--!strict
-- Where the hub's stations are, and the terraced cliffs round the hub. MapService builds the stations and the
-- cliffs from this, and anything that needs to know where a station is (opening its panel, closing it when the
-- player walks away) reads it from here, never from map parts. The players' plots are laid out in Shared/Plots.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Same coordinates as Shared/Runway: the runway starts at z = 0 and runs toward +z; the hub is behind it, at
-- negative z, centred on x = 0. Positions are on the hub's walking surface (Runway.BASE_Y) unless noted.
--
-- Seen from above, with the runway leaving at the bottom:
--
--     x = -220                                                     x = +220
--        +------------------------------------------------------------+  z = -440
--        |  [ plot 1 ]   [ plot 2 ]   [ plot 3 ]   [ plot 4 ]          |
--        |                        fuse machine                        |  z = -290 (back gates)
--        | [ plot 5 ]                spawn                [ plot 7 ] |
--        |               Trails               Sell                    |
--        | [ plot 6 ]                                     [ plot 8 ] |
--        +--------------------[  START ZONE  ]------------------------+  z = 0
--                             |    runway    |
--
-- Terraced cliffs ring the hub on three sides; the way out is the runway.

local Runway = require(script.Parent.Runway)

export type Point = { x: number, z: number }

-- A rectangle on the ground, by its centre and size.
export type Rect = { x: number, z: number, sizeX: number, sizeZ: number }

export type Station = {
	key: string,
	-- Shown on the stall's sign and its prompt.
	name: string,
	x: number,
	z: number,
	-- Unit direction the front of the station faces.
	facing: Point,
}

-- One block of the terraced cliffs: a step of stone with grass on top, seen from above as a rectangle turned to
-- follow the ring round the hub.
export type Terrace = {
	-- The middle of its footprint on the ground.
	x: number,
	z: number,
	-- Turn about the vertical axis, in radians (CFrame.Angles(0, yaw, 0)): the block's X axis then runs along the
	-- ring and its Z axis points out, away from the hub.
	yaw: number,
	-- Its size along the ring and outward, in studs.
	length: number,
	depth: number,
	-- How far its top is above the hub's ground.
	height: number,
	-- 1 for the lowest step, at the foot of the cliffs; the top step is TERRACE_TIERS.
	tier: number,
	-- How far its inner edge is out from the foot of the cliffs.
	offset: number,
	-- Seeds its details (grass hanging over its edge, what grows on top), so every server builds the same cliffs.
	seed: number,
}

local HubLayout = {}

local HALF_WIDTH = Runway.HUB_WIDTH / 2
local LENGTH = Runway.HUB_LENGTH

HubLayout.HALF_WIDTH = HALF_WIDTH
HubLayout.LENGTH = LENGTH

-- The walkable hub ground. Invisible walls run round its edge, leaving only the runway open.
HubLayout.GROUND = { x = 0, z = -LENGTH / 2, sizeX = HALF_WIDTH * 2, sizeZ = LENGTH } :: Rect

----------------------------------------------------------------------------------------------------------------
-- Stations: in the plaza between the plots, on the way from the plots to the runway.

HubLayout.STATIONS = {
	-- Buy trails that boost Max Stamina. Level with the gap between the two side pens, so it blocks neither gate.
	Trails = { key = "Trails", name = "Trails", x = -44, z = -139, facing = { x = 1, z = 0 } },
	-- Sell eggs you do not want.
	Sell = { key = "Sell", name = "Sell", x = 44, z = -139, facing = { x = -1, z = 0 } },
	-- Fuse three of the same pet into that pet's egg: the centrepiece in front of the back row of pens.
	Fuse = { key = "Fuse", name = "Fuse Machine", x = 0, z = -252, facing = { x = 0, z = 1 } },
} :: { [string]: Station }

-- Radius of ground each station stands on (for keeping other things clear of it).
HubLayout.STATION_RADIUS = 16
-- How close a player must be to use a station's prompt.
HubLayout.STATION_REACH = 12
-- How far from a station a player can walk before its panel closes by itself.
HubLayout.STATION_CLOSE_DISTANCE = 26

----------------------------------------------------------------------------------------------------------------
-- Geometry helpers

function HubLayout.bounds(rect: Rect): (number, number, number, number)
	return rect.x - rect.sizeX / 2, rect.x + rect.sizeX / 2, rect.z - rect.sizeZ / 2, rect.z + rect.sizeZ / 2
end

-- Distance from a point to the nearest point of a rectangle (0 inside it).
function HubLayout.distanceToRect(x: number, z: number, rect: Rect): number
	local minX, maxX, minZ, maxZ = HubLayout.bounds(rect)
	local dx = math.max(minX - x, 0, x - maxX)
	local dz = math.max(minZ - z, 0, z - maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

function HubLayout.rectsOverlap(a: Rect, b: Rect): boolean
	local aMinX, aMaxX, aMinZ, aMaxZ = HubLayout.bounds(a)
	local bMinX, bMaxX, bMinZ, bMaxZ = HubLayout.bounds(b)
	return aMinX < bMaxX and bMinX < aMaxX and aMinZ < bMaxZ and bMinZ < aMaxZ
end

----------------------------------------------------------------------------------------------------------------
-- Terraced cliffs round the hub

-- The first zone's runway and the cliff banks down both its sides, which the hub's cliffs must stay off.
HubLayout.BANKS_HALF_WIDTH = Runway.START_WIDTH / 2 + 110
HubLayout.CLIFF_KEEP_OUT = {
	{ x = 0, z = 300, sizeX = HubLayout.BANKS_HALF_WIDTH * 2, sizeZ = 600 } :: Rect,
}
-- How many steps the cliffs climb in, from their foot at the edge of the hub to the crest.
HubLayout.TERRACE_TIERS = 5
-- The foot of the cliffs runs round the hub's edge (this far outside it) with rounded back corners of this radius.
HubLayout.CLIFF_GAP = 0
HubLayout.CLIFF_CORNER_RADIUS = 60
-- How far forward, past the front of the hub, the cliffs run down each side, into the first zone's scenery.
HubLayout.CLIFF_FRONT_Z = 40
-- About how long each block is along the foot of the cliffs (each straight stretch and corner is split evenly).
HubLayout.CLIFF_STEP = 14

-- Each tier: how deep it is (outward) and how much higher it stands than the tier below, as { low, high } in studs.
-- Low steps near the hub, then taller ones, and a broad crest at the top.
local TIERS = {
	{ depth = { 16, 24 }, rise = { 18, 26 } },
	{ depth = { 18, 26 }, rise = { 16, 24 } },
	{ depth = { 20, 30 }, rise = { 20, 30 } },
	{ depth = { 24, 34 }, rise = { 24, 34 } },
	{ depth = { 56, 76 }, rise = { 28, 40 } },
}
assert(#TIERS == HubLayout.TERRACE_TIERS, "one entry per tier")

-- Scenery ground under the cliffs, just below the hub's surface and out of reach behind its walls. It runs as far
-- forward as the cliffs do; beyond that the zones' banks take over.
HubLayout.OUTER_GROUND = {
	x = 0,
	z = (HubLayout.CLIFF_FRONT_Z - (LENGTH + 360)) / 2,
	sizeX = HALF_WIDTH * 2 + 720,
	sizeZ = HubLayout.CLIFF_FRONT_Z + LENGTH + 360,
} :: Rect

-- A small deterministic random number generator (Park-Miller), so every server builds the same cliffs.
-- Products stay below 2^53, so the arithmetic is exact everywhere.
local function newRandom(seed: number): (number?, number?) -> number
	local state = (math.floor(seed) % 2147483646) + 1
	return function(low: number?, high: number?): number
		state = (state * 16807) % 2147483647
		local value = (state - 1) / 2147483646
		if low ~= nil and high ~= nil then
			return low + (high - low) * value
		end
		return value
	end
end

-- A piece of the cliffs' foot: its middle, the way out from the hub there, its length, and (on a rounded corner)
-- the corner's radius and how far round it the piece turns.
type FootPiece = {
	x: number,
	z: number,
	nx: number,
	nz: number,
	length: number,
	radius: number?,
	sweep: number,
	-- Distance along the foot from its front-left end, to the piece's middle.
	distance: number,
}

-- The foot of the cliffs, from the front of the hub on the left, back and round the back corners, to the front on
-- the right, cut into pieces about CLIFF_STEP long.
local function footPieces(): { FootPiece }
	local pieces: { FootPiece } = {}
	local halfX = HALF_WIDTH + HubLayout.CLIFF_GAP
	local backZ = -(LENGTH + HubLayout.CLIFF_GAP)
	local radius = HubLayout.CLIFF_CORNER_RADIUS
	local front = HubLayout.CLIFF_FRONT_Z
	local travelled = 0

	local function straight(ax: number, az: number, bx: number, bz: number, nx: number, nz: number)
		local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local count = math.max(1, math.floor(length / HubLayout.CLIFF_STEP + 0.5))
		for step = 1, count do
			local t = (step - 0.5) / count
			table.insert(pieces, {
				x = ax + (bx - ax) * t,
				z = az + (bz - az) * t,
				nx = nx,
				nz = nz,
				length = length / count,
				sweep = 0,
				distance = travelled + length * t,
			})
		end
		travelled += length
	end

	local function corner(cx: number, cz: number, from: number, to: number)
		local length = math.abs(to - from) * radius
		local count = math.max(1, math.floor(length / HubLayout.CLIFF_STEP + 0.5))
		for step = 1, count do
			local angle = from + (to - from) * (step - 0.5) / count
			local nx, nz = math.cos(angle), math.sin(angle)
			table.insert(pieces, {
				x = cx + nx * radius,
				z = cz + nz * radius,
				nx = nx,
				nz = nz,
				length = length / count,
				radius = radius,
				sweep = math.abs(to - from) / count,
				distance = travelled + length * (step - 0.5) / count,
			})
		end
		travelled += length
	end

	straight(-halfX, front, -halfX, backZ + radius, -1, 0)
	corner(-halfX + radius, backZ + radius, math.pi, math.pi * 1.5)
	straight(-halfX + radius, backZ, halfX - radius, backZ, 0, -1)
	corner(halfX - radius, backZ + radius, math.pi * 1.5, math.pi * 2)
	straight(halfX, backZ + radius, halfX, front, 1, 0)
	return pieces
end

-- Builds the terraced cliffs. Called once when this module loads (HubLayout.TERRACES); exposed for tests.
--
-- Each piece of the foot gets a column of TERRACE_TIERS blocks, each further out and higher than the one below.
-- How deep and how high each step is drifts smoothly round the ring, with a little roughness piece to piece, so
-- the ledges wander and the skyline steps up and down like real terraces.
function HubLayout.generateTerraces(): { Terrace }
	local random = newRandom(20261114)
	local terraces: { Terrace } = {}
	local phases = {}
	for tier = 1, #TIERS do
		phases[tier] = random(0, math.pi * 2)
	end

	-- Smoothly wandering, from 0 to 1, round the ring.
	local function drift(distance: number, phase: number): number
		return 0.5 + 0.3 * math.sin(distance / 57 + phase) + 0.2 * math.sin(distance / 23 + phase * 2.3)
	end

	for _, piece in footPieces() do
		local offset, height = 0, 0
		for tier, shape in TIERS do
			local wander = drift(piece.distance, phases[tier])
			local depth = shape.depth[1] + (shape.depth[2] - shape.depth[1]) * (0.7 * wander + 0.3 * random())
			local rise = shape.rise[1] + (shape.rise[2] - shape.rise[1]) * (0.6 * wander + 0.4 * random())
			height += rise
			-- On a corner the block must reach round the outside of the curve, so it is as long as its outer edge.
			local length = if piece.radius then piece.sweep * (piece.radius + offset + depth) else piece.length
			table.insert(terraces, {
				x = piece.x + piece.nx * (offset + depth / 2),
				z = piece.z + piece.nz * (offset + depth / 2),
				yaw = math.atan2(piece.nx, piece.nz),
				length = length + 0.2,
				depth = depth,
				height = height,
				tier = tier,
				offset = offset,
				seed = math.floor(random() * 1e6),
			})
			offset += depth
		end
	end
	return terraces
end

HubLayout.TERRACES = HubLayout.generateTerraces()

-- The four corners of a terrace's footprint on the ground, as { x, z } points.
function HubLayout.terraceCorners(terrace: Terrace): { Point }
	-- The block's X axis (along the ring) and Z axis (outward) on the ground.
	local ax, az = math.cos(terrace.yaw), -math.sin(terrace.yaw)
	local ox, oz = math.sin(terrace.yaw), math.cos(terrace.yaw)
	local corners = {}
	for _, corner in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local along, out = corner[1] * terrace.length / 2, corner[2] * terrace.depth / 2
		table.insert(corners, { x = terrace.x + ax * along + ox * out, z = terrace.z + az * along + oz * out })
	end
	return corners
end

return HubLayout
