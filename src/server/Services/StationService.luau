-- Connects the hub's stalls (Logic/Stalls) to players: the Trails stall, where trails that boost Max Stamina are
-- bought and equipped, and the Sell stall, where unwanted eggs are sold for dollars. Also keeps each player's device
-- told about their trails, and draws the equipped trail behind their character. (The fuse machine's rules are in
-- Logic/Fuse; its panel only explains them for now.)
--
-- Nothing a client sends is trusted: every argument is type-checked here, requests are rate-limited, and the
-- rules in Logic/Stalls decide. Clients never send prices, dollars, or stamina.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Trails = require(Shared.Config.Trails)

local Stalls = require(script.Parent.Parent.Logic.Stalls)

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local RunwayService = require(script.Parent.RunwayService)

-- Minimum seconds between stall requests from one player; faster ones are refused.
local REQUEST_COOLDOWN = 0.2
-- Most eggs one sell request may ask for, and the longest egg kind accepted.
local MAX_SELL_COUNT = 10000
local MAX_KIND_LENGTH = 64

-- Names of what is added to a character's HumanoidRootPart to draw its trail.
local TRAIL_TOP = "StaminaTrailTop"
local TRAIL_BOTTOM = "StaminaTrailBottom"

local StationService = {}

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

local function sendTrails(player: Player, data)
	Net.TrailsUpdated:FireClient(player, Stalls.ownedTrails(data), data.Trails.Equipped)
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
	local ok, result = Stalls.buyTrail(data, trailId)
	if ok then
		InventoryService.RefreshDollars(player)
		sendTrails(player, data)
		RunwayService.RefreshMaxStamina(player)
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
	local ok, result = Stalls.equipTrail(data, trailId)
	if ok then
		sendTrails(player, data)
		RunwayService.RefreshMaxStamina(player)
		applyTrail(player)
	end
	return ok, result
end

local function onSellEggs(player: Player, kind: unknown, count: unknown)
	if
		typeof(kind) ~= "string"
		or #(kind :: string) > MAX_KIND_LENGTH
		or not isWholeNumber(count, 1, MAX_SELL_COUNT)
		or not allowRequest(player)
	then
		return 0, 0
	end
	local data = DataService.GetData(player)
	if data == nil then
		return 0, 0
	end
	local sold, dollars = Stalls.sellEggs(data, kind :: string, count :: number)
	if sold > 0 then
		InventoryService.RefreshDollars(player)
		InventoryService.Push(player)
	end
	return sold, dollars
end

----------------------------------------------------------------------------------------------------------------
-- Players

local function onDataLoaded(player: Player, data)
	sendTrails(player, data)

	player.CharacterAdded:Connect(function(character)
		if character:FindFirstChild("HumanoidRootPart") then
			applyTrail(player)
			return
		end
		-- The root part can arrive a moment after the character.
		local connection
		connection = character.ChildAdded:Connect(function(child)
			if child.Name == "HumanoidRootPart" then
				connection:Disconnect()
				applyTrail(player)
			end
		end)
	end)
	if player.Character then
		applyTrail(player)
	end
end

function StationService.Init()
	Net.GetTrails.OnServerInvoke = StationService.GetTrails
	Net.BuyTrail.OnServerInvoke = onBuyTrail
	Net.EquipTrail.OnServerInvoke = onEquipTrail
	Net.SellEggs.OnServerInvoke = onSellEggs

	DataService.OnLoaded(onDataLoaded)
	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
	end)
end

-- What the player's device is told about their trails when it starts: { owned, equipped }.
function StationService.GetTrails(player: Player)
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	return { owned = Stalls.ownedTrails(data), equipped = data.Trails.Equipped }
end

return StationService
