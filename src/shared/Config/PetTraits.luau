--!strict
-- Traits every pet has on top of its species: a variant and a size.
-- Pure data and math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Variants are rolled when a pet hatches (Config/Economy.VARIANTS has their odds and what they are worth).
-- Sizes are a ladder. Each hatched pet rolls a size, and bigger sizes are rarer. The fuse machine turns three of
-- the same pet into one that is usually a size bigger (see Logic/Fuse). Titanic, the biggest, only comes from
-- Titan Eggs and the fuse machine. What each size does (how big it is drawn, how much more it earns) is not decided
-- yet, so hatched pets do not roll a size yet.

local Economy = require(script.Parent.Economy)

local PetTraits = {}

-- Rarest last. A pet's variant is rolled when it hatches.
PetTraits.Variants = {}
for _, variant in Economy.VARIANTS do
	table.insert(PetTraits.Variants, variant.name)
end

-- Smallest first.
PetTraits.Sizes = { "Tiny", "Small", "Normal", "Big", "Huge", "Giant", "Colossal", "Titanic" }

-- The chance that the fuse machine grows a pet of this size one step (decided: certain up to Big, then 10% less
-- for each step after it). Titanic is the biggest and cannot grow.
PetTraits.GROW_CHANCE = {
	Tiny = 1,
	Small = 1,
	Normal = 1,
	Big = 0.9,
	Huge = 0.8,
	Giant = 0.7,
	Colossal = 0.6,
	Titanic = 0,
} :: { [string]: number }

-- Relative odds of each size when a pet hatches, by the kind of egg it hatches from (first pass; tune in
-- playtests). The bigger the size, the lower its chance. Only Titan Eggs can hatch a Titanic pet.
PetTraits.HATCH_SIZE_WEIGHTS = {
	-- Eggs claimed on the runway.
	Egg = { Tiny = 40, Small = 28, Normal = 18, Big = 8, Huge = 4, Giant = 1.5, Colossal = 0.5 },
	-- Titan Eggs from the server event.
	TitanEgg = { Tiny = 30, Small = 25, Normal = 20, Big = 12, Huge = 7, Giant = 3.5, Colossal = 1.5, Titanic = 1 },
} :: { [string]: { [string]: number } }

local sizeIndex: { [string]: number } = {}
for index, size in PetTraits.Sizes do
	sizeIndex[size] = index
end

local isVariant: { [string]: boolean } = {}
for _, variant in PetTraits.Variants do
	isVariant[variant] = true
end

function PetTraits.isVariant(variant: string): boolean
	return isVariant[variant] == true
end

-- A size's place on the ladder (1 = Tiny), or nil if it is not a size.
function PetTraits.sizeIndex(size: string): number?
	return sizeIndex[size]
end

-- The next size up; the biggest size stays where it is.
function PetTraits.nextSize(size: string): string
	local index = sizeIndex[size]
	if index == nil then
		return size
	end
	return PetTraits.Sizes[math.min(index + 1, #PetTraits.Sizes)]
end

-- The chance of each size hatching from a kind of egg, as { [size] = chance from 0 to 1 }.
function PetTraits.hatchSizeOdds(eggKind: string): { [string]: number }
	local weights = PetTraits.HATCH_SIZE_WEIGHTS[eggKind]
	local odds: { [string]: number } = {}
	if weights == nil then
		return odds
	end
	local total = 0
	for _, weight in weights do
		total += weight
	end
	for size, weight in weights do
		odds[size] = weight / total
	end
	return odds
end

-- Picks the size of a newly hatched pet from a random number in [0, 1).
function PetTraits.rollHatchSize(eggKind: string, random01: number): string
	local weights = PetTraits.HATCH_SIZE_WEIGHTS[eggKind] or PetTraits.HATCH_SIZE_WEIGHTS.Egg
	local total = 0
	for _, size in PetTraits.Sizes do
		total += weights[size] or 0
	end

	local target = random01 * total
	local running = 0
	local last = PetTraits.Sizes[1]
	for _, size in PetTraits.Sizes do
		local weight = weights[size] or 0
		if weight > 0 then
			running += weight
			last = size
			if target < running then
				return size
			end
		end
	end
	return last
end

return PetTraits
