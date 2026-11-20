--!strict
-- The Prehistoric zone's pets, in the showpiece style (see PetModels/Forest for what that means): scaled and feathered
-- hides in stripes and dapples, crisp angled claws, horns, plates, crests and teeth, and, the rarer they are, more
-- that glows: a frill with glowing eye spots, plates rimmed in light, a moss-grown giant lit by glowing spores, a
-- colossal tyrant studded with amber, a sea monster of the deep glowing violet, and the Lunar Dragon under its moon.
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
local vsub = Kit.vsub
local vscale = Kit.vscale
local vlerp = Kit.vlerp
local vnorm = Kit.vnorm
local glossyEye = Kit.glossyEye

local NEON = Kit.NEON

local Prehistoric: { [string]: Design } = {}

-- A feather from `root` along `dir`, dark at the root, `color` along most of it, and `tip` (glowing, with
-- `tipMaterial`) at the end. `T` is the design's `inUnits`.
local function plume(
	limb: Limb,
	T: any,
	root: Vec,
	dir: Vec,
	length: number,
	width: number,
	facing: Vec,
	dark: { number },
	color: { number },
	tip: { number },
	tipMaterial: string?
)
	Kit.feather(limb, T.at(root), dir, length / T.unit, width / T.unit, width * 0.3 / T.unit, facing, {
		{ color = dark, to = 0.35 },
		{ color = color, to = 0.78 },
		{ color = tip, material = tipMaterial, to = 1 },
	})
end

-- A horn or spike from `a` to `b`, `width` across at its root: `color` for most of it and `tip` (glowing) for the
-- last part. `T` is the design's `inUnits`.
local function spike(limb: Limb, T: any, a: Vec, b: Vec, width: number, facing: Vec, color: { number }, tip: { number })
	local m = vlerp(a, b, 0.62)
	T.blade(limb, a, m, width, width, facing, color)
	T.taper(limb, m, b, width * 0.8, width * 0.8, facing, tip, NEON)
end

----------------------------------------------------------------------------------------------------------------
-- Velociraptor (Epic): a quick, clever hunter, twice a player's height from snout to tail: tawny scales striped
-- dark down its back, a cream belly, a crest of red feathers glowing amber at the tips, feathered arms and a fan of
-- feathers at the end of its tail, a toothy grin, glowing amber eyes, and the famous sickle claw on each foot.

Prehistoric.Velociraptor = {
	name = "Velociraptor",
	skeleton = "Theropod",
	gait = "Walk",
	scale = 0.36,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local HIDE = look(196, 136, 76)
		local HIDE_UNDER = look(140, 92, 52)
		local BACK = look(150, 88, 46)
		local BACK_TOP = look(178, 112, 62)
		local STRIPE = look(70, 40, 30)
		local BELLY = look(236, 218, 178)
		local BELLY_SHADE = look(200, 176, 134)
		local MOUTH = look(96, 32, 30)
		local FEATHER = rgb(196, 64, 34)
		local FEATHER_DARK = rgb(108, 30, 22)
		local FEATHER_LIGHT = rgb(236, 122, 52)
		local AMBER = rgb(255, 172, 40)
		local CLAW = rgb(46, 34, 32)
		local TOOTH = rgb(246, 238, 220)

		local tones = {
			[HIDE] = { under = HIDE_UNDER },
			[BACK] = { top = BACK_TOP },
			[BELLY] = { under = BELLY_SHADE },
		}
		-- Pale underneath, tawny flanks, and a darker back striped across like a tiger's.
		local function hide(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.4 then
				return BELLY
			end
			-- Stripes run from the spine down the flanks, narrowing as they go.
			local width = 1.7 * math.clamp((n[2] + 0.35) / 0.8, 0, 1)
			if (p[3] + 0.9 * math.sin(p[2] * 0.8)) % 4.6 < width then
				return STRIPE
			end
			if n[2] > 0.3 then
				return BACK
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(rod({ { 0, 14, 6, 3.6 }, { 0, 15, -1, 4.4 }, { 0, 15.4, -6, 4 } }), HIDE)
		-- The neck rising in an S to the head.
		body:add(rod({ { 0, 15, 6, 3 }, { 0, 18.6, 9.4, 2.4 }, { 0, 21.6, 11, 2.1 } }), HIDE)
		body:coat(hide)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 22.8, 13.2 }, { 2.5, 2.5, 3.2 }), HIDE)
		head:add(ellipsoid({ 0, 24.4, 13.4 }, { 1.9, 1, 1.8 }), HIDE)
		head:add(rod({ { 0, 22.6, 14.6, 2.1 }, { 0, 21.9, 19.6, 1.3 } }), HIDE)
		head:add(rod({ { 0, 20.9, 14, 1.7 }, { 0, 20.7, 18.8, 1 } }), HIDE)
		head:coat(function(p, open, n)
			if p[3] > 15.2 and p[2] > 21 and p[2] < 22 and math.abs(p[1]) > 0.4 then
				return MOUTH
			end
			return hide(p, open, n)
		end)
		head:bake(tones)

		local arm = newSculpt(U)
		arm:add(rod({ { 3, 13.4, 5.4, 1.4 }, { 3.6, 11, 7, 1 }, { 3.4, 10.6, 9.6, 0.8 } }), HIDE)
		arm:coat(hide)
		arm:bake(tones)

		local leg = newSculpt(U)
		leg:add(ellipsoid({ 3.6, 14, -2.6 }, { 2.2, 3.6, 3.4 }), HIDE)
		leg:add(rod({ { 3.8, 13.4, -2, 2.4 }, { 4, 8.6, 0.6, 1.7 } }), HIDE)
		leg:add(rod({ { 4, 8.6, 0.6, 1.5 }, { 4, 4.2, -2.6, 1 } }), HIDE)
		leg:add(rod({ { 4, 4.2, -2.6, 0.9 }, { 4, 1.2, -1.4, 0.8 } }), HIDE)
		leg:add(ellipsoid({ 4, 0.7, 0.2 }, { 1.2, 0.7, 1.8 }), HIDE)
		leg:coat(hide)
		leg:bake(tones)

		local spine = { { 0, 15.4, -8, 3.6 }, { 0, 16.2, -14, 2.6 }, { 0, 16.8, -21, 1.6 }, { 0, 16.8, -27, 0.8 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), HIDE)
		tail:coat(hide)
		tail:bake(tones)

		local legMirror, armMirror = leg:mirror(), arm:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 15, 0 }))
		body:draw(bodyLimb, { head, tail, leg, legMirror, arm, armMirror }, HIDE)
		-- A ruff of feathers down the back of the neck, and over the hips.
		for i, z in { 10, 8.6, 7.2, 5.8 } do
			local y = topOf(body, z) - 0.6
			plume(
				bodyLimb,
				T,
				{ 0, y, z },
				{ 0, 0.5, -1 },
				4 - i * 0.3,
				1.2,
				{ 1, 0, 0 },
				FEATHER_DARK,
				FEATHER,
				FEATHER_LIGHT
			)
		end
		for i, z in { -5.4, -7 } do
			local y = topOf(body, z) - 0.6
			plume(
				bodyLimb,
				T,
				{ 0, y, z },
				{ 0, 0.4, -1 },
				3.6 - i * 0.4,
				1.1,
				{ 1, 0, 0 },
				FEATHER_DARK,
				FEATHER,
				FEATHER_LIGHT
			)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 21, 11 }))
		head:draw(headLimb, { body }, HIDE)
		glossyEye(headLimb, T, head, 23.4, 14.6, 1.3, rgb(40, 24, 18), AMBER, NEON, rgb(30, 16, 10))
		-- A crest of feathers swept back from the brow, glowing amber at the tips.
		for i, root in { { 0, 25, 14.4 }, { 0, 25.2, 13 }, { 0, 24.8, 11.6 }, { 0, 23.8, 10.4 } } do
			for _, dx in { -0.5, 0.5 } do
				plume(
					headLimb,
					T,
					{ dx, root[2], root[3] },
					{ dx * 0.5, 1 - i * 0.18, -1 },
					5.6 - i * 0.7,
					1.2,
					{ 1, 0, 0 },
					FEATHER_DARK,
					FEATHER,
					AMBER,
					NEON
				)
			end
		end
		-- A grin of sharp teeth.
		for _, s in { 1, -1 } do
			for _, z in { 15.8, 16.9, 18 } do
				local x = sideOf(head, 21.5, z) - 0.2
				if x > 0.3 then
					T.taper(headLimb, { x * s, 21.8, z }, { x * s, 20.7, z + 0.2 }, 0.5, 0.35, { s, 0, 0 }, TOOTH)
				end
			end
		end

		-- Feathered arms ending in three long claws.
		pet:limbPair("LeftArm", "RightArm", T.at({ 3, 13.4, 5.4 }), function(limb)
			arm:draw(limb, { body }, HIDE)
			for i, t in { 0.25, 0.5, 0.75, 1 } do
				local root = vlerp({ 3.6, 11, 7 }, { 3.4, 10.6, 9.6 }, t)
				plume(
					limb,
					T,
					root,
					{ 0.3, -0.5, -1 },
					3 + i * 0.3,
					1,
					{ 1, 0, 0 },
					FEATHER_DARK,
					FEATHER,
					FEATHER_LIGHT
				)
			end
			for _, dx in { -0.5, 0, 0.5 } do
				T.taper(limb, { 3.4 + dx, 10.4, 9.8 }, { 3.4 + dx * 1.3, 8.8, 10.8 }, 0.5, 0.4, { 0, 0, 1 }, CLAW)
			end
		end)

		-- Strong legs on clawed feet, each with its sickle claw raised.
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 3.8, 14, -2 }), function(limb)
			leg:draw(limb, { body }, HIDE)
			for _, dx in { -0.6, 0.6 } do
				T.taper(limb, { 4 + dx, 0.8, 1.6 }, { 4 + dx * 1.2, 0.1, 3 }, 0.6, 0.5, { 0, 1, 0 }, CLAW)
			end
			T.blade(limb, { 3.3, 1.2, 0.2 }, { 3.2, 2.8, 1.4 }, 0.6, 0.6, { 1, 0, 0 }, CLAW)
			T.taper(limb, { 3.2, 2.8, 1.4 }, { 3.2, 2, 2.8 }, 0.6, 0.6, { 1, 0, 0 }, AMBER, NEON)
		end)

		-- The tail, ending in a fan of feathers.
		local tailLimb = pet:limb("Tail", T.at({ 0, 15.4, -8 }))
		tail:draw(tailLimb, { body }, HIDE)
		for _, dx in { -1, -0.5, 0, 0.5, 1 } do
			plume(
				tailLimb,
				T,
				{ dx * 0.6, 16.8, -24.6 },
				{ dx * 0.7, 0.04, -1 },
				5.4 - math.abs(dx) * 1.2,
				1.3,
				{ 0, 1, 0 },
				FEATHER_DARK,
				FEATHER,
				AMBER,
				NEON
			)
		end

		pet:seat(0, (topOf(body, -1) + 0.4) / U, -1 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Pteranodon (Epic): a great flying reptile with wings spanning five players: slate-grey above and pale below,
-- fuzzy round the neck, a long beak, a swept-back crest of red with a glowing stripe, glowing amber eyes, and wide
-- leathery wings, light in the middle and dark at the tips, ribbed with fine lines, with light along their bones.

Prehistoric.Pteranodon = {
	name = "Pteranodon",
	skeleton = "Winged",
	gait = "Walk",
	scale = 0.38,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local BACK = look(74, 86, 108)
		local BACK_TOP = look(108, 122, 146)
		local BACK_UNDER = look(48, 56, 72)
		local BELLY = look(232, 228, 216)
		local BELLY_SHADE = look(186, 182, 172)
		local FACE = look(222, 216, 202)
		local FUZZ = rgb(130, 142, 164)
		local BEAK = rgb(232, 196, 120)
		local BEAK_DARK = rgb(176, 136, 76)
		local CREST = rgb(212, 78, 42)
		local CREST_DARK = rgb(132, 40, 28)
		local BONE = rgb(204, 196, 180)
		local MEMBRANE = rgb(156, 102, 72)
		local MEMBRANE_LIGHT = rgb(196, 140, 94)
		local MEMBRANE_DARK = rgb(92, 56, 48)
		local RIB = rgb(110, 66, 50)
		local GLOW = rgb(255, 176, 50)
		local CLAW = rgb(50, 44, 44)

		local tones = {
			[BACK] = { top = BACK_TOP, under = BACK_UNDER },
			[BELLY] = { under = BELLY_SHADE },
			[FACE] = { under = BELLY_SHADE },
		}
		-- Pale underneath and down the chest and throat.
		local function coat(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.35 or (n[3] > 0.45 and n[2] < 0.5 and p[2] < 15) then
				return BELLY
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 11.4, -1 }, { 3.6, 3.6, 6 }), BACK)
		body:add(ellipsoid({ 0, 12.4, 2.8 }, { 3.8, 3.8, 3.4 }), BACK)
		body:add(rod({ { 0, 13.4, 5, 2.3 }, { 0, 16.4, 8, 1.7 } }), BACK)
		body:coat(coat)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 17.6, 9.4 }, { 1.9, 2.1, 2.5 }), FACE)
		head:add(rod({ { 0, 17.2, 10.8, 1.6 }, { 0, 16.6, 12.8, 1.2 } }), FACE)
		head:bake(tones)

		local leg = newSculpt(U)
		leg:add(rod({ { 2.2, 9.4, -3, 1.3 }, { 2.6, 4.8, -2, 0.9 }, { 2.6, 1.2, -1.2, 0.7 } }), BACK)
		leg:add(ellipsoid({ 2.6, 0.5, -0.4 }, { 1, 0.5, 1.4 }), BACK)
		leg:bake(tones)

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 11, -6.4, 1.1 }, { 0, 10.8, -9.6, 0.5 } }), BACK)

		local legMirror = leg:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 11.4, 0 }))
		body:draw(bodyLimb, { head, tail, leg, legMirror }, BACK)
		-- A fuzzy ruff round the neck and shoulders.
		Kit.fur(
			bodyLimb,
			T,
			body,
			function(p: Vec, n: Vec): boolean
				return p[3] > 2 and n[2] > -0.2 and p[2] > 13.4 and noise(p) < 0.4
			end,
			1.4,
			0.8,
			{ 0, 0.3, -0.8 },
			function(): { number }
				return FUZZ
			end
		)

		local headLimb = pet:limb("Head", T.at({ 0, 16.4, 8 }))
		head:draw(headLimb, { body }, BACK)
		glossyEye(headLimb, T, head, 18.2, 10, 1.05, rgb(40, 30, 30), GLOW, NEON, rgb(30, 18, 10))
		-- The long beak, upper and lower.
		T.blade(headLimb, { 0, 17.3, 11.6 }, { 0, 16.7, 16.4 }, 1.9, 1.5, { 0, 1, 0 }, BEAK)
		T.taper(headLimb, { 0, 16.7, 16.4 }, { 0, 16, 23.4 }, 1.5, 1.2, { 0, 1, 0 }, BEAK)
		T.blade(headLimb, { 0, 16.1, 11.6 }, { 0, 15.8, 16.4 }, 1.6, 1, { 0, 1, 0 }, BEAK_DARK)
		T.taper(headLimb, { 0, 15.8, 16.4 }, { 0, 15.8, 22.2 }, 1.3, 0.9, { 0, 1, 0 }, BEAK_DARK)
		-- The crest, swept far back from the skull, a glowing stripe along it.
		local crestTip = { 0, 26.4, -3.4 }
		T.triangle(headLimb, { 0, 19.6, 10.8 }, { 0, 17.8, 7.6 }, crestTip, 1.1, CREST)
		T.triangle(headLimb, { 0, 19.6, 10.8 }, { 0, 22.4, 6.4 }, crestTip, 1.1, CREST_DARK)
		T.blade(headLimb, { 0, 19.6, 9.4 }, { 0, 25.2, -1.6 }, 0.6, 1.3, { 1, 0, 0 }, GLOW, NEON)

		pet:limbPair("LeftLeg", "RightLeg", T.at({ 2.2, 9.4, -3 }), function(limb)
			leg:draw(limb, { body }, BACK)
			for _, dx in { -0.5, 0, 0.5 } do
				T.taper(limb, { 2.6 + dx, 0.5, 0.7 }, { 2.6 + dx * 1.4, 0.1, 1.8 }, 0.45, 0.4, { 0, 1, 0 }, CLAW)
			end
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 11, -6.4 })), { body }, BACK)

		-- Wide leathery wings on a long arm and one great finger: the membrane light in the middle and dark at the
		-- tip, ribbed with fine lines, a line of light along the bones.
		pet:limbPair("LeftWing", "RightWing", T.at({ 3.2, 13.4, 2.6 }), function(wing)
			local front =
				{ { 3.2, 13.4, 2.6 }, { 8.4, 15, 4.2 }, { 15.4, 17.4, 4.8 }, { 24.4, 20.4, 2.2 }, { 35.6, 23.6, -3 } }
			local back = { { 3.2, 10.6, -4.6 }, { 9.4, 12.6, -7.4 }, { 17.4, 15.4, -8.4 }, { 26.4, 18.8, -6.8 } }
			for k = 1, #front - 1 do
				T.blade(wing, front[k], front[k + 1], 1.6 - k * 0.2, 1.3 - k * 0.15, { 0, 1, 0 }, BONE)
				T.blade(wing, front[k], front[k + 1], 0.45, 1.4 - k * 0.15, { 0, 1, 0 }, GLOW, NEON)
			end
			for k = 2, 4 do
				T.ball(wing, front[k], { 1.8 - k * 0.15, 1.8 - k * 0.15, 1.8 - k * 0.15 }, BONE)
			end
			-- Three small clawed fingers at the wrist, and the bony spur in front of it.
			for _, dz in { 0.4, 1.2, 2 } do
				T.taper(wing, front[3], vadd(front[3], { 0.8, -0.6, dz + 0.4 }), 0.5, 0.4, { 0, 1, 0 }, CLAW)
			end
			T.taper(wing, front[2], vadd(front[2], { 2.4, 0.2, 2 }), 0.6, 0.5, { 0, 1, 0 }, BONE)
			local shades = { MEMBRANE, MEMBRANE_LIGHT, MEMBRANE, MEMBRANE_DARK, MEMBRANE_DARK }
			for k = 1, #back do
				local a, b = front[k], front[k + 1]
				local c = back[k]
				T.triangle(wing, a, b, c, 0.5, shades[k])
				if back[k + 1] then
					T.triangle(wing, b, back[k + 1], c, 0.5, shades[k + 1])
				else
					T.triangle(wing, b, front[k + 1], c, 0.5, shades[k + 1])
				end
			end
			-- Fine ribs running back across the membrane, and a dark trailing edge.
			for k = 1, #back - 1 do
				for _, t in { 0.33, 0.66 } do
					local from = vlerp(front[k + 1], front[k + 2], t)
					local to = vlerp(back[k], back[k + 1], t)
					T.blade(wing, vlerp(from, to, 0.08), vlerp(from, to, 0.95), 0.25, 0.6, { 0, 1, 0 }, RIB)
				end
			end
			for k = 1, #back - 1 do
				T.blade(wing, back[k], back[k + 1], 0.6, 0.7, { 0, 1, 0 }, MEMBRANE_DARK)
			end
			T.blade(wing, back[#back], front[#front], 0.6, 0.7, { 0, 1, 0 }, MEMBRANE_DARK)
		end)

		pet:seat(0, (topOf(body, -1) + 0.4) / U, -1 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Triceratops (Legendary): three times a player's height to the top of its frill: an olive hide banded dark across
-- the back and studded with knobbly scutes, a hooked beak, three great ivory horns glowing at their points, and a
-- huge frill of red and orange rimmed with spikes, with glowing eye spots to frighten off a tyrant.

Prehistoric.Triceratops = {
	name = "Triceratops",
	skeleton = "Strider",
	gait = "Stomp",
	scale = 0.42 * 1.2,
	draw = function(pet)
		-- Built in cells 1.2 design units across.
		local U = 1.2
		local T = inUnits(U)
		local HIDE = look(128, 116, 72)
		local HIDE_TOP = look(162, 150, 98)
		local HIDE_UNDER = look(82, 72, 46)
		local BAND = look(84, 74, 46)
		local SCUTE = look(178, 166, 118)
		local BELLY = look(202, 188, 142)
		local BELLY_SHADE = look(156, 144, 104)
		local FRILL = look(210, 96, 44)
		local FRILL_DARK = look(140, 50, 32)
		local FRILL_RIM = look(76, 44, 32)
		local SPOT = look(255, 176, 50, NEON)
		local SPOT_RING = look(40, 24, 20)
		local MOUTH = look(70, 40, 34)
		local HORN = rgb(238, 226, 194)
		local HORN_DARK = rgb(136, 116, 86)
		local BEAK = rgb(52, 46, 44)
		local GLOW = rgb(255, 176, 50)
		local NAIL = rgb(60, 52, 46)

		local tones = {
			[HIDE] = { top = HIDE_TOP, under = HIDE_UNDER },
			[BAND] = { under = HIDE_UNDER },
			[BELLY] = { under = BELLY_SHADE },
		}
		-- A paler belly, dark bands across the back, and rows of knobbly pale scutes along it.
		local function hide(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.4 then
				return BELLY
			end
			if n[2] > 0.45 and math.abs(p[1]) % 3.6 < 1.3 and (p[3] + p[1] * 0.5) % 3.6 < 1.3 then
				return SCUTE
			end
			if n[2] > -0.1 and (p[3] + 1.6 * math.sin(p[2] * 0.4)) % 7 < 2.2 then
				return BAND
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 18, -2 }, { 10, 9.6, 13 }), HIDE)
		body:add(ellipsoid({ 0, 19.6, -9 }, { 9.4, 8.6, 8 }), HIDE)
		body:add(ellipsoid({ 0, 16.6, 7 }, { 9, 8.6, 7.4 }), HIDE)
		body:add(rod({ { 0, 16, 11, 6.6 }, { 0, 15.6, 15, 5.6 } }), HIDE)
		body:coat(hide)
		body:bake(tones)

		-- The great frill: a broad shield tipped back over the neck.
		local frill = { origin = { 0, 24.4, 13.4 }, pitch = 0.72 }
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 0, 0 }, { 15, 12.4, 1.8 }), FRILL, frill)
		head:add(ellipsoid({ 0, 16.4, 21 }, { 5.8, 5.8, 6 }), HIDE)
		head:add(rod({ { 0, 15.4, 25, 4.4 }, { 0, 13, 31, 2.6 } }), HIDE)
		head:add(rod({ { 0, 12, 23, 3 }, { 0, 10.8, 30, 1.8 } }), HIDE)
		head:coat(function(p, open, n)
			local x, y, z = Kit.toLocal(frill, p[1], p[2], p[3])
			local r = math.sqrt((x / 15) ^ 2 + (y / 12.4) ^ 2)
			if y > -7 and r <= 1.05 and math.abs(z) < 2.4 then
				for _, s in { 1, -1 } do
					local d = math.sqrt((x - 7 * s) ^ 2 + (y - 3.4) ^ 2)
					if d < 1.8 then
						return SPOT
					elseif d < 2.9 then
						return SPOT_RING
					end
				end
				if r > 0.86 then
					return FRILL_RIM
				elseif r > 0.62 and r < 0.72 then
					return FRILL_DARK
				end
				return nil
			end
			if math.abs(p[1]) > 1 and p[3] > 26 and p[2] > 11.6 and p[2] < 12.8 then
				return MOUTH
			end
			return hide(p, open, n)
		end)
		head:bake(tones)

		-- Stout legs in two halves, bending at the knee.
		local front, frontShin, back, backShin = newSculpt(U), newSculpt(U), newSculpt(U), newSculpt(U)
		front:add(ellipsoid({ 7, 14, 7 }, { 3.6, 5, 4.4 }), HIDE)
		front:add(rod({ { 7.4, 12, 7.6, 3.4 }, { 7.5, 7.6, 8, 3.15 } }), HIDE)
		frontShin:add(rod({ { 7.5, 7.6, 8, 3.1 }, { 7.6, 3.6, 8.4, 2.9 } }), HIDE)
		frontShin:add(ellipsoid({ 7.6, 1.8, 9 }, { 3.2, 1.8, 3.6 }), HIDE)
		back:add(ellipsoid({ 7.4, 16, -11 }, { 4, 6.6, 6 }), HIDE)
		back:add(rod({ { 7.6, 12, -11, 4 }, { 7.7, 7.6, -10.5, 3.6 } }), HIDE)
		backShin:add(rod({ { 7.7, 7.6, -10.5, 3.55 }, { 7.8, 3.6, -10, 3.2 } }), HIDE)
		backShin:add(ellipsoid({ 7.8, 1.8, -9.4 }, { 3.4, 1.8, 3.8 }), HIDE)
		for _, s in { front, frontShin, back, backShin } do
			s:coat(hide)
			s:bake(tones)
		end

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 19, -16, 6 }, { 0, 17.4, -26, 4 }, { 0, 14.6, -35, 2.2 }, { 0, 12, -42, 1 } }), HIDE)
		tail:coat(hide)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 18, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, HIDE)

		local headLimb = pet:limb("Head", T.at({ 0, 15.6, 16 }))
		head:draw(headLimb, { body }, HIDE)
		glossyEye(headLimb, T, head, 18.4, 24.6, 1.6, rgb(40, 30, 24), GLOW, NEON, rgb(30, 18, 10))
		-- A hooked beak.
		T.taper(headLimb, { 0, 14.4, 30.4 }, { 0, 10.6, 34.4 }, 2.8, 2.4, { 1, 0, 0 }, BEAK)
		T.taper(headLimb, { 0, 11.2, 29.6 }, { 0, 10.6, 32.6 }, 2.2, 1.8, { 1, 0, 0 }, BEAK)
		-- Three horns: two long ones over the eyes and a short one on the nose, ivory glowing at the points.
		for _, s in { 1, -1 } do
			local root, bend, tip = { 3.6 * s, 21, 22 }, { 4.6 * s, 25, 28 }, { 4.8 * s, 27.6, 36 }
			T.blade(headLimb, root, bend, 2.8, 2.8, { 0, 0, 1 }, HORN_DARK)
			spike(headLimb, T, bend, tip, 2.4, { 0, 0, 1 }, HORN, GLOW)
		end
		spike(headLimb, T, { 0, 16, 29 }, { 0, 19.4, 32.4 }, 2.2, { 1, 0, 0 }, HORN, GLOW)
		-- Bony spikes round the rim of the frill.
		for k = -5, 5 do
			local a = k * 0.3
			local x, y = math.sin(a) * 14.4, math.cos(a) * 11.8
			local ox, oy = math.sin(a) * 18.4, math.cos(a) * 15.4
			local wx, wy, wz = Kit.toWorld(frill, x, y, 0)
			local tx, ty, tz = Kit.toWorld(frill, ox, oy, 0)
			spike(headLimb, T, { wx, wy, wz }, { tx, ty, tz }, 1.8, { 0, 0.66, 0.75 }, HORN, GLOW)
		end

		local function nails(limb: Limb, x: number, z: number)
			for _, dx in { -1.8, -0.6, 0.6, 1.8 } do
				T.taper(limb, { x + dx, 1, z }, { x + dx * 1.1, 0.2, z + 1.4 }, 1, 0.8, { 0, 1, 0 }, NAIL)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 7, 14, 7 }), function(limb)
			front:draw(limb, { body, frontShin }, HIDE)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 7.5, 7.6, 8 }), function(limb)
			frontShin:draw(limb, { front }, HIDE)
			nails(limb, 7.6, 11.6)
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 7.4, 17, -11 }), function(limb)
			back:draw(limb, { body, backShin }, HIDE)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 7.7, 7.6, -10.5 }), function(limb)
			backShin:draw(limb, { back }, HIDE)
			nails(limb, 7.8, -6.8)
		end, "BackLeftLeg")
		tail:draw(pet:limb("Tail", T.at({ 0, 19, -16 })), { body }, HIDE)

		pet:light(GLOW, 2, 22)
		pet:particles("Fireflies", rgb(255, 200, 80), 8)
		pet:aura(rgb(255, 160, 50), rgb(255, 230, 140))
		pet:seat(0, (topOf(body, -4) + 0.4) / U, -4 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Stegosaurus (Legendary): three times a player's height to the top of its plates: a sea-green hide banded dark,
-- a small low head, two staggered rows of great plates along its arched back, slate at the root and rimmed in
-- glowing teal, and the spiked tail (the thagomizer) with glowing points. A gap in the plates over the shoulders
-- makes a saddle.

Prehistoric.Stegosaurus = {
	name = "Stegosaurus",
	skeleton = "Strider",
	gait = "Stomp",
	scale = 0.42 * 1.2,
	draw = function(pet)
		-- Built in cells 1.2 design units across.
		local U = 1.2
		local T = inUnits(U)
		local HIDE = look(72, 112, 96)
		local HIDE_TOP = look(104, 148, 126)
		local HIDE_UNDER = look(42, 66, 58)
		local BAND = look(46, 76, 68)
		local BELLY = look(190, 186, 146)
		local BELLY_SHADE = look(146, 140, 106)
		local MOUTH = look(60, 40, 36)
		local PLATE = rgb(54, 76, 88)
		local PLATE_MID = rgb(40, 120, 132)
		local GLOW = rgb(90, 255, 220)
		local BONE = rgb(222, 214, 190)
		local BEAK = rgb(50, 52, 48)
		local NAIL = rgb(56, 54, 48)

		local tones = {
			[HIDE] = { top = HIDE_TOP, under = HIDE_UNDER },
			[BAND] = { under = HIDE_UNDER },
			[BELLY] = { under = BELLY_SHADE },
		}
		-- A pale belly and dark bands across the back.
		local function hide(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.4 then
				return BELLY
			end
			if n[2] > -0.15 and (p[3] * 0.8 + 2 * math.sin(p[2] * 0.35 + p[1] * 0.2)) % 6 < 1.8 then
				return BAND
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 19, -4 }, { 9, 9.6, 15 }), HIDE)
		body:add(ellipsoid({ 0, 22, -9 }, { 8.4, 8, 9 }), HIDE)
		body:add(ellipsoid({ 0, 15.4, 7 }, { 7.6, 7.4, 7 }), HIDE)
		body:add(rod({ { 0, 14.6, 11, 5 }, { 0, 11.6, 17, 3.2 } }), HIDE)
		body:coat(hide)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 11.2, 20.4 }, { 2.8, 2.8, 3.8 }), HIDE)
		head:add(rod({ { 0, 10.6, 22, 2.2 }, { 0, 9.4, 26, 1.3 } }), HIDE)
		head:coat(function(p, open, n)
			if math.abs(p[1]) > 0.6 and p[3] > 22.6 and p[2] > 9.2 and p[2] < 10.2 then
				return MOUTH
			end
			return hide(p, open, n)
		end)
		head:bake(tones)

		-- Legs in two halves, bending at the knee: short in front, long behind.
		local front, frontShin, back, backShin = newSculpt(U), newSculpt(U), newSculpt(U), newSculpt(U)
		front:add(ellipsoid({ 6, 13, 7 }, { 3.2, 4.4, 3.8 }), HIDE)
		front:add(rod({ { 6.4, 11, 7.6, 3 }, { 6.5, 7, 8, 2.8 } }), HIDE)
		frontShin:add(rod({ { 6.5, 7, 8, 2.75 }, { 6.6, 3.4, 8.4, 2.6 } }), HIDE)
		frontShin:add(ellipsoid({ 6.6, 1.6, 9 }, { 2.8, 1.6, 3.2 }), HIDE)
		back:add(ellipsoid({ 6.8, 19, -10 }, { 4, 7.6, 6.4 }), HIDE)
		back:add(rod({ { 7, 14, -10, 4 }, { 7.1, 8.6, -9.5, 3.6 } }), HIDE)
		backShin:add(rod({ { 7.1, 8.6, -9.5, 3.55 }, { 7.2, 3.6, -9, 3.2 } }), HIDE)
		backShin:add(ellipsoid({ 7.2, 1.8, -8.4 }, { 3.4, 1.8, 3.8 }), HIDE)
		for _, s in { front, frontShin, back, backShin } do
			s:coat(hide)
			s:bake(tones)
		end

		local spine = { { 0, 21, -18, 5.6 }, { 0, 19.6, -28, 3.6 }, { 0, 17, -38, 1.8 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), HIDE)
		tail:coat(hide)
		tail:bake(tones)

		-- A plate standing on the back at (x, z), `tall` high and `long` along the back, leaning out a little: slate
		-- at the root, teal in the middle, rimmed in light.
		local function plate(limb: Limb, s: Sculpt, x: number, z: number, tall: number, long: number)
			local y = topOf(s, z, x) - 1.2
			local lean = if x > 0 then 0.12 else -0.12
			local function at(u: number, v: number): Vec
				return { x + lean * v * tall, y + v * tall, z + u * long }
			end
			local b1, b2 = at(0.5, 0), at(-0.5, 0)
			local m1, m2 = at(0.5, 0.5), at(-0.42, 0.56)
			local top = at(-0.06, 1)
			T.triangle(limb, b1, m1, b2, 1.2, PLATE)
			T.triangle(limb, m1, m2, b2, 1.2, PLATE)
			T.triangle(limb, m1, top, m2, 1.2, PLATE_MID)
			T.blade(limb, m1, top, 0.6, 1.5, { 1, 0, 0 }, GLOW, NEON)
			T.blade(limb, m2, top, 0.6, 1.5, { 1, 0, 0 }, GLOW, NEON)
			T.blade(limb, vlerp(b1, m1, 0.3), m1, 0.5, 1.5, { 1, 0, 0 }, GLOW, NEON)
			T.blade(limb, vlerp(b2, m2, 0.3), m2, 0.5, 1.5, { 1, 0, 0 }, GLOW, NEON)
			-- A glowing vein up the middle.
			T.blade(limb, vlerp(b1, b2, 0.5), vlerp(vlerp(m1, m2, 0.5), top, 0.5), 0.3, 1.4, { 1, 0, 0 }, GLOW, NEON)
		end

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 19, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, HIDE)
		-- Two staggered rows of plates, biggest over the hips; none over the shoulders, where the rider sits.
		for i, z in { 12, 9, -3, -6.4, -10, -13.6 } do
			local tall = ({ 6, 7.6, 12.6, 15, 15.6, 14 })[i]
			local long = ({ 5, 6, 9.4, 10.6, 11, 10 })[i]
			local s = if i % 2 == 0 then 1 else -1
			plate(bodyLimb, body, 1.2 * s, z, tall, long)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 11.6, 17 }))
		head:draw(headLimb, { body }, HIDE)
		glossyEye(headLimb, T, head, 12, 21.4, 1.1, rgb(30, 40, 40), GLOW, NEON, rgb(10, 30, 30))
		T.taper(headLimb, { 0, 9.8, 25.6 }, { 0, 8.6, 27.6 }, 2, 1.6, { 1, 0, 0 }, BEAK)

		local function nails(limb: Limb, x: number, z: number)
			for _, dx in { -1.4, 0, 1.4 } do
				T.taper(limb, { x + dx, 1, z }, { x + dx * 1.1, 0.2, z + 1.4 }, 1, 0.8, { 0, 1, 0 }, NAIL)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 6, 14, 7 }), function(limb)
			front:draw(limb, { body, frontShin }, HIDE)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 6.5, 7, 8 }), function(limb)
			frontShin:draw(limb, { front }, HIDE)
			nails(limb, 6.6, 11.4)
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 6.8, 19, -10 }), function(limb)
			back:draw(limb, { body, backShin }, HIDE)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 7.1, 8.6, -9.5 }), function(limb)
			backShin:draw(limb, { back }, HIDE)
			nails(limb, 7.2, -5.4)
		end, "BackLeftLeg")

		local tailLimb = pet:limb("Tail", T.at({ 0, 21, -18 }))
		tail:draw(tailLimb, { body }, HIDE)
		for i, z in { -18.4, -22.4, -26 } do
			local s = if i % 2 == 0 then 1 else -1
			plate(tailLimb, tail, 1 * s, z, 12 - i * 2.4, 8.6 - i * 1.4)
		end
		-- The thagomizer: two pairs of long spikes near the tip.
		for _, s in { 1, -1 } do
			spike(tailLimb, T, { 1 * s, 18.8, -32 }, { 7 * s, 23, -37 }, 1.4, { 0, 1, 0 }, BONE, GLOW)
			spike(tailLimb, T, { 0.8 * s, 18, -35.6 }, { 6 * s, 21.4, -41.6 }, 1.2, { 0, 1, 0 }, BONE, GLOW)
		end

		pet:light(GLOW, 2, 22)
		pet:particles("Sparkles", rgb(150, 255, 230), 8)
		pet:aura(rgb(70, 230, 200), rgb(190, 255, 240))
		pet:seat(0, (topOf(body, 3) + 0.4) / U, 3 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Brachiosaurus (Mythic): a gentle giant more than five times a player's height, its neck rising like a tree. A
-- grey-green hide dappled darker, a pale belly, a back grown over with moss and ferns and glowing mushrooms, rows of
-- glowing lime spots down its neck, flanks and tail like the lights of a deep-sea fish, a glowing crest on its
-- head and glowing eyes; fireflies drift round it.

Prehistoric.Brachiosaurus = {
	name = "Brachiosaurus",
	skeleton = "Strider",
	gait = "Stomp",
	scale = 0.42 * 1.6,
	draw = function(pet)
		-- Built in cells 1.6 design units across.
		local U = 1.6
		local T = inUnits(U)
		local HIDE = look(108, 102, 96)
		local HIDE_TOP = look(144, 136, 124)
		local HIDE_UNDER = look(62, 58, 56)
		local DAPPLE = look(84, 78, 74)
		local BELLY = look(190, 184, 152)
		local BELLY_SHADE = look(148, 142, 116)
		local MOSS = look(80, 138, 54)
		local MOSS_TOP = look(116, 176, 68)
		local CREST = look(180, 255, 100, NEON)
		local MOUTH = look(70, 50, 46)
		local FERN = rgb(66, 146, 58)
		local FERN_LIGHT = rgb(124, 196, 82)
		local STEM = rgb(226, 220, 196)
		local GLOW = rgb(180, 255, 100)
		local NAIL = rgb(70, 64, 56)

		local tones = {
			[HIDE] = { top = HIDE_TOP, under = HIDE_UNDER },
			[DAPPLE] = { under = HIDE_UNDER },
			[BELLY] = { under = BELLY_SHADE },
			[MOSS] = { top = MOSS_TOP },
		}
		local function hide(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.45 then
				return BELLY
			end
			if patches(p, 3.4) < 0.3 then
				return DAPPLE
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 31, 0 }, { 11, 11, 16 }), HIDE)
		body:add(ellipsoid({ 0, 34, 7 }, { 10.4, 11, 9 }), HIDE)
		body:add(ellipsoid({ 0, 30, -10 }, { 10, 10, 9 }), HIDE)
		body:coat(function(p, open, n)
			-- Moss over the top of the back.
			if n[2] > 0.35 and p[2] > 36 and patches(p, 2.6) > 0.25 then
				return MOSS
			end
			return hide(p, open, n)
		end)
		body:bake(tones)

		-- The neck and head, one limb, so the whole neck sways.
		local neckPath = { { 0, 37, 11, 7.6 }, { 0, 47, 16, 5.4 }, { 0, 56, 19, 4.2 }, { 0, 63.6, 21, 3.6 } }
		local head = newSculpt(U)
		head:add(rod(neckPath), HIDE)
		head:add(ellipsoid({ 0, 66, 24 }, { 3.4, 3.2, 4.6 }), HIDE)
		head:add(ellipsoid({ 0, 69.2, 23.2 }, { 2.6, 2.4, 2.8 }), HIDE)
		head:add(rod({ { 0, 65, 27, 2.8 }, { 0, 64, 31, 2.2 } }), HIDE)
		head:coat(function(p, open, n)
			if p[2] > 70 and n[2] > 0.2 then
				return CREST
			end
			if n[2] > 0.3 and p[2] < 58 and patches(p, 2.2) > 0.45 then
				return MOSS
			end
			if math.abs(p[1]) > 1 and p[3] > 27 and p[2] > 63 and p[2] < 64.4 then
				return MOUTH
			end
			return hide(p, open, n)
		end)
		head:bake(tones)

		-- Pillar legs in two halves, bending at the knee.
		local front, frontShin, back, backShin = newSculpt(U), newSculpt(U), newSculpt(U), newSculpt(U)
		front:add(ellipsoid({ 8, 31, 9 }, { 5, 7, 5.6 }), HIDE)
		front:add(rod({ { 8.4, 26, 9.4, 4.6 }, { 8.5, 15, 10, 4.2 } }), HIDE)
		frontShin:add(rod({ { 8.5, 15, 10, 4.15 }, { 8.6, 4, 10.6, 3.8 } }), HIDE)
		frontShin:add(ellipsoid({ 8.6, 2, 11.4 }, { 4.2, 2, 4.6 }), HIDE)
		back:add(ellipsoid({ 8, 28, -11 }, { 5.4, 8, 7 }), HIDE)
		back:add(rod({ { 8.4, 22, -11, 5 }, { 8.5, 13, -11.6, 4.5 } }), HIDE)
		backShin:add(rod({ { 8.5, 13, -11.6, 4.45 }, { 8.6, 4, -10, 4 } }), HIDE)
		backShin:add(ellipsoid({ 8.6, 2, -9.2 }, { 4.4, 2, 4.8 }), HIDE)
		for _, s in { front, frontShin, back, backShin } do
			s:coat(hide)
			s:bake(tones)
		end

		local spine = { { 0, 31, -16, 7.4 }, { 0, 27, -28, 4.8 }, { 2, 21, -40, 2.8 }, { 5, 15, -52, 1.2 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), HIDE)
		tail:coat(function(p, open, n)
			if n[2] > 0.45 and p[3] > -34 and patches(p, 2.2) > 0.4 then
				return MOSS
			end
			return hide(p, open, n)
		end)
		tail:bake(tones)

		-- A row of glowing spots down each side of a path of { x, y, z, radius }, `height` up its side (0 its
		-- middle, 1 its top), about `step` apart, smaller where it is thinner. On a rod, they sit on the rod's
		-- surface; otherwise on the clay's (which must then be the same on both sides).
		local function lights(
			limb: Limb,
			s: Sculpt,
			path: { { number } },
			step: number,
			height: number,
			size: number,
			onRod: boolean
		)
			for i, sample in Kit.alongPath(path, step) do
				local c, r = sample[1], sample[2]
				if i > 1 and r > 2.2 then
					local y = c[2] + r * height
					local k = size * (0.6 + 0.4 * r / path[1][4])
					for _, side in { 1, -1 } do
						local x = if onRod
							then c[1] + side * r * math.sqrt(1 - height * height) * 0.84
							else side * (sideOf(s, y, c[3]) - 0.1)
						T.ball(limb, { x, y, c[3] }, { k * 0.5, k, k }, GLOW, NEON)
					end
				end
			end
		end

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 31, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, HIDE)
		lights(bodyLimb, body, { { 0, 31, 12, 11 }, { 0, 33, 0, 11 }, { 0, 30, -14, 10 } }, 3.2, 0.2, 2.6, false)
		lights(bodyLimb, body, { { 0, 31, 9, 11 }, { 0, 31, 0, 11 }, { 0, 28, -12, 10 } }, 3.6, -0.25, 2, false)
		-- Ferns and glowing mushrooms growing in the moss on its back, clear of where the rider sits.
		for _, spot in
			body:surface(function(p: Vec, n: Vec): boolean
				return n[2] > 0.5 and p[2] > 38 and math.abs(p[3]) > 4 and noise(p) < 0.16
			end)
		do
			local p = spot[1]
			if noise(vadd(p, { 5, 5, 5 })) < 0.35 then
				T.blade(bodyLimb, vadd(p, { 0, -0.4, 0 }), vadd(p, { 0, 2.4, 0 }), 0.7, 0.7, { 0, 0, 1 }, STEM)
				T.ball(bodyLimb, vadd(p, { 0, 2.7, 0 }), { 2.6, 1.3, 2.6 }, GLOW, NEON)
			else
				for k = 0, 5 do
					local a = k * 1.05 + noise(p) * 6
					local dir = { math.cos(a) * 0.9, 1, math.sin(a) * 0.9 }
					T.taper(
						bodyLimb,
						vadd(p, { 0, -0.3, 0 }),
						vadd(p, vscale(dir, 4.4)),
						1.3,
						0.4,
						{ 0, 1, 0 },
						if k % 2 == 0 then FERN else FERN_LIGHT
					)
				end
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 37, 11 }))
		head:draw(headLimb, { body }, HIDE)
		glossyEye(headLimb, T, head, 67, 25.6, 1.4, rgb(30, 40, 26), GLOW, NEON, rgb(20, 40, 10))
		lights(headLimb, head, neckPath, 2.8, 0.1, 2.2, true)

		local function nails(limb: Limb, x: number, z: number)
			for _, dx in { -2, -0.7, 0.7, 2 } do
				T.taper(limb, { x + dx, 1, z }, { x + dx * 1.1, 0.2, z + 1.4 }, 1, 0.8, { 0, 1, 0 }, NAIL)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 8, 32, 9 }), function(limb)
			front:draw(limb, { body, frontShin }, HIDE)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 8.5, 15, 10 }), function(limb)
			frontShin:draw(limb, { front }, HIDE)
			nails(limb, 8.6, 13.6)
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 8, 29, -11 }), function(limb)
			back:draw(limb, { body, backShin }, HIDE)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 8.5, 13, -11.6 }), function(limb)
			backShin:draw(limb, { back }, HIDE)
			nails(limb, 8.6, -6.6)
		end, "BackLeftLeg")

		local tailLimb = pet:limb("Tail", T.at({ 0, 31, -16 }))
		tail:draw(tailLimb, { body }, HIDE)
		lights(tailLimb, tail, spine, 3, 0.2, 2, true)

		pet:light(GLOW, 3, 34)
		pet:particles("Fireflies", rgb(210, 255, 120), 16)
		pet:aura(rgb(140, 240, 90), rgb(220, 255, 170))
		pet:seat(0, (topOf(body, 0) + 0.4) / U, 0)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- T-Rex (Secret): the tyrant king, colossal: seven times a player's height at the head and longer than a dozen
-- players nose to tail. A dark hide striped with glowing amber like a tiger's, banded scales underneath, clusters
-- of glowing amber crystal along its neck, back and tail, a massive skull with heavy brows and hornlets over
-- glowing eyes, jaws hanging open on rows of great teeth and a glowing throat, tiny clawed arms, and huge legs
-- that bend at the knee as it strides.

Prehistoric.TRex = {
	name = "T-Rex",
	skeleton = "Tyrant",
	gait = "Stomp",
	scale = 0.42 * 2.4,
	draw = function(pet)
		-- Built in cells 2.4 design units across (about a stud each, at its size).
		local U = 2.4
		local T = inUnits(U)
		local HIDE = look(62, 50, 44)
		local HIDE_TOP = look(96, 80, 68)
		local HIDE_UNDER = look(34, 26, 24)
		local BELLY = look(152, 130, 102)
		local BELLY_DARK = look(120, 100, 78)
		local SCUTE = look(42, 34, 32)
		local STRIPE = look(255, 156, 36, NEON)
		local STRIPE_RIM = look(150, 64, 22)
		local MOUTH = look(98, 28, 24)
		local TONGUE = look(150, 52, 48)
		local AMBER = rgb(222, 122, 22)
		local AMBER_TIP = rgb(255, 196, 70)
		local TOOTH = rgb(246, 236, 210)
		local CLAW = rgb(36, 28, 26)
		local HORN = rgb(74, 60, 52)
		local KNOB = rgb(48, 38, 34)
		local IRIS = rgb(255, 180, 40)
		local GLOW = rgb(255, 160, 40)

		local tones = {
			[HIDE] = { top = HIDE_TOP, under = HIDE_UNDER },
			[SCUTE] = { under = HIDE_UNDER },
		}
		-- Glowing amber tiger stripes across the back and down the flanks, narrowing as they go, each a hot line in
		-- a darker rim; banded pale scales underneath; rough dark scutes over the top.
		local function hide(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.45 then
				return if math.floor(p[3] / 4.8) % 2 == 0 then BELLY else BELLY_DARK
			end
			local period = 18
			local w = 3.6 * math.clamp((n[2] + 0.4) / 0.9, 0.35, 1)
			local d = math.abs((p[3] + 3.4 * math.sin(p[2] * 0.16) + math.abs(p[1]) * 0.3) % period - period / 2)
			if d < w then
				return if d < w * 0.42 then STRIPE else STRIPE_RIM
			end
			if n[2] > 0.5 and patches(p, 5) < 0.32 then
				return SCUTE
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 46, 0 }, { 13, 13.6, 20 }), HIDE)
		body:add(ellipsoid({ 0, 44, 12 }, { 12, 13, 11 }), HIDE)
		body:add(ellipsoid({ 0, 48, -10 }, { 12.4, 12, 12 }), HIDE)
		body:add(rod({ { 0, 48, 16, 10.4 }, { 0, 56, 24, 9 }, { 0, 61, 29, 8.4 } }), HIDE)
		body:coat(hide)
		body:bake(tones)

		-- The skull: heavy brows, broad cheeks and a deep snout; the lower jaw is its own limb.
		local head = newSculpt(U)
		head:add(rod({ { 0, 60, 29, 8.4 }, { 0, 64, 34, 8.4 } }), HIDE)
		head:add(ellipsoid({ 0, 66, 38 }, { 9, 8.4, 11 }), HIDE)
		head:add(ellipsoid({ 0, 62.6, 34 }, { 10, 6.6, 7.4 }), HIDE)
		head:add(rod({ { 0, 66, 44, 7.6 }, { 0, 64.6, 52, 6.4 }, { 0, 63.4, 59, 5 } }), HIDE)
		head:add(ellipsoid({ 0, 70.4, 40 }, { 7, 2.6, 6 }), HIDE)
		head:coat(function(p, open, n)
			if n[2] < -0.5 and p[3] > 37 and math.abs(p[1]) < 5.6 then
				return MOUTH
			end
			return hide(p, open, n)
		end)
		head:bake(tones)

		local jaw = newSculpt(U)
		jaw:add(rod({ { 0, 56, 35, 5.8 }, { 0, 51.6, 50, 4.6 }, { 0, 49.6, 57, 3.6 } }), HIDE)
		jaw:coat(function(p, open, n)
			if n[2] > 0.5 and p[3] > 37 then
				return if math.abs(p[1]) < 1.6 then TONGUE else MOUTH
			end
			return hide(p, open, n)
		end)
		jaw:bake(tones)

		local arm = newSculpt(U)
		arm:add(rod({ { 9.4, 40, 16, 3.4 }, { 11.4, 34.6, 19, 2.6 }, { 10.6, 33.6, 24, 2 } }), HIDE)
		arm:coat(hide)
		arm:bake(tones)

		-- Great thighs, then shins bending back to the ankle, and broad three-toed feet.
		local leg = newSculpt(U)
		leg:add(ellipsoid({ 12.4, 42, -6 }, { 7.4, 13, 11 }), HIDE)
		leg:add(rod({ { 13, 38, -4, 7 }, { 14, 26, 2, 5.6 } }), HIDE)
		leg:coat(hide)
		leg:bake(tones)
		local shin = newSculpt(U)
		shin:add(rod({ { 14, 26, 2, 5.4 }, { 14.2, 12, -5, 3.8 } }), HIDE)
		shin:add(rod({ { 14.2, 12, -5, 3.6 }, { 14.2, 4, -2, 3.2 } }), HIDE)
		shin:add(ellipsoid({ 14.2, 2.6, 2 }, { 5, 2.6, 6.4 }), HIDE)
		for _, dx in { -2.8, 0, 2.8 } do
			shin:add(rod({ { 14.2 + dx * 0.6, 2.4, 5, 1.9 }, { 14.2 + dx * 1.3, 1.8, 10.6, 1.4 } }), HIDE)
		end
		shin:coat(hide)
		shin:bake(tones)

		local spine = {
			{ 0, 48, -20, 11 },
			{ 0, 48, -36, 8.4 },
			{ 2, 46, -54, 5.8 },
			{ 5, 42, -72, 3.6 },
			{ 8, 38, -88, 1.8 },
		}
		local tail = newSculpt(U)
		tail:add(rod(spine), HIDE)
		tail:coat(hide)
		tail:bake(tones)

		local legMirror, armMirror = leg:mirror(), arm:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 46, 0 }))
		body:draw(bodyLimb, { head, tail, leg, legMirror, arm, armMirror }, HIDE)
		-- Clusters of glowing amber along the neck and back; the middle of the back is left for a rider.
		for i, at in { { 0, 22 }, { 0, 16.4 }, { 0, -13 }, { 0, -18 } } do
			local z = at[2]
			local y = topOf(body, z)
			Kit.crystalCluster(
				bodyLimb,
				T,
				{ 0, y - 2, z },
				{ 0, 1, -0.3 },
				({ 13, 10, 16, 12 })[i],
				4,
				AMBER,
				AMBER_TIP,
				nil,
				NEON,
				i * 1.7
			)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 60, 29 }))
		head:draw(headLimb, { body, jaw }, HIDE)
		Kit.slitEyes(headLimb, head, { 68.2, 45 }, { 68.6, 41.4 }, 1.6, IRIS, NEON, rgb(20, 12, 10))
		-- A glow deep in its throat.
		T.ball(headLimb, { 0, 57.4, 40 }, { 7, 3.4, 6 }, GLOW, NEON)
		for _, s in { 1, -1 } do
			-- Hornlets over the eyes, and a row of knobs down the snout.
			T.taper(headLimb, { 5.6 * s, 71, 42 }, { 7.6 * s, 74.6, 37 }, 2.8, 2.2, { 0, 0, 1 }, HORN)
			T.taper(headLimb, { 6.4 * s, 70, 38 }, { 8.4 * s, 72, 33.6 }, 2, 1.6, { 0, 0, 1 }, HORN)
			for k = 0, 3 do
				local z = 47 + k * 3.4
				T.ball(headLimb, { 2.6 * s, topOf(head, z, 2.6) - 0.2, z }, { 2, 1.4, 2.2 }, KNOB)
			end
			-- Great teeth down the upper jaw.
			for k = 0, 6 do
				local z = 39 + k * 3
				local x = sideOf(head, 59.6 + k * 0.1, z) - 1.4
				if x > 1 then
					local y = Kit.bottomOf(head, z, x) + 0.6
					local long = 4 - math.abs(k - 3) * 0.4
					T.taper(
						headLimb,
						{ x * s, y, z },
						{ x * s * 0.94, y - long, z + 0.6 },
						1.6,
						1.4,
						{ s, 0, 0 },
						TOOTH
					)
				end
			end
		end
		T.taper(headLimb, { 1.4, 59.8, 60.4 }, { 1.2, 56.6, 61 }, 1.2, 1, { 0, 0, 1 }, TOOTH)
		T.taper(headLimb, { -1.4, 59.8, 60.4 }, { -1.2, 56.6, 61 }, 1.2, 1, { 0, 0, 1 }, TOOTH)

		local jawLimb = pet:limb("Jaw", T.at({ 0, 58, 32 }), "Head")
		jaw:draw(jawLimb, { head }, HIDE)
		for _, s in { 1, -1 } do
			for k = 0, 5 do
				local z = 40 + k * 3
				local x = sideOf(jaw, 53 - k * 0.6, z) - 1.2
				if x > 0.8 then
					local y = topOf(jaw, z, x) - 0.6
					local long = 3.2 - math.abs(k - 2.5) * 0.4
					T.taper(jawLimb, { x * s, y, z }, { x * s * 0.94, y + long, z + 0.6 }, 1.4, 1.2, { s, 0, 0 }, TOOTH)
				end
			end
		end

		pet:limbPair("LeftArm", "RightArm", T.at({ 9.4, 40, 16 }), function(limb)
			arm:draw(limb, { body }, HIDE)
			for _, dx in { -0.8, 0.8 } do
				T.taper(limb, { 10.6 + dx, 33.6, 24.6 }, { 10.6 + dx * 1.2, 30.6, 26.4 }, 1, 0.9, { 0, 0, 1 }, CLAW)
			end
		end)
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 12, 46, -8 }), function(limb)
			leg:draw(limb, { body, shin }, HIDE)
		end)
		pet:limbPair("LeftShin", "RightShin", T.at({ 14, 26, 2 }), function(limb)
			shin:draw(limb, { leg }, HIDE)
			-- Hooked claws on the three toes, and a dew claw behind.
			for _, dx in { -2.8, 0, 2.8 } do
				local tip = { 14.2 + dx * 1.3, 1.8, 10.6 }
				T.taper(limb, vadd(tip, { 0, 0.4, -0.6 }), vadd(tip, { 0, -1.6, 3 }), 1.6, 1.4, { 0, 1, 0 }, CLAW)
			end
			T.taper(limb, { 15.6, 4, -4.6 }, { 16.2, 1.4, -7.6 }, 1.2, 1, { 0, 1, 0 }, CLAW)
		end, "LeftLeg")

		local tailLimb = pet:limb("Tail", T.at({ 0, 48, -20 }))
		tail:draw(tailLimb, { body }, HIDE)
		for k = 1, #spine - 1 do
			local p = vlerp(spine[k], spine[k + 1], 0.5)
			local r = (spine[k][4] + spine[k + 1][4]) / 2
			Kit.crystalCluster(
				tailLimb,
				T,
				{ p[1], p[2] + r * 0.7, p[3] },
				{ 0, 1, -0.5 },
				12 - k * 2,
				3,
				AMBER,
				AMBER_TIP,
				nil,
				NEON,
				k * 2.3
			)
		end

		pet:light(GLOW, 4, 50)
		pet:particles("Sparkles", rgb(255, 196, 80), 20)
		pet:aura(rgb(255, 150, 40), rgb(255, 224, 140))
		pet:seat(0, (topOf(body, -2) + 0.4) / U, -2 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Mosasaurus (Eternal): the tyrant of the ancient seas, colossal, swimming through the air longer than fifteen
-- players: a deep sea-blue hide over a pale belly, chevrons and a lateral line of violet light along it like the
-- glow of the deep, rows of glowing spots down its flanks, a ridge of spines glowing at their points, a long
-- crocodile skull with jaws agape on rows of teeth and a glowing violet throat, great paddle flippers edged in light
-- and a sweeping tail fin.

Prehistoric.Mosasaurus = {
	name = "Mosasaurus",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 8,
	scale = 0.42 * 2.6,
	draw = function(pet)
		-- Built in cells 2.6 design units across (about a stud each, at its size).
		local U = 2.6
		local T = inUnits(U)
		local HIDE = look(26, 48, 64)
		local HIDE_TOP = look(42, 74, 94)
		local HIDE_UNDER = look(16, 28, 40)
		local BELLY = look(172, 192, 200)
		local BELLY_DARK = look(132, 152, 164)
		local VIOLET = look(204, 112, 255, NEON)
		local VIOLET_RIM = look(84, 40, 130)
		local MOUTH = look(56, 18, 58)
		local FIN = look(30, 56, 74)
		local FIN_RIM = look(204, 112, 255, NEON)
		local FIN_RAY = look(18, 36, 50)
		local TOOTH = rgb(244, 240, 226)
		local SPINE = rgb(20, 34, 46)
		local GLOW = rgb(204, 112, 255)
		local IRIS = rgb(230, 160, 255)
		local MEMBRANE = rgb(34, 62, 82)
		local MEMBRANE_DARK = rgb(22, 40, 56)

		local tones = {
			[HIDE] = { top = HIDE_TOP, under = HIDE_UNDER },
			[BELLY] = { under = BELLY_DARK },
			[FIN] = { under = HIDE_UNDER },
		}
		-- Where the middle of a path of { x, y, z, radius } is at a depth z, and its radius there.
		local function centreAt(path: { { number } }, z: number): (number, number)
			for i = 1, #path - 1 do
				local a, b = path[i], path[i + 1]
				if z <= a[3] and z >= b[3] then
					local t = (a[3] - z) / (a[3] - b[3])
					return a[2] + (b[2] - a[2]) * t, a[4] + (b[4] - a[4]) * t
				end
			end
			return -math.huge, 0
		end
		-- Pale underneath in bands; thin violet chevrons pointing forward along the back; and a glowing line along
		-- each flank (on a path's clay), a little below its middle, in a dark violet rim.
		local function coat(path: { { number } }?): (Vec, any, Vec) -> Look?
			return function(p, _, n)
				if n[2] < -0.3 then
					return if math.floor(p[3] / 5.2) % 2 == 0 then BELLY else BELLY_DARK
				end
				if path then
					local cy, r = centreAt(path, p[3])
					local d = math.abs(p[2] - (cy - r * 0.18))
					if d < 2.6 and math.abs(p[1]) > r * 0.5 then
						return if d < 1.2 then VIOLET else VIOLET_RIM
					end
				end
				if n[2] > 0.45 then
					local period = 18
					local d = math.abs((p[3] + math.abs(p[1]) * 1.4) % period - period / 2)
					if d < 1.8 then
						return if d < 0.9 then VIOLET else VIOLET_RIM
					end
				end
				return nil
			end
		end

		local bodyPath =
			{ { 0, 26, 32, 12 }, { 0, 28, 16, 16.4 }, { 0, 28, -6, 16.6 }, { 0, 26, -28, 13 }, { 0, 23, -42, 8.6 } }
		local body = newSculpt(U)
		body:add(rod(bodyPath), HIDE)
		body:coat(coat(bodyPath))
		body:bake(tones)

		-- A paddle flipper: an egg shape flattened and turned, ribbed and edged in light.
		local function paddle(s: Sculpt, frame: any, radii: Vec)
			s:add(ellipsoid({ 0, 0, 0 }, radii), FIN, frame)
			s:coat(function(p, _, n)
				local x, _, z = Kit.toLocal(frame, p[1], p[2], p[3])
				local r = math.sqrt((x / radii[1]) ^ 2 + (z / radii[3]) ^ 2)
				if r > 1.2 then
					return nil
				end
				if r > 0.76 and (z < 0 or x > 0) then
					return FIN_RIM
				end
				if math.abs(z) % 2.6 < 0.9 and n[2] > -0.5 then
					return FIN_RAY
				end
				return nil
			end)
		end
		local hindFin = { origin = { 17, 15, -28 }, yaw = -0.6, roll = -0.45 }
		paddle(body, hindFin, { 9.6, 1.8, 4.2 })
		body:bake(tones)

		-- The skull, jaws agape.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 27, 42 }, { 10.6, 9.6, 12.6 }), HIDE)
		head:add(rod({ { 0, 27.4, 50, 7.6 }, { 0, 25.6, 64, 5.4 }, { 0, 24.2, 76, 3.6 } }), HIDE)
		head:add(rod({ { 0, 18.6, 40, 7 }, { 0, 14, 60, 4.4 }, { 0, 12.6, 72, 3 } }), HIDE)
		head:add(ellipsoid({ 0, 33.6, 46 }, { 6.4, 2.4, 5.6 }), HIDE)
		local skin = coat(nil)
		head:coat(function(p, open, n)
			if p[3] > 46 and math.abs(p[1]) < 5 and p[2] > 15 and p[2] < 24 then
				if n[2] < -0.4 or n[2] > 0.4 then
					return MOUTH
				end
			end
			return skin(p, open, n)
		end)
		head:bake(tones)

		local fin = newSculpt(U)
		local foreFin = { origin = { 24, 14, 14 }, yaw = -0.4, roll = -0.32 }
		paddle(fin, foreFin, { 15, 2.2, 6 })
		fin:bake(tones)

		local spine = { { 0, 23, -42, 8.4 }, { 0, 21, -62, 6 }, { 0, 18, -82, 3.8 }, { 0, 15.4, -96, 2.2 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), HIDE)
		tail:coat(coat(spine))
		tail:bake(tones)

		-- Glowing spots in a row down each flank of a path, `height` up its side.
		local function lights(limb: Limb, path: { { number } }, step: number, height: number, size: number)
			for i, sample in Kit.alongPath(path, step) do
				local c, r = sample[1], sample[2]
				if i > 1 and r > 3 then
					for _, side in { 1, -1 } do
						local x = c[1] + side * r * math.sqrt(1 - height * height) * 0.86
						T.ball(limb, { x, c[2] + r * height, c[3] }, { size * 0.5, size, size }, GLOW, NEON)
					end
				end
			end
		end
		-- A ridge of spines along the back, glowing at their points.
		local function ridge(limb: Limb, s: Sculpt, from: number, to: number, step: number, size: number)
			local z = from
			while z > to do
				local y = topOf(s, z)
				if y > -math.huge then
					spike(
						limb,
						T,
						{ 0, y - 1.4, z },
						{ 0, y + size, z - size * 0.9 },
						size * 0.5,
						{ 1, 0, 0 },
						SPINE,
						GLOW
					)
				end
				z -= step
			end
		end

		local bodyLimb = pet:limb("Body", T.at({ 0, 26, 0 }))
		body:draw(bodyLimb, { head, fin, fin:mirror(), tail }, HIDE)
		lights(bodyLimb, bodyPath, 4.4, -0.5, 2.2)
		ridge(bodyLimb, body, 30, 9, 5, 6)
		ridge(bodyLimb, body, -14, -40, 5, 6)

		local headLimb = pet:limb("Head", T.at({ 0, 25, 34 }))
		head:draw(headLimb, { body }, HIDE)
		Kit.slitEyes(headLimb, head, { 31.6, 52 }, { 32, 47.6 }, 1.8, IRIS, NEON, rgb(14, 10, 24))
		ridge(headLimb, head, 46, 34, 4.6, 3.6)
		-- A violet glow deep in its throat, and rows of teeth in both jaws.
		T.ball(headLimb, { 0, 20.6, 46 }, { 10, 5, 9 }, GLOW, NEON)
		for _, s in { 1, -1 } do
			for k = 0, 8 do
				local z = 47 + k * 3.2
				local x = sideOf(head, 21, z) - 1.6
				if x > 1 then
					local y = Kit.bottomOf(head, z, x) + 0.6
					if y < 24 then
						local long = 3.6 - math.abs(k - 3) * 0.3
						T.taper(
							headLimb,
							{ x * s, y, z },
							{ x * s * 0.9, y - long, z + 0.8 },
							1.5,
							1.3,
							{ s, 0, 0 },
							TOOTH
						)
					end
				end
				local xl = sideOf(head, 16, z - 1.6) - 1.4
				if xl > 1 then
					local y = topOf(head, z - 1.6, xl) - 0.6
					if y < 20 then
						local long = 3 - math.abs(k - 3) * 0.25
						T.taper(
							headLimb,
							{ xl * s, y, z - 1.6 },
							{ xl * s * 0.9, y + long, z - 0.8 },
							1.3,
							1.2,
							{ s, 0, 0 },
							TOOTH
						)
					end
				end
			end
		end

		pet:limbPair("LeftFin", "RightFin", T.at({ 11, 18, 18 }), function(limb)
			fin:draw(limb, { body }, HIDE)
		end)

		local tailLimb = pet:limb("Tail", T.at({ 0, 23, -42 }))
		tail:draw(tailLimb, { body }, HIDE)
		lights(tailLimb, spine, 4.4, -0.5, 1.8)
		ridge(tailLimb, tail, -46, -88, 5.4, 3.6)
		-- The tail fin: a long lower lobe and a shorter upper one, dark, edged with violet light.
		local root, notch = { 0, 15.4, -94 }, { 0, 15, -104 }
		local upper, lower = { 0, 30, -112 }, { 0, 0.4, -114 }
		T.triangle(tailLimb, { 0, 19, -90 }, upper, notch, 1.4, MEMBRANE)
		T.triangle(tailLimb, root, upper, notch, 1.4, MEMBRANE)
		T.triangle(tailLimb, { 0, 12, -90 }, lower, notch, 1.4, MEMBRANE_DARK)
		T.triangle(tailLimb, root, lower, notch, 1.4, MEMBRANE_DARK)
		T.blade(tailLimb, upper, notch, 0.9, 1.8, { 1, 0, 0 }, GLOW, NEON)
		T.blade(tailLimb, lower, notch, 0.9, 1.8, { 1, 0, 0 }, GLOW, NEON)
		T.blade(tailLimb, { 0, 19, -90 }, upper, 0.8, 1.7, { 1, 0, 0 }, MEMBRANE_DARK)
		T.blade(tailLimb, { 0, 12, -90 }, lower, 0.8, 1.7, { 1, 0, 0 }, MEMBRANE)

		pet:light(GLOW, 4.4, 60)
		pet:particles("Bubbles", rgb(220, 170, 255), 12)
		pet:aura(rgb(170, 90, 255), rgb(230, 190, 255))
		pet:seat(0, (topOf(body, 0) + 0.4) / U, 0)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Lunar Dragon (Eternal): a colossal dragon of the night sky, seven times a player's height with wings spanning
-- thirteen. Midnight scales sprinkled with stars over silver belly plates, a long elegant neck with a flowing mane of
-- silver frills glowing at their tips, crescent horns, long glowing whiskers and glowing eyes, a crescent moon
-- cradling its head, moonstone crystals down its back, great violet wings strewn with stars and edged in moonlight,
-- and a crescent blade of light at the end of its tail.

Prehistoric.LunarDragon = {
	name = "Lunar Dragon",
	skeleton = "Dragon",
	gait = "Walk",
	scale = 0.42 * 2.4,
	draw = function(pet)
		-- Built in cells 2.4 design units across (about a stud each, at its size).
		local U = 2.4
		local T = inUnits(U)
		local NIGHT = look(38, 42, 98)
		local NIGHT_TOP = look(62, 68, 140)
		local NIGHT_UNDER = look(22, 24, 62)
		local SILVER = look(214, 222, 244)
		local SILVER_DARK = look(162, 172, 206)
		local STAR = look(255, 255, 255, NEON)
		local MOUTH = look(40, 30, 70)
		local MOON = rgb(226, 236, 255)
		local MOONLIGHT = rgb(176, 206, 255)
		local MOONSTONE = rgb(170, 190, 240)
		local HORN = rgb(206, 214, 236)
		local CLAW = rgb(180, 188, 214)
		local BONE = rgb(190, 198, 226)
		local MEMBRANE = rgb(70, 46, 140)
		local MEMBRANE_DARK = rgb(44, 30, 102)
		local MANE = rgb(150, 170, 230)
		local MANE_DARK = rgb(80, 90, 160)
		local GLOW = rgb(170, 210, 255)
		local IRIS = rgb(150, 240, 255)
		local MOONFIRE = rgb(110, 160, 255)
		local MOONFIRE_HOT = rgb(220, 236, 255)

		local tones = {
			[NIGHT] = { top = NIGHT_TOP, under = NIGHT_UNDER },
			[SILVER] = { under = SILVER_DARK },
		}
		-- Silver belly plates in bands underneath; midnight scales above, sprinkled with stars.
		local function scales(p: Vec, _: any, n: Vec): Look?
			if n[2] < -0.4 then
				return if math.floor(p[3] / 3.6) % 2 == 0 then SILVER else SILVER_DARK
			end
			if n[2] > -0.1 and noise(p) < 0.045 then
				return STAR
			end
			return nil
		end

		-- A deep chest, a slender waist, strong hips, and a long neck curving up.
		local neckPath = { { 0, 36, 14, 7 }, { 0, 46, 20, 5.4 }, { 0, 56, 22, 4.6 }, { 0, 63, 24, 4.2 } }
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 31, 8 }, { 9.6, 11, 10 }), NIGHT)
		body:add(ellipsoid({ 0, 29, -6 }, { 8.6, 9.4, 12 }), NIGHT)
		body:add(ellipsoid({ 0, 30, -18 }, { 8.6, 9, 8 }), NIGHT)
		body:add(rod(neckPath), NIGHT)
		body:coat(scales)
		body:bake(tones)

		-- A long, fine head, its mouth closed.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 66, 29 }, { 5.4, 4.8, 6.4 }), NIGHT)
		head:add(ellipsoid({ 0, 69, 30 }, { 4.6, 1.8, 3.6 }), NIGHT)
		head:add(rod({ { 0, 65, 33, 4 }, { 0, 63.6, 44, 2.6 } }), NIGHT)
		head:add(rod({ { 0, 60.8, 30, 3.2 }, { 0, 60, 41, 2 } }), NIGHT)
		head:coat(function(p, open, n)
			if p[3] > 33 and p[2] > 61.4 and p[2] < 62.6 and math.abs(p[1]) > 0.8 then
				return MOUTH
			end
			return scales(p, open, n)
		end)
		head:bake(tones)

		-- Long, slender legs in two halves, bending at the knee: the front legs' elbows behind, the hind legs'
		-- knees in front and hocks behind.
		local front, frontShin, back, backShin = newSculpt(U), newSculpt(U), newSculpt(U), newSculpt(U)
		front:add(ellipsoid({ 8, 30, 9 }, { 4.6, 7.4, 5.6 }), NIGHT)
		front:add(rod({ { 8.2, 26, 9, 4 }, { 8.6, 16, 6, 3.4 } }), NIGHT)
		frontShin:add(rod({ { 8.6, 16, 6, 3.3 }, { 8.6, 4, 10, 2.9 } }), NIGHT)
		frontShin:add(ellipsoid({ 8.6, 2.4, 11.6 }, { 3.6, 2.4, 4.4 }), NIGHT)
		back:add(ellipsoid({ 8, 29, -18 }, { 5.6, 9, 7.6 }), NIGHT)
		back:add(rod({ { 8.4, 24, -19, 4.4 }, { 8.6, 15, -14, 3.6 } }), NIGHT)
		backShin:add(rod({ { 8.6, 15, -14, 3.5 }, { 8.6, 8, -21, 3 }, { 8.6, 4, -18.4, 3 } }), NIGHT)
		backShin:add(ellipsoid({ 8.6, 2.4, -16.4 }, { 4, 2.4, 4.8 }), NIGHT)
		for _, s in { front, frontShin, back, backShin } do
			s:coat(scales)
			s:bake(tones)
		end

		local spine =
			{ { 0, 30, -24, 6.2 }, { 2, 27, -36, 4.8 }, { 6, 21, -48, 3.6 }, { 9, 16, -60, 2.4 }, { 9, 15, -72, 1.4 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), NIGHT)
		tail:coat(scales)
		tail:bake(tones)

		-- A frill of the mane: a feather of silver, darker at the root, glowing at the tip.
		local function frill(limb: Limb, root: Vec, dir: Vec, length: number, width: number)
			plume(limb, T, root, dir, length, width, { 1, 0, 0 }, MANE_DARK, MANE, GLOW, NEON)
		end

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 30, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, NIGHT)
		-- The mane flowing down the back of the neck.
		for i, sample in Kit.alongPath(neckPath, 3.4) do
			local c, r = sample[1], sample[2]
			if i > 1 and c[2] < 61 then
				frill(bodyLimb, { 0, c[2] + r * 0.7, c[3] - r * 0.6 }, { 0, 0.3, -1 }, 7 - i * 0.3, 2.4)
			end
		end
		-- Moonstone crystals down the back; the back between the wings is left for a rider.
		for i, z in { 12.6, -14, -19 } do
			local y = topOf(body, z)
			Kit.crystal(
				bodyLimb,
				T,
				{ 0, y - 1, z },
				{ 0, 1, -0.4 },
				({ 6, 7, 5.6 })[i],
				2.2,
				MOONSTONE,
				MOON,
				nil,
				NEON
			)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 62, 24 }))
		head:draw(headLimb, { body }, NIGHT)
		Kit.slitEyes(headLimb, head, { 67.4, 35 }, { 67.8, 31.6 }, 1.3, IRIS, NEON, rgb(14, 12, 30))
		for _, s in { 1, -1 } do
			-- Crescent horns sweeping back and curling down, glowing at their points.
			local horn = {
				{ 3.4 * s, 69, 28 },
				{ 6 * s, 74, 23 },
				{ 7.4 * s, 77.6, 16 },
				{ 7 * s, 78, 8 },
				{ 5.4 * s, 75.6, 2 },
			}
			T.branch(headLimb, { horn[1], horn[2], horn[3], horn[4] }, 3.2, { 1, 0, 0 }, HORN)
			T.taper(headLimb, horn[4], horn[5], 1.8, 1.8, { 1, 0, 0 }, GLOW, NEON)
			-- Long whiskers trailing from the snout, glowing at their ends.
			local whisker = { { 2.2 * s, 63, 41 }, { 5 * s, 62, 38 }, { 8 * s, 58, 33 }, { 10 * s, 53, 29 } }
			for k = 1, #whisker - 1 do
				local last = k == #whisker - 1
				T.blade(
					headLimb,
					whisker[k],
					whisker[k + 1],
					0.7,
					0.7,
					{ 0, 1, 0 },
					if last then GLOW else MANE,
					if last then NEON else nil
				)
			end
			-- Frills behind the jaw.
			frill(headLimb, { 4.4 * s, 64, 25 }, { 0.8 * s, 0.1, -1 }, 7, 2.6)
			frill(headLimb, { 4 * s, 66.6, 24.4 }, { 0.6 * s, 0.6, -1 }, 6, 2.2)
		end
		-- A great crescent moon behind its head: a thick arc of light round it, open to one side, tapering to its
		-- two points.
		local centre, radius = { 0, 72, 20 }, 13
		local count = 20
		local from, to = math.rad(70), math.rad(290)
		local function arc(i: number): Vec
			local a = from + (to - from) * i / count
			return { centre[1] + math.cos(a) * radius, centre[2] + math.sin(a) * radius, centre[3] }
		end
		for i = 0, count - 1 do
			local t = (i + 0.5) / count
			local w = 0.6 + 3.4 * math.sin(t * math.pi)
			-- Pushed outwards by half its width, so the inside edge stays a clean circle; on a silver rim.
			local out = vnorm(vsub(arc(i + 0.5), centre))
			local push = vscale(out, w * 0.5 - 0.6)
			local a, b = vadd(arc(i), push), vadd(arc(i + 1), push)
			T.blade(headLimb, a, b, w, 1.2, { 0, 0, 1 }, MOONLIGHT, NEON)
			T.blade(headLimb, vadd(a, { 0, 0, -0.9 }), vadd(b, { 0, 0, -0.9 }), w + 1.6, 1, { 0, 0, 1 }, HORN)
		end

		local function talons(limb: Limb, x: number, z: number)
			for _, dx in { -2.4, -0.8, 0.8, 2.4 } do
				T.taper(limb, { x + dx, 1.8, z }, { x + dx * 1.1, 0.2, z + 2.8 }, 1.1, 1, { 0, 1, 0 }, CLAW)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 8, 34, 9 }), function(limb)
			front:draw(limb, { body, frontShin }, NIGHT)
		end)
		pet:limbPair("FrontLeftShin", "FrontRightShin", T.at({ 8.6, 16, 6 }), function(limb)
			frontShin:draw(limb, { front }, NIGHT)
			talons(limb, 8.6, 13.8)
		end, "FrontLeftLeg")
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 8, 34, -18 }), function(limb)
			back:draw(limb, { body, backShin }, NIGHT)
		end)
		pet:limbPair("BackLeftShin", "BackRightShin", T.at({ 8.6, 15, -14 }), function(limb)
			backShin:draw(limb, { back }, NIGHT)
			talons(limb, 8.6, -14.2)
		end, "BackLeftLeg")

		local tailLimb = pet:limb("Tail", T.at({ 0, 30, -24 }))
		tail:draw(tailLimb, { body }, NIGHT)
		for k = 1, #spine - 2 do
			local p = vlerp(spine[k], spine[k + 1], 0.5)
			local r = (spine[k][4] + spine[k + 1][4]) / 2
			Kit.crystal(
				tailLimb,
				T,
				{ p[1], p[2] + r * 0.6, p[3] },
				{ 0, 1, -0.6 },
				5 - k,
				1.8,
				MOONSTONE,
				MOON,
				nil,
				NEON
			)
		end
		-- A crescent blade of light at the end of the tail.
		local tailEnd = spine[#spine]
		local tc = { tailEnd[1], tailEnd[2], tailEnd[3] - 7.6 }
		for i = 0, 9 do
			local a0, a1 = math.rad(-100 + i * 20), math.rad(-100 + (i + 1) * 20)
			local p0 = { tc[1], tc[2] + math.sin(a0) * 7, tc[3] + math.cos(a0) * 7 }
			local p1 = { tc[1], tc[2] + math.sin(a1) * 7, tc[3] + math.cos(a1) * 7 }
			local w = 0.5 + 3 * math.sin((i + 0.5) / 10 * math.pi)
			T.blade(tailLimb, p0, p1, w, 1.2, { 1, 0, 0 }, MOON, NEON)
		end
		-- Blue moonfire burning in the crescent's hollow.
		tailLimb:fire(T.at(vadd(tc, { 0, 0, 2 })), 5, MOONFIRE, MOONFIRE_HOT)

		-- The wings: silver bones and five fingers webbed with deep violet strewn with stars, the trailing edge
		-- glowing with moonlight.
		pet:limbPair("LeftWing", "RightWing", T.at({ 8, 40, 8 }), function(wing)
			local shoulder, elbow, wrist = { 8, 40, 8 }, { 22, 56, 2 }, { 36, 66, -6 }
			local tips = { { 60, 76, -8 }, { 72, 62, -14 }, { 70, 44, -20 }, { 58, 30, -24 }, { 42, 24, -24 } }
			local root = { 8, 32, -14 }
			T.blade(wing, shoulder, elbow, 3.2, 2.8, { 0, 0, 1 }, BONE)
			T.blade(wing, elbow, wrist, 2.6, 2.4, { 0, 0, 1 }, BONE)
			T.ball(wing, elbow, { 3.4, 3.4, 3.4 }, BONE)
			T.ball(wing, wrist, { 3, 3, 3 }, BONE)
			T.taper(wing, wrist, vadd(wrist, { 1.6, 5, 2 }), 1.8, 1.4, { 0, 0, 1 }, HORN)
			wing:fire(T.at(vadd(wrist, { 1.6, 6, 2 })), 3.6, MOONFIRE, MOONFIRE_HOT)
			local last = tips[#tips]
			for k, tip in tips do
				T.blade(wing, wrist, tip, 1.4, 1.2, { 0, 0, 1 }, BONE)
				if k > 1 then
					T.triangle(wing, wrist, tips[k - 1], tip, 0.8, if k % 2 == 0 then MEMBRANE else MEMBRANE_DARK)
				end
			end
			T.triangle(wing, wrist, last, elbow, 0.8, MEMBRANE)
			T.triangle(wing, elbow, last, root, 0.8, MEMBRANE_DARK)
			T.triangle(wing, elbow, root, shoulder, 0.8, MEMBRANE)
			-- Moonlight along the trailing edge.
			for k = 1, #tips - 1 do
				T.blade(wing, tips[k], tips[k + 1], 0.8, 1, { 0, 0, 1 }, GLOW, NEON)
			end
			T.blade(wing, last, root, 0.8, 1, { 0, 0, 1 }, GLOW, NEON)
			-- Stars strewn over the membrane.
			for k = 2, #tips do
				for j = 1, 3 do
					local a, b = vlerp(wrist, tips[k - 1], 0.3 + j * 0.18), vlerp(wrist, tips[k], 0.3 + j * 0.18)
					local p = vlerp(a, b, 0.25 + 0.5 * noise({ k, j, 1 }))
					local size = 0.8 + 0.8 * noise({ j, k, 2 })
					T.ball(wing, p, { size, size, size }, MOON, NEON)
				end
			end
		end)

		pet:light(GLOW, 4.4, 56)
		pet:particles("Sparkles", rgb(236, 242, 255), 24)
		pet:aura(rgb(140, 160, 255), rgb(236, 240, 255))
		pet:seat(0, (topOf(body, -4) + 0.4) / U, -4 / U)
	end,
}

return Prehistoric
