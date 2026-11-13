--!nocheck
-- Tests for the blocky pet models (Shared/PetModels): the pets made so far exist, match the eggs they hatch from,
-- have the limbs their skeleton needs, hold together, and stay within a part budget. How they look and move is
-- checked by eye in the gallery (lune run tools/egg-gallery).

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local EggModels = harness.load("src/shared/EggModels")
	local PetModels = harness.load("src/shared/PetModels")
	local PetAnimations = harness.load("src/shared/PetAnimations")
	local Rarities = harness.load("src/shared/Config/Rarities")
	local Zones = harness.load("src/shared/Config/Zones")

	-- The pets made so far, zone by zone.
	local DONE = {
		{ "Squirrel", "Bunny", "Hedgehog", "Fox", "Owl", "Bear", "MossStag", "Treant" },
		{ "Meerkat", "Armadillo", "FennecFox", "Camel", "GiantScorpion", "PharaohJackal", "Sphinx", "GoldenScarab" },
		{ "SnowHare", "ArcticFox", "Reindeer", "FrostWolf", "SabertoothCat", "AuroraOwl", "WoollyMammoth", "Yeti" },
		{ "SeaTurtle", "Dolphin", "MantaRay", "GreatShark", "Narwhal", "Hippocampus", "Kraken", "Leviathan" },
		{
			"ObsidianGoat",
			"CinderBoar",
			"VolcanoTortoise",
			"FireSalamander",
			"Chimera",
			"LavaGolem",
			"Cerberus",
			"EternalPhoenix",
		},
	}
	local MATERIALS = { SmoothPlastic = true, Neon = true, Glass = true }
	local SHAPES = { Block = true, Wedge = true, Ball = true }
	local BUDGET = 120
	-- Secret and Eternal pets are the showpieces: far more detailed than the rest, so they get a bigger budget,
	-- and must have at least this many blocks and this much more than any other pet in the game.
	local SHOWPIECE_BUDGET = 700
	local SHOWPIECE_MINIMUM = 150
	local SHOWPIECE_LEAD = 1.3

	local function isShowpiece(model): boolean
		return model.rarity == "Secret" or model.rarity == "Eternal"
	end

	local function blockCount(model): number
		local count = 0
		for _, limb in model.limbs do
			count += #limb.boxes
		end
		return count
	end

	local function each(body)
		for _, kind in PetModels.all() do
			body(PetModels.get(kind), kind)
		end
	end

	describe("PetModels", function()
		it("has every pet in the game, in the order of their eggs", function()
			for zoneId, wanted in DONE do
				local made = {}
				for _, kind in PetModels.all() do
					if PetModels.get(kind).zone == zoneId then
						table.insert(made, kind)
					end
				end
				expect.equal(table.concat(made, ","), table.concat(wanted, ","), "zone " .. zoneId)
			end
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
					expect.truthy(model, entry.pet .. " has a model")
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
					({ Walk = true, Hop = true, Waddle = true, Stomp = true, Swim = true, Crawl = true })[model.gait],
					model.name .. " gait"
				)
			end)
		end)

		it("has no blocks floating loose", function()
			each(function(model)
				expect.equal(model.loose, 0, model.name .. " loose blocks")
			end)
		end)

		it("has no differently coloured blocks sharing a face, which would flicker", function()
			each(function(model)
				expect.equal(
					model.flicker,
					0,
					model.name .. " flickering faces: " .. table.concat(model.flickerAt, "; ")
				)
			end)
		end)

		it("stands on the ground, within its part budget", function()
			each(function(model)
				local count, lowest = 0, math.huge
				for _, limb in model.limbs do
					count += #limb.boxes
					for _, box in limb.boxes do
						expect.truthy(MATERIALS[box.material], model.name .. " material " .. box.material)
						expect.truthy(SHAPES[box.shape or "Block"], model.name .. " shape " .. tostring(box.shape))
						local low = PetModels.extent(box)
						lowest = math.min(lowest, low[2])
					end
				end
				local limit = if isShowpiece(model) then SHOWPIECE_BUDGET else BUDGET
				expect.truthy(count <= limit, `{model.name} has {count} blocks (limit {limit})`)
				expect.near(lowest, 0, 0.2, model.name .. " feet on the ground")
				-- The seat is on top of the pet, roughly over its middle.
				expect.truthy(model.seat[2] > model.size[2] * 0.3, model.name .. " seat height")
				expect.truthy(math.abs(model.seat[1]) < 1, model.name .. " seat is centred")
			end)
		end)

		it("makes Secret and Eternal pets far more detailed than every other pet", function()
			local showpieces = 0
			each(function(model)
				if not isShowpiece(model) then
					return
				end
				showpieces += 1
				local count = blockCount(model)
				expect.truthy(count >= SHOWPIECE_MINIMUM, `{model.name} has only {count} blocks`)
				each(function(other)
					if not isShowpiece(other) then
						local theirs = blockCount(other)
						expect.truthy(
							count >= theirs * SHOWPIECE_LEAD,
							`{model.name} ({count} blocks) should well outdo {other.name} ({theirs})`
						)
					end
				end)
			end)
			expect.truthy(showpieces >= 1, "at least one Secret or Eternal pet is made")
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

	describe("PetAnimations", function()
		it("gives every skeleton an idle and a way to get about, moving only limbs it has", function()
			for skeleton, limbs in PetModels.SKELETONS do
				local moves = PetAnimations.MOVES[skeleton]
				expect.truthy(moves, skeleton .. " has moves")
				expect.truthy(moves.Idle, skeleton .. " idles")
				expect.truthy(PetAnimations.moveFor(skeleton, "Walk") ~= "Idle", skeleton .. " gets about")
				for name, waves in moves do
					for _, w in waves do
						expect.truthy(table.find(limbs, w.limb), `{skeleton} {name} moves a {w.limb}`)
						expect.truthy(({ rx = 1, ry = 1, rz = 1, px = 1, py = 1, pz = 1 })[w.channel], w.channel)
					end
				end
			end
		end)

		it("has every pet's gait as a move, or a sensible stand-in", function()
			each(function(model)
				local move = PetAnimations.moveFor(model.skeleton, model.gait)
				expect.truthy(PetAnimations.MOVES[model.skeleton][move], model.name .. " " .. move)
				expect.truthy(move ~= "Idle", model.name .. " gets about")
			end)
		end)

		it("flies and hovers winged pets off the ground, wings spread and beating", function()
			each(function(model)
				if model.skeleton ~= "Winged" then
					return
				end
				expect.equal(PetAnimations.defaultMove(model.skeleton, model.gait), "Hover")
				for _, move in { "Fly", "Hover" } do
					local lowest, beat = math.huge, {}
					for step = 0, 40 do
						local pose =
							PetAnimations.pose(model.skeleton, move, step * 0.05, model.wingSpread, model.size[2])
						lowest = math.min(lowest, pose.Body[5])
						table.insert(beat, pose.LeftWing[3])
						-- The wings stay mirror images of each other.
						expect.near(pose.LeftWing[3], -pose.RightWing[3], 1e-9, model.name .. " wings mirrored")
					end
					expect.truthy(lowest > model.size[2] * 0.15, `{model.name} stays up while it {move}s: {lowest}`)
					expect.truthy(
						math.max(table.unpack(beat)) - math.min(table.unpack(beat)) > 0.8,
						model.name .. " beats its wings"
					)
				end
				-- Folded wings open out for flight.
				local resting = PetAnimations.pose(model.skeleton, "Idle", 0, model.wingSpread).LeftWing[3]
				local flying = PetAnimations.pose(model.skeleton, "Hover", 0, model.wingSpread).LeftWing[3]
				expect.truthy(flying - resting >= model.wingSpread, model.name .. " spreads its wings to fly")
			end)
		end)
	end)
end
