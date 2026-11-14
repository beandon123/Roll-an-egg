-- Server events, and the admin panel's controls over the runway cycle.
--
-- Built so far: the Egg Avalanche, twice the eggs in every zone until the runway closes. It runs on the schedule in
-- Shared/CycleClock (cycle 10 of every 20, so once an hour) or whenever an admin starts one. The Titan Egg is not
-- built yet, so its slot in the schedule passes quietly.
--
-- Close / Open the runway now jump the shared cycle clock ahead to the next closure or the next cycle
-- (CycleClock.setOffset), so everything that follows the cycle (the egg rules, every player's HUD) moves on
-- together. What every device needs is kept in Workspace attributes:
--     ServerEvent    the event running now ("Avalanche"), or nil   (CycleClock.EVENT_ATTRIBUTE)
--     CycleOffset    seconds the cycle clock has been moved ahead   (CycleClock.OFFSET_ATTRIBUTE)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CycleClock = require(Shared.CycleClock)
local Net = require(Shared.Net)
local Tuning = require(Shared.Config.Tuning)

local RunwayService = require(script.Parent.RunwayService)

local AVALANCHE_COLOR = { 180, 120, 255 }
-- A jump lands this far past the moment it aims for, so rounding cannot leave the clock a hair short of it.
local JUMP_SLACK = 1e-3

local EventService = {}

local active: string? = nil
local lastCycle: number? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function setActive(event: string?)
	active = event
	RunwayService.SetEggRate(if event == "Avalanche" then Tuning.AVALANCHE_EGG_MULTIPLIER else 1)
	Workspace:SetAttribute(CycleClock.EVENT_ATTRIBUTE, event)
end

local function setOffset(seconds: number)
	CycleClock.setOffset(seconds)
	Workspace:SetAttribute(CycleClock.OFFSET_ATTRIBUTE, seconds)
end

-- The event running now ("Avalanche"), or nil.
function EventService.GetActive(): string?
	return active
end

-- Starts an event now. Returns whether it started, and a message saying what happened.
function EventService.StartEvent(event: string): (boolean, string)
	if event ~= "Avalanche" then
		return false, `The {CycleClock.EVENT_NAMES[event] or event} event isn't built yet.`
	end
	if active == event then
		return false, "An Egg Avalanche is already on."
	end
	if CycleClock.getState(now()).phase == "Closed" then
		return false, "The runway is closed. Start the Avalanche once it opens again."
	end
	setActive(event)
	Net.Announce:FireAllClients("EGG AVALANCHE! Twice the eggs in every zone until the runway closes!", AVALANCHE_COLOR)
	return true, "Egg Avalanche started. It ends when the runway closes."
end

-- Ends the event running now.
function EventService.StopEvent(): (boolean, string)
	if active == nil then
		return false, "No event is running."
	end
	local name = CycleClock.EVENT_NAMES[active] or active
	setActive(nil)
	Net.Announce:FireAllClients(`The {name} is over.`)
	return true, `Stopped the {name}.`
end

-- Jumps the cycle ahead to its closure: every egg without a rider disappears, as at any closure.
function EventService.CloseRunwayNow(): (boolean, string)
	local state = CycleClock.getState(now())
	if state.phase == "Closed" then
		return false, "The runway is already closed."
	end
	setOffset(CycleClock.getOffset() + state.untilClose + JUMP_SLACK)
	return true, `Runway closed. It opens again in {CycleClock.CLOSED_LENGTH} seconds.`
end

-- Jumps a closed runway ahead to the start of the next cycle.
function EventService.OpenRunwayNow(): (boolean, string)
	local state = CycleClock.getState(now())
	if state.phase ~= "Closed" then
		return false, "The runway is already open."
	end
	setOffset(CycleClock.getOffset() + state.untilNextCycle + JUMP_SLACK)
	return true, "Runway open. A new cycle has started."
end

local function update()
	local state = CycleClock.getState(now())
	-- An event lasts until the runway closes.
	if state.phase == "Closed" and active ~= nil then
		setActive(nil)
	end
	if state.index ~= lastCycle then
		lastCycle = state.index
		if state.phase ~= "Closed" and CycleClock.eventForCycle(state.index) == "Avalanche" and active == nil then
			EventService.StartEvent("Avalanche")
		end
	end
end

function EventService.Init()
	setOffset(0)
	setActive(nil)
end

function EventService.Start()
	RunService.Heartbeat:Connect(update)
end

return EventService
