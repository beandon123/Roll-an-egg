--!nocheck
-- Builds a web page that stands a zone's pets on a Roblox-like stage (grass, sky, a player for scale, glowing
-- Neon and the pets' flames, sparkles and auras), so a zone's pets can be checked without opening Studio.
-- From the repository root:
--     lune run tools/pet-preview [zone] [out path] [--fragment]
-- writes tools/out/pet-preview.html with every pet, or only the pets of zone 1-6 if one is given. With --split, the
-- pets go beside it in pet-data.json, which the page loads (for hosts that serve the two together). Open it in a
-- browser. The page takes a few settings after a `?` in its address, for pictures of one view: `pet=Bear` (one pet
-- close up), `move=Idle`, `yaw=` and `pitch=` (radians), `zoom=`, `fy=` (the height looked at, in studs) and `t=`
-- (seconds into the animation; holds still).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local harness = require("../tests/harness")

local PetModels = harness.load("src/shared/PetModels")
local PetAnimations = harness.load("src/shared/PetAnimations")
local PetWorth = harness.load("src/shared/PetWorth")
local NumberFormat = harness.load("src/shared/NumberFormat")
local Rarities = harness.load("src/shared/Config/Rarities")
local Zones = harness.load("src/shared/Config/Zones")

local templatePath = "tools/pet-preview.html"
local outPath = "tools/out/pet-preview.html"
local zoneFilter = nil
local fragment = false
local split = false
for _, arg in process.args do
	if arg == "--fragment" then
		fragment = true
	elseif arg == "--split" then
		split = true
	elseif tonumber(arg) then
		zoneFilter = tonumber(arg)
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
		local entry = {
			round(box.x),
			round(box.y),
			round(box.z),
			round(box.sx),
			round(box.sy),
			round(box.sz),
			hex(box.color),
			box.material,
			box.transparency,
			box.shape or "Block",
			false,
		}
		if box.rotation then
			entry[11] = {}
			for index, value in box.rotation do
				entry[11][index] = round(value)
			end
		end
		table.insert(boxes, entry)
	end
	return boxes
end

local pets = {}
for _, kind in PetModels.all() do
	local model = PetModels.get(kind)
	if zoneFilter == nil or model.zone == zoneFilter then
		local limbs = {}
		local parts = 0
		for _, limb in model.limbs do
			parts += #limb.boxes
			table.insert(limbs, {
				name = limb.name,
				parent = limb.parent,
				pivot = limb.pivot,
				boxes = exportBoxes(limb.boxes),
			})
		end
		local fires = {}
		for _, fire in model.fires do
			table.insert(fires, {
				limb = fire.limb,
				position = fire.position,
				size = fire.size,
				color = hex(fire.color),
				secondary = hex(fire.secondary),
			})
		end
		local income = PetWorth.income({ zone = model.zone, rarity = model.rarity, variant = "Normal" })
		table.insert(pets, {
			kind = kind,
			name = model.name,
			zone = model.zone,
			rarity = model.rarity,
			rarityColor = hex(Rarities.Info[model.rarity].color),
			income = "$" .. NumberFormat.abbreviate(income) .. "/s",
			skeleton = model.skeleton,
			gait = model.gait,
			hover = model.hover,
			scale = model.scale,
			wingSpread = model.wingSpread,
			moveNames = PetAnimations.movesOf(model.skeleton),
			move = PetAnimations.defaultMove(model.skeleton, model.gait),
			size = model.size,
			center = model.center,
			seat = model.seat,
			parts = parts,
			limbs = limbs,
			fires = fires,
			aura = model.aura and { color = hex(model.aura.color), accent = hex(model.aura.accent) },
			light = model.light and { color = hex(model.light.color), brightness = model.light.brightness },
			particles = model.particles and { color = hex(model.particles.color), style = model.particles.style },
		})
	end
end

local zones = {}
for _, zone in Zones.List do
	table.insert(zones, { id = zone.id, name = zone.name, ground = hex(zone.ground), accent = hex(zone.accent) })
end

local data = serde.encode("json", { pets = pets, zones = zones, zone = zoneFilter, moves = PetAnimations.MOVES })
local template = fs.readFile(templatePath)
local zoneInfo = zoneFilter and Zones.List[zoneFilter]
local page = template
if not split then
	page = string.gsub(template, "/%*PET_DATA%*/null", function()
		return data
	end)
end
page = string.gsub(page, "/%*PET_TITLE%*/Pet Lineup", if zoneInfo then zoneInfo.name .. " Pets" else "Pet Lineup")
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
if split then
	fs.writeFile((folder or ".") .. "/pet-data.json", data)
end
print(`Wrote {#pets} pets to {outPath}`)
