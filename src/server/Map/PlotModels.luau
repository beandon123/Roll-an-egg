-- Builds the players' plots at the hub out of parts, laid out by Shared/Plots: a grass pen with a fence and a gate
-- onto the plaza, a sign over the gate, and straw nests, each with a countdown board above it (filled in on each
-- client by NestController). PlotService builds them and keeps them up to date.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Plots = require(Shared.Plots)
local Runway = require(Shared.Runway)

local PlotModels = {}

-- Eggs in nests are shown smaller than on the runway, to fit: a nest-sized egg of every rarity.
PlotModels.NEST_EGG = { radius = 2.2, halfLength = 2.9 }
local NEST_SIZE = 9
local FENCE_HEIGHT = 4
local POST_GAP = 12

local GRASS = Color3.fromRGB(110, 184, 84)
local DIRT = Color3.fromRGB(150, 116, 78)
local WOOD = Color3.fromRGB(150, 104, 62)
local STRAW = Color3.fromRGB(222, 186, 98)

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
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = "Free plot"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Parent = gui
end

-- A straw nest with a countdown board above it.
function PlotModels.buildNest(parent: Instance, index: number, slot: number): Model
	local x, z = Plots.nestPoint(index, slot)
	local base = CFrame.new(x, Runway.BASE_Y, z)
	local nest = Instance.new("Model")
	nest.Name = "Nest" .. slot
	nest:SetAttribute("Slot", slot)
	nest:SetAttribute("EggKind", "")
	nest.Parent = parent

	local bed =
		newPart(nest, "Bed", Vector3.new(NEST_SIZE - 2, 0.8, NEST_SIZE - 2), base * CFrame.new(0, 0.4, 0), STRAW)
	bed.Material = Enum.Material.Fabric
	nest.PrimaryPart = bed
	-- A ring of straw round the edge.
	for step = 0, 7 do
		local angle = step / 8 * math.pi * 2
		local tuft = newPart(
			nest,
			"Straw",
			Vector3.new(3.6, 1.6, 1.4),
			base * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.9, -NEST_SIZE / 2 + 0.7) * CFrame.Angles(-0.25, 0, 0),
			if step % 2 == 0 then STRAW else Color3.fromRGB(196, 158, 80)
		)
		tuft.Material = Enum.Material.Fabric
		tuft.CanCollide = false
	end

	-- The countdown: a name and a bar, filled in by each client.
	local holder = newPart(nest, "Board", Vector3.one, base * CFrame.new(0, 10, 0), Color3.new(1, 1, 1))
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Countdown"
	billboard.Size = UDim2.fromScale(9, 3)
	billboard.MaxDistance = 140
	billboard.LightInfluence = 0
	billboard.Parent = holder
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.45)
	title.Font = Enum.Font.FredokaOne
	title.Text = "Empty nest"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0
	title.TextScaled = true
	title.Parent = billboard
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0.05, 0.52)
	bar.Size = UDim2.fromScale(0.9, 0.4)
	bar.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
	bar.Visible = false
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
	local time = Instance.new("TextLabel")
	time.Name = "Time"
	time.BackgroundTransparency = 1
	time.Size = UDim2.fromScale(1, 1)
	time.ZIndex = 2
	time.Font = Enum.Font.GothamBold
	time.Text = ""
	time.TextColor3 = Color3.new(1, 1, 1)
	time.TextStrokeTransparency = 0.3
	time.TextScaled = true
	time.Parent = bar
	return nest
end

local function buildFence(parent: Instance, index: number)
	local side = Plots.sideOf(index)
	local _, centerZ = Plots.center(index)
	local y = Runway.BASE_Y
	local inner = side * Plots.PLAZA_HALF_WIDTH
	local outer = side * (Plots.PLAZA_HALF_WIDTH + Plots.WIDTH)
	local front, back = centerZ - Plots.DEPTH / 2, centerZ + Plots.DEPTH / 2

	-- A straight run of fence from a to b (points on the ground), posts every POST_GAP studs.
	local function run(ax: number, az: number, bx: number, bz: number)
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

	run(outer, front, outer, back)
	run(inner, front, outer, front)
	run(inner, back, outer, back)
	-- The plaza side, with the gate in the middle.
	run(inner, front, inner, centerZ - Plots.GATE_HALF_WIDTH)
	run(inner, centerZ + Plots.GATE_HALF_WIDTH, inner, back)
end

function PlotModels.buildPlot(parent: Instance, index: number): Model
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("Index", index)
	model:SetAttribute("Owner", 0)
	model:SetAttribute("OwnerName", "")
	model:SetAttribute("Pets", "")
	model.Parent = parent

	local side = Plots.sideOf(index)
	local x, z = Plots.center(index)
	local floor = newPart(
		model,
		"Floor",
		Vector3.new(Plots.WIDTH, 0.4, Plots.DEPTH),
		CFrame.new(x, Runway.BASE_Y + 0.2, z),
		GRASS
	)
	floor.Material = Enum.Material.Grass
	model.PrimaryPart = floor
	-- Trodden earth where the nests are.
	local nestX = select(1, Plots.point(index, 24, 0))
	local patch = newPart(
		model,
		"NestPatch",
		Vector3.new(46, 0.1, Plots.DEPTH - 8),
		CFrame.new(nestX, Runway.BASE_Y + 0.42, z),
		DIRT
	)
	patch.Material = Enum.Material.Ground
	patch.CanCollide = false

	local fence = Instance.new("Folder")
	fence.Name = "Fence"
	fence.Parent = model
	buildFence(fence, index)

	-- The owner's name over the gate.
	local gateX = side * Plots.PLAZA_HALF_WIDTH
	for _, along in { -1, 1 } do
		local post = newPart(
			model,
			"GatePost",
			Vector3.new(1.6, 14, 1.6),
			CFrame.new(gateX, Runway.BASE_Y + 7, z + along * (Plots.GATE_HALF_WIDTH + 0.8)),
			WOOD
		)
		post.Material = Enum.Material.Wood
	end
	local sign = newPart(
		model,
		"Sign",
		Vector3.new(0.6, 4, Plots.GATE_HALF_WIDTH * 2 + 6),
		CFrame.new(gateX, Runway.BASE_Y + 12, z),
		Color3.fromRGB(96, 66, 40)
	)
	sign.Material = Enum.Material.WoodPlanks
	addSignGui(sign, Enum.NormalId.Left)
	addSignGui(sign, Enum.NormalId.Right)

	local nests = Instance.new("Folder")
	nests.Name = "Nests"
	nests.Parent = model
	for slot = 1, Plots.START_NESTS do
		PlotModels.buildNest(nests, index, slot)
	end
	return model
end

return PlotModels
