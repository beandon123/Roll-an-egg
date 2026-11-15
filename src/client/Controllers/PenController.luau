-- Draws the pets in every pen at the hub and walks them round. Which pets a pen holds comes from its plot's "Pets"
-- attribute ("Kind:Variant" pairs, set by the server's PlotService) and how big it is from "PenLevel"; the models
-- and their wandering exist only on this device, so the server never moves pets about. PetAnimationController
-- animates them (they live in Workspace.PenPets).
--
-- Each pet strolls to a random spot in the pen, stops for a while, and picks another. Pens far from the camera
-- are left empty, so only nearby pets cost anything.
--
-- Also shows the green "bigger pen" button's prompt on this player's own plot only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local PetAnimations = Load.shared("PetAnimations")
local PetModels = Load.shared("PetModels")
local PetRig = Load.shared("PetRig")
local Plots = Load.shared("Plots")
local Runway = Load.shared("Runway")

local PenController = {}

-- Pens closer than SHOW_DISTANCE to the camera get their pets; ones further than HIDE_DISTANCE lose them.
local SHOW_DISTANCE = 300
local HIDE_DISTANCE = 360
-- The top of a plot's floor.
local FLOOR_Y = Runway.BASE_Y + 0.4

type Roamer = {
	model: Model,
	root: BasePart,
	design: any,
	x: number,
	z: number,
	targetX: number,
	targetZ: number,
	facing: Vector3,
	speed: number,
	restUntil: number,
	area: { number },
	groundOffset: number,
	idleMove: string,
	walkMove: string,
}

type Pen = { key: string, roamers: { Roamer } }

local folder: Folder
local pens: { [number]: Pen } = {}
local templates: { [string]: Model } = {}
local random = Random.new()
local clock = 0

local function template(kind: string, variant: string): Model?
	local key = kind .. ":" .. variant
	local cached = templates[key]
	if cached == nil then
		local built = PetRig.build(kind, variant)
		if built == nil then
			return nil
		end
		templates[key] = built
		cached = built
	end
	return cached
end

local function pickTarget(roamer: Roamer)
	local area = roamer.area
	roamer.targetX = random:NextNumber(area[1], area[2])
	roamer.targetZ = random:NextNumber(area[3], area[4])
end

local function place(roamer: Roamer)
	local position = Vector3.new(roamer.x, FLOOR_Y + roamer.groundOffset, roamer.z)
	roamer.root.CFrame = CFrame.lookAt(position, position + roamer.facing)
end

local function clearPen(index: number)
	local pen = pens[index]
	if pen then
		for _, roamer in pen.roamers do
			roamer.model:Destroy()
		end
		pens[index] = nil
	end
end

local function fillPen(index: number, key: string, pets: string, level: number)
	clearPen(index)
	local pen: Pen = { key = key, roamers = {} }
	pens[index] = pen
	for entry in string.gmatch(pets, "[^,]+") do
		local kind, variant = string.match(entry, "^([^:]+):?(.*)$")
		kind = kind or entry
		variant = if variant and variant ~= "" then variant else "Normal"
		local design = PetModels.get(kind)
		local source = template(kind, variant)
		if design and source then
			local model = source:Clone()
			local root = model.PrimaryPart :: BasePart
			-- Keep the whole pet inside the fence.
			local reach = math.max(root.Size.X, root.Size.Z) / 2 + 1
			local x0, x1, z0, z1 = Plots.roamArea(index, level, reach)
			local moves = PetAnimations.movesOf(design.skeleton)
			local walkMove = PetAnimations.defaultMove(design.skeleton, design.gait)
			local roamer: Roamer = {
				model = model,
				root = root,
				design = design,
				x = random:NextNumber(x0, x1),
				z = random:NextNumber(z0, z1),
				targetX = 0,
				targetZ = 0,
				facing = Vector3.new(0, 0, -1),
				-- Bigger pets stride faster.
				speed = math.clamp(root.Size.Z * 0.35, 4, 9),
				restUntil = clock + random:NextNumber(0, 3),
				area = { x0, x1, z0, z1 },
				groundOffset = (model:GetAttribute("GroundOffset") or 0) :: number,
				idleMove = if table.find(moves, "Idle") then "Idle" else walkMove,
				walkMove = walkMove,
			}
			pickTarget(roamer)
			place(roamer)
			model:SetAttribute("Move", roamer.idleMove)
			model.Parent = folder
			table.insert(pen.roamers, roamer)
		end
	end
end

local function stepRoamer(roamer: Roamer, deltaTime: number)
	if clock < roamer.restUntil then
		return
	end
	local dx, dz = roamer.targetX - roamer.x, roamer.targetZ - roamer.z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance < 0.5 then
		-- Arrived: rest a while, then head somewhere else.
		roamer.restUntil = clock + random:NextNumber(1.5, 4.5)
		roamer.model:SetAttribute("Move", roamer.idleMove)
		pickTarget(roamer)
		return
	end
	if roamer.model:GetAttribute("Move") ~= roamer.walkMove then
		roamer.model:SetAttribute("Move", roamer.walkMove)
	end
	local step = math.min(distance, roamer.speed * deltaTime)
	roamer.x += dx / distance * step
	roamer.z += dz / distance * step
	roamer.facing = Vector3.new(dx / distance, 0, dz / distance)
	place(roamer)
end

-- The green button's prompt works only for the plot's owner, so it is only shown to them.
local function showPrompt(plot: Instance)
	local button = plot:FindFirstChild("UpgradeButton")
	local pad = button and button:FindFirstChild("Pad")
	local prompt = pad and pad:FindFirstChild("Upgrade")
	if prompt and prompt:IsA("ProximityPrompt") then
		local mine = plot:GetAttribute("Owner") == Players.LocalPlayer.UserId
		prompt.Enabled = mine and plot:GetAttribute("Maxed") ~= true
	end
end

local function update(deltaTime: number)
	clock += deltaTime
	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	local camera = Workspace.CurrentCamera
	if plots == nil then
		return
	end
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for _, plot in plots:GetChildren() do
		local index = plot:GetAttribute("Index")
		if typeof(index) == "number" then
			showPrompt(plot)
			local pets = (plot:GetAttribute("Pets") or "") :: string
			local level = (plot:GetAttribute("PenLevel") or 1) :: number
			local key = `{level}|{pets}`
			local x, z = Plots.center(index)
			local distance = (Vector3.new(x, Runway.BASE_Y, z) - eye).Magnitude
			local pen = pens[index]
			local near = distance < (if pen then HIDE_DISTANCE else SHOW_DISTANCE)
			if not near or pets == "" then
				clearPen(index)
			else
				if pen == nil or pen.key ~= key then
					fillPen(index, key, pets, level)
					pen = pens[index]
				end
				for _, roamer in (pen :: Pen).roamers do
					stepRoamer(roamer, deltaTime)
				end
			end
		end
	end
end

function PenController.Init()
	folder = Instance.new("Folder")
	folder.Name = "PenPets"
	folder.Parent = Workspace
end

function PenController.Start()
	RunService.RenderStepped:Connect(update)
end

return PenController
