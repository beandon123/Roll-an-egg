--!strict
-- The Snow zone's pets, in the showpiece style (see PetModels/Forest for what that means): sculpted fine in voxels
-- with light baked in from above, crisp angled parts for claws, fangs, antlers, tusks and tufts of fur, and, the rarer
-- they are, more that glows: a red nose, then ice crystals, frost stripes, aurora feathers and auras, up to the Secret
-- Yeti, a king of the mountains crowned with horns and crystal.
-- Sizes run from about a player's height (the hare) to five times it (the Yeti).
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
local nearPath = Kit.nearPath
local glossyEye = Kit.glossyEye
local fur = Kit.fur
local crystal = Kit.crystal
local crystalCluster = Kit.crystalCluster

local NEON = Kit.NEON
local EYE = Kit.EYE

local Snow: { [string]: Design } = {}

----------------------------------------------------------------------------------------------------------------
-- Snow Hare (Uncommon): a snowshoe hare in its white winter coat, about a player's height, with long black-tipped
-- ears, a fluffy ruff and great furry snowshoe feet.

Snow.SnowHare = {
	name = "Snow Hare",
	skeleton = "Quadruped",
	gait = "Hop",
	scale = 0.22,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local WHITE = look(246, 249, 255)
		local WHITE_TOP = look(255, 255, 255)
		local SHADE = look(200, 214, 236)
		local SHADE_LOW = look(220, 230, 246)
		local TIP = look(44, 46, 58)
		local INNER = rgb(246, 180, 192)
		local NOSE = rgb(232, 130, 150)
		local IRIS = rgb(46, 40, 52)
		local WHISKER = rgb(150, 160, 180)

		local tones = {
			[WHITE] = { top = WHITE_TOP, under = SHADE, low = SHADE_LOW, below = 2.4 },
		}

		-- A lean body, high at the hips.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 8, -1.4 }, { 3.4, 3.6, 5.2 }), WHITE)
		body:add(ellipsoid({ 0, 9, -3.4 }, { 3.6, 3.6, 3.4 }), WHITE)
		body:add(ellipsoid({ 0, 8.6, 2.4 }, { 3, 3.4, 3 }), WHITE)
		body:add(rod({ { 0, 9.6, 3, 2.4 }, { 0, 11.2, 4.6, 2.2 } }), WHITE)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 12.6, 5.4 }, { 2.9, 2.8, 3.2 }), WHITE)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 1.4 * s, 11.4, 6.6 }, { 1.9, 1.7, 1.9 }), WHITE)
		end
		head:add(ellipsoid({ 0, 11.6, 8 }, { 1.5, 1.3, 1.3 }), WHITE)
		head:bake(tones)

		local front = newSculpt(U)
		front:add(rod({ { 2, 8, 2.4, 1.25 }, { 2.1, 4.4, 3.2, 1 }, { 2, 1.2, 3.8, 0.95 } }), WHITE)
		front:add(ellipsoid({ 2, 0.75, 4.4 }, { 1.1, 0.75, 1.4 }), WHITE)
		front:bake(tones)

		-- Big haunches on long, wide, furry snowshoe feet.
		local back = newSculpt(U)
		back:add(ellipsoid({ 2.8, 7.2, -3.4 }, { 2, 3.6, 3.8 }), WHITE)
		back:add(rod({ { 2.8, 4.2, -5.4, 1.4 }, { 2.8, 1.4, -6, 1.15 } }), WHITE)
		back:add(ellipsoid({ 2.9, 0.9, -2.8 }, { 1.7, 0.9, 4 }), WHITE)
		back:bake(tones)

		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 8.8, -6.8 }, { 1.4, 1.5, 1.3 }), WHITE)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 8, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, WHITE)
		-- A fluffy ruff of winter fur round its chest.
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return p[3] > 2 and n[3] > 0.2 and noise(vadd(p, { 4, 4, 1 })) < 0.3
			end,
			1.4,
			0.9,
			{ 0, -0.6, 0 },
			function()
				return WHITE_TOP.color
			end
		)

		local headLimb = pet:limb("Head", T.at({ 0, 10.8, 4 }))
		head:draw(headLimb, { body }, WHITE)
		glossyEye(headLimb, T, head, 13, 6.8, 1.7, nil, IRIS)
		T.ball(headLimb, { 0, 12.2, 9.1 }, { 1, 0.7, 0.6 }, NOSE)
		for _, s in { 1, -1 } do
			-- Long ears laid back, pink inside, tipped in black.
			local root, mid, top = { 1.2 * s, 14.4, 4.4 }, { 1.9 * s, 18.4, 2.6 }, { 2.3 * s, 21.6, 1 }
			T.blade(headLimb, root, mid, 2.1, 0.8, { 0, 0.4, 1 }, WHITE.color)
			T.blade(headLimb, mid, top, 1.9, 0.75, { 0, 0.4, 1 }, WHITE.color)
			T.taper(headLimb, top, { 2.5 * s, 23.4, 0.2 }, 1.8, 0.7, { 0, 0.4, 1 }, TIP.color)
			T.blade(headLimb, { 1.3 * s, 15, 4.75 }, { 2.1 * s, 20.6, 2.25 }, 1.1, 0.3, { 0, 0.4, 1 }, INNER)
			for _, dy in { -0.2, 0.3 } do
				T.blade(
					headLimb,
					{ 0.8 * s, 11.6 + dy, 8.6 },
					{ 3.4 * s, 11.8 + dy * 2.4, 8.4 },
					0.1,
					0.1,
					{ 0, 1, 0 },
					WHISKER
				)
			end
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 2, 7.8, 2.4 }), function(limb)
			front:draw(limb, { body }, WHITE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 2.8, 7.6, -3.4 }), function(limb)
			back:draw(limb, { body }, WHITE)
			-- Fur fringing its snowshoe toes.
			for _, dx in { -0.7, 0, 0.7 } do
				T.taper(
					limb,
					{ 2.9 + dx, 0.7, 0.8 },
					{ 2.9 + dx * 1.3, 0.3, 2.2 },
					0.8,
					0.5,
					{ 0, 1, 0 },
					WHITE_TOP.color
				)
			end
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 8.8, -6 })), { body }, WHITE)

		pet:seat(0, 12.4, -1.6)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Arctic Fox (Uncommon): a round, fluffy white fox in its thick winter coat, with a deep ruff, short rounded ears and
-- a huge bushy tail swept round behind it.

Snow.ArcticFox = {
	name = "Arctic Fox",
	skeleton = "Quadruped",
	scale = 0.23,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local WHITE = look(244, 248, 255)
		local WHITE_TOP = look(255, 255, 255)
		local SHADE = look(196, 212, 236)
		local SHADE_LOW = look(214, 226, 244)
		local FROST = look(176, 204, 236)
		local NOSE = rgb(40, 44, 56)
		local IRIS = rgb(214, 160, 70)
		local INNER = rgb(200, 210, 230)

		local tones = {
			[WHITE] = { top = WHITE_TOP, under = SHADE, low = SHADE_LOW, below = 3 },
		}

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 8.8, -1.2 }, { 3.8, 3.6, 6 }), WHITE)
		body:add(ellipsoid({ 0, 9.4, 3 }, { 3.8, 4, 3.4 }), WHITE)
		body:add(rod({ { 0, 10.4, 4, 3 }, { 0, 12, 6, 2.6 } }), WHITE)
		body:bake(tones)

		-- A short, rounded head with a pointed muzzle.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 13.4, 7 }, { 3.3, 3, 3.1 }), WHITE)
		head:add(ellipsoid({ 0, 12.4, 7.4 }, { 3.8, 2.1, 2.5 }), WHITE)
		head:add(rod({ { 0, 12.6, 8.6, 1.7 }, { 0, 12.2, 11.4, 0.85 } }), WHITE)
		head:coat(function(p)
			if p[3] > 10.6 and p[2] < 12.4 then
				return FROST
			end
			return nil
		end)
		head:bake(tones)

		local function leg(s: Sculpt, top: Vec, knee: Vec, foot: Vec)
			s:add(
				rod({
					{ top[1], top[2], top[3], 1.7 },
					{ knee[1], knee[2], knee[3], 1.2 },
					{ foot[1], 1.2, foot[3], 1 },
				}),
				WHITE
			)
			s:add(ellipsoid({ foot[1], 0.75, foot[3] + 0.4 }, { 1.15, 0.75, 1.5 }), WHITE)
			s:bake(tones)
		end
		local front, back = newSculpt(U), newSculpt(U)
		leg(front, { 2.3, 8.4, 3.6 }, { 2.4, 4.6, 3.8 }, { 2.3, 1, 4 })
		back:add(ellipsoid({ 2.6, 8.8, -5 }, { 1.8, 3, 3.2 }), WHITE)
		leg(back, { 2.6, 7.6, -5.4 }, { 2.5, 4.2, -6.4 }, { 2.4, 1, -5.4 })

		-- A huge bushy tail, swept out behind and curving round.
		local spine = {
			{ 0, 9.6, -7.2, 1.8 },
			{ 0, 9, -10.6, 3 },
			{ 1.6, 7.6, -14, 3.3 },
			{ 4, 6.6, -16, 2.8 },
			{ 6.4, 6.4, -16.4, 1.6 },
		}
		local tail = newSculpt(U)
		tail:add(rod(spine), WHITE)
		tail:coat(function(p)
			local d, r = nearPath(spine, p)
			if d < r * 0.7 then
				return nil
			end
			if patches(p, 1.6) < 0.3 then
				return FROST
			end
			return nil
		end)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 9, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, WHITE)
		-- A deep ruff of fur round its neck and chest.
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return p[3] > 2.4 and n[2] < 0.6 and noise(vadd(p, { 1, 6, 2 })) < 0.38
			end,
			1.8,
			1.1,
			{ 0, -0.5, 0.2 },
			function(p)
				return if noise(p) < 0.6 then WHITE_TOP.color else FROST.color
			end
		)

		local headLimb = pet:limb("Head", T.at({ 0, 11.8, 5.6 }))
		head:draw(headLimb, { body }, WHITE)
		glossyEye(headLimb, T, head, 13.8, 9, 1.4, rgb(40, 40, 52), IRIS, nil, rgb(24, 22, 28))
		T.ball(headLimb, { 0, 12.5, 11.9 }, { 0.9, 0.7, 0.6 }, NOSE)
		for _, s in { 1, -1 } do
			-- Short, rounded ears.
			T.taper(headLimb, { 1.9 * s, 15.6, 6.6 }, { 2.6 * s, 18, 6 }, 2.2, 1, { 0, 0, 1 }, WHITE.color)
			T.taper(headLimb, { 1.95 * s, 15.9, 7.15 }, { 2.5 * s, 17.4, 6.6 }, 1.2, 0.3, { 0, 0, 1 }, INNER)
			-- Fluffy cheeks.
			T.taper(headLimb, { 2.8 * s, 12.6, 7.4 }, { 4.6 * s, 11.8, 5.8 }, 1.6, 0.9, { 0, 1, 0 }, WHITE_TOP.color)
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 2.3, 8.4, 3.6 }), function(limb)
			front:draw(limb, { body }, WHITE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 2.6, 8.8, -5 }), function(limb)
			back:draw(limb, { body }, WHITE)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 9.6, -6.8 }))
		tail:draw(tailLimb, { body, back, backMirror }, WHITE)
		fur(
			tailLimb,
			T,
			tail,
			function(p, n)
				return n[2] > -0.3 and noise(vadd(p, { 3, 9, 1 })) < 0.14
			end,
			1.4,
			0.9,
			{ 0, 0.2, -0.4 },
			function()
				return WHITE_TOP.color
			end
		)

		pet:seat(0, 12.6, -1.4)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Reindeer (Rare): a big reindeer dressed for the holidays, like its knitted egg: a striped knitted scarf trailing
-- from its neck, a knitted saddle blanket, a harness of gold bells, a shaggy white mane, branching antlers, and a
-- glowing red nose.

Snow.Reindeer = {
	name = "Reindeer",
	skeleton = "Quadruped",
	scale = 0.3,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local FUR = look(132, 96, 66)
		local FUR_TOP = look(158, 120, 86)
		local FUR_UNDER = look(92, 64, 42)
		local FUR_LOW = look(104, 74, 50)
		local CREAM = look(236, 226, 206)
		local CREAM_SHADE = look(200, 188, 166)
		local RED = look(204, 46, 56)
		local RED_TOP = look(228, 72, 78)
		local KNIT = look(246, 238, 222)
		local GREEN = look(56, 138, 82)
		local HOOF = look(48, 38, 34)
		local ANTLER = rgb(222, 204, 166)
		local ANTLER_DARK = rgb(176, 152, 112)
		local NOSE = rgb(255, 54, 60)
		local GOLD = rgb(255, 200, 60)
		local STRAP = rgb(120, 70, 40)

		local tones = {
			[FUR] = { top = FUR_TOP, under = FUR_UNDER, low = FUR_LOW, below = 10 },
			[CREAM] = { under = CREAM_SHADE },
			[RED] = { top = RED_TOP },
		}

		-- A knitted pattern: rows of red, a band of green and white zigzags.
		local function knit(p: Vec, base: number): Look
			local row = math.floor((p[2] - base) / 0.9)
			if row % 6 == 2 then
				return GREEN
			elseif row % 6 == 3 then
				return if math.floor(p[3] + p[1] + p[2] * 0.4) % 2 == 0 then KNIT else RED
			end
			return RED
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 18, -1 }, { 4.8, 4.8, 9.6 }), FUR)
		body:add(ellipsoid({ 0, 18.6, 6 }, { 4.6, 5.4, 4.4 }), FUR)
		body:add(ellipsoid({ 0, 18.6, -8.4 }, { 4.8, 5, 4.4 }), FUR)
		body:add(rod({ { 0, 21, 8, 3.6 }, { 0, 25.6, 11, 2.8 } }), FUR)
		body:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if open(0, -1, 0) or (z < -10.6 and y < 21) then
				return CREAM
			end
			-- The scarf, wound round its neck.
			if z > 8.6 and y > 21.4 and y < 24.6 then
				return knit(p, 21.4)
			end
			-- The saddle blanket over its back.
			if math.abs(z + 1) < 4.2 and y > 16.6 then
				if y < 17.6 or math.abs(z + 1) > 3.6 then
					return KNIT
				end
				return knit(p, 17.6)
			end
			if math.abs(x) < 2.6 and z > 5 and y < 19 then
				return CREAM
			end
			return nil
		end)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 27.4, 12.4 }, { 2.8, 2.9, 3.4 }), FUR)
		head:add(rod({ { 0, 26.8, 13.8, 2.2 }, { 0, 25.8, 18, 1.6 } }), FUR)
		head:coat(function(p)
			if p[2] < 26 and p[3] > 14 then
				return CREAM
			end
			return nil
		end)
		head:bake(tones)

		local front = newSculpt(U)
		front:add(rod({ { 3.2, 18.4, 6, 2.4 }, { 3.4, 10.6, 6.8, 1.6 }, { 3.3, 1.6, 6.8, 1.3 } }), FUR)
		front:add(ellipsoid({ 3.3, 0.9, 7.4 }, { 1.6, 0.9, 1.9 }), HOOF)
		front:bake(tones)
		local back = newSculpt(U)
		back:add(ellipsoid({ 3.4, 18, -8.4 }, { 2.6, 5, 4 }), FUR)
		back:add(rod({ { 3.4, 14, -9.8, 2 }, { 3.4, 8.6, -11, 1.5 }, { 3.3, 1.6, -9.6, 1.3 } }), FUR)
		back:add(ellipsoid({ 3.3, 0.9, -9 }, { 1.6, 0.9, 1.9 }), HOOF)
		back:bake(tones)

		local tail = newSculpt(U)
		tail:add(ellipsoid({ 0, 21, -13 }, { 1.3, 1.6, 1.2 }), CREAM)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 18, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, FUR)
		-- A shaggy white mane hanging under its neck.
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return p[3] > 6 and p[2] > 15 and p[2] < 21.4 and n[2] < 0.2 and noise(vadd(p, { 2, 2, 5 })) < 0.45
			end,
			2.4,
			1.3,
			{ 0, -1.6, 0.2 },
			function(p)
				return if noise(p) < 0.5 then CREAM.color else KNIT.color
			end
		)
		-- The ends of the scarf trailing back over its shoulder, fringed.
		local scarf = { (sideOf(body, 22.6, 7.6) - 0.3), 22.6, 7.6 }
		local hang = { scarf[1] + 0.8, 17.8, 4.6 }
		T.blade(bodyLimb, scarf, hang, 2.2, 0.6, { 1, 0, 0 }, RED.color)
		T.blade(
			bodyLimb,
			vadd(scarf, { 0.1, -1.6, -0.9 }),
			vadd(scarf, { 0.4, -2.4, -1.4 }),
			2.3,
			0.7,
			{ 1, 0, 0 },
			GREEN.color
		)
		for _, dz in { -0.7, 0, 0.7 } do
			T.taper(
				bodyLimb,
				vadd(hang, { 0, 0.2, dz }),
				vadd(hang, { 0.1, -1.2, dz - 0.2 }),
				0.5,
				0.4,
				{ 1, 0, 0 },
				KNIT.color
			)
		end
		-- A harness of gold bells round its chest.
		for _, s in { 1, -1 } do
			for i = 0, 3 do
				local y = 15.6 + i * 1.6
				local z = 8.6 - i * 0.6
				local x = (sideOf(body, y, z) - 0.3) * s * 0.7
				T.ball(bodyLimb, { x, y, z + 1.4 }, { 1.1, 1.1, 1.1 }, GOLD)
			end
		end
		T.blade(bodyLimb, { 0, 14.4, 9.8 }, { 0, 21, 9.6 }, 1.2, 0.5, { 0, 0, 1 }, STRAP)

		local headLimb = pet:limb("Head", T.at({ 0, 24.6, 10.6 }))
		head:draw(headLimb, { body }, FUR)
		glossyEye(headLimb, T, head, 28, 14.4, 1.3)
		-- The glowing red nose.
		T.ball(headLimb, { 0, 26, 18.6 }, { 2.2, 1.9, 1.9 }, NOSE, NEON)
		for _, s in { 1, -1 } do
			T.taper(headLimb, { 2.2 * s, 29.4, 11.8 }, { 4.6 * s, 30.6, 10.6 }, 1.4, 0.6, { 0, 1, 0.2 }, FUR.color)
			-- Antlers: a beam sweeping back and up, a broad brow tine forward, and tines along the top.
			local beam =
				{ { 1.4 * s, 30, 12.4 }, { 3 * s, 33.6, 10.6 }, { 4.6 * s, 37.6, 10.2 }, { 5.4 * s, 41.4, 11.4 } }
			for i = 1, #beam - 1 do
				T.blade(headLimb, beam[i], beam[i + 1], 1.1 - i * 0.12, 1.1 - i * 0.12, { 0, 0, 1 }, ANTLER)
			end
			T.taper(headLimb, beam[#beam], { 5.6 * s, 43.4, 13 }, 0.7, 0.7, { 0, 0, 1 }, ANTLER)
			T.blade(headLimb, beam[2], { 2.6 * s, 33.2, 14.6 }, 1.6, 0.4, { s, 0, 0 }, ANTLER_DARK)
			T.taper(headLimb, beam[3], { 4 * s, 40.4, 13.6 }, 0.7, 0.7, { 0, 0, 1 }, ANTLER)
			T.taper(headLimb, beam[3], { 7.2 * s, 39.2, 8.6 }, 0.7, 0.7, { 0, 0, 1 }, ANTLER)
			T.taper(headLimb, beam[4], { 7.4 * s, 42.6, 9.8 }, 0.6, 0.6, { 0, 0, 1 }, ANTLER)
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.2, 18.4, 6 }), function(limb)
			front:draw(limb, { body }, FUR)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3.4, 18, -8.4 }), function(limb)
			back:draw(limb, { body }, FUR)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 21, -12.4 })), { body }, FUR)

		pet:seat(0, 23.4, -1)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Frost Wolf (Epic): a dire wolf of the glaciers, taller than a player at the shoulder, its pale coat darker along
-- the back, a shaggy mane, clusters of ice crystals growing from its shoulders and spine, glowing ice-blue eyes and a
-- snarl of fangs.

Snow.FrostWolf = {
	name = "Frost Wolf",
	skeleton = "Quadruped",
	scale = 0.3 * 1.2,
	draw = function(pet)
		-- Built in cells 1.2 design units across.
		local U = 1.2
		local T = inUnits(U)
		local WOLF = look(178, 198, 224)
		local WOLF_TOP = look(206, 222, 242)
		local WOLF_UNDER = look(118, 136, 174)
		local SADDLE = look(96, 114, 156)
		local SADDLE_TOP = look(122, 140, 180)
		local WHITE = look(240, 246, 255)
		local WHITE_SHADE = look(196, 210, 232)
		local NOSE = look(32, 36, 52)
		local MOUTH = look(70, 30, 50)
		local ICE = rgb(150, 210, 246)
		local GLOW = rgb(140, 240, 255)
		local TOOTH = rgb(244, 248, 255)
		local CLAW = rgb(210, 230, 250)

		local tones = {
			[WOLF] = { top = WOLF_TOP, under = WOLF_UNDER },
			[SADDLE] = { top = SADDLE_TOP, under = WOLF_UNDER },
			[WHITE] = { under = WHITE_SHADE },
		}

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 17.4, -2 }, { 4.8, 4.8, 10 }), WOLF)
		body:add(ellipsoid({ 0, 18.4, 5.4 }, { 5, 5.8, 4.6 }), WOLF)
		body:add(ellipsoid({ 0, 18, -9.4 }, { 4.6, 4.8, 4.2 }), WOLF)
		body:add(rod({ { 0, 20, 7.6, 4 }, { 0, 23.4, 10.6, 3.2 } }), WOLF)
		body:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if z > 5 and y < 19.6 and math.abs(x) < 3.4 then
				return WHITE
			end
			if open(0, -1, 0) then
				return WHITE
			end
			if y > 19.4 and patches(p, 3) < 0.7 then
				return SADDLE
			end
			return nil
		end)
		body:bake(tones)

		-- A long head held low, lips drawn back over its fangs.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 24.4, 12.6 }, { 3.6, 3.2, 3.8 }), WOLF)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 2.6 * s, 23.4, 12.4 }, { 1.8, 2.4, 2.6 }), WOLF)
		end
		head:add(rod({ { 0, 23.6, 14.4, 2.2 }, { 0, 23.2, 19.4, 1.4 } }), WOLF)
		head:add(rod({ { 0, 21, 14.2, 1.6 }, { 0, 20.8, 18.2, 1.1 } }), WHITE)
		head:add(ellipsoid({ 0, 23.8, 19.8 }, { 1.2, 0.9, 0.8 }), NOSE)
		head:carve(ellipsoid({ 0, 22.1, 18.6 }, { 1.6, 0.7, 2.6 }))
		head:coat(function(p, open)
			if p[3] > 15.4 and p[2] > 21.2 and p[2] < 22.8 and math.abs(p[1]) < 1.6 then
				return MOUTH
			end
			if p[2] < 23 and (math.abs(p[1]) > 2.4 or p[3] > 15) and not open(0, 1, 0) then
				return WHITE
			end
			if open(0, 1, 0) and p[3] < 13 then
				return SADDLE
			end
			return nil
		end)
		head:bake(tones)

		local function leg(s: Sculpt, top: Vec, knee: Vec, foot: Vec)
			s:add(
				rod({
					{ top[1], top[2], top[3], 2.4 },
					{ knee[1], knee[2], knee[3], 1.6 },
					{ foot[1], 1.6, foot[3], 1.3 },
				}),
				WOLF
			)
			s:add(ellipsoid({ foot[1], 1, foot[3] + 0.6 }, { 1.6, 1, 2 }), WHITE)
			s:bake(tones)
		end
		local front, back = newSculpt(U), newSculpt(U)
		leg(front, { 3.2, 17.6, 5.4 }, { 3.4, 9.4, 6 }, { 3.3, 1.4, 6.4 })
		back:add(ellipsoid({ 3.4, 17, -9.4 }, { 2.6, 4.8, 3.8 }), WOLF)
		leg(back, { 3.4, 14.4, -10.6 }, { 3.4, 8.6, -12.4 }, { 3.3, 1.4, -10.6 })

		local spine =
			{ { 0, 19.6, -12.6, 1.8 }, { 0, 17.4, -16.4, 2.4 }, { 0, 13.6, -18.6, 2.2 }, { 0, 10.6, -19, 1.2 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), WOLF)
		tail:coat(function(p)
			if p[2] < 12.4 then
				return WHITE
			end
			if p[2] > 15 and patches(p, 2) < 0.5 then
				return SADDLE
			end
			return nil
		end)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 17.4, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, WOLF)
		-- A shaggy mane over its neck and shoulders.
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return p[3] > 1 and p[2] > 19 and n[2] > -0.2 and noise(vadd(p, { 1, 5, 3 })) < 0.26
			end,
			3,
			1.6,
			{ 0, -0.2, -1.5 },
			function(p)
				return if noise(p) < 0.4 then WHITE.color else WOLF_TOP.color
			end
		)
		-- Ice crystals growing in clusters from its shoulders and along its spine, glowing at their points.
		for _, s in { 1, -1 } do
			crystalCluster(bodyLimb, T, { 3 * s, 22.6, 4 }, { 0.5 * s, 1, -0.5 }, 5, 3, ICE, GLOW, nil, NEON, 1 + s)
		end
		for i, z in { -2, -5.4, -8.6 } do
			crystal(bodyLimb, T, { 0, 21.6 - i * 0.2, z }, { 0, 1, -0.6 }, 4.2 - i * 0.6, 1.3, ICE, GLOW, nil, NEON)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 22.4, 10 }))
		head:draw(headLimb, { body }, WOLF)
		Kit.slitEyes(headLimb, head, { 25.6, 16 }, { 26, 13.8 }, 0.9, GLOW, NEON, rgb(30, 34, 56))
		for _, s in { 1, -1 } do
			-- Tall pointed ears.
			T.taper(headLimb, { 2 * s, 27, 11.4 }, { 3 * s, 31.4, 10.6 }, 2.2, 1, { 0, 0, 1 }, SADDLE.color)
			T.taper(headLimb, { 2.05 * s, 27.3, 11.95 }, { 2.9 * s, 30.4, 11.25 }, 1.2, 0.3, { 0, 0, 1 }, WHITE.color)
			-- Fangs, top and bottom.
			T.taper(headLimb, { 1.1 * s, 22.8, 19.4 }, { 1.1 * s, 21.2, 19.6 }, 0.6, 0.6, { 0, 0, 1 }, TOOTH)
			T.taper(headLimb, { 0.9 * s, 21.4, 18.4 }, { 0.9 * s, 22.6, 18.6 }, 0.5, 0.5, { 0, 0, 1 }, TOOTH)
			-- A frosty ruff on its cheeks.
			T.taper(headLimb, { 3.2 * s, 23.2, 12 }, { 5 * s, 22.4, 9.6 }, 1.6, 0.9, { 0, 1, 0 }, WHITE.color)
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.2, 17.6, 5.4 }), function(limb)
			front:draw(limb, { body }, WOLF)
			for _, dx in { -0.8, 0, 0.8 } do
				T.taper(limb, { 3.3 + dx, 0.6, 8 }, { 3.3 + dx * 1.2, 0.2, 9.2 }, 0.45, 0.4, { 0, 1, 0 }, CLAW)
			end
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3.4, 17, -9.4 }), function(limb)
			back:draw(limb, { body }, WOLF)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 19.4, -12 })), { body }, WOLF)

		pet:seat(0, 22.4 / U, -2.4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Sabertooth Cat (Legendary): a hulking sabretooth, its frosty coat striped with glowing ice-blue, great ivory
-- sabres hanging from its jaw, ice crystals on its shoulders, glowing eyes, and an icy aura.

Snow.SabertoothCat = {
	name = "Sabertooth Cat",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.43 * 1.2,
	draw = function(pet)
		-- Built in cells 1.2 design units across.
		local U = 1.2
		local T = inUnits(U)
		local FUR = look(222, 210, 188)
		local FUR_TOP = look(240, 232, 214)
		local FUR_UNDER = look(164, 152, 136)
		local FUR_LOW = look(190, 178, 160)
		local SLATE = look(60, 72, 102)
		local STRIPE = look(90, 200, 255, NEON)
		local NOSE = look(110, 80, 84)
		local MOUTH = look(70, 40, 56)
		local IVORY = rgb(250, 242, 218)
		local ICE = rgb(170, 222, 250)
		local GLOW = rgb(150, 236, 255)
		local CLAW = rgb(214, 236, 252)

		local tones = {
			[FUR] = { top = FUR_TOP, under = FUR_UNDER, low = FUR_LOW, below = 8 },
		}

		-- Glowing stripes across its back and flanks, each edged in slate.
		local function stripes(p: Vec): Look?
			if p[2] < 17 then
				return nil
			end
			local w = math.sin(p[3] * 0.6 + math.abs(p[1]) * 0.18 + math.sin(p[2] * 0.4) * 0.7)
			if w > 0.94 then
				return STRIPE
			elseif w > 0.6 then
				return SLATE
			end
			return nil
		end

		-- A powerful body, high and hunched at the shoulders, low at the hips.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 18, -2 }, { 5, 5, 9.4 }), FUR)
		body:add(ellipsoid({ 0, 19, 6 }, { 5.6, 6.2, 5.2 }), FUR)
		body:add(ellipsoid({ 0, 22.4, 4.4 }, { 4.8, 3, 4.4 }), FUR)
		body:add(ellipsoid({ 0, 18.2, -9.6 }, { 4.8, 4.8, 4.4 }), FUR)
		body:add(rod({ { 0, 21, 8.4, 4.4 }, { 0, 22.6, 11, 3.8 } }), FUR)
		body:coat(function(p)
			return stripes(p)
		end)
		body:bake(tones)

		-- A big head with a short muzzle and its jaw dropped to bare the sabres.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 23.6, 13.4 }, { 4, 3.6, 4 }), FUR)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 2.8 * s, 22.2, 14 }, { 2, 2.4, 2.4 }), FUR)
			head:add(ellipsoid({ 3 * s, 26.8, 11.6 }, { 1.3, 1.3, 0.9 }), FUR)
		end
		head:add(ellipsoid({ 0, 22, 16.6 }, { 2.8, 2.4, 2.6 }), FUR)
		head:add(ellipsoid({ 0, 19.4, 15.4 }, { 2, 1.2, 2.2 }), FUR)
		head:add(ellipsoid({ 0, 23.2, 18.6 }, { 1.1, 0.8, 0.7 }), NOSE)
		head:coat(function(p, open)
			if p[2] < 20.4 and p[2] > 19 and p[3] > 15.6 and math.abs(p[1]) < 1.8 and not open(0, 1, 0) then
				return MOUTH
			end
			if open(0, 1, 0) and p[3] < 14 and math.abs(p[1]) < 1.4 then
				return STRIPE
			end
			return nil
		end)
		head:bake(tones)

		local function leg(s: Sculpt, top: Vec, knee: Vec, foot: Vec, r: number)
			s:add(
				rod({
					{ top[1], top[2], top[3], r },
					{ knee[1], knee[2], knee[3], r * 0.72 },
					{ foot[1], 1.8, foot[3], r * 0.62 },
				}),
				FUR
			)
			s:add(ellipsoid({ foot[1], 1.2, foot[3] + 0.8 }, { r * 0.75, 1.2, r * 0.9 }), FUR)
			s:coat(function(p)
				return stripes(p)
			end)
			s:bake(tones)
		end
		local front, back = newSculpt(U), newSculpt(U)
		leg(front, { 3.6, 19, 6 }, { 3.8, 10, 6.8 }, { 3.7, 1.6, 7.2 }, 2.8)
		back:add(ellipsoid({ 3.6, 18, -9.4 }, { 2.8, 5, 4 }), FUR)
		leg(back, { 3.6, 15, -10.6 }, { 3.6, 9, -12.4 }, { 3.5, 1.6, -10.6 }, 2.4)

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 21.6, -13.4, 1.4 }, { 0, 20.4, -15.6, 1.1 } }), FUR)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 18, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, FUR)
		-- Ice crystals on its shoulders and along its spine.
		for _, s in { 1, -1 } do
			crystalCluster(bodyLimb, T, { 3.4 * s, 23.4, 5 }, { 0.6 * s, 1, -0.4 }, 4.4, 3, ICE, GLOW, nil, NEON, 2 + s)
		end
		for i, z in { -1.6, -4.6, -7.6 } do
			crystal(bodyLimb, T, { 0, 22.4 - i * 0.3, z }, { 0, 1, -0.5 }, 3.4 - i * 0.4, 1.1, ICE, GLOW, nil, NEON)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 22.6, 10.6 }))
		head:draw(headLimb, { body }, FUR)
		Kit.slitEyes(headLimb, head, { 25, 16.4 }, { 25.4, 14.4 }, 0.9, GLOW, NEON, rgb(40, 44, 60))
		for _, s in { 1, -1 } do
			-- The sabres: long, flat, curving back, frosted at the tips.
			local root, mid, tip = { 1.5 * s, 21.4, 17.4 }, { 1.6 * s, 18.2, 17.9 }, { 1.7 * s, 14.6, 17.4 }
			T.blade(headLimb, root, mid, 1.3, 0.7, { s, 0, 0 }, IVORY)
			T.taper(headLimb, mid, tip, 1.2, 0.65, { s, 0, 0 }, IVORY)
			T.taper(
				headLimb,
				vadd(tip, { 0, 0.9, -0.1 }),
				vadd(tip, { 0, -0.4, -0.2 }),
				0.6,
				0.4,
				{ s, 0, 0 },
				GLOW,
				NEON
			)
			-- Whisker-like frost on its cheeks.
			T.taper(headLimb, { 3.4 * s, 22.4, 14.2 }, { 5.6 * s, 21.6, 12.2 }, 1.6, 0.9, { 0, 1, 0 }, FUR_TOP.color)
		end

		local function claws(limb: Limb, x: number, z: number)
			for _, dx in { -1.2, -0.4, 0.4, 1.2 } do
				T.taper(limb, { x + dx, 1, z }, { x + dx * 1.1, 0.2, z + 1.6 }, 0.55, 0.5, { 0, 1, 0 }, CLAW)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.6, 19, 6 }), function(limb)
			front:draw(limb, { body }, FUR)
			claws(limb, 3.7, 9.4)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3.6, 18, -9.4 }), function(limb)
			back:draw(limb, { body }, FUR)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 21.6, -13 })), { body }, FUR)

		pet:light(GLOW, 1.8, 18)
		pet:particles("Snow", rgb(240, 248, 255), 8)
		pet:aura(rgb(110, 210, 255), rgb(235, 250, 255))
		pet:seat(0, 23.4 / U, -2.6 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Aurora Owl (Mythic): a great owl of the polar night, midnight blue and dusted with glowing stars, its wing and
-- tail feathers and its crest glowing with the colours of the aurora, and great glowing eyes.

Snow.AuroraOwl = {
	name = "Aurora Owl",
	skeleton = "Winged",
	gait = "Waddle",
	scale = 0.36,
	wingSpread = 1.35,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local NIGHT = look(30, 40, 92)
		local NIGHT_TOP = look(54, 70, 140)
		local NIGHT_UNDER = look(18, 24, 60)
		local CHEST = look(222, 232, 252)
		local CHEST_SHADE = look(176, 190, 228)
		local MARK = look(90, 112, 184)
		local STAR = look(255, 255, 255, NEON)
		local FACE = look(214, 226, 250)
		local RIM = look(40, 54, 120)
		local TALON = rgb(70, 70, 90)
		local BEAK = rgb(236, 196, 116)
		local GREEN = rgb(90, 255, 170)
		local TEAL = rgb(80, 220, 255)
		local VIOLET = rgb(186, 120, 255)
		local IRIS = rgb(110, 255, 220)

		local tones = {
			[NIGHT] = { top = NIGHT_TOP, under = NIGHT_UNDER },
			[CHEST] = { under = CHEST_SHADE },
		}

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 11.6, 0 }, { 6.4, 7.8, 5.8 }), NIGHT)
		body:add(ellipsoid({ 0, 8.6, 0.8 }, { 5.8, 5.6, 5.2 }), NIGHT)
		body:coat(function(p, open)
			local x, y = p[1], p[2]
			if (open(0, 0, 1) or p[3] > 2.2) and math.abs(x) < 4.9 and y < 17 then
				if (y + math.abs(x) * 0.55) % 3.2 < 0.8 then
					return MARK
				end
				return CHEST
			end
			if noise(p) < 0.025 then
				return STAR
			end
			return nil
		end)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 22.4, 0.4 }, { 6.8, 5.8, 5.6 }), NIGHT)
		head:add(ellipsoid({ 0, 19.6, 0.6 }, { 5.8, 3.2, 4.8 }), NIGHT)
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
			if noise(p) < 0.03 then
				return STAR
			end
			return nil
		end)
		head:bake(tones)

		local leg = newSculpt(U)
		leg:add(ellipsoid({ 2.6, 3.8, 1.4 }, { 2.1, 2.6, 2.1 }), CHEST)
		for _, dx in { -1, 0, 1 } do
			leg:add(rod({ { 2.6 + dx * 0.4, 1.4, 2, 0.8 }, { 2.6 + dx * 1.3, 0.8, 4.2, 0.7 } }), CHEST)
		end
		leg:bake(tones)

		local covert = newSculpt(U)
		covert:add(ellipsoid({ 6, 12.8, -0.8 }, { 1.6, 6, 4.6 }), NIGHT)
		covert:coat(function(p)
			if noise(p) < 0.035 then
				return STAR
			end
			return nil
		end)
		covert:bake(tones)

		local legMirror, covertMirror = leg:mirror(), covert:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 6, 0 }))
		body:draw(bodyLimb, { head, leg, legMirror, covert, covertMirror }, NIGHT)

		-- Aurora bands for a feather, from its root out: midnight, then teal, green and violet at the tip.
		local AURORA = {
			{ color = NIGHT.color, to = 0.34 },
			{ color = TEAL, material = NEON, to = 0.56 },
			{ color = GREEN, material = NEON, to = 0.8 },
			{ color = VIOLET, material = NEON, to = 1 },
		}

		local headLimb = pet:limb("Head", T.at({ 0, 17, 0 }))
		head:draw(headLimb, { body }, NIGHT)
		for _, s in { 1, -1 } do
			-- Great glowing eyes, each with a dark pupil and a glint.
			local face = frontOf(head, 2.5 * s, 22.2)
			T.ball(headLimb, { 2.5 * s, 22.2, face - 0.2 }, { 3.6, 3.6, 0.9 }, RIM.color)
			T.ball(headLimb, { 2.5 * s, 22.2, face + 0.05 }, { 3, 3, 0.8 }, IRIS, NEON)
			T.ball(headLimb, { 2.5 * s, 22.1, face + 0.3 }, { 1.5, 1.5, 0.6 }, EYE)
			T.ball(headLimb, { 2.15 * s, 22.7, face + 0.55 }, { 0.6, 0.6, 0.3 }, rgb(255, 255, 255))
			T.blade(headLimb, { 0.5 * s, 24, face }, { 4.6 * s, 25.4, face - 1.2 }, 0.9, 0.8, { 0, 0.4, 1 }, RIM.color)
			-- Ear tufts and a crest of aurora feathers.
			Kit.feather(
				headLimb,
				T.at({ 3.4 * s, 25.6, -0.4 }),
				{ 0.5 * s, 1, -0.25 },
				6.4,
				1.6,
				0.6,
				{ 0, 0, 1 },
				AURORA
			)
			Kit.feather(
				headLimb,
				T.at({ 2.6 * s, 26, -1.4 }),
				{ 0.3 * s, 1, -0.5 },
				5.2,
				1.4,
				0.55,
				{ 0, 0, 1 },
				AURORA
			)
			T.taper(headLimb, { 5.6 * s, 20.6, 2 }, { 7.4 * s, 18.8, 0.2 }, 1.6, 0.7, { 0, 0, 1 }, NIGHT.color)
		end
		Kit.feather(headLimb, T.at({ 0, 27.6, -0.6 }), { 0, 1, -0.4 }, 6.4, 1.8, 0.6, { 1, 0, 0 }, AURORA)
		local nose = frontOf(head, 0, 21)
		T.blade(headLimb, { 0, 21.6, nose - 0.4 }, { 0, 20, nose + 0.9 }, 1.3, 1.2, { 1, 0, 0 }, BEAK)
		T.taper(headLimb, { 0, 20, nose + 0.9 }, { 0, 18.2, nose + 1 }, 1.1, 1, { 1, 0, 0 }, BEAK)

		pet:limbPair("LeftWing", "RightWing", T.at({ 5.4, 16.6, 0 }), function(wing)
			covert:draw(wing, { body }, NIGHT)
			-- Long flight feathers, midnight at the root and glowing with the aurora towards the tips.
			for index, z in { 2.4, 1, -0.4, -1.8, -3.2, -4.6 } do
				Kit.feather(
					wing,
					T.at({ 6.5, 9.4, z }),
					{ 0.08, -1, -0.5 - index * 0.07 },
					8,
					1.8,
					0.55,
					{ 1, 0, 0 },
					AURORA
				)
			end
			for row, y in { 16.4, 13.6 } do
				for _, z in { 1.6, -0.6, -2.8 } do
					T.taper(
						wing,
						{ 7.3, y, z },
						{ 7.6, y - 3.6, z - 1.4 },
						2,
						0.6,
						{ 1, 0, 0 },
						if row == 1 then NIGHT_TOP.color else NIGHT.color
					)
				end
			end
		end)

		pet:limbPair("LeftLeg", "RightLeg", T.at({ 2.6, 5, 1.4 }), function(limb)
			leg:draw(limb, { body }, NIGHT)
			for _, dx in { -1, 0, 1 } do
				T.taper(limb, { 2.6 + dx * 1.3, 0.9, 3.9 }, { 2.6 + dx * 1.6, 0.2, 5.6 }, 0.6, 0.5, { 0, 1, 0 }, TALON)
			end
		end)

		-- A fan of tail feathers, glowing at the tips.
		local tail = pet:limb("Tail", T.at({ 0, 6, -4.4 }))
		for _, dx in { -2, -1, 0, 1, 2 } do
			Kit.feather(
				tail,
				T.at({ dx * 0.7, 6, -4.2 }),
				{ dx * 0.35, -0.75, -1 },
				6,
				1.8,
				0.55,
				{ 0, 1, -0.6 },
				AURORA
			)
		end

		pet:light(TEAL, 2.4, 22)
		pet:particles("Sparkles", GREEN, 12)
		pet:aura(rgb(80, 240, 170), VIOLET)
		pet:seat(0, 18.6, -3)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Woolly Mammoth (Mythic): a mammoth nearly four times a player's height, its shaggy brown wool hanging in long
-- strands and capped with snow, huge curling tusks banded with glowing frost runes, glowing ice crystals growing
-- from its back, and an icy aura.

Snow.WoollyMammoth = {
	name = "Woolly Mammoth",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.32 * 1.5,
	draw = function(pet)
		-- Built in cells 1.5 design units across.
		local U = 1.5
		local T = inUnits(U)
		local WOOL = look(122, 80, 48)
		local SNOW_CAP = look(246, 250, 255)
		local WOOL_UNDER = look(80, 50, 30)
		local WOOL_LOW = look(96, 62, 38)
		local WOOL_LIGHT = look(150, 104, 66)
		local SKIN = look(70, 52, 44)
		local IVORY = rgb(250, 240, 214)
		local IVORY_DARK = rgb(214, 196, 160)
		local ICE = rgb(170, 222, 250)
		local GLOW = rgb(140, 236, 255)
		local STRAND = rgb(104, 66, 40)
		local STRAND_LIGHT = rgb(140, 96, 60)

		local tones = {
			[WOOL] = { top = SNOW_CAP, under = WOOL_UNDER, low = WOOL_LOW, below = 12 },
			[WOOL_LIGHT] = { top = SNOW_CAP, under = WOOL_UNDER },
		}

		-- A huge barrel of a body under a high shoulder hump.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 30, -2 }, { 10, 10, 15 }), WOOL)
		body:add(ellipsoid({ 0, 38, 6 }, { 8.6, 7.4, 8 }), WOOL)
		body:add(ellipsoid({ 0, 30, -13 }, { 9, 9, 7 }), WOOL)
		body:coat(function(p)
			if patches(p, 4) < 0.35 then
				return WOOL_LIGHT
			end
			return nil
		end)
		body:bake(tones)

		-- A domed head, small ears, and a long trunk curling at its tip.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 40, 14.6 }, { 6.4, 7, 6 }), WOOL)
		head:add(ellipsoid({ 0, 46, 12.4 }, { 5, 4, 5 }), WOOL)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 6 * s, 39.6, 12.6 }, { 1.4, 3, 2.4 }), WOOL)
		end
		local trunk = {
			{ 0, 36, 19.4, 3.2 },
			{ 0, 28, 22, 2.6 },
			{ 0, 18, 22.4, 2.2 },
			{ 0, 10.6, 20.4, 1.8 },
			{ 0, 7.6, 22.4, 1.5 },
			{ 0, 8.6, 24.6, 1.3 },
		}
		head:add(rod(trunk), SKIN)
		head:coat(function(p)
			local d = nearPath(trunk, p)
			if d < 4 and p[2] < 33 and math.floor(p[2] / 1.6) % 2 == 0 then
				return WOOL_UNDER
			end
			return nil
		end)
		head:bake(tones)

		local front = newSculpt(U)
		front:add(rod({ { 7, 28, 8, 5 }, { 7.4, 14, 9, 4.6 }, { 7.4, 4, 9, 4.6 } }), WOOL)
		front:add(ellipsoid({ 7.4, 2.4, 9.6 }, { 4.8, 2.4, 5 }), SKIN)
		front:bake(tones)
		local back = newSculpt(U)
		back:add(ellipsoid({ 7, 28, -13 }, { 5, 8, 6 }), WOOL)
		back:add(rod({ { 7.2, 20, -14, 4.8 }, { 7.4, 4, -13, 4.6 } }), WOOL)
		back:add(ellipsoid({ 7.4, 2.4, -12.4 }, { 4.8, 2.4, 5 }), SKIN)
		back:bake(tones)

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 33, -19.6, 1.4 }, { 0, 26, -21, 1.1 } }), WOOL)
		tail:add(ellipsoid({ 0, 24.6, -21 }, { 1.6, 2.2, 1.6 }), WOOL)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 30, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, WOOL)
		-- Long strands of wool hanging from its flanks and belly.
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return n[2] < 0.3 and p[2] < 32 and noise(vadd(p, { 5, 1, 2 })) < 0.3
			end,
			6,
			2.6,
			{ 0, -2.4, 0 },
			function(p)
				return if noise(p) < 0.5 then STRAND else STRAND_LIGHT
			end
		)
		-- Glowing ice crystals growing from its back.
		crystalCluster(bodyLimb, T, { 0, 44.6, 4 }, { 0, 1, -0.3 }, 9, 4, ICE, GLOW, nil, NEON, 1)
		crystalCluster(bodyLimb, T, { 3, 39, -8 }, { 0.4, 1, -0.4 }, 6.4, 3, ICE, GLOW, nil, NEON, 2)
		crystalCluster(bodyLimb, T, { -3.6, 38.4, -13 }, { -0.4, 1, -0.4 }, 5.6, 3, ICE, GLOW, nil, NEON, 3)

		local headLimb = pet:limb("Head", T.at({ 0, 38, 11 }))
		head:draw(headLimb, { body }, WOOL)
		for _, s in { 1, -1 } do
			local x = sideOf(head, 41, 17.6)
			T.ball(headLimb, { (x - 0.2) * s, 41, 17.6 }, { 1, 1.4, 1.6 }, GLOW, NEON)
			-- Great tusks, sweeping down, out and up, banded with glowing frost runes.
			local tusk = {
				{ 3.4 * s, 33.6, 18 },
				{ 6.4 * s, 27, 22.6 },
				{ 8.6 * s, 21.6, 27.6 },
				{ 8.6 * s, 20.6, 32.6 },
				{ 6.8 * s, 22.6, 36.6 },
				{ 4 * s, 26, 38 },
			}
			for i = 1, #tusk - 1 do
				local w = 2.6 - i * 0.36
				if i == #tusk - 1 then
					T.taper(headLimb, tusk[i], tusk[i + 1], w, w, { 0, 1, 0 }, IVORY)
				else
					T.blade(headLimb, tusk[i], tusk[i + 1], w, w, { 0, 1, 0 }, if i == 1 then IVORY_DARK else IVORY)
					T.ball(
						headLimb,
						tusk[i + 1],
						{ w * 1.04, w * 1.04, w * 1.04 },
						if i % 2 == 0 then GLOW else IVORY,
						if i % 2 == 0 then NEON else nil
					)
				end
			end
		end
		-- Wool hanging from its chin and cheeks.
		fur(
			headLimb,
			T,
			head,
			function(p, n)
				return p[2] < 39
					and p[2] > 33
					and math.abs(p[1]) > 2.4
					and n[2] < 0.2
					and noise(vadd(p, { 3, 8, 1 })) < 0.5
			end,
			4.4,
			2,
			{ 0, -2, 0 },
			function(p)
				return if noise(p) < 0.5 then STRAND else STRAND_LIGHT
			end
		)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 7, 28, 8 }), function(limb)
			front:draw(limb, { body }, WOOL)
			for _, dx in { -2.4, 0, 2.4 } do
				T.ball(limb, { 7.4 + dx, 1.6, 13.4 + math.abs(dx) * -0.2 }, { 1.8, 1.4, 1.4 }, IVORY)
			end
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 7, 28, -13 }), function(limb)
			back:draw(limb, { body }, WOOL)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 33, -19 })), { body }, WOOL)

		pet:light(GLOW, 2.4, 26)
		pet:particles("Snow", rgb(240, 248, 255), 14)
		pet:aura(rgb(110, 210, 255), rgb(235, 250, 255))
		pet:seat(0, 40.6 / U, -4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Yeti (Secret): the king of the mountains, five times a player's height. A white mane and navy hide, great curling
-- horns tipped with ice, glowing ice-crystal clusters bursting from its shoulders, forearms and spine, glowing eyes,
-- and a roaring mouth full of fangs. Snow falls round it and an icy aura swirls at its feet.

Snow.Yeti = {
	name = "Yeti",
	skeleton = "Biped",
	gait = "Stomp",
	scale = 0.32 * 1.5,
	draw = function(pet)
		-- Built in cells 1.5 design units across.
		local U = 1.5
		local T = inUnits(U)
		local FUR = look(240, 246, 252)
		local FUR_TOP = look(255, 255, 255)
		local FUR_UNDER = look(186, 204, 230)
		local NAVY = look(34, 54, 112)
		local NAVY_TOP = look(54, 78, 146)
		local NAVY_UNDER = look(20, 30, 70)
		local MOUTH = look(150, 46, 78)
		local TONGUE = rgb(226, 96, 130)
		local TOOTH = rgb(250, 252, 255)
		local ICE = rgb(120, 214, 255)
		local GLOW = rgb(170, 246, 255)
		local CLAW = rgb(214, 236, 252)

		local tones = {
			[FUR] = { top = FUR_TOP, under = FUR_UNDER },
			[NAVY] = { top = NAVY_TOP, under = NAVY_UNDER },
		}

		-- A massive torso, hunched, with a white mane over its chest and shoulders and navy hide below and behind.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 32, 1 }, { 10, 9, 8 }), NAVY)
		body:add(ellipsoid({ 0, 42, 2 }, { 12.6, 9, 9 }), NAVY)
		body:add(ellipsoid({ 0, 50, -1 }, { 11, 5, 7 }), NAVY)
		body:add(ellipsoid({ 0, 46, -5 }, { 9, 6, 6 }), NAVY)
		body:coat(function(p)
			local y, z = p[2], p[3]
			if y > 43 + math.max(0, -z) * 0.35 or (z > 6 and y > 36) then
				return FUR
			end
			return nil
		end)
		body:bake(tones)

		-- The head: a navy face under a heavy brow, mouth open in a roar, framed in white mane.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 54, 9.4 }, { 6.6, 6.2, 6.4 }), FUR)
		head:add(ellipsoid({ 0, 56.6, 14.4 }, { 5.6, 1.7, 2.2 }), NAVY)
		head:add(ellipsoid({ 0, 51, 14.6 }, { 4.6, 3.4, 3.6 }), NAVY)
		head:add(ellipsoid({ 0, 46.8, 13.6 }, { 3.8, 1.8, 3.4 }), NAVY)
		head:carve(ellipsoid({ 0, 48.8, 17.4 }, { 3.4, 1.9, 3.8 }))
		head:coat(function(p, open)
			local y, z = p[2], p[3]
			if z > 13 and y > 47.4 and y < 50.4 and math.abs(p[1]) < 3 then
				return MOUTH
			end
			if z > 12.4 and y < 58 and math.abs(p[1]) < 5 and open(0, 0, 1) then
				return NAVY
			end
			return nil
		end)
		head:bake(tones)

		-- Arms: thick upper arms, huge forearms with navy gauntlets of hide, great fists.
		local arm = newSculpt(U)
		arm:add(ellipsoid({ 12.6, 48, 0 }, { 6, 5.6, 6 }), FUR)
		arm:add(rod({ { 13, 46, 0.4, 5 }, { 17, 36, 2, 4.4 } }), FUR)
		arm:add(rod({ { 17, 36, 2, 4.6 }, { 19, 26, 4.6, 6 }, { 19.6, 19, 6, 5.6 } }), FUR)
		arm:add(ellipsoid({ 19.8, 14, 7 }, { 5.6, 5, 5.8 }), NAVY)
		arm:coat(function(p)
			if p[2] < 29 and p[2] > 16 and (math.floor(p[2] / 3) % 2 == 0 or p[1] > 20.6) then
				return NAVY
			end
			return nil
		end)
		arm:bake(tones)

		-- Short, thick legs on broad feet.
		local leg = newSculpt(U)
		leg:add(rod({ { 7, 26, 0, 6 }, { 8, 14, 2, 5.2 }, { 8.4, 5, 2, 5 } }), FUR)
		leg:add(ellipsoid({ 8.6, 2.6, 4.6 }, { 5.4, 2.6, 7 }), NAVY)
		leg:coat(function(p)
			if p[2] < 13 then
				return NAVY
			end
			return nil
		end)
		leg:bake(tones)

		local armMirror, legMirror = arm:mirror(), leg:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 26, 0 }))
		body:draw(bodyLimb, { head, arm, armMirror, leg, legMirror }, NAVY)
		-- A shaggy white mane bristling over its chest and shoulders.
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return p[2] > 42 and n[2] > -0.3 and noise(vadd(p, { 7, 3, 3 })) < 0.13
			end,
			4.4,
			2.6,
			{ 0, -0.6, -0.6 },
			function(p)
				return if noise(p) < 0.6 then FUR_TOP.color else FUR_UNDER.color
			end
		)
		-- Crystals bursting from its spine.
		for i, at in { { 0, 51.4, -6 }, { 0, 45, -9.4 }, { 0, 37.6, -5.6 } } do
			crystalCluster(bodyLimb, T, at, { 0, 0.8, -1 }, 9 - i * 1.4, 3, ICE, GLOW, NEON, NEON, i * 2)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 50, 6 }))
		head:draw(headLimb, { body }, NAVY)
		-- Glowing eyes under the brow.
		for _, s in { 1, -1 } do
			local face = frontOf(head, 2.8 * s, 54.4)
			T.ball(headLimb, { 2.8 * s, 54.4, face - 0.3 }, { 2.6, 1.3, 1 }, GLOW, NEON)
		end
		-- Fangs and teeth in the roaring mouth, and its tongue.
		local lip = frontOf(head, 0, 50.6)
		for _, s in { 1, -1 } do
			T.taper(headLimb, { 2.2 * s, 49.8, lip - 1 }, { 2 * s, 46.4, lip - 0.8 }, 1.3, 1.3, { 0, 0, 1 }, TOOTH)
			T.taper(headLimb, { 2.4 * s, 47.4, lip - 2 }, { 2.3 * s, 49.4, lip - 1.9 }, 1, 1, { 0, 0, 1 }, TOOTH)
			for i = 1, 2 do
				T.taper(
					headLimb,
					{ (2.6 - i * 0.2) * s, 49.6, lip - 1.6 - i * 1.4 },
					{ (2.6 - i * 0.2) * s, 48.4, lip - 1.6 - i * 1.4 },
					0.8,
					0.8,
					{ s, 0, 0 },
					TOOTH
				)
			end
		end
		T.ball(headLimb, { 0, 47.8, lip - 2.4 }, { 3.4, 1.2, 4 }, TONGUE)
		T.ball(headLimb, { 0, 52.6, lip + 0.2 }, { 2.4, 1.4, 1.2 }, NAVY_UNDER.color)
		-- A crest of white spikes over its head.
		fur(
			headLimb,
			T,
			head,
			function(p, n)
				return p[3] < 11 and n[2] > 0 and noise(vadd(p, { 2, 2, 9 })) < 0.22
			end,
			5.4,
			2.4,
			{ 0, 0.8, -1 },
			function(p)
				return if noise(p) < 0.6 then FUR_TOP.color else FUR_UNDER.color
			end
		)
		-- Great horns curling out, back and up, tipped with ice crystals.
		for _, s in { 1, -1 } do
			local horn = {
				{ 5.4 * s, 57, 8 },
				{ 9.4 * s, 60, 5.4 },
				{ 13 * s, 62.6, 6 },
				{ 15 * s, 66, 9.4 },
				{ 14.4 * s, 69.4, 12.6 },
			}
			for i = 1, #horn - 1 do
				local w = 3.2 - i * 0.5
				T.blade(headLimb, horn[i], horn[i + 1], w, w, { 0, 0, 1 }, NAVY.color)
				T.ball(headLimb, horn[i + 1], { w, w, w }, NAVY_TOP.color)
			end
			crystal(headLimb, T, horn[#horn], { -0.5 * s, 0.6, 0.6 }, 5.4, 1.6, ICE, GLOW, NEON, NEON)
		end

		pet:limbPair("LeftArm", "RightArm", T.at({ 12.6, 48, 0 }), function(limb)
			arm:draw(limb, { body }, NAVY)
			-- Crystal clusters on its shoulder and the outside of its forearm.
			crystalCluster(limb, T, { 14, 53, -1 }, { 0.6, 1, -0.3 }, 10, 4, ICE, GLOW, NEON, NEON, 5)
			crystalCluster(limb, T, { 24, 26, 3.6 }, { 1, 0.5, -0.4 }, 8, 4, ICE, GLOW, NEON, NEON, 7)
			for _, dz in { -1.8, -0.6, 0.6, 1.8 } do
				T.taper(limb, { 19.8 + dz, 11.4, 10 }, { 20 + dz * 1.2, 8.6, 13 }, 1.1, 1, { 0, 1, 0 }, CLAW)
			end
		end)
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 7, 26, 0 }), function(limb)
			leg:draw(limb, { body }, NAVY)
			for _, dx in { -2.6, 0, 2.6 } do
				T.taper(limb, { 8.6 + dx, 1.4, 10.6 }, { 8.6 + dx * 1.1, 0.3, 12.6 }, 1.2, 1, { 0, 1, 0 }, CLAW)
			end
		end)

		pet:light(GLOW, 3.4, 32)
		pet:particles("Snow", rgb(240, 250, 255), 18)
		pet:aura(rgb(90, 210, 255), rgb(240, 252, 255))
		pet:seat(0, 55.4 / U, -4 / U)
	end,
}

return Snow
