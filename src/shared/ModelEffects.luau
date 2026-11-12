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
		emitter.Parent = part
	end
end

return ModelEffects
