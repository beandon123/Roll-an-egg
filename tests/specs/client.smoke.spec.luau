--!nocheck
-- Runs the real client script from the built place file against the stand-in for Roblox Studio (tests/studio):
-- egg drawing, the riding controller, and the Fusion HUD. As with the server smoke tests, this catches
-- misspelled properties and wiring mistakes, not how things look or feel.

local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Studio = require("../studio")

local Enum = roblox.Enum
local CFrame = roblox.CFrame
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
				dustFolder = session:service("Workspace"):FindFirstChild("EggDust"),
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
			owner = nil,
			bounces = 1,
		}
	end

	local function eggCenter(session, egg)
		local modules = shared(session)
		local spec = modules.EggSpec.get(egg.zone, egg.rarity)
		local z = modules.EggMotion.zAt(egg.spawnTime, spec.startZ, spec.rollSpeed, session.clock)
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
			session:fromServer("EggLeft", 1, 4)
			expect.equal(need.Text, "Needs 500")

			-- Claimed: by someone else, then (on another egg) by this player.
			session:fromServer("EggClaimed", 1, 999, "Common")
			expect.equal(need.Text, "Claimed")
			session:fromServer("EggSpawned", eggData(session, 2, 1, "Common", 5, 10))
			session:fromServer("EggClaimed", 2, LOCAL_USER_ID, "Common")
			expect.equal(parts.eggFolder.Egg2.Shell.Label:GetChildren()[2].Text, "Yours!")
		end)
	end)

	describe("Client: eggs appear, roll, and kick up dust", function()
		local function dustOf(parts, eggId)
			return parts.dustFolder:FindFirstChild("Dust" .. eggId)
		end

		it("puts a new egg on the ground at the start of its zone and rolls it without bouncing", function()
			local session, parts = startClient()
			local modules = shared(session)
			for zone, rarity in { "Common", "Rare", "Secret", "Secret", "Eternal" } do
				local egg = eggData(session, zone, zone, rarity, 0, 0)
				session:fromServer("EggSpawned", egg)
				local spec = modules.EggSpec.get(zone, rarity)
				local position = parts.eggFolder["Egg" .. zone].Shell.CFrame.Position
				-- On the ground, its back just past the zone's start line, from the very first frame.
				local back = modules.Runway.zoneStartZ(zone) + modules.Tuning.EGG_SPAWN_GAP
				expect.near(position.Z - spec.radius, back, 1e-3, rarity .. " start")
				expect.near(position.Y, modules.Runway.surfaceY(position.Z) + spec.radius, 1e-3, rarity .. " height")
			end

			-- Two seconds of frames: every egg stays on the ground and only ever moves down the runway.
			local lastZ = {}
			for _ = 1, 120 do
				session:renderFrame(1 / 60)
				for zone = 1, 5 do
					local spec = modules.EggSpec.get(zone, ({ "Common", "Rare", "Secret", "Secret", "Eternal" })[zone])
					local position = parts.eggFolder["Egg" .. zone].Shell.CFrame.Position
					expect.near(position.Y, modules.Runway.surfaceY(position.Z) + spec.radius, 1e-3, "on the ground")
					expect.truthy(lastZ[zone] == nil or position.Z > lastZ[zone], "rolls forward")
					lastZ[zone] = position.Z
				end
			end
		end)

		it("fades a new egg in with a puff of dust", function()
			local session, parts = startClient()
			session:fromServer("EggSpawned", eggData(session, 1, 1, "Common", 0))
			local dust = dustOf(parts, 1)
			expect.truthy(dust, "dust strip")
			expect.truthy((session.emitted[dust.Dust] or 0) > 0, "puff where it appears")
			-- An egg that was already rolling when the player joined just shows up.
			session:fromServer("EggSpawned", eggData(session, 2, 1, "Common", 20, 10))
			expect.equal(session.emitted[dustOf(parts, 2).Dust], nil)
		end)

		it("leaves a dust trail behind rolling eggs near the camera", function()
			local session, parts = startClient()
			local modules = shared(session)
			local egg = eggData(session, 1, 1, "Rare", 3, 5)
			session:fromServer("EggSpawned", egg)
			session:renderFrame(1 / 60)

			local dust = dustOf(parts, 1)
			local center, spec = eggCenter(session, egg)
			expect.equal(dust.Transparency, 1)
			expect.equal(dust.Dust.Enabled, true)
			expect.equal(dust.Dust.Texture, "rbxasset://textures/particles/smoke_main.dds")
			-- On the ground, just behind where the egg touches it, and not spinning with the egg.
			expect.near(dust.CFrame.Position.X, 5, 1e-3)
			expect.truthy(dust.CFrame.Position.Z < center.Z, "behind the egg")
			expect.truthy(center.Z - dust.CFrame.Position.Z < spec.radius, "close behind the egg")
			expect.near(dust.CFrame.Position.Y, modules.Runway.surfaceY(center.Z), 0.5)
			expect.near(dust.CFrame.LookVector.Z, -1, 1e-6)

			session:renderFrame(1 / 60, 30)
			center = eggCenter(session, egg)
			expect.truthy(center.Z - dust.CFrame.Position.Z < spec.radius, "follows the egg")
			expect.near(dust.CFrame.LookVector.Z, -1, 1e-6)

			-- Far down the runway from the camera: no dust.
			session:fromServer("EggSpawned", eggData(session, 2, 4, "Common", 3))
			session:renderFrame(1 / 60)
			expect.equal(dustOf(parts, 2).Dust.Enabled, false)
		end)

		it("takes its dust color from the ground the egg is rolling on", function()
			local session, parts = startClient()
			-- A Forest egg that has rolled into the Snow.
			session:fromServer("EggSpawned", eggData(session, 1, 1, "Common", 100))
			session:fromServer("EggSpawned", eggData(session, 2, 1, "Common", 1))
			session:renderFrame(1 / 60)
			local snow = dustOf(parts, 1).Dust.Color.Keypoints[1].Value
			local forest = dustOf(parts, 2).Dust.Color.Keypoints[1].Value
			expect.truthy(snow.R > forest.R and snow.B > forest.B, "paler dust on snow than on grass")
		end)

		it("keeps an egg on the ground, and its dust going, when its rider gets off", function()
			local session, parts = startClient()
			local modules = shared(session)
			local egg = eggData(session, 1, 1, "Rare", 3)
			egg.rider = 999
			session:fromServer("EggSpawned", egg)
			session:renderFrame(1 / 60)
			local emitter = dustOf(parts, 1).Dust
			expect.equal(emitter.Enabled, true)

			session:fromServer("EggLeft", 1, 0)
			local shell = parts.eggFolder.Egg1.Shell
			for _ = 1, 60 do
				session:renderFrame(1 / 60)
				local position = shell.CFrame.Position
				local _, spec = eggCenter(session, egg)
				expect.near(position.Y, modules.Runway.surfaceY(position.Z) + spec.radius, 1e-3, "on the ground")
				expect.equal(emitter.Enabled, true)
			end
		end)

		it("stops the dust when an egg is removed and clears it once the puffs have faded", function()
			local session, parts = startClient()
			session:fromServer("EggSpawned", eggData(session, 1, 1, "Common", 3))
			session:fromServer("EggSpawned", eggData(session, 2, 1, "Common", 3, 10))
			session:renderFrame(1 / 60)
			local first, second = dustOf(parts, 1), dustOf(parts, 2)
			session:fromServer("EggRemoved", 1, "Cracked")
			session:fromServer("EggRemoved", 2, "Claimed", LOCAL_USER_ID)
			expect.equal(first.Dust.Enabled, false)
			expect.equal(second.Dust.Enabled, false)
			task.wait(0.9)
			expect.equal(#parts.dustFolder:GetChildren(), 0)
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

		it("lets a player jump on an egg the moment it appears", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common", 0)
			session:fromServer("EggSpawned", egg)
			jumpOnto(session, parts, egg)
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("RequestMount", "server").args[1], 1)
		end)

		it("does not try to mount an egg that is taken or someone else claimed", function()
			local session, parts = startClient()
			local taken = eggData(session, 1, 1, "Common")
			taken.rider = 999
			local claimed = eggData(session, 2, 1, "Common", 5, 10)
			claimed.owner = 999
			for _, egg in { taken, claimed } do
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

		it("celebrates a claim and keeps the rider rolling on the egg until they jump off", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			startRide(session, egg)
			session:renderFrame(1, 2)

			session:fromServer("EggClaimed", 1, LOCAL_USER_ID, "Common")
			session:fromServer("InventoryUpdated", 3)
			session:fromServer("StaminaChanged", 60, session.clock, 12, 100)
			session:renderFrame(1 / 60)

			local toast = hud(parts).Toast
			expect.equal(toast.Text, "CLAIMED! +1 Common egg")
			expect.equal(toast.Visible, true)
			expect.equal(labelOf(hud(parts).Wallet.Eggs).Text, "Eggs  3")

			-- Still on the egg, with a full meter that says so.
			expect.equal(parts.root.Anchored, true)
			local meters = hud(parts).Meters
			expect.equal(meters.Claim.Visible, true)
			expect.near(meters.Claim.Fill.Size.X.Scale, 1, 1e-6)
			expect.equal(labelOf(meters.Claim).Text, "Common Forest egg claimed!")
			expect.equal(meters.RideHint.Text, "In your inventory  -  keep rolling, or jump to leap off")
			expect.equal(parts.eggFolder.Egg1.Shell.Label:GetChildren()[2].Text, "Yours!")

			-- Long after the claim time, still riding: nothing runs out.
			session:renderFrame(1, 20)
			local center, spec = eggCenter(session, egg)
			expect.near(parts.root.CFrame.Position.Z, center.Z, 1e-2, "rider rolls with the egg")
			expect.near(parts.root.CFrame.Position.Y, center.Y + spec.radius + 2, 1e-2)
			expect.equal(labelOf(meters.Claim).Text, "Common Forest egg claimed!")

			-- Jump off.
			task.wait(0.6)
			session:heartbeat(1 / 60)
			session:fire(session:service("UserInputService"), "JumpRequest")
			expect.equal(#session:sent("RequestDismount", "server"), 1)
			expect.equal(parts.root.Anchored, false)
			expect.equal(meters.Claim.Visible, false)
		end)

		it("bounces an egg slightly before it cracks, and nobody can land on it meanwhile", function()
			local session, parts = startClient()
			local modules = shared(session)
			local egg = eggData(session, 1, 1, "Rare", 3)
			session:fromServer("EggSpawned", egg)
			session:renderFrame(1 / 60)
			local shell = parts.eggFolder.Egg1.Shell
			local emitter = parts.dustFolder.Dust1.Dust

			session:fromServer("EggLeft", 1, 0, session.clock)
			session:renderFrame(modules.Tuning.CRACK_BOUNCE_TIME / 2)
			local position = shell.CFrame.Position
			local _, spec = eggCenter(session, egg)
			local lift = position.Y - (modules.Runway.surfaceY(position.Z) + spec.radius)
			expect.near(lift, modules.Tuning.CRACK_BOUNCE_HEIGHT, 1e-2)
			expect.truthy(lift < 4, "only a slight bounce")
			expect.equal(emitter.Enabled, false, "no dust in the air")

			jumpOnto(session, parts, egg)
			session:heartbeat(1 / 60)
			expect.equal(#session:sent("RequestMount"), 0)

			session:fromServer("EggRemoved", 1, "Cracked")
			expect.truthy(parts.eggFolder:FindFirstChild("Splat"), "splat")
		end)

		it("drops an egg out of sight when it goes off the side", function()
			local session, parts = startClient()
			session:fromServer("EggSpawned", eggData(session, 1, 1, "Common", 3, 20))
			session:renderFrame(1 / 60)
			local shell = parts.eggFolder.Egg1.Shell
			local before = shell.CFrame.Position
			session:fromServer("EggRemoved", 1, "FellOff")
			local after = shell.CFrame.Position
			expect.truthy(after.Y < before.Y - 30, "falls")
			expect.truthy(after.X > before.X, "off the side it was on")
			task.wait(0.9)
			expect.falsy(parts.eggFolder:FindFirstChild("Egg1"))
		end)

		it("stuns a rider who is thrown off", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Rare")
			session:fromServer("EggSpawned", egg)
			startRide(session, egg, 9)

			session:fromServer("RideEnded", "ThrownOff", { eggId = 1, zone = 1, rarity = "Rare" })
			session:fromServer("EggLeft", 1, 0, session.clock)
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

	describe("Client: leaping", function()
		local function leapForce(parts)
			return parts.root:FindFirstChild("LeapForce")
		end

		it("launches a player into a floaty leap as soon as they step off the hub onto the runway", function()
			local session, parts = startClient()
			local tuning = shared(session).Tuning
			parts.root.Position = Vector3.new(0, 13, -5)
			session:heartbeat(1 / 60)
			expect.falsy(leapForce(parts), "still on the hub")

			parts.root.Position = Vector3.new(0, 13, 1)
			session:heartbeat(1 / 60)
			expect.equal(parts.root.AssemblyLinearVelocity.Y, tuning.LEAP_UP_SPEED)
			expect.truthy(parts.root.AssemblyLinearVelocity.Z >= tuning.LEAP_FORWARD_SPEED, "forward")
			local force = leapForce(parts)
			expect.truthy(force and force.Enabled, "lighter gravity")
			expect.near(force.Force.Y, 10 * session:service("Workspace").Gravity * (1 - tuning.LEAP_GRAVITY), 1e-3)
			expect.equal(parts.humanoid:GetState(), Enum.HumanoidStateType.Freefall)

			session:renderFrame(1 / 60)
			local leap = hud(parts).Leap
			expect.equal(leap.Visible, true)
			expect.truthy(leap.Text:match("^Land on an egg!  %d%.%d$"), leap.Text)
		end)

		it("kills a leaping player who touches the runway", function()
			local session, parts = startClient()
			local runway = shared(session).Runway
			parts.root.Position = Vector3.new(0, 40, 30)
			session:heartbeat(1 / 60)
			expect.equal(parts.humanoid.Health, 100)
			parts.root.Position = Vector3.new(0, runway.surfaceY(30) + 3, 30)
			session:heartbeat(1 / 60)
			expect.equal(parts.humanoid.Health, 0)
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Toast.Text, "Missed the egg!")
		end)

		it("kills a leaping player who has not landed on an egg in time", function()
			local session, parts = startClient()
			local tuning = shared(session).Tuning
			parts.root.Position = Vector3.new(0, 60, 30)
			session:heartbeat(1 / 60)
			task.wait(tuning.LEAP_TIME - 0.5)
			session:heartbeat(1 / 60)
			expect.equal(parts.humanoid.Health, 100)
			task.wait(0.6)
			session:heartbeat(1 / 60)
			expect.equal(parts.humanoid.Health, 0)
		end)

		it("waits for the answer to a landing before counting a touch of the runway", function()
			local session, parts = startClient()
			local runway = shared(session).Runway
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			jumpOnto(session, parts, egg)
			session:heartbeat(1 / 60)
			expect.truthy(session:lastSent("RequestMount", "server"), "asked to land")

			-- Slipped past the egg onto the runway while the server answers.
			local center = eggCenter(session, egg)
			parts.root.Position = Vector3.new(center.X, runway.surfaceY(center.Z) + 3, center.Z)
			session:heartbeat(1 / 60)
			expect.equal(parts.humanoid.Health, 100)
			startRide(session, egg)
			session:heartbeat(1 / 60)
			expect.equal(parts.humanoid.Health, 100)
			expect.equal(parts.root.Anchored, true)
			expect.equal(leapForce(parts).Enabled, false)
			expect.equal(hud(parts).Leap.Visible, false)
		end)

		it("leaps off an egg with time to land on another", function()
			local session, parts = startClient()
			local tuning = shared(session).Tuning
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			local userInput = session:service("UserInputService")
			startRide(session, egg)
			task.wait(0.4)
			session:heartbeat(1 / 60)
			session:fire(userInput, "JumpRequest")
			expect.equal(parts.root.AssemblyLinearVelocity.Y, tuning.LEAP_UP_SPEED)
			expect.truthy(leapForce(parts).Enabled, "floaty")
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Leap.Visible, true)
		end)

		it("dies at once on hitting a wall", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common", 3, 20)
			session:fromServer("EggSpawned", egg)
			startRide(session, egg)
			session:fromServer("RideEnded", "HitWall", { eggId = 1, zone = 1, rarity = "Common" })
			expect.equal(parts.humanoid.Health, 0)
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Toast.Text, "Hit the wall!")
		end)

		it("goes over the edge through a gap, and does not start a leap", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common", 3, 20)
			session:fromServer("EggSpawned", egg)
			startRide(session, egg)
			session:fromServer("RideEnded", "FellOff", { eggId = 1, zone = 1, rarity = "Common" })
			expect.equal(parts.root.Anchored, false)
			expect.truthy(parts.root.AssemblyLinearVelocity.X > 0, "off the side it was on")
			session:heartbeat(1 / 60)
			expect.falsy(leapForce(parts), "no leap")
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Toast.Text, "Off the edge!")
		end)
	end)

	describe("Client: the endless last zone", function()
		it("builds the repeat of the last zone past the end of the runway", function()
			local session = startClient()
			local runway = shared(session).Runway
			local endless = session:service("Workspace"):FindFirstChild("EndlessRunway")
			expect.truthy(endless, "Workspace.EndlessRunway")
			local grounds, walls, signs = 0, 0, {}
			for _, part in endless:GetChildren() do
				local position = part.CFrame.Position
				if part.Name == "Ground" then
					grounds += 1
					expect.truthy(part.Size.Z <= 2048, "within Roblox's part size limit")
				elseif part.Name == "Wall" then
					walls += 1
					expect.truthy(position.Z >= runway.LENGTH, "past the server's walls")
				elseif part.Name == "Sign" then
					table.insert(signs, position.Z)
				end
			end
			expect.truthy(grounds >= 2, "ground")
			expect.truthy(walls > 20, "walls")
			table.sort(signs)
			expect.near(signs[1], runway.FINAL_ZONE_START + runway.LOOP_LENGTH)
			expect.near(signs[2] - signs[1], runway.LOOP_LENGTH)
			expect.truthy(signs[#signs] > runway.LOOP_END + runway.LOOP_VIEW, "gates well past the loop")
		end)

		it("carries a leaping player back one loop at the end", function()
			local session, parts = startClient()
			local runway = shared(session).Runway
			-- (The stand-in keeps Position and CFrame apart; Roblox keeps them in step.)
			parts.root.Position = Vector3.new(4, 30, runway.LOOP_END + 1)
			parts.root.CFrame = CFrame.new(parts.root.Position)
			session:heartbeat(1 / 60)
			local position = parts.root.CFrame.Position
			expect.near(position.Z, runway.LOOP_START + 1, 1e-3)
			expect.near(position.Y, 30 + runway.LOOP_RISE, 1e-3)
			expect.near(position.X, 4, 1e-3)
			expect.equal(parts.humanoid.Health, 100)
		end)

		it("carries a rider and everything around them back one loop together, so nothing seems to move", function()
			local session, parts = startClient()
			local runway = shared(session).Runway
			-- The rider's Eternal egg (21 studs/s) is 10 studs from the end of the loop.
			local mineSpec = shared(session).EggSpec.get(5, "Eternal")
			local mine = eggData(session, 1, 5, "Eternal", (runway.LOOP_END - 10 - mineSpec.startZ) / 21, 0)
			-- Another egg (12 studs/s) has already been carried back, to just past the start of the loop.
			local otherSpec = shared(session).EggSpec.get(5, "Common")
			local other = eggData(session, 2, 5, "Common", (runway.LOOP_END + 20 - otherSpec.startZ) / 12, 10)
			session:fromServer("EggSpawned", mine)
			session:fromServer("EggSpawned", other)
			startRide(session, mine)
			local camera = session:service("Workspace").CurrentCamera
			-- One frame to sit the rider on their egg; from then on the camera follows them, as it would in the game.
			session:renderFrame(1 / 60)

			local otherShell = parts.eggFolder.Egg2.Shell
			local otherDust = parts.dustFolder.Dust2.Dust
			local echo = parts.dustFolder.Echo2.Dust
			local wrapped = false
			local lastGap = nil
			for _ = 1, 60 do
				camera.CFrame = CFrame.new(parts.root.CFrame.Position + Vector3.new(0, 10, -20))
				session:renderFrame(1 / 60)
				local rider = parts.root.CFrame.Position
				local otherZ = otherShell.CFrame.Position.Z
				-- The other egg is always drawn just ahead of the rider, closing in at 9 studs a second.
				local gap = otherZ - rider.Z
				expect.truthy(gap > 0 and gap < 35, "gap " .. gap)
				if lastGap then
					expect.near(gap, lastGap - 9 / 60, 0.05)
				end
				lastGap = gap
				-- Heights match too: both stay on the ground.
				expect.near(otherShell.CFrame.Position.Y, runway.surfaceY(otherZ) + otherSpec.radius, 1e-3)
				if rider.Z < runway.LOOP_START + 100 then
					wrapped = true
				elseif rider.Z > runway.LOOP_END - 60 then
					-- About to be carried back: the other egg's trail is also being laid one loop back.
					expect.equal(echo.Enabled, true)
				end
			end
			expect.truthy(wrapped, "the rider was carried back")
			expect.equal(session.emitted[otherDust], nil, "the other egg did not pop in")
			expect.equal(parts.humanoid.Health, 100)
		end)
	end)

	describe("Client: HUD", function()
		it("builds the HUD with Fusion", function()
			local _, parts = startClient()
			local root = hud(parts)
			for _, name in { "Cycle", "Zone", "Wallet", "Toast", "Announcement", "Leap", "Meters", "StudioTestPanel" } do
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
			session:fromServer("Announce", "Alex stole a Legendary egg from Sam!", { 255, 190, 40 })
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Toast.Text, "Alex stole a Legendary egg from Sam!")
			expect.equal(hud(parts).Toast.Visible, true)
		end)

		it("says where and when a Secret or rarer egg spawned", function()
			local session, parts = startClient()
			local banner = hud(parts).Announcement
			expect.equal(banner.Visible, false)

			local secret = eggData(session, 1, 3, "Secret", 0)
			session:fromServer("EggSpawned", secret)
			session:renderFrame(1 / 60)
			expect.equal(banner.Visible, true)
			expect.equal(banner.Title.Text, "SECRET EGG SPAWNED!")
			local date = os.date("*t", math.floor(secret.spawnTime))
			local hour = if date.hour % 12 == 0 then 12 else date.hour % 12
			local clock =
				string.format("%d:%02d:%02d %s", hour, date.min, date.sec, if date.hour < 12 then "AM" else "PM")
			expect.equal(banner.Detail.Text, `Start of the Snow zone at {clock}`)
			expect.equal(banner.BackgroundColor3, roblox.Color3.fromRGB(45, 45, 60))

			-- Other messages use the toast and do not hide it.
			session:fromServer("Announce", "Something else", nil)
			expect.equal(hud(parts).Toast.Text, "Something else")
			expect.equal(banner.Visible, true)

			session:fromServer("EggSpawned", eggData(session, 2, 5, "Eternal", 0))
			session:renderFrame(1 / 60)
			expect.equal(banner.Title.Text, "ETERNAL EGG SPAWNED!")
			expect.truthy(banner.Detail.Text:find("Start of the Volcano zone at ", 1, true) == 1, banner.Detail.Text)
		end)

		it("says nothing when an egg below Secret spawns", function()
			local session, parts = startClient()
			for index, rarity in { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } do
				session:fromServer("EggSpawned", eggData(session, index, 3, rarity, 0))
			end
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Announcement.Visible, false)
			expect.equal(hud(parts).Toast.Visible, false)
		end)

		it("does not announce rare eggs that were already rolling when the player joined", function()
			local probe = Studio.open(place, { isServer = false })
			local _, parts = startClient({
				{ id = 9, zone = 3, rarity = "Secret", spawnTime = probe.clock - 4, lateral = 0, bounces = 3 },
			})
			expect.truthy(parts.eggFolder:FindFirstChild("Egg9"))
			expect.equal(hud(parts).Announcement.Visible, false)
		end)
	end)
end
