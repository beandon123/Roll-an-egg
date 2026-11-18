--!nocheck
-- Builds a web page that shows a rider running on a rolling egg, in 3D, so the riding animation (Shared/RiderPose)
-- can be checked without opening Studio: running on slow and fast eggs, steering, bumps, running out of stamina
-- (and being thrown off), landing, and cheering after a claim, on an R15 or an R6 character.
-- From the repository root:
--     lune run tools/rider-preview
-- writes tools/out/rider-preview.html. Open it in a browser. Pass a path to write somewhere else.
--
-- The poses are worked out here, by the same module the game uses, and played back by the page.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local harness = require("../tests/harness")

local EggModels = harness.load("src/shared/EggModels")
local EggSpec = harness.load("src/shared/EggSpec")
local RiderPose = harness.load("src/shared/RiderPose")
local Tuning = harness.load("src/shared/Config/Tuning")

local outPath = process.args[1] or "tools/out/rider-preview.html"

-- Frames a second of the recorded poses (the page blends between them).
local FPS = 30
-- Seconds the controller takes to start looking tired before stamina runs out (RiderAnimationController).
local TIRED_WARNING = 3

local function round(value: number): number
	return math.round(value * 1000) / 1000
end

local function hex(color): string
	return string.format("#%02x%02x%02x", color[1], color[2], color[3])
end

local function smooth(from: number, to: number, t: number): number
	local x = math.clamp((t - from) / (to - from), 0, 1)
	return x * x * (3 - 2 * x)
end

-- Each scenario: the egg ridden, how long it runs, and the rider's state at each moment (on top of the defaults).
-- `tumble` (seconds since being thrown off) replaces the riding pose.
local scenarios = {
	{
		id = "run",
		label = "Running",
		about = "Running on the spot as a Common egg rolls under them (18 studs a second).",
		zone = 1,
		rarity = "Common",
		seconds = 6,
		at = function(_t)
			return {}
		end,
	},
	{
		id = "fast",
		label = "Fast egg",
		about = "Quicker feet and longer strides on an Eternal egg (32 studs a second).",
		zone = 6,
		rarity = "Eternal",
		seconds = 6,
		at = function(_t)
			return {}
		end,
	},
	{
		id = "steer",
		label = "Steering",
		about = "Leaning into the turn, looking where they are going, the outside arm out for balance.",
		zone = 1,
		rarity = "Rare",
		seconds = 6,
		at = function(t)
			local right = smooth(0.6, 1.0, t) - smooth(2.2, 2.6, t)
			local left = smooth(3.4, 3.8, t) - smooth(5.0, 5.4, t)
			return { steer = right - left }
		end,
	},
	{
		id = "bump",
		label = "Bumped",
		about = "The egg bumps into something: the rider rocks with it, arms thrown out, and runs on.",
		zone = 1,
		rarity = "Rare",
		seconds = 6,
		at = function(t)
			local since = nil
			for _, at in { 1, 3, 5 } do
				if t >= at then
					since = t - at
				end
			end
			return { bumped = since }
		end,
	},
	{
		id = "tired",
		label = "Out of stamina",
		about = "Stamina running out: hunched, wobbling, arms windmilling, then thrown off.",
		zone = 1,
		rarity = "Legendary",
		seconds = 7,
		at = function(t)
			local outAt = 5
			if t >= outAt then
				return { tumble = t - outAt }
			end
			return { tired = 1 - math.clamp((outAt - t) / TIRED_WARNING, 0, 1) }
		end,
	},
	{
		id = "land",
		label = "Landing",
		about = "Landing on an egg from a leap: a quick squash, then straight into the run.",
		zone = 1,
		rarity = "Common",
		seconds = 4,
		at = function(t)
			return { landed = t % 2 }
		end,
	},
	{
		id = "claim",
		label = "Claimed",
		about = "The egg is theirs: one fist punched up high, pumping, as they ride on.",
		zone = 1,
		rarity = "Epic",
		seconds = 6,
		at = function(t)
			return { cheer = smooth(0.8, 1.3, t) }
		end,
	},
}

-- The four channels the page needs from each joint (the rest are always 0): rx, ry, rz and py.
local function pack(pose, names, into)
	for _, name in names do
		local p = pose[name]
		table.insert(into, round(p[1]))
		table.insert(into, round(p[2]))
		table.insert(into, round(p[3]))
		table.insert(into, round(p[5]))
	end
end

local function eggOf(zone: number, rarity: string)
	local spec = EggSpec.get(zone, rarity)
	local kind = EggSpec.pickEgg(zone, rarity, 0)
	local design = EggModels.get(kind)
	local voxel = spec.radius / EggModels.RADIUS
	local boxes = {}
	-- Lying on its side as on the runway (Shared/EggRig): the design's y becomes X and its x becomes -Y.
	for _, box in design.boxes do
		table.insert(boxes, {
			round(box.y * voxel),
			round(-box.x * voxel),
			round(box.z * voxel),
			round(box.sy * voxel),
			round(box.sx * voxel),
			round(box.sz * voxel),
			hex(box.color),
			box.material,
			box.transparency,
		})
	end
	return {
		name = EggModels.describe(kind).name,
		rarity = rarity,
		radius = spec.radius,
		speed = spec.rollSpeed,
		rollHeight = spec.radius * (EggModels.RADIUS + EggModels.CORNER_REACH) / (2 * EggModels.RADIUS),
		boxes = boxes,
	}
end

local list = {}
for _, scenario in scenarios do
	local egg = eggOf(scenario.zone, scenario.rarity)
	local frames = {}
	local phase = 0
	local pose, r6 = nil, nil
	for index = 0, scenario.seconds * FPS - 1 do
		local t = index / FPS
		local extra = scenario.at(t)
		local frame = {}
		if extra.tumble then
			pose = RiderPose.tumble(t, extra.tumble, pose)
		else
			pose = RiderPose.pose({
				phase = phase,
				time = t,
				speed = egg.speed,
				steer = extra.steer or 0,
				tired = extra.tired or 0,
				cheer = extra.cheer or 0,
				landed = extra.landed,
				bumped = extra.bumped,
			}, pose)
		end
		r6 = RiderPose.toR6(pose, r6)
		pack(pose, RiderPose.JOINTS, frame)
		pack(r6, RiderPose.R6_JOINTS, frame)
		table.insert(frame, if extra.tumble then round(extra.tumble) else -1)
		table.insert(frames, frame)
		phase = RiderPose.advance(phase, egg.speed, 1 / FPS)
	end
	table.insert(list, {
		id = scenario.id,
		label = scenario.label,
		about = scenario.about,
		egg = egg,
		frames = frames,
	})
end

local data = {
	fps = FPS,
	joints = RiderPose.JOINTS,
	r6Joints = RiderPose.R6_JOINTS,
	stunTime = Tuning.STUN_TIME,
	scenarios = list,
}

local template = fs.readFile("tools/rider-preview.html")
local page = template:gsub("/%*RIDER_DATA%*/null", function()
	return serde.encode("json", data)
end)
local folder = outPath:match("^(.*)/[^/]+$")
if folder and not fs.isDir(folder) then
	fs.writeDir(folder)
end
fs.writeFile(outPath, page)
print(`Wrote {outPath}`)
