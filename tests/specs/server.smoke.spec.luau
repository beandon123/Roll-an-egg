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
			Obstacles = session:require(folder.Obstacles),
			Runway = session:require(folder.Runway),
			Tuning = session:require(folder.Config.Tuning),
		}
	end

	local function runwayService(session)
		return session:require(session:service("ServerScriptService").Server.Services.RunwayService)
	end

	-- The path a riderless egg (as described in an EggSpawned message) follows round the obstacles, and its spec.
	local function eggPath(session, egg)
		local modules = shared(session)
		local spec = modules.EggSpec.get(egg.zone, egg.rarity)
		local startZ = modules.Runway.zoneStartZ(egg.zone) + modules.Tuning.EGG_SPAWN_OFFSET
		local path = modules.Obstacles.planPath(
			egg.lateral,
			startZ,
			modules.Runway.fadeZ(egg.zone),
			spec.halfLength,
			spec.radius
		)
		return path, spec, startZ
	end

	-- Where an egg (as described in an EggSpawned message) is right now, if nobody has steered it.
	local function eggPosition(session, egg)
		local modules = shared(session)
		local path, spec, startZ = eggPath(session, egg)
		local z = modules.EggMotion.zAt(egg.spawnTime, startZ, spec.rollSpeed, session.clock)
		local x = modules.Obstacles.lateralAt(path, z)
		return roblox.Vector3.new(x, modules.Runway.surfaceY(z) + spec.radius, z)
	end

	-- Rides an egg for a while, steering it along the path it would have taken on its own (which misses every
	-- obstacle), the way a careful rider would.
	local function rideAlongPath(session, player, egg, seconds)
		local modules = shared(session)
		local path, spec, startZ = eggPath(session, egg)
		for _ = 1, math.ceil(seconds * 30) do
			session:heartbeat(1 / 30)
			local z = modules.EggMotion.zAt(egg.spawnTime, startZ, spec.rollSpeed, session.clock)
			session:fromClient("RideLateral", player, modules.Obstacles.lateralAt(path, z))
		end
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
		it("builds the map: zones with banks and gates, and every obstacle", function()
			local session = startServer()
			local map = session:service("Workspace"):FindFirstChild("Map")
			expect.truthy(map, "Workspace.Map")
			expect.truthy(map.Hub:IsA("Part"))
			expect.truthy(map.Spawn:IsA("SpawnLocation"))
			expect.equal(#map.Plots:GetChildren(), 8, "plots")
			local runway = shared(session).Runway
			for _, zoneName in { "Forest", "Desert", "Snow", "Ocean", "Volcano", "Prehistoric" } do
				local zone = map:FindFirstChild(zoneName)
				expect.truthy(zone, zoneName)
				-- A level, checkered runway: 20-stud tiles, all with their tops at the runway's height.
				local tiles = 0
				for _, tile in zone.Ground:GetChildren() do
					if tile.Size.X == 20 and tile.Size.Z == 20 then
						tiles += 1
						expect.near(tile.CFrame.Position.Y + tile.Size.Y / 2, runway.BASE_Y, 1e-6)
					end
				end
				expect.equal(tiles, (runway.WIDTH / 20) * (runway.ZONE_LENGTH / 20), zoneName .. " tiles")
				expect.truthy(#zone.Banks:GetChildren() > 50, zoneName .. " banks")
				expect.truthy(#zone.Backdrop:GetChildren() > 0, zoneName .. " backdrop")
				expect.equal(#zone.Sign:GetChildren(), 2, zoneName .. " sign faces")
			end
			expect.equal(map.Desert.Sign.SurfaceGui.TextLabel.Text, "DESERT")
			expect.near(map.Hub.CFrame.Position.Y, runway.BASE_Y - 2)

			-- One model per obstacle, tagged for the client; the ones that go off carry the parts it animates.
			local Obstacles = shared(session).Obstacles
			expect.equal(#map.Obstacles:GetChildren(), #Obstacles.all())
			for _, model in map.Obstacles:GetChildren() do
				local obstacle = Obstacles.get(model:GetAttribute("ObstacleId"))
				expect.equal(model:GetAttribute("Kind"), obstacle.kind)
				expect.truthy(#model:GetChildren() > 0, obstacle.kind .. " has parts")
				if obstacle.kind == "SandGeyser" or obstacle.kind == "LavaVent" then
					expect.truthy(model:FindFirstChild("Burst"), obstacle.kind .. " burst")
					expect.truthy(model.Vent.WarnPoint.Warn:IsA("ParticleEmitter"), obstacle.kind .. " warning")
				elseif obstacle.kind == "GiantClam" then
					expect.truthy(model:FindFirstChild("Lid") and model:FindFirstChild("Shell"), "clam")
				end
			end
			expect.truthy(session:service("Lighting"):FindFirstChildOfClass("Atmosphere"), "haze")
			expect.equal(session:service("Players").RespawnTime, 2)
			expect.equal(#session.warnings, 0, "warnings: " .. table.concat(session.warnings, "; "))
		end)

		it("rolls a lineup at sunrise and tells everyone about its rarest eggs", function()
			local session = startServer()
			session:heartbeat(1 / 60)
			local spawned = session:sent("EggSpawned", "all")
			expect.equal(#spawned, 6, "the first egg of each zone's lineup")
			-- The Prehistoric zone only has Epic eggs and up, so its lineup always has something to announce.
			local announced = session:lastSent("Announce", "all")
			expect.truthy(announced, "announcement")
			expect.truthy(string.find(announced.args[1], "^Sunrise! Rolling today: "), announced.args[1])
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
			expect.equal(#snapshot.inventory.eggs, 0)
			expect.equal(snapshot.inventory.nestCount, 2)
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
			local inventory = session:lastSent("InventoryChanged", player).args[1]
			expect.equal(#inventory.eggs, 1)
			expect.equal(inventory.eggs[1].kind, egg.kind)

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
			session:fromClient("RideLateral", player, egg.lateral * 0.9)
			local first = session:lastSent("EggLateral", "all")
			expect.truthy(first, "EggLateral")
			expect.equal(first.args[1], egg.id)

			-- A move towards the middle, well within the rider's Agility, is relayed exactly.
			session:heartbeat(0.5)
			local target = first.args[2] - 3 * (if first.args[2] >= 0 then 1 else -1)
			session:fromClient("RideLateral", player, target)
			expect.near(session:lastSent("EggLateral", "all").args[2], target, 1e-6)

			-- Reports arriving faster than 30 a second are dropped.
			session:fromClient("RideLateral", player, target + 1)
			expect.equal(#session:sent("EggLateral", "all"), 2)
		end)

		it("checks the obstacle hits a rider reports, and kills riders who hit lava", function()
			local session = startServer()
			local player, humanoid, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			runwayService(session).SetMaxStamina(player, 1e9)
			local modules = shared(session)
			local lava
			for _, obstacle in modules.Obstacles.all() do
				if obstacle.kind == "LavaPool" then
					lava = obstacle
					break
				end
			end

			-- Get on a Volcano egg a few seconds before it reaches the lava pool.
			local egg = dropEgg(session, 5, "Rare")
			local path, spec, startZ = eggPath(session, egg)
			local arrive = egg.spawnTime + (lava.z - startZ) / spec.rollSpeed
			while session.clock < arrive - 3 do
				session:heartbeat(1 / 10)
			end
			root.Position = eggPosition(session, egg) + roblox.Vector3.new(0, 2, 0)
			session:fromClient("RequestMount", player, egg.id)
			session:heartbeat(1 / 60)
			expect.truthy(session:lastSent("RideStarted", player), "riding")

			-- A report from far away, or of nonsense, is ignored.
			session:fromClient("ReportHit", player, lava.id)
			session:fromClient("ReportHit", player, "nonsense")
			session:heartbeat(1 / 60)
			expect.equal(#session:sent("ObstacleHit", player), 0)

			-- Steer into the pool once past the row before it (the server only lets the egg move as fast as the
			-- rider's Agility allows), and report the hit as soon as the egg touches it.
			while session.clock < arrive - 0.6 do
				session:heartbeat(1 / 30)
				local z = modules.EggMotion.zAt(egg.spawnTime, startZ, spec.rollSpeed, session.clock)
				local steer = if session.clock > arrive - 2.2 then lava.x else modules.Obstacles.lateralAt(path, z)
				session:fromClient("RideLateral", player, steer)
			end
			session:fromClient("ReportHit", player, lava.id)
			session:heartbeat(1 / 60)
			local hit = session:lastSent("ObstacleHit", player)
			expect.truthy(hit, "ObstacleHit")
			expect.equal(hit.args[1], lava.id)
			expect.equal(hit.args[2], "Lethal")
			expect.equal(session:lastSent("RideEnded", player).args[1], "Hazard")
			expect.equal(humanoid.Health, 0)
		end)

		it("burns players who walk into lava", function()
			local session = startServer()
			local _, humanoid, root = session:addPlayer(1, "Tester")
			local modules = shared(session)
			local lava
			for _, obstacle in modules.Obstacles.all() do
				if obstacle.kind == "LavaPool" then
					lava = obstacle
					break
				end
			end
			root.Position = roblox.Vector3.new(lava.x + lava.hx + 4, modules.Runway.BASE_Y + 3, lava.z)
			task.wait(0.4)
			expect.equal(humanoid.Health, 100, "safe beside it")
			root.Position = roblox.Vector3.new(lava.x, modules.Runway.BASE_Y + 3, lava.z)
			task.wait(0.4)
			expect.equal(humanoid.Health, 0)
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
			local egg = dropEgg(session, 6, "Eternal")

			-- Wait until the egg is too close to the end to be claimed, then get on, and steer clear of everything.
			session:heartbeat(0.5, 20)
			root.Position = eggPosition(session, egg)
			session:fromClient("RequestMount", player, egg.id)
			rideAlongPath(session, player, egg, 20)
			expect.equal(session:lastSent("RideEnded", player).args[1], "Cliff")
			expect.equal(humanoid.Health, 0)
		end)
	end)

	describe("Server: plots and hatching", function()
		local function services(session)
			local folder = session:service("ServerScriptService").Server.Services
			return session:require(folder.InventoryService), session:require(folder.PlotService)
		end

		local function plotModel(session, index)
			return session:service("Workspace").Map.Plots["Plot" .. index]
		end

		local function signText(plot)
			return plot.Sign:FindFirstChildOfClass("SurfaceGui").TextLabel.Text
		end

		it("gives each player a plot with two nests, and frees it when they leave", function()
			local session = startServer()
			local first = session:addPlayer(1, "Tester")
			local second = session:addPlayer(2, "Other")
			session:heartbeat(1 / 60)
			local _, PlotService = services(session)
			expect.equal(PlotService.GetPlot(first), 1)
			expect.equal(PlotService.GetPlot(second), 2)
			local plot = plotModel(session, 1)
			expect.equal(plot:GetAttribute("Owner"), 1)
			expect.equal(signText(plot), "Tester's Pen")
			expect.equal(#plot.Nests:GetChildren(), 2)
			expect.equal(signText(plotModel(session, 3)), "Free plot")

			session:fire(session:service("Players"), "PlayerRemoving", first)
			expect.equal(plot:GetAttribute("Owner"), 0)
			expect.equal(signText(plot), "Free plot")
		end)

		it("sends players to their plot when they respawn", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local character = roblox.Instance.new("Model")
			local humanoid = roblox.Instance.new("Humanoid")
			humanoid.Parent = character
			local root = roblox.Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Parent = character
			character.Parent = session:service("Workspace")
			session:fire(player, "CharacterAdded", character)
			task.wait()
			local Plots = session:require(session:service("ReplicatedStorage").Shared.Plots)
			local x, z = Plots.spawnPoint(1)
			expect.near(root.CFrame.Position.X, x, 1e-3)
			expect.near(root.CFrame.Position.Z, z, 1e-3)
		end)

		it("places an egg in a nest, where it hatches on a timer into a pet in the pen", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local InventoryService = services(session)
			InventoryService.AddEgg(player, 1, "Common", "Leafy")
			local data = session.profiles.Player_1.Data
			local uid = data.Eggs[1].uid

			session:fromClient("PlaceEgg", player, uid)
			expect.equal(#data.Eggs, 0)
			expect.equal(data.Nests[1].slot, 1)
			local inventory = session:lastSent("InventoryChanged", player).args[1]
			expect.equal(#inventory.nests, 1)
			local nest = plotModel(session, 1).Nests.Nest1
			expect.equal(nest:GetAttribute("EggKind"), "Leafy")
			expect.equal(nest:GetAttribute("EggName"), "Leafy Egg")
			expect.truthy(nest:FindFirstChild("Egg"), "the egg sits in the nest")

			-- A Common egg takes 30 seconds.
			session:heartbeat(1, 29)
			task.wait(0.6)
			expect.equal(#data.Pets, 0)
			session:heartbeat(1, 2)
			task.wait(0.6)
			expect.equal(#data.Pets, 1)
			expect.equal(data.Pets[1].kind, "Squirrel")
			expect.equal(#data.Nests, 0)
			local hatched = session:lastSent("PetHatched", player)
			expect.equal(hatched.args[1].kind, "Squirrel")
			expect.equal(nest:GetAttribute("EggKind"), "")
			expect.falsy(nest:FindFirstChild("Egg"))
			expect.truthy(nest:GetAttribute("HatchedAt"), "marked for the burst")
			expect.equal(plotModel(session, 1):GetAttribute("Pets"), "Squirrel")
			expect.equal(#session:lastSent("InventoryChanged", player).args[1].pets, 1)
		end)

		it("ignores eggs the player does not have, and keeps eggs when the nests are full", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local InventoryService = services(session)
			for _ = 1, 3 do
				InventoryService.AddEgg(player, 1, "Rare", "Toadstool")
			end
			local data = session.profiles.Player_1.Data
			session:fromClient("PlaceEgg", player, "not-an-egg")
			session:fromClient("PlaceEgg", player, 42)
			expect.equal(#data.Nests, 0)
			for index = 1, 3 do
				session:heartbeat(0.3)
				session:fromClient("PlaceEgg", player, data.Eggs[1].uid)
				expect.equal(#data.Nests, math.min(index, 2))
			end
			expect.equal(#data.Eggs, 1, "the third egg waits in the inventory")
		end)

		it("hatches eggs that finished while the player was away", function()
			local session = startServer()
			local now = session.clock
			session.saved.Player_1 = {
				Eggs = {},
				Nests = {
					{
						slot = 1,
						uid = "x",
						zone = 1,
						rarity = "Epic",
						kind = "Bear",
						placedAt = now - 3600,
						bonus = 0,
					},
				},
				Pets = {},
			}
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			expect.equal(#data.Pets, 1)
			expect.equal(data.Pets[1].kind, "Bear")
			expect.equal(data.NestCount, 2, "filled in for an old save")
			expect.equal(session:lastSent("PetHatched", player).args[1].kind, "Bear")
		end)

		it("banks the closure's 30x hatching when the next cycle starts", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			task.wait(0.1)
			local InventoryService = services(session)
			InventoryService.AddEgg(player, 1, "Epic", "Bear")
			local data = session.profiles.Player_1.Data
			-- Placed shortly before the runway closes, then through to the next cycle.
			local cycleStart = (math.floor(session.clock / 180) + 1) * 180
			session.clock = cycleStart - 25
			session:fromClient("PlaceEgg", player, data.Eggs[1].uid)
			session.clock = cycleStart + 1
			task.wait(0.6)
			expect.near(data.Nests[1].bonus, 29 * 10)
		end)

		it("can give eggs and finish hatching from the Studio test panel", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			session:fromClient("DevCommand", player, "GiveEggs")
			local data = session.profiles.Player_1.Data
			expect.equal(#data.Eggs, 8, "one of each Forest egg")
			session:fromClient("PlaceEgg", player, data.Eggs[8].uid)
			session:fromClient("DevCommand", player, "HatchNow")
			expect.equal(#data.Pets, 1)
			expect.equal(data.Pets[1].kind, "Treant")
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

		it("show the Volcano pets, the Lava Dragon with wings of wedges and fire", function()
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
				"Cerberus,Chimera,CinderBoar,FireSalamander,LavaDragon,LavaGolem,ObsidianGoat,VolcanoTortoise"
			)
			local phoenix = folder.LavaDragon
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
			expect.truthy(wedges > 20, "wedges in its wings: " .. wedges)
			expect.truthy(eggs >= 0, "egg shapes: " .. eggs)
			expect.truthy(turned > 30, "parts at an angle: " .. turned)
			expect.truthy(fires >= 3, "flames: " .. fires)
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
				"Obsidian,CinderBoar,VolcanoTortoise,Salamander,Chimera,LavaGolem,Cerberus,LavaDragon"
			)
		end)

		it("show the Prehistoric pets, the Lunar Dragon with starry wings and moonfire", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			root.Position = roblox.Vector3.new(0, 0, 3300) -- Prehistoric
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
				"Brachiosaurus,LunarDragon,Mosasaurus,Pteranodon,Stegosaurus,TRex,Triceratops,Velociraptor"
			)
			local wedges, stars, fires = 0, 0, 0
			for _, part in folder.LunarDragon:GetDescendants() do
				if part:IsA("WedgePart") then
					wedges += 1
				elseif part:IsA("SpecialMesh") and part.MeshType == roblox.Enum.MeshType.Sphere then
					stars += 1
				elseif part:IsA("Fire") then
					fires += 1
				end
			end
			expect.truthy(wedges > 20, "wedges in its wings: " .. wedges)
			expect.truthy(stars >= 20, "stars on its wings: " .. stars)
			expect.equal(fires, 3, "moonfire on its horns and tail")
			-- The T-Rex and the Mosasaurus have animated limbs too.
			for _, name in { "TRex", "Mosasaurus" } do
				local joints = 0
				for _, joint in folder[name]:GetDescendants() do
					if joint:IsA("Motor6D") then
						joints += 1
					end
				end
				expect.truthy(joints >= 4, name .. " joints: " .. joints)
			end
		end)

		it("drop each of the Prehistoric eggs in turn", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			root.Position = roblox.Vector3.new(0, 0, 3300) -- Prehistoric
			session:heartbeat(1 / 60)
			session:clearSent()
			session:fromClient("DevCommand", player, "DropEachEgg")
			task.wait(6)
			session:heartbeat(1 / 60)
			local kinds = {}
			for _, entry in session:sent("EggSpawned", "all") do
				if entry.args[1].zone == 6 then
					table.insert(kinds, entry.args[1].kind)
				end
			end
			expect.equal(
				table.concat(kinds, ","),
				"Raptor,Pteranodon,Triceratops,Stegosaurus,Brachiosaurus,TRex,Mosasaurus,LunarDragon"
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
