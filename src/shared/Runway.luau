--!strict
-- Runway geometry. Everything that needs to know where the runway is (the map builder, egg movement, mounting
-- checks) reads it from here, so gameplay never depends on map parts being loaded.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Coordinates: the runway starts at z = 0 and runs toward +z. x is the side-to-side ("lateral") position,
-- with 0 on the centre line. The hub sits behind the start, at negative z.

local Runway = {}

Runway.ZONE_COUNT = 5
Runway.ZONE_LENGTH = 600
Runway.LENGTH = Runway.ZONE_COUNT * Runway.ZONE_LENGTH
Runway.WIDTH = 64

-- Height of the walking surface at the hub and the start of the runway.
Runway.BASE_Y = 10
-- Studs of drop per stud travelled; the runway is a gentle downhill.
Runway.SLOPE = 0.04

-- The walkable hub behind the start of the runway (x from -HUB_WIDTH / 2 to +HUB_WIDTH / 2, z from -HUB_LENGTH
-- to 0). Everything inside it is laid out in Shared/HubLayout.
Runway.HUB_LENGTH = 260
Runway.HUB_WIDTH = 300

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
