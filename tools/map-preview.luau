--!nocheck
-- Builds a web page that shows the map in 3D (the runway, banks, backdrops, obstacles, and a few eggs rolling down
-- it), so the look of each zone can be checked without opening Studio.
--
-- From the repository root:
--     lune run tools/map-preview
-- writes tools/out/map-preview.html. Open it in a browser and drag to look round. Pass a path to write somewhere
-- else. The page reads its camera from the address: map-preview.html#zone=3 looks down the Snow zone, and
-- #cam=x,y,z,tx,ty,tz puts the camera at x,y,z looking at tx,ty,tz.
--
-- It runs the game's own MapService in the Studio stand-in (tests/studio) and copies every part it builds, so the
-- page shows exactly the parts the game makes, in the game's fog by day. Lighting, particles and the client's
-- animations are left out. Each plot's training stick shows a different tier (plot 1 the first, plot 8 the last), and
-- a few have a blocky player rolling on them, posed the way the game poses riders.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")

local Studio = require("../tests/studio")

local outPath = process.args[1] or "tools/out/map-preview.html"

local place, reason = Studio.buildPlace()
assert(place, `could not build the place: {reason}`)
local session = Studio.open(place, { isServer = true, isStudio = true })
session:useFakeProfileStore()
local Shared = session:service("ReplicatedStorage").Shared
local Server = session:service("ServerScriptService").Server
local MapService = session:require(Server.Services.MapService)
local EggRig = session:require(Shared.EggRig)
local EggSpec = session:require(Shared.EggSpec)
local Obstacles = session:require(Shared.Obstacles)
local Runway = session:require(Shared.Runway)
local Zones = session:require(Shared.Config.Zones)

MapService.Init()
local PlotService = session:require(Server.Services.PlotService)
PlotService.Init()
session:require(Server.Services.LeaderboardService).Init()
local workspace = session:service("Workspace")

-- A few eggs on the runway, each where its path round the obstacles has taken it.
local eggFolder = roblox.Instance.new("Folder")
eggFolder.Name = "PreviewEggs"
eggFolder.Parent = workspace
local seed = 7
local function random()
	seed = (seed * 16807) % 2147483647
	return seed / 2147483647
end
for zoneId, zone in Zones.List do
	for index = 1, 6 do
		local entry = zone.eggs[(index * 3) % #zone.eggs + 1]
		local spec = EggSpec.get(zoneId, entry.rarity)
		local startZ = Runway.zoneStartZ(zoneId) + 12
		local low, high = Runway.lateralRange(spec.halfLength, startZ)
		local lane = low + random() * (high - low)
		local path = Obstacles.planPath(lane, startZ, Runway.fadeZ(zoneId), spec.halfLength, spec.radius)
		local z = startZ + 40 + random() * (Runway.zoneLength(zoneId) - 60)
		local x = Runway.worldX(Obstacles.lateralAt(path, z), z)
		local egg = EggRig.build(entry.egg, spec)
		local target = roblox.CFrame.new(x, Runway.BASE_Y + spec.radius, z)
			* roblox.CFrame.Angles(0, Runway.heading(z), 0)
			* roblox.CFrame.Angles(random() * 6, 0, 0)
			* (if index % 2 == 0 then roblox.CFrame.Angles(0, math.pi, 0) else roblox.CFrame.identity)
		local move = target * egg.PrimaryPart.CFrame:Inverse()
		for _, part in egg:GetDescendants() do
			if part:IsA("BasePart") then
				part.CFrame = move * part.CFrame
			end
		end
		egg.Parent = eggFolder
	end
end

-- Two plots dressed as if their owners were playing: an egg in each nest and pets in the pen.
local PlotModels = session:require(Server.Map.PlotModels)
local PetRig = session:require(Shared.PetRig)
local Plots = session:require(Shared.Plots)
local function moveModel(model, target)
	local move = target * model.PrimaryPart.CFrame:Inverse()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = move * part.CFrame
		end
	end
end
local showcase = {
	{
		plot = 2,
		level = 1,
		eggs = { { "Toadstool", 12, -18 }, { "MossStag", 26, 14 } },
		pets = {
			{ "Bear", "Gold" },
			{ "Fox", "Normal" },
			{ "Owl", "Silver" },
			{ "MossStag", "Normal" },
			{ "Bunny", "Rainbow" },
		},
	},
	{
		plot = 6,
		level = 5,
		eggs = { { "Sphinx", 14, 20 }, { "Yeti", 40, -10 }, { "FrostWolf", 70, 24 } },
		pets = {
			{ "Camel", "Normal" },
			{ "SabertoothCat", "Gold" },
			{ "WoollyMammoth", "Normal" },
			{ "Meerkat", "Rainbow" },
			{ "Reindeer", "Silver" },
			{ "Yeti", "Normal" },
		},
	},
}
for _, entry in showcase do
	local plot = workspace.Map.Plots["Plot" .. entry.plot]
	PlotModels.signText(plot.Sign, "Player's Pen")
	PlotModels.sizePen(plot, entry.plot, entry.level)
	for index, egg in entry.eggs do
		local model = PlotModels.buildEgg(plot.Eggs, entry.plot, {
			uid = "preview" .. index,
			kind = egg[1],
			rarity = "Rare",
			placedAt = 0,
			bonus = 0,
			inward = egg[2],
			along = egg[3],
		})
		model.Parent = eggFolder
	end
	for index, pair in entry.pets do
		local pet = PetRig.build(pair[1], pair[2])
		local root = pet.PrimaryPart
		local reach = math.max(root.Size.X, root.Size.Z) / 2 + 1
		local x0, x1, z0, z1 = Plots.roamArea(entry.plot, entry.level, reach)
		local t = (index - 0.5) / #entry.pets
		local x = x0 + (x1 - x0) * (if index % 2 == 0 then 0.3 else 0.75)
		local z = z0 + (z1 - z0) * t
		moveModel(
			pet,
			roblox.CFrame.new(x, Runway.BASE_Y + 0.4 + pet:GetAttribute("GroundOffset"), z)
				* roblox.CFrame.Angles(0, random() * 6, 0)
		)
		pet.Parent = eggFolder
	end
end

-- Every tier of the training stick, one on each plot's stand: plot 1 has the first tier, plot 8 the last.
local TrainingStand = session:require(Server.Map.TrainingStand)
local StickModels = session:require(Shared.StickModels)
local RiderPose = session:require(Shared.RiderPose)
local Sticks = session:require(Shared.Config.Sticks)
for index = 1, Plots.COUNT do
	TrainingStand.setLevel(workspace.Map.Plots["Plot" .. index].TrainingStick, index, index)
end

-- A blocky player rolling on some of them, posed the way RiderAnimationController poses a real R15 character (from
-- Shared/RiderPose), each caught at a different moment of their stride. The roller is turned to match.
local function addRider(index: number, stride: number)
	local level = index
	local angle = stride * 0.7
	local stand = workspace.Map.Plots["Plot" .. index].TrainingStick
	local roller = stand.Roller
	moveModel(roller, StickModels.axleCFrame(index, level) * StickModels.spin(angle))
	local pose = RiderPose.pose({
		phase = stride,
		time = stride * 0.4,
		pace = Sticks.RUN_PACE,
		steer = 0,
		tired = 0,
		cheer = 0,
	})
	local function turn(name)
		local p = pose[name]
		return roblox.CFrame.fromEulerAnglesYXZ(p[1], p[2], p[3])
	end
	local drop = Sticks.maxTop(level) - Sticks.topHeight(level, angle)
	local root = StickModels.riderCFrame(index, level, 3) * roblox.CFrame.new(0, pose.Root[5] - drop, 0)
	local shirt, skin, pants = { 70, 130, 230 }, { 250, 210, 160 }, { 50, 60, 90 }
	local function limb(name, cframe, size, color)
		local part = roblox.Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Size = roblox.Vector3.new(size[1], size[2], size[3])
		part.CFrame = cframe
		part.Color = roblox.Color3.fromRGB(color[1], color[2], color[3])
		part.Parent = eggFolder
	end
	local lower = root * roblox.CFrame.new(0, -0.2, 0) * turn("Root")
	limb("LowerTorso", lower * roblox.CFrame.new(0, -0.2, 0), { 2, 0.4, 1 }, pants)
	local waist = lower * turn("Waist")
	limb("UpperTorso", waist * roblox.CFrame.new(0, 0.8, 0), { 2, 1.6, 1 }, shirt)
	limb(
		"Head",
		waist * roblox.CFrame.new(0, 1.6, 0) * turn("Neck") * roblox.CFrame.new(0, 0.6, 0),
		{ 1.2, 1.2, 1.2 },
		skin
	)
	for _, side in { "Left", "Right" } do
		local sign = if side == "Left" then -1 else 1
		local hip = lower * roblox.CFrame.new(sign * 0.5, -0.4, 0) * turn(side .. "Hip")
		limb(side .. "UpperLeg", hip * roblox.CFrame.new(0, -0.52, 0), { 0.95, 1.05, 0.95 }, pants)
		local knee = hip * roblox.CFrame.new(0, -1.05, 0) * turn(side .. "Knee")
		limb(side .. "LowerLeg", knee * roblox.CFrame.new(0, -0.52, 0), { 0.9, 1.05, 0.9 }, pants)
		local ankle = knee * roblox.CFrame.new(0, -1.05, 0) * turn(side .. "Ankle")
		limb(side .. "Foot", ankle * roblox.CFrame.new(0, -0.15, -0.15), { 0.95, 0.3, 1.2 }, { 40, 40, 50 })
		local shoulder = waist * roblox.CFrame.new(sign * 1.5, 1.35, 0) * turn(side .. "Shoulder")
		limb(side .. "UpperArm", shoulder * roblox.CFrame.new(0, -0.5, 0), { 0.95, 1.1, 0.95 }, shirt)
		local elbow = shoulder * roblox.CFrame.new(0, -1, 0) * turn(side .. "Elbow")
		limb(side .. "LowerArm", elbow * roblox.CFrame.new(0, -0.55, 0), { 0.9, 1.1, 0.9 }, skin)
	end
end
addRider(2, 1.1)
addRider(3, 2.6)
addRider(6, 0.3)
addRider(8, 4)

local function round(value: number): number
	return math.round(value * 1000) / 1000
end

local parts = {}
local function collect(root)
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local shape = "Block"
			if part:IsA("WedgePart") then
				shape = "Wedge"
			elseif part:IsA("Part") then
				shape = part.Shape.Name
			end
			local components = { part.CFrame:GetComponents() }
			local entry = { shape }
			for _, value in components do
				table.insert(entry, round(value))
			end
			local color = part.Color
			table.insert(entry, round(part.Size.X))
			table.insert(entry, round(part.Size.Y))
			table.insert(entry, round(part.Size.Z))
			table.insert(
				entry,
				string.format(
					"#%02x%02x%02x",
					math.round(color.R * 255),
					math.round(color.G * 255),
					math.round(color.B * 255)
				)
			)
			table.insert(entry, part.Material.Name)
			table.insert(entry, round(part.Transparency))
			table.insert(parts, entry)
		end
	end
end
collect(workspace.Map)
collect(eggFolder)

local zones = {}
for _, zone in Zones.List do
	table.insert(zones, { id = zone.id, name = zone.name, startZ = Runway.zoneStartZ(zone.id) })
end

local data = serde.encode("json", {
	parts = parts,
	zones = zones,
	widths = (function()
		local widths = {}
		for zoneId = 1, Runway.ZONE_COUNT do
			table.insert(widths, Runway.zoneWidth(zoneId))
		end
		return widths
	end)(),
	baseY = Runway.BASE_Y,
	zoneLengths = Runway.ZONE_LENGTHS,
	-- The game's fog by day (MapService), drawn the same way: linear from FogStart to FogEnd.
	fog = (function()
		local lighting = session:service("Lighting")
		local color = lighting.FogColor
		return {
			start = lighting.FogStart,
			finish = lighting.FogEnd,
			color = string.format("#%02x%02x%02x", color.R * 255 + 0.5, color.G * 255 + 0.5, color.B * 255 + 0.5),
		}
	end)(),
})
local template = fs.readFile("tools/map-preview.html")
local page = string.gsub(template, "/%*MAP_DATA%*/null", function()
	return data
end)
local folder = string.match(outPath, "^(.*)/[^/]+$")
if folder and not fs.isDir(folder) then
	fs.writeDir(folder)
end
fs.writeFile(outPath, page)
print(`Wrote {#parts} parts to {outPath}`)
