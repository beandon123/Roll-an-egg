--!strict
-- The rules for a player's eggs, pen and pets, working on their saved data:
--     Eggs      eggs claimed on the runway, waiting in the inventory
--     Hatching  eggs put down in the player's pen, hatching on a timer (Shared/HatchMath)
--     Pets      what has hatched: each Normal, Silver, Gold or Rainbow, in the pen or not
--     PenLevel  how big the pen is: how many eggs can hatch at once and how many pets it holds (Shared/Plots)
--     Dollars   earned by pets in the pen and by selling pets; spent on a bigger pen (Shared/PetWorth)
--     Mount     the pet the player rides (its uid, or "" for none)
-- Like Logic/RunwaySim, this holds rules only: no players, parts or remotes, so it is covered by tests that run
-- outside Studio. InventoryService feeds it the clock and players' requests, and saves and sends the results.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local EggSpec = require(Shared.EggSpec)
local HatchMath = require(Shared.HatchMath)
local PetWorth = require(Shared.PetWorth)
local Plots = require(Shared.Plots)
local Zones = require(Shared.Config.Zones)

-- An egg in the inventory. `kind` is its design name (e.g. "MossStag"); eggs claimed before kinds existed have
-- none, and count as the zone's first egg of their rarity.
export type EggItem = { uid: string, zone: number, rarity: string, kind: string?, claimedAt: number }

-- An egg hatching in the pen: where it was put down (see Shared/Plots: studs in from the plaza-side fence, and
-- along from the middle), when, and the closure bonus it has banked.
export type Incubating = {
	uid: string,
	zone: number,
	rarity: string,
	kind: string,
	placedAt: number,
	bonus: number,
	inward: number,
	along: number,
}

-- A hatched pet. `kind` is its design name in Shared/PetModels; `egg` is the egg it came from.
export type Pet = {
	uid: string,
	kind: string,
	egg: string,
	zone: number,
	rarity: string,
	variant: string,
	inPen: boolean,
	hatchedAt: number,
}

export type Data = {
	Eggs: { EggItem },
	Hatching: { Incubating },
	Pets: { Pet },
	PenLevel: number,
	Dollars: number,
	Mount: string,
	-- From older saves (see migrate).
	Nests: { any }?,
	NestCount: number?,
	Coins: number?,
}

local Hatchery = {}

----------------------------------------------------------------------------------------------------------------
-- Older saves

-- Brings data saved by an older version up to date. Safe to run on every load.
function Hatchery.migrate(data: Data)
	data.Hatching = data.Hatching or {}
	data.Pets = data.Pets or {}
	data.PenLevel = math.clamp(data.PenLevel or 1, 1, Plots.MAX_LEVEL)
	data.Dollars = data.Dollars or 0
	data.Mount = data.Mount or ""
	-- Eggs from the old nests go down in a row near the gate.
	if data.Nests then
		for index, nest in data.Nests do
			table.insert(data.Hatching, {
				uid = nest.uid,
				zone = nest.zone,
				rarity = nest.rarity,
				kind = nest.kind,
				placedAt = nest.placedAt,
				bonus = nest.bonus or 0,
				inward = 10,
				along = -Plots.DEPTH / 2 + 10 + (index - 1) * Plots.EGG_SPACING * 1.5,
			})
		end
		data.Nests = nil
	end
	data.NestCount = nil
	if data.Coins then
		data.Dollars += data.Coins
		data.Coins = nil
	end
	-- Pets from before variants are Normal; from before choosing, the best of them go in the pen.
	local choosing = false
	for _, pet in data.Pets do
		pet.variant = pet.variant or "Normal"
		if pet.inPen == nil then
			pet.inPen = false
			choosing = true
		end
	end
	if choosing then
		Hatchery.equipBest(data)
	end
end

----------------------------------------------------------------------------------------------------------------
-- Eggs

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

function Hatchery.eggCapacity(data: Data): number
	return Plots.eggCapacity(data.PenLevel)
end

function Hatchery.petCapacity(data: Data): number
	return Plots.petCapacity(data.PenLevel)
end

-- Whether an egg could go down at (inward, along) without crowding the eggs already there.
local function spotFree(data: Data, inward: number, along: number): boolean
	if not Plots.inPen(data.PenLevel, inward, along, Plots.EGG_MARGIN) then
		return false
	end
	for _, other in data.Hatching do
		local di, da = other.inward - inward, other.along - along
		if di * di + da * da < Plots.EGG_SPACING * Plots.EGG_SPACING then
			return false
		end
	end
	return true
end

-- The nearest free spot for an egg to (inward, along) in the pen, or nil if there is no room nearby.
function Hatchery.freeSpot(data: Data, inward: number, along: number): (number?, number?)
	local i, a = Plots.clampToPen(data.PenLevel, inward, along, Plots.EGG_MARGIN)
	if spotFree(data, i, a) then
		return i, a
	end
	for ring = 1, 4 do
		local radius = Plots.EGG_SPACING * ring
		local steps = 8 * ring
		for step = 0, steps - 1 do
			local angle = step / steps * math.pi * 2
			local ci, ca = i + math.cos(angle) * radius, a + math.sin(angle) * radius
			if spotFree(data, ci, ca) then
				return ci, ca
			end
		end
	end
	return nil, nil
end

-- Puts an egg from the inventory down in the pen, at (inward, along) or the nearest free spot. Returns it, or nil
-- and why not: "NoEgg", "Full" (as many eggs are hatching as the pen allows), "NoRoom".
function Hatchery.place(data: Data, eggUid: string, inward: number, along: number, now: number): (Incubating?, string?)
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
	if #data.Hatching >= Hatchery.eggCapacity(data) then
		return nil, "Full"
	end
	local spotInward, spotAlong = Hatchery.freeSpot(data, inward, along)
	if spotInward == nil or spotAlong == nil then
		return nil, "NoRoom"
	end
	local item = table.remove(data.Eggs, index) :: EggItem
	local entry: Incubating = {
		uid = item.uid,
		zone = item.zone,
		rarity = item.rarity,
		kind = Hatchery.eggKindOf(item),
		placedAt = now,
		bonus = 0,
		inward = spotInward,
		along = spotAlong,
	}
	table.insert(data.Hatching, entry)
	return entry, nil
end

-- The eggs that have finished hatching by `now`.
function Hatchery.ready(data: Data, now: number): { Incubating }
	local done = {}
	for _, entry in data.Hatching do
		if HatchMath.timeLeft(entry.placedAt, entry.bonus, entry.rarity, now) <= 0 then
			table.insert(done, entry)
		end
	end
	return done
end

local function penCount(data: Data): number
	local count = 0
	for _, pet in data.Pets do
		if pet.inPen then
			count += 1
		end
	end
	return count
end

-- Hatches an egg: it leaves the pen and its pet joins the player's pets, Normal or (by `variantRoll`, a random
-- number in [0, 1)) Silver, Gold or Rainbow. A new pet goes straight into the pen if there is room. Returns it.
function Hatchery.hatch(data: Data, entry: Incubating, now: number, petUid: string, variantRoll: number): Pet?
	local index = table.find(data.Hatching, entry)
	if index == nil then
		return nil
	end
	table.remove(data.Hatching, index)
	local pet: Pet = {
		uid = petUid,
		kind = Hatchery.petOf(entry.kind),
		egg = entry.kind,
		zone = entry.zone,
		rarity = entry.rarity,
		variant = PetWorth.rollVariant(variantRoll),
		inPen = penCount(data) < Hatchery.petCapacity(data),
		hatchedAt = now,
	}
	table.insert(data.Pets, pet)
	return pet
end

-- Banks the hatching boost from the closure that ended as the cycle starting at `cycleStart` began.
function Hatchery.commitClosure(data: Data, cycleStart: number)
	for _, entry in data.Hatching do
		entry.bonus += HatchMath.closureBonus(entry.placedAt, cycleStart)
	end
end

----------------------------------------------------------------------------------------------------------------
-- Pets

local function findPet(data: Data, uid: string): (Pet?, number?)
	for index, pet in data.Pets do
		if pet.uid == uid then
			return pet, index
		end
	end
	return nil, nil
end

-- The pets in the pen.
function Hatchery.penPets(data: Data): { Pet }
	local list = {}
	for _, pet in data.Pets do
		if pet.inPen then
			table.insert(list, pet)
		end
	end
	return list
end

-- Puts a pet in the pen or takes it out. Returns whether it worked, and why not: "NoPet", "Full".
function Hatchery.setInPen(data: Data, uid: string, inPen: boolean): (boolean, string?)
	local pet = findPet(data, uid)
	if pet == nil then
		return false, "NoPet"
	end
	if inPen and not pet.inPen and penCount(data) >= Hatchery.petCapacity(data) then
		return false, "Full"
	end
	pet.inPen = inPen
	return true, nil
end

-- Fills the pen with the player's best pets: the ones that earn the most (the newest first among equals).
function Hatchery.equipBest(data: Data)
	local sorted = table.clone(data.Pets)
	table.sort(sorted, function(a, b)
		local incomeA, incomeB = PetWorth.income(a), PetWorth.income(b)
		if incomeA ~= incomeB then
			return incomeA > incomeB
		end
		return a.hatchedAt > b.hatchedAt
	end)
	local capacity = Hatchery.petCapacity(data)
	for index, pet in sorted do
		pet.inPen = index <= capacity
	end
end

-- Sells a pet. Returns the dollars it fetched, or nil if the player has no such pet.
function Hatchery.sell(data: Data, uid: string): number?
	local pet, index = findPet(data, uid)
	if pet == nil or index == nil then
		return nil
	end
	table.remove(data.Pets, index)
	if data.Mount == uid then
		data.Mount = ""
	end
	local price = PetWorth.sellPrice(pet)
	data.Dollars += price
	return price
end

-- Chooses the pet to ride ("" for none). Returns whether the player has it.
function Hatchery.setMount(data: Data, uid: string): boolean
	if uid ~= "" and findPet(data, uid) == nil then
		return false
	end
	data.Mount = uid
	return true
end

-- The pet the player rides, if they have chosen one.
function Hatchery.mount(data: Data): Pet?
	if data.Mount == "" then
		return nil
	end
	return (findPet(data, data.Mount))
end

----------------------------------------------------------------------------------------------------------------
-- Money and the pen

-- Dollars a second the pets in the pen earn together.
function Hatchery.income(data: Data): number
	local total = 0
	for _, pet in data.Pets do
		if pet.inPen then
			total += PetWorth.income(pet)
		end
	end
	return total
end

-- Buys the next pen level. Returns whether it worked and why not ("Max", "Money"), and what it cost.
function Hatchery.upgradePen(data: Data): (boolean, string?, number?)
	local cost = PetWorth.penUpgradeCost(data.PenLevel)
	if cost == nil then
		return false, "Max", nil
	end
	if data.Dollars < cost then
		return false, "Money", cost
	end
	data.Dollars -= cost
	data.PenLevel += 1
	return true, nil, cost
end

----------------------------------------------------------------------------------------------------------------

-- What the player's device is told: copies of their eggs, hatching eggs and pets, and their pen and money.
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
		hatching = table.clone(data.Hatching),
		pets = table.clone(data.Pets),
		penLevel = data.PenLevel,
		eggCapacity = Hatchery.eggCapacity(data),
		petCapacity = Hatchery.petCapacity(data),
		dollars = data.Dollars,
		income = Hatchery.income(data),
		mount = data.Mount,
	}
end

return Hatchery
