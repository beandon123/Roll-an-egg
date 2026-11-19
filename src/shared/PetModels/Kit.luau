--!strict
-- The toolkit pet designs are drawn with (see PetModels/Designs and the zone files beside it):
--     limb:box() draws a solid block, limb:paint() colours the surface of blocks already drawn (eyes, bellies),
--     and the ...Pair versions mirror across the middle of the pet.
-- Sculpting (`newSculpt`): a limb modelled cell by cell from rounded shapes turned to any angle (`ellipsoid`, `rod`,
-- `curl` for a spiral to end a rod on), coloured by rules (`coat`, `trace`, `bake` for light from above), then packed
-- into blocks. Thin details (horns, claws, fangs, feathers, fins, wings, eyes) are parts at any angle (`blade`,
-- `taper`, `triangle`, `egg`, `feather`, placed in a design's own units with `inUnits`), so they stay crisp however
-- big a pet is shown. `blob` fills a rounded shape from a test function.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.

local Kit = {}
export type Color = { number }
export type Vec = { number }
export type Pet = any
export type Limb = any
export type Design = {
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

-- Points round a curl, for the tip of a tentacle or tail, to follow the points leading up to it in a `rod`.
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

-- How a look is shaded by light from above (see Sculpt.bake): `top` for cells facing up, `under` for cells facing
-- down, and `low` for every cell lower than `below` (design units) that does not face up, such as the shins.
export type Tone = { top: Look?, under: Look?, low: Look?, below: number? }

-- Which way the clay faces at a cell, out from it, worked out from the empty cells round it (so a staircase of
-- cells on a slope faces along the slope, not up). Zero if no side shows.
local function normalAt(self: Sculpt, x: number, y: number, z: number): Vec
	local n = { 0, 0, 0 }
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				if (dx ~= 0 or dy ~= 0 or dz ~= 0) and not self:has(x + dx, y + dy, z + dz) then
					local w = 1 / math.sqrt(dx * dx + dy * dy + dz * dz)
					n[1] += dx * w
					n[2] += dy * w
					n[3] += dz * w
				end
			end
		end
	end
	local length = math.sqrt(n[1] * n[1] + n[2] * n[2] + n[3] * n[3])
	if length < 1e-6 then
		return { 0, 0, 0 }
	end
	return { n[1] / length, n[2] / length, n[3] / length }
end

-- Bakes light from above into the clay, the way the showpiece pets are shaded: each showing cell of a look in
-- `tones` takes that look's top tone where the surface faces well up, its under tone where it faces down, and its
-- low tone if it sits low down. Call it after every other colouring, so patterns get shaded too.
function Sculpt.bake(self: Sculpt, tones: { [Look]: Tone })
	local unit = self.unit
	local changes = {}
	for key, current in self.cells do
		local tone = tones[current]
		if tone then
			local x, y, z = cellAt(key)
			if self:showing(x, y, z) then
				local n = normalAt(self, x, y, z)
				if n[2] > 0.62 and tone.top and not self:has(x, y + 1, z) then
					changes[key] = tone.top
				elseif n[2] < -0.45 and tone.under then
					changes[key] = tone.under
				elseif tone.low and tone.below and (y + 0.5) * unit < tone.below then
					changes[key] = tone.low
				end
			end
		end
	end
	for key, look in changes do
		self.cells[key] = look
	end
end

-- The cells of the clay that show, as { point, normal }: the cell's middle (design units) and which way it faces,
-- out from the clay (worked out from the empty cells round it). `keep(point, normal)` picks which to return.
-- Designs use it to set spikes, quills, tufts of fur and moss over a surface.
function Sculpt.surface(self: Sculpt, keep: ((Vec, Vec) -> boolean)?): { { Vec } }
	local unit = self.unit
	local keys = {}
	for key in self.cells do
		table.insert(keys, key)
	end
	table.sort(keys)
	local out = {}
	for _, key in keys do
		local x, y, z = cellAt(key)
		if self:showing(x, y, z) then
			local normal = normalAt(self, x, y, z)
			if normal[1] ~= 0 or normal[2] ~= 0 or normal[3] ~= 0 then
				local point = { (x + 0.5) * unit, (y + 0.5) * unit, (z + 0.5) * unit }
				if keep == nil or keep(point, normal) then
					table.insert(out, { point, normal })
				end
			end
		end
	end
	return out
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

-- Soft noise from 0 to 1 that changes smoothly over about `size` design units: for patches (moss, dapples, grizzled
-- fur) rather than the speckle `noise` gives.
local function patches(p: Vec, size: number): number
	local x, y, z = p[1] / size, p[2] / size, p[3] / size
	local x0, y0, z0 = math.floor(x), math.floor(y), math.floor(z)
	local fx, fy, fz = x - x0, y - y0, z - z0
	fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
	local function at(i: number, j: number, k: number): number
		return noise({ x0 + i, y0 + j, z0 + k })
	end
	local function mix(a: number, b: number, t: number): number
		return a + (b - a) * t
	end
	return mix(
		mix(mix(at(0, 0, 0), at(1, 0, 0), fx), mix(at(0, 1, 0), at(1, 1, 0), fx), fy),
		mix(mix(at(0, 0, 1), at(1, 0, 1), fx), mix(at(0, 1, 1), at(1, 1, 1), fx), fy),
		fz
	)
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

-- How far a point is from the middle line of a rod's points { x, y, z, radius }, and the rod's radius there: so a
-- design can colour the outside of a tail or trunk (its fringe) differently from the inside.
local function nearPath(points: { { number } }, p: Vec): (number, number)
	local best, radius = math.huge, 0
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local ab = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
		local length = ab[1] * ab[1] + ab[2] * ab[2] + ab[3] * ab[3]
		local t = 0
		if length > 0 then
			t = math.clamp(((p[1] - a[1]) * ab[1] + (p[2] - a[2]) * ab[2] + (p[3] - a[3]) * ab[3]) / length, 0, 1)
		end
		local dx, dy, dz = a[1] + ab[1] * t - p[1], a[2] + ab[2] * t - p[2], a[3] + ab[3] * t - p[3]
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		if d < best then
			best, radius = d, a[4] + (b[4] - a[4]) * t
		end
	end
	return best, radius
end

-- Points about every `step` design units along a path of { x, y, z, radius }: each { position, radius, direction }.
local function alongPath(points: { { number } }, step: number): { { any } }
	local out = {}
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local run = vsub(b, a)
		local count = math.max(1, math.ceil(vlength(run) / step))
		for k = 0, count - 1 do
			local t = k / count
			table.insert(out, { vlerp(a, b, t), a[4] + (b[4] - a[4]) * t, vnorm(run) })
		end
	end
	local last, before = points[#points], points[#points - 1]
	table.insert(out, { { last[1], last[2], last[3] }, last[4], vnorm(vsub(last, before)) })
	return out
end

----------------------------------------------------------------------------------------------------------------
-- Touches shared by the showpiece pets

-- A glossy round eye set into the side of a sculpted head at (y, z), `size` across: a dark iris ringed in `ring`,
-- with a big glint and a small one. `material` "Neon" makes the iris glow.
local function glossyEye(
	limb: Limb,
	T: any,
	s: Sculpt,
	y: number,
	z: number,
	size: number,
	ring: { number }?,
	iris: { number }?,
	material: string?,
	pupil: { number }?
)
	local x = sideOf(s, y, z)
	for _, side in { 1, -1 } do
		if ring then
			T.ball(limb, { (x - size * 0.2) * side, y, z }, { size * 0.5, size * 1.12, size * 1.12 }, ring)
		end
		T.ball(limb, { (x - size * 0.1) * side, y, z }, { size * 0.5, size, size }, iris or EYE, material)
		if pupil then
			T.ball(
				limb,
				{ (x + size * 0.02) * side, y, z + size * 0.05 },
				{ size * 0.32, size * 0.62, size * 0.42 },
				pupil
			)
		end
		T.ball(
			limb,
			{ (x + size * 0.1) * side, y + size * 0.22, z + size * 0.18 },
			{ size * 0.2, size * 0.3, size * 0.3 },
			SHINE
		)
		T.ball(
			limb,
			{ (x + size * 0.08) * side, y - size * 0.2, z - size * 0.18 },
			{ size * 0.12, size * 0.14, size * 0.14 },
			SHINE
		)
	end
end

-- Wisps of fur standing out of a surface: thin tapers from points on it, along (roughly) its normals, bent by
-- `lean`, `length` long. `pick(point, normal)` chooses where; `color` can depend on the point.
local function fur(
	limb: Limb,
	T: any,
	s: Sculpt,
	pick: (Vec, Vec) -> boolean,
	length: number,
	width: number,
	lean: Vec,
	color: (Vec) -> { number }
)
	for _, spot in s:surface(pick) do
		local p, n = spot[1], spot[2]
		local dir = vnorm(vadd(n, lean))
		local tip = vadd(p, vscale(dir, length * (0.75 + 0.5 * noise(vadd(p, { 3, 1, 7 })))))
		T.taper(limb, vadd(p, vscale(dir, -width * 0.4)), tip, width, width * 0.6, n, color(p))
	end
end

----------------------------------------------------------------------------------------------------------------

Kit.rgb = rgb
Kit.NEON = NEON
Kit.GLASS = GLASS
Kit.EYE = EYE
Kit.SHINE = SHINE
Kit.eyes = eyes
Kit.curl = curl
Kit.andThen = andThen
Kit.mirrorPoints = mirrorPoints
Kit.blob = blob
Kit.toWorld = toWorld
Kit.toLocal = toLocal
Kit.ellipsoid = ellipsoid
Kit.rod = rod
Kit.shape = shape
Kit.Sculpt = Sculpt
Kit.cellKey = cellKey
Kit.cellAt = cellAt
Kit.newSculpt = newSculpt
Kit.vadd = vadd
Kit.vsub = vsub
Kit.vscale = vscale
Kit.vlerp = vlerp
Kit.vdot = vdot
Kit.vcross = vcross
Kit.vlength = vlength
Kit.vnorm = vnorm
Kit.squareTo = squareTo
Kit.axesAlong = axesAlong
Kit.blade = blade
Kit.taper = taper
Kit.triangle = triangle
Kit.egg = egg
Kit.feather = feather
Kit.look = look
Kit.noise = noise
Kit.patches = patches
Kit.sideOf = sideOf
Kit.frontOf = frontOf
Kit.bottomOf = bottomOf
Kit.topOf = topOf
Kit.roundEyes = roundEyes
Kit.slitEyes = slitEyes
Kit.inUnits = inUnits
Kit.alongPath = alongPath
Kit.nearPath = nearPath
Kit.glossyEye = glossyEye
Kit.fur = fur

return Kit
