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
			-- No end: the slope carries on past the last zone.
			expect.near(Runway.surfaceY(Runway.LENGTH + 500), Runway.BASE_Y - Runway.SLOPE * (Runway.LENGTH + 500))
		end)

		it("knows which zone a position is in", function()
			expect.equal(Runway.zoneAt(-1), nil)
			expect.equal(Runway.zoneAt(0), 1)
			expect.equal(Runway.zoneAt(599.9), 1)
			expect.equal(Runway.zoneAt(600), 2)
			expect.equal(Runway.zoneAt(2999), 5)
			-- The last zone never ends.
			expect.equal(Runway.zoneAt(3000), 5)
			expect.equal(Runway.zoneAt(50000), 5)
			expect.equal(Runway.zoneStartZ(3), 1200)
		end)

		it("loops the last zone: anything reaching the end of the loop is carried back one loop", function()
			expect.equal(Runway.FINAL_ZONE_START, 2400)
			expect.equal(Runway.LOOP_LENGTH, 600)
			expect.equal(Runway.LOOP_END - Runway.LOOP_START, Runway.LOOP_LENGTH)
			expect.truthy(Runway.LOOP_START > Runway.FINAL_ZONE_START, "the loop starts inside the last zone")
			expect.near(Runway.LOOP_RISE, Runway.surfaceY(Runway.LOOP_START) - Runway.surfaceY(Runway.LOOP_END))

			expect.equal(Runway.wrapZ(100), 100)
			expect.equal(Runway.wrapZ(Runway.LOOP_END - 1), Runway.LOOP_END - 1)
			expect.near(Runway.wrapZ(Runway.LOOP_END), Runway.LOOP_START)
			expect.near(Runway.wrapZ(Runway.LOOP_END + 10), Runway.LOOP_START + 10)
			expect.near(Runway.wrapZ(Runway.LOOP_END + 5 * Runway.LOOP_LENGTH + 10), Runway.LOOP_START + 10)
			-- Never anywhere but inside the loop once past it, however far it has rolled.
			for _, z in { 5000, 12345.6, 1e6 } do
				local wrapped = Runway.wrapZ(z)
				expect.truthy(wrapped >= Runway.LOOP_START and wrapped < Runway.LOOP_END, tostring(z))
			end
		end)

		it("draws things in the last zone at their copy nearest the viewer", function()
			local L = Runway.LOOP_LENGTH
			-- Before the last zone there is only one copy.
			expect.equal(Runway.nearestImage(1000, 3200), 1000)
			-- A viewer near the end of the loop sees an egg just past the loop's start as one loop ahead.
			expect.equal(Runway.nearestImage(Runway.LOOP_START + 10, Runway.LOOP_END - 5), Runway.LOOP_START + 10 + L)
			expect.equal(Runway.nearestImage(Runway.LOOP_START + 10, Runway.LOOP_START), Runway.LOOP_START + 10)
			-- Never a copy before the last zone starts, even for a viewer far behind it.
			expect.equal(Runway.nearestImage(2450, 0), 2450)
			expect.equal(Runway.nearestImage(2450 + L, 0), 2450)
			-- The copy chosen is always within half a loop of the viewer (when the viewer is on the loop).
			for viewer = Runway.LOOP_START, Runway.LOOP_END, 37 do
				for z = Runway.FINAL_ZONE_START, Runway.LOOP_END, 53 do
					expect.truthy(math.abs(Runway.nearestImage(z, viewer) - viewer) <= L / 2 + 1e-9)
				end
			end
		end)

		it("lines both sides with walls and fairly large gaps", function()
			for _, side in { -1, 1 } do
				local walls = Runway.wallsBetween(side, 0, Runway.LENGTH + Runway.RUNOUT)
				expect.truthy(#walls > 20, "walls on side " .. side)
				for index, wall in walls do
					local length = wall.endZ - wall.startZ
					-- Walls cut at the end of the stretch asked for can be shorter.
					if wall.endZ < Runway.LENGTH + Runway.RUNOUT then
						expect.truthy(length >= Runway.WALL_MIN_LENGTH - 1e-9, "wall length " .. length)
					end
					expect.truthy(length <= Runway.WALL_MAX_LENGTH + 1e-9, "wall length " .. length)
					expect.truthy(wall.height >= Runway.WALL_MIN_HEIGHT and wall.height <= Runway.WALL_MAX_HEIGHT)
					local nextWall = walls[index + 1]
					if nextWall then
						local gap = nextWall.startZ - wall.endZ
						expect.truthy(gap >= Runway.GAP_MIN_LENGTH - 1e-9, "gap of " .. gap .. " at z " .. wall.endZ)
						expect.truthy(gap <= Runway.GAP_MAX_LENGTH + 1e-9, "gap of " .. gap .. " at z " .. wall.endZ)
					end
				end
			end
			-- Both sides are different.
			local left, right = Runway.wallsBetween(-1, 0, 600), Runway.wallsBetween(1, 0, 600)
			expect.truthy(left[1].endZ ~= right[1].endZ)
		end)

		it("repeats the last zone's walls every loop, so being carried back is seamless", function()
			for _, side in { -1, 1 } do
				for z = Runway.FINAL_ZONE_START, Runway.LOOP_END + Runway.LOOP_VIEW, 7 do
					expect.equal(
						Runway.wallAt(side, z, 0.5),
						Runway.wallAt(side, z + Runway.LOOP_LENGTH, 0.5),
						"z " .. z
					)
				end
			end
		end)

		it("tells a wall from a gap at an egg's position", function()
			local wall = Runway.wallsBetween(1, 0, 600)[1]
			local middle = (wall.startZ + wall.endZ) / 2
			expect.equal(Runway.wallAt(1, middle, 3), true)
			local nextWall = Runway.wallsBetween(1, wall.endZ, 600)[1]
			local gapMiddle = (wall.endZ + nextWall.startZ) / 2
			expect.equal(Runway.wallAt(1, gapMiddle, 3), false)
			-- An egg wider than what is left of the gap touches the wall beside it.
			expect.equal(Runway.wallAt(1, wall.endZ + 2, 3), true)
		end)

		it("knows when an egg is pressed against the side", function()
			local limit = Runway.maxLateral(4)
			expect.equal(Runway.isAtEdge(limit, 4), true)
			expect.equal(Runway.isAtEdge(-limit, 4), true)
			expect.equal(Runway.isAtEdge(limit - 1, 4), false)
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
		end)
	end)
end
