-- Builds each zone's stretch of runway and everything around it, in the blocky style of the eggs and pets:
--     Ground    the runway itself, checkered in the zone's colours, winding and rolling over the hills, blending
--               into the next zone over its last rows
--     Walls     massive stepped walls up both sides, far too high to climb, topped with the zone's plants and rocks
--               and broken by the gaps (the Ocean zone is a boardwalk over a reef instead, with railings along its
--               edges)
--     Backdrop  big blocky hills, mesas, mountains or volcanoes in the distance
--     Gate      a sign hung across the start of the zone with its name and the stamina its eggs need
--     Repeats   the last zone again past the end of the runway, which never ends (Shared/Runway)
-- Nothing here affects play: eggs and obstacles are worked out from Shared/Runway and Shared/Obstacles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local NumberFormat = require(Shared.NumberFormat)
local Rarities = require(Shared.Config.Rarities)
local Runway = require(Shared.Runway)
local RunwayFrame = require(Shared.RunwayFrame)
local Zones = require(Shared.Config.Zones)

local Build = require(script.Parent.Build)
local ObstacleModels = require(script.Parent.ObstacleModels)

local block, ball, column = Build.block, Build.ball, Build.column
local shade, vary, between, pick = Build.shade, Build.vary, Build.between, Build.pick

type Rgb = Build.Rgb
type Random = Build.Random

local M = Enum.Material

-- The ground is laid in rows of tiles about this long and wide, on a slab this thick.
local TILE = 20
local SLAB = 4
-- A kerb this wide runs along each edge of the runway; the walls rise from behind it.
local KERB = 2
-- How high the wall beside the runway stands, give or take (the tiers behind it stand higher still), how thick the
-- grass, sand or snow on top of every tier is, and how far below the runway the walls go on down, so that wherever
-- a gap shows their ends the runway reads as the top of a plateau.
local WALL_HEIGHT = 46
local CAP = 3
local WALL_FOOT = 40
-- How far each tier behind the first stands into the one in front of it.
local TIER_OVERLAP = 1.5

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
	-- Lava rivers along the tops of the Volcano's walls, and lava falling down its cliffs.
	lava: boolean?,
}

local PALETTES: { Palette } = {
	{ -- Forest
		ground = { { 104, 178, 76 }, { 90, 162, 66 } },
		groundMaterial = M.Grass,
		kerb = { 150, 120, 84 },
		cliff = { 126, 94, 64 },
		cliffMaterial = M.Ground,
		top = { 98, 172, 72 },
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
	{ -- Prehistoric
		ground = { { 132, 156, 82 }, { 118, 142, 72 } },
		groundMaterial = M.Grass,
		kerb = { 120, 92, 62 },
		cliff = { 134, 104, 72 },
		cliffMaterial = M.Ground,
		top = { 96, 150, 64 },
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
--
-- The runway bends and climbs (Shared/Runway), so nothing here is laid out in straight rows. Everything that runs
-- alongside it (ground, kerbs, walls, railings) is built in short pieces, each laid along the line from one spot on
-- the runway to another, so the pieces turn with the bends and step up and down the hills.

-- The same place and heading as `frame`, at a height in the world.
local function atHeight(frame: CFrame, worldY: number): CFrame
	return CFrame.new(frame.X, worldY, frame.Z) * frame.Rotation
end

-- A level frame for a piece that runs alongside the runway from (x0, z0) to (x1, z1): halfway between the two
-- spots, at the height of the ground there, with +Z pointing from the first to the second and +X across the runway
-- (toward +x). Also how far apart the two spots are, on the level.
local function along(x0: number, z0: number, x1: number, z1: number): (CFrame, number)
	local a, b = RunwayFrame.point(x0, z0), RunwayFrame.point(x1, z1)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local forward = flat.Unit
	return CFrame.fromMatrix((a + b) / 2, Vector3.new(forward.Z, 0, -forward.X), Vector3.yAxis, forward), flat.Magnitude
end

-- The same for a piece that lies on the ground: tipped to run up or down the slope from one spot to the other. Also
-- how far apart the two spots are, along the slope.
local function alongSlope(x0: number, z0: number, x1: number, z1: number): (CFrame, number)
	local a, b = RunwayFrame.point(x0, z0), RunwayFrame.point(x1, z1)
	local span = b - a
	local forward = span.Unit
	local across = Vector3.new(forward.Z, 0, -forward.X).Unit
	return CFrame.fromMatrix((a + b) / 2, across, forward:Cross(across), forward), span.Magnitude
end

-- How far apart two spots on the runway are, on the level.
local function distance(x0: number, z0: number, x1: number, z1: number): number
	local a, b = RunwayFrame.point(x0, z0), RunwayFrame.point(x1, z1)
	return Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
end

----------------------------------------------------------------------------------------------------------------
-- Gaps in the walls

-- The stretches of one side of a zone (side = -1 or 1) with no gap in its wall, as { from z, to z }. A rider who
-- steers their egg into a gap (Shared/Runway.wallGaps) goes over the edge with it; one who steers into a wall dies.
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

-- Splits each stretch into pieces no longer than `size`: { from z, to z }.
local function piecesOf(stretches: { { number } }, size: number): { { number } }
	local pieces = {}
	for _, stretch in stretches do
		local z = stretch[1]
		while z < stretch[2] - 0.01 do
			local length = math.min(size, stretch[2] - z)
			table.insert(pieces, { z, z + length })
			z += length
		end
	end
	return pieces
end

----------------------------------------------------------------------------------------------------------------
-- Ground

local function buildGround(folder: Instance, zoneId: number, palette: Palette, nextPalette: Palette?, random: Random)
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = folder
	local startZ = Runway.zoneStartZ(zoneId)
	local length = Runway.zoneLength(zoneId)
	local rows = length // TILE
	local columns = math.round(Runway.zoneWidth(zoneId) / TILE)
	for row = 0, rows - 1 do
		local z0, z1 = startZ + TILE * row, startZ + TILE * (row + 1)
		-- The runway widens toward the next zone over the zone's last rows; the tiles widen with it.
		local half0, half1 = Runway.halfWidthAt(z0), Runway.halfWidthAt(z1)
		local width0, width1 = half0 * 2 / columns, half1 * 2 / columns
		-- The last few rows blend into the next zone's colours.
		local blend = if nextPalette then math.clamp((row - (rows - 5)) / 5, 0, 1) else 0
		-- Tiles are rectangles, so round a bend the ends of one row do not quite meet the next. Every other row is
		-- laid a hair lower and a little longer, tucked under its neighbours, so no crack ever shows; every other
		-- tile across a row is a hair lower too, so tiles that overlap never flicker.
		local tucked = row % 2 == 0
		local turn = math.abs(Runway.heading(z1) - Runway.heading(z0))
		for col = 0, columns - 1 do
			local tone = palette.ground[(row + col) % 2 + 1]
			if nextPalette and blend > 0 then
				tone = Build.mix(tone, nextPalette.ground[(row + col) % 2 + 1], blend)
			end
			local width = math.max(width0, width1)
			-- The outermost tiles run on under the kerb.
			local shift = 0
			if col == 0 then
				width += 1
				shift -= 0.5
			end
			if col == columns - 1 then
				width += 1
				shift += 0.5
			end
			local frame, span =
				alongSlope(-half0 + width0 * (col + 0.5) + shift, z0, -half1 + width1 * (col + 0.5) + shift, z1)
			local tuck = if tucked then width * turn / 2 + 0.15 else 0
			local sink = (if tucked then 0.04 else 0) + (col % 2) * 0.02
			block(
				ground,
				Vector3.new(width + 0.02, SLAB, span + tuck * 2),
				frame * CFrame.new(0, -SLAB / 2 - sink, 0),
				vary(random, tone, 0.015),
				{
					material = if blend > 0.5 and nextPalette
						then nextPalette.groundMaterial
						else palette.groundMaterial,
				}
			).Name =
				"Tile"
		end
	end

	-- A kerb along each edge, broken where the wall has a gap; a glowing red strip warns of each gap.
	for _, side in { -1, 1 } do
		for _, piece in piecesOf(stretchesOf(zoneId, side), TILE) do
			local z0, z1 = piece[1], piece[2]
			local frame, span = alongSlope(
				side * (Runway.halfWidthAt(z0) + KERB / 2),
				z0,
				side * (Runway.halfWidthAt(z1) + KERB / 2),
				z1
			)
			block(
				ground,
				Vector3.new(KERB, 1, span + 0.1),
				frame * CFrame.new(0, 0.5, 0),
				palette.kerb,
				{ material = M.Concrete }
			).Name = if side
					> 0
				then "KerbLeft"
				else "KerbRight"
		end
	end
	for _, gap in Runway.wallGaps(zoneId) do
		for _, piece in piecesOf({ { gap.startZ, gap.endZ } }, TILE) do
			local z0, z1 = piece[1], piece[2]
			local frame, span =
				alongSlope(gap.side * (Runway.halfWidthAt(z0) - 1), z0, gap.side * (Runway.halfWidthAt(z1) - 1), z1)
			block(
				ground,
				Vector3.new(2, 0.2, span + 0.1),
				frame * CFrame.new(0, 0.1, 0),
				{ 255, 70, 60 },
				{ material = M.Neon, collide = false }
			).Name =
				"GapWarning"
		end
	end

	-- The volcano's ground glows through cracks.
	if zoneId == 5 then
		for _ = 1, length // 15 do
			local z = startZ + random() * length
			block(
				ground,
				Vector3.new(between(random, 3, 9), 0.1, 0.35),
				RunwayFrame.onSlope((random() - 0.5) * (Runway.widthAt(z) - 6), z, 0.03)
					* CFrame.Angles(0, random() * math.pi, 0),
				{ 255, 110, 30 },
				{ material = M.Neon, collide = false }
			)
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Walls

-- Somewhere scenery can stand: a level patch `length` long (along the runway) reaching from x0 to x1 studs out
-- from `frame` (a frame at the patch's height, on its edge nearest the runway, +Z along the runway), and the chance
-- that something stands there.
type Top = { frame: CFrame, x0: number, x1: number, length: number, chance: number }

-- One block of a wall, on one side of the runway (side = -1 or 1), from z0 to z1 down it. Its near face stands
-- `offset` studs out from the foot of the wall, it is `depth` studs deep, and its top is at `topY`. Returns a frame
-- at the middle of the near edge of its top, and how long it is.
local function wallBlock(
	folder: Instance,
	palette: Palette,
	side: number,
	z0: number,
	z1: number,
	offset: number,
	depth: number,
	topY: number,
	tier: number,
	stripe: number,
	random: Random
): (CFrame, number)
	local near0 = Runway.halfWidthAt(z0) + KERB + offset
	local near1 = Runway.halfWidthAt(z1) + KERB + offset
	local frame, near = along(side * near0, z0, side * near1, z1)
	-- Round the outside of a bend the far edge is longer than the near one: long enough for both, so the blocks
	-- always close up.
	local length = math.max(near, distance(side * (near0 + depth), z0, side * (near1 + depth), z1)) + 0.3
	local bottom = math.min(Runway.surfaceY(z0), Runway.surfaceY(z1)) - WALL_FOOT
	local faceTop = topY - CAP

	local face = vary(random, palette.cliff, 0.05)
	if palette.bands and tier == 1 then
		-- Sandstone stripes, each a few studs thick, from the runway up.
		local ground = math.min(Runway.surfaceY(z0), Runway.surfaceY(z1)) - SLAB
		block(
			folder,
			Vector3.new(depth, ground - bottom, length),
			atHeight(frame, (ground + bottom) / 2) * CFrame.new(side * depth / 2, 0, 0),
			palette.bands[stripe % #palette.bands + 1],
			{ material = palette.cliffMaterial }
		)
		local y = ground
		local band = stripe
		while y < faceTop - 0.01 do
			band += 1
			local height = math.min(faceTop - y, 6 + (band % 3) * 2.5)
			block(
				folder,
				Vector3.new(depth, height, length),
				atHeight(frame, y + height / 2) * CFrame.new(side * depth / 2, 0, 0),
				palette.bands[band % #palette.bands + 1],
				{ material = palette.cliffMaterial }
			)
			y += height
		end
	else
		block(
			folder,
			Vector3.new(depth, faceTop - bottom, length),
			atHeight(frame, (faceTop + bottom) / 2) * CFrame.new(side * depth / 2, 0, 0),
			shade(face, -0.04 * (tier - 1)),
			{ material = palette.cliffMaterial }
		).Name =
			"Wall"
	end
	-- The top: a thick layer of the zone's grass, sand or snow, hanging out over the face a little.
	block(
		folder,
		Vector3.new(depth + 0.8, CAP, length),
		atHeight(frame, topY - CAP / 2) * CFrame.new(side * (depth / 2 - 0.4), 0, 0),
		vary(random, palette.top, 0.03),
		{ material = palette.topMaterial }
	).Name =
		"WallTop"
	return atHeight(frame, topY), length
end

-- The massive walls up one side of the runway (side = -1 or 1): a sheer face rising straight from the kerb, and
-- two more tiers stepping up and back behind it. Returns their tops, for the scenery that stands on them.
local function buildWalls(folder: Instance, zoneId: number, palette: Palette, side: number, random: Random): { Top }
	local phase = random() * 10
	local tops: { Top } = {}
	for column, piece in piecesOf(stretchesOf(zoneId, side), TILE * 2) do
		local z0, z1 = piece[1], piece[2]
		local middle = (z0 + z1) / 2
		local ground = Runway.surfaceY(middle)
		-- The skyline rises and falls in long waves, with a little roughness block to block.
		local wave = math.sin(middle / 85 + phase) + 0.5 * math.sin(middle / 37 + phase * 2)
		local depths = { 22 + 8 * random(), 24 + 12 * random(), 44 }
		local heights = { WALL_HEIGHT + 7 * wave + 5 * random(), 0, 0 }
		heights[2] = heights[1] + 16 + 12 * random()
		heights[3] = heights[2] + 18 + 16 * random()

		-- The face beside the runway is built in short blocks, so it follows the bends closely.
		local halves = if z1 - z0 > TILE + 0.01 then { { z0, middle }, { middle, z1 } } else { { z0, z1 } }
		for index, half in halves do
			local top = ground + heights[1] + (if index == 2 then (random() - 0.5) * 4 else 0)
			local frame, length =
				wallBlock(folder, palette, side, half[1], half[2], 0, depths[1], top, 1, column + index, random)
			local riverEdge = 0
			if palette.lava then
				-- A lava river along the top of the wall, set into the rock.
				riverEdge = depths[1] * 0.62 + 3
				block(
					folder,
					Vector3.new(4, 0.4, length),
					frame * CFrame.new(side * depths[1] * 0.62, -0.1, 0),
					{ 255, 110, 26 },
					{ material = M.Neon, collide = false }
				)
			end
			table.insert(tops, { frame = frame, x0 = riverEdge, x1 = depths[1], length = length, chance = 0.3 })
		end

		-- The tiers behind stand a little way into the one in front, so no crack shows between them round a bend.
		local offset = depths[1]
		for tier = 2, 3 do
			local frame, length = wallBlock(
				folder,
				palette,
				side,
				z0,
				z1,
				offset - TIER_OVERLAP,
				depths[tier] + TIER_OVERLAP,
				ground + heights[tier],
				tier,
				column,
				random
			)
			if palette.lava and tier == 2 and random() < 0.45 then
				-- Lava pouring down the face of the second tier into the river below.
				local drop = heights[2] - heights[1]
				block(
					folder,
					Vector3.new(0.6, drop, between(random, 3, 6)),
					frame * CFrame.new(-side * 0.25, -CAP - drop / 2 + 1, (random() - 0.5) * length * 0.6),
					{ 255, 130, 30 },
					{ material = M.Neon, collide = false }
				)
			end
			table.insert(tops, {
				frame = frame,
				x0 = TIER_OVERLAP,
				x1 = depths[tier] + TIER_OVERLAP,
				length = length,
				chance = if tier == 2 then 0.45 else 0.35,
			})
			offset += depths[tier]
		end
	end
	return tops
end

-- The world's X and Z from one end of a zone to the other, `reach` studs out from the runway on both sides:
-- { minX, maxX, minZ, maxZ }. (A zone starts and ends square across the world's Z axis; see Shared/Runway.)
local function zoneBounds(zoneId: number, reach: number): { number }
	local startZ = Runway.zoneStartZ(zoneId)
	local endZ = startZ + Runway.zoneLength(zoneId)
	local minX, maxX = math.huge, -math.huge
	for z = startZ, endZ, TILE do
		local x = RunwayFrame.point(0, z).X
		minX, maxX = math.min(minX, x), math.max(maxX, x)
	end
	return { minX - reach, maxX + reach, RunwayFrame.point(0, startZ).Z, RunwayFrame.point(0, endZ).Z }
end

-- How far the Ocean's sea and seabed lie below the boardwalk where the zone starts (the boardwalk humps up from
-- there, never down), and how far the sea reaches out to each side.
local WATER_DROP = 1.5
local SEABED_DROP = 7
local SEA_REACH = 300
-- The sea is laid in sections about this long down the zone, its water a sheet this thick.
local SEA_SECTION = 400
local WATER_SHEET = 0.1

-- The sea round the Ocean's boardwalk, built once for both sides.
local function buildSeaFloor(folder: Instance, zoneId: number, palette: Palette, random: Random)
	local startZ = Runway.zoneStartZ(zoneId)
	local base = Runway.surfaceY(startZ)
	local seabedY = base - SEABED_DROP
	local bounds = zoneBounds(zoneId, Runway.zoneWidth(zoneId) / 2 + SEA_REACH)
	local width = bounds[2] - bounds[1]
	local centerX = (bounds[1] + bounds[2]) / 2
	-- The seabed and the water lie right under the boardwalk too. Anyone who ends up in the water drowns
	-- (MapService), so nobody wanders off across the reef. Both are laid in sections side by side down the zone,
	-- each small enough to stream in as players come near it.
	local sections = math.ceil((bounds[4] - bounds[3]) / SEA_SECTION)
	local depth = (bounds[4] - bounds[3]) / sections
	for section = 1, sections do
		local centerZ = bounds[3] + depth * (section - 0.5)
		block(
			folder,
			Vector3.new(width, 4, depth),
			CFrame.new(centerX, seabedY - 2, centerZ),
			palette.cliff,
			{ material = M.Sand }
		).Name =
			"Seabed"
		-- (The water is a thin sheet, so no edge shows where one section meets the next.)
		block(
			folder,
			Vector3.new(width, WATER_SHEET, depth),
			CFrame.new(centerX, base - WATER_DROP - WATER_SHEET / 2, centerZ),
			{ 56, 168, 214 },
			{ material = M.Glass, transparency = 0.45, collide = false }
		).Name =
			"Water"
	end
	-- A lighthouse on a rock off one side.
	local middleZ = startZ + Runway.zoneLength(zoneId) / 2 + 90
	buildProp(folder, "Lighthouse", RunwayFrame.atHeight(Runway.halfWidthAt(middleZ) + 90, middleZ, seabedY), 5, random)
end

-- One edge of the Ocean's boardwalk (side = -1 or 1): posts and ropes, piles down to the seabed, and an invisible
-- wall so nobody walks off into the sea, all broken at the gaps. Returns the seabed beside it, where the reef's
-- scenery stands.
local function buildSea(folder: Instance, zoneId: number, palette: Palette, side: number, random: Random): { Top }
	local seabedY = Runway.surfaceY(Runway.zoneStartZ(zoneId)) - SEABED_DROP
	local tops: { Top } = {}
	for _, stretch in stretchesOf(zoneId, side) do
		for _, piece in piecesOf({ stretch }, TILE) do
			local z0, z1 = piece[1], piece[2]
			local edge0, edge1 = Runway.halfWidthAt(z0) + 1, Runway.halfWidthAt(z1) + 1
			local frame, span = alongSlope(side * edge0, z0, side * edge1, z1)
			block(folder, Vector3.new(1, 24, span + 0.1), frame * CFrame.new(side * 0.5, 10, 0), {
				255,
				255,
				255,
			}, { transparency = 1 }).Name =
				"SeaWall"
			for _, height in { 2.4, 3.6 } do
				block(
					folder,
					Vector3.new(0.3, 0.3, span + 0.1),
					frame * CFrame.new(0, height, 0),
					{ 214, 190, 140 },
					{ material = M.Fabric, collide = false }
				).Name =
					"Rope"
			end
		end
		for z = stretch[1] + 0.6, stretch[2], 10 do
			local edge = Runway.halfWidthAt(z) + 1
			block(folder, Vector3.new(1.2, 4, 1.2), RunwayFrame.at(side * edge, z, 2), palette.kerb, {
				material = M.Wood,
			}).Name =
				"Post"
			-- A pile under the boardwalk, as tall as the boardwalk is high over the seabed there.
			local deck = Runway.surfaceY(z) - 1
			column(
				folder,
				1.6,
				deck - seabedY,
				RunwayFrame.atHeight(side * (edge - 1), z, seabedY),
				shade(palette.kerb, -0.15),
				{ material = M.Wood, collide = false }
			)
		end
	end
	-- The seabed further out, where the scenery stands: twice over, for a busier reef.
	local startZ = Runway.zoneStartZ(zoneId)
	for z = startZ, startZ + Runway.zoneLength(zoneId) - TILE, TILE do
		for _ = 1, 2 do
			local at = z + TILE * 0.5 + (random() - 0.5) * 12
			table.insert(tops, {
				frame = RunwayFrame.atHeight(side * (Runway.halfWidthAt(at) + 1), at, seabedY),
				x0 = 10,
				x1 = 130,
				length = 8,
				chance = 0.45,
			})
		end
	end
	return tops
end

-- Stands the zone's plants and rocks on the tops of the walls (or the reef).
local function dressBanks(folder: Instance, palette: Palette, tops: { Top }, side: number, random: Random)
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = folder
	for _, top in tops do
		if random() < top.chance then
			local prop = pickProp(random, palette.props)
			local size = (prop.size or 3) * between(random, 0.85, 1.2)
			local margin = math.min(size + 1, (top.x1 - top.x0) / 2)
			local out = between(random, top.x0 + margin, top.x1 - margin)
			local turn = CFrame.Angles(0, (random() - 0.5) * 0.8, 0)
			buildProp(
				props,
				prop.kind,
				top.frame * CFrame.new(side * out, 0, (random() - 0.5) * top.length * 0.6) * turn,
				size,
				random
			)
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Backdrop

-- How far a hill must stand from the runway's centre line, beyond the runway itself: clear of the walls.
local BACKDROP_CLEARANCE = 170

local function buildBackdrop(folder: Instance, zoneId: number, palette: Palette, random: Random)
	local backdrop = Instance.new("Folder")
	backdrop.Name = "Backdrop"
	backdrop.Parent = folder
	local startZ = Runway.zoneStartZ(zoneId)
	local endZ = startZ + Runway.zoneLength(zoneId)
	for _, side in { -1, 1 } do
		local z = startZ + random() * 60
		while z < endZ do
			local width = between(random, 110, 220)
			local out = Runway.halfWidthAt(z) + between(random, 250, 420)
			local base = RunwayFrame.at(side * out, z)
			local layers = if zoneId == 2 then 2 else 4
			local volcano = zoneId == 5 or (zoneId == 6 and random() < 0.3)
			local heights, depths, turns = {}, {}, {}
			for layer = 1, layers do
				heights[layer] = if zoneId == 2 then between(random, 80, 150) else between(random, 40, 75)
				depths[layer] = between(random, 0.7, 1)
				turns[layer] = (random() - 0.5) * 0.3
			end
			-- On the inside of a bend, that far out can be right across the bend, back beside the runway further
			-- on. A hill is only built where it really is clear of the runway and its walls.
			local x = Runway.fromWorld(base.X, base.Z)
			if math.abs(x) >= Runway.halfWidthAt(z) + BACKDROP_CLEARANCE + width / 2 then
				local y = base.Y - 30
				local size = width
				for layer = 1, layers do
					local height = heights[layer]
					local color = shade(palette.backdrop, (layer - 1) * 0.05)
					if palette.backdropTop and layer == layers then
						color = palette.backdropTop
					end
					block(
						backdrop,
						Vector3.new(size, height, size * depths[layer]),
						atHeight(base, y + height / 2) * CFrame.Angles(0, turns[layer], 0),
						color,
						{
							material = if palette.backdropTop and layer == layers
								then M.Snow
								else palette.cliffMaterial,
						}
					)
					y += height
					size *= if zoneId == 2 then 0.85 else 0.66
				end
				if volcano then
					-- A glowing crater and a plume of smoke.
					local crater = block(
						backdrop,
						Vector3.new(size * 0.8, 1, size * 0.8),
						atHeight(base, y + 0.5),
						{ 255, 110, 30 },
						{ material = M.Neon }
					)
					ObstacleModels.emitter(crater, "Smoke", { 80, 74, 74 }, {
						size = 18,
						rate = 3,
						speed = 10,
						life = 9,
						lift = 2,
						spread = 15,
					})
				end
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

-- How high the sign hangs over the runway, and how tall the posts that carry it are: taller than the walls beside
-- them, so they stand out against the sky.
local GATE_HEIGHT = 34
local GATE_POST_HEIGHT = 78
-- How far the posts go down below the runway (in the Ocean they stand in the sea).
local GATE_POST_FOOT = 10

local function buildGate(folder: Instance, zoneId: number)
	local zone = Zones.List[zoneId]
	local accent = zone.accent
	local startZ = Runway.zoneStartZ(zoneId)
	local width = Runway.widthAt(startZ)
	local posts = width / 2 + KERB + 3
	for _, side in { -1, 1 } do
		local post = block(
			folder,
			Vector3.new(7, GATE_POST_HEIGHT + GATE_POST_FOOT, 7),
			RunwayFrame.at(side * posts, startZ, (GATE_POST_HEIGHT - GATE_POST_FOOT) / 2),
			accent,
			{ material = M.Wood }
		)
		post.Name = "SignPost"
		block(
			folder,
			Vector3.new(8.5, 2, 8.5),
			RunwayFrame.at(side * posts, startZ, GATE_POST_HEIGHT + 1),
			shade(accent, 0.2),
			{ material = M.Wood }
		)
	end
	local sign = block(
		folder,
		Vector3.new(width + 12, 12, 2),
		RunwayFrame.at(0, startZ, GATE_HEIGHT),
		accent,
		{ material = M.WoodPlanks }
	)
	sign.Name = "Sign"
	block(
		folder,
		Vector3.new(width + 16, 1.2, 2.6),
		RunwayFrame.at(0, startZ, GATE_HEIGHT + 6.6),
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

-- The height of the sea's surface in a zone that has a sea (the Ocean), or nil. Anyone below it has fallen in.
function Scenery.seaLevel(zoneId: number): number?
	local palette = PALETTES[zoneId]
	if palette and palette.sea then
		return Runway.surfaceY(Runway.zoneStartZ(zoneId)) - WATER_DROP
	end
	return nil
end

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
	if palette.sea then
		buildSeaFloor(banks, zoneId, palette, random)
	end
	for _, side in { -1, 1 } do
		local tops = if palette.sea
			then buildSea(banks, zoneId, palette, side, random)
			else buildWalls(banks, zoneId, palette, side, random)
		dressBanks(banks, palette, tops, side, random)
	end
	buildBackdrop(folder, zoneId, palette, random)
	return folder
end

-- The runway has no end: past it, the last zone again, Runway.REPEATS times (see Shared/Runway). Every scenery part is
-- anchored, and the last zone ends heading the way it started, so each copy is the last zone's finished folder moved
-- one loop further on. The copies' obstacles are built with the rest (Shared/Obstacles lays them out).
function Scenery.buildRepeats(map: Instance, lastZone: Instance)
	for copy = 1, Runway.REPEATS do
		local folder = lastZone:Clone()
		folder.Name = lastZone.Name .. "Repeat" .. copy
		local shift = RunwayFrame.loopShift() * copy
		for _, descendant in folder:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CFrame += shift
			end
		end
		folder.Parent = map
	end
end

-- Builds one obstacle from Shared/Obstacles into `parent`, tagged with its id for the client. One that lies in the
-- ground (a lava pool, a tar pit, a vent) is tipped to lie on the slope; one that stands on it stands upright, sunk
-- just far enough that its downhill side still meets the ground.
function Scenery.buildObstacle(parent: Instance, obstacle): Model
	local model = Build.model(parent, obstacle.kind .. obstacle.id)
	model:SetAttribute("ObstacleId", obstacle.id)
	model:SetAttribute("Kind", obstacle.kind)
	model:SetAttribute("Timed", obstacle.timing ~= nil)
	local base = if obstacle.flat
		then RunwayFrame.onSlope(obstacle.x, obstacle.z)
		else RunwayFrame.at(obstacle.x, obstacle.z, -math.abs(Runway.slope(obstacle.z)) * obstacle.hz)
	ObstacleModels.build(model, obstacle.kind, base, obstacle.hx, obstacle.hz, obstacle.seed)
	return model
end

return Scenery
