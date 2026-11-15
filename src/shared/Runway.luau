--!strict
-- Runway geometry. Everything that needs to know where the runway is (the map builder, egg movement, mounting
-- checks) reads it from here, so gameplay never depends on map parts being loaded.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Coordinates: the runway starts at z = 0 and runs toward +z. x is the side-to-side ("lateral") position,
-- with 0 on the centre line. The hub sits behind the start, at negative z.
--
-- The runway has no end. The last zone repeats forever: the same ground, walls and gate every LOOP_LENGTH studs.
-- Nobody ever gets far along it, though. Anything that reaches LOOP_END is carried back by LOOP_LENGTH (and up the
-- slope by LOOP_RISE) to a spot that looks exactly the same, so the move cannot be seen. Eggs are drawn at the copy
-- of their position nearest the viewer (nearestImage), so they never jump around near anyone either.

local Runway = {}

Runway.ZONE_COUNT = 5
Runway.ZONE_LENGTH = 600
-- Where the last zone starts repeating.
Runway.LENGTH = Runway.ZONE_COUNT * Runway.ZONE_LENGTH
Runway.WIDTH = 64

-- Height of the walking surface at the hub and the start of the runway.
Runway.BASE_Y = 10
-- Studs of drop per stud travelled; the runway is a gentle downhill.
Runway.SLOPE = 0.04

Runway.HUB_LENGTH = 220
Runway.HUB_WIDTH = 240

-- The endless last zone.
Runway.FINAL_ZONE_START = (Runway.ZONE_COUNT - 1) * Runway.ZONE_LENGTH
Runway.LOOP_LENGTH = Runway.ZONE_LENGTH
-- How far around them players can make out other eggs. Everything within this distance of someone being carried
-- back must look the same before and after.
Runway.LOOP_VIEW = Runway.LOOP_LENGTH / 2
Runway.LOOP_END = Runway.FINAL_ZONE_START + Runway.LOOP_LENGTH + Runway.LOOP_VIEW
Runway.LOOP_START = Runway.LOOP_END - Runway.LOOP_LENGTH
-- How much higher the matching spot one loop back is.
Runway.LOOP_RISE = Runway.SLOPE * Runway.LOOP_LENGTH
-- The repeats of the last zone are built this far past LENGTH, well beyond where the fog hides everything.
Runway.RUNOUT = 2700

-- Walls run along both sides of the runway, with gaps. An egg steered into a wall kills its rider; one steered into
-- a gap goes off the side. Lengths in studs.
Runway.WALL_THICKNESS = 3
Runway.WALL_MIN_LENGTH = 50
Runway.WALL_MAX_LENGTH = 150
Runway.GAP_MIN_LENGTH = 40
Runway.GAP_MAX_LENGTH = 80
Runway.WALL_MIN_HEIGHT = 5
Runway.WALL_MAX_HEIGHT = 9

-- Height of the walking surface at a given distance down the runway.
function Runway.surfaceY(z: number): number
	if z <= 0 then
		return Runway.BASE_Y
	end
	return Runway.BASE_Y - Runway.SLOPE * z
end

-- Distance down the runway where a zone begins.
function Runway.zoneStartZ(zoneId: number): number
	return (zoneId - 1) * Runway.ZONE_LENGTH
end

-- Which zone a distance down the runway falls in, or nil if it is behind the start. Everything past the last zone's
-- start is the last zone.
function Runway.zoneAt(z: number): number?
	if z < 0 then
		return nil
	end
	return math.min(math.floor(z / Runway.ZONE_LENGTH) + 1, Runway.ZONE_COUNT)
end

-- The furthest from the centre line an egg of this half-length may sit: its end then touches the wall (or hangs
-- over a gap).
function Runway.maxLateral(halfLength: number): number
	return math.max(0, Runway.WIDTH / 2 - halfLength - 1)
end

function Runway.clampLateral(x: number, halfLength: number): number
	local limit = Runway.maxLateral(halfLength)
	return math.clamp(x, -limit, limit)
end

-- Whether an egg is pressed against the side of the runway.
function Runway.isAtEdge(x: number, halfLength: number): boolean
	return math.abs(x) >= Runway.maxLateral(halfLength) - 0.01
end

----------------------------------------------------------------------------------------------------------------
-- The loop

-- Where something that has travelled to `z` actually is: past LOOP_END it has been carried back, once per loop.
function Runway.wrapZ(z: number): number
	if z < Runway.LOOP_END then
		return z
	end
	return Runway.LOOP_START + (z - Runway.LOOP_START) % Runway.LOOP_LENGTH
end

-- The last zone looks the same every LOOP_LENGTH studs, so a spot in it has copies one loop ahead and behind.
-- This is the copy of `z` nearest `referenceZ` (never one before the last zone's start).
function Runway.nearestImage(z: number, referenceZ: number): number
	if z < Runway.FINAL_ZONE_START then
		return z
	end
	local loops = math.floor((referenceZ - z) / Runway.LOOP_LENGTH + 0.5)
	local earliest = -math.floor((z - Runway.FINAL_ZONE_START) / Runway.LOOP_LENGTH)
	return z + math.max(loops, earliest) * Runway.LOOP_LENGTH
end

----------------------------------------------------------------------------------------------------------------
-- Walls

export type WallSegment = { startZ: number, endZ: number, height: number }

-- A fixed pseudo-random sequence (Park-Miller), so every server and client lays out the same walls.
local function sequence(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

-- Walls and gaps along a stretch `length` studs long. Each stretch starts and ends with half of the smallest gap, so
-- stretches placed end to end (the zones, then each repeat of the last zone) join with a gap like any other.
local function layOut(seed: number, length: number): { WallSegment }
	local random = sequence(seed)
	local function between(low: number, high: number): number
		return low + random() * (high - low)
	end
	local margin = Runway.GAP_MIN_LENGTH / 2
	local segments = {}
	local z = margin
	while true do
		local room = length - margin - z
		local height = between(Runway.WALL_MIN_HEIGHT, Runway.WALL_MAX_HEIGHT)
		if room <= Runway.WALL_MAX_LENGTH then
			-- The last wall runs to the end of the stretch.
			table.insert(segments, { startZ = z, endZ = length - margin, height = height })
			return segments
		end
		-- Leave room for at least one more gap and wall after this one.
		local wallLength = between(
			Runway.WALL_MIN_LENGTH,
			math.min(Runway.WALL_MAX_LENGTH, room - Runway.GAP_MIN_LENGTH - Runway.WALL_MIN_LENGTH)
		)
		table.insert(segments, { startZ = z, endZ = z + wallLength, height = height })
		local gap =
			between(Runway.GAP_MIN_LENGTH, math.min(Runway.GAP_MAX_LENGTH, room - wallLength - Runway.WALL_MIN_LENGTH))
		z += wallLength + gap
	end
end

-- For each side (-1 = negative x, 1 = positive x): the walls before the last zone, and one repeat of the last zone's
-- walls (measured from its start).
local leading = {
	[-1] = layOut(1301, Runway.FINAL_ZONE_START),
	[1] = layOut(2702, Runway.FINAL_ZONE_START),
}
local repeating = {
	[-1] = layOut(4111, Runway.LOOP_LENGTH),
	[1] = layOut(5923, Runway.LOOP_LENGTH),
}

-- The walls on one side (`side` is -1 or 1, the sign of x) within [fromZ, toZ), cut to fit.
function Runway.wallsBetween(side: number, fromZ: number, toZ: number): { WallSegment }
	local found = {}
	local function add(startZ: number, endZ: number, height: number)
		local a, b = math.max(startZ, fromZ), math.min(endZ, toZ)
		if b > a then
			table.insert(found, { startZ = a, endZ = b, height = height })
		end
	end

	for _, segment in leading[side] do
		add(segment.startZ, segment.endZ, segment.height)
	end
	if toZ > Runway.FINAL_ZONE_START then
		local first =
			math.floor((math.max(fromZ, Runway.FINAL_ZONE_START) - Runway.FINAL_ZONE_START) / Runway.LOOP_LENGTH)
		local last = math.floor((toZ - Runway.FINAL_ZONE_START) / Runway.LOOP_LENGTH)
		for loop = first, last do
			local offset = Runway.FINAL_ZONE_START + loop * Runway.LOOP_LENGTH
			for _, segment in repeating[side] do
				add(offset + segment.startZ, offset + segment.endZ, segment.height)
			end
		end
	end
	return found
end

-- Whether anything within `reach` studs of `z` (front to back) on that side is wall rather than gap.
function Runway.wallAt(side: number, z: number, reach: number): boolean
	return #Runway.wallsBetween(side, z - reach, z + reach) > 0
end

return Runway
