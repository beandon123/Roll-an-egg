-- The glow and particles that rare eggs and pets give off, shared by the egg and pet builders.
-- `light` and `particles` are the plain tables EggModels and PetModels describe them with.

local ModelEffects = {}

-- Particle settings by style. Acceleration is in world space, so embers rise and snow falls whichever way the
-- model has turned or rolled.
local STYLES = {
	Sparkles = { lifetime = 0.9, speed = 1.5, acceleration = Vector3.zero, size = 0.45, transparency = 0 },
	Embers = { lifetime = 1.4, speed = 1, acceleration = Vector3.new(0, 7, 0), size = 0.35, transparency = 0 },
	Bubbles = { lifetime = 1.8, speed = 0.6, acceleration = Vector3.new(0, 4, 0), size = 0.5, transparency = 0.35 },
	Snow = { lifetime = 2, speed = 0.5, acceleration = Vector3.new(0, -3, 0), size = 0.35, transparency = 0.1 },
	-- Slow glowing motes drifting round the pet, blinking on and off (forest pets).
	Fireflies = { lifetime = 3, speed = 0.6, acceleration = Vector3.new(0, 0.4, 0), size = 0.3, transparency = 0 },
}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- Adds a light, particles, or both to `part`. `voxel` is the model's studs per voxel, so particles match its size.
function ModelEffects.add(part: BasePart, light, particles, voxel: number)
	if light then
		local glow = Instance.new("PointLight")
		glow.Color = rgb(light.color)
		glow.Brightness = light.brightness
		glow.Range = light.range
		glow.Shadows = false
		glow.Parent = part
	end

	if particles then
		local style = STYLES[particles.style] or STYLES.Sparkles
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(rgb(particles.color))
		emitter.Rate = particles.rate
		emitter.Lifetime = NumberRange.new(style.lifetime * 0.7, style.lifetime)
		emitter.Speed = NumberRange.new(style.speed * 0.5, style.speed)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = style.acceleration
		emitter.Size = NumberSequence.new(style.size * voxel * 2, 0)
		emitter.Transparency = NumberSequence.new(style.transparency, 1)
		emitter.LightEmission = 1
		if particles.style == "Fireflies" then
			-- Fade in and out, so each one blinks.
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.25, 0),
				NumberSequenceKeypoint.new(0.6, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			})
			emitter.Size = NumberSequence.new(style.size * voxel * 2)
			emitter.Drag = 1
		end
		emitter.Parent = part
	end
end

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- The swirl of light round a rare pet's feet, like the auras of the biggest pets in other games: wisps that wind up
-- round it from a ring on the ground, with sparks among them. Built on a flat invisible disc as wide as the pet,
-- `groundOffset` studs below `root`'s centre, welded to `root`.
function ModelEffects.addAura(model: Model, root: BasePart, aura, groundOffset: number)
	local width = math.max(root.Size.X, root.Size.Z) * 0.8
	local disc = Instance.new("Part")
	disc.Name = "Aura"
	disc.Transparency = 1
	disc.Anchored = false
	disc.Massless = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.Size = Vector3.new(width, 0.2, width)
	disc.CFrame = root.CFrame * CFrame.new(0, -groundOffset + 0.1, 0)
	disc.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = disc
	weld.Parent = disc

	local color = rgb(aura.color)
	local accent = rgb(aura.accent)
	local height = math.clamp(root.Size.Y * 0.45, 3, 14)

	-- Wisps rising from a ring round its feet, drawn out along the way they move.
	local wisps = Instance.new("ParticleEmitter")
	wisps.Name = "AuraWisps"
	wisps.Texture = SPARKLE
	wisps.Shape = Enum.ParticleEmitterShape.Disc
	wisps.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	wisps.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	wisps.ShapePartial = 0.25
	wisps.EmissionDirection = Enum.NormalId.Top
	wisps.Orientation = Enum.ParticleOrientation.VelocityParallel
	wisps.Color = ColorSequence.new(accent, color)
	wisps.LightEmission = 1
	wisps.Rate = math.clamp(width * 3, 16, 60)
	wisps.Lifetime = NumberRange.new(0.6, 1.1)
	wisps.Speed = NumberRange.new(height * 0.6, height * 1.1)
	wisps.Drag = 2
	wisps.SpreadAngle = Vector2.new(25, 25)
	wisps.RotSpeed = NumberRange.new(-90, 90)
	wisps.Squash = NumberSequence.new(1.2)
	wisps.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, math.clamp(width * 0.09, 0.4, 2.2)),
		NumberSequenceKeypoint.new(1, 0),
	})
	wisps.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.3, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	wisps.Parent = disc

	-- A soft glow pooled on the ground under it.
	local pool = Instance.new("ParticleEmitter")
	pool.Name = "AuraPool"
	pool.Texture = SPARKLE
	pool.Shape = Enum.ParticleEmitterShape.Disc
	pool.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pool.EmissionDirection = Enum.NormalId.Top
	pool.Color = ColorSequence.new(color)
	pool.LightEmission = 1
	pool.Rate = 6
	pool.Lifetime = NumberRange.new(0.8, 1.2)
	pool.Speed = NumberRange.new(0.2, 0.6)
	pool.RotSpeed = NumberRange.new(-40, 40)
	pool.Rotation = NumberRange.new(0, 360)
	pool.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, width * 0.25),
		NumberSequenceKeypoint.new(1, width * 0.45),
	})
	pool.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	pool.Parent = disc

	-- Sparks thrown up out of the swirl.
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "AuraSparks"
	sparks.Texture = SPARKLE
	sparks.Shape = Enum.ParticleEmitterShape.Disc
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Color = ColorSequence.new(accent)
	sparks.LightEmission = 1
	sparks.Rate = math.clamp(width, 4, 16)
	sparks.Lifetime = NumberRange.new(0.8, 1.6)
	sparks.Speed = NumberRange.new(height * 0.3, height * 0.8)
	sparks.SpreadAngle = Vector2.new(35, 35)
	sparks.Acceleration = Vector3.new(0, -height * 0.25, 0)
	sparks.Size = NumberSequence.new(math.clamp(width * 0.035, 0.2, 0.8), 0)
	sparks.Parent = disc
end

return ModelEffects
