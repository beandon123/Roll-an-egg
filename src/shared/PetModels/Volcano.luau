--!strict
-- The Volcano's pets, in the showpiece style (see PetModels/Forest for what that means): obsidian, basalt and charred
-- hide cracked through with glowing lava, crisp angled horns, tusks, claws and shards, Roblox flames on manes, spines
-- and tails, and, the rarer they are, more of it: an erupting volcano carried on a shell, a fire-maned chimera, a
-- golem of rock and magma, and the colossal Secret Cerberus and Eternal Lava Dragon.
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
local frontOf = Kit.frontOf
local vadd = Kit.vadd
local vscale = Kit.vscale
local vlerp = Kit.vlerp
local vnorm = Kit.vnorm
local fur = Kit.fur
local crystal = Kit.crystal
local crystalCluster = Kit.crystalCluster

local NEON = Kit.NEON
local EYE = Kit.EYE

local Volcano: { [string]: Design } = {}

-- Lava in the cracks between plates of cooled rock about `size` design units across, the cracks `width` thick (see
-- Kit.cracks): `hot` (glowing) down the middle of each crack, `rim` (dark red, cooling) at its edges, or nil off them.
-- `core` (0 to 1, default 0.55) is how deep into the crack it starts to glow: higher for thinner glowing lines.
local function lava(p: Vec, size: number, width: number, hot: Look, rim: Look, core: number?): Look?
	local on, depth = Kit.cracks(p, size, width)
	if not on then
		return nil
	end
	return if depth > (core or 0.55) then hot else rim
end

-- A horn coiled in a spiral beside the head: from `root`, curling back, down and forward round `centre` in the
-- y-z plane, pushed out sideways as it goes; ridged, tipped in glowing lava. `side` is 1 or -1.
local function spiralHorn(
	limb: Limb,
	T: any,
	root: Vec,
	centre: Vec,
	radius: number,
	turns: number,
	width: number,
	side: number,
	color: { number },
	ridge: { number },
	tip: { number }
)
	local points: { Vec } = { root }
	local start = math.atan2(root[2] - centre[2], root[3] - centre[3])
	local count = math.ceil(turns * 10)
	for i = 1, count do
		local t = i / count
		local a = start + t * turns * math.pi * 2
		local r = radius * (1 - 0.45 * t)
		table.insert(points, { (centre[1] + t * 2.4) * side, centre[2] + math.sin(a) * r, centre[3] + math.cos(a) * r })
	end
	for i = 1, #points - 1 do
		local w = width * (1 - 0.7 * (i - 1) / #points)
		if i == #points - 1 then
			T.taper(limb, points[i], points[i + 1], w, w, { 1, 0, 0 }, tip, NEON)
		else
			T.blade(limb, points[i], points[i + 1], w, w, { 1, 0, 0 }, color)
			if i % 2 == 0 then
				T.ball(limb, points[i + 1], { w * 1.15, w * 1.15, w * 1.15 }, ridge)
			end
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- Obsidian Goat (Rare): a mountain goat of glossy volcanic glass, taller than a player, with jagged obsidian shards
-- on its back, great spiral horns tipped in lava, a shaggy beard, glowing amber eyes and molten hooves.

Volcano.ObsidianGoat = {
	name = "Obsidian Goat",
	skeleton = "Quadruped",
	gait = "Hop",
	scale = 0.3,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local GLASSY = look(42, 34, 54)
		local GLASSY_TOP = look(86, 74, 112)
		local GLASSY_UNDER = look(22, 18, 30)
		local FACET = look(62, 52, 82)
		local LAVA = look(255, 120, 30, NEON)
		local MAGMA = look(120, 34, 24)
		local BEARD = rgb(70, 64, 80)
		local SHARD = rgb(52, 42, 68)
		local GLOW = rgb(255, 150, 40)
		local IRIS = rgb(255, 176, 50)

		local tones = {
			[GLASSY] = { top = GLASSY_TOP, under = GLASSY_UNDER },
			[FACET] = { top = GLASSY_TOP, under = GLASSY_UNDER },
		}
		local function obsidian(p: Vec): Look?
			local crack = p[2] > 9 and lava(p, 9, 0.7, LAVA, MAGMA)
			if crack then
				return crack
			end
			if patches(p, 1.6) < 0.35 then
				return FACET
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 15, -1 }, { 4.2, 4.4, 8 }), GLASSY)
		body:add(ellipsoid({ 0, 15.6, 4.4 }, { 4, 4.8, 4 }), GLASSY)
		body:add(rod({ { 0, 17, 6, 3 }, { 0, 21, 9, 2.4 } }), GLASSY)
		body:coat(obsidian)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 23, 10.6 }, { 2.4, 2.6, 3.2 }), GLASSY)
		head:add(rod({ { 0, 22.4, 12, 1.8 }, { 0, 21.4, 15, 1.2 } }), GLASSY)
		head:coat(function(p)
			if patches(p, 1.2) < 0.35 then
				return FACET
			end
			return nil
		end)
		head:bake(tones)

		local function leg(s: Sculpt, top: Vec, knee: Vec, foot: Vec)
			s:add(
				rod({
					{ top[1], top[2], top[3], 1.6 },
					{ knee[1], knee[2], knee[3], 1.05 },
					{ foot[1], 1.4, foot[3], 0.9 },
				}),
				GLASSY
			)
			s:add(ellipsoid({ foot[1], 0.8, foot[3] + 0.2 }, { 1.05, 0.8, 1.3 }), LAVA)
			s:coat(obsidian)
			s:bake(tones)
		end
		local front, back = newSculpt(U), newSculpt(U)
		leg(front, { 2.4, 14.6, 4.4 }, { 2.5, 7.6, 5 }, { 2.4, 1, 5.2 })
		back:add(ellipsoid({ 2.6, 14.6, -6 }, { 2, 3.6, 3 }), GLASSY)
		leg(back, { 2.6, 12, -6.6 }, { 2.6, 7, -8.2 }, { 2.5, 1, -6.8 })

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 17.6, -8.6, 1 }, { 0, 18.6, -10, 0.8 } }), GLASSY)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 15, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, GLASSY)
		-- Jagged obsidian shards along its back, glowing at their points.
		for i, z in { 4.6, 1.6, -1.4, -4.4 } do
			crystal(
				bodyLimb,
				T,
				{ 0, 18.6, z },
				{ (i % 2 == 0) and 0.3 or -0.3, 1, -0.4 },
				3.4 - i * 0.3,
				1.1,
				SHARD,
				GLOW,
				nil,
				NEON
			)
		end
		for _, s in { 1, -1 } do
			crystalCluster(bodyLimb, T, { 3 * s, 18.4, 3.6 }, { 0.6 * s, 1, -0.2 }, 3, 2, SHARD, GLOW, nil, NEON, 2 + s)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 21, 8.6 }))
		head:draw(headLimb, { body }, GLASSY)
		Kit.slitEyes(headLimb, head, { 23.6, 12.6 }, { 23.8, 10.8 }, 0.7, IRIS, NEON, rgb(20, 16, 26))
		for _, s in { 1, -1 } do
			spiralHorn(
				headLimb,
				T,
				{ 1.4 * s, 25, 10 },
				{ 2.4, 24.6, 7 },
				3.6,
				0.85,
				1.6,
				s,
				SHARD,
				GLASSY_TOP.color,
				GLOW
			)
			T.taper(headLimb, { 2.2 * s, 24, 9.6 }, { 3.8 * s, 24.6, 8.8 }, 1.2, 0.5, { 0, 1, 0 }, GLASSY.color)
		end
		-- A shaggy beard.
		for _, x in { -0.6, 0, 0.6 } do
			T.taper(headLimb, { x, 20.6, 14.2 }, { x * 1.4, 18, 14.6 }, 0.9, 0.6, { 0, 0, 1 }, BEARD)
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 2.4, 14.6, 4.4 }), function(limb)
			front:draw(limb, { body }, GLASSY)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 2.6, 14.6, -6 }), function(limb)
			back:draw(limb, { body }, GLASSY)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 17.6, -8.4 })), { body }, GLASSY)

		pet:seat(0, 19.6, -1.4)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Cinder Boar (Epic): a hulking boar of charred hide cracked with glowing embers, flames running along its bristling
-- spine, great curved tusks, glowing eyes, and a flame on the end of its tail.

Volcano.CinderBoar = {
	name = "Cinder Boar",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.36 * 1.2,
	draw = function(pet)
		-- Built in cells 1.2 design units across.
		local U = 1.2
		local T = inUnits(U)
		local HIDE = look(54, 46, 46)
		local HIDE_TOP = look(80, 68, 66)
		local HIDE_UNDER = look(30, 26, 26)
		local ASH = look(96, 88, 86)
		local EMBER = look(255, 110, 30, NEON)
		local MAGMA = look(126, 34, 22)
		local SNOUT = look(110, 84, 84)
		local BRISTLE = rgb(36, 30, 30)
		local TUSK = rgb(236, 226, 204)
		local TUSK_DARK = rgb(70, 58, 52)
		local FLAME = rgb(255, 110, 24)
		local FLAME_HOT = rgb(255, 214, 70)
		local IRIS = rgb(255, 150, 30)

		local tones = {
			[HIDE] = { top = HIDE_TOP, under = HIDE_UNDER },
			[ASH] = { under = HIDE },
		}
		local function charred(p: Vec): Look?
			local crack = lava(p, 8, 0.8, EMBER, MAGMA)
			if crack then
				return crack
			end
			if patches(p, 2.6) < 0.3 then
				return ASH
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 15, 5 }, { 5.6, 6.6, 5.6 }), HIDE)
		body:add(ellipsoid({ 0, 15, -2 }, { 5.4, 5.6, 8 }), HIDE)
		body:add(ellipsoid({ 0, 14.6, -9 }, { 5, 5.2, 4.6 }), HIDE)
		body:add(ellipsoid({ 0, 20, 3.6 }, { 4.6, 3, 4.6 }), HIDE)
		body:coat(charred)
		body:bake(tones)

		-- A massive head with a long snout ending in a broad disc.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 15.6, 11 }, { 3.8, 3.9, 4.2 }), HIDE)
		head:add(rod({ { 0, 14.6, 13, 2.8 }, { 0, 13, 17.4, 2.2 } }), HIDE)
		head:add(ellipsoid({ 0, 13, 18.4 }, { 2.3, 2.1, 0.9 }), SNOUT)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 2.8 * s, 19.2, 9.4 }, { 1.2, 1.8, 1 }), HIDE)
		end
		head:coat(function(p)
			if p[3] > 18.6 then
				return nil
			end
			return charred(p)
		end)
		head:bake(tones)

		local function leg(s: Sculpt, top: Vec, foot: Vec)
			s:add(rod({ { top[1], top[2], top[3], 2.4 }, { foot[1], 2, foot[3], 1.7 } }), HIDE)
			s:add(ellipsoid({ foot[1], 1, foot[3] + 0.4 }, { 1.7, 1, 2 }), ASH)
			s:coat(charred)
			s:bake(tones)
		end
		local front, back = newSculpt(U), newSculpt(U)
		leg(front, { 3.4, 12, 5 }, { 3.6, 1, 5.6 })
		back:add(ellipsoid({ 3.4, 13.6, -8 }, { 2.6, 4.4, 3.6 }), HIDE)
		leg(back, { 3.4, 10, -8.6 }, { 3.5, 1, -8 })

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 17, -13, 0.8 }, { 0, 15, -14.6, 0.6 }, { 0, 13.6, -14.4, 0.5 } }), HIDE)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 15, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, HIDE)
		-- A bristling mane along its spine, embers at the tips, and flames running along it.
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return math.abs(p[1]) < 1.4 and n[2] > 0.4 and p[3] > -10 and noise(vadd(p, { 3, 3, 3 })) < 0.6
			end,
			3,
			1.1,
			{ 0, 0.6, -0.6 },
			function(p)
				return if noise(p) < 0.3 then FLAME else BRISTLE
			end
		)
		for _, z in { 5.6, 1, -4 } do
			bodyLimb:fire(T.at({ 0, Kit.topOf(body, z) + 0.6, z }), 2.6, FLAME, FLAME_HOT)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 14.6, 8 }))
		head:draw(headLimb, { body }, HIDE)
		Kit.slitEyes(headLimb, head, { 17.4, 13 }, { 17.8, 11.2 }, 0.75, IRIS, NEON, rgb(16, 12, 12))
		for _, s in { 1, -1 } do
			-- Great tusks curving up and out from the lower jaw.
			T.blade(headLimb, { 1.8 * s, 12, 15.6 }, { 3 * s, 12.4, 17.6 }, 1.2, 1.1, { 0, 1, 0 }, TUSK_DARK)
			T.blade(headLimb, { 3 * s, 12.4, 17.6 }, { 4.2 * s, 14.6, 18.8 }, 1.05, 1, { 0, 1, 0 }, TUSK)
			T.taper(headLimb, { 4.2 * s, 14.6, 18.8 }, { 4 * s, 17.4, 18.4 }, 0.95, 0.9, { 0, 1, 0 }, TUSK)
			T.taper(headLimb, { 1.4 * s, 12.6, 17 }, { 1.8 * s, 14.4, 17.8 }, 0.6, 0.6, { 0, 1, 0 }, TUSK)
			T.ball(headLimb, { 0.8 * s, 13.2, 18.85 }, { 0.6, 0.9, 0.4 }, HIDE_UNDER.color)
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.4, 13, 5 }), function(limb)
			front:draw(limb, { body }, HIDE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3.4, 13.6, -8 }), function(limb)
			back:draw(limb, { body }, HIDE)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 17, -12.6 }))
		tail:draw(tailLimb, { body }, HIDE)
		tailLimb:fire(T.at({ 0, 13.6, -14.4 }), 1.6, FLAME, FLAME_HOT)

		pet:seat(0, 23 / U, -2 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Volcano Tortoise (Legendary): a giant tortoise carrying an erupting volcano on its back: a rocky shell with lava
-- rivers running down it from the crater, fire and embers pouring out of the top, glowing eyes, and legs like
-- pillars of scaly rock. An ember aura glows at its feet.

Volcano.VolcanoTortoise = {
	name = "Volcano Tortoise",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.4 * 1.4,
	draw = function(pet)
		-- Built in cells 1.4 design units across.
		local U = 1.4
		local T = inUnits(U)
		local ROCK = look(86, 76, 72)
		local ROCK_TOP = look(118, 104, 96)
		local ROCK_UNDER = look(50, 42, 40)
		local ROCK_DARK = look(62, 54, 52)
		local LAVA = look(255, 116, 28, NEON)
		local POOL = look(255, 200, 60, NEON)
		local SKIN = look(96, 84, 78)
		local SKIN_TOP = look(124, 110, 100)
		local SKIN_UNDER = look(60, 52, 48)
		local SPOT = look(214, 96, 40)
		local BEAK = rgb(52, 44, 40)
		local CLAW = rgb(40, 34, 32)
		local IRIS = rgb(255, 160, 40)

		local tones = {
			[ROCK] = { top = ROCK_TOP, under = ROCK_UNDER },
			[ROCK_DARK] = { under = ROCK_UNDER },
			[SKIN] = { top = SKIN_TOP, under = SKIN_UNDER },
		}
		-- Lava rivers running down from the crater, winding as they go.
		local function river(p: Vec): boolean
			local angle = math.atan2(p[1], p[3] + 1)
			local w = math.sin(angle * 5 + math.sin(p[2] * 0.5) * 0.8)
			return w > 0.93 and p[2] > 12
		end
		local function rock(p: Vec): Look?
			if river(p) then
				return LAVA
			end
			if patches(p, 3) < 0.35 then
				return ROCK_DARK
			end
			return nil
		end

		-- The shell: a rocky dome, a volcano rising from it with a crater of glowing lava.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 13, -1 }, { 12, 8.4, 14 }), ROCK)
		body:add(ellipsoid({ 0, 11, -1 }, { 13, 2, 15 }), ROCK_DARK)
		body:add(rod({ { 0, 18, -1, 8 }, { 0, 27, -1, 4.6 }, { 0, 31, -1, 3.4 } }), ROCK)
		body:carve(ellipsoid({ 0, -1, -1 }, { 16, 7, 18 }))
		body:carve(ellipsoid({ 0, 32.4, -1 }, { 2.8, 2, 2.8 }))
		body:add(ellipsoid({ 0, 30.4, -1 }, { 2.4, 0.8, 2.4 }), POOL)
		body:coat(function(p, open)
			if p[2] < 8 and not open(0, 1, 0) then
				return ROCK_UNDER
			end
			return rock(p)
		end)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(rod({ { 0, 9, 12, 3.6 }, { 0, 11, 17, 3.2 } }), SKIN)
		head:add(ellipsoid({ 0, 12, 20 }, { 3.6, 3.2, 4.2 }), SKIN)
		head:coat(function(p)
			if patches(p, 1.2) < 0.25 then
				return SPOT
			end
			return nil
		end)
		head:bake(tones)

		local function leg(s: Sculpt, top: Vec, foot: Vec)
			s:add(rod({ { top[1], top[2], top[3], 3.4 }, { foot[1], 2.6, foot[3], 3.2 } }), SKIN)
			s:add(ellipsoid({ foot[1], 1.6, foot[3] }, { 3.4, 1.6, 3.6 }), SKIN)
			s:coat(function(p)
				if patches(p, 1.2) < 0.25 then
					return SPOT
				end
				return nil
			end)
			s:bake(tones)
		end
		local front, back = newSculpt(U), newSculpt(U)
		leg(front, { 8.6, 9, 7.6 }, { 9.4, 1, 9 })
		leg(back, { 8.6, 9, -9.6 }, { 9.4, 1, -11 })

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 7, -14, 1.8 }, { 0, 5, -17, 1 } }), SKIN)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 10, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, ROCK)
		-- Fire roaring out of the crater.
		bodyLimb:fire(T.at({ 0, 31.6, -1 }), 7, rgb(255, 96, 20), rgb(255, 214, 70))
		-- Glowing rocks thrown up round the rim.
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			local p = { math.cos(a) * 3.6, 30.2, -1 + math.sin(a) * 3.6 }
			crystal(
				bodyLimb,
				T,
				p,
				{ math.cos(a) * 0.4, 1, math.sin(a) * 0.4 },
				2.4,
				1.1,
				ROCK_DARK.color,
				LAVA.color,
				nil,
				NEON
			)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 10, 12 }))
		head:draw(headLimb, { body }, ROCK)
		Kit.slitEyes(headLimb, head, { 13.6, 22 }, { 13.8, 20 }, 0.9, IRIS, NEON, rgb(24, 18, 16))
		T.taper(
			headLimb,
			{ 0, 12.6, frontOf(head, 0, 12.6) - 0.8 },
			{ 0, 10.4, frontOf(head, 0, 12.6) + 0.6 },
			2.6,
			2.2,
			{ 1, 0, 0 },
			BEAK
		)

		local function claws(limb: Limb, x: number, z: number)
			for _, dx in { -2, -0.7, 0.7, 2 } do
				T.taper(limb, { x + dx, 1.2, z + 2.8 }, { x + dx * 1.1, 0.3, z + 4.2 }, 0.9, 0.8, { 0, 1, 0 }, CLAW)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 8.6, 9, 7.6 }), function(limb)
			front:draw(limb, { body }, ROCK)
			claws(limb, 9.4, 9)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 8.6, 9, -9.6 }), function(limb)
			back:draw(limb, { body }, ROCK)
			claws(limb, 9.4, -11)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 7, -13.6 })), { body }, ROCK)

		pet:light(rgb(255, 120, 40), 2.6, 26)
		pet:particles("Embers", rgb(255, 180, 60), 14)
		pet:aura(rgb(255, 110, 30), rgb(255, 220, 120))
		pet:seat(0, 20.4 / U, 7.4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Fire Salamander (Legendary): a great black salamander spotted with glowing yellow and orange, a frill of flame
-- along its back, glowing gold eyes, and a tail that ends in fire.

Volcano.FireSalamander = {
	name = "Fire Salamander",
	skeleton = "LowSlung",
	gait = "Crawl",
	scale = 0.5,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local BLACK = look(30, 26, 32)
		local BLACK_TOP = look(64, 56, 70)
		local BLACK_UNDER = look(16, 14, 18)
		local SPOT = look(255, 196, 40, NEON)
		local EMBER = look(255, 110, 30, NEON)
		local BELLY = look(120, 50, 36)
		local FIN = rgb(255, 120, 30)
		local FLAME = rgb(255, 100, 20)
		local FLAME_HOT = rgb(255, 220, 80)
		local IRIS = rgb(255, 210, 60)

		local tones = {
			[BLACK] = { top = BLACK_TOP, under = BLACK_UNDER },
		}
		-- Big glowing spots in two colours over the back and sides, a dark red belly.
		local function skin(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, -1, 0) then
				return BELLY
			end
			local n = patches(p, 1.6)
			if n < 0.2 then
				return SPOT
			elseif n > 0.84 then
				return EMBER
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(rod({ { 0, 5, 8, 3.4 }, { 0, 5.4, 2, 3.8 }, { 0, 5.2, -6, 3.4 } }), BLACK)
		body:coat(skin)
		body:bake(tones)

		-- A broad flat head.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 5.8, 11.6 }, { 3.8, 2.6, 3.8 }), BLACK)
		head:add(ellipsoid({ 0, 5.4, 14.6 }, { 3, 1.9, 2.2 }), BLACK)
		head:coat(skin)
		head:bake(tones)

		-- Short splayed legs.
		local function leg(s: Sculpt, hip: Vec, foot: Vec)
			s:add(
				rod({
					{ hip[1], hip[2], hip[3], 1.6 },
					{ foot[1], 2.2, foot[3], 1.2 },
					{ foot[1] + 0.6, 0.8, foot[3] + 0.6, 1 },
				}),
				BLACK
			)
			s:coat(skin)
			s:bake(tones)
		end
		local front, back = newSculpt(U), newSculpt(U)
		leg(front, { 3, 4.6, 6 }, { 6.4, 2, 8 })
		leg(back, { 3, 4.6, -5 }, { 6.4, 2, -6.4 })

		-- A long tail, tapering and curving, to a flame at its tip.
		local spine = {
			{ 0, 5.2, -8, 3 },
			{ 1.4, 4.6, -13, 2.4 },
			{ 3.6, 4, -18, 1.8 },
			{ 5.6, 3.6, -22, 1.2 },
			{ 6.6, 3.6, -25, 0.7 },
		}
		local tail = newSculpt(U)
		tail:add(rod(spine), BLACK)
		tail:coat(skin)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 5, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, BLACK)
		-- A frill of flame along its back: a glowing fin with fire along its crest.
		for i = 0, 5 do
			local z = 8 - i * 2.6
			local y = Kit.topOf(body, z)
			T.triangle(
				bodyLimb,
				{ 0, y - 0.6, z + 1.3 },
				{ 0, y + 2.2 - i * 0.2, z },
				{ 0, y - 0.6, z - 1.3 },
				0.4,
				FIN,
				NEON
			)
			if i % 2 == 0 then
				bodyLimb:fire({ 0, y + 1.6, z }, 1.6, FLAME, FLAME_HOT)
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 5.6, 9 }))
		head:draw(headLimb, { body }, BLACK)
		for _, s in { 1, -1 } do
			local x = sideOf(head, 7.2, 12.4)
			T.ball(headLimb, { (x - 0.4) * s, 7.2, 12.4 }, { 1.6, 1.8, 1.8 }, BLACK_TOP.color)
			T.ball(headLimb, { (x - 0.1) * s, 7.3, 12.6 }, { 1.2, 1.4, 1.4 }, IRIS, NEON)
			T.ball(headLimb, { (x + 0.1) * s, 7.3, 12.7 }, { 0.6, 1.2, 0.4 }, EYE)
		end

		local function toes(limb: Limb, foot: Vec)
			for _, dz in { -0.8, 0, 0.8 } do
				T.taper(
					limb,
					{ foot[1] + 0.6, 0.8, foot[3] + 0.6 },
					{ foot[1] + 1.8, 0.3, foot[3] + 0.8 + dz * 1.6 },
					0.6,
					0.5,
					{ 0, 1, 0 },
					BLACK_TOP.color
				)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3, 4.6, 6 }), function(limb)
			front:draw(limb, { body }, BLACK)
			toes(limb, { 6.4, 2, 8 })
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3, 4.6, -5 }), function(limb)
			back:draw(limb, { body }, BLACK)
			toes(limb, { 6.4, 2, -6.4 })
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 5.2, -7.6 }))
		tail:draw(tailLimb, { body }, BLACK)
		tailLimb:fire({ 6.8, 4, -25.4 }, 3, FLAME, FLAME_HOT)

		pet:light(rgb(255, 140, 40), 2, 18)
		pet:particles("Embers", rgb(255, 196, 60), 10)
		pet:aura(rgb(255, 120, 30), rgb(255, 230, 120))
		pet:seat(0, 9.4, 0)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Chimera (Mythic): the beast of legend, three times a player's height: a great tawny lion with a mane of living
-- fire, a black goat's head rising from its back with spiral horns and glowing violet eyes, and a serpent for a tail.
-- Its legs bend at every joint, and its jaw opens on flames.

Volcano.Chimera = {
	name = "Chimera",
	skeleton = "Beast",
	gait = "Stomp",
	scale = 0.4 * 1.3,
	draw = function(pet)
		-- Built in cells 1.3 design units across.
		local U = 1.3
		local T = inUnits(U)
		local COAT = look(206, 146, 70)
		local COAT_TOP = look(230, 176, 96)
		local COAT_UNDER = look(140, 90, 42)
		local COAT_LOW = look(176, 120, 58)
		local CREAM = look(238, 214, 168)
		local CREAM_SHADE = look(196, 166, 120)
		local MANE = look(150, 40, 20)
		local NOSE = look(70, 40, 34)
		local MOUTH = look(110, 30, 30)
		local GOAT = look(46, 40, 48)
		local GOAT_TOP = look(76, 68, 80)
		local SNAKE = look(46, 86, 50)
		local SNAKE_TOP = look(72, 118, 70)
		local SNAKE_BELLY = look(196, 186, 120)
		local FLAME = rgb(255, 110, 24)
		local FLAME_HOT = rgb(255, 214, 70)
		local EMBER = rgb(255, 150, 40)
		local TOOTH = rgb(250, 246, 232)
		local CLAW = rgb(60, 40, 34)
		local IRIS = rgb(255, 200, 60)
		local VIOLET = rgb(196, 110, 255)
		local VENOM = rgb(150, 255, 90)
		local HORN = rgb(52, 44, 56)

		local tones = {
			[COAT] = { top = COAT_TOP, under = COAT_UNDER, low = COAT_LOW, below = 10 },
			[CREAM] = { under = CREAM_SHADE },
			[GOAT] = { top = GOAT_TOP },
			[SNAKE] = { top = SNAKE_TOP, under = SNAKE_BELLY },
		}

		-- A lion's body: deep chest, high shoulders, a thick neck under the mane; the goat's neck rising from its back.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 21, 6 }, { 6, 7, 6 }), COAT)
		body:add(ellipsoid({ 0, 25.6, 4.4 }, { 5.4, 3.2, 5 }), COAT)
		body:add(ellipsoid({ 0, 20.6, -1.6 }, { 5.4, 5.6, 7 }), COAT)
		body:add(ellipsoid({ 0, 20.2, -10 }, { 5, 5.2, 4.8 }), COAT)
		body:add(rod({ { 0, 23, 9.4, 5 }, { 0, 25.6, 12.4, 4.4 } }), MANE)
		body:add(rod({ { 0, 25, -4.6, 2.6 }, { 0, 31, -3, 2.2 }, { 0, 33.4, -1.6, 2 } }), GOAT)
		body:add(ellipsoid({ 0, 35.6, 0.4 }, { 2.1, 2.5, 3.2 }), GOAT)
		body:coat(function(p, open)
			if open(0, -1, 0) and p[3] > -6 then
				return CREAM
			end
			return nil
		end)
		body:bake(tones)

		-- The lion's head: broad, heavy-browed, a short muzzle (its lower jaw moves).
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 27.4, 15 }, { 4.4, 4, 4.4 }), COAT)
		head:add(ellipsoid({ 0, 29.2, 17.6 }, { 3.6, 1.2, 1.8 }), COAT)
		head:add(ellipsoid({ 0, 25.6, 18.6 }, { 3, 2.4, 2.8 }), CREAM)
		head:add(ellipsoid({ 0, 26.8, 21 }, { 1.4, 1, 0.8 }), NOSE)
		head:coat(function(p, open)
			if p[2] < 24.2 and not open(0, 1, 0) then
				return MOUTH
			end
			return nil
		end)
		head:bake(tones)

		local jaw = newSculpt(U)
		jaw:add(rod({ { 0, 23.6, 15.6, 1.9 }, { 0, 22.8, 19.6, 1.4 } }), CREAM)
		jaw:coat(function(p, open)
			if open(0, 1, 0) and p[3] > 16.4 then
				return MOUTH
			end
			return nil
		end)
		jaw:bake(tones)

		-- Lion's legs in two halves, on great padded paws.
		local front = newSculpt(U)
		front:add(ellipsoid({ 3.9, 21, 6 }, { 2.8, 4.6, 3.4 }), COAT)
		front:add(rod({ { 4, 18.6, 5.8, 2.6 }, { 4.1, 13, 4.4, 2.4 } }), COAT)
		local frontShin = newSculpt(U)
		frontShin:add(rod({ { 4.1, 13, 4.4, 2.3 }, { 4.1, 4.4, 5.8, 1.8 }, { 4.1, 2, 6.8, 1.7 } }), COAT)
		frontShin:add(ellipsoid({ 4.1, 1.3, 7.6 }, { 2.2, 1.3, 2.6 }), COAT)
		local back = newSculpt(U)
		back:add(ellipsoid({ 3.9, 18.4, -9.6 }, { 3, 5.2, 4.2 }), COAT)
		back:add(rod({ { 4, 15.6, -8.8, 2.4 }, { 4, 12.2, -7.2, 2.2 } }), COAT)
		local backShin = newSculpt(U)
		backShin:add(rod({ { 4, 12.2, -7.2, 2 }, { 4, 6.4, -11, 1.6 }, { 3.9, 1.8, -10, 1.4 } }), COAT)
		backShin:add(ellipsoid({ 3.9, 1.2, -9.2 }, { 2, 1.2, 2.4 }), COAT)
		for _, s in { front, frontShin, back, backShin } do
			s:bake(tones)
		end

		-- The serpent tail, curling up and over, ending in a snake's head.
		local spine = {
			{ 0, 22, -14, 1.8 },
			{ 0, 25, -18.4, 1.6 },
			{ 0, 31, -19.6, 1.4 },
			{ 0, 35.4, -16.6, 1.2 },
			{ 0, 36.4, -13, 1.1 },
		}
		local tail = newSculpt(U)
		tail:add(rod(spine), SNAKE)
		tail:add(ellipsoid({ 0, 36.4, -11.4 }, { 1.5, 1.3, 2.2 }), SNAKE)
		tail:coat(function(p)
			if p[2] < 23 then
				return COAT
			end
			if math.floor((p[2] + p[3]) / 1.2) % 3 == 0 then
				return SNAKE_TOP
			end
			return nil
		end)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 21, 0 }))
		body:draw(bodyLimb, { head, jaw, front, frontMirror, back, backMirror, tail }, COAT)
		-- A mane of living fire round its neck and head: flame-red tufts tipped with glowing orange and gold, and real
		-- fire burning in it.
		fur(
			bodyLimb,
			T,
			body,
			function(p)
				return p[3] > 7 and p[2] > 19 and noise(vadd(p, { 2, 4, 6 })) < 0.5
			end,
			4,
			2.4,
			{ 0, 0.4, -1.2 },
			function(p)
				local n = noise(p)
				return if n < 0.3 then FLAME_HOT elseif n < 0.65 then FLAME else MANE.color
			end
		)
		for _, at in { { 0, 30.4, 11 }, { 4.4, 27.4, 11.4 }, { -4.4, 27.4, 11.4 }, { 0, 25, 8 } } do
			bodyLimb:fire(T.at(at), 3.2, FLAME, FLAME_HOT)
		end
		-- The goat's head: spiral horns, glowing violet eyes, a beard.
		for _, s in { 1, -1 } do
			spiralHorn(
				bodyLimb,
				T,
				{ 1.2 * s, 37.4, 0 },
				{ 2, 37, -2.4 },
				2.6,
				0.8,
				1.2,
				s,
				HORN,
				rgb(80, 70, 86),
				VIOLET
			)
			T.ball(bodyLimb, { 1.85 * s, 36.4, 1.8 }, { 0.6, 0.9, 1.2 }, VIOLET, NEON)
		end
		T.taper(bodyLimb, { 0, 34, 2.4 }, { 0, 31.6, 3 }, 1, 0.7, { 0, 0, 1 }, GOAT_TOP.color)

		local headLimb = pet:limb("Head", T.at({ 0, 25, 12 }))
		head:draw(headLimb, { body, jaw }, COAT)
		Kit.slitEyes(headLimb, head, { 28.6, 18.6 }, { 29, 16.4 }, 0.9, IRIS, NEON, rgb(40, 20, 16))
		for _, s in { 1, -1 } do
			T.taper(headLimb, { 1.4 * s, 24.4, 20.2 }, { 1.4 * s, 22.2, 20.4 }, 0.7, 0.7, { 0, 0, 1 }, TOOTH)
		end
		local jawLimb = pet:limb("Jaw", T.at({ 0, 23.6, 15.6 }), "Head")
		jaw:draw(jawLimb, { head, body }, COAT)
		for _, s in { 1, -1 } do
			T.taper(jawLimb, { 1.2 * s, 23.6, 19.4 }, { 1.2 * s, 25, 19.6 }, 0.6, 0.6, { 0, 0, 1 }, TOOTH)
		end
		-- Flames in its mouth.
		jawLimb:fire(T.at({ 0, 24.4, 19.8 }), 2.6, FLAME, FLAME_HOT)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.9, 23, 6 }), function(limb)
			front:draw(limb, { body, frontShin }, COAT)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 4.1, 13, 4.4 }), function(limb)
			frontShin:draw(limb, { front }, COAT)
			for _, dx in { -1, -0.35, 0.35, 1 } do
				T.taper(limb, { 4.1 + dx, 1, 9 }, { 4.1 + dx * 1.1, 0.2, 10.6 }, 0.6, 0.5, { 0, 1, 0 }, CLAW)
			end
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3.9, 22, -9.6 }), function(limb)
			back:draw(limb, { body, backShin }, COAT)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 4, 12.2, -7.2 }), function(limb)
			backShin:draw(limb, { back }, COAT)
		end, "BackLeftLeg")
		local tailLimb = pet:limb("Tail", T.at({ 0, 22, -13.6 }))
		tail:draw(tailLimb, { body }, COAT)
		-- The serpent's glowing eyes and fangs.
		for _, s in { 1, -1 } do
			T.ball(tailLimb, { 1.2 * s, 37, -10.8 }, { 0.5, 0.6, 0.8 }, VENOM, NEON)
			T.taper(tailLimb, { 0.4 * s, 36, -11 }, { 0.5 * s, 34.4, -10.4 }, 0.35, 0.35, { 0, 0, 1 }, TOOTH)
		end

		pet:light(EMBER, 2.6, 26)
		pet:particles("Embers", rgb(255, 196, 60), 14)
		pet:aura(rgb(255, 100, 30), rgb(255, 220, 120))
		pet:seat(0, 28.6 / U, 1.4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Lava Golem (Mythic): a colossus of basalt five times a player's height, its plates of rock split by glowing lava,
-- a molten core blazing in the open chest, boulder shoulders on fire, obsidian crystals on its forearms, huge cracked
-- fists, magma dripping from it, and glowing eyes deep under its brow.

Volcano.LavaGolem = {
	name = "Lava Golem",
	skeleton = "Giant",
	gait = "Stomp",
	scale = 0.34 * 1.5,
	draw = function(pet)
		-- Built in cells 1.5 design units across.
		local U = 1.5
		local T = inUnits(U)
		local ROCK = look(70, 62, 60)
		local ROCK_TOP = look(102, 92, 86)
		local ROCK_UNDER = look(40, 34, 34)
		local ROCK_DARK = look(52, 46, 46)
		local LAVA = look(255, 128, 30, NEON)
		local MAGMA = look(140, 40, 22)
		local CORE = rgb(255, 220, 90)
		local OBSIDIAN = rgb(44, 34, 54)
		local GLOW = rgb(255, 150, 40)
		local FLAME = rgb(255, 100, 20)
		local FLAME_HOT = rgb(255, 214, 70)

		local tones = {
			[ROCK] = { top = ROCK_TOP, under = ROCK_UNDER },
			[ROCK_DARK] = { top = ROCK, under = ROCK_UNDER },
		}
		local function basalt(p: Vec): Look?
			local crack = lava(p, 13, 1.9, LAVA, MAGMA)
			if crack then
				return crack
			end
			if patches(p, 4) < 0.3 then
				return ROCK_DARK
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 38, 1 }, { 12.4, 8.6, 8 }), ROCK)
		body:add(ellipsoid({ 0, 28, 1 }, { 7.4, 7, 6 }), ROCK)
		body:add(ellipsoid({ 0, 22, 0 }, { 8, 3.6, 6 }), ROCK)
		body:carve(ellipsoid({ 0, 37, 8.4 }, { 5, 5.4, 3.6 }))
		body:coat(function(p)
			local x, y, z = p[1], p[2], p[3]
			if z > 4.6 and math.abs(x) < 5 and math.abs(y - 37) < 5.4 and (x * x / 19 + (y - 37) ^ 2 / 23) < 1.6 then
				return MAGMA
			end
			return basalt(p)
		end)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 49.6, 3.4 }, { 5, 4.6, 4.6 }), ROCK)
		head:add(ellipsoid({ 0, 52, 6.6 }, { 5, 1.6, 2 }), ROCK_DARK)
		head:coat(function(p)
			return basalt(p)
		end)
		head:bake(tones)

		-- Boulder shoulders, huge arms, cracked fists.
		-- The forearm (from the elbow down) and the shin (from the knee down) are limbs of their own, so they bend.
		local arm, forearm = newSculpt(U), newSculpt(U)
		arm:add(ellipsoid({ 14, 44, 0 }, { 6.4, 6, 6.4 }), ROCK)
		arm:add(rod({ { 14.6, 42, 0.4, 4.6 }, { 18, 31, 2, 4.4 } }), ROCK)
		forearm:add(rod({ { 18, 31, 2, 5 }, { 19.4, 19, 4, 6 } }), ROCK)
		forearm:add(ellipsoid({ 19.6, 13, 5 }, { 6, 5.6, 6 }), ROCK_DARK)

		local leg, shin = newSculpt(U), newSculpt(U)
		leg:add(rod({ { 6, 22, 0, 6 }, { 7, 10, 1, 5.4 } }), ROCK)
		shin:add(rod({ { 7, 10, 1, 5.35 }, { 7.4, 5.4, 1.6, 5 } }), ROCK)
		shin:add(ellipsoid({ 7.6, 2.8, 3 }, { 5.6, 2.8, 7 }), ROCK_DARK)
		for _, s in { arm, forearm, leg, shin } do
			s:coat(function(p)
				return basalt(p)
			end)
			s:bake(tones)
		end

		local armMirror, legMirror = arm:mirror(), leg:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 22, 0 }))
		body:draw(bodyLimb, { head, arm, armMirror, leg, legMirror }, ROCK)
		-- The molten core blazing in the hollow of its chest, behind bars of rock.
		T.ball(bodyLimb, { 0, 37, 6.4 }, { 7.6, 8.4, 5 }, GLOW, NEON)
		T.ball(bodyLimb, { 0, 37, 8 }, { 4.4, 4.8, 3 }, CORE, NEON)
		for _, x in { -2.2, 2.2 } do
			T.blade(bodyLimb, { x, 42.6, 8.6 }, { x * 1.2, 31.6, 8.8 }, 1.2, 1.2, { 0, 0, 1 }, ROCK_DARK.color)
		end
		-- Magma dripping from its chest.
		for _, d in { { -2.6, 31, 5.4, 3 }, { 2.2, 29.6, 5.6, 2.4 } } do
			T.taper(
				bodyLimb,
				{ d[1], d[2], d[3] - 0.6 },
				{ d[1], d[2] - d[4], d[3] },
				0.9,
				0.8,
				{ 0, 0, 1 },
				GLOW,
				NEON
			)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 46, 2 }))
		head:draw(headLimb, { body }, ROCK)
		for _, s in { 1, -1 } do
			local face = frontOf(head, 2 * s, 50)
			T.ball(headLimb, { 2 * s, 50, face - 0.5 }, { 1.8, 1.2, 1 }, CORE, NEON)
			-- Obsidian horns.
			crystal(headLimb, T, { 3.6 * s, 52.6, 2 }, { 0.6 * s, 1, -0.4 }, 4.4, 1.4, OBSIDIAN, GLOW, nil, NEON)
		end
		T.blade(
			headLimb,
			{ -1.8, 47.6, frontOf(head, 0, 47.6) - 0.4 },
			{ 1.8, 47.6, frontOf(head, 0, 47.6) - 0.4 },
			0.6,
			0.6,
			{ 0, 1, 0 },
			GLOW,
			NEON
		)

		-- Fire burning on its boulder shoulder, obsidian crystals on its forearm, magma dripping from its fist.
		pet:limbPair("LeftArm", "RightArm", T.at({ 14, 44, 0 }), function(limb)
			arm:draw(limb, { body, forearm }, ROCK)
			limb:fire(T.at({ 14.4, 50.6, 0 }), 4, FLAME, FLAME_HOT)
		end)
		pet:limbPair("LeftForearm", "RightForearm", T.at({ 18, 31, 2 }), function(limb)
			forearm:draw(limb, { arm }, ROCK)
			crystalCluster(limb, T, { 23, 25, 2.6 }, { 1, 0.4, -0.3 }, 6, 3, OBSIDIAN, GLOW, nil, NEON, 4)
			T.taper(limb, { 19.6, 8.2, 5 }, { 19.6, 5.4, 5.2 }, 1.2, 1.1, { 0, 0, 1 }, GLOW, NEON)
		end, "LeftArm")
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 6, 22, 0 }), function(limb)
			leg:draw(limb, { body, shin }, ROCK)
		end)
		pet:limbPair("LeftShin", "RightShin", T.at({ 7, 10, 1 }), function(limb)
			shin:draw(limb, { leg }, ROCK)
		end, "LeftLeg")

		pet:light(GLOW, 3, 30)
		pet:particles("Embers", rgb(255, 180, 60), 16)
		pet:aura(rgb(255, 100, 30), rgb(255, 220, 120))
		pet:seat(0, 47 / U, -5.4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Cerberus (Secret): the colossal hound of the underworld, six times a player's height. Charcoal hide split by
-- glowing lava; three heads on three thick necks, each with a mane of fire, glowing eyes, bared fangs and a spiked
-- iron collar trailing broken chain; obsidian spines down its back; molten claws; a tail ending in flame. Its legs
-- bend at every joint, and its middle head's jaw opens to roar.

Volcano.Cerberus = {
	name = "Cerberus",
	skeleton = "ThreeHeaded",
	gait = "Stomp",
	scale = 0.42 * 2,
	draw = function(pet)
		-- Built in cells 2 design units across (most of a stud each, at its size).
		local U = 2
		local T = inUnits(U)
		local HIDE = look(38, 32, 34)
		local HIDE_TOP = look(70, 60, 62)
		local HIDE_UNDER = look(20, 16, 18)
		local LAVA = look(255, 110, 30, NEON)
		local MAGMA = look(130, 34, 22)
		local MOUTH = look(110, 24, 24)
		local IRON = look(56, 56, 64)
		local IRON_TOP = look(90, 90, 100)
		local MANE = rgb(150, 34, 20)
		local FLAME = rgb(255, 96, 20)
		local FLAME_HOT = rgb(255, 214, 70)
		local SPIKE = rgb(120, 120, 132)
		local TOOTH = rgb(246, 238, 220)
		local OBSIDIAN = rgb(40, 30, 48)
		local GLOW = rgb(255, 130, 40)
		local IRIS = rgb(255, 80, 40)
		local GOLD = rgb(255, 196, 60)

		local tones = {
			[HIDE] = { top = HIDE_TOP, under = HIDE_UNDER },
			[IRON] = { top = IRON_TOP },
		}
		local function hide(p: Vec): Look?
			return lava(p, 19, 2.6, LAVA, MAGMA, 0.65)
		end

		-- The three heads: where each sits, and which way its muzzle points.
		local heads = {
			{
				centre = { 0, 65, 29 },
				dir = vnorm({ 0, -0.12, 1 }),
				neck = { { 0, 46, 14, 7.6 }, { 0, 56, 22, 6.2 }, { 0, 62, 26, 5.6 } },
			},
			{
				centre = { 19.6, 60, 24 },
				dir = vnorm({ 0.35, -0.12, 1 }),
				neck = { { 6, 45, 13, 6.8 }, { 14, 53, 19, 5.6 }, { 18, 57.4, 21.6, 5.2 } },
			},
			{
				centre = { -19.6, 60, 24 },
				dir = vnorm({ -0.35, -0.12, 1 }),
				neck = { { -6, 45, 13, 6.8 }, { -14, 53, 19, 5.6 }, { -18, 57.4, 21.6, 5.2 } },
			},
		}

		-- A massive chest and shoulders tapering to a lean waist and strong hips.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 40, 8 }, { 12, 13, 11 }), HIDE)
		body:add(ellipsoid({ 0, 48, 5 }, { 10, 5, 9 }), HIDE)
		body:add(ellipsoid({ 0, 39, -6 }, { 11, 11, 13 }), HIDE)
		body:add(ellipsoid({ 0, 39, -18 }, { 8, 8.4, 7 }), HIDE)
		body:add(ellipsoid({ 0, 40, -25 }, { 9.4, 9.6, 8 }), HIDE)
		body:coat(hide)
		body:bake(tones)

		-- Each head with its neck, a sculpt of its own, so each head moves on its own (the middle head's lower jaw
		-- is its own limb too). The side heads snarl with their jaws open; each neck wears a spiked iron collar
		-- three quarters of the way up its first length.
		local function sculptHead(index: number, h: { centre: Vec, dir: Vec, neck: { { number } } }): Sculpt
			local s = newSculpt(U)
			local c, d = h.centre, h.dir
			s:add(rod(h.neck), HIDE)
			s:add(ellipsoid(c, { 5.8, 5.2, 6.4 }), HIDE)
			s:add(ellipsoid(vadd(c, vadd(vscale(d, 4), { 0, 2.2, 0 })), { 4.6, 1.5, 2.2 }), HIDE)
			s:add(
				rod({
					{ c[1] + d[1] * 4, c[2] - 1, c[3] + d[3] * 4, 3.8 },
					{ c[1] + d[1] * 13, c[2] - 2, c[3] + d[3] * 13, 2.4 },
				}),
				HIDE
			)
			s:add(ellipsoid({ c[1] + d[1] * 13.6, c[2] - 1.2, c[3] + d[3] * 13.6 }, { 1.8, 1.3, 1.2 }), HIDE_UNDER)
			if index > 1 then
				s:add(
					rod({
						{ c[1] + d[1] * 3, c[2] - 5, c[3] + d[3] * 3, 2.8 },
						{ c[1] + d[1] * 10, c[2] - 7.6, c[3] + d[3] * 10, 2 },
					}),
					HIDE
				)
			end
			s:coat(function(p, open)
				local dz = p[3] - c[3]
				if
					index > 1
					and math.abs(p[1] - c[1] - d[1] * dz) < 3
					and p[2] < c[2] - 2.4
					and p[2] > c[2] - 6.4
					and dz > 3
				then
					return MOUTH
				end
				local n1, n2 = h.neck[1], h.neck[2]
				local ab = Kit.vsub(n2, n1)
				local t = Kit.vdot(Kit.vsub(p, n1), ab) / Kit.vdot(ab, ab)
				if t > 0.66 and t < 0.84 then
					local axis = vlerp(n1, n2, t)
					if Kit.vlength(Kit.vsub(p, axis)) < n1[4] + (n2[4] - n1[4]) * t + 1.2 then
						return IRON
					end
				end
				if open(0, -1, 0) and p[2] < 50 then
					return nil
				end
				return hide(p)
			end)
			s:bake(tones)
			return s
		end
		local head, leftHead = sculptHead(1, heads[1]), sculptHead(2, heads[2])
		local rightHead = leftHead:mirror()

		local jaw = newSculpt(U)
		jaw:add(rod({ { 0, 60.4, 31, 3 }, { 0, 58.6, 38.6, 2.2 } }), HIDE)
		jaw:coat(function(_, open)
			if open(0, 1, 0) then
				return MOUTH
			end
			return nil
		end)
		jaw:bake(tones)

		-- Legs in two halves on great clawed paws.
		local front = newSculpt(U)
		front:add(ellipsoid({ 8.6, 42, 8 }, { 5.6, 9, 6.4 }), HIDE)
		front:add(rod({ { 8.8, 36, 8, 5 }, { 9, 24, 6, 4.6 } }), HIDE)
		local frontShin = newSculpt(U)
		frontShin:add(rod({ { 9, 24, 6, 4.4 }, { 9, 8, 8.6, 3.6 }, { 9, 3.8, 10.4, 3.4 } }), HIDE)
		frontShin:add(ellipsoid({ 9, 2.4, 12 }, { 4.4, 2.4, 5.2 }), HIDE)
		local back = newSculpt(U)
		back:add(ellipsoid({ 8.6, 37, -24 }, { 6, 10, 8 }), HIDE)
		back:add(rod({ { 8.8, 32, -22, 5 }, { 9, 24, -18, 4.4 } }), HIDE)
		local backShin = newSculpt(U)
		backShin:add(rod({ { 9, 24, -18, 4 }, { 9, 12, -26, 3.2 }, { 8.8, 3.8, -24, 3 } }), HIDE)
		backShin:add(ellipsoid({ 8.8, 2.4, -22.4 }, { 4.2, 2.4, 5 }), HIDE)
		for _, s in { front, frontShin, back, backShin } do
			s:coat(hide)
			s:bake(tones)
		end

		local spine = { { 0, 44, -31, 3.4 }, { 0, 50, -38, 2.8 }, { 0, 54, -46, 2.2 }, { 0, 52, -54, 1.5 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), HIDE)
		tail:coat(hide)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 40, 0 }))
		body:draw(bodyLimb, { head, leftHead, rightHead, jaw, front, frontMirror, back, backMirror, tail }, HIDE)
		-- Obsidian spines along its back, glowing at their points; the middle of the back is left for a rider.
		for i, z in { 8, 3.4, -18, -23, -28 } do
			local y = Kit.topOf(body, z)
			crystal(bodyLimb, T, { 0, y - 1, z }, { 0, 1, -0.4 }, 7 - (i % 2) * 2, 2.2, OBSIDIAN, GLOW, nil, NEON)
		end

		-- The details of a head, on its limb: glowing eyes, ears, a mane of fire, fangs, and its collar's spikes, chain
		-- and gold stud.
		local function dress(
			limb: Limb,
			index: number,
			h: { centre: Vec, dir: Vec, neck: { { number } } },
			clay: Sculpt
		)
			local c, d = h.centre, h.dir
			local side = vnorm(Kit.vcross({ 0, 1, 0 }, d))
			-- Big glowing eyes under the brow, each in a dark socket.
			for _, s in { 1, -1 } do
				local eye = vadd(vadd(c, vscale(d, 4.8)), vadd(vscale(side, 3.2 * s), { 0, 1, 0 }))
				T.ball(limb, eye, { 3, 2, 2 }, HIDE_UNDER.color)
				T.ball(limb, vadd(eye, vscale(d, 0.5)), { 2.4, 1.4, 1.4 }, IRIS, NEON)
			end
			-- Tall pointed ears, and a mane of fire behind them.
			for _, s in { 1, -1 } do
				local root = vadd(vadd(c, vscale(side, 3.6 * s)), { 0, 3.4, -0.6 })
				T.taper(
					limb,
					root,
					vadd(root, vadd(vscale(d, -2.4), vadd(vscale(side, 1.4 * s), { 0, 6.4, 0 }))),
					3,
					1.4,
					d,
					HIDE.color
				)
				T.taper(
					limb,
					vadd(root, vscale(d, 0.7)),
					vadd(root, vadd(vscale(d, -1.6), vadd(vscale(side, 1.3 * s), { 0, 5.2, 0 }))),
					1.6,
					0.4,
					d,
					MAGMA.color
				)
			end
			fur(
				limb,
				T,
				clay,
				function(p, n)
					local dc = vscale(Kit.vsub(p, c), 1)
					return Kit.vlength(dc) < 8
						and Kit.vdot(dc, d) < -1
						and n[2] > -0.3
						and noise(vadd(p, { index, 2, 2 })) < 0.6
				end,
				5,
				2.4,
				vadd(vscale(d, -1.4), { 0, 0.8, 0 }),
				function(p)
					local n = noise(p)
					return if n < 0.35 then FLAME_HOT elseif n < 0.7 then FLAME else MANE
				end
			)
			limb:fire(T.at(vadd(vadd(c, vscale(d, -3)), { 0, 5, 0 })), 5, FLAME, FLAME_HOT)
			-- Fangs in the upper jaw, and in the open lower jaws of the side heads.
			for _, s in { 1, -1 } do
				for k = 0, 2 do
					local along = 10 - k * 2.4
					local base = vadd(
						vadd(c, vscale(d, along)),
						vadd(vscale(side, (1.6 + k * 0.4) * s), { 0, -3.6 + k * 0.2, 0 })
					)
					T.taper(limb, base, vadd(base, { 0, -2.6 + k * 0.4, 0 }), 1, 0.9, side, TOOTH)
					if index > 1 then
						local low = vadd(
							vadd(c, vscale(d, along - 1)),
							vadd(vscale(side, (1.4 + k * 0.4) * s), { 0, -6.6 + k * 0.3, 0 })
						)
						T.taper(limb, low, vadd(low, { 0, 2.2, 0 }), 0.9, 0.8, side, TOOTH)
					end
				end
			end
			-- Spikes on the collar, and a broken chain hanging from it.
			local n = h.neck
			local mid = vlerp({ n[1][1], n[1][2], n[1][3] }, { n[2][1], n[2][2], n[2][3] }, 0.75)
			local r = n[1][4] + (n[2][4] - n[1][4]) * 0.75
			for k = 0, 5 do
				local a = k / 6 * math.pi * 2
				local out = vnorm(vadd(vscale(side, math.cos(a)), { 0, math.sin(a) * 0.8, math.sin(a) * 0.6 }))
				local base = vadd(mid, vscale(out, r + 0.2))
				T.taper(limb, base, vadd(base, vscale(out, 2.6)), 1.4, 1.4, d, SPIKE)
			end
			local link = vadd(mid, { 0, -r - 0.4, r * 0.5 })
			for k = 0, 2 do
				local next = vadd(link, { 0.4 * (k % 2 == 0 and 1 or -1), -2.4, 0.3 })
				T.blade(limb, link, next, 1, 0.6, if k % 2 == 0 then { 1, 0, 0 } else { 0, 0, 1 }, IRON.color)
				link = next
			end
			T.ball(limb, vadd(mid, vscale(d, r + 0.4)), { 1.6, 1.6, 1.6 }, GOLD)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 46, 14 }))
		head:draw(headLimb, { body, jaw, leftHead, rightHead, front, frontMirror }, HIDE)
		dress(headLimb, 1, heads[1], head)
		pet:limbPair("LeftHead", "RightHead", T.at({ 6, 45, 13 }), function(limb)
			leftHead:draw(limb, { body, head, rightHead, front }, HIDE)
			dress(limb, 2, heads[2], leftHead)
		end)

		local jawLimb = pet:limb("Jaw", T.at({ 0, 60.4, 31 }), "Head")
		jaw:draw(jawLimb, { head }, HIDE)
		for _, s in { 1, -1 } do
			T.taper(jawLimb, { 1.6 * s, 60.6, 37.4 }, { 1.6 * s, 62.8, 37.6 }, 0.9, 0.8, { s, 0, 0 }, TOOTH)
		end
		jawLimb:fire(T.at({ 0, 61.4, 38 }), 3.6, FLAME, FLAME_HOT)

		local function claws(limb: Limb, x: number, z: number)
			for _, dx in { -2.6, -0.9, 0.9, 2.6 } do
				T.taper(limb, { x + dx, 1.8, z - 0.6 }, { x + dx * 1.1, 0.2, z + 2.6 }, 1.2, 1, { 0, 1, 0 }, OBSIDIAN)
				T.ball(limb, { x + dx * 1.1, 0.6, z + 2 }, { 0.8, 0.8, 0.8 }, GLOW, NEON)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 8.6, 46, 8 }), function(limb)
			front:draw(limb, { body, frontShin, head, leftHead }, HIDE)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 9, 24, 6 }), function(limb)
			frontShin:draw(limb, { front }, HIDE)
			claws(limb, 9, 15.4)
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 8.6, 44, -24 }), function(limb)
			back:draw(limb, { body, backShin }, HIDE)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 9, 24, -18 }), function(limb)
			backShin:draw(limb, { back }, HIDE)
			claws(limb, 8.8, -19)
		end, "BackLeftLeg")
		local tailLimb = pet:limb("Tail", T.at({ 0, 44, -30 }))
		tail:draw(tailLimb, { body }, HIDE)
		for k = 1, #spine - 1 do
			local p = vlerp(spine[k], spine[k + 1], 0.5)
			crystal(tailLimb, T, { 0, p[2] + 1.6, p[3] }, { 0, 1, -0.6 }, 3.4, 1.2, OBSIDIAN, GLOW, nil, NEON)
		end
		tailLimb:fire(T.at({ 0, 52.4, -55 }), 5, FLAME, FLAME_HOT)

		pet:light(GLOW, 4, 50)
		pet:particles("Embers", rgb(255, 190, 70), 22)
		pet:aura(rgb(255, 80, 30), rgb(255, 214, 110))
		pet:seat(0, 50.4 / U, -8 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Lava Dragon (Eternal): a colossal dragon of the volcano's heart, six times a player's height with wings spanning
-- twelve. Obsidian scales split by glowing lava, a molten belly, great swept-back horns and a spiked brow over
-- glowing eyes, jaws open on fire, huge bat wings with glowing veins and burning tips, obsidian spines down its back
-- and a long tail ending in a blade of obsidian and flame.

Volcano.LavaDragon = {
	name = "Lava Dragon",
	skeleton = "Dragon",
	gait = "Stomp",
	scale = 0.42 * 2.4,
	draw = function(pet)
		-- Built in cells 2.4 design units across (about a stud each, at its size).
		local U = 2.4
		local T = inUnits(U)
		local SCALE = look(44, 28, 30)
		local SCALE_TOP = look(82, 54, 50)
		local SCALE_UNDER = look(24, 14, 16)
		local LAVA = look(255, 120, 30, NEON)
		local MAGMA = look(140, 38, 22)
		local BELLY = look(196, 82, 30)
		local BELLY_DARK = look(150, 56, 24)
		local MOUTH = look(120, 26, 20)
		local THROAT = look(255, 190, 70, NEON)
		local BONE = rgb(60, 40, 40)
		local MEMBRANE = rgb(120, 28, 20)
		local MEMBRANE_DARK = rgb(84, 18, 14)
		local VEIN = rgb(255, 120, 30)
		local OBSIDIAN = rgb(40, 28, 44)
		local GLOW = rgb(255, 150, 40)
		local HORN = rgb(54, 40, 44)
		local TOOTH = rgb(250, 240, 220)
		local IRIS = rgb(255, 210, 60)
		local FLAME = rgb(255, 96, 20)
		local FLAME_HOT = rgb(255, 214, 70)

		local tones = {
			[SCALE] = { top = SCALE_TOP, under = SCALE_UNDER },
		}
		local function scales(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, -1, 0) and p[2] < 30 then
				return if math.floor(p[3] / 3) % 2 == 0 then BELLY else BELLY_DARK
			end
			return lava(p, 30, 3.4, LAVA, MAGMA, 0.72)
		end

		-- A deep chest, a long belly, strong hips, and a neck rising high.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 30, 8 }, { 11, 12, 11 }), SCALE)
		body:add(ellipsoid({ 0, 28, -6 }, { 10, 10, 13 }), SCALE)
		body:add(ellipsoid({ 0, 29, -19 }, { 9.4, 9.6, 8.4 }), SCALE)
		body:add(rod({ { 0, 36, 14, 8 }, { 0, 48, 22, 6.4 }, { 0, 58, 26, 5.6 } }), SCALE)
		body:coat(scales)
		body:bake(tones)

		-- The head: a long armoured skull, a spiked brow, jaws open on a glowing throat.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 64, 30 }, { 6.4, 5.6, 7.4 }), SCALE)
		head:add(ellipsoid({ 0, 67.6, 34 }, { 5.6, 1.8, 3.4 }), SCALE)
		head:add(ellipsoid({ 0, 62, 39 }, { 4.4, 3.4, 8 }), SCALE)
		head:add(ellipsoid({ 0, 62.4, 46.4 }, { 3, 2.4, 2 }), SCALE)
		head:add(rod({ { 0, 57.4, 32, 3.6 }, { 0, 55.6, 44, 2.6 } }), SCALE)
		head:add(ellipsoid({ 0, 59.4, 32 }, { 3.6, 2.6, 3.6 }), THROAT)
		head:carve(ellipsoid({ 0, 59.2, 41 }, { 3.6, 1.8, 8 }))
		head:coat(function(p, open)
			if math.abs(p[1]) < 3.6 and p[2] > 56.4 and p[2] < 61.4 and p[3] > 35 then
				return MOUTH
			end
			return scales(p, open)
		end)
		head:bake(tones)

		-- Legs in two halves, bending at the knee: the front legs' elbows behind, the hind legs' knees in front
		-- and hocks behind, on broad clawed feet.
		local front, frontShin, back, backShin = newSculpt(U), newSculpt(U), newSculpt(U), newSculpt(U)
		front:add(ellipsoid({ 8.4, 30, 9 }, { 5, 8, 6 }), SCALE)
		front:add(rod({ { 8.6, 27, 9, 4.6 }, { 9, 17, 6, 4.1 } }), SCALE)
		frontShin:add(rod({ { 9, 17, 6, 4 }, { 9, 4, 10, 3.6 } }), SCALE)
		frontShin:add(ellipsoid({ 9, 2.4, 12 }, { 4.6, 2.4, 5.4 }), SCALE)
		back:add(ellipsoid({ 8.6, 28, -19 }, { 6, 9.6, 8 }), SCALE)
		back:add(rod({ { 9, 24, -19, 5 }, { 9, 16, -14, 4.4 } }), SCALE)
		backShin:add(rod({ { 9, 16, -14, 4.2 }, { 9, 8, -21, 3.4 }, { 9, 4, -18.6, 3.4 } }), SCALE)
		backShin:add(ellipsoid({ 9, 2.4, -16 }, { 4.8, 2.4, 5.6 }), SCALE)
		for _, s in { front, frontShin, back, backShin } do
			s:coat(scales)
			s:bake(tones)
		end

		local spine =
			{ { 0, 30, -26, 6.4 }, { 2, 26, -38, 5 }, { 6, 18, -50, 3.8 }, { 8, 12, -62, 2.6 }, { 8, 12, -72, 1.6 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), SCALE)
		tail:coat(scales)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 30, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, SCALE)
		-- Obsidian spines down its neck and back, glowing at their points; the back between the wings is left for a
		-- rider.
		for i, z in { 22, 17, 12, -16, -21 } do
			local y = Kit.topOf(body, z)
			crystal(bodyLimb, T, { 0, y - 1, z }, { 0, 1, -0.5 }, 7 - (i % 2) * 2, 2.4, OBSIDIAN, GLOW, nil, NEON)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 58, 25 }))
		head:draw(headLimb, { body }, SCALE)
		Kit.slitEyes(headLimb, head, { 66, 37 }, { 66.6, 33.4 }, 1.4, IRIS, NEON, rgb(20, 12, 14))
		-- Fire roaring in its open jaws.
		headLimb:fire(T.at({ 0, 59.4, 46 }), 8, FLAME, FLAME_HOT)
		for _, s in { 1, -1 } do
			-- Great horns swept back from the skull, a smaller pair below them, spikes along the jaw.
			local horn = { { 4 * s, 68, 26 }, { 7 * s, 74, 18 }, { 9 * s, 78, 10 }, { 9.4 * s, 80, 2 } }
			T.branch(headLimb, horn, 3.6, { 0, 0, 1 }, HORN)
			T.ball(headLimb, horn[#horn], { 1.6, 1.6, 1.6 }, GLOW, NEON)
			T.branch(headLimb, { { 5.4 * s, 64, 25 }, { 9 * s, 66, 19 }, { 11 * s, 66, 14 } }, 2.2, { 0, 0, 1 }, HORN)
			for k = 0, 2 do
				local root = { 5 * s, 60 - k * 1.4, 29 - k * 2.4 }
				T.taper(headLimb, root, vadd(root, { 3.2 * s, -1, -2.4 }), 1.4, 1, { 0, 1, 0 }, HORN)
			end
			-- Fangs, top and bottom.
			for k = 0, 3 do
				local z = 46 - k * 2.4
				local x = sideOf(head, 60.8, z) - 0.8
				if x > 0.6 then
					T.taper(headLimb, { x * s, 61.4, z }, { x * s, 58, z + 0.4 }, 1.1, 1, { s, 0, 0 }, TOOTH)
				end
				local xl = sideOf(head, 56.6, z - 2) - 0.8
				if xl > 0.6 then
					T.taper(headLimb, { xl * s, 56.4, z - 2 }, { xl * s, 59, z - 1.6 }, 1, 0.9, { s, 0, 0 }, TOOTH)
				end
			end
		end

		local function talons(limb: Limb, x: number, z: number)
			for _, dx in { -2.6, -0.9, 0.9, 2.6 } do
				T.taper(limb, { x + dx, 1.8, z }, { x + dx * 1.1, 0.2, z + 3 }, 1.2, 1, { 0, 1, 0 }, OBSIDIAN)
				T.ball(limb, { x + dx * 1.1, 0.6, z + 2.4 }, { 0.8, 0.8, 0.8 }, GLOW, NEON)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 8.4, 34, 9 }), function(limb)
			front:draw(limb, { body, frontShin }, SCALE)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 9, 17, 6 }), function(limb)
			frontShin:draw(limb, { front }, SCALE)
			talons(limb, 9, 14)
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 8.6, 34, -19 }), function(limb)
			back:draw(limb, { body, backShin }, SCALE)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 9, 16, -14 }), function(limb)
			backShin:draw(limb, { back }, SCALE)
			talons(limb, 9, -12.6)
		end, "BackLeftLeg")

		local tailLimb = pet:limb("Tail", T.at({ 0, 30, -25 }))
		tail:draw(tailLimb, { body }, SCALE)
		for k = 1, #spine - 1 do
			local p = vlerp(spine[k], spine[k + 1], 0.5)
			local y = p[2] + (spine[k][4] + spine[k + 1][4]) * 0.4
			crystal(tailLimb, T, { p[1], y, p[3] }, { 0, 1, -0.6 }, 5 - k * 0.8, 1.8, OBSIDIAN, GLOW, nil, NEON)
		end
		-- A blade of obsidian at the end of the tail, and flame.
		T.triangle(tailLimb, { 8, 13, -72 }, { 8, 20, -80 }, { 8, 8, -82 }, 1.2, OBSIDIAN)
		T.blade(tailLimb, { 8, 20, -80 }, { 8, 8, -82 }, 0.6, 1.3, { 1, 0, 0 }, GLOW, NEON)
		tailLimb:fire(T.at({ 8, 16, -80 }), 6, FLAME, FLAME_HOT)

		-- The wings: a long arm of bone and four fingers, webbed with a dark red membrane, glowing veins along the
		-- bones, a glowing trailing edge, and fire burning at the wing's tip.
		pet:limbPair("LeftWing", "RightWing", T.at({ 9, 42, 8 }), function(wing)
			local shoulder, elbow, wrist = { 9, 42, 8 }, { 24, 58, 2 }, { 38, 68, -6 }
			local tips = { { 64, 74, -10 }, { 72, 56, -18 }, { 62, 38, -24 }, { 44, 28, -24 } }
			local root = { 9, 34, -14 }
			T.blade(wing, shoulder, elbow, 3.4, 3, { 0, 0, 1 }, BONE)
			T.blade(wing, elbow, wrist, 2.8, 2.6, { 0, 0, 1 }, BONE)
			T.ball(wing, elbow, { 3.6, 3.6, 3.6 }, BONE)
			T.ball(wing, wrist, { 3.2, 3.2, 3.2 }, BONE)
			T.taper(wing, wrist, vadd(wrist, { 2, 6, 2 }), 2, 1.6, { 0, 0, 1 }, OBSIDIAN)
			wing:fire(T.at(vadd(wrist, { 2, 7, 2 })), 4, FLAME, FLAME_HOT)
			local last = tips[#tips]
			for k, tip in tips do
				T.blade(wing, wrist, tip, 1.6, 1.4, { 0, 0, 1 }, BONE)
				T.blade(wing, vlerp(wrist, tip, 0.1), vlerp(wrist, tip, 0.92), 0.5, 1.6, { 0, 0, 1 }, VEIN, NEON)
				if k > 1 then
					T.triangle(wing, wrist, tips[k - 1], tip, 0.8, if k % 2 == 0 then MEMBRANE else MEMBRANE_DARK)
				end
			end
			T.triangle(wing, wrist, last, elbow, 0.8, MEMBRANE)
			T.triangle(wing, elbow, last, root, 0.8, MEMBRANE_DARK)
			T.triangle(wing, elbow, root, shoulder, 0.8, MEMBRANE)
			-- The glowing trailing edge between the finger tips.
			for k = 1, #tips - 1 do
				T.blade(wing, tips[k], tips[k + 1], 0.8, 1, { 0, 0, 1 }, VEIN, NEON)
			end
			T.blade(wing, tips[#tips], root, 0.8, 1, { 0, 0, 1 }, VEIN, NEON)
			wing:fire(T.at(tips[1]), 5, FLAME, FLAME_HOT)
			wing:fire(T.at(tips[2]), 4, FLAME, FLAME_HOT)
		end)

		pet:light(GLOW, 4.4, 56)
		pet:particles("Embers", rgb(255, 200, 70), 26)
		pet:aura(rgb(255, 110, 30), rgb(255, 230, 140))
		pet:seat(0, 42.4 / U, -6 / U)
	end,
}

return Volcano
