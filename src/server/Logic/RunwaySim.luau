--!strict
-- The rules of the runway: eggs, riding, stamina, claiming, cracking, the side walls, closures.
--
-- This module holds the rules only. It never touches players, parts, or remotes: RunwayService feeds it the
-- clock and player requests, then turns the events it emits into remotes and saved data. Keeping it free of
-- Roblox objects means the whole rulebook is covered by tests that run outside Studio (see tests/).
--
-- Eggs roll along the ground, and the runway has no end (see Shared/Runway). What can happen to an egg:
--   * Its rider runs out of stamina: it makes one small bounce and cracks open. The same egg comes back at the
--     start of its zone a few seconds later.
--   * Its rider steers it off the side through a gap in the wall: it falls, and comes back the same way.
--   * Its rider jumps off, crashes into a wall, dies, or leaves the game: it rolls on without them, free for anyone.
--   * Its claim meter fills: it goes into the rider's inventory at once. The rider keeps rolling on it for as long
--     as they like; when they get off, it disappears.
--   * Nobody is on it for a minute, or the runway closes while nobody is on it: it disappears.
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
	spec: EggSpec.Spec,
	spawnTime: number,
	startZ: number,
	-- Side-to-side position; steered by the rider.
	lateral: number,
	riderId: number?,
	-- Who claimed it. A claimed egg is already in their inventory: it stays on the runway only while they ride it.
	ownerId: number?,
	-- When it last had nobody on it (it appeared, or its rider left). It fades EGG_UNRIDDEN_LIFETIME after that.
	idleSince: number,
	-- Set when its rider ran out of stamina: the egg bounces from this moment and cracks when the bounce ends.
	bounceTime: number?,
}

export type Ride = {
	startTime: number,
	startStamina: number,
	drain: number,
	claimAt: number,
	emptyAt: number,
	lateralTime: number,
	-- Riding an egg already claimed: just for show, so no drain, no claim meter, and no being thrown off.
	claimed: boolean,
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
export type RideEndReason = "Dismount" | "ThrownOff" | "HitWall" | "FellOff" | "Died" | "Left"
-- Why an egg left the runway. "Claimed" is a claimed egg disappearing when its owner gets off.
export type EggRemoveReason = "Faded" | "Cracked" | "FellOff" | "Claimed" | "Closure"

export type SerializedEgg = {
	id: number,
	zone: number,
	rarity: string,
	spawnTime: number,
	lateral: number,
	rider: number?,
	owner: number?,
	bounceTime: number?,
}

type Respawn = { zone: number, rarity: string, at: number }

export type Event =
	{ type: "EggSpawned", egg: SerializedEgg }
	| { type: "EggRemoved", id: number, reason: EggRemoveReason, by: number? }
	| { type: "EggMounted", id: number, rider: number, time: number }
	| { type: "EggLeft", id: number, lateral: number, bounceTime: number? }
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
	| { type: "RideEnded", rider: number, reason: RideEndReason, id: number, zone: number, rarity: string }
	| { type: "StaminaChanged", rider: number, value: number, time: number, rate: number, max: number }
	| { type: "Claimed", rider: number, id: number, zone: number, rarity: string }

local RunwaySim = {}
RunwaySim.__index = RunwaySim

export type RunwaySim = typeof(setmetatable(
	{} :: {
		random: () -> number,
		eggs: { [number]: Egg },
		riders: { [number]: Rider },
		nextEggId: number,
		nextSpawnAt: { [number]: number },
		-- Eggs that cracked or fell off, waiting to appear again at the start of their zone.
		respawns: { Respawn },
		phase: Phase,
		spawnRateMultiplier: number,
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
		respawns = {},
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
		spawnTime = egg.spawnTime,
		lateral = egg.lateral,
		rider = egg.riderId,
		owner = egg.ownerId,
		bounceTime = egg.bounceTime,
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

-- The centre of an egg resting on the runway: x, y, z. In the endless last zone this is the spot it has been carried
-- back to (Runway.wrapZ).
function RunwaySim.eggCenter(_self: RunwaySim, egg: Egg, now: number): (number, number, number)
	local z = Runway.wrapZ(EggMotion.zAt(egg.spawnTime, egg.startZ, egg.spec.rollSpeed, now))
	return egg.lateral, Runway.surfaceY(z) + egg.spec.radius, z
end

function RunwaySim._removeEgg(self: RunwaySim, egg: Egg, reason: EggRemoveReason, by: number?)
	self.eggs[egg.id] = nil
	self:_emit({ type = "EggRemoved", id = egg.id, reason = reason, by = by })
end

-- The same egg comes back at the start of its zone after EGG_RESPAWN_DELAY.
function RunwaySim._respawnLater(self: RunwaySim, egg: Egg, now: number)
	if self.phase == "Closed" then
		return
	end
	table.insert(self.respawns, { zone = egg.zone, rarity = egg.rarity, at = now + Tuning.EGG_RESPAWN_DELAY })
end

-- Puts a new egg on the ground at the start of a zone. `forcedRarity` skips the random roll.
function RunwaySim.spawnEgg(self: RunwaySim, zoneId: number, now: number, forcedRarity: string?): Egg?
	local rarity = forcedRarity or EggSpec.rollRarity(zoneId, self.random())
	local spec = EggSpec.get(zoneId, rarity)
	if spec == nil then
		return nil
	end

	self.nextEggId += 1
	local limit = math.max(0, Runway.maxLateral(spec.halfLength) - Tuning.EGG_SPAWN_EDGE_MARGIN)
	local egg: Egg = {
		id = self.nextEggId,
		zone = zoneId,
		rarity = rarity,
		spec = spec,
		spawnTime = now,
		startZ = spec.startZ,
		lateral = (self.random() * 2 - 1) * limit,
		riderId = nil,
		ownerId = nil,
		idleSince = now,
		bounceTime = nil,
	}
	self.eggs[egg.id] = egg
	self:_emit({ type = "EggSpawned", egg = serialize(egg) })
	return egg
end

-- An egg has just lost its rider, for `reason`.
function RunwaySim._leaveEgg(self: RunwaySim, egg: Egg, now: number, reason: RideEndReason)
	if reason == "FellOff" then
		self:_removeEgg(egg, "FellOff")
		if egg.ownerId == nil then
			self:_respawnLater(egg, now)
		end
		return
	end
	if egg.ownerId ~= nil then
		-- Already in the owner's inventory; it was only on the runway for them to ride.
		self:_removeEgg(egg, "Claimed", egg.ownerId)
		return
	end
	if self.phase == "Closed" then
		-- An egg that loses its rider while the runway is closed disappears like the rest.
		self:_removeEgg(egg, "Closure")
		return
	end

	if reason == "ThrownOff" then
		-- The rider lost their balance: one small bounce, then it cracks (see step).
		egg.bounceTime = now
	elseif reason == "HitWall" then
		local limit = Runway.maxLateral(egg.spec.halfLength)
		egg.lateral = math.sign(egg.lateral) * math.max(0, limit - Tuning.WALL_KNOCKBACK)
	end
	egg.idleSince = now
	self:_emit({ type = "EggLeft", id = egg.id, lateral = egg.lateral, bounceTime = egg.bounceTime })
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
	local ride = rider.ride
	local draining = ride ~= nil and not ride.claimed
	local rate = if ride and draining then -ride.drain else self:_regenRate(rider)
	self:_setStamina(rider, current, now, rate)
	if ride and draining then
		ride.emptyAt = now + StaminaMath.timeUntilEmpty(rider.staminaValue, ride.drain)
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
	})

	if egg then
		egg.riderId = nil
		self:_leaveEgg(egg, now, reason)
	end
end

-- The claim meter is full: the egg goes into the rider's inventory now. The rider stays on and keeps rolling until
-- they get off; from here on the ride is only for show, so it costs no stamina and cannot throw them off.
function RunwaySim._claim(self: RunwaySim, rider: Rider, ride: Ride, now: number)
	local egg = self.eggs[rider.eggId :: number]
	if egg == nil then
		return
	end
	egg.ownerId = rider.id
	ride.claimed = true
	ride.drain = 0
	ride.claimAt = math.huge
	ride.emptyAt = math.huge
	self:_setStamina(rider, self:getStamina(rider.id, now), now, self:_regenRate(rider))
	self:_emit({ type = "Claimed", rider = rider.id, id = egg.id, zone = egg.zone, rarity = egg.rarity })
end

-- The egg is pressed against the side of the runway: a wall there kills the rider, a gap sends egg and rider over
-- the edge.
function RunwaySim._hitEdge(self: RunwaySim, rider: Rider, egg: Egg, now: number)
	local _, _, z = self:eggCenter(egg, now)
	local side = if egg.lateral > 0 then 1 else -1
	local reason: RideEndReason = if Runway.wallAt(side, z, egg.spec.radius) then "HitWall" else "FellOff"
	self:_endRide(rider, now, reason)
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
	if egg == nil then
		return false, "NoEgg"
	end
	if egg.bounceTime ~= nil then
		return false, "Cracking"
	end
	if egg.riderId ~= nil then
		-- Duels will start here once they are built.
		return false, "Occupied"
	end
	if egg.ownerId ~= nil then
		return false, "Claimed"
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
		claimed = false,
	}
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
-- cheating client cannot teleport the egg sideways. Returns the egg if the report was used. Reaching the side of the
-- runway is dealt with on the next step.
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

-- Tells the rules which part of the runway cycle it is.
function RunwaySim.setPhase(self: RunwaySim, phase: Phase)
	if phase == self.phase then
		return
	end
	local wasClosed = self.phase == "Closed"
	self.phase = phase

	if phase == "Closed" then
		-- The runway closes: every egg without a rider disappears, and nothing comes back. Riders keep going.
		for _, egg in self.eggs do
			if egg.riderId == nil then
				self:_removeEgg(egg, "Closure")
			end
		end
		self.respawns = {}
	elseif wasClosed then
		-- A new cycle: every zone starts a fresh lineup.
		self.nextSpawnAt = {}
	end
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

-- Advances the rules to `now`: brings back cracked and fallen eggs, drops new ones, finishes claims, throws off
-- exhausted riders, deals with eggs steered into the side, and cracks and fades eggs.
function RunwaySim.step(self: RunwaySim, now: number)
	if self.phase ~= "Closed" then
		-- Eggs that cracked or fell off, back at the start of their zone.
		local waiting = {}
		for _, respawn in self.respawns do
			if now >= respawn.at then
				self:spawnEgg(respawn.zone, now, respawn.rarity)
			else
				table.insert(waiting, respawn)
			end
		end
		self.respawns = waiting

		-- New eggs.
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

	for _, rider in self.riders do
		local ride = rider.ride
		local egg = if rider.eggId then self.eggs[rider.eggId] else nil
		if ride == nil or egg == nil then
			continue
		end
		-- A claim that completes before the stamina runs out wins.
		if not ride.claimed then
			if now >= ride.claimAt and ride.claimAt <= ride.emptyAt then
				self:_claim(rider, ride, now)
			elseif now >= ride.emptyAt then
				self:_endRide(rider, now, "ThrownOff")
				continue
			end
		end
		if Runway.isAtEdge(egg.lateral, egg.spec.halfLength) then
			self:_hitEdge(rider, egg, now)
		end
	end

	-- Eggs that finish their bounce crack open; eggs nobody has been on for a while fade.
	for _, egg in self.eggs do
		if egg.bounceTime ~= nil then
			if now >= egg.bounceTime + Tuning.CRACK_BOUNCE_TIME then
				self:_removeEgg(egg, "Cracked")
				self:_respawnLater(egg, now)
			end
		elseif egg.riderId == nil and now - egg.idleSince >= Tuning.EGG_UNRIDDEN_LIFETIME then
			self:_removeEgg(egg, "Faded")
		end
	end
end

return RunwaySim
