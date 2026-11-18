--!strict
-- The rules of the training stick (Config/Sticks): what each rep adds, upgrading the stick, and the "2x" bubbles.
--
-- A player rolling on their stick has a session. `step` is called every frame with the clock: it hands back the
-- reps that came due (one every Sticks.REP_INTERVAL, each doubled if a boost was running when it came) and says when
-- a bubble appears. A bubble left alone goes after Sticks.BUBBLE_LIFETIME; tapping it in time (`claim`) doubles the
-- next Sticks.BOOST_DURATION seconds of reps. Either way the next bubble comes a few seconds later.
--
-- These functions change a player's saved data table directly and never touch players, parts, or remotes:
-- TrainingService checks what clients send, calls these, and tells the client what changed. Keeping them free of
-- Roblox objects means they are covered by tests that run outside Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Sticks = require(Shared.Config.Sticks)

local Stats = require(script.Parent.Stats)

export type Bubble = { id: number, endsAt: number }

export type Session = {
	level: number,
	startedAt: number,
	-- When the next rep comes due.
	nextRepAt: number,
	-- Reps that come due from boostFrom until boostUntil count double.
	boostFrom: number,
	boostUntil: number,
	-- The bubble up now, if any, and when the next one appears if none is.
	bubble: Bubble?,
	nextBubbleAt: number,
	bubbles: number,
	reps: number,
	-- 0 to 1, for the gaps between bubbles.
	random: () -> number,
}

-- What one step of a session brought: every rep that came due (true for a boosted one), and a bubble that has just
-- appeared.
export type StepResult = { reps: { boolean }, bubble: Bubble? }

export type UpgradeResult = "Upgraded" | "Max" | "NotEnoughDollars"

local Training = {}

-- Most reps one step hands back. If the server stalls for longer than that, the missed reps are dropped rather than
-- paid all at once.
Training.MAX_CATCH_UP = 8

-- The tier of the stick a player has (1 to Sticks.MAX_LEVEL).
function Training.levelOf(data): number
	return Sticks.tier(data.StickLevel or 1).level
end

-- What one rep's Max Stamina is multiplied by: the player's stamina doublings and their trail's boost.
function Training.multiplier(data): number
	return (data.StaminaMultiplier or 1) * Stats.trailMultiplier(data)
end

-- How much Max Stamina one rep on the player's stick adds, multipliers and all (doubled if `boosted`).
function Training.gainPerRep(data, boosted: boolean?): number
	local gain = Sticks.tier(Training.levelOf(data)).perRep * Training.multiplier(data)
	return if boosted then gain * Sticks.BOOST_MULTIPLIER else gain
end

-- One rep: adds its Max Stamina for good. Returns how much the player's Max Stamina went up.
function Training.addRep(data, boosted: boolean): number
	local before = Stats.maxStamina(data)
	local base = Sticks.tier(Training.levelOf(data)).perRep
	data.TrainedStamina = (data.TrainedStamina or 0) + (if boosted then base * Sticks.BOOST_MULTIPLIER else base)
	data.Stats.TrainingReps = (data.Stats.TrainingReps or 0) + 1
	return Stats.maxStamina(data) - before
end

-- Buys the next tier of the player's stick with dollars. Returns whether it worked, why not, and the price of the
-- tier it was for (nil once the stick is as good as it gets).
function Training.upgrade(data): (boolean, UpgradeResult, number?)
	local nextTier = Sticks.nextTier(Training.levelOf(data))
	if nextTier == nil then
		return false, "Max", nil
	end
	if data.Dollars < nextTier.price then
		return false, "NotEnoughDollars", nextTier.price
	end
	data.Dollars -= nextTier.price
	data.StickLevel = nextTier.level
	return true, "Upgraded", nextTier.price
end

-- Raises the player's stick a tier without paying dollars (bought with Robux). Returns false if it is already as
-- good as it gets.
function Training.raise(data): boolean
	local nextTier = Sticks.nextTier(Training.levelOf(data))
	if nextTier == nil then
		return false
	end
	data.StickLevel = nextTier.level
	return true
end

----------------------------------------------------------------------------------------------------------------
-- Sessions

local function bubbleGap(session: Session): number
	local low, high = Sticks.BUBBLE_GAP[1], Sticks.BUBBLE_GAP[2]
	return low + (high - low) * session.random()
end

-- A player starts rolling on a stick of `level` at `now`. `random` gives numbers from 0 to 1.
function Training.start(level: number, now: number, random: () -> number): Session
	return {
		level = level,
		startedAt = now,
		nextRepAt = now + Sticks.REP_INTERVAL,
		boostFrom = 0,
		boostUntil = 0,
		bubble = nil,
		nextBubbleAt = now + Sticks.FIRST_BUBBLE,
		bubbles = 0,
		reps = 0,
		random = random,
	}
end

-- Moves a session on to `now`: the reps that came due, and a bubble if one has just appeared.
function Training.step(session: Session, now: number): StepResult
	local reps = {}
	while session.nextRepAt <= now do
		if #reps >= Training.MAX_CATCH_UP then
			session.nextRepAt = now + Sticks.REP_INTERVAL
			break
		end
		local due = session.nextRepAt
		table.insert(reps, due >= session.boostFrom and due < session.boostUntil)
		session.reps += 1
		session.nextRepAt += Sticks.REP_INTERVAL
	end

	local appeared: Bubble? = nil
	local bubble = session.bubble
	if bubble and now > bubble.endsAt + Sticks.CLAIM_GRACE then
		-- Nobody tapped it.
		session.bubble = nil
		session.nextBubbleAt = now + bubbleGap(session)
	elseif bubble == nil and now >= session.nextBubbleAt then
		session.bubbles += 1
		appeared = { id = session.bubbles, endsAt = now + Sticks.BUBBLE_LIFETIME }
		session.bubble = appeared
	end
	return { reps = reps, bubble = appeared }
end

-- The player tapped bubble `id` at `now`. If it is the one up and still in time, every rep for the next
-- Sticks.BOOST_DURATION seconds counts double. Returns whether it counted.
function Training.claim(session: Session, id: number, now: number): boolean
	local bubble = session.bubble
	if bubble == nil or bubble.id ~= id or now > bubble.endsAt + Sticks.CLAIM_GRACE then
		return false
	end
	session.bubble = nil
	session.boostFrom = now
	session.boostUntil = now + Sticks.BOOST_DURATION
	session.nextBubbleAt = now + bubbleGap(session)
	return true
end

-- Whether a 2x boost is running at `now`.
function Training.isBoosted(session: Session, now: number): boolean
	return now >= session.boostFrom and now < session.boostUntil
end

return Training
