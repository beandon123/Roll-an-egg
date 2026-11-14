--!strict
-- The trails sold at the Trails shop in the hub. A trail streams behind your character, and while it is equipped
-- your Max Stamina is multiplied by its `stamina` value. Trails are bought once with coins and kept for good;
-- one is equipped at a time.
-- First-pass prices and boosts; adjust in economy tuning.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.

export type TrailInfo = {
	id: string,
	name: string,
	-- Coins.
	price: number,
	-- Max Stamina multiplier while equipped.
	stamina: number,
	-- RGB 0-255, from the character back to the tail end of the trail.
	colors: { { number } },
}

local Trails = {}

-- In shop order: each costs more and boosts more than the one before.
local list: { TrailInfo } = {
	{
		id = "Leaf",
		name = "Leaf Trail",
		price = 100,
		stamina = 1.2,
		colors = { { 140, 230, 100 }, { 40, 150, 70 } },
	},
	{
		id = "Sunbeam",
		name = "Sunbeam Trail",
		price = 500,
		stamina = 1.5,
		colors = { { 255, 240, 120 }, { 255, 170, 40 } },
	},
	{
		id = "Sandstorm",
		name = "Sandstorm Trail",
		price = 2500,
		stamina = 2,
		colors = { { 245, 220, 160 }, { 200, 140, 70 } },
	},
	{
		id = "Frost",
		name = "Frost Trail",
		price = 15000,
		stamina = 3,
		colors = { { 225, 248, 255 }, { 100, 175, 255 } },
	},
	{
		id = "Bubble",
		name = "Bubble Trail",
		price = 75000,
		stamina = 4.5,
		colors = { { 150, 250, 240 }, { 40, 150, 225 } },
	},
	{
		id = "Ember",
		name = "Ember Trail",
		price = 400000,
		stamina = 6,
		colors = { { 255, 215, 80 }, { 240, 70, 30 } },
	},
	{
		id = "Rainbow",
		name = "Rainbow Trail",
		price = 2500000,
		stamina = 8,
		colors = {
			{ 255, 90, 90 },
			{ 255, 200, 70 },
			{ 100, 225, 110 },
			{ 80, 165, 255 },
			{ 190, 105, 255 },
		},
	},
}

Trails.List = list

local byId: { [string]: TrailInfo } = {}
for _, trail in list do
	byId[trail.id] = trail
end
Trails.ById = byId

return Trails
