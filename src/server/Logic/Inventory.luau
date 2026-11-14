--!strict
-- Summaries of a player's saved items for their client. The client is only ever sent these summaries, never the
-- saved records themselves.
-- No Roblox objects, so tests run outside Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Rarities = require(Shared.Config.Rarities)

export type EggGroup = { zone: number, rarity: string, count: number }

local Inventory = {}

-- Unhatched eggs grouped by kind (zone + rarity), Forest first, and Common to rarest within a zone.
function Inventory.eggGroups(eggs: { { zone: number, rarity: string } }): { EggGroup }
	local byKey: { [string]: EggGroup } = {}
	local groups: { EggGroup } = {}
	for _, egg in eggs do
		local key = egg.zone .. ":" .. egg.rarity
		local group = byKey[key]
		if group == nil then
			group = { zone = egg.zone, rarity = egg.rarity, count = 0 }
			byKey[key] = group
			table.insert(groups, group)
		end
		group.count += 1
	end
	table.sort(groups, function(a, b)
		if a.zone ~= b.zone then
			return a.zone < b.zone
		end
		local orderA = Rarities.Info[a.rarity] and Rarities.Info[a.rarity].order or 0
		local orderB = Rarities.Info[b.rarity] and Rarities.Info[b.rarity].order or 0
		return orderA < orderB
	end)
	return groups
end

return Inventory
