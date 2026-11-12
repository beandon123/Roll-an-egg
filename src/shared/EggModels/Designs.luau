--!strict
-- The look of every egg, by name. Which eggs drop in which zone, and at what rarity, is set in Config/Zones.
-- Each design draws on the voxel egg builder in EggModels:
--     y (layer) 1..16 from the round bottom to the pointed top; x and z -6..5 across the widest layer.
--     The front of the egg faces +z (90 degrees round the egg): faces, chests and claws go there.
--
-- The rarer the egg, the more it shows what will hatch:
--     Common             plain: the zone's colour and one simple mark
--     Uncommon, Rare     a zone pattern with a hint of the pets inside
--     Epic and above     the egg looks like its pet (ears, horns, tusks, fins, markings)
-- Legendary and rarer eggs also glow, and Mythic and rarer give off particles (see EggModels).

type Color = { number }
type Egg = any
type Design = {
	name: string,
	-- Which pet hatches from it.
	hatches: string,
	-- Seeds the random-looking patterns (speckles, fur, moss), so each egg always looks the same.
	seed: number,
	-- "Classic" (default), "Round" or "Pointy": see EggModels.Profiles.
	profile: string?,
	-- Set on eggs taken out of the game for now: the rarity they last dropped as. Shelved eggs are in no zone's
	-- lineup (see Config/Zones), but stay here so they can come back.
	shelved: string?,
	draw: (Egg) -> (),
}

local function rgb(r: number, g: number, b: number): Color
	return { r, g, b }
end

local NEON = "Neon"
local GLASS = "Glass"

----------------------------------------------------------------------------------------------------------------
-- Drawing helpers

-- Round spots: { layer, angle in degrees, size in voxels }.
local function spots(egg: Egg, color: Color, list: { { number } }, material: string?)
	for _, spot in list do
		egg:spot(spot[1], spot[2], spot[3], color, material)
	end
end

-- A triangle wave from 0 to 1 and back, `teeth` times around the egg.
local function wave(angle: number, teeth: number): number
	local phase = (angle / 360 * teeth) % 1
	return 1 - math.abs(phase * 2 - 1)
end

-- A zigzag line around the egg, starting at layer `base` and reaching `amplitude` layers higher.
local function zigzag(
	egg: Egg,
	base: number,
	amplitude: number,
	teeth: number,
	thickness: number,
	color: Color,
	material: string?
)
	egg:paint(function(cell)
		local low = base + math.round(wave(cell.angle, teeth) * amplitude)
		if cell.y >= low and cell.y < low + thickness then
			return color, material
		end
		return nil
	end)
end

-- Fills everything above (or below) a zigzag edge, for caps and two-tone eggs with jagged edges.
local function zigzagFill(egg: Egg, base: number, amplitude: number, teeth: number, above: boolean, color: Color)
	egg:paint(function(cell)
		local edge = base + math.round(wave(cell.angle, teeth) * amplitude)
		if (above and cell.y >= edge) or (not above and cell.y <= edge) then
			return color
		end
		return nil
	end)
end

-- Up-and-down stripes. `width` is in degrees; `twist` turns them into spirals (degrees per layer).
local function stripes(
	egg: Egg,
	count: number,
	width: number,
	color: Color,
	first: number,
	last: number,
	twist: number?,
	offset: number?,
	material: string?
)
	local period = 360 / count
	egg:paint(function(cell)
		if cell.y < first or cell.y > last then
			return nil
		end
		local angle = (cell.angle + (twist or 0) * cell.y - (offset or 0)) % period
		if angle < width then
			return color, material
		end
		return nil
	end)
end

-- Paints scattered single cells: `chance` of each visible cell between two layers.
local function speckle(egg: Egg, color: Color, chance: number, salt: number, first: number, last: number)
	egg:paint(function(cell)
		if cell.y >= first and cell.y <= last and egg:noise(cell.x, cell.y, cell.z, salt) < chance then
			return color
		end
		return nil
	end)
end

-- Paints patches made of 2x2x2 blocks, for moss, fur and other clumpy textures.
local function blotches(egg: Egg, color: Color, chance: number, salt: number, first: number, last: number)
	egg:paint(function(cell)
		if cell.y < first or cell.y > last then
			return nil
		end
		if egg:noise(cell.x // 2, cell.y // 2, cell.z // 2, salt) < chance then
			return color
		end
		return nil
	end)
end

-- Hanging streaks of colour, like shaggy fur or drips: each starts at a random layer and runs down.
local function streaks(egg: Egg, color: Color, count: number, salt: number, first: number, last: number, length: number)
	local slots = 24
	egg:paint(function(cell)
		if cell.facing ~= "side" then
			return nil
		end
		local slot = math.floor(cell.angle / 360 * slots)
		if egg:noise(slot, 0, 0, salt) > count / slots then
			return nil
		end
		local top = first + math.floor(egg:noise(slot, 1, 0, salt) * (last - first + 1))
		local len = 1 + math.floor(egg:noise(slot, 2, 0, salt) * length)
		if cell.y <= top and cell.y > top - len then
			return color
		end
		return nil
	end)
end

-- A crack: a line across the shell through { layer, angle } points.
local function crack(egg: Egg, points: { { number } }, color: Color, material: string?, width: number?)
	local circumference = 2 * math.pi * 6
	local reach = width or 0.6
	egg:paint(function(cell)
		if cell.facing ~= "side" then
			return nil
		end
		local px, py = cell.angle / 360 * circumference, cell.y - 0.5
		for index = 1, #points - 1 do
			local ay, aa = points[index][1] - 0.5, points[index][2]
			local by, ba = points[index + 1][1] - 0.5, points[index + 1][2]
			local ax, bx = aa / 360 * circumference, ba / 360 * circumference
			-- Try the point and its copies one turn either way, so lines can cross 0 degrees.
			for _, shift in { 0, circumference, -circumference } do
				local qx = px + shift
				local dx, dy = bx - ax, by - ay
				local lengthSq = dx * dx + dy * dy
				local t = if lengthSq > 0 then math.clamp(((qx - ax) * dx + (py - ay) * dy) / lengthSq, 0, 1) else 0
				local cx, cy = ax + dx * t - qx, ay + dy * t - py
				if cx * cx + cy * cy <= reach * reach then
					return color, material
				end
			end
		end
		return nil
	end)
end

-- Sets a list of cells { x, y, z } (decorations built a voxel at a time).
local function cells(egg: Egg, list: { { number } }, color: Color, material: string?, transparency: number?)
	for _, cell in list do
		egg:set(cell[1], cell[2], cell[3], color, material, transparency)
	end
end

-- Sets a list of cells { x, y, z }, plus a mirror copy of each on the other side (across x).
local function pairCells(egg: Egg, list: { { number } }, color: Color, material: string?, transparency: number?)
	for _, cell in list do
		egg:set(cell[1], cell[2], cell[3], color, material, transparency)
		egg:set(-1 - cell[1], cell[2], cell[3], color, material, transparency)
	end
end

-- A shape drawn as rows of text, standing in the x/y plane: one character per voxel, '.' for empty, letters
-- looked up in `key`. The first row is the highest. `left` and `top` place the shape; `depth` is a list of z.
local function sprite(
	egg: Egg,
	rows: { string },
	left: number,
	top: number,
	depth: { number },
	key: { [string]: { any } },
	mirror: boolean?
)
	for rowIndex, row in rows do
		local y = top - rowIndex + 1
		for column = 1, #row do
			local char = string.sub(row, column, column)
			local look = key[char]
			if look then
				local x = left + column - 1
				for _, z in depth do
					egg:set(x, y, z, look[1], look[2], look[3])
					if mirror then
						egg:set(-1 - x, y, z, look[1], look[2], look[3])
					end
				end
			end
		end
	end
end

-- The same as sprite, but standing in the z/y plane (seen from the side).
local function spriteZ(
	egg: Egg,
	rows: { string },
	front: number,
	top: number,
	xs: { number },
	key: { [string]: { any } }
)
	for rowIndex, row in rows do
		local y = top - rowIndex + 1
		for column = 1, #row do
			local look = key[string.sub(row, column, column)]
			if look then
				for _, x in xs do
					egg:set(x, y, front + column - 1, look[1], look[2], look[3])
				end
			end
		end
	end
end

-- The same again, drawn from above (the x/z plane): the first row is the front (largest z).
local function spriteTop(
	egg: Egg,
	rows: { string },
	left: number,
	front: number,
	ys: { number },
	key: { [string]: { any } },
	mirror: boolean?
)
	for rowIndex, row in rows do
		local z = front - rowIndex + 1
		for column = 1, #row do
			local look = key[string.sub(row, column, column)]
			if look then
				local x = left + column - 1
				for _, y in ys do
					egg:set(x, y, z, look[1], look[2], look[3])
					if mirror then
						egg:set(-1 - x, y, z, look[1], look[2], look[3])
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Palettes

local FOREST = {
	leaf = rgb(132, 202, 92),
	leafDark = rgb(84, 150, 62),
	moss = rgb(86, 146, 66),
	mossLight = rgb(140, 196, 96),
	deep = rgb(52, 104, 50),
	bark = rgb(122, 84, 52),
	barkDark = rgb(86, 58, 36),
	acorn = rgb(200, 142, 82),
	acornCap = rgb(112, 74, 44),
	acornCapLight = rgb(146, 100, 60),
	cream = rgb(244, 234, 206),
	red = rgb(214, 54, 50),
	brown = rgb(142, 94, 58),
	tan = rgb(218, 174, 124),
	honey = rgb(255, 188, 48),
	honeyDark = rgb(232, 150, 30),
	antler = rgb(168, 126, 82),
	pink = rgb(255, 150, 196),
	yellow = rgb(255, 220, 80),
	cotton = rgb(248, 242, 228),
	fawn = rgb(204, 166, 124),
	fox = rgb(232, 118, 46),
	sap = rgb(196, 255, 110),
}

local DESERT = {
	sand = rgb(238, 212, 152),
	sandDark = rgb(216, 180, 114),
	clay = rgb(188, 98, 60),
	terracotta = rgb(214, 128, 80),
	peach = rgb(232, 166, 104),
	camel = rgb(212, 162, 102),
	red = rgb(196, 48, 52),
	gold = rgb(255, 196, 56),
	goldDark = rgb(214, 148, 30),
	teal = rgb(56, 180, 176),
	lapis = rgb(40, 86, 196),
	black = rgb(38, 34, 42),
	amber = rgb(176, 98, 44),
	amberDark = rgb(112, 58, 28),
	venom = rgb(150, 255, 90),
	stone = rgb(226, 192, 124),
	stoneDark = rgb(184, 148, 88),
	cream = rgb(246, 230, 198),
	ginger = rgb(228, 160, 94),
	pink = rgb(246, 160, 170),
	scarab = rgb(240, 186, 50),
	bronze = rgb(196, 128, 38),
	bronzeDark = rgb(120, 76, 24),
	seam = rgb(86, 56, 20),
}

local SNOW = {
	snow = rgb(246, 250, 255),
	frost = rgb(204, 228, 250),
	ice = rgb(150, 206, 244),
	iceDeep = rgb(86, 150, 222),
	navy = rgb(40, 62, 116),
	knitCream = rgb(246, 238, 222),
	knitRed = rgb(212, 52, 62),
	knitGreen = rgb(58, 140, 84),
	brown = rgb(126, 84, 52),
	brownDark = rgb(90, 58, 36),
	ivory = rgb(250, 240, 214),
	pale = rgb(238, 234, 226),
	slate = rgb(74, 84, 104),
	crystal = rgb(196, 240, 255),
	glow = rgb(130, 236, 255),
	night = rgb(30, 40, 92),
	nightWing = rgb(52, 66, 132),
	feather = rgb(86, 116, 196),
	auroraGreen = rgb(90, 255, 170),
	auroraTeal = rgb(80, 220, 255),
	auroraViolet = rgb(182, 124, 255),
	chest = rgb(226, 234, 252),
	chestMark = rgb(160, 182, 228),
	wolf = rgb(164, 184, 212),
	wolfDark = rgb(92, 110, 152),
}

local OCEAN = {
	aqua = rgb(86, 198, 218),
	foam = rgb(226, 250, 246),
	turtle = rgb(98, 168, 84),
	turtleDark = rgb(62, 118, 58),
	shellCream = rgb(232, 218, 156),
	dolphin = rgb(112, 152, 194),
	belly = rgb(232, 242, 250),
	navy = rgb(34, 50, 96),
	spot = rgb(144, 204, 244),
	slate = rgb(122, 142, 172),
	slateDark = rgb(82, 100, 136),
	ivory = rgb(250, 242, 220),
	ivoryDark = rgb(222, 206, 168),
	purple = rgb(104, 42, 134),
	magenta = rgb(202, 72, 164),
	sucker = rgb(255, 186, 224),
	abyss = rgb(18, 42, 58),
	abyssScale = rgb(28, 74, 92),
	biolume = rgb(80, 255, 228),
	finGlass = rgb(90, 220, 210),
	crab = rgb(216, 64, 48),
	crabBelly = rgb(250, 178, 128),
	crabDark = rgb(156, 38, 30),
	crabEye = rgb(32, 26, 30),
	seahorse = rgb(36, 172, 168),
	seahorseDark = rgb(22, 122, 126),
	seahorseBelly = rgb(188, 242, 230),
	shark = rgb(120, 134, 150),
	sharkDark = rgb(84, 96, 112),
	sharkBelly = rgb(240, 244, 248),
	sharkMouth = rgb(90, 30, 40),
}

local VOLCANO = {
	ash = rgb(96, 90, 94),
	ember = rgb(232, 112, 42),
	toad = rgb(210, 86, 42),
	wart = rgb(252, 166, 54),
	toadBelly = rgb(244, 196, 96),
	obsidian = rgb(42, 34, 54),
	shard = rgb(104, 70, 160),
	horn = rgb(156, 146, 146),
	boar = rgb(62, 42, 38),
	snout = rgb(150, 92, 84),
	tusk = rgb(236, 226, 206),
	lava = rgb(255, 112, 24),
	lavaHot = rgb(255, 196, 40),
	charcoal = rgb(50, 44, 50),
	collar = rgb(186, 32, 42),
	silver = rgb(206, 206, 216),
	snake = rgb(74, 150, 72),
	snakeDark = rgb(46, 104, 50),
	lion = rgb(226, 162, 72),
	mane = rgb(184, 92, 38),
	goat = rgb(112, 98, 88),
	dragon = rgb(34, 26, 32),
	dragonScale = rgb(58, 44, 50),
	dragonHorn = rgb(78, 66, 70),
	crimson = rgb(198, 30, 34),
	flame = rgb(242, 82, 28),
	orange = rgb(255, 142, 32),
	gold = rgb(255, 202, 52),
	paleGold = rgb(255, 236, 140),
	eternal = rgb(150, 255, 245),
	tortoise = rgb(84, 66, 58),
	skin = rgb(130, 112, 74),
	cone = rgb(124, 112, 108),
	rock = rgb(74, 64, 62),
	rockLight = rgb(110, 98, 94),
	salamander = rgb(34, 28, 32),
}

----------------------------------------------------------------------------------------------------------------
-- Designs

local Designs: { [string]: Design } = {}

----------------------------------------------------------------------------------------------------------------
-- Forest

Designs.Leafy = {
	name = "Leafy Egg",
	hatches = "Squirrel",
	seed = 11,
	draw = function(egg)
		egg:base(FOREST.leaf)
		spots(egg, FOREST.leafDark, { { 4, 30, 3 }, { 8, 150, 3.4 }, { 11, 260, 3 }, { 6, 330, 2.6 } })
	end,
}

Designs.Acorn = {
	name = "Acorn Egg",
	hatches = "Hedgehog",
	seed = 12,
	draw = function(egg)
		egg:base(FOREST.acorn)
		egg:band(11, 16, FOREST.acornCap)
		-- The cap's scaly rim.
		zigzag(egg, 10, 1, 9, 1, FOREST.acornCap)
		zigzag(egg, 13, 1, 9, 1, FOREST.acornCapLight)
		-- Stalk.
		egg:fill(-1, 17, -1, 0, 17, 0, FOREST.barkDark)
		egg:fill(-1, 18, -1, -1, 18, 0, FOREST.barkDark)
	end,
}

Designs.Toadstool = {
	name = "Toadstool Egg",
	hatches = "Owl",
	seed = 13,
	profile = "Round",
	draw = function(egg)
		egg:base(FOREST.cream)
		egg:band(9, 16, FOREST.red)
		egg:band(8, 8, FOREST.tan)
		spots(egg, FOREST.cream, {
			{ 11, 20, 3 },
			{ 13, 140, 2.6 },
			{ 10, 200, 3.2 },
			{ 12, 290, 2.6 },
			{ 15, 80, 2.2 },
			{ 15, 250, 2 },
		})
		-- A little sprout on top.
		egg:fill(0, 17, 0, 0, 18, 0, FOREST.leafDark)
		egg:fill(-2, 19, 0, -1, 19, 0, FOREST.leaf)
		egg:fill(1, 18, 0, 2, 18, 0, FOREST.leaf)
	end,
}

Designs.Bear = {
	name = "Bear Egg",
	hatches = "Bear",
	seed = 14,
	profile = "Round",
	draw = function(egg)
		egg:base(FOREST.brown)
		-- Tummy patch on the front.
		egg:spot(6, 90, 8, FOREST.tan)
		-- Honey dripping over the top.
		egg:band(15, 16, FOREST.honey)
		streaks(egg, FOREST.honey, 11, 7, 14, 14, 3)
		-- Big round ears with light insides.
		sprite(egg, {
			".BB.",
			"BBBB",
			"BBBB",
			".BB.",
		}, -6, 18, { -1, 0 }, { B = { FOREST.brown } }, true)
		sprite(egg, {
			"TT",
			"TT",
		}, -5, 17, { 1 }, { T = { FOREST.tan } }, true)
	end,
}

Designs.MossStag = {
	name = "Moss Stag Egg",
	hatches = "Moss Stag",
	seed = 15,
	draw = function(egg)
		egg:base(FOREST.moss)
		egg:band(1, 3, FOREST.bark)
		zigzag(egg, 4, 1, 7, 1, FOREST.bark)
		blotches(egg, FOREST.mossLight, 0.35, 3, 5, 16)
		blotches(egg, FOREST.deep, 0.18, 9, 4, 14)
		-- Branching antlers.
		local W = { FOREST.antler }
		local M = { FOREST.mossLight }
		local P = { FOREST.pink, NEON }
		local Y = { FOREST.yellow, NEON }
		sprite(egg, {
			"P.....",
			"W..Y..",
			"W..W..",
			".W.W..",
			"..WW.M",
			"...WWW",
			"....W.",
			"....W.",
		}, -6, 24, { -1, 0 }, { W = W, M = M, P = P, Y = Y }, true)
	end,
}

Designs.Cottontail = {
	name = "Cottontail Egg",
	hatches = "Bunny",
	seed = 16,
	draw = function(egg)
		egg:base(FOREST.cotton)
		zigzagFill(egg, 3, 1, 7, false, FOREST.fawn)
	end,
}

Designs.Foxtail = {
	name = "Foxtail Egg",
	hatches = "Fox",
	seed = 17,
	draw = function(egg)
		egg:base(FOREST.fox)
		-- White chest, dark paws.
		zigzagFill(egg, 5, 2, 5, false, FOREST.cotton)
		egg:paint(function(cell)
			if cell.y == 1 then
				return FOREST.barkDark
			end
			return nil
		end)
		-- Little ears with dark tips.
		pairCells(egg, { { -2, 17, 0 } }, FOREST.fox)
		pairCells(egg, { { -2, 18, 0 } }, FOREST.barkDark)
	end,
}

Designs.Treant = {
	name = "Treant Egg",
	hatches = "Treant",
	seed = 18,
	profile = "Round",
	draw = function(egg)
		egg:base(FOREST.bark)
		-- Bark grooves running up the trunk.
		stripes(egg, 9, 9, FOREST.barkDark, 2, 12)
		-- Glowing knots of sap.
		spots(egg, FOREST.sap, { { 6, 80, 1.6 }, { 9, 200, 1.4 }, { 4, 300, 1.4 } }, NEON)
		-- Roots spreading out at the bottom.
		for _, angle in { 20, 110, 200, 290 } do
			local x, z = egg:outward(2, angle, 0)
			egg:set(x, 2, z, FOREST.barkDark)
			egg:set(x, 3, z, FOREST.bark)
			local fx, fz = egg:outward(1, angle, 1)
			egg:set(fx, 1, fz, FOREST.barkDark)
		end
		-- A leafy crown, with blossoms.
		egg:band(13, 16, FOREST.moss)
		zigzagFill(egg, 11, 1, 6, true, FOREST.moss)
		local crown = { [17] = 4, [18] = 5, [19] = 4, [20] = 2 }
		for y, half in crown do
			for x = -half, half - 1 do
				for z = -half, half - 1 do
					local edgeX = x == -half or x == half - 1
					local edgeZ = z == -half or z == half - 1
					if not (edgeX and edgeZ) then
						local outside = edgeX or edgeZ or y == 20
						local dark = outside and egg:noise(x // 2, y, z // 2, 3) < 0.3
						egg:set(x, y, z, if dark then FOREST.moss else FOREST.leaf)
					end
				end
			end
		end
		cells(egg, { { -5, 18, 1 }, { 4, 18, -2 }, { 1, 19, 3 }, { -3, 19, -4 }, { 0, 20, -2 } }, FOREST.pink)
		egg:light(FOREST.sap, 1.6, 12)
		egg:particles("Sparkles", FOREST.sap, 6)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Desert

Designs.Sandy = {
	name = "Sandy Egg",
	hatches = "Meerkat",
	seed = 21,
	draw = function(egg)
		egg:base(DESERT.sand)
		zigzag(egg, 6, 1, 6, 2, DESERT.sandDark)
	end,
}

Designs.Sandstone = {
	name = "Sandstone Egg",
	hatches = "Armadillo",
	seed = 22,
	draw = function(egg)
		egg:base(DESERT.sand)
		egg:band(1, 2, DESERT.clay)
		egg:band(5, 5, DESERT.terracotta)
		egg:band(8, 9, DESERT.peach)
		egg:band(12, 12, DESERT.terracotta)
		egg:band(15, 16, DESERT.clay)
		spots(egg, DESERT.sandDark, { { 3.5, 60, 1.6 }, { 10.5, 200, 1.6 }, { 6.5, 300, 1.4 } })
	end,
}

Designs.Caravan = {
	name = "Caravan Egg",
	hatches = "Camel",
	seed = 23,
	profile = "Round",
	draw = function(egg)
		egg:base(DESERT.camel)
		-- Saddle blanket with a gold zigzag and tassels.
		egg:band(7, 11, DESERT.red)
		egg:band(7, 7, DESERT.teal)
		egg:band(11, 11, DESERT.teal)
		zigzag(egg, 8, 2, 10, 1, DESERT.gold)
		egg:paint(function(cell)
			if cell.y == 6 and cell.facing == "side" and math.floor(cell.angle / 22.5) % 2 == 0 then
				return DESERT.gold
			end
			return nil
		end)
		-- Tuft on top.
		egg:fill(-1, 17, -1, 0, 17, 0, DESERT.amber)
	end,
}

Designs.Scorpion = {
	name = "Scorpion Egg",
	hatches = "Giant Scorpion",
	seed = 24,
	draw = function(egg)
		egg:base(DESERT.amber)
		for _, layer in { 3, 6, 9, 12, 15 } do
			egg:band(layer, layer, DESERT.amberDark)
		end
		-- A segmented tail rising from the back and curling over the top, with a glowing stinger.
		local A = { DESERT.amber }
		local D = { DESERT.amberDark }
		local V = { DESERT.venom, NEON }
		spriteZ(egg, {
			"...DAD..",
			"..A...A.",
			"..D...D.",
			"..A...VV",
			"..D...V.",
			"..A.....",
			"..D.....",
		}, -5, 22, { -1, 0 }, { A = A, D = D, V = V })
		-- Open pincers reaching forward.
		spriteTop(egg, {
			"A.A",
			"AAA",
			".D.",
			".A.",
			".D.",
		}, -6, 9, { 4, 5 }, { A = A, D = D }, true)
	end,
}

Designs.PharaohJackal = {
	name = "Pharaoh Jackal Egg",
	hatches = "Pharaoh Jackal",
	seed = 25,
	draw = function(egg)
		egg:base(DESERT.black)
		-- Striped headdress over the top half.
		stripes(egg, 8, 22.5, DESERT.gold, 9, 16)
		stripes(egg, 8, 22.5, DESERT.lapis, 9, 16, 0, 22.5)
		-- Jewelled collar.
		egg:band(6, 7, DESERT.gold)
		stripes(egg, 12, 10, DESERT.teal, 6, 7)
		-- Tall pointed ears, gold inside.
		local K = { DESERT.black }
		local G = { DESERT.gold }
		sprite(egg, {
			"K..",
			"KK.",
			"KKK",
			"KKK",
			"KKK",
			"KKK",
			".KK",
		}, -5, 22, { -1, 0 }, { K = K }, true)
		sprite(egg, {
			".G.",
			".G.",
			".GG",
			".GG",
		}, -5, 20, { 1 }, { G = G }, true)
	end,
}

Designs.Sphinx = {
	name = "Sphinx Egg",
	hatches = "Sphinx",
	seed = 26,
	draw = function(egg)
		egg:base(DESERT.stone)
		-- Striped headdress, with flaps hanging down either side of the face.
		for layer = 10, 16 do
			egg:band(layer, layer, if layer % 2 == 0 then DESERT.lapis else DESERT.gold)
		end
		egg:paint(function(cell)
			local near = math.min(math.abs(cell.angle - 60), math.abs(cell.angle - 120))
			if cell.facing == "side" and cell.y >= 5 and cell.y <= 9 and near < 14 then
				return if cell.y % 2 == 0 then DESERT.lapis else DESERT.gold
			end
			return nil
		end)
		-- Carved marks on the back.
		spots(egg, DESERT.stoneDark, { { 3, 240, 1.2 }, { 5, 260, 1.2 }, { 4, 300, 1.2 }, { 7, 280, 1.4 } })
		-- Folded stone wings on both sides, pointing back.
		local S = { DESERT.stone }
		local D = { DESERT.stoneDark }
		local wing = {
			"..SSSS",
			".SDDDS",
			"SDDDS.",
			"SDDS..",
			"SDS...",
			"SS....",
		}
		spriteZ(egg, wing, -5, 9, { 6, 7 }, { S = S, D = D })
		spriteZ(egg, wing, -5, 9, { -7, -8 }, { S = S, D = D })
		-- Gold beard under the face.
		egg:fill(-1, 3, 6, 0, 4, 6, DESERT.gold)
		egg:fill(-1, 2, 6, 0, 2, 6, DESERT.lapis)
		-- Crown with a gem.
		egg:fill(-1, 17, -1, 0, 18, 0, DESERT.gold)
		egg:set(0, 19, -1, DESERT.teal, NEON)
		egg:set(-1, 19, -1, DESERT.gold)
	end,
}

Designs.Fennec = {
	name = "Fennec Egg",
	hatches = "Fennec Fox",
	seed = 27,
	draw = function(egg)
		egg:base(DESERT.cream)
		zigzagFill(egg, 10, 2, 6, true, DESERT.ginger)
		-- Big ears with pink insides.
		pairCells(egg, { { -3, 16, 0 }, { -3, 17, 0 }, { -3, 18, 0 }, { -3, 16, -1 }, { -3, 17, -1 } }, DESERT.ginger)
		pairCells(egg, { { -3, 16, 1 }, { -3, 17, 1 } }, DESERT.pink)
	end,
}

Designs.Scarab = {
	name = "Scarab Egg",
	hatches = "Golden Scarab",
	seed = 28,
	draw = function(egg)
		egg:base(DESERT.scarab)
		egg:band(1, 2, DESERT.bronze)
		egg:band(13, 16, DESERT.bronze)
		egg:band(12, 12, DESERT.teal)
		-- The seam between its wing cases, down the back, and a shimmer on the wings.
		egg:paint(function(cell)
			local back = math.abs(cell.angle - 270)
			if cell.facing == "side" and cell.y >= 3 and cell.y <= 11 and back < 10 then
				return DESERT.seam
			end
			return nil
		end)
		spots(egg, DESERT.teal, { { 7, 215, 2 }, { 9, 325, 2 }, { 5, 330, 1.4 }, { 5, 210, 1.4 } })
		-- A curved horn on its head.
		spriteZ(egg, {
			"..H",
			".H.",
			".H.",
			"H..",
		}, 0, 20, { -1, 0 }, { H = { DESERT.bronzeDark } })
		-- Three legs down each side.
		for _, layer in { 4, 6, 8 } do
			pairCells(egg, { { 6, layer, 0 }, { 7, layer - 1, 0 } }, DESERT.bronzeDark)
		end
		egg:light(DESERT.gold, 1.6, 12)
		egg:particles("Sparkles", DESERT.gold, 6)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Snow

Designs.Snowball = {
	name = "Snowball Egg",
	hatches = "Snow Hare",
	seed = 31,
	draw = function(egg)
		egg:base(SNOW.snow)
		spots(egg, SNOW.frost, { { 3, 80, 3 }, { 9, 200, 3.4 }, { 12, 20, 2.6 }, { 6, 300, 2.6 } })
	end,
}

Designs.Snowcap = {
	name = "Snowcap Egg",
	hatches = "Arctic Fox",
	seed = 32,
	draw = function(egg)
		egg:base(SNOW.ice)
		egg:band(13, 16, SNOW.snow)
		zigzagFill(egg, 10, 2, 7, true, SNOW.snow)
		spots(egg, SNOW.frost, { { 4, 40, 2 }, { 6, 220, 2 } })
	end,
}

Designs.Knitted = {
	name = "Knitted Egg",
	hatches = "Reindeer",
	seed = 33,
	draw = function(egg)
		egg:base(SNOW.knitCream)
		egg:band(3, 4, SNOW.knitRed)
		egg:band(12, 13, SNOW.knitRed)
		zigzag(egg, 7, 2, 8, 1, SNOW.knitGreen)
		egg:paint(function(cell)
			if (cell.y == 6 or cell.y == 10) and math.floor(cell.angle / 30) % 2 == 0 then
				return SNOW.knitRed
			end
			return nil
		end)
		-- Little antler nubs.
		pairCells(egg, { { -2, 17, 0 }, { -2, 18, 0 }, { -3, 19, 0 }, { -1, 19, 0 } }, SNOW.brown)
	end,
}

Designs.Mammoth = {
	name = "Mammoth Egg",
	hatches = "Woolly Mammoth",
	seed = 34,
	profile = "Round",
	draw = function(egg)
		egg:base(SNOW.brown)
		streaks(egg, SNOW.brownDark, 14, 4, 4, 15, 4)
		-- Snow on its head.
		egg:band(16, 16, SNOW.snow)
		streaks(egg, SNOW.snow, 10, 8, 15, 15, 2)
		-- A trunk down the front, between big curved tusks.
		local B = { SNOW.brown }
		spriteZ(egg, {
			"B..",
			"B..",
			"B..",
			"B..",
			"BB.",
			".BB",
		}, 6, 10, { -1, 0 }, { B = B })
		local tusk =
			{ { -3, 7, 6 }, { -3, 6, 7 }, { -4, 6, 8 }, { -5, 7, 8 }, { -5, 8, 8 }, { -5, 9, 7 }, { -6, 10, 7 } }
		pairCells(egg, tusk, SNOW.ivory)
		pairCells(egg, { { -2, 7, 6 }, { -3, 7, 7 }, { -4, 7, 8 } }, SNOW.ivory)
		egg:light(SNOW.glow, 1.6, 12)
		egg:particles("Snow", SNOW.snow, 8)
	end,
}

Designs.Sabertooth = {
	name = "Sabertooth Egg",
	hatches = "Sabertooth Cat",
	seed = 35,
	draw = function(egg)
		egg:base(SNOW.pale)
		-- Wavy tiger stripes round the sides and back; the face stays clear.
		egg:paint(function(cell)
			if cell.facing ~= "side" or cell.y < 3 or cell.y > 14 then
				return nil
			end
			if cell.angle > 55 and cell.angle < 125 then
				return nil
			end
			local wobble = wave(cell.y, 90) * 10
			if (cell.angle + wobble) % 40 < 11 then
				return SNOW.slate
			end
			return nil
		end)
		-- Stripes over the brow.
		egg:paint(function(cell)
			if cell.y >= 13 and cell.y <= 15 and cell.angle > 60 and cell.angle < 120 then
				local column = math.floor(cell.angle / 12)
				if column % 2 == 0 then
					return SNOW.slate
				end
			end
			return nil
		end)
		-- Pointed ears with dark tips.
		sprite(egg, {
			"D..",
			"PP.",
			"PPP",
		}, -4, 18, { -1, 0 }, { P = { SNOW.pale }, D = { SNOW.slate } }, true)
		-- Long sabre fangs on the front.
		local F = { SNOW.ivory }
		spriteZ(egg, {
			"F",
			"F",
			"F",
			"F",
			"F",
		}, 6, 8, { -3, 2 }, { F = F })
		egg:set(-3, 3, 6, SNOW.ivory)
		egg:set(2, 3, 6, SNOW.ivory)
		-- Ice-blue collar.
		egg:band(2, 2, SNOW.ice)
	end,
}

Designs.Yeti = {
	name = "Yeti Egg",
	hatches = "Yeti",
	seed = 36,
	profile = "Round",
	draw = function(egg)
		egg:base(SNOW.snow)
		streaks(egg, SNOW.frost, 16, 5, 5, 16, 4)
		-- A shaggy fringe around the bottom.
		egg:paint(function(cell)
			if cell.y == 4 and cell.facing == "side" and math.floor(cell.angle / 20) % 2 == 0 then
				return SNOW.frost
			end
			return nil
		end)
		-- Blue face patch.
		egg:spot(9, 90, 6.5, SNOW.iceDeep)
		egg:spot(9.5, 90, 3.5, SNOW.ice)
		-- Curling ice horns.
		local I = { SNOW.crystal, GLASS, 0.15 }
		local B = { SNOW.iceDeep }
		sprite(egg, {
			"II...",
			"I....",
			"I..B.",
			".IIB.",
			"...BB",
		}, -7, 19, { -1, 0 }, { I = I, B = B }, true)
	end,
}

Designs.FrostDragon = {
	name = "Frost Dragon Egg",
	hatches = "Frost Dragon",
	seed = 37,
	shelved = "Secret",
	profile = "Pointy",
	draw = function(egg)
		egg:base(SNOW.ice)
		-- Scales: staggered diamonds of a deeper blue.
		egg:paint(function(cell)
			if cell.facing ~= "side" then
				return nil
			end
			local row = cell.y // 2
			local column = math.floor((cell.angle + (row % 2) * 15) / 30)
			if cell.y % 2 == 0 and column % 2 == 0 then
				return SNOW.iceDeep
			end
			return nil
		end)
		egg:band(1, 2, SNOW.navy)
		-- Glowing frost veins.
		crack(egg, { { 2, 40 }, { 6, 70 }, { 9, 50 }, { 13, 80 } }, SNOW.glow, NEON, 0.55)
		crack(egg, { { 3, 220 }, { 7, 250 }, { 11, 230 } }, SNOW.glow, NEON, 0.55)
		-- Ice crystals along its back.
		local C = { SNOW.crystal, GLASS, 0.2 }
		for _, layer in { 4, 7, 10 } do
			local x, z = egg:outward(layer, 270, 0)
			egg:set(x, layer, z, C[1], C[2], C[3])
			egg:set(x, layer + 1, z, C[1], C[2], C[3])
			egg:set(x, layer, z - 1, C[1], C[2], C[3])
		end
		-- Swept-back crystal horns.
		sprite(egg, {
			"C.....",
			"CC....",
			".C....",
			".CC...",
			"..CCC.",
		}, -6, 21, { 0 }, { C = C }, true)
	end,
}

Designs.AuroraOwl = {
	name = "Aurora Owl Egg",
	hatches = "Aurora Owl",
	seed = 38,
	profile = "Round",
	draw = function(egg)
		egg:base(SNOW.night)
		-- Northern lights rippling round it.
		zigzag(egg, 8, 1, 4, 1, SNOW.auroraGreen, NEON)
		zigzag(egg, 10, 1, 4, 1, SNOW.auroraTeal, NEON)
		zigzag(egg, 12, 1, 4, 1, SNOW.auroraViolet, NEON)
		-- Pale feathered chest on the front.
		egg:paint(function(cell)
			if cell.facing == "side" and cell.y >= 2 and cell.y <= 7 and cell.angle > 60 and cell.angle < 120 then
				if cell.y % 3 == 0 and math.floor(cell.angle / 12) % 2 == 0 then
					return SNOW.chestMark
				end
				return SNOW.chest
			end
			return nil
		end)
		-- Feather tufts on top.
		sprite(egg, {
			"A..",
			"NN.",
			".NN",
		}, -4, 19, { -1, 0 }, { N = { SNOW.nightWing }, A = { SNOW.auroraTeal, NEON } }, true)
		-- Wings folded at its sides.
		local wing = {
			"..WWWW",
			".WFFFW",
			"WFFFW.",
			"WFFW..",
			"WFW...",
			"AW....",
			"A.....",
		}
		local key = { W = { SNOW.nightWing }, F = { SNOW.feather }, A = { SNOW.auroraTeal, NEON } }
		spriteZ(egg, wing, -5, 10, { 6 }, key)
		spriteZ(egg, wing, -5, 10, { -7 }, key)
		egg:light(SNOW.auroraTeal, 1.8, 13)
		egg:particles("Sparkles", SNOW.auroraGreen, 6)
	end,
}

Designs.FrostWolf = {
	name = "Frost Wolf Egg",
	hatches = "Frost Wolf",
	seed = 39,
	draw = function(egg)
		egg:base(SNOW.wolf)
		-- Dark saddle down its back, pale chest on the front.
		egg:paint(function(cell)
			if cell.facing == "side" and cell.y >= 4 and cell.y <= 14 and cell.angle > 200 and cell.angle < 340 then
				return SNOW.wolfDark
			end
			return nil
		end)
		egg:spot(6, 90, 7, SNOW.snow)
		-- A mane of ice crystals round its neck.
		for angle = 22.5, 360, 45 do
			local x, z = egg:outward(12, angle, 0)
			egg:set(x, 12, z, SNOW.crystal, GLASS, 0.15)
			egg:set(x, 13, z, SNOW.crystal, GLASS, 0.15)
		end
		-- Tall pointed ears, pale inside.
		sprite(egg, {
			"W..",
			"WW.",
			"WWW",
			"WWW",
			".WW",
		}, -4, 20, { -1, 0 }, { W = { SNOW.wolf } }, true)
		pairCells(egg, { { -3, 17, 1 }, { -3, 18, 1 } }, SNOW.snow)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Ocean

Designs.Seafoam = {
	name = "Seafoam Egg",
	hatches = "Hermit Crab",
	seed = 41,
	shelved = "Common",
	draw = function(egg)
		egg:base(OCEAN.aqua)
		zigzagFill(egg, 2, 2, 8, false, OCEAN.foam)
	end,
}

Designs.Turtle = {
	name = "Turtle Egg",
	hatches = "Sea Turtle",
	seed = 42,
	draw = function(egg)
		egg:base(OCEAN.turtle)
		egg:band(1, 2, OCEAN.shellCream)
		-- Shell plates: rings with staggered seams.
		for _, layer in { 3, 7, 11, 15 } do
			egg:band(layer, layer, OCEAN.turtleDark)
		end
		egg:paint(function(cell)
			if cell.facing ~= "side" or cell.y < 3 then
				return nil
			end
			local row = (cell.y - 3) // 4
			if (cell.angle + row * 30) % 60 < 9 then
				return OCEAN.turtleDark
			end
			return nil
		end)
	end,
}

Designs.Dolphin = {
	name = "Dolphin Egg",
	hatches = "Dolphin",
	seed = 43,
	draw = function(egg)
		egg:base(OCEAN.dolphin)
		-- Pale belly down the front.
		egg:paint(function(cell)
			if cell.y >= 2 and cell.y <= 11 and cell.angle > 35 and cell.angle < 145 then
				return OCEAN.belly
			end
			return nil
		end)
		-- A wave across the back.
		zigzag(egg, 4, 1, 5, 1, OCEAN.foam)
		-- Dorsal fin on the back.
		spriteZ(egg, {
			"F..",
			"FF.",
			"FFF",
			".FF",
		}, -9, 9, { -1, 0 }, { F = { OCEAN.dolphin } })
	end,
}

Designs.Manta = {
	name = "Manta Egg",
	hatches = "Manta Ray",
	seed = 44,
	draw = function(egg)
		egg:base(OCEAN.navy)
		egg:paint(function(cell)
			if cell.angle > 30 and cell.angle < 150 and cell.y <= 13 then
				return OCEAN.belly
			end
			return nil
		end)
		spots(egg, OCEAN.spot, { { 5, 240, 1.8 }, { 8, 280, 2 }, { 11, 250, 1.8 }, { 7, 320, 1.6 }, { 10, 200, 1.6 } })
		-- Wide wing fins on both sides.
		local N = { OCEAN.navy }
		sprite(egg, {
			"N.",
			"NN",
			"NN",
			"NN",
			".N",
		}, -8, 11, { -1, 0 }, { N = N }, true)
		-- Curled head fins on top.
		pairCells(egg, { { -2, 17, -1 }, { -2, 18, -1 }, { -1, 18, -1 } }, OCEAN.navy)
	end,
}

Designs.Narwhal = {
	name = "Narwhal Egg",
	hatches = "Narwhal",
	seed = 45,
	draw = function(egg)
		egg:base(OCEAN.slate)
		blotches(egg, OCEAN.slateDark, 0.22, 5, 6, 16)
		egg:band(1, 4, OCEAN.belly)
		zigzag(egg, 5, 1, 6, 1, OCEAN.belly)
		-- A long spiral tusk.
		for y = 17, 20 do
			egg:fill(-1, y, -1, 0, y, 0, OCEAN.ivory)
			local turn = (y - 17) % 4
			local spiral = ({ { -1, -1 }, { 0, -1 }, { 0, 0 }, { -1, 0 } })[turn + 1]
			egg:set(spiral[1], y, spiral[2], OCEAN.ivoryDark)
		end
		for y = 21, 24 do
			egg:set(0, y, 0, if y % 2 == 0 then OCEAN.ivory else OCEAN.ivoryDark)
		end
	end,
}

Designs.Kraken = {
	name = "Kraken Egg",
	hatches = "Kraken",
	seed = 46,
	profile = "Round",
	draw = function(egg)
		egg:base(OCEAN.purple)
		-- Tentacles wrapping round in a spiral, with suckers.
		stripes(egg, 3, 36, OCEAN.magenta, 1, 15, 14)
		stripes(egg, 3, 10, OCEAN.sucker, 2, 14, 14, 13)
		-- Four tentacles curling off the top.
		local T = { OCEAN.magenta }
		local P = { OCEAN.sucker }
		local curl = {
			".TT..",
			"T..T.",
			"P..T.",
			"...TT",
		}
		sprite(egg, curl, -5, 20, { 0 }, { T = T, P = P }, true)
		spriteZ(egg, curl, -5, 20, { -1 }, { T = T, P = P })
		spriteZ(egg, {
			"..TT.",
			".T..T",
			".T..P",
			"TT...",
		}, 0, 20, { -1 }, { T = T, P = P })
	end,
}

Designs.Abyss = {
	name = "Abyss Egg",
	hatches = "Leviathan",
	seed = 47,
	profile = "Pointy",
	draw = function(egg)
		egg:base(OCEAN.abyss)
		egg:paint(function(cell)
			if cell.facing == "side" and cell.y % 3 == 0 and math.floor(cell.angle / 30) % 2 == 0 then
				return OCEAN.abyssScale
			end
			return nil
		end)
		-- Glowing lights in rows, like a deep-sea fish.
		egg:paint(function(cell)
			if cell.facing ~= "side" or cell.y % 2 ~= 0 or cell.y < 3 or cell.y > 13 then
				return nil
			end
			for _, line in { 0, 120, 240 } do
				local d = math.abs((cell.angle - line + 180) % 360 - 180)
				if d < 8 then
					return OCEAN.biolume, NEON
				end
			end
			return nil
		end)
		-- A see-through fin crest over the top.
		local F = { OCEAN.finGlass, GLASS, 0.3 }
		local R = { OCEAN.biolume, NEON }
		sprite(egg, {
			"....F",
			"...FR",
			"..FFR",
			".FFR.",
			"FFR..",
		}, -4, 21, { 0 }, { F = F, R = R }, true)
		egg:particles("Bubbles", OCEAN.biolume, 6)
		egg:light(OCEAN.biolume, 2, 14)
	end,
}

Designs.GreatShark = {
	name = "Great Shark Egg",
	hatches = "Great Shark",
	seed = 50,
	draw = function(egg)
		egg:base(OCEAN.shark)
		-- A jagged white underside, a grin full of teeth on the front, gill slits, and a tall fin on its back.
		zigzagFill(egg, 5, 2, 7, false, OCEAN.sharkBelly)
		egg:paint(function(cell)
			if cell.facing ~= "side" or cell.angle < 55 or cell.angle > 125 then
				return nil
			end
			if cell.y == 6 then
				return OCEAN.sharkMouth
			elseif cell.y == 7 then
				return if math.floor(cell.angle / 8) % 2 == 0 then OCEAN.sharkBelly else OCEAN.sharkMouth
			end
			return nil
		end)
		spots(egg, rgb(20, 22, 28), { { 10, 62, 1.2 }, { 10, 118, 1.2 } })
		egg:paint(function(cell)
			if cell.facing ~= "side" or cell.y < 7 or cell.y > 10 then
				return nil
			end
			for _, line in { 25, 35, 145, 155 } do
				if math.abs(cell.angle - line) < 3 then
					return OCEAN.sharkDark
				end
			end
			return nil
		end)
		spriteZ(egg, {
			"F...",
			"FF..",
			"FFF.",
			".FFF",
			"..FF",
		}, -9, 13, { -1, 0 }, { F = { OCEAN.sharkDark } })
		pairCells(egg, { { 6, 6, 0 }, { 6, 5, 1 }, { 7, 5, 1 }, { 7, 4, 2 } }, OCEAN.shark)
	end,
}

Designs.KingCrab = {
	name = "King Crab Egg",
	hatches = "King Crab",
	seed = 48,
	shelved = "Epic",
	profile = "Round",
	draw = function(egg)
		egg:base(OCEAN.crab)
		egg:band(1, 3, OCEAN.crabBelly)
		zigzag(egg, 4, 1, 8, 1, OCEAN.crabBelly)
		-- Knobbly shell.
		spots(egg, OCEAN.crabDark, {
			{ 8, 30, 1.6 },
			{ 11, 150, 1.6 },
			{ 9, 250, 1.8 },
			{ 13, 320, 1.4 },
			{ 12, 60, 1.4 },
			{ 7, 200, 1.6 },
		})
		-- Big claws reaching forward.
		spriteTop(egg, {
			"CC.C",
			"CCCC",
			".CC.",
			"..C.",
			"..C.",
			"..C.",
		}, -6, 10, { 6, 7 }, { C = { OCEAN.crab } }, true)
		-- Eyes on stalks.
		pairCells(egg, { { -2, 17, 0 }, { -2, 18, 0 } }, OCEAN.crab)
		pairCells(egg, { { -2, 19, 0 } }, OCEAN.crabEye)
		-- Legs down the sides.
		for _, layer in { 4, 6, 8 } do
			pairCells(egg, { { 6, layer, -1 }, { 7, layer - 1, -1 } }, OCEAN.crabDark)
		end
	end,
}

Designs.Hippocampus = {
	name = "Hippocampus Egg",
	hatches = "Hippocampus",
	seed = 49,
	profile = "Pointy",
	draw = function(egg)
		egg:base(OCEAN.seahorse)
		-- Ridged rings, like a sea horse.
		for layer = 3, 13, 2 do
			egg:band(layer, layer, OCEAN.seahorseDark)
		end
		-- Pale, ridged belly down the front.
		egg:paint(function(cell)
			local front = cell.angle > 60 and cell.angle < 120
			if cell.facing == "side" and cell.y >= 2 and cell.y <= 10 and front and cell.y % 2 == 0 then
				return OCEAN.seahorseBelly
			end
			return nil
		end)
		-- A long horse-like snout, and a little crown of spikes on its head.
		egg:fill(-1, 12, 4, 0, 13, 4, OCEAN.seahorse)
		egg:fill(-1, 12, 5, 0, 12, 7, OCEAN.seahorse)
		egg:fill(-1, 12, 8, 0, 12, 8, OCEAN.seahorseDark)
		cells(
			egg,
			{ { -1, 17, 0 }, { 0, 17, 0 }, { -1, 18, 0 }, { 0, 18, -1 }, { -2, 16, 0 }, { 1, 16, -1 } },
			OCEAN.biolume
		)
		-- A see-through fin mane down the back of its head, with glowing ribs.
		for y = 9, 17 do
			local back = -math.floor(egg:halfWidth(y)) - 1
			for _, x in { -1, 0 } do
				egg:set(x, y, back, OCEAN.biolume, NEON)
				egg:set(x, y, back - 1, OCEAN.finGlass, GLASS, 0.3)
				if y % 2 == 1 then
					egg:set(x, y, back - 2, OCEAN.finGlass, GLASS, 0.3)
				end
			end
		end
		-- A tail curled up under it.
		spriteZ(egg, {
			".TT.",
			"T..T",
			"T.T.",
			".T..",
		}, -2, 0, { -1, 0 }, { T = { OCEAN.seahorseDark } })
		egg:light(OCEAN.biolume, 1.6, 12)
		egg:particles("Bubbles", OCEAN.foam, 6)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Volcano

Designs.Ash = {
	name = "Ash Egg",
	hatches = "Fire Salamander",
	seed = 51,
	shelved = "Common",
	draw = function(egg)
		egg:base(VOLCANO.ash)
		spots(egg, VOLCANO.ember, { { 4, 120, 2 }, { 9, 300, 2.4 }, { 12, 60, 1.8 } })
	end,
}

Designs.MagmaToad = {
	name = "Magma Toad Egg",
	hatches = "Magma Toad",
	seed = 52,
	shelved = "Uncommon",
	profile = "Round",
	draw = function(egg)
		egg:base(VOLCANO.toad)
		egg:band(1, 3, VOLCANO.toadBelly)
		-- Raised warts.
		for index, place in { { 5, 30 }, { 8, 95 }, { 11, 160 }, { 6, 210 }, { 9, 280 }, { 13, 340 }, { 12, 60 } } do
			local x, z = egg:outward(place[1], place[2], 0)
			egg:set(x, place[1], z, VOLCANO.wart)
			if index % 2 == 0 then
				egg:set(x, place[1] + 1, z, VOLCANO.wart)
			end
		end
	end,
}

Designs.Obsidian = {
	name = "Obsidian Egg",
	hatches = "Obsidian Goat",
	seed = 53,
	draw = function(egg)
		egg:base(VOLCANO.obsidian, GLASS)
		spots(egg, VOLCANO.shard, { { 5, 40, 2.6 }, { 10, 160, 3 }, { 7, 260, 2.4 }, { 13, 320, 2 } }, GLASS)
		-- Curled goat horns.
		local H = { VOLCANO.horn }
		sprite(egg, {
			".HH..",
			"H..H.",
			"H....",
			".H...",
		}, -5, 20, { 0 }, { H = H }, true)
		pairCells(egg, { { -2, 17, 0 }, { -3, 17, 0 } }, VOLCANO.horn)
	end,
}

Designs.CinderBoar = {
	name = "Cinder Boar Egg",
	hatches = "Cinder Boar",
	seed = 54,
	profile = "Round",
	draw = function(egg)
		egg:base(VOLCANO.boar)
		speckle(egg, VOLCANO.ember, 0.05, 3, 2, 12)
		-- A glowing bristle ridge down its back.
		for layer = 5, 16 do
			local x, z = egg:outward(layer, 270, 0)
			egg:set(x, layer, z, if layer % 2 == 0 then VOLCANO.lava else VOLCANO.lavaHot, NEON)
			if layer % 2 == 0 and layer < 15 then
				egg:set(x, layer, z - 1, VOLCANO.lava, NEON)
			end
		end
		-- Snout with nostrils, and tusks curling up beside it.
		egg:fill(-2, 6, 6, 1, 8, 6, VOLCANO.snout)
		egg:set(-1, 7, 7, VOLCANO.boar)
		egg:set(0, 7, 7, VOLCANO.boar)
		egg:fill(-2, 6, 7, -2, 8, 7, VOLCANO.snout)
		egg:fill(1, 6, 7, 1, 8, 7, VOLCANO.snout)
		egg:fill(-1, 6, 7, 0, 6, 7, VOLCANO.snout)
		egg:fill(-1, 8, 7, 0, 8, 7, VOLCANO.snout)
		pairCells(egg, { { -4, 6, 6 }, { -4, 7, 7 }, { -5, 8, 7 }, { -5, 9, 7 } }, VOLCANO.tusk)
	end,
}

Designs.Cerberus = {
	name = "Cerberus Egg",
	hatches = "Cerberus",
	seed = 55,
	draw = function(egg)
		egg:base(VOLCANO.charcoal)
		-- Fire markings licking up from the bottom.
		zigzag(egg, 1, 3, 6, 1, VOLCANO.ember, NEON)
		-- Spiked collar.
		egg:band(7, 8, VOLCANO.collar)
		for angle = 0, 315, 45 do
			local x, z = egg:outward(7, angle + 22.5, 0)
			egg:set(x, 7, z, VOLCANO.silver)
			egg:set(x, 8, z, VOLCANO.silver)
		end
		-- Three heads' worth of pointed ears, spaced around the top, glowing inside.
		for _, head in { 90, 210, 330 } do
			for _, side in { -32, 32 } do
				local angle = math.rad(head + side)
				local x = math.floor(math.cos(angle) * 2.6)
				local z = math.floor(math.sin(angle) * 2.6)
				egg:set(x, 16, z, VOLCANO.charcoal)
				egg:set(x, 17, z, VOLCANO.charcoal)
				egg:set(x, 18, z, VOLCANO.charcoal)
				local ox = math.floor(math.cos(angle) * 3.6)
				local oz = math.floor(math.sin(angle) * 3.6)
				egg:set(ox, 16, oz, VOLCANO.ember, NEON)
				egg:set(ox, 17, oz, VOLCANO.charcoal)
			end
		end
		egg:particles("Embers", VOLCANO.ember, 5)
	end,
}

Designs.Chimera = {
	name = "Chimera Egg",
	hatches = "Chimera",
	seed = 56,
	draw = function(egg)
		-- Snake below, lion in the middle, goat on top.
		egg:base(VOLCANO.lion)
		egg:band(1, 5, VOLCANO.snake)
		egg:paint(function(cell)
			if cell.y <= 5 and (cell.y + math.floor(cell.angle / 30)) % 2 == 0 then
				return VOLCANO.snakeDark
			end
			return nil
		end)
		egg:band(13, 16, VOLCANO.goat)
		-- Shaggy lion's mane.
		egg:band(11, 12, VOLCANO.mane)
		egg:paint(function(cell)
			if cell.y == 10 and math.floor(cell.angle / 18) % 2 == 0 then
				return VOLCANO.mane
			end
			return nil
		end)
		-- Goat horns.
		local H = { VOLCANO.horn }
		sprite(egg, {
			"HH...",
			"H.H..",
			"...H.",
			"...HH",
		}, -6, 20, { -1, 0 }, { H = H }, true)
		-- Snake tail curling under.
		local S = { VOLCANO.snake }
		local D = { VOLCANO.snakeDark }
		local L = { VOLCANO.lavaHot, NEON }
		sprite(egg, {
			"..SD.",
			"....S",
			"..L.D",
			"..DSS",
		}, -2, 0, { -1, 0 }, { S = S, D = D, L = L })
	end,
}

Designs.MagmaDragon = {
	name = "Magma Dragon Egg",
	hatches = "Magma Dragon",
	seed = 57,
	shelved = "Secret",
	profile = "Pointy",
	draw = function(egg)
		egg:base(VOLCANO.dragon)
		-- Dark scales.
		egg:paint(function(cell)
			if
				cell.facing == "side"
				and cell.y % 2 == 1
				and math.floor((cell.angle + (cell.y % 4) * 15) / 30) % 2 == 0
			then
				return VOLCANO.dragonScale
			end
			return nil
		end)
		-- Molten bottom.
		egg:band(1, 1, VOLCANO.lava, NEON)
		zigzag(egg, 2, 1, 8, 1, VOLCANO.lava, NEON)
		-- Lava cracks splitting the shell.
		crack(egg, { { 2, 20 }, { 5, 40 }, { 8, 25 }, { 11, 55 }, { 14, 45 } }, VOLCANO.lavaHot, NEON)
		crack(egg, { { 5, 40 }, { 7, 75 } }, VOLCANO.lava, NEON)
		crack(egg, { { 2, 160 }, { 6, 140 }, { 9, 170 }, { 12, 150 } }, VOLCANO.lava, NEON)
		crack(egg, { { 2, 270 }, { 5, 250 }, { 8, 285 }, { 10, 270 } }, VOLCANO.lavaHot, NEON)
		-- Spines down its back, tipped with fire.
		for _, layer in { 4, 6, 8, 10, 12 } do
			local x, z = egg:outward(layer, 270, 0)
			egg:set(x, layer, z, VOLCANO.dragonHorn)
			egg:set(x, layer + 1, z, VOLCANO.lava, NEON)
		end
		-- Big swept-back horns with glowing tips.
		local H = { VOLCANO.dragonHorn }
		local L = { VOLCANO.lava, NEON }
		local Y = { VOLCANO.lavaHot, NEON }
		sprite(egg, {
			"Y.....",
			"L.....",
			"H.....",
			".H....",
			".HH...",
			"..HHH.",
		}, -6, 21, { -1, 0 }, { H = H, L = L, Y = Y }, true)
		egg:light(VOLCANO.lava, 2.5, 16)
		egg:particles("Embers", VOLCANO.lava, 10)
	end,
}

Designs.EternalPhoenix = {
	name = "Eternal Phoenix Egg",
	hatches = "Eternal Phoenix",
	seed = 58,
	draw = function(egg)
		-- Flame colours rising from deep red to gold, tipped with eternal blue.
		egg:base(VOLCANO.crimson)
		zigzagFill(egg, 4, 2, 6, true, VOLCANO.flame)
		zigzagFill(egg, 7, 2, 6, true, VOLCANO.orange)
		zigzagFill(egg, 10, 2, 6, true, VOLCANO.gold)
		zigzagFill(egg, 13, 1, 6, true, VOLCANO.paleGold)
		egg:band(16, 16, VOLCANO.eternal, NEON)
		zigzag(egg, 14, 1, 6, 1, VOLCANO.eternal, NEON)
		-- A fan of flame plumes, orange at the root, gold, then eternal blue at the tips.
		local O = { VOLCANO.orange, NEON }
		local G = { VOLCANO.gold, NEON }
		local E = { VOLCANO.eternal, NEON }
		sprite(egg, {
			"......E",
			"..E...E",
			"..G...G",
			"...G..G",
			"E..O..O",
			"G..O..O",
			".GO.O.O",
			"..OOOOO",
		}, -7, 24, { -1, 0 }, { O = O, G = G, E = E }, true)
		-- Flame wings folded at its sides.
		local W = { VOLCANO.gold }
		local F = { VOLCANO.orange }
		local R = { VOLCANO.flame }
		local wing = {
			"...WWWW.",
			"..WFFFW.",
			".WFFR...",
			"EFFR....",
			"EFR.....",
			"ER......",
		}
		spriteZ(egg, wing, -5, 9, { 6 }, { W = W, F = F, R = R, E = E })
		spriteZ(egg, wing, -5, 9, { -7 }, { W = W, F = F, R = R, E = E })
		egg:light(VOLCANO.eternal, 3, 18)
		egg:particles("Embers", VOLCANO.gold, 14)
	end,
}

Designs.VolcanoTortoise = {
	name = "Volcano Tortoise Egg",
	hatches = "Volcano Tortoise",
	seed = 59,
	profile = "Round",
	draw = function(egg)
		egg:base(VOLCANO.tortoise)
		-- Shell plates split by glowing seams.
		for _, layer in { 4, 8 } do
			egg:band(layer, layer, VOLCANO.lava, NEON)
		end
		egg:paint(function(cell)
			if cell.facing ~= "side" or cell.y < 4 or cell.y > 11 then
				return nil
			end
			local row = if cell.y < 8 then 0 else 1
			if (cell.angle + row * 30) % 60 < 8 then
				return VOLCANO.lava, NEON
			end
			return nil
		end)
		-- A little volcano on its back, with lava running down.
		egg:band(12, 16, VOLCANO.cone)
		streaks(egg, VOLCANO.lava, 7, 6, 16, 16, 4)
		cells(egg, {
			{ -2, 17, -1 },
			{ -2, 17, 0 },
			{ 1, 17, -1 },
			{ 1, 17, 0 },
			{ -1, 17, -2 },
			{ 0, 17, -2 },
			{ -1, 17, 1 },
			{ 0, 17, 1 },
		}, VOLCANO.cone)
		egg:fill(-1, 17, -1, 0, 17, 0, VOLCANO.lavaHot, NEON)
		-- Stubby legs and a head poking out of the front.
		for _, angle in { 40, 140, 220, 320 } do
			local x, z = egg:outward(3, angle, 0)
			egg:set(x, 3, z, VOLCANO.skin)
			egg:set(x, 2, z, VOLCANO.skin)
		end
		egg:fill(-1, 4, 6, 0, 5, 7, VOLCANO.skin)
		egg:light(VOLCANO.lava, 2, 14)
		egg:particles("Embers", VOLCANO.lava, 6)
	end,
}

Designs.Salamander = {
	name = "Salamander Egg",
	hatches = "Fire Salamander",
	seed = 60,
	draw = function(egg)
		egg:base(VOLCANO.salamander)
		-- Bright yellow and orange blotches all over.
		spots(egg, VOLCANO.gold, {
			{ 3, 30, 2.4 },
			{ 5, 170, 2.6 },
			{ 7, 260, 2.4 },
			{ 9, 20, 2.6 },
			{ 11, 200, 2.4 },
			{ 13, 300, 2 },
			{ 12, 120, 2 },
			{ 4, 300, 2 },
			{ 6.4, 98, 3.4 },
			{ 10, 70, 2.2 },
			{ 9.5, 128, 2.9 },
		})
		spots(egg, VOLCANO.orange, { { 3, 110, 2 }, { 8, 330, 2 }, { 13, 40, 1.6 }, { 7, 150, 1.6 } })
		-- Feathery fire gills fanning out from its head.
		sprite(egg, {
			"G...",
			".G.G",
			"G.G.",
			".GG.",
			"..GG",
		}, -6, 20, { 0 }, { G = { VOLCANO.lava, NEON } }, true)
		-- Little legs.
		for _, layer in { 4, 9 } do
			pairCells(egg, { { 6, layer, 0 }, { 7, layer - 1, 0 } }, VOLCANO.salamander)
		end
		egg:particles("Embers", VOLCANO.orange, 6)
	end,
}

Designs.LavaGolem = {
	name = "Lava Golem Egg",
	hatches = "Lava Golem",
	seed = 61,
	profile = "Round",
	draw = function(egg)
		egg:base(VOLCANO.rock)
		blotches(egg, VOLCANO.rockLight, 0.3, 4, 1, 16)
		-- Lava glowing through the cracks between its rocks.
		crack(egg, { { 1, 30 }, { 4, 50 }, { 6, 20 }, { 9, 45 }, { 12, 30 }, { 15, 60 } }, VOLCANO.lava, NEON)
		crack(egg, { { 2, 150 }, { 5, 130 }, { 8, 165 }, { 11, 140 }, { 14, 170 } }, VOLCANO.lavaHot, NEON)
		crack(egg, { { 1, 260 }, { 4, 280 }, { 7, 250 }, { 10, 275 }, { 13, 255 } }, VOLCANO.lava, NEON)
		crack(egg, { { 7, 45 }, { 8, 90 }, { 7, 130 } }, VOLCANO.lavaHot, NEON)
		-- Boulder shoulders, cracked with lava.
		egg:pair(-8, 10, -2, -6, 13, 1, VOLCANO.rock)
		pairCells(egg, { { -8, 11, -1 }, { -8, 12, -1 }, { -8, 12, 0 }, { -7, 13, 0 } }, VOLCANO.lava, NEON)
		-- A molten crown on its head.
		cells(egg, {
			{ -2, 17, -1 },
			{ -2, 17, 0 },
			{ 1, 17, -1 },
			{ 1, 17, 0 },
			{ -1, 17, -2 },
			{ 0, 17, -2 },
			{ -1, 17, 1 },
			{ 0, 17, 1 },
		}, VOLCANO.rockLight)
		egg:fill(-1, 17, -1, 0, 17, 0, VOLCANO.lavaHot, NEON)
		egg:light(VOLCANO.lava, 2, 14)
		egg:particles("Embers", VOLCANO.lava, 8)
	end,
}

return Designs
