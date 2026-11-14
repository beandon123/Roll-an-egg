--!strict
-- Traits every pet has on top of its species: a variant and a size.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Sizes are a ladder. Hatched pets come out small; the fuse machine turns three of the same pet into one a size
-- bigger (see Logic/Fuse). What each size does (how big it is drawn, how much more it earns) is set once pets exist.

local PetTraits = {}

-- Rarest last. A pet's variant is rolled when it hatches.
PetTraits.Variants = { "Normal", "Golden", "Rainbow" }

-- Smallest first.
PetTraits.Sizes = { "Tiny", "Normal", "Big", "Huge", "Giant", "Colossal" }

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

return PetTraits
