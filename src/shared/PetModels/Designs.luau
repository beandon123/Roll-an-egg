--!strict
-- The look of every pet, by name. Which egg each pet hatches from is set in Config/Zones (`pet`).
-- Each design draws limbs on the pet builder in PetModels:
--     x left (+x) and right (-x); y up from the ground; z forward. A cell numbered x covers x to x + 1.
--     limb:box() draws a solid block, limb:paint() colours the surface of blocks already drawn (eyes, bellies),
--     and the ...Pair versions mirror across the middle of the pet.
-- Pets are themed to match their egg. Every pet in the game has a design, zone by zone: Forest, Desert, Snow,
-- Ocean, Volcano and Prehistoric. Zones redrawn in the showpiece style have their own file beside this one
-- (Forest.luau, Desert.luau, Snow.luau, Ocean.luau, Volcano.luau) and are merged in below; the rest are drawn here,
-- with big heads and small bodies like the eggs they come from. The drawing tools are in PetModels/Kit. The more
-- common pets are blocks placed by hand. The rarer ones are sculpted (`newSculpt`): modelled cell by cell from
-- rounded shapes turned to any angle (`ellipsoid`, `rod`, `curl` for a spiral to end a rod on), coloured by rules
-- (`coat`, `trace`), then packed into blocks; with thin details (horns, claws, fangs, feathers, fins, wings, eyes)
-- built from parts at any angle (`blade`, `taper`, `triangle`, `egg`, `feather`, placed in a design's own units
-- with `inUnits`), so they stay crisp however big a pet is shown, and flames (limb:fire). `blob` fills a rounded
-- shape from a test function, for the Great Shark's body.

local Kit = require(script.Parent.Kit)

type Color = Kit.Color
type Limb = Kit.Limb
type Design = Kit.Design
type Look = Kit.Look
type Sculpt = Kit.Sculpt
type Vec = Kit.Vec

local rgb = Kit.rgb
local NEON = Kit.NEON
local EYE = Kit.EYE
local SHINE = Kit.SHINE
local ellipsoid = Kit.ellipsoid
local rod = Kit.rod
local shape = Kit.shape
local newSculpt = Kit.newSculpt
local vadd = Kit.vadd
local vsub = Kit.vsub
local vscale = Kit.vscale
local vlerp = Kit.vlerp
local vdot = Kit.vdot
local vnorm = Kit.vnorm
local blade = Kit.blade
local taper = Kit.taper
local triangle = Kit.triangle
local egg = Kit.egg
local feather = Kit.feather
local look = Kit.look
local noise = Kit.noise
local topOf = Kit.topOf
local roundEyes = Kit.roundEyes
local slitEyes = Kit.slitEyes
local inUnits = Kit.inUnits

local Designs: { [string]: Design } = {}

-- The zones redrawn in the showpiece style have their own files.
for _, zone in
	{
		require(script.Parent.Forest),
		require(script.Parent.Desert),
		require(script.Parent.Snow),
		require(script.Parent.Ocean),
		require(script.Parent.Volcano),
	}
do
	for kind, design in zone do
		Designs[kind] = design
	end
end

----------------------------------------------------------------------------------------------------------------
-- Volcano (shelved designs only: the zone's pets are in Volcano.luau)

Designs.EternalPhoenix = {
	name = "Eternal Phoenix",
	skeleton = "Winged",
	gait = "Walk",
	scale = 0.42,
	draw = function(pet)
		local RED = rgb(214, 30, 24)
		local RED_DARK = rgb(146, 14, 18)
		local ORANGE = rgb(255, 118, 22)
		local AMBER = rgb(255, 166, 30)
		local YELLOW = rgb(255, 218, 60)
		local GOLD = rgb(255, 190, 40)
		local GOLD_DEEP = rgb(226, 140, 22)
		local BEAK = rgb(255, 208, 80)
		local BEAK_TIP = rgb(206, 112, 20)
		local EYE_RED = rgb(255, 36, 20)
		local PUPIL = rgb(36, 8, 8)
		local WHITE = rgb(255, 255, 255)
		local TALON = rgb(64, 30, 22)
		local ETERNAL = rgb(150, 255, 245)
		local UP, FRONT = { 0, 1, 0 }, { 0, 0, 1 }

		local function band(color: Color, to: number, material: string?): Band
			return { color = color, to = to, material = material }
		end
		-- The burning feathers: deep red at the root, through orange to a glowing yellow tip.
		local FLIGHT = { band(RED, 0.38), band(ORANGE, 0.66), band(AMBER, 0.86, NEON), band(YELLOW, 1, NEON) }
		local COVERT = { band(RED, 0.68), band(ORANGE, 1) }
		local PLUME = { band(RED, 0.4), band(ORANGE, 0.7), band(YELLOW, 0.9, NEON), band(ETERNAL, 1, NEON) }

		-- Its body: an upright red torso leaning forward, a golden breast covered in overlapping feathers of red,
		-- orange and gold, and a ruff of red feathers round its neck.
		local body = pet:limb("Body", { 0, 16, 0 })
		local lean = { { 1, 0, 0 }, { 0, 0.978, 0.208 }, { 0, -0.208, 0.978 } }
		egg(body, { 0, 16, 0 }, { 10, 15, 9.5 }, lean, RED)
		egg(body, { 0, 15, 2.4 }, { 8.4, 12.5, 6 }, lean, GOLD)
		egg(body, { 0, 22.5, 1.6 }, { 6.4, 8, 6.4 }, nil, RED)
		egg(body, { 0, 22, 3.4 }, { 4.6, 7, 3.6 }, nil, GOLD)
		-- Overlapping scale feathers over the breast, each pointing down, in a mottle of red, orange and gold.
		local tones = { RED, ORANGE, GOLD_DEEP, AMBER, RED, YELLOW, ORANGE }
		for row = 0, 7 do
			local y = 20.2 - row * 1.45
			for column = -3, 3 do
				local x = column * 1.35 + (if row % 2 == 1 then 0.68 else 0)
				local inside = 1 - (x / 4.2) ^ 2 - ((y - 15) / 6.25) ^ 2
				if inside > 0.15 and math.abs(x) < 3.9 then
					local z = 2.4 + 3 * math.sqrt(inside) + 0.2 * (y - 15) / 6.25 + 0.15
					local normal = vnorm({ x / 4.2 ^ 2, (y - 15) / 6.25 ^ 2 * 0.6, (z - 2.4) / 9 })
					local down = vnorm(vsub({ 0, -1, 0.15 }, vscale(normal, vdot({ 0, -1, 0.15 }, normal))))
					local tone = tones[(row * 3 + column + 9) % #tones + 1]
					local top = vadd({ x, y + 0.7, z }, vscale(normal, 0.05 * (row % 2)))
					taper(body, top, vadd(top, vscale(down, 2)), 1.6, 0.45, normal, tone)
				end
			end
		end
		-- Rows of feathers down its back, between the wings.
		for row = 0, 2 do
			for column = -1, 1 do
				local x = column * 2.2 + (if row % 2 == 1 then 1.1 else 0)
				local root = { x, 21 - row * 3, -3.6 + row * 0.3 }
				feather(body, root, { x * 0.08, -1, -0.45 }, 4.2, 2.2, 0.5, vnorm({ x * 0.1, 0.3, -1 }), COVERT)
			end
		end
		for layer = 0, 1 do
			for index = 0, 8 do
				local a = math.rad(-160 + index * 40 + layer * 20)
				local radius = 3 + layer * 0.35
				local root = { math.sin(a) * radius, 21.5 - layer * 1.6, 1.4 + math.cos(a) * radius }
				local out = { math.sin(a) * 0.8, -1.5, math.cos(a) * 0.7 - 0.35 }
				local length = 4.5 + layer * 1.5
				feather(
					body,
					root,
					out,
					length,
					1.9,
					0.5,
					{ math.sin(a), 0.35, math.cos(a) },
					if layer == 0 then COVERT else FLIGHT
				)
			end
		end

		-- A fierce eagle's head, sculpted in fine blocks as one solid piece: a flat crown, a hard brow jutting over
		-- the eyes, angular cheeks, and a long hooked beak growing out of the face, parted on the fire in its throat.
		-- The eyes are painted flat on the face, narrow and pointed, slanting up and back under the brow. A crest of
		-- five flame plumes sweeps back from the crown, burning at its tip.
		local head = pet:limb("Head", { 0, 24, 2.5 })
		local function tone(color: Color, material: string?): Look
			return { color = color, material = material }
		end
		local FACE, FACE_DEEP, NAPE = tone(rgb(255, 206, 62)), tone(rgb(240, 160, 34)), tone(RED)
		local BILL, HOOK, CERE = tone(BEAK), tone(BEAK_TIP), tone(rgb(255, 228, 120))
		local GAPE, LID = tone(rgb(90, 30, 18)), tone(rgb(70, 10, 12))
		-- Narrower from side to side than it is round: a raptor's beak.
		local function narrow(s: Shape, squeeze: number): Shape
			return shape(s.centre, s.radius, function(x, y, z)
				return s.inside(x * squeeze, y, z)
			end)
		end
		local skull = newSculpt(0.5)
		skull:add(ellipsoid({ 0, 27.6, 3.4 }, { 3.1, 2.8, 3.9 }), FACE)
		skull:add(ellipsoid({ 0, 26.2, 4.7 }, { 2.7, 1.9, 3.2 }), FACE)
		skull:add(ellipsoid({ 0, 26.9, 1 }, { 2.8, 2.8, 2.6 }), NAPE)
		skull:carve(shape({ 0, 31, 3 }, 6, function(x, y)
			return y > 30.1 + math.abs(x) * 0.1
		end))
		-- The brow: a hard shelf over each eye, low at the beak and rising back, frowning.
		for _, s in { 1, -1 } do
			skull:add(
				rod({ { 1 * s, 29, 6.3, 0.6 }, { 2.3 * s, 29.2, 5.3, 0.65 }, { 3 * s, 29.4, 3.9, 0.5 } }),
				FACE_DEEP
			)
		end
		skull:add(
			narrow(
				rod({
					{ 0, 27.5, 6.4, 1.45 },
					{ 0, 27.2, 8.6, 1.1 },
					{ 0, 26.4, 10.3, 0.75 },
					{ 0, 25.2, 11, 0.45 },
					{ 0, 24.4, 10.7, 0.3 },
				}),
				1.35
			),
			BILL
		)
		skull:add(narrow(rod({ { 0, 25.4, 6.8, 0.85 }, { 0, 25.1, 9.2, 0.5 } }), 1.3), BILL)
		skull:carve(shape({ 0, 25.9, 8.6 }, 3, function(x, y, z)
			return math.abs(y - 25.9) < 0.3 and z > 7.4 and z < 10 and math.abs(x) < 1.2
		end))
		skull:add(ellipsoid({ 0, 25.9, 7.4 }, { 0.9, 0.35, 0.6 }), tone(ORANGE, NEON))
		skull:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			local side = if x > 0 then 1 else -1
			-- The hooked tip, darker; the waxy band at the base of the beak; the nostrils.
			if z > 9.4 and y < 26.2 and math.abs(x) < 1.3 then
				return HOOK
			end
			if z > 6.2 and z < 7.1 and y > 26.2 and math.abs(x) < 1.4 then
				return CERE
			end
			if z > 7.6 and z < 8.3 and y > 27.1 and y < 27.7 and math.abs(x) > 0.45 and open(side, 0, 0) then
				return GAPE
			end
			-- The line of the mouth running back under the eye.
			if math.abs(y - 25.95) < 0.3 and z > 5.2 and z < 7.6 and open(side, 0, 0) then
				return GAPE
			end
			-- The eye: flat on the side of the face, pointed at both ends, slanting up towards the back, with a
			-- dark rim round it and a slit pupil.
			if math.abs(x) > 1.6 and open(side, 0, 0) and z > 3 and z < 6.6 then
				local t = (6.3 - z) / 3
				local top = 27.95 + 0.55 * t
				local thick = 0.95 * math.max(0, math.sin(math.pi * math.clamp(t, 0, 1))) ^ 0.7
				if t >= 0 and t <= 1 and y <= top and y >= top - thick then
					if z > 4.7 and z < 5.1 then
						return tone(PUPIL)
					end
					if z >= 5.1 and z < 5.5 and y > top - 0.45 then
						return tone(WHITE, NEON)
					end
					return tone(EYE_RED, NEON)
				end
				if t >= -0.12 and t <= 1.12 and y <= top + 0.35 and y >= top - thick - 0.3 then
					return LID
				end
			end
			-- Red feathers at the back of the head, in a point down the nape.
			if z < 2 - (y - 26) * 0.35 then
				return NAPE
			end
			return nil
		end)
		skull:draw(head, nil, FACE, true)
		-- The crest: five plumes sweeping back from the crown, the middle one longest and burning at its tip.
		for k = -2, 2 do
			local a = math.abs(k)
			local root = { k * 0.9, 29.4, 2.4 - a * 0.4 }
			local reach = 1 - a * 0.25
			local mid = { k * 1.3, 32 + 2.5 * reach, -0.8 - a * 0.3 }
			local tip = { k * 1.7, 34 + 6 * reach, -5.5 - a * 0.6 }
			local facing = vnorm({ k * 0.25, 0.6, 1 })
			blade(head, root, mid, 1.6, 0.5, facing, RED)
			local three = vlerp(mid, tip, 0.5)
			blade(head, mid, three, 1.35, 0.45, facing, ORANGE)
			taper(head, three, tip, 1.15, 0.45, facing, if k == 0 then ETERNAL else YELLOW, NEON)
		end
		head:fire({ 0, 40.6, -6.2 }, 9, ORANGE, YELLOW)

		-- Great wings spread wide, layer over layer: short red coverts along the arm, then long secondaries, then
		-- the longest flight feathers fanning out at the tip, each burning from red to a glowing yellow tip.
		pet:limbPair("LeftWing", "RightWing", { 4.2, 21, -1 }, function(wing)
			local arm = { { 4.2, 21, -1 }, { 10.5, 23, -2.6 }, { 16.5, 22.4, -4 }, { 22, 20.4, -5.4 } }
			local function along(t: number): Vec
				local f = t * (#arm - 1)
				local index = math.min(#arm - 1, math.floor(f) + 1)
				return vlerp(arm[index], arm[index + 1], f - (index - 1))
			end
			local surface = vnorm({ 0, 0.15, 1 })
			for index = 1, #arm - 1 do
				blade(wing, arm[index], arm[index + 1], 2.8 - index * 0.5, 1.6, surface, RED_DARK)
			end
			egg(wing, arm[2], { 2.8, 2.8, 2 }, nil, RED)
			egg(wing, arm[3], { 2.3, 2.3, 1.8 }, nil, RED)
			for index = 0, 11 do
				local t = 0.04 + index * 0.08
				local root = vadd(along(t), { 0, -0.6, 0.55 + (index % 2) * 0.14 })
				local tilt = vnorm({ 0.1 + t * 0.4, -1, -0.15 })
				feather(
					wing,
					root,
					tilt,
					4.8 - t * 1.4,
					2.3,
					0.5,
					vnorm({ 0.03 * (index % 2 * 2 - 1), 0.15, 1 }),
					COVERT
				)
			end
			for index = 0, 5 do
				local t = 0.05 + index * 0.1
				local root = vadd(along(t), { 0, -2.2, 0.1 + (index % 2) * 0.14 })
				local tilt = vnorm({ 0.12 + t * 0.45, -1, -0.2 })
				feather(
					wing,
					root,
					tilt,
					9.5 + index * 0.4,
					2.5,
					0.5,
					vnorm({ 0.03 * (index % 2 * 2 - 1), 0.12, 1 }),
					FLIGHT
				)
			end
			for index = 0, 6 do
				local t = 0.58 + index * 0.07
				local root = vadd(along(t), { 0, -1.2, -0.35 + (index % 2) * 0.14 })
				local fan = index / 6
				local tilt = vnorm({ 0.3 + fan * 0.55, -1 + fan * 0.22, -0.25 })
				feather(
					wing,
					root,
					tilt,
					11.5 + index * 0.45,
					2.3,
					0.5,
					vnorm({ 0.03 * (index % 2 * 2 - 1), 0.12, 1 }),
					FLIGHT
				)
			end
			-- Small feathers over the top of the arm, overlapping back from its leading edge.
			for index = 0, 9 do
				local t = 0.05 + index * 0.1
				local root = vadd(along(t), { 0, 1, 0.9 })
				feather(
					wing,
					root,
					{ 0.25, -0.35, -1 },
					2.6,
					2,
					0.45,
					vnorm({ 0, 1, 0.25 }),
					{ band(RED, 0.6), band(ORANGE, 1) }
				)
			end
			wing:fire(vadd(along(1), { 7.5, -5, -0.5 }), 4, ORANGE, YELLOW)
		end)

		-- Strong red thighs over golden legs, gripping talons, and fire burning round its feet.
		pet:limbPair("LeftLeg", "RightLeg", { 2.6, 9, 0.5 }, function(leg)
			egg(leg, { 2.7, 8.8, 0.6 }, { 4.2, 6, 4.6 }, nil, RED)
			for _, flake in
				{
					{ 2.4, 10.4, 2.7, ORANGE },
					{ 3.6, 10, 2.4, RED },
					{ 2.6, 8.6, 2.8, AMBER },
					{ 3.9, 8.2, 2.2, ORANGE },
					{ 3.1, 6.9, 2.4, GOLD_DEEP },
					{ 4.6, 9, 0.9, AMBER },
					{ 4.7, 7.4, 0.6, ORANGE },
				}
			do
				local normal = vnorm({ flake[1] - 2.7, 0.2, flake[3] - 0.6 })
				local top = { flake[1], flake[2] + 0.8, flake[3] }
				taper(leg, top, vadd(top, { 0, -2, 0.2 }), 1.7, 0.45, normal, flake[4])
			end
			blade(leg, { 2.9, 6.2, 1.2 }, { 3.1, 2, 1.8 }, 1.4, 1.4, FRONT, GOLD)
			egg(leg, { 3.1, 1.9, 1.9 }, { 1.8, 1.6, 1.8 }, nil, GOLD)
			for _, dx in { -1.3, 0, 1.3 } do
				blade(leg, { 3.1, 1.4, 2.2 }, { 3.1 + dx, 0.7, 4.8 }, 0.9, 0.9, UP, GOLD)
				taper(leg, { 3.1 + dx, 0.75, 4.7 }, { 3.1 + dx * 1.1, 0.4, 5.7 }, 0.8, 0.7, { 1, 0, 0 }, TALON)
			end
			blade(leg, { 3.1, 1.4, 1.6 }, { 3.1, 0.6, -0.4 }, 0.9, 0.9, UP, GOLD)
			taper(leg, { 3.1, 0.65, -0.3 }, { 3.1, 0.4, -1.2 }, 0.8, 0.7, { 1, 0, 0 }, TALON)
			leg:fire({ 3, 0.8, 2.6 }, 8, rgb(255, 80, 20), YELLOW)
		end)

		-- A long tail of fanned flame feathers, the middle ones longest and tipped with eternal blue.
		local tail = pet:limb("Tail", { 0, 10, -3.5 })
		for k = -3, 3 do
			local a = math.abs(k)
			local facing = vnorm({ 0, 1, -0.3 })
			local root = vadd({ k * 0.5, 10, -4 }, vscale(facing, (a % 2) * 0.16))
			feather(
				tail,
				root,
				{ k * 0.28, -0.36, -1 },
				15 + (3 - a) * 2.5,
				2.4,
				0.5,
				facing,
				if a == 0 then PLUME else FLIGHT
			)
		end
		for k = -2, 2 do
			local facing = vnorm({ 0, 1, -0.2 })
			local root = vadd({ k * 0.7, 11, -4.2 }, vscale(facing, 0.6 + (math.abs(k) % 2) * 0.15))
			feather(tail, root, { k * 0.3, -0.3, -1 }, 8, 2.3, 0.5, facing, COVERT)
		end
		-- Two long streamers trailing far behind, tipped with eternal blue.
		for _, s in { 1, -1 } do
			local points = {
				{ 0.8 * s, 9.5, -4.5 },
				{ 2.5 * s, 7, -12 },
				{ 4.5 * s, 5.5, -20 },
				{ 6 * s, 6, -27 },
				{ 6.5 * s, 8.5, -32 },
			}
			local colors = { RED, ORANGE, AMBER, YELLOW }
			for index = 1, #points - 2 do
				blade(
					tail,
					points[index],
					points[index + 1],
					1.5 - index * 0.15,
					0.4,
					UP,
					colors[index],
					if index >= 3 then NEON else nil
				)
			end
			taper(tail, points[#points - 1], points[#points], 1.1, 0.4, UP, ETERNAL, NEON)
		end
		tail:fire({ 0, 3, -25 }, 6, ORANGE, YELLOW)

		pet:light(rgb(255, 140, 40), 3.4, 26)
		pet:particles("Embers", rgb(255, 200, 70), 20)
		pet:seat(0, 23.5, -3)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Prehistoric

Designs.Velociraptor = {
	name = "Velociraptor",
	skeleton = "Theropod",
	gait = "Walk",
	scale = 0.45,
	draw = function(pet)
		-- Sculpted in the units it is built in (one to a block), with feathers, teeth and claws of parts at any
		-- angle.
		local U = 1
		local T = inUnits(U)
		local SCALES = look(124, 146, 66)
		local DARK = look(70, 84, 42)
		local BELLY = look(232, 218, 166)
		local FEATHER = rgb(214, 112, 46)
		local FEATHER_DARK = rgb(150, 70, 30)
		local CLAW = rgb(240, 232, 212)
		local AMBER = rgb(255, 172, 36)
		local QUILL = {
			{ color = FEATHER_DARK, to = 0.5 },
			{ color = FEATHER, to = 1 },
		}

		-- Green scales, striped dark across the back, pale underneath.
		local function scales(p: Vec, open: (number, number, number) -> boolean, belly: number): Look?
			if open(0, -1, 0) and p[2] < belly then
				return BELLY
			end
			if
				(open(0, 1, 0) or open(1, 0, 0) or open(-1, 0, 0))
				and p[2] > belly + 1.2
				and (p[3] + 40) % 2.6 < 0.8
			then
				return DARK
			end
			return nil
		end

		-- A lean body held level.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 13, -1 }, { 3, 3.6, 6 }), SCALES)
		body:add(ellipsoid({ 0, 12.6, 3.4 }, { 2.8, 3.4, 3.4 }), SCALES)
		body:coat(function(p, open)
			return scales(p, open, 11)
		end)

		-- A long, low head on an S of a neck: a toothy jaw, glowing amber eyes under ridged brows, a crest of quills.
		local head = newSculpt(U)
		head:add(rod({ { 0, 14.6, 5, 2.1 }, { 0, 17.4, 6.6, 1.65 }, { 0, 19, 8.4, 1.55 } }), SCALES)
		head:add(ellipsoid({ 0, 19.6, 10.4 }, { 1.95, 1.85, 2.9 }), SCALES)
		head:add(ellipsoid({ 0, 19.1, 13.4 }, { 1.35, 1.3, 2.5 }), SCALES)
		head:add(ellipsoid({ 0, 17.9, 12.4 }, { 1.15, 0.65, 2.6 }), SCALES)
		for _, s in { 1, -1 } do
			head:add(rod({ { 1.3 * s, 21.1, 9.6, 0.55 }, { 1.2 * s, 20.9, 12.4, 0.45 } }), DARK)
		end
		head:coat(function(p, open)
			if open(0, -1, 0) and p[3] > 9 then
				return BELLY
			end
			return scales(p, open, 18)
		end)

		local arm = newSculpt(U)
		arm:add(rod({ { 2.2, 13, 4, 0.95 }, { 3, 11, 5.6, 0.8 }, { 3.1, 10, 7.2, 0.65 } }), SCALES)

		local leg = newSculpt(U)
		leg:add(ellipsoid({ 2.8, 11.4, -1.4 }, { 1.9, 3.6, 2.6 }), SCALES)
		leg:add(rod({ { 3, 8.6, -2.6, 1.55 }, { 3.1, 4, -1.4, 1.1 } }), SCALES)
		leg:add(rod({ { 3.1, 4, -1.4, 0.95 }, { 3.1, 1, 0.4, 0.85 } }), SCALES)
		for _, dx in { -0.5, 0.5 } do
			leg:add(rod({ { 3.1 + dx, 0.8, 0.6, 0.6 }, { 3.1 + dx * 1.4, 0.6, 3, 0.45 } }), DARK)
		end
		leg:coat(function(p, open)
			return scales(p, open, 9)
		end)

		local tail = newSculpt(U)
		tail:add(
			rod({ { 0, 13.6, -6.6, 2.4 }, { 0, 13.4, -14, 1.6 }, { 0, 13, -21, 1 }, { 0, 12.8, -26, 0.55 } }),
			SCALES
		)
		tail:coat(function(p, open)
			return scales(p, open, 12.6)
		end)

		local legMirror, armMirror = leg:mirror(), arm:mirror()
		local bodyLimb = pet:limb("Body", T.at({ 0, 12, 0 }))
		body:draw(bodyLimb, { head, leg, legMirror, arm, armMirror, tail }, SCALES)
		for index, z in { 0.4, -1.8, -4 } do
			local y = topOf(body, z)
			feather(
				bodyLimb,
				T.at({ 0, y - 0.3, z }),
				{ 0, 0.5, -1 },
				(2.6 - index * 0.3) / U,
				0.9 / U,
				0.35 / U,
				{ 1, 0, 0 },
				QUILL
			)
		end
		local headLimb = pet:limb("Head", T.at({ 0, 14.6, 5 }))
		head:draw(headLimb, { body }, SCALES)
		slitEyes(headLimb, head, { 20.2, 11.6 }, { 20.5, 10 }, 0.55, AMBER, NEON, DARK.color)
		for _, s in { 1, -1 } do
			for _, z in { 11.4, 12.6, 13.8, 15 } do
				T.taper(headLimb, { 0.95 * s, 18.4, z }, { 0.95 * s, 17.7, z + 0.2 }, 0.35, 0.3, { 1, 0, 0 }, CLAW)
			end
		end
		for index, z in { 9.6, 8.2, 6.8, 5.4 } do
			local y = topOf(head, z)
			feather(
				headLimb,
				T.at({ 0, y - 0.3, z }),
				{ 0, 0.8, -1 },
				(3 - index * 0.35) / U,
				0.9 / U,
				0.35 / U,
				{ 1, 0, 0 },
				QUILL
			)
		end
		pet:limbPair("LeftArm", "RightArm", T.at({ 2.2, 13, 4 }), function(limb)
			arm:draw(limb, { body }, SCALES)
			for index, t in { 0.2, 0.5, 0.8 } do
				local root = vlerp({ 2.4, 13, 4 }, { 3.1, 10.2, 7 }, t)
				feather(limb, T.at(root), { 0.3, -0.5, -1 }, (3 - index * 0.4) / U, 1 / U, 0.35 / U, { 1, 0, 0 }, QUILL)
			end
			for _, dy in { -0.3, 0.3 } do
				T.taper(limb, { 3.1, 10.1 + dy, 6.5 }, { 3.2, 9.2 + dy, 8.4 }, 0.4, 0.35, { 1, 0, 0 }, CLAW)
			end
		end)
		pet:limbPair("LeftLeg", "RightLeg", T.at({ 2.8, 12, -1.4 }), function(limb)
			leg:draw(limb, { body }, SCALES)
			-- The sickle claw, held up off the ground.
			T.taper(limb, { 3.6, 1.4, 0.4 }, { 3.9, 2.6, 2 }, 0.55, 0.5, { 1, 0, 0 }, CLAW)
		end)
		local tailLimb = pet:limb("Tail", T.at({ 0, 13.6, -6.6 }))
		tail:draw(tailLimb, { body }, SCALES)
		for _, dx in { -1, 0, 1 } do
			feather(
				tailLimb,
				T.at({ dx * 0.4, 12.8, -25 }),
				{ dx * 0.4, 0.1, -1 },
				3.4 / U,
				1 / U,
				0.35 / U,
				{ 0, 1, 0 },
				QUILL
			)
		end

		pet:seat(0, 17 / U, -1 / U)
	end,
}

Designs.Pteranodon = {
	name = "Pteranodon",
	skeleton = "Winged",
	gait = "Walk",
	scale = 0.55 * 0.8,
	draw = function(pet)
		-- Sculpted finer than it is drawn (blocks 0.8 of a unit across), with a beak, crest and wings of parts at
		-- any angle, so it keeps its shape however big it is shown.
		local U = 0.8
		local function at(p: Vec): Vec
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local function bladeAt(limb: Limb, a: Vec, b: Vec, w: number, t: number, f: Vec, c: Color, m: string?)
			blade(limb, at(a), at(b), w / U, t / U, f, c, m)
		end
		local function taperAt(limb: Limb, a: Vec, b: Vec, w: number, t: number, f: Vec, c: Color, m: string?)
			taper(limb, at(a), at(b), w / U, t / U, f, c, m)
		end
		local function triangleAt(limb: Limb, a: Vec, b: Vec, c: Vec, t: number, color: Color)
			triangle(limb, at(a), at(b), at(c), t / U, color)
		end
		local function eggAt(limb: Limb, centre: Vec, size: Vec, color: Color)
			egg(limb, at(centre), { size[1] / U, size[2] / U, size[3] / U }, nil, color)
		end
		local FUR = look(204, 150, 104)
		local FUR_LIGHT = look(222, 176, 128)
		local DARK = look(150, 96, 70)
		local CREAM = look(240, 222, 180)
		local CAP = look(120, 72, 52)
		local FOOT = look(196, 146, 78)
		local CLAW = rgb(60, 40, 32)
		local CREST = rgb(226, 78, 46)
		local CREST_DARK = rgb(160, 44, 34)
		local BEAK = rgb(240, 202, 120)
		local BEAK_DARK = rgb(196, 146, 78)
		local MEMBRANE = rgb(186, 100, 70)
		local MEMBRANE_DARK = rgb(146, 72, 54)
		local VEIN = rgb(132, 66, 48)
		local BONE = rgb(112, 70, 50)
		local SIDE = { 1, 0, 0 }
		local FLAT = { 0, 0, 1 }

		local function speckle(p: Vec, chance: number): boolean
			local n = math.sin(p[1] * 12.9898 + p[2] * 78.233 + p[3] * 37.719) * 43758.5453
			return n - math.floor(n) < chance
		end
		-- Short fur: a cream chest and belly, a darker back, flecked lighter all over.
		local function fur(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, 0, 1) and not open(0, 0, -1) and math.abs(p[1]) < 2.4 then
				return CREAM
			end
			if open(0, 0, -1) then
				return DARK
			end
			if speckle(p, 0.14) then
				return FUR_LIGHT
			end
			return nil
		end

		-- An upright, furry body, broad at the shoulders where the wings join.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 9.4, -0.4 }, { 4.2, 5.2, 3.9 }), FUR)
		body:add(ellipsoid({ 0, 11.6, -0.2 }, { 4.8, 2.8, 3.3 }), FUR)
		body:add(ellipsoid({ 0, 6, -0.8 }, { 3.2, 2.6, 3 }), FUR)
		body:coat(fur)

		-- A slender neck and a long head: dark-capped, with a long pointed beak and a tall crest sweeping back.
		local head = newSculpt(U)
		head:add(rod({ { 0, 13, 0, 2.2 }, { 0, 15.2, 0.6, 1.8 }, { 0, 16.8, 0.8, 1.9 } }), FUR)
		head:add(ellipsoid({ 0, 18, 0.7 }, { 2.4, 2.3, 3 }), FUR)
		head:add(ellipsoid({ 0, 17.4, 2.5 }, { 1.6, 1.7, 1.8 }), FUR)
		head:coat(function(p, open)
			if p[2] > 19 then
				return CAP
			end
			return fur(p, open)
		end)

		-- Legs with gripping feet of three clawed toes.
		local leg = newSculpt(U)
		leg:add(rod({ { 1.7, 5.6, -0.6, 1.4 }, { 1.9, 3, -0.2, 0.85 }, { 1.9, 1, 0.3, 0.7 } }), FUR)
		for _, dx in { -0.8, 0, 0.8 } do
			leg:add(rod({ { 1.9 + dx * 0.4, 0.7, 0.6, 0.55 }, { 1.9 + dx, 0.5, 2.4, 0.45 } }), FOOT)
		end
		leg:coat(function(p)
			return if p[2] < 1.6 then FOOT else nil
		end)

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 6, -2.6, 0.9 }, { 0, 5.4, -5.8, 0.35 } }), FUR)
		tail:coat(function()
			return DARK
		end)

		local legMirror = leg:mirror()
		body:draw(pet:limb("Body", at({ 0, 8, 0 })), { head, leg, legMirror, tail }, FUR)
		local headLimb = pet:limb("Head", at({ 0, 13, 0 }))
		head:draw(headLimb, { body }, FUR)
		-- Round eyes on the surface of its head.
		local cx, cy, cz = 0, math.floor(18.4 / U), math.floor(1.6 / U)
		while head:has(cx + 1, cy, cz) do
			cx += 1
		end
		local eyeX = (cx + 1) * U
		for _, s in { 1, -1 } do
			eggAt(headLimb, { (eyeX - 0.12) * s, 18.4, 1.6 }, { 0.55, 0.95, 0.95 }, EYE)
			eggAt(headLimb, { (eyeX + 0.1) * s, 18.75, 1.85 }, { 0.22, 0.32, 0.32 }, SHINE)
		end
		bladeAt(headLimb, { 0, 17.9, 3 }, { 0, 17.6, 7 }, 1.7, 1.8, SIDE, BEAK)
		taperAt(headLimb, { 0, 17.6, 7 }, { 0, 16.9, 12.5 }, 1.7, 1.5, SIDE, BEAK)
		bladeAt(headLimb, { 0, 16.5, 3 }, { 0, 16.3, 6.4 }, 1, 1.6, SIDE, BEAK_DARK)
		taperAt(headLimb, { 0, 16.3, 6.4 }, { 0, 16.1, 10.6 }, 1, 1.3, SIDE, BEAK_DARK)
		triangleAt(headLimb, { 0, 19.8, 1.6 }, { 0, 25.5, -9.5 }, { 0, 17, -1.8 }, 0.7, CREST)
		triangleAt(headLimb, { 0, 19.4, -0.8 }, { 0, 23.6, -8.2 }, { 0, 18.2, -2.2 }, 0.9, CREST_DARK)
		pet:limbPair("LeftLeg", "RightLeg", at({ 1.7, 5.6, -0.6 }), function(limb)
			leg:draw(limb, { body }, FUR)
		end)
		tail:draw(pet:limb("Tail", at({ 0, 6, -2.6 })), { body }, FUR)

		-- Great leathery wings held out wide: a bony arm to the wrist, then one very long finger out to the tip,
		-- the membrane two-toned and veined, and small clawed fingers at each wrist.
		pet:limbPair("LeftWing", "RightWing", at({ 3, 11.4, 0 }), function(wing)
			local shoulder, elbow, wrist = { 3, 11.4, 0 }, { 8, 13, -1 }, { 12.5, 14.5, -0.5 }
			local knuckle, tip = { 19, 15.2, -2 }, { 26, 15, -4 }
			local trail1, trail2, flank = { 19.5, 11, -3.5 }, { 13, 7.5, -3 }, { 3, 6.5, -1.4 }
			triangleAt(wing, wrist, tip, trail1, 0.4, MEMBRANE)
			triangleAt(wing, wrist, trail1, trail2, 0.4, MEMBRANE)
			triangleAt(wing, elbow, wrist, trail2, 0.4, MEMBRANE)
			triangleAt(wing, elbow, trail2, flank, 0.4, MEMBRANE_DARK)
			triangleAt(wing, shoulder, elbow, flank, 0.4, MEMBRANE_DARK)
			for _, vein in { { wrist, trail1 }, { wrist, trail2 }, { elbow, flank } } do
				bladeAt(wing, vein[1], vlerp(vein[1], vein[2], 0.85), 0.28, 0.55, FLAT, VEIN)
			end
			bladeAt(wing, shoulder, elbow, 1.4, 1.1, FLAT, BONE)
			bladeAt(wing, elbow, wrist, 1.2, 1, FLAT, BONE)
			bladeAt(wing, wrist, knuckle, 1, 0.9, FLAT, BONE)
			taperAt(wing, knuckle, tip, 0.9, 0.8, FLAT, BONE)
			eggAt(wing, wrist, { 1.5, 1.5, 1.5 }, BONE)
			for _, claw in { { 12.2, 15.6, 1.6 }, { 13.3, 15.4, 1.4 }, { 11.4, 15.2, 1.2 } } do
				taperAt(wing, wrist, claw, 0.55, 0.45, { 0, 1, 0 }, CLAW)
			end
		end)

		pet:seat(0, 13.5 / U, -1 / U)
	end,
}

Designs.Triceratops = {
	name = "Triceratops",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.46 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with its horns, beak and the knobs
		-- round its frill of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local HIDE = look(118, 138, 98)
		local DARK = look(84, 102, 72)
		local LIGHT = look(166, 178, 124)
		local FRILL = look(234, 120, 50)
		local RIM = look(250, 214, 120)
		local SPOT = look(56, 96, 90)
		local NAIL = look(236, 228, 206)
		local HORN = rgb(246, 236, 206)
		local HORN_BASE = rgb(206, 192, 158)
		local BEAK = rgb(74, 68, 60)

		local function hide(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, -1, 0) and p[2] < 11 then
				return LIGHT
			end
			if open(0, 1, 0) and math.floor((p[3] + 40) / 3.2) % 2 == 0 then
				return DARK
			end
			return if noise(p) < 0.1 then LIGHT else nil
		end

		-- A big barrel of a body, banded across the back.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 13.5, -2 }, { 6.8, 6.6, 10.4 }), HIDE)
		body:add(ellipsoid({ 0, 14.6, 4.4 }, { 6, 5.6, 5 }), HIDE)
		body:add(ellipsoid({ 0, 14.6, -8.6 }, { 6, 6, 5 }), HIDE)
		body:coat(hide)

		-- A great head: a frill tilted back behind it, rimmed and spotted, and a hooked beak.
		local head = newSculpt(U)
		head:add(rod({ { 0, 14, 7, 4.4 }, { 0, 13, 9, 4 } }), HIDE)
		head:add(ellipsoid({ 0, 12.6, 10.8 }, { 3.7, 3.9, 4.4 }), HIDE)
		head:add(ellipsoid({ 0, 11.2, 15.2 }, { 2.3, 2.7, 2.7 }), HIDE)
		local frill = { origin = { 0, 18.4, 7.4 }, pitch = 0.5 }
		head:add(ellipsoid({ 0, 0, 0 }, { 9, 7.8, 0.65 }), RIM, frill)
		head:add(ellipsoid({ 0, 0, 0 }, { 8.4, 7.2, 0.8 }), FRILL, frill)
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			if y > 14.6 and z < 9.6 then
				local n = noise({ math.floor(x / 1.6), math.floor(y / 1.6), 0 })
				return if n < 0.18 and (open(0, 0, 1) or open(0, 1, 0)) then SPOT else nil
			end
			return hide(p, open)
		end)

		local function foot(s: Sculpt, x: number, z: number)
			s:add(ellipsoid({ x, 1.3, z }, { 2.8, 1.3, 3 }), HIDE)
			for _, dx in { -1.3, 0, 1.3 } do
				s:add(ellipsoid({ x + dx, 0.9, z + 2.5 }, { 0.7, 0.9, 0.65 }), NAIL)
			end
		end
		local front = newSculpt(U)
		front:add(rod({ { 4.4, 11, 5, 3 }, { 4.6, 5, 5.6, 2.6 }, { 4.6, 2.4, 5.6, 2.5 } }), HIDE)
		foot(front, 4.6, 6)
		local back = newSculpt(U)
		back:add(ellipsoid({ 4.6, 13, -8.6 }, { 3.4, 5, 4.2 }), HIDE)
		back:add(rod({ { 4.8, 9, -9.6, 3 }, { 4.9, 2.4, -9, 2.6 } }), HIDE)
		foot(back, 4.9, -8.8)
		for _, leg in { front, back } do
			leg:coat(function(p, open)
				return if p[2] > 2.2 then hide(p, open) else nil
			end)
		end

		local tail = newSculpt(U)
		tail:add(rod({ { 0, 14, -13, 3.8 }, { 0, 12.6, -19, 2.4 }, { 0, 11, -24, 1.2 } }), HIDE)
		tail:coat(hide)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 13, 0 })), { head, front, frontMirror, back, backMirror, tail }, HIDE)
		local headLimb = pet:limb("Head", T.at({ 0, 13, 7 }))
		head:draw(headLimb, { body }, HIDE)
		roundEyes(headLimb, head, 14, 13.4, 1.1)
		-- Two long horns over its eyes, one on its nose, small ones on its cheeks, a hooked beak, and knobs all
		-- round the rim of its frill.
		for _, s in { 1, -1 } do
			T.blade(headLimb, { 1.9 * s, 15.4, 12 }, { 2.5 * s, 19, 15.4 }, 1.5, 1.5, { 1, 0, 0 }, HORN_BASE)
			T.taper(headLimb, { 2.5 * s, 19, 15.4 }, { 2.9 * s, 22.2, 19.4 }, 1.3, 1.3, { 1, 0, 0 }, HORN)
			T.taper(headLimb, { 3.4 * s, 11, 10.6 }, { 5.2 * s, 10.6, 10.2 }, 1, 1, { 0, 1, 0 }, HORN)
		end
		T.taper(headLimb, { 0, 13.4, 16.2 }, { 0, 16.2, 17.6 }, 1.2, 1.2, { 1, 0, 0 }, HORN)
		T.blade(headLimb, { 0, 11.8, 16.6 }, { 0, 10.6, 18.4 }, 1.6, 1.6, { 1, 0, 0 }, BEAK)
		T.taper(headLimb, { 0, 10.6, 18.4 }, { 0, 8.6, 18.6 }, 1.4, 1.4, { 1, 0, 0 }, BEAK)
		T.blade(headLimb, { 0, 9.6, 15.6 }, { 0, 9.2, 17.2 }, 1.4, 1.2, { 1, 0, 0 }, BEAK)
		local c, s = math.cos(0.5), math.sin(0.5)
		for index = 0, 15 do
			local angle = math.pi * (index / 15)
			local ex, ey = math.cos(angle) * 8.3, math.sin(angle) * 7.1
			local knob = { ex, 18.4 + ey * c, 7.4 - ey * s }
			if ey > -2 then
				T.taper(
					headLimb,
					knob,
					vadd(knob, { math.cos(angle) * 1.4, math.sin(angle) * 1.2 * c, -math.sin(angle) * 1.2 * s }),
					1.1,
					0.8,
					{ 0, s, c },
					RIM.color
				)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 4.4, 11, 5 }), function(limb)
			front:draw(limb, { body }, HIDE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4.6, 13, -8.6 }), function(limb)
			back:draw(limb, { body }, HIDE)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 14, -12 })), { body }, HIDE)

		pet:light(FRILL.color, 1.8, 16)
		pet:seat(0, 20.6 / U, -2 / U)
	end,
}

Designs.Stegosaurus = {
	name = "Stegosaurus",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.42 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with plates and spikes of parts at
		-- any angle, so it keeps its shape however big it is shown.
		local U = 1.2
		local function at(p: Vec): Vec
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local HIDE = look(104, 132, 88)
		local DARK = look(76, 100, 66)
		local DAPPLE = look(132, 158, 104)
		local BELLY = look(220, 208, 152)
		local BELLY_DARK = look(198, 182, 128)
		local KNOB = look(88, 110, 74)
		local NAIL = look(238, 228, 198)
		local BEAK = look(70, 66, 58)
		local PLATE = rgb(222, 92, 50)
		local PLATE_DARK = rgb(170, 56, 38)
		local TIP = rgb(255, 186, 60)
		local SPIKE = rgb(246, 236, 206)

		local function speckle(p: Vec, chance: number): boolean
			local n = math.sin(p[1] * 12.9898 + p[2] * 78.233 + p[3] * 37.719) * 43758.5453
			return n - math.floor(n) < chance
		end
		local function top(s: Sculpt, z: number, x: number?): number
			-- Down from high above, to the first cell of clay.
			local cx, cz, y = math.floor((x or 0) / U), math.floor(z / U), math.floor(40 / U)
			while y > 0 and not s:has(cx, y, cz) do
				y -= 1
			end
			return (y + 1) * U
		end
		local function side(s: Sculpt, y: number, z: number): number
			local cx, cy, cz = 0, math.floor(y / U), math.floor(z / U)
			while s:has(cx + 1, cy, cz) do
				cx += 1
			end
			return (cx + 1) * U
		end
		-- Hide: a pale belly in bands, dark stripes down the flanks, lighter dapples over the back.
		local function hide(p: Vec, open: (number, number, number) -> boolean, belly: number): Look?
			local y, z = p[2], p[3]
			if open(0, -1, 0) and y < belly then
				return if math.floor(z / 2.4) % 2 == 0 then BELLY else BELLY_DARK
			end
			if open(0, 1, 0) and speckle(p, 0.12) then
				return DAPPLE
			end
			return nil
		end
		-- A plate standing up from the back: a triangle leaning a little back, its root sunk in, a darker band
		-- at the root and, on the big ones, a glowing point.
		local function plate(limb: Limb, s: Sculpt, z: number, x: number, tall: number, long: number, glow: boolean)
			local base = top(s, z, x) - 0.6
			local front, back = { x, base - 0.5, z + long / 2 }, { x, base - 0.5, z - long / 2 }
			local tip = { x, base + tall, z - long * 0.2 }
			triangle(limb, at(front), at(tip), at(back), 0.75 / U, PLATE)
			triangle(
				limb,
				at(vadd(front, { 0, 0, 0.12 })),
				at(vlerp(front, tip, 0.2)),
				at(vadd(back, { 0, 0, -0.12 })),
				0.95 / U,
				PLATE_DARK
			)
			if glow then
				local a, b = vlerp(front, tip, 0.6), vlerp(back, tip, 0.6)
				triangle(
					limb,
					at(vadd(a, { 0, 0, 0.1 })),
					at(vadd(tip, { 0, 0.12, 0 })),
					at(vadd(b, { 0, 0, -0.1 })),
					1.05 / U,
					TIP,
					NEON
				)
			end
		end

		-- A big body arching highest over its hips, dark bands down its flanks, and a row of bony knobs low on
		-- each side.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 16.5, -5 }, { 7, 8, 10.8 }), HIDE)
		body:add(ellipsoid({ 0, 14, 5 }, { 6.4, 6.6, 8.4 }), HIDE)
		body:add(ellipsoid({ 0, 12, -2 }, { 6.2, 4.6, 10 }), HIDE)
		body:coat(function(p, open)
			return hide(p, open, 11.5)
		end)
		for _, s in { 1, -1 } do
			for _, band in { { 8, 6 }, { 3, 1.5 }, { -2, -3.5 }, { -7, -8.5 }, { -11.5, -12.5 } } do
				body:trace({ { 0, 23, band[1] }, { 0, 18, band[2] }, { 0, 14, band[2] + 0.8 } }, { -s, 0, 0 }, DARK)
			end
		end
		for _, z in { 8, 4.5, 1, -2.5, -6, -9.5 } do
			for _, s in { 1, -1 } do
				local x = side(body, 12.5, z) * s
				body:add(rod({ { x - 0.5 * s, 12.5, z, 0.9 }, { x + 0.5 * s, 12.6, z, 0.55 } }), KNOB)
			end
		end

		-- A small head held low on a thick neck, with a dark horny beak and little bony studs down its throat.
		local head = newSculpt(U)
		head:add(rod({ { 0, 14, 9, 4.2 }, { 0, 11.5, 14, 3 }, { 0, 10.4, 17, 2.6 } }), HIDE)
		head:add(ellipsoid({ 0, 10.8, 18.8 }, { 2.6, 2.5, 3.7 }), HIDE)
		head:add(ellipsoid({ 0, 11.6, 18.2 }, { 2.3, 1.6, 2.6 }), HIDE)
		head:add(ellipsoid({ 0, 9.8, 22.3 }, { 1.75, 1.65, 2.1 }), HIDE)
		head:coat(function(p, open)
			if p[3] > 23.2 and p[2] < 11 then
				return BEAK
			end
			if open(0, -1, 0) and p[2] < 10.2 then
				return if p[3] < 15 and math.floor(p[3] / 1.4) % 2 == 0 then KNOB else BELLY
			end
			if open(0, 1, 0) and speckle(p, 0.12) then
				return DAPPLE
			end
			return nil
		end)
		head:trace({ { 0, 9.4, 19.5 }, { 0, 9.5, 23.6 } }, { -1, 0, 0 }, BEAK)
		head:trace({ { 0, 9.4, 19.5 }, { 0, 9.5, 23.6 } }, { 1, 0, 0 }, BEAK)

		-- Sturdy legs, the back ones longer, on round feet with short toes and pale nails.
		local function foot(s: Sculpt, x: number, z: number, toes: number)
			s:add(ellipsoid({ x, 1.4, z }, { 2.8, 1.4, 2.8 }), HIDE)
			for t = 1, toes do
				local dx = (t - (toes + 1) / 2) * 1.5
				s:add(ellipsoid({ x + dx, 1, z + 2.3 }, { 0.75, 0.9, 0.9 }), NAIL)
			end
		end
		local front = newSculpt(U)
		front:add(rod({ { 4.6, 12, 6, 3 }, { 5, 6, 7, 2.5 }, { 5, 2.6, 7.4, 2.4 } }), HIDE)
		foot(front, 5, 7.8, 3)
		front:add(ellipsoid({ 5.4, 7.6, 6.8 }, { 2.3, 1.8, 2.2 }), HIDE)
		local back = newSculpt(U)
		back:add(ellipsoid({ 5, 14.5, -6 }, { 3.4, 6.4, 5 }), HIDE)
		back:add(rod({ { 5.4, 10, -7.5, 3.4 }, { 5.6, 4.5, -8.4, 2.8 }, { 5.6, 2.8, -8, 2.7 } }), HIDE)
		foot(back, 5.6, -6.8, 3)
		for _, leg in { front, back } do
			leg:coat(function(p, open)
				if open(0, 1, 0) and speckle(p, 0.12) then
					return DAPPLE
				end
				return nil
			end)
		end
		back:trace({ { 0, 19, -4.5 }, { 0, 14, -6 }, { 0, 10, -7 } }, { -1, 0, 0 }, DARK)

		-- A long tail with small plates, and four spikes at the end.
		local tail = newSculpt(U)
		tail:add(
			rod({ { 0, 17.5, -13, 5 }, { 0, 15.5, -21, 3.5 }, { 0, 13.5, -29, 2.4 }, { 0, 12.5, -35, 1.3 } }),
			HIDE
		)
		tail:coat(function(p, open)
			return hide(p, open, 30)
		end)
		for _, s in { 1, -1 } do
			for _, band in { { -16, -17.5 }, { -21, -22 }, { -25.5, -26.5 } } do
				tail:trace({ { 0, 21, band[1] }, { 0, 14, band[2] } }, { -s, 0, 0 }, DARK)
			end
		end

		local frontMirror, backMirror = front:mirror(), back:mirror()
		local bodyLimb = pet:limb("Body", at({ 0, 14, -2 }))
		body:draw(bodyLimb, { head, front, frontMirror, back, backMirror, tail }, HIDE)
		local headLimb = pet:limb("Head", at({ 0, 13, 9 }))
		head:draw(headLimb, { body }, HIDE)
		for _, s in { 1, -1 } do
			local x = side(head, 11.6, 20) * s
			egg(headLimb, at({ x - 0.15 * s, 11.6, 20 }), { 0.7 / U, 1.15 / U, 1.15 / U }, nil, EYE)
			egg(headLimb, at({ x + 0.12 * s, 12, 20.3 }), { 0.3 / U, 0.4 / U, 0.4 / U }, nil, SHINE)
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", at({ 4.6, 11, 6 }), function(limb)
			front:draw(limb, { body }, HIDE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", at({ 5, 12, -6 }), function(limb)
			back:draw(limb, { body }, HIDE)
		end)
		local tailLimb = pet:limb("Tail", at({ 0, 16, -13 }))
		tail:draw(tailLimb, { body }, HIDE)

		-- Two staggered rows of plates from the neck to the tail, tallest over the hips.
		plate(headLimb, head, 11.5, -0.7, 3.2, 3.4, false)
		plate(headLimb, head, 14.2, 0.7, 2.4, 2.8, false)
		for index, z in { 8.5, 5.2, 1.9, -1.4, -4.7, -8, -11.3 } do
			local x = if index % 2 == 0 then 0.8 else -0.8
			local tall = ({ 5.5, 7.5, 9.5, 11, 11, 9.5, 7.5 })[index]
			plate(bodyLimb, body, z, x, tall, 5.4, index >= 2 and index <= 6)
		end
		for index, z in { -15.5, -19.5, -23.5, -27 } do
			plate(tailLimb, tail, z, if index % 2 == 0 then 0.6 else -0.6, ({ 6, 4.6, 3.4, 2.4 })[index], 4.2, false)
		end
		for _, s in { 1, -1 } do
			for _, spike in { { -30.5, 13.6, -33, 1.4 }, { -33.5, 13.2, -37.5, 1.2 } } do
				local root = { 1 * s, spike[2], spike[1] }
				local point = { 6 * s, spike[2] + 3.4, spike[3] }
				taper(tailLimb, at(root), at(point), spike[4] / U, spike[4] / U, { 0, 1, 0 }, SPIKE)
			end
		end

		pet:light(TIP, 1.8, 18)
		pet:seat(0, 23 / U, -3 / U)
	end,
}

Designs.Brachiosaurus = {
	name = "Brachiosaurus",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.48 * 1.2,
	draw = function(pet)
		-- Sculpted in finer units than it is built in (1.2 of them to a block), with leaves of parts at any angle.
		local U = 1.2
		local T = inUnits(U)
		local HIDE = look(110, 150, 170)
		local DARK = look(76, 108, 132)
		local BELLY = look(222, 224, 196)
		local LIGHT = look(150, 186, 200)
		local NAIL = look(236, 228, 206)
		local MOUTH = look(60, 70, 84)
		local LEAF = rgb(96, 168, 72)
		local LEAF_DARK = rgb(66, 130, 56)
		local TWIG = rgb(122, 88, 56)

		-- Dappled hide: big darker patches, a pale belly and throat.
		local function hide(p: Vec, open: (number, number, number) -> boolean): Look?
			if open(0, -1, 0) or (open(0, 0, 1) and p[2] > 22) then
				return BELLY
			end
			local n = noise({ math.floor(p[1] / 2.4), math.floor(p[2] / 2.4), math.floor(p[3] / 2.4) })
			if n < 0.28 then
				return DARK
			elseif n > 0.9 then
				return LIGHT
			end
			return nil
		end

		-- A great body, its shoulders higher than its hips.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 20, -1 }, { 6.4, 6.6, 10 }), HIDE)
		body:add(ellipsoid({ 0, 23.6, 4.6 }, { 5.4, 4.4, 5.4 }), HIDE)
		body:add(ellipsoid({ 0, 20, -8 }, { 5.6, 5.8, 5 }), HIDE)
		body:coat(hide)

		-- A neck rising high and a small head with a domed crest.
		local head = newSculpt(U)
		head:add(rod({ { 0, 24, 8, 3.9 }, { 0, 30, 11, 2.9 }, { 0, 37, 13, 2.3 }, { 0, 42.4, 14, 2.05 } }), HIDE)
		head:add(ellipsoid({ 0, 44.2, 15.8 }, { 2.1, 1.9, 3.3 }), HIDE)
		head:add(ellipsoid({ 0, 45.9, 15.2 }, { 1.45, 1.2, 1.6 }), HIDE)
		head:coat(function(p, open)
			if p[3] > 15.6 and p[2] < 43.7 and (open(1, 0, 0) or open(-1, 0, 0)) and p[2] > 43 then
				return MOUTH
			end
			return hide(p, open)
		end)

		local function foot(s: Sculpt, x: number, z: number)
			s:add(ellipsoid({ x, 1.4, z }, { 2.9, 1.4, 3.1 }), HIDE)
			for _, dx in { -1.4, 0, 1.4 } do
				s:add(ellipsoid({ x + dx, 0.9, z + 2.6 }, { 0.75, 0.9, 0.7 }), NAIL)
			end
		end
		local front = newSculpt(U)
		front:add(rod({ { 4.6, 22, 5, 3.1 }, { 4.8, 12, 5.6, 2.7 }, { 4.8, 2.6, 5.4, 2.6 } }), HIDE)
		foot(front, 4.8, 5.8)
		local back = newSculpt(U)
		back:add(ellipsoid({ 4.6, 19, -8 }, { 3.3, 5.2, 4.1 }), HIDE)
		back:add(rod({ { 4.8, 14, -9, 2.8 }, { 4.9, 2.6, -8.6, 2.6 } }), HIDE)
		foot(back, 4.9, -8.4)
		for _, leg in { front, back } do
			leg:coat(function(p, open)
				return if p[2] > 2.4 then hide(p, open) else nil
			end)
		end

		local tail = newSculpt(U)
		tail:add(
			rod({ { 0, 20, -13, 4.1 }, { 0, 18, -20, 2.7 }, { -1, 15.6, -27, 1.7 }, { -2.6, 14.4, -32, 0.8 } }),
			HIDE
		)
		tail:coat(hide)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", T.at({ 0, 20, 0 })), { head, front, frontMirror, back, backMirror, tail }, HIDE)
		local headLimb = pet:limb("Head", T.at({ 0, 24, 8 }))
		head:draw(headLimb, { body }, HIDE)
		roundEyes(headLimb, head, 45, 16.4, 1)
		-- A sprig of leaves in its mouth.
		local mouth = { -1.2, 43.4, 18.6 }
		T.branch(
			headLimb,
			{ mouth, vadd(mouth, { -2, 0.4, 1 }), vadd(mouth, { -3.8, 1.2, 1.4 }) },
			0.35,
			{ 0, 1, 0 },
			TWIG
		)
		for index, leaf in { { -2, 0.6, 1.2 }, { -3, 0.9, 1.3 }, { -3.8, 1.2, 1.5 }, { -1.4, 0.3, 0.9 } } do
			T.ball(headLimb, vadd(mouth, leaf), { 1.6, 0.4, 1 }, if index % 2 == 0 then LEAF_DARK else LEAF)
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", T.at({ 4.6, 22, 5 }), function(limb)
			front:draw(limb, { body }, HIDE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", T.at({ 4.6, 19, -8 }), function(limb)
			back:draw(limb, { body }, HIDE)
		end)
		tail:draw(pet:limb("Tail", T.at({ 0, 20, -12 })), { body }, HIDE)

		pet:light(LEAF, 1.8, 18)
		pet:particles("Leaves", LEAF, 8)
		pet:seat(0, 28 / U, -1 / U)
	end,
}

Designs.TRex = {
	name = "T-Rex",
	skeleton = "Theropod",
	gait = "Stomp",
	scale = 0.42 * 1.2,
	draw = function(pet)
		-- Modelled in finer units than it is built in: 1.2 of them to a block.
		local U = 1.2
		local function at(p: Vec): Vec
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local SCALE = look(84, 70, 56)
		local DARK = look(44, 36, 30)
		local STRIPE = look(156, 40, 30)
		local BELLY = look(198, 166, 118)
		local BELLY_DARK = look(166, 132, 92)
		local TOOTH = look(246, 240, 222)
		local GUM = look(150, 36, 38)
		local MOUTH = look(70, 12, 16)
		local CLAW = look(30, 26, 24)
		local SCAR = look(196, 176, 150)
		local AMBER = rgb(255, 172, 30)

		local function underside(p: Vec, along: number): Look
			return if math.floor(p[along] / 1.8) % 2 == 0 then BELLY else BELLY_DARK
		end
		-- Tiger stripes: lines traced down both sides from the spine.
		local function stripes(s: Sculpt, list: { { Vec } })
			for _, side in { 1, -1 } do
				for _, stripe in list do
					s:trace(stripe, { -side, 0, 0 }, STRIPE)
				end
			end
		end

		-- A deep, heavy body over the hips, banded with crimson stripes, a pale belly in plates, and a row of dark
		-- bony scutes down its spine.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 22, -4 }, { 6, 6.5, 8 }), SCALE)
		body:add(ellipsoid({ 0, 20.6, 5 }, { 6.6, 8.2, 8.5 }), SCALE)
		body:add(ellipsoid({ 0, 25.5, 2 }, { 4.6, 3.6, 9 }), SCALE)
		body:coat(function(p, open)
			if open(0, -1, 0) and p[2] < 19 then
				return underside(p, 3)
			end
			return nil
		end)
		stripes(body, {
			{ { 0, 28.5, 10 }, { 0, 24, 11 }, { 0, 19.5, 12.5 } },
			{ { 0, 29, 5.5 }, { 0, 24, 6 }, { 0, 17.5, 7.5 } },
			{ { 0, 29, 1 }, { 0, 24.5, 1 }, { 0, 17, 2.5 } },
			{ { 0, 28.5, -3.5 }, { 0, 24.5, -4 }, { 0, 19, -3 } },
			{ { 0, 27.5, -8 }, { 0, 23.5, -9 }, { 0, 19.5, -8.5 } },
		})
		local function top(s: Sculpt, z: number, x: number?): number
			local cx, cz, y = math.floor((x or 0) / U), math.floor(z / U), math.floor(20 / U)
			while s:has(cx, y + 1, cz) do
				y += 1
			end
			return (y + 1) * U
		end
		for _, z in { 10, 6.5, 3, -0.5, -4, -7.5, -10.5 } do
			local y = top(body, z) - 0.5
			body:add(rod({ { 0, y, z, 0.9 }, { 0, y + 1.6, z - 1, 0.3 } }), DARK)
		end

		-- A thick neck and a huge head: a deep skull, wide at the jaw muscles, heavy brows and horn knobs over
		-- small glowing eyes, scarred cheeks, and jaws thrown open on rows of fangs.
		local head = newSculpt(U)
		head:add(rod({ { 0, 22, 9, 5 }, { 0, 25.5, 13, 4.6 }, { 0, 28, 16, 4.2 } }), SCALE)
		-- The head is drawn 1.12 times the size of the numbers below, about the top of the neck.
		local H, centre = 1.12, { 0, 28, 17 }
		local function hp(q: Vec): Vec
			return {
				centre[1] + (q[1] - centre[1]) * H,
				centre[2] + (q[2] - centre[2]) * H,
				centre[3] + (q[3] - centre[3]) * H,
			}
		end
		local function E(c: Vec, r: Vec): Shape
			return ellipsoid(hp(c), { r[1] * H, r[2] * H, r[3] * H })
		end
		local function R(points: { { number } }): Shape
			local out = {}
			for _, q in points do
				local m = hp(q)
				table.insert(out, { m[1], m[2], m[3], q[4] * H })
			end
			return rod(out)
		end
		head:add(E({ 0, 30, 19.5 }, { 4.3, 4.1, 5 }), SCALE)
		head:add(E({ 0, 30.4, 24 }, { 3.5, 3.3, 5.4 }), SCALE)
		head:add(E({ 0, 29.8, 28.6 }, { 2.8, 2.6, 3.6 }), SCALE)
		head:add(E({ 0, 32.4, 22.5 }, { 2.6, 1.6, 5.5 }), SCALE)
		head:add(E({ 0, 23.7, 23.5 }, { 3.5, 1.8, 6.6 }), SCALE)
		head:add(E({ 0, 25.4, 18.5 }, { 3.6, 2.6, 3.4 }), SCALE)
		head:carve(E({ 0, 26.5, 25.2 }, { 2.7, 1.7, 6 }))
		head:paint(E({ 0, 26.5, 25.2 }, { 3.2, 2.2, 6.5 }), GUM, nil, true)
		head:paint(E({ 0, 26, 23 }, { 2, 1.3, 4.6 }), MOUTH, nil, true)
		for _, s in { 1, -1 } do
			head:add(R({ { 2.5 * s, 33.2, 19.8, 1.2 }, { 2.4 * s, 33.4, 23.6, 0.8 } }), DARK)
			head:add(R({ { 3 * s, 33.6, 19, 0.9 }, { 3.3 * s, 35, 18.2, 0.35 } }), DARK)
			for _, z in { 20.8, 23, 25.2, 27.4, 29.4 } do
				local inset = if z > 28 then 0.5 else 0
				head:add(R({ { (2.3 - inset) * s, 27.8, z, 0.5 }, { (2.15 - inset) * s, 26.2, z + 0.3, 0.2 } }), TOOTH)
			end
			for _, z in { 22, 24.2, 26.4 } do
				head:add(R({ { 2.1 * s, 25.2, z, 0.45 }, { 2 * s, 26.6, z + 0.3, 0.2 } }), TOOTH)
			end
			head:add(R({ { 0.8 * s, 27.8, 31.2, 0.45 }, { 0.7 * s, 26.3, 31.5, 0.2 } }), TOOTH)
		end
		head:coat(function(real, open)
			local x = centre[1] + (real[1] - centre[1]) / H
			local y = centre[2] + (real[2] - centre[2]) / H
			local z = centre[3] + (real[3] - centre[3]) / H
			-- Nostrils at the tip of the snout.
			if z > 30.6 and y > 30.4 and math.abs(x) > 0.5 and math.abs(x) < 1.7 then
				return DARK
			end
			-- A pale throat and chin.
			if open(0, -1, 0) and y < 24.5 and z < 28 then
				return underside(real, 3)
			end
			return nil
		end)
		stripes(head, {
			{ { 0, 29, 12 }, { 0, 25, 13 }, { 0, 21, 13 } },
			{ { 0, 31, 16 }, { 0, 27.5, 16.5 } },
			{ hp({ 0, 34, 20.5 }), hp({ 0, 31.5, 18 }) },
		})
		-- Old scars clawed across its cheek and snout.
		for _, side in { 1, -1 } do
			head:trace({ hp({ 0, 31.8, 25.5 }), hp({ 0, 29.2, 27.6 }) }, { -side, 0, 0 }, SCAR)
		end
		head:trace({ hp({ 0, 32.2, 23 }), hp({ 0, 30.4, 25.4 }) }, { -1, 0, 0 }, SCAR)

		-- Small, clawed arms held tucked up against its chest.
		local arm = newSculpt(U)
		arm:add(rod({ { 4.2, 19.5, 10.5, 1.4 }, { 5.3, 16.6, 12.6, 1.05 }, { 5.1, 15.8, 15, 0.85 } }), SCALE)
		for _, dx in { -0.45, 0.45 } do
			arm:add(rod({ { 5.1 + dx, 15.6, 15.4, 0.45 }, { 5 + dx, 14.6, 16.6, 0.22 } }), CLAW)
		end

		-- Massive legs: a thick thigh, a shin slanting back, and a foot of three clawed toes with a spur behind.
		local leg = newSculpt(U)
		leg:add(ellipsoid({ 5.4, 18.5, -3 }, { 3.8, 7, 6 }), SCALE)
		leg:add(rod({ { 5.8, 14.5, -4, 3.5 }, { 6.1, 7, -8, 2.4 } }), SCALE)
		leg:add(rod({ { 6.1, 7, -8, 2.1 }, { 6.1, 2.2, -5.5, 1.8 } }), SCALE)
		for _, dx in { -1.5, 0, 1.5 } do
			leg:add(rod({ { 6.1 + dx, 1.7, -5, 1.05 }, { 6.1 + dx * 1.3, 1.25, -1.6, 0.85 } }), SCALE)
			leg:add(rod({ { 6.1 + dx * 1.3, 1.3, -1.4, 0.6 }, { 6.1 + dx * 1.4, 0.35, 0.4, 0.25 } }), CLAW)
		end
		leg:add(rod({ { 6.1, 1.9, -6.8, 0.65 }, { 6.2, 0.6, -8.3, 0.3 } }), CLAW)
		leg:coat(function(p, open)
			if open(0, -1, 0) and p[2] > 12 then
				return underside(p, 3)
			end
			return nil
		end)
		leg:trace({ { 0, 23, -1 }, { 0, 18.5, -2.5 }, { 0, 14.5, -2 } }, { -1, 0, 0 }, STRIPE)
		leg:trace({ { 0, 22.5, -5.5 }, { 0, 17.5, -6.5 } }, { -1, 0, 0 }, STRIPE)

		-- A long, heavy tail held out behind for balance, swinging a little to one side, scuted along the top.
		local tail = newSculpt(U)
		local spine = {
			{ 0, 23, -9, 5.2 },
			{ 0, 22, -16, 4.2 },
			{ 0.8, 20.5, -23, 3.2 },
			{ 2.2, 19, -30, 2.3 },
			{ 3.6, 18, -36, 1.4 },
			{ 4.4, 17.6, -40, 0.6 },
		}
		tail:add(rod(spine), SCALE)
		tail:coat(function(p, open)
			if open(0, -1, 0) then
				return underside(p, 3)
			end
			return nil
		end)
		for index = 2, #spine - 1 do
			local a, b = spine[index - 1], spine[index]
			local mid = vlerp(a, b, 0.5)
			for _, q in { mid, b } do
				local y = top(tail, q[3], q[1]) - 0.4
				tail:add(rod({ { q[1], y, q[3], 0.7 }, { q[1], y + 1.2, q[3] - 0.8, 0.25 } }), DARK)
			end
		end
		stripes(tail, {
			{ { 0, 28, -13 }, { 0, 21, -14 }, { 0, 18, -13 } },
			{ { 0, 26, -18.5 }, { 0, 20, -19.5 }, { 0, 17.5, -19 } },
			{ { 0, 24, -24 }, { 0, 19, -25 }, { 0, 17, -24.5 } },
			{ { 0, 22, -29 }, { 0, 17.5, -30 } },
			{ { 0, 20.5, -33.5 }, { 0, 17, -34.5 } },
		})

		local legMirror, armMirror = leg:mirror(), arm:mirror()
		body:draw(pet:limb("Body", at({ 0, 22, 0 })), { head, leg, legMirror, arm, armMirror, tail }, SCALE)
		local headLimb = pet:limb("Head", at({ 0, 23, 10 }))
		head:draw(headLimb, { body }, SCALE)
		-- Small, deep-set eyes: flat glowing slits slanting up towards the back, each in a dark rim.
		for _, s in { 1, -1 } do
			local out = { s, 0, 0 }
			local eye = hp({ 0, 31.3, 21.6 })
			local cy, cz = math.floor(eye[2] / U), math.floor(eye[3] / U)
			local cx = 6
			while not head:has(if s > 0 then cx else -1 - cx, cy, cz) and cx > 0 do
				cx -= 1
			end
			local depth = (cx + 1) * U - 0.03
			local function slit(grow: number, color: Color, material: string?, thick: number)
				local nose = hp({ 0, 30.9 - grow * 0.2, 23 + grow })
				local backPoint = hp({ 0, 31.8 + grow * 0.2, 20.2 - grow })
				nose[1], backPoint[1] = s * (depth + thick / 2), s * (depth + thick / 2)
				local p1, p2 = vlerp(nose, backPoint, 0.3), vlerp(nose, backPoint, 0.7)
				local width = (0.95 + grow) * H
				taper(headLimb, at(p1), at(nose), width / U, thick / U, out, color, material)
				blade(headLimb, at(p1), at(p2), width / U, thick / U, out, color, material)
				taper(headLimb, at(p2), at(backPoint), width / U, thick / U, out, color, material)
			end
			slit(0.4, CLAW.color, nil, 0.16)
			slit(0, AMBER, NEON, 0.3)
		end
		pet:limbPair("LeftArm", "RightArm", at({ 4.4, 19.5, 10.5 }), function(limb)
			arm:draw(limb, { body }, SCALE)
		end)
		pet:limbPair("LeftLeg", "RightLeg", at({ 5.2, 20, -3 }), function(limb)
			leg:draw(limb, { body }, SCALE)
		end)
		tail:draw(pet:limb("Tail", at({ 0, 22, -10 })), { body }, SCALE)

		pet:light(rgb(255, 150, 40), 2.4, 22)
		pet:particles("Leaves", rgb(110, 176, 70), 10)
		pet:seat(0, 30 / U, -2 / U)
	end,
}

Designs.Mosasaurus = {
	name = "Mosasaurus",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 4,
	scale = 0.42,
	draw = function(pet)
		-- Modelled in the units it is built in: one to a block.
		local U = 1
		local function at(p: Vec): Vec
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local BACK = look(28, 58, 90)
		local SIDE = look(42, 90, 126)
		local BELLY = look(206, 228, 228)
		local STRIPE = look(20, 42, 68)
		local GLOW = look(80, 236, 255, NEON)
		local PALE_GLOW = look(190, 255, 250, NEON)
		local FIN = look(30, 66, 100)
		local TOOTH = look(242, 240, 228)
		local GUM = look(150, 52, 72)
		local MOUTH = look(54, 18, 32)

		-- Dark above, pale below, and rows of glowing spots down each flank, like the lights of deep-sea fish.
		local function skin(p: Vec, open: (number, number, number) -> boolean, middle: number): Look?
			local y, z = p[2], p[3]
			if open(0, -1, 0) and y < middle then
				return BELLY
			end
			if open(0, 1, 0) and not open(1, 0, 0) and not open(-1, 0, 0) then
				return if math.floor(z / 3) % 2 == 0 then BACK else STRIPE
			end
			if math.abs(y - middle - 1) < 0.75 and (z % 3.2) < 1.3 and (open(1, 0, 0) or open(-1, 0, 0)) then
				return GLOW
			end
			return nil
		end

		-- A long, streamlined body with its back flippers, and a low glowing crest down its spine.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 10.5, 4 }, { 6.4, 7, 11.5 }), SIDE)
		body:add(ellipsoid({ 0, 10.2, -8 }, { 5.6, 6.2, 9.5 }), SIDE)
		for _, s in { 1, -1 } do
			body:add(
				ellipsoid({ 0, 0, 0 }, { 4.2, 0.75, 2.2 }),
				GLOW,
				{ origin = { 7.2 * s, 5.2, -9.4 }, yaw = 0.6 * s, roll = -0.5 * s }
			)
			body:add(
				ellipsoid({ 0, 0, 0 }, { 3.7, 0.95, 1.8 }),
				FIN,
				{ origin = { 7 * s, 5.3, -9.2 }, yaw = 0.6 * s, roll = -0.5 * s }
			)
		end
		body:coat(function(p, open)
			return skin(p, open, 10)
		end)
		for _, z in { 10, 6.5, 3, -0.5, -4, -7.5, -11 } do
			local top = math.floor(10 / U)
			while body:has(0, top + 1, math.floor(z / U)) do
				top += 1
			end
			local y = (top + 1) * U - 0.4
			body:add(rod({ { 0, y, z, 0.8 }, { 0, y + 1, z - 1.2, 0.35 } }), GLOW)
		end

		-- A crocodile's head on a thick neck: long jaws open on rows of teeth, glowing eyes, and glowing spots
		-- running down its snout.
		local head = newSculpt(U)
		head:add(rod({ { 0, 10.4, 12, 5.4 }, { 0, 10.6, 17, 4.5 } }), SIDE)
		head:add(ellipsoid({ 0, 11.2, 20.5 }, { 4, 3.6, 5.8 }), SIDE)
		head:add(ellipsoid({ 0, 11, 26.5 }, { 2.6, 2.2, 5.2 }), SIDE)
		head:add(ellipsoid({ 0, 10.8, 31 }, { 1.9, 1.7, 2.6 }), SIDE)
		head:add(ellipsoid({ 0, 6.9, 23.5 }, { 3.1, 1.5, 8.2 }), SIDE)
		head:carve(ellipsoid({ 0, 8.9, 25.5 }, { 2.3, 1.5, 7.4 }))
		head:paint(ellipsoid({ 0, 8.9, 25.5 }, { 2.8, 2, 7.9 }), GUM, nil, true)
		head:paint(ellipsoid({ 0, 8.5, 24 }, { 1.6, 1.1, 5.4 }), MOUTH, nil, true)
		for _, s in { 1, -1 } do
			for _, z in { 19.5, 21.6, 23.7, 25.8, 27.9, 30 } do
				local inset = (z - 19) * 0.07
				head:add(rod({ { (2.1 - inset) * s, 10.2, z, 0.45 }, { (2 - inset) * s, 8.6, z + 0.3, 0.18 } }), TOOTH)
			end
			for _, z in { 20.5, 22.6, 24.7, 26.8, 28.9 } do
				head:add(
					rod({
						{ (1.9 - (z - 19) * 0.07) * s, 7.8, z, 0.42 },
						{ (1.8 - (z - 19) * 0.07) * s, 9.2, z + 0.3, 0.18 },
					}),
					TOOTH
				)
			end
		end
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			-- Glowing spots in a row down the top of its snout.
			if open(0, 1, 0) and z > 21 and math.abs(x) < 0.7 and (z % 2.6) < 1.3 then
				return PALE_GLOW
			end
			if open(0, -1, 0) and y < 9.5 then
				return BELLY
			end
			if open(0, 1, 0) and not open(1, 0, 0) and not open(-1, 0, 0) then
				return BACK
			end
			return nil
		end)

		-- Paddle flippers, edged with light.
		local flipper = newSculpt(U)
		local frame = { origin = { 10, 4.6, 6 }, yaw = 0.55, roll = -0.5 }
		flipper:add(rod({ { 4.8, 7.4, 8.4, 2.2 }, { 7.6, 5.8, 7.2, 1.6 } }), SIDE)
		flipper:add(ellipsoid({ 0, 0, 0 }, { 6.4, 0.75, 3.2 }), GLOW, frame)
		flipper:add(ellipsoid({ 0, 0, 0 }, { 5.8, 0.95, 2.7 }), FIN, frame)

		-- A long tail bending down at the end into a shark-like fluke, its upper lobe glowing along the edge.
		local tail = newSculpt(U)
		tail:add(
			rod({
				{ 0, 9.8, -14, 4.6 },
				{ 0, 9.6, -22, 3.5 },
				{ 0, 9, -30, 2.5 },
				{ 0, 7.8, -36, 1.7 },
				{ 0, 5.4, -40.5, 1.1 },
			}),
			SIDE
		)
		tail:add(ellipsoid({ 0, 0, 0 }, { 0.7, 5, 2 }), GLOW, { origin = { 0, 11.2, -40.6 }, pitch = 0.75 })
		tail:add(ellipsoid({ 0, 0, 0 }, { 0.95, 4.4, 1.6 }), FIN, { origin = { 0, 10.9, -40.2 }, pitch = 0.75 })
		tail:add(ellipsoid({ 0, 0, 0 }, { 0.95, 3.8, 1.5 }), FIN, { origin = { 0, 3, -42.3 }, pitch = -0.6 })
		tail:coat(function(p, open)
			if p[3] < -38 then
				return nil
			end
			return skin(p, open, 9.2)
		end)

		local flipperMirror = flipper:mirror()
		body:draw(pet:limb("Body", at({ 0, 10, 0 })), { head, flipper, flipperMirror, tail }, SIDE)
		local headLimb = pet:limb("Head", at({ 0, 10, 12 }))
		head:draw(headLimb, { body }, SIDE)
		-- Narrow glowing eyes set in dark rims.
		for _, s in { 1, -1 } do
			local out = { s, 0, 0 }
			local cy, cz = math.floor(12 / U), math.floor(20.5 / U)
			local cx = 6
			while not head:has(if s > 0 then cx else -1 - cx, cy, cz) and cx > 0 do
				cx -= 1
			end
			local depth = (cx + 1) * U - 0.03
			local function almond(grow: number, color: Color, material: string?, thick: number)
				local nose = { s * (depth + thick / 2), 11.7 - grow * 0.2, 22.4 + grow }
				local backPoint = { s * (depth + thick / 2), 12.5 + grow * 0.2, 18.8 - grow }
				local p1, p2 = vlerp(nose, backPoint, 0.3), vlerp(nose, backPoint, 0.7)
				local width = 1 + grow
				taper(headLimb, at(p1), at(nose), width / U, thick / U, out, color, material)
				blade(headLimb, at(p1), at(p2), width / U, thick / U, out, color, material)
				taper(headLimb, at(p2), at(backPoint), width / U, thick / U, out, color, material)
			end
			almond(0.4, STRIPE.color, nil, 0.16)
			almond(0, PALE_GLOW.color, NEON, 0.3)
		end
		pet:limbPair("LeftFin", "RightFin", at({ 5, 7.4, 8.2 }), function(limb)
			flipper:draw(limb, { body }, SIDE)
		end)
		tail:draw(pet:limb("Tail", at({ 0, 10, -14 })), { body }, SIDE)

		pet:light(rgb(80, 220, 255), 3, 24)
		pet:particles("Bubbles", rgb(150, 245, 255), 16)
		pet:seat(0, 17.5 / U, 0)
	end,
}

Designs.LunarDragon = {
	name = "Lunar Dragon",
	skeleton = "Dragon",
	gait = "Walk",
	scale = 0.42 * 1.2,
	draw = function(pet)
		-- Modelled in finer units than it is built in: 1.2 of them to a block.
		local U = 1.2
		local function at(p: Vec): Vec
			return { p[1] / U, p[2] / U, p[3] / U }
		end
		local NIGHT = look(38, 42, 96)
		local NIGHT_DARK = look(26, 28, 68)
		local SILVER = look(212, 220, 240)
		local SILVER_DARK = look(164, 174, 206)
		local MOON = look(236, 242, 255, NEON)
		local STAR = look(255, 244, 200, NEON)
		local GLOW = look(150, 190, 255, NEON)
		local CLAW = look(30, 30, 52)
		local MOONFIRE, MOONFIRE_CORE = rgb(110, 160, 255), rgb(235, 245, 255)

		-- A steady scatter of stars over its scales: the same cells every time.
		local function twinkle(p: Vec, chance: number): boolean
			local n = math.sin(p[1] * 12.9898 + p[2] * 78.233 + p[3] * 37.719) * 43758.5453
			return n - math.floor(n) < chance
		end
		-- Silver plates under its belly, and stars on its back.
		local function scales(p: Vec, open: (number, number, number) -> boolean, belly: number): Look?
			if open(0, -1, 0) and p[2] < belly then
				return if math.floor(p[3] / 1.6) % 2 == 0 then SILVER else SILVER_DARK
			end
			if open(0, 1, 0) and twinkle(p, 0.07) then
				return STAR
			end
			if not open(0, 1, 0) and (open(1, 0, 0) or open(-1, 0, 0)) and math.floor(p[2] / 1.2) % 3 == 0 then
				return NIGHT_DARK
			end
			return nil
		end
		-- A crescent moon on the side of a limb: inside one circle and outside another, nudged up and back.
		local function crescent(p: Vec, y: number, z: number, r: number): boolean
			local dy, dz = p[2] - y, p[3] - z
			local ey, ez = dy - r * 0.35, dz + r * 0.35
			return dy * dy + dz * dz <= r * r and ey * ey + ez * ez > (r * 0.8) ^ 2
		end
		local function top(s: Sculpt, z: number, x: number?): number
			local cx, cz, y = math.floor((x or 0) / U), math.floor(z / U), math.floor(12 / U)
			while s:has(cx, y + 1, cz) do
				y += 1
			end
			return (y + 1) * U
		end
		-- A mane of glowing fins down its spine.
		local function mane(s: Sculpt, points: { Vec }, tall: number)
			for _, q in points do
				local y = top(s, q[3], q[1]) - 0.5
				s:add(rod({ { q[1], y, q[3], 0.75 }, { q[1], y + tall, q[3] - 1.6, 0.25 } }), GLOW)
				s:add(rod({ { q[1], y - 0.2, q[3], 0.8 }, { q[1], y + tall * 0.45, q[3] - 0.7, 0.5 } }), SILVER)
			end
		end

		-- A long, slender body of midnight scales scattered with stars, a silver belly, a glowing crescent moon on
		-- each shoulder and a mane of light down its back.
		local body = newSculpt(U)
		body:add(ellipsoid({ 0, 15.5, 3 }, { 5, 5.6, 7.2 }), NIGHT)
		body:add(ellipsoid({ 0, 18.5, 2 }, { 4.2, 3, 6 }), NIGHT)
		body:add(ellipsoid({ 0, 15, -4 }, { 4.5, 5, 7 }), NIGHT)
		body:add(ellipsoid({ 0, 15, -10 }, { 4.8, 5.2, 5 }), NIGHT)
		body:coat(function(p, open)
			if (open(1, 0, 0) or open(-1, 0, 0)) and crescent(p, 16.5, 4.5, 3) then
				return MOON
			end
			return scales(p, open, 13.5)
		end)
		mane(body, { { 0, 0, 8 }, { 0, 0, 4.5 }, { 0, 0, 1 }, { 0, 0, -2.5 }, { 0, 0, -6 }, { 0, 0, -9.5 } }, 3.2)

		-- A long neck rising high and a sleek head: crescent horns sweeping back and up, tipped with moonfire,
		-- glowing fins at its cheeks, a fang showing at each side of its jaw.
		local head = newSculpt(U)
		head:add(rod({ { 0, 18, 6, 3.4 }, { 0, 23, 10, 2.8 }, { 0, 27.5, 12, 2.5 }, { 0, 30, 14.5, 2.4 } }), NIGHT)
		head:add(ellipsoid({ 0, 31.5, 17 }, { 2.9, 2.5, 3.7 }), NIGHT)
		head:add(ellipsoid({ 0, 32.6, 18.6 }, { 2.7, 0.9, 1.9 }), NIGHT)
		head:add(ellipsoid({ 0, 31.2, 21.6 }, { 1.95, 1.6, 3.9 }), NIGHT)
		head:add(ellipsoid({ 0, 29.7, 19.6 }, { 2.2, 1.2, 4.1 }), NIGHT)
		local hornTips = {}
		for _, s in { 1, -1 } do
			local horn = {
				{ 1.6 * s, 33, 16.4, 1.15 },
				{ 2.9 * s, 34.6, 13.4, 1 },
				{ 3.6 * s, 36.6, 11.2, 0.85 },
				{ 3.4 * s, 39, 10.6, 0.65 },
				{ 2.6 * s, 40.8, 12, 0.4 },
			}
			head:add(rod(horn), SILVER)
			head:add(rod({ horn[4], horn[5] }), MOON)
			table.insert(hornTips, { horn[5][1], horn[5][2] + 0.6, horn[5][3] })
			head:add(
				rod({ { 2.1 * s, 30, 17.4, 0.6 }, { 3.6 * s, 29.4, 13.8, 0.4 }, { 4.2 * s, 28.4, 11.6, 0.2 } }),
				GLOW
			)
			head:add(rod({ { 2.4 * s, 31.4, 15.6, 0.5 }, { 3.6 * s, 31.6, 13.2, 0.2 } }), SILVER)
			head:add(rod({ { 1.25 * s, 30.3, 23.6, 0.42 }, { 1.15 * s, 29.3, 23.9, 0.2 } }), SILVER)
		end
		head:coat(function(p, open)
			local x, y, z = p[1], p[2], p[3]
			-- Glowing nostrils, and a silver line along its lips.
			if z > 24.6 and y > 31.6 and math.abs(x) > 0.4 and math.abs(x) < 1.4 then
				return GLOW
			end
			if open(0, -1, 0) and y < 30 then
				return SILVER
			end
			if not open(0, 1, 0) and (open(1, 0, 0) or open(-1, 0, 0)) and math.abs(y - 30.5) < 0.5 and z > 18 then
				return SILVER_DARK
			end
			if open(0, -1, 0) and z < 15.5 and y < 27 then
				return if math.floor(y / 1.6) % 2 == 0 then SILVER else SILVER_DARK
			end
			return scales(p, open, 0)
		end)
		mane(head, { { 0, 0, 8.6 }, { 0, 0, 10.8 }, { 0, 0, 12.6 } }, 2.4)

		-- Slender legs with silver-banded wrists and dark claws.
		local function foot(s: Sculpt, x: number, y: number, z: number)
			s:add(ellipsoid({ x, y, z }, { 1.9, 1.3, 2.5 }), NIGHT)
			for _, dx in { -1.1, 0, 1.1 } do
				s:add(rod({ { x + dx, y - 0.1, z + 1.2, 0.75 }, { x + dx * 1.25, y - 0.4, z + 2.7, 0.6 } }), NIGHT)
				s:add(
					rod({ { x + dx * 1.25, y - 0.35, z + 2.7, 0.45 }, { x + dx * 1.35, y - 1.15, z + 3.8, 0.2 } }),
					CLAW
				)
			end
		end
		local front = newSculpt(U)
		front:add(rod({ { 4.4, 15, 5, 2.5 }, { 5.2, 9, 6.5, 1.9 } }), NIGHT)
		front:add(rod({ { 5.2, 9, 6.5, 1.8 }, { 5.4, 3, 6.1, 1.5 } }), NIGHT)
		front:add(rod({ { 5.3, 4.8, 6.2, 1.75 }, { 5.4, 4, 6.15, 1.7 } }), SILVER)
		foot(front, 5.4, 1.3, 7.6)
		front:coat(function(p, open)
			return scales(p, open, 0)
		end)
		local back = newSculpt(U)
		back:add(ellipsoid({ 4.8, 13, -10 }, { 2.6, 4.6, 3.8 }), NIGHT)
		back:add(rod({ { 5.2, 9.5, -12, 1.9 }, { 5.4, 3.4, -13.6, 1.5 } }), NIGHT)
		back:add(rod({ { 5.4, 3.4, -13.6, 1.4 }, { 5.4, 1.6, -11.4, 1.3 } }), NIGHT)
		back:add(rod({ { 5.4, 4.6, -13.3, 1.65 }, { 5.4, 3.9, -13.5, 1.6 } }), SILVER)
		foot(back, 5.4, 1.3, -10.6)
		back:coat(function(p, open)
			return scales(p, open, 0)
		end)

		-- A long tail curling to one side, with a mane down it, ending in a glowing crescent moon.
		local tail = newSculpt(U)
		local spine = {
			{ 0, 15, -13, 3.2 },
			{ 0, 14, -19, 2.6 },
			{ -1.5, 11.5, -25, 2 },
			{ -3.5, 9, -30, 1.5 },
			{ -4.8, 8, -34, 1 },
			{ -5, 8.8, -37, 0.6 },
		}
		tail:add(rod(spine), NIGHT)
		local moonCentre = { -5, 10.6, -39.6 }
		tail:add(
			shape(moonCentre, 3.2, function(x: number, y: number, z: number): boolean
				if math.abs(x - moonCentre[1]) > 0.7 then
					return false
				end
				local dy, dz = y - moonCentre[2], z - moonCentre[3]
				local ey, ez = dy - 1.1, dz + 1.1
				return dy * dy + dz * dz <= 2.9 * 2.9 and ey * ey + ez * ez > 2.3 * 2.3
			end),
			MOON
		)
		tail:coat(function(p, open)
			if p[3] < -36.5 then
				return nil
			end
			return scales(p, open, 20)
		end)
		mane(tail, { { 0, 0, -15 }, { 0, 0, -19 }, { -1, 0, -23 }, { -2.6, 0, -27 } }, 2.2)

		local frontMirror, backMirror = front:mirror(), back:mirror()
		body:draw(pet:limb("Body", at({ 0, 15, -2 })), { head, front, frontMirror, back, backMirror, tail }, NIGHT)
		local headLimb = pet:limb("Head", at({ 0, 18, 7 }))
		head:draw(headLimb, { body }, NIGHT)
		-- Narrow glowing eyes, slanting up towards the back, in dark rims.
		slitEyes(headLimb, head, { 31.6, 20.3 }, { 32.5, 17 }, 0.95, MOON.color, NEON, CLAW.color)
		for _, tip in hornTips do
			headLimb:fire(at(tip), 2.5, MOONFIRE, MOONFIRE_CORE)
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", at({ 4.6, 15, 5 }), function(limb)
			front:draw(limb, { body }, NIGHT)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", at({ 4.8, 13.5, -10 }), function(limb)
			back:draw(limb, { body }, NIGHT)
		end)
		local tailLimb = pet:limb("Tail", at({ 0, 15, -13 }))
		tail:draw(tailLimb, { body }, NIGHT)
		tailLimb:fire(at({ -5, 12.4, -40.2 }), 3, MOONFIRE, MOONFIRE_CORE)

		-- Great wings of deep violet, sprinkled with stars and edged with moonlight, on silver bones.
		pet:limbPair("LeftWing", "RightWing", at({ 4, 19.5, 2 }), function(wing)
			local MEMBRANE, BONE = rgb(66, 52, 146), SILVER.color
			local FLAT = { 0, 0, 1 }
			local root = { 4, 19.5, 2 }
			local function grow(p: Vec): Vec
				return vadd(root, vscale(vsub(p, root), 1.15))
			end
			local elbow, wrist = grow({ 10, 27, 0 }), grow({ 14, 32.5, -3 })
			local tips = {
				grow({ 28, 30.5, -6 }),
				grow({ 25.5, 21.5, -8 }),
				grow({ 20, 15.5, -8.5 }),
				grow({ 13.5, 15, -7 }),
			}
			local scallops = { grow({ 23.5, 26, -7.2 }), grow({ 20.5, 19.5, -8.4 }), grow({ 16, 17, -8 }) }
			local flank, shoulder = { 5.5, 16.5, -5.5 }, { 4.5, 19, -2 }
			local function membrane(a: Vec, b: Vec, c: Vec)
				triangle(wing, at(a), at(b), at(c), 0.35 / U, MEMBRANE)
			end
			for i = 1, 3 do
				membrane(wrist, tips[i], scallops[i])
				membrane(wrist, scallops[i], tips[i + 1])
			end
			membrane(elbow, wrist, tips[4])
			membrane(elbow, tips[4], flank)
			membrane(elbow, flank, shoulder)
			-- Moonlight along the trailing edge, between the fingers.
			for i = 1, 3 do
				blade(wing, at(tips[i]), at(scallops[i]), 0.3 / U, 0.5 / U, FLAT, MOON.color, NEON)
				blade(wing, at(scallops[i]), at(tips[i + 1]), 0.3 / U, 0.5 / U, FLAT, MOON.color, NEON)
			end
			-- Stars scattered over the membranes.
			local stars = {
				{ wrist, tips[1], scallops[1], 0.45, 0.35 },
				{ wrist, scallops[1], tips[2], 0.5, 0.3 },
				{ wrist, tips[2], scallops[2], 0.35, 0.4 },
				{ wrist, scallops[2], tips[3], 0.55, 0.25 },
				{ wrist, tips[3], scallops[3], 0.3, 0.45 },
				{ elbow, wrist, tips[4], 0.3, 0.35 },
				{ elbow, tips[4], flank, 0.4, 0.3 },
				{ elbow, flank, shoulder, 0.3, 0.3 },
				{ wrist, tips[1], scallops[1], 0.15, 0.7 },
				{ wrist, scallops[2], tips[3], 0.2, 0.6 },
			}
			for index, star in stars do
				local a, b, c, u, v = star[1], star[2], star[3], star[4], star[5]
				local p = vadd(a, vadd(vscale(vsub(b, a), u), vscale(vsub(c, a), v)))
				local size = (if index % 3 == 0 then 0.8 else 0.6) / U
				egg(wing, at(p), { size, size, size }, nil, STAR.color, NEON)
			end
			blade(wing, at(root), at(elbow), 1.5 / U, 1.2 / U, FLAT, BONE)
			blade(wing, at(elbow), at(wrist), 1.25 / U, 1.05 / U, FLAT, BONE)
			for index, tip in tips do
				local mid = vlerp(wrist, tip, 0.7)
				blade(wing, at(wrist), at(mid), (0.9 - index * 0.08) / U, 0.8 / U, FLAT, BONE)
				taper(wing, at(mid), at(tip), 0.7 / U, 0.7 / U, FLAT, MOON.color, NEON)
			end
			taper(wing, at(wrist), at(grow({ 15, 35.5, -2 })), 0.8 / U, 0.7 / U, { 1, 0, 0 }, BONE)
			egg(wing, at(elbow), { 1.4 / U, 1.4 / U, 1.4 / U }, nil, MOON.color, NEON)
		end)

		pet:light(rgb(170, 200, 255), 3.4, 26)
		pet:particles("Sparkles", rgb(236, 242, 255), 18)
		pet:seat(0, 21 / U, -3 / U)
	end,
}

return Designs
