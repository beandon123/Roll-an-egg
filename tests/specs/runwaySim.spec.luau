--!nocheck
-- Tests for the runway rules: eggs, riding, stamina, claiming, cracking, the side walls, the endless runway,
-- closures.

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

		it("places a new egg on the ground at the start of its zone", function()
			local sim = newSim()
			local egg = sim:spawnEgg(3, 50, "Common")
			local x, y, z = sim:eggCenter(egg, 50)
			expect.equal(x, 0)
			-- The back of the egg sits just past the zone's start line.
			expect.near(z - egg.spec.radius, Runway.zoneStartZ(3) + Tuning.EGG_SPAWN_GAP)
			expect.near(y, Runway.surfaceY(z) + egg.spec.radius)
			expect.falsy(sim:spawnEgg(1, 50, "Eternal"), "Eternal cannot drop in the Forest")
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
			expect.equal(claimed.id, egg.id)
			expect.equal(claimed.zone, 1)
			expect.equal(claimed.rarity, "Common")
			-- The rider stays on, and the egg stays on the runway.
			expect.equal(#eventsOfType(finished, "RideEnded"), 0)
			expect.equal(#eventsOfType(finished, "EggRemoved"), 0)
			expect.equal(sim:getEgg(egg.id).ownerId, ALICE)
			expect.equal(sim:getRider(ALICE).eggId, egg.id)

			-- 80% of the 50 requirement was spent, and stamina now regenerates even though she is still on.
			expect.near(sim:getStamina(ALICE, 6), 60)
			expect.truthy(sim:getStamina(ALICE, 7) > 60)
		end)

		it("throws off a rider whose stamina is below the requirement, before the claim", function()
			local sim = newSim()
			sim:addRider(ALICE, 100, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Epic") -- needs 200 stamina, 12 s to claim
			local spare = sim:spawnEgg(1, 0, "Common")
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:takeEvents()

			-- Drain is 200 * 0.8 / 12 = 13.33/s, so 100 stamina lasts 7.5 s.
			sim:step(8.4)
			expect.equal(#eventsOfType(sim:takeEvents(), "RideEnded"), 0)
			sim:step(8.6)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "RideEnded").reason, "ThrownOff")
			expect.equal(#eventsOfType(events, "Claimed"), 0)

			-- Stunned for 1.5 s.
			local ok, reason = sim:requestMount(ALICE, spare.id, 9, true)
			expect.falsy(ok)
			expect.equal(reason, "Stunned")
			expect.truthy(sim:requestMount(ALICE, spare.id, 10.2, true))
		end)

		it("bounces the egg slightly and cracks it when its rider runs out of stamina, then brings it back", function()
			local sim = newSim()
			sim.nextSpawnAt = { math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:addRider(ALICE, 100, 14, 0)
			sim:addRider(BOB, 100, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Epic")
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:takeEvents()

			sim:step(8.6) -- out of stamina at 8.5 s
			local left = firstOfType(sim:takeEvents(), "EggLeft")
			expect.equal(left.id, egg.id)
			expect.equal(left.bounceTime, 8.6, "bouncing")
			expect.equal(sim:snapshot()[1].bounceTime, 8.6)

			-- Mid-bounce: still there, but nobody can get on.
			local ok, reason = sim:requestMount(BOB, egg.id, 8.8, true)
			expect.falsy(ok)
			expect.equal(reason, "Cracking")

			sim:step(8.6 + Tuning.CRACK_BOUNCE_TIME)
			expect.equal(firstOfType(sim:takeEvents(), "EggRemoved").reason, "Cracked")
			expect.falsy(sim:getEgg(egg.id))

			-- The same egg comes back at the start of its zone a few seconds later.
			local crackedAt = 8.6 + Tuning.CRACK_BOUNCE_TIME
			sim:step(crackedAt + Tuning.EGG_RESPAWN_DELAY - 0.1)
			expect.equal(#eventsOfType(sim:takeEvents(), "EggSpawned"), 0)
			sim:step(crackedAt + Tuning.EGG_RESPAWN_DELAY)
			local spawned = firstOfType(sim:takeEvents(), "EggSpawned")
			expect.truthy(spawned, "respawned")
			expect.equal(spawned.egg.zone, 1)
			expect.equal(spawned.egg.rarity, "Epic")
			local _, _, z = sim:eggCenter(sim:getEgg(spawned.egg.id), crackedAt + Tuning.EGG_RESPAWN_DELAY)
			expect.near(z, egg.startZ)
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

	describe("RunwaySim: leaving an egg", function()
		it("leaves the egg rolling on the ground, free for anyone, when its rider jumps off", function()
			local sim = newSim()
			sim:addRider(ALICE, 500, 14, 0)
			sim:addRider(BOB, 500, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Rare") -- 9 s to claim
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:takeEvents()

			sim:requestDismount(ALICE, 6)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "RideEnded").reason, "Dismount")
			local left = firstOfType(events, "EggLeft")
			expect.equal(left.id, egg.id)
			expect.equal(left.bounceTime, nil, "no bounce")
			expect.equal(#eventsOfType(events, "EggRemoved"), 0, "no crack")

			-- Bob's claim starts from zero: 9 s from when he got on.
			sim:step(8)
			expect.truthy(sim:requestMount(BOB, egg.id, 8, true))
			sim:step(16.9)
			expect.equal(#eventsOfType(sim:takeEvents(), "Claimed"), 0)
			sim:step(17)
			expect.equal(firstOfType(sim:takeEvents(), "Claimed").rider, BOB)
		end)

		it("leaves the egg rolling when its rider dies or leaves the game", function()
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
			sim:step(3)
			local events = sim:takeEvents()
			expect.equal(#eventsOfType(events, "RideEnded"), 2)
			expect.equal(#eventsOfType(events, "EggLeft"), 2)
			expect.equal(#eventsOfType(events, "EggRemoved"), 0)
			expect.falsy(sim:getRider(BOB))
			expect.truthy(sim:getRider(ALICE))
			expect.truthy(sim:getEgg(first.id) and sim:getEgg(second.id))
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

	describe("RunwaySim: riding a claimed egg", function()
		-- Alice rides a Common egg (5 s claim) from t = 1 and claims it at t = 6.
		local function claimedEgg(maxStamina)
			local sim = newSim()
			sim.nextSpawnAt = { math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:addRider(ALICE, maxStamina or 100, 14, 0)
			sim:addRider(BOB, 100, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Common")
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:step(6)
			expect.truthy(firstOfType(sim:takeEvents(), "Claimed"), "claimed")
			return sim, egg
		end

		it("keeps the owner rolling with no drain and no throw-off until they get off", function()
			-- 50 stamina is just enough to claim a Common egg: 10 is left at the claim.
			local sim, egg = claimedEgg(50)
			expect.near(sim:getStamina(ALICE, 6), 10)
			sim:step(60)
			local events = sim:takeEvents()
			expect.equal(#eventsOfType(events, "RideEnded"), 0, "still riding a minute later")
			expect.equal(#eventsOfType(events, "Claimed"), 0, "claimed once")
			expect.equal(sim:getStamina(ALICE, 60), 50, "stamina refilled while riding")
			expect.truthy(sim:getEgg(egg.id))

			-- Steering still works, and nobody else can get on.
			expect.truthy(sim:setLateral(ALICE, 3, 60.5))
			local ok, reason = sim:requestMount(BOB, egg.id, 61, true)
			expect.falsy(ok)
			expect.equal(reason, "Occupied")
		end)

		it("makes the egg disappear as soon as the owner gets off", function()
			local sim, egg = claimedEgg()
			sim:requestDismount(ALICE, 20)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "RideEnded").reason, "Dismount")
			local removed = firstOfType(events, "EggRemoved")
			expect.equal(removed.reason, "Claimed")
			expect.equal(removed.by, ALICE)
			expect.equal(#eventsOfType(events, "EggLeft"), 0)
			expect.falsy(sim:getEgg(egg.id))

			-- It is in the inventory already, so it does not come back.
			sim:step(40)
			expect.equal(#eventsOfType(sim:takeEvents(), "EggSpawned"), 0)
		end)

		it("makes the egg disappear when the owner dies on it", function()
			local sim, egg = claimedEgg()
			sim:killRider(ALICE, 20)
			expect.equal(firstOfType(sim:takeEvents(), "EggRemoved").reason, "Claimed")
			expect.falsy(sim:getEgg(egg.id))
		end)

		it("shows the owner in the snapshot, so players who join later see the egg is taken", function()
			local sim, egg = claimedEgg()
			local entry = sim:snapshot()[1]
			expect.equal(entry.id, egg.id)
			expect.equal(entry.owner, ALICE)
			expect.equal(entry.rider, ALICE)
		end)
	end)

	describe("RunwaySim: walls and the endless runway", function()
		-- Alice gets on a Common Forest egg a second before it reaches `z` (well before she could claim it) and steers
		-- it hard against the side (+x) there. Returns the sim, the egg, and the time it got there.
		local function steerIntoSideAt(z)
			local sim = newSim()
			sim.nextSpawnAt = { math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:addRider(ALICE, 1e6, 200, 0)
			local egg = sim:spawnEgg(1, 0, "Common")
			local at = (z - egg.startZ) / egg.spec.rollSpeed
			expect.truthy(at > 1, "far enough down the runway to get on first")
			sim:requestMount(ALICE, egg.id, at - 1, true)
			sim:setLateral(ALICE, 999, at)
			sim:takeEvents()
			sim:step(at)
			return sim, egg, at
		end

		it("kills a rider who steers into a wall, and knocks the egg back toward the middle", function()
			local wall = Runway.wallsBetween(1, 20, 600)[1]
			local sim, egg = steerIntoSideAt((wall.startZ + wall.endZ) / 2)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "RideEnded").reason, "HitWall")
			-- The egg rolls on without them, away from the wall.
			local left = firstOfType(events, "EggLeft")
			expect.equal(left.id, egg.id)
			expect.near(left.lateral, Runway.maxLateral(egg.spec.halfLength) - Tuning.WALL_KNOCKBACK)
			expect.equal(left.bounceTime, nil)
			expect.truthy(sim:getEgg(egg.id))
			expect.equal(#eventsOfType(events, "EggRemoved"), 0)
		end)

		it("sends egg and rider off the side through a gap, and brings the egg back", function()
			local first = Runway.wallsBetween(1, 20, 600)[1]
			local second = Runway.wallsBetween(1, first.endZ, 600)[1]
			local sim, egg, at = steerIntoSideAt((first.endZ + second.startZ) / 2)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "RideEnded").reason, "FellOff")
			expect.equal(firstOfType(events, "EggRemoved").reason, "FellOff")
			expect.falsy(sim:getEgg(egg.id))

			sim:step(at + Tuning.EGG_RESPAWN_DELAY)
			local spawned = firstOfType(sim:takeEvents(), "EggSpawned")
			expect.truthy(spawned, "respawned")
			expect.equal(spawned.egg.rarity, "Common")
			expect.equal(spawned.egg.zone, 1)
		end)

		it("is safe anywhere short of the side", function()
			local wall = Runway.wallsBetween(1, 20, 600)[1]
			local sim = newSim()
			sim:addRider(ALICE, 1e6, 200, 0)
			local egg = sim:spawnEgg(1, 0, "Common")
			sim:requestMount(ALICE, egg.id, 1, true)
			local at = ((wall.startZ + wall.endZ) / 2 - egg.startZ) / egg.spec.rollSpeed
			sim:setLateral(ALICE, Runway.maxLateral(egg.spec.halfLength) - 0.5, at)
			sim:takeEvents()
			sim:step(at)
			expect.equal(#eventsOfType(sim:takeEvents(), "RideEnded"), 0)
		end)

		it("never ends: eggs roll on through the last zone forever, carried back each loop", function()
			local sim = newSim()
			sim.nextSpawnAt = { math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:addRider(ALICE, 1e9, 14, 0)
			local egg = sim:spawnEgg(5, 0, "Eternal")
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:takeEvents()
			for second = 2, 600, 2 do
				sim:step(second)
				local _, y, z = sim:eggCenter(egg, second)
				expect.truthy(z >= Runway.FINAL_ZONE_START and z < Runway.LOOP_END, "z " .. z)
				expect.near(y, Runway.surfaceY(z) + egg.spec.radius)
			end
			local events = sim:takeEvents()
			expect.equal(#eventsOfType(events, "RideEnded"), 0, "nobody went over an end")
			expect.equal(#eventsOfType(events, "EggRemoved"), 0)
			-- 10 minutes at 21 studs a second: far past where the runway used to end.
			expect.truthy(egg.startZ + egg.spec.rollSpeed * 600 > Runway.LENGTH * 4)
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

		it("fades an egg a minute after its rider left it", function()
			local sim = newSim()
			sim.nextSpawnAt = { math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:addRider(ALICE, 500, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Rare")
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:requestDismount(ALICE, 50)
			sim:step(100)
			expect.truthy(sim:getEgg(egg.id), "ridden until 50 s, so not faded at 100 s")
			sim:step(110)
			expect.falsy(sim:getEgg(egg.id))
		end)

		it("brings nothing back once the runway closes", function()
			local sim = newSim()
			sim.nextSpawnAt = { math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:addRider(ALICE, 100, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Epic")
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:step(9.5) -- out of stamina, bounced, cracked
			sim:setPhase("Closed")
			sim:setPhase("Open")
			sim.nextSpawnAt = { math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:takeEvents()
			sim:step(30)
			expect.equal(#eventsOfType(sim:takeEvents(), "EggSpawned"), 0)
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
