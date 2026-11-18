--!strict
-- Runway geometry. Everything that needs to know where the runway is (the map builder, egg movement, mounting
-- checks) reads it from here, so gameplay never depends on map parts being loaded.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Coordinates: the runway starts at z = 0 and runs toward +z. The hub sits behind the start, at negative z. The
-- runway is level all the way: eggs roll at the speed their rarity sets, not because of a slope.
--
-- The runway winds. Its centre line swings from side to side through each zone (Runway.BENDS) and is back in the
-- middle, running straight, at every zone's start, where the gate stands and the eggs appear. Everything that plays
-- the game works in runway space: `z` down the runway, and `lateral`, the side-to-side position measured from the
-- centre line at that z. Only drawing and checking characters needs the world: world x = centerX(z) + lateral
-- (Runway.worldX), and back (Runway.lateralOf). So a row of obstacles, an egg's path and a rider's steering are all
-- worked out as if the runway were straight.
--
-- The runway has no end. Whatever the last zone is, it repeats forever: the same ground, banks, gate and obstacles
-- every LOOP_LENGTH studs (the map builds REPEATS copies of it past LENGTH, Shared/Obstacles lays its obstacles out
-- again in each). Nobody ever gets far along it, though. Anything that reaches LOOP_END is carried back by
-- LOOP_LENGTH to a spot that looks exactly the same, so the move cannot be seen. Eggs are drawn at the copy of
-- their position nearest the viewer (nearestImage), so they never jump around near anyone either.
--
-- Banks (tall stepped cliffs) run down both sides, broken by fairly large gaps that look out over the valley below.
-- Nothing at the edge kills: an egg steered into a bank, or into the low railing across a gap, bounces back off it
-- (see Logic/RunwaySim), which costs its rider some stamina.

local Runway = {}

Runway.ZONE_COUNT = 6
Runway.ZONE_LENGTH = 600
-- Where the zones end and the last zone starts repeating.
Runway.LENGTH = Runway.ZONE_COUNT * Runway.ZONE_LENGTH
-- Wide enough for a whole server to chase eggs side by side; cliff banks run down both sides.
Runway.WIDTH = 120

-- Height of the walking surface, at the hub and all the way down the runway.
Runway.BASE_Y = 10

-- An egg rolls on past the end of its own zone and fades out this far into the next one (a fraction of a zone).
Runway.FADE_INTO_NEXT = 0.25

-- The hub behind the start of the runway: a plaza with the players' plots across its back and down its sides (see
-- Shared/Plots).
Runway.HUB_LENGTH = 440
Runway.HUB_WIDTH = 440

-- The endless last zone.
Runway.FINAL_ZONE_START = (Runway.ZONE_COUNT - 1) * Runway.ZONE_LENGTH
Runway.LOOP_LENGTH = Runway.ZONE_LENGTH
-- How far around them players can make out other eggs. Everything within this distance of someone being carried
-- back must look the same before and after.
Runway.LOOP_VIEW = Runway.LOOP_LENGTH / 2
Runway.LOOP_END = Runway.FINAL_ZONE_START + Runway.LOOP_LENGTH + Runway.LOOP_VIEW
Runway.LOOP_START = Runway.LOOP_END - Runway.LOOP_LENGTH
-- How many copies of the last zone the map builds past LENGTH, so the runway always runs on into the haze.
Runway.REPEATS = 3

-- Gaps in the banks: fairly large, at irregular spacing. None in the first stretch of a zone (its gate stands on the
-- banks and its eggs appear there) or its last stretch, so the banks run on unbroken past every gate.
Runway.GAP_MIN_LENGTH = 40
Runway.GAP_MAX_LENGTH = 80
Runway.BANK_MIN_LENGTH = 50
Runway.BANK_MAX_LENGTH = 150
Runway.GAPLESS_START = 90
Runway.GAPLESS_END = 40

export type WallGap = { side: number, startZ: number, endZ: number }

-- How each zone's stretch of runway winds. "S" swings the centre line out to one side over the first half of the
-- zone and across to the other over the second; "Bulge" swings it out to one side and back. `amplitude` is how far
-- the centre line moves, in studs (positive towards +x). Every shape is back in the middle, running straight, at both
-- ends of the zone. The last zone's shape repeats with it past the end of the runway.
export type Bend = { shape: "S" | "Bulge", amplitude: number }
Runway.BENDS = {
	{ shape = "S", amplitude = 46 }, -- Forest
	{ shape = "Bulge", amplitude = -72 }, -- Desert
	{ shape = "S", amplitude = -46 }, -- Snow
	{ shape = "Bulge", amplitude = 64 }, -- Ocean
	{ shape = "S", amplitude = 46 }, -- Volcano
	{ shape = "S", amplitude = -44 }, -- Prehistoric
} :: { Bend }

-- Height of the walking surface at a given distance down the runway.
function Runway.surfaceY(_z: number): number
	return Runway.BASE_Y
end

----------------------------------------------------------------------------------------------------------------
-- Winding

-- How far the centre line is from x = 0 at `z`, and how fast that changes (studs of x per stud of z).
local function bendAt(z: number): (number, number)
	if z <= 0 then
		return 0, 0
	end
	local zoneIndex = math.min(math.floor(z / Runway.ZONE_LENGTH) + 1, Runway.ZONE_COUNT)
	local bend = Runway.BENDS[zoneIndex]
	if bend == nil then
		return 0, 0
	end
	-- How far through its zone (or, past the end of the runway, through its copy of the last zone) `z` is.
	local u = (z % Runway.ZONE_LENGTH) / Runway.ZONE_LENGTH
	local value, perU
	if bend.shape == "S" then
		local s = math.sin(2 * math.pi * u)
		value, perU = s * s, 2 * math.pi * math.sin(4 * math.pi * u)
		if u > 0.5 then
			value, perU = -value, -perU
		end
	else
		local s = math.sin(math.pi * u)
		value, perU = s * s, math.pi * math.sin(2 * math.pi * u)
	end
	return bend.amplitude * value, bend.amplitude * perU / Runway.ZONE_LENGTH
end

-- World x of the middle of the runway at `z` (0 at the hub and at every zone's start).
function Runway.centerX(z: number): number
	local x = bendAt(z)
	return x
end

-- How fast the runway is swinging sideways at `z`: studs of x per stud down the runway.
function Runway.slope(z: number): number
	local _, slope = bendAt(z)
	return slope
end

-- Which way the runway runs at `z`, as a turn about the vertical axis (radians) from straight down +z, positive
-- towards +x: CFrame.Angles(0, Runway.heading(z), 0) turns something that faces +z to face along the runway.
function Runway.heading(z: number): number
	return math.atan(Runway.slope(z))
end

-- World x of a spot `lateral` studs across the runway at `z`.
function Runway.worldX(lateral: number, z: number): number
	return Runway.centerX(z) + lateral
end

-- How far across the runway world x is at `z` (0 on the centre line).
function Runway.lateralOf(x: number, z: number): number
	return x - Runway.centerX(z)
end

-- Distance down the runway where a zone begins. Past the last zone, the copies of it count on: LENGTH is where
-- "zone ZONE_COUNT + 1" (the first copy) starts.
function Runway.zoneStartZ(zoneId: number): number
	return (zoneId - 1) * Runway.ZONE_LENGTH
end

-- Where a riderless egg from this zone fades out: a quarter of the way into the next zone (for the last zone, into
-- its first copy).
function Runway.fadeZ(zoneId: number): number
	return Runway.zoneStartZ(zoneId + 1) + Runway.FADE_INTO_NEXT * Runway.ZONE_LENGTH
end

-- Which zone a distance down the runway falls in, or nil if it is behind the start. Everything past the last zone's
-- start is the last zone.
function Runway.zoneAt(z: number): number?
	if z < 0 then
		return nil
	end
	return math.min(math.floor(z / Runway.ZONE_LENGTH) + 1, Runway.ZONE_COUNT)
end

-- The furthest from the centre line an egg of this half-length may sit: its end then touches the bank (or hangs
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

-- Where an egg starts its ride, side to side: a riderless egg may run right along a bank, so whoever gets on starts
-- a little way in from it, and only bounces off it if they steer into it.
Runway.MOUNT_EDGE_MARGIN = 1.5
function Runway.mountLateral(x: number, halfLength: number): number
	local limit = math.max(0, Runway.maxLateral(halfLength) - Runway.MOUNT_EDGE_MARGIN)
	return math.clamp(x, -limit, limit)
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
-- Gaps in the banks

-- A fixed pseudo-random sequence (Park-Miller), so every server and client lays out the same gaps.
local function sequence(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

-- The gaps on one side of one zone, measured from the zone's start: banks of BANK_MIN_LENGTH to BANK_MAX_LENGTH
-- between gaps of GAP_MIN_LENGTH to GAP_MAX_LENGTH, none in the gapless stretches at either end.
local function layOutGaps(seed: number): { { number } }
	local random = sequence(seed)
	local function between(low: number, high: number): number
		return low + random() * (high - low)
	end
	local last = Runway.ZONE_LENGTH - Runway.GAPLESS_END
	local gaps = {}
	local z = Runway.GAPLESS_START + between(0, Runway.BANK_MAX_LENGTH - Runway.BANK_MIN_LENGTH)
	while z + Runway.GAP_MIN_LENGTH <= last do
		local gapEnd = math.min(z + between(Runway.GAP_MIN_LENGTH, Runway.GAP_MAX_LENGTH), last)
		table.insert(gaps, { z, gapEnd })
		z = gapEnd + between(Runway.BANK_MIN_LENGTH, Runway.BANK_MAX_LENGTH)
	end
	return gaps
end

-- Each zone's gaps, by side (-1 = negative x, 1 = positive x). The copies of the last zone use the last zone's.
local gapsByZone: { [number]: { [number]: { { number } } } } = {}
for zoneId = 1, Runway.ZONE_COUNT do
	gapsByZone[zoneId] = {
		[-1] = layOutGaps(1301 + 7919 * zoneId),
		[1] = layOutGaps(2702 + 6007 * zoneId),
	}
end

-- The gaps in one zone's banks, in order down the runway. `side` is 1 for the bank at +x (the left, looking down
-- the runway) and -1 for -x. Zones past the last one are its copies, with the same gaps.
function Runway.wallGaps(zoneId: number): { WallGap }
	local pattern = gapsByZone[math.min(zoneId, Runway.ZONE_COUNT)]
	local zoneStart = Runway.zoneStartZ(zoneId)
	local gaps = {}
	for _, side in { -1, 1 } do
		for _, gap in pattern[side] do
			table.insert(gaps, { side = side, startZ = zoneStart + gap[1], endZ = zoneStart + gap[2] })
		end
	end
	table.sort(gaps, function(a, b)
		return a.startZ < b.startZ
	end)
	return gaps
end

-- Whether an egg centred at `z`, reaching `reach` studs front and back, is against the bank on that side (rather
-- than entirely over a gap).
function Runway.wallAt(side: number, z: number, reach: number): boolean
	local zoneId = math.max(1, math.floor(math.max(0, z) / Runway.ZONE_LENGTH) + 1)
	for _, gap in Runway.wallGaps(zoneId) do
		if gap.side == side and gap.startZ <= z - reach and z + reach <= gap.endZ then
			return false
		end
	end
	return true
end

return Runway
