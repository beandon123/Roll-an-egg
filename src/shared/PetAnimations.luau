--!strict
-- How pets move: for each skeleton (see PetModels.SKELETONS), a few named moves, each made of waves on its limbs.
-- The same moves drive the gallery (tools/egg-gallery) and rigged pets in the game (Client/Controllers/
-- PetAnimationController), so a pet moves the same way in both.
--
-- A wave turns or shifts one limb, in the design's own space (x to the pet's left, y up, z forward; turns in
-- radians about those axes, shifts in voxels):
--     value = base + spread * the pet's wing spread + size * shape(speed * time + shift)
-- where shape is "sin" (a plain wave), "lift" (only the upper half of one, eased in and out: a step or a hop) or
-- "bounce" (both halves upwards, rounded: a bob on every step). Winged pets fold their wings differently, so a design
-- gives how far its wings must turn out to be spread for flight (`wingSpread`), and the flying moves add it.
--
-- Moves are layered to look alive rather than mechanical: a limb's motion is usually several waves at speeds that
-- never quite line up, and what hangs off a limb (a head, a tail, an arm) follows it a little late. In the game,
-- PetAnimationController starts each pet at its own point in its moves, so a pen of pets never moves in lockstep, and
-- eases from one move into the next (see `blend`).

local PetAnimations = {}

export type Wave = {
	limb: string,
	-- "rx", "ry" or "rz" to turn about that axis; "px", "py" or "pz" to shift along it.
	channel: string,
	size: number,
	-- Radians per second.
	speed: number,
	shift: number?,
	base: number?,
	shape: string?,
	-- How much of the pet's wing spread to add: 1 for the left wing, -1 for the right.
	spread: number?,
	-- Scaled by the pet's height (as a shift for a pet 20 voxels tall), so every pet rises clear of the ground.
	tall: boolean?,
}

-- For each limb: { rx, ry, rz, px, py, pz }.
export type Pose = { [string]: { number } }

local CHANNELS = { rx = 1, ry = 2, rz = 3, px = 4, py = 5, pz = 6 }

local SHAPES: { [string]: (number) -> number } = {
	sin = math.sin,
	-- The upper half of a wave, eased in and out, so a foot leaves the ground and lands without a jerk.
	lift = function(x: number): number
		local s = math.max(0, math.sin(x))
		return s * s
	end,
	-- A bob on every half wave, rounded at the bottom (sine squared).
	bounce = function(x: number): number
		local s = math.sin(x)
		return s * s
	end,
}

local QUARTER = math.pi / 2

local function wave(limb: string, channel: string, size: number, speed: number, extra: { [string]: any }?): Wave
	local w: Wave = { limb = limb, channel = channel, size = size, speed = speed }
	if extra then
		w.shift, w.base, w.shape, w.spread, w.tall = extra.shift, extra.base, extra.shape, extra.spread, extra.tall
	end
	return w
end

local function joined(...: { Wave }): { Wave }
	local all = {}
	for _, list in { ... } do
		table.move(list, 1, #list, #all + 1, all)
	end
	return all
end

-- Standing still: breathing (the body rising and falling, the chest tipping with each breath), the weight shifting
-- slowly from side to side, and looking round (a slow turn with a quicker glance over it, a slow nod and a tilt of
-- the head, at speeds that never quite line up, so it never looks like a loop); and a lazy swish of the tail, with a
-- flick riding on it, if it has one.
local function idle(tail: boolean?): { Wave }
	local list = {
		wave("Body", "py", 0.12, 1.6),
		wave("Body", "rx", 0.012, 1.6, { shift = QUARTER }),
		wave("Body", "rz", 0.012, 0.5),
		wave("Head", "ry", 0.15, 0.6),
		wave("Head", "ry", 0.05, 1.7, { shift = 1 }),
		wave("Head", "rx", 0.035, 0.45, { shift = 2 }),
		wave("Head", "rx", 0.02, 1.6, { shift = QUARTER }),
		wave("Head", "rz", 0.03, 0.6, { shift = 0.5 }),
	}
	if tail ~= false then
		table.insert(list, wave("Tail", "ry", 0.18, 1.1))
		table.insert(list, wave("Tail", "ry", 0.05, 2.7, { shift = 1 }))
		table.insert(list, wave("Tail", "rx", 0.05, 0.8, { shift = 1.4 }))
	end
	return list
end

-- What a four-legged body does over its legs at a walk: it bobs on each footfall and pitches a little with it, and
-- rolls over the legs taking its weight (more with `sway`, for heavy pets); the head bobs against it (steadying
-- itself), sways a little and looks about now and then; the tail swings behind, lagging the body, and bounces.
local function carried(speed: number, bounce: number, sway: boolean?): { Wave }
	return {
		wave("Body", "py", bounce, speed, { shift = QUARTER, shape = "bounce" }),
		wave("Body", "rx", 0.015, speed * 2, { shift = 0.4 }),
		wave("Body", "rz", if sway then 0.045 else 0.02, speed),
		wave("Head", "rx", 0.05, speed * 2, { shift = QUARTER + 0.6 }),
		wave("Head", "ry", 0.05, speed, { shift = 1 }),
		wave("Head", "ry", 0.08, 0.5),
		wave("Tail", "ry", 0.3, speed, { shift = -1.2 }),
		wave("Tail", "rx", 0.06, speed * 2, { shift = 1 }),
	}
end

-- Four legs stepping in diagonal pairs: `a` how far each swings, `bounce` how high the body bobs.
local function fourLegs(a: number, speed: number, bounce: number, sway: boolean?): { Wave }
	return joined({
		wave("FrontLeftLeg", "rx", a, speed),
		wave("BackRightLeg", "rx", a, speed),
		wave("FrontRightLeg", "rx", -a, speed),
		wave("BackLeftLeg", "rx", -a, speed),
	}, carried(speed, bounce, sway))
end

-- A hop: springing up nose first and landing nose down, the hind legs kicking back, the tail flicking after.
local function hop(): { Wave }
	return {
		wave("Body", "py", 1.6, 6.5, { shape = "lift" }),
		wave("Body", "rx", -0.1, 6.5, { shift = -0.5 }),
		wave("FrontLeftLeg", "rx", -0.5, 6.5),
		wave("FrontRightLeg", "rx", -0.5, 6.5),
		wave("BackLeftLeg", "rx", 0.6, 6.5),
		wave("BackRightLeg", "rx", 0.6, 6.5),
		wave("Head", "rx", -0.08, 6.5),
		wave("Head", "ry", 0.08, 0.6),
		wave("Tail", "ry", 0.35, 5.2),
		wave("Tail", "rx", 0.12, 6.5, { shift = -0.8 }),
	}
end

-- Four legs that bend (the Beast, Strider, ThreeHeaded and Dragon skeletons) stepping in diagonal pairs: each upper
-- leg swings `a`, and its shin folds back by up to `bend` while that foot is lifted and carried forward, then
-- straightens to take the weight. With `jaw`, the jaw hangs a little open, working with each step.
local function jointedLegs(
	a: number,
	bend: number,
	speed: number,
	bounce: number,
	sway: boolean?,
	jaw: boolean?
): { Wave }
	local list = carried(speed, bounce, sway)
	if jaw then
		table.insert(list, wave("Jaw", "rx", 0.04, speed, { base = 0.04 }))
	end
	for _, leg in { { "FrontLeft", 1 }, { "BackRight", 1 }, { "FrontRight", -1 }, { "BackLeft", -1 } } do
		local name, side = leg[1], leg[2]
		table.insert(list, wave(name .. "Leg", "rx", a * side, speed))
		-- A foot moves forward while its leg's swing runs back towards the front: fold the shin then.
		table.insert(list, wave(name .. "Shin", "rx", bend, speed, { shift = -QUARTER * side, shape = "lift" }))
	end
	return list
end

-- Wings beating: `beat` radians per second, `stroke` how far each beat swings, `lift` the wings' resting angle up,
-- `sweep` how far they sweep back as they rise. Both wings swing together, mirrored; a smaller wave at twice the
-- speed makes each downstroke quicker than the recovery, and the wings twist a little through each stroke. With
-- `spread`, they are first turned out to be spread for flight.
local function beating(beat: number, stroke: number, lift: number, sweep: number, spread: boolean): { Wave }
	local out = if spread then 1 else 0
	local list = {
		wave("LeftWing", "rz", stroke, beat, { base = lift, spread = out }),
		wave("RightWing", "rz", -stroke, beat, { base = -lift, spread = -out }),
		wave("LeftWing", "rz", stroke * 0.2, beat * 2),
		wave("RightWing", "rz", -stroke * 0.2, beat * 2),
		wave("LeftWing", "rx", stroke * 0.12, beat, { shift = QUARTER }),
		wave("RightWing", "rx", stroke * 0.12, beat, { shift = QUARTER }),
	}
	if sweep ~= 0 then
		table.insert(list, wave("LeftWing", "ry", sweep, beat, { shift = QUARTER }))
		table.insert(list, wave("RightWing", "ry", -sweep, beat, { shift = QUARTER }))
	end
	return list
end

-- Two jointed legs striding (the Tyrant skeleton): each thigh swings `a`, and its shin folds back by up to `bend`
-- while that foot is lifted and carried forward, then straightens to take the weight. The body rocks over the
-- stepping leg and its hips twist, the tail swings against it, lagging, and the head bobs with each step and holds
-- steady against the twist.
local function stride(a: number, bend: number, speed: number, bounce: number): { Wave }
	local list = {
		wave("Body", "rz", 0.05, speed),
		wave("Body", "ry", 0.03, speed, { shift = QUARTER }),
		wave("Body", "rx", 0.015, speed * 2, { shift = 0.4 }),
		wave("Body", "py", bounce, speed, { shift = QUARTER, shape = "bounce" }),
		wave("Tail", "ry", 0.16, speed, { shift = math.pi - 0.8 }),
		wave("Tail", "rx", 0.04, speed * 2, { shift = 1 }),
		wave("Head", "rx", 0.05, speed * 2, { shift = QUARTER + 0.6 }),
		wave("Head", "ry", 0.08, speed, { shift = math.pi }),
		wave("Head", "ry", -0.03, speed, { shift = QUARTER }),
		wave("Head", "ry", 0.08, 0.5),
		wave("Jaw", "rx", 0.04, speed * 2, { base = 0.04 }),
		wave("LeftArm", "rx", 0.12, speed, { shift = -0.5 }),
		wave("RightArm", "rx", -0.12, speed, { shift = -0.5 }),
	}
	for _, leg in { { "Left", 1 }, { "Right", -1 } } do
		local name, side = leg[1], leg[2]
		table.insert(list, wave(name .. "Leg", "rx", a * side, speed))
		table.insert(list, wave(name .. "Shin", "rx", bend, speed, { shift = -QUARTER * side, shape = "lift" }))
	end
	return list
end

-- Two legs walking upright (the Biped skeleton): the arms swing against the legs, lagging a little and swinging
-- out on each step; the body rolls over the planted foot (`lean`), twists with the arms and bobs; the head holds
-- steady against the twist, nods with each step and looks about slowly.
local function biped(a: number, arm: number, speed: number, bounce: number, lean: number): { Wave }
	return {
		wave("LeftLeg", "rx", a, speed),
		wave("RightLeg", "rx", -a, speed),
		wave("LeftArm", "rx", -arm, speed, { shift = -0.3 }),
		wave("RightArm", "rx", arm, speed, { shift = -0.3 }),
		wave("LeftArm", "rz", 0.05, speed, { shape = "bounce" }),
		wave("RightArm", "rz", -0.05, speed, { shape = "bounce" }),
		wave("Body", "rz", lean, speed),
		wave("Body", "ry", 0.05, speed),
		wave("Body", "py", bounce, speed, { shift = QUARTER, shape = "bounce" }),
		wave("Head", "ry", -0.05, speed, { shift = 0.2 }),
		wave("Head", "ry", 0.1, 0.6),
		wave("Head", "rx", 0.03, speed * 2, { shift = QUARTER }),
	}
end

-- A big two-legged walker with knees and elbows (the Giant skeleton): walking as `biped` does, each shin folding
-- back by up to `bend` while its foot is carried forward, and each forearm hanging a little bent and bending more
-- as its arm swings forward, a beat behind it.
local function giant(a: number, arm: number, speed: number, bounce: number, lean: number, bend: number): { Wave }
	local list = biped(a, arm, speed, bounce, lean)
	for _, side in { { "Left", 1 }, { "Right", -1 } } do
		local name, s = side[1], side[2]
		table.insert(list, wave(name .. "Shin", "rx", bend, speed, { shift = -QUARTER * s, shape = "lift" }))
		table.insert(list, wave(name .. "Forearm", "rx", -0.14 * s, speed, { base = -0.14, shift = -0.7 }))
	end
	return list
end

-- A lizard's wiggle over its legs (the LowSlung skeleton): the body bends from side to side, the head and tail
-- swinging against it, the tail lagging.
local function wiggle(size: number, speed: number): { Wave }
	return {
		wave("Body", "ry", size, speed),
		wave("Head", "ry", -size * 1.2, speed, { shift = 0.3 }),
		wave("Tail", "ry", -size * 2, speed, { shift = -0.6 }),
	}
end

-- Eight tentacles each swaying and lifting a little, `size` radians, each out of step with the last.
local function writhe(speed: number, size: number): { Wave }
	local list = {}
	for i = 1, 8 do
		table.insert(list, wave("Tentacle" .. i, "rz", size, speed, { shift = i * 0.8 }))
		table.insert(list, wave("Tentacle" .. i, "rx", size * 0.6, speed * 0.7, { shift = i * 1.3 }))
	end
	return list
end

-- Hauling along on eight tentacles (the Kraken): the four lying on the ground (3 to 6: left, right, back left,
-- back right) reach forward, lifted a little, and drag back flat, in diagonal pairs like a four-legged gait; the
-- four raised ones (1 and 2 in front, 7 and 8 rearing over the back) lash, reach and curl in the air, each out of
-- step with the others; the body heaves up and surges forward with each pull and rolls from side to side, and the
-- mantle on top sways after it. Each tentacle is given by which way it runs out from the body ({ x, z }), so a
-- lift tips it up along its own length and a sweep swings it forward or back.
local function haul(speed: number): { Wave }
	local list = {
		wave("Body", "py", 0.6, speed, { shape = "bounce" }),
		wave("Body", "pz", 0.35, speed * 2, { shift = 0.4 }),
		wave("Body", "rx", 0.05, speed * 2, { shift = QUARTER }),
		wave("Body", "rz", 0.05, speed),
		wave("Head", "rx", 0.08, speed * 2, { shift = QUARTER - 0.7 }),
		wave("Head", "rz", 0.06, speed, { shift = -0.7 }),
		wave("Head", "ry", 0.08, 0.5),
		wave("Head", "py", 0.3, speed, { shape = "bounce", shift = -0.6 }),
	}
	local function lift(name: string, out: { number }, size: number, extra: { [string]: any })
		table.insert(list, wave(name, "rx", -out[2] * size, speed, extra))
		table.insert(list, wave(name, "rz", out[1] * size, speed, extra))
	end
	-- On the ground: a tentacle's forward reach is `reach` * sin(speed * time + phase), and it lifts while it
	-- reaches forward.
	for _, t in
		{
			{ "Tentacle3", { 1, 0.1 }, 0 },
			{ "Tentacle6", { -0.7, -0.7 }, 0 },
			{ "Tentacle4", { -1, -0.05 }, math.pi },
			{ "Tentacle5", { 0.7, -0.7 }, math.pi },
		}
	do
		local name, out, phase = t[1], t[2], t[3]
		local side = if out[1] > 0 then 1 else -1
		table.insert(list, wave(name, "ry", -side * 0.3, speed, { shift = phase }))
		lift(name, out, 0.22, { shift = phase + QUARTER, shape = "lift" })
	end
	-- In the air: lashing and reaching, each in its own rhythm.
	for i, t in
		{
			{ "Tentacle1", { 0.9, 0.43 } },
			{ "Tentacle2", { -0.9, 0.4 } },
			{ "Tentacle7", { 0.6, -0.8 } },
			{ "Tentacle8", { -0.6, -0.8 } },
		}
	do
		local name, out = t[1], t[2]
		lift(name, out, 0.16, { shift = i * 1.7 })
		table.insert(list, wave(name, "ry", 0.16, speed * 0.7, { shift = i * 2.3 }))
		table.insert(list, wave(name, "rx", 0.06, speed * 1.6, { shift = i * 0.9 }))
		table.insert(list, wave(name, "rz", 0.06, speed * 1.3, { shift = i * 1.4 }))
	end
	return list
end

-- The two side heads of a three-headed beast, each with a mind of its own: looking about out of step with the
-- other heads (a slow turn, a quicker glance, a nod and a tilt), now and then snapping at the air; and, at a walk
-- (`speed`), bobbing with the stride.
local function sideHeads(speed: number?): { Wave }
	local list = {}
	for _, head in { { "LeftHead", 1, 1.3 }, { "RightHead", -1, 3.4 } } do
		local name, side, phase = head[1], head[2], head[3]
		table.insert(list, wave(name, "ry", 0.22 * side, 0.55 + side * 0.06, { shift = phase }))
		table.insert(list, wave(name, "ry", 0.07, 1.9, { shift = phase * 1.7 }))
		table.insert(list, wave(name, "rx", 0.07, 0.7, { shift = phase + 2 }))
		table.insert(list, wave(name, "rz", 0.06 * side, 0.5, { shift = phase * 0.6 }))
		table.insert(list, wave(name, "rx", 0.15, 1.3 + side * 0.15, { shape = "lift", shift = phase * 2.3 }))
		if speed then
			table.insert(list, wave(name, "rx", 0.05, speed * 2, { shift = QUARTER + phase }))
		end
	end
	return list
end

-- Roaring with all three heads: the side heads thrown up and out, shaking, out of step with each other.
local function sideHeadsRoar(): { Wave }
	return {
		wave("LeftHead", "rx", 0.05, 15, { base = -0.22 }),
		wave("LeftHead", "ry", 0.06, 5, { base = 0.16 }),
		wave("RightHead", "rx", 0.05, 17, { base = -0.22, shift = 1 }),
		wave("RightHead", "ry", -0.06, 5.5, { base = -0.16, shift = 2 }),
	}
end

-- Beasts' roar: rearing back a little, head thrown up, jaws gaping, roaring.
local BEAST_ROAR = {
	wave("Body", "rx", 0.03, 8, { base = -0.08 }),
	wave("Head", "rx", 0.04, 9, { base = -0.3 }),
	wave("Head", "ry", 0.05, 2),
	wave("Jaw", "rx", 0.08, 9, { base = 0.6 }),
	wave("FrontLeftLeg", "rx", 0.02, 8, { base = 0.08 }),
	wave("FrontRightLeg", "rx", 0.02, 8, { base = 0.08 }),
	wave("BackLeftShin", "rx", 0.02, 8, { base = 0.12 }),
	wave("BackRightShin", "rx", 0.02, 8, { base = 0.12 }),
	wave("Tail", "ry", 0.4, 6),
}

PetAnimations.MOVES = {
	-- Four jointed legs, a jaw and a tail: the big hunters.
	Beast = {
		Idle = joined(idle(), {
			wave("Jaw", "rx", 0.05, 1.6, { base = 0.06 }),
		}),
		Walk = jointedLegs(0.42, 0.75, 6, 0.25, false, true),
		Stomp = jointedLegs(0.34, 0.65, 4.2, 0.35, true, true),
		Roar = BEAST_ROAR,
	},
	-- A beast with three heads (Cerberus): the middle one with its jaw, the other two each moving on its own.
	ThreeHeaded = {
		Idle = joined(idle(), sideHeads(), {
			wave("Jaw", "rx", 0.05, 1.6, { base = 0.06 }),
		}),
		Walk = joined(jointedLegs(0.42, 0.75, 6, 0.25, false, true), sideHeads(6)),
		Stomp = joined(jointedLegs(0.34, 0.65, 4.2, 0.35, true, true), sideHeads(4.2)),
		Roar = joined(BEAST_ROAR, sideHeadsRoar()),
	},
	-- Four long legs that bend at the knee (deer, camels, elephants, sauropods).
	Strider = {
		Idle = idle(),
		Walk = jointedLegs(0.4, 0.7, 5.5, 0.25),
		Stomp = jointedLegs(0.32, 0.6, 4, 0.35, true),
	},
	Quadruped = {
		Idle = idle(),
		Walk = fourLegs(0.45, 6, 0.25),
		Stomp = fourLegs(0.35, 4, 0.35, true),
		Hop = hop(),
	},
	LowSlung = {
		Idle = idle(),
		Walk = joined(fourLegs(0.6, 6, 0.25), wiggle(0.05, 6)),
		Crawl = joined(fourLegs(0.6, 4.5, 0.12), wiggle(0.08, 4.5)),
		Stomp = joined(fourLegs(0.5, 4, 0.3, true), wiggle(0.05, 4)),
		Hop = hop(),
	},
	Winged = {
		Idle = joined(idle(), {
			wave("LeftWing", "rz", 0.05, 1.6),
			wave("RightWing", "rz", -0.05, 1.6),
			wave("LeftWing", "rx", 0.03, 0.8, { shift = 1 }),
			wave("RightWing", "rx", 0.03, 0.8, { shift = 1 }),
		}),
		-- Walking with wings half-raised for balance, the head bobbing back and forth with each step.
		Walk = joined({
			wave("Body", "rz", 0.12, 6),
			wave("Body", "py", 0.3, 6, { shape = "bounce" }),
			wave("LeftLeg", "rx", 0.4, 6),
			wave("RightLeg", "rx", -0.4, 6),
			wave("Tail", "ry", 0.2, 6, { shift = QUARTER - 0.6 }),
			wave("Head", "rx", 0.06, 12, { shift = 0.6 }),
			wave("Head", "ry", 0.08, 0.6),
		}, beating(9.6, 0.25, 0.2, 0, false)),
		-- Flying on the spot, as if gliding forward through the air: up off the ground and tipped forward, wings
		-- beating in long strokes, legs tucked back, tail lifted level, head raised to look ahead, banking gently.
		Fly = joined({
			wave("Body", "py", 0.4, 5, { base = 6, tall = true, shift = math.pi }),
			wave("Body", "rx", 0.05, 5, { base = 0.35 }),
			wave("Body", "rz", 0.08, 1.2),
			wave("LeftLeg", "rx", 0.05, 5, { base = 1.1, shift = -0.8 }),
			wave("RightLeg", "rx", 0.05, 5, { base = 1.1, shift = -0.8 }),
			wave("Tail", "rx", 0.1, 5, { base = -0.35, shift = 1.5 }),
			wave("Tail", "ry", 0.1, 2.5),
			wave("Head", "rx", 0.04, 5, { base = -0.35, shift = math.pi }),
			wave("Head", "ry", 0.06, 0.7),
		}, beating(5, 0.7, 0.1, 0.18, true)),
		-- Hovering in place: held upright off the ground, rising a little with each quick, deep beat, legs hanging,
		-- tail fanning, head looking round.
		Hover = joined({
			wave("Body", "py", 0.6, 6.5, { base = 5, shift = math.pi, tall = true }),
			wave("Body", "rx", 0.04, 6.5, { base = -0.08 }),
			wave("LeftLeg", "rx", 0.08, 3.25, { base = 0.35, shift = -0.6 }),
			wave("RightLeg", "rx", 0.08, 3.25, { base = 0.35, shift = -0.6 }),
			wave("Tail", "rx", 0.12, 6.5, { base = -0.1, shift = 1 }),
			wave("Head", "rx", 0.05, 6.5),
			wave("Head", "ry", 0.15, 0.8),
		}, beating(6.5, 0.55, 0.15, 0.12, true)),
	},
	-- Four legs that bend at the knee and a pair of wings: a heavy tread on the ground, and in the air the same
	-- wingbeats as birds, legs folded up under it in flight and hanging, swaying, as it hovers.
	Dragon = {
		Idle = joined(idle(), {
			wave("LeftWing", "rz", 0.04, 1.6),
			wave("RightWing", "rz", -0.04, 1.6),
			wave("LeftWing", "ry", 0.03, 0.7, { shift = 1 }),
			wave("RightWing", "ry", -0.03, 0.7, { shift = 1 }),
		}),
		Walk = joined(jointedLegs(0.36, 0.65, 5, 0.25), beating(5, 0.06, 0, 0, false)),
		Stomp = joined(jointedLegs(0.3, 0.6, 4, 0.35, true), beating(4, 0.06, 0, 0, false)),
		Fly = joined({
			wave("Body", "py", 0.4, 4.5, { base = 6, tall = true, shift = math.pi }),
			wave("Body", "rx", 0.04, 4.5, { base = 0.15 }),
			wave("Body", "rz", 0.06, 1),
			wave("FrontLeftLeg", "rx", 0.05, 4.5, { base = -0.5, shift = -0.8 }),
			wave("FrontRightLeg", "rx", 0.05, 4.5, { base = -0.5, shift = -0.8 }),
			wave("FrontLeftShin", "rx", 0.05, 4.5, { base = 1.3, shift = -1.4 }),
			wave("FrontRightShin", "rx", 0.05, 4.5, { base = 1.3, shift = -1.4 }),
			wave("BackLeftLeg", "rx", 0.05, 4.5, { base = 0.7, shift = -0.8 }),
			wave("BackRightLeg", "rx", 0.05, 4.5, { base = 0.7, shift = -0.8 }),
			wave("BackLeftShin", "rx", 0.06, 4.5, { base = 0.6, shift = -1.4 }),
			wave("BackRightShin", "rx", 0.06, 4.5, { base = 0.6, shift = -1.4 }),
			wave("Tail", "rx", 0.08, 4.5, { base = -0.1, shift = 1.5 }),
			wave("Tail", "ry", 0.15, 2),
			wave("Head", "rx", 0.04, 4.5, { base = -0.15, shift = math.pi }),
			wave("Head", "ry", 0.06, 0.6),
		}, beating(4.5, 0.6, 0.1, 0.15, true)),
		Hover = joined({
			wave("Body", "py", 0.5, 5.5, { base = 5, shift = math.pi, tall = true }),
			wave("Body", "rx", 0.04, 5.5, { base = -0.05 }),
			wave("FrontLeftLeg", "rx", 0.06, 2.75, { base = 0.1, shift = -0.6 }),
			wave("FrontRightLeg", "rx", 0.06, 2.75, { base = 0.1, shift = -0.6 }),
			wave("FrontLeftShin", "rx", 0.08, 2.75, { base = 0.35, shift = -1.2 }),
			wave("FrontRightShin", "rx", 0.08, 2.75, { base = 0.35, shift = -1.2 }),
			wave("BackLeftLeg", "rx", 0.06, 2.75, { base = 0.3, shift = -0.6 }),
			wave("BackRightLeg", "rx", 0.06, 2.75, { base = 0.3, shift = -0.6 }),
			wave("BackLeftShin", "rx", 0.08, 2.75, { base = 0.25, shift = -1.2 }),
			wave("BackRightShin", "rx", 0.08, 2.75, { base = 0.25, shift = -1.2 }),
			wave("Tail", "ry", 0.2, 1.5),
			wave("Tail", "rx", 0.06, 5.5, { shift = 1 }),
			wave("Head", "ry", 0.15, 0.7),
			wave("Head", "rx", 0.04, 5.5),
		}, beating(5.5, 0.5, 0.15, 0.1, true)),
	},
	Biped = {
		Idle = joined(idle(false), {
			wave("LeftArm", "rz", 0.04, 1.6),
			wave("RightArm", "rz", -0.04, 1.6),
			wave("LeftArm", "rx", 0.03, 0.8, { shift = 0.5 }),
			wave("RightArm", "rx", 0.03, 0.8, { shift = 1.1 }),
		}),
		Walk = biped(0.35, 0.4, 6, 0.3, 0.05),
		Stomp = biped(0.3, 0.35, 4, 0.35, 0.06),
	},
	Giant = {
		Idle = joined(idle(false), {
			wave("LeftArm", "rz", 0.04, 1.6),
			wave("RightArm", "rz", -0.04, 1.6),
			wave("LeftArm", "rx", 0.03, 0.8, { shift = 0.5 }),
			wave("RightArm", "rx", 0.03, 0.8, { shift = 1.1 }),
			wave("LeftForearm", "rx", 0.04, 1.6, { base = -0.1, shift = 0.6 }),
			wave("RightForearm", "rx", 0.04, 1.6, { base = -0.1, shift = 0.9 }),
		}),
		Walk = giant(0.35, 0.4, 5, 0.3, 0.05, 0.55),
		Stomp = giant(0.3, 0.35, 3.6, 0.4, 0.06, 0.5),
	},
	-- Two strong legs, small arms and a long tail held out behind for balance (raptors): the body tips side to side
	-- over the stepping leg and its hips twist, the tail swings the other way, lagging, and the head bobs with each
	-- step and holds steady against the twist.
	Theropod = {
		Idle = joined(idle(), {
			wave("LeftArm", "rx", 0.08, 1.6),
			wave("RightArm", "rx", 0.08, 1.6, { shift = 0.4 }),
		}),
		Walk = {
			wave("LeftLeg", "rx", 0.5, 7),
			wave("RightLeg", "rx", -0.5, 7),
			wave("Body", "rz", 0.06, 7),
			wave("Body", "ry", 0.03, 7, { shift = QUARTER }),
			wave("Body", "py", 0.3, 7, { shift = QUARTER, shape = "bounce" }),
			wave("Tail", "ry", 0.18, 7, { shift = math.pi - 0.8 }),
			wave("Tail", "rx", 0.05, 14, { shift = 1 }),
			wave("Head", "rx", 0.06, 14, { shift = QUARTER + 0.6 }),
			wave("Head", "ry", -0.04, 7, { shift = QUARTER }),
			wave("Head", "ry", 0.08, 0.6),
			wave("LeftArm", "rx", 0.15, 7, { shift = -0.5 }),
			wave("RightArm", "rx", -0.15, 7, { shift = -0.5 }),
		},
		Stomp = {
			wave("LeftLeg", "rx", 0.38, 4),
			wave("RightLeg", "rx", -0.38, 4),
			wave("Body", "rz", 0.08, 4),
			wave("Body", "ry", 0.05, 4),
			wave("Body", "py", 0.45, 4, { shift = QUARTER, shape = "bounce" }),
			wave("Tail", "ry", 0.25, 4, { shift = math.pi - 0.8 }),
			wave("Tail", "rx", 0.06, 8, { shift = 1 }),
			wave("Head", "ry", 0.12, 4, { shift = math.pi }),
			wave("Head", "rx", 0.06, 8, { shift = QUARTER + 0.6 }),
			wave("LeftArm", "rx", 0.12, 4, { shift = -0.5 }),
			wave("RightArm", "rx", -0.12, 4, { shift = -0.5 }),
		},
		-- Rearing back with its head thrown up and shaking, arms spread, tail lashing.
		Roar = {
			wave("Body", "rx", 0.04, 9, { base = -0.18 }),
			wave("Head", "rx", 0.05, 18, { base = -0.4 }),
			wave("Head", "ry", 0.1, 7),
			wave("LeftArm", "rz", 0.06, 9, { base = 0.25 }),
			wave("RightArm", "rz", -0.06, 9, { base = -0.25 }),
			wave("Tail", "ry", 0.25, 3.5),
			wave("Tail", "rx", 0.06, 9, { base = 0.1 }),
		},
	},
	-- A theropod built to be huge, with knees and a jaw: a heavy stride, and a roar with its jaws flung open.
	Tyrant = {
		Idle = joined(idle(), {
			wave("Jaw", "rx", 0.05, 1.6, { base = 0.06 }),
			wave("LeftArm", "rx", 0.08, 1.6),
			wave("RightArm", "rx", 0.08, 1.6, { shift = 0.4 }),
		}),
		Walk = stride(0.36, 0.65, 5, 0.3),
		Stomp = stride(0.3, 0.6, 3.6, 0.45),
		-- Rearing back with its head thrown up and shaking, jaws gaping, arms spread, tail lashing.
		Roar = {
			wave("Body", "rx", 0.03, 9, { base = -0.14 }),
			wave("Head", "rx", 0.04, 18, { base = -0.32 }),
			wave("Head", "ry", 0.08, 6),
			wave("Jaw", "rx", 0.06, 18, { base = 0.55 }),
			wave("LeftArm", "rz", 0.06, 9, { base = 0.25 }),
			wave("RightArm", "rz", -0.06, 9, { base = -0.25 }),
			wave("LeftShin", "rx", 0.02, 9, { base = 0.1 }),
			wave("RightShin", "rx", 0.02, 9, { base = 0.1 }),
			wave("Tail", "ry", 0.22, 3.5),
			wave("Tail", "rx", 0.05, 9, { base = 0.08 }),
		},
	},
	-- Floats and swims: a gentle bob, the body rocking and bending a little from side to side, the head turning
	-- against it, fins sweeping and twisting, the tail beating up and down and swinging after the body.
	Swimmer = {
		Idle = {
			wave("Body", "py", 0.3, 1.2),
			wave("Body", "rx", 0.03, 1.2, { shift = QUARTER }),
			wave("Body", "ry", 0.03, 0.5),
			wave("Head", "ry", 0.05, 0.6, { shift = 1 }),
			wave("LeftFin", "rz", 0.15, 1.8, { base = 0.15 }),
			wave("RightFin", "rz", -0.15, 1.8, { base = -0.15 }),
			wave("LeftFin", "rx", 0.08, 1.8, { shift = QUARTER }),
			wave("RightFin", "rx", 0.08, 1.8, { shift = QUARTER }),
			wave("Tail", "rx", 0.12, 1.8, { shift = -0.8 }),
			wave("Tail", "ry", 0.06, 0.5, { shift = -1 }),
		},
		Swim = {
			wave("Body", "py", 0.5, 1.6),
			wave("Body", "rx", 0.06, 1.6),
			wave("Body", "ry", 0.04, 2.4),
			wave("LeftFin", "rz", 0.3, 2.4, { base = 0.25 }),
			wave("RightFin", "rz", -0.3, 2.4, { base = -0.25 }),
			wave("LeftFin", "rx", 0.12, 2.4, { shift = QUARTER }),
			wave("RightFin", "rx", 0.12, 2.4, { shift = QUARTER }),
			wave("Tail", "rx", 0.3, 2.4, { shift = -0.8 }),
			wave("Tail", "ry", 0.1, 2.4, { shift = -1.2 }),
			wave("Head", "rx", -0.05, 1.6),
			wave("Head", "ry", -0.04, 2.4, { shift = 0.4 }),
		},
	},
	-- Every tentacle writhes slowly, each a little out of step with the next; crawling, it hauls itself along (see
	-- `haul`).
	Tentacled = {
		Idle = joined({
			wave("Head", "rz", 0.02, 0.8),
			wave("Head", "rx", 0.02, 0.6, { shift = 1 }),
			wave("Head", "ry", 0.04, 0.4, { shift = 2 }),
			wave("Body", "py", 0.15, 1),
		}, writhe(1.1, 0.05)),
		Crawl = haul(2.4),
	},
	-- A sea serpent: a wave runs down its coils from the neck to the tail fan, both from side to side and up and
	-- down, each length a beat behind the one before, and swells towards the tail. Swimming, it rises off the
	-- ground and rides up and down with each stroke, rearing and dipping its neck, the head steadying itself
	-- against the neck's sway and looking about, the front fins rowing: sweeping back as they beat down, twisting
	-- through each stroke.
	Serpent = {
		Idle = {
			wave("Body", "py", 0.4, 0.8, { shape = "bounce" }),
			wave("Body", "ry", 0.02, 1, { shift = 0.9 }),
			wave("Segment1", "ry", 0.06, 1, { shift = -0.9 }),
			wave("Segment1", "rx", 0.02, 1, { base = 0.02, shift = -0.5 }),
			wave("Segment2", "ry", 0.08, 1, { shift = -1.8 }),
			wave("Segment2", "rx", 0.025, 1, { base = 0.025, shift = -1.4 }),
			wave("Tail", "ry", 0.11, 1, { shift = -2.7 }),
			wave("Tail", "rx", 0.04, 1, { base = 0.04, shift = -2.3 }),
			wave("Head", "ry", 0.08, 0.9),
			wave("Head", "ry", 0.04, 2.1, { shift = 1 }),
			wave("Head", "rx", 0.03, 0.6, { shift = 1 }),
			wave("Head", "rz", 0.03, 0.5, { shift = 2 }),
			wave("LeftFin", "rz", 0.08, 1.4, { base = 0.1 }),
			wave("RightFin", "rz", -0.08, 1.4, { base = -0.1 }),
			wave("LeftFin", "rx", 0.05, 1.4, { shift = QUARTER }),
			wave("RightFin", "rx", 0.05, 1.4, { shift = QUARTER }),
		},
		Swim = {
			wave("Body", "py", 0.8, 2, { base = 4 }),
			wave("Body", "rx", 0.035, 2, { shift = 0.3 }),
			wave("Body", "rz", 0.04, 1),
			wave("Body", "ry", 0.06, 2, { shift = 0.9 }),
			wave("Segment1", "ry", 0.16, 2, { shift = -0.9 }),
			wave("Segment1", "rx", 0.06, 2, { base = 0.04, shift = -0.6 }),
			wave("Segment2", "ry", 0.2, 2, { shift = -1.8 }),
			wave("Segment2", "rx", 0.08, 2, { base = 0.03, shift = -1.6 }),
			wave("Tail", "ry", 0.28, 2, { shift = -2.7 }),
			wave("Tail", "rx", 0.1, 2, { base = 0.06, shift = -2.6 }),
			wave("Head", "rx", 0.07, 2, { shift = 2.4 }),
			wave("Head", "ry", -0.05, 2, { shift = 1.3 }),
			wave("Head", "ry", 0.1, 0.9),
			wave("Head", "rz", 0.04, 1, { shift = 1 }),
			wave("LeftFin", "rz", 0.35, 2.4, { base = 0.2 }),
			wave("RightFin", "rz", -0.35, 2.4, { base = -0.2 }),
			wave("LeftFin", "rx", 0.15, 2.4, { shift = QUARTER }),
			wave("RightFin", "rx", 0.15, 2.4, { shift = QUARTER }),
			wave("LeftFin", "ry", 0.12, 2.4, { shift = math.pi }),
			wave("RightFin", "ry", -0.12, 2.4, { shift = math.pi }),
		},
	},
	ManyLegged = {
		Idle = {
			wave("Body", "py", 0.08, 1.6),
			wave("Head", "ry", 0.06, 0.8),
			wave("Head", "rx", 0.03, 0.5, { shift = 1 }),
			wave("Tail", "rx", 0.06, 1.2),
			wave("Tail", "ry", 0.06, 0.6, { shift = 2 }),
		},
		Walk = {},
	},
}

-- Each tentacle curls and uncurls a little out of step with the next.
for i = 1, 8 do
	table.insert(PetAnimations.MOVES.Tentacled.Idle, wave("Tentacle" .. i, "ry", 0.07, 0.9, { shift = i * 0.8 }))
end

-- Tripod walk: three legs swing forward, lifted, while the other three push back. The body rolls a little over each
-- tripod, and the tail (a scorpion's sting) sways after it.
do
	local walk = PetAnimations.MOVES.ManyLegged.Walk
	for _, leg in
		{
			{ "FrontLeftLeg", 1, 1 },
			{ "MiddleRightLeg", 1, -1 },
			{ "BackLeftLeg", 1, 1 },
			{ "FrontRightLeg", -1, -1 },
			{ "MiddleLeftLeg", -1, 1 },
			{ "BackRightLeg", -1, -1 },
		}
	do
		local name, group, side = leg[1], leg[2], leg[3]
		table.insert(walk, wave(name, "ry", 0.35 * group * side, 6))
		table.insert(walk, wave(name, "rz", 0.3 * side, 6, { shift = QUARTER * group, shape = "lift" }))
	end
	table.insert(walk, wave("Body", "py", 0.15, 6, { shift = QUARTER, shape = "bounce" }))
	table.insert(walk, wave("Body", "rz", 0.02, 6))
	table.insert(walk, wave("Head", "ry", 0.06, 6))
	table.insert(walk, wave("Tail", "rx", 0.08, 6, { shift = -0.6 }))
	table.insert(walk, wave("Tail", "ry", 0.08, 3, { shift = 1 }))
end

-- The names of the moves a skeleton has.
function PetAnimations.movesOf(skeleton: string): { string }
	local names = {}
	for name in PetAnimations.MOVES[skeleton] or {} do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- The move a pet uses to get about on the ground (or in water), from its skeleton and gait.
function PetAnimations.moveFor(skeleton: string, gait: string): string
	local moves = PetAnimations.MOVES[skeleton] or {}
	if moves[gait] then
		return gait
	end
	for _, name in { "Walk", "Swim", "Crawl" } do
		if moves[name] then
			return name
		end
	end
	return "Idle"
end

-- The move a pet shows off when nothing else says what it is doing: winged pets hover, the rest get about.
function PetAnimations.defaultMove(skeleton: string, gait: string): string
	local moves = PetAnimations.MOVES[skeleton] or {}
	if moves.Hover then
		return "Hover"
	end
	return PetAnimations.moveFor(skeleton, gait)
end

-- Where each limb is `time` seconds into a move: for each limb, { rx, ry, rz, px, py, pz }. `wingSpread` is the
-- pet's (see the top of this file), `height` its height in voxels.
function PetAnimations.pose(skeleton: string, move: string, time: number, wingSpread: number?, height: number?): Pose
	local pose: Pose = {}
	local moves = PetAnimations.MOVES[skeleton]
	for _, w in (moves and moves[move]) or {} do
		local limb = pose[w.limb]
		if limb == nil then
			limb = { 0, 0, 0, 0, 0, 0 }
			pose[w.limb] = limb
		end
		local shape = SHAPES[w.shape or "sin"]
		local value = (w.base or 0)
			+ (w.spread or 0) * (wingSpread or 0)
			+ w.size * shape(w.speed * time + (w.shift or 0))
		if w.tall then
			value *= (height or 20) / 20
		end
		local channel = CHANNELS[w.channel]
		limb[channel] += value
	end
	return pose
end

-- How long (seconds) a pet takes to ease from one move into the next.
PetAnimations.BLEND_TIME = 0.4

-- A pose part way from `from` to `to`: `t` from 0 (all `from`) to 1 (all `to`), eased in and out, so a pet settles
-- into a new move rather than snapping to it. A limb in only one of them eases from (or to) where it rests.
function PetAnimations.blend(from: Pose, to: Pose, t: number): Pose
	local k = math.clamp(t, 0, 1)
	k = k * k * (3 - 2 * k)
	local pose: Pose = {}
	for name, p in to do
		local a = from[name]
		local limb = table.create(6, 0)
		for i = 1, 6 do
			limb[i] = (if a then a[i] else 0) * (1 - k) + p[i] * k
		end
		pose[name] = limb
	end
	for name, a in from do
		if pose[name] == nil then
			local limb = table.create(6, 0)
			for i = 1, 6 do
				limb[i] = a[i] * (1 - k)
			end
			pose[name] = limb
		end
	end
	return pose
end

return PetAnimations
