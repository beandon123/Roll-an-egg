--!nocheck
-- Tests for eggs, nests and pets: the plot layout, hatch timing (with the closure boost), and the hatchery rules.

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
		return { Eggs = {}, Nests = {}, Pets = {}, NestCount = 2 }
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

		it("puts nests, pets and the spawn where they belong", function()
			for index = 1, Plots.COUNT do
				local x, z = Plots.center(index)
				local spots = {}
				for slot = 1, Plots.MAX_NESTS do
					local nx, nz = Plots.nestPoint(index, slot)
					expect.truthy(math.abs(nx - x) < Plots.WIDTH / 2 - 4, "nest inside the plot")
					expect.truthy(math.abs(nz - z) < Plots.DEPTH / 2 - 4, "nest inside the plot")
					expect.truthy(math.abs(nz - z) > Plots.GATE_HALF_WIDTH + 4, "nest clear of the path from the gate")
					for _, other in spots do
						expect.truthy(math.abs(nx - other[1]) >= 10 or math.abs(nz - other[2]) >= 10, "nests apart")
					end
					table.insert(spots, { nx, nz })
				end
				local x0, x1, z0, z1 = Plots.roamArea(index, 5)
				expect.truthy(x0 < x1 and z0 < z1)
				expect.truthy(math.min(math.abs(x0), math.abs(x1)) > Plots.PLAZA_HALF_WIDTH + 45, "beyond the nests")
				expect.truthy(math.max(math.abs(x0), math.abs(x1)) <= Plots.PLAZA_HALF_WIDTH + Plots.WIDTH - 5)
				local sx = Plots.spawnPoint(index)
				expect.truthy(math.abs(sx) < Plots.PLAZA_HALF_WIDTH, "spawn in the plaza")
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

	describe("Hatchery", function()
		it("moves an egg from the inventory into the first free nest", function()
			local data = newData()
			addEgg(data, "a", 1, "Rare", "Toadstool")
			addEgg(data, "b", 1, "Common", "Leafy")
			local nest = Hatchery.place(data, "b", OPEN)
			expect.equal(nest.slot, 1)
			expect.equal(nest.kind, "Leafy")
			expect.equal(nest.placedAt, OPEN)
			expect.equal(nest.bonus, 0)
			expect.equal(#data.Eggs, 1)
			expect.equal(data.Eggs[1].uid, "a")
			expect.equal(Hatchery.place(data, "a", OPEN).slot, 2)
		end)

		it("refuses eggs it does not have, and full nests", function()
			local data = newData()
			for index = 1, 3 do
				addEgg(data, "egg" .. index, 1, "Common", "Leafy")
			end
			local nest, reason = Hatchery.place(data, "nope", OPEN)
			expect.falsy(nest)
			expect.equal(reason, "NoEgg")
			Hatchery.place(data, "egg1", OPEN)
			Hatchery.place(data, "egg2", OPEN)
			nest, reason = Hatchery.place(data, "egg3", OPEN)
			expect.falsy(nest)
			expect.equal(reason, "NestsFull")
			expect.equal(#data.Eggs, 1, "still in the inventory")
			-- A third nest makes room.
			data.NestCount = 3
			expect.equal(Hatchery.place(data, "egg3", OPEN).slot, 3)
		end)

		it("hatches an egg into its pet when its time is up, emptying the nest", function()
			local data = newData()
			addEgg(data, "a", 1, "Common", "Leafy")
			local nest = Hatchery.place(data, "a", OPEN)
			expect.equal(#Hatchery.ready(data, OPEN + 29), 0)
			local ready = Hatchery.ready(data, OPEN + 30)
			expect.equal(#ready, 1)
			local pet = Hatchery.hatch(data, ready[1], OPEN + 30, "pet-1")
			expect.equal(pet.kind, "Squirrel")
			expect.equal(pet.egg, "Leafy")
			expect.equal(pet.rarity, "Common")
			expect.equal(pet.zone, 1)
			expect.equal(pet.uid, "pet-1")
			expect.equal(#data.Nests, 0)
			expect.equal(data.Pets[1], pet)
			expect.falsy(Hatchery.hatch(data, nest, OPEN + 31, "again"), "a nest hatches once")
			-- The nest is free again.
			addEgg(data, "b", 1, "Common", "Cottontail")
			expect.equal(Hatchery.place(data, "b", OPEN + 31).slot, 1)
		end)

		it("hatches while the player is away: the timer is just timestamps", function()
			local data = newData()
			addEgg(data, "a", 6, "Eternal", "LunarDragon")
			Hatchery.place(data, "a", OPEN)
			expect.equal(#Hatchery.ready(data, OPEN + 5 * 3600), 0)
			expect.equal(#Hatchery.ready(data, OPEN + 6 * 3600), 1)
		end)

		it("banks each closure's boost on every nest", function()
			local data = newData()
			addEgg(data, "a", 1, "Epic", "Bear")
			local cycleStart = 180 * 600
			Hatchery.place(data, "a", cycleStart - 60)
			Hatchery.commitClosure(data, cycleStart)
			expect.near(data.Nests[1].bonus, (Tuning.HATCH_BOOST - 1) * CycleClock.CLOSED_LENGTH)
		end)

		it("fills the pen with the rarest pets, newest first among equals", function()
			local data = newData()
			local rarities = { "Common", "Epic", "Common", "Mythic", "Epic" }
			for index, rarity in rarities do
				table.insert(
					data.Pets,
					{ uid = "p" .. index, kind = "Bear", egg = "Bear", zone = 1, rarity = rarity, hatchedAt = index }
				)
			end
			local pen = Hatchery.penPets(data, 3)
			expect.equal(#pen, 3)
			expect.equal(pen[1].uid, "p4")
			expect.equal(pen[2].uid, "p5")
			expect.equal(pen[3].uid, "p2")
			expect.equal(#Hatchery.penPets(data, 10), 5)
		end)

		it("tells the device about everything, filling in eggs from before kinds existed", function()
			local data = newData()
			table.insert(data.Eggs, { uid = "old", zone = 1, rarity = "Common", claimedAt = 0 })
			local state = Hatchery.state(data)
			expect.equal(state.eggs[1].kind, "Leafy")
			expect.equal(state.nestCount, 2)
			expect.equal(#state.nests, 0)
			expect.equal(#state.pets, 0)
			-- It hatches like any other.
			Hatchery.place(data, "old", OPEN)
			expect.equal(data.Nests[1].kind, "Leafy")
		end)
	end)
end
