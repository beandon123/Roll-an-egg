--!nocheck
-- Tests for the shared math modules.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local CycleClock = harness.load("src/shared/CycleClock")
	local EggMotion = harness.load("src/shared/EggMotion")
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

		it("makes each cycle one day: sunrise as it begins, night before it ends", function()
			local start = 180 * 12
			expect.equal(CycleClock.clockTime(start), CycleClock.SUNRISE)
			expect.near(CycleClock.clockTime(start + 180 * CycleClock.DAY_FRACTION / 2), 12)
			expect.near(CycleClock.clockTime(start + 180 * CycleClock.DAY_FRACTION), CycleClock.SUNSET)
			-- Midnight comes halfway through the night, and the runway closes before dawn.
			local nightLength = 180 * (1 - CycleClock.DAY_FRACTION)
			expect.near(CycleClock.clockTime(start + 180 * CycleClock.DAY_FRACTION + nightLength / 2), 0)
			expect.truthy(CycleClock.clockTime(start + CycleClock.CLOSE_AT) < CycleClock.SUNRISE)
			expect.near(CycleClock.clockTime(start + 179.999), CycleClock.SUNRISE, 1e-3)

			expect.equal(CycleClock.daylight(start + 180 * CycleClock.DAY_FRACTION / 2), 1)
			expect.equal(CycleClock.daylight(start + 180 * CycleClock.DAY_FRACTION + nightLength / 2), 0)
			expect.near(CycleClock.daylight(start), 0.5)
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
		it("is level and wide all the way from the hub to the end", function()
			expect.equal(Runway.surfaceY(-50), Runway.BASE_Y)
			expect.equal(Runway.surfaceY(0), Runway.BASE_Y)
			expect.equal(Runway.surfaceY(1800), Runway.BASE_Y)
			expect.equal(Runway.surfaceY(Runway.LENGTH), Runway.BASE_Y)
			expect.equal(Runway.WIDTH, 120)
		end)

		it("knows which zone a position is in", function()
			expect.equal(Runway.zoneAt(-1), nil)
			expect.equal(Runway.zoneAt(0), 1)
			expect.equal(Runway.zoneAt(599.9), 1)
			expect.equal(Runway.zoneAt(600), 2)
			expect.equal(Runway.zoneAt(2999), 5)
			expect.equal(Runway.zoneAt(3000), 6)
			expect.equal(Runway.zoneAt(3599), 6)
			expect.equal(Runway.zoneAt(3600), nil)
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
end
