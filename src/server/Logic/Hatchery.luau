--!strict
-- The rules for a player's eggs, nests and pets, working on their saved data:
--     Eggs   eggs claimed on the runway, waiting in the inventory
--     Nests  eggs placed in the nests on the player's plot, hatching on a timer (Shared/HatchMath)
--     Pets   what has hatched
-- Like Logic/RunwaySim, this holds rules only: no players, parts or remotes, so it is covered by tests that run
-- outside Studio. InventoryService feeds it the clock and players' requests, and saves and sends the results.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local EggSpec = require(Shared.EggSpec)
local HatchMath = require(Shared.HatchMath)
local Plots = require(Shared.Plots)
local Rarities = require(Shared.Config.Rarities)
local Zones = require(Shared.Config.Zones)

-- An egg in the inventory. `kind` is its design name (e.g. "MossStag"); eggs claimed before kinds existed have
-- none, and count as the zone's first egg of their rarity.
export type EggItem = { uid: string, zone: number, rarity: string, kind: string?, claimedAt: number }

-- An egg in a nest: which nest (1 to the plot's nest count), when it went in, and the closure bonus it has banked.
export type Nest = {
	slot: number,
	uid: string,
	zone: number,
	rarity: string,
	kind: string,
	placedAt: number,
	bonus: number,
}

-- A hatched pet. `kind` is its design name in Shared/PetModels; `egg` is the egg it came from.
export type Pet = { uid: string, kind: string, egg: string, zone: number, rarity: string, hatchedAt: number }

export type Data = {
	Eggs: { EggItem },
	Nests: { Nest },
	Pets: { Pet },
	NestCount: number?,
}

local Hatchery = {}

-- The egg an inventory item is (its design name).
function Hatchery.eggKindOf(item: { zone: number, rarity: string, kind: string? }): string
	if item.kind and EggSpec.placeOf(item.kind) == item.zone then
		return item.kind
	end
	return EggSpec.pickEgg(item.zone, item.rarity, 0) or "Leafy"
end

-- The pet that hatches from an egg (its design name).
function Hatchery.petOf(eggKind: string): string
	for _, zone in Zones.List do
		for _, entry in zone.eggs do
			if entry.egg == eggKind then
				return entry.pet
			end
		end
	end
	return eggKind
end

function Hatchery.nestCount(data: Data): number
	return math.clamp(data.NestCount or Plots.START_NESTS, 1, Plots.MAX_NESTS)
end

-- The first empty nest, or nil if they are all full.
function Hatchery.freeSlot(data: Data): number?
	local used = {}
	for _, nest in data.Nests do
		used[nest.slot] = true
	end
	for slot = 1, Hatchery.nestCount(data) do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

-- Moves an egg from the inventory into the first empty nest. Returns the nest, or nil and why not.
function Hatchery.place(data: Data, eggUid: string, now: number): (Nest?, string?)
	local index = nil
	for position, item in data.Eggs do
		if item.uid == eggUid then
			index = position
			break
		end
	end
	if index == nil then
		return nil, "NoEgg"
	end
	local slot = Hatchery.freeSlot(data)
	if slot == nil then
		return nil, "NestsFull"
	end
	local item = table.remove(data.Eggs, index) :: EggItem
	local nest: Nest = {
		slot = slot,
		uid = item.uid,
		zone = item.zone,
		rarity = item.rarity,
		kind = Hatchery.eggKindOf(item),
		placedAt = now,
		bonus = 0,
	}
	table.insert(data.Nests, nest)
	return nest, nil
end

-- The nests whose eggs have finished hatching by `now`.
function Hatchery.ready(data: Data, now: number): { Nest }
	local done = {}
	for _, nest in data.Nests do
		if HatchMath.timeLeft(nest.placedAt, nest.bonus, nest.rarity, now) <= 0 then
			table.insert(done, nest)
		end
	end
	return done
end

-- Hatches a nest's egg: the nest empties and the pet joins the player's pets. Returns the pet.
function Hatchery.hatch(data: Data, nest: Nest, now: number, petUid: string): Pet?
	local index = table.find(data.Nests, nest)
	if index == nil then
		return nil
	end
	table.remove(data.Nests, index)
	local pet: Pet = {
		uid = petUid,
		kind = Hatchery.petOf(nest.kind),
		egg = nest.kind,
		zone = nest.zone,
		rarity = nest.rarity,
		hatchedAt = now,
	}
	table.insert(data.Pets, pet)
	return pet
end

-- Banks the hatching boost from the closure that ended as the cycle starting at `cycleStart` began.
function Hatchery.commitClosure(data: Data, cycleStart: number)
	for _, nest in data.Nests do
		nest.bonus += HatchMath.closureBonus(nest.placedAt, cycleStart)
	end
end

-- The pets that roam the pen (up to `capacity`): the rarest, and of those the newest.
function Hatchery.penPets(data: Data, capacity: number): { Pet }
	local sorted = table.clone(data.Pets)
	table.sort(sorted, function(a, b)
		local orderA = if Rarities.Info[a.rarity] then Rarities.Info[a.rarity].order else 0
		local orderB = if Rarities.Info[b.rarity] then Rarities.Info[b.rarity].order else 0
		if orderA ~= orderB then
			return orderA > orderB
		end
		return a.hatchedAt > b.hatchedAt
	end)
	local chosen = {}
	for index = 1, math.min(capacity, #sorted) do
		chosen[index] = sorted[index]
	end
	return chosen
end

-- What the player's device is told: copies of their eggs, nests and pets, and how many nests they have.
function Hatchery.state(data: Data)
	local eggs = {}
	for _, item in data.Eggs do
		table.insert(eggs, {
			uid = item.uid,
			zone = item.zone,
			rarity = item.rarity,
			kind = Hatchery.eggKindOf(item),
			claimedAt = item.claimedAt,
		})
	end
	return {
		eggs = eggs,
		nests = table.clone(data.Nests),
		pets = table.clone(data.Pets),
		nestCount = Hatchery.nestCount(data),
	}
end

return Hatchery
