-- Animates the obstacles that go off now and then (sand geysers, lava vents, giant clams), in time with
-- Shared/Obstacles, so what a rider sees is exactly when the server counts a hit:
--     Warning  the vent puffs smoke or sand, or the clam's shell trembles: get out of the way
--     Active   the geyser or lava shoots up, or the clam snaps shut
--     Idle     harmless
-- The map is built by the server (MapService); each timed obstacle is a Model tagged with its ObstacleId, holding
-- the parts named in Map/ObstacleModels. With streaming on, obstacles far away may not be loaded, so the list is
-- refreshed now and then.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local Obstacles = Load.shared("Obstacles")

local ObstacleController = {}

-- How the clam's lid sits: open when idle, shut when active.
local LID_OPEN = math.rad(60)
-- How long a burst takes to shoot up to full height, in seconds.
local BURST_RISE = 0.18
local REFRESH_INTERVAL = 1

type Animated = {
	model: Model,
	obstacle: any,
	burst: BasePart?,
	burstHeight: number,
	burstBase: CFrame?,
	light: PointLight?,
	warn: ParticleEmitter?,
	lid: BasePart?,
	shell: BasePart?,
}

local animated: { [Model]: Animated } = {}
local lastRefresh = -math.huge

local function track(model: Model)
	if animated[model] or model:GetAttribute("Timed") ~= true then
		return
	end
	local obstacle = Obstacles.get(model:GetAttribute("ObstacleId") :: number)
	if obstacle == nil then
		return
	end
	local burst = model:FindFirstChild("Burst") :: BasePart?
	local vent = model:FindFirstChild("Vent")
	local warnPoint = vent and vent:FindFirstChild("WarnPoint")
	animated[model] = {
		model = model,
		obstacle = obstacle,
		burst = burst,
		-- A burst column stands on the ground; it is a cylinder lying along its X axis, turned upright.
		burstHeight = if burst then burst.Size.X else 0,
		burstBase = if burst then burst.CFrame * CFrame.new(-burst.Size.X / 2, 0, 0) else nil,
		light = if burst then burst:FindFirstChildOfClass("PointLight") else nil,
		warn = if warnPoint then warnPoint:FindFirstChildOfClass("ParticleEmitter") else nil,
		lid = model:FindFirstChild("Lid") :: BasePart?,
		shell = model:FindFirstChild("Shell") :: BasePart?,
	}
end

local function refresh()
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Obstacles")
	for model in animated do
		if model.Parent == nil then
			animated[model] = nil
		end
	end
	if folder then
		for _, model in folder:GetChildren() do
			if model:IsA("Model") then
				track(model)
			end
		end
	end
end

local function animate(entry: Animated, now: number)
	local obstacle = entry.obstacle
	local activity = Obstacles.activity(obstacle, now)

	if entry.warn then
		entry.warn.Enabled = activity == "Warning"
	end

	local burst = entry.burst
	if burst and entry.burstBase then
		if activity == "Active" then
			-- Shoots up fast, then holds until it drops away.
			local timing = obstacle.timing
			local into = ((now + obstacle.offset) % timing.period) - timing.warn
			local height = entry.burstHeight * math.clamp(into / BURST_RISE, 0.05, 1)
			burst.Size = Vector3.new(height, burst.Size.Y, burst.Size.Z)
			burst.CFrame = entry.burstBase * CFrame.new(height / 2, 0, 0)
			burst.Transparency = 0.1
		else
			burst.Transparency = 1
		end
		if entry.light then
			entry.light.Enabled = activity == "Active"
		end
	end

	local lid, shell = entry.lid, entry.shell
	if lid and shell then
		local angle = LID_OPEN
		if activity == "Active" then
			angle = 0
		elseif activity == "Warning" then
			angle = LID_OPEN - math.rad(10) + math.sin(now * 40) * math.rad(6)
		end
		local hinge = shell.CFrame * CFrame.new(0, shell.Size.Y / 2, shell.Size.Z / 2)
		lid.CFrame = hinge * CFrame.Angles(angle, 0, 0) * CFrame.new(0, lid.Size.Y / 2, -lid.Size.Z / 2)
	end
end

local function update()
	local now = Workspace:GetServerTimeNow()
	if os.clock() - lastRefresh >= REFRESH_INTERVAL then
		lastRefresh = os.clock()
		refresh()
	end
	for _, entry in animated do
		animate(entry, now)
	end
end

function ObstacleController.Start()
	RunService.RenderStepped:Connect(update)
end

return ObstacleController
