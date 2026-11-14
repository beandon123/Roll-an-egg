--!nocheck
-- Checks the fuse machine's rules (Logic/Fuse) and the pet trait ladder they use (Config/PetTraits), with the
-- examples the game's owner gave.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local Fuse = harness.load("src/server/Logic/Fuse")
	local PetTraits = harness.load("src/shared/Config/PetTraits")

	local nextUid = 0
	local function pet(species, variant, size)
		nextUid += 1
		return { uid = "pet" .. nextUid, species = species, variant = variant or "Normal", size = size or "Normal" }
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

	describe("Pet traits", function()
		it("orders sizes from Tiny to Colossal, one step at a time", function()
			expect.equal(PetTraits.Sizes[1], "Tiny")
			expect.equal(PetTraits.Sizes[#PetTraits.Sizes], "Colossal")
			expect.equal(PetTraits.nextSize("Tiny"), "Normal")
			expect.equal(PetTraits.nextSize("Normal"), "Big")
			expect.equal(PetTraits.nextSize("Colossal"), "Colossal")
			for index, size in PetTraits.Sizes do
				expect.equal(PetTraits.sizeIndex(size), index)
			end
			expect.falsy(PetTraits.sizeIndex("Medium"))
			expect.truthy(PetTraits.isVariant("Golden"))
			expect.falsy(PetTraits.isVariant("Shiny"))
		end)
	end)

	describe("Fuse machine", function()
		it("fuses exactly three pets of the same species, whatever their variants and sizes", function()
			expect.truthy(Fuse.check({
				pet("Woolly Mammoth", "Golden", "Tiny"),
				pet("Woolly Mammoth", "Normal", "Normal"),
				pet("Woolly Mammoth", "Rainbow", "Big"),
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
			local oneGolden = Fuse.odds({ pet("Bunny", "Golden"), pet("Bunny"), pet("Bunny") })
			expect.near(oneGolden.Golden, 1 / 3)
			expect.near(oneGolden.Normal, 2 / 3)

			local allGolden = Fuse.odds({ pet("Bunny", "Golden"), pet("Bunny", "Golden"), pet("Bunny", "Golden") })
			expect.near(allGolden.Golden, 1)
			expect.falsy(allGolden.Normal)
		end)

		it("comes out one size up from a pet picked at random", function()
			-- One Tiny and two Normal: Normal or the next size up, Big.
			local _, mixed = Fuse.odds({ pet("Bunny", "Normal", "Tiny"), pet("Bunny"), pet("Bunny") })
			expect.near(mixed.Normal, 1 / 3)
			expect.near(mixed.Big, 2 / 3)
			expect.falsy(mixed.Tiny, "never smaller than the smallest pet put in, plus one")

			local _, tiny = Fuse.odds({
				pet("Bunny", "Normal", "Tiny"),
				pet("Bunny", "Normal", "Tiny"),
				pet("Bunny", "Normal", "Tiny"),
			})
			expect.near(tiny.Normal, 1)
			local _, normal = Fuse.odds({ pet("Bunny"), pet("Bunny"), pet("Bunny") })
			expect.near(normal.Big, 1)
			local _, colossal = Fuse.odds({
				pet("Bunny", "Normal", "Colossal"),
				pet("Bunny", "Normal", "Colossal"),
				pet("Bunny", "Normal", "Colossal"),
			})
			expect.near(colossal.Colossal, 1)
		end)

		it("rolls the variant and the size separately", function()
			local pets = { pet("Fox", "Golden", "Tiny"), pet("Fox", "Normal", "Normal"), pet("Fox", "Rainbow", "Big") }
			-- First number picks the variant's pet, second the size's.
			local variant, size = Fuse.roll(pets, sequence(0, 0.99))
			expect.equal(variant, "Golden")
			expect.equal(size, "Huge")
			variant, size = Fuse.roll(pets, sequence(0.5, 0))
			expect.equal(variant, "Normal")
			expect.equal(size, "Normal")
			variant, size = Fuse.roll(pets, sequence(0.9999, 0.5))
			expect.equal(variant, "Rainbow")
			expect.equal(size, "Big")
		end)

		it("matches its odds over many fusions", function()
			local pets = { pet("Owl", "Golden", "Tiny"), pet("Owl"), pet("Owl") }
			-- A fixed-seed generator, so the test always sees the same numbers.
			local state = 12345
			local function random()
				state = (state * 16807) % 2147483647
				return (state - 1) / 2147483646
			end
			local golden, big, rolls = 0, 0, 30000
			for _ = 1, rolls do
				local variant, size = Fuse.roll(pets, random)
				if variant == "Golden" then
					golden += 1
				end
				if size == "Big" then
					big += 1
				end
			end
			expect.near(golden / rolls, 1 / 3, 0.02, "Golden")
			expect.near(big / rolls, 2 / 3, 0.02, "Big")
		end)
	end)
end
