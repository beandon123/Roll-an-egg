-- Draws every egg on the runway, the dust trail behind it, and keeps riders sitting on them.
--
-- Eggs are not sent from the server as parts. The server only says "an egg appeared / was mounted / was left /
-- is gone", and each device works out where every egg is from the shared clock (Shared/EggMotion). That keeps
-- eggs perfectly smooth and costs almost no network traffic.
--
-- An egg appears on the ground at the start of its zone and rolls straight down the runway. The only time it
-- leaves the ground is the single hop it makes when a rider gets off.
--
-- Riders are pinned to this device's copy of the egg, so nobody appears to slide off because of lag.
--
-- Also shows the on-screen message when a Secret or rarer egg spawns.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local EggMotion = Load.shared("EggMotion")
local EggSpec = Load.shared("EggSpec")
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")
local Rarities = Load.shared("Config", "Rarities")
local Runway = Load.shared("Runway")
local Tuning = Load.shared("Config", "Tuning")
local Zones = Load.shared("Config", "Zones")

local UiState = require(script.Parent.Parent.Ui.UiState)

local localPlayer = Players.LocalPlayer

-- How far above the top of the egg a seated rider's root part sits.
local SEAT_HEIGHT = 2
-- Riders face down the runway (+Z).
local FACE_FORWARD = CFrame.Angles(0, math.pi, 0)
-- How quickly another rider's egg catches up with their reported steering.
local LATERAL_SMOOTHING = 12

-- Seconds a new egg takes to fade in where it appears.
local APPEAR_TIME = 0.25

-- Dust kicked up behind a rolling egg. Puffs stay where they were made, so a moving egg leaves a short trail
-- behind it. The texture is Roblox's built-in smoke, so no uploaded asset is needed.
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
-- Puffs per second while an egg rolls along the ground.
local DUST_RATE = 14
-- Seconds a puff lasts. Eggs roll at 12-21 studs a second, so the trail is roughly 8-15 studs long.
local DUST_LIFETIME = NumberRange.new(0.45, 0.75)
-- No dust for eggs this far from the camera.
local DUST_MAX_DISTANCE = 250
-- Bursts when an egg appears and when it lands from a hop.
local APPEAR_PUFFS = 12
local LANDING_PUFFS = 8
-- Dust is the color of the ground it comes off, mixed toward a pale tan so it reads as dust.
local DUST_TINT = Color3.fromRGB(205, 192, 168)
local DUST_TINT_AMOUNT = 0.45

local CAN_AFFORD_COLOR = Color3.fromRGB(120, 255, 130)
local CANNOT_AFFORD_COLOR = Color3.fromRGB(255, 95, 95)
local TAKEN_COLOR = Color3.fromRGB(230, 230, 230)

-- Where the three spots sit on the shell: { fraction of half-length along the egg, angle around it }.
-- The spots make the rolling visible and show which zone the egg came from.
local SPOTS = {
	{ 0.4, 0 },
	{ -0.4, math.rad(120) },
	{ 0, math.rad(240) },
}

export type ClientEgg = {
	id: number,
	zone: number,
	rarity: string,
	spec: any,
	spawnTime: number,
	startZ: number,
	-- Where the egg is drawn side to side, and where it is heading (for other riders' eggs).
	lateral: number,
	targetLateral: number,
	riderUserId: number?,
	bouncesLeft: number,
	bounceTime: number?,
	cracking: boolean,
	model: Model,
	shell: Part,
	needLabel: TextLabel,
	-- An invisible strip on the ground behind the egg that the dust comes from. It is not part of the egg's model,
	-- so it does not spin as the egg rolls.
	dust: Part,
	dustEmitter: ParticleEmitter,
	dustOn: boolean,
	-- The zone whose ground color the dust has.
	dustZone: number?,
	airborne: boolean,
}

local EggController = {}

local eggs: { [number]: ClientEgg } = {}
local eggFolder: Folder
local dustFolder: Folder
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

-- Placeholder egg: an egg-shaped shell in the rarity's color, lying on its side, with three spots in the
-- zone's color. Final art will replace this.
local function buildModel(spec, zoneId: number, rarity: string, id: number): (Model, Part, TextLabel)
	local rarityColor = rgb(Rarities.Info[rarity].color)
	local zoneColor = rgb(Zones.List[zoneId].accent)

	local model = Instance.new("Model")
	model.Name = "Egg" .. id

	local shell = newEggPart("Shell", model)
	shell.Size = Vector3.new(spec.halfLength * 2, spec.radius * 2, spec.radius * 2)
	-- The spots below are placed around the origin, so the shell must start there too.
	shell.CFrame = CFrame.new()
	shell.Color = rarityColor
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = shell
	model.PrimaryPart = shell

	for index, spot in SPOTS do
		local along, angle = spot[1], spot[2]
		-- A point on the surface of the egg-shaped shell.
		local ring = math.sqrt(1 - along * along)
		local part = newEggPart("Spot" .. index, model)
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * spec.radius * 0.55
		part.Color = zoneColor
		part.Position = Vector3.new(
			along * spec.halfLength,
			math.cos(angle) * ring * spec.radius * 0.95,
			math.sin(angle) * ring * spec.radius * 0.95
		)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Adornee = shell
	billboard.Size = UDim2.fromScale(11, 3.6)
	billboard.StudsOffset = Vector3.new(0, spec.radius + 3.2, 0)
	billboard.MaxDistance = 260
	billboard.LightInfluence = 0
	billboard.Parent = shell

	newLabel(billboard, rarity, rarityColor, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.55))
	local needLabel = newLabel(billboard, "", CAN_AFFORD_COLOR, UDim2.fromScale(0, 0.55), UDim2.fromScale(1, 0.45))

	return model, shell, needLabel
end

local function dustColor(zoneId: number): Color3
	return rgb(Zones.List[zoneId].ground):Lerp(DUST_TINT, DUST_TINT_AMOUNT)
end

local function buildDust(spec, id: number): (Part, ParticleEmitter)
	local part = newEggPart("Dust" .. id, dustFolder)
	part.Transparency = 1
	-- As wide as most of the egg, since it rolls on its side.
	part.Size = Vector3.new(spec.halfLength * 1.5, 0.2, spec.radius * 0.5)

	-- Bigger eggs kick up bigger puffs.
	local scale = spec.radius / Tuning.EGG_BASE_RADIUS
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Dust"
	emitter.Texture = DUST_TEXTURE
	emitter.Rate = DUST_RATE
	emitter.Lifetime = DUST_LIFETIME
	emitter.Speed = NumberRange.new(1.5, 3.5)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.Drag = 3
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.Size = NumberSequence.new(0.7 * scale, 2 * scale)
	emitter.Transparency = NumberSequence.new(0.35, 1)
	emitter.LightInfluence = 0.6
	emitter.Enabled = false
	emitter.Parent = part
	return part, emitter
end

-- Lets the puffs already in the air fade, then removes the egg's dust.
local function stopDust(egg: ClientEgg)
	egg.dustEmitter.Enabled = false
	egg.dustOn = false
	local dust = egg.dust
	task.delay(DUST_LIFETIME.Max, function()
		dust:Destroy()
	end)
end

-- Where an egg is right now: side-to-side position, height of its centre, distance down the runway, and how high
-- it is off the ground (only while it hops).
local function eggPosition(egg: ClientEgg, now: number): (number, number, number, number)
	local z = EggMotion.zAt(egg.spawnTime, egg.startZ, egg.spec.rollSpeed, now)
	local hop = EggMotion.hopOffset(egg.bounceTime, now, Tuning.HOP_DURATION, Tuning.HOP_HEIGHT)
	return egg.lateral, Runway.surfaceY(z) + egg.spec.radius + hop, z, hop
end

local function getCameraPosition(): Vector3?
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

-- Moves the dust strip to the ground just behind where the egg touches it, and turns the dust on while the egg
-- rolls along the ground near the camera.
local function updateDust(egg: ClientEgg, x: number, z: number, hop: number, cameraPosition: Vector3?)
	local ground = Runway.surfaceY(z)
	local position = Vector3.new(x, ground + 0.2, z - egg.spec.radius * 0.5)
	egg.dust.CFrame = CFrame.new(position)

	-- Eggs roll into later zones; their dust matches the ground they are on.
	local zoneId = Runway.zoneAt(z)
	if zoneId ~= nil and zoneId ~= egg.dustZone then
		egg.dustZone = zoneId
		egg.dustEmitter.Color = ColorSequence.new(dustColor(zoneId))
	end

	local near = cameraPosition == nil or (cameraPosition - position).Magnitude <= DUST_MAX_DISTANCE
	local airborne = hop > 0
	if egg.airborne and not airborne and near then
		-- Landing from a hop.
		egg.dustEmitter:Emit(LANDING_PUFFS)
	end
	egg.airborne = airborne

	local on = near and not airborne
	if on ~= egg.dustOn then
		egg.dustOn = on
		egg.dustEmitter.Enabled = on
	end
end

-- "3:42:07 PM", in the player's own time zone.
local function localClockTime(time: number): string
	local date = os.date("*t", math.floor(time))
	local hour = date.hour % 12
	if hour == 0 then
		hour = 12
	end
	return string.format("%d:%02d:%02d %s", hour, date.min, date.sec, if date.hour < 12 then "AM" else "PM")
end

-- Secret and rarer eggs get an on-screen message saying where and when they spawned. Everything else spawns
-- quietly.
local function announceIfRare(egg: ClientEgg)
	local info = Rarities.Info[egg.rarity]
	if not info.announce then
		return
	end
	UiState.showAnnouncement(
		`{string.upper(egg.rarity)} EGG SPAWNED!`,
		`Start of the {Zones.List[egg.zone].name} zone at {localClockTime(egg.spawnTime)}`,
		rgb(info.color)
	)
end

local function addEgg(data): ClientEgg?
	if typeof(data) ~= "table" or eggs[data.id] ~= nil then
		return nil
	end
	local spec = EggSpec.get(data.zone, data.rarity)
	if spec == nil then
		return nil
	end

	local model, shell, needLabel = buildModel(spec, data.zone, data.rarity, data.id)
	local dust, dustEmitter = buildDust(spec, data.id)
	local egg: ClientEgg = {
		id = data.id,
		zone = data.zone,
		rarity = data.rarity,
		spec = spec,
		spawnTime = data.spawnTime,
		startZ = spec.startZ,
		lateral = data.lateral,
		targetLateral = data.lateral,
		riderUserId = data.rider,
		bouncesLeft = data.bounces,
		bounceTime = data.bounceTime,
		cracking = data.cracking == true,
		model = model,
		shell = shell,
		needLabel = needLabel,
		dust = dust,
		dustEmitter = dustEmitter,
		dustOn = false,
		dustZone = nil,
		airborne = false,
	}
	eggs[egg.id] = egg
	refreshLabel(egg)

	local now = Workspace:GetServerTimeNow()
	local x, y, z, hop = eggPosition(egg, now)
	model:PivotTo(CFrame.new(x, y, z))
	model.Parent = eggFolder
	updateDust(egg, x, z, hop, getCameraPosition())

	-- A brand-new egg fades in with a puff of dust where it appears. Eggs that were already rolling when this
	-- player joined just show up.
	if now - egg.spawnTime < 1 then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Transparency = 1
				TweenService:Create(descendant, TweenInfo.new(APPEAR_TIME), { Transparency = 0 }):Play()
			end
		end
		if egg.dustOn then
			-- Only when the dust is on, which means near enough the camera to be seen.
			dustEmitter:Emit(APPEAR_PUFFS)
		end
	end
	return egg
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

	stopDust(egg)

	if reason == "Cracked" then
		local x, _, z = eggPosition(egg, Workspace:GetServerTimeNow())
		showSplat(egg, x, z)
		egg.model:Destroy()
		return
	end

	-- Everything else fades out quickly.
	egg.needLabel.Parent.Enabled = false
	for _, descendant in egg.model:GetDescendants() do
		if descendant:IsA("BasePart") then
			TweenService:Create(descendant, TweenInfo.new(0.25), { Transparency = 1 }):Play()
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
	local cameraPosition = getCameraPosition()

	for eggId, egg in eggs do
		-- The local rider steers their own egg directly (see RideController); everyone else's eases toward
		-- the last position the server reported.
		if egg.riderUserId ~= localUserId then
			egg.lateral += (egg.targetLateral - egg.lateral) * smoothing
		end

		local x, y, z, hop = eggPosition(egg, now)
		if z > Runway.LENGTH + 40 then
			-- Safety net: the server removes eggs at the end of the runway, but never draw one past it.
			removeEgg(eggId, nil)
			continue
		end

		local angle = EggMotion.rollAngle(z - egg.startZ, egg.spec.radius)
		egg.model:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(angle, 0, 0))
		updateDust(egg, x, z, hop, cameraPosition)

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

-- The closest egg a jumping player at `position` could land on, if any. `ignoreEggId` skips one egg (the one the
-- player just jumped off).
function EggController.FindMountable(position: Vector3, now: number, ignoreEggId: number?): number?
	local bestId: number? = nil
	local bestDistance = math.huge
	for eggId, egg in eggs do
		if egg.riderUserId ~= nil or egg.cracking or eggId == ignoreEggId then
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
		if position.Y < y - 1 or position.Y > y + egg.spec.radius + 9 then
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

	dustFolder = Instance.new("Folder")
	dustFolder.Name = "EggDust"
	dustFolder.Parent = Workspace

	Net.EggSpawned.OnClientEvent:Connect(function(data)
		local egg = addEgg(data)
		if egg then
			announceIfRare(egg)
		end
	end)
	Net.EggRemoved.OnClientEvent:Connect(removeEgg)

	Net.EggMounted.OnClientEvent:Connect(function(eggId: number, userId: number)
		local egg = eggs[eggId]
		if egg then
			egg.riderUserId = userId
			refreshLabel(egg)
		end
	end)

	Net.EggLeft.OnClientEvent:Connect(function(eggId: number, time: number, bouncesLeft: number, lateral: number)
		local egg = eggs[eggId]
		if egg then
			egg.riderUserId = nil
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
