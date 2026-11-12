--!strict
-- The look of every pet, by name. Which egg each pet hatches from is set in Config/Zones (`pet`).
-- Each design draws limbs on the pet builder in PetModels:
--     x left (+x) and right (-x); y up from the ground; z forward. A cell numbered x covers x to x + 1.
--     limb:box() draws a solid block, limb:paint() colours the surface of blocks already drawn (eyes, bellies),
--     and the ...Pair versions mirror across the middle of the pet.
-- Pets have big heads and small bodies, like the eggs they come from, and are themed to match their egg.
-- So far: the Forest pets. The other zones' pets come next.

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
	scale = 0.6,
	draw = function(pet)
		local BARK = rgb(112, 78, 48)
		local BARK_DARK = rgb(84, 56, 34)
		local LEAF = rgb(132, 202, 92)
		local MOSS = rgb(86, 146, 66)
		local SAP = rgb(196, 255, 110)
		local PINK = rgb(255, 150, 196)

		-- A walking tree trunk with glowing eyes.
		local body = pet:limb("Body", { 0, 5, 0 })
		body:box(-4, 5, -3, 3, 14, 3, BARK)
		body:paintPair(3, 6, 0, 3, 14, 0, BARK_DARK)
		body:paint(-2, 5, -3, -2, 13, -3, BARK_DARK)
		body:paint(1, 7, -3, 1, 14, -3, BARK_DARK)
		body:paintPair(1, 11, 3, 2, 11, 3, SAP, NEON)
		body:paint(-1, 8, 3, 0, 8, 3, BARK_DARK)
		body:paint(-4, 13, -3, -2, 14, 0, MOSS)

		-- Its head is a leafy crown, with blossoms and a glowing fruit.
		local head = pet:limb("Head", { 0, 15, 0 })
		head:box(-5, 15, -4, 4, 18, 4, LEAF)
		head:box(-4, 19, -3, 3, 20, 3, LEAF)
		head:box(-2, 21, -1, 1, 21, 1, LEAF)
		head:paint(-5, 15, -4, -3, 16, -2, MOSS)
		head:paint(2, 17, 2, 4, 18, 4, MOSS)
		head:paint(-1, 20, 2, 1, 20, 3, MOSS)
		head:paint(4, 17, -1, 4, 17, -1, PINK)
		head:paint(-3, 19, 3, -3, 19, 3, PINK)
		head:paint(1, 21, 0, 1, 21, 0, PINK)
		head:paint(-5, 18, 2, -5, 18, 2, PINK)
		head:paint(0, 15, 4, 0, 15, 4, SAP, NEON)

		-- Branch arms with twig fingers and a tuft of leaves.
		pet:limbPair("LeftArm", "RightArm", { 4.5, 12, 0 }, function(arm)
			arm:box(4, 11, -1, 5, 12, 0, BARK)
			arm:box(5, 6, -1, 6, 10, 0, BARK)
			arm:box(6, 4, -1, 6, 5, 0, BARK_DARK)
			arm:box(6, 9, 1, 7, 10, 2, LEAF)
		end)
		-- Stumpy legs on spreading roots.
		pet:limbPair("LeftLeg", "RightLeg", { 2, 5, 0 }, function(leg)
			leg:box(1, 1, -2, 3, 5, 1, BARK)
			leg:box(0, 0, -3, 4, 0, 3, BARK_DARK)
		end)

		pet:light(SAP, 1.6, 12)
		pet:particles("Sparkles", SAP, 6)
		pet:seat(0, 22, 0)
	end,
}

return Designs
