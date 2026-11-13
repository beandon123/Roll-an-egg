-- Turns a pet model (Shared/PetModels) into a rigged Roblox Model that can be placed, animated and ridden.
--
-- How the Model is put together:
--     Root     Its PrimaryPart: invisible, anchored, the size of the whole pet, centred on it.
--     Body, Head, FrontLeftLeg, ...
--              One invisible part per limb, at the limb's joint. Each is joined to the limb it hangs from (Body to
--              Root) by a Motor6D with the limb's name, kept in the parent part. Turning a Motor6D (an animation,
--              or a script setting Motor6D.Transform) turns that limb, and every limb hanging from it.
--     Blocks   The visible parts, welded to their limb's part: plain blocks, wedges (WedgePart), and egg shapes (a
--              Part with a sphere SpecialMesh, which stretches to fill it), some turned at an angle.
--     Fires    Small invisible parts holding a Fire, welded to their limb where a design puts a flame.
-- The pet faces -Z, the way Roblox models face. Attributes on the Model:
--     GroundOffset  how far Root's centre is above the ground, in studs (including any hover for floating pets)
--     SeatOffset    where a rider sits, relative to Root
-- Build a pet once and clone it for every copy.

local PetModels = require(script.Parent.PetModels)
local ModelEffects = require(script.Parent.ModelEffects)

local PetRig = {}

local function newPart(name: string, parent: Instance, className: string?): BasePart
	local part = Instance.new(className or "Part") :: BasePart
	part.Name = name
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	if part:IsA("Part") then
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	end
	part.Parent = parent
	return part
end

-- The rigged Model for a pet (a design name such as "MossStag"), or nil if that pet has no model yet.
-- It is built at the origin; move it with Model:PivotTo.
function PetRig.build(kind: string): Model?
	local design = PetModels.get(kind)
	if design == nil then
		return nil
	end
	local scale = design.scale

	-- Designs face +z in voxels; Roblox models face -Z in studs. Turning round flips x and z.
	local function toStuds(point: { number }): Vector3
		return Vector3.new(-point[1] * scale, point[2] * scale, -point[3] * scale)
	end

	local model = Instance.new("Model")
	model.Name = kind

	local root = newPart("Root", model)
	root.Anchored = true
	root.Transparency = 1
	root.Size = Vector3.new(design.size[1], design.size[2], design.size[3]) * scale
	root.CFrame = CFrame.new(toStuds(design.center))
	model.PrimaryPart = root

	-- A design's turned part: its angle, the same way round as its position (x and z flipped).
	local function turned(position: Vector3, r: { number }?): CFrame
		if r == nil then
			return CFrame.new(position)
		end
		return CFrame.new(position.X, position.Y, position.Z, r[1], -r[2], r[3], -r[4], r[5], -r[6], r[7], -r[8], r[9])
	end

	local joints: { [string]: BasePart } = {}
	for _, limb in design.limbs do
		local joint = newPart(limb.name, model)
		joint.Transparency = 1
		joint.Size = Vector3.one * 0.2
		joint.CFrame = CFrame.new(toStuds(limb.pivot))
		joints[limb.name] = joint

		for index, box in limb.boxes do
			local block =
				newPart(limb.name .. "Block" .. index, model, if box.shape == "Wedge" then "WedgePart" else nil)
			block.Size = Vector3.new(box.sx, box.sy, box.sz) * scale
			block.CFrame = turned(toStuds({ box.x, box.y, box.z }), box.rotation)
			if box.shape == "Ball" then
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = block
			end
			block.Color = Color3.fromRGB(box.color[1], box.color[2], box.color[3])
			block.Material = (Enum.Material :: any)[box.material]
			block.Transparency = box.transparency

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = joint
			weld.Part1 = block
			weld.Parent = block
		end
	end

	for _, limb in design.limbs do
		local joint = joints[limb.name]
		local parent = if limb.parent then joints[limb.parent] else root
		local motor = Instance.new("Motor6D")
		motor.Name = limb.name
		motor.Part0 = parent
		motor.Part1 = joint
		motor.C0 = parent.CFrame:Inverse() * joint.CFrame
		motor.C1 = CFrame.identity
		motor.Parent = parent
	end

	for index, fire in design.fires do
		local holder = newPart("Fire" .. index, model)
		holder.Transparency = 1
		holder.Size = Vector3.one * 0.2
		holder.CFrame = CFrame.new(toStuds(fire.position))
		local flame = Instance.new("Fire")
		flame.Size = math.clamp(fire.size * scale, 2, 30)
		flame.Heat = math.clamp(fire.size * scale * 1.5, 1, 25)
		flame.Color = Color3.fromRGB(fire.color[1], fire.color[2], fire.color[3])
		flame.SecondaryColor = Color3.fromRGB(fire.secondary[1], fire.secondary[2], fire.secondary[3])
		flame.Parent = holder
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = joints[fire.limb]
		weld.Part1 = holder
		weld.Parent = holder
	end

	ModelEffects.add(root, design.light, design.particles, scale)

	model:SetAttribute("GroundOffset", (design.center[2] + design.hover) * scale)
	model:SetAttribute("SeatOffset", toStuds(design.seat) - root.CFrame.Position)
	return model
end

return PetRig
