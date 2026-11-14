--!strict
-- The rules of the runway: the egg lineup, riding, stamina, claiming, obstacles, bounces and cracking, closures.
--
-- Eggs: at sunrise (the start of each cycle) every zone rolls a lineup of eggs. They leave the zone's chute a few
-- seconds apart, roll down the runway, fade out a quarter of the way into the next zone, and drop from the chute
-- again, lap after lap, until the runway closes. Now and then a zone also drops an extra, mid-cycle egg, which
-- rolls once; Secret and rarer eggs are much less likely mid-cycle than in the sunrise lineup.
--
-- Obstacles (Shared/Obstacles): an egg without a rider steers round them on its own. A ridden egg goes wherever
-- its rider steers, and hitting one bumps it aside, throws the rider off, or kills the rider.
--
-- This module holds the rules only. It never touches players, parts, or remotes: RunwayService feeds it the
-- clock and player requests, then turns the events it emits into remotes and saved data. Keeping it free of
-- Roblox objects means the whole rulebook is covered by tests that run outside Studio (see tests/).
--
-- Riders are identified by an opaque number (RunwayService uses the player's UserId).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local EggMotion = require(Shared.EggMotion)
local EggSpec = require(Shared.EggSpec)
local Obstacles = require(Shared.Obstacles)
local Runway = require(Shared.Runway)
local StaminaMath = require(Shared.StaminaMath)
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)

export type Phase = "Open" | "Warning" | "Closed"

export type Egg = {
	id: number,
	zone: number,
	rarity: string,
	-- Which of the zone's eggs it is: a design name such as "MossStag".
	kind: string,
	spec: EggSpec.Spec,
	spawnTime: number,
	startZ: number,
	-- Where it fades out if nobody is riding it: a quarter of the way into the next zone.
	fadeZ: number,
	-- Side to side: where the rider has steered it while it is ridden. Without a rider, the egg follows `path`
	-- round the obstacles, and `lateral` is where that path starts, `pathZ` down the runway.
	lateral: number,
	pathZ: number,
	path: Obstacles.Path,
	-- Dropped mid-cycle (rolls once) rather than rolled for the sunrise lineup.
	wild: boolean,
	bouncesLeft: number,
	riderId: number?,
	-- When the egg last started a hop (it hops each time it is left without a rider).
	bounceTime: number?,
	-- Set when the egg is out of bounces: it cracks at this time and cannot be mounted meanwhile.
	crackAt: number?,
}

export type Ride = {
	startTime: number,
	startStamina: number,
	drain: number,
	claimAt: number,
	emptyAt: number,
	lateralTime: number,
	-- Obstacles this ride has already hit, by id, so each one counts once.
	hits: { [number]: boolean },
}

-- One egg of a zone's sunrise lineup: the egg, and when it next leaves the chute.
export type Slot = {
	zone: number,
	rarity: string,
	kind: string,
	nextLaunch: number,
	-- Seconds from the chute to the fade line.
	lapTime: number,
}

export type Rider = {
	id: number,
	maxStamina: number,
	agility: number,
	-- Stamina is stored as a value at a moment plus a rate of change; see StaminaMath.
	staminaValue: number,
	staminaTime: number,
	staminaRate: number,
	eggId: number?,
	ride: Ride?,
	stunnedUntil: number,
	lastMountRequest: number,
	-- For the hop combo: when and how the rider last left an egg.
	lastLeaveTime: number?,
	lastLeaveVoluntary: boolean,
	lastLeftEggId: number?,
	combo: number,
}

-- Why a ride ended.
-- (KnockedOff: hit a KnockOff obstacle. Hazard: hit a Lethal one, which kills the rider.)
export type RideEndReason = "Dismount" | "ThrownOff" | "KnockedOff" | "Hazard" | "Claimed" | "Cliff" | "Died" | "Left"
-- Why an egg left the runway.
export type EggRemoveReason = "Faded" | "Cracked" | "Claimed" | "Closure" | "Cliff"

export type SerializedEgg = {
	id: number,
	zone: number,
	rarity: string,
	kind: string,
	spawnTime: number,
	lateral: number,
	pathZ: number,
	rider: number?,
	bounces: number,
	bounceTime: number?,
	cracking: boolean,
}

export type Event =
	{ type: "EggSpawned", egg: SerializedEgg, wild: boolean }
	| { type: "LineupRolled", eggs: { { zone: number, rarity: string, kind: string } } }
	| { type: "EggRemoved", id: number, reason: EggRemoveReason, by: number? }
	| { type: "EggMounted", id: number, rider: number, time: number }
	| { type: "EggLeft", id: number, time: number, bouncesLeft: number, lateral: number }
	| {
		type: "RideStarted",
		rider: number,
		id: number,
		startTime: number,
		startStamina: number,
		drain: number,
		claimTime: number,
		combo: number,
	}
	| {
		type: "RideEnded",
		rider: number,
		reason: RideEndReason,
		id: number,
		zone: number,
		rarity: string,
		kind: string,
	}
	| { type: "StaminaChanged", rider: number, value: number, time: number, rate: number, max: number }
	| {
		type: "ObstacleHit",
		rider: number,
		id: number,
		obstacle: number,
		tier: Obstacles.Tier,
		lateral: number,
		time: number,
	}
	| { type: "Claimed", rider: number, zone: number, rarity: string, kind: string }

local RunwaySim = {}
RunwaySim.__index = RunwaySim

export type RunwaySim = typeof(setmetatable(
	{} :: {
		random: () -> number,
		obstacles: typeof(Obstacles),
		eggs: { [number]: Egg },
		riders: { [number]: Rider },
		nextEggId: number,
		lineup: { Slot }?,
		nextWildAt: { [number]: number },
		phase: Phase,
		spawnRateMultiplier: number,
		events: { Event },
	},
	RunwaySim
))

-- `random` returns a number in [0, 1); injected so tests can make drops predictable. `obstacles` is the runway's
-- obstacle layout (Shared/Obstacles unless a test gives its own).
function RunwaySim.new(random: () -> number, obstacles: typeof(Obstacles)?): RunwaySim
	local self = setmetatable({
		random = random,
		obstacles = obstacles or Obstacles,
		eggs = {},
		riders = {},
		nextEggId = 0,
		lineup = nil,
		nextWildAt = {},
		phase = "Open" :: Phase,
		spawnRateMultiplier = 1,
		events = {},
	}, RunwaySim)
	return self
end

function RunwaySim._emit(self: RunwaySim, event: Event)
	table.insert(self.events, event)
end

-- Hands over everything that has happened since the last call.
function RunwaySim.takeEvents(self: RunwaySim): { Event }
	local events = self.events
	self.events = {}
	return events
end

----------------------------------------------------------------------------------------------------------------
-- Eggs

local function serialize(egg: Egg): SerializedEgg
	return {
		id = egg.id,
		zone = egg.zone,
		rarity = egg.rarity,
		kind = egg.kind,
		spawnTime = egg.spawnTime,
		lateral = egg.lateral,
		pathZ = egg.pathZ,
		rider = egg.riderId,
		bounces = egg.bouncesLeft,
		bounceTime = egg.bounceTime,
		cracking = egg.crackAt ~= nil,
	}
end

-- Every egg on the runway right now, for a player who has just joined.
function RunwaySim.snapshot(self: RunwaySim): { SerializedEgg }
	local list = {}
	for _, egg in self.eggs do
		table.insert(list, serialize(egg))
	end
	return list
end

function RunwaySim.getEgg(self: RunwaySim, eggId: number): Egg?
	return self.eggs[eggId]
end

function RunwaySim._eggZ(_self: RunwaySim, egg: Egg, now: number): number
	return EggMotion.zAt(egg.spawnTime, egg.startZ, egg.spec.rollSpeed, now)
end

-- Where an egg is side to side: where its rider has steered it, or along its path round the obstacles.
function RunwaySim.eggLateral(self: RunwaySim, egg: Egg, now: number): number
	if egg.riderId ~= nil then
		return egg.lateral
	end
	return self.obstacles.lateralAt(egg.path, self:_eggZ(egg, now))
end

-- The centre of an egg resting on the runway: x, y, z.
function RunwaySim.eggCenter(self: RunwaySim, egg: Egg, now: number): (number, number, number)
	local z = self:_eggZ(egg, now)
	return self:eggLateral(egg, now), Runway.surfaceY(z) + egg.spec.radius, z
end

-- Sends a riderless egg on its way from where it is now (`lateral`, at `z`), steering round the obstacles ahead.
function RunwaySim._setPath(self: RunwaySim, egg: Egg, lateral: number, z: number)
	egg.lateral = Runway.clampLateral(lateral, egg.spec.halfLength)
	egg.pathZ = z
	egg.path = self.obstacles.planPath(egg.lateral, z, egg.fadeZ, egg.spec.halfLength, egg.spec.radius)
end

function RunwaySim._removeEgg(self: RunwaySim, egg: Egg, reason: EggRemoveReason, by: number?)
	self.eggs[egg.id] = nil
	self:_emit({ type = "EggRemoved", id = egg.id, reason = reason, by = by })
end

-- Puts an egg on the runway at the start of its zone (it drops in from the chute), leaving at `spawnTime`.
function RunwaySim._launch(
	self: RunwaySim,
	zoneId: number,
	rarity: string,
	kind: string,
	spawnTime: number,
	wild: boolean
): Egg?
	local spec = EggSpec.get(zoneId, rarity)
	if spec == nil then
		return nil
	end
	self.nextEggId += 1
	local limit = Runway.maxLateral(spec.halfLength)
	local startZ = Runway.zoneStartZ(zoneId) + Tuning.EGG_SPAWN_OFFSET
	local egg: Egg = {
		id = self.nextEggId,
		zone = zoneId,
		rarity = rarity,
		kind = kind,
		spec = spec,
		spawnTime = spawnTime,
		startZ = startZ,
		fadeZ = Runway.fadeZ(zoneId),
		lateral = 0,
		pathZ = startZ,
		path = nil :: any,
		wild = wild,
		bouncesLeft = spec.bounces,
		riderId = nil,
		bounceTime = nil,
		crackAt = nil,
	}
	self:_setPath(egg, (self.random() * 2 - 1) * limit, startZ)
	self.eggs[egg.id] = egg
	self:_emit({ type = "EggSpawned", egg = serialize(egg), wild = wild })
	return egg
end

-- Drops an extra egg at the start of a zone, now: a random rarity for the zone, then one of the zone's eggs of that
-- rarity. It rolls once, like a mid-cycle drop. `forcedRarity` and `forcedKind` skip the random rolls; a forced
-- egg must belong to the zone.
function RunwaySim.spawnEgg(
	self: RunwaySim,
	zoneId: number,
	now: number,
	forcedRarity: string?,
	forcedKind: string?
): Egg?
	local rarity: string
	local kind: string?
	if forcedKind then
		local place, placeRarity = EggSpec.placeOf(forcedKind)
		if place ~= zoneId or placeRarity == nil then
			return nil
		end
		rarity, kind = placeRarity, forcedKind
	else
		rarity = forcedRarity or EggSpec.rollRarity(zoneId, self.random())
		kind = EggSpec.pickEgg(zoneId, rarity, self.random())
	end
	if kind == nil then
		return nil
	end
	return self:_launch(zoneId, rarity, kind, now, true)
end

-- Rolls every zone's lineup for a new day. Lineup eggs leave the chute LINEUP_LAUNCH_GAP seconds apart.
function RunwaySim._rollLineup(self: RunwaySim, now: number)
	local lineup: { Slot } = {}
	local rolled = {}
	local count = math.max(1, math.round(Tuning.EGGS_PER_ZONE * self.spawnRateMultiplier))
	for zoneId = 1, #Zones.List do
		local startZ = Runway.zoneStartZ(zoneId) + Tuning.EGG_SPAWN_OFFSET
		for index = 1, count do
			local rarity = EggSpec.rollRarity(zoneId, self.random())
			local kind = EggSpec.pickEgg(zoneId, rarity, self.random())
			local spec = EggSpec.get(zoneId, rarity)
			if kind and spec then
				table.insert(lineup, {
					zone = zoneId,
					rarity = rarity,
					kind = kind,
					nextLaunch = now + (index - 1) * Tuning.LINEUP_LAUNCH_GAP / self.spawnRateMultiplier,
					lapTime = (Runway.fadeZ(zoneId) - startZ) / spec.rollSpeed,
				})
				table.insert(rolled, { zone = zoneId, rarity = rarity, kind = kind })
			end
		end
	end
	self.lineup = lineup
	self:_emit({ type = "LineupRolled", eggs = rolled })
end

-- The zone's mid-cycle eggs still on the runway.
function RunwaySim._countWild(self: RunwaySim, zoneId: number): number
	local count = 0
	for _, egg in self.eggs do
		if egg.zone == zoneId and egg.wild then
			count += 1
		end
	end
	return count
end

-- Called whenever an egg is left without a rider (and was not claimed): it hops and loses a bounce.
function RunwaySim._leaveEgg(self: RunwaySim, egg: Egg, now: number)
	if self.phase == "Closed" then
		-- An egg that loses its rider while the runway is closed disappears like the rest.
		self:_removeEgg(egg, "Closure")
		return
	end
	local z = self:_eggZ(egg, now)
	if z >= egg.fadeZ then
		-- Ridden past its fade line: with nobody on it, it fades like any other.
		self:_removeEgg(egg, "Faded")
		return
	end
	self:_setPath(egg, egg.lateral, z)
	egg.bouncesLeft -= 1
	egg.bounceTime = now
	if egg.bouncesLeft <= 0 then
		egg.crackAt = now + Tuning.HOP_DURATION
	end
	self:_emit({
		type = "EggLeft",
		id = egg.id,
		time = now,
		bouncesLeft = math.max(0, egg.bouncesLeft),
		lateral = egg.lateral,
	})
end

----------------------------------------------------------------------------------------------------------------
-- Stamina

function RunwaySim._regenRate(_self: RunwaySim, rider: Rider): number
	return rider.maxStamina * Tuning.STAMINA_REGEN_FRACTION
end

function RunwaySim._setStamina(self: RunwaySim, rider: Rider, value: number, now: number, rate: number)
	rider.staminaValue = math.clamp(value, 0, rider.maxStamina)
	rider.staminaTime = now
	rider.staminaRate = rate
	self:_emit({
		type = "StaminaChanged",
		rider = rider.id,
		value = rider.staminaValue,
		time = now,
		rate = rate,
		max = rider.maxStamina,
	})
end

function RunwaySim.getStamina(self: RunwaySim, riderId: number, now: number): number
	local rider = self.riders[riderId]
	if rider == nil then
		return 0
	end
	return StaminaMath.current(rider.staminaValue, rider.staminaTime, rider.staminaRate, rider.maxStamina, now)
end

----------------------------------------------------------------------------------------------------------------
-- Riders

-- Registers a player. They start with full stamina.
function RunwaySim.addRider(self: RunwaySim, riderId: number, maxStamina: number, agility: number, now: number)
	local rider: Rider = {
		id = riderId,
		maxStamina = maxStamina,
		agility = agility,
		staminaValue = maxStamina,
		staminaTime = now,
		staminaRate = 0,
		eggId = nil,
		ride = nil,
		stunnedUntil = 0,
		lastMountRequest = -math.huge,
		lastLeaveTime = nil,
		lastLeaveVoluntary = false,
		lastLeftEggId = nil,
		combo = 0,
	}
	self.riders[riderId] = rider
	self:_setStamina(rider, maxStamina, now, self:_regenRate(rider))
end

function RunwaySim.getRider(self: RunwaySim, riderId: number): Rider?
	return self.riders[riderId]
end

-- Changes a player's Max Stamina (an upgrade, for example) without touching their current stamina.
function RunwaySim.setMaxStamina(self: RunwaySim, riderId: number, maxStamina: number, now: number)
	local rider = self.riders[riderId]
	if rider == nil then
		return
	end
	local current = self:getStamina(riderId, now)
	rider.maxStamina = maxStamina
	local rate = if rider.ride then -rider.ride.drain else self:_regenRate(rider)
	self:_setStamina(rider, current, now, rate)
	if rider.ride then
		rider.ride.emptyAt = now + StaminaMath.timeUntilEmpty(rider.staminaValue, rider.ride.drain)
	end
end

function RunwaySim._endRide(self: RunwaySim, rider: Rider, now: number, reason: RideEndReason)
	local eggId = rider.eggId
	if eggId == nil then
		return
	end
	local egg = self.eggs[eggId]

	local stamina = self:getStamina(rider.id, now)
	rider.eggId = nil
	rider.ride = nil
	self:_setStamina(rider, stamina, now, self:_regenRate(rider))

	if reason == "ThrownOff" or reason == "KnockedOff" then
		rider.stunnedUntil = now + Tuning.STUN_TIME
	end
	rider.lastLeaveTime = now
	rider.lastLeaveVoluntary = reason == "Dismount"
	rider.lastLeftEggId = eggId

	self:_emit({
		type = "RideEnded",
		rider = rider.id,
		reason = reason,
		id = eggId,
		zone = if egg then egg.zone else 0,
		rarity = if egg then egg.rarity else "",
		kind = if egg then egg.kind else "",
	})

	if egg then
		egg.riderId = nil
		if reason == "Claimed" then
			self:_removeEgg(egg, "Claimed", rider.id)
		elseif reason == "Cliff" then
			self:_removeEgg(egg, "Cliff")
		else
			self:_leaveEgg(egg, now)
		end
	end
end

-- A player asks to jump onto an egg. `inReach` is RunwayService's verdict on whether the player's character is
-- close enough to the egg. Returns whether the ride started and, if not, why.
function RunwaySim.requestMount(
	self: RunwaySim,
	riderId: number,
	eggId: number,
	now: number,
	inReach: boolean
): (boolean, string?)
	local rider = self.riders[riderId]
	if rider == nil then
		return false, "NoRider"
	end
	if now - rider.lastMountRequest < Tuning.MOUNT_REQUEST_COOLDOWN then
		return false, "TooSoon"
	end
	rider.lastMountRequest = now

	if rider.eggId ~= nil then
		return false, "AlreadyRiding"
	end
	if now < rider.stunnedUntil then
		return false, "Stunned"
	end
	local egg = self.eggs[eggId]
	if egg == nil or egg.crackAt ~= nil then
		return false, "NoEgg"
	end
	if egg.riderId ~= nil then
		-- Duels will start here once they are built.
		return false, "Occupied"
	end
	if not inReach then
		return false, "TooFar"
	end

	local stamina = self:getStamina(riderId, now)

	-- Hop combo: landing on a different egg soon after jumping off one refunds some stamina.
	local hopped = rider.lastLeaveVoluntary
		and rider.lastLeaveTime ~= nil
		and now - rider.lastLeaveTime <= Tuning.HOP_COMBO_WINDOW
		and rider.lastLeftEggId ~= eggId
	if hopped then
		stamina = math.min(rider.maxStamina, stamina + rider.maxStamina * Tuning.HOP_COMBO_REFUND)
		rider.combo += 1
	else
		rider.combo = 0
	end
	rider.lastLeaveTime = nil

	local spec = egg.spec
	local ride: Ride = {
		startTime = now,
		startStamina = stamina,
		drain = spec.drain,
		claimAt = now + spec.claimTime,
		emptyAt = now + StaminaMath.timeUntilEmpty(stamina, spec.drain),
		lateralTime = now,
		hits = {},
	}
	-- From here the rider steers, starting from wherever the egg's path had taken it.
	egg.lateral = self:eggLateral(egg, now)
	rider.ride = ride
	rider.eggId = eggId
	egg.riderId = riderId

	self:_setStamina(rider, stamina, now, -spec.drain)
	self:_emit({ type = "EggMounted", id = eggId, rider = riderId, time = now })
	self:_emit({
		type = "RideStarted",
		rider = riderId,
		id = eggId,
		startTime = now,
		startStamina = stamina,
		drain = spec.drain,
		claimTime = spec.claimTime,
		combo = rider.combo,
	})
	return true, nil
end

-- The rider jumps off on purpose.
function RunwaySim.requestDismount(self: RunwaySim, riderId: number, now: number)
	local rider = self.riders[riderId]
	if rider and rider.eggId ~= nil then
		self:_endRide(rider, now, "Dismount")
	end
end

-- The rider's character died.
function RunwaySim.killRider(self: RunwaySim, riderId: number, now: number)
	local rider = self.riders[riderId]
	if rider and rider.eggId ~= nil then
		self:_endRide(rider, now, "Died")
	end
end

-- The player left the game.
function RunwaySim.removeRider(self: RunwaySim, riderId: number, now: number)
	local rider = self.riders[riderId]
	if rider == nil then
		return
	end
	if rider.eggId ~= nil then
		self:_endRide(rider, now, "Left")
	end
	self.riders[riderId] = nil
end

-- The rider's client reports where it has steered the egg. The move is capped at the rider's Agility, so a
-- cheating client cannot teleport the egg sideways. Returns the egg if the report was used.
function RunwaySim.setLateral(self: RunwaySim, riderId: number, x: number, now: number): Egg?
	local rider = self.riders[riderId]
	if rider == nil or rider.ride == nil or rider.eggId == nil then
		return nil
	end
	local egg = self.eggs[rider.eggId]
	if egg == nil then
		return nil
	end
	-- Reject NaN and infinity.
	if x ~= x or math.abs(x) == math.huge then
		return nil
	end

	local ride = rider.ride
	local elapsed = math.max(0, now - ride.lateralTime)
	local maxMove = rider.agility * elapsed * 1.5 + 2
	local target = Runway.clampLateral(x, egg.spec.halfLength)
	egg.lateral += math.clamp(target - egg.lateral, -maxMove, maxMove)
	ride.lateralTime = now
	return egg
end

----------------------------------------------------------------------------------------------------------------
-- Obstacles

-- A ridden egg ran into an obstacle: it is knocked clear of the obstacle's row, and the rider pays for it.
function RunwaySim._hitObstacle(self: RunwaySim, rider: Rider, egg: Egg, obstacle: Obstacles.Obstacle, now: number)
	local ride = rider.ride
	if ride == nil then
		return
	end
	ride.hits[obstacle.id] = true
	egg.lateral = self.obstacles.clearLane(obstacle.row, egg.lateral, egg.spec.halfLength)
	ride.lateralTime = now
	self:_emit({
		type = "ObstacleHit",
		rider = rider.id,
		id = egg.id,
		obstacle = obstacle.id,
		tier = obstacle.tier,
		lateral = egg.lateral,
		time = now,
	})

	if obstacle.tier == "Bump" then
		local stamina = math.max(0, self:getStamina(rider.id, now) - egg.spec.requirement * Tuning.BUMP_STAMINA)
		self:_setStamina(rider, stamina, now, -ride.drain)
		-- Out of stamina now means thrown off on the next step, as usual.
		ride.emptyAt = now + StaminaMath.timeUntilEmpty(stamina, ride.drain)
	elseif obstacle.tier == "KnockOff" then
		self:_endRide(rider, now, "KnockedOff")
	else
		self:_endRide(rider, now, "Hazard")
	end
end

-- The rider's device says their egg hit an obstacle. It is believed if the egg was near the obstacle about then
-- (the report has crossed the network) and the obstacle was dangerous. Returns whether the hit counted.
function RunwaySim.reportHit(self: RunwaySim, riderId: number, obstacleId: number, now: number): boolean
	local rider = self.riders[riderId]
	local ride = rider and rider.ride
	local egg = if rider and rider.eggId then self.eggs[rider.eggId] else nil
	local obstacle = self.obstacles.get(obstacleId)
	if rider == nil or ride == nil or egg == nil or obstacle == nil or ride.hits[obstacleId] then
		return false
	end
	local slack = Tuning.HIT_REPORT_SLACK
	local z = self:_eggZ(egg, now)
	local reachZ = egg.spec.radius + egg.spec.rollSpeed * slack
	local reachX = egg.spec.halfLength + rider.agility * slack + 3
	if math.abs(z - obstacle.z) > obstacle.hz + reachZ or math.abs(egg.lateral - obstacle.x) > obstacle.hx + reachX then
		return false
	end
	if not self.obstacles.activeAround(obstacle, now, slack) then
		return false
	end
	self:_hitObstacle(rider, egg, obstacle, now)
	return true
end

-- The server's own check: an egg well inside an obstacle has hit it, whatever its rider's device says.
function RunwaySim._checkObstacles(self: RunwaySim, now: number)
	for _, rider in self.riders do
		local ride = rider.ride
		local egg = if rider.eggId then self.eggs[rider.eggId] else nil
		if ride and egg then
			local obstacle = self.obstacles.hitAt(
				egg.lateral,
				self:_eggZ(egg, now),
				egg.spec.halfLength,
				egg.spec.radius,
				now,
				Tuning.HIT_BACKUP_INSET
			)
			if obstacle and not ride.hits[obstacle.id] then
				self:_hitObstacle(rider, egg, obstacle, now)
			end
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- The clock

-- Tells the rules which part of the runway cycle it is.
function RunwaySim.setPhase(self: RunwaySim, phase: Phase)
	if phase == self.phase then
		return
	end
	local wasClosed = self.phase == "Closed"
	self.phase = phase

	if phase == "Closed" then
		-- The runway closes: every egg without a rider disappears. Riders keep going.
		for _, egg in self.eggs do
			if egg.riderId == nil then
				self:_removeEgg(egg, "Closure")
			end
		end
	elseif wasClosed then
		-- Sunrise: a new cycle, so every zone rolls a fresh lineup on the next step.
		self.lineup = nil
		self.nextWildAt = {}
	end
end

-- Sends out lineup eggs whose turn has come, and now and then a mid-cycle egg.
function RunwaySim._launchEggs(self: RunwaySim, now: number)
	if self.lineup == nil then
		self:_rollLineup(now)
	end
	for _, slot in self.lineup :: { Slot } do
		if now >= slot.nextLaunch then
			-- If the server stalled for longer than a lap, skip the laps it missed.
			while now >= slot.nextLaunch + slot.lapTime do
				slot.nextLaunch += slot.lapTime
			end
			self:_launch(slot.zone, slot.rarity, slot.kind, slot.nextLaunch, false)
			slot.nextLaunch += slot.lapTime
		end
	end

	local interval = Tuning.WILD_DROP_INTERVAL / self.spawnRateMultiplier
	for zoneId = 1, #Zones.List do
		local at = self.nextWildAt[zoneId]
		if at == nil then
			at = now + interval * (0.5 + self.random())
			self.nextWildAt[zoneId] = at
		end
		if now >= at then
			if self:_countWild(zoneId) < Tuning.WILD_DROP_MAX then
				local rarity = EggSpec.rollRarity(zoneId, self.random(), Tuning.WILD_RARE_ODDS, Tuning.WILD_RARE_FROM)
				local kind = EggSpec.pickEgg(zoneId, rarity, self.random())
				if kind then
					self:_launch(zoneId, rarity, kind, now, true)
				end
			end
			self.nextWildAt[zoneId] = now + interval * (0.7 + 0.6 * self.random())
		end
	end
end

-- Advances the rules to `now`: sends out eggs, checks obstacles, finishes claims, throws off exhausted riders,
-- cracks and fades eggs.
function RunwaySim.step(self: RunwaySim, now: number)
	if self.phase ~= "Closed" then
		self:_launchEggs(now)
	end

	self:_checkObstacles(now)

	-- Finish rides: a claim that completes before the stamina runs out wins.
	for _, rider in self.riders do
		local ride = rider.ride
		if ride then
			if now >= ride.claimAt and ride.claimAt <= ride.emptyAt then
				local egg = self.eggs[rider.eggId :: number]
				if egg then
					self:_emit({
						type = "Claimed",
						rider = rider.id,
						zone = egg.zone,
						rarity = egg.rarity,
						kind = egg.kind,
					})
				end
				self:_endRide(rider, now, "Claimed")
			elseif now >= ride.emptyAt then
				self:_endRide(rider, now, "ThrownOff")
			end
		end
	end

	-- Eggs that crack, fade at the end of their lap, or roll off the end.
	for _, egg in self.eggs do
		if egg.crackAt ~= nil then
			if now >= egg.crackAt then
				self:_removeEgg(egg, "Cracked")
			end
		else
			local z = self:_eggZ(egg, now)
			local rider = if egg.riderId then self.riders[egg.riderId] else nil
			if rider == nil and z >= egg.fadeZ then
				self:_removeEgg(egg, "Faded")
			elseif z >= Runway.LENGTH then
				if rider then
					self:_endRide(rider, now, "Cliff")
				else
					self:_removeEgg(egg, "Cliff")
				end
			end
		end
	end
end

return RunwaySim
