--!nocheck
-- Checks the shop's packs (Config/Shop, Logic/Packs), revives (Logic/Revives), the pack-only trails and pets, the
-- leaderboards (Config/Leaderboards, Logic/Rankings, where HubLayout stands them) and the pet collection they count
-- (Logic/Hatchery), directly on config and saved-data tables.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local Economy = harness.load("src/shared/Config/Economy")
	local HubLayout = harness.load("src/shared/HubLayout")
	local Leaderboards = harness.load("src/shared/Config/Leaderboards")
	local PetModels = harness.load("src/shared/PetModels")
	local PetWorth = harness.load("src/shared/PetWorth")
	local Plots = harness.load("src/shared/Plots")
	local Runway = harness.load("src/shared/Runway")
	local Shop = harness.load("src/shared/Config/Shop")
	local Trails = harness.load("src/shared/Config/Trails")
	local Tuning = harness.load("src/shared/Config/Tuning")

	local Hatchery = harness.load("src/server/Logic/Hatchery")
	local Packs = harness.load("src/server/Logic/Packs")
	local Rankings = harness.load("src/server/Logic/Rankings")
	local Revives = harness.load("src/server/Logic/Revives")
	local Stalls = harness.load("src/server/Logic/Stalls")
	local Stats = harness.load("src/server/Logic/Stats")

	-- A player's saved data, shaped like DataService's template.
	local function newData()
		return {
			Dollars = 0,
			MaxStaminaBonus = 0,
			StaminaMultiplier = 1,
			TrainedStamina = 0,
			Eggs = {},
			Hatching = {},
			Pets = {},
			PenLevel = 1,
			Mount = "",
			Trails = { Owned = {}, Equipped = "" },
			Revives = 0,
			Packs = {},
			PackStamina = 1,
			Discovered = {},
			Stats = { EggsClaimed = 0, EggsSold = 0 },
		}
	end

	describe("Packs: the shop's packs", function()
		it("sells an Epic Pack and a Super Pack, each far cheaper than its parts", function()
			expect.equal(#Shop.Packs, 2)
			expect.equal(Shop.Sections[1], "Packs", "packs first in the shop")
			expect.truthy(table.find(Shop.Sections, "Revives"), "a Revives section")
			local epic, super = Shop.PacksById.EpicPack, Shop.PacksById.SuperPack
			expect.equal(epic.title, "EPIC PACK")
			expect.equal(super.title, "SUPER PACK")
			-- Worth: the parts at the shop's own prices (dollars at the best dollar pack's rate, the doublings that
			-- make the stamina boost, one revive at a time, the luck boost).
			expect.equal(Shop.packWorth(epic), 249 + (49 + 79 + 99) + 2 * 19)
			expect.equal(Shop.packWorth(super), 996 + (49 + 79 + 99 + 117) + 3 * 19 + 99)
			expect.equal(Shop.packDiscount(epic), 71)
			expect.equal(Shop.packDiscount(super), 80)
			-- The Super Pack has more of everything.
			expect.truthy(super.robux > epic.robux)
			expect.truthy(super.dollars > epic.dollars and super.stamina > epic.stamina, "more dollars and stamina")
			expect.truthy(super.revives > epic.revives and super.luck ~= nil and epic.luck == nil, "revives and luck")
		end)

		it("gives each pack its own pet in a variant only packs give, and its own trail", function()
			for _, pack in Shop.Packs do
				local origin = Shop.petOrigin(pack.pet.kind)
				expect.truthy(origin, pack.id .. " pet comes from a zone")
				expect.truthy(PetModels.describe(pack.pet.kind), pack.id .. " pet has a model")
				local variant = PetWorth.variant(pack.pet.variant)
				expect.equal(variant.name, pack.pet.variant)
				expect.equal(variant.chance, 0, pack.id .. " variant never hatches")
				local trail = Trails.ById[pack.trail]
				expect.truthy(trail and trail.pack == pack.id, pack.id .. " trail")
				expect.falsy(table.find(Trails.List, trail), "not sold at the stall")
				expect.truthy(table.find(Trails.PackList, trail), "listed as a pack trail")
			end
			-- The pack variants earn between Gold and Rainbow, and carry a rider faster than either.
			local molten = PetWorth.variant("Molten")
			expect.truthy(molten.worth > PetWorth.variant("Gold").worth, "worth more than Gold")
			expect.truthy(molten.speedBonus > PetWorth.variant("Rainbow").speedBonus, "fastest to ride")
			-- The Super Pack's pet earns about 25 times the Epic Pack's, like the reference.
			local function income(pack)
				local origin = Shop.petOrigin(pack.pet.kind)
				return PetWorth.income({ zone = origin.zone, rarity = origin.rarity, variant = pack.pet.variant })
			end
			local ratio = income(Shop.PacksById.SuperPack) / income(Shop.PacksById.EpicPack)
			expect.truthy(ratio > 15 and ratio < 40, `ratio {ratio}`)
			for _, entry in Economy.VARIANTS do
				expect.truthy(entry.chance >= 0, entry.name)
			end
		end)

		it("finds the developer product of a pack", function()
			Shop.PacksById.SuperPack.productId = 777
			local reward, itemId = Shop.rewardForProductId(777)
			expect.equal(reward.kind, "Pack")
			expect.equal(reward.packId, "SuperPack")
			expect.equal(itemId, "SuperPack")
			Shop.PacksById.SuperPack.productId = 0
			for _, pack in Shop.Packs do
				expect.falsy(Shop.ProductsById[pack.id], pack.id .. " id not shared with a product")
			end
		end)

		it("gives the pet, dollars, stamina boost, trail and revives, and remembers the pack", function()
			local data = newData()
			local pack = Shop.PacksById.EpicPack
			local pet = Packs.grant(data, pack, "pet-1", 50)
			expect.equal(pet.uid, "pet-1")
			expect.equal(pet.kind, "SabertoothCat")
			expect.equal(pet.variant, "Molten")
			expect.equal(pet.zone, 3)
			expect.equal(pet.rarity, "Legendary")
			expect.equal(pet.egg, "Sabertooth")
			expect.equal(pet.inPen, true, "straight into the pen")
			expect.equal(data.Dollars, pack.dollars)
			expect.equal(data.PackStamina, 8)
			expect.equal(data.Trails.Owned.Molten, true)
			expect.equal(data.Trails.Equipped, "Molten")
			expect.equal(data.Revives, 2)
			expect.equal(Packs.owns(data, "EpicPack"), true)
			expect.equal(Packs.owns(data, "SuperPack"), false)
			expect.equal(Hatchery.discoveredCount(data), 1)
			-- Max Stamina: 100 x8 for the pack x5 for its trail.
			expect.equal(Stats.maxStamina(data), 100 * 8 * 5)
		end)

		it("keeps the biggest stamina boost rather than adding packs up, and a better trail on", function()
			local data = newData()
			data.Trails.Owned.Rainbow = true
			data.Trails.Equipped = "Rainbow"
			Packs.grant(data, Shop.PacksById.SuperPack, "a", 0)
			Packs.grant(data, Shop.PacksById.EpicPack, "b", 0)
			expect.equal(data.PackStamina, 16)
			expect.equal(data.Trails.Equipped, "Rainbow", "the x25 trail stays on")
			expect.equal(data.Trails.Owned.Crystal, true)
			expect.equal(data.Trails.Owned.Molten, true)
			expect.equal(data.Revives, 5)
			expect.equal(#data.Pets, 2)
		end)
	end)

	describe("Packs: pack-only trails at the stall", function()
		it("never sells them for dollars, but packs give them", function()
			local data = newData()
			data.Dollars = 10 ^ 12
			local ok, result = Stalls.buyTrail(data, "Crystal")
			expect.equal(ok, false)
			expect.equal(result, "PackOnly")
			expect.equal(data.Dollars, 10 ^ 12)
			expect.equal(Stalls.giveTrail(data, "Crystal"), true)
			expect.equal(Stalls.giveTrail(data, "Crystal"), false, "only once")
			expect.equal(data.Trails.Equipped, "Crystal")
			-- Owned pack trails are listed after the stall's.
			Stalls.buyTrail(data, "Leaf")
			local owned = Stalls.ownedTrails(data)
			expect.equal(owned[1], "Leaf")
			expect.equal(owned[2], "Crystal")
			expect.equal(select(2, Stalls.equipTrail(data, "Leaf")), "Equipped")
			expect.equal(select(2, Stalls.equipTrail(data, "Crystal")), "Equipped")
		end)

		it("multiplies a rep on the training stick by the packs' boost too", function()
			local Training = harness.load("src/server/Logic/Training")
			local data = newData()
			data.Stats.TrainingReps = 0
			data.PackStamina = 8
			local gain = Training.addRep(data, false)
			expect.near(gain, 8)
			expect.near(Training.gainPerRep(data), 8)
		end)
	end)

	describe("Revives", function()
		it("offers a revive only to a player who has one, once at a time", function()
			local offers = {}
			local data = newData()
			expect.equal(Revives.offer(offers, data, 1, 100), nil)
			Revives.add(data, 2)
			expect.equal(Revives.count(data), 2)
			expect.equal(Revives.offer(offers, data, 1, 100), 100 + Tuning.REVIVE_OFFER_TIME)
			expect.equal(Revives.offer(offers, data, 1, 101), nil, "already on offer")
			expect.truthy(Revives.isWaiting(offers, 1, 100 + Tuning.REVIVE_OFFER_TIME), "waiting")
			expect.falsy(Revives.isWaiting(offers, 2, 100), "another player")
		end)

		it("uses one revive when the player says yes in time", function()
			local offers = {}
			local data = newData()
			Revives.add(data, 2)
			Revives.offer(offers, data, 1, 0)
			expect.equal(Revives.use(offers, data, 1, 3), true)
			expect.equal(data.Revives, 1)
			expect.equal(Revives.use(offers, data, 1, 3.5), false, "the offer is used up")
			expect.equal(data.Revives, 1)
			-- A second miss, a second offer.
			Revives.offer(offers, data, 1, 10)
			expect.equal(Revives.use(offers, data, 1, 11), true)
			expect.equal(data.Revives, 0)
		end)

		it("runs out: too late to say yes, and the server sends the player back", function()
			local offers = {}
			local data = newData()
			Revives.add(data, 1)
			Revives.offer(offers, data, 1, 0)
			local late = Tuning.REVIVE_OFFER_TIME + Tuning.LEAP_SERVER_GRACE + 0.1
			expect.equal(#Revives.expire(offers, Tuning.REVIVE_OFFER_TIME), 0, "the grace is allowed")
			local expired = Revives.expire(offers, late)
			expect.equal(#expired, 1)
			expect.equal(expired[1], 1)
			expect.equal(Revives.use(offers, data, 1, late), false)
			expect.equal(data.Revives, 1, "nothing used")
		end)

		it("forgets the offer when the player says no or dies", function()
			local offers = {}
			local data = newData()
			Revives.add(data, 1)
			Revives.offer(offers, data, 1, 0)
			Revives.cancel(offers, 1)
			expect.falsy(Revives.isWaiting(offers, 1, 1))
			expect.equal(Revives.use(offers, data, 1, 1), false)
			Revives.add(data, -5)
			expect.equal(data.Revives, 1, "never takes revives away")
		end)

		it("sells revives in the shop", function()
			local total = 0
			for _, product in Shop.productsIn("Revives") do
				expect.equal(product.grant.kind, "Revives")
				expect.truthy(product.grant.amount > total, product.id .. " gives more")
				total = product.grant.amount
			end
			expect.equal(total, 15)
		end)
	end)

	describe("Leaderboards", function()
		it("has three boards: Top Stamina, Top Collectors and Top Earners", function()
			local active = Leaderboards.active()
			expect.equal(#active, 3)
			expect.equal(#active, HubLayout.LEADERBOARD_COUNT)
			expect.equal(active[1].title, "TOP STAMINA")
			expect.equal(active[2].title, "TOP COLLECTORS")
			expect.equal(active[3].title, "TOP EARNERS")
			local stores = {}
			for _, board in Leaderboards.List do
				expect.falsy(stores[board.store], board.id .. " store")
				stores[board.store] = true
			end
			-- The first board is shelved, not gone.
			expect.equal(Leaderboards.ById.EggClaimers.shelved, true)
		end)

		it("writes scores the way each board counts", function()
			local stamina, collectors, earners =
				Leaderboards.ById.Stamina, Leaderboards.ById.Collectors, Leaderboards.ById.Earners
			expect.equal(Leaderboards.formatScore(stamina, 24800000000000), "24.8T")
			expect.equal(Leaderboards.formatScore(collectors, 1629), "1,629")
			expect.equal(Leaderboards.formatScore(collectors, 42), "42")
			expect.equal(Leaderboards.formatScore(earners, 85120000000), "$85.1B")
			expect.equal(Leaderboards.formatRank(4), "#4")
			expect.equal(Leaderboards.formatRank(250), "#100+")
			expect.equal(Leaderboards.formatRank(0), "-")
		end)

		it("ranks every server's best with this server's live scores on top", function()
			local global = { [1] = 500, [2] = 900, [3] = 40 }
			-- Player 2 took off a trail (their score went down); player 9 is new.
			local ranking = Rankings.rank(global, { [2] = 300, [9] = 300, [4] = 0 })
			expect.equal(#ranking, 4, "nobody with nothing")
			expect.equal(ranking[1].userId, 1)
			expect.equal(ranking[2].userId, 2, "ties go to the lower user ID")
			expect.equal(ranking[3].userId, 9)
			expect.equal(ranking[4].userId, 3)
			expect.equal(Rankings.rankOf(ranking, 9), 3)
			expect.equal(Rankings.rankOf(ranking, 4), 0)
			expect.equal(Rankings.stored(123.9), 123)
			expect.equal(Rankings.stored(0 / 0), 0)
			expect.equal(Rankings.stored(10 ^ 30), 2 ^ 53)
		end)

		it("stands the boards in a row beside the start zone, clear of the plots and stations", function()
			local startZone = { x = 0, z = -15, sizeX = Runway.START_WIDTH + 4, sizeZ = 30 }
			local rects = {}
			for index = 1, HubLayout.LEADERBOARD_COUNT do
				local rect = HubLayout.leaderboardRect(index)
				table.insert(rects, rect)
				local minX, maxX, minZ, maxZ = HubLayout.bounds(rect)
				expect.truthy(minX >= -HubLayout.HALF_WIDTH and maxX <= HubLayout.HALF_WIDTH, `board {index} x`)
				expect.truthy(minZ >= -HubLayout.LENGTH and maxZ <= 0, `board {index} z`)
				expect.falsy(HubLayout.rectsOverlap(rect, startZone), `board {index} on the start zone`)
				for plot = 1, Plots.COUNT do
					local x, z, sizeX, sizeZ = Plots.rect(plot)
					expect.falsy(
						HubLayout.rectsOverlap(rect, { x = x, z = z, sizeX = sizeX, sizeZ = sizeZ }),
						`board {index} on plot {plot}`
					)
					local sx, sz, ssx, ssz = Plots.stickRect(plot)
					expect.falsy(
						HubLayout.rectsOverlap(rect, { x = sx, z = sz, sizeX = ssx, sizeZ = ssz }),
						`board {index} on stick {plot}`
					)
				end
				for key, station in HubLayout.STATIONS do
					local around = HubLayout.STATION_RADIUS
					expect.falsy(
						HubLayout.rectsOverlap(
							rect,
							{ x = station.x, z = station.z, sizeX = around * 2, sizeZ = around * 2 }
						),
						`board {index} on {key}`
					)
				end
				if index > 1 then
					-- Left to right, walking up to the start zone (facing +z, left is +x).
					expect.truthy(rect.x < rects[index - 1].x, `board {index} right of board {index - 1}`)
					expect.falsy(HubLayout.rectsOverlap(rect, rects[index - 1]), `boards {index - 1} and {index}`)
				end
			end
		end)
	end)

	describe("The pet collection", function()
		it("counts each pet in each variant once, and keeps it when the pet is sold", function()
			local data = newData()
			Hatchery.discover(data, { kind = "Fox", variant = "Normal" })
			Hatchery.discover(data, { kind = "Fox", variant = "Normal" })
			Hatchery.discover(data, { kind = "Fox", variant = "Gold" })
			Hatchery.discover(data, { kind = "Owl" })
			expect.equal(Hatchery.discoveredCount(data), 3)
			expect.equal(Hatchery.discoveryKey({ kind = "Owl" }), "Owl/Normal")
		end)

		it("counts a hatched pet, and an old save's pets", function()
			local data = newData()
			local entry = { uid = "e", zone = 1, rarity = "Common", kind = "Leafy", placedAt = 0, bonus = 0 }
			table.insert(data.Hatching, entry)
			Hatchery.hatch(data, entry, 100, "p", 0.99)
			expect.equal(Hatchery.discoveredCount(data), 1)

			local old = newData()
			old.Discovered = nil
			old.Pets = {
				{ uid = "a", kind = "Bear", egg = "Bear", zone = 1, rarity = "Epic", variant = "Normal", inPen = true },
				{ uid = "b", kind = "Bear", egg = "Bear", zone = 1, rarity = "Epic", variant = "Gold", inPen = true },
				{ uid = "c", kind = "Bear", egg = "Bear", zone = 1, rarity = "Epic", variant = "Gold", inPen = false },
			}
			Hatchery.migrate(old, 3)
			expect.equal(Hatchery.discoveredCount(old), 2)
		end)
	end)
end
