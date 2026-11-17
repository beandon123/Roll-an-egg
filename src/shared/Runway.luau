--!strict
-- Runway geometry. Everything that needs to know where the runway is (the map builder, egg movement, mounting
-- checks) reads it from here, so gameplay never depends on map parts being loaded.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Coordinates: the runway starts at z = 0 and runs toward +z. x is the side-to-side ("lateral") position,
-- with 0 on the centre line. The hub sits behind the start, at negative z. The runway is level all the way: eggs
-- roll at the speed their rarity sets, not because of a slope.
--
-- The runway has no end. Whatever the last zone is, it repeats forever: the same ground, banks, gate and obstacles
-- every LOOP_LENGTH studs (the map builds REPEATS copies of it past LENGTH, Shared/Obstacles lays its obstacles out
-- again in each). Nobody ever gets far along it, though. Anything that reaches LOOP_END is carried back by
-- LOOP_LENGTH to a spot that looks exactly the same, so the move cannot be seen. Eggs are drawn at the copy of
-- their position nearest the viewer (nearestImage), so they never jump around near anyone either.
--
-- Banks (walls) run down both sides, with fairly large gaps. A rider who steers their egg into a bank dies; one who
-- steers it into a gap goes over the edge with it.
--
-- The runway gets longer and wider the further it goes: each zone is longer than the one before (ZONE_LENGTHS, 800
-- studs in the Forest up to 2,600 in the Prehistoric zone) and WIDTH_STEP studs wider, the banks stepping out at
-- its gate. The last zone is the widest, and keeps that width all the way through its endless repeats.
--
-- The runway itself is a straight strip, but its walls wind: along each stretch of bank between gaps, the wall
-- swings in towards the middle in a long, smooth curve and back out again (wallInset), each side in its own
-- places, so the open runway snakes between them. A rider has to steer round each bend in the wall in time; eggs
-- nobody is riding slide along it. The walls are straight again at every gate, at every gap, and all through the
-- Ocean, whose railings run along a straight boardwalk. So the edge of the runway is not the same distance from the
-- centre line on both sides: lateralRange says where an egg may be at a distance down it.

local Runway = {}

Runway.ZONE_COUNT = 6
-- How long each zone is, in order down the runway.
Runway.ZONE_LENGTHS = { 800, 1160, 1520, 1880, 2240, 2600 }

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
-- How much wider each zone is than the one before (a multiple of the 20-stud ground tiles).
Runway.WIDTH_STEP = 20
-- The last zone's width, which its endless repeats keep.
Runway.MAX_WIDTH = Runway.START_WIDTH + Runway.WIDTH_STEP * (Runway.ZONE_COUNT - 1)

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
-- Long stretches of bank between the gaps, so the walls have room to wind.
Runway.BANK_MIN_LENGTH = 100
Runway.BANK_MAX_LENGTH = 300
Runway.GAPLESS_START = 90
Runway.GAPLESS_END = 40

-- Bends in the walls. A bend fills most of a stretch of bank between gaps, coming no nearer than BEND_GAP_CLEAR to
-- a gap, BEND_GATE_CLEAR to the start of its zone (where its eggs appear and its gate stands) or BEND_END_CLEAR to
-- its end. It reaches in at most BEND_DEPTH of the zone's width, and is at least BEND_SLOPE times as long as it is
-- deep, so it comes in gently enough to steer round. A stretch shorter than BEND_MIN_LENGTH stays straight, and so
-- does one in every so many others (BEND_CHANCE).
Runway.BEND_GAP_CLEAR = 20
Runway.BEND_GATE_CLEAR = 140
Runway.BEND_END_CLEAR = 60
Runway.BEND_DEPTH = 0.15
Runway.BEND_SLOPE = 8
Runway.BEND_MIN_LENGTH = 120
Runway.BEND_CHANCE = 0.8
-- Zones whose walls never bend: the Ocean's boardwalk.
Runway.STRAIGHT_ZONES = { [4] = true }

export type WallGap = { side: number, startZ: number, endZ: number }
-- A bend in one side's wall: where it starts and ends (distance down the runway) and how far in it reaches at its
-- deepest, halfway along.
export type Bend = { side: number, startZ: number, endZ: number, depth: number }

-- Height of the walking surface at a given distance down the runway.
function Runway.surfaceY(_z: number): number
	return Runway.BASE_Y
end

-- How long a zone is. Zones past the last one are its copies.
function Runway.zoneLength(zoneId: number): number
	return Runway.ZONE_LENGTHS[math.clamp(zoneId, 1, Runway.ZONE_COUNT)]
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
	return Runway.START_WIDTH + Runway.WIDTH_STEP * (math.clamp(zoneId, 1, Runway.ZONE_COUNT) - 1)
end

-- How wide the runway is at a distance down it. Behind the start (where it leaves the hub) it is the first zone's
-- width.
function Runway.widthAt(z: number): number
	return Runway.zoneWidth(Runway.zoneAt(z) or 1)
end

-- How far the runway's ground reaches from the centre line at a distance down it (to its straight edges; the walls
-- may bend in over it, see wallInset).
function Runway.halfWidthAt(z: number): number
	return Runway.widthAt(z) / 2
end

-- Where the open runway ends on one side (side = 1 for +x, -1 for -x) at a distance down it: the face of the wall,
-- or the edge over a gap. As a lateral position (negative on the -x side).
function Runway.edgeAt(side: number, z: number): number
	return side * (Runway.halfWidthAt(z) - Runway.wallInset(side, z))
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

-- Whether an egg at `z` is pressed against the side of the runway (or a wall has come in to meet it).
function Runway.isAtEdge(x: number, halfLength: number, z: number): boolean
	local low, high = Runway.lateralRange(halfLength, z)
	return x >= high - 0.01 or x <= low + 0.01
end

-- Where an egg starts its ride, side to side: a riderless egg may run right along a bank, so whoever gets on starts
-- a little way in from it, and only dies there if they steer into it.
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

-- The bends in one side of one zone's wall, measured from the zone's start, given its gaps: one in most stretches of
-- bank long enough for one (see BEND_GAP_CLEAR and the rest), as { from, to, depth }.
local function layOutBends(seed: number, zoneId: number, gaps: { { number } }): { { number } }
	if Runway.STRAIGHT_ZONES[zoneId] then
		return {}
	end
	local random = sequence(seed)
	local length = Runway.ZONE_LENGTHS[zoneId]
	local deepest = Runway.BEND_DEPTH * Runway.zoneWidth(zoneId)
	-- The stretches of wall: from the clear ground after the gate, between the gaps, to the clear ground at the end.
	local stretches = {}
	local from = Runway.BEND_GATE_CLEAR
	for _, gap in gaps do
		table.insert(stretches, { from, gap[1] - Runway.BEND_GAP_CLEAR })
		from = gap[2] + Runway.BEND_GAP_CLEAR
	end
	table.insert(stretches, { from, length - Runway.BEND_END_CLEAR })
	local bends = {}
	for _, stretch in stretches do
		local span = stretch[2] - stretch[1]
		local chance, fill, deep = random(), random(), random()
		if span >= Runway.BEND_MIN_LENGTH and chance < Runway.BEND_CHANCE then
			-- Most of the stretch, set somewhere along it.
			local bendLength = span * (0.7 + 0.3 * fill)
			local start = stretch[1] + (span - bendLength) * random()
			local depth = math.min(deepest, bendLength / Runway.BEND_SLOPE) * (0.6 + 0.4 * deep)
			if depth >= 4 then
				table.insert(bends, { start, start + bendLength, depth })
			end
		end
	end
	return bends
end

-- Each zone's gaps and bends, by side (-1 = negative x, 1 = positive x). The copies of the last zone use the last
-- zone's.
local gapsByZone: { [number]: { [number]: { { number } } } } = {}
local bendsByZone: { [number]: { [number]: { { number } } } } = {}
for zoneId = 1, Runway.ZONE_COUNT do
	local length = Runway.ZONE_LENGTHS[zoneId]
	gapsByZone[zoneId] = {
		[-1] = layOutGaps(1301 + 7919 * zoneId, length),
		[1] = layOutGaps(2702 + 6007 * zoneId, length),
	}
	bendsByZone[zoneId] = {
		[-1] = layOutBends(4421 + 3637 * zoneId, zoneId, gapsByZone[zoneId][-1]),
		[1] = layOutBends(5903 + 2953 * zoneId, zoneId, gapsByZone[zoneId][1]),
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

----------------------------------------------------------------------------------------------------------------
-- Bends in the walls

-- The bends in one zone's walls, in order down the runway, both sides. Zones past the last one are its copies.
function Runway.wallBends(zoneId: number): { Bend }
	local pattern = bendsByZone[math.min(zoneId, Runway.ZONE_COUNT)]
	local zoneStart = Runway.zoneStartZ(zoneId)
	local bends = {}
	for _, side in { -1, 1 } do
		for _, bend in pattern[side] do
			table.insert(
				bends,
				{ side = side, startZ = zoneStart + bend[1], endZ = zoneStart + bend[2], depth = bend[3] }
			)
		end
	end
	table.sort(bends, function(a, b)
		return a.startZ < b.startZ
	end)
	return bends
end

-- How far the wall on one side (1 for +x, -1 for -x) has come in from the runway's straight edge, at a distance
-- down it: 0 along the straight stretches, and in a bend a smooth swell in and back out (a raised cosine).
function Runway.wallInset(side: number, z: number): number
	if z <= 0 then
		return 0
	end
	local stretch = Runway.stretchAt(z)
	local relative = z - Runway.zoneStartZ(stretch)
	for _, bend in bendsByZone[math.min(stretch, Runway.ZONE_COUNT)][side] do
		if relative > bend[1] and relative < bend[2] then
			local u = (relative - bend[1]) / (bend[2] - bend[1])
			return bend[3] * (0.5 - 0.5 * math.cos(2 * math.pi * u))
		end
	end
	return 0
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
