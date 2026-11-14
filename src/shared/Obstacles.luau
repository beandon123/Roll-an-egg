--!strict
-- Where every obstacle on the runway is, and what that means for eggs:
--     * the layout: zone-themed obstacles in rows across the runway (kinds and sizes in Config/Obstacles)
--     * paths: how an egg without a rider steers round them, so it never rolls through one
--     * hits: whether a ridden egg, which goes wherever its rider steers, has run into one
--     * timing: when obstacles that go off now and then (geysers, lava vents, clams) are dangerous
-- The layout comes from a fixed seed per zone, so the server, every client and the map builder all get the same
-- runway without sending it anywhere. Pure math (no Roblox APIs) so the test runner can load it outside Studio.

local Config = require(script.Parent.Config.Obstacles)
local Runway = require(script.Parent.Runway)

export type Tier = Config.Tier

export type Obstacle = {
	id: number,
	kind: string,
	zone: number,
	tier: Tier,
	-- Centre of its footprint.
	x: number,
	z: number,
	-- Half its footprint: across the runway, and along it.
	hx: number,
	hz: number,
	-- For obstacles that go off now and then: the timing, and where in its cycle this one starts.
	timing: Config.Timing?,
	offset: number,
	flat: boolean,
	-- A number from 0 to 1 for the model builder, so each one looks a little different.
	seed: number,
	row: Row,
}

export type Row = {
	-- The front and back of the row's obstacles along the runway.
	zMin: number,
	zMax: number,
	obstacles: { Obstacle },
}

-- One lane change on a path: between z0 and z1 the egg slides from `from` to `to`.
export type Move = { z0: number, z1: number, from: number, to: number }

-- The way an egg without a rider rolls from `fromZ`: it starts at `lane` and makes each move in turn.
export type Path = { lane: number, fromZ: number, moves: { Move } }

export type Activity = "Idle" | "Warning" | "Active"

local Obstacles = {}

Obstacles.Config = Config

-- The shortest stretch of runway, and the stretch per stud moved sideways, over which an egg changes lane.
local MIN_RAMP = 10
local RAMP_PER_STUD = 1.8
-- How far in front of an obstacle an egg must already be on its new lane.
local FRONT_CLEARANCE = 1

-- A small random number generator (Park and Miller's) that gives the same numbers on every machine.
local function newRandom(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

-- Draws kinds like tiles from a bag: each kind goes in as many times as its weight (rounded), the bag is shuffled,
-- and it is refilled when empty. So every kind of the zone turns up, in about the shares the weights ask for.
local function newBag(weights: { [string]: number }, random: () -> number): () -> string
	-- Sorted names, so the bag does not depend on the order a table happens to be stored in.
	local names = {}
	for name in weights do
		table.insert(names, name)
	end
	table.sort(names)
	local bag: { string } = {}
	return function()
		if #bag == 0 then
			for _, name in names do
				for _ = 1, math.max(1, math.round(weights[name])) do
					table.insert(bag, name)
				end
			end
			for index = #bag, 2, -1 do
				local other = math.floor(random() * index) + 1
				bag[index], bag[other] = bag[other], bag[index]
			end
		end
		return table.remove(bag) :: string
	end
end

-- The gaps between a row's obstacles (and the runway edges), widest first.
local function widestGap(placed: { { lo: number, hi: number } }): number
	local spans = table.clone(placed)
	table.sort(spans, function(a, b)
		return a.lo < b.lo
	end)
	local widest = 0
	local edge = -Runway.WIDTH / 2
	for _, span in spans do
		widest = math.max(widest, span.lo - edge)
		edge = math.max(edge, span.hi)
	end
	return math.max(widest, Runway.WIDTH / 2 - edge)
end

local rows: { Row } = {}
local byId: { Obstacle } = {}

local function layOutZone(zoneId: number)
	local mix = Config.Zones[zoneId]
	if mix == nil then
		return
	end
	local random = newRandom(7919 * zoneId + 104729)
	local nextKind = newBag(mix.weights, random)
	local zoneStart = Runway.zoneStartZ(zoneId)
	local z = zoneStart + Config.FIRST_ROW
	local half = Runway.WIDTH / 2

	while z <= zoneStart + Runway.ZONE_LENGTH - Config.LAST_ROW do
		-- One to three obstacles, usually two.
		local roll = random()
		local count = if roll < 0.3 then 1 elseif roll < 0.8 then 2 else 3

		local placed: { { lo: number, hi: number } } = {}
		local row: Row = { zMin = math.huge, zMax = -math.huge, obstacles = {} }
		for _ = 1, count do
			local kindName = nextKind()
			local kind = Config.Kinds[kindName]
			local grow = 1 + (kind.grow - 1) * random()
			local hx, hz = kind.hx * grow, kind.hz * grow
			-- Try a few spots; give up on this obstacle if none leaves the row passable.
			for _ = 1, 12 do
				local x = (random() * 2 - 1) * (half - hx)
				local span = { lo = x - hx, hi = x + hx }
				local clash = false
				for _, other in placed do
					-- Keep obstacles in a row apart, or clearly together; never a sliver of a gap.
					if span.lo < other.hi + 6 and span.hi > other.lo - 6 then
						clash = true
						break
					end
				end
				if clash then
					continue
				end
				table.insert(placed, span)
				if widestGap(placed) < Config.MIN_GAP then
					table.remove(placed)
					continue
				end
				local obstacleZ = z + (random() * 2 - 1) * Config.ROW_JITTER
				local obstacle: Obstacle = {
					id = #byId + 1,
					kind = kindName,
					zone = zoneId,
					tier = kind.tier,
					x = x,
					z = obstacleZ,
					hx = hx,
					hz = hz,
					timing = kind.timing,
					offset = if kind.timing then random() * kind.timing.period else 0,
					flat = kind.flat,
					seed = random(),
					row = row,
				}
				table.insert(byId, obstacle)
				table.insert(row.obstacles, obstacle)
				row.zMin = math.min(row.zMin, obstacleZ - hz)
				row.zMax = math.max(row.zMax, obstacleZ + hz)
				break
			end
		end
		if #row.obstacles > 0 then
			table.insert(rows, row)
		end
		z += Config.ROW_GAP_MIN + (Config.ROW_GAP_MAX - Config.ROW_GAP_MIN) * random()
	end
end

for zoneId = 1, Runway.ZONE_COUNT do
	layOutZone(zoneId)
end

----------------------------------------------------------------------------------------------------------------
-- Looking obstacles up

-- Every obstacle, in order down the runway (an obstacle's id is its place in this list).
function Obstacles.all(): { Obstacle }
	return byId
end

function Obstacles.get(id: number): Obstacle?
	return byId[id]
end

-- The rows that reach into the stretch of runway from zLow to zHigh, in order.
function Obstacles.rowsBetween(zLow: number, zHigh: number): { Row }
	-- The first row whose back is past zLow (rows never overlap, so their backs are in order too).
	local low, high = 1, #rows + 1
	while low < high do
		local middle = (low + high) // 2
		if rows[middle].zMax < zLow then
			low = middle + 1
		else
			high = middle
		end
	end
	local found = {}
	for index = low, #rows do
		local row = rows[index]
		if row.zMin > zHigh then
			break
		end
		table.insert(found, row)
	end
	return found
end

----------------------------------------------------------------------------------------------------------------
-- Timing

-- What an obstacle is doing at a moment. Obstacles that do not go off are always Active (always in the way).
function Obstacles.activity(obstacle: Obstacle, now: number): Activity
	local timing = obstacle.timing
	if timing == nil then
		return "Active"
	end
	local phase = (now + obstacle.offset) % timing.period
	if phase < timing.warn then
		return "Warning"
	elseif phase < timing.warn + timing.active then
		return "Active"
	end
	return "Idle"
end

-- Whether an obstacle is dangerous at any point within `slack` seconds of a moment.
function Obstacles.activeAround(obstacle: Obstacle, now: number, slack: number): boolean
	local timing = obstacle.timing
	if timing == nil then
		return true
	end
	-- The active window starts `warn` seconds into each period; step through the moments that matter.
	local step = math.max(0.05, math.min(timing.active, slack) / 2)
	local t = now - slack
	while t <= now + slack do
		if Obstacles.activity(obstacle, t) == "Active" then
			return true
		end
		t += step
	end
	return false
end

----------------------------------------------------------------------------------------------------------------
-- Paths for eggs without a rider

-- The nearest spot to `x` where an egg of this half-length can pass a row without touching any of it.
-- `beside` lists obstacles the egg is already level with: it cannot slide across those to get there.
function Obstacles.clearLane(row: Row, x: number, halfLength: number, beside: { Obstacle }?): number
	local limit = Runway.maxLateral(halfLength)
	local margin = halfLength + Config.STEER_MARGIN
	local function blocked(at: number): boolean
		for _, obstacle in row.obstacles do
			if math.abs(at - obstacle.x) < obstacle.hx + margin then
				return true
			end
		end
		if beside then
			local low, high = math.min(x, at), math.max(x, at)
			for _, obstacle in beside do
				if obstacle.x + obstacle.hx + margin > low and obstacle.x - obstacle.hx - margin < high then
					return true
				end
			end
		end
		return false
	end

	local start = math.clamp(x, -limit, limit)
	if not blocked(start) then
		return start
	end
	local best, bestDistance = start, math.huge
	for _, obstacle in row.obstacles do
		for _, side in { -1, 1 } do
			local candidate = obstacle.x + side * (obstacle.hx + margin + 0.01)
			if math.abs(candidate) <= limit and not blocked(candidate) then
				local distance = math.abs(candidate - x)
				if distance < bestDistance then
					best, bestDistance = candidate, distance
				end
			end
		end
	end
	return best
end

-- The way an egg without a rider rolls from `fromZ` to `toZ`, starting at `lane`: whenever a row of obstacles is
-- in its way, it slides over to the nearest gap in good time and carries on along its new lane.
function Obstacles.planPath(lane: number, fromZ: number, toZ: number, halfLength: number, radius: number): Path
	local current = Runway.clampLateral(lane, halfLength)
	local path: Path = { lane = current, fromZ = fromZ, moves = {} }
	-- No lane change starts before the egg is clear of the last row it passed.
	local readyFrom = fromZ
	for _, row in Obstacles.rowsBetween(fromZ - radius, toZ + radius) do
		-- Where the egg's front first reaches an obstacle of the row that is still ahead of it. An obstacle the
		-- egg is already level with is one it is rolling past.
		local touchZ = math.huge
		local beside = {}
		for _, obstacle in row.obstacles do
			local front = obstacle.z - obstacle.hz - radius
			if front > fromZ then
				touchZ = math.min(touchZ, front)
			else
				table.insert(beside, obstacle)
			end
		end
		if touchZ < math.huge then
			local target = Obstacles.clearLane(row, current, halfLength, if #beside > 0 then beside else nil)
			if target ~= current then
				-- On the new lane just before the row; an egg that starts right in front of it swerves sharply.
				local z1 = math.max(touchZ - FRONT_CLEARANCE, (fromZ + touchZ) / 2)
				local wanted = math.max(MIN_RAMP, math.abs(target - current) * RAMP_PER_STUD)
				local z0 = math.max(readyFrom, z1 - wanted)
				z0 = math.max(fromZ, math.min(z0, z1 - math.min(1, (z1 - fromZ) / 2)))
				table.insert(path.moves, { z0 = z0, z1 = z1, from = current, to = target })
				current = target
			end
		end
		readyFrom = math.max(readyFrom, row.zMax + radius + 0.5)
	end
	return path
end

-- Where an egg following a path is, side to side, at a distance down the runway.
function Obstacles.lateralAt(path: Path, z: number): number
	local x = path.lane
	for _, move in path.moves do
		if z >= move.z1 then
			x = move.to
		elseif z > move.z0 then
			local u = (z - move.z0) / (move.z1 - move.z0)
			u = u * u * (3 - 2 * u)
			return move.from + (move.to - move.from) * u
		else
			break
		end
	end
	return x
end

----------------------------------------------------------------------------------------------------------------
-- Hits

-- The obstacle a ridden egg at (x, z) is touching right now, if any. `inset` shrinks the egg's footprint by that
-- many studs on every side: a little, to forgive grazes; more, for the server's own check, which only knows
-- where the egg was a moment ago.
function Obstacles.hitAt(
	x: number,
	z: number,
	halfLength: number,
	radius: number,
	now: number,
	inset: number
): Obstacle?
	local reachX = math.max(0.5, halfLength - inset)
	local reachZ = math.max(0.5, radius - inset)
	for _, row in Obstacles.rowsBetween(z - reachZ, z + reachZ) do
		for _, obstacle in row.obstacles do
			if
				math.abs(x - obstacle.x) < obstacle.hx + reachX
				and math.abs(z - obstacle.z) < obstacle.hz + reachZ
				and Obstacles.activity(obstacle, now) == "Active"
			then
				return obstacle
			end
		end
	end
	return nil
end

-- The Lethal obstacle a player on foot at (x, z) is standing in right now, if any.
function Obstacles.lethalAt(x: number, z: number, now: number): Obstacle?
	for _, row in Obstacles.rowsBetween(z, z) do
		for _, obstacle in row.obstacles do
			if
				obstacle.tier == "Lethal"
				and math.abs(x - obstacle.x) < obstacle.hx
				and math.abs(z - obstacle.z) < obstacle.hz
				and Obstacles.activity(obstacle, now) == "Active"
			then
				return obstacle
			end
		end
	end
	return nil
end

return Obstacles
