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
		it("leaves the hub level, straight and dead ahead", function()
			expect.equal(Runway.surfaceY(-50), Runway.BASE_Y)
			expect.equal(Runway.surfaceY(0), Runway.BASE_Y)
			expect.equal(Runway.heading(-50), 0)
			expect.equal(Runway.heading(0), 0)
			expect.equal(Runway.WIDTH, Runway.ZONE_WIDTHS[1])
			-- In the hub, and for the first stretch beside its cliffs, runway and world coordinates are the same.
			for _, spot in { { 0, -200 }, { 30, -10 }, { -40, 0 }, { 25, 60 } } do
				local worldX, worldY, worldZ = Runway.toWorld(spot[1], spot[2])
				expect.near(worldX, spot[1], 1e-9)
				expect.near(worldY, Runway.BASE_Y, 1e-9)
				expect.near(worldZ, spot[2], 1e-9)
			end
		end)

		it("makes every zone longer and wider than the one before", function()
			expect.equal(#Runway.ZONE_LENGTHS, Runway.ZONE_COUNT)
			expect.equal(#Runway.ZONE_WIDTHS, Runway.ZONE_COUNT)
			expect.equal(Runway.zoneLength(1), 800)
			expect.equal(Runway.zoneLength(Runway.ZONE_COUNT), 2600)
			local total = 0
			for zoneId = 1, Runway.ZONE_COUNT do
				expect.equal(Runway.zoneStartZ(zoneId), total)
				total += Runway.zoneLength(zoneId)
				if zoneId > 1 then
					expect.truthy(Runway.zoneLength(zoneId) > Runway.zoneLength(zoneId - 1), "longer: zone " .. zoneId)
					expect.truthy(Runway.zoneWidth(zoneId) > Runway.zoneWidth(zoneId - 1), "wider: zone " .. zoneId)
				end
			end
			expect.equal(Runway.LENGTH, total)
			-- The copies of the last zone are as long and wide as it is.
			expect.equal(Runway.zoneLength(Runway.ZONE_COUNT + 2), Runway.zoneLength(Runway.ZONE_COUNT))
			expect.equal(Runway.zoneStartZ(Runway.ZONE_COUNT + 2), Runway.LENGTH + Runway.LOOP_LENGTH)
		end)

		it("is each zone's width from its gate on, widening to the next zone's over the zone's last stretch", function()
			for zoneId = 1, Runway.ZONE_COUNT do
				local startZ = Runway.zoneStartZ(zoneId)
				local endZ = startZ + Runway.zoneLength(zoneId)
				expect.equal(Runway.widthAt(startZ), Runway.zoneWidth(zoneId))
				expect.equal(Runway.widthAt(endZ - Runway.WIDTH_TAPER), Runway.zoneWidth(zoneId))
				expect.near(Runway.widthAt(endZ - 1e-6), Runway.zoneWidth(zoneId + 1), 1e-6)
			end
			expect.equal(Runway.widthAt(-100), Runway.WIDTH)
			expect.equal(Runway.widthAt(Runway.LENGTH + 5000), Runway.MAX_WIDTH)
			-- It never narrows: an egg nobody is riding keeps its lane all the way.
			local last = 0
			for z = -50, Runway.LENGTH + Runway.LOOP_LENGTH, 7 do
				local width = Runway.widthAt(z)
				expect.truthy(width >= last, "narrower at " .. z)
				expect.equal(Runway.halfWidthAt(z), width / 2)
				last = width
			end
		end)

		it("knows which zone a position is in", function()
			expect.equal(Runway.zoneAt(-1), nil)
			expect.equal(Runway.zoneAt(0), 1)
			expect.equal(Runway.zoneAt(799.9), 1)
			expect.equal(Runway.zoneAt(800), 2)
			expect.equal(Runway.zoneAt(Runway.FINAL_ZONE_START - 1), 5)
			expect.equal(Runway.zoneAt(Runway.FINAL_ZONE_START), 6)
			expect.equal(Runway.zoneAt(Runway.LENGTH - 1), 6)
			-- The last zone never ends.
			expect.equal(Runway.zoneAt(Runway.LENGTH), 6)
			expect.equal(Runway.zoneAt(500000), 6)
			expect.equal(Runway.zoneStartZ(3), 800 + 1160)
		end)

		it("winds from side to side through every zone, never bending too tightly or doubling back", function()
			for zoneId = 1, Runway.ZONE_COUNT do
				local startZ = Runway.zoneStartZ(zoneId)
				local endZ = startZ + Runway.zoneLength(zoneId)
				local left, right, tightest = 0, 0, math.huge
				for z = startZ, endZ do
					local heading = Runway.heading(z)
					left, right = math.max(left, heading), math.min(right, heading)
					expect.truthy(math.abs(heading) <= Runway.MAX_HEADING + 1e-9, "swings too far at " .. z)
					local curvature = math.abs(Runway.curvature(z))
					if curvature > 0 then
						tightest = math.min(tightest, 1 / curvature)
					end
				end
				-- Real bends, both ways...
				expect.truthy(left > math.rad(15), `zone {zoneId} bends left`)
				expect.truthy(right < -math.rad(15), `zone {zoneId} bends right`)
				-- ...but never so tight that the walls on the inside of a bend run out of room.
				expect.truthy(
					tightest >= Runway.minBendRadius(zoneId) - 1,
					`zone {zoneId}: a bend of radius {tightest}`
				)
				expect.truthy(Runway.minBendRadius(zoneId) > Runway.zoneWidth(zoneId) / 2 + 150, "room for the walls")
				-- Every zone starts and ends dead ahead, so its gate stands square across it.
				expect.near(Runway.heading(startZ), 0, 1e-9)
				expect.near(Runway.heading(startZ + 50), 0, 1e-9)
				expect.near(Runway.heading(endZ), 0, 1e-9)
			end
			-- Always onward: the further down the runway, the further along the world's Z axis.
			local _, _, lastZ = Runway.toWorld(0, 0)
			for z = 5, Runway.LENGTH + Runway.LOOP_LENGTH * 2, 5 do
				local _, _, worldZ = Runway.toWorld(0, z)
				expect.truthy(worldZ > lastZ + 4, "doubles back at " .. z)
				lastZ = worldZ
			end
		end)

		it("rolls over hills in every zone, never too steeply", function()
			for zoneId = 1, Runway.ZONE_COUNT do
				local startZ = Runway.zoneStartZ(zoneId)
				local endZ = startZ + Runway.zoneLength(zoneId)
				local low, high = math.huge, -math.huge
				for z = startZ, endZ do
					local y = Runway.surfaceY(z)
					low, high = math.min(low, y), math.max(high, y)
					expect.truthy(math.abs(Runway.slope(z)) <= Runway.MAX_GRADE + 1e-9, "too steep at " .. z)
				end
				expect.truthy(high - low >= 8, `zone {zoneId} has hills ({high - low} studs)`)
				-- Level by the gate.
				expect.near(Runway.slope(startZ), 0, 1e-9)
				expect.near(Runway.surfaceY(startZ + 50), Runway.surfaceY(startZ), 1e-9)
			end
			-- The slope is how fast the height changes.
			for _, z in { 250.5, 1333, 4100.25, 9000 } do
				local measured = (Runway.surfaceY(z + 1) - Runway.surfaceY(z - 1)) / 2
				expect.near(Runway.slope(z), measured, 1e-3, "slope at " .. z)
			end
		end)

		it("only ever humps up through the Ocean, whose boardwalk stands over a level sea", function()
			local startZ = Runway.zoneStartZ(4)
			local level = Runway.surfaceY(startZ)
			for z = startZ, startZ + Runway.zoneLength(4) do
				expect.truthy(Runway.surfaceY(z) >= level - 1e-9, "dips into the sea at " .. z)
			end
			expect.near(Runway.surfaceY(startZ + Runway.zoneLength(4)), level, 1e-9)
		end)

		it("turns runway coordinates into places in the world and back", function()
			-- The same spots every run.
			local state = 20261116
			local function random(): number
				state = (state * 48271) % 2147483647
				return state / 2147483647
			end
			for _ = 1, 4000 do
				local z = -200 + random() * (Runway.LENGTH + Runway.LOOP_LENGTH * 2.5)
				-- Anywhere on the runway, and out past the far side of its walls.
				local x = (random() * 2 - 1) * (Runway.halfWidthAt(z) + 110)
				local worldX, worldY, worldZ = Runway.toWorld(x, z)
				expect.near(worldY, Runway.surfaceY(z), 1e-9)
				local backX, backZ = Runway.fromWorld(worldX, worldZ)
				expect.near(backX, x, 0.02, `x of ({x}, {z})`)
				expect.near(backZ, z, 0.02, `z of ({x}, {z})`)
			end
			-- Across the runway is square to the way it points, and a stud across is a stud in the world.
			for _, z in { 300, 2222, 6000, 9999 } do
				local heading = Runway.heading(z)
				local ax, _, az = Runway.toWorld(-20, z)
				local bx, _, bz = Runway.toWorld(30, z)
				expect.near(math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2), 50, 1e-9)
				expect.near((bx - ax) * math.sin(heading) + (bz - az) * math.cos(heading), 0, 1e-9)
				-- A stud down the runway covers more ground round the outside of a bend than round the inside.
				local curvature = Runway.curvature(z)
				expect.near(Runway.stretch(40, z), 1 - 40 * curvature, 1e-9)
				local fx, _, fz = Runway.toWorld(40, z + 0.5)
				local gx, _, gz = Runway.toWorld(40, z - 0.5)
				expect.near(math.sqrt((fx - gx) ^ 2 + (fz - gz) ^ 2), Runway.stretch(40, z), 1e-3)
			end
			-- Somewhere far off to the side (the Model Showroom, say) is never mistaken for the runway.
			for _, worldZ in { -300, 100, 2500, 7000 } do
				local x, z = Runway.fromWorld(-3000, worldZ)
				expect.truthy(math.abs(x) > Runway.halfWidthAt(z) + 1000, "the showroom is not on the runway")
			end
		end)

		it("loops the last zone: anything reaching the end of the loop is carried back one loop", function()
			expect.equal(Runway.FINAL_ZONE_START, Runway.zoneStartZ(Runway.ZONE_COUNT))
			expect.equal(Runway.LOOP_LENGTH, Runway.zoneLength(Runway.ZONE_COUNT))
			expect.equal(Runway.LOOP_END - Runway.LOOP_START, Runway.LOOP_LENGTH)
			expect.truthy(Runway.LOOP_START > Runway.FINAL_ZONE_START, "the loop starts inside the last zone")
			expect.truthy(Runway.LOOP_END < Runway.LENGTH + Runway.REPEATS * Runway.LOOP_LENGTH, "built that far")

			expect.equal(Runway.wrapZ(100), 100)
			expect.equal(Runway.wrapZ(Runway.LOOP_END - 1), Runway.LOOP_END - 1)
			expect.near(Runway.wrapZ(Runway.LOOP_END), Runway.LOOP_START)
			expect.near(Runway.wrapZ(Runway.LOOP_END + 10), Runway.LOOP_START + 10)
			expect.near(Runway.wrapZ(Runway.LOOP_END + 5 * Runway.LOOP_LENGTH + 10), Runway.LOOP_START + 10)
			for _, z in { Runway.LOOP_END + 5000, 123456.7, 1e6 } do
				local wrapped = Runway.wrapZ(z)
				expect.truthy(wrapped >= Runway.LOOP_START and wrapped < Runway.LOOP_END, tostring(z))
			end
		end)

		it("builds each copy of the last zone as the one before it, moved along and not turned", function()
			local shiftX, shiftY, shiftZ = Runway.loopShift()
			expect.truthy(shiftZ > Runway.LOOP_LENGTH * 0.8, "a loop is a long way on")
			-- The last zone ends at the height it started at, so the copies do not creep up or down.
			expect.near(shiftY, 0, 1e-6)
			local L = Runway.LOOP_LENGTH
			for z = Runway.FINAL_ZONE_START, Runway.LENGTH, 61 do
				for _, x in { -100, 0, 55 } do
					local worldX, worldY, worldZ = Runway.toWorld(x, z)
					for copy = 1, 3 do
						local copyX, copyY, copyZ = Runway.toWorld(x, z + copy * L)
						expect.near(copyX, worldX + copy * shiftX, 1e-6)
						expect.near(copyY, worldY + copy * shiftY, 1e-6)
						expect.near(copyZ, worldZ + copy * shiftZ, 1e-6)
					end
				end
				expect.near(Runway.heading(z + L), Runway.heading(z), 1e-9)
				expect.near(Runway.curvature(z + L + 0.5), Runway.curvature(z + 0.5), 1e-9)
				expect.near(Runway.slope(z + 2 * L + 0.5), Runway.slope(z + 0.5), 1e-9)
				expect.equal(Runway.widthAt(z + L), Runway.widthAt(z))
			end
			-- So being carried back one loop is a plain move, the same from anywhere.
			local worldX, _, worldZ = Runway.toWorld(12, Runway.LOOP_END)
			local backX, backZ = Runway.fromWorld(worldX - shiftX, worldZ - shiftZ)
			expect.near(backX, 12, 0.02)
			expect.near(backZ, Runway.LOOP_START, 0.02)
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
				-- A quarter of the way into the next zone, however long that is.
				expect.equal(Runway.fadeZ(1), Runway.zoneStartZ(2) + Runway.zoneLength(2) / 4)
				local last = Runway.fadeZ(Runway.ZONE_COUNT)
				expect.equal(last, Runway.LENGTH + Runway.LOOP_LENGTH / 4)
				expect.truthy(last < Runway.LOOP_END)
			end
		)

		it("knows when an egg is pressed against the side", function()
			local limit = Runway.maxLateral(4, 300)
			expect.equal(Runway.isAtEdge(limit, 4, 300), true)
			expect.equal(Runway.isAtEdge(-limit, 4, 300), true)
			expect.equal(Runway.isAtEdge(limit - 1, 4, 300), false)
			-- Further down, where the runway is wider, the same spot is nowhere near the side.
			expect.equal(Runway.isAtEdge(limit, 4, Runway.FINAL_ZONE_START + 300), false)
		end)

		it("keeps eggs on the runway", function()
			local limit = Runway.maxLateral(4, 300)
			expect.near(limit, Runway.WIDTH / 2 - 5)
			expect.equal(Runway.clampLateral(999, 4, 300), limit)
			expect.equal(Runway.clampLateral(-999, 4, 300), -limit)
			expect.equal(Runway.clampLateral(3, 4, 300), 3)
			-- As far as the wider zones are wide.
			local deep = Runway.FINAL_ZONE_START + 300
			expect.near(Runway.maxLateral(4, deep), Runway.MAX_WIDTH / 2 - 5)
			expect.equal(Runway.clampLateral(999, 4, deep), Runway.MAX_WIDTH / 2 - 5)
			-- Whoever gets on an egg running along a wall starts a little way in from it.
			expect.near(Runway.mountLateral(999, 4, 300), limit - Runway.MOUNT_EDGE_MARGIN)
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
		it("puts fairly large gaps in both walls of every zone, clear of the zone's start and end", function()
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
						gap.endZ <= startZ + Runway.zoneLength(zoneId) - Runway.GAPLESS_END,
						"clear of the next zone"
					)
					expect.truthy(gap.startZ >= lastEnd[gap.side] + Runway.BANK_MIN_LENGTH - 1e-9, "bank between gaps")
					lastEnd[gap.side] = gap.endZ
				end
				expect.truthy(sides[1] and sides[-1], "zone " .. zoneId .. " has gaps on both sides")
				-- The longer the zone, the more gaps it has.
				if zoneId > 1 then
					expect.truthy(#Runway.wallGaps(zoneId) >= #Runway.wallGaps(zoneId - 1), "gaps in zone " .. zoneId)
				end
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
end
