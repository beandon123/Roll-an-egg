-- Connects the hub shops (Logic/Shop) to players: the Trails shop, where trails that boost Max Stamina are bought
-- and equipped, and the Sell stall, where unwanted eggs are sold for coins. Also keeps each player's client told
-- about their coins, eggs, and trails, and draws the equipped trail behind their character.
--
-- Nothing a client sends is trusted: every argument is type-checked here, requests are rate-limited, and the
-- rules in Logic/Shop decide. Clients never send prices, coins, or stamina.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Rarities = require(Shared.Config.Rarities)
local Trails = require(Shared.Config.Trails)

local Logic = script.Parent.Parent.Logic
local Inventory = require(Logic.Inventory)
local Shop = require(Logic.Shop)
local Stats = require(Logic.Stats)

local DataService = require(script.Parent.DataService)
local RunwayService = require(script.Parent.RunwayService)

-- Minimum seconds between shop requests from one player; faster ones are refused.
local REQUEST_COOLDOWN = 0.2
-- Most eggs one sell request may ask for.
local MAX_SELL_COUNT = 10000

-- Names of what is added to a character's HumanoidRootPart to draw its trail.
local TRAIL_TOP = "StaminaTrailTop"
local TRAIL_BOTTOM = "StaminaTrailBottom"

local ShopService = {}

local lastRequestAt: { [Player]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Whether to handle a request from this player now (rate limit).
local function allowRequest(player: Player): boolean
	local time = now()
	local last = lastRequestAt[player]
	if last and time - last < REQUEST_COOLDOWN then
		return false
	end
	lastRequestAt[player] = time
	return true
end

local function isWholeNumber(value: unknown, low: number, high: number): boolean
	return typeof(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

----------------------------------------------------------------------------------------------------------------
-- Telling the client

local function sendCoins(player: Player, data)
	Net.CoinsChanged:FireClient(player, data.Coins)
end

local function sendInventory(player: Player, data)
	Net.InventoryUpdated:FireClient(player, Inventory.eggGroups(data.Eggs))
end

local function sendTrails(player: Player, data)
	Net.TrailsUpdated:FireClient(player, Shop.ownedTrails(data), data.Trails.Equipped)
end

----------------------------------------------------------------------------------------------------------------
-- Trails on characters

local function colorSequence(colors: { { number } }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(Color3.fromRGB(colors[1][1], colors[1][2], colors[1][3]))
	end
	local keypoints = {}
	for index, color in colors do
		local time = (index - 1) / (#colors - 1)
		table.insert(keypoints, ColorSequenceKeypoint.new(time, Color3.fromRGB(color[1], color[2], color[3])))
	end
	return ColorSequence.new(keypoints)
end

-- Draws the player's equipped trail behind their character (or removes it if none is equipped).
local function applyTrail(player: Player)
	local data = DataService.GetData(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if data == nil or root == nil or not root:IsA("BasePart") then
		return
	end

	for _, name in { TRAIL_TOP, TRAIL_BOTTOM } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local info = Trails.ById[data.Trails.Equipped]
	if info == nil then
		return
	end

	-- A ribbon between the shoulders and the knees, left behind as the character moves.
	local top = Instance.new("Attachment")
	top.Name = TRAIL_TOP
	top.Position = Vector3.new(0, 1, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = TRAIL_BOTTOM
	bottom.Position = Vector3.new(0, -1.6, 0)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "Trail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = colorSequence(info.colors)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	trail.Lifetime = 0.6
	trail.MinLength = 0.1
	trail.LightEmission = 0.5
	trail.Parent = top
end

-- Puts the player's Max Stamina in line with their saved data (their equipped trail).
local function applyStamina(player: Player, data)
	RunwayService.SetMaxStamina(player, Stats.maxStamina(data))
end

----------------------------------------------------------------------------------------------------------------
-- Requests from players

local function onBuyTrail(player: Player, trailId: unknown)
	if typeof(trailId) ~= "string" then
		return false, "Invalid"
	end
	if not allowRequest(player) then
		return false, "TooFast"
	end
	local data = DataService.GetData(player)
	if data == nil then
		return false, "NotLoaded"
	end
	local ok, result = Shop.buyTrail(data, trailId)
	if ok then
		sendCoins(player, data)
		sendTrails(player, data)
		applyStamina(player, data)
		applyTrail(player)
	end
	return ok, result
end

local function onEquipTrail(player: Player, trailId: unknown)
	if typeof(trailId) ~= "string" then
		return false, "Invalid"
	end
	if not allowRequest(player) then
		return false, "TooFast"
	end
	local data = DataService.GetData(player)
	if data == nil then
		return false, "NotLoaded"
	end
	local ok, result = Shop.equipTrail(data, trailId)
	if ok then
		sendTrails(player, data)
		applyStamina(player, data)
		applyTrail(player)
	end
	return ok, result
end

local function onSellEggs(player: Player, zone: unknown, rarity: unknown, count: unknown)
	if
		not isWholeNumber(zone, 1, 100)
		or typeof(rarity) ~= "string"
		or Rarities.Info[rarity :: string] == nil
		or not isWholeNumber(count, 1, MAX_SELL_COUNT)
		or not allowRequest(player)
	then
		return 0, 0
	end
	local data = DataService.GetData(player)
	if data == nil then
		return 0, 0
	end
	local sold, coins = Shop.sellEggs(data, zone :: number, rarity :: string, count :: number)
	if sold > 0 then
		sendCoins(player, data)
		sendInventory(player, data)
	end
	return sold, coins
end

----------------------------------------------------------------------------------------------------------------
-- Players

local function onDataLoaded(player: Player, data)
	sendCoins(player, data)
	sendInventory(player, data)
	sendTrails(player, data)

	player.CharacterAdded:Connect(function(character)
		-- The root part can arrive a moment after the character.
		if character:WaitForChild("HumanoidRootPart", 10) then
			applyTrail(player)
		end
	end)
	if player.Character then
		applyTrail(player)
	end
end

----------------------------------------------------------------------------------------------------------------
-- For other services

-- Gives a player coins (selling, pet income, and the Studio test panel use this). Returns false if their data is
-- not loaded.
function ShopService.AddCoins(player: Player, amount: number): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	data.Coins += amount
	sendCoins(player, data)
	return true
end

function ShopService.Init()
	Net.BuyTrail.OnServerInvoke = onBuyTrail
	Net.EquipTrail.OnServerInvoke = onEquipTrail
	Net.SellEggs.OnServerInvoke = onSellEggs

	DataService.OnLoaded(onDataLoaded)
	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
	end)
end

return ShopService
