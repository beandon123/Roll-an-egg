-- Everything the HUD shows, as Fusion values. Controllers write to these; the HUD redraws itself when they change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))

local scope = Fusion.scoped(Fusion)

local UiState = {
	Fusion = Fusion,
	scope = scope,

	coins = scope:Value(0),
	eggCount = scope:Value(0),

	stamina = scope:Value(100),
	maxStamina = scope:Value(100),

	-- "Open" | "Warning" | "Closed", and whole seconds until the next change.
	cyclePhase = scope:Value("Open"),
	cycleSeconds = scope:Value(0),

	zoneName = scope:Value("Hub"),

	riding = scope:Value(false),
	rideTitle = scope:Value(""),
	claimProgress = scope:Value(0),
	-- True while the rider's stamina will run out before the claim finishes.
	rideDoomed = scope:Value(false),

	toastText = scope:Value(""),
	toastColor = scope:Value(Color3.new(1, 1, 1)),
	toastVisible = scope:Value(false),

	-- The banner shown when a Secret or rarer egg spawns: a title, then where and when it spawned.
	announceTitle = scope:Value(""),
	announceDetail = scope:Value(""),
	announceColor = scope:Value(Color3.new(1, 1, 1)),
	announceVisible = scope:Value(false),

	-- Plain data (not shown directly): the numbers the stamina bar is worked out from each frame.
	-- See Shared/StaminaMath.
	staminaState = { value = 100, time = 0, rate = 0, max = 100 },
	-- The local player's current ride, or nil: { eggId, startTime, claimTime, drain }
	ride = nil :: { eggId: number, startTime: number, claimTime: number, drain: number }?,
}

local toastToken = 0
local announceToken = 0

-- Shows a short message near the top of the screen.
function UiState.showToast(text: string, color: Color3?, seconds: number?)
	toastToken += 1
	local token = toastToken
	UiState.toastText:set(text)
	UiState.toastColor:set(color or Color3.new(1, 1, 1))
	UiState.toastVisible:set(true)
	task.delay(seconds or 2.5, function()
		if token == toastToken then
			UiState.toastVisible:set(false)
		end
	end)
end

-- Shows the rare-egg banner. It sits below the toast, so everyday messages such as "Hop combo" never hide it.
function UiState.showAnnouncement(title: string, detail: string, color: Color3, seconds: number?)
	announceToken += 1
	local token = announceToken
	UiState.announceTitle:set(title)
	UiState.announceDetail:set(detail)
	UiState.announceColor:set(color)
	UiState.announceVisible:set(true)
	task.delay(seconds or 10, function()
		if token == announceToken then
			UiState.announceVisible:set(false)
		end
	end)
end

return UiState
