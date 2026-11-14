-- The local player's side of the hub stations: the Trails stall, the Sell stall, and the fuse machine.
--
-- Each station has a ProximityPrompt (made by the server's map builder, Map/Stations) tagged with the station's
-- key. Using it opens that station's panel in the middle of the screen; walking away closes it. The panels' buttons
-- come here, and this asks the server, which decides every purchase and sale. This only asks and shows the answer.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local Load = require(script.Parent.Parent.Load)
local EggModels = Load.shared("EggModels")
local HubLayout = Load.shared("HubLayout")
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")
local Trails = Load.shared("Config", "Trails")

local UiState = require(script.Parent.Parent.Ui.UiState)

local peek = UiState.Fusion.peek
local localPlayer = Players.LocalPlayer

local GOOD_COLOR = Color3.fromRGB(120, 235, 130)
local BAD_COLOR = Color3.fromRGB(255, 110, 110)

local StationController = {}

-- Closes the open panel if it is a station's.
local function closeStation()
	if HubLayout.STATIONS[peek(UiState.openPanel) or ""] then
		UiState.openPanel:set(nil)
	end
end

local function onPromptTriggered(prompt: ProximityPrompt)
	local station = prompt:GetAttribute("Station")
	if typeof(station) == "string" and HubLayout.STATIONS[station] then
		UiState.openPanel:set(station)
		UiState.panel:set("None")
	end
end

-- Closes a station's panel once the player has walked away from the station.
local function closeWhenFar()
	local station = HubLayout.STATIONS[peek(UiState.openPanel) or ""]
	if station == nil then
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		closeStation()
		return
	end
	local position = root.CFrame.Position
	local dx, dz = position.X - station.x, position.Z - station.z
	if dx * dx + dz * dz > HubLayout.STATION_CLOSE_DISTANCE ^ 2 then
		closeStation()
	end
end

-- Calls a server function without letting a failed call break the button that made it.
local function ask(remote: RemoteFunction, ...): (boolean, ...any)
	local results = table.pack(pcall(remote.InvokeServer, remote, ...))
	if not results[1] then
		warn(`[StationController] {remote.Name} failed: {results[2]}`)
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
		elseif result == "NotEnoughDollars" then
			UiState.showToast("Not enough dollars", BAD_COLOR)
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

local function sellEggs(kind: string, count: number)
	task.spawn(function()
		local answered, sold, dollars = ask(Net.SellEggs, kind, count)
		if not answered or typeof(sold) ~= "number" or sold <= 0 then
			return
		end
		local about = EggModels.describe(kind)
		local name = if about then about.name else "Egg"
		local what = if sold == 1 then name else `{sold} {name}s`
		UiState.showToast(`Sold {what} for ${NumberFormat.abbreviate(dollars)}`, GOOD_COLOR)
	end)
end

function StationController.Init()
	UiState.actions.buyTrail = buyTrail
	UiState.actions.equipTrail = equipTrail
	UiState.actions.sellEggs = sellEggs

	Net.TrailsUpdated.OnClientEvent:Connect(UiState.setTrails)

	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	RunService.Heartbeat:Connect(closeWhenFar)
	-- A new character (after dying or resetting) starts back at its plot, away from every station.
	localPlayer.CharacterAdded:Connect(closeStation)
end

function StationController.Start()
	local ok, trails = pcall(function()
		return Net.GetTrails:InvokeServer()
	end)
	if ok and typeof(trails) == "table" then
		UiState.setTrails(trails.owned, trails.equipped)
	end
end

return StationController
