--!strict
-- Money, pets' worth and the pen: first-pass numbers, to adjust in playtests.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.
--
-- The currency is dollars. Pets in a player's pen earn dollars every second; a pet can also be sold for a lump
-- sum. Dollars buy a bigger pen (the green button at its front). Unwanted eggs sell at the Sell stall in the hub.

local Zones = require(script.Parent.Zones)

local Economy = {}

-- Dollars a second a Forest pet earns, by rarity. Each zone's pets earn ZONE_SCALE times the zone before's, so a
-- new zone's Common pets earn about what the zone before's best do.
Economy.RARITY_INCOME = {
	Common = 1,
	Uncommon = 1.6,
	Rare = 2.5,
	Epic = 4,
	Legendary = 6.5,
	Mythic = 10,
	Secret = 16,
	Eternal = 25,
}
Economy.ZONE_SCALE = 10

-- What selling a pet pays, in seconds of its income.
Economy.SELL_SECONDS = 150

-- Variants (shown to players as mutations): when an egg hatches, its pet may come out Gold (8%), Diamond (4%) or
-- Rainbow (1%) instead of Normal (decided, odds and worth too). Each is rarer and worth more (income and sale price are
-- multiplied) and rides a little faster. Silver is shelved (chance 0): it no longer hatches, but pets that already
-- have it keep it. Molten and Crystal never hatch either (chance 0): they are only the pets that come in the
-- shop's packs (Config/Shop).
-- Rarest hatchable mutation last among the hatchable ones; PetWorth.rollVariant checks the rarest first.
export type Variant = { name: string, chance: number, worth: number, speedBonus: number }
Economy.VARIANTS = {
	{ name = "Normal", chance = 0, worth = 1, speedBonus = 0 },
	{ name = "Silver", chance = 0, worth = 2, speedBonus = 2 },
	{ name = "Gold", chance = 0.08, worth = 1.5, speedBonus = 4 },
	{ name = "Diamond", chance = 0.04, worth = 3, speedBonus = 5 },
	{ name = "Rainbow", chance = 0.01, worth = 10, speedBonus = 6 },
	{ name = "Molten", chance = 0, worth = 10, speedBonus = 8 },
	{ name = "Crystal", chance = 0, worth = 10, speedBonus = 8 },
} :: { Variant }

-- How fast a pet carries its rider round the hub (studs per second; walking is 16), by rarity. Pets never go on the
-- runway.
Economy.MOUNT_SPEED = {
	Common = 33,
	Uncommon = 36,
	Rare = 41,
	Epic = 45,
	Legendary = 50,
	Mythic = 54,
	Secret = 60,
	Eternal = 66,
}

-- The pen. It starts at level 1; each level makes it wider and holds one more egg and one more pet.
Economy.MAX_PEN_LEVEL = 9
-- Dollars to go up to each level (index = the level bought).
Economy.PEN_UPGRADE_COST = {
	[2] = 750,
	[3] = 5_000,
	[4] = 30_000,
	[5] = 200_000,
	[6] = 1_500_000,
	[7] = 10_000_000,
	[8] = 75_000_000,
	[9] = 500_000_000,
}

-- An egg sells at the Sell stall for this fraction of its stamina requirement, so eggs that are harder to hold on
-- to are worth more: a Forest Common sells for $25, a Volcano Eternal for $187.5K. Far less than the egg's pet earns,
-- so selling is for eggs a player has no room or use for.
Economy.EGG_SELL_FRACTION = 0.5

-- Dollars for selling one egg, or nil if that rarity cannot drop in that zone.
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
