--!strict
-- The look of every pet, by name. Which egg each pet hatches from is set in Config/Zones (`pet`).
-- Each design draws limbs on the pet builder in PetModels:
--     x left (+x) and right (-x); y up from the ground; z forward. A cell numbered x covers x to x + 1.
--     limb:box() draws a solid block, limb:paint() colours the surface of blocks already drawn (eyes, bellies),
--     and the ...Pair versions mirror across the middle of the pet.
-- Pets have big heads and small bodies, like the eggs they come from, and are themed to match their egg.
-- Every pet in the game has a design, zone by zone: Forest, Desert, Snow, Ocean and Volcano.
-- Secret and Eternal pets are the showpieces, far more detailed than the rest (the tests check this).
-- Curved parts use the helpers below: `tube` (tentacles, coils, horns), `curl` (a spiral to end a tube on), and
-- `blob` (rounded bodies, filled from a shape function). The finest pets are sculpted (`newSculpt`): modelled cell
-- by cell from rounded shapes turned to any angle, then packed into blocks.

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

-- A shape squashed `factor` times thinner along z, round the plane z = z0: feathers, fins, blades.
local function flatten(s: Shape, z0: number, factor: number): Shape
	return {
		centre = s.centre,
		radius = s.radius,
		inside = function(x: number, y: number, z: number): boolean
			return s.inside(x, y, z0 + (z - z0) * factor)
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

-- `others` are the sculpts of the limbs that overlap this one: where they fill a cell too, it is hidden inside.
-- Hidden cells all take `inside` (by default the commonest look); limbs that overlap should share it.
function Sculpt.draw(self: Sculpt, limb: Limb, others: { Sculpt }?, inside: Look?)
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
			limb:box(b[1], b[2], b[3], b[4], b[5], b[6], look.color, look.material, look.transparency)
		end
	end
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
	scale = 0.5,
	draw = function(pet)
		local BROWN = rgb(140, 98, 62)
		local DARK = rgb(96, 64, 40)
		local LIGHT = rgb(222, 196, 152)
		local BEAK = rgb(242, 164, 44)
		local RING = rgb(255, 214, 70)

		-- A round, fluffy body: a soft chest with chevrons, speckles on its back.
		local body = pet:limb("Body", { 0, 2, 0 })
		body:box(-4, 2, -3, 3, 9, 3, BROWN)
		body:box(-3, 3, 4, 2, 8, 4, LIGHT)
		body:paintPair(1, 6, 4, 1, 6, 4, DARK)
		body:paintPair(2, 4, 4, 2, 4, 4, DARK)
		body:paint(-1, 4, 4, 0, 4, 4, DARK)
		body:paint(-1, 7, 4, 0, 7, 4, DARK)
		body:paint(-3, 8, -3, -3, 8, -3, LIGHT)
		body:paint(2, 6, -3, 2, 6, -3, LIGHT)
		body:paint(-1, 4, -3, 0, 4, -3, LIGHT)
		body:paint(1, 8, -3, 1, 8, -3, LIGHT)
		body:paint(-3, 3, -3, -3, 3, -3, LIGHT)
		body:paint(-4, 2, -3, 3, 2, 3, LIGHT)

		-- A big round head: pale face disc with a dark rim, frowning brows, huge eyes, a hooked beak, tall tufts.
		local head = pet:limb("Head", { 0, 10, 0 })
		head:box(-4, 10, -3, 3, 15, 3, BROWN)
		head:box(-3, 16, -2, 2, 16, 2, BROWN)
		head:paint(-4, 10, 3, 3, 14, 3, LIGHT)
		head:paint(-4, 10, 3, -4, 14, 3, DARK)
		head:paint(3, 10, 3, 3, 14, 3, DARK)
		head:paintPair(1, 12, 3, 2, 13, 3, RING)
		head:paintPair(1, 12, 3, 1, 13, 3, EYE)
		head:paintPair(1, 13, 3, 1, 13, 3, SHINE)
		head:boxPair(1, 14, 4, 2, 14, 4, DARK)
		head:boxPair(3, 15, 4, 3, 15, 4, DARK)
		head:box(-1, 11, 4, 0, 12, 4, BEAK)
		head:box(-1, 10, 5, 0, 11, 5, BEAK)
		head:boxPair(2, 16, -1, 3, 17, 0, BROWN)
		head:boxPair(3, 18, -1, 4, 18, 0, DARK)
		head:boxPair(4, 19, -1, 4, 19, 0, DARK)
		head:paint(-2, 16, -2, -2, 16, -2, LIGHT)
		head:paint(1, 16, 1, 1, 16, 1, LIGHT)
		head:paint(-3, 14, -3, -3, 14, -3, LIGHT)
		head:paint(2, 12, -3, 2, 12, -3, LIGHT)

		-- Layered wings: soft coverts, barred flight feathers and dark tips.
		pet:limbPair("LeftWing", "RightWing", { 4.5, 9, 0 }, function(wing)
			wing:box(4, 6, -2, 5, 9, 2, BROWN)
			wing:box(4, 2, -3, 4, 5, 1, DARK)
			wing:box(4, 1, -4, 4, 2, -3, DARK)
			wing:paint(4, 7, -2, 5, 7, 2, LIGHT)
			wing:paint(4, 4, -3, 4, 4, 1, LIGHT)
			wing:paint(4, 2, -3, 4, 2, 1, LIGHT)
		end)
		-- Fluffy legs and orange talons.
		pet:limbPair("LeftLeg", "RightLeg", { 2, 2, 1 }, function(leg)
			leg:box(1, 1, 0, 2, 1, 1, LIGHT)
			leg:box(1, 0, 0, 2, 0, 2, BEAK)
			leg:paint(1, 0, 2, 2, 0, 2, DARK)
		end)

		-- A fan of tail feathers.
		local tail = pet:limb("Tail", { 0, 3, -3 })
		tail:box(-2, 2, -4, 1, 4, -4, DARK)
		tail:box(-3, 1, -5, 2, 2, -5, DARK)
		tail:paint(-3, 1, -5, 2, 1, -5, LIGHT)

		pet:seat(0, 17, -1)
	end,
}

Designs.Bear = {
	name = "Bear",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local BROWN = rgb(142, 94, 58)
		local TAN = rgb(218, 174, 124)
		local NOSE = rgb(44, 32, 28)
		local HONEY = rgb(255, 188, 48)

		local body = pet:limb("Body", { 0, 6, 0 })
		body:box(-5, 3, -5, 4, 10, 4, BROWN)
		body:paint(-3, 3, 4, 2, 8, 4, TAN)

		local head = pet:limb("Head", { 0, 10, 4 })
		head:box(-4, 9, 4, 3, 15, 10, BROWN)
		head:box(-2, 9, 11, 1, 11, 12, TAN)
		head:paint(-1, 11, 12, 0, 11, 12, NOSE)
		head:paint(-1, 11, 11, 0, 11, 11, rgb(116, 76, 46))
		eyes(head, 1, 12, 10, 1)
		-- Round ears, light inside.
		head:boxPair(2, 16, 6, 4, 17, 7, BROWN)
		head:paintPair(3, 16, 7, 3, 16, 7, TAN)
		-- Honey dripping down its head, like on its egg.
		head:paint(-3, 15, 5, 1, 15, 9, HONEY)
		head:paint(-1, 14, 10, -1, 15, 10, HONEY)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 4, 2 }, function(leg)
			leg:box(2, 0, 1, 4, 3, 3, BROWN)
			leg:paint(2, 0, 3, 4, 0, 3, TAN)
			leg:box(2, 0, 4, 4, 0, 4, NOSE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 4, -4 }, function(leg)
			leg:box(2, 0, -5, 4, 3, -3, BROWN)
		end)

		local tail = pet:limb("Tail", { 0, 8, -5 })
		tail:box(-1, 8, -6, 0, 9, -6, BROWN)

		pet:seat(0, 11, -1)
	end,
}

Designs.MossStag = {
	name = "Moss Stag",
	skeleton = "Quadruped",
	scale = 0.55,
	draw = function(pet)
		local DEER = rgb(152, 106, 68)
		local DEER_DARK = rgb(116, 78, 48)
		local LIGHT = rgb(232, 206, 162)
		local MOSS = rgb(86, 146, 66)
		local MOSS_LIGHT = rgb(140, 196, 96)
		local VINE = rgb(70, 128, 58)
		local WOOD = rgb(168, 126, 82)
		local HOOF = rgb(64, 46, 34)
		local CAP = rgb(214, 54, 50)
		local SPOT = rgb(250, 240, 226)
		local PINK = rgb(255, 150, 196)
		local YELLOW = rgb(255, 220, 80)

		-- A deer's body: deep chest, slimmer middle, rounded rump, pale belly and a few fawn spots.
		local body = pet:limb("Body", { 0, 9, 0 })
		body:box(-4, 7, 1, 3, 12, 5, DEER)
		body:box(-3, 7, -5, 2, 11, 0, DEER)
		body:box(-4, 7, -8, 3, 12, -6, DEER)
		body:paint(-3, 7, -5, 2, 7, 0, LIGHT)
		body:paint(-2, 8, 5, 1, 11, 5, LIGHT)
		body:paintPair(3, 10, -8, 3, 10, -8, SPOT)
		body:paintPair(3, 11, -7, 3, 11, -7, SPOT)
		body:paintPair(2, 9, -3, 2, 9, -3, SPOT)
		-- A blanket of moss over its back, hanging in uneven drips, with mushrooms, blossoms and a trailing vine.
		body:box(-5, 12, -7, 4, 13, 4, MOSS)
		body:boxPair(4, 10, -4, 4, 11, 3, MOSS)
		body:boxPair(4, 9, -4, 4, 9, -3, MOSS)
		body:boxPair(4, 8, 0, 4, 9, 0, MOSS)
		body:boxPair(4, 9, 2, 4, 9, 2, MOSS)
		body:boxPair(4, 6, -3, 4, 8, -3, VINE)
		body:paint(-3, 13, -5, -1, 13, -3, MOSS_LIGHT)
		body:paint(0, 13, 0, 2, 13, 3, MOSS_LIGHT)
		body:paintPair(4, 11, -2, 4, 11, 0, MOSS_LIGHT)
		body:box(2, 14, -5, 3, 14, -4, CAP)
		body:paint(2, 14, -5, 2, 14, -5, SPOT)
		body:box(-4, 14, 2, -4, 14, 2, CAP)
		body:box(-2, 14, -1, -2, 14, -1, PINK, NEON)
		body:box(1, 14, 2, 1, 14, 2, YELLOW, NEON)
		body:box(-4, 14, -6, -4, 14, -6, PINK, NEON)

		-- A strong neck with a pale throat, a soft muzzle, and great branching antlers in bloom.
		local head = pet:limb("Head", { 0, 12, 5 })
		head:box(-2, 11, 5, 1, 15, 7, DEER)
		head:paint(-1, 11, 7, 0, 14, 7, LIGHT)
		head:box(-3, 15, 5, 2, 19, 10, DEER)
		head:box(-2, 15, 11, 1, 17, 12, LIGHT)
		head:box(-1, 16, 13, 0, 17, 13, HOOF)
		head:paint(-2, 18, 10, 1, 19, 10, DEER_DARK)
		eyes(head, 1, 17, 10, 1)
		head:boxPair(3, 18, 7, 4, 19, 8, DEER)
		head:paintPair(3, 18, 8, 4, 18, 8, LIGHT)
		head:paint(-2, 19, 6, 1, 19, 9, MOSS)
		head:boxPair(1, 20, 7, 1, 21, 7, WOOD)
		head:boxPair(2, 22, 7, 3, 22, 7, WOOD)
		head:boxPair(4, 23, 7, 4, 25, 7, WOOD)
		head:boxPair(5, 26, 7, 5, 27, 7, WOOD)
		head:boxPair(2, 23, 8, 2, 24, 9, WOOD)
		head:boxPair(3, 24, 6, 3, 26, 6, WOOD)
		head:boxPair(6, 25, 7, 7, 25, 7, WOOD)
		head:paintPair(4, 23, 7, 4, 24, 7, MOSS_LIGHT)
		head:paintPair(2, 22, 7, 2, 22, 7, MOSS)
		head:boxPair(5, 28, 7, 5, 28, 7, PINK, NEON)
		head:boxPair(3, 27, 6, 3, 27, 6, YELLOW, NEON)
		head:boxPair(2, 25, 9, 2, 25, 9, PINK, NEON)
		head:boxPair(8, 25, 7, 8, 25, 7, YELLOW, NEON)
		head:boxPair(7, 22, 7, 7, 24, 7, VINE)

		-- Long legs with knees, pale cuffs and dark hooves.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 8, 3.5 }, function(leg)
			leg:box(2, 4, 3, 3, 7, 4, DEER)
			leg:box(2, 0, 3, 3, 3, 4, DEER)
			leg:paint(2, 4, 4, 3, 4, 4, DEER_DARK)
			leg:paint(2, 1, 3, 3, 1, 4, LIGHT)
			leg:paint(2, 0, 3, 3, 0, 4, HOOF)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 8, -6.5 }, function(leg)
			leg:box(3, 6, -8, 4, 10, -5, DEER)
			leg:box(2, 0, -7, 3, 5, -6, DEER)
			leg:paint(2, 1, -7, 3, 1, -6, LIGHT)
			leg:paint(2, 0, -7, 3, 0, -6, HOOF)
		end)

		-- A white flag of a tail.
		local tail = pet:limb("Tail", { 0, 11, -8 })
		tail:box(-1, 10, -9, 0, 12, -9, LIGHT)
		tail:paint(-1, 12, -9, 0, 12, -9, DEER)

		pet:seat(0, 14, -1)
	end,
}

Designs.Treant = {
	name = "Treant",
	skeleton = "Biped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local BARK = rgb(112, 78, 48)
		local BARK_DARK = rgb(78, 52, 32)
		local HOLLOW = rgb(36, 24, 16)
		local LEAF = rgb(132, 202, 92)
		local LEAF_DARK = rgb(74, 140, 60)
		local MOSS = rgb(96, 156, 70)
		local VINE = rgb(70, 128, 58)
		local SAP = rgb(196, 255, 110)
		local PINK = rgb(255, 150, 196)
		local CAP = rgb(214, 54, 50)
		local SPOT = rgb(250, 240, 226)

		-- A hunched trunk: narrow at the hips, broad at the shoulders.
		local body = pet:limb("Body", { 0, 6, 0 })
		body:box(-4, 6, -3, 3, 11, 3, BARK)
		body:box(-5, 12, -4, 4, 18, 3, BARK)
		-- A heavy brow over glowing slit eyes, and a hollow mouth glowing deep inside.
		body:box(-4, 16, 4, 3, 16, 4, BARK_DARK)
		body:paintPair(1, 15, 3, 2, 15, 3, SAP, NEON)
		body:paint(-2, 12, 3, 1, 13, 3, HOLLOW)
		body:paint(-1, 12, 3, 0, 12, 3, SAP, NEON)
		-- Glowing sap showing through jagged cracks in the bark.
		body:paint(-3, 10, 3, -3, 11, 3, SAP, NEON)
		body:paint(-2, 8, 3, -2, 9, 3, SAP, NEON)
		body:paint(-3, 7, 3, -3, 7, 3, SAP, NEON)
		body:paint(2, 9, 3, 2, 10, 3, SAP, NEON)
		body:paint(1, 7, 3, 1, 8, 3, SAP, NEON)
		body:paint(2, 6, 3, 2, 6, 3, SAP, NEON)
		body:paint(4, 16, -2, 4, 17, -2, SAP, NEON)
		body:paint(4, 14, -1, 4, 15, -1, SAP, NEON)
		body:paint(4, 13, -2, 4, 13, -2, SAP, NEON)
		body:paint(-1, 9, -3, -1, 11, -3, SAP, NEON)
		body:paint(0, 12, -4, 0, 13, -4, SAP, NEON)
		body:paint(-1, 14, -4, -1, 15, -4, SAP, NEON)
		-- Bark grooves and moss on its shoulders.
		body:paint(1, 6, -3, 1, 11, -3, BARK_DARK)
		body:paint(2, 12, -4, 2, 18, -4, BARK_DARK)
		body:paint(-5, 12, 0, -5, 18, 0, BARK_DARK)
		body:paint(-5, 18, -4, -2, 18, -1, MOSS)
		body:paint(2, 18, 0, 4, 18, 3, MOSS)
		-- Red mushrooms growing out of one side, a snapped-off branch on the other.
		body:box(-7, 13, -4, -6, 13, -2, CAP)
		body:paint(-7, 13, -3, -7, 13, -3, SPOT)
		body:box(-6, 9, 0, -5, 9, 1, CAP)
		body:box(4, 8, -1, 5, 9, -1, BARK_DARK)

		-- A big crown of leaves with branches poking through, blossoms, and glowing fruit hanging underneath.
		local head = pet:limb("Head", { 0, 19, 0 })
		head:box(-6, 19, -5, 5, 21, 4, LEAF)
		head:box(-5, 22, -4, 4, 23, 3, LEAF)
		head:box(-3, 24, -3, 2, 24, 2, LEAF)
		head:box(-7, 20, -2, -7, 21, 1, LEAF)
		head:box(6, 19, -3, 6, 20, 0, LEAF)
		head:box(-2, 20, 5, 1, 22, 5, LEAF)
		head:paint(-6, 19, -5, -3, 20, -3, LEAF_DARK)
		head:paint(2, 21, 1, 5, 21, 4, LEAF_DARK)
		head:paint(-5, 23, 0, -3, 23, 3, LEAF_DARK)
		head:paint(1, 24, -3, 2, 24, -1, LEAF_DARK)
		head:box(-4, 25, -1, -3, 26, 0, BARK)
		head:box(-5, 27, -1, -5, 27, 0, BARK)
		head:box(-7, 28, -2, -5, 29, 1, LEAF)
		head:paint(-7, 28, -2, -6, 28, 1, LEAF_DARK)
		head:box(2, 25, -3, 3, 26, -2, BARK)
		head:box(4, 27, -3, 4, 27, -2, BARK)
		head:box(4, 28, -4, 6, 29, -1, LEAF)
		head:paint(5, 28, -4, 6, 28, -1, LEAF_DARK)
		head:paint(5, 20, -2, 5, 20, -2, PINK)
		head:paint(-4, 23, 3, -4, 23, 3, PINK)
		head:paint(0, 24, 2, 0, 24, 2, PINK)
		head:paint(-7, 21, 0, -7, 21, 0, PINK)
		head:paint(1, 22, 5, 1, 22, 5, PINK)
		head:box(-6, 18, 3, -6, 18, 3, SAP, NEON)
		head:box(5, 17, 2, 5, 18, 2, SAP, NEON)
		head:box(-2, 18, -5, -2, 18, -5, SAP, NEON)

		-- Long branch arms reaching down, with twig claws, a tuft of leaves and a hanging vine.
		pet:limbPair("LeftArm", "RightArm", { 5.5, 17, 0 }, function(arm)
			arm:box(5, 15, -1, 6, 17, 1, BARK)
			arm:box(6, 11, -1, 7, 15, 0, BARK)
			arm:box(6, 8, 0, 7, 10, 1, BARK)
			arm:box(6, 6, 2, 6, 7, 2, BARK_DARK)
			arm:box(7, 6, 0, 7, 7, 0, BARK_DARK)
			arm:box(5, 6, 1, 5, 7, 1, BARK_DARK)
			arm:box(5, 18, -1, 7, 18, 1, LEAF)
			arm:box(7, 12, 1, 7, 14, 1, VINE)
			arm:paint(6, 13, -1, 7, 14, -1, MOSS)
		end)
		-- Thick legs on spreading roots.
		pet:limbPair("LeftLeg", "RightLeg", { 2.5, 6, 0 }, function(leg)
			leg:box(1, 2, -2, 3, 6, 1, BARK)
			leg:box(0, 0, -3, 4, 1, 2, BARK_DARK)
			leg:box(1, 0, 3, 1, 0, 4, BARK_DARK)
			leg:box(3, 0, 3, 3, 0, 4, BARK_DARK)
			leg:box(5, 0, -1, 5, 0, 0, BARK_DARK)
			leg:box(1, 0, -4, 1, 0, -4, BARK_DARK)
			leg:paint(0, 1, -3, 2, 1, -1, MOSS)
		end)

		pet:light(SAP, 2, 14)
		pet:particles("Sparkles", SAP, 8)
		pet:seat(0, 25, -1)
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
	scale = 0.55,
	draw = function(pet)
		local AMBER = rgb(176, 98, 44)
		local DARK = rgb(112, 58, 28)
		local LIGHT = rgb(214, 140, 70)
		local VENOM = rgb(150, 255, 90)

		-- A low body of overlapping plates, with a keel down the middle and pale spots.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 2, -5, 3, 4, 4, AMBER)
		body:box(-3, 5, -5, 2, 5, -4, AMBER)
		body:box(-3, 5, -2, 2, 5, -1, AMBER)
		body:box(-3, 5, 1, 2, 5, 3, AMBER)
		body:paint(-4, 4, -3, 3, 4, -3, DARK)
		body:paint(-4, 4, 0, 3, 4, 0, DARK)
		body:paint(-1, 5, -5, 0, 5, -4, LIGHT)
		body:paint(-1, 5, -2, 0, 5, -1, LIGHT)
		body:paint(-1, 5, 1, 0, 5, 3, LIGHT)
		body:paintPair(3, 2, -5, 3, 2, 4, DARK)
		body:paintPair(2, 5, -5, 2, 5, -5, LIGHT)
		body:paintPair(2, 5, 2, 2, 5, 2, LIGHT)

		-- A head with a mound of eyes, little fangs, and huge pincers with toothed edges.
		local head = pet:limb("Head", { 0, 3, 5 })
		head:box(-3, 2, 5, 2, 4, 6, AMBER)
		head:box(-1, 5, 5, 0, 5, 6, DARK)
		head:paint(-1, 5, 6, 0, 5, 6, VENOM, NEON)
		eyes(head, 1, 3, 6, 1)
		head:boxPair(0, 2, 7, 0, 3, 7, DARK)
		head:boxPair(3, 3, 5, 4, 3, 7, AMBER)
		head:boxPair(4, 3, 8, 5, 3, 9, AMBER)
		head:boxPair(3, 2, 10, 6, 4, 12, AMBER)
		head:boxPair(5, 3, 13, 6, 4, 15, AMBER)
		head:boxPair(3, 2, 13, 3, 3, 15, DARK)
		head:paintPair(5, 3, 13, 5, 3, 15, LIGHT)
		head:paintPair(5, 4, 15, 6, 4, 15, DARK)
		head:paintPair(4, 4, 10, 5, 4, 11, LIGHT)

		-- Six legs, each bent at a dark joint.
		local function leg(z: number)
			return function(limb)
				limb:box(4, 3, z, 5, 4, z, AMBER)
				limb:box(6, 4, z, 6, 4, z, DARK)
				limb:box(7, 1, z, 7, 3, z, AMBER)
				limb:box(7, 0, z, 8, 0, z, DARK)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 4, 3.5, 3.5 }, leg(3))
		pet:limbPair("MiddleLeftLeg", "MiddleRightLeg", { 4, 3.5, 0.5 }, leg(0))
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 4, 3.5, -2.5 }, leg(-3))

		-- A tail of shrinking segments arching over its back, with a venom bulb and a dripping stinger.
		local tail = pet:limb("Tail", { 0, 4, -5 })
		tail:box(-2, 3, -7, 1, 5, -6, AMBER)
		tail:box(-1, 6, -8, 0, 8, -7, AMBER)
		tail:box(-1, 9, -8, 0, 10, -7, AMBER)
		tail:box(-1, 11, -7, 0, 12, -6, AMBER)
		tail:box(-1, 13, -6, 0, 13, -4, AMBER)
		tail:box(-1, 13, -3, 0, 13, -2, DARK)
		tail:paint(-2, 5, -7, 1, 5, -7, DARK)
		tail:paint(-1, 8, -8, 0, 8, -8, DARK)
		tail:paint(-1, 10, -8, 0, 10, -8, DARK)
		tail:paint(-1, 12, -7, 0, 12, -7, DARK)
		tail:box(-1, 11, -1, 0, 13, 0, LIGHT)
		tail:box(-1, 9, 1, 0, 10, 1, VENOM, NEON)
		tail:box(-1, 8, 2, 0, 8, 2, VENOM, NEON)
		tail:box(-1, 6, 2, -1, 7, 2, VENOM, NEON)

		pet:seat(0, 6, 0)
	end,
}

Designs.PharaohJackal = {
	name = "Pharaoh Jackal",
	skeleton = "Quadruped",
	scale = 0.55,
	draw = function(pet)
		local BLACK = rgb(38, 34, 42)
		local SHEEN = rgb(66, 60, 76)
		local GOLD = rgb(255, 196, 56)
		local LAPIS = rgb(40, 86, 196)
		local TEAL = rgb(56, 180, 176)
		local RED = rgb(196, 48, 52)

		-- A sleek black body: deep chest, slim waist, a gold-and-lapis sash.
		local body = pet:limb("Body", { 0, 7, 0 })
		body:box(-3, 6, 1, 2, 10, 4, BLACK)
		body:box(-2, 6, -4, 1, 9, 0, BLACK)
		body:box(-3, 6, -7, 2, 10, -5, BLACK)
		body:paintPair(2, 8, -7, 2, 9, -6, SHEEN)
		body:paint(-1, 10, -7, 0, 10, -5, SHEEN)
		body:box(-3, 7, -3, 2, 10, -2, GOLD)
		body:paint(-3, 8, -3, 2, 8, -2, LAPIS)
		-- A broad collar in gold, teal and lapis, with an ankh hanging from it.
		body:box(-4, 9, 2, 3, 11, 5, GOLD)
		body:paint(-4, 10, 2, 3, 10, 5, TEAL)
		body:paint(-4, 9, 2, 3, 9, 5, LAPIS)
		body:box(-1, 9, 6, 0, 10, 6, GOLD)
		body:box(-2, 8, 6, 1, 8, 6, GOLD)
		body:box(-1, 6, 6, 0, 7, 6, GOLD)

		-- A long muzzle, glowing gold eyes lined in kohl, a striped headdress and tall ears.
		local head = pet:limb("Head", { 0, 11, 4 })
		head:box(-2, 12, 3, 1, 12, 5, BLACK)
		head:box(-2, 13, 3, 1, 16, 7, BLACK)
		head:box(-1, 13, 8, 0, 14, 11, BLACK)
		head:paint(-1, 13, 9, 0, 13, 11, SHEEN)
		head:box(-1, 14, 12, 0, 14, 12, SHEEN)
		head:paintPair(1, 15, 7, 1, 15, 7, GOLD, NEON)
		head:paintPair(1, 15, 5, 1, 15, 6, GOLD)
		head:box(-3, 17, 2, 2, 18, 7, GOLD)
		head:paint(-3, 18, 2, 2, 18, 2, LAPIS)
		head:paint(-3, 18, 4, 2, 18, 4, LAPIS)
		head:paint(-3, 18, 6, 2, 18, 6, LAPIS)
		head:paintPair(2, 17, 2, 2, 17, 7, LAPIS)
		head:paint(-1, 17, 7, 0, 17, 7, RED)
		head:boxPair(2, 12, 2, 2, 16, 3, GOLD)
		head:paintPair(2, 13, 2, 2, 13, 3, LAPIS)
		head:paintPair(2, 15, 2, 2, 15, 3, LAPIS)
		head:box(-2, 12, 1, 1, 16, 1, GOLD)
		head:paint(-2, 13, 1, 1, 13, 1, LAPIS)
		head:paint(-2, 15, 1, 1, 15, 1, LAPIS)
		head:boxPair(1, 19, 4, 2, 21, 5, BLACK)
		head:boxPair(2, 22, 4, 2, 23, 5, BLACK)
		head:paintPair(1, 19, 5, 1, 21, 5, GOLD)

		-- Slender legs with gold armbands.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 7, 2.5 }, function(leg)
			leg:box(1, 1, 2, 2, 5, 3, BLACK)
			leg:box(1, 0, 2, 2, 0, 4, BLACK)
			leg:paint(1, 4, 2, 2, 4, 3, GOLD)
			leg:paint(1, 1, 2, 2, 1, 3, LAPIS)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2, 7, -6 }, function(leg)
			leg:box(1, 3, -7, 2, 6, -5, BLACK)
			leg:box(1, 0, -7, 2, 2, -6, BLACK)
			leg:box(1, 0, -5, 2, 0, -5, BLACK)
			leg:paint(1, 1, -7, 2, 1, -6, GOLD)
		end)

		-- A long tail with gold rings.
		local tail = pet:limb("Tail", { 0, 9, -7 })
		tail:box(-1, 8, -9, 0, 9, -8, BLACK)
		tail:box(-1, 6, -10, 0, 8, -10, BLACK)
		tail:box(-1, 3, -11, 0, 6, -11, BLACK)
		tail:paint(-1, 7, -10, 0, 7, -10, GOLD)
		tail:paint(-1, 4, -11, 0, 4, -11, GOLD)

		pet:seat(0, 11, -2)
	end,
}

Designs.Sphinx = {
	name = "Sphinx",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local STONE = rgb(226, 192, 124)
		local STONE_LIGHT = rgb(242, 216, 164)
		local STONE_DARK = rgb(184, 148, 88)
		local CARVING = rgb(146, 112, 62)
		local GOLD = rgb(255, 196, 56)
		local LAPIS = rgb(40, 86, 196)
		local TEAL = rgb(56, 180, 176)

		-- A stone lion: deep chest, narrow waist, strong haunches, a ridge down its spine.
		local body = pet:limb("Body", { 0, 7, 0 })
		body:box(-4, 6, 1, 3, 12, 5, STONE)
		body:box(-3, 6, -5, 2, 10, 0, STONE)
		body:box(-4, 6, -8, 3, 11, -6, STONE)
		body:box(-1, 11, -5, 0, 11, 0, STONE_LIGHT)
		body:paint(-3, 6, -5, 2, 6, 0, STONE_DARK)
		-- Carved marks along its flanks, and lighter muscle on its haunches.
		body:paintPair(2, 8, -4, 2, 9, -4, CARVING)
		body:paintPair(2, 9, -2, 2, 9, -1, CARVING)
		body:paintPair(2, 7, -2, 2, 7, -2, CARVING)
		body:paintPair(3, 9, -8, 3, 10, -7, STONE_LIGHT)
		-- A broad jewelled collar with an amulet.
		body:box(-5, 9, 2, 4, 11, 6, GOLD)
		body:paint(-5, 10, 2, 4, 10, 6, TEAL)
		body:paint(-5, 9, 2, 4, 9, 6, LAPIS)
		body:box(-1, 8, 7, 0, 9, 7, GOLD)
		body:box(-1, 8, 8, 0, 8, 8, TEAL, NEON)
		-- Great feathered wings rising from its shoulders, banded gold and lapis.
		body:boxPair(4, 10, -1, 5, 12, 1, STONE)
		body:boxPair(5, 17, -3, 5, 17, 0, GOLD)
		body:boxPair(5, 16, -5, 5, 16, 1, LAPIS)
		body:boxPair(5, 15, -7, 5, 15, 1, GOLD)
		body:boxPair(5, 14, -8, 5, 14, 0, STONE_LIGHT)
		body:boxPair(5, 13, -9, 5, 13, -1, STONE_LIGHT)
		body:boxPair(5, 12, -9, 5, 12, -3, STONE_LIGHT)
		body:boxPair(5, 11, -8, 5, 11, -5, STONE_LIGHT)
		body:paintPair(5, 11, -7, 5, 14, -7, STONE_DARK)
		body:paintPair(5, 12, -4, 5, 14, -4, STONE_DARK)
		body:paintPair(5, 13, -9, 5, 13, -9, TEAL)
		body:paintPair(5, 12, -9, 5, 12, -9, TEAL)

		-- A calm face with glowing eyes, framed by a striped headdress, a rearing cobra and a gold beard.
		local head = pet:limb("Head", { 0, 12, 5 })
		head:box(-2, 11, 5, 1, 12, 5, STONE)
		head:box(-3, 13, 5, 2, 18, 9, STONE)
		head:box(-1, 13, 10, 0, 15, 10, STONE)
		head:paint(-1, 15, 10, 0, 15, 10, STONE_DARK)
		head:paint(-1, 13, 10, 0, 13, 10, CARVING)
		head:paintPair(2, 16, 9, 2, 16, 9, LAPIS)
		head:paintPair(1, 16, 9, 1, 16, 9, TEAL, NEON)
		head:box(-4, 18, 4, 3, 19, 10, GOLD)
		head:paint(-4, 19, 4, 3, 19, 4, LAPIS)
		head:paint(-4, 19, 6, 3, 19, 6, LAPIS)
		head:paint(-4, 19, 8, 3, 19, 8, LAPIS)
		head:boxPair(3, 11, 6, 3, 17, 8, GOLD)
		head:boxPair(3, 10, 6, 4, 10, 8, GOLD)
		head:paintPair(3, 12, 6, 3, 12, 8, LAPIS)
		head:paintPair(3, 15, 6, 3, 15, 8, LAPIS)
		head:box(-3, 13, 4, 2, 18, 4, GOLD)
		head:paint(-3, 14, 4, 2, 14, 4, LAPIS)
		head:paint(-3, 16, 4, 2, 16, 4, LAPIS)
		head:box(-1, 19, 10, 0, 20, 10, GOLD)
		head:box(-1, 21, 10, 0, 21, 11, GOLD)
		head:box(-1, 20, 11, 0, 20, 11, TEAL, NEON)
		head:box(-1, 10, 9, 0, 12, 9, GOLD)
		head:paint(-1, 11, 9, 0, 11, 9, LAPIS)
		head:box(-1, 10, 10, 0, 10, 10, GOLD)

		-- Lion legs with big paws, gold bands on the front ones.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 7, 3 }, function(leg)
			leg:box(2, 3, 2, 3, 7, 4, STONE)
			leg:box(2, 0, 3, 3, 2, 4, STONE)
			leg:box(2, 0, 5, 4, 1, 6, STONE)
			leg:paint(3, 1, 5, 3, 1, 6, STONE_DARK)
			leg:paint(2, 0, 6, 4, 0, 6, CARVING)
			leg:paint(2, 5, 2, 3, 5, 4, GOLD)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 7, -6 }, function(leg)
			leg:box(3, 3, -8, 4, 9, -5, STONE)
			leg:box(2, 0, -7, 3, 2, -6, STONE)
			leg:box(2, 0, -5, 3, 0, -4, STONE)
			leg:paint(2, 0, -4, 3, 0, -4, CARVING)
		end)

		-- A lion's tail curling up over its rump, with a gold band and a dark tuft.
		local tail = pet:limb("Tail", { 0, 9, -8 })
		tail:box(-1, 8, -10, 0, 9, -9, STONE)
		tail:box(-1, 10, -11, 0, 12, -11, STONE)
		tail:box(-1, 13, -11, 0, 13, -10, STONE)
		tail:box(-2, 13, -9, 1, 15, -8, STONE_DARK)
		tail:paint(-1, 10, -11, 0, 10, -11, GOLD)

		pet:light(GOLD, 2, 14)
		pet:particles("Sparkles", GOLD, 6)
		pet:seat(0, 12, -3)
	end,
}

Designs.GoldenScarab = {
	name = "Golden Scarab",
	skeleton = "ManyLegged",
	scale = 0.6,
	draw = function(pet)
		local SCARAB = rgb(240, 186, 50)
		local GOLD_LIGHT = rgb(255, 224, 120)
		local BRONZE = rgb(196, 128, 38)
		local BRONZE_DARK = rgb(120, 76, 24)
		local TEAL = rgb(56, 180, 176)
		local LAPIS = rgb(40, 86, 196)
		local SEAM = rgb(86, 56, 20)
		local SUN = rgb(255, 196, 60)
		local SUN_CORE = rgb(255, 240, 170)

		-- A rounded golden shell, split down the middle, inlaid with teal and lapis bands.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 2, -6, 3, 5, 2, SCARAB)
		body:box(-5, 3, -5, 4, 4, 1, SCARAB)
		body:box(-3, 6, -5, 2, 6, 1, SCARAB)
		body:box(-2, 7, -4, 1, 7, 0, SCARAB)
		body:box(-3, 3, -7, 2, 5, -7, SCARAB)
		body:box(-1, 8, -4, 0, 8, 0, BRONZE)
		body:paint(-1, 2, -7, 0, 5, -7, SEAM)
		for _, band in { { -3, TEAL }, { -1, LAPIS } } do
			local z, color = band[1], band[2]
			body:paint(-5, 3, z, 4, 4, z, color)
			body:paint(-4, 5, z, 3, 5, z, color)
			body:paint(-3, 6, z, 2, 6, z, color)
		end
		body:paint(-2, 7, -4, -2, 7, -4, GOLD_LIGHT)
		body:paint(1, 7, -2, 1, 7, -2, GOLD_LIGHT)
		-- A bronze plate behind its head, rimmed in pale gold.
		body:box(-4, 2, 3, 3, 5, 5, BRONZE)
		body:box(-3, 6, 3, 2, 6, 4, BRONZE)
		body:paint(-4, 5, 5, 3, 5, 5, GOLD_LIGHT)
		-- Jewelled wings spread out from under its shell, like on a temple wall.
		body:boxPair(5, 4, -4, 7, 4, 1, SCARAB)
		body:boxPair(8, 4, -6, 9, 4, 0, LAPIS)
		body:boxPair(10, 4, -6, 10, 4, -2, TEAL)
		body:boxPair(11, 4, -5, 11, 4, -3, TEAL)
		body:boxPair(8, 5, -5, 10, 5, -3, GOLD_LIGHT)
		body:paintPair(8, 4, -3, 9, 4, -3, SCARAB)
		body:paintPair(10, 4, -6, 11, 4, -6, SCARAB)

		-- A shovel head with a toothed edge, clubbed feelers, and a horn holding up a blazing sun.
		local head = pet:limb("Head", { 0, 3, 6 })
		head:box(-3, 2, 6, 2, 4, 7, BRONZE_DARK)
		head:box(-3, 2, 8, 2, 2, 8, BRONZE)
		head:boxPair(2, 2, 9, 2, 2, 9, BRONZE)
		head:boxPair(0, 2, 9, 0, 2, 9, BRONZE)
		eyes(head, 2, 3, 7, 1, 1)
		head:boxPair(2, 5, 7, 2, 5, 7, BRONZE_DARK)
		head:boxPair(3, 6, 7, 3, 6, 7, BRONZE_DARK)
		head:boxPair(3, 6, 8, 3, 7, 8, GOLD_LIGHT)
		head:box(-1, 5, 6, 0, 8, 6, BRONZE_DARK)
		head:box(-1, 9, 6, 0, 9, 7, SUN, NEON)
		head:box(-2, 10, 6, 1, 10, 7, SUN, NEON)
		head:box(-3, 11, 6, 2, 12, 7, SUN, NEON)
		head:box(-2, 13, 6, 1, 13, 7, SUN, NEON)
		head:box(-1, 14, 6, 0, 14, 7, SUN, NEON)
		head:paint(-2, 11, 7, 1, 12, 7, SUN_CORE, NEON)
		head:paint(-1, 10, 7, 0, 13, 7, SUN_CORE, NEON)
		head:boxPair(3, 11, 6, 4, 12, 6, SUN, NEON)
		head:box(-1, 15, 6, 0, 16, 6, SUN, NEON)
		head:boxPair(2, 14, 6, 2, 14, 6, SUN, NEON)

		-- Six spiny legs; the front pair are toothed for digging.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 4, 3, 4.5 }, function(leg)
			leg:box(4, 2, 4, 5, 3, 4, BRONZE_DARK)
			leg:box(6, 0, 5, 6, 3, 5, BRONZE_DARK)
			leg:box(7, 1, 5, 7, 1, 5, BRONZE)
			leg:box(7, 3, 5, 7, 3, 5, BRONZE)
		end)
		local function leg(z: number)
			return function(limb)
				limb:box(5, 3, z, 6, 3, z, BRONZE_DARK)
				limb:box(7, 0, z, 7, 3, z, BRONZE_DARK)
				limb:box(8, 2, z, 8, 2, z, BRONZE)
			end
		end
		pet:limbPair("MiddleLeftLeg", "MiddleRightLeg", { 5, 3.5, 0.5 }, leg(0))
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 5, 3.5, -3.5 }, leg(-4))

		local tail = pet:limb("Tail", { 0, 3, -7 })
		tail:box(-1, 2, -8, 0, 3, -8, BRONZE)

		pet:light(SUN, 2.2, 14)
		pet:particles("Sparkles", SUN, 8)
		pet:seat(0, 9, -2)
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
	scale = 0.6,
	draw = function(pet)
		local FUR = rgb(236, 230, 218)
		local SHADE = rgb(206, 198, 184)
		local STRIPE = rgb(74, 84, 104)
		local IVORY = rgb(250, 240, 214)
		local NOSE = rgb(120, 86, 86)
		local MOUTH = rgb(60, 50, 56)
		local ICE = rgb(150, 206, 244)
		local CRYSTAL = rgb(196, 240, 255)

		-- A powerful pale cat: high shoulders, slim waist, heavy hips, slate stripes and an ice-blue collar.
		local body = pet:limb("Body", { 0, 8, 0 })
		body:box(-5, 7, 0, 4, 13, 5, FUR)
		body:box(-4, 7, -5, 3, 11, -1, FUR)
		body:box(-4, 7, -9, 3, 12, -6, FUR)
		body:paint(-4, 7, -5, 3, 7, -1, SHADE)
		body:paint(-5, 13, 2, 4, 13, 2, STRIPE)
		body:paintPair(4, 10, 2, 4, 13, 2, STRIPE)
		for _, z in { -4, -2 } do
			body:paint(-4, 11, z, 3, 11, z, STRIPE)
			body:paintPair(3, 9, z, 3, 11, z, STRIPE)
		end
		body:paint(-4, 12, -8, 3, 12, -8, STRIPE)
		body:paintPair(3, 9, -8, 3, 12, -8, STRIPE)
		body:box(-6, 11, 4, 5, 12, 6, ICE)
		body:boxPair(6, 11, 5, 6, 12, 5, CRYSTAL, GLASS, 0.15)
		body:box(-1, 11, 7, 0, 12, 7, CRYSTAL, GLASS, 0.15)

		-- A broad head with a heavy brow, glowing ice eyes, cheek ruffs, tufted ears and huge sabre fangs.
		local head = pet:limb("Head", { 0, 12, 6 })
		head:box(-4, 12, 6, 3, 17, 10, FUR)
		head:box(-3, 16, 11, 2, 16, 11, SHADE)
		head:box(-2, 12, 11, 1, 14, 12, FUR)
		head:box(-1, 14, 13, 0, 14, 13, NOSE)
		head:paint(-2, 12, 12, 1, 12, 12, MOUTH)
		head:paintPair(1, 13, 12, 1, 13, 12, STRIPE)
		head:boxPair(1, 10, 13, 1, 12, 13, IVORY)
		head:boxPair(1, 8, 12, 1, 9, 12, IVORY)
		head:paintPair(1, 15, 10, 2, 15, 10, ICE, NEON)
		head:paint(-1, 17, 6, 0, 17, 10, STRIPE)
		head:paintPair(2, 17, 7, 2, 17, 8, STRIPE)
		head:boxPair(4, 12, 7, 4, 15, 9, FUR)
		head:paintPair(4, 13, 7, 4, 13, 9, STRIPE)
		head:boxPair(2, 18, 7, 3, 19, 8, FUR)
		head:boxPair(3, 20, 7, 3, 20, 7, STRIPE)
		head:paintPair(2, 18, 8, 2, 18, 8, SHADE)

		-- Thick striped legs with big paws and ivory claws.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3.5, 8, 3 }, function(leg)
			leg:box(2, 3, 2, 4, 7, 4, FUR)
			leg:box(2, 0, 2, 4, 2, 5, FUR)
			leg:box(2, 0, 6, 4, 0, 6, IVORY)
			leg:paint(3, 0, 5, 3, 1, 5, SHADE)
			leg:paint(2, 5, 2, 4, 5, 4, STRIPE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3.5, 8, -7.5 }, function(leg)
			leg:box(3, 4, -9, 5, 10, -6, FUR)
			leg:box(2, 0, -8, 4, 3, -7, FUR)
			leg:box(2, 0, -6, 4, 0, -6, FUR)
			leg:paint(5, 6, -8, 5, 9, -8, STRIPE)
			leg:paint(2, 2, -8, 4, 2, -7, STRIPE)
		end)

		-- A short bobtail.
		local tail = pet:limb("Tail", { 0, 11, -9 })
		tail:box(-1, 10, -11, 0, 12, -10, FUR)
		tail:paint(-1, 12, -11, 0, 12, -11, STRIPE)

		pet:light(ICE, 1.6, 12)
		pet:seat(0, 14, -2)
	end,
}

Designs.AuroraOwl = {
	name = "Aurora Owl",
	skeleton = "Winged",
	gait = "Waddle",
	scale = 0.55,
	draw = function(pet)
		local NIGHT = rgb(30, 40, 92)
		local NIGHT_LIGHT = rgb(52, 66, 132)
		local FEATHER = rgb(86, 116, 196)
		local CHEST = rgb(226, 234, 252)
		local MARK = rgb(160, 182, 228)
		local GREEN = rgb(90, 255, 170)
		local TEAL = rgb(80, 220, 255)
		local VIOLET = rgb(182, 124, 255)
		local STAR = rgb(255, 255, 255)
		local BEAK = rgb(240, 200, 120)
		local TALON = rgb(60, 60, 80)

		-- A night-blue owl whose back is speckled with stars.
		local body = pet:limb("Body", { 0, 2, 0 })
		body:box(-4, 2, -3, 3, 10, 3, NIGHT)
		body:box(-3, 3, 4, 2, 9, 4, CHEST)
		body:paintPair(1, 8, 4, 2, 8, 4, MARK)
		body:paintPair(2, 6, 4, 2, 6, 4, MARK)
		body:paint(-1, 7, 4, 0, 7, 4, MARK)
		body:paint(-1, 5, 4, 0, 5, 4, MARK)
		body:paintPair(1, 4, 4, 1, 4, 4, MARK)
		body:paint(-3, 9, -3, -3, 9, -3, STAR, NEON)
		body:paint(2, 7, -3, 2, 7, -3, STAR, NEON)
		body:paint(-1, 5, -3, -1, 5, -3, STAR, NEON)
		body:paint(1, 3, -3, 1, 3, -3, STAR, NEON)
		body:paint(-3, 4, -3, -3, 4, -3, STAR, NEON)
		body:paint(0, 9, -3, 0, 9, -3, STAR, NEON)

		-- A pale face disc, glowing eyes under aurora brows, a hooked beak and tufts tipped with light.
		local head = pet:limb("Head", { 0, 11, 0 })
		head:box(-4, 11, -3, 3, 16, 3, NIGHT)
		head:box(-3, 17, -2, 2, 17, 2, NIGHT)
		head:paint(-4, 11, 3, 3, 15, 3, CHEST)
		head:paint(-4, 11, 3, -4, 15, 3, FEATHER)
		head:paint(3, 11, 3, 3, 15, 3, FEATHER)
		head:paintPair(1, 12, 3, 2, 13, 3, TEAL, NEON)
		head:paintPair(1, 12, 3, 1, 13, 3, NIGHT)
		head:paintPair(1, 13, 3, 1, 13, 3, STAR)
		head:boxPair(1, 15, 4, 3, 15, 4, VIOLET, NEON)
		head:box(-1, 11, 4, 0, 12, 4, BEAK)
		head:box(-1, 10, 5, 0, 11, 5, BEAK)
		head:boxPair(2, 18, -1, 3, 18, 0, NIGHT)
		head:boxPair(3, 19, -1, 4, 19, 0, FEATHER)
		head:boxPair(4, 20, -1, 5, 20, 0, TEAL, NEON)
		head:boxPair(5, 21, -1, 5, 21, 0, GREEN, NEON)
		head:paint(-2, 16, -3, -2, 16, -3, STAR, NEON)
		head:paint(1, 14, -3, 1, 14, -3, STAR, NEON)
		head:paint(-1, 17, 1, -1, 17, 1, STAR, NEON)

		-- Half-open wings banded with the northern lights.
		pet:limbPair("LeftWing", "RightWing", { 4.5, 10, 0 }, function(wing)
			wing:box(4, 6, -2, 5, 10, 2, NIGHT_LIGHT)
			wing:box(4, 3, -3, 5, 5, 1, FEATHER)
			wing:box(4, 1, -6, 4, 4, -4, FEATHER)
			wing:paint(5, 8, -2, 5, 8, 2, GREEN, NEON)
			wing:paint(5, 6, -2, 5, 6, 2, TEAL, NEON)
			wing:paint(5, 4, -3, 5, 4, 1, VIOLET, NEON)
			wing:paint(4, 2, -6, 4, 2, -4, TEAL, NEON)
		end)
		pet:limbPair("LeftLeg", "RightLeg", { 2, 2, 1 }, function(leg)
			leg:box(1, 1, 0, 2, 1, 1, CHEST)
			leg:box(1, 0, 0, 2, 0, 2, BEAK)
			leg:paint(1, 0, 2, 2, 0, 2, TALON)
		end)

		-- Long trailing tail feathers with glowing tips.
		local tail = pet:limb("Tail", { 0, 4, -3 })
		tail:box(-2, 3, -5, 1, 5, -4, NIGHT)
		tail:box(-1, 2, -11, 0, 3, -6, FEATHER)
		tail:box(-1, 2, -12, 0, 2, -12, TEAL, NEON)
		tail:boxPair(1, 3, -9, 2, 3, -6, FEATHER)
		tail:boxPair(1, 3, -10, 2, 3, -10, VIOLET, NEON)
		tail:paint(-1, 3, -9, 0, 3, -9, GREEN, NEON)

		pet:light(TEAL, 1.8, 13)
		pet:particles("Sparkles", GREEN, 8)
		pet:seat(0, 18, -1)
	end,
}

Designs.WoollyMammoth = {
	name = "Woolly Mammoth",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local WOOL = rgb(120, 78, 48)
		local WOOL_DARK = rgb(88, 56, 34)
		local WOOL_LIGHT = rgb(150, 104, 66)
		local SNOW = rgb(246, 250, 255)
		local IVORY = rgb(250, 240, 214)
		local IVORY_DARK = rgb(222, 206, 168)
		local ICE = rgb(196, 240, 255)

		-- A huge shaggy body with a shoulder hump, a curtain of long fur with icicles, snow on its back and
		-- frost crystals growing out of the snow.
		local body = pet:limb("Body", { 0, 10, 0 })
		body:box(-6, 7, -7, 5, 15, 5, WOOL)
		body:box(-4, 16, -1, 3, 17, 4, WOOL)
		body:box(-5, 8, -8, 4, 14, -8, WOOL)
		body:boxPair(6, 6, -6, 6, 13, 4, WOOL_DARK)
		body:boxPair(6, 5, -5, 6, 5, -4, WOOL_DARK)
		body:boxPair(6, 4, -1, 6, 5, -1, WOOL_DARK)
		body:boxPair(6, 5, 2, 6, 5, 3, WOOL_DARK)
		body:box(-5, 6, -3, 4, 6, 0, WOOL_DARK)
		body:box(-3, 5, -3, -2, 5, -2, WOOL_DARK)
		body:box(1, 5, -1, 2, 5, -1, WOOL_DARK)
		body:paint(-4, 15, -5, -3, 15, -2, WOOL_LIGHT)
		body:paint(1, 15, -6, 2, 15, -3, WOOL_LIGHT)
		body:paintPair(6, 10, -3, 6, 12, -2, WOOL)
		body:box(-3, 16, -6, 2, 16, -2, SNOW)
		body:paint(-3, 17, 0, 2, 17, 3, SNOW)
		body:box(-1, 17, -5, 0, 19, -5, ICE, GLASS, 0.15)
		body:boxPair(2, 17, -4, 2, 18, -4, ICE, GLASS, 0.15)
		body:box(-2, 17, -3, -2, 17, -3, ICE, GLASS, 0.15)
		body:boxPair(6, 3, -4, 6, 4, -4, ICE, GLASS, 0.15)
		body:boxPair(6, 2, -1, 6, 3, -1, ICE, GLASS, 0.15)

		-- A high domed head capped with snow, shaggy bangs, a curling trunk and great frost-tipped tusks.
		local head = pet:limb("Head", { 0, 13, 6 })
		head:box(-4, 10, 6, 3, 17, 11, WOOL)
		head:box(-3, 18, 7, 2, 19, 10, WOOL)
		head:paint(-3, 19, 7, 2, 19, 10, SNOW)
		head:paint(-3, 18, 10, -3, 18, 10, SNOW)
		head:paint(2, 18, 7, 2, 18, 8, SNOW)
		eyes(head, 2, 14, 11, 1)
		head:box(-3, 16, 12, 2, 17, 12, WOOL_DARK)
		head:boxPair(4, 13, 8, 4, 15, 9, WOOL_DARK)
		head:box(-1, 9, 12, 0, 14, 13, WOOL)
		head:box(-1, 6, 12, 0, 8, 13, WOOL)
		head:box(-1, 5, 14, 0, 6, 14, WOOL)
		head:box(-1, 6, 15, 0, 7, 15, WOOL_LIGHT)
		head:paint(-1, 8, 13, 0, 8, 13, WOOL_DARK)
		head:paint(-1, 11, 13, 0, 11, 13, WOOL_DARK)
		head:boxPair(2, 10, 12, 2, 11, 13, IVORY)
		head:boxPair(3, 8, 13, 3, 10, 14, IVORY)
		head:boxPair(4, 7, 15, 4, 8, 16, IVORY)
		head:boxPair(4, 9, 17, 4, 11, 17, IVORY)
		head:boxPair(3, 12, 17, 3, 12, 17, ICE, GLASS, 0.15)
		head:paintPair(3, 9, 13, 3, 9, 14, IVORY_DARK)

		-- Pillar legs with shaggy cuffs and ivory toenails.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 4, 9, 3 }, function(leg)
			leg:box(2, 1, 1, 5, 8, 4, WOOL)
			leg:box(2, 0, 1, 5, 0, 4, WOOL_DARK)
			leg:paint(2, 2, 1, 5, 3, 4, WOOL_DARK)
			leg:box(2, 0, 5, 2, 0, 5, IVORY)
			leg:box(4, 0, 5, 4, 0, 5, IVORY)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 4, 9, -5 }, function(leg)
			leg:box(2, 1, -7, 5, 8, -4, WOOL)
			leg:box(2, 0, -7, 5, 0, -4, WOOL_DARK)
			leg:paint(2, 2, -7, 5, 3, -4, WOOL_DARK)
			leg:box(2, 0, -3, 2, 0, -3, IVORY)
			leg:box(4, 0, -3, 4, 0, -3, IVORY)
		end)

		local tail = pet:limb("Tail", { 0, 13, -8 })
		tail:box(-1, 10, -9, 0, 13, -9, WOOL)
		tail:box(-1, 8, -9, 0, 9, -9, WOOL_DARK)

		pet:light(ICE, 1.6, 14)
		pet:particles("Snow", SNOW, 8)
		pet:seat(0, 18, -2)
	end,
}

Designs.Yeti = {
	name = "Yeti",
	skeleton = "Biped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local FUR = rgb(240, 245, 250)
		local SHADE = rgb(204, 218, 236)
		local DEEP = rgb(170, 190, 220)
		local SKIN = rgb(146, 182, 224)
		local SKIN_DARK = rgb(92, 124, 172)
		local MOUTH = rgb(30, 36, 56)
		local CLAW = rgb(220, 236, 250)
		local ICE = rgb(196, 240, 255)
		local ICE_DEEP = rgb(120, 190, 240)
		local GLOW = rgb(130, 236, 255)
		local GLOW_WHITE = rgb(230, 250, 255)

		-- A towering, hunched body of shaggy white fur, hanging in layered fringes.
		local body = pet:limb("Body", { 0, 9, 0 })
		body:box(-5, 9, -4, 4, 14, 3, FUR)
		body:box(-7, 15, -5, 6, 21, 4, FUR)
		body:box(-5, 22, -5, 4, 22, 1, FUR)
		body:boxPair(5, 12, -4, 6, 14, -3, FUR)
		body:boxPair(5, 13, -1, 6, 14, 0, FUR)
		body:boxPair(5, 11, 2, 6, 14, 3, FUR)
		body:paintPair(5, 12, -4, 6, 12, -3, DEEP)
		body:paintPair(5, 11, 2, 6, 11, 3, DEEP)
		body:paintPair(5, 13, -1, 6, 13, 0, DEEP)
		body:box(-1, 8, -3, 0, 8, 2, SHADE)
		body:box(-1, 7, -2, 0, 7, 1, SHADE)
		body:paint(-5, 9, -4, 4, 9, 3, DEEP)
		body:paint(-5, 11, 3, 4, 11, 3, SHADE)
		body:paint(-5, 13, 3, 4, 13, 3, SHADE)
		body:paint(-7, 15, -5, 6, 15, 4, DEEP)
		body:paintPair(6, 18, -3, 6, 18, 3, SHADE)
		body:paintPair(6, 15, -5, 6, 21, -5, SHADE)
		body:paintPair(4, 17, -5, 4, 21, -5, SHADE)
		body:paint(-1, 15, -5, 0, 20, -5, SHADE)
		body:paintPair(6, 17, 0, 6, 20, 0, SHADE)
		-- A bare blue chest with a glowing frost rune, and a necklace of ice fangs.
		body:paint(-3, 15, 4, 2, 20, 4, SKIN)
		body:paint(-1, 15, 4, 0, 17, 4, GLOW, NEON)
		body:paintPair(1, 16, 4, 2, 16, 4, GLOW, NEON)
		body:paintPair(1, 15, 4, 1, 15, 4, GLOW, NEON)
		body:paintPair(1, 17, 4, 1, 17, 4, GLOW, NEON)
		body:paint(-1, 18, 4, 0, 18, 4, SKIN_DARK)
		body:box(-4, 21, 5, 3, 21, 5, SKIN_DARK)
		body:boxPair(0, 19, 5, 0, 20, 5, ICE, GLASS, 0.1)
		body:boxPair(2, 20, 5, 2, 20, 5, ICE, GLASS, 0.1)
		body:boxPair(3, 20, 5, 3, 20, 5, CLAW)
		-- Ice shards growing out of its back and shoulders, glowing from inside.
		body:box(-3, 19, -7, -2, 23, -6, ICE_DEEP, GLASS, 0.1)
		body:paint(-3, 21, -7, -3, 22, -7, GLOW, NEON)
		body:box(1, 18, -7, 2, 21, -6, ICE, GLASS, 0.15)
		body:box(-1, 20, -6, 0, 25, -6, ICE, GLASS, 0.15)
		body:paint(-1, 22, -6, 0, 23, -6, GLOW, NEON)
		body:box(3, 16, -6, 3, 18, -6, ICE_DEEP, GLASS, 0.1)
		body:boxPair(5, 22, -2, 6, 24, -1, ICE, GLASS, 0.15)
		body:boxPair(6, 25, -2, 6, 26, -2, ICE, GLASS, 0.15)
		body:paintPair(5, 23, -1, 5, 23, -1, GLOW, NEON)

		-- A blue face under a heavy fur brow: glowing eyes, a flat nose, tusks, cheek tufts, and great
		-- curling horns of ice with a crown of shards between them.
		local head = pet:limb("Head", { 0, 22, 1 })
		head:box(-4, 23, -1, 3, 29, 5, FUR)
		head:paint(-3, 23, 5, 2, 27, 5, SKIN)
		head:box(-4, 28, 6, 3, 28, 6, FUR)
		head:paint(-4, 28, 6, 3, 28, 6, SHADE)
		head:paintPair(1, 26, 5, 2, 27, 5, GLOW, NEON)
		head:paintPair(1, 27, 5, 1, 27, 5, SKIN_DARK)
		head:box(-1, 24, 6, 0, 25, 6, SKIN_DARK)
		head:paint(-1, 24, 6, 0, 24, 6, MOUTH)
		head:paint(-2, 23, 5, 1, 23, 5, MOUTH)
		head:boxPair(2, 23, 6, 2, 24, 6, CLAW)
		head:boxPair(4, 23, 2, 4, 27, 4, FUR)
		head:paintPair(4, 23, 2, 4, 23, 4, SHADE)
		head:paintPair(4, 25, 2, 4, 25, 4, SHADE)
		head:box(-3, 30, 0, 2, 30, 4, FUR)
		head:box(-2, 31, 1, 1, 31, 3, FUR)
		head:paintPair(3, 24, -1, 3, 28, 0, SHADE)
		head:paint(-3, 24, -1, 2, 26, -1, SHADE)
		head:paint(-3, 30, 0, 2, 30, 0, SHADE)
		head:boxPair(4, 28, 1, 5, 29, 3, ICE_DEEP, GLASS)
		head:boxPair(6, 29, 0, 7, 30, 2, ICE_DEEP, GLASS)
		head:boxPair(8, 27, -1, 9, 29, 1, ICE_DEEP, GLASS)
		head:boxPair(8, 24, 0, 9, 26, 2, ICE_DEEP, GLASS)
		head:boxPair(7, 23, 2, 7, 24, 3, ICE_DEEP, GLASS)
		head:boxPair(6, 23, 4, 6, 23, 4, GLOW_WHITE, NEON)
		head:paintPair(4, 28, 3, 5, 28, 3, GLOW, NEON)
		head:paintPair(6, 30, 2, 7, 30, 2, GLOW, NEON)
		head:paintPair(8, 28, 1, 9, 28, 1, GLOW, NEON)
		head:paintPair(8, 25, 2, 9, 25, 2, GLOW, NEON)
		head:box(-1, 32, 2, 0, 33, 2, ICE, GLASS, 0.15)
		head:paint(-1, 33, 2, 0, 33, 2, GLOW_WHITE, NEON)
		head:boxPair(1, 32, 1, 1, 32, 1, ICE, GLASS, 0.15)
		head:boxPair(2, 31, 3, 2, 31, 3, ICE, GLASS, 0.15)

		-- Long arms to the ground: fur shoulders, ice bracers with glowing runes, blue fists and ice claws.
		local function arm(limb: Limb)
			limb:box(7, 17, -2, 9, 21, 2, FUR)
			limb:paint(7, 21, -2, 9, 21, 2, SHADE)
			limb:box(8, 12, -2, 10, 16, 1, FUR)
			limb:box(10, 11, -3, 10, 14, -3, DEEP)
			limb:box(8, 7, -2, 10, 11, 1, FUR)
			limb:box(7, 8, -3, 11, 10, 2, ICE, GLASS, 0.15)
			limb:paint(11, 9, -1, 11, 9, 0, GLOW, NEON)
			limb:paint(9, 9, 2, 9, 9, 2, GLOW, NEON)
			limb:box(8, 3, -2, 10, 6, 2, SKIN)
			limb:paint(8, 6, -2, 10, 6, 2, FUR)
			limb:box(8, 2, 3, 8, 3, 3, ICE, GLASS, 0.15)
			limb:box(10, 2, 3, 10, 3, 3, ICE, GLASS, 0.15)
			limb:box(9, 1, 3, 9, 2, 3, ICE, GLASS, 0.15)
		end
		arm(pet:limb("LeftArm", { 8.5, 20, 0 }))
		local right = mirrored(pet:limb("RightArm", { -8.5, 20, 0 }))
		arm(right)
		-- In its right hand, a club of frost crystal.
		right:box(9, 4, 3, 9, 5, 6, ICE_DEEP, GLASS, 0.1)
		right:box(8, 3, 7, 10, 7, 10, ICE, GLASS, 0.15)
		right:box(9, 8, 8, 9, 9, 9, ICE, GLASS, 0.15)
		right:box(11, 5, 8, 11, 6, 9, ICE, GLASS, 0.15)
		right:box(9, 4, 11, 9, 5, 11, ICE, GLASS, 0.15)
		right:paint(9, 4, 10, 9, 6, 10, GLOW, NEON)
		right:paint(10, 5, 8, 10, 6, 9, GLOW, NEON)

		-- Thick legs with a fringe at the knee, icicles, and wide blue feet with claws.
		pet:limbPair("LeftLeg", "RightLeg", { 3, 9, 0 }, function(leg)
			leg:box(1, 5, -3, 5, 9, 2, FUR)
			leg:box(1, 4, -3, 5, 4, 3, DEEP)
			leg:box(2, 1, -2, 4, 3, 2, FUR)
			leg:box(1, 0, -3, 5, 0, 4, SKIN)
			leg:paint(1, 0, -3, 5, 0, -3, SKIN_DARK)
			leg:box(1, 0, 5, 1, 0, 5, CLAW)
			leg:box(3, 0, 5, 3, 0, 5, CLAW)
			leg:box(5, 0, 5, 5, 0, 5, CLAW)
			leg:box(5, 2, 0, 5, 3, 0, ICE, GLASS, 0.15)
			leg:box(1, 2, 3, 1, 3, 3, ICE, GLASS, 0.15)
			leg:paint(1, 7, 2, 5, 7, 2, SHADE)
		end)

		pet:light(GLOW, 2.6, 18)
		pet:particles("Snow", GLOW_WHITE, 14)
		pet:seat(0, 23, -4)
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
	scale = 0.55,
	draw = function(pet)
		local SLATE = rgb(122, 142, 172)
		local SLATE_DARK = rgb(82, 100, 136)
		local BELLY = rgb(232, 242, 250)
		local IVORY = rgb(250, 242, 220)
		local IVORY_DARK = rgb(222, 206, 168)
		local GLOW = rgb(255, 250, 230)
		local ICE = rgb(170, 230, 255)

		-- A plump whale body, mottled on the back and pale underneath, with a low ridge.
		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-4, 1, -6, 3, 7, 3, SLATE)
		body:box(-3, 8, -5, 2, 8, 2, SLATE)
		body:box(-3, 0, -5, 2, 0, 2, BELLY)
		body:paint(-4, 1, -6, 3, 2, 3, BELLY)
		body:box(-1, 9, -4, 0, 9, -1, SLATE_DARK)
		body:box(-1, 10, -3, -1, 11, -3, ICE, GLASS, 0.2)
		body:box(0, 10, -2, 0, 10, -2, ICE, GLASS, 0.2)
		body:box(-1, 10, -1, -1, 10, -1, ICE, GLASS, 0.2)
		body:boxPair(2, 9, -4, 2, 9, -4, ICE, GLASS, 0.2)
		for _, spot in
			{
				{ 3, 6, -4 },
				{ 3, 4, -1 },
				{ -4, 5, -3 },
				{ -4, 6, 1 },
				{ 1, 8, -3 },
				{ -2, 8, 0 },
				{ 3, 5, 2 },
				{ -4, 3, -5 },
				{ 0, 7, -6 },
				{ 3, 7, -2 },
				{ -4, 7, -1 },
				{ 2, 8, -5 },
				{ -3, 8, -4 },
				{ 3, 3, 0 },
				{ -4, 4, 2 },
				{ -2, 6, -6 },
			}
		do
			body:paint(spot[1], spot[2], spot[3], spot[1], spot[2], spot[3], SLATE_DARK)
		end

		-- A rounded head with a smile, and the long spiral tusk, glowing faintly at its tip.
		local head = pet:limb("Head", { 0, 4, 4 })
		head:box(-3, 1, 4, 2, 6, 7, SLATE)
		head:box(-2, 7, 4, 1, 7, 6, SLATE)
		head:paint(-3, 1, 4, 2, 1, 7, BELLY)
		head:paint(-3, 2, 7, 2, 2, 7, SLATE_DARK)
		eyes(head, 2, 4, 7, 1, 1)
		head:paintPair(2, 6, 5, 2, 6, 5, SLATE_DARK)
		head:box(-1, 4, 8, 0, 5, 10, IVORY)
		head:paint(-1, 5, 8, -1, 5, 8, IVORY_DARK)
		head:paint(0, 4, 9, 0, 4, 9, IVORY_DARK)
		head:paint(-1, 5, 10, -1, 5, 10, IVORY_DARK)
		head:box(0, 5, 11, 0, 5, 13, IVORY)
		head:paint(0, 5, 12, 0, 5, 12, IVORY_DARK)
		head:box(0, 6, 14, 0, 6, 17, IVORY)
		head:paint(0, 6, 15, 0, 6, 15, IVORY_DARK)
		head:box(0, 6, 18, 0, 6, 18, GLOW, NEON)
		head:paint(0, 6, 17, 0, 6, 17, IVORY_DARK)
		head:paint(0, 5, 13, 0, 5, 13, IVORY_DARK)
		head:paint(-2, 7, 5, -2, 7, 5, SLATE_DARK)
		head:paint(1, 6, 7, 1, 6, 7, SLATE_DARK)
		head:paint(-3, 5, 5, -3, 5, 5, SLATE_DARK)

		pet:limbPair("LeftFin", "RightFin", { 4, 1.5, 2 }, function(fin)
			fin:box(4, 1, 1, 6, 1, 3, SLATE_DARK)
			fin:box(7, 0, 1, 7, 0, 2, SLATE_DARK)
			fin:paint(6, 1, 1, 6, 1, 3, BELLY)
			fin:paint(5, 1, 2, 5, 1, 2, SLATE)
		end)

		-- A thick tail and broad flukes, with a few chips of ice stuck to them.
		local tail = pet:limb("Tail", { 0, 4, -6 })
		tail:box(-2, 2, -9, 1, 5, -7, SLATE)
		tail:paint(-2, 2, -9, 1, 2, -7, BELLY)
		tail:box(-1, 3, -11, 0, 4, -10, SLATE)
		tail:box(-5, 4, -13, 4, 4, -12, SLATE_DARK)
		tail:boxPair(3, 4, -14, 4, 4, -14, SLATE_DARK)
		tail:paint(-1, 5, -8, -1, 5, -8, SLATE_DARK)
		tail:box(-3, 5, -13, -3, 5, -13, ICE, GLASS, 0.2)
		tail:box(2, 5, -12, 2, 5, -12, ICE, GLASS, 0.2)
		tail:paintPair(1, 5, -8, 1, 5, -8, SLATE_DARK)
		tail:paint(-5, 4, -12, -4, 4, -12, SLATE)
		tail:paint(3, 4, -12, 4, 4, -12, SLATE)
		tail:paint(-1, 3, -11, 0, 3, -10, BELLY)

		pet:light(ICE, 1.6, 12)
		pet:seat(0, 9, 1)
	end,
}

Designs.Hippocampus = {
	name = "Hippocampus",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.55,
	draw = function(pet)
		local TEAL = rgb(36, 172, 168)
		local TEAL_DARK = rgb(22, 122, 126)
		local BELLY = rgb(188, 242, 230)
		local FIN = rgb(90, 220, 210)
		local GLOW = rgb(80, 255, 228)
		local CORAL = rgb(255, 150, 160)
		local PEARL = rgb(250, 246, 240)

		-- A sea horse's body: ridged, pale-bellied, with a see-through fin down its back.
		local body = pet:limb("Body", { 0, 6, 0 })
		body:box(-3, 4, -3, 2, 9, 3, TEAL)
		body:box(-2, 4, 4, 1, 8, 4, BELLY)
		body:paint(-2, 5, 4, 1, 5, 4, TEAL_DARK)
		body:paint(-2, 7, 4, 1, 7, 4, TEAL_DARK)
		body:paint(-3, 4, -3, 2, 4, 3, BELLY)
		for _, z in { -2, 0, 2 } do
			body:paintPair(2, 4, z, 2, 9, z, TEAL_DARK)
		end
		body:box(-3, 10, -2, 2, 10, 0, CORAL)
		body:box(-2, 11, -2, 1, 11, -1, rgb(255, 214, 200))
		body:paint(-2, 11, -2, 1, 11, -2, CORAL)
		body:boxPair(3, 9, -1, 3, 10, 0, CORAL)
		body:boxPair(3, 8, -1, 3, 8, -1, PEARL)
		body:boxPair(3, 8, 0, 3, 8, 0, PEARL)
		body:box(-1, 11, 0, 0, 11, 0, PEARL)
		body:box(-1, 10, -3, 0, 11, -3, FIN, GLASS, 0.3)
		body:paint(-1, 11, -3, 0, 11, -3, GLOW, NEON)
		for _, dot in { { 2, 6, -2 }, { 2, 8, 2 }, { -3, 7, -1 }, { -3, 5, 1 }, { 2, 5, 0 }, { -3, 8, 2 } } do
			body:paint(dot[1], dot[2], dot[3], dot[1], dot[2], dot[3], GLOW, NEON)
		end

		-- A horse's head on a long neck, with a glassy fin mane, a coral crown and a pearl on its brow.
		local head = pet:limb("Head", { 0, 9, 3 })
		head:box(-2, 9, 2, 1, 12, 4, TEAL)
		head:box(-2, 12, 3, 1, 15, 7, TEAL)
		head:box(-1, 12, 8, 0, 14, 10, TEAL)
		head:paint(-1, 12, 10, 0, 12, 10, TEAL_DARK)
		head:paint(-1, 14, 10, 0, 14, 10, TEAL_DARK)
		eyes(head, 1, 14, 7, 1)
		head:box(-1, 15, 8, 0, 15, 8, PEARL)
		head:box(-1, 9, 1, 0, 12, 1, FIN, GLASS, 0.3)
		head:box(-1, 13, 2, 0, 16, 2, FIN, GLASS, 0.3)
		head:box(-1, 16, 3, 0, 17, 5, FIN, GLASS, 0.3)
		head:paint(-1, 10, 1, 0, 10, 1, GLOW, NEON)
		head:paint(-1, 14, 2, 0, 14, 2, GLOW, NEON)
		head:paint(-1, 17, 4, 0, 17, 4, GLOW, NEON)
		head:boxPair(1, 16, 5, 1, 17, 5, CORAL)
		head:boxPair(1, 16, 7, 1, 16, 7, CORAL)
		head:boxPair(2, 15, 4, 2, 16, 4, FIN, GLASS, 0.3)
		head:box(-1, 12, 0, 0, 12, 0, FIN, GLASS, 0.3)
		head:paintPair(1, 10, 4, 1, 11, 4, TEAL_DARK)
		head:paintPair(2, 13, 6, 2, 14, 6, TEAL_DARK)
		head:box(-2, 13, 9, 1, 13, 9, rgb(70, 150, 90))
		head:boxPair(2, 11, 6, 2, 12, 8, rgb(70, 150, 90))
		head:paintPair(2, 12, 7, 2, 12, 7, PEARL)

		-- Horse forelegs ending in webbed fins.
		pet:limbPair("LeftFin", "RightFin", { 1.5, 6, 2.5 }, function(leg)
			leg:box(1, 4, 2, 2, 6, 3, TEAL)
			leg:box(1, 2, 4, 2, 3, 5, TEAL)
			leg:paint(1, 3, 4, 2, 3, 5, TEAL_DARK)
			leg:box(1, 1, 6, 3, 2, 7, FIN, GLASS, 0.3)
			leg:paint(1, 1, 7, 3, 1, 7, GLOW, NEON)
			leg:box(3, 2, 4, 3, 3, 4, FIN, GLASS, 0.3)
		end)

		-- A fish tail sweeping down and back, curling up into a great see-through fin.
		local tail = pet:limb("Tail", { 0, 5, -3 })
		tail:box(-2, 3, -6, 1, 6, -4, TEAL)
		tail:box(-2, 1, -8, 1, 3, -7, TEAL)
		tail:box(-1, 0, -10, 0, 1, -9, TEAL)
		tail:box(-1, 1, -12, 0, 3, -11, TEAL)
		tail:box(-1, 4, -12, 0, 5, -12, TEAL)
		tail:paint(-2, 3, -6, 1, 3, -6, TEAL_DARK)
		tail:paint(-2, 2, -8, 1, 2, -8, TEAL_DARK)
		tail:paint(-1, 1, -10, 0, 1, -10, TEAL_DARK)
		tail:boxPair(2, 2, -8, 2, 3, -7, FIN, GLASS, 0.3)
		tail:box(-3, 4, -14, 2, 6, -13, FIN, GLASS, 0.3)
		tail:paint(-3, 5, -14, 2, 5, -14, GLOW, NEON)
		tail:boxPair(1, 0, -10, 1, 1, -9, FIN, GLASS, 0.3)
		tail:box(-1, 2, -13, 0, 3, -13, FIN, GLASS, 0.3)
		tail:paint(-1, 4, -6, 0, 4, -6, GLOW, NEON)
		tail:paint(-1, 2, -11, 0, 2, -11, TEAL_DARK)

		pet:light(GLOW, 1.8, 13)
		pet:particles("Bubbles", rgb(226, 250, 246), 6)
		pet:seat(0, 10, 0)
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
	scale = 0.55,
	draw = function(pet)
		local SHELL = rgb(84, 66, 58)
		local SHELL_LIGHT = rgb(112, 90, 76)
		local RIM = rgb(60, 48, 44)
		local CONE = rgb(124, 112, 108)
		local CONE_DARK = rgb(92, 82, 80)
		local SKIN = rgb(130, 112, 74)
		local SKIN_DARK = rgb(98, 82, 52)
		local PLASTRON = rgb(176, 150, 96)
		local BEAK = rgb(70, 58, 44)
		local LAVA = rgb(255, 112, 24)
		local LAVA_HOT = rgb(255, 196, 40)
		local NAIL = rgb(214, 204, 186)

		-- A high domed shell, its plates split by seams of glowing lava: a rim of dark plates round the bottom,
		-- a ring of plates above it, and three more over the top.
		local function inShell(x: number, y: number, z: number): boolean
			-- Leaving a gap at the front for its neck.
			if y < 4 or (y <= 6 and z >= 5 and x >= -3 and x <= 2) then
				return false
			end
			return ((x + 0.5) / 8.2) ^ 2 + ((z + 0.5) / 9.2) ^ 2 + ((y + 0.5 - 4) / 8.5) ^ 2 <= 1
		end
		local body = pet:limb("Body", { 0, 6, 0 })
		local bounds = { -9, 4, -10, 8, 12, 9 }
		local function plate(color: Color, keep: (number, number, number) -> boolean)
			blob(body, bounds, function(x, y, z)
				return inShell(x, y, z) and keep(x, y, z)
			end, color)
		end
		local function seam(keep: (number, number, number) -> boolean)
			blob(body, bounds, function(x, y, z)
				return inShell(x, y, z) and keep(x, y, z)
			end, LAVA, NEON)
		end
		-- Round the gap for the neck, each level is drawn in three parts, so each part has no gap in it.
		for _, part in { { -9, -4 }, { -3, 2 }, { 3, 8 } } do
			plate(RIM, function(x, y)
				return y <= 5 and x >= part[1] and x <= part[2]
			end)
			seam(function(x, y)
				return y == 6 and x >= part[1] and x <= part[2]
			end)
		end
		for index, band in { { -10, -5 }, { -3, 2 }, { 4, 9 } } do
			plate(if index == 2 then SHELL_LIGHT else SHELL, function(_, y, z)
				return y >= 7 and z >= band[1] and z <= band[2]
			end)
		end
		seam(function(_, y, z)
			return y >= 7 and (z == -4 or z == 3)
		end)
		-- Its belly, between the legs.
		body:box(-4, 2, -7, 3, 3, 6, PLASTRON)

		-- A little volcano on its back, glowing at the crater, with lava running down its sides and over the shell.
		body:box(-3, 12, -6, 2, 12, -1, CONE)
		body:box(-2, 13, -5, 1, 14, -2, CONE)
		body:box(-2, 15, -5, 1, 15, -5, CONE_DARK)
		body:box(-2, 15, -2, 1, 15, -2, CONE_DARK)
		body:box(-2, 15, -4, -2, 15, -3, CONE_DARK)
		body:box(1, 15, -4, 1, 15, -3, CONE_DARK)
		body:box(-1, 15, -4, 0, 15, -3, LAVA_HOT, NEON)
		body:box(-1, 16, -4, 0, 16, -3, LAVA, NEON)
		body:box(-1, 17, -4, -1, 18, -4, LAVA_HOT, NEON)
		body:box(-1, 13, -1, 0, 14, -1, LAVA, NEON)
		body:box(-1, 12, 0, 0, 12, 0, LAVA, NEON)
		body:box(2, 13, -4, 2, 14, -4, LAVA, NEON)
		body:box(3, 12, -4, 3, 12, -4, LAVA, NEON)
		-- The lava keeps running down the shell, just outside it.
		for _, flow in { { 0, 1, 12, 7 }, { 1, 0, 11, 5 } } do
			local cellsDown = {}
			for y = flow[3], flow[4], -1 do
				local reach = 0
				while inShell(if flow[2] == 0 then reach + 1 else -1, y, if flow[1] == 0 then reach + 1 else -4) do
					reach += 1
				end
				if flow[1] == 0 then
					table.insert(cellsDown, { -1, y, reach + 1 })
				else
					table.insert(cellsDown, { reach + 1, y, -4 })
				end
			end
			cells(body, cellsDown, LAVA, false, NEON)
		end

		-- A wrinkled neck and a blunt head with a hooked beak and ember eyes.
		local head = pet:limb("Head", { 0, 6, 7 })
		tube(head, { { 0, 4.5, 7, 1.5 }, { 0, 6, 9.5, 1.4 }, { 0, 7.5, 10.5, 1.3 } }, SKIN, { even = true })
		head:box(-2, 6, 10, 1, 9, 14, SKIN)
		head:box(-1, 6, 15, 0, 8, 15, BEAK)
		head:box(-1, 5, 15, 0, 5, 15, BEAK)
		head:paint(-2, 6, 14, 1, 6, 14, BEAK)
		head:paintPair(1, 8, 12, 1, 8, 13, LAVA_HOT, NEON)
		head:paintPair(1, 8, 12, 1, 8, 12, BEAK)
		head:paintPair(1, 6, 11, 1, 7, 11, SKIN_DARK)

		-- Stumpy, scaly elephant legs with pale nails.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 5, 3.5, 4 }, function(leg)
			leg:box(4, 0, 3, 6, 3, 5, SKIN)
			leg:box(4, 0, 6, 6, 0, 6, NAIL)
			leg:paint(6, 2, 3, 6, 2, 4, SKIN_DARK)
			leg:paint(4, 3, 5, 5, 3, 5, SKIN_DARK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 5, 3.5, -6 }, function(leg)
			leg:box(4, 0, -7, 6, 3, -5, SKIN)
			leg:box(4, 0, -4, 6, 0, -4, NAIL)
			leg:paint(6, 1, -6, 6, 2, -6, SKIN_DARK)
		end)

		-- A stubby pointed tail.
		local tail = pet:limb("Tail", { 0, 4, -9 })
		tail:box(-1, 2, -11, 0, 3, -9, SKIN)
		tail:box(-1, 2, -12, 0, 2, -12, SKIN_DARK)

		pet:light(LAVA, 2, 14)
		pet:seat(0, 12, 2)
	end,
}

Designs.FireSalamander = {
	name = "Fire Salamander",
	skeleton = "LowSlung",
	gait = "Crawl",
	scale = 0.6,
	draw = function(pet)
		local BLACK = rgb(34, 28, 32)
		local BLACK_LIGHT = rgb(60, 50, 56)
		local YELLOW = rgb(255, 210, 40)
		local ORANGE = rgb(255, 142, 32)
		local FLAME = rgb(242, 82, 28)
		local BELLY = rgb(74, 60, 64)
		local IRIS = rgb(255, 196, 40)
		local MOUTH = rgb(120, 40, 36)

		-- A long, low black body splashed with bright yellow and orange blotches.
		local function inBody(x: number, y: number, z: number): boolean
			local t = (z + 0.5 - 0) / 6.5
			if math.abs(t) > 1 then
				return false
			end
			local r = 1 - t * t
			return ((x + 0.5) / (3.4 * r ^ 0.4)) ^ 2 + ((y + 0.5 - 3) / (2.4 * r ^ 0.4)) ^ 2 <= 1
		end
		local body = pet:limb("Body", { 0, 3, 0 })
		blob(body, { -4, 0, -7, 3, 6, 6 }, inBody, BLACK)
		local function onBody(y: number, z: number, side: number): { number }
			local x = if side > 0 then 0 else -1
			while inBody(x + side, y, z) do
				x += side
			end
			return { x, y, z }
		end
		for _, blotch in { { 4, -4, 1, YELLOW }, { 3, 0, 1, ORANGE }, { 3, 3, -1, ORANGE }, { 4, -2, -1, YELLOW } } do
			local cell = onBody(blotch[1], blotch[2], blotch[3])
			local top = if inBody(cell[1], cell[2] + 1, cell[3]) then cell[2] + 1 else cell[2]
			local front = if inBody(cell[1], cell[2], cell[3] + 1) and inBody(cell[1], top, cell[3] + 1)
				then cell[3] + 1
				else cell[3]
			body:paint(cell[1], cell[2], cell[3], cell[1], top, front, blotch[4])
		end
		for _, spot in { { -2, -5, 0, -4, YELLOW }, { 0, -2, 1, 0, ORANGE }, { -2, 2, -1, 4, YELLOW } } do
			body:paint(spot[1], 4, spot[2], spot[3], 4, spot[4], spot[5])
		end
		body:paint(-2, 1, -3, 1, 1, 3, BELLY)

		-- A wide flat head with bulging golden eyes, a broad smile, and feathery gills of fire fanning out behind.
		local head = pet:limb("Head", { 0, 3, 6 })
		head:box(-3, 1, 6, 2, 5, 9, BLACK)
		head:box(-2, 1, 10, 1, 4, 11, BLACK)
		head:paint(-2, 2, 11, 1, 2, 11, MOUTH)
		head:paintPair(2, 2, 9, 2, 2, 9, MOUTH)
		head:paint(-2, 4, 11, 1, 4, 11, BLACK_LIGHT)
		head:boxPair(1, 6, 8, 2, 6, 9, BLACK)
		head:paintPair(1, 6, 9, 2, 6, 9, IRIS, NEON)
		head:paintPair(2, 6, 9, 2, 6, 9, EYE)
		head:paint(-1, 5, 7, 0, 5, 9, YELLOW)
		-- Each gill runs out from the head in three steps, from red at the root to yellow at the tip.
		for _, gill in
			{
				{ { 3, 5, 7, 4, 5, 7 }, { 5, 6, 7, 6, 6, 7 }, { 7, 7, 7, 7, 8, 7 } },
				{ { 3, 4, 6, 4, 4, 6 }, { 5, 4, 5, 6, 4, 5 }, { 7, 4, 4, 8, 4, 4 } },
				{ { 3, 3, 7, 4, 3, 7 }, { 5, 2, 7, 6, 2, 7 }, { 7, 1, 7, 7, 1, 7 } },
			}
		do
			for step, color in { FLAME, ORANGE, YELLOW } do
				local b = gill[step]
				head:boxPair(b[1], b[2], b[3], b[4], b[5], b[6], color, NEON)
			end
		end

		-- Short legs splayed out to the sides, with yellow-tipped toes.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 3, 3 }, function(leg)
			leg:box(3, 2, 2, 4, 3, 4, BLACK)
			leg:box(5, 0, 2, 6, 2, 4, BLACK)
			leg:box(5, 0, 5, 6, 0, 5, BLACK)
			leg:paint(5, 0, 5, 6, 0, 5, YELLOW)
			leg:paint(4, 3, 3, 4, 3, 3, ORANGE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 3, -4 }, function(leg)
			leg:box(3, 2, -5, 4, 3, -3, BLACK)
			leg:box(5, 0, -6, 6, 2, -4, BLACK)
			leg:box(5, 0, -3, 6, 0, -3, BLACK)
			leg:paint(5, 0, -3, 6, 0, -3, YELLOW)
			leg:paint(5, 2, -5, 5, 2, -5, ORANGE)
		end)

		-- A long tail, swinging to one side, banded yellow and burning at the tip.
		local tail = pet:limb("Tail", { 0, 3, -6 })
		local t = tube(tail, {
			{ 0, 3, -6, 1.6 },
			{ 0.5, 2.5, -9, 1.4 },
			{ 2, 2, -12, 1.1 },
			{ 3.5, 1.5, -14.5, 0.9 },
			{ 3, 1.5, -17, 0.7 },
			{ 1.5, 1.5, -18.5, 0.5 },
		}, BLACK)
		for index, cube in t.cubes do
			if index > #t.cubes - 2 then
				tail:paint(cube[1], cube[2], cube[3], cube[4], cube[5], cube[6], FLAME, NEON)
			elseif index % 4 == 2 and index > 2 then
				tail:paint(cube[1], cube[2], cube[3], cube[4], cube[5], cube[6], YELLOW)
			end
		end
		local tip = t.cubes[#t.cubes]
		tail:box(tip[1], tip[5] + 1, tip[3], tip[1], tip[5] + 2, tip[3], ORANGE, NEON)
		tail:box(tip[1], tip[5] + 3, tip[3], tip[1], tip[5] + 3, tip[3], YELLOW, NEON)

		pet:light(FLAME, 1.8, 12)
		pet:seat(0, 6, -1)
	end,
}

Designs.Chimera = {
	name = "Chimera",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local LION = rgb(226, 162, 72)
		local LION_LIGHT = rgb(244, 204, 132)
		local LION_DARK = rgb(196, 128, 50)
		local MANE = rgb(184, 92, 38)
		local MANE_DARK = rgb(140, 62, 28)
		local NOSE = rgb(90, 50, 40)
		local GOAT = rgb(112, 98, 88)
		local GOAT_LIGHT = rgb(150, 136, 124)
		local GOAT_DARK = rgb(78, 68, 62)
		local HORN = rgb(190, 180, 168)
		local HORN_DARK = rgb(130, 120, 112)
		local SNAKE = rgb(74, 150, 72)
		local SNAKE_DARK = rgb(46, 104, 50)
		local FANG = rgb(250, 246, 236)
		local FIRE = rgb(255, 120, 30)
		local FLAME = rgb(255, 200, 50)
		local AMBER = rgb(255, 176, 40)
		local VENOM = rgb(200, 255, 60)
		local TONGUE = rgb(230, 40, 60)

		-- A lion's body, deep in the chest and narrow at the waist.
		local body = pet:limb("Body", { 0, 8, -2 })
		body:box(-4, 6, -1, 3, 12, 2, LION)
		body:box(-3, 6, -7, 2, 11, -2, LION)
		body:box(-4, 6, -10, 3, 11, -8, LION)
		body:paint(-3, 6, -7, 2, 6, -2, LION_LIGHT)
		body:paint(-4, 6, -1, 3, 6, 2, LION_LIGHT)
		body:paintPair(3, 9, -10, 3, 10, -9, LION_DARK)
		body:paintPair(2, 8, -6, 2, 9, -4, LION_DARK)

		-- A goat's head rising from the middle of its back, on a shaggy neck, with long swept horns.
		body:box(-2, 12, -7, 1, 13, -3, GOAT_DARK)
		body:box(-1, 14, -6, 0, 15, -4, GOAT)
		body:box(-2, 16, -6, 1, 19, -2, GOAT)
		body:box(-1, 16, -1, 0, 18, 0, GOAT_LIGHT)
		body:paint(-1, 18, 0, 0, 18, 0, NOSE)
		body:box(-1, 14, -1, 0, 15, -1, GOAT_DARK)
		body:paintPair(1, 18, -3, 1, 18, -3, AMBER, NEON)
		body:paintPair(1, 18, -3, 1, 18, -3, EYE)
		body:boxPair(2, 18, -5, 3, 18, -4, GOAT)
		body:boxPair(1, 20, -4, 1, 20, -3, HORN)
		body:boxPair(2, 21, -6, 2, 21, -4, HORN)
		body:boxPair(3, 21, -9, 3, 21, -7, HORN_DARK)
		body:boxPair(3, 20, -10, 3, 20, -10, HORN_DARK)

		-- The lion's head: a great shaggy mane, glowing eyes under a heavy brow, and jaws open on a mouthful of fire.
		local head = pet:limb("Head", { 0, 11, 5 })
		head:box(-5, 8, 3, 4, 16, 5, MANE)
		head:box(-4, 7, 3, 3, 17, 5, MANE)
		head:boxPair(5, 10, 3, 5, 14, 4, MANE_DARK)
		head:box(-3, 18, 3, 2, 18, 4, MANE_DARK)
		head:box(-2, 6, 3, 1, 6, 5, MANE_DARK)
		head:boxPair(3, 18, 4, 4, 19, 4, LION)
		head:paintPair(3, 18, 4, 3, 18, 4, NOSE)
		head:box(-3, 9, 6, 2, 16, 9, LION)
		head:box(-3, 15, 10, 2, 15, 10, LION_DARK)
		head:box(-2, 11, 10, 1, 13, 12, LION_LIGHT)
		head:box(-1, 12, 13, 0, 13, 13, NOSE)
		head:box(-2, 7, 9, 1, 8, 9, LION)
		head:box(-2, 7, 10, 1, 8, 12, LION_LIGHT)
		head:paint(-2, 9, 9, 1, 10, 9, FIRE, NEON)
		head:boxPair(1, 10, 12, 1, 10, 12, FANG)
		head:boxPair(1, 9, 11, 1, 9, 11, FANG)
		head:box(-1, 9, 13, 0, 10, 14, FIRE, NEON)
		head:box(-1, 9, 15, 0, 9, 16, FLAME, NEON)
		head:paintPair(1, 14, 9, 2, 14, 9, AMBER, NEON)
		head:paintPair(1, 14, 9, 1, 14, 9, EYE)
		head:paintPair(2, 12, 9, 2, 13, 9, LION_DARK)

		-- Powerful lion legs on broad paws.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 7, 2 }, function(leg)
			leg:box(2, 1, 1, 4, 6, 3, LION)
			leg:box(2, 0, 1, 4, 0, 4, LION_LIGHT)
			leg:paint(2, 0, 4, 4, 0, 4, LION_DARK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 8, -8.5 }, function(leg)
			leg:box(2, 4, -10, 4, 9, -7, LION)
			leg:box(2, 1, -9, 3, 3, -8, LION)
			leg:box(2, 0, -9, 4, 0, -7, LION_LIGHT)
		end)

		-- Its tail is a serpent, rearing up behind with its hood spread and its tongue flicking.
		local tail = pet:limb("Tail", { 0, 10, -10 })
		local snake = tube(tail, {
			{ 0, 10, -10.5, 1.2 },
			{ 0, 11, -13, 1.1 },
			{ 0, 14, -15, 1 },
			{ 0, 17, -15.5, 1 },
			{ 0, 19, -14.5, 1 },
		}, SNAKE)
		for index, cube in snake.cubes do
			if index % 3 == 2 then
				tail:paint(cube[1], cube[2], cube[3], cube[4], cube[5], cube[6], SNAKE_DARK)
			end
		end
		tail:box(-3, 16, -16, 2, 21, -16, SNAKE)
		tail:paint(-3, 16, -16, -3, 21, -16, SNAKE_DARK)
		tail:paint(2, 16, -16, 2, 21, -16, SNAKE_DARK)
		tail:box(-2, 18, -19, 1, 20, -17, SNAKE)
		tail:box(-1, 18, -21, 0, 19, -20, SNAKE)
		tail:paint(-2, 20, -19, 1, 20, -17, SNAKE_DARK)
		tail:paintPair(1, 19, -18, 1, 19, -18, VENOM, NEON)
		tail:boxPair(0, 17, -21, 0, 17, -21, FANG)
		tail:box(-1, 18, -23, 0, 18, -22, TONGUE)
		tail:boxPair(1, 18, -24, 1, 18, -24, TONGUE)

		pet:light(FIRE, 2, 14)
		pet:particles("Embers", FLAME, 8)
		pet:seat(0, 13, 0)
	end,
}

Designs.LavaGolem = {
	name = "Lava Golem",
	skeleton = "Biped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local ROCK = rgb(74, 64, 62)
		local ROCK_LIGHT = rgb(110, 98, 94)
		local ROCK_DARK = rgb(52, 44, 44)
		local LAVA = rgb(255, 112, 24)
		local LAVA_HOT = rgb(255, 196, 40)

		-- A body of heavy slabs of rock round a core of molten lava, which glows out through every crack between
		-- them, hottest at its heart.
		local body = pet:limb("Body", { 0, 9, 0 })
		body:box(-4, 8, -2, 3, 16, 2, LAVA, NEON)
		body:paint(-1, 13, 2, -1, 14, 2, LAVA_HOT, NEON)
		body:box(0, 12, 3, 4, 16, 4, ROCK)
		body:box(-5, 11, 3, -2, 15, 4, ROCK_LIGHT)
		body:box(-4, 8, 3, 3, 10, 4, ROCK_DARK)
		body:box(-5, 8, -4, -1, 13, -3, ROCK)
		body:box(1, 9, -4, 4, 16, -3, ROCK_LIGHT)
		body:box(-5, 15, -4, -1, 16, -3, ROCK_DARK)
		body:box(4, 8, -2, 5, 11, 2, ROCK_DARK)
		body:box(4, 13, -2, 5, 16, 2, ROCK)
		body:box(-6, 8, -2, -5, 12, 2, ROCK)
		body:box(-6, 14, -2, -5, 16, 2, ROCK_LIGHT)
		body:box(-5, 17, -3, 4, 17, 3, ROCK_DARK)
		body:box(-4, 7, -2, 3, 7, 2, ROCK_DARK)
		body:paint(2, 14, 4, 2, 16, 4, LAVA, NEON)
		body:paint(3, 13, 4, 3, 13, 4, LAVA, NEON)
		body:paint(-4, 13, 4, -3, 13, 4, LAVA, NEON)
		body:paint(5, 9, 2, 5, 10, 2, LAVA, NEON)
		body:paint(-3, 10, 4, -3, 10, 4, LAVA, NEON)
		body:paint(-5, 12, 3, -5, 13, 3, ROCK)
		body:paint(1, 15, -4, 2, 16, -4, ROCK_DARK)
		body:paint(-3, 11, -4, -3, 12, -4, LAVA, NEON)
		-- A ridge of rocks down its back.
		body:box(-1, 14, -5, 0, 17, -5, ROCK_DARK)
		body:box(-1, 10, -5, 0, 12, -5, ROCK)
		body:box(-1, 13, -5, 0, 13, -5, LAVA, NEON)

		-- A small head sunk between the shoulders, with burning eyes and mouth, under a crown of molten spikes
		-- that drips down its face.
		local head = pet:limb("Head", { 0, 18, 0 })
		head:box(-2, 18, -1, 1, 21, 2, ROCK)
		head:box(-3, 21, 3, 2, 21, 3, ROCK_DARK)
		head:paintPair(1, 20, 2, 1, 20, 2, LAVA_HOT, NEON)
		head:paint(-1, 18, 2, 0, 18, 2, LAVA, NEON)
		head:paintPair(1, 19, -1, 1, 21, -1, LAVA, NEON)
		head:box(-2, 22, -1, 1, 22, 2, LAVA, NEON)
		head:boxPair(1, 23, -1, 1, 24, -1, LAVA_HOT, NEON)
		head:boxPair(1, 23, 2, 1, 23, 2, LAVA_HOT, NEON)
		head:box(-1, 23, 2, 0, 25, 2, LAVA_HOT, NEON)
		head:box(-1, 23, -1, 0, 23, -1, LAVA_HOT, NEON)

		-- Huge boulder shoulders and long arms ending in fists that nearly drag on the ground, glowing at the joints.
		pet:limbPair("LeftArm", "RightArm", { 6, 16, 0 }, function(arm)
			arm:box(6, 14, -3, 10, 19, 3, ROCK_LIGHT)
			arm:paint(6, 16, 3, 10, 16, 3, LAVA, NEON)
			arm:paint(10, 15, -3, 10, 17, -3, LAVA, NEON)
			arm:box(7, 20, -2, 9, 21, 1, ROCK)
			arm:box(8, 22, -1, 8, 22, 0, ROCK_DARK)
			arm:box(11, 15, -2, 11, 18, 1, ROCK_DARK)
			arm:paint(7, 20, 1, 9, 20, 1, LAVA, NEON)
			arm:paint(11, 16, 1, 11, 17, 1, LAVA, NEON)
			arm:paint(6, 18, -3, 7, 19, -3, ROCK)
			arm:box(11, 6, -1, 11, 7, 1, ROCK)
			arm:paint(10, 6, 2, 10, 7, 2, LAVA, NEON)
			arm:box(7, 10, -1, 9, 13, 1, ROCK)
			arm:box(7, 9, -1, 9, 9, 1, LAVA, NEON)
			arm:box(6, 5, -2, 10, 8, 2, ROCK_DARK)
			arm:box(7, 4, -1, 9, 4, 1, LAVA, NEON)
			arm:box(6, 1, -2, 10, 3, 3, ROCK)
			arm:paint(6, 2, 3, 10, 2, 3, LAVA, NEON)
			arm:paint(10, 1, 0, 10, 2, 0, LAVA, NEON)
			arm:box(6, 2, 4, 7, 3, 4, ROCK_LIGHT)
			arm:box(9, 2, 4, 10, 3, 4, ROCK_LIGHT)
			arm:box(8, 3, 4, 8, 3, 4, ROCK_LIGHT)
		end)

		-- Short, massive legs on wide feet of rock.
		pet:limbPair("LeftLeg", "RightLeg", { 2.5, 7, 0 }, function(leg)
			leg:box(1, 3, -2, 4, 6, 2, ROCK)
			leg:paint(1, 3, 2, 4, 3, 2, LAVA, NEON)
			leg:box(0, 0, -2, 4, 2, 3, ROCK_DARK)
			leg:paint(0, 0, 3, 4, 1, 3, ROCK)
			leg:paint(2, 1, 3, 2, 1, 3, LAVA, NEON)
			leg:box(1, 5, 3, 4, 6, 3, ROCK_LIGHT)
			leg:paint(2, 5, 3, 3, 5, 3, LAVA, NEON)
		end)

		pet:light(LAVA, 2.2, 16)
		pet:particles("Embers", LAVA_HOT, 10)
		pet:seat(0, 18, -3)
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
		local function look(r: number, g: number, b: number, material: string?): Look
			return { color = rgb(r, g, b), material = material }
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
	hover = 2,
	scale = 0.45 * 1.4,
	draw = function(pet)
		-- Modelled in finer units than it is built in: 1.4 of them to a block.
		local U = 1.4
		local function at(p: { number }): { number }
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local function look(r: number, g: number, b: number, material: string?): Look
			return { color = rgb(r, g, b), material = material }
		end
		local CRIMSON = look(186, 24, 32)
		local CRIMSON_DARK = look(112, 12, 22)
		local BREAST = look(255, 168, 52)
		local BREAST_DARK = look(214, 104, 30)
		local GILT = look(255, 200, 70)
		local GILT_DARK = look(196, 132, 30)
		local TALON = look(48, 26, 28)
		local EMBER = look(255, 66, 22, NEON)
		local FLAME = look(255, 132, 30, NEON)
		local GOLD = look(255, 206, 60, NEON)
		local ETERNAL = look(150, 255, 245, NEON)
		local ETERNAL_DEEP = look(60, 200, 236, NEON)
		local HOT = look(255, 236, 140, NEON)

		-- A plume of fire along a path: each stretch of it in a colour, from the root out (each band ends at a
		-- fraction of the way along).
		local function plume(s: Sculpt, points: { { number } }, bands: { { any } }, frame: Frame?, flat: number?)
			local lengths, total = { 0 }, 0
			for index = 2, #points do
				local a, b = points[index - 1], points[index]
				total += math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
				lengths[index] = total
			end
			local function pointAt(f: number): { number }
				local d = f * total
				for index = 2, #points do
					if d <= lengths[index] or index == #points then
						local a, b = points[index - 1], points[index]
						local span = lengths[index] - lengths[index - 1]
						local t = if span > 0 then math.clamp((d - lengths[index - 1]) / span, 0, 1) else 0
						return {
							a[1] + (b[1] - a[1]) * t,
							a[2] + (b[2] - a[2]) * t,
							a[3] + (b[3] - a[3]) * t,
							a[4] + (b[4] - a[4]) * t,
						}
					end
				end
				return points[#points]
			end
			local from = 0
			for _, band in bands do
				local to = band[2]
				local part = { pointAt(from) }
				for index = 2, #points - 1 do
					local f = lengths[index] / total
					if f > from and f < to then
						table.insert(part, points[index])
					end
				end
				table.insert(part, pointAt(to))
				s:add(if flat then flatten(rod(part), points[1][3], flat) else rod(part), band[1], frame)
				from = to
			end
		end
		local BURN = { { CRIMSON, 0.25 }, { EMBER, 0.45 }, { FLAME, 0.65 }, { GOLD, 0.86 }, { ETERNAL, 1 } }
		local LICK = { { EMBER, 0.4 }, { FLAME, 0.75 }, { HOT, 1 } }

		-- A body leaning forward to strike, crimson over a golden breast, with a heart of eternal fire burning in
		-- its chest, and behind it a halo of eternal fire ringed with flames.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 0, 0 }, { 5.2, 7.2, 5.6 }), CRIMSON, { origin = { 0, 17, -1 }, pitch = -0.35 })
		body:paint(ellipsoid({ 0, 15, 3.5 }, { 4.8, 6.2, 3.4 }), BREAST, nil, true)
		for _, y in { 11.5, 14.5, 17.5 } do
			body:paint(
				rod({ { -4.5, y + 1, 1.5, 0.6 }, { 0, y, 5.5, 0.6 }, { 4.5, y + 1, 1.5, 0.6 } }),
				BREAST_DARK,
				nil,
				true
			)
		end
		body:add(ellipsoid({ 0, 17, 4.4 }, { 1.6, 1.9, 1.1 }), ETERNAL)
		body:paint(ellipsoid({ 0, 17, 4.2 }, { 2.6, 2.9, 1.2 }), GILT, nil, true)
		body:add(ellipsoid({ 0, 17, 4.6 }, { 1.4, 1.7, 1 }), ETERNAL)
		local halo = { 0, 26, -8.5 }
		body:add(
			shape(halo, 14, function(x, y, z)
				local r = math.sqrt(x * x + (y - halo[2]) ^ 2)
				return math.abs(r - 12.5) <= 1.4 and math.abs(z - halo[3]) <= 0.8
			end),
			ETERNAL_DEEP
		)
		body:paint(
			shape(halo, 14, function(x, y, z)
				local r = math.sqrt(x * x + (y - halo[2]) ^ 2)
				return math.abs(r - 12.5) <= 0.6 and z >= halo[3]
			end),
			ETERNAL
		)
		for a = 0, 330, 30 do
			if a < 230 or a > 310 then
				local c, s = math.cos(math.rad(a)), math.sin(math.rad(a))
				local long = if a % 60 == 0 then 5 else 3
				plume(body, {
					{ c * 13.5, halo[2] + s * 13.5, halo[3], 1.1 },
					{ c * (13.8 + long), halo[2] + s * (13.8 + long), halo[3], 0.3 },
				}, if a % 60 == 0 then { { ETERNAL, 0.45 }, { GOLD, 1 } } else { { GOLD, 1 } }, nil, 1.6)
			end
		end
		-- The halo is held to its back by a stream of fire.
		plume(body, { { 0, 13.5, -5.5, 1.4 }, { 0, 13.2, -8.5, 1.1 } }, { { FLAME, 1 } })

		-- A long neck ruffed with flame feathers, and a raptor's head thrust forward: horned brows, slanted eyes
		-- burning eternal blue, a hooked golden beak open on a throat of fire, and a blazing crown of plumes.
		local head = newSculpt(U)
		head:add(rod({ { 0, 23, 2, 3.3 }, { 0, 26.5, 5.5, 2.7 }, { 0, 29, 8.5, 2.3 } }), CRIMSON)
		for _, s in { 1, -1 } do
			plume(head, { { 2 * s, 25, 3.5, 1.1 }, { 4.6 * s, 26.5, -1, 0.7 }, { 5.6 * s, 28, -4, 0.3 } }, LICK)
			plume(head, { { 1.6 * s, 22.5, 1.5, 1 }, { 4.2 * s, 23, -2.5, 0.6 }, { 5 * s, 24, -5, 0.3 } }, LICK)
		end
		local face = { origin = { 0, 29.5, 10.5 }, pitch = -0.2 }
		-- The head is drawn at 1.3 times the size of the numbers below.
		local H = 1.3
		local function E(c: { number }, r: { number }): Shape
			return ellipsoid({ c[1] * H, c[2] * H, c[3] * H }, { r[1] * H, r[2] * H, r[3] * H })
		end
		local function scaled(points: { { number } }): { { number } }
			local out = {}
			for _, p in points do
				table.insert(out, { p[1] * H, p[2] * H, p[3] * H, p[4] * H })
			end
			return out
		end
		local function R(points: { { number } }): Shape
			return rod(scaled(points))
		end
		head:add(E({ 0, 0, 0 }, { 3, 2.8, 3.6 }), CRIMSON, face)
		head:add(E({ 0, 1.4, 1.8 }, { 3.1, 0.9, 1.6 }), CRIMSON_DARK, face)
		head:add(
			R({ { 0, 0, 2.4, 1.6 }, { 0, -0.4, 5.5, 1.2 }, { 0, -1.4, 7.2, 0.8 }, { 0, -2.8, 7.6, 0.45 } }),
			GILT,
			face
		)
		head:add(R({ { 0, -1.4, 7.2, 0.7 }, { 0, -2.8, 7.6, 0.45 } }), GILT_DARK, face)
		head:add(R({ { 0, -1.8, 2.5, 1.2 }, { 0, -3, 5.2, 0.7 } }), GILT, face)
		head:carve(E({ 0, -1.6, 4.6 }, { 1, 0.65, 2.3 }), face)
		head:add(E({ 0, -1.6, 3 }, { 0.9, 0.6, 0.8 }), FLAME, face)
		for _, s in { 1, -1 } do
			head:add(R({ { 1.2 * s, 0.45, 3.3, 0.7 }, { 2.7 * s, 1.05, 2.4, 0.7 } }), ETERNAL, face)
			head:add(
				R({ { 1.8 * s, 1.6, 2.2, 0.8 }, { 3 * s, 3.4, -1.5, 0.5 }, { 3.4 * s, 4.6, -3.5, 0.25 } }),
				CRIMSON_DARK,
				face
			)
			plume(
				head,
				scaled({ { 2.4 * s, -0.6, 0, 0.9 }, { 3.8 * s, 0.4, -4, 0.6 }, { 4.4 * s, 1.4, -6.5, 0.3 } }),
				LICK,
				face
			)
		end
		for _, crest in { { 0, 9 }, { 1.7, 8 }, { -1.7, 8 }, { 3, 6.5 }, { -3, 6.5 } } do
			local x, tall = crest[1], crest[2]
			plume(
				head,
				scaled({
					{ x * 0.6, 2, 0.2, 0.75 },
					{ x * 1.1, 2 + tall * 0.5, -2.8, 0.55 },
					{ x * 1.6, 2 + tall * 0.85, -6.8, 0.25 },
				}),
				BURN,
				face
			)
		end

		-- Wings raised and burning: flames lick up from their leading edges, and every feather burns from
		-- crimson at the root through flame and gold to a tip of eternal blue, the longest at the wingtips.
		local wing = newSculpt(U)
		local arm = { { 4.5, 22, -1, 2.4 }, { 11, 28.5, -2, 1.9 }, { 17.5, 33.5, -3, 1.4 }, { 25, 37, -4.2, 0.8 } }
		local function armAt(x: number): (number, number)
			for index = 2, #arm do
				local a, b = arm[index - 1], arm[index]
				if x <= b[1] or index == #arm then
					local t = math.clamp((x - a[1]) / (b[1] - a[1]), 0, 1)
					return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
				end
			end
			return arm[#arm][2], arm[#arm][3]
		end
		-- Broad flame-shaped feathers, each overlapping the next: four along the arm, four longer ones fanning out
		-- from the tip.
		for index, feather in
			{
				{ 6.5, 10 },
				{ 9.5, 11 },
				{ 12.5, 12 },
				{ 15, 13 },
				{ 17, 14.5 },
				{ 19.5, 16 },
				{ 22, 17 },
				{ 24.2, 15.5 },
			}
		do
			local x, length = feather[1], feather[2]
			local y, z = armAt(x)
			local spread = if index > 4 then (index - 4) * 1.3 else 0
			local back = if index % 2 == 0 then -0.9 else 0
			plume(wing, {
				{ x, y - 0.5, z + back, 1.4 },
				{ x + spread * 0.4, y - length * 0.45, z - 0.8 + back, 2 },
				{ x + spread * 0.75, y - length * 0.8, z - 1.3 + back, 1.1 },
				{ x + spread, y - length, z - 1.6 + back, 0.35 },
			}, BURN, nil, 2.2)
		end
		for _, c in { { 9, 24.8, -2, 3.4, 2.4 }, { 15, 29.8, -2.8, 3.4, 2.4 }, { 20, 33.2, -3.5, 3, 2 } } do
			wing:add(ellipsoid({ c[1], c[2], c[3] }, { c[4], c[5], 1.4 }), CRIMSON)
		end
		wing:add(rod(arm), CRIMSON_DARK)
		for _, x in { 8, 12.5, 17, 21, 24.5 } do
			local y, z = armAt(x)
			local tall = if x == 12.5 or x == 21 then 7 else 5
			plume(
				wing,
				{ { x, y + 0.5, z, 1.4 }, { x - 0.6, y + tall * 0.55, z - 1, 0.9 }, { x - 1.4, y + tall, z - 2, 0.25 } },
				LICK,
				nil,
				1.6
			)
		end

		-- Golden legs with great dark talons, reaching forward to strike.
		local leg = newSculpt(U)
		leg:add(ellipsoid({ 2.8, 9.5, 1 }, { 2.6, 4, 3 }), CRIMSON)
		plume(
			leg,
			{ { 2.8, 7, 2.5, 1.6 }, { 3, 5, 3.5, 1.2 }, { 3.1, 4, 4.2, 0.5 } },
			{ { CRIMSON, 0.4 }, { EMBER, 0.7 }, { FLAME, 1 } }
		)
		leg:add(rod({ { 3, 5.5, 2.5, 1.1 }, { 3.1, 2.4, 3.5, 0.95 } }), GILT)
		for _, toe in { -1.5, 0, 1.5 } do
			leg:add(rod({ { 3.1, 2, 3.6, 0.8 }, { 3.1 + toe, 1.1, 6, 0.75 } }), GILT)
			leg:add(
				rod({
					{ 3.1 + toe, 1.2, 6.2, 0.7 },
					{ 3.1 + toe * 1.15, 0.9, 7.6, 0.5 },
					{ 3.1 + toe * 1.2, 0.2, 8.2, 0.35 },
				}),
				TALON
			)
		end
		leg:add(rod({ { 3.1, 2, 3, 0.75 }, { 3.1, 1.1, 0.8, 0.65 } }), GILT)
		leg:add(rod({ { 3.1, 1.1, 0.6, 0.6 }, { 3.1, 0.3, -0.8, 0.4 } }), TALON)

		-- A long train of fire streamers, curling up at their ends.
		local tail = newSculpt(U)
		for _, x in { 0, 2.6, -2.6, 5, -5 } do
			local reach = 1 - math.abs(x) / 10
			local points = andThen(
				{
					{ x * 0.2, 12.5, -5, 1.6 },
					{ x * 0.5, 10, -10, 1.3 },
					{ x * 0.8, 7, -16 - 2 * reach, 1 },
					{ x, 5, -21 - 3 * reach, 0.8 },
				},
				curl({
					centre = { x, 7.6, -21 - 3 * reach },
					plane = { 3, 2 },
					from = -math.pi / 2,
					turns = -0.7,
					radius = { 2.6, 1.2 },
					width = { 0.8, 0.45 },
				})
			)
			plume(tail, points, { { CRIMSON, 0.2 }, { EMBER, 0.4 }, { FLAME, 0.6 }, { GOLD, 0.82 }, { ETERNAL, 1 } })
		end

		local mirroredWing, mirroredLeg = wing:mirror(), leg:mirror()
		body:draw(pet:limb("Body", at({ 0, 17, -1 })), { head, wing, mirroredWing, leg, mirroredLeg, tail }, CRIMSON)
		head:draw(pet:limb("Head", at({ 0, 27, 6 })), { body, wing, mirroredWing }, CRIMSON)
		pet:limbPair("LeftWing", "RightWing", at({ 4.5, 22, -1 }), function(limb)
			wing:draw(limb, { body, head }, CRIMSON)
		end)
		pet:limbPair("LeftLeg", "RightLeg", at({ 2.6, 11, 0.5 }), function(limb)
			leg:draw(limb, { body }, CRIMSON)
		end)
		tail:draw(pet:limb("Tail", at({ 0, 12.5, -5 })), { body }, CRIMSON)

		pet:light(rgb(150, 255, 245), 3.4, 28)
		pet:particles("Embers", rgb(255, 206, 60), 18)
		pet:seat(0, 26 / U, -4 / U)
	end,
}

return Designs
