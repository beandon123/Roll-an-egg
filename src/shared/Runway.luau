--!strict
-- Runway geometry. Everything that needs to know where the runway is (the map builder, egg movement, mounting
-- checks) reads it from here, so gameplay never depends on map parts being loaded.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Coordinates: the runway starts at z = 0 and runs toward +z. x is the side-to-side ("lateral") position,
-- with 0 on the centre line. The hub sits behind the start, at negative z. The runway is level all the way: eggs
-- roll at the speed their rarity sets, not because of a slope.

local Runway = {}

Runway.ZONE_COUNT = 6
Runway.ZONE_LENGTH = 600
Runway.LENGTH = Runway.ZONE_COUNT * Runway.ZONE_LENGTH
Runway.WIDTH = 120

-- Height of the walking surface, at the hub and all the way down the runway.
Runway.BASE_Y = 10

-- An egg rolls on past the end of its own zone and fades out this far into the next one (a fraction of a zone).
Runway.FADE_INTO_NEXT = 0.25

Runway.HUB_LENGTH = 220
Runway.HUB_WIDTH = 240

-- Height of the walking surface at a given distance down the runway.
function Runway.surfaceY(_z: number): number
	return Runway.BASE_Y
end

-- Distance down the runway where a zone begins.
function Runway.zoneStartZ(zoneId: number): number
	return (zoneId - 1) * Runway.ZONE_LENGTH
end

-- Where a riderless egg from this zone fades out: a quarter of the way into the next zone, or at the end cliff
-- for the last zone.
function Runway.fadeZ(zoneId: number): number
	return math.min(Runway.zoneStartZ(zoneId + 1) + Runway.FADE_INTO_NEXT * Runway.ZONE_LENGTH, Runway.LENGTH)
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
