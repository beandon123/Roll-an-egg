--!strict
-- How pets move: for each skeleton (see PetModels.SKELETONS), a few named moves, each made of waves on its limbs.
-- The same moves drive the gallery (tools/egg-gallery) and rigged pets in the game (Client/Controllers/
-- PetAnimationController), so a pet moves the same way in both.
--
-- A wave turns or shifts one limb, in the design's own space (x to the pet's left, y up, z forward; turns in
-- radians about those axes, shifts in voxels):
--     value = base + spread * the pet's wing spread + size * shape(speed * time + shift)
-- where shape is "sin" (a plain wave), "lift" (only the upper half of one: a step or a hop) or "bounce" (both
-- halves upwards: a bob on every step). Winged pets fold their wings differently, so a design gives how far its wings
-- must turn out to be spread for flight (`wingSpread`), and the flying moves add it.

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
	lift = function(x: number): number
		return math.max(0, math.sin(x))
	end,
	bounce = function(x: number): number
		return math.abs(math.sin(x))
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

-- A gentle breath and a look round, for any pet standing still (with a swish of its tail, if it has one).
local function idle(tail: boolean?): { Wave }
	local list = {
		wave("Body", "py", 0.12, 1.6),
		wave("Head", "ry", 0.15, 0.7),
		wave("Head", "rx", 0.03, 1.6, { shift = QUARTER }),
	}
	if tail ~= false then
		table.insert(list, wave("Tail", "ry", 0.2, 1.2))
	end
	return list
end

-- Four legs stepping in diagonal pairs: `a` how far each swings, `bounce` how high the body bobs.
local function fourLegs(a: number, speed: number, bounce: number, sway: boolean?): { Wave }
	local list = {
		wave("FrontLeftLeg", "rx", a, speed),
		wave("BackRightLeg", "rx", a, speed),
		wave("FrontRightLeg", "rx", -a, speed),
		wave("BackLeftLeg", "rx", -a, speed),
		wave("Body", "py", bounce, speed, { shift = QUARTER, shape = "bounce" }),
		wave("Head", "rx", 0.05, speed, { shift = QUARTER }),
		wave("Tail", "ry", 0.35, speed * 0.8),
	}
	if sway then
		table.insert(list, wave("Body", "rz", 0.04, speed))
	end
	return list
end

local function hop(): { Wave }
	return {
		wave("Body", "py", 1.6, 6.5, { shape = "lift" }),
		wave("FrontLeftLeg", "rx", -0.5, 6.5),
		wave("FrontRightLeg", "rx", -0.5, 6.5),
		wave("BackLeftLeg", "rx", 0.6, 6.5),
		wave("BackRightLeg", "rx", 0.6, 6.5),
		wave("Head", "rx", -0.08, 6.5),
		wave("Tail", "ry", 0.35, 5.2),
	}
end

-- Wings beating: `beat` radians per second, `stroke` how far each beat swings, `lift` the wings' resting angle up,
-- `sweep` how far they sweep back as they rise. Both wings swing together, mirrored. With `spread`, they are first
-- turned out to be spread for flight.
local function beating(beat: number, stroke: number, lift: number, sweep: number, spread: boolean): { Wave }
	local out = if spread then 1 else 0
	local list = {
		wave("LeftWing", "rz", stroke, beat, { base = lift, spread = out }),
		wave("RightWing", "rz", -stroke, beat, { base = -lift, spread = -out }),
	}
	if sweep ~= 0 then
		table.insert(list, wave("LeftWing", "ry", sweep, beat, { shift = QUARTER }))
		table.insert(list, wave("RightWing", "ry", -sweep, beat, { shift = QUARTER }))
	end
	return list
end

local function joined(...: { Wave }): { Wave }
	local all = {}
	for _, list in { ... } do
		table.move(list, 1, #list, #all + 1, all)
	end
	return all
end

PetAnimations.MOVES = {
	Quadruped = {
		Idle = idle(),
		Walk = fourLegs(0.45, 6, 0.25),
		Stomp = fourLegs(0.35, 4, 0.35, true),
		Hop = hop(),
	},
	LowSlung = {
		Idle = idle(),
		Walk = fourLegs(0.6, 6, 0.25),
		Crawl = fourLegs(0.6, 4.5, 0.12),
		Stomp = fourLegs(0.5, 4, 0.3, true),
		Hop = hop(),
	},
	Winged = {
		Idle = joined(idle(), {
			wave("LeftWing", "rz", 0.05, 1.6),
			wave("RightWing", "rz", -0.05, 1.6),
		}),
		-- Walking with wings half-raised for balance.
		Walk = joined({
			wave("Body", "rz", 0.12, 6),
			wave("Body", "py", 0.3, 6, { shape = "bounce" }),
			wave("LeftLeg", "rx", 0.4, 6),
			wave("RightLeg", "rx", -0.4, 6),
			wave("Tail", "ry", 0.2, 6, { shift = QUARTER }),
		}, beating(9.6, 0.25, 0.2, 0, false)),
		-- Flying on the spot, as if gliding forward through the air: up off the ground and tipped forward, wings
		-- beating in long strokes, legs tucked back, tail lifted level, head raised to look ahead, banking gently.
		Fly = joined({
			wave("Body", "py", 0.4, 5, { base = 6, tall = true }),
			wave("Body", "rx", 0.05, 5, { base = 0.35 }),
			wave("Body", "rz", 0.08, 1.2),
			wave("LeftLeg", "rx", 0.05, 5, { base = 1.1 }),
			wave("RightLeg", "rx", 0.05, 5, { base = 1.1 }),
			wave("Tail", "rx", 0.1, 5, { base = -0.35, shift = 1.5 }),
			wave("Tail", "ry", 0.1, 2.5),
			wave("Head", "rx", 0.04, 5, { base = -0.35, shift = math.pi }),
		}, beating(5, 0.7, 0.1, 0.18, true)),
		-- Hovering in place: held upright off the ground, rising a little with each quick, deep beat, legs hanging,
		-- tail fanning, head looking round.
		Hover = joined({
			wave("Body", "py", 0.6, 6.5, { base = 5, shift = math.pi, tall = true }),
			wave("Body", "rx", 0.04, 6.5, { base = -0.08 }),
			wave("LeftLeg", "rx", 0.08, 3.25, { base = 0.35 }),
			wave("RightLeg", "rx", 0.08, 3.25, { base = 0.35 }),
			wave("Tail", "rx", 0.12, 6.5, { base = -0.1, shift = 1 }),
			wave("Head", "rx", 0.05, 6.5),
			wave("Head", "ry", 0.15, 0.8),
		}, beating(6.5, 0.55, 0.15, 0.12, true)),
	},
	Biped = {
		Idle = joined(idle(false), { wave("LeftArm", "rz", 0.04, 1.6), wave("RightArm", "rz", -0.04, 1.6) }),
		Walk = {
			wave("LeftLeg", "rx", 0.35, 6),
			wave("RightLeg", "rx", -0.35, 6),
			wave("LeftArm", "rx", -0.4, 6),
			wave("RightArm", "rx", 0.4, 6),
			wave("Body", "rz", 0.05, 6),
			wave("Body", "py", 0.3, 6, { shift = QUARTER, shape = "bounce" }),
			wave("Head", "ry", 0.12, 1.3),
		},
		Stomp = {
			wave("LeftLeg", "rx", 0.3, 4),
			wave("RightLeg", "rx", -0.3, 4),
			wave("LeftArm", "rx", -0.35, 4),
			wave("RightArm", "rx", 0.35, 4),
			wave("Body", "rz", 0.06, 4),
			wave("Body", "py", 0.35, 4, { shift = QUARTER, shape = "bounce" }),
			wave("Head", "ry", 0.12, 1.3),
		},
	},
	-- Floats and swims: a gentle bob, the body rocking, fins sweeping, the tail beating up and down.
	Swimmer = {
		Idle = {
			wave("Body", "py", 0.3, 1.2),
			wave("LeftFin", "rz", 0.15, 1.8, { base = 0.15 }),
			wave("RightFin", "rz", -0.15, 1.8, { base = -0.15 }),
			wave("Tail", "rx", 0.12, 1.8, { shift = -0.8 }),
		},
		Swim = {
			wave("Body", "py", 0.5, 1.6),
			wave("Body", "rx", 0.06, 1.6),
			wave("LeftFin", "rz", 0.3, 2.4, { base = 0.25 }),
			wave("RightFin", "rz", -0.3, 2.4, { base = -0.25 }),
			wave("Tail", "rx", 0.3, 2.4, { shift = -0.8 }),
			wave("Head", "rx", -0.05, 1.6),
		},
	},
	Tentacled = {
		Idle = {},
		Crawl = {
			wave("Head", "rz", 0.04, 1.2),
			wave("Body", "py", 0.3, 1.2, { shape = "bounce" }),
		},
	},
	-- A ripple runs down the coils from the neck to the tail fin.
	Serpent = {
		Idle = {
			wave("Segment1", "ry", 0.06, 1, { shift = -0.9 }),
			wave("Segment2", "ry", 0.08, 1, { shift = -1.8 }),
			wave("Tail", "ry", 0.11, 1, { shift = -2.7 }),
			wave("Head", "ry", 0.08, 0.9),
		},
		Swim = {
			wave("Segment1", "ry", 0.12, 2, { shift = -0.9 }),
			wave("Segment2", "ry", 0.16, 2, { shift = -1.8 }),
			wave("Tail", "ry", 0.22, 2, { shift = -2.7 }),
			wave("Head", "rx", 0.06, 2),
			wave("Head", "ry", 0.08, 0.9),
			wave("LeftFin", "rz", 0.25, 2.4, { base = 0.2 }),
			wave("RightFin", "rz", -0.25, 2.4, { base = -0.2 }),
		},
	},
	ManyLegged = {
		Idle = { wave("Body", "py", 0.08, 1.6), wave("Head", "ry", 0.06, 0.8), wave("Tail", "rx", 0.06, 1.2) },
		Walk = {},
	},
}

-- Each tentacle curls and uncurls a little out of step with the next.
for i = 1, 8 do
	local name = "Tentacle" .. i
	local moves = PetAnimations.MOVES.Tentacled
	table.insert(moves.Crawl, wave(name, "ry", 0.15, 1.8, { shift = i * 0.8 }))
	table.insert(moves.Crawl, wave(name, "rx", 0.08, 2.34, { shift = i * 1.04 }))
	table.insert(moves.Idle, wave(name, "ry", 0.07, 0.9, { shift = i * 0.8 }))
end

-- Tripod walk: three legs swing forward, lifted, while the other three push back.
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
	table.insert(walk, wave("Head", "ry", 0.06, 6))
	table.insert(walk, wave("Tail", "rx", 0.08, 6))
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

return PetAnimations
