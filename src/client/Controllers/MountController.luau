-- Riding pets, on this device: every ridden pet (the server welds them under their riders, in Workspace.Mounts)
-- walks while its rider is moving and stands still when they stop, and the local player sits on theirs, using the
-- sitting pose from Roblox's own character animations. PetAnimationController plays the pets' moves.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local PetAnimations = Load.shared("PetAnimations")
local PetModels = Load.shared("PetModels")

local localPlayer = Players.LocalPlayer

local MountController = {}

-- Faster than this (studs per second, across the ground) counts as moving.
local MOVING_SPEED = 2

-- Each ridden pet's walking and standing moves.
local moves: { [Model]: { walk: string, idle: string } } = {}
local sitTrack: AnimationTrack? = nil

local function movesOf(model: Model)
	local cached = moves[model]
	if cached == nil then
		local design = PetModels.get(model.Name)
		if design == nil then
			return nil
		end
		local walk = PetAnimations.defaultMove(design.skeleton, design.gait)
		local available = PetAnimations.movesOf(design.skeleton)
		cached = { walk = walk, idle = if table.find(available, "Idle") then "Idle" else walk }
		moves[model] = cached
	end
	return cached
end

-- Seats the local player on their pet, or stands them back up.
local function seat(riding: boolean)
	if riding and sitTrack == nil then
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		local animate = character and character:FindFirstChild("Animate")
		local sit = animate and animate:FindFirstChild("sit")
		local animation = sit and sit:FindFirstChildOfClass("Animation")
		if animator and animation then
			local track = animator:LoadAnimation(animation)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			track:Play()
			sitTrack = track
		end
	elseif not riding and sitTrack then
		sitTrack:Stop()
		sitTrack = nil
	end
end

local function update()
	local folder = Workspace:FindFirstChild("Mounts")
	local mine = false
	for model in moves do
		if model.Parent == nil then
			moves[model] = nil
		end
	end
	if folder then
		for _, model in folder:GetChildren() do
			if model:IsA("Model") then
				local riderId = model:GetAttribute("Rider")
				local rider = if typeof(riderId) == "number" then Players:GetPlayerByUserId(riderId) else nil
				local character = rider and rider.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local pair = movesOf(model)
				if pair and root and root:IsA("BasePart") then
					local velocity = root.AssemblyLinearVelocity
					local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > MOVING_SPEED
					local move = if moving then pair.walk else pair.idle
					if model:GetAttribute("Move") ~= move then
						model:SetAttribute("Move", move)
					end
				end
				if riderId == localPlayer.UserId then
					mine = true
				end
			end
		end
	end
	seat(mine)
end

function MountController.Init()
	localPlayer.CharacterAdded:Connect(function()
		-- A new character has no seat to stand up from.
		sitTrack = nil
	end)
end

function MountController.Start()
	RunService.RenderStepped:Connect(update)
end

return MountController
