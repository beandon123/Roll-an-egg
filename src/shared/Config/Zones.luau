--!strict
-- The runway's zones, in order from the hub to the end cliff.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.
--
-- eggs:    the zone's 8 eggs, from the most common to the rarest. `egg` names a design in Shared/EggModels/Designs;
--          `pet` is the pet that hatches from it (a design in Shared/PetModels/Designs, once it has a model).
--          A zone can have two eggs of the same rarity.
-- stamina: the stamina requirement of each egg rarity that can drop in the zone.
--          A rarity missing from this table cannot drop there.
-- weights: relative drop odds for each rarity in the zone. A drop first picks a rarity with these odds, then one
--          of the zone's eggs of that rarity, each equally likely.

export type ZoneEgg = { egg: string, rarity: string, pet: string }

export type ZoneInfo = {
	id: number,
	key: string,
	name: string,
	-- RGB 0-255 for the placeholder ground and trim.
	ground: { number },
	accent: { number },
	eggs: { ZoneEgg },
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
		eggs = {
			{ egg = "Leafy", rarity = "Common", pet = "Squirrel" },
			{ egg = "Cottontail", rarity = "Common", pet = "Bunny" },
			{ egg = "Acorn", rarity = "Uncommon", pet = "Hedgehog" },
			{ egg = "Foxtail", rarity = "Uncommon", pet = "Fox" },
			{ egg = "Toadstool", rarity = "Rare", pet = "Owl" },
			{ egg = "Bear", rarity = "Epic", pet = "Bear" },
			{ egg = "MossStag", rarity = "Legendary", pet = "MossStag" },
			{ egg = "Treant", rarity = "Mythic", pet = "Treant" },
		},
		stamina = { Common = 50, Uncommon = 80, Rare = 120, Epic = 200, Legendary = 350, Mythic = 450 },
		weights = { Common = 55, Uncommon = 27, Rare = 12, Epic = 5, Legendary = 1, Mythic = 0.2 },
	},
	{
		id = 2,
		key = "Desert",
		name = "Desert",
		ground = { 226, 196, 128 },
		accent = { 176, 120, 62 },
		eggs = {
			{ egg = "Sandy", rarity = "Common", pet = "Meerkat" },
			{ egg = "Sandstone", rarity = "Uncommon", pet = "Armadillo" },
			{ egg = "Fennec", rarity = "Uncommon", pet = "FennecFox" },
			{ egg = "Caravan", rarity = "Rare", pet = "Camel" },
			{ egg = "Scorpion", rarity = "Epic", pet = "GiantScorpion" },
			{ egg = "PharaohJackal", rarity = "Legendary", pet = "PharaohJackal" },
			{ egg = "Sphinx", rarity = "Mythic", pet = "Sphinx" },
			{ egg = "Scarab", rarity = "Mythic", pet = "GoldenScarab" },
		},
		stamina = { Common = 500, Uncommon = 650, Rare = 850, Epic = 1100, Legendary = 1400, Mythic = 1800 },
		weights = { Common = 52, Uncommon = 27, Rare = 13, Epic = 6, Legendary = 1.7, Mythic = 0.3 },
	},
	{
		id = 3,
		key = "Snow",
		name = "Snow",
		ground = { 236, 243, 250 },
		accent = { 140, 190, 230 },
		eggs = {
			{ egg = "Snowball", rarity = "Uncommon", pet = "SnowHare" },
			{ egg = "Snowcap", rarity = "Uncommon", pet = "ArcticFox" },
			{ egg = "Knitted", rarity = "Rare", pet = "Reindeer" },
			{ egg = "Mammoth", rarity = "Epic", pet = "WoollyMammoth" },
			{ egg = "Sabertooth", rarity = "Legendary", pet = "SabertoothCat" },
			{ egg = "AuroraOwl", rarity = "Mythic", pet = "AuroraOwl" },
			{ egg = "FrostWolf", rarity = "Mythic", pet = "FrostWolf" },
			{ egg = "Yeti", rarity = "Secret", pet = "Yeti" },
		},
		stamina = {
			Uncommon = 2500,
			Rare = 3200,
			Epic = 4000,
			Legendary = 5000,
			Mythic = 6200,
			Secret = 7500,
		},
		weights = { Uncommon = 27, Rare = 14, Epic = 6.5, Legendary = 2, Mythic = 0.45, Secret = 0.05 },
	},
	{
		id = 4,
		key = "Ocean",
		name = "Ocean",
		ground = { 240, 222, 170 },
		accent = { 40, 150, 200 },
		eggs = {
			{ egg = "Turtle", rarity = "Rare", pet = "SeaTurtle" },
			{ egg = "Dolphin", rarity = "Rare", pet = "Dolphin" },
			{ egg = "Manta", rarity = "Epic", pet = "MantaRay" },
			{ egg = "KingCrab", rarity = "Epic", pet = "KingCrab" },
			{ egg = "Narwhal", rarity = "Legendary", pet = "Narwhal" },
			{ egg = "Hippocampus", rarity = "Mythic", pet = "Hippocampus" },
			{ egg = "Kraken", rarity = "Secret", pet = "Kraken" },
			{ egg = "Abyss", rarity = "Secret", pet = "Leviathan" },
		},
		stamina = {
			Rare = 12500,
			Epic = 16000,
			Legendary = 20000,
			Mythic = 25000,
			Secret = 30000,
		},
		weights = { Rare = 14, Epic = 6.5, Legendary = 2, Mythic = 0.45, Secret = 0.05 },
	},
	{
		id = 5,
		key = "Volcano",
		name = "Volcano",
		ground = { 74, 60, 60 },
		accent = { 235, 95, 40 },
		eggs = {
			{ egg = "Obsidian", rarity = "Rare", pet = "ObsidianGoat" },
			{ egg = "CinderBoar", rarity = "Epic", pet = "CinderBoar" },
			{ egg = "VolcanoTortoise", rarity = "Legendary", pet = "VolcanoTortoise" },
			{ egg = "Salamander", rarity = "Legendary", pet = "FireSalamander" },
			{ egg = "Chimera", rarity = "Mythic", pet = "Chimera" },
			{ egg = "LavaGolem", rarity = "Mythic", pet = "LavaGolem" },
			{ egg = "Cerberus", rarity = "Secret", pet = "Cerberus" },
			{ egg = "EternalPhoenix", rarity = "Eternal", pet = "EternalPhoenix" },
		},
		stamina = {
			Rare = 55000,
			Epic = 70000,
			Legendary = 85000,
			Mythic = 100000,
			Secret = 125000,
			Eternal = 150000,
		},
		weights = {
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
