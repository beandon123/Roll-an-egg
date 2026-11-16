--!strict
-- Server luck boosts: timed multipliers that make rarer eggs drop more often for everyone in the server.
-- Pure (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Each multiplier keeps its own timer. Buying a boost that is already running adds its time on top, and the
-- strongest running boost is the one in effect, so nobody's purchase is ever wasted: a x2 bought during a x4 waits
-- underneath and takes over when the x4 ends.
--
-- Boosts are a list of { multiplier, endsAt } (a list, not a map, so it survives being sent through a remote).

export type Boost = { multiplier: number, endsAt: number }

local LuckBoost = {}

-- Adds `duration` seconds of a multiplier. Returns the updated list (the same table, with expired boosts removed).
function LuckBoost.add(boosts: { Boost }, multiplier: number, duration: number, now: number): { Boost }
	LuckBoost.prune(boosts, now)
	for _, boost in boosts do
		if boost.multiplier == multiplier then
			boost.endsAt += duration
			return boosts
		end
	end
	table.insert(boosts, { multiplier = multiplier, endsAt = now + duration })
	return boosts
end

-- Removes boosts that have run out.
function LuckBoost.prune(boosts: { Boost }, now: number)
	for index = #boosts, 1, -1 do
		if boosts[index].endsAt <= now then
			table.remove(boosts, index)
		end
	end
end

-- The luck in effect (1 when nothing is running) and when that boost ends (nil when nothing is running).
function LuckBoost.current(boosts: { Boost }, now: number): (number, number?)
	local best, endsAt = 1, nil
	for _, boost in boosts do
		if boost.endsAt > now and boost.multiplier > best then
			best, endsAt = boost.multiplier, boost.endsAt
		end
	end
	return best, endsAt
end

return LuckBoost
