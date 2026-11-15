-- Builds the placeholder map out of plain parts: the hub, the five zone slabs, their gates, and the side walls
-- (see Shared/MapParts).
-- Final art will replace this; gameplay does not depend on any of these parts (it reads positions from
-- Shared/Runway), so swapping the map never breaks the rules.
--
-- Also handles falling: a character well below the runway surface has fallen off and dies.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local MapParts = require(Shared.MapParts)
local Runway = require(Shared.Runway)
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)

local SLAB_THICKNESS = MapParts.SLAB_THICKNESS
local PLOT_COUNT = 8

-- Light fog far away. The runway never ends, and the fog makes sure nobody can see where the parts stop.
local FOG_START = 900
local FOG_END = 2000
local FOG_COLOR = Color3.fromRGB(192, 214, 232)

local MapService = {}

local newPart = MapParts.newPart

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
	for _, zone in Zones.List do
		local folder = Instance.new("Folder")
		folder.Name = zone.key
		folder.Parent = map
		local startZ = Runway.zoneStartZ(zone.id)
		MapParts.ground(folder, zone.id, startZ, startZ + Runway.ZONE_LENGTH)
		MapParts.gate(folder, zone.id, startZ)
	end

	-- Walls along both sides, with gaps. Past the last zone's end, each player's device builds the endless repeat.
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = map
	MapParts.walls(walls, 0, Runway.LENGTH)
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
	buildRunway(map)

	map.Parent = Workspace

	Players.RespawnTime = Tuning.RESPAWN_TIME
	Lighting.ClockTime = 14
	Lighting.FogStart = FOG_START
	Lighting.FogEnd = FOG_END
	Lighting.FogColor = FOG_COLOR
end

function MapService.Start()
	watchForFalls()
end

return MapService
