--!strict
-- The rules of the runway: the egg lineup, riding, stamina, claiming, obstacles, cracking, the banks, closures.
--
-- Eggs: at sunrise (the start of each cycle) every zone rolls a lineup of eggs. They appear on the ground at the
-- start of the zone a few seconds apart, roll down the runway, fade out a quarter of the way into the next zone, and
-- appear at the start again, lap after lap, until the runway closes. Now and then a zone also drops an extra,
-- mid-cycle egg, which rolls once; Secret and rarer eggs are much less likely mid-cycle than in the sunrise lineup.
--
-- What can happen to an egg while it rolls:
--   * Its rider runs out of stamina: they lose their balance, and the egg makes one small bounce and cracks open.
--     The same egg comes back at the start of its zone EGG_RESPAWN_DELAY later.
--   * Its rider steers it into a gap in the banks: egg and rider go over the edge; the egg comes back the same way.
--   * Its rider steers it into a bank: the rider dies, and the egg rolls on without them.
--   * Its rider jumps off, is knocked off, or dies: it rolls on without them, free for anyone.
--   * Its claim meter fills: it goes into the rider's inventory at once. The rider keeps rolling on it for as long
--     as they like; when they get off, it disappears (a lineup egg comes back on its next lap).
-- The runway has no end (Shared/Runway): an egg ridden past the end of the loop is carried back one loop.
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
local Rarities = require(Shared.Config.Rarities)
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
	-- The lineup slot it was launched from, if any.
	slot: Slot?,
	riderId: number?,
	-- Who claimed it. A claimed egg is already in their inventory: it stays on the runway only while they ride it.
	ownerId: number?,
	-- Set when its rider ran out of stamina: the egg bounces from this moment, cracks at `crackAt`, and nobody can
	-- get on it meanwhile.
	bounceTime: number?,
	crackAt: number?,
}

export type Ride = {
	startTime: number,
	startStamina: number,
	drain: number,
	claimAt: number,
	emptyAt: number,
	lateralTime: number,
	-- Obstacles this ride has already hit, by id, so each one counts once (per loop of the endless last zone).
	hits: { [number]: boolean },
	-- Where the egg was last checked, to notice it being carried back one loop.
	lastZ: number,
	-- Riding an egg already claimed: just for show, so no drain, no claim meter, and no being thrown off.
	claimed: boolean,
}

-- One egg of a zone's sunrise lineup: the egg, and when it next leaves the chute.
export type Slot = {
	zone: number,
	rarity: string,
	kind: string,
	nextLaunch: number,
	-- Seconds from the chute to the fade line.
	lapTime: number,
	-- Added when an Egg Avalanche started mid-cycle; dropped again if it stops.
	extra: boolean?,
	-- Whether it has left the start yet today (a Secret or rarer egg is announced on its first lap only).
	launched: boolean?,
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
	-- Riding a pet (not an egg): stamina drains at Tuning.PET_RIDE_DRAIN, and the pet bucks them off at `petEmptyAt`.
	onPet: boolean,
	petEmptyAt: number,
}

-- Why a ride ended.
-- (KnockedOff: hit a KnockOff obstacle. Hazard: hit a Lethal one, which kills the rider. HitWall: steered into a
-- bank, which kills the rider. FellOff: steered into a gap in the banks, over the edge with the egg.)
export type RideEndReason = "Dismount" | "ThrownOff" | "KnockedOff" | "Hazard" | "HitWall" | "FellOff" | "Died" | "Left"
-- Why an egg left the runway. "Claimed" is a claimed egg disappearing when its owner gets off.
export type EggRemoveReason = "Faded" | "Cracked" | "FellOff" | "Claimed" | "Closure"

export type SerializedEgg = {
	id: number,
	zone: number,
	rarity: string,
	kind: string,
	spawnTime: number,
	-- Where it landed, down the runway: its zone's chute, unless an admin dropped it somewhere else.
	startZ: number,
	lateral: number,
	pathZ: number,
	rider: number?,
	owner: number?,
	-- Set while it bounces before cracking.
	bounceTime: number?,
}

-- An egg that cracked or went over the edge, waiting to appear at the start of its zone again (mid-cycle eggs;
-- lineup eggs just leave the start again sooner).
type Respawn = { zone: number, rarity: string, kind: string, at: number }

export type Event =
	-- `announce`: put the on-screen message for a Secret or rarer egg up (each mid-cycle drop, and a lineup egg's
	-- first lap of the day; not every lap).
	{ type: "EggSpawned", egg: SerializedEgg, wild: boolean, announce: boolean }
	| { type: "LineupRolled", eggs: { { zone: number, rarity: string, kind: string } } }
	| { type: "EggRemoved", id: number, reason: EggRemoveReason, by: number? }
	| { type: "EggMounted", id: number, rider: number, time: number }
	| { type: "EggLeft", id: number, time: number, lateral: number, cracking: boolean }
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
	| { type: "Claimed", rider: number, id: number, zone: number, rarity: string, kind: string }
	-- The rider's pet ran their stamina out and bucked them off.
	| { type: "PetBucked", rider: number }

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
		respawns: { Respawn },
		phase: Phase,
		spawnRateMultiplier: number,
		-- Server luck (1 = normal): rarer eggs drop more often. See Shared/LuckBoost.
		luck: number,
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
		respawns = {},
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
		pathZ = egg.pathZ,
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

-- Where an egg is down the runway. Past the end of the loop it has been carried back (Runway.wrapZ).
function RunwaySim._eggZ(_self: RunwaySim, egg: Egg, now: number): number
	return Runway.wrapZ(EggMotion.zAt(egg.spawnTime, egg.startZ, egg.spec.rollSpeed, now))
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
	egg.lateral = Runway.clampLateral(lateral, egg.spec.halfLength, z)
	egg.pathZ = z
	egg.path = self.obstacles.planPath(egg.lateral, z, egg.fadeZ, egg.spec.halfLength, egg.spec.radius)
end

function RunwaySim._removeEgg(self: RunwaySim, egg: Egg, reason: EggRemoveReason, by: number?)
	self.eggs[egg.id] = nil
	self:_emit({ type = "EggRemoved", id = egg.id, reason = reason, by = by })
end

-- Where an egg should land instead of its zone's chute: `z` down the runway and `lateral` across it. Either can be
-- left out. Used by the admin panel to drop an egg in front of a player.
export type Placement = { z: number?, lateral: number? }

-- Puts an egg on the ground at the start of its zone, leaving at `spawnTime`, or where `placement` says. `slot` is
-- the lineup slot it comes from, if any.
function RunwaySim._launch(
	self: RunwaySim,
	zoneId: number,
	rarity: string,
	kind: string,
	spawnTime: number,
	wild: boolean,
	placement: Placement?,
	slot: Slot?
): Egg?
	local spec = EggSpec.get(zoneId, rarity)
	if spec == nil then
		return nil
	end
	self.nextEggId += 1
	local startZ = spec.startZ
	local placedZ = placement and placement.z
	-- On the runway, and far enough before the end of the loop to be worth riding.
	if placedZ and placedZ == placedZ then
		startZ = math.clamp(placedZ, 0, Runway.LOOP_END - spec.radius * 4)
	end
	-- Clear of the banks, so a rider who gets on is not straight against one.
	local low, high = Runway.lateralRange(spec.halfLength, startZ)
	low = math.min(0, low + Tuning.EGG_SPAWN_EDGE_MARGIN)
	high = math.max(0, high - Tuning.EGG_SPAWN_EDGE_MARGIN)
	local lateral = low + self.random() * (high - low)
	local placedX = placement and placement.lateral
	if placedX and placedX == placedX then
		lateral = Runway.clampLateral(placedX, spec.halfLength, startZ)
	end
	local egg: Egg = {
		id = self.nextEggId,
		zone = zoneId,
		rarity = rarity,
		kind = kind,
		spec = spec,
		spawnTime = spawnTime,
		startZ = startZ,
		-- An egg dropped further down than its zone still gets a stretch of runway before it fades (but fades before
		-- the end of the loop).
		fadeZ = EggSpec.fadeZ(zoneId, startZ),
		lateral = 0,
		pathZ = startZ,
		path = nil :: any,
		wild = wild,
		slot = slot,
		riderId = nil,
		ownerId = nil,
		bounceTime = nil,
		crackAt = nil,
	}
	self:_setPath(egg, lateral, startZ)
	self.eggs[egg.id] = egg
	local firstLap = slot == nil or not slot.launched
	if slot then
		slot.launched = true
	end
	self:_emit({
		type = "EggSpawned",
		egg = serialize(egg),
		wild = wild,
		announce = firstLap and Rarities.Info[rarity].announce,
	})
	return egg
end

-- Drops an extra egg at the start of a zone, now: a random rarity for the zone (rarer ones more often with server
-- luck), then one of the zone's eggs of that rarity. It rolls once, like a mid-cycle drop. `forcedRarity` and
-- `forcedKind` skip the random rolls; a forced egg must belong to the zone. `placement` drops it somewhere else on
-- the runway; it keeps its zone's rarity, size and stamina wherever it lands.
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
	if kind == nil then
		return nil
	end
	return self:_launch(zoneId, rarity, kind, now, true, placement)
end

-- How many eggs a zone's lineup holds at the current egg rate (EggSpec.lineupSize at the usual rate).
local function lineupSize(zoneId: number, rate: number): number
	return math.max(1, math.round(EggSpec.lineupSize(zoneId) * rate))
end

-- Rolls `count` lineup eggs for a zone, leaving the chute EggSpec.lineupGap seconds apart (less while eggs drop
-- faster) from `firstLaunch`.
function RunwaySim._rollSlots(
	self: RunwaySim,
	zoneId: number,
	count: number,
	firstLaunch: number,
	extra: boolean,
	into: { Slot },
	rolled: { any }
)
	local gap = EggSpec.lineupGap(zoneId, self.spawnRateMultiplier)
	for index = 1, count do
		local rarity = EggSpec.rollRarity(zoneId, self.random(), self.luck)
		local kind = EggSpec.pickEgg(zoneId, rarity, self.random())
		local spec = EggSpec.get(zoneId, rarity)
		if kind and spec then
			local startZ = spec.startZ
			table.insert(into, {
				zone = zoneId,
				rarity = rarity,
				kind = kind,
				nextLaunch = firstLaunch + (index - 1) * gap,
				lapTime = (Runway.fadeZ(zoneId) - startZ) / spec.rollSpeed,
				extra = if extra then true else nil,
			})
			table.insert(rolled, { zone = zoneId, rarity = rarity, kind = kind })
		end
	end
end

-- Rolls every zone's lineup for a new day.
function RunwaySim._rollLineup(self: RunwaySim, now: number)
	local lineup: { Slot } = {}
	local rolled = {}
	for zoneId = 1, #Zones.List do
		self:_rollSlots(zoneId, lineupSize(zoneId, self.spawnRateMultiplier), now, false, lineup, rolled)
	end
	self.lineup = lineup
	self:_emit({ type = "LineupRolled", eggs = rolled })
end

-- Sets how many eggs drop, as a multiple of the usual (2 during an Egg Avalanche). Started mid-cycle, every zone's
-- lineup grows at once, the new eggs leaving the chute from now; stopped, those extra eggs stop coming back (the
-- ones already rolling finish their lap).
function RunwaySim.setEggRate(self: RunwaySim, multiplier: number, now: number)
	multiplier = if multiplier == multiplier then math.clamp(multiplier, 1, 10) else 1
	if multiplier == self.spawnRateMultiplier then
		return
	end
	self.spawnRateMultiplier = multiplier
	self.nextWildAt = {}
	local lineup = self.lineup
	if lineup == nil or self.phase == "Closed" then
		return
	end
	-- Drop the extras of an earlier Avalanche, then add what this rate needs beyond the sunrise lineup.
	for index = #lineup, 1, -1 do
		if lineup[index].extra then
			table.remove(lineup, index)
		end
	end
	local rolled = {}
	for zoneId = 1, #Zones.List do
		local have = 0
		for _, slot in lineup do
			if slot.zone == zoneId then
				have += 1
			end
		end
		local more = lineupSize(zoneId, multiplier) - have
		if more > 0 then
			self:_rollSlots(zoneId, more, now, true, lineup, rolled)
		end
	end
	if #rolled > 0 then
		self:_emit({ type = "LineupRolled", eggs = rolled })
	end
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

-- An egg that cracked or went over the edge comes back at the start of its zone EGG_RESPAWN_DELAY later: a lineup
-- egg by leaving the start again sooner than its next lap, a mid-cycle egg as a new mid-cycle egg.
function RunwaySim._respawnSoon(self: RunwaySim, egg: Egg, now: number)
	if self.phase == "Closed" then
		return
	end
	local at = now + Tuning.EGG_RESPAWN_DELAY
	local slot = egg.slot
	if slot and self.lineup and table.find(self.lineup, slot) then
		slot.nextLaunch = math.min(slot.nextLaunch, at)
	elseif slot == nil then
		table.insert(self.respawns, { zone = egg.zone, rarity = egg.rarity, kind = egg.kind, at = at })
	end
end

-- An egg has just lost its rider, for `reason`.
function RunwaySim._leaveEgg(self: RunwaySim, egg: Egg, now: number, reason: RideEndReason)
	if reason == "FellOff" then
		self:_removeEgg(egg, "FellOff")
		if egg.ownerId == nil then
			self:_respawnSoon(egg, now)
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
	local z = self:_eggZ(egg, now)
	if z >= egg.fadeZ then
		-- Ridden past its fade line: with nobody on it, it fades like any other.
		self:_removeEgg(egg, "Faded")
		return
	end
	if reason == "HitWall" then
		local side = if egg.lateral > 0 then 1 else -1
		local limit = Runway.maxLateral(egg.spec.halfLength, z, side)
		egg.lateral = side * math.max(0, limit - Tuning.WALL_KNOCKBACK)
	end
	self:_setPath(egg, egg.lateral, z)
	-- Only running out of stamina cracks an egg: the rider lost their balance, so it bounces and cracks open.
	local cracking = reason == "ThrownOff"
	if cracking then
		egg.bounceTime = now
		egg.crackAt = now + Tuning.CRACK_BOUNCE_TIME
	end
	self:_emit({ type = "EggLeft", id = egg.id, time = now, lateral = egg.lateral, cracking = cracking })
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
		onPet = false,
		petEmptyAt = math.huge,
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
	self:_restartStamina(rider, current, now)
end

-- Sets a rider's stamina, draining it while they ride an unclaimed egg or a pet, and refilling it otherwise.
function RunwaySim._restartStamina(self: RunwaySim, rider: Rider, value: number, now: number)
	local ride = rider.ride
	local onEgg = ride ~= nil and not ride.claimed
	local onPet = rider.onPet and rider.eggId == nil
	local rate = if ride and onEgg then -ride.drain elseif onPet then -Tuning.PET_RIDE_DRAIN else self:_regenRate(rider)
	self:_setStamina(rider, value, now, rate)
	if ride and onEgg then
		ride.emptyAt = now + StaminaMath.timeUntilEmpty(rider.staminaValue, ride.drain)
	end
	rider.petEmptyAt = if onPet
		then now + StaminaMath.timeUntilEmpty(rider.staminaValue, Tuning.PET_RIDE_DRAIN)
		else math.huge
end

-- The player gets on their pet (`onPet`), or off it. Riding a pet costs PET_RIDE_DRAIN stamina a second; when it
-- runs out the pet bucks them off (a PetBucked event). Returns false, changing nothing, if they are too tired to get
-- on (less than PET_RIDE_MIN_STAMINA) or are riding an egg.
function RunwaySim.setOnPet(self: RunwaySim, riderId: number, onPet: boolean, now: number): boolean
	local rider = self.riders[riderId]
	if rider == nil then
		return false
	end
	if onPet == rider.onPet then
		return true
	end
	local stamina = self:getStamina(riderId, now)
	if onPet and (rider.eggId ~= nil or stamina < Tuning.PET_RIDE_MIN_STAMINA) then
		return false
	end
	rider.onPet = onPet
	self:_restartStamina(rider, stamina, now)
	return true
end

-- Fills a player's stamina to their Max Stamina. A ride in progress keeps draining from the new value.
function RunwaySim.refillStamina(self: RunwaySim, riderId: number, now: number)
	local rider = self.riders[riderId]
	if rider == nil then
		return
	end
	self:_restartStamina(rider, rider.maxStamina, now)
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
	self:_emit({
		type = "Claimed",
		rider = rider.id,
		id = egg.id,
		zone = egg.zone,
		rarity = egg.rarity,
		kind = egg.kind,
	})
end

-- The egg is pressed against the side of the runway: a bank there kills the rider, a gap sends egg and rider over
-- the edge.
function RunwaySim._hitEdge(self: RunwaySim, rider: Rider, egg: Egg, now: number)
	local side = if egg.lateral > 0 then 1 else -1
	local onBank = Runway.wallAt(side, self:_eggZ(egg, now), egg.spec.radius)
	self:_endRide(rider, now, if onBank then "HitWall" else "FellOff")
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
	if egg.crackAt ~= nil then
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
		hits = {},
		lastZ = self:_eggZ(egg, now),
		claimed = false,
	}
	-- From here the rider steers, starting from wherever the egg's path had taken it (a little way in from a bank).
	egg.lateral = Runway.mountLateral(self:eggLateral(egg, now), egg.spec.halfLength, self:_eggZ(egg, now))
	rider.ride = ride
	rider.eggId = eggId
	egg.riderId = riderId
	-- Off their pet, if they were on one (RunwayService sends it away).
	rider.onPet = false
	rider.petEmptyAt = math.huge

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
	local target = Runway.clampLateral(x, egg.spec.halfLength, self:_eggZ(egg, now))
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
		if not ride.claimed then
			-- Out of stamina now means thrown off on the next step, as usual. (A claimed egg's ride costs nothing.)
			local stamina = math.max(0, self:getStamina(rider.id, now) - egg.spec.requirement * Tuning.BUMP_STAMINA)
			self:_restartStamina(rider, stamina, now)
		end
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
			local z = self:_eggZ(egg, now)
			if z < ride.lastZ - Runway.LOOP_LENGTH / 2 then
				-- Carried back one loop: the obstacles ahead can be hit again.
				ride.hits = {}
			end
			ride.lastZ = z
			local obstacle =
				self.obstacles.hitAt(egg.lateral, z, egg.spec.halfLength, egg.spec.radius, now, Tuning.HIT_BACKUP_INSET)
			if obstacle and not ride.hits[obstacle.id] then
				self:_hitObstacle(rider, egg, obstacle, now)
			end
		end
	end
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
		self.respawns = {}
	elseif wasClosed then
		-- Sunrise: a new cycle, so every zone rolls a fresh lineup on the next step.
		self.lineup = nil
		self.nextWildAt = {}
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

-- Sends out lineup eggs whose turn has come, eggs coming back after cracking or going over the edge, and now and then
-- a mid-cycle egg.
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
			self:_launch(slot.zone, slot.rarity, slot.kind, slot.nextLaunch, false, nil, slot)
			slot.nextLaunch += slot.lapTime
		end
	end

	local waiting = {}
	for _, respawn in self.respawns do
		if now >= respawn.at then
			self:_launch(respawn.zone, respawn.rarity, respawn.kind, now, true)
		else
			table.insert(waiting, respawn)
		end
	end
	self.respawns = waiting

	local interval = Tuning.WILD_DROP_INTERVAL / self.spawnRateMultiplier
	for zoneId = 1, #Zones.List do
		local at = self.nextWildAt[zoneId]
		if at == nil then
			at = now + interval * (0.5 + self.random())
			self.nextWildAt[zoneId] = at
		end
		if now >= at then
			if self:_countWild(zoneId) < Tuning.WILD_DROP_MAX * self.spawnRateMultiplier then
				local rarity =
					EggSpec.rollRarity(zoneId, self.random(), self.luck, Tuning.WILD_RARE_ODDS, Tuning.WILD_RARE_FROM)
				local kind = EggSpec.pickEgg(zoneId, rarity, self.random())
				if kind then
					self:_launch(zoneId, rarity, kind, now, true)
				end
			end
			self.nextWildAt[zoneId] = now + interval * (0.7 + 0.6 * self.random())
		end
	end
end

-- Advances the rules to `now`: sends out eggs, checks obstacles, finishes claims, throws off exhausted riders, deals
-- with eggs steered into the side, and cracks and fades eggs.
function RunwaySim.step(self: RunwaySim, now: number)
	if self.phase ~= "Closed" then
		self:_launchEggs(now)
	end

	self:_checkObstacles(now)

	-- Pets that have run their riders' stamina out buck them off.
	for _, rider in self.riders do
		if rider.onPet and rider.eggId == nil and now >= rider.petEmptyAt then
			rider.onPet = false
			self:_restartStamina(rider, 0, now)
			self:_emit({ type = "PetBucked", rider = rider.id })
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
		if Runway.isAtEdge(egg.lateral, egg.spec.halfLength, self:_eggZ(egg, now)) then
			self:_hitEdge(rider, egg, now)
		end
	end

	-- Eggs that finish their bounce crack open; riderless eggs fade at the end of their lap.
	for _, egg in self.eggs do
		if egg.crackAt ~= nil then
			if now >= egg.crackAt then
				self:_removeEgg(egg, "Cracked")
				self:_respawnSoon(egg, now)
			end
		elseif egg.riderId == nil and self:_eggZ(egg, now) >= egg.fadeZ then
			self:_removeEgg(egg, "Faded")
		end
	end
end

return RunwaySim
