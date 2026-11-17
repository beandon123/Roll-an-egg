-- Builds the roller of each training stick tier (Config/Sticks) out of parts: the part a player stands on and rolls.
-- The server puts one on every plot's stand (Server/Map/TrainingStand); the client shows them in the upgrade panel.
--
-- A roller is built round the origin, lying along Z: the axle runs down Z, and the roller turns about it. At rest
-- its top is up (a plank lies flat, a girder stands upright, the crystal has a face on top).
--
-- How the Model is put together:
--     Root      Its PrimaryPart: invisible, at the origin and unturned, so the model's pivot is the axle's frame.
--     Axle      The steel rod everything turns on, as long as the stand is wide.
--     the rest  The tier's parts. Every part is anchored and does not collide.
-- Parts tagged with the attribute "Rainbow" (the Rainbow Crystal's core) are cycled through the rainbow by the client.
--
--     1 Stick            a crooked twig with knots, two little side shoots and leaves
--     2 Plank            three boards side by side, nailed, with iron bands round the ends
--     3 Short Log        a stubby log with ridged bark, tree rings on its cut ends, a toadstool and moss
--     4 Tree Trunk       a long, rugged trunk with bark plates, moss, branch stubs and a sapling
--     5 Metal Pipe       a steel pipe with bolted flanges, gold bands and rows of rivets
--     6 Steel Girder     a riveted red I-beam with holes in its web, end plates and a stencil
--     7 Marble Column    a fluted white column with gold bands, round capitals and purple gems
--     8 Rainbow Crystal  a glowing six-sided crystal: rainbow facets round a shining core, stepped tips, sparkles

local Sticks = require(script.Parent.Config.Sticks)
local Plots = require(script.Parent.Plots)
local Runway = require(script.Parent.Runway)

local StickModels = {}

----------------------------------------------------------------------------------------------------------------
-- Where things are on a plot's stand (the server builds it there; the client spins its roller and poses its rider
-- from the same numbers, never from the parts)

-- The middle of a plot's stand on the plaza, turned with the plot: X points into the pen, Z runs along the fence.
function StickModels.standCFrame(index: number): CFrame
	local x, z = Plots.stickSpot(index)
	return CFrame.new(x, Runway.BASE_Y, z) * CFrame.Angles(0, Plots.yaw(index), 0)
end

-- The roller's axle on a plot's stand, at rest: the roller turns about this CFrame's Z axis.
function StickModels.axleCFrame(index: number, level: number): CFrame
	return StickModels.standCFrame(index) * CFrame.new(0, Sticks.axleHeight(level), 0)
end

-- Where a rider's HumanoidRootPart goes on a plot's stand: over the middle of the roller, `legs` studs above its
-- top (from the root part's middle down to the soles), facing out to the plaza.
function StickModels.riderCFrame(index: number, level: number, legs: number): CFrame
	return StickModels.axleCFrame(index, level)
		* CFrame.new(0, Sticks.maxTop(level) + legs, 0)
		* CFrame.Angles(0, math.pi / 2, 0)
end

-- The turn of a roller `angle` radians round from rest, about its axle. Positive turns carry the top of the roller
-- back under the rider's feet as they run forward (towards the plaza).
function StickModels.spin(angle: number): CFrame
	-- The rider faces -X; turning about Z the negative way moves the top of the roller towards +X.
	return CFrame.Angles(0, 0, -angle)
end

----------------------------------------------------------------------------------------------------------------
-- Building

local AXLE_RADIUS = 0.22

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- Turns a CFrame so a cylinder (which lies along its own X axis) lies along the CFrame's Z axis.
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

type Builder = {
	model: Model,
	count: number,
}

local function newPart(
	builder: Builder,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: { number },
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	builder.count += 1
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material or Enum.Material.SmoothPlastic
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Color = rgb(color)
	part.Parent = builder.model
	return part
end

-- A box.
local function box(builder: Builder, name: string, size: Vector3, cframe: CFrame, color, material: Enum.Material?)
	return newPart(builder, name, size, cframe, color, material)
end

-- A cylinder of `radius` and `length`, centred on `cframe` and lying along its Z axis.
local function rod(builder: Builder, name: string, radius: number, length: number, cframe: CFrame, color, material)
	return newPart(
		builder,
		name,
		Vector3.new(length, radius * 2, radius * 2),
		cframe * ALONG_Z,
		color,
		material,
		Enum.PartType.Cylinder
	)
end

local function ball(builder: Builder, name: string, diameter: number, cframe: CFrame, color, material)
	return newPart(builder, name, Vector3.one * diameter, cframe, color, material, Enum.PartType.Ball)
end

-- A point on the roller's surface: `radius` out from the axle at `angle` (radians from straight up, turning towards
-- +X), `z` along it, turned so its X axis points out from the axle (a box placed here with size X small stands
-- out from the surface like a ridge).
local function onSurface(radius: number, angle: number, z: number): CFrame
	return CFrame.Angles(0, 0, -angle) * CFrame.new(0, radius, z) * CFrame.Angles(0, 0, math.pi / 2)
end

-- Rings on a cut end of wood, from the bark in: alternating light and dark wood. `face` is +1 for the +Z end.
local function treeRings(builder: Builder, z: number, face: number, radius: number, rings: number)
	local light, dark = { 226, 188, 134 }, { 192, 148, 96 }
	for ring = 0, rings do
		local r = radius * (1 - ring / (rings + 1))
		local depth = 0.06 + ring * 0.012
		rod(
			builder,
			"Ring",
			r,
			depth,
			CFrame.new(0, 0, z + face * depth / 2),
			if ring % 2 == 0 then light else dark,
			Enum.Material.Wood
		)
	end
end

----------------------------------------------------------------------------------------------------------------
-- The tiers

local builders: { [string]: (Builder, Sticks.Tier) -> () } = {}

-- 1: a crooked twig.
builders.Stick = function(b, tier)
	local bark = { 112, 80, 50 }
	local half = tier.length / 2
	-- Five segments, each a little off line, so the twig is not quite straight.
	local bends = { { 0.04, -0.03 }, { -0.03, 0.02 }, { 0, 0 }, { 0.03, 0.04 }, { -0.05, -0.02 } }
	local segment = tier.length / #bends
	for index, bend in bends do
		local z = -half + segment * (index - 0.5)
		local radius = 0.45 - math.abs(index - 3) * 0.025
		rod(b, "Twig", radius, segment + 0.12, CFrame.new(bend[1], bend[2], z), bark, Enum.Material.Wood)
	end
	-- Knots in the bark.
	for index, knot in { { 0.4, -2.6 }, { 2.4, 1.8 }, { 4.1, 3.6 }, { 1.2, -4.1 } } do
		ball(b, "Knot" .. index, 0.34, onSurface(0.36, knot[1], knot[2]), { 84, 58, 36 }, Enum.Material.Wood)
	end
	-- Freshly snapped ends.
	for _, face in { -1, 1 } do
		rod(b, "End", 0.38, 0.06, CFrame.new(0, 0, face * (half + 0.02)), { 218, 184, 130 }, Enum.Material.Wood)
	end
	-- Two little shoots, each with a pair of leaves.
	for index, shoot in { { 0.9, -3.4, 1 }, { 3.6, 2.9, -1 } } do
		local base = CFrame.Angles(0, 0, -shoot[1]) * CFrame.new(0, 0.4, shoot[2])
		local stem = base * CFrame.Angles(shoot[3] * 0.5, 0, 0) * CFrame.new(0, 0.18, 0)
		box(b, "Shoot" .. index, Vector3.new(0.12, 0.42, 0.12), stem, bark, Enum.Material.Wood)
		for leaf = -1, 1, 2 do
			box(
				b,
				"Leaf",
				Vector3.new(0.3, 0.05, 0.46),
				stem * CFrame.new(leaf * 0.16, 0.2, 0) * CFrame.Angles(0, leaf * 0.6, leaf * 0.5),
				if leaf < 0 then { 112, 206, 82 } else { 86, 178, 66 }
			)
		end
	end
end

-- 2: three boards side by side, nailed, with iron bands round the ends.
builders.Plank = function(b, tier)
	local profile = tier.profile :: { kind: "Box", halfWidth: number, halfHeight: number }
	local width, thick, half = profile.halfWidth * 2, profile.halfHeight * 2, tier.length / 2
	local woods = { { 204, 152, 96 }, { 214, 164, 106 }, { 196, 144, 90 } }
	local board = width / 3
	for index, wood in woods do
		local x = -width / 2 + board * (index - 0.5)
		box(
			b,
			"Board" .. index,
			Vector3.new(board - 0.04, thick, tier.length),
			CFrame.new(x, 0, 0),
			wood,
			Enum.Material.WoodPlanks
		)
	end
	-- The seams between the boards, dark lines on both faces.
	for _, x in { -board / 2, board / 2 } do
		box(
			b,
			"Seam",
			Vector3.new(0.06, thick + 0.02, tier.length),
			CFrame.new(x, 0, 0),
			{ 132, 92, 56 },
			Enum.Material.Wood
		)
	end
	-- End grain.
	for _, face in { -1, 1 } do
		box(
			b,
			"EndGrain",
			Vector3.new(width + 0.02, thick + 0.02, 0.06),
			CFrame.new(0, 0, face * half),
			{ 230, 192, 140 },
			Enum.Material.Wood
		)
	end
	-- Iron bands, and nails in every board near both ends, top and bottom.
	for _, face in { -1, 1 } do
		box(
			b,
			"Band",
			Vector3.new(width + 0.08, thick + 0.08, 0.34),
			CFrame.new(0, 0, face * (half - 0.7)),
			{ 64, 66, 76 },
			Enum.Material.Metal
		)
		for index = 1, 3 do
			local x = -width / 2 + board * (index - 0.5)
			for _, side in { -1, 1 } do
				local at = CFrame.new(x, side * (thick / 2 + 0.01), face * (half - 1.5))
					* CFrame.Angles(math.pi / 2, 0, 0)
				rod(b, "Nail", 0.07, 0.04, at, { 70, 70, 78 }, Enum.Material.Metal)
			end
		end
	end
end

-- 3: a stubby log, with tree rings on its cut ends.
builders.ShortLog = function(b, tier)
	local radius, half = (tier.profile :: any).radius, tier.length / 2
	rod(b, "Log", radius - 0.03, tier.length, CFrame.identity, { 128, 86, 54 }, Enum.Material.Wood)
	-- Ridges of bark all round, which also show it turning.
	for index = 1, 10 do
		local angle = (index - 1) / 10 * math.pi * 2 + 0.15
		local shade = if index % 2 == 0 then { 98, 66, 42 } else { 110, 74, 46 }
		box(
			b,
			"Bark",
			Vector3.new(0.16, 0.3, tier.length - 0.1),
			onSurface(radius - 0.04, angle, 0),
			shade,
			Enum.Material.Wood
		)
	end
	for _, face in { -1, 1 } do
		treeRings(b, face * half, face, radius - 0.08, 3)
	end
	-- A toadstool and a patch of moss, off to one side where the rider's feet will not land.
	local stool = onSurface(radius, 2.2, 2.6)
	box(b, "Stalk", Vector3.new(0.3, 0.16, 0.16), stool * CFrame.new(0.12, 0, 0), { 240, 232, 214 })
	rod(b, "Cap", 0.3, 0.2, stool * CFrame.new(0.3, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), { 226, 64, 52 })
	ball(b, "Spot", 0.12, stool * CFrame.new(0.4, 0.12, 0.1), { 255, 255, 255 })
	box(b, "Moss", Vector3.new(0.1, 0.8, 1.6), onSurface(radius, 4.1, -2.2), { 104, 176, 72 }, Enum.Material.Grass)
end

-- 4: a long, rugged trunk.
builders.TreeTrunk = function(b, tier)
	local radius, half = (tier.profile :: any).radius, tier.length / 2
	rod(b, "Trunk", radius - 0.06, tier.length, CFrame.identity, { 92, 64, 44 }, Enum.Material.Wood)
	-- Plates of bark in two staggered rows, a little uneven, as old bark is.
	for index = 1, 12 do
		local angle = (index - 1) / 12 * math.pi * 2
		local split = if index % 2 == 0 then 1.4 else -1.8
		local shades = { { 78, 54, 36 }, { 102, 72, 48 }, { 88, 62, 40 } }
		for part, span in { { -half, split }, { split, half } } do
			local length = span[2] - span[1] - 0.12
			box(
				b,
				"Bark",
				Vector3.new(0.2, 0.62, length),
				onSurface(radius - 0.06, angle + (part - 1.5) * 0.06, (span[1] + span[2]) / 2),
				shades[(index + part) % 3 + 1],
				Enum.Material.Wood
			)
		end
	end
	-- Moss on the old wood.
	for index, patch in { { 0.6, -3.4, 2.4 }, { 2.7, 2.2, 3 }, { 4.4, -0.4, 1.6 } } do
		box(
			b,
			"Moss" .. index,
			Vector3.new(0.14, 1.1, patch[3]),
			onSurface(radius + 0.03, patch[1], patch[2]),
			{ 98, 172, 70 },
			Enum.Material.Grass
		)
	end
	-- Two branch stubs, sawn off.
	for index, stub in { { 2.0, 4.0 }, { 5.1, -3.6 } } do
		local at = onSurface(radius, stub[1], stub[2])
		local stem = at * CFrame.new(0.15, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
		rod(b, "Stub" .. index, 0.3, 0.42, stem, { 96, 66, 44 }, Enum.Material.Wood)
		rod(b, "StubEnd" .. index, 0.24, 0.44, stem, { 222, 182, 128 }, Enum.Material.Wood)
	end
	-- A sapling sprouting from the bark.
	local sprout = onSurface(radius, 3.3, -4.6)
	box(b, "Sapling", Vector3.new(0.6, 0.1, 0.1), sprout * CFrame.new(0.3, 0, 0), { 110, 150, 60 })
	for leaf = -1, 1, 2 do
		box(
			b,
			"SaplingLeaf",
			Vector3.new(0.06, 0.34, 0.5),
			sprout * CFrame.new(0.55, leaf * 0.16, 0) * CFrame.Angles(leaf * 0.5, 0, 0),
			{ 120, 214, 90 }
		)
	end
	for _, face in { -1, 1 } do
		treeRings(b, face * half, face, radius - 0.12, 5)
	end
end

-- 5: a steel pipe.
builders.MetalPipe = function(b, tier)
	local radius, half = (tier.profile :: any).radius, tier.length / 2
	local steel, dark, gold = { 182, 190, 202 }, { 112, 120, 134 }, { 255, 196, 60 }
	local pipe = rod(b, "Pipe", radius, tier.length - 0.6, CFrame.identity, steel, Enum.Material.Metal)
	pipe.Reflectance = 0.12
	-- Bolted flanges, and the open, dark ends of the pipe.
	for _, face in { -1, 1 } do
		local z = face * (half - 0.2)
		local flange = rod(b, "Flange", 1.45, 0.4, CFrame.new(0, 0, z), dark, Enum.Material.Metal)
		flange.Reflectance = 0.1
		rod(b, "Bore", 0.86, 0.44, CFrame.new(0, 0, z), { 24, 26, 32 })
		for bolt = 1, 8 do
			local angle = bolt / 8 * math.pi * 2
			rod(
				b,
				"Bolt",
				0.1,
				0.5,
				CFrame.new(math.sin(angle) * 1.24, math.cos(angle) * 1.24, z),
				{ 60, 62, 70 },
				Enum.Material.Metal
			)
		end
	end
	-- Gold bands, clear of the rider's feet.
	for _, z in { -3, 3 } do
		local band = rod(b, "GoldBand", radius + 0.03, 0.45, CFrame.new(0, 0, z), gold, Enum.Material.Metal)
		band.Reflectance = 0.25
	end
	-- Two seams of rivets, opposite each other: they show it turning.
	for _, angle in { math.pi / 2, math.pi * 1.5 } do
		for step = -4, 4 do
			ball(b, "Rivet", 0.2, onSurface(radius, angle, step * 1.05), { 140, 148, 160 }, Enum.Material.Metal)
		end
	end
end

-- 6: a riveted red I-beam, upright.
builders.SteelGirder = function(b, tier)
	local profile = tier.profile :: { kind: "Box", halfWidth: number, halfHeight: number }
	local width, depth, half = profile.halfWidth * 2, profile.halfHeight * 2, tier.length / 2
	local paint, deep = { 214, 72, 44 }, { 158, 50, 32 }
	local flange = 0.3
	for _, side in { -1, 1 } do
		box(
			b,
			"Flange",
			Vector3.new(width, flange, tier.length),
			CFrame.new(0, side * (depth - flange) / 2, 0),
			paint,
			Enum.Material.Metal
		)
		-- Rivets in two rows down the outside of each flange.
		for _, x in { -0.75, 0.75 } do
			for step = -4, 4 do
				ball(b, "Rivet", 0.2, CFrame.new(x, side * depth / 2, step * 1.15), deep, Enum.Material.Metal)
			end
		end
	end
	local web =
		box(b, "Web", Vector3.new(0.32, depth - flange * 2, tier.length), CFrame.identity, paint, Enum.Material.Metal)
	-- Round holes through the web.
	for _, z in { -3.6, 0, 3.6 } do
		newPart(b, "Hole", Vector3.new(0.36, 1, 1), CFrame.new(0, 0, z), { 40, 30, 30 }, nil, Enum.PartType.Cylinder)
	end
	-- Plates bolted across both ends.
	for _, face in { -1, 1 } do
		box(
			b,
			"EndPlate",
			Vector3.new(width + 0.1, depth + 0.1, 0.16),
			CFrame.new(0, 0, face * (half + 0.06)),
			deep,
			Enum.Material.DiamondPlate
		)
		for _, corner in { { -0.7, -0.9 }, { 0.7, -0.9 }, { -0.7, 0.9 }, { 0.7, 0.9 } } do
			rod(
				b,
				"Bolt",
				0.1,
				0.12,
				CFrame.new(corner[1], corner[2], face * (half + 0.18)),
				{ 60, 50, 50 },
				Enum.Material.Metal
			)
		end
	end
	-- A stencil on both sides of the web.
	for index, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Stencil"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 1
		gui.Parent = web
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		-- Between two of the holes.
		label.Position = UDim2.fromScale(if index == 1 then 0.335 else 0.665, 0.5)
		label.Size = UDim2.fromScale(0.22, 0.5)
		label.Font = Enum.Font.Oswald
		label.Text = "HEAVY DUTY"
		label.TextColor3 = Color3.fromRGB(255, 236, 214)
		label.TextTransparency = 0.15
		label.TextScaled = true
		label.Parent = gui
	end
end

-- 7: a fluted marble column.
builders.MarbleColumn = function(b, tier)
	local radius, half = (tier.profile :: any).radius, tier.length / 2
	local marble, vein, gold = { 242, 238, 232 }, { 214, 208, 200 }, { 240, 186, 64 }
	rod(b, "Shaft", radius - 0.05, tier.length - 1, CFrame.identity, marble, Enum.Material.Marble)
	-- Flutes all the way round.
	for index = 1, 12 do
		local angle = (index - 0.5) / 12 * math.pi * 2
		box(
			b,
			"Flute",
			Vector3.new(0.1, 0.24, tier.length - 2.4),
			onSurface(radius - 0.04, angle, 0),
			vein,
			Enum.Material.Marble
		)
	end
	local function goldRing(name: string, r: number, length: number, z: number)
		local ring = rod(b, name, r, length, CFrame.new(0, 0, z), gold, Enum.Material.Metal)
		ring.Reflectance = 0.3
	end
	for _, z in { -2.8, 2.8 } do
		goldRing("GoldBand", radius + 0.02, 0.22, z)
	end
	-- Round capitals at both ends: a moulding, a gold ring, a broad block, and a glowing gem.
	for _, face in { -1, 1 } do
		local z = face * (half - 0.25)
		rod(b, "Moulding", radius + 0.18, 0.4, CFrame.new(0, 0, z - face * 0.55), marble, Enum.Material.Marble)
		goldRing("CapitalRing", radius + 0.24, 0.14, z - face * 0.28)
		rod(b, "Capital", (tier.reach - 0.05), 0.5, CFrame.new(0, 0, z), marble, Enum.Material.Marble)
		ball(b, "Gem", 0.62, CFrame.new(0, 0, z + face * 0.22), { 176, 120, 255 }, Enum.Material.Neon)
	end
	-- A soft shimmer.
	local shimmer = Instance.new("ParticleEmitter")
	shimmer.Name = "Shimmer"
	shimmer.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	shimmer.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 160, 255))
	shimmer.LightEmission = 1
	shimmer.Rate = 4
	shimmer.Lifetime = NumberRange.new(0.8, 1.4)
	shimmer.Speed = NumberRange.new(0.2, 0.8)
	shimmer.SpreadAngle = Vector2.new(180, 180)
	shimmer.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	shimmer.Parent = b.model:FindFirstChild("Shaft")
end

-- 8: a glowing rainbow crystal.
builders.RainbowCrystal = function(b, tier)
	local radius, half = (tier.profile :: any).radius, tier.length / 2
	local apothem = radius * math.sqrt(3) / 2
	local body = tier.length - 2.2
	local hues =
		{ { 255, 92, 120 }, { 255, 170, 70 }, { 255, 236, 90 }, { 110, 236, 120 }, { 90, 170, 255 }, { 190, 110, 255 } }
	-- Six facets round a shining core, each a colour of the rainbow, with bright edges between them.
	for face = 0, 5 do
		local angle = face * math.pi / 3 + math.pi / 6
		local facet = box(
			b,
			"Facet",
			Vector3.new(0.14, radius, body),
			CFrame.Angles(0, 0, angle) * CFrame.new(apothem - 0.07, 0, 0),
			hues[face + 1],
			Enum.Material.Glass
		)
		facet.Transparency = 0.3
		facet.Reflectance = 0.2
		local edge = rod(
			b,
			"Edge",
			0.07,
			body,
			CFrame.Angles(0, 0, face * math.pi / 3) * CFrame.new(radius - 0.05, 0, 0),
			{ 255, 255, 255 },
			Enum.Material.Neon
		)
		edge.Transparency = 0.1
	end
	local core = rod(b, "Core", 0.62, body + 0.2, CFrame.identity, { 170, 255, 250 }, Enum.Material.Neon)
	core:SetAttribute("Rainbow", true)
	-- Stepped tips at both ends: smaller and smaller crystals, then a glowing point.
	for _, face in { -1, 1 } do
		local z = face * body / 2
		for step, size in { { 1.15, 0.5 }, { 0.75, 0.45 } } do
			local r, length = size[1], size[2]
			local at = z + face * ((step - 1) * 0.5 + length / 2)
			for turn = 0, 2 do
				local tip = box(
					b,
					"Tip",
					Vector3.new(r, r * math.sqrt(3), length),
					CFrame.new(0, 0, at) * CFrame.Angles(0, 0, turn * math.pi / 3),
					{ 214, 250, 255 },
					Enum.Material.Glass
				)
				tip.Transparency = 0.15
			end
		end
		local point =
			ball(b, "Point", 0.55, CFrame.new(0, 0, face * (half - 0.2)), { 255, 255, 255 }, Enum.Material.Neon)
		point:SetAttribute("Rainbow", true)
	end
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = Color3.fromRGB(170, 255, 250)
	glow.Brightness = 1.6
	glow.Range = 14
	glow.Shadows = false
	glow.Parent = core
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	local keypoints = {}
	for index, hue in hues do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#hues - 1), rgb(hue)))
	end
	sparkles.Color = ColorSequence.new(keypoints)
	sparkles.LightEmission = 1
	sparkles.Rate = 10
	sparkles.Lifetime = NumberRange.new(0.8, 1.5)
	sparkles.Speed = NumberRange.new(0.5, 1.6)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.RotSpeed = NumberRange.new(-90, 90)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Parent = core
end

----------------------------------------------------------------------------------------------------------------

-- The roller of a tier (level 1 to Sticks.MAX_LEVEL), built round the origin and lying along Z.
function StickModels.buildRoller(level: number): Model
	local tier = Sticks.tier(level)
	local model = Instance.new("Model")
	model.Name = tier.id
	model:SetAttribute("Level", tier.level)
	local b: Builder = { model = model, count = 0 }

	-- The pivot: unturned, so the model's pivot is the axle's own frame (the axle itself is a cylinder, turned to lie
	-- along Z).
	local root = box(b, "Root", Vector3.one * 0.2, CFrame.identity, { 255, 255, 255 })
	root.Transparency = 1
	model.PrimaryPart = root
	local axle = rod(b, "Axle", AXLE_RADIUS, Sticks.POST_SPAN, CFrame.identity, { 150, 156, 168 }, Enum.Material.Metal)
	axle.Reflectance = 0.15

	builders[tier.id](b, tier)
	return model
end

-- How many parts a tier's roller is made of (for tests).
function StickModels.partCount(level: number): number
	local model = StickModels.buildRoller(level)
	local count = 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			count += 1
		end
	end
	model:Destroy()
	return count
end

return StickModels
