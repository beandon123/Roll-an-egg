-- Animates rigged pets (built by Shared/PetRig): every rendered frame, each pet's joints are turned to where its
-- current move puts them (Shared/PetAnimations), by setting each Motor6D's Transform.
--
-- A pet plays the move named by its "Move" attribute, or, without one, its default: winged pets hover, the rest
-- walk (or swim, or crawl) on the spot. That means the pets roaming the pens at the hub (Workspace.PenPets, from
-- PenController, which sets "Move" as they walk and rest) and the ones ShowPets stands in Workspace.StudioPets;
-- set "Move" on one of those in Studio's Properties window to see its other moves (listed in PetAnimations).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local PetAnimations = Load.shared("PetAnimations")
local PetModels = Load.shared("PetModels")

local PetAnimationController = {}

type Tracked = { model: Model, motors: { [string]: Motor6D }, design: any }

local tracked: { [Model]: Tracked } = {}
local clock = 0

-- Starts animating a rigged pet. Pets of a kind with no model are left alone.
function PetAnimationController.track(model: Model)
	local design = PetModels.get(model.Name)
	if design == nil or tracked[model] then
		return
	end
	local motors = {}
	for _, motor in model:GetDescendants() do
		if motor:IsA("Motor6D") then
			motors[motor.Name] = motor
		end
	end
	tracked[model] = { model = model, motors = motors, design = design }
end

-- Turns each joint of a pet to where its move puts it `time` seconds in. The designs are drawn facing +z and the rig
-- turns them round to face -Z, so turns about x and z, and shifts along x and z, change sign.
local function apply(entry: Tracked, time: number)
	local design = entry.design
	-- Its joints may still be arriving from the server: look again until every limb's is there.
	local count = 0
	for _ in entry.motors do
		count += 1
	end
	if count < #design.limbs then
		for _, motor in entry.model:GetDescendants() do
			if motor:IsA("Motor6D") then
				entry.motors[motor.Name] = motor
			end
		end
	end
	local move = entry.model:GetAttribute("Move")
	if typeof(move) ~= "string" then
		move = PetAnimations.defaultMove(design.skeleton, design.gait)
	end
	local pose = PetAnimations.pose(design.skeleton, move, time, design.wingSpread, design.size[2])
	local scale = design.scale
	for name, motor in entry.motors do
		local p = pose[name]
		if p then
			motor.Transform = CFrame.new(-p[4] * scale, p[5] * scale, -p[6] * scale)
				* CFrame.fromEulerAnglesXYZ(-p[1], p[2], -p[3])
		else
			motor.Transform = CFrame.identity
		end
	end
end

local function step(deltaTime: number)
	clock += deltaTime
	for model, entry in tracked do
		if model.Parent == nil then
			tracked[model] = nil
		else
			apply(entry, clock)
		end
	end
end

-- Tracks the pets in a folder, now and as they arrive.
local function watchFolder(folder: Instance)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			PetAnimationController.track(child)
		end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			PetAnimationController.track(child)
		end
	end)
end

-- The folders of pets to animate: Studio's ShowPets, the pens, and pets being ridden.
local FOLDERS = { StudioPets = true, PenPets = true, Mounts = true }

function PetAnimationController.Init()
	for name in FOLDERS do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			watchFolder(existing)
		end
	end
	Workspace.ChildAdded:Connect(function(child)
		if FOLDERS[child.Name] then
			watchFolder(child)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return PetAnimationController
