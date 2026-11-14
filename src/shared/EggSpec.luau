--!strict
-- Everything about one tier of egg (a zone + a rarity), worked out once from the config tables: its size, speed,
-- claim time and stamina. Every egg of the same zone and rarity shares these; only the look differs.

local Config = script.Parent.Config
local Rarities = require(Config.Rarities)
local StaminaMath = require(script.Parent.StaminaMath)
local Tuning = require(Config.Tuning)
local Zones = require(Config.Zones)

export type Spec = {
	zone: number,
	rarity: string,
	-- Rolling radius in studs.
	radius: number,
	-- Half the egg's side-to-side length in studs.
	halfLength: number,
	rollSpeed: number,
	claimTime: number,
	bounces: number,
	-- Stamina requirement shown on the egg.
	requirement: number,
	-- Stamina lost per second while riding it.
	drain: number,
}

local EggSpec = {}

local cache: { [string]: Spec } = {}

-- The spec for a zone + rarity, or nil if that rarity cannot drop in that zone.
function EggSpec.get(zoneId: number, rarity: string): Spec?
	local key = zoneId .. ":" .. rarity
	local cached = cache[key]
	if cached then
		return cached
	end

	local zone = Zones.List[zoneId]
	local info = Rarities.Info[rarity]
	if zone == nil or info == nil then
		return nil
	end
	local requirement = zone.stamina[rarity]
	if requirement == nil then
		return nil
	end

	local radius = Tuning.EGG_BASE_RADIUS * info.size
	local spec: Spec = {
		zone = zoneId,
		rarity = rarity,
		radius = radius,
		halfLength = radius * Tuning.EGG_LENGTH_RATIO,
		rollSpeed = info.rollSpeed,
		claimTime = info.claimTime,
		bounces = info.bounces,
		requirement = requirement,
		drain = StaminaMath.drainRate(requirement, info.claimTime, Tuning.DRAIN_FRACTION),
	}
	cache[key] = spec
	return spec
end

-- Picks a rarity for a zone from a random number in [0, 1), using the zone's drop weights. `rareOdds`, if given,
-- scales the weight of every rarity from `rareFrom` up (mid-cycle drops use it to make Secret and Eternal eggs
-- much rarer than in the lineup rolled at sunrise).
function EggSpec.rollRarity(zoneId: number, random01: number, rareOdds: number?, rareFrom: string?): string
	local zone = Zones.List[zoneId]
	local fromOrder = if rareFrom and Rarities.Info[rareFrom] then Rarities.Info[rareFrom].order else math.huge
	local function weightOf(rarity: string): number
		local weight = zone.weights[rarity] or 0
		if rareOdds and Rarities.Info[rarity].order >= fromOrder then
			weight *= rareOdds
		end
		return weight
	end

	local total = 0
	for _, rarity in Rarities.Order do
		total += weightOf(rarity)
	end

	local target = random01 * total
	local running = 0
	local last = ""
	for _, rarity in Rarities.Order do
		local weight = weightOf(rarity)
		if weight > 0 then
			running += weight
			last = rarity
			if target < running then
				return rarity
			end
		end
	end
	return last
end

-- The zone's eggs of one rarity (design names such as "MossStag"), in the order the zone lists them.
function EggSpec.eggsOf(zoneId: number, rarity: string): { string }
	local zone = Zones.List[zoneId]
	local list = {}
	if zone then
		for _, entry in zone.eggs do
			if entry.rarity == rarity then
				table.insert(list, entry.egg)
			end
		end
	end
	return list
end

-- Picks one of the zone's eggs of a rarity from a random number in [0, 1), each equally likely.
function EggSpec.pickEgg(zoneId: number, rarity: string, random01: number): string?
	local list = EggSpec.eggsOf(zoneId, rarity)
	if #list == 0 then
		return nil
	end
	return list[math.clamp(math.floor(random01 * #list) + 1, 1, #list)]
end

-- The zone and rarity an egg drops at, or nil if it is in no zone's lineup.
function EggSpec.placeOf(kind: string): (number?, string?)
	for zoneId, zone in Zones.List do
		for _, entry in zone.eggs do
			if entry.egg == kind then
				return zoneId, entry.rarity
			end
		end
	end
	return nil, nil
end

return EggSpec
