--!strict
-- The rules of the runway: eggs, riding, stamina, claiming, bounces and cracking, closures.
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
	-- Side-to-side position; steered by the rider.
	lateral: number,
	bouncesLeft: number,
	riderId: number?,
	everRidden: boolean,
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
export type RideEndReason = "Dismount" | "ThrownOff" | "Claimed" | "Cliff" | "Died" | "Left"
-- Why an egg left the runway.
export type EggRemoveReason = "Faded" | "Cracked" | "Claimed" | "Closure" | "Cliff"

export type SerializedEgg = {
	id: number,
	zone: number,
	rarity: string,
	kind: string,
	spawnTime: number,
	-- Where it landed, down the runway: its zone's chute, unless an admin dropped it somewhere else.
	startZ: number,
	lateral: number,
	rider: number?,
	bounces: number,
	bounceTime: number?,
	cracking: boolean,
}

export type Event =
	{ type: "EggSpawned", egg: SerializedEgg }
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
	| { type: "Claimed", rider: number, zone: number, rarity: string, kind: string }

local RunwaySim = {}
RunwaySim.__index = RunwaySim

export type RunwaySim = typeof(setmetatable(
	{} :: {
		random: () -> number,
		eggs: { [number]: Egg },
		riders: { [number]: Rider },
		nextEggId: number,
		nextSpawnAt: { [number]: number },
		phase: Phase,
		spawnRateMultiplier: number,
		-- Server luck (1 = normal): rarer eggs drop more often. See Shared/LuckBoost.
		luck: number,
		events: { Event },
	},
	RunwaySim
))

-- `random` returns a number in [0, 1); injected so tests can make drops predictable.
function RunwaySim.new(random: () -> number): RunwaySim
	local self = setmetatable({
		random = random,
		eggs = {},
		riders = {},
		nextEggId = 0,
		nextSpawnAt = {},
		phase = "Open" :: Phase,
		spawnRateMultiplier = 1,
		luck = 1,
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
		startZ = egg.startZ,
		lateral = egg.lateral,
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

-- The centre of an egg resting on the runway: x, y, z.
function RunwaySim.eggCenter(_self: RunwaySim, egg: Egg, now: number): (number, number, number)
	local z = EggMotion.zAt(egg.spawnTime, egg.startZ, egg.spec.rollSpeed, now)
	return egg.lateral, Runway.surfaceY(z) + egg.spec.radius, z
end

function RunwaySim._removeEgg(self: RunwaySim, egg: Egg, reason: EggRemoveReason, by: number?)
	self.eggs[egg.id] = nil
	self:_emit({ type = "EggRemoved", id = egg.id, reason = reason, by = by })
end

-- Where an egg should land instead of its zone's chute: `z` down the runway and `lateral` across it. Either can be
-- left out. Used by the admin panel to drop an egg in front of a player.
export type Placement = { z: number?, lateral: number? }

-- Drops a new egg at the start of a zone: a random rarity for the zone (rarer ones more often with server luck),
-- then one of the zone's eggs of that rarity. `forcedRarity` and `forcedKind` skip the random rolls; a forced egg
-- must belong to the zone. `placement` drops it somewhere else on the runway; it keeps its zone's rarity, size and
-- stamina wherever it lands.
function RunwaySim.spawnEgg(
	self: RunwaySim,
	zoneId: number,
	now: number,
	forcedRarity: string?,
	forcedKind: string?,
	placement: Placement?
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
		rarity = forcedRarity or EggSpec.rollRarity(zoneId, self.random(), self.luck)
		kind = EggSpec.pickEgg(zoneId, rarity, self.random())
	end
	local spec = EggSpec.get(zoneId, rarity)
	if spec == nil or kind == nil then
		return nil
	end

	local startZ = Runway.zoneStartZ(zoneId) + Tuning.EGG_SPAWN_OFFSET
	local lateral = (self.random() * 2 - 1) * Runway.maxLateral(spec.halfLength)
	if placement then
		local z, x = placement.z, placement.lateral
		-- On the runway, and far enough from the end cliff to be worth riding.
		if z and z == z then
			startZ = math.clamp(z, 0, Runway.LENGTH - spec.radius * 4)
		end
		if x and x == x then
			lateral = Runway.clampLateral(x, spec.halfLength)
		end
	end

	self.nextEggId += 1
	local egg: Egg = {
		id = self.nextEggId,
		zone = zoneId,
		rarity = rarity,
		kind = kind,
		spec = spec,
		spawnTime = now,
		startZ = startZ,
		lateral = lateral,
		bouncesLeft = spec.bounces,
		riderId = nil,
		everRidden = false,
		bounceTime = nil,
		crackAt = nil,
	}
	self.eggs[egg.id] = egg
	self:_emit({ type = "EggSpawned", egg = serialize(egg) })
	return egg
end

-- Called whenever an egg is left without a rider (and was not claimed): it hops and loses a bounce.
function RunwaySim._leaveEgg(self: RunwaySim, egg: Egg, now: number)
	if self.phase == "Closed" then
		-- An egg that loses its rider while the runway is closed disappears like the rest.
		self:_removeEgg(egg, "Closure")
		return
	end
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

-- Fills a player's stamina to their Max Stamina. A ride in progress keeps draining from the new value.
function RunwaySim.refillStamina(self: RunwaySim, riderId: number, now: number)
	local rider = self.riders[riderId]
	if rider == nil then
		return
	end
	local rate = if rider.ride then -rider.ride.drain else self:_regenRate(rider)
	self:_setStamina(rider, rider.maxStamina, now, rate)
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

	if reason == "ThrownOff" then
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
	}
	rider.ride = ride
	rider.eggId = eggId
	egg.riderId = riderId
	egg.everRidden = true

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
-- The clock

-- Sets the server luck used for every egg dropped from now on (1 = normal).
function RunwaySim.setLuck(self: RunwaySim, luck: number)
	self.luck = if luck == luck then math.max(1, luck) else 1
end

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
		-- A new cycle: every chute starts a fresh lineup.
		self.nextSpawnAt = {}
	end
end

-- Removes every egg without a rider, as a closure does, and returns how many went. Ridden eggs are left alone.
function RunwaySim.clearUnridden(self: RunwaySim): number
	local count = 0
	for _, egg in self.eggs do
		if egg.riderId == nil then
			self:_removeEgg(egg, "Closure")
			count += 1
		end
	end
	return count
end

function RunwaySim._countZone(self: RunwaySim, zoneId: number): number
	local count = 0
	for _, egg in self.eggs do
		if egg.zone == zoneId then
			count += 1
		end
	end
	return count
end

-- Advances the rules to `now`: drops eggs, finishes claims, throws off exhausted riders, cracks and fades eggs.
function RunwaySim.step(self: RunwaySim, now: number)
	-- Drop new eggs.
	if self.phase ~= "Closed" then
		local interval = Tuning.EGG_UNRIDDEN_LIFETIME / Tuning.EGGS_PER_ZONE / self.spawnRateMultiplier
		local cap = math.ceil(Tuning.EGGS_PER_ZONE * 1.5 * self.spawnRateMultiplier)
		for zoneId = 1, #Zones.List do
			local at = self.nextSpawnAt[zoneId]
			if at == nil then
				at = now + self.random() * interval * 0.5
				self.nextSpawnAt[zoneId] = at
			end
			if now >= at then
				if self:_countZone(zoneId) < cap then
					self:spawnEgg(zoneId, now)
				end
				self.nextSpawnAt[zoneId] = now + interval * (0.7 + 0.6 * self.random())
			end
		end
	end

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

	-- Eggs that crack, roll off the end, or fade.
	for _, egg in self.eggs do
		if egg.crackAt ~= nil then
			if now >= egg.crackAt then
				self:_removeEgg(egg, "Cracked")
			end
		else
			local z = EggMotion.zAt(egg.spawnTime, egg.startZ, egg.spec.rollSpeed, now)
			if z >= Runway.LENGTH then
				local rider = if egg.riderId then self.riders[egg.riderId] else nil
				if rider then
					self:_endRide(rider, now, "Cliff")
				else
					self:_removeEgg(egg, "Cliff")
				end
			elseif not egg.everRidden and now - egg.spawnTime >= Tuning.EGG_UNRIDDEN_LIFETIME then
				self:_removeEgg(egg, "Faded")
			end
		end
	end
end

return RunwaySim
