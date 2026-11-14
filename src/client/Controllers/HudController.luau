-- Puts the HUD on screen and refreshes the numbers that change every frame (stamina, timers, claim progress).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local CycleClock = Load.shared("CycleClock")
local Runway = Load.shared("Runway")
local Showroom = Load.shared("Showroom")
local StaminaMath = Load.shared("StaminaMath")
local Zones = Load.shared("Config", "Zones")

local Hud = require(script.Parent.Parent.Ui.Hud)
local UiState = require(script.Parent.Parent.Ui.UiState)

local localPlayer = Players.LocalPlayer

local HudController = {}

local function update()
	local now = Workspace:GetServerTimeNow()

	-- Stamina, worked out from the last numbers the server sent.
	local state = UiState.staminaState
	local stamina = StaminaMath.current(state.value, state.time, state.rate, state.max, now)
	UiState.stamina:set(math.floor(stamina))

	-- The runway cycle comes straight from the shared clock, plus however far admins have moved it on.
	local offset = Workspace:GetAttribute(CycleClock.OFFSET_ATTRIBUTE)
	CycleClock.setOffset(if typeof(offset) == "number" then offset else 0)
	local cycle = CycleClock.getState(now)
	local event = Workspace:GetAttribute(CycleClock.EVENT_ATTRIBUTE)
	UiState.serverEvent:set(if typeof(event) == "string" then event else nil)
	UiState.cyclePhase:set(cycle.phase)
	UiState.cycleSeconds:set(math.ceil(if cycle.phase == "Closed" then cycle.untilNextCycle else cycle.untilClose))

	-- Claim progress, and whether stamina will run out first.
	local ride = UiState.ride
	if ride then
		local progress = math.clamp((now - ride.startTime) / ride.claimTime, 0, 1)
		UiState.claimProgress:set(progress)
		local timeLeft = ride.claimTime * (1 - progress)
		UiState.rideDoomed:set(StaminaMath.timeUntilEmpty(stamina, ride.drain) < timeLeft)
	else
		UiState.rideDoomed:set(false)
	end

	-- Which zone the player is in.
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local position = root.Position
		local zoneId = Runway.zoneAt(position.Z)
		if Showroom.contains(position.X, position.Z) then
			UiState.zoneName:set("Model Showroom")
		else
			UiState.zoneName:set(if zoneId then Zones.List[zoneId].name else "Hub")
		end
	end
end

function HudController.Start()
	Hud.mount(localPlayer:WaitForChild("PlayerGui"))
	RunService.RenderStepped:Connect(update)
end

return HudController
