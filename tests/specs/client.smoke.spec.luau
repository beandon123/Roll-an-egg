--!nocheck
-- Runs the real client script from the built place file against the stand-in for Roblox Studio (tests/studio):
-- egg drawing, the riding controller, and the Fusion HUD. As with the server smoke tests, this catches
-- misspelled properties and wiring mistakes, not how things look or feel.

local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Studio = require("../studio")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local place, reason = Studio.buildPlace()
	if place == nil then
		print(`SKIPPED client smoke tests: {reason}`)
		return
	end

	local LOCAL_USER_ID = 7

	-- One player's device, with the client script running. `eggs` is what the server's snapshot contains;
	-- `options.shop` and `options.settings` what the server says about the shop and the saved settings.
	local function startClient(eggs, options)
		local session = Studio.open(place, { isServer = false })
		session:createRemotes()
		local player, humanoid, root = session:addPlayer(LOCAL_USER_ID, "Me")
		local playerGui = session:setLocalPlayer(player)

		session.invokeHandlers.GetSnapshot = function()
			return {
				eggs = eggs or {},
				stamina = { value = 100, time = session.clock, rate = 12, max = 100 },
				agility = 14,
				inventory = {
					eggs = {
						{ uid = "a", zone = 1, rarity = "Common", kind = "Leafy", claimedAt = 0 },
						{ uid = "b", zone = 1, rarity = "Rare", kind = "Toadstool", claimedAt = 0 },
					},
					hatching = {},
					pets = {},
					penLevel = 1,
					eggCapacity = 2,
					petCapacity = 10,
					dollars = 0,
					income = 0,
					mount = "",
				},
				dollars = 0,
			}
		end
		session.invokeHandlers.GetShopState = function()
			return (options and options.shop) or { dollars = 0, penLevel = 1, passes = {}, luck = {} }
		end
		session.invokeHandlers.GetSettings = function()
			-- `settingsDelay` holds the reply back, like a server still loading the player's data.
			if options and options.settingsDelay then
				task.wait(options.settingsDelay)
			end
			return (options and options.settings) or {}
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
			Obstacles = session:require(folder.Obstacles),
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

	-- Where an egg is now: where its rider has it, or along its path round the obstacles.
	local function eggCenter(session, egg)
		local modules = shared(session)
		local spec = modules.EggSpec.get(egg.zone, egg.rarity)
		local startZ = modules.Runway.zoneStartZ(egg.zone) + modules.Tuning.EGG_SPAWN_OFFSET
		local z = modules.EggMotion.zAt(egg.spawnTime, startZ, spec.rollSpeed, session.clock)
		local x = egg.lateral
		if egg.rider == nil then
			local path = modules.Obstacles.planPath(
				egg.lateral,
				startZ,
				modules.Runway.fadeZ(egg.zone),
				spec.halfLength,
				spec.radius
			)
			x = modules.Obstacles.lateralAt(path, z)
		end
		return Vector3.new(x, modules.Runway.surfaceY(z) + spec.radius, z), spec
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
				if child:IsA("BasePart") and child ~= common.Root and child.Name ~= "Dust" then
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
				-- Everything but the root and the dust.
				return #model:GetChildren() - 2
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

		it("moves eggs down the runway every frame, steering round obstacles", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common", 5, 3)
			session:fromServer("EggSpawned", egg)
			session:renderFrame(1 / 60, 30)
			local expected = eggCenter(session, egg)
			local position = parts.eggFolder.Egg1.Root.CFrame.Position
			expect.near(position.Z, expected.Z, 1e-3, "z")
			expect.near(position.Y, expected.Y, 1e-3, "y")
			expect.near(position.X, expected.X, 1e-3, "x")

			-- Further on, it has steered round whatever was in its lane.
			session:renderFrame(1, 20)
			expected = eggCenter(session, egg)
			position = parts.eggFolder.Egg1.Root.CFrame.Position
			expect.near(position.X, expected.X, 1e-3, "x later")
		end)

		it("kicks up dust while rolling, coloured for the ground", function()
			local session, parts = startClient()
			session:fromServer("EggSpawned", eggData(session, 1, 2, "Common", 5, 0))
			-- Just dropped in: still in the air, so no dust yet.
			session:fromServer("EggSpawned", eggData(session, 2, 1, "Common", 0, 0))
			session:renderFrame(1 / 60)
			local rolling = parts.eggFolder.Egg1.Dust
			local emitter = rolling:FindFirstChildOfClass("ParticleEmitter")
			expect.truthy(emitter.Enabled, "dust while rolling")
			expect.equal(emitter.Color.Keypoints[1].Value, roblox.Color3.fromRGB(236, 208, 152), "desert sand")
			expect.near(rolling.CFrame.Position.Y, shared(session).Runway.BASE_Y + 0.2, 1e-3)
			expect.truthy(session.emitted[emitter] > 0, "a puff as it landed")
			local dropping = parts.eggFolder.Egg2.Dust:FindFirstChildOfClass("ParticleEmitter")
			expect.falsy(dropping.Enabled, "no dust in the air")
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
			session:fromServer("InventoryChanged", {
				eggs = {
					{ uid = "a", zone = 1, rarity = "Common", kind = "Leafy", claimedAt = 0 },
					{ uid = "b", zone = 1, rarity = "Rare", kind = "Toadstool", claimedAt = 0 },
					{ uid = "c", zone = 1, rarity = "Common", kind = "Leafy", claimedAt = 1 },
				},
				hatching = {},
				pets = {},
				penLevel = 1,
				eggCapacity = 2,
				petCapacity = 10,
				mount = "",
			})
			session:renderFrame(1 / 60)

			expect.equal(parts.root.Anchored, false)
			local toast = hud(parts).Toast
			expect.equal(toast.Text, "CLAIMED! +1 Leafy Egg")
			expect.equal(toast.Visible, true)
			expect.equal(hud(parts).Wallet.Eggs.Value.Text, "3")
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

		-- The first obstacle of a tier (and timing) in a zone.
		local function findObstacle(session, zoneId, tier, timed)
			for _, obstacle in shared(session).Obstacles.all() do
				if obstacle.zone == zoneId and obstacle.tier == tier and (obstacle.timing ~= nil) == timed then
					return obstacle
				end
			end
			error(`no {tier} obstacle in zone {zoneId}`)
		end

		-- Starts riding an egg lined up with an obstacle, a moment before it gets there.
		local function rideTowards(session, obstacle, rarity)
			local modules = shared(session)
			local spec = modules.EggSpec.get(obstacle.zone, rarity)
			local startZ = modules.Runway.zoneStartZ(obstacle.zone) + modules.Tuning.EGG_SPAWN_OFFSET
			local gap = obstacle.z - obstacle.hz - spec.radius - 1 - startZ
			local egg = eggData(session, 1, obstacle.zone, rarity, gap / spec.rollSpeed, obstacle.x)
			egg.rider = LOCAL_USER_ID
			session:fromServer("EggSpawned", egg)
			startRide(session, egg, spec.claimTime)
			return egg, spec
		end

		it("bumps into obstacles: reports the hit at once, knocks the egg clear and wobbles it", function()
			local session, parts = startClient()
			local bump = findObstacle(session, 1, "Bump", false)
			local _, spec = rideTowards(session, bump, "Rare")
			session:renderFrame(1 / 60, 20)
			local report = session:lastSent("ReportHit", "server")
			expect.truthy(report, "ReportHit")
			expect.equal(report.args[1], bump.id)
			expect.equal(#session:sent("ReportHit", "server"), 1, "once")
			expect.truthy(string.find(hud(parts).Toast.Text, "^Bumped into "), hud(parts).Toast.Text)
			local x = session:service("Workspace").Eggs.Egg1.Root.CFrame.Position.X
			expect.truthy(math.abs(x - bump.x) >= bump.hx + spec.halfLength, "knocked clear")
			expect.equal(parts.root.Anchored, true, "still riding")
		end)

		it("is thrown off by a KnockOff obstacle", function()
			local session, parts = startClient()
			local rock = findObstacle(session, 1, "KnockOff", false)
			rideTowards(session, rock, "Rare")
			session:renderFrame(1 / 60, 20)
			expect.equal(session:lastSent("ReportHit", "server").args[1], rock.id)
			expect.truthy(string.find(hud(parts).Toast.Text, "^Knocked off by "), hud(parts).Toast.Text)
			expect.equal(parts.root.Anchored, false)
			expect.equal(parts.humanoid.PlatformStand, true, "stunned")
			-- The server's word arriving afterwards changes nothing.
			session:fromServer("RideEnded", "KnockedOff", { eggId = 1, zone = 1, rarity = "Rare" })
			expect.truthy(string.find(hud(parts).Toast.Text, "^Knocked off by "), "no second toast")
		end)

		it("follows the server when it spots a hit first", function()
			local session, parts = startClient()
			local bump = findObstacle(session, 1, "Bump", false)
			local egg = eggData(session, 1, 1, "Rare", 1, 0)
			egg.rider = LOCAL_USER_ID
			session:fromServer("EggSpawned", egg)
			startRide(session, egg, 9)
			session:fromServer("ObstacleHit", bump.id, "Bump", 21)
			session:renderFrame(1 / 60)
			expect.near(session:service("Workspace").Eggs.Egg1.Root.CFrame.Position.X, 21, 1e-3)
			expect.truthy(string.find(hud(parts).Toast.Text, "^Bumped into "), hud(parts).Toast.Text)
			expect.equal(#session:sent("ReportHit"), 0)
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

	describe("Client: eggs and pets", function()
		local function panel(parts)
			return hud(parts).Inventory
		end

		local function state(extra)
			local base = {
				eggs = {
					{ uid = "a", zone = 1, rarity = "Common", kind = "Leafy", claimedAt = 0 },
					{ uid = "b", zone = 1, rarity = "Rare", kind = "Toadstool", claimedAt = 0 },
				},
				hatching = {},
				pets = {},
				penLevel = 1,
				eggCapacity = 2,
				petCapacity = 10,
				dollars = 0,
				income = 0,
				mount = "",
			}
			for key, value in extra or {} do
				base[key] = value
			end
			return base
		end

		local function pet(uid, kind, rarity, variant, inPen)
			return {
				uid = uid,
				kind = kind,
				egg = kind,
				zone = 1,
				rarity = rarity,
				variant = variant or "Normal",
				inPen = inPen or false,
				hatchedAt = 0,
			}
		end

		-- Builds plot 1 on this device as the server would, owned by the local player.
		local function ownPlot(session)
			local PlotModels = session:require(session:service("ServerScriptService").Server.Map.PlotModels)
			local map = roblox.Instance.new("Folder")
			map.Name = "Map"
			local plots = roblox.Instance.new("Folder")
			plots.Name = "Plots"
			plots.Parent = map
			map.Parent = session:service("Workspace")
			local plot = PlotModels.buildPlot(plots, 1)
			plot:SetAttribute("Owner", LOCAL_USER_ID)
			return plot, PlotModels
		end

		it("puts an egg down from the Eggs tab, but only in the player's own pen", function()
			local session, parts = startClient()
			ownPlot(session)
			local Plots = session:require(session:service("ReplicatedStorage").Shared.Plots)
			local tabs = hud(parts).SideTabs
			expect.equal(tabs.EggsTab.Badge.Text, "2")
			expect.equal(panel(parts).Visible, false)

			session:fire(tabs.EggsTab, "Activated")
			expect.equal(panel(parts).Visible, true)
			expect.equal(panel(parts).Title.Text, "Your eggs (2)")
			local cards = panel(parts).List.EggsPage.Eggs
			expect.equal(cards.Egg_a.Title.Text, "Leafy Egg")
			session:renderFrame(1 / 60)
			local preview = panel(parts).Preview
			expect.truthy(preview:FindFirstChildOfClass("Model"), "egg in the preview")
			expect.truthy(preview:FindFirstChildOfClass("Camera"), "preview camera")

			-- Out in the plaza: not yet.
			session:fire(cards.Egg_b.Place, "Activated")
			expect.equal(#session:sent("PlaceEgg"), 0)
			expect.truthy(string.find(hud(parts).Toast.Text, "Walk into your pen"), hud(parts).Toast.Text)
			-- In the pen: asks the server.
			local x, z = Plots.point(1, 25, 0)
			parts.root.CFrame = roblox.CFrame.new(x, 13, z)
			session:fire(cards.Egg_b.Place, "Activated")
			expect.equal(session:lastSent("PlaceEgg", "server").args[1], "b")

			-- Full: the device says so without asking.
			session:fromServer(
				"InventoryChanged",
				state({
					hatching = {
						{
							uid = "x",
							zone = 1,
							rarity = "Common",
							kind = "Leafy",
							placedAt = 0,
							bonus = 0,
							inward = 9,
							along = 0,
						},
						{
							uid = "y",
							zone = 1,
							rarity = "Common",
							kind = "Leafy",
							placedAt = 0,
							bonus = 0,
							inward = 20,
							along = 0,
						},
					},
				})
			)
			session:fire(cards.Egg_a.Place, "Activated")
			expect.equal(#session:sent("PlaceEgg"), 1)
			expect.truthy(string.find(hud(parts).Toast.Text, "only hatch 2 eggs"), hud(parts).Toast.Text)
		end)

		it("shows hatching eggs counting down, and every pet, in the Pets tab", function()
			local session, parts = startClient()
			session:fromServer(
				"InventoryChanged",
				state({
					hatching = {
						{
							uid = "n",
							zone = 1,
							rarity = "Common",
							kind = "Leafy",
							placedAt = session.clock - 10,
							bonus = 0,
							inward = 20,
							along = 0,
						},
					},
					pets = { pet("p", "Bear", "Epic", "Gold", true), pet("q", "Fox", "Uncommon") },
				})
			)
			session:fromServer("PetHatched", pet("r", "Owl", "Rare", "Rainbow"))
			expect.equal(hud(parts).Toast.Text, "Your Rainbow Owl hatched! (Rainbow Rare)")
			expect.equal(hud(parts).SideTabs.PetsTab.Badge.Text, "1")

			session:fire(hud(parts).SideTabs.PetsTab, "Activated")
			expect.equal(hud(parts).SideTabs.PetsTab.Badge.Visible, false, "seen")
			session:renderFrame(1 / 60)
			local page = panel(parts).List.PetsPage
			expect.equal(page.Hatching.Egg_n.Title.Text, "Leafy Egg")
			expect.equal(page.Hatching.Egg_n.Bar.Time.Text, "20s left")
			expect.truthy(page.Hatching:FindFirstChild("Free2"), "room for another egg")
			expect.equal(page.PetsHeader.Count.Text, "Pets (2) - in pen 1 of 10")
			local card = page.Pets.Pet_p
			expect.equal(card.Title.Text, "Bear")
			expect.equal(card.Rarity.Text, "Gold Epic")
			expect.equal(card.Income.Text, "$20/s")
			expect.equal(card.Pen.Text, "In pen")
			expect.equal(page.Pets.Pet_q.Pen.Text, "Put in pen")
			expect.truthy(panel(parts).Preview:FindFirstChildOfClass("Model"), "pet in the preview")

			-- The free spot's button jumps to the eggs.
			session:fire(page.Hatching.Free2.Fill, "Activated")
			expect.equal(panel(parts).Title.Text, "Your eggs (2)")
		end)

		it("puts pets in or out of the pen, equips the best, sells (after asking) and rides them", function()
			local session, parts = startClient()
			session:fromServer(
				"InventoryChanged",
				state({ pets = { pet("p", "Bear", "Epic", "Normal", true), pet("q", "Fox", "Uncommon") } })
			)
			session:fire(hud(parts).SideTabs.PetsTab, "Activated")
			local page = panel(parts).List.PetsPage
			session:fire(page.Pets.Pet_q.Pen, "Activated")
			local sent = session:lastSent("SetInPen", "server")
			expect.equal(sent.args[1], "q")
			expect.equal(sent.args[2], true)
			session:fire(page.Pets.Pet_p.Pen, "Activated")
			expect.equal(session:lastSent("SetInPen", "server").args[2], false)
			session:fire(page.PetsHeader.EquipBest, "Activated")
			expect.equal(#session:sent("EquipBest", "server"), 1)

			-- Selling takes two taps.
			expect.equal(page.Pets.Pet_q.Sell.Text, "$240")
			session:fire(page.Pets.Pet_q.Sell, "Activated")
			expect.equal(#session:sent("SellPet"), 0)
			expect.equal(page.Pets.Pet_q.Sell.Text, "Sure?")
			session:fire(page.Pets.Pet_q.Sell, "Activated")
			expect.equal(session:lastSent("SellPet", "server").args[1], "q")

			-- Riding: the card's button chooses the pet, and a Ride button appears under the tabs.
			local tabs = hud(parts).SideTabs
			expect.equal(tabs.RideTab.Visible, false)
			session:fire(page.Pets.Pet_p.Ride, "Activated")
			expect.equal(session:lastSent("RidePet", "server").args[1], "p")
			session:fromServer(
				"InventoryChanged",
				state({ pets = { pet("p", "Bear", "Epic", "Normal", true) }, mount = "p" })
			)
			session:fromServer("MountChanged", "p", 30)
			expect.equal(tabs.RideTab.Visible, true)
			expect.equal(tabs.RideTab.Text, "GET OFF")
			session:fire(tabs.RideTab, "Activated")
			expect.equal(session:lastSent("RidePet", "server").args[1], "")
			session:fromServer("MountChanged", "", 0)
			expect.equal(tabs.RideTab.Text, "RIDE")
			session:fire(tabs.RideTab, "Activated")
			expect.equal(session:lastSent("RidePet", "server").args[1], "p")

			-- The server's messages show as toasts.
			session:fromServer("Notice", "Sold Fox for $240", { 120, 230, 120 })
			expect.equal(hud(parts).Toast.Text, "Sold Fox for $240")
		end)

		it("counts down over eggs in the pens and bursts them open when they hatch", function()
			local session = startClient()
			local plot, PlotModels = ownPlot(session)
			local egg = PlotModels.buildEgg(plot.Eggs, 1, {
				uid = "e",
				kind = "Leafy",
				rarity = "Common",
				placedAt = session.clock - 15,
				bonus = 0,
				inward = 20,
				along = 0,
			})
			egg:SetAttribute("EggName", "Leafy Egg")

			session:renderFrame(1 / 60)
			local board = egg.Board.Countdown
			expect.equal(board.Title.Text, "Leafy Egg")
			expect.equal(board.Bar.Time.Text, "15s")
			expect.near(board.Bar.Fill.Size.X.Scale, 0.5, 0.01)

			egg:SetAttribute("HatchedAt", session.clock)
			task.wait(0.25)
			session:renderFrame(1 / 60)
			local burst = session:service("Workspace"):FindFirstChild("HatchBurst")
			expect.truthy(burst, "burst")
			local total = 0
			for _, emitter in burst:GetChildren() do
				total += session.emitted[emitter] or 0
			end
			expect.truthy(total > 0, "shells and sparkles")
		end)

		it("walks each pen's pets round it, in their variants, and shows the upgrade button to its owner", function()
			local session = startClient()
			local plot, PlotModels = ownPlot(session)
			local Plots = session:require(session:service("ReplicatedStorage").Shared.Plots)
			local workspace = session:service("Workspace")
			local other = PlotModels.buildPlot(plot.Parent, 2)
			other:SetAttribute("Owner", 99)
			plot:SetAttribute("Pets", "Squirrel:Gold,Bear:Normal")
			local camera = roblox.Instance.new("Camera")
			local x, z = Plots.center(1)
			camera.CFrame = roblox.CFrame.new(x, 40, z + 60)
			camera.Parent = workspace
			workspace.CurrentCamera = camera

			session:renderFrame(1 / 60)
			local pets = workspace.PenPets:GetChildren()
			expect.equal(#pets, 2)
			local gold
			for _, model in pets do
				if model.Name == "Squirrel" then
					gold = model
				end
			end
			expect.equal(gold:GetAttribute("Variant"), "Gold")
			local function inside(model)
				local position = model.PrimaryPart.CFrame.Position
				local inward, along = Plots.toLocal(1, position.X, position.Z)
				return Plots.inPen(1, inward, along, 0)
			end
			local before = {}
			for _, model in pets do
				expect.truthy(inside(model), model.Name .. " in the pen")
				before[model] = model.PrimaryPart.CFrame.Position
			end
			session:renderFrame(1 / 10, 80)
			local moved = 0
			for _, model in pets do
				expect.truthy(inside(model), model.Name .. " still in the pen")
				if (model.PrimaryPart.CFrame.Position - before[model]).Magnitude > 1 then
					moved += 1
				end
				expect.truthy(model:GetAttribute("Move"), "animated")
			end
			expect.truthy(moved > 0, "they wander")
			expect.equal(plot.UpgradeButton.Pad.Upgrade.Enabled, true, "own button")
			expect.equal(other.UpgradeButton.Pad.Upgrade.Enabled, false, "someone else's")

			-- A bigger pen gives them more room; an empty list empties it.
			plot:SetAttribute("PenLevel", 3)
			session:renderFrame(1 / 60)
			expect.equal(#workspace.PenPets:GetChildren(), 2)
			plot:SetAttribute("Pets", "")
			session:renderFrame(1 / 60)
			expect.equal(#workspace.PenPets:GetChildren(), 0)
		end)

		it("walks ridden pets when their riders move", function()
			local session, parts = startClient()
			local PetRig = session:require(session:service("ReplicatedStorage").Shared.PetRig)
			local workspace = session:service("Workspace")
			local mounts = roblox.Instance.new("Folder")
			mounts.Name = "Mounts"
			mounts.Parent = workspace
			local ridden = PetRig.build("Fox")
			ridden:SetAttribute("Rider", LOCAL_USER_ID)
			ridden.Parent = mounts
			session:renderFrame(1 / 60)
			expect.equal(ridden:GetAttribute("Move"), "Idle")
			parts.root.AssemblyLinearVelocity = Vector3.new(0, 0, 20)
			session:renderFrame(1 / 60)
			expect.equal(ridden:GetAttribute("Move"), "Walk")
		end)
	end)

	describe("Client: the world", function()
		it("animates geysers, lava vents and clams in time with the server", function()
			local session = startClient()
			local Obstacles = shared(session).Obstacles
			local Scenery = session:require(session:service("ServerScriptService").Server.Map.Scenery)
			local map = roblox.Instance.new("Folder")
			map.Name = "Map"
			local folder = roblox.Instance.new("Folder")
			folder.Name = "Obstacles"
			folder.Parent = map
			map.Parent = session:service("Workspace")
			local function first(kind)
				for _, obstacle in Obstacles.all() do
					if obstacle.kind == kind then
						return obstacle
					end
				end
			end
			local geyser, clam = first("LavaVent"), first("GiantClam")
			local vent = Scenery.buildObstacle(folder, geyser)
			local shell = Scenery.buildObstacle(folder, clam)

			-- A moment in the middle of a phase.
			local function during(obstacle, activity)
				local base = session.clock
				for tenth = 0, 200 do
					local t = base + tenth / 10
					if
						Obstacles.activity(obstacle, t - 0.15) == activity
						and Obstacles.activity(obstacle, t + 0.15) == activity
					then
						return t
					end
				end
				error("no " .. activity)
			end

			session.clock = during(geyser, "Active") - 1 / 60
			session:renderFrame(1 / 60)
			expect.truthy(vent.Burst.Transparency < 1, "lava shooting up")
			expect.truthy(vent.Burst:FindFirstChildOfClass("PointLight").Enabled, "glowing")
			session.clock = during(geyser, "Warning") - 1 / 60
			session:renderFrame(1 / 60)
			expect.equal(vent.Burst.Transparency, 1)
			expect.truthy(vent.Vent.WarnPoint.Warn.Enabled, "smoking as a warning")
			session.clock = during(geyser, "Idle") - 1 / 60
			session:renderFrame(1 / 60)
			expect.falsy(vent.Vent.WarnPoint.Warn.Enabled)

			-- The clam snaps shut while active, and gapes open otherwise.
			session.clock = during(clam, "Active") - 1 / 60
			session:renderFrame(1 / 60)
			expect.near(shell.Lid.CFrame.UpVector.Y, 1, 1e-3, "shut")
			session.clock = during(clam, "Idle") - 1 / 60
			session:renderFrame(1 / 60)
			expect.truthy(shell.Lid.CFrame.UpVector.Y < 0.6, "open")
		end)

		it("turns day to night with the runway cycle", function()
			local session = startClient()
			local Lighting = session:service("Lighting")
			local CycleClock = session:require(session:service("ReplicatedStorage").Shared.CycleClock)
			local cycleStart = math.floor(session.clock / 180) * 180 + 180
			session.clock = cycleStart - 1 / 60
			session:renderFrame(1 / 60)
			expect.near(Lighting.ClockTime, CycleClock.SUNRISE, 1e-3)
			session.clock = cycleStart + 63 - 1 / 60
			session:renderFrame(1 / 60)
			expect.near(Lighting.ClockTime, 12, 1e-3)
			local noonBrightness = Lighting.Brightness
			session.clock = cycleStart + 126 + 27 - 1 / 60
			session:renderFrame(1 / 60)
			expect.near(Lighting.ClockTime, 0, 1e-3)
			expect.truthy(Lighting.Brightness < noonBrightness, "darker at night")
		end)
	end)

	describe("Client: HUD", function()
		it("animates rigged pets: winged ones hover, beating their wings, and play the move they are given", function()
			local session = startClient()
			local workspace = session:service("Workspace")
			local PetRig = session:require(session:service("ReplicatedStorage").Shared.PetRig)
			-- Pets spawned from the admin panel.
			local folder = roblox.Instance.new("Folder")
			folder.Name = "AdminPets"
			folder.Parent = workspace
			session:fire(workspace, "ChildAdded", folder)
			local phoenix = PetRig.build("LavaDragon")
			phoenix.Parent = folder
			session:fire(folder, "DescendantAdded", phoenix)
			local fox = PetRig.build("Fox")
			fox.Parent = folder
			session:fire(folder, "DescendantAdded", fox)

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

		it("animates the pets in the Model Showroom, but not ones too far away to see", function()
			local session = startClient()
			local workspace = session:service("Workspace")
			local PetRig = session:require(session:service("ReplicatedStorage").Shared.PetRig)
			-- The showroom keeps its pets a few folders deep, next to eggs (which are not pets).
			local showroom = roblox.Instance.new("Folder")
			showroom.Name = "Showroom"
			local imported = roblox.Instance.new("Folder")
			imported.Name = "Roll an Egg Pets"
			imported.Parent = showroom
			local forest = roblox.Instance.new("Folder")
			forest.Name = "Forest"
			forest.Parent = imported
			local near = PetRig.build("Fox")
			near.Parent = forest
			local far = PetRig.build("Bear")
			far:PivotTo(roblox.CFrame.new(0, 0, 2000))
			far.Parent = forest
			local egg = roblox.Instance.new("Model")
			egg.Name = "Leafy Egg"
			egg.Parent = forest
			showroom.Parent = workspace
			session:fire(workspace, "ChildAdded", showroom)

			session:renderFrame(0.1, 3)
			local leg = near.Body.FrontLeftLeg.Transform
			session:renderFrame(0.1)
			expect.truthy(near.Body.FrontLeftLeg.Transform ~= leg, "the Fox walks on the spot")
			local ok = pcall(function()
				return far.Body.FrontLeftLeg.Transform
			end)
			expect.falsy(ok, "the Bear, 2,000 studs away, was never moved")
		end)

		it("builds the HUD with Fusion", function()
			local session, parts = startClient()
			local root = hud(parts)
			for _, name in { "Cycle", "Zone", "Luck", "Tabs", "Wallet", "Toast", "Meters" } do
				expect.truthy(root:FindFirstChild(name), name)
			end
			expect.truthy(root.Meters.Claim and root.Meters.Stamina and root.Meters.RideHint, "meters")
			expect.truthy(root.Tabs.Shop and root.Tabs.Settings, "tabs")
			expect.equal(root.Wallet.Eggs.Value.Text, "2")
			expect.equal(root.Wallet.Dollars.Value.Text, "0")
			expect.equal(root.Wallet.Stamina.Value.Text, "100")
			session:fromServer("DollarsChanged", 1520, 12)
			expect.equal(root.Wallet.Dollars.Value.Text, "1.52K  +12/s")
			-- Nothing open, and no luck boost running.
			expect.equal(root.ShopPanel.Visible, false)
			expect.equal(root.SettingsPanel.Visible, false)
			expect.equal(root.Backdrop.Visible, false)
			expect.equal(root.Luck.Visible, false)
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

		it("shows a running event and follows the runway cycle when admins move it on", function()
			local session, parts = startClient()
			local workspace = session:service("Workspace")
			local cycle = hud(parts).Cycle
			workspace:SetAttribute("ServerEvent", "Avalanche")
			session:renderFrame(1 / 60)
			expect.truthy(labelOf(cycle).Text:match("^Egg Avalanche!  Runway closes in"), labelOf(cycle).Text)
			-- The stand-in clock starts 5 s into a cycle: 165 s on, the runway has closed.
			workspace:SetAttribute("CycleOffset", 165.5)
			session:renderFrame(1 / 60)
			expect.truthy(labelOf(cycle).Text:match("^Runway closed"), labelOf(cycle).Text)
		end)

		it("names the Model Showroom as the place the player is in", function()
			local session, parts = startClient()
			parts.root.Position = Vector3.new(-3000, 13, 0)
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Zone.Text, "Model Showroom")
		end)

		it("shows server announcements", function()
			local session, parts = startClient()
			session:fromServer("Announce", "A Legendary egg just dropped in the Forest!", { 255, 190, 40 })
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Toast.Text, "A Legendary egg just dropped in the Forest!")
			expect.equal(hud(parts).Toast.Visible, true)
		end)
	end)

	describe("Client: admin panel", function()
		-- A client whose player is an admin, with the server's answers to admin commands faked: every command is
		-- recorded in `sent`, and answered with `answer` (ok, message, data) if set.
		local function startAdmin()
			local session, parts = startClient()
			local sent = {}
			local answer = { true, "Done." }
			session.invokeHandlers.AdminCommand = function(command, args)
				table.insert(sent, { command = command, args = args })
				return table.unpack(answer)
			end
			parts.player:SetAttribute("IsAdmin", true)
			session:renderFrame(1 / 60)
			return session, parts, sent, answer
		end

		local function panel(parts)
			return parts.playerGui.AdminPanel.Root
		end

		local function click(session, button)
			session:fire(button, "Activated")
			session:renderFrame(1 / 60)
		end

		local function body(parts)
			return panel(parts).Window.Body
		end

		it("shows only to admins, behind an ADMIN button", function()
			local session, parts = startClient()
			session:renderFrame(1 / 60)
			local gui = parts.playerGui:FindFirstChild("AdminPanel")
			expect.truthy(gui, "the panel is built")
			expect.equal(gui.Enabled, false, "but hidden from players who are not admins")

			parts.player:SetAttribute("IsAdmin", true)
			session:renderFrame(1 / 60)
			expect.equal(gui.Enabled, true)
			expect.equal(gui.Root.Window.Visible, false, "closed until the button is pressed")
			click(session, gui.Root.Toggle)
			expect.equal(gui.Root.Window.Visible, true)
			click(session, gui.Root.Window.Close)
			expect.equal(gui.Root.Window.Visible, false)
		end)

		it("drops and gives eggs from any zone, and shows the server's answer", function()
			local session, parts, sent, answer = startAdmin()
			click(session, panel(parts).Toggle)
			local list = body(parts).EggList
			expect.truthy(list:FindFirstChild("MossStag"), "the Forest's eggs are listed")
			expect.equal(list.MossStag.Title.Text, "Moss Stag Egg")
			expect.equal(list.MossStag.Rarity.Text, "Legendary")

			click(session, list.MossStag.Drop)
			expect.equal(sent[#sent].command, "DropEgg")
			expect.equal(sent[#sent].args.egg, "MossStag")
			expect.equal(sent[#sent].args.where, "Here")
			expect.equal(panel(parts).Window.StatusLine.Text, "Done.")

			-- Pick the Desert, and drop at the chute.
			click(session, body(parts).Zone.Zones.Desert)
			expect.equal(body(parts).EggList:FindFirstChild("MossStag"), nil, "the Forest's eggs are gone")
			click(session, body(parts).Where.DropWhere.Chute)
			click(session, body(parts).EggList.Sphinx.Drop)
			expect.equal(sent[#sent].args.egg, "Sphinx")
			expect.equal(sent[#sent].args.where, "Chute")

			answer[1], answer[2] = false, "Your data has not loaded yet."
			click(session, body(parts).EggList.Sphinx.Give)
			expect.equal(sent[#sent].command, "GiveEgg")
			expect.equal(panel(parts).Window.StatusLine.Text, "Your data has not loaded yet.")

			click(session, body(parts).WholeZone.Buttons.DropAll)
			expect.equal(sent[#sent].command, "DropZoneEggs")
			expect.equal(sent[#sent].args.zone, 2)
			click(session, body(parts).WholeZone.Buttons.ClearRunway)
			expect.equal(sent[#sent].command, "ClearRunway")
		end)

		it("spawns and gives pets", function()
			local session, parts, sent = startAdmin()
			click(session, panel(parts).Toggle)
			click(session, panel(parts).Window.Tabs.Pets)
			click(session, body(parts).Zone.Zones.Volcano)
			local row = body(parts).PetList.LavaDragon
			expect.equal(row.Title.Text, "Lava Dragon")
			click(session, row.Spawn)
			expect.equal(sent[#sent].command, "SpawnPet")
			expect.equal(sent[#sent].args.pet, "LavaDragon")
			click(session, row.Give)
			expect.equal(sent[#sent].command, "GivePet")
			click(session, body(parts).PetActions.Buttons.ShowZone)
			expect.equal(sent[#sent].command, "ShowZonePets")
			expect.equal(sent[#sent].args.zone, 5)
		end)

		it("flies, sets speeds and stamina, and lists the inventory", function()
			local session, parts, sent, answer = startAdmin()
			answer[3] = {
				eggs = { { kind = "MossStag", name = "Moss Stag Egg", zone = 1, rarity = "Legendary", count = 3 } },
				pets = { { kind = "Fox", name = "Fox", zone = 1, rarity = "Uncommon", count = 1 } },
				eggCount = 3,
				petCount = 1,
			}
			click(session, panel(parts).Toggle)
			click(session, panel(parts).Window.Tabs.Me)
			expect.equal(sent[#sent].command, "GetInventory", "opening the tab loads the inventory")
			local lines = body(parts).Inventory.Lines
			expect.equal(lines.Summary.Text, "3 eggs, 1 pet")
			expect.equal(lines.Line1.Text, "Moss Stag Egg  x3")
			expect.equal(lines.Line2.Text, "Fox  x1")

			local toggle = body(parts).Flight.FlyToggle
			expect.equal(toggle.Text, "Fly")
			click(session, toggle)
			expect.equal(sent[#sent].command, "SetFlying")
			expect.equal(sent[#sent].args.on, true)
			-- The server answers by setting the attribute; the button follows it.
			parts.player:SetAttribute("Flying", true)
			session:renderFrame(1 / 60)
			expect.equal(body(parts).Flight.FlyToggle.Text, "Flying: tap to land")

			click(session, body(parts).Flight.FlySpeed["160"])
			expect.equal(sent[#sent].command, "SetFlySpeed")
			expect.equal(sent[#sent].args.speed, 160)
			click(session, body(parts).Walking.WalkSpeed["64"])
			expect.equal(sent[#sent].args.speed, 64)
			click(session, body(parts).Stamina.Buttons.Max)
			expect.equal(sent[#sent].command, "Stamina")
			expect.equal(sent[#sent].args.action, "Max")
			local dollars = body(parts).Dollars.Buttons
			expect.equal(dollars.Add1000000.Text, "+$1M")
			click(session, dollars.Add1000000)
			expect.equal(sent[#sent].command, "Dollars")
			expect.equal(sent[#sent].args.amount, 1e6)
			click(session, dollars.Reset)
			expect.equal(sent[#sent].args.action, "Reset")
			click(session, body(parts).Inventory.Buttons.HatchNow)
			expect.equal(sent[#sent].command, "HatchNow")
			click(session, body(parts).Inventory.Buttons.ClearEggs)
			expect.equal(sent[#sent].command, "ClearInventory")
			expect.equal(sent[#sent].args.what, "Eggs")
		end)

		it("starts events, moves the runway cycle on, and teleports", function()
			local session, parts, sent = startAdmin()
			click(session, panel(parts).Toggle)
			click(session, panel(parts).Window.Tabs.Events)
			expect.equal(body(parts).Events.Status.Text, "No event running.")
			click(session, body(parts).Events.Buttons.StartAvalanche)
			expect.equal(sent[#sent].command, "StartEvent")
			expect.equal(sent[#sent].args.event, "Avalanche")
			session:service("Workspace"):SetAttribute("ServerEvent", "Avalanche")
			session:renderFrame(1 / 60)
			expect.equal(body(parts).Events.Status.Text, "Running: Egg Avalanche, until the runway closes")
			click(session, body(parts).Runway.Buttons.CloseRunway)
			expect.equal(sent[#sent].command, "CloseRunway")
			click(session, body(parts).Luck.Buttons.Luck4)
			expect.equal(sent[#sent].command, "StartLuck")
			expect.equal(sent[#sent].args.multiplier, 4)
			click(session, body(parts).Luck.Buttons.StopLuck)
			expect.equal(sent[#sent].command, "StopLuck")

			click(session, panel(parts).Window.Tabs.Teleport)
			click(session, body(parts).Places.Buttons.Showroom)
			expect.equal(sent[#sent].command, "Teleport")
			expect.equal(sent[#sent].args.to, "Showroom")
			click(session, body(parts).Zones.Buttons.Ocean)
			expect.equal(sent[#sent].args.to, "Zone")
			expect.equal(sent[#sent].args.zone, 4)
			expect.truthy(body(parts).Players:FindFirstChild("Nobody"), "nobody else to go to yet")

			local friend = roblox.Instance.new("Player")
			friend.Name = "Friend"
			friend.UserId = 99
			friend.Parent = session:service("Players")
			session:fire(session:service("Players"), "PlayerAdded", friend)
			session:renderFrame(1 / 60)
			click(session, body(parts).Players.Friend.GoTo)
			expect.equal(sent[#sent].command, "TeleportToPlayer")
			expect.equal(sent[#sent].args.userId, 99)
		end)
	end)

	describe("Client: flight", function()
		local function flyVelocity(parts)
			return parts.root:FindFirstChild("FlyVelocity")
		end

		it("flies where the camera looks while the Flying attribute is set, and lands when it is cleared", function()
			local session, parts = startClient()
			session:renderFrame(1 / 60)
			expect.equal(flyVelocity(parts), nil, "walking to start with")

			parts.player:SetAttribute("Flying", true)
			session:renderFrame(1 / 60)
			expect.truthy(flyVelocity(parts), "a LinearVelocity carries the character")
			expect.truthy(parts.root:FindFirstChild("FlyGyro"), "an AlignOrientation keeps it upright")
			expect.equal(parts.humanoid.PlatformStand, true)

			-- The camera looks down the runway (+Z); pushing forward flies that way.
			session.moveVector = Vector3.new(0, 0, -1)
			session:renderFrame(0.1, 20)
			local velocity = flyVelocity(parts).VectorVelocity
			expect.truthy(velocity.Z > 70, "flying forward at about the default 80: " .. tostring(velocity))
			session.moveVector = Vector3.zero
			session.keysDown[Enum.KeyCode.Space] = true
			session:renderFrame(0.1, 20)
			expect.truthy(flyVelocity(parts).VectorVelocity.Y > 70, "rising")
			session.keysDown[Enum.KeyCode.Space] = nil

			parts.player:SetAttribute("Flying", false)
			session:renderFrame(1 / 60)
			expect.equal(flyVelocity(parts), nil, "landed")
			expect.equal(parts.humanoid.PlatformStand, false)
		end)

		it("lets go of the character while it rides an egg", function()
			local session, parts = startClient()
			parts.player:SetAttribute("Flying", true)
			session:renderFrame(1 / 60)
			expect.truthy(flyVelocity(parts))
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			startRide(session, egg)
			session:renderFrame(1 / 60)
			expect.equal(flyVelocity(parts), nil, "the ride holds the character, not flight")
		end)
	end)

	-- The shop panel's scrolling body, and a button's text.
	local function shopBody(parts)
		return hud(parts).ShopPanel.Body.Scroll
	end
	local function buttonText(button)
		return button.Face.Label.Text
	end

	describe("Client: shop", function()
		it("opens and closes from the Shop tab, the close button, and the backdrop", function()
			local session, parts = startClient()
			local root = hud(parts)
			session:fire(root.Tabs.Shop, "Activated")
			expect.equal(root.ShopPanel.Visible, true)
			expect.equal(root.Backdrop.Visible, true)
			session:fire(root.ShopPanel.TitleBar.Close, "Activated")
			expect.equal(root.ShopPanel.Visible, false)

			session:fire(root.Tabs.Shop, "Activated")
			session:fire(root.Backdrop, "Activated")
			expect.equal(root.ShopPanel.Visible, false)

			-- The Settings tab swaps one panel for the other; pressing it again closes it.
			session:fire(root.Tabs.Shop, "Activated")
			session:fire(root.Tabs.Settings, "Activated")
			expect.equal(root.ShopPanel.Visible, false)
			expect.equal(root.SettingsPanel.Visible, true)
			session:fire(root.Tabs.Settings, "Activated")
			expect.equal(root.SettingsPanel.Visible, false)
		end)

		it("opens at the right section from the + next to dollars and stamina", function()
			local session, parts = startClient()
			local root = hud(parts)
			local chips = root.ShopPanel.Body.Sections
			local featuredColor = chips.Featured.Face.BackgroundColor3
			session:fire(root.Wallet.Dollars.Add, "Activated")
			expect.equal(root.ShopPanel.Visible, true)
			task.wait(0.1)
			expect.truthy(chips.Dollars.Face.BackgroundColor3 ~= chips.Luck.Face.BackgroundColor3, "Dollars chip lit")
			expect.truthy(chips.Featured.Face.BackgroundColor3 ~= featuredColor, "Featured chip no longer lit")
			expect.falsy(root.Wallet.Eggs:FindFirstChild("Add"), "eggs cannot be bought")
		end)

		it("lists every item with its price, and asks the server to buy it", function()
			local session, parts = startClient()
			local body = shopBody(parts)
			local robux = utf8.char(0xE002)

			local dollars = body.Dollars.Grid.Dollars1
			expect.equal(dollars.Title.Text, "+$5K")
			expect.equal(buttonText(dollars.Buy), robux .. " 39")
			session:fire(dollars.Buy, "Activated")
			expect.equal(session:lastSent("RequestPurchase", "server").args[1], "Dollars1")

			expect.truthy(body.Stamina.Grid.Stamina3.Badge, "best value tag")
			expect.equal(body.Luck.Grid.Luck2.Badge.Label.Text, "15 MIN")

			local pen = body.Featured.PenUpgrade
			expect.equal(pen.Current.Level.Text, "LEVEL 1")
			expect.equal(pen.Next.Level.Text, "LEVEL 2")
			expect.equal(pen.Next.Capacity.Text, "11 pets")
			expect.equal(buttonText(pen.Buttons.BuyDollars), "750")
			session:fire(pen.Buttons.BuyDollars, "Activated")
			expect.equal(session:lastSent("BuyWithDollars", "server").args[1], "PenUpgrade")
			session:fire(pen.Buttons.BuyRobux, "Activated")
			expect.equal(session:lastSent("RequestPurchase", "server").args[1], "PenUpgrade")

			local pass = body.Passes.List.DoubleDollars
			expect.equal(pass.Owned.Visible, false)
			session:fire(pass.Buy, "Activated")
			expect.equal(session:lastSent("RequestPurchase", "server").args[1], "DoubleDollars")
		end)

		it("follows dollars, pen level, and passes from the server", function()
			local session, parts =
				startClient(nil, { shop = { dollars = 12500, penLevel = 3, passes = {}, luck = {} } })
			local root = hud(parts)
			local pen = shopBody(parts).Featured.PenUpgrade
			expect.equal(root.Wallet.Dollars.Value.Text, "12.5K")
			expect.equal(pen.Current.Level.Text, "LEVEL 3")
			expect.equal(buttonText(pen.Buttons.BuyDollars), "30K")

			session:fromServer("PlayerStateUpdated", { dollars = 0, penLevel = 9, passes = { "DoubleDollars" } })
			expect.equal(root.Wallet.Dollars.Value.Text, "0")
			expect.equal(pen.Headline.Text, "YOUR PEN IS MAXED!")
			expect.equal(pen.Buttons.Visible, false)
			expect.equal(pen.Next.Visible, false)
			local pass = shopBody(parts).Passes.List.DoubleDollars
			expect.equal(pass.Owned.Visible, true)
			expect.equal(pass.Buy.Visible, false)
		end)

		it("shows the stamina doubling, from x1 up to maxed out at x1024", function()
			local session, parts = startClient()
			local card = shopBody(parts).Stamina.StaminaDoubling
			local robux = utf8.char(0xE002)
			expect.equal(card.Multipliers.From.Text, "x1")
			expect.equal(card.Multipliers.To.Text, "x2")
			expect.equal(buttonText(card.Buy), robux .. " 49")
			session:fire(card.Buy, "Activated")
			expect.equal(session:lastSent("RequestPurchase", "server").args[1], "StaminaDoubling")

			session:fromServer("PlayerStateUpdated", { staminaMultiplier = 32 })
			expect.equal(card.Multipliers.From.Text, "x32")
			expect.equal(card.Multipliers.To.Text, "x64")
			expect.equal(buttonText(card.Buy), robux .. " 199")
			expect.equal(card.Maxed.Visible, false)

			session:fromServer("PlayerStateUpdated", { staminaMultiplier = 1024 })
			expect.equal(card.Title.Text, "STAMINA MAXED OUT!")
			expect.equal(card.Multipliers.From.Text, "x1024")
			expect.equal(card.Multipliers.To.Visible, false)
			expect.equal(card.Buy.Visible, false)
			expect.equal(card.Maxed.Visible, true)
		end)

		it("shows how each purchase went", function()
			local session, parts = startClient()
			session:fromServer("PurchaseResult", "Dollars1", true, "+$5K!")
			expect.equal(hud(parts).Toast.Text, "+$5K!")
			expect.equal(hud(parts).Toast.Visible, true)
		end)

		it("counts down a server luck boost", function()
			local session, parts = startClient()
			local root = hud(parts)
			session:fromServer("LuckChanged", { { multiplier = 2, endsAt = session.clock + 90 } })
			session:renderFrame(1 / 60)
			expect.equal(root.Luck.Visible, true)
			expect.equal(root.Luck.Label.Text, "🍀 x2 LUCK  1:30")
			expect.equal(shopBody(parts).Luck.Grid.Luck2.Badge.Label.Text, "ON  1:30")
			expect.equal(shopBody(parts).Luck.Grid.Luck4.Badge.Label.Text, "15 MIN")

			session:renderFrame(1, 91)
			expect.equal(root.Luck.Visible, false)
			expect.equal(shopBody(parts).Luck.Grid.Luck2.Badge.Label.Text, "15 MIN")
		end)
	end)

	describe("Client: settings", function()
		local function settingsRow(parts, key)
			return hud(parts).SettingsPanel.Body.Scroll[key]
		end

		local function press(session, button, x)
			session:fire(button, "InputBegan", {
				UserInputType = Enum.UserInputType.MouseButton1,
				Position = Vector3.new(x, 0, 0),
			})
		end

		it("shows the saved settings and applies the volumes", function()
			local session, parts = startClient(nil, { settings = { MusicVolume = 0.3, ShowOthersPets = false } })
			task.wait(0.05)
			expect.equal(settingsRow(parts, "MusicVolume").Slider.Percent.Text, "30%")
			expect.equal(settingsRow(parts, "EffectsVolume").Slider.Percent.Text, "100%")
			expect.equal(settingsRow(parts, "ShowOthersPets").Toggle.State.Text, "OFF")
			expect.equal(settingsRow(parts, "ShowMyPets").Toggle.State.Text, "ON")
			local sound = session:service("SoundService")
			expect.near(sound.Music.Volume, 0.3, 1e-6)
			expect.near(sound.Effects.Volume, 1, 1e-6)
			expect.truthy(sound:FindFirstChild("Nature"), "Nature sound group")
		end)

		it("slides, switches, and saves a moment later", function()
			local session, parts = startClient()
			local sound = session:service("SoundService")
			local slider = settingsRow(parts, "MusicVolume").Slider
			slider.Track.AbsolutePosition = Vector2.new(100, 0)
			slider.Track.AbsoluteSize = Vector2.new(200, 44)

			-- Press a quarter of the way along, then drag to three quarters and let go.
			press(session, slider.Track, 150)
			expect.equal(slider.Percent.Text, "25%")
			expect.near(sound.Music.Volume, 0.25, 1e-6)
			local userInput = session:service("UserInputService")
			session:fire(userInput, "InputChanged", {
				UserInputType = Enum.UserInputType.MouseMovement,
				Position = Vector3.new(250, 0, 0),
			})
			expect.equal(slider.Percent.Text, "75%")
			session:fire(userInput, "InputEnded", { UserInputType = Enum.UserInputType.MouseButton1 })
			session:fire(userInput, "InputChanged", {
				UserInputType = Enum.UserInputType.MouseMovement,
				Position = Vector3.new(120, 0, 0),
			})
			expect.equal(slider.Percent.Text, "75%", "no longer dragging")

			local toggle = settingsRow(parts, "ShowMyPets").Toggle
			session:fire(toggle, "Activated")
			expect.equal(toggle.State.Text, "OFF")

			expect.equal(#session:sent("SaveSettings"), 0, "waits before saving")
			task.wait(1.7)
			local saves = session:sent("SaveSettings", "server")
			expect.equal(#saves, 1, "one save for all the changes")
			expect.equal(saves[1].args[1].MusicVolume, 0.75)
			expect.equal(saves[1].args[1].ShowMyPets, false)
		end)

		it("keeps changes made before the saved settings arrive, and saves them", function()
			local session, parts = startClient(nil, {
				settings = { MusicVolume = 0.3, ShowOthersPets = false },
				settingsDelay = 0.3,
			})
			local sound = session:service("SoundService")
			local slider = settingsRow(parts, "MusicVolume").Slider
			slider.Track.AbsolutePosition = Vector2.new(100, 0)
			slider.Track.AbsoluteSize = Vector2.new(200, 44)

			-- The player moves the slider while the server is still answering.
			press(session, slider.Track, 250)
			expect.equal(slider.Percent.Text, "75%")

			task.wait(0.4)
			-- The player's change wins; saved settings they did not touch are loaded.
			expect.equal(slider.Percent.Text, "75%")
			expect.near(sound.Music.Volume, 0.75, 1e-6)
			expect.equal(settingsRow(parts, "ShowOthersPets").Toggle.State.Text, "OFF")

			task.wait(1.7)
			local saves = session:sent("SaveSettings", "server")
			expect.equal(#saves, 1, "the early change is saved")
			expect.equal(saves[1].args[1].MusicVolume, 0.75)
			expect.equal(saves[1].args[1].ShowOthersPets, false)
		end)
	end)
end
