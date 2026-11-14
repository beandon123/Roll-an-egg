-- Builds the scenery round the hub: the ground beyond its walls and the terraced cliffs from Shared/HubLayout,
-- steps of pale stone with thick grass on top, climbing away from the hub in five tiers, with grass hanging over
-- their edges and bushes, rocks and trees on the ledges. The cliffs are solid, but gameplay never reads them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local HubLayout = require(Shared.HubLayout)
local Runway = require(Shared.Runway)

local Build = require(script.Parent.Build)
local Scenery = require(script.Parent.Scenery)

local block, vary, between, pick = Build.block, Build.vary, Build.between, Build.pick

local M = Enum.Material

-- Pale stone faces, a shade darker on the lower steps, under bright grass.
local STONE = { 182, 186, 178 }
local GRASS = { 104, 188, 72 }
local GRASS_DARK = { 82, 158, 58 }
local OUTER_GROUND = { 88, 160, 76 }

-- How thick the grass on top of each step is, and how far it hangs out over the face.
local GRASS_THICKNESS = 2
local GRASS_OVERHANG = 0.8
-- How far below the hub's ground each step is buried, so no gap ever shows at its foot.
local BURY = 6

-- What grows on each tier's ledge: the chance a block gets something, and what it may be.
local DRESSING = {
	{ chance = 0.14, props = { { "Bush", 3.2 }, { "Flowers", 3.5 }, { "Boulder", 3.6 } } },
	{ chance = 0.16, props = { { "Bush", 3.6 }, { "Boulder", 4 }, { "Flowers", 4 } } },
	{ chance = 0.2, props = { { "Oak", 3.2 }, { "Bush", 4 }, { "ForestPine", 3.6 } } },
	{ chance = 0.22, props = { { "ForestPine", 4 }, { "Oak", 3.6 }, { "Boulder", 5 } } },
	{ chance = 0.34, props = { { "ForestPine", 4.6 }, { "Oak", 4.2 }, { "ForestPine", 5.2 } } },
}

local Cliffs = {}

-- One step: its stone, the grass on top, now and then grass hanging down its face, and maybe a prop on top.
local function buildTerrace(parent: Instance, terrace: HubLayout.Terrace)
	local random = Build.random(terrace.seed + 1)
	local frame = CFrame.new(terrace.x, Runway.BASE_Y, terrace.z) * CFrame.Angles(0, terrace.yaw, 0)
	local top = terrace.height
	local faceHeight = top - GRASS_THICKNESS + BURY

	-- The stone, a little lighter or darker block to block so the steps read as separate stones.
	block(
		parent,
		Vector3.new(terrace.length, faceHeight, terrace.depth),
		frame * CFrame.new(0, -BURY + faceHeight / 2, 0),
		vary(random, Build.shade(STONE, -0.035 * (terrace.tier - 1)), 0.05),
		{ material = M.Slate }
	).Name =
		"Stone"
	-- The grass, hanging out over the front (the side facing the hub, -Z) a little.
	block(
		parent,
		Vector3.new(terrace.length + 0.3, GRASS_THICKNESS, terrace.depth + GRASS_OVERHANG),
		frame * CFrame.new(0, top - GRASS_THICKNESS / 2, -GRASS_OVERHANG / 2),
		vary(random, GRASS, 0.04),
		{ material = M.Grass }
	).Name =
		"Grass"

	-- Tufts of grass hanging down the face.
	local front = -terrace.depth / 2 - GRASS_OVERHANG / 2
	for _ = 1, if random() < 0.55 then math.floor(between(random, 1, 3.99)) else 0 do
		local width = between(random, 1.6, 3.4)
		local drop = math.min(between(random, 2, 7), faceHeight - BURY - GRASS_THICKNESS - 1)
		if drop > 1 then
			local along = between(random, -terrace.length / 2 + width, terrace.length / 2 - width)
			block(
				parent,
				Vector3.new(width, drop, 0.6),
				frame * CFrame.new(along, top - GRASS_THICKNESS - drop / 2 + 0.2, front),
				vary(random, GRASS_DARK, 0.06),
				{ material = M.Grass, collide = false }
			).Name =
				"Hanging"
		end
	end

	local dressing = DRESSING[terrace.tier]
	if random() < dressing.chance then
		local choice = pick(random, dressing.props)
		local size = choice[2] * between(random, 0.85, 1.2)
		local roomAlong = math.max(0, terrace.length / 2 - size - 1)
		local roomOut = math.max(0, terrace.depth / 2 - size - 2)
		if roomOut > 0 or terrace.depth > size * 2 + 2 then
			local spot = frame
				* CFrame.new(between(random, -roomAlong, roomAlong), top, between(random, -roomOut, roomOut))
				* CFrame.Angles(0, random() * math.pi * 2, 0)
			Scenery.buildProp(parent, choice[1], spot, size, random)
		end
	end
end

function Cliffs.build(map: Instance): Folder
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"

	-- Just below the hub's surface, so the two never flicker where they overlap.
	local outer = HubLayout.OUTER_GROUND
	block(
		scenery,
		Vector3.new(outer.sizeX, 4, outer.sizeZ),
		CFrame.new(outer.x, Runway.BASE_Y - 0.3 - 2, outer.z),
		OUTER_GROUND,
		{ material = M.Grass }
	).Name =
		"OuterGround"

	local folder = Instance.new("Folder")
	folder.Name = "Cliffs"
	folder.Parent = scenery
	-- One model per column of steps, streamed in whole.
	local column: Model? = nil
	for index, terrace in HubLayout.TERRACES do
		if terrace.tier == 1 or column == nil then
			column = Instance.new("Model")
			assert(column)
			column.Name = "Cliff" .. index
			column.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			column.Parent = folder
		end
		buildTerrace(column :: Model, terrace)
	end

	scenery.Parent = map
	return scenery
end

return Cliffs
