-- Builds the map: the hub (PlotService adds the players' plots) with the painted START ZONE where the runway begins,
-- its stations (the Trails and Sell stalls and the fuse machine, Map/Stations) and the terraced cliffs round it
-- (Map/Cliffs), then each zone's stretch of runway with its banks, backdrop and gate (Map/Scenery), copies of the
-- last zone past the end (the runway never ends; see Shared/Runway), and the
-- obstacles on the runway (laid out by Shared/Obstacles, built by Map/ObstacleModels). Gameplay does not depend on any of these parts
-- (it reads positions from Shared/Runway and Shared/Obstacles), so changing how the map looks never breaks the rules.
--
-- Also catches a character that has somehow fallen out of the world (well below the runway) and sends it back to
-- the hub. Nothing on the runway kills: lava and tar only slow players down (see the client's RideController), and
-- the gaps in the banks have a railing across them. An admin who is flying (the admin panel) is never caught.

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

local Cliffs = require(script.Parent.Parent.Map.Cliffs)
local Scenery = require(script.Parent.Parent.Map.Scenery)
local Stations = require(script.Parent.Parent.Map.Stations)

local SLAB_THICKNESS = 4
-- The painted strip just before the runway where players line up.
local START_ZONE_DEPTH = 26
-- The invisible walls round the hub.
local WALL_HEIGHT = 80

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
-- players' plots across its back and down its sides.
local function buildHub(map: Instance)
	local hub = newPart("Hub", map)
	hub.Size = Vector3.new(Runway.HUB_WIDTH, SLAB_THICKNESS, Runway.HUB_LENGTH)
	hub.CFrame = CFrame.new(0, Runway.BASE_Y - SLAB_THICKNESS / 2, -Runway.HUB_LENGTH / 2)
	hub.Color = Color3.fromRGB(150, 152, 158)
	hub.Material = Enum.Material.Cobblestone

	-- A paved path up the middle of the plaza to the runway.
	local path = newPart("Path", map)
	path.Size = Vector3.new(Runway.START_WIDTH * 0.6, 0.2, Runway.HUB_LENGTH)
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
	spawnPad.Material = Enum.Material.Slate
	spawnPad.Color = Color3.fromRGB(236, 222, 186)
	spawnPad.Parent = map
	-- A gold rim round it.
	local rim = newPart("SpawnRim", map)
	rim.Size = Vector3.new(15.6, 0.9, 15.6)
	rim.CFrame = CFrame.new(0, Runway.BASE_Y + 0.45, -Runway.HUB_LENGTH / 2)
	rim.Color = Color3.fromRGB(246, 196, 60)
	rim.CanCollide = false
	rim.CanQuery = false

	-- Invisible walls round the edge, open only where the runway leaves.
	local walls = Instance.new("Folder")
	walls.Name = "HubWalls"
	walls.Parent = map
	local half, length = Runway.HUB_WIDTH / 2, Runway.HUB_LENGTH
	local gap = Runway.START_WIDTH / 2
	local wallY = Runway.BASE_Y + WALL_HEIGHT / 2
	local pieces = {
		Left = { Vector3.new(2, WALL_HEIGHT, length), Vector3.new(-half - 1, wallY, -length / 2) },
		Right = { Vector3.new(2, WALL_HEIGHT, length), Vector3.new(half + 1, wallY, -length / 2) },
		Back = { Vector3.new(half * 2 + 4, WALL_HEIGHT, 2), Vector3.new(0, wallY, -length - 1) },
		FrontLeft = { Vector3.new(half - gap, WALL_HEIGHT, 2), Vector3.new(-(half + gap) / 2, wallY, 1) },
		FrontRight = { Vector3.new(half - gap, WALL_HEIGHT, 2), Vector3.new((half + gap) / 2, wallY, 1) },
	}
	for name, piece in pieces do
		local wall = newPart(name, walls)
		wall.Size = piece[1]
		wall.CFrame = CFrame.new(piece[2])
		wall.Transparency = 1
		wall.CastShadow = false
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

	flat("Border", Vector2.new(Runway.START_WIDTH + 4, START_ZONE_DEPTH + 4), 0.05, Color3.fromRGB(255, 255, 255))
	local strip = flat("Strip", Vector2.new(Runway.START_WIDTH, START_ZONE_DEPTH), 0.12, Color3.fromRGB(238, 214, 160))
	addFloorText(strip, "START ZONE")

	-- Two yolk-yellow lane marks either side of the words.
	for _, side in { -1, 1 } do
		local mark =
			flat(if side < 0 then "MarkRight" else "MarkLeft", Vector2.new(14, 5), 0.2, Color3.fromRGB(255, 196, 40))
		local center = Vector3.new(side * Runway.START_WIDTH * 0.4, Runway.BASE_Y + 0.4, centerZ)
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

-- A bright, milky fog, like the owner's reference: crisp close by, then everything fading into pale white-blue from
-- FOG_START studs away, half gone by about 490 and lost in it by FOG_END (pushed back from 40 and 600, decided:
-- the owner wanted a little less fog). It is Lighting's own fog, which is set in studs (an Atmosphere's strength
-- can only be judged by eye, and hides this fog, so there is none). The time of day, and the fog's colour with it,
-- are set by each client from the cycle (see the client's DayNightController).
local FOG_START = 80
local FOG_END = 900

-- Bloom, so Neon glows the way it does round the showpiece pets of other games: their eyes, runes, cracks and auras
-- throw a soft halo of light. Only light brighter than the threshold blooms, which Neon is and sunlit ground is not.
-- To try the game without it, delete Lighting.Bloom in Studio (or remove it here).
local BLOOM = { intensity = 1, size = 28, threshold = 1.4 }

local function setUpSky()
	Lighting.ClockTime = 14
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") or child:IsA("BloomEffect") then
			child:Destroy()
		end
	end
	Lighting.FogStart = FOG_START
	Lighting.FogEnd = FOG_END
	Lighting.FogColor = Color3.fromRGB(220, 233, 245)

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	bloom.Intensity = BLOOM.intensity
	bloom.Size = BLOOM.size
	bloom.Threshold = BLOOM.threshold
	bloom.Parent = Lighting
end

-- Sends characters that have fallen out of the world back to the hub.
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
	buildStartZone(map)
	Stations.build(map)
	Cliffs.build(map)
	local lastZone
	for zoneId = 1, #Zones.List do
		lastZone = Scenery.buildZone(map, zoneId)
	end
	-- No end cliff: the runway never ends, so the last zone goes on past it (see Shared/Runway).
	Scenery.buildRepeats(map, lastZone)
	buildObstacles(map)

	map.Parent = Workspace

	Players.RespawnTime = Tuning.RESPAWN_TIME
	setUpSky()
end

function MapService.Start()
	watchForFalls()
end

return MapService
