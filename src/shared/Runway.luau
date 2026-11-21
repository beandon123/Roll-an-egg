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
--
-- The runway gets longer and wider the further it goes: each zone is longer than the one before (ZONE_LENGTHS, 800
-- studs in the Forest up to 2,960 in the Prehistoric zone) and wider (zoneWidth: 120, 140 and 160 studs, then a
-- quarter wider each zone: 200, 260, 320 and 400), the banks stepping out at its gate. The last zone is the widest,
-- and keeps that width all the way through its endless repeats.
-- Because the zones differ in width, where an egg may be side to side depends on how far down the runway it is:
-- lateralRange says, at a distance down it.

local Runway = {}

Runway.ZONE_COUNT = 7
-- How long each zone is, in order down the runway: each 360 studs longer than the one before.
Runway.ZONE_LENGTHS = { 800, 1160, 1520, 1880, 2240, 2600, 2960 }

-- Where each zone starts, and where the zones end and the last zone starts repeating.
local zoneStarts: { number } = {}
do
	local z = 0
	for zoneId = 1, Runway.ZONE_COUNT do
		zoneStarts[zoneId] = z
		z += Runway.ZONE_LENGTHS[zoneId]
	end
	Runway.LENGTH = z
end
-- The first zone's width: wide enough for a whole server to chase eggs side by side. Cliff banks run down both sides.
Runway.START_WIDTH = 120
-- The next zones are each WIDTH_STEP studs wider than the one before. From zone GROWTH_FROM on, each is GROWTH times
-- as wide as the one before instead, up to zone GROWTH_UNTIL; any zones after that are as wide as it. Every zone's
-- width is rounded to a whole number of the 20-stud ground tiles.
Runway.WIDTH_STEP = 20
Runway.GROWTH_FROM = 4
Runway.GROWTH = 1.25
Runway.GROWTH_UNTIL = 7
local GROUND_TILE = 20

local zoneWidths: { number } = {}
do
	local exact = Runway.START_WIDTH
	for zoneId = 1, Runway.ZONE_COUNT do
		-- Zone 1 is START_WIDTH wide, and any zone past GROWTH_UNTIL as wide as the one before it.
		if zoneId > 1 and zoneId <= Runway.GROWTH_UNTIL then
			if zoneId >= Runway.GROWTH_FROM then
				exact *= Runway.GROWTH
			else
				exact += Runway.WIDTH_STEP
			end
		end
		zoneWidths[zoneId] = math.round(exact / GROUND_TILE) * GROUND_TILE
	end
end
-- The last zone's width, which its endless repeats keep: the widest.
Runway.MAX_WIDTH = zoneWidths[Runway.ZONE_COUNT]

-- Height of the walking surface, at the hub and all the way down the runway.
Runway.BASE_Y = 10

-- An egg rolls on past the end of its own zone and fades out this far into the next one (a fraction of a zone).
Runway.FADE_INTO_NEXT = 0.25

-- The hub behind the start of the runway: a plaza with the players' plots across its back and down its sides (see
-- Shared/Plots).
Runway.HUB_LENGTH = 440
Runway.HUB_WIDTH = 440

-- The endless last zone.
Runway.FINAL_ZONE_START = zoneStarts[Runway.ZONE_COUNT]
Runway.LOOP_LENGTH = Runway.ZONE_LENGTHS[Runway.ZONE_COUNT]
-- How far around them players can make out other eggs. Everything within this distance of someone being carried
-- back must look the same before and after.
Runway.LOOP_VIEW = Runway.LOOP_LENGTH / 2
Runway.LOOP_END = Runway.FINAL_ZONE_START + Runway.LOOP_LENGTH + Runway.LOOP_VIEW
Runway.LOOP_START = Runway.LOOP_END - Runway.LOOP_LENGTH
-- How many copies of the last zone the map builds past LENGTH, so the runway always runs on into the haze. One is
-- enough now the zone is so long: nobody gets nearer than LOOP_VIEW to the end of it.
Runway.REPEATS = 1

-- Gaps in the banks: fairly large, at irregular spacing. None in the first stretch of a zone (its gate stands on the
-- banks and its eggs appear there) or its last stretch, so the banks run on unbroken past every gate.
Runway.GAP_MIN_LENGTH = 40
Runway.GAP_MAX_LENGTH = 80
-- Long stretches of bank between the gaps.
Runway.BANK_MIN_LENGTH = 100
Runway.BANK_MAX_LENGTH = 300
Runway.GAPLESS_START = 90
Runway.GAPLESS_END = 40

export type WallGap = { side: number, startZ: number, endZ: number }

-- How each zone's stretch of runway winds. "S" swings the centre line out to one side and across to the other;
-- "Bulge" swings it out to one side and back. `amplitude` is how far the centre line moves, in studs (positive
-- towards +x). A zone longer than BEND_LENGTH has its shape again for each BEND_LENGTH or so of its length, so the
-- long zones wind as much as the short ones. Every shape is back in the middle, running straight, at both ends, so
-- the runway is straight at every zone's start. The last zone's bends repeat with it past the end of the runway.
export type Bend = { shape: "S" | "Bulge", amplitude: number }
Runway.BENDS = {
	{ shape = "S", amplitude = 46 }, -- Forest
	{ shape = "Bulge", amplitude = -72 }, -- Desert
	{ shape = "S", amplitude = -46 }, -- Snow
	{ shape = "S", amplitude = 52 }, -- Jungle
	{ shape = "Bulge", amplitude = 64 }, -- Ocean
	{ shape = "S", amplitude = 46 }, -- Volcano
	{ shape = "S", amplitude = -44 }, -- Prehistoric
} :: { Bend }
Runway.BEND_LENGTH = 650

-- Height of the walking surface at a given distance down the runway.
function Runway.surfaceY(_z: number): number
	return Runway.BASE_Y
end

-- How long a zone is. Zones past the last one are its copies.
function Runway.zoneLength(zoneId: number): number
	return Runway.ZONE_LENGTHS[math.clamp(zoneId, 1, Runway.ZONE_COUNT)]
end

----------------------------------------------------------------------------------------------------------------
-- Winding

-- How far the centre line is from x = 0 at `z`, and how fast that changes (studs of x per stud of z).
local function bendAt(z: number): (number, number)
	if z <= 0 then
		return 0, 0
	end
	local stretch = Runway.stretchAt(z)
	local bend = Runway.BENDS[math.min(stretch, Runway.ZONE_COUNT)]
	if bend == nil then
		return 0, 0
	end
	-- How far through one swing of its zone's shape (or, past the end of the runway, of its copy of the last zone)
	-- `z` is: the shape comes round again every `span` studs.
	local length = Runway.zoneLength(stretch)
	local swings = math.max(1, math.round(length / Runway.BEND_LENGTH))
	local span = length / swings
	local u = ((z - Runway.zoneStartZ(stretch)) % span) / span
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
	return bend.amplitude * value, bend.amplitude * perU / span
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
	if zoneId <= Runway.ZONE_COUNT then
		return zoneStarts[math.max(1, zoneId)]
	end
	return Runway.LENGTH + (zoneId - Runway.ZONE_COUNT - 1) * Runway.LOOP_LENGTH
end

-- Where a riderless egg from this zone fades out: a quarter of the way into the next zone (for the last zone, into
-- its first copy).
function Runway.fadeZ(zoneId: number): number
	return Runway.zoneStartZ(zoneId + 1) + Runway.FADE_INTO_NEXT * Runway.zoneLength(zoneId + 1)
end

-- Which stretch a distance down the runway falls in, counting the copies of the last zone as zones of their own
-- (ZONE_COUNT + 1 is the first copy). Anything behind the start counts as zone 1.
function Runway.stretchAt(z: number): number
	if z >= Runway.LENGTH then
		return Runway.ZONE_COUNT + 1 + math.floor((z - Runway.LENGTH) / Runway.LOOP_LENGTH)
	end
	for zoneId = Runway.ZONE_COUNT, 2, -1 do
		if z >= zoneStarts[zoneId] then
			return zoneId
		end
	end
	return 1
end

-- Which zone a distance down the runway falls in, or nil if it is behind the start. Everything past the last zone's
-- start is the last zone.
function Runway.zoneAt(z: number): number?
	if z < 0 then
		return nil
	end
	return math.min(Runway.stretchAt(z), Runway.ZONE_COUNT)
end

-- How wide a zone's stretch of runway is. Copies of the last zone (zone ids past ZONE_COUNT) are as wide as it.
function Runway.zoneWidth(zoneId: number): number
	return zoneWidths[math.clamp(zoneId, 1, Runway.ZONE_COUNT)]
end

-- How wide the runway is at a distance down it. Behind the start (where it leaves the hub) it is the first zone's
-- width.
function Runway.widthAt(z: number): number
	return Runway.zoneWidth(Runway.zoneAt(z) or 1)
end

-- How far the runway reaches from its centre line at a distance down it.
function Runway.halfWidthAt(z: number): number
	return Runway.widthAt(z) / 2
end

-- Where the open runway ends on one side (side = 1 for +x, -1 for -x) at a distance down it: the face of the wall,
-- or the railing across a gap. As a lateral position (negative on the -x side).
function Runway.edgeAt(side: number, z: number): number
	return side * Runway.halfWidthAt(z)
end

-- Where an egg of this half-length may be, side to side, at a distance `z` down the runway: from `low` to `high`.
-- At either end it touches the wall (or hangs over a gap).
function Runway.lateralRange(halfLength: number, z: number): (number, number)
	local high = math.max(0, Runway.edgeAt(1, z) - halfLength - 1)
	local low = math.min(0, Runway.edgeAt(-1, z) + halfLength + 1)
	return low, high
end

-- The furthest from the centre line an egg of this half-length may sit at a distance `z` down the runway: on one
-- side (side = 1 or -1), or, without a side, on whichever side the wall comes in further.
function Runway.maxLateral(halfLength: number, z: number, side: number?): number
	local low, high = Runway.lateralRange(halfLength, z)
	if side == 1 then
		return high
	elseif side == -1 then
		return -low
	end
	return math.min(high, -low)
end

function Runway.clampLateral(x: number, halfLength: number, z: number): number
	local low, high = Runway.lateralRange(halfLength, z)
	return math.clamp(x, low, high)
end

-- Whether an egg at `z` is pressed against the side of the runway.
function Runway.isAtEdge(x: number, halfLength: number, z: number): boolean
	local low, high = Runway.lateralRange(halfLength, z)
	return x >= high - 0.01 or x <= low + 0.01
end

-- Where an egg starts its ride, side to side: a riderless egg may run right along a bank, so whoever gets on starts
-- a little way in from it, and only bounces off it if they steer into it.
Runway.MOUNT_EDGE_MARGIN = 1.5
function Runway.mountLateral(x: number, halfLength: number, z: number): number
	local low, high = Runway.lateralRange(halfLength, z)
	low = math.min(0, low + Runway.MOUNT_EDGE_MARGIN)
	high = math.max(0, high - Runway.MOUNT_EDGE_MARGIN)
	return math.clamp(x, low, high)
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
local function layOutGaps(seed: number, length: number): { { number } }
	local random = sequence(seed)
	local function between(low: number, high: number): number
		return low + random() * (high - low)
	end
	local last = length - Runway.GAPLESS_END
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
	local length = Runway.ZONE_LENGTHS[zoneId]
	gapsByZone[zoneId] = {
		[-1] = layOutGaps(1301 + 7919 * zoneId, length),
		[1] = layOutGaps(2702 + 6007 * zoneId, length),
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
	local zoneId = Runway.stretchAt(math.max(0, z))
	for _, gap in Runway.wallGaps(zoneId) do
		if gap.side == side and gap.startZ <= z - reach and z + reach <= gap.endZ then
			return false
		end
	end
	return true
end

-- The narrowest the open runway gets between `fromZ` and `toZ` (checked every `step` studs): where an egg of this
-- half-length may be all the way along, as `low` to `high`.
function Runway.lateralRangeOver(halfLength: number, fromZ: number, toZ: number, step: number?): (number, number)
	local low, high = Runway.lateralRange(halfLength, fromZ)
	local z = fromZ
	while z < toZ do
		z = math.min(toZ, z + (step or 4))
		local l, h = Runway.lateralRange(halfLength, z)
		low, high = math.max(low, l), math.min(high, h)
	end
	return low, high
end

return Runway
