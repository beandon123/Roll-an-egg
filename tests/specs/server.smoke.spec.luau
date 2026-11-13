--!nocheck
-- Runs the real server script from the built place file against the stand-in for Roblox Studio (tests/studio).
-- These catch misspelled properties, wrong wiring between services, and mistakes in how the server talks to
-- players. They cannot check physics or anything else that needs the real engine.

local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Studio = require("../studio")

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local place, reason = Studio.buildPlace()
	if place == nil then
		print(`SKIPPED server smoke tests: {reason}`)
		return
	end

	-- A running server with the save system replaced by an in-memory stand-in.
	local function startServer(options)
		local session = Studio.open(place, { isServer = true, isStudio = not (options and options.live) })
		session:useFakeProfileStore()
		session:run(session:service("ServerScriptService").Server)
		return session
	end

	local function shared(session)
		local folder = session:service("ReplicatedStorage").Shared
		return {
			EggSpec = session:require(folder.EggSpec),
			EggMotion = session:require(folder.EggMotion),
			Runway = session:require(folder.Runway),
			Tuning = session:require(folder.Config.Tuning),
		}
	end

	local function runwayService(session)
		return session:require(session:service("ServerScriptService").Server.Services.RunwayService)
	end

	-- Where an egg (as described in an EggSpawned message) is right now.
	local function eggPosition(session, egg)
		local modules = shared(session)
		local spec = modules.EggSpec.get(egg.zone, egg.rarity)
		local startZ = modules.Runway.zoneStartZ(egg.zone) + modules.Tuning.EGG_SPAWN_OFFSET
		local z = modules.EggMotion.zAt(egg.spawnTime, startZ, spec.rollSpeed, session.clock)
		return roblox.Vector3.new(egg.lateral, modules.Runway.surfaceY(z) + spec.radius, z)
	end

	-- Drops an egg of a chosen rarity and returns its EggSpawned message.
	local function dropEgg(session, zone, rarity)
		session:clearSent()
		expect.truthy(runwayService(session).DropEgg(zone, rarity), "DropEgg")
		session:heartbeat(1 / 60)
		for _, entry in session:sent("EggSpawned", "all") do
			local egg = entry.args[1]
			if egg.zone == zone and egg.rarity == rarity then
				return egg
			end
		end
		error("the dropped egg was not announced")
	end

	-- Drops an egg, stands the player on it, and asks to mount.
	local function mount(session, player, root, zone, rarity)
		local egg = dropEgg(session, zone, rarity)
		root.Position = eggPosition(session, egg) + roblox.Vector3.new(0, 2, 0)
		session:fromClient("RequestMount", player, egg.id)
		session:heartbeat(1 / 60)
		return egg
	end

	describe("Server: starting up", function()
		it("builds the placeholder map", function()
			local session = startServer()
			local map = session:service("Workspace"):FindFirstChild("Map")
			expect.truthy(map, "Workspace.Map")
			expect.truthy(map.Hub:IsA("Part"))
			expect.truthy(map.Spawn:IsA("SpawnLocation"))
			expect.equal(#map.Plots:GetChildren(), 8, "plots")
			for _, zoneName in { "Forest", "Desert", "Snow", "Ocean", "Volcano" } do
				local zone = map:FindFirstChild(zoneName)
				expect.truthy(zone, zoneName)
				expect.truthy(zone.Ground:IsA("Part"))
				expect.equal(#zone.Sign:GetChildren(), 2, zoneName .. " sign faces")
			end
			-- The Forest slab starts level with the hub and ends 24 studs lower (600 studs at a 4% slope).
			local runway = shared(session).Runway
			expect.near(map.Hub.Position.Y, runway.BASE_Y - 2)
			expect.near(map.Forest.Ground.Size.X, runway.WIDTH)
			expect.near(map.Forest.Ground.Size.Z, 600 / math.cos(math.atan(0.04)), 1e-3)
			expect.equal(map.Desert.Sign.SurfaceGui.TextLabel.Text, "DESERT")
			expect.equal(session:service("Players").RespawnTime, 2)
			expect.equal(#session.warnings, 0, "warnings: " .. table.concat(session.warnings, "; "))
		end)

		it("creates every remote", function()
			local session = startServer()
			local remotes = session:service("ReplicatedStorage").Remotes
			for _, name in { "EggSpawned", "EggRemoved", "RideStarted", "RideEnded", "StaminaChanged", "RequestMount" } do
				expect.equal(remotes[name].ClassName, "RemoteEvent", name)
			end
			expect.equal(remotes.RideLateral.ClassName, "UnreliableRemoteEvent")
			expect.equal(remotes.GetSnapshot.ClassName, "RemoteFunction")
		end)

		it("drops eggs in every zone", function()
			local session = startServer()
			session:heartbeat(0.1, 300)
			local zonesSeen = {}
			for _, entry in session:sent("EggSpawned", "all") do
				zonesSeen[entry.args[1].zone] = true
			end
			for zoneId = 1, 5 do
				expect.truthy(zonesSeen[zoneId], "zone " .. zoneId)
			end
		end)

		it("clears eggs without riders when the runway closes", function()
			local session = startServer()
			session:heartbeat(0.1, 300)
			session:clearSent()
			-- The session starts 5 s into a cycle and the runway closes at 170 s.
			session:heartbeat(0.5, 280)
			local closures = 0
			for _, entry in session:sent("EggRemoved", "all") do
				if entry.args[2] == "Closure" then
					closures += 1
				end
			end
			expect.truthy(closures >= 10, "eggs removed by the closure: " .. closures)
		end)
	end)

	describe("Server: players", function()
		it("loads a player's data and tells them their stamina", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			local stamina = session:lastSent("StaminaChanged", player)
			expect.truthy(stamina, "StaminaChanged")
			expect.equal(stamina.args[1], 100, "value")
			expect.near(stamina.args[3], 12, 1e-6, "regen per second")
			expect.equal(stamina.args[4], 100, "max")

			local snapshot = session:remote("GetSnapshot").OnServerInvoke(player)
			expect.equal(type(snapshot.eggs), "table")
			expect.equal(snapshot.stamina.max, 100)
			expect.equal(snapshot.eggCount, 0)
			expect.equal(#session.kicks, 0)
		end)

		it("gives every player a streaming focus that follows them", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			root.Position = roblox.Vector3.new(5, 13, 250)
			session:heartbeat(1 / 60)
			local focus = player.ReplicationFocus
			expect.truthy(focus and focus:IsA("Part"), "ReplicationFocus")
			expect.equal(focus.Position, root.Position)
		end)

		it("kills a character that falls off the runway", function()
			local session = startServer()
			local _, humanoid, root = session:addPlayer(1, "Tester")
			root.Position = roblox.Vector3.new(80, -200, 300)
			-- The fall check runs on its own loop four times a second.
			task.wait(0.8)
			expect.equal(humanoid.Health, 0)
		end)
	end)

	describe("Server: riding", function()
		it("lets a player ride an egg to a claim and saves it", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			local egg = mount(session, player, root, 1, "Common")
			local started = session:lastSent("RideStarted", player)
			expect.truthy(started, "RideStarted")
			expect.equal(started.args[1], egg.id)
			expect.equal(started.args[2].claimTime, 5)
			expect.near(started.args[2].drain, 8)
			expect.equal(session:lastSent("EggMounted", "all").args[2], 1)

			-- While riding, the streaming focus rides the egg, not the character the server last saw.
			root.Position = roblox.Vector3.new(0, 13, -100)
			session:heartbeat(0.5)
			expect.near(player.ReplicationFocus.Position.Z, eggPosition(session, egg).Z, 1e-3)

			session:heartbeat(0.1, 50)
			local ended = session:lastSent("RideEnded", player)
			expect.truthy(ended, "RideEnded")
			expect.equal(ended.args[1], "Claimed")
			expect.equal(ended.args[2].rarity, "Common")
			expect.equal(ended.args[2].kind, egg.kind)

			local removed
			for _, entry in session:sent("EggRemoved", "all") do
				if entry.args[1] == egg.id then
					removed = entry
				end
			end
			expect.equal(removed.args[2], "Claimed")
			expect.equal(removed.args[3], 1, "claimed by")
			expect.equal(session:lastSent("InventoryUpdated", player).args[1], 1)

			local data = session.profiles.Player_1.Data
			expect.equal(#data.Eggs, 1)
			expect.equal(data.Eggs[1].zone, 1)
			expect.equal(data.Eggs[1].rarity, "Common")
			expect.equal(data.Eggs[1].kind, egg.kind)
			expect.truthy(egg.kind == "Leafy" or egg.kind == "Cottontail", "a Forest Common egg: " .. egg.kind)
			expect.truthy(data.Eggs[1].uid, "uid")
			expect.equal(data.Stats.EggsClaimed, 1)

			-- Leaving saves the data.
			session:fire(session:service("Players"), "PlayerRemoving", player)
			expect.equal(#session.saved.Player_1.Eggs, 1)
		end)

		it("ignores mount requests from far away and nonsense arguments", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local egg = dropEgg(session, 3, "Uncommon")

			-- The player is still at the hub, 1,300 studs from a Snow egg.
			session:fromClient("RequestMount", player, egg.id)
			session:fromClient("RequestMount", player, "abc")
			session:fromClient("RequestMount", player, nil)
			session:fromClient("RequestMount", player, 0 / 0)
			session:fromClient("RequestMount", player, {})
			session:fromClient("RideLateral", player, "left")
			session:fromClient("RideLateral", player, 5)
			session:fromClient("RequestDismount", player)
			session:fromClient("DevCommand", player, 42)
			session:heartbeat(1 / 60)
			expect.equal(#session:sent("RideStarted"), 0)
			expect.equal(#session:sent("EggLateral"), 0)
		end)

		it("throws off a rider who runs out of stamina and bounces the egg", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local egg = mount(session, player, root, 1, "Epic") -- needs 200 stamina; the player has 100
			expect.truthy(session:lastSent("RideStarted", player), "RideStarted")

			session:heartbeat(0.1, 80)
			expect.equal(session:lastSent("RideEnded", player).args[1], "ThrownOff")
			local left = session:lastSent("EggLeft", "all")
			expect.equal(left.args[1], egg.id)
			expect.equal(left.args[3], 1, "bounces left")
			expect.equal(#session.profiles.Player_1.Data.Eggs, 0)
		end)

		it("relays steering to everyone", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local egg = mount(session, player, root, 1, "Common")

			session:heartbeat(0.5)
			session:fromClient("RideLateral", player, egg.lateral + 4)
			local relayed = session:lastSent("EggLateral", "all")
			expect.truthy(relayed, "EggLateral")
			expect.equal(relayed.args[1], egg.id)
			expect.near(relayed.args[2], egg.lateral + 4, 1e-6)

			-- Reports arriving faster than 30 a second are dropped.
			session:fromClient("RideLateral", player, egg.lateral + 5)
			expect.equal(#session:sent("EggLateral", "all"), 1)
		end)

		it("frees the egg when its rider dies or hops off", function()
			local session = startServer()
			local player, humanoid, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			local first = mount(session, player, root, 1, "Rare")
			session:fire(humanoid, "Died")
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("RideEnded", player).args[1], "Died")
			expect.equal(session:lastSent("EggLeft", "all").args[1], first.id)

			-- The server ignores mount requests that come less than 0.2 s apart.
			session:heartbeat(0.5)
			local second = mount(session, player, root, 1, "Rare")
			session:fromClient("RequestDismount", player)
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("RideEnded", player).args[1], "Dismount")
			expect.equal(session:lastSent("EggLeft", "all").args[1], second.id)
		end)

		it("kills a rider who goes over the end of the runway", function()
			local session = startServer()
			local player, humanoid, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			runwayService(session).SetMaxStamina(player, 1e9)
			local egg = dropEgg(session, 5, "Eternal")

			-- Wait until the egg is too close to the end to be claimed, then get on.
			session:heartbeat(0.5, 20)
			root.Position = eggPosition(session, egg)
			session:fromClient("RequestMount", player, egg.id)
			session:heartbeat(0.5, 40)
			expect.equal(session:lastSent("RideEnded", player).args[1], "Cliff")
			expect.equal(humanoid.Health, 0)
		end)
	end)

	describe("Server: Studio test tools", function()
		it("raise Max Stamina in Studio", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			session:fromClient("DevCommand", player, "StaminaUp")
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("StaminaChanged", player).args[4], 500)
			session:fromClient("DevCommand", player, "StaminaReset")
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("StaminaChanged", player).args[4], 100)
		end)

		it("drop the best egg of the zone the player is in", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			root.Position = roblox.Vector3.new(0, 0, 700) -- Desert
			session:heartbeat(1 / 60)
			session:clearSent()
			session:fromClient("DevCommand", player, "DropBestEgg")
			session:heartbeat(1 / 60)
			local found = false
			for _, entry in session:sent("EggSpawned", "all") do
				if entry.args[1].zone == 2 and entry.args[1].rarity == "Mythic" then
					found = true
				end
			end
			expect.truthy(found, "a Mythic Desert egg")
			local announce = session:lastSent("Announce", "all")
			expect.truthy(announce, "announcement")
			local text = announce.args[1]
			expect.truthy(
				text == "A Mythic Sphinx Egg just dropped in the Desert!"
					or text == "A Mythic Scarab Egg just dropped in the Desert!",
				text
			)
		end)

		it("show the zone's pets, rigged and ready to animate", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			root.Position = roblox.Vector3.new(0, 13, 100) -- Forest
			session:heartbeat(1 / 60)
			session:fromClient("DevCommand", player, "ShowPets")
			local folder = session:service("Workspace"):FindFirstChild("StudioPets")
			expect.truthy(folder, "Workspace.StudioPets")
			local names = {}
			for _, pet in folder:GetChildren() do
				table.insert(names, pet.Name)
			end
			table.sort(names)
			expect.equal(table.concat(names, ","), "Bear,Bunny,Fox,Hedgehog,MossStag,Owl,Squirrel,Treant")

			local fox = folder.Fox
			expect.truthy(fox.PrimaryPart == fox.Root, "PrimaryPart")
			expect.equal(fox.Root.Anchored, true)
			-- Every limb is a part on a Motor6D, and the legs and head hang from the body.
			local body = fox.Body
			expect.truthy(fox.Root:FindFirstChild("Body"):IsA("Motor6D"), "Root -> Body motor")
			for _, limb in { "Head", "FrontLeftLeg", "FrontRightLeg", "BackLeftLeg", "BackRightLeg", "Tail" } do
				local motor = body:FindFirstChild(limb)
				expect.truthy(motor and motor:IsA("Motor6D"), "Body -> " .. limb .. " motor")
				expect.truthy(motor.Part1 == fox[limb], limb .. " motor joins the limb")
			end
			local blocks = 0
			for _, part in fox:GetChildren() do
				if part:IsA("BasePart") and part:FindFirstChildOfClass("WeldConstraint") then
					blocks += 1
					expect.equal(part.Anchored, false)
				end
			end
			expect.truthy(blocks > 15, "visible blocks welded to their limbs: " .. blocks)
			expect.truthy(fox:GetAttribute("GroundOffset") > 0, "GroundOffset")
			expect.truthy(fox:GetAttribute("SeatOffset"), "SeatOffset")
			-- The Treant is Mythic: it glows and sparkles.
			expect.truthy(folder.Treant.Root:FindFirstChildOfClass("PointLight"), "Treant light")
			expect.truthy(folder.Treant.Root:FindFirstChildOfClass("ParticleEmitter"), "Treant particles")

			-- Showing them again replaces them rather than piling up.
			session:fromClient("DevCommand", player, "ShowPets")
			local folders = 0
			for _, child in session:service("Workspace"):GetChildren() do
				if child.Name == "StudioPets" then
					folders += 1
				end
			end
			expect.equal(folders, 1)
		end)

		it("show the Volcano pets, the Eternal Phoenix with wedges, egg shapes and fire", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			root.Position = roblox.Vector3.new(0, 0, 2500) -- Volcano
			session:heartbeat(1 / 60)
			session:fromClient("DevCommand", player, "ShowPets")
			local folder = session:service("Workspace"):FindFirstChild("StudioPets")
			local names = {}
			for _, pet in folder:GetChildren() do
				table.insert(names, pet.Name)
			end
			table.sort(names)
			expect.equal(
				table.concat(names, ","),
				"Cerberus,Chimera,CinderBoar,EternalPhoenix,FireSalamander,LavaGolem,ObsidianGoat,VolcanoTortoise"
			)
			local phoenix = folder.EternalPhoenix
			local wedges, eggs, fires, turned = 0, 0, 0, 0
			for _, part in phoenix:GetDescendants() do
				if part:IsA("WedgePart") then
					wedges += 1
				elseif part:IsA("SpecialMesh") and part.MeshType == roblox.Enum.MeshType.Sphere then
					eggs += 1
				elseif part:IsA("Fire") then
					fires += 1
				end
				if part:IsA("BasePart") and part.CFrame.UpVector.Y < 0.999 then
					turned += 1
				end
			end
			expect.truthy(wedges > 50, "wedge feather tips: " .. wedges)
			expect.truthy(eggs > 10, "egg shapes: " .. eggs)
			expect.truthy(turned > 100, "parts at an angle: " .. turned)
			expect.truthy(fires >= 5, "flames: " .. fires)
			for _, fire in phoenix:GetDescendants() do
				if fire:IsA("Fire") then
					expect.truthy(
						fire.Parent:FindFirstChildOfClass("WeldConstraint"),
						"each flame is welded to its limb"
					)
				end
			end
		end)

		it("drop each of the zone's eggs in turn", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			root.Position = roblox.Vector3.new(0, 0, 2500) -- Volcano
			session:heartbeat(1 / 60)
			session:clearSent()
			session:fromClient("DevCommand", player, "DropEachEgg")
			task.wait(6)
			session:heartbeat(1 / 60)
			local kinds = {}
			for _, entry in session:sent("EggSpawned", "all") do
				if entry.args[1].zone == 5 then
					table.insert(kinds, entry.args[1].kind)
				end
			end
			expect.equal(
				table.concat(kinds, ","),
				"Obsidian,CinderBoar,VolcanoTortoise,Salamander,Chimera,LavaGolem,Cerberus,EternalPhoenix"
			)
		end)

		it("do nothing in a live server", function()
			local session = startServer({ live = true })
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			session:fromClient("DevCommand", player, "StaminaUp")
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("StaminaChanged", player).args[4], 100)
		end)
	end)
end
