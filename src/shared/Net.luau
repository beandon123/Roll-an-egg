-- Every remote in the game, in one place. The server creates them; clients wait for them.
--
-- Rule for server handlers: never trust what a client sends. Check the type and range of every argument, and
-- never accept dollars, rarities, or times from a client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Reliable, ordered messages.
local EVENTS = {
	-- Server -> everyone
	"EggSpawned", -- (egg)
	"EggRemoved", -- (eggId, reason, byUserId?)
	"EggMounted", -- (eggId, userId, time)
	"EggLeft", -- (eggId, time, bouncesLeft, lateral)
	"Announce", -- (text, colorRgb?)
	"LuckChanged", -- (boosts): see LuckBoost
	-- Server -> one player
	"RideStarted", -- (eggId, { startTime, startStamina, drain, claimTime, combo })
	"RideEnded", -- (reason, { eggId, zone, rarity, kind })
	"StaminaChanged", -- (value, time, rate, max): see StaminaMath
	"ObstacleHit", -- (obstacleId, tier, lateral): the rider's egg hit an obstacle (Shared/Obstacles)
	"InventoryChanged", -- ({ eggs, hatching, pets, penLevel, ... }): see Logic/Hatchery's state()
	"PetHatched", -- (pet): one of the player's eggs has hatched
	"DollarsChanged", -- (dollars, incomePerSecond)
	"Notice", -- (text, colorRgb?): a message for this player alone
	"MountChanged", -- (petUid or "", speed): the pet the player is riding now, if any
	"PlayerStateUpdated", -- ({ dollars, penLevel, passes }): sent whenever any of them changes
	"PurchaseResult", -- (itemId, ok, message)
	"TrailsUpdated", -- (ownedTrailIds, equippedTrailId): "" when none is equipped
	-- Player -> server
	"RequestMount", -- (eggId)
	"RequestDismount", -- ()
	"ReportHit", -- (obstacleId): the rider's device saw their egg hit an obstacle
	"PlaceEgg", -- (eggUid): put an egg from the inventory down where the player stands in their pen
	"SetInPen", -- (petUid, inPen): put a pet in the pen or take it out
	"EquipBest", -- (): fill the pen with the player's best pets
	"SellPet", -- (petUid)
	"RidePet", -- (petUid or ""): ride a pet, or get off
	"RequestPurchase", -- (itemId) a Robux item from Config/Shop; the server shows Roblox's purchase prompt
	"BuyWithDollars", -- (itemId) an item with a dollar price
	"SaveSettings", -- ({ [key]: value }) see Config/Settings
}

-- Frequent messages where a lost one does not matter, because a newer one follows.
local UNRELIABLE_EVENTS = {
	"RideLateral", -- player -> server (x): where the rider has steered their egg
	"EggLateral", -- server -> everyone (eggId, x)
}

local FUNCTIONS = {
	"GetSnapshot", -- player -> server: () -> { eggs, inventory, ... }
	"GetShopState", -- player -> server: () -> { dollars, penLevel, passes, luck }
	"GetSettings", -- player -> server: () -> { [key]: value }
	"AdminCommand", -- player -> server: (command, args) -> (ok, message, data?); admins only (see AdminService)
	"GetTrails", -- player -> server: () -> { owned, equipped }
	"BuyTrail", -- player -> server: (trailId) -> (ok, result): see Logic/Stalls' TrailResult
	"EquipTrail", -- player -> server: (trailId) -> (ok, result)
	"SellEggs", -- player -> server: (eggKind, count) -> (sold, dollars)
}

local Net = {}

local isServer = RunService:IsServer()
local folder: Instance

if isServer then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local function get(name: string, className: string): Instance
	if isServer then
		local remote = folder:FindFirstChild(name)
		if remote == nil then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		return remote
	end
	return folder:WaitForChild(name)
end

for _, name in EVENTS do
	Net[name] = get(name, "RemoteEvent")
end
for _, name in UNRELIABLE_EVENTS do
	Net[name] = get(name, "UnreliableRemoteEvent")
end
for _, name in FUNCTIONS do
	Net[name] = get(name, "RemoteFunction")
end

if isServer then
	-- Parented last, so a client that finds the folder finds every remote inside it.
	folder.Parent = ReplicatedStorage
end

return Net
