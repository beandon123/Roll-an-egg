--!nocheck
-- Tests for the runway rules: the egg lineup, riding, stamina, claiming, obstacles, cracking, the banks, the endless
-- last zone, closures.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local RunwaySim = harness.load("src/server/Logic/RunwaySim")
	local EggSpec = harness.load("src/shared/EggSpec")
	local Obstacles = harness.load("src/shared/Obstacles")
	local Runway = harness.load("src/shared/Runway")
	local Tuning = harness.load("src/shared/Config/Tuning")
	local Zones = harness.load("src/shared/Config/Zones")

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

	-- Stops mid-cycle drops in every zone.
	local function noMidCycle(sim)
		sim.nextWildAt = {}
		for zoneId = 1, Runway.ZONE_COUNT do
			sim.nextWildAt[zoneId] = math.huge
		end
	end

	-- The zones with eggs (a new zone can stand on the runway before its creatures are chosen).
	local function zonesWithEggs(): number
		local count = 0
		for zoneId = 1, Runway.ZONE_COUNT do
			if EggSpec.lineupSize(zoneId) > 0 then
				count += 1
			end
		end
		return count
	end

	-- Stops the sunrise lineup and mid-cycle drops, for tests that place their own eggs.
	local function quiet(sim)
		sim.lineup = {}
		noMidCycle(sim)
		return sim
	end

	-- Stops mid-cycle drops and the extra eggs that keep every zone's start stocked, for tests about the lineup's own
	-- laps.
	local function lapsOnly(sim)
		noMidCycle(sim)
		sim.startEggGap = math.huge
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
			local sim = lapsOnly(newSim())
			sim:step(0)
			local events = sim:takeEvents()
			local rolled = firstOfType(events, "LineupRolled")
			-- One egg for every LINEUP_EGG_SPACING studs of zone: more in the longer zones.
			local total, longest = 0, 0
			for zoneId = 1, Runway.ZONE_COUNT do
				local size = EggSpec.lineupSize(zoneId)
				local hasEggs = #Zones.List[zoneId].eggs > 0
				expect.equal(
					size,
					if hasEggs then math.round(Runway.zoneLength(zoneId) / Tuning.LINEUP_EGG_SPACING) else 0,
					"zone " .. zoneId
				)
				total += size
				longest = math.max(longest, (size - 1) * EggSpec.lineupGap(zoneId, 1))
				-- Out within a lap, a few seconds apart.
				expect.truthy(EggSpec.lineupGap(zoneId, 1) <= Tuning.LINEUP_LAUNCH_GAP, "gap")
			end
			expect.equal(EggSpec.lineupSize(1), 11)
			expect.equal(EggSpec.lineupSize(Runway.ZONE_COUNT), 39)
			expect.equal(#rolled.eggs, total)
			-- The first egg of every zone (with eggs) leaves straight away.
			expect.equal(#eventsOfType(events, "EggSpawned"), zonesWithEggs())

			for second = 1, math.ceil(longest) + 1 do
				sim:step(second)
			end
			local perZone = {}
			for _, egg in sim.eggs do
				perZone[egg.zone] = (perZone[egg.zone] or 0) + 1
				expect.falsy(egg.wild)
			end
			for zoneId = 1, Runway.ZONE_COUNT do
				expect.equal(perZone[zoneId] or 0, EggSpec.lineupSize(zoneId), "zone " .. zoneId)
			end
		end)

		it(
			"fades a riderless egg a quarter of the way into the next zone and starts it at the zone's start again",
			function()
				local sim = lapsOnly(newSim())
				sim:step(0)
				local first
				for _, egg in sim.eggs do
					if egg.zone == 1 then
						first = egg
					end
				end
				-- Random numbers of 0.5 roll Forest Common eggs, which roll from the start of the zone to a quarter of
				-- the way into the Desert.
				expect.equal(first.rarity, "Common")
				expect.equal(first.fadeZ, Runway.fadeZ(1))
				local lapTime = (Runway.fadeZ(1) - first.startZ) / first.spec.rollSpeed
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
				expect.truthy(again, "back at the start of the zone")
				expect.equal(again.kind, first.kind)
				expect.near(again.spawnTime, lapTime)
				local x, _, z = sim:eggCenter(sim:getEgg(again.id), lapTime)
				expect.equal(z, first.spec.startZ)
				-- In the world, on the runway's centre line there (eggs are steered in runway space; the runway winds).
				expect.near(x, Runway.worldX(again.lateral, z))
			end
		)

		it("fades the last zone's eggs a quarter of the way into its first copy (the runway has no end)", function()
			expect.equal(Runway.fadeZ(7), Runway.LENGTH + Runway.zoneLength(7) / 4)
			expect.equal(Runway.fadeZ(6), Runway.zoneStartZ(7) + Runway.zoneLength(7) / 4)
		end)

		it("brings a claimed lineup egg back on its next lap", function()
			local sim = lapsOnly(newSim())
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
			-- Alice rolls on for a while on her claimed egg, then gets off, and it disappears.
			sim:requestDismount(ALICE, 20)
			expect.falsy(sim:getEgg(first.id))

			-- (Eggs roll fast enough that some of the lineup is still waiting to set off by then, so look for this
			-- egg's own slot.)
			local function slotFilled()
				for _, egg in sim.eggs do
					if egg.slot == first.slot then
						return true
					end
				end
				return false
			end
			local lapTime = (Runway.fadeZ(1) - first.startZ) / first.spec.rollSpeed
			sim:step(lapTime - 0.01)
			expect.falsy(slotFilled(), "gone until its next lap")
			sim:step(lapTime)
			expect.truthy(slotFilled(), "the claimed egg's slot is back")
		end)

		it("never leaves the start of a zone without an egg for long, so there is always one to jump on", function()
			local sim = newSim()
			noMidCycle(sim)
			local lastAtStart = {}
			local longest = 0
			-- A whole day, a tenth of a second at a time, noting every egg that leaves the start of its zone.
			for tenth = 0, 1700 do
				local now = tenth / 10
				sim:step(now)
				for _, event in eventsOfType(sim:takeEvents(), "EggSpawned") do
					local egg = event.egg
					if egg.startZ == EggSpec.get(egg.zone, egg.rarity).startZ then
						if lastAtStart[egg.zone] then
							longest = math.max(longest, egg.spawnTime - lastAtStart[egg.zone])
						end
						lastAtStart[egg.zone] = egg.spawnTime
					end
				end
				-- And there is always an egg in the first stretch of every zone (that has eggs).
				if now > Tuning.START_EGG_GAP then
					for zoneId = 1, Runway.ZONE_COUNT do
						if EggSpec.lineupSize(zoneId) == 0 then
							continue
						end
						local near = false
						for _, egg in sim.eggs do
							local _, _, z = sim:eggCenter(egg, now)
							if egg.zone == zoneId and z - Runway.zoneStartZ(zoneId) < 120 then
								near = true
							end
						end
						expect.truthy(near, `zone {zoneId} at {now}s`)
					end
				end
			end
			expect.truthy(longest <= Tuning.START_EGG_GAP + 0.1 + 1e-6, `longest wait at a zone's start: {longest}s`)
		end)

		it("keeps the lineup's own eggs coming round when it sends one early", function()
			local sim = newSim()
			noMidCycle(sim)
			for second = 0, 170 do
				sim:step(second)
				sim:takeEvents()
			end
			-- Only the lineup's eggs (no mid-cycle eggs), and only the zone's own kinds.
			for _, egg in sim.eggs do
				expect.falsy(egg.wild)
				local found = false
				for _, slot in sim.lineup do
					found = found or (slot.zone == egg.zone and slot.kind == egg.kind)
				end
				expect.truthy(found, egg.kind)
			end
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
				if EggSpec.lineupSize(zoneId) > 0 then
					expect.truthy(wild[zoneId], "zone " .. zoneId)
				else
					expect.falsy(wild[zoneId], "no eggs yet in zone " .. zoneId)
				end
			end

			-- It fades at the end of its lap and does not come back.
			local forest = wild[1]
			local fadeAt = Tuning.WILD_DROP_INTERVAL + (forest.fadeZ - forest.startZ) / forest.spec.rollSpeed
			noMidCycle(sim)
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
					local rarity = EggSpec.rollRarity(6, (index + 0.5) / total, nil, rareOdds, "Secret")
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

		it("places a new egg on the ground at the start of its zone", function()
			local sim = quiet(newSim())
			local egg = sim:spawnEgg(3, 50, "Uncommon")
			local x, y, z = sim:eggCenter(egg, 50)
			-- On the centre line (the runway is straight, in the middle, at every zone's start).
			expect.near(x, Runway.worldX(0, z))
			expect.truthy(math.abs(x) < 1, "the runway is in the middle at a zone's start")
			-- The back of the egg sits just past the zone's start line.
			expect.near(z - egg.spec.radius, Runway.zoneStartZ(3) + Tuning.EGG_SPAWN_GAP)
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
			expect.equal(sim:spawnEgg(5, 0, "Secret").kind, "Abyss")

			-- A particular egg can be dropped by name, in its own zone only.
			local yeti = sim:spawnEgg(3, 0, nil, "Yeti")
			expect.equal(yeti.rarity, "Secret")
			expect.equal(yeti.spec.requirement, 7500)
			expect.falsy(sim:spawnEgg(1, 0, nil, "Yeti"), "Yeti is a Snow egg")
			expect.falsy(sim:spawnEgg(6, 0, nil, "MagmaDragon"), "shelved")
			expect.falsy(sim:spawnEgg(1, 0, nil, "NoSuchEgg"))
		end)

		it("drops an egg somewhere else when told to, keeping its own zone's numbers", function()
			local sim = newSim()
			-- A Volcano egg dropped in the Forest, off to one side.
			local egg = sim:spawnEgg(6, 10, nil, "LavaGolem", { z = 300, lateral = 12 })
			expect.equal(egg.zone, 6)
			expect.equal(egg.spec.requirement, 250000)
			local x, _, z = sim:eggCenter(egg, 10)
			expect.equal(z, 300)
			-- 12 studs across the runway from its centre line there (it winds).
			expect.near(x, Runway.worldX(12, 300))
			local spawned = firstOfType(sim:takeEvents(), "EggSpawned")
			expect.equal(spawned.egg.startZ, 300, "players' devices are told where it landed")
			expect.equal(spawned.egg.lateral, 12)

			-- Kept on the runway: not past its sides or beyond the end.
			local wide = sim:spawnEgg(1, 0, "Common", nil, { z = 1e6, lateral = -500 })
			expect.truthy(wide.startZ < Runway.LOOP_END, "before the end of the loop")
			expect.truthy(wide.fadeZ < Runway.LOOP_END, "and fades before it")
			expect.equal(wide.lateral, -Runway.maxLateral(wide.spec.halfLength, wide.startZ))
			local common = EggSpec.get(1, "Common")
			expect.equal(sim:spawnEgg(1, 0, "Common", nil, { z = 0 / 0 }).startZ, common.startZ, "nonsense is ignored")
			-- Without a placement, eggs appear at the start of their zone, and say so.
			expect.equal(sim:spawnEgg(2, 0, "Common").startZ, EggSpec.get(2, "Common").startZ)
		end)

		it("drops twice as many eggs at twice the rate (an Egg Avalanche)", function()
			local function dropsInAMinute(multiplier)
				local sim = newSim()
				sim.spawnRateMultiplier = multiplier
				for tick = 0, 600 do
					sim:step(tick / 10)
				end
				return #eventsOfType(sim:takeEvents(), "EggSpawned")
			end
			local normal, avalanche = dropsInAMinute(1), dropsInAMinute(2)
			expect.truthy(avalanche >= normal * 1.8, `{avalanche} in an Avalanche, {normal} normally`)
		end)

		it("clears every egg nobody is riding", function()
			local sim = newSim()
			sim:addRider(ALICE, 1000, 14, 0)
			local ridden = sim:spawnEgg(1, 0, "Common")
			sim:spawnEgg(1, 0, "Common")
			sim:spawnEgg(2, 0, "Common")
			sim:requestMount(ALICE, ridden.id, 0, true)
			sim:takeEvents()
			expect.equal(sim:clearUnridden(), 2)
			local removed = eventsOfType(sim:takeEvents(), "EggRemoved")
			expect.equal(#removed, 2)
			expect.equal(removed[1].reason, "Closure")
			expect.truthy(sim:getEgg(ridden.id), "the ridden egg rolls on")
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
			expect.equal(claimed.id, egg.id)
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
			-- She lost her balance: the egg bounces, about to crack.
			local left = firstOfType(events, "EggLeft")
			expect.equal(left.cracking, true)
			expect.truthy(sim:getEgg(egg.id))

			-- Stunned for 1.5 s.
			local ok, reason = sim:requestMount(ALICE, spare.id, 9, true)
			expect.falsy(ok)
			expect.equal(reason, "Stunned")
			expect.truthy(sim:requestMount(ALICE, spare.id, 10.2, true))
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

	describe("RunwaySim: leaving and cracking", function()
		it("leaves the egg rolling on the ground, free for anyone, when its rider jumps off", function()
			local sim = quiet(newSim())
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
			expect.equal(left.cracking, false, "no bounce, no crack")
			expect.equal(#eventsOfType(events, "EggRemoved"), 0)

			-- Bob's claim starts from zero: 9 s from when he got on.
			sim:step(8)
			expect.truthy(sim:requestMount(BOB, egg.id, 8, true))
			sim:step(16.9)
			expect.equal(#eventsOfType(sim:takeEvents(), "Claimed"), 0)
			sim:step(17)
			expect.equal(firstOfType(sim:takeEvents(), "Claimed").rider, BOB)
		end)

		it("leaves the egg rolling when its rider dies, leaves the game, or is knocked off", function()
			local sim = quiet(newSim())
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
			expect.truthy(sim:getEgg(first.id) and sim:getEgg(second.id))
		end)

		it("bounces the egg slightly and cracks it when its rider runs out of stamina, then brings it back", function()
			local sim = quiet(newSim())
			sim:addRider(ALICE, 100, 14, 0)
			sim:addRider(BOB, 100, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Epic") -- a mid-cycle egg
			sim:requestMount(ALICE, egg.id, 1, true)
			sim:takeEvents()

			sim:step(8.6) -- out of stamina at 8.5 s
			local left = firstOfType(sim:takeEvents(), "EggLeft")
			expect.equal(left.id, egg.id)
			expect.equal(left.cracking, true)
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
			expect.truthy(spawned, "back")
			expect.equal(spawned.egg.kind, egg.kind)
			expect.equal(spawned.egg.startZ, egg.spec.startZ)
		end)

		it("brings a cracked lineup egg back sooner than its next lap", function()
			local sim = newSim()
			noMidCycle(sim)
			sim:addRider(ALICE, 30, 14, 0) -- not enough for a Common egg (50)
			sim:step(0)
			local first
			for _, egg in sim.eggs do
				if egg.zone == 1 then
					first = egg
				end
			end
			sim:requestMount(ALICE, first.id, 1, true)
			sim:step(4.75) -- 30 stamina at 8 a second
			sim:step(4.75 + Tuning.CRACK_BOUNCE_TIME)
			sim:takeEvents()
			local back = 4.75 + Tuning.CRACK_BOUNCE_TIME + Tuning.EGG_RESPAWN_DELAY
			sim:step(back)
			local found = false
			for _, event in eventsOfType(sim:takeEvents(), "EggSpawned") do
				if event.egg.zone == 1 and math.abs(event.egg.spawnTime - back) < 1e-6 then
					found = true
				end
			end
			expect.truthy(found, "the cracked egg's slot left the start again")
		end)

		it("refunds stamina for hopping straight onto another egg", function()
			local sim = quiet(newSim())
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
			local sim = quiet(newSim())
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
			local sim = quiet(newSim())
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
			expect.truthy(sim:getEgg(egg.id), "carried past its fade line by its rider")

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
			-- It is in the inventory already, so it does not come back early.
			sim:step(40)
			expect.equal(#eventsOfType(sim:takeEvents(), "EggSpawned"), 0)
		end)

		it("shows the owner in the snapshot, so players who join later see the egg is taken", function()
			local sim, egg = claimedEgg()
			local entry = sim:snapshot()[1]
			expect.equal(entry.id, egg.id)
			expect.equal(entry.owner, ALICE)
			expect.equal(entry.rider, ALICE)
		end)
	end)

	describe("RunwaySim: the banks and the endless runway", function()
		-- Alice gets on a Common Forest egg a second before it reaches `z` (well before she could claim it) and steers
		-- it hard against the +x side there. Returns the sim, the egg, and when it got there.
		local function steerIntoSideAt(z)
			local sim = quiet(newSim())
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

		local function firstGap(side)
			for _, gap in Runway.wallGaps(1) do
				if gap.side == side then
					return gap
				end
			end
			error("no gap")
		end

		it(
			"bounces an egg steered into a bank back toward the middle, at a cost in stamina, and never kills",
			function()
				local sim, egg, at = steerIntoSideAt(60) -- the gate's stretch: no gaps
				-- She got on a second ago with a full 1M stamina, draining since.
				local before = 1e6 - egg.spec.drain
				local events = sim:takeEvents()
				expect.equal(#eventsOfType(events, "RideEnded"), 0, "she stays on")
				local edge = firstOfType(events, "EdgeHit")
				expect.equal(edge.id, egg.id)
				expect.equal(edge.rider, ALICE)
				expect.near(edge.lateral, Runway.maxLateral(egg.spec.halfLength, 60, 1) - Tuning.WALL_KNOCKBACK)
				expect.near(egg.lateral, edge.lateral)
				expect.equal(sim:getRider(ALICE).eggId, egg.id)
				local cost = egg.spec.requirement * Tuning.HIT_EFFECTS.Wall.stamina
				expect.near(sim:getStamina(ALICE, at), before - cost, 1e-3)
				-- It slows down for a moment.
				local slowed = firstOfType(events, "EggSlowed")
				expect.equal(slowed.id, egg.id)
				expect.near(slowed.slow.duration, Tuning.HIT_EFFECTS.Wall.slow)
				-- One knock counts once: still pressed against the side a moment later, it does not bounce again.
				sim:setLateral(ALICE, 999, at + 0.1)
				sim:step(at + 0.1)
				expect.equal(#eventsOfType(sim:takeEvents(), "EdgeHit"), 0)
			end
		)

		it("bounces an egg off the railing across a gap in the same way: nobody goes over the edge", function()
			local gap = firstGap(1)
			local sim, egg = steerIntoSideAt((gap.startZ + gap.endZ) / 2)
			local events = sim:takeEvents()
			expect.equal(#eventsOfType(events, "RideEnded"), 0)
			expect.equal(#eventsOfType(events, "EggRemoved"), 0)
			expect.truthy(firstOfType(events, "EdgeHit"))
			expect.truthy(sim:getEgg(egg.id))
		end)

		it("believes a rider's device that says the egg hit the side, if it was near the side", function()
			local sim = quiet(newSim())
			sim:addRider(ALICE, 1e6, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Common")
			sim:requestMount(ALICE, egg.id, 2, true)
			sim:takeEvents()
			expect.falsy(sim:reportEdge(ALICE, 2.1), "in the middle of the runway")
			expect.falsy(sim:reportEdge(BOB, 2.1), "not riding")
			egg.lateral = Runway.maxLateral(egg.spec.halfLength, egg.startZ) - 2
			expect.truthy(sim:reportEdge(ALICE, 2.2))
			expect.truthy(firstOfType(sim:takeEvents(), "EdgeHit"))
			expect.falsy(sim:reportEdge(ALICE, 2.3), "the same knock")
		end)

		it("is safe anywhere short of the side", function()
			local sim = quiet(newSim())
			sim:addRider(ALICE, 1e6, 200, 0)
			local egg = sim:spawnEgg(1, 0, "Common")
			sim:requestMount(ALICE, egg.id, 2, true)
			local _, _, z = sim:eggCenter(egg, 3)
			sim:setLateral(ALICE, Runway.maxLateral(egg.spec.halfLength, z) - 0.5, 3)
			sim:takeEvents()
			sim:step(3)
			expect.equal(#eventsOfType(sim:takeEvents(), "RideEnded"), 0)
		end)

		it("never ends: a ridden egg rolls on through the last zone forever, carried back each loop", function()
			local sim = quiet(newSim())
			sim:addRider(ALICE, 1e9, 14, 0)
			local egg = sim:spawnEgg(7, 0, "Eternal")
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
			expect.truthy(egg.startZ + egg.spec.rollSpeed * 600 > Runway.LENGTH * 3, "far past where it used to end")
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
			-- A Mythic egg takes 18 s to claim. Alice gets on 5 s before it reaches its fade line (750) and is still
			-- on it, unclaimed, when it gets there.
			local egg = sim:spawnEgg(1, 0, "Mythic")
			local atLine = (egg.fadeZ - egg.startZ) / egg.spec.rollSpeed
			sim:step(atLine - 5)
			sim:requestMount(ALICE, egg.id, atLine - 5, true)
			sim:step(atLine + 2)
			expect.truthy(sim:getEgg(egg.id), "carried past the line by its rider")
			sim:takeEvents()
			sim:requestDismount(ALICE, atLine + 3)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "EggRemoved").reason, "Faded")
			expect.equal(#eventsOfType(events, "EggLeft"), 0)
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
				local halfWidth = Runway.zoneWidth(obstacle.zone) / 2
				expect.truthy(math.abs(obstacle.x) + obstacle.hx <= halfWidth + 1e-6, "on the runway")
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
			local biggest = EggSpec.get(7, "Eternal")
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
					local startZ = spec.startZ
					local fadeZ = Runway.fadeZ(zoneId)
					for _, fromZ in { startZ, startZ + 230, startZ + 470 } do
						for lane = -60, 60, 4 do
							local path = Obstacles.planPath(lane, fromZ, fadeZ, spec.halfLength, spec.radius)
							local z = fromZ
							while z <= fadeZ do
								local x = Obstacles.lateralAt(path, z)
								local low, high = Runway.lateralRange(spec.halfLength, z)
								expect.truthy(x >= low - 1e-6 and x <= high + 1e-6, "stays on the runway")
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

		it("slows an egg down for a moment and catches it up again with time, the same on every device", function()
			local EggMotion = harness.load("src/shared/EggMotion")
			local slow = EggMotion.addSlow(nil, 10, 2)
			-- Before the slow-down: as normal. During it: rolling at SLOW_FACTOR. After it: as normal, a little behind.
			expect.near(EggMotion.zAt(0, 0, 20, 10, slow), 200)
			expect.near(EggMotion.zAt(0, 0, 20, 11, slow), 200 + 20 * Tuning.SLOW_FACTOR)
			local lost = 2 * (1 - Tuning.SLOW_FACTOR)
			expect.near(EggMotion.zAt(0, 0, 20, 15, slow), 20 * (15 - lost))
			-- A second slow-down while the first is still going keeps what the first had already cost.
			local again = EggMotion.addSlow(slow, 11, 2)
			expect.near(again.lost, 1 - Tuning.SLOW_FACTOR)
			expect.near(EggMotion.zAt(0, 0, 20, 11, again), EggMotion.zAt(0, 0, 20, 11, slow))
			expect.near(EggMotion.zAt(0, 0, 20, 20, again), 20 * (20 - 3 * (1 - Tuning.SLOW_FACTOR)))
			-- It never rolls backwards.
			local last = -math.huge
			for tenth = 0, 200 do
				local z = EggMotion.zAt(0, 0, 20, tenth / 10, again)
				expect.truthy(z >= last)
				last = z
			end
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
			expect.near(sim:getStamina(ALICE, arrive), before - egg.spec.requirement * Tuning.HIT_EFFECTS.Bump.stamina)
			expect.truthy(math.abs(egg.lateral - obstacle.x) >= obstacle.hx + egg.spec.halfLength, "clear of it")
			expect.equal(sim:getRider(ALICE).eggId, egg.id, "still riding")
			expect.falsy(sim:reportHit(ALICE, obstacle.id, arrive + 0.1), "each obstacle counts once")
		end)

		it("charges more for a Crash and slows the egg down, but the rider stays on", function()
			local sim = quiet(newSimWithObstacles())
			local obstacle = findObstacle(1, "Crash", false)
			local egg, arrive = rideInto(sim, obstacle, "Rare")
			local before = sim:getStamina(ALICE, arrive)
			expect.truthy(sim:reportHit(ALICE, obstacle.id, arrive))
			local events = sim:takeEvents()
			expect.equal(#eventsOfType(events, "RideEnded"), 0, "nothing throws a rider off but running out of stamina")
			expect.equal(firstOfType(events, "ObstacleHit").tier, "Crash")
			expect.near(sim:getStamina(ALICE, arrive), before - egg.spec.requirement * Tuning.HIT_EFFECTS.Crash.stamina)
			local slowed = firstOfType(events, "EggSlowed")
			expect.equal(slowed.id, egg.id)
			expect.equal(slowed.slow.at, arrive)
			-- From here it rolls slower for a moment: behind where it would have been.
			local _, _, z = sim:eggCenter(egg, arrive + 1)
			expect.near(z, egg.startZ + egg.spec.rollSpeed * (arrive + Tuning.SLOW_FACTOR))
			expect.equal(sim:getRider(ALICE).eggId, egg.id)
			-- Everyone is told, so every device draws it in the same place.
			expect.equal(sim:snapshot()[1].slow.at, arrive)
		end)

		it("slows the egg in lava or tar, and costs a little stamina, but never kills", function()
			-- Lava in the Volcano, tar in the Prehistoric zone (whose eggs start at Epic).
			for zoneId, rarity in { [6] = "Rare", [7] = "Epic" } do
				local sim = quiet(newSimWithObstacles())
				local obstacle = findObstacle(zoneId, "Slow", false)
				local egg, arrive = rideInto(sim, obstacle, rarity)
				local before = sim:getStamina(ALICE, arrive)
				expect.truthy(sim:reportHit(ALICE, obstacle.id, arrive))
				local events = sim:takeEvents()
				expect.equal(#eventsOfType(events, "RideEnded"), 0)
				expect.near(firstOfType(events, "EggSlowed").slow.duration, Tuning.HIT_EFFECTS.Slow.slow)
				expect.near(
					sim:getStamina(ALICE, arrive),
					before - egg.spec.requirement * Tuning.HIT_EFFECTS.Slow.stamina
				)
			end
		end)

		it("has no obstacle anywhere that throws a rider off or kills them", function()
			for _, obstacle in Obstacles.all() do
				expect.truthy(Tuning.HIT_EFFECTS[obstacle.tier], `{obstacle.kind} is a {obstacle.tier}`)
			end
			for name, kind in Obstacles.Config.Kinds do
				expect.truthy(kind.tier == "Bump" or kind.tier == "Crash" or kind.tier == "Slow", name)
			end
		end)

		it("lays out big obstacles too, with room to get past them", function()
			local big = {}
			for _, obstacle in Obstacles.all() do
				if obstacle.hx >= 9 then
					big[obstacle.zone] = (big[obstacle.zone] or 0) + 1
				end
			end
			for zoneId = 1, Runway.ZONE_COUNT do
				expect.truthy((big[zoneId] or 0) >= 1, `zone {zoneId} has a big obstacle`)
			end
		end)

		it("counts a hit on its own when the egg is well inside an obstacle", function()
			local sim = quiet(newSimWithObstacles())
			local obstacle = findObstacle(1, "Crash", false)
			local _, arrive = rideInto(sim, obstacle, "Rare")
			sim:step(arrive)
			local hit = firstOfType(sim:takeEvents(), "ObstacleHit")
			expect.equal(hit.obstacle, obstacle.id)
		end)

		it("ignores reports of hits that could not have happened", function()
			local sim = quiet(newSimWithObstacles())
			local obstacle = findObstacle(1, "Crash", false)
			local _, arrive = rideInto(sim, obstacle, "Rare")
			expect.falsy(sim:reportHit(ALICE, obstacle.id, arrive - 1.5), "not there yet")
			expect.falsy(sim:reportHit(ALICE, 99999, arrive), "no such obstacle")
			expect.falsy(sim:reportHit(BOB, obstacle.id, arrive), "not riding")

			-- A geyser only counts while it is going off.
			local geyser = findObstacle(2, "Crash", true)
			local function arrivalWhen(active)
				for tenth = 0, 600 do
					local spawnTime = 100 + tenth / 10
					local egg = EggSpec.get(2, "Common")
					local reach = spawnTime + (geyser.z - egg.startZ) / egg.rollSpeed
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

	describe("RunwaySim: refilling stamina", function()
		it("fills stamina to the max, and a ride keeps draining from there", function()
			local sim = newSim()
			sim:addRider(ALICE, 100, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Epic") -- drains 160 over 12 s: more than 100 stamina lasts
			sim:requestMount(ALICE, egg.id, 0, true)
			sim:step(5)
			expect.truthy(sim:getStamina(ALICE, 5) < 50, "drained")
			sim:refillStamina(ALICE, 5)
			expect.near(sim:getStamina(ALICE, 5), 100)
			local changed = firstOfType(sim:takeEvents(), "StaminaChanged")
			expect.truthy(changed, "StaminaChanged")
			-- With the refill, 100 stamina at 13.3 a second lasts the 7 s left of the claim.
			sim:step(12.5)
			expect.equal(#eventsOfType(sim:takeEvents(), "Claimed"), 1, "claimed")
			expect.equal(sim:getRider(ALICE).eggId, egg.id, "and still rolling on it")
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
			local _, _, z = sim:eggCenter(egg, 60)
			expect.near(egg.lateral, Runway.maxLateral(egg.spec.halfLength, z))

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

	describe("RunwaySim: riding a pet", function()
		it("costs stamina while riding, and the pet bucks its rider off when it runs out", function()
			local sim = quiet(newSim())
			sim:addRider(ALICE, 100, 14, 0)
			sim:takeEvents()
			expect.truthy(sim:setOnPet(ALICE, true, 0))
			local changed = firstOfType(sim:takeEvents(), "StaminaChanged")
			expect.equal(changed.rate, -Tuning.PET_RIDE_DRAIN)
			expect.near(sim:getStamina(ALICE, 10), 100 - 10 * Tuning.PET_RIDE_DRAIN)

			local emptyAt = 100 / Tuning.PET_RIDE_DRAIN
			sim:step(emptyAt - 0.1)
			expect.equal(#eventsOfType(sim:takeEvents(), "PetBucked"), 0)
			sim:step(emptyAt)
			local events = sim:takeEvents()
			expect.equal(firstOfType(events, "PetBucked").rider, ALICE)
			expect.equal(sim:getRider(ALICE).onPet, false)
			-- Off the pet, stamina comes back as usual.
			expect.truthy(sim:getStamina(ALICE, emptyAt + 1) > 0, "regenerates")
		end)

		it("lets a player with more Max Stamina ride for longer", function()
			local sim = quiet(newSim())
			sim:addRider(ALICE, 100, 14, 0)
			sim:addRider(BOB, 1000, 14, 0)
			sim:setOnPet(ALICE, true, 0)
			sim:setOnPet(BOB, true, 0)
			sim:takeEvents()
			sim:step(100 / Tuning.PET_RIDE_DRAIN)
			local bucked = eventsOfType(sim:takeEvents(), "PetBucked")
			expect.equal(#bucked, 1)
			expect.equal(bucked[1].rider, ALICE)
			sim:step(1000 / Tuning.PET_RIDE_DRAIN)
			expect.equal(firstOfType(sim:takeEvents(), "PetBucked").rider, BOB)
		end)

		it("turns away a player too tired to ride", function()
			local sim = quiet(newSim())
			sim:addRider(ALICE, 100, 14, 0)
			sim:setOnPet(ALICE, true, 0)
			sim:step(100 / Tuning.PET_RIDE_DRAIN)
			sim:takeEvents()
			-- Bucked off with nothing left: back on only once some stamina has come back.
			local now = 100 / Tuning.PET_RIDE_DRAIN
			expect.falsy(sim:setOnPet(ALICE, true, now))
			expect.equal(sim:getRider(ALICE).onPet, false)
			expect.truthy(sim:setOnPet(ALICE, true, now + 2), "rested")
		end)

		it("ends the pet ride when the rider gets on an egg", function()
			local sim = quiet(newSim())
			sim:addRider(ALICE, 500, 14, 0)
			local egg = sim:spawnEgg(1, 0, "Common")
			sim:setOnPet(ALICE, true, 0)
			expect.truthy(sim:requestMount(ALICE, egg.id, 1, true))
			expect.equal(sim:getRider(ALICE).onPet, false)
			sim:requestDismount(ALICE, 3)
			sim:takeEvents()
			sim:step(200)
			expect.equal(#eventsOfType(sim:takeEvents(), "PetBucked"), 0, "no pet to buck")
			expect.truthy(sim:getStamina(ALICE, 4) > sim:getStamina(ALICE, 3), "regenerating, not draining")
		end)

		it("keeps draining from the new value when Max Stamina changes mid-ride", function()
			local sim = quiet(newSim())
			sim:addRider(ALICE, 100, 14, 0)
			sim:setOnPet(ALICE, true, 0)
			sim:setMaxStamina(ALICE, 200, 10) -- 50 left
			sim:refillStamina(ALICE, 10) -- 200
			sim:takeEvents()
			sim:step(10 + 200 / Tuning.PET_RIDE_DRAIN - 0.1)
			expect.equal(#eventsOfType(sim:takeEvents(), "PetBucked"), 0)
			sim:step(10 + 200 / Tuning.PET_RIDE_DRAIN)
			expect.truthy(firstOfType(sim:takeEvents(), "PetBucked"))
		end)
	end)

	describe("RunwaySim: server luck", function()
		it("rolls rarer eggs while luck is boosted", function()
			-- With every random number at 0.5, a Forest egg is Common at normal luck and Uncommon at x4.
			local sim = newSim()
			expect.equal(sim:spawnEgg(1, 0).rarity, "Common")
			sim:setLuck(4)
			expect.equal(sim:spawnEgg(1, 0).rarity, "Uncommon")
			sim:setLuck(1)
			expect.equal(sim:spawnEgg(1, 0).rarity, "Common")
		end)

		it("ignores luck below 1 or not a number", function()
			local sim = newSim()
			sim:setLuck(0.25)
			expect.equal(sim.luck, 1)
			sim:setLuck(0 / 0)
			expect.equal(sim.luck, 1)
		end)
	end)
end
