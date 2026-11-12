--!nocheck
-- Tests for the runway rules: eggs, riding, stamina, claiming, bounces and cracking, closures.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local RunwaySim = harness.load("src/server/Logic/RunwaySim")
	local Runway = harness.load("src/shared/Runway")
	local Tuning = harness.load("src/shared/Config/Tuning")

	local ALICE, BOB = 101, 202

	-- A sim whose random numbers are always 0.5: eggs land on the centre line and drops are predictable.
	local function newSim()
		return RunwaySim.new(function()
			return 0.5
		end)
	end

	local function eventsOfType(events, eventType)
		local found = {}
		for _, event in events do
			if event.type == eventType then
				table.insert(found, event)
			end
		end
		return found
	end

	local function firstOfType(events, eventType)
		return eventsOfType(events, eventType)[1]
	end

	describe("RunwaySim: dropping eggs", function()
		it("drops eggs in every zone while the runway is open", function()
			local sim = newSim()
			for second = 0, 30 do
				sim:step(second)
			end
			local spawned = eventsOfType(sim:takeEvents(), "EggSpawned")
			local zonesSeen = {}
			for _, event in spawned do
				zonesSeen[event.egg.zone] = true
			end
			for zoneId = 1, Runway.ZONE_COUNT do
				expect.truthy(zonesSeen[zoneId], "zone " .. zoneId)
			end
		end)

		it("keeps roughly the target number of eggs alive per zone", function()
			local sim = newSim()
			for tick = 0, 590 do
				sim:step(tick / 10)
			end
			-- Forest eggs never reach the end in 59 s, and none have faded yet.
			local forest = 0
			for _, egg in sim.eggs do
				if egg.zone == 1 then
					forest += 1
				end
			end
			expect.truthy(forest >= Tuning.EGGS_PER_ZONE - 2 and forest <= Tuning.EGGS_PER_ZONE + 2, "got " .. forest)
		end)

		it("places a new egg just past the start of its zone", function()
			local sim = newSim()
			local egg = sim:spawnEgg(3, 50, "Uncommon")
			local x, y, z = sim:eggCenter(egg, 50)
			expect.equal(x, 0)
			expect.equal(z, Runway.zoneStartZ(3) + Tuning.EGG_SPAWN_OFFSET)
			expect.near(y, Runway.surfaceY(z) + egg.spec.radius)
			expect.falsy(sim:spawnEgg(1, 50, "Eternal"), "Eternal cannot drop in the Forest")
			expect.falsy(sim:spawnEgg(3, 50, "Common"), "Snow has no Common eggs")
		end)

		it("drops one of the zone's eggs of the rolled rarity", function()
			local sim = newSim()
			-- Random numbers are 0.5, which picks the second of two eggs.
			local egg = sim:spawnEgg(1, 0, "Common")
			expect.equal(egg.kind, "Cottontail")
			local spawned = firstOfType(sim:takeEvents(), "EggSpawned")
			expect.equal(spawned.egg.kind, "Cottontail")
			expect.equal(sim:spawnEgg(4, 0, "Secret").kind, "Abyss")

			-- A particular egg can be dropped by name, in its own zone only.
			local yeti = sim:spawnEgg(3, 0, nil, "Yeti")
			expect.equal(yeti.rarity, "Secret")
			expect.equal(yeti.spec.requirement, 7500)
			expect.falsy(sim:spawnEgg(1, 0, nil, "Yeti"), "Yeti is a Snow egg")
			expect.falsy(sim:spawnEgg(5, 0, nil, "MagmaDragon"), "shelved")
			expect.falsy(sim:spawnEgg(1, 0, nil, "NoSuchEgg"))
		end)
	end)

	describe("RunwaySim: riding and claiming", function()
		it("claims an egg when the rider has enough stamina", function()
			local sim = newSim()
			sim:addRider(ALICE, 100, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Common") -- needs 50 stamina, 5 s to claim
			sim:takeEvents()

			local ok = sim:requestMount(ALICE, egg.id, 1, true)
			expect.truthy(ok)
			local started = sim:takeEvents()
			expect.equal(firstOfType(started, "EggMounted").rider, ALICE)
			local ride = firstOfType(started, "RideStarted")
			expect.equal(ride.id, egg.id)
			expect.equal(ride.claimTime, 5)
			expect.near(ride.drain, 8)
			expect.equal(ride.startStamina, 100)

			sim:step(5.9)
			expect.equal(#eventsOfType(sim:takeEvents(), "Claimed"), 0, "not claimed early")
			expect.near(sim:getStamina(ALICE, 5.9), 100 - 8 * 4.9)

			sim:step(6)
			local finished = sim:takeEvents()
			local claimed = firstOfType(finished, "Claimed")
			expect.equal(claimed.rider, ALICE)
			expect.equal(claimed.zone, 1)
			expect.equal(claimed.rarity, "Common")
			expect.equal(claimed.kind, egg.kind)
			expect.equal(firstOfType(finished, "RideEnded").kind, egg.kind)
			expect.equal(firstOfType(finished, "RideEnded").reason, "Claimed")
			local removed = firstOfType(finished, "EggRemoved")
			expect.equal(removed.reason, "Claimed")
			expect.equal(removed.by, ALICE)
			expect.falsy(sim:getEgg(egg.id))

			-- 80% of the 50 requirement was spent, and stamina now regenerates.
			expect.near(sim:getStamina(ALICE, 6), 60)
			expect.truthy(sim:getStamina(ALICE, 7) > 60)
		end)

		it("throws off a rider whose stamina is below the requirement, before the claim", function()
			local sim = newSim()
			sim:addRider(ALICE, 100, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Epic") -- needs 200 stamina, 12 s to claim
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:takeEvents()

			-- Drain is 200 * 0.8 / 12 = 13.33/s, so 100 stamina lasts 7.5 s.
			sim:step(8.4)
			expect.equal(#eventsOfType(sim:takeEvents(), "RideEnded"), 0)
			sim:step(8.6)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "RideEnded").reason, "ThrownOff")
			expect.equal(#eventsOfType(events, "Claimed"), 0)
			-- The egg hops and loses one of its two bounces.
			local left = firstOfType(events, "EggLeft")
			expect.equal(left.bouncesLeft, 1)
			expect.truthy(sim:getEgg(egg.id))

			-- Stunned for 1.5 s.
			local ok, reason = sim:requestMount(ALICE, egg.id, 9, true)
			expect.falsy(ok)
			expect.equal(reason, "Stunned")
			expect.truthy(sim:requestMount(ALICE, egg.id, 10.2, true))
		end)

		it("lets a player who exactly meets the requirement claim with a 20% buffer", function()
			local sim = newSim()
			sim:addRider(ALICE, 350, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Legendary") -- needs 350
			sim:requestMount(ALICE, egg.id, 0, true)
			sim:step(15)
			expect.truthy(firstOfType(sim:takeEvents(), "Claimed"))
			expect.near(sim:getStamina(ALICE, 15), 70)
		end)

		it("rejects mounts that are too far, too frequent, or onto a taken egg", function()
			local sim = newSim()
			sim:addRider(ALICE, 100, 14, 0)
			sim:addRider(BOB, 100, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Common")

			local ok, reason = sim:requestMount(ALICE, egg.id, 1, false)
			expect.falsy(ok)
			expect.equal(reason, "TooFar")

			ok, reason = sim:requestMount(ALICE, egg.id, 1.05, true)
			expect.falsy(ok)
			expect.equal(reason, "TooSoon")

			expect.truthy(sim:requestMount(ALICE, egg.id, 1.5, true))

			ok, reason = sim:requestMount(BOB, egg.id, 2, true)
			expect.falsy(ok)
			expect.equal(reason, "Occupied")

			ok, reason = sim:requestMount(BOB, 9999, 3, true)
			expect.falsy(ok)
			expect.equal(reason, "NoEgg")

			ok, reason = sim:requestMount(ALICE, egg.id, 3, true)
			expect.falsy(ok)
			expect.equal(reason, "AlreadyRiding")
		end)
	end)

	describe("RunwaySim: bounces and cracking", function()
		it("cracks a one-bounce egg after its hop when the rider jumps off", function()
			local sim = newSim()
			sim:addRider(ALICE, 100, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Common")
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:takeEvents()

			sim:requestDismount(ALICE, 2)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "RideEnded").reason, "Dismount")
			expect.equal(firstOfType(events, "EggLeft").bouncesLeft, 0)

			-- Still hopping: on the runway but nobody can jump on.
			sim:step(2.3)
			expect.truthy(sim:getEgg(egg.id))
			sim:addRider(BOB, 100, 14, 0)
			local ok, reason = sim:requestMount(BOB, egg.id, 2.3, true)
			expect.falsy(ok)
			expect.equal(reason, "NoEgg")

			sim:step(2 + Tuning.HOP_DURATION)
			expect.equal(firstOfType(sim:takeEvents(), "EggRemoved").reason, "Cracked")
			expect.falsy(sim:getEgg(egg.id))
		end)

		it("lets a two-bounce egg survive one jump-off and be ridden again from zero", function()
			local sim = newSim()
			sim:addRider(ALICE, 500, 14, 0)
			sim:addRider(BOB, 500, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Rare") -- 2 bounces, 9 s to claim
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:requestDismount(ALICE, 6)
			sim:step(8)
			expect.truthy(sim:getEgg(egg.id), "survived the first bounce")
			sim:takeEvents()

			expect.truthy(sim:requestMount(BOB, egg.id, 8, true))
			-- Bob's claim starts from zero: 9 s from when he got on.
			sim:step(16.9)
			expect.equal(#eventsOfType(sim:takeEvents(), "Claimed"), 0)
			sim:step(17)
			expect.equal(firstOfType(sim:takeEvents(), "Claimed").rider, BOB)
		end)

		it("cracks the egg when its rider dies or leaves the game", function()
			local sim = newSim()
			sim:addRider(ALICE, 100, 14, 0)
			sim:addRider(BOB, 100, 14, 0)
			local first = sim:spawnEgg(1, 0, "Common")
			local second = sim:spawnEgg(1, 0, "Common")
			sim:requestMount(ALICE, first.id, 1, true)
			sim:requestMount(BOB, second.id, 1, true)
			sim:takeEvents()

			sim:killRider(ALICE, 2)
			sim:removeRider(BOB, 2)
			local events = sim:takeEvents()
			local ended = eventsOfType(events, "RideEnded")
			expect.equal(#ended, 2)
			expect.equal(#eventsOfType(events, "EggLeft"), 2)
			expect.falsy(sim:getRider(BOB))
			expect.truthy(sim:getRider(ALICE))

			sim:step(3)
			expect.equal(#eventsOfType(sim:takeEvents(), "EggRemoved"), 2)
		end)

		it("refunds stamina for hopping straight onto another egg", function()
			local sim = newSim()
			sim:addRider(ALICE, 100, 14, 0)
			local first = sim:spawnEgg(1, 0, "Common")
			local second = sim:spawnEgg(1, 0, "Common")
			local third = sim:spawnEgg(1, 0, "Common")
			sim:requestMount(ALICE, first.id, 1, true)
			sim:requestDismount(ALICE, 3) -- 2 s at 8/s: 84 left
			sim:takeEvents()

			expect.truthy(sim:requestMount(ALICE, second.id, 3.5, true))
			local ride = firstOfType(sim:takeEvents(), "RideStarted")
			expect.equal(ride.combo, 1)
			-- 84 + 0.5 s of regen (12/s) + the 10 hop refund = 100, capped at the maximum.
			expect.near(ride.startStamina, 100)

			-- Too slow: no bonus, and the combo resets.
			sim:requestDismount(ALICE, 5.5)
			sim:takeEvents()
			expect.truthy(sim:requestMount(ALICE, third.id, 7, true))
			expect.equal(firstOfType(sim:takeEvents(), "RideStarted").combo, 0)
		end)

		it("gives no hop bonus after being thrown off", function()
			local sim = newSim()
			sim:addRider(ALICE, 30, 14, 0)
			local first = sim:spawnEgg(1, 0, "Common")
			local second = sim:spawnEgg(1, 0, "Common")
			sim:requestMount(ALICE, first.id, 1, true)
			sim:step(6) -- 30 stamina at 8/s runs out at 4.75 s
			expect.equal(firstOfType(sim:takeEvents(), "RideEnded").reason, "ThrownOff")
			expect.truthy(sim:requestMount(ALICE, second.id, 8, true))
			expect.equal(firstOfType(sim:takeEvents(), "RideStarted").combo, 0)
		end)
	end)

	describe("RunwaySim: the runway cycle", function()
		it("removes every egg without a rider when the runway closes, and keeps riders going", function()
			local sim = newSim()
			sim:addRider(ALICE, 500, 14, 0)
			local ridden = sim:spawnEgg(1, 0, "Rare")
			local loose = sim:spawnEgg(1, 0, "Common")
			local alsoLoose = sim:spawnEgg(2, 0, "Common")
			sim:requestMount(ALICE, ridden.id, 1, true)
			sim:takeEvents()

			sim:setPhase("Closed")
			local removed = eventsOfType(sim:takeEvents(), "EggRemoved")
			expect.equal(#removed, 2)
			for _, event in removed do
				expect.equal(event.reason, "Closure")
			end
			expect.falsy(sim:getEgg(loose.id))
			expect.falsy(sim:getEgg(alsoLoose.id))
			expect.truthy(sim:getEgg(ridden.id))

			-- The rider can still finish the claim while the runway is closed.
			sim:step(10)
			expect.equal(firstOfType(sim:takeEvents(), "Claimed").rider, ALICE)
		end)

		it("removes an egg that loses its rider during the closure", function()
			local sim = newSim()
			sim:addRider(ALICE, 500, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Legendary") -- 3 bounces
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:setPhase("Closed")
			sim:takeEvents()

			sim:requestDismount(ALICE, 2)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "EggRemoved").reason, "Closure")
			expect.equal(#eventsOfType(events, "EggLeft"), 0)
		end)

		it("drops nothing while closed and starts a fresh lineup when it reopens", function()
			local sim = newSim()
			sim:setPhase("Closed")
			for second = 0, 20 do
				sim:step(second)
			end
			expect.equal(#eventsOfType(sim:takeEvents(), "EggSpawned"), 0)

			sim:setPhase("Open")
			for second = 21, 30 do
				sim:step(second)
			end
			expect.truthy(#eventsOfType(sim:takeEvents(), "EggSpawned") >= Runway.ZONE_COUNT)
		end)

		it("fades eggs nobody jumped on after a minute", function()
			local sim = newSim()
			sim:setPhase("Closed") -- stops other eggs dropping; the phase does not affect fading
			sim.phase = "Open"
			sim.nextSpawnAt = { math.huge, math.huge, math.huge, math.huge, math.huge }
			local egg = sim:spawnEgg(1, 0, "Common")
			sim:takeEvents()
			sim:step(59)
			expect.truthy(sim:getEgg(egg.id))
			sim:step(60)
			expect.equal(firstOfType(sim:takeEvents(), "EggRemoved").reason, "Faded")
		end)

		it("does not fade an egg that has been ridden", function()
			local sim = newSim()
			sim.nextSpawnAt = { math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:addRider(ALICE, 500, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Rare")
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:requestDismount(ALICE, 2)
			sim:step(120)
			expect.truthy(sim:getEgg(egg.id))
		end)

		it("ends the ride and removes the egg when it rolls off the end of the runway", function()
			local sim = newSim()
			sim.nextSpawnAt = { math.huge, math.huge, math.huge, math.huge, math.huge }
			-- Plenty of stamina, but Alice gets on a Volcano egg far too late to finish the claim.
			sim:addRider(ALICE, 1e9, 14, 0)
			local egg = sim:spawnEgg(5, 0, "Eternal") -- 21 studs/s, 26 s to claim, 588 studs to the end
			sim:requestMount(ALICE, egg.id, 10, true)
			sim:takeEvents()

			sim:step(27.9)
			expect.equal(#eventsOfType(sim:takeEvents(), "RideEnded"), 0)
			sim:step(28.1)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "RideEnded").reason, "Cliff")
			expect.equal(firstOfType(events, "EggRemoved").reason, "Cliff")
			expect.equal(#eventsOfType(events, "Claimed"), 0)
		end)
	end)

	describe("RunwaySim: steering and stamina", function()
		it("caps steering at the rider's Agility and keeps the egg on the runway", function()
			local sim = newSim()
			sim:addRider(ALICE, 500, 10, 0)
			local egg = sim:spawnEgg(1, 0, "Common")
			sim:requestMount(ALICE, egg.id, 1, true)

			-- 0.1 s at 10 studs/s allows 1.5 (with slack) + 2 studs of movement.
			sim:setLateral(ALICE, 20, 1.1)
			expect.near(egg.lateral, 3.5)

			-- Given time, the egg can reach the edge but not pass it.
			sim:setLateral(ALICE, 999, 60)
			expect.near(egg.lateral, Runway.maxLateral(egg.spec.halfLength))

			-- Garbage is ignored.
			local before = egg.lateral
			expect.falsy(sim:setLateral(ALICE, 0 / 0, 61))
			expect.falsy(sim:setLateral(ALICE, math.huge, 61))
			expect.equal(egg.lateral, before)
		end)

		it("ignores steering from players who are not riding", function()
			local sim = newSim()
			sim:addRider(ALICE, 100, 14, 0)
			expect.falsy(sim:setLateral(ALICE, 5, 1))
			expect.falsy(sim:setLateral(BOB, 5, 1))
		end)

		it("keeps current stamina when Max Stamina changes", function()
			local sim = newSim()
			sim:addRider(ALICE, 100, 14, 0)
			sim:setMaxStamina(ALICE, 1000, 5)
			expect.equal(sim:getStamina(ALICE, 5), 100)
			-- Regenerates toward the new maximum at 12% of it per second.
			expect.near(sim:getStamina(ALICE, 6), 220)
			expect.equal(sim:getStamina(ALICE, 60), 1000)
		end)

		it("reports every stamina change so the HUD can follow it", function()
			local sim = newSim()
			sim:addRider(ALICE, 100, 14, 0)
			local joined = firstOfType(sim:takeEvents(), "StaminaChanged")
			expect.equal(joined.value, 100)
			expect.equal(joined.max, 100)

			local egg = sim:spawnEgg(1, 0, "Common")
			sim:requestMount(ALICE, egg.id, 1, true)
			local riding = firstOfType(sim:takeEvents(), "StaminaChanged")
			expect.near(riding.rate, -8)

			sim:requestDismount(ALICE, 2)
			local resting = firstOfType(sim:takeEvents(), "StaminaChanged")
			expect.near(resting.value, 92)
			expect.near(resting.rate, 12)
		end)
	end)
end
