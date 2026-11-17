--!nocheck
-- Tests for the shared math modules.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local CycleClock = harness.load("src/shared/CycleClock")
	local EggMotion = harness.load("src/shared/EggMotion")
	local EggSpec = harness.load("src/shared/EggSpec")
	local JumpAim = harness.load("src/shared/JumpAim")
	local LuckBoost = harness.load("src/shared/LuckBoost")
	local NumberFormat = harness.load("src/shared/NumberFormat")
	local Runway = harness.load("src/shared/Runway")
	local StaminaMath = harness.load("src/shared/StaminaMath")

	describe("CycleClock", function()
		it("runs 5-minute cycles: open for 4 minutes 50 seconds, then a 10-second closure", function()
			expect.equal(CycleClock.CYCLE_LENGTH, 300)
			expect.equal(CycleClock.CLOSED_LENGTH, 10)
			expect.equal(CycleClock.CLOSE_AT, 290)

			local open = CycleClock.getState(300 * 7 + 30)
			expect.equal(open.index, 7)
			expect.equal(open.phase, "Open")
			expect.near(open.untilClose, 260)
			expect.near(open.untilNextCycle, 270)

			expect.equal(CycleClock.getState(300 * 7 + 279.9).phase, "Open")
			expect.equal(CycleClock.getState(300 * 7 + 280).phase, "Warning")
			expect.equal(CycleClock.getState(300 * 7 + 289.9).phase, "Warning")

			local closed = CycleClock.getState(300 * 7 + 290)
			expect.equal(closed.phase, "Closed")
			expect.equal(closed.untilClose, 0)
			expect.near(closed.untilNextCycle, 10)

			expect.equal(CycleClock.getState(300 * 8).index, 8)
			expect.equal(CycleClock.getState(300 * 8).phase, "Open")
		end)

		it("makes each cycle one day and one night: a 4:50 day while the runway is open, a 10-second night", function()
			local start = 300 * 12
			local dayLength = CycleClock.CYCLE_LENGTH * CycleClock.DAY_FRACTION
			local nightLength = CycleClock.CYCLE_LENGTH - dayLength
			expect.near(dayLength, 290, 1e-9)
			expect.near(nightLength, 10, 1e-9)
			-- The sun rises as the cycle begins, is highest half way through the day, and sets as the runway closes.
			expect.equal(CycleClock.clockTime(start), CycleClock.SUNRISE)
			expect.near(CycleClock.clockTime(start + dayLength / 2), 12)
			expect.near(CycleClock.clockTime(start + CycleClock.CLOSE_AT), CycleClock.SUNSET)
			expect.near(CycleClock.clockTime(start + CycleClock.CLOSE_AT - 0.001), CycleClock.SUNSET, 1e-3)
			-- Midnight comes halfway through the night (the clock runs 0 to 24, so a hair before midnight is nearly
			-- 24), and the sun is back up as the next cycle begins.
			local midnight = CycleClock.clockTime(start + dayLength + nightLength / 2)
			expect.near(math.min(midnight, 24 - midnight), 0)
			expect.truthy(CycleClock.clockTime(start + CycleClock.CLOSE_AT + 6) < CycleClock.SUNRISE)
			-- (The whole night goes by in 10 seconds, so the clock is racing here.)
			expect.near(CycleClock.clockTime(start + 299.999), CycleClock.SUNRISE, 0.01)

			expect.equal(CycleClock.daylight(start + dayLength / 2), 1)
			expect.equal(CycleClock.daylight(start + dayLength + nightLength / 2), 0)
			expect.near(CycleClock.daylight(start), 0.5)
			-- Broad daylight for most of the day: it only starts to fade in the last minute before the runway closes.
			expect.equal(CycleClock.daylight(start + 60), 1)
			expect.equal(CycleClock.daylight(start + CycleClock.CLOSE_AT - 60), 1)
			expect.truthy(CycleClock.daylight(start + CycleClock.CLOSE_AT - 10) < 1)
		end)

		it("tells the HUD whether it is day, and how long until that changes", function()
			local start = 300 * 12
			local sunset = CycleClock.CLOSE_AT
			local isDay, untilChange = CycleClock.dayNight(start + 5)
			expect.equal(isDay, true)
			expect.near(untilChange, 285)
			isDay, untilChange = CycleClock.dayNight(start + sunset - 0.5)
			expect.equal(isDay, true, "day right up to the closure")
			expect.near(untilChange, 0.5)
			isDay, untilChange = CycleClock.dayNight(start + sunset)
			expect.equal(isDay, false, "night falls as the runway closes")
			expect.near(untilChange, 10, 1e-9, "until the next sunrise")
			isDay, untilChange = CycleClock.dayNight(start + CycleClock.CLOSE_AT + 2)
			expect.equal(isDay, false, "night while the runway is closed")
			expect.near(untilChange, CycleClock.CLOSED_LENGTH - 2)
			-- It is night exactly when the runway is closed.
			for second = 0, 299 do
				local closed = CycleClock.getState(start + second + 0.5).phase == "Closed"
				expect.equal(CycleClock.dayNight(start + second + 0.5), not closed, "at " .. second)
			end
		end)

		it("schedules each event once an hour, 30 minutes apart", function()
			expect.equal(CycleClock.EVENT_PERIOD * CycleClock.CYCLE_LENGTH, 3600)
			expect.equal((CycleClock.AVALANCHE_CYCLE - CycleClock.TITAN_CYCLE) * CycleClock.CYCLE_LENGTH, 1800)
			local titans, avalanches = 0, 0
			for index = 0, 23 do
				local event = CycleClock.eventForCycle(index)
				if event == "Titan" then
					titans += 1
				elseif event == "Avalanche" then
					avalanches += 1
				end
			end
			-- 24 cycles x 5 minutes = 2 hours.
			expect.equal(titans, 2)
			expect.equal(avalanches, 2)
			expect.equal(CycleClock.eventForCycle(12), "Titan")
			expect.equal(CycleClock.eventForCycle(18), "Avalanche")
			expect.equal(CycleClock.eventForCycle(15), nil)
		end)

		it("can be moved ahead, for every device at once", function()
			local time = 300 * 7 + 30
			expect.equal(CycleClock.getOffset(), 0)
			CycleClock.setOffset(260)
			local moved = CycleClock.getState(time)
			CycleClock.setOffset(0)
			expect.equal(moved.phase, "Closed", "260 s on, the runway has closed")
			expect.equal(moved.index, 7)
			expect.equal(CycleClock.getState(time).phase, "Open", "and back")
		end)
	end)

	describe("Showroom", function()
		local Showroom = harness.load("src/shared/Showroom")

		it("is far from the hub and the runway, level with the hub", function()
			expect.truthy(math.abs(Showroom.X) - Runway.HUB_WIDTH / 2 >= 2000, "well away from the hub")
			expect.equal(Showroom.FLOOR_Y, Runway.BASE_Y)
			expect.truthy(Showroom.contains(Showroom.X + 100, Showroom.Z + 200))
			expect.falsy(Showroom.contains(0, 0), "the hub is not in it")
			expect.falsy(Showroom.contains(0, 1500), "nor is the runway")
			local x, y, z = Showroom.arrivalPoint()
			expect.equal(x, Showroom.X)
			expect.equal(y, Showroom.FLOOR_Y)
			expect.truthy(z < Showroom.Z, "arrive in front of the displays")
		end)
	end)

	describe("Runway", function()
		it("is level and wide all the way from the hub to the end", function()
			expect.equal(Runway.surfaceY(-50), Runway.BASE_Y)
			expect.equal(Runway.surfaceY(0), Runway.BASE_Y)
			expect.equal(Runway.surfaceY(1800), Runway.BASE_Y)
			expect.equal(Runway.surfaceY(Runway.LENGTH), Runway.BASE_Y)
		end)

		it("gets wider zone by zone, then keeps the last zone's width through its endless repeats", function()
			expect.equal(Runway.START_WIDTH, 120)
			expect.equal(Runway.widthAt(-10), Runway.START_WIDTH, "where it leaves the hub")
			expect.equal(Runway.widthAt(0), Runway.START_WIDTH)
			for zoneId = 2, Runway.ZONE_COUNT do
				local start = Runway.zoneStartZ(zoneId)
				expect.truthy(Runway.widthAt(start) > Runway.widthAt(start - 1), `zone {zoneId} is wider`)
				expect.equal(Runway.widthAt(start), Runway.zoneWidth(zoneId))
				expect.equal(Runway.widthAt(start + Runway.ZONE_LENGTH - 1), Runway.zoneWidth(zoneId), "all along it")
				expect.equal(Runway.zoneWidth(zoneId) % 20, 0, "a whole number of ground tiles")
			end
			expect.equal(Runway.zoneWidth(Runway.ZONE_COUNT), Runway.MAX_WIDTH)
			-- The last zone's copies, and everywhere an egg can be carried back to, are as wide as it.
			for _, z in { Runway.FINAL_ZONE_START, Runway.LENGTH, Runway.LOOP_START, Runway.LOOP_END, 1e6 } do
				expect.equal(Runway.widthAt(z), Runway.MAX_WIDTH, `at {z}`)
			end
			expect.equal(Runway.zoneWidth(Runway.ZONE_COUNT + 2), Runway.MAX_WIDTH)
			-- Wider runway, more room to steer.
			expect.truthy(Runway.maxLateral(4, Runway.LENGTH) > Runway.maxLateral(4, 0))
		end)

		it("knows which zone a position is in", function()
			expect.equal(Runway.zoneAt(-1), nil)
			expect.equal(Runway.zoneAt(0), 1)
			expect.equal(Runway.zoneAt(599.9), 1)
			expect.equal(Runway.zoneAt(600), 2)
			expect.equal(Runway.zoneAt(2999), 5)
			expect.equal(Runway.zoneAt(3000), 6)
			expect.equal(Runway.zoneAt(3599), 6)
			-- The last zone never ends.
			expect.equal(Runway.zoneAt(3600), 6)
			expect.equal(Runway.zoneAt(50000), 6)
			expect.equal(Runway.zoneStartZ(3), 1200)
		end)

		it("loops the last zone: anything reaching the end of the loop is carried back one loop", function()
			expect.equal(Runway.FINAL_ZONE_START, Runway.zoneStartZ(Runway.ZONE_COUNT))
			expect.equal(Runway.LOOP_LENGTH, Runway.ZONE_LENGTH)
			expect.equal(Runway.LOOP_END - Runway.LOOP_START, Runway.LOOP_LENGTH)
			expect.truthy(Runway.LOOP_START > Runway.FINAL_ZONE_START, "the loop starts inside the last zone")
			expect.truthy(Runway.LOOP_END < Runway.LENGTH + Runway.REPEATS * Runway.LOOP_LENGTH, "built that far")

			expect.equal(Runway.wrapZ(100), 100)
			expect.equal(Runway.wrapZ(Runway.LOOP_END - 1), Runway.LOOP_END - 1)
			expect.near(Runway.wrapZ(Runway.LOOP_END), Runway.LOOP_START)
			expect.near(Runway.wrapZ(Runway.LOOP_END + 10), Runway.LOOP_START + 10)
			expect.near(Runway.wrapZ(Runway.LOOP_END + 5 * Runway.LOOP_LENGTH + 10), Runway.LOOP_START + 10)
			for _, z in { 5000, 12345.6, 1e6 } do
				local wrapped = Runway.wrapZ(z)
				expect.truthy(wrapped >= Runway.LOOP_START and wrapped < Runway.LOOP_END, tostring(z))
			end
		end)

		it("draws things in the last zone at their copy nearest the viewer", function()
			local L = Runway.LOOP_LENGTH
			local final = Runway.FINAL_ZONE_START
			-- Before the last zone there is only one copy.
			expect.equal(Runway.nearestImage(1000, final + 200), 1000)
			-- A viewer near the end of the loop sees an egg just past the loop's start as one loop ahead.
			expect.equal(Runway.nearestImage(Runway.LOOP_START + 10, Runway.LOOP_END - 5), Runway.LOOP_START + 10 + L)
			expect.equal(Runway.nearestImage(Runway.LOOP_START + 10, Runway.LOOP_START), Runway.LOOP_START + 10)
			-- Never a copy before the last zone starts, even for a viewer far behind it.
			expect.equal(Runway.nearestImage(final + 50, 0), final + 50)
			expect.equal(Runway.nearestImage(final + 50 + L, 0), final + 50)
			-- The copy chosen is always within half a loop of the viewer (when the viewer is on the loop).
			for viewer = Runway.LOOP_START, Runway.LOOP_END, 37 do
				for z = final, Runway.LOOP_END, 53 do
					expect.truthy(math.abs(Runway.nearestImage(z, viewer) - viewer) <= L / 2 + 1e-9)
				end
			end
		end)

		it(
			"fades the last zone's riderless eggs a quarter of the way into its first copy, before the loop ends",
			function()
				expect.equal(Runway.fadeZ(1), 750)
				local last = Runway.fadeZ(Runway.ZONE_COUNT)
				expect.equal(last, Runway.LENGTH + Runway.ZONE_LENGTH / 4)
				expect.truthy(last < Runway.LOOP_END)
			end
		)

		it("knows when an egg is pressed against the side", function()
			for _, z in { 10, Runway.zoneStartZ(4) + 10, Runway.LOOP_END - 10 } do
				local limit = Runway.maxLateral(4, z)
				expect.equal(Runway.isAtEdge(limit, 4, z), true)
				expect.equal(Runway.isAtEdge(-limit, 4, z), true)
				expect.equal(Runway.isAtEdge(limit - 1, 4, z), false)
			end
			-- Pressed against the first zone's bank is well clear of the wider zone's.
			expect.equal(Runway.isAtEdge(Runway.maxLateral(4, 10), 4, Runway.zoneStartZ(2) + 10), false)
		end)

		it("keeps eggs on the runway", function()
			for _, z in { 10, Runway.zoneStartZ(3) + 10, Runway.LENGTH + 10 } do
				local limit = Runway.maxLateral(4, z)
				expect.near(limit, Runway.widthAt(z) / 2 - 5)
				expect.equal(Runway.clampLateral(999, 4, z), limit)
				expect.equal(Runway.clampLateral(-999, 4, z), -limit)
				expect.equal(Runway.clampLateral(3, 4, z), 3)
			end
		end)
	end)

	describe("EggMotion", function()
		it("rolls at a steady speed from the spawn point", function()
			expect.equal(EggMotion.zAt(100, 612, 12, 100), 612)
			expect.equal(EggMotion.zAt(100, 612, 12, 110), 732)
			-- Never behind its starting point, even if a client's clock is slightly behind.
			expect.equal(EggMotion.zAt(100, 612, 12, 99), 612)
		end)

		it("bounces once, slightly, before cracking", function()
			expect.equal(EggMotion.bounceOffset(nil, 10, 0.6, 2.5), 0)
			expect.equal(EggMotion.bounceOffset(10, 10, 0.6, 2.5), 0)
			expect.near(EggMotion.bounceOffset(10, 10.3, 0.6, 2.5), 2.5)
			expect.near(EggMotion.bounceOffset(10, 10.6, 0.6, 2.5), 0, 1e-9)
			expect.equal(EggMotion.bounceOffset(10, 12, 0.6, 2.5), 0)
		end)

		it("turns one full circle per circumference rolled", function()
			expect.near(EggMotion.rollAngle(2 * math.pi * 3, 3), 2 * math.pi)
		end)
	end)

	describe("StaminaMath", function()
		it("regenerates up to the maximum and drains down to zero", function()
			expect.equal(StaminaMath.current(40, 100, 12, 100, 100), 40)
			expect.equal(StaminaMath.current(40, 100, 12, 100, 102), 64)
			expect.equal(StaminaMath.current(40, 100, 12, 100, 200), 100)
			expect.equal(StaminaMath.current(40, 100, -8, 100, 102), 24)
			expect.equal(StaminaMath.current(40, 100, -8, 100, 200), 0)
		end)

		it("drains 80% of the requirement over the claim time", function()
			expect.near(StaminaMath.drainRate(50, 5, 0.8), 8)
			expect.near(StaminaMath.timeUntilEmpty(100, 8), 12.5)
			expect.equal(StaminaMath.timeUntilEmpty(100, 0), math.huge)
		end)
	end)

	describe("NumberFormat", function()
		it("abbreviates big numbers", function()
			expect.equal(NumberFormat.abbreviate(0), "0")
			expect.equal(NumberFormat.abbreviate(950), "950")
			expect.equal(NumberFormat.abbreviate(999.9), "999")
			expect.equal(NumberFormat.abbreviate(1000), "1K")
			expect.equal(NumberFormat.abbreviate(1250), "1.25K")
			expect.equal(NumberFormat.abbreviate(12500), "12.5K")
			expect.equal(NumberFormat.abbreviate(30000), "30K")
			expect.equal(NumberFormat.abbreviate(150000), "150K")
			expect.equal(NumberFormat.abbreviate(999999), "999K")
			expect.equal(NumberFormat.abbreviate(4500000), "4.5M")
			expect.equal(NumberFormat.abbreviate(2.5e9), "2.5B")
			expect.equal(NumberFormat.abbreviate(-1500), "-1.5K")
		end)

		it("formats countdowns", function()
			expect.equal(NumberFormat.clock(0), "0:00")
			expect.equal(NumberFormat.clock(9.2), "0:10")
			expect.equal(NumberFormat.clock(133), "2:13")
			expect.equal(NumberFormat.countdown(0), "0s")
			expect.equal(NumberFormat.countdown(44.2), "45s")
			expect.equal(NumberFormat.countdown(60), "1m")
			expect.equal(NumberFormat.countdown(80), "1m 20s")
			expect.equal(NumberFormat.countdown(121), "2m 1s")
		end)
	end)

	describe("LuckBoost", function()
		it("runs a boost for its duration", function()
			local boosts = LuckBoost.add({}, 2, 900, 100)
			expect.equal(LuckBoost.current(boosts, 100), 2)
			local luck, endsAt = LuckBoost.current(boosts, 500)
			expect.equal(luck, 2)
			expect.equal(endsAt, 1000)
			expect.equal(LuckBoost.current(boosts, 1000), 1)
			expect.equal(select(2, LuckBoost.current(boosts, 1000)), nil)
		end)

		it("adds the time of a boost bought while the same one is running", function()
			local boosts = LuckBoost.add({}, 2, 900, 0)
			LuckBoost.add(boosts, 2, 900, 300)
			expect.equal(#boosts, 1)
			expect.equal(boosts[1].endsAt, 1800)
		end)

		it("uses the strongest boost, keeping a weaker one waiting underneath", function()
			local boosts = LuckBoost.add({}, 2, 900, 0)
			LuckBoost.add(boosts, 4, 300, 100)
			local luck, endsAt = LuckBoost.current(boosts, 200)
			expect.equal(luck, 4)
			expect.equal(endsAt, 400)
			-- The x4 runs out; the x2 still has its time left.
			luck, endsAt = LuckBoost.current(boosts, 401)
			expect.equal(luck, 2)
			expect.equal(endsAt, 900)
		end)

		it("forgets boosts that have run out", function()
			local boosts = LuckBoost.add({}, 2, 10, 0)
			LuckBoost.add(boosts, 4, 100, 0)
			LuckBoost.prune(boosts, 50)
			expect.equal(#boosts, 1)
			expect.equal(boosts[1].multiplier, 4)
			-- An expired boost bought again starts fresh.
			LuckBoost.add(boosts, 4, 100, 500)
			expect.equal(boosts[1].endsAt, 600)
		end)
	end)

	describe("EggSpec luck", function()
		local function countRare(zoneId, luck)
			local rare = 0
			for step = 0, 9999 do
				if EggSpec.rollRarity(zoneId, step / 10000, luck) ~= "Common" then
					rare += 1
				end
			end
			return rare
		end

		it("changes nothing at luck 1", function()
			for step = 0, 999 do
				expect.equal(EggSpec.rollRarity(2, step / 1000, 1), EggSpec.rollRarity(2, step / 1000))
			end
		end)

		it("makes rarer eggs more likely without breaking the zone's rarity cap", function()
			local normal, lucky, luckier = countRare(1, 1), countRare(1, 2), countRare(1, 4)
			expect.truthy(lucky > normal, "x2 beats x1")
			expect.truthy(luckier > lucky, "x4 beats x2")
			-- Luck only reweights what a zone can drop: it never adds a rarity the zone does not have.
			local Zones = harness.load("src/shared/Config/Zones")
			for zoneId, zone in Zones.List do
				for step = 0, 999 do
					local rarity = EggSpec.rollRarity(zoneId, step / 1000, 4)
					expect.truthy((zone.weights[rarity] or 0) > 0, `{zone.name} {rarity}`)
				end
			end
		end)
	end)

	describe("Runway wall gaps", function()
		it("puts fairly large gaps in both banks of every zone, clear of the zone's start and end", function()
			for zoneId = 1, Runway.ZONE_COUNT do
				local startZ = Runway.zoneStartZ(zoneId)
				local sides = {}
				local lastEnd = { [1] = -math.huge, [-1] = -math.huge }
				for _, gap in Runway.wallGaps(zoneId) do
					expect.truthy(gap.side == 1 or gap.side == -1, "side")
					sides[gap.side] = true
					local length = gap.endZ - gap.startZ
					expect.truthy(length >= Runway.GAP_MIN_LENGTH - 1e-9, "gap of " .. length)
					expect.truthy(length <= Runway.GAP_MAX_LENGTH + 1e-9, "gap of " .. length)
					expect.truthy(
						gap.startZ >= startZ + Runway.GAPLESS_START,
						"clear of the gate and where eggs appear"
					)
					expect.truthy(
						gap.endZ <= startZ + Runway.ZONE_LENGTH - Runway.GAPLESS_END,
						"clear of the next zone"
					)
					expect.truthy(gap.startZ >= lastEnd[gap.side] + Runway.BANK_MIN_LENGTH - 1e-9, "bank between gaps")
					lastEnd[gap.side] = gap.endZ
				end
				expect.truthy(sides[1] and sides[-1], "zone " .. zoneId .. " has gaps on both sides")
			end
		end)

		it("does not repeat the same pattern in neighbouring zones", function()
			for zoneId = 2, Runway.ZONE_COUNT do
				local here = Runway.wallGaps(zoneId)[1].startZ - Runway.zoneStartZ(zoneId)
				local before = Runway.wallGaps(zoneId - 1)[1].startZ - Runway.zoneStartZ(zoneId - 1)
				expect.truthy(math.abs(here - before) > 1e-6, "zone " .. zoneId)
			end
		end)

		it("repeats the last zone's gaps in each copy of it past the end, so the loop is seamless", function()
			local last = Runway.wallGaps(Runway.ZONE_COUNT)
			for copy = 1, Runway.REPEATS do
				local gaps = Runway.wallGaps(Runway.ZONE_COUNT + copy)
				expect.equal(#gaps, #last)
				for index, gap in gaps do
					expect.equal(gap.side, last[index].side)
					expect.near(gap.startZ, last[index].startZ + copy * Runway.LOOP_LENGTH, 1e-9)
				end
			end
		end)

		it("tells a bank from a gap at an egg's position", function()
			local gap = Runway.wallGaps(2)[1]
			local middle = (gap.startZ + gap.endZ) / 2
			expect.equal(Runway.wallAt(gap.side, middle, 3), false)
			expect.equal(Runway.wallAt(-gap.side, middle, 3) or Runway.wallAt(gap.side, gap.startZ + 1, 3), true)
			-- An egg wider than what is left of the gap touches the bank beside it.
			expect.equal(Runway.wallAt(gap.side, gap.startZ + 1, 3), true)
			-- The gate's stretch has no gaps.
			expect.equal(Runway.wallAt(1, Runway.zoneStartZ(3) + 10, 3), true)
			expect.equal(Runway.wallAt(-1, Runway.zoneStartZ(3) + 10, 3), true)
		end)
	end)

	describe("JumpAim", function()
		-- A Common-sized egg at the middle of the runway, 100 studs down it, rolling at 27 studs a second.
		local function egg(id, x, z, speed)
			return { id = id, x = x, z = z, seatY = 18, speed = speed or 0, halfLength = 3.9, radius = 3 }
		end
		local function jumper(x, y, z, vx, vy, vz, gravity)
			return { x = x, y = y, z = z, vx = vx or 0, vy = vy or 0, vz = vz or 0, gravity = gravity or 0 }
		end

		it("works out when a jump comes back down to a height", function()
			-- Dropped from 20 studs up with gravity 10: sqrt(2 * 20 / 10) = 2 s.
			expect.near(JumpAim.timeToHeight(20, 0, 10, 0), 2)
			-- Thrown up at 10 from the ground: back down after 2 s.
			expect.near(JumpAim.timeToHeight(0, 10, 10, 0), 2)
			-- Below the height and never rising to it, or no gravity: where it is now.
			expect.equal(JumpAim.timeToHeight(0, 1, 10, 5), 0)
			expect.equal(JumpAim.timeToHeight(5, -3, 0, 0), 0)
		end)

		it("measures how far outside an egg's footprint a spot is", function()
			expect.equal(JumpAim.footprintGap(0, 0, 4, 3), 0)
			expect.equal(JumpAim.footprintGap(3.9, -2.9, 4, 3), 0, "inside, near a corner")
			expect.near(JumpAim.footprintGap(10, 0, 4, 3), 6, 1e-9)
			expect.near(JumpAim.footprintGap(0, -8, 4, 3), 5, 1e-9)
			expect.near(JumpAim.footprintGap(7, 7, 4, 3), 5, 1e-9)
		end)

		it("picks the egg a jump will come down on, allowing for the eggs rolling on meanwhile", function()
			-- Falling straight down from 38 studs with gravity 10: lands at the seat height after 2 s. The egg 40 studs
			-- behind rolls under them at 20 studs a second; the one right below now has rolled 40 studs on by then.
			local falling = jumper(0, 38, 100, 0, 0, 0, 10)
			local below = egg(1, 0, 100, 20)
			local behind = egg(2, 0, 60, 20)
			expect.equal(JumpAim.pick(falling, { below, behind }, nil, 14, 3, 3), 2)
			expect.near(JumpAim.miss(falling, behind, 3), 0, 1e-9)
			-- Moving forward with the eggs, the one below stays below.
			local riding = jumper(0, 38, 100, 0, 0, 20, 10)
			expect.equal(JumpAim.pick(riding, { below, behind }, nil, 14, 3, 3), 1)
			-- Nothing near where the jump comes down: no egg.
			expect.equal(JumpAim.pick(jumper(0, 38, 100, 40, 0, 0, 10), { below, behind }, nil, 14, 3, 3), nil)
			-- Judged from where they are now when there is no gravity (a player on a pet).
			expect.equal(JumpAim.pick(jumper(10, 40, 100), { egg(1, 0, 100), egg(2, 0, 60) }, nil, 14, 3, 3), 1)
		end)

		it("keeps the egg it picked unless another is clearly nearer", function()
			local here = jumper(0, 18, 100)
			local left = egg(1, -9, 100)
			local right = egg(2, 10, 100)
			-- Left is 1 stud nearer than right: it wins from scratch, but does not take over from right.
			expect.equal(JumpAim.pick(here, { left, right }, nil, 14, 3, 3), 1)
			expect.equal(JumpAim.pick(here, { left, right }, 2, 14, 3, 3), 2)
			-- Clearly nearer: it takes over.
			expect.equal(JumpAim.pick(here, { egg(1, -5, 100), right }, 2, 14, 3, 3), 1)
			-- An egg picked last frame that has gone (or is out of range) is dropped.
			expect.equal(JumpAim.pick(here, { left }, 2, 14, 3, 3), 1)
			expect.equal(JumpAim.pick(here, { left, egg(2, 40, 100) }, 2, 14, 3, 3), 1)
		end)

		it("takes hold of a jumper close to the egg, not far off, far above it, or below its middle", function()
			local target = egg(1, 0, 100)
			expect.truthy(JumpAim.inMagnetRange(jumper(0, 18, 100), target, 10, 20), "on top")
			expect.truthy(JumpAim.inMagnetRange(jumper(12, 30, 100), target, 10, 20), "close by, above")
			expect.falsy(JumpAim.inMagnetRange(jumper(16, 18, 100), target, 10, 20), "too far across")
			expect.falsy(JumpAim.inMagnetRange(jumper(0, 18, 115), target, 10, 20), "too far ahead")
			expect.falsy(JumpAim.inMagnetRange(jumper(0, 39, 100), target, 10, 20), "too high")
			-- The seat is 18; the egg's middle is 18 - radius - 2 = 13.
			expect.truthy(JumpAim.inMagnetRange(jumper(0, 13.5, 100), target, 10, 20), "level with it")
			expect.falsy(JumpAim.inMagnetRange(jumper(0, 12, 100), target, 10, 20), "below its middle")
		end)

		it("draws the jumper onto the egg's top, moving with it", function()
			local target = egg(1, 0, 100, 27)
			-- Right on the seat: just roll along with the egg.
			local x, y, z = JumpAim.pull(jumper(0, 18, 100), target, 9, 70)
			expect.near(x, 0, 1e-9)
			expect.near(y, 0, 1e-9)
			expect.near(z, 27, 1e-9)
			-- A little way off: pulled toward the seat in proportion.
			x, y, z = JumpAim.pull(jumper(2, 19, 100), target, 9, 70)
			expect.near(x, -18, 1e-9)
			expect.near(y, -9, 1e-9)
			expect.near(z, 27, 1e-9)
			-- Far off: the pull is capped, but the egg's own speed is always added.
			x, y, z = JumpAim.pull(jumper(30, 18, 100), target, 9, 70)
			expect.near(x, -70, 1e-9)
			expect.near(z, 27, 1e-9)
			-- Following the pull closes in on the seat within a fraction of a second.
			local at = jumper(8, 26, 96)
			local eggZ = 100
			for _ = 1, 20 do
				local vx, vy, vz = JumpAim.pull(at, egg(1, 0, eggZ, 27), 9, 70)
				at.x += vx / 60
				at.y += vy / 60
				at.z += vz / 60
				eggZ += 27 / 60
			end
			expect.truthy(JumpAim.footprintGap(at.x, at.z - eggZ, 0, 0) < 1, "within a stud after a third of a second")
			expect.truthy(math.abs(at.y - 18) < 1, "and at the seat's height")
		end)
	end)
end
