--!strict
-- The look of every pet, by name. Which egg each pet hatches from is set in Config/Zones (`pet`).
-- Each design draws limbs on the pet builder in PetModels:
--     x left (+x) and right (-x); y up from the ground; z forward. A cell numbered x covers x to x + 1.
--     limb:box() draws a solid block, limb:paint() colours the surface of blocks already drawn (eyes, bellies),
--     and the ...Pair versions mirror across the middle of the pet.
-- Pets have big heads and small bodies, like the eggs they come from, and are themed to match their egg.
-- So far: the Forest and Desert pets. The other zones' pets come next.

type Color = { number }
type Pet = any
type Limb = any
type Design = {
	name: string,
	-- One of PetModels.SKELETONS: decides which limbs the pet has and so which animations it uses.
	skeleton: string,
	-- How it moves: "Walk" (default), "Hop", "Waddle" or "Stomp".
	gait: string?,
	-- Studs per voxel; bigger pets are drawn with more voxels, small ones get a bigger scale to be rideable.
	scale: number?,
	draw: (Pet) -> (),
}

local function rgb(r: number, g: number, b: number): Color
	return { r, g, b }
end

local NEON = "Neon"
local EYE = rgb(26, 22, 26)
local SHINE = rgb(255, 255, 255)

-- Two eyes on a face whose front cells are at `z`. The left eye covers x..x+width-1 (the right one is mirrored),
-- y..y+tall-1, with a white glint in its top corner nearest the middle.
local function eyes(head: Limb, x: number, y: number, z: number, width: number?, tall: number?)
	local w, t = width or 2, tall or 2
	head:paintPair(x, y, z, x + w - 1, y + t - 1, z, EYE)
	head:paintPair(x, y + t - 1, z, x, y + t - 1, z, SHINE)
end

local Designs: { [string]: Design } = {}

----------------------------------------------------------------------------------------------------------------
-- Forest

Designs.Squirrel = {
	name = "Squirrel",
	skeleton = "Quadruped",
	gait = "Hop",
	scale = 0.45,
	draw = function(pet)
		local FUR = rgb(204, 116, 54)
		local DARK = rgb(140, 74, 34)
		local CREAM = rgb(248, 226, 186)
		local TIP = rgb(232, 160, 96)
		local NOSE = rgb(84, 44, 30)

		local ACORN = rgb(200, 142, 82)
		local CAP = rgb(112, 74, 44)
		local PINK = rgb(255, 172, 188)

		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-3, 3, -3, 2, 7, 3, FUR)
		body:paint(-2, 3, 3, 1, 6, 3, CREAM)
		body:paint(-1, 7, -3, 0, 7, 2, DARK)
		-- An acorn held up in its front paws.
		body:box(-1, 4, 4, 0, 5, 5, ACORN)
		body:box(-1, 6, 4, 0, 6, 5, CAP)

		local head = pet:limb("Head", { 0, 8, 1 })
		head:box(-4, 8, -1, 3, 14, 5, FUR)
		head:paint(-3, 8, 5, 2, 10, 5, CREAM)
		head:paint(-1, 10, 5, 0, 10, 5, NOSE)
		eyes(head, 1, 11, 5)
		-- Pointed ears with dark tufts.
		head:boxPair(2, 15, 1, 3, 16, 2, FUR)
		head:paintPair(2, 15, 2, 2, 15, 2, PINK)
		head:boxPair(3, 17, 2, 3, 17, 2, DARK)
		head:paintPair(3, 9, 5, 3, 9, 5, PINK)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 4, 2 }, function(leg)
			leg:box(1, 0, 1, 2, 3, 2, FUR)
			leg:paint(1, 0, 2, 2, 0, 2, CREAM)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2.5, 5, -2 }, function(leg)
			leg:box(1, 1, -3, 3, 5, -1, FUR)
			leg:box(1, 0, -3, 2, 0, 0, FUR)
		end)

		-- A big bushy tail curling up over its back.
		local tail = pet:limb("Tail", { 0, 5, -3 })
		tail:box(-2, 4, -6, 1, 6, -4, FUR)
		tail:box(-3, 6, -8, 2, 15, -5, FUR)
		tail:box(-3, 14, -5, 2, 16, -3, FUR)
		tail:paint(-3, 15, -8, 2, 16, -3, TIP)
		tail:paint(-3, 6, -8, 2, 7, -8, DARK)
		tail:paint(-3, 10, -8, 2, 10, -5, TIP)
		tail:paint(-3, 12, -8, 2, 12, -5, DARK)

		pet:seat(0, 8, -1)
	end,
}

Designs.Bunny = {
	name = "Bunny",
	skeleton = "Quadruped",
	gait = "Hop",
	scale = 0.45,
	draw = function(pet)
		local FUR = rgb(244, 238, 226)
		local FAWN = rgb(206, 168, 128)
		local PINK = rgb(255, 172, 188)

		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-3, 2, -3, 2, 6, 2, FUR)
		-- A fawn saddle, like the bottom of its egg.
		body:paint(-3, 5, -3, 2, 6, -1, FAWN)
		body:box(-2, 3, 3, 1, 5, 3, FUR)

		local head = pet:limb("Head", { 0, 7, 1 })
		head:box(-3, 7, -1, 2, 12, 4, FUR)
		-- Fluffy cheeks.
		head:box(-4, 7, 0, 3, 9, 3, FUR)
		head:paint(-1, 9, 4, 0, 9, 4, PINK)
		head:box(-1, 7, 5, 0, 7, 5, SHINE)
		head:paintPair(2, 8, 3, 3, 8, 3, PINK)
		eyes(head, 1, 10, 4)
		-- Tall ears, pink inside, fawn at the tips.
		head:boxPair(1, 13, 1, 3, 18, 2, FUR)
		head:paintPair(2, 14, 2, 2, 17, 2, PINK)
		head:paintPair(1, 18, 1, 3, 18, 2, FAWN)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 3, 2 }, function(leg)
			leg:box(1, 0, 1, 2, 2, 2, FUR)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2.5, 4, -2 }, function(leg)
			leg:box(1, 1, -3, 3, 4, -1, FUR)
			-- Long hind feet.
			leg:box(1, 0, -3, 3, 0, 1, FUR)
		end)

		local tail = pet:limb("Tail", { 0, 4, -3 })
		tail:box(-1, 3, -5, 0, 5, -4, FUR)

		pet:seat(0, 7, -1)
	end,
}

Designs.Hedgehog = {
	name = "Hedgehog",
	skeleton = "LowSlung",
	scale = 0.65,
	draw = function(pet)
		local SPINE = rgb(112, 76, 48)
		local TIP = rgb(180, 140, 100)
		local FACE = rgb(234, 200, 156)

		-- A round dome of spines, with lighter spikes sticking out.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 1, -4, 3, 5, 3, SPINE)
		body:box(-3, 6, -3, 2, 7, 2, SPINE)
		body:boxPair(4, 2, -2, 4, 2, -2, TIP)
		body:boxPair(4, 4, 0, 4, 4, 0, TIP)
		body:boxPair(3, 6, -2, 3, 6, -2, TIP)
		body:boxPair(2, 8, 0, 2, 8, 0, TIP)
		body:boxPair(1, 8, -3, 1, 8, -3, TIP)
		body:boxPair(2, 4, -5, 2, 4, -5, TIP)
		body:boxPair(0, 2, -5, 0, 2, -5, TIP)
		body:boxPair(1, 6, -4, 1, 6, -4, TIP)
		body:boxPair(4, 3, -3, 4, 3, -3, TIP)
		body:boxPair(3, 7, 0, 3, 7, 0, TIP)
		body:boxPair(0, 8, 1, 0, 8, 1, TIP)
		body:box(-2, 8, -2, -1, 8, -1, rgb(132, 202, 92))
		body:box(-2, 9, -2, -2, 9, -2, rgb(84, 150, 62))

		-- A pointed little face poking out of the front.
		local head = pet:limb("Head", { 0, 3, 4 })
		head:box(-2, 1, 4, 1, 4, 6, FACE)
		head:box(-1, 1, 7, 0, 2, 7, FACE)
		head:box(-1, 2, 8, 0, 2, 8, EYE)
		head:paintPair(1, 3, 6, 1, 3, 6, EYE)
		head:paintPair(1, 2, 6, 1, 2, 6, rgb(255, 172, 188))
		head:boxPair(1, 5, 4, 1, 5, 4, FACE)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2.5, 1, 2.5 }, function(leg)
			leg:box(2, 0, 2, 2, 0, 2, FACE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2.5, 1, -2.5 }, function(leg)
			leg:box(2, 0, -3, 2, 0, -3, FACE)
		end)

		local tail = pet:limb("Tail", { 0, 2, -4 })
		tail:box(-1, 1, -5, 0, 1, -5, FACE)

		pet:seat(0, 8, -1)
	end,
}

Designs.Fox = {
	name = "Fox",
	skeleton = "Quadruped",
	scale = 0.5,
	draw = function(pet)
		local ORANGE = rgb(232, 118, 46)
		local WHITE = rgb(248, 242, 230)
		local DARK = rgb(64, 42, 32)

		local body = pet:limb("Body", { 0, 5, 0 })
		body:box(-3, 3, -4, 2, 7, 3, ORANGE)
		body:paint(-2, 3, 3, 1, 6, 3, WHITE)
		body:box(-1, 4, 4, 0, 6, 4, WHITE)

		local head = pet:limb("Head", { 0, 7, 3 })
		head:box(-3, 7, 2, 2, 12, 7, ORANGE)
		-- White cheeks and a pointed muzzle with a dark nose.
		head:paint(-3, 7, 7, 2, 8, 7, WHITE)
		head:box(-1, 7, 8, 0, 8, 9, WHITE)
		head:box(-1, 8, 10, 0, 8, 10, DARK)
		eyes(head, 1, 9, 7, 1)
		-- Big pointed ears with dark tips.
		head:boxPair(1, 13, 4, 2, 14, 5, ORANGE)
		head:paintPair(1, 13, 5, 1, 14, 5, WHITE)
		head:boxPair(2, 15, 4, 2, 15, 5, DARK)
		head:boxPair(3, 7, 5, 3, 8, 6, WHITE)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 4, 2 }, function(leg)
			leg:box(1, 0, 1, 2, 3, 2, ORANGE)
			leg:paint(1, 0, 1, 2, 1, 2, DARK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2, 4, -3 }, function(leg)
			leg:box(1, 0, -4, 2, 3, -3, ORANGE)
			leg:paint(1, 0, -4, 2, 1, -3, DARK)
		end)

		-- A long bushy tail with a white tip.
		local tail = pet:limb("Tail", { 0, 6, -4 })
		tail:box(-2, 5, -7, 1, 7, -5, ORANGE)
		tail:box(-3, 3, -9, 2, 6, -8, ORANGE)
		tail:box(-2, 2, -11, 1, 4, -10, WHITE)

		pet:seat(0, 8, -1)
	end,
}

Designs.Owl = {
	name = "Owl",
	skeleton = "Winged",
	gait = "Waddle",
	scale = 0.5,
	draw = function(pet)
		local BROWN = rgb(140, 98, 62)
		local DARK = rgb(96, 64, 40)
		local LIGHT = rgb(222, 196, 152)
		local BEAK = rgb(242, 164, 44)
		local RING = rgb(255, 214, 70)

		-- A round, fluffy body: a soft chest with chevrons, speckles on its back.
		local body = pet:limb("Body", { 0, 2, 0 })
		body:box(-4, 2, -3, 3, 9, 3, BROWN)
		body:box(-3, 3, 4, 2, 8, 4, LIGHT)
		body:paintPair(1, 6, 4, 1, 6, 4, DARK)
		body:paintPair(2, 4, 4, 2, 4, 4, DARK)
		body:paint(-1, 4, 4, 0, 4, 4, DARK)
		body:paint(-1, 7, 4, 0, 7, 4, DARK)
		body:paint(-3, 8, -3, -3, 8, -3, LIGHT)
		body:paint(2, 6, -3, 2, 6, -3, LIGHT)
		body:paint(-1, 4, -3, 0, 4, -3, LIGHT)
		body:paint(1, 8, -3, 1, 8, -3, LIGHT)
		body:paint(-3, 3, -3, -3, 3, -3, LIGHT)
		body:paint(-4, 2, -3, 3, 2, 3, LIGHT)

		-- A big round head: pale face disc with a dark rim, frowning brows, huge eyes, a hooked beak, tall tufts.
		local head = pet:limb("Head", { 0, 10, 0 })
		head:box(-4, 10, -3, 3, 15, 3, BROWN)
		head:box(-3, 16, -2, 2, 16, 2, BROWN)
		head:paint(-4, 10, 3, 3, 14, 3, LIGHT)
		head:paint(-4, 10, 3, -4, 14, 3, DARK)
		head:paint(3, 10, 3, 3, 14, 3, DARK)
		head:paintPair(1, 12, 3, 2, 13, 3, RING)
		head:paintPair(1, 12, 3, 1, 13, 3, EYE)
		head:paintPair(1, 13, 3, 1, 13, 3, SHINE)
		head:boxPair(1, 14, 4, 2, 14, 4, DARK)
		head:boxPair(3, 15, 4, 3, 15, 4, DARK)
		head:box(-1, 11, 4, 0, 12, 4, BEAK)
		head:box(-1, 10, 5, 0, 11, 5, BEAK)
		head:boxPair(2, 16, -1, 3, 17, 0, BROWN)
		head:boxPair(3, 18, -1, 4, 18, 0, DARK)
		head:boxPair(4, 19, -1, 4, 19, 0, DARK)
		head:paint(-2, 16, -2, -2, 16, -2, LIGHT)
		head:paint(1, 16, 1, 1, 16, 1, LIGHT)
		head:paint(-3, 14, -3, -3, 14, -3, LIGHT)
		head:paint(2, 12, -3, 2, 12, -3, LIGHT)

		-- Layered wings: soft coverts, barred flight feathers and dark tips.
		pet:limbPair("LeftWing", "RightWing", { 4.5, 9, 0 }, function(wing)
			wing:box(4, 6, -2, 5, 9, 2, BROWN)
			wing:box(4, 2, -3, 4, 5, 1, DARK)
			wing:box(4, 1, -4, 4, 2, -3, DARK)
			wing:paint(4, 7, -2, 5, 7, 2, LIGHT)
			wing:paint(4, 4, -3, 4, 4, 1, LIGHT)
			wing:paint(4, 2, -3, 4, 2, 1, LIGHT)
		end)
		-- Fluffy legs and orange talons.
		pet:limbPair("LeftLeg", "RightLeg", { 2, 2, 1 }, function(leg)
			leg:box(1, 1, 0, 2, 1, 1, LIGHT)
			leg:box(1, 0, 0, 2, 0, 2, BEAK)
			leg:paint(1, 0, 2, 2, 0, 2, DARK)
		end)

		-- A fan of tail feathers.
		local tail = pet:limb("Tail", { 0, 3, -3 })
		tail:box(-2, 2, -4, 1, 4, -4, DARK)
		tail:box(-3, 1, -5, 2, 2, -5, DARK)
		tail:paint(-3, 1, -5, 2, 1, -5, LIGHT)

		pet:seat(0, 17, -1)
	end,
}

Designs.Bear = {
	name = "Bear",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local BROWN = rgb(142, 94, 58)
		local TAN = rgb(218, 174, 124)
		local NOSE = rgb(44, 32, 28)
		local HONEY = rgb(255, 188, 48)

		local body = pet:limb("Body", { 0, 6, 0 })
		body:box(-5, 3, -5, 4, 10, 4, BROWN)
		body:paint(-3, 3, 4, 2, 8, 4, TAN)

		local head = pet:limb("Head", { 0, 10, 4 })
		head:box(-4, 9, 4, 3, 15, 10, BROWN)
		head:box(-2, 9, 11, 1, 11, 12, TAN)
		head:paint(-1, 11, 12, 0, 11, 12, NOSE)
		head:paint(-1, 11, 11, 0, 11, 11, rgb(116, 76, 46))
		eyes(head, 1, 12, 10, 1)
		-- Round ears, light inside.
		head:boxPair(2, 16, 6, 4, 17, 7, BROWN)
		head:paintPair(3, 16, 7, 3, 16, 7, TAN)
		-- Honey dripping down its head, like on its egg.
		head:paint(-3, 15, 5, 1, 15, 9, HONEY)
		head:paint(-1, 14, 10, -1, 15, 10, HONEY)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 4, 2 }, function(leg)
			leg:box(2, 0, 1, 4, 3, 3, BROWN)
			leg:paint(2, 0, 3, 4, 0, 3, TAN)
			leg:box(2, 0, 4, 4, 0, 4, NOSE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 4, -4 }, function(leg)
			leg:box(2, 0, -5, 4, 3, -3, BROWN)
		end)

		local tail = pet:limb("Tail", { 0, 8, -5 })
		tail:box(-1, 8, -6, 0, 9, -6, BROWN)

		pet:seat(0, 11, -1)
	end,
}

Designs.MossStag = {
	name = "Moss Stag",
	skeleton = "Quadruped",
	scale = 0.55,
	draw = function(pet)
		local DEER = rgb(152, 106, 68)
		local DEER_DARK = rgb(116, 78, 48)
		local LIGHT = rgb(232, 206, 162)
		local MOSS = rgb(86, 146, 66)
		local MOSS_LIGHT = rgb(140, 196, 96)
		local VINE = rgb(70, 128, 58)
		local WOOD = rgb(168, 126, 82)
		local HOOF = rgb(64, 46, 34)
		local CAP = rgb(214, 54, 50)
		local SPOT = rgb(250, 240, 226)
		local PINK = rgb(255, 150, 196)
		local YELLOW = rgb(255, 220, 80)

		-- A deer's body: deep chest, slimmer middle, rounded rump, pale belly and a few fawn spots.
		local body = pet:limb("Body", { 0, 9, 0 })
		body:box(-4, 7, 1, 3, 12, 5, DEER)
		body:box(-3, 7, -5, 2, 11, 0, DEER)
		body:box(-4, 7, -8, 3, 12, -6, DEER)
		body:paint(-3, 7, -5, 2, 7, 0, LIGHT)
		body:paint(-2, 8, 5, 1, 11, 5, LIGHT)
		body:paintPair(3, 10, -8, 3, 10, -8, SPOT)
		body:paintPair(3, 11, -7, 3, 11, -7, SPOT)
		body:paintPair(2, 9, -3, 2, 9, -3, SPOT)
		-- A blanket of moss over its back, hanging in uneven drips, with mushrooms, blossoms and a trailing vine.
		body:box(-5, 12, -7, 4, 13, 4, MOSS)
		body:boxPair(4, 10, -4, 4, 11, 3, MOSS)
		body:boxPair(4, 9, -4, 4, 9, -3, MOSS)
		body:boxPair(4, 8, 0, 4, 9, 0, MOSS)
		body:boxPair(4, 9, 2, 4, 9, 2, MOSS)
		body:boxPair(4, 6, -3, 4, 8, -3, VINE)
		body:paint(-3, 13, -5, -1, 13, -3, MOSS_LIGHT)
		body:paint(0, 13, 0, 2, 13, 3, MOSS_LIGHT)
		body:paintPair(4, 11, -2, 4, 11, 0, MOSS_LIGHT)
		body:box(2, 14, -5, 3, 14, -4, CAP)
		body:paint(2, 14, -5, 2, 14, -5, SPOT)
		body:box(-4, 14, 2, -4, 14, 2, CAP)
		body:box(-2, 14, -1, -2, 14, -1, PINK, NEON)
		body:box(1, 14, 2, 1, 14, 2, YELLOW, NEON)
		body:box(-4, 14, -6, -4, 14, -6, PINK, NEON)

		-- A strong neck with a pale throat, a soft muzzle, and great branching antlers in bloom.
		local head = pet:limb("Head", { 0, 12, 5 })
		head:box(-2, 11, 5, 1, 15, 7, DEER)
		head:paint(-1, 11, 7, 0, 14, 7, LIGHT)
		head:box(-3, 15, 5, 2, 19, 10, DEER)
		head:box(-2, 15, 11, 1, 17, 12, LIGHT)
		head:box(-1, 16, 13, 0, 17, 13, HOOF)
		head:paint(-2, 18, 10, 1, 19, 10, DEER_DARK)
		eyes(head, 1, 17, 10, 1)
		head:boxPair(3, 18, 7, 4, 19, 8, DEER)
		head:paintPair(3, 18, 8, 4, 18, 8, LIGHT)
		head:paint(-2, 19, 6, 1, 19, 9, MOSS)
		head:boxPair(1, 20, 7, 1, 21, 7, WOOD)
		head:boxPair(2, 22, 7, 3, 22, 7, WOOD)
		head:boxPair(4, 23, 7, 4, 25, 7, WOOD)
		head:boxPair(5, 26, 7, 5, 27, 7, WOOD)
		head:boxPair(2, 23, 8, 2, 24, 9, WOOD)
		head:boxPair(3, 24, 6, 3, 26, 6, WOOD)
		head:boxPair(6, 25, 7, 7, 25, 7, WOOD)
		head:paintPair(4, 23, 7, 4, 24, 7, MOSS_LIGHT)
		head:paintPair(2, 22, 7, 2, 22, 7, MOSS)
		head:boxPair(5, 28, 7, 5, 28, 7, PINK, NEON)
		head:boxPair(3, 27, 6, 3, 27, 6, YELLOW, NEON)
		head:boxPair(2, 25, 9, 2, 25, 9, PINK, NEON)
		head:boxPair(8, 25, 7, 8, 25, 7, YELLOW, NEON)
		head:boxPair(7, 22, 7, 7, 24, 7, VINE)

		-- Long legs with knees, pale cuffs and dark hooves.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 8, 3.5 }, function(leg)
			leg:box(2, 4, 3, 3, 7, 4, DEER)
			leg:box(2, 0, 3, 3, 3, 4, DEER)
			leg:paint(2, 4, 4, 3, 4, 4, DEER_DARK)
			leg:paint(2, 1, 3, 3, 1, 4, LIGHT)
			leg:paint(2, 0, 3, 3, 0, 4, HOOF)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 8, -6.5 }, function(leg)
			leg:box(3, 6, -8, 4, 10, -5, DEER)
			leg:box(2, 0, -7, 3, 5, -6, DEER)
			leg:paint(2, 1, -7, 3, 1, -6, LIGHT)
			leg:paint(2, 0, -7, 3, 0, -6, HOOF)
		end)

		-- A white flag of a tail.
		local tail = pet:limb("Tail", { 0, 11, -8 })
		tail:box(-1, 10, -9, 0, 12, -9, LIGHT)
		tail:paint(-1, 12, -9, 0, 12, -9, DEER)

		pet:seat(0, 14, -1)
	end,
}

Designs.Treant = {
	name = "Treant",
	skeleton = "Biped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local BARK = rgb(112, 78, 48)
		local BARK_DARK = rgb(78, 52, 32)
		local HOLLOW = rgb(36, 24, 16)
		local LEAF = rgb(132, 202, 92)
		local LEAF_DARK = rgb(74, 140, 60)
		local MOSS = rgb(96, 156, 70)
		local VINE = rgb(70, 128, 58)
		local SAP = rgb(196, 255, 110)
		local PINK = rgb(255, 150, 196)
		local CAP = rgb(214, 54, 50)
		local SPOT = rgb(250, 240, 226)

		-- A hunched trunk: narrow at the hips, broad at the shoulders.
		local body = pet:limb("Body", { 0, 6, 0 })
		body:box(-4, 6, -3, 3, 11, 3, BARK)
		body:box(-5, 12, -4, 4, 18, 3, BARK)
		-- A heavy brow over glowing slit eyes, and a hollow mouth glowing deep inside.
		body:box(-4, 16, 4, 3, 16, 4, BARK_DARK)
		body:paintPair(1, 15, 3, 2, 15, 3, SAP, NEON)
		body:paint(-2, 12, 3, 1, 13, 3, HOLLOW)
		body:paint(-1, 12, 3, 0, 12, 3, SAP, NEON)
		-- Glowing sap showing through jagged cracks in the bark.
		body:paint(-3, 10, 3, -3, 11, 3, SAP, NEON)
		body:paint(-2, 8, 3, -2, 9, 3, SAP, NEON)
		body:paint(-3, 7, 3, -3, 7, 3, SAP, NEON)
		body:paint(2, 9, 3, 2, 10, 3, SAP, NEON)
		body:paint(1, 7, 3, 1, 8, 3, SAP, NEON)
		body:paint(2, 6, 3, 2, 6, 3, SAP, NEON)
		body:paint(4, 16, -2, 4, 17, -2, SAP, NEON)
		body:paint(4, 14, -1, 4, 15, -1, SAP, NEON)
		body:paint(4, 13, -2, 4, 13, -2, SAP, NEON)
		body:paint(-1, 9, -3, -1, 11, -3, SAP, NEON)
		body:paint(0, 12, -4, 0, 13, -4, SAP, NEON)
		body:paint(-1, 14, -4, -1, 15, -4, SAP, NEON)
		-- Bark grooves and moss on its shoulders.
		body:paint(1, 6, -3, 1, 11, -3, BARK_DARK)
		body:paint(2, 12, -4, 2, 18, -4, BARK_DARK)
		body:paint(-5, 12, 0, -5, 18, 0, BARK_DARK)
		body:paint(-5, 18, -4, -2, 18, -1, MOSS)
		body:paint(2, 18, 0, 4, 18, 3, MOSS)
		-- Red mushrooms growing out of one side, a snapped-off branch on the other.
		body:box(-7, 13, -4, -6, 13, -2, CAP)
		body:paint(-7, 13, -3, -7, 13, -3, SPOT)
		body:box(-6, 9, 0, -5, 9, 1, CAP)
		body:box(4, 8, -1, 5, 9, -1, BARK_DARK)

		-- A big crown of leaves with branches poking through, blossoms, and glowing fruit hanging underneath.
		local head = pet:limb("Head", { 0, 19, 0 })
		head:box(-6, 19, -5, 5, 21, 4, LEAF)
		head:box(-5, 22, -4, 4, 23, 3, LEAF)
		head:box(-3, 24, -3, 2, 24, 2, LEAF)
		head:box(-7, 20, -2, -7, 21, 1, LEAF)
		head:box(6, 19, -3, 6, 20, 0, LEAF)
		head:box(-2, 20, 5, 1, 22, 5, LEAF)
		head:paint(-6, 19, -5, -3, 20, -3, LEAF_DARK)
		head:paint(2, 21, 1, 5, 21, 4, LEAF_DARK)
		head:paint(-5, 23, 0, -3, 23, 3, LEAF_DARK)
		head:paint(1, 24, -3, 2, 24, -1, LEAF_DARK)
		head:box(-4, 25, -1, -3, 26, 0, BARK)
		head:box(-5, 27, -1, -5, 27, 0, BARK)
		head:box(-7, 28, -2, -5, 29, 1, LEAF)
		head:paint(-7, 28, -2, -6, 28, 1, LEAF_DARK)
		head:box(2, 25, -3, 3, 26, -2, BARK)
		head:box(4, 27, -3, 4, 27, -2, BARK)
		head:box(4, 28, -4, 6, 29, -1, LEAF)
		head:paint(5, 28, -4, 6, 28, -1, LEAF_DARK)
		head:paint(5, 20, -2, 5, 20, -2, PINK)
		head:paint(-4, 23, 3, -4, 23, 3, PINK)
		head:paint(0, 24, 2, 0, 24, 2, PINK)
		head:paint(-7, 21, 0, -7, 21, 0, PINK)
		head:paint(1, 22, 5, 1, 22, 5, PINK)
		head:box(-6, 18, 3, -6, 18, 3, SAP, NEON)
		head:box(5, 17, 2, 5, 18, 2, SAP, NEON)
		head:box(-2, 18, -5, -2, 18, -5, SAP, NEON)

		-- Long branch arms reaching down, with twig claws, a tuft of leaves and a hanging vine.
		pet:limbPair("LeftArm", "RightArm", { 5.5, 17, 0 }, function(arm)
			arm:box(5, 15, -1, 6, 17, 1, BARK)
			arm:box(6, 11, -1, 7, 15, 0, BARK)
			arm:box(6, 8, 0, 7, 10, 1, BARK)
			arm:box(6, 6, 2, 6, 7, 2, BARK_DARK)
			arm:box(7, 6, 0, 7, 7, 0, BARK_DARK)
			arm:box(5, 6, 1, 5, 7, 1, BARK_DARK)
			arm:box(5, 18, -1, 7, 18, 1, LEAF)
			arm:box(7, 12, 1, 7, 14, 1, VINE)
			arm:paint(6, 13, -1, 7, 14, -1, MOSS)
		end)
		-- Thick legs on spreading roots.
		pet:limbPair("LeftLeg", "RightLeg", { 2.5, 6, 0 }, function(leg)
			leg:box(1, 2, -2, 3, 6, 1, BARK)
			leg:box(0, 0, -3, 4, 1, 2, BARK_DARK)
			leg:box(1, 0, 3, 1, 0, 4, BARK_DARK)
			leg:box(3, 0, 3, 3, 0, 4, BARK_DARK)
			leg:box(5, 0, -1, 5, 0, 0, BARK_DARK)
			leg:box(1, 0, -4, 1, 0, -4, BARK_DARK)
			leg:paint(0, 1, -3, 2, 1, -1, MOSS)
		end)

		pet:light(SAP, 2, 14)
		pet:particles("Sparkles", SAP, 8)
		pet:seat(0, 25, -1)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Desert

Designs.Meerkat = {
	name = "Meerkat",
	skeleton = "Biped",
	scale = 0.5,
	draw = function(pet)
		local FUR = rgb(214, 178, 124)
		local LIGHT = rgb(240, 218, 172)
		local DARK = rgb(92, 66, 44)

		-- Standing up on lookout, with its long tail for balance.
		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-2, 4, -2, 1, 10, 1, FUR)
		body:paint(-1, 4, 1, 0, 9, 1, LIGHT)
		body:paint(-2, 9, -2, 1, 9, -2, DARK)
		body:paint(-2, 7, -2, 1, 7, -2, DARK)
		body:paint(-2, 5, -2, 1, 5, -2, DARK)
		body:box(-1, 4, -4, 0, 5, -3, FUR)
		body:box(-1, 1, -5, 0, 4, -5, FUR)
		body:box(-1, 0, -7, 0, 1, -5, FUR)
		body:box(-1, 0, -8, 0, 0, -8, DARK)

		local head = pet:limb("Head", { 0, 10, 0 })
		head:box(-2, 11, -2, 1, 14, 2, FUR)
		head:box(-1, 11, 3, 0, 12, 3, LIGHT)
		head:box(-1, 12, 4, 0, 12, 4, DARK)
		-- Dark patches round its eyes, and little round ears.
		head:paintPair(1, 12, 2, 1, 13, 2, DARK)
		head:paintPair(1, 13, 2, 1, 13, 2, EYE)
		head:paintPair(1, 13, 2, 1, 13, 2, SHINE)
		head:boxPair(2, 13, 0, 2, 13, 0, DARK)

		-- Paws held up in front of its chest.
		pet:limbPair("LeftArm", "RightArm", { 2.5, 9, 0.5 }, function(arm)
			arm:box(2, 7, 0, 2, 9, 1, FUR)
			arm:box(1, 7, 2, 2, 7, 2, DARK)
		end)
		pet:limbPair("LeftLeg", "RightLeg", { 1, 4, 0 }, function(leg)
			leg:box(0, 0, -1, 1, 3, 0, FUR)
			leg:box(0, 0, 1, 1, 0, 1, DARK)
		end)

		pet:seat(0, 15, 0)
	end,
}

Designs.Armadillo = {
	name = "Armadillo",
	skeleton = "LowSlung",
	scale = 0.75,
	draw = function(pet)
		local SHELL = rgb(214, 166, 108)
		local BAND = rgb(178, 106, 64)
		local SKIN = rgb(232, 196, 160)
		local DARK = rgb(80, 56, 40)

		-- A domed shell with raised bands, like the strata on its egg.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 2, -5, 3, 5, 4, SHELL)
		body:box(-3, 6, -4, 2, 7, 3, SHELL)
		for _, z in { -3, -1, 1 } do
			body:box(-5, 3, z, 4, 6, z, BAND)
			body:box(-4, 7, z, 3, 8, z, BAND)
			body:paintPair(4, 5, z, 4, 5, z, SHELL)
			body:paint(-1, 8, z, 0, 8, z, SHELL)
		end
		body:paint(-4, 2, -5, 3, 2, 4, BAND)

		-- A long pointed snout, upright ears and a little armoured cap.
		local head = pet:limb("Head", { 0, 3, 5 })
		head:box(-2, 2, 5, 1, 5, 7, SKIN)
		head:box(-1, 2, 8, 0, 3, 9, SKIN)
		head:box(-1, 3, 10, 0, 3, 10, DARK)
		head:paint(-2, 5, 5, 1, 5, 7, SHELL)
		head:paintPair(1, 4, 7, 1, 4, 7, EYE)
		head:boxPair(1, 6, 5, 1, 7, 5, SKIN)
		head:paintPair(1, 6, 5, 1, 7, 5, rgb(246, 166, 170))

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 2, 3 }, function(leg)
			leg:box(2, 0, 2, 3, 1, 3, SKIN)
			leg:paint(2, 0, 3, 3, 0, 3, DARK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 2, -3 }, function(leg)
			leg:box(2, 0, -4, 3, 1, -3, SKIN)
			leg:paint(2, 0, -3, 3, 0, -3, DARK)
		end)

		-- A banded tail.
		local tail = pet:limb("Tail", { 0, 3, -5 })
		tail:box(-1, 2, -7, 0, 3, -6, SHELL)
		tail:box(-1, 1, -9, 0, 2, -8, BAND)
		tail:box(-1, 1, -10, 0, 1, -10, SHELL)

		pet:seat(0, 9, -1)
	end,
}

Designs.FennecFox = {
	name = "Fennec Fox",
	skeleton = "Quadruped",
	scale = 0.55,
	draw = function(pet)
		local CREAM = rgb(246, 230, 198)
		local GINGER = rgb(228, 160, 94)
		local PINK = rgb(246, 160, 170)
		local DARK = rgb(70, 48, 36)

		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-2, 3, -3, 1, 6, 2, GINGER)
		body:paint(-1, 3, 2, 0, 5, 2, CREAM)

		local head = pet:limb("Head", { 0, 6, 2 })
		head:box(-3, 6, 1, 2, 10, 5, CREAM)
		head:paint(-3, 10, 1, 2, 10, 5, GINGER)
		head:box(-1, 6, 6, 0, 7, 7, CREAM)
		head:box(-1, 7, 8, 0, 7, 8, DARK)
		eyes(head, 1, 8, 5, 1)
		-- Enormous ears, pink inside, leaning out.
		head:boxPair(1, 11, 2, 3, 13, 3, GINGER)
		head:boxPair(2, 14, 2, 4, 15, 3, GINGER)
		head:boxPair(3, 16, 2, 4, 16, 3, GINGER)
		head:paintPair(2, 12, 3, 2, 13, 3, PINK)
		head:paintPair(3, 14, 3, 3, 15, 3, PINK)
		head:paintPair(2, 11, 3, 2, 11, 3, CREAM)
		head:boxPair(3, 6, 4, 3, 7, 5, CREAM)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 1.5, 3, 1.5 }, function(leg)
			leg:box(1, 0, 1, 1, 2, 1, CREAM)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 1.5, 3, -2.5 }, function(leg)
			leg:box(1, 0, -3, 1, 2, -3, CREAM)
		end)

		local tail = pet:limb("Tail", { 0, 5, -3 })
		tail:box(-1, 4, -6, 0, 6, -4, GINGER)
		tail:box(-1, 3, -8, 0, 5, -7, GINGER)
		tail:box(-1, 3, -9, 0, 4, -9, DARK)

		pet:seat(0, 7, -1)
	end,
}

Designs.Camel = {
	name = "Camel",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.5,
	draw = function(pet)
		local CAMEL = rgb(212, 162, 102)
		local SHAGGY = rgb(160, 112, 62)
		local DARK = rgb(110, 76, 44)
		local LIGHT = rgb(236, 204, 156)
		local LEATHER = rgb(140, 84, 44)
		local RED = rgb(196, 48, 52)
		local GOLD = rgb(255, 196, 56)
		local TEAL = rgb(56, 180, 176)

		-- Two shaggy humps, with the saddle blanket from its egg draped between them, a saddle,
		-- saddlebags and a rolled-up blanket.
		local body = pet:limb("Body", { 0, 9, 0 })
		body:box(-4, 8, -6, 3, 13, 5, CAMEL)
		body:paint(-3, 8, -5, 2, 8, 4, LIGHT)
		body:box(-3, 14, 1, 2, 16, 4, CAMEL)
		body:box(-2, 17, 2, 1, 17, 3, SHAGGY)
		body:paint(-3, 16, 1, 2, 16, 4, SHAGGY)
		body:box(-3, 14, -5, 2, 16, -2, CAMEL)
		body:box(-2, 17, -4, 1, 17, -3, SHAGGY)
		body:paint(-3, 16, -5, 2, 16, -2, SHAGGY)
		body:box(-5, 10, -1, 4, 14, 0, RED)
		body:paint(-5, 10, -1, 4, 10, 0, GOLD)
		body:paint(-5, 12, -1, 4, 12, 0, TEAL)
		body:boxPair(4, 9, -1, 4, 9, 0, GOLD)
		body:boxPair(4, 8, -1, 4, 8, -1, TEAL)
		body:boxPair(4, 8, 0, 4, 8, 0, RED)
		body:box(-2, 15, -1, 1, 15, 0, LEATHER)
		body:box(-1, 16, 0, 0, 16, 0, GOLD)
		body:boxPair(4, 9, -4, 5, 12, -2, LEATHER)
		body:paintPair(5, 12, -4, 5, 12, -2, DARK)
		body:paintPair(5, 11, -3, 5, 11, -3, GOLD)
		body:paintPair(5, 9, -4, 5, 9, -2, RED)
		body:box(-3, 14, -7, 2, 15, -6, TEAL)
		body:paint(-3, 14, -7, 2, 15, -7, GOLD)

		-- A long neck with a shaggy throat and a bell, sleepy eyes, a split lip, and a red bridle with gold rings.
		local head = pet:limb("Head", { 0, 12, 5 })
		head:box(-2, 10, 6, 1, 13, 8, CAMEL)
		head:box(-2, 9, 7, 1, 9, 8, SHAGGY)
		head:paint(-2, 13, 6, 1, 13, 8, SHAGGY)
		head:box(-1, 11, 9, 0, 12, 9, GOLD)
		head:box(-2, 14, 8, 1, 17, 9, CAMEL)
		head:box(-2, 18, 8, 1, 20, 12, CAMEL)
		head:box(-1, 21, 9, 0, 21, 10, SHAGGY)
		head:box(-2, 17, 13, 1, 18, 14, LIGHT)
		head:box(-1, 16, 13, 0, 16, 14, LIGHT)
		head:paintPair(1, 18, 14, 1, 18, 14, DARK)
		head:paint(-1, 17, 14, 0, 17, 14, DARK)
		head:paintPair(1, 19, 12, 1, 19, 12, EYE)
		head:paintPair(1, 20, 12, 1, 20, 12, DARK)
		head:boxPair(1, 21, 8, 1, 21, 8, CAMEL)
		head:paint(-2, 18, 13, 1, 18, 13, RED)
		head:paintPair(1, 19, 11, 1, 19, 11, GOLD)
		head:box(-1, 21, 11, 0, 22, 11, RED)
		head:box(-1, 23, 11, 0, 23, 11, GOLD)

		-- Long legs with knobbly knees and wide padded feet.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 8, 3.5 }, function(leg)
			leg:box(2, 4, 3, 3, 7, 4, CAMEL)
			leg:box(2, 1, 3, 3, 3, 4, CAMEL)
			leg:box(2, 0, 3, 3, 0, 5, DARK)
			leg:paint(2, 4, 4, 3, 4, 4, DARK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 8, -4.5 }, function(leg)
			leg:box(2, 4, -5, 3, 7, -4, CAMEL)
			leg:box(2, 1, -5, 3, 3, -4, CAMEL)
			leg:box(2, 0, -5, 3, 0, -3, DARK)
			leg:paint(2, 4, -4, 3, 4, -4, DARK)
		end)

		local tail = pet:limb("Tail", { 0, 12, -6 })
		tail:box(-1, 9, -7, 0, 12, -7, CAMEL)
		tail:box(-1, 7, -7, 0, 8, -7, SHAGGY)

		pet:seat(0, 16, -1)
	end,
}

Designs.GiantScorpion = {
	name = "Giant Scorpion",
	skeleton = "ManyLegged",
	scale = 0.55,
	draw = function(pet)
		local AMBER = rgb(176, 98, 44)
		local DARK = rgb(112, 58, 28)
		local LIGHT = rgb(214, 140, 70)
		local VENOM = rgb(150, 255, 90)

		-- A low body of overlapping plates, with a keel down the middle and pale spots.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 2, -5, 3, 4, 4, AMBER)
		body:box(-3, 5, -5, 2, 5, -4, AMBER)
		body:box(-3, 5, -2, 2, 5, -1, AMBER)
		body:box(-3, 5, 1, 2, 5, 3, AMBER)
		body:paint(-4, 4, -3, 3, 4, -3, DARK)
		body:paint(-4, 4, 0, 3, 4, 0, DARK)
		body:paint(-1, 5, -5, 0, 5, -4, LIGHT)
		body:paint(-1, 5, -2, 0, 5, -1, LIGHT)
		body:paint(-1, 5, 1, 0, 5, 3, LIGHT)
		body:paintPair(3, 2, -5, 3, 2, 4, DARK)
		body:paintPair(2, 5, -5, 2, 5, -5, LIGHT)
		body:paintPair(2, 5, 2, 2, 5, 2, LIGHT)

		-- A head with a mound of eyes, little fangs, and huge pincers with toothed edges.
		local head = pet:limb("Head", { 0, 3, 5 })
		head:box(-3, 2, 5, 2, 4, 6, AMBER)
		head:box(-1, 5, 5, 0, 5, 6, DARK)
		head:paint(-1, 5, 6, 0, 5, 6, VENOM, NEON)
		eyes(head, 1, 3, 6, 1)
		head:boxPair(0, 2, 7, 0, 3, 7, DARK)
		head:boxPair(3, 3, 5, 4, 3, 7, AMBER)
		head:boxPair(4, 3, 8, 5, 3, 9, AMBER)
		head:boxPair(3, 2, 10, 6, 4, 12, AMBER)
		head:boxPair(5, 3, 13, 6, 4, 15, AMBER)
		head:boxPair(3, 2, 13, 3, 3, 15, DARK)
		head:paintPair(5, 3, 13, 5, 3, 15, LIGHT)
		head:paintPair(5, 4, 15, 6, 4, 15, DARK)
		head:paintPair(4, 4, 10, 5, 4, 11, LIGHT)

		-- Six legs, each bent at a dark joint.
		local function leg(z: number)
			return function(limb)
				limb:box(4, 3, z, 5, 4, z, AMBER)
				limb:box(6, 4, z, 6, 4, z, DARK)
				limb:box(7, 1, z, 7, 3, z, AMBER)
				limb:box(7, 0, z, 8, 0, z, DARK)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 4, 3.5, 3.5 }, leg(3))
		pet:limbPair("MiddleLeftLeg", "MiddleRightLeg", { 4, 3.5, 0.5 }, leg(0))
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 4, 3.5, -2.5 }, leg(-3))

		-- A tail of shrinking segments arching over its back, with a venom bulb and a dripping stinger.
		local tail = pet:limb("Tail", { 0, 4, -5 })
		tail:box(-2, 3, -7, 1, 5, -6, AMBER)
		tail:box(-1, 6, -8, 0, 8, -7, AMBER)
		tail:box(-1, 9, -8, 0, 10, -7, AMBER)
		tail:box(-1, 11, -7, 0, 12, -6, AMBER)
		tail:box(-1, 13, -6, 0, 13, -4, AMBER)
		tail:box(-1, 13, -3, 0, 13, -2, DARK)
		tail:paint(-2, 5, -7, 1, 5, -7, DARK)
		tail:paint(-1, 8, -8, 0, 8, -8, DARK)
		tail:paint(-1, 10, -8, 0, 10, -8, DARK)
		tail:paint(-1, 12, -7, 0, 12, -7, DARK)
		tail:box(-1, 11, -1, 0, 13, 0, LIGHT)
		tail:box(-1, 9, 1, 0, 10, 1, VENOM, NEON)
		tail:box(-1, 8, 2, 0, 8, 2, VENOM, NEON)
		tail:box(-1, 6, 2, -1, 7, 2, VENOM, NEON)

		pet:seat(0, 6, 0)
	end,
}

Designs.PharaohJackal = {
	name = "Pharaoh Jackal",
	skeleton = "Quadruped",
	scale = 0.55,
	draw = function(pet)
		local BLACK = rgb(38, 34, 42)
		local SHEEN = rgb(66, 60, 76)
		local GOLD = rgb(255, 196, 56)
		local LAPIS = rgb(40, 86, 196)
		local TEAL = rgb(56, 180, 176)
		local RED = rgb(196, 48, 52)

		-- A sleek black body: deep chest, slim waist, a gold-and-lapis sash.
		local body = pet:limb("Body", { 0, 7, 0 })
		body:box(-3, 6, 1, 2, 10, 4, BLACK)
		body:box(-2, 6, -4, 1, 9, 0, BLACK)
		body:box(-3, 6, -7, 2, 10, -5, BLACK)
		body:paintPair(2, 8, -7, 2, 9, -6, SHEEN)
		body:paint(-1, 10, -7, 0, 10, -5, SHEEN)
		body:box(-3, 7, -3, 2, 10, -2, GOLD)
		body:paint(-3, 8, -3, 2, 8, -2, LAPIS)
		-- A broad collar in gold, teal and lapis, with an ankh hanging from it.
		body:box(-4, 9, 2, 3, 11, 5, GOLD)
		body:paint(-4, 10, 2, 3, 10, 5, TEAL)
		body:paint(-4, 9, 2, 3, 9, 5, LAPIS)
		body:box(-1, 9, 6, 0, 10, 6, GOLD)
		body:box(-2, 8, 6, 1, 8, 6, GOLD)
		body:box(-1, 6, 6, 0, 7, 6, GOLD)

		-- A long muzzle, glowing gold eyes lined in kohl, a striped headdress and tall ears.
		local head = pet:limb("Head", { 0, 11, 4 })
		head:box(-2, 12, 3, 1, 12, 5, BLACK)
		head:box(-2, 13, 3, 1, 16, 7, BLACK)
		head:box(-1, 13, 8, 0, 14, 11, BLACK)
		head:paint(-1, 13, 9, 0, 13, 11, SHEEN)
		head:box(-1, 14, 12, 0, 14, 12, SHEEN)
		head:paintPair(1, 15, 7, 1, 15, 7, GOLD, NEON)
		head:paintPair(1, 15, 5, 1, 15, 6, GOLD)
		head:box(-3, 17, 2, 2, 18, 7, GOLD)
		head:paint(-3, 18, 2, 2, 18, 2, LAPIS)
		head:paint(-3, 18, 4, 2, 18, 4, LAPIS)
		head:paint(-3, 18, 6, 2, 18, 6, LAPIS)
		head:paintPair(2, 17, 2, 2, 17, 7, LAPIS)
		head:paint(-1, 17, 7, 0, 17, 7, RED)
		head:boxPair(2, 12, 2, 2, 16, 3, GOLD)
		head:paintPair(2, 13, 2, 2, 13, 3, LAPIS)
		head:paintPair(2, 15, 2, 2, 15, 3, LAPIS)
		head:box(-2, 12, 1, 1, 16, 1, GOLD)
		head:paint(-2, 13, 1, 1, 13, 1, LAPIS)
		head:paint(-2, 15, 1, 1, 15, 1, LAPIS)
		head:boxPair(1, 19, 4, 2, 21, 5, BLACK)
		head:boxPair(2, 22, 4, 2, 23, 5, BLACK)
		head:paintPair(1, 19, 5, 1, 21, 5, GOLD)

		-- Slender legs with gold armbands.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 7, 2.5 }, function(leg)
			leg:box(1, 1, 2, 2, 5, 3, BLACK)
			leg:box(1, 0, 2, 2, 0, 4, BLACK)
			leg:paint(1, 4, 2, 2, 4, 3, GOLD)
			leg:paint(1, 1, 2, 2, 1, 3, LAPIS)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2, 7, -6 }, function(leg)
			leg:box(1, 3, -7, 2, 6, -5, BLACK)
			leg:box(1, 0, -7, 2, 2, -6, BLACK)
			leg:box(1, 0, -5, 2, 0, -5, BLACK)
			leg:paint(1, 1, -7, 2, 1, -6, GOLD)
		end)

		-- A long tail with gold rings.
		local tail = pet:limb("Tail", { 0, 9, -7 })
		tail:box(-1, 8, -9, 0, 9, -8, BLACK)
		tail:box(-1, 6, -10, 0, 8, -10, BLACK)
		tail:box(-1, 3, -11, 0, 6, -11, BLACK)
		tail:paint(-1, 7, -10, 0, 7, -10, GOLD)
		tail:paint(-1, 4, -11, 0, 4, -11, GOLD)

		pet:seat(0, 11, -2)
	end,
}

Designs.Sphinx = {
	name = "Sphinx",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local STONE = rgb(226, 192, 124)
		local STONE_LIGHT = rgb(242, 216, 164)
		local STONE_DARK = rgb(184, 148, 88)
		local CARVING = rgb(146, 112, 62)
		local GOLD = rgb(255, 196, 56)
		local LAPIS = rgb(40, 86, 196)
		local TEAL = rgb(56, 180, 176)

		-- A stone lion: deep chest, narrow waist, strong haunches, a ridge down its spine.
		local body = pet:limb("Body", { 0, 7, 0 })
		body:box(-4, 6, 1, 3, 12, 5, STONE)
		body:box(-3, 6, -5, 2, 10, 0, STONE)
		body:box(-4, 6, -8, 3, 11, -6, STONE)
		body:box(-1, 11, -5, 0, 11, 0, STONE_LIGHT)
		body:paint(-3, 6, -5, 2, 6, 0, STONE_DARK)
		-- Carved marks along its flanks, and lighter muscle on its haunches.
		body:paintPair(2, 8, -4, 2, 9, -4, CARVING)
		body:paintPair(2, 9, -2, 2, 9, -1, CARVING)
		body:paintPair(2, 7, -2, 2, 7, -2, CARVING)
		body:paintPair(3, 9, -8, 3, 10, -7, STONE_LIGHT)
		-- A broad jewelled collar with an amulet.
		body:box(-5, 9, 2, 4, 11, 6, GOLD)
		body:paint(-5, 10, 2, 4, 10, 6, TEAL)
		body:paint(-5, 9, 2, 4, 9, 6, LAPIS)
		body:box(-1, 8, 7, 0, 9, 7, GOLD)
		body:box(-1, 8, 8, 0, 8, 8, TEAL, NEON)
		-- Great feathered wings rising from its shoulders, banded gold and lapis.
		body:boxPair(4, 10, -1, 5, 12, 1, STONE)
		body:boxPair(5, 17, -3, 5, 17, 0, GOLD)
		body:boxPair(5, 16, -5, 5, 16, 1, LAPIS)
		body:boxPair(5, 15, -7, 5, 15, 1, GOLD)
		body:boxPair(5, 14, -8, 5, 14, 0, STONE_LIGHT)
		body:boxPair(5, 13, -9, 5, 13, -1, STONE_LIGHT)
		body:boxPair(5, 12, -9, 5, 12, -3, STONE_LIGHT)
		body:boxPair(5, 11, -8, 5, 11, -5, STONE_LIGHT)
		body:paintPair(5, 11, -7, 5, 14, -7, STONE_DARK)
		body:paintPair(5, 12, -4, 5, 14, -4, STONE_DARK)
		body:paintPair(5, 13, -9, 5, 13, -9, TEAL)
		body:paintPair(5, 12, -9, 5, 12, -9, TEAL)

		-- A calm face with glowing eyes, framed by a striped headdress, a rearing cobra and a gold beard.
		local head = pet:limb("Head", { 0, 12, 5 })
		head:box(-2, 11, 5, 1, 12, 5, STONE)
		head:box(-3, 13, 5, 2, 18, 9, STONE)
		head:box(-1, 13, 10, 0, 15, 10, STONE)
		head:paint(-1, 15, 10, 0, 15, 10, STONE_DARK)
		head:paint(-1, 13, 10, 0, 13, 10, CARVING)
		head:paintPair(2, 16, 9, 2, 16, 9, LAPIS)
		head:paintPair(1, 16, 9, 1, 16, 9, TEAL, NEON)
		head:box(-4, 18, 4, 3, 19, 10, GOLD)
		head:paint(-4, 19, 4, 3, 19, 4, LAPIS)
		head:paint(-4, 19, 6, 3, 19, 6, LAPIS)
		head:paint(-4, 19, 8, 3, 19, 8, LAPIS)
		head:boxPair(3, 11, 6, 3, 17, 8, GOLD)
		head:boxPair(3, 10, 6, 4, 10, 8, GOLD)
		head:paintPair(3, 12, 6, 3, 12, 8, LAPIS)
		head:paintPair(3, 15, 6, 3, 15, 8, LAPIS)
		head:box(-3, 13, 4, 2, 18, 4, GOLD)
		head:paint(-3, 14, 4, 2, 14, 4, LAPIS)
		head:paint(-3, 16, 4, 2, 16, 4, LAPIS)
		head:box(-1, 19, 10, 0, 20, 10, GOLD)
		head:box(-1, 21, 10, 0, 21, 11, GOLD)
		head:box(-1, 20, 11, 0, 20, 11, TEAL, NEON)
		head:box(-1, 10, 9, 0, 12, 9, GOLD)
		head:paint(-1, 11, 9, 0, 11, 9, LAPIS)
		head:box(-1, 10, 10, 0, 10, 10, GOLD)

		-- Lion legs with big paws, gold bands on the front ones.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 7, 3 }, function(leg)
			leg:box(2, 3, 2, 3, 7, 4, STONE)
			leg:box(2, 0, 3, 3, 2, 4, STONE)
			leg:box(2, 0, 5, 4, 1, 6, STONE)
			leg:paint(3, 1, 5, 3, 1, 6, STONE_DARK)
			leg:paint(2, 0, 6, 4, 0, 6, CARVING)
			leg:paint(2, 5, 2, 3, 5, 4, GOLD)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 7, -6 }, function(leg)
			leg:box(3, 3, -8, 4, 9, -5, STONE)
			leg:box(2, 0, -7, 3, 2, -6, STONE)
			leg:box(2, 0, -5, 3, 0, -4, STONE)
			leg:paint(2, 0, -4, 3, 0, -4, CARVING)
		end)

		-- A lion's tail curling up over its rump, with a gold band and a dark tuft.
		local tail = pet:limb("Tail", { 0, 9, -8 })
		tail:box(-1, 8, -10, 0, 9, -9, STONE)
		tail:box(-1, 10, -11, 0, 12, -11, STONE)
		tail:box(-1, 13, -11, 0, 13, -10, STONE)
		tail:box(-2, 13, -9, 1, 15, -8, STONE_DARK)
		tail:paint(-1, 10, -11, 0, 10, -11, GOLD)

		pet:light(GOLD, 2, 14)
		pet:particles("Sparkles", GOLD, 6)
		pet:seat(0, 12, -3)
	end,
}

Designs.GoldenScarab = {
	name = "Golden Scarab",
	skeleton = "ManyLegged",
	scale = 0.6,
	draw = function(pet)
		local SCARAB = rgb(240, 186, 50)
		local GOLD_LIGHT = rgb(255, 224, 120)
		local BRONZE = rgb(196, 128, 38)
		local BRONZE_DARK = rgb(120, 76, 24)
		local TEAL = rgb(56, 180, 176)
		local LAPIS = rgb(40, 86, 196)
		local SEAM = rgb(86, 56, 20)
		local SUN = rgb(255, 196, 60)
		local SUN_CORE = rgb(255, 240, 170)

		-- A rounded golden shell, split down the middle, inlaid with teal and lapis bands.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 2, -6, 3, 5, 2, SCARAB)
		body:box(-5, 3, -5, 4, 4, 1, SCARAB)
		body:box(-3, 6, -5, 2, 6, 1, SCARAB)
		body:box(-2, 7, -4, 1, 7, 0, SCARAB)
		body:box(-3, 3, -7, 2, 5, -7, SCARAB)
		body:box(-1, 8, -4, 0, 8, 0, BRONZE)
		body:paint(-1, 2, -7, 0, 5, -7, SEAM)
		for _, band in { { -3, TEAL }, { -1, LAPIS } } do
			local z, color = band[1], band[2]
			body:paint(-5, 3, z, 4, 4, z, color)
			body:paint(-4, 5, z, 3, 5, z, color)
			body:paint(-3, 6, z, 2, 6, z, color)
		end
		body:paint(-2, 7, -4, -2, 7, -4, GOLD_LIGHT)
		body:paint(1, 7, -2, 1, 7, -2, GOLD_LIGHT)
		-- A bronze plate behind its head, rimmed in pale gold.
		body:box(-4, 2, 3, 3, 5, 5, BRONZE)
		body:box(-3, 6, 3, 2, 6, 4, BRONZE)
		body:paint(-4, 5, 5, 3, 5, 5, GOLD_LIGHT)
		-- Jewelled wings spread out from under its shell, like on a temple wall.
		body:boxPair(5, 4, -4, 7, 4, 1, SCARAB)
		body:boxPair(8, 4, -6, 9, 4, 0, LAPIS)
		body:boxPair(10, 4, -6, 10, 4, -2, TEAL)
		body:boxPair(11, 4, -5, 11, 4, -3, TEAL)
		body:boxPair(8, 5, -5, 10, 5, -3, GOLD_LIGHT)
		body:paintPair(8, 4, -3, 9, 4, -3, SCARAB)
		body:paintPair(10, 4, -6, 11, 4, -6, SCARAB)

		-- A shovel head with a toothed edge, clubbed feelers, and a horn holding up a blazing sun.
		local head = pet:limb("Head", { 0, 3, 6 })
		head:box(-3, 2, 6, 2, 4, 7, BRONZE_DARK)
		head:box(-3, 2, 8, 2, 2, 8, BRONZE)
		head:boxPair(2, 2, 9, 2, 2, 9, BRONZE)
		head:boxPair(0, 2, 9, 0, 2, 9, BRONZE)
		eyes(head, 2, 3, 7, 1, 1)
		head:boxPair(2, 5, 7, 2, 5, 7, BRONZE_DARK)
		head:boxPair(3, 6, 7, 3, 6, 7, BRONZE_DARK)
		head:boxPair(3, 6, 8, 3, 7, 8, GOLD_LIGHT)
		head:box(-1, 5, 6, 0, 8, 6, BRONZE_DARK)
		head:box(-1, 9, 6, 0, 9, 7, SUN, NEON)
		head:box(-2, 10, 6, 1, 10, 7, SUN, NEON)
		head:box(-3, 11, 6, 2, 12, 7, SUN, NEON)
		head:box(-2, 13, 6, 1, 13, 7, SUN, NEON)
		head:box(-1, 14, 6, 0, 14, 7, SUN, NEON)
		head:paint(-2, 11, 7, 1, 12, 7, SUN_CORE, NEON)
		head:paint(-1, 10, 7, 0, 13, 7, SUN_CORE, NEON)
		head:boxPair(3, 11, 6, 4, 12, 6, SUN, NEON)
		head:box(-1, 15, 6, 0, 16, 6, SUN, NEON)
		head:boxPair(2, 14, 6, 2, 14, 6, SUN, NEON)

		-- Six spiny legs; the front pair are toothed for digging.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 4, 3, 4.5 }, function(leg)
			leg:box(4, 2, 4, 5, 3, 4, BRONZE_DARK)
			leg:box(6, 0, 5, 6, 3, 5, BRONZE_DARK)
			leg:box(7, 1, 5, 7, 1, 5, BRONZE)
			leg:box(7, 3, 5, 7, 3, 5, BRONZE)
		end)
		local function leg(z: number)
			return function(limb)
				limb:box(5, 3, z, 6, 3, z, BRONZE_DARK)
				limb:box(7, 0, z, 7, 3, z, BRONZE_DARK)
				limb:box(8, 2, z, 8, 2, z, BRONZE)
			end
		end
		pet:limbPair("MiddleLeftLeg", "MiddleRightLeg", { 5, 3.5, 0.5 }, leg(0))
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 5, 3.5, -3.5 }, leg(-4))

		local tail = pet:limb("Tail", { 0, 3, -7 })
		tail:box(-1, 2, -8, 0, 3, -8, BRONZE)

		pet:light(SUN, 2.2, 14)
		pet:particles("Sparkles", SUN, 8)
		pet:seat(0, 9, -2)
	end,
}

return Designs
