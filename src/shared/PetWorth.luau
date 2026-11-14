--!strict
-- What a pet is worth: the dollars it earns in the pen, what it sells for, how fast it carries a rider, and the
-- variant it hatches as. Worked out from Config/Economy, the same way on the server (which pays out) and on each
-- player's device (which shows the numbers).
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.

local Economy = require(script.Parent.Config.Economy)

-- The parts of a pet this needs.
export type PetLike = { zone: number, rarity: string, variant: string? }

local PetWorth = {}

local variantsByName: { [string]: Economy.Variant } = {}
for _, variant in Economy.VARIANTS do
	variantsByName[variant.name] = variant
end

function PetWorth.variant(name: string?): Economy.Variant
	return variantsByName[name or "Normal"] or variantsByName.Normal
end

-- Dollars a second the pet earns while it is in its owner's pen.
function PetWorth.income(pet: PetLike): number
	local base = Economy.RARITY_INCOME[pet.rarity] or 1
	return base * Economy.ZONE_SCALE ^ math.max(0, pet.zone - 1) * PetWorth.variant(pet.variant).worth
end

-- Dollars selling the pet pays.
function PetWorth.sellPrice(pet: PetLike): number
	return math.floor(PetWorth.income(pet) * Economy.SELL_SECONDS)
end

-- How fast the pet carries a rider, in studs per second.
function PetWorth.mountSpeed(pet: PetLike): number
	return (Economy.MOUNT_SPEED[pet.rarity] or 22) + PetWorth.variant(pet.variant).speedBonus
end

-- The variant a newly hatched pet comes out as, from a random number in [0, 1): the rarest is checked first.
function PetWorth.rollVariant(random01: number): string
	local running = 0
	for index = #Economy.VARIANTS, 2, -1 do
		local variant = Economy.VARIANTS[index]
		running += variant.chance
		if random01 < running then
			return variant.name
		end
	end
	return "Normal"
end

-- Dollars to buy the next pen level up from `level`, or nil if the pen is as big as it gets.
function PetWorth.penUpgradeCost(level: number): number?
	if level >= Economy.MAX_PEN_LEVEL then
		return nil
	end
	return Economy.PEN_UPGRADE_COST[level + 1]
end

return PetWorth
