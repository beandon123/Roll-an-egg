-- Builds the map: the hub (PlotService adds the players' plots), then each zone's stretch of runway with its banks, backdrop and gate
-- (Map/Scenery), and the obstacles on the runway (laid out by Shared/Obstacles, built by Map/ObstacleModels).
-- Gameplay does not depend on any of these parts (it reads positions from Shared/Runway and Shared/Obstacles),
-- so changing how the map looks never breaks the rules.
--
-- Also handles dying on the map: a character well below the runway has gone over the end cliff, and one standing
-- in lava or tar (a Lethal obstacle that is going off) is burned up.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Obstacles = require(Shared.Obstacles)
local Runway = require(Shared.Runway)
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)

local Scenery = require(script.Parent.Parent.Map.Scenery)
local RunwayService = require(script.Parent.RunwayService)

local SLAB_THICKNESS = 4
-- A player on foot counts as standing in a Lethal obstacle when their root part is this close to the ground.
local HAZARD_HEIGHT = 5

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
			if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
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
