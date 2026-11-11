--!strict
-- Stamina is stored as "a value at a moment, changing at a steady rate", so its current amount can be worked out
-- at any time without a per-frame loop. The server writes those three numbers; the server and the HUD both read
-- the current amount with `current`.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.

local StaminaMath = {}

-- The stamina right now, given what it was at `time` and how fast it changes per second
-- (positive while regenerating, negative while riding).
function StaminaMath.current(value: number, time: number, rate: number, max: number, now: number): number
	return math.clamp(value + rate * (now - time), 0, max)
end

-- Stamina lost per second while riding an egg.
function StaminaMath.drainRate(requirement: number, claimTime: number, drainFraction: number): number
	if claimTime <= 0 then
		return 0
	end
	return requirement * drainFraction / claimTime
end

-- Seconds until `stamina` runs out at `drain` per second (math.huge if it never does).
function StaminaMath.timeUntilEmpty(stamina: number, drain: number): number
	if drain <= 0 then
		return math.huge
	end
	return math.max(0, stamina) / drain
end

return StaminaMath
