-- Connects the runway rules (Logic/RunwaySim) to the real game: it feeds the rules the clock and what players
-- ask to do, and turns the events that come back into remotes, saved data, and character changes.
--
-- Eggs are not parts on the server. Each client draws them itself from the shared clock (see the client's
-- EggController), so the server only ever sends "an egg appeared / was mounted / was left / is gone".

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CycleClock = require(Shared.CycleClock)
local EggModels = require(Shared.EggModels)
local Net = require(Shared.Net)
local Rarities = require(Shared.Config.Rarities)
local Runway = require(Shared.Runway)
local Shop = require(Shared.Config.Shop)
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)

local DataService = require(script.Parent.DataService)
local RunwaySim = require(script.Parent.Parent.Logic.RunwaySim)

-- Fastest a client may report steering; extra reports are dropped.
local MIN_LATERAL_INTERVAL = 1 / 30

local RunwayService = {}

local rng = Random.new()
local sim = RunwaySim.new(function()
	return rng:NextNumber()
end)

-- Players whose data has loaded, by UserId (the rules know riders only by that number).
local playersByUserId: { [number]: Player } = {}
local lastLateralAt: { [Player]: number } = {}

-- While a player rides, their character is held in place on their own device, so the server's copy of it stays
-- where they got on. Streaming would then load the map around the wrong spot. So every player gets an invisible
-- part that is always where they really are (on their egg while riding, at their character otherwise), and that
-- part is used as their streaming focus.
local focusFolder: Folder
local focusParts: { [Player]: Part } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function createFocus(player: Player)
	local part = Instance.new("Part")
	part.Name = "Focus_" .. player.UserId
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = Vector3.new(0, Runway.BASE_Y, -Runway.HUB_LENGTH / 2)
	part.Parent = focusFolder
	focusParts[player] = part
	player.ReplicationFocus = part
end

local function updateFocusParts(time: number)
	for player, part in focusParts do
		local rider = sim:getRider(player.UserId)
		local egg = if rider and rider.eggId then sim:getEgg(rider.eggId) else nil
		if egg then
			local x, y, z = sim:eggCenter(egg, time)
			part.Position = Vector3.new(x, y, z)
		else
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				part.Position = root.Position
			end
		end
	end
end

-- Max Stamina from what the player owns: the base plus Max Stamina bought in the shop, times their doublings.
local function maxStaminaOf(player: Player): number
	local data = DataService.GetData(player)
	if data == nil then
		return Tuning.BASE_MAX_STAMINA
	end
	return Shop.maxStamina(Tuning.BASE_MAX_STAMINA, data.MaxStaminaBonus, data.StaminaMultiplier)
end

local function killCharacter(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
end

local function grantEgg(player: Player, zone: number, rarity: string, kind: string)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	table.insert(data.Eggs, {
		uid = HttpService:GenerateGUID(false),
		zone = zone,
		rarity = rarity,
		kind = kind,
		claimedAt = os.time(),
	})
	data.Stats.EggsClaimed += 1
	Net.InventoryUpdated:FireClient(player, #data.Eggs)
end

-- Turns what the rules say happened into remotes and saved data.
local function dispatch(events)
	for _, event in events do
		local kind = event.type
		if kind == "EggSpawned" then
			Net.EggSpawned:FireAllClients(event.egg)
			local info = Rarities.Info[event.egg.rarity]
			if info.announce then
				local zone = Zones.List[event.egg.zone]
				local article = if event.egg.rarity == "Eternal" then "An" else "A"
				local about = EggModels.describe(event.egg.kind)
				local name = if about then about.name else "egg"
				Net.Announce:FireAllClients(
					`{article} {event.egg.rarity} {name} just dropped in the {zone.name}!`,
					info.color
				)
			end
		elseif kind == "EggRemoved" then
			Net.EggRemoved:FireAllClients(event.id, event.reason, event.by)
		elseif kind == "EggMounted" then
			Net.EggMounted:FireAllClients(event.id, event.rider, event.time)
		elseif kind == "EggLeft" then
			Net.EggLeft:FireAllClients(event.id, event.time, event.bouncesLeft, event.lateral)
		elseif kind == "RideStarted" then
			local player = playersByUserId[event.rider]
			if player then
				Net.RideStarted:FireClient(player, event.id, {
					startTime = event.startTime,
					startStamina = event.startStamina,
					drain = event.drain,
					claimTime = event.claimTime,
					combo = event.combo,
				})
			end
		elseif kind == "RideEnded" then
			local player = playersByUserId[event.rider]
			if player then
				Net.RideEnded:FireClient(player, event.reason, {
					eggId = event.id,
					zone = event.zone,
					rarity = event.rarity,
					kind = event.kind,
				})
				if event.reason == "Cliff" then
					-- Rode the egg over the end of the runway.
					killCharacter(player)
				end
			end
		elseif kind == "StaminaChanged" then
			local player = playersByUserId[event.rider]
			if player then
				Net.StaminaChanged:FireClient(player, event.value, event.time, event.rate, event.max)
			end
		elseif kind == "Claimed" then
			local player = playersByUserId[event.rider]
			if player then
				grantEgg(player, event.zone, event.rarity, event.kind)
			end
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Requests from players. Nothing a client sends is trusted: types are checked here, and the rules decide.

local function onRequestMount(player: Player, eggId: unknown)
	if typeof(eggId) ~= "number" or eggId ~= eggId then
		return
	end
	local egg = sim:getEgg(eggId)
	if egg == nil then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return
	end

	-- The player must really be next to the egg, with some slack for network delay.
	local time = now()
	local x, y, z = sim:eggCenter(egg, time)
	local distance = (root.Position - Vector3.new(x, y, z)).Magnitude
	local inReach = distance <= egg.spec.halfLength + Tuning.MOUNT_TOLERANCE

	sim:requestMount(player.UserId, eggId, time, inReach)
end

local function onRequestDismount(player: Player)
	sim:requestDismount(player.UserId, now())
end

local function onRideLateral(player: Player, x: unknown)
	if typeof(x) ~= "number" then
		return
	end
	local time = now()
	local last = lastLateralAt[player]
	if last and time - last < MIN_LATERAL_INTERVAL then
		return
	end
	lastLateralAt[player] = time

	local egg = sim:setLateral(player.UserId, x, time)
	if egg then
		Net.EggLateral:FireAllClients(egg.id, egg.lateral)
	end
end

-- What a client needs when it starts: every egg on the runway and its own numbers.
local function onGetSnapshot(player: Player)
	local time = now()
	local rider = sim:getRider(player.UserId)
	local data = DataService.GetData(player)
	return {
		eggs = sim:snapshot(),
		stamina = if rider
			then {
				value = rider.staminaValue,
				time = rider.staminaTime,
				rate = rider.staminaRate,
				max = rider.maxStamina,
			}
			else nil,
		agility = if rider then rider.agility else Tuning.BASE_AGILITY,
		eggCount = if data then #data.Eggs else 0,
		coins = if data then data.Coins else 0,
		serverTime = time,
	}
end

----------------------------------------------------------------------------------------------------------------
-- Players

local function hookCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			sim:killRider(player.UserId, now())
		end)
	end
end

local function onDataLoaded(player: Player, _data)
	playersByUserId[player.UserId] = player
	createFocus(player)
	sim:addRider(player.UserId, maxStaminaOf(player), Tuning.BASE_AGILITY, now())

	player.CharacterAdded:Connect(function(character)
		hookCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		sim:killRider(player.UserId, now())
	end)
	if player.Character then
		task.spawn(hookCharacter, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	sim:removeRider(player.UserId, now())
	playersByUserId[player.UserId] = nil
	lastLateralAt[player] = nil
	local part = focusParts[player]
	if part then
		focusParts[player] = nil
		part:Destroy()
	end
end

----------------------------------------------------------------------------------------------------------------
-- For other services

-- Works a player's Max Stamina out again from what they own. Call after anything that changes it.
function RunwayService.RefreshMaxStamina(player: Player)
	sim:setMaxStamina(player.UserId, maxStaminaOf(player), now())
end

-- Server luck for every egg dropped from now on (1 = normal). See Shared/LuckBoost.
function RunwayService.SetLuck(luck: number)
	sim:setLuck(luck)
end

-- Sets a player's Max Stamina directly, ignoring what they own (only the admin panel does this).
function RunwayService.SetMaxStamina(player: Player, maxStamina: number)
	sim:setMaxStamina(player.UserId, maxStamina, now())
end

function RunwayService.GetMaxStamina(player: Player): number
	local rider = sim:getRider(player.UserId)
	return if rider then rider.maxStamina else Tuning.BASE_MAX_STAMINA
end

-- Drops an egg of a chosen rarity in a zone, if that rarity can drop there. Returns whether it did.
-- `kind` picks one particular egg of the zone (its rarity then comes from the zone's lineup). `placement`
-- ({ z, lateral }) drops it somewhere on the runway other than the zone's chute.
function RunwayService.DropEgg(zoneId: number, rarity: string?, kind: string?, placement: RunwaySim.Placement?): boolean
	return sim:spawnEgg(zoneId, now(), rarity, kind, placement) ~= nil
end

-- Removes every egg nobody is riding, as a closure does. Returns how many went.
function RunwayService.ClearEggs(): number
	return sim:clearUnridden()
end

-- Fills a player's stamina to their Max Stamina.
function RunwayService.RefillStamina(player: Player)
	sim:refillStamina(player.UserId, now())
end

-- Takes a player off the egg they are riding, as if they had hopped off. Does nothing if they are not riding.
function RunwayService.Dismount(player: Player)
	sim:requestDismount(player.UserId, now())
end

-- How many eggs drop, as a multiple of the usual rate (2 during an Egg Avalanche).
function RunwayService.SetEggRate(multiplier: number)
	sim.spawnRateMultiplier = multiplier
end

-- The zone a player's character is standing in (1 when they are at the hub).
function RunwayService.GetZoneOf(player: Player): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return Runway.zoneAt(root.Position.Z) or 1
	end
	return 1
end

function RunwayService.Init()
	focusFolder = Instance.new("Folder")
	focusFolder.Name = "StreamingFocus"
	focusFolder.Parent = Workspace

	Net.RequestMount.OnServerEvent:Connect(onRequestMount)
	Net.RequestDismount.OnServerEvent:Connect(onRequestDismount)
	Net.RideLateral.OnServerEvent:Connect(onRideLateral)
	Net.GetSnapshot.OnServerInvoke = onGetSnapshot

	DataService.OnLoaded(onDataLoaded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function RunwayService.Start()
	RunService.Heartbeat:Connect(function()
		local time = now()
		sim:setPhase(CycleClock.getState(time).phase)
		sim:step(time)
		dispatch(sim:takeEvents())
		updateFocusParts(time)
	end)
end

return RunwayService
