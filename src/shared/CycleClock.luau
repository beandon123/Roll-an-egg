--!strict
-- The runway cycle, derived from the shared server clock so the server, every client, and anyone who joins late
-- all agree on it without sending any messages.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Each cycle is CYCLE_LENGTH seconds: the runway is open, shows a warning for the last WARNING_LENGTH seconds
-- before it closes, then is closed for the final CLOSED_LENGTH seconds.

export type Phase = "Open" | "Warning" | "Closed"

export type State = {
	-- Cycle number since the clock's epoch.
	index: number,
	phase: Phase,
	-- Seconds since this cycle began.
	elapsed: number,
	-- Seconds until the runway closes (0 while closed).
	untilClose: number,
	-- Seconds until the next cycle begins.
	untilNextCycle: number,
}

local CycleClock = {}

CycleClock.CYCLE_LENGTH = 180
CycleClock.CLOSED_LENGTH = 10
CycleClock.WARNING_LENGTH = 10
-- Seconds into a cycle when the runway closes.
CycleClock.CLOSE_AT = CycleClock.CYCLE_LENGTH - CycleClock.CLOSED_LENGTH

-- Events repeat every EVENT_PERIOD cycles (20 x 3 min = once an hour each, 30 min apart).
CycleClock.EVENT_PERIOD = 20
CycleClock.TITAN_CYCLE = 0
CycleClock.AVALANCHE_CYCLE = 10

function CycleClock.getState(serverTime: number): State
	local index = math.floor(serverTime / CycleClock.CYCLE_LENGTH)
	local elapsed = serverTime - index * CycleClock.CYCLE_LENGTH
	local phase: Phase
	if elapsed >= CycleClock.CLOSE_AT then
		phase = "Closed"
	elseif elapsed >= CycleClock.CLOSE_AT - CycleClock.WARNING_LENGTH then
		phase = "Warning"
	else
		phase = "Open"
	end
	return {
		index = index,
		phase = phase,
		elapsed = elapsed,
		untilClose = math.max(0, CycleClock.CLOSE_AT - elapsed),
		untilNextCycle = CycleClock.CYCLE_LENGTH - elapsed,
	}
end

-- Which server event, if any, belongs to a cycle.
function CycleClock.eventForCycle(index: number): "Titan" | "Avalanche" | nil
	local slot = index % CycleClock.EVENT_PERIOD
	if slot == CycleClock.TITAN_CYCLE then
		return "Titan"
	elseif slot == CycleClock.AVALANCHE_CYCLE then
		return "Avalanche"
	end
	return nil
end

return CycleClock
