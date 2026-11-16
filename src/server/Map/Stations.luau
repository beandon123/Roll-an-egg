-- Builds the hub's stations from Shared/HubLayout: the Trails stall, the Sell stall, and the fuse machine. Each
-- has a ProximityPrompt that opens its panel on the player's device (Client/Controllers/StationController).
-- Gameplay reads positions from HubLayout, never from these parts.
--
-- The stalls are market booths: a raised wooden deck on a stone base, carved posts, a counter, a striped awning
-- with a row of pennants along its front, a framed signboard on top, and lanterns that light up at night. Each is
-- dressed for its trade: hanging trail samples and glowing display cases at the Trails stall; coin stacks, a
-- balance and crates of eggs at the Sell stall. The fuse machine is a glass chamber on gold-trimmed steps, with the
-- golden mystery egg floating inside, gears at its sides, four lamp pillars, and three pads in front for the pets
-- that go in. The Beams (glowing arcs) only show in the game, not in the map preview.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local HubLayout = require(Shared.HubLayout)
local Runway = require(Shared.Runway)
local Trails = require(Shared.Config.Trails)

local Build = require(script.Parent.Build)
local Parts = require(script.Parent.Parts)

type Rgb = Build.Rgb

local M = Enum.Material
local block, ball, column = Build.block, Build.ball, Build.column

local WOOD = { 150, 100, 60 }
local WOOD_DARK = { 98, 62, 38 }
local WOOD_LIGHT = { 214, 166, 112 }
local STONE = { 206, 202, 192 }
local STONE_DARK = { 150, 146, 140 }
local GOLD = { 246, 196, 60 }
local GOLD_DEEP = { 214, 150, 36 }
local WHITE = { 252, 250, 246 }
local LAMP = { 255, 214, 140 }
local EGGSHELL = { 255, 246, 226 }

export type Theme = {
	title: string,
	icon: string,
	main: Rgb,
	deep: Rgb,
	light: Rgb,
}

local TRAILS_THEME: Theme = {
	title = "TRAILS",
	icon = "✨",
	main = { 168, 92, 232 },
	deep = { 108, 52, 178 },
	light = { 220, 180, 255 },
}
local SELL_THEME: Theme = {
	title = "SELL",
	icon = "💰",
	main = { 232, 70, 70 },
	deep = { 168, 36, 46 },
	light = { 255, 186, 176 },
}
local FUSE_COLOR = Color3.fromRGB(245, 175, 30)

-- The booths' size: across, front to back, the height of the deck, and where the awning's front edge is.
local WIDTH = 24
local DEPTH = 14
local FLOOR = 1.3
local AWNING_FRONT = { y = FLOOR + 14, z = -DEPTH / 2 - 2 }
local AWNING_BACK = { y = FLOOR + 17.5, z = DEPTH / 2 + 0.6 }
-- The counter's middle, front to back, and the height of its top.
local COUNTER_Z = -DEPTH / 2 + 2.6
local COUNTER_TOP = FLOOR + 5.2

local Stations = {}

local Y = Runway.BASE_Y

-- A frame on the hub's ground at (x, z) whose front (-Z) faces `facing`.
local function groundFrame(x: number, z: number, facing: HubLayout.Point): CFrame
	local position = Vector3.new(x, Y, z)
	return CFrame.lookAt(position, position + Vector3.new(facing.x, 0, facing.z))
end

local function color(rgb: Rgb): Color3
	return Build.color(rgb)
end

-- Makes a part pure decoration: nothing collides with it, touches it, or hits it with a raycast.
local function trim(part: BasePart): BasePart
	return Parts.scenery(part)
end

-- A flat disc facing the front of `at` (-Z), `diameter` across and `thickness` deep.
local function plate(parent: Instance, at: CFrame, diameter: number, thickness: number, rgb: Rgb, options): BasePart
	local opts = table.clone(options or {})
	opts.shape = Enum.PartType.Cylinder
	-- A Roblox cylinder runs along its X axis; turn it to run front to back. Its Right face then faces the front.
	return Build.part(
		parent,
		"Plate",
		Vector3.new(thickness, diameter, diameter),
		at * CFrame.Angles(0, math.pi / 2, 0),
		rgb,
		opts
	)
end

local function light(parent: BasePart, rgb: Rgb, range: number, brightness: number): PointLight
	local glow = Instance.new("PointLight")
	glow.Color = color(rgb)
	glow.Range = range
	glow.Brightness = brightness
	glow.Shadows = false
	glow.Parent = parent
	return glow
end

local function sequence(colors: { Rgb }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(color(colors[1]))
	end
	local keypoints = {}
	for index, rgb in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color(rgb)))
	end
	return ColorSequence.new(keypoints)
end

local function sparkles(parent: BasePart, colors: { Rgb }, rate: number, size: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = sequence(colors)
	emitter.LightEmission = 1
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = parent
	return emitter
end

-- A glowing arc between two parts, bulging `bulge` studs up (shown in the game only). Each end's attachment points
-- its X axis up, so the curve leaves and lands vertically.
local function arc(parent: BasePart, from: BasePart, to: BasePart, colors: { Rgb }, width: number, bulge: number)
	local function anchor(part: BasePart): Attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "ArcPoint"
		attachment.CFrame = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, -Vector3.xAxis)
		attachment.Parent = part
		return attachment
	end
	local beam = Instance.new("Beam")
	beam.Name = "Arc"
	beam.Attachment0 = anchor(from)
	beam.Attachment1 = anchor(to)
	beam.Color = sequence(colors)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 24
	beam.Width0 = width
	beam.Width1 = width
	beam.CurveSize0 = bulge
	beam.CurveSize1 = -bulge
	beam.Transparency = NumberSequence.new(0.15)
	beam.Parent = parent
	return beam
end

-- Text on one face of a part, in the signs' style: big bouncy letters with a dark outline.
local function signText(part: BasePart, face: Enum.NormalId, text: string, textColor: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignText"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.52)
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Font = Enum.Font.LuckiestGuy
	label.Text = text
	label.TextColor3 = textColor or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(46, 30, 22)
	stroke.Thickness = 4
	stroke.Parent = label
	return gui
end

-- A lantern hanging from `top` (a point in `origin`'s space): chain, gold caps, and a warm glowing glass.
local function lantern(model: Model, origin: CFrame, top: Vector3)
	local at = origin * CFrame.new(top)
	trim(block(model, Vector3.new(0.15, 1.4, 0.15), at * CFrame.new(0, -0.7, 0), WOOD_DARK))
	trim(block(model, Vector3.new(1.3, 0.3, 1.3), at * CFrame.new(0, -1.55, 0), GOLD))
	local glass = trim(block(model, Vector3.new(1, 1.5, 1), at * CFrame.new(0, -2.45, 0), LAMP, { material = M.Neon }))
	trim(block(model, Vector3.new(1.3, 0.3, 1.3), at * CFrame.new(0, -3.35, 0), GOLD))
	light(glass, LAMP, 18, 1.2)
end

----------------------------------------------------------------------------------------------------------------
-- The market booth both stalls share

-- Builds the booth into `model` and returns its counter (which holds the prompt) and its signboard.
local function buildBooth(model: Model, station: HubLayout.Station, theme: Theme): (BasePart, BasePart)
	local origin = groundFrame(station.x, station.z, station.facing)
	local halfWidth = WIDTH / 2

	-- The base: a stone plinth with a plank deck, and a step up at the front.
	block(model, Vector3.new(WIDTH + 4, 1, DEPTH + 4), origin * CFrame.new(0, 0.5, 0), STONE, { material = M.Slate })
	block(
		model,
		Vector3.new(WIDTH + 2, 0.3, DEPTH + 2),
		origin * CFrame.new(0, FLOOR - 0.15, 0),
		WOOD_LIGHT,
		{ material = M.WoodPlanks }
	)
	block(
		model,
		Vector3.new(WIDTH * 0.55, 0.5, 2.4),
		origin * CFrame.new(0, 0.25, -(DEPTH / 2 + 3.2)),
		STONE_DARK,
		{ material = M.Slate }
	)

	-- Carved posts on gold feet, with gold rings near the top.
	local postHeight = AWNING_FRONT.y - FLOOR + 1
	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local x, z = corner[1] * (halfWidth - 0.4), corner[2] * (DEPTH / 2 - 0.6)
		local foot = origin * CFrame.new(x, FLOOR, z)
		block(model, Vector3.new(2, 1, 2), foot * CFrame.new(0, 0.5, 0), GOLD)
		column(model, 1.4, postHeight, foot, WOOD_DARK, { material = M.Wood })
		trim(column(model, 1.7, 0.5, foot * CFrame.new(0, postHeight - 3, 0), GOLD))
		trim(column(model, 1.7, 0.5, foot * CFrame.new(0, 3, 0), GOLD))
	end

	-- The back wall: planks, a coloured panel framed in gold, and low side walls.
	block(
		model,
		Vector3.new(WIDTH - 1, 13, 0.8),
		origin * CFrame.new(0, FLOOR + 6.5, DEPTH / 2 - 0.6),
		WOOD,
		{ material = M.WoodPlanks }
	)
	trim(block(model, Vector3.new(WIDTH - 3.4, 9.4, 0.2), origin * CFrame.new(0, FLOOR + 7.4, DEPTH / 2 - 1.1), GOLD))
	trim(
		block(model, Vector3.new(WIDTH - 4, 8.8, 0.3), origin * CFrame.new(0, FLOOR + 7.4, DEPTH / 2 - 1.2), theme.deep)
	)
	for _, side in { -1, 1 } do
		block(
			model,
			Vector3.new(0.6, 5, DEPTH - 2),
			origin * CFrame.new(side * (halfWidth - 0.4), FLOOR + 2.5, 0.4),
			WOOD,
			{ material = M.WoodPlanks }
		)
		trim(
			block(
				model,
				Vector3.new(0.9, 0.4, DEPTH - 1.6),
				origin * CFrame.new(side * (halfWidth - 0.4), FLOOR + 5.1, 0.4),
				WOOD_LIGHT
			)
		)
	end

	-- The counter: a coloured front with a lighter inset and an emblem, a wooden top with gold trim, a dark kick
	-- plate.
	local counter =
		block(model, Vector3.new(WIDTH - 4, 4.6, 3.2), origin * CFrame.new(0, FLOOR + 2.3, COUNTER_Z), theme.main)
	counter.Name = "Counter"
	trim(
		block(
			model,
			Vector3.new(WIDTH - 7, 2.8, 0.2),
			origin * CFrame.new(0, FLOOR + 2.5, COUNTER_Z - 1.65),
			theme.light
		)
	)
	block(
		model,
		Vector3.new(WIDTH - 3, 0.6, 4),
		origin * CFrame.new(0, COUNTER_TOP - 0.3, COUNTER_Z),
		WOOD_LIGHT,
		{ material = M.Wood }
	)
	trim(
		block(
			model,
			Vector3.new(WIDTH - 3.1, 0.35, 0.3),
			origin * CFrame.new(0, COUNTER_TOP - 0.75, COUNTER_Z - 1.95),
			GOLD
		)
	)
	trim(
		block(
			model,
			Vector3.new(WIDTH - 3.6, 0.6, 3.4),
			origin * CFrame.new(0, FLOOR + 0.3, COUNTER_Z - 0.1),
			WOOD_DARK
		)
	)
	local emblem = trim(plate(model, origin * CFrame.new(0, FLOOR + 2.5, COUNTER_Z - 1.9), 3.6, 0.4, GOLD))
	trim(plate(model, origin * CFrame.new(0, FLOOR + 2.5, COUNTER_Z - 2.05), 3, 0.2, WHITE))
	signText(emblem, Enum.NormalId.Right, theme.icon)

	-- The awning: stripes sloping down to the front, a ridge along the back, a valance and pennants along the front.
	local rise = AWNING_BACK.y - AWNING_FRONT.y
	local run = AWNING_BACK.z - AWNING_FRONT.z
	local slope = math.atan2(rise, run)
	local length = math.sqrt(rise * rise + run * run)
	local middle = origin
		* CFrame.new(0, (AWNING_FRONT.y + AWNING_BACK.y) / 2, (AWNING_FRONT.z + AWNING_BACK.z) / 2)
		* CFrame.Angles(-slope, 0, 0)
	local stripes = 9
	local stripeWidth = (WIDTH + 3) / stripes
	for index = 0, stripes - 1 do
		local stripe = trim(
			block(
				model,
				Vector3.new(stripeWidth, 0.6, length),
				middle * CFrame.new(-(WIDTH + 3) / 2 + stripeWidth * (index + 0.5), 0, 0),
				if index % 2 == 0 then theme.main else WHITE
			)
		)
		stripe.Name = "Awning"
		stripe.CanQuery = true
	end
	trim(
		block(
			model,
			Vector3.new(WIDTH + 3.4, 0.8, 0.8),
			origin * CFrame.new(0, AWNING_BACK.y + 0.2, AWNING_BACK.z),
			WOOD_DARK
		)
	)
	trim(
		block(
			model,
			Vector3.new(WIDTH + 3.2, 1.4, 0.3),
			origin * CFrame.new(0, AWNING_FRONT.y - 0.55, AWNING_FRONT.z),
			theme.deep
		)
	)
	trim(
		block(
			model,
			Vector3.new(WIDTH + 3.2, 0.3, 0.4),
			origin * CFrame.new(0, AWNING_FRONT.y + 0.1, AWNING_FRONT.z),
			GOLD
		)
	)
	local flags = 11
	local flagWidth = (WIDTH + 3) / flags
	for index = 0, flags - 1 do
		local x0 = -(WIDTH + 3) / 2 + flagWidth * index
		local top = AWNING_FRONT.y - 1.25
		Parts.triangle(
			model,
			(origin * CFrame.new(x0 + 0.15, top, AWNING_FRONT.z - 0.05)).Position,
			(origin * CFrame.new(x0 + flagWidth - 0.15, top, AWNING_FRONT.z - 0.05)).Position,
			(origin * CFrame.new(x0 + flagWidth / 2, top - 1.8, AWNING_FRONT.z - 0.05)).Position,
			color(if index % 2 == 0 then GOLD else theme.light)
		)
	end

	-- The signboard on top, framed in gold, on two short posts.
	local signZ = AWNING_FRONT.z + 1.6
	local signY = AWNING_FRONT.y + 4.6
	for _, side in { -1, 1 } do
		trim(
			block(
				model,
				Vector3.new(0.6, 3, 0.6),
				origin * CFrame.new(side * 5, AWNING_FRONT.y + 1.6, signZ + 0.2),
				WOOD_DARK
			)
		)
	end
	trim(block(model, Vector3.new(16.8, 5.4, 0.6), origin * CFrame.new(0, signY, signZ + 0.15), GOLD))
	local sign = trim(block(model, Vector3.new(16, 4.6, 0.6), origin * CFrame.new(0, signY, signZ - 0.05), theme.main))
	sign.Name = "Sign"
	signText(sign, Enum.NormalId.Front, theme.title)
	for _, side in { -1, 1 } do
		local badge = trim(ball(model, 2.4, (origin * CFrame.new(side * 8.4, signY, signZ - 0.2)).Position, GOLD))
		badge.Name = "SignBadge"
	end
	-- The floating name tag, readable from across the plaza.
	Parts.nameTag(sign, theme.title, color(theme.main), 10, 2.6, 5.4)

	-- Lanterns under the front corners of the awning, and gold finials above them.
	for _, side in { -1, 1 } do
		lantern(model, origin, Vector3.new(side * (halfWidth + 0.6), AWNING_FRONT.y - 1.4, AWNING_FRONT.z + 0.4))
		local finial = trim(
			ball(
				model,
				1.6,
				(origin * CFrame.new(side * (halfWidth + 1.4), AWNING_FRONT.y + 0.8, AWNING_FRONT.z + 0.4)).Position,
				GOLD
			)
		)
		finial.Name = "Finial"
	end

	-- A ring on the ground in front, where players stand to use the stall.
	local ring = trim(
		Parts.disc(model, "StandHere", origin * CFrame.new(0, 0.08, -(DEPTH / 2 + 8)), 11, 0.16, color(theme.main))
	)
	ring.Transparency = 0.3
	trim(
		Parts.disc(
			model,
			"StandHereInner",
			origin * CFrame.new(0, 0.12, -(DEPTH / 2 + 8)),
			8.6,
			0.16,
			color(theme.light)
		)
	).Transparency =
		0.45

	Parts.stationPrompt(counter, station.key, station.name, HubLayout.STATION_REACH)
	return counter, sign
end

----------------------------------------------------------------------------------------------------------------
-- Trails stall

local function buildTrailsStall(stations: Instance)
	local station = HubLayout.STATIONS.Trails
	local model = Instance.new("Model")
	model.Name = station.key
	model.Parent = stations
	buildBooth(model, station, TRAILS_THEME)
	local origin = groundFrame(station.x, station.z, station.facing)

	-- A sample of every trail hanging on the back wall, like ribbons in a draper's shop: each a streamer of its
	-- colours on a gold rail, the fancier ones glowing.
	local count = #Trails.List
	local spacing = math.min(2, (WIDTH - 6) / count)
	local wallZ = DEPTH / 2 - 1.45
	trim(block(model, Vector3.new(spacing * count + 1, 0.4, 0.4), origin * CFrame.new(0, FLOOR + 11.2, wallZ), GOLD))
	for index, trail in Trails.List do
		local x = (index - (count + 1) / 2) * spacing
		local colors = trail.colors
		local pieces = math.max(3, #colors)
		local pieceHeight = 6.6 / pieces
		for piece = 1, pieces do
			local rgb = colors[math.clamp(math.floor((piece - 1) / pieces * #colors) + 1, 1, #colors)]
			trim(
				block(
					model,
					Vector3.new(spacing * 0.7, pieceHeight, 0.2),
					origin * CFrame.new(x, FLOOR + 11 - pieceHeight * (piece - 0.5), wallZ),
					rgb,
					{ material = if trail.glow >= 0.8 then M.Neon else M.SmoothPlastic }
				)
			).Name =
				"Sample"
		end
		-- A pennant tip at the bottom of each streamer.
		Parts.triangle(
			model,
			(origin * CFrame.new(x - spacing * 0.35, FLOOR + 4.4, wallZ - 0.05)).Position,
			(origin * CFrame.new(x + spacing * 0.35, FLOOR + 4.4, wallZ - 0.05)).Position,
			(origin * CFrame.new(x, FLOOR + 3.5, wallZ - 0.05)).Position,
			color(colors[#colors])
		)
	end

	-- Glass display cases on the counter, each with a glowing orb of one of the finest trails.
	local showcase = { Trails.List[count - 2], Trails.List[count - 1], Trails.List[count] }
	for index, trail in showcase do
		local x = (index - 2) * 6.5
		local base = origin * CFrame.new(x, COUNTER_TOP, COUNTER_Z)
		trim(column(model, 2.6, 0.5, base, GOLD))
		trim(
			block(
				model,
				Vector3.new(2.2, 2.8, 2.2),
				base * CFrame.new(0, 1.9, 0),
				{ 210, 236, 255 },
				{ material = M.Glass, transparency = 0.6 }
			)
		)
		trim(block(model, Vector3.new(2.5, 0.3, 2.5), base * CFrame.new(0, 3.45, 0), GOLD))
		local orb =
			trim(ball(model, 1.3, (base * CFrame.new(0, 1.8, 0)).Position, trail.colors[1], { material = M.Neon }))
		orb.Name = "Orb"
		sparkles(orb, trail.colors, 6, 0.35)
		light(orb, trail.colors[1], 8, 0.8)
	end

	-- Glowing ribbons arching over the sign between the finials, in the colours of the three finest trails.
	local finials = {}
	for _, child in model:GetChildren() do
		if child.Name == "Finial" then
			table.insert(finials, child)
		end
	end
	if #finials == 2 then
		for index, trail in showcase do
			arc(
				finials[1] :: BasePart,
				finials[1] :: BasePart,
				finials[2] :: BasePart,
				trail.colors,
				0.5,
				6 + index * 2
			)
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Sell stall

-- An egg standing on end, `height` tall.
local function egg(model: Model, at: CFrame, height: number, rgb: Rgb): BasePart
	local part = trim(block(model, Vector3.new(height * 0.76, height, height * 0.76), at, rgb))
	part.Name = "Egg"
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- A wooden crate with eggs nestled in straw.
local function eggCrate(model: Model, at: CFrame, eggColors: { Rgb })
	trim(block(model, Vector3.new(4, 1.8, 3), at * CFrame.new(0, 0.9, 0), WOOD, { material = M.WoodPlanks }))
	for _, side in { -1, 1 } do
		trim(block(model, Vector3.new(4.2, 0.4, 0.3), at * CFrame.new(0, 1.2, side * 1.5), WOOD_DARK))
	end
	trim(
		block(
			model,
			Vector3.new(3.6, 0.3, 2.6),
			at * CFrame.new(0, 1.75, 0),
			{ 226, 190, 104 },
			{ material = M.Fabric }
		)
	)
	for index, rgb in eggColors do
		local x = (index - (#eggColors + 1) / 2) * 1.2
		egg(model, at * CFrame.new(x, 2.4, (index % 2) * 0.6 - 0.3), 1.5, rgb)
	end
end

local function buildSellStall(stations: Instance)
	local station = HubLayout.STATIONS.Sell
	local model = Instance.new("Model")
	model.Name = station.key
	model.Parent = stations
	buildBooth(model, station, SELL_THEME)
	local origin = groundFrame(station.x, station.z, station.facing)

	-- A big gold coin on the back wall, with shelves of eggs either side.
	local wallZ = DEPTH / 2 - 1.4
	local coin = trim(plate(model, origin * CFrame.new(0, FLOOR + 7.6, wallZ - 0.1), 6.4, 0.6, GOLD))
	coin.Name = "Coin"
	trim(plate(model, origin * CFrame.new(0, FLOOR + 7.6, wallZ - 0.35), 5.2, 0.2, GOLD_DEEP))
	signText(coin, Enum.NormalId.Right, "$", Color3.fromRGB(255, 236, 140))
	for _, side in { -1, 1 } do
		for shelf = 0, 1 do
			local y = FLOOR + 5.6 + shelf * 3.6
			trim(block(model, Vector3.new(6, 0.4, 1.6), origin * CFrame.new(side * 7, y, wallZ - 0.8), WOOD_LIGHT))
			for slot = 0, 2 do
				local shell = if (slot + shelf) % 3 == 0 then { 140, 210, 255 } else EGGSHELL
				egg(model, origin * CFrame.new(side * 7 + (slot - 1) * 1.8, y + 1, wallZ - 0.8), 1.6, shell)
			end
		end
	end

	-- On the counter: stacks of coins, a money bag, and a balance with an egg weighed against coins.
	local top = origin * CFrame.new(0, COUNTER_TOP, COUNTER_Z)
	for index, height in { 5, 8, 3 } do
		for coinIndex = 0, height - 1 do
			trim(
				column(
					model,
					1.4,
					0.25,
					top
						* CFrame.new(-8 + index * 1.6, coinIndex * 0.26, (index % 2) * 0.5)
						* CFrame.Angles(0, coinIndex * 0.4, 0),
					if coinIndex % 2 == 0 then GOLD else GOLD_DEEP
				)
			)
		end
	end
	local bag =
		trim(ball(model, 2.6, (top * CFrame.new(7.4, 1.2, 0.2)).Position, { 214, 184, 130 }, { material = M.Fabric }))
	bag.Name = "MoneyBag"
	trim(column(model, 1, 0.8, top * CFrame.new(7.4, 2.3, 0.2), { 176, 140, 90 }, { material = M.Fabric }))
	trim(column(model, 1.3, 0.3, top * CFrame.new(7.4, 3.1, 0.2), { 214, 184, 130 }, { material = M.Fabric }))
	-- The balance.
	trim(column(model, 1.6, 0.3, top * CFrame.new(1.6, 0, 0), GOLD_DEEP))
	trim(column(model, 0.3, 3.4, top * CFrame.new(1.6, 0.3, 0), GOLD))
	trim(block(model, Vector3.new(4.6, 0.25, 0.25), top * CFrame.new(1.6, 3.6, 0) * CFrame.Angles(0, 0, 0.12), GOLD))
	for _, side in { -1, 1 } do
		local hang = top * CFrame.new(1.6 + side * 2.2, 3.6 - side * 0.27, 0)
		trim(block(model, Vector3.new(0.08, 1.4, 0.08), hang * CFrame.new(0, -0.7, 0), GOLD))
		trim(column(model, 1.8, 0.2, hang * CFrame.new(0, -1.5, 0), GOLD))
	end
	egg(model, top * CFrame.new(-0.6, 3.55, 0), 1.3, EGGSHELL)
	for coinIndex = 0, 2 do
		trim(column(model, 1, 0.22, top * CFrame.new(3.8, 2.42 + coinIndex * 0.23, 0), GOLD))
	end

	-- Crates of eggs on the deck either side of the counter.
	for _, side in { -1, 1 } do
		local at = origin
			* CFrame.new(side * (WIDTH / 2 - 0.2), FLOOR, -DEPTH / 2 - 1.4)
			* CFrame.Angles(0, side * 0.25, 0)
		eggCrate(model, at, { EGGSHELL, { 255, 214, 120 }, EGGSHELL })
	end
end

----------------------------------------------------------------------------------------------------------------
-- Fuse machine

-- A gear standing on its edge, its face pointing along `at`'s X axis.
local function gear(model: Model, at: CFrame, diameter: number, rgb: Rgb)
	trim(Build.part(model, "Gear", Vector3.new(0.8, diameter, diameter), at, rgb, { shape = Enum.PartType.Cylinder }))
	trim(
		Build.part(
			model,
			"GearHub",
			Vector3.new(1.2, diameter * 0.3, diameter * 0.3),
			at,
			GOLD,
			{ shape = Enum.PartType.Cylinder }
		)
	)
	local teeth = 12
	for index = 0, teeth - 1 do
		local angle = index / teeth * math.pi * 2
		trim(
			block(
				model,
				Vector3.new(0.7, 1, 1.1),
				at * CFrame.Angles(angle, 0, 0) * CFrame.new(0, diameter / 2 + 0.3, 0),
				rgb
			)
		)
	end
end

-- The fuse machine. Its front faces the runway; the prompt is on the console at the front of the chamber.
local function buildFuseMachine(stations: Instance)
	local station = HubLayout.STATIONS.Fuse
	local model = Instance.new("Model")
	model.Name = station.key
	model.Parent = stations
	local origin = groundFrame(station.x, station.z, station.facing)

	local VIOLET = { 92, 74, 138 }
	local VIOLET_LIGHT = { 132, 108, 186 }
	local RUNE = { 175, 115, 255 }

	-- Three round steps, each trimmed with gold.
	local steps = { { 28, VIOLET }, { 23, { 110, 90, 158 } }, { 18, VIOLET_LIGHT } }
	for index, step in steps do
		local y = index - 1
		Parts.disc(model, "Step", origin * CFrame.new(0, y + 0.5, 0), step[1], 1, color(step[2])).Material = M.Slate
		trim(Parts.disc(model, "StepTrim", origin * CFrame.new(0, y + 1.02, 0), step[1] + 0.4, 0.12, color(GOLD)))
	end
	local floor = 3

	-- The chamber: a glass tube between gold rings, ribbed with gold, under a violet dome and a glowing crown.
	local base = origin * CFrame.new(0, floor, 0)
	local pedestal = column(model, 10, 1.2, base, GOLD)
	pedestal.Name = "Pedestal"
	column(model, 8.6, 10, base * CFrame.new(0, 1.2, 0), { 200, 230, 255 }, { material = M.Glass, transparency = 0.62 }).Name =
		"Glass"
	for index = 0, 5 do
		local angle = index / 6 * math.pi * 2 + math.pi / 6
		trim(
			block(
				model,
				Vector3.new(0.45, 10, 0.45),
				base * CFrame.new(math.cos(angle) * 4.4, 6.2, math.sin(angle) * 4.4),
				GOLD
			)
		)
	end
	trim(column(model, 10, 1, base * CFrame.new(0, 11.2, 0), GOLD))
	trim(ball(model, 9.6, (base * CFrame.new(0, 12.2, 0)).Position, { 120, 70, 200 }))
	trim(column(model, 10.4, 0.5, base * CFrame.new(0, 12, 0), GOLD_DEEP))
	trim(column(model, 1.2, 3.4, base * CFrame.new(0, 16.4, 0), GOLD))
	local crown =
		trim(ball(model, 2.4, (base * CFrame.new(0, 20.6, 0)).Position, { 255, 226, 140 }, { material = M.Neon }))
	crown.Name = "Crown"
	light(crown, { 255, 220, 140 }, 22, 1.4)

	-- The golden mystery egg floating inside.
	local mystery = block(model, Vector3.new(4.6, 6, 4.6), base * CFrame.new(0, 6.6, 0), { 255, 212, 70 })
	mystery.Name = "Egg"
	mystery.Reflectance = 0.15
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = mystery
	light(mystery, { 255, 220, 120 }, 18, 1.6)
	sparkles(mystery, { { 255, 236, 150 }, { 255, 255, 255 } }, 8, 0.5)
	local question = Instance.new("BillboardGui")
	question.Name = "Mystery"
	question.Size = UDim2.fromScale(3.6, 3.6)
	question.LightInfluence = 0
	question.MaxDistance = 200
	question.Parent = mystery
	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.Font = Enum.Font.LuckiestGuy
	mark.Text = "?"
	mark.TextColor3 = Color3.fromRGB(150, 86, 10)
	mark.TextScaled = true
	mark.Parent = question

	-- Gears turning (in spirit) at each side of the chamber.
	for _, side in { -1, 1 } do
		gear(model, base * CFrame.new(side * 5.6, 5.6, 0.4), 5.6, GOLD_DEEP)
		gear(model, base * CFrame.new(side * 5.4, 9.2, -1.6), 3.4, GOLD)
	end

	-- Four lamp pillars round the machine, their lamps linked to the crown by glowing arcs.
	for index = 0, 3 do
		local angle = math.pi / 4 + index * math.pi / 2
		local at = origin * CFrame.new(math.cos(angle) * 11.6, 1, math.sin(angle) * 11.6)
		block(model, Vector3.new(2.6, 1, 2.6), at * CFrame.new(0, 0.5, 0), GOLD)
		column(model, 1.6, 12, at * CFrame.new(0, 1, 0), VIOLET_LIGHT, { material = M.Slate })
		trim(block(model, Vector3.new(2.4, 0.8, 2.4), at * CFrame.new(0, 13.4, 0), GOLD))
		local orb =
			trim(ball(model, 2, (at * CFrame.new(0, 14.8, 0)).Position, { 255, 235, 140 }, { material = M.Neon }))
		orb.Name = "Lamp"
		light(orb, { 255, 220, 130 }, 14, 0.9)
		arc(orb, orb, crown, { { 255, 236, 150 }, { 190, 120, 255 } }, 0.35, 5)
	end

	-- The console at the front, which opens the machine's panel.
	local console = block(
		model,
		Vector3.new(4.4, 3.4, 1.6),
		origin * CFrame.new(0, floor + 1.7, -7) * CFrame.Angles(0.25, 0, 0),
		VIOLET
	)
	console.Name = "Console"
	trim(
		block(
			model,
			Vector3.new(4.8, 0.3, 2),
			origin * CFrame.new(0, floor + 3.55, -7.1) * CFrame.Angles(0.25, 0, 0),
			GOLD
		)
	)
	local screen = trim(
		block(
			model,
			Vector3.new(3.4, 2.2, 0.2),
			origin * CFrame.new(0, floor + 1.9, -7.85) * CFrame.Angles(0.25, 0, 0),
			RUNE,
			{ material = M.Neon }
		)
	)
	signText(screen, Enum.NormalId.Front, "FUSE")

	-- Three pads in front, for the three pets that go in, each sending a glowing stream into the chamber.
	for index = -1, 1 do
		local at = origin * CFrame.new(index * 6, 0, -16)
		trim(Parts.disc(model, "PadRim", at * CFrame.new(0, 0.2, 0), 5, 0.4, color(GOLD)))
		local pad = trim(Parts.disc(model, "PetPad", at * CFrame.new(0, 0.3, 0), 4, 0.4, color(RUNE)))
		pad.Material = M.Neon
		arc(pad, pad, mystery, { { 200, 150, 255 }, { 255, 230, 150 } }, 0.3, 6)
	end

	Parts.nameTag(mystery, "FUSE", FUSE_COLOR, 7, 2.4, 13)
	Parts.stationPrompt(console, station.key, station.name, HubLayout.STATION_REACH)
end

-- Builds the stations under `map`.
function Stations.build(map: Instance): Folder
	local stations = Instance.new("Folder")
	stations.Name = "Stations"
	buildTrailsStall(stations)
	buildSellStall(stations)
	buildFuseMachine(stations)
	stations.Parent = map
	return stations
end

return Stations
