--!nocheck
-- Checks that the config tables agree with each other and with the design request (docs/REQUEST.md).

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local Rarities = harness.load("src/shared/Config/Rarities")
	local Zones = harness.load("src/shared/Config/Zones")
	local Runway = harness.load("src/shared/Runway")
	local EggSpec = harness.load("src/shared/EggSpec")
	local Tuning = harness.load("src/shared/Config/Tuning")

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

	describe("Rarities: announcements", function()
		it("puts a message on screen only for Secret and rarer eggs", function()
			for _, rarity in Rarities.Order do
				local expected = Rarities.Info[rarity].order >= Rarities.Info.Secret.order
				expect.equal(Rarities.Info[rarity].announce, expected, rarity)
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

		it("starts every egg on the ground right at the start of its zone", function()
			for _, zone in Zones.List do
				for rarity in zone.stamina do
					local spec = EggSpec.get(zone.id, rarity)
					local back = spec.startZ - spec.radius
					expect.near(back, Runway.zoneStartZ(zone.id) + Tuning.EGG_SPAWN_GAP, 1e-9, rarity)
					expect.equal(Runway.zoneAt(back), zone.id, rarity .. " starts inside its own zone")
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
end
