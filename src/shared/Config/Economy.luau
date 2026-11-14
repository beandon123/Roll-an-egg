--!strict
-- What things are worth in coins. First-pass numbers; adjust in economy tuning.
-- Pure (no Roblox APIs) so the test runner can load it outside Studio.

local Zones = require(script.Parent.Zones)

local Economy = {}

-- An egg sells at the Sell stall for this fraction of its stamina requirement, so eggs that are harder to hold on
-- to are worth more: a Forest Common sells for 25 coins, a Volcano Eternal for 75K.
Economy.EGG_SELL_FRACTION = 0.5

-- Coins for selling one egg, or nil if that rarity cannot drop in that zone.
function Economy.eggSellValue(zoneId: number, rarity: string): number?
	local zone = Zones.List[zoneId]
	if zone == nil then
		return nil
	end
	local requirement = zone.stamina[rarity]
	if requirement == nil then
		return nil
	end
	return math.floor(requirement * Economy.EGG_SELL_FRACTION)
end

return Economy
