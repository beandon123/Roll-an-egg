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
-- An egg appears on the ground at the start of its zone (fading in with a puff of dust) and rolls on down the
-- runway. The only time it leaves the ground is the one small bounce it makes before cracking, when its rider runs
-- out of stamina.
--
-- The runway winds and rolls over hills. Where an egg is, is worked out in runway coordinates (how far down the
-- runway, how far across it: Shared/Runway) and only turned into a place in the world when it is drawn
-- (Shared/RunwayFrame), so eggs follow every bend and slope. While the local player rides an egg, their camera
-- turns with the runway too, so "ahead" stays ahead round every bend.
--
-- The last zone never ends (see Shared/Runway). Every egg in it is drawn at its copy nearest the local player, so
-- when the local player is carried back one loop, everything around them is carried back with them and nothing
-- seems to move. Dust is the one thing that cannot be moved once made, so near the end of a loop each egg also lays
-- its trail one loop back ("echo" dust), ready for when the player arrives there.
--
-- Also shows the on-screen message when a Secret or rarer egg spawns.
--
-- Each egg's look comes from Shared/EggModels (a blocky model, different for every zone and rarity), built into parts
-- by Shared/EggRig. Every part is anchored, and this controller writes where every one of them goes, each at its own
-- place on the egg (see setPose). Nothing is welded: an egg is never moved by moving one part and trusting the rest to
-- follow, because parts moved before a weld takes hold are left behind and then swing round the egg as it rolls.
--
-- Eggs far from the camera are redrawn less often (see redrawInterval), since nobody can see the difference.

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
local RunwayFrame = Load.shared("RunwayFrame")
local Tuning = Load.shared("Config", "Tuning")
local Zones = Load.shared("Config", "Zones")

local UiState = require(script.Parent.Parent.Ui.UiState)

local localPlayer = Players.LocalPlayer

-- How far above the top of the egg a seated rider's root part sits.
local SEAT_HEIGHT = 2
-- Riders face down the runway (a character looks along its own -Z; the runway's frames point +Z down it).
local FACE_FORWARD = CFrame.Angles(0, math.pi, 0)
-- The camera only follows a turn of the runway this small in one frame; anything bigger is a jump, not a bend.
local MAX_CAMERA_TURN = 0.2
-- How quickly another rider's egg catches up with their reported steering.
local LATERAL_SMOOTHING = 12

local CAN_AFFORD_COLOR = Color3.fromRGB(120, 255, 130)
local CANNOT_AFFORD_COLOR = Color3.fromRGB(255, 95, 95)
local TAKEN_COLOR = Color3.fromRGB(230, 230, 230)
local YOURS_COLOR = Color3.fromRGB(255, 225, 90)

-- Seconds a new egg takes to fade in where it appears, and the puff of dust it appears with.
local APPEAR_TIME = 0.25
local APPEAR_PUFFS = 12
-- An egg drawn this many studs from where it was drawn last frame has jumped to another copy of itself (it just
-- rolled into the endless last zone). Unless the local player jumped too, it fades in as if new.
local POP_DISTANCE = 50
-- Within this many studs of the end of a loop, eggs also lay their dust one loop back (see the header).
local ECHO_RANGE = 60
-- No dust for eggs this far from the camera.
local DUST_MAX_DISTANCE = 250
-- Seconds an egg that goes off the side takes to fall out of sight.
local FALL_TIME = 0.7

-- Eggs far from the camera are redrawn every few frames instead of every frame: within NEAR_DISTANCE studs every
-- frame, out to FAR_DISTANCE every MID_REDRAW_FRAMES frames, out to OUT_OF_SIGHT every FAR_REDRAW_FRAMES, and
-- beyond that (zones away, far past where the map has even loaded) only every DISTANT_REDRAW_FRAMES. An egg someone
-- is riding is always redrawn, because its rider is held on it.
local NEAR_DISTANCE = 500
local FAR_DISTANCE = 1500
local OUT_OF_SIGHT = 3000
local MID_REDRAW_FRAMES = 2
local FAR_REDRAW_FRAMES = 6
local DISTANT_REDRAW_FRAMES = 30

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
	-- Who claimed it, once someone has. Nobody else can get on it, and it disappears when they get off.
	ownerUserId: number?,
	-- Set while it bounces before cracking (its rider ran out of stamina).
	bounceTime: number?,
	cracking: boolean,
	model: Model,
	-- The invisible part at the middle of the egg, which its label and effects sit on.
	root: Part,
	-- Every part of the egg (the root first, then its blocks), where each one sits measured from the root, and how
	-- see-through its design makes it. `cframes` is a scratch list, reused every frame, of where each part goes.
	parts: { BasePart },
	offsets: { CFrame },
	shown: { number },
	cframes: { CFrame },
	-- Whether the model is in the Workspace yet.
	placed: boolean,
	-- How high its middle rides above the ground (EggRig.rollHeight).
	rollHeight: number,
	-- Which way round the egg lies.
	facing: CFrame,
	needLabel: TextLabel,
	-- The dust cloud behind it: an invisible part that follows the egg along the ground (it does not roll).
	dust: BasePart,
	dustEmitter: ParticleEmitter,
	dustOn: boolean,
	-- The same, one loop back (see the header).
	echo: BasePart,
	echoEmitter: ParticleEmitter,
	echoOn: boolean,
	dustZone: number?,
	-- Which way the runway pointed when the dust was last aimed back up it.
	dustHeading: number?,
	wobbleAt: number?,
	-- Where it was last drawn (in runway coordinates: across, and down the runway), and on which frame.
	drawnX: number?,
	drawnZ: number?,
	drawnFrame: number,
}

local EggController = {}

local eggs: { [number]: ClientEgg } = {}
-- One finished model per kind of egg, cloned for every egg of that kind.
local templates: { [string]: Model } = {}
local eggFolder: Folder
local localMaxStamina = Tuning.BASE_MAX_STAMINA
-- The local player's position along the runway last frame (see getReferenceZ).
local lastReferenceZ: number? = nil
-- Which way the runway pointed under the egg the local player rides, last frame (see turnCamera).
local lastRideHeading: number? = nil
-- Frames drawn so far, for redrawing far-off eggs every few frames, and the frame on which the local player was last
-- carried back one loop (or respawned).
local frame = 0
local lastJumpFrame = 0

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function refreshLabel(egg: ClientEgg)
	if egg.ownerUserId ~= nil then
		local mine = egg.ownerUserId == localPlayer.UserId
		egg.needLabel.Text = if mine then "Yours!" else "Claimed"
		egg.needLabel.TextColor3 = if mine then YOURS_COLOR else TAKEN_COLOR
	elseif egg.riderUserId ~= nil then
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

-- Every part of a freshly copied egg model (the root first, then its blocks), where each one sits measured from the
-- root, and how see-through its design makes it. Read before anything moves or fades the egg.
local function layoutOf(model: Model, root: Part): ({ BasePart }, { CFrame }, { number })
	local parts: { BasePart } = { root }
	local offsets = { CFrame.identity }
	local shown = { root.Transparency }
	local rootCFrame = root.CFrame
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= root then
			table.insert(parts, child)
			table.insert(offsets, rootCFrame:ToObjectSpace(child.CFrame))
			table.insert(shown, child.Transparency)
		end
	end
	return parts, offsets, shown
end

-- Puts the whole egg at `pose` (where its root goes): every part is written, each at its own place on the egg. Once
-- the egg is in the Workspace all its parts move in one call.
local function setPose(egg: ClientEgg, pose: CFrame)
	local parts, offsets, cframes = egg.parts, egg.offsets, egg.cframes
	for index = 1, #parts do
		cframes[index] = pose * offsets[index]
	end
	if egg.placed then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	else
		for index, part in parts do
			part.CFrame = cframes[index]
		end
	end
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
	-- Up, and back up the runway (updateDust aims it as the runway turns).
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

-- Where an egg is down the runway (carried back in the endless last zone: Runway.wrapZ), as on the server.
local function eggZ(egg: ClientEgg, now: number): number
	return Runway.wrapZ(EggMotion.zAt(egg.spawnTime, egg.startZ, egg.spec.rollSpeed, now))
end

-- How far an egg has rolled in all, for how far round it has turned.
local function rolled(egg: ClientEgg, now: number): number
	return EggMotion.zAt(egg.spawnTime, egg.startZ, egg.spec.rollSpeed, now) - egg.startZ
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

-- Where the local player is along the runway: on their egg while riding, else their character. Eggs in the endless
-- last zone are drawn at their copy nearest this.
local function getReferenceZ(now: number): number
	local ride = UiState.ride
	local mine = if ride then eggs[ride.eggId] else nil
	if mine then
		return eggZ(mine, now)
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local place = if root and root:IsA("BasePart") then root.Position else nil
	if place == nil then
		local camera = Workspace.CurrentCamera
		place = if camera then camera.CFrame.Position else nil
	end
	if place then
		local _, z = RunwayFrame.locate(place)
		return z
	end
	return 0
end

-- Where to draw an egg, in runway coordinates: how far across the runway, how high its centre is above the ground
-- there (higher only during its bounce before cracking), and how far down the runway. The egg the local player
-- rides is drawn where it really is, so it carries them back one loop when it gets there; every other egg is drawn
-- at its copy nearest them.
local function eggPosition(egg: ClientEgg, now: number, referenceZ: number): (number, number, number)
	local z = eggZ(egg, now)
	local x = currentLateral(egg, now)
	if egg.riderUserId ~= localPlayer.UserId then
		z = Runway.nearestImage(z, referenceZ)
	end
	local bounce = EggMotion.bounceOffset(egg.bounceTime, now, Tuning.CRACK_BOUNCE_TIME, Tuning.CRACK_BOUNCE_HEIGHT)
	return x, egg.rollHeight + bounce, z
end

local function getCameraPosition(): Vector3?
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function setEmitting(emitter: ParticleEmitter, on: boolean, current: boolean): boolean
	if on ~= current then
		emitter.Enabled = on
	end
	return on
end

-- Moves the dust strip to the ground just behind the egg, colours it for the zone underfoot, and turns it on while
-- the egg rolls along the ground near the camera. `echoing`: the local player is about to be carried back one loop.
local function updateDust(egg: ClientEgg, x: number, z: number, cameraPosition: Vector3?, echoing: boolean)
	local dustZ = z - egg.spec.radius * 0.6
	local strip = RunwayFrame.at(x, dustZ, 0.2)
	local position = strip.Position
	egg.dust.CFrame = strip

	-- The dust drifts back up the runway, whichever way that is here.
	local heading = Runway.heading(dustZ)
	if egg.dustHeading == nil or math.abs(heading - egg.dustHeading) > 0.05 then
		egg.dustHeading = heading
		local drift = Vector3.new(0, 1.5, 0) - RunwayFrame.forward(dustZ) * 2
		egg.dustEmitter.Acceleration = drift
		egg.echoEmitter.Acceleration = drift
	end

	local zone = Runway.zoneAt(z)
	if zone and zone ~= egg.dustZone then
		egg.dustZone = zone
		local color = DUST_COLORS[zone]
		local sequence = ColorSequence.new(Color3.fromRGB(color[1], color[2], color[3]))
		egg.dustEmitter.Color = sequence
		egg.echoEmitter.Color = sequence
	end

	local near = cameraPosition == nil or (cameraPosition - position).Magnitude <= DUST_MAX_DISTANCE
	local on = near and not egg.cracking
	egg.dustOn = setEmitting(egg.dustEmitter, on, egg.dustOn)

	local echoOn = on and echoing
	if echoOn then
		egg.echo.CFrame = RunwayFrame.at(x, dustZ - Runway.LOOP_LENGTH, 0.2)
	end
	egg.echoOn = setEmitting(egg.echoEmitter, echoOn, egg.echoOn)
end

-- Fades an egg in with a puff of dust, as when it first appears. Each part fades to how see-through its design makes
-- it (not to whatever it is right now, which is partly faded if the egg was already fading in).
local function appear(egg: ClientEgg)
	for index, part in egg.parts do
		local shown = egg.shown[index]
		if shown < 1 then
			part.Transparency = 1
			TweenService:Create(part, TweenInfo.new(APPEAR_TIME), { Transparency = shown }):Play()
		end
	end
	if egg.dustOn then
		-- Only when the dust is on, which means near enough the camera to be seen.
		egg.dustEmitter:Emit(APPEAR_PUFFS)
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

-- The on-screen message for a Secret or rarer egg: what spawned, where, and when.
local function announce(egg: ClientEgg)
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

-- Holds a rider's character on top of an egg whose centre is `height` above the runway at (x, z), facing down the
-- runway.
local function pinRider(userId: number, x: number, height: number, z: number, radius: number)
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = RunwayFrame.at(x, z, height + radius + SEAT_HEIGHT) * FACE_FORWARD
	end
end

-- Keeps the local player's camera pointing down the runway while they ride: as the runway turns under their egg, the
-- camera turns by the same amount, on top of wherever they have swung it themselves. (Roblox's camera carries on
-- from whichever way the camera is facing, so turning it here is enough.)
local function turnCamera(z: number)
	local heading = Runway.heading(z)
	local turn = if lastRideHeading then heading - lastRideHeading else 0
	lastRideHeading = heading
	local camera = Workspace.CurrentCamera
	if camera == nil or turn == 0 or math.abs(turn) > MAX_CAMERA_TURN then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local current = camera.CFrame
	camera.CFrame = CFrame.new(current.Position) * CFrame.Angles(0, turn, 0) * current.Rotation
end

-- Puts an egg where eggPosition says it belongs this frame (x across the runway, its centre `height` above the
-- ground, z down the runway), turned to face down the runway and as far round as it has rolled, with its dust and
-- rider.
local function draw(
	egg: ClientEgg,
	now: number,
	x: number,
	height: number,
	z: number,
	cameraPosition: Vector3?,
	echoing: boolean
)
	local wobble = CFrame.identity
	if egg.wobbleAt then
		local t = now - egg.wobbleAt
		if t < WOBBLE_TIME then
			wobble = CFrame.Angles(0, 0, math.sin(t * 32) * 0.22 * (1 - t / WOBBLE_TIME))
		else
			egg.wobbleAt = nil
		end
	end
	local angle = EggMotion.rollAngle(rolled(egg, now), egg.spec.radius)
	setPose(egg, RunwayFrame.at(x, z, height) * wobble * CFrame.Angles(angle, 0, 0) * egg.facing)
	egg.drawnX, egg.drawnZ = x, z
	updateDust(egg, x, z, cameraPosition, echoing)
	if egg.riderUserId ~= nil then
		pinRider(egg.riderUserId, x, height, z, egg.spec.radius)
	end
end

local function addEgg(data): ClientEgg?
	if typeof(data) ~= "table" or eggs[data.id] ~= nil then
		return nil
	end
	local spec = EggSpec.get(data.zone, data.rarity)
	if spec == nil then
		return nil
	end
	-- The egg must be one of that zone's eggs of that rarity; fall back to the first one if not.
	local kind = data.kind
	if typeof(kind) ~= "string" or not table.find(EggSpec.eggsOf(data.zone, data.rarity), kind) then
		kind = EggSpec.pickEgg(data.zone, data.rarity, 0)
	end
	if kind == nil then
		return nil
	end

	local model, root, needLabel = buildModel(spec, kind, data.rarity, data.id)
	-- Before the dust strips join the model: they are placed on their own, not as parts of the egg.
	local parts, offsets, shown = layoutOf(model, root)
	local dust, dustEmitter = addDust(model, spec)
	local echo = dust:Clone()
	echo.Name = "Echo"
	echo.Parent = model
	local echoEmitter = echo:FindFirstChildOfClass("ParticleEmitter") :: ParticleEmitter
	-- Eggs appear at the start of their zone unless an admin dropped one somewhere else (the server worked out its
	-- fade line the same way: Logic/RunwaySim).
	local startZ = if typeof(data.startZ) == "number" then data.startZ else spec.startZ
	local fadeZ = EggSpec.fadeZ(data.zone, startZ)
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
		ownerUserId = data.owner,
		bounceTime = data.bounceTime,
		cracking = data.bounceTime ~= nil,
		model = model,
		root = root,
		parts = parts,
		offsets = offsets,
		shown = shown,
		cframes = table.create(#parts),
		placed = false,
		rollHeight = EggRig.rollHeight(spec.radius),
		facing = if data.id % 2 == 0 then FLIPPED else CFrame.identity,
		needLabel = needLabel,
		dust = dust,
		dustEmitter = dustEmitter,
		dustOn = false,
		echo = echo,
		echoEmitter = echoEmitter,
		echoOn = false,
		dustZone = nil,
		dustHeading = nil,
		wobbleAt = nil,
		drawnX = nil,
		drawnZ = nil,
		drawnFrame = frame,
	}
	eggs[egg.id] = egg
	refreshLabel(egg)

	-- Every part is put in its place before the egg is shown, so it never appears anywhere but where it belongs.
	local now = Workspace:GetServerTimeNow()
	local x, height, z = eggPosition(egg, now, getReferenceZ(now))
	draw(egg, now, x, height, z, getCameraPosition(), false)
	model.Parent = eggFolder
	egg.placed = true
	-- A brand-new egg fades in with a puff of dust where it appears. Eggs that were already rolling when this
	-- player joined just show up.
	if now - egg.spawnTime < 1 then
		appear(egg)
	end
	return egg
end

-- A cartoon splat left on the runway where an egg cracked, lying on the slope there.
local function showSplat(egg: ClientEgg, x: number, z: number)
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
		part.CFrame = RunwayFrame.onSlope(x, z, piece.height / 2) * flat
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

	local x = egg.drawnX or egg.lateral
	local z = egg.drawnZ or eggZ(egg, Workspace:GetServerTimeNow())
	if reason == "Cracked" then
		showSplat(egg, x, z)
		egg.model:Destroy()
		return
	end

	-- Everything else fades out quickly; an egg that went over the edge also drops out of sight.
	local falling = reason == "FellOff"
	local tweenInfo = if falling
		then TweenInfo.new(FALL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		else TweenInfo.new(0.25)
	-- Out over the edge it went off, and down.
	local drop = RunwayFrame.across(z) * (if x > 0 then 12 else -12) - Vector3.new(0, 40, 0)
	egg.needLabel.Parent.Enabled = false
	for _, descendant in egg.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= egg.root then
			local goal: { [string]: any } = { Transparency = 1 }
			if falling and descendant ~= egg.dust and descendant ~= egg.echo then
				goal.CFrame = descendant.CFrame + drop
			end
			TweenService:Create(descendant, tweenInfo, goal):Play()
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
	if falling then
		-- The root falls with them, taking the egg's light and particles along.
		TweenService:Create(egg.root, tweenInfo, { CFrame = egg.root.CFrame + drop }):Play()
	end
	task.delay(if falling then FALL_TIME + 0.1 else 0.3, function()
		egg.model:Destroy()
	end)
end

-- How many frames go by between redraws of an egg this many studs from the camera.
local function redrawInterval(distance: number): number
	if distance <= NEAR_DISTANCE then
		return 1
	elseif distance <= FAR_DISTANCE then
		return MID_REDRAW_FRAMES
	elseif distance <= OUT_OF_SIGHT then
		return FAR_REDRAW_FRAMES
	end
	return DISTANT_REDRAW_FRAMES
end

local function render(deltaTime: number)
	frame += 1
	local now = Workspace:GetServerTimeNow()
	local smoothing = math.min(1, deltaTime * LATERAL_SMOOTHING)
	local localUserId = localPlayer.UserId
	local settle = math.exp(-deltaTime * OFFSET_SETTLE)
	local cameraPosition = getCameraPosition()

	local referenceZ = getReferenceZ(now)
	-- The local player was just carried back one loop (or respawned): everything moved with them.
	if lastReferenceZ ~= nil and math.abs(referenceZ - lastReferenceZ) > POP_DISTANCE then
		lastJumpFrame = frame
	end
	lastReferenceZ = referenceZ
	local echoing = referenceZ >= Runway.LOOP_END - ECHO_RANGE and referenceZ < Runway.LOOP_END

	-- Round a bend, the camera of a player riding an egg turns with the runway.
	local ride = UiState.ride
	local mine = if ride then eggs[ride.eggId] else nil
	if mine then
		turnCamera(eggZ(mine, now))
	else
		lastRideHeading = nil
	end

	for eggId, egg in eggs do
		-- The local rider steers their own egg directly (see RideController); everyone else's eases toward
		-- the last position the server reported. A riderless egg settles onto its path.
		if egg.riderUserId == nil then
			egg.offset *= settle
			if eggZ(egg, now) > egg.fadeZ + 30 then
				-- Safety net: the server removes eggs at the end of their lap, but never draw one far past it.
				removeEgg(eggId, nil)
				continue
			end
		elseif egg.riderUserId ~= localUserId then
			egg.lateral += (egg.targetLateral - egg.lateral) * smoothing
		end

		local x, height, z = eggPosition(egg, now, referenceZ)
		if egg.riderUserId == nil and cameraPosition ~= nil then
			-- Far from the camera: redrawn only every few frames (eggs take turns, by id).
			local interval = redrawInterval((cameraPosition - RunwayFrame.point(x, z, height)).Magnitude)
			if interval > 1 and (frame + eggId) % interval ~= 0 then
				continue
			end
		end

		local drawnBefore, drawnFrame = egg.drawnZ, egg.drawnFrame
		draw(egg, now, x, height, z, cameraPosition, echoing)
		egg.drawnFrame = frame
		-- An egg that jumped to another copy of itself fades in there, unless it only moved because the local player
		-- did (since it was last drawn).
		if drawnBefore ~= nil and drawnFrame >= lastJumpFrame and math.abs(z - drawnBefore) > POP_DISTANCE then
			appear(egg)
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
	-- A little way in from a wall, as on the server (Runway.mountLateral).
	local now = Workspace:GetServerTimeNow()
	local lateral = Runway.mountLateral(currentLateral(egg, now), egg.spec.halfLength, eggZ(egg, now))
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

-- The closest egg a leaping player at `position` could land on, if any. `ignoreEggId` skips one egg (the one the
-- player just jumped off). Eggs that are taken, claimed, or cracking are skipped. `extraHeight` lets a player riding a tall pet, held high above the ground, reach down.
function EggController.FindMountable(
	position: Vector3,
	now: number,
	ignoreEggId: number?,
	extraHeight: number?
): number?
	local bestId: number? = nil
	local bestDistance = math.huge
	-- Where the player is on the runway: how far across it, and how far down it.
	local playerX, playerZ = RunwayFrame.locate(position)
	for eggId, egg in eggs do
		if egg.riderUserId ~= nil or egg.ownerUserId ~= nil or egg.cracking or eggId == ignoreEggId then
			continue
		end
		local x, height, z = eggPosition(egg, now, playerZ)
		-- How far the player is from the egg across the runway and along it, in studs (round a bend, runway
		-- distance is stretched: Runway.stretch).
		local dx, dz = playerX - x, (playerZ - z) * Runway.stretch(x, z)
		local y = Runway.surfaceY(z) + height
		-- The egg's footprint is an oval: long side to side, short front to back.
		local nx = dx / (egg.spec.halfLength + Tuning.MOUNT_REACH)
		local nz = dz / (egg.spec.radius + Tuning.MOUNT_REACH)
		if nx * nx + nz * nz > 1 then
			continue
		end
		-- The player must be at least level with the middle of the egg.
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

	Net.EggSpawned.OnClientEvent:Connect(function(data, shouldAnnounce: boolean?)
		local egg = addEgg(data)
		if egg and shouldAnnounce then
			announce(egg)
		end
	end)
	Net.EggRemoved.OnClientEvent:Connect(removeEgg)

	Net.EggMounted.OnClientEvent:Connect(function(eggId: number, userId: number)
		local egg = eggs[eggId]
		if egg and egg.riderUserId ~= userId then
			EggController.SetRider(eggId, userId)
		end
	end)

	Net.EggLeft.OnClientEvent:Connect(function(eggId: number, time: number, lateral: number, cracking: boolean?)
		local egg = eggs[eggId]
		if egg then
			local now = Workspace:GetServerTimeNow()
			-- Drawn from where it is now, settling onto the path the server set it on from where it was left.
			local drawn = currentLateral(egg, now)
			egg.riderUserId = nil
			setPath(egg, lateral, eggZ(egg, time), now, drawn)
			if cracking then
				egg.bounceTime = time
				egg.cracking = true
			end
			egg.targetLateral = lateral
			refreshLabel(egg)
		end
	end)

	Net.EggClaimed.OnClientEvent:Connect(function(eggId: number, userId: number)
		local egg = eggs[eggId]
		if egg then
			egg.ownerUserId = userId
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
