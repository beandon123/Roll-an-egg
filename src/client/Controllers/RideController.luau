-- The local player's side of riding: asking to jump onto eggs, steering, hopping off, being thrown off, and
-- running into obstacles (spotted here at once and reported; the server has the final say and checks on its own).
--
-- The server decides everything that matters (whether a mount counts, stamina, claims). This controller only
-- asks, steers, and makes the result feel immediate.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local EggModels = Load.shared("EggModels")
local EggMotion = Load.shared("EggMotion")
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")
local Obstacles = Load.shared("Obstacles")
local Rarities = Load.shared("Config", "Rarities")
local Runway = Load.shared("Runway")
local Tuning = Load.shared("Config", "Tuning")

local EggController = require(script.Parent.EggController)
local InventoryController = require(script.Parent.InventoryController)
local UiState = require(script.Parent.Parent.Ui.UiState)

local localPlayer = Players.LocalPlayer

-- Seconds between mount requests while a jumping player is near an egg.
local MOUNT_REQUEST_INTERVAL = 0.25
-- After jumping off an egg, ignore that same egg for this long so the player does not land straight back on it.
local SAME_EGG_IGNORE_TIME = 1
-- A jump press only counts as "hop off" once the jump input that got the player onto the egg has been released.
local JUMP_RELEASE_GAP = 0.15
local MIN_RIDE_BEFORE_HOP = 0.3
-- How much higher above an egg a player riding a pet may be when they jump onto it (as on the server).
local MOUNTED_REACH = 40

local RideController = {}

local controls = nil
local agility = Tuning.BASE_AGILITY

-- os.clock() times
local stunnedUntil = 0
local lastMountRequestAt = 0
local lastLateralSentAt = 0
local lastJumpRequestAt = 0
local rideStartedAt = 0
local awaitingJumpRelease = false

local lastLeftEggId: number? = nil
local lastLeftAt = 0

-- Obstacles this ride has hit, so each one counts once, and whether a hit has already ended the ride here.
local rideHits: { [number]: boolean } = {}
local endedByHit = false

local BUMP_COLOR = Color3.fromRGB(255, 190, 90)
local OUCH_COLOR = Color3.fromRGB(255, 110, 110)

local function getCharacter(): (Humanoid?, BasePart?)
	local character = localPlayer.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- Left/right steering from -1 to 1, relative to the camera, from whatever the player is using
-- (keyboard, thumbstick, or gamepad).
local function readSteer(): number
	local move = Vector3.zero
	if controls then
		move = controls:GetMoveVector()
	end
	if move.Magnitude < 0.05 then
		return 0
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return 0
	end
	-- Side to side on the runway is the world X axis.
	local world = camera.CFrame:VectorToWorldSpace(Vector3.new(move.X, 0, move.Z))
	return math.clamp(world.X, -1, 1)
end

-- Lets go of the egg on this device. `reason` decides how the character leaves it.
local function release(reason: string)
	local ride = UiState.ride
	if ride == nil then
		return
	end
	local egg = EggController.GetEgg(ride.eggId)
	local eggSpeed = if egg then egg.spec.rollSpeed else 0

	UiState.ride = nil
	UiState.riding:set(false)
	lastLeftEggId = ride.eggId
	lastLeftAt = os.clock()

	local humanoid, root = getCharacter()
	if humanoid == nil or root == nil then
		return
	end
	root.Anchored = false
	humanoid.Sit = false

	if reason == "Dismount" then
		-- Hop forward off the egg, fast enough to reach the next one.
		root.AssemblyLinearVelocity = Vector3.new(0, 52, eggSpeed + 4)
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	elseif reason == "ThrownOff" or reason == "KnockedOff" then
		-- Tumble off to one side and lie stunned for a moment.
		stunnedUntil = os.clock() + Tuning.STUN_TIME
		local side = if root.Position.X >= 0 then 1 else -1
		humanoid.PlatformStand = true
		root.AssemblyLinearVelocity = Vector3.new(side * 16, 28, eggSpeed * 0.5)
		task.delay(Tuning.STUN_TIME, function()
			if humanoid.Parent and humanoid.Health > 0 then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	elseif reason == "Claimed" then
		root.AssemblyLinearVelocity = Vector3.new(0, 30, eggSpeed)
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

-- The player pressed jump while riding.
local function hopOff()
	if UiState.ride == nil then
		return
	end
	Net.RequestDismount:FireServer()
	-- Let go straight away rather than waiting for the server to answer; it always allows a hop off.
	release("Dismount")
end

local function onRideStarted(eggId: number, info)
	local humanoid, root = getCharacter()
	if humanoid == nil or root == nil or humanoid.Health <= 0 then
		-- No character to put on the egg; give it back.
		Net.RequestDismount:FireServer()
		return
	end

	UiState.ride = {
		eggId = eggId,
		startTime = info.startTime,
		claimTime = info.claimTime,
		drain = info.drain,
	}
	rideStartedAt = os.clock()
	awaitingJumpRelease = true
	rideHits = {}
	endedByHit = false

	-- Hold the character still; EggController places it on top of the egg every frame.
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	humanoid.PlatformStand = false
	humanoid.Sit = true

	-- From here this device steers the egg, starting from wherever it was drawn.
	EggController.SetRider(eggId, localPlayer.UserId)
	local egg = EggController.GetEgg(eggId)
	if egg then
		local about = EggModels.describe(egg.kind)
		UiState.rideTitle:set(if about then `{egg.rarity} {about.name}` else `{egg.rarity} egg`)
	else
		UiState.rideTitle:set("Egg")
	end
	UiState.claimProgress:set(0)
	UiState.riding:set(true)

	if info.combo and info.combo > 0 then
		UiState.showToast(`Hop combo x{info.combo}! +{math.floor(Tuning.HOP_COMBO_REFUND * 100)}% stamina`)
	end
end

local function onRideEnded(reason: string, info)
	if reason == "Claimed" then
		local color = if Rarities.Info[info.rarity] then rgb(Rarities.Info[info.rarity].color) else nil
		local about = EggModels.describe(info.kind)
		UiState.showToast(`CLAIMED! +1 {if about then about.name else info.rarity .. " egg"}`, color, 3)
	elseif reason == "ThrownOff" then
		UiState.showToast("Out of stamina!", OUCH_COLOR)
	elseif (reason == "KnockedOff" or reason == "Hazard") and not endedByHit then
		UiState.showToast(if reason == "Hazard" then "Ouch!" else "Knocked off!", OUCH_COLOR)
	elseif reason == "Cliff" then
		UiState.showToast("Over the edge!", Color3.fromRGB(255, 110, 110))
	end

	-- A hop off was already handled on this device when the button was pressed.
	local ride = UiState.ride
	if ride and ride.eggId == info.eggId then
		release(reason)
	end
end

-- The egg being ridden ran into an obstacle: spotted on this device (`lateral` nil: knock it clear here), or by
-- the server (`lateral`: where it knocked the egg).
local function onHit(obstacleId: number, lateral: number?)
	local ride = UiState.ride
	local obstacle = Obstacles.get(obstacleId)
	if ride == nil or obstacle == nil or rideHits[obstacleId] then
		return
	end
	rideHits[obstacleId] = true
	local egg = EggController.GetEgg(ride.eggId)
	if egg == nil then
		return
	end
	egg.lateral = lateral or Obstacles.clearLane(obstacle.row, egg.lateral, egg.spec.halfLength)
	egg.targetLateral = egg.lateral
	EggController.Wobble(egg.id)

	local kind = Obstacles.Config.Kinds[obstacle.kind]
	if obstacle.tier == "Bump" then
		local cost = NumberFormat.abbreviate(egg.spec.requirement * Tuning.BUMP_STAMINA)
		UiState.showToast(`Bumped into {kind.name}! -{cost} stamina`, BUMP_COLOR)
	elseif obstacle.tier == "KnockOff" then
		endedByHit = true
		UiState.showToast(`Knocked off by {kind.name}!`, OUCH_COLOR)
		release("KnockedOff")
	else
		-- The server ends the ride and the character.
		endedByHit = true
		UiState.showToast(kind.hitText or `Into {kind.name}!`, OUCH_COLOR)
	end
end

-- While in the air next to an egg, ask the server to put us on it.
local function lookForEgg()
	if UiState.ride ~= nil then
		return
	end
	local clock = os.clock()
	if clock < stunnedUntil or clock - lastMountRequestAt < MOUNT_REQUEST_INTERVAL then
		return
	end
	local humanoid, root = getCharacter()
	if humanoid == nil or root == nil or humanoid.Health <= 0 then
		return
	end
	local state = humanoid:GetState()
	if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then
		return
	end

	local ignore = if clock - lastLeftAt < SAME_EGG_IGNORE_TIME then lastLeftEggId else nil
	-- Riding a pet holds the player high up, so they may reach further down to an egg.
	local reach = if UiState.Fusion.peek(UiState.riddenPet) ~= "" then MOUNTED_REACH else 0
	local eggId = EggController.FindMountable(root.Position, Workspace:GetServerTimeNow(), ignore, reach)
	if eggId then
		lastMountRequestAt = clock
		Net.RequestMount:FireServer(eggId)
	end
end

-- Runs every frame before the eggs are drawn: applies steering to the egg being ridden.
local function steer(deltaTime: number)
	local ride = UiState.ride
	if ride == nil then
		return
	end
	local egg = EggController.GetEgg(ride.eggId)
	if egg == nil then
		return
	end

	local humanoid = getCharacter()
	if humanoid and not humanoid.Sit then
		-- Pressing jump stands the character up; keep it seated for as long as the ride lasts.
		humanoid.Sit = true
	end

	egg.lateral = Runway.clampLateral(egg.lateral + readSteer() * agility * deltaTime, egg.spec.halfLength)
	egg.targetLateral = egg.lateral

	-- Obstacles: report a hit straight away so the server can check it, and show it now.
	local now = Workspace:GetServerTimeNow()
	local z = EggMotion.zAt(egg.spawnTime, egg.startZ, egg.spec.rollSpeed, now)
	local hit = Obstacles.hitAt(egg.lateral, z, egg.spec.halfLength, egg.spec.radius, now, Tuning.HIT_GRAZE)
	if hit and not rideHits[hit.id] then
		Net.ReportHit:FireServer(hit.id)
		onHit(hit.id, nil)
		if UiState.ride == nil then
			return
		end
	end

	local clock = os.clock()
	if clock - lastLateralSentAt >= 1 / Tuning.LATERAL_SEND_RATE then
		lastLateralSentAt = clock
		Net.RideLateral:FireServer(egg.lateral)
	end
end

local function onCharacterAdded(character: Model)
	-- A fresh character is never riding.
	UiState.ride = nil
	UiState.riding:set(false)
	stunnedUntil = 0

	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			if UiState.ride ~= nil then
				UiState.ride = nil
				UiState.riding:set(false)
			end
			-- Let the body fall rather than hang where the egg was.
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.Anchored = false
			end
		end)
	end
end

function RideController.Init()
	Net.RideStarted.OnClientEvent:Connect(onRideStarted)
	Net.RideEnded.OnClientEvent:Connect(onRideEnded)

	Net.ObstacleHit.OnClientEvent:Connect(function(obstacleId: number, _tier: string, lateral: number)
		onHit(obstacleId, lateral)
	end)

	Net.StaminaChanged.OnClientEvent:Connect(function(value: number, time: number, rate: number, max: number)
		UiState.staminaState = { value = value, time = time, rate = rate, max = max }
		UiState.maxStamina:set(max)
		EggController.SetLocalMaxStamina(max)
	end)

	Net.Announce.OnClientEvent:Connect(function(text: string, color: { number }?)
		UiState.showToast(text, if color then rgb(color) else nil, 4)
	end)

	UserInputService.JumpRequest:Connect(function()
		local clock = os.clock()
		lastJumpRequestAt = clock
		if UiState.ride ~= nil and not awaitingJumpRelease and clock - rideStartedAt >= MIN_RIDE_BEFORE_HOP then
			hopOff()
		end
	end)

	RunService.Heartbeat:Connect(function()
		if awaitingJumpRelease and os.clock() - lastJumpRequestAt > JUMP_RELEASE_GAP then
			awaitingJumpRelease = false
		end
		lookForEgg()
	end)

	-- Before the eggs are drawn (EggController renders just before the camera).
	RunService:BindToRenderStep("RollAnEgg_Steer", Enum.RenderPriority.Input.Value + 1, steer)

	localPlayer.CharacterAdded:Connect(onCharacterAdded)
	if localPlayer.Character then
		task.spawn(onCharacterAdded, localPlayer.Character)
	end
end

function RideController.Start()
	-- The standard Roblox control scripts give us one movement reading for keyboard, touch, and gamepad.
	local ok, result = pcall(function()
		local playerScripts = localPlayer:WaitForChild("PlayerScripts")
		local playerModule = require(playerScripts:WaitForChild("PlayerModule") :: ModuleScript) :: any
		return playerModule:GetControls()
	end)
	if ok then
		controls = result
	else
		warn(`[RideController] could not load movement controls: {result}`)
	end

	-- Everything already on the runway, plus this player's own numbers.
	local gotSnapshot, snapshot = pcall(function()
		return Net.GetSnapshot:InvokeServer()
	end)
	if gotSnapshot and typeof(snapshot) == "table" then
		EggController.LoadSnapshot(snapshot.eggs)
		if snapshot.stamina then
			UiState.staminaState = snapshot.stamina
			UiState.maxStamina:set(snapshot.stamina.max)
			EggController.SetLocalMaxStamina(snapshot.stamina.max)
		end
		agility = snapshot.agility or agility
		InventoryController.Apply(snapshot.inventory)
		UiState.dollars:set(snapshot.dollars or 0)
	else
		warn(`[RideController] could not load the runway snapshot: {snapshot}`)
	end
end

return RideController
