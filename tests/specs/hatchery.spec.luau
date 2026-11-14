--!nocheck
-- Tests for eggs, pens, pets and money: the plot layout, hatch timing (with the closure boost), what pets are worth,
-- and the hatchery rules.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local CycleClock = harness.load("src/shared/CycleClock")
	local HatchMath = harness.load("src/shared/HatchMath")
	local Hatchery = harness.load("src/server/Logic/Hatchery")
	local NumberFormat = harness.load("src/shared/NumberFormat")
	local Plots = harness.load("src/shared/Plots")
	local Runway = harness.load("src/shared/Runway")
	local Tuning = harness.load("src/shared/Config/Tuning")

	local function newData()
		return { Eggs = {}, Hatching = {}, Pets = {}, PenLevel = 1, Dollars = 0, Mount = "" }
	end

	local function addEgg(data, uid, zone, rarity, kind)
		table.insert(data.Eggs, { uid = uid, zone = zone, rarity = rarity, kind = kind, claimedAt = 0 })
	end

	-- A moment well inside the open part of a cycle.
	local OPEN = 180 * 500 + 30

	describe("Plots", function()
		it("fits eight plots in the hub, either side of the plaza, clear of each other", function()
			local boxes = {}
			for index = 1, Plots.COUNT do
				local x, z = Plots.center(index)
				local box = {
					x - Plots.WIDTH / 2,
					x + Plots.WIDTH / 2,
					z - Plots.DEPTH / 2,
					z + Plots.DEPTH / 2,
				}
				expect.truthy(math.abs(x) - Plots.WIDTH / 2 >= Plots.PLAZA_HALF_WIDTH - 1e-6, "beside the plaza")
				expect.truthy(box[1] >= -Runway.HUB_WIDTH / 2 and box[2] <= Runway.HUB_WIDTH / 2, "in the hub")
				expect.truthy(box[3] >= -Runway.HUB_LENGTH and box[4] <= 0, "behind the runway")
				for _, other in boxes do
					local apart = box[2] <= other[1] or other[2] <= box[1] or box[4] <= other[3] or other[4] <= box[3]
					expect.truthy(apart, "plots overlap")
				end
				table.insert(boxes, box)
			end
		end)

		it("grows each pen a level at a time, holding more eggs and pets", function()
			expect.equal(Plots.penWidth(1), Plots.START_WIDTH)
			expect.equal(Plots.penWidth(Plots.MAX_LEVEL), Plots.WIDTH, "the biggest pen fills the plot")
			expect.equal(Plots.eggCapacity(1), 2)
			expect.equal(Plots.petCapacity(1), 10)
			expect.equal(Plots.eggCapacity(Plots.MAX_LEVEL), 10)
			expect.equal(Plots.petCapacity(Plots.MAX_LEVEL), 18)
			for level = 2, Plots.MAX_LEVEL do
				expect.truthy(Plots.penWidth(level) > Plots.penWidth(level - 1))
			end
			expect.truthy(Plots.inPen(1, 30, 0, 0))
			expect.falsy(Plots.inPen(1, Plots.START_WIDTH + 5, 0, 0), "past the fence")
			expect.truthy(Plots.inPen(2, Plots.START_WIDTH + 5, 0, 0), "inside the bigger pen")
			expect.falsy(Plots.inPen(1, -2, 0, 0), "in the plaza")
		end)

		it("turns points of a plot to the world and back, the same on both sides of the plaza", function()
			for _, index in { 1, 6 } do
				local x, z = Plots.point(index, 25, -10)
				local inward, along = Plots.toLocal(index, x, z)
				expect.near(inward, 25)
				expect.near(along, -10)
				expect.truthy(math.abs(x) > Plots.PLAZA_HALF_WIDTH, "in from the plaza")
			end
		end)

		it("keeps pets in the pen, and puts the spawn and the upgrade button in the plaza", function()
			for index = 1, Plots.COUNT do
				for _, level in { 1, Plots.MAX_LEVEL } do
					local x0, x1, z0, z1 = Plots.roamArea(index, level, 5)
					expect.truthy(x0 < x1 and z0 < z1)
					for _, x in { x0, x1 } do
						local inward = Plots.toLocal(index, x, z0)
						expect.truthy(inward >= 5 - 1e-6 and inward <= Plots.penWidth(level) - 5 + 1e-6, "inside")
					end
				end
				local sx = Plots.spawnPoint(index)
				expect.truthy(math.abs(sx) < Plots.PLAZA_HALF_WIDTH, "spawn in the plaza")
				expect.truthy(Plots.BUTTON_SPOT[1] < 0, "button in front of the fence")
				expect.truthy(math.abs(Plots.BUTTON_SPOT[2]) > Plots.GATE_HALF_WIDTH + 3, "beside the gate")
			end
		end)
	end)

	describe("HatchMath", function()
		it("hatches on each rarity's timer", function()
			expect.equal(HatchMath.hatchTime("Common"), 30)
			expect.equal(HatchMath.hatchTime("Eternal"), 6 * 60 * 60)
			expect.near(HatchMath.progress(OPEN, 0, "Common", OPEN + 15), 0.5)
			expect.near(HatchMath.timeLeft(OPEN, 0, "Common", OPEN + 15), 15)
			expect.equal(HatchMath.progress(OPEN, 0, "Common", OPEN + 60), 1)
			expect.equal(HatchMath.timeLeft(OPEN, 0, "Common", OPEN + 60), 0)
			-- Banked bonus counts as time already spent.
			expect.near(HatchMath.timeLeft(OPEN, 20, "Common", OPEN + 5), 5)
		end)

		it("hatches 30 times as fast while the runway is closed", function()
			local cycleStart = 180 * 600
			local closedAt = cycleStart - CycleClock.CLOSED_LENGTH
			local placed = closedAt - 100
			local boost = Tuning.HATCH_BOOST - 1
			expect.near(HatchMath.elapsed(placed, 0, closedAt - 1), 99)
			expect.near(HatchMath.elapsed(placed, 0, closedAt + 4), 104 + boost * 4)
			-- A whole closure banks 29 x 10 = 290 extra seconds; one placed partway through, only its share.
			expect.near(HatchMath.closureBonus(placed, cycleStart), boost * CycleClock.CLOSED_LENGTH)
			expect.near(HatchMath.closureBonus(closedAt + 6, cycleStart), boost * 4)
			expect.equal(HatchMath.closureBonus(cycleStart + 1, cycleStart), 0)
			-- Once banked, the live boost is gone and the total carries on smoothly.
			local banked = HatchMath.closureBonus(placed, cycleStart)
			expect.near(HatchMath.elapsed(placed, banked, cycleStart + 1), 111 + banked)
		end)

		it("writes long times in hours and minutes", function()
			expect.equal(NumberFormat.duration(45), "45s")
			expect.equal(NumberFormat.duration(125), "2m 05s")
			expect.equal(NumberFormat.duration(6 * 3600 - 30), "5h 59m")
			expect.equal(NumberFormat.duration(-3), "0s")
		end)
	end)

	describe("PetWorth", function()
		local PetWorth = harness.load("src/shared/PetWorth")
		local Economy = harness.load("src/shared/Config/Economy")

		it("pays more for rarer pets, deeper zones and rarer variants", function()
			local forestCommon = PetWorth.income({ zone = 1, rarity = "Common" })
			expect.equal(forestCommon, 1)
			expect.truthy(PetWorth.income({ zone = 1, rarity = "Mythic" }) > forestCommon)
			-- A zone's Common pets earn about what the zone before's best do.
			local forestBest = PetWorth.income({ zone = 1, rarity = "Mythic" })
			local desertCommon = PetWorth.income({ zone = 2, rarity = "Common" })
			expect.truthy(desertCommon >= forestBest * 0.5 and desertCommon <= forestBest * 2)
			expect.equal(PetWorth.income({ zone = 1, rarity = "Common", variant = "Gold" }), 5)
			expect.equal(PetWorth.income({ zone = 1, rarity = "Common", variant = "Rainbow" }), 15)
			expect.equal(PetWorth.sellPrice({ zone = 1, rarity = "Common" }), Economy.SELL_SECONDS)
		end)

		it("makes rarer pets faster to ride, and walking slowest of all", function()
			local slowest = PetWorth.mountSpeed({ zone = 1, rarity = "Common" })
			expect.truthy(slowest > 16, "faster than walking")
			expect.truthy(PetWorth.mountSpeed({ zone = 6, rarity = "Eternal" }) > slowest)
			expect.truthy(
				PetWorth.mountSpeed({ zone = 1, rarity = "Common", variant = "Rainbow" }) > slowest,
				"variants are a little faster"
			)
		end)

		it("hatches Silver, Gold and Rainbow pets, each rarer than the last", function()
			local counts = { Normal = 0, Silver = 0, Gold = 0, Rainbow = 0 }
			local total = 20000
			for index = 0, total - 1 do
				local variant = PetWorth.rollVariant((index + 0.5) / total)
				counts[variant] += 1
			end
			expect.truthy(counts.Rainbow > 0 and counts.Rainbow < counts.Gold)
			expect.truthy(counts.Gold < counts.Silver and counts.Silver < counts.Normal)
			expect.near(counts.Silver / total, 0.08, 0.002)
		end)

		it("prices a bigger pen, more for each level, until it is as big as it gets", function()
			local last = 0
			for level = 1, Economy.MAX_PEN_LEVEL - 1 do
				local cost = PetWorth.penUpgradeCost(level)
				expect.truthy(cost and cost > last, "level " .. level)
				last = cost
			end
			expect.equal(PetWorth.penUpgradeCost(Economy.MAX_PEN_LEVEL), nil)
		end)
	end)

	describe("Hatchery", function()
		local Economy = harness.load("src/shared/Config/Economy")
		local PetWorth = harness.load("src/shared/PetWorth")

		local function pet(uid, rarity, zone, variant, inPen)
			return {
				uid = uid,
				kind = "Bear",
				egg = "Bear",
				zone = zone or 1,
				rarity = rarity,
				variant = variant or "Normal",
				inPen = inPen or false,
				hatchedAt = 0,
			}
		end

		it("brings an old save up to date", function()
			local data = {
				Eggs = {},
				Nests = {
					{ slot = 1, uid = "n1", zone = 1, rarity = "Common", kind = "Leafy", placedAt = 5, bonus = 0 },
					{ slot = 2, uid = "n2", zone = 1, rarity = "Rare", kind = "Toadstool", placedAt = 6, bonus = 9 },
				},
				NestCount = 2,
				Coins = 40,
				Pets = { { uid = "p", kind = "Bear", egg = "Bear", zone = 1, rarity = "Epic", hatchedAt = 1 } },
			}
			Hatchery.migrate(data)
			expect.equal(data.Nests, nil)
			expect.equal(data.NestCount, nil)
			expect.equal(data.Coins, nil)
			expect.equal(data.Dollars, 40)
			expect.equal(data.PenLevel, 1)
			expect.equal(data.Mount, "")
			expect.equal(#data.Hatching, 2)
			expect.equal(data.Hatching[2].bonus, 9)
			for _, entry in data.Hatching do
				expect.truthy(Plots.inPen(1, entry.inward, entry.along, Plots.EGG_MARGIN), "in the pen")
			end
			expect.equal(data.Pets[1].variant, "Normal")
			expect.equal(data.Pets[1].inPen, true, "the best pets go in the pen")
			-- Running it again changes nothing.
			Hatchery.migrate(data)
			expect.equal(#data.Hatching, 2)
		end)

		it("puts an egg down where the player stands, clear of the others", function()
			local data = newData()
			addEgg(data, "a", 1, "Rare", "Toadstool")
			addEgg(data, "b", 1, "Common", "Leafy")
			local entry = Hatchery.place(data, "b", 20, 5, OPEN)
			expect.equal(entry.kind, "Leafy")
			expect.equal(entry.inward, 20)
			expect.equal(entry.along, 5)
			expect.equal(entry.placedAt, OPEN)
			expect.equal(#data.Eggs, 1)
			-- The same spot is taken: the next egg goes down nearby instead.
			local second = Hatchery.place(data, "a", 20, 5, OPEN)
			local dx, dz = second.inward - 20, second.along - 5
			expect.truthy(math.sqrt(dx * dx + dz * dz) >= Plots.EGG_SPACING - 1e-6, "spaced apart")
			expect.truthy(Plots.inPen(1, second.inward, second.along, Plots.EGG_MARGIN))
		end)

		it("keeps eggs inside the pen, and refuses eggs it does not have or has no room for", function()
			local data = newData()
			for index = 1, 3 do
				addEgg(data, "egg" .. index, 1, "Common", "Leafy")
			end
			local entry, reason = Hatchery.place(data, "nope", 10, 0, OPEN)
			expect.falsy(entry)
			expect.equal(reason, "NoEgg")
			entry = Hatchery.place(data, "egg1", 500, 500, OPEN)
			expect.truthy(Plots.inPen(1, entry.inward, entry.along, Plots.EGG_MARGIN), "pulled inside the fence")
			Hatchery.place(data, "egg2", 10, 0, OPEN)
			entry, reason = Hatchery.place(data, "egg3", 30, 0, OPEN)
			expect.falsy(entry)
			expect.equal(reason, "Full")
			expect.equal(#data.Eggs, 1, "still in the inventory")
			-- A bigger pen hatches more at once.
			data.PenLevel = 2
			expect.truthy(Hatchery.place(data, "egg3", 30, 0, OPEN))
		end)

		it("hatches an egg into its pet when its time is up, sometimes Silver, Gold or Rainbow", function()
			local data = newData()
			addEgg(data, "a", 1, "Common", "Leafy")
			local entry = Hatchery.place(data, "a", 20, 0, OPEN)
			expect.equal(#Hatchery.ready(data, OPEN + 29), 0)
			local ready = Hatchery.ready(data, OPEN + 30)
			expect.equal(#ready, 1)
			local hatched = Hatchery.hatch(data, ready[1], OPEN + 30, "pet-1", 0.5)
			expect.equal(hatched.kind, "Squirrel")
			expect.equal(hatched.egg, "Leafy")
			expect.equal(hatched.variant, "Normal")
			expect.equal(hatched.inPen, true, "straight into the pen")
			expect.equal(#data.Hatching, 0)
			expect.falsy(Hatchery.hatch(data, entry, OPEN + 31, "again", 0.5), "an egg hatches once")

			for _, case in { { 0.001, "Rainbow" }, { 0.02, "Gold" }, { 0.06, "Silver" } } do
				addEgg(data, "v" .. case[2], 1, "Common", "Leafy")
				local next = Hatchery.place(data, "v" .. case[2], 30, 0, OPEN)
				expect.equal(Hatchery.hatch(data, next, OPEN + 30, "pv" .. case[2], case[1]).variant, case[2])
			end
		end)

		it("hatches while the player is away: the timer is just timestamps", function()
			local data = newData()
			addEgg(data, "a", 6, "Eternal", "LunarDragon")
			Hatchery.place(data, "a", 20, 0, OPEN)
			expect.equal(#Hatchery.ready(data, OPEN + 5 * 3600), 0)
			expect.equal(#Hatchery.ready(data, OPEN + 6 * 3600), 1)
		end)

		it("banks each closure's boost on every hatching egg", function()
			local data = newData()
			addEgg(data, "a", 1, "Epic", "Bear")
			local cycleStart = 180 * 600
			Hatchery.place(data, "a", 20, 0, cycleStart - 60)
			Hatchery.commitClosure(data, cycleStart)
			expect.near(data.Hatching[1].bonus, (Tuning.HATCH_BOOST - 1) * CycleClock.CLOSED_LENGTH)
		end)

		it("lets the player choose the pets in the pen, up to its size, or equip the best", function()
			local data = newData()
			for index = 1, 12 do
				table.insert(data.Pets, pet("p" .. index, "Common"))
			end
			local best = pet("best", "Common", 2, "Gold")
			table.insert(data.Pets, best)
			for index = 1, 10 do
				expect.truthy(Hatchery.setInPen(data, "p" .. index, true))
			end
			local ok, reason = Hatchery.setInPen(data, "p11", true)
			expect.falsy(ok)
			expect.equal(reason, "Full")
			expect.truthy(Hatchery.setInPen(data, "p1", false))
			expect.truthy(Hatchery.setInPen(data, "p11", true))
			expect.equal(#Hatchery.penPets(data), 10)
			expect.near(Hatchery.income(data), 10)

			Hatchery.equipBest(data)
			expect.equal(best.inPen, true, "the Gold Desert pet earns the most")
			expect.equal(#Hatchery.penPets(data), 10)
			expect.near(Hatchery.income(data), 9 + PetWorth.income(best))
		end)

		it("sells pets for dollars", function()
			local data = newData()
			local sold = pet("p", "Epic", 1, "Silver", true)
			table.insert(data.Pets, sold)
			data.Mount = "p"
			local price = Hatchery.sell(data, "p")
			expect.equal(price, PetWorth.sellPrice(sold))
			expect.equal(data.Dollars, price)
			expect.equal(#data.Pets, 0)
			expect.equal(data.Mount, "", "no longer riding a sold pet")
			expect.equal(Hatchery.sell(data, "p"), nil)
		end)

		it("chooses a pet to ride only from the player's own", function()
			local data = newData()
			table.insert(data.Pets, pet("mine", "Rare"))
			expect.truthy(Hatchery.setMount(data, "mine"))
			expect.equal(Hatchery.mount(data).uid, "mine")
			expect.falsy(Hatchery.setMount(data, "theirs"))
			expect.equal(data.Mount, "mine")
			expect.truthy(Hatchery.setMount(data, ""))
			expect.equal(Hatchery.mount(data), nil)
		end)

		it("buys a bigger pen with dollars, a level at a time", function()
			local data = newData()
			local ok, reason, cost = Hatchery.upgradePen(data)
			expect.falsy(ok)
			expect.equal(reason, "Money")
			expect.equal(cost, Economy.PEN_UPGRADE_COST[2])
			data.Dollars = cost + 10
			expect.truthy(Hatchery.upgradePen(data))
			expect.equal(data.PenLevel, 2)
			expect.equal(data.Dollars, 10)
			expect.equal(Hatchery.eggCapacity(data), 3)
			expect.equal(Hatchery.petCapacity(data), 11)
			data.PenLevel = Economy.MAX_PEN_LEVEL
			data.Dollars = 1e12
			ok, reason = Hatchery.upgradePen(data)
			expect.falsy(ok)
			expect.equal(reason, "Max")
		end)

		it("tells the device about everything, filling in eggs from before kinds existed", function()
			local data = newData()
			table.insert(data.Eggs, { uid = "old", zone = 1, rarity = "Common", claimedAt = 0 })
			table.insert(data.Pets, pet("p", "Rare", 1, "Normal", true))
			data.Dollars = 77
			local state = Hatchery.state(data)
			expect.equal(state.eggs[1].kind, "Leafy")
			expect.equal(state.penLevel, 1)
			expect.equal(state.eggCapacity, 2)
			expect.equal(state.petCapacity, 10)
			expect.equal(state.dollars, 77)
			expect.equal(state.income, 2.5)
			expect.equal(#state.hatching, 0)
			expect.equal(#state.pets, 1)
		end)
	end)
end
