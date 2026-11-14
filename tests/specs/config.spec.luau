--!nocheck
-- Checks that the config tables agree with each other and with the design request (docs/REQUEST.md).

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local Rarities = harness.load("src/shared/Config/Rarities")
	local Zones = harness.load("src/shared/Config/Zones")
	local Runway = harness.load("src/shared/Runway")
	local EggSpec = harness.load("src/shared/EggSpec")

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
			local names = { "Forest", "Desert", "Snow", "Ocean", "Volcano", "Prehistoric" }
			for index, zone in Zones.List do
				expect.equal(zone.id, index)
				expect.equal(zone.name, names[index])
			end
		end)

		it("gives every zone 8 eggs in the agreed mix of rarities", function()
			local mixes = {
				{ Common = 2, Uncommon = 2, Rare = 1, Epic = 1, Legendary = 1, Mythic = 1 },
				{ Common = 1, Uncommon = 2, Rare = 1, Epic = 1, Legendary = 1, Mythic = 2 },
				{ Uncommon = 2, Rare = 1, Epic = 1, Legendary = 1, Mythic = 2, Secret = 1 },
				{ Rare = 2, Epic = 2, Legendary = 1, Mythic = 1, Secret = 2 },
				{ Rare = 1, Epic = 1, Legendary = 2, Mythic = 2, Secret = 1, Eternal = 1 },
				{ Epic = 2, Legendary = 2, Mythic = 1, Secret = 1, Eternal = 2 },
			}
			for index, zone in Zones.List do
				expect.equal(#zone.eggs, 8, zone.name .. " eggs")
				local counts = {}
				local lastOrder = 0
				for _, entry in zone.eggs do
					counts[entry.rarity] = (counts[entry.rarity] or 0) + 1
					local order = Rarities.Info[entry.rarity].order
					expect.truthy(order >= lastOrder, zone.name .. " lists its eggs from most common to rarest")
					lastOrder = order
				end
				for _, rarity in Rarities.Order do
					expect.equal(counts[rarity] or 0, mixes[index][rarity] or 0, `{zone.name} {rarity} eggs`)
				end
			end
		end)

		it("only drops the rarities a zone has eggs for", function()
			for _, zone in Zones.List do
				for _, rarity in Rarities.Order do
					local hasEgg = false
					for _, entry in zone.eggs do
						hasEgg = hasEgg or entry.rarity == rarity
					end
					expect.equal(zone.stamina[rarity] ~= nil, hasEgg, `{zone.name} {rarity}`)
				end
			end
		end)

		it("never puts the same egg in two places", function()
			local seen = {}
			for _, zone in Zones.List do
				for _, entry in zone.eggs do
					expect.falsy(seen[entry.egg], entry.egg .. " is listed twice")
					seen[entry.egg] = true
				end
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
				local lowest = math.huge
				for _, requirement in zone.stamina do
					lowest = math.min(lowest, requirement)
				end
				expect.truthy(lowest > previousTop, zone.name .. " starts above the previous zone")
				previousTop = last
			end
		end)

		it("uses the zone baselines from the request", function()
			expect.equal(Zones.List[1].stamina.Common, 50)
			expect.equal(Zones.List[2].stamina.Common, 500)
			-- Snow starts at Uncommon now; its old Common baseline (2,000) is gone with its Commons.
			expect.equal(Zones.List[3].stamina.Uncommon, 2500)
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
			expect.falsy(EggSpec.get(1, "Secret"))
			expect.falsy(EggSpec.get(3, "Common"))
			expect.falsy(EggSpec.get(4, "Eternal"))
			expect.falsy(EggSpec.get(9, "Common"))
		end)

		it("only rolls rarities the zone allows", function()
			for _, zone in Zones.List do
				for step = 0, 999 do
					local rarity = EggSpec.rollRarity(zone.id, step / 1000)
					expect.truthy(zone.stamina[rarity], zone.name .. " rolled " .. rarity)
				end
				expect.equal(EggSpec.rollRarity(zone.id, 0), zone.eggs[1].rarity, zone.name .. " most common")
			end
			expect.equal(EggSpec.rollRarity(1, 0.99999), "Mythic")
			expect.equal(EggSpec.rollRarity(4, 0), "Rare")
			expect.equal(EggSpec.rollRarity(5, 0.99999), "Eternal")
			expect.equal(EggSpec.rollRarity(6, 0), "Epic")
			expect.equal(EggSpec.rollRarity(6, 0.99999), "Eternal")
		end)

		it("picks evenly between a zone's eggs of the same rarity", function()
			expect.equal(table.concat(EggSpec.eggsOf(1, "Common"), ","), "Leafy,Cottontail")
			expect.equal(EggSpec.pickEgg(1, "Common", 0), "Leafy")
			expect.equal(EggSpec.pickEgg(1, "Common", 0.49), "Leafy")
			expect.equal(EggSpec.pickEgg(1, "Common", 0.5), "Cottontail")
			expect.equal(EggSpec.pickEgg(1, "Common", 0.9999), "Cottontail")
			expect.equal(EggSpec.pickEgg(4, "Secret", 0.7), "Abyss")
			expect.equal(EggSpec.pickEgg(1, "Epic", 0.9), "Bear")
			expect.equal(EggSpec.pickEgg(6, "Eternal", 0.2), "Mosasaurus")
			expect.equal(EggSpec.pickEgg(6, "Eternal", 0.8), "LunarDragon")
			expect.falsy(EggSpec.pickEgg(3, "Common", 0))
			local zone, rarity = EggSpec.placeOf("Yeti")
			expect.equal(zone, 3)
			expect.equal(rarity, "Secret")
			expect.falsy(EggSpec.placeOf("MagmaDragon"), "shelved")
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

	describe("AdminTools", function()
		local AdminTools = harness.load("src/shared/Config/AdminTools")

		it("offers its default speeds, and sensible limits", function()
			expect.truthy(table.find(AdminTools.FLY_SPEEDS, AdminTools.DEFAULT_FLY_SPEED), "default fly speed offered")
			expect.truthy(
				table.find(AdminTools.WALK_SPEEDS, AdminTools.DEFAULT_WALK_SPEED),
				"default walk speed offered"
			)
			expect.equal(AdminTools.DEFAULT_WALK_SPEED, 16, "Roblox's own walk speed")
			expect.truthy(AdminTools.MAX_GIVE <= AdminTools.MAX_INVENTORY)
			expect.truthy(AdminTools.MAX_STAMINA >= 500000, "enough for the hungriest egg")
		end)
	end)
end
