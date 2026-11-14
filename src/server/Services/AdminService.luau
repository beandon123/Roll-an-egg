-- The admin panel's server side: every command the panel can send, each checked here.
--
-- Who is an admin: everyone while testing in Studio; in a live game, the experience's owner and anyone listed in
-- Config/Admins. Admins get the Player attribute IsAdmin, which shows them the panel (Client/Ui/AdminPanel). Every
-- command checks again here, so a client that fakes the panel gets nothing.
--
-- Commands arrive through Net.AdminCommand as (command, args) and answer (ok, message, data?). `args` is a table
-- of plain values; each command checks the ones it reads.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AdminTools = require(Shared.Config.AdminTools)
local EggModels = require(Shared.EggModels)
local EggSpec = require(Shared.EggSpec)
local Net = require(Shared.Net)
local PetModels = require(Shared.PetModels)
local PetRig = require(Shared.PetRig)
local Rarities = require(Shared.Config.Rarities)
local Runway = require(Shared.Runway)
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)

local Admins = require(script.Parent.Parent.Config.Admins)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local RunwayService = require(script.Parent.RunwayService)
local ShowroomService = require(script.Parent.ShowroomService)
local TeleportService = require(script.Parent.TeleportService)

-- Most commands one player may send in RATE_WINDOW seconds.
local RATE_LIMIT = 20
local RATE_WINDOW = 1
-- An egg dropped "here" lands this many studs ahead of the player, then rolls on down the runway.
local DROP_AHEAD = 10
-- Seconds between eggs when dropping all of a zone's eggs, so they spread out down the runway.
local EACH_EGG_GAP = 0.8
-- How high a character's HumanoidRootPart is above its feet.
local ROOT_HEIGHT = 3
-- Where "Show this zone's pets" stands them: two rows of four in front of the player, in studs.
local PET_COLUMNS = { -18, -6, 6, 18 }
local PET_ROWS = { 18, 32 }

local AdminService = {}

type Args = { [string]: any }

local admins: { [Player]: boolean } = {}
local recentCommands: { [Player]: { number } } = {}
local petFolder: Folder

----------------------------------------------------------------------------------------------------------------
-- Who is an admin

local function checkAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(Admins.UserIds, player.UserId) then
		return true
	end
	-- Who owns the experience. Reading these can fail outside a published game, which just means "not the owner".
	local ok, creatorType, creatorId = pcall(function()
		return game.CreatorType, game.CreatorId
	end)
	if not ok then
		return false
	end
	if creatorType == Enum.CreatorType.User then
		return player.UserId == creatorId
	elseif creatorType == Enum.CreatorType.Group then
		local gotRank, rank = pcall(function()
			return player:GetRankInGroup(creatorId)
		end)
		return gotRank and rank >= Admins.GROUP_RANK
	end
	return false
end

-- Whether a player is an admin (once the check made when they joined has finished).
function AdminService.IsAdmin(player: Player): boolean
	return admins[player] == true
end

----------------------------------------------------------------------------------------------------------------
-- Helpers

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- The way the player faces, level, and the point under their feet.
local function standing(root: BasePart): (Vector3, Vector3)
	local look = root.CFrame.LookVector
	local level = Vector3.new(look.X, 0, look.Z)
	level = if level.Magnitude > 1e-3 then level.Unit else Vector3.new(0, 0, 1)
	return level, root.Position - Vector3.new(0, ROOT_HEIGHT, 0)
end

local function isString(value: any): boolean
	return typeof(value) == "string" and #value <= 100
end

local function isWhole(value: any, low: number, high: number): boolean
	return typeof(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

local function eggName(kind: string): string
	local about = EggModels.describe(kind)
	return if about then about.name else kind
end

local function petName(kind: string): string
	local about = PetModels.describe(kind)
	return if about then about.name else kind
end

-- Where a pet hatches from: its zone and rarity, or nil if no egg in any zone hatches it.
local function petPlace(kind: string): (number?, string?)
	for zoneId, zone in Zones.List do
		for _, entry in zone.eggs do
			if entry.pet == kind then
				return zoneId, entry.rarity
			end
		end
	end
	return nil, nil
end

-- Where to drop an egg "here": ahead of the player on the runway, or nil if they are not on it.
local function placementAhead(player: Player): { z: number, lateral: number }?
	local root = getRoot(player)
	if root == nil then
		return nil
	end
	local position = root.Position
	local z = position.Z + DROP_AHEAD
	if Runway.zoneAt(position.Z) == nil or Runway.zoneAt(z) == nil then
		return nil
	end
	return { z = z, lateral = position.X }
end

-- Drops eggs at the chute or "here". Returns the placement used, and a note to add if "here" was not possible.
local function dropPlacement(player: Player, where: any): ({ z: number, lateral: number }?, string)
	if where ~= "Here" then
		return nil, ""
	end
	local placement = placementAhead(player)
	if placement == nil then
		return nil, " You're not on the runway, so it dropped at its zone's chute."
	end
	return placement, ""
end

----------------------------------------------------------------------------------------------------------------
-- Inventory

-- Each of a player's eggs or pets, counted by kind, in runway order: { kind, name, zone, rarity, count }.
local function summarize(list: { any }, isPet: boolean): { any }
	local byKind = {}
	local order = {}
	for _, item in list do
		local kind = if typeof(item.kind) == "string" then item.kind else nil
		if kind == nil and not isPet then
			-- Eggs claimed before eggs had kinds count as the zone's first egg of their rarity.
			kind = EggSpec.pickEgg(item.zone, item.rarity, 0)
		end
		local key = kind or `{item.zone}:{item.rarity}`
		local entry = byKind[key]
		if entry == nil then
			entry = {
				kind = key,
				name = if kind == nil then `{item.rarity} egg` elseif isPet then petName(kind) else eggName(kind),
				zone = item.zone or 0,
				rarity = item.rarity or "Common",
				count = 0,
			}
			byKind[key] = entry
			table.insert(order, entry)
		end
		entry.count += 1
	end
	table.sort(order, function(a, b)
		if a.zone ~= b.zone then
			return a.zone < b.zone
		end
		local aOrder = Rarities.Info[a.rarity] and Rarities.Info[a.rarity].order or 0
		local bOrder = Rarities.Info[b.rarity] and Rarities.Info[b.rarity].order or 0
		if aOrder ~= bOrder then
			return aOrder < bOrder
		end
		return a.name < b.name
	end)
	return order
end

local function inventoryOf(data): any
	return {
		eggs = summarize(data.Eggs, false),
		pets = summarize(data.Pets, true),
		eggCount = #data.Eggs,
		petCount = #data.Pets,
	}
end

----------------------------------------------------------------------------------------------------------------
-- Pets in the world

local function trimSpawnedPets()
	local pets = {}
	for _, child in petFolder:GetChildren() do
		if child:IsA("Model") then
			table.insert(pets, child)
		end
	end
	for index = 1, #pets - AdminTools.MAX_SPAWNED_PETS do
		pets[index]:Destroy()
	end
end

-- Stands a pet at `spot` (on the ground there), facing `towards`.
local function standPet(pet: Model, spot: Vector3, towards: Vector3)
	local position = spot + Vector3.new(0, pet:GetAttribute("GroundOffset") or 0, 0)
	local target = Vector3.new(towards.X, position.Y, towards.Z)
	if (target - position).Magnitude < 1e-3 then
		target = position + Vector3.new(0, 0, -1)
	end
	-- Pets face their -Z, which is the way CFrame.lookAt points.
	pet:PivotTo(CFrame.lookAt(position, target))
end

----------------------------------------------------------------------------------------------------------------
-- Commands

local commands: { [string]: (Player, Args) -> (boolean, string, any?) } = {}

-- Eggs on the runway

commands.DropEgg = function(player, args)
	local kind = args.egg
	local zoneId = if isString(kind) then EggSpec.placeOf(kind) else nil
	if zoneId == nil then
		return false, "That egg is not in any zone."
	end
	local placement, note = dropPlacement(player, args.where)
	if not RunwayService.DropEgg(zoneId, nil, kind, placement) then
		return false, `Could not drop a {eggName(kind)}.`
	end
	return true, `Dropped a {eggName(kind)}.{note}`
end

commands.DropRandomEgg = function(player, args)
	if not isWhole(args.zone, 1, #Zones.List) then
		return false, "Pick a zone."
	end
	local placement, note = dropPlacement(player, args.where)
	RunwayService.DropEgg(args.zone, nil, nil, placement)
	return true, `Dropped a random {Zones.List[args.zone].name} egg.{note}`
end

commands.DropZoneEggs = function(player, args)
	if not isWhole(args.zone, 1, #Zones.List) then
		return false, "Pick a zone."
	end
	local zone = Zones.List[args.zone]
	local placement, note = dropPlacement(player, args.where)
	for index, entry in zone.eggs do
		task.delay((index - 1) * EACH_EGG_GAP, function()
			RunwayService.DropEgg(zone.id, nil, entry.egg, placement)
		end)
	end
	return true, `Dropping all {#zone.eggs} {zone.name} eggs.{note}`
end

commands.ClearRunway = function()
	local count = RunwayService.ClearEggs()
	return true, `Cleared {count} egg{if count == 1 then "" else "s"} nobody was riding.`
end

-- Inventory

commands.GiveEgg = function(player, args)
	local kind = args.egg
	local zoneId, rarity = nil, nil
	if isString(kind) then
		zoneId, rarity = EggSpec.placeOf(kind)
	end
	if zoneId == nil or rarity == nil then
		return false, "That egg is not in any zone."
	end
	local count = if isWhole(args.count, 1, AdminTools.MAX_GIVE) then args.count else 1
	local data = DataService.GetData(player)
	if data == nil then
		return false, "Your data has not loaded yet."
	end
	count = math.min(count, AdminTools.MAX_INVENTORY - #data.Eggs)
	if count <= 0 then
		return false, `Your inventory already holds {AdminTools.MAX_INVENTORY} eggs. Clear some first.`
	end
	for _ = 1, count do
		table.insert(data.Eggs, {
			uid = HttpService:GenerateGUID(false),
			zone = zoneId,
			rarity = rarity,
			kind = kind,
			claimedAt = os.time(),
		})
	end
	Net.InventoryUpdated:FireClient(player, #data.Eggs)
	return true, `Gave you {count} {eggName(kind)}{if count == 1 then "" else "s"}.`, inventoryOf(data)
end

commands.GivePet = function(player, args)
	local kind = args.pet
	local zoneId, rarity = nil, nil
	if isString(kind) and PetModels.describe(kind) then
		zoneId, rarity = petPlace(kind)
	end
	if zoneId == nil or rarity == nil then
		return false, "That pet does not hatch from any egg."
	end
	local count = if isWhole(args.count, 1, AdminTools.MAX_GIVE) then args.count else 1
	local data = DataService.GetData(player)
	if data == nil then
		return false, "Your data has not loaded yet."
	end
	count = math.min(count, AdminTools.MAX_INVENTORY - #data.Pets)
	if count <= 0 then
		return false, `Your inventory already holds {AdminTools.MAX_INVENTORY} pets. Clear some first.`
	end
	for _ = 1, count do
		table.insert(data.Pets, {
			uid = HttpService:GenerateGUID(false),
			kind = kind,
			zone = zoneId,
			rarity = rarity,
			variant = "Normal",
			hatchedAt = os.time(),
		})
	end
	return true, `Gave you {count} {petName(kind)}{if count == 1 then "" else "s"}.`, inventoryOf(data)
end

commands.ClearInventory = function(player, args)
	local data = DataService.GetData(player)
	if data == nil then
		return false, "Your data has not loaded yet."
	end
	if args.what == "Eggs" then
		table.clear(data.Eggs)
		Net.InventoryUpdated:FireClient(player, 0)
		return true, "Cleared your eggs.", inventoryOf(data)
	elseif args.what == "Pets" then
		table.clear(data.Pets)
		return true, "Cleared your pets.", inventoryOf(data)
	end
	return false, "Clear eggs or pets?"
end

commands.GetInventory = function(player)
	local data = DataService.GetData(player)
	if data == nil then
		return false, "Your data has not loaded yet."
	end
	return true, "", inventoryOf(data)
end

-- Pets in the world

commands.SpawnPet = function(player, args)
	local kind = args.pet
	local root = getRoot(player)
	if root == nil then
		return false, "You need a character to spawn a pet next to."
	end
	local pet = if isString(kind) and PetModels.describe(kind) then PetRig.build(kind) else nil
	if pet == nil then
		return false, "That pet has no model."
	end
	local facing, feet = standing(root)
	local size = (pet.PrimaryPart :: BasePart).Size
	local spot = feet + facing * (6 + math.max(size.X, size.Z) / 2)
	standPet(pet, spot, feet)
	pet.Parent = petFolder
	trimSpawnedPets()
	return true, `Spawned a {petName(kind)}.`
end

commands.ShowZonePets = function(player, args)
	if not isWhole(args.zone, 1, #Zones.List) then
		return false, "Pick a zone."
	end
	local root = getRoot(player)
	if root == nil then
		return false, "You need a character to stand them in front of."
	end
	local old = petFolder:FindFirstChild("ZonePets")
	if old then
		old:Destroy()
	end
	local group = Instance.new("Folder")
	group.Name = "ZonePets"

	local zone = Zones.List[args.zone]
	local facing, feet = standing(root)
	local right = facing:Cross(Vector3.new(0, 1, 0))
	local slot = 0
	for _, entry in zone.eggs do
		local pet = PetRig.build(entry.pet)
		if pet then
			slot += 1
			local column = PET_COLUMNS[(slot - 1) % #PET_COLUMNS + 1]
			local row = PET_ROWS[(slot - 1) // #PET_COLUMNS + 1] or PET_ROWS[#PET_ROWS]
			standPet(pet, feet + right * column + facing * row, feet)
			pet.Parent = group
		end
	end
	group.Parent = petFolder
	return true, `Showing the {zone.name} pets. Remove them from the Pets tab.`
end

commands.ClearPets = function()
	local count = 0
	for _, child in petFolder:GetDescendants() do
		if child:IsA("Model") and child.Parent and child:FindFirstChild("Root") then
			count += 1
		end
	end
	petFolder:ClearAllChildren()
	return true, `Removed {count} spawned pet{if count == 1 then "" else "s"}.`
end

-- Moving around

commands.SetFlying = function(player, args)
	local on = args.on == true
	player:SetAttribute(AdminTools.FLYING, on)
	return true, if on then "Flying. Move to fly where the camera looks; Space/E up, Q/Ctrl down." else "Landed."
end

commands.SetFlySpeed = function(player, args)
	if not table.find(AdminTools.FLY_SPEEDS, args.speed) then
		return false, "Pick one of the fly speeds."
	end
	player:SetAttribute(AdminTools.FLY_SPEED, args.speed)
	return true, `Fly speed {args.speed}.`
end

local function applyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local speed = player:GetAttribute(AdminTools.WALK_SPEED)
	if humanoid and typeof(speed) == "number" then
		humanoid.WalkSpeed = speed
	end
end

commands.SetWalkSpeed = function(player, args)
	if not table.find(AdminTools.WALK_SPEEDS, args.speed) then
		return false, "Pick one of the walk speeds."
	end
	player:SetAttribute(AdminTools.WALK_SPEED, args.speed)
	applyWalkSpeed(player)
	return true, `Walk speed {args.speed}.`
end

commands.Stamina = function(player, args)
	local action = args.action
	if action == "Times5" then
		local max = math.min(AdminTools.MAX_STAMINA, RunwayService.GetMaxStamina(player) * 5)
		RunwayService.SetMaxStamina(player, max)
		return true, `Max Stamina is now {max}.`
	elseif action == "Max" then
		RunwayService.SetMaxStamina(player, AdminTools.MAX_STAMINA)
		RunwayService.RefillStamina(player)
		return true, `Max Stamina is now {AdminTools.MAX_STAMINA}, and full.`
	elseif action == "Refill" then
		RunwayService.RefillStamina(player)
		return true, "Stamina refilled."
	elseif action == "Reset" then
		RunwayService.SetMaxStamina(player, Tuning.BASE_MAX_STAMINA)
		return true, `Max Stamina is back to {Tuning.BASE_MAX_STAMINA}.`
	end
	return false, "Unknown stamina action."
end

commands.Teleport = function(player, args)
	local ok: boolean
	local where: string
	if args.to == "Hub" then
		ok, where = TeleportService.ToHub(player), "the hub"
	elseif args.to == "Cliff" then
		ok, where = TeleportService.ToCliff(player), "the end cliff"
	elseif args.to == "Showroom" then
		ShowroomService.Prepare()
		local feet, facing = ShowroomService.GetArrival()
		ok, where = TeleportService.To(player, feet, facing), "the Model Showroom"
		if ok and not ShowroomService.IsReady() then
			where ..= " (models are being built from code; they appear over a few seconds)"
		end
	elseif args.to == "Zone" and isWhole(args.zone, 1, #Zones.List) then
		ok, where = TeleportService.ToZone(player, args.zone), `the {Zones.List[args.zone].name}`
	else
		return false, "Teleport where?"
	end
	if not ok then
		return false, "You need a character to teleport."
	end
	return true, `Teleported to {where}.`
end

commands.TeleportToPlayer = function(player, args)
	local target = if typeof(args.userId) == "number" then Players:GetPlayerByUserId(args.userId) else nil
	if target == nil then
		return false, "That player is not in this server."
	end
	if not TeleportService.ToPlayer(player, target) then
		return false, `Could not reach {target.Name}.`
	end
	return true, `Teleported to {target.Name}.`
end

-- Events and the runway cycle

commands.StartEvent = function(_, args)
	if not isString(args.event) then
		return false, "Start which event?"
	end
	return EventService.StartEvent(args.event)
end

commands.StopEvent = function()
	return EventService.StopEvent()
end

commands.CloseRunway = function()
	return EventService.CloseRunwayNow()
end

commands.OpenRunway = function()
	return EventService.OpenRunwayNow()
end

----------------------------------------------------------------------------------------------------------------

local function allowRate(player: Player): boolean
	local clock = os.clock()
	local times = recentCommands[player]
	if times == nil then
		times = {}
		recentCommands[player] = times
	end
	while times[1] and clock - times[1] > RATE_WINDOW do
		table.remove(times, 1)
	end
	if #times >= RATE_LIMIT then
		return false
	end
	table.insert(times, clock)
	return true
end

local function onAdminCommand(player: Player, command: unknown, args: unknown): (boolean, string, any?)
	if not admins[player] then
		return false, "Only admins can do that."
	end
	if typeof(command) ~= "string" or commands[command] == nil then
		return false, "Unknown command."
	end
	if not allowRate(player) then
		return false, "Slow down a little."
	end
	local ok, success, message, data = pcall(commands[command], player, if typeof(args) == "table" then args else {})
	if not ok then
		warn(`[AdminService] {command} failed: {success}`)
		return false, "That command failed. See the server output."
	end
	return success, message, data
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(AdminTools.FLY_SPEED, AdminTools.DEFAULT_FLY_SPEED)
	player.CharacterAdded:Connect(function()
		applyWalkSpeed(player)
	end)
	task.spawn(function()
		local isAdmin = checkAdmin(player)
		if player.Parent ~= Players then
			return
		end
		admins[player] = isAdmin or nil
		player:SetAttribute(AdminTools.IS_ADMIN, isAdmin)
	end)
end

function AdminService.Init()
	petFolder = Instance.new("Folder")
	petFolder.Name = "AdminPets"
	petFolder.Parent = Workspace

	ShowroomService.SetLeaveHandler(function(player)
		TeleportService.ToHub(player)
	end)
	Net.AdminCommand.OnServerInvoke = onAdminCommand

	Players.PlayerRemoving:Connect(function(player)
		admins[player] = nil
		recentCommands[player] = nil
	end)
end

function AdminService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return AdminService
