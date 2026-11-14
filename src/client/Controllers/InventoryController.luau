-- The local player's eggs, nests and pets: keeps UiState up to date with what the server sends, does what the
-- Eggs and Pets panels' buttons ask (Ui/Panels), announces hatches, and fills the panels' 3D preview with the
-- selected egg or pet, turning slowly.
--
-- The server decides everything (see InventoryService): this only asks, and shows.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local EggRig = Load.shared("EggRig")
local HatchMath = Load.shared("HatchMath")
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")
local PetRig = Load.shared("PetRig")

local Panels = require(script.Parent.Parent.Ui.Panels)
local UiState = require(script.Parent.Parent.Ui.UiState)

local localPlayer = Players.LocalPlayer
local peek = UiState.Fusion.peek

local InventoryController = {}

-- How often countdowns refresh, per second.
local CLOCK_RATE = 4
-- How fast the preview turns, in radians per second.
local PREVIEW_TURN = 0.7
-- An egg in the preview is shown at nest size.
local PREVIEW_EGG = { radius = 2.2, halfLength = 2.9 }

-- The egg the player last asked to place, until the server answers.
local pendingPlace: string? = nil
local lastClockAt = -math.huge

local preview = {
	key = nil :: string?,
	model = nil :: Model?,
	camera = nil :: Camera?,
	focus = Vector3.zero,
	distance = 10,
	angle = math.pi,
}

local function freeNests(): number
	return peek(UiState.nestCount) - #peek(UiState.nests)
end

-- The first item of a panel, to show when it opens with nothing of its own selected.
local function firstOf(panel: string)
	if panel == "Eggs" then
		local egg = peek(UiState.eggs)[1]
		return if egg then { type = "Egg", kind = egg.kind, rarity = egg.rarity } else nil
	end
	local pets = peek(UiState.pets)
	local pet = pets[#pets]
	return if pet then { type = "Pet", kind = pet.kind, rarity = pet.rarity } else nil
end

local function openPanel(panel: string)
	UiState.panel:set(panel)
	if panel == "Pets" then
		UiState.newPets:set(0)
	end
	local selected = peek(UiState.selected)
	local wanted = if panel == "Eggs" then "Egg" else "Pet"
	if panel ~= "None" and (selected == nil or selected.type ~= wanted) then
		UiState.selected:set(firstOf(panel))
	end
end

local function placeEgg(uid: string)
	if freeNests() <= 0 then
		UiState.showToast("Your nests are full: wait for an egg to hatch", Color3.fromRGB(255, 190, 90))
		return
	end
	pendingPlace = uid
	Net.PlaceEgg:FireServer(uid)
end

-- Takes in the inventory the server sent.
function InventoryController.Apply(state)
	if typeof(state) ~= "table" then
		return
	end
	UiState.eggs:set(state.eggs or {})
	UiState.nests:set(state.nests or {})
	UiState.pets:set(state.pets or {})
	UiState.nestCount:set(state.nestCount or 2)
	UiState.eggCount:set(#(state.eggs or {}))

	if pendingPlace then
		for _, nest in state.nests or {} do
			if nest.uid == pendingPlace then
				local left = HatchMath.timeLeft(nest.placedAt, nest.bonus, nest.rarity, Workspace:GetServerTimeNow())
				UiState.showToast(
					`Placed in nest {nest.slot}: hatches in {NumberFormat.duration(left)}`,
					Panels.rarityColor(nest.rarity)
				)
			end
		end
		pendingPlace = nil
	end
end

local function onHatched(pet)
	if typeof(pet) ~= "table" then
		return
	end
	UiState.showToast(`Your {Panels.petName(pet.kind)} hatched! ({pet.rarity})`, Panels.rarityColor(pet.rarity), 4)
	if peek(UiState.panel) ~= "Pets" then
		UiState.newPets:set(peek(UiState.newPets) + 1)
	end
end

----------------------------------------------------------------------------------------------------------------
-- The preview

local function findPreview(): ViewportFrame?
	local gui = localPlayer:FindFirstChild("PlayerGui")
	local hud = gui and gui:FindFirstChild("Hud")
	local root = hud and hud:FindFirstChild("Root")
	local inventory = root and root:FindFirstChild("Inventory")
	local viewport = inventory and inventory:FindFirstChild("Preview")
	return if viewport and viewport:IsA("ViewportFrame") then viewport else nil
end

local function clearPreview()
	if preview.model then
		preview.model:Destroy()
		preview.model = nil
	end
end

-- Puts the selected egg or pet in the preview.
local function showInPreview(viewport: ViewportFrame, selected)
	clearPreview()
	if selected == nil then
		return
	end
	local model: Model?
	if selected.type == "Egg" then
		model = EggRig.build(selected.kind, PREVIEW_EGG)
		-- The egg is built lying with its top towards +X; stand it on end.
		local upright = CFrame.Angles(0, 0, math.pi / 2)
		for _, part in (model :: Model):GetDescendants() do
			if part:IsA("BasePart") then
				part.CFrame = upright * part.CFrame
			end
		end
		preview.focus = Vector3.zero
		preview.distance = PREVIEW_EGG.halfLength * 4.6
	else
		model = PetRig.build(selected.kind)
		if model then
			local root = model.PrimaryPart :: BasePart
			preview.focus = root.CFrame.Position
			preview.distance = math.max(root.Size.X, root.Size.Y, root.Size.Z) * 1.7
		end
	end
	if model == nil then
		return
	end
	model.Parent = viewport
	preview.model = model
	if preview.camera == nil or preview.camera.Parent ~= viewport then
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		preview.camera = camera
	end
	-- Start facing the front (models face -Z).
	preview.angle = math.pi
end

local function selectionKey(selected): string?
	return if selected then `{selected.type}:{selected.kind}:{selected.rarity}` else nil
end

local function update(deltaTime: number)
	local now = Workspace:GetServerTimeNow()
	if os.clock() - lastClockAt >= 1 / CLOCK_RATE then
		lastClockAt = os.clock()
		UiState.clock:set(now)
	end

	if peek(UiState.panel) == "None" then
		return
	end
	local viewport = findPreview()
	if viewport == nil then
		return
	end
	local selected = peek(UiState.selected)
	local key = selectionKey(selected)
	if key ~= preview.key then
		preview.key = key
		showInPreview(viewport, selected)
	end
	local camera = preview.camera
	if camera and preview.model then
		preview.angle += deltaTime * PREVIEW_TURN
		local d = preview.distance
		local eye = preview.focus + Vector3.new(math.sin(preview.angle) * d, d * 0.3, math.cos(preview.angle) * d)
		camera.CFrame = CFrame.lookAt(eye, preview.focus)
	end
end

function InventoryController.Init()
	UiState.actions.placeEgg = placeEgg
	UiState.actions.openPanel = openPanel
	Net.InventoryChanged.OnClientEvent:Connect(InventoryController.Apply)
	Net.PetHatched.OnClientEvent:Connect(onHatched)
	RunService.RenderStepped:Connect(update)
end

return InventoryController
