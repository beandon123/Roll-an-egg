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

	-- The player's inventory (see the server's Logic/Hatchery for the shapes): eggs held, eggs hatching in their
	-- nests, hatched pets, and how many nests they have.
	eggs = scope:Value({}),
	nests = scope:Value({}),
	pets = scope:Value({}),
	nestCount = scope:Value(2),
	-- Which panel is open on the right: "None", "Eggs" or "Pets".
	panel = scope:Value("None"),
	-- What is shown in the panel's 3D preview: { type = "Egg" | "Pet", kind = string, rarity = string } or nil.
	selected = scope:Value(nil :: any),
	-- Pets hatched since the Pets panel was last opened.
	newPets = scope:Value(0),
	-- The shared clock, refreshed a few times a second, for countdowns.
	clock = scope:Value(0),

	toastText = scope:Value(""),
	toastColor = scope:Value(Color3.new(1, 1, 1)),
	toastVisible = scope:Value(false),

	-- Plain data (not shown directly): the numbers the stamina bar is worked out from each frame.
	-- See Shared/StaminaMath.
	staminaState = { value = 100, time = 0, rate = 0, max = 100 },
	-- The local player's current ride, or nil: { eggId, startTime, claimTime, drain }
	ride = nil :: { eggId: number, startTime: number, claimTime: number, drain: number }?,

	-- What the panels' buttons do, set by InventoryController.
	actions = {
		placeEgg = function(_uid: string) end,
		openPanel = function(_panel: string) end,
	},
}

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
