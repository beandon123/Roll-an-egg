-- Keeps the countdown board over every egg hatching in the pens at the hub up to date, worked out on this device
-- from the egg's attributes (set by the server's PlotService) and the shared clock, and bursts an egg open when it
-- hatches.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local HatchMath = Load.shared("HatchMath")
local NumberFormat = Load.shared("NumberFormat")

local Panels = require(script.Parent.Parent.Ui.Panels)

local HatchController = {}

-- Countdowns refresh this many times a second.
local UPDATE_RATE = 5
-- A hatch seen this long after it happened (a player arriving late) is not burst open.
local BURST_WINDOW = 3

local lastUpdateAt = -math.huge
local burst: { [Instance]: boolean } = {}

-- Bits of shell and sparkles flying out of an egg's bed.
local function burstOpen(egg: Model)
	local bed = egg:FindFirstChild("Bed")
	if bed == nil or not bed:IsA("BasePart") then
		return
	end
	local holder = Instance.new("Part")
	holder.Name = "HatchBurst"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(2, 1, 2)
	holder.CFrame = bed.CFrame * CFrame.new(0, 2.5, 0)
	holder.Parent = Workspace
	local shells = Instance.new("ParticleEmitter")
	shells.Color = ColorSequence.new(Color3.fromRGB(250, 246, 232))
	shells.Size = NumberSequence.new(0.6, 0.2)
	shells.Speed = NumberRange.new(12, 22)
	shells.SpreadAngle = Vector2.new(50, 50)
	shells.Acceleration = Vector3.new(0, -40, 0)
	shells.Lifetime = NumberRange.new(0.8, 1.2)
	shells.Rotation = NumberRange.new(0, 360)
	shells.RotSpeed = NumberRange.new(-200, 200)
	shells.Enabled = false
	shells.Parent = holder
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 236, 140))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.9, 0)
	sparkles.Speed = NumberRange.new(6, 14)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Lifetime = NumberRange.new(0.6, 1)
	sparkles.Enabled = false
	sparkles.Parent = holder
	shells:Emit(30)
	sparkles:Emit(40)
	task.delay(2, function()
		holder:Destroy()
	end)
end

local function updateEgg(egg: Model, now: number)
	local hatchedAt = egg:GetAttribute("HatchedAt")
	if typeof(hatchedAt) == "number" then
		if not burst[egg] and now - hatchedAt < BURST_WINDOW then
			burst[egg] = true
			burstOpen(egg)
		end
		return
	end
	local board = egg:FindFirstChild("Board")
	local billboard = board and board:FindFirstChild("Countdown")
	if billboard == nil or not billboard:IsA("BillboardGui") then
		return
	end
	local title = billboard:FindFirstChild("Title") :: TextLabel
	local bar = billboard:FindFirstChild("Bar") :: Frame
	local fill = bar:FindFirstChild("Fill") :: Frame
	local time = bar:FindFirstChild("Time") :: TextLabel
	local rarity = (egg:GetAttribute("Rarity") or "Common") :: string
	local placedAt = (egg:GetAttribute("PlacedAt") or now) :: number
	local bonus = (egg:GetAttribute("Bonus") or 0) :: number
	title.Text = (egg:GetAttribute("EggName") or "Egg") :: string
	title.TextColor3 = Panels.rarityColor(rarity)
	fill.BackgroundColor3 = Panels.rarityColor(rarity)
	fill.Size = UDim2.fromScale(HatchMath.progress(placedAt, bonus, rarity, now), 1)
	local left = HatchMath.timeLeft(placedAt, bonus, rarity, now)
	time.Text = if left > 0 then NumberFormat.duration(left) else "Hatching!"
end

local function update()
	if os.clock() - lastUpdateAt < 1 / UPDATE_RATE then
		return
	end
	lastUpdateAt = os.clock()
	for egg in burst do
		if egg.Parent == nil then
			burst[egg] = nil
		end
	end
	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if plots == nil then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for _, plot in plots:GetChildren() do
		local eggs = plot:FindFirstChild("Eggs")
		if eggs then
			for _, egg in eggs:GetChildren() do
				if egg:IsA("Model") then
					updateEgg(egg, now)
				end
			end
		end
	end
end

function HatchController.Start()
	RunService.RenderStepped:Connect(update)
end

return HatchController
