--!nocheck
-- Builds a web page that shows every egg model, and every pet model made so far, in 3D, so designs can be checked
-- without opening Studio.
-- From the repository root:
--     lune run tools/egg-gallery
-- writes tools/out/egg-gallery.html. Open it in a browser. Pass a path to write somewhere else, and add
-- --fragment to leave out the <!doctype>/<head> wrapper (for hosts that add their own).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local harness = require("../tests/harness")

local EggModels = harness.load("src/shared/EggModels")
local PetModels = harness.load("src/shared/PetModels")
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

local function exportBoxes(list)
	local boxes = {}
	for _, box in list do
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
	return boxes
end

local function describe(model, slot: number?)
	local zone = Zones.List[model.zone]
	return {
		kind = model.kind,
		zone = model.zone,
		zoneName = if zone then zone.name else "Shelved",
		slot = slot,
		rarity = model.rarity,
		shelved = model.shelved,
		name = model.name,
		hatches = model.hatches,
		stamina = if zone then zone.stamina[model.rarity] else nil,
		size = Rarities.Info[model.rarity].size,
		pet = PetModels.fromEgg(model.kind),
		boxes = exportBoxes(model.boxes),
		light = model.light and { color = hex(model.light.color), brightness = model.light.brightness },
		particles = model.particles and { color = hex(model.particles.color), style = model.particles.style },
	}
end

local pets = {}
for _, kind in PetModels.all() do
	local model = PetModels.get(kind)
	local limbs = {}
	for _, limb in model.limbs do
		table.insert(limbs, {
			name = limb.name,
			parent = limb.parent,
			pivot = limb.pivot,
			boxes = exportBoxes(limb.boxes),
		})
	end
	table.insert(pets, {
		kind = kind,
		name = model.name,
		zone = model.zone,
		rarity = model.rarity,
		skeleton = model.skeleton,
		gait = model.gait,
		scale = model.scale,
		size = model.size,
		center = model.center,
		limbs = limbs,
		light = model.light and { color = hex(model.light.color), brightness = model.light.brightness },
		particles = model.particles and { color = hex(model.particles.color), style = model.particles.style },
	})
end

local eggs = {}
local slots = {}
for _, entry in EggModels.lineup() do
	slots[entry.zone] = (slots[entry.zone] or 0) + 1
	table.insert(eggs, describe(EggModels.get(entry.kind), slots[entry.zone]))
end
for index, kind in EggModels.shelved() do
	table.insert(eggs, describe(EggModels.get(kind), index))
end

local zones = {}
for _, zone in Zones.List do
	table.insert(zones, { id = zone.id, name = zone.name, ground = hex(zone.ground), accent = hex(zone.accent) })
end
local rarities = {}
for _, rarity in Rarities.Order do
	table.insert(rarities, { name = rarity, color = hex(Rarities.Info[rarity].color) })
end

local data =
	serde.encode("json", { eggs = eggs, pets = pets, zones = zones, rarities = rarities, radius = EggModels.RADIUS })
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
print(`Wrote {#eggs} eggs ({#EggModels.shelved()} shelved) and {#pets} pets to {outPath}`)
