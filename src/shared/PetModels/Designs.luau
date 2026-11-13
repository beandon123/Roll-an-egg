--!strict
-- The look of every pet, by name. Which egg each pet hatches from is set in Config/Zones (`pet`).
-- Each design draws limbs on the pet builder in PetModels:
--     x left (+x) and right (-x); y up from the ground; z forward. A cell numbered x covers x to x + 1.
--     limb:box() draws a solid block, limb:paint() colours the surface of blocks already drawn (eyes, bellies),
--     and the ...Pair versions mirror across the middle of the pet.
-- Pets have big heads and small bodies, like the eggs they come from, and are themed to match their egg.
-- Every pet in the game has a design, zone by zone: Forest, Desert, Snow, Ocean, Volcano and Prehistoric.
-- Secret and Eternal pets are the showpieces, far more detailed than the rest (the tests check this).
-- Curved parts use the helpers below: `tube` (tentacles, coils, horns), `curl` (a spiral to end a tube on), and
-- `blob` (rounded bodies, filled from a shape function). The finest pets are sculpted (`newSculpt`): modelled cell
-- by cell from rounded shapes turned to any angle, then packed into blocks; or built from parts at any angle
-- (`blade`, `taper`, `egg`, `feather`), with flames (limb:fire).

type Color = { number }
type Pet = any
type Limb = any
type Design = {
	name: string,
	-- One of PetModels.SKELETONS: decides which limbs the pet has and so which animations it uses.
	skeleton: string,
	-- How it moves: "Walk" (default), "Hop", "Waddle", "Stomp", "Swim" or "Crawl".
	gait: string?,
	-- How high it floats, in voxels, for pets that swim through the air.
	hover: number?,
	-- Studs per voxel; bigger pets are drawn with more voxels, small ones get a bigger scale to be rideable.
	scale: number?,
	-- For winged pets: how far (radians) each wing turns out from how it is drawn to be spread for flight.
	wingSpread: number?,
	draw: (Pet) -> (),
}

local function rgb(r: number, g: number, b: number): Color
	return { r, g, b }
end

local NEON = "Neon"
local GLASS = "Glass"
local EYE = rgb(26, 22, 26)
local SHINE = rgb(255, 255, 255)

-- Two eyes on a face whose front cells are at `z`. The left eye covers x..x+width-1 (the right one is mirrored),
-- y..y+tall-1, with a white glint in its top corner nearest the middle.
local function eyes(head: Limb, x: number, y: number, z: number, width: number?, tall: number?)
	local w, t = width or 2, tall or 2
	head:paintPair(x, y, z, x + w - 1, y + t - 1, z, EYE)
	head:paintPair(x, y + t - 1, z, x, y + t - 1, z, SHINE)
end

-- Draws on a limb as if it were on the other side of the pet (x mirrored), for limbs that are mirror images
-- except for something only one side has, like a club in one hand.
local function mirrored(limb: Limb): Limb
	return {
		box = function(_, x0, y0, z0, x1, y1, z1, ...)
			limb:box(-1 - x0, y0, z0, -1 - x1, y1, z1, ...)
		end,
		paint = function(_, x0, y0, z0, x1, y1, z1, ...)
			limb:paint(-1 - x0, y0, z0, -1 - x1, y1, z1, ...)
		end,
	}
end

-- Whether two blocks overlap or share part of a face.
local function touching(a: { number }, b: { number }): boolean
	local faces = 0
	for k = 1, 3 do
		local low, high = math.max(a[k], b[k]), math.min(a[k + 3], b[k + 3]) + 1
		if high < low then
			return false
		elseif high == low then
			faces += 1
		end
	end
	return faces <= 1
end

-- A block one step from `cube` towards `previous`, along the axis they are furthest apart on.
local function between(previous: { number }, cube: { number }): { number }
	local axis, most = 1, 0
	for k = 1, 3 do
		local d = (previous[k] + previous[k + 3]) - (cube[k] + cube[k + 3])
		if math.abs(d) > math.abs(most) then
			axis, most = k, d
		end
	end
	local moved = table.clone(cube)
	local sign = if most > 0 then 1 else -1
	moved[axis] += sign
	moved[axis + 3] += sign
	return moved
end

-- The cells along a path through points { x, y, z, radius } (centres in voxels; halves are fine): one cube per
-- step, { x0, y0, z0, x1, y1, z1 } with cells inclusive, as wide as twice the radius there. With `even`, widths
-- stay even, so a path down the middle of the pet (x = 0) stays symmetric.
local function path(points: { { number } }, even: boolean?): { { number } }
	local cubes: { { number } } = {}
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local steps = math.max(1, math.ceil(math.abs(b[1] - a[1]) + math.abs(b[2] - a[2]) + math.abs(b[3] - a[3])))
		local last = if index == #points - 1 then steps else steps - 1
		for step = 0, last do
			local t = step / steps
			local radius = a[4] + (b[4] - a[4]) * t
			local size = if even then math.max(2, math.round(radius) * 2) else math.max(1, math.round(radius * 2))
			local cube = {}
			for axis = 1, 3 do
				local centre = a[axis] + (b[axis] - a[axis]) * t
				cube[axis] = math.round(centre - size / 2)
				cube[axis + 3] = cube[axis] + size - 1
			end
			local previous = cubes[#cubes]
			if previous == nil then
				table.insert(cubes, cube)
				continue
			end
			local same = true
			for k = 1, 6 do
				same = same and previous[k] == cube[k]
			end
			if not same then
				-- Where a step jumps across a corner, put blocks in between so the path stays joined face to face.
				local chain = { cube }
				while not touching(previous, chain[1]) and #chain < 8 do
					table.insert(chain, 1, between(previous, chain[1]))
				end
				for _, link in chain do
					table.insert(cubes, link)
				end
			end
		end
	end
	return cubes
end

-- The cells on a straight line from one cell to another, each touching the one before.
local function line(from: { number }, to: { number }): { { number } }
	local list = {}
	for _, cube in path({
		{ from[1] + 0.5, from[2] + 0.5, from[3] + 0.5, 0.5 },
		{ to[1] + 0.5, to[2] + 0.5, to[3] + 0.5, 0.5 },
	}) do
		table.insert(list, { cube[1], cube[2], cube[3] })
	end
	return list
end

-- Draws single cells (or, with `paint`, paints them), joining cells that follow on in a straight line into one block.
local function cells(
	limb: Limb,
	list: { { number } },
	color: Color,
	paint: boolean?,
	material: string?,
	transparency: number?
)
	local runs = {}
	for _, cell in list do
		local run = runs[#runs]
		local joined = false
		if run then
			local axis, sign, moved = 0, 0, 0
			for k = 1, 3 do
				local d = cell[k] - run.last[k]
				if d ~= 0 then
					axis, sign, moved = k, d, moved + 1
				end
			end
			if moved == 0 then
				joined = true
			elseif
				moved == 1
				and math.abs(sign) == 1
				and (run.axis == nil or (run.axis == axis and run.sign == sign))
			then
				run.axis, run.sign, run.last = axis, sign, cell
				run.box[axis] = math.min(run.box[axis], cell[axis])
				run.box[axis + 3] = math.max(run.box[axis + 3], cell[axis])
				joined = true
			end
		end
		if not joined then
			table.insert(runs, { box = { cell[1], cell[2], cell[3], cell[1], cell[2], cell[3] }, last = cell })
		end
	end
	for _, run in runs do
		local b = run.box
		if paint then
			limb:paint(b[1], b[2], b[3], b[4], b[5], b[6], color, material)
		else
			limb:box(b[1], b[2], b[3], b[4], b[5], b[6], color, material, transparency)
		end
	end
end

export type Tube = {
	-- Every block along the tube, in order: { x0, y0, z0, x1, y1, z1, axis }, with cells inclusive and `axis` (1 to
	-- 3 for x, y, z) the way the tube runs there. Blocks 4 or more wide have their edges along `axis` trimmed off,
	-- which rounds the tube.
	cubes: { { number } },
	-- Whether a cell is inside the tube.
	inside: (x: number, y: number, z: number) -> boolean,
}

export type TubeOptions = {
	material: string?,
	transparency: number?,
	even: boolean?,
	-- Colours each block along the tube instead of `color`: given the block, its place along the tube and how many
	-- blocks there are, returns its colour and material.
	shade: ((cube: { number }, index: number, count: number) -> (Color, string?))?,
}

local ROUNDED = 4

-- Draws a rounded tube through points { x, y, z, radius } (see `path`), tapering as the radius changes: tentacles,
-- serpent bodies, horns. Blocks are merged where the tube runs straight. Returns the tube, so details can be added
-- along it.
local function tube(limb: Limb, points: { { number } }, color: Color, options: TubeOptions?): Tube
	local material = options and options.material
	local transparency = options and options.transparency
	local cubes = path(points, options and options.even)

	-- The way the tube runs at each block: the axis it moves furthest along between the blocks either side.
	for index, cube in cubes do
		local before, after = cubes[math.max(1, index - 1)], cubes[math.min(#cubes, index + 1)]
		local axis, most = 2, 0
		for k = 1, 3 do
			local d = math.abs(after[k] - before[k])
			if d > most then
				axis, most = k, d
			end
		end
		cube[7] = axis
	end

	-- How each block looks.
	local shade = options and options.shade
	local looks = {}
	for index, cube in cubes do
		if shade then
			local c, m = shade(cube, index, #cubes)
			looks[index] = { color = c, material = m }
		else
			looks[index] = { color = color, material = material }
		end
	end
	-- Where the colour changes, cut back the blocks of the new colour that overlap blocks of the old one just
	-- before them (overlapping blocks of different colours flicker), dropping any cut away to nothing.
	local function overlaps(a: { number }, b: { number }): boolean
		for k = 1, 3 do
			if a[k] > b[k + 3] or b[k] > a[k + 3] then
				return false
			end
		end
		return true
	end
	local kept, keptLooks = {}, {}
	for index, cube in cubes do
		local look = looks[index]
		local empty = false
		for back = #kept, math.max(1, #kept - 4), -1 do
			local previous, before = kept[back], keptLooks[back]
			if
				not empty
				and (look.color ~= before.color or look.material ~= before.material)
				and overlaps(cube, previous)
			then
				local axis, most = 1, 0
				for k = 1, 3 do
					local moved = (cube[k] + cube[k + 3]) - (previous[k] + previous[k + 3])
					if math.abs(moved) > math.abs(most) then
						axis, most = k, moved
					end
				end
				if most >= 0 then
					cube[axis] = previous[axis + 3] + 1
				else
					cube[axis + 3] = previous[axis] - 1
				end
				empty = cube[axis] > cube[axis + 3]
			end
		end
		if not empty then
			table.insert(kept, cube)
			table.insert(keptLooks, look)
		end
	end
	cubes, looks = kept, keptLooks

	-- Join runs of same-sized, same-looking blocks that slide one step at a time along one axis into single long
	-- blocks.
	local runs = {}
	for index, cube in cubes do
		local look = looks[index]
		local run = runs[#runs]
		local joined = false
		if run and run.look.color == look.color and run.look.material == look.material then
			local head = run.cubes[#run.cubes]
			local axis, sign = nil, 0
			local fits = true
			for k = 1, 3 do
				fits = fits and cube[k + 3] - cube[k] == head[k + 3] - head[k]
			end
			for k = 1, 3 do
				local d = cube[k] - head[k]
				if d ~= 0 then
					if axis ~= nil or math.abs(d) ~= 1 then
						fits = false
					end
					axis, sign = k, d
				end
			end
			if fits and axis and (run.axis == nil or (run.axis == axis and run.sign == sign)) then
				run.box[axis] = math.min(run.box[axis], cube[axis])
				run.box[axis + 3] = math.max(run.box[axis + 3], cube[axis + 3])
				run.axis, run.sign = axis, sign
				table.insert(run.cubes, cube)
				joined = true
			end
		end
		if not joined then
			table.insert(runs, { box = table.clone(cube), cubes = { cube }, look = look })
		end
	end
	for _, run in runs do
		local runColor, runMaterial = run.look.color, run.look.material
		if run.axis then
			for _, cube in run.cubes do
				cube[7] = run.axis
			end
		end
		local b = run.box
		local along = run.cubes[1][7]
		if run.cubes[1][4] - run.cubes[1][1] + 1 < ROUNDED then
			limb:box(b[1], b[2], b[3], b[4], b[5], b[6], runColor, runMaterial, transparency)
		else
			-- Two crossed blocks, each one narrower on a different side: a block with its long edges cut off.
			for _, trim in { along % 3 + 1, (along + 1) % 3 + 1 } do
				local c = table.clone(b)
				c[trim] += 1
				c[trim + 3] -= 1
				limb:box(c[1], c[2], c[3], c[4], c[5], c[6], runColor, runMaterial, transparency)
			end
		end
	end

	return {
		cubes = cubes,
		inside = function(x: number, y: number, z: number): boolean
			local p = { x, y, z }
			for _, c in cubes do
				if x >= c[1] and x <= c[4] and y >= c[2] and y <= c[5] and z >= c[3] and z <= c[6] then
					if c[4] - c[1] + 1 < ROUNDED then
						return true
					end
					local edges = 0
					for k = 1, 3 do
						if k ~= c[7] and (p[k] == c[k] or p[k] == c[k + 3]) then
							edges += 1
						end
					end
					if edges < 2 then
						return true
					end
				end
			end
			return false
		end,
	}
end

-- A tube and its mirror image on the other side of the pet (horns, whiskers).
local function tubePair(limb: Limb, points: { { number } }, color: Color, options: TubeOptions?): (Tube, Tube)
	local other = {}
	for _, point in points do
		table.insert(other, { -point[1], point[2], point[3], point[4] })
	end
	return tube(limb, points, color, options), tube(limb, other, color, options)
end

-- The middle cell of a tube block.
local function cubeMiddle(cube: { number }): (number, number, number)
	return (cube[1] + cube[4]) // 2, (cube[2] + cube[5]) // 2, (cube[3] + cube[6]) // 2
end

-- The axis (1 to 3) a direction such as { 0, 1, 0 } points along.
local function axisOf(direction: { number }): number
	return if direction[1] ~= 0 then 1 elseif direction[2] ~= 0 then 2 else 3
end

-- The outermost cell of a tube going out from the middle of one of its blocks in a direction such as { 0, 1, 0 }:
-- where to paint a sucker, or stand a spike. Nil if the tube runs that way there, so there is no side to find.
local function surfaceCell(t: Tube, cube: { number }, direction: { number }): { number }?
	if cube[7] == axisOf(direction) then
		return nil
	end
	local x, y, z = cubeMiddle(cube)
	while t.inside(x + direction[1], y + direction[2], z + direction[3]) do
		x, y, z = x + direction[1], y + direction[2], z + direction[3]
	end
	return { x, y, z }
end

export type Curl = {
	-- The middle of the curl.
	centre: { number },
	-- The two axes (1 to 3 for x, y, z) of the plane it curls in.
	plane: { number },
	-- Where it starts, as an angle round the middle (radians, from the first axis towards the second).
	from: number,
	-- How far round it goes, in whole turns; negative goes the other way.
	turns: number,
	-- How far from the middle it is at the start and at the end.
	radius: { number },
	-- How thick the tube is (its radius) at the start and at the end.
	width: { number },
}

-- Points round a curl, for the tip of a tentacle or tail, to pass to `tube` after the points leading up to it.
local function curl(c: Curl): { { number } }
	local points = {}
	local count = math.max(4, math.ceil(math.abs(c.turns) * 12))
	for i = 0, count do
		local f = i / count
		local angle = c.from + c.turns * 2 * math.pi * f
		local r = c.radius[1] + (c.radius[2] - c.radius[1]) * f
		local point = { c.centre[1], c.centre[2], c.centre[3], c.width[1] + (c.width[2] - c.width[1]) * f }
		point[c.plane[1]] += r * math.cos(angle)
		point[c.plane[2]] += r * math.sin(angle)
		table.insert(points, point)
	end
	return points
end

-- `points` followed by `more`.
local function andThen(points: { { number } }, more: { { number } }): { { number } }
	local all = table.clone(points)
	table.move(more, 1, #more, #all + 1, all)
	return all
end

-- `points` mirrored to the other side of the pet.
local function mirrorPoints(points: { { number } }): { { number } }
	local other = {}
	for _, point in points do
		table.insert(other, { -point[1], point[2], point[3], point[4] })
	end
	return other
end

-- Fills the cells inside a rounded shape with blocks: `inside(x, y, z)` says which cells are in it, and `bounds`
-- ({ x0, y0, z0, x1, y1, z1 }) is a box round it. Each level of the shape must be convex, with no dents or holes.
-- Blocks overlap, so a few cover each level, and stack into taller blocks where levels match. Returns `inside`.
local function blob(
	limb: Limb,
	bounds: { number },
	inside: (number, number, number) -> boolean,
	color: Color,
	material: string?
): (number, number, number) -> boolean
	local open: { { number } } = {}
	local function draw(b: { number })
		limb:box(b[1], b[5], b[2], b[3], b[6], b[4], color, material)
	end
	for y = bounds[2], bounds[5] do
		-- Each row across the level (along x), by z.
		local rows: { [number]: { number } } = {}
		for z = bounds[3], bounds[6] do
			for x = bounds[1], bounds[4] do
				if inside(x, y, z) then
					local row = rows[z]
					if row then
						row[2] = x
					else
						rows[z] = { x, x }
					end
				end
			end
		end
		-- One block for each different row, reaching over every row next to it that is at least as wide.
		local level: { { number } } = {}
		for z = bounds[3], bounds[6] do
			local row = rows[z]
			if row then
				local function covers(other: { number }?): boolean
					return other ~= nil and other[1] <= row[1] and other[2] >= row[2]
				end
				local z0, z1 = z, z
				while covers(rows[z0 - 1]) do
					z0 -= 1
				end
				while covers(rows[z1 + 1]) do
					z1 += 1
				end
				local new = true
				for _, b in level do
					if b[1] == row[1] and b[3] == row[2] and b[2] == z0 and b[4] == z1 then
						new = false
					end
				end
				if new then
					table.insert(level, { row[1], z0, row[2], z1 })
				end
			end
		end
		-- Carry on the blocks from the level below that this level matches; finish the rest.
		local carried: { { number } } = {}
		for _, b in level do
			local found = nil
			for index, o in open do
				if o[1] == b[1] and o[2] == b[2] and o[3] == b[3] and o[4] == b[4] then
					found = index
				end
			end
			if found then
				local o = table.remove(open, found)
				o[6] = y
				table.insert(carried, o)
			else
				table.insert(carried, { b[1], b[2], b[3], b[4], y, y })
			end
		end
		for _, o in open do
			draw(o)
		end
		open = carried
	end
	for _, o in open do
		draw(o)
	end
	return inside
end

----------------------------------------------------------------------------------------------------------------
-- Sculpting, for the showpieces: a limb is modelled cell by cell out of rounded shapes, each of which can be turned
-- to any angle, then packed into as few blocks as possible. Later shapes cover earlier ones, so details are just
-- more shapes on top. Every cell belongs to one block, so no two blocks ever overlap (and so never flicker).

export type Look = { color: Color, material: string?, transparency: number? }
-- Where a shape sits and which way it faces: its own x, y and z are turned by `yaw` (round y, turning forward
-- towards its left), then `pitch` (tipping forward up), then `roll` (round its forward axis), and moved to `origin`.
export type Frame = { origin: { number }, yaw: number?, pitch: number?, roll: number? }
export type Shape = {
	-- Whether a point (not a cell: the middle of cell x is x + 0.5) is inside it, in its own frame.
	inside: (x: number, y: number, z: number) -> boolean,
	-- A ball round it, in its own frame, to know which cells to try.
	centre: { number },
	radius: number,
}

local function toWorld(frame: Frame, x: number, y: number, z: number): (number, number, number)
	local c, s = math.cos(frame.roll or 0), math.sin(frame.roll or 0)
	x, y = x * c - y * s, x * s + y * c
	c, s = math.cos(frame.pitch or 0), math.sin(frame.pitch or 0)
	y, z = y * c + z * s, -y * s + z * c
	c, s = math.cos(frame.yaw or 0), math.sin(frame.yaw or 0)
	x, z = x * c + z * s, -x * s + z * c
	return x + frame.origin[1], y + frame.origin[2], z + frame.origin[3]
end

local function toLocal(frame: Frame, x: number, y: number, z: number): (number, number, number)
	x, y, z = x - frame.origin[1], y - frame.origin[2], z - frame.origin[3]
	local c, s = math.cos(-(frame.yaw or 0)), math.sin(-(frame.yaw or 0))
	x, z = x * c + z * s, -x * s + z * c
	c, s = math.cos(-(frame.pitch or 0)), math.sin(-(frame.pitch or 0))
	y, z = y * c + z * s, -y * s + z * c
	c, s = math.cos(-(frame.roll or 0)), math.sin(-(frame.roll or 0))
	x, y = x * c - y * s, x * s + y * c
	return x, y, z
end

-- An egg shape: a ball stretched to radii { rx, ry, rz }.
local function ellipsoid(centre: { number }, radii: { number }): Shape
	return {
		centre = centre,
		radius = math.max(radii[1], radii[2], radii[3]),
		inside = function(x: number, y: number, z: number): boolean
			local dx, dy, dz = (x - centre[1]) / radii[1], (y - centre[2]) / radii[2], (z - centre[3]) / radii[3]
			return dx * dx + dy * dy + dz * dz <= 1
		end,
	}
end

-- A rounded rod through points { x, y, z, radius }, tapering from one to the next: legs, necks, horns, claws.
local function rod(points: { { number } }): Shape
	local low, high = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	for _, p in points do
		for k = 1, 3 do
			low[k] = math.min(low[k], p[k] - p[4])
			high[k] = math.max(high[k], p[k] + p[4])
		end
	end
	local centre = { (low[1] + high[1]) / 2, (low[2] + high[2]) / 2, (low[3] + high[3]) / 2 }
	return {
		centre = centre,
		radius = math.max(high[1] - low[1], high[2] - low[2], high[3] - low[3]) / 2 * 1.74,
		inside = function(x: number, y: number, z: number): boolean
			for index = 1, #points - 1 do
				local a, b = points[index], points[index + 1]
				local abx, aby, abz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
				local length = abx * abx + aby * aby + abz * abz
				local t = 0
				if length > 0 then
					t = math.clamp(((x - a[1]) * abx + (y - a[2]) * aby + (z - a[3]) * abz) / length, 0, 1)
				end
				local dx, dy, dz = a[1] + abx * t - x, a[2] + aby * t - y, a[3] + abz * t - z
				local r = a[4] + (b[4] - a[4]) * t
				if dx * dx + dy * dy + dz * dz <= r * r then
					return true
				end
			end
			return false
		end,
	}
end

-- Any shape at all, from a test for points inside it and a ball round it.
local function shape(centre: { number }, radius: number, inside: (number, number, number) -> boolean): Shape
	return { centre = centre, radius = radius, inside = inside }
end

local Sculpt = {}
Sculpt.__index = Sculpt
export type Sculpt = typeof(setmetatable({} :: { cells: { [number]: Look }, unit: number }, Sculpt))

local function cellKey(x: number, y: number, z: number): number
	return ((x + 512) * 1024 + (y + 512)) * 1024 + (z + 512)
end

local function cellAt(key: number): (number, number, number)
	local z = key % 1024
	key = (key - z) // 1024
	local y = key % 1024
	return (key - y) // 1024 - 512, y - 512, z - 512
end

-- Clay modelled in units of the design's choosing, `unit` of them to a cell, so a design can be drawn once and
-- built finer or coarser. Positions given to the limbs it is drawn on (pivots, the seat) are in cells: divide by
-- `unit`.
local function newSculpt(unit: number?): Sculpt
	return setmetatable({ cells = {}, unit = unit or 1 }, Sculpt)
end

-- Calls `fn` with every cell whose middle is inside the shape. With `ensure`, a shape too small to hold the middle
-- of any cell still gets the cell its own middle is in, so small details never vanish.
function Sculpt.each(self: Sculpt, s: Shape, frame: Frame?, fn: (number, number, number) -> (), ensure: boolean?)
	local unit = self.unit
	local cx, cy, cz = s.centre[1], s.centre[2], s.centre[3]
	if frame then
		cx, cy, cz = toWorld(frame, cx, cy, cz)
	end
	local r = s.radius / unit + 1
	cx, cy, cz = cx / unit, cy / unit, cz / unit
	local found = false
	for x = math.floor(cx - r), math.ceil(cx + r) do
		for y = math.floor(cy - r), math.ceil(cy + r) do
			for z = math.floor(cz - r), math.ceil(cz + r) do
				local px, py, pz = (x + 0.5) * unit, (y + 0.5) * unit, (z + 0.5) * unit
				if frame then
					px, py, pz = toLocal(frame, px, py, pz)
				end
				if s.inside(px, py, pz) then
					found = true
					fn(x, y, z)
				end
			end
		end
	end
	if ensure and not found then
		fn(math.floor(cx), math.floor(cy), math.floor(cz))
	end
end

-- Fills a shape with clay of a look, over anything already there.
function Sculpt.add(self: Sculpt, s: Shape, look: Look, frame: Frame?)
	self:each(s, frame, function(x, y, z)
		self.cells[cellKey(x, y, z)] = look
	end, true)
end

-- Cuts a shape away.
function Sculpt.carve(self: Sculpt, s: Shape, frame: Frame?)
	self:each(s, frame, function(x, y, z)
		self.cells[cellKey(x, y, z)] = nil
	end)
end

function Sculpt.has(self: Sculpt, x: number, y: number, z: number): boolean
	return self.cells[cellKey(x, y, z)] ~= nil
end

-- Whether a cell is on the outside of the clay, with at least one side showing.
function Sculpt.showing(self: Sculpt, x: number, y: number, z: number): boolean
	return self:has(x, y, z)
		and not (
			self:has(x + 1, y, z)
			and self:has(x - 1, y, z)
			and self:has(x, y + 1, z)
			and self:has(x, y - 1, z)
			and self:has(x, y, z + 1)
			and self:has(x, y, z - 1)
		)
end

-- Recolours the clay already inside a shape: with `outside`, only the cells that show.
function Sculpt.paint(self: Sculpt, s: Shape, look: Look, frame: Frame?, outside: boolean?)
	self:each(s, frame, function(x, y, z)
		if self:has(x, y, z) and (not outside or self:showing(x, y, z)) then
			self.cells[cellKey(x, y, z)] = look
		end
	end)
end

-- Builds the clay on a limb as blocks. Cells that are hidden inside (in this clay or another limb's) take the main look (the most common one), so
-- the bulk of the clay is one solid colour, then each look is covered with as few blocks as it can find. Blocks of
-- the same look may overlap, which never shows; blocks of different looks never do.
-- Draws a line over the outside of the clay: follows a path of points { x, y, z } (design units), and at each step
-- colours the outermost cell seen looking along `direction` (such as { -1, 0, 0 }, looking from its left side).
-- Only the path's other two coordinates matter.
function Sculpt.trace(self: Sculpt, points: { { number } }, direction: { number }, look: Look)
	local unit = self.unit
	local axis = if direction[1] ~= 0 then 1 elseif direction[2] ~= 0 then 2 else 3
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local length = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
		local steps = math.max(1, math.ceil(length / (unit * 0.4)))
		for step = 0, steps do
			local t = step / steps
			local cell = {}
			for k = 1, 3 do
				cell[k] = math.floor((a[k] + (b[k] - a[k]) * t) / unit)
			end
			cell[axis] = -direction[axis] * 60
			for _ = 0, 120 do
				local key = cellKey(cell[1], cell[2], cell[3])
				if self.cells[key] then
					self.cells[key] = look
					break
				end
				cell[axis] += direction[axis]
			end
		end
	end
end

-- A copy mirrored to the other side of the pet, for the clay of a limb drawn with limbPair.
function Sculpt.mirror(self: Sculpt): Sculpt
	local copy = newSculpt(self.unit)
	for key, look in self.cells do
		local x, y, z = cellAt(key)
		copy.cells[cellKey(-1 - x, y, z)] = look
	end
	return copy
end

-- Recolours the cells that show by a rule: `rule` is given each one's middle (in design units) and a test of
-- whether the cell beside it in a direction is empty (so which way it faces), and returns a look or nil to leave it.
function Sculpt.coat(self: Sculpt, rule: (point: { number }, open: (number, number, number) -> boolean) -> Look?)
	local unit = self.unit
	local changes = {}
	for key in self.cells do
		local x, y, z = cellAt(key)
		if self:showing(x, y, z) then
			local look = rule({ (x + 0.5) * unit, (y + 0.5) * unit, (z + 0.5) * unit }, function(dx, dy, dz)
				return not self:has(x + dx, y + dy, z + dz)
			end)
			if look then
				changes[key] = look
			end
		end
	end
	for key, look in changes do
		self.cells[key] = look
	end
end

-- `others` are the sculpts of the limbs that overlap this one: where they fill a cell too, it is hidden inside.
-- Hidden cells all take `inside` (by default the commonest look); limbs that overlap should share it. With `asParts`,
-- the blocks are placed in the design's own units (cells `unit` across) rather than one voxel to a cell, so clay
-- can be finer than the rest of the pet.
function Sculpt.draw(self: Sculpt, limb: Limb, others: { Sculpt }?, inside: Look?, asParts: boolean?)
	-- Thin tips can end in cells touching the rest only at a corner, which would float: keep only the cells
	-- joined, face to face or edge to edge, to the biggest piece.
	local neighbours = {}
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				local moved = math.abs(dx) + math.abs(dy) + math.abs(dz)
				if moved == 1 or moved == 2 then
					table.insert(neighbours, { dx, dy, dz })
				end
			end
		end
	end
	local piece: { [number]: number } = {}
	local sizes: { number } = {}
	local starts = {}
	for key in self.cells do
		table.insert(starts, key)
	end
	table.sort(starts)
	for _, start in starts do
		if not piece[start] then
			local id = #sizes + 1
			sizes[id] = 0
			piece[start] = id
			local queue = { start }
			local head = 1
			while head <= #queue do
				local x, y, z = cellAt(queue[head])
				head += 1
				sizes[id] += 1
				for _, n in neighbours do
					local k = cellKey(x + n[1], y + n[2], z + n[3])
					if self.cells[k] and not piece[k] then
						piece[k] = id
						table.insert(queue, k)
					end
				end
			end
		end
	end
	local biggest = 1
	for id, size in sizes do
		if size > sizes[biggest] then
			biggest = id
		end
	end
	for key, id in piece do
		if id ~= biggest then
			self.cells[key] = nil
		end
	end

	local names: { [number]: string } = {}
	local looks: { [string]: Look } = {}
	local counts: { [string]: number } = {}
	for key, look in self.cells do
		local name = `{look.color[1]},{look.color[2]},{look.color[3]},{look.material},{look.transparency}`
		names[key] = name
		looks[name] = look
		counts[name] = (counts[name] or 0) + 1
	end
	local main, most = nil, -1
	for name, count in counts do
		if count > most or (count == most and name < (main :: string)) then
			main, most = name, count
		end
	end
	if inside then
		main = `{inside.color[1]},{inside.color[2]},{inside.color[3]},{inside.material},{inside.transparency}`
		looks[main :: string] = inside
	end
	local sets: { [string]: { [number]: boolean } } = {}
	for key, name in names do
		local x, y, z = cellAt(key)
		local covered = false
		for _, other in others or {} do
			covered = covered or other.cells[key] ~= nil
		end
		local into = if self:showing(x, y, z) and not covered then name else main :: string
		sets[into] = sets[into] or {}
		sets[into][key] = true
	end

	-- As few blocks as it can find covering one set of cells exactly (blocks may overlap), as
	-- { x0, y0, z0, x1, y1, z1 }. Candidates come from every row of cells in every slice, in all three
	-- directions: each row is widened over the rows beside it that hold it, then thickened over the slices beside
	-- it that hold it. Then the candidate covering the most cells not yet covered is taken, again and again, and
	-- any taken block the others turn out to cover is dropped.
	local function cover(set: { [number]: boolean }): { { number } }
		local candidates: { { number } } = {}
		local seen: { [string]: boolean } = {}
		local function inSet(p: { number }): boolean
			return set[cellKey(p[1], p[2], p[3])] == true
		end
		for axis = 1, 3 do
			local u, v = axis % 3 + 1, (axis + 1) % 3 + 1
			local rows: { [string]: { number } } = {}
			for key in set do
				local p = { cellAt(key) }
				local name = `{p[axis]},{p[u]}`
				rows[name] = rows[name] or { p[axis], p[u] }
				table.insert(rows[name], p[v])
			end
			for _, row in rows do
				local a0, ui = row[1], row[2]
				local vs = table.move(row, 3, #row, 1, {})
				table.sort(vs)
				local index = 1
				while index <= #vs do
					local v0 = vs[index]
					local v1 = v0
					while index < #vs and vs[index + 1] == v1 + 1 do
						index += 1
						v1 = vs[index]
					end
					index += 1
					local box = {}
					box[axis], box[axis + 3] = a0, a0
					box[u], box[u + 3] = ui, ui
					box[v], box[v + 3] = v0, v1
					-- Grow it one way, then another, while every cell it would take is in the set.
					local function grow(k: number, step: number): boolean
						local edge = if step > 0 then box[k + 3] + 1 else box[k] - 1
						local p = {}
						local ka, kb = k % 3 + 1, (k + 1) % 3 + 1
						for i = box[ka], box[ka + 3] do
							for j = box[kb], box[kb + 3] do
								p[k], p[ka], p[kb] = edge, i, j
								if not inSet(p) then
									return false
								end
							end
						end
						if step > 0 then
							box[k + 3] = edge
						else
							box[k] = edge
						end
						return true
					end
					for _, k in { u, axis } do
						for _, step in { -1, 1 } do
							local more = true
							while more do
								more = grow(k, step)
							end
						end
					end
					local name = table.concat(box, ",")
					if not seen[name] then
						seen[name] = true
						table.insert(candidates, box)
					end
				end
			end
		end
		table.sort(candidates, function(a, b)
			return table.concat(a, ",") < table.concat(b, ",")
		end)

		-- The cells each candidate covers.
		local cellsOf: { { number } } = {}
		for index, box in candidates do
			local list = {}
			for x = box[1], box[4] do
				for y = box[2], box[5] do
					for z = box[3], box[6] do
						table.insert(list, cellKey(x, y, z))
					end
				end
			end
			cellsOf[index] = list
		end
		local covered: { [number]: number } = {}
		local left = 0
		for _ in set do
			left += 1
		end
		local gain = {}
		for index, list in cellsOf do
			gain[index] = #list
		end
		local taken = {}
		while left > 0 do
			local best, bestGain = nil, 0
			for index, g in gain do
				if g > bestGain then
					-- Stored gains only ever shrink, so check this one is still right before trusting it.
					local fresh = 0
					for _, key in cellsOf[index] do
						if not covered[key] then
							fresh += 1
						end
					end
					gain[index] = fresh
					if fresh > bestGain then
						best, bestGain = index, fresh
					end
				end
			end
			if best == nil then
				break
			end
			gain[best] = 0
			table.insert(taken, best)
			for _, key in cellsOf[best] do
				if not covered[key] then
					left -= 1
				end
				covered[key] = (covered[key] or 0) + 1
			end
		end
		local blocks = {}
		for i = #taken, 1, -1 do
			local list = cellsOf[taken[i]]
			local needed = false
			for _, key in list do
				if covered[key] == 1 then
					needed = true
					break
				end
			end
			if needed then
				table.insert(blocks, 1, candidates[taken[i]])
			else
				for _, key in list do
					covered[key] -= 1
				end
			end
		end
		return blocks
	end

	local names2 = {}
	for name in sets do
		table.insert(names2, name)
	end
	table.sort(names2, function(a, b)
		return (a == main) and b ~= main or ((b == main) == (a == main) and a < b)
	end)
	for _, name in names2 do
		local look = looks[name]
		for _, b in cover(sets[name]) do
			if asParts then
				local unit = self.unit
				limb:part(
					{ (b[1] + b[4] + 1) / 2 * unit, (b[2] + b[5] + 1) / 2 * unit, (b[3] + b[6] + 1) / 2 * unit },
					{ (b[4] - b[1] + 1) * unit, (b[5] - b[2] + 1) * unit, (b[6] - b[3] + 1) * unit },
					{ { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } },
					look.color,
					look.material,
					look.transparency
				)
			else
				limb:box(b[1], b[2], b[3], b[4], b[5], b[6], look.color, look.material, look.transparency)
			end
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Parts at an angle, for the most detailed pets: blades, wedge points and egg shapes pointed any way, in voxels.

type Vec = { number }

local function vadd(a: Vec, b: Vec): Vec
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

local function vsub(a: Vec, b: Vec): Vec
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function vscale(a: Vec, s: number): Vec
	return { a[1] * s, a[2] * s, a[3] * s }
end

local function vlerp(a: Vec, b: Vec, t: number): Vec
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function vdot(a: Vec, b: Vec): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local function vcross(a: Vec, b: Vec): Vec
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function vlength(a: Vec): number
	return math.sqrt(vdot(a, a))
end

local function vnorm(a: Vec): Vec
	local length = vlength(a)
	return if length > 1e-9 then vscale(a, 1 / length) else { 0, 1, 0 }
end

-- Some direction square to `a`, for when the one wanted lines up with it.
local function squareTo(a: Vec): Vec
	local x = vcross(a, { 1, 0, 0 })
	if vdot(x, x) < 1e-6 then
		x = vcross(a, { 0, 0, 1 })
	end
	return vnorm(x)
end

-- Axes for a part whose own y runs along `along`, with its own z turned as near to `facing` as it can be.
local function axesAlong(along: Vec, facing: Vec): { Vec }
	local y = vnorm(along)
	local x = vcross(y, facing)
	x = if vdot(x, x) < 1e-6 then squareTo(y) else vnorm(x)
	return { x, y, vcross(x, y) }
end

-- A flat blade (a block) from `a` to `b`, `width` across and `thickness` through, its broad face towards `facing`.
local function blade(
	limb: Limb,
	a: Vec,
	b: Vec,
	width: number,
	thickness: number,
	facing: Vec,
	color: Color,
	material: string?
)
	limb:part(
		vlerp(a, b, 0.5),
		{ width, vlength(vsub(b, a)), thickness },
		axesAlong(vsub(b, a), facing),
		color,
		material
	)
end

-- A wedge from its broad end at `a` to an edge at `b`: a feather's tip, a claw, the hook of a beak. Its broad face
-- (`width` across) is towards `facing`, `thickness` through it. One side runs straight on from the part before it,
-- the other slants in to the point.
local function taper(
	limb: Limb,
	a: Vec,
	b: Vec,
	width: number,
	thickness: number,
	facing: Vec,
	color: Color,
	material: string?
)
	-- A Roblox wedge narrows towards its own -z, along its bottom: point that at `b`, its own x through it.
	local z = vnorm(vsub(a, b))
	local x = vsub(facing, vscale(z, vdot(facing, z)))
	x = if vdot(x, x) < 1e-6 then squareTo(z) else vnorm(x)
	local y = vcross(z, x)
	limb:part(vlerp(a, b, 0.5), { thickness, width, vlength(vsub(b, a)) }, { x, y, z }, color, material, nil, "Wedge")
end

-- A flat triangle between three points, `thickness` thick (for wing membranes): two wedges, split along the line
-- from the corner opposite its longest side, square to that side.
local function triangle(limb: Limb, a: Vec, b: Vec, c: Vec, thickness: number, color: Color, material: string?)
	local ab, ac, bc = vsub(b, a), vsub(c, a), vsub(c, b)
	local abd, acd, bcd = vdot(ab, ab), vdot(ac, ac), vdot(bc, bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = vsub(b, a), vsub(c, a), vsub(c, b)
	local right = vnorm(vcross(ac, ab))
	local up = vnorm(vcross(bc, right))
	local back = vnorm(bc)
	local height = math.abs(vdot(ab, up))
	local wedge = "Wedge"
	limb:part(
		vlerp(a, b, 0.5),
		{ thickness, height, math.abs(vdot(ab, back)) },
		{ right, up, back },
		color,
		material,
		nil,
		wedge
	)
	limb:part(
		vlerp(a, c, 0.5),
		{ thickness, height, math.abs(vdot(ac, back)) },
		{ vscale(right, -1), up, vscale(back, -1) },
		color,
		material,
		nil,
		wedge
	)
end

-- An egg shape at `center`, `size` along its axes (default lined up with the pet).
local function egg(limb: Limb, center: Vec, size: Vec, axes: { Vec }?, color: Color, material: string?)
	limb:part(center, size, axes or { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }, color, material, nil, "Ball")
end

export type Band = { color: Color, material: string?, to: number }

-- A feather from `root`, `length` long along `direction`, in bands of colour from the root out (each ending
-- `to` of the way along), narrowing a little band by band and ending in a point.
local function feather(
	limb: Limb,
	root: Vec,
	direction: Vec,
	length: number,
	width: number,
	thickness: number,
	facing: Vec,
	bands: { Band }
)
	local d = vnorm(direction)
	local from = 0
	for index, band in bands do
		local a, b = vadd(root, vscale(d, from * length)), vadd(root, vscale(d, band.to * length))
		local w = width * (1 - 0.08 * (index - 1))
		if index == #bands then
			taper(limb, a, b, w, thickness, facing, band.color, band.material)
		else
			blade(limb, a, b, w, thickness, facing, band.color, band.material)
		end
		from = band.to
	end
end

----------------------------------------------------------------------------------------------------------------
-- Helpers for sculpted pets

-- A look for sculpted clay: a colour and, optionally, a material.
local function look(r: number, g: number, b: number, material: string?): Look
	return { color = rgb(r, g, b), material = material }
end

-- A steady pseudo-random number from 0 to 1 for a point: the same every time, for speckles and dapples.
local function noise(p: Vec): number
	local n = math.sin(p[1] * 12.9898 + p[2] * 78.233 + p[3] * 37.719) * 43758.5453
	return n - math.floor(n)
end

-- How far the clay reaches out to the pet's left at a height and depth (design units): where its surface is.
local function sideOf(s: Sculpt, y: number, z: number): number
	local u = s.unit
	local cx, cy, cz = 0, math.floor(y / u), math.floor(z / u)
	while s:has(cx + 1, cy, cz) do
		cx += 1
	end
	return (cx + 1) * u
end

-- How far the clay reaches forward at a point across and a height (design units): where its front surface is.
local function frontOf(s: Sculpt, x: number, y: number): number
	local u = s.unit
	local cx, cy, cz = math.floor(x / u), math.floor(y / u), math.floor(90 / u)
	while cz > -90 / u and not s:has(cx, cy, cz) do
		cz -= 1
	end
	return (cz + 1) * u
end

-- The underside of the clay under a point (design units): up from low down to the first cell.
local function bottomOf(s: Sculpt, z: number, x: number?): number
	local u = s.unit
	local cx, cz, y = math.floor((x or 0) / u), math.floor(z / u), math.floor(-10 / u)
	while y < 120 / u and not s:has(cx, y, cz) do
		y += 1
	end
	return y * u
end

-- The top of the clay over a point (design units): down from high above to the first cell.
local function topOf(s: Sculpt, z: number, x: number?): number
	local u = s.unit
	local cx, cz, y = math.floor((x or 0) / u), math.floor(z / u), math.floor(90 / u)
	while y > -20 and not s:has(cx, y, cz) do
		y -= 1
	end
	return (y + 1) * u
end

-- Round eyes set into both sides of a sculpted head at a height and depth (design units), `size` across, each
-- with a glint of light. Ball parts, so they stay round however big the pet is shown.
local function roundEyes(limb: Limb, s: Sculpt, y: number, z: number, size: number, color: Color?)
	local u = s.unit
	local x = sideOf(s, y, z)
	for _, side in { 1, -1 } do
		egg(
			limb,
			{ (x - size * 0.12) * side / u, y / u, z / u },
			{ size * 0.55 / u, size / u, size / u },
			nil,
			color or EYE
		)
		egg(
			limb,
			{ (x + size * 0.12) * side / u, (y + size * 0.25) / u, (z + size * 0.2) / u },
			{ size * 0.24 / u, size * 0.34 / u, size * 0.34 / u },
			nil,
			SHINE
		)
	end
end

-- Narrow eyes, pointed at both ends, flat on both sides of a sculpted head: from `front` to `back` ({ y, z } in
-- design units), `width` across the middle, each in a dark rim.
local function slitEyes(
	limb: Limb,
	s: Sculpt,
	front: { number },
	back: { number },
	width: number,
	color: Color,
	material: string?,
	rim: Color?
)
	local u = s.unit
	local depth = sideOf(s, (front[1] + back[1]) / 2, (front[2] + back[2]) / 2) - 0.03
	local function at(p: Vec): Vec
		return { p[1] / u, p[2] / u, p[3] / u }
	end
	for _, side in { 1, -1 } do
		local out = { side, 0, 0 }
		local function almond(grow: number, shade: Color, glow: string?, thick: number)
			local x = side * (depth + thick / 2)
			local nose = { x, front[1] - grow * 0.2, front[2] + grow }
			local tail = { x, back[1] + grow * 0.2, back[2] - grow }
			local p1, p2 = vlerp(nose, tail, 0.3), vlerp(nose, tail, 0.7)
			taper(limb, at(p1), at(nose), (width + grow) / u, thick / u, out, shade, glow)
			blade(limb, at(p1), at(p2), (width + grow) / u, thick / u, out, shade, glow)
			taper(limb, at(p2), at(tail), (width + grow) / u, thick / u, out, shade, glow)
		end
		almond(0.4, rim or EYE, nil, 0.16)
		almond(0, color, material, 0.3)
	end
end

-- Angled parts placed in a sculpted pet's own design units (`u` of them to a block), so a design can use one set of
-- numbers for its clay and its parts.
local function inUnits(u: number)
	local t = {}
	function t.at(p: Vec): Vec
		return { p[1] / u, p[2] / u, p[3] / u }
	end
	function t.blade(
		limb: Limb,
		a: Vec,
		b: Vec,
		width: number,
		thick: number,
		facing: Vec,
		color: Color,
		material: string?
	)
		blade(limb, t.at(a), t.at(b), width / u, thick / u, facing, color, material)
	end
	function t.taper(
		limb: Limb,
		a: Vec,
		b: Vec,
		width: number,
		thick: number,
		facing: Vec,
		color: Color,
		material: string?
	)
		taper(limb, t.at(a), t.at(b), width / u, thick / u, facing, color, material)
	end
	function t.triangle(limb: Limb, a: Vec, b: Vec, c: Vec, thick: number, color: Color, material: string?)
		triangle(limb, t.at(a), t.at(b), t.at(c), thick / u, color, material)
	end
	-- A ball (or egg shape, given three sizes) centred on a point.
	function t.ball(limb: Limb, centre: Vec, size: number | Vec, color: Color, material: string?)
		local s: Vec = if type(size) == "number" then { size, size, size } else size
		egg(limb, t.at(centre), { s[1] / u, s[2] / u, s[3] / u }, nil, color, material)
	end
	-- A chain of blades through points, `width` across, narrowing to a point at the end: a branch, a horn, a vine.
	function t.branch(limb: Limb, points: { Vec }, width: number, facing: Vec, color: Color, material: string?)
		for index = 1, #points - 1 do
			local w = width * (1 - 0.5 * (index - 1) / math.max(1, #points - 1))
			if index == #points - 1 then
				t.taper(limb, points[index], points[index + 1], w, w, facing, color, material)
			else
				t.blade(limb, points[index], points[index + 1], w, w, facing, color, material)
			end
		end
	end
	return t
end

local Designs: { [string]: Design } = {}

----------------------------------------------------------------------------------------------------------------
-- Forest

Designs.Squirrel = {
	name = "Squirrel",
	skeleton = "Quadruped",
	gait = "Hop",
	scale = 0.45,
	draw = function(pet)
		local FUR = rgb(204, 116, 54)
		local DARK = rgb(140, 74, 34)
		local CREAM = rgb(248, 226, 186)
		local TIP = rgb(232, 160, 96)
		local NOSE = rgb(84, 44, 30)

		local ACORN = rgb(200, 142, 82)
		local CAP = rgb(112, 74, 44)
		local PINK = rgb(255, 172, 188)

		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-3, 3, -3, 2, 7, 3, FUR)
		body:paint(-2, 3, 3, 1, 6, 3, CREAM)
		body:paint(-1, 7, -3, 0, 7, 2, DARK)
		-- An acorn held up in its front paws.
		body:box(-1, 4, 4, 0, 5, 5, ACORN)
		body:box(-1, 6, 4, 0, 6, 5, CAP)

		local head = pet:limb("Head", { 0, 8, 1 })
		head:box(-4, 8, -1, 3, 14, 5, FUR)
		head:paint(-3, 8, 5, 2, 10, 5, CREAM)
		head:paint(-1, 10, 5, 0, 10, 5, NOSE)
		eyes(head, 1, 11, 5)
		-- Pointed ears with dark tufts.
		head:boxPair(2, 15, 1, 3, 16, 2, FUR)
		head:paintPair(2, 15, 2, 2, 15, 2, PINK)
		head:boxPair(3, 17, 2, 3, 17, 2, DARK)
		head:paintPair(3, 9, 5, 3, 9, 5, PINK)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 4, 2 }, function(leg)
			leg:box(1, 0, 1, 2, 3, 2, FUR)
			leg:paint(1, 0, 2, 2, 0, 2, CREAM)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2.5, 5, -2 }, function(leg)
			leg:box(1, 1, -3, 3, 5, -1, FUR)
			leg:box(1, 0, -3, 2, 0, 0, FUR)
		end)

		-- A big bushy tail curling up over its back.
		local tail = pet:limb("Tail", { 0, 5, -3 })
		tail:box(-2, 4, -6, 1, 6, -4, FUR)
		tail:box(-3, 6, -8, 2, 15, -5, FUR)
		tail:box(-3, 14, -5, 2, 16, -3, FUR)
		tail:paint(-3, 15, -8, 2, 16, -3, TIP)
		tail:paint(-3, 6, -8, 2, 7, -8, DARK)
		tail:paint(-3, 10, -8, 2, 10, -5, TIP)
		tail:paint(-3, 12, -8, 2, 12, -5, DARK)

		pet:seat(0, 8, -1)
	end,
}

Designs.Bunny = {
	name = "Bunny",
	skeleton = "Quadruped",
	gait = "Hop",
	scale = 0.45,
	draw = function(pet)
		local FUR = rgb(244, 238, 226)
		local FAWN = rgb(206, 168, 128)
		local PINK = rgb(255, 172, 188)

		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-3, 2, -3, 2, 6, 2, FUR)
		-- A fawn saddle, like the bottom of its egg.
		body:paint(-3, 5, -3, 2, 6, -1, FAWN)
		body:box(-2, 3, 3, 1, 5, 3, FUR)

		local head = pet:limb("Head", { 0, 7, 1 })
		head:box(-3, 7, -1, 2, 12, 4, FUR)
		-- Fluffy cheeks.
		head:box(-4, 7, 0, 3, 9, 3, FUR)
		head:paint(-1, 9, 4, 0, 9, 4, PINK)
		head:box(-1, 7, 5, 0, 7, 5, SHINE)
		head:paintPair(2, 8, 3, 3, 8, 3, PINK)
		eyes(head, 1, 10, 4)
		-- Tall ears, pink inside, fawn at the tips.
		head:boxPair(1, 13, 1, 3, 18, 2, FUR)
		head:paintPair(2, 14, 2, 2, 17, 2, PINK)
		head:paintPair(1, 18, 1, 3, 18, 2, FAWN)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 3, 2 }, function(leg)
			leg:box(1, 0, 1, 2, 2, 2, FUR)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2.5, 4, -2 }, function(leg)
			leg:box(1, 1, -3, 3, 4, -1, FUR)
			-- Long hind feet.
			leg:box(1, 0, -3, 3, 0, 1, FUR)
		end)

		local tail = pet:limb("Tail", { 0, 4, -3 })
		tail:box(-1, 3, -5, 0, 5, -4, FUR)

		pet:seat(0, 7, -1)
	end,
}

Designs.Hedgehog = {
	name = "Hedgehog",
	skeleton = "LowSlung",
	scale = 0.65,
	draw = function(pet)
		local SPINE = rgb(112, 76, 48)
		local TIP = rgb(180, 140, 100)
		local FACE = rgb(234, 200, 156)

		-- A round dome of spines, with lighter spikes sticking out.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 1, -4, 3, 5, 3, SPINE)
		body:box(-3, 6, -3, 2, 7, 2, SPINE)
		body:boxPair(4, 2, -2, 4, 2, -2, TIP)
		body:boxPair(4, 4, 0, 4, 4, 0, TIP)
		body:boxPair(3, 6, -2, 3, 6, -2, TIP)
		body:boxPair(2, 8, 0, 2, 8, 0, TIP)
		body:boxPair(1, 8, -3, 1, 8, -3, TIP)
		body:boxPair(2, 4, -5, 2, 4, -5, TIP)
		body:boxPair(0, 2, -5, 0, 2, -5, TIP)
		body:boxPair(1, 6, -4, 1, 6, -4, TIP)
		body:boxPair(4, 3, -3, 4, 3, -3, TIP)
		body:boxPair(3, 7, 0, 3, 7, 0, TIP)
		body:boxPair(0, 8, 1, 0, 8, 1, TIP)
		body:box(-2, 8, -2, -1, 8, -1, rgb(132, 202, 92))
		body:box(-2, 9, -2, -2, 9, -2, rgb(84, 150, 62))

		-- A pointed little face poking out of the front.
		local head = pet:limb("Head", { 0, 3, 4 })
		head:box(-2, 1, 4, 1, 4, 6, FACE)
		head:box(-1, 1, 7, 0, 2, 7, FACE)
		head:box(-1, 2, 8, 0, 2, 8, EYE)
		head:paintPair(1, 3, 6, 1, 3, 6, EYE)
		head:paintPair(1, 2, 6, 1, 2, 6, rgb(255, 172, 188))
		head:boxPair(1, 5, 4, 1, 5, 4, FACE)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2.5, 1, 2.5 }, function(leg)
			leg:box(2, 0, 2, 2, 0, 2, FACE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2.5, 1, -2.5 }, function(leg)
			leg:box(2, 0, -3, 2, 0, -3, FACE)
		end)

		local tail = pet:limb("Tail", { 0, 2, -4 })
		tail:box(-1, 1, -5, 0, 1, -5, FACE)

		pet:seat(0, 8, -1)
	end,
}

Designs.Fox = {
	name = "Fox",
	skeleton = "Quadruped",
	scale = 0.5,
	draw = function(pet)
		local ORANGE = rgb(232, 118, 46)
		local WHITE = rgb(248, 242, 230)
		local DARK = rgb(64, 42, 32)

		local body = pet:limb("Body", { 0, 5, 0 })
		body:box(-3, 3, -4, 2, 7, 3, ORANGE)
		body:paint(-2, 3, 3, 1, 6, 3, WHITE)
		body:box(-1, 4, 4, 0, 6, 4, WHITE)

		local head = pet:limb("Head", { 0, 7, 3 })
		head:box(-3, 7, 2, 2, 12, 7, ORANGE)
		-- White cheeks and a pointed muzzle with a dark nose.
		head:paint(-3, 7, 7, 2, 8, 7, WHITE)
		head:box(-1, 7, 8, 0, 8, 9, WHITE)
		head:box(-1, 8, 10, 0, 8, 10, DARK)
		eyes(head, 1, 9, 7, 1)
		-- Big pointed ears with dark tips.
		head:boxPair(1, 13, 4, 2, 14, 5, ORANGE)
		head:paintPair(1, 13, 5, 1, 14, 5, WHITE)
		head:boxPair(2, 15, 4, 2, 15, 5, DARK)
		head:boxPair(3, 7, 5, 3, 8, 6, WHITE)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 4, 2 }, function(leg)
			leg:box(1, 0, 1, 2, 3, 2, ORANGE)
			leg:paint(1, 0, 1, 2, 1, 2, DARK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2, 4, -3 }, function(leg)
			leg:box(1, 0, -4, 2, 3, -3, ORANGE)
			leg:paint(1, 0, -4, 2, 1, -3, DARK)
		end)

		-- A long bushy tail with a white tip.
		local tail = pet:limb("Tail", { 0, 6, -4 })
		tail:box(-2, 5, -7, 1, 7, -5, ORANGE)
		tail:box(-3, 3, -9, 2, 6, -8, ORANGE)
		tail:box(-2, 2, -11, 1, 4, -10, WHITE)

		pet:seat(0, 8, -1)
	end,
}

Designs.Owl = {
	name = "Owl",
	skeleton = "Winged",
	gait = "Waddle",
	scale = 0.42 * 0.8,
	-- Its wings hang folded at its sides: they turn out this far to fly.
	wingSpread = 1.35,
	draw = function(pet)
		-- Sculpted finer than it is drawn (blocks 0.8 of a unit across), with feathers, beak, brows and eyes of
		-- parts at any angle, so it keeps its shape however big it is shown.
		local U = 0.8
		local T = inUnits(U)
		local BROWN = look(140, 98, 62)
		local DARK = look(96, 64, 40)
		local LIGHT = look(222, 196, 152)
		local FACE = look(238, 220, 184)
		local RIM = look(104, 68, 42)
		local TALON = look(242, 164, 44)
		local BEAK = rgb(242, 164, 44)
		local RING = rgb(255, 214, 70)
		local CLAW = rgb(60, 44, 34)

		-- A round, fluffy body: a pale chest barred with dark chevrons, speckles over its back.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 9.6, 0 }, { 6, 7.4, 5.6 }), BROWN)
		body:add(ellipsoid({ 0, 7.4, 1 }, { 5.3, 5.4, 4.8 }), BROWN)
		body:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if open(0, 0, 1) and z > 1.4 and math.abs(x) < 4.6 then
				if y > 3 and y < 14.5 and (y + math.abs(x) * 0.7) % 2.6 < 0.7 then
					return DARK
				end
				return LIGHT
			end
			if noise(p) < 0.12 then
				return LIGHT
			end
			return nil
		end)

		-- A big round head: a pale facial disc in a dark rim, huge ringed eyes under frowning brows, a hooked
		-- beak and tall ear tufts.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 20, 0.3 }, { 6.6, 5.7, 5.4 }), BROWN)
		head:add(ellipsoid({ 0, 17.4, 0.4 }, { 5.2, 3, 4.6 }), BROWN)
		head:coat(function(p, open)
			local x, y = p[1], p[2]
			if open(0, 0, 1) or p[3] > 3.2 then
				local near = math.min((x - 2.3) ^ 2 + ((y - 20) * 1.1) ^ 2, (x + 2.3) ^ 2 + ((y - 20) * 1.1) ^ 2)
				if near < 3.3 ^ 2 then
					return FACE
				elseif near < 4.2 ^ 2 then
					return RIM
				end
			end
			if open(0, 1, 0) and noise(p) < 0.18 then
				return LIGHT
			end
			return nil
		end)

		-- Fluffy legs and orange feet, each with three toes and dark talons.
		local leg = newSculpt(U)
		leg:add(ellipsoid({ 2.4, 3.2, 1.2 }, { 1.7, 2.1, 1.7 }), LIGHT)
		leg:add(rod({ { 2.4, 1.7, 1.5, 0.9 }, { 2.4, 1, 2.2, 0.75 } }), TALON)
		for _, dx in { -0.8, 0, 0.8 } do
			leg:add(rod({ { 2.4 + dx * 0.4, 0.9, 2, 0.62 }, { 2.4 + dx * 1.5, 0.7, 3.8, 0.55 } }), TALON)
		end

		-- Folded wings at its sides: barred coverts over long barred flight feathers.
		local covert = newSculpt(U)
		covert:add(ellipsoid({ 5.9, 10.6, -0.6 }, { 1.3, 5.2, 4.2 }), BROWN)
		covert:coat(function(p)
			if p[2] < 12.5 and math.floor((p[2] + 30) / 2.2) % 2 == 0 then
				return LIGHT
			end
			return nil
		end)

		local legMirror, covertMirror = leg:mirror(), covert:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 6, 0 })), { head, leg, legMirror, covert, covertMirror }, BROWN)
		local headLimb = pet:limb("Head", T.at({ 0, 15.5, 0 }))
		head:draw(headLimb, { body }, BROWN)
		for _, s in { 1, -1 } do
			local face = frontOf(head, 2.3 * s, 20.4)
			T.ball(headLimb, { 2.3 * s, 20.4, face - 0.15 }, { 3, 3, 0.8 }, RING)
			T.ball(headLimb, { 2.3 * s, 20.3, face + 0.1 }, { 2.1, 2.1, 0.7 }, EYE)
			T.ball(headLimb, { 2.05 * s, 20.9, face + 0.42 }, { 0.6, 0.6, 0.3 }, SHINE)
			T.blade(
				headLimb,
				{ 0.6 * s, 22.3, face + 0.1 },
				{ 4 * s, 23.5, face - 0.8 },
				0.8,
				0.6,
				{ 0, 0, 1 },
				DARK.color
			)
			T.taper(headLimb, { 3.6 * s, 24, -0.4 }, { 5.8 * s, 28.8, -1.2 }, 1.5, 0.7, { 0, 0, 1 }, DARK.color)
			T.taper(headLimb, { 3 * s, 24.2, -1.2 }, { 4.5 * s, 27.8, -2.3 }, 1.3, 0.6, { 0, 0, 1 }, BROWN.color)
		end
		local nose = frontOf(head, 0, 19.6)
		T.blade(headLimb, { 0, 19.9, nose - 0.4 }, { 0, 18.6, nose + 0.8 }, 1.3, 1.2, { 1, 0, 0 }, BEAK)
		T.taper(headLimb, { 0, 18.6, nose + 0.8 }, { 0, 16.9, nose + 0.9 }, 1.1, 1, { 1, 0, 0 }, BEAK)

		pet:limbPair("LeftWing", "RightWing", T.at({ 5, 14.5, 0 }), function(wing)
			covert:draw(wing, { body }, BROWN)
			for index, z in { 2, 0.6, -0.8, -2.2, -3.6 } do
				feather(
					wing,
					T.at({ 6.1, 8, z }),
					{ 0.1, -1, -0.45 - index * 0.06 },
					6.4 / U,
					1.5 / U,
					0.5 / U,
					{ 1, 0, 0 },
					{
						{ color = DARK.color, to = 0.3 },
						{ color = LIGHT.color, to = 0.42 },
						{ color = DARK.color, to = 0.72 },
						{ color = LIGHT.color, to = 0.82 },
						{ color = DARK.color, to = 1 },
					}
				)
			end
		end)
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 2.4, 4, 1.2 }), function(limb)
			leg:draw(limb, { body }, BROWN)
			for _, dx in { -0.8, 0, 0.8 } do
				T.taper(limb, { 2.4 + dx * 1.3, 0.8, 2.9 }, { 2.4 + dx * 1.6, 0.35, 4.7 }, 0.5, 0.45, { 0, 1, 0 }, CLAW)
			end
		end)

		-- A fan of barred tail feathers.
		local tail = pet:limb("Tail", T.at({ 0, 5, -4 }))
		for _, dx in { -2, -1, 0, 1, 2 } do
			feather(
				tail,
				T.at({ dx * 0.6, 5.2, -3.8 }),
				{ dx * 0.35, -0.8, -1 },
				4.6 / U,
				1.5 / U,
				0.5 / U,
				{ 0, 1, -0.6 },
				{
					{ color = DARK.color, to = 0.45 },
					{ color = LIGHT.color, to = 0.6 },
					{ color = DARK.color, to = 1 },
				}
			)
		end

		pet:seat(0, 25.6 / U, -0.5 / U)
	end,
}

Designs.Bear = {
	name = "Bear",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with claws of parts at an angle.
		local U = 1.2
		local T = inUnits(U)
		local FUR = look(142, 94, 58)
		local FUR_DARK = look(112, 72, 44)
		local FUR_LIGHT = look(168, 118, 76)
		local TAN = look(218, 174, 124)
		local NOSE = look(44, 32, 28)
		local HONEY = look(255, 188, 48)
		local HONEY_DARK = look(232, 150, 30)
		local PAD = look(70, 50, 40)
		local CLAW = rgb(236, 226, 206)

		local function fur(p: Vec): Look?
			local n = noise(p)
			if n < 0.1 then
				return FUR_LIGHT
			elseif n > 0.92 then
				return FUR_DARK
			end
			return nil
		end

		-- A big, heavy body with a hump at the shoulders and a pale blaze on its chest.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 13, -1 }, { 7, 7, 11 }), FUR)
		body:add(ellipsoid({ 0, 17, 4 }, { 5.6, 3.6, 5.4 }), FUR)
		body:add(ellipsoid({ 0, 13.5, -8 }, { 6.4, 6.6, 5.6 }), FUR)
		body:coat(function(p, open)
			if open(0, 0, 1) and p[3] > 6 and p[2] < 15 and math.abs(p[1]) < 3.6 then
				return TAN
			end
			return fur(p)
		end)

		-- A broad head with round ears, a pale muzzle and a shiny nose, honey dripping down from its crown.
		local head = newSculpt(U)
		head:add(rod({ { 0, 15, 7, 4.9 }, { 0, 16.6, 11, 4.5 } }), FUR)
		head:add(ellipsoid({ 0, 18.2, 14 }, { 5.3, 4.9, 4.7 }), FUR)
		head:add(ellipsoid({ 0, 16.4, 18.2 }, { 2.9, 2.4, 2.9 }), TAN)
		head:add(ellipsoid({ 0, 17.6, 20.6 }, { 1.5, 1, 1 }), NOSE)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 3.9 * s, 22.6, 12.8 }, { 1.9, 1.9, 1.3 }), FUR)
			head:paint(ellipsoid({ 3.9 * s, 22.6, 13.9 }, { 1.2, 1.2, 0.7 }), TAN, nil, true)
		end
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			-- Honey pooled on its crown, running down in drips.
			if open(0, 1, 0) and y > 21.6 and math.abs(x + 0.6) < 3.2 and z > 11 and z < 17 then
				return HONEY
			end
			for _, drip in { { -2.4, 19.6 }, { -0.6, 18.8 }, { 1.4, 20 } } do
				if math.abs(x - drip[1]) < 0.7 and y > drip[2] and y < 22.6 and z > 15 then
					return if y < drip[2] + 0.9 then HONEY_DARK else HONEY
				end
			end

			return fur(p)
		end)
		head:trace({ { 0, 15.6, 18.6 }, { 0, 15.4, 20.4 } }, { 0, 0, -1 }, NOSE)

		-- Thick legs on broad paws with pale claws.
		local function paw(s: Sculpt, x: number, z: number)
			s:add(ellipsoid({ x, 1.7, z }, { 3, 1.7, 3.3 }), FUR)
		end
		local front = newSculpt(U)
		front:add(rod({ { 4.6, 13, 5, 3.3 }, { 4.9, 6, 6.2, 2.9 }, { 4.9, 2.6, 6.4, 2.8 } }), FUR)
		paw(front, 4.9, 7.4)
		local back = newSculpt(U)
		back:add(ellipsoid({ 4.8, 12.5, -8 }, { 3.8, 5.6, 4.8 }), FUR)
		back:add(rod({ { 5, 9, -9, 3.3 }, { 5, 2.6, -8.2, 2.9 } }), FUR)
		paw(back, 5, -7.2)
		for _, leg in { front, back } do
			leg:coat(function(p, open)
				if open(0, -1, 0) or p[2] < 0.8 then
					return PAD
				end
				return fur(p)
			end)
		end

		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 16, -13.6 }, { 1.6, 1.6, 1.4 }), FUR)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 12, 0 })), { head, front, frontMirror, back, backMirror, tail }, FUR)
		local headLimb = pet:limb("Head", T.at({ 0, 15, 8 }))
		head:draw(headLimb, { body }, FUR)
		roundEyes(headLimb, head, 19.6, 16.6, 1.55)
		local function claws(limb: Limb, x: number, z: number)
			for _, dx in { -1.3, -0.45, 0.45, 1.3 } do
				T.taper(limb, { x + dx, 1.4, z - 1.2 }, { x + dx * 1.1, 0.3, z + 0.9 }, 0.55, 0.5, { 0, 1, 0 }, CLAW)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 4.6, 12, 5 }), function(limb)
			front:draw(limb, { body }, FUR)
			claws(limb, 4.9, 10.6)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4.8, 12, -8 }), function(limb)
			back:draw(limb, { body }, FUR)
			claws(limb, 5, -4)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 16, -12.5 })), { body }, FUR)

		pet:seat(0, 21.4 / U, -2 / U)
	end,
}

Designs.MossStag = {
	name = "Moss Stag",
	skeleton = "Quadruped",
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with antlers, ears, mushrooms and
		-- blossoms of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local DEER = look(152, 106, 68)
		local LIGHT = look(232, 206, 162)
		local SPOT = look(250, 240, 226)
		local MOSS = look(86, 146, 66)
		local MOSS_LIGHT = look(140, 196, 96)
		local MOSS_DARK = look(62, 112, 50)
		local HOOF = look(64, 46, 34)
		local NOSE = look(54, 40, 32)
		local WOOD = rgb(168, 126, 82)
		local VINE = rgb(70, 128, 58)
		local CAP = rgb(214, 54, 50)
		local CREAM = rgb(250, 240, 226)
		local PINK = rgb(255, 150, 196)
		local YELLOW = rgb(255, 220, 80)

		local function moss(p: Vec): Look
			local n = noise(p)
			return if n < 0.25 then MOSS_LIGHT elseif n > 0.85 then MOSS_DARK else MOSS
		end
		local function mossEdge(z: number): number
			return 21.4 + 1.3 * math.sin(z * 1.1) + 0.8 * math.sin(z * 2.7 + 1)
		end

		-- A deer's body: a deep chest, a slim middle and a rounded rump, a pale belly and fawn spots, under a
		-- ragged blanket of moss with mounds, mushrooms and blossoms growing in it and vines trailing down.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 20, 5 }, { 5, 5.6, 6.6 }), DEER)
		body:add(ellipsoid({ 0, 19.6, -2 }, { 4.5, 4.8, 6.2 }), DEER)
		body:add(ellipsoid({ 0, 20.2, -8.5 }, { 4.9, 5.2, 5.2 }), DEER)
		body:coat(function(p, open)
			local y, z = p[2], p[3]
			if y > mossEdge(z) and z > -12.5 and z < 9 then
				return moss(p)
			end
			if open(0, -1, 0) and y < 17 then
				return LIGHT
			end
			if (open(1, 0, 0) or open(-1, 0, 0)) and z < -4 and noise(p) < 0.12 then
				return SPOT
			end
			return nil
		end)
		for _, mound in { { 1.6, 2.5 }, { -2, -1.5 }, { 0.8, -6.5 }, { -1.4, 5.5 }, { 2.4, -9.5 } } do
			local x, z = mound[1], mound[2]
			body:add(ellipsoid({ x, topOf(body, z, x) - 0.2, z }, { 1.8, 1, 1.8 }), MOSS_LIGHT)
		end

		-- A strong neck with a pale throat, a soft muzzle with a dark nose, moss on its crown.
		local head = newSculpt(U)
		head:add(rod({ { 0, 22, 8.5, 3.2 }, { 0, 26, 11, 2.5 }, { 0, 28, 12.4, 2.4 } }), DEER)
		head:add(ellipsoid({ 0, 29.2, 13.4 }, { 2.7, 2.6, 3.2 }), DEER)
		head:add(ellipsoid({ 0, 28, 16.6 }, { 1.75, 1.7, 2.3 }), DEER)
		head:coat(function(p, open)
			local y, z = p[2], p[3]
			if z > 18.2 and y > 27.6 then
				return NOSE
			end
			if z > 15.5 and y < 27.4 then
				return LIGHT
			end
			if open(0, -1, 0) and z < 13 then
				return LIGHT
			end
			if open(0, 1, 0) and y > 31.2 then
				return moss(p)
			end
			return nil
		end)

		-- Long legs with knobbly knees, pale cuffs and dark hooves.
		local front = newSculpt(U)
		front:add(rod({ { 3.4, 19, 6, 2.4 }, { 3.6, 10.5, 6.8, 1.35 }, { 3.6, 2.6, 6.4, 1.05 } }), DEER)
		front:add(ellipsoid({ 3.6, 10.6, 6.8 }, { 1.5, 1.4, 1.5 }), DEER)
		front:add(ellipsoid({ 3.6, 1.1, 6.6 }, { 1.3, 1.1, 1.5 }), HOOF)
		local back = newSculpt(U)
		back:add(ellipsoid({ 3.6, 18.8, -8.6 }, { 2.7, 4.8, 3.8 }), DEER)
		back:add(rod({ { 3.8, 15, -10, 1.9 }, { 3.9, 9.5, -11.6, 1.3 }, { 3.9, 2.6, -10, 1.05 } }), DEER)
		back:add(ellipsoid({ 3.9, 1.1, -9.8 }, { 1.3, 1.1, 1.5 }), HOOF)
		for _, leg in { front, back } do
			leg:coat(function(p)
				if p[2] > 2.2 and p[2] < 3.4 then
					return LIGHT
				end
				return nil
			end)
		end

		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 22.4, -13.4 }, { 1.1, 2, 1 }), LIGHT)
		tail:coat(function(_, open)
			return if open(0, 0, -1) then nil else DEER
		end)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 19, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, DEER)
		local headLimb = pet:limb("Head", T.at({ 0, 22, 8.5 }))
		head:draw(headLimb, { body }, DEER)
		roundEyes(headLimb, head, 29.7, 15, 1.1)

		-- Mushrooms, blossoms and trailing vines on its mossy back.
		for _, mushroom in { { 2.6, -4.5, 1 }, { -2.8, 3.5, 0.8 }, { -1, -10, 0.7 } } do
			local x, z, size = mushroom[1], mushroom[2], mushroom[3]
			local y = topOf(body, z, x)
			T.blade(bodyLimb, { x, y - 0.5, z }, { x, y + 1.2 * size, z }, 0.6 * size, 0.6 * size, { 0, 0, 1 }, CREAM)
			T.ball(bodyLimb, { x, y + 1.4 * size, z }, { 2.4 * size, 1.2 * size, 2.4 * size }, CAP)
			T.ball(bodyLimb, { x + 0.5 * size, y + 1.9 * size, z + 0.3 }, 0.45 * size, CREAM)
			T.ball(bodyLimb, { x - 0.4 * size, y + 1.85 * size, z - 0.5 * size }, 0.4 * size, CREAM)
		end
		for index, flower in { { -1.4, 0 }, { 2, 6 }, { -2.6, -7 }, { 0.4, -3 }, { 1.2, -12 } } do
			local x, z = flower[1], flower[2]
			T.ball(bodyLimb, { x, topOf(body, z, x) + 0.1, z }, 1, if index % 2 == 0 then YELLOW else PINK, NEON)
		end
		for _, s in { 1, -1 } do
			for _, z in { 3, -5.5 } do
				local edge = mossEdge(z)
				local x = sideOf(body, edge - 0.6, z) * s
				T.branch(
					bodyLimb,
					{ { x, edge, z }, { x + 0.3 * s, edge - 3, z + 0.3 }, { x + 0.1 * s, edge - 5.4, z } },
					0.5,
					{ 1, 0, 0 },
					VINE
				)
			end
		end

		-- Great branching antlers of wood, mossy and in bloom, with a vine hanging from one tine; ears like leaves.
		for _, s in { 1, -1 } do
			T.taper(headLimb, { 2.2 * s, 30.4, 12.4 }, { 5.4 * s, 31.6, 11.6 }, 1.7, 0.5, { 0, 0, 1 }, DEER.color)
			T.taper(headLimb, { 2.4 * s, 30.5, 12.6 }, { 4.9 * s, 31.4, 11.9 }, 1, 0.55, { 0, 0, 1 }, LIGHT.color)
			local base, p1, p2, p3 =
				{ 1.5 * s, 31, 12.6 }, { 3.4 * s, 34.6, 11.4 }, { 5.4 * s, 38.4, 10.6 }, { 6.4 * s, 41.8, 9.6 }
			local tip = { 6.6 * s, 45, 10.2 }
			T.branch(headLimb, { base, p1, p2, p3, tip }, 1.2, { 0, 0, 1 }, WOOD)
			local tines = {
				{ p1, { 4.2 * s, 37.6, 14 } },
				{ p2, { 8.8 * s, 40.8, 11.2 } },
				{ p2, { 5.6 * s, 42.4, 7.2 } },
				{ p3, { 9.6 * s, 44.6, 9.2 } },
			}
			for _, tine in tines do
				T.taper(headLimb, tine[1], tine[2], 0.85, 0.85, { 0, 0, 1 }, WOOD)
			end
			T.ball(headLimb, vlerp(p1, p2, 0.5), { 1.5, 1.1, 1.5 }, MOSS.color)
			T.ball(headLimb, vlerp(base, p1, 0.6), { 1.2, 0.9, 1.2 }, MOSS_LIGHT.color)
			T.ball(headLimb, vlerp(p3, tip, 0.3), { 1.1, 0.9, 1.1 }, MOSS.color)
			T.ball(headLimb, tines[4][2], 1, PINK, NEON)
			T.ball(headLimb, tines[1][2], 0.9, YELLOW, NEON)
			T.ball(headLimb, tip, 0.9, PINK, NEON)
			T.ball(headLimb, tines[3][2], 0.8, YELLOW, NEON)
			local hang = vlerp(p2, tines[2][2], 0.55)
			T.branch(
				headLimb,
				{ hang, vadd(hang, { -0.4 * s, -3, 0.3 }), vadd(hang, { -0.2 * s, -5.4, 0 }) },
				0.4,
				{ 0, 0, 1 },
				VINE
			)
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.4, 18, 6 }), function(limb)
			front:draw(limb, { body }, DEER)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3.6, 18, -8.6 }), function(limb)
			back:draw(limb, { body }, DEER)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 22, -12.5 })), { body }, DEER)

		pet:light(rgb(140, 220, 110), 1.8, 16)
		pet:seat(0, 25.5 / U, -2 / U)
	end,
}

Designs.Treant = {
	name = "Treant",
	skeleton = "Biped",
	gait = "Stomp",
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with twigs, branches, eyes,
		-- blossoms and fruit of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local BARK = look(112, 78, 48)
		local BARK_DARK = look(78, 52, 32)
		local BARK_LIGHT = look(138, 100, 64)
		local HOLLOW = look(36, 24, 16)
		local SAP = look(196, 255, 110, NEON)
		local MOSS = look(96, 156, 70)
		local LEAF = look(132, 202, 92)
		local LEAF_DARK = look(74, 140, 60)
		local LEAF_LIGHT = look(172, 226, 122)
		local VINE = rgb(70, 128, 58)
		local PINK = rgb(255, 150, 196)
		local CAP = rgb(214, 54, 50)
		local SPOT = rgb(250, 240, 226)

		local function bark(p: Vec): Look?
			local n = noise(p)
			if n < 0.1 then
				return BARK_LIGHT
			elseif n > 0.9 then
				return BARK_DARK
			end
			return nil
		end

		-- A hunched trunk, narrow at the hips and broad at the shoulders, with a face: a heavy brow and a hollow
		-- mouth glowing deep inside. Grooved bark, cracks of glowing sap, moss on its shoulders.
		local body = newSculpt(U)
		body:add(rod({ { 0, 12.5, 0, 5 }, { 0, 21, 0.2, 5.4 }, { 0, 28, -0.4, 6.6 } }), BARK)
		body:add(ellipsoid({ 0, 29.5, -0.4 }, { 8.4, 4.2, 5.8 }), BARK)
		body:add(rod({ { -4.8, 27.6, 4.8, 1.6 }, { 0, 26.4, 6.3, 1.7 }, { 4.8, 27.6, 4.8, 1.6 } }), BARK_DARK)
		body:carve(ellipsoid({ 0, 20.4, 6.4 }, { 3.2, 2.2, 2.6 }))
		body:paint(ellipsoid({ 0, 20.4, 6.4 }, { 3.8, 2.8, 3.2 }), HOLLOW, nil, true)
		body:add(ellipsoid({ 0, 20.2, 3.6 }, { 1.6, 1.1, 0.9 }), SAP)
		body:coat(function(p, open)
			if open(0, 1, 0) and p[2] > 30.5 then
				return if noise(p) < 0.3 then LEAF_DARK else MOSS
			end
			return bark(p)
		end)
		for _, groove in { { -2.8, 0 }, { 2.2, 0 } } do
			body:trace(
				{ { groove[1], 31, 0 }, { groove[1] + 0.5, 21, 0 }, { groove[1] - 0.2, 10, 0 } },
				{ 0, 0, 1 },
				BARK_DARK
			)
		end
		for _, s in { 1, -1 } do
			body:trace({ { 0, 31, 2 }, { 0, 20, 1.4 }, { 0, 10, 1.8 } }, { -s, 0, 0 }, BARK_DARK)
			body:trace({ { 0, 30, -2.4 }, { 0, 19, -2 }, { 0, 10, -2.6 } }, { -s, 0, 0 }, BARK_DARK)
		end
		local cracks = {
			{ { { -3.2, 16.4, 0 }, { -2.2, 14.4, 0 }, { -3.2, 12.6, 0 }, { -2.2, 10, 0 } }, { 0, 0, -1 } },
			{ { { 2.6, 16.6, 0 }, { 1.6, 14.8, 0 }, { 2.8, 13, 0 }, { 2, 11, 0 } }, { 0, 0, -1 } },
			{ { { -1, 25, 0 }, { 0.4, 21.5, 0 }, { -0.8, 17.4, 0 }, { 0.4, 14, 0 } }, { 0, 0, 1 } },
			{ { { 0, 27, 2 }, { 0, 24, 0.4 }, { 0, 21.6, 1.6 }, { 0, 18.4, 0.2 } }, { -1, 0, 0 } },
			{ { { 0, 25, -1.4 }, { 0, 22, 0.2 }, { 0, 19.4, -1 } }, { 1, 0, 0 } },
		}
		for _, crack in cracks do
			body:trace(crack[1], crack[2], SAP)
		end

		-- A crown of leaves: billowing clumps, dark underneath, with branches poking through, blossoms, and glowing
		-- fruit hanging below.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 36.5, -0.4 }, { 8.6, 4.8, 7.2 }), LEAF)
		head:add(ellipsoid({ -5.2, 38.6, 1 }, { 5, 4, 5 }), LEAF)
		head:add(ellipsoid({ 5, 38.2, -1.8 }, { 5.2, 4.2, 5 }), LEAF)
		head:add(ellipsoid({ 0, 41.2, -1 }, { 6.2, 3.8, 5.6 }), LEAF)
		head:add(ellipsoid({ -1.6, 44, 0.4 }, { 3.8, 2.6, 3.4 }), LEAF)
		head:add(ellipsoid({ 2.6, 43.4, -2.4 }, { 3, 2.4, 3 }), LEAF)
		head:add(ellipsoid({ 0, 33, -0.4 }, { 4.6, 2.4, 4 }), BARK)
		head:coat(function(p, open)
			if p[2] < 33.6 then
				return nil
			end
			if open(0, -1, 0) then
				return LEAF_DARK
			end
			local n = noise(p)
			if n < 0.2 then
				return LEAF_LIGHT
			elseif n > 0.8 then
				return LEAF_DARK
			end
			return nil
		end)

		-- Long branch arms reaching down, a tuft of leaves at each shoulder, moss on the forearm, twig claws.
		local arm = newSculpt(U)
		arm:add(
			rod({ { 6.8, 29.6, -0.4, 2.6 }, { 9.6, 23, 0.4, 1.9 }, { 10.2, 16, 1.4, 1.5 }, { 9.9, 12, 2.2, 1.2 } }),
			BARK
		)
		arm:add(ellipsoid({ 8.2, 31.6, -0.4 }, { 2.8, 1.9, 2.8 }), LEAF)
		arm:coat(function(p, open)
			if p[2] > 30.5 then
				return if noise(p) < 0.3 then LEAF_LIGHT else nil
			end
			if open(0, 1, 0) and p[2] < 24 and p[2] > 15 then
				return MOSS
			end
			return bark(p)
		end)

		-- Thick legs spreading into roots over the ground, moss on the roots.
		local leg = newSculpt(U)
		leg:add(rod({ { 3.4, 13, 0, 3.4 }, { 3.8, 6, 0.3, 3.1 }, { 4, 3.6, 0.5, 3.4 } }), BARK)
		for _, root in { { 8.8, 3.6 }, { 3.4, 6.8 }, { 8.2, -4.4 }, { 2, -5.6 } } do
			local mid = { (4 + root[1]) / 2, 1.6, (0.5 + root[2]) / 2 }
			leg:add(
				rod({ { 4, 2.6, 0.5, 2.2 }, { mid[1], mid[2], mid[3], 1.3 }, { root[1], 0.7, root[2], 0.6 } }),
				BARK_DARK
			)
		end
		leg:coat(function(p, open)
			if open(0, 1, 0) and p[2] < 3.4 and noise(p) < 0.45 then
				return MOSS
			end
			return bark(p)
		end)

		local legMirror, armMirror = leg:mirror(), arm:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 14, 0 }))
		body:draw(bodyLimb, { head, leg, legMirror, arm, armMirror }, BARK)
		-- Glowing slit eyes under the brow, slanting down to the middle.
		for _, s in { 1, -1 } do
			local z = frontOf(body, 2.6 * s, 23.4) + 0.12
			T.blade(bodyLimb, { 0.8 * s, 23.2, z }, { 2.8 * s, 23.8, z - 0.2 }, 1.9, 0.5, { 0, 0, 1 }, SAP.color, NEON)
			T.taper(
				bodyLimb,
				{ 2.8 * s, 23.8, z - 0.2 },
				{ 4.8 * s, 24.9, z - 1.1 },
				1.9,
				0.5,
				{ 0, 0, 1 },
				SAP.color,
				NEON
			)
		end
		-- Red mushrooms growing out of its side.
		for _, mushroom in { { -1, 17, 1.2 }, { -1, 13.6, 0.9 }, { 1, 22.4, 0.8 } } do
			local s, y, size = mushroom[1], mushroom[2], mushroom[3]
			local x = sideOf(body, y, 0) * s
			T.blade(
				bodyLimb,
				{ x - 0.4 * s, y, 0.4 },
				{ x + 0.9 * s * size, y + 0.3, 0.4 },
				0.6 * size,
				0.6 * size,
				{ 0, 1, 0 },
				SPOT
			)
			T.ball(bodyLimb, { x + 1 * s * size, y + 0.5, 0.4 }, { 1.4 * size, 0.9 * size, 2.4 * size }, CAP)
			T.ball(bodyLimb, { x + 1.3 * s * size, y + 0.85, 0.9 }, 0.4 * size, SPOT)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 32, 0 }))
		head:draw(headLimb, { body, arm, armMirror }, BARK)
		for _, branch in
			{
				{ { -1, 35, 0 }, { -3.6, 43, 0.6 }, { -6.4, 47.6, 1.4 } },
				{ { 1, 35, -1 }, { 4.4, 42.6, -2.8 }, { 7, 46.4, -3.6 } },
				{ { 0, 35, -2 }, { 0.6, 42, -5.4 }, { 1.4, 44.4, -8.2 } },
			}
		do
			T.branch(headLimb, branch, 1.3, { 0, 0, 1 }, BARK.color)
			T.ball(headLimb, branch[3], { 3.2, 2, 3 }, LEAF.color)
			T.ball(headLimb, vadd(branch[3], { 0.6, 0.8, 0.6 }), 0.9, PINK)
		end
		for _, flower in { { -4, 2 }, { 3, 2.6 }, { -6.6, -2 }, { 5.6, -4.4 }, { 0, 3.4 }, { -1.6, -5.2 }, { 2.4, -1 } } do
			local x, z = flower[1], flower[2]
			T.ball(headLimb, { x, topOf(head, z, x) - 0.1, z }, 1.1, PINK)
		end
		for _, fruit in { { -6.4, 2 }, { 6.6, -2.6 }, { -2.6, -6.4 }, { 3.6, 5 }, { -4.6, -4.2 } } do
			local x, z = fruit[1], fruit[2]
			local y = bottomOf(head, z, x)
			T.blade(headLimb, { x, y + 0.6, z }, { x, y - 1.2, z }, 0.3, 0.3, { 0, 0, 1 }, VINE)
			T.ball(headLimb, { x, y - 1.8, z }, 1.4, SAP.color, NEON)
		end

		pet:limbPair("LeftArm", "RightArm", T.at({ 7.6, 29, -0.4 }), function(limb)
			arm:draw(limb, { body, head }, BARK)
			for _, twig in
				{
					{ { 9.9, 12.6, 2.2 }, { 10.6, 9.4, 3.2 }, { 11.2, 7.8, 4.6 } },
					{ { 9.6, 12.4, 2.6 }, { 9.2, 9, 4 }, { 8.8, 7.6, 5.4 } },
					{ { 10.2, 12.4, 1.6 }, { 11.6, 9.6, 1.4 }, { 12.6, 8.2, 1.8 } },
				}
			do
				T.branch(limb, twig, 0.8, { 1, 0, 0 }, BARK_DARK.color)
			end
			T.branch(limb, { { 10, 21, 1.4 }, { 10.7, 17.4, 2.4 }, { 10.4, 14.4, 2.2 } }, 0.4, { 0, 0, 1 }, VINE)
		end)
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 3.6, 13, 0 }), function(limb)
			leg:draw(limb, { body }, BARK)
		end)

		pet:light(SAP.color, 2.2, 18)
		pet:particles("Sparkles", SAP.color, 10)
		pet:seat(0, 46.6 / U, -0.5 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Desert

Designs.Meerkat = {
	name = "Meerkat",
	skeleton = "Biped",
	scale = 0.5,
	draw = function(pet)
		local FUR = rgb(214, 178, 124)
		local LIGHT = rgb(240, 218, 172)
		local DARK = rgb(92, 66, 44)

		-- Standing up on lookout, with its long tail for balance.
		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-2, 4, -2, 1, 10, 1, FUR)
		body:paint(-1, 4, 1, 0, 9, 1, LIGHT)
		body:paint(-2, 9, -2, 1, 9, -2, DARK)
		body:paint(-2, 7, -2, 1, 7, -2, DARK)
		body:paint(-2, 5, -2, 1, 5, -2, DARK)
		body:box(-1, 4, -4, 0, 5, -3, FUR)
		body:box(-1, 1, -5, 0, 4, -5, FUR)
		body:box(-1, 0, -7, 0, 1, -5, FUR)
		body:box(-1, 0, -8, 0, 0, -8, DARK)

		local head = pet:limb("Head", { 0, 10, 0 })
		head:box(-2, 11, -2, 1, 14, 2, FUR)
		head:box(-1, 11, 3, 0, 12, 3, LIGHT)
		head:box(-1, 12, 4, 0, 12, 4, DARK)
		-- Dark patches round its eyes, and little round ears.
		head:paintPair(1, 12, 2, 1, 13, 2, DARK)
		head:paintPair(1, 13, 2, 1, 13, 2, EYE)
		head:paintPair(1, 13, 2, 1, 13, 2, SHINE)
		head:boxPair(2, 13, 0, 2, 13, 0, DARK)

		-- Paws held up in front of its chest.
		pet:limbPair("LeftArm", "RightArm", { 2.5, 9, 0.5 }, function(arm)
			arm:box(2, 7, 0, 2, 9, 1, FUR)
			arm:box(1, 7, 2, 2, 7, 2, DARK)
		end)
		pet:limbPair("LeftLeg", "RightLeg", { 1, 4, 0 }, function(leg)
			leg:box(0, 0, -1, 1, 3, 0, FUR)
			leg:box(0, 0, 1, 1, 0, 1, DARK)
		end)

		pet:seat(0, 15, 0)
	end,
}

Designs.Armadillo = {
	name = "Armadillo",
	skeleton = "LowSlung",
	scale = 0.75,
	draw = function(pet)
		local SHELL = rgb(214, 166, 108)
		local BAND = rgb(178, 106, 64)
		local SKIN = rgb(232, 196, 160)
		local DARK = rgb(80, 56, 40)

		-- A domed shell with raised bands, like the strata on its egg.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 2, -5, 3, 5, 4, SHELL)
		body:box(-3, 6, -4, 2, 7, 3, SHELL)
		for _, z in { -3, -1, 1 } do
			body:box(-5, 3, z, 4, 6, z, BAND)
			body:box(-4, 7, z, 3, 8, z, BAND)
			body:paintPair(4, 5, z, 4, 5, z, SHELL)
			body:paint(-1, 8, z, 0, 8, z, SHELL)
		end
		body:paint(-4, 2, -5, 3, 2, 4, BAND)

		-- A long pointed snout, upright ears and a little armoured cap.
		local head = pet:limb("Head", { 0, 3, 5 })
		head:box(-2, 2, 5, 1, 5, 7, SKIN)
		head:box(-1, 2, 8, 0, 3, 9, SKIN)
		head:box(-1, 3, 10, 0, 3, 10, DARK)
		head:paint(-2, 5, 5, 1, 5, 7, SHELL)
		head:paintPair(1, 4, 7, 1, 4, 7, EYE)
		head:boxPair(1, 6, 5, 1, 7, 5, SKIN)
		head:paintPair(1, 6, 5, 1, 7, 5, rgb(246, 166, 170))

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 2, 3 }, function(leg)
			leg:box(2, 0, 2, 3, 1, 3, SKIN)
			leg:paint(2, 0, 3, 3, 0, 3, DARK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 2, -3 }, function(leg)
			leg:box(2, 0, -4, 3, 1, -3, SKIN)
			leg:paint(2, 0, -3, 3, 0, -3, DARK)
		end)

		-- A banded tail.
		local tail = pet:limb("Tail", { 0, 3, -5 })
		tail:box(-1, 2, -7, 0, 3, -6, SHELL)
		tail:box(-1, 1, -9, 0, 2, -8, BAND)
		tail:box(-1, 1, -10, 0, 1, -10, SHELL)

		pet:seat(0, 9, -1)
	end,
}

Designs.FennecFox = {
	name = "Fennec Fox",
	skeleton = "Quadruped",
	scale = 0.55,
	draw = function(pet)
		local CREAM = rgb(246, 230, 198)
		local GINGER = rgb(228, 160, 94)
		local PINK = rgb(246, 160, 170)
		local DARK = rgb(70, 48, 36)

		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-2, 3, -3, 1, 6, 2, GINGER)
		body:paint(-1, 3, 2, 0, 5, 2, CREAM)

		local head = pet:limb("Head", { 0, 6, 2 })
		head:box(-3, 6, 1, 2, 10, 5, CREAM)
		head:paint(-3, 10, 1, 2, 10, 5, GINGER)
		head:box(-1, 6, 6, 0, 7, 7, CREAM)
		head:box(-1, 7, 8, 0, 7, 8, DARK)
		eyes(head, 1, 8, 5, 1)
		-- Enormous ears, pink inside, leaning out.
		head:boxPair(1, 11, 2, 3, 13, 3, GINGER)
		head:boxPair(2, 14, 2, 4, 15, 3, GINGER)
		head:boxPair(3, 16, 2, 4, 16, 3, GINGER)
		head:paintPair(2, 12, 3, 2, 13, 3, PINK)
		head:paintPair(3, 14, 3, 3, 15, 3, PINK)
		head:paintPair(2, 11, 3, 2, 11, 3, CREAM)
		head:boxPair(3, 6, 4, 3, 7, 5, CREAM)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 1.5, 3, 1.5 }, function(leg)
			leg:box(1, 0, 1, 1, 2, 1, CREAM)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 1.5, 3, -2.5 }, function(leg)
			leg:box(1, 0, -3, 1, 2, -3, CREAM)
		end)

		local tail = pet:limb("Tail", { 0, 5, -3 })
		tail:box(-1, 4, -6, 0, 6, -4, GINGER)
		tail:box(-1, 3, -8, 0, 5, -7, GINGER)
		tail:box(-1, 3, -9, 0, 4, -9, DARK)

		pet:seat(0, 7, -1)
	end,
}

Designs.Camel = {
	name = "Camel",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.5,
	draw = function(pet)
		local CAMEL = rgb(212, 162, 102)
		local SHAGGY = rgb(160, 112, 62)
		local DARK = rgb(110, 76, 44)
		local LIGHT = rgb(236, 204, 156)
		local LEATHER = rgb(140, 84, 44)
		local RED = rgb(196, 48, 52)
		local GOLD = rgb(255, 196, 56)
		local TEAL = rgb(56, 180, 176)

		-- Two shaggy humps, with the saddle blanket from its egg draped between them, a saddle,
		-- saddlebags and a rolled-up blanket.
		local body = pet:limb("Body", { 0, 9, 0 })
		body:box(-4, 8, -6, 3, 13, 5, CAMEL)
		body:paint(-3, 8, -5, 2, 8, 4, LIGHT)
		body:box(-3, 14, 1, 2, 16, 4, CAMEL)
		body:box(-2, 17, 2, 1, 17, 3, SHAGGY)
		body:paint(-3, 16, 1, 2, 16, 4, SHAGGY)
		body:box(-3, 14, -5, 2, 16, -2, CAMEL)
		body:box(-2, 17, -4, 1, 17, -3, SHAGGY)
		body:paint(-3, 16, -5, 2, 16, -2, SHAGGY)
		body:box(-5, 10, -1, 4, 14, 0, RED)
		body:paint(-5, 10, -1, 4, 10, 0, GOLD)
		body:paint(-5, 12, -1, 4, 12, 0, TEAL)
		body:boxPair(4, 9, -1, 4, 9, 0, GOLD)
		body:boxPair(4, 8, -1, 4, 8, -1, TEAL)
		body:boxPair(4, 8, 0, 4, 8, 0, RED)
		body:box(-2, 15, -1, 1, 15, 0, LEATHER)
		body:box(-1, 16, 0, 0, 16, 0, GOLD)
		body:boxPair(4, 9, -4, 5, 12, -2, LEATHER)
		body:paintPair(5, 12, -4, 5, 12, -2, DARK)
		body:paintPair(5, 11, -3, 5, 11, -3, GOLD)
		body:paintPair(5, 9, -4, 5, 9, -2, RED)
		body:box(-3, 14, -7, 2, 15, -6, TEAL)
		body:paint(-3, 14, -7, 2, 15, -7, GOLD)

		-- A long neck with a shaggy throat and a bell, sleepy eyes, a split lip, and a red bridle with gold rings.
		local head = pet:limb("Head", { 0, 12, 5 })
		head:box(-2, 10, 6, 1, 13, 8, CAMEL)
		head:box(-2, 9, 7, 1, 9, 8, SHAGGY)
		head:paint(-2, 13, 6, 1, 13, 8, SHAGGY)
		head:box(-1, 11, 9, 0, 12, 9, GOLD)
		head:box(-2, 14, 8, 1, 17, 9, CAMEL)
		head:box(-2, 18, 8, 1, 20, 12, CAMEL)
		head:box(-1, 21, 9, 0, 21, 10, SHAGGY)
		head:box(-2, 17, 13, 1, 18, 14, LIGHT)
		head:box(-1, 16, 13, 0, 16, 14, LIGHT)
		head:paintPair(1, 18, 14, 1, 18, 14, DARK)
		head:paint(-1, 17, 14, 0, 17, 14, DARK)
		head:paintPair(1, 19, 12, 1, 19, 12, EYE)
		head:paintPair(1, 20, 12, 1, 20, 12, DARK)
		head:boxPair(1, 21, 8, 1, 21, 8, CAMEL)
		head:paint(-2, 18, 13, 1, 18, 13, RED)
		head:paintPair(1, 19, 11, 1, 19, 11, GOLD)
		head:box(-1, 21, 11, 0, 22, 11, RED)
		head:box(-1, 23, 11, 0, 23, 11, GOLD)

		-- Long legs with knobbly knees and wide padded feet.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 8, 3.5 }, function(leg)
			leg:box(2, 4, 3, 3, 7, 4, CAMEL)
			leg:box(2, 1, 3, 3, 3, 4, CAMEL)
			leg:box(2, 0, 3, 3, 0, 5, DARK)
			leg:paint(2, 4, 4, 3, 4, 4, DARK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 8, -4.5 }, function(leg)
			leg:box(2, 4, -5, 3, 7, -4, CAMEL)
			leg:box(2, 1, -5, 3, 3, -4, CAMEL)
			leg:box(2, 0, -5, 3, 0, -3, DARK)
			leg:paint(2, 4, -4, 3, 4, -4, DARK)
		end)

		local tail = pet:limb("Tail", { 0, 12, -6 })
		tail:box(-1, 9, -7, 0, 12, -7, CAMEL)
		tail:box(-1, 7, -7, 0, 8, -7, SHAGGY)

		pet:seat(0, 16, -1)
	end,
}

Designs.GiantScorpion = {
	name = "Giant Scorpion",
	skeleton = "ManyLegged",
	scale = 0.5,
	draw = function(pet)
		-- Sculpted in the units it is built in (one to a block); legs, pincer fingers and stinger are parts at any
		-- angle, so they stay sharp however big it is shown.
		local U = 1
		local T = inUnits(U)
		local AMBER = look(176, 98, 44)
		local DARK = look(112, 58, 28)
		local LIGHT = look(214, 140, 70)
		local BELLY = look(226, 170, 104)
		local VENOM = look(150, 255, 90, NEON)
		local CLAW = rgb(70, 36, 18)

		-- A low body armoured in overlapping plates, dark at the seams, a pale ridge down the middle.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 4.4, 3 }, { 4.4, 2.2, 3.4 }), AMBER)
		local plates = { { -0.6, 5 }, { -3.2, 5.2 }, { -5.8, 5 }, { -8.4, 4.5 }, { -10.6, 3.8 } }
		for _, plate in plates do
			body:add(ellipsoid({ 0, 4.6, plate[1] }, { plate[2], 2.4, 1.7 }), AMBER)
		end
		body:coat(function(p, open)
			local x, z = p[1], p[3]
			if open(0, -1, 0) then
				return BELLY
			end
			for _, plate in plates do
				if math.abs(z - (plate[1] + 1.35)) < 0.45 then
					return DARK
				end
			end
			if math.abs(x) < 0.8 and open(0, 1, 0) then
				return LIGHT
			end
			return nil
		end)

		-- A flat head with great pincers on jointed arms, and small dark mouthparts.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 4.4, 6.6 }, { 3.4, 1.9, 2.4 }), AMBER)
		for _, s in { 1, -1 } do
			head:add(
				rod({ { 2.4 * s, 4.2, 7.4, 1.15 }, { 5.4 * s, 4.8, 9.6, 1.1 }, { 6.4 * s, 4.8, 12.6, 1.15 } }),
				AMBER
			)
			head:add(ellipsoid({ 5.4 * s, 4.8, 9.6 }, { 1.4, 1.3, 1.4 }), DARK)
			head:add(ellipsoid({ 6.4 * s, 4.9, 14.8 }, { 1.9, 1.6, 2.7 }), AMBER)
			head:add(ellipsoid({ 0.7 * s, 3.8, 8.9 }, { 0.65, 0.65, 0.75 }), DARK)
		end
		head:coat(function(p, open)
			if open(0, -1, 0) then
				return BELLY
			end
			if open(0, 1, 0) and noise(p) < 0.18 then
				return LIGHT
			end
			return nil
		end)

		-- A segmented tail curling up over its back, dark at every joint, to a glowing venom bulb and stinger.
		local tail = newSculpt(U)
		local segments = {
			{ 0, 4.8, -11.6, 1.75 },
			{ 0, 6.8, -14.1, 1.6 },
			{ 0, 9.8, -15.4, 1.5 },
			{ 0, 12.9, -14.7, 1.4 },
			{ 0, 15.1, -12.3, 1.3 },
			{ 0, 15.9, -9.6, 1.25 },
		}
		for index = 1, #segments - 1 do
			local a, b = segments[index], segments[index + 1]
			tail:add(rod({ { a[1], a[2], a[3], a[4] * 0.7 }, { b[1], b[2], b[3], b[4] * 0.7 } }), DARK)
		end
		for _, c in segments do
			tail:add(ellipsoid({ c[1], c[2], c[3] }, { c[4], c[4], c[4] }), AMBER)
		end
		tail:add(ellipsoid({ 0, 15.3, -7.3 }, { 1.5, 1.7, 2 }), VENOM)

		body:draw(pet:limb("Body", T.at({ 0, 4, 0 })), { head, tail }, AMBER)
		local headLimb = pet:limb("Head", T.at({ 0, 4.2, 5 }))
		head:draw(headLimb, { body }, AMBER)
		for _, s in { 1, -1 } do
			T.taper(headLimb, { 6 * s, 5.3, 16.4 }, { 5.1 * s, 5.5, 19.8 }, 1.1, 1, { 0, 1, 0 }, AMBER.color)
			T.taper(headLimb, { 6.9 * s, 4.5, 16.4 }, { 6.7 * s, 4, 19.4 }, 1, 0.9, { 0, 1, 0 }, DARK.color)
			T.ball(headLimb, { 0.55 * s, topOf(head, 6.4, 0.55 * s) - 0.05, 6.4 }, 0.65, EYE)
			T.ball(headLimb, { 2.6 * s, topOf(head, 7.8, 2.6 * s) - 0.2, 7.8 }, 0.45, EYE)
		end
		T.ball(headLimb, { 0, topOf(head, 5.4, 0) - 0.1, 5.4 }, { 0.9, 0.5, 1.6 }, VENOM.color, NEON)

		local function leg(z: number, spread: number)
			return function(limb: Limb)
				local hip, knee = { 4, 4.2, z }, { 7, 6.8, z + spread * 0.5 }
				local ankle, foot = { 9.4, 3, z + spread }, { 10.2, 0.2, z + spread * 1.4 }
				T.blade(limb, hip, knee, 1, 1, { 0, 0, 1 }, AMBER.color)
				T.blade(limb, knee, ankle, 0.9, 0.9, { 0, 0, 1 }, AMBER.color)
				T.taper(limb, ankle, foot, 0.8, 0.8, { 0, 0, 1 }, DARK.color)
				T.ball(limb, knee, 1.3, DARK.color)
				T.ball(limb, ankle, 1.1, DARK.color)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 4, 4.2, 1.6 }), leg(1.6, 1.2))
		pet:limbPair("MiddleLeftLeg", "MiddleRightLeg", T.at({ 4.4, 4.2, -1.6 }), leg(-1.6, 0))
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4.2, 4.2, -4.8 }), leg(-4.8, -1.2))

		local tailLimb = pet:limb("Tail", T.at({ 0, 4.6, -11 }))
		tail:draw(tailLimb, { body }, AMBER)
		T.taper(tailLimb, { 0, 14.7, -5.8 }, { 0, 12.2, -3.8 }, 0.9, 0.9, { 1, 0, 0 }, CLAW)
		T.ball(tailLimb, { 0, 11.9, -3.6 }, 0.55, VENOM.color, NEON)

		pet:seat(0, 7.4 / U, -3 / U)
	end,
}

Designs.PharaohJackal = {
	name = "Pharaoh Jackal",
	skeleton = "Quadruped",
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with ears, eyes and its cobra crown
		-- of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local BLACK = look(38, 34, 42)
		local SHEEN = look(68, 62, 80)
		local NOSE = look(20, 18, 22)
		local GOLD = look(255, 196, 56)
		local LAPIS = look(40, 86, 196)
		local TEAL = look(56, 180, 176)
		local RED = rgb(196, 48, 52)

		local function sheen(p: Vec): Look?
			return if noise(p) < 0.12 then SHEEN else nil
		end
		local function jewels(v: number, period: number): Look
			local k = math.floor(v / period) % 4
			return if k == 0 then LAPIS elseif k == 2 then TEAL else GOLD
		end
		local function stripes(v: number, period: number): Look
			return if math.floor(v / period) % 2 == 0 then LAPIS else GOLD
		end

		-- A sleek black body with a broad jewelled collar over its chest and a gold belt.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 16.5, 4 }, { 4, 4.8, 5.2 }), BLACK)
		body:add(ellipsoid({ 0, 16, -2 }, { 3.4, 3.8, 5 }), BLACK)
		body:add(ellipsoid({ 0, 16.6, -7.5 }, { 3.8, 4.2, 4.2 }), BLACK)
		body:add(ellipsoid({ 0, 18.2, 7.2 }, { 4.6, 3.6, 3.3 }), GOLD)
		body:coat(function(p)
			local x, y, z = p[1], p[2], p[3]
			if (x / 4.7) ^ 2 + ((y - 18.2) / 3.7) ^ 2 + ((z - 7.2) / 3.4) ^ 2 <= 1.05 then
				return jewels(math.sqrt((y - 21.8) ^ 2 + ((z - 8.6) * 0.8) ^ 2), 0.75)
			end
			if z > -3.6 and z < -1.8 then
				return if math.abs(z + 2.7) < 0.35 then LAPIS else GOLD
			end
			return sheen(p)
		end)

		-- A long, narrow head: striped headdress lappets down each side of its neck, a gold band round its brow.
		local head = newSculpt(U)
		head:add(rod({ { 0, 18.5, 7.5, 2.8 }, { 0, 22.2, 9.2, 2.3 } }), BLACK)
		head:add(ellipsoid({ 0, 24, 10.4 }, { 2.6, 2.6, 3 }), BLACK)
		head:add(ellipsoid({ 0, 23.1, 14.2 }, { 1.3, 1.4, 3.3 }), BLACK)
		head:add(ellipsoid({ 0, 23.6, 17.3 }, { 0.75, 0.65, 0.55 }), NOSE)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 2.7 * s, 21.2, 8.6 }, { 0.95, 3.4, 1.9 }), GOLD)
		end
		head:coat(function(p)
			local x, y, z = p[1], p[2], p[3]
			if ((math.abs(x) - 2.7) / 1) ^ 2 + ((y - 21.2) / 3.45) ^ 2 + ((z - 8.6) / 1.95) ^ 2 <= 1 then
				return stripes(y, 0.8)
			end
			if y > 25.4 and z > 9.6 and z < 11.4 then
				return GOLD
			end
			return sheen(p)
		end)

		-- Slender legs with gold and lapis anklets.
		local front = newSculpt(U)
		front:add(rod({ { 2.8, 15, 5, 1.8 }, { 3, 8, 5.6, 1.25 }, { 3, 2, 5.4, 1 } }), BLACK)
		front:add(ellipsoid({ 3, 0.9, 6.2 }, { 1.25, 0.9, 1.6 }), BLACK)
		local back = newSculpt(U)
		back:add(ellipsoid({ 2.8, 15.6, -7.6 }, { 2.1, 3.8, 3 }), BLACK)
		back:add(rod({ { 3, 12, -9, 1.45 }, { 3.1, 7, -10.2, 1.05 }, { 3.1, 2, -9, 0.95 } }), BLACK)
		back:add(ellipsoid({ 3.1, 0.9, -8.4 }, { 1.25, 0.9, 1.6 }), BLACK)
		for _, leg in { front, back } do
			leg:coat(function(p)
				if p[2] > 2.6 and p[2] < 4.4 then
					return if p[2] < 3.2 then LAPIS else GOLD
				end
				return sheen(p)
			end)
		end

		-- A long tail hanging low, banded in gold.
		local tail = newSculpt(U)
		tail:add(
			rod({ { 0, 18, -10.6, 1.25 }, { 0, 15, -13, 1.1 }, { 0, 10.4, -13.8, 0.9 }, { 0, 6.6, -13.2, 0.7 } }),
			BLACK
		)
		tail:coat(function(p)
			if p[2] < 14 and math.floor(p[2] / 1.6) % 2 == 0 then
				return GOLD
			end
			return sheen(p)
		end)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 16, 0 })), { head, front, frontMirror, back, backMirror, tail }, BLACK)
		local headLimb = pet:limb("Head", T.at({ 0, 18.5, 7.5 }))
		head:draw(headLimb, { body }, BLACK)
		slitEyes(headLimb, head, { 24.5, 12.6 }, { 25.1, 10.6 }, 0.6, GOLD.color, NEON)
		for _, s in { 1, -1 } do
			T.triangle(
				headLimb,
				{ 1.1 * s, 25.8, 11.4 },
				{ 2.5 * s, 31.6, 9.8 },
				{ 2.5 * s, 25.4, 9 },
				0.6,
				BLACK.color
			)
			T.triangle(
				headLimb,
				{ 1.4 * s, 26.4, 11.4 },
				{ 2.4 * s, 30.6, 10.3 },
				{ 2.35 * s, 26.2, 9.9 },
				0.35,
				GOLD.color
			)
		end
		T.branch(headLimb, { { 0, 26.2, 12.2 }, { 0, 27.6, 12.8 }, { 0, 28.4, 12.4 } }, 0.65, { 0, 0, 1 }, GOLD.color)
		T.ball(headLimb, { 0, 27.4, 13.2 }, { 1, 1.1, 0.5 }, GOLD.color)
		T.ball(headLimb, { 0, 27.6, 13.4 }, 0.45, RED)
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 2.8, 15, 5 }), function(limb)
			front:draw(limb, { body }, BLACK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 2.8, 15, -7.6 }), function(limb)
			back:draw(limb, { body }, BLACK)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 18, -10 })), { body }, BLACK)

		pet:light(GOLD.color, 1.8, 14)
		pet:seat(0, 21 / U, -2 / U)
	end,
}

Designs.Sphinx = {
	name = "Sphinx",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with wings, eyes and crown of parts
		-- at any angle.
		local U = 1.2
		local T = inUnits(U)
		local STONE = look(226, 192, 124)
		local STONE_LIGHT = look(242, 216, 164)
		local STONE_DARK = look(184, 148, 88)
		local CARVING = look(146, 112, 62)
		local GOLD = look(255, 196, 56)
		local LAPIS = look(40, 86, 196)
		local TEAL = look(56, 180, 176)
		local GLOW = rgb(90, 240, 220)

		local function weathered(p: Vec): Look?
			local n = noise(p)
			if n < 0.1 then
				return STONE_LIGHT
			elseif n > 0.9 then
				return STONE_DARK
			end
			return nil
		end
		local function stripes(v: number, period: number): Look
			return if math.floor(v / period) % 2 == 0 then GOLD else LAPIS
		end

		-- A lion's body of carved sandstone: a deep chest under a jewelled collar, carved ribs, weathered speckles.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 16, 4.5 }, { 5, 5.4, 5.6 }), STONE)
		body:add(ellipsoid({ 0, 15.6, -2 }, { 4.3, 4.4, 5.2 }), STONE)
		body:add(ellipsoid({ 0, 16.2, -8 }, { 4.6, 5, 4.6 }), STONE)
		body:coat(function(p, open)
			local y, z = p[2], p[3]
			if z > 6.6 and y > 14 and open(0, 0, 1) then
				local k = math.floor(y - 14) % 3
				return if k == 0 then GOLD elseif k == 1 then TEAL else LAPIS
			end
			if open(0, -1, 0) then
				return STONE_DARK
			end
			return weathered(p)
		end)
		for _, s in { 1, -1 } do
			for _, z in { 1, -1.6, -4.2 } do
				body:trace({ { 0, 18.4, z }, { 0, 15.4, z - 0.6 }, { 0, 12.6, z - 0.2 } }, { -s, 0, 0 }, CARVING)
			end
		end

		-- A pharaoh's head: a calm stone face framed by a striped headdress, a long striped beard, glowing eyes
		-- lined in kohl, and a cobra rearing at its brow.
		local head = newSculpt(U)
		head:add(rod({ { 0, 18.5, 7.6, 3 }, { 0, 22, 9.4, 2.6 } }), STONE)
		head:add(ellipsoid({ 0, 26.4, 9.8 }, { 4.2, 3.6, 3.6 }), GOLD)
		head:carve(ellipsoid({ 0, 24.6, 13.8 }, { 2.7, 3.2, 2.7 }))
		head:add(ellipsoid({ 0, 24.6, 11 }, { 2.8, 3.2, 2.9 }), STONE)
		head:add(ellipsoid({ 0, 24.4, 13.7 }, { 0.6, 0.95, 0.7 }), STONE)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 3.1 * s, 21.6, 11 }, { 0.85, 3.6, 1.15 }), GOLD)
		end
		head:add(rod({ { 0, 22, 12.4, 0.95 }, { 0, 19, 13, 0.8 } }), GOLD)
		head:coat(function(p)
			local x, y, z = p[1], p[2], p[3]
			if math.abs(x) < 1.1 and y < 22.2 and z > 11.6 then
				return stripes(y, 0.6)
			end
			local face = (x / 2.85) ^ 2 + ((y - 24.6) / 3.25) ^ 2 + ((z - 11) / 2.95) ^ 2 <= 1
				or (x / 0.65) ^ 2 + ((y - 24.4) / 1) ^ 2 + ((z - 13.7) / 0.75) ^ 2 <= 1
			if not face and y > 17.5 then
				if y > 26.4 and z > 10.6 and z < 12.6 then
					return GOLD
				end
				return stripes(y, 0.85)
			end
			return weathered(p)
		end)

		-- Lion's legs on big paws, carved toes and gold anklets.
		local front = newSculpt(U)
		front:add(rod({ { 3.4, 14.5, 5.4, 2.4 }, { 3.6, 8, 6.2, 1.9 }, { 3.6, 2.6, 6.4, 1.8 } }), STONE)
		front:add(ellipsoid({ 3.6, 1.5, 7.6 }, { 2.1, 1.5, 2.6 }), STONE)
		local back = newSculpt(U)
		back:add(ellipsoid({ 3.6, 15.2, -8 }, { 2.8, 4.6, 3.8 }), STONE)
		back:add(rod({ { 3.8, 11, -9.6, 2 }, { 3.9, 6, -10.6, 1.5 }, { 3.9, 2.6, -9.6, 1.6 } }), STONE)
		back:add(ellipsoid({ 3.9, 1.5, -8.6 }, { 2, 1.5, 2.4 }), STONE)
		for _, leg in { front, back } do
			leg:coat(function(p)
				if p[2] > 3.4 and p[2] < 4.8 then
					return if p[2] < 4 then LAPIS else GOLD
				end
				return weathered(p)
			end)
		end
		for _, dx in { -0.7, 0.7 } do
			front:trace({ { 3.6 + dx, 2.8, 0 }, { 3.6 + dx, 0.4, 0 } }, { 0, 0, -1 }, CARVING)
		end

		-- A lion's tail curling up at the end into a tuft.
		local tail = newSculpt(U)
		tail:add(
			rod({ { 0, 18, -12, 1.15 }, { 0, 15, -14.6, 1 }, { 0, 11, -15.6, 0.85 }, { 0, 9.4, -14, 0.75 } }),
			STONE
		)
		tail:add(ellipsoid({ 0, 9.8, -12.6 }, { 1.3, 1.5, 1.5 }), STONE_DARK)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 16, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, STONE)
		-- Stone wings folded up over its back like a fan, long feathers inlaid with teal and gold at their tips.
		for _, s in { 1, -1 } do
			T.triangle(bodyLimb, { 3.2 * s, 21.2, 4.6 }, { 4.6 * s, 27, -6.5 }, { 4.2 * s, 19.6, -7 }, 0.9, STONE.color)
			for index = 0, 6 do
				local t = index / 6
				local root = vlerp({ 3.3 * s, 21.6, 4.4 }, { 3.9 * s, 20.4, -2 }, t)
				local direction = { 0.12 * s, 0.62 - t * 0.6, -1 }
				local length = 11.5 - index * 0.35
				feather(bodyLimb, T.at(root), direction, length / U, 2.5 / U, 0.6 / U, { s, 0.3, 0 }, {
					{ color = STONE_LIGHT.color, to = 0.7 },
					{ color = TEAL.color, to = 0.85 },
					{ color = GOLD.color, to = 1 },
				})
			end
			for index = 0, 3 do
				local root = vlerp({ 3.1 * s, 22.2, 4.8 }, { 3.5 * s, 21.6, 0.4 }, index / 3)
				feather(
					bodyLimb,
					T.at(root),
					{ 0.1 * s, 0.5 - index * 0.1, -1 },
					5.4 / U,
					2.4 / U,
					0.7 / U,
					{ s, 0.3, 0 },
					{
						{ color = STONE.color, to = 0.78 },
						{ color = LAPIS.color, to = 1 },
					}
				)
			end
		end
		local headLimb = pet:limb("Head", T.at({ 0, 18.5, 7.6 }))
		head:draw(headLimb, { body }, STONE)
		for _, s in { 1, -1 } do
			local z = frontOf(head, 1.15 * s, 25.4)
			T.blade(headLimb, { 0.45 * s, 25.4, z - 0.15 }, { 2.1 * s, 25.6, z - 0.45 }, 0.95, 0.4, { 0, 0, 1 }, EYE)
			T.taper(headLimb, { 2.1 * s, 25.6, z - 0.45 }, { 2.9 * s, 25.4, z - 0.9 }, 0.95, 0.4, { 0, 0, 1 }, EYE)
			T.blade(
				headLimb,
				{ 0.65 * s, 25.4, z - 0.05 },
				{ 1.9 * s, 25.55, z - 0.3 },
				0.6,
				0.4,
				{ 0, 0, 1 },
				GLOW,
				NEON
			)
			T.blade(
				headLimb,
				{ 0.4 * s, 26.5, z - 0.2 },
				{ 2.4 * s, 26.6, z - 0.6 },
				0.35,
				0.4,
				{ 0, 0, 1 },
				CARVING.color
			)
		end
		local chin = frontOf(head, 0, 23)
		T.blade(headLimb, { -0.8, 22.9, chin - 0.1 }, { 0.8, 22.9, chin - 0.1 }, 0.3, 0.3, { 0, 0, 1 }, CARVING.color)
		T.branch(headLimb, { { 0, 27.8, 12.4 }, { 0, 29, 13 }, { 0, 29.8, 12.6 } }, 0.7, { 0, 0, 1 }, GOLD.color)
		T.ball(headLimb, { 0, 29, 13.3 }, { 1.2, 1.3, 0.5 }, GOLD.color)
		T.ball(headLimb, { 0, 29.2, 13.5 }, 0.55, GLOW, NEON)
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.4, 14.5, 5.4 }), function(limb)
			front:draw(limb, { body }, STONE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3.6, 15, -8 }), function(limb)
			back:draw(limb, { body }, STONE)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 18, -11.5 })), { body }, STONE)

		pet:light(GOLD.color, 2, 16)
		pet:particles("Sparkles", GOLD.color, 8)
		pet:seat(0, 21.4 / U, -3 / U)
	end,
}

Designs.GoldenScarab = {
	name = "Golden Scarab",
	skeleton = "ManyLegged",
	scale = 0.5,
	draw = function(pet)
		-- Sculpted in the units it is built in (one to a block); wings, legs, the rake of its head and the rays of
		-- its sun are parts at any angle.
		local U = 1
		local T = inUnits(U)
		local SCARAB = look(240, 186, 50)
		local GOLD_LIGHT = look(255, 224, 120)
		local BRONZE = look(196, 128, 38)
		local BRONZE_DARK = look(120, 76, 24)
		local TEAL = look(56, 180, 176)
		local LAPIS = look(40, 86, 196)
		local SEAM = look(86, 56, 20)
		local SUN = rgb(255, 196, 60)
		local SUN_CORE = rgb(255, 240, 170)

		-- A domed golden shell banded in teal and lapis enamel, split by a dark seam, behind a bronze shield.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 5.6, -2.4 }, { 5.4, 3.8, 6 }), SCARAB)
		body:add(ellipsoid({ 0, 5.2, 4.2 }, { 4.4, 2.8, 2.6 }), BRONZE)
		body:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if z < 1.7 then
				if math.abs(x) < 0.55 and open(0, 1, 0) then
					return SEAM
				end
				if math.abs(z + 0.7) < 0.55 then
					return TEAL
				elseif math.abs(z + 3.9) < 0.55 then
					return LAPIS
				elseif math.abs(z + 6.6) < 0.45 then
					return TEAL
				end
				if open(0, -1, 0) then
					return BRONZE_DARK
				end
				return if noise(p) < 0.1 then GOLD_LIGHT else nil
			end
			if y > 6.8 or (math.abs(x) > 3.6 and open(0, 1, 0)) then
				return SCARAB
			end
			return nil
		end)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 4.4, 7.3 }, { 2.9, 1.8, 1.9 }), BRONZE_DARK)

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 4, -7.6, 1.4 }, { 0, 3.4, -9.4, 0.9 } }), BRONZE)

		local bodyLimb = pet:limb("Body", T.at({ 0, 4.5, 0 }))
		body:draw(bodyLimb, { head, tail }, SCARAB)
		-- Jewelled wings spread out at its sides: long feathers banded in lapis, teal and gold.
		for _, s in { 1, -1 } do
			for index, tip in { { 13.4, 6.8, 0.4 }, { 13.8, 6.2, -2.4 }, { 13, 5.6, -5 }, { 11.4, 5.2, -7.4 } } do
				local root = { 4.4 * s, 5.8, 0.2 - index * 0.9 }
				local target = { tip[1] * s, tip[2], tip[3] }
				local d = vsub(target, root)
				feather(bodyLimb, T.at(root), d, vlength(d) / U, (2 - index * 0.15) / U, 0.5 / U, { 0, 1, 0 }, {
					{ color = LAPIS.color, to = 0.4 },
					{ color = TEAL.color, to = 0.62 },
					{ color = SCARAB.color, to = 0.86 },
					{ color = GOLD_LIGHT.color, to = 1 },
				})
			end
			T.triangle(bodyLimb, { 4.2 * s, 6, 1.6 }, { 9.4 * s, 7, 0.6 }, { 4.4 * s, 5.6, -2.6 }, 0.7, SCARAB.color)
		end
		-- A bronze head with dark eyes and a rake of golden teeth, pushing a blazing sun.
		local headLimb = pet:limb("Head", T.at({ 0, 4.4, 6 }))
		head:draw(headLimb, { body }, SCARAB)
		for _, s in { 1, -1 } do
			T.ball(headLimb, { 2.6 * s, 4.7, 7.6 }, 0.95, EYE)
			for _, tooth in { 0.5, 1.5, 2.4 } do
				T.taper(
					headLimb,
					{ tooth * s, 4.2, 8.6 },
					{ tooth * 1.15 * s, 4, 10.2 },
					0.7,
					0.5,
					{ 0, 1, 0 },
					GOLD_LIGHT.color
				)
			end
			T.branch(
				headLimb,
				{ { 1.6 * s, 5.4, 8.2 }, { 2.8 * s, 6.8, 9.4 }, { 3.6 * s, 7.4, 9.8 } },
				0.4,
				{ 0, 0, 1 },
				BRONZE.color
			)
			T.ball(headLimb, { 3.7 * s, 7.5, 9.9 }, 0.7, BRONZE.color)
		end
		T.blade(headLimb, { 0, 5.4, 7.4 }, { 0, 8.4, 8.4 }, 0.8, 0.8, { 0, 0, 1 }, BRONZE.color)
		T.ball(headLimb, { 0, 10.4, 8.8 }, { 5, 5, 1.4 }, SUN, NEON)
		T.ball(headLimb, { 0, 10.4, 9.4 }, { 3, 3, 0.8 }, SUN_CORE, NEON)
		for ray = 0, 7 do
			local angle = ray * math.pi / 4
			local out = { math.cos(angle), math.sin(angle), 0 }
			T.taper(
				headLimb,
				vadd({ 0, 10.4, 8.8 }, vscale(out, 2.2)),
				vadd({ 0, 10.4, 8.8 }, vscale(out, 4.4)),
				0.8,
				0.4,
				{ 0, 0, 1 },
				SUN,
				NEON
			)
		end

		local function leg(z: number, spread: number)
			return function(limb: Limb)
				local hip, knee = { 4, 4.2, z }, { 6.8, 5.6, z + spread * 0.5 }
				local ankle, foot = { 8.6, 2.6, z + spread }, { 9.4, 0.25, z + spread * 1.5 }
				T.blade(limb, hip, knee, 1.1, 0.9, { 0, 1, 0 }, BRONZE_DARK.color)
				T.blade(limb, knee, ankle, 1, 0.8, { 0, 0, 1 }, BRONZE.color)
				T.taper(limb, ankle, foot, 0.8, 0.7, { 0, 0, 1 }, BRONZE_DARK.color)
				T.taper(
					limb,
					vlerp(knee, ankle, 0.5),
					vadd(vlerp(knee, ankle, 0.5), { 1, 0.6, 0.3 }),
					0.4,
					0.3,
					{ 0, 0, 1 },
					GOLD_LIGHT.color
				)
				T.ball(limb, knee, 1.1, SCARAB.color)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 4, 4.2, 3.6 }), leg(3.6, 1.4))
		pet:limbPair("MiddleLeftLeg", "MiddleRightLeg", T.at({ 4.4, 4.2, -0.6 }), leg(-0.6, 0))
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4.2, 4.2, -4.4 }), leg(-4.4, -1.4))
		tail:draw(pet:limb("Tail", T.at({ 0, 4, -7.4 })), { body }, SCARAB)

		pet:light(SUN, 2.4, 16)
		pet:particles("Sparkles", SUN, 10)
		pet:seat(0, 9.6 / U, -2.4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Snow

Designs.SnowHare = {
	name = "Snow Hare",
	skeleton = "Quadruped",
	gait = "Hop",
	scale = 0.45,
	draw = function(pet)
		local WHITE = rgb(246, 250, 255)
		local SHADE = rgb(214, 228, 244)
		local FROST = rgb(170, 210, 245)
		local TIP = rgb(44, 46, 58)
		local PINK = rgb(255, 172, 188)

		-- A round white body with frosty shading, a fluffy chest and a puffed-up back.
		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-3, 2, -3, 2, 6, 2, WHITE)
		body:box(-2, 7, -2, 1, 7, 1, WHITE)
		body:box(-2, 3, 3, 1, 5, 3, WHITE)
		body:paint(-3, 2, -3, 2, 2, 2, SHADE)
		body:paintPair(2, 3, -3, 2, 4, -1, SHADE)

		-- Fluffy cheeks, a frost mark on its forehead, and long ears with black tips.
		local head = pet:limb("Head", { 0, 7, 1 })
		head:box(-3, 8, -1, 2, 12, 4, WHITE)
		head:box(-4, 8, 0, 3, 9, 3, WHITE)
		head:paint(-1, 9, 4, 0, 9, 4, PINK)
		head:box(-1, 8, 5, 0, 8, 5, SHINE)
		head:paint(-1, 11, 4, 0, 12, 4, FROST)
		head:paintPair(2, 8, 3, 3, 8, 3, PINK)
		eyes(head, 1, 10, 4, 1)
		head:boxPair(1, 13, 1, 2, 18, 2, WHITE)
		head:paintPair(1, 14, 2, 1, 17, 2, FROST)
		head:boxPair(1, 19, 1, 2, 19, 2, TIP)
		head:paintPair(1, 18, 1, 2, 18, 2, TIP)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 3, 2 }, function(leg)
			leg:box(1, 0, 1, 2, 2, 2, WHITE)
			leg:paint(1, 0, 2, 2, 0, 2, SHADE)
		end)
		-- Big snowshoe hind feet.
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2.5, 4, -2 }, function(leg)
			leg:box(1, 1, -3, 3, 4, -1, WHITE)
			leg:box(1, 0, -4, 3, 0, 1, WHITE)
			leg:paint(1, 0, 1, 3, 0, 1, SHADE)
		end)

		local tail = pet:limb("Tail", { 0, 4, -3 })
		tail:box(-1, 3, -5, 0, 5, -4, WHITE)
		tail:paint(-1, 3, -5, 0, 3, -4, SHADE)

		pet:seat(0, 8, -1)
	end,
}

Designs.ArcticFox = {
	name = "Arctic Fox",
	skeleton = "Quadruped",
	scale = 0.5,
	draw = function(pet)
		local WHITE = rgb(244, 248, 255)
		local SHADE = rgb(210, 226, 242)
		local ICE = rgb(150, 206, 244)
		local DARK = rgb(40, 44, 56)

		-- A thick white coat with a fluffy ruff, ice-blue socks like the bottom of its egg.
		local body = pet:limb("Body", { 0, 5, 0 })
		body:box(-3, 3, -4, 2, 7, 3, WHITE)
		body:box(-4, 6, 2, 3, 8, 4, WHITE)
		body:box(-2, 3, 4, 1, 5, 4, WHITE)
		body:paint(-3, 3, -4, 2, 3, 3, SHADE)
		body:paint(-2, 7, -4, 1, 7, -1, SHADE)

		local head = pet:limb("Head", { 0, 8, 3 })
		head:box(-3, 8, 2, 2, 12, 7, WHITE)
		head:boxPair(3, 8, 4, 3, 9, 6, WHITE)
		head:box(-1, 8, 8, 0, 9, 9, WHITE)
		head:box(-1, 9, 10, 0, 9, 10, DARK)
		head:paint(-1, 8, 9, 0, 8, 9, SHADE)
		eyes(head, 1, 10, 7, 1)
		-- Short rounded ears, icy inside.
		head:boxPair(1, 13, 4, 2, 14, 5, WHITE)
		head:paintPair(1, 13, 5, 1, 14, 5, ICE)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 4, 2 }, function(leg)
			leg:box(1, 0, 1, 2, 3, 2, WHITE)
			leg:paint(1, 0, 1, 2, 1, 2, ICE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2, 4, -3 }, function(leg)
			leg:box(1, 0, -4, 2, 3, -3, WHITE)
			leg:paint(1, 0, -4, 2, 1, -3, ICE)
		end)

		-- A huge fluffy tail with an ice-blue tip.
		local tail = pet:limb("Tail", { 0, 6, -4 })
		tail:box(-2, 5, -7, 1, 7, -5, WHITE)
		tail:box(-3, 4, -10, 2, 7, -8, WHITE)
		tail:box(-2, 4, -11, 1, 6, -11, WHITE)
		tail:box(-2, 4, -12, 1, 6, -12, ICE)
		tail:paint(-3, 4, -10, 2, 4, -8, SHADE)

		pet:seat(0, 9, -1)
	end,
}

Designs.Reindeer = {
	name = "Reindeer",
	skeleton = "Quadruped",
	scale = 0.5,
	draw = function(pet)
		local FUR = rgb(138, 98, 66)
		local FUR_DARK = rgb(100, 70, 46)
		local CREAM = rgb(236, 226, 206)
		local ANTLER = rgb(214, 196, 160)
		local HOOF = rgb(52, 40, 34)
		local RED = rgb(212, 52, 62)
		local GREEN = rgb(58, 140, 84)
		local KNIT = rgb(246, 238, 222)
		local GOLD = rgb(255, 200, 60)

		-- A sturdy deer with a pale ruff and rump, wearing the knitted blanket from its egg and a belled harness.
		local body = pet:limb("Body", { 0, 8, 0 })
		body:box(-4, 7, 1, 3, 11, 5, FUR)
		body:box(-3, 7, -5, 2, 10, 0, FUR)
		body:box(-4, 7, -8, 3, 11, -6, FUR)
		body:paint(-3, 7, -5, 2, 7, 0, CREAM)
		body:paint(-3, 8, -8, 2, 10, -8, CREAM)
		body:box(-3, 8, 5, 2, 10, 6, CREAM)
		body:box(-2, 7, 6, 1, 7, 6, CREAM)
		body:box(-5, 9, -4, 4, 11, -1, RED)
		body:paint(-5, 10, -4, 4, 10, -1, KNIT)
		body:paintPair(4, 10, -4, 4, 10, -4, GREEN)
		body:paintPair(4, 10, -2, 4, 10, -2, GREEN)
		body:paint(-1, 11, -4, 0, 11, -1, GREEN)
		body:boxPair(4, 8, -4, 4, 8, -4, KNIT)
		body:boxPair(4, 8, -1, 4, 8, -1, KNIT)
		body:paint(-4, 10, 1, 3, 10, 5, RED)
		body:box(-1, 8, 7, 0, 9, 7, GOLD)
		body:boxPair(4, 9, 3, 4, 9, 3, GOLD)

		-- A gentle face and great branching antlers, with a sprig of holly caught in one.
		local head = pet:limb("Head", { 0, 11, 5 })
		head:box(-2, 11, 4, 1, 14, 6, FUR)
		head:box(-3, 14, 5, 2, 17, 9, FUR)
		head:box(-2, 14, 10, 1, 15, 11, CREAM)
		head:box(-1, 15, 12, 0, 15, 12, HOOF)
		head:paint(-3, 17, 9, 2, 17, 9, FUR_DARK)
		eyes(head, 1, 15, 9, 1)
		head:boxPair(3, 16, 6, 4, 16, 7, FUR)
		head:paintPair(3, 16, 7, 4, 16, 7, CREAM)
		head:boxPair(1, 18, 6, 1, 20, 7, ANTLER)
		head:boxPair(1, 19, 8, 1, 19, 9, ANTLER)
		head:boxPair(2, 21, 6, 5, 21, 7, ANTLER)
		head:boxPair(2, 22, 6, 2, 23, 7, ANTLER)
		head:boxPair(5, 22, 6, 5, 22, 7, ANTLER)
		head:boxPair(3, 24, 6, 7, 24, 7, ANTLER)
		head:boxPair(3, 25, 6, 3, 26, 7, ANTLER)
		head:boxPair(5, 25, 6, 5, 26, 7, ANTLER)
		head:boxPair(7, 25, 6, 7, 26, 7, ANTLER)
		head:box(5, 21, 8, 6, 21, 8, GREEN)
		head:box(5, 22, 8, 5, 22, 8, RED)
		head:box(6, 20, 8, 6, 20, 8, RED)

		-- Long legs with shaggy pale fur over wide hooves.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 8, 3.5 }, function(leg)
			leg:box(2, 4, 3, 3, 7, 4, FUR)
			leg:box(2, 1, 3, 3, 3, 4, FUR_DARK)
			leg:paint(2, 1, 3, 3, 1, 4, CREAM)
			leg:box(2, 0, 3, 3, 0, 5, HOOF)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 8, -6.5 }, function(leg)
			leg:box(3, 5, -8, 4, 10, -5, FUR)
			leg:box(2, 1, -7, 3, 4, -6, FUR_DARK)
			leg:paint(2, 1, -7, 3, 1, -6, CREAM)
			leg:box(2, 0, -7, 3, 0, -5, HOOF)
		end)

		local tail = pet:limb("Tail", { 0, 10, -8 })
		tail:box(-1, 9, -9, 0, 11, -9, CREAM)

		pet:seat(0, 12, -2)
	end,
}

Designs.FrostWolf = {
	name = "Frost Wolf",
	skeleton = "Quadruped",
	scale = 0.55,
	draw = function(pet)
		local WOLF = rgb(164, 184, 212)
		local WOLF_DARK = rgb(92, 110, 152)
		local WHITE = rgb(240, 246, 255)
		local ICE = rgb(196, 240, 255)
		local GLOW = rgb(130, 236, 255)
		local NOSE = rgb(36, 40, 56)

		-- A lean wolf with a dark saddle, a white chest, and ice crystals growing along its back.
		local body = pet:limb("Body", { 0, 7, 0 })
		body:box(-4, 6, 1, 3, 11, 5, WOLF)
		body:box(-3, 6, -5, 2, 10, 0, WOLF)
		body:box(-4, 6, -8, 3, 10, -6, WOLF)
		body:paint(-3, 10, -5, 2, 10, 0, WOLF_DARK)
		body:paint(-4, 11, 1, 3, 11, 3, WOLF_DARK)
		body:paint(-4, 10, -8, 3, 10, -6, WOLF_DARK)
		body:paint(-2, 6, 5, 1, 10, 5, WHITE)
		body:paint(-3, 6, -5, 2, 6, 0, WHITE)
		body:box(-1, 12, 1, 0, 14, 2, ICE, GLASS, 0.15)
		body:boxPair(2, 12, 2, 2, 13, 3, ICE, GLASS, 0.15)
		body:box(-1, 11, -2, 0, 12, -2, ICE, GLASS, 0.15)
		body:box(-1, 11, -4, 0, 11, -4, ICE, GLASS, 0.15)
		body:box(-1, 11, -7, 0, 12, -7, ICE, GLASS, 0.15)

		-- A long snout with icy fangs, glowing eyes under a dark brow, and tall ears.
		local head = pet:limb("Head", { 0, 11, 5 })
		head:box(-2, 10, 5, 1, 13, 6, WOLF)
		head:box(-3, 9, 6, 2, 10, 7, WHITE)
		head:box(-3, 13, 5, 2, 17, 9, WOLF)
		head:box(-2, 13, 10, 1, 15, 12, WHITE)
		head:box(-1, 15, 13, 0, 15, 13, NOSE)
		head:paint(-2, 13, 10, 1, 13, 12, WOLF_DARK)
		head:boxPair(1, 12, 12, 1, 12, 12, ICE, GLASS, 0.15)
		head:paintPair(2, 13, 9, 2, 15, 9, WHITE)
		head:paintPair(1, 16, 9, 1, 16, 9, GLOW, NEON)
		head:paintPair(1, 17, 9, 2, 17, 9, WOLF_DARK)
		head:paint(-1, 17, 9, 0, 17, 9, WHITE)
		head:boxPair(1, 18, 6, 2, 19, 7, WOLF)
		head:boxPair(2, 20, 6, 2, 20, 7, WOLF_DARK)
		head:paintPair(1, 18, 7, 1, 19, 7, WHITE)

		-- Legs with white socks and claws of ice.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 7, 3.5 }, function(leg)
			leg:box(2, 3, 3, 3, 6, 4, WOLF)
			leg:box(2, 0, 3, 3, 2, 4, WOLF_DARK)
			leg:paint(2, 0, 3, 3, 1, 4, WHITE)
			leg:box(2, 0, 5, 3, 0, 5, ICE, GLASS, 0.15)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 7, -6.5 }, function(leg)
			leg:box(3, 4, -8, 4, 9, -5, WOLF)
			leg:box(2, 0, -7, 3, 3, -6, WOLF_DARK)
			leg:paint(2, 0, -7, 3, 1, -6, WHITE)
			leg:box(2, 0, -5, 3, 0, -5, ICE, GLASS, 0.15)
		end)

		-- A bushy tail with a white tip and a crust of frost.
		local tail = pet:limb("Tail", { 0, 9, -8 })
		tail:box(-2, 8, -10, 1, 10, -9, WOLF)
		tail:box(-2, 6, -12, 1, 9, -11, WOLF)
		tail:box(-2, 5, -13, 1, 7, -13, WHITE)
		tail:box(-1, 8, -13, 0, 8, -13, ICE, GLASS, 0.15)
		tail:paint(-2, 10, -10, 1, 10, -9, WOLF_DARK)

		pet:seat(0, 12, -2)
	end,
}

Designs.SabertoothCat = {
	name = "Sabertooth Cat",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with fangs, ears, claws and ice
		-- crystals of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local FUR = look(236, 230, 218)
		local SHADE = look(206, 198, 184)
		local STRIPE = look(74, 84, 104)
		local NOSE = look(120, 86, 86)
		local MOUTH = look(60, 50, 56)
		local ICE = look(150, 206, 244)
		local IVORY = rgb(250, 240, 214)
		local CRYSTAL = rgb(196, 240, 255)
		local GLOW = rgb(150, 230, 255)

		local function fur(p: Vec): Look?
			return if noise(p) < 0.1 then SHADE else nil
		end
		local function stripes(s: Sculpt, list: { { Vec } })
			for _, side in { 1, -1 } do
				for _, stripe in list do
					s:trace(stripe, { -side, 0, 0 }, STRIPE)
				end
			end
		end

		-- A powerful pale cat: high shoulders, a slim waist and heavy hips, slate stripes, a pale belly.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 17, 4 }, { 5.4, 5.8, 6 }), FUR)
		body:add(ellipsoid({ 0, 20.4, 3 }, { 4.2, 2.6, 4 }), FUR)
		body:add(ellipsoid({ 0, 16, -3 }, { 4.4, 4.6, 5.4 }), FUR)
		body:add(ellipsoid({ 0, 16.8, -9 }, { 5, 5.2, 4.6 }), FUR)
		body:coat(function(p, open)
			if open(0, -1, 0) and p[2] < 14 then
				return SHADE
			end
			return fur(p)
		end)
		stripes(body, {
			{ { 0, 23, 4.5 }, { 0, 19, 5.6 }, { 0, 16, 5 } },
			{ { 0, 22.6, 1 }, { 0, 18.6, 1.8 }, { 0, 15, 1.2 } },
			{ { 0, 20.6, -2.6 }, { 0, 17, -2 }, { 0, 13.6, -2.6 } },
			{ { 0, 21.4, -6 }, { 0, 17.4, -5.4 }, { 0, 14, -6 } },
			{ { 0, 22, -9.6 }, { 0, 18, -9 }, { 0, 14.6, -9.6 } },
		})
		body:trace({ { 0, 24, 6 }, { 0, 21.6, -12 } }, { 0, -1, 0 }, STRIPE)

		-- A broad head: a heavy brow, cheek ruffs, a pale muzzle, glowing ice eyes, and an ice-blue collar.
		local head = newSculpt(U)
		head:add(rod({ { 0, 18.6, 8, 4.2 }, { 0, 20, 10.4, 3.8 } }), FUR)
		head:add(ellipsoid({ 0, 21.4, 12 }, { 4.3, 3.9, 4 }), FUR)
		head:add(ellipsoid({ 0, 19.6, 15.4 }, { 2.5, 2.1, 2.3 }), FUR)
		head:add(ellipsoid({ 0, 20.5, 17.4 }, { 0.75, 0.5, 0.45 }), NOSE)
		head:add(rod({ { -2.8, 23.2, 14.2, 1.15 }, { 0, 23.6, 14.8, 1.25 }, { 2.8, 23.2, 14.2, 1.15 } }), FUR)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 3.9 * s, 19.8, 11.8 }, { 1.7, 2.3, 2.1 }), SHADE)
		end
		head:add(rod({ { -5, 18.4, 8.4, 1.3 }, { 0, 17.4, 10.6, 1.4 }, { 5, 18.4, 8.4, 1.3 } }), ICE)
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if z > 15.4 and y > 17.7 and y < 18.5 and (open(0, 0, 1) or open(1, 0, 0) or open(-1, 0, 0)) then
				return MOUTH
			end
			if z > 13.6 and y < 20.6 then
				return SHADE
			end
			if open(0, 1, 0) and math.abs(x) < 0.9 and z < 13.6 then
				return STRIPE
			end
			return fur(p)
		end)
		stripes(head, { { { 0, 24.2, 11.6 }, { 0, 21.6, 10.4 } }, { { 0, 23.6, 9.4 }, { 0, 20.6, 8.6 } } })

		-- Thick striped legs on big paws with ivory claws.
		local front = newSculpt(U)
		front:add(rod({ { 3.8, 16, 5, 2.9 }, { 4, 8, 6, 2.3 }, { 4, 3, 6.2, 2.1 } }), FUR)
		front:add(ellipsoid({ 4, 1.6, 7.2 }, { 2.5, 1.6, 2.9 }), FUR)
		local back = newSculpt(U)
		back:add(ellipsoid({ 4, 16, -9 }, { 3.2, 5.2, 4 }), FUR)
		back:add(rod({ { 4.2, 11, -10.6, 2.3 }, { 4.3, 6, -11.6, 1.8 }, { 4.3, 2.8, -10.2, 1.9 } }), FUR)
		back:add(ellipsoid({ 4.3, 1.6, -9.2 }, { 2.4, 1.6, 2.8 }), FUR)
		for _, leg in { front, back } do
			leg:coat(function(p)
				if p[2] > 6 and p[2] < 12 and math.floor(p[2] / 1.8) % 2 == 0 then
					return STRIPE
				end
				return fur(p)
			end)
		end

		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 19.2, -13.4 }, { 1.4, 1.8, 1.8 }), FUR)
		tail:coat(function(p)
			return if p[3] < -14.2 then STRIPE else nil
		end)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 16, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, FUR)
		local headLimb = pet:limb("Head", T.at({ 0, 18.6, 8 }))
		head:draw(headLimb, { body }, FUR)
		-- A hunter's eyes, facing forward: glowing ice in dark rims.
		for _, s in { 1, -1 } do
			local z = frontOf(head, 1.9 * s, 21.9)
			T.blade(
				headLimb,
				{ 0.9 * s, 21.7, z - 0.2 },
				{ 2.4 * s, 22.1, z - 0.6 },
				1.25,
				0.4,
				{ 0, 0, 1 },
				STRIPE.color
			)
			T.taper(
				headLimb,
				{ 2.4 * s, 22.1, z - 0.6 },
				{ 3.4 * s, 22.6, z - 1.3 },
				1.25,
				0.4,
				{ 0, 0, 1 },
				STRIPE.color
			)
			T.blade(
				headLimb,
				{ 1.1 * s, 21.75, z - 0.05 },
				{ 2.4 * s, 22.05, z - 0.45 },
				0.8,
				0.4,
				{ 0, 0, 1 },
				GLOW,
				NEON
			)
			T.taper(
				headLimb,
				{ 2.4 * s, 22.05, z - 0.45 },
				{ 3.1 * s, 22.45, z - 1 },
				0.8,
				0.4,
				{ 0, 0, 1 },
				GLOW,
				NEON
			)
		end
		for _, s in { 1, -1 } do
			T.taper(headLimb, { 1.25 * s, 18.4, 16.2 }, { 1.45 * s, 12.8, 17.2 }, 1, 0.8, { 1, 0, 0 }, IVORY)
			T.triangle(
				headLimb,
				{ 1.6 * s, 24.6, 12.6 },
				{ 3.6 * s, 27.8, 11.2 },
				{ 3.8 * s, 24, 10.4 },
				0.7,
				FUR.color
			)
			T.taper(headLimb, { 3.6 * s, 27.4, 11.2 }, { 3.8 * s, 29.4, 11 }, 0.5, 0.5, { 0, 0, 1 }, STRIPE.color)
			for _, angle in { 0.5, 1.1, 1.8 } do
				local base = { 4.4 * s * math.cos(angle * 0.5), 17.6, 9.6 + math.sin(angle) * 0.8 }
				T.taper(headLimb, base, vadd(base, { 1.2 * s, 1.8, 0.8 }), 0.9, 0.9, { 0, 0, 1 }, CRYSTAL, GLASS)
			end
		end
		T.taper(headLimb, { 0, 17, 11.6 }, { 0, 15.8, 13 }, 1, 1, { 1, 0, 0 }, CRYSTAL, GLASS)
		local function claws(limb: Limb, x: number, z: number)
			for _, dx in { -1.2, -0.4, 0.4, 1.2 } do
				T.taper(limb, { x + dx, 1.4, z - 1.2 }, { x + dx * 1.1, 0.3, z + 0.8 }, 0.5, 0.45, { 0, 1, 0 }, IVORY)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.8, 16, 5 }), function(limb)
			front:draw(limb, { body }, FUR)
			claws(limb, 4, 10)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4, 16, -9 }), function(limb)
			back:draw(limb, { body }, FUR)
			claws(limb, 4.3, -6.4)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 19, -12.5 })), { body }, FUR)

		pet:light(ICE.color, 1.8, 14)
		pet:seat(0, 22.5 / U, -2 / U)
	end,
}

Designs.AuroraOwl = {
	name = "Aurora Owl",
	skeleton = "Winged",
	gait = "Waddle",
	scale = 0.5 * 0.8,
	-- Its wings hang folded at its sides: they turn out this far to fly.
	wingSpread = 1.35,
	draw = function(pet)
		-- Sculpted finer than it is drawn (blocks 0.8 of a unit across), with feathers, beak, brows and eyes of
		-- parts at any angle.
		local U = 0.8
		local T = inUnits(U)
		local NIGHT = look(30, 40, 92)
		local NIGHT_LIGHT = look(52, 66, 132)
		local FEATHER = look(86, 116, 196)
		local CHEST = look(226, 234, 252)
		local MARK = look(160, 182, 228)
		local STAR = look(255, 255, 255, NEON)
		local FACE = look(214, 226, 250)
		local RIM = look(86, 116, 196)
		local TALON = look(240, 200, 120)
		local GREEN = rgb(90, 255, 170)
		local TEAL = rgb(80, 220, 255)
		local VIOLET = rgb(182, 124, 255)
		local BEAK = rgb(240, 200, 120)
		local CLAW = rgb(60, 60, 80)
		local AURORA = {
			{ color = NIGHT_LIGHT.color, to = 0.35 },
			{ color = GREEN, material = NEON, to = 0.55 },
			{ color = TEAL, material = NEON, to = 0.78 },
			{ color = VIOLET, material = NEON, to = 1 },
		}

		-- A night-blue owl with a pale chest marked in chevrons, and a back speckled with stars.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 9.6, 0 }, { 6, 7.4, 5.6 }), NIGHT)
		body:add(ellipsoid({ 0, 7.4, 1 }, { 5.3, 5.4, 4.8 }), NIGHT)
		body:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if open(0, 0, 1) and z > 1.4 and math.abs(x) < 4.6 then
				if y > 3 and y < 14.5 and (y + math.abs(x) * 0.7) % 2.6 < 0.6 then
					return MARK
				end
				return CHEST
			end
			if noise(p) < 0.06 then
				return STAR
			end
			return nil
		end)

		-- A big round head: a pale face disc, glowing teal eyes under brows of violet light, a hooked beak and
		-- tall tufts tipped with the aurora.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 20, 0.3 }, { 6.6, 5.7, 5.4 }), NIGHT)
		head:add(ellipsoid({ 0, 17.4, 0.4 }, { 5.2, 3, 4.6 }), NIGHT)
		head:coat(function(p, open)
			local x, y = p[1], p[2]
			if open(0, 0, 1) or p[3] > 3.2 then
				local near = math.min((x - 2.3) ^ 2 + ((y - 20) * 1.1) ^ 2, (x + 2.3) ^ 2 + ((y - 20) * 1.1) ^ 2)
				if near < 3.3 ^ 2 then
					return FACE
				elseif near < 4.2 ^ 2 then
					return RIM
				end
			end
			if noise(p) < 0.06 then
				return STAR
			end
			return nil
		end)

		local leg = newSculpt(U)
		leg:add(ellipsoid({ 2.4, 3.2, 1.2 }, { 1.7, 2.1, 1.7 }), CHEST)
		leg:add(rod({ { 2.4, 1.7, 1.5, 0.9 }, { 2.4, 1, 2.2, 0.75 } }), TALON)
		for _, dx in { -0.8, 0, 0.8 } do
			leg:add(rod({ { 2.4 + dx * 0.4, 0.9, 2, 0.62 }, { 2.4 + dx * 1.5, 0.7, 3.8, 0.55 } }), TALON)
		end

		local covert = newSculpt(U)
		covert:add(ellipsoid({ 5.9, 10.6, -0.6 }, { 1.3, 5.2, 4.2 }), FEATHER)
		covert:coat(function(p)
			local k = math.floor((p[2] + 30) / 1.6) % 3
			if p[2] < 13 then
				return if k == 0 then look(90, 255, 170, NEON) elseif k == 1 then NIGHT_LIGHT else nil
			end
			return nil
		end)

		local legMirror, covertMirror = leg:mirror(), covert:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 6, 0 })), { head, leg, legMirror, covert, covertMirror }, NIGHT)
		local headLimb = pet:limb("Head", T.at({ 0, 15.5, 0 }))
		head:draw(headLimb, { body }, NIGHT)
		for _, s in { 1, -1 } do
			local face = frontOf(head, 2.3 * s, 20.4)
			T.ball(headLimb, { 2.3 * s, 20.4, face - 0.15 }, { 3, 3, 0.8 }, TEAL, NEON)
			T.ball(headLimb, { 2.3 * s, 20.3, face + 0.1 }, { 2, 2, 0.7 }, NIGHT.color)
			T.ball(headLimb, { 2.05 * s, 20.9, face + 0.42 }, { 0.6, 0.6, 0.3 }, SHINE)
			T.blade(
				headLimb,
				{ 0.6 * s, 22.3, face + 0.1 },
				{ 4 * s, 23.5, face - 0.8 },
				0.8,
				0.6,
				{ 0, 0, 1 },
				VIOLET,
				NEON
			)
			feather(
				headLimb,
				T.at({ 3.6 * s, 24, -0.4 }),
				{ 0.45 * s, 1, -0.2 },
				6 / U,
				1.5 / U,
				0.7 / U,
				{ 0, 0, 1 },
				{
					{ color = NIGHT.color, to = 0.5 },
					{ color = TEAL, material = NEON, to = 0.75 },
					{ color = GREEN, material = NEON, to = 1 },
				}
			)
			feather(
				headLimb,
				T.at({ 3 * s, 24.2, -1.2 }),
				{ 0.35 * s, 1, -0.3 },
				4.6 / U,
				1.3 / U,
				0.6 / U,
				{ 0, 0, 1 },
				{
					{ color = FEATHER.color, to = 0.6 },
					{ color = VIOLET, material = NEON, to = 1 },
				}
			)
		end
		local nose = frontOf(head, 0, 19.6)
		T.blade(headLimb, { 0, 19.9, nose - 0.4 }, { 0, 18.6, nose + 0.8 }, 1.3, 1.2, { 1, 0, 0 }, BEAK)
		T.taper(headLimb, { 0, 18.6, nose + 0.8 }, { 0, 16.9, nose + 0.9 }, 1.1, 1, { 1, 0, 0 }, BEAK)

		-- Folded wings banded with the northern lights.
		pet:limbPair("LeftWing", "RightWing", T.at({ 5, 14.5, 0 }), function(wing)
			covert:draw(wing, { body }, NIGHT)
			for index, z in { 2, 0.6, -0.8, -2.2, -3.6 } do
				feather(
					wing,
					T.at({ 6.1, 8, z }),
					{ 0.1, -1, -0.45 - index * 0.06 },
					6.6 / U,
					1.5 / U,
					0.5 / U,
					{ 1, 0, 0 },
					AURORA
				)
			end
		end)
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 2.4, 4, 1.2 }), function(limb)
			leg:draw(limb, { body }, NIGHT)
			for _, dx in { -0.8, 0, 0.8 } do
				T.taper(limb, { 2.4 + dx * 1.3, 0.8, 2.9 }, { 2.4 + dx * 1.6, 0.35, 4.7 }, 0.5, 0.45, { 0, 1, 0 }, CLAW)
			end
		end)

		-- Long trailing tail feathers, glowing at the tips.
		local tail = pet:limb("Tail", T.at({ 0, 5, -4 }))
		for _, dx in { -2, -1, 0, 1, 2 } do
			local length = 8.5 - math.abs(dx) * 1.2
			feather(
				tail,
				T.at({ dx * 0.6, 5.2, -3.8 }),
				{ dx * 0.3, -0.45, -1 },
				length / U,
				1.5 / U,
				0.5 / U,
				{ 0, 1, -0.4 },
				AURORA
			)
		end

		pet:light(TEAL, 2, 15)
		pet:particles("Sparkles", GREEN, 10)
		pet:seat(0, 25.6 / U, -0.5 / U)
	end,
}

Designs.WoollyMammoth = {
	name = "Woolly Mammoth",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.48 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with tusks, icicles and frost
		-- crystals of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local WOOL = look(120, 78, 48)
		local WOOL_DARK = look(88, 56, 34)
		local WOOL_LIGHT = look(150, 104, 66)
		local SNOW = look(246, 250, 255)
		local SKIN = look(70, 52, 44)
		local IVORY = rgb(250, 240, 214)
		local ICE = rgb(196, 240, 255)

		-- Long hair falls in strands: each column of cells has its own shade, the same all the way down.
		local function wool(p: Vec): Look?
			local n = noise({ math.floor(p[1] / 1.2), 0, math.floor(p[3] / 1.2) })
			if n < 0.22 then
				return WOOL_DARK
			elseif n > 0.82 then
				return WOOL_LIGHT
			end
			return nil
		end

		-- A huge shaggy body with a shoulder hump, a curtain of long hair down its sides, snow on its back.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 17, -1 }, { 7.4, 7.6, 11 }), WOOL)
		body:add(ellipsoid({ 0, 22.6, 4 }, { 5.6, 3.4, 5 }), WOOL)
		body:add(ellipsoid({ 0, 17.2, -8.4 }, { 6.6, 6.6, 5.4 }), WOOL)
		for _, s in { 1, -1 } do
			for z = -9, 7, 2.2 do
				local x = 6.6 * s
				body:add(rod({ { x, 14.4, z, 1.3 }, { x + 0.3 * s, 9.4 + (z % 3) * 0.4, z + 0.4, 0.8 } }), WOOL_DARK)
			end
		end
		body:coat(function(p, open)
			if open(0, 1, 0) and p[2] > 22 then
				return SNOW
			end
			return wool(p)
		end)

		-- A high domed head capped with snow, shaggy bangs, small ears and a long curling trunk.
		local head = newSculpt(U)
		head:add(rod({ { 0, 20, 7, 5 }, { 0, 21, 10, 4.6 } }), WOOL)
		head:add(ellipsoid({ 0, 22, 12.4 }, { 4.6, 5, 4.4 }), WOOL)
		head:add(ellipsoid({ 0, 26.4, 11.6 }, { 3.4, 2.6, 3.2 }), WOOL)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 4.4 * s, 21.6, 10.6 }, { 0.9, 1.8, 1.5 }), WOOL_DARK)
		end
		for _, x in { -2.4, -0.8, 0.8, 2.4 } do
			head:add(rod({ { x, 26, 14.6, 1 }, { x * 1.1, 23.4, 16, 0.7 } }), WOOL_DARK)
		end
		head:add(
			rod({
				{ 0, 20, 16, 2.3 },
				{ 0, 15.5, 18, 1.85 },
				{ 0, 10.5, 18.4, 1.45 },
				{ 0, 7, 17.4, 1.15 },
				{ 0, 5.6, 19, 0.95 },
				{ 0, 6.8, 20.4, 0.85 },
			}),
			WOOL
		)
		head:coat(function(p, open)
			local y, z = p[2], p[3]
			if open(0, 1, 0) and y > 27 then
				return SNOW
			end
			if z > 16.5 and y < 19 then
				return if math.floor(y / 1.4) % 2 == 0 then WOOL_DARK else SKIN
			end
			return wool(p)
		end)

		-- Pillar legs with shaggy cuffs and ivory toenails.
		local function pillar(s: Sculpt, x: number, z: number, top: number)
			s:add(rod({ { x, top, z, 3.4 }, { x, 8, z + 0.4, 3 }, { x, 2.4, z + 0.4, 3 } }), WOOL)
			s:add(ellipsoid({ x, 1.4, z + 0.6 }, { 3.2, 1.4, 3.2 }), SKIN)
			s:add(ellipsoid({ x, 4.6, z + 0.4 }, { 3.5, 1.4, 3.5 }), WOOL_DARK)
		end
		local front = newSculpt(U)
		pillar(front, 4.8, 4.6, 16)
		local back = newSculpt(U)
		pillar(back, 4.8, -8, 16)
		for _, leg in { front, back } do
			leg:coat(function(p)
				return if p[2] > 5.6 then wool(p) else nil
			end)
		end

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 21, -13.6, 0.9 }, { 0, 17, -14.6, 0.65 } }), WOOL)
		tail:add(ellipsoid({ 0, 16, -14.7 }, { 0.9, 1.6, 0.9 }), WOOL_DARK)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 16, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, WOOL)
		-- Frost crystals growing out of the snow on its back, and icicles hanging from its long hair.
		for _, crystal in { { 0, -4.6, 0, 2.6 }, { 2.4, -2.4, 0.4, 1.8 }, { -2.2, 0.6, -0.3, 2 }, { 1, 3.6, 0.2, 1.6 } } do
			local x, z = crystal[1], crystal[2]
			local y = topOf(body, z, x)
			T.taper(
				bodyLimb,
				{ x, y - 0.6, z },
				{ x + crystal[3], y + crystal[4] * 1.6, z },
				crystal[4] * 0.6,
				crystal[4] * 0.6,
				{ 0, 0, 1 },
				ICE,
				GLASS
			)
		end
		for _, s in { 1, -1 } do
			for _, z in { -6.8, -0.2, 4.2 } do
				local top = { 6.9 * s, 10.2, z + 0.4 }
				T.taper(bodyLimb, top, vadd(top, { 0, -2.4, 0 }), 0.6, 0.6, { 1, 0, 0 }, ICE, GLASS)
			end
		end
		local headLimb = pet:limb("Head", T.at({ 0, 20, 7 }))
		head:draw(headLimb, { body }, WOOL)
		roundEyes(headLimb, head, 22.4, 15.4, 1.05)
		-- Great curving tusks of ivory, frosted at the tips.
		for _, s in { 1, -1 } do
			local points = {
				{ 2.4 * s, 18.4, 15.8 },
				{ 4 * s, 14.4, 19.4 },
				{ 5.4 * s, 12.6, 23.4 },
				{ 5.4 * s, 14.4, 27 },
				{ 4.4 * s, 17.4, 28.6 },
			}
			for index = 1, #points - 2 do
				T.blade(
					headLimb,
					points[index],
					points[index + 1],
					1.7 - index * 0.2,
					1.7 - index * 0.2,
					{ 1, 0, 0 },
					IVORY
				)
			end
			T.taper(headLimb, points[#points - 1], points[#points], 1.1, 1.1, { 1, 0, 0 }, ICE, GLASS)
			for index = 2, #points - 1 do
				T.ball(headLimb, points[index], 1.75 - index * 0.2, IVORY)
			end
		end
		local function nails(limb: Limb, x: number, z: number)
			for _, dx in { -1.6, 0, 1.6 } do
				T.ball(limb, { x + dx, 0.8, z + 3.2 }, { 1.2, 1, 0.9 }, IVORY)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 4.8, 16, 4.6 }), function(limb)
			front:draw(limb, { body }, WOOL)
			nails(limb, 4.8, 5)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4.8, 16, -8 }), function(limb)
			back:draw(limb, { body }, WOOL)
			nails(limb, 4.8, -7.6)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 21, -13 })), { body }, WOOL)

		pet:light(ICE, 1.8, 16)
		pet:particles("Snow", SNOW.color, 10)
		pet:seat(0, 26.6 / U, -2 / U)
	end,
}

Designs.Yeti = {
	name = "Yeti",
	skeleton = "Biped",
	gait = "Stomp",
	scale = 0.5 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with horns, tusks, claws, ice
		-- shards and its crystal club of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local FUR = look(240, 245, 250)
		local SHADE = look(204, 218, 236)
		local DEEP = look(170, 190, 220)
		local SKIN = look(104, 146, 208)
		local SKIN_DARK = look(62, 92, 150)
		local MOUTH = look(30, 36, 56)
		local GLOW = look(130, 236, 255, NEON)
		local ICE_LOOK = look(196, 240, 255, GLASS)
		local CLAW = rgb(220, 236, 250)
		local ICE = rgb(196, 240, 255)
		local ICE_DEEP = rgb(120, 190, 240)
		local GLOW_WHITE = rgb(230, 250, 255)

		-- Shaggy white fur in long locks, deeper blue-white where it hangs.
		local function fur(p: Vec): Look?
			local n = noise({ math.floor(p[1] / 1.2), math.floor(p[2] / 3.6), math.floor(p[3] / 1.2) })
			if n < 0.2 then
				return SHADE
			elseif n > 0.88 then
				return DEEP
			end
			return nil
		end

		-- A towering, hunched body of shaggy fur, a bare blue chest with a glowing frost rune.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 16, -0.5 }, { 6, 5.2, 4.6 }), FUR)
		body:add(ellipsoid({ 0, 24, -0.5 }, { 8.6, 7, 5.6 }), FUR)
		body:add(ellipsoid({ 0, 28.6, -1 }, { 9.6, 3.6, 5.2 }), FUR)
		body:add(ellipsoid({ 0, 28, -3.6 }, { 6, 4.6, 3.8 }), FUR)
		for _, s in { 1, -1 } do
			for _, z in { -3, -0.5, 2 } do
				body:add(rod({ { 7.6 * s, 20, z, 1.4 }, { 8 * s, 15.6, z + 0.2, 0.8 } }), DEEP)
			end
		end
		body:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if z > 2 and open(0, 0, 1) and (x / 4.4) ^ 2 + ((y - 24) / 4.6) ^ 2 < 1 then
				return SKIN
			end
			if open(0, -1, 0) then
				return DEEP
			end
			return fur(p)
		end)
		-- A blue face under a heavy fur brow: a flat nose, a wide mouth with tusks, cheek tufts.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 34.4, 2 }, { 4.4, 4.4, 4.1 }), FUR)
		head:add(rod({ { -3.6, 36.4, 4.6, 1.5 }, { 0, 36.8, 5.6, 1.6 }, { 3.6, 36.4, 4.6, 1.5 } }), FUR)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 4 * s, 32.6, 2.8 }, { 1.6, 2.4, 2 }), FUR)
		end
		head:add(ellipsoid({ 0, 33.6, 6 }, { 1.3, 1, 0.9 }), SKIN_DARK)
		head:carve(ellipsoid({ 0, 31.4, 6.2 }, { 2.4, 0.9, 1.6 }))
		head:paint(ellipsoid({ 0, 31.4, 6.2 }, { 2.9, 1.4, 2.1 }), MOUTH, nil, true)
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if z > 3.6 and y < 36 and math.abs(x) < 3.2 and open(0, 0, 1) then
				return SKIN
			end
			return fur(p)
		end)

		-- Long arms to the ground: fur shoulders, ice bracers glowing with runes, blue fists and ice claws.
		local arm = newSculpt(U)
		arm:add(rod({ { 8.4, 29, -0.6, 3.6 }, { 10.4, 22, -0.4, 2.9 }, { 11, 14, 0, 2.7 }, { 11, 8, 0.4, 2.6 } }), FUR)
		arm:add(ellipsoid({ 11, 12.4, 0.2 }, { 3.3, 1.8, 3.3 }), ICE_LOOK)
		arm:add(ellipsoid({ 11, 4.8, 0.8 }, { 2.9, 2.9, 2.9 }), SKIN)
		arm:coat(function(p, open)
			local y = p[2]
			if
				y > 11
				and y < 14
				and (open(1, 0, 0) or open(-1, 0, 0) or open(0, 0, 1))
				and math.floor(p[3] / 1.2) % 2 == 0
			then
				return GLOW
			end
			if y > 14.4 and y < 17 then
				return DEEP
			end
			if y < 7.6 then
				return nil
			end
			return fur(p)
		end)

		-- Thick legs with a fringe at the knee, and wide blue feet.
		local leg = newSculpt(U)
		leg:add(rod({ { 3.6, 16, -0.5, 3.6 }, { 4, 9, 0, 3.3 }, { 4.2, 4, 0.4, 3 } }), FUR)
		leg:add(ellipsoid({ 4.2, 1.4, 1.6 }, { 3.3, 1.4, 4.2 }), SKIN)
		for _, z in { -1.6, 0.6, 2.6 } do
			leg:add(rod({ { 6.6, 10, z, 1 }, { 7, 6.4, z + 0.3, 0.6 } }), DEEP)
		end
		leg:coat(function(p)
			return if p[2] > 2.8 then fur(p) else nil
		end)

		local legMirror, armMirror = leg:mirror(), arm:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 16, 0 }))
		body:draw(bodyLimb, { head, leg, legMirror, arm, armMirror }, FUR)
		-- A necklace of ice fangs, and ice shards growing out of its back and shoulders, glowing at their roots.
		for _, x in { -2.8, -1.4, 0, 1.4, 2.8 } do
			local y = 28.6 - math.abs(x) * 0.3
			local z = frontOf(body, x, y)
			T.taper(bodyLimb, { x, y, z - 0.3 }, { x * 1.05, y - 2, z + 0.3 }, 0.8, 0.6, { 0, 0, 1 }, ICE, GLASS)
		end
		for _, shard in
			{
				{ { -2.6, 27, -7 }, { -3.6, 33.4, -9.6 }, 1.8 },
				{ { 1.4, 26, -7.2 }, { 2.2, 31, -9.8 }, 1.4 },
				{ { -0.4, 29, -6.4 }, { -0.6, 36.6, -8.4 }, 1.9 },
				{ { 6.4, 30.4, -2.4 }, { 8.4, 35.6, -3.4 }, 1.4 },
				{ { -6.4, 30.4, -2.4 }, { -8.4, 35.6, -3.4 }, 1.4 },
				{ { 3.6, 23.4, -6.4 }, { 5, 26.4, -8.6 }, 1.1 },
			}
		do
			T.taper(
				bodyLimb,
				shard[1],
				shard[2],
				shard[3],
				shard[3],
				{ 0, 0, 1 },
				if shard[3] > 1.5 then ICE_DEEP else ICE,
				GLASS
			)
			T.ball(bodyLimb, vlerp(shard[1], shard[2], 0.12), shard[3] * 0.8, GLOW_WHITE, NEON)
		end

		-- A glowing frost rune on its chest: a six-pointed snowflake.
		local heart = { 0, 24, frontOf(body, 0, 24) + 0.1 }
		for spoke = 0, 2 do
			local angle = math.pi / 2 + spoke * math.pi / 3
			local out = { math.cos(angle) * 3, math.sin(angle) * 3, 0 }
			T.blade(bodyLimb, vsub(heart, out), vadd(heart, out), 0.45, 0.3, { 0, 0, 1 }, GLOW.color, NEON)
			for _, tip in { vadd(heart, vscale(out, 0.7)), vsub(heart, vscale(out, 0.7)) } do
				T.ball(bodyLimb, tip, 0.9, GLOW_WHITE, NEON)
			end
		end
		T.ball(bodyLimb, heart, 1.4, GLOW_WHITE, NEON)
		local headLimb = pet:limb("Head", T.at({ 0, 30, 1 }))
		head:draw(headLimb, { body }, FUR)
		for _, s in { 1, -1 } do
			local z = frontOf(head, 1.8 * s, 34) + 0.08
			T.blade(headLimb, { 0.7 * s, 33.8, z }, { 2.4 * s, 34.2, z - 0.4 }, 1.4, 0.4, { 0, 0, 1 }, GLOW.color, NEON)
			T.taper(
				headLimb,
				{ 2.4 * s, 34.2, z - 0.4 },
				{ 3.4 * s, 34.8, z - 1.1 },
				1.4,
				0.4,
				{ 0, 0, 1 },
				GLOW.color,
				NEON
			)
			T.taper(headLimb, { 1.8 * s, 30.8, 5.6 }, { 2.3 * s, 33.4, 6.6 }, 0.8, 0.7, { 0, 0, 1 }, CLAW)
			-- Curling horns of ice, ringed with glowing bands.
			local horn = {
				{ 3.2 * s, 37, 1.4 },
				{ 6 * s, 38.8, 0.4 },
				{ 8.4 * s, 37.4, -0.6 },
				{ 9.4 * s, 34.2, 0.4 },
				{ 8.4 * s, 31.6, 2 },
			}
			T.branch(headLimb, horn, 2, { 0, 0, 1 }, ICE_DEEP, GLASS)
			for index = 2, 4 do
				T.ball(headLimb, horn[index], 2.1 - index * 0.25, GLOW_WHITE, NEON)
			end
		end
		for _, crown in { { 0, 0.4, 3 }, { 1.4, -0.4, 2.2 }, { -1.4, -0.4, 2.2 } } do
			local x, z = crown[1], crown[2]
			local y = topOf(head, z, x)
			T.taper(headLimb, { x, y - 0.6, z }, { x * 1.3, y + crown[3], z - 0.6 }, 1.1, 1.1, { 0, 0, 1 }, ICE, GLASS)
		end

		local function claws(limb: Limb, x: number)
			for _, dz in { -1.2, 0, 1.2 } do
				T.taper(
					limb,
					{ x, 3.8, 3 + dz * 0.5 },
					{ x + 0.2 * math.sign(x), 1.2, 4.4 + dz * 0.6 },
					0.8,
					0.7,
					{ 1, 0, 0 },
					ICE,
					GLASS
				)
			end
		end
		local left = pet:limb("LeftArm", T.at({ 8.5, 29, 0 }))
		arm:draw(left, { body }, FUR)
		claws(left, 11)
		local right = pet:limb("RightArm", T.at({ -8.5, 29, 0 }))
		armMirror:draw(right, { body }, FUR)
		claws(right, -11)
		-- In its right fist, a club of frost crystal glowing at its heart.
		T.blade(right, { -11, 5.2, 2.6 }, { -11, 6.4, 9.6 }, 1.2, 1.2, { 1, 0, 0 }, ICE_DEEP, GLASS)
		T.ball(right, { -11, 6.6, 10 }, 2.6, GLOW_WHITE, NEON)
		for _, spike in
			{ { 0, 3, 1 }, { 2.4, 1.4, 1.6 }, { -2.4, 1.6, 1.4 }, { 0.6, -2, 2 }, { -1.2, 0, 3.2 }, { 1.6, 1, 3 } }
		do
			local root = { -11, 6.6, 10 }
			T.taper(right, root, vadd(root, spike), 2, 2, { 0, 0, 1 }, ICE, GLASS)
		end
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 3.6, 16, -0.5 }), function(limb)
			leg:draw(limb, { body }, FUR)
			for _, dx in { -1.6, 0, 1.6 } do
				T.taper(limb, { 4.2 + dx, 1.4, 4.4 }, { 4.2 + dx * 1.1, 0.4, 6.4 }, 0.8, 0.7, { 0, 1, 0 }, CLAW)
			end
		end)

		pet:light(GLOW.color, 2.8, 22)
		pet:particles("Snow", GLOW_WHITE, 14)
		pet:seat(0, 39 / U, -1 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Ocean

Designs.SeaTurtle = {
	name = "Sea Turtle",
	skeleton = "LowSlung",
	scale = 0.75,
	draw = function(pet)
		local SHELL = rgb(98, 168, 84)
		local SHELL_DARK = rgb(62, 118, 58)
		local SKIN = rgb(150, 196, 120)
		local SPOT = rgb(100, 150, 80)
		local PLASTRON = rgb(232, 218, 156)
		local BARNACLE = rgb(226, 220, 206)
		local STAR = rgb(255, 140, 90)
		local WEED = rgb(60, 140, 90)

		-- A stepped shell of plates with dark seams, a dark rim, a cream belly, barnacles and a starfish.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 0, -4, 3, 0, 4, PLASTRON)
		body:box(-6, 1, -6, 5, 1, 5, SHELL_DARK)
		body:box(-5, 2, -5, 4, 3, 4, SHELL)
		body:box(-4, 4, -4, 3, 5, 3, SHELL)
		body:box(-3, 6, -3, 2, 6, 2, SHELL)
		body:paint(-1, 6, -3, 0, 6, 2, SHELL_DARK)
		body:paint(-4, 5, 0, 3, 5, 0, SHELL_DARK)
		body:paint(-4, 5, -3, 3, 5, -3, SHELL_DARK)
		body:paintPair(4, 2, -2, 4, 3, -2, SHELL_DARK)
		body:paintPair(4, 2, 2, 4, 3, 2, SHELL_DARK)
		body:paint(-2, 2, 4, -2, 3, 4, SHELL_DARK)
		body:paint(1, 2, 4, 1, 3, 4, SHELL_DARK)
		body:paint(-2, 2, -5, 1, 3, -5, SHELL_DARK)
		for _, z in { -5, -1, 3 } do
			body:paintPair(5, 1, z, 5, 1, z, SHELL)
		end
		body:paint(-1, 1, 5, 0, 1, 5, SHELL)
		body:box(2, 7, -2, 2, 7, -2, BARNACLE)
		body:box(-3, 6, 3, -3, 6, 3, BARNACLE)
		body:box(2, 7, 1, 2, 7, 1, BARNACLE)
		body:box(-2, 7, -1, -2, 7, 1, STAR)
		body:box(-3, 7, 0, -1, 7, 0, STAR)
		body:box(1, 0, -7, 1, 0, -7, WEED)

		-- A spotted head with a beaky mouth and a gentle smile.
		local head = pet:limb("Head", { 0, 2, 5 })
		head:box(-1, 2, 5, 0, 3, 6, SKIN)
		head:box(-2, 2, 7, 1, 4, 9, SKIN)
		head:box(-1, 2, 10, 0, 3, 10, SHELL_DARK)
		eyes(head, 1, 3, 9, 1, 1)
		head:paint(-2, 2, 9, 1, 2, 9, SPOT)
		head:paintPair(1, 4, 8, 1, 4, 8, SPOT)
		head:paint(-1, 4, 7, 0, 4, 7, SPOT)
		head:paint(-1, 3, 10, 0, 3, 10, rgb(40, 70, 40))
		head:paintPair(2, 2, 8, 2, 3, 8, SPOT)

		-- Broad spotted flippers.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 5, 0.5, 3 }, function(leg)
			leg:box(5, 0, 2, 8, 0, 4, SKIN)
			leg:box(8, 0, 5, 8, 0, 5, SKIN)
			leg:paint(6, 0, 3, 6, 0, 3, SPOT)
			leg:paint(8, 0, 2, 8, 0, 2, SPOT)
			leg:box(9, 0, 3, 9, 0, 3, SHELL_DARK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 4, 0.5, -4 }, function(leg)
			leg:box(4, 0, -5, 6, 0, -3, SKIN)
			leg:paint(5, 0, -4, 5, 0, -4, SPOT)
		end)

		local tail = pet:limb("Tail", { 0, 0.5, -6 })
		tail:box(-1, 0, -7, 0, 0, -6, SKIN)

		pet:seat(0, 7, -1)
	end,
}

Designs.Dolphin = {
	name = "Dolphin",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.55,
	draw = function(pet)
		local GREY = rgb(112, 152, 194)
		local CAPE = rgb(78, 112, 156)
		local BELLY = rgb(232, 242, 250)

		-- A sleek body, dark along the back and pale underneath, with a swept-back fin.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-3, 1, -5, 2, 5, 3, GREY)
		body:box(-2, 6, -4, 1, 6, 2, CAPE)
		body:box(-2, 0, -4, 1, 0, 2, BELLY)
		body:paint(-3, 5, -5, 2, 5, 3, CAPE)
		body:paint(-3, 1, -5, 2, 1, 3, BELLY)
		body:paintPair(2, 2, -4, 2, 2, 2, BELLY)
		body:box(-1, 7, -2, 0, 8, 0, CAPE)
		body:box(-1, 9, -3, 0, 9, -1, CAPE)
		body:box(-1, 10, -4, 0, 10, -3, CAPE)
		body:paint(-1, 7, 0, 0, 8, 0, GREY)
		body:paintPair(2, 3, -4, 2, 3, -1, rgb(170, 204, 232))
		body:paintPair(2, 4, 0, 2, 4, 2, rgb(170, 204, 232))
		body:paint(-1, 0, -2, -1, 0, -2, rgb(200, 214, 230))
		body:paint(0, 0, 1, 0, 0, 1, rgb(200, 214, 230))

		-- A rounded head, a smiling beak and a blowhole.
		local head = pet:limb("Head", { 0, 3, 3 })
		head:box(-2, 1, 4, 1, 5, 7, GREY)
		head:box(-1, 2, 8, 0, 2, 10, GREY)
		head:box(-1, 1, 8, 0, 1, 10, BELLY)
		head:paint(-2, 1, 4, 1, 1, 7, BELLY)
		head:paint(-2, 5, 4, 1, 5, 7, CAPE)
		head:paint(-1, 5, 5, 0, 5, 5, rgb(40, 50, 70))
		eyes(head, 1, 3, 7, 1, 1)
		head:paintPair(1, 2, 7, 1, 2, 7, rgb(170, 204, 232))
		head:box(-1, 6, 5, 0, 7, 5, rgb(200, 240, 255), GLASS, 0.3)
		head:box(-1, 8, 5, 0, 8, 5, rgb(240, 252, 255))
		head:boxPair(1, 8, 4, 1, 8, 4, rgb(200, 240, 255), GLASS, 0.3)
		head:boxPair(1, 9, 5, 1, 9, 5, rgb(240, 252, 255))

		pet:limbPair("LeftFin", "RightFin", { 3, 1.5, 1 }, function(fin)
			fin:box(3, 1, 0, 5, 1, 2, CAPE)
			fin:box(6, 0, 0, 6, 0, 1, CAPE)
		end)

		-- A narrow tail ending in wide flukes.
		local tail = pet:limb("Tail", { 0, 3, -5 })
		tail:box(-1, 2, -8, 0, 4, -6, GREY)
		tail:paint(-1, 2, -8, 0, 2, -6, BELLY)
		tail:paint(-1, 4, -8, 0, 4, -6, CAPE)
		tail:box(-4, 3, -10, 3, 3, -9, CAPE)
		tail:boxPair(2, 3, -11, 3, 3, -11, CAPE)

		pet:seat(0, 7, 2)
	end,
}

Designs.MantaRay = {
	name = "Manta Ray",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 4,
	scale = 0.55,
	draw = function(pet)
		local NAVY = rgb(34, 50, 96)
		local NAVY_LIGHT = rgb(54, 74, 128)
		local BELLY = rgb(232, 242, 250)
		local SPOT = rgb(144, 204, 244)
		local REMORA = rgb(150, 156, 170)

		-- A flat, broad body, dark above with pale shoulder marks and spots, white below,
		-- with a little remora fish hitching a ride underneath.
		local body = pet:limb("Body", { 0, 2, 0 })
		body:box(-3, 2, -4, 2, 3, 4, NAVY)
		body:box(-3, 1, -4, 2, 1, 4, BELLY)
		body:box(-2, 4, -3, 1, 4, 2, NAVY)
		body:paintPair(1, 4, 1, 1, 4, 2, BELLY)
		body:paintPair(2, 3, 2, 2, 3, 3, BELLY)
		body:paint(-1, 4, -2, -1, 4, -2, SPOT)
		body:paint(0, 4, 0, 0, 4, 0, SPOT)
		body:paint(-2, 4, -3, -2, 4, -3, SPOT)
		body:box(-2, 0, 0, -1, 0, 2, REMORA)
		body:paint(-2, 0, 2, -1, 0, 2, rgb(110, 116, 130))
		body:box(1, 0, -3, 1, 0, -1, REMORA)
		for _, z in { 1, 2, 3 } do
			body:paintPair(1, 1, z, 2, 1, z, rgb(170, 180, 200))
		end
		body:paint(1, 4, -2, 1, 4, -2, SPOT)
		body:paint(-2, 4, 1, -2, 4, 1, SPOT)

		-- Curled head lobes either side of a wide mouth.
		local head = pet:limb("Head", { 0, 2, 5 })
		head:box(-3, 1, 5, 2, 2, 6, NAVY)
		head:paint(-2, 1, 6, 1, 1, 6, rgb(200, 210, 230))
		eyes(head, 2, 2, 6, 1, 1)
		head:boxPair(2, 1, 7, 3, 2, 9, NAVY)
		head:boxPair(2, 3, 9, 2, 3, 9, NAVY)
		head:paintPair(2, 1, 7, 3, 1, 9, BELLY)

		-- Great wings, dark above and white below, with up-curled tips.
		pet:limbPair("LeftFin", "RightFin", { 3.5, 2, 0 }, function(wing)
			wing:box(3, 2, -3, 6, 2, 3, NAVY)
			wing:box(3, 1, -3, 6, 1, 3, BELLY)
			wing:box(7, 2, -2, 8, 2, 2, NAVY)
			wing:box(7, 1, -2, 8, 1, 2, BELLY)
			wing:box(9, 2, -1, 10, 2, 1, NAVY)
			wing:box(9, 1, -1, 10, 1, 1, BELLY)
			wing:box(11, 2, 0, 12, 3, 0, NAVY)
			wing:paint(5, 2, 1, 5, 2, 1, SPOT)
			wing:paint(7, 2, -1, 7, 2, -1, SPOT)
			wing:paint(4, 2, -2, 4, 2, -2, SPOT)
			wing:paint(3, 2, 2, 4, 2, 3, BELLY)
			wing:paint(7, 2, -2, 8, 2, -2, NAVY_LIGHT)
			wing:paint(9, 2, -1, 10, 2, -1, NAVY_LIGHT)
			wing:paint(6, 2, -3, 6, 2, -3, NAVY_LIGHT)
			wing:paint(9, 2, 1, 9, 2, 1, SPOT)
			wing:paint(5, 1, 0, 5, 1, 0, rgb(170, 180, 200))
			wing:paint(8, 1, 0, 8, 1, 0, rgb(170, 180, 200))
		end)

		-- A long whip of a tail.
		local tail = pet:limb("Tail", { 0, 2, -5 })
		tail:box(-1, 2, -10, 0, 2, -5, NAVY_LIGHT)
		tail:box(-1, 2, -14, -1, 2, -11, NAVY_LIGHT)
		tail:boxPair(1, 1, -5, 2, 1, -5, NAVY)

		pet:seat(0, 5, 0)
	end,
}

Designs.GreatShark = {
	name = "Great Shark",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.42,
	draw = function(pet)
		local GREY = rgb(112, 128, 146)
		local GREY_DARK = rgb(78, 90, 108)
		local WHITE = rgb(238, 242, 246)
		local MOUTH = rgb(96, 24, 36)
		local TOOTH = rgb(252, 252, 244)
		local SCAR = rgb(176, 186, 198)

		-- A torpedo: deepest just behind the head, tapering to a pointed snout and a narrow tail.
		local function girth(z: number): (number, number, number)
			local rx, ry
			if z >= 2 then
				local t = math.min(1, (z - 2) / 14.5)
				rx, ry = 4.4 * (1 - t ^ 2.2) ^ 0.5, 4.8 * (1 - t ^ 2) ^ 0.5
			else
				local t = math.min(1, (2 - z) / 16)
				rx, ry = 4.4 * (1 - t ^ 1.6) ^ 0.6 + 0.9 * t, 4.8 * (1 - t ^ 1.6) ^ 0.6 + 1.2 * t
			end
			return rx, ry, 5 + 0.08 * z
		end
		local function inBody(x: number, y: number, z: number): boolean
			local rx, ry, yc = girth(z + 0.5)
			return ((x + 0.5) / rx) ^ 2 + ((y + 0.5 - yc) / ry) ^ 2 <= 1
		end
		-- Grey above, white below, along a jagged line.
		local function white(y: number, z: number): boolean
			local _, ry, yc = girth(z + 0.5)
			return y + 0.5 < yc - ry * 0.2 + (if z % 3 == 0 then 0.8 else 0)
		end
		-- The open mouth: a wedge cut under the snout, widening towards the front.
		local function inMouth(y: number, z: number): boolean
			if z < 9 or z > 15 then
				return false
			end
			local _, ry, yc = girth(z + 0.5)
			local low = yc - ry * 0.6
			return y + 0.5 > low and y + 0.5 < low + 1.2 + (z - 9) * 0.45
		end
		local function part(limb, z0: number, z1: number, plain: boolean?)
			for _, pale in if plain then { false } else { true, false } do
				blob(limb, { -5, 0, z0, 4, 12, z1 }, function(x, y, z)
					return z >= z0
						and z <= z1
						and inBody(x, y, z)
						and not inMouth(y, z)
						and (plain or white(y, z) == pale)
				end, if pale then WHITE else GREY)
			end
		end

		-- The outermost cell on its left side at a height, to paint on.
		local function side(y: number, z: number): number
			local x = 0
			while inBody(x + 1, y, z) and not inMouth(y, z) do
				x += 1
			end
			return x
		end
		local function paintSide(limb, y0: number, y1: number, z: number, color: Color)
			local x = side(y0, z)
			if side(y1, z) == x then
				limb:paintPair(x, y0, z, x, y1, z, color)
			else
				for y = y0, y1 do
					limb:paintPair(side(y, z), y, z, side(y, z), y, z, color)
				end
			end
		end

		local body = pet:limb("Body", { 0, 5, 0 })
		part(body, -5, 8)
		-- A tall swept-back dorsal fin, gill slits, and an old scar.
		for _, row in
			{
				{ 10, -3, 3 },
				{ 11, -3, 2 },
				{ 12, -3, 1 },
				{ 13, -3, 0 },
				{ 14, -4, -1 },
				{ 15, -5, -2 },
				{ 16, -6, -4 },
			}
		do
			body:box(-1, row[1], row[2], 0, row[1], row[3], GREY_DARK)
		end
		for _, z in { 4, 6, 8 } do
			paintSide(body, 5, 6, z, GREY_DARK)
		end
		local scarX = side(7, -1)
		body:paint(scarX, 7, -2, scarX, 7, 0, SCAR)
		body:paint(side(6, -3), 6, -3, side(6, -3), 6, -3, SCAR)

		-- The head: a pointed snout over a gaping mouth ringed with jagged teeth, and flat black eyes.
		local head = pet:limb("Head", { 0, 5, 9 })
		part(head, 9, 16)
		head:paint(-2, 3, 9, 1, 4, 9, MOUTH)
		for z = 10, 15 do
			local low, high = math.huge, -math.huge
			for y = 0, 12 do
				if inMouth(y, z) then
					low, high = math.min(low, y), math.max(high, y)
				end
			end
			local edge = if z <= 13 then 1 else 0
			if high > low then
				head:boxPair(
					edge,
					if z % 2 == 1 then high else low,
					z,
					edge,
					if z % 2 == 1 then high else low,
					z,
					TOOTH
				)
			end
		end
		paintSide(head, 6, 7, 11, EYE)

		-- Long pectoral fins, swept back and angled down.
		pet:limbPair("LeftFin", "RightFin", { 4, 3, 3 }, function(fin)
			fin:box(4, 3, 1, 5, 3, 4, GREY)
			fin:box(6, 2, -1, 7, 2, 3, GREY)
			fin:box(8, 1, -3, 9, 1, 1, GREY)
			fin:box(10, 0, -4, 10, 0, -1, GREY_DARK)
			fin:paint(4, 3, 1, 9, 3, 1, GREY_DARK)
		end)

		-- The narrow tail and a tall crescent fin, its upper lobe longer than the lower.
		local tail = pet:limb("Tail", { 0, 5, -6 })
		part(tail, -15, -6, true)
		for _, row in
			{
				{ 14, -24, -23 },
				{ 13, -24, -22 },
				{ 12, -23, -21 },
				{ 11, -22, -20 },
				{ 10, -21, -19 },
				{ 9, -20, -18 },
				{ 8, -19, -17 },
				{ 7, -18, -16 },
				{ 6, -17, -16 },
				{ 3, -17, -16 },
				{ 2, -18, -17 },
				{ 1, -19, -18 },
				{ 0, -20, -19 },
			}
		do
			tail:box(-1, row[1], row[2], 0, row[1], row[3], GREY_DARK)
		end
		tail:box(-1, 4, -18, 0, 5, -16, GREY_DARK)

		pet:seat(0, 10, 3)
	end,
}

Designs.Narwhal = {
	name = "Narwhal",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with its tusk and ice chips of parts
		-- at any angle.
		local U = 1.2
		local T = inUnits(U)
		local SLATE = look(122, 142, 172)
		local SLATE_DARK = look(82, 100, 136)
		local BELLY = look(232, 242, 250)
		local IVORY = rgb(250, 242, 220)
		local IVORY_DARK = rgb(214, 196, 158)
		local GLOW = rgb(255, 250, 230)
		local ICE = rgb(170, 230, 255)

		-- Mottled slate above, pale below.
		local function hide(p: Vec, open: (number, number, number) -> boolean, belly: number): Look?
			if p[2] < belly and (open(0, -1, 0) or open(1, 0, 0) or open(-1, 0, 0) or open(0, 0, 1)) then
				return BELLY
			end
			if noise(p) < 0.16 then
				return SLATE_DARK
			end
			return nil
		end

		-- A plump whale body with a low ridge down its back and chips of ice stuck to it.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 4.4, -2 }, { 5.2, 5, 9 }), SLATE)
		for _, z in { 2, -1.6, -5.2 } do
			body:add(ellipsoid({ 0, topOf(body, z) - 0.4, z }, { 0.9, 0.8, 1.4 }), SLATE_DARK)
		end
		body:coat(function(p, open)
			return hide(p, open, 2.6)
		end)

		-- A round head with a gentle smile.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 4.8, 7.2 }, { 4.8, 4.6, 4.6 }), SLATE)
		head:add(ellipsoid({ 0, 6.6, 7.6 }, { 3.6, 2.8, 3.6 }), SLATE)
		head:coat(function(p, open)
			return hide(p, open, 3.4)
		end)
		for _, side in { 1, -1 } do
			head:trace({ { 0, 3.8, 9.6 }, { 0, 3.2, 8.2 }, { 0, 3.6, 6.4 } }, { -side, 0, 0 }, SLATE_DARK)
		end

		-- Flippers, pale underneath.
		local flipper = newSculpt(U)
		local frame = { origin = { 6.4, 1.4, 3 }, yaw = 0.5, roll = -0.4 }
		flipper:add(ellipsoid({ 0, 0, 0 }, { 3.4, 0.8, 1.8 }), SLATE_DARK, frame)
		flipper:add(rod({ { 4.2, 2.6, 3.4, 1.4 }, { 5.6, 1.8, 3.2, 1 } }), SLATE)
		flipper:coat(function(_, open)
			return if open(0, -1, 0) then BELLY else nil
		end)

		-- A thick tail and broad flukes.
		local tail = newSculpt(U)
		tail:add(rod({ { 0, 4.4, -10.4, 3.9 }, { 0, 5, -16, 2.6 }, { 0, 5.4, -20.6, 1.6 } }), SLATE)
		for _, s in { 1, -1 } do
			tail:add(
				ellipsoid({ 0, 0, 0 }, { 3.6, 0.75, 2 }),
				SLATE_DARK,
				{ origin = { 3 * s, 5.6, -22.4 }, yaw = 0.35 * s }
			)
		end
		tail:coat(function(p, open)
			return hide(p, open, 2.8)
		end)

		local flipperMirror = flipper:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 4.4, 0 }))
		body:draw(bodyLimb, { head, flipper, flipperMirror, tail }, SLATE)
		for _, chip in { { -1.2, -3.6, 1.6 }, { 1.4, -0.6, 1.2 }, { -0.4, 2.6, 1 }, { 2.2, -6, 1 } } do
			local x, z = chip[1], chip[2]
			local y = topOf(body, z, x)
			T.taper(
				bodyLimb,
				{ x, y - 0.4, z },
				{ x + 0.3, y + chip[3] * 1.4, z - 0.4 },
				chip[3],
				chip[3],
				{ 0, 0, 1 },
				ICE,
				GLASS
			)
		end
		local headLimb = pet:limb("Head", T.at({ 0, 4.8, 4 }))
		head:draw(headLimb, { body }, SLATE)
		roundEyes(headLimb, head, 5.2, 9.6, 1.05)
		-- The long spiral tusk, twisting in bands, glowing at its tip.
		local root, tip = { 0.8, 6, 11.2 }, { 1.4, 8.2, 27 }
		for index = 0, 7 do
			local a, b = vlerp(root, tip, index / 8), vlerp(root, tip, (index + 1) / 8)
			local width = 1.5 - index * 0.13
			local angle = index * 0.8
			local facing = { math.cos(angle), math.sin(angle), 0 }
			if index == 7 then
				T.taper(headLimb, a, b, width, width, facing, IVORY)
			else
				T.blade(headLimb, a, b, width, width, facing, if index % 2 == 0 then IVORY else IVORY_DARK)
			end
		end
		T.ball(headLimb, tip, 0.8, GLOW, NEON)
		pet:limbPair("LeftFin", "RightFin", T.at({ 4.6, 2.6, 3.4 }), function(limb)
			flipper:draw(limb, { body }, SLATE)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 4.4, -10 }))
		tail:draw(tailLimb, { body }, SLATE)
		for _, chip in { { -3.6, -22.4 }, { 3, -23 } } do
			local y = topOf(tail, chip[2], chip[1])
			T.taper(
				tailLimb,
				{ chip[1], y - 0.3, chip[2] },
				{ chip[1], y + 1.3, chip[2] - 0.3 },
				0.9,
				0.9,
				{ 0, 0, 1 },
				ICE,
				GLASS
			)
		end

		pet:light(ICE, 1.8, 14)
		pet:seat(0, 9.8 / U, 0)
	end,
}

Designs.Hippocampus = {
	name = "Hippocampus",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with its glassy fins, coral and
		-- pearls of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local TEAL = look(36, 172, 168)
		local TEAL_DARK = look(22, 122, 126)
		local BELLY = look(188, 242, 230)
		local DOT = look(80, 255, 228, NEON)
		local WEED = look(70, 150, 90)
		local FIN = rgb(90, 220, 210)
		local GLOW = rgb(80, 255, 228)
		local CORAL = rgb(255, 150, 160)
		local PEARL = rgb(250, 246, 240)

		-- Ridged like a sea horse: dark rings, a pale belly, glowing dots.
		local function hide(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, 0, 1) and math.abs(p[1]) < 2.2 then
				return BELLY
			end
			if p[2] % 1.8 < 0.45 then
				return TEAL_DARK
			end
			if noise(p) < 0.05 then
				return DOT
			end
			return nil
		end
		local function fin(limb: Limb, a: Vec, b: Vec, c: Vec)
			T.triangle(limb, a, b, c, 0.4, FIN, GLASS)
			T.blade(limb, b, c, 0.3, 0.5, vnorm(vcross(vsub(b, a), vsub(c, a))), GLOW, NEON)
		end

		-- An upright, curving body.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 13, 2 }, { 3.6, 4.6, 4 }), TEAL)
		body:add(ellipsoid({ 0, 10.2, 1.2 }, { 3.2, 3.4, 3.4 }), TEAL)
		body:coat(hide)

		-- A horse's head on a long neck: a pale muzzle in a bridle of sea-weed, small ears, a pearl on its brow.
		local head = newSculpt(U)
		head:add(rod({ { 0, 15.5, 2.6, 2.7 }, { 0, 19.6, 4, 2.2 } }), TEAL)
		head:add(ellipsoid({ 0, 21.6, 6 }, { 2.4, 2.6, 3.1 }), TEAL)
		head:add(ellipsoid({ 0, 20.6, 9.4 }, { 1.7, 1.9, 2.3 }), TEAL)
		head:coat(function(p, open)
			local y, z = p[2], p[3]
			if z > 10.4 and y < 21.4 then
				return BELLY
			end
			if math.abs(z - 8.4) < 0.5 and y < 22.6 then
				return WEED
			end
			return hide(p, open)
		end)

		-- Horse's forelegs ending in webbed fins.
		local leg = newSculpt(U)
		leg:add(rod({ { 2.2, 12, 3.6, 1.4 }, { 2.6, 8.6, 6.2, 1.1 }, { 2.6, 6.6, 8, 0.9 } }), TEAL)
		leg:coat(function(p)
			return if p[2] % 1.8 < 0.45 then TEAL_DARK else nil
		end)

		-- A fish's tail sweeping down and back, curling up at the end.
		local tail = newSculpt(U)
		tail:add(
			rod({
				{ 0, 9, -1.4, 3.2 },
				{ 0, 6.2, -4.4, 2.6 },
				{ 0, 3.6, -7.8, 2.1 },
				{ 0, 2, -11.6, 1.6 },
				{ 0, 3.2, -15, 1.15 },
				{ 0, 5.6, -17, 0.85 },
			}),
			TEAL
		)
		tail:coat(hide)

		local legMirror = leg:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 12, 0 }))
		body:draw(bodyLimb, { head, leg, legMirror, tail }, TEAL)
		-- A glassy fin down its back, and coral and pearls growing on it.
		for _, rib in { { 16, -0.6, 17.6, -3.6 }, { 13.4, -1.8, 13.8, -5.4 }, { 10.6, -2, 10, -5.6 } } do
			fin(bodyLimb, { 0, rib[1], rib[2] }, { 0, rib[1] + 2.4, rib[2] - 2.6 }, { 0, rib[3], rib[4] - 1.2 })
		end
		for _, coral in { { 1.8, 3, 1 }, { -1.6, 0.6, 0.8 } } do
			local x, z = coral[1], coral[2]
			local y = topOf(body, z, x)
			local base = { x, y - 0.4, z }
			T.branch(
				bodyLimb,
				{ base, vadd(base, { 0.4, 1.6, 0 }), vadd(base, { 1, 2.8, 0.4 }) },
				0.6 * coral[3],
				{ 0, 0, 1 },
				CORAL
			)
			T.branch(
				bodyLimb,
				{ vadd(base, { 0.4, 1.4, 0 }), vadd(base, { -0.6, 2.6, -0.2 }) },
				0.45 * coral[3],
				{ 0, 0, 1 },
				CORAL
			)
			T.ball(bodyLimb, vadd(base, { 0, 0.4, 0.8 }), 0.8, PEARL)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 15.5, 2.6 }))
		head:draw(headLimb, { body }, TEAL)
		roundEyes(headLimb, head, 22.2, 7.6, 1)
		-- A mane of glassy fins down its neck, small ears, a coral crown and a pearl on its brow.
		for _, rib in { { 23.4, 4.6 }, { 21.4, 3 }, { 19, 1.8 }, { 16.6, 1 } } do
			fin(headLimb, { 0, rib[1], rib[2] }, { 0, rib[1] + 2.2, rib[2] - 3.6 }, { 0, rib[1] - 3, rib[2] - 2.6 })
		end
		for _, s in { 1, -1 } do
			T.taper(headLimb, { 1.2 * s, 23.4, 5.4 }, { 1.6 * s, 25.4, 4.8 }, 0.8, 0.5, { 0, 0, 1 }, TEAL.color)
			T.branch(
				headLimb,
				{ { 0.9 * s, 23.6, 6.4 }, { 1.6 * s, 25.2, 6.8 }, { 2.4 * s, 26.2, 6.2 } },
				0.55,
				{ 0, 0, 1 },
				CORAL
			)
			T.ball(headLimb, { sideOf(head, 20.6, 8.4) * s, 20.6, 8.4 }, 0.7, PEARL)
		end
		T.ball(headLimb, { 0, topOf(head, 7.8) - 0.1, 7.8 }, 0.9, PEARL)
		pet:limbPair("LeftFin", "RightFin", T.at({ 2.2, 12, 3.6 }), function(limb)
			leg:draw(limb, { body }, TEAL)
			fin(limb, { 2.6, 6.8, 7.6 }, { 4.2, 5, 10.2 }, { 1.4, 4.8, 10.6 })
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 9, -1.4 }))
		tail:draw(tailLimb, { body }, TEAL)
		-- The tail ends in a great glassy fan, with smaller fins along it.
		local tip = { 0, 5.6, -17 }
		for _, edge in
			{
				{ { 0, 11, -18.4 }, { 0, 9.6, -21.4 } },
				{ { 0, 9.6, -21.4 }, { 0, 6.4, -22.6 } },
				{ { 0, 6.4, -22.6 }, { 0, 3.6, -20.6 } },
			}
		do
			fin(tailLimb, tip, edge[1], edge[2])
		end
		for _, s in { 1, -1 } do
			fin(tailLimb, { 1.6 * s, 4.4, -8 }, { 4 * s, 3.4, -10.4 }, { 1.4 * s, 3, -11 })
		end

		pet:light(GLOW, 2, 15)
		pet:particles("Bubbles", rgb(226, 250, 246), 8)
		pet:seat(0, 18 / U, 0)
	end,
}

Designs.Kraken = {
	name = "Kraken",
	skeleton = "Tentacled",
	gait = "Crawl",
	scale = 0.5,
	draw = function(pet)
		local PURPLE = rgb(104, 42, 134)
		local PURPLE_DARK = rgb(64, 22, 90)
		local PURPLE_LIGHT = rgb(150, 82, 180)
		local SUCKER = rgb(255, 190, 226)
		local GLOW = rgb(255, 110, 220)
		local EYE_GLOW = rgb(255, 214, 60)
		local PUPIL = rgb(24, 8, 24)
		local GOLD = rgb(255, 196, 56)
		local GOLD_DARK = rgb(206, 140, 30)
		local RUBY = rgb(220, 30, 80)
		local EMERALD = rgb(40, 200, 120)
		local PEARL = rgb(250, 246, 240)
		local BARNACLE = rgb(226, 220, 206)
		local WOOD = rgb(132, 86, 50)
		local WOOD_DARK = rgb(96, 60, 36)

		-- A rounded level of a dome, as wide as `r` and a little deeper, centred across the pet on `zc`.
		local function round(x: number, z: number, zc: number, r: number): boolean
			return r > 0.5 and (math.abs(x + 0.5) / r) ^ 2.3 + (math.abs(z + 0.5 - zc) / (r * 1.08)) ^ 2.3 <= 1
		end

		-- The squat body the tentacles grow from.
		local body = pet:limb("Body", { 0, 5, 0 })
		blob(body, { -8, 2, -8, 7, 8, 7 }, function(x, y, z)
			local t = (y - 1.5) / 7.5
			return round(x, z, 0, 6.6 * math.sqrt(1 - (t * 0.75) ^ 2))
		end, PURPLE)

		-- A huge rounded mantle swelling up and leaning back.
		local head = pet:limb("Head", { 0, 9, 0 })
		local inMantle = blob(head, { -9, 9, -16, 8, 28, 8 }, function(x, y, z)
			local t = (y - 8.5) / 20
			local bulge = if t < 0.35 then 1 - ((0.35 - t) / 0.62) ^ 2 else 1 - ((t - 0.35) / 0.66) ^ 2
			return round(x, z, -0.8 - 5.5 * t ^ 1.4, 8.2 * math.sqrt(math.max(0, bulge)))
		end, PURPLE)
		-- The outermost cell of the mantle at height y, going out from its middle at an angle: 0 is straight ahead,
		-- 90 to its left, 180 straight back.
		local function onMantle(y: number, angle: number): { number }
			local t = (y - 8.5) / 20
			local zc = -0.8 - 5.5 * t ^ 1.4
			local a = math.rad(angle)
			local cell = { 0, y, math.floor(zc) }
			for r = 0, 12, 0.25 do
				local x, z = math.floor(math.sin(a) * r), math.floor(zc + math.cos(a) * r)
				if not inMantle(x, y, z) then
					break
				end
				cell = { x, y, z }
			end
			return cell
		end
		-- A spot on the mantle at height y and an angle round it, up to `size` cells across and tall where the
		-- mantle is there to take it.
		local function dot(y: number, angle: number, color: Color, material: string?, size: number?)
			local cell = onMantle(y, angle)
			local a = math.rad(angle)
			local across = if math.abs(math.cos(a)) > math.abs(math.sin(a)) then { 1, 0, 0 } else { 0, 0, 1 }
			local range = { cell[1], cell[2], cell[3], cell[1], cell[2], cell[3] }
			for _, grow in { across, { 0, 1, 0 } } do
				for _ = 2, size or 1 do
					local ok = true
					for x = range[1], range[4] + grow[1] do
						for yy = range[2], range[5] + grow[2] do
							for z = range[3], range[6] + grow[3] do
								ok = ok and inMantle(x, yy, z)
							end
						end
					end
					if ok then
						range[4] += grow[1]
						range[5] += grow[2]
						range[6] += grow[3]
					end
				end
			end
			head:paint(range[1], range[2], range[3], range[4], range[5], range[6], color, material)
		end
		-- Mottling light and dark, and rows of glowing spots down its sides.
		for _, spot in
			{
				{ 12, 40 },
				{ 16, 65 },
				{ 20, 35 },
				{ 14, 145 },
				{ 19, 115 },
				{ 23, 160 },
				{ 25, 75 },
				{ 21, 180 },
				{ 10, 110 },
				{ 17, 10 },
			}
		do
			dot(spot[1], spot[2], PURPLE_LIGHT, nil, 3)
			dot(spot[1] + 1, -spot[2] - 12, PURPLE_LIGHT, nil, 3)
		end
		for _, spot in { { 15, 25 }, { 22, 100 }, { 18, 160 }, { 26, 130 }, { 13, 85 }, { 24, 20 } } do
			dot(spot[1], spot[2], PURPLE_DARK, nil, 2)
			dot(spot[1] - 1, -spot[2] + 10, PURPLE_DARK, nil, 2)
		end
		for y = 12, 26, 2 do
			dot(y, 88 + (y - 12) * 3, GLOW, NEON)
			dot(y, -88 - (y - 12) * 3, GLOW, NEON)
		end
		-- Barnacles crusted on its back.
		for _, b in { { 16, 170 }, { 17, 160 }, { 13, -150 }, { 14, -155 }, { 21, 185 }, { 24, -165 } } do
			local cell = onMantle(b[1], b[2])
			local out = { cell[1] + (if b[2] > 180 or b[2] < 0 then -1 else 1), cell[2], cell[3] - 1 }
			if not inMantle(out[1], out[2], out[3]) then
				head:box(out[1], out[2], out[3], out[1], out[2], out[3], BARNACLE)
			end
		end

		-- Huge glowing eyes in raised sockets, with slit pupils, under heavy scowling brows; a hooked beak below.
		head:boxPair(3, 9, 3, 7, 14, 6, PURPLE)
		head:paintPair(3, 9, 6, 7, 14, 6, PURPLE_DARK)
		head:paintPair(4, 10, 6, 6, 13, 6, EYE_GLOW, NEON)
		head:paintPair(5, 10, 6, 5, 13, 6, PUPIL)
		head:paintPair(4, 13, 6, 4, 13, 6, SHINE)
		head:paintPair(7, 10, 3, 7, 13, 5, PURPLE_DARK)
		head:boxPair(2, 15, 5, 4, 15, 7, PURPLE)
		head:boxPair(5, 16, 5, 8, 16, 6, PURPLE)
		head:paintPair(2, 15, 5, 4, 15, 7, PURPLE_DARK)
		head:paintPair(5, 16, 5, 8, 16, 6, PURPLE_DARK)

		-- A sunken king's crown, sat crooked on top.
		head:box(-3, 29, -9, 2, 29, -4, GOLD)
		head:paint(-3, 29, -9, 2, 29, -9, GOLD_DARK)
		head:box(-3, 30, -9, -3, 32, -9, GOLD)
		head:box(2, 30, -9, 2, 31, -9, GOLD)
		head:box(-3, 30, -4, -3, 32, -4, GOLD)
		head:box(2, 30, -4, 2, 30, -4, GOLD)
		head:box(-1, 30, -4, 0, 31, -4, GOLD)
		head:box(-1, 32, -4, 0, 32, -4, PEARL)
		head:paint(-1, 29, -4, 0, 29, -4, RUBY)
		head:paint(-3, 29, -7, -3, 29, -6, EMERALD)
		head:paint(2, 29, -7, 2, 29, -6, EMERALD)

		-- Eight thick tentacles, each ending in a curl: two arms raised in front (one brandishing a ship's wheel),
		-- two sprawled out to the sides, two trailing behind, and two rearing up over its back. A pale line of
		-- suckers runs along the inside of every bend (or underneath, where it runs straight), and the tips glow.
		local function tentacle(name: string, pivot: { number }, points: { { number } })
			local limb = pet:limb(name, pivot)
			local t = tube(limb, points, PURPLE)
			local count = #t.cubes
			local function middle(c: { number }, k: number): number
				return (c[k] + c[k + 3]) / 2
			end
			local suckers = {}
			for index, cube in t.cubes do
				if index >= count - 1 then
					limb:paint(cube[1], cube[2], cube[3], cube[4], cube[5], cube[6], GLOW, NEON)
				elseif index > 3 then
					local before, after = t.cubes[math.max(1, index - 3)], t.cubes[math.min(count, index + 3)]
					local axis, most = 2, 0.6
					for k = 1, 3 do
						local bend = (middle(before, k) + middle(after, k)) / 2 - middle(cube, k)
						if k ~= cube[7] and math.abs(bend) > most then
							axis, most = k, math.abs(bend)
						end
					end
					local direction = { 0, -1, 0 }
					if most > 0.6 then
						local bend = (middle(before, axis) + middle(after, axis)) / 2 - middle(cube, axis)
						direction = { 0, 0, 0 }
						direction[axis] = if bend > 0 then 1 else -1
					end
					local s = surfaceCell(t, cube, direction)
					if s and s[2] > 0 then
						table.insert(suckers, s)
					end
				end
			end
			cells(limb, suckers, SUCKER, true)
			return limb
		end

		tentacle(
			"Tentacle1",
			{ 3, 5, 4 },
			andThen(
				{
					{ 3, 5, 4, 2.4 },
					{ 6, 4, 7.5, 2.2 },
					{ 9, 5, 9, 1.9 },
					{ 11.5, 8.5, 9.5, 1.6 },
					{ 12.5, 12.5, 9, 1.4 },
					{ 12.5, 16.5, 8.5, 1.2 },
				},
				curl({
					centre = { 15.5, 16.5, 8.5 },
					plane = { 1, 2 },
					from = math.pi,
					turns = -0.8,
					radius = { 3, 1.2 },
					width = { 1.2, 0.5 },
				})
			)
		)
		local wheelArm = tentacle("Tentacle2", { -4, 5, 4 }, {
			{ -4, 5, 4, 2.4 },
			{ -7, 4, 7.5, 2.2 },
			{ -10, 5.5, 9, 1.9 },
			{ -12, 9, 9.5, 1.5 },
			{ -13, 12.5, 9.5, 1.25 },
			{ -14, 15, 9.5, 1 },
			{ -15.5, 16.5, 9.5, 0.8 },
			{ -16.5, 15.5, 9.5, 0.6 },
			{ -16, 14, 9.5, 0.5 },
		})
		tentacle(
			"Tentacle3",
			{ 5, 4, 0 },
			andThen(
				{ { 5, 4, 0, 2.3 }, { 9, 2.2, 1, 2 }, { 13, 1.8, 1.5, 1.6 }, { 16.5, 1.3, 1.5, 1.2 } },
				curl({
					centre = { 16.5, 4, 1.5 },
					plane = { 1, 2 },
					from = -math.pi / 2,
					turns = 0.8,
					radius = { 2.7, 1.2 },
					width = { 1.2, 0.5 },
				})
			)
		)
		tentacle(
			"Tentacle4",
			{ -6, 4, 0 },
			andThen(
				{ { -6, 4, 0, 2.3 }, { -10, 2.2, 0, 2 }, { -14, 1.8, -0.5, 1.6 }, { -17.5, 1.3, -1, 1.2 } },
				curl({
					centre = { -17.5, 3.8, -1 },
					plane = { 1, 2 },
					from = -math.pi / 2,
					turns = -0.85,
					radius = { 2.5, 1.1 },
					width = { 1.2, 0.5 },
				})
			)
		)
		local back = andThen(
			{ { 4, 4, -4, 2.2 }, { 7, 2.2, -7, 1.9 }, { 10, 1.6, -10, 1.5 }, { 12, 1.2, -13, 1.1 } },
			curl({
				centre = { 12, 3.6, -13 },
				plane = { 3, 2 },
				from = -math.pi / 2,
				turns = -0.8,
				radius = { 2.4, 1.1 },
				width = { 1.1, 0.5 },
			})
		)
		tentacle("Tentacle5", { 4, 4, -4 }, back)
		tentacle("Tentacle6", { -5, 4, -4 }, mirrorPoints(back))
		tentacle(
			"Tentacle7",
			{ 3, 5, -6 },
			andThen(
				{
					{ 3, 5, -6, 2.2 },
					{ 5, 6, -10, 1.9 },
					{ 8, 9, -12, 1.7 },
					{ 10, 14, -12, 1.5 },
					{ 11, 19, -11, 1.3 },
					{ 11, 24, -10, 1.1 },
				},
				curl({
					centre = { 14, 24, -10 },
					plane = { 1, 2 },
					from = math.pi,
					turns = -0.75,
					radius = { 3, 1.2 },
					width = { 1.1, 0.5 },
				})
			)
		)
		tentacle(
			"Tentacle8",
			{ -4, 5, -6 },
			andThen(
				{
					{ -4, 5, -6, 2.2 },
					{ -6, 6, -10, 1.9 },
					{ -9, 10, -12, 1.7 },
					{ -11, 15, -12, 1.5 },
					{ -12, 20, -11, 1.3 },
					{ -12, 25, -10, 1.1 },
				},
				curl({
					centre = { -12, 25, -13 },
					plane = { 3, 2 },
					from = 0,
					turns = 0.75,
					radius = { 3, 1.2 },
					width = { 1.1, 0.5 },
				})
			)
		)

		-- A ship's wheel, torn from a wreck and held up high.
		local function wood(x0: number, y0: number, x1: number, y1: number, color: Color?)
			wheelArm:box(x0, y0, 8, x1, y1, 8, color or WOOD)
		end
		wood(-16, 17, -13, 17)
		wood(-16, 26, -13, 26)
		wood(-19, 20, -19, 23)
		wood(-10, 20, -10, 23)
		for _, corner in
			{ { -17, 18 }, { -18, 19 }, { -12, 18 }, { -11, 19 }, { -17, 25 }, { -18, 24 }, { -12, 25 }, { -11, 24 } }
		do
			wood(corner[1], corner[2], corner[1], corner[2])
		end
		wood(-15, 18, -14, 25, WOOD_DARK)
		wood(-18, 21, -16, 22, WOOD_DARK)
		wood(-13, 21, -11, 22, WOOD_DARK)
		wood(-15, 27, -14, 28)
		wood(-21, 21, -20, 22)
		wood(-9, 21, -8, 22)
		wood(-15, 15, -14, 16)
		wheelArm:box(-15, 21, 9, -14, 22, 9, GOLD)

		pet:light(GLOW, 3, 22)
		pet:particles("Bubbles", SUCKER, 14)
		pet:seat(0, 24, 2)
	end,
}

Designs.Leviathan = {
	name = "Leviathan",
	skeleton = "Serpent",
	gait = "Swim",
	scale = 0.36,
	draw = function(pet)
		local SCALE = rgb(20, 52, 76)
		local SCALE_DARK = rgb(10, 28, 46)
		local SCALE_LIGHT = rgb(42, 102, 126)
		local BELLY = rgb(168, 214, 200)
		local BELLY_DARK = rgb(116, 170, 160)
		local GLOW = rgb(80, 255, 228)
		local FIN = rgb(90, 220, 210)
		local HORN = rgb(222, 232, 226)
		local HORN_DARK = rgb(132, 152, 156)
		local FANG = rgb(248, 250, 242)
		local MOUTH = rgb(66, 14, 38)
		local THROAT = rgb(190, 255, 240)
		local TONGUE = rgb(214, 70, 110)
		local PUPIL = rgb(8, 18, 22)

		-- The long body as tubes: rearing up into a neck at the front, then two great arching coils and a tail,
		-- swaying from side to side. Each length is a limb of its own, so a ripple can run down it.
		local body = pet:limb("Body", { 0, 3, -3 })
		local neck = tube(body, {
			{ 0, 3, -3, 2.8 },
			{ 0, 3.2, 1, 2.8 },
			{ 0, 5.5, 4, 2.6 },
			{ 0, 10, 5.5, 2.5 },
			{ 0, 15, 5.5, 2.4 },
			{ 0, 19, 6.5, 2.2 },
			{ 0, 21.5, 8.5, 2 },
		}, SCALE, { even = true })
		local segment1 = pet:limb("Segment1", { 0, 3, -3 })
		local coil1 = tube(segment1, {
			{ 0, 3, -3, 2.8 },
			{ 0, 3, -6, 2.8 },
			{ 0, 7, -9, 2.7 },
			{ 0, 12, -11.5, 2.6 },
			{ 0, 13, -14, 2.5 },
			{ 0, 9, -17, 2.4 },
			{ 0, 3, -19.5, 2.3 },
			{ 0, 2.2, -21.5, 2.2 },
		}, SCALE, { even = true })
		local segment2 = pet:limb("Segment2", { 0, 2.2, -21.5 }, "Segment1")
		local coil2 = tube(segment2, {
			{ 0, 2.2, -21.5, 2.2 },
			{ -1, 2.4, -24, 2.1 },
			{ -2, 6, -26.5, 2 },
			{ -2.5, 9.5, -29, 1.9 },
			{ -2, 8, -31.5, 1.8 },
			{ -1, 3, -33.5, 1.7 },
			{ 0, 2, -35, 1.6 },
		}, SCALE)
		local tail = pet:limb("Tail", { 0, 2, -35 }, "Segment2")
		local tailTube = tube(tail, {
			{ 0, 2, -35, 1.6 },
			{ 1, 1.5, -37.5, 1.3 },
			{ 1.5, 1.5, -40, 1.1 },
			{ 1.5, 3, -42, 0.9 },
			{ 1.5, 5, -43, 0.7 },
		}, SCALE)
		local tubes = { neck, coil1, coil2, tailTube }

		-- Whether a cell is free for a spike or fin: not in the body, the head, or a spike already drawn.
		local used: { [string]: boolean } = {}
		local function free(cell: { number }): boolean
			local x, y, z = cell[1], cell[2], cell[3]
			if y < 0 or used[`{x},{y},{z}`] or (x >= -6 and x <= 5 and y >= 16 and z >= 5) or z <= -45 then
				return false
			end
			for _, t in tubes do
				if t.inside(x, y, z) then
					return false
				end
			end
			return true
		end
		local function step(cell: { number }, direction: { number }, count: number): { number }
			return { cell[1] + direction[1] * count, cell[2] + direction[2] * count, cell[3] + direction[3] * count }
		end

		-- Along each length: horn spikes down the spine with a glassy fin between them, banded plates down the
		-- belly where it shows, and a glowing line along each flank. Its back faces away from the middle of the
		-- arch it is part of (`focus`), or, up the rearing neck, towards the inside of the curve.
		local function decorate(limb, t: Tube, focus: { number }, inward: boolean, wide: boolean)
			local backs = {}
			for index, cube in t.cubes do
				local _, y, z = cubeMiddle(cube)
				local dy, dz = y - focus[2], z - focus[3]
				if inward then
					dy, dz = -dy, -dz
				end
				local upward = math.abs(dy) >= math.abs(dz)
				if (upward and cube[7] == 2) or (not upward and cube[7] == 3) then
					upward = not upward
				end
				backs[index] = if upward
					then { 0, if dy >= 0 then 1 else -1, 0 }
					else { 0, 0, if dz >= 0 then 1 else -1 }
			end
			local columns = if wide then { 0, 1 } else { 0 }

			-- Spikes first, then the fin fills the gaps between them.
			for pass = 1, 2 do
				local fin = {}
				for _, column in columns do
					for index, cube in t.cubes do
						local back = backs[index]
						local top = surfaceCell(t, cube, back)
						local spike = index % 4 == 0
						if top and back[2] >= 0 and spike == (pass == 1) then
							top = step(top, { 1, 0, 0 }, column)
							local reach = if not spike then 1 elseif cube[4] - cube[1] >= 3 then 3 else 2
							local cellsHere = {}
							for n = 1, reach do
								local cell = step(top, back, n)
								if not free(cell) then
									break
								end
								table.insert(cellsHere, cell)
							end
							for _, cell in cellsHere do
								used[`{cell[1]},{cell[2]},{cell[3]}`] = true
								if not spike then
									table.insert(fin, cell)
								end
							end
							if spike and #cellsHere > 0 then
								local a, b = cellsHere[1], cellsHere[#cellsHere]
								limb:box(a[1], a[2], a[3], b[1], b[2], b[3], HORN)
							end
						end
					end
				end
				if pass == 2 then
					cells(limb, fin, FIN, false, GLASS, 0.3)
				end
			end

			-- Belly plates, light and dark, where the belly faces forwards or back: a row across the belly at each
			-- block, two rows to a plate.
			local rows = {}
			for index, cube in t.cubes do
				local back = backs[index]
				local belly = { 0, -back[2], -back[3] }
				local s = if belly[3] ~= 0 then surfaceCell(t, cube, belly) else nil
				if s and free(step(s, belly, 1)) then
					local x0, x1 = s[1], s[1]
					while t.inside(x0 - 1, s[2], s[3]) do
						x0 -= 1
					end
					while t.inside(x1 + 1, s[2], s[3]) do
						x1 += 1
					end
					local previous = rows[#rows]
					local within = previous
						and previous[2] <= s[2]
						and s[2] <= previous[5]
						and previous[3] <= s[3]
						and s[3] <= previous[6]
					if
						previous
						and not previous.full
						and previous[1] == x0
						and previous[4] == x1
						and math.abs(previous[2] - s[2]) + math.abs(previous[3] - s[3]) == 1
					then
						previous[2], previous[5] = math.min(previous[2], s[2]), math.max(previous[5], s[2])
						previous[3], previous[6] = math.min(previous[3], s[3]), math.max(previous[6], s[3])
						previous.full = true
					elseif not within then
						table.insert(rows, { x0, s[2], s[3], x1, s[2], s[3] })
					end
				end
			end
			for index, r in rows do
				limb:paint(r[1], r[2], r[3], r[4], r[5], r[6], if index % 2 == 0 then BELLY else BELLY_DARK)
			end

			-- Dashes of light along both flanks.
			for _, side in { { 1, 0, 0 }, { -1, 0, 0 } } do
				local dashes = {}
				for index, cube in t.cubes do
					local s = if index % 5 ~= 0 then surfaceCell(t, cube, side) else nil
					if s and free(step(s, side, 1)) then
						table.insert(dashes, s)
					end
				end
				cells(limb, dashes, GLOW, true, NEON)
			end
		end

		-- A dragon's head, jaws wide: fangs, a forked tongue and a glowing throat, slanted glowing eyes under heavy
		-- brows, ridged horns sweeping back, frilled gill fans, whiskers, and a glowing lure dangling over the snout.
		local head = pet:limb("Head", { 0, 21, 8 })
		head:box(-4, 22, 7, 3, 26, 13, SCALE)
		head:box(-3, 21, 7, 2, 27, 13, SCALE)
		head:box(-3, 22, 6, 2, 26, 6, SCALE)
		head:box(-3, 22, 12, 2, 25, 18, SCALE)
		head:box(-2, 22, 19, 1, 24, 21, SCALE)
		head:box(-1, 23, 22, 0, 24, 22, SCALE)
		head:box(-3, 18, 8, 2, 20, 11, SCALE)
		head:box(-3, 17, 12, 2, 18, 18, SCALE)
		head:box(-2, 17, 19, 1, 18, 20, SCALE)
		head:box(-1, 16, 13, 0, 16, 19, SCALE_LIGHT)
		-- Inside the mouth.
		head:paint(-2, 19, 11, 1, 20, 11, THROAT, NEON)
		head:paint(-2, 22, 14, 1, 22, 20, MOUTH)
		head:paint(-2, 18, 12, 1, 18, 19, MOUTH)
		head:box(-1, 19, 12, 0, 19, 15, TONGUE)
		head:boxPair(1, 19, 16, 1, 19, 17, TONGUE)
		for _, z in { 14, 16, 18 } do
			head:boxPair(2, 21, z, 2, 21, z, FANG)
		end
		for _, z in { 13, 15, 17 } do
			head:boxPair(2, 19, z, 2, 19, z, FANG)
		end
		head:boxPair(1, 20, 21, 1, 21, 21, FANG)
		head:boxPair(1, 19, 19, 1, 20, 19, FANG)
		-- Glowing lines along the jaws, nostrils, and nubs of horn up the snout.
		head:paintPair(2, 23, 13, 2, 23, 18, GLOW, NEON)
		head:paintPair(2, 17, 13, 2, 17, 18, GLOW, NEON)
		head:paintPair(1, 24, 21, 1, 24, 21, SCALE_DARK)
		for _, z in { 14, 16, 18 } do
			head:box(-1, 26, z, 0, 26, z, HORN)
		end
		head:box(-1, 25, 20, 0, 25, 20, HORN)
		-- Scales on the cheeks and crown.
		for _, cell in { { 3, 22, 10 }, { 3, 23, 11 }, { 3, 22, 12 }, { 2, 19, 10 } } do
			head:paintPair(cell[1], cell[2], cell[3], cell[1], cell[2], cell[3], SCALE_LIGHT)
		end
		for _, cell in { { 1, 27, 8 }, { 1, 27, 11 } } do
			head:paintPair(cell[1], cell[2], cell[3], cell[1], cell[2], cell[3], SCALE_LIGHT)
		end
		-- Eyes: glowing, slanted, slit-pupilled, under jutting brows.
		head:paintPair(3, 24, 12, 3, 24, 13, GLOW, NEON)
		head:paintPair(3, 25, 11, 3, 25, 12, GLOW, NEON)
		head:paintPair(3, 24, 12, 3, 25, 12, PUPIL)
		head:boxPair(3, 27, 10, 4, 27, 14, SCALE_DARK)
		head:boxPair(4, 26, 13, 4, 26, 14, SCALE_DARK)
		-- Horns: ridged, sweeping back and up, tipped with light.
		local horns = {
			tubePair(head, {
				{ 3.5, 28.5, 10, 1 },
				{ 4.5, 30, 7, 1 },
				{ 5.5, 31, 4, 0.8 },
				{ 6.5, 31.5, 1, 0.7 },
				{ 7.5, 32.5, -1.5, 0.5 },
				{ 8, 34, -3, 0.5 },
			}, HORN),
		}
		for _, horn in horns do
			for index, cube in horn.cubes do
				local color = if index == #horn.cubes then GLOW elseif index % 3 == 0 then HORN_DARK else nil
				if color then
					head:paint(
						cube[1],
						cube[2],
						cube[3],
						cube[4],
						cube[5],
						cube[6],
						color,
						if color == GLOW then NEON else nil
					)
				end
			end
		end
		-- Gill fans: glassy frills on spines, behind the jaw.
		for _, column in
			{ { 3, 20, 24 }, { 4, 19, 25 }, { 5, 18, 26 }, { 6, 17, 27 }, { 7, 17, 27 }, { 8, 18, 26 }, { 9, 19, 25 } }
		do
			head:boxPair(4, column[2], column[1], 4, column[3], column[1], FIN, GLASS, 0.3)
		end
		for _, spine in
			{ { { 5, 22, 8 }, { 5, 28, 5 } }, { { 5, 21, 8 }, { 5, 21, 1 } }, { { 5, 21, 8 }, { 5, 16, 4 } } }
		do
			local spineCells = line(spine[1], spine[2])
			cells(head, spineCells, HORN)
			cells(mirrored(head), spineCells, HORN)
			local tip = spineCells[#spineCells]
			head:paintPair(tip[1], tip[2], tip[3], tip[1], tip[2], tip[3], GLOW, NEON)
		end
		-- Whiskers drooping from the lip.
		local whiskers = {
			tubePair(head, {
				{ 2.5, 22.5, 19.5, 0.5 },
				{ 4.5, 22.5, 20.5, 0.5 },
				{ 5.5, 20.5, 20.5, 0.5 },
				{ 6.5, 17.5, 19.5, 0.5 },
				{ 6.5, 15.5, 18.5, 0.5 },
			}, SCALE_LIGHT),
		}
		for _, whisker in whiskers do
			local tip = whisker.cubes[#whisker.cubes]
			head:paint(tip[1], tip[2], tip[3], tip[4], tip[5], tip[6], GLOW, NEON)
		end
		-- The lure: a stalk arching forward from the brow, with a glowing bulb hanging in front of the jaws.
		tube(head, {
			{ 0, 28.5, 12.5, 0.5 },
			{ 0, 31, 14, 0.5 },
			{ 0, 32, 16.5, 0.5 },
			{ 0, 31, 19, 0.5 },
			{ 0, 29.5, 20.5, 0.5 },
		}, HORN_DARK)
		head:box(-2, 26, 20, 0, 28, 22, GLOW, NEON)

		-- Front fins: webbed fans of glass on bony rays, glowing at the tips.
		pet:limbPair("LeftFin", "RightFin", { 3, 3, 2 }, function(fin)
			fin:box(3, 2, 0, 3, 4, 3, SCALE)
			for _, row in
				{ { 4, 0, 4 }, { 5, -1, 4 }, { 6, -2, 3 }, { 7, -3, 2 }, { 8, -4, 1 }, { 9, -5, -1 }, { 10, -5, -3 } }
			do
				fin:box(row[1], 3, row[2], row[1], 3, row[3], FIN, GLASS, 0.3)
			end
			for _, ray in { { 4, 6, 3 }, { 4, 8, 1 }, { 5, 9, -1 }, { 7, 10, -3 } } do
				fin:paint(ray[1], 3, ray[3], ray[2], 3, ray[3], HORN)
			end
			for _, tip in { { 6, 3 }, { 8, 1 }, { 9, -1 }, { 10, -3 } } do
				fin:paint(tip[1], 3, tip[2], tip[1], 3, tip[2], GLOW, NEON)
			end
		end)

		-- A great forked tail fan of glass, ribbed with bone.
		for _, column in
			{
				{ -45, 3, 9 },
				{ -46, 2, 12 },
				{ -47, 1, 14 },
				{ -48, 1, 16 },
				{ -49, 1, 8, 11, 17 },
				{ -50, 1, 5, 13, 18 },
				{ -51, 1, 3, 15, 18 },
			}
		do
			tail:box(1, column[2], column[1], 1, column[3], column[1], FIN, GLASS, 0.3)
			if column[4] then
				tail:box(1, column[4], column[1], 1, column[5], column[1], FIN, GLASS, 0.3)
			end
		end
		for _, ray in
			{ { { 1, 6, -45 }, { 1, 14, -47 } }, { { 1, 6, -45 }, { 1, 17, -50 } }, { { 1, 5, -45 }, { 1, 2, -50 } } }
		do
			local rayCells = line(ray[1], ray[2])
			cells(tail, rayCells, HORN, true)
			local tip = rayCells[#rayCells]
			tail:paint(tip[1], tip[2], tip[3], tip[1], tip[2], tip[3], GLOW, NEON)
		end
		tail:paint(1, 15, -51, 1, 18, -51, GLOW, NEON)
		tail:paint(1, 1, -51, 1, 3, -51, GLOW, NEON)

		decorate(body, neck, { 0, 16, -6 }, true, true)
		decorate(segment1, coil1, { 0, 2, -12.5 }, false, false)
		decorate(segment2, coil2, { -2, 1, -28.5 }, false, false)
		decorate(tail, tailTube, { 1, -20, -39 }, false, false)

		pet:light(GLOW, 3, 22)
		pet:particles("Bubbles", GLOW, 16)
		pet:seat(0, 16, -13)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Volcano

Designs.ObsidianGoat = {
	name = "Obsidian Goat",
	skeleton = "Quadruped",
	gait = "Hop",
	scale = 0.6,
	draw = function(pet)
		local OBSIDIAN = rgb(42, 34, 54)
		local SHEEN = rgb(84, 70, 112)
		local SHARD = rgb(120, 80, 190)
		local SHARD_GLOW = rgb(196, 150, 255)
		local EMBER = rgb(255, 128, 36)
		local ASH = rgb(118, 110, 116)
		local HORN = rgb(150, 140, 138)
		local HORN_DARK = rgb(104, 96, 96)
		local HOOF = rgb(24, 20, 28)

		-- A goat of glassy black volcanic rock, glinting where the light catches it, with purple crystals
		-- growing from its back and a few cracks still glowing from the lava it cooled from.
		local body = pet:limb("Body", { 0, 7, -1 })
		body:box(-3, 6, -6, 2, 10, 3, OBSIDIAN, GLASS)
		body:box(-2, 5, -5, 1, 5, 2, OBSIDIAN, GLASS)
		body:box(-2, 11, -5, 1, 11, 2, OBSIDIAN, GLASS)
		body:paintPair(2, 9, -4, 2, 10, -3, SHEEN, GLASS)
		body:paintPair(2, 8, 1, 2, 9, 2, SHEEN, GLASS)
		body:paint(-2, 11, -1, -1, 11, 0, SHEEN, GLASS)
		body:paintPair(2, 6, -2, 2, 7, -2, EMBER, NEON)
		body:paintPair(2, 7, -1, 2, 7, -1, EMBER, NEON)
		body:paint(2, 8, -5, 2, 8, -5, EMBER, NEON)
		for _, crystal in
			{
				{ -1, 12, -1, 0, 14, 0 },
				{ 0, 12, -3, 1, 15, -2 },
				{ -2, 12, -4, -2, 13, -4 },
				{ -1, 12, -5, -1, 14, -5 },
				{ 1, 12, 1, 1, 12, 1 },
			}
		do
			body:box(crystal[1], crystal[2], crystal[3], crystal[4], crystal[5], crystal[6], SHARD, GLASS, 0.1)
		end
		body:box(-1, 15, 0, -1, 15, 0, SHARD_GLOW, NEON)
		body:box(1, 16, -2, 1, 16, -2, SHARD_GLOW, NEON)
		body:box(-1, 15, -5, -1, 15, -5, SHARD_GLOW, NEON)
		body:box(-2, 14, -4, -2, 14, -4, SHARD_GLOW, NEON)

		-- A long face with an ashen muzzle and beard, glowing ember eyes, and great ram's horns curling round.
		local head = pet:limb("Head", { 0, 10, 4 })
		head:box(-2, 9, 3, 1, 13, 7, OBSIDIAN, GLASS)
		head:box(-2, 9, 8, 1, 11, 10, OBSIDIAN, GLASS)
		head:paint(-2, 9, 10, 1, 10, 10, ASH)
		head:paint(-1, 10, 10, 0, 10, 10, HOOF)
		head:paint(-2, 11, 8, 1, 11, 9, SHEEN, GLASS)
		head:box(-1, 7, 8, 0, 8, 9, ASH)
		head:box(-1, 6, 9, 0, 6, 9, ASH)
		head:paintPair(1, 12, 6, 1, 12, 7, EMBER, NEON)
		head:paintPair(1, 12, 7, 1, 12, 7, HOOF)
		-- Each horn rises from the crown, sweeps back, curls down behind the eye and forward again.
		head:boxPair(1, 14, 4, 2, 14, 6, HORN)
		head:boxPair(2, 15, 1, 3, 15, 4, HORN)
		head:boxPair(2, 11, 0, 3, 14, 1, HORN)
		head:boxPair(2, 11, 2, 3, 11, 3, HORN)
		head:boxPair(3, 12, 4, 3, 12, 4, HORN)
		head:paintPair(2, 15, 3, 3, 15, 3, HORN_DARK)
		head:paintPair(2, 13, 0, 3, 13, 1, HORN_DARK)

		-- Slim legs on black hooves, built for leaping up crags.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 1.5, 6, 1.5 }, function(leg)
			leg:box(1, 1, 0, 2, 5, 2, OBSIDIAN, GLASS)
			leg:box(1, 0, 0, 2, 0, 2, HOOF)
			leg:paint(2, 3, 2, 2, 3, 2, EMBER, NEON)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 1.5, 6, -4.5 }, function(leg)
			leg:box(1, 4, -6, 2, 8, -3, OBSIDIAN, GLASS)
			leg:box(1, 1, -5, 2, 3, -4, OBSIDIAN, GLASS)
			leg:box(1, 0, -5, 2, 0, -4, HOOF)
		end)

		-- A short tail, tipped with a crystal.
		local tail = pet:limb("Tail", { 0, 10, -6 })
		tail:box(-1, 10, -8, 0, 11, -7, OBSIDIAN, GLASS)
		tail:box(-1, 12, -8, 0, 12, -8, SHARD, GLASS, 0.1)

		pet:seat(0, 11, -2)
	end,
}

Designs.CinderBoar = {
	name = "Cinder Boar",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.6,
	draw = function(pet)
		local BOAR = rgb(62, 42, 38)
		local BOAR_DARK = rgb(42, 28, 26)
		local ASH = rgb(104, 96, 98)
		local SNOUT = rgb(150, 92, 84)
		local NOSTRIL = rgb(66, 36, 36)
		local TUSK = rgb(236, 226, 206)
		local LAVA = rgb(255, 112, 24)
		local LAVA_HOT = rgb(255, 196, 40)
		local HOOF = rgb(30, 24, 24)

		-- A hulking boar, high in the shoulder, with lava glowing through cracks in its hide and a ridge of
		-- burning bristles down its back.
		local body = pet:limb("Body", { 0, 7, -1 })
		body:box(-4, 5, -2, 3, 11, 4, BOAR)
		body:box(-3, 5, -8, 2, 10, -3, BOAR)
		body:paintPair(3, 5, -1, 3, 6, 4, BOAR_DARK)
		body:paintPair(3, 7, 0, 3, 8, 0, LAVA, NEON)
		body:paintPair(3, 8, 1, 3, 8, 2, LAVA, NEON)
		body:paintPair(3, 9, 2, 3, 9, 2, LAVA_HOT, NEON)
		body:paintPair(2, 7, -6, 2, 7, -4, LAVA, NEON)
		body:paintPair(2, 8, -7, 2, 8, -7, LAVA, NEON)
		body:paint(-4, 10, -2, 3, 11, -2, ASH)
		body:paint(-3, 10, -8, 2, 10, -8, ASH)
		-- Burning bristles, tallest over the shoulders.
		body:box(-1, 12, -1, 0, 13, 4, LAVA, NEON)
		body:box(-1, 14, 0, 0, 14, 0, LAVA_HOT, NEON)
		body:box(-1, 14, 2, 0, 15, 2, LAVA_HOT, NEON)
		body:box(-1, 14, 4, 0, 14, 4, LAVA_HOT, NEON)
		body:box(-1, 11, -7, 0, 11, -3, LAVA, NEON)
		body:box(-1, 12, -6, 0, 12, -6, LAVA_HOT, NEON)
		body:box(-1, 12, -4, 0, 12, -4, LAVA_HOT, NEON)

		-- A heavy head with a wide snout, small burning eyes under a heavy brow, pointed ears, and tusks curling up.
		local head = pet:limb("Head", { 0, 8, 4 })
		head:box(-3, 5, 5, 2, 10, 8, BOAR)
		head:box(-2, 5, 9, 1, 8, 10, BOAR)
		head:box(-2, 5, 11, 1, 7, 11, SNOUT)
		head:paintPair(0, 6, 11, 0, 6, 11, NOSTRIL)
		head:paint(-2, 5, 9, 1, 5, 10, NOSTRIL)
		head:boxPair(2, 6, 10, 2, 7, 10, TUSK)
		head:boxPair(3, 8, 10, 3, 9, 10, TUSK)
		head:boxPair(3, 10, 9, 3, 10, 9, TUSK)
		head:paintPair(2, 9, 7, 2, 9, 8, LAVA_HOT, NEON)
		head:boxPair(1, 11, 7, 2, 11, 8, BOAR_DARK)
		head:boxPair(2, 11, 5, 3, 12, 6, BOAR)
		head:boxPair(3, 13, 5, 3, 13, 5, BOAR_DARK)
		head:paintPair(3, 11, 6, 3, 12, 6, LAVA, NEON)
		head:paint(-1, 10, 6, 0, 10, 8, ASH)
		head:box(-1, 11, 5, 0, 12, 6, LAVA, NEON)

		-- Short, thick legs on cloven hooves.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2.5, 5, 1.5 }, function(leg)
			leg:box(1, 1, 0, 3, 4, 2, BOAR)
			leg:box(1, 0, 0, 3, 0, 2, HOOF)
			leg:paint(2, 0, 2, 2, 0, 2, BOAR_DARK)
			leg:paint(3, 3, 1, 3, 3, 1, LAVA, NEON)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2, 5, -6 }, function(leg)
			leg:box(1, 1, -7, 2, 4, -5, BOAR)
			leg:box(1, 0, -7, 2, 0, -5, HOOF)
		end)

		-- A thin tail ending in a smouldering tuft.
		local tail = pet:limb("Tail", { 0, 9, -8 })
		tail:box(-1, 8, -9, 0, 9, -9, BOAR)
		tail:box(-1, 6, -10, 0, 8, -10, BOAR_DARK)
		tail:box(-1, 5, -10, 0, 5, -10, LAVA, NEON)

		pet:seat(0, 11, -5)
	end,
}

Designs.VolcanoTortoise = {
	name = "Volcano Tortoise",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with its beak, nails and tail of
		-- parts at any angle, and a real flame at the crater of its volcano.
		local U = 1.2
		local T = inUnits(U)
		local SHELL = look(84, 66, 58)
		local SHELL_LIGHT = look(112, 90, 76)
		local RIM = look(60, 48, 44)
		local CONE = look(124, 112, 108)
		local CONE_DARK = look(92, 82, 80)
		local SKIN = look(130, 112, 74)
		local SKIN_DARK = look(98, 82, 52)
		local PLASTRON = look(176, 150, 96)
		local LAVA = look(255, 112, 24, NEON)
		local LAVA_HOT = look(255, 196, 40, NEON)
		local BEAK = rgb(70, 58, 44)
		local NAIL = rgb(214, 204, 186)

		-- Plates in rings round the dome: a rim of dark plates at the bottom, a ring above, three over the top.
		local seeds = {}
		for _, ring in { { 8.6, 10.4, 10, RIM }, { 13, 7.4, 8, SHELL }, { 16.4, 3.2, 3, SHELL_LIGHT } } do
			for index = 0, ring[3] - 1 do
				local angle = (index + 0.5) / ring[3] * math.pi * 2
				table.insert(
					seeds,
					{ math.sin(angle) * ring[2], ring[1], -1 + math.cos(angle) * ring[2] * 1.15, ring[4] }
				)
			end
		end
		local function plates(p: Vec): Look
			local best, second, shade = math.huge, math.huge, SHELL
			for _, seed in seeds do
				local dx, dy, dz = p[1] - seed[1], p[2] - seed[2], p[3] - seed[3]
				local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
				if dist < best then
					best, second, shade = dist, best, seed[4]
				elseif dist < second then
					second = dist
				end
			end
			return if second - best < 0.75 then LAVA else shade
		end
		local function scaly(p: Vec): Look?
			return if noise(p) < 0.2 then SKIN_DARK else nil
		end

		-- A high domed shell over a pale belly, and a little volcano on top, glowing at the crater, with lava
		-- running down its sides and over the shell.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 10.6, -1 }, { 8.8, 7.2, 10.4 }), SHELL)
		body:carve(ellipsoid({ 0, 0, -1 }, { 12, 6.8, 14 }))
		body:add(ellipsoid({ 0, 7.6, -1 }, { 6.8, 1.6, 8.2 }), PLASTRON)
		body:coat(function(p, open)
			if p[2] < 8.2 and open(0, -1, 0) then
				return PLASTRON
			end
			return plates(p)
		end)
		body:add(rod({ { 0, 16.6, -1, 3.4 }, { 0, 20.4, -1.2, 1.8 } }), CONE)
		body:carve(ellipsoid({ 0, 20.8, -1.2 }, { 1.3, 1, 1.3 }))
		body:paint(ellipsoid({ 0, 20.8, -1.2 }, { 1.9, 1.6, 1.9 }), LAVA_HOT, nil, true)
		body:coat(function(p, open)
			if p[2] > 17.6 and p[2] < 20.2 and not open(0, 1, 0) then
				return if noise(p) < 0.3 then CONE_DARK else nil
			end
			return nil
		end)
		for _, flow in { { 1.2, 0.6, 5.6, 3.2 }, { -1.4, -0.2, -6.4, 2.4 }, { 0.6, -1.6, 2, -8.4 } } do
			local function side(x: number, z: number): Vec
				return { x, 0, z }
			end
			local a, b, c = side(flow[1], -1 + flow[2]), side(flow[1] * 2.6, -1 + flow[2] * 2.6), side(flow[3], flow[4])
			body:trace({ { a[1], 20, a[3] }, { b[1], 16.6, b[3] }, { c[1], 13, c[3] } }, { 0, -1, 0 }, LAVA)
		end

		-- A wrinkled neck and a blunt head with a hooked beak and ember eyes.
		local head = newSculpt(U)
		head:add(rod({ { 0, 10, 6.6, 2.6 }, { 0, 11.4, 10, 2.1 } }), SKIN)
		head:add(ellipsoid({ 0, 12.2, 12.2 }, { 2.4, 2.1, 2.7 }), SKIN)
		head:coat(function(p)
			if p[3] < 10.6 and p[3] % 1.4 < 0.45 then
				return SKIN_DARK
			end
			return scaly(p)
		end)

		-- Stumpy, scaly elephant legs with pale nails.
		local function leg(s: Sculpt, z: number)
			s:add(rod({ { 5, 9.4, z, 2.7 }, { 5.4, 2.6, z + 0.4, 2.5 } }), SKIN)
			s:add(ellipsoid({ 5.4, 1.3, z + 0.8 }, { 2.7, 1.3, 2.7 }), SKIN)
			s:coat(scaly)
		end
		local front = newSculpt(U)
		leg(front, 4.6)
		local back = newSculpt(U)
		leg(back, -7)

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 8.6, -10.4, 1.5 }, { 0, 7.8, -12.6, 0.7 } }), SKIN)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 10, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, SHELL)
		bodyLimb:fire(T.at({ 0, 21.8, -1.2 }), 3, rgb(255, 100, 24), rgb(255, 210, 60))
		local headLimb = pet:limb("Head", T.at({ 0, 10, 6.4 }))
		head:draw(headLimb, { body }, SHELL)
		slitEyes(headLimb, head, { 12.8, 13.4 }, { 13.1, 12.1 }, 0.5, LAVA_HOT.color, NEON)
		T.blade(headLimb, { 0, 12.4, 14.4 }, { 0, 11.6, 15.4 }, 1.6, 1.5, { 1, 0, 0 }, BEAK)
		T.taper(headLimb, { 0, 11.6, 15.4 }, { 0, 10.2, 15.5 }, 1.4, 1.3, { 1, 0, 0 }, BEAK)
		local function nails(limb: Limb, z: number)
			for _, dx in { -1.3, 0, 1.3 } do
				T.ball(limb, { 5.4 + dx * 0.9, 0.8, z + 2.9 }, { 1, 0.9, 0.9 }, NAIL)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 5, 9.4, 4.6 }), function(limb)
			front:draw(limb, { body }, SHELL)
			nails(limb, 4.6)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 5, 9.4, -7 }), function(limb)
			back:draw(limb, { body }, SHELL)
			nails(limb, -7)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 8.6, -10 }))
		tail:draw(tailLimb, { body }, SHELL)
		T.taper(tailLimb, { 0, 7.9, -12.4 }, { 0, 7.2, -14 }, 0.8, 0.8, { 0, 1, 0 }, SKIN.color)

		pet:light(LAVA.color, 2.2, 16)
		pet:seat(0, 17.6 / U, 4.6 / U)
	end,
}

Designs.FireSalamander = {
	name = "Fire Salamander",
	skeleton = "LowSlung",
	gait = "Crawl",
	scale = 0.5,
	draw = function(pet)
		-- Sculpted in the units it is built in (one to a block), with gills of flame, eyes and toes of parts at any
		-- angle, and a real flame at the tip of its tail.
		local U = 1
		local T = inUnits(U)
		local BLACK = look(34, 28, 32)
		local BLACK_LIGHT = look(60, 50, 56)
		local YELLOW = look(255, 210, 40)
		local ORANGE = look(255, 142, 32)
		local BELLY = look(74, 60, 64)
		local MOUTH = look(120, 40, 36)
		local FLAME = rgb(242, 82, 28)
		local IRIS = rgb(255, 196, 40)

		-- Glossy black, splashed with big blotches of yellow and orange.
		local function blotches(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, -1, 0) then
				return BELLY
			end
			local n = noise({ math.floor(p[1] / 2.2), math.floor(p[2] / 2.2), math.floor(p[3] / 2.2) })
			if n < 0.22 then
				return YELLOW
			elseif n < 0.34 then
				return ORANGE
			elseif n > 0.92 then
				return BLACK_LIGHT
			end
			return nil
		end

		-- A long, low body.
		local body = newSculpt(U)
		body:add(rod({ { 0, 3.6, 5, 3.2 }, { 0, 3.8, -1, 3.4 }, { 0, 3.6, -6.6, 3 } }), BLACK)
		body:coat(blotches)

		-- A wide, flat head with bulging eyes and a broad smile.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 3.9, 9.4 }, { 3.7, 2.1, 3.4 }), BLACK)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 2.2 * s, 5.4, 10.4 }, { 1.3, 1.3, 1.3 }), BLACK)
		end
		head:coat(function(p, open)
			if open(0, -1, 0) then
				return BELLY
			end
			return if noise(p) < 0.15 then YELLOW else nil
		end)
		for _, side in { 1, -1 } do
			head:trace({ { 0, 3.2, 12.6 }, { 0, 3, 10.4 }, { 0, 3.4, 8 } }, { -side, 0, 0 }, MOUTH)
		end
		head:trace({ { -1.6, 3.2, 0 }, { 0, 2.9, 0 }, { 1.6, 3.2, 0 } }, { 0, 0, -1 }, MOUTH)

		-- Short legs splayed out to the sides.
		local function leg(s: Sculpt, z: number)
			s:add(rod({ { 2.4, 3.4, z, 1.3 }, { 4.6, 2.6, z + 0.6, 1 }, { 5.6, 1, z + 1.2, 0.85 } }), BLACK)
			s:coat(blotches)
		end
		local front = newSculpt(U)
		leg(front, 3.4)
		local back = newSculpt(U)
		leg(back, -4.8)

		-- A long tail swinging to one side, banded yellow.
		local tail = newSculpt(U)
		tail:add(
			rod({ { 0, 3.6, -8.6, 2.7 }, { 1.6, 3, -14, 1.9 }, { 4, 2.6, -18, 1.2 }, { 6, 2.6, -21, 0.7 } }),
			BLACK
		)
		tail:coat(function(p, open)
			if open(0, -1, 0) then
				return BELLY
			end
			return if (p[3] % 3) < 1 then YELLOW else nil
		end)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 3.6, 0 })), { head, front, frontMirror, back, backMirror, tail }, BLACK)
		local headLimb = pet:limb("Head", T.at({ 0, 3.8, 6.4 }))
		head:draw(headLimb, { body }, BLACK)
		for _, s in { 1, -1 } do
			T.ball(headLimb, { 2.6 * s, 5.8, 11.2 }, 1.5, IRIS)
			T.ball(headLimb, { 2.75 * s, 5.95, 11.75 }, { 0.5, 1.1, 0.5 }, EYE)
			-- Feathery gills of fire fanning out behind its head.
			for index, direction in { { 1, 0.7, -0.6 }, { 1, 0.15, -0.8 }, { 1, -0.35, -0.5 } } do
				feather(
					headLimb,
					T.at({ 3 * s, 4.4 + index * 0.1, 7.6 }),
					{ direction[1] * s, direction[2], direction[3] },
					(5.2 - index * 0.5) / U,
					1.2 / U,
					0.4 / U,
					{ 0, 1, 0 },
					{
						{ color = FLAME, material = NEON, to = 0.4 },
						{ color = ORANGE.color, material = NEON, to = 0.75 },
						{ color = YELLOW.color, material = NEON, to = 1 },
					}
				)
			end
		end
		local function toes(limb: Limb, z: number)
			for _, dz in { -0.8, 0.2, 1.2 } do
				T.taper(
					limb,
					{ 5.6, 0.9, z + 1.2 + dz * 0.6 },
					{ 6.8, 0.35, z + 1.2 + dz * 1.4 },
					0.5,
					0.45,
					{ 0, 1, 0 },
					YELLOW.color
				)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 2.4, 3.4, 3.4 }), function(limb)
			front:draw(limb, { body }, BLACK)
			toes(limb, 3.4)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 2.4, 3.4, -4.8 }), function(limb)
			back:draw(limb, { body }, BLACK)
			toes(limb, -4.8)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 3.6, -8 }))
		tail:draw(tailLimb, { body }, BLACK)
		tailLimb:fire(T.at({ 6.2, 3.6, -21.4 }), 2.5, FLAME, IRIS)

		pet:light(FLAME, 2, 14)
		pet:seat(0, 7.4 / U, -1 / U)
	end,
}

Designs.Chimera = {
	name = "Chimera",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with horns, fangs, claws and mane
		-- spikes of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local LION = look(226, 162, 72)
		local LION_LIGHT = look(244, 204, 132)
		local LION_DARK = look(196, 128, 50)
		local MANE = look(184, 92, 38)
		local MANE_DARK = look(140, 62, 28)
		local NOSE = look(90, 50, 40)
		local MOUTH = look(70, 20, 16)
		local FIRE = look(255, 120, 30, NEON)
		local GOAT = look(112, 98, 88)
		local GOAT_LIGHT = look(150, 136, 124)
		local GOAT_DARK = look(78, 68, 62)
		local SNAKE = look(74, 150, 72)
		local SNAKE_DARK = look(46, 104, 50)
		local SNAKE_BELLY = look(196, 220, 140)
		local HORN = rgb(190, 180, 168)
		local HORN_DARK = rgb(130, 120, 112)
		local FANG = rgb(250, 246, 236)
		local AMBER = rgb(255, 176, 40)
		local VENOM = rgb(200, 255, 60)
		local TONGUE = rgb(230, 40, 60)
		local CLAW = rgb(60, 40, 30)

		local function lion(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, -1, 0) and p[2] < 14 then
				return LION_LIGHT
			end
			return if noise(p) < 0.1 then LION_DARK else nil
		end

		-- A lion's body, deep in the chest and narrow at the waist, and rising from its back on a shaggy neck, a
		-- goat's head with a beard.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 16, 4 }, { 5, 5.4, 5.6 }), LION)
		body:add(ellipsoid({ 0, 15.4, -2.6 }, { 4.2, 4.4, 5.2 }), LION)
		body:add(ellipsoid({ 0, 16, -8.4 }, { 4.6, 5, 4.4 }), LION)
		body:add(rod({ { 0, 18.6, -3.6, 2.2 }, { 0, 23, -2.4, 1.7 } }), GOAT)
		body:add(ellipsoid({ 0, 24.6, -1 }, { 1.9, 2, 2.4 }), GOAT)
		body:add(ellipsoid({ 0, 24, 1.4 }, { 1.15, 1.25, 1.5 }), GOAT_LIGHT)
		body:add(rod({ { 0, 22.6, 1.2, 0.6 }, { 0, 20.8, 1.6, 0.35 } }), GOAT_DARK)
		body:coat(function(p, open)
			if p[2] > 18.4 then
				if p[2] < 22.4 and noise(p) < 0.3 then
					return GOAT_DARK
				end
				return nil
			end
			return lion(p, open)
		end)

		-- The lion's head in a great shaggy mane: glowing eyes, a heavy brow, and jaws open on a throat of fire.
		local head = newSculpt(U)
		head:add(rod({ { 0, 17, 7, 3.6 }, { 0, 19, 9.4, 3.2 } }), MANE)
		head:add(ellipsoid({ 0, 19.6, 9.6 }, { 5.2, 5.6, 3.2 }), MANE)
		head:add(ellipsoid({ 0, 20, 11.8 }, { 3.4, 3.4, 3.4 }), LION)
		head:add(ellipsoid({ 0, 18.6, 14.8 }, { 2.1, 1.8, 2.1 }), LION_LIGHT)
		head:add(ellipsoid({ 0, 16.5, 13.8 }, { 1.9, 0.95, 2.3 }), LION_LIGHT)
		head:add(ellipsoid({ 0, 19.6, 16.7 }, { 0.8, 0.6, 0.5 }), NOSE)
		head:add(rod({ { -2.4, 22.2, 14, 0.9 }, { 0, 22.5, 14.6, 1 }, { 2.4, 22.2, 14, 0.9 } }), LION_DARK)
		head:carve(ellipsoid({ 0, 17.6, 15.4 }, { 1.5, 0.75, 2 }))
		head:paint(ellipsoid({ 0, 17.6, 15.4 }, { 2, 1.2, 2.5 }), MOUTH, nil, true)
		head:paint(ellipsoid({ 0, 17.6, 14.2 }, { 1, 0.6, 1.2 }), FIRE, nil, true)
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if z < 12.4 and (x / 5.3) ^ 2 + ((y - 19.6) / 5.7) ^ 2 + ((z - 9.6) / 3.3) ^ 2 <= 1.02 then
				return if noise(p) < 0.35 then MANE_DARK else nil
			end
			return lion(p, open)
		end)

		local front = newSculpt(U)
		front:add(rod({ { 3.4, 14, 5, 2.5 }, { 3.6, 8, 6, 2 }, { 3.6, 2.6, 6.2, 1.9 } }), LION)
		front:add(ellipsoid({ 3.6, 1.5, 7.2 }, { 2.2, 1.5, 2.6 }), LION)
		local back = newSculpt(U)
		back:add(ellipsoid({ 3.6, 15, -8.4 }, { 2.9, 4.6, 3.8 }), LION)
		back:add(rod({ { 3.8, 11, -10, 2.1 }, { 3.9, 6, -11, 1.6 }, { 3.9, 2.6, -9.8, 1.7 } }), LION)
		back:add(ellipsoid({ 3.9, 1.5, -8.8 }, { 2.1, 1.5, 2.5 }), LION)
		for _, leg in { front, back } do
			leg:coat(lion)
		end

		-- A serpent for a tail, rearing up behind with its hood spread.
		local tail = newSculpt(U)
		tail:add(
			rod({ { 0, 18, -12, 1.5 }, { 0, 20, -15, 1.35 }, { 0, 23.4, -16.4, 1.25 }, { 0, 26, -15.6, 1.2 } }),
			SNAKE
		)
		tail:add(ellipsoid({ 0, 26.2, -15.8 }, { 2.7, 2.3, 0.9 }), SNAKE)
		tail:add(ellipsoid({ 0, 27.2, -17.6 }, { 1.25, 1.05, 1.9 }), SNAKE)
		tail:coat(function(p, open)
			if open(0, 0, -1) and p[2] < 26 then
				return SNAKE_BELLY
			end
			return if p[2] % 1.6 < 0.5 then SNAKE_DARK else nil
		end)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 16, -2 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, LION)
		slitEyes(bodyLimb, body, { 24.9, 0.6 }, { 25.2, -0.8 }, 0.45, AMBER, NEON)
		for _, s in { 1, -1 } do
			T.branch(bodyLimb, {
				{ 1 * s, 26, -1.6 },
				{ 2.2 * s, 27.8, -3.6 },
				{ 3.1 * s, 27.6, -6 },
				{ 2.9 * s, 25.8, -7.6 },
				{ 2.2 * s, 24.6, -7 },
			}, 1.1, { 1, 0, 0 }, HORN)
			T.ball(bodyLimb, { 2.6 * s, 27.9, -4.8 }, 1, HORN_DARK)
		end
		local headLimb = pet:limb("Head", T.at({ 0, 17, 7 }))
		head:draw(headLimb, { body }, LION)
		slitEyes(headLimb, head, { 20.8, 14.6 }, { 21.2, 13 }, 0.6, AMBER, NEON)
		for _, s in { 1, -1 } do
			T.taper(headLimb, { 1.2 * s, 18.2, 16.2 }, { 1.25 * s, 16.6, 16.6 }, 0.55, 0.5, { 1, 0, 0 }, FANG)
			T.taper(headLimb, { 1.1 * s, 16.9, 15.6 }, { 1.15 * s, 17.9, 16 }, 0.5, 0.45, { 1, 0, 0 }, FANG)
			T.ball(headLimb, { 3.6 * s, 23.2, 10.8 }, { 1.4, 1.6, 0.9 }, LION.color)
		end
		-- Spikes of mane bristling out all round its face.
		for index = 0, 13 do
			local angle = index / 14 * math.pi * 2
			local out = { math.cos(angle), math.sin(angle), 0 }
			local root = vadd({ 0, 19.6, 9.8 }, { out[1] * 4.2, out[2] * 4.6, 0 })
			local tip = vadd(root, { out[1] * 2.6, out[2] * 2.4, -1.6 })
			T.taper(headLimb, root, tip, 1.6, 1, { 0, 0, 1 }, if index % 2 == 0 then MANE.color else MANE_DARK.color)
		end
		headLimb:fire(T.at({ 0, 17.4, 17.6 }), 3, rgb(255, 110, 30), rgb(255, 210, 60))
		local function claws(limb: Limb, x: number, z: number)
			for _, dx in { -1, 0, 1 } do
				T.taper(limb, { x + dx, 1.3, z - 1 }, { x + dx * 1.1, 0.3, z + 0.8 }, 0.45, 0.4, { 0, 1, 0 }, CLAW)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.4, 14, 5 }), function(limb)
			front:draw(limb, { body }, LION)
			claws(limb, 3.6, 9.6)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3.6, 15, -8.4 }), function(limb)
			back:draw(limb, { body }, LION)
			claws(limb, 3.9, -6.4)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 18, -11.5 }))
		tail:draw(tailLimb, { body }, LION)
		for _, s in { 1, -1 } do
			T.ball(tailLimb, { 0.9 * s, 27.7, -18.4 }, 0.5, VENOM, NEON)
			T.taper(tailLimb, { 0.5 * s, 26.6, -19.2 }, { 0.5 * s, 25.6, -19.6 }, 0.35, 0.3, { 1, 0, 0 }, FANG)
			T.taper(tailLimb, { 0, 26.8, -19.4 }, { 0.6 * s, 26.6, -21.2 }, 0.35, 0.25, { 0, 1, 0 }, TONGUE)
		end

		pet:light(FIRE.color, 2.2, 16)
		pet:particles("Embers", rgb(255, 200, 50), 10)
		pet:seat(0, 21 / U, -6 / U)
	end,
}

Designs.LavaGolem = {
	name = "Lava Golem",
	skeleton = "Biped",
	gait = "Stomp",
	scale = 0.48 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with spikes, drips and knuckles of
		-- parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local ROCK = look(74, 64, 62)
		local ROCK_LIGHT = look(110, 98, 94)
		local ROCK_DARK = look(52, 44, 44)
		local LAVA = look(255, 112, 24, NEON)
		local LAVA_HOT = look(255, 196, 40, NEON)
		local SHADES = { ROCK, ROCK_LIGHT, ROCK_DARK, ROCK }

		-- Slabs of rock fitted round a molten core: each cell takes the shade of the slab whose centre is nearest,
		-- and where two slabs meet, the lava glows through the seam.
		local seeds = {}
		for index = 1, 90 do
			local x = (noise({ index, 1, 7 }) - 0.5) * 30
			local y = noise({ index, 3, 11 }) * 36
			local z = (noise({ index, 5, 13 }) - 0.5) * 12
			table.insert(seeds, { x, y, z, SHADES[index % 4 + 1] })
		end
		local function slabs(p: Vec): Look
			local best, second, shade = math.huge, math.huge, ROCK
			for _, seed in seeds do
				local dx, dy, dz = p[1] - seed[1], (p[2] - seed[2]) * 0.8, p[3] - seed[3]
				local dist = dx * dx + dy * dy + dz * dz
				if dist < best then
					best, second, shade = dist, best, seed[4]
				elseif dist < second then
					second = dist
				end
			end
			if math.sqrt(second) - math.sqrt(best) < 0.32 then
				return LAVA
			end
			return shade
		end
		local function coatSlabs(s: Sculpt)
			s:coat(function(p)
				return slabs(p)
			end)
		end

		-- A broad, hunched body with a ridge of rocks down its back, and its molten heart showing in its chest.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 20, 0 }, { 7, 7.4, 5.4 }), ROCK)
		body:add(ellipsoid({ 0, 14, 0.4 }, { 5.4, 4.4, 4.4 }), ROCK)
		body:add(ellipsoid({ 0, 25.4, -0.6 }, { 8.6, 3.6, 5 }), ROCK)
		for _, y in { 26, 22.6, 19.2, 15.8 } do
			body:add(ellipsoid({ 0, y, -5.2 }, { 1.6, 1.6, 1.4 }), ROCK)
		end
		coatSlabs(body)
		body:carve(ellipsoid({ 0, 20.6, 5.8 }, { 2.4, 2.6, 1.6 }))
		body:paint(ellipsoid({ 0, 20.6, 5.8 }, { 3, 3.2, 2.2 }), LAVA_HOT, nil, true)

		-- A small head sunk between its shoulders.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 29.4, 1.6 }, { 2.8, 2.6, 2.6 }), ROCK)
		coatSlabs(head)

		-- Huge boulder shoulders, and long arms down to fists that nearly drag on the ground.
		local arm = newSculpt(U)
		arm:add(ellipsoid({ 9.4, 25, -0.4 }, { 3.8, 3.6, 3.8 }), ROCK)
		arm:add(rod({ { 10, 22, -0.2, 2.6 }, { 11, 15, 0.2, 2.3 } }), ROCK)
		arm:add(rod({ { 11, 15, 0.2, 2.5 }, { 11.2, 8, 0.6, 2.7 } }), ROCK)
		arm:add(ellipsoid({ 11.2, 4.8, 1 }, { 3.3, 3.3, 3.5 }), ROCK)
		coatSlabs(arm)

		-- Short, massive legs on wide feet.
		local leg = newSculpt(U)
		leg:add(rod({ { 3.6, 12.4, 0, 3.5 }, { 3.8, 5, 0.3, 3.3 } }), ROCK)
		leg:add(ellipsoid({ 3.8, 1.9, 1.2 }, { 3.9, 1.9, 4.5 }), ROCK)
		coatSlabs(leg)

		local legMirror, armMirror = leg:mirror(), arm:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 14, 0 }))
		body:draw(bodyLimb, { head, leg, legMirror, arm, armMirror }, ROCK)
		local headLimb = pet:limb("Head", T.at({ 0, 27, 1 }))
		head:draw(headLimb, { body }, ROCK)
		-- Burning eyes and mouth, and a crown of molten spikes dripping down its face.
		local face = frontOf(head, 1, 29.8)
		for _, s in { 1, -1 } do
			T.blade(
				headLimb,
				{ 0.5 * s, 29.8, face },
				{ 1.8 * s, 30.2, face - 0.4 },
				0.8,
				0.4,
				{ 0, 0, 1 },
				LAVA_HOT.color,
				NEON
			)
		end
		T.blade(
			headLimb,
			{ -1, 28, frontOf(head, 0, 28) },
			{ 1, 28, frontOf(head, 0, 28) },
			0.45,
			0.4,
			{ 0, 0, 1 },
			LAVA.color,
			NEON
		)
		for index, spike in
			{ { 0, 0.4, 3.4 }, { 1.4, -0.2, 2.4 }, { -1.4, -0.2, 2.4 }, { 0.8, 1.4, 1.8 }, { -0.8, 1.4, 1.8 } }
		do
			local x, z = spike[1], spike[2]
			local y = topOf(head, z + 1.6, x)
			T.taper(
				headLimb,
				{ x, y - 0.6, z + 1.6 },
				{ x * 1.4, y + spike[3], z + 1.2 },
				1.1,
				1.1,
				{ 0, 0, 1 },
				if index == 1 then LAVA_HOT.color else LAVA.color,
				NEON
			)
		end
		for _, x in { -1.6, 0.6, 1.8 } do
			local y = 30.6 - math.abs(x) * 0.3
			T.blade(
				headLimb,
				{ x, y, frontOf(head, x, y) - 0.1 },
				{ x, y - 1.6, frontOf(head, x, y - 1.6) - 0.1 },
				0.4,
				0.35,
				{ 0, 0, 1 },
				LAVA.color,
				NEON
			)
		end
		local function knuckles(limb: Limb, x: number)
			for _, dy in { -1.2, 0, 1.2 } do
				T.taper(
					limb,
					{ x, 4.8 + dy, 3.6 },
					{ x * 1.02, 4.8 + dy * 1.2, 5.4 },
					1,
					1,
					{ 0, 1, 0 },
					ROCK_LIGHT.color
				)
			end
		end
		local left = pet:limb("LeftArm", T.at({ 9, 25, 0 }))
		arm:draw(left, { body }, ROCK)
		knuckles(left, 11.2)
		local right = pet:limb("RightArm", T.at({ -9, 25, 0 }))
		armMirror:draw(right, { body }, ROCK)
		knuckles(right, -11.2)
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 3.6, 12.4, 0 }), function(limb)
			leg:draw(limb, { body }, ROCK)
		end)

		pet:light(LAVA.color, 2.6, 18)
		pet:particles("Embers", LAVA_HOT.color, 12)
		pet:seat(0, 29 / U, -3 / U)
	end,
}

Designs.Cerberus = {
	name = "Cerberus",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.42 * 1.4,
	draw = function(pet)
		-- Modelled in finer units than it is built in: 1.4 of them to a block.
		local U = 1.4
		local function at(p: { number }): { number }
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local FUR = look(64, 48, 54)
		local FUR_DARK = look(30, 22, 28)
		local HORN = look(58, 46, 48)
		local CLAW = look(226, 216, 196)
		local FANG = look(246, 240, 224)
		local GUM = look(112, 18, 28)
		local EMBER = look(255, 76, 24, NEON)
		local FLAME = look(255, 146, 30, NEON)
		local HOT = look(255, 226, 90, NEON)
		local STEEL = look(196, 198, 210)
		local IRON = look(84, 84, 96)

		-- A hunched, heavy-shouldered hellhound, fire showing through cracks between its ribs, a row of bone
		-- spikes and tongues of fire down its spine.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 20, 4 }, { 7.5, 8, 9 }), FUR)
		body:add(ellipsoid({ 0, 25.5, 2.5 }, { 7, 5, 8 }), FUR)
		body:add(ellipsoid({ 0, 20.5, -7 }, { 5.6, 6.5, 8 }), FUR)
		body:add(ellipsoid({ 0, 20, -15 }, { 6.5, 7, 7 }), FUR)
		-- Molten veins tracing the muscles of its shoulders, ribs and haunches, as if fire ran under its hide.
		for _, side in { 1, -1 } do
			for _, vein in
				{
					{ { 0, 26, 6.5 }, { 0, 21, 10 }, { 0, 17, 11.5 } },
					{ { 0, 21, 10 }, { 0, 16, 7.5 }, { 0, 13.5, 6 } },
					{ { 0, 24, 1.5 }, { 0, 20, 0 }, { 0, 16.5, -1.5 } },
					{ { 0, 24.5, -3.5 }, { 0, 20, -5 }, { 0, 16, -7 } },
					{ { 0, 25.5, -11 }, { 0, 21, -14 }, { 0, 18.5, -18.5 } },
					{ { 0, 21, -14 }, { 0, 16, -13 }, { 0, 14, -16 } },
				}
			do
				body:trace(vein, { -side, 0, 0 }, EMBER)
			end
		end
		-- The height of the top of its back at a point along it.
		local function top(z: number): number
			local cz, y = math.floor(z / U), math.floor(20 / U)
			while body:has(0, y + 1, cz) do
				y += 1
			end
			return (y + 1) * U
		end
		-- Bone spikes jutting from its shoulders, and a mane of fire streaming back along its spine.
		for _, spike in { { 4, 6.5, 6 }, { -4, 6.5, 6 } } do
			local y = top(spike[2]) - 1
			body:add(rod({ { spike[1], y, spike[2], 1.4 }, { spike[1] * 1.5, y + spike[3], spike[2] - 3, 0.3 } }), HORN)
		end
		for index, z in { 4, 0, -4, -8, -12.5, -17 } do
			local y = top(z) - 1.5
			local tall = if index % 2 == 0 then 1 else 1.35
			body:add(rod({ { 0, y, z, 2 }, { 0, y + 3.5 * tall, z - 2.5, 1.3 } }), EMBER)
			body:add(rod({ { 0, y + 3.5 * tall, z - 2.5, 1.3 }, { 0, y + 6.5 * tall, z - 5, 0.6 } }), FLAME)
			body:add(rod({ { 0, y + 6.5 * tall, z - 5, 0.65 }, { 0, y + 8.5 * tall, z - 6.5, 0.25 } }), HOT)
		end

		-- Three heads on thick necks, each turned its own way: the middle one snarling straight ahead, one reared
		-- up roaring, one low and stalking. Each has eyes burning deep under a heavy brow, curved horns, a crest
		-- of fire, lips curled back from rows of fangs, fire in its throat and dripping from its jaws, and a
		-- studded collar.
		local heads = newSculpt(U)
		local function hound(frame: Frame, k: number)
			local function E(c: { number }, r: { number }): Shape
				return ellipsoid({ c[1] * k, c[2] * k, c[3] * k }, { r[1] * k, r[2] * k, r[3] * k })
			end
			local function R(points: { { number } }): Shape
				local scaled = {}
				for _, p in points do
					table.insert(scaled, { p[1] * k, p[2] * k, p[3] * k, p[4] * k })
				end
				return rod(scaled)
			end
			local function add(s: Shape, l: Look)
				heads:add(s, l, frame)
			end
			add(E({ 0, 0, 1.5 }, { 4, 3.4, 4.2 }), FUR)
			add(E({ 0, -2.6, 2.8 }, { 3.6, 2.2, 2.6 }), FUR)
			add(E({ 0, -0.8, 8 }, { 2.5, 1.9, 5.2 }), FUR)
			add(E({ 0, -5.3, 7 }, { 2.2, 1, 4.6 }), FUR)
			heads:carve(E({ 0, -3.3, 8.3 }, { 1.9, 1.45, 4.8 }), frame)
			heads:paint(E({ 0, -3.3, 8.3 }, { 2.6, 2.1, 5.4 }), GUM, frame, true)
			add(E({ 0, -3.1, 3.6 }, { 1.8, 1.1, 1 }), EMBER)
			add(E({ 0, 1.9, 4.3 }, { 4.1, 1.15, 1.5 }), FUR_DARK)
			add(E({ 0, 0.1, 13 }, { 1.3, 0.9, 0.8 }), FUR_DARK)
			for _, s in { 1, -1 } do
				add(R({ { 1.2 * s, 0.2, 5.9, 0.7 }, { 3.1 * s, 1, 4.6, 0.7 } }), HOT)
				add(R({ { 1.5 * s, -2, 11.2, 0.6 }, { 1.4 * s, -4.6, 11.5, 0.4 } }), FANG)
				add(R({ { 1.2 * s, -4.6, 10.4, 0.55 }, { 1.15 * s, -2.8, 10.6, 0.35 } }), FANG)
				for _, z in { 5.6, 7.3, 9 } do
					add(E({ 1.7 * s, -2.7, z }, { 0.5, 0.65, 0.5 }), FANG)
				end
				for _, z in { 6.4, 8.1 } do
					add(E({ 1.5 * s, -4.1, z }, { 0.5, 0.65, 0.5 }), FANG)
				end
				add(
					R({
						{ 2.3 * s, 2.2, 1.8, 1.15 },
						{ 3.7 * s, 4.2, -0.4, 0.95 },
						{ 4.7 * s, 6.2, -0.2, 0.7 },
						{ 5.1 * s, 7.8, 1.9, 0.4 },
					}),
					HORN
				)
				add(R({ { 4.95 * s, 7.3, 1.2, 0.5 }, { 5.1 * s, 7.9, 2.1, 0.35 } }), EMBER)
				add(R({ { 3 * s, 2, -0.4, 0.95 }, { 3.9 * s, 3, -3.6, 0.3 } }), FUR)
				add(R({ { 2 * s, -3.8, 9, 0.6 }, { 2.3 * s, -7.2, 9.6, 0.3 } }), FLAME)
			end
			add(R({ { 0, 2.9, -0.4, 1.1 }, { 0, 4.6, -2.4, 0.6 } }), EMBER)
			add(R({ { 0, 4.6, -2.4, 0.6 }, { 0, 6, -4, 0.25 } }), FLAME)
			add(R({ { 0, -3.4, 12.4, 0.8 }, { 0, -2.4, 15, 0.3 } }), FLAME)
			for _, a in { 90, 30, 150 } do
				local c, s = math.cos(math.rad(a)), math.sin(math.rad(a))
				add(R({ { c * 3.2, -0.6 + s * 3.2, -2.6, 0.9 }, { c * 5.8, -0.6 + s * 5.8, -2.6, 0.25 } }), STEEL)
			end
		end
		heads:add(rod({ { 0, 23, 7, 4.6 }, { 0, 25, 12, 4.2 }, { 0, 26, 16, 3.9 } }), FUR)
		heads:add(rod({ { 4.5, 22, 7, 4.1 }, { 9, 24.5, 11, 3.6 }, { 12, 26, 13.5, 3.3 } }), FUR)
		heads:add(rod({ { -4.5, 22, 7, 4.1 }, { -9, 22.5, 11.5, 3.6 }, { -12, 22, 14.5, 3.3 } }), FUR)
		hound({ origin = { 0, 26.5, 17 }, pitch = -0.2 }, 1.35)
		hound({ origin = { 12.4, 26.5, 14 }, yaw = 0.6, pitch = 0.35 }, 1.2)
		hound({ origin = { -12.4, 22, 15 }, yaw = -0.5, pitch = -0.3 }, 1.2)

		-- Massive legs with clawed paws wreathed in fire, iron shackles on the forelegs with their chains snapped.
		local function paw(s: Sculpt, x: number, y: number, z: number)
			s:add(ellipsoid({ x, y, z }, { 3.4, 2, 3.8 }), FUR)
			for i = 0, 3 do
				local tx = x - 1.7 + 1.13 * i
				s:add(ellipsoid({ tx, y - 0.5, z + 2.8 }, { 0.75, 1, 1.2 }), FUR)
				s:add(rod({ { tx, y - 0.4, z + 3.4, 0.5 }, { tx, y - 1.3, z + 4.8, 0.3 } }), CLAW)
			end
		end
		local front = newSculpt(U)
		do
			local s = front
			s:add(rod({ { 6.5, 20, 5.5, 4.3 }, { 8, 11, 7, 3.4 } }), FUR)
			s:add(rod({ { 8, 11, 7, 3.2 }, { 8.4, 3.5, 8.6, 2.6 } }), FUR)
			s:trace({ { 0, 18, 8 }, { 0, 12, 8.5 }, { 0, 6, 9.5 } }, { -1, 0, 0 }, EMBER)
			paw(s, 8.4, 2, 10.4)
			s:add(
				shape({ 7.6, 6, 7.9 }, 4, function(x, y, z)
					local r = math.sqrt((x - 7.6) ^ 2 + (z - 7.9) ^ 2)
					return r >= 2 and r <= 3.1 and math.abs(y - 6) <= 0.9
				end),
				IRON
			)
			s:add(
				rod({
					{ 10.4, 5.6, 8.5, 0.55 },
					{ 11.4, 3.6, 9.4, 0.5 },
					{ 12, 1.6, 8.6, 0.5 },
					{ 13.4, 0.5, 10.4, 0.5 },
				}),
				IRON
			)
			s:add(rod({ { 5.2, 2.6, 8.4, 0.9 }, { 4.6, 6, 7.4, 0.25 } }), FLAME)
			s:add(rod({ { 10, 2.6, 8.8, 0.9 }, { 10.6, 5.6, 7.8, 0.25 } }), EMBER)
			s:add(rod({ { 7.6, 3, 11.6, 0.8 }, { 7.6, 5.4, 12.2, 0.25 } }), FLAME)
		end
		local back = newSculpt(U)
		do
			local s = back
			s:add(ellipsoid({ 6.8, 16.5, -15 }, { 4, 6.8, 6.2 }), FUR)
			s:add(rod({ { 7.2, 12, -18.5, 3 }, { 7.8, 5, -20.5, 2.3 } }), FUR)
			s:add(rod({ { 7.8, 5, -20.5, 2.3 }, { 7.8, 2.5, -17.4, 2.2 } }), FUR)
			s:trace({ { 0, 21, -12 }, { 0, 16, -15 }, { 0, 11, -18.5 } }, { -1, 0, 0 }, EMBER)
			paw(s, 7.8, 1.8, -15.2)
			s:add(rod({ { 9.4, 5, -20, 0.8 }, { 10.2, 8.5, -21, 0.25 } }), FLAME)
			s:add(rod({ { 5.8, 5, -20.5, 0.8 }, { 5.2, 8.2, -21.4, 0.25 } }), EMBER)
		end

		-- A long whip of a tail, spiked along its back, ending in a burst of fire.
		local tail = newSculpt(U)
		tail:add(
			rod({
				{ 0, 22, -20, 3.4 },
				{ 0, 25, -25, 2.7 },
				{ 0, 30, -28.5, 2 },
				{ 0, 35, -28.5, 1.5 },
				{ 0, 38, -25.5, 1.1 },
			}),
			FUR
		)
		for _, spike in { { 26.5, -26.5, 1 }, { 31, -30.5, 0 }, { 35.5, -30.3, -0.5 } } do
			tail:add(
				rod({ { 0, spike[1], spike[2], 0.8 }, { 0, spike[1] + 1 + spike[3], spike[2] - 2.6, 0.25 } }),
				HORN
			)
		end
		tail:add(rod({ { 0, 35, -28.5, 1.35 }, { 0, 38, -25.5, 1 } }), EMBER)
		tail:add(rod({ { 0, 38, -25.5, 1.2 }, { 0, 40.5, -22.5, 0.4 } }), FLAME)
		tail:add(rod({ { 0, 39, -24.5, 0.8 }, { 0, 42.5, -23.5, 0.2 } }), HOT)
		tail:add(rod({ { 0, 37.5, -27, 0.9 }, { 0, 40.5, -30, 0.2 } }), FLAME)
		tail:add(rod({ { 1, 38.5, -25, 0.8 }, { 2.6, 41, -24, 0.2 } }), FLAME)
		tail:add(rod({ { -1, 38.5, -25, 0.8 }, { -2.6, 41, -24, 0.2 } }), FLAME)
		-- Each limb is built knowing which others overlap it.
		local frontRight, backRight = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", at({ 0, 20, -4 })), { heads, front, frontRight, back, backRight, tail })
		heads:draw(pet:limb("Head", at({ 0, 24, 9 })), { body })
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", at({ 6.5, 19, 6 }), function(limb)
			front:draw(limb, { body })
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", at({ 6.5, 18, -15 }), function(limb)
			back:draw(limb, { body })
		end)
		tail:draw(pet:limb("Tail", at({ 0, 22, -21 })), { body })

		pet:light(rgb(255, 96, 30), 3.2, 26)
		pet:particles("Embers", rgb(255, 196, 60), 18)
		pet:seat(0, 27 / U, -6 / U)
	end,
}

Designs.EternalPhoenix = {
	name = "Eternal Phoenix",
	skeleton = "Winged",
	gait = "Walk",
	scale = 0.42,
	draw = function(pet)
		local RED = rgb(214, 30, 24)
		local RED_DARK = rgb(146, 14, 18)
		local ORANGE = rgb(255, 118, 22)
		local AMBER = rgb(255, 166, 30)
		local YELLOW = rgb(255, 218, 60)
		local GOLD = rgb(255, 190, 40)
		local GOLD_DEEP = rgb(226, 140, 22)
		local BEAK = rgb(255, 208, 80)
		local BEAK_TIP = rgb(206, 112, 20)
		local EYE_RED = rgb(255, 36, 20)
		local PUPIL = rgb(36, 8, 8)
		local WHITE = rgb(255, 255, 255)
		local TALON = rgb(64, 30, 22)
		local ETERNAL = rgb(150, 255, 245)
		local UP, FRONT = { 0, 1, 0 }, { 0, 0, 1 }

		local function band(color: Color, to: number, material: string?): Band
			return { color = color, to = to, material = material }
		end
		-- The burning feathers: deep red at the root, through orange to a glowing yellow tip.
		local FLIGHT = { band(RED, 0.38), band(ORANGE, 0.66), band(AMBER, 0.86, NEON), band(YELLOW, 1, NEON) }
		local COVERT = { band(RED, 0.68), band(ORANGE, 1) }
		local PLUME = { band(RED, 0.4), band(ORANGE, 0.7), band(YELLOW, 0.9, NEON), band(ETERNAL, 1, NEON) }

		-- Its body: an upright red torso leaning forward, a golden breast covered in overlapping feathers of red,
		-- orange and gold, and a ruff of red feathers round its neck.
		local body = pet:limb("Body", { 0, 16, 0 })
		local lean = { { 1, 0, 0 }, { 0, 0.978, 0.208 }, { 0, -0.208, 0.978 } }
		egg(body, { 0, 16, 0 }, { 10, 15, 9.5 }, lean, RED)
		egg(body, { 0, 15, 2.4 }, { 8.4, 12.5, 6 }, lean, GOLD)
		egg(body, { 0, 22.5, 1.6 }, { 6.4, 8, 6.4 }, nil, RED)
		egg(body, { 0, 22, 3.4 }, { 4.6, 7, 3.6 }, nil, GOLD)
		-- Overlapping scale feathers over the breast, each pointing down, in a mottle of red, orange and gold.
		local tones = { RED, ORANGE, GOLD_DEEP, AMBER, RED, YELLOW, ORANGE }
		for row = 0, 7 do
			local y = 20.2 - row * 1.45
			for column = -3, 3 do
				local x = column * 1.35 + (if row % 2 == 1 then 0.68 else 0)
				local inside = 1 - (x / 4.2) ^ 2 - ((y - 15) / 6.25) ^ 2
				if inside > 0.15 and math.abs(x) < 3.9 then
					local z = 2.4 + 3 * math.sqrt(inside) + 0.2 * (y - 15) / 6.25 + 0.15
					local normal = vnorm({ x / 4.2 ^ 2, (y - 15) / 6.25 ^ 2 * 0.6, (z - 2.4) / 9 })
					local down = vnorm(vsub({ 0, -1, 0.15 }, vscale(normal, vdot({ 0, -1, 0.15 }, normal))))
					local tone = tones[(row * 3 + column + 9) % #tones + 1]
					local top = vadd({ x, y + 0.7, z }, vscale(normal, 0.05 * (row % 2)))
					taper(body, top, vadd(top, vscale(down, 2)), 1.6, 0.45, normal, tone)
				end
			end
		end
		-- Rows of feathers down its back, between the wings.
		for row = 0, 2 do
			for column = -1, 1 do
				local x = column * 2.2 + (if row % 2 == 1 then 1.1 else 0)
				local root = { x, 21 - row * 3, -3.6 + row * 0.3 }
				feather(body, root, { x * 0.08, -1, -0.45 }, 4.2, 2.2, 0.5, vnorm({ x * 0.1, 0.3, -1 }), COVERT)
			end
		end
		for layer = 0, 1 do
			for index = 0, 8 do
				local a = math.rad(-160 + index * 40 + layer * 20)
				local radius = 3 + layer * 0.35
				local root = { math.sin(a) * radius, 21.5 - layer * 1.6, 1.4 + math.cos(a) * radius }
				local out = { math.sin(a) * 0.8, -1.5, math.cos(a) * 0.7 - 0.35 }
				local length = 4.5 + layer * 1.5
				feather(
					body,
					root,
					out,
					length,
					1.9,
					0.5,
					{ math.sin(a), 0.35, math.cos(a) },
					if layer == 0 then COVERT else FLIGHT
				)
			end
		end

		-- A fierce eagle's head, sculpted in fine blocks as one solid piece: a flat crown, a hard brow jutting over
		-- the eyes, angular cheeks, and a long hooked beak growing out of the face, parted on the fire in its throat.
		-- The eyes are painted flat on the face, narrow and pointed, slanting up and back under the brow. A crest of
		-- five flame plumes sweeps back from the crown, burning at its tip.
		local head = pet:limb("Head", { 0, 24, 2.5 })
		local function tone(color: Color, material: string?): Look
			return { color = color, material = material }
		end
		local FACE, FACE_DEEP, NAPE = tone(rgb(255, 206, 62)), tone(rgb(240, 160, 34)), tone(RED)
		local BILL, HOOK, CERE = tone(BEAK), tone(BEAK_TIP), tone(rgb(255, 228, 120))
		local GAPE, LID = tone(rgb(90, 30, 18)), tone(rgb(70, 10, 12))
		-- Narrower from side to side than it is round: a raptor's beak.
		local function narrow(s: Shape, squeeze: number): Shape
			return shape(s.centre, s.radius, function(x, y, z)
				return s.inside(x * squeeze, y, z)
			end)
		end
		local skull = newSculpt(0.5)
		skull:add(ellipsoid({ 0, 27.6, 3.4 }, { 3.1, 2.8, 3.9 }), FACE)
		skull:add(ellipsoid({ 0, 26.2, 4.7 }, { 2.7, 1.9, 3.2 }), FACE)
		skull:add(ellipsoid({ 0, 26.9, 1 }, { 2.8, 2.8, 2.6 }), NAPE)
		skull:carve(shape({ 0, 31, 3 }, 6, function(x, y)
			return y > 30.1 + math.abs(x) * 0.1
		end))
		-- The brow: a hard shelf over each eye, low at the beak and rising back, frowning.
		for _, s in { 1, -1 } do
			skull:add(
				rod({ { 1 * s, 29, 6.3, 0.6 }, { 2.3 * s, 29.2, 5.3, 0.65 }, { 3 * s, 29.4, 3.9, 0.5 } }),
				FACE_DEEP
			)
		end
		skull:add(
			narrow(
				rod({
					{ 0, 27.5, 6.4, 1.45 },
					{ 0, 27.2, 8.6, 1.1 },
					{ 0, 26.4, 10.3, 0.75 },
					{ 0, 25.2, 11, 0.45 },
					{ 0, 24.4, 10.7, 0.3 },
				}),
				1.35
			),
			BILL
		)
		skull:add(narrow(rod({ { 0, 25.4, 6.8, 0.85 }, { 0, 25.1, 9.2, 0.5 } }), 1.3), BILL)
		skull:carve(shape({ 0, 25.9, 8.6 }, 3, function(x, y, z)
			return math.abs(y - 25.9) < 0.3 and z > 7.4 and z < 10 and math.abs(x) < 1.2
		end))
		skull:add(ellipsoid({ 0, 25.9, 7.4 }, { 0.9, 0.35, 0.6 }), tone(ORANGE, NEON))
		skull:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			local side = if x > 0 then 1 else -1
			-- The hooked tip, darker; the waxy band at the base of the beak; the nostrils.
			if z > 9.4 and y < 26.2 and math.abs(x) < 1.3 then
				return HOOK
			end
			if z > 6.2 and z < 7.1 and y > 26.2 and math.abs(x) < 1.4 then
				return CERE
			end
			if z > 7.6 and z < 8.3 and y > 27.1 and y < 27.7 and math.abs(x) > 0.45 and open(side, 0, 0) then
				return GAPE
			end
			-- The line of the mouth running back under the eye.
			if math.abs(y - 25.95) < 0.3 and z > 5.2 and z < 7.6 and open(side, 0, 0) then
				return GAPE
			end
			-- The eye: flat on the side of the face, pointed at both ends, slanting up towards the back, with a
			-- dark rim round it and a slit pupil.
			if math.abs(x) > 1.6 and open(side, 0, 0) and z > 3 and z < 6.6 then
				local t = (6.3 - z) / 3
				local top = 27.95 + 0.55 * t
				local thick = 0.95 * math.max(0, math.sin(math.pi * math.clamp(t, 0, 1))) ^ 0.7
				if t >= 0 and t <= 1 and y <= top and y >= top - thick then
					if z > 4.7 and z < 5.1 then
						return tone(PUPIL)
					end
					if z >= 5.1 and z < 5.5 and y > top - 0.45 then
						return tone(WHITE, NEON)
					end
					return tone(EYE_RED, NEON)
				end
				if t >= -0.12 and t <= 1.12 and y <= top + 0.35 and y >= top - thick - 0.3 then
					return LID
				end
			end
			-- Red feathers at the back of the head, in a point down the nape.
			if z < 2 - (y - 26) * 0.35 then
				return NAPE
			end
			return nil
		end)
		skull:draw(head, nil, FACE, true)
		-- The crest: five plumes sweeping back from the crown, the middle one longest and burning at its tip.
		for k = -2, 2 do
			local a = math.abs(k)
			local root = { k * 0.9, 29.4, 2.4 - a * 0.4 }
			local reach = 1 - a * 0.25
			local mid = { k * 1.3, 32 + 2.5 * reach, -0.8 - a * 0.3 }
			local tip = { k * 1.7, 34 + 6 * reach, -5.5 - a * 0.6 }
			local facing = vnorm({ k * 0.25, 0.6, 1 })
			blade(head, root, mid, 1.6, 0.5, facing, RED)
			local three = vlerp(mid, tip, 0.5)
			blade(head, mid, three, 1.35, 0.45, facing, ORANGE)
			taper(head, three, tip, 1.15, 0.45, facing, if k == 0 then ETERNAL else YELLOW, NEON)
		end
		head:fire({ 0, 40.6, -6.2 }, 9, ORANGE, YELLOW)

		-- Great wings spread wide, layer over layer: short red coverts along the arm, then long secondaries, then
		-- the longest flight feathers fanning out at the tip, each burning from red to a glowing yellow tip.
		pet:limbPair("LeftWing", "RightWing", { 4.2, 21, -1 }, function(wing)
			local arm = { { 4.2, 21, -1 }, { 10.5, 23, -2.6 }, { 16.5, 22.4, -4 }, { 22, 20.4, -5.4 } }
			local function along(t: number): Vec
				local f = t * (#arm - 1)
				local index = math.min(#arm - 1, math.floor(f) + 1)
				return vlerp(arm[index], arm[index + 1], f - (index - 1))
			end
			local surface = vnorm({ 0, 0.15, 1 })
			for index = 1, #arm - 1 do
				blade(wing, arm[index], arm[index + 1], 2.8 - index * 0.5, 1.6, surface, RED_DARK)
			end
			egg(wing, arm[2], { 2.8, 2.8, 2 }, nil, RED)
			egg(wing, arm[3], { 2.3, 2.3, 1.8 }, nil, RED)
			for index = 0, 11 do
				local t = 0.04 + index * 0.08
				local root = vadd(along(t), { 0, -0.6, 0.55 + (index % 2) * 0.14 })
				local tilt = vnorm({ 0.1 + t * 0.4, -1, -0.15 })
				feather(
					wing,
					root,
					tilt,
					4.8 - t * 1.4,
					2.3,
					0.5,
					vnorm({ 0.03 * (index % 2 * 2 - 1), 0.15, 1 }),
					COVERT
				)
			end
			for index = 0, 5 do
				local t = 0.05 + index * 0.1
				local root = vadd(along(t), { 0, -2.2, 0.1 + (index % 2) * 0.14 })
				local tilt = vnorm({ 0.12 + t * 0.45, -1, -0.2 })
				feather(
					wing,
					root,
					tilt,
					9.5 + index * 0.4,
					2.5,
					0.5,
					vnorm({ 0.03 * (index % 2 * 2 - 1), 0.12, 1 }),
					FLIGHT
				)
			end
			for index = 0, 6 do
				local t = 0.58 + index * 0.07
				local root = vadd(along(t), { 0, -1.2, -0.35 + (index % 2) * 0.14 })
				local fan = index / 6
				local tilt = vnorm({ 0.3 + fan * 0.55, -1 + fan * 0.22, -0.25 })
				feather(
					wing,
					root,
					tilt,
					11.5 + index * 0.45,
					2.3,
					0.5,
					vnorm({ 0.03 * (index % 2 * 2 - 1), 0.12, 1 }),
					FLIGHT
				)
			end
			-- Small feathers over the top of the arm, overlapping back from its leading edge.
			for index = 0, 9 do
				local t = 0.05 + index * 0.1
				local root = vadd(along(t), { 0, 1, 0.9 })
				feather(
					wing,
					root,
					{ 0.25, -0.35, -1 },
					2.6,
					2,
					0.45,
					vnorm({ 0, 1, 0.25 }),
					{ band(RED, 0.6), band(ORANGE, 1) }
				)
			end
			wing:fire(vadd(along(1), { 7.5, -5, -0.5 }), 4, ORANGE, YELLOW)
		end)

		-- Strong red thighs over golden legs, gripping talons, and fire burning round its feet.
		pet:limbPair("LeftLeg", "RightLeg", { 2.6, 9, 0.5 }, function(leg)
			egg(leg, { 2.7, 8.8, 0.6 }, { 4.2, 6, 4.6 }, nil, RED)
			for _, flake in
				{
					{ 2.4, 10.4, 2.7, ORANGE },
					{ 3.6, 10, 2.4, RED },
					{ 2.6, 8.6, 2.8, AMBER },
					{ 3.9, 8.2, 2.2, ORANGE },
					{ 3.1, 6.9, 2.4, GOLD_DEEP },
					{ 4.6, 9, 0.9, AMBER },
					{ 4.7, 7.4, 0.6, ORANGE },
				}
			do
				local normal = vnorm({ flake[1] - 2.7, 0.2, flake[3] - 0.6 })
				local top = { flake[1], flake[2] + 0.8, flake[3] }
				taper(leg, top, vadd(top, { 0, -2, 0.2 }), 1.7, 0.45, normal, flake[4])
			end
			blade(leg, { 2.9, 6.2, 1.2 }, { 3.1, 2, 1.8 }, 1.4, 1.4, FRONT, GOLD)
			egg(leg, { 3.1, 1.9, 1.9 }, { 1.8, 1.6, 1.8 }, nil, GOLD)
			for _, dx in { -1.3, 0, 1.3 } do
				blade(leg, { 3.1, 1.4, 2.2 }, { 3.1 + dx, 0.7, 4.8 }, 0.9, 0.9, UP, GOLD)
				taper(leg, { 3.1 + dx, 0.75, 4.7 }, { 3.1 + dx * 1.1, 0.4, 5.7 }, 0.8, 0.7, { 1, 0, 0 }, TALON)
			end
			blade(leg, { 3.1, 1.4, 1.6 }, { 3.1, 0.6, -0.4 }, 0.9, 0.9, UP, GOLD)
			taper(leg, { 3.1, 0.65, -0.3 }, { 3.1, 0.4, -1.2 }, 0.8, 0.7, { 1, 0, 0 }, TALON)
			leg:fire({ 3, 0.8, 2.6 }, 8, rgb(255, 80, 20), YELLOW)
		end)

		-- A long tail of fanned flame feathers, the middle ones longest and tipped with eternal blue.
		local tail = pet:limb("Tail", { 0, 10, -3.5 })
		for k = -3, 3 do
			local a = math.abs(k)
			local facing = vnorm({ 0, 1, -0.3 })
			local root = vadd({ k * 0.5, 10, -4 }, vscale(facing, (a % 2) * 0.16))
			feather(
				tail,
				root,
				{ k * 0.28, -0.36, -1 },
				15 + (3 - a) * 2.5,
				2.4,
				0.5,
				facing,
				if a == 0 then PLUME else FLIGHT
			)
		end
		for k = -2, 2 do
			local facing = vnorm({ 0, 1, -0.2 })
			local root = vadd({ k * 0.7, 11, -4.2 }, vscale(facing, 0.6 + (math.abs(k) % 2) * 0.15))
			feather(tail, root, { k * 0.3, -0.3, -1 }, 8, 2.3, 0.5, facing, COVERT)
		end
		-- Two long streamers trailing far behind, tipped with eternal blue.
		for _, s in { 1, -1 } do
			local points = {
				{ 0.8 * s, 9.5, -4.5 },
				{ 2.5 * s, 7, -12 },
				{ 4.5 * s, 5.5, -20 },
				{ 6 * s, 6, -27 },
				{ 6.5 * s, 8.5, -32 },
			}
			local colors = { RED, ORANGE, AMBER, YELLOW }
			for index = 1, #points - 2 do
				blade(
					tail,
					points[index],
					points[index + 1],
					1.5 - index * 0.15,
					0.4,
					UP,
					colors[index],
					if index >= 3 then NEON else nil
				)
			end
			taper(tail, points[#points - 1], points[#points], 1.1, 0.4, UP, ETERNAL, NEON)
		end
		tail:fire({ 0, 3, -25 }, 6, ORANGE, YELLOW)

		pet:light(rgb(255, 140, 40), 3.4, 26)
		pet:particles("Embers", rgb(255, 200, 70), 20)
		pet:seat(0, 23.5, -3)
	end,
}

Designs.LavaDragon = {
	name = "Lava Dragon",
	skeleton = "Dragon",
	gait = "Stomp",
	scale = 0.42 * 1.2,
	draw = function(pet)
		-- Modelled in finer units than it is built in: 1.2 of them to a block.
		local U = 1.2
		local function at(p: Vec): Vec
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local SCALE = look(38, 28, 32)
		local HORN = look(78, 62, 60)
		local CLAW = look(26, 20, 22)
		local FANG = look(244, 236, 216)
		local GUM = look(120, 22, 20)
		local LAVA = look(255, 104, 20, NEON)
		local HOT = look(255, 198, 46, NEON)
		local MAGMA = look(200, 44, 16, NEON)
		local PUPIL = look(30, 6, 6)

		-- Glowing plates where its underside shows, molten and darker by turns.
		local function plates(p: Vec, along: number): Look
			return if math.floor(p[along] / 1.6) % 2 == 0 then LAVA else MAGMA
		end

		-- A heavy body of black obsidian scales, a molten belly in glowing plates, cracks of lava down its flanks, and
		-- a row of horn spikes down its spine, glowing at their tips.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 15, 4 }, { 6, 6.5, 7 }), SCALE)
		body:add(ellipsoid({ 0, 18.5, 3 }, { 5.6, 3.6, 6 }), SCALE)
		body:add(ellipsoid({ 0, 14, -4 }, { 5.2, 5.8, 7 }), SCALE)
		body:add(ellipsoid({ 0, 14.5, -11 }, { 5.6, 6, 5.5 }), SCALE)
		body:coat(function(p, open)
			if open(0, -1, 0) and p[2] < 14 then
				return plates(p, 3)
			end
			return nil
		end)
		-- Molten veins tracing its shoulders, ribs and haunches, branching as they run down.
		for _, side in { 1, -1 } do
			for _, vein in
				{
					{ { 0, 19.5, 7 }, { 0, 16, 9.5 }, { 0, 12.5, 8.5 } },
					{ { 0, 16, 9.5 }, { 0, 17.5, 4.5 } },
					{ { 0, 19.5, 3 }, { 0, 15.5, 1 }, { 0, 11.5, 2 } },
					{ { 0, 19, -2 }, { 0, 15, -4 }, { 0, 11, -3 } },
					{ { 0, 15, -4 }, { 0, 16.5, -8 } },
					{ { 0, 18.5, -7.5 }, { 0, 14.5, -9.5 }, { 0, 11, -8.5 } },
					{ { 0, 19.5, -11 }, { 0, 15.5, -13.5 }, { 0, 12, -12.5 } },
				}
			do
				body:trace(vein, { -side, 0, 0 }, LAVA)
			end
		end
		local function top(z: number): number
			local cz, y = math.floor(z / U), math.floor(15 / U)
			while body:has(0, y + 1, cz) do
				y += 1
			end
			return (y + 1) * U
		end
		for index, z in { 9.5, 6, -8, -11.5, -15 } do
			local y = top(z) - 0.6
			local tall = if index % 2 == 1 then 4 else 3
			body:add(rod({ { 0, y, z, 1.3 }, { 0, y + tall, z - 2.2, 0.35 } }), HORN)
			body:add(rod({ { 0, y + tall - 0.8, z - 1.7, 0.5 }, { 0, y + tall + 0.3, z - 2.5, 0.3 } }), HOT)
		end

		-- A long neck, molten plates down its throat, and a horned head with jaws open on a throat of fire: heavy
		-- brows over narrow glowing eyes, back-swept horns tipped with flame, fangs, glowing nostrils.
		local head = newSculpt(U)
		head:add(rod({ { 0, 18, 7, 3.8 }, { 0, 22.5, 11.5, 3.2 }, { 0, 26.5, 14, 2.7 } }), SCALE)
		-- The head is drawn 1.22 times the size of the numbers below, about a point at the top of the neck.
		local H, centre = 1.22, { 0, 26.5, 15 }
		local function hp(p: Vec): Vec
			return {
				centre[1] + (p[1] - centre[1]) * H,
				centre[2] + (p[2] - centre[2]) * H,
				centre[3] + (p[3] - centre[3]) * H,
			}
		end
		local function E(c: Vec, r: Vec): Shape
			return ellipsoid(hp(c), { r[1] * H, r[2] * H, r[3] * H })
		end
		local function R(points: { { number } }): Shape
			local out = {}
			for _, p in points do
				local q = hp(p)
				table.insert(out, { q[1], q[2], q[3], p[4] * H })
			end
			return rod(out)
		end
		head:add(E({ 0, 28.5, 16.5 }, { 3.2, 2.8, 4 }), SCALE)
		head:add(E({ 0, 29.6, 18.5 }, { 3.3, 1.2, 1.8 }), SCALE)
		head:add(E({ 0, 27.8, 21.5 }, { 2.4, 1.9, 4.4 }), SCALE)
		head:add(E({ 0, 26.4, 17 }, { 2.8, 1.8, 2.4 }), SCALE)
		head:add(E({ 0, 25.2, 20.2 }, { 2.1, 1, 4 }), SCALE)
		head:carve(E({ 0, 26.4, 21 }, { 1.7, 0.75, 3.8 }))
		head:paint(E({ 0, 26.4, 21 }, { 2.2, 1.2, 4.3 }), GUM, nil, true)
		head:add(E({ 0, 26.4, 17.8 }, { 1.4, 0.7, 0.8 }), HOT)
		for _, s in { 1, -1 } do
			for _, z in { 19, 20.5, 22, 23.4 } do
				head:add(R({ { 1.6 * s, 26, z, 0.4 }, { 1.6 * s, 25.3, z + 0.2, 0.25 } }), FANG)
			end
			for _, z in { 19.8, 21.3, 22.8 } do
				head:add(R({ { 1.4 * s, 25.6, z, 0.4 }, { 1.4 * s, 26.3, z + 0.2, 0.25 } }), FANG)
			end
			head:add(R({ { 1.2 * s, 26.6, 24.4, 0.5 }, { 1.1 * s, 24.9, 24.8, 0.3 } }), FANG)
			head:add(
				R({
					{ 1.8 * s, 30.3, 14.6, 1.4 },
					{ 2.9 * s, 32.2, 11.8, 1.1 },
					{ 3.4 * s, 33.1, 8.8, 0.75 },
					{ 3.2 * s, 32.6, 6.4, 0.35 },
				}),
				HORN
			)
			head:add(R({ { 3.35 * s, 32.95, 7.6, 0.45 }, { 3.2 * s, 32.6, 6.4, 0.3 } }), HOT)
			head:add(R({ { 2.8 * s, 27.4, 15.4, 0.7 }, { 4.1 * s, 27.8, 12.8, 0.25 } }), HORN)
			head:add(R({ { 2.4 * s, 30.2, 18, 0.6 }, { 3.2 * s, 31.3, 16.6, 0.25 } }), HORN)
			head:add(R({ { 2.5 * s, 25, 16.5, 0.6 }, { 3.6 * s, 24.4, 14.6, 0.25 } }), HORN)
		end
		head:coat(function(real, open)
			local p = {
				centre[1] + (real[1] - centre[1]) / H,
				centre[2] + (real[2] - centre[2]) / H,
				centre[3] + (real[3] - centre[3]) / H,
			}
			local x, y, z = p[1], p[2], p[3]
			-- Glowing nostrils.
			if z > 24.6 and y > 28.3 and math.abs(x) > 0.4 and math.abs(x) < 1.4 then
				return LAVA
			end
			-- Molten plates down the throat.
			if real[3] < 15.5 and (open(0, -1, 0) or open(0, 0, 1)) and real[2] < 25.5 then
				return plates(real, 2)
			end
			return nil
		end)
		-- Veins of lava up the sides of its neck to its horns.
		for _, side in { 1, -1 } do
			head:trace({ { 0, 19.5, 9 }, { 0, 23, 12 }, { 0, 26.5, 14 }, { 0, 29, 14.5 } }, { -side, 0, 0 }, LAVA)
		end

		-- Thick, clawed legs, cracked with lava, with spikes at the elbows and knees.
		local function foot(s: Sculpt, x: number, y: number, z: number)
			s:add(ellipsoid({ x, y, z }, { 2.3, 1.5, 2.9 }), SCALE)
			for _, dx in { -1.3, 0, 1.3 } do
				s:add(rod({ { x + dx, y - 0.1, z + 1.3, 0.9 }, { x + dx * 1.3, y - 0.5, z + 3, 0.7 } }), SCALE)
				s:add(rod({ { x + dx * 1.3, y - 0.4, z + 3, 0.55 }, { x + dx * 1.4, y - 1.3, z + 4.2, 0.25 } }), CLAW)
			end
		end
		local function veins(s: Sculpt, points: { Vec })
			s:trace(points, { -1, 0, 0 }, LAVA)
			s:trace(points, { 0, 0, -1 }, MAGMA)
		end
		local front = newSculpt(U)
		front:add(rod({ { 5.2, 16, 5, 3 }, { 6.2, 9, 7, 2.3 } }), SCALE)
		front:add(rod({ { 6.2, 9, 7, 2.1 }, { 6.4, 3, 6.6, 1.8 } }), SCALE)
		foot(front, 6.4, 1.5, 8.2)
		front:add(rod({ { 6.6, 9.5, 5.6, 0.7 }, { 6.9, 10.5, 3.6, 0.2 } }), HORN)
		veins(front, { { 0, 15.5, 6 }, { 0, 10, 7.5 }, { 0, 5, 7 }, { 0, 2.5, 8.5 } })
		local back = newSculpt(U)
		back:add(ellipsoid({ 5.6, 12.5, -11 }, { 3, 5.2, 4.2 }), SCALE)
		back:add(rod({ { 6.1, 8.5, -13, 2.1 }, { 6.4, 3.6, -14.8, 1.7 } }), SCALE)
		back:add(rod({ { 6.4, 3.6, -14.8, 1.6 }, { 6.4, 1.6, -12.4, 1.5 } }), SCALE)
		foot(back, 6.4, 1.4, -11.2)
		back:add(rod({ { 6.4, 9, -14.6, 0.7 }, { 6.7, 10.5, -16.4, 0.2 } }), HORN)
		veins(back, { { 0, 17, -10 }, { 0, 12, -12 }, { 0, 7, -14 }, { 0, 3, -14.5 } })

		-- A long tail sweeping round, spiked along its top, molten underneath, ending in a glowing spade of lava.
		local tail = newSculpt(U)
		local spine = {
			{ 0, 14, -14, 3.6 },
			{ 0, 12.5, -20, 2.9 },
			{ 1.5, 9, -26, 2.2 },
			{ 3.5, 6.5, -31, 1.6 },
			{ 4.6, 5.5, -35, 1.1 },
			{ 4.4, 6.5, -38.5, 0.7 },
		}
		tail:add(rod(spine), SCALE)
		for index = 2, #spine - 1 do
			local p = spine[index]
			tail:add(
				rod({ { p[1], p[2] + p[4] - 0.4, p[3], p[4] * 0.45 }, { p[1], p[2] + p[4] + 1.8, p[3] - 1.6, 0.25 } }),
				HORN
			)
		end
		tail:add(ellipsoid({ 4.4, 7.4, -40.2 }, { 0.7, 2.4, 2 }), LAVA)
		tail:add(ellipsoid({ 4.4, 7.4, -40.2 }, { 0.75, 1.3, 1.1 }), HOT)
		tail:coat(function(p, open)
			if open(0, -1, 0) and p[3] > -37 then
				return plates(p, 3)
			end
			return nil
		end)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", at({ 0, 14, -2 })), { head, front, frontMirror, back, backMirror, tail }, SCALE)
		local headLimb = pet:limb("Head", at({ 0, 19, 9 }))
		head:draw(headLimb, { body }, SCALE)
		-- The eyes: flat on the sides of its head under the brow, narrow and pointed at both ends, slanting up
		-- towards the back, glowing, each set in a dark rim with a slit pupil.
		for _, s in { 1, -1 } do
			local out = { s, 0, 0 }
			local function almond(depth: number, grow: number, color: Color, material: string?, thick: number)
				local nose = { s * depth, 28.9 - grow * 0.2, 20.7 + grow }
				local backPoint = { s * depth, 29.95 + grow * 0.2, 16.3 - grow }
				local p1, p2 = vlerp(nose, backPoint, 0.3), vlerp(nose, backPoint, 0.7)
				local width = 1.05 + grow
				taper(headLimb, at(p1), at(nose), width / U, thick / U, out, color, material)
				blade(headLimb, at(p1), at(p2), width / U, thick / U, out, color, material)
				taper(headLimb, at(p2), at(backPoint), width / U, thick / U, out, color, material)
			end
			almond(3.62, 0.45, CLAW.color, nil, 0.2)
			almond(3.74, 0, HOT.color, NEON, 0.2)
			blade(
				headLimb,
				at({ s * 3.86, 28.75, 18.75 }),
				at({ s * 3.86, 29.95, 18.45 }),
				0.32 / U,
				0.12 / U,
				out,
				PUPIL.color
			)
		end
		headLimb:fire(at(hp({ 0, 25.4, 27.2 })), 4, rgb(255, 90, 20), rgb(255, 210, 60))
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", at({ 5, 15, 5 }), function(limb)
			front:draw(limb, { body }, SCALE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", at({ 5, 14, -11 }), function(limb)
			back:draw(limb, { body }, SCALE)
		end)
		local tailLimb = pet:limb("Tail", at({ 0, 14, -15 }))
		tail:draw(tailLimb, { body }, SCALE)
		tailLimb:fire(at({ 4.4, 9.5, -40.2 }), 5, rgb(255, 90, 20), rgb(255, 210, 60))

		-- Great bat wings raised and swept back: dark bones, membranes of deep red veined with glowing lava, a hooked
		-- claw at each wrist, a spike at each elbow, and flame at the tips.
		pet:limbPair("LeftWing", "RightWing", at({ 4.5, 21, 2 }), function(wing)
			local MEMBRANE, VEIN, BONE = rgb(120, 22, 18), rgb(255, 120, 24), rgb(66, 52, 52)
			local FLAT = { 0, 0, 1 }
			-- Drawn 1.15 times the size of the numbers below, out from the shoulder.
			local root = { 4.5, 21, 2 }
			local function grow(p: Vec): Vec
				return vadd(root, vscale(vsub(p, root), 1.15))
			end
			local shoulderJoint, elbow, wrist = root, grow({ 10.5, 28.5, -1.5 }), grow({ 14.5, 34, -4.5 })
			local tips = {
				grow({ 27, 31, -7.5 }),
				grow({ 24.5, 22.5, -9 }),
				grow({ 19.5, 16.5, -9.5 }),
				grow({ 13.5, 15.5, -8 }),
			}
			local scallops = { grow({ 22.5, 26.5, -8 }), grow({ 19.5, 20.5, -8.8 }), grow({ 15.5, 18, -8.5 }) }
			local flank, shoulder = { 6, 17, -6 }, { 5, 19.5, -2 }
			local function membrane(a: Vec, b: Vec, c: Vec)
				triangle(wing, at(a), at(b), at(c), 0.35 / U, MEMBRANE)
			end
			for i = 1, 3 do
				membrane(wrist, tips[i], scallops[i])
				membrane(wrist, scallops[i], tips[i + 1])
			end
			membrane(elbow, wrist, tips[4])
			membrane(elbow, tips[4], flank)
			membrane(elbow, flank, shoulder)
			for _, vein in { { wrist, scallops[1] }, { wrist, scallops[2] }, { wrist, scallops[3] }, { elbow, flank } } do
				blade(wing, at(vein[1]), at(vlerp(vein[1], vein[2], 0.85)), 0.3 / U, 0.6 / U, FLAT, VEIN, NEON)
			end
			blade(wing, at(shoulderJoint), at(elbow), 1.7 / U, 1.4 / U, FLAT, BONE)
			blade(wing, at(elbow), at(wrist), 1.4 / U, 1.2 / U, FLAT, BONE)
			for index, tip in tips do
				local mid = vlerp(wrist, tip, 0.7)
				blade(wing, at(wrist), at(mid), (1 - index * 0.08) / U, 0.9 / U, FLAT, BONE)
				taper(wing, at(mid), at(tip), 0.8 / U, 0.8 / U, FLAT, BONE)
			end
			taper(wing, at(wrist), at(grow({ 15.5, 36.5, -2.8 })), 0.9 / U, 0.8 / U, { 1, 0, 0 }, CLAW.color)
			taper(wing, at(elbow), at(grow({ 10, 30.8, -4.4 })), 0.8 / U, 0.7 / U, { 1, 0, 0 }, HORN.color)
			wing:fire(at(tips[1]), 4, rgb(255, 90, 20), rgb(255, 210, 60))
		end)

		pet:light(rgb(255, 110, 30), 3.4, 26)
		pet:particles("Embers", rgb(255, 200, 70), 18)
		pet:seat(0, 22 / U, -3 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Prehistoric

Designs.Velociraptor = {
	name = "Velociraptor",
	skeleton = "Theropod",
	gait = "Walk",
	scale = 0.45,
	draw = function(pet)
		-- Sculpted in the units it is built in (one to a block), with feathers, teeth and claws of parts at any
		-- angle.
		local U = 1
		local T = inUnits(U)
		local SCALES = look(124, 146, 66)
		local DARK = look(70, 84, 42)
		local BELLY = look(232, 218, 166)
		local FEATHER = rgb(214, 112, 46)
		local FEATHER_DARK = rgb(150, 70, 30)
		local CLAW = rgb(240, 232, 212)
		local AMBER = rgb(255, 172, 36)
		local QUILL = {
			{ color = FEATHER_DARK, to = 0.5 },
			{ color = FEATHER, to = 1 },
		}

		-- Green scales, striped dark across the back, pale underneath.
		local function scales(p: Vec, open: (number, number, number) -> boolean, belly: number): Look?
			if open(0, -1, 0) and p[2] < belly then
				return BELLY
			end
			if
				(open(0, 1, 0) or open(1, 0, 0) or open(-1, 0, 0))
				and p[2] > belly + 1.2
				and (p[3] + 40) % 2.6 < 0.8
			then
				return DARK
			end
			return nil
		end

		-- A lean body held level.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 13, -1 }, { 3, 3.6, 6 }), SCALES)
		body:add(ellipsoid({ 0, 12.6, 3.4 }, { 2.8, 3.4, 3.4 }), SCALES)
		body:coat(function(p, open)
			return scales(p, open, 11)
		end)

		-- A long, low head on an S of a neck: a toothy jaw, glowing amber eyes under ridged brows, a crest of quills.
		local head = newSculpt(U)
		head:add(rod({ { 0, 14.6, 5, 2.1 }, { 0, 17.4, 6.6, 1.65 }, { 0, 19, 8.4, 1.55 } }), SCALES)
		head:add(ellipsoid({ 0, 19.6, 10.4 }, { 1.95, 1.85, 2.9 }), SCALES)
		head:add(ellipsoid({ 0, 19.1, 13.4 }, { 1.35, 1.3, 2.5 }), SCALES)
		head:add(ellipsoid({ 0, 17.9, 12.4 }, { 1.15, 0.65, 2.6 }), SCALES)
		for _, s in { 1, -1 } do
			head:add(rod({ { 1.3 * s, 21.1, 9.6, 0.55 }, { 1.2 * s, 20.9, 12.4, 0.45 } }), DARK)
		end
		head:coat(function(p, open)
			if open(0, -1, 0) and p[3] > 9 then
				return BELLY
			end
			return scales(p, open, 18)
		end)

		local arm = newSculpt(U)
		arm:add(rod({ { 2.2, 13, 4, 0.95 }, { 3, 11, 5.6, 0.8 }, { 3.1, 10, 7.2, 0.65 } }), SCALES)

		local leg = newSculpt(U)
		leg:add(ellipsoid({ 2.8, 11.4, -1.4 }, { 1.9, 3.6, 2.6 }), SCALES)
		leg:add(rod({ { 3, 8.6, -2.6, 1.55 }, { 3.1, 4, -1.4, 1.1 } }), SCALES)
		leg:add(rod({ { 3.1, 4, -1.4, 0.95 }, { 3.1, 1, 0.4, 0.85 } }), SCALES)
		for _, dx in { -0.5, 0.5 } do
			leg:add(rod({ { 3.1 + dx, 0.8, 0.6, 0.6 }, { 3.1 + dx * 1.4, 0.6, 3, 0.45 } }), DARK)
		end
		leg:coat(function(p, open)
			return scales(p, open, 9)
		end)

		local tail = newSculpt(U)
		tail:add(
			rod({ { 0, 13.6, -6.6, 2.4 }, { 0, 13.4, -14, 1.6 }, { 0, 13, -21, 1 }, { 0, 12.8, -26, 0.55 } }),
			SCALES
		)
		tail:coat(function(p, open)
			return scales(p, open, 12.6)
		end)

		local legMirror, armMirror = leg:mirror(), arm:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 12, 0 }))
		body:draw(bodyLimb, { head, leg, legMirror, arm, armMirror, tail }, SCALES)
		for index, z in { 0.4, -1.8, -4 } do
			local y = topOf(body, z)
			feather(
				bodyLimb,
				T.at({ 0, y - 0.3, z }),
				{ 0, 0.5, -1 },
				(2.6 - index * 0.3) / U,
				0.9 / U,
				0.35 / U,
				{ 1, 0, 0 },
				QUILL
			)
		end
		local headLimb = pet:limb("Head", T.at({ 0, 14.6, 5 }))
		head:draw(headLimb, { body }, SCALES)
		slitEyes(headLimb, head, { 20.2, 11.6 }, { 20.5, 10 }, 0.55, AMBER, NEON, DARK.color)
		for _, s in { 1, -1 } do
			for _, z in { 11.4, 12.6, 13.8, 15 } do
				T.taper(headLimb, { 0.95 * s, 18.4, z }, { 0.95 * s, 17.7, z + 0.2 }, 0.35, 0.3, { 1, 0, 0 }, CLAW)
			end
		end
		for index, z in { 9.6, 8.2, 6.8, 5.4 } do
			local y = topOf(head, z)
			feather(
				headLimb,
				T.at({ 0, y - 0.3, z }),
				{ 0, 0.8, -1 },
				(3 - index * 0.35) / U,
				0.9 / U,
				0.35 / U,
				{ 1, 0, 0 },
				QUILL
			)
		end
		pet:limbPair("LeftArm", "RightArm", T.at({ 2.2, 13, 4 }), function(limb)
			arm:draw(limb, { body }, SCALES)
			for index, t in { 0.2, 0.5, 0.8 } do
				local root = vlerp({ 2.4, 13, 4 }, { 3.1, 10.2, 7 }, t)
				feather(limb, T.at(root), { 0.3, -0.5, -1 }, (3 - index * 0.4) / U, 1 / U, 0.35 / U, { 1, 0, 0 }, QUILL)
			end
			for _, dy in { -0.3, 0.3 } do
				T.taper(limb, { 3.1, 10.1 + dy, 6.5 }, { 3.2, 9.2 + dy, 8.4 }, 0.4, 0.35, { 1, 0, 0 }, CLAW)
			end
		end)
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 2.8, 12, -1.4 }), function(limb)
			leg:draw(limb, { body }, SCALES)
			-- The sickle claw, held up off the ground.
			T.taper(limb, { 3.6, 1.4, 0.4 }, { 3.9, 2.6, 2 }, 0.55, 0.5, { 1, 0, 0 }, CLAW)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 13.6, -6.6 }))
		tail:draw(tailLimb, { body }, SCALES)
		for _, dx in { -1, 0, 1 } do
			feather(
				tailLimb,
				T.at({ dx * 0.4, 12.8, -25 }),
				{ dx * 0.4, 0.1, -1 },
				3.4 / U,
				1 / U,
				0.35 / U,
				{ 0, 1, 0 },
				QUILL
			)
		end

		pet:seat(0, 17 / U, -1 / U)
	end,
}

Designs.Pteranodon = {
	name = "Pteranodon",
	skeleton = "Winged",
	gait = "Walk",
	scale = 0.55 * 0.8,
	draw = function(pet)
		-- Sculpted finer than it is drawn (blocks 0.8 of a unit across), with a beak, crest and wings of parts at
		-- any angle, so it keeps its shape however big it is shown.
		local U = 0.8
		local function at(p: Vec): Vec
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local function bladeAt(limb: Limb, a: Vec, b: Vec, w: number, t: number, f: Vec, c: Color, m: string?)
			blade(limb, at(a), at(b), w / U, t / U, f, c, m)
		end
		local function taperAt(limb: Limb, a: Vec, b: Vec, w: number, t: number, f: Vec, c: Color, m: string?)
			taper(limb, at(a), at(b), w / U, t / U, f, c, m)
		end
		local function triangleAt(limb: Limb, a: Vec, b: Vec, c: Vec, t: number, color: Color)
			triangle(limb, at(a), at(b), at(c), t / U, color)
		end
		local function eggAt(limb: Limb, centre: Vec, size: Vec, color: Color)
			egg(limb, at(centre), { size[1] / U, size[2] / U, size[3] / U }, nil, color)
		end
		local FUR = look(204, 150, 104)
		local FUR_LIGHT = look(222, 176, 128)
		local DARK = look(150, 96, 70)
		local CREAM = look(240, 222, 180)
		local CAP = look(120, 72, 52)
		local FOOT = look(196, 146, 78)
		local CLAW = rgb(60, 40, 32)
		local CREST = rgb(226, 78, 46)
		local CREST_DARK = rgb(160, 44, 34)
		local BEAK = rgb(240, 202, 120)
		local BEAK_DARK = rgb(196, 146, 78)
		local MEMBRANE = rgb(186, 100, 70)
		local MEMBRANE_DARK = rgb(146, 72, 54)
		local VEIN = rgb(132, 66, 48)
		local BONE = rgb(112, 70, 50)
		local SIDE = { 1, 0, 0 }
		local FLAT = { 0, 0, 1 }

		local function speckle(p: Vec, chance: number): boolean
			local n = math.sin(p[1] * 12.9898 + p[2] * 78.233 + p[3] * 37.719) * 43758.5453
			return n - math.floor(n) < chance
		end
		-- Short fur: a cream chest and belly, a darker back, flecked lighter all over.
		local function fur(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, 0, 1) and not open(0, 0, -1) and math.abs(p[1]) < 2.4 then
				return CREAM
			end
			if open(0, 0, -1) then
				return DARK
			end
			if speckle(p, 0.14) then
				return FUR_LIGHT
			end
			return nil
		end

		-- An upright, furry body, broad at the shoulders where the wings join.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 9.4, -0.4 }, { 4.2, 5.2, 3.9 }), FUR)
		body:add(ellipsoid({ 0, 11.6, -0.2 }, { 4.8, 2.8, 3.3 }), FUR)
		body:add(ellipsoid({ 0, 6, -0.8 }, { 3.2, 2.6, 3 }), FUR)
		body:coat(fur)

		-- A slender neck and a long head: dark-capped, with a long pointed beak and a tall crest sweeping back.
		local head = newSculpt(U)
		head:add(rod({ { 0, 13, 0, 2.2 }, { 0, 15.2, 0.6, 1.8 }, { 0, 16.8, 0.8, 1.9 } }), FUR)
		head:add(ellipsoid({ 0, 18, 0.7 }, { 2.4, 2.3, 3 }), FUR)
		head:add(ellipsoid({ 0, 17.4, 2.5 }, { 1.6, 1.7, 1.8 }), FUR)
		head:coat(function(p, open)
			if p[2] > 19 then
				return CAP
			end
			return fur(p, open)
		end)

		-- Legs with gripping feet of three clawed toes.
		local leg = newSculpt(U)
		leg:add(rod({ { 1.7, 5.6, -0.6, 1.4 }, { 1.9, 3, -0.2, 0.85 }, { 1.9, 1, 0.3, 0.7 } }), FUR)
		for _, dx in { -0.8, 0, 0.8 } do
			leg:add(rod({ { 1.9 + dx * 0.4, 0.7, 0.6, 0.55 }, { 1.9 + dx, 0.5, 2.4, 0.45 } }), FOOT)
		end
		leg:coat(function(p)
			return if p[2] < 1.6 then FOOT else nil
		end)

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 6, -2.6, 0.9 }, { 0, 5.4, -5.8, 0.35 } }), FUR)
		tail:coat(function()
			return DARK
		end)

		local legMirror = leg:mirror()
		body:draw(pet:limb("Body", at({ 0, 8, 0 })), { head, leg, legMirror, tail }, FUR)
		local headLimb = pet:limb("Head", at({ 0, 13, 0 }))
		head:draw(headLimb, { body }, FUR)
		-- Round eyes on the surface of its head.
		local cx, cy, cz = 0, math.floor(18.4 / U), math.floor(1.6 / U)
		while head:has(cx + 1, cy, cz) do
			cx += 1
		end
		local eyeX = (cx + 1) * U
		for _, s in { 1, -1 } do
			eggAt(headLimb, { (eyeX - 0.12) * s, 18.4, 1.6 }, { 0.55, 0.95, 0.95 }, EYE)
			eggAt(headLimb, { (eyeX + 0.1) * s, 18.75, 1.85 }, { 0.22, 0.32, 0.32 }, SHINE)
		end
		bladeAt(headLimb, { 0, 17.9, 3 }, { 0, 17.6, 7 }, 1.7, 1.8, SIDE, BEAK)
		taperAt(headLimb, { 0, 17.6, 7 }, { 0, 16.9, 12.5 }, 1.7, 1.5, SIDE, BEAK)
		bladeAt(headLimb, { 0, 16.5, 3 }, { 0, 16.3, 6.4 }, 1, 1.6, SIDE, BEAK_DARK)
		taperAt(headLimb, { 0, 16.3, 6.4 }, { 0, 16.1, 10.6 }, 1, 1.3, SIDE, BEAK_DARK)
		triangleAt(headLimb, { 0, 19.8, 1.6 }, { 0, 25.5, -9.5 }, { 0, 17, -1.8 }, 0.7, CREST)
		triangleAt(headLimb, { 0, 19.4, -0.8 }, { 0, 23.6, -8.2 }, { 0, 18.2, -2.2 }, 0.9, CREST_DARK)
		pet:limbPair("LeftLeg", "RightLeg", at({ 1.7, 5.6, -0.6 }), function(limb)
			leg:draw(limb, { body }, FUR)
		end)
		tail:draw(pet:limb("Tail", at({ 0, 6, -2.6 })), { body }, FUR)

		-- Great leathery wings held out wide: a bony arm to the wrist, then one very long finger out to the tip,
		-- the membrane two-toned and veined, and small clawed fingers at each wrist.
		pet:limbPair("LeftWing", "RightWing", at({ 3, 11.4, 0 }), function(wing)
			local shoulder, elbow, wrist = { 3, 11.4, 0 }, { 8, 13, -1 }, { 12.5, 14.5, -0.5 }
			local knuckle, tip = { 19, 15.2, -2 }, { 26, 15, -4 }
			local trail1, trail2, flank = { 19.5, 11, -3.5 }, { 13, 7.5, -3 }, { 3, 6.5, -1.4 }
			triangleAt(wing, wrist, tip, trail1, 0.4, MEMBRANE)
			triangleAt(wing, wrist, trail1, trail2, 0.4, MEMBRANE)
			triangleAt(wing, elbow, wrist, trail2, 0.4, MEMBRANE)
			triangleAt(wing, elbow, trail2, flank, 0.4, MEMBRANE_DARK)
			triangleAt(wing, shoulder, elbow, flank, 0.4, MEMBRANE_DARK)
			for _, vein in { { wrist, trail1 }, { wrist, trail2 }, { elbow, flank } } do
				bladeAt(wing, vein[1], vlerp(vein[1], vein[2], 0.85), 0.28, 0.55, FLAT, VEIN)
			end
			bladeAt(wing, shoulder, elbow, 1.4, 1.1, FLAT, BONE)
			bladeAt(wing, elbow, wrist, 1.2, 1, FLAT, BONE)
			bladeAt(wing, wrist, knuckle, 1, 0.9, FLAT, BONE)
			taperAt(wing, knuckle, tip, 0.9, 0.8, FLAT, BONE)
			eggAt(wing, wrist, { 1.5, 1.5, 1.5 }, BONE)
			for _, claw in { { 12.2, 15.6, 1.6 }, { 13.3, 15.4, 1.4 }, { 11.4, 15.2, 1.2 } } do
				taperAt(wing, wrist, claw, 0.55, 0.45, { 0, 1, 0 }, CLAW)
			end
		end)

		pet:seat(0, 13.5 / U, -1 / U)
	end,
}

Designs.Triceratops = {
	name = "Triceratops",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with its horns, beak and the knobs
		-- round its frill of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local HIDE = look(118, 138, 98)
		local DARK = look(84, 102, 72)
		local LIGHT = look(166, 178, 124)
		local FRILL = look(234, 120, 50)
		local RIM = look(250, 214, 120)
		local SPOT = look(56, 96, 90)
		local NAIL = look(236, 228, 206)
		local HORN = rgb(246, 236, 206)
		local HORN_BASE = rgb(206, 192, 158)
		local BEAK = rgb(74, 68, 60)

		local function hide(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, -1, 0) and p[2] < 11 then
				return LIGHT
			end
			if open(0, 1, 0) and math.floor((p[3] + 40) / 3.2) % 2 == 0 then
				return DARK
			end
			return if noise(p) < 0.1 then LIGHT else nil
		end

		-- A big barrel of a body, banded across the back.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 13.5, -2 }, { 6.8, 6.6, 10.4 }), HIDE)
		body:add(ellipsoid({ 0, 14.6, 4.4 }, { 6, 5.6, 5 }), HIDE)
		body:add(ellipsoid({ 0, 14.6, -8.6 }, { 6, 6, 5 }), HIDE)
		body:coat(hide)

		-- A great head: a frill tilted back behind it, rimmed and spotted, and a hooked beak.
		local head = newSculpt(U)
		head:add(rod({ { 0, 14, 7, 4.4 }, { 0, 13, 9, 4 } }), HIDE)
		head:add(ellipsoid({ 0, 12.6, 10.8 }, { 3.7, 3.9, 4.4 }), HIDE)
		head:add(ellipsoid({ 0, 11.2, 15.2 }, { 2.3, 2.7, 2.7 }), HIDE)
		local frill = { origin = { 0, 18.4, 7.4 }, pitch = 0.5 }
		head:add(ellipsoid({ 0, 0, 0 }, { 9, 7.8, 0.65 }), RIM, frill)
		head:add(ellipsoid({ 0, 0, 0 }, { 8.4, 7.2, 0.8 }), FRILL, frill)
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if y > 14.6 and z < 9.6 then
				local n = noise({ math.floor(x / 1.6), math.floor(y / 1.6), 0 })
				return if n < 0.18 and (open(0, 0, 1) or open(0, 1, 0)) then SPOT else nil
			end
			return hide(p, open)
		end)

		local function foot(s: Sculpt, x: number, z: number)
			s:add(ellipsoid({ x, 1.3, z }, { 2.8, 1.3, 3 }), HIDE)
			for _, dx in { -1.3, 0, 1.3 } do
				s:add(ellipsoid({ x + dx, 0.9, z + 2.5 }, { 0.7, 0.9, 0.65 }), NAIL)
			end
		end
		local front = newSculpt(U)
		front:add(rod({ { 4.4, 11, 5, 3 }, { 4.6, 5, 5.6, 2.6 }, { 4.6, 2.4, 5.6, 2.5 } }), HIDE)
		foot(front, 4.6, 6)
		local back = newSculpt(U)
		back:add(ellipsoid({ 4.6, 13, -8.6 }, { 3.4, 5, 4.2 }), HIDE)
		back:add(rod({ { 4.8, 9, -9.6, 3 }, { 4.9, 2.4, -9, 2.6 } }), HIDE)
		foot(back, 4.9, -8.8)
		for _, leg in { front, back } do
			leg:coat(function(p, open)
				return if p[2] > 2.2 then hide(p, open) else nil
			end)
		end

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 14, -13, 3.8 }, { 0, 12.6, -19, 2.4 }, { 0, 11, -24, 1.2 } }), HIDE)
		tail:coat(hide)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 13, 0 })), { head, front, frontMirror, back, backMirror, tail }, HIDE)
		local headLimb = pet:limb("Head", T.at({ 0, 13, 7 }))
		head:draw(headLimb, { body }, HIDE)
		roundEyes(headLimb, head, 14, 13.4, 1.1)
		-- Two long horns over its eyes, one on its nose, small ones on its cheeks, a hooked beak, and knobs all
		-- round the rim of its frill.
		for _, s in { 1, -1 } do
			T.blade(headLimb, { 1.9 * s, 15.4, 12 }, { 2.5 * s, 19, 15.4 }, 1.5, 1.5, { 1, 0, 0 }, HORN_BASE)
			T.taper(headLimb, { 2.5 * s, 19, 15.4 }, { 2.9 * s, 22.2, 19.4 }, 1.3, 1.3, { 1, 0, 0 }, HORN)
			T.taper(headLimb, { 3.4 * s, 11, 10.6 }, { 5.2 * s, 10.6, 10.2 }, 1, 1, { 0, 1, 0 }, HORN)
		end
		T.taper(headLimb, { 0, 13.4, 16.2 }, { 0, 16.2, 17.6 }, 1.2, 1.2, { 1, 0, 0 }, HORN)
		T.blade(headLimb, { 0, 11.8, 16.6 }, { 0, 10.6, 18.4 }, 1.6, 1.6, { 1, 0, 0 }, BEAK)
		T.taper(headLimb, { 0, 10.6, 18.4 }, { 0, 8.6, 18.6 }, 1.4, 1.4, { 1, 0, 0 }, BEAK)
		T.blade(headLimb, { 0, 9.6, 15.6 }, { 0, 9.2, 17.2 }, 1.4, 1.2, { 1, 0, 0 }, BEAK)
		local c, s = math.cos(0.5), math.sin(0.5)
		for index = 0, 15 do
			local angle = math.pi * (index / 15)
			local ex, ey = math.cos(angle) * 8.3, math.sin(angle) * 7.1
			local knob = { ex, 18.4 + ey * c, 7.4 - ey * s }
			if ey > -2 then
				T.taper(
					headLimb,
					knob,
					vadd(knob, { math.cos(angle) * 1.4, math.sin(angle) * 1.2 * c, -math.sin(angle) * 1.2 * s }),
					1.1,
					0.8,
					{ 0, s, c },
					RIM.color
				)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 4.4, 11, 5 }), function(limb)
			front:draw(limb, { body }, HIDE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4.6, 13, -8.6 }), function(limb)
			back:draw(limb, { body }, HIDE)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 14, -12 })), { body }, HIDE)

		pet:light(FRILL.color, 1.8, 16)
		pet:seat(0, 20.6 / U, -2 / U)
	end,
}

Designs.Stegosaurus = {
	name = "Stegosaurus",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.42 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with plates and spikes of parts at
		-- any angle, so it keeps its shape however big it is shown.
		local U = 1.2
		local function at(p: Vec): Vec
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local HIDE = look(104, 132, 88)
		local DARK = look(76, 100, 66)
		local DAPPLE = look(132, 158, 104)
		local BELLY = look(220, 208, 152)
		local BELLY_DARK = look(198, 182, 128)
		local KNOB = look(88, 110, 74)
		local NAIL = look(238, 228, 198)
		local BEAK = look(70, 66, 58)
		local PLATE = rgb(222, 92, 50)
		local PLATE_DARK = rgb(170, 56, 38)
		local TIP = rgb(255, 186, 60)
		local SPIKE = rgb(246, 236, 206)

		local function speckle(p: Vec, chance: number): boolean
			local n = math.sin(p[1] * 12.9898 + p[2] * 78.233 + p[3] * 37.719) * 43758.5453
			return n - math.floor(n) < chance
		end
		local function top(s: Sculpt, z: number, x: number?): number
			-- Down from high above, to the first cell of clay.
			local cx, cz, y = math.floor((x or 0) / U), math.floor(z / U), math.floor(40 / U)
			while y > 0 and not s:has(cx, y, cz) do
				y -= 1
			end
			return (y + 1) * U
		end
		local function side(s: Sculpt, y: number, z: number): number
			local cx, cy, cz = 0, math.floor(y / U), math.floor(z / U)
			while s:has(cx + 1, cy, cz) do
				cx += 1
			end
			return (cx + 1) * U
		end
		-- Hide: a pale belly in bands, dark stripes down the flanks, lighter dapples over the back.
		local function hide(p: Vec, open: (number, number, number) -> boolean, belly: number): Look?
			local y, z = p[2], p[3]
			if open(0, -1, 0) and y < belly then
				return if math.floor(z / 2.4) % 2 == 0 then BELLY else BELLY_DARK
			end
			if open(0, 1, 0) and speckle(p, 0.12) then
				return DAPPLE
			end
			return nil
		end
		-- A plate standing up from the back: a triangle leaning a little back, its root sunk in, a darker band
		-- at the root and, on the big ones, a glowing point.
		local function plate(limb: Limb, s: Sculpt, z: number, x: number, tall: number, long: number, glow: boolean)
			local base = top(s, z, x) - 0.6
			local front, back = { x, base - 0.5, z + long / 2 }, { x, base - 0.5, z - long / 2 }
			local tip = { x, base + tall, z - long * 0.2 }
			triangle(limb, at(front), at(tip), at(back), 0.75 / U, PLATE)
			triangle(
				limb,
				at(vadd(front, { 0, 0, 0.12 })),
				at(vlerp(front, tip, 0.2)),
				at(vadd(back, { 0, 0, -0.12 })),
				0.95 / U,
				PLATE_DARK
			)
			if glow then
				local a, b = vlerp(front, tip, 0.6), vlerp(back, tip, 0.6)
				triangle(
					limb,
					at(vadd(a, { 0, 0, 0.1 })),
					at(vadd(tip, { 0, 0.12, 0 })),
					at(vadd(b, { 0, 0, -0.1 })),
					1.05 / U,
					TIP,
					NEON
				)
			end
		end

		-- A big body arching highest over its hips, dark bands down its flanks, and a row of bony knobs low on
		-- each side.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 16.5, -5 }, { 7, 8, 10.8 }), HIDE)
		body:add(ellipsoid({ 0, 14, 5 }, { 6.4, 6.6, 8.4 }), HIDE)
		body:add(ellipsoid({ 0, 12, -2 }, { 6.2, 4.6, 10 }), HIDE)
		body:coat(function(p, open)
			return hide(p, open, 11.5)
		end)
		for _, s in { 1, -1 } do
			for _, band in { { 8, 6 }, { 3, 1.5 }, { -2, -3.5 }, { -7, -8.5 }, { -11.5, -12.5 } } do
				body:trace({ { 0, 23, band[1] }, { 0, 18, band[2] }, { 0, 14, band[2] + 0.8 } }, { -s, 0, 0 }, DARK)
			end
		end
		for _, z in { 8, 4.5, 1, -2.5, -6, -9.5 } do
			for _, s in { 1, -1 } do
				local x = side(body, 12.5, z) * s
				body:add(rod({ { x - 0.5 * s, 12.5, z, 0.9 }, { x + 0.5 * s, 12.6, z, 0.55 } }), KNOB)
			end
		end

		-- A small head held low on a thick neck, with a dark horny beak and little bony studs down its throat.
		local head = newSculpt(U)
		head:add(rod({ { 0, 14, 9, 4.2 }, { 0, 11.5, 14, 3 }, { 0, 10.4, 17, 2.6 } }), HIDE)
		head:add(ellipsoid({ 0, 10.8, 18.8 }, { 2.6, 2.5, 3.7 }), HIDE)
		head:add(ellipsoid({ 0, 11.6, 18.2 }, { 2.3, 1.6, 2.6 }), HIDE)
		head:add(ellipsoid({ 0, 9.8, 22.3 }, { 1.75, 1.65, 2.1 }), HIDE)
		head:coat(function(p, open)
			if p[3] > 23.2 and p[2] < 11 then
				return BEAK
			end
			if open(0, -1, 0) and p[2] < 10.2 then
				return if p[3] < 15 and math.floor(p[3] / 1.4) % 2 == 0 then KNOB else BELLY
			end
			if open(0, 1, 0) and speckle(p, 0.12) then
				return DAPPLE
			end
			return nil
		end)
		head:trace({ { 0, 9.4, 19.5 }, { 0, 9.5, 23.6 } }, { -1, 0, 0 }, BEAK)
		head:trace({ { 0, 9.4, 19.5 }, { 0, 9.5, 23.6 } }, { 1, 0, 0 }, BEAK)

		-- Sturdy legs, the back ones longer, on round feet with short toes and pale nails.
		local function foot(s: Sculpt, x: number, z: number, toes: number)
			s:add(ellipsoid({ x, 1.4, z }, { 2.8, 1.4, 2.8 }), HIDE)
			for t = 1, toes do
				local dx = (t - (toes + 1) / 2) * 1.5
				s:add(ellipsoid({ x + dx, 1, z + 2.3 }, { 0.75, 0.9, 0.9 }), NAIL)
			end
		end
		local front = newSculpt(U)
		front:add(rod({ { 4.6, 12, 6, 3 }, { 5, 6, 7, 2.5 }, { 5, 2.6, 7.4, 2.4 } }), HIDE)
		foot(front, 5, 7.8, 3)
		front:add(ellipsoid({ 5.4, 7.6, 6.8 }, { 2.3, 1.8, 2.2 }), HIDE)
		local back = newSculpt(U)
		back:add(ellipsoid({ 5, 14.5, -6 }, { 3.4, 6.4, 5 }), HIDE)
		back:add(rod({ { 5.4, 10, -7.5, 3.4 }, { 5.6, 4.5, -8.4, 2.8 }, { 5.6, 2.8, -8, 2.7 } }), HIDE)
		foot(back, 5.6, -6.8, 3)
		for _, leg in { front, back } do
			leg:coat(function(p, open)
				if open(0, 1, 0) and speckle(p, 0.12) then
					return DAPPLE
				end
				return nil
			end)
		end
		back:trace({ { 0, 19, -4.5 }, { 0, 14, -6 }, { 0, 10, -7 } }, { -1, 0, 0 }, DARK)

		-- A long tail with small plates, and four spikes at the end.
		local tail = newSculpt(U)
		tail:add(
			rod({ { 0, 17.5, -13, 5 }, { 0, 15.5, -21, 3.5 }, { 0, 13.5, -29, 2.4 }, { 0, 12.5, -35, 1.3 } }),
			HIDE
		)
		tail:coat(function(p, open)
			return hide(p, open, 30)
		end)
		for _, s in { 1, -1 } do
			for _, band in { { -16, -17.5 }, { -21, -22 }, { -25.5, -26.5 } } do
				tail:trace({ { 0, 21, band[1] }, { 0, 14, band[2] } }, { -s, 0, 0 }, DARK)
			end
		end

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", at({ 0, 14, -2 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, HIDE)
		local headLimb = pet:limb("Head", at({ 0, 13, 9 }))
		head:draw(headLimb, { body }, HIDE)
		for _, s in { 1, -1 } do
			local x = side(head, 11.6, 20) * s
			egg(headLimb, at({ x - 0.15 * s, 11.6, 20 }), { 0.7 / U, 1.15 / U, 1.15 / U }, nil, EYE)
			egg(headLimb, at({ x + 0.12 * s, 12, 20.3 }), { 0.3 / U, 0.4 / U, 0.4 / U }, nil, SHINE)
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", at({ 4.6, 11, 6 }), function(limb)
			front:draw(limb, { body }, HIDE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", at({ 5, 12, -6 }), function(limb)
			back:draw(limb, { body }, HIDE)
		end)
		local tailLimb = pet:limb("Tail", at({ 0, 16, -13 }))
		tail:draw(tailLimb, { body }, HIDE)

		-- Two staggered rows of plates from the neck to the tail, tallest over the hips.
		plate(headLimb, head, 11.5, -0.7, 3.2, 3.4, false)
		plate(headLimb, head, 14.2, 0.7, 2.4, 2.8, false)
		for index, z in { 8.5, 5.2, 1.9, -1.4, -4.7, -8, -11.3 } do
			local x = if index % 2 == 0 then 0.8 else -0.8
			local tall = ({ 5.5, 7.5, 9.5, 11, 11, 9.5, 7.5 })[index]
			plate(bodyLimb, body, z, x, tall, 5.4, index >= 2 and index <= 6)
		end
		for index, z in { -15.5, -19.5, -23.5, -27 } do
			plate(tailLimb, tail, z, if index % 2 == 0 then 0.6 else -0.6, ({ 6, 4.6, 3.4, 2.4 })[index], 4.2, false)
		end
		for _, s in { 1, -1 } do
			for _, spike in { { -30.5, 13.6, -33, 1.4 }, { -33.5, 13.2, -37.5, 1.2 } } do
				local root = { 1 * s, spike[2], spike[1] }
				local point = { 6 * s, spike[2] + 3.4, spike[3] }
				taper(tailLimb, at(root), at(point), spike[4] / U, spike[4] / U, { 0, 1, 0 }, SPIKE)
			end
		end

		pet:light(TIP, 1.8, 18)
		pet:seat(0, 23 / U, -3 / U)
	end,
}

Designs.Brachiosaurus = {
	name = "Brachiosaurus",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.48 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with leaves of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local HIDE = look(110, 150, 170)
		local DARK = look(76, 108, 132)
		local BELLY = look(222, 224, 196)
		local LIGHT = look(150, 186, 200)
		local NAIL = look(236, 228, 206)
		local MOUTH = look(60, 70, 84)
		local LEAF = rgb(96, 168, 72)
		local LEAF_DARK = rgb(66, 130, 56)
		local TWIG = rgb(122, 88, 56)

		-- Dappled hide: big darker patches, a pale belly and throat.
		local function hide(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, -1, 0) or (open(0, 0, 1) and p[2] > 22) then
				return BELLY
			end
			local n = noise({ math.floor(p[1] / 2.4), math.floor(p[2] / 2.4), math.floor(p[3] / 2.4) })
			if n < 0.28 then
				return DARK
			elseif n > 0.9 then
				return LIGHT
			end
			return nil
		end

		-- A great body, its shoulders higher than its hips.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 20, -1 }, { 6.4, 6.6, 10 }), HIDE)
		body:add(ellipsoid({ 0, 23.6, 4.6 }, { 5.4, 4.4, 5.4 }), HIDE)
		body:add(ellipsoid({ 0, 20, -8 }, { 5.6, 5.8, 5 }), HIDE)
		body:coat(hide)

		-- A neck rising high and a small head with a domed crest.
		local head = newSculpt(U)
		head:add(rod({ { 0, 24, 8, 3.9 }, { 0, 30, 11, 2.9 }, { 0, 37, 13, 2.3 }, { 0, 42.4, 14, 2.05 } }), HIDE)
		head:add(ellipsoid({ 0, 44.2, 15.8 }, { 2.1, 1.9, 3.3 }), HIDE)
		head:add(ellipsoid({ 0, 45.9, 15.2 }, { 1.45, 1.2, 1.6 }), HIDE)
		head:coat(function(p, open)
			if p[3] > 15.6 and p[2] < 43.7 and (open(1, 0, 0) or open(-1, 0, 0)) and p[2] > 43 then
				return MOUTH
			end
			return hide(p, open)
		end)

		local function foot(s: Sculpt, x: number, z: number)
			s:add(ellipsoid({ x, 1.4, z }, { 2.9, 1.4, 3.1 }), HIDE)
			for _, dx in { -1.4, 0, 1.4 } do
				s:add(ellipsoid({ x + dx, 0.9, z + 2.6 }, { 0.75, 0.9, 0.7 }), NAIL)
			end
		end
		local front = newSculpt(U)
		front:add(rod({ { 4.6, 22, 5, 3.1 }, { 4.8, 12, 5.6, 2.7 }, { 4.8, 2.6, 5.4, 2.6 } }), HIDE)
		foot(front, 4.8, 5.8)
		local back = newSculpt(U)
		back:add(ellipsoid({ 4.6, 19, -8 }, { 3.3, 5.2, 4.1 }), HIDE)
		back:add(rod({ { 4.8, 14, -9, 2.8 }, { 4.9, 2.6, -8.6, 2.6 } }), HIDE)
		foot(back, 4.9, -8.4)
		for _, leg in { front, back } do
			leg:coat(function(p, open)
				return if p[2] > 2.4 then hide(p, open) else nil
			end)
		end

		local tail = newSculpt(U)
		tail:add(
			rod({ { 0, 20, -13, 4.1 }, { 0, 18, -20, 2.7 }, { -1, 15.6, -27, 1.7 }, { -2.6, 14.4, -32, 0.8 } }),
			HIDE
		)
		tail:coat(hide)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 20, 0 })), { head, front, frontMirror, back, backMirror, tail }, HIDE)
		local headLimb = pet:limb("Head", T.at({ 0, 24, 8 }))
		head:draw(headLimb, { body }, HIDE)
		roundEyes(headLimb, head, 45, 16.4, 1)
		-- A sprig of leaves in its mouth.
		local mouth = { -1.2, 43.4, 18.6 }
		T.branch(
			headLimb,
			{ mouth, vadd(mouth, { -2, 0.4, 1 }), vadd(mouth, { -3.8, 1.2, 1.4 }) },
			0.35,
			{ 0, 1, 0 },
			TWIG
		)
		for index, leaf in { { -2, 0.6, 1.2 }, { -3, 0.9, 1.3 }, { -3.8, 1.2, 1.5 }, { -1.4, 0.3, 0.9 } } do
			T.ball(headLimb, vadd(mouth, leaf), { 1.6, 0.4, 1 }, if index % 2 == 0 then LEAF_DARK else LEAF)
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 4.6, 22, 5 }), function(limb)
			front:draw(limb, { body }, HIDE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4.6, 19, -8 }), function(limb)
			back:draw(limb, { body }, HIDE)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 20, -12 })), { body }, HIDE)

		pet:light(LEAF, 1.8, 18)
		pet:particles("Leaves", LEAF, 8)
		pet:seat(0, 28 / U, -1 / U)
	end,
}

Designs.TRex = {
	name = "T-Rex",
	skeleton = "Theropod",
	gait = "Stomp",
	scale = 0.42 * 1.2,
	draw = function(pet)
		-- Modelled in finer units than it is built in: 1.2 of them to a block.
		local U = 1.2
		local function at(p: Vec): Vec
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local SCALE = look(84, 70, 56)
		local DARK = look(44, 36, 30)
		local STRIPE = look(156, 40, 30)
		local BELLY = look(198, 166, 118)
		local BELLY_DARK = look(166, 132, 92)
		local TOOTH = look(246, 240, 222)
		local GUM = look(150, 36, 38)
		local MOUTH = look(70, 12, 16)
		local CLAW = look(30, 26, 24)
		local SCAR = look(196, 176, 150)
		local AMBER = rgb(255, 172, 30)

		local function underside(p: Vec, along: number): Look
			return if math.floor(p[along] / 1.8) % 2 == 0 then BELLY else BELLY_DARK
		end
		-- Tiger stripes: lines traced down both sides from the spine.
		local function stripes(s: Sculpt, list: { { Vec } })
			for _, side in { 1, -1 } do
				for _, stripe in list do
					s:trace(stripe, { -side, 0, 0 }, STRIPE)
				end
			end
		end

		-- A deep, heavy body over the hips, banded with crimson stripes, a pale belly in plates, and a row of dark
		-- bony scutes down its spine.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 22, -4 }, { 6, 6.5, 8 }), SCALE)
		body:add(ellipsoid({ 0, 20.6, 5 }, { 6.6, 8.2, 8.5 }), SCALE)
		body:add(ellipsoid({ 0, 25.5, 2 }, { 4.6, 3.6, 9 }), SCALE)
		body:coat(function(p, open)
			if open(0, -1, 0) and p[2] < 19 then
				return underside(p, 3)
			end
			return nil
		end)
		stripes(body, {
			{ { 0, 28.5, 10 }, { 0, 24, 11 }, { 0, 19.5, 12.5 } },
			{ { 0, 29, 5.5 }, { 0, 24, 6 }, { 0, 17.5, 7.5 } },
			{ { 0, 29, 1 }, { 0, 24.5, 1 }, { 0, 17, 2.5 } },
			{ { 0, 28.5, -3.5 }, { 0, 24.5, -4 }, { 0, 19, -3 } },
			{ { 0, 27.5, -8 }, { 0, 23.5, -9 }, { 0, 19.5, -8.5 } },
		})
		local function top(s: Sculpt, z: number, x: number?): number
			local cx, cz, y = math.floor((x or 0) / U), math.floor(z / U), math.floor(20 / U)
			while s:has(cx, y + 1, cz) do
				y += 1
			end
			return (y + 1) * U
		end
		for _, z in { 10, 6.5, 3, -0.5, -4, -7.5, -10.5 } do
			local y = top(body, z) - 0.5
			body:add(rod({ { 0, y, z, 0.9 }, { 0, y + 1.6, z - 1, 0.3 } }), DARK)
		end

		-- A thick neck and a huge head: a deep skull, wide at the jaw muscles, heavy brows and horn knobs over
		-- small glowing eyes, scarred cheeks, and jaws thrown open on rows of fangs.
		local head = newSculpt(U)
		head:add(rod({ { 0, 22, 9, 5 }, { 0, 25.5, 13, 4.6 }, { 0, 28, 16, 4.2 } }), SCALE)
		-- The head is drawn 1.12 times the size of the numbers below, about the top of the neck.
		local H, centre = 1.12, { 0, 28, 17 }
		local function hp(q: Vec): Vec
			return {
				centre[1] + (q[1] - centre[1]) * H,
				centre[2] + (q[2] - centre[2]) * H,
				centre[3] + (q[3] - centre[3]) * H,
			}
		end
		local function E(c: Vec, r: Vec): Shape
			return ellipsoid(hp(c), { r[1] * H, r[2] * H, r[3] * H })
		end
		local function R(points: { { number } }): Shape
			local out = {}
			for _, q in points do
				local m = hp(q)
				table.insert(out, { m[1], m[2], m[3], q[4] * H })
			end
			return rod(out)
		end
		head:add(E({ 0, 30, 19.5 }, { 4.3, 4.1, 5 }), SCALE)
		head:add(E({ 0, 30.4, 24 }, { 3.5, 3.3, 5.4 }), SCALE)
		head:add(E({ 0, 29.8, 28.6 }, { 2.8, 2.6, 3.6 }), SCALE)
		head:add(E({ 0, 32.4, 22.5 }, { 2.6, 1.6, 5.5 }), SCALE)
		head:add(E({ 0, 23.7, 23.5 }, { 3.5, 1.8, 6.6 }), SCALE)
		head:add(E({ 0, 25.4, 18.5 }, { 3.6, 2.6, 3.4 }), SCALE)
		head:carve(E({ 0, 26.5, 25.2 }, { 2.7, 1.7, 6 }))
		head:paint(E({ 0, 26.5, 25.2 }, { 3.2, 2.2, 6.5 }), GUM, nil, true)
		head:paint(E({ 0, 26, 23 }, { 2, 1.3, 4.6 }), MOUTH, nil, true)
		for _, s in { 1, -1 } do
			head:add(R({ { 2.5 * s, 33.2, 19.8, 1.2 }, { 2.4 * s, 33.4, 23.6, 0.8 } }), DARK)
			head:add(R({ { 3 * s, 33.6, 19, 0.9 }, { 3.3 * s, 35, 18.2, 0.35 } }), DARK)
			for _, z in { 20.8, 23, 25.2, 27.4, 29.4 } do
				local inset = if z > 28 then 0.5 else 0
				head:add(R({ { (2.3 - inset) * s, 27.8, z, 0.5 }, { (2.15 - inset) * s, 26.2, z + 0.3, 0.2 } }), TOOTH)
			end
			for _, z in { 22, 24.2, 26.4 } do
				head:add(R({ { 2.1 * s, 25.2, z, 0.45 }, { 2 * s, 26.6, z + 0.3, 0.2 } }), TOOTH)
			end
			head:add(R({ { 0.8 * s, 27.8, 31.2, 0.45 }, { 0.7 * s, 26.3, 31.5, 0.2 } }), TOOTH)
		end
		head:coat(function(real, open)
			local x = centre[1] + (real[1] - centre[1]) / H
			local y = centre[2] + (real[2] - centre[2]) / H
			local z = centre[3] + (real[3] - centre[3]) / H
			-- Nostrils at the tip of the snout.
			if z > 30.6 and y > 30.4 and math.abs(x) > 0.5 and math.abs(x) < 1.7 then
				return DARK
			end
			-- A pale throat and chin.
			if open(0, -1, 0) and y < 24.5 and z < 28 then
				return underside(real, 3)
			end
			return nil
		end)
		stripes(head, {
			{ { 0, 29, 12 }, { 0, 25, 13 }, { 0, 21, 13 } },
			{ { 0, 31, 16 }, { 0, 27.5, 16.5 } },
			{ hp({ 0, 34, 20.5 }), hp({ 0, 31.5, 18 }) },
		})
		-- Old scars clawed across its cheek and snout.
		for _, side in { 1, -1 } do
			head:trace({ hp({ 0, 31.8, 25.5 }), hp({ 0, 29.2, 27.6 }) }, { -side, 0, 0 }, SCAR)
		end
		head:trace({ hp({ 0, 32.2, 23 }), hp({ 0, 30.4, 25.4 }) }, { -1, 0, 0 }, SCAR)

		-- Small, clawed arms held tucked up against its chest.
		local arm = newSculpt(U)
		arm:add(rod({ { 4.2, 19.5, 10.5, 1.4 }, { 5.3, 16.6, 12.6, 1.05 }, { 5.1, 15.8, 15, 0.85 } }), SCALE)
		for _, dx in { -0.45, 0.45 } do
			arm:add(rod({ { 5.1 + dx, 15.6, 15.4, 0.45 }, { 5 + dx, 14.6, 16.6, 0.22 } }), CLAW)
		end

		-- Massive legs: a thick thigh, a shin slanting back, and a foot of three clawed toes with a spur behind.
		local leg = newSculpt(U)
		leg:add(ellipsoid({ 5.4, 18.5, -3 }, { 3.8, 7, 6 }), SCALE)
		leg:add(rod({ { 5.8, 14.5, -4, 3.5 }, { 6.1, 7, -8, 2.4 } }), SCALE)
		leg:add(rod({ { 6.1, 7, -8, 2.1 }, { 6.1, 2.2, -5.5, 1.8 } }), SCALE)
		for _, dx in { -1.5, 0, 1.5 } do
			leg:add(rod({ { 6.1 + dx, 1.7, -5, 1.05 }, { 6.1 + dx * 1.3, 1.25, -1.6, 0.85 } }), SCALE)
			leg:add(rod({ { 6.1 + dx * 1.3, 1.3, -1.4, 0.6 }, { 6.1 + dx * 1.4, 0.35, 0.4, 0.25 } }), CLAW)
		end
		leg:add(rod({ { 6.1, 1.9, -6.8, 0.65 }, { 6.2, 0.6, -8.3, 0.3 } }), CLAW)
		leg:coat(function(p, open)
			if open(0, -1, 0) and p[2] > 12 then
				return underside(p, 3)
			end
			return nil
		end)
		leg:trace({ { 0, 23, -1 }, { 0, 18.5, -2.5 }, { 0, 14.5, -2 } }, { -1, 0, 0 }, STRIPE)
		leg:trace({ { 0, 22.5, -5.5 }, { 0, 17.5, -6.5 } }, { -1, 0, 0 }, STRIPE)

		-- A long, heavy tail held out behind for balance, swinging a little to one side, scuted along the top.
		local tail = newSculpt(U)
		local spine = {
			{ 0, 23, -9, 5.2 },
			{ 0, 22, -16, 4.2 },
			{ 0.8, 20.5, -23, 3.2 },
			{ 2.2, 19, -30, 2.3 },
			{ 3.6, 18, -36, 1.4 },
			{ 4.4, 17.6, -40, 0.6 },
		}
		tail:add(rod(spine), SCALE)
		tail:coat(function(p, open)
			if open(0, -1, 0) then
				return underside(p, 3)
			end
			return nil
		end)
		for index = 2, #spine - 1 do
			local a, b = spine[index - 1], spine[index]
			local mid = vlerp(a, b, 0.5)
			for _, q in { mid, b } do
				local y = top(tail, q[3], q[1]) - 0.4
				tail:add(rod({ { q[1], y, q[3], 0.7 }, { q[1], y + 1.2, q[3] - 0.8, 0.25 } }), DARK)
			end
		end
		stripes(tail, {
			{ { 0, 28, -13 }, { 0, 21, -14 }, { 0, 18, -13 } },
			{ { 0, 26, -18.5 }, { 0, 20, -19.5 }, { 0, 17.5, -19 } },
			{ { 0, 24, -24 }, { 0, 19, -25 }, { 0, 17, -24.5 } },
			{ { 0, 22, -29 }, { 0, 17.5, -30 } },
			{ { 0, 20.5, -33.5 }, { 0, 17, -34.5 } },
		})

		local legMirror, armMirror = leg:mirror(), arm:mirror()
		body:draw(pet:limb("Body", at({ 0, 22, 0 })), { head, leg, legMirror, arm, armMirror, tail }, SCALE)
		local headLimb = pet:limb("Head", at({ 0, 23, 10 }))
		head:draw(headLimb, { body }, SCALE)
		-- Small, deep-set eyes: flat glowing slits slanting up towards the back, each in a dark rim.
		for _, s in { 1, -1 } do
			local out = { s, 0, 0 }
			local eye = hp({ 0, 31.3, 21.6 })
			local cy, cz = math.floor(eye[2] / U), math.floor(eye[3] / U)
			local cx = 6
			while not head:has(if s > 0 then cx else -1 - cx, cy, cz) and cx > 0 do
				cx -= 1
			end
			local depth = (cx + 1) * U - 0.03
			local function slit(grow: number, color: Color, material: string?, thick: number)
				local nose = hp({ 0, 30.9 - grow * 0.2, 23 + grow })
				local backPoint = hp({ 0, 31.8 + grow * 0.2, 20.2 - grow })
				nose[1], backPoint[1] = s * (depth + thick / 2), s * (depth + thick / 2)
				local p1, p2 = vlerp(nose, backPoint, 0.3), vlerp(nose, backPoint, 0.7)
				local width = (0.95 + grow) * H
				taper(headLimb, at(p1), at(nose), width / U, thick / U, out, color, material)
				blade(headLimb, at(p1), at(p2), width / U, thick / U, out, color, material)
				taper(headLimb, at(p2), at(backPoint), width / U, thick / U, out, color, material)
			end
			slit(0.4, CLAW.color, nil, 0.16)
			slit(0, AMBER, NEON, 0.3)
		end
		pet:limbPair("LeftArm", "RightArm", at({ 4.4, 19.5, 10.5 }), function(limb)
			arm:draw(limb, { body }, SCALE)
		end)
		pet:limbPair("LeftLeg", "RightLeg", at({ 5.2, 20, -3 }), function(limb)
			leg:draw(limb, { body }, SCALE)
		end)
		tail:draw(pet:limb("Tail", at({ 0, 22, -10 })), { body }, SCALE)

		pet:light(rgb(255, 150, 40), 2.4, 22)
		pet:particles("Leaves", rgb(110, 176, 70), 10)
		pet:seat(0, 30 / U, -2 / U)
	end,
}

Designs.Mosasaurus = {
	name = "Mosasaurus",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 4,
	scale = 0.42,
	draw = function(pet)
		-- Modelled in the units it is built in: one to a block.
		local U = 1
		local function at(p: Vec): Vec
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local BACK = look(28, 58, 90)
		local SIDE = look(42, 90, 126)
		local BELLY = look(206, 228, 228)
		local STRIPE = look(20, 42, 68)
		local GLOW = look(80, 236, 255, NEON)
		local PALE_GLOW = look(190, 255, 250, NEON)
		local FIN = look(30, 66, 100)
		local TOOTH = look(242, 240, 228)
		local GUM = look(150, 52, 72)
		local MOUTH = look(54, 18, 32)

		-- Dark above, pale below, and rows of glowing spots down each flank, like the lights of deep-sea fish.
		local function skin(p: Vec, open: (number, number, number) -> boolean, middle: number): Look?
			local y, z = p[2], p[3]
			if open(0, -1, 0) and y < middle then
				return BELLY
			end
			if open(0, 1, 0) and not open(1, 0, 0) and not open(-1, 0, 0) then
				return if math.floor(z / 3) % 2 == 0 then BACK else STRIPE
			end
			if math.abs(y - middle - 1) < 0.75 and (z % 3.2) < 1.3 and (open(1, 0, 0) or open(-1, 0, 0)) then
				return GLOW
			end
			return nil
		end

		-- A long, streamlined body with its back flippers, and a low glowing crest down its spine.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 10.5, 4 }, { 6.4, 7, 11.5 }), SIDE)
		body:add(ellipsoid({ 0, 10.2, -8 }, { 5.6, 6.2, 9.5 }), SIDE)
		for _, s in { 1, -1 } do
			body:add(
				ellipsoid({ 0, 0, 0 }, { 4.2, 0.75, 2.2 }),
				GLOW,
				{ origin = { 7.2 * s, 5.2, -9.4 }, yaw = 0.6 * s, roll = -0.5 * s }
			)
			body:add(
				ellipsoid({ 0, 0, 0 }, { 3.7, 0.95, 1.8 }),
				FIN,
				{ origin = { 7 * s, 5.3, -9.2 }, yaw = 0.6 * s, roll = -0.5 * s }
			)
		end
		body:coat(function(p, open)
			return skin(p, open, 10)
		end)
		for _, z in { 10, 6.5, 3, -0.5, -4, -7.5, -11 } do
			local top = math.floor(10 / U)
			while body:has(0, top + 1, math.floor(z / U)) do
				top += 1
			end
			local y = (top + 1) * U - 0.4
			body:add(rod({ { 0, y, z, 0.8 }, { 0, y + 1, z - 1.2, 0.35 } }), GLOW)
		end

		-- A crocodile's head on a thick neck: long jaws open on rows of teeth, glowing eyes, and glowing spots
		-- running down its snout.
		local head = newSculpt(U)
		head:add(rod({ { 0, 10.4, 12, 5.4 }, { 0, 10.6, 17, 4.5 } }), SIDE)
		head:add(ellipsoid({ 0, 11.2, 20.5 }, { 4, 3.6, 5.8 }), SIDE)
		head:add(ellipsoid({ 0, 11, 26.5 }, { 2.6, 2.2, 5.2 }), SIDE)
		head:add(ellipsoid({ 0, 10.8, 31 }, { 1.9, 1.7, 2.6 }), SIDE)
		head:add(ellipsoid({ 0, 6.9, 23.5 }, { 3.1, 1.5, 8.2 }), SIDE)
		head:carve(ellipsoid({ 0, 8.9, 25.5 }, { 2.3, 1.5, 7.4 }))
		head:paint(ellipsoid({ 0, 8.9, 25.5 }, { 2.8, 2, 7.9 }), GUM, nil, true)
		head:paint(ellipsoid({ 0, 8.5, 24 }, { 1.6, 1.1, 5.4 }), MOUTH, nil, true)
		for _, s in { 1, -1 } do
			for _, z in { 19.5, 21.6, 23.7, 25.8, 27.9, 30 } do
				local inset = (z - 19) * 0.07
				head:add(rod({ { (2.1 - inset) * s, 10.2, z, 0.45 }, { (2 - inset) * s, 8.6, z + 0.3, 0.18 } }), TOOTH)
			end
			for _, z in { 20.5, 22.6, 24.7, 26.8, 28.9 } do
				head:add(
					rod({
						{ (1.9 - (z - 19) * 0.07) * s, 7.8, z, 0.42 },
						{ (1.8 - (z - 19) * 0.07) * s, 9.2, z + 0.3, 0.18 },
					}),
					TOOTH
				)
			end
		end
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			-- Glowing spots in a row down the top of its snout.
			if open(0, 1, 0) and z > 21 and math.abs(x) < 0.7 and (z % 2.6) < 1.3 then
				return PALE_GLOW
			end
			if open(0, -1, 0) and y < 9.5 then
				return BELLY
			end
			if open(0, 1, 0) and not open(1, 0, 0) and not open(-1, 0, 0) then
				return BACK
			end
			return nil
		end)

		-- Paddle flippers, edged with light.
		local flipper = newSculpt(U)
		local frame = { origin = { 10, 4.6, 6 }, yaw = 0.55, roll = -0.5 }
		flipper:add(rod({ { 4.8, 7.4, 8.4, 2.2 }, { 7.6, 5.8, 7.2, 1.6 } }), SIDE)
		flipper:add(ellipsoid({ 0, 0, 0 }, { 6.4, 0.75, 3.2 }), GLOW, frame)
		flipper:add(ellipsoid({ 0, 0, 0 }, { 5.8, 0.95, 2.7 }), FIN, frame)

		-- A long tail bending down at the end into a shark-like fluke, its upper lobe glowing along the edge.
		local tail = newSculpt(U)
		tail:add(
			rod({
				{ 0, 9.8, -14, 4.6 },
				{ 0, 9.6, -22, 3.5 },
				{ 0, 9, -30, 2.5 },
				{ 0, 7.8, -36, 1.7 },
				{ 0, 5.4, -40.5, 1.1 },
			}),
			SIDE
		)
		tail:add(ellipsoid({ 0, 0, 0 }, { 0.7, 5, 2 }), GLOW, { origin = { 0, 11.2, -40.6 }, pitch = 0.75 })
		tail:add(ellipsoid({ 0, 0, 0 }, { 0.95, 4.4, 1.6 }), FIN, { origin = { 0, 10.9, -40.2 }, pitch = 0.75 })
		tail:add(ellipsoid({ 0, 0, 0 }, { 0.95, 3.8, 1.5 }), FIN, { origin = { 0, 3, -42.3 }, pitch = -0.6 })
		tail:coat(function(p, open)
			if p[3] < -38 then
				return nil
			end
			return skin(p, open, 9.2)
		end)

		local flipperMirror = flipper:mirror()
		body:draw(pet:limb("Body", at({ 0, 10, 0 })), { head, flipper, flipperMirror, tail }, SIDE)
		local headLimb = pet:limb("Head", at({ 0, 10, 12 }))
		head:draw(headLimb, { body }, SIDE)
		-- Narrow glowing eyes set in dark rims.
		for _, s in { 1, -1 } do
			local out = { s, 0, 0 }
			local cy, cz = math.floor(12 / U), math.floor(20.5 / U)
			local cx = 6
			while not head:has(if s > 0 then cx else -1 - cx, cy, cz) and cx > 0 do
				cx -= 1
			end
			local depth = (cx + 1) * U - 0.03
			local function almond(grow: number, color: Color, material: string?, thick: number)
				local nose = { s * (depth + thick / 2), 11.7 - grow * 0.2, 22.4 + grow }
				local backPoint = { s * (depth + thick / 2), 12.5 + grow * 0.2, 18.8 - grow }
				local p1, p2 = vlerp(nose, backPoint, 0.3), vlerp(nose, backPoint, 0.7)
				local width = 1 + grow
				taper(headLimb, at(p1), at(nose), width / U, thick / U, out, color, material)
				blade(headLimb, at(p1), at(p2), width / U, thick / U, out, color, material)
				taper(headLimb, at(p2), at(backPoint), width / U, thick / U, out, color, material)
			end
			almond(0.4, STRIPE.color, nil, 0.16)
			almond(0, PALE_GLOW.color, NEON, 0.3)
		end
		pet:limbPair("LeftFin", "RightFin", at({ 5, 7.4, 8.2 }), function(limb)
			flipper:draw(limb, { body }, SIDE)
		end)
		tail:draw(pet:limb("Tail", at({ 0, 10, -14 })), { body }, SIDE)

		pet:light(rgb(80, 220, 255), 3, 24)
		pet:particles("Bubbles", rgb(150, 245, 255), 16)
		pet:seat(0, 17.5 / U, 0)
	end,
}

Designs.LunarDragon = {
	name = "Lunar Dragon",
	skeleton = "Dragon",
	gait = "Walk",
	scale = 0.42 * 1.2,
	draw = function(pet)
		-- Modelled in finer units than it is built in: 1.2 of them to a block.
		local U = 1.2
		local function at(p: Vec): Vec
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local NIGHT = look(38, 42, 96)
		local NIGHT_DARK = look(26, 28, 68)
		local SILVER = look(212, 220, 240)
		local SILVER_DARK = look(164, 174, 206)
		local MOON = look(236, 242, 255, NEON)
		local STAR = look(255, 244, 200, NEON)
		local GLOW = look(150, 190, 255, NEON)
		local CLAW = look(30, 30, 52)
		local MOONFIRE, MOONFIRE_CORE = rgb(110, 160, 255), rgb(235, 245, 255)

		-- A steady scatter of stars over its scales: the same cells every time.
		local function twinkle(p: Vec, chance: number): boolean
			local n = math.sin(p[1] * 12.9898 + p[2] * 78.233 + p[3] * 37.719) * 43758.5453
			return n - math.floor(n) < chance
		end
		-- Silver plates under its belly, and stars on its back.
		local function scales(p: Vec, open: (number, number, number) -> boolean, belly: number): Look?
			if open(0, -1, 0) and p[2] < belly then
				return if math.floor(p[3] / 1.6) % 2 == 0 then SILVER else SILVER_DARK
			end
			if open(0, 1, 0) and twinkle(p, 0.07) then
				return STAR
			end
			if not open(0, 1, 0) and (open(1, 0, 0) or open(-1, 0, 0)) and math.floor(p[2] / 1.2) % 3 == 0 then
				return NIGHT_DARK
			end
			return nil
		end
		-- A crescent moon on the side of a limb: inside one circle and outside another, nudged up and back.
		local function crescent(p: Vec, y: number, z: number, r: number): boolean
			local dy, dz = p[2] - y, p[3] - z
			local ey, ez = dy - r * 0.35, dz + r * 0.35
			return dy * dy + dz * dz <= r * r and ey * ey + ez * ez > (r * 0.8) ^ 2
		end
		local function top(s: Sculpt, z: number, x: number?): number
			local cx, cz, y = math.floor((x or 0) / U), math.floor(z / U), math.floor(12 / U)
			while s:has(cx, y + 1, cz) do
				y += 1
			end
			return (y + 1) * U
		end
		-- A mane of glowing fins down its spine.
		local function mane(s: Sculpt, points: { Vec }, tall: number)
			for _, q in points do
				local y = top(s, q[3], q[1]) - 0.5
				s:add(rod({ { q[1], y, q[3], 0.75 }, { q[1], y + tall, q[3] - 1.6, 0.25 } }), GLOW)
				s:add(rod({ { q[1], y - 0.2, q[3], 0.8 }, { q[1], y + tall * 0.45, q[3] - 0.7, 0.5 } }), SILVER)
			end
		end

		-- A long, slender body of midnight scales scattered with stars, a silver belly, a glowing crescent moon on
		-- each shoulder and a mane of light down its back.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 15.5, 3 }, { 5, 5.6, 7.2 }), NIGHT)
		body:add(ellipsoid({ 0, 18.5, 2 }, { 4.2, 3, 6 }), NIGHT)
		body:add(ellipsoid({ 0, 15, -4 }, { 4.5, 5, 7 }), NIGHT)
		body:add(ellipsoid({ 0, 15, -10 }, { 4.8, 5.2, 5 }), NIGHT)
		body:coat(function(p, open)
			if (open(1, 0, 0) or open(-1, 0, 0)) and crescent(p, 16.5, 4.5, 3) then
				return MOON
			end
			return scales(p, open, 13.5)
		end)
		mane(body, { { 0, 0, 8 }, { 0, 0, 4.5 }, { 0, 0, 1 }, { 0, 0, -2.5 }, { 0, 0, -6 }, { 0, 0, -9.5 } }, 3.2)

		-- A long neck rising high and a sleek head: crescent horns sweeping back and up, tipped with moonfire,
		-- glowing fins at its cheeks, a fang showing at each side of its jaw.
		local head = newSculpt(U)
		head:add(rod({ { 0, 18, 6, 3.4 }, { 0, 23, 10, 2.8 }, { 0, 27.5, 12, 2.5 }, { 0, 30, 14.5, 2.4 } }), NIGHT)
		head:add(ellipsoid({ 0, 31.5, 17 }, { 2.9, 2.5, 3.7 }), NIGHT)
		head:add(ellipsoid({ 0, 32.6, 18.6 }, { 2.7, 0.9, 1.9 }), NIGHT)
		head:add(ellipsoid({ 0, 31.2, 21.6 }, { 1.95, 1.6, 3.9 }), NIGHT)
		head:add(ellipsoid({ 0, 29.7, 19.6 }, { 2.2, 1.2, 4.1 }), NIGHT)
		local hornTips = {}
		for _, s in { 1, -1 } do
			local horn = {
				{ 1.6 * s, 33, 16.4, 1.15 },
				{ 2.9 * s, 34.6, 13.4, 1 },
				{ 3.6 * s, 36.6, 11.2, 0.85 },
				{ 3.4 * s, 39, 10.6, 0.65 },
				{ 2.6 * s, 40.8, 12, 0.4 },
			}
			head:add(rod(horn), SILVER)
			head:add(rod({ horn[4], horn[5] }), MOON)
			table.insert(hornTips, { horn[5][1], horn[5][2] + 0.6, horn[5][3] })
			head:add(
				rod({ { 2.1 * s, 30, 17.4, 0.6 }, { 3.6 * s, 29.4, 13.8, 0.4 }, { 4.2 * s, 28.4, 11.6, 0.2 } }),
				GLOW
			)
			head:add(rod({ { 2.4 * s, 31.4, 15.6, 0.5 }, { 3.6 * s, 31.6, 13.2, 0.2 } }), SILVER)
			head:add(rod({ { 1.25 * s, 30.3, 23.6, 0.42 }, { 1.15 * s, 29.3, 23.9, 0.2 } }), SILVER)
		end
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			-- Glowing nostrils, and a silver line along its lips.
			if z > 24.6 and y > 31.6 and math.abs(x) > 0.4 and math.abs(x) < 1.4 then
				return GLOW
			end
			if open(0, -1, 0) and y < 30 then
				return SILVER
			end
			if not open(0, 1, 0) and (open(1, 0, 0) or open(-1, 0, 0)) and math.abs(y - 30.5) < 0.5 and z > 18 then
				return SILVER_DARK
			end
			if open(0, -1, 0) and z < 15.5 and y < 27 then
				return if math.floor(y / 1.6) % 2 == 0 then SILVER else SILVER_DARK
			end
			return scales(p, open, 0)
		end)
		mane(head, { { 0, 0, 8.6 }, { 0, 0, 10.8 }, { 0, 0, 12.6 } }, 2.4)

		-- Slender legs with silver-banded wrists and dark claws.
		local function foot(s: Sculpt, x: number, y: number, z: number)
			s:add(ellipsoid({ x, y, z }, { 1.9, 1.3, 2.5 }), NIGHT)
			for _, dx in { -1.1, 0, 1.1 } do
				s:add(rod({ { x + dx, y - 0.1, z + 1.2, 0.75 }, { x + dx * 1.25, y - 0.4, z + 2.7, 0.6 } }), NIGHT)
				s:add(
					rod({ { x + dx * 1.25, y - 0.35, z + 2.7, 0.45 }, { x + dx * 1.35, y - 1.15, z + 3.8, 0.2 } }),
					CLAW
				)
			end
		end
		local front = newSculpt(U)
		front:add(rod({ { 4.4, 15, 5, 2.5 }, { 5.2, 9, 6.5, 1.9 } }), NIGHT)
		front:add(rod({ { 5.2, 9, 6.5, 1.8 }, { 5.4, 3, 6.1, 1.5 } }), NIGHT)
		front:add(rod({ { 5.3, 4.8, 6.2, 1.75 }, { 5.4, 4, 6.15, 1.7 } }), SILVER)
		foot(front, 5.4, 1.3, 7.6)
		front:coat(function(p, open)
			return scales(p, open, 0)
		end)
		local back = newSculpt(U)
		back:add(ellipsoid({ 4.8, 13, -10 }, { 2.6, 4.6, 3.8 }), NIGHT)
		back:add(rod({ { 5.2, 9.5, -12, 1.9 }, { 5.4, 3.4, -13.6, 1.5 } }), NIGHT)
		back:add(rod({ { 5.4, 3.4, -13.6, 1.4 }, { 5.4, 1.6, -11.4, 1.3 } }), NIGHT)
		back:add(rod({ { 5.4, 4.6, -13.3, 1.65 }, { 5.4, 3.9, -13.5, 1.6 } }), SILVER)
		foot(back, 5.4, 1.3, -10.6)
		back:coat(function(p, open)
			return scales(p, open, 0)
		end)

		-- A long tail curling to one side, with a mane down it, ending in a glowing crescent moon.
		local tail = newSculpt(U)
		local spine = {
			{ 0, 15, -13, 3.2 },
			{ 0, 14, -19, 2.6 },
			{ -1.5, 11.5, -25, 2 },
			{ -3.5, 9, -30, 1.5 },
			{ -4.8, 8, -34, 1 },
			{ -5, 8.8, -37, 0.6 },
		}
		tail:add(rod(spine), NIGHT)
		local moonCentre = { -5, 10.6, -39.6 }
		tail:add(
			shape(moonCentre, 3.2, function(x: number, y: number, z: number): boolean
				if math.abs(x - moonCentre[1]) > 0.7 then
					return false
				end
				local dy, dz = y - moonCentre[2], z - moonCentre[3]
				local ey, ez = dy - 1.1, dz + 1.1
				return dy * dy + dz * dz <= 2.9 * 2.9 and ey * ey + ez * ez > 2.3 * 2.3
			end),
			MOON
		)
		tail:coat(function(p, open)
			if p[3] < -36.5 then
				return nil
			end
			return scales(p, open, 20)
		end)
		mane(tail, { { 0, 0, -15 }, { 0, 0, -19 }, { -1, 0, -23 }, { -2.6, 0, -27 } }, 2.2)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", at({ 0, 15, -2 })), { head, front, frontMirror, back, backMirror, tail }, NIGHT)
		local headLimb = pet:limb("Head", at({ 0, 18, 7 }))
		head:draw(headLimb, { body }, NIGHT)
		-- Narrow glowing eyes, slanting up towards the back, in dark rims.
		slitEyes(headLimb, head, { 31.6, 20.3 }, { 32.5, 17 }, 0.95, MOON.color, NEON, CLAW.color)
		for _, tip in hornTips do
			headLimb:fire(at(tip), 2.5, MOONFIRE, MOONFIRE_CORE)
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", at({ 4.6, 15, 5 }), function(limb)
			front:draw(limb, { body }, NIGHT)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", at({ 4.8, 13.5, -10 }), function(limb)
			back:draw(limb, { body }, NIGHT)
		end)
		local tailLimb = pet:limb("Tail", at({ 0, 15, -13 }))
		tail:draw(tailLimb, { body }, NIGHT)
		tailLimb:fire(at({ -5, 12.4, -40.2 }), 3, MOONFIRE, MOONFIRE_CORE)

		-- Great wings of deep violet, sprinkled with stars and edged with moonlight, on silver bones.
		pet:limbPair("LeftWing", "RightWing", at({ 4, 19.5, 2 }), function(wing)
			local MEMBRANE, BONE = rgb(66, 52, 146), SILVER.color
			local FLAT = { 0, 0, 1 }
			local root = { 4, 19.5, 2 }
			local function grow(p: Vec): Vec
				return vadd(root, vscale(vsub(p, root), 1.15))
			end
			local elbow, wrist = grow({ 10, 27, 0 }), grow({ 14, 32.5, -3 })
			local tips = {
				grow({ 28, 30.5, -6 }),
				grow({ 25.5, 21.5, -8 }),
				grow({ 20, 15.5, -8.5 }),
				grow({ 13.5, 15, -7 }),
			}
			local scallops = { grow({ 23.5, 26, -7.2 }), grow({ 20.5, 19.5, -8.4 }), grow({ 16, 17, -8 }) }
			local flank, shoulder = { 5.5, 16.5, -5.5 }, { 4.5, 19, -2 }
			local function membrane(a: Vec, b: Vec, c: Vec)
				triangle(wing, at(a), at(b), at(c), 0.35 / U, MEMBRANE)
			end
			for i = 1, 3 do
				membrane(wrist, tips[i], scallops[i])
				membrane(wrist, scallops[i], tips[i + 1])
			end
			membrane(elbow, wrist, tips[4])
			membrane(elbow, tips[4], flank)
			membrane(elbow, flank, shoulder)
			-- Moonlight along the trailing edge, between the fingers.
			for i = 1, 3 do
				blade(wing, at(tips[i]), at(scallops[i]), 0.3 / U, 0.5 / U, FLAT, MOON.color, NEON)
				blade(wing, at(scallops[i]), at(tips[i + 1]), 0.3 / U, 0.5 / U, FLAT, MOON.color, NEON)
			end
			-- Stars scattered over the membranes.
			local stars = {
				{ wrist, tips[1], scallops[1], 0.45, 0.35 },
				{ wrist, scallops[1], tips[2], 0.5, 0.3 },
				{ wrist, tips[2], scallops[2], 0.35, 0.4 },
				{ wrist, scallops[2], tips[3], 0.55, 0.25 },
				{ wrist, tips[3], scallops[3], 0.3, 0.45 },
				{ elbow, wrist, tips[4], 0.3, 0.35 },
				{ elbow, tips[4], flank, 0.4, 0.3 },
				{ elbow, flank, shoulder, 0.3, 0.3 },
				{ wrist, tips[1], scallops[1], 0.15, 0.7 },
				{ wrist, scallops[2], tips[3], 0.2, 0.6 },
			}
			for index, star in stars do
				local a, b, c, u, v = star[1], star[2], star[3], star[4], star[5]
				local p = vadd(a, vadd(vscale(vsub(b, a), u), vscale(vsub(c, a), v)))
				local size = (if index % 3 == 0 then 0.8 else 0.6) / U
				egg(wing, at(p), { size, size, size }, nil, STAR.color, NEON)
			end
			blade(wing, at(root), at(elbow), 1.5 / U, 1.2 / U, FLAT, BONE)
			blade(wing, at(elbow), at(wrist), 1.25 / U, 1.05 / U, FLAT, BONE)
			for index, tip in tips do
				local mid = vlerp(wrist, tip, 0.7)
				blade(wing, at(wrist), at(mid), (0.9 - index * 0.08) / U, 0.8 / U, FLAT, BONE)
				taper(wing, at(mid), at(tip), 0.7 / U, 0.7 / U, FLAT, MOON.color, NEON)
			end
			taper(wing, at(wrist), at(grow({ 15, 35.5, -2 })), 0.8 / U, 0.7 / U, { 1, 0, 0 }, BONE)
			egg(wing, at(elbow), { 1.4 / U, 1.4 / U, 1.4 / U }, nil, MOON.color, NEON)
		end)

		pet:light(rgb(170, 200, 255), 3.4, 26)
		pet:particles("Sparkles", rgb(236, 242, 255), 18)
		pet:seat(0, 21 / U, -3 / U)
	end,
}

return Designs
