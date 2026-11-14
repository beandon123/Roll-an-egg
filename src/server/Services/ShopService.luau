-- The shop: Robux purchases (developer products and game passes), dollar purchases, and server luck boosts.
--
-- Robux purchases follow Roblox's rules for granting exactly once: ProcessReceipt records each purchase ID in the
-- player's saved data and only reports the purchase as granted once that record has been saved. If anything
-- fails, Roblox calls ProcessReceipt again later, and the recorded ID stops it being granted twice.
--
-- Clients only say which item they want (an id from Config/Shop). The server looks up the price, checks it, and
-- shows Roblox's purchase prompt itself. Clients never send prices, amounts, or product IDs.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local LuckBoost = require(Shared.LuckBoost)
local Net = require(Shared.Net)
local NumberFormat = require(Shared.NumberFormat)
local Shop = require(Shared.Config.Shop)

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local RunwayService = require(script.Parent.RunwayService)

-- How many granted purchase IDs each player's data remembers.
local PURCHASE_ID_MEMORY = 100
-- Fewest seconds between two shop requests from one player.
local REQUEST_COOLDOWN = 0.5

local LUCK_COLOR = { 90, 230, 120 }
-- The game pass that doubles what a player's pen earns, and by how much.
local DOUBLE_DOLLARS = "DoubleDollars"
local DOUBLE_DOLLARS_MULTIPLIER = 2

local ShopService = {}

-- passId -> true, for each player. Game passes belong to the Roblox account, so this is looked up on join,
-- never saved.
local ownedPasses: { [Player]: { [string]: boolean } } = {}
local lastRequestAt: { [Player]: number } = {}
-- Server luck boosts (Shared/LuckBoost) and the luck last applied.
local luckBoosts: { LuckBoost.Boost } = {}
local appliedLuck = 1

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function sendResult(player: Player, itemId: string, ok: boolean, message: string)
	Net.PurchaseResult:FireClient(player, itemId, ok, message)
end

local function passList(player: Player): { string }
	local list = {}
	for passId, owned in ownedPasses[player] or {} do
		if owned then
			table.insert(list, passId)
		end
	end
	table.sort(list)
	return list
end

-- Everything the shop shows for a player.
local function stateOf(player: Player)
	local data = DataService.GetData(player)
	return {
		dollars = if data then data.Dollars else 0,
		penLevel = if data then data.PenLevel else 1,
		staminaMultiplier = if data then data.StaminaMultiplier else 1,
		passes = passList(player),
	}
end

local function pushState(player: Player)
	Net.PlayerStateUpdated:FireClient(player, stateOf(player))
end

local function throttled(player: Player): boolean
	local time = os.clock()
	local last = lastRequestAt[player]
	if last and time - last < REQUEST_COOLDOWN then
		return true
	end
	lastRequestAt[player] = time
	return false
end

----------------------------------------------------------------------------------------------------------------
-- Luck

local function applyLuck()
	local luck = LuckBoost.current(luckBoosts, now())
	if luck ~= appliedLuck then
		appliedLuck = luck
		RunwayService.SetLuck(luck)
	end
end

local function addLuck(multiplier: number, duration: number, buyer: Player?)
	LuckBoost.add(luckBoosts, multiplier, duration, now())
	applyLuck()
	Net.LuckChanged:FireAllClients(luckBoosts)
	local minutes = math.floor(duration / 60 + 0.5)
	local who = if buyer then buyer.DisplayName else "Someone"
	Net.Announce:FireAllClients(`{who} boosted everyone's luck x{multiplier} for {minutes} minutes!`, LUCK_COLOR)
end

----------------------------------------------------------------------------------------------------------------
-- Granting

-- Gives a player what they paid for. Returns the message to show them. Must not yield.
local function grant(player: Player, reward: Shop.Grant): string
	local data = DataService.GetData(player)
	if data == nil then
		error("data not loaded")
	end

	if reward.kind == "Dollars" then
		InventoryService.AddDollars(player, reward.amount)
		pushState(player)
		return `+${NumberFormat.abbreviate(reward.amount)}!`
	elseif reward.kind == "MaxStamina" then
		data.MaxStaminaBonus += reward.amount
		RunwayService.RefreshMaxStamina(player)
		return `+{NumberFormat.abbreviate(reward.amount)} Max Stamina!`
	elseif reward.kind == "Luck" then
		addLuck(reward.multiplier, reward.duration, player)
		return `x{reward.multiplier} luck for the whole server!`
	elseif reward.kind == "PenLevel" then
		local message = InventoryService.RaisePen(player)
		pushState(player)
		return message or "Your pen is already the biggest it can be!"
	elseif reward.kind == "StaminaDoubling" then
		data.StaminaMultiplier = math.min(Shop.MAX_STAMINA_MULTIPLIER, data.StaminaMultiplier * 2)
		RunwayService.RefreshMaxStamina(player)
		pushState(player)
		return `Max Stamina doubled! Now x{data.StaminaMultiplier}.`
	end
	error(`unknown grant {reward.kind}`)
end

local function grantPass(player: Player, passId: string)
	local owned = ownedPasses[player]
	if owned == nil then
		return
	end
	owned[passId] = true
	if passId == DOUBLE_DOLLARS then
		InventoryService.SetIncomeMultiplier(player, DOUBLE_DOLLARS_MULTIPLIER)
	end
	pushState(player)
end

-- Roblox calls this for every developer product purchase, possibly more than once, possibly after the player
-- has left and rejoined another server.
local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local reward, itemId = Shop.rewardForProductId(receipt.ProductId)
	if reward == nil or itemId == nil then
		warn(`[ShopService] no shop item for developer product {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if DataService.WaitForData(player) == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Fetched again after the wait: never keep a data table across a yield.
	local data = DataService.GetData(player)
	if data == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = receipt.PurchaseId
	if table.find(data.PurchaseIds, purchaseId) == nil then
		local ok, result = pcall(grant, player, reward)
		if not ok then
			warn(`[ShopService] could not grant {itemId}: {result}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		while #data.PurchaseIds >= PURCHASE_ID_MEMORY do
			table.remove(data.PurchaseIds, 1)
		end
		table.insert(data.PurchaseIds, purchaseId)
		sendResult(player, itemId, true, result)
	end

	local saved = DataService.SaveAndWait(player, function(lastSaved)
		return lastSaved ~= nil
			and lastSaved.PurchaseIds ~= nil
			and table.find(lastSaved.PurchaseIds, purchaseId) ~= nil
	end)
	return if saved then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

----------------------------------------------------------------------------------------------------------------
-- Requests from players

-- "Buy this with Robux": shows Roblox's prompt. Items without an ID yet are granted straight away in Studio
-- (so the shop can be tested) and refused in a live game.
local function onRequestPurchase(player: Player, itemId: unknown)
	if typeof(itemId) ~= "string" or throttled(player) then
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		return
	end

	local pass = Shop.PassesById[itemId]
	if pass then
		if (ownedPasses[player] or {})[pass.id] then
			sendResult(player, pass.id, false, "You already own this!")
		elseif pass.gamePassId ~= 0 then
			MarketplaceService:PromptGamePassPurchase(player, pass.gamePassId)
		elseif RunService:IsStudio() then
			grantPass(player, pass.id)
			sendResult(player, pass.id, true, `{pass.title} unlocked! (Studio test purchase)`)
		else
			sendResult(player, pass.id, false, "This isn't for sale yet.")
		end
		return
	end

	local productId, reward
	if itemId == Shop.PEN_UPGRADE_ID then
		local next = Shop.PenLevels[data.PenLevel + 1]
		if next == nil then
			sendResult(player, itemId, false, "Your pen is already the biggest it can be!")
			return
		end
		productId, reward = next.productId, { kind = "PenLevel" }
	elseif itemId == Shop.STAMINA_DOUBLING_ID then
		local next = Shop.StaminaDoublings[data.StaminaMultiplier * 2]
		if next == nil then
			sendResult(player, itemId, false, "Your Max Stamina is already doubled all the way!")
			return
		end
		productId, reward = next.productId, { kind = "StaminaDoubling" }
	else
		local product = Shop.ProductsById[itemId]
		if product == nil then
			return
		end
		productId, reward = product.productId, product.grant
	end

	if productId ~= 0 then
		MarketplaceService:PromptProductPurchase(player, productId)
	elseif RunService:IsStudio() then
		sendResult(player, itemId, true, grant(player, reward) .. " (Studio test purchase)")
	else
		sendResult(player, itemId, false, "This isn't for sale yet.")
	end
end

-- "Buy this with dollars". Only the next pen level has a dollar price for now; it is the same purchase as the
-- green button at the front of the pen.
local function onBuyWithDollars(player: Player, itemId: unknown)
	if itemId ~= Shop.PEN_UPGRADE_ID or throttled(player) then
		return
	end
	if DataService.GetData(player) == nil then
		return
	end
	local ok, message = InventoryService.UpgradePen(player)
	pushState(player)
	sendResult(player, itemId, ok, message)
end

local function onGetShopState(player: Player)
	local state = stateOf(player)
	state.luck = luckBoosts
	return state
end

----------------------------------------------------------------------------------------------------------------
-- Players

local function checkPasses(player: Player)
	for _, pass in Shop.Passes do
		if pass.gamePassId ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.gamePassId)
			end)
			if ok and owns and ownedPasses[player] then
				grantPass(player, pass.id)
			end
		end
	end
end

local function onDataLoaded(player: Player, _data)
	ownedPasses[player] = {}
	pushState(player)
	checkPasses(player)
end

local function onPassPurchaseFinished(player: Player, gamePassId: number, purchased: boolean)
	if not purchased then
		return
	end
	for _, pass in Shop.Passes do
		if pass.gamePassId ~= 0 and pass.gamePassId == gamePassId then
			grantPass(player, pass.id)
			sendResult(player, pass.id, true, `{pass.title} unlocked!`)
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- For other services

function ShopService.OwnsPass(player: Player, passId: string): boolean
	local owned = ownedPasses[player]
	return owned ~= nil and owned[passId] == true
end

-- The luck boosts running in this server (Shared/LuckBoost).
function ShopService.GetLuckBoosts(): { LuckBoost.Boost }
	return luckBoosts
end

-- Sends a player their dollars, pen level and passes again, after something outside the shop changed them (the
-- admin panel).
function ShopService.RefreshPlayer(player: Player)
	pushState(player)
end

-- Starts a luck boost without a purchase (the admin panel), announced as coming from `by`.
function ShopService.AddLuck(multiplier: number, duration: number, by: Player?)
	addLuck(multiplier, duration, by)
end

-- Ends every luck boost running now (the admin panel).
function ShopService.ClearLuck()
	table.clear(luckBoosts)
	applyLuck()
	Net.LuckChanged:FireAllClients(luckBoosts)
end

function ShopService.Init()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchaseFinished)

	Net.RequestPurchase.OnServerEvent:Connect(onRequestPurchase)
	Net.BuyWithDollars.OnServerEvent:Connect(onBuyWithDollars)
	Net.GetShopState.OnServerInvoke = onGetShopState

	DataService.OnLoaded(onDataLoaded)
	Players.PlayerRemoving:Connect(function(player)
		ownedPasses[player] = nil
		lastRequestAt[player] = nil
	end)
end

function ShopService.Start()
	-- Ends boosts on time; the next strongest boost (if any) takes over.
	while true do
		task.wait(1)
		local before = #luckBoosts
		LuckBoost.prune(luckBoosts, now())
		applyLuck()
		if #luckBoosts ~= before then
			Net.LuckChanged:FireAllClients(luckBoosts)
		end
	end
end

return ShopService
