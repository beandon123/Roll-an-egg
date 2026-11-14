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

	-- A running server with the save system replaced by an in-memory stand-in. Options:
	--     live      run as a live game rather than in Studio
	--     admins    user IDs listed as admins (Server/Config/Admins)
	--     clock     the shared server clock to start at
	--     before    called with the session just before the server script runs (to add imported models, say)
	local function startServer(options)
		options = options or {}
		local session = Studio.open(place, { isServer = true, isStudio = not options.live })
		session:useFakeProfileStore()
		local server = session:service("ServerScriptService").Server
		if options.admins then
			session:override(server.Config.Admins, { UserIds = options.admins, GROUP_RANK = 255 })
		end
		if options.clock then
			session.clock = options.clock
		end
		if options.before then
			options.before(session)
		end
		session:run(server)
		return session
	end

	-- Sends an admin panel command as `player`, then lets the server run a frame (it sends what happened to the
	-- runway on its next frame). Returns the server's answer (ok, message, data).
	local function admin(session, player, command, args)
		local ok, message, data = session:remote("AdminCommand").OnServerInvoke(player, command, args)
		session:heartbeat(1 / 60)
		return ok, message, data
	end

	-- The last egg of a kind announced as dropped, or nil.
	local function lastDropped(session, kind)
		local found = nil
		for _, entry in session:sent("EggSpawned", "all") do
			if entry.args[1].kind == kind then
				found = entry.args[1]
			end
		end
		return found
	end

	local function shared(session)
		local folder = session:service("ReplicatedStorage").Shared
		return {
			EggSpec = session:require(folder.EggSpec),
			EggMotion = session:require(folder.EggMotion),
			Obstacles = session:require(folder.Obstacles),
			Runway = session:require(folder.Runway),
			Tuning = session:require(folder.Config.Tuning),
			Zones = session:require(folder.Config.Zones),
		}
	end

	local function runwayService(session)
		return session:require(session:service("ServerScriptService").Server.Services.RunwayService)
	end

	-- The server's own copy of Config/Shop: changing it (to give an item a product ID) changes the running game.
	local function shopConfig(session)
		return session:require(session:service("ReplicatedStorage").Shared.Config.Shop)
	end

	local function dataOf(session, userId)
		return session.profiles["Player_" .. userId].Data
	end

	-- The last purchase result sent to a player: { itemId, ok, message }.
	local function purchaseResult(session, player)
		local entry = session:lastSent("PurchaseResult", player)
		return entry and entry.args
	end

	local function processReceipt(session, receipt)
		return session:service("MarketplaceService").ProcessReceipt(receipt)
	end

	-- The shop ignores requests closer together than this (seconds of real time).
	local SHOP_COOLDOWN = 0.55

	-- The path a riderless egg (as described in an EggSpawned message) follows round the obstacles, and its spec.
	local function eggPath(session, egg)
		local modules = shared(session)
		local spec = modules.EggSpec.get(egg.zone, egg.rarity)
		local startZ = egg.startZ or (modules.Runway.zoneStartZ(egg.zone) + modules.Tuning.EGG_SPAWN_OFFSET)
		local fadeZ = math.max(
			modules.Runway.fadeZ(egg.zone),
			math.min(startZ + modules.Runway.ZONE_LENGTH, modules.Runway.LENGTH)
		)
		local path = modules.Obstacles.planPath(egg.lateral, startZ, fadeZ, spec.halfLength, spec.radius)
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
			expect.equal(snapshot.inventory.eggCapacity, 2)
			expect.equal(snapshot.dollars, 0)
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
			admin(session, player, 42)
			admin(session, player, "DropEgg", "MossStag")
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

			-- Steering clear of the obstacles, the stamina runs out after 7.5 s.
			rideAlongPath(session, player, egg, 8)
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

	describe("Server: plots, pens and pets", function()
		local function services(session)
			local folder = session:service("ServerScriptService").Server.Services
			return session:require(folder.InventoryService),
				session:require(folder.PlotService),
				session:require(folder.MountService)
		end

		local function plotModel(session, index)
			return session:service("Workspace").Map.Plots["Plot" .. index]
		end

		local function signText(plot)
			return plot.Sign:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel").Text
		end

		local function plots(session)
			return session:require(session:service("ReplicatedStorage").Shared.Plots)
		end

		-- Stands the player's character in their pen, at (inward, along), facing up the plot.
		local function standInPen(session, root, index, inward, along)
			local x, z = plots(session).point(index, inward, along)
			root.CFrame = roblox.CFrame.new(x, 13, z)
		end

		local function lastNotice(session, player)
			local notice = session:lastSent("Notice", player)
			return if notice then notice.args[1] else ""
		end

		it("gives each player a plot with an open pen and an upgrade button, and frees it when they leave", function()
			local session = startServer()
			local first = session:addPlayer(1, "Tester")
			local second = session:addPlayer(2, "Other")
			session:heartbeat(1 / 60)
			local _, PlotService = services(session)
			expect.equal(PlotService.GetPlot(first), 1)
			expect.equal(PlotService.GetPlot(second), 2)
			local plot = plotModel(session, 1)
			expect.equal(plot:GetAttribute("Owner"), 1)
			expect.equal(plot:GetAttribute("PenLevel"), 1)
			expect.equal(signText(plot), "Tester's Pen")
			expect.near(plot.Pen.Floor.Size.X, plots(session).penWidth(1))
			expect.falsy(plot:FindFirstChild("Nests"), "no nests: eggs go anywhere")
			local prompt = plot.UpgradeButton.Pad.Upgrade
			expect.truthy(prompt:IsA("ProximityPrompt"))
			expect.equal(plot.UpgradeButton.Pad.Material, roblox.Enum.Material.Neon)
			expect.equal(prompt.ObjectText, "$750")
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
			local x, z = plots(session).spawnPoint(1)
			expect.near(root.CFrame.Position.X, x, 1e-3)
			expect.near(root.CFrame.Position.Z, z, 1e-3)
		end)

		it("puts an egg down where the player stands in their pen, where it hatches into a pet", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local InventoryService = services(session)
			InventoryService.AddEgg(player, 1, "Common", "Leafy")
			local data = session.profiles.Player_1.Data
			local uid = data.Eggs[1].uid

			-- Not in the pen: nothing happens but a hint.
			session:fromClient("PlaceEgg", player, uid)
			expect.equal(#data.Hatching, 0)
			expect.truthy(string.find(lastNotice(session, player), "Walk into your pen"), lastNotice(session, player))

			standInPen(session, root, 1, 30, 10)
			session:heartbeat(0.3)
			session:fromClient("PlaceEgg", player, uid)
			expect.equal(#data.Eggs, 0)
			local entry = data.Hatching[1]
			expect.near(entry.along, 10, 5)
			expect.near(entry.inward, 30, 5)
			local egg = plotModel(session, 1).Eggs["Egg_" .. uid]
			expect.equal(egg:GetAttribute("EggKind"), "Leafy")
			expect.equal(egg:GetAttribute("EggName"), "Leafy Egg")
			local x, z = plots(session).point(1, entry.inward, entry.along)
			expect.near(egg.Bed.CFrame.Position.X, x, 1e-3)
			expect.near(egg.Bed.CFrame.Position.Z, z, 1e-3)
			expect.equal(#session:lastSent("InventoryChanged", player).args[1].hatching, 1)

			-- A Common egg takes 30 seconds.
			session:heartbeat(1, 29)
			task.wait(0.6)
			expect.equal(#data.Pets, 0)
			session:heartbeat(1, 2)
			task.wait(0.6)
			expect.equal(#data.Pets, 1)
			local pet = data.Pets[1]
			expect.equal(pet.kind, "Squirrel")
			expect.truthy(pet.variant, "a variant")
			expect.equal(pet.inPen, true)
			expect.equal(session:lastSent("PetHatched", player).args[1].kind, "Squirrel")
			expect.truthy(egg:GetAttribute("HatchedAt"), "bursting open")
			expect.equal(plotModel(session, 1):GetAttribute("Pets"), "Squirrel:" .. pet.variant)
		end)

		it("hatches only as many eggs at once as the pen allows, spaced apart", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local InventoryService = services(session)
			for _ = 1, 3 do
				InventoryService.AddEgg(player, 1, "Rare", "Toadstool")
			end
			local data = session.profiles.Player_1.Data
			standInPen(session, root, 1, 30, 0)
			session:fromClient("PlaceEgg", player, "not-an-egg")
			session:fromClient("PlaceEgg", player, 42)
			expect.equal(#data.Hatching, 0)
			for index = 1, 3 do
				session:heartbeat(0.3)
				session:fromClient("PlaceEgg", player, data.Eggs[1].uid)
				expect.equal(#data.Hatching, math.min(index, 2))
			end
			expect.equal(#data.Eggs, 1, "the third egg waits in the inventory")
			expect.truthy(string.find(lastNotice(session, player), "only hatch 2 eggs"), lastNotice(session, player))
			local a, b = data.Hatching[1], data.Hatching[2]
			local dx, dz = a.inward - b.inward, a.along - b.along
			expect.truthy(math.sqrt(dx * dx + dz * dz) >= 8 - 1e-6, "spaced apart")
		end)

		it("hatches eggs that finished while the player was away, from an old save too", function()
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
				NestCount = 2,
				Coins = 5,
				Pets = {},
			}
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			expect.equal(#data.Pets, 1)
			expect.equal(data.Pets[1].kind, "Bear")
			expect.equal(data.Nests, nil, "moved over")
			expect.equal(data.SchemaVersion, 2)
			expect.truthy(data.Dollars >= 5)
			expect.equal(session:lastSent("PetHatched", player).args[1].kind, "Bear")
		end)

		it("banks the closure's 30x hatching when the next cycle starts", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			task.wait(0.1)
			local InventoryService = services(session)
			InventoryService.AddEgg(player, 1, "Epic", "Bear")
			local data = session.profiles.Player_1.Data
			standInPen(session, root, 1, 30, 0)
			-- Put down shortly before the runway closes, then through to the next cycle.
			local cycleStart = (math.floor(session.clock / 180) + 1) * 180
			session.clock = cycleStart - 25
			session:fromClient("PlaceEgg", player, data.Eggs[1].uid)
			session.clock = cycleStart + 1
			task.wait(0.6)
			expect.near(data.Hatching[1].bonus, 29 * 10)
		end)

		it("pays dollars every second for the pets in the pen", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			for index = 1, 2 do
				table.insert(data.Pets, {
					uid = "p" .. index,
					kind = "Bear",
					egg = "Bear",
					zone = 1,
					rarity = "Epic",
					variant = "Normal",
					inPen = index == 1,
					hatchedAt = 0,
				})
			end
			task.wait(0.6)
			local before = data.Dollars
			session:heartbeat(2)
			task.wait(0.6)
			-- One Forest Epic pet in the pen earns $4 a second; the other is not in the pen.
			expect.near(data.Dollars - before, 8, 0.5)
			local paid = session:lastSent("DollarsChanged", player)
			expect.equal(paid.args[2], 4)
		end)

		it("lets players choose their pen's pets, equip the best, and sell pets", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			for index, rarity in { "Common", "Mythic" } do
				table.insert(data.Pets, {
					uid = "p" .. index,
					kind = "Bear",
					egg = "Bear",
					zone = 1,
					rarity = rarity,
					variant = "Normal",
					inPen = false,
					hatchedAt = index,
				})
			end
			session:fromClient("SetInPen", player, "p1", true)
			expect.equal(data.Pets[1].inPen, true)
			expect.equal(plotModel(session, 1):GetAttribute("Pets"), "Bear:Normal")
			session:heartbeat(0.3)
			session:fromClient("SetInPen", player, "p1", "yes")
			session:fromClient("SetInPen", player, "p1", false)
			expect.equal(data.Pets[1].inPen, false)
			session:heartbeat(0.3)
			session:fromClient("EquipBest", player)
			expect.equal(data.Pets[1].inPen, true)
			expect.equal(data.Pets[2].inPen, true)

			session:heartbeat(0.3)
			local before = data.Dollars
			session:fromClient("SellPet", player, "p2")
			expect.equal(#data.Pets, 1)
			expect.near(data.Dollars - before, 10 * 150)
			expect.truthy(string.find(lastNotice(session, player), "Sold Bear for %$1.5K"), lastNotice(session, player))
		end)

		it("buys a bigger pen when its owner presses the green button and can pay", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			local other = session:addPlayer(2, "Other")
			session:heartbeat(1 / 60)
			local plot = plotModel(session, 1)
			local prompt = plot.UpgradeButton.Pad.Upgrade
			local data = session.profiles.Player_1.Data

			session:fire(prompt, "Triggered", player)
			expect.equal(data.PenLevel, 1)
			expect.truthy(string.find(lastNotice(session, player), "costs %$750"), lastNotice(session, player))

			data.Dollars = 1000
			session:fire(prompt, "Triggered", other)
			expect.equal(data.PenLevel, 1, "only the owner")
			session:fire(prompt, "Triggered", player)
			expect.equal(data.PenLevel, 2)
			expect.equal(data.Dollars, 250)
			expect.equal(plot:GetAttribute("PenLevel"), 2)
			expect.near(plot.Pen.Floor.Size.X, plots(session).penWidth(2))
			expect.equal(prompt.ObjectText, "$5K")
			expect.equal(session:lastSent("InventoryChanged", player).args[1].eggCapacity, 3)
		end)

		it("lets players ride their pets, faster than walking, and get off again", function()
			local session = startServer()
			local player, humanoid, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			table.insert(data.Pets, {
				uid = "steed",
				kind = "Bear",
				egg = "Bear",
				zone = 1,
				rarity = "Epic",
				variant = "Gold",
				inPen = true,
				hatchedAt = 0,
			})
			humanoid.WalkSpeed = 16
			humanoid.HipHeight = 2
			session:fromClient("RidePet", player, "steed")
			local mounts = session:service("Workspace").Mounts:GetChildren()
			expect.equal(#mounts, 1)
			local ridden = mounts[1]
			expect.equal(ridden.Name, "Bear")
			expect.equal(ridden:GetAttribute("Rider"), 1)
			expect.equal(ridden:GetAttribute("Variant"), "Gold")
			expect.equal(ridden.PrimaryPart.MountWeld.Part0, root)
			expect.equal(ridden.PrimaryPart.Anchored, false)
			expect.equal(humanoid.WalkSpeed, 30 + 4, "an Epic pet, plus Gold")
			expect.truthy(humanoid.HipHeight > 2, "lifted onto its back")
			expect.equal(data.Mount, "steed")
			expect.equal(session:lastSent("MountChanged", player).args[1], "steed")

			session:heartbeat(0.3)
			session:fromClient("RidePet", player, "")
			expect.equal(#session:service("Workspace").Mounts:GetChildren(), 0)
			expect.equal(humanoid.WalkSpeed, 16)
			expect.equal(humanoid.HipHeight, 2)
			expect.equal(session:lastSent("MountChanged", player).args[1], "")

			-- Someone else's pet cannot be ridden.
			session:heartbeat(0.3)
			session:fromClient("RidePet", player, "not-mine")
			expect.equal(#session:service("Workspace").Mounts:GetChildren(), 0)
		end)

		it("sends a ridden pet away while its rider is on an egg, and brings it back after", function()
			local session = startServer()
			local player, humanoid, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			table.insert(data.Pets, {
				uid = "steed",
				kind = "Fox",
				egg = "Foxtail",
				zone = 1,
				rarity = "Uncommon",
				variant = "Normal",
				inPen = true,
				hatchedAt = 0,
			})
			session:fromClient("RidePet", player, "steed")
			expect.equal(#session:service("Workspace").Mounts:GetChildren(), 1)
			mount(session, player, root, 1, "Common")
			expect.equal(session:lastSent("RideStarted", player).args[1] ~= nil, true)
			expect.equal(#session:service("Workspace").Mounts:GetChildren(), 0, "away while on the egg")
			session:fromClient("RequestDismount", player)
			session:heartbeat(1 / 60)
			task.wait(3.3)
			expect.equal(#session:service("Workspace").Mounts:GetChildren(), 1, "back after leaving the egg")
			expect.equal(humanoid.WalkSpeed, 24)

			-- Selling the pet sends it away for good.
			session:heartbeat(0.3)
			session:fromClient("SellPet", player, "steed")
			expect.equal(#session:service("Workspace").Mounts:GetChildren(), 0)
			expect.equal(data.Mount, "")
		end)

		it("can give eggs, pets and dollars and finish hatching from the admin panel", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			expect.truthy((admin(session, player, "GiveEgg", { egg = "Treant", count = 2 })))
			expect.equal(#data.Eggs, 2)
			expect.equal(session:lastSent("InventoryChanged", player).args[1].eggs[1].kind, "Treant")

			-- Nothing to hatch yet.
			expect.falsy((admin(session, player, "HatchNow")))
			standInPen(session, root, 1, 30, 0)
			session:fromClient("PlaceEgg", player, data.Eggs[1].uid)
			local ok, message = admin(session, player, "HatchNow")
			expect.truthy(ok, message)
			expect.equal(message, "Hatched 1 egg.")
			expect.equal(#data.Pets, 1)
			expect.equal(data.Pets[1].kind, "Treant")
			expect.truthy(data.Pets[1].inPen, "into the pen")

			-- A pet given straight away goes into the pen too, ready to earn.
			expect.truthy((admin(session, player, "GivePet", { pet = "Fox" })))
			expect.equal(#data.Pets, 2)
			expect.equal(data.Pets[2].egg, "Foxtail")
			expect.truthy(data.Pets[2].inPen)
			expect.equal(plotModel(session, 1):GetAttribute("Pets"):find("Fox:Normal", 1, true) ~= nil, true)

			expect.truthy((admin(session, player, "Dollars", { action = "Add", amount = 1e6 })))
			expect.equal(data.Dollars, 1e6)
			expect.equal(session:lastSent("DollarsChanged", player).args[1], 1e6)
			expect.truthy((admin(session, player, "Dollars", { action = "Reset" })))
			expect.equal(data.Dollars, 0)
		end)
	end)

	-- The kinds of egg announced as dropped in a zone, in the order they dropped.
	local function droppedKinds(session, zone)
		local kinds = {}
		for _, entry in session:sent("EggSpawned", "all") do
			if entry.args[1].zone == zone then
				table.insert(kinds, entry.args[1].kind)
			end
		end
		return kinds
	end

	local function server(session)
		return session:service("ServerScriptService").Server
	end

	describe("Server: who can use the admin panel", function()
		it("lets everyone in Studio", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			expect.equal(player:GetAttribute("IsAdmin"), true)
			expect.equal(player:GetAttribute("FlySpeed"), 80, "default fly speed")
			local ok, message = admin(session, player, "Stamina", { action = "Times5" })
			expect.truthy(ok, message)
		end)

		it("lets nobody in a live game but the owner and the listed admins", function()
			local session = startServer({ live = true, admins = { 2 } })
			local player = session:addPlayer(1, "Player")
			local listed = session:addPlayer(2, "Listed")
			session:heartbeat(1 / 60)
			expect.equal(player:GetAttribute("IsAdmin"), false)
			local ok, message = admin(session, player, "Stamina", { action = "Times5" })
			expect.falsy(ok)
			expect.equal(message, "Only admins can do that.")
			expect.equal(session:lastSent("StaminaChanged", player).args[4], 100)

			expect.equal(listed:GetAttribute("IsAdmin"), true)
			expect.truthy((admin(session, listed, "Stamina", { action = "Times5" })))
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("StaminaChanged", listed).args[4], 500)
		end)

		it("turns away unknown commands, bad arguments, and floods", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			expect.falsy((admin(session, player, "Explode")))
			expect.falsy((admin(session, player, 42)))
			expect.falsy((admin(session, player, "DropEgg", { egg = "NoSuchEgg" })))
			expect.falsy((admin(session, player, "DropEgg", { egg = 7 })))
			expect.falsy((admin(session, player, "Teleport", { to = "Zone", zone = 99 })))
			expect.falsy((admin(session, player, "SetFlySpeed", { speed = 5000 })))
			local refused = 0
			for _ = 1, 30 do
				local _, message = admin(session, player, "Stamina", { action = "Refill" })
				if message == "Slow down a little." then
					refused += 1
				end
			end
			expect.truthy(refused > 0, "a flood of commands is slowed down")
			expect.equal(#session.warnings, 0, "warnings: " .. table.concat(session.warnings, "; "))
		end)
	end)

	describe("Server: admin panel, eggs and stamina", function()
		it("raises, maxes, refills and resets stamina", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			admin(session, player, "Stamina", { action = "Times5" })
			expect.equal(session:lastSent("StaminaChanged", player).args[4], 500)
			admin(session, player, "Stamina", { action = "Max" })
			local changed = session:lastSent("StaminaChanged", player)
			expect.equal(changed.args[4], 1e7, "max")
			expect.equal(changed.args[1], 1e7, "and full")
			admin(session, player, "Stamina", { action = "Reset" })
			expect.equal(session:lastSent("StaminaChanged", player).args[4], 100)
		end)

		it("resets Max Stamina to what the player owns from the shop", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			data.MaxStaminaBonus = 400
			data.StaminaMultiplier = 2
			admin(session, player, "Stamina", { action = "Max" })
			local ok, message = admin(session, player, "Stamina", { action = "Reset" })
			expect.truthy(ok, message)
			expect.equal(message, "Max Stamina is back to 1000.")
			expect.equal(session:lastSent("StaminaChanged", player).args[4], 1000, "(100 + 400 bought) x2")
		end)

		it("gives and resets dollars, showing the player straight away", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			local ok, message = admin(session, player, "Dollars", { action = "Add", amount = 1e6 })
			expect.truthy(ok, message)
			expect.equal(message, "You have $1M.")
			expect.equal(data.Dollars, 1e6)
			expect.equal(session:lastSent("PlayerStateUpdated", player).args[1].dollars, 1e6)
			expect.equal(session:lastSent("DollarsChanged", player).args[1], 1e6)
			expect.falsy(
				(admin(session, player, "Dollars", { action = "Add", amount = 123 })),
				"only the offered amounts"
			)
			expect.equal(data.Dollars, 1e6)
			admin(session, player, "Dollars", { action = "Reset" })
			expect.equal(data.Dollars, 0)
			expect.equal(session:lastSent("PlayerStateUpdated", player).args[1].dollars, 0)
		end)

		it("drops any egg at its zone's chute, or on the runway in front of the player", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			session:clearSent()
			local ok, message = admin(session, player, "DropEgg", { egg = "MossStag", where = "Chute" })
			expect.truthy(ok, message)
			expect.equal(message, "Dropped a Moss Stag Egg.")
			local egg = lastDropped(session, "MossStag")
			expect.truthy(egg, "the Moss Stag egg dropped")
			expect.equal(egg.rarity, "Legendary")
			expect.equal(egg.startZ, 12, "lands at the Forest chute")

			-- Standing in the Desert, a Snow egg lands just ahead and keeps its Snow rarity and size.
			root.Position = roblox.Vector3.new(10, 0, 700)
			session:clearSent()
			ok, message = admin(session, player, "DropEgg", { egg = "Yeti", where = "Here" })
			expect.truthy(ok, message)
			egg = lastDropped(session, "Yeti")
			expect.equal(egg.zone, 3)
			expect.equal(egg.rarity, "Secret")
			expect.equal(egg.startZ, 710)
			expect.equal(egg.lateral, 10)

			-- Off the runway, "here" falls back to the chute and says so.
			root.Position = roblox.Vector3.new(0, 13, -100)
			session:clearSent()
			ok, message = admin(session, player, "DropEgg", { egg = "Yeti", where = "Here" })
			expect.truthy(ok)
			expect.truthy(message:find("not on the runway"), message)
			expect.equal(lastDropped(session, "Yeti").startZ, 1212)

			-- A Mythic egg is announced to everyone, by its name.
			ok = admin(session, player, "DropEgg", { egg = "Sphinx", where = "Chute" })
			expect.truthy(ok)
			local announced = false
			for _, entry in session:sent("Announce", "all") do
				announced = announced or entry.args[1] == "A Mythic Sphinx Egg just dropped in the Desert!"
			end
			expect.truthy(announced, "announced")
		end)

		it("drops a random egg and every egg of a zone, and clears the runway", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			session:clearSent()
			expect.truthy((admin(session, player, "DropRandomEgg", { zone = 2, where = "Chute" })))
			expect.truthy(#droppedKinds(session, 2) >= 1, "a Desert egg dropped")

			session:clearSent()
			admin(session, player, "DropZoneEggs", { zone = 5 })
			admin(session, player, "DropZoneEggs", { zone = 6 })
			task.wait(6.5)
			session:heartbeat(1 / 60)
			expect.equal(
				table.concat(droppedKinds(session, 5), ","),
				"Obsidian,CinderBoar,VolcanoTortoise,Salamander,Chimera,LavaGolem,Cerberus,LavaDragon"
			)
			expect.equal(
				table.concat(droppedKinds(session, 6), ","),
				"Raptor,Pteranodon,Triceratops,Stegosaurus,Brachiosaurus,TRex,Mosasaurus,LunarDragon"
			)

			session:clearSent()
			local ok, message = admin(session, player, "ClearRunway")
			expect.truthy(ok)
			local cleared = tonumber(message:match("^Cleared (%d+) eggs nobody was riding%.$"))
			expect.truthy(cleared and cleared >= 17, message)
			local closures = 0
			for _, entry in session:sent("EggRemoved", "all") do
				if entry.args[2] == "Closure" then
					closures += 1
				end
			end
			expect.equal(closures, cleared, "each one goes the way eggs do at a closure")
		end)
	end)

	describe("Server: admin panel, inventory", function()
		it("gives eggs and pets, lists them by kind, and clears them", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			local ok, message, inventory = admin(session, player, "GiveEgg", { egg = "MossStag", count = 3 })
			expect.truthy(ok, message)
			expect.equal(message, "Gave you 3 Moss Stag Eggs.")
			admin(session, player, "GiveEgg", { egg = "Leafy" })
			local data = session.profiles.Player_1.Data
			expect.equal(#data.Eggs, 4)
			expect.equal(data.Eggs[1].kind, "MossStag")
			expect.equal(data.Eggs[1].zone, 1)
			expect.equal(data.Eggs[1].rarity, "Legendary")
			expect.equal(data.Stats.EggsClaimed, 0, "given eggs are not counted as claimed")
			expect.equal(#session:lastSent("InventoryChanged", player).args[1].eggs, 4)
			expect.equal(inventory.eggCount, 3)

			ok, message, inventory = admin(session, player, "GivePet", { pet = "LavaDragon" })
			expect.truthy(ok, message)
			expect.equal(#data.Pets, 1)
			local pet = data.Pets[1]
			expect.equal(pet.kind, "LavaDragon")
			expect.equal(pet.zone, 5)
			expect.equal(pet.rarity, "Eternal")
			expect.equal(pet.variant, "Normal")
			expect.equal(pet.egg, "LavaDragon")
			expect.equal(pet.inPen, true, "into the pen, where it earns")
			expect.equal(type(pet.uid), "string")

			-- Listed by kind, in runway order and rarest last.
			ok, _, inventory = admin(session, player, "GetInventory")
			expect.truthy(ok)
			expect.equal(inventory.eggCount, 4)
			expect.equal(inventory.eggs[1].name, "Leafy Egg")
			expect.equal(inventory.eggs[2].name, "Moss Stag Egg")
			expect.equal(inventory.eggs[2].count, 3)
			expect.equal(inventory.pets[1].name, "Lava Dragon")

			-- Nonsense is refused, and a huge count is not trusted.
			expect.falsy((admin(session, player, "GivePet", { pet = "Dinosaur" })))
			admin(session, player, "GiveEgg", { egg = "Leafy", count = 1e9 })
			expect.equal(#data.Eggs, 5)

			ok = admin(session, player, "ClearInventory", { what = "Eggs" })
			expect.truthy(ok)
			expect.equal(#data.Eggs, 0)
			expect.equal(#data.Pets, 1)
			expect.equal(#session:lastSent("InventoryChanged", player).args[1].eggs, 0)
			admin(session, player, "ClearInventory", { what = "Pets" })
			expect.equal(#data.Pets, 0)
			expect.equal(#session:lastSent("InventoryChanged", player).args[1].pets, 0)
		end)
	end)

	describe("Server: admin panel, pets in the world", function()
		it("spawns a pet in front of the player, facing them, and removes it", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			-- Facing down the runway (+Z).
			root.CFrame = roblox.CFrame.lookAt(roblox.Vector3.new(0, 13, -100), roblox.Vector3.new(0, 13, 0))
			session:heartbeat(1 / 60)
			local ok, message = admin(session, player, "SpawnPet", { pet = "Fox" })
			expect.truthy(ok, message)
			local fox = session:service("Workspace").AdminPets.Fox
			local position = fox.Root.CFrame.Position
			expect.truthy(position.Z > -95, "in front of the player: " .. position.Z)
			expect.near(position.X, 0, 1e-3)
			expect.near(position.Y, 10 + fox:GetAttribute("GroundOffset"), 1e-3, "standing on the ground")
			expect.truthy(fox.Root.CFrame.LookVector.Z < -0.99, "facing back at the player")

			ok, message = admin(session, player, "ClearPets")
			expect.truthy(ok)
			expect.equal(message, "Removed 1 spawned pet.")
			expect.equal(#session:service("Workspace").AdminPets:GetChildren(), 0)
		end)

		it("shows a zone's pets, rigged and ready to animate", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			admin(session, player, "ShowZonePets", { zone = 1 })
			local folder = session:service("Workspace").AdminPets:FindFirstChild("ZonePets")
			expect.truthy(folder, "Workspace.AdminPets.ZonePets")
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
			admin(session, player, "ShowZonePets", { zone = 1 })
			expect.equal(#session:service("Workspace").AdminPets:GetChildren(), 1)
		end)

		it("shows the Volcano pets, the Lava Dragon with wings of wedges and fire", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			admin(session, player, "ShowZonePets", { zone = 5 })
			local folder = session:service("Workspace").AdminPets.ZonePets
			local names = {}
			for _, pet in folder:GetChildren() do
				table.insert(names, pet.Name)
			end
			table.sort(names)
			expect.equal(
				table.concat(names, ","),
				"Cerberus,Chimera,CinderBoar,FireSalamander,LavaDragon,LavaGolem,ObsidianGoat,VolcanoTortoise"
			)
			local dragon = folder.LavaDragon
			local wedges, fires, turned = 0, 0, 0
			for _, part in dragon:GetDescendants() do
				if part:IsA("WedgePart") then
					wedges += 1
				elseif part:IsA("Fire") then
					fires += 1
					expect.truthy(
						part.Parent:FindFirstChildOfClass("WeldConstraint"),
						"each flame is welded to its limb"
					)
				end
				if part:IsA("BasePart") and part.CFrame.UpVector.Y < 0.999 then
					turned += 1
				end
			end
			expect.truthy(wedges > 20, "wedges in its wings: " .. wedges)
			expect.truthy(turned > 30, "parts at an angle: " .. turned)
			expect.truthy(fires >= 3, "flames: " .. fires)
		end)

		it("shows the Prehistoric pets, the Lunar Dragon with starry wings and moonfire", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			admin(session, player, "ShowZonePets", { zone = 6 })
			local folder = session:service("Workspace").AdminPets.ZonePets
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
	end)

	describe("Server: admin panel, moving around", function()
		it("turns flight on and off, and a flying admin does not die below the runway", function()
			local session = startServer()
			local player, humanoid, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			expect.truthy((admin(session, player, "SetFlying", { on = true })))
			expect.equal(player:GetAttribute("Flying"), true)
			expect.truthy((admin(session, player, "SetFlySpeed", { speed = 160 })))
			expect.equal(player:GetAttribute("FlySpeed"), 160)

			root.Position = roblox.Vector3.new(80, -200, 300)
			task.wait(0.6)
			expect.equal(humanoid.Health, 100, "still alive while flying")
			admin(session, player, "SetFlying", { on = false })
			expect.equal(player:GetAttribute("Flying"), false)
			task.wait(0.6)
			expect.equal(humanoid.Health, 0, "falls to their doom once they land")
		end)

		it("sets walk speed, and keeps it for the next character", function()
			local session = startServer()
			local player, humanoid = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			expect.truthy((admin(session, player, "SetWalkSpeed", { speed = 64 })))
			expect.equal(humanoid.WalkSpeed, 64)
			expect.falsy((admin(session, player, "SetWalkSpeed", { speed = 63 })))

			local character = roblox.Instance.new("Model")
			local fresh = roblox.Instance.new("Humanoid")
			fresh.Parent = character
			character.Parent = session:service("Workspace")
			player.Character = character
			session:fire(player, "CharacterAdded", character)
			expect.equal(fresh.WalkSpeed, 64)
		end)

		it("teleports to the hub, a zone, the end cliff and another player, taking riders off their egg", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			local other, _, otherRoot = session:addPlayer(2, "Friend")
			session:heartbeat(1 / 60)
			local runway = shared(session).Runway

			expect.truthy((admin(session, player, "Teleport", { to = "Zone", zone = 3 })))
			local position = root.CFrame.Position
			expect.near(position.Z, 1240, 1e-3)
			expect.near(position.Y, runway.surfaceY(1240) + 3.5, 1e-3)
			expect.near(position.X, 0, 1e-3)

			expect.truthy((admin(session, player, "Teleport", { to = "Cliff" })))
			expect.near(root.CFrame.Position.Z, runway.LENGTH - 90, 1e-3)

			expect.truthy((admin(session, player, "Teleport", { to = "Hub" })))
			expect.near(root.CFrame.Position.Z, -runway.HUB_LENGTH / 2, 1e-3)
			expect.near(root.CFrame.Position.Y, 14.5, 1e-3)

			otherRoot.CFrame = roblox.CFrame.new(20, 13, 400)
			local ok, message = admin(session, player, "TeleportToPlayer", { userId = other.UserId })
			expect.truthy(ok, message)
			expect.equal(message, "Teleported to Friend.")
			expect.truthy((root.CFrame.Position - otherRoot.CFrame.Position).Magnitude < 8, "next to them")
			expect.falsy((admin(session, player, "TeleportToPlayer", { userId = 999 })))

			-- A rider is taken off their egg first.
			mount(session, player, root, 1, "Common")
			expect.truthy(session:lastSent("RideStarted", player), "riding")
			admin(session, player, "Teleport", { to = "Hub" })
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("RideEnded", player).args[1], "Dismount")
		end)
	end)

	describe("Server: admin panel, events and the runway cycle", function()
		-- How many eggs drop in a minute.
		local function dropsInAMinute(session)
			session:clearSent()
			session:heartbeat(0.1, 600)
			return #session:sent("EggSpawned", "all")
		end

		it("starts an Egg Avalanche that drops twice the eggs, until stopped", function()
			local normal = dropsInAMinute(startServer())

			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local ok, message = admin(session, player, "StartEvent", { event = "Avalanche" })
			expect.truthy(ok, message)
			local workspace = session:service("Workspace")
			expect.equal(workspace:GetAttribute("ServerEvent"), "Avalanche")
			local announced = false
			for _, entry in session:sent("Announce", "all") do
				announced = announced or entry.args[1]:find("EGG AVALANCHE") ~= nil
			end
			expect.truthy(announced, "announced")
			expect.falsy((admin(session, player, "StartEvent", { event = "Avalanche" })), "already on")
			local avalanche = dropsInAMinute(session)
			expect.truthy(avalanche > normal * 1.5, `{avalanche} eggs in an Avalanche, {normal} normally`)

			expect.truthy((admin(session, player, "StopEvent")))
			expect.equal(workspace:GetAttribute("ServerEvent"), nil)
			expect.falsy((admin(session, player, "StopEvent")), "nothing left to stop")
			ok, message = admin(session, player, "StartEvent", { event = "Titan" })
			expect.falsy(ok)
			expect.equal(message, "The Titan Egg event isn't built yet.")
		end)

		it("closes and reopens the runway on demand, ending an Avalanche at the closure", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(0.1, 100)
			local CycleClock = session:require(session:service("ReplicatedStorage").Shared.CycleClock)
			local workspace = session:service("Workspace")
			admin(session, player, "StartEvent", { event = "Avalanche" })
			expect.falsy((admin(session, player, "OpenRunway")), "already open")

			session:clearSent()
			local ok, message = admin(session, player, "CloseRunway")
			expect.truthy(ok, message)
			session:heartbeat(1 / 60)
			expect.equal(CycleClock.getState(session.clock).phase, "Closed")
			expect.truthy(workspace:GetAttribute("CycleOffset") > 0, "every device is told the new offset")
			expect.truthy(#session:sent("EggRemoved", "all") > 0, "the closure clears the eggs")
			expect.equal(session:lastSent("EggRemoved", "all").args[2], "Closure")
			expect.equal(workspace:GetAttribute("ServerEvent"), nil, "the Avalanche ends at the closure")
			expect.falsy((admin(session, player, "CloseRunway")), "already closed")

			ok = admin(session, player, "OpenRunway")
			expect.truthy(ok)
			session:clearSent()
			session:heartbeat(0.1, 100)
			expect.equal(CycleClock.getState(session.clock).phase, "Open")
			expect.truthy(#session:sent("EggSpawned", "all") > 0, "eggs drop again")
		end)

		it("starts and ends a server luck boost without a purchase", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local ShopService = session:require(server(session).Services.ShopService)
			local ok, message = admin(session, player, "StartLuck", { multiplier = 4 })
			expect.truthy(ok, message)
			expect.equal(message, "Luck x4 for everyone for 15 minutes.")
			local boosts = session:lastSent("LuckChanged", "all").args[1]
			expect.equal(#boosts, 1)
			expect.equal(boosts[1].multiplier, 4)
			expect.falsy((admin(session, player, "StartLuck", { multiplier = 3 })), "only the shop's boosts")

			expect.truthy((admin(session, player, "StopLuck")))
			expect.equal(#ShopService.GetLuckBoosts(), 0)
			expect.equal(#session:lastSent("LuckChanged", "all").args[1], 0, "every device is told")
			expect.falsy((admin(session, player, "StopLuck")), "nothing left to end")
		end)

		it("runs the Egg Avalanche on its own once an hour", function()
			-- Cycle 1010 is an Avalanche cycle (10 of every 20).
			local session = startServer({ clock = 180 * 1010 + 5 })
			session:heartbeat(1 / 60)
			expect.equal(session:service("Workspace"):GetAttribute("ServerEvent"), "Avalanche")
			-- It ends when the runway closes and does not start again in the next cycle.
			session:heartbeat(1, 180)
			expect.equal(session:service("Workspace"):GetAttribute("ServerEvent"), nil)
		end)
	end)

	describe("Server: Model Showroom", function()
		-- Pets and eggs laid out the way tools/export-models does, in folders as Studio's Import Roblox Model adds
		-- them (saved to a model file and read back), near the hub where an import lands.
		local function importModels(session, petParent, eggParent)
			local Shared = session:service("ReplicatedStorage").Shared
			local PetRig = session:require(Shared.PetRig)
			local EggRig = session:require(Shared.EggRig)
			local EggSpec = session:require(Shared.EggSpec)

			local pets = roblox.Instance.new("Folder")
			pets.Name = "Roll an Egg Pets"
			local forest = roblox.Instance.new("Folder")
			forest.Name = "Forest"
			forest.Parent = pets
			for index, kind in { "Fox", "Bear" } do
				local pet = PetRig.build(kind)
				pet:PivotTo(roblox.CFrame.new(index * 12, pet:GetAttribute("GroundOffset"), -20))
				pet.Parent = forest
			end

			local eggs = roblox.Instance.new("Folder")
			eggs.Name = "Roll an Egg Eggs"
			local desert = roblox.Instance.new("Folder")
			desert.Name = "Desert"
			desert.Parent = eggs
			for index, kind in { "Sandy", "Sphinx" } do
				local _, rarity = EggSpec.placeOf(kind)
				local egg = EggRig.build(kind, EggSpec.get(2, rarity))
				egg.Name = kind .. " Egg"
				egg:PivotTo(roblox.CFrame.new(index * 10, 5, -60) * roblox.CFrame.Angles(0, 0, math.pi / 2))
				egg.Parent = desert
			end

			pets = roblox.deserializeModel(roblox.serializeModel({ pets }))[1]
			eggs = roblox.deserializeModel(roblox.serializeModel({ eggs }))[1]
			pets.Parent = petParent
			eggs.Parent = eggParent
			return pets, eggs
		end

		-- The lowest and highest corners of every visible part under `container`, as { x, y, z } tables.
		local function bounds(container)
			local low, high = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
			for _, part in container:GetDescendants() do
				if part:IsA("BasePart") and part.Transparency < 1 then
					local p = part.CFrame.Position
					for axis, value in { p.X, p.Y, p.Z } do
						low[axis] = math.min(low[axis], value)
						high[axis] = math.max(high[axis], value)
					end
				end
			end
			return low, high
		end

		it("moves the imported pets and eggs onto the showroom floor, keeping their layout", function()
			local fox, bear, gap
			local session = startServer({
				before = function(starting)
					local pets =
						importModels(starting, starting:service("Workspace"), starting:service("ServerStorage"))
					fox, bear = pets.Forest.Fox, pets.Forest.Bear
					gap = bear.Root.CFrame.Position - fox.Root.CFrame.Position
				end,
			})
			local Showroom = session:require(session:service("ReplicatedStorage").Shared.Showroom)
			local workspace = session:service("Workspace")
			local showroom = workspace:FindFirstChild("Showroom")
			expect.truthy(showroom, "Workspace.Showroom")
			local pets = showroom:FindFirstChild("Roll an Egg Pets")
			local eggs = showroom:FindFirstChild("Roll an Egg Eggs")
			expect.truthy(pets, "the imported pets are in the showroom")
			expect.truthy(eggs, "the imported eggs too, brought out of ServerStorage")
			expect.equal(workspace:FindFirstChild("Roll an Egg Pets"), nil, "and gone from the hub")

			-- Still laid out the same, and still in one piece.
			expect.truthy(fox.Parent ~= nil and fox:IsDescendantOf(showroom), "the same Fox model")
			local moved = bear.Root.CFrame.Position - fox.Root.CFrame.Position
			expect.truthy((moved - gap).Magnitude < 1e-3, "the Bear is where it was next to the Fox")
			expect.truthy(
				(fox.Body.CFrame.Position - fox.Root.CFrame.Position - fox.Root.Body.C0.Position).Magnitude < 1e-3,
				"the Fox's body is still on its joint"
			)

			-- Pets left of the aisle, eggs right of it, both on the floor at the front line.
			local petLow, petHigh = bounds(pets)
			local eggLow = bounds(eggs)
			expect.truthy(petHigh[1] <= Showroom.X - Showroom.AISLE / 2 + 1e-3, "pets left of the aisle")
			expect.truthy(eggLow[1] >= Showroom.X - 1, "eggs right of the aisle")
			expect.truthy(petLow[2] >= Showroom.FLOOR_Y - 1e-3, "pets on the floor")
			expect.truthy(petLow[3] >= Showroom.Z - 1, "from the front line back")

			local fixtures = showroom.Fixtures
			local floor = fixtures.Floor
			local top = floor.Position.Y + floor.Size.Y / 2
			expect.near(top, Showroom.FLOOR_Y, 1e-3, "floor height")
			expect.truthy(floor.Position.X - floor.Size.X / 2 < petLow[1], "the floor reaches past the pets")
			expect.equal(fixtures.PetsSign.SurfaceGui.TextLabel.Text, "PETS")
			local labels = {}
			for _, child in fixtures:GetChildren() do
				if child.Name == "Label" then
					table.insert(labels, child.BillboardGui.TextLabel.Text)
				end
			end
			table.sort(labels)
			expect.equal(table.concat(labels, ","), "Bear,Fox,Sandy Egg,Sphinx Egg")
			expect.equal(fixtures:FindFirstChild("BuildingSign"), nil, "nothing left to build")
			expect.equal(#session.warnings, 0, "warnings: " .. table.concat(session.warnings, "; "))
		end)

		it("sends visitors there from the admin panel, and back to the hub from the floor", function()
			local session = startServer({
				before = function(starting)
					importModels(starting, starting:service("Workspace"), starting:service("Workspace"))
				end,
			})
			local Showroom = session:require(session:service("ReplicatedStorage").Shared.Showroom)
			local player, _, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local ok, message = admin(session, player, "Teleport", { to = "Showroom" })
			expect.truthy(ok, message)
			expect.equal(message, "Teleported to the Model Showroom.")
			local x, y, z = Showroom.arrivalPoint()
			expect.near(root.CFrame.Position.X, x, 1e-3)
			expect.near(root.CFrame.Position.Y, y + 3.5, 1e-3)
			expect.near(root.CFrame.Position.Z, z, 1e-3)
			expect.truthy(root.CFrame.LookVector.Z > 0.99, "facing the models")

			local pad = session:service("Workspace").Showroom.Fixtures.HubPad
			session:fire(pad.ProximityPrompt, "Triggered", player)
			expect.near(root.CFrame.Position.Z, -shared(session).Runway.HUB_LENGTH / 2, 1e-3, "back at the hub")
		end)

		it("moves the imported folders in the place itself from Studio's command bar", function()
			-- In edit mode nothing runs: just the module, required from the command bar.
			local session = Studio.open(place, { isServer = true })
			local workspace = session:service("Workspace")
			local pets = importModels(session, workspace, workspace)
			local service = session:require(server(session).Services.ShowroomService)
			local Showroom = session:require(session:service("ReplicatedStorage").Shared.Showroom)
			expect.equal(service.MoveImportedModels(), 2)
			expect.equal(pets.Parent, workspace, "left where it was in the Explorer")
			local _, high = bounds(pets)
			expect.truthy(math.abs(high[1] - (Showroom.X - Showroom.AISLE / 2)) < 3, "but standing in the showroom")
			-- Running it again changes nothing.
			local before = pets.Forest.Fox.Root.CFrame.Position
			service.MoveImportedModels()
			expect.truthy((pets.Forest.Fox.Root.CFrame.Position - before).Magnitude < 1e-3, "stays put")
			expect.equal(workspace:FindFirstChild("Showroom"), nil, "and builds nothing else")
		end)

		it("builds every pet and egg from code when none were imported", function()
			local session = startServer()
			local Showroom = session:require(session:service("ReplicatedStorage").Shared.Showroom)
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local fixtures = session:service("Workspace").Showroom.Fixtures
			expect.truthy(fixtures.Floor, "an empty floor to start with")
			expect.truthy(fixtures:FindFirstChild("BuildingSign"), "saying the models are on their way")

			local ok, message = admin(session, player, "Teleport", { to = "Showroom" })
			expect.truthy(ok, message)
			expect.truthy(message:find("being built"), message)
			local service = session:require(server(session).Services.ShowroomService)
			local waited = 0
			while not service.IsReady() and waited < 120 do
				task.wait(0.05)
				waited += 0.05
			end
			expect.truthy(service.IsReady(), "built in time")

			local showroom = session:service("Workspace").Showroom
			local pets = showroom["Pets (built from code)"]
			local eggs = showroom["Eggs (built from code)"]
			local petCount, eggCount = 0, 0
			for _, zone in pets:GetChildren() do
				petCount += #zone:GetChildren()
			end
			for _, zone in eggs:GetChildren() do
				eggCount += #zone:GetChildren()
			end
			expect.equal(petCount, 48)
			expect.equal(eggCount, 48)
			expect.equal(#pets:GetChildren(), 6, "a row per zone")

			-- Forest eggs stand on end on the floor, right of the aisle.
			local leafy = eggs.Forest["Leafy Egg"]
			local low, high = bounds(leafy)
			expect.near(low[2], Showroom.FLOOR_Y, 0.6, "on the floor")
			expect.truthy(high[2] - low[2] > high[1] - low[1], "standing up")
			expect.truthy(low[1] >= Showroom.X, "right of the aisle")
			-- Pets stand on the floor, their root as high above it as it is in the game.
			local fox = pets.Forest.Fox
			expect.near(fox.Root.CFrame.Position.Y, Showroom.FLOOR_Y + fox:GetAttribute("GroundOffset"), 1e-3)

			fixtures = showroom.Fixtures
			expect.equal(fixtures:FindFirstChild("BuildingSign"), nil)
			local labels = 0
			for _, child in fixtures:GetChildren() do
				if child.Name == "Label" then
					labels += 1
				end
			end
			expect.equal(labels, 96, "a name over every model")
		end)
	end)

	describe("Server: map", function()
		it("breaks the runway's banks with gaps and paints the start zone", function()
			local session = startServer()
			local map = session:service("Workspace").Map
			local runway = shared(session).Runway
			for zoneId, zone in shared(session).Zones.List do
				local folder = map[zone.key]
				-- No kerb runs across a gap, and every gap has a warning strip along the runway's edge.
				local gaps = runway.wallGaps(zoneId)
				local strips, kerbLength = 0, 0
				for _, part in folder.Ground:GetChildren() do
					local side = if part.Name == "KerbLeft" then 1 elseif part.Name == "KerbRight" then -1 else nil
					if side then
						local center, half = part.CFrame.Position.Z, part.Size.Z / 2
						kerbLength += half * 2
						expect.truthy(side * part.CFrame.Position.X > runway.WIDTH / 2, `{zone.key} {part.Name} side`)
						for _, gap in gaps do
							if gap.side == side then
								local overlaps = center + half > gap.startZ + 1e-3 and center - half < gap.endZ - 1e-3
								expect.falsy(overlaps, `{zone.key} {part.Name} covers a gap`)
							end
						end
					elseif part.Name == "GapWarning" then
						strips += 1
					end
				end
				expect.equal(strips, #gaps, zone.key .. " warning strips")
				expect.near(kerbLength, 2 * runway.ZONE_LENGTH - #gaps * runway.WALL_GAP_LENGTH, 1e-3)
			end

			local strip = map.StartZone.Strip
			expect.equal(strip.SurfaceGui.TextLabel.Text, "START ZONE")
			-- Lying flat, written face up, its top edge pointing down the runway.
			expect.near(strip.CFrame.LookVector.Y, 1, 1e-6)
			expect.near(strip.CFrame.UpVector.Z, 1, 1e-6)
			expect.truthy(strip.CFrame.Position.Z < 0, "on the hub, before the runway")
		end)

		it("ranks players by eggs claimed on the leaderboard", function()
			local session = startServer()
			local board = session:service("Workspace").Map.Leaderboard
			local display = board.Board.Display
			local rows = display.Rows
			expect.equal(display.Banner.Title.Text, "TOP EGG CLAIMERS")
			expect.truthy(rows.Row1 and rows.Row10, "ten rows")
			expect.equal(display.Empty.Visible, true)

			session:addPlayer(1, "Alice")
			session:addPlayer(2, "Bob")
			session:addPlayer(3, "Cara")
			session:heartbeat(1 / 60)
			dataOf(session, 1).Stats.EggsClaimed = 5
			dataOf(session, 2).Stats.EggsClaimed = 1200
			dataOf(session, 3).Stats.EggsClaimed = 0
			session:require(session:service("ServerScriptService").Server.Services.LeaderboardService).Refresh()

			expect.equal(display.Empty.Visible, false)
			expect.equal(rows.Row1.PlayerName.Text, "Bob")
			expect.equal(rows.Row1.Score.Text, "1.2K 🥚")
			expect.truthy(rows.Row1.Face.Image:match("id=2&"), rows.Row1.Face.Image)
			expect.equal(rows.Row2.PlayerName.Text, "Alice")
			-- Nobody with zero claims is listed.
			expect.equal(rows.Row3.Visible, false)
			expect.equal(#session.warnings, 0, "warnings: " .. table.concat(session.warnings, "; "))
		end)
	end)

	describe("Server: shop", function()
		it("grants Studio test purchases of items with no product ID yet", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			session:fromClient("RequestPurchase", player, "Dollars1")
			expect.equal(dataOf(session, 1).Dollars, 5000)
			local result = purchaseResult(session, player)
			expect.equal(result[1], "Dollars1")
			expect.equal(result[2], true)
			expect.truthy(result[3]:match("^%+%$5K!"), result[3])
			expect.equal(session:lastSent("PlayerStateUpdated", player).args[1].dollars, 5000)
			expect.equal(#session.prompts, 0, "no Roblox prompt")

			task.wait(SHOP_COOLDOWN)
			session:fromClient("RequestPurchase", player, "Stamina1")
			session:heartbeat(1 / 60)
			expect.equal(dataOf(session, 1).MaxStaminaBonus, 500)
			expect.equal(session:lastSent("StaminaChanged", player).args[4], 600)
		end)

		it("boosts the whole server's luck and tells everyone", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			session:fromClient("RequestPurchase", player, "Luck4")

			local boosts = session:lastSent("LuckChanged", "all").args[1]
			expect.equal(#boosts, 1)
			expect.equal(boosts[1].multiplier, 4)
			expect.near(boosts[1].endsAt - session.clock, 15 * 60, 1)
			expect.truthy(session:lastSent("Announce", "all").args[1]:match("luck x4"), "announcement")
			local state = session:remote("GetShopState").OnServerInvoke(player)
			expect.equal(state.luck[1].multiplier, 4)
		end)

		it("refuses items with no product ID in a live game", function()
			local session = startServer({ live = true })
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			session:fromClient("RequestPurchase", player, "Dollars1")
			expect.equal(dataOf(session, 1).Dollars, 0)
			local result = purchaseResult(session, player)
			expect.equal(result[2], false)
			expect.equal(result[3], "This isn't for sale yet.")
		end)

		it("shows Roblox's prompt for items with an ID, and grants each receipt once", function()
			local session = startServer()
			shopConfig(session).ProductsById.Dollars2.productId = 1111
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			session:fromClient("RequestPurchase", player, "Dollars2")
			expect.equal(#session.prompts, 1)
			expect.equal(session.prompts[1].kind, "Product")
			expect.equal(session.prompts[1].id, 1111)
			expect.equal(dataOf(session, 1).Dollars, 0, "nothing granted until Roblox confirms")

			local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
			local receipt = { PlayerId = 1, ProductId = 1111, PurchaseId = "receipt-1" }
			expect.equal(processReceipt(session, receipt), granted)
			expect.equal(dataOf(session, 1).Dollars, 50000)
			-- Roblox can send the same receipt again: nothing more is granted.
			expect.equal(processReceipt(session, receipt), granted)
			expect.equal(dataOf(session, 1).Dollars, 50000)
			expect.truthy(table.find(session.saved.Player_1.PurchaseIds, "receipt-1"), "receipt saved")
		end)

		it("only reports a purchase as granted once it is saved", function()
			local session = startServer()
			shopConfig(session).ProductsById.Dollars2.productId = 1111
			session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			session.savesPaused = true
			local decision
			task.spawn(function()
				decision = processReceipt(session, { PlayerId = 1, ProductId = 1111, PurchaseId = "receipt-2" })
			end)
			expect.equal(decision, nil, "still waiting for the save")
			expect.equal(dataOf(session, 1).Dollars, 50000)

			session.savesPaused = false
			session.profiles.Player_1:Save()
			expect.equal(decision, roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
		end)

		it("leaves receipts for unknown products or absent players for later", function()
			local session = startServer()
			shopConfig(session).ProductsById.Dollars2.productId = 1111
			session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local later = roblox.Enum.ProductPurchaseDecision.NotProcessedYet
			expect.equal(processReceipt(session, { PlayerId = 1, ProductId = 999, PurchaseId = "a" }), later)
			expect.equal(processReceipt(session, { PlayerId = 42, ProductId = 1111, PurchaseId = "b" }), later)
			expect.equal(dataOf(session, 1).Dollars, 0)
		end)

		it("upgrades the pen with dollars or Robux, the same upgrade as the green button", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local plot = session:service("Workspace").Map.Plots.Plot1

			session:fromClient("BuyWithDollars", player, "PenUpgrade")
			local result = purchaseResult(session, player)
			expect.equal(result[2], false)
			expect.equal(result[3], "A bigger pen costs $750: you have $0")
			expect.equal(dataOf(session, 1).PenLevel, 1)

			dataOf(session, 1).Dollars = 3000
			task.wait(SHOP_COOLDOWN)
			session:fromClient("BuyWithDollars", player, "PenUpgrade")
			expect.equal(dataOf(session, 1).PenLevel, 2)
			expect.equal(dataOf(session, 1).Dollars, 2250)
			expect.equal(session:lastSent("PlayerStateUpdated", player).args[1].penLevel, 2)
			expect.equal(session:lastSent("InventoryChanged", player).args[1].penLevel, 2)
			expect.equal(plot:GetAttribute("PenLevel"), 2, "the pen grew")
			expect.equal(purchaseResult(session, player)[2], true)

			-- With Robux (a Studio test purchase here), no dollars are taken.
			task.wait(SHOP_COOLDOWN)
			session:fromClient("RequestPurchase", player, "PenUpgrade")
			expect.equal(dataOf(session, 1).PenLevel, 3)
			expect.equal(dataOf(session, 1).Dollars, 2250)
			expect.equal(plot:GetAttribute("PenLevel"), 3)
			expect.truthy(purchaseResult(session, player)[3]:match("^Bigger pen!"), purchaseResult(session, player)[3])

			dataOf(session, 1).PenLevel = 9
			task.wait(SHOP_COOLDOWN)
			session:fromClient("BuyWithDollars", player, "PenUpgrade")
			expect.equal(purchaseResult(session, player)[2], false)
			expect.equal(dataOf(session, 1).Dollars, 2250)
		end)

		it("unlocks game passes", function()
			local session = startServer()
			local shop = shopConfig(session)
			shop.PassesById.DoubleDollars.gamePassId = 2222
			session.ownedGamePasses[1] = { [2222] = true }
			local player = session:addPlayer(1, "Owner")
			session:heartbeat(1 / 60)
			local service = session:require(session:service("ServerScriptService").Server.Services.ShopService)
			expect.equal(service.OwnsPass(player, "DoubleDollars"), true, "owned before joining")

			local passes = session:lastSent("PlayerStateUpdated", player).args[1].passes
			expect.equal(table.concat(passes, ","), "DoubleDollars")
			session:fromClient("RequestPurchase", player, "DoubleDollars")
			expect.equal(purchaseResult(session, player)[3], "You already own this!")
			expect.equal(#session.prompts, 0)

			-- Bought through Roblox's prompt during the game.
			local buyer = session:addPlayer(2, "Buyer")
			session:heartbeat(1 / 60)
			expect.equal(service.OwnsPass(buyer, "DoubleDollars"), false)
			session:fire(session:service("MarketplaceService"), "PromptGamePassPurchaseFinished", buyer, 2222, true)
			expect.equal(service.OwnsPass(buyer, "DoubleDollars"), true)
		end)

		it("doubles what the pen earns for owners of the x2 Dollars pass", function()
			local session = startServer()
			shopConfig(session).PassesById.DoubleDollars.gamePassId = 2222
			session.ownedGamePasses[1] = { [2222] = true }
			local owner = session:addPlayer(1, "Owner")
			local other = session:addPlayer(2, "Other")
			session:heartbeat(1 / 60)
			admin(session, owner, "GivePet", { pet = "Squirrel" })
			admin(session, other, "GivePet", { pet = "Squirrel" })
			local ownerIncome = session:lastSent("InventoryChanged", owner).args[1].income
			local otherIncome = session:lastSent("InventoryChanged", other).args[1].income
			expect.truthy(otherIncome > 0, "a pet in the pen earns")
			expect.equal(ownerIncome, otherIncome * 2)
			session:heartbeat(0.5)
			expect.equal(session:lastSent("DollarsChanged", owner).args[2], ownerIncome)
		end)

		it("doubles Max Stamina with each purchase, up to x1024", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			session:fromClient("RequestPurchase", player, "StaminaDoubling")
			session:heartbeat(1 / 60)
			expect.equal(dataOf(session, 1).StaminaMultiplier, 2)
			expect.equal(session:lastSent("StaminaChanged", player).args[4], 200)
			expect.equal(session:lastSent("PlayerStateUpdated", player).args[1].staminaMultiplier, 2)
			expect.truthy(purchaseResult(session, player)[3]:match("^Max Stamina doubled! Now x2%."), "message")

			-- Max Stamina bought in packs is doubled too.
			dataOf(session, 1).MaxStaminaBonus = 400
			dataOf(session, 1).StaminaMultiplier = 512
			task.wait(SHOP_COOLDOWN)
			session:fromClient("RequestPurchase", player, "StaminaDoubling")
			session:heartbeat(1 / 60)
			expect.equal(dataOf(session, 1).StaminaMultiplier, 1024)
			expect.equal(session:lastSent("StaminaChanged", player).args[4], 500 * 1024)

			task.wait(SHOP_COOLDOWN)
			session:fromClient("RequestPurchase", player, "StaminaDoubling")
			expect.equal(purchaseResult(session, player)[2], false)
			expect.equal(dataOf(session, 1).StaminaMultiplier, 1024)
		end)

		it("sells each stamina doubling as its own developer product", function()
			local session = startServer()
			local shop = shopConfig(session)
			shop.StaminaDoublings[2].productId = 4002
			shop.StaminaDoublings[4].productId = 4004
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			session:fromClient("RequestPurchase", player, "StaminaDoubling")
			expect.equal(session.prompts[1].id, 4002)
			local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
			expect.equal(processReceipt(session, { PlayerId = 1, ProductId = 4002, PurchaseId = "d1" }), granted)
			expect.equal(dataOf(session, 1).StaminaMultiplier, 2)

			task.wait(SHOP_COOLDOWN)
			session:fromClient("RequestPurchase", player, "StaminaDoubling")
			expect.equal(session.prompts[2].id, 4004, "the next step's product")
		end)

		it("starts players at the stamina they have doubled to", function()
			local session = startServer()
			session.saved.Player_1 = { StaminaMultiplier = 8, MaxStaminaBonus = 50 }
			local player = session:addPlayer(1, "Returning")
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("StaminaChanged", player).args[4], 150 * 8)
		end)

		it("ignores requests for things that are not for sale", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			session:fromClient("RequestPurchase", player, 5)
			session:fromClient("RequestPurchase", player, "FreeDollars")
			session:fromClient("BuyWithDollars", player, "Dollars1")
			expect.equal(#session:sent("PurchaseResult", player), 0)
			expect.equal(#session.prompts, 0)
			expect.equal(dataOf(session, 1).Dollars, 0)
		end)
	end)

	describe("Server: hub stations", function()
		local Vector3 = roblox.Vector3

		local function layoutOf(session)
			return session:require(session:service("ReplicatedStorage").Shared.HubLayout)
		end

		local function findDescendant(root, name)
			for _, descendant in root:GetDescendants() do
				if descendant.Name == name then
					return descendant
				end
			end
			return nil
		end

		-- Calls a server function as the player, then lets one frame pass so stamina changes are sent.
		local function invoke(session, name, player, ...)
			local results = table.pack(session:remote(name).OnServerInvoke(player, ...))
			session:heartbeat(1 / 60)
			return table.unpack(results, 1, results.n)
		end

		local function addEggs(data, zone, rarity, kind, count)
			for index = 1, count do
				table.insert(
					data.Eggs,
					{ uid = `{kind}{index}`, zone = zone, rarity = rarity, kind = kind, claimedAt = 0 }
				)
			end
		end

		it("builds the Trails stall, the Sell stall and the fuse machine, each with a prompt", function()
			local session = startServer()
			local layout = layoutOf(session)
			local stations = session:service("Workspace").Map.Stations
			for key, station in layout.STATIONS do
				local model = stations:FindFirstChild(key)
				expect.truthy(model, key)
				local prompt = findDescendant(model, "Prompt")
				expect.truthy(prompt and prompt:IsA("ProximityPrompt"), key .. " prompt")
				expect.equal(prompt:GetAttribute("Station"), key)
				expect.equal(prompt.ObjectText, station.name)
				expect.equal(prompt.MaxActivationDistance, layout.STATION_REACH)
				expect.equal(prompt.HoldDuration, 0)
				local at = prompt.Parent.CFrame.Position
				local dx, dz = at.X - station.x, at.Z - station.z
				expect.truthy(math.sqrt(dx * dx + dz * dz) < layout.STATION_RADIUS, key .. " prompt position")
			end
			expect.equal(findDescendant(stations.Trails, "NameTag").Frame.TextLabel.Text, "TRAILS")
			expect.equal(findDescendant(stations.Sell, "NameTag").Frame.TextLabel.Text, "SELL")
			expect.equal(findDescendant(stations.Fuse, "NameTag").Frame.TextLabel.Text, "FUSE")
			-- The stalls face the middle of the plaza.
			expect.truthy(stations.Trails.Counter.CFrame.LookVector.X > 0.99, "Trails faces the middle")
			expect.truthy(stations.Sell.Counter.CFrame.LookVector.X < -0.99, "Sell faces the middle")
		end)

		it("walls in the hub, leaving only the runway open", function()
			local session = startServer()
			local walls = session:service("Workspace").Map.HubWalls
			expect.equal(#walls:GetChildren(), 5)
			for _, wall in walls:GetChildren() do
				expect.equal(wall.Transparency, 1, wall.Name)
				expect.equal(wall.CanCollide, true, wall.Name)
			end
			local left, right = walls.FrontLeft.CFrame.Position, walls.FrontRight.CFrame.Position
			local gap = (right.X - walls.FrontRight.Size.X / 2) - (left.X + walls.FrontLeft.Size.X / 2)
			expect.near(gap, shared(session).Runway.WIDTH, 1e-6)
		end)

		it("rings the hub with low-poly mountains that nothing collides with", function()
			local session = startServer()
			local layout = layoutOf(session)
			local scenery = session:service("Workspace").Map.Scenery
			local models = scenery.Mountains:GetChildren()
			expect.equal(#models, #layout.MOUNTAINS)
			local wedges, triangles = 0, 0
			for _, model in models do
				for _, part in model:GetChildren() do
					expect.truthy(part:IsA("WedgePart"), part.ClassName)
					expect.equal(part.CanCollide, false)
					expect.equal(part.Anchored, true)
					wedges += 1
				end
			end
			for _, mountain in layout.MOUNTAINS do
				triangles += #layout.mountainTriangles(mountain)
			end
			-- Two wedges a face (a sliver is occasionally skipped).
			expect.truthy(wedges <= triangles * 2 and wedges >= triangles * 1.9, `{wedges} wedges, {triangles} faces`)
			-- The outer ground sits just below the hub, so the two never flicker.
			local outer = scenery.OuterGround
			local top = outer.CFrame.Position.Y + outer.Size.Y / 2
			local base = shared(session).Runway.BASE_Y
			expect.truthy(top < base and top > base - 1, "outer ground")
		end)

		it("draws each mountain face exactly with two wedges", function()
			local session = startServer()
			local Parts = session:require(session:service("ServerScriptService").Server.Map.Parts)
			local cases = {
				{ Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(3, 8, 0) },
				{ Vector3.new(0, 0, 0), Vector3.new(4, 0, 0), Vector3.new(0, 3, 0) },
				{ Vector3.new(5, 2, -3), Vector3.new(-40, 60, 12), Vector3.new(30, 15, 44) },
				{ Vector3.new(-200, -30, 80), Vector3.new(-150, 120, 60), Vector3.new(-120, -30, 150) },
			}
			for index, case in cases do
				local a, b, c = case[1], case[2], case[3]
				local folder = roblox.Instance.new("Folder")
				Parts.triangle(folder, a, b, c, roblox.Color3.new(1, 1, 1))
				local wedges = folder:GetChildren()
				expect.equal(#wedges, 2, "wedges for case " .. index)
				local corners = {}
				local area = 0
				for _, wedge in wedges do
					local h, l = wedge.Size.Y / 2, wedge.Size.Z / 2
					for _, offset in { Vector3.new(0, -h, -l), Vector3.new(0, -h, l), Vector3.new(0, h, l) } do
						table.insert(corners, wedge.CFrame * offset)
					end
					area += 2 * h * l
				end
				local expected = (b - a):Cross(c - a).Magnitude / 2
				expect.near(area, expected, expected * 1e-5, "area of case " .. index)
				for _, point in { a, b, c } do
					local found = false
					for _, corner in corners do
						if (corner - point).Magnitude < 0.01 then
							found = true
						end
					end
					expect.truthy(found, "a corner of case " .. index .. " is drawn")
				end
			end
		end)

		it("tells a joining player their trails", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local trails = session:lastSent("TrailsUpdated", player)
			expect.equal(#trails.args[1], 0)
			expect.equal(trails.args[2], "")
			local state = session:remote("GetTrails").OnServerInvoke(player)
			expect.equal(#state.owned, 0)
			expect.equal(state.equipped, "")
		end)

		it("sells eggs for dollars", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			addEggs(data, 1, "Common", "Leafy", 3)
			addEggs(data, 1, "Rare", "Toadstool", 1)
			session:clearSent()

			local sold, dollars = invoke(session, "SellEggs", player, "Leafy", 2)
			expect.equal(sold, 2)
			expect.equal(dollars, 50)
			expect.equal(data.Dollars, 50)
			expect.equal(#data.Eggs, 2)
			expect.equal(data.Stats.EggsSold, 2)
			expect.equal(session:lastSent("DollarsChanged", player).args[1], 50)
			local eggs = session:lastSent("InventoryChanged", player).args[1].eggs
			expect.equal(#eggs, 2)
		end)

		it("ignores nonsense sell requests", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			addEggs(data, 1, "Common", "Leafy", 3)
			local nonsense = {
				{ 1, 1 },
				{ "Leafy", 1.5 },
				{ "Leafy", -3 },
				{ "Leafy", 0 / 0 },
				{ "Leafy", math.huge },
				{ "Leafy", nil },
				{ string.rep("x", 500), 1 },
				{ {}, {} },
			}
			for _, args in nonsense do
				session:heartbeat(0.3)
				local sold, dollars = invoke(session, "SellEggs", player, args[1], args[2])
				expect.equal(sold, 0)
				expect.equal(dollars, 0)
			end
			expect.equal(#data.Eggs, 3)
			expect.equal(data.Dollars, 0)
		end)

		it("buys and equips trails, which boost Max Stamina and stream behind the character", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			data.Dollars = 1000

			local ok, result = invoke(session, "BuyTrail", player, "Leaf")
			expect.equal(ok, true)
			expect.equal(result, "BoughtAndEquipped")
			expect.equal(data.Dollars, 900)
			expect.equal(session:lastSent("DollarsChanged", player).args[1], 900)
			expect.near(session:lastSent("StaminaChanged", player).args[4], 120)
			local trails = session:lastSent("TrailsUpdated", player)
			expect.equal(trails.args[1][1], "Leaf")
			expect.equal(trails.args[2], "Leaf")
			local top = root:FindFirstChild("StaminaTrailTop")
			expect.truthy(top and top.Trail, "trail on the character")
			expect.equal(top.Trail.Attachment1, root.StaminaTrailBottom)

			-- Requests closer together than 0.2 s are refused.
			ok, result = invoke(session, "BuyTrail", player, "Sunbeam")
			expect.equal(ok, false)
			expect.equal(result, "TooFast")

			session:heartbeat(0.3)
			ok = invoke(session, "BuyTrail", player, "Sunbeam")
			expect.equal(ok, true)
			expect.near(session:lastSent("StaminaChanged", player).args[4], 150)
			local trailCount = 0
			for _, child in root:GetChildren() do
				if child.Name == "StaminaTrailTop" then
					trailCount += 1
				end
			end
			expect.equal(trailCount, 1, "the old trail is replaced")

			session:heartbeat(0.3)
			ok, result = invoke(session, "EquipTrail", player, "Leaf")
			expect.equal(ok, true)
			expect.equal(result, "Equipped")
			expect.near(session:lastSent("StaminaChanged", player).args[4], 120)

			session:heartbeat(0.3)
			expect.equal(select(2, invoke(session, "EquipTrail", player, "Frost")), "NotOwned")
			session:heartbeat(0.3)
			expect.equal(select(2, invoke(session, "BuyTrail", player, "Rainbow")), "NotEnoughDollars")
			expect.equal(select(2, invoke(session, "BuyTrail", player, 42)), "Invalid")
			expect.equal(data.Dollars, 400)
		end)

		it("stacks a trail's boost on Max Stamina bought in the shop", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			data.Dollars = 100
			invoke(session, "BuyTrail", player, "Leaf")
			session:fromClient("RequestPurchase", player, "Stamina1")
			session:heartbeat(1 / 60)
			expect.near(session:lastSent("StaminaChanged", player).args[4], 600 * 1.2)
		end)

		it("keeps the trail's boost after respawning and rejoining", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			session.profiles.Player_1.Data.Dollars = 100
			invoke(session, "BuyTrail", player, "Leaf")

			-- A new character gets the trail too.
			local character = roblox.Instance.new("Model")
			roblox.Instance.new("Humanoid").Parent = character
			local root = roblox.Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Parent = character
			character.Parent = session:service("Workspace")
			player.Character = character
			session:fire(player, "CharacterAdded", character)
			expect.truthy(root:FindFirstChild("StaminaTrailTop"), "trail on the new character")

			-- Leave and come back: the boost is there from the start.
			session:fire(session:service("Players"), "PlayerRemoving", player)
			player.Parent = nil
			local again = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			expect.near(session:lastSent("StaminaChanged", again).args[4], 120)
			expect.equal(session:lastSent("TrailsUpdated", again).args[2], "Leaf")
		end)
	end)

	describe("Server: settings", function()
		it("saves only valid settings and hands them back with defaults", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			session:fromClient("SaveSettings", player, {
				MusicVolume = 0.456,
				ShowMyPets = false,
				Vibration = "yes",
				Junk = 5,
			})
			session:fromClient("SaveSettings", player, "not a table")
			local saved = dataOf(session, 1).Settings
			expect.equal(saved.MusicVolume, 0.46)
			expect.equal(saved.ShowMyPets, false)
			expect.equal(saved.Vibration, nil)
			expect.equal(saved.Junk, nil)

			local values = session:remote("GetSettings").OnServerInvoke(player)
			expect.equal(values.MusicVolume, 0.46)
			expect.equal(values.ShowMyPets, false)
			expect.equal(values.Vibration, true)
		end)
	end)
end
