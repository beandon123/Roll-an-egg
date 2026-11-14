-- Each player's eggs, nests and pets: claimed eggs arrive in the inventory, the player places them in the nests on
-- their plot, and they hatch on a timer into pets. The rules are in Logic/Hatchery and Shared/HatchMath; this
-- service runs them against the clock, saves the results, and keeps the player's device and plot up to date.
--
-- Hatching is worked out from timestamps, so eggs keep hatching while their owner is offline and are ready when
-- they come back. While the runway is closed every nest in the server hatches 30x as fast; when the next cycle
-- starts, the extra time is banked on each nest of every player in the server.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CycleClock = require(Shared.CycleClock)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local Hatchery = require(script.Parent.Parent.Logic.Hatchery)

-- How often hatching is checked, in seconds.
local CHECK_INTERVAL = 0.5
-- The fewest seconds between egg placements the server accepts from one player.
local PLACE_COOLDOWN = 0.2
local MAX_UID_LENGTH = 64

local InventoryService = {}

local lastPlaceAt: { [Player]: number } = {}
local lastCycle: number? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Sends the player everything in their inventory, nests and pets.
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

-- Hatches every egg of the player's that is ready. Returns whether any did.
local function hatchReady(player: Player, time: number): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	local hatched = false
	for _, nest in Hatchery.ready(data, time) do
		local pet = Hatchery.hatch(data, nest, time, HttpService:GenerateGUID(false))
		if pet then
			hatched = true
			PlotService.Hatched(player, nest.slot, time)
			Net.PetHatched:FireClient(player, pet)
		end
	end
	if hatched then
		PlotService.Refresh(player)
		InventoryService.Push(player)
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
			if data and #data.Nests > 0 then
				Hatchery.commitClosure(data, cycleStart)
				PlotService.Refresh(player)
				InventoryService.Push(player)
			end
		end
	end
	lastCycle = cycle
end

local function onPlaceEgg(player: Player, eggUid: unknown)
	if typeof(eggUid) ~= "string" or #eggUid == 0 or #eggUid > MAX_UID_LENGTH then
		return
	end
	local time = now()
	if time - (lastPlaceAt[player] or -math.huge) < PLACE_COOLDOWN then
		return
	end
	lastPlaceAt[player] = time
	local data = DataService.GetData(player)
	if data == nil or PlotService.GetPlot(player) == nil then
		return
	end
	local nest = Hatchery.place(data, eggUid, time)
	if nest then
		PlotService.Refresh(player)
	end
	-- Sent either way, so the device's view of the inventory is never left wrong.
	InventoryService.Push(player)
end

function InventoryService.Init()
	Net.PlaceEgg.OnServerEvent:Connect(onPlaceEgg)
	DataService.OnLoaded(function(player)
		-- Eggs that finished while the player was away hatch straight away.
		hatchReady(player, now())
		PlotService.Refresh(player)
		InventoryService.Push(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPlaceAt[player] = nil
	end)
end

function InventoryService.Start()
	while true do
		local time = now()
		bankClosure(time)
		for _, player in Players:GetPlayers() do
			hatchReady(player, time)
		end
		task.wait(CHECK_INTERVAL)
	end
end

-- For the Studio test panel: finishes every egg in the player's nests now.
function InventoryService.FinishHatching(player: Player)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	for _, nest in data.Nests do
		nest.bonus += 1e7
	end
	hatchReady(player, now())
end

return InventoryService
