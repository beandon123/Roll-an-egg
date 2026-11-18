--!strict
-- Where an egg is at a given moment. The server and every client run these same functions against the shared
-- server clock, so eggs never need their positions sent over the network.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.

local Tuning = require(script.Parent.Config.Tuning)

local EggMotion = {}

-- An egg that runs into something slows down for a moment (Tuning.HIT_EFFECTS), rolling at Tuning.SLOW_FACTOR of its
-- speed. Its motion stays a function of the clock: `lost` is the seconds of rolling lost to earlier slow-downs, and
-- the one in progress (if any) began at `at` and lasts `duration` seconds.
export type Slow = { lost: number, at: number?, duration: number }

-- Seconds of rolling an egg has lost to slow-downs by `now`.
function EggMotion.lostTime(slow: Slow?, now: number): number
	if slow == nil then
		return 0
	end
	local lost = slow.lost
	if slow.at then
		lost += math.clamp(now - slow.at, 0, slow.duration) * (1 - Tuning.SLOW_FACTOR)
	end
	return lost
end

-- A slow-down of `duration` seconds starting at `now`, on top of any before it.
function EggMotion.addSlow(slow: Slow?, now: number, duration: number): Slow
	return { lost = EggMotion.lostTime(slow, now), at = now, duration = duration }
end

-- Distance down the runway. `slow` is the egg's slow-downs, if it has had any.
function EggMotion.zAt(spawnTime: number, startZ: number, rollSpeed: number, now: number, slow: Slow?): number
	return startZ + rollSpeed * math.max(0, now - spawnTime - EggMotion.lostTime(slow, now))
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
