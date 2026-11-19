-- Putting eggs down from the Roblox inventory. Every egg the player has claimed is a tool in their Backpack (the
-- hotbar; see the server's EggToolService). While they hold one, a see-through egg on a ring follows the pointer
-- (the mouse, the last tap, or the middle of the screen on a gamepad): green where the egg can go down in their own
-- pen, red anywhere else. Clicking (or tapping, or the gamepad's trigger) puts it down there.
--
-- The server decides (InventoryService): this only shows where the egg would go, and asks.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local EggRig = Load.shared("EggRig")
local Net = Load.shared("Net")
local Plots = Load.shared("Plots")

local UiState = require(script.Parent.Parent.Ui.UiState)

local localPlayer = Players.LocalPlayer
local peek = UiState.Fusion.peek

local EggToolController = {}

-- Must match the server's EggToolService.
local KIND_ATTRIBUTE = "EggKind"
-- The ghost egg is drawn at the size eggs have in the pen.
local GHOST_EGG = { radius = 2.2, halfLength = 2.9 }
local GHOST_TRANSPARENCY = 0.55
local RING_DIAMETER = 7
local GOOD = Color3.fromRGB(90, 230, 110)
local BAD = Color3.fromRGB(240, 80, 80)
local WARN = Color3.fromRGB(255, 190, 90)
-- How far the pointer can reach to put an egg down, in studs.
local REACH = 400
-- The fewest seconds between two eggs put down (a held button or a double tap is one egg).
local PLACE_COOLDOWN = 0.3

local ghost = {
	folder = nil :: Folder?,
	kind = nil :: string?,
	model = nil :: Model?,
	ring = nil :: Part?,
}
-- Tools whose Activated is already hooked up.
local hooked: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastPlacedAt = -math.huge

-- The egg tool in the player's hand, if they are holding one.
local function heldEggTool(): Tool?
	local character = localPlayer.Character
	if character == nil then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and typeof(child:GetAttribute(KIND_ATTRIBUTE)) == "string" then
			return child
		end
	end
	return nil
end

-- The local player's plot (its index in Shared/Plots), from the plot models the server tagged with their owner.
local function ownPlot(): number?
	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("Owner") == localPlayer.UserId then
			local index = plot:GetAttribute("Index")
			return if typeof(index) == "number" then index else nil
		end
	end
	return nil
end

-- The ray from the camera through the pointer: the mouse, or the last tap (Roblox moves the mouse to a tap before
-- the tool hears about it), or the middle of the screen on a gamepad.
local function pointerRay(): Ray?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	if string.find(UserInputService:GetLastInputType().Name, "^Gamepad") then
		local size = camera.ViewportSize
		return camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	end
	return localPlayer:GetMouse().UnitRay
end

-- The spot on the ground the pointer is over (only the map counts, not players, pets or eggs), if any.
local function pointerSpot(): Vector3?
	local ray = pointerRay()
	local map = Workspace:FindFirstChild("Map")
	if ray == nil or map == nil then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	local result = Workspace:Raycast(ray.Origin, ray.Direction.Unit * REACH, params)
	return if result then result.Position else nil
end

-- Whether an egg could go down at a spot: in the player's own pen, clear of its fence, with room for another egg
-- hatching. Returns the reason if not.
local function canPlaceAt(spot: Vector3?): (boolean, string?)
	if #peek(UiState.hatching) >= peek(UiState.eggCapacity) then
		return false, `Your pen can only hatch {peek(UiState.eggCapacity)} eggs at once: wait, or buy a bigger pen`
	end
	local plot = ownPlot()
	if spot == nil or plot == nil then
		return false, "Click a spot inside your pen to put the egg down"
	end
	local inward, along = Plots.toLocal(plot, spot.X, spot.Z)
	if not Plots.inPen(peek(UiState.penLevel), inward, along, Plots.EGG_MARGIN) then
		return false, "Click a spot inside your pen to put the egg down"
	end
	return true, nil
end

-- One of the player's eggs of a kind (its uid), to put down.
local function eggOfKind(kind: string): string?
	for _, egg in peek(UiState.eggs) do
		if egg.kind == kind then
			return egg.uid
		end
	end
	return nil
end

local function clearGhost()
	if ghost.model then
		ghost.model:Destroy()
		ghost.model = nil
	end
	ghost.kind = nil
	if ghost.ring then
		ghost.ring.Transparency = 1
	end
end

-- The see-through egg standing where the held egg would go, and the ring under it.
local function showGhost(kind: string, spot: Vector3, good: boolean)
	local folder = ghost.folder :: Folder
	if ghost.kind ~= kind then
		clearGhost()
		local model = EggRig.build(kind, GHOST_EGG)
		model.Name = "Ghost"
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanQuery = false
				part.CastShadow = false
				if part.Transparency < 1 then
					part.Transparency = math.max(part.Transparency, GHOST_TRANSPARENCY)
				end
			elseif part:IsA("ParticleEmitter") or part:IsA("Light") then
				part:Destroy()
			end
		end
		model.Parent = folder
		ghost.model = model
		ghost.kind = kind
	end
	local ring = ghost.ring :: Part
	ring.Transparency = 0.25
	ring.Color = if good then GOOD else BAD
	ring.CFrame = CFrame.new(spot + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	-- Standing on end (the egg is built lying with its top towards +X), its bottom on the ground.
	local model = ghost.model :: Model
	model:PivotTo(CFrame.new(spot + Vector3.new(0, GHOST_EGG.halfLength, 0)) * CFrame.Angles(0, 0, math.pi / 2))
end

-- The player clicked (or tapped) while holding an egg: put one down at the pointer, if it can go there.
local function placeHeld(tool: Tool)
	local clock = os.clock()
	if clock - lastPlacedAt < PLACE_COOLDOWN then
		return
	end
	local kind = tool:GetAttribute(KIND_ATTRIBUTE)
	local uid = if typeof(kind) == "string" then eggOfKind(kind) else nil
	if uid == nil then
		return
	end
	local spot = pointerSpot()
	local ok, reason = canPlaceAt(spot)
	if not ok or spot == nil then
		UiState.showToast(reason or "Click a spot inside your pen to put the egg down", WARN)
		return
	end
	lastPlacedAt = clock
	Net.PlaceEgg:FireServer(uid, spot.X, spot.Z)
end

local function update()
	local tool = heldEggTool()
	if tool == nil then
		if ghost.kind ~= nil then
			clearGhost()
		end
		return
	end
	if not hooked[tool] then
		hooked[tool] = true
		tool.Activated:Connect(function()
			placeHeld(tool)
		end)
		UiState.showToast("Click a spot in your pen to put the egg down")
	end
	local spot = pointerSpot()
	local kind = tool:GetAttribute(KIND_ATTRIBUTE) :: string
	if spot then
		showGhost(kind, spot, (canPlaceAt(spot)))
	elseif ghost.kind ~= nil then
		clearGhost()
	end
end

-- Puts one of the player's eggs of a kind in their hand (the Eggs panel's Hold button).
function EggToolController.Hold(kind: string)
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if backpack == nil or humanoid == nil then
		return
	end
	for _, tool in backpack:GetChildren() do
		if tool:IsA("Tool") and tool:GetAttribute(KIND_ATTRIBUTE) == kind then
			humanoid:EquipTool(tool)
			UiState.actions.openPanel("None")
			return
		end
	end
end

function EggToolController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "EggPlacement"
	folder.Parent = Workspace
	ghost.folder = folder
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, RING_DIAMETER, RING_DIAMETER)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Transparency = 1
	ring.Parent = folder
	ghost.ring = ring

	UiState.actions.holdEgg = EggToolController.Hold
	RunService.RenderStepped:Connect(update)
end

return EggToolController
