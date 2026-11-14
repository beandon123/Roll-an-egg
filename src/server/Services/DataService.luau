-- Loads and saves each player's data with ProfileStore.
--
-- ProfileStore locks a player's data to one server at a time, which is what stops items being duplicated by
-- joining two servers at once. In Studio without API access it automatically uses a throwaway in-memory store,
-- so the game still runs; nothing is saved in that case.
--
-- Rules for saved data: plain tables, numbers, strings and booleans only. Store timestamps, never running timers.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

-- Bump the store name's version only if saved data must be wiped (never after launch).
local STORE_NAME = "PlayerData_v1"

-- What a brand-new player starts with. Fields added here later are filled in for existing players on load.
local TEMPLATE = {
	SchemaVersion = 1,
	Coins = 0,
	-- upgradeId -> level bought
	Upgrades = {},
	-- Max Stamina bought in the shop, added to the base (see Config/Shop).
	MaxStaminaBonus = 0,
	-- "Double your Max Stamina" purchases: 1, 2, 4 ... up to Shop.MAX_STAMINA_MULTIPLIER.
	StaminaMultiplier = 1,
	-- Pet pen level: 1 holds 10 pets, each level adds 1 (see Config/Shop).
	PenLevel = 1,
	-- settingKey -> value (see Config/Settings). Missing keys use the default.
	Settings = {},
	-- The latest Robux purchase IDs already granted, oldest first, so a purchase is never granted twice.
	PurchaseIds = {},
	-- Unhatched eggs: { uid = string, zone = number, rarity = string, kind = string, claimedAt = number }
	-- `kind` is the egg's design name (e.g. "MossStag"). Eggs claimed before kinds existed have none; treat those
	-- as the zone's first egg of that rarity.
	Eggs = {},
	-- Hatched pets: { uid = string, kind = string, zone = number, rarity = string, variant = string,
	-- hatchedAt = number }. `kind` is the pet's design name (e.g. "MossStag"); `variant` is "Normal" for now
	-- (Golden and Rainbow come with hatching). Only the admin panel adds pets until hatching is built.
	Pets = {},
	Stats = {
		EggsClaimed = 0,
	},
}

local DataService = {}

local store
local profiles = {}
local loadedCallbacks = {}
local releasingCallbacks = {}

-- The player's saved data, or nil if it has not loaded (or they are leaving). Never keep the returned table
-- across a yield; ask again instead.
function DataService.GetData(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile.Data
	end
	return nil
end

-- Waits (up to `timeout` seconds) for a player's data to load. Returns it, or nil if they left or it timed out.
function DataService.WaitForData(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 15)
	while player.Parent == Players and os.clock() < deadline do
		local data = DataService.GetData(player)
		if data then
			return data
		end
		task.wait(0.25)
	end
	return DataService.GetData(player)
end

-- Saves a player's data now and waits until a save satisfies `isSaved(lastSavedData)`.
-- Returns false if the session ends or `timeout` seconds pass first. Used so a Robux purchase is only reported
-- to Roblox as granted once the grant is safely stored.
function DataService.SaveAndWait(player: Player, isSaved: (any) -> boolean, timeout: number?): boolean
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end
	if isSaved(profile.LastSavedData) then
		return true
	end

	local thread = coroutine.running()
	local result: boolean? = nil
	local waiting = false
	local connections = {}
	local function finish(value: boolean)
		if result ~= nil then
			return
		end
		result = value
		for _, connection in connections do
			connection:Disconnect()
		end
		if waiting then
			task.spawn(thread, value)
		end
	end
	table.insert(
		connections,
		profile.OnAfterSave:Connect(function(saved)
			if isSaved(saved) then
				finish(true)
			end
		end)
	)
	table.insert(
		connections,
		profile.OnSessionEnd:Connect(function()
			finish(false)
		end)
	)
	task.delay(timeout or 30, finish, false)
	profile:Save()
	-- A save can finish before Save() returns; only wait if it has not.
	if result ~= nil then
		return result
	end
	waiting = true
	return coroutine.yield()
end

-- Runs `callback(player, data)` once a player's data is ready. Also runs for players already loaded.
function DataService.OnLoaded(callback: (Player, any) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile.Data)
	end
end

-- Runs `callback(player)` just before a player's data is saved for the last time.
function DataService.OnReleasing(callback: (Player) -> ())
	table.insert(releasingCallbacks, callback)
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- Loading failed or another server would not let go of the data. Rejoining retries.
		player:Kick("Your data could not be loaded. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your data was opened somewhere else. Please rejoin.")
	end)

	if player.Parent ~= Players then
		-- They left while the data was loading.
		profile:EndSession()
		return
	end

	profiles[player] = profile
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile.Data)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	for _, callback in releasingCallbacks do
		-- A failing callback must never stop the save.
		local ok, err = pcall(callback, player)
		if not ok then
			warn(`[DataService] release callback failed: {err}`)
		end
	end
	profiles[player] = nil
	profile:EndSession()
end

function DataService.Init()
	store = ProfileStore.New(STORE_NAME, TEMPLATE)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
