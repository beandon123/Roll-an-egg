--!strict
-- How a player rolls on their training stick ("birling", the lumberjack sport): running on the spot on top of the
-- spinning roller, knees pumping, leaning forward, arms held out wide and see-sawing for balance.
--
-- `pose` gives each joint's turn, in radians about its parent part's own axes (X to the character's right, Y up,
-- Z backwards), as the client's TrainingController needs them to set each Motor6D's Transform. Those are the same
-- for R15 and R6 characters: the controller works out what each rig's joints need from them (R6 has no waist, knees
-- or elbows; its legs swing from the hips alone).
--
--     x  pitch: positive swings a hanging limb forwards (and tips the body backwards)
--     z  roll: positive swings a hanging limb out to the right
--     lift  (Root only) studs the whole body moves up
--
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.

export type JointPose = { x: number, y: number, z: number, lift: number }

local BirlingPose = {}

-- Every joint the pose turns, by its R15 name.
BirlingPose.JOINTS = {
	"Root",
	"Waist",
	"Neck",
	"LeftHip",
	"RightHip",
	"LeftKnee",
	"RightKnee",
	"LeftAnkle",
	"RightAnkle",
	"LeftShoulder",
	"RightShoulder",
	"LeftElbow",
	"RightElbow",
}

-- Strides a second, each leg: a quick jog on the spot, and a sprint during a 2x boost.
BirlingPose.STRIDE_RATE = 1.7
BirlingPose.BOOST_STRIDE_RATE = 2.6
-- The slow see-saw of the arms and body as the rider keeps their balance (cycles a second).
BirlingPose.BALANCE_RATE = 0.45

-- How far forward the rider leans (radians), how far out their arms are held (radians from hanging down) and how
-- far they see-saw.
local LEAN = 0.17
local ARMS_OUT = 1.3
local ARM_SEESAW = 0.24
-- The legs: thighs swing about a forward bias, and knees bend most as each leg swings forward.
local THIGH_BIAS = 0.3
local THIGH_SWING = 0.55
local KNEE_MIN = 0.3
local KNEE_BEND = 0.85
-- The body bobs with each footfall (twice per stride).
local BOB = 0.08

local function joint(x: number, z: number, weight: number): JointPose
	return { x = x * weight, y = 0, z = z * weight, lift = 0 }
end

-- The pose `stride` radians into the running cycle (one full turn = one stride of each leg) and `time` seconds in
-- (for the slower balance see-saw). `weight` from 0 to 1 eases the pose in as the rider steps on.
function BirlingPose.pose(stride: number, time: number, weight: number): { [string]: JointPose }
	local w = math.clamp(weight, 0, 1)
	local balance = math.sin(time * 2 * math.pi * BirlingPose.BALANCE_RATE)
	local wobble = math.sin(time * 2 * math.pi * BirlingPose.BALANCE_RATE * 1.9 + 1.3)
	local pose: { [string]: JointPose } = {}

	-- The whole body bobs with each footfall, a little lower on average so the knees can stay bent.
	pose.Root = { x = 0, y = 0, z = 0, lift = (BOB * math.cos(2 * stride) - BOB) * w }
	-- Leaning in, swaying against the arms, and the head kept level.
	pose.Waist = joint(-LEAN - 0.04 * math.cos(2 * stride), 0.08 * balance + 0.03 * wobble, w)
	pose.Neck = joint(LEAN * 0.7, -0.08 * balance, w)

	for _, side in { "Left", "Right" } do
		local phase = if side == "Left" then stride else stride + math.pi
		pose[side .. "Hip"] = joint(THIGH_BIAS + THIGH_SWING * math.sin(phase), 0, w)
		pose[side .. "Knee"] = joint(-(KNEE_MIN + KNEE_BEND * (0.5 + 0.5 * math.cos(phase))), 0, w)
		pose[side .. "Ankle"] = joint(0.25 * math.sin(phase - 0.8), 0, w)
	end

	-- Arms out wide, see-sawing: as one rises the other dips. A little pump with each stride.
	local pump = 0.06 * math.sin(stride)
	pose.RightShoulder = joint(0.25 + pump, ARMS_OUT + ARM_SEESAW * balance, w)
	pose.LeftShoulder = joint(0.25 - pump, -(ARMS_OUT - ARM_SEESAW * balance), w)
	pose.RightElbow = joint(0.35 + 0.1 * math.sin(2 * stride), 0, w)
	pose.LeftElbow = joint(0.35 + 0.1 * math.sin(2 * stride + 1), 0, w)
	return pose
end

return BirlingPose
