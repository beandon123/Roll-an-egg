--!nocheck
-- Tests for the blocky egg models (Shared/EggModels): every egg in the zones' lineups (and every shelved one)
-- exists, is different from the others, holds together, and stays within a part budget. How the eggs look is checked by eye in the egg gallery
-- (lune run tools/egg-gallery).

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local EggModels = harness.load("src/shared/EggModels")
	local Rarities = harness.load("src/shared/Config/Rarities")
	local Zones = harness.load("src/shared/Config/Zones")

	local MATERIALS = { SmoothPlastic = true, Neon = true, Glass = true }
	-- Most eggs on the runway are Common or Uncommon, so those stay light. Rarer eggs are seldom on screen.
	local COMMON_BUDGET = 70
	local BUDGET = 230

	-- Every egg with a design: the 40 in the zones' lineups, then the shelved ones.
	local function each(body)
		for _, entry in EggModels.lineup() do
			body(EggModels.get(entry.kind), entry.rarity)
		end
		for _, kind in EggModels.shelved() do
			local model = EggModels.get(kind)
			body(model, model.rarity)
		end
	end

	-- Whether any box reaches outside the plain shell (ears, horns, fins and so on).
	local function sticksOut(model): boolean
		local reach = EggModels.RADIUS + 0.2
		local half = EggModels.LAYERS / 2 + 0.2
		for _, box in model.boxes do
			if
				math.abs(box.x) + box.sx / 2 > reach
				or math.abs(box.z) + box.sz / 2 > reach
				or math.abs(box.y) + box.sy / 2 > half
			then
				return true
			end
		end
		return false
	end

	describe("EggModels", function()
		it("has a model for every egg in every zone, 8 per zone", function()
			local lineup = EggModels.lineup()
			expect.equal(#lineup, 40)
			local perZone = {}
			for _, entry in lineup do
				local model = EggModels.get(entry.kind)
				expect.truthy(model, entry.kind)
				expect.equal(model.zone, entry.zone, entry.kind .. " zone")
				expect.equal(model.rarity, entry.rarity, entry.kind .. " rarity")
				expect.falsy(model.shelved, entry.kind .. " shelved")
				perZone[entry.zone] = (perZone[entry.zone] or 0) + 1
			end
			for zoneId in Zones.List do
				expect.equal(perZone[zoneId], 8, "zone " .. zoneId)
			end
			expect.equal(EggModels.get("NoSuchEgg"), nil)
			expect.equal(EggModels.describe("MossStag").name, "Moss Stag Egg")
			expect.equal(EggModels.describe("NoSuchEgg"), nil)
		end)

		it("keeps shelved eggs out of the zones, ready to come back", function()
			local shelved = EggModels.shelved()
			expect.equal(
				table.concat(shelved, ","),
				"Ash,Seafoam,MagmaToad,KingCrab,FrostDragon,MagmaDragon,EternalPhoenix"
			)
			for _, kind in shelved do
				local model = EggModels.get(kind)
				expect.truthy(model.shelved, kind)
				expect.equal(model.zone, 0, kind .. " zone")
			end
			expect.equal(EggModels.get("MagmaDragon").rarity, "Secret")
			expect.equal(EggModels.get("EternalPhoenix").rarity, "Eternal")
		end)

		it("gives every egg its own name and its own look", function()
			local names, looks = {}, {}
			each(function(model)
				expect.falsy(names[model.name], "duplicate name " .. model.name)
				names[model.name] = true
				local parts = {}
				for _, box in model.boxes do
					table.insert(
						parts,
						string.format(
							"%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%s",
							box.x,
							box.y,
							box.z,
							box.sx,
							box.sy,
							box.sz,
							box.color[1],
							box.color[2],
							box.color[3],
							box.material
						)
					)
				end
				table.sort(parts)
				local signature = table.concat(parts, ";")
				expect.falsy(looks[signature], model.name .. " looks the same as " .. tostring(looks[signature]))
				looks[signature] = model.name
				expect.truthy(model.hatches ~= nil and model.hatches ~= "", model.name .. " says what hatches")
			end)
		end)

		it("has no decorations floating loose", function()
			each(function(model)
				expect.equal(model.loose, 0, model.name .. " loose cells")
			end)
		end)

		it("stays within its part budget and close to the egg", function()
			each(function(model, rarity)
				local limit = if Rarities.Info[rarity].order <= 2 then COMMON_BUDGET else BUDGET
				expect.truthy(#model.boxes <= limit, `{model.name} has {#model.boxes} boxes (limit {limit})`)
				for _, box in model.boxes do
					expect.truthy(MATERIALS[box.material], model.name .. " material " .. box.material)
					expect.truthy(box.sx > 0 and box.sy > 0 and box.sz > 0, model.name .. " box size")
					expect.truthy(math.abs(box.x) <= 10 and math.abs(box.z) <= 10, model.name .. " sideways reach")
					expect.truthy(box.y >= -12 and box.y <= 17, model.name .. " length reach")
				end
			end)
		end)

		it("goes from plain Commons to eggs that look like their pet", function()
			each(function(model, rarity)
				local order = Rarities.Info[rarity].order
				if rarity == "Common" then
					expect.falsy(sticksOut(model), model.name .. " should be a plain egg")
				end
				if order >= 4 then
					expect.truthy(sticksOut(model), model.name .. " should have pet features (ears, horns, fins...)")
				end
			end)
		end)

		it("makes Legendary and rarer eggs glow, and Mythic and rarer sparkle", function()
			each(function(model, rarity)
				local order = Rarities.Info[rarity].order
				expect.equal(model.light ~= nil, order >= 5, model.name .. " light")
				if order >= 6 then
					expect.truthy(model.particles, model.name .. " particles")
				end
				if order <= 4 then
					expect.falsy(model.particles, model.name .. " particles")
				end
				-- Secret's rarity colour is nearly black; its glow must still show.
				for _, effect in { model.light, model.particles } do
					local c = effect.color
					expect.truthy(math.max(c[1], c[2], c[3]) > 120, model.name .. " glow is bright enough")
				end
			end)
		end)

		it("builds the same egg every time", function()
			local first = EggModels.get("Cerberus")
			expect.truthy(first == EggModels.get("Cerberus"), "cached")
			expect.equal(first.rarity, "Secret")
		end)
	end)
end
