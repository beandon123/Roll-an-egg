--!nocheck
-- Builds a web page that shows every egg model in 3D, so designs can be checked without opening Studio.
-- From the repository root:
--     lune run tools/egg-gallery
-- writes tools/out/egg-gallery.html. Open it in a browser. Pass a path to write somewhere else, and add
-- --fragment to leave out the <!doctype>/<head> wrapper (for hosts that add their own).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local harness = require("../tests/harness")

local EggModels = harness.load("src/shared/EggModels")
local Rarities = harness.load("src/shared/Config/Rarities")
local Zones = harness.load("src/shared/Config/Zones")

local outPath = "tools/out/egg-gallery.html"
local fragment = false
for _, arg in process.args do
	if arg == "--fragment" then
		fragment = true
	else
		outPath = arg
	end
end

local function hex(color): string
	return string.format("#%02x%02x%02x", color[1], color[2], color[3])
end

local function round(value: number): number
	return math.round(value * 1000) / 1000
end

local eggs = {}
for _, entry in EggModels.all() do
	local model = EggModels.get(entry.zone, entry.rarity)
	local zone = Zones.List[entry.zone]
	local boxes = {}
	for _, box in model.boxes do
		table.insert(boxes, {
			round(box.x),
			round(box.y),
			round(box.z),
			round(box.sx),
			round(box.sy),
			round(box.sz),
			hex(box.color),
			box.material,
			box.transparency,
		})
	end
	table.insert(eggs, {
		zone = entry.zone,
		zoneName = zone.name,
		rarity = entry.rarity,
		name = model.name,
		hatches = model.hatches,
		stamina = zone.stamina[entry.rarity],
		size = Rarities.Info[entry.rarity].size,
		boxes = boxes,
		light = model.light and { color = hex(model.light.color), brightness = model.light.brightness },
		particles = model.particles and { color = hex(model.particles.color), style = model.particles.style },
	})
end

local zones = {}
for _, zone in Zones.List do
	table.insert(zones, { id = zone.id, name = zone.name, ground = hex(zone.ground), accent = hex(zone.accent) })
end
local rarities = {}
for _, rarity in Rarities.Order do
	table.insert(rarities, { name = rarity, color = hex(Rarities.Info[rarity].color) })
end

local data = serde.encode("json", { eggs = eggs, zones = zones, rarities = rarities, radius = EggModels.RADIUS })
local template = fs.readFile("tools/egg-gallery.html")
local page = string.gsub(template, "/%*EGG_DATA%*/null", function()
	return data
end)
if not fragment then
	page = '<!doctype html>\n<html lang="en">\n<meta charset="utf-8">\n'
		.. '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
		.. page
		.. "\n</html>\n"
end

local folder = string.match(outPath, "^(.*)/[^/]+$")
if folder and not fs.isDir(folder) then
	fs.writeDir(folder)
end
fs.writeFile(outPath, page)
print(`Wrote {#eggs} eggs to {outPath}`)
