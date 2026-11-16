--!strict
-- Blocky pet models, in the same voxel style as the eggs. Each pet is built from limbs (Body, Head, legs, wings,
-- tail...) and each limb from blocks. A limb turns around its pivot, so the same few skeletons can share walk,
-- hop and flap animations (see SKELETONS). The output is plain data with no Roblox objects, so the tests and the
-- gallery (tools/egg-gallery.luau) can load it outside Studio; Shared/PetRig turns it into a rigged Model.
--
-- Designs are drawn in voxels, facing +z, standing on y = 0:
--     x  left (+x) and right (-x) of the pet; a cell numbered x covers x to x + 1
--     y  up from the ground
--     z  forward
-- PetRig turns the pet round to face -Z, the way Roblox models face.

local Designs = require(script.Designs)
local Rarities = require(script.Parent.Config.Rarities)
local Zones = require(script.Parent.Config.Zones)

export type Color = { number }

export type Box = {
	-- Centre and size in voxels.
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: Color,
	material: string,
	transparency: number,
	-- "Block" (the default), "Wedge" (a Roblox wedge: full height at its back, +z, sloping down to an edge at its
	-- front, -z, along its bottom) or "Ball" (an egg shape filling the box).
	shape: string?,
	-- For a part turned at an angle: the directions of its own x, y and z axes, as the columns of a 3x3 matrix
	-- written row by row. Nil for a block lined up with the grid.
	rotation: { number }?,
}

-- A flame burning at a point on a limb (a Roblox Fire), in voxels.
export type Fire = { limb: string, position: { number }, size: number, color: Color, secondary: Color }

export type Limb = {
	name: string,
	-- The limb this one hangs from (nil for Body, which hangs from the pet's root).
	parent: string?,
	-- The point it turns around, in voxels.
	pivot: { number },
	boxes: { Box },
}

export type Light = { color: Color, brightness: number, range: number }
export type Particles = { color: Color, style: string, rate: number }

export type Model = {
	kind: string,
	name: string,
	-- The zone and rarity of the egg it hatches from (zone 0 if no egg hatches it yet).
	zone: number,
	rarity: string,
	skeleton: string,
	-- How it moves: "Walk", "Hop", "Waddle", "Stomp", "Swim" or "Crawl".
	gait: string,
	-- How high it floats above the ground, in voxels (0 for pets that stand on it). Designs are drawn standing
	-- on y = 0; a floating pet is raised by this much when placed.
	hover: number,
	-- Studs per voxel.
	scale: number,
	-- For winged pets: how far each wing turns out to be spread for flight (see PetAnimations).
	wingSpread: number,
	limbs: { Limb },
	-- Where a rider sits, in voxels.
	seat: { number },
	-- The size of the whole pet in voxels, and the centre of that box.
	size: { number },
	center: { number },
	light: Light?,
	particles: Particles?,
	fires: { Fire },
	-- Blocks not joined to the rest of the pet, which would float in the air. Should always be 0.
	loose: number,
	-- Pairs of differently coloured blocks with faces in the same place, which flicker in Roblox. Should be 0.
	flicker: number,
	-- Where the first few of those are, to help fix them.
	flickerAt: { string },
}

local PetModels = {}

-- Studs per voxel unless a design says otherwise. Eggs use about the same.
PetModels.VOXEL = 0.5

-- The limbs each skeleton must have. Animations are written per skeleton, so every pet that shares one moves
-- the same way. Every limb except Body hangs from Body unless a design says otherwise.
PetModels.SKELETONS = {
	Quadruped = { "Body", "Head", "FrontLeftLeg", "FrontRightLeg", "BackLeftLeg", "BackRightLeg", "Tail" },
	-- Short legs and a long body close to the ground (hedgehogs, lizards).
	LowSlung = { "Body", "Head", "FrontLeftLeg", "FrontRightLeg", "BackLeftLeg", "BackRightLeg", "Tail" },
	Winged = { "Body", "Head", "LeftWing", "RightWing", "LeftLeg", "RightLeg", "Tail" },
	Biped = { "Body", "Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg" },
	-- Two legs, small arms and a long tail (raptors, tyrannosaurs).
	Theropod = { "Body", "Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Tail" },
	-- Floats and swims: fins (or wings, or forelegs) and a tail.
	Swimmer = { "Body", "Head", "LeftFin", "RightFin", "Tail" },
	-- Eight tentacles round a body, with the head (mantle) on top.
	Tentacled = {
		"Body",
		"Head",
		"Tentacle1",
		"Tentacle2",
		"Tentacle3",
		"Tentacle4",
		"Tentacle5",
		"Tentacle6",
		"Tentacle7",
		"Tentacle8",
	},
	-- A long body in a chain of coils (Segment1 hangs from Body, Segment2 from Segment1, Tail from Segment2), so
	-- a ripple can run down it.
	Serpent = { "Body", "Head", "LeftFin", "RightFin", "Segment1", "Segment2", "Tail" },
	-- Four legs and a pair of wings (dragons).
	Dragon = {
		"Body",
		"Head",
		"FrontLeftLeg",
		"FrontRightLeg",
		"BackLeftLeg",
		"BackRightLeg",
		"LeftWing",
		"RightWing",
		"Tail",
	},
	-- Six legs (scorpions, beetles, crabs). Claws are part of the Head.
	ManyLegged = {
		"Body",
		"Head",
		"FrontLeftLeg",
		"FrontRightLeg",
		"MiddleLeftLeg",
		"MiddleRightLeg",
		"BackLeftLeg",
		"BackRightLeg",
		"Tail",
	},
} :: { [string]: { string } }

local DEFAULT_MATERIAL = "SmoothPlastic"

-- Paint sits a hair outside the blocks it covers so it always draws on top. Paint over earlier paint on the same
-- limb (an eye on a cheek patch) sits a step further out, and paint right beside earlier paint sits at a different
-- depth from it, so no two paints ever share a surface and flicker.
local PAINT_BASE = 0.03
local PAINT_STEP = 0.02
local PAINT_MAX = 0.15

type Range = { number } -- { x0, y0, z0, x1, y1, z1 }, inclusive cell numbers

type LimbBuild = {
	name: string,
	parent: string?,
	pivot: { number },
	boxes: { Box },
	-- The cells each box covers (for a part at an angle, the cells round it).
	ranges: { Range },
	-- Each paint so far and how many steps out it sits.
	paints: { { range: Range, layer: number } },
	fires: { Fire },
}

----------------------------------------------------------------------------------------------------------------
-- The builder a design draws with

local LimbBuilder = {}
LimbBuilder.__index = LimbBuilder

export type LimbBuilder = typeof(setmetatable({} :: { build: LimbBuild }, LimbBuilder))

local function sorted(a: number, b: number): (number, number)
	if a <= b then
		return a, b
	end
	return b, a
end

local function addBox(
	build: LimbBuild,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	color: Color,
	material: string?,
	transparency: number?,
	pad: number
)
	x0, x1 = sorted(x0, x1)
	y0, y1 = sorted(y0, y1)
	z0, z1 = sorted(z0, z1)
	table.insert(build.boxes, {
		x = (x0 + x1 + 1) / 2,
		y = (y0 + y1 + 1) / 2,
		z = (z0 + z1 + 1) / 2,
		sx = x1 - x0 + 1 + pad * 2,
		sy = y1 - y0 + 1 + pad * 2,
		sz = z1 - z0 + 1 + pad * 2,
		color = color,
		material = material or DEFAULT_MATERIAL,
		transparency = transparency or 0,
	})
	table.insert(build.ranges, { x0, y0, z0, x1, y1, z1 })
end

-- A solid block covering cells x0..x1, y0..y1, z0..z1 (corners inclusive, in any order).
function LimbBuilder.box(
	self: LimbBuilder,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	color: Color,
	material: string?,
	transparency: number?
)
	addBox(self.build, x0, y0, z0, x1, y1, z1, color, material, transparency, 0)
end

-- Colour on the surface of blocks drawn before (eyes, noses, bellies): drawn a hair larger so it shows on top.
function LimbBuilder.paint(
	self: LimbBuilder,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	color: Color,
	material: string?
)
	x0, x1 = sorted(x0, x1)
	y0, y1 = sorted(y0, y1)
	z0, z1 = sorted(z0, z1)
	-- Out past every paint it covers, and not at the depth of any paint it touches.
	local above, beside = 0, {}
	for _, earlier in self.build.paints do
		local r = earlier.range
		local overlaps, touches = true, true
		for axis, low in { x0, y0, z0 } do
			local high = ({ x1, y1, z1 })[axis]
			if r[axis] > high or r[axis + 3] < low then
				overlaps = false
			end
			if r[axis] > high + 1 or r[axis + 3] < low - 1 then
				touches = false
			end
		end
		if overlaps then
			above = math.max(above, earlier.layer + 1)
		elseif touches then
			beside[earlier.layer] = true
		end
	end
	local layer = above
	while beside[layer] do
		layer += 1
	end
	table.insert(self.build.paints, { range = { x0, y0, z0, x1, y1, z1 }, layer = layer })
	local pad = math.min(PAINT_MAX, PAINT_BASE + PAINT_STEP * layer)
	addBox(self.build, x0, y0, z0, x1, y1, z1, color, material, 0, pad)
end

-- box and paint, plus a mirror copy on the other side of the pet (across x).
function LimbBuilder.boxPair(
	self: LimbBuilder,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	color: Color,
	material: string?,
	transparency: number?
)
	self:box(x0, y0, z0, x1, y1, z1, color, material, transparency)
	self:box(-1 - x0, y0, z0, -1 - x1, y1, z1, color, material, transparency)
end

function LimbBuilder.paintPair(
	self: LimbBuilder,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	color: Color,
	material: string?
)
	self:paint(x0, y0, z0, x1, y1, z1, color, material)
	self:paint(-1 - x0, y0, z0, -1 - x1, y1, z1, color, material)
end

-- The box round a part at an angle: from its centre, how far it reaches along each axis.
local function reach(size: { number }, rotation: { number }, round: boolean): { number }
	local out = {}
	for i = 0, 2 do
		local total = 0
		for j = 0, 2 do
			local r = rotation[i * 3 + j + 1] * size[j + 1] / 2
			total += if round then r * r else math.abs(r)
		end
		out[i + 1] = if round then math.sqrt(total) else total
	end
	return out
end

local function addPart(build: LimbBuild, box: Box)
	table.insert(build.boxes, box)
	local around = reach({ box.sx, box.sy, box.sz }, box.rotation or { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, box.shape == "Ball")
	local centre = { box.x, box.y, box.z }
	local range = {}
	for axis = 1, 3 do
		range[axis] = centre[axis] - around[axis]
		range[axis + 3] = centre[axis] + around[axis] - 1
	end
	table.insert(build.ranges, range)
end

-- A part of any shape, turned to any angle: `axes` are the directions its own x, y and z point in (at right angles
-- to each other, each of length 1), `size` its size along them, all in voxels. See Box for the shapes.
function LimbBuilder.part(
	self: LimbBuilder,
	center: { number },
	size: { number },
	axes: { { number } },
	color: Color,
	material: string?,
	transparency: number?,
	shape: string?
)
	local rotation = {}
	for i = 1, 3 do
		for j = 1, 3 do
			rotation[(i - 1) * 3 + j] = axes[j][i]
		end
	end
	addPart(self.build, {
		x = center[1],
		y = center[2],
		z = center[3],
		sx = size[1],
		sy = size[2],
		sz = size[3],
		color = color,
		material = material or DEFAULT_MATERIAL,
		transparency = transparency or 0,
		shape = shape or "Block",
		rotation = rotation,
	})
end

-- A flame burning at a point on the limb, in voxels, `size` voxels tall, shading from `color` to `secondary`.
function LimbBuilder.fire(self: LimbBuilder, position: { number }, size: number, color: Color, secondary: Color)
	table.insert(
		self.build.fires,
		{ limb = self.build.name, position = position, size = size, color = color, secondary = secondary }
	)
end

local PetBuilder = {}
PetBuilder.__index = PetBuilder

export type PetBuilder = typeof(setmetatable(
	{} :: {
		limbs: { LimbBuild },
		byName: { [string]: LimbBuild },
		seatPoint: { number }?,
		lightInfo: Light?,
		particleInfo: Particles?,
	},
	PetBuilder
))

local function newPet(): PetBuilder
	return setmetatable({ limbs = {}, byName = {}, seatPoint = nil, lightInfo = nil, particleInfo = nil }, PetBuilder)
end

-- Starts a limb that turns around `pivot` (x, y, z in voxels; halves are fine). `parent` defaults to Body.
function PetBuilder.limb(self: PetBuilder, name: string, pivot: { number }, parent: string?): LimbBuilder
	assert(self.byName[name] == nil, "limb drawn twice: " .. name)
	local build: LimbBuild = {
		name = name,
		parent = if name == "Body" then nil else (parent or "Body"),
		pivot = pivot,
		boxes = {},
		ranges = {},
		paints = {},
		fires = {},
	}
	table.insert(self.limbs, build)
	self.byName[name] = build
	return setmetatable({ build = build }, LimbBuilder)
end

-- Draws a left limb with `draw`, then its mirror image as the right limb. The pivot is the left one's.
function PetBuilder.limbPair(
	self: PetBuilder,
	leftName: string,
	rightName: string,
	pivot: { number },
	draw: (LimbBuilder) -> (),
	parent: string?
)
	local left = self:limb(leftName, pivot, parent)
	draw(left)
	local right = self:limb(rightName, { -pivot[1], pivot[2], pivot[3] }, parent)
	-- Replay the left limb's blocks mirrored, keeping paint on top of blocks. A part at an angle is mirrored by
	-- turning it the mirror-image way round; every shape is symmetrical across its own x, so it looks the same.
	for index, range in left.build.ranges do
		local box = left.build.boxes[index]
		if box.rotation then
			local r = box.rotation
			local copy = table.clone(box)
			copy.x = -box.x
			copy.rotation = { r[1], -r[2], -r[3], -r[4], r[5], r[6], -r[7], r[8], r[9] }
			addPart(right.build, copy)
			continue
		end
		local pad = (box.sx - (range[4] - range[1] + 1)) / 2
		addBox(
			right.build,
			-1 - range[1],
			range[2],
			range[3],
			-1 - range[4],
			range[5],
			range[6],
			box.color,
			box.material,
			box.transparency,
			pad
		)
	end
	for _, paint in left.build.paints do
		local r = paint.range
		table.insert(
			right.build.paints,
			{ range = { -1 - r[4], r[2], r[3], -1 - r[1], r[5], r[6] }, layer = paint.layer }
		)
	end
	for _, fire in left.build.fires do
		local p = fire.position
		table.insert(right.build.fires, {
			limb = rightName,
			position = { -p[1], p[2], p[3] },
			size = fire.size,
			color = fire.color,
			secondary = fire.secondary,
		})
	end
end

-- Where a rider sits on the pet's back, in voxels.
function PetBuilder.seat(self: PetBuilder, x: number, y: number, z: number)
	self.seatPoint = { x, y, z }
end

function PetBuilder.light(self: PetBuilder, color: Color, brightness: number?, range: number?)
	self.lightInfo = { color = color, brightness = brightness or 1.5, range = range or 12 }
end

function PetBuilder.particles(self: PetBuilder, style: string, color: Color, rate: number?)
	self.particleInfo = { style = style, color = color, rate = rate or 6 }
end

----------------------------------------------------------------------------------------------------------------
-- Checks

-- Whether two blocks are joined: they overlap, share a face, or share an edge. Corners alone do not count.
local function joined(a: Range, b: Range): boolean
	local touching = 0
	for axis = 1, 3 do
		local low = math.max(a[axis], b[axis])
		local high = math.min(a[axis + 3], b[axis + 3]) + 1
		if high < low then
			return false
		elseif high == low then
			touching += 1
		end
	end
	return touching <= 2
end

-- Pairs of solid blocks of different looks whose faces lie on the same plane, facing the same way, and overlap.
-- Roblox cannot tell which to draw in front, so they flicker. Paint never counts: it always sits on top.
local function countFlicker(pet: PetBuilder): (number, { string })
	local solids: { { range: Range, look: string, limb: string } } = {}
	for _, limb in pet.limbs do
		for index, range in limb.ranges do
			local box = limb.boxes[index]
			-- Parts at an angle are left to the design to keep apart.
			if box.rotation == nil and box.sx == range[4] - range[1] + 1 then
				local look = `{box.color[1]},{box.color[2]},{box.color[3]},{box.material},{box.transparency}`
				table.insert(solids, { range = range, look = look, limb = limb.name })
			end
		end
	end
	local count = 0
	local where = {}
	for i = 1, #solids do
		for j = i + 1, #solids do
			local a, b = solids[i], solids[j]
			if a.look == b.look then
				continue
			end
			local clash = false
			for axis = 1, 3 do
				local other1, other2 = axis % 3 + 1, (axis + 1) % 3 + 1
				local function overlaps(o: number): boolean
					return math.max(a.range[o], b.range[o]) < math.min(a.range[o + 3], b.range[o + 3]) + 1
				end
				if overlaps(other1) and overlaps(other2) then
					if a.range[axis] == b.range[axis] or a.range[axis + 3] == b.range[axis + 3] then
						clash = true
					end
				end
			end
			if clash then
				count += 1
				if #where < 5 then
					table.insert(
						where,
						`{a.limb} {table.concat(a.range, ",")} and {b.limb} {table.concat(b.range, ",")}`
					)
				end
			end
		end
	end
	return count, where
end

-- Blocks not joined, through other blocks, to the first block of the Body.
local function countLoose(pet: PetBuilder): number
	local all: { Range } = {}
	for _, limb in pet.limbs do
		for _, range in limb.ranges do
			table.insert(all, range)
		end
	end
	local body = pet.byName.Body
	if body == nil or #body.ranges == 0 then
		return #all
	end
	local start = table.find(all, body.ranges[1]) :: number
	local reached = { [start] = true }
	local queue = { start }
	local head = 1
	while head <= #queue do
		local current = all[queue[head]]
		head += 1
		for index, other in all do
			if not reached[index] and joined(current, other) then
				reached[index] = true
				table.insert(queue, index)
			end
		end
	end
	local loose = 0
	for index in all do
		if not reached[index] then
			loose += 1
		end
	end
	return loose
end

----------------------------------------------------------------------------------------------------------------
-- Public

-- Which egg each pet hatches from: kind -> { zone, rarity }.
local function hatchPlaces(): { [string]: { zone: number, rarity: string } }
	local map = {}
	for zoneId, zone in Zones.List do
		for _, entry in zone.eggs do
			map[entry.pet] = { zone = zoneId, rarity = entry.rarity }
		end
	end
	return map
end

-- Secret's rarity colour is nearly black, which would make a dark light and invisible sparkles.
local SECRET_GLOW: Color = { 226, 214, 255 }

local cache: { [string]: Model } = {}

-- The model for a pet (a design name such as "MossStag"), or nil if that pet has no model yet.
function PetModels.get(kind: string): Model?
	local cached = cache[kind]
	if cached then
		return cached
	end
	local design = Designs[kind]
	if design == nil then
		return nil
	end
	local place = hatchPlaces()[kind]
	local rarity = if place then place.rarity else "Common"

	local pet = newPet()
	design.draw(pet)

	local info = Rarities.Info[rarity]
	local glow = if rarity == "Secret" then SECRET_GLOW else info.color
	if info.order >= 5 and pet.lightInfo == nil then
		pet:light(glow, 1 + (info.order - 5) * 0.4, 10 + (info.order - 5) * 2)
	end
	if info.order >= 6 and pet.particleInfo == nil then
		pet:particles("Sparkles", glow, 4 + (info.order - 6) * 3)
	end

	local low = { math.huge, math.huge, math.huge }
	local high = { -math.huge, -math.huge, -math.huge }
	local limbs: { Limb } = {}
	local fires: { Fire } = {}
	for _, build in pet.limbs do
		for _, fire in build.fires do
			table.insert(fires, fire)
		end
		for _, range in build.ranges do
			for axis = 1, 3 do
				low[axis] = math.min(low[axis], range[axis])
				high[axis] = math.max(high[axis], range[axis + 3] + 1)
			end
		end
		table.insert(limbs, { name = build.name, parent = build.parent, pivot = build.pivot, boxes = build.boxes })
	end

	local model: Model = {
		kind = kind,
		name = design.name,
		zone = if place then place.zone else 0,
		rarity = rarity,
		skeleton = design.skeleton,
		gait = design.gait or "Walk",
		hover = design.hover or 0,
		scale = design.scale or PetModels.VOXEL,
		wingSpread = design.wingSpread or 0,
		limbs = limbs,
		seat = pet.seatPoint or { 0, high[2], 0 },
		size = { high[1] - low[1], high[2] - low[2], high[3] - low[3] },
		center = { (high[1] + low[1]) / 2, (high[2] + low[2]) / 2, (high[3] + low[3]) / 2 },
		light = pet.lightInfo,
		particles = pet.particleInfo,
		fires = fires,
		loose = countLoose(pet),
		flicker = 0,
		flickerAt = {},
	}
	model.flicker, model.flickerAt = countFlicker(pet)
	cache[kind] = model
	return model
end

-- The lowest and highest point a box reaches along each axis, in voxels, allowing for its angle and shape.
function PetModels.extent(box: Box): ({ number }, { number })
	local around = if box.rotation
		then reach({ box.sx, box.sy, box.sz }, box.rotation, box.shape == "Ball")
		else { box.sx / 2, box.sy / 2, box.sz / 2 }
	local centre = { box.x, box.y, box.z }
	local low, high = {}, {}
	for axis = 1, 3 do
		low[axis] = centre[axis] - around[axis]
		high[axis] = centre[axis] + around[axis]
	end
	return low, high
end

-- Every pet that has a model, in the order their eggs appear in the zones.
function PetModels.all(): { string }
	local list = {}
	for _, zone in Zones.List do
		for _, entry in zone.eggs do
			if Designs[entry.pet] then
				table.insert(list, entry.pet)
			end
		end
	end
	return list
end

-- A pet's name for people (e.g. "Moss Stag" for "MossStag"), without building its model, or nil if it has no
-- design.
function PetModels.describe(kind: string): { name: string }?
	local design = Designs[kind]
	if design == nil then
		return nil
	end
	return { name = design.name }
end

-- The pet that hatches from an egg (its design name), or nil.
function PetModels.fromEgg(eggKind: string): string?
	for _, zone in Zones.List do
		for _, entry in zone.eggs do
			if entry.egg == eggKind then
				return entry.pet
			end
		end
	end
	return nil
end

return PetModels
