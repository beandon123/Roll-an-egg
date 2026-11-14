--!strict
-- Where everything at the hub is: the start zone, the shop stalls, the fuse machine, the spawn, the eight pens,
-- and the ring of mountains around it all. MapService builds the placeholder hub from this, and anything that needs
-- to know where a station or pen is (opening a shop, pets roaming a pen) reads it from here, never from map parts.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Same coordinates as Shared/Runway: the runway starts at z = 0 and runs toward +z; the hub is behind it, at
-- negative z, centred on x = 0. Positions are on the hub's walking surface (Runway.BASE_Y) unless noted.
--
-- Seen from above, with the runway leaving at the bottom (a player standing on the start zone and looking back
-- into the hub sees it this way round):
--
--     x = -150                                            x = +150
--        +---------------------------------------------------+  z = -260
--        |              [ Pen 4 ]       [ Pen 5 ]            |
--        |  [ Pen 3 ]                               [ Pen 6 ]|
--        |                       spawn                       |
--        |  [ Pen 2 ]        fuse machine           [ Pen 7 ]|
--        |              Trails             Sell              |
--        |  [ Pen 1 ]                               [ Pen 8 ]|
--        +-----------------[  START ZONE  ]------------------+  z = 0
--                          |    runway    |
--
-- Mountains surround the whole hub; the only way out is the runway.

local Runway = require(script.Parent.Runway)

export type Point = { x: number, z: number }

-- A rectangle on the ground, by its centre and size.
export type Rect = { x: number, z: number, sizeX: number, sizeZ: number }

export type Station = {
	key: string,
	-- Shown on the stall's sign and its prompt.
	name: string,
	x: number,
	z: number,
	-- Unit direction the front of the station faces.
	facing: Point,
}

export type Pen = {
	index: number,
	x: number,
	z: number,
	sizeX: number,
	sizeZ: number,
	-- Unit direction from the pen out through its gate, toward the plaza.
	gate: Point,
}

export type Mountain = {
	x: number,
	z: number,
	-- Radius where the mountain meets the hub's ground level (before its shape is roughened).
	groundRadius: number,
	-- Height of the peak above the hub's ground level.
	height: number,
	-- How far below the hub's ground level the mountain's base is buried.
	sink: number,
	sides: number,
	-- Big mountains have a rocky band and, if tall enough, a snowy peak; small ones are grassy hills.
	big: boolean,
	-- Seeds the roughening, so every server builds the same mountain.
	seed: number,
}

export type Band = "Grass" | "Hilltop" | "Rock" | "Snow"

export type Triangle = {
	a: { number },
	b: { number },
	c: { number },
	band: Band,
	-- Brightness multiplier for this face, so neighbouring faces read as separate facets.
	shade: number,
}

local HubLayout = {}

local HALF_WIDTH = Runway.HUB_WIDTH / 2
local LENGTH = Runway.HUB_LENGTH

HubLayout.HALF_WIDTH = HALF_WIDTH
HubLayout.LENGTH = LENGTH

-- The walkable hub ground. Invisible walls run round its edge, leaving only the runway open.
HubLayout.GROUND = { x = 0, z = -LENGTH / 2, sizeX = HALF_WIDTH * 2, sizeZ = LENGTH } :: Rect

-- The pad where the runway leaves the hub.
HubLayout.START_ZONE = { x = 0, z = -12, sizeX = Runway.WIDTH, sizeZ = 24 } :: Rect

HubLayout.SPAWN = { x = 0, z = -160 } :: Point

----------------------------------------------------------------------------------------------------------------
-- Stations

HubLayout.STATIONS = {
	-- Buy trails that boost Max Stamina.
	Trails = { key = "Trails", name = "Trails", x = -40, z = -70, facing = { x = 1, z = 0 } },
	-- Sell eggs (and later pets) you do not want.
	Sell = { key = "Sell", name = "Sell", x = 40, z = -70, facing = { x = -1, z = 0 } },
	-- Fuse three of the same pet into that pet's egg.
	Fuse = { key = "Fuse", name = "Fuse Machine", x = 0, z = -100, facing = { x = 0, z = 1 } },
} :: { [string]: Station }

-- Radius of ground each station stands on (for keeping other things clear of it).
HubLayout.STATION_RADIUS = 14
-- How close a player must be to use a station's prompt.
HubLayout.STATION_REACH = 12
-- How far from a station a player can walk before its panel closes by itself.
HubLayout.STATION_CLOSE_DISTANCE = 26

----------------------------------------------------------------------------------------------------------------
-- Pens: three down each side of the plaza and two at the back, each with its gate facing the plaza.

local SIDE_PEN_X = HALF_WIDTH - 8 - 30 -- 8 studs in from the edge, 60 wide
local BACK_PEN_Z = -LENGTH + 8 + 27 -- 8 studs in from the edge, 54 deep
local ROW_Z = { -42, -102, -162 }

local pens: { Pen } = {}
local function addPen(x: number, z: number, sizeX: number, sizeZ: number, gate: Point)
	table.insert(pens, { index = #pens + 1, x = x, z = z, sizeX = sizeX, sizeZ = sizeZ, gate = gate })
end
-- Left side, front to back.
for _, z in ROW_Z do
	addPen(-SIDE_PEN_X, z, 60, 54, { x = 1, z = 0 })
end
-- Back, left to right.
addPen(-40, BACK_PEN_Z, 64, 54, { x = 0, z = 1 })
addPen(40, BACK_PEN_Z, 64, 54, { x = 0, z = 1 })
-- Right side, back to front.
for index = #ROW_Z, 1, -1 do
	addPen(SIDE_PEN_X, ROW_Z[index], 60, 54, { x = -1, z = 0 })
end

HubLayout.PENS = pens
HubLayout.PEN_GATE_WIDTH = 14

----------------------------------------------------------------------------------------------------------------
-- Geometry helpers

function HubLayout.bounds(rect: Rect): (number, number, number, number)
	return rect.x - rect.sizeX / 2, rect.x + rect.sizeX / 2, rect.z - rect.sizeZ / 2, rect.z + rect.sizeZ / 2
end

-- Distance from a point to the nearest point of a rectangle (0 inside it).
function HubLayout.distanceToRect(x: number, z: number, rect: Rect): number
	local minX, maxX, minZ, maxZ = HubLayout.bounds(rect)
	local dx = math.max(minX - x, 0, x - maxX)
	local dz = math.max(minZ - z, 0, z - maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

function HubLayout.rectsOverlap(a: Rect, b: Rect): boolean
	local aMinX, aMaxX, aMinZ, aMaxZ = HubLayout.bounds(a)
	local bMinX, bMaxX, bMinZ, bMaxZ = HubLayout.bounds(b)
	return aMinX < bMaxX and bMinX < aMaxX and aMinZ < bMaxZ and bMinZ < aMaxZ
end

-- The pen a ground position is inside, if any.
function HubLayout.penAt(x: number, z: number): Pen?
	for _, pen in pens do
		if HubLayout.distanceToRect(x, z, pen :: any) == 0 then
			return pen
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------------------
-- Mountains

-- Ground the mountains must stay off: the hub, and a strip along the runway (wider than it, because the runway
-- runs downhill and a mountain widens toward its base).
HubLayout.MOUNTAIN_KEEP_OUT = {
	HubLayout.GROUND,
	{ x = 0, z = 300, sizeX = Runway.WIDTH + 20, sizeZ = 600 } :: Rect,
}
-- Scenery ground that the mountains stand on, just below the hub's surface and out of reach behind its walls.
-- It stops level with the front of the hub; beside the runway there is only the void the runway crosses.
HubLayout.OUTER_GROUND_FRONT_Z = 0
HubLayout.OUTER_GROUND = {
	x = 0,
	z = -(LENGTH + 340) / 2,
	sizeX = HALF_WIDTH * 2 + 680,
	sizeZ = LENGTH + 340,
} :: Rect
-- Space left between a mountain's foot and the ground it must stay off.
HubLayout.MOUNTAIN_CLEARANCE = 4
-- The largest a mountain's outline is pushed outward when it is roughened.
HubLayout.MOUNTAIN_ROUGHNESS = 0.12

-- Mountains taller than this get a snowy peak.
local SNOW_HEIGHT = 170

-- Lines the mountains are strung along, from the left of the runway, round the back of the hub, to its right.
-- The first ring is the big mountains; the second is smaller hills in front of them.
local RINGS = {
	{
		big = true,
		spacing = 112,
		jitter = 12,
		radius = { 72, 96 },
		height = { 150, 250 },
		sides = 7,
		path = {
			{ x = -(Runway.WIDTH / 2 + 100), z = 150 },
			{ x = -(HALF_WIDTH + 92), z = 40 },
			{ x = -(HALF_WIDTH + 92), z = -(LENGTH + 92) },
			{ x = HALF_WIDTH + 92, z = -(LENGTH + 92) },
			{ x = HALF_WIDTH + 92, z = 40 },
			{ x = Runway.WIDTH / 2 + 100, z = 150 },
		},
	},
	{
		big = false,
		spacing = 70,
		jitter = 8,
		radius = { 34, 46 },
		height = { 45, 85 },
		sides = 6,
		path = {
			{ x = -(Runway.WIDTH / 2 + 46), z = 46 },
			{ x = -(HALF_WIDTH + 48), z = 18 },
			{ x = -(HALF_WIDTH + 48), z = -(LENGTH + 48) },
			{ x = HALF_WIDTH + 48, z = -(LENGTH + 48) },
			{ x = HALF_WIDTH + 48, z = 18 },
			{ x = Runway.WIDTH / 2 + 46, z = 46 },
		},
	},
}

-- A small deterministic random number generator (Park-Miller), so every server builds the same mountains.
-- Products stay below 2^53, so the arithmetic is exact everywhere.
local function newRandom(seed: number): (number?, number?) -> number
	local state = (math.floor(seed) % 2147483646) + 1
	return function(low: number?, high: number?): number
		state = (state * 16807) % 2147483647
		local value = (state - 1) / 2147483646
		if low ~= nil and high ~= nil then
			return low + (high - low) * value
		end
		return value
	end
end

-- Builds the ring of mountains. Called once when this module loads (HubLayout.MOUNTAINS); exposed for tests.
function HubLayout.generateMountains(): { Mountain }
	local random = newRandom(20261114)
	local mountains: { Mountain } = {}

	for _, ring in RINGS do
		-- Spread the mountains evenly along the whole line, so there is one at each end, beside the runway.
		local path = ring.path
		local total = 0
		for index = 1, #path - 1 do
			total += math.sqrt((path[index + 1].x - path[index].x) ^ 2 + (path[index + 1].z - path[index].z) ^ 2)
		end
		local count = math.max(1, math.floor(total / ring.spacing + 0.5))

		for step = 0, count do
			-- Find the point `distance` along the line.
			local distance = total * step / count
			local px, pz = path[#path].x, path[#path].z
			for index = 1, #path - 1 do
				local from, to = path[index], path[index + 1]
				local length = math.sqrt((to.x - from.x) ^ 2 + (to.z - from.z) ^ 2)
				if distance <= length then
					px = from.x + (to.x - from.x) * distance / length
					pz = from.z + (to.z - from.z) * distance / length
					break
				end
				distance -= length
			end

			local x = px + random(-ring.jitter, ring.jitter)
			local z = pz + random(-ring.jitter, ring.jitter)
			local radius = random(ring.radius[1], ring.radius[2])
			local height = random(ring.height[1], ring.height[2])

			-- Shrink any mountain that would spill onto the hub or the runway.
			local room = math.huge
			for _, rect in HubLayout.MOUNTAIN_KEEP_OUT do
				room = math.min(room, HubLayout.distanceToRect(x, z, rect))
			end
			local widest = (room - HubLayout.MOUNTAIN_CLEARANCE) / (1 + HubLayout.MOUNTAIN_ROUGHNESS)
			radius = math.min(radius, widest)

			-- The outer ground (see HubLayout.OUTER_GROUND) hides a shallow base. A mountain that reaches out over
			-- the void beside the runway has no ground under that side, so its base is buried deep instead.
			local reachesVoid = z + radius * (1 + HubLayout.MOUNTAIN_ROUGHNESS) > HubLayout.OUTER_GROUND_FRONT_Z
			local sink = if reachesVoid then 140 else 25

			if radius >= ring.radius[1] * 0.6 then
				table.insert(mountains, {
					x = x,
					z = z,
					groundRadius = radius,
					height = height,
					sink = sink,
					sides = ring.sides,
					big = ring.big,
					seed = math.floor(random() * 1e6),
				})
			end
		end
	end
	return mountains
end

HubLayout.MOUNTAINS = HubLayout.generateMountains()

-- The faces of one mountain, as triangles of { x, y, z } points in world space.
--
-- A mountain is a cone cut into rings: a buried base, one or two rings up its side, and a peak. Each ring's points
-- are pushed in or out a little and turned a little, so the faces catch the light differently.
function HubLayout.mountainTriangles(mountain: Mountain): { Triangle }
	local random = newRandom(mountain.seed)
	local groundY = Runway.BASE_Y
	local peakY = groundY + mountain.height
	local baseY = groundY - mountain.sink
	local sides = mountain.sides
	local roughness = HubLayout.MOUNTAIN_ROUGHNESS

	-- Radius of the smooth cone at a height.
	local function coneRadius(y: number): number
		return mountain.groundRadius * (peakY - y) / (peakY - groundY)
	end

	local turn = random(0, math.pi * 2)
	local function ring(y: number, wobble: number): { { number } }
		local points = {}
		for side = 0, sides - 1 do
			local angle = turn + (side + random(-0.22, 0.22)) * math.pi * 2 / sides
			local radius = coneRadius(y) * random(1 - roughness, 1 + roughness)
			local height = y + random(-wobble, wobble)
			table.insert(
				points,
				{ mountain.x + math.cos(angle) * radius, height, mountain.z + math.sin(angle) * radius }
			)
		end
		return points
	end

	local peak = {
		mountain.x + random(-0.08, 0.08) * mountain.groundRadius,
		peakY,
		mountain.z + random(-0.08, 0.08) * mountain.groundRadius,
	}

	-- Rings from the bottom up, and the band each ring starts.
	local rings: { { { number } } }
	local bands: { Band }
	if mountain.big then
		rings = {
			ring(baseY, 0),
			ring(groundY + mountain.height * 0.35, mountain.height * 0.04),
			ring(groundY + mountain.height * 0.72, mountain.height * 0.03),
		}
		bands = { "Grass", "Rock", if mountain.height >= SNOW_HEIGHT then "Snow" else "Rock" }
	else
		rings = { ring(baseY, 0), ring(groundY + mountain.height * 0.55, mountain.height * 0.05) }
		bands = { "Grass", "Hilltop" }
	end

	local triangles: { Triangle } = {}
	local function add(a, b, c, band: Band)
		table.insert(triangles, { a = a, b = b, c = c, band = band, shade = random(0.9, 1.06) })
	end

	for level = 1, #rings do
		local lower = rings[level]
		local upper = rings[level + 1]
		for side = 1, sides do
			local nextSide = side % sides + 1
			if upper then
				add(lower[side], lower[nextSide], upper[side], bands[level])
				add(lower[nextSide], upper[nextSide], upper[side], bands[level])
			else
				add(lower[side], lower[nextSide], peak, bands[level])
			end
		end
	end
	return triangles
end

return HubLayout
