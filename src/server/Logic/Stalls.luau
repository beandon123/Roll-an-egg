--!strict
-- The rules of the hub's stalls: buying and equipping trails at the Trails stall (and the trails the shop's packs
-- give), and selling eggs at the Sell stall. Both pay and charge in dollars.
--
-- These functions change a player's saved data table directly and never touch players, parts, or remotes:
-- StationService checks what clients send, calls these, and tells the client what changed. Keeping them free of
-- Roblox objects means they are covered by tests that run outside Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Economy = require(Shared.Config.Economy)
local Trails = require(Shared.Config.Trails)

local Hatchery = require(script.Parent.Hatchery)

-- Why a trail purchase or equip did or did not go through.
export type TrailResult =
	"Bought"
	| "BoughtAndEquipped"
	| "Equipped"
	| "Unknown"
	| "Owned"
	| "NotOwned"
	| "NotEnoughDollars"
	| "PackOnly"

local Stalls = {}

-- Adds a trail to what the player owns, and equips it unless the one already equipped boosts stamina more.
-- Returns whether it was equipped.
local function addTrail(data, trail: Trails.TrailInfo): boolean
	data.Trails.Owned[trail.id] = true
	local equipped = Trails.ById[data.Trails.Equipped]
	if equipped == nil or trail.stamina >= equipped.stamina then
		data.Trails.Equipped = trail.id
		return true
	end
	return false
end

-- Buys a trail. A new trail is equipped straight away unless the one already equipped boosts stamina more. The
-- packs' trails are not for sale here.
function Stalls.buyTrail(data, trailId: string): (boolean, TrailResult)
	local trail = Trails.ById[trailId]
	if trail == nil then
		return false, "Unknown"
	end
	if data.Trails.Owned[trailId] then
		return false, "Owned"
	end
	if trail.pack then
		return false, "PackOnly"
	end
	if data.Dollars < trail.price then
		return false, "NotEnoughDollars"
	end

	data.Dollars -= trail.price
	if addTrail(data, trail) then
		return true, "BoughtAndEquipped"
	end
	return true, "Bought"
end

-- Gives a player a trail for free (a pack from the shop), equipped unless theirs boosts more. Returns whether they
-- did not have it already.
function Stalls.giveTrail(data, trailId: string): boolean
	local trail = Trails.ById[trailId]
	if trail == nil or data.Trails.Owned[trailId] then
		return false
	end
	addTrail(data, trail)
	return true
end

-- Equips a trail the player owns.
function Stalls.equipTrail(data, trailId: string): (boolean, TrailResult)
	if Trails.ById[trailId] == nil then
		return false, "Unknown"
	end
	if not data.Trails.Owned[trailId] then
		return false, "NotOwned"
	end
	data.Trails.Equipped = trailId
	return true, "Equipped"
end

-- The ids of the trails a player owns, in shop order (the stall's, then the packs').
function Stalls.ownedTrails(data): { string }
	local owned = {}
	for _, trail in Trails.All do
		if data.Trails.Owned[trail.id] then
			table.insert(owned, trail.id)
		end
	end
	return owned
end

-- Dollars one egg of this kind sells for (see Config/Economy), or nil if it is not an egg any zone drops.
function Stalls.eggValue(item: { zone: number, rarity: string }): number?
	return Economy.eggSellValue(item.zone, item.rarity)
end

-- Sells up to `count` of the player's eggs of one kind (an egg kind from Config/Zones, such as "Acorn"). Eggs
-- already put down in the pen are not for sale. Returns how many were sold and the dollars they made.
function Stalls.sellEggs(data, kind: string, count: number): (number, number)
	if count < 1 then
		return 0, 0
	end
	local sold, dollars = 0, 0
	-- Newest first; eggs of one kind are all alike.
	for index = #data.Eggs, 1, -1 do
		if sold >= count then
			break
		end
		local egg = data.Eggs[index]
		local value = Stalls.eggValue(egg)
		if value and Hatchery.eggKindOf(egg) == kind then
			table.remove(data.Eggs, index)
			sold += 1
			dollars += value
		end
	end
	data.Dollars += dollars
	data.Stats.EggsSold = (data.Stats.EggsSold or 0) + sold
	return sold, dollars
end

return Stalls
