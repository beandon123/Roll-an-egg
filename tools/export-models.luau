--!nocheck
-- Exports every pet and egg in the game as Roblox model files, to insert into Roblox Studio.
--
-- From the repository root:
--     lune run tools/export-models
-- writes tools/out/RollAnEgg-Pets.rbxm and tools/out/RollAnEgg-Eggs.rbxm (pass a folder to write them somewhere
-- else). Each holds a folder per zone, in runway order, of models built by the game's own code (Shared/PetRig and
-- Shared/EggRig), so they are exactly what the game shows: pets rigged with a Motor6D per limb and their glow,
-- particles and fire; eggs at their size on the runway, stood up on end. Each is named after its pet or egg, and
-- they are laid out in rows, a zone to a row, standing on the ground at y = 0 (floating pets float above it, as they
-- do in the game).
--
-- In Studio: right-click Workspace (or ServerStorage) in the Explorer > Insert > Import Roblox Model, and pick a file
-- (older Studios call it Insert from File...). Or drag the file into the viewport.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Studio = require("../tests/studio")

local outDir = process.args[1] or "tools/out"
fs.writeDir(outDir)

local place, reason = Studio.buildPlace()
assert(place, `could not build the place: {reason}`)
local session = Studio.open(place, { isServer = true, isStudio = true })
local Shared = session:service("ReplicatedStorage").Shared
local PetRig = session:require(Shared.PetRig)
local EggRig = session:require(Shared.EggRig)
local EggModels = session:require(Shared.EggModels)
local EggSpec = session:require(Shared.EggSpec)
local Zones = session:require(Shared.Config.Zones)

local Instance, CFrame = roblox.Instance, roblox.CFrame

-- Gaps between models in a row, and between rows, in studs.
local GAP = 6
local ROW_GAP = 16

local function newFolder(name: string, parent: Instance?): Instance
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- The box round a model's visible parts (min and max corners, as { x, y, z }), measured from its root once the
-- model is turned by `turn`. Parts at an angle count by the box round them.
local function extents(model: Instance, turn: CFrame): ({ number }, { number })
	local fromRoot = turn * model.PrimaryPart.CFrame:Inverse()
	local low, high = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = (fromRoot * part.CFrame):GetComponents()
			local s = part.Size
			local half = {
				math.abs(r00) * s.X / 2 + math.abs(r01) * s.Y / 2 + math.abs(r02) * s.Z / 2,
				math.abs(r10) * s.X / 2 + math.abs(r11) * s.Y / 2 + math.abs(r12) * s.Z / 2,
				math.abs(r20) * s.X / 2 + math.abs(r21) * s.Y / 2 + math.abs(r22) * s.Z / 2,
			}
			for axis, centre in { x, y, z } do
				low[axis] = math.min(low[axis], centre - half[axis])
				high[axis] = math.max(high[axis], centre + half[axis])
			end
		end
	end
	return low, high
end

-- Moves a whole model so its root ends up at `target`, carrying every part with it (what Model:PivotTo does in
-- Roblox, done by hand so this tool does not depend on the test stand-in's version of it).
local function moveTo(model: Instance, target: CFrame)
	local move = target * model.PrimaryPart.CFrame:Inverse()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = move * part.CFrame
		end
	end
end

-- Lays out a zone's models in a row along +X, centred on depth z, each turned by `turn` and with its root at the
-- height `rootHeight` gives it, and returns how deep the row is.
local function layOut(
	models: { Instance },
	z: number,
	turn: CFrame,
	rootHeight: (Instance, { number }) -> number
): number
	local x, deepest = 0, 0
	for _, model in models do
		local low, high = extents(model, turn)
		moveTo(model, CFrame.new(x - low[1], rootHeight(model, low), z - (low[3] + high[3]) / 2) * turn)
		x += high[1] - low[1] + GAP
		deepest = math.max(deepest, high[3] - low[3])
	end
	return deepest
end

local function export(name: string, root: Instance)
	local path = `{outDir}/{name}`
	fs.writeFile(path, roblox.serializeModel({ root }))
	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Model") and descendant.Parent and descendant.Parent:IsA("Folder") then
			count += 1
		end
	end
	print(`Wrote {count} models to {path}`)
end

-- Pets: rigged, facing -Z, with their root at its height above the ground.
local pets = newFolder("Roll an Egg Pets")
local petZ = 0
for _, zone in Zones.List do
	local folder = newFolder(zone.name, pets)
	local row = {}
	for _, entry in zone.eggs do
		local pet = PetRig.build(entry.pet)
		if pet then
			pet.Parent = folder
			table.insert(row, pet)
		end
	end
	-- Each pet's root at its own height above the ground, so floating pets float as they do in the game.
	local deepest = layOut(row, petZ, CFrame.identity, function(pet)
		return pet:GetAttribute("GroundOffset")
	end)
	petZ -= deepest + ROW_GAP
end

-- Eggs: as they look on the runway, at their size for their zone and rarity, stood up on end to show them off.
local eggs = newFolder("Roll an Egg Eggs")
local eggZ = 0
for _, zone in Zones.List do
	local folder = newFolder(zone.name, eggs)
	local row = {}
	for _, entry in zone.eggs do
		local spec = EggSpec.get(zone.id, entry.rarity)
		local egg = EggRig.build(entry.egg, spec)
		egg.Name = EggModels.describe(entry.egg).name
		egg.Parent = folder
		table.insert(row, egg)
	end
	-- Stood up on end, pointed top upwards, resting on its lowest point.
	local deepest = layOut(row, eggZ, CFrame.Angles(0, 0, math.pi / 2), function(_, low)
		return -low[2]
	end)
	eggZ -= deepest + ROW_GAP
end

export("RollAnEgg-Pets.rbxm", pets)
export("RollAnEgg-Eggs.rbxm", eggs)
