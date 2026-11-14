--!strict
-- The runway cycle, derived from the shared server clock so the server, every client, and anyone who joins late
-- all agree on it without sending any messages.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Each cycle is CYCLE_LENGTH seconds: the runway is open, shows a warning for the last WARNING_LENGTH seconds
-- before it closes, then is closed for the final CLOSED_LENGTH seconds.
--
-- Each cycle is also one day. The sun rises as a cycle begins, which is when every zone rolls out its fresh lineup
-- of eggs; night falls DAY_FRACTION of the way through; the runway closes in the last moments before the next
-- sunrise.

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

-- The time of day (Lighting.ClockTime, in hours) at the start of a cycle and when night falls.
CycleClock.SUNRISE = 6
CycleClock.SUNSET = 18
-- How much of each cycle is daytime.
CycleClock.DAY_FRACTION = 0.7

-- Events repeat every EVENT_PERIOD cycles (20 x 3 min = once an hour each, 30 min apart).
CycleClock.EVENT_PERIOD = 20
CycleClock.TITAN_CYCLE = 0
CycleClock.AVALANCHE_CYCLE = 10
-- The event running now ("Avalanche"), or nil: the server's EventService keeps it in this Workspace attribute.
CycleClock.EVENT_ATTRIBUTE = "ServerEvent"
-- What each event is called on screen.
CycleClock.EVENT_NAMES = { Titan = "Titan Egg", Avalanche = "Egg Avalanche" }

-- Seconds the cycle has been moved forward on top of the server clock: the admin panel's "Close the runway now"
-- and "Open the runway now" jump ahead to the next closure or cycle. The server shares it with every device in the
-- Workspace attribute OFFSET_ATTRIBUTE; each device passes it to setOffset, and getState adds it.
CycleClock.OFFSET_ATTRIBUTE = "CycleOffset"
local offset = 0

function CycleClock.setOffset(seconds: number)
	offset = seconds
end

function CycleClock.getOffset(): number
	return offset
end

function CycleClock.getState(serverTime: number): State
	local cycleTime = serverTime + offset
	local index = math.floor(cycleTime / CycleClock.CYCLE_LENGTH)
	local elapsed = cycleTime - index * CycleClock.CYCLE_LENGTH
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

-- The time of day at a moment, in hours from 0 to 24, for Lighting.ClockTime: sunrise as each cycle begins, sunset
-- DAY_FRACTION of the way through, and through the night to the next sunrise.
function CycleClock.clockTime(serverTime: number): number
	local u = CycleClock.getState(serverTime).elapsed / CycleClock.CYCLE_LENGTH
	local dayHours = CycleClock.SUNSET - CycleClock.SUNRISE
	local hours
	if u < CycleClock.DAY_FRACTION then
		hours = CycleClock.SUNRISE + dayHours * u / CycleClock.DAY_FRACTION
	else
		hours = CycleClock.SUNSET + (24 - dayHours) * (u - CycleClock.DAY_FRACTION) / (1 - CycleClock.DAY_FRACTION)
	end
	return hours % 24
end

-- How bright the day is, from 0 (the middle of the night) to 1 (noon), for lighting that follows the sun.
function CycleClock.daylight(serverTime: number): number
	local hours = CycleClock.clockTime(serverTime)
	-- Full daylight from two hours after sunrise to two hours before sunset; darkest at midnight.
	local fromNoon = math.abs(hours - 12)
	return math.clamp((8 - fromNoon) / 4, 0, 1)
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
