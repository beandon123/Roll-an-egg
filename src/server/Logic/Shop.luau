--!strict
-- The rules of the hub shops: buying and equipping trails at the Trails shop, and selling eggs at the Sell stall.
--
-- These functions change a player's saved data table directly and never touch players, parts, or remotes:
-- ShopService checks what clients send, calls these, and tells the client what changed. Keeping them free of
-- Roblox objects means they are covered by tests that run outside Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Economy = require(Shared.Config.Economy)
local Trails = require(Shared.Config.Trails)

-- Why a trail purchase or equip did or did not go through.
export type TrailResult =
	"Bought"
	| "BoughtAndEquipped"
	| "Equipped"
	| "Unknown"
	| "Owned"
	| "NotOwned"
	| "NotEnoughCoins"

local Shop = {}

-- Buys a trail. A new trail is equipped straight away unless the one already equipped boosts stamina more.
function Shop.buyTrail(data, trailId: string): (boolean, TrailResult)
	local trail = Trails.ById[trailId]
	if trail == nil then
		return false, "Unknown"
	end
	if data.Trails.Owned[trailId] then
		return false, "Owned"
	end
	if data.Coins < trail.price then
		return false, "NotEnoughCoins"
	end

	data.Coins -= trail.price
	data.Trails.Owned[trailId] = true

	local equipped = Trails.ById[data.Trails.Equipped]
	if equipped == nil or trail.stamina >= equipped.stamina then
		data.Trails.Equipped = trailId
		return true, "BoughtAndEquipped"
	end
	return true, "Bought"
end

-- Equips a trail the player owns.
function Shop.equipTrail(data, trailId: string): (boolean, TrailResult)
	if Trails.ById[trailId] == nil then
		return false, "Unknown"
	end
	if not data.Trails.Owned[trailId] then
		return false, "NotOwned"
	end
	data.Trails.Equipped = trailId
	return true, "Equipped"
end

-- The ids of the trails a player owns, in shop order.
function Shop.ownedTrails(data): { string }
	local owned = {}
	for _, trail in Trails.List do
		if data.Trails.Owned[trail.id] then
			table.insert(owned, trail.id)
		end
	end
	return owned
end

-- Sells up to `count` of the player's eggs of one kind. Returns how many were sold and the coins they made.
function Shop.sellEggs(data, zone: number, rarity: string, count: number): (number, number)
	local value = Economy.eggSellValue(zone, rarity)
	if value == nil or count < 1 then
		return 0, 0
	end

	local sold = 0
	-- Newest first; the eggs of one kind are all alike.
	for index = #data.Eggs, 1, -1 do
		if sold >= count then
			break
		end
		local egg = data.Eggs[index]
		if egg.zone == zone and egg.rarity == rarity then
			table.remove(data.Eggs, index)
			sold += 1
		end
	end

	local coins = sold * value
	data.Coins += coins
	data.Stats.EggsSold += sold
	return sold, coins
end

return Shop
