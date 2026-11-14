-- Draws every egg on the runway and keeps riders sitting on them.
--
-- Eggs are not sent from the server as parts. The server only says "an egg appeared / was mounted / was left /
-- is gone", and each device works out where every egg is from the shared clock (Shared/EggMotion). That keeps
-- eggs perfectly smooth and costs almost no network traffic.
--
-- Riders are pinned to this device's copy of the egg, so nobody appears to slide off because of lag. An egg without
-- a rider follows its path round the obstacles (Shared/Obstacles), worked out here exactly as on the server.
--
-- Rolling eggs kick up a small cloud of dust behind them, coloured for the ground they are rolling over.
--
-- Each egg's look comes from Shared/EggModels (a blocky model, different for every zone and rarity), built into parts
-- by Shared/EggRig. The parts are welded to one invisible, anchored root part, so moving an egg each frame is a
-- single CFrame write.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local EggRig = Load.shared("EggRig")
local EggMotion = Load.shared("EggMotion")
local EggSpec = Load.shared("EggSpec")
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")
local Obstacles = Load.shared("Obstacles")
local Rarities = Load.shared("Config", "Rarities")
local Runway = Load.shared("Runway")
local Tuning = Load.shared("Config", "Tuning")

local localPlayer = Players.LocalPlayer

-- How far above the top of the egg a seated rider's root part sits.
local SEAT_HEIGHT = 2
-- Riders face down the runway (+Z).
local FACE_FORWARD = CFrame.Angles(0, math.pi, 0)
-- How quickly another rider's egg catches up with their reported steering.
local LATERAL_SMOOTHING = 12

local CAN_AFFORD_COLOR = Color3.fromRGB(120, 255, 130)
local CANNOT_AFFORD_COLOR = Color3.fromRGB(255, 95, 95)
local TAKEN_COLOR = Color3.fromRGB(230, 230, 230)

-- Eggs with an even id lie the other way round (pointed end to the left), so the runway looks less uniform.
local FLIPPED = CFrame.Angles(0, math.pi, 0)
-- How quickly a riderless egg settles onto its path after its rider leaves (it starts from where it was drawn).
local OFFSET_SETTLE = 6

-- The dust an egg kicks up, by the zone it is rolling through.
local DUST_COLORS = {
	{ 182, 160, 118 }, -- Forest: dry earth
	{ 236, 208, 152 }, -- Desert: sand
	{ 246, 250, 255 }, -- Snow: powder
	{ 214, 236, 248 }, -- Ocean: spray off the boardwalk
	{ 112, 102, 102 }, -- Volcano: ash
	{ 176, 156, 116 }, -- Prehistoric: dirt
}
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
-- How long a bumped egg wobbles.
local WOBBLE_TIME = 0.6

export type ClientEgg = {
	id: number,
	zone: number,
	rarity: string,
	-- Which egg it is: a design name in Shared/EggModels, such as "MossStag".
	kind: string,
	spec: any,
	spawnTime: number,
	startZ: number,
	-- Where it fades out if nobody is riding it.
	fadeZ: number,
	-- Side to side: for a ridden egg, where it is drawn and where it is heading (another rider's egg eases toward
	-- the last position the server reported). Without a rider, the egg follows `path`, drawn `offset` studs off
	-- it while it settles after its rider leaves.
	lateral: number,
	targetLateral: number,
	path: any,
	offset: number,
	riderUserId: number?,
	bouncesLeft: number,
	bounceTime: number?,
	cracking: boolean,
	model: Model,
	-- The invisible part every other part is welded to. Moving it moves the whole egg.
	root: Part,
	-- Which way round the egg lies.
	facing: CFrame,
	needLabel: TextLabel,
	-- The dust cloud behind it: an invisible part that follows the egg along the ground (it does not roll).
	dust: BasePart,
	dustEmitter: ParticleEmitter,
	dustZone: number?,
	-- Whether it has landed from its chute, and the last hop it puffed dust for.
	landed: boolean,
	puffedBounce: number?,
	wobbleAt: number?,
}

local EggController = {}

local eggs: { [number]: ClientEgg } = {}
-- One finished model per kind of egg, cloned for every egg of that kind.
local templates: { [string]: Model } = {}
local eggFolder: Folder
local localMaxStamina = Tuning.BASE_MAX_STAMINA

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function refreshLabel(egg: ClientEgg)
	if egg.riderUserId ~= nil then
		egg.needLabel.Text = "Taken"
		egg.needLabel.TextColor3 = TAKEN_COLOR
	else
		egg.needLabel.Text = "Needs " .. NumberFormat.abbreviate(egg.spec.requirement)
		egg.needLabel.TextColor3 = if localMaxStamina >= egg.spec.requirement
			then CAN_AFFORD_COLOR
			else CANNOT_AFFORD_COLOR
	end
end

local function newEggPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function newLabel(parent: Instance, text: string, color: Color3, position: UDim2, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = parent
	return label
end

-- Every egg of a kind has the same zone and rarity (see Config/Zones), so the spec, and so the size, is the same.
local function getTemplate(spec, kind: string): Model
	local template = templates[kind]
	if template == nil then
		template = EggRig.build(kind, spec)
		templates[kind] = template
	end
	return template
end

-- A copy of the egg's model, with the label that shows its rarity and stamina requirement.
local function buildModel(spec, kind: string, rarity: string, id: number): (Model, Part, TextLabel)
	local rarityColor = rgb(Rarities.Info[rarity].color)

	local model = getTemplate(spec, kind):Clone()
	model.Name = "Egg" .. id
	local root = model:FindFirstChild("Root") :: Part
	model.PrimaryPart = root

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Adornee = root
	billboard.Size = UDim2.fromScale(11, 3.6)
	billboard.StudsOffset = Vector3.new(0, spec.radius + 3.2, 0)
	billboard.MaxDistance = 260
	billboard.LightInfluence = 0
	billboard.Parent = root

	newLabel(billboard, rarity, rarityColor, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.55))
	local needLabel = newLabel(billboard, "", CAN_AFFORD_COLOR, UDim2.fromScale(0, 0.55), UDim2.fromScale(1, 0.45))

	return model, root, needLabel
end

-- The dust an egg kicks up as it rolls: puffs from a strip across its width, drifting up and back.
local function addDust(model: Model, spec): (BasePart, ParticleEmitter)
	local dust = newEggPart("Dust", model)
	dust.Transparency = 1
	dust.Size = Vector3.new(spec.halfLength * 1.5, 0.2, 0.6)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Dust"
	emitter.Texture = DUST_TEXTURE
	emitter.Rate = 8 + spec.radius * 3
	emitter.Lifetime = NumberRange.new(0.7, 1.3)
	emitter.Speed = NumberRange.new(1.5, 4)
	emitter.SpreadAngle = Vector2.new(35, 35)
	-- Up, and back up the runway (eggs roll towards +Z).
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, 1.5, -2)
	emitter.Drag = 2
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.radius * 0.45),
		NumberSequenceKeypoint.new(1, spec.radius * 1.3),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.Enabled = false
	emitter.Parent = dust
	return dust, emitter
end

local function eggZ(egg: ClientEgg, now: number): number
	return EggMotion.zAt(egg.spawnTime, egg.startZ, egg.spec.rollSpeed, now)
end

-- Where an egg is drawn side to side: where its rider has it, or along its path round the obstacles.
local function currentLateral(egg: ClientEgg, now: number): number
	if egg.riderUserId ~= nil then
		return egg.lateral
	end
	return Obstacles.lateralAt(egg.path, eggZ(egg, now)) + egg.offset
end

-- Sends a riderless egg along a fresh path from `lateral` at `z`. It is drawn `drawn` studs across right now, and
-- settles onto the path from there, so it does not jump.
local function setPath(egg: ClientEgg, lateral: number, z: number, now: number, drawn: number)
	egg.lateral = lateral
	egg.path = Obstacles.planPath(lateral, z, egg.fadeZ, egg.spec.halfLength, egg.spec.radius)
	egg.offset = drawn - Obstacles.lateralAt(egg.path, eggZ(egg, now))
end

-- Where an egg is right now: side-to-side position, height of its centre, distance down the runway.
local function eggPosition(egg: ClientEgg, now: number): (number, number, number)
	local z = eggZ(egg, now)
	local y = Runway.surfaceY(z)
		+ egg.spec.radius
		+ EggMotion.hopOffset(egg.bounceTime, now, Tuning.HOP_DURATION, Tuning.HOP_HEIGHT)
		+ EggMotion.dropOffset(now - egg.spawnTime, Tuning.EGG_DROP_TIME, Tuning.EGG_DROP_HEIGHT)
	return currentLateral(egg, now), y, z
end

local function addEgg(data)
	if typeof(data) ~= "table" or eggs[data.id] ~= nil then
		return
	end
	local spec = EggSpec.get(data.zone, data.rarity)
	if spec == nil then
		return
	end
	-- The egg must be one of that zone's eggs of that rarity; fall back to the first one if not.
	local kind = data.kind
	if typeof(kind) ~= "string" or not table.find(EggSpec.eggsOf(data.zone, data.rarity), kind) then
		kind = EggSpec.pickEgg(data.zone, data.rarity, 0)
	end
	if kind == nil then
		return
	end

	local model, root, needLabel = buildModel(spec, kind, data.rarity, data.id)
	local dust, dustEmitter = addDust(model, spec)
	-- Eggs land at their zone's chute unless an admin dropped one somewhere else (the server worked out its fade
	-- line the same way: Logic/RunwaySim).
	local startZ = if typeof(data.startZ) == "number"
		then data.startZ
		else Runway.zoneStartZ(data.zone) + Tuning.EGG_SPAWN_OFFSET
	local fadeZ = math.max(Runway.fadeZ(data.zone), math.min(startZ + Runway.ZONE_LENGTH, Runway.LENGTH))
	local pathZ = if typeof(data.pathZ) == "number" then data.pathZ else startZ
	local egg: ClientEgg = {
		id = data.id,
		zone = data.zone,
		rarity = data.rarity,
		kind = kind,
		spec = spec,
		spawnTime = data.spawnTime,
		startZ = startZ,
		fadeZ = fadeZ,
		lateral = data.lateral,
		targetLateral = data.lateral,
		path = Obstacles.planPath(data.lateral, pathZ, fadeZ, spec.halfLength, spec.radius),
		offset = 0,
		riderUserId = data.rider,
		bouncesLeft = data.bounces,
		bounceTime = data.bounceTime,
		cracking = data.cracking == true,
		model = model,
		root = root,
		facing = if data.id % 2 == 0 then FLIPPED else CFrame.identity,
		needLabel = needLabel,
		dust = dust,
		dustEmitter = dustEmitter,
		dustZone = nil,
		landed = false,
		puffedBounce = data.bounceTime,
		wobbleAt = nil,
	}
	eggs[egg.id] = egg
	refreshLabel(egg)

	local x, y, z = eggPosition(egg, Workspace:GetServerTimeNow())
	root.CFrame = CFrame.new(x, y, z) * egg.facing
	model.Parent = eggFolder
end

-- A cartoon splat left on the runway where an egg cracked.
local function showSplat(egg: ClientEgg, x: number, z: number)
	local ground = Runway.surfaceY(z)
	local flat = CFrame.Angles(0, 0, math.pi / 2)
	local pieces = {
		{ diameter = egg.spec.radius * 3.4, color = Color3.fromRGB(250, 250, 245), height = 0.12 },
		{ diameter = egg.spec.radius * 1.5, color = Color3.fromRGB(255, 200, 40), height = 0.3 },
	}
	for _, piece in pieces do
		local part = newEggPart("Splat", eggFolder)
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(piece.height, piece.diameter, piece.diameter)
		part.Color = piece.color
		part.CFrame = CFrame.new(x, ground + piece.height / 2, z) * flat
		local tween = TweenService:Create(part, TweenInfo.new(0.6, Enum.EasingStyle.Linear), { Transparency = 1 })
		task.delay(2.2, function()
			tween:Play()
		end)
		task.delay(3, function()
			part:Destroy()
		end)
	end
end

local function removeEgg(eggId: number, reason: string?)
	local egg = eggs[eggId]
	if egg == nil then
		return
	end
	eggs[eggId] = nil

	if reason == "Cracked" then
		local x, _, z = eggPosition(egg, Workspace:GetServerTimeNow())
		showSplat(egg, x, z)
		egg.model:Destroy()
		return
	end

	-- Everything else fades out quickly.
	egg.needLabel.Parent.Enabled = false
	for _, descendant in egg.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= egg.root then
			TweenService:Create(descendant, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
	task.delay(0.3, function()
		egg.model:Destroy()
	end)
end

-- Holds a rider's character on top of an egg.
local function pinRider(userId: number, x: number, y: number, z: number, radius: number)
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = CFrame.new(x, y + radius + SEAT_HEIGHT, z) * FACE_FORWARD
	end
end

local function render(deltaTime: number)
	local now = Workspace:GetServerTimeNow()
	local smoothing = math.min(1, deltaTime * LATERAL_SMOOTHING)
	local localUserId = localPlayer.UserId

	local settle = math.exp(-deltaTime * OFFSET_SETTLE)

	for eggId, egg in eggs do
		-- The local rider steers their own egg directly (see RideController); everyone else's eases toward
		-- the last position the server reported. A riderless egg settles onto its path.
		if egg.riderUserId == nil then
			egg.offset *= settle
		elseif egg.riderUserId ~= localUserId then
			egg.lateral += (egg.targetLateral - egg.lateral) * smoothing
		end

		local x, y, z = eggPosition(egg, now)
		if z > Runway.LENGTH + 40 or (egg.riderUserId == nil and z > egg.fadeZ + 30) then
			-- Safety net: the server removes eggs at the end of their lap, but never draw one far past it.
			removeEgg(eggId, nil)
			continue
		end

		local wobble = CFrame.identity
		if egg.wobbleAt then
			local t = now - egg.wobbleAt
			if t < WOBBLE_TIME then
				wobble = CFrame.Angles(0, 0, math.sin(t * 32) * 0.22 * (1 - t / WOBBLE_TIME))
			else
				egg.wobbleAt = nil
			end
		end
		local angle = EggMotion.rollAngle(z - egg.startZ, egg.spec.radius)
		egg.root.CFrame = CFrame.new(x, y, z) * wobble * CFrame.Angles(angle, 0, 0) * egg.facing

		-- Dust: only while rolling along the ground, coloured for the zone underfoot; a puff on each landing.
		local ground = Runway.surfaceY(z)
		egg.dust.CFrame = CFrame.new(x, ground + 0.2, z - egg.spec.radius * 0.6)
		local onGround = y - ground - egg.spec.radius < 0.3
		egg.dustEmitter.Enabled = onGround and not egg.cracking
		local zone = Runway.zoneAt(z)
		if zone and zone ~= egg.dustZone then
			egg.dustZone = zone
			local color = DUST_COLORS[zone]
			egg.dustEmitter.Color = ColorSequence.new(Color3.fromRGB(color[1], color[2], color[3]))
		end
		if onGround and not egg.landed then
			egg.landed = true
			egg.dustEmitter:Emit(10)
		end
		if onGround and egg.bounceTime and egg.puffedBounce ~= egg.bounceTime and now > egg.bounceTime + 0.1 then
			egg.puffedBounce = egg.bounceTime
			egg.dustEmitter:Emit(8)
		end

		if egg.riderUserId ~= nil then
			pinRider(egg.riderUserId, x, y, z, egg.spec.radius)
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- For other controllers

function EggController.GetEgg(eggId: number): ClientEgg?
	return eggs[eggId]
end

-- Hands an egg to a rider: from now on it is drawn where they steer it, starting from wherever it is.
function EggController.SetRider(eggId: number, userId: number)
	local egg = eggs[eggId]
	if egg == nil then
		return
	end
	local lateral = currentLateral(egg, Workspace:GetServerTimeNow())
	egg.riderUserId = userId
	egg.lateral = lateral
	egg.targetLateral = lateral
	egg.offset = 0
	refreshLabel(egg)
end

-- Gives an egg a quick wobble, as when it bumps into something.
function EggController.Wobble(eggId: number)
	local egg = eggs[eggId]
	if egg then
		egg.wobbleAt = Workspace:GetServerTimeNow()
	end
end

-- The closest egg a jumping player at `position` could land on, if any. `ignoreEggId` skips one egg (the one the
-- player just jumped off). `extraHeight` lets a player riding a tall pet, held high above the ground, reach down.
function EggController.FindMountable(
	position: Vector3,
	now: number,
	ignoreEggId: number?,
	extraHeight: number?
): number?
	local bestId: number? = nil
	local bestDistance = math.huge
	for eggId, egg in eggs do
		if egg.riderUserId ~= nil or egg.cracking or eggId == ignoreEggId then
			continue
		end
		if now - egg.spawnTime < Tuning.EGG_DROP_TIME then
			-- Still dropping in from its chute.
			continue
		end
		local x, y, z = eggPosition(egg, now)
		local dx, dz = position.X - x, position.Z - z
		-- The egg's footprint is an oval: long side to side, short front to back.
		local nx = dx / (egg.spec.halfLength + Tuning.MOUNT_REACH)
		local nz = dz / (egg.spec.radius + Tuning.MOUNT_REACH)
		if nx * nx + nz * nz > 1 then
			continue
		end
		-- The player must be at least level with the middle of the egg, so running into one does nothing.
		if position.Y < y - 1 or position.Y > y + egg.spec.radius + 9 + (extraHeight or 0) then
			continue
		end
		local distance = dx * dx + dz * dz
		if distance < bestDistance then
			bestId, bestDistance = eggId, distance
		end
	end
	return bestId
end

-- Tells the egg labels how much stamina the local player has, for the green/red "Needs" text.
function EggController.SetLocalMaxStamina(maxStamina: number)
	if maxStamina == localMaxStamina then
		return
	end
	localMaxStamina = maxStamina
	for _, egg in eggs do
		refreshLabel(egg)
	end
end

-- The egg list sent by the server when this client asked for its snapshot.
function EggController.LoadSnapshot(list)
	if typeof(list) ~= "table" then
		return
	end
	for _, data in list do
		addEgg(data)
	end
end

function EggController.Init()
	eggFolder = Instance.new("Folder")
	eggFolder.Name = "Eggs"
	eggFolder.Parent = Workspace

	Net.EggSpawned.OnClientEvent:Connect(addEgg)
	Net.EggRemoved.OnClientEvent:Connect(removeEgg)

	Net.EggMounted.OnClientEvent:Connect(function(eggId: number, userId: number)
		local egg = eggs[eggId]
		if egg and egg.riderUserId ~= userId then
			EggController.SetRider(eggId, userId)
		end
	end)

	Net.EggLeft.OnClientEvent:Connect(function(eggId: number, time: number, bouncesLeft: number, lateral: number)
		local egg = eggs[eggId]
		if egg then
			local now = Workspace:GetServerTimeNow()
			-- Drawn from where it is now, settling onto the path the server set it on from where it was left.
			local drawn = currentLateral(egg, now)
			egg.riderUserId = nil
			setPath(egg, lateral, eggZ(egg, time), now, drawn)
			egg.bounceTime = time
			egg.bouncesLeft = bouncesLeft
			egg.cracking = bouncesLeft <= 0
			egg.targetLateral = lateral
			refreshLabel(egg)
		end
	end)

	Net.EggLateral.OnClientEvent:Connect(function(eggId: number, lateral: number)
		local egg = eggs[eggId]
		if egg and egg.riderUserId ~= localPlayer.UserId then
			egg.targetLateral = lateral
		end
	end)

	-- Just before the camera updates, so the camera follows a rider smoothly.
	RunService:BindToRenderStep("RollAnEgg_Eggs", Enum.RenderPriority.Camera.Value - 10, render)
end

return EggController
