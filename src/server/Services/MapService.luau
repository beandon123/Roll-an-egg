-- Builds the map: the hub (PlotService adds the players' plots) with the painted START ZONE where the runway begins,
-- then each zone's stretch of runway with its banks, backdrop and gate (Map/Scenery), and the obstacles on the
-- runway (laid out by Shared/Obstacles, built by Map/ObstacleModels). Gameplay does not depend on any of these parts
-- (it reads positions from Shared/Runway and Shared/Obstacles), so changing how the map looks never breaks the rules.
--
-- Also handles dying on the map: a character well below the runway has fallen through a gap in the banks or gone
-- over the end cliff, and one standing in lava or tar (a Lethal obstacle that is going off) is burned up. An admin
-- who is flying (the admin panel) is spared both.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AdminTools = require(Shared.Config.AdminTools)
local Obstacles = require(Shared.Obstacles)
local Runway = require(Shared.Runway)
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)

local Scenery = require(script.Parent.Parent.Map.Scenery)
local RunwayService = require(script.Parent.RunwayService)

local SLAB_THICKNESS = 4
-- A player on foot counts as standing in a Lethal obstacle when their root part is this close to the ground.
local HAZARD_HEIGHT = 5
-- The painted strip just before the runway where players line up.
local START_ZONE_DEPTH = 26

local MapService = {}

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

-- The hub: a stone plaza behind the start of the runway, with the spawn in the middle. PlotService adds the
-- players' plots down both sides.
local function buildHub(map: Instance)
	local hub = newPart("Hub", map)
	hub.Size = Vector3.new(Runway.HUB_WIDTH, SLAB_THICKNESS, Runway.HUB_LENGTH)
	hub.CFrame = CFrame.new(0, Runway.BASE_Y - SLAB_THICKNESS / 2, -Runway.HUB_LENGTH / 2)
	hub.Color = Color3.fromRGB(150, 152, 158)
	hub.Material = Enum.Material.Cobblestone

	-- A paved path up the middle of the plaza to the runway.
	local path = newPart("Path", map)
	path.Size = Vector3.new(Runway.WIDTH * 0.6, 0.2, Runway.HUB_LENGTH)
	path.CFrame = CFrame.new(0, Runway.BASE_Y + 0.1, -Runway.HUB_LENGTH / 2)
	path.Color = Color3.fromRGB(196, 178, 140)
	path.Material = Enum.Material.Brick
	path.CanCollide = false

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "Spawn"
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.Size = Vector3.new(14, 1, 14)
	spawnPad.CFrame = CFrame.new(0, Runway.BASE_Y + 0.5, -Runway.HUB_LENGTH / 2)
	spawnPad.TopSurface = Enum.SurfaceType.Smooth
	spawnPad.Material = Enum.Material.SmoothPlastic
	spawnPad.Color = Color3.fromRGB(245, 245, 245)
	spawnPad.Parent = map
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
	-- round for players walking from the hub to the runway. Painted over the plaza's path.
	local function flat(name: string, size: Vector2, lift: number, color: Color3): Part
		local part = newPart(name, folder)
		part.Size = Vector3.new(size.X, size.Y, 0.2)
		local center = Vector3.new(0, Runway.BASE_Y + 0.2 + lift, centerZ)
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
		local center = Vector3.new(side * Runway.WIDTH * 0.4, Runway.BASE_Y + 0.4, centerZ)
		mark.CFrame = CFrame.lookAt(center, center + Vector3.yAxis, Vector3.zAxis)
	end
end

local function buildObstacles(map: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Obstacles"
	folder.Parent = map
	for _, obstacle in Obstacles.all() do
		Scenery.buildObstacle(folder, obstacle)
	end
end

-- A soft haze in the distance, as in a big outdoor world. The time of day is set by each client from the cycle
-- (see the client's DayNightController).
local function setUpSky()
	Lighting.ClockTime = 14
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Haze = 1.4
	atmosphere.Glare = 0.4
	atmosphere.Color = Color3.fromRGB(199, 220, 236)
	atmosphere.Decay = Color3.fromRGB(106, 132, 160)
	atmosphere.Parent = Lighting
end

-- Kills characters that have fallen off the end of the runway, or are standing in lava or tar.
local function watchForDangers()
	while true do
		local now = Workspace:GetServerTimeNow()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local flying = player:GetAttribute(AdminTools.FLYING) == true
			if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and not flying then
				local position = root.Position
				local ground = Runway.surfaceY(position.Z)
				local fell = position.Y < ground - Tuning.FALL_KILL_DEPTH
				-- A rider's character is on their egg, wherever the server last saw it on foot.
				local burned = not RunwayService.IsRiding(player)
					and position.Y < ground + HAZARD_HEIGHT
					and Obstacles.lethalAt(position.X, position.Z, now) ~= nil
				if fell or burned then
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
	for zoneId = 1, #Zones.List do
		Scenery.buildZone(map, zoneId)
	end
	buildObstacles(map)
	Scenery.buildEnd(map)

	map.Parent = Workspace

	Players.RespawnTime = Tuning.RESPAWN_TIME
	setUpSky()
end

function MapService.Start()
	watchForDangers()
end

return MapService
