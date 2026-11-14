-- Animates rigged pets (built by Shared/PetRig): every rendered frame, each pet's joints are turned to where its
-- current move puts them (Shared/PetAnimations), by setting each Motor6D's Transform.
--
-- A pet plays the move named by its "Move" attribute, or, without one, its default: winged pets hover, the rest
-- walk (or swim, or crawl) on the spot. That means the pets roaming the pens at the hub (Workspace.PenPets, from
-- PenController, which sets "Move" as they walk and rest), pets being ridden (Workspace.Mounts, from
-- MountController), pets spawned from the admin panel (Workspace.AdminPets) and those in the Model Showroom
-- (Workspace.Showroom); set "Move" on one in Studio's Properties window to see its other moves (its moves are
-- listed in PetAnimations). Pets far from the camera are left still, since nobody can see them move.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local PetAnimations = Load.shared("PetAnimations")
local PetModels = Load.shared("PetModels")

local PetAnimationController = {}

-- `design` is worked out the first time the pet is close enough to animate (see step).
type Tracked = { model: Model, motors: { [string]: Motor6D }, design: any? }

-- Folders in Workspace whose pets are animated, however deep in them a pet is.
local WATCHED_FOLDERS = { "PenPets", "Mounts", "AdminPets", "Showroom" }
-- Pets further than this from the camera (in studs) stand still.
local ANIMATE_DISTANCE = 250
-- Working out a pet's design takes a while, so a frame works out at most this many (arriving at the showroom
-- brings dozens of pets into view at once).
local DESIGNS_PER_FRAME = 2

local tracked: { [Model]: Tracked } = {}
local clock = 0

-- Starts animating a rigged pet. Pets of a kind with no model are left alone.
function PetAnimationController.track(model: Model)
	if tracked[model] or PetModels.describe(model.Name) == nil then
		return
	end
	local motors = {}
	for _, motor in model:GetDescendants() do
		if motor:IsA("Motor6D") then
			motors[motor.Name] = motor
		end
	end
	tracked[model] = { model = model, motors = motors, design = nil }
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
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	local designsLeft = DESIGNS_PER_FRAME
	for model, entry in tracked do
		if model.Parent == nil then
			tracked[model] = nil
		else
			-- The root streams out when the player is far away; then there is nothing to see.
			local root = model.PrimaryPart
			if root and (eye == nil or (root.CFrame.Position - eye).Magnitude <= ANIMATE_DISTANCE) then
				if entry.design == nil and designsLeft > 0 then
					designsLeft -= 1
					entry.design = PetModels.get(model.Name)
				end
				if entry.design then
					apply(entry, clock)
				end
			end
		end
	end
end

-- Tracks a model if it is a pet, and otherwise the pets inside it (a folder of a zone's pets, say).
local function trackAll(instance: Instance)
	if instance:IsA("Model") and PetModels.describe(instance.Name) ~= nil then
		PetAnimationController.track(instance)
		return
	end
	for _, child in instance:GetChildren() do
		trackAll(child)
	end
end

-- Tracks the pets in a folder, now and as they arrive (the showroom's arrive as the player gets near).
local function watchFolder(folder: Instance)
	trackAll(folder)
	folder.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Model") and PetModels.describe(descendant.Name) ~= nil then
			PetAnimationController.track(descendant)
		end
	end)
end

function PetAnimationController.Init()
	for _, name in WATCHED_FOLDERS do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			watchFolder(existing)
		end
	end
	Workspace.ChildAdded:Connect(function(child)
		if table.find(WATCHED_FOLDERS, child.Name) then
			watchFolder(child)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return PetAnimationController
