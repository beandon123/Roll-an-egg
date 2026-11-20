--!strict
-- The Jungle's pets, in the showpiece style (see PetModels/Forest for what that means): jungle animals and giant
-- insects in glossy, vivid colours, crisp angled legs, horns, mandibles and wings, and, the rarer they are, more
-- that glows. Four candidates the owner did not pick are shelved here, kept for later: no egg hatches them (the
-- Chameleon, Morpho Queen, Silverback King and Titan Beetle; their eggs are shelved too).
-- See PetModels/Kit for the drawing tools and PetModels/Designs for how a design is laid out.

local Kit = require(script.Parent.Kit)

type Design = Kit.Design
type Limb = Kit.Limb
type Look = Kit.Look
type Sculpt = Kit.Sculpt
type Vec = Kit.Vec

local rgb = Kit.rgb
local look = Kit.look
local noise = Kit.noise
local patches = Kit.patches
local ellipsoid = Kit.ellipsoid
local rod = Kit.rod
local newSculpt = Kit.newSculpt
local inUnits = Kit.inUnits
local sideOf = Kit.sideOf
local topOf = Kit.topOf
local vadd = Kit.vadd
local vscale = Kit.vscale
local vlerp = Kit.vlerp
local vnorm = Kit.vnorm
local alongPath = Kit.alongPath
local glossyEye = Kit.glossyEye

local NEON = Kit.NEON
local GLASS = Kit.GLASS
local SHINE = Kit.SHINE

local Jungle: { [string]: Design } = {}

-- An insect's leg through `points`, `widths` across each length, with a knobbly joint at every bend and a hooked
-- claw at the foot. `T` is the design's `inUnits`.
local function insectLeg(limb: Limb, T: any, points: { Vec }, widths: { number }, color: { number }, joint: { number })
	for i = 1, #points - 1 do
		if i == #points - 1 then
			T.taper(limb, points[i], points[i + 1], widths[i], widths[i], { 0, 1, 0 }, color)
		else
			T.blade(limb, points[i], points[i + 1], widths[i], widths[i], { 0, 1, 0 }, color)
			T.ball(limb, points[i + 1], widths[i] * 1.3, joint)
		end
	end
end

-- A long body in lengths (for the Serpent and Snake skeletons: Body, Segment1, Segment2 and Tail, each a limb of its
-- own so a ripple can run down it), from paths of { x, y, z, radius }. `paint(sculpt, path)` colours each one.
local function lengths(
	U: number,
	paths: { { { number } } },
	base: Look,
	paint: (Sculpt, { { number } }) -> ()
): { Sculpt }
	local list = {}
	for _, path in paths do
		local s = newSculpt(U)
		s:add(rod(path), base)
		paint(s, path)
		table.insert(list, s)
	end
	return list
end

-- Everything in `all` but `s`: the sculpts that overlap it, for drawing.
local function others(all: { Sculpt }, s: Sculpt): { Sculpt }
	local list = {}
	for _, other in all do
		if other ~= s then
			table.insert(list, other)
		end
	end
	return list
end

----------------------------------------------------------------------------------------------------------------
-- Poison Dart Frog (Uncommon): a plump little frog about a player's height, vivid blue blotched with black, deeper
-- blue on its legs, big glossy black eyes, a wide smile, and round pads on its splayed toes. It hops.

Jungle.PoisonDartFrog = {
	name = "Poison Dart Frog",
	skeleton = "LowSlung",
	gait = "Hop",
	scale = 0.3,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local BLUE = look(36, 112, 232)
		local BLUE_TOP = look(96, 168, 255)
		local BLUE_UNDER = look(20, 66, 160)
		local DEEP = look(20, 58, 170)
		local BLACK = look(18, 20, 30)
		local BELLY = look(150, 196, 255)
		local MOUTH = look(14, 30, 80)
		local PAD = rgb(30, 70, 190)

		local tones = {
			[BLUE] = { top = BLUE_TOP, under = BLUE_UNDER },
			[DEEP] = { under = BLUE_UNDER },
		}
		-- Black blotches over a blue back; a pale throat and belly.
		local function skin(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.45 then
				return BELLY
			end
			if patches(p, 1.5) < 0.26 then
				return BLACK
			end
			return nil
		end
		local function legSkin(p: Vec, open: any, n: Vec): Look?
			local spot = skin(p, open, n)
			return if spot == BLACK then BLACK else DEEP
		end

		-- A squat round body and a broad head with a wide mouth.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 7.4, -0.6 }, { 5.6, 4.8, 6.6 }), BLUE)
		body:add(ellipsoid({ 0, 8.6, 4.4 }, { 5.2, 3.8, 4.4 }), BLUE)
		body:coat(skin)
		body:bake(tones)
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 9.6, 7.2 }, { 4.8, 3.2, 3.8 }), BLUE)
		head:coat(function(p, open, n)
			if p[3] > 7 and p[2] > 8.2 and p[2] < 9 and n[3] > 0.1 then
				return MOUTH
			end
			return skin(p, open, n)
		end)
		head:bake(tones)

		-- Front legs short and splayed; back legs folded under big haunches.
		local front, back = newSculpt(U), newSculpt(U)
		front:add(rod({ { 3.6, 6.4, 5, 1.5 }, { 5.6, 3.6, 7, 1.1 }, { 5.8, 1, 8.4, 0.9 } }), DEEP)
		back:add(ellipsoid({ 4.4, 5.6, -4 }, { 2.8, 3.4, 4 }), DEEP)
		back:add(rod({ { 5.6, 3.6, -5.4, 1.6 }, { 6.6, 1.8, -1.6, 1.1 }, { 6.6, 1, 0.4, 0.9 } }), DEEP)
		for _, s in { front, back } do
			s:coat(legSkin)
			s:bake(tones)
		end
		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 6.2, -6.6 }, { 2.6, 2.4, 1.6 }), BLUE)
		tail:coat(skin)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 7, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, BLUE)

		local headLimb = pet:limb("Head", T.at({ 0, 9, 5 }))
		head:draw(headLimb, { body }, BLUE)
		-- Big glossy black eyes bulging from the top of the head.
		for _, s in { 1, -1 } do
			T.ball(headLimb, { 3 * s, 11.6, 7.6 }, { 3, 3, 3 }, BLACK.color)
			T.ball(headLimb, { 3.5 * s, 12.4, 8.4 }, { 0.9, 0.9, 0.9 }, SHINE)
			T.ball(headLimb, { 3.9 * s, 11.6, 8.6 }, { 0.4, 0.4, 0.4 }, SHINE)
		end

		-- Four long toes on each foot, each ending in a round pad.
		local function toes(limb: Limb, foot: Vec, spread: number, length: number)
			for i = -1.5, 1.5 do
				local a = math.rad(i * spread)
				local tip = vadd(foot, { math.sin(a) * length, -foot[2] + 0.35, math.cos(a) * length })
				T.blade(limb, foot, tip, 0.55, 0.45, { 0, 1, 0 }, DEEP.color)
				T.ball(limb, tip, { 1, 0.7, 1 }, PAD)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.6, 6.4, 5 }), function(limb)
			front:draw(limb, { body }, BLUE)
			toes(limb, { 5.8, 0.9, 8.4 }, 30, 1.8)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4.4, 5.6, -4 }), function(limb)
			back:draw(limb, { body, tail }, BLUE)
			toes(limb, { 6.6, 0.9, 0.4 }, 24, 2.6)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 6.4, -6 })), { body, back, backMirror }, BLUE)

		pet:seat(0, (topOf(body, -1) + 0.4) / U, -1 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Chameleon (Rare, shelved): taller than a player, its colours shifting in bands from lime through teal to sunset
-- orange, a tall crest down its back, a helmet-shaped casque, turret eyes ringed in light, gripping two-toed feet, and
-- a long tail curled in a spiral.

Jungle.Chameleon = {
	name = "Chameleon",
	skeleton = "LowSlung",
	gait = "Crawl",
	scale = 0.34,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local GREEN = look(80, 196, 98)
		local GREEN_TOP = look(140, 226, 120)
		local GREEN_UNDER = look(44, 130, 70)
		local TEAL = look(46, 170, 186)
		local LIME = look(196, 226, 70)
		local ORANGE = look(250, 140, 52)
		local PINK = look(240, 100, 140)
		local STRIPE = look(250, 244, 220)
		local DARK = rgb(34, 96, 64)
		local IRIS = rgb(255, 214, 70)
		local RING = rgb(120, 255, 200)

		local tones = {
			[GREEN] = { top = GREEN_TOP, under = GREEN_UNDER },
			[TEAL] = { under = look(28, 120, 136) },
			[LIME] = { under = GREEN },
			[ORANGE] = { under = look(200, 100, 40) },
		}
		-- A panther chameleon's colours: green flanks crossed by broad bars that shift from orange at the front
		-- through pink to teal behind, a lime back, and a pale stripe low along each side.
		local LIPS = look(40, 70, 50)
		local function skin(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.55 then
				return STRIPE
			end
			if math.abs(p[2] - 8.4 + p[3] * 0.08) < 0.6 and math.abs(n[1]) > 0.5 then
				return STRIPE
			end
			if n[2] > 0.6 then
				return LIME
			end
			local bar = (p[3] + 0.4 * p[2] + 40) % 4.4
			if bar < 1.6 and math.abs(n[1]) > 0.3 then
				return if p[3] > 3 then ORANGE elseif p[3] > -3 then PINK else TEAL
			end
			return nil
		end

		-- A tall, narrow body, a crest of scales down its back.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 10.6, 0 }, { 3.2, 5.4, 8 }), GREEN)
		body:add(ellipsoid({ 0, 12.6, 1 }, { 2.4, 4.4, 6 }), GREEN)
		body:coat(skin)
		body:bake(tones)
		-- The head: a long jaw and a tall helmet (casque) sweeping back.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 12.4, 9.2 }, { 2.8, 3, 3.6 }), GREEN)
		head:add(rod({ { 0, 12, 10, 2.2 }, { 0, 11.4, 13.4, 1.3 } }), GREEN)
		head:add(rod({ { 0, 14, 9.6, 1.6 }, { 0, 16.6, 7, 1.1 }, { 0, 16.2, 5.4, 0.7 } }), GREEN)
		head:coat(function(p, open, n)
			if p[3] > 10.4 and math.abs(p[2] - 11.2 + (p[3] - 10.4) * 0.1) < 0.35 then
				return LIPS
			end
			return skin(p, open, n)
		end)
		head:bake(tones)

		-- Thin legs bent at the elbow, standing tall.
		local front, back = newSculpt(U), newSculpt(U)
		front:add(rod({ { 2.4, 9, 5, 1.4 }, { 4.2, 5.2, 6.6, 1.1 }, { 4.2, 1.6, 8, 0.9 } }), GREEN)
		back:add(rod({ { 2.4, 9, -5, 1.6 }, { 4.4, 5.6, -7.6, 1.1 }, { 4.2, 1.6, -6.4, 0.9 } }), GREEN)
		for _, s in { front, back } do
			s:coat(skin)
			s:bake(tones)
		end

		-- The tail runs back and down, then curls up in a spiral.
		local spine = Kit.andThen(
			{ { 0, 10, -7, 2 }, { 0, 8, -11, 1.5 }, { 0, 5.4, -13.4, 1.2 } },
			Kit.curl({
				centre = { 0, 5.4, -10.6 },
				plane = { 3, 2 },
				from = math.pi,
				turns = 1.1,
				radius = { 2.8, 0.8 },
				width = { 1.2, 0.5 },
			})
		)
		local tail = newSculpt(U)
		tail:add(rod(spine), GREEN)
		tail:coat(skin)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 10, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, GREEN)
		-- A sawtooth crest of scales down the spine (leaving a gap where the rider sits).
		for _, z in { 6.4, 5, 3.6, -3, -4.6, -6 } do
			local y = topOf(body, z)
			T.taper(bodyLimb, { 0, y - 0.6, z + 0.5 }, { 0, y + 1.2, z - 0.3 }, 1, 0.5, { 1, 0, 0 }, DARK)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 12, 7 }))
		head:draw(headLimb, { body }, GREEN)
		-- Turret eyes: cones of scaly skin, a ring of light, a gold eye with a pinpoint pupil, each looking its own way.
		for _, s in { 1, -1 } do
			local x = sideOf(head, 13, 9.8)
			local c = { (x + 0.2) * s, 13, 9.8 }
			T.ball(headLimb, c, { 2.2, 2.4, 2.4 }, GREEN.color)
			T.ball(headLimb, vadd(c, { 0.8 * s, 0, 0.3 }), { 1.2, 1.6, 1.6 }, RING, NEON)
			T.ball(headLimb, vadd(c, { 1 * s, 0, 0.4 }), { 1, 1.2, 1.2 }, IRIS)
			T.ball(headLimb, vadd(c, { 1.3 * s, 0, 0.5 }), { 0.5, 0.5, 0.5 }, rgb(20, 20, 20))
		end

		-- Two-toed gripping feet: a pair of toes forward, a pair back.
		local function grip(limb: Limb, foot: Vec)
			for _, dz in { 1.4, -1.2 } do
				T.taper(limb, foot, vadd(foot, { 0.4, -1.1, dz }), 1, 0.7, { 0, 1, 0 }, GREEN.color)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 2.4, 9, 5 }), function(limb)
			front:draw(limb, { body }, GREEN)
			grip(limb, { 4.2, 1.4, 8 })
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 2.4, 9, -5 }), function(limb)
			back:draw(limb, { body }, GREEN)
			grip(limb, { 4.2, 1.4, -6.4 })
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 10, -7 })), { body }, GREEN)

		pet:seat(0, (topOf(body, 0.6) + 0.4) / U, 0.6 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Giant Leafcutter Ant (Rare): a rust-red ant taller than a player, glossy, spines on its back, big jagged
-- mandibles holding up a great green leaf twice its height, a tiny ant riding on the leaf, and long elbowed
-- antennae.

Jungle.GiantLeafcutterAnt = {
	name = "Giant Leafcutter Ant",
	skeleton = "ManyLegged",
	scale = 0.3,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local RUST = look(172, 70, 36)
		local RUST_TOP = look(214, 112, 64)
		local RUST_UNDER = look(100, 38, 22)
		local DARK = look(92, 34, 22)
		local SHINE_LOOK = look(232, 150, 96)
		local LEAF = rgb(92, 180, 70)
		local LEAF_DARK = rgb(54, 128, 52)
		local VEIN = rgb(170, 230, 120)
		local JOINT = rgb(120, 46, 26)

		local tones = {
			[RUST] = { top = RUST_TOP, under = RUST_UNDER },
		}
		-- Glossy: a highlight on top, dark where the plates meet.
		local function shell(p: Vec, _: any, n: Vec): Look?
			if n[2] > 0.75 and noise(p) < 0.25 then
				return SHINE_LOOK
			end
			return nil
		end

		-- The thorax (with its waist), the head, and the big round abdomen behind.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 9, 1.6 }, { 2.8, 2.8, 4.2 }), RUST)
		body:add(rod({ { 0, 8.6, -2, 1.3 }, { 0, 8.8, -3.6, 1.1 } }), DARK)
		body:coat(shell)
		body:bake(tones)
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 10.6, 7 }, { 3.6, 3.2, 3 }), RUST)
		head:coat(shell)
		head:bake(tones)
		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 9.4, -8.2 }, { 4, 3.8, 5 }), RUST)
		tail:coat(function(p, open, n)
			if math.abs((p[3] + 8.2) % 2.6 - 1.3) < 0.3 and n[2] > -0.2 then
				return DARK
			end
			return shell(p, open, n)
		end)
		tail:bake(tones)

		local bodyLimb = pet:limb("Body", T.at({ 0, 9, 0 }))
		body:draw(bodyLimb, { head, tail }, RUST)
		-- Spines on its back.
		for _, s in { 1, -1 } do
			T.taper(bodyLimb, { 1.2 * s, 11, 3.6 }, { 2.2 * s, 13, 4.4 }, 0.8, 0.8, { 0, 0, 1 }, DARK.color)
			T.taper(bodyLimb, { 1 * s, 11, -0.6 }, { 1.8 * s, 12.6, -1.2 }, 0.7, 0.7, { 0, 0, 1 }, DARK.color)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 10, 5 }))
		head:draw(headLimb, { body }, RUST)
		glossyEye(headLimb, T, head, 11.4, 7.6, 1.3, nil, rgb(30, 18, 14), nil)
		for _, s in { 1, -1 } do
			-- Jagged mandibles closing on the leaf's stem.
			local root = { 1.6 * s, 9.2, 9.4 }
			local tip = { 0.4 * s, 9.4, 12.4 }
			T.blade(headLimb, root, tip, 1, 0.9, { 0, 1, 0 }, DARK.color)
			for k = 1, 2 do
				local q = vlerp(root, tip, k / 3)
				T.taper(headLimb, q, vadd(q, { -0.6 * s, 0, 0.4 }), 0.4, 0.4, { 0, 1, 0 }, DARK.color)
			end
			-- Long elbowed antennae.
			local a1, a2, a3 = { 1 * s, 12.6, 8.6 }, { 2.4 * s, 16, 9 }, { 3.8 * s, 16.6, 12.4 }
			T.blade(headLimb, a1, a2, 0.5, 0.5, { 0, 0, 1 }, DARK.color)
			T.ball(headLimb, a2, 0.7, JOINT)
			T.taper(headLimb, a2, a3, 0.5, 0.5, { 0, 0, 1 }, DARK.color)
		end
		-- The leaf, held up by its stem: a broad oval of two halves either side of a pale midrib, a bite out of one
		-- edge, and a tiny ant riding on it.
		local stem, tipLeaf = { 0, 9.6, 12 }, { 0, 30, 6 }
		T.blade(headLimb, stem, { 0, 13, 11 }, 0.6, 0.6, { 1, 0, 0 }, LEAF_DARK)
		local spineLeaf = { { 0, 13, 11 }, { 0, 18, 9.6 }, { 0, 23.6, 8.2 }, { 0, 28, 6.8 }, tipLeaf }
		local widths = { 4.6, 6.4, 5.6, 3 }
		for i = 1, #spineLeaf - 1 do
			local a, b = spineLeaf[i], spineLeaf[i + 1]
			local wa = widths[i - 1] or 0.8
			local wb = widths[i]
			for _, s in { 1, -1 } do
				local ea = vadd(a, { wa * s, 0, -0.2 * wa })
				local eb = vadd(b, { wb * s, 0, -0.2 * wb })
				local color = if s > 0 then LEAF else LEAF_DARK
				T.triangle(headLimb, a, b, eb, 0.4, color)
				T.triangle(headLimb, a, eb, ea, 0.4, color)
			end
			T.blade(headLimb, a, b, 0.5, 0.6, { 0, 0, 1 }, VEIN)
		end
		-- The tiny rider, partway up the leaf.
		T.ball(headLimb, { 0.6, 22, 8.9 }, { 0.8, 0.8, 1.2 }, RUST.color)
		T.ball(headLimb, { 0.6, 22.4, 9.8 }, { 0.7, 0.7, 0.7 }, RUST.color)

		-- Three pairs of jointed legs.
		local function legs(left: string, right: string, z: number, dz: number)
			pet:limbPair(left, right, T.at({ 2.2, 8.6, z }), function(limb)
				insectLeg(limb, T, {
					{ 2, 8.6, z },
					{ 6, 11.6, z + dz },
					{ 8.4, 4, z + dz * 1.5 },
					{ 9, 0, z + dz * 1.8 },
				}, { 1.1, 0.9, 0.7 }, RUST.color, JOINT)
			end)
		end
		legs("FrontLeftLeg", "FrontRightLeg", 3.6, 2.4)
		legs("MiddleLeftLeg", "MiddleRightLeg", 1, 0)
		legs("BackLeftLeg", "BackRightLeg", -1.4, -2.4)

		tail:draw(pet:limb("Tail", T.at({ 0, 9, -3.6 })), { body }, RUST)

		pet:seat(0, (topOf(tail, -7) + 0.3) / U, -7 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Giant Centipede (Epic): a centipede twice a player's length, its head raised: a long body of dark plates edged
-- in red, a pair of bright orange legs on every plate, long antennae, big venom claws with glowing tips, and a
-- forked tail. A ripple runs down it as it crawls.

Jungle.GiantCentipede = {
	name = "Giant Centipede",
	skeleton = "Serpent",
	gait = "Crawl",
	scale = 0.36 * 1.2,
	draw = function(pet)
		-- Built in cells 1.2 design units across.
		local U = 1.2
		local T = inUnits(U)
		local PLATE = look(66, 30, 34)
		local PLATE_TOP = look(104, 48, 54)
		local PLATE_UNDER = look(36, 16, 18)
		local EDGE = look(206, 58, 38)
		local BELLY = look(232, 150, 70)
		local LEG = rgb(255, 150, 40)
		local LEG_TIP = rgb(255, 214, 90)
		local VENOM = rgb(150, 255, 90)

		local tones = {
			[PLATE] = { top = PLATE_TOP, under = PLATE_UNDER },
		}
		-- A plate every 2.6 units, each edged in red at its back; a pale orange belly.
		local function plates(s: Sculpt)
			s:coat(function(p, _, n)
				if n[2] < -0.5 then
					return BELLY
				end
				if (p[3] + 100) % 2.6 < 0.65 then
					return EDGE
				end
				return nil
			end)
			s:bake(tones)
		end

		-- The body winds back over the ground in an S; the front lifts the head.
		local paths = {
			{ { 0, 4.4, 2, 2.6 }, { 0.6, 4, -4, 2.8 }, { 2.4, 3, -10, 2.8 } },
			{ { 2.4, 3, -10, 2.8 }, { 4, 3, -16, 2.7 }, { 3, 3, -22, 2.6 } },
			{ { 3, 3, -22, 2.6 }, { 0, 3, -28, 2.4 }, { -2.6, 3, -33, 2.2 } },
			{ { -2.6, 3, -33, 2.2 }, { -3.6, 2.8, -38, 1.8 }, { -3, 2.6, -42, 1.4 } },
		}
		local sculpts = lengths(U, paths, PLATE, function(s)
			plates(s)
		end)
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 6.6, 6 }, { 3, 1.8, 3.2 }), PLATE)
		head:add(rod({ { 0, 4.6, 2.4, 2.4 }, { 0, 6, 5, 2.2 } }), PLATE)
		plates(head)
		local all = { head, sculpts[1], sculpts[2], sculpts[3], sculpts[4] }

		-- Legs along a length: a pair on every plate, arching out and down to the ground.
		local function legsAlong(limb: Limb, path: { { number } }, from: number)
			for i, sample in alongPath(path, 2.6) do
				if i >= from then
					local c, r, dir = sample[1], sample[2], sample[3]
					local side = vnorm({ dir[3], 0, -dir[1] })
					for _, s in { 1, -1 } do
						local out = vscale(side, s)
						local hip = vadd(c, vscale(out, r * 0.7))
						local knee = vadd(vadd(c, vscale(out, r + 2.4)), { 0, 1.4, 0 })
						local foot = vadd(vadd(c, vscale(out, r + 3.6)), { 0, -c[2] + 0.2, 0 })
						T.blade(limb, hip, knee, 0.7, 0.6, { 0, 1, 0 }, LEG)
						T.taper(limb, knee, foot, 0.6, 0.5, { 0, 1, 0 }, LEG_TIP)
					end
				end
			end
		end

		local bodyLimb = pet:limb("Body", T.at({ 0, 4.4, 2 }))
		sculpts[1]:draw(bodyLimb, others(all, sculpts[1]), PLATE)
		legsAlong(bodyLimb, paths[1], 2)
		local segment1 = pet:limb("Segment1", T.at({ 2.4, 3, -10 }))
		sculpts[2]:draw(segment1, others(all, sculpts[2]), PLATE)
		legsAlong(segment1, paths[2], 2)
		local segment2 = pet:limb("Segment2", T.at({ 3, 3, -22 }), "Segment1")
		sculpts[3]:draw(segment2, others(all, sculpts[3]), PLATE)
		legsAlong(segment2, paths[3], 2)
		local tailLimb = pet:limb("Tail", T.at({ -2.6, 3, -33 }), "Segment2")
		sculpts[4]:draw(tailLimb, others(all, sculpts[4]), PLATE)
		legsAlong(tailLimb, paths[4], 2)
		-- The forked tail: two long trailing legs.
		for _, s in { 1, -1 } do
			T.blade(tailLimb, { -3, 2.8, -41.6 }, { -3 + 1.6 * s, 3.4, -46 }, 0.6, 0.6, { 0, 1, 0 }, LEG)
			T.taper(tailLimb, { -3 + 1.6 * s, 3.4, -46 }, { -3 + 2.4 * s, 3, -49 }, 0.5, 0.5, { 0, 1, 0 }, LEG_TIP)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 4.6, 2.4 }))
		head:draw(headLimb, others(all, head), PLATE)
		for _, s in { 1, -1 } do
			-- A cluster of small glowing eyes, and long antennae sweeping forward and up.
			T.ball(headLimb, { 2 * s, 7.4, 7.4 }, 0.8, VENOM, NEON)
			T.ball(headLimb, { 2.4 * s, 7.2, 6.6 }, 0.6, VENOM, NEON)
			T.branch(
				headLimb,
				{ { 1 * s, 7.6, 8.4 }, { 3 * s, 10.4, 12 }, { 5.4 * s, 12, 15 }, { 7 * s, 11.6, 18 } },
				0.6,
				{ 0, 0, 1 },
				LEG
			)
		end

		-- The venom claws (the first pair of legs, reaching forward round the head), glowing at the tips.
		pet:limbPair("LeftFin", "RightFin", T.at({ 2, 4.4, 4 }), function(limb)
			T.blade(limb, { 1.8, 4.4, 4 }, { 3.6, 4.6, 7.4 }, 1, 0.9, { 0, 1, 0 }, LEG)
			T.blade(limb, { 3.6, 4.6, 7.4 }, { 2.6, 4.6, 10 }, 0.9, 0.8, { 0, 1, 0 }, LEG)
			T.taper(limb, { 2.6, 4.6, 10 }, { 1.2, 4.4, 11 }, 0.7, 0.6, { 0, 1, 0 }, VENOM, NEON)
		end)

		pet:seat(0, (topOf(sculpts[1], -4) + 0.3) / U, -4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Hercules Beetle (Legendary): a great beetle, a rideable tank three times a player's length: olive-gold wing
-- cases freckled black, a glossy black head and shoulders, a huge black horn sweeping forward over the head and a
-- shorter one curving up to meet it, both tipped in glowing jade, spiny legs with gold hairs, and glowing eyes.

Jungle.HerculesBeetle = {
	name = "Hercules Beetle",
	skeleton = "ManyLegged",
	gait = "Stomp",
	scale = 0.42 * 1.4,
	draw = function(pet)
		-- Built in cells 1.4 design units across.
		local U = 1.4
		local T = inUnits(U)
		local GOLD = look(196, 176, 80)
		local GOLD_TOP = look(214, 194, 100)
		local GOLD_UNDER = look(132, 116, 50)
		local FRECKLE = look(40, 36, 28)
		local BLACK = look(30, 28, 30)
		local BLACK_TOP = look(62, 60, 70)
		local BLACK_UNDER = look(14, 12, 14)
		local JADE = rgb(100, 255, 170)
		local HAIR = rgb(214, 180, 90)
		local JOINT = rgb(50, 46, 46)

		local tones = {
			[GOLD] = { top = GOLD_TOP, under = GOLD_UNDER },
			[BLACK] = { top = BLACK_TOP, under = BLACK_UNDER },
		}
		local function shell(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.3 then
				return BLACK
			end
			if patches(p, 1.6) < 0.2 then
				return FRECKLE
			end
			if math.abs(p[1]) < 0.7 and n[2] > 0.3 then
				return FRECKLE
			end
			return nil
		end

		-- The wing cases (a great rounded dome) and the black shoulder shield in front.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 10, -5 }, { 9, 7.4, 13 }), GOLD)
		body:coat(shell)
		body:add(ellipsoid({ 0, 10.6, 8.6 }, { 7, 6, 5.6 }), BLACK)
		body:bake(tones)
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 8.6, 14 }, { 4.4, 3.6, 3.6 }), BLACK)
		head:bake(tones)
		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 7.6, -17 }, { 6, 4.4, 2.6 }), BLACK)
		tail:bake(tones)

		-- (Every part shares one inside look, so the parts never flicker where they meet.)
		local bodyLimb = pet:limb("Body", T.at({ 0, 10, 0 }))
		body:draw(bodyLimb, { head, tail }, BLACK)
		-- The great horn: up off the shoulder shield and forward over the head, downcurved at the tip, hairy
		-- underneath, glowing jade at its point.
		local horn = { { 0, 15, 9 }, { 0, 19, 14 }, { 0, 20.6, 20 }, { 0, 19.6, 26 }, { 0, 16.6, 30 } }
		T.branch(bodyLimb, horn, 3.4, { 1, 0, 0 }, BLACK.color)
		for k = 2, #horn - 1 do
			T.taper(bodyLimb, vadd(horn[k], { 0, -1, 0 }), vadd(horn[k], { 0, -2.6, 0.6 }), 1, 0.6, { 1, 0, 0 }, HAIR)
		end
		T.ball(bodyLimb, horn[#horn], 1.8, JADE, NEON)

		local headLimb = pet:limb("Head", T.at({ 0, 9, 11 }))
		head:draw(headLimb, { body, tail }, BLACK)
		-- The lower horn curving up from the head to meet the great one.
		local lower = { { 0, 9, 16 }, { 0, 10, 20 }, { 0, 12, 23.6 }, { 0, 14.6, 25.6 } }
		T.branch(headLimb, lower, 2.4, { 1, 0, 0 }, BLACK.color)
		T.ball(headLimb, lower[#lower], 1.4, JADE, NEON)
		for _, s in { 1, -1 } do
			T.ball(headLimb, { 3.4 * s, 9.6, 15.6 }, { 1.4, 1.6, 1.6 }, JADE, NEON)
			-- Short clubbed antennae.
			T.blade(headLimb, { 1.8 * s, 8.6, 16 }, { 4 * s, 8.6, 19 }, 0.5, 0.5, { 0, 1, 0 }, JOINT)
			T.ball(headLimb, { 4.2 * s, 8.7, 19.3 }, { 1, 0.8, 1 }, HAIR)
		end

		-- Six spiny legs: a jointed leg with a row of spines, gold hairs, and a hooked foot.
		local function legs(left: string, right: string, z: number, dz: number)
			pet:limbPair(left, right, T.at({ 5.4, 7.6, z }), function(limb)
				local points = {
					{ 5.2, 7.6, z },
					{ 9.6, 9.4, z + dz },
					{ 11.6, 3.4, z + dz * 1.5 },
					{ 12.2, 0, z + dz * 1.9 },
				}
				insectLeg(limb, T, points, { 2, 1.7, 1.2 }, BLACK.color, JOINT)
				for k = 1, 3 do
					local q = vlerp(points[2], points[3], k / 4)
					T.taper(limb, q, vadd(q, { 1.2, 0.2, 0 }), 0.5, 0.5, { 0, 1, 0 }, HAIR)
				end
			end)
		end
		legs("FrontLeftLeg", "FrontRightLeg", 6, 3)
		legs("MiddleLeftLeg", "MiddleRightLeg", -1, 0)
		legs("BackLeftLeg", "BackRightLeg", -8, -3)

		tail:draw(pet:limb("Tail", T.at({ 0, 8, -15 })), { body, head }, BLACK)

		pet:light(JADE, 1.8, 20)
		pet:particles("Fireflies", rgb(170, 255, 140), 6)
		pet:aura(rgb(100, 240, 150), rgb(250, 230, 140))
		pet:seat(0, (topOf(body, -5) + 0.4) / U, -5 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Morpho Queen (Mythic, shelved): a butterfly with wings spanning six players, brilliant iridescent blue edged in black
-- with white spots, glowing veins running out through them, a velvety dark body, great glossy eyes, a coiled proboscis,
-- and long clubbed antennae with glowing tips. She hovers on slow, deep wingbeats.

Jungle.MorphoQueen = {
	name = "Morpho Queen",
	skeleton = "Winged",
	gait = "Walk",
	scale = 0.42 * 1.6,
	draw = function(pet)
		-- Built in cells 1.6 design units across.
		local U = 1.6
		local T = inUnits(U)
		local VELVET = look(30, 34, 70)
		local VELVET_TOP = look(54, 62, 120)
		local VELVET_UNDER = look(16, 18, 40)
		local FUZZ = rgb(70, 90, 170)
		local BLACK = rgb(16, 18, 34)
		local BLUE = rgb(40, 130, 255)
		local SKY = rgb(120, 206, 255)
		local WHITE = rgb(246, 248, 255)
		local VEIN = rgb(130, 236, 255)
		local EYEBALL = rgb(24, 30, 60)
		local LEG = rgb(40, 44, 80)
		local UNDERSIDE = rgb(126, 92, 64)
		local EYESPOT = rgb(240, 196, 90)

		local tones = {
			[VELVET] = { top = VELVET_TOP, under = VELVET_UNDER },
		}
		-- A furry thorax and a long tapering abdomen behind it.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 14, 2 }, { 3, 3, 3.8 }), VELVET)
		body:bake(tones)
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 15, 6.6 }, { 2.4, 2.4, 2.2 }), VELVET)
		head:bake(tones)
		local tail = newSculpt(U)
		tail:add(rod({ { 0, 13.6, -1, 2.6 }, { 0, 12.8, -7, 2 }, { 0, 12, -12, 1 } }), VELVET)
		local BAND = look(60, 80, 160)
		tail:coat(function(p, _, n)
			if (p[3] + 40) % 2 < 0.6 and n[2] > -0.3 then
				return BAND
			end
			return nil
		end)
		tail:bake(tones)

		local bodyLimb = pet:limb("Body", T.at({ 0, 14, 0 }))
		body:draw(bodyLimb, { head, tail }, VELVET)
		Kit.fur(
			bodyLimb,
			T,
			body,
			function(p: Vec, n: Vec): boolean
				return n[2] > -0.2 and noise(p) < 0.35
			end,
			1.4,
			0.7,
			{ 0, 0.2, -0.6 },
			function(): { number }
				return FUZZ
			end
		)

		local headLimb = pet:limb("Head", T.at({ 0, 14.6, 5 }))
		head:draw(headLimb, { body }, VELVET)
		for _, s in { 1, -1 } do
			-- Great glossy compound eyes.
			T.ball(headLimb, { 1.9 * s, 15.6, 7.2 }, { 2.4, 2.6, 2.6 }, EYEBALL)
			T.ball(headLimb, { 2.4 * s, 16.4, 7.8 }, { 0.7, 0.7, 0.7 }, SHINE)
			-- Long antennae ending in glowing clubs.
			local base = { 0.8 * s, 16.8, 7.4 }
			local a1, a2 = { 2.4 * s, 22, 10 }, { 4.4 * s, 26, 11 }
			T.blade(headLimb, base, a1, 0.5, 0.5, { 0, 0, 1 }, BLACK)
			T.blade(headLimb, a1, a2, 0.45, 0.45, { 0, 0, 1 }, BLACK)
			T.ball(headLimb, a2, { 1.2, 1.6, 1.2 }, VEIN, NEON)
		end
		-- The proboscis, coiled up under the head.
		local coil = Kit.curl({
			centre = { 0, 12.6, 8.4 },
			plane = { 3, 2 },
			from = math.pi / 2,
			turns = -1.4,
			radius = { 1.4, 0.4 },
			width = { 0.3, 0.2 },
		})
		for k = 1, #coil - 1 do
			T.blade(headLimb, coil[k], coil[k + 1], 0.4, 0.4, { 1, 0, 0 }, rgb(200, 120, 60))
		end

		-- Six thin legs, three each side, down to the ground.
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 1.6, 12.6, 2 }), function(limb)
			for _, dz in { 2.4, 0, -2.4 } do
				local hip = { 1.6, 12.4, 2 + dz * 0.4 }
				local knee = { 5, 12.4, 2 + dz * 1.6 }
				local foot = { 6.4, 0, 2 + dz * 2.2 }
				T.blade(limb, hip, knee, 0.6, 0.6, { 0, 1, 0 }, LEG)
				T.ball(limb, knee, 0.8, LEG)
				T.taper(limb, knee, foot, 0.55, 0.55, { 0, 1, 0 }, LEG)
			end
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 13.6, -1 })), { body }, VELVET)

		-- The wings: a forewing and a hindwing, each a fan from the body out to its scalloped edge. Black border
		-- with white spots; inside it, brilliant blue, paler towards the body; glowing veins running out.
		local function fan(limb: Limb, root: Vec, edge: { Vec }, fraction: number, lift: number, color: { number })
			for k = 1, #edge - 1 do
				local a = vadd(vlerp(root, edge[k], fraction), { 0, lift, 0 })
				local b = vadd(vlerp(root, edge[k + 1], fraction), { 0, lift, 0 })
				T.triangle(limb, vadd(root, { 0, lift, 0 }), a, b, 0.4, color)
			end
		end
		pet:limbPair("LeftWing", "RightWing", T.at({ 2.4, 14.6, 2 }), function(wing)
			local foreRoot = { 2.4, 14.8, 3.4 }
			local fore = {
				{ 6, 17, 9 },
				{ 14, 21, 12 },
				{ 24, 25, 11 },
				{ 32, 27.6, 6 },
				{ 35, 27, 0 },
				{ 32, 24.6, -5 },
				{ 22, 19.6, -5 },
				{ 10, 16, -2 },
			}
			local hindRoot = { 2.4, 14, -0.4 }
			local hind = {
				{ 10, 16, -2 },
				{ 22, 18.4, -6 },
				{ 26, 17.6, -12 },
				{ 22, 15.4, -18 },
				{ 13, 13.4, -19 },
				{ 5, 13.2, -11 },
			}
			for _, part in { { foreRoot, fore }, { hindRoot, hind } } do
				local root, edge = part[1], part[2]
				-- Underneath: dusky brown with a row of eyespots.
				fan(wing, root, edge, 0.92, -0.3, UNDERSIDE)
				for k = 2, #edge - 1, 2 do
					local spot = vadd(vlerp(root, edge[k], 0.62), { 0, -0.6, 0 })
					T.ball(wing, spot, { 2.4, 0.4, 2.4 }, EYESPOT)
					T.ball(wing, vadd(spot, { 0, -0.1, 0 }), { 1.2, 0.4, 1.2 }, BLACK)
				end
				fan(wing, root, edge, 1, 0, BLACK)
				fan(wing, root, edge, 0.84, 0.3, BLUE)
				fan(wing, root, edge, 0.42, 0.55, SKY)
				-- White spots in the black border.
				for k = 2, #edge - 1, 2 do
					T.ball(wing, vadd(vlerp(root, edge[k], 0.93), { 0, 0.35, 0 }), { 1.4, 0.4, 1.4 }, WHITE)
				end
				-- Glowing veins from the root out towards the edge.
				for k = 1, #edge, 2 do
					T.blade(
						wing,
						vadd(root, { 0, 0.8, 0 }),
						vadd(vlerp(root, edge[k], 0.82), { 0, 0.8, 0 }),
						0.35,
						0.3,
						{ 0, 1, 0 },
						VEIN,
						NEON
					)
				end
			end
		end)

		pet:light(VEIN, 2.6, 26)
		pet:particles("Sparkles", rgb(170, 230, 255), 14)
		pet:aura(rgb(70, 160, 255), rgb(190, 240, 255))
		pet:seat(0, (topOf(body, 1) + 0.4) / U, 1 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Titan Anaconda (Mythic): an ancient anaconda, coiled in a great pile five times a player's height to the head it
-- rears: olive scales with big black rings and side spots, a pale banded belly, moss and ferns grown over its back
-- with glowing flowers, a broad heavy head with an orange stripe behind each glowing eye, and a flicking forked
-- tongue.

Jungle.TitanAnaconda = {
	name = "Titan Anaconda",
	skeleton = "Snake",
	gait = "Slither",
	scale = 0.42 * 2,
	draw = function(pet)
		-- Built in cells 2 design units across.
		local U = 2
		local T = inUnits(U)
		local OLIVE = look(110, 124, 56)
		local OLIVE_TOP = look(146, 160, 80)
		local OLIVE_UNDER = look(64, 74, 34)
		local RING = look(30, 32, 24)
		local SPOT = look(214, 170, 60)
		local BELLY = look(226, 210, 136)
		local BELLY_DARK = look(192, 172, 104)
		local MOSS = look(70, 140, 60)
		local MOSS_TOP = look(110, 180, 80)
		local STRIPE = look(236, 140, 50)
		local IRIS = rgb(255, 190, 40)
		local TONGUE = rgb(214, 40, 56)
		local FERN = rgb(70, 150, 60)
		local GLOW = rgb(255, 200, 90)

		local tones = {
			[OLIVE] = { top = OLIVE_TOP, under = OLIVE_UNDER },
			[MOSS] = { top = MOSS_TOP },
		}
		-- Big black rings over the back (each with an olive middle), gold-ringed spots low on the sides, a pale
		-- banded belly, and moss on top.
		local function scales(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.5 then
				return if math.floor(p[3] / 2.4 + p[1] / 2.4) % 2 == 0 then BELLY else BELLY_DARK
			end
			if n[2] > 0.55 and patches(p, 3) > 0.62 then
				return MOSS
			end
			local cell = Kit.cracks(p, 7, 1.4)
			if cell and n[2] > -0.1 then
				return RING
			end
			if n[2] > -0.45 and n[2] < -0.05 and patches(p, 2) < 0.22 then
				return SPOT
			end
			return nil
		end

		-- A great coiled pile: the neck rears from the front, the coils loop round behind, the tail tucked beside.
		local paths = {
			{ { 0, 6.2, -4, 6.2 }, { 0, 7, 4, 6 }, { 0, 14, 10, 5.6 }, { 0, 24, 13, 5 }, { 0, 31, 15, 4.6 } },
			{ { 0, 6.2, -4, 6.2 }, { -9, 6.2, -9, 6.2 }, { -13, 6.2, -19, 6 }, { -7, 6.2, -28, 6 } },
			{ { -7, 6.2, -28, 6 }, { 5, 6, -30, 5.6 }, { 12, 6, -22, 5.4 }, { 11, 5.6, -12, 5 } },
			{ { 11, 5.6, -12, 5 }, { 15, 4.8, -4, 4 }, { 19, 3.6, 2, 2.8 }, { 20, 2.6, 8, 1.6 } },
		}
		local sculpts = lengths(U, paths, OLIVE, function(s)
			s:coat(scales)
			s:bake(tones)
		end)
		-- The head: broad and heavy, the snout blunt, the jaw closed, an orange stripe back from each eye.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 33, 19 }, { 5, 3.4, 6.4 }), OLIVE)
		head:add(rod({ { 0, 33, 22, 3.6 }, { 0, 32.4, 27, 2.6 } }), OLIVE)
		head:coat(function(p, open, n)
			if math.abs(p[2] - 33.6 + (p[3] - 21) * 0.06) < 0.5 and math.abs(n[1]) > 0.5 and p[3] < 22 then
				return STRIPE
			end
			if p[3] > 20 and math.abs(p[2] - 31.4) < 0.35 and math.abs(n[1]) > 0.4 then
				return RING
			end
			return scales(p, open, n)
		end)
		head:bake(tones)
		local all = { head, sculpts[1], sculpts[2], sculpts[3], sculpts[4] }

		-- Ferns and glowing flowers in the moss on its coils.
		local function garden(limb: Limb, s: Sculpt, path: { { number } })
			for _, spot in
				s:surface(function(p: Vec, n: Vec): boolean
					local d = Kit.nearPath(path, p)
					return n[2] > 0.7 and d < 99 and noise(vadd(p, { 4, 4, 4 })) < 0.05
				end)
			do
				local p = spot[1]
				if math.abs(p[3] + 4) < 5 and math.abs(p[1]) < 5 then
					continue
				end
				if noise(p) < 0.4 then
					T.ball(limb, vadd(p, { 0, 0.6, 0 }), { 1.4, 1, 1.4 }, GLOW, NEON)
				else
					for k = 0, 4 do
						local a = k * 1.26 + noise(p) * 6
						T.taper(
							limb,
							p,
							vadd(p, { math.cos(a) * 2.6, 2.4, math.sin(a) * 2.6 }),
							1,
							0.4,
							{ 0, 1, 0 },
							FERN
						)
					end
				end
			end
		end

		local bodyLimb = pet:limb("Body", T.at({ 0, 6.2, -4 }))
		sculpts[1]:draw(bodyLimb, others(all, sculpts[1]), OLIVE)
		garden(bodyLimb, sculpts[1], paths[1])
		local segment1 = pet:limb("Segment1", T.at({ 0, 6.2, -4 }))
		sculpts[2]:draw(segment1, others(all, sculpts[2]), OLIVE)
		garden(segment1, sculpts[2], paths[2])
		local segment2 = pet:limb("Segment2", T.at({ -7, 6.2, -28 }), "Segment1")
		sculpts[3]:draw(segment2, others(all, sculpts[3]), OLIVE)
		garden(segment2, sculpts[3], paths[3])
		local tailLimb = pet:limb("Tail", T.at({ 11, 5.6, -12 }), "Segment2")
		sculpts[4]:draw(tailLimb, others(all, sculpts[4]), OLIVE)

		local headLimb = pet:limb("Head", T.at({ 0, 31, 15 }))
		head:draw(headLimb, others(all, head), OLIVE)
		Kit.slitEyes(headLimb, head, { 34.4, 23.4 }, { 34.6, 20.6 }, 1.3, IRIS, NEON, rgb(24, 26, 18))
		-- A forked tongue flicking out.
		T.blade(headLimb, { 0, 31.8, 25 }, { 0, 31.6, 32 }, 0.5, 0.4, { 0, 1, 0 }, TONGUE)
		for _, s in { 1, -1 } do
			T.taper(headLimb, { 0, 31.6, 32 }, { 0.9 * s, 31.4, 33.6 }, 0.45, 0.35, { 0, 1, 0 }, TONGUE)
		end

		-- Clumps of moss and leaves on its neck, stirring as it moves (the Snake skeleton's fins).
		pet:limbPair("LeftFin", "RightFin", T.at({ 4, 16, 10 }), function(limb)
			T.ball(limb, { 4, 16, 10 }, { 2.6, 2, 2.6 }, MOSS.color)
			for k = 0, 2 do
				local a = k * 0.9
				T.taper(
					limb,
					{ 4.4, 16.4, 10 },
					{ 6.4 + math.cos(a), 18 + k * 0.4, 10 + math.sin(a) * 2 },
					1,
					0.4,
					{ 0, 1, 0 },
					FERN
				)
			end
		end)

		pet:light(GLOW, 2.6, 30)
		pet:particles("Fireflies", rgb(255, 220, 120), 12)
		pet:aura(rgb(160, 220, 80), rgb(255, 230, 140))
		pet:seat(0, (topOf(sculpts[1], -4) + 0.4) / U, -4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Silverback King (Secret, shelved): a colossal gorilla, six times a player's height: near-black fur with a silver
-- saddle down its broad back, a dark bare chest and face under a heavy brow and tall crest, glowing jade war paint, a
-- crown of gold set with glowing jade and ringed with leaves and orchids, gold bands on its huge arms, and great
-- knuckled fists. Its knees and elbows bend as it walks.

Jungle.SilverbackKing = {
	name = "Silverback King",
	skeleton = "Giant",
	gait = "Stomp",
	scale = 0.42 * 2.4,
	draw = function(pet)
		-- Built in cells 2.4 design units across (about a stud each, at its size).
		local U = 2.4
		local T = inUnits(U)
		local FUR = look(52, 48, 58)
		local FUR_TOP = look(98, 94, 108)
		local FUR_UNDER = look(28, 26, 32)
		local SILVER = look(184, 186, 196)
		local SILVER_TOP = look(222, 224, 232)
		local SKIN = look(104, 92, 100)
		local SKIN_TOP = look(136, 124, 132)
		local WARPAINT = look(100, 255, 170, NEON)
		local CHESTPAINT = look(90, 210, 150)
		local MOUTH = look(30, 20, 24)
		local GOLD = rgb(246, 196, 62)
		local GOLD_DARK = rgb(196, 140, 40)
		local JADE = rgb(100, 255, 170)
		local LEAF = rgb(70, 160, 70)
		local ORCHID = rgb(250, 140, 210)
		local HAIR = rgb(26, 24, 30)
		local NAIL = rgb(40, 36, 36)

		local tones = {
			[FUR] = { top = FUR_TOP, under = FUR_UNDER },
			[SILVER] = { top = SILVER_TOP, under = FUR },
			[SKIN] = { top = SKIN_TOP },
		}
		-- The silver saddle over the back and hips.
		local function coat(p: Vec, _: any, n: Vec): Look?
			if n[3] < -0.2 and p[2] > 24 and p[2] < 52 and math.abs(p[1]) < 12 then
				return SILVER
			end
			return nil
		end

		-- A huge barrel of a chest and shoulders, a hunched back, narrower hips.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 44, 4 }, { 16, 14, 12 }), FUR)
		body:add(ellipsoid({ 0, 50, -3 }, { 14, 10, 10 }), FUR)
		body:add(ellipsoid({ 0, 33, 2 }, { 12, 11, 10 }), FUR)
		body:add(ellipsoid({ 0, 26, 0 }, { 11, 7, 9 }), FUR)
		body:coat(function(p, open, n)
			-- The bare chest.
			if n[3] > 0.5 and p[2] > 36 and p[2] < 50 and math.abs(p[1]) < 11 then
				local mark = math.abs(math.abs(p[1]) - 5.6) < 0.9 and p[2] > 41 and p[2] < 47
				return if mark then CHESTPAINT else SKIN
			end
			return coat(p, open, n)
		end)
		body:bake(tones)

		-- The head: a tall crest, a heavy brow, a broad muzzle; the face bare and dark, war paint on the cheeks.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 60, 9 }, { 7, 8, 7 }), FUR)
		head:add(ellipsoid({ 0, 66, 5 }, { 3, 5, 5 }), FUR)
		head:add(ellipsoid({ 0, 62.4, 14.4 }, { 6.6, 1.8, 2.4 }), SKIN)
		head:add(ellipsoid({ 0, 56, 14.6 }, { 5, 4, 3.6 }), SKIN)
		head:coat(function(p, _, n)
			if n[3] > 0.3 and p[2] < 63 and p[2] > 51 and math.abs(p[1]) < 6 then
				if math.abs(p[2] - 54.4) < 0.5 and math.abs(p[1]) < 3 then
					return MOUTH
				end
				if math.abs(math.abs(p[1]) - 4.4) < 0.8 and p[2] > 56 and p[2] < 60 then
					return WARPAINT
				end
				return SKIN
			end
			return nil
		end)
		head:bake(tones)

		-- Arms: huge upper arms, forearms thicker still, knuckled fists; legs short and thick.
		local arm, forearm = newSculpt(U), newSculpt(U)
		arm:add(ellipsoid({ 15, 50, 4 }, { 7, 7, 7 }), FUR)
		arm:add(rod({ { 16, 46, 5, 6.2 }, { 20, 34, 8, 5.2 } }), FUR)
		forearm:add(rod({ { 20, 34, 8, 5.4 }, { 21.4, 22, 11, 6 }, { 21.6, 14, 12, 5 } }), FUR)
		forearm:add(ellipsoid({ 21.6, 9, 13 }, { 5.4, 5, 5.6 }), SKIN)
		local leg, shin = newSculpt(U), newSculpt(U)
		leg:add(rod({ { 7, 26, 0, 7 }, { 9, 15, 2, 6 } }), FUR)
		shin:add(rod({ { 9, 15, 2, 5.8 }, { 9.4, 5, 1, 5 } }), FUR)
		shin:add(ellipsoid({ 9.6, 2.6, 4.4 }, { 5.4, 2.6, 7.4 }), SKIN)
		for _, s in { arm, forearm, leg, shin } do
			s:coat(coat)
			s:bake(tones)
		end

		local armMirror, legMirror = arm:mirror(), leg:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 26, 0 }))
		body:draw(bodyLimb, { head, arm, armMirror, leg, legMirror }, FUR)
		-- Shaggy tufts over its shoulders and back.
		Kit.fur(
			bodyLimb,
			T,
			body,
			function(p: Vec, n: Vec): boolean
				return n[2] > 0.2 and n[3] < 0.4 and p[2] > 48 and noise(p) < 0.3
			end,
			3,
			1.6,
			{ 0, -0.3, -0.6 },
			function(): { number }
				return HAIR
			end
		)
		-- A jade pendant on a gold chain across its chest.
		for k = 0, 6 do
			local a = math.rad(200 + k * 23.3)
			T.ball(bodyLimb, { math.cos(a) * 8, 50 + math.sin(a) * 6, 15.6 - math.abs(math.cos(a)) * 1.6 }, 1.2, GOLD)
		end
		T.ball(bodyLimb, { 0, 43.4, 16.4 }, { 3, 3.6, 1.6 }, GOLD_DARK)
		T.ball(bodyLimb, { 0, 43.4, 17 }, { 2, 2.6, 1.2 }, JADE, NEON)

		local headLimb = pet:limb("Head", T.at({ 0, 54, 8 }))
		head:draw(headLimb, { body }, FUR)
		Kit.glossyEye(headLimb, T, head, 60.4, 14, 1.6, rgb(40, 30, 26), rgb(120, 70, 30), nil, rgb(20, 14, 10))
		for _, s in { 1, -1 } do
			T.ball(headLimb, { 1.4 * s, 56.6, 18.2 }, { 1.2, 0.9, 0.6 }, MOUTH.color)
		end
		-- The crown: a ring of gold round the crest, points rising from it, a glowing jade gem in each, leaves and
		-- orchids woven between them.
		local ring = 8
		for k = 0, ring - 1 do
			local a = k / ring * math.pi * 2
			local c = { math.sin(a) * 6.4, 66, 6 + math.cos(a) * 6 }
			local nxt = { math.sin(a + math.pi * 2 / ring) * 6.4, 66, 6 + math.cos(a + math.pi * 2 / ring) * 6 }
			T.blade(headLimb, c, nxt, 2, 1.4, { 0, 1, 0 }, GOLD)
			T.taper(
				headLimb,
				vadd(c, { 0, 0.6, 0 }),
				vadd(c, { 0, 6.4, 0 }),
				1.8,
				0.8,
				vnorm({ c[1], 0, c[3] - 6 }),
				GOLD
			)
			T.ball(headLimb, vadd(c, { 0, 1.6, 0 }), 1.1, JADE, NEON)
			local mid = vlerp(c, nxt, 0.5)
			T.taper(
				headLimb,
				mid,
				vadd(mid, { math.sin(a) * 1.6, 2.6, math.cos(a) * 1.6 }),
				1.6,
				0.3,
				{ 0, 1, 0 },
				LEAF
			)
			if k % 2 == 0 then
				T.ball(headLimb, vadd(mid, { 0, 1.4, 0 }), { 1.4, 0.9, 1.4 }, ORCHID)
			end
		end

		-- Gold bands on the upper arms, each set with a glowing jade gem; knuckles and nails on the fists.
		pet:limbPair("LeftArm", "RightArm", T.at({ 15, 50, 4 }), function(limb)
			arm:draw(limb, { body, forearm }, FUR)
			for _, t in { 0.35, 0.55 } do
				local c = vlerp({ 16, 46, 5 }, { 20, 34, 8 }, t)
				for k = 0, 7 do
					local a = k / 8 * math.pi * 2
					T.ball(limb, vadd(c, { math.cos(a) * 5.8, 0, math.sin(a) * 5.8 }), { 1.6, 1.4, 1.6 }, GOLD)
				end
			end
			T.ball(limb, vadd(vlerp({ 16, 46, 5 }, { 20, 34, 8 }, 0.45), { 5.4, 0, 1 }), { 1, 1.6, 1.6 }, JADE, NEON)
		end)
		pet:limbPair("LeftForearm", "RightForearm", T.at({ 20, 34, 8 }), function(limb)
			forearm:draw(limb, { arm }, FUR)
			for _, dx in { -2.4, -0.8, 0.8, 2.4 } do
				T.ball(limb, { 21.6 + dx, 7, 17.4 }, { 1.6, 1.8, 1.4 }, SKIN_TOP.color)
				T.ball(limb, { 21.6 + dx, 6, 18 }, { 1, 0.6, 0.6 }, NAIL)
			end
		end, "LeftArm")
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 7, 26, 0 }), function(limb)
			leg:draw(limb, { body, shin }, FUR)
		end)
		pet:limbPair("LeftShin", "RightShin", T.at({ 9, 15, 2 }), function(limb)
			shin:draw(limb, { leg }, FUR)
			for _, dx in { -2.8, -0.9, 0.9, 2.8 } do
				T.ball(limb, { 9.6 + dx, 1.4, 10 }, { 1.8, 1.6, 1.8 }, SKIN_TOP.color)
			end
		end, "LeftLeg")

		pet:light(JADE, 3.4, 40)
		pet:particles("Fireflies", rgb(160, 255, 190), 16)
		pet:aura(rgb(80, 240, 160), rgb(250, 220, 120))
		pet:seat(0, (topOf(body, -4) + 0.4) / U, -4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Titan Beetle (Secret, shelved): a colossal beetle, longer than eight players, carrying a ruined jungle temple on its
-- back: glossy bronze wing cases, a dark saw-edged shield, huge curved mandibles lined with teeth, glowing amber eyes,
-- and on its back a stepped pyramid of mossy stone with a glowing jade doorway, vines trailing down, braziers of green
-- fire at its corners, and a glowing jade gem at its peak.

Jungle.TitanBeetle = {
	name = "Titan Beetle",
	skeleton = "ManyLegged",
	gait = "Stomp",
	scale = 0.5 * 2.4,
	draw = function(pet)
		-- Built in cells 2.4 design units across (well over a stud each, at its size).
		local U = 2.4
		local T = inUnits(U)
		local BRONZE = look(126, 80, 42)
		local BRONZE_TOP = look(176, 120, 66)
		local BRONZE_UNDER = look(70, 42, 22)
		local RIDGE = look(92, 56, 30)
		local DARK = look(46, 32, 24)
		local DARK_TOP = look(84, 62, 46)
		local STONE = rgb(150, 150, 130)
		local STONE_DARK = rgb(112, 114, 98)
		local MOSS = rgb(86, 152, 64)
		local VINE = rgb(52, 120, 54)
		local JADE = rgb(100, 255, 170)
		local AMBER = rgb(255, 170, 40)
		local TOOTH = rgb(236, 220, 190)
		local JOINT = rgb(60, 40, 28)
		local FIRE = rgb(80, 255, 140)
		local FIRE_HOT = rgb(210, 255, 220)

		local tones = {
			[BRONZE] = { top = BRONZE_TOP, under = BRONZE_UNDER },
			[DARK] = { top = DARK_TOP, under = BRONZE_UNDER },
		}
		-- Ridges along the wing cases, split down the middle.
		local function shell(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.4 then
				return DARK
			end
			if math.abs(p[1]) < 1.2 and n[2] > 0.3 then
				return DARK
			end
			if math.abs(p[1]) % 5 < 1 and n[2] > 0 then
				return RIDGE
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 16, -12 }, { 16, 9, 24 }), BRONZE)
		body:coat(shell)
		body:add(ellipsoid({ 0, 17, 15 }, { 14, 8, 7.4 }), DARK)
		body:bake(tones)
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 13, 24 }, { 8, 5.6, 5.4 }), DARK)
		head:bake(tones)
		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 12, -35 }, { 9, 4.6, 3.4 }), DARK)
		tail:bake(tones)

		local bodyLimb = pet:limb("Body", T.at({ 0, 16, 0 }))
		body:draw(bodyLimb, { head, tail }, DARK)
		-- Saw teeth along both sides of the shield.
		for _, s in { 1, -1 } do
			for k = 0, 3 do
				local z = 10 + k * 3.4
				local root = { (sideOf(body, 17, z) - 1) * s, 17, z }
				T.taper(bodyLimb, root, vadd(root, { 3 * s, 0.4, 1 }), 1.8, 1.2, { 0, 1, 0 }, DARK.color)
			end
		end

		-- The temple: two stepped platforms on its back, a stepped tower behind, moss on every ledge, vines down the
		-- sides, a glowing jade doorway, green fire in braziers at the corners, a jade gem at the peak.
		local function slab(
			limb: Limb,
			x: number,
			y0: number,
			y1: number,
			z: number,
			width: number,
			depth: number,
			color: { number }
		)
			T.blade(limb, { x, y0, z }, { x, y1, z }, width, depth, { 0, 0, 1 }, color)
		end
		local deck = topOf(body, -12) - 2
		slab(bodyLimb, 0, deck, deck + 4, -12, 24, 30, STONE_DARK)
		slab(bodyLimb, 0, deck + 4, deck + 4.6, -12, 25, 31, MOSS)
		slab(bodyLimb, 0, deck + 4, deck + 8, -14, 18, 22, STONE)
		slab(bodyLimb, 0, deck + 8, deck + 8.6, -14, 19, 23, MOSS)
		local tower = { { 14, 6 }, { 11, 5 }, { 8, 5 }, { 5.6, 4 } }
		local y = deck + 8
		for i, tier in tower do
			-- (Each tier sinks a little into the one below, so they hold together.)
			slab(bodyLimb, 0, y - 1, y + tier[2], -18, tier[1], tier[1], if i % 2 == 0 then STONE else STONE_DARK)
			slab(bodyLimb, 0, y + tier[2], y + tier[2] + 0.5, -18, tier[1] + 1, tier[1] + 1, MOSS)
			y += tier[2]
		end
		-- The doorway into the tower, glowing.
		T.blade(bodyLimb, { 0, deck + 8.4, -18 + 7.2 }, { 0, deck + 14, -18 + 7.2 }, 4, 0.8, { 0, 0, 1 }, JADE, NEON)
		-- The peak: a shrine roof and a glowing gem.
		T.ball(bodyLimb, { 0, y + 1.6, -18 }, 3.6, JADE, NEON)
		T.taper(bodyLimb, { 0, y + 2.6, -18 }, { 0, y + 6.6, -18 }, 2, 2, { 1, 0, 0 }, AMBER)
		-- Braziers of green fire at the front corners of the upper platform.
		for _, s in { 1, -1 } do
			local brazier = { 7.4 * s, deck + 8.6, -5 }
			slab(bodyLimb, brazier[1], brazier[2] - 1.4, brazier[2] + 2, brazier[3], 2.4, 2.4, STONE_DARK)
			bodyLimb:fire(T.at({ brazier[1], brazier[2] + 3.4, brazier[3] }), 4, FIRE, FIRE_HOT)
			-- Vines hanging over the sides of the platforms.
			for _, z in { -24, -16, -6 } do
				local top = { 12.4 * s, deck + 4.4, z }
				T.blade(bodyLimb, top, vadd(top, { 0.6 * s, -6, 0 }), 0.6, 0.6, { 1, 0, 0 }, VINE)
				T.taper(
					bodyLimb,
					vadd(top, { 0.6 * s, -6, 0 }),
					vadd(top, { 0.4 * s, -9, 0 }),
					0.6,
					0.6,
					{ 1, 0, 0 },
					VINE
				)
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 13, 20 }))
		head:draw(headLimb, { body }, DARK)
		for _, s in { 1, -1 } do
			T.ball(headLimb, { 6 * s, 14.6, 26 }, { 2.6, 2.4, 2.6 }, AMBER, NEON)
			-- The great mandibles: curving forward and in, a row of teeth along the inside.
			local jaw = { { 4.6 * s, 12, 27.6 }, { 9 * s, 12.4, 34 }, { 8 * s, 12.6, 40 }, { 3.6 * s, 12.6, 44 } }
			T.branch(headLimb, jaw, 3.6, { 0, 1, 0 }, DARK_TOP.color)
			for k = 1, 3 do
				local q = vlerp(jaw[2], jaw[3], k / 4)
				T.taper(headLimb, q, vadd(q, { -2.2 * s, 0, 0.4 }), 1, 0.8, { 0, 1, 0 }, TOOTH)
			end
			-- Antennae sweeping back.
			T.branch(headLimb, { { 6 * s, 16, 27 }, { 10 * s, 21, 28 }, { 14 * s, 24, 24 } }, 1, { 0, 0, 1 }, JOINT)
		end

		local function legs(left: string, right: string, z: number, dz: number)
			pet:limbPair(left, right, T.at({ 10, 12, z }), function(limb)
				insectLeg(limb, T, {
					{ 10, 12, z },
					{ 21, 20, z + dz },
					{ 26, 6, z + dz * 1.5 },
					{ 27, 0, z + dz * 1.8 },
				}, { 3.4, 2.8, 2 }, DARK.color, JOINT)
				-- Spines along the shin.
				for k = 1, 3 do
					local q = vlerp({ 21, 20, z + dz }, { 26, 6, z + dz * 1.5 }, k / 4)
					T.taper(limb, q, vadd(q, { 2, 0.6, 0 }), 1, 1, { 0, 1, 0 }, BRONZE.color)
				end
			end)
		end
		legs("FrontLeftLeg", "FrontRightLeg", 10, 5)
		legs("MiddleLeftLeg", "MiddleRightLeg", -4, 0)
		legs("BackLeftLeg", "BackRightLeg", -18, -5)

		tail:draw(pet:limb("Tail", T.at({ 0, 12, -32 })), { body }, DARK)

		pet:light(JADE, 3.6, 46)
		pet:particles("Fireflies", rgb(140, 255, 180), 18)
		pet:aura(rgb(100, 230, 150), rgb(255, 200, 100))
		pet:seat(0, (deck + 8.8) / U, -4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Mantis Empress (Secret): a colossal orchid mantis, seven times a player's height to the top of her crown: a
-- pearl-pink body banded like petals, a broad flower-like abdomen with flared petal edges curling up behind, great
-- petal lobes on her thick banded walking legs, heavy scythe arms raised and folded, gold-braceleted and spined in
-- glowing pink, a wide triangular head with huge green eyes, feathery antennae, a tall gold crown set with gems,
-- and glass wings lifted in a V, glowing veins down them.

Jungle.MantisEmpress = {
	name = "Mantis Empress",
	skeleton = "ManyLegged",
	gait = "Walk",
	scale = 0.5 * 2.4,
	draw = function(pet)
		-- Built in cells 2.4 design units across.
		local U = 2.4
		local T = inUnits(U)
		local PEARL = look(248, 220, 234)
		local PEARL_TOP = look(255, 242, 250)
		local PEARL_UNDER = look(212, 166, 196)
		local PINK = look(240, 146, 200)
		local DEEP = look(204, 84, 158)
		local GREEN = look(150, 214, 120)
		local EYE = rgb(130, 226, 112)
		local PUPIL = rgb(36, 92, 44)
		local GLOW = rgb(255, 110, 205)
		local PETAL = rgb(252, 200, 228)
		local PETAL_DEEP = rgb(226, 104, 176)
		local WING = rgb(255, 196, 234)
		local GOLD = rgb(246, 200, 70)
		local GEM = rgb(120, 255, 200)
		local JOINT = rgb(236, 160, 206)

		local tones = {
			[PEARL] = { top = PEARL_TOP, under = PEARL_UNDER },
			[PINK] = { under = DEEP },
		}
		-- Layered like petals: bands of pink along the body, deeper at their edges.
		local function petals(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.5 then
				return PINK
			end
			local band = (p[3] + p[2] * 0.4 + 60) % 6
			if band < 1.1 then
				return DEEP
			elseif band < 2.6 then
				return PINK
			end
			return nil
		end
		-- A rounded petal lobe off the line from `a` to `b`, reaching `depth` out along `out`: pale, edged in deeper
		-- pink behind it, a glowing vein down its middle.
		local function lobe(limb: Limb, a: Vec, b: Vec, out: Vec, depth: number)
			local steps = 5
			local function rim(t: number, reach: number): Vec
				return vadd(vlerp(a, b, t), vscale(out, depth * reach * math.sin(math.pi * t)))
			end
			for i = 0, steps - 1 do
				local t0, t1 = i / steps, (i + 1) / steps
				local l0, l1 = vlerp(a, b, t0), vlerp(a, b, t1)
				-- (Each end comes to a point on the line: no triangle there.)
				for _, layer in { { 1.18, 0.5, PETAL_DEEP }, { 1, 0.9, PETAL } } do
					local reach, thickness, color = layer[1], layer[2], layer[3]
					if i > 0 then
						T.triangle(limb, l0, rim(t0, reach), rim(t1, reach), thickness, color)
					end
					if i < steps - 1 then
						T.triangle(limb, l0, rim(t1, reach), l1, thickness, color)
					end
				end
			end
			T.blade(limb, vlerp(a, b, 0.5), rim(0.5, 0.9), 0.5, 1.1, vnorm(Kit.vsub(b, a)), GLOW, NEON)
		end

		-- The middle of the body, and the long neck-like front of it raised high.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 21, 0 }, { 7, 6, 10 }), PEARL)
		body:add(rod({ { 0, 23, 7, 4.8 }, { 0, 32, 10, 4.2 }, { 0, 40, 13, 3.8 } }), PEARL)
		body:coat(petals)
		body:bake(tones)
		-- The head: wide and triangular, huge eyes at its corners, its mouth pointing down.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 45, 15 }, { 10, 5.4, 4.4 }), PEARL)
		head:add(rod({ { 0, 44, 16.4, 3.4 }, { 0, 38, 19, 1.8 } }), PEARL)
		head:coat(function(p, _, _)
			if p[2] < 41 then
				return GREEN
			end
			return nil
		end)
		head:bake(tones)
		-- The abdomen: broad and flower-like, curling up behind.
		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 21, -12 }, { 9, 6, 11 }), PEARL)
		tail:add(ellipsoid({ 0, 25, -23 }, { 7.6, 6, 7.6 }), PEARL)
		tail:add(ellipsoid({ 0, 31, -30 }, { 5, 5, 5 }), PEARL)
		tail:add(ellipsoid({ 0, 37, -32 }, { 3, 3.4, 3 }), PEARL)
		tail:coat(petals)
		tail:bake(tones)

		local bodyLimb = pet:limb("Body", T.at({ 0, 21, 0 }))
		body:draw(bodyLimb, { head, tail }, PEARL)

		local headLimb = pet:limb("Head", T.at({ 0, 40, 13 }))
		head:draw(headLimb, { body }, PEARL)
		for _, s in { 1, -1 } do
			-- Huge rounded eyes at the corners of the head, a dark pupil and a glint in each.
			T.ball(headLimb, { 9.6 * s, 46.4, 15 }, { 6, 7, 6 }, EYE)
			T.ball(headLimb, { 10.4 * s, 46.4, 17.4 }, { 1.6, 2, 1.4 }, PUPIL)
			T.ball(headLimb, { 10.8 * s, 48.6, 17.4 }, 1.6, SHINE)
			-- Feathery antennae.
			T.branch(
				headLimb,
				{ { 2.4 * s, 49.6, 17 }, { 6 * s, 58, 21 }, { 11 * s, 63, 19 } },
				0.9,
				{ 0, 0, 1 },
				JOINT
			)
		end
		-- A tall gold crown: a band across the top of the head, seven points with a glowing gem in each, and a great
		-- gem at its front.
		T.blade(headLimb, { -8, 50, 15 }, { 8, 50, 15 }, 2, 2, { 0, 1, 0 }, GOLD)
		for k = -3, 3 do
			local base = { k * 2.4, 50.6, 15 }
			T.taper(headLimb, base, vadd(base, { k * 0.5, 7 - math.abs(k) * 1.4, 0 }), 2.2, 1.2, { 0, 0, 1 }, GOLD)
			T.ball(headLimb, vadd(base, { 0, 1.6, 0.7 }), 1.3, GEM, NEON)
		end
		T.ball(headLimb, { 0, 51.4, 16.4 }, { 2.6, 3, 1.6 }, GEM, NEON)

		-- The scythe arms, raised and folded: a thick spiny upper part with a gold bracelet, the blade folding back
		-- down against it, both spined in glowing pink, a hooked claw at the tip.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.4, 34, 11 }), function(limb)
			local hip, elbow, wrist = { 3.4, 34, 11 }, { 8, 46, 23 }, { 7, 31, 27 }
			T.blade(limb, hip, elbow, 4.4, 3.6, { 1, 0, 0 }, PETAL)
			T.ball(limb, elbow, 4.4, JOINT)
			T.blade(limb, elbow, wrist, 3.4, 2.8, { 1, 0, 0 }, PETAL)
			T.taper(limb, wrist, vadd(wrist, { 0, 3, 4 }), 2.6, 2, { 1, 0, 0 }, PETAL_DEEP)
			T.blade(limb, vlerp(hip, elbow, 0.74), vlerp(hip, elbow, 0.84), 5.2, 4.4, { 1, 0, 0 }, GOLD)
			T.ball(limb, vadd(vlerp(hip, elbow, 0.79), { 0, -0.6, 2.2 }), 1.6, GEM, NEON)
			for k = 1, 6 do
				local q = vlerp(hip, elbow, 0.1 + k * 0.1)
				T.taper(limb, q, vadd(q, { -0.4, -3, 0.8 }), 1.1, 0.8, { 1, 0, 0 }, GLOW, NEON)
				local b = vlerp(elbow, wrist, k * 0.13)
				T.taper(limb, b, vadd(b, { -0.2, 0.6, 2.6 }), 0.9, 0.7, { 1, 0, 0 }, GLOW, NEON)
			end
		end)

		-- Thick walking legs, crouched: banded deeper pink at the knee, a great petal lobe under each upper leg and a
		-- smaller one behind each shin, the foot turned out on a short last joint.
		local function legs(left: string, right: string, z: number, dz: number)
			pet:limbPair(left, right, T.at({ 5, 19, z }), function(limb)
				local hip, knee, ankle, toe =
					{ 5, 19, z }, { 15, 26, z + dz }, { 21, 4.6, z + dz * 1.5 }, { 25, 0.9, z + dz * 1.8 }
				insectLeg(limb, T, { hip, knee, ankle, toe }, { 3.6, 3, 2.2 }, PETAL, JOINT)
				T.blade(limb, vlerp(hip, knee, 0.78), vlerp(hip, knee, 0.88), 4.2, 3.8, { 0, 1, 0 }, PETAL_DEEP)
				T.blade(limb, vlerp(knee, ankle, 0.82), vlerp(knee, ankle, 0.92), 3.4, 3.4, { 0, 1, 0 }, PETAL_DEEP)
				lobe(limb, vlerp(hip, knee, 0.1), vlerp(hip, knee, 0.95), { 0, -1, 0 }, 9)
				lobe(limb, vlerp(knee, ankle, 0.12), vlerp(knee, ankle, 0.7), vnorm({ 0.4, 0.2, -1 }), 3.6)
			end)
		end
		legs("MiddleLeftLeg", "MiddleRightLeg", 2, 3)
		legs("BackLeftLeg", "BackRightLeg", -5, -6)

		local tailLimb = pet:limb("Tail", T.at({ 0, 21, -6 }))
		tail:draw(tailLimb, { body }, PEARL)
		for _, s in { 1, -1 } do
			-- Flared petal edges along each side of the abdomen, in two layers.
			lobe(tailLimb, { 8.4 * s, 21, -4 }, { 7 * s, 22, -22 }, vnorm({ s, -0.35, 0 }), 5)
			lobe(tailLimb, { 6.6 * s, 25, -17 }, { 4.4 * s, 29, -30 }, vnorm({ s, -0.2, 0 }), 4)
			-- Glass wings lifted in a V, glowing veins down them.
			T.triangle(tailLimb, { 1.6 * s, 25.6, -5 }, { 13 * s, 37, -24 }, { 2.4 * s, 32, -30 }, 0.6, WING, GLASS)
			T.blade(tailLimb, { 2 * s, 26.4, -6 }, { 12 * s, 36.4, -23 }, 0.5, 0.9, { 0, 1, 0 }, GLOW, NEON)
			T.blade(tailLimb, { 2 * s, 27.4, -8 }, { 3.6 * s, 32, -28 }, 0.5, 0.9, { 0, 1, 0 }, GLOW, NEON)
		end

		pet:light(GLOW, 3.6, 44)
		pet:particles("Sparkles", rgb(255, 190, 236), 18)
		pet:aura(rgb(255, 120, 210), rgb(255, 230, 245))
		pet:seat(0, (topOf(tail, -12) + 0.4) / U, -12 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Vine Hydra (Eternal): a colossal monster of the jungle grown from roots and vines, seven times a player's height:
-- a great bulb of twisted bark wrapped in vines and moss, glowing seed pods, giant leaves and orchids, a crown of
-- huge red petals; three flytrap heads on thorny vine necks, their jaws edged in white spines and glowing inside,
-- each moving on its own; four root legs that bend at the knee and spread over the ground; and a long thorny tail
-- ending in a glowing bud.

Jungle.VineHydra = {
	name = "Vine Hydra",
	skeleton = "ThreeHeaded",
	gait = "Stomp",
	scale = 0.5 * 2.4,
	draw = function(pet)
		-- Built in cells 2.4 design units across.
		local U = 2.4
		local T = inUnits(U)
		local BARK = look(104, 76, 50)
		local BARK_TOP = look(140, 108, 72)
		local BARK_UNDER = look(64, 46, 30)
		local GROOVE = look(66, 46, 30)
		local VINE = look(62, 140, 58)
		local VINE_TOP = look(96, 176, 76)
		local MOSS = look(88, 156, 64)
		local TRAP = look(112, 196, 70)
		local TRAP_TOP = look(150, 224, 96)
		local TRAP_RED = look(222, 54, 72)
		local POD = rgb(210, 255, 90)
		local NECTAR = rgb(255, 120, 150)
		local SPINE = rgb(250, 248, 230)
		local THORN = rgb(70, 50, 34)
		local LEAF = rgb(66, 150, 62)
		local LEAF_DARK = rgb(42, 108, 48)
		local PETAL = rgb(206, 44, 54)
		local PETAL_SPOT = rgb(250, 230, 220)
		local ORCHID = rgb(250, 150, 220)

		local tones = {
			[BARK] = { top = BARK_TOP, under = BARK_UNDER },
			[VINE] = { top = VINE_TOP, under = look(40, 100, 44) },
			[TRAP] = { top = TRAP_TOP },
		}
		-- Bark twisted in grooves, vines winding round it, moss over the top.
		local function bark(p: Vec, _: any, n: Vec): Look?
			if n[2] > 0.6 and patches(p, 3) > 0.55 then
				return MOSS
			end
			local twist = (math.atan2(p[1], p[3]) * 4 + p[2] * 0.3) % (math.pi * 2)
			if twist < 0.9 then
				return VINE
			elseif twist > 3 and twist < 3.5 then
				return GROOVE
			end
			return nil
		end

		-- The three heads: where each trap sits, which way it gapes, and the vine neck that carries it.
		local heads = {
			{ centre = { 0, 64, 26 }, yaw = 0, neck = { { 0, 31, 8, 5 }, { 0, 46, 12, 4.2 }, { 0, 57, 19, 3.6 } } },
			{
				centre = { 23, 56, 19 },
				yaw = 0.45,
				neck = { { 6, 31, 6, 4.6 }, { 13, 44, 8, 3.8 }, { 19, 51, 14, 3.4 } },
			},
		}
		-- A flytrap: two great lobes hinged at the back, gaping, green outside and red inside; `jawless` leaves the
		-- lower lobe off (the middle head's is its own limb).
		local function trap(s: Sculpt, centre: Vec, yaw: number, jawless: boolean)
			local frame = { origin = centre, yaw = yaw }
			s:add(ellipsoid({ 0, 0, -4 }, { 5.4, 5.4, 5.4 }), TRAP, frame)
			s:add(ellipsoid({ 0, 4, 4 }, { 8, 3.2, 9.4 }), TRAP, frame)
			if not jawless then
				s:add(ellipsoid({ 0, -5.4, 4 }, { 8, 3, 9.4 }), TRAP, frame)
			end
			s:carve(ellipsoid({ 0, -0.8, 5.4 }, { 6.8, 3, 9.4 }), frame)
		end
		local function trapCoat(s: Sculpt)
			s:coat(function(p, _, n)
				for _, h in heads do
					for _, side in { 1, -1 } do
						local c = { h.centre[1] * side, h.centre[2], h.centre[3] }
						local yaw = h.yaw * side
						local x, y, z = Kit.toLocal({ origin = c, yaw = yaw }, p[1], p[2], p[3])
						if z > -1.4 and math.abs(x) < 8.6 and math.abs(y) < 4.6 and math.abs(n[2]) > 0.5 then
							return TRAP_RED
						end
					end
				end
				return nil
			end)
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 24, -2 }, { 17, 12, 19 }), BARK)
		body:add(ellipsoid({ 0, 31, 4 }, { 12, 9, 10 }), BARK)
		body:coat(bark)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(rod(heads[1].neck), VINE)
		trap(head, heads[1].centre, 0, true)
		trapCoat(head)
		head:bake(tones)
		local leftHead = newSculpt(U)
		leftHead:add(rod(heads[2].neck), VINE)
		trap(leftHead, heads[2].centre, heads[2].yaw, false)
		trapCoat(leftHead)
		leftHead:bake(tones)
		local rightHead = leftHead:mirror()
		local jaw = newSculpt(U)
		local jawFrame = { origin = heads[1].centre, yaw = 0 }
		jaw:add(ellipsoid({ 0, -5.4, 4 }, { 8, 3, 9.4 }), TRAP, jawFrame)
		jaw:carve(ellipsoid({ 0, -0.8, 5.4 }, { 6.8, 3, 9.4 }), jawFrame)
		trapCoat(jaw)
		jaw:bake(tones)

		-- Root legs in two halves, bending at the knee, on spreading roots.
		local front, frontShin, back, backShin = newSculpt(U), newSculpt(U), newSculpt(U), newSculpt(U)
		front:add(rod({ { 11, 24, 9, 6.6 }, { 15, 14, 12, 5.8 } }), BARK)
		frontShin:add(rod({ { 15, 14, 12, 5.6 }, { 15, 4, 14, 5 } }), BARK)
		frontShin:add(ellipsoid({ 15, 2.6, 14 }, { 6.6, 2.6, 6.6 }), BARK)
		back:add(rod({ { 11, 22, -12, 7 }, { 15, 13, -8, 5.8 } }), BARK)
		backShin:add(rod({ { 15, 13, -8, 5.6 }, { 15, 4, -14, 5 } }), BARK)
		backShin:add(ellipsoid({ 15, 2.6, -14 }, { 6.6, 2.6, 6.6 }), BARK)
		for _, s in { front, frontShin, back, backShin } do
			s:coat(bark)
			s:bake(tones)
		end

		local spine =
			{ { 0, 22, -19, 5.4 }, { 0, 18, -31, 4.2 }, { 4, 15, -41, 3 }, { 9, 15, -49, 2.2 }, { 12, 19, -55, 1.6 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), VINE)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local all = {
			body,
			head,
			leftHead,
			rightHead,
			jaw,
			front,
			frontMirror,
			frontShin,
			frontShin:mirror(),
			back,
			backMirror,
			backShin,
			backShin:mirror(),
			tail,
		}
		local bodyLimb = pet:limb("Body", T.at({ 0, 26, 0 }))
		body:draw(bodyLimb, others(all, body), BARK)
		-- A crown of huge red petals round the base of the necks, spotted white, and glowing seed pods, giant
		-- leaves and orchids over the bulb (the back left clear for a rider).
		for k = 0, 6 do
			local a = math.rad(-90 + k * 30)
			local root = { math.sin(a) * 8, 39, 6 + math.cos(a) * 6 }
			local tip = vadd(root, { math.sin(a) * 13, 7, math.cos(a) * 10 })
			local side = vnorm({ math.cos(a), 0, -math.sin(a) })
			T.triangle(bodyLimb, vadd(root, vscale(side, 4.4)), vadd(root, vscale(side, -4.4)), tip, 1, PETAL)
			T.ball(bodyLimb, vadd(vlerp(root, tip, 0.5), { 0, 0.4, 0 }), { 2, 0.8, 2 }, PETAL_SPOT)
		end
		for _, spot in
			body:surface(function(p: Vec, n: Vec): boolean
				return n[2] > -0.2 and p[3] < 2 and noise(p) < 0.05 and math.abs(p[3] + 8) + math.abs(p[1]) > 7
			end)
		do
			local p, n = spot[1], spot[2]
			local r = noise(vadd(p, { 3, 3, 3 }))
			if r < 0.4 then
				T.ball(bodyLimb, vadd(p, vscale(n, 0.8)), 2.2, POD, NEON)
			elseif r < 0.75 then
				local tip = vadd(p, vadd(vscale(n, 6), { 0, 3, 0 }))
				local side = vnorm(Kit.vcross(n, { 0, 1, 0 }))
				T.triangle(
					bodyLimb,
					vadd(p, vscale(side, 1.6)),
					vadd(p, vscale(side, -1.6)),
					tip,
					0.4,
					if r < 0.6 then LEAF else LEAF_DARK
				)
			else
				T.ball(bodyLimb, vadd(p, vscale(n, 0.6)), { 1.8, 1.2, 1.8 }, ORCHID)
			end
		end

		-- Thorns down every neck, white spines round the rims of each trap, a glowing nectar ball deep inside.
		local function dress(
			limb: Limb,
			h: { centre: Vec, yaw: number, neck: { { number } } },
			side: number,
			upper: boolean,
			lower: boolean
		)
			local c = { h.centre[1] * side, h.centre[2], h.centre[3] }
			local frame = { origin = c, yaw = h.yaw * side }
			local function at(x: number, y: number, z: number): Vec
				local wx, wy, wz = Kit.toWorld(frame, x, y, z)
				return { wx, wy, wz }
			end
			for k = -3, 3 do
				local z = 4 + math.cos(k / 3.4 * math.pi / 2) * 8.6
				local x = k * 2.3
				if upper then
					T.taper(limb, at(x, 2.2, z), at(x * 1.15, -1.8, z + 1.6), 1.1, 0.8, { 0, 1, 0 }, SPINE)
				end
				if lower then
					T.taper(limb, at(x, -3.4, z), at(x * 1.15, 0.6, z + 1.6), 1.1, 0.8, { 0, 1, 0 }, SPINE)
				end
			end
			if upper then
				T.ball(limb, at(0, -0.8, -2.6), 4.4, NECTAR, NEON)
				-- Glowing spots on top, like eyes.
				for _, x in { -3.2, 3.2 } do
					T.ball(limb, at(x, 6.6, 1.4), { 1.8, 1, 1.8 }, POD, NEON)
				end
				for k = 1, #h.neck - 1 do
					local a, b = h.neck[k], h.neck[k + 1]
					for _, t in { 0.3, 0.7 } do
						local q = vlerp({ a[1] * side, a[2], a[3] }, { b[1] * side, b[2], b[3] }, t)
						local r = a[4] + (b[4] - a[4]) * t
						-- (None where the neck is still buried in the bulb.)
						if q[2] < 40 then
							continue
						end
						T.taper(
							limb,
							vadd(q, { 0, 0, -r + 1.4 }),
							vadd(q, { 0, 1, -r - 2 }),
							1.2,
							1.2,
							{ 1, 0, 0 },
							THORN
						)
					end
				end
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 31, 8 }))
		head:draw(headLimb, others(all, head), BARK)
		dress(headLimb, heads[1], 1, true, false)
		local jawLimb = pet:limb("Jaw", T.at({ 0, 61, 22 }), "Head")
		jaw:draw(jawLimb, others(all, jaw), BARK)
		dress(jawLimb, heads[1], 1, false, true)
		pet:limbPair("LeftHead", "RightHead", T.at({ 6, 31, 6 }), function(limb)
			leftHead:draw(limb, others(all, leftHead), BARK)
			dress(limb, heads[2], 1, true, true)
		end)

		-- Roots spreading from each foot over the ground.
		local function roots(limb: Limb, foot: Vec)
			for k = 0, 4 do
				local a = k / 5 * math.pi * 2 + 0.4
				T.taper(
					limb,
					vadd(foot, { 0, 0.4, 0 }),
					vadd(foot, { math.cos(a) * 9, -foot[2] + 0.6, math.sin(a) * 9 }),
					2.6,
					1.6,
					{ 0, 1, 0 },
					BARK_UNDER.color
				)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 11, 24, 9 }), function(limb)
			front:draw(limb, others(all, front), BARK)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 15, 14, 12 }), function(limb)
			frontShin:draw(limb, { front }, BARK)
			roots(limb, { 15, 1.6, 14 })
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 11, 22, -12 }), function(limb)
			back:draw(limb, others(all, back), BARK)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 15, 13, -8 }), function(limb)
			backShin:draw(limb, { back }, BARK)
			roots(limb, { 15, 1.6, -14 })
		end, "BackLeftLeg")

		local tailLimb = pet:limb("Tail", T.at({ 0, 22, -19 }))
		tail:draw(tailLimb, others(all, tail), BARK)
		for k = 1, #spine - 1 do
			local q = vlerp(spine[k], spine[k + 1], 0.5)
			local r = (spine[k][4] + spine[k + 1][4]) / 2
			T.taper(tailLimb, vadd(q, { 0, r - 1.4, 0 }), vadd(q, { 0, r + 2.6, -1.2 }), 1.6, 1.6, { 1, 0, 0 }, THORN)
		end
		-- The glowing bud at its tip, wrapped in petals.
		T.ball(tailLimb, { 12, 20.6, -57 }, { 4.6, 5.6, 4.6 }, POD, NEON)
		for k = 0, 3 do
			local a = k / 4 * math.pi * 2
			T.taper(
				tailLimb,
				{ 12, 18.6, -56.6 },
				{ 12 + math.cos(a) * 3.4, 24.6, -57 + math.sin(a) * 3.4 },
				2.4,
				0.6,
				{ 0, 1, 0 },
				PETAL
			)
		end

		pet:light(POD, 4.4, 56)
		pet:particles("Fireflies", rgb(220, 255, 120), 24)
		pet:aura(rgb(140, 240, 80), rgb(255, 160, 200))
		pet:seat(0, (topOf(body, -10) + 0.4) / U, -10 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Jade Temple Guardian (Eternal): a living temple idol, seven times a player's height, carved from jade and
-- trimmed in gold: glowing runes running through its stone, a great gold sun disc on its chest, a stern carved
-- face with glowing eyes and gold ear spools, a stepped headdress fanned with long glowing feathers, gold bands on
-- its massive arms and legs, and vines and orchids trailing over its shoulders. Its knees and elbows bend.

Jungle.JadeTempleGuardian = {
	name = "Jade Temple Guardian",
	skeleton = "Giant",
	gait = "Stomp",
	scale = 0.5 * 2.4,
	draw = function(pet)
		-- Built in cells 2.4 design units across.
		local U = 2.4
		local T = inUnits(U)
		local JADE = look(62, 166, 112)
		local JADE_TOP = look(110, 206, 150)
		local JADE_UNDER = look(30, 100, 70)
		local JADE_DARK = look(36, 112, 78)
		local RUNE = look(70, 230, 150, NEON)
		local GOLD = look(240, 192, 64)
		local GOLD_TOP = look(255, 226, 120)
		local MOUTH = look(20, 50, 36)
		local GLOW = rgb(110, 255, 180)
		local GOLD_C = rgb(240, 192, 64)
		local SUN = rgb(255, 214, 90)
		local FEATHER = rgb(40, 190, 120)
		local FEATHER_TIP = rgb(120, 255, 200)
		local VINE = rgb(56, 132, 58)
		local ORCHID = rgb(250, 140, 210)

		local tones = {
			[JADE] = { top = JADE_TOP, under = JADE_UNDER },
			[GOLD] = { top = GOLD_TOP },
		}
		-- Carved stone: courses of blocks with dark seams between them, the seams glowing like runes here and
		-- there, and darker veins in the jade.
		local function stone(p: Vec, _: any, n: Vec): Look?
			local course = math.floor(p[2] / 9.6)
			local seam = p[2] % 9.6 < 2.4 or (p[1] + p[3] + course * 6) % 14.4 < 2.4
			if seam and n[2] < 0.6 then
				return if patches(p, 7) > 0.62 then RUNE else JADE_DARK
			end
			if patches(p, 3) < 0.2 then
				return JADE_DARK
			end
			return nil
		end
		-- A gold band round a part between two heights.
		local function banded(low: number, high: number): (Vec, any, Vec) -> Look?
			return function(p, open, n)
				if p[2] > low and p[2] < high then
					return GOLD
				end
				return stone(p, open, n)
			end
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 46, 0 }, { 16, 11, 10 }), JADE)
		body:add(ellipsoid({ 0, 35, 0 }, { 12, 9, 8.6 }), JADE)
		body:add(ellipsoid({ 0, 27, 0 }, { 12, 6, 8.4 }), JADE)
		body:coat(banded(29, 31.4))
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 61, 2 }, { 7.4, 7.4, 6.6 }), JADE)
		head:coat(function(p, _, n)
			if n[3] > 0.5 and math.abs(p[2] - 57.6) < 0.7 and math.abs(p[1]) < 3.4 then
				return MOUTH
			end
			if patches(p, 2.4) < 0.25 then
				return JADE_DARK
			end
			return nil
		end)
		head:bake(tones)

		local arm, forearm = newSculpt(U), newSculpt(U)
		arm:add(ellipsoid({ 15, 50, 0 }, { 7, 7, 7 }), JADE)
		arm:add(rod({ { 16, 46, 0, 6 }, { 19, 34, 3, 5 } }), JADE)
		forearm:add(rod({ { 19, 34, 3, 5.2 }, { 20, 22, 6, 5.6 } }), JADE)
		forearm:add(ellipsoid({ 20, 16, 7 }, { 6, 6, 6 }), JADE)
		local leg, shin = newSculpt(U), newSculpt(U)
		leg:add(rod({ { 7, 27, 0, 7 }, { 8, 15, 1, 6.4 } }), JADE)
		shin:add(rod({ { 8, 15, 1, 6.2 }, { 8.4, 5, 1, 6 } }), JADE)
		shin:add(ellipsoid({ 8.6, 2.6, 3 }, { 6.4, 2.6, 8 }), JADE)
		arm:coat(banded(41, 43.4))
		forearm:coat(banded(25, 28))
		leg:coat(stone)
		shin:coat(banded(7, 9.4))
		for _, s in { arm, forearm, leg, shin } do
			s:bake(tones)
		end

		local armMirror, legMirror = arm:mirror(), leg:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 27, 0 }))
		body:draw(bodyLimb, { head, arm, armMirror, leg, legMirror }, JADE)
		-- The sun disc on its chest: a gold disc ringed with rays, glowing at its heart.
		local front = (Kit.frontOf(body, 0, 46)) + 0.4
		T.ball(bodyLimb, { 0, 46, front - 0.4 }, { 11, 11, 1.6 }, GOLD_C)
		T.ball(bodyLimb, { 0, 46, front + 0.2 }, { 6, 6, 1.4 }, SUN, NEON)
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			local from = { math.cos(a) * 5, 46 + math.sin(a) * 5, front - 0.2 }
			T.taper(
				bodyLimb,
				from,
				{ math.cos(a) * 8.6, 46 + math.sin(a) * 8.6, front - 0.6 },
				1.6,
				0.6,
				{ 0, 0, 1 },
				GOLD_C
			)
		end
		-- Vines and orchids trailing over its shoulders.
		for _, s in { 1, -1 } do
			for k = 0, 3 do
				local top = { (8 + k * 2.4) * s, topOf(body, -2 + k, (8 + k * 2.4) * s) - 0.6, -2 + k }
				T.blade(bodyLimb, top, vadd(top, { 1 * s, -12 + k * 2, 2 }), 0.8, 0.8, { 1, 0, 0 }, VINE)
				if k % 2 == 0 then
					T.ball(bodyLimb, vadd(top, { 0.6 * s, -5, 1 }), { 1.6, 1.2, 1.6 }, ORCHID)
				end
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 54, 2 }))
		head:draw(headLimb, { body }, JADE)
		local face = Kit.frontOf(head, 0, 61) + 0.2
		-- A stern carved face: a heavy gold brow, glowing eyes, a broad nose, gold ear spools.
		local brow = Kit.frontOf(head, 0, 63.4) - 0.8
		T.blade(headLimb, { -6, 63.4, brow }, { 6, 63.4, brow }, 1.6, 1.6, { 0, 1, 0 }, GOLD_C)
		for _, s in { 1, -1 } do
			T.blade(
				headLimb,
				{ 1.4 * s, 61.2, face - 0.4 },
				{ 4.2 * s, 61.2, face - 0.4 },
				1.4,
				1,
				{ 0, 1, 0 },
				GLOW,
				NEON
			)
			local ear = { (sideOf(head, 60, 2) - 0.4) * s, 60, 2 }
			T.ball(headLimb, ear, { 1.6, 4, 4 }, GOLD_C)
			T.ball(headLimb, vadd(ear, { 0.4 * s, 0, 0 }), { 1.2, 2, 2 }, GLOW, NEON)
		end
		T.blade(headLimb, { 0, 61, face - 0.8 }, { 0, 58.6, face + 0.6 }, 2.2, 1.6, { 0, 0, 1 }, JADE_DARK.color)
		-- The headdress: stepped gold tiers, and a great fan of glowing-tipped feathers rising behind it.
		local y = 66.4
		for i, width in { 15, 12, 9 } do
			T.blade(
				headLimb,
				{ 0, y - 1, 2 },
				{ 0, y + 2, 2 },
				width,
				width * 0.8,
				{ 0, 0, 1 },
				if i % 2 == 1 then GOLD_C else JADE.color
			)
			y += 2.6
		end
		T.ball(headLimb, { 0, 68, 8.4 }, { 3.4, 3.4, 1.6 }, GLOW, NEON)
		for k = -4, 4 do
			local a = k * 0.2
			local dir = { math.sin(a), math.cos(a), -0.25 }
			Kit.feather(headLimb, T.at({ k * 1.2, y - 1, -1 }), dir, 18 / U, 3 / U, 0.6 / U, { 0, 0, 1 }, {
				{ color = GOLD_C, to = 0.15 },
				{ color = FEATHER, to = 0.8 },
				{ color = FEATHER_TIP, material = NEON, to = 1 },
			})
		end

		-- Gold bands on the arms; blocky fists.
		pet:limbPair("LeftArm", "RightArm", T.at({ 15, 50, 0 }), function(limb)
			arm:draw(limb, { body, forearm }, JADE)
			T.ball(limb, { 15, 56, 0 }, { 9, 2.4, 9 }, GOLD_C)
			T.ball(limb, { 15, 57.2, 0 }, { 3, 2, 3 }, GLOW, NEON)
		end)
		pet:limbPair("LeftForearm", "RightForearm", T.at({ 19, 34, 3 }), function(limb)
			forearm:draw(limb, { arm }, JADE)
			for _, dz in { -2.4, 0, 2.4 } do
				T.ball(limb, { 20 + 1.4, 12.6, 7 + dz }, { 2.4, 2.2, 2 }, JADE_TOP.color)
			end
		end, "LeftArm")
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 7, 27, 0 }), function(limb)
			leg:draw(limb, { body, shin }, JADE)
		end)
		pet:limbPair("LeftShin", "RightShin", T.at({ 8, 15, 1 }), function(limb)
			shin:draw(limb, { leg }, JADE)
		end, "LeftLeg")

		pet:light(GLOW, 4.4, 56)
		pet:particles("Sparkles", rgb(180, 255, 210), 24)
		pet:aura(rgb(90, 240, 160), rgb(255, 220, 110))
		pet:seat(0, (topOf(body, -4) + 0.4) / U, -4 / U)
	end,
}

return Jungle
