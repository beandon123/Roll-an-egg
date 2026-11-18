--!nocheck
-- Tests for the shared math modules.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local CycleClock = harness.load("src/shared/CycleClock")
	local EggMotion = harness.load("src/shared/EggMotion")
	local EggSpec = harness.load("src/shared/EggSpec")
	local LuckBoost = harness.load("src/shared/LuckBoost")
	local NumberFormat = harness.load("src/shared/NumberFormat")
	local RiderPose = harness.load("src/shared/RiderPose")
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

		it("tells the HUD whether it is day, and how long until that changes", function()
			local start = 180 * 12
			local sunset = 180 * CycleClock.DAY_FRACTION
			local isDay, untilChange = CycleClock.dayNight(start + 5)
			expect.equal(isDay, true)
			expect.near(untilChange, sunset - 5)
			isDay, untilChange = CycleClock.dayNight(start + sunset)
			expect.equal(isDay, false, "night falls at sunset")
			expect.near(untilChange, 180 - sunset, 1e-9, "until the next sunrise")
			isDay, untilChange = CycleClock.dayNight(start + CycleClock.CLOSE_AT + 2)
			expect.equal(isDay, false, "still night while the runway is closed")
			expect.near(untilChange, CycleClock.CLOSED_LENGTH - 2)
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

		it("can be moved ahead, for every device at once", function()
			local time = 180 * 7 + 30
			expect.equal(CycleClock.getOffset(), 0)
			CycleClock.setOffset(140)
			local moved = CycleClock.getState(time)
			CycleClock.setOffset(0)
			expect.equal(moved.phase, "Closed", "140 s on, the runway has closed")
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
			-- When it runs out: only while running down.
			expect.near(StaminaMath.runsOutAt(100, 20, -8), 32.5)
			expect.near(StaminaMath.runsOutAt(-5, 20, -8), 20)
			expect.equal(StaminaMath.runsOutAt(100, 20, 0), nil)
			expect.equal(StaminaMath.runsOutAt(100, 20, 12), nil)
		end)
	end)

	describe("RiderPose", function()
		local function riding(extra)
			local state = { phase = 0, time = 0, speed = 21, steer = 0, tired = 0, cheer = 0 }
			for key, value in extra or {} do
				state[key] = value
			end
			return state
		end

		local function finite(pose, names, label)
			for _, name in names do
				local joint = pose[name]
				expect.truthy(joint, label .. ": " .. name)
				expect.equal(#joint, 6, label .. ": " .. name)
				for _, value in joint do
					expect.truthy(value == value and math.abs(value) < 10, `{label}: {name} = {value}`)
				end
			end
		end

		it("poses every joint, whatever is going on", function()
			local states = {
				riding(),
				riding({ phase = 2, time = 7, speed = 32, steer = 1, tired = 1, cheer = 1, landed = 0, bumped = 0 }),
				riding({ phase = 5, time = 3, speed = 18, steer = -1, tired = 0.5, landed = 0.1, bumped = 0.3 }),
				riding({ speed = 500, steer = 9, tired = 4, cheer = -2, landed = -1, bumped = -1 }),
			}
			for index, state in states do
				local pose = RiderPose.pose(state)
				finite(pose, RiderPose.JOINTS, "state " .. index)
				finite(RiderPose.toR6(pose), RiderPose.R6_JOINTS, "R6 state " .. index)
			end
			finite(RiderPose.tumble(3, 0.4), RiderPose.JOINTS, "tumble")

			-- A pose can be reused from frame to frame.
			local reused = RiderPose.pose(riding({ phase = 1 }))
			local again = RiderPose.pose(riding({ phase = 1 }), RiderPose.tumble(3, 0.4))
			for _, name in RiderPose.JOINTS do
				for channel = 1, 6 do
					expect.near(again[name][channel], reused[name][channel], 1e-9, name)
				end
			end
		end)

		it("runs with quicker feet on faster eggs, the legs taking turns", function()
			expect.truthy(RiderPose.strideRate(18) < RiderPose.strideRate(32))
			expect.truthy(RiderPose.strideRate(18) >= 2 and RiderPose.strideRate(32) <= 3.5)
			expect.near(RiderPose.advance(0, 18, 1 / RiderPose.strideRate(18)), 0, 1e-9, "one stride a turn")

			local quarter = RiderPose.pose(riding({ phase = math.pi / 2 }))
			local threeQuarters = RiderPose.pose(riding({ phase = 3 * math.pi / 2 }))
			expect.truthy(quarter.LeftHip[1] > quarter.RightHip[1] + 0.8, "left leg forward")
			expect.truthy(threeQuarters.RightHip[1] > threeQuarters.LeftHip[1] + 0.8, "right leg forward")
			-- Each arm swings against the leg on its side.
			expect.truthy(quarter.RightShoulder[1] > quarter.LeftShoulder[1], "right arm forward")
			-- Leaning into the run, bobbing up between steps.
			expect.truthy(quarter.Root[1] < -0.1, "leaning forward")
			expect.truthy(quarter.Root[5] > RiderPose.pose(riding({ phase = 0 })).Root[5], "bobs up between steps")
		end)

		it("leans into a turn, with the outside arm out", function()
			local right = RiderPose.pose(riding({ steer = 1 }))
			local left = RiderPose.pose(riding({ steer = -1 }))
			expect.truthy(right.Root[3] < -0.2, "tips to the right")
			expect.truthy(left.Root[3] > 0.2, "tips to the left")
			-- The left arm swings out to the left (negative turn about z) in a right turn.
			expect.truthy(-right.LeftShoulder[3] > -left.LeftShoulder[3] + 0.3)
			expect.truthy(right.RightShoulder[3] >= 0.05 and left.LeftShoulder[3] <= -0.05, "never across the body")
		end)

		it("wobbles and windmills when tired, punches the air when the egg is theirs", function()
			local calm, tired = 0, 0
			for step = 0, 59 do
				local t = step / 30
				calm = math.max(calm, math.abs(RiderPose.pose(riding({ time = t, phase = t * 15 })).Root[3]))
				local pose = RiderPose.pose(riding({ time = t, phase = t * 15, tired = 1 }))
				tired = math.max(tired, math.abs(pose.Root[3]))
				expect.truthy(pose.LeftShoulder[3] < -0.3 and pose.RightShoulder[3] > 0.3, "arms out wide")
			end
			expect.truthy(tired > calm + 0.1, `sways more: {tired} vs {calm}`)

			local cheering = RiderPose.pose(riding({ cheer = 1 }))
			expect.truthy(cheering.RightShoulder[1] > 2.5, "right arm up")
		end)

		it("squashes on landing and is jolted by a bump, then runs on", function()
			local plain = RiderPose.pose(riding())
			local landing = RiderPose.pose(riding({ landed = 0 }))
			expect.truthy(landing.Root[5] < plain.Root[5] - 0.3, "crouches")
			expect.truthy(landing.LeftKnee[1] < -1 and landing.RightKnee[1] < -1, "both knees bend")
			local landed = RiderPose.pose(riding({ landed = RiderPose.LANDING_TIME }))
			expect.near(landed.Root[5], plain.Root[5], 1e-9)

			local bumped = RiderPose.pose(riding({ bumped = 0.05 }))
			expect.truthy(-bumped.LeftShoulder[3] > -plain.LeftShoulder[3] + 0.5, "arms thrown out")
			local over = RiderPose.pose(riding({ bumped = RiderPose.STUMBLE_TIME }))
			expect.near(over.LeftShoulder[3], plain.LeftShoulder[3], 1e-9)
		end)

		it("folds onto R6 joints", function()
			local pose = RiderPose.pose(riding({ phase = 1, steer = 0.5 }))
			local r6 = RiderPose.toR6(pose)
			expect.near(r6.RootJoint[1], pose.Root[1] + pose.Waist[1], 1e-9)
			expect.near(r6.Neck[1], pose.Neck[1], 1e-9)
			expect.near(r6["Left Hip"][1], pose.LeftHip[1] + 0.3 * pose.LeftKnee[1], 1e-9)
			expect.near(r6["Right Shoulder"][3], pose.RightShoulder[3], 1e-9)
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
end
