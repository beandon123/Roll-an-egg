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
			local folder = roblox.Instance.new("Folder")
			folder.Name = "StudioPets"
			folder.Parent = workspace
			session:fire(workspace, "ChildAdded", folder)
			local phoenix = PetRig.build("LavaDragon")
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
			local session, parts = startClient()
			local root = hud(parts)
			for _, name in { "Cycle", "Zone", "Wallet", "Toast", "Meters", "StudioTestPanel" } do
				expect.truthy(root:FindFirstChild(name), name)
			end
			expect.truthy(root.Meters.Claim and root.Meters.Stamina and root.Meters.RideHint, "meters")
			expect.equal(labelOf(root.Wallet.Eggs).Text, "Eggs  2")
			expect.equal(labelOf(root.Wallet.Dollars).Text, "$0")
			session:fromServer("DollarsChanged", 1520, 12)
			expect.equal(labelOf(root.Wallet.Dollars).Text, "$1.52K  +$12/s")
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
