-- How Silver, Gold and Rainbow pets look: every block of the pet is recoloured, keeping its light and shade so the
-- pet's markings still show, and dark details (eyes, nostrils) stay dark. Gold and Rainbow pets also glint.
-- PetRig uses this when it builds a pet of a variant.

local PetVariants = {}

-- Blocks darker than this keep their colour, so eyes stay eyes.
local KEEP_DARK = 0.12

local SILVER = Color3.fromRGB(206, 212, 224)
local GOLD = Color3.fromRGB(255, 196, 58)

local function luminance(color: Color3): number
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

-- The colour a block of `color` takes in a variant. `along` is how far along the pet the block is, from 0 (tail)
-- to 1 (nose), which a Rainbow pet's stripes follow.
function PetVariants.tint(color: Color3, variant: string?, along: number): Color3
	if variant == nil or variant == "Normal" then
		return color
	end
	local light = luminance(color)
	if light < KEEP_DARK then
		return color
	end
	-- Light and shade from the original, from 0.55 (dark) to 1.15 (light).
	local shade = 0.55 + 0.6 * light
	if variant == "Silver" then
		return Color3.new(math.min(1, SILVER.R * shade), math.min(1, SILVER.G * shade), math.min(1, SILVER.B * shade))
			:Lerp(color, 0.15)
	elseif variant == "Gold" then
		return Color3.new(math.min(1, GOLD.R * shade), math.min(1, GOLD.G * shade), math.min(1, GOLD.B * shade))
	elseif variant == "Rainbow" then
		return Color3.fromHSV((along * 0.85) % 1, 0.62, math.clamp(0.45 + 0.55 * shade, 0, 1))
	end
	return color
end

-- How shiny a variant's blocks are.
function PetVariants.reflectance(variant: string?): number
	if variant == "Silver" then
		return 0.2
	elseif variant == "Gold" then
		return 0.25
	end
	return 0
end

-- Gives Gold and Rainbow pets a glint of sparkles from their root.
function PetVariants.addGlint(root: BasePart, variant: string?)
	if variant ~= "Gold" and variant ~= "Rainbow" then
		return
	end
	local glint = Instance.new("ParticleEmitter")
	glint.Name = "VariantGlint"
	glint.LightEmission = 1
	glint.Color = if variant == "Gold"
		then ColorSequence.new(Color3.fromRGB(255, 230, 120))
		else ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 255, 140)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 150, 255)),
		})
	glint.Size = NumberSequence.new(0.5, 0)
	glint.Lifetime = NumberRange.new(0.6, 1.2)
	glint.Rate = 6
	glint.Speed = NumberRange.new(1, 3)
	glint.SpreadAngle = Vector2.new(180, 180)
	glint.Parent = root
end

return PetVariants
