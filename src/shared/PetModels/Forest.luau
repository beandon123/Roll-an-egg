--!strict
-- The Forest's pets, in the showpiece style: sculpted fine in voxels with light baked in from above (lighter
-- tops, darker undersides), crisp angled parts for claws, teeth, quills, antlers and tufts of fur, and, the rarer
-- they are, more that glows: Neon eyes and markings, then lights, fireflies and an aura round their feet.
-- Sizes run from about a player's height (the Commons) to several times it (the Treant).
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
local vnorm = Kit.vnorm
local nearPath = Kit.nearPath
local glossyEye = Kit.glossyEye
local fur = Kit.fur

local NEON = Kit.NEON
local EYE = Kit.EYE
local SHINE = Kit.SHINE

local Forest: { [string]: Design } = {}

----------------------------------------------------------------------------------------------------------------
-- Squirrel (Common): a red squirrel about a player's size, crouched on all fours with big haunches, its great
-- bushy tail swept up behind it in an S and curling over at the top.

Forest.Squirrel = {
	name = "Squirrel",
	skeleton = "Quadruped",
	gait = "Hop",
	scale = 0.22,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local FUR = look(204, 108, 46)
		local FUR_TOP = look(226, 136, 64)
		local FUR_UNDER = look(150, 72, 32)
		local FUR_LOW = look(172, 86, 38)
		local CREAM = look(250, 232, 200)
		local CREAM_SHADE = look(224, 198, 164)
		local FRINGE = look(236, 150, 76)
		local FRINGE_TOP = look(248, 182, 110)
		local DARK = look(98, 54, 30)
		local NOSE = look(52, 34, 30)
		local PINK = rgb(240, 160, 160)
		local CLAW = rgb(66, 42, 30)

		local tones = {
			[FUR] = { top = FUR_TOP, under = FUR_UNDER, low = FUR_LOW, below = 3.5 },
			[CREAM] = { under = CREAM_SHADE },
			[FRINGE] = { top = FRINGE_TOP, under = FUR },
		}

		-- A compact, rounded body, higher at the shoulders, with a cream chest and belly.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 7.8, -1.2 }, { 3.9, 3.8, 5 }), FUR)
		body:add(ellipsoid({ 0, 9, 2.4 }, { 3.3, 3.5, 3.1 }), FUR)
		body:add(rod({ { 0, 9.6, 3, 2.7 }, { 0, 11.2, 5.4, 2.4 } }), FUR)
		body:coat(function(p, open)
			if open(0, -1, 0) or (p[3] > 2.6 and p[2] < 10 and math.abs(p[1]) < 2.4) then
				return CREAM
			end
			return nil
		end)
		body:bake(tones)

		-- A big round head with full cheeks and a short muzzle.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 13, 6.8 }, { 3.4, 3.2, 3.5 }), FUR)
		head:add(ellipsoid({ 0, 11.8, 7.8 }, { 3.6, 2.3, 2.7 }), FUR)
		head:add(ellipsoid({ 0, 12, 9.8 }, { 2, 1.8, 2 }), FUR)
		head:add(ellipsoid({ 0, 12.5, 11.5 }, { 0.85, 0.65, 0.55 }), NOSE)
		head:coat(function(p)
			if p[2] < 11.8 and (p[3] > 8.2 or math.abs(p[1]) > 2.6) then
				return CREAM
			end
			return nil
		end)
		head:bake(tones)

		-- Short front legs with small dark hands.
		local front = newSculpt(U)
		front:add(rod({ { 2.2, 8.4, 2.8, 1.45 }, { 2.4, 5, 3.6, 1.15 }, { 2.2, 1.4, 4.6, 0.95 } }), FUR)
		front:add(ellipsoid({ 2.2, 0.75, 5.1 }, { 1.05, 0.75, 1.3 }), DARK)
		front:bake(tones)

		-- Big haunches folded at its sides, and long dark feet flat on the ground.
		local back = newSculpt(U)
		back:add(ellipsoid({ 3, 6.6, -3.4 }, { 2, 3.5, 3.9 }), FUR)
		back:add(rod({ { 3, 3.6, -5.6, 1.4 }, { 2.9, 1.2, -5.9, 1.05 } }), FUR)
		back:add(rod({ { 2.9, 0.75, -6.2, 1.05 }, { 2.8, 0.7, -1.6, 0.9 } }), DARK)
		back:coat(function(p, open)
			if open(0, -1, 0) and p[2] > 2.5 then
				return CREAM
			end
			return nil
		end)
		back:bake(tones)

		-- The tail: thick and bushy, out behind it, up in an S and curling over at the top, with a pale fringe.
		local spine = {
			{ 0, 6.8, -5.8, 1.7 },
			{ 0, 7.8, -9, 2.6 },
			{ 0, 11, -11.6, 3.6 },
			{ 0, 15.6, -12, 4.1 },
			{ 0, 19.8, -10.4, 4 },
			{ 0, 22, -7.6, 3.3 },
			{ 0, 21, -5.4, 2.4 },
			{ 0, 19.2, -5.2, 1.6 },
		}
		local tail = newSculpt(U)
		tail:add(rod(spine), FUR)
		-- Tufts along both sides and the back of the curl, so its outline is shaggy.
		for i = 2, #spine - 1 do
			local p, q = spine[i], spine[i + 1]
			for _, side in { 1, -1 } do
				tail:add(ellipsoid({ side * p[4] * 0.55, p[2], p[3] }, { p[4] * 0.62, p[4] * 0.7, p[4] * 0.7 }), FUR)
			end
			local mid = { (p[1] + q[1]) / 2, (p[2] + q[2]) / 2, (p[3] + q[3]) / 2 }
			local away = vnorm({ 0, mid[2] - 15, mid[3] + 7 })
			tail:add(ellipsoid(vadd(mid, vscale(away, p[4] * 0.7)), { p[4] * 0.55, p[4] * 0.55, p[4] * 0.55 }), FUR)
		end
		tail:coat(function(p)
			local d, r = nearPath(spine, p)
			if d > r * 1.02 then
				return FRINGE
			end
			return nil
		end)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 7.8, 0 })), { head, front, frontMirror, back, backMirror, tail }, FUR)

		local headLimb = pet:limb("Head", T.at({ 0, 11, 5 }))
		head:draw(headLimb, { body }, FUR)
		glossyEye(headLimb, T, head, 13.6, 8.4, 2)
		for _, s in { 1, -1 } do
			-- Tall ears, pink inside, with dark tufts on the tips.
			T.taper(headLimb, { 2.1 * s, 15, 6 }, { 2.7 * s, 18.6, 5.4 }, 1.9, 0.9, { 0, 0, 1 }, FUR.color)
			T.taper(headLimb, { 2.1 * s, 15.4, 6.5 }, { 2.6 * s, 17.6, 5.9 }, 1.1, 0.3, { 0, 0, 1 }, PINK)
			T.taper(headLimb, { 2.6 * s, 17.8, 5.5 }, { 2.9 * s, 19.8, 4.6 }, 1, 0.7, { 0, 0, 1 }, DARK.color)
			-- Whiskers.
			for _, dy in { -0.25, 0.25 } do
				T.blade(
					headLimb,
					{ 1.5 * s, 11.9 + dy, 10.8 },
					{ 3.4 * s, 12.1 + dy * 2, 10.6 },
					0.1,
					0.1,
					{ 0, 1, 0 },
					DARK.color
				)
			end
		end
		T.blade(headLimb, { 0, 11.8, 11.3 }, { 0, 11, 11 }, 0.25, 0.2, { 0, 0, 1 }, NOSE.color)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 2.2, 8.2, 2.8 }), function(limb)
			front:draw(limb, { body }, FUR)
			for _, dx in { -0.6, 0, 0.6 } do
				T.taper(limb, { 2.2 + dx, 0.5, 5.9 }, { 2.2 + dx * 1.3, 0.2, 6.8 }, 0.35, 0.3, { 0, 1, 0 }, CLAW)
			end
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3, 7.4, -3.4 }), function(limb)
			back:draw(limb, { body }, FUR)
			for _, dx in { -0.6, 0, 0.6 } do
				T.taper(limb, { 2.8 + dx, 0.5, -1.1 }, { 2.8 + dx * 1.3, 0.2, -0.1 }, 0.35, 0.3, { 0, 1, 0 }, CLAW)
			end
		end)

		tail:draw(pet:limb("Tail", T.at({ 0, 7, -5.8 })), { body }, FUR)

		pet:seat(0, 12, -1)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Bunny (Common): a big cottontail, white with a fawn saddle like its egg, tall ears up, crouched to spring.

Forest.Bunny = {
	name = "Bunny",
	skeleton = "Quadruped",
	gait = "Hop",
	scale = 0.22,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local FUR = look(246, 242, 234)
		local FUR_TOP = look(255, 253, 248)
		local FUR_UNDER = look(206, 200, 192)
		local FUR_LOW = look(226, 220, 212)
		local FAWN = look(212, 170, 124)
		local FAWN_TOP = look(232, 194, 150)
		local FAWN_UNDER = look(178, 136, 96)
		local PINK = look(246, 160, 172)
		local INNER = rgb(250, 186, 194)
		local NOSE = rgb(232, 120, 140)
		local IRIS = rgb(70, 40, 30)
		local LINE = rgb(150, 128, 112)

		local tones = {
			[FUR] = { top = FUR_TOP, under = FUR_UNDER, low = FUR_LOW, below = 2.5 },
			[FAWN] = { top = FAWN_TOP, under = FAWN_UNDER },
		}

		-- A round body, highest over the hips, with a fawn saddle over its back.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 7.2, -1.6 }, { 3.9, 3.9, 4.8 }), FUR)
		body:add(ellipsoid({ 0, 8.4, -3 }, { 3.8, 3.7, 3.6 }), FUR)
		body:add(ellipsoid({ 0, 8, 2 }, { 3.2, 3.4, 3 }), FUR)
		body:add(rod({ { 0, 9, 2.6, 2.6 }, { 0, 10.4, 4.4, 2.4 } }), FUR)
		body:coat(function(p, open)
			if p[2] > 8.6 and p[3] < 1.6 and (open(0, 1, 0) or math.abs(p[1]) < 3.4) then
				return FAWN
			end
			return nil
		end)
		body:bake(tones)

		-- A round head with puffed cheeks and a little pink nose.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 12.2, 5.2 }, { 3.1, 3, 3.3 }), FUR)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 1.5 * s, 10.9, 6.4 }, { 2, 1.8, 2 }), FUR)
		end
		head:add(ellipsoid({ 0, 11.2, 7.8 }, { 1.6, 1.4, 1.4 }), FUR)
		head:coat(function(p, open)
			if open(0, 1, 0) and p[3] < 6 and math.abs(p[1]) < 2 then
				return FAWN
			end
			return nil
		end)
		head:bake(tones)

		local front = newSculpt(U)
		front:add(rod({ { 2, 7.6, 2.4, 1.3 }, { 2.1, 4.4, 3.4, 1.05 }, { 2, 1.2, 4, 0.95 } }), FUR)
		front:add(ellipsoid({ 2, 0.75, 4.6 }, { 1.05, 0.75, 1.3 }), FUR)
		front:bake(tones)

		-- Big haunches and long hind feet.
		local back = newSculpt(U)
		back:add(ellipsoid({ 2.9, 6.4, -3.2 }, { 2, 3.6, 4 }), FUR)
		back:add(rod({ { 2.9, 3.4, -5.4, 1.4 }, { 2.8, 1.2, -5.8, 1.1 } }), FUR)
		back:add(rod({ { 2.8, 0.8, -6.2, 1.1 }, { 2.7, 0.7, -0.8, 0.95 } }), FUR)
		back:coat(function(p, open)
			if p[2] > 7.6 and open(0, 1, 0) then
				return FAWN
			end
			return nil
		end)
		back:bake(tones)

		-- A fluffy cotton tail.
		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 8, -6.6 }, { 2, 2, 1.8 }), FUR)
		for _, o in { { 1, 0.8, -0.4 }, { -1, 0.8, -0.4 }, { 0, -0.6, -0.8 }, { 0, 1.4, -0.2 } } do
			tail:add(ellipsoid({ o[1], 8 + o[2], -6.6 + o[3] }, { 1.2, 1.2, 1.2 }), FUR)
		end
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 7.4, 0 })), { head, front, frontMirror, back, backMirror, tail }, FUR)

		local headLimb = pet:limb("Head", T.at({ 0, 10.6, 4 }))
		head:draw(headLimb, { body }, FUR)
		glossyEye(headLimb, T, head, 12.8, 6.6, 2, nil, IRIS)
		-- A pink nose and a split lip.
		T.ball(headLimb, { 0, 11.7, 9.05 }, { 1.1, 0.7, 0.6 }, NOSE)
		T.blade(headLimb, { 0, 11.4, 9.05 }, { 0, 10.5, 8.9 }, 0.18, 0.2, { 0, 0, 1 }, LINE)
		for _, s in { 1, -1 } do
			-- Tall ears standing up and leaning back a little, pink inside, with fawn tips.
			local root, mid, top = { 1.3 * s, 14.2, 4.6 }, { 1.9 * s, 18.4, 3.8 }, { 2.3 * s, 22.4, 3 }
			T.blade(headLimb, root, mid, 2.3, 0.9, { 0, 0, 1 }, FUR.color)
			T.blade(headLimb, mid, top, 2.1, 0.85, { 0, 0, 1 }, FUR.color)
			T.taper(headLimb, top, { 2.5 * s, 24.4, 2.6 }, 2, 0.8, { 0, 0, 1 }, FAWN.color)
			T.blade(headLimb, { 1.4 * s, 15, 5.05 }, { 2.1 * s, 21.4, 3.65 }, 1.2, 0.3, { 0, 0, 1 }, INNER)
			T.ball(headLimb, { 1.6 * s, 10.6, 8.2 }, { 0.5, 0.5, 0.5 }, PINK.color)
			for _, dy in { -0.2, 0.3 } do
				T.blade(
					headLimb,
					{ 0.9 * s, 11 + dy, 8.2 },
					{ 3.6 * s, 11.2 + dy * 2.4, 8.2 },
					0.1,
					0.1,
					{ 0, 1, 0 },
					LINE
				)
			end
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 2, 7.4, 2.4 }), function(limb)
			front:draw(limb, { body }, FUR)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 2.9, 7.2, -3.2 }), function(limb)
			back:draw(limb, { body }, FUR)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 8, -5.6 })), { body }, FUR)

		pet:seat(0, 11.4, -1.4)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Hedgehog (Uncommon): a hedgehog as big as a player, a dome of banded quills bristling out of it, with an acorn
-- and an oak leaf caught on its back, and a pointed, whiskered face.

Forest.Hedgehog = {
	name = "Hedgehog",
	skeleton = "LowSlung",
	scale = 0.25,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local QUILL = look(104, 72, 48)
		local QUILL_DARK = look(70, 48, 34)
		local QUILL_TOP = look(128, 92, 62)
		local QUILL_LIGHT = look(214, 186, 150)
		local FACE = look(232, 200, 160)
		local FACE_SHADE = look(196, 162, 124)
		local FACE_LOW = look(212, 178, 140)
		local NOSE = look(36, 28, 26)
		local TIP = rgb(236, 214, 180)
		local BASE = rgb(92, 62, 42)
		local ACORN = rgb(196, 134, 70)
		local ACORN_TOP = rgb(222, 162, 92)
		local CAP = rgb(112, 76, 46)
		local LEAF = rgb(108, 168, 64)
		local LEAF_DARK = rgb(72, 126, 44)
		local CLAW = rgb(60, 44, 34)

		local tones = {
			[QUILL] = { top = QUILL_TOP, under = QUILL_DARK },
			[FACE] = { under = FACE_SHADE, low = FACE_LOW, below = 2 },
		}

		-- A big round dome of quills, banded light and dark, over a pale underside.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 7.4, -1 }, { 7.6, 6.8, 8.4 }), QUILL)
		body:add(ellipsoid({ 0, 4.2, 0 }, { 6.4, 3.4, 7.4 }), FACE)
		body:carve(ellipsoid({ 0, -1.6, 0 }, { 9, 3, 10 }))
		body:coat(function(p, open)
			if p[2] < 4.4 and not open(0, 1, 0) then
				return FACE
			end
			-- Soft bands of paler quills.
			if patches(p, 2.4) < 0.3 then
				return QUILL_LIGHT
			end
			return nil
		end)
		body:bake(tones)

		-- A pointed face with round cheeks, a dark nose and bright eyes.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 5.4, 6.4 }, { 4, 3.6, 3.4 }), FACE)
		head:add(rod({ { 0, 5, 7.6, 2.6 }, { 0, 4.6, 10.6, 1.4 }, { 0, 4.6, 11.8, 1 } }), FACE)
		head:add(ellipsoid({ 0, 4.9, 12.5 }, { 1, 0.85, 0.75 }), NOSE)
		head:bake(tones)

		local function foot(s: Sculpt, x: number, z: number)
			s:add(rod({ { x, 2.6, z, 1.3 }, { x, 0.8, z + 0.3, 1.1 } }), FACE)
			s:add(ellipsoid({ x, 0.6, z + 0.8 }, { 1.2, 0.6, 1.4 }), FACE)
			s:bake(tones)
		end
		local front, back = newSculpt(U), newSculpt(U)
		foot(front, 3.8, 4)
		foot(back, 4, -4.4)

		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 3.6, -9 }, { 1, 0.9, 1.2 }), FACE)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 5, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, QUILL)
		-- Quills bristling out all over the dome, sweeping back, each dark at the root and pale at the tip.
		for _, spot in
			body:surface(function(p, n)
				return p[2] > 4.6 and n[2] > -0.2 and noise(vadd(p, { 5, 3, 1 })) < 0.22
			end)
		do
			local p, n = spot[1], spot[2]
			local dir = vnorm(vadd(n, { 0, 0.1, -0.85 }))
			local length = 2.2 + 1.4 * noise(vadd(p, { 1, 9, 4 }))
			local mid = vadd(p, vscale(dir, length * 0.55))
			T.blade(bodyLimb, vadd(p, vscale(dir, -0.4)), mid, 0.55, 0.55, n, BASE)
			T.taper(bodyLimb, mid, vadd(p, vscale(dir, length)), 0.55, 0.5, n, TIP)
		end
		-- An acorn and an oak leaf caught on its back.
		T.ball(bodyLimb, { -2.2, 14.2, -1.4 }, { 2.2, 2.6, 2.2 }, ACORN)
		T.ball(bodyLimb, { -2.4, 14.8, -1.1 }, { 1.2, 1.2, 1.2 }, ACORN_TOP)
		T.ball(bodyLimb, { -2.2, 15.4, -1.4 }, { 2.6, 1.3, 2.6 }, CAP)
		T.blade(bodyLimb, { -2.2, 15.9, -1.4 }, { -2.1, 16.8, -1.6 }, 0.35, 0.35, { 0, 0, 1 }, CAP)
		T.triangle(bodyLimb, { 1, 13.8, 0.2 }, { 4.6, 13.2, -2.2 }, { 0.8, 13.6, -3.6 }, 0.25, LEAF)
		T.triangle(bodyLimb, { 1, 13.8, 0.2 }, { 0.8, 13.6, -3.6 }, { -1.6, 13.4, -1.6 }, 0.25, LEAF_DARK)

		local headLimb = pet:limb("Head", T.at({ 0, 5, 6 }))
		head:draw(headLimb, { body }, QUILL)
		glossyEye(headLimb, T, head, 6.4, 9.2, 1.4)
		for _, s in { 1, -1 } do
			T.ball(headLimb, { 2.7 * s, 8.4, 7.3 }, { 1, 1.4, 1.4 }, FACE.color)
			for _, dy in { -0.3, 0.3 } do
				T.blade(
					headLimb,
					{ 0.8 * s, 4.6 + dy, 11.6 },
					{ 3.2 * s, 4.8 + dy * 2.4, 11 },
					0.1,
					0.1,
					{ 0, 1, 0 },
					NOSE.color
				)
			end
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.8, 2.6, 4 }), function(limb)
			front:draw(limb, { body }, QUILL)
			for _, dx in { -0.5, 0, 0.5 } do
				T.taper(limb, { 3.8 + dx, 0.4, 5.6 }, { 3.8 + dx * 1.4, 0.2, 6.4 }, 0.3, 0.3, { 0, 1, 0 }, CLAW)
			end
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4, 2.6, -4.4 }), function(limb)
			back:draw(limb, { body }, QUILL)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 3.6, -8.4 })), { body }, QUILL)

		pet:seat(0, 13.4, -2.4)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Fox (Uncommon): a sleek red fox, a little bigger than a player, with black stockings, a white chest and a long
-- bushy white-tipped tail.

Forest.Fox = {
	name = "Fox",
	skeleton = "Quadruped",
	scale = 0.24,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local FUR = look(226, 110, 40)
		local FUR_TOP = look(244, 140, 62)
		local FUR_UNDER = look(170, 74, 28)
		local WHITE = look(248, 242, 232)
		local WHITE_SHADE = look(214, 204, 194)
		local SOCK = look(52, 36, 30)
		local SOCK_TOP = look(76, 54, 44)
		local NOSE = look(30, 24, 24)
		local INNER = rgb(250, 232, 214)
		local IRIS = rgb(214, 150, 40)

		local tones = {
			[FUR] = { top = FUR_TOP, under = FUR_UNDER },
			[WHITE] = { under = WHITE_SHADE },
			[SOCK] = { top = SOCK_TOP },
		}

		-- A slim, deep-chested body with a white throat and chest.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 9.6, -1.6 }, { 3.3, 3.2, 7.2 }), FUR)
		body:add(ellipsoid({ 0, 9.8, 3.8 }, { 3.2, 3.6, 3.4 }), FUR)
		body:add(rod({ { 0, 11, 5, 2.6 }, { 0, 13.2, 7.6, 2.2 } }), FUR)
		body:coat(function(p, open)
			if (p[3] > 4 and p[2] < 12.6 and math.abs(p[1]) < 2.4) or (open(0, -1, 0) and p[3] > 1) then
				return WHITE
			end
			return nil
		end)
		body:bake(tones)

		-- A wedge-shaped head: broad cheeks, a long narrow muzzle, white below, a dark nose.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 14.8, 8.6 }, { 3.3, 3, 3.2 }), FUR)
		head:add(ellipsoid({ 0, 13.7, 9 }, { 3.7, 2.1, 2.5 }), FUR)
		head:add(rod({ { 0, 14, 10, 1.9 }, { 0, 13.6, 13.6, 0.95 } }), FUR)
		head:add(ellipsoid({ 0, 13.8, 14.2 }, { 0.8, 0.6, 0.6 }), NOSE)
		head:coat(function(p)
			if p[2] < 13.8 and (math.abs(p[1]) > 2.2 or p[3] > 10) then
				return WHITE
			end
			return nil
		end)
		head:bake(tones)

		-- Long slim legs in black stockings.
		local function leg(s: Sculpt, top: Vec, knee: Vec, foot: Vec)
			s:add(
				rod({
					{ top[1], top[2], top[3], 1.6 },
					{ knee[1], knee[2], knee[3], 1.05 },
					{ foot[1], 1.2, foot[3], 0.85 },
				}),
				FUR
			)
			s:add(ellipsoid({ foot[1], 0.7, foot[3] + 0.4 }, { 0.95, 0.7, 1.3 }), SOCK)
			s:coat(function(p)
				if p[2] < 5.2 then
					return SOCK
				end
				return nil
			end)
			s:bake(tones)
		end
		local front, back = newSculpt(U), newSculpt(U)
		leg(front, { 2.1, 9, 3.6 }, { 2.2, 5, 3.9 }, { 2.1, 1, 4.2 })
		back:add(ellipsoid({ 2.4, 9.2, -5.4 }, { 1.6, 2.8, 3 }), FUR)
		leg(back, { 2.4, 8.4, -5.6 }, { 2.3, 4.6, -6.8 }, { 2.2, 1, -5.6 })

		-- A long, thick brush of a tail, held out and down, white at the tip.
		local spine = {
			{ 0, 10.4, -8.2, 1.6 },
			{ 0, 9.2, -11.6, 2.6 },
			{ 0, 7.4, -15, 2.9 },
			{ 0, 6.4, -18.2, 2.4 },
			{ 0, 6.6, -20.4, 1.3 },
		}
		local tail = newSculpt(U)
		tail:add(rod(spine), FUR)
		for i = 2, 4 do
			local q = spine[i]
			for _, side in { 1, -1 } do
				tail:add(ellipsoid({ side * q[4] * 0.5, q[2], q[3] }, { q[4] * 0.6, q[4] * 0.75, q[4] * 0.8 }), FUR)
			end
		end
		tail:coat(function(p)
			if p[3] < -17.2 then
				return WHITE
			end
			return nil
		end)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 9.6, 0 })), { head, front, frontMirror, back, backMirror, tail }, FUR)

		local headLimb = pet:limb("Head", T.at({ 0, 12.6, 6.6 }))
		head:draw(headLimb, { body }, FUR)
		glossyEye(headLimb, T, head, 15.4, 10.6, 1.5, rgb(30, 22, 20), IRIS, nil, rgb(24, 18, 16))
		for _, s in { 1, -1 } do
			-- Big pointed ears, dark on the back, pale inside.
			T.taper(headLimb, { 1.8 * s, 16.6, 8.2 }, { 2.6 * s, 21.4, 7.4 }, 2.6, 1, { 0, 0, 1 }, FUR.color)
			T.taper(headLimb, { 1.8 * s, 16.6, 7.55 }, { 2.6 * s, 21.2, 6.85 }, 2.4, 0.4, { 0, 0, 1 }, SOCK.color)
			T.taper(headLimb, { 1.8 * s, 16.9, 8.75 }, { 2.5 * s, 20.2, 8.15 }, 1.4, 0.3, { 0, 0, 1 }, INNER)
			-- White cheek ruffs sweeping back.
			T.taper(headLimb, { 2.6 * s, 13.2, 8.6 }, { 4.2 * s, 12.6, 6.6 }, 1.4, 0.8, { 0, 1, 0 }, WHITE.color)
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 2.1, 9, 3.6 }), function(limb)
			front:draw(limb, { body }, FUR)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 2.4, 9.2, -5.4 }), function(limb)
			back:draw(limb, { body }, FUR)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 10.2, -7.8 }))
		tail:draw(tailLimb, { body }, FUR)
		fur(
			tailLimb,
			T,
			tail,
			function(p, n)
				return n[2] > -0.3 and noise(vadd(p, { 2, 8, 3 })) < 0.12
			end,
			1.3,
			0.8,
			{ 0, 0, -0.6 },
			function(p)
				return if p[3] < -17.2 then WHITE.color else FUR_TOP.color
			end
		)

		pet:seat(0, 13, -1.6)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Owl (Rare): a great horned owl taller than a player, glaring out of a pale facial disc with glowing amber eyes,
-- tall ear tufts, barred feathers layered down its folded wings, and two little toadstools (its egg) on a shoulder.

Forest.Owl = {
	name = "Owl",
	skeleton = "Winged",
	gait = "Waddle",
	scale = 0.27,
	wingSpread = 1.35,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local BROWN = look(132, 90, 56)
		local BROWN_TOP = look(160, 116, 74)
		local BROWN_UNDER = look(92, 62, 40)
		local DARK = look(72, 48, 32)
		local LIGHT = look(222, 196, 154)
		local LIGHT_SHADE = look(188, 160, 122)
		local BAR = look(110, 76, 48)
		local FACE = look(236, 214, 176)
		local RIM = look(64, 42, 28)
		local TALON = rgb(44, 36, 32)
		local BEAK = rgb(58, 54, 56)
		local IRIS = rgb(255, 156, 32)
		local CAP = rgb(214, 52, 44)
		local SPOT = rgb(252, 244, 232)
		local STALK = rgb(240, 228, 206)

		local tones = {
			[BROWN] = { top = BROWN_TOP, under = BROWN_UNDER },
			[LIGHT] = { under = LIGHT_SHADE },
		}

		-- A tall egg of a body: a pale barred chest, speckled brown back.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 11.6, 0 }, { 6.4, 7.8, 5.8 }), BROWN)
		body:add(ellipsoid({ 0, 8.6, 0.8 }, { 5.8, 5.6, 5.2 }), BROWN)
		body:coat(function(p, open)
			local x, y = p[1], p[2]
			if (open(0, 0, 1) or p[3] > 2.2) and math.abs(x) < 4.9 and y < 17 then
				-- Dark chevrons across the chest.
				if (y + math.abs(x) * 0.55) % 3.2 < 0.8 then
					return BAR
				end
				return LIGHT
			end
			if noise(p) < 0.05 then
				return LIGHT
			end
			return nil
		end)
		body:bake(tones)

		-- A broad head: a pale facial disc round each eye in a dark rim, a frowning brow.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 22.4, 0.4 }, { 6.8, 5.8, 5.6 }), BROWN)
		head:add(ellipsoid({ 0, 19.6, 0.6 }, { 5.8, 3.2, 4.8 }), BROWN)
		head:coat(function(p, open)
			local x, y = p[1], p[2]
			if open(0, 0, 1) or p[3] > 3.4 then
				local near = math.min((x - 2.5) ^ 2 + ((y - 22) * 1.05) ^ 2, (x + 2.5) ^ 2 + ((y - 22) * 1.05) ^ 2)
				if near < 3.4 ^ 2 then
					return FACE
				elseif near < 4.3 ^ 2 then
					return RIM
				end
			end
			if noise(p) < 0.14 then
				return LIGHT
			end
			return nil
		end)
		head:bake(tones)

		-- Feathered legs and big feet.
		local leg = newSculpt(U)
		leg:add(ellipsoid({ 2.6, 3.8, 1.4 }, { 2.1, 2.6, 2.1 }), LIGHT)
		for _, dx in { -1, 0, 1 } do
			leg:add(rod({ { 2.6 + dx * 0.4, 1.4, 2, 0.8 }, { 2.6 + dx * 1.3, 0.8, 4.2, 0.7 } }), LIGHT)
		end
		leg:bake(tones)

		-- Folded wings: barred coverts over the shoulder.
		local covert = newSculpt(U)
		covert:add(ellipsoid({ 6, 12.8, -0.8 }, { 1.6, 6, 4.6 }), BROWN)
		covert:coat(function(p)
			if p[2] < 14 and math.floor((p[2] + 30) / 2.2) % 2 == 0 then
				return LIGHT
			end
			if noise(p) < 0.12 then
				return LIGHT
			end
			return nil
		end)
		covert:bake(tones)

		local legMirror, covertMirror = leg:mirror(), covert:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 6, 0 }))
		body:draw(bodyLimb, { head, leg, legMirror, covert, covertMirror }, BROWN)

		local headLimb = pet:limb("Head", T.at({ 0, 17, 0 }))
		head:draw(headLimb, { body }, BROWN)
		for _, s in { 1, -1 } do
			-- Huge glowing amber eyes, each with a big black pupil and a glint.
			local face = frontOf(head, 2.5 * s, 22.2)
			T.ball(headLimb, { 2.5 * s, 22.2, face - 0.2 }, { 3.6, 3.6, 0.9 }, RIM.color)
			T.ball(headLimb, { 2.5 * s, 22.2, face + 0.05 }, { 3, 3, 0.8 }, IRIS, NEON)
			T.ball(headLimb, { 2.5 * s, 22.1, face + 0.3 }, { 1.7, 1.7, 0.6 }, EYE)
			T.ball(headLimb, { 2.15 * s, 22.7, face + 0.55 }, { 0.6, 0.6, 0.3 }, SHINE)
			-- A heavy frowning brow, pale above.
			T.blade(headLimb, { 0.5 * s, 24, face }, { 4.6 * s, 25.4, face - 1.2 }, 1, 0.9, { 0, 0.4, 1 }, DARK.color)
			T.blade(
				headLimb,
				{ 0.6 * s, 24.9, face - 0.3 },
				{ 4.2 * s, 26, face - 1.5 },
				0.7,
				0.7,
				{ 0, 0.4, 1 },
				LIGHT.color
			)
			-- Tall ear tufts of three feathers each.
			T.taper(headLimb, { 3.6 * s, 25.8, -0.2 }, { 6.6 * s, 32.4, -1.6 }, 1.8, 0.8, { 0, 0, 1 }, DARK.color)
			T.taper(headLimb, { 3 * s, 25.8, -1 }, { 5.4 * s, 31, -2.6 }, 1.6, 0.7, { 0, 0, 1 }, BROWN.color)
			T.taper(headLimb, { 4.2 * s, 25.2, 0.6 }, { 7.2 * s, 29.4, -0.2 }, 1.4, 0.6, { 0, 0, 1 }, BROWN_TOP.color)
			-- Feathery cheeks round the facial disc.
			T.taper(headLimb, { 5.6 * s, 20.6, 2 }, { 7.4 * s, 18.8, 0.2 }, 1.6, 0.7, { 0, 0, 1 }, BROWN.color)
		end
		-- A hooked beak between the eyes.
		local nose = frontOf(head, 0, 21)
		T.blade(headLimb, { 0, 21.6, nose - 0.4 }, { 0, 20, nose + 0.9 }, 1.3, 1.2, { 1, 0, 0 }, BEAK)
		T.taper(headLimb, { 0, 20, nose + 0.9 }, { 0, 18.2, nose + 1 }, 1.1, 1, { 1, 0, 0 }, BEAK)

		pet:limbPair("LeftWing", "RightWing", T.at({ 5.4, 16.6, 0 }), function(wing)
			covert:draw(wing, { body }, BROWN)
			-- Long barred flight feathers hanging down its sides and crossing at the back.
			for index, z in { 2.4, 1, -0.4, -1.8, -3.2, -4.6 } do
				Kit.feather(
					wing,
					T.at({ 6.5, 9.4, z }),
					{ 0.08, -1, -0.5 - index * 0.07 },
					7.4 / U,
					1.7 / U,
					0.55 / U,
					{ 1, 0, 0 },
					{
						{ color = DARK.color, to = 0.24 },
						{ color = LIGHT.color, to = 0.36 },
						{ color = BROWN.color, to = 0.6 },
						{ color = LIGHT.color, to = 0.72 },
						{ color = DARK.color, to = 1 },
					}
				)
			end
			-- Rows of shorter feathers over the top of the wing.
			for row, y in { 16.4, 13.6 } do
				for _, z in { 1.6, -0.6, -2.8 } do
					T.taper(
						wing,
						{ 7.3, y, z },
						{ 7.6, y - 3.6, z - 1.4 },
						2,
						0.6,
						{ 1, 0, 0 },
						if row == 1 then BROWN_TOP.color else DARK.color
					)
				end
			end
		end)
		-- Two little toadstools growing on its left shoulder.
		for index, at in { { 4.6, 18.6, -1.6, 1 }, { 3.2, 18.4, -3.6, 0.7 } } do
			local k = at[4]
			T.blade(
				bodyLimb,
				{ at[1], at[2] - 0.6, at[3] },
				{ at[1], at[2] + 1.6 * k, at[3] },
				0.8 * k,
				0.8 * k,
				{ 0, 0, 1 },
				STALK
			)
			T.ball(bodyLimb, { at[1], at[2] + 1.9 * k, at[3] }, { 3 * k, 1.6 * k, 3 * k }, CAP)
			for _, d in { { 0.7, 0.3 }, { -0.6, 0.5 }, { 0.1, -0.8 } } do
				T.ball(
					bodyLimb,
					{ at[1] + d[1] * k, at[2] + 2.55 * k, at[3] + d[2] * k },
					{ 0.5 * k, 0.3 * k, 0.5 * k },
					SPOT
				)
			end
			if index == 1 then
				T.ball(bodyLimb, { at[1], at[2] + 1.6 * k, at[3] }, { 2.4 * k, 0.5 * k, 2.4 * k }, STALK)
			end
		end

		pet:limbPair("LeftLeg", "RightLeg", T.at({ 2.6, 5, 1.4 }), function(limb)
			leg:draw(limb, { body }, BROWN)
			for _, dx in { -1, 0, 1 } do
				T.taper(limb, { 2.6 + dx * 1.3, 0.9, 3.9 }, { 2.6 + dx * 1.6, 0.2, 5.6 }, 0.6, 0.5, { 0, 1, 0 }, TALON)
			end
			T.taper(limb, { 2.6, 0.9, 0.6 }, { 2.6, 0.2, -0.8 }, 0.6, 0.5, { 0, 1, 0 }, TALON)
		end)

		-- A fan of barred tail feathers.
		local tail = pet:limb("Tail", T.at({ 0, 6, -4.4 }))
		for _, dx in { -2, -1, 0, 1, 2 } do
			Kit.feather(
				tail,
				T.at({ dx * 0.7, 6, -4.2 }),
				{ dx * 0.35, -0.75, -1 },
				5.4 / U,
				1.8 / U,
				0.55 / U,
				{ 0, 1, -0.6 },
				{
					{ color = DARK.color, to = 0.4 },
					{ color = LIGHT.color, to = 0.56 },
					{ color = DARK.color, to = 1 },
				}
			)
		end

		pet:seat(0, 18.6, -3)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Bear (Epic): a hulking grizzly, head low and snarling, with a shaggy mane over its shoulder hump, long pale claws,
-- glowing amber eyes, and moss on its back where little mushrooms glow, beside glowing claw-mark runes.

Forest.Bear = {
	name = "Bear",
	skeleton = "Strider",
	gait = "Stomp",
	scale = 0.3 * 1.25,
	draw = function(pet)
		-- Built in cells 1.25 design units across: it is big enough to keep its detail with fewer, larger blocks.
		local U = 1.25
		local T = inUnits(U)
		local FUR = look(120, 80, 50)
		local FUR_TOP = look(148, 102, 64)
		local FUR_UNDER = look(80, 52, 34)
		local FUR_LOW = look(86, 58, 38)
		local GRIZZLE = look(170, 128, 88)
		local GRIZZLE_TOP = look(194, 152, 108)
		local MUZZLE = look(176, 134, 92)
		local MUZZLE_SHADE = look(138, 100, 66)
		local MOSS = look(86, 140, 56)
		local MOSS_TOP = look(118, 172, 72)
		local MOUTH = look(120, 34, 42)
		local NOSE = look(34, 26, 24)
		local TONGUE = rgb(206, 90, 104)
		local TOOTH = rgb(246, 240, 224)
		local CLAW = rgb(232, 222, 200)
		local EYE_GLOW = rgb(255, 172, 40)
		local RUNE = rgb(80, 255, 196)
		local STALK = rgb(226, 236, 214)

		local tones = {
			[FUR] = { top = FUR_TOP, under = FUR_UNDER, low = FUR_LOW, below = 9 },
			[GRIZZLE] = { top = GRIZZLE_TOP, under = FUR },
			[MUZZLE] = { under = MUZZLE_SHADE },
			[MOSS] = { top = MOSS_TOP },
		}

		-- A massive body: a great hump over the shoulders, a deep chest and a heavy rump.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 18, -3 }, { 8, 8.2, 14 }), FUR)
		body:add(ellipsoid({ 0, 23.4, 4 }, { 7, 5.4, 7.4 }), FUR)
		body:add(ellipsoid({ 0, 17, 7 }, { 7.2, 8, 6.6 }), FUR)
		body:add(ellipsoid({ 0, 18.6, -12.6 }, { 7.6, 7.8, 6.6 }), FUR)
		body:add(rod({ { 0, 19, 10, 5.6 }, { 0, 19.6, 13.6, 4.8 } }), FUR)
		body:coat(function(p)
			local y, z = p[2], p[3]
			-- Silver-tipped (grizzled) fur over the hump and shoulders.
			if y > 22 and z > -2 and patches(p, 2.5) < 0.42 then
				return GRIZZLE
			end
			-- Moss growing over its back.
			if y > 20 and z < -1 and patches(p, 3.5) < 0.5 then
				return MOSS
			end
			return nil
		end)
		body:bake(tones)

		-- A broad, scarred head held low, with an open snarling mouth.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 20, 15.6 }, { 5.6, 5, 5.4 }), FUR)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 3.6 * s, 18.4, 15.2 }, { 3, 3.6, 3.4 }), FUR)
			head:add(ellipsoid({ 4.4 * s, 24.4, 13.6 }, { 1.9, 1.9, 1.3 }), FUR)
		end
		head:add(ellipsoid({ 0, 22.2, 18 }, { 4.6, 1.7, 2.8 }), FUR)
		head:add(rod({ { 0, 18.6, 18.6, 3.2 }, { 0, 18.2, 23.6, 2.5 } }), MUZZLE)
		head:add(rod({ { 0, 14.6, 17.6, 2.4 }, { 0, 14.2, 22.4, 1.9 } }), MUZZLE)
		head:add(ellipsoid({ 0, 19.4, 25 }, { 1.7, 1.2, 1.1 }), NOSE)
		head:carve(ellipsoid({ 0, 16.2, 23.4 }, { 2.4, 1.15, 3.4 }))
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if z > 18.4 and y > 14.6 and y < 17.4 and math.abs(x) < 2.3 then
				return MOUTH
			end
			if y > 21.5 and patches(p, 2) < 0.4 then
				return GRIZZLE
			end
			for _, s in { 1, -1 } do
				if (x - 4.4 * s) ^ 2 + (y - 24.4) ^ 2 < 1.4 and open(0, 0, 1) then
					return NOSE
				end
			end
			return nil
		end)
		head:bake(tones)

		-- Pillar legs with dark lower legs and broad paws.
		-- Each in two halves, bending at the elbow (or, behind, the knee).
		local front, frontShin = newSculpt(U), newSculpt(U)
		front:add(rod({ { 5.4, 19, 7, 3.8 }, { 5.8, 10, 8, 3.5 } }), FUR)
		frontShin:add(rod({ { 5.8, 10, 8, 3.45 }, { 5.8, 3.6, 8.8, 3 } }), FUR)
		frontShin:add(ellipsoid({ 5.8, 1.8, 10 }, { 3.4, 1.8, 3.9 }), FUR)
		local back, backShin = newSculpt(U), newSculpt(U)
		back:add(ellipsoid({ 5.4, 17, -12 }, { 3.6, 6.4, 5.4 }), FUR)
		back:add(rod({ { 5.6, 11, -13.2, 3.3 }, { 5.7, 7.6, -12.8, 3.1 } }), FUR)
		backShin:add(rod({ { 5.7, 7.6, -12.8, 3.05 }, { 5.8, 3.4, -12, 2.9 } }), FUR)
		backShin:add(ellipsoid({ 5.8, 1.8, -10.6 }, { 3.3, 1.8, 3.9 }), FUR)
		for _, s in { front, frontShin, back, backShin } do
			s:bake(tones)
		end

		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 22, -18.6 }, { 1.8, 1.8, 1.6 }), FUR)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 18, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, FUR)
		-- A shaggy mane of thick tufts over the neck and hump, lying back.
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return p[3] > -1 and p[2] > 20 and n[2] > 0.2 and noise(vadd(p, { 4, 7, 2 })) < 0.17
			end,
			3.6,
			2.4,
			{ 0, -0.1, -1.7 },
			function(p)
				return if noise(p) < 0.35 then GRIZZLE.color else FUR_TOP.color
			end
		)
		-- Glowing mushrooms in the moss on its back.
		for _, m in
			{ { 4.4, 23.6, -8, 1 }, { 5.6, 21.4, -11.4, 0.75 }, { -4.6, 23.8, -12.6, 0.9 }, { -5.4, 22.6, -6.4, 0.65 } }
		do
			local k = m[4]
			T.blade(
				bodyLimb,
				{ m[1], m[2] - 0.8, m[3] },
				{ m[1], m[2] + 1.4 * k, m[3] },
				0.7 * k,
				0.7 * k,
				{ 0, 0, 1 },
				STALK
			)
			T.ball(bodyLimb, { m[1], m[2] + 1.8 * k, m[3] }, { 2.6 * k, 1.3 * k, 2.6 * k }, RUNE, NEON)
		end
		-- Three glowing claw-mark runes raked across each shoulder.
		for _, s in { 1, -1 } do
			for i = -1, 1 do
				local z = 5 + i * 1.6
				T.blade(
					bodyLimb,
					{ 6.9 * s, 21.6, z + 1.4 },
					{ 7.9 * s, 15.6, z - 1.4 },
					0.55,
					0.4,
					{ s, 0.2, 0 },
					RUNE,
					NEON
				)
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 19, 12 }))
		head:draw(headLimb, { body }, FUR)
		-- Small, deep-set glowing eyes under a scowling brow.
		for _, s in { 1, -1 } do
			local x = sideOf(head, 21, 19.4) - 0.5
			T.ball(headLimb, { x * s, 21, 19.4 }, { 1.2, 1.3, 1.9 }, NOSE.color)
			T.ball(headLimb, { (x + 0.2) * s, 21, 19.6 }, { 1, 1, 1.5 }, EYE_GLOW, NEON)
			T.blade(headLimb, { 0.8 * s, 22.6, 20.2 }, { 4.6 * s, 23.2, 18.6 }, 1, 1, { 0, 0.5, 1 }, FUR_UNDER.color)
		end
		-- Fangs, teeth and a tongue in the open mouth.
		for _, s in { 1, -1 } do
			T.taper(headLimb, { 1.5 * s, 17.4, 25.2 }, { 1.4 * s, 14.9, 25.4 }, 0.8, 0.8, { 0, 0, 1 }, TOOTH)
			T.taper(headLimb, { 1.6 * s, 14.9, 23.6 }, { 1.5 * s, 16.6, 23.8 }, 0.7, 0.7, { 0, 0, 1 }, TOOTH)
			for i = 0, 2 do
				local z = 23.6 - i * 1.4
				T.taper(headLimb, { 2 * s, 17.4, z }, { 2 * s, 16.4, z }, 0.6, 0.6, { s, 0, 0 }, TOOTH)
			end
		end
		T.ball(headLimb, { 0, 15.2, 21.4 }, { 2.6, 0.8, 3.8 }, TONGUE)

		local function claws(limb: Limb, x: number, z: number, forward: number)
			for _, dx in { -1.6, -0.55, 0.55, 1.6 } do
				T.taper(
					limb,
					{ x + dx, 1.4, z },
					{ x + dx * 1.1, 0.2, z + 2.8 * forward },
					0.75,
					0.6,
					{ 0, 1, 0 },
					CLAW
				)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 5.4, 19, 7 }), function(limb)
			front:draw(limb, { body, frontShin }, FUR)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 5.8, 10, 8 }), function(limb)
			frontShin:draw(limb, { front }, FUR)
			claws(limb, 5.8, 12.6, 1)
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 5.4, 18, -12 }), function(limb)
			back:draw(limb, { body, backShin }, FUR)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 5.7, 7.6, -12.8 }), function(limb)
			backShin:draw(limb, { back }, FUR)
			claws(limb, 5.8, -8, 1)
		end, "BackLeftLeg")
		tail:draw(pet:limb("Tail", T.at({ 0, 22, -17.6 })), { body }, FUR)

		pet:seat(0, 26.4 / U, -4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Moss Stag (Legendary): a towering stag, its great branching antlers hung with moss and tipped with glowing
-- leaves, a shaggy moss mane down its neck and chest, a glowing vine rune winding along each flank, and glowing eyes.
-- Fireflies drift round it and a green aura swirls at its hooves.

Forest.MossStag = {
	name = "Moss Stag",
	skeleton = "Strider",
	scale = 0.3,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local COAT = look(150, 98, 60)
		local COAT_TOP = look(178, 124, 80)
		local COAT_UNDER = look(100, 64, 40)
		local COAT_LOW = look(118, 78, 50)
		local BELLY = look(232, 212, 178)
		local BELLY_SHADE = look(196, 174, 140)
		local MOSS = look(78, 136, 50)
		local MOSS_TOP = look(112, 172, 66)
		local MOSS_DARK = look(54, 98, 38)
		local HOOF = look(48, 38, 34)
		local NOSE = look(40, 30, 28)
		local ANTLER = rgb(214, 194, 152)
		local ANTLER_DARK = rgb(170, 146, 106)
		local GLOW = rgb(120, 255, 150)
		local STRAND = rgb(88, 150, 58)
		local STRAND_DARK = rgb(62, 112, 44)

		local tones = {
			[COAT] = { top = COAT_TOP, under = COAT_UNDER, low = COAT_LOW, below = 14 },
			[BELLY] = { under = BELLY_SHADE },
			[MOSS] = { top = MOSS_TOP, under = MOSS_DARK },
		}

		-- A deep-chested, long-legged body with a pale belly and moss across its shoulders and back.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 22, -2 }, { 5.4, 5.6, 11 }), COAT)
		body:add(ellipsoid({ 0, 22.4, 7 }, { 5.2, 6.4, 5.4 }), COAT)
		body:add(ellipsoid({ 0, 23, -10 }, { 5.4, 5.8, 5.2 }), COAT)
		body:add(rod({ { 0, 25, 8.6, 4.4 }, { 0, 28.4, 11.4, 3.6 }, { 0, 31, 13.2, 3.1 } }), COAT)
		body:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if open(0, -1, 0) or (y < 19.6 and math.abs(x) < 3.4) then
				return BELLY
			end
			-- A mossy mantle over the withers and down the neck.
			if y > 24 and z > -6 and patches(p, 3) < 0.62 then
				return MOSS
			end
			if y > 25.5 and z <= -6 and patches(p, 3) < 0.38 then
				return MOSS
			end
			return nil
		end)
		body:bake(tones)

		-- A long, noble head with a dark nose, held high.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 33, 15 }, { 3.2, 3.4, 4 }), COAT)
		head:add(rod({ { 0, 32.4, 16.4, 2.6 }, { 0, 31, 21.2, 1.8 } }), COAT)
		head:add(ellipsoid({ 0, 31.4, 21.8 }, { 1.5, 1.3, 1.1 }), NOSE)
		head:coat(function(p, open)
			if p[2] < 30.6 and p[3] > 17 then
				return BELLY
			end
			if open(0, 1, 0) and p[3] < 17 and patches(p, 1.5) < 0.4 then
				return MOSS
			end
			return nil
		end)
		head:bake(tones)

		-- Long slender legs on dark hooves, each in two halves that bend at the knee (or, behind, the hock).
		local front, frontShin = newSculpt(U), newSculpt(U)
		front:add(rod({ { 3.4, 22, 7, 2.4 }, { 3.6, 13, 7.8, 1.6 } }), COAT)
		frontShin:add(rod({ { 3.6, 13, 7.8, 1.55 }, { 3.5, 4.6, 7.2, 1.2 }, { 3.5, 1.6, 7.6, 1.15 } }), COAT)
		frontShin:add(ellipsoid({ 3.5, 0.9, 7.9 }, { 1.4, 0.9, 1.5 }), HOOF)
		local back, backShin = newSculpt(U), newSculpt(U)
		back:add(ellipsoid({ 3.6, 21.6, -10 }, { 2.5, 5.2, 4.2 }), COAT)
		back:add(rod({ { 3.6, 17, -11.6, 2.2 }, { 3.6, 9.6, -13.4, 1.5 } }), COAT)
		backShin:add(rod({ { 3.6, 9.6, -13.4, 1.45 }, { 3.5, 4.6, -12.2, 1.2 }, { 3.5, 1.6, -11.6, 1.15 } }), COAT)
		backShin:add(ellipsoid({ 3.5, 0.9, -11.3 }, { 1.4, 0.9, 1.5 }), HOOF)
		for _, s in { front, frontShin, back, backShin } do
			s:bake(tones)
		end

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 25.4, -14.6, 1.3 }, { 0, 24.2, -16.2, 1.1 } }), COAT)
		tail:coat(function(_, open)
			if not open(0, 1, 0) then
				return BELLY
			end
			return nil
		end)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 22, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, COAT)
		-- A shaggy moss mane: long strands hanging from under the neck and over the chest.
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return p[3] > 6 and p[2] > 17 and n[3] > 0.1 and n[2] < 0.5 and noise(vadd(p, { 6, 1, 3 })) < 0.3
			end,
			3.2,
			1.6,
			{ 0, -1.8, 0 },
			function(p)
				return if noise(p) < 0.5 then STRAND else STRAND_DARK
			end
		)
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return p[3] > -6 and p[2] > 26 and n[2] > 0.3 and noise(vadd(p, { 2, 5, 8 })) < 0.2
			end,
			2.4,
			1.6,
			{ 0, -0.2, -1.4 },
			function(p)
				return if noise(p) < 0.5 then MOSS_TOP.color else STRAND
			end
		)
		-- A glowing vine rune winding along each flank, from shoulder to hip, with leaves along it.
		for _, s in { 1, -1 } do
			local points: { Vec } = {}
			for i = 0, 10 do
				local z = 6 - i * 1.65
				local y = 22.4 + math.sin(i * 0.9) * 2.2
				table.insert(points, { (sideOf(body, y, z) + 0.15) * s, y, z })
			end
			for i = 1, #points - 1 do
				T.blade(bodyLimb, points[i], points[i + 1], 0.55, 0.3, { s, 0, 0 }, GLOW, NEON)
				if i % 3 == 1 then
					local p = points[i]
					local up = if i % 2 == 1 then 1 else -1
					T.triangle(
						bodyLimb,
						p,
						vadd(p, { 0.2 * s, 1.6 * up, -0.4 }),
						vadd(p, { 0.2 * s, 0.6 * up, -1.8 }),
						0.25,
						GLOW,
						NEON
					)
				end
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 30, 13 }))
		head:draw(headLimb, { body }, COAT)
		Kit.slitEyes(headLimb, head, { 34, 18.2 }, { 34.4, 16.2 }, 0.9, GLOW, NEON, rgb(30, 24, 20))
		for _, s in { 1, -1 } do
			-- Long ears turned out to the side.
			T.taper(headLimb, { 2.4 * s, 35, 13.4 }, { 6.4 * s, 36.4, 12 }, 1.8, 0.7, { 0, 1, 0.2 }, COAT.color)
			T.taper(headLimb, { 2.6 * s, 35.3, 13.4 }, { 6 * s, 36.5, 12.2 }, 1, 0.3, { 0, 1, 0.2 }, BELLY.color)
		end

		-- Great branching antlers: pale, mossy at the base, each tine ending in a glowing leaf, with moss hanging off.
		local function tine(from: Vec, to: Vec, width: number)
			T.blade(headLimb, from, to, width, width, { 0, 0, 1 }, ANTLER)
			T.taper(
				headLimb,
				to,
				vadd(to, vscale(vnorm({ to[1] - from[1], to[2] - from[2], to[3] - from[3] }), 1.6)),
				width * 0.8,
				width * 0.8,
				{ 0, 0, 1 },
				GLOW,
				NEON
			)
		end
		for _, s in { 1, -1 } do
			local beam: { Vec } = {
				{ 1.6 * s, 35.4, 14 },
				{ 4 * s, 39.6, 12.4 },
				{ 7.4 * s, 44, 11.2 },
				{ 9.6 * s, 48.6, 11.6 },
				{ 11 * s, 52.6, 13 },
			}
			for i = 1, #beam - 1 do
				T.blade(
					headLimb,
					beam[i],
					beam[i + 1],
					1.5 - i * 0.18,
					1.5 - i * 0.18,
					{ 0, 0, 1 },
					if i == 1 then MOSS.color else ANTLER
				)
			end
			T.taper(headLimb, beam[#beam], { 11.6 * s, 55.4, 14.6 }, 0.8, 0.8, { 0, 0, 1 }, GLOW, NEON)
			-- Tines: a brow tine forward, then up and out along the beam.
			tine(beam[2], { 4.2 * s, 41.6, 16.6 }, 0.9)
			tine(beam[3], { 6.4 * s, 49, 14.4 }, 0.85)
			tine(beam[3], { 10.6 * s, 46.2, 8.4 }, 0.75)
			tine(beam[4], { 8.6 * s, 53.4, 12.4 }, 0.75)
			tine(beam[4], { 13.4 * s, 50.6, 9.8 }, 0.7)
			T.blade(headLimb, beam[2], beam[3], 1.3, 0.4, { 0, 0, 1 }, ANTLER_DARK)
			-- Moss hanging in strands off the antlers.
			for _, h in
				{ { 5.4, 41.4, 12, 3.6 }, { 8.4, 45.6, 11.4, 4.4 }, { 10.2, 49.6, 12, 3.2 }, { 3, 37.6, 13.2, 2.4 } }
			do
				local top = { h[1] * s, h[2], h[3] }
				T.blade(headLimb, top, vadd(top, { 0.3 * s, -h[4] * 0.6, 0.1 }), 0.7, 0.5, { 0, 0, 1 }, STRAND)
				T.taper(
					headLimb,
					vadd(top, { 0.3 * s, -h[4] * 0.6, 0.1 }),
					vadd(top, { 0.5 * s, -h[4], 0.3 }),
					0.6,
					0.45,
					{ 0, 0, 1 },
					STRAND_DARK
				)
			end
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.4, 22, 7 }), function(limb)
			front:draw(limb, { body, frontShin }, COAT)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 3.6, 13, 7.8 }), function(limb)
			frontShin:draw(limb, { front }, COAT)
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3.6, 22, -10 }), function(limb)
			back:draw(limb, { body, backShin }, COAT)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 3.6, 9.6, -13.4 }), function(limb)
			backShin:draw(limb, { back }, COAT)
		end, "BackLeftLeg")
		tail:draw(pet:limb("Tail", T.at({ 0, 25, -14 })), { body }, COAT)

		pet:light(GLOW, 1.6, 18)
		pet:particles("Fireflies", rgb(210, 255, 120), 8)
		pet:aura(rgb(90, 230, 120), rgb(220, 255, 180))
		pet:seat(0, 28, -3)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Treant (Mythic): a walking oak four times a player's height. Grooved bark split by glowing green cracks, a glowing
-- heart in a hollow of its chest, knots of glowing sap (like its egg), a scowling face with glowing eyes, a crown of
-- leaves in blossom, moss on its shoulders, twig fingers, and roots for feet.

Forest.Treant = {
	name = "Treant",
	skeleton = "Giant",
	gait = "Stomp",
	scale = 0.32 * 1.5,
	draw = function(pet)
		-- Built in cells 1.5 design units across: at its size the bark keeps its grooves with fewer, larger blocks.
		local U = 1.5
		local T = inUnits(U)
		local BARK = look(112, 80, 54)
		local BARK_TOP = look(140, 104, 72)
		local BARK_UNDER = look(74, 52, 36)
		local GROOVE = look(66, 46, 32)
		local LIGHT_BARK = look(150, 116, 82)
		local GLOW = look(130, 255, 120, NEON)
		local HOLLOW = look(40, 30, 24)
		local MOSS = look(80, 138, 52)
		local MOSS_TOP = look(114, 174, 66)
		local LEAF = look(70, 148, 58)
		local LEAF_TOP = look(108, 186, 72)
		local LEAF_DARK = look(44, 104, 42)
		local SAP = rgb(255, 176, 48)
		local BLOSSOM = rgb(255, 196, 220)
		local BLOSSOM_DEEP = rgb(244, 132, 176)
		local TWIG = rgb(96, 68, 46)
		local STRAND = rgb(86, 146, 56)

		local tones = {
			[BARK] = { top = BARK_TOP, under = BARK_UNDER },
			[MOSS] = { top = MOSS_TOP },
			[LEAF] = { top = LEAF_TOP, under = LEAF_DARK },
		}

		-- Bark with deep grooves running up it, wandering a little, and paler ridges between them.
		local function bark(p: Vec, centre: Vec): Look?
			local angle = math.atan2(p[3] - centre[3], p[1] - centre[1])
			local wave = math.sin(angle * 7 + p[2] * 0.22 + math.sin(p[2] * 0.4) * 0.6)
			if wave > 0.72 then
				return GROOVE
			elseif wave < -0.85 then
				return LIGHT_BARK
			end
			return nil
		end

		-- Glowing cracks across the chest and up the trunk: paths of points, and whether a cell is on one.
		local cracks = {
			{ { -4.6, 26, 7 }, { -2.4, 30, 7.6 }, { -3.4, 33.4, 8 }, { -1.4, 37, 8.4 } },
			{ { 5.2, 28, 6.6 }, { 3, 31.6, 7.4 }, { 4.4, 35, 7.8 }, { 2.6, 39, 8.4 }, { 4.6, 43, 8 } },
			{ { -6.4, 41, 6.4 }, { -4.6, 44, 7.4 }, { -6, 47.4, 6.8 } },
			{ { 7.8, 31, -2 }, { 8.6, 35, -4 }, { 8, 39, -6 } },
			{ { -8, 30, -3 }, { -8.6, 34.6, -5 }, { -7.4, 38.4, -6.6 } },
		}
		local function onCrack(p: Vec): boolean
			for _, path in cracks do
				for i = 1, #path - 1 do
					local a, c = path[i], path[i + 1]
					local t = math.clamp((p[2] - a[2]) / (c[2] - a[2]), 0, 1)
					if p[2] >= a[2] - 0.5 and p[2] <= c[2] + 0.5 then
						local x, z = a[1] + (c[1] - a[1]) * t, a[3] + (c[3] - a[3]) * t
						if (p[1] - x) ^ 2 + (p[3] - z) ^ 2 < 1.1 then
							return true
						end
					end
				end
			end
			return false
		end

		-- The trunk: broad at the hips, broader at the shoulders, with a yoke of shoulders to sit on behind its head.
		local body = newSculpt(U)
		body:add(rod({ { 0, 20, 0, 7.6 }, { 0, 32, 0.6, 8.4 }, { 0, 44, 0, 9.2 } }), BARK)
		body:add(ellipsoid({ 0, 47.6, -0.4 }, { 12.4, 5.4, 7.6 }), BARK)
		body:add(ellipsoid({ 0, 18.6, 0 }, { 8.6, 4, 6.4 }), BARK)
		-- A hollow in its chest, holding its glowing heart.
		body:carve(ellipsoid({ 0, 35, 8.2 }, { 3.6, 4.4, 3.4 }))
		body:coat(function(p)
			local x, y, z = p[1], p[2], p[3]
			if
				z > 4.5
				and math.abs(x) < 4.6
				and math.abs(y - 35) < 5.4
				and (x * x / 13 + (y - 35) ^ 2 / 19.4) < 1.6
			then
				return HOLLOW
			end
			if onCrack(p) then
				return GLOW
			end
			if y > 48 and patches(p, 3) < 0.6 then
				return MOSS
			end
			return bark(p, { 0, y, 0 })
		end)
		body:bake(tones)

		-- The head: the top of the trunk, with a heavy brow over glowing eyes, a dark mouth, and a crown of leaves.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 55.6, 2.2 }, { 6.6, 7, 6 }), BARK)
		head:add(ellipsoid({ 0, 58.4, 4.8 }, { 6.2, 1.8, 2.6 }), BARK)
		head:carve(ellipsoid({ 0, 51.8, 7.6 }, { 2.8, 1.3, 1.6 }))
		for _, s in { 1, -1 } do
			head:carve(ellipsoid({ 2.6 * s, 56, 7.6 }, { 1.6, 1.2, 1.2 }))
		end
		-- The canopy: clumps of leaves piled into a crown.
		local canopy = {
			{ 0, 67, 0, 9, 6.4, 8.2 },
			{ 7, 64, 0.6, 5.8, 5, 5.8 },
			{ -7, 64.4, -0.4, 6, 5, 5.6 },
			{ 2.8, 72, -2.4, 5.6, 4.6, 5.2 },
			{ -3.4, 71.4, 2.8, 5.2, 4.4, 5 },
			{ 0, 75.4, 0, 4.4, 3.4, 4.2 },
			{ 0, 64, -6, 6.4, 4.6, 4.4 },
			{ 0, 64.4, 6.4, 5.4, 3.8, 3.4 },
			{ 10.2, 61, -2.4, 3.8, 3.4, 4 },
			{ -10.4, 61.4, 1.4, 3.8, 3.4, 4 },
		}
		for _, c in canopy do
			head:add(ellipsoid({ c[1], c[2], c[3] }, { c[4], c[5], c[6] }), LEAF)
		end
		head:coat(function(p)
			local x, y, z = p[1], p[2], p[3]
			if y > 59.6 then
				return nil
			end
			if z > 6 and math.abs(x) < 2.8 and y > 50.2 and y < 53.4 then
				return HOLLOW
			end
			for _, s in { 1, -1 } do
				if (x - 2.6 * s) ^ 2 + (y - 56) ^ 2 < 3.2 and z > 6 then
					return HOLLOW
				end
			end
			if y < 51 and patches(p, 2) < 0.45 then
				return MOSS
			end
			return bark(p, { 0, y, 2.2 })
		end)
		head:coat(function(p)
			if p[2] > 59.6 and patches(p, 2.2) < 0.36 then
				return LEAF_DARK
			end
			return nil
		end)
		head:bake(tones)

		-- Branch arms ending in long twig fingers.
		-- The forearm (from the elbow down) and the shin (from the knee down) are limbs of their own, so they bend.
		local arm, forearm = newSculpt(U), newSculpt(U)
		arm:add(ellipsoid({ 11, 46.6, -0.4 }, { 4.4, 4.6, 4.6 }), BARK)
		arm:add(rod({ { 11.6, 45, 0, 3.8 }, { 13.4, 36, 1.6, 3.2 } }), BARK)
		forearm:add(rod({ { 13.4, 36, 1.6, 3.15 }, { 14, 27, 3.6, 2.7 }, { 14, 23.6, 4.6, 2.5 } }), BARK)
		for _, s in { arm, forearm } do
			s:coat(function(p)
				if p[2] > 48 and patches(p, 2.5) < 0.6 then
					return MOSS
				end
				return bark(p, { 13, p[2], 2 })
			end)
			s:bake(tones)
		end

		-- Root legs on feet of spreading roots.
		local leg, shin = newSculpt(U), newSculpt(U)
		leg:add(rod({ { 5, 20, 0, 4.6 }, { 6, 11, 0.8, 4.2 } }), BARK)
		shin:add(rod({ { 6, 11, 0.8, 4.15 }, { 6.6, 4.4, 0.4, 4.4 } }), BARK)
		for _, r in { { 3.6, 4.6 }, { 0.6, 6.6 }, { -2.8, 5 }, { -3.4, -1 }, { 3.6, -4.6 } } do
			shin:add(
				rod({
					{ 6.6, 3, 0.4, 2.6 },
					{ 6.6 + r[1] * 0.6, 1.6, 0.4 + r[2] * 0.6, 1.8 },
					{ 6.6 + r[1], 1, 0.4 + r[2], 1.1 },
				}),
				BARK
			)
		end
		for _, s in { leg, shin } do
			s:coat(function(p)
				return bark(p, { 6.4, p[2], 0.4 })
			end)
			s:bake(tones)
		end

		local armMirror, legMirror = arm:mirror(), leg:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 20, 0 }))
		body:draw(bodyLimb, { head, arm, armMirror, leg, legMirror }, BARK)
		-- The glowing heart in its chest: a core of light in a cage of roots.
		T.ball(bodyLimb, { 0, 35, 6.4 }, { 4.6, 5.4, 3.6 }, GLOW.color, NEON)
		T.ball(bodyLimb, { 0, 35, 7.6 }, { 2.4, 2.8, 2 }, rgb(236, 255, 214), NEON)
		for _, a in { -1, 1 } do
			T.blade(bodyLimb, { a * 1.8, 40.6, 8.4 }, { a * 3, 29.6, 8.6 }, 0.8, 0.8, { 0, 0, 1 }, TWIG)
		end
		-- Knots of glowing sap in the bark.
		for _, k in { { -6.4, 27, 4.4 }, { 7, 40, 4.6 }, { -3.8, 45, -7.4 }, { 5.4, 24, -5 }, { -8.2, 37, 1.6 } } do
			local out = vnorm({ k[1], 0, k[3] })
			T.ball(bodyLimb, vadd(k, vscale(out, 2)), { 3, 3.4, 3 }, GROOVE.color)
			T.ball(bodyLimb, vadd(k, vscale(out, 2.9)), { 1.9, 2.3, 1.9 }, SAP, NEON)
		end
		-- Moss hanging off its shoulders.
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return p[2] > 45 and n[2] > -0.1 and n[2] < 0.6 and noise(vadd(p, { 3, 3, 9 })) < 0.25
			end,
			3.4,
			1.4,
			{ 0, -2, 0 },
			function(p)
				return if noise(p) < 0.5 then STRAND else MOSS.color
			end
		)

		local headLimb = pet:limb("Head", T.at({ 0, 51, 1 }))
		head:draw(headLimb, { body }, BARK)
		-- Glowing eyes deep in their hollows, and a glow in its mouth.
		for _, s in { 1, -1 } do
			T.ball(headLimb, { 2.6 * s, 56, 7 }, { 2, 1.5, 1 }, GLOW.color, NEON)
			-- A heavy, knotted brow.
			T.blade(headLimb, { 0.4 * s, 58.4, 7.6 }, { 5.4 * s, 57.2, 6.4 }, 1.4, 1.2, { 0, 0.3, 1 }, BARK_UNDER.color)
			-- Twigs and leaves sticking out of the crown.
			T.branch(
				headLimb,
				{ { 6.8 * s, 60, 3 }, { 10.8 * s, 63.6, 5.6 }, { 13.4 * s, 66.6, 5 } },
				1,
				{ 0, 0, 1 },
				TWIG
			)
			T.triangle(
				headLimb,
				{ 13.4 * s, 66.6, 5 },
				{ 15.6 * s, 67.6, 6.6 },
				{ 14 * s, 69, 4.4 },
				0.3,
				LEAF_TOP.color
			)
		end
		T.ball(headLimb, { 0, 51.8, 6.6 }, { 3.6, 1.4, 2 }, GLOW.color, NEON)
		-- A beard of moss hanging from its chin.
		for _, x in { -2.4, -0.8, 0.8, 2.4 } do
			local top = { x, 49.8, 6.4 - math.abs(x) * 0.3 }
			T.taper(headLimb, top, vadd(top, { x * 0.15, -4 - math.abs(x) * 0.2, 0.6 }), 1.2, 0.6, { 0, 0, 1 }, STRAND)
		end
		-- Blossoms dotted over the crown.
		for _, spot in
			head:surface(function(p, n)
				return p[2] > 61 and n[2] > -0.2 and noise(vadd(p, { 7, 7, 7 })) < 0.07
			end)
		do
			local p, n = spot[1], spot[2]
			local c = vadd(p, vscale(n, 0.5))
			T.ball(headLimb, c, { 1.4, 1.4, 1.4 }, if noise(p) < 0.5 then BLOSSOM else BLOSSOM_DEEP)
			T.ball(headLimb, vadd(c, vscale(n, 0.5)), { 0.6, 0.6, 0.6 }, SAP)
		end

		pet:limbPair("LeftArm", "RightArm", T.at({ 11, 46, -0.4 }), function(limb)
			arm:draw(limb, { body, forearm }, BARK)
			-- A leafy twig growing from the elbow.
			T.branch(limb, { { 14, 37, 0 }, { 17.4, 40.6, -1.6 }, { 18.6, 43.6, -1 } }, 0.9, { 0, 0, 1 }, TWIG)
			T.triangle(limb, { 18.6, 43.6, -1 }, { 20.4, 45, 0 }, { 18.4, 46, -1.8 }, 0.3, LEAF.color)
			T.triangle(limb, { 17.4, 40.6, -1.6 }, { 19.6, 40.2, -3.4 }, { 18.6, 42.4, -3.2 }, 0.3, LEAF_TOP.color)
		end)
		pet:limbPair("LeftForearm", "RightForearm", T.at({ 13.4, 36, 1.6 }), function(limb)
			forearm:draw(limb, { arm }, BARK)
			-- Long twig fingers.
			for _, f in { { -1.6, -0.6 }, { 0, 0.2 }, { 1.6, -0.4 }, { 1.2, 1.6 } } do
				local root = { 14 + f[2] * 0.6, 22.6, 4.6 + f[1] }
				local knuckle = vadd(root, { f[2] * 1.2, -3.2, f[1] * 0.4 + 0.6 })
				T.blade(limb, root, knuckle, 1.2, 1.1, { 1, 0, 0 }, TWIG)
				T.taper(limb, knuckle, vadd(knuckle, { f[2] * 0.6, -3, 1.4 }), 1, 0.9, { 1, 0, 0 }, TWIG)
			end
		end, "LeftArm")
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 5, 20, 0 }), function(limb)
			leg:draw(limb, { body, shin }, BARK)
		end)
		pet:limbPair("LeftShin", "RightShin", T.at({ 6, 11, 0.8 }), function(limb)
			shin:draw(limb, { leg }, BARK)
		end, "LeftLeg")

		pet:light(rgb(150, 255, 130), 2.4, 24)
		pet:particles("Fireflies", rgb(220, 255, 130), 14)
		pet:aura(rgb(90, 230, 110), rgb(255, 210, 120))
		pet:seat(0, 53 / U, -4.6 / U)
	end,
}

return Forest
