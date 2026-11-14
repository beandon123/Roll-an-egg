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

-- Names of what is added to a character's HumanoidRootPart to draw its trail: the ribbon's two edges, the halo
-- ribbon's two edges, and the point the particles and light come from.
local TRAIL_TOP = "StaminaTrailTop"
local TRAIL_BOTTOM = "StaminaTrailBottom"
local HALO_TOP = "StaminaTrailHaloTop"
local HALO_BOTTOM = "StaminaTrailHaloBottom"
local TRAIL_FX = "StaminaTrailFx"
local TRAIL_PARTS = { TRAIL_TOP, TRAIL_BOTTOM, HALO_TOP, HALO_BOTTOM, TRAIL_FX }
-- The ribbon is centred a little below the middle of the root part, between the shoulders and the knees.
local TRAIL_CENTER_Y = -0.3

-- How each kind of trail particle looks and moves: Roblox's own textures, so nothing has to be uploaded.
local PARTICLE_STYLES = {
	Dust = {
		texture = "rbxasset://textures/particles/smoke_main.dds",
		life = { 0.8, 1.4 },
		speed = { 1, 2.5 },
		grow = 2.5,
		glow = 0,
		lift = 0.5,
		fade = 0.45,
	},
	Bubble = {
		texture = "rbxasset://textures/particles/smoke_main.dds",
		life = { 1.2, 2 },
		speed = { 0.5, 1.5 },
		grow = 1.4,
		glow = 0.6,
		lift = 3,
		fade = 0.3,
	},
	Sparkle = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		life = { 0.8, 1.4 },
		speed = { 0.5, 2 },
		grow = 0,
		glow = 1,
		lift = -0.5,
		fade = 0.1,
	},
	Ember = {
		texture = "rbxasset://textures/particles/fire_main.dds",
		life = { 0.5, 1 },
		speed = { 1, 3 },
		grow = 0,
		glow = 1,
		lift = 5,
		fade = 0.15,
	},
	Spark = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		life = { 0.25, 0.5 },
		speed = { 6, 11 },
		grow = 0,
		glow = 1,
		lift = 0,
		fade = 0,
	},
	Star = {
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		life = { 1, 1.8 },
		speed = { 0.3, 1.2 },
		grow = 0,
		glow = 1,
		lift = 0.3,
		fade = 0,
	},
}

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

local function addAttachment(root: BasePart, name: string, y: number): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = Vector3.new(0, y, 0)
	attachment.Parent = root
	return attachment
end

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- A ribbon left behind between two attachments.
local function ribbon(top: Attachment, bottom: Attachment, info: Trails.TrailInfo, halo: boolean): Trail
	local trail = Instance.new("Trail")
	trail.Name = if halo then "Halo" else "Trail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.MinLength = 0.1
	if halo then
		-- Wider, fainter and shorter, glowing round the ribbon.
		trail.Color = ColorSequence.new(rgb(info.halo :: { number }))
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Lifetime = info.lifetime * 0.75
		trail.LightEmission = 1
	else
		trail.Color = colorSequence(info.colors)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.7, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Lifetime = info.lifetime
		trail.LightEmission = info.glow
	end
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	trail.Parent = top
	return trail
end

local function particles(fx: Attachment, info: Trails.TrailInfo)
	local spec = info.particles
	if spec == nil then
		return
	end
	local style = PARTICLE_STYLES[spec.kind]
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Particles"
	emitter.Texture = style.texture
	emitter.Color = colorSequence(spec.colors)
	emitter.LightEmission = style.glow
	emitter.Rate = spec.rate
	emitter.Lifetime = NumberRange.new(style.life[1], style.life[2])
	emitter.Speed = NumberRange.new(style.speed[1], style.speed[2])
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, style.lift, 0)
	emitter.Drag = 2
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Rotation = NumberRange.new(0, 360)
	if style.grow > 0 then
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, spec.size),
			NumberSequenceKeypoint.new(1, spec.size * style.grow),
		})
	else
		-- Twinkling: grows in, then shrinks away.
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.25, spec.size),
			NumberSequenceKeypoint.new(1, 0),
		})
	end
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, style.fade),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Particles stay where they were shed, so they trail behind a moving character.
	emitter.LockedToPart = false
	emitter.Parent = fx
end

-- Draws the player's equipped trail behind their character (or removes it if none is equipped): its ribbon, and
-- for the fancier trails a halo ribbon, particles and a light.
local function applyTrail(player: Player)
	local data = DataService.GetData(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if data == nil or root == nil or not root:IsA("BasePart") then
		return
	end

	for _, name in TRAIL_PARTS do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local info = Trails.ById[data.Trails.Equipped]
	if info == nil then
		return
	end

	local half = info.width / 2
	local top = addAttachment(root, TRAIL_TOP, TRAIL_CENTER_Y + half)
	local bottom = addAttachment(root, TRAIL_BOTTOM, TRAIL_CENTER_Y - half)
	ribbon(top, bottom, info, false)
	if info.halo then
		local haloTop = addAttachment(root, HALO_TOP, TRAIL_CENTER_Y + half * 1.45)
		local haloBottom = addAttachment(root, HALO_BOTTOM, TRAIL_CENTER_Y - half * 1.45)
		ribbon(haloTop, haloBottom, info, true)
	end
	if info.particles or info.light then
		local fx = addAttachment(root, TRAIL_FX, TRAIL_CENTER_Y)
		particles(fx, info)
		if info.light then
			local glow = Instance.new("PointLight")
			glow.Name = "Glow"
			glow.Color = rgb(info.light)
			glow.Range = 10
			glow.Brightness = 1.2
			glow.Shadows = false
			glow.Parent = fx
		end
	end
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
