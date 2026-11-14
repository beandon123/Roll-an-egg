--!strict
-- Everything the shop sells, and for how much. Adjust prices and amounts during economy tuning.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Robux items need an ID from the Creator Dashboard (Monetization > Developer Products / Passes). While an ID is 0
-- the item cannot be bought in a live game; in Studio, buying it grants it straight away so the shop can be tested.
--
-- `robux` is only what the button shows until the real price loads from Roblox, so a price changed on the
-- dashboard is never shown wrong for long.

export type Grant =
	{ kind: "Dollars", amount: number }
	| { kind: "MaxStamina", amount: number }
	| { kind: "Luck", multiplier: number, duration: number }
	| { kind: "PenLevel" }
	| { kind: "StaminaDoubling" }

-- A developer product: bought with Robux, can be bought again.
export type Product = {
	id: string,
	section: "Luck" | "Stamina" | "Dollars",
	order: number,
	-- Big text on the card, e.g. "+5K", and the word under it.
	title: string,
	subtitle: string,
	-- A small tag in the card's corner, e.g. "15 MIN".
	badge: string?,
	productId: number,
	robux: number,
	grant: Grant,
}

-- A game pass: bought once, kept forever.
export type Pass = {
	id: string,
	order: number,
	title: string,
	tagline: string,
	description: string,
	gamePassId: number,
	robux: number,
}

-- One pen level: buy it with dollars, or skip the grind with Robux (one developer product per level, because a
-- developer product's price is fixed).
export type PenLevel = {
	level: number,
	dollars: number,
	productId: number,
	robux: number,
}

-- One step of "Double your Max Stamina": from one multiplier to twice it. One developer product per step, so each
-- step can have its own price.
export type StaminaDoubling = {
	from: number,
	to: number,
	productId: number,
	robux: number,
}

local Economy = require(script.Parent.Economy)

local Shop = {}

-- Sections in the order the shop shows them.
Shop.Sections = { "Featured", "Luck", "Stamina", "Dollars", "Passes" }

Shop.LUCK_DURATION = 15 * 60

local products: { Product } = {
	{
		id = "Luck2",
		section = "Luck",
		order = 1,
		title = "x2",
		subtitle = "SERVER LUCK",
		badge = "15 MIN",
		productId = 0,
		robux = 99,
		grant = { kind = "Luck", multiplier = 2, duration = Shop.LUCK_DURATION },
	},
	{
		id = "Luck4",
		section = "Luck",
		order = 2,
		title = "x4",
		subtitle = "SERVER LUCK",
		badge = "15 MIN",
		productId = 0,
		robux = 299,
		grant = { kind = "Luck", multiplier = 4, duration = Shop.LUCK_DURATION },
	},
	{
		id = "Stamina1",
		section = "Stamina",
		order = 1,
		title = "+500",
		subtitle = "MAX STAMINA",
		productId = 0,
		robux = 79,
		grant = { kind = "MaxStamina", amount = 500 },
	},
	{
		id = "Stamina2",
		section = "Stamina",
		order = 2,
		title = "+5K",
		subtitle = "MAX STAMINA",
		productId = 0,
		robux = 299,
		grant = { kind = "MaxStamina", amount = 5000 },
	},
	{
		id = "Stamina3",
		section = "Stamina",
		order = 3,
		title = "+25K",
		subtitle = "MAX STAMINA",
		badge = "BEST VALUE",
		productId = 0,
		robux = 799,
		grant = { kind = "MaxStamina", amount = 25000 },
	},
	{
		id = "Dollars1",
		section = "Dollars",
		order = 1,
		title = "+$5K",
		subtitle = "DOLLARS",
		productId = 0,
		robux = 39,
		grant = { kind = "Dollars", amount = 5000 },
	},
	{
		id = "Dollars2",
		section = "Dollars",
		order = 2,
		title = "+$50K",
		subtitle = "DOLLARS",
		productId = 0,
		robux = 99,
		grant = { kind = "Dollars", amount = 50000 },
	},
	{
		id = "Dollars3",
		section = "Dollars",
		order = 3,
		title = "+$250K",
		subtitle = "DOLLARS",
		badge = "BEST VALUE",
		productId = 0,
		robux = 249,
		grant = { kind = "Dollars", amount = 250000 },
	},
}

local passes: { Pass } = {
	{
		id = "DoubleDollars",
		order = 1,
		title = "x2 DOLLARS",
		tagline = "FOREVER!",
		description = "Every pet in your pen earns double",
		gamePassId = 0,
		robux = 199,
	},
}

-- "Double your Max Stamina": bought again and again, each purchase doubles the player's Max Stamina multiplier,
-- from x1 up to this cap (x2, x4, x8 ... ten doublings). Kept forever.
Shop.MAX_STAMINA_MULTIPLIER = 1024
-- The id the client sends to buy the next doubling.
Shop.STAMINA_DOUBLING_ID = "StaminaDoubling"

-- Keyed by the multiplier the step reaches (2, 4, 8 ... 1024).
local staminaDoublings: { [number]: StaminaDoubling } = {}
local DOUBLING_PRICES = { 49, 79, 99, 117, 149, 199, 249, 349, 449, 599 }
do
	local to = 2
	for _, robux in DOUBLING_PRICES do
		staminaDoublings[to] = { from = to / 2, to = to, productId = 0, robux = robux }
		to *= 2
	end
end

-- Pen levels: 10 pets at level 1, +1 per level, up to Economy.MAX_PEN_LEVEL. The dollar prices are the green
-- button's (Config/Economy), so the shop and the button always agree.
Shop.PEN_BASE_CAPACITY = 10
Shop.MAX_PEN_LEVEL = Economy.MAX_PEN_LEVEL

-- The Robux price of each level, to skip saving up.
local PEN_ROBUX = { [2] = 49, [3] = 79, [4] = 129, [5] = 199, [6] = 299, [7] = 449, [8] = 649, [9] = 899 }

local penLevels: { [number]: PenLevel } = {}
for level = 2, Shop.MAX_PEN_LEVEL do
	penLevels[level] = {
		level = level,
		dollars = Economy.PEN_UPGRADE_COST[level],
		productId = 0,
		robux = PEN_ROBUX[level],
	}
end

Shop.Products = products
Shop.Passes = passes
Shop.PenLevels = penLevels
Shop.StaminaDoublings = staminaDoublings

local productsById: { [string]: Product } = {}
for _, product in products do
	productsById[product.id] = product
end
local passesById: { [string]: Pass } = {}
for _, pass in passes do
	passesById[pass.id] = pass
end
Shop.ProductsById = productsById
Shop.PassesById = passesById

-- The id the client sends to buy the next pen level.
Shop.PEN_UPGRADE_ID = "PenUpgrade"

function Shop.penCapacity(level: number): number
	return Shop.PEN_BASE_CAPACITY + (level - 1)
end

-- The products in one section, in display order.
function Shop.productsIn(section: string): { Product }
	local list = {}
	for _, product in products do
		if product.section == section then
			table.insert(list, product)
		end
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

-- What a Roblox developer product ID pays for, and the id of the shop item it belongs to. Nil for unknown IDs (and
-- for 0, the ID of an item not set up yet).
function Shop.rewardForProductId(productId: number): (Grant?, string?)
	if productId == 0 then
		return nil, nil
	end
	for _, product in products do
		if product.productId == productId then
			return product.grant, product.id
		end
	end
	for _, penLevel in penLevels do
		if penLevel.productId == productId then
			return { kind = "PenLevel" }, Shop.PEN_UPGRADE_ID
		end
	end
	for _, doubling in staminaDoublings do
		if doubling.productId == productId then
			return { kind = "StaminaDoubling" }, Shop.STAMINA_DOUBLING_ID
		end
	end
	return nil, nil
end

-- Max Stamina from what the player owns: the base plus Max Stamina bought, times the doubling multiplier.
-- Later, stamina upgrades bought with dollars add to `bonus` too.
function Shop.maxStamina(baseStamina: number, bonus: number, multiplier: number): number
	return (baseStamina + bonus) * multiplier
end

return Shop
