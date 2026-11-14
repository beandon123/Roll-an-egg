-- Builds the placeholder map out of plain parts: the hub, the five zone slabs, and the zone signs.
-- Final art will replace this; gameplay does not depend on any of these parts (it reads positions from
-- Shared/Runway), so swapping the map never breaks the rules.
--
-- Also handles falling: a character well below the runway surface has fallen off and dies (unless an admin is
-- flying it).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AdminTools = require(Shared.Config.AdminTools)
local NumberFormat = require(Shared.NumberFormat)
local Rarities = require(Shared.Config.Rarities)
local Runway = require(Shared.Runway)
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)

local SLAB_THICKNESS = 4
local SIGN_HEIGHT = 26
local PLOT_COUNT = 8

local MapService = {}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function newPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

local function addSignText(part: Part, face: Enum.NormalId, title: string, subtitle: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = part

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, 0.62)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.Text = title
	titleLabel.TextColor3 = color
	titleLabel.TextScaled = true
	titleLabel.Parent = gui

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Position = UDim2.fromScale(0, 0.62)
	subtitleLabel.Size = UDim2.fromScale(1, 0.34)
	subtitleLabel.Font = Enum.Font.GothamBold
	subtitleLabel.Text = subtitle
	subtitleLabel.TextColor3 = Color3.new(1, 1, 1)
	subtitleLabel.TextScaled = true
	subtitleLabel.Parent = gui
end

-- The lowest and highest stamina requirement of a zone's eggs.
local function staminaRange(zone): (number, number)
	local low, high = math.huge, 0
	for rarity in Rarities.Info do
		local requirement = zone.stamina[rarity]
		if requirement then
			low = math.min(low, requirement)
			high = math.max(high, requirement)
		end
	end
	return low, high
end

local function buildHub(map: Instance)
	local hub = newPart("Hub", map)
	hub.Size = Vector3.new(Runway.HUB_WIDTH, SLAB_THICKNESS, Runway.HUB_LENGTH)
	hub.Position = Vector3.new(0, Runway.BASE_Y - SLAB_THICKNESS / 2, -Runway.HUB_LENGTH / 2)
	hub.Color = Color3.fromRGB(120, 124, 132)

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "Spawn"
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.Size = Vector3.new(14, 1, 14)
	spawnPad.Position = Vector3.new(0, Runway.BASE_Y + 0.5, -Runway.HUB_LENGTH / 2)
	spawnPad.TopSurface = Enum.SurfaceType.Smooth
	spawnPad.Material = Enum.Material.SmoothPlastic
	spawnPad.Color = Color3.fromRGB(245, 245, 245)
	spawnPad.Parent = map

	-- Plot pads down both sides of the hub. They do nothing yet; pens and nests will be built on them.
	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = map
	local perSide = PLOT_COUNT / 2
	local spacing = (Runway.HUB_LENGTH - 40) / perSide
	for index = 1, PLOT_COUNT do
		local side = if index <= perSide then -1 else 1
		local row = (index - 1) % perSide
		local pad = newPart("Plot" .. index, plots)
		pad.Size = Vector3.new(40, 0.4, spacing - 8)
		pad.Position = Vector3.new(
			side * (Runway.HUB_WIDTH / 2 - 30),
			Runway.BASE_Y + 0.2,
			-Runway.HUB_LENGTH + 20 + spacing * (row + 0.5)
		)
		pad.Color = Color3.fromRGB(196, 172, 124)
	end
end

local function buildRunway(map: Instance)
	local angle = math.atan(Runway.SLOPE)
	-- Unit vectors along the slope (downhill) and straight out of its surface.
	local along = Vector3.new(0, -math.sin(angle), math.cos(angle))
	local normal = Vector3.new(0, math.cos(angle), math.sin(angle))

	for _, zone in Zones.List do
		local folder = Instance.new("Folder")
		folder.Name = zone.key
		folder.Parent = map

		local startZ = Runway.zoneStartZ(zone.id)
		local middleZ = startZ + Runway.ZONE_LENGTH / 2

		local slab = newPart("Ground", folder)
		slab.Size = Vector3.new(Runway.WIDTH, SLAB_THICKNESS, Runway.ZONE_LENGTH / math.cos(angle))
		local surfaceMiddle = Vector3.new(0, Runway.surfaceY(middleZ), middleZ)
		local center = surfaceMiddle - normal * (SLAB_THICKNESS / 2)
		slab.CFrame = CFrame.lookAt(center, center + along, normal)
		slab.Color = rgb(zone.ground)

		-- A sign over the start of the zone: its name and the stamina its eggs need.
		local surfaceStart = Runway.surfaceY(startZ)
		for _, side in { -1, 1 } do
			local post = newPart("SignPost", folder)
			post.Size = Vector3.new(3, SIGN_HEIGHT + 8, 3)
			post.Position = Vector3.new(side * (Runway.WIDTH / 2 + 3), surfaceStart + (SIGN_HEIGHT + 8) / 2 - 4, startZ)
			post.Color = rgb(zone.accent)
		end

		local sign = newPart("Sign", folder)
		sign.Size = Vector3.new(Runway.WIDTH + 9, 9, 1.5)
		sign.Position = Vector3.new(0, surfaceStart + SIGN_HEIGHT, startZ)
		sign.Color = rgb(zone.accent)
		local low, high = staminaRange(zone)
		local subtitle = `Eggs need {NumberFormat.abbreviate(low)} - {NumberFormat.abbreviate(high)} stamina`
		local textColor = Color3.new(1, 1, 1)
		-- Front faces players coming from the hub; Back faces players walking home.
		addSignText(sign, Enum.NormalId.Front, string.upper(zone.name), subtitle, textColor)
		addSignText(sign, Enum.NormalId.Back, string.upper(zone.name), subtitle, textColor)
	end

	-- A warning stripe before the cliff at the end of the runway.
	local warningZ = Runway.LENGTH - 60
	local stripe = newPart("EdgeWarning", map)
	stripe.Size = Vector3.new(Runway.WIDTH, 0.3, 6)
	local stripeCenter = Vector3.new(0, Runway.surfaceY(warningZ) + 0.1, warningZ)
	stripe.CFrame = CFrame.lookAt(stripeCenter, stripeCenter + along, normal)
	stripe.Color = Color3.fromRGB(255, 60, 60)
	stripe.Material = Enum.Material.Neon
	stripe.CanCollide = false
end

-- Kills characters that have fallen off the runway or the hub.
local function watchForFalls()
	while true do
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local flying = player:GetAttribute(AdminTools.FLYING) == true
			if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and not flying then
				local position = root.Position
				if position.Y < Runway.surfaceY(position.Z) - Tuning.FALL_KILL_DEPTH then
					humanoid.Health = 0
				end
			end
		end
		task.wait(0.25)
	end
end

function MapService.Init()
	local map = Instance.new("Folder")
	map.Name = "Map"

	buildHub(map)
	buildRunway(map)

	map.Parent = Workspace

	Players.RespawnTime = Tuning.RESPAWN_TIME
	Lighting.ClockTime = 14
end

function MapService.Start()
	watchForFalls()
end

return MapService
