-- Draws every egg on the runway and keeps riders sitting on them.
--
-- Eggs are not sent from the server as parts. The server only says "an egg appeared / was mounted / was left /
-- is gone", and each device works out where every egg is from the shared clock (Shared/EggMotion). That keeps
-- eggs perfectly smooth and costs almost no network traffic.
--
-- Riders are pinned to this device's copy of the egg, so nobody appears to slide off because of lag.

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
}

local EggController = {}

local eggs: { [number]: ClientEgg } = {}
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

-- Placeholder egg: an egg-shaped shell in the rarity's color, lying on its side, with three spots in the
-- zone's color. Final art will replace this.
local function buildModel(spec, zoneId: number, rarity: string, id: number): (Model, Part, TextLabel)
	local rarityColor = rgb(Rarities.Info[rarity].color)
	local zoneColor = rgb(Zones.List[zoneId].accent)

	local model = Instance.new("Model")
	model.Name = "Egg" .. id

	local shell = newEggPart("Shell", model)
	shell.Size = Vector3.new(spec.halfLength * 2, spec.radius * 2, spec.radius * 2)
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

-- Where an egg is right now: side-to-side position, height of its centre, distance down the runway.
local function eggPosition(egg: ClientEgg, now: number): (number, number, number)
	local z = EggMotion.zAt(egg.spawnTime, egg.startZ, egg.spec.rollSpeed, now)
	local y = Runway.surfaceY(z)
		+ egg.spec.radius
		+ EggMotion.hopOffset(egg.bounceTime, now, Tuning.HOP_DURATION, Tuning.HOP_HEIGHT)
		+ EggMotion.dropOffset(now - egg.spawnTime, Tuning.EGG_DROP_TIME, Tuning.EGG_DROP_HEIGHT)
	return egg.lateral, y, z
end

local function addEgg(data)
	if typeof(data) ~= "table" or eggs[data.id] ~= nil then
		return
	end
	local spec = EggSpec.get(data.zone, data.rarity)
	if spec == nil then
		return
	end

	local model, shell, needLabel = buildModel(spec, data.zone, data.rarity, data.id)
	local egg: ClientEgg = {
		id = data.id,
		zone = data.zone,
		rarity = data.rarity,
		spec = spec,
		spawnTime = data.spawnTime,
		startZ = Runway.zoneStartZ(data.zone) + Tuning.EGG_SPAWN_OFFSET,
		lateral = data.lateral,
		targetLateral = data.lateral,
		riderUserId = data.rider,
		bouncesLeft = data.bounces,
		bounceTime = data.bounceTime,
		cracking = data.cracking == true,
		model = model,
		shell = shell,
		needLabel = needLabel,
	}
	eggs[egg.id] = egg
	refreshLabel(egg)

	local x, y, z = eggPosition(egg, Workspace:GetServerTimeNow())
	model:PivotTo(CFrame.new(x, y, z))
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

	for eggId, egg in eggs do
		-- The local rider steers their own egg directly (see RideController); everyone else's eases toward
		-- the last position the server reported.
		if egg.riderUserId ~= localUserId then
			egg.lateral += (egg.targetLateral - egg.lateral) * smoothing
		end

		local x, y, z = eggPosition(egg, now)
		if z > Runway.LENGTH + 40 then
			-- Safety net: the server removes eggs at the end of the runway, but never draw one past it.
			removeEgg(eggId, nil)
			continue
		end

		local angle = EggMotion.rollAngle(z - egg.startZ, egg.spec.radius)
		egg.model:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(angle, 0, 0))

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

	Net.EggSpawned.OnClientEvent:Connect(addEgg)
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
