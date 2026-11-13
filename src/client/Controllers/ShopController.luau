-- Keeps the shop's numbers up to date: coins, pen level, owned passes, server luck, and real Robux prices.
-- Shows the result of each purchase as a toast.

local MarketplaceService = game:GetService("MarketplaceService")

local Load = require(script.Parent.Parent.Load)
local Net = Load.shared("Net")
local Shop = Load.shared("Config", "Shop")

local UiState = require(script.Parent.Parent.Ui.UiState)

local SUCCESS_COLOR = Color3.fromRGB(110, 235, 130)
local FAILURE_COLOR = Color3.fromRGB(255, 110, 100)

local ShopController = {}

local function applyState(state)
	if typeof(state) ~= "table" then
		return
	end
	if typeof(state.coins) == "number" then
		UiState.coins:set(state.coins)
	end
	if typeof(state.penLevel) == "number" then
		UiState.penLevel:set(state.penLevel)
	end
	if typeof(state.passes) == "table" then
		local owned = {}
		for _, passId in state.passes do
			owned[passId] = true
		end
		UiState.ownedPasses:set(owned)
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
	for _, pass in Shop.Passes do
		if pass.gamePassId ~= 0 then
			table.insert(wanted, { key = pass.id, id = pass.gamePassId, infoType = Enum.InfoType.GamePass })
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
end

function ShopController.Start()
	applyState(Net.GetShopState:InvokeServer())
	loadPrices()
end

return ShopController
