-- The local player's side of the hub stations: the Trails shop, the Sell stall, and the fuse machine.
--
-- Each station has a ProximityPrompt (made by the server's map builder) tagged with the station's key. Using it
-- opens that station's panel; walking away closes it. The panels' buttons come here, and this asks the server,
-- which decides every purchase and sale. This only asks and shows the answer.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local Load = require(script.Parent.Parent.Load)
local HubLayout = Load.shared("HubLayout")
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")
local Trails = Load.shared("Config", "Trails")
local Zones = Load.shared("Config", "Zones")

local UiState = require(script.Parent.Parent.Ui.UiState)

local peek = UiState.Fusion.peek
local localPlayer = Players.LocalPlayer

local GOOD_COLOR = Color3.fromRGB(120, 235, 130)
local BAD_COLOR = Color3.fromRGB(255, 110, 110)
local COIN_COLOR = Color3.fromRGB(255, 215, 80)

local ShopController = {}

local function closePanel()
	UiState.openPanel:set("")
end

local function onPromptTriggered(prompt: ProximityPrompt)
	local station = prompt:GetAttribute("Station")
	if typeof(station) == "string" and HubLayout.STATIONS[station] then
		UiState.openPanel:set(station)
	end
end

-- Closes the open panel once the player has walked away from its station.
local function closeWhenFar()
	local open = peek(UiState.openPanel)
	local station = HubLayout.STATIONS[open]
	if station == nil then
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		closePanel()
		return
	end
	local dx, dz = root.Position.X - station.x, root.Position.Z - station.z
	if dx * dx + dz * dz > HubLayout.STATION_CLOSE_DISTANCE ^ 2 then
		closePanel()
	end
end

-- Calls a server function without letting a failed call break the button that made it.
local function ask(remote: RemoteFunction, ...): (boolean, ...any)
	local results = table.pack(pcall(remote.InvokeServer, remote, ...))
	if not results[1] then
		warn(`[ShopController] {remote.Name} failed: {results[2]}`)
		return false
	end
	return true, table.unpack(results, 2, results.n)
end

local function buyTrail(trailId: string)
	local trail = Trails.ById[trailId]
	if trail == nil then
		return
	end
	task.spawn(function()
		local answered, ok, result = ask(Net.BuyTrail, trailId)
		if not answered then
			return
		end
		if ok then
			if result == "BoughtAndEquipped" then
				UiState.showToast(`{trail.name} equipped! Stamina x{trail.stamina}`, GOOD_COLOR)
			else
				UiState.showToast(`Bought the {trail.name}!`, GOOD_COLOR)
			end
		elseif result == "NotEnoughCoins" then
			UiState.showToast("Not enough coins", BAD_COLOR)
		elseif result == "Owned" then
			UiState.showToast("You already own that trail", BAD_COLOR)
		end
	end)
end

local function equipTrail(trailId: string)
	local trail = Trails.ById[trailId]
	if trail == nil or peek(UiState.trailEquipped) == trailId then
		return
	end
	task.spawn(function()
		local answered, ok = ask(Net.EquipTrail, trailId)
		if answered and ok then
			UiState.showToast(`{trail.name} equipped! Stamina x{trail.stamina}`, GOOD_COLOR)
		end
	end)
end

local function sellEggs(zone: number, rarity: string, count: number)
	task.spawn(function()
		local answered, sold, coins = ask(Net.SellEggs, zone, rarity, count)
		if not answered or typeof(sold) ~= "number" or sold <= 0 then
			return
		end
		local zoneInfo = Zones.List[zone]
		local what = `{rarity} {if zoneInfo then zoneInfo.name .. " " else ""}egg{if sold == 1 then "" else "s"}`
		UiState.showToast(`Sold {sold} {what} for {NumberFormat.abbreviate(coins)} coins`, COIN_COLOR)
	end)
end

function ShopController.Init()
	UiState.actions.buyTrail = buyTrail
	UiState.actions.equipTrail = equipTrail
	UiState.actions.sellEggs = sellEggs
	UiState.actions.closePanel = closePanel

	Net.CoinsChanged.OnClientEvent:Connect(function(coins: unknown)
		if typeof(coins) == "number" then
			UiState.coins:set(coins)
		end
	end)
	Net.InventoryUpdated.OnClientEvent:Connect(UiState.setInventory)
	Net.TrailsUpdated.OnClientEvent:Connect(UiState.setTrails)

	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	RunService.Heartbeat:Connect(closeWhenFar)
	-- A new character (after dying or resetting) starts back at the spawn, away from every station.
	localPlayer.CharacterAdded:Connect(closePanel)
end

return ShopController
