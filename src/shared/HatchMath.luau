--!strict
-- How far along an egg in a nest is. Hatching is worked out from timestamps, never a running timer, so it carries
-- on while the player is offline and every device shows the same countdown.
--
-- While the runway is closed (the last seconds of each cycle) every nest in the server hatches HATCH_BOOST times as
-- fast. During the closure that extra time is counted live from the clock; when the next cycle starts, the server
-- adds it to the nest's saved `bonus` for good (see InventoryService).
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.

local CycleClock = require(script.Parent.CycleClock)
local Rarities = require(script.Parent.Config.Rarities)
local Tuning = require(script.Parent.Config.Tuning)

local HatchMath = {}

-- Seconds a rarity takes to hatch at normal speed.
function HatchMath.hatchTime(rarity: string): number
	local info = Rarities.Info[rarity]
	return if info then info.hatchTime else 60
end

-- The extra seconds of hatching a nest gets from the closure going on at `now` (0 when the runway is open).
-- Only the part of the closure after the egg was placed counts.
function HatchMath.closureBoost(placedAt: number, now: number): number
	local state = CycleClock.getState(now)
	if state.phase ~= "Closed" then
		return 0
	end
	local closedAt = now - (state.elapsed - CycleClock.CLOSE_AT)
	return (Tuning.HATCH_BOOST - 1) * math.max(0, now - math.max(closedAt, placedAt))
end

-- The extra seconds a whole closure gives an egg placed at `placedAt`, for the closure that ended at `cycleStart`.
function HatchMath.closureBonus(placedAt: number, cycleStart: number): number
	local closedAt = cycleStart - CycleClock.CLOSED_LENGTH
	return (Tuning.HATCH_BOOST - 1) * math.max(0, cycleStart - math.max(closedAt, placedAt))
end

-- Seconds of hatching an egg has had: time in the nest, plus closure bonuses saved and going on now.
function HatchMath.elapsed(placedAt: number, bonus: number, now: number): number
	return math.max(0, now - placedAt) + bonus + HatchMath.closureBoost(placedAt, now)
end

-- How far along an egg is, from 0 to 1.
function HatchMath.progress(placedAt: number, bonus: number, rarity: string, now: number): number
	return math.clamp(HatchMath.elapsed(placedAt, bonus, now) / HatchMath.hatchTime(rarity), 0, 1)
end

-- Seconds of normal time until an egg hatches (0 when it is ready).
function HatchMath.timeLeft(placedAt: number, bonus: number, rarity: string, now: number): number
	return math.max(0, HatchMath.hatchTime(rarity) - HatchMath.elapsed(placedAt, bonus, now))
end

return HatchMath
