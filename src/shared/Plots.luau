--!strict
-- Where the players' plots are at the hub, and what is where on them. The server builds the plots from this
-- (PlotService) and each client walks pets round the pens with it (PenController), so both agree without sending
-- positions.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- The hub is a plaza in front of the runway's start, shaped like a U: four plots across the back, their gates
-- facing the runway, and two down each side, their gates facing across the plaza. Each plot is one open, fenced
-- pen: its gate opens onto the plaza, pets roam all of it, and eggs can be put down anywhere in it. The pen starts
-- narrow and is made deeper, a level at a time, with the green upgrade button beside its gate; the plot has room
-- for the biggest pen.
--
-- Points on a plot are given as (inward, along): studs in from the plaza-side fence, and studs along the fence from
-- the middle of the gate. They mean the same spot on any plot, whichever way it faces, so saved positions (of eggs)
-- fit whichever plot a player gets.

local Economy = require(script.Parent.Config.Economy)
local Runway = require(script.Parent.Runway)

export type Row = "Back" | "Left" | "Right"

-- Where a plot is and which way it faces: the middle of its gate, the way "inward" points (from the gate into the
-- pen) and the way "along" points (along the fence), each a unit vector on the ground.
export type Frame = {
	row: Row,
	gateX: number,
	gateZ: number,
	inX: number,
	inZ: number,
	alongX: number,
	alongZ: number,
}

local Plots = {}

Plots.COUNT = 8
-- Four across the back, two down each side.
Plots.BACK_COUNT = 4
Plots.SIDE_COUNT = 2
-- The plaza between the two side rows, from x = -PLAZA_HALF_WIDTH to +PLAZA_HALF_WIDTH.
Plots.PLAZA_HALF_WIDTH = 70
-- How wide (along the fence) every pen is, and how deep (in from the plaza) at level 1 and per level after.
Plots.DEPTH = 84
Plots.START_WIDTH = 60
Plots.WIDTH_PER_LEVEL = 10
Plots.MAX_LEVEL = Economy.MAX_PEN_LEVEL
-- The room each plot has: deep enough for the biggest pen.
Plots.WIDTH = Plots.START_WIDTH + Plots.WIDTH_PER_LEVEL * (Plots.MAX_LEVEL - 1)
-- The gap between neighbouring plots, and between the back row and the back of the hub.
Plots.GAP = 10
-- Where the back row's gates are: the fence on the plaza side of the four back plots.
Plots.BACK_GATE_Z = -Runway.HUB_LENGTH + Plots.GAP + Plots.WIDTH
-- The front edge of the side rows: they stop short of the start zone, leaving room for the leaderboard.
Plots.SIDE_FRONT_Z = -50
-- Half the width of the gate in the fence on the plaza side.
Plots.GATE_HALF_WIDTH = 8
-- How far apart eggs on a plot must be, and from the fence.
Plots.EGG_SPACING = 8
Plots.EGG_MARGIN = 4
-- Where the green "bigger pen" button stands: in the plaza, just in front of the fence, beside the gate.
Plots.BUTTON_SPOT = { -6, 18 }

-- Every plot's frame. The back row comes first, left to right as seen from the start zone (from -x to +x), so the
-- first players to join get the plots facing the runway; then the left side and the right side, back to front.
local frames: { Frame } = {}
for slot = 1, Plots.BACK_COUNT do
	table.insert(frames, {
		row = "Back",
		gateX = (slot - (Plots.BACK_COUNT + 1) / 2) * (Plots.DEPTH + Plots.GAP),
		gateZ = Plots.BACK_GATE_Z,
		inX = 0,
		inZ = -1,
		alongX = 1,
		alongZ = 0,
	})
end
for _, side in { -1, 1 } do
	for slot = 1, Plots.SIDE_COUNT do
		table.insert(frames, {
			row = if side < 0 then "Left" else "Right",
			gateX = side * Plots.PLAZA_HALF_WIDTH,
			gateZ = Plots.SIDE_FRONT_Z - Plots.DEPTH / 2 - (Plots.SIDE_COUNT - slot) * (Plots.DEPTH + Plots.GAP),
			inX = side,
			inZ = 0,
			alongX = 0,
			alongZ = 1,
		})
	end
end
assert(#frames == Plots.COUNT, "Plots.COUNT does not match the rows")

-- How wide a pen of a level is (how deep it reaches in from the plaza).
function Plots.penWidth(level: number): number
	return Plots.START_WIDTH + Plots.WIDTH_PER_LEVEL * (math.clamp(level, 1, Plots.MAX_LEVEL) - 1)
end

-- How many eggs can hatch at once in a pen of a level, and how many pets it holds.
function Plots.eggCapacity(level: number): number
	return 1 + math.clamp(level, 1, Plots.MAX_LEVEL)
end

function Plots.petCapacity(level: number): number
	return 9 + math.clamp(level, 1, Plots.MAX_LEVEL)
end

function Plots.frame(index: number): Frame
	return frames[index]
end

-- Which row a plot is in: "Back", "Left" or "Right".
function Plots.rowOf(index: number): Row
	return frames[index].row
end

-- The turn about the vertical axis, in radians, that points a model's +X axis inward (from the gate into the pen):
-- build a plot's parts with X running inward and Z along the fence, then turn them by CFrame.Angles(0, yaw, 0).
function Plots.yaw(index: number): number
	local frame = frames[index]
	return math.atan2(-frame.inZ, frame.inX)
end

-- A point on a plot given as (inward, along), in world x and z.
function Plots.point(index: number, inward: number, along: number): (number, number)
	local frame = frames[index]
	return frame.gateX + frame.inX * inward + frame.alongX * along,
		frame.gateZ + frame.inZ * inward + frame.alongZ * along
end

-- The other way round: where a world point is on a plot, as (inward, along).
function Plots.toLocal(index: number, x: number, z: number): (number, number)
	local frame = frames[index]
	local dx, dz = x - frame.gateX, z - frame.gateZ
	return dx * frame.inX + dz * frame.inZ, dx * frame.alongX + dz * frame.alongZ
end

-- The middle of a plot's room (the biggest pen), on the ground.
function Plots.center(index: number): (number, number)
	return Plots.point(index, Plots.WIDTH / 2, 0)
end

-- A plot's whole room (the biggest pen) as a rectangle on the ground: its middle and its size along world x and z.
function Plots.rect(index: number): (number, number, number, number)
	local x, z = Plots.center(index)
	if frames[index].inX ~= 0 then
		return x, z, Plots.WIDTH, Plots.DEPTH
	end
	return x, z, Plots.DEPTH, Plots.WIDTH
end

-- Whether (inward, along) is inside a pen of a level, at least `margin` studs from its fence.
function Plots.inPen(level: number, inward: number, along: number, margin: number): boolean
	return inward >= margin and inward <= Plots.penWidth(level) - margin and math.abs(along) <= Plots.DEPTH / 2 - margin
end

-- The nearest point to (inward, along) inside a pen of a level, `margin` studs from its fence.
function Plots.clampToPen(level: number, inward: number, along: number, margin: number): (number, number)
	local halfDepth = Plots.DEPTH / 2 - margin
	return math.clamp(inward, margin, Plots.penWidth(level) - margin), math.clamp(along, -halfDepth, halfDepth)
end

-- The middle of a pen of a level, as (inward, along).
function Plots.penMiddle(level: number): (number, number)
	return Plots.penWidth(level) / 2, 0
end

-- Where a player appears at their plot: in the plaza just outside their gate.
function Plots.spawnPoint(index: number): (number, number)
	return Plots.point(index, -8, 0)
end

-- The area pets roam in a pen of a level, kept `margin` studs from the fence: world x and z ranges.
function Plots.roamArea(index: number, level: number, margin: number): (number, number, number, number)
	local width = Plots.penWidth(level)
	local inner, outer = margin, width - margin
	if inner > outer then
		-- A pet too big to wander stays in the middle.
		inner = width / 2
		outer = inner
	end
	local halfDepth = math.max(0, Plots.DEPTH / 2 - margin)
	local x0, z0 = Plots.point(index, inner, -halfDepth)
	local x1, z1 = Plots.point(index, outer, halfDepth)
	return math.min(x0, x1), math.max(x0, x1), math.min(z0, z1), math.max(z0, z1)
end

-- The hub must hold the plots: its size follows from them.
assert(
	Runway.HUB_WIDTH / 2 >= Plots.PLAZA_HALF_WIDTH + Plots.WIDTH + Plots.GAP,
	"Runway.HUB_WIDTH is too narrow for the side rows"
)
assert(
	Runway.HUB_WIDTH >= Plots.BACK_COUNT * (Plots.DEPTH + Plots.GAP) + Plots.GAP,
	"Runway.HUB_WIDTH is too narrow for the back row"
)
assert(
	Plots.SIDE_FRONT_Z - Plots.SIDE_COUNT * (Plots.DEPTH + Plots.GAP) + Plots.GAP >= Plots.BACK_GATE_Z + 40,
	"Runway.HUB_LENGTH is too short: the side rows crowd the back row's gates"
)

return Plots
