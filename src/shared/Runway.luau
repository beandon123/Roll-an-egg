--!strict
-- Runway geometry. Everything that needs to know where the runway is (the map builder, egg movement, mounting
-- checks) reads it from here, so gameplay never depends on map parts being loaded.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- The runway winds and rolls: it bends left and right between massive walls, climbs and drops over hills, and gets
-- longer and wider zone by zone. The rules never deal with that shape directly. They work in runway coordinates:
--     z   distance down the runway, measured along its centre line (0 where it leaves the hub)
--     x   side-to-side ("lateral") position, 0 on the centre line, positive to the left looking down the runway
-- so in the rules the runway is still a straight strip, as wide as halfWidthAt(z) says. Only what is drawn or
-- built, and what is read off a character's position, goes through toWorld and fromWorld, which bend that strip
-- along the centre line.
--
-- World coordinates: the hub sits behind the start, at negative world Z, centred on world X = 0, where runway and
-- world coordinates are the same thing. From the start the runway heads off toward +Z; its heading never swings
-- far from that, so it never doubles back, and it is back to dead ahead (and level) at the start of every zone, so
-- every zone begins at a gate standing square across it.
--
-- The runway has no end. Whatever the last zone is, it repeats forever: the same ground, walls, gate and obstacles
-- every LOOP_LENGTH studs (the map builds REPEATS copies of it past LENGTH, Shared/Obstacles lays its obstacles out
-- again in each). Because the last zone ends heading the way it started, each copy is the one before it shifted
-- by loopShift(), with nothing turned. Nobody ever gets far along it, though. Anything that reaches LOOP_END is
-- carried back by LOOP_LENGTH to a spot that looks exactly the same, so the move cannot be seen. Eggs are drawn at
-- the copy of their position nearest the viewer (nearestImage), so they never jump around near anyone either.
--
-- Walls run down both sides, with fairly large gaps. A rider who steers their egg into a wall dies; one who steers
-- it into a gap goes over the edge with it.

local Runway = {}

Runway.ZONE_COUNT = 6
-- How long each zone is, and how wide the runway is through it. Every zone is longer and wider than the one
-- before. (The runway may only widen: an egg nobody is riding keeps its lane from one zone into the next.)
Runway.ZONE_LENGTHS = { 800, 1160, 1520, 1880, 2240, 2600 }
Runway.ZONE_WIDTHS = { 140, 160, 180, 200, 220, 240 }
-- A zone widens to the next zone's width over its last stretch, so each zone is one width from its gate on.
Runway.WIDTH_TAPER = 120

-- Where each zone starts, and where the zones end and the last zone starts repeating.
local zoneStarts: { number } = {}
do
	local z = 0
	for zoneId = 1, Runway.ZONE_COUNT do
		zoneStarts[zoneId] = z
		z += Runway.ZONE_LENGTHS[zoneId]
		assert(
			zoneId == 1 or Runway.ZONE_WIDTHS[zoneId] >= Runway.ZONE_WIDTHS[zoneId - 1],
			"the runway may only get wider"
		)
	end
	Runway.LENGTH = z
end

-- The runway's width where it leaves the hub (the hub's opening and START ZONE are this wide), and at its widest.
Runway.WIDTH = Runway.ZONE_WIDTHS[1]
Runway.MAX_WIDTH = Runway.ZONE_WIDTHS[Runway.ZONE_COUNT]

-- Height of the walking surface at the hub, and where the runway leaves it.
Runway.BASE_Y = 10

-- An egg rolls on past the end of its own zone and fades out this far into the next one (a fraction of that zone).
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

-- Gaps in the walls: fairly large, at irregular spacing. None in the first stretch of a zone (its gate stands
-- between the walls and its eggs appear there) or its last stretch, so the walls run on unbroken past every gate.
Runway.GAP_MIN_LENGTH = 50
Runway.GAP_MAX_LENGTH = 110
Runway.BANK_MIN_LENGTH = 70
Runway.BANK_MAX_LENGTH = 220
Runway.GAPLESS_START = 90
Runway.GAPLESS_END = 60

export type WallGap = { side: number, startZ: number, endZ: number }

----------------------------------------------------------------------------------------------------------------
-- Zones

-- How long a zone is. Zones past the last one are its copies.
function Runway.zoneLength(zoneId: number): number
	return Runway.ZONE_LENGTHS[math.clamp(zoneId, 1, Runway.ZONE_COUNT)]
end

-- How wide the runway is through a zone (it widens toward the next zone's width over the zone's last stretch).
function Runway.zoneWidth(zoneId: number): number
	return Runway.ZONE_WIDTHS[math.clamp(zoneId, 1, Runway.ZONE_COUNT)]
end

-- Distance down the runway where a zone begins. Past the last zone, the copies of it count on: LENGTH is where
-- "zone ZONE_COUNT + 1" (the first copy) starts.
function Runway.zoneStartZ(zoneId: number): number
	if zoneId <= Runway.ZONE_COUNT then
		return zoneStarts[math.max(1, zoneId)]
	end
	return Runway.LENGTH + (zoneId - Runway.ZONE_COUNT - 1) * Runway.LOOP_LENGTH
end

-- Which stretch a distance down the runway falls in, counting the copies of the last zone as zones of their own
-- (ZONE_COUNT + 1 is the first copy). Anything behind the start counts as zone 1.
local function stretchAt(z: number): number
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
	return math.min(stretchAt(z), Runway.ZONE_COUNT)
end

-- Where a riderless egg from this zone fades out: a quarter of the way into the next zone (for the last zone, into
-- its first copy).
function Runway.fadeZ(zoneId: number): number
	return Runway.zoneStartZ(zoneId + 1) + Runway.FADE_INTO_NEXT * Runway.zoneLength(zoneId + 1)
end

----------------------------------------------------------------------------------------------------------------
-- Width

local function smooth(u: number): number
	return u * u * (3 - 2 * u)
end

-- How wide the runway is at a distance down it.
function Runway.widthAt(z: number): number
	local zoneId = math.min(stretchAt(z), Runway.ZONE_COUNT)
	local width = Runway.ZONE_WIDTHS[zoneId]
	if zoneId < Runway.ZONE_COUNT then
		local taperStart = zoneStarts[zoneId + 1] - Runway.WIDTH_TAPER
		if z > taperStart then
			local u = (z - taperStart) / Runway.WIDTH_TAPER
			width += (Runway.ZONE_WIDTHS[zoneId + 1] - width) * smooth(u)
		end
	end
	return width
end

function Runway.halfWidthAt(z: number): number
	return Runway.widthAt(z) / 2
end

-- The furthest from the centre line an egg of this half-length may sit at `z`: its end then touches the wall (or
-- hangs over a gap).
function Runway.maxLateral(halfLength: number, z: number): number
	return math.max(0, Runway.halfWidthAt(z) - halfLength - 1)
end

function Runway.clampLateral(x: number, halfLength: number, z: number): number
	local limit = Runway.maxLateral(halfLength, z)
	return math.clamp(x, -limit, limit)
end

-- Whether an egg is pressed against the side of the runway.
function Runway.isAtEdge(x: number, halfLength: number, z: number): boolean
	return math.abs(x) >= Runway.maxLateral(halfLength, z) - 0.01
end

-- Where an egg starts its ride, side to side: a riderless egg may run right along a wall, so whoever gets on starts
-- a little way in from it, and only dies there if they steer into it.
Runway.MOUNT_EDGE_MARGIN = 1.5
function Runway.mountLateral(x: number, halfLength: number, z: number): number
	local limit = math.max(0, Runway.maxLateral(halfLength, z) - Runway.MOUNT_EDGE_MARGIN)
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
-- Shape: bends and hills
--
-- The centre line is described by two curves along the runway: its heading (which way it points, in radians from
-- dead ahead; positive swings toward +x) and its height. Each is a row of knots joined by smooth S-shaped ramps,
-- level at every knot, so the runway eases into and out of every bend and slope. The knots come from a fixed seed
-- per zone, so the server, every client and the map builder all get the same runway without sending it anywhere.

-- A fixed pseudo-random sequence (Park-Miller), the same on every machine.
local function sequence(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

type Knot = { z: number, value: number }

-- The furthest the runway swings from dead ahead.
Runway.MAX_HEADING = math.rad(34)
-- The steepest the runway gets (rise over run).
Runway.MAX_GRADE = 0.15
-- Straight, level runway at the start of each zone (where its gate stands and its eggs appear) and at its end. The
-- first zone's is longer: the hub's cliffs run down beside it.
local LEAD_IN = 70
local FIRST_LEAD_IN = 120
local LEAD_OUT = 40

-- How each zone's ground rolls. `trend` makes its slopes more often downhill (negative) or uphill, from -1 (always
-- down) to 1 (always up); `grade` is its steepest slope. `humps`: level, with humps that only ever rise (the Ocean's boardwalk never dips into the sea).
-- `returns`: ends at the height it started at (the last zone, so that its copies line up level).
type Hills = { trend: number, grade: number, humps: boolean?, returns: boolean? }
local HILLS: { Hills } = {
	{ trend = -0.25, grade = 0.11 }, -- Forest: rolling meadows, gently downhill
	{ trend = -0.3, grade = 0.13 }, -- Desert: dunes
	{ trend = -0.4, grade = 0.15 }, -- Snow: down off the mountain to the shore
	{ trend = 0, grade = 0.1, humps = true }, -- Ocean: a boardwalk humping over the reef
	{ trend = 0.45, grade = 0.15 }, -- Volcano: up the mountainside
	{ trend = 0, grade = 0.13, returns = true }, -- Prehistoric: a rolling valley
}

-- The tightest bend in a zone: the wider the runway, the wider its bends, so the walls on the inside of a bend
-- always have room.
function Runway.minBendRadius(zoneId: number): number
	return Runway.zoneWidth(zoneId) + 90
end

local function addKnot(knots: { Knot }, z: number, value: number)
	local last = knots[#knots]
	if last and z <= last.z + 1e-6 then
		last.value = value
		return
	end
	table.insert(knots, { z = z, value = value })
end

local headingKnots: { Knot } = {}
local heightKnots: { Knot } = {}

-- The value of a row of knots at `z`, and how fast it is changing there (per stud).
local function evaluate(knots: { Knot }, z: number): (number, number)
	local low, high = 1, #knots
	if z <= knots[low].z then
		return knots[low].value, 0
	elseif z >= knots[high].z then
		return knots[high].value, 0
	end
	while high - low > 1 do
		local middle = (low + high) // 2
		if knots[middle].z <= z then
			low = middle
		else
			high = middle
		end
	end
	local a, b = knots[low], knots[high]
	local span = b.z - a.z
	local u = (z - a.z) / span
	return a.value + (b.value - a.value) * smooth(u), (b.value - a.value) * 6 * u * (1 - u) / span
end

-- Lays out one zone's bends: out to one side, back across to the other, and so on, ending dead ahead again. The
-- first swing is back toward world X = 0 from wherever the zone starts (`worldX`), so the runway never wanders far
-- to one side.
local function layOutBends(zoneId: number, worldX: number)
	local random = sequence(9001 + 613 * zoneId)
	local start, length = zoneStarts[zoneId], Runway.ZONE_LENGTHS[zoneId]
	local leadIn = if zoneId == 1 then FIRST_LEAD_IN else LEAD_IN
	local room = length - leadIn - LEAD_OUT
	-- Studs of runway needed per radian of turn, for the tightest bend allowed.
	local perRadian = 1.5 * Runway.minBendRadius(zoneId)

	local count = math.max(2, math.round(room / (perRadian * 1.925 * Runway.MAX_HEADING)))
	local side = if math.abs(worldX) > 1 then -math.sign(worldX) elseif random() < 0.5 then -1 else 1
	-- How far each swing goes, as a share of the zone's widest swing.
	local swings = {}
	for index = 1, count do
		swings[index] = side * (0.75 + 0.25 * random())
		side = -side
	end
	-- How much each stretch between swings turns (in the same units), and how much runway it gets: enough for its
	-- turn, and a little more for some.
	local weights = {}
	local total = 0
	for index = 1, count + 1 do
		local turn = math.abs((swings[index] or 0) - (swings[index - 1] or 0))
		weights[index] = turn * (1 + 0.2 * random())
		total += weights[index]
	end
	local widest = math.min(Runway.MAX_HEADING, room / (perRadian * total))

	addKnot(headingKnots, start, 0)
	addKnot(headingKnots, start + leadIn, 0)
	local z = start + leadIn
	for index = 1, count do
		z += room * weights[index] / total
		addKnot(headingKnots, z, swings[index] * widest)
	end
	addKnot(headingKnots, start + length - LEAD_OUT, 0)
	addKnot(headingKnots, start + length, 0)
end

-- Lays out one zone's hills from the height it starts at, and returns the height it ends at.
local function layOutHills(zoneId: number, startHeight: number): number
	local random = sequence(4409 + 877 * zoneId)
	local hills = HILLS[zoneId]
	local start, length = zoneStarts[zoneId], Runway.ZONE_LENGTHS[zoneId]
	local leadIn = if zoneId == 1 then FIRST_LEAD_IN else LEAD_IN
	local finish = start + length - LEAD_OUT

	-- Split the zone into slopes of 190 to 330 studs (the last one takes whatever is left).
	local spans = {}
	local z = start + leadIn
	while finish - z > 1 do
		local span = 190 + 140 * random()
		if finish - z - span < 150 then
			span = finish - z
		end
		table.insert(spans, span)
		z += span
	end

	-- How far each slope climbs (or drops): as much as the zone's steepest grade allows, scaled by a random share.
	local climbs = {}
	if hills.humps then
		-- Level, then up and over a hump, then level again.
		local stage = 0
		for index, span in spans do
			if stage == 1 and index < #spans then
				-- As high as the shorter of its two slopes allows.
				local limit = hills.grade * math.min(span, spans[index + 1]) / 1.5
				climbs[index] = limit * (0.6 + 0.4 * random())
				stage = 2
			elseif stage == 2 then
				climbs[index] = -climbs[index - 1]
				stage = 0
			else
				climbs[index] = 0
				stage = 1
			end
		end
	else
		local net, run = 0, 0
		for index, span in spans do
			-- Every slope is a real one, at least half as steep as the zone allows; the trend tips the odds of it
			-- going down or up.
			local direction = if random() < (1 - hills.trend) / 2 then -1 else 1
			local share = direction * (0.5 + 0.5 * random())
			climbs[index] = hills.grade * span / 1.5 * share
			net += climbs[index]
			run += span
		end
		if hills.returns then
			-- Take the net climb back out, spread along the zone, then ease every slope off together if that made
			-- any of them too steep.
			local scale = 1
			for index, span in spans do
				climbs[index] -= net * span / run
				local limit = hills.grade * span / 1.5
				if math.abs(climbs[index]) > limit then
					scale = math.min(scale, limit / math.abs(climbs[index]))
				end
			end
			for index in spans do
				climbs[index] *= scale
			end
		end
	end

	addKnot(heightKnots, start, startHeight)
	addKnot(heightKnots, start + leadIn, startHeight)
	local height = startHeight
	z = start + leadIn
	for index, span in spans do
		z += span
		height += climbs[index]
		addKnot(heightKnots, z, if hills.returns and index == #spans then startHeight else height)
	end
	if hills.returns then
		height = startHeight
	end
	addKnot(heightKnots, start + length, height)
	return height
end

-- The centre line itself, worked out once: its world X and Z, height and heading every SAMPLE_STEP studs from the
-- start to the end of the last zone. Anything in between is read off between two samples.
local SAMPLE_STEP = 2
local sampleX: { number } = { 0 }
local sampleZ: { number } = { 0 }
local sampleY: { number } = { Runway.BASE_Y }
local sampleHeading: { number } = { 0 }
do
	local x, z = 0, 0
	local height = Runway.BASE_Y
	local index = 1
	for zoneId = 1, Runway.ZONE_COUNT do
		layOutBends(zoneId, x)
		height = layOutHills(zoneId, height)
		-- Walk the zone's centre line a stud at a time, heading the way it points halfway through each step.
		local distance = zoneStarts[zoneId]
		for _ = 1, Runway.ZONE_LENGTHS[zoneId] do
			local heading = evaluate(headingKnots, distance + 0.5)
			x += math.sin(heading)
			z += math.cos(heading)
			distance += 1
			if distance % SAMPLE_STEP == 0 then
				index += 1
				sampleX[index] = x
				sampleZ[index] = z
				sampleY[index] = (evaluate(heightKnots, distance))
				sampleHeading[index] = (evaluate(headingKnots, distance))
			end
		end
	end
end
local sampleCount = #sampleX

-- How far one copy of the last zone is from the one before it, in world X, Y and Z.
local finalSample = Runway.FINAL_ZONE_START // SAMPLE_STEP + 1
local loopShiftX = sampleX[sampleCount] - sampleX[finalSample]
local loopShiftY = sampleY[sampleCount] - sampleY[finalSample]
local loopShiftZ = sampleZ[sampleCount] - sampleZ[finalSample]

function Runway.loopShift(): (number, number, number)
	return loopShiftX, loopShiftY, loopShiftZ
end

-- Folds a distance past the end of the zones back into the last zone: the distance there, and how many copies on
-- it was.
local function foldLoop(z: number): (number, number)
	if z < Runway.LENGTH then
		return z, 0
	end
	local loops = math.floor((z - Runway.FINAL_ZONE_START) / Runway.LOOP_LENGTH)
	return z - loops * Runway.LOOP_LENGTH, loops
end

-- The centre line at a distance down the runway: world X, height, world Z, and heading.
local function centerLine(z: number): (number, number, number, number)
	if z <= 0 then
		-- The hub: straight back from the start, and level.
		return 0, Runway.BASE_Y, z, 0
	end
	local folded, loops = foldLoop(z)
	local position = folded / SAMPLE_STEP
	local index = math.min(math.floor(position), sampleCount - 2)
	local t = position - index
	local a, b = index + 1, index + 2
	return sampleX[a] + (sampleX[b] - sampleX[a]) * t + loops * loopShiftX,
		sampleY[a] + (sampleY[b] - sampleY[a]) * t + loops * loopShiftY,
		sampleZ[a] + (sampleZ[b] - sampleZ[a]) * t + loops * loopShiftZ,
		sampleHeading[a] + (sampleHeading[b] - sampleHeading[a]) * t
end

-- Height of the walking surface at a distance down the runway (the same right across it).
function Runway.surfaceY(z: number): number
	local _, y = centerLine(z)
	return y
end

-- Which way the runway points at a distance down it, in radians from dead ahead (world +Z); positive is toward +x.
function Runway.heading(z: number): number
	local _, _, _, heading = centerLine(z)
	return heading
end

-- How sharply the runway is bending (radians per stud; positive bends toward +x), and how steeply it is climbing
-- (rise over run; negative is downhill).
function Runway.curvature(z: number): number
	if z <= 0 then
		return 0
	end
	local _, rate = evaluate(headingKnots, (foldLoop(z)))
	return rate
end

function Runway.slope(z: number): number
	if z <= 0 then
		return 0
	end
	local _, rate = evaluate(heightKnots, (foldLoop(z)))
	return rate
end

-- How many studs of world one stud down the runway covers at lateral position `x`: more than 1 round the outside
-- of a bend, less round the inside.
function Runway.stretch(x: number, z: number): number
	return math.max(0.3, 1 - x * Runway.curvature(z))
end

-- Where a spot on the runway is in the world: world X, the height of the surface there, and world Z.
function Runway.toWorld(x: number, z: number): (number, number, number)
	local centerX, y, centerZ, heading = centerLine(z)
	return centerX + x * math.cos(heading), y, centerZ - x * math.sin(heading)
end

-- The other way round: the runway coordinates (x, z) of a spot in the world, from its world X and Z. Exact on and
-- beside the runway (out to the far side of the walls); further out than the bends are wide there is no one answer,
-- and what comes back is some spot well off the runway.
function Runway.fromWorld(worldX: number, worldZ: number): (number, number)
	if worldZ <= 0 then
		return worldX, worldZ
	end
	-- In a copy of the last zone: work it out in the last zone itself.
	local loops = 0
	if worldZ >= sampleZ[sampleCount] then
		loops = math.floor((worldZ - sampleZ[finalSample]) / loopShiftZ)
		worldX -= loops * loopShiftX
		worldZ -= loops * loopShiftZ
	end

	-- The runway never doubles back, so its centre line passes each world Z once: start level with the spot.
	local low, high = 1, sampleCount
	while high - low > 1 do
		local middle = (low + high) // 2
		if sampleZ[middle] <= worldZ then
			low = middle
		else
			high = middle
		end
	end
	local z = (low - 1 + (worldZ - sampleZ[low]) / (sampleZ[high] - sampleZ[low])) * SAMPLE_STEP

	-- Then slide along the centre line until the spot is square across from it.
	local lateral, along = 0, 0
	for _ = 1, 8 do
		local centerX, _, centerZ, heading = centerLine(z)
		local sin, cos = math.sin(heading), math.cos(heading)
		local dx, dz = worldX - centerX, worldZ - centerZ
		along = dx * sin + dz * cos
		lateral = dx * cos - dz * sin
		if math.abs(along) < 0.002 then
			break
		end
		z += math.clamp(along / Runway.stretch(lateral, z), -200, 200)
	end
	-- Never settled: too far out to be anywhere near the runway. Make sure it reads as off it.
	if math.abs(along) > 1 then
		lateral += math.sign(if lateral == 0 then 1 else lateral) * math.abs(along)
	end
	return lateral, z + loops * Runway.LOOP_LENGTH
end

----------------------------------------------------------------------------------------------------------------
-- Gaps in the walls

-- The gaps on one side of one zone, measured from the zone's start: walls of BANK_MIN_LENGTH to BANK_MAX_LENGTH
-- between gaps of GAP_MIN_LENGTH to GAP_MAX_LENGTH, none in the gapless stretches at either end.
local function layOutGaps(seed: number, zoneLength: number): { { number } }
	local random = sequence(seed)
	local function between(low: number, high: number): number
		return low + random() * (high - low)
	end
	local last = zoneLength - Runway.GAPLESS_END
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
		[-1] = layOutGaps(1301 + 7919 * zoneId, Runway.ZONE_LENGTHS[zoneId]),
		[1] = layOutGaps(2702 + 6007 * zoneId, Runway.ZONE_LENGTHS[zoneId]),
	}
end

-- The gaps in one zone's walls, in order down the runway. `side` is 1 for the wall at +x (the left, looking down
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

-- Whether an egg centred at `z`, reaching `reach` studs front and back, is against the wall on that side (rather
-- than entirely over a gap).
function Runway.wallAt(side: number, z: number, reach: number): boolean
	for _, gap in Runway.wallGaps(stretchAt(z)) do
		if gap.side == side and gap.startZ <= z - reach and z + reach <= gap.endZ then
			return false
		end
	end
	return true
end

return Runway
