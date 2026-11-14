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

	-- Drops an egg of a chosen kind and returns its EggSpawned message.
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
			local hub = map.Hub
			expect.truthy(hub:IsA("Model"), "Hub is a model")
			expect.equal(hub.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Persistent)
			expect.truthy(hub.Ground:IsA("Part"))
			expect.truthy(hub.Spawn:IsA("SpawnLocation"))
			expect.equal(#hub.Pens:GetChildren(), 8, "pens")
			for _, zoneName in { "Forest", "Desert", "Snow", "Ocean", "Volcano" } do
				local zone = map:FindFirstChild(zoneName)
				expect.truthy(zone, zoneName)
				expect.truthy(zone.Ground:IsA("Part"))
				expect.equal(#zone.Sign:GetChildren(), 2, zoneName .. " sign faces")
			end
			-- The Forest slab starts level with the hub and ends 24 studs lower (600 studs at a 4% slope).
			local runway = shared(session).Runway
			expect.near(hub.Ground.Position.Y + hub.Ground.Size.Y / 2, runway.BASE_Y)
			expect.near(map.Forest.Ground.Size.X, runway.WIDTH)
			expect.near(map.Forest.Ground.Size.Z, 600 / math.cos(math.atan(0.04)), 1e-3)
			expect.equal(map.Desert.Sign.SurfaceGui.TextLabel.Text, "DESERT")
			expect.equal(session:service("Players").RespawnTime, 2)
			expect.truthy(session:service("Lighting"):FindFirstChildOfClass("Atmosphere"), "haze")
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
			expect.equal(#snapshot.inventory, 0)
			expect.equal(snapshot.coins, 0)
			expect.equal(snapshot.trails.equipped, "")
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

			local removed
			for _, entry in session:sent("EggRemoved", "all") do
				if entry.args[1] == egg.id then
					removed = entry
				end
			end
			expect.equal(removed.args[2], "Claimed")
			expect.equal(removed.args[3], 1, "claimed by")
			local groups = session:lastSent("InventoryUpdated", player).args[1]
			expect.equal(#groups, 1)
			expect.equal(groups[1].zone, 1)
			expect.equal(groups[1].rarity, "Common")
			expect.equal(groups[1].count, 1)

			local data = session.profiles.Player_1.Data
			expect.equal(#data.Eggs, 1)
			expect.equal(data.Eggs[1].zone, 1)
			expect.equal(data.Eggs[1].rarity, "Common")
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
			local egg = dropEgg(session, 3, "Common")

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

			-- Steer 4 studs toward the middle, so the move never runs into the edge of the runway.
			local target = egg.lateral + (if egg.lateral > 0 then -4 else 4)
			session:heartbeat(0.5)
			session:fromClient("RideLateral", player, target)
			local relayed = session:lastSent("EggLateral", "all")
			expect.truthy(relayed, "EggLateral")
			expect.equal(relayed.args[1], egg.id)
			expect.near(relayed.args[2], target, 1e-6)

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

	describe("Server: hub", function()
		local Instance, CFrame, Enum = roblox.Instance, roblox.CFrame, roblox.Enum
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

		-- Whether a world point is inside a part's box.
		local function contains(part, point)
			local localPoint = part.CFrame:PointToObjectSpace(point)
			local half = part.Size / 2
			return math.abs(localPoint.X) <= half.X
				and math.abs(localPoint.Y) <= half.Y
				and math.abs(localPoint.Z) <= half.Z
		end

		it("builds the Trails stall, the Sell stall and the fuse machine, each with a prompt", function()
			local session = startServer()
			local layout = layoutOf(session)
			local stations = session:service("Workspace").Map.Hub.Stations
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
			expect.equal(findDescendant(stations.Fuse, "Mystery").TextLabel.Text, "?")
			-- The stalls face the middle of the plaza.
			expect.truthy(stations.Trails.Counter.CFrame.LookVector.X > 0.99, "Trails faces the middle")
			expect.truthy(stations.Sell.Counter.CFrame.LookVector.X < -0.99, "Sell faces the middle")
		end)

		it("paints START ZONE on the pad, readable from the hub", function()
			local session = startServer()
			local layout = layoutOf(session)
			local startZone = session:service("Workspace").Map.Hub.StartZone
			expect.near(startZone.Pad.Position.Z, layout.START_ZONE.z)
			expect.near(startZone.Pad.Size.X, shared(session).Runway.WIDTH)
			-- The label lies on its back: its Front face (where the text is) points at the sky, and the top of the
			-- text points down the runway, so it reads the right way round for a player walking out of the hub.
			local label = startZone.Label
			expect.near(label.CFrame.LookVector.Y, 1, 1e-6)
			expect.near(label.CFrame.UpVector.Z, 1, 1e-6)
			expect.equal(label.SurfaceGui.Face, Enum.NormalId.Front)
			expect.equal(label.SurfaceGui.TextLabel.Text, "START ZONE")
		end)

		it("walls in the hub, leaving only the runway open", function()
			local session = startServer()
			local walls = session:service("Workspace").Map.Hub.Walls
			expect.equal(#walls:GetChildren(), 5)
			for _, wall in walls:GetChildren() do
				expect.equal(wall.Transparency, 1, wall.Name)
				expect.equal(wall.CanCollide, true, wall.Name)
			end
			local left, right = walls.FrontLeft, walls.FrontRight
			local gap = (right.Position.X - right.Size.X / 2) - (left.Position.X + left.Size.X / 2)
			expect.near(gap, shared(session).Runway.WIDTH, 1e-6)
			-- The spawn is on the hub, facing the runway.
			local spawn = session:service("Workspace").Map.Hub.Spawn
			expect.near(spawn.CFrame.Position.Z, layoutOf(session).SPAWN.z)
			expect.near(spawn.CFrame.LookVector.Z, 1, 1e-6)
		end)

		it("fences every pen and leaves its gate open toward the plaza", function()
			local session = startServer()
			local layout = layoutOf(session)
			local pens = session:service("Workspace").Map.Hub.Pens
			for _, pen in layout.PENS do
				local model = pens["Pen" .. pen.index]
				expect.equal(model:GetAttribute("PenIndex"), pen.index)
				expect.near(model.Floor.Position.X, pen.x)
				expect.near(model.Floor.Position.Z, pen.z)
				expect.truthy(#model:GetChildren() > 30, "fence parts")
				-- The sign over the gate faces out of the pen.
				expect.near(model.Sign.CFrame.LookVector.X, pen.gate.x, 1e-6)
				expect.near(model.Sign.CFrame.LookVector.Z, pen.gate.z, 1e-6)
				expect.equal(model.Sign:FindFirstChildOfClass("SurfaceGui").TextLabel.Text, `PEN {pen.index}`)

				-- Nothing blocks the gateway at walking height.
				local gateX = pen.x + pen.gate.x * pen.sizeX / 2
				local gateZ = pen.z + pen.gate.z * pen.sizeZ / 2
				local along = Vector3.new(math.abs(pen.gate.z), 0, math.abs(pen.gate.x))
				for offset = -5, 5, 1 do
					for _, height in { 1, 2.5, 4 } do
						local point = Vector3.new(gateX, shared(session).Runway.BASE_Y + height, gateZ) + along * offset
						for _, part in model:GetChildren() do
							if part:IsA("BasePart") and part.Name ~= "Sign" and part.Name ~= "Floor" then
								expect.falsy(contains(part, point), `pen {pen.index} gate blocked by a {part.Name}`)
							end
						end
					end
				end
				-- And the rest of the side is fenced.
				local fenced = Vector3.new(gateX, shared(session).Runway.BASE_Y + 1.7, gateZ) + along * 12
				local blocked = false
				for _, part in model:GetChildren() do
					if part:IsA("BasePart") and part.Name == "Rail" and contains(part, fenced) then
						blocked = true
					end
				end
				expect.truthy(blocked, `pen {pen.index} fence beside the gate`)
			end
		end)

		it("rings the hub with low-poly mountains that nothing collides with", function()
			local session = startServer()
			local layout = layoutOf(session)
			local scenery = session:service("Workspace").Map.Scenery
			local models = scenery.Mountains:GetChildren()
			expect.equal(#models, #layout.MOUNTAINS)
			local wedges, triangles = 0, 0
			for _, model in models do
				expect.equal(model.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
				for _, part in model:GetChildren() do
					expect.truthy(part:IsA("WedgePart"), part.ClassName)
					expect.equal(part.CanCollide, false)
					expect.equal(part.CanQuery, false)
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
			local top = outer.Position.Y + outer.Size.Y / 2
			expect.truthy(
				top < shared(session).Runway.BASE_Y and top > shared(session).Runway.BASE_Y - 1,
				"outer ground"
			)
		end)

		it("draws each mountain face exactly with two wedges", function()
			local session = startServer()
			local Build = session:require(session:service("ServerScriptService").Server.Map.Build)
			local cases = {
				{ Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(3, 8, 0) },
				{ Vector3.new(0, 0, 0), Vector3.new(4, 0, 0), Vector3.new(0, 3, 0) },
				{ Vector3.new(5, 2, -3), Vector3.new(-40, 60, 12), Vector3.new(30, 15, 44) },
				{ Vector3.new(-200, -30, 80), Vector3.new(-150, 120, 60), Vector3.new(-120, -30, 150) },
			}
			for index, case in cases do
				local a, b, c = case[1], case[2], case[3]
				local folder = Instance.new("Folder")
				Build.triangle(folder, a, b, c, roblox.Color3.new(1, 1, 1))
				local wedges = folder:GetChildren()
				expect.equal(#wedges, 2, "wedges for case " .. index)

				-- The corners of each wedge's triangular side face, at the middle of its thickness.
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
				-- Every wedge corner is a corner of the triangle or lies on its longest edge.
				local longest = { a, b }
				for _, edge in { { b, c }, { a, c } } do
					if (edge[2] - edge[1]).Magnitude > (longest[2] - longest[1]).Magnitude then
						longest = edge
					end
				end
				for _, corner in corners do
					local onEdge = ((corner - longest[1]):Cross(longest[2] - longest[1])).Magnitude
						/ (longest[2] - longest[1]).Magnitude
					local isCorner = (corner - a).Magnitude < 0.01
						or (corner - b).Magnitude < 0.01
						or (corner - c).Magnitude < 0.01
					expect.truthy(isCorner or onEdge < 0.01, "stray wedge corner in case " .. index)
				end
			end
		end)
	end)

	describe("Server: shops", function()
		local Instance = roblox.Instance

		-- Calls a server function as the player, then lets one frame pass so stamina changes are sent.
		local function invoke(session, name, player, ...)
			local results = table.pack(session:remote(name).OnServerInvoke(player, ...))
			session:heartbeat(1 / 60)
			return table.unpack(results, 1, results.n)
		end

		local function addEggs(data, zone, rarity, count)
			for index = 1, count do
				table.insert(data.Eggs, { uid = `{zone}{rarity}{index}`, zone = zone, rarity = rarity, claimedAt = 0 })
			end
		end

		it("tells a joining player their coins, eggs and trails", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("CoinsChanged", player).args[1], 0)
			expect.equal(#session:lastSent("InventoryUpdated", player).args[1], 0)
			local trails = session:lastSent("TrailsUpdated", player)
			expect.equal(#trails.args[1], 0)
			expect.equal(trails.args[2], "")
		end)

		it("sells eggs for coins", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			addEggs(data, 1, "Common", 3)
			addEggs(data, 1, "Rare", 1)
			session:clearSent()

			local sold, coins = invoke(session, "SellEggs", player, 1, "Common", 2)
			expect.equal(sold, 2)
			expect.equal(coins, 50)
			expect.equal(data.Coins, 50)
			expect.equal(#data.Eggs, 2)
			expect.equal(data.Stats.EggsSold, 2)
			expect.equal(session:lastSent("CoinsChanged", player).args[1], 50)
			local groups = session:lastSent("InventoryUpdated", player).args[1]
			expect.equal(#groups, 2)
			expect.equal(groups[1].count, 1)
			expect.equal(groups[2].rarity, "Rare")
		end)

		it("ignores nonsense sell requests", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			addEggs(data, 1, "Common", 3)
			local nonsense = {
				{ "1", "Common", 1 },
				{ 1, "Shiny", 1 },
				{ 1, 5, 1 },
				{ 1, "Common", 1.5 },
				{ 1, "Common", -3 },
				{ 1, "Common", 0 / 0 },
				{ 1, "Common", math.huge },
				{ 0 / 0, "Common", 1 },
				{ 1, "Common", nil },
				{ {}, {}, {} },
			}
			for _, args in nonsense do
				session:heartbeat(0.3)
				local sold, coins = invoke(session, "SellEggs", player, args[1], args[2], args[3])
				expect.equal(sold, 0)
				expect.equal(coins, 0)
			end
			expect.equal(#data.Eggs, 3)
			expect.equal(data.Coins, 0)
		end)

		it("buys and equips trails, which boost Max Stamina and stream behind the character", function()
			local session = startServer()
			local player, _, root = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local data = session.profiles.Player_1.Data
			data.Coins = 1000

			local ok, result = invoke(session, "BuyTrail", player, "Leaf")
			expect.equal(ok, true)
			expect.equal(result, "BoughtAndEquipped")
			expect.equal(data.Coins, 900)
			expect.equal(session:lastSent("CoinsChanged", player).args[1], 900)
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
			expect.equal(select(2, invoke(session, "BuyTrail", player, "Rainbow")), "NotEnoughCoins")
			expect.equal(select(2, invoke(session, "BuyTrail", player, 42)), "Invalid")
			expect.equal(data.Coins, 400)
		end)

		it("keeps the trail's boost after respawning and rejoining", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			session.profiles.Player_1.Data.Coins = 100
			invoke(session, "BuyTrail", player, "Leaf")

			-- A new character gets the trail too.
			local character = Instance.new("Model")
			Instance.new("Humanoid").Parent = character
			local root = Instance.new("Part")
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

		it("give coins in Studio", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			session:fromClient("DevCommand", player, "AddCoins")
			expect.equal(session.profiles.Player_1.Data.Coins, 10000)
			expect.equal(session:lastSent("CoinsChanged", player).args[1], 10000)
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
			expect.truthy(session:lastSent("Announce", "all"), "announcement")
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
