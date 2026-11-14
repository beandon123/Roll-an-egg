--!strict
-- Where the players' plots are at the hub, and where things go on them: the pen, its nests, and the gate.
-- The server builds the plots from this (PlotService) and each client walks pets round the pens with it
-- (PenController), so both agree without sending positions.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- The hub is a plaza in front of the runway's start, with four plots down each side. Each plot is a fenced pen:
-- its gate opens onto the plaza, nests line the plaza side, and pets roam the far side.

local Runway = require(script.Parent.Runway)

local Plots = {}

Plots.COUNT = 8
-- The plaza between the two rows of plots, from x = -PLAZA_HALF_WIDTH to +PLAZA_HALF_WIDTH.
Plots.PLAZA_HALF_WIDTH = 70
-- Each plot's size: across (x, away from the plaza) and along (z).
Plots.WIDTH = 100
Plots.DEPTH = 84
-- The gap between plots along a row.
Plots.GAP = 10
-- Half the width of the gate in the fence on the plaza side.
Plots.GATE_HALF_WIDTH = 8
-- The most nests a plot can hold, and how many a new player starts with.
Plots.MAX_NESTS = 10
Plots.START_NESTS = 2
-- How many pets roam a pen.
Plots.PEN_CAPACITY = 10

-- Nest spots, as (studs in from the plaza-side fence, studs along the plot from its middle). They sit either side
-- of the path in from the gate.
local NEST_SPOTS = {
	{ 10, -14 },
	{ 10, 14 },
	{ 10, -28 },
	{ 10, 28 },
	{ 24, -14 },
	{ 24, 14 },
	{ 24, -28 },
	{ 24, 28 },
	{ 38, -14 },
	{ 38, 14 },
}
-- Pets roam the part of the pen beyond the nests.
local ROAM_FROM = 50

-- Which side of the plaza a plot is on (-1 or 1), and its place in its row (0 to 3, from the back of the hub).
function Plots.sideOf(index: number): (number, number)
	local perSide = Plots.COUNT // 2
	local side = if index <= perSide then -1 else 1
	return side, (index - 1) % perSide
end

-- The middle of a plot, on the ground.
function Plots.center(index: number): (number, number)
	local side, row = Plots.sideOf(index)
	local x = side * (Plots.PLAZA_HALF_WIDTH + Plots.WIDTH / 2)
	local z = -Runway.HUB_LENGTH + Plots.GAP + (Plots.DEPTH + Plots.GAP) * row + Plots.DEPTH / 2
	return x, z
end

-- A point on a plot given as (studs in from the plaza-side fence, studs along from the middle).
function Plots.point(index: number, inward: number, along: number): (number, number)
	local side = Plots.sideOf(index)
	local _, z = Plots.center(index)
	return side * (Plots.PLAZA_HALF_WIDTH + inward), z + along
end

-- Where a nest sits on a plot.
function Plots.nestPoint(index: number, slot: number): (number, number)
	local spot = NEST_SPOTS[slot]
	return Plots.point(index, spot[1], spot[2])
end

-- Where a player appears at their plot: in the plaza just outside their gate.
function Plots.spawnPoint(index: number): (number, number)
	return Plots.point(index, -8, 0)
end

-- The area pets roam on a plot, kept `margin` studs from the fences: x and z ranges.
function Plots.roamArea(index: number, margin: number): (number, number, number, number)
	local side = Plots.sideOf(index)
	local _, z = Plots.center(index)
	local inner = Plots.PLAZA_HALF_WIDTH + ROAM_FROM + margin
	local outer = Plots.PLAZA_HALF_WIDTH + Plots.WIDTH - margin
	if inner > outer then
		-- A pet too big to wander stays in the middle of the roaming ground.
		inner = (inner + outer) / 2
		outer = inner
	end
	local halfDepth = math.max(0, Plots.DEPTH / 2 - margin)
	local x0, x1 = side * inner, side * outer
	return math.min(x0, x1), math.max(x0, x1), z - halfDepth, z + halfDepth
end

-- The hub must hold the plots: its size follows from them.
assert(Runway.HUB_WIDTH >= 2 * (Plots.PLAZA_HALF_WIDTH + Plots.WIDTH), "Runway.HUB_WIDTH is too narrow for the plots")
assert(
	Runway.HUB_LENGTH >= (Plots.COUNT // 2) * (Plots.DEPTH + Plots.GAP) + Plots.GAP,
	"Runway.HUB_LENGTH is too short for the plots"
)

return Plots
