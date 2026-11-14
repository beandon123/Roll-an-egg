--!nocheck
-- Runs the real client script from the built place file against the stand-in for Roblox Studio (tests/studio):
-- egg drawing, the riding controller, and the Fusion HUD. As with the server smoke tests, this catches
-- misspelled properties and wiring mistakes, not how things look or feel.

local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Studio = require("../studio")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local place, reason = Studio.buildPlace()
	if place == nil then
		print(`SKIPPED client smoke tests: {reason}`)
		return
	end

	local LOCAL_USER_ID = 7

	-- One player's device, with the client script running. `eggs` is what the server's snapshot contains.
	local function startClient(eggs)
		local session = Studio.open(place, { isServer = false })
		session:createRemotes()
		local player, humanoid, root = session:addPlayer(LOCAL_USER_ID, "Me")
		local playerGui = session:setLocalPlayer(player)

		session.invokeHandlers.GetSnapshot = function()
			return {
				eggs = eggs or {},
				stamina = { value = 100, time = session.clock, rate = 12, max = 100 },
				agility = 14,
				inventory = { { zone = 1, rarity = "Common", count = 2 } },
				coins = 0,
				trails = { owned = {}, equipped = "" },
			}
		end

		session:run(session:service("StarterPlayer").StarterPlayerScripts.Client)
		return session,
			{
				player = player,
				humanoid = humanoid,
				root = root,
				playerGui = playerGui,
				eggFolder = session:service("Workspace"):FindFirstChild("Eggs"),
			}
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

	-- An egg as the server describes it, spawned `age` seconds ago.
	local function eggData(session, id, zone, rarity, age, lateral)
		return {
			id = id,
			zone = zone,
			rarity = rarity,
			spawnTime = session.clock - (age or 5),
			lateral = lateral or 0,
			rider = nil,
			bounces = 1,
			bounceTime = nil,
			cracking = false,
		}
	end

	local function eggCenter(session, egg)
		local modules = shared(session)
		local spec = modules.EggSpec.get(egg.zone, egg.rarity)
		local startZ = modules.Runway.zoneStartZ(egg.zone) + modules.Tuning.EGG_SPAWN_OFFSET
		local z = modules.EggMotion.zAt(egg.spawnTime, startZ, spec.rollSpeed, session.clock)
		return Vector3.new(egg.lateral, modules.Runway.surfaceY(z) + spec.radius, z), spec
	end

	-- Puts the character in the air right on top of an egg, as if it had just jumped there.
	local function jumpOnto(session, parts, egg)
		local center, spec = eggCenter(session, egg)
		parts.root.Position = center + Vector3.new(0, spec.radius, 0)
		parts.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	local function startRide(session, egg, claimTime)
		session:fromServer("EggMounted", egg.id, LOCAL_USER_ID, session.clock)
		session:fromServer("RideStarted", egg.id, {
			startTime = session.clock,
			startStamina = 100,
			drain = 8,
			claimTime = claimTime or 5,
			combo = 0,
		})
	end

	local function hud(parts)
		return parts.playerGui.Hud.Root
	end

	-- The text label inside a HUD bar or pill.
	local function labelOf(frame)
		return frame:FindFirstChildOfClass("TextLabel")
	end

	describe("Client: drawing eggs", function()
		it("draws the eggs in the snapshot and ones that drop later", function()
			local session, parts = startClient()
			expect.truthy(parts.eggFolder, "Workspace.Eggs")
			expect.equal(#parts.eggFolder:GetChildren(), 0)

			local first = eggData(session, 1, 1, "Common")
			local second = eggData(session, 2, 2, "Mythic")
			session:fromServer("EggSpawned", first)
			session:fromServer("EggSpawned", second)
			-- A repeat of an egg we already have is ignored.
			session:fromServer("EggSpawned", first)
			expect.equal(#parts.eggFolder:GetChildren(), 2)

			local model = parts.eggFolder.Egg1
			expect.truthy(model.PrimaryPart == model.Shell, "PrimaryPart")
			expect.truthy(model.Spot1 and model.Spot2 and model.Spot3, "spots")
			local _, spec = eggCenter(session, first)
			expect.near(model.Shell.Size.Y, spec.radius * 2, 1e-3)
			expect.near(model.Shell.Size.X, spec.halfLength * 2, 1e-3)

			-- Labels: rarity, then the stamina needed (green if the player has enough, red if not).
			local labels = model.Shell.Label:GetChildren()
			expect.equal(labels[1].Text, "Common")
			expect.equal(labels[2].Text, "Needs 50")
			local mythicLabels = parts.eggFolder.Egg2.Shell.Label:GetChildren()
			expect.equal(mythicLabels[2].Text, "Needs 1.8K")
			expect.truthy(
				labels[2].TextColor3 ~= mythicLabels[2].TextColor3,
				"affordable and not are colored differently"
			)
		end)

		it("loads eggs from the server snapshot at startup", function()
			local probe = Studio.open(place, { isServer = false })
			local clock = probe.clock
			local _, parts = startClient({
				{
					id = 4,
					zone = 1,
					rarity = "Rare",
					spawnTime = clock - 3,
					lateral = 2,
					bounces = 2,
					cracking = false,
				},
			})
			expect.equal(#parts.eggFolder:GetChildren(), 1)
			expect.truthy(parts.eggFolder:FindFirstChild("Egg4"))
		end)

		it("moves eggs down the runway every frame", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common", 5, 3)
			session:fromServer("EggSpawned", egg)
			session:renderFrame(1 / 60, 30)
			local expected = eggCenter(session, egg)
			local position = parts.eggFolder.Egg1.Shell.CFrame.Position
			expect.near(position.Z, expected.Z, 1e-3, "z")
			expect.near(position.Y, expected.Y, 1e-3, "y")
			expect.near(position.X, 3, 1e-3, "x")
		end)

		it("removes eggs, leaving a splat when one cracks", function()
			local session, parts = startClient()
			session:fromServer("EggSpawned", eggData(session, 1, 1, "Common"))
			session:fromServer("EggSpawned", eggData(session, 2, 1, "Common"))

			session:fromServer("EggRemoved", 1, "Cracked")
			expect.falsy(parts.eggFolder:FindFirstChild("Egg1"))
			expect.truthy(parts.eggFolder:FindFirstChild("Splat"), "splat")

			session:fromServer("EggRemoved", 2, "Faded")
			session:fromServer("EggRemoved", 99, "Faded") -- unknown eggs are ignored
			session:renderFrame(1 / 60)
			task.wait(0.7)
			expect.falsy(parts.eggFolder:FindFirstChild("Egg2"))
		end)

		it("shows when an egg is taken and turns labels green as stamina grows", function()
			local session, parts = startClient()
			session:fromServer("EggSpawned", eggData(session, 1, 2, "Common")) -- needs 500
			local need = parts.eggFolder.Egg1.Shell.Label:GetChildren()[2]
			local red = need.TextColor3

			session:fromServer("StaminaChanged", 100, session.clock, 60, 500)
			expect.truthy(need.TextColor3 ~= red, "label recolored once the player can afford the egg")

			session:fromServer("EggMounted", 1, 999, session.clock)
			expect.equal(need.Text, "Taken")
			session:fromServer("EggLeft", 1, session.clock, 0, 4)
			expect.equal(need.Text, "Needs 500")
		end)
	end)

	describe("Client: riding", function()
		it("asks to mount when jumping next to an egg, and not otherwise", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)

			-- Standing next to it: nothing.
			local center = eggCenter(session, egg)
			parts.root.Position = center
			session:heartbeat(1 / 60)
			expect.equal(#session:sent("RequestMount"), 0)

			-- In the air but far away: nothing.
			parts.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			parts.root.Position = center + Vector3.new(0, 0, 30)
			session:heartbeat(1 / 60)
			expect.equal(#session:sent("RequestMount"), 0)

			-- In the air on top of it: ask.
			jumpOnto(session, parts, egg)
			session:heartbeat(1 / 60)
			local request = session:lastSent("RequestMount", "server")
			expect.truthy(request, "RequestMount")
			expect.equal(request.args[1], 1)
		end)

		it("does not try to mount an egg that is taken, cracking, or still dropping in", function()
			local session, parts = startClient()
			local taken = eggData(session, 1, 1, "Common")
			taken.rider = 999
			local cracking = eggData(session, 2, 1, "Common", 5, 10)
			cracking.cracking = true
			local dropping = eggData(session, 3, 1, "Common", 0.1, -10)
			for _, egg in { taken, cracking, dropping } do
				session:fromServer("EggSpawned", egg)
				jumpOnto(session, parts, egg)
				session:heartbeat(1 / 60)
				task.wait(0.3)
			end
			expect.equal(#session:sent("RequestMount"), 0)
		end)

		it("holds the character on the egg and steers it", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			startRide(session, egg)
			expect.equal(parts.root.Anchored, true)
			expect.equal(parts.humanoid.Sit, true)

			-- The character is placed on top of the egg, facing down the runway.
			session:renderFrame(1 / 60)
			local center, spec = eggCenter(session, egg)
			local seat = parts.root.CFrame
			expect.near(seat.Position.Z, center.Z, 1e-3)
			expect.near(seat.Position.Y, center.Y + spec.radius + 2, 1e-3)
			expect.near(seat.LookVector.Z, 1, 1e-3, "facing +Z")

			-- Pushing right on the stick moves the egg to the player's right. The camera looks down the
			-- runway (+Z), so screen-right is -X.
			session.moveVector = Vector3.new(1, 0, 0)
			session:renderFrame(1 / 60, 30)
			task.wait(0.3)
			session:renderFrame(1 / 60)
			local model = session:service("Workspace").Eggs.Egg1
			expect.truthy(model.Shell.CFrame.Position.X < -5, "egg moved: " .. model.Shell.CFrame.Position.X)
			local report = session:lastSent("RideLateral", "server")
			expect.truthy(report, "RideLateral")
			expect.truthy(report.args[1] < 0)

			-- It cannot be steered off the side of the runway.
			session:renderFrame(1, 30)
			local limit = shared(session).Runway.maxLateral(spec.halfLength)
			expect.near(model.Shell.CFrame.Position.X, -limit, 1e-3)
		end)

		it("hops off on a fresh jump press", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			local userInput = session:service("UserInputService")

			-- The jump that got the player onto the egg is still held: it must not throw them straight off.
			session:fire(userInput, "JumpRequest")
			startRide(session, egg)
			session:fire(userInput, "JumpRequest")
			session:heartbeat(1 / 60)
			expect.equal(#session:sent("RequestDismount"), 0)
			expect.equal(parts.root.Anchored, true)

			-- Released, then pressed again a moment later.
			task.wait(0.6)
			session:heartbeat(1 / 60)
			session:fire(userInput, "JumpRequest")
			expect.equal(#session:sent("RequestDismount", "server"), 1)
			expect.equal(parts.root.Anchored, false)
			expect.equal(parts.humanoid.Sit, false)
			expect.truthy(parts.root.AssemblyLinearVelocity.Y > 0, "hops upward")

			-- The server's confirmation arriving afterwards changes nothing.
			session:fromServer("RideEnded", "Dismount", { eggId = 1, zone = 1, rarity = "Common" })
			expect.equal(parts.root.Anchored, false)

			-- The egg just left is ignored for a moment, so the player does not land straight back on it.
			jumpOnto(session, parts, egg)
			session:heartbeat(1 / 60)
			expect.equal(#session:sent("RequestMount"), 0)
		end)

		it("lets go and celebrates when the egg is claimed", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			startRide(session, egg)

			session:fromServer("RideEnded", "Claimed", { eggId = 1, zone = 1, rarity = "Common" })
			session:fromServer("EggRemoved", 1, "Claimed", LOCAL_USER_ID)
			session:fromServer("InventoryUpdated", { { zone = 1, rarity = "Common", count = 3 } })
			session:renderFrame(1 / 60)

			expect.equal(parts.root.Anchored, false)
			local toast = hud(parts).Toast
			expect.equal(toast.Text, "CLAIMED! +1 Common egg")
			expect.equal(toast.Visible, true)
			expect.equal(labelOf(hud(parts).Wallet.Eggs).Text, "Eggs  3")
		end)

		it("stuns a rider who is thrown off", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Rare")
			session:fromServer("EggSpawned", egg)
			startRide(session, egg, 9)

			session:fromServer("RideEnded", "ThrownOff", { eggId = 1, zone = 1, rarity = "Rare" })
			session:fromServer("EggLeft", 1, session.clock, 1, 0)
			expect.equal(parts.root.Anchored, false)
			expect.equal(parts.humanoid.PlatformStand, true)

			-- Still stunned: jumping at an egg does nothing.
			local other = eggData(session, 2, 1, "Common", 5, 12)
			session:fromServer("EggSpawned", other)
			jumpOnto(session, parts, other)
			session:heartbeat(1 / 60)
			expect.equal(#session:sent("RequestMount"), 0)

			-- The stun wears off.
			task.wait(2)
			expect.equal(parts.humanoid.PlatformStand, false)
			jumpOnto(session, parts, other)
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("RequestMount", "server").args[1], 2)
		end)

		it("gives the egg back if there is no character to put on it", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			parts.humanoid.Health = 0
			startRide(session, egg)
			expect.equal(#session:sent("RequestDismount", "server"), 1)
			expect.equal(parts.root.Anchored, false)
		end)

		it("pins other players to their eggs", function()
			local session = startClient()
			local _, _, otherRoot = session:addPlayer(55, "Other")
			local egg = eggData(session, 1, 1, "Common", 5, 6)
			egg.rider = 55
			session:fromServer("EggSpawned", egg)
			session:fromServer("EggLateral", 1, 6)
			session:renderFrame(1 / 60)
			local center = eggCenter(session, egg)
			expect.near(otherRoot.CFrame.Position.Z, center.Z, 1e-3)
			expect.near(otherRoot.CFrame.Position.X, 6, 1e-3)
		end)
	end)

	describe("Client: hub stations", function()
		local function layoutOf(session)
			return session:require(session:service("ReplicatedStorage").Shared.HubLayout)
		end

		-- Stands the character beside a station and uses its prompt. (A key that is not a station's is tried from
		-- beside the Sell stall.)
		local function useStation(session, parts, key)
			local stations = layoutOf(session).STATIONS
			local station = stations[key] or stations.Sell
			parts.root.Position = Vector3.new(station.x + 4, 13, station.z + 4)
			local prompt = roblox.Instance.new("ProximityPrompt")
			prompt:SetAttribute("Station", key)
			session:fire(session:service("ProximityPromptService"), "PromptTriggered", prompt, parts.player)
			session:heartbeat(1 / 60)
			session:renderFrame(1 / 60)
		end

		local function click(session, button)
			session:fire(button, "Activated")
			session:renderFrame(1 / 60)
		end

		it("opens a station's panel from its prompt and closes it when the player walks away", function()
			local session, parts = startClient()
			local root = hud(parts)
			expect.equal(root.Trails.Visible, false)

			useStation(session, parts, "Trails")
			expect.equal(root.Trails.Visible, true)
			expect.equal(root.Sell.Visible, false)
			expect.equal(root.Fuse.Visible, false)

			parts.root.Position = Vector3.new(0, 13, 0)
			session:heartbeat(1 / 60)
			expect.equal(root.Trails.Visible, false)

			-- The close button works too, and prompts that are not stations are ignored.
			useStation(session, parts, "Sell")
			expect.equal(root.Sell.Visible, true)
			click(session, root.Sell.Close)
			expect.equal(root.Sell.Visible, false)
			useStation(session, parts, "Nothing")
			for _, name in { "Trails", "Sell", "Fuse" } do
				expect.equal(root[name].Visible, false, name)
			end
		end)

		it("shows each trail's price, and whether it is owned or equipped", function()
			local session, parts = startClient()
			local panel = hud(parts).Trails
			useStation(session, parts, "Trails")
			local leaf = panel.List.Leaf.Action
			expect.equal(panel.List.Leaf.TrailName.Text, "Leaf Trail")
			expect.equal(panel.List.Leaf.Boost.Text, "Stamina x1.2")
			expect.equal(leaf.Text, "100 coins")
			expect.equal(panel.List.Rainbow.Action.Text, "2.5M coins")
			local tooExpensive = leaf.BackgroundColor3

			session:fromServer("CoinsChanged", 600)
			session:renderFrame(1 / 60)
			expect.truthy(leaf.BackgroundColor3 ~= tooExpensive, "affordable trails light up")
			expect.equal(labelOf(hud(parts).Wallet.Coins).Text, "Coins  600")

			session:fromServer("TrailsUpdated", { "Leaf" }, "Leaf")
			session:renderFrame(1 / 60)
			expect.equal(leaf.Text, "Equipped")
			expect.equal(panel.List.Sunbeam.Action.Text, "500 coins")
			expect.equal(panel.Footer.Text, "Coins: 600     Stamina boost: x1.2")

			session:fromServer("TrailsUpdated", { "Leaf", "Sunbeam" }, "Sunbeam")
			session:renderFrame(1 / 60)
			expect.equal(leaf.Text, "Equip")
			expect.equal(panel.List.Sunbeam.Action.Text, "Equipped")
		end)

		it("asks the server to buy and equip trails, and says how it went", function()
			local session, parts = startClient()
			local panel = hud(parts).Trails
			useStation(session, parts, "Trails")
			session.invokeHandlers.BuyTrail = function(trailId)
				if trailId == "Rainbow" then
					return false, "NotEnoughCoins"
				end
				return true, "BoughtAndEquipped"
			end
			session.invokeHandlers.EquipTrail = function()
				return true, "Equipped"
			end

			click(session, panel.List.Sunbeam.Action)
			expect.equal(session:lastSent("BuyTrail", "server").args[1], "Sunbeam")
			expect.equal(hud(parts).Toast.Text, "Sunbeam Trail equipped! Stamina x1.5")

			click(session, panel.List.Rainbow.Action)
			expect.equal(hud(parts).Toast.Text, "Not enough coins")

			-- Owned trails are equipped instead of bought; the one already equipped does nothing.
			session:fromServer("TrailsUpdated", { "Leaf", "Sunbeam" }, "Sunbeam")
			session:renderFrame(1 / 60)
			click(session, panel.List.Leaf.Action)
			expect.equal(session:lastSent("EquipTrail", "server").args[1], "Leaf")
			click(session, panel.List.Sunbeam.Action)
			expect.equal(#session:sent("EquipTrail", "server"), 1)
			expect.equal(#session:sent("BuyTrail", "server"), 2)
		end)

		it("lists the player's eggs at the Sell stall and sells them", function()
			local session, parts = startClient()
			local panel = hud(parts).Sell
			useStation(session, parts, "Sell")
			session:fromServer("InventoryUpdated", {
				{ zone = 1, rarity = "Common", count = 3 },
				{ zone = 2, rarity = "Mythic", count = 1 },
			})
			session:renderFrame(1 / 60)
			expect.equal(panel.List.Empty.Visible, false)
			local commons = panel.List.Egg_1_Common
			expect.equal(commons.EggName.Text, "Common Forest egg")
			expect.equal(commons.Details.Text, "x3   25 coins each")
			expect.equal(panel.List.Egg_2_Mythic.Details.Text, "x1   900 coins each")
			expect.truthy(commons.LayoutOrder < panel.List.Egg_2_Mythic.LayoutOrder, "in inventory order")
			expect.equal(labelOf(hud(parts).Wallet.Eggs).Text, "Eggs  4")

			session.invokeHandlers.SellEggs = function(_zone, _rarity, count)
				return count, count * 25
			end
			click(session, commons.SellAll)
			local request = session:lastSent("SellEggs", "server")
			expect.equal(request.args[1], 1)
			expect.equal(request.args[2], "Common")
			expect.equal(request.args[3], 3)
			expect.equal(hud(parts).Toast.Text, "Sold 3 Common Forest eggs for 75 coins")

			click(session, commons.SellOne)
			expect.equal(session:lastSent("SellEggs", "server").args[3], 1)
			expect.equal(hud(parts).Toast.Text, "Sold 1 Common Forest egg for 25 coins")

			-- Once everything is sold, the panel says so.
			session:fromServer("InventoryUpdated", {})
			session:renderFrame(1 / 60)
			expect.equal(panel.List.Empty.Visible, true)
			expect.falsy(panel.List:FindFirstChild("Egg_1_Common"), "sold rows are gone")
			expect.equal(labelOf(hud(parts).Wallet.Eggs).Text, "Eggs  0")
			expect.equal(#session.warnings, 0, "warnings: " .. table.concat(session.warnings, "; "))
		end)

		it("explains the fuse machine", function()
			local session, parts = startClient()
			useStation(session, parts, "Fuse")
			local panel = hud(parts).Fuse
			expect.equal(panel.Visible, true)
			expect.truthy(panel.List.HowItWorks.Text:find("3 of the same pet"), panel.List.HowItWorks.Text)
			expect.truthy(panel.List.Odds.Text:find("1 in 3"), panel.List.Odds.Text)
		end)
	end)

	describe("Client: HUD", function()
		it("builds the HUD with Fusion", function()
			local session, parts = startClient()
			local root = hud(parts)
			for _, name in { "Cycle", "Zone", "Wallet", "Toast", "Meters", "StudioTestPanel", "Trails", "Sell", "Fuse" } do
				expect.truthy(root:FindFirstChild(name), name)
			end
			expect.truthy(root.Meters.Claim and root.Meters.Stamina and root.Meters.RideHint, "meters")
			expect.equal(labelOf(root.Wallet.Eggs).Text, "Eggs  2")
			expect.equal(labelOf(root.Wallet.Coins).Text, "Coins  0")
			expect.equal(#session.warnings, 0, "warnings: " .. table.concat(session.warnings, "; "))
		end)

		it("shows stamina, the runway cycle, and the zone", function()
			local session, parts = startClient()
			local root = hud(parts)

			session:fromServer("StaminaChanged", 40, session.clock, 0, 100)
			parts.root.Position = Vector3.new(0, 0, 700)
			session:renderFrame(1 / 60, 2)
			expect.equal(labelOf(root.Meters.Stamina).Text, "Stamina  40 / 100")
			expect.near(root.Meters.Stamina.Fill.Size.X.Scale, 0.4, 1e-6)
			expect.equal(root.Zone.Text, "Desert")
			-- The stand-in clock starts 5 s into a cycle; the runway closes at 170 s.
			expect.truthy(labelOf(root.Cycle).Text:match("^Runway closes in 2:4%d$"), labelOf(root.Cycle).Text)

			-- Stamina regenerating is followed without further messages.
			session:fromServer("StaminaChanged", 40, session.clock, 10, 100)
			session:renderFrame(1, 3)
			expect.equal(labelOf(root.Meters.Stamina).Text, "Stamina  70 / 100")

			-- Into the warning, then the closure.
			session:renderFrame(1, 158)
			expect.truthy(labelOf(root.Cycle).Text:match("^Runway closing in"), labelOf(root.Cycle).Text)
			session:renderFrame(1, 10)
			expect.truthy(labelOf(root.Cycle).Text:match("^Runway closed"), labelOf(root.Cycle).Text)
		end)

		it("shows the claim meter only while riding, and warns when stamina will not last", function()
			local session, parts = startClient()
			local claim = hud(parts).Meters.Claim
			session:renderFrame(1 / 60)
			expect.equal(claim.Visible, false)

			local egg = eggData(session, 1, 1, "Epic")
			session:fromServer("EggSpawned", egg)
			-- 100 stamina draining at 13.3 a second will not last a 12 s claim.
			session:fromServer("StaminaChanged", 100, session.clock, -13.3, 100)
			session:fromServer("EggMounted", 1, LOCAL_USER_ID, session.clock)
			session:fromServer("RideStarted", 1, {
				startTime = session.clock,
				startStamina = 100,
				drain = 13.3,
				claimTime = 12,
				combo = 0,
			})
			session:renderFrame(1, 3)
			expect.equal(claim.Visible, true)
			expect.near(claim.Fill.Size.X.Scale, 0.25, 1e-3)
			expect.equal(labelOf(claim).Text, "Epic Forest egg  25%  - not enough stamina!")
		end)

		it("sends Studio test commands from the test panel", function()
			local session, parts = startClient()
			local button = hud(parts).StudioTestPanel.StaminaUp
			session:fire(button, "Activated")
			expect.equal(session:lastSent("DevCommand", "server").args[1], "StaminaUp")
		end)

		it("shows server announcements", function()
			local session, parts = startClient()
			session:fromServer("Announce", "A Legendary egg just dropped in the Forest!", { 255, 190, 40 })
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Toast.Text, "A Legendary egg just dropped in the Forest!")
			expect.equal(hud(parts).Toast.Visible, true)
		end)
	end)
end
