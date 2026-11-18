-- Makes everyone riding an egg run on top of it as it rolls (Shared/RiderPose works out the poses): quicker feet on
-- faster eggs, leaning into their steering, stumbling when the egg bumps into something, wobbling and windmilling
-- their arms as their stamina is about to run out, and pumping a fist once the egg is theirs. Riders thrown off (their
-- stamina gone) tumble through the air with their arms and legs flailing.
--
-- Players rolling on their training stick run the same way (TrainingController says who, how hard, and how far a
-- plank or girder rocks them as it turns): a steady run, and a flat-out sprint during a 2x boost.
--
-- Every device animates every rider it can see, every frame just before it is drawn. Riders are anchored, and
-- Roblox's own animations (the Animate script) set every joint's Motor6D.Transform each frame, so the pose goes into
-- each joint's C0 instead, which nothing else touches, cancelling out whatever those animations are doing: the joint
-- ends up exactly in the pose. It blends in from Roblox's pose when a rider gets on and back out when they get off,
-- and each joint's C0 is put back when they are done. Works on R15 and R6 characters.
--
-- How tired an egg rider looks comes from when their stamina will run out: the local player's from their own stamina
-- (UiState), anyone else's from the attribute the server keeps on their Player (StaminaMath.RUNS_OUT_AT).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local RiderPose = Load.shared("RiderPose")
local StaminaMath = Load.shared("StaminaMath")
local Tuning = Load.shared("Config", "Tuning")

local EggController = require(script.Parent.EggController)
local UiState = require(script.Parent.Parent.Ui.UiState)

local localPlayer = Players.LocalPlayer

local RiderAnimationController = {}

-- Seconds to blend into the run on getting on, and back to Roblox's own animations after getting off.
local BLEND_IN_TIME = 0.12
local BLEND_OUT_TIME = 0.25
-- How quickly steering, tiredness, cheering and the pace ease to where they are heading (the larger, the quicker).
local STEER_EASE = 10
local TIRED_EASE = 4
local CHEER_EASE = 5
local PACE_EASE = 6
-- Riders start to look tired this many seconds before their stamina runs out.
local TIRED_WARNING = 3
-- Sideways speed (studs a second) that counts as steering flat out.
local FULL_STEER_SPEED = Tuning.BASE_AGILITY
-- Riders further than this from the camera are left alone.
local ANIMATE_DISTANCE = 300
-- Seconds between looks for a character's joints while some are missing (they may still be loading).
local RESCAN_INTERVAL = 0.5
-- The usual height of a character's root part above the ground: RiderPose's shifts are for this size.
local NORMAL_STAND_HEIGHT = 3
-- A player TrainingController has not mentioned for this long (seconds) has got off their stick.
local STICK_HOLD = 0.1

-- A pose: see Shared/RiderPose.
type Pose = { [string]: { number } }

type Joint = {
	motor: Motor6D,
	-- The pose turns a limb about its parent part's axes; a Motor6D's offsets are in its C0's axes. These turn one
	-- into the other (C0's rotation, and its inverse).
	toJoint: CFrame,
	fromJoint: CFrame,
	-- The joint's own C0, put back when the rider is done, and the C0 last written here (as Roblox stores it).
	rest: CFrame,
	written: CFrame?,
}

type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	r6: boolean,
	-- The size of the character next to a usual one, for the pose's shifts.
	scale: number,
	joints: { [string]: Joint },
	count: number,
	scannedAt: number,
}

type Rider = {
	userId: number,
	-- The egg they are on (nil once they have left it), or whether they are on their training stick.
	eggId: number?,
	onStick: boolean,
	-- How much of the pose shows over Roblox's own animations, 0 to 1.
	weight: number,
	phase: number,
	-- Seconds of animation so far, for the sways and flails.
	time: number,
	pace: number,
	steer: number,
	tired: number,
	cheer: number,
	-- Studs the whole body is raised (a plank or girder rocks its rider down as it turns).
	lift: number,
	lastLateral: number?,
	-- When (on `clock`) they got on, and were thrown off (nil if not).
	landedAt: number,
	thrownAt: number?,
	-- The server time of the egg's last bump, while the rider stumbles from it.
	bumpedAt: number?,
	pose: Pose?,
	r6Pose: Pose?,
	rig: Rig?,
}

-- What TrainingController last said about someone on their stick.
type StickRide = { pace: number, lift: number, seenAt: number }

local riders: { [number]: Rider } = {}
-- In Studio, who has been reported in the Output as running (once each), to show the animation is at work.
local reported: { [number]: boolean } = {}
-- Seconds of frames so far: what landings, tumbles and looks for joints are timed by.
local clock = 0
-- Who is on which egg this frame (filled by visitRider), and who is on their training stick.
local onEgg: { [number]: any } = {}
local onStick: { [number]: StickRide } = {}

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Eases `current` towards `target`, `rate` being how quick.
local function ease(current: number, target: number, rate: number, deltaTime: number): number
	return target + (current - target) * math.exp(-rate * deltaTime)
end

local function findJoints(rig: Rig)
	local wanted = if rig.r6 then RiderPose.R6_JOINTS else RiderPose.JOINTS
	for _, descendant in rig.character:GetDescendants() do
		if descendant:IsA("Motor6D") and rig.joints[descendant.Name] == nil and table.find(wanted, descendant.Name) then
			local rotation = descendant.C0.Rotation
			rig.joints[descendant.Name] = {
				motor = descendant,
				toJoint = rotation:Inverse(),
				fromJoint = rotation,
				rest = descendant.C0,
				written = nil,
			}
			rig.count += 1
		end
	end
	rig.scannedAt = clock
end

-- The character's joints, found once and looked for again while some are missing.
local function rigOf(rider: Rider): Rig?
	local player = Players:GetPlayerByUserId(rider.userId)
	local character = player and player.Character
	if character == nil then
		return nil
	end
	local rig = rider.rig
	if rig == nil or rig.character ~= character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if humanoid == nil or root == nil or not root:IsA("BasePart") then
			return nil
		end
		local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
		local scale = if r6 then 1 else (humanoid.HipHeight + root.Size.Y / 2) / NORMAL_STAND_HEIGHT
		rig = {
			character = character,
			humanoid = humanoid,
			root = root,
			r6 = r6,
			scale = if scale > 0 then scale else 1,
			joints = {},
			count = 0,
			scannedAt = 0,
		}
		rider.rig = rig
		findJoints(rig)
	end
	local found = rig :: Rig
	local wanted = if found.r6 then #RiderPose.R6_JOINTS else #RiderPose.JOINTS
	if found.count < wanted and clock - found.scannedAt >= RESCAN_INTERVAL then
		findJoints(found)
	end
	return found
end

-- When the rider's stamina will run out (server time), if it is running down.
local function runsOutAt(userId: number): number?
	if userId == localPlayer.UserId then
		local stamina = UiState.staminaState
		if stamina == nil then
			return nil
		end
		return StaminaMath.runsOutAt(stamina.value, stamina.time, stamina.rate)
	end
	local player = Players:GetPlayerByUserId(userId)
	local value = player and player:GetAttribute(StaminaMath.RUNS_OUT_AT)
	return if typeof(value) == "number" then value else nil
end

local function newRider(userId: number): Rider
	return {
		userId = userId,
		eggId = nil,
		onStick = false,
		weight = 0,
		-- Riders do not all step in time.
		phase = (userId * 2.399) % (2 * math.pi),
		time = 0,
		pace = 0,
		steer = 0,
		tired = 0,
		cheer = 0,
		lift = 0,
		lastLateral = nil,
		landedAt = clock,
		thrownAt = nil,
		bumpedAt = nil,
		pose = nil,
		r6Pose = nil,
		rig = nil,
	}
end

local function visitRider(userId: number, egg)
	onEgg[userId] = egg
end

-- Starts a fresh ride: on an egg (`eggId`), or on the training stick.
local function getOn(rider: Rider, eggId: number?)
	rider.eggId = eggId
	rider.onStick = eggId == nil
	rider.landedAt = clock
	rider.thrownAt = nil
	rider.bumpedAt = nil
	rider.lastLateral = nil
	rider.steer = 0
end

-- Keeps a rider's state up to date with the egg they are on.
local function follow(rider: Rider, egg, now: number, deltaTime: number)
	if rider.eggId ~= egg.id then
		getOn(rider, egg.id)
	end
	rider.pace = RiderPose.paceOf(egg.spec.rollSpeed)
	rider.lift = 0

	-- Steering, from how fast the egg is moving across the runway. Riders face down it, so their right is towards
	-- -lateral.
	local sideways = 0
	if rider.lastLateral ~= nil and deltaTime > 0 then
		sideways = -(egg.lateral - rider.lastLateral) / deltaTime
	end
	rider.lastLateral = egg.lateral
	rider.steer = ease(rider.steer, math.clamp(sideways / FULL_STEER_SPEED, -1, 1), STEER_EASE, deltaTime)

	local outAt = if egg.ownerUserId == rider.userId then nil else runsOutAt(rider.userId)
	local tired = if outAt then 1 - math.clamp((outAt - now) / TIRED_WARNING, 0, 1) else 0
	rider.tired = ease(rider.tired, tired, TIRED_EASE, deltaTime)
	rider.cheer = ease(rider.cheer, if egg.ownerUserId == rider.userId then 1 else 0, CHEER_EASE, deltaTime)

	if egg.wobbleAt ~= nil then
		rider.bumpedAt = egg.wobbleAt
	end
end

-- Keeps a rider's state up to date on their training stick: no steering or stamina to run out there, just the pace
-- (a sprint in a boost) and the rocking of the roller.
local function followStick(rider: Rider, stick: StickRide, deltaTime: number)
	if not rider.onStick then
		getOn(rider, nil)
		rider.pace = stick.pace
	end
	rider.pace = ease(rider.pace, stick.pace, PACE_EASE, deltaTime)
	rider.lift = stick.lift
	rider.steer = ease(rider.steer, 0, STEER_EASE, deltaTime)
	rider.tired = ease(rider.tired, 0, TIRED_EASE, deltaTime)
	rider.cheer = ease(rider.cheer, 0, CHEER_EASE, deltaTime)
end

-- The rider has just got off: thrown off if the egg is cracking under them (they ran out of stamina).
local function getOff(rider: Rider)
	local egg = rider.eggId and EggController.GetEgg(rider.eggId)
	if egg and egg.cracking and rider.thrownAt == nil then
		rider.thrownAt = clock
	end
	rider.eggId = nil
	rider.onStick = false
	rider.lastLateral = nil
end

-- Sets the rider's joints to their pose, `weight` of the way from where Roblox's animations put them.
--
-- A joint places its limb at Part0 * C0 * Transform * C1:Inverse(). Roblox's animations own Transform (they set it
-- every frame), so the pose goes into C0, with their Transform cancelled out: C0 = rest * pose * Transform:Inverse().
local function apply(rig: Rig, pose: Pose, weight: number)
	local scale = rig.scale
	for name, joint in rig.joints do
		local motor = joint.motor
		if motor.Parent == nil then
			rig.joints[name] = nil
			rig.count -= 1
			continue
		end
		local p = pose[name]
		if p == nil then
			continue
		end
		if joint.written and motor.C0 ~= joint.written then
			-- Something else moved the joint (the character was rescaled): that is where it rests now.
			joint.rest = motor.C0
		end
		local animated = motor.Transform
		local target = joint.toJoint
			* CFrame.new(p[4] * scale, p[5] * scale, p[6] * scale)
			* CFrame.fromEulerAnglesYXZ(p[1], p[2], p[3])
			* joint.fromJoint
		if weight < 1 then
			target = animated:Lerp(target, weight)
		end
		motor.C0 = joint.rest * target * animated:Inverse()
		-- Read back, as Roblox rounds what it stores.
		joint.written = motor.C0
	end
end

-- Puts every joint of the rider's character back as it was.
local function release(rider: Rider)
	local rig = rider.rig
	if rig == nil then
		return
	end
	for _, joint in rig.joints do
		if joint.written and joint.motor.C0 == joint.written then
			joint.motor.C0 = joint.rest
		end
		joint.written = nil
	end
end

local function animate(rider: Rider, eye: Vector3?)
	local rig = rigOf(rider)
	if rig == nil or rig.humanoid.Health <= 0 then
		return
	end
	if eye and (rig.root.Position - eye).Magnitude > ANIMATE_DISTANCE then
		return
	end
	if RunService:IsStudio() and not reported[rider.userId] then
		reported[rider.userId] = true
		local wanted = if rig.r6 then #RiderPose.R6_JOINTS else #RiderPose.JOINTS
		print(
			`[Riding animation] {rig.character.Name} is running on {if rider.onStick
				then "their training stick"
				else "an egg"}` .. ` ({if rig.r6 then "R6" else "R15"}, {rig.count} of {wanted} joints)`
		)
	end

	local pose
	if rider.thrownAt then
		pose = RiderPose.tumble(rider.time, clock - rider.thrownAt, rider.pose)
	else
		local now = Workspace:GetServerTimeNow()
		pose = RiderPose.pose({
			phase = rider.phase,
			time = rider.time,
			pace = rider.pace,
			steer = rider.steer,
			tired = rider.tired,
			cheer = rider.cheer,
			landed = clock - rider.landedAt,
			bumped = if rider.bumpedAt then now - rider.bumpedAt else nil,
		}, rider.pose)
		-- The lift is in studs whatever the character's size (the pose's shifts are scaled to it).
		pose.Root[5] += rider.lift / rig.scale
	end
	rider.pose = pose
	if rig.r6 then
		rider.r6Pose = RiderPose.toR6(pose, rider.r6Pose)
		apply(rig, rider.r6Pose :: Pose, smoothstep(rider.weight))
	else
		apply(rig, pose, smoothstep(rider.weight))
	end
end

local function step(deltaTime: number)
	clock += deltaTime
	table.clear(onEgg)
	EggController.VisitRiders(visitRider)
	for userId, stick in onStick do
		if clock - stick.seenAt > STICK_HOLD then
			onStick[userId] = nil
		end
	end

	local now = Workspace:GetServerTimeNow()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil

	for userId in onEgg do
		if riders[userId] == nil then
			riders[userId] = newRider(userId)
		end
	end
	for userId in onStick do
		if riders[userId] == nil then
			riders[userId] = newRider(userId)
		end
	end

	for userId, rider in riders do
		local egg = onEgg[userId]
		local stick = onStick[userId]
		if egg and rider.thrownAt == nil then
			follow(rider, egg, now, deltaTime)
		elseif stick and rider.thrownAt == nil then
			followStick(rider, stick, deltaTime)
		elseif (rider.eggId ~= nil and egg == nil) or (rider.onStick and stick == nil) then
			getOff(rider)
		end

		-- Shown while on an egg or a stick, or tumbling off an egg; fading back to Roblox's own animations otherwise.
		local riding = egg ~= nil or stick ~= nil
		local tumbling = rider.thrownAt ~= nil and clock - rider.thrownAt < Tuning.STUN_TIME
		if rider.thrownAt and not tumbling and riding then
			-- Thrown off one egg and already on another (the server says when): back to running.
			rider.thrownAt = nil
		end
		local showing = (riding and rider.thrownAt == nil) or tumbling
		local blend = if showing then BLEND_IN_TIME else BLEND_OUT_TIME
		rider.weight = math.clamp(rider.weight + (if showing then 1 else -1) * deltaTime / blend, 0, 1)
		if rider.weight <= 0 and not showing then
			release(rider)
			riders[userId] = nil
			continue
		end

		rider.time += deltaTime
		rider.phase = RiderPose.advance(rider.phase, rider.pace, deltaTime)
		animate(rider, eye)
	end
end

----------------------------------------------------------------------------------------------------------------
-- For other controllers

-- The local player has just been thrown off their egg (out of stamina): they tumble through the air until they get
-- their balance back.
function RiderAnimationController.Tumble(userId: number)
	local rider = riders[userId]
	if rider == nil then
		rider = newRider(userId)
		riders[userId] = rider
	end
	rider.thrownAt = clock
	rider.eggId = nil
	rider.onStick = false
	rider.lastLateral = nil
end

-- A player is rolling on their training stick this frame (TrainingController calls this every frame while they
-- are): running at `pace` (as in Shared/RiderPose), raised `lift` studs (negative when the roller rocks them down).
function RiderAnimationController.SetStickRider(userId: number, pace: number, lift: number)
	local stick = onStick[userId]
	if stick == nil then
		onStick[userId] = { pace = pace, lift = lift, seenAt = clock }
	else
		stick.pace, stick.lift, stick.seenAt = pace, lift, clock
	end
end

function RiderAnimationController.Init()
	-- Last thing before the frame is drawn: after the camera, and after EggController has put riders on their eggs.
	RunService:BindToRenderStep("RollAnEgg_RiderPose", Enum.RenderPriority.Last.Value, step)
	Players.PlayerRemoving:Connect(function(player)
		riders[player.UserId] = nil
		onStick[player.UserId] = nil
	end)
end

return RiderAnimationController
