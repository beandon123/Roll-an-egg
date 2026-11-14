-- Admin flight. While the server has set the local player's Flying attribute (the admin panel's Fly button), the
-- character flies instead of walking:
--     move (WASD, thumbstick, left stick)    flies where the camera looks, so look up to climb
--     Space or E, the jump button, A         rises
--     Q or Ctrl, B on a gamepad              sinks
-- Its speed is the FlySpeed attribute.
--
-- A LinearVelocity carries the character and an AlignOrientation keeps it upright, facing where the camera looks,
-- with the Humanoid in PlatformStand so it does not try to walk (which also stops it jumping onto eggs by
-- accident). Flight pauses while riding an egg, since the ride holds the character itself.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local AdminTools = Load.shared("Config", "AdminTools")

local UiState = require(script.Parent.Parent.Ui.UiState)

local localPlayer = Players.LocalPlayer

-- How quickly the speed follows the controls (per second): high enough to feel direct, low enough to be smooth.
local RESPONSIVENESS = 8

local FlyController = {}

type Rig = {
	humanoid: Humanoid,
	root: BasePart,
	attachment: Attachment,
	velocity: LinearVelocity,
	gyro: AlignOrientation,
}

local controls = nil
local rig: Rig? = nil

local function getCharacter(): (Humanoid?, BasePart?)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

-- Whether the character is flying right now.
function FlyController.IsFlying(): boolean
	return rig ~= nil
end

local function stop()
	local current = rig
	if current == nil then
		return
	end
	rig = nil
	current.attachment:Destroy()
	current.velocity:Destroy()
	current.gyro:Destroy()
	-- Fall back to the ground, unless a ride has taken the character over.
	local humanoid = current.humanoid
	if humanoid.Parent and humanoid.Health > 0 and UiState.ride == nil then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function start(humanoid: Humanoid, root: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "FlyAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "FlyVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root

	local gyro = Instance.new("AlignOrientation")
	gyro.Name = "FlyGyro"
	gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
	gyro.Attachment0 = attachment
	gyro.MaxTorque = math.huge
	gyro.Responsiveness = 40
	gyro.CFrame = root.CFrame.Rotation
	gyro.Parent = root

	humanoid.PlatformStand = true
	rig = { humanoid = humanoid, root = root, attachment = attachment, velocity = velocity, gyro = gyro }
end

-- +1 to rise, -1 to sink, 0 to hold height.
local function readVertical(humanoid: Humanoid): number
	local up = humanoid.Jump
		or UserInputService:IsKeyDown(Enum.KeyCode.Space)
		or UserInputService:IsKeyDown(Enum.KeyCode.E)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
	local down = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonB)
	return (if up then 1 else 0) - (if down then 1 else 0)
end

local function update(deltaTime: number)
	local humanoid, root = getCharacter()
	local wanted = localPlayer:GetAttribute(AdminTools.FLYING) == true and UiState.ride == nil
	if not wanted or humanoid == nil or root == nil then
		stop()
		return
	end
	if rig == nil or rig.root ~= root then
		stop()
		start(humanoid, root)
	end
	local current = rig :: Rig

	-- The move reading is relative to the camera (forward is -Z), so turning it by the camera flies where it looks.
	local camera = Workspace.CurrentCamera
	local move = if controls then controls:GetMoveVector() else Vector3.zero
	local direction = if camera then camera.CFrame:VectorToWorldSpace(move) else move
	direction += Vector3.new(0, readVertical(humanoid), 0)
	if direction.Magnitude > 1 then
		direction = direction.Unit
	end
	local speed = localPlayer:GetAttribute(AdminTools.FLY_SPEED)
	if typeof(speed) ~= "number" then
		speed = AdminTools.DEFAULT_FLY_SPEED
	end
	local blend = math.min(1, deltaTime * RESPONSIVENESS)
	current.velocity.VectorVelocity = current.velocity.VectorVelocity:Lerp(direction * speed, blend)

	-- Upright, facing the way the camera looks.
	if camera then
		local look = camera.CFrame.LookVector
		local level = Vector3.new(look.X, 0, look.Z)
		if level.Magnitude > 1e-3 then
			current.gyro.CFrame = CFrame.lookAt(Vector3.zero, level.Unit)
		end
	end
	-- Something else (a respawn, the stun after a ride) may have let go of PlatformStand.
	if not humanoid.PlatformStand then
		humanoid.PlatformStand = true
	end
end

function FlyController.Init()
	RunService.RenderStepped:Connect(update)
end

function FlyController.Start()
	-- The standard Roblox control scripts give one movement reading for keyboard, touch, and gamepad.
	local ok, result = pcall(function()
		local playerScripts = localPlayer:WaitForChild("PlayerScripts")
		local playerModule = require(playerScripts:WaitForChild("PlayerModule") :: ModuleScript) :: any
		return playerModule:GetControls()
	end)
	if ok then
		controls = result
	else
		warn(`[FlyController] could not load movement controls: {result}`)
	end
end

return FlyController
