-- Builds the placeholder hub from Shared/HubLayout: the grass plaza with invisible walls round it, the spawn, the
-- START ZONE pad where the runway leaves, the Trails stall, the Sell stall, the fuse machine, and the eight pens.
-- Final art will replace all of this; gameplay reads positions from HubLayout, never from these parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local HubLayout = require(Shared.HubLayout)
local Runway = require(Shared.Runway)
local Trails = require(Shared.Config.Trails)

local Build = require(script.Parent.Build)

local GROUND_THICKNESS = 4
local WALL_HEIGHT = 80

local GRASS = Color3.fromRGB(104, 186, 82)
local WOOD = Color3.fromRGB(150, 100, 60)
local LIGHT_WOOD = Color3.fromRGB(205, 155, 100)
local DARK_WOOD = Color3.fromRGB(115, 75, 45)
local WHITE = Color3.fromRGB(250, 250, 250)
local GOLD = Color3.fromRGB(240, 190, 50)

local TRAILS_COLOR = Color3.fromRGB(170, 95, 230)
local SELL_COLOR = Color3.fromRGB(230, 70, 70)
local FUSE_COLOR = Color3.fromRGB(245, 175, 30)

local Hub = {}

local Y = Runway.BASE_Y

-- A frame on the hub's ground at (x, z) whose front (-Z) faces `facing`.
local function groundFrame(x: number, z: number, facing: HubLayout.Point): CFrame
	local position = Vector3.new(x, Y, z)
	return CFrame.lookAt(position, position + Vector3.new(facing.x, 0, facing.z))
end

local function buildGround(hub: Instance)
	local ground = HubLayout.GROUND
	Build.part(hub, "Ground", {
		Size = Vector3.new(ground.sizeX, GROUND_THICKNESS, ground.sizeZ),
		Position = Vector3.new(ground.x, Y - GROUND_THICKNESS / 2, ground.z),
		Color = GRASS,
	})

	-- Invisible walls round the edge, open only where the runway leaves.
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = hub
	local half, length = HubLayout.HALF_WIDTH, HubLayout.LENGTH
	local gap = Runway.WIDTH / 2
	local wallY = Y + WALL_HEIGHT / 2
	local pieces = {
		Left = { Vector3.new(2, WALL_HEIGHT, length), Vector3.new(-half - 1, wallY, -length / 2) },
		Right = { Vector3.new(2, WALL_HEIGHT, length), Vector3.new(half + 1, wallY, -length / 2) },
		Back = { Vector3.new(half * 2 + 4, WALL_HEIGHT, 2), Vector3.new(0, wallY, -length - 1) },
		FrontLeft = { Vector3.new(half - gap, WALL_HEIGHT, 2), Vector3.new(-(half + gap) / 2, wallY, 1) },
		FrontRight = { Vector3.new(half - gap, WALL_HEIGHT, 2), Vector3.new((half + gap) / 2, wallY, 1) },
	}
	for name, piece in pieces do
		Build.part(walls, name, {
			Size = piece[1],
			Position = piece[2],
			Transparency = 1,
			CastShadow = false,
		})
	end

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "Spawn"
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.Size = Vector3.new(14, 1, 14)
	-- Players appear facing the runway.
	spawnPad.CFrame = groundFrame(HubLayout.SPAWN.x, HubLayout.SPAWN.z, { x = 0, z = 1 }) * CFrame.new(0, 0.5, 0)
	spawnPad.TopSurface = Enum.SurfaceType.Smooth
	spawnPad.Material = Enum.Material.SmoothPlastic
	spawnPad.Color = WHITE
	spawnPad.Parent = hub
end

local function buildStartZone(hub: Instance)
	local rect = HubLayout.START_ZONE
	local model = Instance.new("Model")
	model.Name = "StartZone"
	model.Parent = hub

	Build.part(model, "Pad", {
		Size = Vector3.new(rect.sizeX, 0.4, rect.sizeZ),
		Position = Vector3.new(rect.x, Y + 0.2, rect.z),
		Color = Color3.fromRGB(238, 224, 186),
	})
	for _, side in { -1, 1 } do
		Build.scenery(
			Build.disc(
				model,
				"Marker",
				CFrame.new(rect.x + side * (rect.sizeX / 2 - 8), Y + 0.45, rect.z),
				7,
				0.1,
				Color3.fromRGB(90, 200, 245)
			)
		)
	end

	-- "START ZONE" painted on the pad, readable from the hub. Text is drawn on a face that stands up from its part,
	-- so the label part lies on its back: its Front face points at the sky and its top edge toward the runway.
	local label = Build.scenery(Build.part(model, "Label", {
		Size = Vector3.new(rect.sizeX - 18, rect.sizeZ * 0.5, 0.1),
		CFrame = CFrame.fromMatrix(
			Vector3.new(rect.x, Y + 0.48, rect.z),
			Vector3.new(1, 0, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, -1, 0)
		),
		Transparency = 1,
	}))
	Build.signText(label, Enum.NormalId.Front, "START ZONE", nil, Color3.fromRGB(40, 40, 55))
end

-- A market stall: counter, back wall, four posts, and a striped canopy, with a floating sign and a ring on the
-- ground in front where players stand. Returns the model and its counter (which holds the prompt).
local function buildStall(parent: Instance, station: HubLayout.Station, color: Color3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = station.key
	model.Parent = parent
	local origin = groundFrame(station.x, station.z, station.facing)

	local counter = Build.part(model, "Counter", {
		Size = Vector3.new(14, 4, 4),
		CFrame = origin * CFrame.new(0, 2, -2),
		Color = WOOD,
	})
	Build.part(model, "CounterTop", {
		Size = Vector3.new(15, 0.6, 5),
		CFrame = origin * CFrame.new(0, 4.3, -2),
		Color = LIGHT_WOOD,
	})
	Build.part(model, "BackWall", {
		Size = Vector3.new(14, 7, 0.8),
		CFrame = origin * CFrame.new(0, 3.5, 3.8),
		Color = WOOD,
	})
	for _, corner in { { -7, -4.2 }, { 7, -4.2 }, { -7, 4.2 }, { 7, 4.2 } } do
		Build.part(model, "Post", {
			Size = Vector3.new(0.8, 11, 0.8),
			CFrame = origin * CFrame.new(corner[1], 5.5, corner[2]),
			Color = DARK_WOOD,
		})
	end

	local stripes = 7
	local stripeWidth = 15.4 / stripes
	local middleStripe: BasePart
	for index = 0, stripes - 1 do
		local stripe = Build.part(model, "Canopy", {
			Size = Vector3.new(stripeWidth, 0.5, 10.4),
			CFrame = origin * CFrame.new(-7.7 + stripeWidth * (index + 0.5), 11.25, 0),
			Color = if index % 2 == 0 then color else WHITE,
		})
		if index == stripes // 2 then
			middleStripe = stripe
		end
	end
	Build.nameTag(middleStripe, string.upper(station.name), color, 10, 2.6, 3.2)

	Build.scenery(Build.disc(model, "StandHere", origin * CFrame.new(0, 0.1, -9), 10, 0.2, color)).Transparency = 0.35

	Build.stationPrompt(counter, station.key, station.name, HubLayout.STATION_REACH)
	return model, counter
end

local function buildTrailsStall(stations: Instance)
	local station = HubLayout.STATIONS.Trails
	local model = buildStall(stations, station, TRAILS_COLOR)
	-- Glowing samples of the first few trails on the counter.
	local origin = groundFrame(station.x, station.z, station.facing)
	local samples = math.min(5, #Trails.List)
	for index = 1, samples do
		local trail = Trails.List[index]
		Build.scenery(Build.part(model, "Sample", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.2,
			CFrame = origin * CFrame.new(-5 + (index - 1) * 10 / math.max(1, samples - 1), 5.2, -2),
			Color = Build.rgb(trail.colors[1]),
			Material = Enum.Material.Neon,
		}))
	end
end

local function buildSellStall(stations: Instance)
	local station = HubLayout.STATIONS.Sell
	local model = buildStall(stations, station, SELL_COLOR)
	local origin = groundFrame(station.x, station.z, station.facing)
	-- A stack of coins and an egg on the counter.
	for level = 0, 2 do
		Build.scenery(Build.disc(model, "Coin", origin * CFrame.new(-4, 4.85 + level * 0.5, -2), 1.8, 0.45, GOLD))
	end
	local egg = Build.scenery(Build.part(model, "Egg", {
		Size = Vector3.new(1.8, 2.4, 1.8),
		CFrame = origin * CFrame.new(3.5, 5.8, -2),
		Color = WHITE,
	}))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg
end

-- The fuse machine: a golden mystery egg on a pedestal between four golden pillars, with three glowing pads in
-- front for the three pets that go in.
local function buildFuseMachine(stations: Instance)
	local station = HubLayout.STATIONS.Fuse
	local model = Instance.new("Model")
	model.Name = station.key
	model.Parent = stations
	local origin = groundFrame(station.x, station.z, station.facing)

	Build.disc(model, "Base", origin * CFrame.new(0, 1, 0), 20, 2, Color3.fromRGB(70, 72, 95))
	Build.disc(model, "Trim", origin * CFrame.new(0, 0.3, 0), 21, 0.6, GOLD)
	local pedestal = Build.disc(model, "Pedestal", origin * CFrame.new(0, 3.5, 0), 9, 3, GOLD)

	local egg = Build.part(model, "Egg", {
		Size = Vector3.new(6.4, 8.4, 6.4),
		CFrame = origin * CFrame.new(0, 9.2, 0),
		Color = Color3.fromRGB(255, 212, 70),
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 120)
	light.Range = 16
	light.Brightness = 1.5
	light.Parent = egg
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 230, 130))
	sparkles.LightEmission = 1
	sparkles.Rate = 4
	sparkles.Lifetime = NumberRange.new(1, 2)
	sparkles.Speed = NumberRange.new(1, 2)
	sparkles.Size = NumberSequence.new(0.4)
	sparkles.Parent = egg

	-- The "?" on the egg.
	local question = Instance.new("BillboardGui")
	question.Name = "Mystery"
	question.Size = UDim2.fromScale(4, 4)
	question.LightInfluence = 0
	question.MaxDistance = 200
	question.Parent = egg
	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.Font = Enum.Font.FredokaOne
	mark.Text = "?"
	mark.TextColor3 = Color3.fromRGB(120, 70, 10)
	mark.TextScaled = true
	mark.Parent = question

	for index = 0, 3 do
		local angle = math.pi / 4 + index * math.pi / 2
		local x, z = math.cos(angle) * 8, math.sin(angle) * 8
		Build.part(model, "Pillar", {
			Size = Vector3.new(1.4, 9, 1.4),
			CFrame = origin * CFrame.new(x, 6.5, z),
			Color = GOLD,
		})
		Build.scenery(Build.part(model, "Orb", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.8,
			CFrame = origin * CFrame.new(x, 11.9, z),
			Color = Color3.fromRGB(255, 235, 140),
			Material = Enum.Material.Neon,
		}))
	end

	for index = -1, 1 do
		Build.scenery(
			Build.disc(
				model,
				"PetPad",
				origin * CFrame.new(index * 5, 0.15, -13),
				3.6,
				0.3,
				Color3.fromRGB(175, 115, 255)
			)
		).Material =
			Enum.Material.Neon
	end

	Build.nameTag(egg, "FUSE", FUSE_COLOR, 7, 2.4, 7)
	Build.stationPrompt(pedestal, station.key, station.name, HubLayout.STATION_REACH)
end

-- A straight run of fence from `from` to `to` (on the ground): posts and two rails.
local function buildFence(parent: Instance, from: Vector3, to: Vector3)
	local offset = to - from
	local length = offset.Magnitude
	if length < 0.5 then
		return
	end
	local posts = math.max(1, math.ceil(length / 7))
	for index = 0, posts do
		Build.part(parent, "Post", {
			Size = Vector3.new(1, 5, 1),
			Position = from + offset * (index / posts) + Vector3.new(0, 2.5, 0),
			Color = DARK_WOOD,
		})
	end
	local middle = (from + to) / 2
	for _, height in { 1.7, 3.6 } do
		local center = middle + Vector3.new(0, height, 0)
		Build.part(parent, "Rail", {
			Size = Vector3.new(0.4, 0.5, length),
			CFrame = CFrame.lookAt(center, center + offset),
			Color = WOOD,
		})
	end
end

local function buildPen(parent: Instance, pen: HubLayout.Pen)
	local model = Instance.new("Model")
	model.Name = "Pen" .. pen.index
	model:SetAttribute("PenIndex", pen.index)
	model.Parent = parent

	Build.part(model, "Floor", {
		Size = Vector3.new(pen.sizeX, 0.4, pen.sizeZ),
		Position = Vector3.new(pen.x, Y + 0.2, pen.z),
		Color = Color3.fromRGB(214, 192, 140),
	})

	local minX, maxX, minZ, maxZ = HubLayout.bounds(pen :: any)
	local function corner(x: number, z: number): Vector3
		return Vector3.new(x, Y, z)
	end
	-- Each side, with the direction it faces out of the pen.
	local sides = {
		{ corner(maxX, minZ), corner(maxX, maxZ), 1, 0 },
		{ corner(minX, minZ), corner(minX, maxZ), -1, 0 },
		{ corner(minX, maxZ), corner(maxX, maxZ), 0, 1 },
		{ corner(minX, minZ), corner(maxX, minZ), 0, -1 },
	}
	local gateWidth = HubLayout.PEN_GATE_WIDTH
	for _, side in sides do
		local from, to = side[1], side[2]
		if side[3] == pen.gate.x and side[4] == pen.gate.z then
			-- The gate side: two runs of fence with a gap in the middle, under an arch with the pen's sign.
			local middle = (from + to) / 2
			local along = (to - from).Unit
			local gateA = middle - along * (gateWidth / 2)
			local gateB = middle + along * (gateWidth / 2)
			buildFence(model, from, gateA)
			buildFence(model, gateB, to)
			for _, gatePost in { gateA, gateB } do
				Build.part(model, "GatePost", {
					Size = Vector3.new(1.4, 9.6, 1.4),
					Position = gatePost + Vector3.new(0, 4.8, 0),
					Color = DARK_WOOD,
				})
			end
			local signCenter = middle + Vector3.new(0, 8.6, 0)
			local outward = Vector3.new(pen.gate.x, 0, pen.gate.z)
			local sign = Build.part(model, "Sign", {
				Size = Vector3.new(gateWidth + 3, 2.6, 0.5),
				CFrame = CFrame.lookAt(signCenter, signCenter + outward),
				Color = LIGHT_WOOD,
			})
			-- Front faces the plaza; Back faces into the pen.
			Build.signText(sign, Enum.NormalId.Front, `PEN {pen.index}`, nil, WHITE)
			Build.signText(sign, Enum.NormalId.Back, `PEN {pen.index}`, nil, WHITE)
		else
			buildFence(model, from, to)
		end
	end
end

-- Builds the hub under `map`. The whole hub is always streamed to every player, because players spawn there and
-- the stations and pens are used from there.
function Hub.build(map: Instance): Model
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	hub.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	buildGround(hub)
	buildStartZone(hub)

	local stations = Instance.new("Folder")
	stations.Name = "Stations"
	stations.Parent = hub
	buildTrailsStall(stations)
	buildSellStall(stations)
	buildFuseMachine(stations)

	local pens = Instance.new("Folder")
	pens.Name = "Pens"
	pens.Parent = hub
	for _, pen in HubLayout.PENS do
		buildPen(pens, pen)
	end

	hub.Parent = map
	return hub
end

return Hub
