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
	| { kind: "StickLevel" }
	| { kind: "StaminaDoubling" }
	| { kind: "Revives", amount: number }
	| { kind: "Pack", packId: string }

-- A developer product: bought with Robux, can be bought again.
export type Product = {
	id: string,
	section: "Luck" | "Stamina" | "Revives" | "Dollars",
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

-- One tier of the training stick (Config/Sticks): buy it with dollars, or with Robux (one developer product per
-- tier, like the pen levels).
export type StickLevel = {
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

-- A pack: one developer product that gives a bundle at once, at a big discount. Each player can buy each pack once.
export type Pack = {
	id: string,
	order: number,
	-- Its name in messages ("Epic Pack"), the big title on its card, and the tilted sticker in the card's corner.
	name: string,
	title: string,
	badge: string,
	-- Its own pet: a pet from Config/Zones (by its design name) in a variant only packs give (Config/Economy).
	pet: { kind: string, variant: string },
	-- Dollars, straight away.
	dollars: number,
	-- Multiplies Max Stamina, for good. Packs do not add up: the biggest one a player has counts.
	stamina: number,
	-- A trail only this pack gives (Config/Trails' PackList): the pack's "aura".
	trail: string,
	-- Revives (Config/Tuning): each lets a player who missed their leap carry on instead of going back to the hub.
	revives: number,
	-- A server luck boost, like the Luck section's, started when the pack is bought.
	luck: { multiplier: number, duration: number }?,
	productId: number,
	robux: number,
}

local Economy = require(script.Parent.Economy)
local Sticks = require(script.Parent.Sticks)
local Zones = require(script.Parent.Zones)

local Shop = {}

-- Sections in the order the shop shows them.
Shop.Sections = { "Packs", "Featured", "Luck", "Stamina", "Revives", "Dollars", "Passes" }

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
		id = "Revives1",
		section = "Revives",
		order = 1,
		title = "+1",
		subtitle = "REVIVE",
		productId = 0,
		robux = 19,
		grant = { kind = "Revives", amount = 1 },
	},
	{
		id = "Revives2",
		section = "Revives",
		order = 2,
		title = "+5",
		subtitle = "REVIVES",
		productId = 0,
		robux = 79,
		grant = { kind = "Revives", amount = 5 },
	},
	{
		id = "Revives3",
		section = "Revives",
		order = 3,
		title = "+15",
		subtitle = "REVIVES",
		badge = "BEST VALUE",
		productId = 0,
		robux = 199,
		grant = { kind = "Revives", amount = 15 },
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

-- The training stick's tiers: the dollar prices are Config/Sticks', so the sign by the stick and the shop always
-- agree; these are the Robux prices, to skip saving up.
Shop.MAX_STICK_LEVEL = Sticks.MAX_LEVEL
local STICK_ROBUX = { [2] = 29, [3] = 59, [4] = 99, [5] = 179, [6] = 299, [7] = 499, [8] = 799 }

local stickLevels: { [number]: StickLevel } = {}
for level = 2, Shop.MAX_STICK_LEVEL do
	stickLevels[level] = {
		level = level,
		dollars = Sticks.tier(level).price,
		productId = 0,
		robux = STICK_ROBUX[level],
	}
end

-- The packs (decided: like the owner's reference, each with its own pet, dollars, a Max Stamina boost kept for good,
-- an "aura" that is a trail, and revives; the bigger one adds server luck). Prices and amounts are first-pass.
local packs: { Pack } = {
	{
		id = "EpicPack",
		order = 1,
		name = "Epic Pack",
		title = "EPIC PACK",
		badge = "MOST POPULAR",
		pet = { kind = "SabertoothCat", variant = "Molten" },
		dollars = 250000,
		stamina = 8,
		trail = "Molten",
		revives = 2,
		productId = 0,
		robux = 149,
	},
	{
		id = "SuperPack",
		order = 2,
		name = "Super Pack",
		title = "SUPER PACK",
		badge = "BEST VALUE",
		pet = { kind = "MantisEmpress", variant = "Crystal" },
		dollars = 1000000,
		stamina = 16,
		trail = "Crystal",
		revives = 3,
		luck = { multiplier = 2, duration = Shop.LUCK_DURATION },
		productId = 0,
		robux = 299,
	},
}

Shop.Products = products
Shop.Passes = passes
Shop.PenLevels = penLevels
Shop.StickLevels = stickLevels
Shop.StaminaDoublings = staminaDoublings
Shop.Packs = packs

local productsById: { [string]: Product } = {}
for _, product in products do
	productsById[product.id] = product
end
local passesById: { [string]: Pass } = {}
for _, pass in passes do
	passesById[pass.id] = pass
end
local packsById: { [string]: Pack } = {}
for _, pack in packs do
	packsById[pack.id] = pack
end
Shop.ProductsById = productsById
Shop.PassesById = passesById
Shop.PacksById = packsById

-- The id the client sends to buy the next pen level.
Shop.PEN_UPGRADE_ID = "PenUpgrade"
-- The id the client sends to buy the next tier of the training stick.
Shop.STICK_UPGRADE_ID = "StickUpgrade"

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
	for _, stickLevel in stickLevels do
		if stickLevel.productId == productId then
			return { kind = "StickLevel" }, Shop.STICK_UPGRADE_ID
		end
	end
	for _, doubling in staminaDoublings do
		if doubling.productId == productId then
			return { kind = "StaminaDoubling" }, Shop.STAMINA_DOUBLING_ID
		end
	end
	for _, pack in packs do
		if pack.productId == productId then
			return { kind = "Pack", packId = pack.id }, pack.id
		end
	end
	return nil, nil
end

-- What a pack's parts would cost in Robux bought on their own in this shop, shown crossed out on its card: its
-- dollars at the best dollar pack's rate, the doublings that make its Max Stamina boost, its revives one at a time,
-- and its luck boost. The pet and the trail come on top (neither is sold on its own).
function Shop.packWorth(pack: Pack): number
	local worth = 0
	local bestDollars: Product? = nil
	for _, product in products do
		if product.grant.kind == "Dollars" then
			local best = bestDollars :: Product?
			if best == nil or product.grant.amount / product.robux > (best.grant :: any).amount / best.robux then
				bestDollars = product
			end
		end
	end
	if bestDollars then
		worth += pack.dollars * bestDollars.robux / (bestDollars.grant :: any).amount
	end
	local to = 2
	while to <= pack.stamina and staminaDoublings[to] do
		worth += staminaDoublings[to].robux
		to *= 2
	end
	local oneRevive = productsById.Revives1
	if oneRevive then
		worth += pack.revives * oneRevive.robux
	end
	if pack.luck then
		for _, product in products do
			local grant = product.grant
			if grant.kind == "Luck" and grant.multiplier == pack.luck.multiplier then
				worth += product.robux * pack.luck.duration / grant.duration
				break
			end
		end
	end
	return math.floor(worth + 0.5)
end

-- Where a pack's pet comes from: its egg, zone and rarity in Config/Zones (which set what it earns), or nil for a
-- pet no zone has.
function Shop.petOrigin(kind: string): { egg: string, zone: number, rarity: string }?
	for _, zone in Zones.List do
		for _, entry in zone.eggs do
			if entry.pet == kind then
				return { egg = entry.egg, zone = zone.id, rarity = entry.rarity }
			end
		end
	end
	return nil
end

-- How much cheaper a pack is than its parts (Shop.packWorth), as a whole percentage.
function Shop.packDiscount(pack: Pack): number
	return math.floor((1 - pack.robux / Shop.packWorth(pack)) * 100 + 0.5)
end

-- Max Stamina from what the player owns: the base plus Max Stamina bought or trained on the training stick (`bonus`),
-- times the doubling multiplier.
function Shop.maxStamina(baseStamina: number, bonus: number, multiplier: number): number
	return (baseStamina + bonus) * multiplier
end

return Shop
