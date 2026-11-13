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

			-- Steer toward the centre line: eggs land at a random spot, maybe too close to a wall to go further out.
			local step = if egg.lateral > 0 then -4 else 4
			session:heartbeat(0.5)
			session:fromClient("RideLateral", player, egg.lateral + step)
			local relayed = session:lastSent("EggLateral", "all")
			expect.truthy(relayed, "EggLateral")
			expect.equal(relayed.args[1], egg.id)
			expect.near(relayed.args[2], egg.lateral + step, 1e-6)

			-- Reports arriving faster than 30 a second are dropped.
			session:fromClient("RideLateral", player, egg.lateral + step * 1.25)
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

	describe("Server: map", function()
		it("walls the runway and paints the start zone", function()
			local session = startServer()
			local map = session:service("Workspace").Map
			local width = shared(session).Runway.WIDTH
			local runway = shared(session).Runway
			local slope = math.cos(math.atan(runway.SLOPE))
			for zoneId, zoneName in { "Forest", "Desert", "Snow", "Ocean", "Volcano" } do
				local zone = map[zoneName]
				local left, right = zone.WallLeft1.CFrame.Position, zone.WallRight1.CFrame.Position
				expect.truthy(left.X > width / 2, zoneName .. " left wall")
				expect.truthy(right.X < -width / 2, zoneName .. " right wall")
				expect.truthy(left.Y > zone.Ground.CFrame.Position.Y, zoneName .. " wall stands up")

				-- No wall covers a gap, and every gap has a warning strip along the runway's edge.
				local gaps = runway.wallGaps(zoneId)
				local strips, wallLength = 0, 0
				for _, part in zone:GetChildren() do
					local side = if part.Name:match("Left") then 1 elseif part.Name:match("Right") then -1 else nil
					if part.Name:match("^Wall") then
						local center, half = part.CFrame.Position.Z, part.Size.Z * slope / 2
						wallLength += half * 2
						for _, gap in gaps do
							if gap.side == side then
								-- Half a stud of slack: a sloped wall's centre sits a little down-runway of its footprint.
								local overlaps = center + half > gap.startZ + 0.5 and center - half < gap.endZ - 0.5
								expect.falsy(overlaps, `{zoneName} {part.Name} covers a gap`)
							end
						end
					elseif part.Name:match("^GapWarning") then
						strips += 1
					end
				end
				expect.equal(strips, #gaps, zoneName .. " warning strips")
				expect.near(wallLength, 2 * runway.ZONE_LENGTH - #gaps * runway.WALL_GAP_LENGTH, 1e-3)
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

			session:fromClient("RequestPurchase", player, "Coins1")
			expect.equal(dataOf(session, 1).Coins, 5000)
			local result = purchaseResult(session, player)
			expect.equal(result[1], "Coins1")
			expect.equal(result[2], true)
			expect.truthy(result[3]:match("^%+5K Coins!"), result[3])
			expect.equal(session:lastSent("PlayerStateUpdated", player).args[1].coins, 5000)
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
			session:fromClient("RequestPurchase", player, "Coins1")
			expect.equal(dataOf(session, 1).Coins, 0)
			local result = purchaseResult(session, player)
			expect.equal(result[2], false)
			expect.equal(result[3], "This isn't for sale yet.")
		end)

		it("shows Roblox's prompt for items with an ID, and grants each receipt once", function()
			local session = startServer()
			shopConfig(session).ProductsById.Coins2.productId = 1111
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			session:fromClient("RequestPurchase", player, "Coins2")
			expect.equal(#session.prompts, 1)
			expect.equal(session.prompts[1].kind, "Product")
			expect.equal(session.prompts[1].id, 1111)
			expect.equal(dataOf(session, 1).Coins, 0, "nothing granted until Roblox confirms")

			local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
			local receipt = { PlayerId = 1, ProductId = 1111, PurchaseId = "receipt-1" }
			expect.equal(processReceipt(session, receipt), granted)
			expect.equal(dataOf(session, 1).Coins, 50000)
			-- Roblox can send the same receipt again: nothing more is granted.
			expect.equal(processReceipt(session, receipt), granted)
			expect.equal(dataOf(session, 1).Coins, 50000)
			expect.truthy(table.find(session.saved.Player_1.PurchaseIds, "receipt-1"), "receipt saved")
		end)

		it("only reports a purchase as granted once it is saved", function()
			local session = startServer()
			shopConfig(session).ProductsById.Coins2.productId = 1111
			session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			session.savesPaused = true
			local decision
			task.spawn(function()
				decision = processReceipt(session, { PlayerId = 1, ProductId = 1111, PurchaseId = "receipt-2" })
			end)
			expect.equal(decision, nil, "still waiting for the save")
			expect.equal(dataOf(session, 1).Coins, 50000)

			session.savesPaused = false
			session.profiles.Player_1:Save()
			expect.equal(decision, roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
		end)

		it("leaves receipts for unknown products or absent players for later", function()
			local session = startServer()
			shopConfig(session).ProductsById.Coins2.productId = 1111
			session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)
			local later = roblox.Enum.ProductPurchaseDecision.NotProcessedYet
			expect.equal(processReceipt(session, { PlayerId = 1, ProductId = 999, PurchaseId = "a" }), later)
			expect.equal(processReceipt(session, { PlayerId = 42, ProductId = 1111, PurchaseId = "b" }), later)
			expect.equal(dataOf(session, 1).Coins, 0)
		end)

		it("upgrades the pen with coins, up to the top level", function()
			local session = startServer()
			local player = session:addPlayer(1, "Tester")
			session:heartbeat(1 / 60)

			session:fromClient("BuyWithCoins", player, "PenUpgrade")
			local result = purchaseResult(session, player)
			expect.equal(result[2], false)
			expect.equal(result[3], "You need 2.5K more coins.")
			expect.equal(dataOf(session, 1).PenLevel, 1)

			dataOf(session, 1).Coins = 3000
			task.wait(SHOP_COOLDOWN)
			session:fromClient("BuyWithCoins", player, "PenUpgrade")
			expect.equal(dataOf(session, 1).PenLevel, 2)
			expect.equal(dataOf(session, 1).Coins, 500)
			expect.equal(session:lastSent("PlayerStateUpdated", player).args[1].penLevel, 2)
			expect.equal(purchaseResult(session, player)[2], true)

			dataOf(session, 1).PenLevel = 9
			task.wait(SHOP_COOLDOWN)
			session:fromClient("BuyWithCoins", player, "PenUpgrade")
			expect.equal(purchaseResult(session, player)[2], false)
			expect.equal(dataOf(session, 1).Coins, 500)
		end)

		it("unlocks game passes", function()
			local session = startServer()
			local shop = shopConfig(session)
			shop.PassesById.DoubleCoins.gamePassId = 2222
			session.ownedGamePasses[1] = { [2222] = true }
			local player = session:addPlayer(1, "Owner")
			session:heartbeat(1 / 60)
			local service = session:require(session:service("ServerScriptService").Server.Services.ShopService)
			expect.equal(service.OwnsPass(player, "DoubleCoins"), true, "owned before joining")

			local passes = session:lastSent("PlayerStateUpdated", player).args[1].passes
			expect.equal(table.concat(passes, ","), "DoubleCoins")
			session:fromClient("RequestPurchase", player, "DoubleCoins")
			expect.equal(purchaseResult(session, player)[3], "You already own this!")
			expect.equal(#session.prompts, 0)

			-- Bought through Roblox's prompt during the game.
			local buyer = session:addPlayer(2, "Buyer")
			session:heartbeat(1 / 60)
			expect.equal(service.OwnsPass(buyer, "DoubleCoins"), false)
			session:fire(session:service("MarketplaceService"), "PromptGamePassPurchaseFinished", buyer, 2222, true)
			expect.equal(service.OwnsPass(buyer, "DoubleCoins"), true)
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
			session:fromClient("RequestPurchase", player, "FreeCoins")
			session:fromClient("BuyWithCoins", player, "Coins1")
			expect.equal(#session:sent("PurchaseResult", player), 0)
			expect.equal(#session.prompts, 0)
			expect.equal(dataOf(session, 1).Coins, 0)
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
