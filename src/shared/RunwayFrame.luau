-- Runway coordinates as places in the world. The rules work in runway coordinates (Shared/Runway): x across the
-- runway, z down it along its centre line. The runway itself bends and climbs, so everything that draws, builds or
-- reads a character's position goes through here to get Vector3s and CFrames (Shared/Runway does the math).

local Runway = require(script.Parent.Runway)

local RunwayFrame = {}

-- The spot on the runway at (x, z), `height` studs above its surface.
function RunwayFrame.point(x: number, z: number, height: number?): Vector3
	local worldX, worldY, worldZ = Runway.toWorld(x, z)
	return Vector3.new(worldX, worldY + (height or 0), worldZ)
end

-- A frame standing upright on the runway at (x, z), `height` studs above its surface: +X points across the runway
-- (toward +x), +Y straight up, and +Z down the runway. Where the runway is straight and level this is just
-- CFrame.new(x, surface + height, z).
function RunwayFrame.at(x: number, z: number, height: number?): CFrame
	local worldX, worldY, worldZ = Runway.toWorld(x, z)
	return CFrame.new(worldX, worldY + (height or 0), worldZ) * CFrame.Angles(0, Runway.heading(z), 0)
end

-- The same, tipped to lie on the slope: +Z runs down the runway along the ground, +Y points square off it.
function RunwayFrame.onSlope(x: number, z: number, height: number?): CFrame
	return RunwayFrame.at(x, z) * CFrame.Angles(-math.atan(Runway.slope(z)), 0, 0) * CFrame.new(0, height or 0, 0)
end

-- The same spot and heading as `at`, but at a height in the world rather than above the runway.
function RunwayFrame.atHeight(x: number, z: number, worldY: number): CFrame
	local worldX, _, worldZ = Runway.toWorld(x, z)
	return CFrame.new(worldX, worldY, worldZ) * CFrame.Angles(0, Runway.heading(z), 0)
end

-- Which way is down the runway at `z` (level, whatever the slope), and which way is across it (toward +x).
function RunwayFrame.forward(z: number): Vector3
	local heading = Runway.heading(z)
	return Vector3.new(math.sin(heading), 0, math.cos(heading))
end

function RunwayFrame.across(z: number): Vector3
	local heading = Runway.heading(z)
	return Vector3.new(math.cos(heading), 0, -math.sin(heading))
end

-- Where a place in the world is on the runway: x across it, z down it, and how high above its surface there.
-- (Behind the start, in the hub, x and z are simply the world X and Z.)
function RunwayFrame.locate(position: Vector3): (number, number, number)
	local x, z = Runway.fromWorld(position.X, position.Z)
	return x, z, position.Y - Runway.surfaceY(z)
end

-- How far one copy of the endless last zone is from the one before it (see Shared/Runway).
function RunwayFrame.loopShift(): Vector3
	return Vector3.new(Runway.loopShift())
end

return RunwayFrame
