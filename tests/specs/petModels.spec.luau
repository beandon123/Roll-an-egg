--!nocheck
-- Tests for the blocky pet models (Shared/PetModels): the pets made so far exist, match the eggs they hatch from,
-- have the limbs their skeleton needs, hold together, and stay within a part budget. How they look and move is
-- checked by eye in the gallery (lune run tools/egg-gallery).

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local EggModels = harness.load("src/shared/EggModels")
	local PetModels = harness.load("src/shared/PetModels")
	local Rarities = harness.load("src/shared/Config/Rarities")
	local Zones = harness.load("src/shared/Config/Zones")

	local FOREST_PETS = { "Squirrel", "Bunny", "Hedgehog", "Fox", "Owl", "Bear", "MossStag", "Treant" }
	local MATERIALS = { SmoothPlastic = true, Neon = true, Glass = true }
	local BUDGET = 120

	local function each(body)
		for _, kind in PetModels.all() do
			body(PetModels.get(kind), kind)
		end
	end

	describe("PetModels", function()
		it("has every Forest pet, in the order of their eggs", function()
			local forest = {}
			for _, kind in PetModels.all() do
				if PetModels.get(kind).zone == 1 then
					table.insert(forest, kind)
				end
			end
			expect.equal(table.concat(forest, ","), table.concat(FOREST_PETS, ","))
			expect.equal(PetModels.get("NoSuchPet"), nil)
			expect.equal(PetModels.fromEgg("Toadstool"), "Owl")
			expect.equal(PetModels.fromEgg("NoSuchEgg"), nil)
		end)

		it("names every egg's pet after what its egg says hatches", function()
			for _, zone in Zones.List do
				for _, entry in zone.eggs do
					local hatches = EggModels.describe(entry.egg).hatches
					expect.equal(entry.pet, (string.gsub(hatches, " ", "")), entry.egg .. " pet")
					local model = PetModels.get(entry.pet)
					if model then
						expect.equal(model.name, hatches, entry.pet .. " name")
						expect.equal(model.rarity, entry.rarity, entry.pet .. " rarity")
						expect.equal(model.zone, zone.id, entry.pet .. " zone")
					end
				end
			end
		end)

		it("gives each pet exactly the limbs its skeleton needs, hanging from Body", function()
			each(function(model)
				local wanted = PetModels.SKELETONS[model.skeleton]
				expect.truthy(wanted, model.name .. " skeleton " .. tostring(model.skeleton))
				local names = {}
				for _, limb in model.limbs do
					names[limb.name] = limb
					expect.truthy(#limb.boxes > 0, model.name .. " " .. limb.name .. " has blocks")
				end
				for _, name in wanted do
					expect.truthy(names[name], model.name .. " has a " .. name)
				end
				expect.equal(#model.limbs, #wanted, model.name .. " limb count")
				expect.equal(names.Body.parent, nil, model.name .. " Body hangs from the root")
				for _, limb in model.limbs do
					if limb.name ~= "Body" then
						expect.truthy(names[limb.parent], model.name .. " " .. limb.name .. " parent")
					end
				end
				expect.truthy(
					({ Walk = true, Hop = true, Waddle = true, Stomp = true })[model.gait],
					model.name .. " gait"
				)
			end)
		end)

		it("has no blocks floating loose", function()
			each(function(model)
				expect.equal(model.loose, 0, model.name .. " loose blocks")
			end)
		end)

		it("stands on the ground, within its part budget", function()
			each(function(model)
				local count, lowest = 0, math.huge
				for _, limb in model.limbs do
					count += #limb.boxes
					for _, box in limb.boxes do
						expect.truthy(MATERIALS[box.material], model.name .. " material " .. box.material)
						lowest = math.min(lowest, box.y - box.sy / 2)
					end
				end
				expect.truthy(count <= BUDGET, `{model.name} has {count} blocks (limit {BUDGET})`)
				expect.near(lowest, 0, 0.2, model.name .. " feet on the ground")
				-- The seat is on top of the pet, roughly over its middle.
				expect.truthy(model.seat[2] > model.size[2] * 0.3, model.name .. " seat height")
				expect.truthy(math.abs(model.seat[1]) < 1, model.name .. " seat is centred")
			end)
		end)

		it("gives every pet its own look", function()
			local looks = {}
			each(function(model)
				local parts = {}
				for _, limb in model.limbs do
					for _, box in limb.boxes do
						table.insert(
							parts,
							string.format("%s %.2f %.2f %.2f %d", limb.name, box.x, box.y, box.z, box.color[1])
						)
					end
				end
				table.sort(parts)
				local signature = table.concat(parts, ";")
				expect.falsy(looks[signature], model.name .. " looks the same as " .. tostring(looks[signature]))
				looks[signature] = model.name
			end)
		end)

		it("makes Legendary and rarer pets glow, and Mythic and rarer sparkle", function()
			each(function(model)
				local order = Rarities.Info[model.rarity].order
				expect.equal(model.light ~= nil, order >= 5, model.name .. " light")
				expect.equal(model.particles ~= nil, order >= 6, model.name .. " particles")
			end)
		end)
	end)
end
