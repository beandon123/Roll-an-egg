--!strict
-- Numbers worked out from a player's saved data.
-- No Roblox objects, so tests run outside Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Shop = require(Shared.Config.Shop)
local Trails = require(Shared.Config.Trails)
local Tuning = require(Shared.Config.Tuning)

local Stats = {}

-- The Max Stamina multiplier of the trail the player has equipped (1 with none).
function Stats.trailMultiplier(data): number
	local trails = data.Trails
	local trail = if trails then Trails.ById[trails.Equipped] else nil
	return if trail then trail.stamina else 1
end

-- Max Stamina from everything the player owns: the base plus Max Stamina bought in the shop, times their
-- doublings, times their equipped trail's boost.
function Stats.maxStamina(data): number
	return Shop.maxStamina(Tuning.BASE_MAX_STAMINA, data.MaxStaminaBonus or 0, data.StaminaMultiplier or 1)
		* Stats.trailMultiplier(data)
end

return Stats
