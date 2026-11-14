-- The local player's eggs, pen, pets and dollars: keeps UiState up to date with what the server sends, does what
-- the Eggs and Pets panels' buttons ask (Ui/Panels), shows the server's messages and announces hatches, and fills
-- the panels' 3D preview with the selected egg or pet, turning slowly.
--
-- The server decides everything (see InventoryService and MountService): this only asks, and shows.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local EggRig = Load.shared("EggRig")
local Net = Load.shared("Net")
local PetRig = Load.shared("PetRig")
local Plots = Load.shared("Plots")

local Panels = require(script.Parent.Parent.Ui.Panels)
local UiState = require(script.Parent.Parent.Ui.UiState)

local localPlayer = Players.LocalPlayer
local peek = UiState.Fusion.peek

local InventoryController = {}

-- How often countdowns refresh, per second.
local CLOCK_RATE = 4
-- How fast the preview turns, in radians per second.
local PREVIEW_TURN = 0.7
-- An egg in the preview is shown at the size it has in the pen.
local PREVIEW_EGG = { radius = 2.2, halfLength = 2.9 }
local WARN = Color3.fromRGB(255, 190, 90)

local lastClockAt = -math.huge

local preview = {
	key = nil :: string?,
	model = nil :: Model?,
	camera = nil :: Camera?,
	focus = Vector3.zero,
	distance = 10,
	angle = math.pi,
}

local function rgb(color: { number }?): Color3?
	return if color then Color3.fromRGB(color[1], color[2], color[3]) else nil
end

-- Whether the local player is standing in their own pen.
local function inOwnPen(): boolean
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if root == nil or not root:IsA("BasePart") or plots == nil then
		return false
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("Owner") == localPlayer.UserId then
			local index = plot:GetAttribute("Index") :: number
			local position = root.CFrame.Position
			local inward, along = Plots.toLocal(index, position.X, position.Z)
			return Plots.inPen(peek(UiState.penLevel), inward, along, 0)
		end
	end
	return false
end

-- The first item of a panel, to show when it opens with nothing of its own selected.
local function firstOf(panel: string)
	if panel == "Eggs" then
		local egg = peek(UiState.eggs)[1]
		return if egg then { type = "Egg", kind = egg.kind, rarity = egg.rarity } else nil
	end
	local pets = peek(UiState.pets)
	local pet = pets[#pets]
	return if pet
		then { type = "Pet", kind = pet.kind, rarity = pet.rarity, variant = pet.variant, uid = pet.uid }
		else nil
end

local function openPanel(panel: string)
	UiState.panel:set(panel)
	if panel ~= "None" then
		-- One panel at a time: close the Shop or Settings.
		UiState.openPanel:set(nil)
	end
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
	if #peek(UiState.hatching) >= peek(UiState.eggCapacity) then
		UiState.showToast(
			`Your pen can only hatch {peek(UiState.eggCapacity)} eggs at once: wait, or buy a bigger pen`,
			WARN
		)
		return
	end
	if not inOwnPen() then
		UiState.showToast("Walk into your pen to put eggs down", WARN)
		return
	end
	Net.PlaceEgg:FireServer(uid)
end

-- Takes in the inventory the server sent.
function InventoryController.Apply(state)
	if typeof(state) ~= "table" then
		return
	end
	UiState.eggs:set(state.eggs or {})
	UiState.hatching:set(state.hatching or {})
	UiState.pets:set(state.pets or {})
	UiState.penLevel:set(state.penLevel or 1)
	UiState.eggCapacity:set(state.eggCapacity or 2)
	UiState.petCapacity:set(state.petCapacity or 10)
	UiState.mountChoice:set(state.mount or "")
	UiState.eggCount:set(#(state.eggs or {}))
	if state.dollars then
		UiState.dollars:set(state.dollars)
		UiState.income:set(state.income or 0)
	end
	-- A selected pet that has been sold is no longer shown.
	local selected = peek(UiState.selected)
	if selected and selected.type == "Pet" and selected.uid then
		local found = false
		for _, pet in state.pets or {} do
			found = found or pet.uid == selected.uid
		end
		if not found then
			UiState.selected:set(firstOf("Pets"))
		end
	end
end

local function onHatched(pet)
	if typeof(pet) ~= "table" then
		return
	end
	local variant = if pet.variant and pet.variant ~= "Normal" then `{pet.variant} ` else ""
	UiState.showToast(
		`Your {Panels.fullPetName(pet.kind, pet.variant)} hatched! ({variant}{pet.rarity})`,
		Panels.rarityColor(pet.rarity),
		4
	)
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
		model = PetRig.build(selected.kind, selected.variant)
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
	return if selected then `{selected.type}:{selected.kind}:{selected.rarity}:{selected.variant or ""}` else nil
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
	UiState.actions.setInPen = function(uid: string, inPen: boolean)
		Net.SetInPen:FireServer(uid, inPen)
	end
	UiState.actions.equipBest = function()
		Net.EquipBest:FireServer()
	end
	UiState.actions.sellPet = function(uid: string)
		Net.SellPet:FireServer(uid)
	end
	UiState.actions.ridePet = function(uid: string)
		Net.RidePet:FireServer(uid)
	end
	Net.InventoryChanged.OnClientEvent:Connect(InventoryController.Apply)
	Net.PetHatched.OnClientEvent:Connect(onHatched)
	Net.DollarsChanged.OnClientEvent:Connect(function(dollars: number, income: number)
		UiState.dollars:set(dollars)
		UiState.income:set(income)
	end)
	Net.Notice.OnClientEvent:Connect(function(text: string, color: { number }?)
		UiState.showToast(text, rgb(color), 3)
	end)
	Net.MountChanged.OnClientEvent:Connect(function(uid: string)
		UiState.riddenPet:set(uid or "")
	end)
	RunService.RenderStepped:Connect(update)
end

return InventoryController
