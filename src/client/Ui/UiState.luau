-- Everything the HUD shows, as Fusion values. Controllers write to these; the HUD redraws itself when they change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))

local Load = require(script.Parent.Parent.Load)
local Settings = Load.shared("Config", "Settings")

local scope = Fusion.scoped(Fusion)

-- One value per setting, starting at its default until the saved settings arrive.
local settings = {}
for _, setting in Settings.List do
	settings[setting.key] = scope:Value(setting.default)
end

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
	-- The server event running now ("Avalanche"), or nil.
	serverEvent = scope:Value(nil :: string?),

	riding = scope:Value(false),
	rideTitle = scope:Value(""),
	claimProgress = scope:Value(0),
	-- True while the rider's stamina will run out before the claim finishes.
	rideDoomed = scope:Value(false),

	-- Which panel is open: "Shop", "Settings", or nil.
	openPanel = scope:Value(nil :: string?),
	-- A shop section to scroll to when the shop opens (the "+" buttons next to coins and stamina set this).
	shopSection = scope:Value(nil :: string?),

	-- Shop state from the server.
	penLevel = scope:Value(1),
	-- "Double your Max Stamina": 1, 2, 4 ... 1024.
	staminaMultiplier = scope:Value(1),
	-- passId -> true
	ownedPasses = scope:Value({} :: { [string]: boolean }),
	-- itemId (or "PenLevel<n>", "StaminaDoubling<n>") -> Robux price, once loaded from Roblox. Until then the shop
	-- shows Config/Shop's.
	prices = scope:Value({} :: { [string]: number }),
	-- The server luck in effect, and whole seconds until it ends (0 when none).
	luck = scope:Value(1),
	luckSeconds = scope:Value(0),

	-- settingKey -> Value. See Config/Settings.
	settings = settings,

	toastText = scope:Value(""),
	toastColor = scope:Value(Color3.new(1, 1, 1)),
	toastVisible = scope:Value(false),

	-- Plain data (not shown directly): the numbers the stamina bar is worked out from each frame.
	-- See Shared/StaminaMath.
	staminaState = { value = 100, time = 0, rate = 0, max = 100 },
	-- The local player's current ride, or nil: { eggId, startTime, claimTime, drain }
	ride = nil :: { eggId: number, startTime: number, claimTime: number, drain: number }?,
	-- The server's luck boosts (Shared/LuckBoost); the HUD works the timer out from these each frame.
	luckBoosts = {} :: { { multiplier: number, endsAt: number } },
}

-- Opens a panel, or closes it if it is already open.
function UiState.togglePanel(name: string)
	if Fusion.peek(UiState.openPanel) == name then
		UiState.openPanel:set(nil)
	else
		UiState.openPanel:set(name)
	end
end

-- Opens the shop at one section.
function UiState.openShop(section: string?)
	UiState.openPanel:set("Shop")
	-- Cleared first, so asking for the same section twice still scrolls to it.
	UiState.shopSection:set(nil)
	UiState.shopSection:set(section)
end

local toastToken = 0

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

return UiState
