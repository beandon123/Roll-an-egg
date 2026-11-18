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

	-- Dollars, and how many a second the pets in the pen earn.
	dollars = scope:Value(0),
	income = scope:Value(0),
	eggCount = scope:Value(0),

	stamina = scope:Value(100),
	maxStamina = scope:Value(100),

	-- "Open" | "Warning" | "Closed", and whole seconds until the next change.
	cyclePhase = scope:Value("Open"),
	cycleSeconds = scope:Value(0),

	-- Day or night (each runway cycle is one day), and whole seconds until that changes.
	isDay = scope:Value(true),
	dayNightSeconds = scope:Value(0),

	-- The server event running now ("Avalanche"), or nil.
	serverEvent = scope:Value(nil :: string?),

	riding = scope:Value(false),
	rideTitle = scope:Value(""),
	claimProgress = scope:Value(0),
	-- True once the egg being ridden is claimed (already in the inventory); the rest of the ride is for show.
	rideClaimed = scope:Value(false),

	-- While leaping onto the runway or off an egg: whole tenths of a second left to land on an egg.
	leaping = scope:Value(false),
	leapSecondsLeft = scope:Value(0),
	-- True while the rider's stamina will run out before the claim finishes.
	rideDoomed = scope:Value(false),

	-- The player's inventory (see the server's Logic/Hatchery for the shapes): eggs held, eggs hatching in their
	-- pen, hatched pets, and the pen's size.
	eggs = scope:Value({}),
	hatching = scope:Value({}),
	pets = scope:Value({}),
	penLevel = scope:Value(1),
	eggCapacity = scope:Value(2),
	petCapacity = scope:Value(10),
	-- The pet chosen to ride (its uid, "" for none), and the one being ridden right now ("" when on foot).
	mountChoice = scope:Value(""),
	riddenPet = scope:Value(""),
	-- Which panel is open on the right: "None", "Eggs" or "Pets".
	panel = scope:Value("None"),
	-- What is shown in the panel's 3D preview: { type = "Egg" | "Pet", kind = string, rarity = string } or nil.
	selected = scope:Value(nil :: any),
	-- Pets hatched since the Pets panel was last opened.
	newPets = scope:Value(0),
	-- The shared clock, refreshed a few times a second, for countdowns.
	clock = scope:Value(0),

	-- Which panel is open in the middle: "Shop" or "Settings" (the tabs on the left), a hub station's ("Trails",
	-- "Sell", "Fuse"), the training stick's upgrade panel ("Stick", from the sign beside it), or nil. Opening one closes the Eggs or Pets panel on the right, and back.
	openPanel = scope:Value(nil :: string?),
	-- A shop section to scroll to when the shop opens (the "+" buttons next to dollars and stamina set this).
	shopSection = scope:Value(nil :: string?),

	-- Shop state from the server (the pen level is above, with the inventory).
	-- "Double your Max Stamina": 1, 2, 4 ... 1024.
	staminaMultiplier = scope:Value(1),
	-- passId -> true
	ownedPasses = scope:Value({} :: { [string]: boolean }),
	-- itemId (or "PenLevel<n>", "StickLevel<n>", "StaminaDoubling<n>") -> Robux price, once loaded from Roblox. Until then the shop
	-- shows Config/Shop's.
	prices = scope:Value({} :: { [string]: number }),
	-- The server luck in effect, and whole seconds until it ends (0 when none).
	luck = scope:Value(1),
	luckSeconds = scope:Value(0),

	-- Trails from the Trails stall: owned is a set of trail ids; equipped is a trail id or "".
	trailsOwned = scope:Value({} :: { [string]: boolean }),
	trailEquipped = scope:Value(""),

	-- The training stick (Config/Sticks): the tier the player has, and, while they roll on it, the session.
	stickLevel = scope:Value(1),
	training = scope:Value(false),
	-- Max Stamina gained since they got on, and the last rep's gain (multipliers and boost included).
	trainingGained = scope:Value(0),
	trainingLastGain = scope:Value(0),
	-- The "2x" bubble on screen ({ id, endsAt, x, y }, x and y as fractions of the screen), or nil; how much of its
	-- time is left (1 to 0), and how far through popping it is once tapped (0 to 1, or 0 when not popping).
	trainingBubble = scope:Value(nil :: { id: number, endsAt: number, x: number, y: number }?),
	bubbleLeft = scope:Value(1),
	bubblePop = scope:Value(0),
	-- How much of a running 2x boost is left (1 to 0; 0 when none is running).
	boostLeft = scope:Value(0),
	-- A gentle beat (-1 to 1) the bubble and boost bar pulse with.
	pulse = scope:Value(0),

	-- settingKey -> Value. See Config/Settings.
	settings = settings,

	toastText = scope:Value(""),
	toastColor = scope:Value(Color3.new(1, 1, 1)),
	toastVisible = scope:Value(false),

	-- The big white message shown when a Secret or rarer egg spawns: a title, then where and when it spawned, and
	-- the colour of its rarity.
	announceTitle = scope:Value(""),
	announceDetail = scope:Value(""),
	announceColor = scope:Value(Color3.new(1, 1, 1)),
	announceVisible = scope:Value(false),

	-- Plain data (not shown directly): the numbers the stamina bar is worked out from each frame.
	-- See Shared/StaminaMath.
	staminaState = { value = 100, time = 0, rate = 0, max = 100 },
	-- When the current leap runs out (os.clock()), or nil when not leaping.
	leapEndsAt = nil :: number?,
	-- The local player's current ride, or nil: { eggId, startTime, claimTime, drain, claimed }
	ride = nil :: { eggId: number, startTime: number, claimTime: number, drain: number, claimed: boolean }?,

	-- What the panels' buttons do, set by InventoryController, StationController and TrainingController.
	actions = {
		stopTraining = function() end,
		claimBubble = function(_id: number) end,
		buyTrail = function(_trailId: string) end,
		equipTrail = function(_trailId: string) end,
		sellEggs = function(_kind: string, _count: number) end,
		-- Puts one of the player's eggs of a kind in their hand, ready to click a spot in their pen.
		holdEgg = function(_kind: string) end,
		openPanel = function(_panel: string) end,
		setInPen = function(_uid: string, _inPen: boolean) end,
		equipBest = function() end,
		sellPet = function(_uid: string) end,
		ridePet = function(_uid: string) end,
	},
	-- The server's luck boosts (Shared/LuckBoost); the HUD works the timer out from these each frame.
	luckBoosts = {} :: { { multiplier: number, endsAt: number } },
}

-- Opens a panel on the left, or closes it if it is already open. The Eggs or Pets panel on the right closes.
function UiState.togglePanel(name: string)
	if Fusion.peek(UiState.openPanel) == name then
		UiState.openPanel:set(nil)
	else
		UiState.openPanel:set(name)
		UiState.panel:set("None")
	end
end

-- Opens the shop at one section.
function UiState.openShop(section: string?)
	UiState.openPanel:set("Shop")
	UiState.panel:set("None")
	-- Cleared first, so asking for the same section twice still scrolls to it.
	UiState.shopSection:set(nil)
	UiState.shopSection:set(section)
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

-- Shows the rare-egg message for `seconds` (5 unless given). It sits below the toast, so everyday messages such as
-- "Hop combo" never hide it.
function UiState.showAnnouncement(title: string, detail: string, color: Color3, seconds: number?)
	announceToken += 1
	local token = announceToken
	UiState.announceTitle:set(title)
	UiState.announceDetail:set(detail)
	UiState.announceColor:set(color)
	UiState.announceVisible:set(true)
	task.delay(seconds or 5, function()
		if token == announceToken then
			UiState.announceVisible:set(false)
		end
	end)
end

return UiState
