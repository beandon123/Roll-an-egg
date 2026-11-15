-- The Model Showroom (see Shared/Showroom): a floor far from the hub with every pet and egg model standing on it.
--
-- When the server starts, the pet and egg folders imported into the place from tools/export-models (Studio's
-- Import Roblox Model, into Workspace or ServerStorage) are moved there, keeping how they are laid out: pets to the
-- left of the aisle, eggs to the right. Any edits made to them by hand come along. A folder that was not imported is
-- built from the game's own code instead, the first time someone goes to the showroom (it takes a few seconds, so
-- it is not done at start-up). Imported models are a snapshot from when they were exported; built ones always
-- match the code.
--
-- That move only lasts while the game runs. To move the imported folders in the place itself, so they are out of
-- the hub in edit mode too, run this once in Studio's command bar (not while playing), then save the place:
--     require(game.ServerScriptService.Server.Services.ShowroomService).MoveImportedModels()
-- Requiring this module changes nothing by itself, so that is safe outside a running game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local EggModels = require(Shared.EggModels)
local EggRig = require(Shared.EggRig)
local EggSpec = require(Shared.EggSpec)
local PetModels = require(Shared.PetModels)
local PetRig = require(Shared.PetRig)
local Showroom = require(Shared.Showroom)
local Zones = require(Shared.Config.Zones)

-- Gaps between models built from code: across a row, and between rows (one row per zone).
local GAP = 6
local ROW_GAP = 16
local FLOOR_THICKNESS = 4
-- Name labels float this far above each model and show from this far away.
local LABEL_HEIGHT = 2.5
local LABEL_DISTANCE = 90

local ShowroomService = {}

type Side = "Pets" | "Eggs"

local SIDES: { Side } = { "Pets", "Eggs" }
local IMPORTED_NAMES: { [Side]: string } = { Pets = Showroom.PET_FOLDER, Eggs = Showroom.EGG_FOLDER }

-- While the game runs: Workspace.Showroom, and what stands on each side of the aisle.
local root: Folder? = nil
local displays: { [Side]: Instance } = {}
local building = false
-- Called with (player) when someone uses the prompt on the floor; AdminService sends them to the hub.
local onLeave: ((Player) -> ())? = nil

----------------------------------------------------------------------------------------------------------------
-- Measuring and moving

-- The box round every visible part under `container` (its lowest and highest corners), or nil if there are none.
-- A part at an angle counts by the box round it.
local function boundsOf(container: Instance): (Vector3?, Vector3?)
	local low = { math.huge, math.huge, math.huge }
	local high = { -math.huge, -math.huge, -math.huge }
	local found = false
	for _, part in container:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			found = true
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
			local size = part.Size
			local centre = { x, y, z }
			local half = {
				(math.abs(r00) * size.X + math.abs(r01) * size.Y + math.abs(r02) * size.Z) / 2,
				(math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z) / 2,
				(math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z) / 2,
			}
			for axis = 1, 3 do
				low[axis] = math.min(low[axis], centre[axis] - half[axis])
				high[axis] = math.max(high[axis], centre[axis] + half[axis])
			end
		end
	end
	if not found then
		return nil, nil
	end
	return Vector3.new(low[1], low[2], low[3]), Vector3.new(high[1], high[2], high[3])
end

-- Every model under `container` that is not inside another model: the pets and eggs themselves.
local function modelsIn(container: Instance): { Model }
	local list = {}
	local function walk(instance: Instance)
		for _, child in instance:GetChildren() do
			if child:IsA("Model") then
				table.insert(list, child)
			else
				walk(child)
			end
		end
	end
	walk(container)
	return list
end

-- Moves everything under `container` by `offset`: each model whole (PivotTo, so its joints and welds come too),
-- and any part that is not in a model. Every target is worked out before anything moves, so parts welded to each
-- other end up in the right place whichever moves first.
local function moveBy(container: Instance, offset: Vector3)
	local loose: { [BasePart]: CFrame } = {}
	local function walk(instance: Instance)
		for _, child in instance:GetChildren() do
			if child:IsA("Model") then
				child:PivotTo(child:GetPivot() + offset)
			elseif child:IsA("BasePart") then
				loose[child] = child.CFrame + offset
			else
				walk(child)
			end
		end
	end
	walk(container)
	for part, target in loose do
		part.CFrame = target
	end
end

-- Moves a whole display so it stands on the showroom floor on its side of the aisle, with its front edge on the
-- showroom's front line. Returns false if it has nothing visible to place.
local function placeDisplay(container: Instance, side: Side): boolean
	local low, high = boundsOf(container)
	if low == nil or high == nil then
		return false
	end
	local x = if side == "Pets"
		then Showroom.X - Showroom.AISLE / 2 - high.X
		else Showroom.X + Showroom.AISLE / 2 - low.X
	moveBy(container, Vector3.new(x, Showroom.FLOOR_Y - low.Y, Showroom.Z - low.Z))
	return true
end

-- Finds a folder imported from tools/export-models, in Workspace or ServerStorage.
local function findImported(side: Side): Instance?
	local name = IMPORTED_NAMES[side]
	for _, container in { Workspace, ServerStorage } :: { Instance } do
		local found = container:FindFirstChild(name)
		if found then
			return found
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------------------
-- Building models from code

-- Lays a zone's models out in a row along +X at the front line `frontZ`, each standing on the floor (`rise` says
-- how far up each one goes from where it was built), right up against the aisle. Returns how deep the row is.
local function layRow(models: { Model }, side: Side, frontZ: number, rise: (Model, Vector3) -> number): number
	local boxes = {}
	local width, depth = 0, 0
	for _, model in models do
		local low, high = boundsOf(model)
		low = low or model:GetPivot().Position
		high = high or model:GetPivot().Position
		table.insert(boxes, { low = low, high = high })
		width += high.X - low.X
		depth = math.max(depth, high.Z - low.Z)
	end
	width += GAP * math.max(0, #models - 1)

	local x = if side == "Pets" then Showroom.X - Showroom.AISLE / 2 - width else Showroom.X + Showroom.AISLE / 2
	for index, model in models do
		local box = boxes[index]
		local offset =
			Vector3.new(x - box.low.X, rise(model, box.low), frontZ + depth / 2 - (box.low.Z + box.high.Z) / 2)
		model:PivotTo(model:GetPivot() + offset)
		x += box.high.X - box.low.X + GAP
	end
	return depth
end

-- Builds every zone's pets (or eggs), a row per zone in runway order, into a new folder. Yields after each model
-- so the server keeps running smoothly while it works.
local function buildDisplay(side: Side): Folder
	local display = Instance.new("Folder")
	display.Name = if side == "Pets" then "Pets (built from code)" else "Eggs (built from code)"
	local frontZ = Showroom.Z
	for _, zone in Zones.List do
		local row: { Model } = {}
		for _, entry in zone.eggs do
			if side == "Pets" then
				local pet = PetRig.build(entry.pet)
				if pet then
					pet:PivotTo(CFrame.identity)
					table.insert(row, pet)
				end
			else
				local spec = EggSpec.get(zone.id, entry.rarity)
				if spec then
					local egg = EggRig.build(entry.egg, spec)
					local about = EggModels.describe(entry.egg)
					egg.Name = if about then about.name else entry.egg
					-- Stood up on end, pointed top upwards.
					egg:PivotTo(CFrame.Angles(0, 0, math.pi / 2))
					table.insert(row, egg)
				end
			end
			task.wait()
		end
		if #row > 0 then
			local depth = layRow(row, side, frontZ, function(model, low)
				if side == "Pets" then
					-- Floating pets float above the floor as they do in the game.
					return Showroom.FLOOR_Y + (model:GetAttribute("GroundOffset") or -low.Y)
				end
				return Showroom.FLOOR_Y - low.Y
			end)
			local zoneFolder = Instance.new("Folder")
			zoneFolder.Name = zone.name
			for _, model in row do
				model.Parent = zoneFolder
			end
			zoneFolder.Parent = display
			frontZ += depth + ROW_GAP
		end
	end
	return display
end

----------------------------------------------------------------------------------------------------------------
-- The floor, signs and labels

local function newPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

local function newText(parent: Instance, text: string, size: UDim2, position: UDim2, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = font
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.4
	label.Parent = parent
	return label
end

-- A sign board facing the visitors (-Z), its bottom edge at `bottom`.
local function addSign(parent: Instance, name: string, text: string, centreX: number, bottom: number, z: number)
	local sign = newPart(name, parent)
	sign.Size = Vector3.new(math.max(30, #text * 4.2), 9, 1)
	sign.Position = Vector3.new(centreX, bottom + 4.5, z)
	sign.Color = Color3.fromRGB(46, 50, 66)
	sign.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = sign
	newText(gui, text, UDim2.fromScale(0.94, 0.8), UDim2.fromScale(0.03, 0.1), Enum.Font.FredokaOne)
end

-- The name people know a model by: "Moss Stag" for a pet called MossStag; eggs exported or built here are
-- already named "Moss Stag Egg".
local function displayName(model: Model): string
	local pet = PetModels.describe(model.Name)
	if pet then
		return pet.name
	end
	local egg = EggModels.describe(model.Name)
	if egg then
		return egg.name
	end
	return model.Name
end

local function addLabels(parent: Instance, display: Instance)
	for _, model in modelsIn(display) do
		local low, high = boundsOf(model)
		if low and high then
			local anchor = newPart("Label", parent)
			anchor.Size = Vector3.one * 0.2
			anchor.Transparency = 1
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.CanTouch = false
			anchor.Position = Vector3.new((low.X + high.X) / 2, high.Y + LABEL_HEIGHT, (low.Z + high.Z) / 2)
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromOffset(180, 30)
			billboard.MaxDistance = LABEL_DISTANCE
			billboard.LightInfluence = 0
			billboard.Parent = anchor
			newText(billboard, displayName(model), UDim2.fromScale(1, 1), UDim2.new(), Enum.Font.GothamBold)
		end
	end
end

-- (Re)builds the floor under everything on display, the sign over each side, the labels, and the way back.
local function buildFixtures()
	local showroom = root :: Folder
	local old = showroom:FindFirstChild("Fixtures")
	if old then
		old:Destroy()
	end
	local fixtures = Instance.new("Folder")
	fixtures.Name = "Fixtures"

	-- The floor reaches past everything on display, and is never smaller than the minimum, centred on the aisle.
	local left = Showroom.X - Showroom.MIN_WIDTH / 2
	local right = Showroom.X + Showroom.MIN_WIDTH / 2
	local front = Showroom.Z - Showroom.ARRIVAL_SPACE
	local back = Showroom.Z + Showroom.MIN_DEPTH - Showroom.ARRIVAL_SPACE
	local bounds: { [Side]: { low: Vector3, high: Vector3 } } = {}
	for _, side in SIDES do
		local display = displays[side]
		local low, high
		if display then
			low, high = boundsOf(display)
		end
		if low and high then
			bounds[side] = { low = low, high = high }
			left = math.min(left, low.X - Showroom.MARGIN)
			right = math.max(right, high.X + Showroom.MARGIN)
			front = math.min(front, low.Z - Showroom.ARRIVAL_SPACE)
			back = math.max(back, high.Z + Showroom.MARGIN)
		end
	end

	local floor = newPart("Floor", fixtures)
	floor.Size = Vector3.new(right - left, FLOOR_THICKNESS, back - front)
	floor.Position = Vector3.new((left + right) / 2, Showroom.FLOOR_Y - FLOOR_THICKNESS / 2, (front + back) / 2)
	floor.Color = Color3.fromRGB(72, 78, 98)

	local aisle = newPart("Aisle", fixtures)
	aisle.Size = Vector3.new(Showroom.AISLE - 4, 0.2, back - front)
	aisle.Position = Vector3.new(Showroom.X, Showroom.FLOOR_Y + 0.1, (front + back) / 2)
	aisle.Color = Color3.fromRGB(236, 196, 92)
	aisle.CanCollide = false

	for _, side in SIDES do
		local box = bounds[side]
		if box then
			addSign(
				fixtures,
				side .. "Sign",
				string.upper(side),
				(box.low.X + box.high.X) / 2,
				box.high.Y + 6,
				box.low.Z
			)
			addLabels(fixtures, displays[side])
		end
	end
	if bounds.Pets == nil or bounds.Eggs == nil then
		local _, y, z = Showroom.arrivalPoint()
		addSign(fixtures, "BuildingSign", "Building the models from code...", Showroom.X, y + 14, z + 12)
	end

	-- The way back: a pad where visitors arrive, with a prompt that sends them to the hub.
	local x, y, z = Showroom.arrivalPoint()
	local pad = newPart("HubPad", fixtures)
	pad.Size = Vector3.new(12, 0.4, 12)
	pad.Position = Vector3.new(x, y + 0.2, z)
	pad.Color = Color3.fromRGB(120, 220, 140)
	pad.Material = Enum.Material.Neon
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Back to the hub"
	prompt.ObjectText = "Model Showroom"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	prompt.Triggered:Connect(function(player: Player)
		if onLeave then
			onLeave(player)
		end
	end)

	fixtures.Parent = showroom
end

----------------------------------------------------------------------------------------------------------------
-- For other services, and for Studio's command bar

-- Moves the imported pet and egg folders (tools/export-models) onto the showroom floor, keeping their layout.
-- Safe to run again: they stay where they are once they are there. Prints what it did, for the command bar.
function ShowroomService.MoveImportedModels(): number
	local moved = 0
	for _, side in SIDES do
		local folder = findImported(side)
		if folder and placeDisplay(folder, side) then
			moved += 1
			print(`[Showroom] Moved "{folder.Name}" to the Model Showroom ({#modelsIn(folder)} models).`)
		end
	end
	if moved == 0 then
		print(
			`[Showroom] Found no "{Showroom.PET_FOLDER}" or "{Showroom.EGG_FOLDER}" folder in Workspace or ServerStorage.`
		)
	end
	return moved
end

-- Starts building any side that was not imported, if that has not started yet. Returns straight away; the models
-- appear over a few seconds.
function ShowroomService.Prepare()
	if root == nil or building or (displays.Pets and displays.Eggs) then
		return
	end
	building = true
	task.spawn(function()
		for _, side in SIDES do
			if displays[side] == nil then
				local display = buildDisplay(side)
				display.Parent = root
				displays[side] = display
				buildFixtures()
			end
		end
		building = false
	end)
end

-- True once both sides have something on display.
function ShowroomService.IsReady(): boolean
	return displays.Pets ~= nil and displays.Eggs ~= nil
end

-- Where a visitor arrives: their feet, and the way to face (towards the displays).
function ShowroomService.GetArrival(): (Vector3, Vector3)
	local x, y, z = Showroom.arrivalPoint()
	return Vector3.new(x, y, z), Vector3.new(0, 0, 1)
end

-- What to do when someone asks to leave from the showroom floor (AdminService sends them to the hub).
function ShowroomService.SetLeaveHandler(handler: (Player) -> ())
	onLeave = handler
end

function ShowroomService.Init()
	local showroom = Instance.new("Folder")
	showroom.Name = "Showroom"
	root = showroom

	for _, side in SIDES do
		local folder = findImported(side)
		if folder and placeDisplay(folder, side) then
			folder.Parent = showroom
			displays[side] = folder
		end
	end
	buildFixtures()
	showroom.Parent = Workspace
end

return ShowroomService
