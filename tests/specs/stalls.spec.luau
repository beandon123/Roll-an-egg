--!nocheck
-- Checks the hub stall rules (Logic/Stalls) and the numbers worked out from saved data (Logic/Stats), directly on
-- saved-data tables.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local Stalls = harness.load("src/server/Logic/Stalls")
	local Stats = harness.load("src/server/Logic/Stats")
	local Trails = harness.load("src/shared/Config/Trails")

	-- A player's saved data, shaped like DataService's template.
	local function newData(dollars, eggs)
		return {
			Dollars = dollars or 0,
			MaxStaminaBonus = 0,
			StaminaMultiplier = 1,
			Eggs = eggs or {},
			Pets = {},
			Trails = { Owned = {}, Equipped = "" },
			Stats = { EggsClaimed = 0, EggsSold = 0 },
		}
	end

	local function egg(zone, rarity, kind, uid)
		return { uid = uid or "x", zone = zone, rarity = rarity, kind = kind, claimedAt = 0 }
	end

	describe("Stalls: trails", function()
		it("buys a trail, takes its price, and equips it", function()
			local data = newData(150)
			local ok, result = Stalls.buyTrail(data, "Leaf")
			expect.equal(ok, true)
			expect.equal(result, "BoughtAndEquipped")
			expect.equal(data.Dollars, 50)
			expect.equal(data.Trails.Owned.Leaf, true)
			expect.equal(data.Trails.Equipped, "Leaf")
		end)

		it("refuses unknown trails, trails already owned, and trails the player cannot afford", function()
			local data = newData(120)
			expect.equal(select(2, Stalls.buyTrail(data, "Nope")), "Unknown")
			expect.equal(select(2, Stalls.buyTrail(data, "Sunbeam")), "NotEnoughDollars")
			expect.equal(data.Dollars, 120)
			Stalls.buyTrail(data, "Leaf")
			local ok, result = Stalls.buyTrail(data, "Leaf")
			expect.equal(ok, false)
			expect.equal(result, "Owned")
			expect.equal(data.Dollars, 20, "charged once")
		end)

		it("does not swap a better equipped trail for a weaker one just bought", function()
			local data = newData(10000)
			Stalls.buyTrail(data, "Sandstorm")
			local ok, result = Stalls.buyTrail(data, "Leaf")
			expect.equal(ok, true)
			expect.equal(result, "Bought")
			expect.equal(data.Trails.Equipped, "Sandstorm")
		end)

		it("equips only trails the player owns", function()
			local data = newData(10000)
			Stalls.buyTrail(data, "Leaf")
			Stalls.buyTrail(data, "Sunbeam")
			expect.equal(select(2, Stalls.equipTrail(data, "Frost")), "NotOwned")
			expect.equal(select(2, Stalls.equipTrail(data, "Nope")), "Unknown")
			local ok, result = Stalls.equipTrail(data, "Leaf")
			expect.equal(ok, true)
			expect.equal(result, "Equipped")
			expect.equal(data.Trails.Equipped, "Leaf")
			local owned = Stalls.ownedTrails(data)
			expect.equal(#owned, 2)
			expect.equal(owned[1], "Leaf")
			expect.equal(owned[2], "Sunbeam")
		end)

		it("multiplies Max Stamina by the equipped trail", function()
			local data = newData(100000)
			expect.equal(Stats.maxStamina(data), 100)
			expect.equal(Stats.trailMultiplier(data), 1)
			Stalls.buyTrail(data, "Leaf")
			expect.near(Stats.maxStamina(data), 120)
			Stalls.buyTrail(data, "Frost")
			expect.near(Stats.maxStamina(data), 300)
			-- On top of Max Stamina bought in the shop and its doublings.
			data.MaxStaminaBonus = 400
			data.StaminaMultiplier = 2
			expect.near(Stats.maxStamina(data), 3000)
			-- Old saves from before trails existed have no trail data at all.
			expect.equal(Stats.maxStamina({ Dollars = 0 }), 100)
		end)

		it("lets trails alone carry a new player to the Desert", function()
			-- Riding drains 80% of an egg's requirement, so that much stamina is enough to claim it.
			local function canClaim(trailId, requirement)
				return 100 * Trails.ById[trailId].stamina >= requirement * 0.8
			end
			expect.truthy(canClaim("Frost", 350), "Frost holds a Forest Legendary")
			expect.truthy(canClaim("Bubble", 500), "Bubble holds a Desert Common")
		end)
	end)

	describe("Stalls: selling eggs", function()
		it("sells eggs of one kind for half their stamina requirement each", function()
			local data = newData(0, {
				egg(1, "Common", "Leafy", "a"),
				egg(1, "Rare", "Toadstool", "b"),
				egg(1, "Common", "Leafy", "c"),
				egg(1, "Common", "Cottontail", "d"),
				egg(1, "Common", "Leafy", "e"),
			})
			local sold, dollars = Stalls.sellEggs(data, "Leafy", 2)
			expect.equal(sold, 2)
			expect.equal(dollars, 50)
			expect.equal(data.Dollars, 50)
			expect.equal(data.Stats.EggsSold, 2)
			expect.equal(#data.Eggs, 3)
			-- Newest first, and the other kinds are untouched.
			expect.equal(data.Eggs[1].uid, "a")
			expect.equal(data.Eggs[2].uid, "b")
			expect.equal(data.Eggs[3].uid, "d")
		end)

		it("sells no more than the player has", function()
			local data = newData(0, { egg(2, "Mythic", "Sphinx"), egg(2, "Mythic", "Sphinx") })
			local sold, dollars = Stalls.sellEggs(data, "Sphinx", 99)
			expect.equal(sold, 2)
			expect.equal(dollars, 1800)
			expect.equal(#data.Eggs, 0)
		end)

		it("sells eggs saved before eggs had kinds as their zone's egg of that rarity", function()
			local data = newData(0, { { uid = "old", zone = 1, rarity = "Rare", claimedAt = 0 } })
			local sold, dollars = Stalls.sellEggs(data, "Toadstool", 1)
			expect.equal(sold, 1)
			expect.equal(dollars, 60)
		end)

		it("sells nothing for eggs that are not held, or a count of zero", function()
			local data = newData(0, { egg(1, "Common", "Leafy") })
			for _, case in { { "Treant", 1 }, { "Nope", 1 }, { "Leafy", 0 } } do
				local sold, dollars = Stalls.sellEggs(data, case[1], case[2])
				expect.equal(sold, 0)
				expect.equal(dollars, 0)
			end
			expect.equal(data.Dollars, 0)
			expect.equal(#data.Eggs, 1)
		end)
	end)
end
