--!strict
-- The leaderboards' rankings (Config/Leaderboards): the top scores across every server, with the live scores of the
-- players in this server on top, and how scores are stored.
-- Plain Luau (no Roblox objects), so tests run outside Studio. LeaderboardService reads and writes the stores.

local Rankings = {}

export type Entry = { userId: number, score: number }

-- The biggest score an OrderedDataStore entry is given: it only holds whole numbers, and above 2^53 a Luau number
-- can no longer hold every whole number.
Rankings.MAX_STORED = 2 ^ 53

-- A score as the store keeps it: a whole number from 0 up to MAX_STORED.
function Rankings.stored(score: number): number
	if score ~= score or score <= 0 then
		return 0
	end
	return math.min(Rankings.MAX_STORED, math.floor(score))
end

-- Everyone ranked, best first, from the last read of a store (`global`: userId -> score) and the scores of players
-- in this server right now (`live`), which replace what the store had for them (a score can go down: a trail taken
-- off, a pet sold). Players with no score are left out. Ties go to whoever has the lower user ID, so the order
-- never flickers.
function Rankings.rank(global: { [number]: number }, live: { [number]: number }): { Entry }
	local merged = table.clone(global)
	for userId, score in live do
		merged[userId] = score
	end
	local list: { Entry } = {}
	for userId, score in merged do
		if score > 0 then
			table.insert(list, { userId = userId, score = score })
		end
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.userId < b.userId
	end)
	return list
end

-- A player's place in a ranking (1 for the top), or 0 if they are not in it.
function Rankings.rankOf(list: { Entry }, userId: number): number
	for index, entry in list do
		if entry.userId == userId then
			return index
		end
	end
	return 0
end

return Rankings
