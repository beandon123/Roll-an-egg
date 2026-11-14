--!strict
-- The trails sold at the Trails shop in the hub. A trail streams behind your character, and while it is equipped
-- your Max Stamina is multiplied by its `stamina` value. Trails are bought once with dollars and kept for good;
-- one is equipped at a time.
--
-- Nine trails, from a plain ribbon to a blazing rainbow: each costs more, boosts more, and looks fancier than the
-- one before. The plain ones are a single ribbon; then come particles (dust, bubbles, snowflakes, embers, sparks,
-- stars), a glowing halo round the ribbon, and a light that travels with you.
-- First-pass prices and boosts; adjust in economy tuning.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.

-- What a trail sheds as it goes (StationService picks the texture and motion for each kind).
export type ParticleKind = "Dust" | "Bubble" | "Sparkle" | "Ember" | "Spark" | "Star"

export type TrailInfo = {
	id: string,
	name: string,
	-- Its place in the shop, from 1 (the first trail) to 9.
	level: number,
	-- A rarity from Config/Rarities, for its colour on the shop card.
	rarity: string,
	-- Dollars.
	price: number,
	-- Max Stamina multiplier while equipped.
	stamina: number,
	-- RGB 0-255, from the character back to the tail end of the trail.
	colors: { { number } },
	-- How tall the ribbon is (studs), how long it lingers (seconds), and how much it glows (0 to 1).
	width: number,
	lifetime: number,
	glow: number,
	-- A second, wider and fainter ribbon round the first, in this colour.
	halo: { number }?,
	-- Particles shed along the way.
	particles: { kind: ParticleKind, colors: { { number } }, rate: number, size: number }?,
	-- A light carried with the trail.
	light: { number }?,
}

local Trails = {}

-- In shop order: each costs more, boosts more and looks fancier than the one before.
local list: { TrailInfo } = {
	{
		id = "Leaf",
		name = "Leaf Trail",
		level = 1,
		rarity = "Common",
		price = 100,
		stamina = 1.5,
		colors = { { 140, 230, 100 }, { 40, 150, 70 } },
		width = 2.2,
		lifetime = 0.45,
		glow = 0,
	},
	{
		id = "Sunbeam",
		name = "Sunbeam Trail",
		level = 2,
		rarity = "Common",
		price = 1000,
		stamina = 2,
		colors = { { 255, 245, 150 }, { 255, 170, 40 } },
		width = 2.4,
		lifetime = 0.55,
		glow = 0.6,
	},
	{
		id = "Sandstorm",
		name = "Sandstorm Trail",
		level = 3,
		rarity = "Uncommon",
		price = 7500,
		stamina = 3,
		colors = { { 250, 226, 168 }, { 200, 140, 70 } },
		width = 2.6,
		lifetime = 0.6,
		glow = 0.1,
		particles = { kind = "Dust", colors = { { 240, 214, 160 }, { 196, 150, 96 } }, rate = 14, size = 1.2 },
	},
	{
		id = "Bubble",
		name = "Bubble Trail",
		level = 4,
		rarity = "Uncommon",
		price = 50000,
		stamina = 4,
		colors = { { 170, 250, 245 }, { 40, 150, 225 } },
		width = 2.6,
		lifetime = 0.65,
		glow = 0.35,
		particles = { kind = "Bubble", colors = { { 220, 255, 255 }, { 120, 210, 255 } }, rate = 10, size = 0.7 },
	},
	{
		id = "Frost",
		name = "Frost Trail",
		level = 5,
		rarity = "Rare",
		price = 300000,
		stamina = 6,
		colors = { { 240, 252, 255 }, { 150, 210, 255 }, { 70, 130, 240 } },
		width = 2.8,
		lifetime = 0.7,
		glow = 0.5,
		halo = { 190, 230, 255 },
		particles = { kind = "Sparkle", colors = { { 255, 255, 255 }, { 170, 220, 255 } }, rate = 14, size = 0.6 },
	},
	{
		id = "Ember",
		name = "Ember Trail",
		level = 6,
		rarity = "Epic",
		price = 2000000,
		stamina = 9,
		colors = { { 255, 240, 140 }, { 255, 150, 40 }, { 220, 50, 30 } },
		width = 3,
		lifetime = 0.75,
		glow = 0.8,
		halo = { 255, 120, 40 },
		particles = { kind = "Ember", colors = { { 255, 220, 100 }, { 255, 80, 30 } }, rate = 22, size = 0.9 },
		light = { 255, 140, 60 },
	},
	{
		id = "Thunder",
		name = "Thunder Trail",
		level = 7,
		rarity = "Legendary",
		price = 15000000,
		stamina = 13,
		colors = { { 255, 255, 255 }, { 130, 220, 255 }, { 70, 90, 255 } },
		width = 3.2,
		lifetime = 0.8,
		glow = 1,
		halo = { 120, 200, 255 },
		particles = { kind = "Spark", colors = { { 255, 255, 255 }, { 120, 220, 255 } }, rate = 28, size = 0.8 },
		light = { 120, 190, 255 },
	},
	{
		id = "Galaxy",
		name = "Galaxy Trail",
		level = 8,
		rarity = "Mythic",
		price = 100000000,
		stamina = 18,
		colors = { { 255, 140, 230 }, { 150, 80, 255 }, { 40, 30, 120 }, { 20, 10, 60 } },
		width = 3.4,
		lifetime = 0.9,
		glow = 1,
		halo = { 170, 110, 255 },
		particles = {
			kind = "Star",
			colors = { { 255, 255, 255 }, { 255, 170, 240 }, { 160, 140, 255 } },
			rate = 30,
			size = 0.8,
		},
		light = { 190, 120, 255 },
	},
	{
		id = "Rainbow",
		name = "Rainbow Trail",
		level = 9,
		rarity = "Eternal",
		price = 750000000,
		stamina = 25,
		colors = {
			{ 255, 90, 90 },
			{ 255, 170, 60 },
			{ 255, 235, 80 },
			{ 100, 225, 110 },
			{ 80, 165, 255 },
			{ 190, 105, 255 },
		},
		width = 3.8,
		lifetime = 1,
		glow = 1,
		halo = { 255, 255, 255 },
		particles = {
			kind = "Star",
			colors = { { 255, 120, 120 }, { 255, 230, 100 }, { 120, 240, 140 }, { 120, 180, 255 }, { 210, 130, 255 } },
			rate = 40,
			size = 0.9,
		},
		light = { 255, 240, 255 },
	},
}

Trails.List = list

local byId: { [string]: TrailInfo } = {}
for _, trail in list do
	byId[trail.id] = trail
end
Trails.ById = byId

return Trails
