-- Builds each zone's stretch of runway and everything around it, in the blocky style of the eggs and pets. The
-- runway winds (Shared/Runway), and everything along it follows its bends. Each zone is also longer and wider than
-- the one before, so the banks step out at every gate:
--     Ground    the level runway, checkered in the zone's colours, blending into the next zone over its last rows
--     Banks     tall stepped cliffs up both sides, like a canyon: stone capped with the zone's grass (or sand, snow,
--               rock) hanging over the edges, with the zone's plants and rocks on the ledges. Gaps in them look out
--               over a valley, with a low railing across (the Ocean zone is a boardwalk over a reef instead, with
--               rope railings along its edges)
--     Backdrop  big blocky hills, mesas, mountains or volcanoes in the distance
--     Gate      an arch over the start of the zone with its name and the stamina its eggs need
--     Repeats   the last zone again past the end of the runway, which never ends (Shared/Runway)
-- Nothing here affects play: eggs and obstacles are worked out from Shared/Runway and Shared/Obstacles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local NumberFormat = require(Shared.NumberFormat)
local Rarities = require(Shared.Config.Rarities)
local Runway = require(Shared.Runway)
local Zones = require(Shared.Config.Zones)

local Build = require(script.Parent.Build)
local ObstacleModels = require(script.Parent.ObstacleModels)

local block, ball, column = Build.block, Build.ball, Build.column
local shade, vary, between, pick = Build.shade, Build.vary, Build.between, Build.pick

type Rgb = Build.Rgb
type Random = Build.Random

local M = Enum.Material

local TILE = 20
local SLAB = 4
-- Where a zone's banks begin: the runway's edge plus a kerb (the gate's posts stand just beyond it).
local function edgeOf(zoneId: number): number
	return Runway.zoneWidth(zoneId) / 2 + 1
end

-- How much further out from the centre line a zone's backdrop stands than the first zone's does.
local function spreadOf(zoneId: number): number
	return (Runway.zoneWidth(zoneId) - Runway.START_WIDTH) / 2
end

-- The Ocean's railing: how tall its posts stand, the heights of its ropes, and the invisible wall behind it.
local RAILING_HEIGHT = 7
local ROPE_HEIGHTS = { 2.4, 4.2, 6 }
local SEA_WALL_HEIGHT = 40

export type Prop = { kind: string, weight: number, size: number? }

export type Palette = {
	ground: { Rgb },
	groundMaterial: Enum.Material,
	kerb: Rgb,
	cliff: Rgb,
	cliffMaterial: Enum.Material,
	-- Optional stripes across the cliff faces (desert sandstone).
	bands: { Rgb }?,
	top: Rgb,
	topMaterial: Enum.Material,
	backdrop: Rgb,
	backdropTop: Rgb?,
	props: { Prop },
	-- The Ocean zone's sea, in place of banks.
	sea: boolean?,
	-- Lava rivers along the Volcano's banks, and lava falling down its cliffs.
	lava: boolean?,
}

local PALETTES: { Palette } = {
	{ -- Forest: pale stone cliffs under thick grass, like the cliffs round the hub
		ground = { { 104, 178, 76 }, { 90, 162, 66 } },
		groundMaterial = M.Grass,
		kerb = { 150, 120, 84 },
		cliff = { 182, 186, 178 },
		cliffMaterial = M.Slate,
		top = { 104, 188, 72 },
		topMaterial = M.Grass,
		backdrop = { 70, 132, 70 },
		props = {
			{ kind = "Oak", weight = 5, size = 3.2 },
			{ kind = "ForestPine", weight = 3, size = 4 },
			{ kind = "Bush", weight = 4, size = 3.6 },
			{ kind = "Boulder", weight = 2, size = 4.5 },
			{ kind = "Toadstools", weight = 2, size = 3 },
			{ kind = "Flowers", weight = 4, size = 4 },
		},
	},
	{ -- Desert
		ground = { { 236, 210, 146 }, { 224, 194, 128 } },
		groundMaterial = M.Sand,
		kerb = { 196, 136, 84 },
		cliff = { 206, 148, 92 },
		cliffMaterial = M.Sandstone,
		bands = { { 214, 156, 98 }, { 194, 132, 82 }, { 226, 174, 114 } },
		top = { 236, 210, 150 },
		topMaterial = M.Sand,
		backdrop = { 210, 140, 86 },
		props = {
			{ kind = "Cactus", weight = 5, size = 2.6 },
			{ kind = "Sandstone", weight = 3, size = 5 },
			{ kind = "Palm", weight = 2, size = 4 },
			{ kind = "Skull", weight = 1, size = 3 },
			{ kind = "Tumbleweed", weight = 2, size = 2.2 },
		},
	},
	{ -- Snow
		ground = { { 244, 248, 254 }, { 214, 228, 246 } },
		groundMaterial = M.Snow,
		kerb = { 140, 178, 214 },
		cliff = { 132, 152, 176 },
		cliffMaterial = M.Slate,
		top = { 246, 250, 255 },
		topMaterial = M.Snow,
		backdrop = { 150, 168, 196 },
		backdropTop = { 248, 250, 255 },
		props = {
			{ kind = "Pine", weight = 7, size = 4 },
			{ kind = "IceBoulder", weight = 2, size = 4.5 },
			{ kind = "IceCrystal", weight = 2, size = 3 },
			{ kind = "Snowdrift", weight = 2, size = 6 },
			{ kind = "Snowman", weight = 1, size = 2.8 },
		},
	},
	{ -- Ocean: a boardwalk over a reef
		ground = { { 184, 140, 94 }, { 166, 124, 82 } },
		groundMaterial = M.WoodPlanks,
		kerb = { 120, 86, 56 },
		cliff = { 220, 206, 160 },
		cliffMaterial = M.Sand,
		top = { 232, 220, 176 },
		topMaterial = M.Sand,
		backdrop = { 96, 150, 120 },
		sea = true,
		props = {
			{ kind = "Coral", weight = 5, size = 4.5 },
			{ kind = "SeaRock", weight = 4, size = 7 },
			{ kind = "Islet", weight = 3, size = 8 },
			{ kind = "Buoy", weight = 2, size = 1.4 },
		},
	},
	{ -- Volcano
		ground = { { 82, 66, 66 }, { 62, 52, 56 } },
		groundMaterial = M.Basalt,
		lava = true,
		kerb = { 110, 46, 30 },
		cliff = { 56, 50, 56 },
		cliffMaterial = M.Basalt,
		top = { 84, 76, 80 },
		topMaterial = M.CrackedLava,
		backdrop = { 60, 50, 54 },
		props = {
			{ kind = "Basalt", weight = 4, size = 4.5 },
			{ kind = "MagmaRock", weight = 3, size = 4 },
			{ kind = "ObsidianSpikes", weight = 3, size = 3.2 },
			{ kind = "LavaPool", weight = 2, size = 6 },
		},
	},
	{ -- Prehistoric: grey stone under deep teal-green grass
		ground = { { 132, 156, 82 }, { 118, 142, 72 } },
		groundMaterial = M.Grass,
		kerb = { 120, 92, 62 },
		cliff = { 160, 164, 156 },
		cliffMaterial = M.Slate,
		top = { 62, 160, 120 },
		topMaterial = M.Grass,
		backdrop = { 84, 112, 70 },
		props = {
			{ kind = "Fern", weight = 5, size = 4 },
			{ kind = "Cycad", weight = 4, size = 4 },
			{ kind = "MossyBoulder", weight = 2, size = 4.5 },
			{ kind = "Ribcage", weight = 1, size = 6 },
			{ kind = "TreeFern", weight = 3, size = 3 },
		},
	},
}

----------------------------------------------------------------------------------------------------------------
-- Scenery pieces that are not runway obstacles

local extras: { [string]: (model: Model, base: CFrame, size: number, random: Random) -> () } = {}

extras.ForestPine = function(model, base, size, random)
	ObstacleModels.pine(model, base, size, random, 6, false)
end

extras.Flowers = function(model, base, size, random)
	local colors = { { 250, 220, 60 }, { 250, 120, 160 }, { 250, 250, 250 }, { 160, 120, 250 } }
	for _ = 1, 9 do
		local x, z = (random() - 0.5) * size * 2, (random() - 0.5) * size * 2
		block(model, Vector3.new(0.25, 1.2, 0.25), base * CFrame.new(x, 0.6, z), { 70, 140, 60 }, { collide = false })
		block(
			model,
			Vector3.new(0.8, 0.5, 0.8),
			base * CFrame.new(x, 1.35, z),
			pick(random, colors),
			{ collide = false }
		)
	end
end

local function palm(model: Model, base: CFrame, size: number, random: Random)
	local trunk = { 150, 112, 70 }
	local height = size * between(random, 3.5, 4.5)
	local lean = between(random, -0.25, 0.25)
	local top = base
	for index = 1, 6 do
		local piece = height / 6
		top = top * CFrame.Angles(0, 0, lean / 6) * CFrame.new(0, piece / 2, 0)
		block(model, Vector3.new(1.2, piece, 1.2), top, shade(trunk, (index % 2) * 0.08), { material = M.Wood })
		top = top * CFrame.new(0, piece / 2, 0)
	end
	local leaf = vary(random, { 70, 156, 60 }, 0.06)
	for index = 1, 7 do
		local angle = index / 7 * math.pi * 2
		local length = size * between(random, 1.4, 1.8)
		block(
			model,
			Vector3.new(1.6, 0.3, length),
			top * CFrame.Angles(0, angle, 0) * CFrame.Angles(-0.35, 0, 0) * CFrame.new(0, 0, -length / 2),
			shade(leaf, (index % 2) * 0.06),
			{ material = M.Grass, collide = false }
		)
	end
	for index = 1, 3 do
		ball(
			model,
			0.9,
			(top * CFrame.Angles(0, index * 2.1, 0) * CFrame.new(0, -0.6, -0.7)).Position,
			{ 110, 74, 40 },
			{
				collide = false,
			}
		)
	end
end
extras.Palm = palm

extras.IceCrystal = function(model, base, size, random)
	for _ = 1, 4 do
		local height = size * between(random, 1.5, 3)
		block(
			model,
			Vector3.new(size * 0.6, height, size * 0.6),
			base
				* CFrame.new((random() - 0.5) * size, height * 0.4, (random() - 0.5) * size)
				* CFrame.Angles((random() - 0.5) * 0.6, random() * 3, (random() - 0.5) * 0.6),
			vary(random, { 160, 220, 250 }, 0.06),
			{ material = M.Ice, transparency = 0.2, reflectance = 0.15 }
		)
	end
end

-- How far the sea's surface is above the seabed, where sea scenery stands.
local SEA_DEPTH = 5.5

extras.Islet = function(model, base, size, random)
	-- A sandy island rising out of the water, with a palm.
	local sand = { 232, 218, 170 }
	local top = SEA_DEPTH + 2.5
	block(model, Vector3.new(size * 2, top, size * 1.6), base * CFrame.new(0, top / 2, 0), sand, { material = M.Sand })
	block(model, Vector3.new(size * 1.4, 1.6, size * 1.1), base * CFrame.new(0, top + 0.8, 0), shade(sand, 0.05), {
		material = M.Sand,
	})
	palm(model, base * CFrame.new(size * 0.2, top + 1.6, 0), 4, random)
	block(
		model,
		Vector3.new(2.4, 1.6, 1.6),
		base * CFrame.new(-size * 0.45, top + 1.2, size * 0.2),
		{ 150, 150, 140 },
		{
			material = M.Slate,
		}
	)
end

extras.Lighthouse = function(model, base, size, _random)
	local rock = { 110, 112, 118 }
	block(model, Vector3.new(size * 3, SEA_DEPTH + 4, size * 2.6), base * CFrame.new(0, (SEA_DEPTH + 4) / 2, 0), rock, {
		material = M.Slate,
	})
	local y = SEA_DEPTH + 4
	for index = 0, 5 do
		local color = if index % 2 == 0 then { 245, 245, 245 } else { 214, 52, 52 }
		column(model, size * (1.6 - index * 0.1), 5, base * CFrame.new(0, y, 0), color)
		y += 5
	end
	column(model, size * 1.5, 1, base * CFrame.new(0, y, 0), { 60, 60, 66 })
	local lamp = column(model, size * 0.9, 3, base * CFrame.new(0, y + 1, 0), { 255, 236, 150 }, { material = M.Neon })
	ObstacleModels.glow(lamp, { 255, 236, 160 }, 40, 2)
	column(model, size * 1.3, 1.6, base * CFrame.new(0, y + 4, 0), { 214, 52, 52 })
end

extras.Buoy = function(model, base, size, random)
	base = base * CFrame.new(0, SEA_DEPTH, 0)
	local color = pick(random, { { 220, 50, 50 }, { 250, 200, 40 } })
	column(model, size * 1.6, 2.2, base * CFrame.new(0, -1, 0), color)
	column(model, size * 1.2, 0.5, base * CFrame.new(0, 1.2, 0), { 250, 250, 250 })
	column(model, size * 0.5, 2.6, base * CFrame.new(0, 1.7, 0), color, { collide = false })
	ball(
		model,
		size * 0.7,
		(base * CFrame.new(0, 4.6, 0)).Position,
		{ 255, 240, 160 },
		{ material = M.Neon, collide = false }
	)
end

extras.Cycad = function(model, base, size, random)
	local trunk = { 120, 94, 60 }
	local height = size * between(random, 1.2, 2.2)
	block(model, Vector3.new(2.2, height, 2.2), base * CFrame.new(0, height / 2, 0), trunk, { material = M.Wood })
	for y = 0.4, height - 0.4, 0.9 do
		block(
			model,
			Vector3.new(2.5, 0.3, 2.5),
			base * CFrame.new(0, y, 0) * CFrame.Angles(0, y, 0),
			shade(trunk, -0.1),
			{
				collide = false,
			}
		)
	end
	ObstacleModels.fern(model, base * CFrame.new(0, height, 0), size * 1.3, random, 9)
end

extras.TreeFern = function(model, base, size, random)
	local height = size * between(random, 4, 6)
	block(
		model,
		Vector3.new(1.3, height, 1.3),
		base * CFrame.new(0, height / 2, 0),
		{ 96, 70, 46 },
		{ material = M.Wood }
	)
	ObstacleModels.fern(model, base * CFrame.new(0, height, 0), size * 2.2, random, 10)
end

local function buildProp(parent: Instance, kind: string, base: CFrame, size: number, random: Random)
	local model = Build.model(parent, kind)
	local extra = extras[kind]
	if extra then
		extra(model, base, size, random)
	else
		ObstacleModels.build(model, kind, base, size, size * 0.9, random())
	end
end

local function pickProp(random: Random, props: { Prop }): Prop
	local total = 0
	for _, prop in props do
		total += prop.weight
	end
	local target = random() * total
	for _, prop in props do
		target -= prop.weight
		if target < 0 then
			return prop
		end
	end
	return props[#props]
end

----------------------------------------------------------------------------------------------------------------
-- Following the runway

-- The runway winds (Shared/Runway), so the banks are built in short segments, each turned to run along it. Things
-- further from the runway, or low and plain, use segments twice as long: nobody can tell the difference.
local SEGMENT = 12
local LONG_SEGMENT = 24
-- How much longer than it needs to be each segment is, so neighbouring segments always meet.
local SEGMENT_OVERLAP = 1

-- A frame on the edge of a zone's runway on one side (side = -1 or 1) at `z`, turned to run along the runway: its x
-- axis points straight across the runway, its z axis along it, and it sits at the height of the runway. `side * d`
-- along its x axis is `d` studs out from the edge, away from the runway. (The zone's own width, even at its very end,
-- where the next, wider zone begins.)
local function edgeFrame(zoneId: number, z: number, side: number): CFrame
	local x = Runway.worldX(side * Runway.zoneWidth(zoneId) / 2, z)
	return CFrame.new(x, Runway.BASE_Y, z) * CFrame.Angles(0, Runway.heading(z), 0)
end

-- How long a segment of the bank covering `length` studs of runway at `z` must be, `reach` studs out from the edge:
-- longer where the runway is turning, so the outside of a bend has no notches.
local function segmentLength(z: number, length: number, reach: number): number
	local turn = math.abs(Runway.heading(z + length / 2) - Runway.heading(z - length / 2))
	return length / math.cos(Runway.heading(z)) + SEGMENT_OVERLAP + reach * turn
end

-- A smooth bump between -1 and 1 along the runway, so bank heights rise and fall gently from segment to segment.
local function wave(z: number, phase: number): number
	return 0.65 * math.sin(z / 70 + phase) + 0.35 * math.sin(z / 29 + phase * 1.7)
end

-- A height rounded to whole steps of `step` studs, for a blocky look.
local function steps(height: number, step: number): number
	return math.max(step, math.floor(height / step + 0.5) * step)
end

----------------------------------------------------------------------------------------------------------------
-- Gaps in the banks

-- The stretches of one side of a zone (side = -1 or 1) with no gap in its bank, as { from z, to z }. Gaps
-- (Shared/Runway.wallGaps) look out over the valley below; a low railing across each one keeps everyone on the runway,
-- and an egg steered into it bounces off, as off a bank.
local function stretchesOf(zoneId: number, side: number): { { number } }
	local startZ = Runway.zoneStartZ(zoneId)
	local list = {}
	local from = startZ
	for _, gap in Runway.wallGaps(zoneId) do
		if gap.side == side then
			table.insert(list, { from, gap.startZ })
			from = gap.endZ
		end
	end
	table.insert(list, { from, startZ + Runway.zoneLength(zoneId) })
	return list
end

-- The gaps on one side of a zone, as { from z, to z }.
local function gapsOf(zoneId: number, side: number): { { number } }
	local list = {}
	for _, gap in Runway.wallGaps(zoneId) do
		if gap.side == side then
			table.insert(list, { gap.startZ, gap.endZ })
		end
	end
	return list
end

-- Splits each stretch into pieces no longer than `size`: { centre z, length }.
local function piecesOf(stretches: { { number } }, size: number): { { number } }
	local pieces = {}
	for _, stretch in stretches do
		local z = stretch[1]
		while z < stretch[2] - 0.01 do
			local length = math.min(size, stretch[2] - z)
			table.insert(pieces, { z + length / 2, length })
			z += length
		end
	end
	return pieces
end

----------------------------------------------------------------------------------------------------------------
-- Ground

-- The checkered ground reaches one tile further than the runway is wide (half a tile past each edge, under the
-- banks), so no gap shows where a bend moves the banks across a row of tiles.

local function buildGround(folder: Instance, zoneId: number, palette: Palette, nextPalette: Palette?, random: Random)
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = folder
	local startZ = Runway.zoneStartZ(zoneId)
	local rows = Runway.zoneLength(zoneId) // TILE
	local width = Runway.zoneWidth(zoneId)
	local columns = width // TILE + 1
	for row = 0, rows - 1 do
		-- The last few rows blend into the next zone's colours.
		local blend = if nextPalette then math.clamp((row - (rows - 5)) / 5, 0, 1) else 0
		local z = startZ + TILE * (row + 0.5)
		-- Each row of tiles is centred on the runway where it is, so the checks follow the bends.
		local middle = Runway.centerX(z)
		for col = 0, columns - 1 do
			local tone = palette.ground[(row + col) % 2 + 1]
			if nextPalette and blend > 0 then
				tone = Build.mix(tone, nextPalette.ground[(row + col) % 2 + 1], blend)
			end
			block(
				ground,
				Vector3.new(TILE, SLAB, TILE),
				CFrame.new(middle + TILE * (col - (columns - 1) / 2), Runway.BASE_Y - SLAB / 2, z),
				vary(random, tone, 0.015),
				{
					material = if blend > 0.5 and nextPalette
						then nextPalette.groundMaterial
						else palette.groundMaterial,
				}
			)
		end
	end

	-- A kerb along each edge, all the way down.
	for _, side in { -1, 1 } do
		for _, piece in piecesOf({ { startZ, startZ + Runway.zoneLength(zoneId) } }, LONG_SEGMENT) do
			local z, length = piece[1], piece[2]
			block(
				ground,
				Vector3.new(2.4, 1, segmentLength(z, length, 2)),
				edgeFrame(zoneId, z, side) * CFrame.new(side * 1, 0.5, 0),
				palette.kerb,
				{ material = M.Concrete }
			).Name = if side
					> 0
				then "KerbLeft"
				else "KerbRight"
		end
	end

	-- The volcano's ground glows through cracks.
	if zoneId == 5 then
		for _ = 1, math.round(40 * Runway.zoneLength(zoneId) / 600) do
			local z = startZ + random() * Runway.zoneLength(zoneId)
			block(
				ground,
				Vector3.new(between(random, 3, 9), 0.1, 0.35),
				CFrame.new(Runway.worldX((random() - 0.5) * (width - 6), z), Runway.BASE_Y + 0.03, z)
					* CFrame.Angles(0, random() * math.pi, 0),
				{ 255, 110, 30 },
				{ material = M.Neon, collide = false }
			)
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Banks

-- How thick the grass (or sand, snow, rock) on top of each step is, how far it hangs out over the face towards the
-- runway, and how far below the runway each step is buried so no gap shows at its foot.
local CAP = 2
local OVERHANG = 0.8
local BURY = 6

-- A ledge along the bank where a prop can stand: `from` to `to` studs out from the runway's edge, at height `y`
-- (world), at `z`, on step `step` (1 is nearest the runway).
type Top = { from: number, to: number, y: number, z: number, step: number }

-- One step of a bank: a block of stone from `inner` to `inner + width` studs out from the edge, up to `top` above the
-- runway, with a cap of the zone's top material hanging a little over its face. Returns the stone.
local function buildStep(
	folder: Instance,
	frame: CFrame,
	side: number,
	length: number,
	inner: number,
	width: number,
	top: number,
	face: Build.Rgb,
	palette: Palette,
	random: Random
): BasePart
	local x = side * (inner + width / 2)
	local stone = block(
		folder,
		Vector3.new(width, top - CAP + BURY, length),
		frame * CFrame.new(x, (top - CAP - BURY) / 2, 0),
		face,
		{ material = palette.cliffMaterial }
	)
	block(
		folder,
		Vector3.new(width + OVERHANG, CAP, length + 0.2),
		frame * CFrame.new(x - side * OVERHANG / 2, top - CAP / 2, 0),
		vary(random, palette.top, 0.03),
		{ material = palette.topMaterial }
	)
	return stone
end

-- Tall stepped cliffs up one side of the runway (side = -1 or 1), like a canyon: three steps of stone, each capped
-- with the zone's grass (or sand, snow, rock), now and then hanging down the face. They follow the runway's bends and
-- stop at the gaps. Returns the steps' tops, for the props.
local function buildCliffs(folder: Instance, zoneId: number, palette: Palette, side: number, random: Random): { Top }
	local phase = random() * 10
	local tops: { Top } = {}
	-- Each step's width and height at `z`, rising and falling gently along the runway. The wall beside the runway stands
	-- 16 to 34 studs high, well above the head of anyone riding even the biggest egg; the step behind it climbs 12 to
	-- 20 studs more, and the back step 14 to 30 more again.
	local function layoutAt(z: number)
		local w1 = 12 + 4 * wave(z, phase + 3)
		local w2 = 14 + 4 * wave(z, phase + 5)
		local h1 = steps(25 + 9 * wave(z, phase), 2)
		local h2 = h1 + steps(16 + 4 * wave(z, phase + 1), 2)
		local h3 = h2 + steps(22 + 8 * wave(z, phase + 2), 2)
		return {
			{ inner = 2, width = w1, top = h1 },
			{ inner = 2 + w1, width = w2, top = h2 },
			{ inner = 2 + w1 + w2, width = 34, top = h3 },
		}
	end
	-- The back step, out of reach, in long segments.
	for _, piece in piecesOf(stretchesOf(zoneId, side), LONG_SEGMENT) do
		local z, length = piece[1], piece[2]
		local spec = layoutAt(z)[3]
		local segment = segmentLength(z, length, spec.inner + spec.width)
		local face = vary(random, shade(palette.cliff, -0.07), 0.04)
		buildStep(
			folder,
			edgeFrame(zoneId, z, side),
			side,
			segment,
			spec.inner,
			spec.width,
			spec.top,
			face,
			palette,
			random
		)
		table.insert(tops, {
			from = spec.inner,
			to = spec.inner + spec.width,
			y = Runway.BASE_Y + spec.top,
			z = z,
			step = 3,
		})
	end
	-- The two steps beside the runway.
	for index, piece in piecesOf(stretchesOf(zoneId, side), SEGMENT) do
		local z, length = piece[1], piece[2]
		local frame = edgeFrame(zoneId, z, side)
		local layout = layoutAt(z)
		local h1 = layout[1].top
		for step = 1, 2 do
			local spec = layout[step]
			local segment = segmentLength(z, length, spec.inner + spec.width)
			local face = vary(random, shade(palette.cliff, -0.035 * (step - 1)), 0.04)
			if palette.bands and step == 1 then
				-- Sandstone stripes across the first step, a few studs each.
				local y = -BURY
				local band = index % #palette.bands
				local x = side * (spec.inner + spec.width / 2)
				while y < spec.top - CAP - 0.5 do
					local height = math.min(spec.top - CAP - y, 5 + (band % 2) * 2)
					block(
						folder,
						Vector3.new(spec.width, height, segment),
						frame * CFrame.new(x, y + height / 2, 0),
						palette.bands[band % #palette.bands + 1],
						{ material = palette.cliffMaterial }
					)
					y += height
					band += 1
				end
				block(
					folder,
					Vector3.new(spec.width + OVERHANG, CAP, segment + 0.2),
					frame * CFrame.new(x - side * OVERHANG / 2, spec.top - CAP / 2, 0),
					vary(random, palette.top, 0.03),
					{ material = palette.topMaterial }
				)
			else
				buildStep(folder, frame, side, segment, spec.inner, spec.width, spec.top, face, palette, random)
			end

			-- Now and then the grass hangs down the face towards the runway.
			if not palette.lava and random() < 0.3 then
				local drop =
					math.min(between(random, 2, 6), spec.top - (if step == 1 then 0 else layout[step - 1].top) - 3)
				if drop > 1 then
					local width = between(random, 2, math.min(5, length - 1))
					block(
						folder,
						Vector3.new(0.6, drop, width),
						frame
							* CFrame.new(
								side * (spec.inner - OVERHANG + 0.2),
								spec.top - CAP - drop / 2 + 0.2,
								(random() - 0.5) * (length - width)
							),
						shade(palette.top, -0.12),
						{ material = palette.topMaterial, collide = false }
					).Name =
						"Hanging"
				end
			end

			if palette.lava and step == 1 then
				-- A lava river along the top of the first step, set into the rock.
				block(
					folder,
					Vector3.new(4, 0.4, segment),
					frame * CFrame.new(side * (spec.inner + spec.width * 0.62), spec.top - 0.1, 0),
					{ 255, 110, 26 },
					{ material = M.Neon, collide = false }
				)
			elseif palette.lava and step == 2 and random() < 0.3 then
				-- Lava pouring down the face of the second step into the river below.
				block(
					folder,
					Vector3.new(0.6, spec.top - h1, between(random, 3, 6)),
					frame * CFrame.new(side * (spec.inner - 0.25), (spec.top + h1) / 2, 0),
					{ 255, 130, 30 },
					{ material = M.Neon, collide = false }
				)
			end
			table.insert(tops, {
				from = spec.inner + (if palette.lava and step == 1 then spec.width * 0.62 + 3 else 0),
				to = spec.inner + spec.width,
				y = Runway.BASE_Y + spec.top,
				z = z,
				step = step,
			})
		end
	end
	return tops
end

-- The low railing across a gap in the banks (wooden posts and two rails), and an invisible wall above it, so
-- nobody leaves the runway there; the view opens out over the valley below.
local function buildRailing(folder: Instance, zoneId: number, palette: Palette, side: number, from: number, to: number)
	local wood = shade(palette.kerb, -0.1)
	for _, piece in piecesOf({ { from, to } }, LONG_SEGMENT) do
		local z, length = piece[1], piece[2]
		local frame = edgeFrame(zoneId, z, side)
		local segment = segmentLength(z, length, 2)
		for _, height in { 1.6, 3 } do
			block(
				folder,
				Vector3.new(0.5, 0.5, segment),
				frame * CFrame.new(side * 1.2, height, 0),
				palette.kerb,
				{ material = M.Wood, collide = false }
			).Name =
				"Rail"
		end
		block(
			folder,
			Vector3.new(0.9, 3.8, 0.9),
			frame * CFrame.new(side * 1.2, 1.9, -length / 2 + 0.6),
			wood,
			{ material = M.Wood }
		).Name =
			"Post"
		block(folder, Vector3.new(1, 30, segment), frame * CFrame.new(side * 1.2, 15, 0), { 255, 255, 255 }, {
			transparency = 1,
		}).Name =
			"GapWall"
	end
end

-- What lies beyond a gap: a grassy ledge at the runway's height, then big steps down into a valley, so the gap
-- looks out over open country. Returns the ledges, for the props.
local function buildVista(
	folder: Instance,
	zoneId: number,
	palette: Palette,
	side: number,
	from: number,
	to: number,
	random: Random
): { Top }
	local tops: { Top } = {}
	local layout = {
		{ inner = 2, width = 8, top = 0 },
		{ inner = 10, width = 18, top = -8 },
		{ inner = 28, width = 22, top = -18 },
		{ inner = 50, width = 90, top = -30 },
	}
	-- A little past the gap at each end, under the banks beside it, so its sides are closed.
	for _, piece in piecesOf({ { from - 4, to + 4 } }, LONG_SEGMENT) do
		local z, length = piece[1], piece[2]
		local frame = edgeFrame(zoneId, z, side)
		for step, spec in layout do
			local segment = segmentLength(z, length, spec.inner + spec.width)
			local bottom = -40
			local x = side * (spec.inner + spec.width / 2)
			block(
				folder,
				Vector3.new(spec.width, spec.top - CAP - bottom, segment),
				frame * CFrame.new(x, (spec.top - CAP + bottom) / 2, 0),
				vary(random, shade(palette.cliff, -0.06 * step), 0.03),
				{ material = palette.cliffMaterial }
			)
			block(
				folder,
				Vector3.new(spec.width + OVERHANG, CAP, segment + 0.2),
				frame * CFrame.new(x - side * OVERHANG / 2, spec.top - CAP / 2, 0),
				shade(palette.top, -0.03 * step),
				{ material = palette.topMaterial }
			)
			if z > from and z < to and step > 1 then
				table.insert(tops, {
					from = spec.inner,
					to = spec.inner + spec.width,
					y = Runway.BASE_Y + spec.top,
					z = z,
					step = math.min(step - 1, 3),
				})
			end
		end
	end
	return tops
end

-- A boardwalk's edges: posts and ropes (open at the gaps), and an invisible wall the whole way so nobody walks off
-- into the sea, over a reef that follows the boardwalk's bends.
local function buildSea(folder: Instance, zoneId: number, palette: Palette, side: number, random: Random): { Top }
	local startZ = Runway.zoneStartZ(zoneId)
	local length = Runway.zoneLength(zoneId)
	local seabedY = Runway.BASE_Y - 7
	local waterY = Runway.BASE_Y - 1.5
	local outer = 200
	-- The seabed and the water over it, in strips that follow the bends.
	for _, piece in piecesOf({ { startZ, startZ + length } }, TILE * 2) do
		local z, span = piece[1], piece[2]
		local frame = edgeFrame(zoneId, z, side)
		local segment = segmentLength(z, span, outer)
		block(
			folder,
			Vector3.new(outer, 4, segment),
			frame * CFrame.new(side * outer / 2, seabedY - 2 - Runway.BASE_Y, 0),
			palette.cliff,
			{ material = M.Sand }
		)
		block(
			folder,
			Vector3.new(outer, 1, segment),
			frame * CFrame.new(side * outer / 2, waterY - 0.5 - Runway.BASE_Y, 0),
			{ 56, 168, 214 },
			{ material = M.Glass, transparency = 0.45, collide = false }
		)
	end
	-- Piles under the boardwalk, and the invisible wall, all the way down.
	for _, piece in piecesOf({ { startZ, startZ + length } }, SEGMENT) do
		local z, span = piece[1], piece[2]
		local frame = edgeFrame(zoneId, z, side)
		block(
			folder,
			Vector3.new(1, SEA_WALL_HEIGHT, segmentLength(z, span, 1)),
			frame * CFrame.new(side * 1.5, SEA_WALL_HEIGHT / 2 - 2, 0),
			{ 255, 255, 255 },
			{ transparency = 1 }
		).Name =
			"SeaWall"
		column(folder, 1.6, 9, frame * CFrame.new(0, seabedY - Runway.BASE_Y, 0), shade(palette.kerb, -0.15), {
			material = M.Wood,
			collide = false,
		})
	end
	-- Posts with ropes between them, open where the bank has a gap.
	for _, piece in piecesOf(stretchesOf(zoneId, side), SEGMENT) do
		local z, span = piece[1], piece[2]
		local frame = edgeFrame(zoneId, z, side)
		for _, height in ROPE_HEIGHTS do
			block(
				folder,
				Vector3.new(0.3, 0.3, segmentLength(z, span, 1)),
				frame * CFrame.new(side * 1, height, 0),
				{ 214, 190, 140 },
				{ material = M.Fabric, collide = false }
			)
		end
		block(
			folder,
			Vector3.new(1.2, RAILING_HEIGHT, 1.2),
			frame * CFrame.new(side * 1, RAILING_HEIGHT / 2, -span / 2 + 0.6),
			palette.kerb,
			{ material = M.Wood }
		)
	end
	-- A lighthouse on a rock off one side.
	if side > 0 then
		local z = startZ + length / 2 + 90
		buildProp(
			folder,
			"Lighthouse",
			edgeFrame(zoneId, z, side) * CFrame.new(side * 90, seabedY - Runway.BASE_Y, 0),
			5,
			random
		)
	end
	-- The seabed further out, where the scenery stands: twice over, for a busier reef.
	local tops: { Top } = {}
	for col = 0, length // TILE - 1 do
		for _ = 1, 2 do
			table.insert(tops, {
				from = 10,
				to = 130,
				y = seabedY,
				z = startZ + TILE * (col + 0.5) + (random() - 0.5) * 12,
				step = 1,
			})
		end
	end
	return tops
end

local function dressBanks(
	folder: Instance,
	zoneId: number,
	palette: Palette,
	tops: { Top },
	side: number,
	random: Random
)
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = folder
	-- How likely each step is to get a prop.
	local chance = { 0.45, 0.32, 0.2 }
	for _, top in tops do
		if random() < chance[top.step] then
			local prop = pickProp(random, palette.props)
			local size = (prop.size or 3) * between(random, 0.85, 1.2)
			local margin = math.min(size + 1, (top.to - top.from) / 2)
			local out = between(random, top.from + margin, top.to - margin)
			local z = top.z + (random() - 0.5) * 6
			local turn = CFrame.Angles(0, (random() - 0.5) * 0.8, 0)
			local base = edgeFrame(zoneId, z, side) * CFrame.new(side * out, top.y - Runway.BASE_Y, 0) * turn
			buildProp(props, prop.kind, base, size, random)
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Backdrop

local function buildBackdrop(folder: Instance, zoneId: number, palette: Palette, random: Random)
	local backdrop = Instance.new("Folder")
	backdrop.Name = "Backdrop"
	backdrop.Parent = folder
	local startZ = Runway.zoneStartZ(zoneId)
	for _, side in { -1, 1 } do
		local z = startZ + random() * 60
		while z < startZ + Runway.zoneLength(zoneId) do
			local width = between(random, 70, 140)
			local x = Runway.centerX(z) + side * (between(random, 210, 330) + spreadOf(zoneId))
			local y = Runway.BASE_Y - 10
			local layers = if zoneId == 2 then 2 else 4
			local size = width
			local volcano = zoneId == 5 or (zoneId == 6 and random() < 0.3)
			for layer = 1, layers do
				local height = if zoneId == 2 then between(random, 40, 70) else between(random, 18, 34)
				local color = shade(palette.backdrop, (layer - 1) * 0.05)
				if palette.backdropTop and layer == layers then
					color = palette.backdropTop
				end
				block(
					backdrop,
					Vector3.new(size, height, size * between(random, 0.7, 1)),
					CFrame.new(x, y + height / 2, z) * CFrame.Angles(0, (random() - 0.5) * 0.3, 0),
					color,
					{ material = if palette.backdropTop and layer == layers then M.Snow else palette.cliffMaterial }
				)
				y += height
				size *= if zoneId == 2 then 0.85 else 0.66
			end
			if volcano then
				-- A glowing crater and a plume of smoke.
				local crater = block(
					backdrop,
					Vector3.new(size * 0.8, 1, size * 0.8),
					CFrame.new(x, y + 0.5, z),
					{ 255, 110, 30 },
					{ material = M.Neon }
				)
				ObstacleModels.emitter(crater, "Smoke", { 80, 74, 74 }, {
					size = 12,
					rate = 3,
					speed = 8,
					life = 8,
					lift = 2,
					spread = 15,
				})
			end
			z += width * between(random, 0.8, 1.3)
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Gate

local function addSignText(part: BasePart, face: Enum.NormalId, title: string, subtitle: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = part

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, 0.62)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.Text = title
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextStrokeTransparency = 0.4
	titleLabel.TextScaled = true
	titleLabel.Parent = gui

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Position = UDim2.fromScale(0, 0.62)
	subtitleLabel.Size = UDim2.fromScale(1, 0.34)
	subtitleLabel.Font = Enum.Font.GothamBold
	subtitleLabel.Text = subtitle
	subtitleLabel.TextColor3 = Color3.new(1, 1, 1)
	subtitleLabel.TextScaled = true
	subtitleLabel.Parent = gui
end

-- The lowest and highest stamina requirement of a zone's eggs.
local function staminaRange(zone): (number, number)
	local low, high = math.huge, 0
	for rarity in Rarities.Info do
		local requirement = zone.stamina[rarity]
		if requirement then
			low = math.min(low, requirement)
			high = math.max(high, requirement)
		end
	end
	return low, high
end

-- High enough that the arch stands well clear of the banks either side of it.
local GATE_HEIGHT = 46

local function buildGate(folder: Instance, zoneId: number)
	local zone = Zones.List[zoneId]
	local accent = zone.accent
	local startZ = Runway.zoneStartZ(zoneId)
	local edge = edgeOf(zoneId)
	local width = Runway.zoneWidth(zoneId)
	for _, side in { -1, 1 } do
		local post = block(
			folder,
			Vector3.new(6, GATE_HEIGHT + 6, 6),
			CFrame.new(side * (edge + 3), Runway.BASE_Y + (GATE_HEIGHT + 6) / 2 - 2, startZ),
			accent,
			{ material = M.Wood }
		)
		post.Name = "SignPost"
		block(
			folder,
			Vector3.new(7.5, 2, 7.5),
			CFrame.new(side * (edge + 3), Runway.BASE_Y + GATE_HEIGHT + 5, startZ),
			shade(accent, 0.2),
			{ material = M.Wood }
		)
	end
	local sign = block(
		folder,
		Vector3.new(width + 12, 10, 2),
		CFrame.new(0, Runway.BASE_Y + GATE_HEIGHT, startZ),
		accent,
		{ material = M.WoodPlanks }
	)
	sign.Name = "Sign"
	block(
		folder,
		Vector3.new(width + 16, 1.2, 2.6),
		CFrame.new(0, Runway.BASE_Y + GATE_HEIGHT + 5.6, startZ),
		shade(accent, 0.25),
		{ material = M.Wood }
	)
	local low, high = staminaRange(zone)
	local subtitle = `Eggs need {NumberFormat.abbreviate(low)} - {NumberFormat.abbreviate(high)} stamina`
	-- Front faces players coming from the hub; Back faces players walking home.
	addSignText(sign, Enum.NormalId.Front, string.upper(zone.name), subtitle)
	addSignText(sign, Enum.NormalId.Back, string.upper(zone.name), subtitle)
end

----------------------------------------------------------------------------------------------------------------

local Scenery = {}

Scenery.PALETTES = PALETTES

-- Builds one scenery prop (a tree, bush, rock, flowers...) standing at `base`, about `size` studs across. Any kind
-- from the zones' palettes, or any runway obstacle.
Scenery.buildProp = buildProp

function Scenery.buildZone(map: Instance, zoneId: number)
	local zone = Zones.List[zoneId]
	local palette = PALETTES[zoneId]
	local folder = Instance.new("Folder")
	folder.Name = zone.key
	folder.Parent = map
	local random = Build.random(4241 * zoneId + 17)

	buildGround(folder, zoneId, palette, PALETTES[zoneId + 1], random)
	buildGate(folder, zoneId)

	local banks = Instance.new("Folder")
	banks.Name = "Banks"
	banks.Parent = folder
	for _, side in { -1, 1 } do
		local tops = if palette.sea
			then buildSea(banks, zoneId, palette, side, random)
			else buildCliffs(banks, zoneId, palette, side, random)
		if not palette.sea then
			for _, gap in gapsOf(zoneId, side) do
				buildRailing(banks, zoneId, palette, side, gap[1], gap[2])
				for _, top in buildVista(banks, zoneId, palette, side, gap[1], gap[2], random) do
					table.insert(tops, top)
				end
			end
		end
		dressBanks(banks, zoneId, palette, tops, side, random)
	end
	buildBackdrop(folder, zoneId, palette, random)
	return folder
end

-- The runway has no end: past it, the last zone again, Runway.REPEATS times (see Shared/Runway). Every scenery part is
-- anchored, so each copy is the last zone's finished folder moved one loop further on. The copies' obstacles are
-- built with the rest (Shared/Obstacles lays them out).
function Scenery.buildRepeats(map: Instance, lastZone: Instance)
	for copy = 1, Runway.REPEATS do
		local folder = lastZone:Clone()
		folder.Name = lastZone.Name .. "Repeat" .. copy
		local shift = Vector3.new(0, 0, copy * Runway.LOOP_LENGTH)
		for _, descendant in folder:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CFrame += shift
			end
		end
		folder.Parent = map
	end
end

-- Builds one obstacle from Shared/Obstacles into `parent`, tagged with its id for the client.
function Scenery.buildObstacle(parent: Instance, obstacle): Model
	local model = Build.model(parent, obstacle.kind .. obstacle.id)
	model:SetAttribute("ObstacleId", obstacle.id)
	model:SetAttribute("Kind", obstacle.kind)
	model:SetAttribute("Timed", obstacle.timing ~= nil)
	-- Where it is across the runway, wherever the runway's bends have taken it, turned to face along the runway.
	ObstacleModels.build(
		model,
		obstacle.kind,
		CFrame.new(Runway.worldX(obstacle.x, obstacle.z), Runway.BASE_Y, obstacle.z)
			* CFrame.Angles(0, Runway.heading(obstacle.z), 0),
		obstacle.hx,
		obstacle.hz,
		obstacle.seed
	)
	return model
end

return Scenery
