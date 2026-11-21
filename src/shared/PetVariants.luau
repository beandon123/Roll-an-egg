-- How the mutations look (Gold, Diamond and Rainbow, rolled when a pet hatches; Silver is shelved but drawn for pets
-- that already have it): every block of the pet is recoloured, keeping its light and shade so the pet's markings
-- still show, and dark details (eyes, nostrils) stay dark. Gold is shiny gold; Diamond is bright icy white glass;
-- Rainbow runs through every colour from tail to nose (teal, blue, purple, red, then green at the head, like the
-- owner's reference). All three glint.
-- The pack-only variants (Config/Shop's packs) go further: a Molten pet is black obsidian whose lighter markings
-- glow like lava, shedding embers; a Crystal pet is cyan glass, shiny and see-through a little, sparkling.
-- PetRig uses this when it builds a pet of a variant.

local PetVariants = {}

-- Blocks darker than this keep their colour, so eyes stay eyes.
local KEEP_DARK = 0.12
-- On a Molten pet, blocks at least this light (pale markings, bellies, muzzles) glow as lava; the rest is obsidian.
local MOLTEN_LAVA_FROM = 0.72

local SILVER = Color3.fromRGB(206, 212, 224)
local GOLD = Color3.fromRGB(255, 196, 58)
local DIAMOND = Color3.fromRGB(176, 226, 255)
-- Where a Rainbow pet's colours start at its tail (teal), and how far round the colour wheel they turn by its nose
-- (through blue, purple and red to green).
local RAINBOW_START = 0.5
local RAINBOW_TURN = 0.83
local OBSIDIAN = Color3.fromRGB(46, 36, 40)
local LAVA_DARK = Color3.fromRGB(255, 84, 16)
local LAVA_BRIGHT = Color3.fromRGB(255, 196, 70)
local CRYSTAL = Color3.fromRGB(110, 236, 255)
local CRYSTAL_TIP = Color3.fromRGB(196, 170, 255)

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
	elseif variant == "Diamond" then
		-- Icy white-blue, its lightest blocks almost pure white, like facets catching the light.
		local ice = DIAMOND:Lerp(Color3.new(1, 1, 1), math.clamp(light - 0.55, 0, 0.45))
		return Color3.new(
			math.min(1, ice.R * (0.6 + 0.4 * shade)),
			math.min(1, ice.G * (0.6 + 0.4 * shade)),
			math.min(1, ice.B * (0.6 + 0.4 * shade))
		)
	elseif variant == "Rainbow" then
		return Color3.fromHSV((RAINBOW_START + along * RAINBOW_TURN) % 1, 0.86, math.clamp(0.5 + 0.5 * shade, 0, 1))
	elseif variant == "Molten" then
		if light >= MOLTEN_LAVA_FROM then
			-- The lighter it was, the hotter it glows.
			return LAVA_DARK:Lerp(LAVA_BRIGHT, math.clamp((light - MOLTEN_LAVA_FROM) * 2, 0, 1))
		end
		return Color3.new(
			math.min(1, OBSIDIAN.R * shade * 1.2),
			math.min(1, OBSIDIAN.G * shade * 1.2),
			math.min(1, OBSIDIAN.B * shade * 1.2)
		)
	elseif variant == "Crystal" then
		-- Cyan glass, turning lilac towards the nose.
		local glass = CRYSTAL:Lerp(CRYSTAL_TIP, along * 0.6)
		return Color3.new(
			math.min(1, glass.R * (0.6 + 0.5 * shade)),
			math.min(1, glass.G * (0.6 + 0.5 * shade)),
			math.min(1, glass.B * (0.6 + 0.5 * shade))
		)
	end
	return color
end

-- How shiny a variant's blocks are.
function PetVariants.reflectance(variant: string?): number
	if variant == "Silver" then
		return 0.2
	elseif variant == "Gold" then
		return 0.25
	elseif variant == "Diamond" then
		return 0.35
	elseif variant == "Molten" then
		return 0.1
	elseif variant == "Crystal" then
		return 0.3
	end
	return 0
end

-- How one block of a pet is drawn in a variant: its colour, material (an Enum.Material name) and transparency, from
-- how the design draws it. A Molten pet's lava, and whatever already glowed, glows (Neon) as lava; a Crystal pet's
-- blocks are a little see-through.
function PetVariants.paint(
	color: Color3,
	material: string,
	transparency: number,
	variant: string?,
	along: number
): (Color3, string, number)
	if variant == "Molten" then
		local light = luminance(color)
		if material == "Neon" and light >= KEEP_DARK then
			return LAVA_BRIGHT, "Neon", transparency
		elseif light >= MOLTEN_LAVA_FROM then
			return PetVariants.tint(color, variant, along), "Neon", transparency
		end
		return PetVariants.tint(color, variant, along),
			if material == "Neon" then "SmoothPlastic" else material,
			transparency
	elseif variant == "Crystal" then
		return PetVariants.tint(color, variant, along), material, math.max(transparency, 0.2)
	elseif variant == "Diamond" then
		-- Solid, unlike Crystal, but glassy; whatever already glowed keeps glowing.
		return PetVariants.tint(color, variant, along), if material == "Neon" then "Neon" else "Glass", transparency
	end
	return PetVariants.tint(color, variant, along), material, transparency
end

-- The variants that glint.
local GLINTS = { Gold = true, Diamond = true, Rainbow = true, Molten = true, Crystal = true }

-- Gives the mutations and the pack-only pets a glint of sparkles (embers for Molten) from their root.
function PetVariants.addGlint(root: BasePart, variant: string?)
	if variant == nil or not GLINTS[variant] then
		return
	end
	local glint = Instance.new("ParticleEmitter")
	glint.Name = "VariantGlint"
	glint.LightEmission = 1
	if variant == "Gold" then
		glint.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	elseif variant == "Molten" then
		glint.Color = ColorSequence.new(LAVA_BRIGHT, LAVA_DARK)
		glint.Texture = "rbxasset://textures/particles/fire_main.dds"
		glint.Acceleration = Vector3.new(0, 4, 0)
	elseif variant == "Crystal" then
		glint.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), CRYSTAL)
	elseif variant == "Diamond" then
		glint.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), DIAMOND)
	else
		glint.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 255, 140)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 150, 255)),
		})
	end
	glint.Size = NumberSequence.new(if variant == "Molten" then 0.8 else 0.5, 0)
	glint.Lifetime = NumberRange.new(0.6, 1.2)
	glint.Rate = if variant == "Molten" or variant == "Crystal" or variant == "Diamond" then 14 else 6
	glint.Speed = NumberRange.new(1, 3)
	glint.SpreadAngle = Vector2.new(180, 180)
	glint.Parent = root
end

return PetVariants
