--!nocheck
-- Checks the hub shop rules (Logic/Shop), the numbers worked out from saved data (Logic/Stats), and the egg
-- summaries sent to clients (Logic/Inventory), directly on saved-data tables.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local Shop = harness.load("src/server/Logic/Shop")
	local Stats = harness.load("src/server/Logic/Stats")
	local Inventory = harness.load("src/server/Logic/Inventory")
	local Trails = harness.load("src/shared/Config/Trails")

	-- A player's saved data, shaped like DataService's template.
	local function newData(coins, eggs)
		return {
			Coins = coins or 0,
			Eggs = eggs or {},
			Pets = {},
			Trails = { Owned = {}, Equipped = "" },
			Stats = { EggsClaimed = 0, EggsSold = 0 },
		}
	end

	local function egg(zone, rarity, uid)
		return { uid = uid or "x", zone = zone, rarity = rarity, claimedAt = 0 }
	end

	describe("Shop: trails", function()
		it("buys a trail, takes its price, and equips it", function()
			local data = newData(150)
			local ok, result = Shop.buyTrail(data, "Leaf")
			expect.equal(ok, true)
			expect.equal(result, "BoughtAndEquipped")
			expect.equal(data.Coins, 50)
			expect.equal(data.Trails.Owned.Leaf, true)
			expect.equal(data.Trails.Equipped, "Leaf")
		end)

		it("refuses unknown trails, trails already owned, and trails the player cannot afford", function()
			local data = newData(120)
			expect.equal(select(2, Shop.buyTrail(data, "Nope")), "Unknown")
			expect.equal(select(2, Shop.buyTrail(data, "Sunbeam")), "NotEnoughCoins")
			expect.equal(data.Coins, 120)
			Shop.buyTrail(data, "Leaf")
			local ok, result = Shop.buyTrail(data, "Leaf")
			expect.equal(ok, false)
			expect.equal(result, "Owned")
			expect.equal(data.Coins, 20, "charged once")
		end)

		it("does not swap a better equipped trail for a weaker one just bought", function()
			local data = newData(10000)
			Shop.buyTrail(data, "Sandstorm")
			local ok, result = Shop.buyTrail(data, "Leaf")
			expect.equal(ok, true)
			expect.equal(result, "Bought")
			expect.equal(data.Trails.Equipped, "Sandstorm")
		end)

		it("equips only trails the player owns", function()
			local data = newData(10000)
			Shop.buyTrail(data, "Leaf")
			Shop.buyTrail(data, "Sunbeam")
			expect.equal(select(2, Shop.equipTrail(data, "Frost")), "NotOwned")
			expect.equal(select(2, Shop.equipTrail(data, "Nope")), "Unknown")
			local ok, result = Shop.equipTrail(data, "Leaf")
			expect.equal(ok, true)
			expect.equal(result, "Equipped")
			expect.equal(data.Trails.Equipped, "Leaf")
			local owned = Shop.ownedTrails(data)
			expect.equal(#owned, 2)
			expect.equal(owned[1], "Leaf")
			expect.equal(owned[2], "Sunbeam")
		end)

		it("multiplies Max Stamina by the equipped trail", function()
			local data = newData(100000)
			expect.equal(Stats.maxStamina(data), 100)
			expect.equal(Stats.trailMultiplier(data), 1)
			Shop.buyTrail(data, "Leaf")
			expect.near(Stats.maxStamina(data), 120)
			Shop.buyTrail(data, "Frost")
			expect.near(Stats.maxStamina(data), 300)
			-- Old saves from before trails existed have no trail data at all.
			expect.equal(Stats.maxStamina({ Coins = 0 }), 100)
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

	describe("Shop: selling eggs", function()
		it("sells eggs of one kind for half their stamina requirement each", function()
			local data = newData(0, {
				egg(1, "Common", "a"),
				egg(1, "Rare", "b"),
				egg(1, "Common", "c"),
				egg(2, "Common", "d"),
				egg(1, "Common", "e"),
			})
			local sold, coins = Shop.sellEggs(data, 1, "Common", 2)
			expect.equal(sold, 2)
			expect.equal(coins, 50)
			expect.equal(data.Coins, 50)
			expect.equal(data.Stats.EggsSold, 2)
			expect.equal(#data.Eggs, 3)
			-- The other kinds are untouched; one Forest Common is left.
			local left = Inventory.eggGroups(data.Eggs)
			expect.equal(#left, 3)
			expect.equal(left[1].rarity, "Common")
			expect.equal(left[1].count, 1)
		end)

		it("sells no more than the player has", function()
			local data = newData(0, { egg(2, "Mythic"), egg(2, "Mythic") })
			local sold, coins = Shop.sellEggs(data, 2, "Mythic", 99)
			expect.equal(sold, 2)
			expect.equal(coins, 1800)
			expect.equal(#data.Eggs, 0)
		end)

		it("sells nothing for eggs that cannot exist or are not held", function()
			local data = newData(0, { egg(1, "Common") })
			for _, case in { { 1, "Mythic", 1 }, { 9, "Common", 1 }, { 1, "Rare", 1 }, { 1, "Common", 0 } } do
				local sold, coins = Shop.sellEggs(data, case[1], case[2], case[3])
				expect.equal(sold, 0)
				expect.equal(coins, 0)
			end
			expect.equal(data.Coins, 0)
			expect.equal(#data.Eggs, 1)
		end)
	end)

	describe("Inventory", function()
		it("groups eggs by zone, then from Common to rarest", function()
			local groups = Inventory.eggGroups({
				egg(2, "Common"),
				egg(1, "Legendary"),
				egg(1, "Common"),
				egg(1, "Legendary"),
				egg(1, "Rare"),
			})
			expect.equal(#groups, 4)
			local expected = { { 1, "Common", 1 }, { 1, "Rare", 1 }, { 1, "Legendary", 2 }, { 2, "Common", 1 } }
			for index, want in expected do
				expect.equal(groups[index].zone, want[1])
				expect.equal(groups[index].rarity, want[2])
				expect.equal(groups[index].count, want[3])
			end
			expect.equal(#Inventory.eggGroups({}), 0)
		end)
	end)
end
