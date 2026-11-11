--!strict
-- The runway's zones, in order from the hub to the end cliff.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.
--
-- stamina: the stamina requirement of each egg rarity that can drop in the zone.
--          A rarity missing from this table cannot drop there (that is how the zone's rarity cap is set).
-- weights: relative drop odds for each rarity in the zone.

export type ZoneInfo = {
	id: number,
	key: string,
	name: string,
	-- RGB 0-255 for the placeholder ground and trim.
	ground: { number },
	accent: { number },
	stamina: { [string]: number },
	weights: { [string]: number },
}

local Zones = {}

local list: { ZoneInfo } = {
	{
		id = 1,
		key = "Forest",
		name = "Forest",
		ground = { 92, 150, 78 },
		accent = { 50, 96, 48 },
		stamina = { Common = 50, Uncommon = 80, Rare = 120, Epic = 200, Legendary = 350 },
		weights = { Common = 55, Uncommon = 27, Rare = 12, Epic = 5, Legendary = 1 },
	},
	{
		id = 2,
		key = "Desert",
		name = "Desert",
		ground = { 226, 196, 128 },
		accent = { 176, 120, 62 },
		stamina = { Common = 500, Uncommon = 650, Rare = 850, Epic = 1100, Legendary = 1400, Mythic = 1800 },
		weights = { Common = 52, Uncommon = 27, Rare = 13, Epic = 6, Legendary = 1.7, Mythic = 0.3 },
	},
	{
		id = 3,
		key = "Snow",
		name = "Snow",
		ground = { 236, 243, 250 },
		accent = { 140, 190, 230 },
		stamina = {
			Common = 2000,
			Uncommon = 2500,
			Rare = 3200,
			Epic = 4000,
			Legendary = 5000,
			Mythic = 6200,
			Secret = 7500,
		},
		weights = { Common = 50, Uncommon = 27, Rare = 14, Epic = 6.5, Legendary = 2, Mythic = 0.45, Secret = 0.05 },
	},
	{
		id = 4,
		key = "Ocean",
		name = "Ocean",
		ground = { 240, 222, 170 },
		accent = { 40, 150, 200 },
		stamina = {
			Common = 8000,
			Uncommon = 10000,
			Rare = 12500,
			Epic = 16000,
			Legendary = 20000,
			Mythic = 25000,
			Secret = 30000,
		},
		weights = { Common = 50, Uncommon = 27, Rare = 14, Epic = 6.5, Legendary = 2, Mythic = 0.45, Secret = 0.05 },
	},
	{
		id = 5,
		key = "Volcano",
		name = "Volcano",
		ground = { 74, 60, 60 },
		accent = { 235, 95, 40 },
		stamina = {
			Common = 35000,
			Uncommon = 45000,
			Rare = 55000,
			Epic = 70000,
			Legendary = 85000,
			Mythic = 100000,
			Secret = 125000,
			Eternal = 150000,
		},
		weights = {
			Common = 50,
			Uncommon = 27,
			Rare = 14,
			Epic = 6.5,
			Legendary = 2,
			Mythic = 0.43,
			Secret = 0.05,
			Eternal = 0.02,
		},
	},
}

Zones.List = list

return Zones
