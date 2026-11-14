--!strict
-- Runway geometry. Everything that needs to know where the runway is (the map builder, egg movement, mounting
-- checks) reads it from here, so gameplay never depends on map parts being loaded.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Coordinates: the runway starts at z = 0 and runs toward +z. x is the side-to-side ("lateral") position,
-- with 0 on the centre line. The hub sits behind the start, at negative z.

local Runway = {}

Runway.ZONE_COUNT = 6
Runway.ZONE_LENGTH = 600
Runway.LENGTH = Runway.ZONE_COUNT * Runway.ZONE_LENGTH
-- Wide enough for a whole server to chase eggs side by side; walls run down both sides.
Runway.WIDTH = 120

-- Height of the walking surface at the hub and the start of the runway.
Runway.BASE_Y = 10
-- Studs of drop per stud travelled; the runway is a gentle downhill.
Runway.SLOPE = 0.04

Runway.HUB_LENGTH = 220
Runway.HUB_WIDTH = 240

-- Gaps in the side walls: a player on foot who wanders through one falls off the runway. Eggs never do, because
-- they are kept within the runway's width.
Runway.WALL_GAP_LENGTH = 24
-- Where each zone's gaps open, in studs from the start of the zone. They skip the zone's first stretch (its sign
-- stands on the walls and its eggs drop in there) and its last stretch, and alternate sides.
Runway.WALL_GAP_OFFSETS = { 150, 300, 450 }

export type WallGap = { side: number, startZ: number, endZ: number }

-- The gaps in one zone's walls. `side` is 1 for the wall at +x (the left, looking down the runway) and -1 for -x.
-- The first gap switches side from one zone to the next, so the pattern does not repeat exactly.
function Runway.wallGaps(zoneId: number): { WallGap }
	local gaps = {}
	local zoneStart = Runway.zoneStartZ(zoneId)
	for index, offset in Runway.WALL_GAP_OFFSETS do
		local side = if (index + zoneId) % 2 == 0 then 1 else -1
		local startZ = zoneStart + offset
		table.insert(gaps, { side = side, startZ = startZ, endZ = startZ + Runway.WALL_GAP_LENGTH })
	end
	return gaps
end

-- Height of the walking surface at a given distance down the runway.
function Runway.surfaceY(z: number): number
	if z <= 0 then
		return Runway.BASE_Y
	end
	return Runway.BASE_Y - Runway.SLOPE * math.min(z, Runway.LENGTH)
end

-- Distance down the runway where a zone begins.
function Runway.zoneStartZ(zoneId: number): number
	return (zoneId - 1) * Runway.ZONE_LENGTH
end

-- Which zone a distance down the runway falls in, or nil if it is off either end.
function Runway.zoneAt(z: number): number?
	if z < 0 or z >= Runway.LENGTH then
		return nil
	end
	return math.floor(z / Runway.ZONE_LENGTH) + 1
end

-- The furthest from the centre line an egg of this radius may sit without hanging over the edge.
function Runway.maxLateral(radius: number): number
	return math.max(0, Runway.WIDTH / 2 - radius - 1)
end

function Runway.clampLateral(x: number, radius: number): number
	local limit = Runway.maxLateral(radius)
	return math.clamp(x, -limit, limit)
end

return Runway
