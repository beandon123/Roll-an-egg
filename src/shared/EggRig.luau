-- Turns an egg model (Shared/EggModels) into a Roblox Model, lying on its side with its pointed top towards +X, the
-- way eggs roll down the runway.
--
-- How the Model is put together:
--     Root     Its PrimaryPart: invisible, anchored, the size of the whole egg, centred on it. Moving it moves the
--              whole egg, so an egg rolling down the runway is a single CFrame write a frame.
--     Blocks   The visible parts, welded to Root.
--     Effects  The egg's light and particles (Shared/ModelEffects), on Root.
-- Every egg of a kind is the same size (see Shared/EggSpec), so build each kind once and clone it for every copy.

local EggModels = require(script.Parent.EggModels)
local ModelEffects = require(script.Parent.ModelEffects)

local EggRig = {}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- The Model for one kind of egg (a design name such as "MossStag"), sized by its spec (Shared/EggSpec: the egg's
-- radius and half its length, in studs). It is built at the origin; move it with Model:PivotTo.
function EggRig.build(kind: string, spec: { radius: number, halfLength: number }): Model
	local design = EggModels.get(kind)
	assert(design, `no egg model called {kind}`)
	-- Studs per voxel: the egg's widest layer is EggModels.RADIUS voxels from the middle.
	local voxel = spec.radius / EggModels.RADIUS

	local model = Instance.new("Model")
	model.Name = "Egg"

	-- Invisible, anchored, and the size of the egg: what a label sits on and the particles come from.
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Material = Enum.Material.SmoothPlastic
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Size = Vector3.new(spec.halfLength * 2, spec.radius * 2, spec.radius * 2)
	root.Transparency = 1
	root.CFrame = CFrame.identity
	root.Parent = model
	model.PrimaryPart = root

	for index, box in design.boxes do
		local part = Instance.new("Part")
		part.Name = "Block" .. index
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Material = (Enum.Material :: any)[box.material]
		part.Color = rgb(box.color)
		part.Transparency = box.transparency
		-- The designs stand the egg up (y along the egg); on the runway it lies on its side, so the egg's y becomes
		-- X, and its x becomes -Y.
		part.Size = Vector3.new(box.sy, box.sx, box.sz) * voxel
		part.CFrame = CFrame.new(box.y * voxel, -box.x * voxel, box.z * voxel)
		part.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	ModelEffects.add(root, design.light, design.particles, voxel)

	return model
end

return EggRig
