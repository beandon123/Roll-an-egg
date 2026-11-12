--!strict
-- The look of every pet, by name. Which egg each pet hatches from is set in Config/Zones (`pet`).
-- Each design draws limbs on the pet builder in PetModels:
--     x left (+x) and right (-x); y up from the ground; z forward. A cell numbered x covers x to x + 1.
--     limb:box() draws a solid block, limb:paint() colours the surface of blocks already drawn (eyes, bellies),
--     and the ...Pair versions mirror across the middle of the pet.
-- Pets have big heads and small bodies, like the eggs they come from, and are themed to match their egg.
-- So far: the Forest, Desert, Snow and Ocean pets. The Volcano pets come next.
-- Secret and Eternal pets are the showpieces, far more detailed than the rest (the tests check this).

type Color = { number }
type Pet = any
type Limb = any
type Design = {
	name: string,
	-- One of PetModels.SKELETONS: decides which limbs the pet has and so which animations it uses.
	skeleton: string,
	-- How it moves: "Walk" (default), "Hop", "Waddle", "Stomp", "Swim" or "Crawl".
	gait: string?,
	-- How high it floats, in voxels, for pets that swim through the air.
	hover: number?,
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

-- Draws on a limb as if it were on the other side of the pet (x mirrored), for limbs that are mirror images
-- except for something only one side has, like a club in one hand.
local function mirrored(limb: Limb): Limb
	return {
		box = function(_, x0, y0, z0, x1, y1, z1, ...)
			limb:box(-1 - x0, y0, z0, -1 - x1, y1, z1, ...)
		end,
		paint = function(_, x0, y0, z0, x1, y1, z1, ...)
			limb:paint(-1 - x0, y0, z0, -1 - x1, y1, z1, ...)
		end,
	}
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

----------------------------------------------------------------------------------------------------------------
-- Snow

Designs.SnowHare = {
	name = "Snow Hare",
	skeleton = "Quadruped",
	gait = "Hop",
	scale = 0.45,
	draw = function(pet)
		local WHITE = rgb(246, 250, 255)
		local SHADE = rgb(214, 228, 244)
		local FROST = rgb(170, 210, 245)
		local TIP = rgb(44, 46, 58)
		local PINK = rgb(255, 172, 188)

		-- A round white body with frosty shading, a fluffy chest and a puffed-up back.
		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-3, 2, -3, 2, 6, 2, WHITE)
		body:box(-2, 7, -2, 1, 7, 1, WHITE)
		body:box(-2, 3, 3, 1, 5, 3, WHITE)
		body:paint(-3, 2, -3, 2, 2, 2, SHADE)
		body:paintPair(2, 3, -3, 2, 4, -1, SHADE)

		-- Fluffy cheeks, a frost mark on its forehead, and long ears with black tips.
		local head = pet:limb("Head", { 0, 7, 1 })
		head:box(-3, 8, -1, 2, 12, 4, WHITE)
		head:box(-4, 8, 0, 3, 9, 3, WHITE)
		head:paint(-1, 9, 4, 0, 9, 4, PINK)
		head:box(-1, 8, 5, 0, 8, 5, SHINE)
		head:paint(-1, 11, 4, 0, 12, 4, FROST)
		head:paintPair(2, 8, 3, 3, 8, 3, PINK)
		eyes(head, 1, 10, 4, 1)
		head:boxPair(1, 13, 1, 2, 18, 2, WHITE)
		head:paintPair(1, 14, 2, 1, 17, 2, FROST)
		head:boxPair(1, 19, 1, 2, 19, 2, TIP)
		head:paintPair(1, 18, 1, 2, 18, 2, TIP)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 3, 2 }, function(leg)
			leg:box(1, 0, 1, 2, 2, 2, WHITE)
			leg:paint(1, 0, 2, 2, 0, 2, SHADE)
		end)
		-- Big snowshoe hind feet.
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2.5, 4, -2 }, function(leg)
			leg:box(1, 1, -3, 3, 4, -1, WHITE)
			leg:box(1, 0, -4, 3, 0, 1, WHITE)
			leg:paint(1, 0, 1, 3, 0, 1, SHADE)
		end)

		local tail = pet:limb("Tail", { 0, 4, -3 })
		tail:box(-1, 3, -5, 0, 5, -4, WHITE)
		tail:paint(-1, 3, -5, 0, 3, -4, SHADE)

		pet:seat(0, 8, -1)
	end,
}

Designs.ArcticFox = {
	name = "Arctic Fox",
	skeleton = "Quadruped",
	scale = 0.5,
	draw = function(pet)
		local WHITE = rgb(244, 248, 255)
		local SHADE = rgb(210, 226, 242)
		local ICE = rgb(150, 206, 244)
		local DARK = rgb(40, 44, 56)

		-- A thick white coat with a fluffy ruff, ice-blue socks like the bottom of its egg.
		local body = pet:limb("Body", { 0, 5, 0 })
		body:box(-3, 3, -4, 2, 7, 3, WHITE)
		body:box(-4, 6, 2, 3, 8, 4, WHITE)
		body:box(-2, 3, 4, 1, 5, 4, WHITE)
		body:paint(-3, 3, -4, 2, 3, 3, SHADE)
		body:paint(-2, 7, -4, 1, 7, -1, SHADE)

		local head = pet:limb("Head", { 0, 8, 3 })
		head:box(-3, 8, 2, 2, 12, 7, WHITE)
		head:boxPair(3, 8, 4, 3, 9, 6, WHITE)
		head:box(-1, 8, 8, 0, 9, 9, WHITE)
		head:box(-1, 9, 10, 0, 9, 10, DARK)
		head:paint(-1, 8, 9, 0, 8, 9, SHADE)
		eyes(head, 1, 10, 7, 1)
		-- Short rounded ears, icy inside.
		head:boxPair(1, 13, 4, 2, 14, 5, WHITE)
		head:paintPair(1, 13, 5, 1, 14, 5, ICE)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 4, 2 }, function(leg)
			leg:box(1, 0, 1, 2, 3, 2, WHITE)
			leg:paint(1, 0, 1, 2, 1, 2, ICE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2, 4, -3 }, function(leg)
			leg:box(1, 0, -4, 2, 3, -3, WHITE)
			leg:paint(1, 0, -4, 2, 1, -3, ICE)
		end)

		-- A huge fluffy tail with an ice-blue tip.
		local tail = pet:limb("Tail", { 0, 6, -4 })
		tail:box(-2, 5, -7, 1, 7, -5, WHITE)
		tail:box(-3, 4, -10, 2, 7, -8, WHITE)
		tail:box(-2, 4, -11, 1, 6, -11, WHITE)
		tail:box(-2, 4, -12, 1, 6, -12, ICE)
		tail:paint(-3, 4, -10, 2, 4, -8, SHADE)

		pet:seat(0, 9, -1)
	end,
}

Designs.Reindeer = {
	name = "Reindeer",
	skeleton = "Quadruped",
	scale = 0.5,
	draw = function(pet)
		local FUR = rgb(138, 98, 66)
		local FUR_DARK = rgb(100, 70, 46)
		local CREAM = rgb(236, 226, 206)
		local ANTLER = rgb(214, 196, 160)
		local HOOF = rgb(52, 40, 34)
		local RED = rgb(212, 52, 62)
		local GREEN = rgb(58, 140, 84)
		local KNIT = rgb(246, 238, 222)
		local GOLD = rgb(255, 200, 60)

		-- A sturdy deer with a pale ruff and rump, wearing the knitted blanket from its egg and a belled harness.
		local body = pet:limb("Body", { 0, 8, 0 })
		body:box(-4, 7, 1, 3, 11, 5, FUR)
		body:box(-3, 7, -5, 2, 10, 0, FUR)
		body:box(-4, 7, -8, 3, 11, -6, FUR)
		body:paint(-3, 7, -5, 2, 7, 0, CREAM)
		body:paint(-3, 8, -8, 2, 10, -8, CREAM)
		body:box(-3, 8, 5, 2, 10, 6, CREAM)
		body:box(-2, 7, 6, 1, 7, 6, CREAM)
		body:box(-5, 9, -4, 4, 11, -1, RED)
		body:paint(-5, 10, -4, 4, 10, -1, KNIT)
		body:paintPair(4, 10, -4, 4, 10, -4, GREEN)
		body:paintPair(4, 10, -2, 4, 10, -2, GREEN)
		body:paint(-1, 11, -4, 0, 11, -1, GREEN)
		body:boxPair(4, 8, -4, 4, 8, -4, KNIT)
		body:boxPair(4, 8, -1, 4, 8, -1, KNIT)
		body:paint(-4, 10, 1, 3, 10, 5, RED)
		body:box(-1, 8, 7, 0, 9, 7, GOLD)
		body:boxPair(4, 9, 3, 4, 9, 3, GOLD)

		-- A gentle face and great branching antlers, with a sprig of holly caught in one.
		local head = pet:limb("Head", { 0, 11, 5 })
		head:box(-2, 11, 4, 1, 14, 6, FUR)
		head:box(-3, 14, 5, 2, 17, 9, FUR)
		head:box(-2, 14, 10, 1, 15, 11, CREAM)
		head:box(-1, 15, 12, 0, 15, 12, HOOF)
		head:paint(-3, 17, 9, 2, 17, 9, FUR_DARK)
		eyes(head, 1, 15, 9, 1)
		head:boxPair(3, 16, 6, 4, 16, 7, FUR)
		head:paintPair(3, 16, 7, 4, 16, 7, CREAM)
		head:boxPair(1, 18, 6, 1, 20, 7, ANTLER)
		head:boxPair(1, 19, 8, 1, 19, 9, ANTLER)
		head:boxPair(2, 21, 6, 5, 21, 7, ANTLER)
		head:boxPair(2, 22, 6, 2, 23, 7, ANTLER)
		head:boxPair(5, 22, 6, 5, 22, 7, ANTLER)
		head:boxPair(3, 24, 6, 7, 24, 7, ANTLER)
		head:boxPair(3, 25, 6, 3, 26, 7, ANTLER)
		head:boxPair(5, 25, 6, 5, 26, 7, ANTLER)
		head:boxPair(7, 25, 6, 7, 26, 7, ANTLER)
		head:box(5, 21, 8, 6, 21, 8, GREEN)
		head:box(5, 22, 8, 5, 22, 8, RED)
		head:box(6, 20, 8, 6, 20, 8, RED)

		-- Long legs with shaggy pale fur over wide hooves.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 8, 3.5 }, function(leg)
			leg:box(2, 4, 3, 3, 7, 4, FUR)
			leg:box(2, 1, 3, 3, 3, 4, FUR_DARK)
			leg:paint(2, 1, 3, 3, 1, 4, CREAM)
			leg:box(2, 0, 3, 3, 0, 5, HOOF)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 8, -6.5 }, function(leg)
			leg:box(3, 5, -8, 4, 10, -5, FUR)
			leg:box(2, 1, -7, 3, 4, -6, FUR_DARK)
			leg:paint(2, 1, -7, 3, 1, -6, CREAM)
			leg:box(2, 0, -7, 3, 0, -5, HOOF)
		end)

		local tail = pet:limb("Tail", { 0, 10, -8 })
		tail:box(-1, 9, -9, 0, 11, -9, CREAM)

		pet:seat(0, 12, -2)
	end,
}

Designs.FrostWolf = {
	name = "Frost Wolf",
	skeleton = "Quadruped",
	scale = 0.55,
	draw = function(pet)
		local WOLF = rgb(164, 184, 212)
		local WOLF_DARK = rgb(92, 110, 152)
		local WHITE = rgb(240, 246, 255)
		local ICE = rgb(196, 240, 255)
		local GLOW = rgb(130, 236, 255)
		local NOSE = rgb(36, 40, 56)

		-- A lean wolf with a dark saddle, a white chest, and ice crystals growing along its back.
		local body = pet:limb("Body", { 0, 7, 0 })
		body:box(-4, 6, 1, 3, 11, 5, WOLF)
		body:box(-3, 6, -5, 2, 10, 0, WOLF)
		body:box(-4, 6, -8, 3, 10, -6, WOLF)
		body:paint(-3, 10, -5, 2, 10, 0, WOLF_DARK)
		body:paint(-4, 11, 1, 3, 11, 3, WOLF_DARK)
		body:paint(-4, 10, -8, 3, 10, -6, WOLF_DARK)
		body:paint(-2, 6, 5, 1, 10, 5, WHITE)
		body:paint(-3, 6, -5, 2, 6, 0, WHITE)
		body:box(-1, 12, 1, 0, 14, 2, ICE, GLASS, 0.15)
		body:boxPair(2, 12, 2, 2, 13, 3, ICE, GLASS, 0.15)
		body:box(-1, 11, -2, 0, 12, -2, ICE, GLASS, 0.15)
		body:box(-1, 11, -4, 0, 11, -4, ICE, GLASS, 0.15)
		body:box(-1, 11, -7, 0, 12, -7, ICE, GLASS, 0.15)

		-- A long snout with icy fangs, glowing eyes under a dark brow, and tall ears.
		local head = pet:limb("Head", { 0, 11, 5 })
		head:box(-2, 10, 5, 1, 13, 6, WOLF)
		head:box(-3, 9, 6, 2, 10, 7, WHITE)
		head:box(-3, 13, 5, 2, 17, 9, WOLF)
		head:box(-2, 13, 10, 1, 15, 12, WHITE)
		head:box(-1, 15, 13, 0, 15, 13, NOSE)
		head:paint(-2, 13, 10, 1, 13, 12, WOLF_DARK)
		head:boxPair(1, 12, 12, 1, 12, 12, ICE, GLASS, 0.15)
		head:paintPair(2, 13, 9, 2, 15, 9, WHITE)
		head:paintPair(1, 16, 9, 1, 16, 9, GLOW, NEON)
		head:paintPair(1, 17, 9, 2, 17, 9, WOLF_DARK)
		head:paint(-1, 17, 9, 0, 17, 9, WHITE)
		head:boxPair(1, 18, 6, 2, 19, 7, WOLF)
		head:boxPair(2, 20, 6, 2, 20, 7, WOLF_DARK)
		head:paintPair(1, 18, 7, 1, 19, 7, WHITE)

		-- Legs with white socks and claws of ice.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 7, 3.5 }, function(leg)
			leg:box(2, 3, 3, 3, 6, 4, WOLF)
			leg:box(2, 0, 3, 3, 2, 4, WOLF_DARK)
			leg:paint(2, 0, 3, 3, 1, 4, WHITE)
			leg:box(2, 0, 5, 3, 0, 5, ICE, GLASS, 0.15)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 7, -6.5 }, function(leg)
			leg:box(3, 4, -8, 4, 9, -5, WOLF)
			leg:box(2, 0, -7, 3, 3, -6, WOLF_DARK)
			leg:paint(2, 0, -7, 3, 1, -6, WHITE)
			leg:box(2, 0, -5, 3, 0, -5, ICE, GLASS, 0.15)
		end)

		-- A bushy tail with a white tip and a crust of frost.
		local tail = pet:limb("Tail", { 0, 9, -8 })
		tail:box(-2, 8, -10, 1, 10, -9, WOLF)
		tail:box(-2, 6, -12, 1, 9, -11, WOLF)
		tail:box(-2, 5, -13, 1, 7, -13, WHITE)
		tail:box(-1, 8, -13, 0, 8, -13, ICE, GLASS, 0.15)
		tail:paint(-2, 10, -10, 1, 10, -9, WOLF_DARK)

		pet:seat(0, 12, -2)
	end,
}

Designs.SabertoothCat = {
	name = "Sabertooth Cat",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.6,
	draw = function(pet)
		local FUR = rgb(236, 230, 218)
		local SHADE = rgb(206, 198, 184)
		local STRIPE = rgb(74, 84, 104)
		local IVORY = rgb(250, 240, 214)
		local NOSE = rgb(120, 86, 86)
		local MOUTH = rgb(60, 50, 56)
		local ICE = rgb(150, 206, 244)
		local CRYSTAL = rgb(196, 240, 255)

		-- A powerful pale cat: high shoulders, slim waist, heavy hips, slate stripes and an ice-blue collar.
		local body = pet:limb("Body", { 0, 8, 0 })
		body:box(-5, 7, 0, 4, 13, 5, FUR)
		body:box(-4, 7, -5, 3, 11, -1, FUR)
		body:box(-4, 7, -9, 3, 12, -6, FUR)
		body:paint(-4, 7, -5, 3, 7, -1, SHADE)
		body:paint(-5, 13, 2, 4, 13, 2, STRIPE)
		body:paintPair(4, 10, 2, 4, 13, 2, STRIPE)
		for _, z in { -4, -2 } do
			body:paint(-4, 11, z, 3, 11, z, STRIPE)
			body:paintPair(3, 9, z, 3, 11, z, STRIPE)
		end
		body:paint(-4, 12, -8, 3, 12, -8, STRIPE)
		body:paintPair(3, 9, -8, 3, 12, -8, STRIPE)
		body:box(-6, 11, 4, 5, 12, 6, ICE)
		body:boxPair(6, 11, 5, 6, 12, 5, CRYSTAL, GLASS, 0.15)
		body:box(-1, 11, 7, 0, 12, 7, CRYSTAL, GLASS, 0.15)

		-- A broad head with a heavy brow, glowing ice eyes, cheek ruffs, tufted ears and huge sabre fangs.
		local head = pet:limb("Head", { 0, 12, 6 })
		head:box(-4, 12, 6, 3, 17, 10, FUR)
		head:box(-3, 16, 11, 2, 16, 11, SHADE)
		head:box(-2, 12, 11, 1, 14, 12, FUR)
		head:box(-1, 14, 13, 0, 14, 13, NOSE)
		head:paint(-2, 12, 12, 1, 12, 12, MOUTH)
		head:paintPair(1, 13, 12, 1, 13, 12, STRIPE)
		head:boxPair(1, 10, 13, 1, 12, 13, IVORY)
		head:boxPair(1, 8, 12, 1, 9, 12, IVORY)
		head:paintPair(1, 15, 10, 2, 15, 10, ICE, NEON)
		head:paint(-1, 17, 6, 0, 17, 10, STRIPE)
		head:paintPair(2, 17, 7, 2, 17, 8, STRIPE)
		head:boxPair(4, 12, 7, 4, 15, 9, FUR)
		head:paintPair(4, 13, 7, 4, 13, 9, STRIPE)
		head:boxPair(2, 18, 7, 3, 19, 8, FUR)
		head:boxPair(3, 20, 7, 3, 20, 7, STRIPE)
		head:paintPair(2, 18, 8, 2, 18, 8, SHADE)

		-- Thick striped legs with big paws and ivory claws.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3.5, 8, 3 }, function(leg)
			leg:box(2, 3, 2, 4, 7, 4, FUR)
			leg:box(2, 0, 2, 4, 2, 5, FUR)
			leg:box(2, 0, 6, 4, 0, 6, IVORY)
			leg:paint(3, 0, 5, 3, 1, 5, SHADE)
			leg:paint(2, 5, 2, 4, 5, 4, STRIPE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3.5, 8, -7.5 }, function(leg)
			leg:box(3, 4, -9, 5, 10, -6, FUR)
			leg:box(2, 0, -8, 4, 3, -7, FUR)
			leg:box(2, 0, -6, 4, 0, -6, FUR)
			leg:paint(5, 6, -8, 5, 9, -8, STRIPE)
			leg:paint(2, 2, -8, 4, 2, -7, STRIPE)
		end)

		-- A short bobtail.
		local tail = pet:limb("Tail", { 0, 11, -9 })
		tail:box(-1, 10, -11, 0, 12, -10, FUR)
		tail:paint(-1, 12, -11, 0, 12, -11, STRIPE)

		pet:light(ICE, 1.6, 12)
		pet:seat(0, 14, -2)
	end,
}

Designs.AuroraOwl = {
	name = "Aurora Owl",
	skeleton = "Winged",
	gait = "Waddle",
	scale = 0.55,
	draw = function(pet)
		local NIGHT = rgb(30, 40, 92)
		local NIGHT_LIGHT = rgb(52, 66, 132)
		local FEATHER = rgb(86, 116, 196)
		local CHEST = rgb(226, 234, 252)
		local MARK = rgb(160, 182, 228)
		local GREEN = rgb(90, 255, 170)
		local TEAL = rgb(80, 220, 255)
		local VIOLET = rgb(182, 124, 255)
		local STAR = rgb(255, 255, 255)
		local BEAK = rgb(240, 200, 120)
		local TALON = rgb(60, 60, 80)

		-- A night-blue owl whose back is speckled with stars.
		local body = pet:limb("Body", { 0, 2, 0 })
		body:box(-4, 2, -3, 3, 10, 3, NIGHT)
		body:box(-3, 3, 4, 2, 9, 4, CHEST)
		body:paintPair(1, 8, 4, 2, 8, 4, MARK)
		body:paintPair(2, 6, 4, 2, 6, 4, MARK)
		body:paint(-1, 7, 4, 0, 7, 4, MARK)
		body:paint(-1, 5, 4, 0, 5, 4, MARK)
		body:paintPair(1, 4, 4, 1, 4, 4, MARK)
		body:paint(-3, 9, -3, -3, 9, -3, STAR, NEON)
		body:paint(2, 7, -3, 2, 7, -3, STAR, NEON)
		body:paint(-1, 5, -3, -1, 5, -3, STAR, NEON)
		body:paint(1, 3, -3, 1, 3, -3, STAR, NEON)
		body:paint(-3, 4, -3, -3, 4, -3, STAR, NEON)
		body:paint(0, 9, -3, 0, 9, -3, STAR, NEON)

		-- A pale face disc, glowing eyes under aurora brows, a hooked beak and tufts tipped with light.
		local head = pet:limb("Head", { 0, 11, 0 })
		head:box(-4, 11, -3, 3, 16, 3, NIGHT)
		head:box(-3, 17, -2, 2, 17, 2, NIGHT)
		head:paint(-4, 11, 3, 3, 15, 3, CHEST)
		head:paint(-4, 11, 3, -4, 15, 3, FEATHER)
		head:paint(3, 11, 3, 3, 15, 3, FEATHER)
		head:paintPair(1, 12, 3, 2, 13, 3, TEAL, NEON)
		head:paintPair(1, 12, 3, 1, 13, 3, NIGHT)
		head:paintPair(1, 13, 3, 1, 13, 3, STAR)
		head:boxPair(1, 15, 4, 3, 15, 4, VIOLET, NEON)
		head:box(-1, 11, 4, 0, 12, 4, BEAK)
		head:box(-1, 10, 5, 0, 11, 5, BEAK)
		head:boxPair(2, 18, -1, 3, 18, 0, NIGHT)
		head:boxPair(3, 19, -1, 4, 19, 0, FEATHER)
		head:boxPair(4, 20, -1, 5, 20, 0, TEAL, NEON)
		head:boxPair(5, 21, -1, 5, 21, 0, GREEN, NEON)
		head:paint(-2, 16, -3, -2, 16, -3, STAR, NEON)
		head:paint(1, 14, -3, 1, 14, -3, STAR, NEON)
		head:paint(-1, 17, 1, -1, 17, 1, STAR, NEON)

		-- Half-open wings banded with the northern lights.
		pet:limbPair("LeftWing", "RightWing", { 4.5, 10, 0 }, function(wing)
			wing:box(4, 6, -2, 5, 10, 2, NIGHT_LIGHT)
			wing:box(4, 3, -3, 5, 5, 1, FEATHER)
			wing:box(4, 1, -6, 4, 4, -4, FEATHER)
			wing:paint(5, 8, -2, 5, 8, 2, GREEN, NEON)
			wing:paint(5, 6, -2, 5, 6, 2, TEAL, NEON)
			wing:paint(5, 4, -3, 5, 4, 1, VIOLET, NEON)
			wing:paint(4, 2, -6, 4, 2, -4, TEAL, NEON)
		end)
		pet:limbPair("LeftLeg", "RightLeg", { 2, 2, 1 }, function(leg)
			leg:box(1, 1, 0, 2, 1, 1, CHEST)
			leg:box(1, 0, 0, 2, 0, 2, BEAK)
			leg:paint(1, 0, 2, 2, 0, 2, TALON)
		end)

		-- Long trailing tail feathers with glowing tips.
		local tail = pet:limb("Tail", { 0, 4, -3 })
		tail:box(-2, 3, -5, 1, 5, -4, NIGHT)
		tail:box(-1, 2, -11, 0, 3, -6, FEATHER)
		tail:box(-1, 2, -12, 0, 2, -12, TEAL, NEON)
		tail:boxPair(1, 3, -9, 2, 3, -6, FEATHER)
		tail:boxPair(1, 3, -10, 2, 3, -10, VIOLET, NEON)
		tail:paint(-1, 3, -9, 0, 3, -9, GREEN, NEON)

		pet:light(TEAL, 1.8, 13)
		pet:particles("Sparkles", GREEN, 8)
		pet:seat(0, 18, -1)
	end,
}

Designs.WoollyMammoth = {
	name = "Woolly Mammoth",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local WOOL = rgb(120, 78, 48)
		local WOOL_DARK = rgb(88, 56, 34)
		local WOOL_LIGHT = rgb(150, 104, 66)
		local SNOW = rgb(246, 250, 255)
		local IVORY = rgb(250, 240, 214)
		local IVORY_DARK = rgb(222, 206, 168)
		local ICE = rgb(196, 240, 255)

		-- A huge shaggy body with a shoulder hump, a curtain of long fur with icicles, snow on its back and
		-- frost crystals growing out of the snow.
		local body = pet:limb("Body", { 0, 10, 0 })
		body:box(-6, 7, -7, 5, 15, 5, WOOL)
		body:box(-4, 16, -1, 3, 17, 4, WOOL)
		body:box(-5, 8, -8, 4, 14, -8, WOOL)
		body:boxPair(6, 6, -6, 6, 13, 4, WOOL_DARK)
		body:boxPair(6, 5, -5, 6, 5, -4, WOOL_DARK)
		body:boxPair(6, 4, -1, 6, 5, -1, WOOL_DARK)
		body:boxPair(6, 5, 2, 6, 5, 3, WOOL_DARK)
		body:box(-5, 6, -3, 4, 6, 0, WOOL_DARK)
		body:box(-3, 5, -3, -2, 5, -2, WOOL_DARK)
		body:box(1, 5, -1, 2, 5, -1, WOOL_DARK)
		body:paint(-4, 15, -5, -3, 15, -2, WOOL_LIGHT)
		body:paint(1, 15, -6, 2, 15, -3, WOOL_LIGHT)
		body:paintPair(6, 10, -3, 6, 12, -2, WOOL)
		body:box(-3, 16, -6, 2, 16, -2, SNOW)
		body:paint(-3, 17, 0, 2, 17, 3, SNOW)
		body:box(-1, 17, -5, 0, 19, -5, ICE, GLASS, 0.15)
		body:boxPair(2, 17, -4, 2, 18, -4, ICE, GLASS, 0.15)
		body:box(-2, 17, -3, -2, 17, -3, ICE, GLASS, 0.15)
		body:boxPair(6, 3, -4, 6, 4, -4, ICE, GLASS, 0.15)
		body:boxPair(6, 2, -1, 6, 3, -1, ICE, GLASS, 0.15)

		-- A high domed head capped with snow, shaggy bangs, a curling trunk and great frost-tipped tusks.
		local head = pet:limb("Head", { 0, 13, 6 })
		head:box(-4, 10, 6, 3, 17, 11, WOOL)
		head:box(-3, 18, 7, 2, 19, 10, WOOL)
		head:paint(-3, 19, 7, 2, 19, 10, SNOW)
		head:paint(-3, 18, 10, -3, 18, 10, SNOW)
		head:paint(2, 18, 7, 2, 18, 8, SNOW)
		eyes(head, 2, 14, 11, 1)
		head:box(-3, 16, 12, 2, 17, 12, WOOL_DARK)
		head:boxPair(4, 13, 8, 4, 15, 9, WOOL_DARK)
		head:box(-1, 9, 12, 0, 14, 13, WOOL)
		head:box(-1, 6, 12, 0, 8, 13, WOOL)
		head:box(-1, 5, 14, 0, 6, 14, WOOL)
		head:box(-1, 6, 15, 0, 7, 15, WOOL_LIGHT)
		head:paint(-1, 8, 13, 0, 8, 13, WOOL_DARK)
		head:paint(-1, 11, 13, 0, 11, 13, WOOL_DARK)
		head:boxPair(2, 10, 12, 2, 11, 13, IVORY)
		head:boxPair(3, 8, 13, 3, 10, 14, IVORY)
		head:boxPair(4, 7, 15, 4, 8, 16, IVORY)
		head:boxPair(4, 9, 17, 4, 11, 17, IVORY)
		head:boxPair(3, 12, 17, 3, 12, 17, ICE, GLASS, 0.15)
		head:paintPair(3, 9, 13, 3, 9, 14, IVORY_DARK)

		-- Pillar legs with shaggy cuffs and ivory toenails.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 4, 9, 3 }, function(leg)
			leg:box(2, 1, 1, 5, 8, 4, WOOL)
			leg:box(2, 0, 1, 5, 0, 4, WOOL_DARK)
			leg:paint(2, 2, 1, 5, 3, 4, WOOL_DARK)
			leg:box(2, 0, 5, 2, 0, 5, IVORY)
			leg:box(4, 0, 5, 4, 0, 5, IVORY)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 4, 9, -5 }, function(leg)
			leg:box(2, 1, -7, 5, 8, -4, WOOL)
			leg:box(2, 0, -7, 5, 0, -4, WOOL_DARK)
			leg:paint(2, 2, -7, 5, 3, -4, WOOL_DARK)
			leg:box(2, 0, -3, 2, 0, -3, IVORY)
			leg:box(4, 0, -3, 4, 0, -3, IVORY)
		end)

		local tail = pet:limb("Tail", { 0, 13, -8 })
		tail:box(-1, 10, -9, 0, 13, -9, WOOL)
		tail:box(-1, 8, -9, 0, 9, -9, WOOL_DARK)

		pet:light(ICE, 1.6, 14)
		pet:particles("Snow", SNOW, 8)
		pet:seat(0, 18, -2)
	end,
}

Designs.Yeti = {
	name = "Yeti",
	skeleton = "Biped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local FUR = rgb(240, 245, 250)
		local SHADE = rgb(204, 218, 236)
		local DEEP = rgb(170, 190, 220)
		local SKIN = rgb(146, 182, 224)
		local SKIN_DARK = rgb(92, 124, 172)
		local MOUTH = rgb(30, 36, 56)
		local CLAW = rgb(220, 236, 250)
		local ICE = rgb(196, 240, 255)
		local ICE_DEEP = rgb(120, 190, 240)
		local GLOW = rgb(130, 236, 255)
		local GLOW_WHITE = rgb(230, 250, 255)

		-- A towering, hunched body of shaggy white fur, hanging in layered fringes.
		local body = pet:limb("Body", { 0, 9, 0 })
		body:box(-5, 9, -4, 4, 14, 3, FUR)
		body:box(-7, 15, -5, 6, 21, 4, FUR)
		body:box(-5, 22, -5, 4, 22, 1, FUR)
		body:boxPair(5, 12, -4, 6, 14, -3, FUR)
		body:boxPair(5, 13, -1, 6, 14, 0, FUR)
		body:boxPair(5, 11, 2, 6, 14, 3, FUR)
		body:paintPair(5, 12, -4, 6, 12, -3, DEEP)
		body:paintPair(5, 11, 2, 6, 11, 3, DEEP)
		body:paintPair(5, 13, -1, 6, 13, 0, DEEP)
		body:box(-1, 8, -3, 0, 8, 2, SHADE)
		body:box(-1, 7, -2, 0, 7, 1, SHADE)
		body:paint(-5, 9, -4, 4, 9, 3, DEEP)
		body:paint(-5, 11, 3, 4, 11, 3, SHADE)
		body:paint(-5, 13, 3, 4, 13, 3, SHADE)
		body:paint(-7, 15, -5, 6, 15, 4, DEEP)
		body:paintPair(6, 18, -3, 6, 18, 3, SHADE)
		body:paintPair(6, 15, -5, 6, 21, -5, SHADE)
		body:paintPair(4, 17, -5, 4, 21, -5, SHADE)
		body:paint(-1, 15, -5, 0, 20, -5, SHADE)
		body:paintPair(6, 17, 0, 6, 20, 0, SHADE)
		-- A bare blue chest with a glowing frost rune, and a necklace of ice fangs.
		body:paint(-3, 15, 4, 2, 20, 4, SKIN)
		body:paint(-1, 15, 4, 0, 17, 4, GLOW, NEON)
		body:paintPair(1, 16, 4, 2, 16, 4, GLOW, NEON)
		body:paintPair(1, 15, 4, 1, 15, 4, GLOW, NEON)
		body:paintPair(1, 17, 4, 1, 17, 4, GLOW, NEON)
		body:paint(-1, 18, 4, 0, 18, 4, SKIN_DARK)
		body:box(-4, 21, 5, 3, 21, 5, SKIN_DARK)
		body:boxPair(0, 19, 5, 0, 20, 5, ICE, GLASS, 0.1)
		body:boxPair(2, 20, 5, 2, 20, 5, ICE, GLASS, 0.1)
		body:boxPair(3, 20, 5, 3, 20, 5, CLAW)
		-- Ice shards growing out of its back and shoulders, glowing from inside.
		body:box(-3, 19, -7, -2, 23, -6, ICE_DEEP, GLASS, 0.1)
		body:paint(-3, 21, -7, -3, 22, -7, GLOW, NEON)
		body:box(1, 18, -7, 2, 21, -6, ICE, GLASS, 0.15)
		body:box(-1, 20, -6, 0, 25, -6, ICE, GLASS, 0.15)
		body:paint(-1, 22, -6, 0, 23, -6, GLOW, NEON)
		body:box(3, 16, -6, 3, 18, -6, ICE_DEEP, GLASS, 0.1)
		body:boxPair(5, 22, -2, 6, 24, -1, ICE, GLASS, 0.15)
		body:boxPair(6, 25, -2, 6, 26, -2, ICE, GLASS, 0.15)
		body:paintPair(5, 23, -1, 5, 23, -1, GLOW, NEON)

		-- A blue face under a heavy fur brow: glowing eyes, a flat nose, tusks, cheek tufts, and great
		-- curling horns of ice with a crown of shards between them.
		local head = pet:limb("Head", { 0, 22, 1 })
		head:box(-4, 23, -1, 3, 29, 5, FUR)
		head:paint(-3, 23, 5, 2, 27, 5, SKIN)
		head:box(-4, 28, 6, 3, 28, 6, FUR)
		head:paint(-4, 28, 6, 3, 28, 6, SHADE)
		head:paintPair(1, 26, 5, 2, 27, 5, GLOW, NEON)
		head:paintPair(1, 27, 5, 1, 27, 5, SKIN_DARK)
		head:box(-1, 24, 6, 0, 25, 6, SKIN_DARK)
		head:paint(-1, 24, 6, 0, 24, 6, MOUTH)
		head:paint(-2, 23, 5, 1, 23, 5, MOUTH)
		head:boxPair(2, 23, 6, 2, 24, 6, CLAW)
		head:boxPair(4, 23, 2, 4, 27, 4, FUR)
		head:paintPair(4, 23, 2, 4, 23, 4, SHADE)
		head:paintPair(4, 25, 2, 4, 25, 4, SHADE)
		head:box(-3, 30, 0, 2, 30, 4, FUR)
		head:box(-2, 31, 1, 1, 31, 3, FUR)
		head:paintPair(3, 24, -1, 3, 28, 0, SHADE)
		head:paint(-3, 24, -1, 2, 26, -1, SHADE)
		head:paint(-3, 30, 0, 2, 30, 0, SHADE)
		head:boxPair(4, 28, 1, 5, 29, 3, ICE_DEEP, GLASS)
		head:boxPair(6, 29, 0, 7, 30, 2, ICE_DEEP, GLASS)
		head:boxPair(8, 27, -1, 9, 29, 1, ICE_DEEP, GLASS)
		head:boxPair(8, 24, 0, 9, 26, 2, ICE_DEEP, GLASS)
		head:boxPair(7, 23, 2, 7, 24, 3, ICE_DEEP, GLASS)
		head:boxPair(6, 23, 4, 6, 23, 4, GLOW_WHITE, NEON)
		head:paintPair(4, 28, 3, 5, 28, 3, GLOW, NEON)
		head:paintPair(6, 30, 2, 7, 30, 2, GLOW, NEON)
		head:paintPair(8, 28, 1, 9, 28, 1, GLOW, NEON)
		head:paintPair(8, 25, 2, 9, 25, 2, GLOW, NEON)
		head:box(-1, 32, 2, 0, 33, 2, ICE, GLASS, 0.15)
		head:paint(-1, 33, 2, 0, 33, 2, GLOW_WHITE, NEON)
		head:boxPair(1, 32, 1, 1, 32, 1, ICE, GLASS, 0.15)
		head:boxPair(2, 31, 3, 2, 31, 3, ICE, GLASS, 0.15)

		-- Long arms to the ground: fur shoulders, ice bracers with glowing runes, blue fists and ice claws.
		local function arm(limb: Limb)
			limb:box(7, 17, -2, 9, 21, 2, FUR)
			limb:paint(7, 21, -2, 9, 21, 2, SHADE)
			limb:box(8, 12, -2, 10, 16, 1, FUR)
			limb:box(10, 11, -3, 10, 14, -3, DEEP)
			limb:box(8, 7, -2, 10, 11, 1, FUR)
			limb:box(7, 8, -3, 11, 10, 2, ICE, GLASS, 0.15)
			limb:paint(11, 9, -1, 11, 9, 0, GLOW, NEON)
			limb:paint(9, 9, 2, 9, 9, 2, GLOW, NEON)
			limb:box(8, 3, -2, 10, 6, 2, SKIN)
			limb:paint(8, 6, -2, 10, 6, 2, FUR)
			limb:box(8, 2, 3, 8, 3, 3, ICE, GLASS, 0.15)
			limb:box(10, 2, 3, 10, 3, 3, ICE, GLASS, 0.15)
			limb:box(9, 1, 3, 9, 2, 3, ICE, GLASS, 0.15)
		end
		arm(pet:limb("LeftArm", { 8.5, 20, 0 }))
		local right = mirrored(pet:limb("RightArm", { -8.5, 20, 0 }))
		arm(right)
		-- In its right hand, a club of frost crystal.
		right:box(9, 4, 3, 9, 5, 6, ICE_DEEP, GLASS, 0.1)
		right:box(8, 3, 7, 10, 7, 10, ICE, GLASS, 0.15)
		right:box(9, 8, 8, 9, 9, 9, ICE, GLASS, 0.15)
		right:box(11, 5, 8, 11, 6, 9, ICE, GLASS, 0.15)
		right:box(9, 4, 11, 9, 5, 11, ICE, GLASS, 0.15)
		right:paint(9, 4, 10, 9, 6, 10, GLOW, NEON)
		right:paint(10, 5, 8, 10, 6, 9, GLOW, NEON)

		-- Thick legs with a fringe at the knee, icicles, and wide blue feet with claws.
		pet:limbPair("LeftLeg", "RightLeg", { 3, 9, 0 }, function(leg)
			leg:box(1, 5, -3, 5, 9, 2, FUR)
			leg:box(1, 4, -3, 5, 4, 3, DEEP)
			leg:box(2, 1, -2, 4, 3, 2, FUR)
			leg:box(1, 0, -3, 5, 0, 4, SKIN)
			leg:paint(1, 0, -3, 5, 0, -3, SKIN_DARK)
			leg:box(1, 0, 5, 1, 0, 5, CLAW)
			leg:box(3, 0, 5, 3, 0, 5, CLAW)
			leg:box(5, 0, 5, 5, 0, 5, CLAW)
			leg:box(5, 2, 0, 5, 3, 0, ICE, GLASS, 0.15)
			leg:box(1, 2, 3, 1, 3, 3, ICE, GLASS, 0.15)
			leg:paint(1, 7, 2, 5, 7, 2, SHADE)
		end)

		pet:light(GLOW, 2.6, 18)
		pet:particles("Snow", GLOW_WHITE, 14)
		pet:seat(0, 23, -4)
	end,
}

----------------------------------------------------------------------------------------------------------------
-- Ocean

Designs.SeaTurtle = {
	name = "Sea Turtle",
	skeleton = "LowSlung",
	scale = 0.75,
	draw = function(pet)
		local SHELL = rgb(98, 168, 84)
		local SHELL_DARK = rgb(62, 118, 58)
		local SKIN = rgb(150, 196, 120)
		local SPOT = rgb(100, 150, 80)
		local PLASTRON = rgb(232, 218, 156)
		local BARNACLE = rgb(226, 220, 206)
		local STAR = rgb(255, 140, 90)
		local WEED = rgb(60, 140, 90)

		-- A stepped shell of plates with dark seams, a dark rim, a cream belly, barnacles and a starfish.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 0, -4, 3, 0, 4, PLASTRON)
		body:box(-6, 1, -6, 5, 1, 5, SHELL_DARK)
		body:box(-5, 2, -5, 4, 3, 4, SHELL)
		body:box(-4, 4, -4, 3, 5, 3, SHELL)
		body:box(-3, 6, -3, 2, 6, 2, SHELL)
		body:paint(-1, 6, -3, 0, 6, 2, SHELL_DARK)
		body:paint(-4, 5, 0, 3, 5, 0, SHELL_DARK)
		body:paint(-4, 5, -3, 3, 5, -3, SHELL_DARK)
		body:paintPair(4, 2, -2, 4, 3, -2, SHELL_DARK)
		body:paintPair(4, 2, 2, 4, 3, 2, SHELL_DARK)
		body:paint(-2, 2, 4, -2, 3, 4, SHELL_DARK)
		body:paint(1, 2, 4, 1, 3, 4, SHELL_DARK)
		body:paint(-2, 2, -5, 1, 3, -5, SHELL_DARK)
		for _, z in { -5, -1, 3 } do
			body:paintPair(5, 1, z, 5, 1, z, SHELL)
		end
		body:paint(-1, 1, 5, 0, 1, 5, SHELL)
		body:box(2, 7, -2, 2, 7, -2, BARNACLE)
		body:box(-3, 6, 3, -3, 6, 3, BARNACLE)
		body:box(2, 7, 1, 2, 7, 1, BARNACLE)
		body:box(-2, 7, -1, -2, 7, 1, STAR)
		body:box(-3, 7, 0, -1, 7, 0, STAR)
		body:box(1, 0, -7, 1, 0, -7, WEED)

		-- A spotted head with a beaky mouth and a gentle smile.
		local head = pet:limb("Head", { 0, 2, 5 })
		head:box(-1, 2, 5, 0, 3, 6, SKIN)
		head:box(-2, 2, 7, 1, 4, 9, SKIN)
		head:box(-1, 2, 10, 0, 3, 10, SHELL_DARK)
		eyes(head, 1, 3, 9, 1, 1)
		head:paint(-2, 2, 9, 1, 2, 9, SPOT)
		head:paintPair(1, 4, 8, 1, 4, 8, SPOT)
		head:paint(-1, 4, 7, 0, 4, 7, SPOT)
		head:paint(-1, 3, 10, 0, 3, 10, rgb(40, 70, 40))
		head:paintPair(2, 2, 8, 2, 3, 8, SPOT)

		-- Broad spotted flippers.
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 5, 0.5, 3 }, function(leg)
			leg:box(5, 0, 2, 8, 0, 4, SKIN)
			leg:box(8, 0, 5, 8, 0, 5, SKIN)
			leg:paint(6, 0, 3, 6, 0, 3, SPOT)
			leg:paint(8, 0, 2, 8, 0, 2, SPOT)
			leg:box(9, 0, 3, 9, 0, 3, SHELL_DARK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 4, 0.5, -4 }, function(leg)
			leg:box(4, 0, -5, 6, 0, -3, SKIN)
			leg:paint(5, 0, -4, 5, 0, -4, SPOT)
		end)

		local tail = pet:limb("Tail", { 0, 0.5, -6 })
		tail:box(-1, 0, -7, 0, 0, -6, SKIN)

		pet:seat(0, 7, -1)
	end,
}

Designs.Dolphin = {
	name = "Dolphin",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.55,
	draw = function(pet)
		local GREY = rgb(112, 152, 194)
		local CAPE = rgb(78, 112, 156)
		local BELLY = rgb(232, 242, 250)

		-- A sleek body, dark along the back and pale underneath, with a swept-back fin.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-3, 1, -5, 2, 5, 3, GREY)
		body:box(-2, 6, -4, 1, 6, 2, CAPE)
		body:box(-2, 0, -4, 1, 0, 2, BELLY)
		body:paint(-3, 5, -5, 2, 5, 3, CAPE)
		body:paint(-3, 1, -5, 2, 1, 3, BELLY)
		body:paintPair(2, 2, -4, 2, 2, 2, BELLY)
		body:box(-1, 7, -2, 0, 8, 0, CAPE)
		body:box(-1, 9, -3, 0, 9, -1, CAPE)
		body:box(-1, 10, -4, 0, 10, -3, CAPE)
		body:paint(-1, 7, 0, 0, 8, 0, GREY)
		body:paintPair(2, 3, -4, 2, 3, -1, rgb(170, 204, 232))
		body:paintPair(2, 4, 0, 2, 4, 2, rgb(170, 204, 232))
		body:paint(-1, 0, -2, -1, 0, -2, rgb(200, 214, 230))
		body:paint(0, 0, 1, 0, 0, 1, rgb(200, 214, 230))

		-- A rounded head, a smiling beak and a blowhole.
		local head = pet:limb("Head", { 0, 3, 3 })
		head:box(-2, 1, 4, 1, 5, 7, GREY)
		head:box(-1, 2, 8, 0, 2, 10, GREY)
		head:box(-1, 1, 8, 0, 1, 10, BELLY)
		head:paint(-2, 1, 4, 1, 1, 7, BELLY)
		head:paint(-2, 5, 4, 1, 5, 7, CAPE)
		head:paint(-1, 5, 5, 0, 5, 5, rgb(40, 50, 70))
		eyes(head, 1, 3, 7, 1, 1)
		head:paintPair(1, 2, 7, 1, 2, 7, rgb(170, 204, 232))
		head:box(-1, 6, 5, 0, 7, 5, rgb(200, 240, 255), GLASS, 0.3)
		head:box(-1, 8, 5, 0, 8, 5, rgb(240, 252, 255))
		head:boxPair(1, 8, 4, 1, 8, 4, rgb(200, 240, 255), GLASS, 0.3)
		head:boxPair(1, 9, 5, 1, 9, 5, rgb(240, 252, 255))

		pet:limbPair("LeftFin", "RightFin", { 3, 1.5, 1 }, function(fin)
			fin:box(3, 1, 0, 5, 1, 2, CAPE)
			fin:box(6, 0, 0, 6, 0, 1, CAPE)
		end)

		-- A narrow tail ending in wide flukes.
		local tail = pet:limb("Tail", { 0, 3, -5 })
		tail:box(-1, 2, -8, 0, 4, -6, GREY)
		tail:paint(-1, 2, -8, 0, 2, -6, BELLY)
		tail:paint(-1, 4, -8, 0, 4, -6, CAPE)
		tail:box(-4, 3, -10, 3, 3, -9, CAPE)
		tail:boxPair(2, 3, -11, 3, 3, -11, CAPE)

		pet:seat(0, 7, 2)
	end,
}

Designs.MantaRay = {
	name = "Manta Ray",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 4,
	scale = 0.55,
	draw = function(pet)
		local NAVY = rgb(34, 50, 96)
		local NAVY_LIGHT = rgb(54, 74, 128)
		local BELLY = rgb(232, 242, 250)
		local SPOT = rgb(144, 204, 244)
		local REMORA = rgb(150, 156, 170)

		-- A flat, broad body, dark above with pale shoulder marks and spots, white below,
		-- with a little remora fish hitching a ride underneath.
		local body = pet:limb("Body", { 0, 2, 0 })
		body:box(-3, 2, -4, 2, 3, 4, NAVY)
		body:box(-3, 1, -4, 2, 1, 4, BELLY)
		body:box(-2, 4, -3, 1, 4, 2, NAVY)
		body:paintPair(1, 4, 1, 1, 4, 2, BELLY)
		body:paintPair(2, 3, 2, 2, 3, 3, BELLY)
		body:paint(-1, 4, -2, -1, 4, -2, SPOT)
		body:paint(0, 4, 0, 0, 4, 0, SPOT)
		body:paint(-2, 4, -3, -2, 4, -3, SPOT)
		body:box(-2, 0, 0, -1, 0, 2, REMORA)
		body:paint(-2, 0, 2, -1, 0, 2, rgb(110, 116, 130))
		body:box(1, 0, -3, 1, 0, -1, REMORA)
		for _, z in { 1, 2, 3 } do
			body:paintPair(1, 1, z, 2, 1, z, rgb(170, 180, 200))
		end
		body:paint(1, 4, -2, 1, 4, -2, SPOT)
		body:paint(-2, 4, 1, -2, 4, 1, SPOT)

		-- Curled head lobes either side of a wide mouth.
		local head = pet:limb("Head", { 0, 2, 5 })
		head:box(-3, 1, 5, 2, 2, 6, NAVY)
		head:paint(-2, 1, 6, 1, 1, 6, rgb(200, 210, 230))
		eyes(head, 2, 2, 6, 1, 1)
		head:boxPair(2, 1, 7, 3, 2, 9, NAVY)
		head:boxPair(2, 3, 9, 2, 3, 9, NAVY)
		head:paintPair(2, 1, 7, 3, 1, 9, BELLY)

		-- Great wings, dark above and white below, with up-curled tips.
		pet:limbPair("LeftFin", "RightFin", { 3.5, 2, 0 }, function(wing)
			wing:box(3, 2, -3, 6, 2, 3, NAVY)
			wing:box(3, 1, -3, 6, 1, 3, BELLY)
			wing:box(7, 2, -2, 8, 2, 2, NAVY)
			wing:box(7, 1, -2, 8, 1, 2, BELLY)
			wing:box(9, 2, -1, 10, 2, 1, NAVY)
			wing:box(9, 1, -1, 10, 1, 1, BELLY)
			wing:box(11, 2, 0, 12, 3, 0, NAVY)
			wing:paint(5, 2, 1, 5, 2, 1, SPOT)
			wing:paint(7, 2, -1, 7, 2, -1, SPOT)
			wing:paint(4, 2, -2, 4, 2, -2, SPOT)
			wing:paint(3, 2, 2, 4, 2, 3, BELLY)
			wing:paint(7, 2, -2, 8, 2, -2, NAVY_LIGHT)
			wing:paint(9, 2, -1, 10, 2, -1, NAVY_LIGHT)
			wing:paint(6, 2, -3, 6, 2, -3, NAVY_LIGHT)
			wing:paint(9, 2, 1, 9, 2, 1, SPOT)
			wing:paint(5, 1, 0, 5, 1, 0, rgb(170, 180, 200))
			wing:paint(8, 1, 0, 8, 1, 0, rgb(170, 180, 200))
		end)

		-- A long whip of a tail.
		local tail = pet:limb("Tail", { 0, 2, -5 })
		tail:box(-1, 2, -10, 0, 2, -5, NAVY_LIGHT)
		tail:box(-1, 2, -14, -1, 2, -11, NAVY_LIGHT)
		tail:boxPair(1, 1, -5, 2, 1, -5, NAVY)

		pet:seat(0, 5, 0)
	end,
}

Designs.KingCrab = {
	name = "King Crab",
	skeleton = "ManyLegged",
	scale = 0.55,
	draw = function(pet)
		local CRAB = rgb(216, 64, 48)
		local CRAB_DARK = rgb(156, 38, 30)
		local BELLY = rgb(250, 178, 128)
		local SPIKE = rgb(240, 120, 86)
		local TIP = rgb(48, 32, 32)
		local GOLD = rgb(255, 200, 60)
		local RUBY = rgb(220, 30, 80)

		-- A spiky shell with a pale belly, and a little gold crown, because it is the king.
		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-5, 3, -4, 4, 5, 3, CRAB)
		body:box(-4, 6, -3, 3, 6, 2, CRAB)
		body:box(-4, 2, -3, 3, 2, 2, BELLY)
		body:paint(-5, 3, -4, 4, 3, 3, CRAB_DARK)
		body:boxPair(2, 7, -2, 2, 7, -2, SPIKE)
		body:boxPair(3, 7, 1, 3, 7, 1, SPIKE)
		body:boxPair(5, 4, -2, 5, 4, -2, SPIKE)
		body:boxPair(5, 4, 1, 5, 4, 1, SPIKE)
		body:boxPair(2, 5, -5, 2, 5, -5, SPIKE)
		body:box(-2, 7, -1, 1, 7, 1, GOLD)
		body:boxPair(1, 8, -1, 1, 8, -1, GOLD)
		body:boxPair(1, 8, 1, 1, 8, 1, GOLD)
		body:paint(-1, 7, 1, 0, 7, 1, RUBY)

		-- Eyes on stalks, and claws: one big one for show, one small one for eating.
		local head = pet:limb("Head", { 0, 4, 4 })
		head:box(-3, 3, 4, 2, 4, 4, CRAB)
		head:paint(-1, 3, 4, 0, 3, 4, BELLY)
		head:boxPair(1, 5, 4, 1, 6, 4, CRAB)
		head:boxPair(1, 7, 4, 1, 7, 4, EYE)
		head:box(3, 3, 4, 4, 4, 6, CRAB)
		head:box(4, 3, 7, 5, 4, 8, CRAB)
		head:box(3, 2, 9, 6, 5, 11, CRAB)
		head:box(4, 4, 12, 6, 5, 14, CRAB)
		head:box(4, 2, 12, 5, 2, 13, CRAB_DARK)
		head:paint(4, 4, 14, 6, 5, 14, TIP)
		head:paint(3, 5, 9, 6, 5, 11, SPIKE)
		head:box(-5, 3, 4, -4, 4, 6, CRAB)
		head:box(-6, 3, 7, -5, 4, 8, CRAB)
		head:box(-6, 3, 9, -4, 4, 10, CRAB)
		head:box(-6, 3, 11, -5, 4, 12, CRAB)
		head:box(-4, 3, 11, -4, 3, 12, CRAB_DARK)
		head:paint(-6, 4, 12, -5, 4, 12, TIP)

		-- Long spiky legs, bent high at the knee.
		local function leg(z: number)
			return function(limb)
				limb:box(5, 4, z, 6, 5, z, CRAB)
				limb:box(7, 5, z, 8, 5, z, CRAB)
				limb:box(9, 1, z, 9, 4, z, CRAB)
				limb:box(9, 0, z, 9, 0, z, TIP)
				limb:paint(7, 5, z, 8, 5, z, SPIKE)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 5, 4.5, 2.5 }, leg(2))
		pet:limbPair("MiddleLeftLeg", "MiddleRightLeg", { 5, 4.5, -0.5 }, leg(-1))
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 5, 4.5, -2.5 }, leg(-3))

		local tail = pet:limb("Tail", { 0, 3, -4 })
		tail:box(-2, 2, -5, 1, 3, -5, CRAB_DARK)

		pet:seat(0, 8, -3)
	end,
}

Designs.Narwhal = {
	name = "Narwhal",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.55,
	draw = function(pet)
		local SLATE = rgb(122, 142, 172)
		local SLATE_DARK = rgb(82, 100, 136)
		local BELLY = rgb(232, 242, 250)
		local IVORY = rgb(250, 242, 220)
		local IVORY_DARK = rgb(222, 206, 168)
		local GLOW = rgb(255, 250, 230)
		local ICE = rgb(170, 230, 255)

		-- A plump whale body, mottled on the back and pale underneath, with a low ridge.
		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-4, 1, -6, 3, 7, 3, SLATE)
		body:box(-3, 8, -5, 2, 8, 2, SLATE)
		body:box(-3, 0, -5, 2, 0, 2, BELLY)
		body:paint(-4, 1, -6, 3, 2, 3, BELLY)
		body:box(-1, 9, -4, 0, 9, -1, SLATE_DARK)
		body:box(-1, 10, -3, -1, 11, -3, ICE, GLASS, 0.2)
		body:box(0, 10, -2, 0, 10, -2, ICE, GLASS, 0.2)
		body:box(-1, 10, -1, -1, 10, -1, ICE, GLASS, 0.2)
		body:boxPair(2, 9, -4, 2, 9, -4, ICE, GLASS, 0.2)
		for _, spot in
			{
				{ 3, 6, -4 },
				{ 3, 4, -1 },
				{ -4, 5, -3 },
				{ -4, 6, 1 },
				{ 1, 8, -3 },
				{ -2, 8, 0 },
				{ 3, 5, 2 },
				{ -4, 3, -5 },
				{ 0, 7, -6 },
				{ 3, 7, -2 },
				{ -4, 7, -1 },
				{ 2, 8, -5 },
				{ -3, 8, -4 },
				{ 3, 3, 0 },
				{ -4, 4, 2 },
				{ -2, 6, -6 },
			}
		do
			body:paint(spot[1], spot[2], spot[3], spot[1], spot[2], spot[3], SLATE_DARK)
		end

		-- A rounded head with a smile, and the long spiral tusk, glowing faintly at its tip.
		local head = pet:limb("Head", { 0, 4, 4 })
		head:box(-3, 1, 4, 2, 6, 7, SLATE)
		head:box(-2, 7, 4, 1, 7, 6, SLATE)
		head:paint(-3, 1, 4, 2, 1, 7, BELLY)
		head:paint(-3, 2, 7, 2, 2, 7, SLATE_DARK)
		eyes(head, 2, 4, 7, 1, 1)
		head:paintPair(2, 6, 5, 2, 6, 5, SLATE_DARK)
		head:box(-1, 4, 8, 0, 5, 10, IVORY)
		head:paint(-1, 5, 8, -1, 5, 8, IVORY_DARK)
		head:paint(0, 4, 9, 0, 4, 9, IVORY_DARK)
		head:paint(-1, 5, 10, -1, 5, 10, IVORY_DARK)
		head:box(0, 5, 11, 0, 5, 13, IVORY)
		head:paint(0, 5, 12, 0, 5, 12, IVORY_DARK)
		head:box(0, 6, 14, 0, 6, 17, IVORY)
		head:paint(0, 6, 15, 0, 6, 15, IVORY_DARK)
		head:box(0, 6, 18, 0, 6, 18, GLOW, NEON)
		head:paint(0, 6, 17, 0, 6, 17, IVORY_DARK)
		head:paint(0, 5, 13, 0, 5, 13, IVORY_DARK)
		head:paint(-2, 7, 5, -2, 7, 5, SLATE_DARK)
		head:paint(1, 6, 7, 1, 6, 7, SLATE_DARK)
		head:paint(-3, 5, 5, -3, 5, 5, SLATE_DARK)

		pet:limbPair("LeftFin", "RightFin", { 4, 1.5, 2 }, function(fin)
			fin:box(4, 1, 1, 6, 1, 3, SLATE_DARK)
			fin:box(7, 0, 1, 7, 0, 2, SLATE_DARK)
			fin:paint(6, 1, 1, 6, 1, 3, BELLY)
			fin:paint(5, 1, 2, 5, 1, 2, SLATE)
		end)

		-- A thick tail and broad flukes, with a few chips of ice stuck to them.
		local tail = pet:limb("Tail", { 0, 4, -6 })
		tail:box(-2, 2, -9, 1, 5, -7, SLATE)
		tail:paint(-2, 2, -9, 1, 2, -7, BELLY)
		tail:box(-1, 3, -11, 0, 4, -10, SLATE)
		tail:box(-5, 4, -13, 4, 4, -12, SLATE_DARK)
		tail:boxPair(3, 4, -14, 4, 4, -14, SLATE_DARK)
		tail:paint(-1, 5, -8, -1, 5, -8, SLATE_DARK)
		tail:box(-3, 5, -13, -3, 5, -13, ICE, GLASS, 0.2)
		tail:box(2, 5, -12, 2, 5, -12, ICE, GLASS, 0.2)
		tail:paintPair(1, 5, -8, 1, 5, -8, SLATE_DARK)
		tail:paint(-5, 4, -12, -4, 4, -12, SLATE)
		tail:paint(3, 4, -12, 4, 4, -12, SLATE)
		tail:paint(-1, 3, -11, 0, 3, -10, BELLY)

		pet:light(ICE, 1.6, 12)
		pet:seat(0, 9, 1)
	end,
}

Designs.Hippocampus = {
	name = "Hippocampus",
	skeleton = "Swimmer",
	gait = "Swim",
	hover = 3,
	scale = 0.55,
	draw = function(pet)
		local TEAL = rgb(36, 172, 168)
		local TEAL_DARK = rgb(22, 122, 126)
		local BELLY = rgb(188, 242, 230)
		local FIN = rgb(90, 220, 210)
		local GLOW = rgb(80, 255, 228)
		local CORAL = rgb(255, 150, 160)
		local PEARL = rgb(250, 246, 240)

		-- A sea horse's body: ridged, pale-bellied, with a see-through fin down its back.
		local body = pet:limb("Body", { 0, 6, 0 })
		body:box(-3, 4, -3, 2, 9, 3, TEAL)
		body:box(-2, 4, 4, 1, 8, 4, BELLY)
		body:paint(-2, 5, 4, 1, 5, 4, TEAL_DARK)
		body:paint(-2, 7, 4, 1, 7, 4, TEAL_DARK)
		body:paint(-3, 4, -3, 2, 4, 3, BELLY)
		for _, z in { -2, 0, 2 } do
			body:paintPair(2, 4, z, 2, 9, z, TEAL_DARK)
		end
		body:box(-3, 10, -2, 2, 10, 0, CORAL)
		body:box(-2, 11, -2, 1, 11, -1, rgb(255, 214, 200))
		body:paint(-2, 11, -2, 1, 11, -2, CORAL)
		body:boxPair(3, 9, -1, 3, 10, 0, CORAL)
		body:boxPair(3, 8, -1, 3, 8, -1, PEARL)
		body:boxPair(3, 8, 0, 3, 8, 0, PEARL)
		body:box(-1, 11, 0, 0, 11, 0, PEARL)
		body:box(-1, 10, -3, 0, 11, -3, FIN, GLASS, 0.3)
		body:paint(-1, 11, -3, 0, 11, -3, GLOW, NEON)
		for _, dot in { { 2, 6, -2 }, { 2, 8, 2 }, { -3, 7, -1 }, { -3, 5, 1 }, { 2, 5, 0 }, { -3, 8, 2 } } do
			body:paint(dot[1], dot[2], dot[3], dot[1], dot[2], dot[3], GLOW, NEON)
		end

		-- A horse's head on a long neck, with a glassy fin mane, a coral crown and a pearl on its brow.
		local head = pet:limb("Head", { 0, 9, 3 })
		head:box(-2, 9, 2, 1, 12, 4, TEAL)
		head:box(-2, 12, 3, 1, 15, 7, TEAL)
		head:box(-1, 12, 8, 0, 14, 10, TEAL)
		head:paint(-1, 12, 10, 0, 12, 10, TEAL_DARK)
		head:paint(-1, 14, 10, 0, 14, 10, TEAL_DARK)
		eyes(head, 1, 14, 7, 1)
		head:box(-1, 15, 8, 0, 15, 8, PEARL)
		head:box(-1, 9, 1, 0, 12, 1, FIN, GLASS, 0.3)
		head:box(-1, 13, 2, 0, 16, 2, FIN, GLASS, 0.3)
		head:box(-1, 16, 3, 0, 17, 5, FIN, GLASS, 0.3)
		head:paint(-1, 10, 1, 0, 10, 1, GLOW, NEON)
		head:paint(-1, 14, 2, 0, 14, 2, GLOW, NEON)
		head:paint(-1, 17, 4, 0, 17, 4, GLOW, NEON)
		head:boxPair(1, 16, 5, 1, 17, 5, CORAL)
		head:boxPair(1, 16, 7, 1, 16, 7, CORAL)
		head:boxPair(2, 15, 4, 2, 16, 4, FIN, GLASS, 0.3)
		head:box(-1, 12, 0, 0, 12, 0, FIN, GLASS, 0.3)
		head:paintPair(1, 10, 4, 1, 11, 4, TEAL_DARK)
		head:paintPair(2, 13, 6, 2, 14, 6, TEAL_DARK)
		head:box(-2, 13, 9, 1, 13, 9, rgb(70, 150, 90))
		head:boxPair(2, 11, 6, 2, 12, 8, rgb(70, 150, 90))
		head:paintPair(2, 12, 7, 2, 12, 7, PEARL)

		-- Horse forelegs ending in webbed fins.
		pet:limbPair("LeftFin", "RightFin", { 1.5, 6, 2.5 }, function(leg)
			leg:box(1, 4, 2, 2, 6, 3, TEAL)
			leg:box(1, 2, 4, 2, 3, 5, TEAL)
			leg:paint(1, 3, 4, 2, 3, 5, TEAL_DARK)
			leg:box(1, 1, 6, 3, 2, 7, FIN, GLASS, 0.3)
			leg:paint(1, 1, 7, 3, 1, 7, GLOW, NEON)
			leg:box(3, 2, 4, 3, 3, 4, FIN, GLASS, 0.3)
		end)

		-- A fish tail sweeping down and back, curling up into a great see-through fin.
		local tail = pet:limb("Tail", { 0, 5, -3 })
		tail:box(-2, 3, -6, 1, 6, -4, TEAL)
		tail:box(-2, 1, -8, 1, 3, -7, TEAL)
		tail:box(-1, 0, -10, 0, 1, -9, TEAL)
		tail:box(-1, 1, -12, 0, 3, -11, TEAL)
		tail:box(-1, 4, -12, 0, 5, -12, TEAL)
		tail:paint(-2, 3, -6, 1, 3, -6, TEAL_DARK)
		tail:paint(-2, 2, -8, 1, 2, -8, TEAL_DARK)
		tail:paint(-1, 1, -10, 0, 1, -10, TEAL_DARK)
		tail:boxPair(2, 2, -8, 2, 3, -7, FIN, GLASS, 0.3)
		tail:box(-3, 4, -14, 2, 6, -13, FIN, GLASS, 0.3)
		tail:paint(-3, 5, -14, 2, 5, -14, GLOW, NEON)
		tail:boxPair(1, 0, -10, 1, 1, -9, FIN, GLASS, 0.3)
		tail:box(-1, 2, -13, 0, 3, -13, FIN, GLASS, 0.3)
		tail:paint(-1, 4, -6, 0, 4, -6, GLOW, NEON)
		tail:paint(-1, 2, -11, 0, 2, -11, TEAL_DARK)

		pet:light(GLOW, 1.8, 13)
		pet:particles("Bubbles", rgb(226, 250, 246), 6)
		pet:seat(0, 10, 0)
	end,
}

Designs.Kraken = {
	name = "Kraken",
	skeleton = "Tentacled",
	gait = "Crawl",
	scale = 0.55,
	draw = function(pet)
		local PURPLE = rgb(104, 42, 134)
		local PURPLE_DARK = rgb(70, 26, 96)
		local MAGENTA = rgb(202, 72, 164)
		local SUCKER = rgb(255, 186, 224)
		local GLOW = rgb(255, 120, 220)
		local EYE_GLOW = rgb(255, 220, 80)
		local PUPIL = rgb(30, 10, 30)
		local BEAK = rgb(60, 40, 30)
		local GOLD = rgb(255, 200, 60)
		local RUBY = rgb(220, 30, 80)
		local BARNACLE = rgb(226, 220, 206)
		local CORAL = rgb(255, 120, 100)
		local IRON = rgb(92, 98, 112)
		local RUST = rgb(150, 86, 52)

		-- The body the tentacles grow from, glowing spots round its rim.
		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-4, 3, -4, 3, 6, 3, PURPLE)
		body:box(-5, 3, -3, 4, 5, 2, PURPLE)
		body:box(-3, 3, -5, 2, 5, 4, PURPLE)
		body:paint(-5, 3, -3, 4, 3, 2, PURPLE_DARK)
		body:paint(-3, 3, -5, 2, 3, 4, PURPLE_DARK)
		for _, dot in
			{ { 4, 4, -2 }, { 4, 4, 1 }, { -5, 4, -2 }, { -5, 4, 1 }, { 1, 4, 4 }, { -2, 4, 4 }, { -1, 4, -5 } }
		do
			body:paint(dot[1], dot[2], dot[3], dot[1], dot[2], dot[3], GLOW, NEON)
		end

		-- A towering mantle curving back, ridged and spotted with light, with huge glowing eyes, angry brows and
		-- a beak, crusted with barnacles and coral, wearing a sunken king's crown askew.
		local head = pet:limb("Head", { 0, 7, 0 })
		head:box(-5, 7, -5, 4, 14, 4, PURPLE)
		head:box(-4, 15, -5, 3, 17, 2, PURPLE)
		head:box(-3, 18, -6, 2, 19, 0, PURPLE)
		head:box(-2, 20, -6, 1, 21, -2, PURPLE)
		head:paint(-5, 14, -5, 4, 14, 4, PURPLE_DARK)
		head:paint(-4, 17, -5, 3, 17, 2, PURPLE_DARK)
		head:paintPair(4, 8, -3, 4, 13, -3, MAGENTA)
		head:paintPair(4, 8, 0, 4, 13, 0, MAGENTA)
		head:paint(-2, 8, -5, -2, 13, -5, MAGENTA)
		head:paint(1, 8, -5, 1, 13, -5, MAGENTA)
		head:paintPair(3, 15, -3, 3, 17, -3, MAGENTA)
		for _, dot in
			{
				{ 4, 12, -2 },
				{ 4, 9, 2 },
				{ -5, 11, 1 },
				{ -5, 8, -4 },
				{ 3, 16, -1 },
				{ -4, 16, 0 },
				{ 0, 19, -6 },
				{ -2, 10, -5 },
				{ 2, 18, -4 },
				{ -3, 19, -2 },
			}
		do
			head:paint(dot[1], dot[2], dot[3], dot[1], dot[2], dot[3], GLOW, NEON)
		end
		head:paintPair(2, 10, 4, 4, 12, 4, EYE_GLOW, NEON)
		head:paintPair(3, 10, 4, 3, 12, 4, PUPIL)
		head:boxPair(2, 13, 5, 4, 13, 5, PURPLE_DARK)
		head:boxPair(1, 12, 5, 1, 12, 5, PURPLE_DARK)
		head:box(-1, 7, 5, 0, 9, 5, BEAK)
		head:box(-1, 7, 6, 0, 7, 6, BEAK)
		head:box(2, 20, -1, 2, 20, -1, BARNACLE)
		head:box(-3, 20, -5, -3, 20, -5, BARNACLE)
		head:box(2, 20, -5, 2, 20, -5, BARNACLE)
		head:box(-5, 15, 1, -5, 15, 1, BARNACLE)
		head:box(4, 15, -2, 4, 17, -2, CORAL)
		head:box(5, 16, -2, 5, 16, -2, CORAL)
		head:box(5, 18, -2, 5, 18, -2, CORAL)
		head:box(-2, 22, -5, 1, 22, -3, GOLD)
		head:box(-2, 23, -5, -2, 23, -5, GOLD)
		head:box(1, 23, -5, 1, 24, -5, GOLD)
		head:box(-2, 23, -3, -2, 23, -3, GOLD)
		head:box(1, 23, -3, 1, 24, -3, GOLD)
		head:paint(-1, 22, -3, 0, 22, -3, RUBY)
		head:paint(1, 22, -5, 1, 22, -5, RUBY)
		head:box(-3, 20, -4, -3, 22, -4, rgb(60, 140, 90))
		head:box(2, 20, -4, 2, 21, -4, rgb(60, 140, 90))

		-- Eight thick tentacles spreading over the ground, lined with suckers, their tips curling up and glowing.
		local function frontTentacle(limb)
			limb:box(2, 2, 3, 3, 4, 4, PURPLE)
			limb:box(3, 1, 5, 4, 2, 6, PURPLE)
			limb:box(4, 0, 7, 5, 1, 9, PURPLE)
			limb:box(5, 0, 10, 5, 0, 11, PURPLE)
			limb:box(5, 1, 12, 5, 2, 12, MAGENTA)
			limb:box(5, 3, 11, 5, 3, 11, GLOW, NEON)
			limb:paint(4, 1, 7, 4, 1, 7, SUCKER)
			limb:paint(5, 1, 9, 5, 1, 9, SUCKER)
			limb:paint(3, 2, 5, 3, 2, 5, SUCKER)
			limb:paint(5, 0, 11, 5, 0, 11, SUCKER)
			limb:paint(2, 4, 4, 3, 4, 4, MAGENTA)
			limb:box(4, 2, 8, 4, 2, 8, BARNACLE)
		end
		local function sideTentacle(limb)
			limb:box(4, 2, 0, 5, 4, 2, PURPLE)
			limb:box(6, 1, 1, 7, 2, 2, PURPLE)
			limb:box(8, 0, 1, 10, 1, 2, PURPLE)
			limb:box(11, 0, 2, 12, 0, 2, PURPLE)
			limb:box(13, 1, 2, 13, 2, 2, MAGENTA)
			limb:box(12, 3, 2, 12, 3, 2, GLOW, NEON)
			limb:paint(6, 2, 2, 6, 2, 2, SUCKER)
			limb:paint(8, 1, 2, 8, 1, 2, SUCKER)
			limb:paint(10, 1, 2, 10, 1, 2, SUCKER)
			limb:paint(12, 0, 2, 12, 0, 2, SUCKER)
			limb:paint(4, 4, 0, 5, 4, 1, MAGENTA)
			limb:box(9, 2, 1, 9, 2, 1, BARNACLE)
		end
		local function rearSideTentacle(limb)
			limb:box(4, 2, -3, 5, 4, -2, PURPLE)
			limb:box(6, 1, -4, 7, 2, -3, PURPLE)
			limb:box(8, 0, -6, 9, 1, -4, PURPLE)
			limb:box(10, 0, -8, 10, 0, -6, PURPLE)
			limb:box(11, 1, -8, 11, 2, -8, MAGENTA)
			limb:box(11, 3, -7, 11, 3, -7, GLOW, NEON)
			limb:paint(6, 2, -3, 6, 2, -3, SUCKER)
			limb:paint(9, 1, -5, 9, 1, -5, SUCKER)
			limb:paint(10, 0, -7, 10, 0, -7, SUCKER)
			limb:paint(8, 1, -4, 8, 1, -4, SUCKER)
			limb:paint(4, 4, -3, 5, 4, -2, MAGENTA)
		end
		local function rearTentacle(limb)
			limb:box(2, 2, -5, 3, 4, -4, PURPLE)
			limb:box(3, 1, -7, 4, 2, -6, PURPLE)
			limb:box(4, 0, -10, 5, 1, -8, PURPLE)
			limb:box(5, 0, -12, 5, 0, -11, PURPLE)
			limb:box(5, 1, -13, 5, 2, -13, MAGENTA)
			limb:box(5, 3, -12, 5, 3, -12, GLOW, NEON)
			limb:paint(4, 1, -9, 4, 1, -9, SUCKER)
			limb:paint(3, 2, -6, 3, 2, -6, SUCKER)
			limb:paint(5, 0, -11, 5, 0, -11, SUCKER)
			limb:paint(2, 4, -5, 3, 4, -4, MAGENTA)
			limb:box(4, 2, -9, 4, 2, -9, BARNACLE)
		end
		local shapes = {
			{ frontTentacle, { 2.5, 3, 3.5 } },
			{ sideTentacle, { 4.5, 3, 1 } },
			{ rearSideTentacle, { 4.5, 3, -2.5 } },
			{ rearTentacle, { 2.5, 3, -4.5 } },
		}
		local grip
		for index, shape in shapes do
			local draw, pivot = shape[1], shape[2]
			draw(pet:limb("Tentacle" .. (index * 2 - 1), pivot))
			local right = mirrored(pet:limb("Tentacle" .. (index * 2), { -pivot[1], pivot[2], pivot[3] }))
			draw(right)
			if index == 2 then
				grip = right
			end
		end
		-- One tentacle grips a rusted ship's anchor.
		grip:box(13, 1, 1, 13, 8, 1, IRON)
		grip:box(11, 7, 1, 15, 7, 1, IRON)
		grip:box(12, 9, 1, 12, 10, 1, IRON)
		grip:box(14, 9, 1, 14, 10, 1, IRON)
		grip:box(13, 11, 1, 13, 11, 1, IRON)
		grip:box(11, 0, 1, 15, 0, 1, IRON)
		grip:box(11, 1, 1, 11, 2, 1, IRON)
		grip:box(15, 1, 1, 15, 2, 1, IRON)
		grip:paint(13, 4, 1, 13, 5, 1, RUST)
		grip:paint(14, 0, 1, 15, 0, 1, RUST)
		grip:paint(11, 7, 1, 11, 7, 1, RUST)
		grip:box(12, 5, 2, 14, 5, 2, MAGENTA)
		grip:box(13, 12, 1, 13, 12, 1, IRON)
		grip:box(12, 13, 1, 12, 13, 1, IRON)
		grip:box(11, 14, 1, 11, 14, 1, IRON)
		grip:paint(13, 12, 1, 13, 12, 1, RUST)

		pet:light(GLOW, 2.6, 18)
		pet:particles("Bubbles", SUCKER, 12)
		pet:seat(0, 18, 1)
	end,
}

Designs.Leviathan = {
	name = "Leviathan",
	skeleton = "Serpent",
	gait = "Swim",
	scale = 0.55,
	draw = function(pet)
		local SCALE = rgb(18, 42, 58)
		local SCALE_LIGHT = rgb(30, 78, 96)
		local BELLY = rgb(46, 122, 130)
		local GLOW = rgb(80, 255, 228)
		local FIN = rgb(90, 220, 210)
		local HORN = rgb(196, 222, 226)
		local FANG = rgb(236, 244, 244)
		local THROAT = rgb(180, 255, 240)

		-- Scales: a checker of lighter scales over the sides of a block, between two heights.
		local function scales(limb, x: number, y0: number, y1: number, z0: number, z1: number)
			for y = y0, y1 do
				for z = z0, z1 do
					if (y + z) % 2 == 0 then
						limb:paintPair(x, y, z, x, y, z, SCALE_LIGHT)
					end
				end
			end
		end

		-- The front coil rising from the ground into a long neck, pale-bellied, glowing along its flanks.
		local body = pet:limb("Body", { 0, 4, 4 })
		body:box(-3, 0, 2, 2, 5, 6, SCALE)
		body:box(-2, 6, 4, 1, 12, 7, SCALE)
		body:paint(-2, 6, 7, 1, 12, 7, BELLY)
		body:paint(-3, 0, 6, 2, 5, 6, BELLY)
		body:paint(-2, 7, 7, 1, 7, 7, SCALE)
		body:paint(-2, 10, 7, 1, 10, 7, SCALE)
		body:paintPair(2, 2, 2, 2, 2, 5, GLOW, NEON)
		body:paintPair(1, 8, 4, 1, 11, 4, GLOW, NEON)
		scales(body, 2, 3, 5, 2, 5)
		scales(body, 1, 6, 7, 5, 6)
		body:box(-1, 8, 3, 0, 11, 3, FIN, GLASS, 0.3)
		body:paint(-1, 9, 3, 0, 9, 3, GLOW, NEON)
		body:box(-1, 6, 3, 0, 6, 3, HORN)
		scales(body, 1, 8, 12, 5, 6)

		-- A dragon's head with an open jaw: fangs, a glowing throat, glowing eyes, swept-back horns,
		-- glassy frilled gills and a crest.
		local head = pet:limb("Head", { 0, 13, 6 })
		head:box(-3, 13, 5, 2, 17, 10, SCALE)
		head:box(-2, 13, 11, 1, 15, 14, SCALE)
		head:box(-2, 10, 9, 1, 11, 13, SCALE)
		head:box(-1, 12, 9, 0, 12, 11, THROAT, NEON)
		head:paint(-2, 10, 9, 1, 10, 13, BELLY)
		head:boxPair(1, 12, 13, 1, 12, 13, FANG)
		head:boxPair(1, 12, 12, 1, 12, 12, FANG)
		head:paint(-1, 15, 14, 0, 15, 14, SCALE_LIGHT)
		head:paintPair(1, 14, 14, 1, 14, 14, GLOW, NEON)
		head:paintPair(2, 16, 10, 2, 16, 10, GLOW, NEON)
		head:boxPair(2, 17, 11, 3, 17, 11, HORN)
		head:boxPair(2, 18, 6, 2, 19, 7, HORN)
		head:boxPair(2, 20, 4, 2, 21, 5, HORN)
		head:boxPair(2, 22, 3, 2, 22, 3, GLOW, NEON)
		head:boxPair(3, 13, 6, 5, 16, 7, FIN, GLASS, 0.3)
		head:paintPair(4, 13, 7, 4, 16, 7, GLOW, NEON)
		head:boxPair(6, 14, 6, 6, 15, 6, FIN, GLASS, 0.3)
		head:box(-1, 18, 5, 0, 19, 9, FIN, GLASS, 0.3)
		head:paint(-1, 18, 7, 0, 19, 7, GLOW, NEON)
		scales(head, 2, 13, 16, 5, 9)
		head:paintPair(2, 13, 11, 2, 13, 13, GLOW, NEON)
		head:boxPair(1, 12, 10, 1, 12, 10, FANG)
		head:box(-1, 18, 10, -1, 20, 10, HORN)
		head:box(-1, 21, 11, -1, 21, 12, HORN)
		head:box(-1, 19, 13, -1, 20, 13, GLOW, NEON)
		head:paint(-3, 17, 6, 2, 17, 6, SCALE_LIGHT)
		head:paintPair(1, 17, 8, 1, 17, 8, GLOW, NEON)
		head:paintPair(2, 14, 5, 2, 14, 5, GLOW, NEON)

		-- Front flippers with see-through webbing.
		pet:limbPair("LeftFin", "RightFin", { 3, 3, 4 }, function(fin)
			fin:box(3, 2, 3, 3, 4, 5, SCALE_LIGHT)
			fin:box(4, 1, 2, 6, 4, 6, FIN, GLASS, 0.3)
			fin:paint(5, 1, 3, 5, 4, 3, GLOW, NEON)
			fin:paint(5, 1, 5, 5, 4, 5, GLOW, NEON)
		end)

		-- A great arching coil with a glassy crest and glowing stripes.
		local coil = pet:limb("Segment1", { 0, 3, 1 })
		coil:box(-3, 0, -1, 2, 5, 1, SCALE)
		coil:box(-3, 6, -5, 2, 9, -1, SCALE)
		coil:box(-3, 0, -7, 2, 5, -5, SCALE)
		coil:paint(-3, 6, -5, 2, 6, -1, BELLY)
		coil:paint(-3, 0, 1, 2, 5, 1, BELLY)
		coil:paintPair(2, 7, -5, 2, 7, -1, GLOW, NEON)
		coil:paintPair(2, 2, -7, 2, 2, -5, GLOW, NEON)
		coil:paintPair(2, 3, -1, 2, 3, 0, GLOW, NEON)
		scales(coil, 2, 8, 9, -5, -1)
		scales(coil, 2, 3, 5, -7, -5)
		scales(coil, 2, 0, 2, -1, 0)
		coil:box(-1, 10, -5, 0, 11, -2, FIN, GLASS, 0.3)
		coil:paint(-1, 10, -4, 0, 11, -4, GLOW, NEON)
		coil:box(-1, 6, -7, 0, 7, -6, FIN, GLASS, 0.3)

		-- A smaller second coil.
		local coil2 = pet:limb("Segment2", { 0, 2, -7 }, "Segment1")
		coil2:box(-2, 0, -9, 1, 4, -8, SCALE)
		coil2:box(-2, 5, -12, 1, 7, -8, SCALE)
		coil2:box(-2, 0, -13, 1, 4, -12, SCALE)
		coil2:paint(-2, 5, -12, 1, 5, -8, BELLY)
		coil2:paintPair(1, 6, -12, 1, 6, -8, GLOW, NEON)
		coil2:paintPair(1, 2, -13, 1, 2, -12, GLOW, NEON)
		scales(coil2, 1, 0, 4, -9, -8)
		coil2:box(-1, 8, -12, 0, 9, -9, FIN, GLASS, 0.3)
		coil2:paint(-1, 8, -10, 0, 9, -10, GLOW, NEON)
		coil2:box(-1, 8, -8, 0, 8, -8, HORN)
		scales(coil2, 1, 5, 7, -12, -9)
		scales(coil2, 1, 0, 4, -13, -12)

		-- A tapering tail ending in a tall see-through fin.
		local tail = pet:limb("Tail", { 0, 2, -13 }, "Segment2")
		tail:box(-1, 0, -17, 0, 2, -14, SCALE)
		tail:box(-1, 1, -19, 0, 3, -18, SCALE)
		tail:paintPair(0, 1, -17, 0, 1, -14, GLOW, NEON)
		tail:box(-1, 2, -22, 0, 7, -20, FIN, GLASS, 0.3)
		tail:paint(-1, 3, -21, 0, 7, -21, GLOW, NEON)
		tail:box(-1, 8, -21, 0, 8, -21, GLOW, NEON)
		tail:box(-1, 3, -16, 0, 3, -16, HORN)
		tail:box(-1, 3, -14, 0, 3, -14, HORN)
		tail:box(-1, 4, -18, 0, 4, -18, HORN)

		pet:light(GLOW, 2.6, 18)
		pet:particles("Bubbles", GLOW, 12)
		pet:seat(0, 10, -1)
	end,
}

return Designs
