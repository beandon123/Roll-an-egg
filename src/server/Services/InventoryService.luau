-- Each player's eggs, pen, pets and dollars. Claimed eggs arrive in the inventory; the player puts them down in
-- their pen, where they hatch on a timer into pets (Silver, Gold or Rainbow if lucky). Pets in the pen earn dollars
-- every second; pets can be sold; dollars buy a bigger pen. The rules are in Logic/Hatchery, Shared/HatchMath and
-- Shared/PetWorth; this service runs them against the clock, saves the results, and keeps the player's device
-- and plot up to date.
--
-- Hatching is worked out from timestamps, so eggs keep hatching while their owner is offline and are ready when
-- they come back. While the runway is closed every egg in the server hatches 30x as fast; when the next cycle
-- starts, the extra time is banked on each egg of every player in the server.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CycleClock = require(Shared.CycleClock)
local EggModels = require(Shared.EggModels)
local Net = require(Shared.Net)
local NumberFormat = require(Shared.NumberFormat)
local PetModels = require(Shared.PetModels)

local DataService = require(script.Parent.DataService)
local MountService = require(script.Parent.MountService)
local PlotService = require(script.Parent.PlotService)
local Hatchery = require(script.Parent.Parent.Logic.Hatchery)

-- How often hatching and income are worked out, in seconds.
local TICK = 0.5
-- The fewest seconds between requests the server accepts from one player.
local REQUEST_COOLDOWN = 0.15
local MAX_UID_LENGTH = 64

local GOOD = { 120, 230, 120 }
local WARN = { 255, 190, 90 }

local InventoryService = {}

local lastRequestAt: { [Player]: number } = {}
local lastCycle: number? = nil
local rng = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function notice(player: Player, text: string, color: { number }?)
	Net.Notice:FireClient(player, text, color)
end

local function money(amount: number): string
	return "$" .. NumberFormat.abbreviate(amount)
end

local function petName(kind: string): string
	local design = PetModels.get(kind)
	return if design then design.name else kind
end

-- Sends the player everything in their inventory, pen and pets.
function InventoryService.Push(player: Player)
	local data = DataService.GetData(player)
	if data then
		Net.InventoryChanged:FireClient(player, Hatchery.state(data))
	end
end

-- What the player's device is told about their inventory when it starts.
function InventoryService.GetState(player: Player)
	local data = DataService.GetData(player)
	return if data then Hatchery.state(data) else nil
end

-- Adds a claimed egg to a player's inventory.
function InventoryService.AddEgg(player: Player, zone: number, rarity: string, kind: string)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	table.insert(data.Eggs, {
		uid = HttpService:GenerateGUID(false),
		zone = zone,
		rarity = rarity,
		kind = kind,
		claimedAt = now(),
	})
	data.Stats.EggsClaimed += 1
	InventoryService.Push(player)
end

-- Gives a player dollars (the Studio test panel uses this).
function InventoryService.AddDollars(player: Player, amount: number)
	local data = DataService.GetData(player)
	if data then
		data.Dollars += amount
		Net.DollarsChanged:FireClient(player, data.Dollars, Hatchery.income(data))
	end
end

-- The player changed something about their pen or pets: update the plot and their device.
local function changed(player: Player)
	PlotService.Refresh(player)
	InventoryService.Push(player)
end

-- Hatches every egg of the player's that is ready. Returns whether any did.
local function hatchReady(player: Player, time: number): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	local hatched = false
	for _, entry in Hatchery.ready(data, time) do
		local pet = Hatchery.hatch(data, entry, time, HttpService:GenerateGUID(false), rng:NextNumber())
		if pet then
			hatched = true
			PlotService.Hatched(player, entry.uid, time)
			Net.PetHatched:FireClient(player, pet)
		end
	end
	if hatched then
		changed(player)
	end
	return hatched
end

-- When a new cycle has started, bank the closure that just ended for everyone in the server.
local function bankClosure(time: number)
	local cycle = CycleClock.getState(time).index
	if lastCycle ~= nil and cycle > lastCycle then
		local cycleStart = cycle * CycleClock.CYCLE_LENGTH
		for _, player in Players:GetPlayers() do
			local data = DataService.GetData(player)
			if data and #data.Hatching > 0 then
				Hatchery.commitClosure(data, cycleStart)
				changed(player)
			end
		end
	end
	lastCycle = cycle
end

-- Pays every player what their pen earned over `seconds`.
local function payIncome(seconds: number)
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data then
			local income = Hatchery.income(data)
			data.Dollars += income * seconds
			Net.DollarsChanged:FireClient(player, data.Dollars, income)
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Requests. Nothing a client sends is trusted: types are checked here, and the rules decide.

-- The player's data, if they may make a request now (it has loaded, and they are not sending too fast).
local function forRequest(player: Player)
	local time = now()
	if time - (lastRequestAt[player] or -math.huge) < REQUEST_COOLDOWN then
		return nil
	end
	lastRequestAt[player] = time
	return DataService.GetData(player)
end

local function isUid(value: unknown): boolean
	return typeof(value) == "string" and #value > 0 and #value <= MAX_UID_LENGTH
end

local function onPlaceEgg(player: Player, eggUid: unknown)
	if not isUid(eggUid) then
		return
	end
	local data = forRequest(player)
	if data == nil then
		return
	end
	local inward, along = PlotService.SpotInPen(player)
	if inward == nil or along == nil then
		notice(player, "Walk into your pen to put eggs down", WARN)
		return
	end
	local entry, reason = Hatchery.place(data, eggUid :: string, inward, along, now())
	if entry then
		local about = EggModels.describe(entry.kind)
		notice(player, `{if about then about.name else "Egg"} is hatching!`, GOOD)
		changed(player)
	elseif reason == "Full" then
		notice(
			player,
			`Your pen can only hatch {Hatchery.eggCapacity(data)} eggs at once: wait, or buy a bigger pen`,
			WARN
		)
	elseif reason == "NoRoom" then
		notice(player, "No room for an egg here: try another spot", WARN)
	end
	InventoryService.Push(player)
end

local function onSetInPen(player: Player, petUid: unknown, inPen: unknown)
	if not isUid(petUid) or typeof(inPen) ~= "boolean" then
		return
	end
	local data = forRequest(player)
	if data == nil then
		return
	end
	local ok, reason = Hatchery.setInPen(data, petUid :: string, inPen :: boolean)
	if not ok and reason == "Full" then
		notice(player, `Your pen holds {Hatchery.petCapacity(data)} pets: take one out, or buy a bigger pen`, WARN)
	end
	changed(player)
end

local function onEquipBest(player: Player)
	local data = forRequest(player)
	if data == nil then
		return
	end
	Hatchery.equipBest(data)
	notice(player, "Your best pets are in your pen", GOOD)
	changed(player)
end

local function onSellPet(player: Player, petUid: unknown)
	if not isUid(petUid) then
		return
	end
	local data = forRequest(player)
	if data == nil then
		return
	end
	local kind
	for _, pet in data.Pets do
		if pet.uid == petUid then
			kind = pet.kind
		end
	end
	local price = Hatchery.sell(data, petUid :: string)
	if price then
		notice(player, `Sold {petName(kind)} for {money(price)}`, GOOD)
		MountService.Refresh(player)
		changed(player)
		Net.DollarsChanged:FireClient(player, data.Dollars, Hatchery.income(data))
	end
end

local function onRidePet(player: Player, petUid: unknown)
	if typeof(petUid) ~= "string" or #petUid > MAX_UID_LENGTH then
		return
	end
	local data = forRequest(player)
	if data == nil then
		return
	end
	MountService.Ride(player, petUid)
	InventoryService.Push(player)
end

local function onUpgrade(player: Player)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	local ok, reason, cost = Hatchery.upgradePen(data)
	if ok then
		notice(
			player,
			`Bigger pen! Room for {Hatchery.eggCapacity(data)} eggs and {Hatchery.petCapacity(data)} pets`,
			GOOD
		)
		changed(player)
		Net.DollarsChanged:FireClient(player, data.Dollars, Hatchery.income(data))
	elseif reason == "Money" and cost then
		notice(player, `A bigger pen costs {money(cost)}: you have {money(data.Dollars)}`, WARN)
	elseif reason == "Max" then
		notice(player, "Your pen is as big as it gets!", GOOD)
	end
end

function InventoryService.Init()
	Net.PlaceEgg.OnServerEvent:Connect(onPlaceEgg)
	Net.SetInPen.OnServerEvent:Connect(onSetInPen)
	Net.EquipBest.OnServerEvent:Connect(onEquipBest)
	Net.SellPet.OnServerEvent:Connect(onSellPet)
	Net.RidePet.OnServerEvent:Connect(onRidePet)
	PlotService.OnUpgradePressed(onUpgrade)
	DataService.OnLoaded(function(player, data)
		-- Eggs that finished while the player was away hatch straight away.
		hatchReady(player, now())
		changed(player)
		Net.DollarsChanged:FireClient(player, data.Dollars, Hatchery.income(data))
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
	end)
end

function InventoryService.Start()
	local last = now()
	while true do
		local time = now()
		bankClosure(time)
		for _, player in Players:GetPlayers() do
			hatchReady(player, time)
		end
		payIncome(math.clamp(time - last, 0, 5))
		last = time
		task.wait(TICK)
	end
end

-- For the Studio test panel: finishes every egg hatching in the player's pen now.
function InventoryService.FinishHatching(player: Player)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	for _, entry in data.Hatching do
		entry.bonus += 1e7
	end
	hatchReady(player, now())
end

return InventoryService
