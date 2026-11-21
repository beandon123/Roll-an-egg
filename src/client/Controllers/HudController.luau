-- Puts the HUD on screen and refreshes the numbers that change every frame (stamina, timers, claim progress), and
-- says so when the runway is about to close and when it closes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local CycleClock = Load.shared("CycleClock")
local LuckBoost = Load.shared("LuckBoost")
local StaminaMath = Load.shared("StaminaMath")
local Tuning = Load.shared("Config", "Tuning")

local Hud = require(script.Parent.Parent.Ui.Hud)
local UiState = require(script.Parent.Parent.Ui.UiState)

local localPlayer = Players.LocalPlayer

local HudController = {}

local CLOSING_COLOR = Color3.fromRGB(255, 170, 70)
-- The runway's phase last frame, to notice it changing.
local lastPhase: string? = nil

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
	-- A short message as the runway starts to close, and as it closes (there is no timer on screen).
	if cycle.phase ~= lastPhase then
		if lastPhase ~= nil and cycle.phase == "Warning" then
			UiState.showToast(`Runway closes in {math.ceil(cycle.untilClose)}s!`, CLOSING_COLOR, 3)
		elseif lastPhase ~= nil and cycle.phase == "Closed" then
			UiState.showToast(`Runway closed: eggs hatch {Tuning.HATCH_BOOST}x faster!`, CLOSING_COLOR, 4)
		end
		lastPhase = cycle.phase
	end
	local isDay, untilChange = CycleClock.dayNight(now)
	UiState.isDay:set(isDay)
	UiState.dayNightSeconds:set(math.ceil(untilChange))

	-- Server luck: the strongest running boost and the time it has left.
	local luck, luckEndsAt = LuckBoost.current(UiState.luckBoosts, now)
	UiState.luck:set(luck)
	UiState.luckSeconds:set(if luckEndsAt then math.ceil(luckEndsAt - now) else 0)

	-- Claim progress, and whether stamina will run out first.
	local ride = UiState.ride
	if ride and ride.claimed then
		-- Already in the inventory: a full meter, and nothing to run out of.
		UiState.claimProgress:set(1)
		UiState.rideDoomed:set(false)
	elseif ride then
		local progress = math.clamp((now - ride.startTime) / ride.claimTime, 0, 1)
		UiState.claimProgress:set(progress)
		local timeLeft = ride.claimTime * (1 - progress)
		UiState.rideDoomed:set(StaminaMath.timeUntilEmpty(stamina, ride.drain) < timeLeft)
	else
		UiState.rideDoomed:set(false)
	end

	-- Time left to land on an egg while leaping.
	local leapEndsAt = UiState.leapEndsAt
	if leapEndsAt then
		UiState.leapSecondsLeft:set(math.max(0, math.ceil((leapEndsAt - os.clock()) * 10) / 10))
	end

	-- The rare-egg alert's lines pop in, shine and fade out by this clock.
	if #UiState.Fusion.peek(UiState.announcements) > 0 then
		UiState.announceClock:set(os.clock())
	end
end

function HudController.Start()
	Hud.mount(localPlayer:WaitForChild("PlayerGui"))
	RunService.RenderStepped:Connect(update)
end

return HudController
