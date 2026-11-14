--!strict
-- Money, pets' worth and the pen: first-pass numbers, to adjust in playtests.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.
--
-- The currency is dollars. Pets in a player's pen earn dollars every second; a pet can also be sold for a lump
-- sum. Dollars buy a bigger pen (the green button at its front).

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

-- Variants: when an egg hatches, its pet may come out Silver, Gold or Rainbow instead of Normal. Each is rarer and
-- worth more (income and sale price are multiplied) and rides a little faster.
export type Variant = { name: string, chance: number, worth: number, speedBonus: number }
Economy.VARIANTS = {
	{ name = "Normal", chance = 0, worth = 1, speedBonus = 0 },
	{ name = "Silver", chance = 0.08, worth = 2, speedBonus = 2 },
	{ name = "Gold", chance = 0.025, worth = 5, speedBonus = 4 },
	{ name = "Rainbow", chance = 0.005, worth = 15, speedBonus = 6 },
} :: { Variant }

-- How fast a pet carries its rider (studs per second; walking is 16), by rarity.
Economy.MOUNT_SPEED = {
	Common = 22,
	Uncommon = 24,
	Rare = 27,
	Epic = 30,
	Legendary = 33,
	Mythic = 36,
	Secret = 40,
	Eternal = 44,
}
-- Seconds after leaving an egg before a ridden pet comes back.
Economy.RESUMMON_DELAY = 3

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

return Economy
