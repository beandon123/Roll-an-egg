-- Builds each zone's stretch of runway and everything around it, in the blocky style of the eggs and pets:
--     Ground    the level runway, checkered in the zone's colours, blending into the next zone over its last rows
--     Banks     stepped cliffs up both sides, walls players cannot climb, topped with the zone's plants and rocks
--               (the Ocean zone is a boardwalk over a reef instead, with railings along its edges)
--     Backdrop  big blocky hills, mesas, mountains or volcanoes in the distance
--     Gate      an arch over the start of the zone with its name and the stamina its eggs need
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
-- Where the banks begin: the runway's edge plus a kerb.
local EDGE = Runway.WIDTH / 2 + 1

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
-- Ground

local function buildGround(folder: Instance, zoneId: number, palette: Palette, nextPalette: Palette?, random: Random)
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = folder
	local startZ = Runway.zoneStartZ(zoneId)
	local rows = Runway.ZONE_LENGTH // TILE
	local columns = Runway.WIDTH // TILE
	for row = 0, rows - 1 do
		-- The last few rows blend into the next zone's colours.
		local blend = if nextPalette then math.clamp((row - (rows - 5)) / 5, 0, 1) else 0
		for col = 0, columns - 1 do
			local tone = palette.ground[(row + col) % 2 + 1]
			if nextPalette and blend > 0 then
				tone = Build.mix(tone, nextPalette.ground[(row + col) % 2 + 1], blend)
			end
			block(
				ground,
				Vector3.new(TILE, SLAB, TILE),
				CFrame.new(
					-Runway.WIDTH / 2 + TILE * (col + 0.5),
					Runway.BASE_Y - SLAB / 2,
					startZ + TILE * (row + 0.5)
				),
				vary(random, tone, 0.015),
				{
					material = if blend > 0.5 and nextPalette
						then nextPalette.groundMaterial
						else palette.groundMaterial,
				}
			)
		end
	end

	-- A kerb along each edge.
	for _, side in { -1, 1 } do
		block(
			ground,
			Vector3.new(2, 1, Runway.ZONE_LENGTH),
			CFrame.new(side * (Runway.WIDTH / 2 + 1), Runway.BASE_Y + 0.5, startZ + Runway.ZONE_LENGTH / 2),
			palette.kerb,
			{ material = M.Concrete }
		)
	end

	-- The volcano's ground glows through cracks.
	if zoneId == 5 then
		for _ = 1, 40 do
			block(
				ground,
				Vector3.new(between(random, 3, 9), 0.1, 0.35),
				CFrame.new(
					(random() - 0.5) * (Runway.WIDTH - 6),
					Runway.BASE_Y + 0.03,
					startZ + random() * Runway.ZONE_LENGTH
				) * CFrame.Angles(0, random() * math.pi, 0),
				{ 255, 110, 30 },
				{ material = M.Neon, collide = false }
			)
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Banks

-- Stepped cliffs up one side of the runway (side = -1 or 1). Returns the steps' tops, for the props.
local function buildCliffs(folder: Instance, zoneId: number, palette: Palette, side: number, random: Random)
	local startZ = Runway.zoneStartZ(zoneId)
	local phase = random() * 10
	local tops = {}
	for col = 0, Runway.ZONE_LENGTH // TILE - 1 do
		local z = startZ + TILE * (col + 0.5)
		local wave = math.sin(z / 85 + phase) + 0.5 * math.sin(z / 37 + phase * 2)
		local steps = {
			{ width = 18 + 6 * random(), height = 12 + 3 * wave + 3 * random() },
			{ width = 22 + 10 * random(), height = 0 },
			{ width = 40, height = 0 },
		}
		steps[2].height = steps[1].height + 8 + 6 * random()
		steps[3].height = steps[2].height + 10 + 12 * random()
		local inner = EDGE + 1
		for index, step in steps do
			local x = side * (inner + step.width / 2)
			local bottom = Runway.BASE_Y - SLAB
			local top = Runway.BASE_Y + step.height
			local face = vary(random, palette.cliff, 0.05)
			if palette.bands and index == 1 then
				-- Sandstone stripes, a few studs each.
				local y = bottom
				local band = col % #palette.bands
				while y < top - 1.5 do
					local height = math.min(top - 1.5 - y, 3 + (band % 2) * 1.5)
					block(
						folder,
						Vector3.new(step.width, height, TILE),
						CFrame.new(x, y + height / 2, z),
						palette.bands[band % #palette.bands + 1],
						{ material = palette.cliffMaterial }
					)
					y += height
					band += 1
				end
			else
				block(
					folder,
					Vector3.new(step.width, top - 1.5 - bottom, TILE),
					CFrame.new(x, (top - 1.5 + bottom) / 2, z),
					shade(face, -0.04 * (index - 1)),
					{ material = palette.cliffMaterial }
				)
			end
			block(
				folder,
				Vector3.new(step.width + 0.6, 1.5, TILE),
				CFrame.new(x - side * 0.3, top - 0.75, z),
				vary(random, palette.top, 0.03),
				{ material = palette.topMaterial }
			)
			if palette.lava and index == 1 then
				-- A lava river along the top of the first step, set into the rock.
				block(
					folder,
					Vector3.new(4, 0.4, TILE),
					CFrame.new(side * (inner + step.width * 0.62), top - 0.1, z),
					{ 255, 110, 26 },
					{ material = M.Neon, collide = false }
				)
			elseif palette.lava and index == 2 and random() < 0.3 then
				-- Lava pouring down the face of the second step into the river below.
				block(
					folder,
					Vector3.new(0.6, step.height - steps[1].height, between(random, 3, 6)),
					CFrame.new(side * (inner - 0.25), Runway.BASE_Y + (step.height + steps[1].height) / 2, z),
					{ 255, 130, 30 },
					{ material = M.Neon, collide = false }
				)
			end
			table.insert(tops, {
				x0 = inner + (if palette.lava and index == 1 then step.width * 0.62 + 3 else 0),
				x1 = inner + step.width,
				y = top,
				z = z,
				step = index,
			})
			inner += step.width
		end
	end
	return tops
end

-- A boardwalk's edges: posts and ropes, and an invisible wall so nobody walks off into the sea.
local function buildSea(folder: Instance, zoneId: number, palette: Palette, side: number, random: Random)
	local startZ = Runway.zoneStartZ(zoneId)
	local length = Runway.ZONE_LENGTH
	local middleZ = startZ + length / 2
	local seabedY = Runway.BASE_Y - 7
	local waterY = Runway.BASE_Y - 1.5
	local outer = 260
	block(
		folder,
		Vector3.new(outer - EDGE, 4, length),
		CFrame.new(side * (EDGE + (outer - EDGE) / 2), seabedY - 2, middleZ),
		palette.cliff,
		{ material = M.Sand }
	)
	block(
		folder,
		Vector3.new(outer - EDGE, 1, length),
		CFrame.new(side * (EDGE + (outer - EDGE) / 2), waterY - 0.5, middleZ),
		{ 56, 168, 214 },
		{ material = M.Glass, transparency = 0.45, collide = false }
	)
	block(
		folder,
		Vector3.new(1, 24, length),
		CFrame.new(side * (EDGE + 0.5), Runway.BASE_Y + 10, middleZ),
		{ 255, 255, 255 },
		{ transparency = 1 }
	).Name =
		"SeaWall"
	-- Posts with a rope between them, and piles under the boardwalk.
	for z = startZ + 5, startZ + length, 10 do
		block(folder, Vector3.new(1.2, 4, 1.2), CFrame.new(side * EDGE, Runway.BASE_Y + 2, z), palette.kerb, {
			material = M.Wood,
		})
		column(folder, 1.6, 9, CFrame.new(side * (EDGE - 1), seabedY, z), shade(palette.kerb, -0.15), {
			material = M.Wood,
			collide = false,
		})
	end
	for _, height in { 2.4, 3.6 } do
		block(
			folder,
			Vector3.new(0.3, 0.3, length),
			CFrame.new(side * EDGE, Runway.BASE_Y + height, middleZ),
			{ 214, 190, 140 },
			{ material = M.Fabric, collide = false }
		)
	end
	-- A lighthouse on a rock off one side.
	if side > 0 then
		buildProp(folder, "Lighthouse", CFrame.new(side * 150, seabedY, middleZ + 90), 5, random)
	end
	-- The seabed further out, where the scenery stands: twice over, for a busier reef.
	local tops = {}
	for col = 0, length // TILE - 1 do
		for _ = 1, 2 do
			table.insert(tops, {
				x0 = EDGE + 10,
				x1 = EDGE + 130,
				y = seabedY,
				z = startZ + TILE * (col + 0.5) + (random() - 0.5) * 12,
				step = 1,
			})
		end
	end
	return tops
end

local function dressBanks(folder: Instance, palette: Palette, tops, side: number, random: Random)
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = folder
	-- How likely each step is to get a prop in each column.
	local chance = { 0.55, 0.4, 0.25 }
	for _, top in tops do
		if random() < chance[top.step] then
			local prop = pickProp(random, palette.props)
			local size = (prop.size or 3) * between(random, 0.85, 1.2)
			local margin = math.min(size + 1, (top.x1 - top.x0) / 2)
			local x = side * between(random, top.x0 + margin, top.x1 - margin)
			local turn = CFrame.Angles(0, (random() - 0.5) * 0.8, 0)
			buildProp(props, prop.kind, CFrame.new(x, top.y, top.z + (random() - 0.5) * 8) * turn, size, random)
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
		while z < startZ + Runway.ZONE_LENGTH do
			local width = between(random, 70, 140)
			local x = side * between(random, 200, 320)
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

local GATE_HEIGHT = 34

local function buildGate(folder: Instance, zoneId: number)
	local zone = Zones.List[zoneId]
	local accent = zone.accent
	local startZ = Runway.zoneStartZ(zoneId)
	for _, side in { -1, 1 } do
		local post = block(
			folder,
			Vector3.new(6, GATE_HEIGHT + 6, 6),
			CFrame.new(side * (EDGE + 3), Runway.BASE_Y + (GATE_HEIGHT + 6) / 2 - 2, startZ),
			accent,
			{ material = M.Wood }
		)
		post.Name = "SignPost"
		block(
			folder,
			Vector3.new(7.5, 2, 7.5),
			CFrame.new(side * (EDGE + 3), Runway.BASE_Y + GATE_HEIGHT + 5, startZ),
			shade(accent, 0.2),
			{ material = M.Wood }
		)
	end
	local sign = block(
		folder,
		Vector3.new(Runway.WIDTH + 12, 10, 2),
		CFrame.new(0, Runway.BASE_Y + GATE_HEIGHT, startZ),
		accent,
		{ material = M.WoodPlanks }
	)
	sign.Name = "Sign"
	block(
		folder,
		Vector3.new(Runway.WIDTH + 16, 1.2, 2.6),
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
		dressBanks(banks, palette, tops, side, random)
	end
	buildBackdrop(folder, zoneId, palette, random)
	return folder
end

-- The drop at the end of the runway: a sheer cliff below its last edge, and a warning stripe before it.
function Scenery.buildEnd(map: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "End"
	folder.Parent = map
	block(
		folder,
		Vector3.new(Runway.WIDTH + 140, 160, 12),
		CFrame.new(0, Runway.BASE_Y - SLAB - 80, Runway.LENGTH - 6),
		{ 90, 70, 60 },
		{ material = M.Slate }
	)
	block(
		folder,
		Vector3.new(Runway.WIDTH, 0.3, 6),
		CFrame.new(0, Runway.BASE_Y + 0.1, Runway.LENGTH - 60),
		{ 255, 60, 60 },
		{ material = M.Neon, collide = false }
	).Name =
		"EdgeWarning"
end

-- Builds one obstacle from Shared/Obstacles into `parent`, tagged with its id for the client.
function Scenery.buildObstacle(parent: Instance, obstacle): Model
	local model = Build.model(parent, obstacle.kind .. obstacle.id)
	model:SetAttribute("ObstacleId", obstacle.id)
	model:SetAttribute("Kind", obstacle.kind)
	model:SetAttribute("Timed", obstacle.timing ~= nil)
	ObstacleModels.build(
		model,
		obstacle.kind,
		CFrame.new(obstacle.x, Runway.BASE_Y, obstacle.z),
		obstacle.hx,
		obstacle.hz,
		obstacle.seed
	)
	return model
end

return Scenery
