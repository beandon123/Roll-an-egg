-- The training stick on this device (Config/Sticks; the server side is TrainingService, the stand Map/TrainingStand).
--
--     Prompts    the "Start rolling" prompt on the stand and the "Upgrade" prompt on its sign only work for the plot's
--                owner, so only the owner sees them. The sign's opens the upgrade panel (Ui/TrainingUi), which closes
--                again when they walk away.
--     Rollers    every stand someone is rolling on spins (its Roller is turned by its Root; the rest is welded on),
--                splashes water, and sparkles and glows during a 2x boost. A stand that upgrades bursts with sparkles.
--     Riders     everyone rolling on a stand runs on the spot, the same way as riders on the eggs: this tells
--                RiderAnimationController who is on a stand each frame, how hard they run (flat out during a 2x boost)
--                and how far a plank or a girder rocks them up and down as it turns.
--     "+1"       each rep floats a number up over the rider's head: the local player's from the server (exactly what
--                they got), other riders' worked out here from their stand.
--     2x         the server's bubbles appear on screen; tapping one asks the server for the boost.
--
-- Jumping, or the Stop button, gets the player off.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")
local Plots = Load.shared("Plots")
local StickModels = Load.shared("StickModels")
local Sticks = Load.shared("Config", "Sticks")

local RiderAnimationController = require(script.Parent.RiderAnimationController)
local TrainingUi = require(script.Parent.Parent.Ui.TrainingUi)
local UiState = require(script.Parent.Parent.Ui.UiState)

local peek = UiState.Fusion.peek
local localPlayer = Players.LocalPlayer

local TrainingController = {}

local STAND_NAME = "TrainingStick"
-- Seconds after getting on before a jump gets the player off (the jump that brought up the prompt is ignored).
local STOP_GRACE = 0.4
-- How quickly a roller gets up to speed and slows down again.
local SPIN_EASE = 5
-- How far from the camera (studs) stands splash and sparkle, and other riders' "+1"s show.
local FX_DISTANCE = 160
local OTHERS_POPUP_DISTANCE = 90
-- How far from their sign the player can walk before the upgrade panel closes.
local PANEL_CLOSE_DISTANCE = 26
-- "+1"s: how long each floats, how far it rises, and the most on screen at once.
local POPUP_LIFE = 0.95
local POPUP_RISE = 3.4
local MAX_POPUPS = 40
-- How long a tapped bubble takes to pop.
local POP_TIME = 0.22

local STAMINA_BLUE = Color3.fromRGB(110, 220, 255)
local BOOST_GOLD = Color3.fromRGB(255, 210, 60)
local INK = Color3.fromRGB(46, 30, 22)

type StandState = {
	angle: number,
	speed: number,
	level: number?,
	lastPopup: number,
}

type Popup = {
	gui: BillboardGui,
	label: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	offset: Vector3,
	born: number,
}

local stands: { [Model]: StandState } = {}
local popups: { Popup } = {}
local popupFolder: Folder

local training = {
	active = false,
	startedAt = 0,
	sessionStart = -1,
	stopping = false,
}
local bubblePoppedAt: number? = nil
local boostEndsAt = 0
local clock = 0
local random = Random.new()

----------------------------------------------------------------------------------------------------------------
-- "+1" popups

local function popup(character: Model, amount: number, boosted: boolean)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") or popupFolder == nil then
		return
	end
	if #popups >= MAX_POPUPS then
		local oldest = table.remove(popups, 1) :: Popup
		oldest.gui:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "TrainingPopup"
	gui.Adornee = root
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.Size = if boosted then UDim2.fromOffset(180, 66) else UDim2.fromOffset(130, 50)
	local offset = Vector3.new(random:NextNumber(-1.3, 1.3), 3.4, random:NextNumber(-0.6, 0.6))
	gui.StudsOffsetWorldSpace = offset

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Rotation = random:NextNumber(-10, 10)
	label.Font = Enum.Font.LuckiestGuy
	label.Text = (if boosted then "2x +" else "+") .. NumberFormat.amount(amount)
	label.TextColor3 = if boosted then BOOST_GOLD else STAMINA_BLUE
	label.TextScaled = true
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = if boosted then 4 else 3
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	gui.Parent = popupFolder

	table.insert(popups, { gui = gui, label = label, stroke = stroke, scale = scale, offset = offset, born = clock })
end

-- Floats each popup up: it pops in a little too big, settles, rises and fades.
local function stepPopups()
	local index = 1
	while index <= #popups do
		local entry = popups[index]
		local t = (clock - entry.born) / POPUP_LIFE
		if t >= 1 or entry.gui.Adornee == nil or entry.gui.Adornee.Parent == nil then
			entry.gui:Destroy()
			table.remove(popups, index)
		else
			local rise = POPUP_RISE * (1 - (1 - t) ^ 2)
			entry.gui.StudsOffsetWorldSpace = entry.offset + Vector3.new(0, rise, 0)
			local size
			if t < 0.12 then
				size = 0.3 + 0.95 * (t / 0.12)
			elseif t < 0.25 then
				size = 1.25 - 0.25 * ((t - 0.12) / 0.13)
			else
				size = 1
			end
			entry.scale.Scale = size
			local fade = math.clamp((t - 0.65) / 0.35, 0, 1)
			entry.label.TextTransparency = fade
			entry.stroke.Transparency = fade
			index += 1
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Stands

local function setEnabled(parent: Instance?, childName: string, className: string, on: boolean)
	local child = parent and parent:FindFirstChild(childName)
	if child and child:IsA(className) then
		(child :: any).Enabled = on
	end
end

-- Only the plot's owner can use the stand's prompts, so only they see them.
local function showPrompts(plot: Instance, stand: Instance)
	local mine = plot:GetAttribute("Owner") == localPlayer.UserId
	local seat = stand:FindFirstChild("Seat")
	setEnabled(seat, "Train", "ProximityPrompt", mine and not training.active)
	local sign = stand:FindFirstChild("Sign")
	setEnabled(sign and sign:FindFirstChild("Board"), "Upgrade", "ProximityPrompt", mine)
end

local function burst(stand: Instance)
	local boost = stand:FindFirstChild("BoostFx")
	local sparkles = boost and boost:FindFirstChild("Sparkles")
	if sparkles and sparkles:IsA("ParticleEmitter") then
		sparkles:Emit(90)
	end
	local splash = stand:FindFirstChild("SplashFx")
	local drops = splash and splash:FindFirstChild("Splash")
	if drops and drops:IsA("ParticleEmitter") then
		drops:Emit(40)
	end
end

local function stepStand(plot: Instance, stand: Model, deltaTime: number, now: number, eye: Vector3?)
	local index = plot:GetAttribute("Index")
	if typeof(index) ~= "number" then
		return
	end
	local state = stands[stand]
	if state == nil then
		state = { angle = 0, speed = 0, level = nil, lastPopup = 0 }
		stands[stand] = state
	end
	showPrompts(plot, stand)

	local level = stand:GetAttribute("Level")
	level = if typeof(level) == "number" then level else 1
	if state.level and level > state.level then
		burst(stand)
	end
	state.level = level

	local riderId = stand:GetAttribute("Rider")
	local rider = if typeof(riderId) == "number" and riderId ~= 0 then Players:GetPlayerByUserId(riderId) else nil
	local boostUntil = stand:GetAttribute("BoostUntil")
	local boosted = rider ~= nil and typeof(boostUntil) == "number" and boostUntil > now

	-- The roller: up to speed while someone rolls, faster in a boost; slowing to a stop when they get off.
	local tier = Sticks.tier(level)
	local target = if rider then tier.spin * 2 * math.pi * (if boosted then Sticks.BOOST_SPIN else 1) else 0
	state.speed += (target - state.speed) * math.min(1, deltaTime * SPIN_EASE)
	if math.abs(state.speed) < 0.01 and target == 0 then
		state.speed = 0
	end
	state.angle = (state.angle + state.speed * deltaTime) % (2 * math.pi)
	local roller = stand:FindFirstChild("Roller")
	local root = roller and (roller :: Model).PrimaryPart
	if roller and root and state.speed ~= 0 then
		local rollerLevel = roller:GetAttribute("Level")
		root.CFrame = StickModels.axleCFrame(index, if typeof(rollerLevel) == "number" then rollerLevel else level)
			* StickModels.spin(state.angle)
	end

	local distance = if eye then (StickModels.standCFrame(index).Position - eye).Magnitude else 0
	local near = distance < FX_DISTANCE
	setEnabled(stand:FindFirstChild("SplashFx"), "Splash", "ParticleEmitter", near and rider ~= nil)
	local boost = stand:FindFirstChild("BoostFx")
	setEnabled(boost, "Sparkles", "ParticleEmitter", near and boosted)
	setEnabled(boost, "BoostLight", "PointLight", boosted)

	-- The rainbow crystal's core shifts through the rainbow.
	if roller and level == Sticks.MAX_LEVEL and near then
		local color = Color3.fromHSV((clock * 0.15) % 1, 0.45, 1)
		for _, part in roller:GetDescendants() do
			if part:IsA("BasePart") and part:GetAttribute("Rainbow") then
				part.Color = color
			end
		end
	end

	local character = rider and rider.Character
	if rider and character then
		-- Running on the roller (sprinting in a boost), rocked down as a plank or a girder turns.
		RiderAnimationController.SetStickRider(
			rider.UserId,
			if boosted then Sticks.BOOST_RUN_PACE else Sticks.RUN_PACE,
			Sticks.topHeight(level, state.angle) - Sticks.maxTop(level)
		)
		-- Other riders' "+1"s (the local player's come from the server).
		if
			rider ~= localPlayer
			and distance < OTHERS_POPUP_DISTANCE
			and clock - state.lastPopup >= Sticks.REP_INTERVAL
		then
			state.lastPopup = clock
			local gain = stand:GetAttribute("RepGain")
			if typeof(gain) == "number" and gain > 0 then
				popup(character, if boosted then gain * Sticks.BOOST_MULTIPLIER else gain, boosted)
			end
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- The local player's session

local function clearBubble()
	UiState.trainingBubble:set(nil)
	UiState.bubblePop:set(0)
	UiState.bubbleLeft:set(1)
	bubblePoppedAt = nil
end

local function stopTraining()
	if training.active and not training.stopping then
		training.stopping = true
		Net.StopTraining:FireServer()
	end
end

local function claimBubble(id: number)
	local bubble = peek(UiState.trainingBubble)
	if bubble == nil or bubble.id ~= id or bubble.popped then
		return
	end
	Net.ClaimTrainingBoost:FireServer(id)
	UiState.trainingBubble:set({ id = bubble.id, endsAt = bubble.endsAt, x = bubble.x, y = bubble.y, popped = true })
	bubblePoppedAt = clock
end

local function onStarted(info)
	if typeof(info) ~= "table" then
		return
	end
	if info.startedAt ~= training.sessionStart then
		-- A new session (not the same one after an upgrade).
		training.sessionStart = info.startedAt
		training.startedAt = os.clock()
		UiState.trainingGained:set(0)
		clearBubble()
		boostEndsAt = 0
	end
	training.active = true
	training.stopping = false
	if typeof(info.level) == "number" then
		UiState.stickLevel:set(info.level)
	end
	UiState.training:set(true)
end

local function onEnded()
	training.active = false
	training.stopping = false
	training.sessionStart = -1
	UiState.training:set(false)
	UiState.boostLeft:set(0)
	boostEndsAt = 0
	clearBubble()
end

local function onRep(gain: unknown, boosted: unknown)
	if typeof(gain) ~= "number" then
		return
	end
	UiState.trainingGained:set(peek(UiState.trainingGained) + gain)
	UiState.trainingLastGain:set(gain)
	local character = localPlayer.Character
	if character then
		popup(character, gain, boosted == true)
	end
end

-- A bubble goes up somewhere round the middle of the screen, never right over the player.
local function onBubble(id: unknown, endsAt: unknown)
	if typeof(id) ~= "number" or typeof(endsAt) ~= "number" or not training.active then
		return
	end
	local angle = random:NextNumber(0, math.pi * 2)
	local reach = random:NextNumber(0.85, 1)
	bubblePoppedAt = nil
	UiState.bubblePop:set(0)
	UiState.trainingBubble:set({
		id = id,
		endsAt = endsAt,
		x = 0.5 + math.cos(angle) * 0.21 * reach,
		y = 0.44 + math.sin(angle) * 0.19 * reach,
	})
end

local function onBoost(endsAt: unknown)
	if typeof(endsAt) ~= "number" then
		return
	end
	boostEndsAt = endsAt
	UiState.showToast("2x STAMINA!", BOOST_GOLD, Sticks.BOOST_DURATION)
end

-- The bubble's countdown, its pop once tapped, the boost bar, and the beat they pulse to.
local function stepSession(now: number)
	if not training.active then
		return
	end
	UiState.pulse:set(math.sin(clock * 9))
	UiState.boostLeft:set(math.clamp((boostEndsAt - now) / Sticks.BOOST_DURATION, 0, 1))
	local bubble = peek(UiState.trainingBubble)
	if bubble == nil then
		return
	end
	if bubblePoppedAt then
		local progress = (clock - bubblePoppedAt) / POP_TIME
		if progress >= 1 then
			clearBubble()
		else
			UiState.bubblePop:set(progress)
		end
	elseif now > bubble.endsAt then
		clearBubble()
	else
		UiState.bubbleLeft:set(math.clamp((bubble.endsAt - now) / Sticks.BUBBLE_LIFETIME, 0, 1))
	end
end

----------------------------------------------------------------------------------------------------------------
-- The upgrade panel

local function myPlot(): number?
	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("Owner") == localPlayer.UserId then
			local index = plot:GetAttribute("Index")
			return if typeof(index) == "number" then index else nil
		end
	end
	return nil
end

local function onPromptTriggered(prompt: ProximityPrompt)
	if prompt:GetAttribute("StickSign") then
		UiState.openPanel:set("Stick")
		UiState.panel:set("None")
	end
end

-- Closes the upgrade panel once the player walks away from their sign.
local function closeWhenFar()
	if peek(UiState.openPanel) ~= "Stick" then
		return
	end
	local index = myPlot()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if index == nil or root == nil or not root:IsA("BasePart") then
		UiState.openPanel:set(nil)
		return
	end
	local x, z = Plots.point(index, Plots.STICK_SIGN_SPOT[1], Plots.STICK_SIGN_SPOT[2])
	local position = root.CFrame.Position
	if (position.X - x) ^ 2 + (position.Z - z) ^ 2 > PANEL_CLOSE_DISTANCE ^ 2 then
		UiState.openPanel:set(nil)
	end
end

----------------------------------------------------------------------------------------------------------------

local function render(deltaTime: number)
	clock += deltaTime
	local now = Workspace:GetServerTimeNow()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil

	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			local stand = plot:FindFirstChild(STAND_NAME)
			if stand and stand:IsA("Model") then
				stepStand(plot, stand, deltaTime, now, eye)
			end
		end
	end
	for stand in stands do
		if stand.Parent == nil then
			stands[stand] = nil
		end
	end

	stepPopups()
	stepSession(now)
	TrainingUi.step(deltaTime, clock)
end

function TrainingController.Init()
	UiState.actions.stopTraining = stopTraining
	UiState.actions.claimBubble = claimBubble

	popupFolder = Instance.new("Folder")
	popupFolder.Name = "TrainingPopups"

	Net.TrainingStarted.OnClientEvent:Connect(onStarted)
	Net.TrainingEnded.OnClientEvent:Connect(onEnded)
	Net.TrainingRep.OnClientEvent:Connect(onRep)
	Net.TrainingBubble.OnClientEvent:Connect(onBubble)
	Net.TrainingBoost.OnClientEvent:Connect(onBoost)

	UserInputService.JumpRequest:Connect(function()
		if training.active and os.clock() - training.startedAt >= STOP_GRACE then
			stopTraining()
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	RunService.Heartbeat:Connect(closeWhenFar)
	localPlayer.CharacterAdded:Connect(function()
		-- A new character is never on the stick.
		if training.active then
			onEnded()
		end
	end)
end

function TrainingController.Start()
	popupFolder.Parent = localPlayer:WaitForChild("PlayerGui")
	RunService.RenderStepped:Connect(render)
end

return TrainingController
