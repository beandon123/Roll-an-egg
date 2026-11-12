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

		local body = pet:limb("Body", { 0, 4, 0 })
		body:box(-3, 3, -3, 2, 7, 3, FUR)
		body:paint(-2, 3, 3, 1, 6, 3, CREAM)

		local head = pet:limb("Head", { 0, 8, 1 })
		head:box(-4, 8, -1, 3, 14, 5, FUR)
		head:paint(-3, 8, 5, 2, 10, 5, CREAM)
		head:paint(-1, 10, 5, 0, 10, 5, NOSE)
		eyes(head, 1, 11, 5)
		-- Pointed ears with dark tufts.
		head:boxPair(2, 15, 1, 3, 16, 2, FUR)
		head:boxPair(3, 17, 2, 3, 17, 2, DARK)

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

		local head = pet:limb("Head", { 0, 7, 1 })
		head:box(-3, 7, -1, 2, 12, 4, FUR)
		-- Fluffy cheeks.
		head:box(-4, 7, 0, 3, 9, 3, FUR)
		head:paint(-1, 9, 4, 0, 9, 4, PINK)
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

		-- A pointed little face poking out of the front.
		local head = pet:limb("Head", { 0, 3, 4 })
		head:box(-2, 1, 4, 1, 4, 6, FACE)
		head:box(-1, 1, 7, 0, 2, 7, FACE)
		head:box(-1, 2, 8, 0, 2, 8, EYE)
		head:paintPair(1, 3, 6, 1, 3, 6, EYE)
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

		local head = pet:limb("Head", { 0, 7, 3 })
		head:box(-3, 7, 2, 2, 12, 7, ORANGE)
		-- White cheeks and a pointed muzzle with a dark nose.
		head:paint(-3, 7, 7, 2, 8, 7, WHITE)
		head:box(-1, 7, 8, 0, 8, 9, WHITE)
		head:box(-1, 8, 10, 0, 8, 10, DARK)
		eyes(head, 1, 9, 7, 1)
		-- Big pointed ears with dark tips.
		head:boxPair(1, 13, 4, 2, 14, 5, ORANGE)
		head:paintPair(1, 13, 5, 1, 13, 5, WHITE)
		head:boxPair(2, 15, 4, 2, 15, 5, DARK)

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
		local DARK = rgb(100, 68, 42)
		local LIGHT = rgb(222, 196, 152)
		local BEAK = rgb(242, 164, 44)
		local RING = rgb(255, 214, 70)

		-- A round body with a speckled chest.
		local body = pet:limb("Body", { 0, 2, 0 })
		body:box(-4, 2, -3, 3, 9, 3, BROWN)
		body:paint(-3, 2, 3, 2, 8, 3, LIGHT)
		body:paintPair(1, 6, 3, 1, 6, 3, DARK)
		body:paintPair(2, 4, 3, 2, 4, 3, DARK)
		body:paint(-1, 3, 3, -1, 3, 3, DARK)

		-- A pale face disc, big yellow eyes, a hooked beak and ear tufts.
		local head = pet:limb("Head", { 0, 10, 0 })
		head:box(-4, 10, -3, 3, 15, 3, BROWN)
		head:paint(-4, 10, 3, 3, 14, 3, LIGHT)
		head:paintPair(1, 12, 3, 2, 13, 3, RING)
		head:paintPair(1, 12, 3, 1, 13, 3, EYE)
		head:paintPair(1, 13, 3, 1, 13, 3, SHINE)
		head:box(-1, 10, 4, 0, 11, 4, BEAK)
		head:boxPair(2, 16, -1, 3, 16, 0, BROWN)
		head:boxPair(3, 17, -1, 3, 17, 0, DARK)

		pet:limbPair("LeftWing", "RightWing", { 4.5, 9, 0 }, function(wing)
			wing:box(4, 3, -2, 4, 9, 2, DARK)
			wing:paint(4, 3, -2, 4, 3, 2, LIGHT)
			wing:paint(4, 5, 2, 4, 5, 2, LIGHT)
		end)
		pet:limbPair("LeftLeg", "RightLeg", { 2, 2, 1 }, function(leg)
			leg:box(1, 0, 0, 2, 1, 1, BEAK)
			leg:box(1, 0, 2, 2, 0, 2, BEAK)
		end)

		local tail = pet:limb("Tail", { 0, 3, -3 })
		tail:box(-2, 2, -4, 1, 4, -4, DARK)

		pet:seat(0, 16, -1)
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
		local LIGHT = rgb(228, 198, 152)
		local MOSS = rgb(86, 146, 66)
		local MOSS_LIGHT = rgb(140, 196, 96)
		local WOOD = rgb(168, 126, 82)
		local HOOF = rgb(64, 46, 34)
		local PINK = rgb(255, 150, 196)
		local YELLOW = rgb(255, 220, 80)

		-- A deer's body under a blanket of moss, with blossoms growing in it.
		local body = pet:limb("Body", { 0, 8, 0 })
		body:box(-4, 6, -6, 3, 11, 5, DEER)
		body:paint(-3, 6, 5, 2, 9, 5, LIGHT)
		body:box(-5, 10, -5, 4, 12, 3, MOSS)
		body:paint(-3, 12, -3, -1, 12, -1, MOSS_LIGHT)
		body:paint(1, 12, 0, 3, 12, 2, MOSS_LIGHT)
		body:paintPair(4, 10, -4, 4, 11, -2, MOSS_LIGHT)
		body:paint(2, 12, -4, 2, 12, -4, PINK, NEON)
		body:paint(-4, 12, 1, -4, 12, 1, YELLOW, NEON)

		local head = pet:limb("Head", { 0, 11, 4 })
		head:box(-2, 10, 4, 1, 14, 6, DEER)
		head:box(-3, 14, 4, 2, 18, 9, DEER)
		head:box(-2, 14, 10, 1, 16, 11, LIGHT)
		head:paint(-1, 16, 11, 0, 16, 11, HOOF)
		eyes(head, 1, 16, 9, 1)
		head:boxPair(3, 17, 6, 4, 17, 7, DEER)
		-- Branching antlers with moss and glowing blossoms.
		head:boxPair(1, 19, 6, 1, 21, 6, WOOD)
		head:boxPair(2, 21, 6, 3, 21, 6, WOOD)
		head:boxPair(3, 22, 6, 3, 25, 6, WOOD)
		head:boxPair(4, 24, 6, 5, 24, 6, WOOD)
		head:boxPair(2, 23, 6, 2, 24, 6, WOOD)
		head:paintPair(3, 22, 6, 3, 22, 6, MOSS_LIGHT)
		head:boxPair(5, 25, 6, 5, 25, 6, PINK, NEON)
		head:boxPair(3, 26, 6, 3, 26, 6, YELLOW, NEON)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 7, 4 }, function(leg)
			leg:box(2, 0, 3, 3, 6, 4, DEER)
			leg:paint(2, 0, 3, 3, 0, 4, HOOF)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 7, -4 }, function(leg)
			leg:box(2, 0, -5, 3, 6, -4, DEER)
			leg:paint(2, 0, -5, 3, 0, -4, HOOF)
		end)

		local tail = pet:limb("Tail", { 0, 10, -6 })
		tail:box(-1, 9, -7, 0, 10, -7, LIGHT)

		pet:seat(0, 13, -1)
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
		body:box(-7, 14, -2, -6, 14, 0, CAP)
		body:paint(-7, 14, -1, -7, 14, -1, SPOT)
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
		head:box(-4, 18, 3, -4, 18, 3, SAP, NEON)
		head:box(3, 17, 2, 3, 18, 2, SAP, NEON)
		head:box(-2, 18, -4, -2, 18, -4, SAP, NEON)

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
		body:box(-4, 2, -5, 3, 6, 4, SHELL)
		body:box(-3, 7, -4, 2, 7, 3, SHELL)
		for _, z in { -3, -1, 1 } do
			body:box(-5, 2, z, 4, 6, z, BAND)
			body:box(-4, 7, z, 3, 7, z, BAND)
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

		pet:seat(0, 8, -1)
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

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 1.5, 3.5, 1.5 }, function(leg)
			leg:box(1, 0, 1, 1, 3, 1, CREAM)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 1.5, 3.5, -2.5 }, function(leg)
			leg:box(1, 0, -3, 1, 3, -3, CREAM)
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
		local DARK = rgb(150, 104, 60)
		local LIGHT = rgb(236, 204, 156)
		local RED = rgb(196, 48, 52)
		local GOLD = rgb(255, 196, 56)
		local TEAL = rgb(56, 180, 176)

		-- Two humps, with the saddle blanket from its egg draped between them.
		local body = pet:limb("Body", { 0, 9, 0 })
		body:box(-4, 8, -6, 3, 13, 5, CAMEL)
		body:paint(-3, 8, -5, 2, 8, 4, LIGHT)
		body:box(-3, 14, 1, 2, 16, 4, CAMEL)
		body:box(-2, 17, 2, 1, 17, 3, CAMEL)
		body:box(-3, 14, -5, 2, 16, -2, CAMEL)
		body:box(-2, 17, -4, 1, 17, -3, CAMEL)
		body:box(-5, 10, -1, 4, 14, 0, RED)
		body:paint(-5, 10, -1, 4, 10, 0, GOLD)
		body:paint(-5, 12, -1, 4, 12, 0, TEAL)
		body:boxPair(4, 9, -1, 4, 9, -1, GOLD)
		body:boxPair(4, 9, 0, 4, 9, 0, GOLD)

		-- A long curved neck, droopy lips and a bridle.
		local head = pet:limb("Head", { 0, 12, 5 })
		head:box(-2, 10, 6, 1, 13, 8, CAMEL)
		head:box(-2, 14, 8, 1, 17, 9, CAMEL)
		head:box(-2, 17, 8, 1, 20, 12, CAMEL)
		head:box(-2, 17, 13, 1, 18, 13, LIGHT)
		head:paint(-1, 18, 13, 0, 18, 13, DARK)
		head:box(-1, 16, 13, 0, 16, 13, LIGHT)
		eyes(head, 1, 19, 12, 1)
		head:boxPair(1, 21, 9, 1, 21, 9, CAMEL)
		head:paint(-2, 18, 10, 1, 18, 11, RED)
		head:paintPair(1, 18, 11, 1, 18, 11, GOLD)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 8, 4 }, function(leg)
			leg:box(2, 0, 3, 3, 8, 4, CAMEL)
			leg:paint(2, 4, 3, 3, 4, 4, DARK)
			leg:paint(2, 0, 3, 3, 0, 4, DARK)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 8, -4 }, function(leg)
			leg:box(2, 0, -5, 3, 8, -4, CAMEL)
			leg:paint(2, 4, -5, 3, 4, -4, DARK)
			leg:paint(2, 0, -5, 3, 0, -4, DARK)
		end)

		local tail = pet:limb("Tail", { 0, 12, -6 })
		tail:box(-1, 9, -7, 0, 12, -7, CAMEL)
		tail:box(-1, 8, -7, 0, 8, -7, DARK)

		pet:seat(0, 15, -1)
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

		-- A low, plated body.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 2, -4, 3, 4, 3, AMBER)
		body:box(-2, 5, -3, 1, 5, 2, AMBER)
		body:paint(-4, 4, -2, 3, 4, -2, DARK)
		body:paint(-4, 4, 1, 3, 4, 1, DARK)
		body:paint(-2, 5, -3, 1, 5, -3, DARK)
		body:paint(-1, 5, 0, 0, 5, 1, LIGHT)

		-- A head with big pincers reaching forward.
		local head = pet:limb("Head", { 0, 3, 4 })
		head:box(-3, 2, 4, 2, 4, 6, AMBER)
		eyes(head, 1, 3, 6, 1)
		head:boxPair(3, 3, 6, 3, 3, 8, AMBER)
		head:boxPair(3, 2, 9, 5, 4, 10, AMBER)
		head:boxPair(3, 3, 11, 3, 3, 12, DARK)
		head:boxPair(5, 3, 11, 5, 3, 12, DARK)
		head:paintPair(3, 4, 9, 5, 4, 10, LIGHT)

		-- Six jointed legs.
		local function leg(z: number)
			return function(limb)
				limb:box(4, 3, z, 5, 3, z, AMBER)
				limb:box(6, 0, z, 6, 3, z, DARK)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 4, 3, 2.5 }, leg(2))
		pet:limbPair("MiddleLeftLeg", "MiddleRightLeg", { 4, 3, 0.5 }, leg(0))
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 4, 3, -1.5 }, leg(-2))

		-- A segmented tail curling over its back, with a glowing stinger.
		local tail = pet:limb("Tail", { 0, 4, -4 })
		tail:box(-1, 3, -6, 0, 4, -5, AMBER)
		tail:box(-1, 5, -7, 0, 6, -6, DARK)
		tail:box(-1, 7, -7, 0, 8, -6, AMBER)
		tail:box(-1, 9, -6, 0, 10, -5, DARK)
		tail:box(-1, 11, -5, 0, 12, -3, AMBER)
		tail:box(-1, 12, -2, 0, 12, -1, DARK)
		tail:box(-1, 11, 0, 0, 12, 0, DARK)
		tail:box(-1, 9, 1, 0, 10, 1, VENOM, NEON)

		pet:seat(0, 6, 0)
	end,
}

Designs.PharaohJackal = {
	name = "Pharaoh Jackal",
	skeleton = "Quadruped",
	scale = 0.55,
	draw = function(pet)
		local BLACK = rgb(38, 34, 42)
		local GOLD = rgb(255, 196, 56)
		local LAPIS = rgb(40, 86, 196)
		local TEAL = rgb(56, 180, 176)

		-- A sleek black body with a jewelled gold collar.
		local body = pet:limb("Body", { 0, 6, 0 })
		body:box(-3, 5, -5, 2, 9, 4, BLACK)
		body:box(-4, 8, 3, 3, 10, 4, GOLD)
		body:paint(-4, 10, 3, 3, 10, 4, LAPIS)
		body:paint(-1, 8, 4, 0, 8, 4, TEAL)

		-- A long muzzle, glowing gold eyes, a striped headdress and tall ears.
		local head = pet:limb("Head", { 0, 10, 4 })
		head:box(-2, 9, 4, 1, 11, 5, BLACK)
		head:box(-2, 11, 3, 1, 14, 7, BLACK)
		head:box(-1, 11, 8, 0, 12, 10, BLACK)
		head:paintPair(1, 13, 7, 1, 13, 7, GOLD, NEON)
		head:box(-3, 14, 3, 2, 15, 6, GOLD)
		head:paint(-3, 15, 3, 2, 15, 6, LAPIS)
		head:boxPair(2, 10, 4, 2, 13, 5, GOLD)
		head:paintPair(2, 11, 4, 2, 11, 5, LAPIS)
		head:paintPair(2, 13, 4, 2, 13, 5, LAPIS)
		head:boxPair(1, 16, 4, 2, 17, 5, BLACK)
		head:boxPair(1, 18, 4, 1, 19, 5, BLACK)
		head:paintPair(1, 16, 5, 1, 17, 5, GOLD)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 2, 5, 3 }, function(leg)
			leg:box(1, 0, 2, 2, 4, 3, BLACK)
			leg:paint(1, 1, 2, 2, 1, 3, GOLD)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 2, 5, -4 }, function(leg)
			leg:box(1, 0, -5, 2, 4, -4, BLACK)
			leg:paint(1, 1, -5, 2, 1, -4, GOLD)
		end)

		local tail = pet:limb("Tail", { 0, 8, -5 })
		tail:box(-1, 6, -7, 0, 8, -6, BLACK)
		tail:box(-1, 4, -8, 0, 6, -8, BLACK)
		tail:paint(-1, 4, -8, 0, 4, -8, GOLD)

		pet:seat(0, 10, -1)
	end,
}

Designs.Sphinx = {
	name = "Sphinx",
	skeleton = "Quadruped",
	gait = "Stomp",
	scale = 0.55,
	draw = function(pet)
		local STONE = rgb(226, 192, 124)
		local STONE_DARK = rgb(184, 148, 88)
		local GOLD = rgb(255, 196, 56)
		local LAPIS = rgb(40, 86, 196)
		local TEAL = rgb(56, 180, 176)

		-- A stone lion's body with wings folded up over its back.
		local body = pet:limb("Body", { 0, 6, 0 })
		body:box(-4, 5, -6, 3, 10, 5, STONE)
		body:boxPair(3, 11, 0, 4, 13, 3, STONE)
		body:boxPair(4, 12, -6, 4, 14, 2, STONE)
		body:paintPair(4, 12, -6, 4, 12, 2, STONE_DARK)
		body:paintPair(4, 14, -6, 4, 14, -4, STONE_DARK)
		body:paintPair(4, 14, -2, 4, 14, 2, GOLD)
		body:paint(-3, 5, -5, 2, 5, 4, STONE_DARK)

		-- A face framed by a striped headdress, with a crown, a gem and a gold beard.
		local head = pet:limb("Head", { 0, 10, 5 })
		head:box(-3, 10, 5, 2, 15, 9, STONE)
		head:box(-1, 10, 10, 0, 11, 10, STONE_DARK)
		eyes(head, 1, 12, 9, 1)
		head:box(-4, 15, 4, 3, 16, 9, GOLD)
		head:paint(-4, 16, 4, 3, 16, 9, LAPIS)
		head:boxPair(3, 9, 6, 3, 14, 8, GOLD)
		head:paintPair(3, 10, 6, 3, 10, 8, LAPIS)
		head:paintPair(3, 12, 6, 3, 12, 8, LAPIS)
		head:paintPair(3, 14, 6, 3, 14, 8, LAPIS)
		head:box(-3, 11, 4, 2, 14, 4, GOLD)
		head:paint(-3, 12, 4, 2, 12, 4, LAPIS)
		head:box(-1, 17, 8, 0, 17, 8, GOLD)
		head:box(-1, 18, 8, 0, 18, 8, TEAL, NEON)
		head:box(-1, 8, 9, 0, 9, 9, GOLD)
		head:paint(-1, 8, 9, 0, 8, 9, LAPIS)

		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 6, 4 }, function(leg)
			leg:box(2, 0, 3, 3, 5, 4, STONE)
			leg:box(2, 0, 5, 3, 1, 5, STONE)
		end)
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 3, 6, -4 }, function(leg)
			leg:box(2, 0, -5, 3, 5, -4, STONE)
		end)

		-- A lion's tail with a tuft.
		local tail = pet:limb("Tail", { 0, 9, -6 })
		tail:box(-1, 9, -8, 0, 9, -7, STONE)
		tail:box(-1, 10, -9, 0, 12, -9, STONE)
		tail:box(-1, 13, -10, 0, 14, -9, STONE_DARK)

		pet:light(GOLD, 1.8, 12)
		pet:particles("Sparkles", GOLD, 6)
		pet:seat(0, 11, -2)
	end,
}

Designs.GoldenScarab = {
	name = "Golden Scarab",
	skeleton = "ManyLegged",
	scale = 0.6,
	draw = function(pet)
		local SCARAB = rgb(240, 186, 50)
		local BRONZE = rgb(196, 128, 38)
		local BRONZE_DARK = rgb(120, 76, 24)
		local TEAL = rgb(56, 180, 176)
		local SEAM = rgb(86, 56, 20)
		local SUN = rgb(255, 206, 70)

		-- Gold wing cases split by a dark seam, with teal shimmer.
		local body = pet:limb("Body", { 0, 3, 0 })
		body:box(-4, 2, -5, 3, 6, 2, SCARAB)
		body:box(-3, 7, -4, 2, 7, 1, SCARAB)
		body:paint(-1, 7, -4, 0, 7, 1, SEAM)
		body:paint(-1, 2, -5, 0, 6, -5, SEAM)
		body:paintPair(2, 7, -3, 2, 7, -2, TEAL)
		body:paintPair(3, 4, -3, 3, 5, -1, TEAL)
		body:box(-3, 2, 3, 2, 5, 4, BRONZE)

		-- A head with a curved horn holding up a glowing sun.
		local head = pet:limb("Head", { 0, 3, 5 })
		head:box(-2, 2, 5, 1, 4, 6, BRONZE_DARK)
		eyes(head, 1, 3, 6, 1, 1)
		head:box(-1, 5, 5, 0, 6, 6, BRONZE_DARK)
		head:box(-1, 7, 6, 0, 8, 6, BRONZE_DARK)
		head:box(-1, 9, 6, 0, 14, 6, SUN, NEON)
		head:box(-2, 10, 6, 1, 13, 6, SUN, NEON)
		head:box(-3, 11, 6, 2, 12, 6, SUN, NEON)

		local function leg(reach: number, z: number)
			return function(limb)
				limb:box(reach, 2, z, reach + 1, 2, z, BRONZE_DARK)
				limb:box(reach + 2, 0, z, reach + 2, 2, z, BRONZE_DARK)
			end
		end
		pet:limbPair("FrontLeftLeg", "FrontRightLeg", { 3, 2.5, 3.5 }, leg(3, 3))
		pet:limbPair("MiddleLeftLeg", "MiddleRightLeg", { 4, 2.5, 0.5 }, leg(4, 0))
		pet:limbPair("BackLeftLeg", "BackRightLeg", { 4, 2.5, -2.5 }, leg(4, -3))

		local tail = pet:limb("Tail", { 0, 3, -5 })
		tail:box(-1, 2, -6, 0, 3, -6, BRONZE)

		pet:light(SUN, 1.8, 12)
		pet:particles("Sparkles", SUN, 6)
		pet:seat(0, 8, -2)
	end,
}

return Designs
