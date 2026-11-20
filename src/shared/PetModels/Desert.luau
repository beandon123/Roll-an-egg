--!strict
-- The Desert's pets, in the showpiece style (see PetModels/Forest for what that means): sculpted fine in voxels with
-- light baked in from above, crisp angled parts for claws, plates, pincers and regalia, and, the rarer they are, more
-- that glows: jewels, venom, then gold and turquoise eyes, hieroglyphs and auras.
-- Sizes run from about a player's height (the Meerkat) to several times it (the Sphinx).
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
local vadd = Kit.vadd
local vscale = Kit.vscale
local vnorm = Kit.vnorm
local vlerp = Kit.vlerp
local glossyEye = Kit.glossyEye
local fur = Kit.fur

local NEON = Kit.NEON
local EYE = Kit.EYE

local Desert: { [string]: Design } = {}

----------------------------------------------------------------------------------------------------------------
-- Meerkat (Common): a meerkat standing up on sentry duty, about a player's height, paws held at its chest, its tail
-- propped on the ground behind it, with a dark mask round its eyes and faint stripes down its back.

Desert.Meerkat = {
	name = "Meerkat",
	skeleton = "Biped",
	scale = 0.24,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local FUR = look(212, 172, 116)
		local FUR_TOP = look(232, 196, 142)
		local FUR_UNDER = look(170, 132, 84)
		local STRIPE = look(176, 136, 88)
		local CREAM = look(244, 222, 180)
		local CREAM_SHADE = look(214, 190, 150)
		local MASK = look(74, 52, 36)
		local DARK = rgb(70, 48, 34)
		local NOSE = rgb(40, 30, 26)

		local tones = {
			[FUR] = { top = FUR_TOP, under = FUR_UNDER },
			[CREAM] = { under = CREAM_SHADE },
		}

		-- An upright, pear-shaped body: pale belly, faint dark bands across its back, a long tail to lean on.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 9.4, 0 }, { 3.6, 5.2, 3.2 }), FUR)
		body:add(ellipsoid({ 0, 13.8, 0.4 }, { 2.9, 3.2, 2.6 }), FUR)
		body:add(rod({ { 0, 6, -2.4, 1.3 }, { 0, 2.8, -5.4, 0.95 }, { 0, 0.8, -8, 0.6 } }), FUR)
		body:coat(function(p, open)
			local y, z = p[2], p[3]
			if z > 0.8 and math.abs(p[1]) < 2.6 and y > 5 then
				return CREAM
			end
			if z < -1.4 and y > 7 and (y + 0.3 * math.abs(p[1])) % 1.8 < 0.55 then
				return STRIPE
			end
			if z < -6.4 then
				return MASK
			end
			if not open(0, 1, 0) and y < 4 and z > -2 then
				return CREAM
			end
			return nil
		end)
		body:bake(tones)

		-- A round head with a pointed snout, dark eye patches and little dark ears.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 18.6, 0.6 }, { 2.6, 2.4, 2.6 }), FUR)
		head:add(rod({ { 0, 18.2, 2, 1.6 }, { 0, 17.6, 5.2, 0.75 } }), FUR)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 2.5 * s, 19.2, -0.2 }, { 0.7, 0.9, 0.9 }), MASK)
		end
		head:coat(function(p)
			local x, y, z = p[1], p[2], p[3]
			for _, s in { 1, -1 } do
				if (x - 1.5 * s) ^ 2 + (y - 18.9) ^ 2 * 1.4 + (z - 2.2) ^ 2 < 2.4 then
					return MASK
				end
			end
			if y < 17.8 and z > 1.6 then
				return CREAM
			end
			return nil
		end)
		head:bake(tones)

		-- Paws held up at its chest.
		local arm = newSculpt(U)
		arm:add(rod({ { 2.3, 14, 1, 1.05 }, { 2.4, 11.8, 2.6, 0.85 }, { 1.6, 11.4, 3.3, 0.7 } }), FUR)
		arm:bake(tones)

		-- Crouched haunches on long flat feet.
		local leg = newSculpt(U)
		leg:add(ellipsoid({ 2.3, 4.4, -0.4 }, { 1.8, 2.7, 2.6 }), FUR)
		leg:add(rod({ { 2.3, 1.6, -0.6, 1 }, { 2.3, 0.7, -0.8, 0.9 }, { 2.3, 0.6, 2.6, 0.8 } }), FUR)
		leg:bake(tones)

		local armMirror, legMirror = arm:mirror(), leg:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 6, 0 })), { head, arm, armMirror, leg, legMirror }, FUR)
		local headLimb = pet:limb("Head", T.at({ 0, 16.6, 0.4 }))
		head:draw(headLimb, { body }, FUR)
		glossyEye(headLimb, T, head, 18.9, 2.2, 1.3)
		T.ball(headLimb, { 0, 17.8, 5.6 }, { 1.1, 0.8, 0.7 }, NOSE)
		pet:limbPair("LeftArm", "RightArm", T.at({ 2.3, 14, 1 }), function(limb)
			arm:draw(limb, { body }, FUR)
			for _, dx in { -0.4, 0.1, 0.6 } do
				T.taper(limb, { 1.6 + dx, 11, 3.6 }, { 1.5 + dx, 10.2, 3.8 }, 0.25, 0.25, { 0, 0, 1 }, DARK)
			end
		end)
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 2.3, 5.6, -0.4 }), function(limb)
			leg:draw(limb, { body }, FUR)
			for _, dx in { -0.35, 0, 0.35 } do
				T.taper(limb, { 2.3 + dx, 0.6, 2.6 }, { 2.3 + dx * 1.3, 0.2, 3.8 }, 0.3, 0.3, { 0, 1, 0 }, DARK)
			end
		end)

		pet:seat(0, 15.6, -3.2)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Armadillo (Uncommon): an armadillo in a domed shell of sandstone bands, each banded ridge standing proud, with an
-- armoured head cap, big ears, digging claws and a ringed tail.

Desert.Armadillo = {
	name = "Armadillo",
	skeleton = "LowSlung",
	scale = 0.32,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local SHELL = look(214, 166, 108)
		local SHELL_TOP = look(234, 192, 134)
		local SHELL_UNDER = look(170, 124, 76)
		local BAND = look(176, 104, 62)
		local BAND_TOP = look(200, 128, 80)
		local SCUTE = look(194, 144, 90)
		local SKIN = look(230, 192, 158)
		local SKIN_SHADE = look(196, 156, 124)
		local INNER = rgb(240, 160, 160)
		local CLAW = rgb(70, 50, 36)

		local tones = {
			[SHELL] = { top = SHELL_TOP, under = SHELL_UNDER },
			[BAND] = { top = BAND_TOP, under = SHELL_UNDER },
			[SKIN] = { under = SKIN_SHADE },
		}

		-- The shell: a long dome, shields at front and back with a scaly pattern, and raised bands round its middle.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 6.6, -1 }, { 5.6, 5.4, 8.4 }), SHELL)
		local bands = { -4.2, -2.4, -0.6, 1.2, 3 }
		for _, z in bands do
			body:add(ellipsoid({ 0, 6.6, z }, { 6, 5.8, 0.7 }), BAND)
		end
		body:add(ellipsoid({ 0, 3, -1 }, { 4.6, 2.2, 7.4 }), SKIN)
		body:carve(ellipsoid({ 0, -1, -1 }, { 8, 2.6, 11 }))
		body:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if y < 3.4 and not open(0, 1, 0) then
				return SKIN
			end
			local near = false
			for _, b in bands do
				near = near or math.abs(z - b) < 0.75
			end
			if near then
				return BAND
			end
			-- A scaly pattern on the front and back shields.
			if (z > 3.8 or z < -5) and (math.floor(x / 1.4) + math.floor(y / 1.4) + math.floor(z / 1.4)) % 2 == 0 then
				return SCUTE
			end
			return nil
		end)
		body:bake(tones)

		-- A long tapering snout under an armoured cap.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 5.6, 7.4 }, { 2.5, 2.3, 2.6 }), SKIN)
		head:add(rod({ { 0, 5, 8.6, 1.7 }, { 0, 4.2, 12.4, 0.8 } }), SKIN)
		head:add(ellipsoid({ 0, 4.4, 12.8 }, { 0.8, 0.6, 0.5 }), BAND)
		head:coat(function(p, open)
			if open(0, 1, 0) and p[2] > 5.6 then
				return SCUTE
			end
			return nil
		end)
		head:bake(tones)

		local function foot(s: Sculpt, x: number, z: number)
			s:add(rod({ { x, 3.4, z, 1.3 }, { x, 0.9, z + 0.3, 1.1 } }), SKIN)
			s:add(ellipsoid({ x, 0.6, z + 0.7 }, { 1.2, 0.6, 1.4 }), SKIN)
			s:bake(tones)
		end
		local front, back = newSculpt(U), newSculpt(U)
		foot(front, 4, 4.2)
		foot(back, 4.2, -5.4)

		-- A ringed tail tapering to a point.
		local spine = { { 0, 4.6, -8.8, 1.7 }, { 0, 3, -12.4, 1.1 }, { 0, 1.5, -15.6, 0.5 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), SHELL)
		tail:coat(function(p)
			if (p[3] + 30) % 1.6 < 0.55 then
				return BAND
			end
			return nil
		end)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 4, 0 })), { head, front, frontMirror, back, backMirror, tail }, SHELL)
		local headLimb = pet:limb("Head", T.at({ 0, 5, 6.6 }))
		head:draw(headLimb, { body }, SHELL)
		glossyEye(headLimb, T, head, 6.3, 9.2, 1.1)
		for _, s in { 1, -1 } do
			-- Big upright ears, pink inside.
			T.taper(headLimb, { 1.6 * s, 7.4, 7.6 }, { 3 * s, 11, 6.6 }, 1.9, 0.6, { s * 0.4, 0, 1 }, SKIN.color)
			T.taper(headLimb, { 1.65 * s, 7.6, 7.95 }, { 2.9 * s, 10.4, 7 }, 1.1, 0.25, { s * 0.4, 0, 1 }, INNER)
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 4, 3.4, 4.2 }), function(limb)
			front:draw(limb, { body }, SHELL)
			-- Long digging claws.
			for _, dx in { -0.6, 0, 0.6 } do
				T.taper(limb, { 4 + dx, 0.6, 5.8 }, { 4 + dx * 1.3, 0.15, 7.4 }, 0.45, 0.4, { 0, 1, 0 }, CLAW)
			end
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4.2, 3.4, -5.4 }), function(limb)
			back:draw(limb, { body }, SHELL)
			for _, dx in { -0.5, 0.5 } do
				T.taper(limb, { 4.2 + dx, 0.6, -4 }, { 4.2 + dx * 1.3, 0.15, -3 }, 0.4, 0.35, { 0, 1, 0 }, CLAW)
			end
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 4.4, -8.2 })), { body }, SHELL)

		pet:seat(0, 12, -1)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Fennec Fox (Uncommon): a little cream desert fox made big enough to ride, with enormous ears, huge dark eyes, a
-- ginger back and a bushy black-tipped tail.

Desert.FennecFox = {
	name = "Fennec Fox",
	skeleton = "Quadruped",
	scale = 0.21,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local CREAM = look(246, 228, 192)
		local CREAM_SHADE = look(214, 192, 156)
		local GINGER = look(226, 158, 92)
		local GINGER_TOP = look(240, 182, 116)
		local GINGER_UNDER = look(190, 124, 70)
		local TIP = look(64, 44, 34)
		local NOSE = rgb(36, 28, 26)
		local INNER = rgb(246, 170, 174)
		local TUFT = rgb(252, 244, 228)
		local IRIS = rgb(60, 36, 24)

		local tones = {
			[CREAM] = { under = CREAM_SHADE },
			[GINGER] = { top = GINGER_TOP, under = GINGER_UNDER },
		}

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 8.4, -1.2 }, { 3, 2.9, 5.6 }), CREAM)
		body:add(ellipsoid({ 0, 8.8, 3 }, { 2.8, 3.2, 2.8 }), CREAM)
		body:add(rod({ { 0, 9.6, 4, 2.3 }, { 0, 11.4, 6, 2 } }), CREAM)
		body:coat(function(p, open)
			if p[2] > 9.4 and p[3] < 3.4 and (open(0, 1, 0) or math.abs(p[1]) < 2.6) then
				return GINGER
			end
			return nil
		end)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 12.8, 6.8 }, { 3.1, 2.8, 2.9 }), CREAM)
		head:add(rod({ { 0, 12.2, 8.4, 1.6 }, { 0, 11.9, 11, 0.8 } }), CREAM)
		head:coat(function(p, open)
			if open(0, 1, 0) and p[3] < 8.6 then
				return GINGER
			end
			return nil
		end)
		head:bake(tones)

		local front, back = newSculpt(U), newSculpt(U)
		front:add(rod({ { 1.9, 8.4, 3.4, 1.3 }, { 2, 4.6, 3.8, 0.95 }, { 1.9, 1, 4, 0.8 } }), CREAM)
		front:add(ellipsoid({ 1.9, 0.65, 4.4 }, { 0.9, 0.65, 1.2 }), CREAM)
		front:bake(tones)
		back:add(ellipsoid({ 2.2, 8.4, -4.6 }, { 1.5, 2.6, 2.8 }), CREAM)
		back:add(rod({ { 2.2, 7.4, -5, 1.2 }, { 2.1, 4, -6, 0.95 }, { 2, 1, -5, 0.8 } }), CREAM)
		back:add(ellipsoid({ 2, 0.65, -4.6 }, { 0.9, 0.65, 1.2 }), CREAM)
		back:coat(function(p, open)
			if p[2] > 8 and open(0, 1, 0) then
				return GINGER
			end
			return nil
		end)
		back:bake(tones)

		local spine = { { 0, 9, -6.6, 1.3 }, { 0, 8, -9.6, 2.1 }, { 0, 6.6, -12.6, 2.2 }, { 0, 5.8, -15.2, 1.3 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), GINGER)
		tail:coat(function(p)
			if p[3] < -13.6 then
				return TIP
			end
			return nil
		end)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 8.4, 0 })), { head, front, frontMirror, back, backMirror, tail }, CREAM)
		local headLimb = pet:limb("Head", T.at({ 0, 11, 5.4 }))
		head:draw(headLimb, { body }, CREAM)
		glossyEye(headLimb, T, head, 13.2, 8.8, 1.9, nil, IRIS)
		T.ball(headLimb, { 0, 12, 11.3 }, { 1, 0.75, 0.8 }, NOSE)
		for _, s in { 1, -1 } do
			-- Enormous ears: ginger behind, pink inside with pale tufts.
			T.taper(
				headLimb,
				{ 1.9 * s, 14.4, 6.4 },
				{ 5.4 * s, 22.6, 5.2 },
				4.4,
				0.9,
				{ s * 0.25, 0, 1 },
				GINGER.color
			)
			T.taper(headLimb, { 1.95 * s, 14.8, 6.95 }, { 5.1 * s, 21.6, 5.8 }, 3, 0.3, { s * 0.25, 0, 1 }, INNER)
			T.taper(headLimb, { 2 * s, 14.8, 7.15 }, { 3.6 * s, 18, 6.6 }, 2, 0.3, { s * 0.25, 0, 1 }, TUFT)
			-- Dark lines from the eyes down the muzzle.
			T.blade(headLimb, { 1.3 * s, 12.4, 10 }, { 2.2 * s, 11.6, 8.2 }, 0.25, 0.2, { s, 0, 0.4 }, TIP.color)
		end

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 1.9, 8.4, 3.4 }), function(limb)
			front:draw(limb, { body }, CREAM)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 2.2, 8.4, -4.6 }), function(limb)
			back:draw(limb, { body }, CREAM)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 9, -6.2 }))
		tail:draw(tailLimb, { body }, CREAM)
		fur(
			tailLimb,
			T,
			tail,
			function(p, n)
				return n[2] > -0.4 and noise(vadd(p, { 4, 2, 6 })) < 0.14
			end,
			1.1,
			0.7,
			{ 0, 0, -0.6 },
			function(p)
				return if p[3] < -13.6 then TIP.color else GINGER_TOP.color
			end
		)

		pet:seat(0, 11.6, -1.4)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Camel (Rare): a tall two-humped caravan camel, twice a player's height, with shaggy humps and a beard, a saddle
-- cushion between its humps on a red blanket trimmed in gold, and a harness hung with glowing jewels.

Desert.Camel = {
	name = "Camel",
	skeleton = "Strider",
	gait = "Stomp",
	scale = 0.3,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local COAT = look(212, 160, 100)
		local COAT_TOP = look(232, 186, 126)
		local COAT_UNDER = look(164, 116, 66)
		local COAT_LOW = look(186, 136, 82)
		local SHAGGY = look(150, 100, 56)
		local SHAGGY_TOP = look(176, 124, 74)
		local BLANKET = look(196, 46, 52)
		local BLANKET_TOP = look(222, 66, 70)
		local BLANKET_UNDER = look(150, 30, 40)
		local TRIM = look(255, 196, 56)
		local DIAMOND = look(52, 176, 172)
		local NOSE = rgb(70, 46, 30)
		local LASH = rgb(60, 40, 28)
		local PAD = rgb(110, 76, 44)
		local STRAP = rgb(132, 78, 40)
		local GEM = rgb(70, 240, 230)
		local GOLD = rgb(255, 204, 70)

		local tones = {
			[COAT] = { top = COAT_TOP, under = COAT_UNDER, low = COAT_LOW, below = 12 },
			[SHAGGY] = { top = SHAGGY_TOP },
			[BLANKET] = { top = BLANKET_TOP, under = BLANKET_UNDER },
		}

		-- A deep barrel of a body under two shaggy humps, with a red blanket over its back between them.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 20, -1 }, { 5, 5, 10 }), COAT)
		body:add(ellipsoid({ 0, 19.6, 6.4 }, { 4.6, 5.2, 4.4 }), COAT)
		for _, z in { 4.6, -6.6 } do
			body:add(ellipsoid({ 0, 26, z }, { 3.9, 5.4, 4.2 }), COAT)
		end
		body:add(rod({ { 0, 21, 8.6, 3.4 }, { 0, 19.4, 12.4, 2.6 }, { 0, 22.8, 15.2, 2.3 } }), COAT)
		body:coat(function(p, open)
			local y, z = p[2], p[3]
			-- Shaggy hair on top of the humps and under the neck.
			if y > 27.6 then
				return SHAGGY
			end
			if z > 9 and y < 20 and not open(0, 1, 0) then
				return SHAGGY
			end
			-- The blanket: draped over the back between the humps and down the flanks, trimmed in gold, with teal
			-- diamonds along its edge.
			if math.abs(z + 1) < 4 and y > 15.4 then
				if y < 16.6 or math.abs(z + 1) > 3.4 then
					return TRIM
				end
				if y < 18.2 and (z + 30) % 2.2 < 1 then
					return DIAMOND
				end
				return BLANKET
			end
			return nil
		end)
		body:bake(tones)

		-- A long head held high on the curve of its neck: drooping lips, heavy-lidded eyes with long lashes.
		local head = newSculpt(U)
		head:add(rod({ { 0, 22.8, 15.2, 2.3 }, { 0, 28.4, 16.4, 2.2 } }), COAT)
		head:add(ellipsoid({ 0, 30.2, 18 }, { 2.4, 2.4, 3.2 }), COAT)
		head:add(rod({ { 0, 29.6, 19.6, 2 }, { 0, 28.6, 23, 1.6 } }), COAT)
		head:add(ellipsoid({ 0, 27.4, 22.6 }, { 1.4, 0.9, 1.6 }), COAT)
		head:coat(function(p, open)
			if p[3] < 17 and not open(0, 1, 0) and p[2] < 27 then
				return SHAGGY
			end
			return nil
		end)
		head:bake(tones)

		-- Long legs with knobbly knees and broad padded feet.
		-- Each leg in two halves, bending at the knee (or, behind, the hock).
		local front, frontShin = newSculpt(U), newSculpt(U)
		front:add(rod({ { 3.2, 19, 6.6, 2.6 }, { 3.4, 11, 7.2, 1.4 } }), COAT)
		front:add(ellipsoid({ 3.4, 11, 7.4 }, { 1.8, 1.7, 1.8 }), COAT)
		frontShin:add(rod({ { 3.4, 11, 7.2, 1.35 }, { 3.4, 2, 7, 1.2 } }), COAT)
		frontShin:add(ellipsoid({ 3.4, 0.9, 7.6 }, { 1.9, 0.9, 2.2 }), COAT)
		local back, backShin = newSculpt(U), newSculpt(U)
		back:add(ellipsoid({ 3.4, 18.4, -8.4 }, { 2.6, 5, 3.8 }), COAT)
		back:add(rod({ { 3.4, 14, -9.6, 2 }, { 3.4, 9.6, -10.6, 1.4 } }), COAT)
		backShin:add(rod({ { 3.4, 9.6, -10.6, 1.35 }, { 3.4, 2, -9.4, 1.2 } }), COAT)
		backShin:add(ellipsoid({ 3.4, 0.9, -8.8 }, { 1.9, 0.9, 2.2 }), COAT)
		for _, s in { front, frontShin, back, backShin } do
			s:bake(tones)
		end

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 22, -10.8, 0.9 }, { 0, 17.4, -12.2, 0.7 } }), COAT)
		tail:add(ellipsoid({ 0, 16.4, -12.4 }, { 1, 1.6, 1 }), SHAGGY)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 20, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, COAT)
		-- Shaggy tufts on the humps and a beard under the neck.
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return p[2] > 27 and n[2] > 0.3 and noise(vadd(p, { 3, 1, 4 })) < 0.35
			end,
			1.8,
			1.3,
			{ 0, 0, -0.8 },
			function(p)
				return if noise(p) < 0.5 then SHAGGY.color else SHAGGY_TOP.color
			end
		)
		fur(
			bodyLimb,
			T,
			body,
			function(p, n)
				return p[3] > 9 and n[2] < -0.3 and noise(vadd(p, { 8, 2, 1 })) < 0.4
			end,
			2.2,
			1.2,
			{ 0, -1.4, 0 },
			function()
				return SHAGGY.color
			end
		)
		-- A saddle cushion between the humps, tasselled at its corners.
		T.ball(bodyLimb, { 0, 25.2, -1 }, { 6.4, 2.2, 4.6 }, BLANKET_TOP.color)
		T.ball(bodyLimb, { 0, 26, -1 }, { 4.6, 1.2, 3 }, GOLD)
		for _, s in { 1, -1 } do
			for _, z in { 2.8, -4.8 } do
				local x = sideOf(body, 16, z) - 0.5
				T.blade(bodyLimb, { x * s, 16.4, z }, { (x + 0.2) * s, 14, z }, 0.35, 0.35, { s, 0, 0 }, TRIM.color)
				T.ball(bodyLimb, { (x + 0.2) * s, 13.6, z }, { 0.9, 1.2, 0.9 }, GEM, NEON)
			end
			-- A breast strap round its chest, studded with glowing jewels.
			for i = 0, 3 do
				local y = 16.4 + i * 1.9
				local z = 9.4 - i * 0.5
				T.ball(bodyLimb, { (sideOf(body, y, z) - 0.2) * s * 0.55, y, z + 1.2 }, { 1, 1, 0.7 }, GOLD, NEON)
			end
		end
		T.blade(bodyLimb, { 0, 15.4, 10.6 }, { 0, 24.4, 9.6 }, 1.6, 0.6, { 0, 0, 1 }, STRAP)

		local headLimb = pet:limb("Head", T.at({ 0, 24, 15.4 }))
		head:draw(headLimb, { body }, COAT)
		for _, s in { 1, -1 } do
			local x = sideOf(head, 30.6, 19.4)
			T.ball(headLimb, { (x - 0.25) * s, 30.6, 19.4 }, { 0.6, 1.1, 1.4 }, EYE)
			T.ball(headLimb, { (x - 0.05) * s, 30.95, 19.5 }, { 0.25, 0.35, 0.4 }, rgb(255, 255, 255))
			-- A heavy lid and long lashes.
			T.blade(
				headLimb,
				{ (x - 0.2) * s, 31.4, 18.6 },
				{ (x - 0.2) * s, 31.4, 20.4 },
				0.6,
				0.6,
				{ s, 1, 0 },
				COAT_UNDER.color
			)
			for _, dz in { -0.5, 0.1, 0.7 } do
				T.taper(
					headLimb,
					{ x * s, 31.5, 19.4 + dz },
					{ (x + 0.6) * s, 32.2, 19.6 + dz * 1.3 },
					0.2,
					0.15,
					{ 0, 1, 0 },
					LASH
				)
			end
			-- Small ears.
			T.taper(headLimb, { 1.8 * s, 32, 16.6 }, { 2.6 * s, 33.6, 15.6 }, 1, 0.5, { 0, 0, 1 }, COAT.color)
			-- Nostrils.
			T.blade(headLimb, { 0.7 * s, 29.6, 24.4 }, { 0.9 * s, 29, 24.4 }, 0.3, 0.3, { 0, 0, 1 }, NOSE)
			-- A bridle with a glowing jewel at the cheek.
			T.ball(headLimb, { (sideOf(head, 28.6, 20.6) + 0.15) * s, 28.6, 20.6 }, { 0.5, 1.1, 1.1 }, GEM, NEON)
		end
		T.blade(headLimb, { -2.1, 29.2, 20.4 }, { 2.1, 29.2, 20.4 }, 0.5, 0.5, { 0, 0, 1 }, STRAP)
		T.blade(headLimb, { 0, 27.2, 23.6 }, { 0, 27.4, 21.6 }, 1.4, 0.8, { 0, 1, 0 }, NOSE)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3.2, 19, 6.6 }), function(limb)
			front:draw(limb, { body, frontShin }, COAT)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 3.4, 11, 7.2 }), function(limb)
			frontShin:draw(limb, { front }, COAT)
			for _, dx in { -0.7, 0.7 } do
				T.taper(limb, { 3.4 + dx, 0.6, 9.2 }, { 3.4 + dx, 0.2, 10.2 }, 0.6, 0.5, { 0, 1, 0 }, PAD)
			end
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3.4, 18.4, -8.4 }), function(limb)
			back:draw(limb, { body, backShin }, COAT)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 3.4, 9.6, -10.6 }), function(limb)
			backShin:draw(limb, { back }, COAT)
			for _, dx in { -0.7, 0.7 } do
				T.taper(limb, { 3.4 + dx, 0.6, -7.2 }, { 3.4 + dx, 0.2, -6.2 }, 0.6, 0.5, { 0, 1, 0 }, PAD)
			end
		end, "BackLeftLeg")
		tail:draw(pet:limb("Tail", T.at({ 0, 22, -10.6 })), { body }, COAT)

		pet:seat(0, 26.6, -1)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Giant Scorpion (Epic): a scorpion longer than a car, armoured in ridged amber plates, pincers raised, its glowing
-- eyes clustered on its head and its tail curled high over its back to a stinger dripping glowing venom.

-- Draws one jointed leg of `segments` (from the body out to the foot) as blades, with a spur at each joint.
local function jointedLeg(limb: Limb, T: any, points: { Vec }, widths: { number }, color: { number }, joint: { number })
	for i = 1, #points - 1 do
		if i == #points - 1 then
			T.taper(limb, points[i], points[i + 1], widths[i], widths[i], { 0, 1, 0 }, color)
		else
			T.blade(limb, points[i], points[i + 1], widths[i], widths[i], { 0, 1, 0 }, color)
			T.ball(limb, points[i + 1], { widths[i] * 1.25, widths[i] * 1.25, widths[i] * 1.25 }, joint)
		end
	end
end

Desert.GiantScorpion = {
	name = "Giant Scorpion",
	skeleton = "ManyLegged",
	scale = 0.36 * 1.2,
	draw = function(pet)
		-- Built in cells 1.2 design units across.
		local U = 1.2
		local T = inUnits(U)
		local CHITIN = look(118, 58, 26)
		local CHITIN_TOP = look(150, 80, 36)
		local CHITIN_UNDER = look(72, 34, 16)
		local EDGE = look(206, 122, 50)
		local EDGE_TOP = look(232, 152, 72)
		local BELLY = look(212, 150, 86)
		local BELLY_SHADE = look(170, 112, 60)
		local VENOM = rgb(150, 255, 90)
		local SPINE = rgb(56, 28, 14)
		local JOINT = rgb(206, 122, 50)

		local tones = {
			[CHITIN] = { top = CHITIN_TOP, under = CHITIN_UNDER },
			[EDGE] = { top = EDGE_TOP, under = CHITIN },
			[BELLY] = { under = BELLY_SHADE },
		}

		-- The body: a long, flat back of overlapping plates, each with a pale rim, over a pale belly.
		local plates = { 3, 0.6, -1.8, -4.2, -6.6, -9 }
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 6.8, -3 }, { 5.8, 2.9, 8 }), CHITIN)
		for i, z in plates do
			local w = 5.6 - math.abs(i - 3) * 0.3
			body:add(ellipsoid({ 0, 7.2, z }, { w, 2.8, 1.15 }), CHITIN)
		end
		body:coat(function(p, open)
			if not open(0, 1, 0) and p[2] < 6 then
				return BELLY
			end
			for _, z in plates do
				if p[3] > z + 0.7 and p[3] < z + 1.5 then
					return EDGE
				end
			end
			return nil
		end)
		body:bake(tones)

		-- The head: a broad shield, and the arms with their great pincers.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 7, 6.6 }, { 4.4, 2.5, 3.8 }), CHITIN)
		for _, s in { 1, -1 } do
			head:add(
				rod({ { 3.2 * s, 6.6, 8.2, 1.3 }, { 7.4 * s, 8.2, 11.4, 1.3 }, { 7.2 * s, 8.4, 15.4, 1.15 } }),
				CHITIN
			)
			head:add(ellipsoid({ 6.6 * s, 8.6, 18.4 }, { 2.5, 2.3, 3.6 }), CHITIN)
			head:add(ellipsoid({ 0.9 * s, 6.2, 10 }, { 0.8, 0.8, 1 }), EDGE)
		end
		head:coat(function(p, open)
			if not open(0, 1, 0) and p[2] < 6.4 then
				return BELLY
			end
			-- Pale rims round the joints of the arms and the knuckles of the pincers.
			for _, s in { 1, -1 } do
				if (p[1] - 7.4 * s) ^ 2 + (p[2] - 8.2) ^ 2 + (p[3] - 11.4) ^ 2 < 2.6 then
					return EDGE
				end
				if (p[1] - 7.2 * s) ^ 2 + (p[2] - 8.4) ^ 2 + (p[3] - 15.2) ^ 2 < 1.8 then
					return EDGE
				end
			end
			return nil
		end)
		head:bake(tones)

		-- The tail: five swollen segments curling up and over its back, ending in the venom bulb.
		local spine = {
			{ 0, 7.4, -10, 2 },
			{ 0, 9.4, -14, 1.9 },
			{ 0, 13.6, -16.8, 1.8 },
			{ 0, 18.4, -16.6, 1.7 },
			{ 0, 22, -14, 1.6 },
			{ 0, 23.4, -10.6, 1.5 },
		}
		local tail = newSculpt(U)
		tail:add(rod(spine), CHITIN)
		for i = 1, #spine - 1 do
			local mid = vlerp(spine[i], spine[i + 1], 0.5)
			local r = spine[i][4] * 1.18
			tail:add(ellipsoid({ mid[1], mid[2], mid[3] }, { r, r, r }), CHITIN)
		end
		tail:add(ellipsoid({ 0, 22.6, -8.4 }, { 2, 1.9, 2.3 }), CHITIN)
		tail:coat(function(p)
			for i = 2, #spine - 1 do
				local q = spine[i]
				if (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2 < (q[4] * 1.05) ^ 2 then
					return EDGE
				end
			end
			return nil
		end)
		tail:bake(tones)

		local bodyLimb = pet:limb("Body", T.at({ 0, 6, 0 }))
		body:draw(bodyLimb, { head, tail }, CHITIN)
		-- A keel of short spines down the middle of its back.
		for i, z in plates do
			if i > 1 and i < #plates then
				T.taper(bodyLimb, { 0, 9.4, z + 0.8 }, { 0, 10.8, z + 0.2 }, 0.9, 0.7, { 1, 0, 0 }, SPINE)
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 6.6, 4.6 }))
		head:draw(headLimb, { body }, CHITIN)
		-- A cluster of glowing eyes: two big ones on top, three small at each front corner.
		for _, s in { 1, -1 } do
			T.ball(headLimb, { 0.8 * s, 9.3, 7.4 }, { 1.2, 1, 1.2 }, VENOM, NEON)
			for i = 0, 2 do
				T.ball(headLimb, { (3 + i * 0.35) * s, 8.2 - i * 0.2, 8.8 - i * 0.7 }, { 0.6, 0.6, 0.6 }, VENOM, NEON)
			end
			-- The pincer's two fingers, open, with teeth along their inner edges.
			local fixed = { { 5.6 * s, 8.6, 20.6 }, { 5 * s, 8.9, 23.6 }, { 5.6 * s, 9, 26.4 } }
			local moving = { { 7.8 * s, 8.4, 20.6 }, { 8.4 * s, 8.6, 23.4 }, { 7.2 * s, 8.8, 26 } }
			for _, finger in { fixed, moving } do
				T.blade(headLimb, finger[1], finger[2], 1.6, 1.4, { 0, 1, 0 }, CHITIN.color)
				T.taper(headLimb, finger[2], finger[3], 1.4, 1.2, { 0, 1, 0 }, SPINE)
			end
			for i = 1, 3 do
				local f = vlerp(fixed[1], fixed[2], i / 4)
				local m = vlerp(moving[1], moving[2], i / 4)
				T.taper(headLimb, f, vadd(f, { 0.9 * s, 0, 0.3 }), 0.4, 0.4, { 0, 1, 0 }, EDGE.color)
				T.taper(headLimb, m, vadd(m, { -0.9 * s, 0, 0.3 }), 0.4, 0.4, { 0, 1, 0 }, EDGE.color)
			end
		end

		-- Three pairs of jointed legs, splayed out and down.
		local function legs(left: string, right: string, z: number, dz: number)
			pet:limbPair(left, right, T.at({ 4.6, 6.4, z }), function(limb)
				jointedLeg(limb, T, {
					{ 4.4, 6.4, z },
					{ 8.6, 9.8, z + dz },
					{ 11.4, 3.6, z + dz * 1.4 },
					{ 12.4, 0, z + dz * 1.6 },
				}, { 1.6, 1.3, 1 }, CHITIN.color, JOINT)
				T.taper(limb, { 8.2, 9.6, z + dz }, { 8.6, 11.4, z + dz - 0.6 }, 0.5, 0.5, { 0, 0, 1 }, SPINE)
			end)
		end
		legs("FrontLeftLeg", "FrontRightLeg", 2, 1.8)
		legs("MiddleLeftLeg", "MiddleRightLeg", -2.4, 0)
		legs("BackLeftLeg", "BackRightLeg", -6.6, -1.8)

		local tailLimb = pet:limb("Tail", T.at({ 0, 7.4, -9.6 }))
		tail:draw(tailLimb, { body }, CHITIN)
		-- A glowing seam of venom along the top of the tail, a stinger, and a drop of venom at its tip.
		for i = 1, #spine - 1 do
			local a, c = spine[i], spine[i + 1]
			local up = { 0, 1, 0 }
			local function onTop(q: { number }): Vec
				local along = vnorm({ c[1] - a[1], c[2] - a[2], c[3] - a[3] })
				local out = vnorm(vadd(up, vscale(along, -along[2])))
				return vadd({ q[1], q[2], q[3] }, vscale(out, q[4] * 0.95))
			end
			T.blade(tailLimb, onTop(a), onTop(c), 0.45, 0.35, { 0, 1, 0 }, VENOM, NEON)
		end
		T.ball(tailLimb, { 0, 22.6, -8.4 }, { 3, 2.6, 3.4 }, rgb(200, 255, 130), NEON)
		T.blade(tailLimb, { 0, 22, -7.2 }, { 0, 20.4, -6.2 }, 1.2, 1.2, { 1, 0, 0 }, SPINE)
		T.taper(tailLimb, { 0, 20.4, -6.2 }, { 0, 18.6, -5.6 }, 1, 1, { 1, 0, 0 }, VENOM, NEON)
		T.ball(tailLimb, { 0, 18.4, -5.6 }, { 0.7, 0.9, 0.7 }, VENOM, NEON)

		pet:seat(0, 10.6 / U, -2.6 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Pharaoh Jackal (Legendary): a tall black jackal of the pharaohs' tombs, in a broad collar of gold, lapis and
-- turquoise, gold cuffs on its ears and legs and a golden cobra at its brow, with glowing eyes, a glowing gold ankh on
-- each flank, and a golden aura.

Desert.PharaohJackal = {
	name = "Pharaoh Jackal",
	skeleton = "Strider",
	scale = 0.32,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local BLACK = look(36, 32, 42)
		local SHEEN = look(74, 68, 92)
		local BLACK_UNDER = look(20, 18, 24)
		local GOLD = look(255, 192, 52)
		local GOLD_TOP = look(255, 226, 120)
		local GOLD_UNDER = look(190, 128, 28)
		local LAPIS = look(36, 80, 190)
		local TEAL = look(52, 178, 172)
		local NOSE = rgb(16, 14, 18)
		local GLOW = rgb(110, 255, 230)
		local RUNE = rgb(255, 210, 90)

		local tones = {
			[BLACK] = { top = SHEEN, under = BLACK_UNDER },
			[GOLD] = { top = GOLD_TOP, under = GOLD_UNDER },
		}

		-- A lean, deep-chested body with a broad collar over its chest and shoulders.
		local collar = { 0, 24.6, 8 }
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 21, -1 }, { 4.4, 4.6, 9.6 }), BLACK)
		body:add(ellipsoid({ 0, 21.6, 6.2 }, { 4.6, 5.6, 4.6 }), BLACK)
		body:add(ellipsoid({ 0, 22, -8.6 }, { 4.6, 5, 4.6 }), BLACK)
		body:add(rod({ { 0, 24, 8, 3.6 }, { 0, 29, 11, 2.8 } }), BLACK)
		body:coat(function(p)
			local x, y, z = p[1], p[2], p[3]
			if z > 3.4 and y > 18 then
				local d = math.sqrt(x * x + (y - collar[2]) ^ 2 + (z - collar[3]) ^ 2)
				if d > 3.6 and d <= 4.4 then
					return GOLD
				elseif d > 4.4 and d <= 5.2 then
					return LAPIS
				elseif d > 5.2 and d <= 5.9 then
					return TEAL
				elseif d > 5.9 and d <= 6.6 then
					return GOLD
				end
			end
			return nil
		end)
		body:bake(tones)

		-- A long narrow head with a pointed snout, a gold band round its brow.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 31, 12.4 }, { 3, 3, 3.6 }), BLACK)
		head:add(rod({ { 0, 30.2, 14.4, 2.1 }, { 0, 29.2, 20, 1.1 } }), BLACK)
		head:coat(function(p, open)
			if open(0, 1, 0) and p[3] > 11.2 and p[3] < 12.6 then
				return GOLD
			end
			return nil
		end)
		head:bake(tones)

		-- Long slim legs, each with a gold band.
		local function bands(s: Sculpt)
			s:coat(function(p)
				if p[2] > 7 and p[2] < 9 then
					return GOLD
				end
				return nil
			end)
			s:bake(tones)
		end
		local front, frontShin = newSculpt(U), newSculpt(U)
		front:add(rod({ { 3, 21, 6.4, 2.2 }, { 3.2, 12, 7, 1.5 } }), BLACK)
		frontShin:add(rod({ { 3.2, 12, 7, 1.45 }, { 3.1, 1.4, 7.2, 1.2 } }), BLACK)
		frontShin:add(ellipsoid({ 3.1, 0.9, 7.8 }, { 1.3, 0.9, 1.7 }), BLACK)
		local back, backShin = newSculpt(U), newSculpt(U)
		back:add(ellipsoid({ 3.2, 21, -8.6 }, { 2.4, 5, 3.8 }), BLACK)
		back:add(rod({ { 3.2, 16.4, -10, 2 }, { 3.2, 9.4, -11.6, 1.4 } }), BLACK)
		backShin:add(rod({ { 3.2, 9.4, -11.6, 1.35 }, { 3.1, 1.4, -9.8, 1.2 } }), BLACK)
		backShin:add(ellipsoid({ 3.1, 0.9, -9.2 }, { 1.3, 0.9, 1.7 }), BLACK)
		for _, s in { front, frontShin, back, backShin } do
			bands(s)
		end

		-- A long tail with a gold ring near the tip.
		local spine =
			{ { 0, 24.2, -12.6, 1.3 }, { 0, 21.4, -16, 1.6 }, { 0, 16.4, -17.6, 1.5 }, { 0, 12.6, -17.2, 0.9 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), BLACK)
		tail:coat(function(p)
			if p[2] > 14.4 and p[2] < 15.8 then
				return GOLD
			end
			return nil
		end)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 21, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, BLACK)
		-- Glowing gold beads strung along the collar's outer edge.
		for index, spot in
			body:surface(function(p)
				local d = math.sqrt(p[1] ^ 2 + (p[2] - collar[2]) ^ 2 + (p[3] - collar[3]) ^ 2)
				return d > 6.2 and d < 7 and p[3] > 5 and p[2] < collar[2]
			end)
		do
			if index % 3 == 0 then
				T.ball(bodyLimb, vadd(spot[1], vscale(spot[2], 0.35)), { 0.8, 0.8, 0.8 }, RUNE, NEON)
			end
		end
		-- A glowing ankh on each flank, with a row of hieroglyph marks under it.
		for _, s in { 1, -1 } do
			local function at(y: number, z: number): Vec
				return { (sideOf(body, y, z) + 0.12) * s, y, z }
			end
			local function stroke(a: Vec, c: Vec)
				T.blade(bodyLimb, a, c, 0.5, 0.3, { s, 0, 0 }, RUNE, NEON)
			end
			stroke(at(17.8, -2), at(21.4, -2))
			stroke(at(21.4, -3.6), at(21.4, -0.4))
			stroke(at(21.6, -2), at(22.8, -3))
			stroke(at(22.8, -3), at(24.2, -2))
			stroke(at(24.2, -2), at(22.8, -1))
			stroke(at(22.8, -1), at(21.6, -2))
			for i = 0, 3 do
				local z = 3.2 - i * 1.6
				stroke(at(18.6, z - 0.4), at(19.4, z))
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 28, 10.4 }))
		head:draw(headLimb, { body }, BLACK)
		Kit.slitEyes(headLimb, head, { 32, 15.2 }, { 32.5, 13 }, 0.9, GLOW, NEON, GOLD.color)
		T.ball(headLimb, { 0, 29.6, 20.4 }, { 1.4, 1, 1 }, NOSE)
		for _, s in { 1, -1 } do
			-- Tall pointed ears with gold cuffs.
			T.taper(headLimb, { 1.6 * s, 33.4, 11.6 }, { 2.8 * s, 40.6, 10.4 }, 2.4, 1, { 0, 0, 1 }, BLACK.color)
			T.taper(headLimb, { 1.65 * s, 33.8, 12.05 }, { 2.7 * s, 39.4, 10.95 }, 1.3, 0.3, { 0, 0, 1 }, LAPIS.color)
			T.blade(headLimb, { 1.6 * s, 34, 11.6 }, { 1.8 * s, 35.4, 11.4 }, 2.8, 1.4, { 0, 0, 1 }, GOLD.color)
		end
		-- A golden cobra rearing at its brow, its hood inlaid with lapis.
		T.blade(headLimb, { 0, 33.6, 13.6 }, { 0, 35.4, 14 }, 0.8, 0.8, { 0, 0, 1 }, GOLD.color)
		T.ball(headLimb, { 0, 35.6, 14 }, { 1.6, 1.8, 0.7 }, GOLD.color)
		T.ball(headLimb, { 0, 35.6, 14.3 }, { 0.8, 1, 0.3 }, LAPIS.color)
		T.ball(headLimb, { 0, 36.5, 14.3 }, { 0.6, 0.6, 0.8 }, GOLD.color)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 3, 21, 6.4 }), function(limb)
			front:draw(limb, { body, frontShin }, BLACK)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 3.2, 12, 7 }), function(limb)
			frontShin:draw(limb, { front }, BLACK)
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 3.2, 21, -8.6 }), function(limb)
			back:draw(limb, { body, backShin }, BLACK)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 3.2, 9.4, -11.6 }), function(limb)
			backShin:draw(limb, { back }, BLACK)
		end, "BackLeftLeg")
		tail:draw(pet:limb("Tail", T.at({ 0, 24, -12 })), { body }, BLACK)

		pet:light(rgb(255, 210, 110), 1.8, 18)
		pet:particles("Sparkles", rgb(255, 214, 110), 6)
		pet:aura(rgb(255, 184, 60), rgb(130, 255, 236))
		pet:seat(0, 26.4, -2.4)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Sphinx (Mythic): a living sandstone colossus, more than three times a player's height: a lion's body, the striped
-- headdress and beard of a pharaoh, folded wings of gold, lapis and turquoise feathers, glowing turquoise eyes, a
-- glowing ankh on its chest, an inscription glowing along its flanks and turquoise light shining through the cracks
-- in its stone.

Desert.Sphinx = {
	name = "Sphinx",
	skeleton = "Strider",
	gait = "Stomp",
	scale = 0.32 * 1.5,
	draw = function(pet)
		-- Built in cells 1.5 design units across.
		local U = 1.5
		local T = inUnits(U)
		local STONE = look(226, 190, 122)
		local STONE_TOP = look(244, 216, 160)
		local STONE_UNDER = look(170, 136, 80)
		local STONE_LOW = look(198, 160, 98)
		local WEATHER = look(206, 168, 104)
		local GOLD = look(255, 192, 52)
		local GOLD_TOP = look(255, 226, 120)
		local LAPIS = look(36, 80, 190)
		local LAPIS_TOP = look(64, 112, 220)
		local GLOW = look(90, 250, 230, NEON)
		local NOSE = rgb(120, 92, 56)
		local TEAL = rgb(52, 178, 172)

		local tones = {
			[STONE] = { top = STONE_TOP, under = STONE_UNDER, low = STONE_LOW, below = 6 },
			[WEATHER] = { under = STONE_UNDER },
			[GOLD] = { top = GOLD_TOP },
			[LAPIS] = { top = LAPIS_TOP },
		}

		-- Cracks in the stone with turquoise light shining through.
		local cracks = {
			{ { 9.4, 28, 6 }, { 9.6, 25, 3 }, { 9.2, 22, 1 } },
			{ { -9.2, 27, -10 }, { -9.6, 24, -12 }, { -9, 21, -11 } },
			{ { 9.6, 18, 14 }, { 9.8, 13, 13 }, { 9.6, 8, 14.6 } },
			{ { -9.8, 16, -18 }, { -10, 11, -19.4 }, { -9.6, 7, -18 } },
			{ { 5, 33, 18.4 }, { 2.6, 29, 19.6 }, { 4, 24, 19 } },
		}
		local function onCrack(p: Vec): boolean
			for _, path in cracks do
				for i = 1, #path - 1 do
					local a, c = path[i], path[i + 1]
					local lo, hi = math.min(a[2], c[2]), math.max(a[2], c[2])
					if p[2] >= lo - 0.5 and p[2] <= hi + 0.5 then
						local t = math.clamp((p[2] - a[2]) / (c[2] - a[2]), 0, 1)
						local x, z = a[1] + (c[1] - a[1]) * t, a[3] + (c[3] - a[3]) * t
						if (p[1] - x) ^ 2 + (p[3] - z) ^ 2 < 3.2 then
							return true
						end
					end
				end
			end
			return false
		end
		local function stone(p: Vec): Look?
			if onCrack(p) then
				return GLOW
			end
			if patches(p, 4) < 0.32 then
				return WEATHER
			end
			return nil
		end

		-- A lion's body: deep chest, long back, powerful haunches, with folded wings along its sides, banded in
		-- rows of feathers.
		local WING = look(255, 192, 52)
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 28, 11 }, { 10, 10, 9 }), STONE)
		body:add(ellipsoid({ 0, 28, -3 }, { 9.4, 8.6, 16 }), STONE)
		body:add(ellipsoid({ 0, 28.4, -16 }, { 9.6, 9, 8.4 }), STONE)
		body:add(rod({ { 0, 33, 13, 7.4 }, { 0, 37, 17, 6.4 } }), STONE)
		for _, s in { 1, -1 } do
			body:add(
				ellipsoid({ 0, 0, 0 }, { 1.8, 5.6, 14 }),
				WING,
				{ origin = { 9.6 * s, 34.4, -3 }, roll = -0.32 * s, pitch = 0.1 }
			)
		end
		body:coat(function(p)
			local look0 = body.cells[Kit.cellKey(math.floor(p[1] / U), math.floor(p[2] / U), math.floor(p[3] / U))]
			if look0 == WING then
				-- Rows of feathers: gold coverts, lapis below them, turquoise at the trailing edge.
				local row = p[2] + (p[3] + 20) * 0.08
				if row < 31.4 then
					return look(52, 178, 172)
				elseif row < 34 then
					return if (p[3] + 40) % 3 < 1.5 then LAPIS else LAPIS_TOP
				end
				return if (p[3] + 40) % 3 < 1.5 then nil else GOLD_TOP
			end
			return stone(p)
		end)
		body:bake(tones)

		-- The head: a broad lion's face looking straight ahead, framed by a striped headdress whose lappets fall to
		-- its chest, with a braided beard.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 47.6, 19 }, { 7.6, 5.6, 6.8 }), GOLD)
		for _, s in { 1, -1 } do
			head:add(rod({ { 5.6 * s, 46, 19.6, 2.8 }, { 8.4 * s, 41, 20, 2.6 }, { 7.6 * s, 33, 21.6, 2.4 } }), GOLD)
		end
		head:add(rod({ { 0, 37.6, 24.2, 1.6 }, { 0, 32.4, 24.8, 1.3 } }), GOLD)
		head:carve(ellipsoid({ 0, 43, 26.6 }, { 5.8, 6.4, 5.4 }))
		head:add(ellipsoid({ 0, 43.4, 21.6 }, { 5.6, 5.6, 4.6 }), STONE)
		head:add(ellipsoid({ 0, 46.4, 24 }, { 4.6, 1.3, 1.6 }), STONE)
		head:add(ellipsoid({ 0, 40.8, 24.8 }, { 3.4, 2.4, 2.6 }), STONE)
		head:coat(function(p)
			local look0 = head.cells[Kit.cellKey(math.floor(p[1] / U), math.floor(p[2] / U), math.floor(p[3] / U))]
			if look0 == GOLD then
				-- The headdress and beard in stripes of gold and lapis.
				if (p[2] + 40) % 2.6 < 1.1 then
					return LAPIS
				end
				return nil
			end
			return stone(p)
		end)
		head:bake(tones)

		-- Thick legs on great paws.
		-- Each leg in two halves, bending at the elbow (or, behind, the hock).
		local front, frontShin = newSculpt(U), newSculpt(U)
		front:add(rod({ { 7.4, 28, 12, 5 }, { 7.6, 14, 13, 4.2 } }), STONE)
		frontShin:add(rod({ { 7.6, 14, 13, 4.1 }, { 7.6, 4, 14, 3.8 } }), STONE)
		frontShin:add(ellipsoid({ 7.6, 2.6, 16 }, { 4.4, 2.6, 5.4 }), STONE)
		local back, backShin = newSculpt(U), newSculpt(U)
		back:add(ellipsoid({ 7.6, 26, -16 }, { 4.8, 9, 7.4 }), STONE)
		back:add(rod({ { 7.8, 18, -19, 4 }, { 7.8, 11, -20.4, 3.8 } }), STONE)
		backShin:add(rod({ { 7.8, 11, -20.4, 3.7 }, { 7.8, 4, -16, 3.6 } }), STONE)
		backShin:add(ellipsoid({ 7.8, 2.6, -13.6 }, { 4.2, 2.6, 5.2 }), STONE)
		for _, s in { front, frontShin, back, backShin } do
			s:coat(function(p)
				return stone(p)
			end)
			s:bake(tones)
		end

		local spine = { { 0, 34, -23, 1.6 }, { 0, 30, -27, 1.4 }, { 0, 22, -28, 1.2 }, { 0, 16, -26, 1 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), STONE)
		tail:add(ellipsoid({ 0, 15, -25.4 }, { 1.8, 2.2, 1.8 }), GOLD)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 28, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, STONE)
		-- The long flight feathers of each wing, sweeping back past its haunches.
		for _, s in { 1, -1 } do
			for i = 0, 5 do
				local z = -10 - i * 1.6
				local y = 31.4 - i * 0.5
				local root = { (9.6 + i * 0.12) * s, y, z }
				T.taper(bodyLimb, root, vadd(root, { 0.6 * s, -2.4 - i * 0.3, -6 }), 2.2, 0.8, { s, 0.3, 0 }, TEAL)
			end
		end
		-- A glowing ankh on its chest.
		local chest = 20.6
		T.blade(bodyLimb, { 0, 25.6, chest }, { 0, 31, chest - 0.6 }, 1.2, 0.8, { 0, 0, 1 }, GLOW.color, NEON)
		T.blade(bodyLimb, { -2.4, 31, chest - 0.6 }, { 2.4, 31, chest - 0.6 }, 1.2, 0.8, { 0, 1, 0 }, GLOW.color, NEON)
		T.ball(bodyLimb, { 0, 33.4, chest - 1.4 }, { 3.2, 3.8, 1.2 }, GLOW.color, NEON)
		T.ball(bodyLimb, { 0, 33.4, chest - 1.1 }, { 1.4, 2, 1.2 }, STONE_UNDER.color)
		-- An inscription glowing along each flank.
		for _, s in { 1, -1 } do
			for i = 0, 9 do
				local z = 7 - i * 2.4
				local y = 21.4 + (i % 3) * 0.3
				local x = (sideOf(body, y, z) + 0.1) * s
				local tall = if i % 2 == 0 then 2.4 else 1.4
				T.blade(bodyLimb, { x, y, z }, { x, y + tall, z }, 0.6, 0.4, { s, 0, 0 }, GLOW.color, NEON)
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 36, 17 }))
		head:draw(headLimb, { body }, STONE)
		-- Big glowing eyes looking straight ahead, rimmed and lined in kohl, under a heavy brow.
		for _, s in { 1, -1 } do
			local face = Kit.frontOf(head, 2.3 * s, 44.6)
			T.ball(headLimb, { 2.3 * s, 44.6, face - 0.3 }, { 3, 1.9, 1 }, rgb(30, 26, 40))
			T.ball(headLimb, { 2.3 * s, 44.6, face - 0.1 }, { 2.4, 1.4, 1 }, GLOW.color, NEON)
			T.blade(
				headLimb,
				{ 3.4 * s, 44.4, face - 0.4 },
				{ 5.2 * s, 43.8, face - 1.6 },
				0.5,
				0.4,
				{ 0, 0.2, 1 },
				LAPIS.color
			)
		end
		local muzzle = Kit.frontOf(head, 0, 41.6)
		T.ball(headLimb, { 0, 42.2, muzzle - 0.2 }, { 2.6, 1.6, 1.4 }, NOSE)
		T.blade(headLimb, { -1.6, 39.4, muzzle - 0.6 }, { 1.6, 39.4, muzzle - 0.6 }, 0.4, 0.4, { 0, 1, 0 }, NOSE)
		T.blade(headLimb, { 0, 52.6, 22 }, { 0, 55.6, 22.6 }, 1.2, 1.2, { 0, 0, 1 }, GOLD.color)
		T.ball(headLimb, { 0, 56, 22.6 }, { 2.4, 2.8, 1 }, GOLD.color)
		T.ball(headLimb, { 0, 56, 23 }, { 1, 1.4, 0.4 }, GLOW.color, NEON)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 7.4, 28, 12 }), function(limb)
			front:draw(limb, { body, frontShin }, STONE)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 7.6, 14, 13 }), function(limb)
			frontShin:draw(limb, { front }, STONE)
			for _, dx in { -2.2, -0.8, 0.8, 2.2 } do
				T.taper(limb, { 7.6 + dx, 1.6, 20 }, { 7.6 + dx * 1.1, 0.4, 22 }, 1, 0.9, { 0, 1, 0 }, GOLD.color)
			end
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 7.6, 28, -16 }), function(limb)
			back:draw(limb, { body, backShin }, STONE)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 7.8, 11, -20.4 }), function(limb)
			backShin:draw(limb, { back }, STONE)
		end, "BackLeftLeg")
		tail:draw(pet:limb("Tail", T.at({ 0, 34, -22 })), { body }, STONE)

		pet:light(rgb(110, 255, 236), 2.6, 26)
		pet:particles("Sparkles", rgb(255, 214, 110), 12)
		pet:aura(rgb(70, 230, 220), rgb(255, 214, 110))
		pet:seat(0, 37 / U, -4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Golden Scarab (Mythic): a scarab of polished gold as big as a car, its wing cases inlaid with lapis and turquoise,
-- holding up a blazing sun disc between its horns, its rays turning slowly with it.

Desert.GoldenScarab = {
	name = "Golden Scarab",
	skeleton = "ManyLegged",
	scale = 0.46,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local GOLD = look(240, 182, 46)
		local GOLD_TOP = look(255, 230, 124)
		local GOLD_UNDER = look(168, 102, 24)
		local BRONZE = look(150, 92, 26)
		local SEAM = look(86, 52, 18)
		local LAPIS = look(38, 82, 190)
		local LAPIS_TOP = look(66, 116, 222)
		local TEAL = look(48, 176, 170)
		local SUN = rgb(255, 190, 50)
		local CORE = rgb(255, 246, 200)
		local EYES = rgb(110, 255, 236)

		local tones = {
			[GOLD] = { top = GOLD_TOP, under = GOLD_UNDER },
			[LAPIS] = { top = LAPIS_TOP },
		}

		-- Domed wing cases, split down the middle, with lines of lapis and turquoise inlaid along them.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 9.2, -3.6 }, { 7.4, 6, 9.4 }), GOLD)
		body:add(ellipsoid({ 0, 4.4, -2.6 }, { 6, 2.4, 8.4 }), BRONZE)
		body:carve(ellipsoid({ 0, -0.6, -3 }, { 10, 3, 12 }))
		body:coat(function(p, open)
			local x, y = math.abs(p[1]), p[2]
			if y < 5.4 and not open(0, 1, 0) then
				return BRONZE
			end
			if x < 0.7 and y > 8 then
				return SEAM
			end
			if y > 8.4 and p[3] > -11 then
				if math.abs(x - 2.8) < 0.5 then
					return LAPIS
				elseif math.abs(x - 5.2) < 0.45 then
					return TEAL
				end
			end
			return nil
		end)
		body:bake(tones)

		-- The head: a broad shield behind a flat, toothed face, rimmed in lapis.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 9.6, 6.6 }, { 6.6, 4.6, 4 }), GOLD)
		head:add(ellipsoid({ 0, 7.4, 10.4 }, { 4.8, 2.1, 2.8 }), GOLD)
		head:coat(function(p, open)
			if p[3] > 9.4 and p[3] < 10.4 and open(0, 1, 0) and p[2] > 9 then
				return LAPIS
			end
			if p[2] < 6 and not open(0, 1, 0) then
				return BRONZE
			end
			return nil
		end)
		head:bake(tones)

		local bodyLimb = pet:limb("Body", T.at({ 0, 8, 0 }))
		body:draw(bodyLimb, { head }, GOLD)

		local headLimb = pet:limb("Head", T.at({ 0, 8.6, 5 }))
		head:draw(headLimb, { body }, GOLD)
		-- A rake of teeth across the front of the face, and glowing eyes at its corners.
		for i = -3, 3 do
			local x = i * 1.3
			local z = if math.abs(i) == 3 then 11.2 else 12.4
			T.taper(headLimb, { x, 7.4, z }, { x * 1.15, 7.2, z + 1.6 }, 0.9, 0.6, { 0, 1, 0 }, BRONZE.color)
		end
		for _, s in { 1, -1 } do
			T.ball(headLimb, { 4.4 * s, 8.4, 9.4 }, { 1.2, 1.2, 1.2 }, EYES, NEON)
		end
		-- The sun disc, held up between two curving horns: a blazing core in a gold ring, with rays all round it.
		local sun = { 0, 23.6, 6.4 }
		for _, s in { 1, -1 } do
			T.branch(headLimb, {
				{ 2.6 * s, 9.6, 9.6 },
				{ 4.6 * s, 14.4, 9.4 },
				{ 5.6 * s, 19.4, 8 },
				{ 5.4 * s, 23.6, 6.6 },
			}, 1.4, { 0, 0, 1 }, GOLD.color)
		end
		T.ball(headLimb, sun, { 9.4, 9.4, 3 }, SUN, NEON)
		T.ball(headLimb, vadd(sun, { 0, 0, 0.6 }), { 5.6, 5.6, 2.4 }, CORE, NEON)
		for i = 0, 15 do
			local a = i / 16 * math.pi * 2
			local b = (i + 1) / 16 * math.pi * 2
			local p1 = vadd(sun, { math.cos(a) * 5.2, math.sin(a) * 5.2, 0 })
			local p2 = vadd(sun, { math.cos(b) * 5.2, math.sin(b) * 5.2, 0 })
			T.blade(headLimb, p1, p2, 1.1, 1.4, { 0, 0, 1 }, GOLD_TOP.color)
			if i % 2 == 0 then
				local out = vadd(sun, { math.cos(a) * 9.2, math.sin(a) * 9.2, 0 })
				T.taper(
					headLimb,
					vadd(sun, { math.cos(a) * 5.4, math.sin(a) * 5.4, 0 }),
					out,
					1.3,
					0.5,
					{ 0, 0, 1 },
					SUN,
					NEON
				)
			end
		end

		-- Three pairs of spiked legs, gold and bronze, with turquoise joints.
		local function legs(left: string, right: string, z: number, dz: number)
			pet:limbPair(left, right, T.at({ 5.2, 6, z }), function(limb)
				jointedLeg(limb, T, {
					{ 5, 6, z },
					{ 9.4, 8.6, z + dz },
					{ 11.6, 3, z + dz * 1.5 },
					{ 12.4, 0, z + dz * 1.8 },
				}, { 1.5, 1.2, 0.9 }, GOLD.color, TEAL.color)
				for t = 1, 3 do
					local p = vlerp({ 9.4, 8.6, z + dz }, { 11.6, 3, z + dz * 1.5 }, t / 4)
					T.taper(limb, p, vadd(p, { 0.9, 0.2, -0.6 }), 0.5, 0.5, { 0, 1, 0 }, BRONZE.color)
				end
			end)
		end
		legs("FrontLeftLeg", "FrontRightLeg", 4.6, 2)
		legs("MiddleLeftLeg", "MiddleRightLeg", -1.6, 0)
		legs("BackLeftLeg", "BackRightLeg", -7, -2)

		-- Its tail end: the tip of the abdomen showing under the wing cases.
		local tail = pet:limb("Tail", T.at({ 0, 6, -11.6 }))
		T.ball(tail, { 0, 5.6, -12.4 }, { 6.4, 4, 3 }, BRONZE.color)

		pet:light(SUN, 3, 28)
		pet:particles("Sparkles", rgb(255, 222, 120), 14)
		pet:aura(rgb(255, 176, 40), rgb(255, 244, 200))
		pet:seat(0, 15.2 / U, -4 / U)
	end,
}

return Desert
