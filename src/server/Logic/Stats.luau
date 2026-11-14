--!strict
-- Numbers worked out from a player's saved data. Upgrades will add to these once they are built.
-- No Roblox objects, so tests run outside Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Trails = require(Shared.Config.Trails)
local Tuning = require(Shared.Config.Tuning)

local Stats = {}

-- The Max Stamina multiplier of the trail the player has equipped (1 with none).
function Stats.trailMultiplier(data): number
	local trails = data.Trails
	local trail = if trails then Trails.ById[trails.Equipped] else nil
	return if trail then trail.stamina else 1
end

function Stats.maxStamina(data): number
	return Tuning.BASE_MAX_STAMINA * Stats.trailMultiplier(data)
end

return Stats
