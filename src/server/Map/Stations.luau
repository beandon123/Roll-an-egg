-- Builds the hub's stations from Shared/HubLayout: the Trails stall, the Sell stall, and the fuse machine. Each
-- has a ProximityPrompt that opens its panel on the player's device (Client/Controllers/StationController).
-- Placeholder art; gameplay reads positions from HubLayout, never from these parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local HubLayout = require(Shared.HubLayout)
local Runway = require(Shared.Runway)
local Trails = require(Shared.Config.Trails)

local Parts = require(script.Parent.Parts)

local WOOD = Color3.fromRGB(150, 100, 60)
local LIGHT_WOOD = Color3.fromRGB(205, 155, 100)
local DARK_WOOD = Color3.fromRGB(115, 75, 45)
local WHITE = Color3.fromRGB(250, 250, 250)
local GOLD = Color3.fromRGB(240, 190, 50)
local DOLLAR_GREEN = Color3.fromRGB(96, 206, 104)

local TRAILS_COLOR = Color3.fromRGB(170, 95, 230)
local SELL_COLOR = Color3.fromRGB(230, 70, 70)
local FUSE_COLOR = Color3.fromRGB(245, 175, 30)

local Stations = {}

local Y = Runway.BASE_Y

-- A frame on the hub's ground at (x, z) whose front (-Z) faces `facing`.
local function groundFrame(x: number, z: number, facing: HubLayout.Point): CFrame
	local position = Vector3.new(x, Y, z)
	return CFrame.lookAt(position, position + Vector3.new(facing.x, 0, facing.z))
end

-- A market stall: counter, back wall, four posts, and a striped canopy, with a floating sign and a ring on the
-- ground in front where players stand. Returns the model and its counter (which holds the prompt).
local function buildStall(parent: Instance, station: HubLayout.Station, color: Color3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = station.key
	model.Parent = parent
	local origin = groundFrame(station.x, station.z, station.facing)

	local counter = Parts.part(model, "Counter", {
		Size = Vector3.new(14, 4, 4),
		CFrame = origin * CFrame.new(0, 2, -2),
		Color = WOOD,
	})
	Parts.part(model, "CounterTop", {
		Size = Vector3.new(15, 0.6, 5),
		CFrame = origin * CFrame.new(0, 4.3, -2),
		Color = LIGHT_WOOD,
	})
	Parts.part(model, "BackWall", {
		Size = Vector3.new(14, 7, 0.8),
		CFrame = origin * CFrame.new(0, 3.5, 3.8),
		Color = WOOD,
	})
	for _, corner in { { -7, -4.2 }, { 7, -4.2 }, { -7, 4.2 }, { 7, 4.2 } } do
		Parts.part(model, "Post", {
			Size = Vector3.new(0.8, 11, 0.8),
			CFrame = origin * CFrame.new(corner[1], 5.5, corner[2]),
			Color = DARK_WOOD,
		})
	end

	local stripes = 7
	local stripeWidth = 15.4 / stripes
	local middleStripe: BasePart
	for index = 0, stripes - 1 do
		local stripe = Parts.part(model, "Canopy", {
			Size = Vector3.new(stripeWidth, 0.5, 10.4),
			CFrame = origin * CFrame.new(-7.7 + stripeWidth * (index + 0.5), 11.25, 0),
			Color = if index % 2 == 0 then color else WHITE,
		})
		if index == stripes // 2 then
			middleStripe = stripe
		end
	end
	Parts.nameTag(middleStripe, string.upper(station.name), color, 10, 2.6, 3.2)

	Parts.scenery(Parts.disc(model, "StandHere", origin * CFrame.new(0, 0.1, -9), 10, 0.2, color)).Transparency = 0.35

	Parts.stationPrompt(counter, station.key, station.name, HubLayout.STATION_REACH)
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
		Parts.scenery(Parts.part(model, "Sample", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.2,
			CFrame = origin * CFrame.new(-5 + (index - 1) * 10 / math.max(1, samples - 1), 5.2, -2),
			Color = Parts.rgb(trail.colors[1]),
			Material = Enum.Material.Neon,
		}))
	end
end

local function buildSellStall(stations: Instance)
	local station = HubLayout.STATIONS.Sell
	local model = buildStall(stations, station, SELL_COLOR)
	local origin = groundFrame(station.x, station.z, station.facing)
	-- A stack of dollar bills and an egg on the counter.
	for level = 0, 2 do
		Parts.scenery(Parts.part(model, "Bills", {
			Size = Vector3.new(2.6, 0.3, 1.3),
			CFrame = origin * CFrame.new(-4, 4.75 + level * 0.32, -2) * CFrame.Angles(0, level * 0.25, 0),
			Color = DOLLAR_GREEN,
		}))
	end
	local egg = Parts.scenery(Parts.part(model, "Egg", {
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

	Parts.disc(model, "Base", origin * CFrame.new(0, 1, 0), 20, 2, Color3.fromRGB(70, 72, 95))
	Parts.disc(model, "Trim", origin * CFrame.new(0, 0.3, 0), 21, 0.6, GOLD)
	local pedestal = Parts.disc(model, "Pedestal", origin * CFrame.new(0, 3.5, 0), 9, 3, GOLD)

	local egg = Parts.part(model, "Egg", {
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
		Parts.part(model, "Pillar", {
			Size = Vector3.new(1.4, 9, 1.4),
			CFrame = origin * CFrame.new(x, 6.5, z),
			Color = GOLD,
		})
		Parts.scenery(Parts.part(model, "Orb", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.8,
			CFrame = origin * CFrame.new(x, 11.9, z),
			Color = Color3.fromRGB(255, 235, 140),
			Material = Enum.Material.Neon,
		}))
	end

	for index = -1, 1 do
		Parts.scenery(
			Parts.disc(
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

	Parts.nameTag(egg, "FUSE", FUSE_COLOR, 7, 2.4, 7)
	Parts.stationPrompt(pedestal, station.key, station.name, HubLayout.STATION_REACH)
end

-- Builds the stations under `map`.
function Stations.build(map: Instance): Folder
	local stations = Instance.new("Folder")
	stations.Name = "Stations"
	buildTrailsStall(stations)
	buildSellStall(stations)
	buildFuseMachine(stations)
	stations.Parent = map
	return stations
end

return Stations
