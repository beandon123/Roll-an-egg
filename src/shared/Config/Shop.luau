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
	{ kind: "Coins", amount: number }
	| { kind: "MaxStamina", amount: number }
	| { kind: "Luck", multiplier: number, duration: number }
	| { kind: "PenLevel" }

-- A developer product: bought with Robux, can be bought again.
export type Product = {
	id: string,
	section: "Luck" | "Stamina" | "Coins",
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

-- One pen level: buy it with coins, or skip the grind with Robux (one developer product per level, because a
-- developer product's price is fixed).
export type PenLevel = {
	level: number,
	coins: number,
	productId: number,
	robux: number,
}

local Shop = {}

-- Sections in the order the shop shows them.
Shop.Sections = { "Featured", "Luck", "Stamina", "Coins", "Passes" }

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
		id = "Coins1",
		section = "Coins",
		order = 1,
		title = "+5K",
		subtitle = "COINS",
		productId = 0,
		robux = 39,
		grant = { kind = "Coins", amount = 5000 },
	},
	{
		id = "Coins2",
		section = "Coins",
		order = 2,
		title = "+50K",
		subtitle = "COINS",
		productId = 0,
		robux = 99,
		grant = { kind = "Coins", amount = 50000 },
	},
	{
		id = "Coins3",
		section = "Coins",
		order = 3,
		title = "+250K",
		subtitle = "COINS",
		badge = "BEST VALUE",
		productId = 0,
		robux = 249,
		grant = { kind = "Coins", amount = 250000 },
	},
}

local passes: { Pass } = {
	{
		id = "DoubleCoins",
		order = 1,
		title = "x2 COINS",
		tagline = "FOREVER!",
		description = "Every pet in your pen earns double",
		gamePassId = 0,
		robux = 199,
	},
	{
		id = "DoubleStamina",
		order = 2,
		title = "x2 MAX STAMINA",
		tagline = "FOREVER!",
		description = "Doubles your Max Stamina, upgrades included",
		gamePassId = 0,
		robux = 249,
	},
}

-- What the x2 Max Stamina pass multiplies by.
Shop.STAMINA_PASS_MULTIPLIER = 2

-- Pen capacity: 10 pets at level 1, +1 per level, up to level 9 (18 pets) for now.
Shop.PEN_BASE_CAPACITY = 10
Shop.MAX_PEN_LEVEL = 9

local penLevels: { [number]: PenLevel } = {}
local PEN_PRICES = {
	-- level = { coins, robux }
	[2] = { 2500, 49 },
	[3] = { 10000, 79 },
	[4] = { 40000, 129 },
	[5] = { 150000, 199 },
	[6] = { 500000, 299 },
	[7] = { 1500000, 449 },
	[8] = { 5000000, 649 },
	[9] = { 15000000, 899 },
}
for level, prices in PEN_PRICES do
	penLevels[level] = { level = level, coins = prices[1], productId = 0, robux = prices[2] }
end

Shop.Products = products
Shop.Passes = passes
Shop.PenLevels = penLevels

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

-- What a Roblox developer product ID pays for: a product, or a pen level. Nil for unknown IDs (and for 0).
function Shop.findByProductId(productId: number): (Product?, PenLevel?)
	if productId == 0 then
		return nil, nil
	end
	for _, product in products do
		if product.productId == productId then
			return product, nil
		end
	end
	for _, penLevel in penLevels do
		if penLevel.productId == productId then
			return nil, penLevel
		end
	end
	return nil, nil
end

-- Max Stamina from what the player owns. Later, stamina upgrades bought with coins add to `bonus` too.
function Shop.maxStamina(baseStamina: number, bonus: number, hasStaminaPass: boolean): number
	local total = baseStamina + bonus
	return if hasStaminaPass then total * Shop.STAMINA_PASS_MULTIPLIER else total
end

return Shop
