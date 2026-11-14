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
-- page shows exactly the parts the game makes. Lighting, particles and the client's animations are left out.

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
		local lane = (random() * 2 - 1) * Runway.maxLateral(spec.halfLength)
		local path = Obstacles.planPath(lane, startZ, Runway.fadeZ(zoneId), spec.halfLength, spec.radius)
		local z = startZ + 40 + random() * (Runway.ZONE_LENGTH - 60)
		local x = Obstacles.lateralAt(path, z)
		local egg = EggRig.build(entry.egg, spec)
		local target = roblox.CFrame.new(x, Runway.BASE_Y + spec.radius, z)
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
	width = Runway.WIDTH,
	baseY = Runway.BASE_Y,
	zoneLength = Runway.ZONE_LENGTH,
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
