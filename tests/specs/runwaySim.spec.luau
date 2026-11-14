--!nocheck
-- Tests for the runway rules: the egg lineup, riding, stamina, claiming, obstacles, bounces and cracking,
-- closures.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local RunwaySim = harness.load("src/server/Logic/RunwaySim")
	local EggSpec = harness.load("src/shared/EggSpec")
	local Obstacles = harness.load("src/shared/Obstacles")
	local Runway = harness.load("src/shared/Runway")
	local Tuning = harness.load("src/shared/Config/Tuning")

	local ALICE, BOB = 101, 202

	-- A runway with no obstacles, for tests about everything else.
	local CLEAR_RUNWAY = {
		planPath = function(lane, fromZ)
			return { lane = lane, fromZ = fromZ, moves = {} }
		end,
		lateralAt = function(path)
			return path.lane
		end,
		clearLane = function(_, x)
			return x
		end,
		get = function()
			return nil
		end,
		activeAround = function()
			return true
		end,
		hitAt = function()
			return nil
		end,
	}

	local function half()
		return 0.5
	end

	-- A sim whose random numbers are always 0.5, on a runway without obstacles: eggs land on the centre line and
	-- drops are predictable.
	local function newSim()
		return RunwaySim.new(half, CLEAR_RUNWAY)
	end

	-- The same, with the real obstacles.
	local function newSimWithObstacles()
		return RunwaySim.new(half)
	end

	-- Stops the sunrise lineup and mid-cycle drops, for tests that place their own eggs.
	local function quiet(sim)
		sim.lineup = {}
		sim.nextWildAt = { math.huge, math.huge, math.huge, math.huge, math.huge, math.huge }
		return sim
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

	describe("RunwaySim: the egg lineup", function()
		it("rolls a lineup for every zone at sunrise and sends it out a few seconds apart", function()
			local sim = newSim()
			sim.nextWildAt = { math.huge, math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:step(0)
			local events = sim:takeEvents()
			local rolled = firstOfType(events, "LineupRolled")
			expect.equal(#rolled.eggs, Tuning.EGGS_PER_ZONE * Runway.ZONE_COUNT)
			-- The first egg of every zone leaves straight away.
			expect.equal(#eventsOfType(events, "EggSpawned"), Runway.ZONE_COUNT)

			for second = 1, Tuning.LINEUP_LAUNCH_GAP * Tuning.EGGS_PER_ZONE do
				sim:step(second)
			end
			local perZone = {}
			for _, egg in sim.eggs do
				perZone[egg.zone] = (perZone[egg.zone] or 0) + 1
				expect.falsy(egg.wild)
			end
			for zoneId = 1, Runway.ZONE_COUNT do
				expect.equal(perZone[zoneId], Tuning.EGGS_PER_ZONE, "zone " .. zoneId)
			end
		end)

		it("fades a riderless egg a quarter of the way into the next zone and drops it from the chute again", function()
			local sim = newSim()
			sim.nextWildAt = { math.huge, math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:step(0)
			local first
			for _, egg in sim.eggs do
				if egg.zone == 1 then
					first = egg
				end
			end
			-- Random numbers of 0.5 roll Forest Common eggs: 12 studs/s from 12 studs in to 750 (600 + 150).
			expect.equal(first.rarity, "Common")
			expect.equal(first.fadeZ, 750)
			local lapTime = (750 - 12) / 12
			sim:takeEvents()

			sim:step(lapTime - 0.01)
			expect.truthy(sim:getEgg(first.id))
			sim:step(lapTime)
			local events = sim:takeEvents()
			local faded
			for _, event in eventsOfType(events, "EggRemoved") do
				if event.id == first.id then
					faded = event
				end
			end
			expect.truthy(faded, "faded")
			expect.equal(faded.reason, "Faded")
			local again
			for _, event in eventsOfType(events, "EggSpawned") do
				if event.egg.zone == 1 then
					again = event.egg
				end
			end
			expect.truthy(again, "back at the chute")
			expect.equal(again.kind, first.kind)
			expect.near(again.spawnTime, lapTime)
			local _, _, z = sim:eggCenter(sim:getEgg(again.id), lapTime)
			expect.equal(z, Runway.zoneStartZ(1) + Tuning.EGG_SPAWN_OFFSET)
		end)

		it("fades the last zone's eggs at the end cliff", function()
			expect.equal(Runway.fadeZ(6), Runway.LENGTH)
			expect.equal(Runway.fadeZ(5), Runway.zoneStartZ(6) + Runway.ZONE_LENGTH / 4)
		end)

		it("brings a claimed lineup egg back on its next lap", function()
			local sim = newSim()
			sim.nextWildAt = { math.huge, math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:addRider(ALICE, 1000, 14, 0)
			sim:step(0)
			local first
			for _, egg in sim.eggs do
				if egg.zone == 1 then
					first = egg
				end
			end
			sim:requestMount(ALICE, first.id, 1, true)
			sim:step(6)
			expect.equal(firstOfType(sim:takeEvents(), "Claimed").kind, first.kind)

			local lapTime = (750 - 12) / 12
			sim:step(lapTime - 0.01)
			local before = 0
			for _, egg in sim.eggs do
				if egg.zone == 1 then
					before += 1
				end
			end
			sim:step(lapTime)
			local after = 0
			for _, egg in sim.eggs do
				if egg.zone == 1 then
					after += 1
				end
			end
			expect.equal(before, Tuning.EGGS_PER_ZONE - 1)
			expect.equal(after, Tuning.EGGS_PER_ZONE, "the claimed egg's slot is back")
		end)

		it("drops mid-cycle eggs that roll once", function()
			local sim = newSim()
			sim.lineup = {}
			sim:step(0)
			-- With random numbers of 0.5, the first mid-cycle drop comes 30 s in.
			sim:step(Tuning.WILD_DROP_INTERVAL)
			local wild = {}
			for _, egg in sim.eggs do
				expect.truthy(egg.wild)
				wild[egg.zone] = egg
			end
			for zoneId = 1, Runway.ZONE_COUNT do
				expect.truthy(wild[zoneId], "zone " .. zoneId)
			end

			-- It fades at the end of its lap and does not come back.
			local forest = wild[1]
			local fadeAt = Tuning.WILD_DROP_INTERVAL + (forest.fadeZ - forest.startZ) / forest.spec.rollSpeed
			sim.nextWildAt = { math.huge, math.huge, math.huge, math.huge, math.huge, math.huge }
			sim:takeEvents()
			sim:step(fadeAt)
			expect.falsy(sim:getEgg(forest.id))
			for _, event in eventsOfType(sim:takeEvents(), "EggSpawned") do
				expect.truthy(event.egg.zone ~= 1, "no Forest egg replaces it")
			end
		end)

		it("makes Secret and Eternal eggs far rarer mid-cycle than at sunrise", function()
			local function shareOfRare(rareOdds)
				local rare, total = 0, 2000
				for index = 0, total - 1 do
					local rarity = EggSpec.rollRarity(6, (index + 0.5) / total, rareOdds, "Secret")
					if rarity == "Secret" or rarity == "Eternal" then
						rare += 1
					end
				end
				return rare / total
			end
			local sunrise = shareOfRare(nil)
			local midCycle = shareOfRare(Tuning.WILD_RARE_ODDS)
			expect.truthy(sunrise > 0, "Prehistoric lineups can hold Secret and Eternal eggs")
			expect.truthy(midCycle > 0, "they can still drop mid-cycle")
			expect.truthy(midCycle < sunrise / 5, `mid-cycle {midCycle} vs sunrise {sunrise}`)
		end)

		it("places a new egg just past the start of its zone", function()
			local sim = quiet(newSim())
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

		it("keeps a ridden egg going past its fade line, and fades it once nobody is on it", function()
			local sim = quiet(newSim())
			sim:addRider(ALICE, 1e6, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Mythic") -- 19 studs/s, 18 s to claim: at the line (750) after 38.8 s
			sim:step(30)
			sim:requestMount(ALICE, egg.id, 30, true)
			sim:step(40)
			expect.truthy(sim:getEgg(egg.id), "carried past the line by its rider")
			sim:takeEvents()
			sim:requestDismount(ALICE, 41)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "EggRemoved").reason, "Faded")
			expect.equal(#eventsOfType(events, "EggLeft"), 0)
		end)

		it("ends the ride and removes the egg when it rolls off the end of the runway", function()
			local sim = quiet(newSim())
			-- Plenty of stamina, but Alice gets on a Prehistoric egg far too late to finish the claim.
			sim:addRider(ALICE, 1e9, 14, 0)
			local egg = sim:spawnEgg(6, 0, "Eternal") -- 21 studs/s, 26 s to claim, 588 studs to the end
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

	describe("RunwaySim: obstacles", function()
		local function findObstacle(zoneId, tier, timed)
			for _, obstacle in Obstacles.all() do
				if obstacle.zone == zoneId and obstacle.tier == tier and (obstacle.timing ~= nil) == timed then
					return obstacle
				end
			end
			error(`no {tier} obstacle in zone {zoneId}`)
		end

		-- Alice rides an egg of the zone and steers it onto the obstacle. Returns the egg and when it gets there.
		local function rideInto(sim, obstacle, rarity, spawnTime)
			sim:addRider(ALICE, 1e7, 1000, 0)
			local egg = sim:spawnEgg(obstacle.zone, spawnTime or 0, rarity)
			local arrive = (spawnTime or 0) + (obstacle.z - egg.startZ) / egg.spec.rollSpeed
			sim:requestMount(ALICE, egg.id, arrive - 2, true)
			sim:setLateral(ALICE, obstacle.x, arrive - 1)
			sim:takeEvents()
			return egg, arrive
		end

		it("lays out zone-themed obstacles, clear of each zone's chute", function()
			local kindsPerZone = {}
			for id, obstacle in Obstacles.all() do
				expect.equal(obstacle.id, id)
				expect.equal(Runway.zoneAt(obstacle.z), obstacle.zone)
				local fromStart = obstacle.z - Runway.zoneStartZ(obstacle.zone)
				expect.truthy(fromStart >= Obstacles.Config.FIRST_ROW - Obstacles.Config.ROW_JITTER, `{obstacle.kind}`)
				expect.truthy(Obstacles.Config.Zones[obstacle.zone].weights[obstacle.kind], obstacle.kind)
				expect.truthy(math.abs(obstacle.x) + obstacle.hx <= Runway.WIDTH / 2 + 1e-6, "on the runway")
				kindsPerZone[obstacle.zone] = kindsPerZone[obstacle.zone] or {}
				kindsPerZone[obstacle.zone][obstacle.kind] = (kindsPerZone[obstacle.zone][obstacle.kind] or 0) + 1
			end
			for zoneId = 1, Runway.ZONE_COUNT do
				local kinds, count = 0, 0
				for _, number in kindsPerZone[zoneId] or {} do
					kinds += 1
					count += number
				end
				expect.truthy(kinds >= 3, `zone {zoneId} has {kinds} kinds of obstacle`)
				expect.truthy(count >= 8, `zone {zoneId} has {count} obstacles`)
			end
		end)

		it("leaves a gap in every row for the biggest egg", function()
			local biggest = EggSpec.get(6, "Eternal")
			for _, row in Obstacles.rowsBetween(-math.huge, math.huge) do
				local lane = Obstacles.clearLane(row, 0, biggest.halfLength)
				for _, obstacle in row.obstacles do
					expect.truthy(math.abs(lane - obstacle.x) >= obstacle.hx + biggest.halfLength, "clear")
				end
			end
		end)

		it("steers eggs without a rider round every obstacle, staying on the runway", function()
			for zoneId = 1, Runway.ZONE_COUNT do
				local sizes = {}
				for _, rarity in { "Common", "Uncommon", "Rare", "Epic", "Eternal", "Secret", "Mythic" } do
					local spec = EggSpec.get(zoneId, rarity)
					if spec then
						table.insert(sizes, spec)
					end
				end
				local smallest, biggest = sizes[1], sizes[#sizes]
				for _, spec in { smallest, biggest } do
					local startZ = Runway.zoneStartZ(zoneId) + Tuning.EGG_SPAWN_OFFSET
					local fadeZ = Runway.fadeZ(zoneId)
					for _, fromZ in { startZ, startZ + 230, startZ + 470 } do
						for lane = -60, 60, 4 do
							local path = Obstacles.planPath(lane, fromZ, fadeZ, spec.halfLength, spec.radius)
							local limit = Runway.maxLateral(spec.halfLength)
							local z = fromZ
							while z <= fadeZ do
								local x = Obstacles.lateralAt(path, z)
								expect.truthy(math.abs(x) <= limit + 1e-6, "stays on the runway")
								for _, row in Obstacles.rowsBetween(z - spec.radius, z + spec.radius) do
									for _, obstacle in row.obstacles do
										local touching = math.abs(x - obstacle.x) < obstacle.hx + spec.halfLength
											and math.abs(z - obstacle.z) < obstacle.hz + spec.radius
										-- An egg that starts beside an obstacle is left to roll on past it.
										if touching and obstacle.z - obstacle.hz > fromZ + spec.radius then
											error(
												`zone {zoneId} {spec.rarity} egg from lane {lane} at {fromZ} hits {obstacle.kind} {obstacle.id} at z {z}`
											)
										end
									end
								end
								z += 0.5
							end
						end
					end
				end
			end
		end)

		it("moves riderless eggs along their path, and lets a rider take over from where it has got to", function()
			local sim = quiet(newSimWithObstacles())
			sim:addRider(ALICE, 1e6, 14, 0)
			-- Find an egg that has to swerve.
			local egg
			for spawnTime = 0, 200 do
				local candidate = sim:spawnEgg(1, spawnTime, "Common")
				if #candidate.path.moves > 0 then
					egg = candidate
					break
				end
			end
			expect.truthy(egg, "some egg swerves")
			local move = egg.path.moves[1]
			local atMove = egg.spawnTime + (move.z1 - egg.startZ) / egg.spec.rollSpeed
			expect.near(sim:eggLateral(egg, egg.spawnTime), move.from)
			expect.near(sim:eggLateral(egg, atMove), move.to)
			expect.truthy(sim:requestMount(ALICE, egg.id, atMove, true))
			expect.near(egg.lateral, move.to)
		end)

		it("charges stamina for a Bump and knocks the egg clear", function()
			local sim = quiet(newSimWithObstacles())
			local obstacle = findObstacle(1, "Bump", false)
			local egg, arrive = rideInto(sim, obstacle, "Rare")
			local before = sim:getStamina(ALICE, arrive)

			expect.truthy(sim:reportHit(ALICE, obstacle.id, arrive))
			local hit = firstOfType(sim:takeEvents(), "ObstacleHit")
			expect.equal(hit.obstacle, obstacle.id)
			expect.equal(hit.tier, "Bump")
			expect.equal(hit.lateral, egg.lateral)
			expect.near(sim:getStamina(ALICE, arrive), before - egg.spec.requirement * Tuning.BUMP_STAMINA)
			expect.truthy(math.abs(egg.lateral - obstacle.x) >= obstacle.hx + egg.spec.halfLength, "clear of it")
			expect.equal(sim:getRider(ALICE).eggId, egg.id, "still riding")
			expect.falsy(sim:reportHit(ALICE, obstacle.id, arrive + 0.1), "each obstacle counts once")
		end)

		it("throws the rider off at a KnockOff obstacle", function()
			local sim = quiet(newSimWithObstacles())
			local obstacle = findObstacle(1, "KnockOff", false)
			local egg, arrive = rideInto(sim, obstacle, "Rare")
			expect.truthy(sim:reportHit(ALICE, obstacle.id, arrive))
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "RideEnded").reason, "KnockedOff")
			expect.equal(firstOfType(events, "EggLeft").bouncesLeft, 1)
			local ok, reason = sim:requestMount(ALICE, egg.id, arrive + 0.5, true)
			expect.falsy(ok)
			expect.equal(reason, "Stunned")
		end)

		it("kills the rider in lava", function()
			local sim = quiet(newSimWithObstacles())
			local obstacle = findObstacle(5, "Lethal", false)
			local _, arrive = rideInto(sim, obstacle, "Rare")
			expect.truthy(sim:reportHit(ALICE, obstacle.id, arrive))
			expect.equal(firstOfType(sim:takeEvents(), "RideEnded").reason, "Hazard")
		end)

		it("counts a hit on its own when the egg is well inside an obstacle", function()
			local sim = quiet(newSimWithObstacles())
			local obstacle = findObstacle(1, "KnockOff", false)
			local _, arrive = rideInto(sim, obstacle, "Rare")
			sim:step(arrive)
			expect.equal(firstOfType(sim:takeEvents(), "RideEnded").reason, "KnockedOff")
		end)

		it("ignores reports of hits that could not have happened", function()
			local sim = quiet(newSimWithObstacles())
			local obstacle = findObstacle(1, "KnockOff", false)
			local _, arrive = rideInto(sim, obstacle, "Rare")
			expect.falsy(sim:reportHit(ALICE, obstacle.id, arrive - 1.5), "not there yet")
			expect.falsy(sim:reportHit(ALICE, 99999, arrive), "no such obstacle")
			expect.falsy(sim:reportHit(BOB, obstacle.id, arrive), "not riding")

			-- A geyser only counts while it is going off.
			local geyser = findObstacle(2, "KnockOff", true)
			local function arrivalWhen(active)
				for tenth = 0, 600 do
					local spawnTime = 100 + tenth / 10
					local egg = EggSpec.get(2, "Common")
					local reach = spawnTime
						+ (geyser.z - (Runway.zoneStartZ(2) + Tuning.EGG_SPAWN_OFFSET)) / egg.rollSpeed
					if Obstacles.activeAround(geyser, reach, Tuning.HIT_REPORT_SLACK) == active then
						return spawnTime
					end
				end
				error("no such moment")
			end
			local idleSim = quiet(newSimWithObstacles())
			local _, idleArrive = rideInto(idleSim, geyser, "Common", arrivalWhen(false))
			expect.falsy(idleSim:reportHit(ALICE, geyser.id, idleArrive))
			local activeSim = quiet(newSimWithObstacles())
			local _, activeArrive = rideInto(activeSim, geyser, "Common", arrivalWhen(true))
			expect.truthy(activeSim:reportHit(ALICE, geyser.id, activeArrive))
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
