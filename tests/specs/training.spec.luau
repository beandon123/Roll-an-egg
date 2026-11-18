--!nocheck
-- Checks the training stick: its tiers (Config/Sticks), its rules (Logic/Training) on saved-data tables, the sessions
-- that hand out reps and "2x" bubbles, the shop's Robux tiers, the rider's pose (Shared/BirlingPose), and Max
-- Stamina counting what was trained (Logic/Stats).

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local BirlingPose = harness.load("src/shared/BirlingPose")
	local NumberFormat = harness.load("src/shared/NumberFormat")
	local Rarities = harness.load("src/shared/Config/Rarities")
	local Shop = harness.load("src/shared/Config/Shop")
	local Sticks = harness.load("src/shared/Config/Sticks")
	local Stats = harness.load("src/server/Logic/Stats")
	local Training = harness.load("src/server/Logic/Training")
	local Tuning = harness.load("src/shared/Config/Tuning")

	-- A player's saved data, shaped like DataService's template.
	local function newData(dollars, level)
		return {
			Dollars = dollars or 0,
			MaxStaminaBonus = 0,
			StaminaMultiplier = 1,
			StickLevel = level or 1,
			TrainedStamina = 0,
			Trails = { Owned = {}, Equipped = "" },
			Stats = { EggsClaimed = 0, EggsSold = 0, TrainingReps = 0 },
		}
	end

	-- Numbers from 0 to 1 that repeat, so sessions are the same every run.
	local function fixedRandom(...)
		local values = { ... }
		local index = 0
		return function()
			index = index % #values + 1
			return values[index]
		end
	end

	describe("Training stick: tiers", function()
		it("has eight tiers, from a stick to a rainbow crystal, each dearer and stronger than the last", function()
			expect.equal(#Sticks.Tiers, 8)
			expect.equal(Sticks.MAX_LEVEL, 8)
			local names = {}
			for level, tier in Sticks.Tiers do
				expect.equal(tier.level, level)
				table.insert(names, tier.name)
				expect.truthy(Rarities.Info[tier.rarity], tier.name .. " rarity")
				if level > 1 then
					local before = Sticks.Tiers[level - 1]
					expect.truthy(tier.price > before.price, tier.name .. " costs more")
					expect.truthy(tier.perRep > before.perRep, tier.name .. " gives more")
					expect.truthy(Rarities.Info[tier.rarity].order >= Rarities.Info[before.rarity].order, "rarity")
				end
				expect.truthy(tier.length <= Sticks.POST_SPAN - 2, tier.name .. " fits between the posts")
				expect.truthy(tier.reach >= Sticks.maxTop(level) - 1e-9, tier.name .. " reach covers its top")
			end
			expect.equal(
				table.concat(names, ", "),
				"Stick, Plank, Short Log, Tree Trunk, Metal Pipe, Steel Girder, Marble Column, Rainbow Crystal"
			)
			-- The first tier is free and gives exactly 1 a rep, 4 a second.
			expect.equal(Sticks.tier(1).price, 0)
			expect.equal(Sticks.tier(1).perRep, 1)
			expect.equal(Sticks.REP_INTERVAL, 0.25)
			expect.equal(Sticks.perSecond(1), 4)
		end)

		it("clamps levels and knows the tier after each", function()
			expect.equal(Sticks.tier(0).level, 1)
			expect.equal(Sticks.tier(99).level, 8)
			expect.equal(Sticks.nextTier(1).name, "Plank")
			expect.equal(Sticks.nextTier(8), nil)
		end)

		it("works out how high the top of a turning roller is", function()
			-- A round roller's top never moves.
			expect.near(Sticks.topHeight(1, 0), Sticks.topHeight(1, 1.234))
			-- A plank lies flat at rest, and stands on its edge a quarter turn later.
			local plank = Sticks.tier(2).profile
			expect.near(Sticks.topHeight(2, 0), plank.halfHeight)
			expect.near(Sticks.topHeight(2, math.pi / 2), plank.halfWidth)
			-- The crystal has a flat face on top at rest and a corner on top a sixth of a turn later.
			local crystal = Sticks.tier(8).profile
			expect.near(Sticks.topHeight(8, 0), crystal.radius * math.sqrt(3) / 2)
			expect.near(Sticks.topHeight(8, math.pi / 6), crystal.radius)
			-- Never higher than the highest the rider is stood at, all the way round.
			for level = 1, Sticks.MAX_LEVEL do
				for step = 0, 72 do
					local angle = step / 72 * math.pi * 2
					expect.truthy(Sticks.topHeight(level, angle) <= Sticks.maxTop(level) + 1e-9, `{level} at {angle}`)
				end
				-- The roller clears the water as it turns.
				expect.truthy(Sticks.axleHeight(level) - Sticks.tier(level).reach > Sticks.WATER_HEIGHT, "clear")
			end
		end)
	end)

	describe("Training stick: rules", function()
		it("adds Max Stamina for good with every rep, through the player's multipliers", function()
			local data = newData()
			local base = Stats.maxStamina(data)
			expect.equal(base, Tuning.BASE_MAX_STAMINA)
			expect.equal(Training.addRep(data, false), 1)
			expect.equal(Training.addRep(data, true), 2, "a boosted rep counts double")
			expect.equal(data.TrainedStamina, 3)
			expect.equal(data.Stats.TrainingReps, 2)
			expect.equal(Stats.maxStamina(data), base + 3)

			-- Doublings and the equipped trail multiply what is trained, like everything else.
			data.StaminaMultiplier = 4
			data.Trails = { Owned = { Leaf = true }, Equipped = "Leaf" }
			expect.equal(Training.multiplier(data), 6)
			expect.equal(Training.gainPerRep(data), 6)
			expect.equal(Training.gainPerRep(data, true), 12)
			local before = Stats.maxStamina(data)
			expect.near(Training.addRep(data, false), 6)
			expect.near(Stats.maxStamina(data), before + 6)

			-- A better stick gives more a rep.
			data.StickLevel = 3
			expect.equal(Training.gainPerRep(data), 5 * 6)
		end)

		it("upgrades with dollars, one tier at a time, until it is as good as it gets", function()
			local data = newData(600)
			local ok, result, price = Training.upgrade(data)
			expect.equal(ok, true)
			expect.equal(result, "Upgraded")
			expect.equal(price, 500)
			expect.equal(data.StickLevel, 2)
			expect.equal(data.Dollars, 100)

			ok, result, price = Training.upgrade(data)
			expect.equal(ok, false)
			expect.equal(result, "NotEnoughDollars")
			expect.equal(price, Sticks.tier(3).price)
			expect.equal(data.StickLevel, 2)
			expect.equal(data.Dollars, 100, "nothing taken")

			data.StickLevel = 8
			data.Dollars = 1e12
			ok, result, price = Training.upgrade(data)
			expect.equal(ok, false)
			expect.equal(result, "Max")
			expect.equal(price, nil)
			expect.equal(data.Dollars, 1e12)
		end)

		it("raises the stick a tier for Robux, without dollars", function()
			local data = newData(0, 7)
			expect.equal(Training.raise(data), true)
			expect.equal(data.StickLevel, 8)
			expect.equal(Training.raise(data), false)
			expect.equal(data.StickLevel, 8)
		end)
	end)

	describe("Training stick: rolling", function()
		it("hands out four reps a second, and never a pile of them after a stall", function()
			local session = Training.start(1, 100, fixedRandom(0.5))
			expect.equal(#Training.step(session, 100.2).reps, 0)
			expect.equal(#Training.step(session, 101).reps, 4)
			expect.equal(#Training.step(session, 101.1).reps, 0)
			expect.equal(#Training.step(session, 101.5).reps, 2)
			-- Ten seconds without a step: only MAX_CATCH_UP reps, then back on the beat.
			expect.equal(#Training.step(session, 111.5).reps, Training.MAX_CATCH_UP)
			expect.equal(#Training.step(session, 112).reps, 2)
			expect.equal(session.reps, 4 + 2 + Training.MAX_CATCH_UP + 2)
		end)

		it("puts up a 2x bubble that doubles the next reps when tapped in time", function()
			local session = Training.start(1, 0, fixedRandom(0, 1))
			-- The first bubble comes a moment after getting on.
			local result = Training.step(session, Sticks.FIRST_BUBBLE - 0.01)
			expect.equal(result.bubble, nil)
			result = Training.step(session, Sticks.FIRST_BUBBLE)
			local bubble = result.bubble
			expect.truthy(bubble, "a bubble")
			expect.equal(bubble.id, 1)
			expect.near(bubble.endsAt, Sticks.FIRST_BUBBLE + Sticks.BUBBLE_LIFETIME)
			-- Only one at a time.
			expect.equal(Training.step(session, Sticks.FIRST_BUBBLE + 0.5).bubble, nil)

			-- A wrong id does nothing; the right one starts the boost.
			local tapAt = Sticks.FIRST_BUBBLE + 1
			expect.equal(Training.claim(session, 2, tapAt), false)
			expect.equal(Training.claim(session, 1, tapAt), true)
			expect.equal(Training.isBoosted(session, tapAt + 0.1), true)
			expect.equal(Training.claim(session, 1, tapAt), false, "tapped once only")

			-- Reps during the boost count double; the boost lasts BOOST_DURATION.
			local reps = Training.step(session, tapAt + Sticks.BOOST_DURATION + 1).reps
			local doubled = 0
			for _, boosted in reps do
				if boosted then
					doubled += 1
				end
			end
			expect.equal(doubled, Sticks.BOOST_DURATION / Sticks.REP_INTERVAL)
			expect.truthy(#reps > doubled, "and then back to normal")
			expect.equal(Training.isBoosted(session, tapAt + Sticks.BOOST_DURATION + 0.01), false)

			-- The next bubble comes between BUBBLE_GAP[1] and BUBBLE_GAP[2] seconds after the tap (here the shortest).
			expect.near(session.nextBubbleAt, tapAt + Sticks.BUBBLE_GAP[1])
		end)

		it("lets an untapped bubble go, and refuses a tap that comes too late", function()
			local session = Training.start(1, 0, fixedRandom(1))
			local bubble = Training.step(session, Sticks.FIRST_BUBBLE).bubble
			local late = bubble.endsAt + Sticks.CLAIM_GRACE + 0.05
			Training.step(session, late)
			expect.equal(session.bubble, nil)
			expect.equal(Training.claim(session, bubble.id, late), false)
			expect.equal(Training.isBoosted(session, late), false)
			-- The next one comes a while later (here the longest gap), with a new id.
			expect.near(session.nextBubbleAt, late + Sticks.BUBBLE_GAP[2])
			expect.equal(Training.step(session, late + Sticks.BUBBLE_GAP[2] - 0.1).bubble, nil)
			expect.equal(Training.step(session, late + Sticks.BUBBLE_GAP[2]).bubble.id, 2)

			-- A tap just after the bubble's time, within the grace for network delay, still counts.
			local again = Training.start(1, 0, fixedRandom(0.5))
			local slow = Training.step(again, Sticks.FIRST_BUBBLE).bubble
			expect.equal(Training.claim(again, slow.id, slow.endsAt + Sticks.CLAIM_GRACE * 0.5), true)
		end)
	end)

	describe("Training stick: shop", function()
		it("sells every tier after the first for Robux and for its dollar price", function()
			expect.equal(Shop.MAX_STICK_LEVEL, Sticks.MAX_LEVEL)
			expect.equal(Shop.StickLevels[1], nil)
			local last = 0
			for level = 2, Sticks.MAX_LEVEL do
				local entry = Shop.StickLevels[level]
				expect.truthy(entry, "level " .. level)
				expect.equal(entry.dollars, Sticks.tier(level).price)
				expect.truthy(entry.robux > last, "dearer in Robux")
				last = entry.robux
			end
		end)

		it("knows which tier a developer product pays for", function()
			local entry = Shop.StickLevels[3]
			local saved = entry.productId
			entry.productId = 555123
			local grant, itemId = Shop.rewardForProductId(555123)
			entry.productId = saved
			expect.equal(grant.kind, "StickLevel")
			expect.equal(itemId, Shop.STICK_UPGRADE_ID)
		end)
	end)

	describe("Training stick: the rider's pose", function()
		it("poses every joint, arms out for balance and legs taking turns", function()
			local pose = BirlingPose.pose(0.7, 1.3, 1)
			for _, name in BirlingPose.JOINTS do
				expect.truthy(pose[name], name)
			end
			-- Arms held out to the sides (well over 45 degrees), each to its own side.
			expect.truthy(pose.RightShoulder.z > math.rad(50), "right arm out")
			expect.truthy(pose.LeftShoulder.z < -math.rad(50), "left arm out")
			-- Leaning forward.
			expect.truthy(pose.Waist.x < 0, "leaning in")
			-- Half a stride later the legs have swapped.
			local later = BirlingPose.pose(0.7 + math.pi, 1.3, 1)
			expect.near(later.LeftHip.x, pose.RightHip.x)
			expect.near(later.RightKnee.x, pose.LeftKnee.x)
			-- Knees only ever bend backwards.
			for step = 0, 24 do
				local frame = BirlingPose.pose(step / 24 * math.pi * 2, step, 1)
				expect.truthy(frame.LeftKnee.x < 0 and frame.RightKnee.x < 0, "knees")
			end
		end)

		it("eases in from standing still", function()
			local pose = BirlingPose.pose(2.1, 0.4, 0)
			for name, joint in pose do
				expect.near(joint.x, 0, 1e-9, name)
				expect.near(joint.z, 0, 1e-9, name)
				expect.near(joint.lift, 0, 1e-9, name)
			end
		end)
	end)

	describe("Training stick: numbers", function()
		it("shows small amounts with a decimal, and big ones abbreviated", function()
			expect.equal(NumberFormat.amount(1), "1")
			expect.equal(NumberFormat.amount(1.5), "1.5")
			expect.equal(NumberFormat.amount(7.25), "7.2")
			expect.equal(NumberFormat.amount(6), "6")
			expect.equal(NumberFormat.amount(250), "250")
			expect.equal(NumberFormat.amount(2500), "2.5K")
		end)
	end)
end
