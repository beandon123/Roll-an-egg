--!nocheck
-- Tests for the blocky pet models (Shared/PetModels): the pets made so far exist, match the eggs they hatch from,
-- have the limbs their skeleton needs, hold together, and stand on the ground. How they look and move is
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
		{
			"PoisonDartFrog",
			"GiantLeafcutterAnt",
			"GiantCentipede",
			"HerculesBeetle",
			"TitanAnaconda",
			"MantisEmpress",
			"VineHydra",
			"JadeTempleGuardian",
		},
		{ "SeaTurtle", "Dolphin", "MantaRay", "GreatShark", "Narwhal", "Hippocampus", "Kraken", "Leviathan" },
		{
			"ObsidianGoat",
			"CinderBoar",
			"VolcanoTortoise",
			"FireSalamander",
			"Chimera",
			"LavaGolem",
			"Cerberus",
			"LavaDragon",
		},
		{
			"Velociraptor",
			"Pteranodon",
			"Triceratops",
			"Stegosaurus",
			"Brachiosaurus",
			"TRex",
			"Mosasaurus",
			"LunarDragon",
		},
	}
	local MATERIALS = { SmoothPlastic = true, Neon = true, Glass = true }
	local SHAPES = { Block = true, Wedge = true, Ball = true }
	-- Pets have no block budget: quality comes first. Secret and Eternal pets are the showpieces, built in fine
	-- detail, so each has at least this many blocks.
	local SHOWPIECE_MINIMUM = 150

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
					expect.equal(entry.pet, (string.gsub(hatches, "[^%w]", "")), entry.egg .. " pet")
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
					({
						Walk = true,
						Hop = true,
						Waddle = true,
						Stomp = true,
						Swim = true,
						Crawl = true,
						Slither = true,
					})[model.gait],
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

		it("stands on the ground, with its seat on its back", function()
			each(function(model)
				local lowest = math.huge
				for _, limb in model.limbs do
					for _, box in limb.boxes do
						expect.truthy(MATERIALS[box.material], model.name .. " material " .. box.material)
						expect.truthy(SHAPES[box.shape or "Block"], model.name .. " shape " .. tostring(box.shape))
						local low = PetModels.extent(box)
						lowest = math.min(lowest, low[2])
					end
				end
				expect.near(lowest, 0, 0.2, model.name .. " feet on the ground")
				-- The seat is on top of the pet, roughly over its middle.
				expect.truthy(model.seat[2] > model.size[2] * 0.3, model.name .. " seat height")
				expect.truthy(math.abs(model.seat[1]) < 1, model.name .. " seat is centred")
			end)
		end)

		it("builds Secret and Eternal pets in showpiece detail", function()
			local showpieces = 0
			each(function(model)
				if not isShowpiece(model) then
					return
				end
				showpieces += 1
				local count = blockCount(model)
				expect.truthy(count >= SHOWPIECE_MINIMUM, `{model.name} has only {count} blocks`)
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
				-- Legendary pets may give off particles too (the Moss Stag's fireflies); Mythic and rarer always do.
				if order >= 6 then
					expect.truthy(model.particles ~= nil, model.name .. " particles")
				elseif order < 5 then
					expect.equal(model.particles, nil, model.name .. " particles")
				end
			end)
		end)

		it("gives only Legendary and rarer pets an aura round their feet", function()
			each(function(model)
				if model.aura then
					expect.truthy(Rarities.Info[model.rarity].order >= 5, model.name .. " aura")
				end
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

		it("flies and hovers winged pets (birds and dragons) off the ground, wings spread and beating", function()
			each(function(model)
				if PetAnimations.MOVES[model.skeleton].Hover == nil then
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

		it("bends every jointed leg and arm at the knee or elbow as the pet gets about", function()
			for skeleton, limbs in PetModels.SKELETONS do
				local move = PetAnimations.moveFor(skeleton, "Walk")
				for _, limb in limbs do
					if string.find(limb, "Shin$") or string.find(limb, "Forearm$") then
						local low, high = math.huge, -math.huge
						for step = 0, 60 do
							local p = PetAnimations.pose(skeleton, move, step * 0.03)[limb]
							local bend = if p then p[1] else 0
							low, high = math.min(low, bend), math.max(high, bend)
						end
						expect.truthy(high - low > 0.15, `{skeleton} {move} bends its {limb}: {high - low}`)
					end
				end
			end
		end)

		it("moves each of a three-headed pet's heads on its own", function()
			for _, move in { "Idle", "Walk" } do
				local apart = 0
				for step = 0, 80 do
					local pose = PetAnimations.pose("ThreeHeaded", move, step * 0.1)
					local left, right = pose.LeftHead, pose.RightHead
					apart = math.max(apart, math.abs(left[2] + right[2]), math.abs(left[1] - right[1]))
				end
				-- Mirror images of each other would cancel out (or match) at every moment.
				expect.truthy(apart > 0.1, `the side heads move out of step when they {move}: {apart}`)
			end
		end)

		it("eases from one move into the next", function()
			local from = { Head = { 0.4, 0, 0, 0, 0, 0 }, Tail = { 0, 0.2, 0, 0, 0, 0 } }
			local to = { Head = { 0, 0, 0, 0, 1, 0 }, Jaw = { 0.6, 0, 0, 0, 0, 0 } }
			local start = PetAnimations.blend(from, to, 0)
			expect.near(start.Head[1], 0.4, 1e-9, "starts where it was")
			expect.near(start.Tail[2], 0.2, 1e-9, "a limb only the old move turned starts where it was")
			expect.near(start.Jaw[1], 0, 1e-9, "a limb only the new move turns starts at rest")
			local done = PetAnimations.blend(from, to, 1)
			expect.near(done.Head[5], 1, 1e-9, "ends on the new move")
			expect.near(done.Tail[2], 0, 1e-9, "the old move's limb comes to rest")
			local middle = PetAnimations.blend(from, to, 0.5)
			expect.near(middle.Head[1], 0.2, 1e-9, "halfway, half of each")
			-- Eased: slow to leave and slow to arrive.
			local early = PetAnimations.blend(from, to, 0.1)
			expect.truthy(early.Head[1] > 0.4 - 0.1 * 0.4, "eases out of the old move")
		end)
	end)

	describe("Mutations (Shared/PetVariants)", function()
		-- PetVariants works in Color3s, so it is loaded with Lune's own Roblox types rather than through the harness.
		local fs = require("@lune/fs")
		local luau = require("@lune/luau")
		local Color3 = require("@lune/roblox").Color3
		local PetVariants = luau.load(fs.readFile("src/shared/PetVariants.luau"), {
			debugName = "src/shared/PetVariants",
			environment = { Color3 = Color3 },
		})()

		local BROWN = Color3.fromRGB(150, 100, 60)
		local CREAM = Color3.fromRGB(240, 226, 200)
		local EYE = Color3.fromRGB(20, 16, 14)

		it("keeps dark details dark in every mutation", function()
			for _, mutation in { "Gold", "Diamond", "Rainbow", "Silver" } do
				local eye = PetVariants.tint(EYE, mutation, 0.9)
				expect.equal(eye, EYE, mutation)
			end
		end)

		it("makes Diamond pets bright icy white-blue glass, unlike see-through Crystal", function()
			for _, color in { BROWN, CREAM } do
				local ice, material, transparency = PetVariants.paint(color, "SmoothPlastic", 0, "Diamond", 0.5)
				expect.truthy(math.min(ice.R, ice.G, ice.B) > 0.55, "pale")
				expect.truthy(ice.B >= ice.R, "blue-white")
				expect.equal(material, "Glass")
				expect.equal(transparency, 0, "solid")
			end
			local _, glowing = PetVariants.paint(CREAM, "Neon", 0, "Diamond", 0.5)
			expect.equal(glowing, "Neon", "what glowed keeps glowing")
			local _, _, crystal = PetVariants.paint(BROWN, "SmoothPlastic", 0, "Crystal", 0.5)
			expect.truthy(crystal > 0, "Crystal stays the see-through one")
			expect.truthy(PetVariants.reflectance("Diamond") > PetVariants.reflectance("Gold"), "the shiniest")
		end)

		it("runs Rainbow pets through every colour from teal at the tail to green at the nose", function()
			local function hueAt(along: number): number
				local hue, saturation = PetVariants.tint(BROWN, "Rainbow", along):ToHSV()
				expect.truthy(saturation > 0.8, "bright, saturated colours")
				return hue
			end
			expect.near(hueAt(0), 0.5, 0.02, "teal tail")
			expect.near(hueAt(0.3), 0.75, 0.02, "purple body")
			expect.near(hueAt(1), 0.33, 0.02, "green head")
			local red = hueAt(0.6)
			expect.truthy(red > 0.95 or red < 0.05, "red towards the neck")
		end)

		it("keeps Gold gold and Silver silver for the pets that already have it", function()
			local gold = PetVariants.tint(BROWN, "Gold", 0.5)
			expect.truthy(gold.R > gold.G and gold.G > gold.B, "gold")
			local silver = PetVariants.tint(BROWN, "Silver", 0.5)
			expect.truthy(math.abs(silver.R - silver.B) < 0.15, "grey")
		end)
	end)
end
