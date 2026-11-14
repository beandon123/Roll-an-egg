--!strict
-- The rules of the fuse machine: three of the same pet go in, and one egg of that pet comes out, which hatches a
-- size bigger.
--
--   - Exactly three pets, all of the same species (three Mammoths, never a Mammoth and a Dolphin).
--   - Variants and sizes may be mixed.
--   - Variant: each pet put in passes on its variant with a 1 in 3 chance (one Golden of three -> 33% Golden).
--   - Size: each pet put in has a 1 in 3 chance to set the size, and the result is one size up from that pet's
--     (one Tiny and two Normal -> 33% Normal, 67% Big). The variant and the size are rolled separately.
--
-- Pets and hatching are not built yet; FuseService will use these rules to take the three pets out of a player's
-- data and give them the egg. No Roblox objects, so tests run outside Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local PetTraits = require(Shared.Config.PetTraits)

-- The parts of a saved pet that fusing looks at.
export type Pet = { uid: string, species: string, variant: string, size: string }

-- Why a set of pets cannot be fused.
export type Refusal = "WrongCount" | "SamePetTwice" | "MixedSpecies" | "BadTraits"

local Fuse = {}

Fuse.COUNT = 3

-- Whether these pets can go into the fuse machine together, and if not, why.
function Fuse.check(pets: { Pet }): (boolean, Refusal?)
	if #pets ~= Fuse.COUNT then
		return false, "WrongCount"
	end
	local seen: { [string]: boolean } = {}
	for _, pet in pets do
		if seen[pet.uid] then
			return false, "SamePetTwice"
		end
		seen[pet.uid] = true
		if pet.species ~= pets[1].species then
			return false, "MixedSpecies"
		end
		if not PetTraits.isVariant(pet.variant) or PetTraits.sizeIndex(pet.size) == nil then
			return false, "BadTraits"
		end
	end
	return true, nil
end

-- The chances of each variant and each size coming out, as { [name] = chance from 0 to 1 }. For showing the odds
-- before the player fuses.
function Fuse.odds(pets: { Pet }): ({ [string]: number }, { [string]: number })
	local variants: { [string]: number } = {}
	local sizes: { [string]: number } = {}
	local share = 1 / #pets
	for _, pet in pets do
		variants[pet.variant] = (variants[pet.variant] or 0) + share
		local size = PetTraits.nextSize(pet.size)
		sizes[size] = (sizes[size] or 0) + share
	end
	return variants, sizes
end

-- Rolls what the egg will hatch into. `random` returns a number in [0, 1); it is called twice, once for the
-- variant and once for the size. Only call this for pets that pass `check`.
function Fuse.roll(pets: { Pet }, random: () -> number): (string, string)
	local function pick(): Pet
		local index = math.clamp(math.floor(random() * #pets) + 1, 1, #pets)
		return pets[index]
	end
	local variant = pick().variant
	local size = PetTraits.nextSize(pick().size)
	return variant, size
end

return Fuse
