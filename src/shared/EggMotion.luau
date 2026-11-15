--!strict
-- Where an egg is at a given moment. The server and every client run these same functions against the shared
-- server clock, so eggs never need their positions sent over the network.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.

local EggMotion = {}

-- Distance down the runway.
function EggMotion.zAt(spawnTime: number, startZ: number, rollSpeed: number, now: number): number
	return startZ + rollSpeed * math.max(0, now - spawnTime)
end

-- Extra height during the one small bounce an egg makes before it cracks (when its rider runs out of stamina).
-- `bounceTime` is when the bounce began, or nil if the egg is not bouncing.
function EggMotion.bounceOffset(bounceTime: number?, now: number, duration: number, height: number): number
	if bounceTime == nil or duration <= 0 then
		return 0
	end
	local u = (now - bounceTime) / duration
	if u <= 0 or u >= 1 then
		return 0
	end
	-- A parabola that peaks at `height` halfway through.
	return height * 4 * u * (1 - u)
end

-- How far (radians) an egg of this radius has turned after rolling `distance` studs.
function EggMotion.rollAngle(distance: number, radius: number): number
	if radius <= 0 then
		return 0
	end
	return distance / radius
end

return EggMotion
