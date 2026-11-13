--!nocheck
-- Checks that the config tables agree with each other and with the design request (docs/REQUEST.md).

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local Rarities = harness.load("src/shared/Config/Rarities")
	local Zones = harness.load("src/shared/Config/Zones")
	local Runway = harness.load("src/shared/Runway")
	local EggSpec = harness.load("src/shared/EggSpec")
	local Settings = harness.load("src/shared/Config/Settings")
	local Shop = harness.load("src/shared/Config/Shop")

	describe("Rarities", function()
		it("has info for every rarity, in order", function()
			expect.equal(#Rarities.Order, 8)
			for index, rarity in Rarities.Order do
				local info = Rarities.Info[rarity]
				expect.truthy(info, rarity)
				expect.equal(info.order, index, rarity .. " order")
			end
		end)

		it("gets bigger, slower to claim, and faster as rarity rises", function()
			for index = 2, #Rarities.Order do
				local lower = Rarities.Info[Rarities.Order[index - 1]]
				local higher = Rarities.Info[Rarities.Order[index]]
				expect.truthy(higher.size > lower.size, "size")
				expect.truthy(higher.claimTime > lower.claimTime, "claimTime")
				expect.truthy(higher.rollSpeed > lower.rollSpeed, "rollSpeed")
				expect.truthy(higher.bounces >= lower.bounces, "bounces")
				expect.truthy(higher.hatchTime > lower.hatchTime, "hatchTime")
			end
		end)
	end)

	describe("Zones", function()
		it("has one zone per runway segment, in order", function()
			expect.equal(#Zones.List, Runway.ZONE_COUNT)
			local names = { "Forest", "Desert", "Snow", "Ocean", "Volcano" }
			for index, zone in Zones.List do
				expect.equal(zone.id, index)
				expect.equal(zone.name, names[index])
			end
		end)

		it("caps each zone at the agreed rarity", function()
			local caps = { "Legendary", "Mythic", "Secret", "Secret", "Eternal" }
			for index, zone in Zones.List do
				local highest = 0
				for rarity in zone.stamina do
					highest = math.max(highest, Rarities.Info[rarity].order)
				end
				expect.equal(Rarities.Order[highest], caps[index], zone.name .. " cap")
			end
		end)

		it("gives every droppable rarity a stamina requirement and a drop weight, and nothing else", function()
			for _, zone in Zones.List do
				for rarity in zone.stamina do
					expect.truthy(Rarities.Info[rarity], rarity)
					expect.truthy((zone.weights[rarity] or 0) > 0, zone.name .. " weight for " .. rarity)
				end
				for rarity in zone.weights do
					expect.truthy(zone.stamina[rarity], zone.name .. " stamina for " .. rarity)
				end
			end
		end)

		it("needs more stamina for rarer eggs and for deeper zones", function()
			local previousTop = 0
			for _, zone in Zones.List do
				local last = 0
				for _, rarity in Rarities.Order do
					local requirement = zone.stamina[rarity]
					if requirement then
						expect.truthy(requirement > last, zone.name .. " " .. rarity)
						last = requirement
					end
				end
				expect.truthy(zone.stamina.Common > previousTop, zone.name .. " starts above the previous zone")
				previousTop = last
			end
		end)

		it("uses the zone baselines from the request", function()
			expect.equal(Zones.List[1].stamina.Common, 50)
			expect.equal(Zones.List[2].stamina.Common, 500)
			expect.equal(Zones.List[3].stamina.Common, 2000)
		end)
	end)

	describe("EggSpec", function()
		it("builds a spec for every egg that can drop", function()
			for _, zone in Zones.List do
				for rarity in zone.stamina do
					local spec = EggSpec.get(zone.id, rarity)
					expect.truthy(spec, zone.name .. " " .. rarity)
					expect.equal(spec.requirement, zone.stamina[rarity])
					-- A full claim drains 80% of the requirement.
					expect.near(spec.drain * spec.claimTime, spec.requirement * 0.8, 1e-6)
				end
			end
		end)

		it("returns nil for an egg that cannot drop in a zone", function()
			expect.falsy(EggSpec.get(1, "Mythic"))
			expect.falsy(EggSpec.get(4, "Eternal"))
			expect.falsy(EggSpec.get(9, "Common"))
		end)

		it("only rolls rarities the zone allows", function()
			for _, zone in Zones.List do
				for step = 0, 999 do
					local rarity = EggSpec.rollRarity(zone.id, step / 1000)
					expect.truthy(zone.stamina[rarity], zone.name .. " rolled " .. rarity)
				end
				expect.equal(EggSpec.rollRarity(zone.id, 0), "Common")
			end
			expect.equal(EggSpec.rollRarity(1, 0.9999), "Legendary")
			expect.equal(EggSpec.rollRarity(5, 0.99999), "Eternal")
		end)

		it("fits every egg on the runway with room to steer", function()
			for _, zone in Zones.List do
				for rarity in zone.stamina do
					local spec = EggSpec.get(zone.id, rarity)
					expect.truthy(Runway.maxLateral(spec.halfLength) > 10, rarity .. " steering room")
				end
			end
		end)

		it("lets every egg be claimed before it rolls off the end of the runway", function()
			for _, zone in Zones.List do
				for rarity in zone.stamina do
					local spec = EggSpec.get(zone.id, rarity)
					local rideDistance = spec.rollSpeed * spec.claimTime
					local room = Runway.LENGTH - Runway.zoneStartZ(zone.id)
					expect.truthy(rideDistance < room * 0.95, zone.name .. " " .. rarity)
				end
			end
		end)
	end)

	describe("Shop", function()
		it("lists every product once, in a known section, with a price and a reward", function()
			local seen = {}
			local sections = {}
			for _, name in Shop.Sections do
				sections[name] = true
			end
			local kinds = { Coins = true, MaxStamina = true, Luck = true }
			for _, product in Shop.Products do
				expect.falsy(seen[product.id], "duplicate id " .. product.id)
				seen[product.id] = true
				expect.truthy(sections[product.section], product.id .. " section")
				expect.truthy(product.robux > 0, product.id .. " price")
				expect.equal(product.productId, math.floor(product.productId), product.id .. " product ID")
				expect.truthy(kinds[product.grant.kind], product.id .. " grant")
				expect.truthy(Shop.ProductsById[product.id] == product, product.id .. " lookup")
			end
			for _, pass in Shop.Passes do
				expect.falsy(seen[pass.id], "duplicate id " .. pass.id)
				seen[pass.id] = true
				expect.truthy(pass.robux > 0, pass.id .. " price")
			end
			expect.falsy(seen[Shop.PEN_UPGRADE_ID], "the pen upgrade id is not used by anything else")
		end)

		it("lists each section's products in order, bigger packs costing more", function()
			for _, section in { "Luck", "Stamina", "Coins" } do
				local products = Shop.productsIn(section)
				expect.truthy(#products >= 2, section)
				for index = 2, #products do
					expect.truthy(products[index].order > products[index - 1].order, section .. " order")
					expect.truthy(products[index].robux > products[index - 1].robux, section .. " price")
				end
			end
		end)

		it("sells pen levels 2 to 9, holding 10 pets at level 1 and 18 at the top (REQUEST)", function()
			expect.equal(Shop.penCapacity(1), 10)
			expect.equal(Shop.penCapacity(Shop.MAX_PEN_LEVEL), 18)
			expect.equal(Shop.PenLevels[1], nil)
			for level = 2, Shop.MAX_PEN_LEVEL do
				local penLevel = Shop.PenLevels[level]
				expect.truthy(penLevel, "level " .. level)
				expect.equal(penLevel.level, level)
				if level > 2 then
					expect.truthy(penLevel.coins > Shop.PenLevels[level - 1].coins, "coins rise")
					expect.truthy(penLevel.robux > Shop.PenLevels[level - 1].robux, "Robux rise")
				end
			end
			expect.equal(Shop.PenLevels[Shop.MAX_PEN_LEVEL + 1], nil)
		end)

		it("never matches the unset product ID 0", function()
			local product, penLevel = Shop.findByProductId(0)
			expect.equal(product, nil)
			expect.equal(penLevel, nil)
		end)

		it("works out Max Stamina from the base, the bonus bought, and the pass", function()
			expect.equal(Shop.maxStamina(100, 0, false), 100)
			expect.equal(Shop.maxStamina(100, 500, false), 600)
			expect.equal(Shop.maxStamina(100, 500, true), 1200)
		end)
	end)

	describe("Settings", function()
		it("lists every setting once, under a known section, with a default of the right type", function()
			local seen = {}
			local sections = {}
			for _, name in Settings.Sections do
				sections[name] = 0
			end
			for _, setting in Settings.List do
				expect.falsy(seen[setting.key], "duplicate " .. setting.key)
				seen[setting.key] = true
				expect.truthy(sections[setting.section], setting.key .. " section")
				sections[setting.section] += 1
				if setting.kind == "Slider" then
					expect.equal(type(setting.default), "number", setting.key)
					expect.truthy(setting.default >= 0 and setting.default <= 1, setting.key .. " range")
				else
					expect.equal(type(setting.default), "boolean", setting.key)
				end
			end
			for name, count in sections do
				expect.truthy(count > 0, name .. " has settings")
			end
		end)

		it("only lets valid values be saved", function()
			expect.equal(Settings.sanitize("MusicVolume", 0.456), 0.46)
			expect.equal(Settings.sanitize("MusicVolume", 7), 1)
			expect.equal(Settings.sanitize("MusicVolume", -2), 0)
			expect.equal(Settings.sanitize("MusicVolume", 0 / 0), nil)
			expect.equal(Settings.sanitize("MusicVolume", true), nil)
			expect.equal(Settings.sanitize("ShowMyPets", false), false)
			expect.equal(Settings.sanitize("ShowMyPets", 1), nil)
			expect.equal(Settings.sanitize("NotASetting", 1), nil)
			expect.equal(Settings.sanitize(5, 1), nil)
		end)

		it("fills in defaults around valid saved values", function()
			local values = Settings.withDefaults({ MusicVolume = 0.3, ShowMyPets = "no", Junk = 1 })
			expect.equal(values.MusicVolume, 0.3)
			expect.equal(values.ShowMyPets, true)
			expect.equal(values.Junk, nil)
			expect.equal(Settings.withDefaults(nil).Vibration, true)
		end)
	end)
end
