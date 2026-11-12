-- Turns a pet model (Shared/PetModels) into a rigged Roblox Model that can be placed, animated and ridden.
--
-- How the Model is put together:
--     Root     Its PrimaryPart: invisible, anchored, the size of the whole pet, centred on it.
--     Body, Head, FrontLeftLeg, ...
--              One invisible part per limb, at the limb's joint. Each is joined to the limb it hangs from (Body to
--              Root) by a Motor6D with the limb's name, kept in the parent part. Turning a Motor6D (an animation,
--              or a script setting Motor6D.Transform) turns that limb, and every limb hanging from it.
--     Blocks   The visible parts, welded to their limb's part.
-- The pet faces -Z, the way Roblox models face. Attributes on the Model:
--     GroundOffset  how far Root's centre is above the pet's feet, in studs
--     SeatOffset    where a rider sits, relative to Root
-- Build a pet once and clone it for every copy.

local PetModels = require(script.Parent.PetModels)
local ModelEffects = require(script.Parent.ModelEffects)

local PetRig = {}

local function newPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
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

	local joints: { [string]: Part } = {}
	for _, limb in design.limbs do
		local joint = newPart(limb.name, model)
		joint.Transparency = 1
		joint.Size = Vector3.one * 0.2
		joint.CFrame = CFrame.new(toStuds(limb.pivot))
		joints[limb.name] = joint

		for index, box in limb.boxes do
			local block = newPart(limb.name .. "Block" .. index, model)
			block.Size = Vector3.new(box.sx, box.sy, box.sz) * scale
			block.CFrame = CFrame.new(toStuds({ box.x, box.y, box.z }))
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

	ModelEffects.add(root, design.light, design.particles, scale)

	model:SetAttribute("GroundOffset", design.center[2] * scale)
	model:SetAttribute("SeatOffset", toStuds(design.seat) - root.CFrame.Position)
	return model
end

return PetRig
