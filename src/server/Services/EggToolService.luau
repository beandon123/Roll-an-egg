-- Puts each player's claimed eggs in their Roblox inventory (the Backpack, shown in the hotbar at the bottom of the
-- screen): one Tool for each kind of egg they hold, named for the egg and how many of it they have ("Acorn Egg x3").
-- Holding one shows the egg in the player's hand; clicking (or tapping) a spot in their own pen puts one down there
-- to hatch (the client's EggToolController asks; InventoryService and Logic/Hatchery decide).
--
-- The tools are only a view of the saved eggs (the player's data, Logic/Hatchery's Eggs list), rebuilt from it
-- whenever it changes (InventoryService calls Sync) and whenever the player respawns, since Roblox gives them a new,
-- empty Backpack then.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EggModels = require(Shared.EggModels)
local EggRig = require(Shared.EggRig)

local DataService = require(script.Parent.DataService)
local Hatchery = require(script.Parent.Parent.Logic.Hatchery)

local EggToolService = {}

-- The attribute that marks a Tool as an egg, holding the egg's kind (its design name, such as "MossStag").
EggToolService.KIND_ATTRIBUTE = "EggKind"
-- How many of that egg the player holds.
EggToolService.COUNT_ATTRIBUTE = "EggCount"

-- The egg in the player's hand: a little smaller than in the pen.
local HELD_EGG = { radius = 1.1, halfLength = 1.1 * 1.3 }
local TOOL_TIP = "Click a spot in your pen to put it down"

-- One finished tool per kind of egg, copied for every player who holds one.
local templates: { [string]: Tool } = {}

local function eggName(kind: string): string
	local about = EggModels.describe(kind)
	return if about then about.name else "Egg"
end

-- The name shown in the hotbar: the egg, and how many there are if more than one.
function EggToolService.toolName(kind: string, count: number): string
	local name = eggName(kind)
	return if count > 1 then `{name} x{count}` else name
end

-- A tool holding one kind of egg. The egg's own model (Shared/EggRig) is the handle, welded together and standing
-- on end in the player's hand.
local function buildTemplate(kind: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = eggName(kind)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = TOOL_TIP
	tool:SetAttribute(EggToolService.KIND_ATTRIBUTE, kind)
	tool.Grip = CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.pi / 2)

	local egg = EggRig.build(kind, HELD_EGG)
	local handle = egg:FindFirstChild("Root") :: BasePart
	handle.Name = "Handle"
	handle.Anchored = false
	handle.Massless = true
	handle.CanCollide = false
	handle.Parent = tool
	for _, part in egg:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.Parent = handle
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
		end
	end
	egg:Destroy()
	return tool
end

local function newTool(kind: string): Tool
	local template = templates[kind]
	if template == nil then
		template = buildTemplate(kind)
		templates[kind] = template
	end
	return template:Clone()
end

-- Every egg tool the player has, by kind: in the Backpack, or in their hand. Spare copies of a kind are removed.
local function toolsOf(player: Player): { [string]: Tool }
	local found: { [string]: Tool } = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				local kind = child:GetAttribute(EggToolService.KIND_ATTRIBUTE)
				if child:IsA("Tool") and typeof(kind) == "string" then
					if found[kind] then
						child:Destroy()
					else
						found[kind] = child
					end
				end
			end
		end
	end
	return found
end

-- Makes the player's egg tools match the eggs they hold: one per kind, named with the count; tools for eggs they no
-- longer have are taken away. New tools go to the end of the hotbar, in the order the eggs were claimed.
function EggToolService.Sync(player: Player)
	local data = DataService.GetData(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if data == nil or backpack == nil then
		return
	end
	local counts: { [string]: number } = {}
	local order: { string } = {}
	for _, item in data.Eggs do
		local kind = Hatchery.eggKindOf(item)
		if counts[kind] == nil then
			counts[kind] = 0
			table.insert(order, kind)
		end
		counts[kind] += 1
	end

	local tools = toolsOf(player)
	for kind, tool in tools do
		if counts[kind] == nil then
			tool:Destroy()
		end
	end
	for _, kind in order do
		local tool = tools[kind]
		if tool == nil then
			tool = newTool(kind)
			tool.Parent = backpack
		end
		local count = counts[kind]
		tool.Name = EggToolService.toolName(kind, count)
		tool:SetAttribute(EggToolService.COUNT_ATTRIBUTE, count)
	end
end

function EggToolService.Init()
	DataService.OnLoaded(function(player)
		-- Roblox gives a respawning player a new, empty Backpack: fill it again once it is there.
		player.ChildAdded:Connect(function(child)
			if child:IsA("Backpack") then
				task.defer(EggToolService.Sync, player)
			end
		end)
		player.CharacterAdded:Connect(function()
			task.defer(EggToolService.Sync, player)
		end)
		EggToolService.Sync(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, tool in toolsOf(player) do
			tool:Destroy()
		end
	end)
end

return EggToolService
