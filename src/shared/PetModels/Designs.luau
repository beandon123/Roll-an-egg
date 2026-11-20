--!strict
-- The look of every pet, by name. Which egg each pet hatches from is set in Config/Zones (`pet`).
-- Each design draws limbs on the pet builder in PetModels:
--     x left (+x) and right (-x); y up from the ground; z forward. A cell numbered x covers x to x + 1.
--     limb:box() draws a solid block, limb:paint() colours the surface of blocks already drawn (eyes, bellies),
--     and the ...Pair versions mirror across the middle of the pet.
-- Pets are themed to match their egg. Every pet in the game has a design, zone by zone, each zone in its own file
-- beside this one (Forest, Desert, Snow, Jungle, Ocean, Volcano and Prehistoric .luau), merged in
-- below; this file keeps only shelved designs. The drawing tools are in PetModels/Kit. Pets are sculpted
-- (`newSculpt`): modelled cell by cell from rounded shapes turned to any angle (`ellipsoid`, `rod`, `curl` for a
-- spiral to end a rod on), coloured by rules (`coat`, `trace`), then packed into blocks; with thin details (horns,
-- claws, fangs, feathers, fins, wings, eyes) built from parts at any angle (`blade`, `taper`, `triangle`, `egg`,
-- `feather`, placed in a design's own units with `inUnits`), so they stay crisp however big a pet is shown, and
-- flames (limb:fire). The smallest are blocks placed by hand (limb:box).

local Kit = require(script.Parent.Kit)

type Color = Kit.Color
type Limb = Kit.Limb
type Design = Kit.Design
type Look = Kit.Look
type Sculpt = Kit.Sculpt
type Vec = Kit.Vec

local rgb = Kit.rgb
local NEON = Kit.NEON
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
local egg = Kit.egg
local feather = Kit.feather

local Designs: { [string]: Design } = {}

-- Each zone's pets are in its own file.
for _, zone in
	{
		require(script.Parent.Forest),
		require(script.Parent.Desert),
		require(script.Parent.Snow),
		require(script.Parent.Jungle),
		require(script.Parent.Ocean),
		require(script.Parent.Volcano),
		require(script.Parent.Prehistoric),
	}
do
	for kind, design in zone do
		Designs[kind] = design
	end
end

----------------------------------------------------------------------------------------------------------------
-- Shelved designs, kept for later: no zone's egg hatches them.

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

return Designs
