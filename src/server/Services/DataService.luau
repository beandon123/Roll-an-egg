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
