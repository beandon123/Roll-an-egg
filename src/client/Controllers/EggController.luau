-- Draws every egg on the runway and keeps riders sitting on them.
--
-- Eggs are not sent from the server as parts. The server only says "an egg appeared / was mounted / was left /
-- is gone", and each device works out where every egg is from the shared clock (Shared/EggMotion). That keeps
-- eggs perfectly smooth and costs almost no network traffic.
--
-- Riders are pinned to this device's copy of the egg, so nobody appears to slide off because of lag.
--
-- Each egg's look comes from Shared/EggModels: a blocky model made of parts, different for every zone and rarity.
-- The parts are welded to one invisible, anchored root part, so moving an egg each frame is a single CFrame write.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local EggModels = Load.shared("EggModels")
local ModelEffects = Load.shared("ModelEffects")
local EggMotion = Load.shared("EggMotion")
local EggSpec = Load.shared("EggSpec")
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")
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

export type ClientEgg = {
	id: number,
	zone: number,
	rarity: string,
	-- Which egg it is: a design name in Shared/EggModels, such as "MossStag".
	kind: string,
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
	-- The invisible part every other part is welded to. Moving it moves the whole egg.
	root: Part,
	-- Which way round the egg lies.
	facing: CFrame,
	needLabel: TextLabel,
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

-- Builds the model for one kind of egg from its boxes, lying on its side with the pointed top towards +X.
local function buildTemplate(spec, kind: string): Model
	local design = EggModels.get(kind)
	assert(design, `no egg model called {kind}`)
	-- Studs per voxel: the egg's widest layer is EggModels.RADIUS voxels from the middle.
	local voxel = spec.radius / EggModels.RADIUS

	local model = Instance.new("Model")
	model.Name = "Egg"

	-- Invisible, anchored, and the size of the egg: what the label sits on and the particles come from.
	local root = newEggPart("Root", model)
	root.Size = Vector3.new(spec.halfLength * 2, spec.radius * 2, spec.radius * 2)
	root.Transparency = 1
	root.CFrame = CFrame.identity
	model.PrimaryPart = root

	for index, box in design.boxes do
		local part = Instance.new("Part")
		part.Name = "Block" .. index
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Material = (Enum.Material :: any)[box.material]
		part.Color = rgb(box.color)
		part.Transparency = box.transparency
		-- The designs stand the egg up (y along the egg); on the runway it lies on its side, so the egg's
		-- y becomes X, and its x becomes -Y.
		part.Size = Vector3.new(box.sy, box.sx, box.sz) * voxel
		part.CFrame = CFrame.new(box.y * voxel, -box.x * voxel, box.z * voxel)
		part.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	ModelEffects.add(root, design.light, design.particles, voxel)

	return model
end

-- Every egg of a kind has the same zone and rarity (see Config/Zones), so the spec, and so the size, is the same.
local function getTemplate(spec, kind: string): Model
	local template = templates[kind]
	if template == nil then
		template = buildTemplate(spec, kind)
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
	-- The egg must be one of that zone's eggs of that rarity; fall back to the first one if not.
	local kind = data.kind
	if typeof(kind) ~= "string" or not table.find(EggSpec.eggsOf(data.zone, data.rarity), kind) then
		kind = EggSpec.pickEgg(data.zone, data.rarity, 0)
	end
	if kind == nil then
		return
	end

	local model, root, needLabel = buildModel(spec, kind, data.rarity, data.id)
	local egg: ClientEgg = {
		id = data.id,
		zone = data.zone,
		rarity = data.rarity,
		kind = kind,
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
		root = root,
		facing = if data.id % 2 == 0 then FLIPPED else CFrame.identity,
		needLabel = needLabel,
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
		egg.root.CFrame = CFrame.new(x, y, z) * CFrame.Angles(angle, 0, 0) * egg.facing

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
