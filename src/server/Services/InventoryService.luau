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
-- Income boosts (the x2 Dollars pass), per player.
local incomeMultipliers: { [Player]: number } = {}
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

local function incomeOf(player: Player, data): number
	return Hatchery.income(data, incomeMultipliers[player])
end

local function sendDollars(player: Player, data)
	Net.DollarsChanged:FireClient(player, data.Dollars, incomeOf(player, data))
end

-- Sends the player everything in their inventory, pen and pets.
function InventoryService.Push(player: Player)
	local data = DataService.GetData(player)
	if data then
		Net.InventoryChanged:FireClient(player, Hatchery.state(data, incomeMultipliers[player]))
	end
end

-- What the player's device is told about their inventory when it starts.
function InventoryService.GetState(player: Player)
	local data = DataService.GetData(player)
	return if data then Hatchery.state(data, incomeMultipliers[player]) else nil
end

-- Multiplies what a player's pen earns (the x2 Dollars pass).
function InventoryService.SetIncomeMultiplier(player: Player, multiplier: number)
	incomeMultipliers[player] = multiplier
	local data = DataService.GetData(player)
	if data then
		sendDollars(player, data)
		InventoryService.Push(player)
	end
end

-- Adds a claimed egg to a player's inventory. `given` is for eggs from the admin panel, which do not count as
-- claimed.
function InventoryService.AddEgg(player: Player, zone: number, rarity: string, kind: string, given: boolean?)
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
	if not given then
		data.Stats.EggsClaimed += 1
	end
	InventoryService.Push(player)
end

-- Gives a player dollars (shop purchases and the admin panel). `cap` limits the total.
function InventoryService.AddDollars(player: Player, amount: number, cap: number?)
	local data = DataService.GetData(player)
	if data then
		data.Dollars = math.min(data.Dollars + amount, cap or math.huge)
		sendDollars(player, data)
	end
end

-- Takes all of a player's dollars away (the admin panel).
function InventoryService.ResetDollars(player: Player)
	local data = DataService.GetData(player)
	if data then
		data.Dollars = 0
		sendDollars(player, data)
	end
end

-- The player changed something about their pen or pets: update the plot and their device.
local function changed(player: Player)
	PlotService.Refresh(player)
	InventoryService.Push(player)
end

-- Something outside this service changed the player's eggs, pets or pen (the admin panel): update everything.
function InventoryService.Changed(player: Player)
	MountService.Refresh(player)
	changed(player)
	local data = DataService.GetData(player)
	if data then
		sendDollars(player, data)
	end
end

-- Gives a player a pet as if it had just hatched (the admin panel): into the pen if there is room.
function InventoryService.GivePet(player: Player, kind: string, egg: string, zone: number, rarity: string): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	local pet = {
		uid = HttpService:GenerateGUID(false),
		kind = kind,
		egg = egg,
		zone = zone,
		rarity = rarity,
		variant = "Normal",
		inPen = false,
		hatchedAt = now(),
	}
	table.insert(data.Pets, pet)
	Hatchery.setInPen(data, pet.uid, true)
	return true
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
			local income = incomeOf(player, data)
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
		sendDollars(player, data)
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

local function biggerPenMessage(data): string
	return `Bigger pen! Room for {Hatchery.eggCapacity(data)} eggs and {Hatchery.petCapacity(data)} pets`
end

-- Buys the next pen level with dollars (the green button, or the shop). Returns whether it worked and what to
-- tell the player.
function InventoryService.UpgradePen(player: Player): (boolean, string)
	local data = DataService.GetData(player)
	if data == nil then
		return false, "Your data has not loaded yet."
	end
	local ok, reason, cost = Hatchery.upgradePen(data)
	if ok then
		changed(player)
		sendDollars(player, data)
		return true, biggerPenMessage(data)
	elseif reason == "Money" and cost then
		return false, `A bigger pen costs {money(cost)}: you have {money(data.Dollars)}`
	end
	return false, "Your pen is as big as it gets!"
end

-- Raises the pen a level without paying dollars (bought with Robux). Returns what to tell the player, or nil if
-- the pen is already as big as it gets.
function InventoryService.RaisePen(player: Player): string?
	local data = DataService.GetData(player)
	if data == nil then
		error("data not loaded")
	end
	if not Hatchery.raisePen(data) then
		return nil
	end
	changed(player)
	return biggerPenMessage(data)
end

local function onUpgrade(player: Player)
	local ok, message = InventoryService.UpgradePen(player)
	notice(player, message, if ok then GOOD else WARN)
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
		sendDollars(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
		incomeMultipliers[player] = nil
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

-- For the admin panel: finishes every egg hatching in the player's pen now. Returns how many hatched.
function InventoryService.FinishHatching(player: Player): number
	local data = DataService.GetData(player)
	if data == nil then
		return 0
	end
	local count = #data.Hatching
	for _, entry in data.Hatching do
		entry.bonus += 1e7
	end
	hatchReady(player, now())
	return count - #data.Hatching
end

return InventoryService
