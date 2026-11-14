--!strict
-- Where the players' plots are at the hub, and what is where on them. The server builds the plots from this
-- (PlotService) and each client walks pets round the pens with it (PenController), so both agree without sending
-- positions.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- The hub is a plaza in front of the runway's start, with four plots down each side. Each plot is one open, fenced
-- pen: its gate opens onto the plaza, pets roam all of it, and eggs can be put down anywhere in it. The pen starts
-- narrow and is made wider, a level at a time, with the green upgrade button beside its gate; the plot has room
-- for the biggest pen.
--
-- Points on a plot are given as (inward, along): studs in from the plaza-side fence, and studs along the plot from
-- its middle. They mean the same spot on any plot, so saved positions (of eggs) fit whichever plot a player gets.

local Economy = require(script.Parent.Config.Economy)
local Runway = require(script.Parent.Runway)

local Plots = {}

Plots.COUNT = 8
-- The plaza between the two rows of plots, from x = -PLAZA_HALF_WIDTH to +PLAZA_HALF_WIDTH.
Plots.PLAZA_HALF_WIDTH = 70
-- How deep (along the hub) every pen is, and how wide (in from the plaza) at level 1 and per level after.
Plots.DEPTH = 84
Plots.START_WIDTH = 60
Plots.WIDTH_PER_LEVEL = 10
Plots.MAX_LEVEL = Economy.MAX_PEN_LEVEL
-- The room each plot has: wide enough for the biggest pen.
Plots.WIDTH = Plots.START_WIDTH + Plots.WIDTH_PER_LEVEL * (Plots.MAX_LEVEL - 1)
-- The gap between plots along a row.
Plots.GAP = 10
-- Half the width of the gate in the fence on the plaza side.
Plots.GATE_HALF_WIDTH = 8
-- How far apart eggs on a plot must be, and from the fence.
Plots.EGG_SPACING = 8
Plots.EGG_MARGIN = 4
-- Where the green "bigger pen" button stands: in the plaza, just in front of the fence, beside the gate.
Plots.BUTTON_SPOT = { -6, 18 }

-- How wide a pen of a level is.
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

-- Which side of the plaza a plot is on (-1 or 1), and its place in its row (0 to 3, from the back of the hub).
function Plots.sideOf(index: number): (number, number)
	local perSide = Plots.COUNT // 2
	local side = if index <= perSide then -1 else 1
	return side, (index - 1) % perSide
end

-- The middle of a plot's room (the biggest pen), on the ground.
function Plots.center(index: number): (number, number)
	local side, row = Plots.sideOf(index)
	local x = side * (Plots.PLAZA_HALF_WIDTH + Plots.WIDTH / 2)
	local z = -Runway.HUB_LENGTH + Plots.GAP + (Plots.DEPTH + Plots.GAP) * row + Plots.DEPTH / 2
	return x, z
end

-- A point on a plot given as (inward, along), in world x and z.
function Plots.point(index: number, inward: number, along: number): (number, number)
	local side = Plots.sideOf(index)
	local _, z = Plots.center(index)
	return side * (Plots.PLAZA_HALF_WIDTH + inward), z + along
end

-- The other way round: where a world point is on a plot, as (inward, along).
function Plots.toLocal(index: number, x: number, z: number): (number, number)
	local side = Plots.sideOf(index)
	local _, centerZ = Plots.center(index)
	return side * x - Plots.PLAZA_HALF_WIDTH, z - centerZ
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
	local x0 = Plots.point(index, inner, 0)
	local x1 = Plots.point(index, outer, 0)
	local _, z = Plots.center(index)
	return math.min(x0, x1), math.max(x0, x1), z - halfDepth, z + halfDepth
end

-- The hub must hold the plots: its size follows from them.
assert(Runway.HUB_WIDTH >= 2 * (Plots.PLAZA_HALF_WIDTH + Plots.WIDTH), "Runway.HUB_WIDTH is too narrow for the plots")
assert(
	Runway.HUB_LENGTH >= (Plots.COUNT // 2) * (Plots.DEPTH + Plots.GAP) + Plots.GAP,
	"Runway.HUB_LENGTH is too short for the plots"
)

return Plots
