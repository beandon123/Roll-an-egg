-- Everything the HUD shows, as Fusion values. Controllers write to these; the HUD redraws itself when they change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))

local scope = Fusion.scoped(Fusion)

local UiState = {
	Fusion = Fusion,
	scope = scope,

	coins = scope:Value(0),
	eggCount = scope:Value(0),
	-- Unhatched eggs grouped by kind: { { zone, rarity, count } }
	inventory = scope:Value({}),
	-- Trails from the Trails shop: owned is a set of trail ids; equipped is a trail id or "".
	trailsOwned = scope:Value({}),
	trailEquipped = scope:Value(""),

	-- Which hub station panel is open: "Trails", "Sell", "Fuse", or "" for none.
	openPanel = scope:Value(""),

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

	-- Plain data (not shown directly): the numbers the stamina bar is worked out from each frame.
	-- See Shared/StaminaMath.
	staminaState = { value = 100, time = 0, rate = 0, max = 100 },
	-- The local player's current ride, or nil: { eggId, startTime, claimTime, drain }
	ride = nil :: { eggId: number, startTime: number, claimTime: number, drain: number }?,

	-- What the panels' buttons do. ShopController fills these in; the HUD only calls them.
	actions = {
		buyTrail = function(_trailId: string) end,
		equipTrail = function(_trailId: string) end,
		sellEggs = function(_zone: number, _rarity: string, _count: number) end,
		closePanel = function() end,
	},
}

-- The player's eggs, as the server summarizes them: { { zone, rarity, count } }.
function UiState.setInventory(groups: unknown)
	if typeof(groups) ~= "table" then
		return
	end
	local list = {}
	local total = 0
	for _, group in groups :: { any } do
		if typeof(group) == "table" and typeof(group.count) == "number" then
			table.insert(list, group)
			total += group.count
		end
	end
	UiState.inventory:set(list)
	UiState.eggCount:set(total)
end

-- The player's trails, as the server sends them: a list of owned ids and the equipped id ("" for none).
function UiState.setTrails(owned: unknown, equipped: unknown)
	local set = {}
	if typeof(owned) == "table" then
		for _, id in owned :: { any } do
			if typeof(id) == "string" then
				set[id] = true
			end
		end
	end
	UiState.trailsOwned:set(set)
	UiState.trailEquipped:set(if typeof(equipped) == "string" then equipped else "")
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
