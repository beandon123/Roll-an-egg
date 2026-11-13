-- Builds the placeholder map out of plain parts: the hub, the start zone, the five walled zone slabs, and the
-- zone signs.
-- Final art will replace this; gameplay does not depend on any of these parts (it reads positions from
-- Shared/Runway), so swapping the map never breaks the rules.
--
-- Also handles falling: a character well below the runway surface has fallen off and dies.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local NumberFormat = require(Shared.NumberFormat)
local Rarities = require(Shared.Config.Rarities)
local Runway = require(Shared.Runway)
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)

local SLAB_THICKNESS = 4
local SIGN_HEIGHT = 30
local PLOT_COUNT = 8
-- The walls down both sides of the runway.
local WALL_HEIGHT = 22
local WALL_THICKNESS = 8
-- The painted strip just before the runway where players line up.
local START_ZONE_DEPTH = 26

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

-- Text painted flat on top of a part, readable by someone standing at the hub looking down the runway.
local function addFloorText(part: Part, text: string)
	local gui = Instance.new("SurfaceGui")
	-- The part is laid with its Front face pointing up and its top edge pointing down the runway; see buildStartZone.
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 12
	gui.LightInfluence = 0.3
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.62, 0.62)
	label.Font = Enum.Font.LuckiestGuy
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(40, 28, 20)
	stroke.Thickness = 6
	stroke.Parent = label
end

-- A painted strip on the hub floor right where the runway begins, like a race's starting line.
local function buildStartZone(map: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "StartZone"
	folder.Parent = map

	local centerZ = -START_ZONE_DEPTH / 2 - 1
	-- Front face up, top edge pointing down the runway (+z): text on the Front face then reads the right way
	-- round for players walking from the hub to the runway.
	local function flat(name: string, size: Vector2, lift: number, color: Color3): Part
		local part = newPart(name, folder)
		part.Size = Vector3.new(size.X, size.Y, 0.2)
		local center = Vector3.new(0, Runway.BASE_Y + lift, centerZ)
		part.CFrame = CFrame.lookAt(center, center + Vector3.yAxis, Vector3.zAxis)
		part.Color = color
		part.CanCollide = false
		part.CanQuery = false
		return part
	end

	flat("Border", Vector2.new(Runway.WIDTH + 4, START_ZONE_DEPTH + 4), 0.05, Color3.fromRGB(255, 255, 255))
	local strip = flat("Strip", Vector2.new(Runway.WIDTH, START_ZONE_DEPTH), 0.12, Color3.fromRGB(238, 214, 160))
	addFloorText(strip, "START ZONE")

	-- Two yolk-yellow lane marks either side of the words.
	for _, side in { -1, 1 } do
		local mark =
			flat(if side < 0 then "MarkRight" else "MarkLeft", Vector2.new(14, 5), 0.2, Color3.fromRGB(255, 196, 40))
		local center = Vector3.new(side * Runway.WIDTH * 0.4, Runway.BASE_Y + 0.2, centerZ)
		mark.CFrame = CFrame.lookAt(center, center + Vector3.yAxis, Vector3.zAxis)
	end
end

-- The walls down both sides of one zone's slab, sloping with it.
local function buildWalls(
	folder: Instance,
	zone,
	surfaceMiddle: Vector3,
	along: Vector3,
	normal: Vector3,
	length: number
)
	for _, side in { -1, 1 } do
		local offset = Vector3.new(side * (Runway.WIDTH / 2 + WALL_THICKNESS / 2), 0, 0)
		local wall = newPart(if side < 0 then "WallRight" else "WallLeft", folder)
		wall.Size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT + SLAB_THICKNESS, length)
		local wallCenter = surfaceMiddle + offset + normal * ((WALL_HEIGHT - SLAB_THICKNESS) / 2)
		wall.CFrame = CFrame.lookAt(wallCenter, wallCenter + along, normal)
		wall.Color = rgb(zone.accent)

		local cap = newPart(if side < 0 then "CapRight" else "CapLeft", folder)
		cap.Size = Vector3.new(WALL_THICKNESS + 2, 1.5, length)
		local capCenter = surfaceMiddle + offset + normal * (WALL_HEIGHT + 0.75)
		cap.CFrame = CFrame.lookAt(capCenter, capCenter + along, normal)
		cap.Color = rgb(zone.ground)
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
		local slopeLength = Runway.ZONE_LENGTH / math.cos(angle)
		slab.Size = Vector3.new(Runway.WIDTH, SLAB_THICKNESS, slopeLength)
		local surfaceMiddle = Vector3.new(0, Runway.surfaceY(middleZ), middleZ)
		local center = surfaceMiddle - normal * (SLAB_THICKNESS / 2)
		slab.CFrame = CFrame.lookAt(center, center + along, normal)
		slab.Color = rgb(zone.ground)

		buildWalls(folder, zone, surfaceMiddle, along, normal, slopeLength)

		-- A sign over the start of the zone, held up by posts standing on the walls: the zone's name and the
		-- stamina its eggs need.
		local surfaceStart = Runway.surfaceY(startZ)
		local signTop = SIGN_HEIGHT + 4.5
		for _, side in { -1, 1 } do
			local post = newPart("SignPost", folder)
			post.Size = Vector3.new(3, signTop - WALL_HEIGHT, 3)
			post.Position = Vector3.new(
				side * (Runway.WIDTH / 2 + WALL_THICKNESS / 2),
				surfaceStart + (WALL_HEIGHT + signTop) / 2,
				startZ + 2
			)
			post.Color = rgb(zone.accent)
		end

		local sign = newPart("Sign", folder)
		sign.Size = Vector3.new(Runway.WIDTH + WALL_THICKNESS + 4, 9, 1.5)
		sign.Position = Vector3.new(0, surfaceStart + SIGN_HEIGHT, startZ + 2)
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
			if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
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
	buildStartZone(map)
	buildRunway(map)

	map.Parent = Workspace

	Players.RespawnTime = Tuning.RESPAWN_TIME
	Lighting.ClockTime = 14
end

function MapService.Start()
	watchForFalls()
end

return MapService
