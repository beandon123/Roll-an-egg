-- Small helpers for building the map out of plain parts: blocks, wedges, balls and cylinders, a random number
-- generator that gives the same numbers every time (so the map is the same in every server), and colour tools.

local Build = {}

export type Rgb = { number }
export type Random = () -> number

-- Park and Miller's generator: the same seed always gives the same map.
function Build.random(seed: number): Random
	local state = math.floor(seed) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

-- A number between low and high.
function Build.between(random: Random, low: number, high: number): number
	return low + (high - low) * random()
end

function Build.pick<T>(random: Random, list: { T }): T
	return list[math.clamp(math.floor(random() * #list) + 1, 1, #list)]
end

function Build.color(rgb: Rgb): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- A colour made lighter (amount > 0) or darker (amount < 0), from -1 to 1.
function Build.shade(rgb: Rgb, amount: number): Rgb
	local target = if amount > 0 then 255 else 0
	local t = math.abs(amount)
	return {
		math.floor(rgb[1] + (target - rgb[1]) * t + 0.5),
		math.floor(rgb[2] + (target - rgb[2]) * t + 0.5),
		math.floor(rgb[3] + (target - rgb[3]) * t + 0.5),
	}
end

function Build.mix(a: Rgb, b: Rgb, t: number): Rgb
	return {
		math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
	}
end

-- A little random variation on a colour, so rows of the same thing do not look stamped out.
function Build.vary(random: Random, rgb: Rgb, amount: number): Rgb
	return Build.shade(rgb, (random() * 2 - 1) * amount)
end

export type PartOptions = {
	material: Enum.Material?,
	transparency: number?,
	collide: boolean?,
	reflectance: number?,
	shape: Enum.PartType?,
	-- "Wedge" makes a WedgePart.
	class: string?,
}

-- An anchored part. Map parts never take part in hit checks for eggs (that is Shared/Obstacles' job), so they are
-- left out of raycasts and touch events unless they are something players walk on.
function Build.part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	rgb: Rgb,
	options: PartOptions?
): BasePart
	local opts = options or {}
	local part: BasePart
	if opts.class == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local plain = Instance.new("Part")
		if opts.shape then
			plain.Shape = opts.shape
		end
		part = plain
	end
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.CanCollide = if opts.collide == nil then true else opts.collide
	part.CanQuery = part.CanCollide
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = opts.material or Enum.Material.SmoothPlastic
	part.Color = Build.color(rgb)
	part.Transparency = opts.transparency or 0
	part.Reflectance = opts.reflectance or 0
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

function Build.block(parent: Instance, size: Vector3, cframe: CFrame, rgb: Rgb, options: PartOptions?): BasePart
	return Build.part(parent, "Block", size, cframe, rgb, options)
end

-- A wedge: full height at its back (+Z), sloping down to its front (-Z).
function Build.wedge(parent: Instance, size: Vector3, cframe: CFrame, rgb: Rgb, options: PartOptions?): BasePart
	local opts = table.clone(options or {})
	opts.class = "Wedge"
	return Build.part(parent, "Wedge", size, cframe, rgb, opts)
end

function Build.ball(parent: Instance, diameter: number, position: Vector3, rgb: Rgb, options: PartOptions?): BasePart
	local opts = table.clone(options or {})
	opts.shape = Enum.PartType.Ball
	return Build.part(parent, "Ball", Vector3.new(diameter, diameter, diameter), CFrame.new(position), rgb, opts)
end

-- A cylinder standing upright, its base at `base`.
function Build.column(
	parent: Instance,
	diameter: number,
	height: number,
	base: CFrame,
	rgb: Rgb,
	options: PartOptions?
): BasePart
	local opts = table.clone(options or {})
	opts.shape = Enum.PartType.Cylinder
	-- A Roblox cylinder runs along its X axis; turn it upright.
	return Build.part(
		parent,
		"Column",
		Vector3.new(height, diameter, diameter),
		base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		rgb,
		opts
	)
end

-- A cylinder lying along its own X axis, centred at `cframe`.
function Build.log(
	parent: Instance,
	diameter: number,
	length: number,
	cframe: CFrame,
	rgb: Rgb,
	options: PartOptions?
): BasePart
	local opts = table.clone(options or {})
	opts.shape = Enum.PartType.Cylinder
	return Build.part(parent, "Log", Vector3.new(length, diameter, diameter), cframe, rgb, opts)
end

function Build.model(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

return Build
