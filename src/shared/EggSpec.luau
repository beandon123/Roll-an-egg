--!strict
-- Everything about one kind of egg (a zone + a rarity), worked out once from the config tables.

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

-- A rarity's drop weight in a zone under a luck multiplier: every rarity above Common is `luck` times as likely
-- (compared with Common) as normal.
local function luckyWeight(zone, rarity: string, luck: number): number
	local weight = zone.weights[rarity] or 0
	if rarity ~= "Common" then
		weight *= luck
	end
	return weight
end

-- Picks a rarity for a zone from a random number in [0, 1), using the zone's drop weights.
-- `luck` (default 1) comes from server luck boosts; see Shared/LuckBoost.
function EggSpec.rollRarity(zoneId: number, random01: number, luck: number?): string
	local zone = Zones.List[zoneId]
	local multiplier = math.max(1, luck or 1)
	local total = 0
	for _, rarity in Rarities.Order do
		total += luckyWeight(zone, rarity, multiplier)
	end

	local target = random01 * total
	local running = 0
	local last = "Common"
	for _, rarity in Rarities.Order do
		local weight = luckyWeight(zone, rarity, multiplier)
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

return EggSpec
