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
				eggCount = 2,
				coins = 0,
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

	-- An egg as the server describes it, spawned `age` seconds ago. It is the zone's first egg of that rarity.
	local function eggData(session, id, zone, rarity, age, lateral)
		return {
			id = id,
			zone = zone,
			rarity = rarity,
			kind = shared(session).EggSpec.pickEgg(zone, rarity, 0),
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
			expect.truthy(model.PrimaryPart == model.Root, "PrimaryPart")
			local _, spec = eggCenter(session, first)
			expect.near(model.Root.Size.Y, spec.radius * 2, 1e-3)
			expect.near(model.Root.Size.X, spec.halfLength * 2, 1e-3)
			expect.equal(model.Root.Transparency, 1)
			expect.equal(model.Root.Anchored, true)

			-- Labels: rarity, then the stamina needed (green if the player has enough, red if not).
			local labels = model.Root.Label:GetChildren()
			expect.equal(labels[1].Text, "Common")
			expect.equal(labels[2].Text, "Needs 50")
			local mythicLabels = parts.eggFolder.Egg2.Root.Label:GetChildren()
			expect.equal(mythicLabels[2].Text, "Needs 1.8K")
			expect.truthy(
				labels[2].TextColor3 ~= mythicLabels[2].TextColor3,
				"affordable and not are colored differently"
			)
		end)

		it("builds each egg from its blocky model, welded to the root", function()
			local session, parts = startClient()
			session:fromServer("EggSpawned", eggData(session, 1, 1, "Common"))
			session:fromServer("EggSpawned", eggData(session, 3, 1, "Common", 5, 8))
			session:fromServer("EggSpawned", eggData(session, 2, 5, "Secret", 5, -8))

			local EggModels = session:require(session:service("ReplicatedStorage").Shared.EggModels)
			local common = parts.eggFolder.Egg1
			local blocks = {}
			for _, child in common:GetChildren() do
				if child:IsA("BasePart") and child ~= common.Root then
					table.insert(blocks, child)
				end
			end
			expect.equal(#blocks, #EggModels.get("Leafy").boxes, "one part per box")
			for _, block in blocks do
				local weld = block:FindFirstChildOfClass("WeldConstraint")
				expect.truthy(weld, block.Name .. " is welded")
				expect.equal(block.Anchored, false)
				expect.equal(block.CanCollide, false)
			end

			-- A second egg of the same kind is a copy of the same model.
			expect.equal(#parts.eggFolder.Egg3:GetChildren(), #common:GetChildren())

			-- Rare eggs glow and give off particles; a Common egg does neither.
			local secret = parts.eggFolder.Egg2
			expect.truthy(secret.Root:FindFirstChildOfClass("PointLight"), "light")
			expect.truthy(secret.Root:FindFirstChildOfClass("ParticleEmitter"), "particles")
			expect.falsy(common.Root:FindFirstChildOfClass("PointLight"), "no light on a Common egg")
			local neon = 0
			for _, child in secret:GetChildren() do
				if child:IsA("BasePart") and child.Material == Enum.Material.Neon then
					neon += 1
				end
			end
			expect.truthy(neon > 0, "glowing lava")

			-- Eggs with even ids lie the other way round.
			session:renderFrame(1 / 60)
			expect.truthy(common.Root.CFrame.RightVector.X > 0.99, "Egg1 points +X")
			expect.truthy(parts.eggFolder.Egg2.Root.CFrame.RightVector.X < -0.99, "Egg2 points -X")
		end)

		it("draws each of a zone's eggs of the same rarity differently", function()
			local session, parts = startClient()
			local leafy = eggData(session, 1, 1, "Common")
			local cottontail = eggData(session, 3, 1, "Common", 5, 10)
			cottontail.kind = "Cottontail"
			-- An egg the zone does not have at that rarity is drawn as the zone's first egg of the rarity.
			local wrong = eggData(session, 5, 1, "Common", 5, -10)
			wrong.kind = "Yeti"
			for _, egg in { leafy, cottontail, wrong } do
				session:fromServer("EggSpawned", egg)
			end
			local EggModels = session:require(session:service("ReplicatedStorage").Shared.EggModels)
			local function blockCount(model)
				return #model:GetChildren() - 1
			end
			expect.equal(blockCount(parts.eggFolder.Egg1), #EggModels.get("Leafy").boxes)
			expect.equal(blockCount(parts.eggFolder.Egg3), #EggModels.get("Cottontail").boxes)
			expect.equal(blockCount(parts.eggFolder.Egg5), #EggModels.get("Leafy").boxes)
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
			local position = parts.eggFolder.Egg1.Root.CFrame.Position
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
			local need = parts.eggFolder.Egg1.Root.Label:GetChildren()[2]
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
			expect.truthy(model.Root.CFrame.Position.X < -5, "egg moved: " .. model.Root.CFrame.Position.X)
			local report = session:lastSent("RideLateral", "server")
			expect.truthy(report, "RideLateral")
			expect.truthy(report.args[1] < 0)

			-- It cannot be steered off the side of the runway.
			session:renderFrame(1, 30)
			local limit = shared(session).Runway.maxLateral(spec.halfLength)
			expect.near(model.Root.CFrame.Position.X, -limit, 1e-3)
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

			session:fromServer("RideEnded", "Claimed", { eggId = 1, zone = 1, rarity = "Common", kind = "Leafy" })
			session:fromServer("EggRemoved", 1, "Claimed", LOCAL_USER_ID)
			session:fromServer("InventoryUpdated", 3)
			session:renderFrame(1 / 60)

			expect.equal(parts.root.Anchored, false)
			local toast = hud(parts).Toast
			expect.equal(toast.Text, "CLAIMED! +1 Leafy Egg")
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

	describe("Client: HUD", function()
		it("animates rigged pets: winged ones hover, beating their wings, and play the move they are given", function()
			local session = startClient()
			local workspace = session:service("Workspace")
			local PetRig = session:require(session:service("ReplicatedStorage").Shared.PetRig)
			local folder = roblox.Instance.new("Folder")
			folder.Name = "StudioPets"
			folder.Parent = workspace
			session:fire(workspace, "ChildAdded", folder)
			local phoenix = PetRig.build("EternalPhoenix")
			phoenix.Parent = folder
			session:fire(folder, "ChildAdded", phoenix)
			local fox = PetRig.build("Fox")
			fox.Parent = folder
			session:fire(folder, "ChildAdded", fox)

			session:renderFrame(0.1, 3)
			local lift = phoenix.Root.Body.Transform.Position.Y
			expect.truthy(lift > 1, "the phoenix rises off the ground to hover: " .. lift)
			local wing = phoenix.Body.LeftWing.Transform
			session:renderFrame(0.1)
			expect.truthy(phoenix.Body.LeftWing.Transform ~= wing, "its wings beat")
			-- The fox walks on the spot: its legs swing.
			local leg = fox.Body.FrontLeftLeg.Transform
			session:renderFrame(0.1)
			expect.truthy(fox.Body.FrontLeftLeg.Transform ~= leg, "the fox's legs swing")

			phoenix:SetAttribute("Move", "Idle")
			session:renderFrame(0.1)
			expect.truthy(phoenix.Root.Body.Transform.Position.Y < 0.5, "standing idle, it is back on the ground")
			phoenix:SetAttribute("Move", "Fly")
			session:renderFrame(0.1)
			local _, _, _, _, _, _, _, _, _, _, forward = phoenix.Root.Body.Transform:GetComponents()
			expect.truthy(phoenix.Root.Body.Transform.Position.Y > 1, "flying, it is up in the air")
			expect.truthy(forward < 0.99, "and tipped forward")
		end)

		it("builds the HUD with Fusion", function()
			local _, parts = startClient()
			local root = hud(parts)
			for _, name in { "Cycle", "Zone", "Wallet", "Toast", "Meters", "StudioTestPanel" } do
				expect.truthy(root:FindFirstChild(name), name)
			end
			expect.truthy(root.Meters.Claim and root.Meters.Stamina and root.Meters.RideHint, "meters")
			expect.equal(labelOf(root.Wallet.Eggs).Text, "Eggs  2")
			expect.equal(labelOf(root.Wallet.Coins).Text, "Coins  0")
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
			expect.equal(labelOf(claim).Text, "Epic Bear Egg  25%  - not enough stamina!")
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
