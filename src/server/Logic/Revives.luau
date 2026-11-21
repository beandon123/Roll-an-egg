--!strict
-- Revives: a player who misses their leap (lands on the runway, or runs out of time) and has a revive left is held
-- where they fell and offered one, for Tuning.REVIVE_OFFER_TIME seconds. Using it takes one revive and puts them
-- back in the air above an egg with a fresh leap (their device does that); letting the time run out, or saying no,
-- sends them back to the hub as usual. Revives are bought in the shop and come in its packs (Config/Shop), and are
-- kept until used.
--
-- Like the other rules in Logic/, this works on plain tables (a player's saved data, and the offers running in a
-- server, by user ID) with no players, parts or remotes, so it is covered by tests outside Studio. RunwayService
-- feeds it the clock and what players ask, and holds or kills their characters.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Tuning = require(Shared.Config.Tuning)

-- The offers running in a server: userId -> when the player's time to answer runs out (server time).
export type Offers = { [number]: number }

local Revives = {}

-- How many revives a player has.
function Revives.count(data): number
	return math.max(0, math.floor(data.Revives or 0))
end

-- Gives a player revives (a purchase).
function Revives.add(data, amount: number)
	data.Revives = Revives.count(data) + math.max(0, math.floor(amount))
end

-- The player missed their leap: offer them a revive if they have one and none is on offer already. Returns when the
-- offer runs out, or nil if there is none to offer.
function Revives.offer(offers: Offers, data, userId: number, now: number): number?
	if offers[userId] ~= nil or Revives.count(data) < 1 then
		return nil
	end
	local endsAt = now + Tuning.REVIVE_OFFER_TIME
	offers[userId] = endsAt
	return endsAt
end

-- Whether the player is held where they fell, waiting to answer an offer (the server allows LEAP_SERVER_GRACE more
-- than their device, for the answer to arrive).
function Revives.isWaiting(offers: Offers, userId: number, now: number): boolean
	local endsAt = offers[userId]
	return endsAt ~= nil and now <= endsAt + Tuning.LEAP_SERVER_GRACE
end

-- The player said yes: uses one of their revives if their offer is still open. Returns whether it did.
function Revives.use(offers: Offers, data, userId: number, now: number): boolean
	if not Revives.isWaiting(offers, userId, now) or Revives.count(data) < 1 then
		return false
	end
	offers[userId] = nil
	data.Revives = Revives.count(data) - 1
	return true
end

-- The player said no, died, or left: their offer is gone.
function Revives.cancel(offers: Offers, userId: number)
	offers[userId] = nil
end

-- Offers whose time (and the server's grace) has run out with no answer. They are removed; returns their user IDs,
-- for the server to send those players back to the hub.
function Revives.expire(offers: Offers, now: number): { number }
	local expired = {}
	for userId, endsAt in offers do
		if now > endsAt + Tuning.LEAP_SERVER_GRACE then
			table.insert(expired, userId)
		end
	end
	table.sort(expired)
	for _, userId in expired do
		offers[userId] = nil
	end
	return expired
end

return Revives
