--!strict
-- Where an egg is at a given moment. The server and every client run these same functions against the shared
-- server clock, so eggs never need their positions sent over the network.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.

local EggMotion = {}

-- Distance down the runway.
function EggMotion.zAt(spawnTime: number, startZ: number, rollSpeed: number, now: number): number
	return startZ + rollSpeed * math.max(0, now - spawnTime)
end

-- Extra height while an egg drops in from its chute. `age` is seconds since it spawned.
function EggMotion.dropOffset(age: number, dropTime: number, dropHeight: number): number
	if age >= dropTime or dropTime <= 0 then
		return 0
	end
	local remaining = 1 - math.max(0, age) / dropTime
	return dropHeight * remaining * remaining
end

-- Extra height during the hop an egg makes when it is left without a rider.
-- `bounceTime` is when the hop began, or nil if the egg has never hopped.
function EggMotion.hopOffset(bounceTime: number?, now: number, hopDuration: number, hopHeight: number): number
	if bounceTime == nil or hopDuration <= 0 then
		return 0
	end
	local u = (now - bounceTime) / hopDuration
	if u <= 0 or u >= 1 then
		return 0
	end
	-- A parabola that peaks at hopHeight halfway through.
	return hopHeight * 4 * u * (1 - u)
end

-- How far (radians) an egg of this radius has turned after rolling `distance` studs.
function EggMotion.rollAngle(distance: number, radius: number): number
	if radius <= 0 then
		return 0
	end
	return distance / radius
end

return EggMotion
