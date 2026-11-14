-- The players' plots at the hub: each player gets one when they join and gives it back when they leave.
--
-- A plot (Workspace.Map.Plots.PlotN, built by Map/PlotModels, laid out by Shared/Plots) is one open pen: its size
-- follows the owner's pen level, eggs they put down hatch where they lie, and their pets roam it. Attributes:
--     Plot  Owner (UserId, 0 when free), OwnerName, PenLevel, Pets (the pets roaming the pen, as "Kind:Variant"
--           pairs, comma-separated; the clients draw and walk them: PenController)
--     Egg   Uid, EggKind, EggName, Rarity, PlacedAt, Bonus, and HatchedAt once it hatches (it is removed a moment
--           later, so clients can burst it open)
-- The green button at the front of each pen buys its owner a bigger pen (InventoryService does the buying).
--
-- Players appear at their own plot when they respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local EggModels = require(Shared.EggModels)
local PetWorth = require(Shared.PetWorth)
local Plots = require(Shared.Plots)
local Runway = require(Shared.Runway)

local DataService = require(script.Parent.DataService)
local Hatchery = require(script.Parent.Parent.Logic.Hatchery)
local PlotModels = require(script.Parent.Parent.Map.PlotModels)

local PlotService = {}

-- How long a hatched egg stays (bursting open on clients) before it is removed.
local HATCH_LINGER = 1

local plotFolder: Folder
local plotModels: { [number]: Model } = {}
local owners: { [number]: Player } = {}
local plotOf: { [Player]: number } = {}
local upgradeHandler: ((Player) -> ())? = nil

-- Puts the plot's eggs in step with the owner's hatching eggs: new ones are built, gone ones removed (unless they
-- have just hatched, and are bursting open).
local function syncEggs(plot: Model, index: number, hatching: { Hatchery.Incubating })
	local folder = plot:FindFirstChild("Eggs") :: Folder
	local wanted = {}
	for _, entry in hatching do
		wanted[entry.uid] = entry
	end
	for _, model in folder:GetChildren() do
		local uid = model:GetAttribute("Uid")
		local entry = wanted[uid]
		if entry then
			model:SetAttribute("Bonus", entry.bonus)
			wanted[uid] = nil
		elseif model:GetAttribute("HatchedAt") == nil then
			model:Destroy()
		end
	end
	for _, entry in wanted do
		local model = PlotModels.buildEgg(folder, index, entry)
		local about = EggModels.describe(entry.kind)
		model:SetAttribute("EggName", if about then about.name else "Egg")
	end
end

-- Brings a player's plot up to date with their data: pen size, eggs, the pets in the pen, the button's price.
function PlotService.Refresh(player: Player)
	local index = plotOf[player]
	local data = DataService.GetData(player)
	if index == nil or data == nil then
		return
	end
	local plot = plotModels[index]
	if plot:GetAttribute("PenLevel") ~= data.PenLevel then
		PlotModels.sizePen(plot, index, data.PenLevel)
	end
	PlotModels.setButton(plot, data.PenLevel, PetWorth.penUpgradeCost(data.PenLevel))
	syncEggs(plot, index, data.Hatching)
	local pets = {}
	for _, pet in Hatchery.penPets(data) do
		table.insert(pets, `{pet.kind}:{pet.variant}`)
	end
	plot:SetAttribute("Pets", table.concat(pets, ","))
end

-- Marks an egg as hatched so clients burst it open, and removes it a moment later.
function PlotService.Hatched(player: Player, uid: string, time: number)
	local index = plotOf[player]
	if index == nil then
		return
	end
	local folder = plotModels[index]:FindFirstChild("Eggs")
	local model = folder and folder:FindFirstChild("Egg_" .. uid)
	if model then
		model:SetAttribute("HatchedAt", time)
		task.delay(HATCH_LINGER, function()
			model:Destroy()
		end)
	end
end

-- The plot a player owns (its index), or nil.
function PlotService.GetPlot(player: Player): number?
	return plotOf[player]
end

-- Where the player is standing in their own pen, as (inward, along), or nil if they are not in it.
function PlotService.SpotInPen(player: Player): (number?, number?)
	local index = plotOf[player]
	local data = DataService.GetData(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if index == nil or data == nil or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	local position = root.CFrame.Position
	local inward, along = Plots.toLocal(index, position.X, position.Z)
	if not Plots.inPen(data.PenLevel, inward, along, 0) or position.Y > Runway.BASE_Y + 12 then
		return nil, nil
	end
	-- A little in front of the player, so the egg is not under their feet.
	local ahead = root.CFrame.LookVector * 4
	local aheadInward, aheadAlong = Plots.toLocal(index, position.X + ahead.X, position.Z + ahead.Z)
	return aheadInward, aheadAlong
end

-- Who presses the green button is handed to `handler` (InventoryService buys the upgrade).
function PlotService.OnUpgradePressed(handler: (Player) -> ())
	upgradeHandler = handler
end

local function spawnAtPlot(player: Player, character: Model)
	local index = plotOf[player]
	local root = character:FindFirstChild("HumanoidRootPart")
	if index == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	local x, z = Plots.spawnPoint(index)
	local position = Vector3.new(x, Runway.BASE_Y + 3, z)
	-- Facing up the plaza, towards the runway.
	root.CFrame = CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

local function assign(player: Player)
	if plotOf[player] then
		return
	end
	for index = 1, Plots.COUNT do
		if owners[index] == nil then
			owners[index] = player
			plotOf[player] = index
			local model = plotModels[index]
			local name = if player.DisplayName ~= "" then player.DisplayName else player.Name
			model:SetAttribute("Owner", player.UserId)
			model:SetAttribute("OwnerName", name)
			PlotModels.signText(model:FindFirstChild("Sign") :: BasePart, `{name}'s Pen`)
			PlotService.Refresh(player)
			break
		end
	end

	player.CharacterAdded:Connect(function(character)
		-- Once Roblox has finished placing the new character at the spawn.
		task.defer(spawnAtPlot, player, character)
	end)
	-- A character that has only just appeared at the hub's spawn goes to the plot too.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and root and root:IsA("BasePart") then
		local spawnPoint = Vector3.new(0, Runway.BASE_Y, -Runway.HUB_LENGTH / 2)
		if (root.Position - spawnPoint).Magnitude < 30 then
			spawnAtPlot(player, character)
		end
	end
end

local function release(player: Player)
	local index = plotOf[player]
	if index == nil then
		return
	end
	plotOf[player] = nil
	owners[index] = nil
	local model = plotModels[index]
	model:SetAttribute("Owner", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("Pets", "")
	PlotModels.signText(model:FindFirstChild("Sign") :: BasePart, "Free plot")
	PlotModels.sizePen(model, index, 1)
	PlotModels.setButton(model, 1, PetWorth.penUpgradeCost(1))
	for _, egg in (model:FindFirstChild("Eggs") :: Folder):GetChildren() do
		egg:Destroy()
	end
end

function PlotService.Init()
	local map = Workspace:FindFirstChild("Map")
	assert(map, "PlotService needs MapService to have built the map first")
	plotFolder = Instance.new("Folder")
	plotFolder.Name = "Plots"
	plotFolder.Parent = map
	for index = 1, Plots.COUNT do
		local plot = PlotModels.buildPlot(plotFolder, index)
		plotModels[index] = plot
		local prompt = (plot :: any).UpgradeButton.Pad.Upgrade :: ProximityPrompt
		prompt.Triggered:Connect(function(player: Player)
			-- Only the plot's owner can buy its upgrade.
			if owners[index] == player and upgradeHandler then
				upgradeHandler(player)
			end
		end)
	end

	DataService.OnLoaded(function(player)
		assign(player)
	end)
	Players.PlayerRemoving:Connect(release)
end

return PlotService
