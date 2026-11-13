--!nocheck
-- Tests for the shared math modules.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local CycleClock = harness.load("src/shared/CycleClock")
	local EggMotion = harness.load("src/shared/EggMotion")
	local EggSpec = harness.load("src/shared/EggSpec")
	local LuckBoost = harness.load("src/shared/LuckBoost")
	local NumberFormat = harness.load("src/shared/NumberFormat")
	local Runway = harness.load("src/shared/Runway")
	local StaminaMath = harness.load("src/shared/StaminaMath")

	describe("CycleClock", function()
		it("runs 3-minute cycles that end with a 10-second closure", function()
			expect.equal(CycleClock.CYCLE_LENGTH, 180)
			expect.equal(CycleClock.CLOSED_LENGTH, 10)

			local open = CycleClock.getState(180 * 7 + 30)
			expect.equal(open.index, 7)
			expect.equal(open.phase, "Open")
			expect.near(open.untilClose, 140)
			expect.near(open.untilNextCycle, 150)

			expect.equal(CycleClock.getState(180 * 7 + 159.9).phase, "Open")
			expect.equal(CycleClock.getState(180 * 7 + 160).phase, "Warning")
			expect.equal(CycleClock.getState(180 * 7 + 169.9).phase, "Warning")

			local closed = CycleClock.getState(180 * 7 + 170)
			expect.equal(closed.phase, "Closed")
			expect.equal(closed.untilClose, 0)
			expect.near(closed.untilNextCycle, 10)

			expect.equal(CycleClock.getState(180 * 8).index, 8)
			expect.equal(CycleClock.getState(180 * 8).phase, "Open")
		end)

		it("schedules each event once an hour, 30 minutes apart", function()
			local titans, avalanches = 0, 0
			for index = 0, 39 do
				local event = CycleClock.eventForCycle(index)
				if event == "Titan" then
					titans += 1
				elseif event == "Avalanche" then
					avalanches += 1
				end
			end
			-- 40 cycles x 3 minutes = 2 hours.
			expect.equal(titans, 2)
			expect.equal(avalanches, 2)
			expect.equal(CycleClock.eventForCycle(20), "Titan")
			expect.equal(CycleClock.eventForCycle(30), "Avalanche")
			expect.equal(CycleClock.eventForCycle(25), nil)
		end)
	end)

	describe("Runway", function()
		it("is flat at the hub and slopes down along the runway", function()
			expect.equal(Runway.surfaceY(-50), Runway.BASE_Y)
			expect.equal(Runway.surfaceY(0), Runway.BASE_Y)
			expect.near(Runway.surfaceY(100), Runway.BASE_Y - 4)
			expect.near(Runway.surfaceY(Runway.LENGTH + 500), Runway.BASE_Y - Runway.SLOPE * Runway.LENGTH)
		end)

		it("knows which zone a position is in", function()
			expect.equal(Runway.zoneAt(-1), nil)
			expect.equal(Runway.zoneAt(0), 1)
			expect.equal(Runway.zoneAt(599.9), 1)
			expect.equal(Runway.zoneAt(600), 2)
			expect.equal(Runway.zoneAt(2999), 5)
			expect.equal(Runway.zoneAt(3000), nil)
			expect.equal(Runway.zoneStartZ(3), 1200)
		end)

		it("keeps eggs on the runway", function()
			local limit = Runway.maxLateral(4)
			expect.near(limit, Runway.WIDTH / 2 - 5)
			expect.equal(Runway.clampLateral(999, 4), limit)
			expect.equal(Runway.clampLateral(-999, 4), -limit)
			expect.equal(Runway.clampLateral(3, 4), 3)
		end)
	end)

	describe("EggMotion", function()
		it("rolls at a steady speed from the spawn point", function()
			expect.equal(EggMotion.zAt(100, 612, 12, 100), 612)
			expect.equal(EggMotion.zAt(100, 612, 12, 110), 732)
			-- Never behind its starting point, even if a client's clock is slightly behind.
			expect.equal(EggMotion.zAt(100, 612, 12, 99), 612)
		end)

		it("drops in from above and then stays on the ground", function()
			expect.equal(EggMotion.dropOffset(0, 0.6, 24), 24)
			expect.truthy(EggMotion.dropOffset(0.3, 0.6, 24) < 24)
			expect.equal(EggMotion.dropOffset(0.6, 0.6, 24), 0)
			expect.equal(EggMotion.dropOffset(5, 0.6, 24), 0)
		end)

		it("hops once when left without a rider", function()
			expect.equal(EggMotion.hopOffset(nil, 10, 0.7, 5), 0)
			expect.equal(EggMotion.hopOffset(10, 10, 0.7, 5), 0)
			expect.near(EggMotion.hopOffset(10, 10.35, 0.7, 5), 5)
			expect.near(EggMotion.hopOffset(10, 10.7, 0.7, 5), 0, 1e-9)
			expect.equal(EggMotion.hopOffset(10, 12, 0.7, 5), 0)
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
			for step = 0, 999 do
				local rarity = EggSpec.rollRarity(1, step / 1000, 4)
				expect.truthy(rarity ~= "Mythic" and rarity ~= "Secret" and rarity ~= "Eternal", rarity)
			end
		end)
	end)

	describe("Runway wall gaps", function()
		it("puts gaps in both walls of every zone, clear of the zone's start and end", function()
			for zoneId = 1, Runway.ZONE_COUNT do
				local startZ = Runway.zoneStartZ(zoneId)
				local sides = {}
				local lastEnd = { [1] = -math.huge, [-1] = -math.huge }
				for _, gap in Runway.wallGaps(zoneId) do
					expect.truthy(gap.side == 1 or gap.side == -1, "side")
					sides[gap.side] = true
					expect.near(gap.endZ - gap.startZ, Runway.WALL_GAP_LENGTH)
					expect.truthy(gap.startZ >= startZ + 60, "clear of the sign and egg drop")
					expect.truthy(gap.endZ <= startZ + Runway.ZONE_LENGTH - 30, "clear of the next zone")
					expect.truthy(gap.startZ > lastEnd[gap.side], "gaps on one side do not overlap")
					lastEnd[gap.side] = gap.endZ
				end
				expect.truthy(sides[1] and sides[-1], "zone " .. zoneId .. " has gaps on both sides")
			end
		end)

		it("does not repeat the same pattern in neighbouring zones", function()
			for zoneId = 2, Runway.ZONE_COUNT do
				expect.truthy(Runway.wallGaps(zoneId)[1].side ~= Runway.wallGaps(zoneId - 1)[1].side, "zone " .. zoneId)
			end
		end)
	end)
end
