-- Keeps the shop's numbers up to date: dollars, pen level, training stick tier, owned passes and packs, revives,
-- server luck, and real Robux prices.
-- Shows the result of each purchase as a toast, and turns each pack's pet on its card while the shop is open.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Load = require(script.Parent.Parent.Load)
local Net = Load.shared("Net")
local PetRig = Load.shared("PetRig")
local Shop = Load.shared("Config", "Shop")

local UiState = require(script.Parent.Parent.Ui.UiState)

local SUCCESS_COLOR = Color3.fromRGB(110, 235, 130)
local FAILURE_COLOR = Color3.fromRGB(255, 110, 100)
-- How fast the pack pets turn, in radians per second.
local PET_TURN = 0.6

local localPlayer = Players.LocalPlayer

local ShopController = {}

-- Each pack's pet on its card, once built: packId -> { model, camera, focus, distance, angle }.
local petViews: { [string]: any } = {}

-- A pack's card in the shop panel, if the HUD is up.
local function findPackCard(packId: string): Instance?
	local gui = localPlayer:FindFirstChild("PlayerGui")
	local node: Instance? = gui and gui:FindFirstChild("Hud")
	for _, name in { "Root", "ShopPanel", "Body", "Scroll", "Packs", "List", packId } do
		node = node and node:FindFirstChild(name)
	end
	return node
end

-- Builds a pack's pet into its card's 3D view, facing the front.
local function showPackPet(pack): any?
	local card = findPackCard(pack.id)
	local viewport = card and card:FindFirstChild("PetView")
	if viewport == nil or not viewport:IsA("ViewportFrame") then
		return nil
	end
	local model = PetRig.build(pack.pet.kind, pack.pet.variant)
	if model == nil then
		return nil
	end
	model.Parent = viewport:FindFirstChild("World") or viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local root = model.PrimaryPart :: BasePart
	return {
		model = model,
		camera = camera,
		focus = root.CFrame.Position,
		distance = math.max(root.Size.X, root.Size.Y, root.Size.Z) * 1.6,
		-- Three-quarters on, to start.
		angle = math.pi * 0.8,
	}
end

local function turnPackPets(deltaTime: number)
	if UiState.Fusion.peek(UiState.openPanel) ~= "Shop" then
		return
	end
	for _, pack in Shop.Packs do
		local view = petViews[pack.id]
		if view == nil then
			view = showPackPet(pack)
			petViews[pack.id] = view
		end
		if view then
			view.angle += deltaTime * PET_TURN
			local d = view.distance
			local eye = view.focus + Vector3.new(math.sin(view.angle) * d, d * 0.25, math.cos(view.angle) * d)
			view.camera.CFrame = CFrame.lookAt(eye, view.focus)
		end
	end
end

local function applyState(state)
	if typeof(state) ~= "table" then
		return
	end
	if typeof(state.dollars) == "number" then
		UiState.dollars:set(state.dollars)
	end
	if typeof(state.penLevel) == "number" then
		UiState.penLevel:set(state.penLevel)
	end
	if typeof(state.stickLevel) == "number" then
		UiState.stickLevel:set(state.stickLevel)
	end
	if typeof(state.staminaMultiplier) == "number" then
		UiState.staminaMultiplier:set(state.staminaMultiplier)
	end
	if typeof(state.passes) == "table" then
		local owned = {}
		for _, passId in state.passes do
			owned[passId] = true
		end
		UiState.ownedPasses:set(owned)
	end
	if typeof(state.packs) == "table" then
		local owned = {}
		for _, packId in state.packs do
			if typeof(packId) == "string" then
				owned[packId] = true
			end
		end
		UiState.ownedPacks:set(owned)
	end
	if typeof(state.revives) == "number" then
		UiState.revives:set(state.revives)
	end
	if typeof(state.luck) == "table" then
		UiState.luckBoosts = state.luck
	end
end

-- Asks Roblox for each item's real price (the dashboard is the source of truth), so a price changed there shows
-- right away. Items without an ID keep the price written in Config/Shop.
local function loadPrices()
	local wanted = {}
	for _, product in Shop.Products do
		if product.productId ~= 0 then
			table.insert(wanted, { key = product.id, id = product.productId, infoType = Enum.InfoType.Product })
		end
	end
	for level, penLevel in Shop.PenLevels do
		if penLevel.productId ~= 0 then
			table.insert(
				wanted,
				{ key = "PenLevel" .. level, id = penLevel.productId, infoType = Enum.InfoType.Product }
			)
		end
	end
	for level, stickLevel in Shop.StickLevels do
		if stickLevel.productId ~= 0 then
			table.insert(
				wanted,
				{ key = "StickLevel" .. level, id = stickLevel.productId, infoType = Enum.InfoType.Product }
			)
		end
	end
	for to, doubling in Shop.StaminaDoublings do
		if doubling.productId ~= 0 then
			table.insert(
				wanted,
				{ key = "StaminaDoubling" .. to, id = doubling.productId, infoType = Enum.InfoType.Product }
			)
		end
	end
	for _, pass in Shop.Passes do
		if pass.gamePassId ~= 0 then
			table.insert(wanted, { key = pass.id, id = pass.gamePassId, infoType = Enum.InfoType.GamePass })
		end
	end
	for _, pack in Shop.Packs do
		if pack.productId ~= 0 then
			table.insert(wanted, { key = pack.id, id = pack.productId, infoType = Enum.InfoType.Product })
		end
	end

	for _, item in wanted do
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(item.id, item.infoType)
		end)
		if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
			local prices = table.clone(UiState.Fusion.peek(UiState.prices))
			prices[item.key] = info.PriceInRobux
			UiState.prices:set(prices)
		end
	end
end

function ShopController.Init()
	Net.PlayerStateUpdated.OnClientEvent:Connect(applyState)
	Net.LuckChanged.OnClientEvent:Connect(function(boosts)
		if typeof(boosts) == "table" then
			UiState.luckBoosts = boosts
		end
	end)
	Net.PurchaseResult.OnClientEvent:Connect(function(_itemId, ok, message)
		if typeof(message) == "string" then
			UiState.showToast(message, if ok then SUCCESS_COLOR else FAILURE_COLOR, 3)
		end
	end)
	RunService.RenderStepped:Connect(turnPackPets)
end

function ShopController.Start()
	applyState(Net.GetShopState:InvokeServer())
	loadPrices()
end

return ShopController
