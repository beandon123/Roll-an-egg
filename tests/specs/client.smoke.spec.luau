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
			EggRig = session:require(folder.EggRig),
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
			owner = nil,
			bounceTime = nil,
		}
	end

	-- The zone's first rarity that has eggs.
	local function firstRarity(session, zone)
		local Rarities = session:require(session:service("ReplicatedStorage").Shared.Config.Rarities)
		for _, rarity in Rarities.Order do
			if shared(session).EggSpec.get(zone, rarity) then
				return rarity
			end
		end
		error("no eggs in zone " .. zone)
	end

	-- Puts the camera near a spot, as it would be near the player there.
	local function cameraAt(session, position)
		session:service("Workspace").CurrentCamera.CFrame = roblox.CFrame.new(position + Vector3.new(0, 10, -20))
	end

	-- Where the middle of an egg is drawn now, in the world: where its rider has it, or along its path round the
	-- obstacles, riding at its rolling height above the ground. (Eggs are steered in runway space; the runway winds,
	-- so world x is its centre line there plus the egg's lateral.)
	local function eggCenter(session, egg)
		local modules = shared(session)
		local spec = modules.EggSpec.get(egg.zone, egg.rarity)
		local startZ = spec.startZ
		local z = modules.Runway.wrapZ(modules.EggMotion.zAt(egg.spawnTime, startZ, spec.rollSpeed, session.clock))
		local x = egg.lateral
		if egg.rider == nil then
			local fadeZ = modules.EggSpec.fadeZ(egg.zone, startZ)
			local path = modules.Obstacles.planPath(egg.lateral, startZ, fadeZ, spec.halfLength, spec.radius)
			x = modules.Obstacles.lateralAt(path, z)
		end
		local world = modules.Runway.worldX(x, z)
		return Vector3.new(world, modules.Runway.surfaceY(z) + modules.EggRig.rollHeight(spec.radius), z), spec
	end

	-- How far across the runway a world position is (0 on its centre line, which winds).
	local function across(session, position)
		return shared(session).Runway.lateralOf(position.X, position.Z)
	end

	-- The way across the runway (to +lateral) at a point on it, and the way down it.
	local function runwayAxes(session, z)
		local heading = shared(session).Runway.heading(z)
		return Vector3.new(math.cos(heading), 0, -math.sin(heading)),
			Vector3.new(math.sin(heading), 0, math.cos(heading))
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

		it("builds each egg from its blocky model, every part anchored and none welded", function()
			local session, parts = startClient()
			session:fromServer("EggSpawned", eggData(session, 1, 1, "Common"))
			session:fromServer("EggSpawned", eggData(session, 3, 1, "Common", 5, 8))
			session:fromServer("EggSpawned", eggData(session, 2, 5, "Secret", 5, -8))

			local EggModels = session:require(session:service("ReplicatedStorage").Shared.EggModels)
			local common = parts.eggFolder.Egg1
			local blocks = {}
			for _, child in common:GetChildren() do
				if child:IsA("BasePart") and child ~= common.Root and child.Name ~= "Dust" and child.Name ~= "Echo" then
					table.insert(blocks, child)
				end
			end
			expect.equal(#blocks, #EggModels.get("Leafy").boxes, "one part per box")
			-- Nothing holds an egg together but where its parts are put: no welds to go wrong, no physics to pull a
			-- part away.
			for _, block in blocks do
				expect.equal(block.Anchored, true, block.Name .. " is anchored")
				expect.equal(block.CanCollide, false)
			end
			for _, descendant in common:GetDescendants() do
				expect.falsy(descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint"), "no welds")
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

			-- Eggs lie across the runway, which winds; eggs with even ids lie the other way round.
			session:renderFrame(1 / 60)
			local acrossOne = runwayAxes(session, common.Root.CFrame.Position.Z)
			local acrossTwo = runwayAxes(session, parts.eggFolder.Egg2.Root.CFrame.Position.Z)
			expect.truthy(common.Root.CFrame.RightVector:Dot(acrossOne) > 0.99, "Egg1 points across, to +lateral")
			expect.truthy(parts.eggFolder.Egg2.Root.CFrame.RightVector:Dot(acrossTwo) < -0.99, "Egg2 the other way")
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
				-- Everything but the root and the dust (and its echo, see EggController).
				return #model:GetChildren() - 3
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

			-- Further on, it has steered round whatever was in its lane. (With the camera near it: eggs far from the
			-- camera are only redrawn every few frames.)
			session:renderFrame(1, 20)
			cameraAt(session, eggCenter(session, egg))
			session:renderFrame(1 / 60)
			expected = eggCenter(session, egg)
			position = parts.eggFolder.Egg1.Root.CFrame.Position
			expect.near(position.X, expected.X, 1e-3, "x later")
		end)

		it("keeps every part of an egg in its place, where it appears and as it rolls", function()
			local session, parts = startClient()
			local EggRig = session:require(session:service("ReplicatedStorage").Shared.EggRig)
			-- In the second zone, 600 studs from where egg models are built: a part left behind there, or carried
			-- round the root at that distance, is nowhere near the egg.
			local egg = eggData(session, 1, 2, "Common", 5, 6)
			local center, spec = eggCenter(session, egg)
			cameraAt(session, center)
			session:fromServer("EggSpawned", egg)
			local model = parts.eggFolder.Egg1

			-- Where the design puts each block, measured from the root.
			local reference = EggRig.build(egg.kind, spec)
			local referenceRoot = reference.PrimaryPart
			local function furthestOut(): (number, number)
				local worst, count = 0, 0
				for _, block in reference:GetChildren() do
					if block:IsA("BasePart") and block ~= referenceRoot then
						local drawn = model:FindFirstChild(block.Name)
						local expected = model.Root.CFrame * referenceRoot.CFrame:ToObjectSpace(block.CFrame)
						worst = math.max(
							worst,
							(drawn.CFrame.Position - expected.Position).Magnitude,
							(drawn.CFrame.LookVector - expected.LookVector).Magnitude,
							(drawn.CFrame.UpVector - expected.UpVector).Magnitude
						)
						count += 1
					end
				end
				return worst, count
			end

			local worst, count = furthestOut()
			expect.truthy(count > 10, "the egg has blocks")
			expect.truthy(worst < 1e-2, `in one piece where it appears (a block is {worst} out)`)

			local turnedBefore = model.Root.CFrame.UpVector
			session:renderFrame(1 / 60, 45)
			worst = furthestOut()
			expect.truthy(worst < 1e-2, `in one piece as it rolls (a block is {worst} out)`)
			expect.truthy((model.Root.CFrame.UpVector - turnedBefore).Magnitude > 0.1, "it turns as it rolls")
			expect.near(model.Root.CFrame.Position.Z, eggCenter(session, egg).Z, 1e-3, "and moves down the runway")
		end)

		it(
			"fades an egg that jumps to another copy of itself fully back in, even part-way through fading in",
			function()
				local session, parts = startClient()
				local modules = shared(session)
				local runway = modules.Runway
				local rarity = firstRarity(session, 6)
				local spec = modules.EggSpec.get(6, rarity)
				-- For a player back at the hub, an egg one loop into the endless last zone is drawn back at the zone's
				-- start. This one is a stud short of that.
				local jumpZ = runway.FINAL_ZONE_START + runway.LOOP_LENGTH
				local egg = eggData(session, 1, 6, rarity, (jumpZ - 1 - spec.startZ) / spec.rollSpeed, 0)
				cameraAt(session, Vector3.new(0, 13, jumpZ))
				session:fromServer("EggSpawned", egg)
				local model = parts.eggFolder.Egg1
				local block = model.Block1
				local designed = block.Transparency
				expect.truthy(model.Root.CFrame.Position.Z > jumpZ - 5, "not there yet")

				-- Caught part-way through fading in when it jumps.
				block.Transparency = 0.6
				session:renderFrame(1 / 60, 30)
				expect.truthy(model.Root.CFrame.Position.Z < jumpZ - 100, "drawn one loop back")
				expect.equal(block.Transparency, designed, "faded all the way in, not left half see-through")
			end
		)

		it("kicks up dust while rolling, coloured for the ground", function()
			local session, parts = startClient()
			local desert = eggData(session, 1, 2, "Common", 5, 0)
			cameraAt(session, eggCenter(session, desert))
			session:fromServer("EggSpawned", desert)
			session:renderFrame(1 / 60)
			local rolling = parts.eggFolder.Egg1.Dust
			local emitter = rolling:FindFirstChildOfClass("ParticleEmitter")
			expect.truthy(emitter.Enabled, "dust while rolling")
			expect.equal(emitter.Color.Keypoints[1].Value, roblox.Color3.fromRGB(236, 208, 152), "desert sand")
			expect.near(rolling.CFrame.Position.Y, shared(session).Runway.BASE_Y + 0.2, 1e-3)
			expect.equal(session.emitted[emitter], nil, "already rolling when the player joined: no puff")

			-- A brand-new egg appears with a puff of dust.
			local fresh = eggData(session, 2, 2, "Common", 0, 10)
			session:fromServer("EggSpawned", fresh)
			local puff = parts.eggFolder.Egg2.Dust:FindFirstChildOfClass("ParticleEmitter")
			expect.truthy((session.emitted[puff] or 0) > 0, "a puff where it appears")

			-- No dust for eggs far from the camera.
			session:fromServer("EggSpawned", eggData(session, 3, 5, firstRarity(session, 5), 5, 0))
			session:renderFrame(1 / 60)
			expect.falsy(parts.eggFolder.Egg3.Dust:FindFirstChildOfClass("ParticleEmitter").Enabled, "far away")
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

			-- On foot on the hub: nothing. (Nobody stands on the runway itself; see "Client: leaping".)
			local center = eggCenter(session, egg)
			session:heartbeat(1 / 60)
			expect.equal(#session:sent("RequestMount"), 0)

			-- Leaping, but far away: nothing.
			parts.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			parts.root.Position = center + Vector3.new(0, 20, 30)
			session:heartbeat(1 / 60)
			expect.equal(#session:sent("RequestMount"), 0)

			-- In the air on top of it: ask.
			jumpOnto(session, parts, egg)
			session:heartbeat(1 / 60)
			local request = session:lastSent("RequestMount", "server")
			expect.truthy(request, "RequestMount")
			expect.equal(request.args[1], 1)
		end)

		it("does not try to mount an egg that is taken, cracking, or claimed by someone else", function()
			local session, parts = startClient()
			local taken = eggData(session, 1, 1, "Common")
			taken.rider = 999
			local cracking = eggData(session, 2, 1, "Common", 5, 10)
			cracking.bounceTime = session.clock
			local claimed = eggData(session, 3, 1, "Common", 5, -10)
			claimed.owner = 999
			for _, egg in { taken, cracking, claimed } do
				session:fromServer("EggSpawned", egg)
				jumpOnto(session, parts, egg)
				session:heartbeat(1 / 60)
				task.wait(0.3)
			end
			expect.equal(#session:sent("RequestMount"), 0)
		end)

		it("circles the egg a jumping player is heading for in red, and draws them onto it once close", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			local center, spec = eggCenter(session, egg)
			local function ring()
				return parts.playerGui:FindFirstChild("JumpTarget")
			end

			-- In the air, but nowhere near it: no circle.
			parts.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			parts.root.Position = center + Vector3.new(0, 20, 60)
			session:heartbeat(1 / 60)
			expect.truthy(ring() == nil or not ring().Enabled, "no circle")

			-- Close by, off to one side and a little above: the egg is circled, and the player is pulled toward its top
			-- while moving on down the runway with it. Not on it yet, so no request to get on.
			center = eggCenter(session, egg)
			parts.root.Position = center + Vector3.new(spec.halfLength + 6, spec.radius + 6, 0)
			parts.root.AssemblyLinearVelocity = Vector3.zero
			session:heartbeat(1 / 60)
			local circle = ring()
			expect.truthy(circle and circle.Enabled, "circled")
			expect.equal(circle.Adornee, parts.eggFolder.Egg1.Root)
			expect.equal(circle.AlwaysOnTop, true)
			expect.truthy(circle.Size.X.Scale > spec.halfLength * 2, "round the whole egg")
			local stroke = circle.Ring.UIStroke
			expect.truthy(stroke.Color.R > 0.9 and stroke.Color.G < 0.3, "red")
			local velocity = parts.root.AssemblyLinearVelocity
			expect.truthy(velocity.X < 0, "pulled toward the egg")
			expect.truthy(velocity.Y < 0, "and down onto it")
			expect.truthy(velocity.Z > 0, "rolling on with it")
			expect.equal(#session:sent("RequestMount"), 0)

			-- Drawn in on top of it: ask to get on it.
			jumpOnto(session, parts, egg)
			task.wait(0.3)
			session:heartbeat(1 / 60)
			local request = session:lastSent("RequestMount", "server")
			expect.truthy(request, "RequestMount")
			expect.equal(request.args[1], 1)

			-- On it: the circle goes.
			startRide(session, egg)
			session:heartbeat(1 / 60)
			expect.equal(ring().Enabled, false)
		end)

		it("holds the character on the egg and steers it", function()
			local session, parts = startClient()
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			startRide(session, egg)
			expect.equal(parts.root.Anchored, true)
			expect.equal(parts.humanoid.Sit, true)

			-- The character stands on top of the egg, facing down the runway (which winds). It is an R6 character
			-- (legs 2 studs long) with no legs: its root part is held as high above the egg as it would stand above
			-- the ground.
			session:renderFrame(1 / 60)
			local center, spec = eggCenter(session, egg)
			local seat = parts.root.CFrame
			expect.near(seat.Position.Z, center.Z, 1e-3)
			expect.near(seat.Position.Y, center.Y + spec.radius + 2 + parts.root.Size.Y / 2, 1e-3)
			local _, down = runwayAxes(session, seat.Position.Z)
			expect.near(seat.LookVector:Dot(down), 1, 1e-3, "facing down the runway")

			-- Pushing right on the stick moves the egg to the player's right. The camera looks down the
			-- runway (+Z), so screen-right is -X.
			session.moveVector = Vector3.new(1, 0, 0)
			session:renderFrame(1 / 60, 30)
			task.wait(0.3)
			session:renderFrame(1 / 60)
			local model = session:service("Workspace").Eggs.Egg1
			local moved = across(session, model.Root.CFrame.Position)
			expect.truthy(moved < -5, "egg moved: " .. moved)
			local report = session:lastSent("RideLateral", "server")
			expect.truthy(report, "RideLateral")
			expect.truthy(report.args[1] < 0)

			-- It cannot be steered off the side of the runway: it bounces back off it.
			session:renderFrame(1, 30)
			local limit = shared(session).Runway.maxLateral(spec.halfLength, model.Root.CFrame.Position.Z)
			local side = across(session, model.Root.CFrame.Position)
			expect.truthy(side >= -limit - 1e-3 and side < -limit + shared(session).Tuning.WALL_KNOCKBACK + 1e-3, side)
			expect.equal(parts.root.Anchored, true, "still riding")
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
			-- Just out of its chute, short of the zone's first row of obstacles, with stamina that would run out in a
			-- second if the egg were not claimed.
			local egg = eggData(session, 1, 1, "Common", 0.5)
			session:fromServer("EggSpawned", egg)
			session:fromServer("EggMounted", egg.id, LOCAL_USER_ID, session.clock)
			session:fromServer("RideStarted", egg.id, {
				startTime = session.clock,
				startStamina = 100,
				drain = 100,
				claimTime = 5,
				combo = 0,
			})

			session:fromServer("EggClaimed", 1, LOCAL_USER_ID, "Common", "Leafy")
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

			local toast = hud(parts).Toast
			expect.equal(toast.Text, "CLAIMED! +1 Leafy Egg")
			expect.equal(toast.Visible, true)
			expect.equal(hud(parts).Wallet.Eggs.Content.Value.Text, "3")

			-- Still on the egg, with a full meter that says so; nothing runs out.
			expect.equal(parts.root.Anchored, true)
			local meters = hud(parts).Meters
			expect.equal(meters.Claim.Visible, true)
			expect.near(meters.Claim.Fill.Size.X.Scale, 1, 1e-6)
			expect.truthy(string.find(labelOf(meters.Claim).Text, "claimed!$"), labelOf(meters.Claim).Text)
			expect.equal(meters.RideHint.Text, "In your inventory  -  keep rolling, or jump to leap off")
			session:renderFrame(0.25, 8)
			expect.truthy(string.find(labelOf(meters.Claim).Text, "claimed!$"), "still claimed")
			expect.equal(parts.root.Anchored, true)

			-- Jump off: a leap, and the meter goes.
			task.wait(0.6)
			session:heartbeat(1 / 60)
			session:fire(session:service("UserInputService"), "JumpRequest")
			expect.equal(#session:sent("RequestDismount", "server"), 1)
			expect.equal(parts.root.Anchored, false)
			expect.equal(meters.Claim.Visible, false)
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
			local startZ = spec.startZ
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
			local x = across(session, session:service("Workspace").Eggs.Egg1.Root.CFrame.Position)
			expect.truthy(math.abs(x - bump.x) >= bump.hx + spec.halfLength, "knocked clear")
			expect.equal(parts.root.Anchored, true, "still riding")
		end)

		it("crashes into big obstacles: stays on, pays in stamina, and slows down for a moment", function()
			local session, parts = startClient()
			local rock = findObstacle(session, 1, "Crash", false)
			rideTowards(session, rock, "Rare")
			session:renderFrame(1 / 60, 20)
			expect.equal(session:lastSent("ReportHit", "server").args[1], rock.id)
			expect.truthy(string.find(hud(parts).Toast.Text, "^Crashed into "), hud(parts).Toast.Text)
			expect.truthy(string.find(hud(parts).Toast.Text, "stamina$"), hud(parts).Toast.Text)
			expect.equal(parts.root.Anchored, true, "still riding")
			expect.equal(parts.humanoid.Health, 100)
			-- Slowed here at once; the server's own numbers, when they come, replace these without a jump.
			local EggController =
				session:require(session:service("StarterPlayer").StarterPlayerScripts.Client.Controllers.EggController)
			local egg = EggController.GetEgg(1)
			expect.truthy(egg.slow, "slowed")
			local before = session:service("Workspace").Eggs.Egg1.Root.CFrame.Position.Z
			session:fromServer("EggSlowed", 1, { lost = 0, at = session.clock - 0.3, duration = 1.2 })
			session:renderFrame(1 / 60)
			local after = session:service("Workspace").Eggs.Egg1.Root.CFrame.Position.Z
			expect.truthy(math.abs(after - before) < 1, "eases onto the server's numbers")
		end)

		it("is slowed by lava, and never killed by it", function()
			local session, parts = startClient()
			local lava = findObstacle(session, 5, "Slow", false)
			rideTowards(session, lava, "Rare")
			session:renderFrame(1 / 60, 20)
			expect.equal(session:lastSent("ReportHit", "server").args[1], lava.id)
			expect.equal(parts.root.Anchored, true, "still riding")
			expect.equal(parts.humanoid.Health, 100)
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
			expect.near(across(session, session:service("Workspace").Eggs.Egg1.Root.CFrame.Position), 21, 1e-3)
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
			expect.near(across(session, otherRoot.CFrame.Position), 6, 1e-3)
		end)
	end)

	describe("Client: riders running on their eggs", function()
		-- Gives a character the joints of an R15 rig, or an R6 one (whose limbs' joints are turned, as in Roblox's
		-- own R6 rig), all at rest. Returns them by name.
		local function rigCharacter(session, humanoid, root, r6)
			local RiderPose = session:require(session:service("ReplicatedStorage").Shared.RiderPose)
			humanoid.RigType = if r6 then Enum.HumanoidRigType.R6 else Enum.HumanoidRigType.R15
			if not r6 then
				humanoid.HipHeight = 2
				root.Size = Vector3.new(2, 2, 1)
			end
			local turned = {
				["Left Shoulder"] = roblox.CFrame.new(-1, 0.5, 0) * roblox.CFrame.Angles(0, -math.pi / 2, 0),
				["Right Shoulder"] = roblox.CFrame.new(1, 0.5, 0) * roblox.CFrame.Angles(0, math.pi / 2, 0),
				["Left Hip"] = roblox.CFrame.new(-1, -1, 0) * roblox.CFrame.Angles(0, -math.pi / 2, 0),
				["Right Hip"] = roblox.CFrame.new(1, -1, 0) * roblox.CFrame.Angles(0, math.pi / 2, 0),
			}
			local motors = {}
			for _, name in if r6 then RiderPose.R6_JOINTS else RiderPose.JOINTS do
				local motor = roblox.Instance.new("Motor6D")
				motor.Name = name
				motor.C0 = turned[name] or roblox.CFrame.identity
				-- Roblox always has one; Lune has none until it is set.
				motor.Transform = roblox.CFrame.identity
				motor.Parent = humanoid.Parent
				motors[name] = motor
			end
			return motors
		end

		-- Puts every joint back at rest, as Roblox's own animations would set them each frame.
		local function rest(motors)
			for _, motor in motors do
				motor.Transform = roblox.CFrame.identity
			end
		end

		local function atRest(motors): boolean
			for _, motor in motors do
				if (motor.Transform.Position).Magnitude > 1e-6 or motor.Transform.LookVector.Z > -1 + 1e-6 then
					return false
				end
			end
			return true
		end

		-- Where a limb hanging straight down from a joint points, in its parent part's space.
		local function limbDirection(motor)
			local turn = motor.C0.Rotation * motor.Transform.Rotation * motor.C0.Rotation:Inverse()
			return turn:VectorToWorldSpace(Vector3.new(0, -1, 0))
		end

		it("makes a rider run on their egg, standing on it, and lets go after they hop off", function()
			local session, parts = startClient()
			local motors = rigCharacter(session, parts.humanoid, parts.root, false)
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			startRide(session, egg)
			cameraAt(session, eggCenter(session, egg))
			session:renderFrame(1 / 60, 20)

			-- Standing on the egg: an R15 root part is its hip height and half its own height up.
			local center, spec = eggCenter(session, egg)
			expect.near(parts.root.CFrame.Position.Y, center.Y + spec.radius + 3, 1e-3)

			-- Leaning into the run, the legs taking turns to swing forward.
			expect.truthy(motors.Root.Transform.LookVector.Y < -0.1, "leaning forward")
			local most, least = -math.huge, math.huge
			for _ = 1, 30 do
				rest(motors)
				session:renderFrame(1 / 60)
				local ahead = limbDirection(motors.LeftHip).Z - limbDirection(motors.RightHip).Z
				most, least = math.max(most, ahead), math.min(least, ahead)
			end
			-- A leg swinging forward points its foot ahead (-Z).
			expect.truthy(most > 0.5 and least < -0.5, `legs take turns: {least} to {most}`)

			-- Hops off: blended back to Roblox's own animations, then left alone.
			task.wait(0.6)
			session:heartbeat(1 / 60)
			session:fire(session:service("UserInputService"), "JumpRequest")
			session:fromServer("RideEnded", "Dismount", { eggId = 1, zone = 1, rarity = "Common" })
			session:fromServer("EggLeft", 1, session.clock, 0, false)
			session:renderFrame(1 / 60, 30)
			rest(motors)
			session:renderFrame(1 / 60)
			expect.truthy(atRest(motors), "no longer posed")
		end)

		it("tumbles a rider who is thrown off until they get their balance back", function()
			local session, parts = startClient()
			local motors = rigCharacter(session, parts.humanoid, parts.root, false)
			local egg = eggData(session, 1, 1, "Rare")
			session:fromServer("EggSpawned", egg)
			startRide(session, egg, 9)
			cameraAt(session, eggCenter(session, egg))
			session:renderFrame(1 / 60, 10)

			session:fromServer("RideEnded", "ThrownOff", { eggId = 1, zone = 1, rarity = "Rare" })
			session:fromServer("EggLeft", 1, session.clock, 1, true)
			-- Flailing: the arms windmill right round while stunned.
			local highest = -math.huge
			for _ = 1, 30 do
				rest(motors)
				session:renderFrame(1 / 60)
				highest = math.max(highest, limbDirection(motors.LeftShoulder).Y)
			end
			expect.truthy(highest > 0.3, `an arm swings up overhead: {highest}`)

			-- Once the stun is over, back to Roblox's own animations.
			local Tuning = shared(session).Tuning
			session:renderFrame(1 / 60, math.ceil(Tuning.STUN_TIME * 60) + 20)
			rest(motors)
			session:renderFrame(1 / 60)
			expect.truthy(atRest(motors), "no longer posed")
		end)

		it("shows another rider tiring as their stamina is about to run out, on an R6 character", function()
			local session = startClient()
			local other, humanoid, root = session:addPlayer(999, "Other")
			local motors = rigCharacter(session, humanoid, root, true)
			local egg = eggData(session, 1, 1, "Rare")
			egg.rider = 999
			session:fromServer("EggSpawned", egg)
			cameraAt(session, eggCenter(session, egg))

			-- How far the left arm swings out to the side, at most, over a second.
			local function armOut(): number
				local widest = -math.huge
				for _ = 1, 60 do
					rest(motors)
					session:renderFrame(1 / 60)
					widest = math.max(widest, -limbDirection(motors["Left Shoulder"]).X)
					-- The legs swing forwards and back, not out to the side, however the R6 joints are turned.
					expect.truthy(math.abs(limbDirection(motors["Left Hip"]).X) < 0.35, "leg swings fore and aft")
				end
				return widest
			end

			-- Past the squash of landing on the egg (arms thrown out), running along.
			armOut()
			local calm = armOut()
			expect.truthy(calm < 0.6, `arms in while running: {calm}`)
			local StaminaMath = session:require(session:service("ReplicatedStorage").Shared.StaminaMath)
			other:SetAttribute(StaminaMath.RUNS_OUT_AT, session.clock + 0.5)
			armOut()
			local tired = armOut()
			expect.truthy(tired > 0.8, `arms flung out for balance: {tired}`)
		end)
	end)

	describe("Client: eggs on the ground, cracking, and going over the edge", function()
		local function emitterOf(part)
			return part:FindFirstChildOfClass("ParticleEmitter")
		end

		it("puts a new egg on the ground at the start of its zone and rolls it without bouncing", function()
			local session, parts = startClient()
			local modules = shared(session)
			for zone = 1, 6 do
				local rarity = firstRarity(session, zone)
				session:fromServer("EggSpawned", eggData(session, zone, zone, rarity, 0, 0))
				local spec = modules.EggSpec.get(zone, rarity)
				local position = parts.eggFolder["Egg" .. zone].Root.CFrame.Position
				-- On the ground, its back just past the zone's start line, from the very first frame.
				local back = modules.Runway.zoneStartZ(zone) + modules.Tuning.EGG_SPAWN_GAP
				expect.near(position.Z - spec.radius, back, 1e-3, rarity .. " start")
				local height = modules.Runway.BASE_Y + modules.EggRig.rollHeight(spec.radius)
				expect.near(position.Y, height, 1e-3, rarity .. " height")
			end
			-- Two seconds of frames: every egg stays on the ground and only ever moves down the runway. (The ones far
			-- from the camera are redrawn every few frames, so they do not move on every single frame.)
			local firstZ, lastZ = {}, {}
			for _ = 1, 120 do
				session:renderFrame(1 / 60)
				for zone = 1, 6 do
					local spec = modules.EggSpec.get(zone, firstRarity(session, zone))
					local position = parts.eggFolder["Egg" .. zone].Root.CFrame.Position
					local height = modules.Runway.BASE_Y + modules.EggRig.rollHeight(spec.radius)
					expect.near(position.Y, height, 1e-3, "on the ground")
					expect.truthy(lastZ[zone] == nil or position.Z >= lastZ[zone], "never rolls backwards")
					firstZ[zone] = firstZ[zone] or position.Z
					lastZ[zone] = position.Z
				end
			end
			for zone = 1, 6 do
				local spec = modules.EggSpec.get(zone, firstRarity(session, zone))
				expect.truthy(lastZ[zone] - firstZ[zone] > spec.rollSpeed * 1.5, "rolls forward")
			end
		end)

		it("rides just high enough that the blocky shell neither floats nor digs into the ground", function()
			local session = startClient()
			local Shared = session:service("ReplicatedStorage").Shared
			local EggModels = session:require(Shared.EggModels)
			local EggRig = session:require(Shared.EggRig)
			-- The shell's flat sides are RADIUS voxels from its long axis; its corners reach further.
			expect.truthy(EggModels.CORNER_REACH > EggModels.RADIUS, "corners reach past the flat sides")
			for _, radius in { 3, 6.9 } do
				local height = EggRig.rollHeight(radius)
				local corner = radius * EggModels.CORNER_REACH / EggModels.RADIUS
				-- Lying on a flat side it hangs a little above the ground; on a corner it sinks in as little.
				expect.truthy(height > radius and height < corner, "between the two")
				expect.near(height - radius, corner - height, 1e-6, "evenly")
				expect.truthy(height - radius < radius * 0.1, "by a small fraction of its size")
			end
		end)

		it("redraws eggs near the camera every frame, and far-off ones every few frames", function()
			local session, parts = startClient()
			-- The camera is over the hub. One egg just down the runway, one a zone on, one at the far end.
			cameraAt(session, Vector3.new(0, 13, 0))
			session:fromServer("EggSpawned", eggData(session, 1, 1, "Common", 1, 0))
			session:fromServer("EggSpawned", eggData(session, 2, 2, "Common", 1, 0))
			session:fromServer("EggSpawned", eggData(session, 3, 6, firstRarity(session, 6), 1, 0))
			local roots = {
				near = parts.eggFolder.Egg1.Root,
				mid = parts.eggFolder.Egg2.Root,
				far = parts.eggFolder.Egg3.Root,
			}
			local moved = { near = 0, mid = 0, far = 0 }
			local last = {}
			local frames = 120
			for _ = 1, frames do
				session:renderFrame(1 / 60)
				for name, root in roots do
					local z = root.CFrame.Position.Z
					if last[name] and z ~= last[name] then
						moved[name] += 1
					end
					last[name] = z
				end
			end
			expect.equal(moved.near, frames - 1, "the near egg moves every frame")
			expect.truthy(
				moved.mid >= frames / 4 and moved.mid < frames * 0.75,
				`the middle egg moved {moved.mid} times`
			)
			expect.truthy(moved.far >= frames / 15 and moved.far < moved.mid, `the far egg moved {moved.far} times`)

			-- However rarely it is redrawn, each egg ends up where it should be, to within one redraw.
			local modules = shared(session)
			local farSpec = modules.EggSpec.get(6, firstRarity(session, 6))
			local behind = farSpec.startZ + farSpec.rollSpeed * (1 + frames / 60) - roots.far.CFrame.Position.Z
			expect.truthy(behind >= 0 and behind < farSpec.rollSpeed * 0.25, `the far egg is {behind} studs behind`)

			-- An egg somebody is riding is redrawn every frame wherever it is, because its rider is held on it.
			session:fromServer("EggMounted", 3, 999, session.clock)
			local before = roots.far.CFrame.Position.Z
			session:renderFrame(1 / 60)
			local after = roots.far.CFrame.Position.Z
			session:renderFrame(1 / 60)
			expect.truthy(after > before and roots.far.CFrame.Position.Z > after, "a ridden egg moves every frame")
		end)

		it("keeps an egg on the ground, and its dust going, when its rider gets off", function()
			local session, parts = startClient()
			local modules = shared(session)
			local egg = eggData(session, 1, 1, "Rare", 3)
			egg.rider = 999
			cameraAt(session, eggCenter(session, egg))
			session:fromServer("EggSpawned", egg)
			session:renderFrame(1 / 60)
			local emitter = emitterOf(parts.eggFolder.Egg1.Dust)
			expect.equal(emitter.Enabled, true)

			session:fromServer("EggLeft", 1, session.clock, 0, false)
			local root = parts.eggFolder.Egg1.Root
			local spec = modules.EggSpec.get(1, "Rare")
			for _ = 1, 60 do
				session:renderFrame(1 / 60)
				local height = modules.Runway.BASE_Y + modules.EggRig.rollHeight(spec.radius)
				expect.near(root.CFrame.Position.Y, height, 1e-3, "no hop")
				expect.equal(emitter.Enabled, true)
			end
		end)

		it("bounces an egg slightly before it cracks, and nobody can land on it meanwhile", function()
			local session, parts = startClient()
			local modules = shared(session)
			local egg = eggData(session, 1, 1, "Rare", 3)
			egg.rider = 999
			cameraAt(session, eggCenter(session, egg))
			session:fromServer("EggSpawned", egg)
			session:renderFrame(1 / 60)
			local root = parts.eggFolder.Egg1.Root
			local emitter = emitterOf(parts.eggFolder.Egg1.Dust)

			session:fromServer("EggLeft", 1, session.clock, 0, true)
			egg.rider = nil
			session:renderFrame(modules.Tuning.CRACK_BOUNCE_TIME / 2)
			local spec = modules.EggSpec.get(1, "Rare")
			local lift = root.CFrame.Position.Y - (modules.Runway.BASE_Y + modules.EggRig.rollHeight(spec.radius))
			expect.near(lift, modules.Tuning.CRACK_BOUNCE_HEIGHT, 1e-2)
			expect.truthy(lift < 4, "only a slight bounce")
			expect.equal(emitter.Enabled, false, "no dust while it cracks")

			jumpOnto(session, parts, egg)
			session:heartbeat(1 / 60)
			expect.equal(#session:sent("RequestMount"), 0)

			session:fromServer("EggRemoved", 1, "Cracked")
			expect.truthy(parts.eggFolder:FindFirstChild("Splat"), "splat")
		end)
	end)

	describe("Client: leaping", function()
		local function leapForce(parts)
			return parts.root:FindFirstChild("LeapForce")
		end

		it("launches a player into a floaty leap as soon as they step past the start zone", function()
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
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Leap.Visible, false)
		end)

		it("leaps off an egg with time to land on another", function()
			local session, parts = startClient()
			local tuning = shared(session).Tuning
			local egg = eggData(session, 1, 1, "Common")
			session:fromServer("EggSpawned", egg)
			startRide(session, egg)
			task.wait(0.4)
			session:heartbeat(1 / 60)
			session:fire(session:service("UserInputService"), "JumpRequest")
			expect.equal(parts.root.AssemblyLinearVelocity.Y, tuning.LEAP_UP_SPEED)
			expect.truthy(leapForce(parts).Enabled, "floaty")
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Leap.Visible, true)
		end)

		it("bounces off the side of the runway instead of dying, and tells the server", function()
			local session, parts = startClient()
			local modules = shared(session)
			local egg = eggData(session, 1, 1, "Common", 3, 20)
			session:fromServer("EggSpawned", egg)
			startRide(session, egg)
			-- Hard to the left (+lateral) until the egg reaches the side.
			session.moveVector = Vector3.new(-1, 0, 0)
			for _ = 1, 120 do
				session:renderFrame(1 / 30)
				if session:lastSent("ReportEdge", "server") then
					break
				end
			end
			expect.truthy(session:lastSent("ReportEdge", "server"), "ReportEdge")
			expect.equal(#session:sent("ReportEdge", "server"), 1, "once per knock")
			session:renderFrame(1 / 60)
			expect.truthy(string.find(hud(parts).Toast.Text, "^Bounced off the wall!"), hud(parts).Toast.Text)
			local spec = modules.EggSpec.get(1, "Common")
			local drawn = parts.eggFolder.Egg1.Root.CFrame.Position
			local back = across(session, drawn)
			local limit = modules.Runway.maxLateral(spec.halfLength, drawn.Z)
			expect.truthy(back < limit - 1, `back from the side: {back}`)
			expect.equal(parts.root.Anchored, true, "still riding")
			expect.equal(parts.humanoid.Health, 100)

			-- When the server spots it first, the egg goes where the server bounced it.
			session.moveVector = Vector3.zero
			task.wait(1.4)
			session:fromServer("EdgeHit", -40)
			session:renderFrame(1 / 60)
			expect.near(across(session, parts.eggFolder.Egg1.Root.CFrame.Position), -40, 1e-3)
		end)

		it("sends a ridden pet away and leaps the rider off it at the start zone", function()
			local session, parts = startClient()
			local tuning = shared(session).Tuning
			session:fromServer("MountChanged", "p", 30)
			parts.root.Position = Vector3.new(0, 16, 1)
			session:heartbeat(1 / 60)
			expect.equal(session:lastSent("RidePet", "server").args[1], "", "off the pet")
			expect.equal(parts.root.AssemblyLinearVelocity.Y, tuning.LEAP_UP_SPEED)
			expect.truthy(leapForce(parts) and leapForce(parts).Enabled, "leaping")
		end)

		it("tosses the player off when their pet bucks them", function()
			local session, parts = startClient()
			session:fromServer("PetBucked", "Bear")
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Toast.Text, "Your Bear bucked you off! Out of stamina.")
			expect.equal(parts.humanoid.PlatformStand, true, "staggering")
			expect.truthy(parts.root.AssemblyLinearVelocity.Y > 0, "thrown up")
			task.wait(shared(session).Tuning.BUCKED_STAGGER_TIME + 0.2)
			expect.equal(parts.humanoid.PlatformStand, false, "back on their feet")
		end)
	end)

	describe("Client: the endless last zone", function()
		it("carries a leaping player back one loop at the end", function()
			local session, parts = startClient()
			local runway = shared(session).Runway
			-- (The stand-in keeps Position and CFrame apart; Roblox keeps them in step.)
			parts.root.Position = Vector3.new(4, 30, runway.LOOP_END + 1)
			parts.root.CFrame = roblox.CFrame.new(parts.root.Position)
			session:heartbeat(1 / 60)
			local position = parts.root.CFrame.Position
			expect.near(position.Z, runway.LOOP_START + 1, 1e-3)
			expect.near(position.Y, 30, 1e-3)
			expect.near(position.X, 4, 1e-3)
			expect.equal(parts.humanoid.Health, 100)
		end)

		it("carries a rider and everything around them back one loop together, so nothing seems to move", function()
			local session, parts = startClient()
			local modules = shared(session)
			local runway = modules.Runway
			-- The rider's Eternal egg (21 studs/s) is 10 studs from the end of the loop, in a lane clear of obstacles
			-- there (and so, the last zone repeating, one loop back too).
			local mineSpec = modules.EggSpec.get(6, "Eternal")
			local lane
			for x = -50, 50, 2 do
				local path = modules.Obstacles.planPath(
					x,
					runway.LOOP_END - 15,
					runway.LOOP_END + 15,
					mineSpec.halfLength,
					mineSpec.radius
				)
				if #path.moves == 0 then
					lane = x
					break
				end
			end
			expect.truthy(lane, "a clear lane")
			local mine =
				eggData(session, 1, 6, "Eternal", (runway.LOOP_END - 10 - mineSpec.startZ) / mineSpec.rollSpeed, lane)
			mine.rider = LOCAL_USER_ID
			-- Someone else's slower Epic egg has already been carried back, to just past the start of the loop.
			local otherSpec = modules.EggSpec.get(6, "Epic")
			local other =
				eggData(session, 2, 6, "Epic", (runway.LOOP_END + 20 - otherSpec.startZ) / otherSpec.rollSpeed, 10)
			other.rider = 999
			session:fromServer("EggSpawned", mine)
			session:fromServer("EggSpawned", other)
			startRide(session, mine)
			local camera = session:service("Workspace").CurrentCamera
			-- One frame to sit the rider on their egg; from then on the camera follows them, as it would in the game.
			session:renderFrame(1 / 60)

			local otherRoot = parts.eggFolder.Egg2.Root
			local otherDust = parts.eggFolder.Egg2.Dust:FindFirstChildOfClass("ParticleEmitter")
			local echo = parts.eggFolder.Egg2.Echo:FindFirstChildOfClass("ParticleEmitter")
			local closing = (mineSpec.rollSpeed - otherSpec.rollSpeed) / 60
			local wrapped, lastGap = false, nil
			for _ = 1, 60 do
				camera.CFrame = roblox.CFrame.new(parts.root.CFrame.Position + Vector3.new(0, 10, -20))
				session:renderFrame(1 / 60)
				local rider = parts.root.CFrame.Position
				local otherZ = otherRoot.CFrame.Position.Z
				-- The other egg is always drawn just ahead of the rider, closing in steadily.
				local gap = otherZ - rider.Z
				expect.truthy(gap > 0 and gap < 35, "gap " .. gap)
				if lastGap then
					expect.near(gap, lastGap - closing, 0.05)
				end
				lastGap = gap
				expect.near(
					otherRoot.CFrame.Position.Y,
					runway.BASE_Y + modules.EggRig.rollHeight(otherSpec.radius),
					1e-3,
					"on the ground"
				)
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

	describe("Client: rare egg messages", function()
		local function clockText(time)
			local date = os.date("*t", math.floor(time))
			local hour = if date.hour % 12 == 0 then 12 else date.hour % 12
			return string.format("%d:%02d:%02d %s", hour, date.min, date.sec, if date.hour < 12 then "AM" else "PM")
		end

		it("says where and when a Secret or rarer egg spawned", function()
			local session, parts = startClient()
			local folder = session:service("ReplicatedStorage").Shared
			local Rarities = session:require(folder.Config.Rarities)
			local Zones = session:require(folder.Config.Zones)
			local banner = hud(parts).Announcement
			expect.equal(banner.Visible, false)

			local secret = eggData(session, 1, 3, "Secret", 0)
			session:fromServer("EggSpawned", secret, true)
			session:renderFrame(1 / 60)
			expect.equal(banner.Visible, true)
			expect.equal(banner.Title.Text, "SECRET EGG SPAWNED!")
			expect.equal(banner.Detail.Text, `Start of the {Zones.List[3].name} zone at {clockText(secret.spawnTime)}`)
			-- In big white letters, with no box behind them.
			expect.equal(banner.BackgroundTransparency, 1)
			expect.equal(banner.Title.TextColor3, roblox.Color3.new(1, 1, 1))
			expect.truthy(banner.Title.TextSize >= 60, "large")
			expect.equal(banner.Detail.TextColor3, roblox.Color3.new(1, 1, 1))
			-- And an alert everyone hears.
			task.wait(1.2)
			local alert = session:require(folder.Config.Sounds).SECRET_ALERT
			expect.equal(session.soundsPlayed[alert.id], #alert.notes, "the alert's notes")
			-- It stays up for five seconds.
			task.wait(3.5)
			expect.equal(banner.Visible, true, "still up after 4.7 s")
			task.wait(0.6)
			expect.equal(banner.Visible, false, "gone after 5 s")
			session:fromServer("EggSpawned", eggData(session, 4, 3, "Secret", 0), true)
			session:renderFrame(1 / 60)
			expect.equal(banner.Visible, true)
			expect.truthy(Rarities.Info.Secret.announce)

			-- Other messages use the toast and do not hide it.
			session:fromServer("Announce", "Something else", nil)
			expect.equal(hud(parts).Toast.Text, "Something else")
			expect.equal(banner.Visible, true)

			session:fromServer("EggSpawned", eggData(session, 2, 6, "Eternal", 0), true)
			session:renderFrame(1 / 60)
			expect.equal(banner.Title.Text, "ETERNAL EGG SPAWNED!")
			local prefix = `Start of the {Zones.List[6].name} zone at `
			expect.truthy(banner.Detail.Text:find(prefix, 1, true) == 1, banner.Detail.Text)
		end)

		it("says nothing for eggs below Secret, or for a lineup egg's later laps", function()
			local session, parts = startClient()
			session:fromServer("EggSpawned", eggData(session, 1, 1, "Legendary", 0), true)
			session:fromServer("EggSpawned", eggData(session, 2, 2, "Mythic", 0), true)
			-- The server only asks for the message on a lineup egg's first lap of the day.
			session:fromServer("EggSpawned", eggData(session, 3, 3, "Secret", 0), false)
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Announcement.Visible, false)
		end)

		it("does not announce rare eggs that were already rolling when the player joined", function()
			local probe = Studio.open(place, { isServer = false })
			local _, parts = startClient({
				{ id = 9, zone = 3, rarity = "Secret", kind = "Yeti", spawnTime = probe.clock - 4, lateral = 0 },
			})
			expect.truthy(parts.eggFolder:FindFirstChild("Egg9"))
			expect.equal(hud(parts).Announcement.Visible, false)
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

		it("holds an egg from the Eggs tab and puts it down where the player clicks, only in their own pen", function()
			local session, parts = startClient()
			ownPlot(session)
			local Plots = session:require(session:service("ReplicatedStorage").Shared.Plots)
			-- The egg tools the server puts in the player's Roblox inventory (see the server's EggToolService).
			local backpack = parts.player:FindFirstChildOfClass("Backpack")
			local tools = {}
			for _, kind in { "Leafy", "Toadstool" } do
				local tool = roblox.Instance.new("Tool")
				tool.Name = kind .. " Egg"
				tool:SetAttribute("EggKind", kind)
				tool.Parent = backpack
				tools[kind] = tool
			end
			local tabs = hud(parts).SideTabs
			expect.equal(tabs.EggsTab.Badge.Text, "2")
			expect.equal(panel(parts).Visible, false)
			-- The tabs show pictures: an egg, and a paw.
			expect.truthy(tabs.EggsTab:FindFirstChild("EggPicture"), "an egg")
			expect.truthy(tabs.PetsTab:FindFirstChild("PawPicture"), "a paw")

			session:fire(tabs.EggsTab, "Activated")
			expect.equal(panel(parts).Visible, true)
			expect.equal(panel(parts).Title.Text, "Your eggs (2)")
			local cards = panel(parts).List.EggsPage.Eggs
			expect.equal(cards.Egg_a.Title.Text, "Leafy Egg")
			session:renderFrame(1 / 60)
			local preview = panel(parts).Preview
			expect.truthy(preview:FindFirstChildOfClass("Model"), "egg in the preview")
			expect.truthy(preview:FindFirstChildOfClass("Camera"), "preview camera")

			-- Hold: the egg goes in the player's hand, and the panel gets out of the way.
			session:fire(cards.Egg_b.Hold, "Activated")
			expect.equal(tools.Toadstool.Parent, parts.player.Character)
			expect.equal(panel(parts).Visible, false)

			-- Pointing outside their pen (another plot): a red ring, and a click does nothing but say so.
			local function pointAt(x, z)
				session.pointerRay = roblox.Ray.new(Vector3.new(x, 100, z), Vector3.new(0, -1, 0))
				session:renderFrame(1 / 60)
			end
			local otherX, otherZ = Plots.point(2, 25, 0)
			pointAt(otherX, otherZ)
			local placement = session:service("Workspace").EggPlacement
			expect.truthy(placement:FindFirstChild("Ghost"), "the egg it would put down")
			expect.equal(placement.Ring.Color, roblox.Color3.fromRGB(240, 80, 80))
			session:fire(tools.Toadstool, "Activated")
			expect.equal(#session:sent("PlaceEgg"), 0)
			expect.truthy(string.find(hud(parts).Toast.Text, "inside your pen"), hud(parts).Toast.Text)

			-- Pointing into their pen: a green ring, and a click asks the server to put it down right there.
			local x, z = Plots.point(1, 25, 0)
			pointAt(x, z)
			expect.equal(placement.Ring.Color, roblox.Color3.fromRGB(90, 230, 110))
			expect.near(placement.Ring.CFrame.Position.X, x, 1e-3)
			task.wait(0.35)
			session:fire(tools.Toadstool, "Activated")
			local sent = session:lastSent("PlaceEgg", "server")
			expect.equal(sent.args[1], "b")
			expect.near(sent.args[2], x, 1e-3)
			expect.near(sent.args[3], z, 1e-3)

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
			task.wait(0.35)
			session:fire(tools.Toadstool, "Activated")
			expect.equal(#session:sent("PlaceEgg"), 1)
			expect.truthy(string.find(hud(parts).Toast.Text, "only hatch 2 eggs"), hud(parts).Toast.Text)

			-- Putting the egg away hides the ghost.
			tools.Toadstool.Parent = backpack
			session:renderFrame(1 / 60)
			expect.falsy(placement:FindFirstChild("Ghost"))
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
				-- All of it: every part arrives with the root (which is the size of the whole pet), not left behind
				-- where pet models are built.
				local reach = model.PrimaryPart.Size.Magnitude
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						local away = (part.CFrame.Position - before[model]).Magnitude
						expect.truthy(away <= reach, `{model.Name}'s {part.Name} is {away} studs from it`)
					end
				end
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
			local cycle = CycleClock.CYCLE_LENGTH
			local cycleStart = math.floor(session.clock / cycle) * cycle + cycle
			session.clock = cycleStart - 1 / 60
			session:renderFrame(1 / 60)
			expect.near(Lighting.ClockTime, CycleClock.SUNRISE, 1e-3)
			-- Noon is half way through the 4:50 day.
			session.clock = cycleStart + 145 - 1 / 60
			session:renderFrame(1 / 60)
			expect.near(Lighting.ClockTime, 12, 1e-3)
			local noonBrightness = Lighting.Brightness
			-- The sun sets as the runway closes, 4:50 in; the afternoon light has already begun to fade.
			session.clock = cycleStart + CycleClock.CLOSE_AT - 1 / 60
			session:renderFrame(1 / 60)
			expect.near(Lighting.ClockTime, CycleClock.SUNSET, 1e-3)
			local sunsetBrightness = Lighting.Brightness
			expect.truthy(sunsetBrightness < noonBrightness, "dimmer at sunset")
			-- Midnight is half way through the 10-second night.
			session.clock = cycleStart + CycleClock.CLOSE_AT + 5 - 1 / 60
			session:renderFrame(1 / 60)
			expect.near(math.min(Lighting.ClockTime, 24 - Lighting.ClockTime), 0, 1e-3)
			expect.truthy(Lighting.Brightness < sunsetBrightness, "darkest in the night")
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
			for _, name in { "Luck", "Tabs", "Wallet", "DayNight", "Toast", "Announcement", "Leap", "Meters" } do
				expect.truthy(root:FindFirstChild(name), name)
			end
			-- No runway timer or zone name across the top.
			expect.falsy(root:FindFirstChild("Cycle"), "no runway timer")
			expect.falsy(root:FindFirstChild("Zone"), "no zone name")
			expect.truthy(root.Meters.Claim and root.Meters.Stamina and root.Meters.RideHint, "meters")
			expect.truthy(root.Tabs.Shop and root.Tabs.Settings, "tabs")
			expect.equal(root.Wallet.Eggs.Content.Value.Text, "2")
			expect.equal(root.Wallet.Dollars.Content.Value.Text, "$0")
			expect.equal(root.Wallet.Dollars.Under.Text, "", "no income yet")
			expect.equal(root.Wallet.Stamina.Content.Value.Text, "100")
			session:fromServer("DollarsChanged", 1520, 12)
			expect.equal(root.Wallet.Dollars.Content.Value.Text, "$1.52K")
			expect.equal(root.Wallet.Dollars.Under.Text, "+$12/s")
			-- Nothing open, and no luck boost running.
			expect.equal(root.ShopPanel.Visible, false)
			expect.equal(root.SettingsPanel.Visible, false)
			expect.equal(root.Backdrop.Visible, false)
			expect.equal(root.Luck.Visible, false)
		end)

		it("shows stamina, and says when the runway is about to close and when it closes", function()
			local session, parts = startClient()
			local root = hud(parts)

			session:fromServer("StaminaChanged", 40, session.clock, 0, 100)
			-- (Partway down the Desert, the second zone.)
			parts.root.Position = Vector3.new(0, 0, 900)
			session:renderFrame(1 / 60, 2)
			expect.equal(labelOf(root.Meters.Stamina).Text, "Stamina  40 / 100")
			expect.near(root.Meters.Stamina.Fill.Size.X.Scale, 0.4, 1e-6)

			-- Stamina regenerating is followed without further messages.
			session:fromServer("StaminaChanged", 40, session.clock, 10, 100)
			session:renderFrame(1, 3)
			expect.equal(labelOf(root.Meters.Stamina).Text, "Stamina  70 / 100")

			-- Into the warning, then the closure: a short message each time (the stand-in clock starts 5 s into a
			-- cycle; the runway closes at 290 s, 4:50 into it).
			session:renderFrame(1, 273)
			expect.truthy(root.Toast.Text:match("^Runway closes in %d+s!$"), root.Toast.Text)
			session:renderFrame(1, 10)
			expect.truthy(root.Toast.Text:match("^Runway closed"), root.Toast.Text)
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

		it("counts down to nightfall by day, and to sunrise by night, at the bottom right", function()
			local session, parts = startClient()
			local dayNight = hud(parts).DayNight
			-- The stand-in clock starts 5 s into a cycle; night falls 290 s in, as the runway closes.
			session:renderFrame(1 / 60)
			expect.equal(dayNight.Icon.Text, "🌙")
			expect.equal(dayNight.Label.Text, "in 4m 45s")
			session:renderFrame(1, 225)
			expect.equal(dayNight.Label.Text, "in 1m")
			session:renderFrame(1, 59)
			expect.equal(dayNight.Label.Text, "in 1s")
			-- Night: a sun and the time until the next sunrise, 10 s away.
			session:renderFrame(1, 1)
			expect.equal(dayNight.Icon.Text, "☀️")
			expect.equal(dayNight.Label.Text, "in 10s")
			expect.truthy(hud(parts).Toast.Text:match("^Runway closed"), "closed for the night")
			-- And day again 10 seconds later, as the runway reopens.
			session:renderFrame(1, 10)
			expect.equal(dayNight.Icon.Text, "🌙")
			expect.equal(dayNight.Label.Text, "in 4m 50s")
		end)

		it("follows the runway cycle when admins move it on", function()
			local session, parts = startClient()
			local workspace = session:service("Workspace")
			session:renderFrame(1 / 60)
			-- The stand-in clock starts 5 s into a cycle: 285 s on, the runway has closed.
			workspace:SetAttribute("CycleOffset", 285.5)
			session:renderFrame(1 / 60)
			expect.truthy(hud(parts).Toast.Text:match("^Runway closed"), hud(parts).Toast.Text)
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

	describe("Client: hub stations", function()
		local function layoutOf(session)
			return session:require(session:service("ReplicatedStorage").Shared.HubLayout)
		end

		-- Stands the character beside a station and uses its prompt. (A key that is not a station's is tried from
		-- beside the Sell stall.)
		local function useStation(session, parts, key)
			local stations = layoutOf(session).STATIONS
			local station = stations[key] or stations.Sell
			parts.root.CFrame = roblox.CFrame.new(station.x + 4, 13, station.z + 4)
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

		local function rows(panel)
			return panel.Body.Scroll
		end

		it("opens a station's panel from its prompt and closes it when the player walks away", function()
			local session, parts = startClient()
			local root = hud(parts)
			expect.equal(root.Trails.Visible, false)

			useStation(session, parts, "Trails")
			expect.equal(root.Trails.Visible, true)
			expect.equal(root.Sell.Visible, false)
			expect.equal(root.Fuse.Visible, false)
			expect.equal(root.Backdrop.Visible, true, "the world is dimmed behind it")

			parts.root.CFrame = roblox.CFrame.new(0, 13, 0)
			session:heartbeat(1 / 60)
			expect.equal(root.Trails.Visible, false)

			-- The close button works too, and prompts that are not stations are ignored.
			useStation(session, parts, "Sell")
			expect.equal(root.Sell.Visible, true)
			click(session, root.Sell.TitleBar.Close)
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
			local list = rows(panel)
			local leaf = list.Leaf.Action
			expect.equal(list.Leaf.TrailName.Text, "Leaf Trail")
			expect.truthy(string.find(list.Leaf.Boost.Text, "x1.5</font> Stamina", 1, true), list.Leaf.Boost.Text)
			expect.truthy(string.find(list.Leaf.Level.Text, "^Lvl 1 .*Common"), list.Leaf.Level.Text)
			expect.truthy(string.find(list.Rainbow.Level.Text, "^Lvl 9 .*Eternal"), list.Rainbow.Level.Text)
			-- Nine cards, each with a picture of its trail; the plain first trail has no particles in it.
			local cards = 0
			for _, child in list:GetChildren() do
				if child:IsA("Frame") and child:FindFirstChild("Picture") then
					cards += 1
				end
			end
			expect.equal(cards, 9)
			expect.truthy(list.Leaf.Picture:FindFirstChild("Ribbon"), "the ribbon")
			expect.falsy(list.Leaf.Picture:FindFirstChild("Speck1"), "no particles")
			expect.truthy(list.Rainbow.Picture:FindFirstChild("Halo") and list.Rainbow.Picture.Speck1, "the works")
			expect.equal(buttonText(leaf), "$100")
			expect.equal(buttonText(list.Rainbow.Action), "$750M")
			local tooExpensive = leaf.Face.BackgroundColor3

			session:fromServer("DollarsChanged", 600, 0)
			session:renderFrame(1 / 60)
			expect.truthy(leaf.Face.BackgroundColor3 ~= tooExpensive, "affordable trails light up")

			session:fromServer("TrailsUpdated", { "Leaf" }, "Leaf")
			session:renderFrame(1 / 60)
			expect.equal(buttonText(leaf), "Equipped")
			expect.equal(buttonText(list.Sunbeam.Action), "$1K")
			expect.equal(panel.Footer.Text, "You have $600.  Trail boost: Max Stamina x1.5")

			session:fromServer("TrailsUpdated", { "Leaf", "Sunbeam" }, "Sunbeam")
			session:renderFrame(1 / 60)
			expect.equal(buttonText(leaf), "Equip")
			expect.equal(buttonText(list.Sunbeam.Action), "Equipped")
		end)

		it("asks the server to buy and equip trails, and says how it went", function()
			local session, parts = startClient()
			local list = rows(hud(parts).Trails)
			useStation(session, parts, "Trails")
			session.invokeHandlers.BuyTrail = function(trailId)
				if trailId == "Rainbow" then
					return false, "NotEnoughDollars"
				end
				return true, "BoughtAndEquipped"
			end
			session.invokeHandlers.EquipTrail = function()
				return true, "Equipped"
			end

			click(session, list.Sunbeam.Action)
			expect.equal(session:lastSent("BuyTrail", "server").args[1], "Sunbeam")
			expect.equal(hud(parts).Toast.Text, "Sunbeam Trail equipped! Stamina x2")

			click(session, list.Rainbow.Action)
			expect.equal(hud(parts).Toast.Text, "Not enough dollars")

			-- Owned trails are equipped instead of bought; the one already equipped does nothing.
			session:fromServer("TrailsUpdated", { "Leaf", "Sunbeam" }, "Sunbeam")
			session:renderFrame(1 / 60)
			click(session, list.Leaf.Action)
			expect.equal(session:lastSent("EquipTrail", "server").args[1], "Leaf")
			click(session, list.Sunbeam.Action)
			expect.equal(#session:sent("EquipTrail", "server"), 1)
			expect.equal(#session:sent("BuyTrail", "server"), 2)
		end)

		it("lists the player's eggs at the Sell stall and sells them", function()
			local session, parts = startClient()
			local list = rows(hud(parts).Sell)
			useStation(session, parts, "Sell")
			session:fromServer("InventoryChanged", {
				eggs = {
					{ uid = "a", zone = 2, rarity = "Mythic", kind = "Sphinx", claimedAt = 0 },
					{ uid = "b", zone = 1, rarity = "Common", kind = "Leafy", claimedAt = 0 },
					{ uid = "c", zone = 1, rarity = "Common", kind = "Leafy", claimedAt = 0 },
					{ uid = "d", zone = 1, rarity = "Common", kind = "Leafy", claimedAt = 0 },
				},
				hatching = {},
				pets = {},
				penLevel = 1,
				eggCapacity = 2,
				petCapacity = 10,
				mount = "",
			})
			session:renderFrame(1 / 60)
			expect.equal(list.Empty.Visible, false)
			local leafy = list.Egg_Leafy
			expect.equal(leafy.EggName.Text, "Leafy Egg")
			expect.equal(leafy.Details.Text, "Common  x3   $25 each")
			expect.equal(list.Egg_Sphinx.Details.Text, "Mythic  x1   $900 each")
			expect.truthy(leafy.LayoutOrder < list.Egg_Sphinx.LayoutOrder, "in runway order")

			session.invokeHandlers.SellEggs = function(_kind, count)
				return count, count * 25
			end
			click(session, leafy.SellAll)
			local request = session:lastSent("SellEggs", "server")
			expect.equal(request.args[1], "Leafy")
			expect.equal(request.args[2], 3)
			expect.equal(hud(parts).Toast.Text, "Sold 3 Leafy Eggs for $75")

			click(session, leafy.SellOne)
			expect.equal(session:lastSent("SellEggs", "server").args[2], 1)
			expect.equal(hud(parts).Toast.Text, "Sold Leafy Egg for $25")

			-- Once everything is sold, the panel says so.
			session:fromServer("InventoryChanged", {
				eggs = {},
				hatching = {},
				pets = {},
				penLevel = 1,
				eggCapacity = 2,
				petCapacity = 10,
				mount = "",
			})
			session:renderFrame(1 / 60)
			expect.equal(list.Empty.Visible, true)
			expect.falsy(list:FindFirstChild("Egg_Leafy"), "sold rows are gone")
		end)

		it("explains the fuse machine", function()
			local session, parts = startClient()
			useStation(session, parts, "Fuse")
			local panel = hud(parts).Fuse
			expect.equal(panel.Visible, true)
			local list = rows(panel)
			expect.truthy(list.HowItWorks.Text:find("3 of the same pet"), list.HowItWorks.Text)
			expect.truthy(list.Odds.Text:find("1 in 3"), list.Odds.Text)
		end)
	end)

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
			session:fire(root.Wallet.Dollars.Content.Add, "Activated")
			expect.equal(root.ShopPanel.Visible, true)
			task.wait(0.1)
			expect.truthy(chips.Dollars.Face.BackgroundColor3 ~= chips.Luck.Face.BackgroundColor3, "Dollars chip lit")
			expect.truthy(chips.Featured.Face.BackgroundColor3 ~= featuredColor, "Featured chip no longer lit")
			expect.falsy(root.Wallet.Eggs.Content:FindFirstChild("Add"), "eggs cannot be bought")
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
			expect.equal(root.Wallet.Dollars.Content.Value.Text, "$12.5K")
			expect.equal(pen.Current.Level.Text, "LEVEL 3")
			expect.equal(buttonText(pen.Buttons.BuyDollars), "30K")

			session:fromServer("PlayerStateUpdated", { dollars = 0, penLevel = 9, passes = { "DoubleDollars" } })
			expect.equal(root.Wallet.Dollars.Content.Value.Text, "$0")
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
	describe("Client: training stick", function()
		local CFrame = roblox.CFrame
		local ROBUX = utf8.char(0xE002)

		-- Builds plots on this device as the server would: plot 1 is the local player's, plot 2 someone else's.
		local function buildPlots(session)
			local PlotModels = session:require(session:service("ServerScriptService").Server.Map.PlotModels)
			local map = roblox.Instance.new("Folder")
			map.Name = "Map"
			local plots = roblox.Instance.new("Folder")
			plots.Name = "Plots"
			plots.Parent = map
			map.Parent = session:service("Workspace")
			local mine = PlotModels.buildPlot(plots, 1)
			mine:SetAttribute("Owner", LOCAL_USER_ID)
			local theirs = PlotModels.buildPlot(plots, 2)
			theirs:SetAttribute("Owner", 99)
			return mine.TrainingStick, theirs.TrainingStick
		end

		local function modules(session)
			local folder = session:service("ReplicatedStorage").Shared
			return {
				Plots = session:require(folder.Plots),
				StickModels = session:require(folder.StickModels),
			}
		end

		local function start(session, level)
			session:fromServer("TrainingStarted", { level = level or 1, plot = 1, startedAt = session.clock })
			session:renderFrame(1 / 60)
		end

		local function popupTexts(parts)
			local texts = {}
			for _, gui in parts.playerGui.TrainingPopups:GetChildren() do
				table.insert(texts, gui.Amount.Text)
			end
			return texts
		end

		it(
			"shows the stick's prompts only on the player's own plot, and opens the upgrade panel from the sign",
			function()
				local session, parts = startClient()
				local mine, theirs = buildPlots(session)
				session:renderFrame(1 / 60)
				expect.equal(mine.Seat.Train.Enabled, true)
				expect.equal(mine.Sign.Board.Upgrade.Enabled, true)
				expect.equal(theirs.Seat.Train.Enabled, false)
				expect.equal(theirs.Sign.Board.Upgrade.Enabled, false)

				local m = modules(session)
				local x, z = m.Plots.point(1, m.Plots.STICK_SIGN_SPOT[1] - 3, m.Plots.STICK_SIGN_SPOT[2])
				parts.root.CFrame = CFrame.new(x, 13, z)
				session:fire(
					session:service("ProximityPromptService"),
					"PromptTriggered",
					mine.Sign.Board.Upgrade,
					parts.player
				)
				session:heartbeat(1 / 60)
				session:renderFrame(1 / 60)
				expect.equal(hud(parts).Stick.Visible, true)
				-- All eight tiers, in a row under the card.
				local chips = 0
				for _, child in hud(parts).Stick.Body.Scroll.Ladder:GetChildren() do
					if child:IsA("Frame") then
						chips += 1
					end
				end
				expect.equal(chips, 8)

				-- Walking away closes it.
				parts.root.CFrame = CFrame.new(0, 13, 0)
				session:heartbeat(1 / 60)
				expect.equal(hud(parts).Stick.Visible, false)
			end
		)

		it("shows the training card while rolling, floats a +1 over the player for each rep, and stops", function()
			local session, parts = startClient()
			local mine = buildPlots(session)
			local card = hud(parts).Training.Card
			expect.equal(hud(parts).Training.Visible, false)

			start(session)
			expect.equal(hud(parts).Training.Visible, true)
			expect.equal(card.TierName.Text, "STICK")
			expect.equal(card.Rate.Text, "⚡ +1 a roll  •  +4/s")
			expect.equal(mine.Seat.Train.Enabled, false, "no prompt while rolling")

			session:fromServer("TrainingRep", 1, false)
			session:fromServer("TrainingRep", 1, false)
			session:renderFrame(1 / 60)
			expect.equal(table.concat(popupTexts(parts), ","), "+1,+1")
			expect.equal(card.Gained.Text, "+2 Max Stamina so far")
			-- They float up and are gone within a second.
			session:renderFrame(0.1, 12)
			expect.equal(#popupTexts(parts), 0)

			-- The Stop button, or a jump, gets off (asking once).
			session:fire(card.Stop, "Activated")
			expect.equal(#session:sent("StopTraining", "server"), 1)
			session:fire(card.Stop, "Activated")
			expect.equal(#session:sent("StopTraining", "server"), 1)
			session:fromServer("TrainingEnded", "Stopped")
			session:renderFrame(1 / 60)
			expect.equal(hud(parts).Training.Visible, false)
			expect.equal(mine.Seat.Train.Enabled, true)

			start(session)
			session:fire(session:service("UserInputService"), "JumpRequest")
			expect.equal(#session:sent("StopTraining", "server"), 1, "the jump that got them on is ignored")
			task.wait(0.45)
			session:fire(session:service("UserInputService"), "JumpRequest")
			expect.equal(#session:sent("StopTraining", "server"), 2)
		end)

		it("puts up 2x bubbles to tap, and shows the boost", function()
			local session, parts = startClient()
			buildPlots(session)
			start(session)
			local training = hud(parts).Training

			session:fromServer("TrainingBubble", 1, session.clock + 2.5)
			session:renderFrame(1 / 60)
			expect.equal(training.Bubble.Visible, true)
			session:fire(training.Bubble.Tap, "Activated")
			expect.equal(session:lastSent("ClaimTrainingBoost", "server").args[1], 1)
			session:fire(training.Bubble.Tap, "Activated")
			expect.equal(#session:sent("ClaimTrainingBoost", "server"), 1, "tapped once")
			session:renderFrame(0.1, 4)
			expect.equal(training.Bubble.Visible, false, "popped")

			session:fromServer("TrainingBoost", session.clock + 1.5)
			session:renderFrame(1 / 60)
			expect.equal(training.Card.Boost.Visible, true)
			expect.equal(training.Card.Rate.Text, "⚡ +2 a roll  •  +8/s")
			expect.equal(hud(parts).Toast.Text, "2x STAMINA!")
			session:fromServer("TrainingRep", 2, true)
			session:renderFrame(1 / 60)
			expect.equal(popupTexts(parts)[1], "2x +2")
			session:renderFrame(0.1, 16)
			expect.equal(training.Card.Boost.Visible, false, "the boost runs out")

			-- A bubble nobody taps goes when its time is up.
			session:fromServer("TrainingBubble", 2, session.clock + 0.5)
			session:renderFrame(1 / 60)
			expect.equal(training.Bubble.Visible, true)
			session:renderFrame(0.1, 6)
			expect.equal(training.Bubble.Visible, false)
		end)

		it("spins the roller under a rider and runs them on it, as on an egg, then lets them go", function()
			local session, parts = startClient()
			local mine, theirs = buildPlots(session)
			local m = modules(session)

			-- An R15 character: a joint for each part the pose turns.
			parts.humanoid.RigType = Enum.HumanoidRigType.R15
			parts.humanoid.HipHeight = 2
			parts.root.Size = Vector3.new(2, 2, 1)
			local motors = {}
			for _, name in
				{
					"Root",
					"Waist",
					"Neck",
					"LeftHip",
					"RightHip",
					"LeftKnee",
					"RightKnee",
					"LeftAnkle",
					"RightAnkle",
					"LeftShoulder",
					"RightShoulder",
					"LeftElbow",
					"RightElbow",
				}
			do
				local motor = roblox.Instance.new("Motor6D")
				motor.Name = name
				-- Roblox always has one; Lune has none until it is set.
				motor.Transform = CFrame.identity
				motor.Parent = parts.root.Parent
				motors[name] = motor
			end
			-- Held on top of the roller, as TrainingService does.
			parts.root.CFrame = m.StickModels.riderCFrame(1, 1, 3)
			local rest = mine.Roller.PrimaryPart.CFrame
			local theirRest = theirs.Roller.PrimaryPart.CFrame
			-- Splashes and other riders' reps only show near the camera.
			cameraAt(session, m.StickModels.standCFrame(1).Position)
			mine:SetAttribute("Rider", LOCAL_USER_ID)
			start(session)
			session:renderFrame(1 / 30, 15)
			local turned = mine.Roller.PrimaryPart.CFrame
			expect.near((turned.Position - m.StickModels.axleCFrame(1, 1).Position).Magnitude, 0, 1e-3)
			expect.truthy(turned.UpVector:Dot(rest.UpVector) < 0.999, "the roller turns")
			-- Running on the spot as on an egg: leaning forward, the legs taking turns to swing forward (-Z).
			expect.truthy(motors.Root.Transform.LookVector.Y < -0.1, "leaning forward")
			local most, least = -math.huge, math.huge
			for _ = 1, 24 do
				session:renderFrame(1 / 60)
				local left = motors.LeftHip.Transform:VectorToWorldSpace(Vector3.new(0, -1, 0))
				local right = motors.RightHip.Transform:VectorToWorldSpace(Vector3.new(0, -1, 0))
				most, least = math.max(most, right.Z - left.Z), math.min(least, right.Z - left.Z)
			end
			expect.truthy(most > 0.5 and least < -0.5, `legs take turns: {least} to {most}`)
			expect.equal(mine.SplashFx.Splash.Enabled, true, "splashing")
			expect.equal(theirs.Roller.PrimaryPart.CFrame, theirRest, "nobody on theirs, so it stays still")

			-- Another player rolling on their own stick: their "+5"s show here too, worked out on this device.
			local other = session:addPlayer(99, "Other")
			other.Character.HumanoidRootPart.CFrame = m.StickModels.riderCFrame(2, 1, 3)
			theirs:SetAttribute("Rider", 99)
			theirs:SetAttribute("RepGain", 5)
			cameraAt(session, m.StickModels.standCFrame(2).Position)
			session:renderFrame(0.13, 4)
			local fives = 0
			for _, text in popupTexts(parts) do
				if text == "+5" then
					fives += 1
				end
			end
			expect.truthy(fives >= 1, "the other rider's reps")

			-- Off the stick: the joints blend back to the character's own animations (which set them every frame),
			-- then are left to them.
			mine:SetAttribute("Rider", 0)
			session:renderFrame(1 / 30, 15)
			for _, motor in motors do
				motor.Transform = CFrame.identity
			end
			session:renderFrame(1 / 30)
			expect.equal(motors.RightShoulder.Transform, CFrame.identity)
			expect.equal(motors.LeftHip.Transform, CFrame.identity)
			expect.equal(mine.SplashFx.Splash.Enabled, false)
		end)

		it("offers the next tier in the shop, for Robux or dollars, until the stick is maxed", function()
			local session, parts = startClient()
			local card = shopBody(parts).Featured.StickUpgrade
			expect.equal(card.Current.TierName.Text, "Stick")
			expect.equal(card.Next.TierName.Text, "Plank")
			expect.truthy(card.Current.Preview:FindFirstChild("Stick"), "the stick in 3D")
			expect.truthy(card.Next.Preview:FindFirstChild("Plank"), "the plank in 3D")
			expect.equal(card.Gain.Text, "+2 STAMINA\nPER ROLL")
			expect.equal(buttonText(card.Buttons.BuyDollars), "$500")
			expect.equal(buttonText(card.Buttons.BuyRobux), ROBUX .. " 29")
			session:fire(card.Buttons.BuyDollars, "Activated")
			expect.equal(session:lastSent("BuyWithDollars", "server").args[1], "StickUpgrade")
			session:fire(card.Buttons.BuyRobux, "Activated")
			expect.equal(session:lastSent("RequestPurchase", "server").args[1], "StickUpgrade")

			-- The pen upgrade is still there, after it.
			expect.truthy(shopBody(parts).Featured.PenUpgrade.LayoutOrder > card.LayoutOrder, "stick first")

			session:fromServer("PlayerStateUpdated", { stickLevel = 4 })
			session:renderFrame(1 / 60)
			expect.equal(card.Current.TierName.Text, "Tree Trunk")
			expect.equal(card.Next.TierName.Text, "Metal Pipe")
			expect.truthy(card.Next.Preview:FindFirstChild("MetalPipe"), "the new preview")
			expect.equal(buttonText(card.Buttons.BuyDollars), "$500K")

			session:fromServer("PlayerStateUpdated", { stickLevel = 8 })
			expect.equal(card.Headline.Text, "STICK MAXED OUT!")
			expect.equal(card.Buttons.Visible, false)
			expect.equal(card.Next.Visible, false)
			expect.equal(card.Maxed.Visible, true)
		end)
	end)
end
