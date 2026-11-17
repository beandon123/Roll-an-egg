-- Riding pets, on this device: every ridden pet (the server welds them under their riders, in Workspace.Mounts)
-- walks while its rider is moving and stands still when they stop, and the local player sits on theirs, using the
-- sitting pose from Roblox's own character animations. PetAnimationController plays the pets' moves.
--
-- Riding costs stamina; when it runs out the server takes the pet away (MountService.Buck) and this device tosses
-- the player off it, staggering, and says why.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local Net = Load.shared("Net")
local PetAnimations = Load.shared("PetAnimations")
local PetModels = Load.shared("PetModels")
local Tuning = Load.shared("Config", "Tuning")

local UiState = require(script.Parent.Parent.Ui.UiState)

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

local BUCKED_COLOR = Color3.fromRGB(255, 150, 90)

-- The player's pet has bucked them off (their stamina ran out): up and backwards, staggering for a moment.
local function bucked(kind: string)
	seat(false)
	local about = PetModels.describe(kind)
	UiState.showToast(
		`{if about then "Your " .. about.name else "Your pet"} bucked you off! Out of stamina.`,
		BUCKED_COLOR,
		3
	)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return
	end
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = root.CFrame.LookVector * -18 + Vector3.new(0, 38, 0)
	task.delay(Tuning.BUCKED_STAGGER_TIME, function()
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

function MountController.Init()
	localPlayer.CharacterAdded:Connect(function()
		-- A new character has no seat to stand up from.
		sitTrack = nil
	end)
	Net.PetBucked.OnClientEvent:Connect(bucked)
end

function MountController.Start()
	RunService.RenderStepped:Connect(update)
end

return MountController
