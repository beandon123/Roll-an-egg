--!strict
-- Blocky egg models. Every egg has its own design (see Designs), all built on the same voxel grid:
-- a stack of square-cornered layers for the shell, painted cells for patterns, and extra cells for ears, horns,
-- fins and so on. Plain Commons up to eggs that look like the pet inside.
--
-- The output is a list of boxes measured in voxels, with no Roblox objects, so the test runner and the egg
-- gallery (tools/egg-gallery.luau) can load it outside Studio. EggController turns the boxes into parts.
--
-- Designs are built standing up, the way you would draw an egg:
--     y (layer) 1..16, from the round bottom (1) to the pointed top (16)
--     x and z   -6..5 across the widest layer (a cell numbered x covers x to x + 1)
-- On the runway the egg lies on its side, with the pointed top facing along +X.

local Designs = require(script.Designs)
local Rarities = require(script.Parent.Config.Rarities)
local Zones = require(script.Parent.Config.Zones)

export type Color = { number }

export type Box = {
	-- Centre and size in voxels, in the standing-up frame (y is the egg's long axis, 0 at the middle).
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: Color,
	material: string,
	transparency: number,
}

export type Light = { color: Color, brightness: number, range: number }

export type Particles = {
	color: Color,
	-- "Sparkles" (rarity shine), "Embers" (rising sparks), "Bubbles", "Snow", "Leaves".
	style: string,
	rate: number,
}

export type Model = {
	-- The design's name in Designs, e.g. "MossStag". Also what saved data and remotes call the egg.
	kind: string,
	-- The zone it drops in, and its rarity there. A shelved egg has zone 0 and the rarity it last had.
	zone: number,
	rarity: string,
	shelved: boolean,
	name: string,
	-- Which pet hatches from it.
	hatches: string,
	boxes: { Box },
	light: Light?,
	particles: Particles?,
	-- Decoration cells that do not touch the egg, which would float in the air. Should always be 0.
	loose: number,
}

export type Cell = {
	x: number,
	y: number,
	z: number,
	-- Degrees around the egg's long axis, 0 to 360, measured from +x towards +z.
	angle: number,
	-- 0 at the bottom layer, 1 at the top layer.
	height: number,
	-- Which way this cell faces out of the shell: "side", "top" or "bottom".
	facing: string,
}

local EggModels = {}

-- Half the width of the widest layer, in voxels. A rolling egg's radius is this many voxels.
EggModels.RADIUS = 6
EggModels.LAYERS = 16

local R = EggModels.RADIUS
local LAYERS = EggModels.LAYERS

-- Cross-sections by width: centred rectangles { half width in x, half width in z }. Overlapping rectangles give
-- the stepped, rounded-square layers of a voxel egg.
local DISCS: { [number]: { { number } } } = {
	[2] = { { 1, 1 } },
	[4] = { { 2, 1 }, { 1, 2 } },
	[6] = { { 3, 2 }, { 2, 3 } },
	[8] = { { 4, 2 }, { 3, 3 }, { 2, 4 } },
	[10] = { { 5, 2 }, { 4, 4 }, { 2, 5 } },
	[12] = { { 6, 3 }, { 5, 5 }, { 3, 6 } },
}

-- Layer widths from bottom to top.
local PROFILES: { [string]: { number } } = {
	Classic = { 6, 8, 10, 12, 12, 12, 12, 12, 12, 10, 10, 10, 8, 8, 6, 4 },
	-- Fuller towards the top: for big, bulky pets.
	Round = { 6, 8, 10, 12, 12, 12, 12, 12, 12, 12, 10, 10, 10, 8, 6, 4 },
	-- A long point: for dragons and other sleek pets.
	Pointy = { 6, 8, 10, 12, 12, 12, 12, 12, 10, 10, 10, 8, 8, 6, 4, 2 },
}
EggModels.Profiles = PROFILES

local DEFAULT_MATERIAL = "SmoothPlastic"

-- Painted cells and decorations sit a hair outside the shell so they always draw on top of it. Each later colour
-- sits a little further out than the one before, so two touching colours never flicker.
local OVERLAY_BASE = 0.03
local OVERLAY_STEP = 0.006
local OVERLAY_MAX = 0.09

local function cellKey(x: number, y: number, z: number): number
	return (x + 128) + (y + 128) * 256 + (z + 128) * 65536
end

----------------------------------------------------------------------------------------------------------------
-- The builder a design draws with

local Egg = {}
Egg.__index = Egg

export type Egg = typeof(setmetatable(
	{} :: {
		widths: { number },
		layerColor: { Color },
		layerMaterial: { string },
		layerTransparency: { number },
		cells: { [number]: { x: number, y: number, z: number, look: number } },
		looks: { { color: Color, material: string, transparency: number } },
		lookIndex: { [string]: number },
		surfaceCache: { Cell }?,
		lightInfo: Light?,
		particleInfo: Particles?,
		seed: number,
	},
	Egg
))

local function newEgg(profile: string, seed: number): Egg
	local widths = PROFILES[profile]
	assert(widths, "unknown egg profile " .. profile)
	local self = setmetatable({
		widths = widths,
		layerColor = {},
		layerMaterial = {},
		layerTransparency = {},
		cells = {},
		looks = {},
		lookIndex = {},
		surfaceCache = nil,
		lightInfo = nil,
		particleInfo = nil,
		seed = seed,
	}, Egg)
	for layer = 1, LAYERS do
		self.layerColor[layer] = { 255, 255, 255 }
		self.layerMaterial[layer] = DEFAULT_MATERIAL
		self.layerTransparency[layer] = 0
	end
	return self
end

-- Half the width of a layer in voxels (0 above or below the egg).
function Egg.halfWidth(self: Egg, layer: number): number
	local width = self.widths[layer]
	return if width then width / 2 else 0
end

-- Whether a cell is part of the shell.
function Egg.inside(self: Egg, x: number, y: number, z: number): boolean
	local width = self.widths[y]
	if width == nil then
		return false
	end
	for _, rect in DISCS[width] do
		local hx, hz = rect[1], rect[2]
		if x >= -hx and x < hx and z >= -hz and z < hz then
			return true
		end
	end
	return false
end

-- Whether a shell cell can be seen from outside.
function Egg.isSurface(self: Egg, x: number, y: number, z: number): boolean
	if not self:inside(x, y, z) then
		return false
	end
	return not (
		self:inside(x + 1, y, z)
		and self:inside(x - 1, y, z)
		and self:inside(x, y, z + 1)
		and self:inside(x, y, z - 1)
		and self:inside(x, y + 1, z)
		and self:inside(x, y - 1, z)
	)
end

-- Every visible shell cell, bottom to top.
function Egg.surface(self: Egg): { Cell }
	if self.surfaceCache then
		return self.surfaceCache
	end
	local list: { Cell } = {}
	for y = 1, LAYERS do
		for z = -R, R - 1 do
			for x = -R, R - 1 do
				if self:isSurface(x, y, z) then
					local facing = "side"
					local sideways = not (
						self:inside(x + 1, y, z)
						and self:inside(x - 1, y, z)
						and self:inside(x, y, z + 1)
						and self:inside(x, y, z - 1)
					)
					if not sideways then
						facing = if self:inside(x, y + 1, z) then "bottom" else "top"
					end
					local angle = math.deg(math.atan2(z + 0.5, x + 0.5)) % 360
					table.insert(list, {
						x = x,
						y = y,
						z = z,
						angle = angle,
						height = (y - 1) / (LAYERS - 1),
						facing = facing,
					})
				end
			end
		end
	end
	self.surfaceCache = list
	return list
end

-- A steady pseudo-random number in [0, 1) for a cell, so speckles and fur look the same every time.
function Egg.noise(self: Egg, x: number, y: number, z: number, salt: number?): number
	local prime = 2147483647
	local h = ((x + 300) * 73 + (y + 300) * 9973 + (z + 300) * 1000003 + (salt or 0) * 7919 + self.seed * 104729)
		% prime
	for _ = 1, 3 do
		h = (h * 16807) % prime
		h = bit32.bxor(h, bit32.rshift(h, 11))
	end
	return (h % prime) / prime
end

-- Colours the whole shell.
function Egg.base(self: Egg, color: Color, material: string?, transparency: number?)
	self:band(1, LAYERS, color, material, transparency)
end

-- Colours whole layers of the shell, from `first` to `last` (1 is the bottom).
function Egg.band(self: Egg, first: number, last: number, color: Color, material: string?, transparency: number?)
	for layer = math.max(1, first), math.min(LAYERS, last) do
		self.layerColor[layer] = color
		self.layerMaterial[layer] = material or DEFAULT_MATERIAL
		self.layerTransparency[layer] = transparency or 0
	end
end

local function lookId(self: Egg, color: Color, material: string?, transparency: number?): number
	local mat = material or DEFAULT_MATERIAL
	local tr = transparency or 0
	local key = `{color[1]},{color[2]},{color[3]}|{mat}|{tr}`
	local id = self.lookIndex[key]
	if id == nil then
		table.insert(self.looks, { color = color, material = mat, transparency = tr })
		id = #self.looks
		self.lookIndex[key] = id
	end
	return id
end

-- Sets one cell: paint on the shell, or a decoration outside it.
function Egg.set(self: Egg, x: number, y: number, z: number, color: Color, material: string?, transparency: number?)
	self.cells[cellKey(x, y, z)] = { x = x, y = y, z = z, look = lookId(self, color, material, transparency) }
end

-- Clears a cell set earlier.
function Egg.clear(self: Egg, x: number, y: number, z: number)
	self.cells[cellKey(x, y, z)] = nil
end

-- Sets every cell in a block (corners inclusive, in any order).
function Egg.fill(
	self: Egg,
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
	for y = math.min(y0, y1), math.max(y0, y1) do
		for z = math.min(z0, z1), math.max(z0, z1) do
			for x = math.min(x0, x1), math.max(x0, x1) do
				self:set(x, y, z, color, material, transparency)
			end
		end
	end
end

-- Like fill, plus a mirror copy on the other side of the egg (across x).
function Egg.pair(
	self: Egg,
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
	self:fill(x0, y0, z0, x1, y1, z1, color, material, transparency)
	self:fill(-1 - x0, y0, z0, -1 - x1, y1, z1, color, material, transparency)
end

-- Paints shell cells chosen by a function: it gets each visible cell and returns a colour (or nil to skip),
-- and optionally a material and transparency.
function Egg.paint(self: Egg, choose: (Cell) -> (Color?, string?, number?))
	for _, cell in self:surface() do
		local color, material, transparency = choose(cell)
		if color then
			self:set(cell.x, cell.y, cell.z, color, material, transparency)
		end
	end
end

-- Paints a round spot centred on the shell at a layer and an angle (degrees), `size` voxels across.
function Egg.spot(self: Egg, layer: number, angle: number, size: number, color: Color, material: string?)
	local half = self:halfWidth(math.clamp(math.round(layer), 1, LAYERS))
	local radians = math.rad(angle)
	local cx, cz = math.cos(radians) * half, math.sin(radians) * half
	local cy = layer - 0.5
	local reach = size / 2
	self:paint(function(cell)
		local dx, dy, dz = cell.x + 0.5 - cx, cell.y - 0.5 - cy, cell.z + 0.5 - cz
		if dx * dx + dy * dy + dz * dz <= reach * reach then
			return color, material
		end
		return nil
	end)
end

-- Adds a cell on the outside of the shell at a layer and angle, `out` cells beyond the surface (0 = touching).
-- Returns the cell's x and z.
function Egg.outward(self: Egg, layer: number, angle: number, out: number): (number, number)
	local radians = math.rad(angle)
	local dx, dz = math.cos(radians), math.sin(radians)
	-- Walk out from the middle until we leave the shell.
	local step = 0
	local x, z = 0, 0
	repeat
		step += 0.25
		x = math.floor(dx * step)
		z = math.floor(dz * step)
	until not self:inside(x, layer, z) or step > R * 2
	return math.floor(dx * (step + out)), math.floor(dz * (step + out))
end

-- A light that shines from the egg.
function Egg.light(self: Egg, color: Color, brightness: number?, range: number?)
	self.lightInfo = { color = color, brightness = brightness or 1.5, range = range or 12 }
end

-- Particles around the egg.
function Egg.particles(self: Egg, style: string, color: Color, rate: number?)
	self.particleInfo = { style = style, color = color, rate = rate or 6 }
end

----------------------------------------------------------------------------------------------------------------
-- Turning a finished design into boxes

local function shellBoxes(self: Egg, boxes: { Box })
	-- One box per rectangle, stretched over every layer in a row that has the same rectangle and colour.
	local done: { [string]: boolean } = {}
	for layer = 1, LAYERS do
		for _, rect in DISCS[self.widths[layer]] do
			local id = `{layer}:{rect[1]}:{rect[2]}`
			if done[id] then
				continue
			end
			local last = layer
			while last < LAYERS do
				local nextLayer = last + 1
				local same = self.layerColor[nextLayer] == self.layerColor[layer]
					and self.layerMaterial[nextLayer] == self.layerMaterial[layer]
					and self.layerTransparency[nextLayer] == self.layerTransparency[layer]
				local hasRect = false
				for _, other in DISCS[self.widths[nextLayer]] do
					if other[1] == rect[1] and other[2] == rect[2] then
						hasRect = true
					end
				end
				if not (same and hasRect) then
					break
				end
				last = nextLayer
				done[`{last}:{rect[1]}:{rect[2]}`] = true
			end
			table.insert(boxes, {
				x = 0,
				y = (layer - 1 + last) / 2 - LAYERS / 2,
				z = 0,
				sx = rect[1] * 2,
				sy = last - layer + 1,
				sz = rect[2] * 2,
				color = self.layerColor[layer],
				material = self.layerMaterial[layer],
				transparency = self.layerTransparency[layer],
			})
		end
	end
end

-- Joins painted and decoration cells of the same look into as few boxes as it can. Hidden cells inside the shell
-- may be swallowed by a box, which lets a patch on a curved part of the shell become one box instead of many.
local function cellBoxes(self: Egg, boxes: { Box })
	local byLook: { { { x: number, y: number, z: number } } } = {}
	for _, cell in self.cells do
		if self:inside(cell.x, cell.y, cell.z) and not self:isSurface(cell.x, cell.y, cell.z) then
			-- Paint on a hidden cell would never be seen.
			continue
		end
		local list = byLook[cell.look]
		if list == nil then
			list = {}
			byLook[cell.look] = list
		end
		table.insert(list, cell)
	end

	for look, list in byLook do
		table.sort(list, function(a, b)
			if a.y ~= b.y then
				return a.y < b.y
			elseif a.z ~= b.z then
				return a.z < b.z
			end
			return a.x < b.x
		end)

		local mine: { [number]: boolean } = {}
		for _, cell in list do
			mine[cellKey(cell.x, cell.y, cell.z)] = true
		end
		local used: { [number]: boolean } = {}

		-- Whether a cell may be inside a box of this look, and whether it is one of this look's own cells.
		local function allowed(x: number, y: number, z: number): (boolean, boolean)
			local key = cellKey(x, y, z)
			if mine[key] then
				return true, not used[key]
			end
			if self:inside(x, y, z) and not self:isSurface(x, y, z) then
				return true, false
			end
			return false, false
		end

		-- Whether a block of cells may all be in the box, and whether it adds any new cell of this look.
		local function slab(x0: number, x1: number, y0: number, y1: number, z0: number, z1: number): (boolean, boolean)
			local any = false
			for y = y0, y1 do
				for z = z0, z1 do
					for x = x0, x1 do
						local ok, new = allowed(x, y, z)
						if not ok then
							return false, false
						end
						any = any or new
					end
				end
			end
			return true, any
		end

		for _, cell in list do
			if used[cellKey(cell.x, cell.y, cell.z)] then
				continue
			end
			local x0, x1, y0, y1, z0, z1 = cell.x, cell.x, cell.y, cell.y, cell.z, cell.z
			while true do
				local ok, new = slab(x1 + 1, x1 + 1, y0, y1, z0, z1)
				if not (ok and new) then
					break
				end
				x1 += 1
			end
			while true do
				local ok, new = slab(x0 - 1, x0 - 1, y0, y1, z0, z1)
				if not (ok and new) then
					break
				end
				x0 -= 1
			end
			while true do
				local ok, new = slab(x0, x1, y0, y1, z1 + 1, z1 + 1)
				if not (ok and new) then
					break
				end
				z1 += 1
			end
			while true do
				local ok, new = slab(x0, x1, y0, y1, z0 - 1, z0 - 1)
				if not (ok and new) then
					break
				end
				z0 -= 1
			end
			while true do
				local ok, new = slab(x0, x1, y1 + 1, y1 + 1, z0, z1)
				if not (ok and new) then
					break
				end
				y1 += 1
			end
			for y = y0, y1 do
				for z = z0, z1 do
					for x = x0, x1 do
						local key = cellKey(x, y, z)
						if mine[key] then
							used[key] = true
						end
					end
				end
			end

			local info = self.looks[look]
			local pad = math.min(OVERLAY_MAX, OVERLAY_BASE + OVERLAY_STEP * (look - 1))
			table.insert(boxes, {
				x = (x0 + x1 + 1) / 2,
				y = (y0 - 1 + y1) / 2 - LAYERS / 2,
				z = (z0 + z1 + 1) / 2,
				sx = x1 - x0 + 1 + pad * 2,
				sy = y1 - y0 + 1 + pad * 2,
				sz = z1 - z0 + 1 + pad * 2,
				color = info.color,
				material = info.material,
				transparency = info.transparency,
			})
		end
	end
end

-- Counts decoration cells that are not joined to the shell, through other decorations, by a face or an edge.
-- Edges count because voxel staircases (curved horns, tusks) only meet at edges and still look joined.
local NEIGHBOURS: { { number } } = {}
for dx = -1, 1 do
	for dy = -1, 1 do
		for dz = -1, 1 do
			local moved = math.abs(dx) + math.abs(dy) + math.abs(dz)
			if moved == 1 or moved == 2 then
				table.insert(NEIGHBOURS, { dx, dy, dz })
			end
		end
	end
end

local function countLoose(self: Egg): number
	local outside: { [number]: { x: number, y: number, z: number } } = {}
	for key, cell in self.cells do
		if not self:inside(cell.x, cell.y, cell.z) then
			outside[key] = cell
		end
	end

	local reached: { [number]: boolean } = {}
	local queue = {}
	for key, cell in outside do
		for _, d in NEIGHBOURS do
			if self:inside(cell.x + d[1], cell.y + d[2], cell.z + d[3]) then
				reached[key] = true
				table.insert(queue, cell)
				break
			end
		end
	end
	local head = 1
	while head <= #queue do
		local cell = queue[head]
		head += 1
		for _, d in NEIGHBOURS do
			local key = cellKey(cell.x + d[1], cell.y + d[2], cell.z + d[3])
			local other = outside[key]
			if other and not reached[key] then
				reached[key] = true
				table.insert(queue, other)
			end
		end
	end

	local loose = 0
	for key in outside do
		if not reached[key] then
			loose += 1
		end
	end
	return loose
end

-- Secret's rarity colour is nearly black, which would make a dark light and invisible sparkles.
local SECRET_GLOW: Color = { 226, 214, 255 }

-- Rarer eggs shine. A design can choose its own light or particles; otherwise these are used.
local function rarityExtras(self: Egg, rarity: string)
	local info = Rarities.Info[rarity]
	local color = if rarity == "Secret" then SECRET_GLOW else info.color
	if info.order >= 5 and self.lightInfo == nil then
		self:light(color, 1 + (info.order - 5) * 0.4, 10 + (info.order - 5) * 2)
	end
	if info.order >= 6 and self.particleInfo == nil then
		self:particles("Sparkles", color, 4 + (info.order - 6) * 3)
	end
end

----------------------------------------------------------------------------------------------------------------
-- Public

export type LineupEgg = { zone: number, rarity: string, kind: string }

-- Where each egg drops: kind -> { zone, rarity }. Built from Config/Zones the first time it is needed.
local placeByKind: { [string]: LineupEgg }? = nil

local function places(): { [string]: LineupEgg }
	if placeByKind == nil then
		local map = {}
		for zoneId, zone in Zones.List do
			for _, entry in zone.eggs do
				map[entry.egg] = { zone = zoneId, rarity = entry.rarity, kind = entry.egg }
			end
		end
		placeByKind = map
	end
	return placeByKind :: { [string]: LineupEgg }
end

-- A string's own steady number, used as the pattern seed for a design that does not set one.
local function hashOf(text: string): number
	local h = 7
	for index = 1, #text do
		h = (h * 31 + string.byte(text, index)) % 1000003
	end
	return h
end

local cache: { [string]: Model } = {}

-- The model for an egg (a design name such as "MossStag"), or nil if there is no such egg.
function EggModels.get(kind: string): Model?
	local cached = cache[kind]
	if cached then
		return cached
	end

	local design = Designs[kind]
	if design == nil then
		return nil
	end
	local place = places()[kind]
	local rarity = if place then place.rarity else design.shelved
	if rarity == nil or Rarities.Info[rarity] == nil then
		return nil
	end

	local egg = newEgg(design.profile or "Classic", design.seed or hashOf(kind))
	design.draw(egg)
	rarityExtras(egg, rarity)

	local boxes: { Box } = {}
	shellBoxes(egg, boxes)
	cellBoxes(egg, boxes)

	local model: Model = {
		kind = kind,
		zone = if place then place.zone else 0,
		rarity = rarity,
		shelved = place == nil,
		name = design.name,
		hatches = design.hatches,
		boxes = boxes,
		light = egg.lightInfo,
		particles = egg.particleInfo,
		loose = countLoose(egg),
	}
	cache[kind] = model
	return model
end

-- An egg's name and pet without building its model, or nil if there is no such egg.
function EggModels.describe(kind: string): { name: string, hatches: string }?
	local design = Designs[kind]
	if design == nil then
		return nil
	end
	return { name = design.name, hatches = design.hatches }
end

-- Every egg that can drop, zone by zone in runway order, each zone's eggs from most common to rarest.
function EggModels.lineup(): { LineupEgg }
	local list = {}
	for zoneId, zone in Zones.List do
		for _, entry in zone.eggs do
			table.insert(list, { zone = zoneId, rarity = entry.rarity, kind = entry.egg })
		end
	end
	return list
end

-- Eggs taken out of the game for now (designed, but in no zone), from most common to rarest.
function EggModels.shelved(): { string }
	local list = {}
	for kind, design in Designs do
		if design.shelved and places()[kind] == nil then
			table.insert(list, kind)
		end
	end
	table.sort(list, function(a, b)
		local ra = Rarities.Info[Designs[a].shelved :: string].order
		local rb = Rarities.Info[Designs[b].shelved :: string].order
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	return list
end

return EggModels
