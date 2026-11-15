--!strict
-- Where an egg is at a given moment. The server and every client run these same functions against the shared
-- server clock, so eggs never need their positions sent over the network.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.

local EggMotion = {}

-- Distance down the runway.
function EggMotion.zAt(spawnTime: number, startZ: number, rollSpeed: number, now: number): number
	return startZ + rollSpeed * math.max(0, now - spawnTime)
end

-- How far (radians) an egg of this radius has turned after rolling `distance` studs.
function EggMotion.rollAngle(distance: number, radius: number): number
	if radius <= 0 then
		return 0
	end
	return distance / radius
end

return EggMotion
