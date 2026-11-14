-- Builds the players' plots at the hub out of parts, laid out by Shared/Plots. Each plot is:
--     Land           the plot's whole room, rough grass, enough for the biggest pen
--     Pen            the pen at its current size: a grass floor and a fence, with a gate onto the plaza
--     Sign           the owner's name over the gate
--     UpgradeButton  a big green button in front of the pen, beside the gate, that buys a bigger pen (a
--                    ProximityPrompt), with its price above it
--     Eggs           the eggs hatching in the pen, each on a little straw bed with a countdown board above it
--                    (filled in on each client by HatchController)
-- PlotService builds them and keeps them up to date.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EggRig = require(Shared.EggRig)
local NumberFormat = require(Shared.NumberFormat)
local PetWorth = require(Shared.PetWorth)
local Plots = require(Shared.Plots)
local Runway = require(Shared.Runway)

local PlotModels = {}

-- Eggs in the pen are shown smaller than on the runway: an egg of every rarity at the same, pen-friendly size.
PlotModels.PEN_EGG = { radius = 2.2, halfLength = 2.9 }
local BED_SIZE = 7
local FENCE_HEIGHT = 4
local POST_GAP = 12

local GRASS = Color3.fromRGB(110, 184, 84)
local ROUGH = Color3.fromRGB(128, 160, 96)
local WOOD = Color3.fromRGB(150, 104, 62)
local STRAW = Color3.fromRGB(222, 186, 98)
local BUTTON_GREEN = Color3.fromRGB(60, 220, 90)

local function newPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Parent = parent
	return part
end

local function textLabel(parent: Instance, name: string, text: string, size: UDim2, position: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Parent = parent
	return label
end

function PlotModels.signText(sign: BasePart, text: string)
	for _, gui in sign:GetChildren() do
		if gui:IsA("SurfaceGui") then
			(gui:FindFirstChildOfClass("TextLabel") :: TextLabel).Text = text
		end
	end
end

local function addSignGui(sign: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Parent = sign
	textLabel(gui, "Text", "Free plot", UDim2.fromScale(1, 1), UDim2.new())
end

-- A world CFrame on the ground at a point of a plot.
local function ground(index: number, inward: number, along: number, height: number?): CFrame
	local x, z = Plots.point(index, inward, along)
	return CFrame.new(x, Runway.BASE_Y + 0.4 + (height or 0), z)
end

----------------------------------------------------------------------------------------------------------------
-- The pen

local function buildFence(parent: Instance, index: number, width: number)
	local y = Runway.BASE_Y + 0.4
	local half = Plots.DEPTH / 2

	-- A straight run of fence between two points of the plot, posts every POST_GAP studs.
	local function run(inwardA: number, alongA: number, inwardB: number, alongB: number)
		local ax, az = Plots.point(index, inwardA, alongA)
		local bx, bz = Plots.point(index, inwardB, alongB)
		local from, to = Vector3.new(ax, y, az), Vector3.new(bx, y, bz)
		local length = (to - from).Magnitude
		if length < 0.5 then
			return
		end
		local middle = (from + to) / 2
		for _, height in { 1.6, 3.2 } do
			local rail = newPart(
				parent,
				"Rail",
				Vector3.new(0.5, 0.5, length),
				CFrame.lookAt(middle + Vector3.new(0, height, 0), to + Vector3.new(0, height, 0)),
				WOOD
			)
			rail.Material = Enum.Material.Wood
		end
		local posts = math.max(1, math.floor(length / POST_GAP))
		for step = 0, posts do
			local point = from:Lerp(to, step / posts)
			local post = newPart(
				parent,
				"Post",
				Vector3.new(1, FENCE_HEIGHT, 1),
				CFrame.new(point + Vector3.new(0, FENCE_HEIGHT / 2, 0)),
				WOOD
			)
			post.Material = Enum.Material.Wood
		end
	end

	run(width, -half, width, half)
	run(0, -half, width, -half)
	run(0, half, width, half)
	-- The plaza side, with the gate in the middle.
	run(0, -half, 0, -Plots.GATE_HALF_WIDTH)
	run(0, Plots.GATE_HALF_WIDTH, 0, half)
end

-- (Re)builds a plot's pen at the size of a level: its floor and fence.
function PlotModels.sizePen(plot: Model, index: number, level: number)
	local old = plot:FindFirstChild("Pen")
	if old then
		old:Destroy()
	end
	local pen = Instance.new("Folder")
	pen.Name = "Pen"
	pen.Parent = plot
	local width = Plots.penWidth(level)
	-- A shade above the plot's rough grass, so the two never flicker.
	local floor = newPart(pen, "Floor", Vector3.new(width, 0.2, Plots.DEPTH), ground(index, width / 2, 0, 0), GRASS)
	floor.Material = Enum.Material.Grass
	buildFence(pen, index, width)
	plot:SetAttribute("PenLevel", level)
end

----------------------------------------------------------------------------------------------------------------
-- The upgrade button

local function buildButton(plot: Model, index: number)
	local spot = Plots.BUTTON_SPOT
	local button = Instance.new("Model")
	button.Name = "UpgradeButton"
	button.Parent = plot
	local base = newPart(button, "Base", Vector3.new(1.4, 10, 10), CFrame.new(), WOOD)
	base.Shape = Enum.PartType.Cylinder
	base.CFrame = ground(index, spot[1], spot[2], 0.7) * CFrame.Angles(0, 0, math.pi / 2)
	local pad = newPart(button, "Pad", Vector3.new(1.2, 8, 8), CFrame.new(), BUTTON_GREEN)
	pad.Shape = Enum.PartType.Cylinder
	pad.Material = Enum.Material.Neon
	pad.CFrame = ground(index, spot[1], spot[2], 1.6) * CFrame.Angles(0, 0, math.pi / 2)
	button.PrimaryPart = pad

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Upgrade"
	prompt.ActionText = "Buy a bigger pen"
	prompt.ObjectText = ""
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	-- The price, floating over the button.
	local holder = newPart(button, "Board", Vector3.one, ground(index, spot[1], spot[2], 7), Color3.new())
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Price"
	billboard.Size = UDim2.fromScale(10, 3.4)
	billboard.MaxDistance = 120
	billboard.LightInfluence = 0
	billboard.Parent = holder
	textLabel(billboard, "Title", "BIGGER PEN", UDim2.fromScale(1, 0.5), UDim2.new())
	local cost = textLabel(billboard, "Cost", "", UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.52))
	cost.TextColor3 = BUTTON_GREEN
end

-- Shows the price of the next pen level on a plot's button, or that the pen is as big as it gets.
function PlotModels.setButton(plot: Model, level: number, cost: number?)
	local button = plot:FindFirstChild("UpgradeButton")
	if button == nil then
		return
	end
	local billboard = (button :: any).Board.Price
	local prompt = (button :: any).Pad.Upgrade :: ProximityPrompt
	-- Each client shows the prompt only on its own plot, and not once the pen is as big as it gets.
	plot:SetAttribute("Maxed", cost == nil)
	if cost then
		billboard.Cost.Text = `${NumberFormat.abbreviate(cost)}  (level {level + 1})`
		prompt.ObjectText = `${NumberFormat.abbreviate(cost)}`
	else
		billboard.Cost.Text = "Biggest size!"
		prompt.ObjectText = ""
	end
end

----------------------------------------------------------------------------------------------------------------
-- Eggs

-- An egg hatching in the pen: the egg standing on a little straw bed, with its countdown board above.
function PlotModels.buildEgg(parent: Instance, index: number, entry): Model
	local model = Instance.new("Model")
	model.Name = "Egg_" .. entry.uid
	model:SetAttribute("Uid", entry.uid)
	model:SetAttribute("EggKind", entry.kind)
	model:SetAttribute("Rarity", entry.rarity)
	model:SetAttribute("PlacedAt", entry.placedAt)
	model:SetAttribute("Bonus", entry.bonus)
	model.Parent = parent
	local base = ground(index, entry.inward, entry.along)

	local bed = newPart(model, "Bed", Vector3.new(BED_SIZE - 2, 0.6, BED_SIZE - 2), base * CFrame.new(0, 0.3, 0), STRAW)
	bed.Material = Enum.Material.Fabric
	model.PrimaryPart = bed
	for step = 0, 5 do
		local angle = step / 6 * math.pi * 2
		local tuft = newPart(
			model,
			"Straw",
			Vector3.new(2.8, 1.2, 1.1),
			base * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.7, -BED_SIZE / 2 + 0.6) * CFrame.Angles(-0.25, 0, 0),
			if step % 2 == 0 then STRAW else Color3.fromRGB(196, 158, 80)
		)
		tuft.Material = Enum.Material.Fabric
		tuft.CanCollide = false
	end

	local spec = PlotModels.PEN_EGG
	local egg = EggRig.build(entry.kind, spec)
	-- The egg model lies with its top towards +X; stand it on end.
	local root = egg.PrimaryPart :: BasePart
	local move = base
		* CFrame.new(0, 0.6 + spec.halfLength, 0)
		* CFrame.Angles(0, 0, math.pi / 2)
		* root.CFrame:Inverse()
	for _, part in egg:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = move * part.CFrame
		end
	end
	egg.Parent = model

	-- The countdown: a name and a bar, filled in by each client.
	local holder = newPart(model, "Board", Vector3.one, base * CFrame.new(0, 10, 0), Color3.new(1, 1, 1))
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Countdown"
	billboard.Size = UDim2.fromScale(9, 3)
	billboard.MaxDistance = 140
	billboard.LightInfluence = 0
	billboard.Parent = holder
	textLabel(billboard, "Title", "", UDim2.fromScale(1, 0.45), UDim2.new())
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0.05, 0.52)
	bar.Size = UDim2.fromScale(0.9, 0.4)
	bar.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
	bar.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 230, 120)
	fill.Parent = bar
	corner:Clone().Parent = fill
	local time = textLabel(bar, "Time", "", UDim2.fromScale(1, 1), UDim2.new())
	time.ZIndex = 2
	time.Font = Enum.Font.GothamBold
	return model
end

----------------------------------------------------------------------------------------------------------------
-- The plot

function PlotModels.buildPlot(parent: Instance, index: number): Model
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("Index", index)
	model:SetAttribute("Owner", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("Pets", "")
	model.Parent = parent

	local land = newPart(
		model,
		"Land",
		Vector3.new(Plots.WIDTH, 0.4, Plots.DEPTH),
		ground(index, Plots.WIDTH / 2, 0, -0.2),
		ROUGH
	)
	land.Material = Enum.Material.Grass
	model.PrimaryPart = land
	PlotModels.sizePen(model, index, 1)

	-- The owner's name over the gate.
	for _, along in { -1, 1 } do
		local post = newPart(
			model,
			"GatePost",
			Vector3.new(1.6, 14, 1.6),
			ground(index, 0, along * (Plots.GATE_HALF_WIDTH + 0.8), 7),
			WOOD
		)
		post.Material = Enum.Material.Wood
	end
	local sign = newPart(
		model,
		"Sign",
		Vector3.new(0.6, 4, Plots.GATE_HALF_WIDTH * 2 + 6),
		ground(index, 0, 0, 11.6),
		Color3.fromRGB(96, 66, 40)
	)
	sign.Material = Enum.Material.WoodPlanks
	addSignGui(sign, Enum.NormalId.Left)
	addSignGui(sign, Enum.NormalId.Right)

	buildButton(model, index)
	PlotModels.setButton(model, 1, PetWorth.penUpgradeCost(1))

	local eggs = Instance.new("Folder")
	eggs.Name = "Eggs"
	eggs.Parent = model
	return model
end

return PlotModels
