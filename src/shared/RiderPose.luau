--!strict
-- How a rider moves on top of a rolling egg, or of their training stick's roller. They run on the spot to stay on it
-- as it rolls under them, quicker on faster eggs (and in a training boost). They lean into their steering, and stumble with their arms thrown out when the egg bumps into
-- something. As their stamina runs out they hunch over, wobble and windmill their arms to keep their balance. Once
-- the egg is theirs they pump a fist in the air as they go. When they are thrown off they tumble through the air,
-- arms and legs flailing.
--
-- Pure math (no Roblox APIs), so the test runner and the preview pages (tools/rider-preview, tools/map-preview) can
-- load it. The client's RiderAnimationController keeps each rider's State up to date and turns the pose into their
-- joints every frame.
--
-- A pose gives each joint of an R15 character (named as its Motor6D) a turn and a shift of the limb hanging from it:
-- { rx, ry, rz, px, py, pz }. Turns are in radians about the parent part's axes, Roblox's own (x to the character's
-- right, y up, z backwards), applied as CFrame.fromEulerAnglesYXZ(rx, ry, rz). Shifts are in studs, for a character
-- of the usual size (its root part 3 studs off the ground). So:
--     rx  positive swings a hanging limb forwards (and bends an elbow), negative bends a knee, and tips the body back
--     ry  positive turns to the character's left
--     rz  positive tips the body to its left, swings a right limb out to the side and a left limb in
-- RiderPose.toR6 folds a pose onto the six joints of an R6 character.

local Rarities = require(script.Parent.Config.Rarities)

local RiderPose = {}

export type Pose = { [string]: { number } }

export type State = {
	-- Where the stride is, in radians: one full turn is a step with each foot. The caller moves it on with
	-- RiderPose.advance, so the legs never jump when the pace changes.
	phase: number,
	-- Seconds, for the sways and flails that are not tied to the stride.
	time: number,
	-- How hard they run, from 0 (as on the slowest eggs) to 1 (the fastest): see RiderPose.paceOf.
	pace: number,
	-- Steering, from -1 (sideways to the rider's left, flat out) to 1 (to their right).
	steer: number,
	-- 0 normally, rising to 1 as the rider's stamina is about to run out.
	tired: number,
	-- 0 normally, 1 once the egg is theirs.
	cheer: number,
	-- Seconds since the rider landed on the egg, or nil if that was a while ago.
	landed: number?,
	-- Seconds since the egg bumped into something, or nil if it has not lately.
	bumped: number?,
}

-- The R15 joints a pose turns, by their Motor6D names.
RiderPose.JOINTS = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}

-- The R6 joints RiderPose.toR6 turns, by their Motor6D names.
RiderPose.R6_JOINTS = { "RootJoint", "Neck", "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }

-- How long a landing squash lasts, and how long a stumble after a bump lasts (as long as the egg wobbles: see the
-- client's EggController).
RiderPose.LANDING_TIME = 0.32
RiderPose.STUMBLE_TIME = 0.6

local TAU = 2 * math.pi

-- Each leg: its name, which way it swings with the stride, how far through the stride it is, and which side it is
-- on (-1 left, 1 right). Each arm in the windmill and the tumble: its name, side, and how far behind the left one it
-- turns.
local LEGS = { { "Left", 1, 0, -1 }, { "Right", -1, math.pi, 1 } }
local WINDMILL_ARMS = { { "Left", -1, 0 }, { "Right", 1, 2.6 } }
local TUMBLE_ARMS = { { "Left", -1, 0 }, { "Right", 1, 2.4 } }

-- The roll speeds of the slowest eggs (Common) and the fastest (Eternal), studs a second.
local SLOWEST = Rarities.rollSpeedOf(1)
local FASTEST = Rarities.rollSpeedOf(#Rarities.Order)

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

-- How hard a rider runs on an egg rolling at `speed` studs a second: 0 on the slowest eggs, 1 on the fastest.
function RiderPose.paceOf(speed: number): number
	return clamp01((speed - SLOWEST) / math.max(1, FASTEST - SLOWEST))
end

-- Strides a second at `pace`: 2.4 at 0 (the slowest eggs), up to 3.2 at 1 (the fastest).
function RiderPose.strideRate(pace: number): number
	return 2.4 + 0.8 * clamp01(pace)
end

-- The stride's phase `deltaTime` seconds on, running at `pace`.
function RiderPose.advance(phase: number, pace: number, deltaTime: number): number
	return (phase + TAU * RiderPose.strideRate(pace) * deltaTime) % TAU
end

local function smoothstep(from: number, to: number, value: number): number
	local t = clamp01((value - from) / (to - from))
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- A pose with every joint at rest, or `into` cleared for reuse.
local function blank(into: Pose?): Pose
	local pose: Pose = into or {}
	for _, name in RiderPose.JOINTS do
		local joint = pose[name]
		if joint then
			for index = 1, 6 do
				joint[index] = 0
			end
		else
			pose[name] = { 0, 0, 0, 0, 0, 0 }
		end
	end
	return pose
end

-- Sets an arm's shoulder and elbow. `side` is -1 for the left arm and 1 for the right; `out` is how far it is raised
-- out to the side (radians, never across the body).
local function setArm(shoulder: { number }, elbow: { number }, side: number, forward: number, out: number, bend: number)
	shoulder[1] = forward
	shoulder[3] = side * math.max(0.05, out)
	elbow[1] = bend
end

-- The pose for one frame of riding. Pass `into` to reuse a pose table from an earlier frame.
function RiderPose.pose(state: State, into: Pose?): Pose
	local pose = blank(into)
	local root, waist, neck = pose.Root, pose.Waist, pose.Neck

	local phase, t = state.phase, state.time
	local s = math.sin(phase)
	local tired = clamp01(state.tired)
	local cheer = clamp01(state.cheer)
	local steer = math.clamp(state.steer, -1, 1)
	local pace = clamp01(state.pace)

	-- Landing: a quick squash, legs gathered under the body before the strides open up.
	local landing = 0
	if state.landed and state.landed < RiderPose.LANDING_TIME then
		landing = (1 - math.max(0, state.landed) / RiderPose.LANDING_TIME) ^ 2
	end
	-- Bumped: rocked back and forth with the egg, arms thrown out.
	local stumble, stumbleAt = 0, 0
	if state.bumped and state.bumped < RiderPose.STUMBLE_TIME then
		stumbleAt = math.max(0, state.bumped)
		stumble = (1 - stumbleAt / RiderPose.STUMBLE_TIME) ^ 2
	end

	-- How far the legs and arms swing: longer strides on faster eggs, shorter and sloppier when tired.
	local stride = (0.62 + 0.18 * pace) * (1 - 0.3 * tired) * (1 - landing)
	local armSwing = (0.85 + 0.15 * pace) * (1 - 0.25 * tired) * (1 - landing)

	-- Losing balance: a gentle sway all the time, a big unsteady one when tired.
	local sway = 0.035 * math.sin(t * 4.1)
		+ tired * (0.2 * math.sin(t * 6.3) + 0.06 * math.sin(t * 17.9))
		- 0.26 * stumble * math.sin(stumbleAt * 32)
	local rock = tired * 0.1 * math.sin(t * 9.7 + 1) + 0.32 * stumble * math.sin(stumbleAt * 15)

	-- The body: leaning into the run (more on faster eggs, hunched when tired, upright when cheering), into a turn,
	-- the hips turning with the leg that swings forward, and bobbing down as each foot lands.
	local lean = (-(0.2 + 0.1 * pace) - 0.12 * tired) * (1 - 0.35 * cheer) - 0.25 * landing
	root[1] = lean + rock
	root[2] = -0.13 * s * (1 - landing) - 0.2 * steer
	root[3] = sway - 0.26 * steer
	root[5] = (0.3 * math.abs(s) - 0.12) * (1 - landing) - 0.55 * landing - 0.35 * stumble

	-- The chest turns against the hips, as the arms swing, and straightens up out of a sway.
	waist[1] = -0.1 - 0.12 * tired + 0.08 * cheer
	waist[2] = 0.3 * s * (1 - landing)
	waist[3] = -0.4 * sway

	-- The head stays level and looks ahead (and a little where they are steering), while a tired rider stares down
	-- at their feet, and a bumped one is jolted back.
	neck[1] = -(root[1] + waist[1]) * 0.6 + tired * (-0.3 + 0.08 * math.sin(t * 13)) + 0.18 * cheer + 0.3 * stumble
	neck[2] = -(root[2] + waist[2]) * 0.85 - 0.2 * steer
	neck[3] = -(root[3] + waist[3]) * 0.6

	-- Legs: thighs swing (staying under the body however it leans), the heel kicks up just after a foot leaves the
	-- egg, and the knees soak up each landing.
	for _, leg in LEGS do
		local name, swing, offset, side = leg[1] :: string, leg[2] :: number, leg[3] :: number, leg[4] :: number
		local legPhase = phase + offset
		local kick = math.max(0, math.cos(legPhase + 0.5)) ^ 2
		local hip, knee, ankle = pose[name .. "Hip"], pose[name .. "Knee"], pose[name .. "Ankle"]
		hip[1] = -root[1] * 0.9 + stride * swing * s + 0.3 * kick * (1 - landing) + 0.55 * landing
		-- Feet a little apart for balance, staying on the egg when the body tips.
		hip[3] = side * 0.05 - root[3] * 0.7
		local bend = 0.28 + 0.15 * math.max(0, -math.cos(legPhase)) + (1.25 + 0.25 * pace) * kick * (1 - 0.2 * tired)
		knee[1] = -bend * (1 - landing) - 1.1 * landing - 0.5 * stumble
		ankle[1] = 0.12 - 0.55 * kick * (1 - landing) + 0.3 * landing
	end

	-- Arms: pumping against the legs with the elbows bent, held a little out for balance, the outside arm raised in
	-- a turn or a sway. Thrown up and out by a bump or a landing.
	local leftShoulder, leftElbow = pose.LeftShoulder, pose.LeftElbow
	local rightShoulder, rightElbow = pose.RightShoulder, pose.RightElbow
	local flung = 1.1 * stumble + 0.7 * landing
	local straighten = 1 - 0.6 * stumble
	setArm(
		leftShoulder,
		leftElbow,
		-1,
		0.1 - armSwing * s + 0.5 * stumble,
		0.18 + 0.45 * math.max(0, steer) + 2 * math.max(0, -sway) + flung,
		(1.35 - 0.35 * s) * straighten
	)
	setArm(
		rightShoulder,
		rightElbow,
		1,
		0.1 + armSwing * s + 0.5 * stumble,
		0.18 + 0.45 * math.max(0, -steer) + 2 * math.max(0, sway) + flung,
		(1.35 + 0.35 * s) * straighten
	)

	-- Tired: the arms give up pumping and windmill round to keep balance, not quite in step with each other.
	local windmill = smoothstep(0.3, 0.85, tired)
	if windmill > 0 then
		for _, arm in WINDMILL_ARMS do
			local name, side, shift = arm[1] :: string, arm[2] :: number, arm[3] :: number
			local shoulder, elbow = pose[name .. "Shoulder"], pose[name .. "Elbow"]
			local turn = t * 11 + shift
			shoulder[1] = lerp(shoulder[1], 0.4 + 1.4 * math.sin(turn), windmill)
			shoulder[3] = lerp(shoulder[3], side * (1.0 + 0.6 * math.cos(turn)), windmill)
			elbow[1] = lerp(elbow[1], 0.35, windmill)
		end
	end

	-- Cheering: the right fist punched up high, pumping.
	if cheer > 0 then
		rightShoulder[1] = lerp(rightShoulder[1], 2.75, cheer)
		rightShoulder[3] = lerp(rightShoulder[3], 0.3, cheer)
		rightElbow[1] = lerp(rightElbow[1], 0.2 + 0.6 * math.abs(math.sin(t * 7)), cheer)
	end

	return pose
end

-- Thrown off: tumbling through the air for `since` seconds, arms windmilling, legs kicking, arched back.
function RiderPose.tumble(time: number, since: number, into: Pose?): Pose
	local pose = blank(into)
	local arch = 1 - math.exp(-math.max(0, since) * 6)
	pose.Root[1] = 0.35 * arch + 0.12 * math.sin(time * 5)
	pose.Root[3] = 0.25 * math.sin(time * 7)
	pose.Waist[1] = 0.15 * arch
	pose.Neck[1] = 0.35 * arch
	pose.Neck[3] = 0.2 * math.sin(time * 9)

	for _, arm in TUMBLE_ARMS do
		local name, side, shift = arm[1] :: string, arm[2] :: number, arm[3] :: number
		local turn = time * 16 + shift
		pose[name .. "Shoulder"][1] = 0.8 + 1.6 * math.sin(turn)
		pose[name .. "Shoulder"][3] = side * (1.2 + 0.5 * math.cos(turn))
		pose[name .. "Elbow"][1] = 0.4 + 0.3 * math.sin(turn * 0.5)
	end
	for _, leg in LEGS do
		local name, shift = leg[1] :: string, leg[3] :: number
		local turn = time * 13 + shift
		pose[name .. "Hip"][1] = 0.5 + 0.8 * math.sin(turn)
		pose[name .. "Knee"][1] = -(0.7 + 0.3 * (1 + math.sin(turn + 1.3)))
		pose[name .. "Ankle"][1] = -0.3
	end
	return pose
end

-- Folds an R15 pose onto an R6 character, whose arms and legs do not bend: the body takes the waist's turn too, and
-- each arm and leg points part of the way its lower half would.
function RiderPose.toR6(pose: Pose, into: Pose?): Pose
	local r6: Pose = into or {}
	local function joint(name: string): { number }
		local values = r6[name]
		if values == nil then
			values = { 0, 0, 0, 0, 0, 0 }
			r6[name] = values
		end
		return values
	end

	local body, root, waist = joint("RootJoint"), pose.Root, pose.Waist
	for index = 1, 6 do
		body[index] = root[index] + waist[index]
	end
	table.move(pose.Neck, 1, 6, 1, joint("Neck"))
	for _, leg in LEGS do
		local side = leg[1] :: string
		local shoulder = joint(side .. " Shoulder")
		table.move(pose[side .. "Shoulder"], 1, 6, 1, shoulder)
		shoulder[1] += 0.3 * pose[side .. "Elbow"][1]
		local hip = joint(side .. " Hip")
		table.move(pose[side .. "Hip"], 1, 6, 1, hip)
		hip[1] += 0.3 * pose[side .. "Knee"][1]
	end
	return r6
end

return RiderPose
