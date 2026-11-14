--!nocheck
-- Checks the fuse machine's rules (Logic/Fuse) and the pet traits they use (Config/PetTraits): the size ladder,
-- how often each size grows when fused, and how often each size hatches. Uses the examples the game's owner gave.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local Fuse = harness.load("src/server/Logic/Fuse")
	local PetTraits = harness.load("src/shared/Config/PetTraits")

	local nextUid = 0
	local function pet(species, variant, size)
		nextUid += 1
		return { uid = "pet" .. nextUid, species = species, variant = variant or "Normal", size = size or "Normal" }
	end

	-- Three pets of one species, all the same size and variant.
	local function three(size, variant)
		return { pet("Bunny", variant, size), pet("Bunny", variant, size), pet("Bunny", variant, size) }
	end

	-- A random source that hands out the given numbers in turn.
	local function sequence(...)
		local values = { ... }
		local index = 0
		return function()
			index += 1
			return values[index]
		end
	end

	-- A fixed-seed generator, so statistical tests always see the same numbers.
	local function seeded(seed)
		local state = seed
		return function()
			state = (state * 16807) % 2147483647
			return (state - 1) / 2147483646
		end
	end

	describe("Pet traits", function()
		it("orders sizes from Tiny to Titanic, one step at a time", function()
			local expected = { "Tiny", "Small", "Normal", "Big", "Huge", "Giant", "Colossal", "Titanic" }
			expect.equal(#PetTraits.Sizes, #expected)
			for index, size in expected do
				expect.equal(PetTraits.Sizes[index], size)
				expect.equal(PetTraits.sizeIndex(size), index)
			end
			expect.equal(PetTraits.nextSize("Tiny"), "Small")
			expect.equal(PetTraits.nextSize("Normal"), "Big")
			expect.equal(PetTraits.nextSize("Colossal"), "Titanic")
			expect.equal(PetTraits.nextSize("Titanic"), "Titanic")
			expect.falsy(PetTraits.sizeIndex("Medium"))
			expect.truthy(PetTraits.isVariant("Gold"))
			expect.falsy(PetTraits.isVariant("Shiny"))
		end)

		it("grows sizes for sure up to Big, then 10% less often for each step after it", function()
			local expected = {
				Tiny = 1,
				Small = 1,
				Normal = 1,
				Big = 0.9,
				Huge = 0.8,
				Giant = 0.7,
				Colossal = 0.6,
				Titanic = 0,
			}
			for _, size in PetTraits.Sizes do
				expect.near(PetTraits.GROW_CHANCE[size], expected[size], 1e-9, size)
			end
		end)

		it("hatches bigger sizes less often", function()
			for kind, weights in PetTraits.HATCH_SIZE_WEIGHTS do
				local previous = math.huge
				for _, size in PetTraits.Sizes do
					local weight = weights[size]
					if weight then
						expect.truthy(weight > 0 and weight < previous, `{kind}: {size} is rarer than the size below`)
						previous = weight
					end
				end
				local total = 0
				for _, chance in PetTraits.hatchSizeOdds(kind) do
					total += chance
				end
				expect.near(total, 1, 1e-9, kind .. " odds add up")
			end
		end)

		it("hatches Titanic pets only from Titan Eggs", function()
			expect.falsy(PetTraits.HATCH_SIZE_WEIGHTS.Egg.Titanic, "runway eggs")
			expect.truthy(PetTraits.hatchSizeOdds("TitanEgg").Titanic > 0, "Titan Eggs")
			for step = 0, 9999 do
				expect.truthy(PetTraits.rollHatchSize("Egg", step / 10000) ~= "Titanic", "rolled from a runway egg")
			end
			expect.equal(PetTraits.rollHatchSize("TitanEgg", 0.99999), "Titanic")
			expect.equal(PetTraits.rollHatchSize("Egg", 0), "Tiny")
			expect.equal(PetTraits.rollHatchSize("Egg", 0.99999), "Colossal")
		end)

		it("rolls hatch sizes at their odds", function()
			local random = seeded(777)
			local counts, rolls = {}, 40000
			for _ = 1, rolls do
				local size = PetTraits.rollHatchSize("Egg", random())
				counts[size] = (counts[size] or 0) + 1
			end
			for size, chance in PetTraits.hatchSizeOdds("Egg") do
				expect.near((counts[size] or 0) / rolls, chance, 0.01, size)
			end
		end)
	end)

	describe("Fuse machine", function()
		it("fuses exactly three pets of the same species, whatever their variants and sizes", function()
			expect.truthy(Fuse.check({
				pet("Woolly Mammoth", "Gold", "Tiny"),
				pet("Woolly Mammoth", "Normal", "Normal"),
				pet("Woolly Mammoth", "Rainbow", "Titanic"),
			}))

			local ok, reason = Fuse.check({ pet("Woolly Mammoth"), pet("Woolly Mammoth"), pet("Dolphin") })
			expect.equal(ok, false)
			expect.equal(reason, "MixedSpecies")

			expect.equal(select(2, Fuse.check({ pet("Dolphin"), pet("Dolphin") })), "WrongCount")
			expect.equal(
				select(2, Fuse.check({ pet("Dolphin"), pet("Dolphin"), pet("Dolphin"), pet("Dolphin") })),
				"WrongCount"
			)

			local same = pet("Dolphin")
			expect.equal(select(2, Fuse.check({ same, same, pet("Dolphin") })), "SamePetTwice")
			expect.equal(
				select(2, Fuse.check({ pet("Dolphin", "Shiny"), pet("Dolphin"), pet("Dolphin") })),
				"BadTraits"
			)
			expect.equal(
				select(2, Fuse.check({ pet("Dolphin", "Normal", "Medium"), pet("Dolphin"), pet("Dolphin") })),
				"BadTraits"
			)
		end)

		it("passes on each pet's variant with a 1 in 3 chance", function()
			local oneGold = Fuse.odds({ pet("Bunny", "Gold"), pet("Bunny"), pet("Bunny") })
			expect.near(oneGold.Gold, 1 / 3)
			expect.near(oneGold.Normal, 2 / 3)

			local allGold = Fuse.odds(three("Normal", "Gold"))
			expect.near(allGold.Gold, 1)
			expect.falsy(allGold.Normal)
		end)

		it("always grows three pets up to Big", function()
			for _, case in { { "Tiny", "Small" }, { "Small", "Normal" }, { "Normal", "Big" } } do
				local _, sizes = Fuse.odds(three(case[1]))
				expect.near(sizes[case[2]], 1, 1e-9, case[1])
			end
		end)

		it("grows bigger pets less often: 90% Huge, 80% Giant, 70% Colossal, 60% Titanic", function()
			local steps = {
				{ "Big", "Huge", 0.9 },
				{ "Huge", "Giant", 0.8 },
				{ "Giant", "Colossal", 0.7 },
				{ "Colossal", "Titanic", 0.6 },
			}
			for _, step in steps do
				local _, sizes = Fuse.odds(three(step[1]))
				expect.near(sizes[step[2]], step[3], 1e-9, step[1] .. " grows")
				expect.near(sizes[step[1]], 1 - step[3], 1e-9, step[1] .. " stays")
			end
			local _, titanic = Fuse.odds(three("Titanic"))
			expect.near(titanic.Titanic, 1, 1e-9, "Titanic stays Titanic")
		end)

		it("lets each pet put in set the size a third of the time", function()
			-- One Tiny and two Normal: Tiny grows to Small, Normal to Big.
			local _, mixed = Fuse.odds({ pet("Bunny", "Normal", "Tiny"), pet("Bunny"), pet("Bunny") })
			expect.near(mixed.Small, 1 / 3)
			expect.near(mixed.Big, 2 / 3)
			-- One Big and two Normal: Big grows 90% of the time.
			local _, bigger = Fuse.odds({ pet("Bunny", "Normal", "Big"), pet("Bunny"), pet("Bunny") })
			expect.near(bigger.Huge, 0.3)
			expect.near(bigger.Big, 0.1 / 3 + 2 / 3)
		end)

		it("rolls the variant and the size separately", function()
			local pets = { pet("Fox", "Gold", "Tiny"), pet("Fox", "Normal", "Normal"), pet("Fox", "Rainbow", "Big") }
			-- The numbers pick the variant's pet, then the size's pet, then whether that size grows.
			local variant, size = Fuse.roll(pets, sequence(0, 0.99, 0.5))
			expect.equal(variant, "Gold")
			expect.equal(size, "Huge")
			variant, size = Fuse.roll(pets, sequence(0.5, 0, 0.99))
			expect.equal(variant, "Normal")
			expect.equal(size, "Small", "Tiny always grows")
			variant, size = Fuse.roll(pets, sequence(0.9999, 0.9999, 0.95))
			expect.equal(variant, "Rainbow")
			expect.equal(size, "Big", "Big did not grow")
		end)

		it("matches its odds over many fusions", function()
			local pets = { pet("Owl", "Gold", "Big"), pet("Owl", "Normal", "Big"), pet("Owl", "Normal", "Big") }
			local random = seeded(12345)
			local golden, huge, rolls = 0, 0, 30000
			for _ = 1, rolls do
				local variant, size = Fuse.roll(pets, random)
				if variant == "Gold" then
					golden += 1
				end
				if size == "Huge" then
					huge += 1
				end
			end
			expect.near(golden / rolls, 1 / 3, 0.02, "Gold")
			expect.near(huge / rolls, 0.9, 0.02, "Huge")
		end)
	end)
end
