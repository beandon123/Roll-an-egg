--!strict
-- The Ocean's pets, in the showpiece style (see PetModels/Forest for what that means): sculpted fine in voxels with
-- light baked in from above, crisp angled parts for fins, flippers, teeth, tusks and tentacle tips, and, the rarer
-- they are, more that glows: a pearl and a racing stripe, then glowing eyes and markings, a spiral tusk of light, a
-- fin-maned sea horse, and two Secrets of the deep: the crowned Kraken and the Leviathan with its lure.
-- Swimmers float above the ground (their `hover`); every pet keeps a seat for a rider.
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
local glossyEye = Kit.glossyEye
local andThen = Kit.andThen
local curl = Kit.curl
local mirrorPoints = Kit.mirrorPoints
local alongPath = Kit.alongPath
local vsub = Kit.vsub
local vdot = Kit.vdot
local vlength = Kit.vlength
local fur = Kit.fur

local NEON = Kit.NEON
local GLASS = Kit.GLASS
local EYE = Kit.EYE

local Ocean: { [string]: Design } = {}

-- A flat fin between three points, `thick` through, with a darker rim along its trailing edge (b to c): fins, flukes,
-- flippers. `T` is the design's `inUnits`.
local function fin(limb: Limb, T: any, a: Vec, b: Vec, c: Vec, thick: number, color: { number }, rim: { number }?)
	T.triangle(limb, a, b, c, thick, color)
	if rim then
		T.blade(
			limb,
			vlerp(b, a, 0.06),
			vlerp(c, a, 0.06),
			thick * 1.6,
			thick * 1.15,
			vnorm(Kit.vcross(Kit.vsub(b, a), Kit.vsub(c, a))),
			rim
		)
	end
end

----------------------------------------------------------------------------------------------------------------
-- Sea Turtle (Rare): a great green sea turtle, its shell a pattern of plates with dark seams, crusted with barnacles,
-- trailing seaweed, a starfish clinging to it and an open clam on top holding a glowing pearl.

Ocean.SeaTurtle = {
	name = "Sea Turtle",
	skeleton = "LowSlung",
	scale = 0.3,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local SCUTE = look(104, 150, 74)
		local SCUTE_TOP = look(128, 174, 92)
		local SCUTE_ALT = look(122, 132, 64)
		local SEAM = look(56, 72, 40)
		local MARGIN = look(150, 178, 98)
		local PLASTRON = look(232, 218, 162)
		local PLASTRON_SHADE = look(194, 178, 122)
		local SKIN = look(118, 162, 112)
		local SKIN_TOP = look(146, 188, 136)
		local SKIN_UNDER = look(82, 118, 80)
		local SCALE = look(88, 126, 84)
		local BEAK = rgb(70, 64, 52)
		local BARNACLE = rgb(232, 226, 212)
		local STAR = rgb(255, 128, 84)
		local WEED = rgb(66, 140, 84)
		local WEED_DARK = rgb(44, 102, 62)
		local CLAM = rgb(236, 206, 186)
		local CLAM_DARK = rgb(196, 158, 136)
		local PEARL = rgb(240, 250, 255)

		local tones = {
			[SCUTE] = { top = SCUTE_TOP },
			[PLASTRON] = { under = PLASTRON_SHADE },
			[SKIN] = { top = SKIN_TOP, under = SKIN_UNDER },
		}

		-- The shell's plates: the middle of each, so every cell can find which plate it is in and how near a seam.
		local scutes: { Vec } = {}
		for _, z in { 8, 3.4, -1.2, -5.8, -10 } do
			table.insert(scutes, { 0, 0, z })
		end
		for _, z in { 6, 1, -4, -9 } do
			table.insert(scutes, { 5.4, 0, z })
			table.insert(scutes, { -5.4, 0, z })
		end
		local function shell(p: Vec): Look?
			if p[2] < 6 then
				-- The rim, cut into small plates.
				local a = math.atan2(p[3] + 1, p[1])
				if (a * 9 / math.pi) % 1 < 0.14 then
					return SEAM
				end
				return MARGIN
			end
			local best, second, index = math.huge, math.huge, 1
			for i, c in scutes do
				local d = math.sqrt((p[1] - c[1]) ^ 2 + (p[3] - c[3]) ^ 2)
				if d < best then
					best, second, index = d, best, i
				elseif d < second then
					second = d
				end
			end
			if second - best < 0.75 then
				return SEAM
			end
			return if index % 2 == 0 then SCUTE_ALT else nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 6.4, -1 }, { 8.6, 5.4, 12 }), SCUTE)
		body:add(ellipsoid({ 0, 5.2, -1 }, { 9.4, 1.4, 12.8 }), SCUTE)
		body:carve(ellipsoid({ 0, -0.6, -1 }, { 12, 3.6, 16 }))
		body:add(ellipsoid({ 0, 2.6, -1 }, { 7.4, 2.6, 10.6 }), PLASTRON)
		body:coat(function(p, open)
			if p[2] < 4.6 and not open(0, 1, 0) then
				return PLASTRON
			end
			return shell(p)
		end)
		body:bake(tones)

		-- A blunt head on a thick neck, with a hooked beak.
		local head = newSculpt(U)
		head:add(rod({ { 0, 4.8, 9.6, 2.4 }, { 0, 5.8, 13.4, 2.2 } }), SKIN)
		head:add(ellipsoid({ 0, 6.4, 15 }, { 2.6, 2.4, 3 }), SKIN)
		head:coat(function(p)
			if patches(p, 0.9) < 0.38 then
				return SCALE
			end
			return nil
		end)
		head:bake(tones)

		-- Long front flippers swept back, short rear flippers, patterned with scales.
		local function flipper(s: Sculpt, origin: Vec, radii: Vec, yaw: number)
			s:add(ellipsoid({ 0, 0, 0 }, radii), SKIN, { origin = origin, yaw = yaw, roll = -0.15 })
			s:coat(function(p)
				if patches(p, 0.9) < 0.4 then
					return SCALE
				end
				return nil
			end)
			s:bake(tones)
		end
		local front, back = newSculpt(U), newSculpt(U)
		flipper(front, { 11.6, 3.4, 4.6 }, { 6.6, 0.9, 2.3 }, -0.45)
		flipper(back, { 8.6, 3, -11 }, { 3.6, 0.8, 2.1 }, 0.55)

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 3.8, -12.6, 1.2 }, { 0, 3.2, -14.6, 0.6 } }), SKIN)
		tail:bake(tones)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 4, 0 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, SCUTE)
		-- Barnacles crusted on the shell.
		for _, spot in
			body:surface(function(p, n)
				return p[2] > 6.4 and n[2] > 0.2 and noise(vadd(p, { 2, 9, 4 })) < 0.04 and math.abs(p[3] + 3) > 4
			end)
		do
			local c = vadd(spot[1], vscale(spot[2], 0.3))
			T.ball(bodyLimb, c, { 1, 0.8, 1 }, BARNACLE)
			T.ball(bodyLimb, vadd(c, vscale(spot[2], 0.35)), { 0.45, 0.3, 0.45 }, SEAM.color)
		end
		-- Seaweed trailing from the back of the shell.
		fur(
			bodyLimb,
			T,
			body,
			function(p)
				return p[3] < -9 and p[2] > 4.6 and p[2] < 7 and noise(vadd(p, { 3, 3, 3 })) < 0.35
			end,
			3.4,
			0.9,
			{ 0, -1.6, -0.6 },
			function(p)
				return if noise(p) < 0.5 then WEED else WEED_DARK
			end
		)
		-- A starfish clinging to the side of the shell.
		local star = { sideOf(body, 6.6, -6) + 0.1, 6.6, -6 }
		T.ball(bodyLimb, star, { 0.5, 1, 1 }, STAR)
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			T.taper(bodyLimb, star, vadd(star, { -0.1, math.cos(a) * 2, math.sin(a) * 2 }), 0.9, 0.4, { 1, 0, 0 }, STAR)
		end
		-- An open clam on top of the shell, holding a glowing pearl.
		local top = Kit.topOf(body, 5.6)
		T.ball(bodyLimb, { 0, top + 0.2, 5.6 }, { 4, 1, 3.4 }, CLAM)
		T.ball(bodyLimb, { 0, top + 0.6, 5.6 }, { 2.6, 0.5, 2.2 }, CLAM_DARK)
		T.ball(bodyLimb, { 0, top + 1.4, 5.6 }, { 1.8, 1.8, 1.8 }, PEARL, NEON)
		Kit.blade(bodyLimb, T.at({ 0, top + 0.5, 4.2 }), T.at({ 0, top + 3, 3.4 }), 4, 0.5, { 0, 0.3, 1 }, CLAM)

		local headLimb = pet:limb("Head", T.at({ 0, 5, 9 }))
		head:draw(headLimb, { body }, SCUTE)
		glossyEye(headLimb, T, head, 6.9, 15.6, 1.3)
		T.taper(headLimb, { 0, 6.6, 17.4 }, { 0, 5, 18.4 }, 1.8, 1.6, { 1, 0, 0 }, BEAK)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 6.6, 4, 6 }), function(limb)
			front:draw(limb, { body }, SCUTE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 6.4, 3.6, -9 }), function(limb)
			back:draw(limb, { body }, SCUTE)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 3.8, -12 })), { body }, SCUTE)

		pet:seat(0, Kit.topOf(body, -3), -3)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Dolphin (Rare): a sleek, smiling bottlenose dolphin, dark along the back, pale below, with a glowing aqua stripe
-- sweeping down each flank.

Ocean.Dolphin = {
	name = "Dolphin",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.37,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local GREY = look(116, 150, 190)
		local GREY_TOP = look(140, 172, 210)
		local CAPE = look(70, 98, 140)
		local CAPE_TOP = look(90, 118, 162)
		local BELLY = look(236, 244, 252)
		local BELLY_SHADE = look(196, 210, 228)
		local MOUTH = rgb(60, 80, 110)
		local STRIPE = rgb(90, 250, 236)

		local tones = {
			[GREY] = { top = GREY_TOP, under = BELLY_SHADE },
			[CAPE] = { top = CAPE_TOP },
			[BELLY] = { under = BELLY_SHADE },
		}

		local function shade(p: Vec, open: (number, number, number) -> boolean): Look?
			local y = p[2] - 6 + math.sin(p[3] * 0.35) * 0.4
			if y > 1.6 then
				return CAPE
			elseif y < -1.2 or open(0, -1, 0) then
				return BELLY
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 6, 0.6 }, { 3.6, 3.8, 9 }), GREY)
		body:coat(shade)
		body:bake(tones)

		-- The rounded melon of its head and a short beak.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 6.6, 9.4 }, { 3, 3.2, 3.8 }), GREY)
		head:add(rod({ { 0, 5.4, 12, 1.5 }, { 0, 5.2, 15.6, 0.95 } }), GREY)
		head:coat(function(p, open)
			if p[2] < 5.2 and p[3] > 11 then
				return BELLY
			end
			return shade(p, open)
		end)
		head:bake(tones)

		-- The tail stock tapering back to its flukes.
		local tail = newSculpt(U)
		tail:add(rod({ { 0, 6, -6, 2.9 }, { 0, 6.4, -12, 1.7 }, { 0, 6.6, -16.4, 0.9 } }), GREY)
		tail:coat(shade)
		tail:bake(tones)

		local bodyLimb = pet:limb("Body", T.at({ 0, 6, 0 }))
		body:draw(bodyLimb, { head, tail }, GREY)
		-- A curved dorsal fin.
		fin(bodyLimb, T, { 0, 9.2, 2.4 }, { 0, 13, -2.6 }, { 0, 9, -3 }, 0.8, CAPE.color, CAPE_TOP.color)
		-- The glowing stripe down each flank.
		for _, s in { 1, -1 } do
			local points: { Vec } = {}
			for i = 0, 6 do
				local z = 6 - i * 2.2
				local y = 6.6 - i * 0.3 + math.sin(i * 0.8) * 0.4
				table.insert(points, { (sideOf(body, y, z) + 0.1) * s, y, z })
			end
			for i = 1, #points - 1 do
				T.blade(bodyLimb, points[i], points[i + 1], 0.5, 0.3, { s, 0, 0 }, STRIPE, NEON)
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 6, 6.4 }))
		head:draw(headLimb, { body }, GREY)
		glossyEye(headLimb, T, head, 6.9, 11, 1.2)
		-- Its smile.
		for _, s in { 1, -1 } do
			local x = sideOf(head, 5.2, 12.6)
			T.blade(
				headLimb,
				{ (x - 0.05) * s, 5.1, 14.6 },
				{ (x + 0.05) * s, 5.5, 11.2 },
				0.25,
				0.25,
				{ s, 0, 0 },
				MOUTH
			)
		end

		pet:limbPair("LeftFin", "RightFin", T.at({ 3, 4.6, 4.6 }), function(limb)
			fin(limb, T, { 2.6, 4.6, 5.6 }, { 6.6, 2.4, 1.6 }, { 2.8, 4, 3 }, 0.6, GREY.color, CAPE.color)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 6, -5.6 }))
		tail:draw(tailLimb, { body }, GREY)
		-- Broad flukes.
		for _, s in { 1, -1 } do
			fin(
				tailLimb,
				T,
				{ 0.4 * s, 6.6, -15.6 },
				{ 5.6 * s, 6.8, -19 },
				{ 0.4 * s, 6.6, -18.4 },
				0.7,
				CAPE.color,
				CAPE_TOP.color
			)
		end

		pet:seat(0, 9.6, 3.4)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Manta Ray (Epic): a giant manta, its great wings spanning nearly four times a player's height, midnight blue
-- spotted with white above and pale below, with glowing lines along the leading edges of its wings and glowing dots
-- across them, curled horn fins, glowing eyes and a long whip of a tail.

Ocean.MantaRay = {
	name = "Manta Ray",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 4,
	scale = 0.4,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local NAVY = look(32, 46, 92)
		local NAVY_TOP = look(48, 66, 120)
		local BELLY = look(232, 240, 250)
		local BELLY_SHADE = look(190, 200, 222)
		local SPOT = rgb(214, 228, 246)
		local GLOW = rgb(90, 220, 255)
		local DARK = rgb(18, 26, 52)

		local tones = {
			[NAVY] = { top = NAVY_TOP, under = BELLY_SHADE },
			[BELLY] = { under = BELLY_SHADE },
		}

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 4.4, 0 }, { 6.6, 2.6, 8.6 }), NAVY)
		body:coat(function(p, open)
			if open(0, -1, 0) or p[2] < 3.6 then
				return BELLY
			end
			return nil
		end)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 4.2, 8.2 }, { 5, 2, 2.6 }), NAVY)
		for _, s in { 1, -1 } do
			head:add(
				rod(Kit.andThen(
					{ { 4.2 * s, 4.2, 8.6, 1.1 }, { 4.8 * s, 3.8, 11.4, 0.9 } },
					Kit.curl({
						centre = { 3.6 * s, 3.4, 11.4 },
						plane = { 1, 3 },
						from = if s > 0 then 0 else math.pi,
						turns = 0.45 * s,
						radius = { 1.2, 0.8 },
						width = { 0.9, 0.5 },
					})
				)),
				NAVY
			)
		end
		head:coat(function(_, open)
			if open(0, -1, 0) then
				return BELLY
			end
			return nil
		end)
		head:bake(tones)

		local bodyLimb = pet:limb("Body", T.at({ 0, 4.4, 0 }))
		body:draw(bodyLimb, { head }, NAVY)
		for _, spot in
			body:surface(function(p, n)
				return n[2] > 0.5 and noise(vadd(p, { 5, 5, 1 })) < 0.08
			end)
		do
			T.ball(bodyLimb, vadd(spot[1], vscale(spot[2], 0.35)), { 0.9, 0.3, 0.9 }, SPOT)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 4.2, 6.6 }))
		head:draw(headLimb, { body }, NAVY)
		for _, s in { 1, -1 } do
			local x = sideOf(head, 4.4, 9.4)
			T.ball(headLimb, { (x - 0.1) * s, 4.4, 9.4 }, { 0.7, 0.9, 1.1 }, GLOW, NEON)
		end
		T.blade(headLimb, { -2.6, 3.2, 10.6 }, { 2.6, 3.2, 10.6 }, 0.6, 0.6, { 0, 0, 1 }, DARK)

		-- The wings: a sheet dark above and pale below, a thick leading edge glowing along its front, glowing dots.
		pet:limbPair("LeftFin", "RightFin", T.at({ 5.4, 4.4, 0 }), function(limb)
			local root, tip, rear = { 5, 4.4, 6.2 }, { 27, 5.6, -3.6 }, { 5, 4.4, -7.6 }
			local mid = { 12, 4.6, -6.4 }
			T.triangle(
				limb,
				vadd(root, { 0, 0.4, 0 }),
				vadd(tip, { 0, 0.3, 0 }),
				vadd(mid, { 0, 0.4, 0 }),
				0.7,
				NAVY.color
			)
			T.triangle(
				limb,
				vadd(root, { 0, 0.4, 0 }),
				vadd(mid, { 0, 0.4, 0 }),
				vadd(rear, { 0, 0.4, 0 }),
				0.7,
				NAVY.color
			)
			T.triangle(
				limb,
				vadd(root, { 0, -0.3, 0 }),
				vadd(tip, { 0, -0.2, 0 }),
				vadd(mid, { 0, -0.3, 0 }),
				0.6,
				BELLY.color
			)
			T.triangle(
				limb,
				vadd(root, { 0, -0.3, 0 }),
				vadd(mid, { 0, -0.3, 0 }),
				vadd(rear, { 0, -0.3, 0 }),
				0.6,
				BELLY.color
			)
			T.blade(limb, root, vlerp(root, tip, 0.55), 1.6, 1.4, { 0, 1, 0 }, NAVY_TOP.color)
			T.taper(limb, vlerp(root, tip, 0.55), tip, 1.4, 1.1, { 0, 1, 0 }, NAVY_TOP.color)
			T.blade(
				limb,
				vadd(root, { 0.6, 0.8, -0.3 }),
				vadd(vlerp(root, tip, 0.9), { 0, 0.7, -0.3 }),
				0.4,
				0.3,
				{ 0, 1, 0 },
				GLOW,
				NEON
			)
			for i, t in { { 0.25, 0.35 }, { 0.45, 0.25 }, { 0.6, 0.45 }, { 0.35, 0.6 }, { 0.75, 0.3 }, { 0.5, 0.65 } } do
				local p = vadd(vlerp(root, vlerp(tip, rear, t[2]), t[1]), { 0, 0.85, 0 })
				T.ball(limb, p, { 0.8, 0.3, 0.8 }, if i % 2 == 0 then GLOW else SPOT, if i % 2 == 0 then NEON else nil)
			end
		end)

		-- A long whip of a tail.
		local tailLimb = pet:limb("Tail", T.at({ 0, 4.2, -8 }))
		T.blade(tailLimb, { 0, 4.2, -7.6 }, { 0, 4, -15 }, 0.9, 0.8, { 0, 1, 0 }, NAVY.color)
		T.blade(tailLimb, { 0, 4, -15 }, { 0, 3.8, -22 }, 0.6, 0.6, { 0, 1, 0 }, NAVY.color)
		T.taper(tailLimb, { 0, 3.8, -22 }, { 0, 3.6, -28 }, 0.5, 0.5, { 0, 1, 0 }, NAVY.color)
		fin(tailLimb, T, { 0, 4.6, -8.4 }, { 0, 6.6, -10.4 }, { 0, 4.6, -11.4 }, 0.4, NAVY.color)

		pet:seat(0, 7, -1)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Great Shark (Epic): a great white, longer than a bus is tall, grey above and stark white below, jaws open on rows
-- of teeth, gill slits, old scars, a towering dorsal fin and glowing red eyes.

Ocean.GreatShark = {
	name = "Great Shark",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.36 * 1.2,
	draw = function(pet)
		-- Built in cells 1.2 design units across.
		local U = 1.2
		local T = inUnits(U)
		local GREY = look(104, 120, 142)
		local GREY_TOP = look(128, 144, 166)
		local GREY_DARK = look(76, 88, 108)
		local WHITE = look(238, 242, 248)
		local WHITE_SHADE = look(196, 202, 214)
		local MOUTH = look(110, 28, 44)
		local GUM = look(214, 110, 128)
		local TOOTH = rgb(252, 252, 244)
		local SCAR = rgb(180, 190, 204)
		local RED = rgb(255, 50, 60)

		local tones = {
			[GREY] = { top = GREY_TOP, under = GREY_DARK },
			[WHITE] = { under = WHITE_SHADE },
		}
		-- Countershading: grey above a ragged line, white below.
		local function shade(p: Vec, open: (number, number, number) -> boolean): Look?
			local line = 5 + math.sin(p[3] * 0.45) * 0.6 + math.sin(p[3] * 1.3) * 0.25
			if p[2] < line or open(0, -1, 0) then
				return WHITE
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 6, 0 }, { 5, 5.4, 11 }), GREY)
		body:coat(shade)
		body:bake(tones)

		-- The head: a conical snout over open jaws lined with teeth.
		local head = newSculpt(U)
		head:add(rod({ { 0, 6.2, 8, 4.8 }, { 0, 6.8, 14, 3.2 }, { 0, 6.8, 18.4, 1.6 } }), GREY)
		head:add(rod({ { 0, 3.4, 9, 3.4 }, { 0, 2.8, 14.2, 2 } }), WHITE)
		head:carve(ellipsoid({ 0, 4.4, 15.4 }, { 3.2, 1.6, 4.4 }))
		head:coat(function(p, open)
			if p[3] > 11 and p[2] > 3.2 and p[2] < 5.6 and math.abs(p[1]) < 3.2 then
				-- Dark inside the open mouth, pink gums at its edges.
				if math.abs(p[1]) < 2.4 and p[2] > 3.8 and p[2] < 5 then
					return MOUTH
				end
				return GUM
			end
			return shade(p, open)
		end)
		head:bake(tones)

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 6.2, -9, 3.8 }, { 0, 6.6, -15, 2.2 }, { 0, 7, -19.6, 1.2 } }), GREY)
		tail:coat(shade)
		tail:bake(tones)

		local bodyLimb = pet:limb("Body", T.at({ 0, 6, 0 }))
		body:draw(bodyLimb, { head, tail }, GREY)
		-- The towering dorsal fin, and gill slits on each side.
		fin(bodyLimb, T, { 0, 10.6, 4 }, { 0, 17.4, -2.6 }, { 0, 10.2, -3 }, 1, GREY.color, GREY_DARK.color)
		for _, s in { 1, -1 } do
			for i = 0, 4 do
				local z = 8.4 - i * 1.1
				local x = sideOf(body, 6.2, z) + 0.05
				T.blade(
					bodyLimb,
					{ x * s, 4.4, z + 0.3 },
					{ x * s, 8, z - 0.2 },
					0.3,
					0.3,
					{ s, 0, 0 },
					GREY_DARK.color
				)
			end
			-- Old scars raked across its flank.
			for i = 0, 2 do
				local z = -1 - i * 1.2
				local x = sideOf(body, 8, z) + 0.05
				T.blade(bodyLimb, { x * s, 9, z + 1 }, { x * s, 6.6, z - 1 }, 0.25, 0.2, { s, 0, 0 }, SCAR)
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 6, 7 }))
		head:draw(headLimb, { body }, GREY)
		-- Glowing red eyes, black-rimmed.
		for _, s in { 1, -1 } do
			local x = sideOf(head, 7.6, 13.4)
			T.ball(headLimb, { (x - 0.2) * s, 7.6, 13.4 }, { 0.8, 1.3, 1.3 }, EYE)
			T.ball(headLimb, { (x - 0.05) * s, 7.6, 13.5 }, { 0.6, 0.8, 0.8 }, RED, NEON)
		end
		-- Rows of teeth along the edges of the open jaws, top and bottom.
		for i = 0, 5 do
			for _, s in { 1, -1 } do
				local zu = 17 - i * 0.95
				local xu = sideOf(head, 6.2, zu) - 0.45
				if xu > 0.4 then
					T.taper(headLimb, { xu * s, 6.4, zu }, { xu * s, 4.9, zu + 0.2 }, 0.7, 0.4, { s, 0, 0 }, TOOTH)
				end
				local zl = 15.4 - i * 0.8
				local xl = sideOf(head, 2.6, zl) - 0.45
				if xl > 0.4 then
					T.taper(headLimb, { xl * s, 2.4, zl }, { xl * s, 3.7, zl + 0.2 }, 0.6, 0.4, { s, 0, 0 }, TOOTH)
				end
			end
		end

		pet:limbPair("LeftFin", "RightFin", T.at({ 4, 3.6, 4 }), function(limb)
			fin(limb, T, { 3.6, 3.8, 6 }, { 11.4, 0.6, -0.6 }, { 3.8, 3.4, 1.6 }, 0.8, GREY.color, GREY_DARK.color)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 6.2, -8.6 }))
		tail:draw(tailLimb, { body }, GREY)
		-- A crescent tail fin, taller above, and small fins before it.
		fin(tailLimb, T, { 0, 7.2, -18.6 }, { 0, 14.4, -23.6 }, { 0, 7.4, -21 }, 0.9, GREY.color, GREY_DARK.color)
		fin(tailLimb, T, { 0, 6.6, -18.6 }, { 0, 1.4, -22.4 }, { 0, 6.6, -20.6 }, 0.9, GREY.color, GREY_DARK.color)
		fin(tailLimb, T, { 0, 8.4, -13.6 }, { 0, 10.6, -15.6 }, { 0, 8.2, -15.6 }, 0.6, GREY.color)

		pet:seat(0, 11.2 / U, -4.6 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Narwhal (Legendary): a mottled narwhal three times a player's length, its long spiral tusk wound with glowing light
-- from root to tip, glowing eyes, bubbles rising round it and an icy aura.

Ocean.Narwhal = {
	name = "Narwhal",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.46,
	draw = function(pet)
		local U = 1
		local T = inUnits(U)
		local SLATE = look(126, 146, 178)
		local SLATE_TOP = look(150, 168, 198)
		local SLATE_UNDER = look(92, 108, 140)
		local DARK = look(70, 86, 122)
		local BELLY = look(236, 242, 250)
		local BELLY_SHADE = look(194, 204, 224)
		local IVORY = rgb(250, 242, 220)
		local IVORY_DARK = rgb(214, 196, 158)
		local GLOW = rgb(200, 250, 255)
		local ICE = rgb(150, 230, 255)

		local tones = {
			[SLATE] = { top = SLATE_TOP, under = SLATE_UNDER },
			[BELLY] = { under = BELLY_SHADE },
		}
		-- Darker and more mottled along the back, pale on the belly.
		local function shade(p: Vec, open: (number, number, number) -> boolean): Look?
			if p[2] < 4.4 or open(0, -1, 0) then
				return BELLY
			end
			if patches(p, 1.2) < 0.36 + (p[2] - 6) * 0.06 then
				return DARK
			end
			return nil
		end

		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 6, 0 }, { 4.6, 4.8, 10.4 }), SLATE)
		body:coat(shade)
		body:bake(tones)

		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 6.4, 9.6 }, { 4, 4, 4.4 }), SLATE)
		head:coat(shade)
		head:bake(tones)

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 6, -8, 3.6 }, { 0, 6.4, -15, 1.9 }, { 0, 6.6, -19, 0.9 } }), SLATE)
		tail:coat(shade)
		tail:bake(tones)

		local bodyLimb = pet:limb("Body", T.at({ 0, 6, 0 }))
		body:draw(bodyLimb, { head, tail }, SLATE)
		-- A low ridge along its back instead of a fin.
		for i = 0, 3 do
			local z = -1 - i * 2.4
			local y = Kit.topOf(body, z)
			T.taper(bodyLimb, { 0, y - 0.4, z + 0.8 }, { 0, y + 0.8, z - 0.6 }, 1, 0.8, { 1, 0, 0 }, DARK.color)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 6.2, 7 }))
		head:draw(headLimb, { body }, SLATE)
		for _, s in { 1, -1 } do
			local x = sideOf(head, 6.6, 11.6)
			T.ball(headLimb, { (x - 0.2) * s, 6.6, 11.6 }, { 0.6, 1, 1 }, EYE)
			T.ball(headLimb, { (x - 0.05) * s, 6.7, 11.7 }, { 0.4, 0.6, 0.6 }, ICE, NEON)
		end
		-- The tusk: a long spiral shaft from the left of its lip, wound with a glowing band to the tip.
		local root = { 0.9, 6.8, frontOf(head, 0.9, 6.8) - 0.6 }
		local tip = vadd(root, { 0.4, 1.6, 20 })
		local steps = 10
		for i = 0, steps - 1 do
			local a, b = vlerp(root, tip, i / steps), vlerp(root, tip, (i + 1) / steps)
			local w = 1.5 * (1 - i / steps) + 0.25
			if i == steps - 1 then
				T.taper(headLimb, a, b, w, w, { 0, 1, 0 }, IVORY)
			else
				T.blade(headLimb, a, b, w, w, { 0, 1, 0 }, if i % 2 == 0 then IVORY else IVORY_DARK)
			end
		end
		local turns = 7
		local prev: Vec? = nil
		for i = 0, 56 do
			local t = i / 56
			local a = t * turns * math.pi * 2
			local r = (1.5 * (1 - t) + 0.25) * 0.55
			local c = vlerp(root, tip, t * 0.96)
			local p = vadd(c, { math.cos(a) * r, math.sin(a) * r, 0 })
			if prev then
				T.blade(headLimb, prev, p, 0.3, 0.3, { 0, 0, 1 }, GLOW, NEON)
			end
			prev = p
		end

		pet:limbPair("LeftFin", "RightFin", T.at({ 4, 4.2, 5 }), function(limb)
			fin(limb, T, { 3.6, 4.4, 6.4 }, { 7.6, 2.6, 2.4 }, { 3.8, 3.8, 3.4 }, 0.6, SLATE.color, DARK.color)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 6, -7.6 }))
		tail:draw(tailLimb, { body }, SLATE)
		for _, s in { 1, -1 } do
			fin(
				tailLimb,
				T,
				{ 0.4 * s, 6.6, -18.4 },
				{ 6.4 * s, 6.8, -21.4 },
				{ 0.4 * s, 6.6, -21.6 },
				0.7,
				DARK.color,
				SLATE_UNDER.color
			)
		end

		pet:light(GLOW, 2, 22)
		pet:particles("Bubbles", rgb(220, 246, 255), 8)
		pet:aura(rgb(130, 220, 255), rgb(240, 252, 255))
		pet:seat(0, 10.6, 0)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Hippocampus (Mythic): the sea horse of legend, four times a player's height, a horse in front and a great fish
-- behind: teal scales studded with glowing spots, a glowing fin for a mane, finned hooves, a tail ending in a glowing
-- fan, a crest of coral, a bridle of pearls and gold, bubbles and an aqua aura.

Ocean.Hippocampus = {
	name = "Hippocampus",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.46 * 1.3,
	draw = function(pet)
		-- Built in cells 1.3 design units across.
		local U = 1.3
		local T = inUnits(U)
		local TEAL = look(36, 168, 166)
		local TEAL_TOP = look(70, 200, 192)
		local TEAL_UNDER = look(20, 112, 120)
		local SCALE = look(26, 140, 146)
		local BELLY = look(186, 240, 226)
		local BELLY_SHADE = look(130, 200, 192)
		local DOT = look(90, 255, 230, NEON)
		local NOSE = rgb(20, 70, 80)
		local FIN = rgb(90, 230, 220)
		local GLOW = rgb(110, 255, 236)
		local CORAL = rgb(255, 120, 140)
		local CORAL_TIP = rgb(255, 196, 196)
		local PEARL = rgb(250, 246, 240)
		local GOLD = rgb(255, 200, 70)

		local tones = {
			[TEAL] = { top = TEAL_TOP, under = TEAL_UNDER },
			[SCALE] = { top = TEAL, under = TEAL_UNDER },
			[BELLY] = { under = BELLY_SHADE },
		}
		-- Scales in rows, a pale belly, and lines of glowing spots along the flanks.
		local function scales(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, -1, 0) and p[2] < 12 then
				return BELLY
			end
			if math.abs(p[1]) > 2.6 and (p[3] * 0.9 + p[2]) % 2.6 < 0.5 and math.abs((p[2] - 13) % 3 - 1.5) < 0.35 then
				return DOT
			end
			if (math.floor(p[3] / 1.4) + math.floor(p[2] / 1.4)) % 2 == 0 then
				return SCALE
			end
			return nil
		end

		-- A horse's chest and barrel.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 13, 4 }, { 4.4, 5.2, 4.8 }), TEAL)
		body:add(ellipsoid({ 0, 13.4, -2 }, { 4.2, 4.6, 6 }), TEAL)
		body:add(rod({ { 0, 15.6, 6.6, 3.4 }, { 0, 20, 9.6, 2.6 } }), TEAL)
		body:coat(scales)
		body:bake(tones)

		-- A horse's head with a long face.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 22, 11.4 }, { 2.4, 2.6, 3.2 }), TEAL)
		head:add(rod({ { 0, 21.4, 12.8, 2 }, { 0, 20.2, 16.4, 1.5 } }), TEAL)
		head:coat(function(p, open)
			if p[3] > 15 and p[2] < 20.8 then
				return BELLY
			end
			return scales(p, open)
		end)
		head:bake(tones)

		-- The fish half: a long tail curving down, back and up into a fan.
		local spine =
			{ { 0, 13, -7, 3.8 }, { 0, 10.4, -12, 3.2 }, { 0, 8.6, -17, 2.6 }, { 0, 9, -22, 1.9 }, { 0, 12, -26, 1.2 } }
		local tail = newSculpt(U)
		tail:add(rod(spine), TEAL)
		tail:coat(scales)
		tail:bake(tones)

		-- Forelegs ending in webbed fins instead of hooves.
		local leg = newSculpt(U)
		leg:add(rod({ { 2.8, 11.6, 5.4, 1.5 }, { 3, 7, 7.2, 1.1 }, { 3, 4.6, 8.6, 1 } }), TEAL)
		leg:coat(scales)
		leg:bake(tones)

		local legMirror = leg:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 13, 0 }))
		body:draw(bodyLimb, { head, tail, leg, legMirror }, TEAL)
		-- A glowing fin for a mane, from the top of its head down to its withers, ribbed with rays.
		local mane = {}
		for i = 0, 7 do
			local t = i / 7
			local base = vlerp({ 0, 22.6, 9.6 }, { 0, 16.6, 2.6 }, t)
			base[2] = Kit.topOf(body, base[3]) - 0.4
			table.insert(mane, base)
		end
		for i = 1, #mane - 1 do
			local a, b = mane[i], mane[i + 1]
			local h = 4 - i * 0.3
			T.triangle(bodyLimb, a, vadd(a, { 0, h, -1.6 }), b, 0.35, FIN, GLASS)
			T.blade(bodyLimb, a, vadd(a, { 0, h, -1.6 }), 0.35, 0.4, { 1, 0, 0 }, GLOW, NEON)
		end

		local headLimb = pet:limb("Head", T.at({ 0, 20, 9.6 }))
		head:draw(headLimb, { body }, TEAL)
		Kit.slitEyes(headLimb, head, { 22.8, 13.4 }, { 23.1, 11.6 }, 0.8, GLOW, NEON, NOSE)
		for _, s in { 1, -1 } do
			-- Fin ears.
			fin(headLimb, T, { 1.4 * s, 24.2, 10.6 }, { 3.6 * s, 27.2, 9.4 }, { 1.4 * s, 23.6, 8.8 }, 0.35, FIN, GLOW)
			-- A bridle of pearls with a gold boss at the cheek.
			local x = sideOf(head, 21.4, 13.6)
			T.ball(headLimb, { (x + 0.1) * s, 21.4, 13.6 }, { 0.8, 1.2, 1.2 }, GOLD)
			for k = 0, 3 do
				T.ball(
					headLimb,
					{ (sideOf(head, 21.2 + k * 0.5, 14.4 + k * 0.4) - 0.05) * s, 21.2 + k * 0.5, 14.4 + k * 0.4 },
					{ 0.6, 0.6, 0.6 },
					PEARL
				)
			end
			-- A crest of coral branching up from its brow.
			T.branch(
				headLimb,
				{ { 0.8 * s, 24, 11.6 }, { 2 * s, 26.6, 12 }, { 2.6 * s, 29, 11 } },
				0.9,
				{ 0, 0, 1 },
				CORAL
			)
			T.taper(headLimb, { 2 * s, 26.6, 12 }, { 3.6 * s, 27.4, 13.4 }, 0.6, 0.6, { 0, 1, 0 }, CORAL_TIP)
		end
		T.ball(headLimb, { 0, 20.6, 16.9 }, { 1.6, 1, 0.8 }, NOSE)

		pet:limbPair("LeftFin", "RightFin", T.at({ 2.8, 11.6, 5.4 }), function(limb)
			leg:draw(limb, { body }, TEAL)
			-- A webbed fin where a hoof would be.
			fin(limb, T, { 3, 4.6, 8.6 }, { 4.6, 1.05, 11.6 }, { 1.4, 1.05, 11.2 }, 0.4, FIN, GLOW)
			T.blade(limb, { 3, 4.6, 8.6 }, { 4.6, 1.05, 11.6 }, 0.3, 0.3, { 0, 0, 1 }, GLOW, NEON)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 13, -6.4 }))
		tail:draw(tailLimb, { body }, TEAL)
		-- A dorsal fin along the tail and a great glowing fan at its end.
		fin(tailLimb, T, { 0, 15.6, -9 }, { 0, 17.6, -14 }, { 0, 12.4, -15 }, 0.4, FIN, GLOW)
		local fanRoot = { 0, 12.4, -26.4 }
		local fan = { { 0, 20, -27.4 }, { 0, 18, -31.6 }, { 0, 13.4, -33.4 }, { 0, 9, -31.4 } }
		for k, ray in fan do
			T.blade(tailLimb, fanRoot, ray, 0.4, 0.5, { 1, 0, 0 }, GLOW, NEON)
			if k < #fan then
				T.triangle(tailLimb, fanRoot, ray, fan[k + 1], 0.35, FIN, GLASS)
			end
		end

		pet:light(GLOW, 2.6, 26)
		pet:particles("Bubbles", rgb(226, 250, 246), 12)
		pet:aura(rgb(60, 240, 210), rgb(220, 255, 250))
		pet:seat(0, 18.2 / U, -1.6 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Kraken (Secret): a colossal crowned octopus, over six times a player's height, rearing its mantle over eight thick
-- tentacles curled at glowing tips, glowing suckers among the pale ones, rows of glowing spots, huge glowing eyes, a
-- gold crown set crooked on its head, and a ship's wheel torn from a wreck held up high.

Ocean.Kraken = {
	name = "Kraken",
	skeleton = "Tentacled",
	gait = "Crawl",
	scale = 0.95 * 1.3,
	draw = function(pet)
		-- Built in cells 1.3 design units across, with eyes, beak, crown, suckers, barnacles, its ship's wheel and
		-- its anchor of parts at any angle.
		local U = 1.3
		local T = inUnits(U)
		local PURPLE = look(104, 42, 134)
		local PURPLE_TOP = look(132, 64, 164)
		local PURPLE_DARK = look(64, 22, 90)
		local PURPLE_LIGHT = look(124, 58, 156)
		local UNDER = look(196, 126, 206)
		local UNDER_SHADE = look(150, 86, 164)
		local tones = {
			[PURPLE] = { top = PURPLE_TOP, under = PURPLE_DARK },
			[PURPLE_LIGHT] = { under = PURPLE },
			[UNDER] = { under = UNDER_SHADE },
		}
		local GLOW = look(255, 110, 220, NEON)
		local SUCKER = rgb(255, 190, 226)
		local EYE_GLOW = rgb(255, 214, 60)
		local PUPIL = rgb(24, 8, 24)
		local BEAK = rgb(40, 28, 40)
		local GOLD = rgb(255, 196, 56)
		local GOLD_DARK = rgb(206, 140, 30)
		local RUBY = rgb(220, 30, 80)
		local EMERALD = rgb(40, 200, 120)
		local PEARL = rgb(250, 246, 240)
		local BARNACLE = rgb(226, 220, 206)
		local BARNACLE_DARK = rgb(120, 110, 100)
		local WOOD = rgb(132, 86, 50)
		local WOOD_DARK = rgb(96, 60, 36)
		local IRON = rgb(70, 74, 86)

		-- Mottled light and dark in big soft patches.
		local function skin(p: Vec): Look?
			local n = patches(p, 3.4)
			if n < 0.32 then
				return PURPLE_LIGHT
			elseif n > 0.82 then
				return PURPLE_DARK
			end
			return nil
		end

		-- The squat body the tentacles grow from, paler underneath.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 5.4, 0 }, { 7, 3.9, 7 }), PURPLE)
		body:coat(function(p, open)
			return if open(0, -1, 0) then UNDER else skin(p)
		end)
		body:bake(tones)

		-- A huge rounded mantle swelling up and leaning back, with raised sockets for its eyes under heavy
		-- scowling brows, and rows of glowing spots down its sides.
		local mantle = {
			{ 0, 9.4, -0.8, 6.4 },
			{ 0, 15.5, -2.6, 8.3 },
			{ 0, 21, -4.3, 7.4 },
			{ 0, 25.6, -5.6, 5.2 },
			{ 0, 28.2, -6.3, 2.4 },
		}
		local function ring(y: number): (number, number)
			for index = 1, #mantle - 1 do
				local a, b = mantle[index], mantle[index + 1]
				if y <= b[2] or index == #mantle - 1 then
					local t = math.clamp((y - a[2]) / (b[2] - a[2]), 0, 1)
					return a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
				end
			end
			return 0, 0
		end
		local function onMantle(y: number, angle: number, out: number?): Vec
			local zc, r = ring(y)
			local a = math.rad(angle)
			return { math.sin(a) * (r + (out or 0)), y, zc + math.cos(a) * (r + (out or 0)) }
		end
		local spots = {}
		for y = 12, 26, 2 do
			for _, side in { 1, -1 } do
				table.insert(spots, onMantle(y, side * (88 + (y - 12) * 3)))
			end
		end
		local head = newSculpt(U)
		head:add(rod(mantle), PURPLE)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 5 * s, 11.8, 4.2 }, { 2.7, 3.1, 2.4 }), PURPLE)
			head:add(
				rod({ { 2 * s, 15.6, 5.8, 1.1 }, { 5.4 * s, 16.6, 5.6, 1.25 }, { 7.6 * s, 15.6, 3.4, 0.9 } }),
				PURPLE_DARK
			)
		end
		head:coat(function(p, open)
			-- Glowing veins winding up the mantle.
			local zc = ring(p[2])
			local angle = math.atan2(p[1], p[3] - zc)
			if p[2] > 13 and p[2] < 27 and math.abs(angle) < 2.2 then
				if math.abs(math.sin(angle * 4 + p[2] * 0.22 + math.sin(p[2] * 0.5) * 0.6)) < 0.09 then
					return GLOW
				end
			end
			for _, spot in spots do
				local dx, dy, dz = p[1] - spot[1], p[2] - spot[2], p[3] - spot[3]
				if dx * dx + dy * dy + dz * dz < 0.95 then
					return GLOW
				end
			end
			if open(0, -1, 0) then
				return UNDER
			end
			return skin(p)
		end)
		head:bake(tones)

		-- Eight thick tentacles, each ending in a glowing curl: two arms raised in front (one brandishing a ship's
		-- wheel), two sprawled out to the sides, two trailing behind, and two rearing up over its back.
		local back = andThen(
			{ { 4, 4, -4, 2.97 }, { 7, 2.2, -7, 2.56 }, { 10, 1.6, -10, 2.03 }, { 12, 1.2, -13, 1.49 } },
			curl({
				centre = { 12, 3.6, -13 },
				plane = { 3, 2 },
				from = -math.pi / 2,
				turns = -0.8,
				radius = { 2.4, 1.1 },
				width = { 1.49, 0.68 },
			})
		)
		local tentacles = {
			{
				"Tentacle1",
				andThen(
					{
						{ 3, 5, 4, 3.24 },
						{ 6, 4, 7.5, 2.97 },
						{ 9, 5, 9, 2.56 },
						{ 11.5, 8.5, 9.5, 2.16 },
						{ 12.5, 12.5, 9, 1.89 },
						{ 12.5, 16.5, 8.5, 1.62 },
					},
					curl({
						centre = { 15.5, 16.5, 8.5 },
						plane = { 1, 2 },
						from = math.pi,
						turns = -0.8,
						radius = { 3, 1.2 },
						width = { 1.62, 0.68 },
					})
				),
			},
			{
				"Tentacle2",
				{
					{ -4, 5, 4, 3.24 },
					{ -7, 4, 7.5, 2.97 },
					{ -10, 5.5, 9, 2.56 },
					{ -12, 9, 9.5, 2.03 },
					{ -13, 12.5, 9.5, 1.69 },
					{ -14, 15, 9.5, 1.35 },
					{ -15.5, 16.5, 9.5, 1.08 },
					{ -16.5, 15.5, 9.5, 0.81 },
					{ -16, 14, 9.5, 0.68 },
				},
			},
			{
				"Tentacle3",
				andThen(
					{ { 5, 4, 0, 3.1 }, { 9, 2.2, 1, 2.7 }, { 13, 1.8, 1.5, 2.16 }, { 16.5, 1.3, 1.5, 1.62 } },
					curl({
						centre = { 16.5, 4, 1.5 },
						plane = { 1, 2 },
						from = -math.pi / 2,
						turns = 0.8,
						radius = { 2.7, 1.2 },
						width = { 1.62, 0.68 },
					})
				),
			},
			{
				"Tentacle4",
				andThen(
					{ { -6, 4, 0, 3.1 }, { -10, 2.2, 0, 2.7 }, { -14, 1.8, -0.5, 2.16 }, { -17.5, 1.3, -1, 1.62 } },
					curl({
						centre = { -17.5, 3.8, -1 },
						plane = { 1, 2 },
						from = -math.pi / 2,
						turns = -0.85,
						radius = { 2.5, 1.1 },
						width = { 1.62, 0.68 },
					})
				),
			},
			{ "Tentacle5", back },
			{ "Tentacle6", mirrorPoints(back) },
			{
				"Tentacle7",
				andThen(
					{
						{ 3, 5, -6, 2.97 },
						{ 5, 6, -10, 2.56 },
						{ 8, 9, -12, 2.29 },
						{ 10, 14, -12, 2.03 },
						{ 11, 19, -11, 1.76 },
						{ 11, 24, -10, 1.49 },
					},
					curl({
						centre = { 14, 24, -10 },
						plane = { 1, 2 },
						from = math.pi,
						turns = -0.75,
						radius = { 3, 1.2 },
						width = { 1.49, 0.68 },
					})
				),
			},
			{
				"Tentacle8",
				andThen(
					{
						{ -4, 5, -6, 2.97 },
						{ -6, 6, -10, 2.56 },
						{ -9, 10, -12, 2.29 },
						{ -11, 15, -12, 2.03 },
						{ -12, 20, -11, 1.76 },
						{ -12, 25, -10, 1.49 },
					},
					curl({
						centre = { -12, 25, -13 },
						plane = { 3, 2 },
						from = 0,
						turns = 0.75,
						radius = { 3, 1.2 },
						width = { 1.49, 0.68 },
					})
				),
			},
		}
		local sculpts = { body, head }
		for _, tentacle in tentacles do
			local route = tentacle[2]
			local s = newSculpt(U)
			s:add(rod(route), PURPLE)
			s:add(rod({ route[#route - 2], route[#route - 1], route[#route] }), GLOW)
			s:coat(function(p, open)
				if open(0, -1, 0) then
					return UNDER
				end
				return skin(p)
			end)
			s:bake(tones)
			tentacle[3] = s
			table.insert(sculpts, s)
		end
		local function othersOf(s: Sculpt): { Sculpt }
			local list = {}
			for _, other in sculpts do
				if other ~= s then
					table.insert(list, other)
				end
			end
			return list
		end

		body:draw(pet:limb("Body", T.at({ 0, 5, 0 })), othersOf(body), PURPLE)
		local headLimb = pet:limb("Head", T.at({ 0, 9, 0 }))
		head:draw(headLimb, othersOf(head), PURPLE)
		-- Huge glowing eyes in the sockets, slit-pupilled and dark-rimmed, and a hooked beak below.
		for _, s in { 1, -1 } do
			local face = frontOf(head, 5 * s, 11.8)
			T.ball(headLimb, { 5 * s, 11.8, face - 0.9 }, { 4.4, 5.2, 1.8 }, PURPLE_DARK.color)
			T.ball(headLimb, { 5 * s, 11.8, face - 0.55 }, { 3.6, 4.4, 1.6 }, EYE_GLOW, NEON)
			T.blade(headLimb, { 5 * s, 10.4, face + 0.12 }, { 5 * s, 13.2, face + 0.12 }, 0.6, 0.3, { 0, 0, 1 }, PUPIL)
			T.ball(headLimb, { 4.3 * s, 13, face + 0.1 }, { 0.7, 0.7, 0.3 }, Kit.SHINE)
		end
		local chin = frontOf(head, 0, 9.6)
		T.blade(headLimb, { 0, 10.2, chin - 0.8 }, { 0, 9.2, chin + 0.6 }, 1.6, 1.4, { 1, 0, 0 }, BEAK)
		T.taper(headLimb, { 0, 9.2, chin + 0.6 }, { 0, 7.6, chin + 0.9 }, 1.4, 1.2, { 1, 0, 0 }, BEAK)
		-- Barnacles crusted on its back.
		for _, barnacle in
			{
				{ 16, 170, 1.3 },
				{ 17.4, 158, 1 },
				{ 13, -150, 1.2 },
				{ 14.6, -160, 0.9 },
				{ 21, 182, 1.1 },
				{ 24, -166, 1 },
				{ 19, -175, 0.8 },
			}
		do
			local at = onMantle(barnacle[1], barnacle[2], -0.2)
			local size = barnacle[3]
			T.ball(headLimb, at, { size * 1.4, size * 1.1, size * 1.4 }, BARNACLE)
			T.ball(headLimb, onMantle(barnacle[1], barnacle[2], size * 0.5), size * 0.5, BARNACLE_DARK)
		end
		-- A king's crown, sat crooked on top: a band of gold set with rubies and emeralds, and points tipped with
		-- pearls.
		local crown, radius, tilt = { -0.4, 29, -6.3 }, 4.2, 0.24
		local up = { -math.sin(tilt), math.cos(tilt), 0 }
		local function rim(index: number): Vec
			local a = index / 8 * math.pi * 2
			local x, z = math.cos(a) * radius, math.sin(a) * radius
			return vadd(crown, { x * math.cos(tilt), x * math.sin(tilt), z })
		end
		for index = 0, 7 do
			local a, b = rim(index), rim(index + 1)
			local out = vnorm(vsub(vlerp(a, b, 0.5), crown))
			T.blade(headLimb, a, b, 1.9, 0.6, out, GOLD)
			T.ball(
				headLimb,
				vadd(vlerp(a, b, 0.5), vscale(out, 0.3)),
				0.8,
				if index % 2 == 0 then RUBY else EMERALD,
				NEON
			)
			local tall = if index % 2 == 0 then 4.4 else 2.6
			local base = vadd(a, vscale(up, 0.5))
			T.taper(
				headLimb,
				base,
				vadd(base, vscale(up, tall)),
				1.1,
				0.5,
				out,
				if index % 2 == 0 then GOLD else GOLD_DARK
			)
			if index % 2 == 0 then
				T.ball(headLimb, vadd(base, vscale(up, tall + 0.2)), 0.7, PEARL, NEON)
			end
		end

		-- The tentacles, with a pale row of suckers along the inside of every bend (or underneath, where they run
		-- straight).
		for index, tentacle in tentacles do
			local route, s = tentacle[2], tentacle[3]
			local limb = pet:limb(tentacle[1], T.at(route[1]))
			s:draw(limb, othersOf(s), PURPLE)
			local samples = alongPath(route, 1.3)
			for k = 3, #samples - 4 do
				local here, r = samples[k][1], samples[k][2]
				local bend = vsub(vlerp(samples[k - 2][1], samples[k + 2][1], 0.5), here)
				local inside = if vlength(bend) > 0.15 then vnorm(bend) else { 0, -1, 0 }
				local spot = vadd(here, vscale(inside, r * 0.7))
				if spot[2] > 0.6 and r > 0.8 then
					if k % 3 == 0 then
						T.ball(limb, spot, r * 0.62, GLOW.color, NEON)
					else
						T.ball(limb, spot, r * 0.62, SUCKER)
					end
				end
			end
			if index == 2 then
				-- A ship's wheel, torn from a wreck and held up high: a rim, spokes with handles, a gold hub.
				local hub = { -14.5, 21.5, 8.9 }
				local function point(k: number, reach: number): Vec
					local a = k / 8 * math.pi * 2
					return vadd(hub, { math.cos(a) * reach, math.sin(a) * reach, 0 })
				end
				for k = 0, 7 do
					T.blade(limb, point(k, 4.3), point(k + 1, 4.3), 1, 0.9, { 0, 0, 1 }, WOOD)
					T.blade(limb, hub, point(k, 5.9), 0.6, 0.6, { 0, 0, 1 }, WOOD_DARK)
					T.ball(limb, point(k, 6), { 1, 1, 0.8 }, WOOD)
				end
				T.ball(limb, hub, { 2, 2, 1.4 }, GOLD)
			elseif index == 8 then
				-- An iron anchor hanging from the tentacle that rears up behind it, trimmed in gold.
				local ring0 = { -12, 23.6, -10.4 }
				local foot = { -12, 13.6, -10.4 }
				T.ball(limb, ring0, { 1.6, 1.6, 0.8 }, GOLD)
				T.blade(limb, ring0, foot, 0.9, 0.9, { 0, 0, 1 }, IRON)
				T.blade(limb, { -14.2, 21.6, -10.4 }, { -9.8, 21.6, -10.4 }, 0.7, 0.7, { 0, 0, 1 }, IRON)
				for _, side in { 1, -1 } do
					local elbow = { -12 + 2.6 * side, 14.4, -10.4 }
					local tip = { -12 + 3.8 * side, 16.8, -10.4 }
					T.blade(limb, foot, elbow, 0.9, 0.9, { 0, 0, 1 }, IRON)
					T.blade(limb, elbow, tip, 0.8, 0.8, { 0, 0, 1 }, IRON)
					T.taper(limb, tip, vadd(tip, { 0.4 * side, 1.6, 0 }), 1.4, 0.5, { 0, 0, 1 }, GOLD_DARK)
				end
				T.ball(limb, foot, { 1.4, 1.4, 1.4 }, GOLD)
			end
		end

		pet:light(GLOW.color, 4, 46)
		pet:particles("Bubbles", SUCKER, 20)
		pet:aura(rgb(200, 80, 255), rgb(255, 190, 236))
		pet:seat(0, 24 / U, 1 / U)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Leviathan (Secret): a colossal sea dragon of the abyss, rearing its head eight times a player's height out of
-- great arching coils as thick as a house. Deep blue scales over a pale banded belly, two rows of big glowing
-- portholes down its flanks, a glass sail on horn spines along its back, a huge head with heavy brows over glowing
-- eyes, sweeping horns and glass gill frills, a gaping mouth glowing deep inside and lined with long needle fangs, a
-- lure arching high over its head to a blazing bulb, and a great forked glass tail fan.

Ocean.Leviathan = {
	name = "Leviathan",
	skeleton = "Serpent",
	gait = "Swim",
	scale = 0.38 * 2.8,
	draw = function(pet)
		-- Built in cells 2.8 design units across (about a stud each): it is big enough to keep every detail.
		local U = 2.8
		local T = inUnits(U)
		local SCALE = look(24, 58, 128)
		local SCALE_TOP = look(42, 88, 170)
		local SCALE_DARK = look(14, 32, 78)
		local SCALE_LIGHT = look(54, 112, 190)
		local BELLY = look(150, 210, 236)
		local BELLY_DARK = look(104, 160, 204)
		local MOUTH = look(46, 14, 52)
		local THROAT = look(110, 250, 255, NEON)
		local GLOW = rgb(90, 240, 255)
		local FIN = rgb(110, 220, 255)
		local HORN = rgb(220, 232, 240)
		local HORN_DARK = rgb(120, 140, 160)
		local FANG = rgb(250, 252, 255)
		local BULB = rgb(210, 255, 255)

		local tones = {
			[SCALE] = { top = SCALE_TOP, under = SCALE_DARK },
			[SCALE_LIGHT] = { under = SCALE },
		}
		-- Scales in big soft patches of lighter and darker blue, like facets catching the light.
		local function scales(p: Vec): Look?
			local n = patches(p, 4.5)
			if n < 0.3 then
				return SCALE_LIGHT
			elseif n > 0.78 then
				return SCALE_DARK
			end
			return nil
		end

		-- The body in lengths, each a limb of its own so a ripple can run down it. Along each, every sample knows
		-- which way its back faces (up, or behind where the neck rears), for the belly plates, spines and portholes.
		type Length = { sculpt: Sculpt, samples: { { any } }, tailward: number }
		local lengths: { Length } = {}
		local function length(points: { { number } }, tailward: number): Length
			local s = newSculpt(U)
			s:add(rod(points), SCALE)
			local samples = alongPath(points, 3.4)
			for _, sample in samples do
				local run = sample[3]
				local back = vsub({ 0, 1, 0 }, vscale(run, run[2]))
				back = if vlength(back) > 0.2 then vnorm(back) else { 0, 0, -1 }
				sample[4] = back
				sample[5] = vnorm(Kit.vcross(run, back))
			end
			s:coat(function(p)
				local best, nearest, at = math.huge, samples[1], 1
				for index, sample in samples do
					local d = vlength(vsub(p, sample[1]))
					if d < best then
						best, nearest, at = d, sample, index
					end
				end
				local out = vnorm(vsub(p, nearest[1]))
				if vdot(out, nearest[4]) < -0.5 then
					return if at % 2 == 0 then BELLY else BELLY_DARK
				end
				return scales(p)
			end)
			s:bake(tones)
			local entry = { sculpt = s, samples = samples, tailward = tailward }
			table.insert(lengths, entry)
			return entry
		end
		-- Rearing up into the neck at the front; two great arches; a tail lifting to its fan.
		local neck = length({
			{ 0, 11.45, -8, 11.25 },
			{ 0, 11.45, 2, 11.25 },
			{ 0, 18, 10, 10.75 },
			{ 0, 34, 14, 10 },
			{ 0, 50, 15, 9.25 },
			{ 0, 61, 19, 8.5 },
		}, -1)
		local coil1 = length({
			{ 0, 11.45, -8, 11.25 },
			{ 3, 11.2, -18, 11 },
			{ 5, 26, -28, 10.5 },
			{ 0, 33, -40, 10 },
			{ 1, 26, -52, 9.5 },
			{ -2, 9.2, -60, 9 },
			{ -3, 8.95, -66, 8.75 },
		}, 1)
		local coil2 = length({
			{ -3, 8.95, -66, 8.75 },
			{ -5, 8.45, -74, 8.25 },
			{ -6, 20, -82, 7.75 },
			{ -5, 25, -92, 7.25 },
			{ -2, 17, -102, 6.75 },
			{ 0, 6.45, -108, 6.25 },
		}, 1)
		local tail = length({
			{ 0, 6.45, -108, 6.25 },
			{ 2, 5.2, -116, 5 },
			{ 3, 6, -123, 3.75 },
			{ 3, 12, -129, 2.5 },
		}, 1)

		-- The head: huge, a broad skull under heavy brows, a long upper jaw, the lower jaw hanging open on a glowing
		-- throat.
		local head = newSculpt(U)
		head:add(ellipsoid({ 0, 69, 26 }, { 13, 11.5, 14 }), SCALE)
		for _, s in { 1, -1 } do
			head:add(ellipsoid({ 7.6 * s, 78.6, 34 }, { 5.6, 3.2, 6.6 }), SCALE_DARK)
			head:add(ellipsoid({ 9.6 * s, 62, 26 }, { 5.4, 7, 7 }), SCALE)
		end
		head:add(ellipsoid({ 0, 68, 44 }, { 9.6, 6, 17 }), SCALE)
		head:add(ellipsoid({ 0, 68.6, 59.6 }, { 6, 4.6, 4 }), SCALE)
		head:add(rod({ { 0, 56, 28, 8.4 }, { 0, 50.4, 44, 6.4 }, { 0, 48, 57, 4.6 } }), SCALE)
		head:add(ellipsoid({ 0, 59, 33 }, { 7.4, 5.6, 6.4 }), THROAT)
		head:carve(ellipsoid({ 0, 58, 47 }, { 8.6, 4.4, 17 }))
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if math.abs(x) < 8.6 and y > 50.5 and y < 64 and z > 37 then
				return MOUTH
			end
			if open(0, -1, 0) and y < 54 then
				return BELLY
			end
			return scales(p)
		end)
		head:bake(tones)

		local all: { Sculpt } = { head }
		for _, entry in lengths do
			table.insert(all, entry.sculpt)
		end
		local function othersOf(s: Sculpt): { Sculpt }
			local list = {}
			for _, other in all do
				if other ~= s then
					table.insert(list, other)
				end
			end
			return list
		end

		-- Along a length: horn spines down its back with a glass sail between them (leaving a gap where a rider
		-- sits), and two rows of big glowing portholes down each flank, each in a dark ring.
		local seat = { 0, 43.4, -40 }
		local function dress(limb: Limb, entry: Length)
			local samples = entry.samples
			local tips, bases = {}, {}
			for k = 2, #samples - 1, 2 do
				local here, r, run, back = samples[k][1], samples[k][2], samples[k][3], samples[k][4]
				if vlength(vsub(here, { seat[1], here[2], seat[3] })) > 7 then
					local base = vadd(here, vscale(back, r * 0.8))
					local tip = vadd(base, vadd(vscale(back, 3 + r * 0.7), vscale(run, 1.6 * entry.tailward)))
					T.taper(limb, base, tip, 1.8 + r * 0.2, 1.4, Kit.squareTo(back), HORN)
					table.insert(bases, base)
					table.insert(tips, vlerp(base, tip, 0.75))
				else
					table.insert(bases, false :: any)
					table.insert(tips, false :: any)
				end
			end
			for k = 1, #bases - 1 do
				if bases[k] and bases[k + 1] then
					T.triangle(limb, bases[k], tips[k], bases[k + 1], 0.6, FIN, GLASS)
					T.triangle(limb, tips[k], tips[k + 1], bases[k + 1], 0.6, FIN, GLASS)
				end
			end
			for k = 2, #samples - 1 do
				local here, r, side, back = samples[k][1], samples[k][2], samples[k][5], samples[k][4]
				if r > 3.6 and k % 3 == 2 then
					for _, s in { 1, -1 } do
						local dir = vnorm(vadd(vscale(side, s), vscale(back, 0.08)))
						local c = vadd(here, vscale(dir, r * 0.88))
						T.ball(limb, c, { r * 0.66, r * 0.66, r * 0.66 }, SCALE_DARK.color)
						T.ball(limb, vadd(c, vscale(dir, r * 0.14)), { r * 0.5, r * 0.5, r * 0.5 }, GLOW, NEON)
					end
				end
			end
		end

		local bodyLimb = pet:limb("Body", T.at({ 0, 11.45, -8 }))
		neck.sculpt:draw(bodyLimb, othersOf(neck.sculpt), SCALE)
		dress(bodyLimb, neck)
		local segment1 = pet:limb("Segment1", T.at({ 0, 11.45, -8 }))
		coil1.sculpt:draw(segment1, othersOf(coil1.sculpt), SCALE)
		dress(segment1, coil1)
		local segment2 = pet:limb("Segment2", T.at({ -3, 8.95, -66 }), "Segment1")
		coil2.sculpt:draw(segment2, othersOf(coil2.sculpt), SCALE)
		dress(segment2, coil2)
		local tailLimb = pet:limb("Tail", T.at({ 0, 6.45, -108 }), "Segment2")
		tail.sculpt:draw(tailLimb, othersOf(tail.sculpt), SCALE)
		dress(tailLimb, tail)
		-- A great forked tail fan of glass on bony rays, glowing at its tips.
		local root = { 3, 12, -129 }
		local rays = { { 3, 34, -138 }, { 3, 26, -144 }, { 3, 15, -147 }, { 3, 6, -146 }, { 3, 2, -140 } }
		for k, ray in rays do
			T.blade(tailLimb, root, ray, 1, 1.2, { 1, 0, 0 }, HORN)
			T.ball(tailLimb, ray, { 2, 2, 2 }, GLOW, NEON)
			if k < #rays then
				T.triangle(tailLimb, root, ray, rays[k + 1], 0.6, FIN, GLASS)
			end
		end

		local headLimb = pet:limb("Head", T.at({ 0, 61, 19 }))
		head:draw(headLimb, othersOf(head), SCALE)
		-- Big glowing eyes under the brows, slit-pupilled, ringed in dark scale.
		for _, s in { 1, -1 } do
			local x = sideOf(head, 73, 37)
			T.ball(headLimb, { (x - 0.8) * s, 73, 37 }, { 3.2, 7, 8.4 }, SCALE_DARK.color)
			T.ball(headLimb, { (x - 0.3) * s, 73, 37.2 }, { 2.6, 5.8, 7.2 }, GLOW, NEON)
			T.blade(
				headLimb,
				{ (x + 0.7) * s, 70.6, 37.4 },
				{ (x + 0.7) * s, 75.4, 37.4 },
				1.3,
				0.6,
				{ s, 0, 0 },
				SCALE_DARK.color
			)
		end
		-- Rows of long needle fangs along both jaws, longest at the front.
		for i = 0, 9 do
			for _, s in { 1, -1 } do
				local zu = 57 - i * 2.6
				local xu = sideOf(head, 62.6, zu) - 1.2
				if xu > 1 then
					local long = 9.6 - i * 0.55
					T.taper(
						headLimb,
						{ xu * s, 63.6, zu },
						{ xu * 0.9 * s, 63.6 - long, zu + 1 },
						1.8,
						1.5,
						{ s, 0, 0 },
						FANG
					)
				end
				local zl = 54 - i * 2.6
				local xl = sideOf(head, 53.6, zl) - 1.2
				if xl > 1 then
					local long = 7.4 - i * 0.45
					T.taper(
						headLimb,
						{ xl * s, 52.6, zl },
						{ xl * 0.9 * s, 52.6 + long, zl + 0.8 },
						1.6,
						1.4,
						{ s, 0, 0 },
						FANG
					)
				end
			end
		end
		for _, s in { 1, -1 } do
			-- Great horns sweeping back and up from the skull, ridged, glowing at their tips.
			local horn =
				{ { 8 * s, 78, 20 }, { 12 * s, 86, 12 }, { 15 * s, 94, 4 }, { 16 * s, 101, -4 }, { 14 * s, 106, -10 } }
			T.branch(headLimb, horn, 5, { 0, 0, 1 }, HORN)
			for k = 2, #horn - 1 do
				T.ball(headLimb, horn[k], { 5.4 - k * 0.6, 5.4 - k * 0.6, 5.4 - k * 0.6 }, HORN_DARK)
			end
			T.ball(headLimb, horn[#horn], { 2.6, 2.6, 2.6 }, GLOW, NEON)
			-- Glass gill frills fanned out behind the jaw on bony spines, glowing at the tips.
			local gill = { 11 * s, 64, 20 }
			local spineTips = { { 19 * s, 80, 13 }, { 22 * s, 70, 8 }, { 22 * s, 59, 8 }, { 18 * s, 48, 13 } }
			for k, tip in spineTips do
				T.blade(headLimb, gill, tip, 1.4, 1.4, { s, 0, 0 }, HORN)
				T.ball(headLimb, tip, { 2.2, 2.2, 2.2 }, GLOW, NEON)
				if k < #spineTips then
					T.triangle(headLimb, gill, tip, spineTips[k + 1], 0.8, FIN, GLASS)
				end
			end
			-- Barbels drooping from the snout, glowing at the tips.
			local barbel = { { 4 * s, 64, 58 }, { 10 * s, 62, 61 }, { 12 * s, 54, 61 }, { 12.6 * s, 46, 58 } }
			T.branch(headLimb, barbel, 1.5, { 0, 0, 1 }, SCALE_LIGHT.color)
			T.ball(headLimb, barbel[#barbel], { 2, 2, 2 }, GLOW, NEON)
		end
		-- Horn nubs up the snout.
		for _, z in { 42, 49, 55 } do
			local y = Kit.topOf(head, z)
			T.taper(headLimb, { 0, y - 1, z }, { 0, y + 2.8, z - 1.4 }, 2.2, 1.8, { 1, 0, 0 }, HORN)
		end
		-- The lure: a stalk arching from the brow high over the head, a blazing bulb hanging in front of the jaws.
		local lure = { { 0, 77, 30 }, { 0, 94, 40 }, { 0, 104, 50 }, { 0, 104, 62 }, { 0, 96, 70 }, { 0, 89, 72 } }
		T.branch(headLimb, lure, 2.2, { 1, 0, 0 }, HORN_DARK)
		T.ball(headLimb, { 0, 84, 72.6 }, { 11, 11, 11 }, FIN, GLASS)
		T.ball(headLimb, { 0, 84, 72.6 }, { 8.4, 8.4, 8.4 }, BULB, NEON)

		-- Front fins: great webbed fans of glass on bony rays at the base of the neck, glowing at the tips.
		pet:limbPair("LeftFin", "RightFin", T.at({ 8, 12, 4 }), function(limb)
			local finRoot = { 8, 12, 4 }
			local finRays = { { 20, 18, 8 }, { 24, 14, 2 }, { 25, 10, -4 }, { 22, 6, -10 } }
			for k, ray in finRays do
				T.blade(limb, finRoot, ray, 1.1, 1.2, { 0, 1, 0 }, HORN)
				T.ball(limb, ray, { 1.8, 1.8, 1.8 }, GLOW, NEON)
				if k < #finRays then
					T.triangle(limb, finRoot, ray, finRays[k + 1], 0.6, FIN, GLASS)
				end
			end
		end)

		pet:light(GLOW, 4, 48)
		pet:particles("Bubbles", GLOW, 22)
		pet:aura(rgb(60, 200, 255), rgb(200, 250, 255))
		pet:seat(seat[1] / U, seat[2] / U, seat[3] / U)
	end,
}

return Ocean
