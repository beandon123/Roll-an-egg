-- The players' plots at the hub: each player gets one when they join and gives it back when they leave.
--
-- A plot (Workspace.Map.Plots.PlotN, laid out by Shared/Plots) is a fenced pen with a gate onto the plaza, the
-- owner's name over the gate, and nests. Each nest shows the egg hatching in it, with a countdown above it that
-- every client keeps up to date from the nest's attributes (see the client's NestController):
--     Plot   Owner (UserId, 0 when free), OwnerName, Pets (the pet kinds roaming the pen, comma-separated)
--     Nest   Slot, EggKind, EggName, Rarity, PlacedAt, Bonus (empty EggKind: no egg), HatchedAt (the last hatch)
-- The pets themselves are drawn and walked round by each client (PenController); the server only says which.
--
-- Players appear at their own plot when they respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local EggModels = require(Shared.EggModels)
local EggRig = require(Shared.EggRig)
local Plots = require(Shared.Plots)
local Runway = require(Shared.Runway)

local DataService = require(script.Parent.DataService)
local Hatchery = require(script.Parent.Parent.Logic.Hatchery)
local PlotModels = require(script.Parent.Parent.Map.PlotModels)

local PlotService = {}

local NEST_EGG = PlotModels.NEST_EGG

local plotFolder: Folder
local plotModels: { [number]: Model } = {}
local owners: { [number]: Player } = {}
local plotOf: { [Player]: number } = {}

-- Shows a nest's egg (or none), and sets the attributes its countdown is drawn from.
local function showNestEgg(nest: Model, entry: Hatchery.Nest?)
	local old = nest:FindFirstChild("Egg")
	local kind = if entry then entry.kind else ""
	if old and old:GetAttribute("Uid") ~= (entry and entry.uid) then
		old:Destroy()
		old = nil
	end
	nest:SetAttribute("EggKind", kind)
	if entry == nil then
		return
	end
	nest:SetAttribute("Rarity", entry.rarity)
	nest:SetAttribute("PlacedAt", entry.placedAt)
	nest:SetAttribute("Bonus", entry.bonus)
	local about = EggModels.describe(entry.kind)
	nest:SetAttribute("EggName", if about then about.name else "Egg")
	if old == nil then
		local egg = EggRig.build(entry.kind, NEST_EGG)
		egg:SetAttribute("Uid", entry.uid)
		local bed = nest.PrimaryPart :: BasePart
		-- The egg model lies with its top towards +X; stand it on end in the nest.
		local root = egg.PrimaryPart :: BasePart
		root.CFrame = bed.CFrame * CFrame.new(0, 0.4 + NEST_EGG.halfLength, 0) * CFrame.Angles(0, 0, math.pi / 2)
		egg.Parent = nest
	end
end

-- Brings a player's plot up to date with their data: nests, eggs in them, and the pets in the pen.
function PlotService.Refresh(player: Player)
	local index = plotOf[player]
	local data = DataService.GetData(player)
	if index == nil or data == nil then
		return
	end
	local model = plotModels[index]
	local nests = model:FindFirstChild("Nests") :: Folder
	-- Build any nests bought since.
	for slot = 1, Hatchery.nestCount(data) do
		if nests:FindFirstChild("Nest" .. slot) == nil then
			PlotModels.buildNest(nests, index, slot)
		end
	end
	local bySlot = {}
	for _, entry in data.Nests do
		bySlot[entry.slot] = entry
	end
	for _, nest in nests:GetChildren() do
		if nest:IsA("Model") then
			showNestEgg(nest, bySlot[nest:GetAttribute("Slot")])
		end
	end
	local kinds = {}
	for _, pet in Hatchery.penPets(data, Plots.PEN_CAPACITY) do
		table.insert(kinds, pet.kind)
	end
	model:SetAttribute("Pets", table.concat(kinds, ","))
end

-- Marks the moment a nest's egg hatched, so clients can burst it open.
function PlotService.Hatched(player: Player, slot: number, time: number)
	local index = plotOf[player]
	if index == nil then
		return
	end
	local nests = plotModels[index]:FindFirstChild("Nests")
	local nest = nests and nests:FindFirstChild("Nest" .. slot)
	if nest then
		nest:SetAttribute("HatchedAt", time)
	end
end

-- The plot a player owns (its index), or nil.
function PlotService.GetPlot(player: Player): number?
	return plotOf[player]
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
	local nests = model:FindFirstChild("Nests") :: Folder
	for _, nest in nests:GetChildren() do
		local slot = nest:GetAttribute("Slot")
		if typeof(slot) == "number" and slot > Plots.START_NESTS then
			nest:Destroy()
		elseif nest:IsA("Model") then
			showNestEgg(nest, nil)
		end
	end
end

function PlotService.Init()
	local map = Workspace:FindFirstChild("Map")
	assert(map, "PlotService needs MapService to have built the map first")
	plotFolder = Instance.new("Folder")
	plotFolder.Name = "Plots"
	plotFolder.Parent = map
	for index = 1, Plots.COUNT do
		plotModels[index] = PlotModels.buildPlot(plotFolder, index)
	end

	DataService.OnLoaded(function(player)
		assign(player)
	end)
	Players.PlayerRemoving:Connect(release)
end

return PlotService
