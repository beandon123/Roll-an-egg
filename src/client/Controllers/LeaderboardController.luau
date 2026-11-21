-- The player's own line under each leaderboard board beside the start zone ("YOUR STAMINA  1.2K  #12"): the boards
-- themselves are the same for everyone (LeaderboardService), but each device draws this strip for its own player,
-- from the score and rank the server keeps on their Player (Config/Leaderboards' attributes).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local Leaderboards = Load.shared("Config", "Leaderboards")

local localPlayer = Players.LocalPlayer

local LeaderboardController = {}

-- Seconds between looks for boards that have streamed in, and between refreshes of the numbers.
local REFRESH_INTERVAL = 1
local PIXELS_PER_STUD = 25

local INK = Color3.fromRGB(22, 18, 44)
local SOFT = Color3.fromRGB(200, 194, 236)

type Strip = { gui: SurfaceGui, value: TextLabel, rank: TextLabel }

-- boardId -> the strip drawn for it.
local strips: { [string]: Strip } = {}
local sinceRefresh = math.huge

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function label(parent: Instance, props): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = props.name
	text.BackgroundTransparency = 1
	text.Font = props.font
	text.Text = props.text or ""
	text.TextColor3 = props.color
	text.TextSize = props.size
	text.TextXAlignment = props.align or Enum.TextXAlignment.Center
	text.Position = props.position
	text.Size = props.box
	if props.stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Color = INK
		stroke.Thickness = props.stroke
		stroke.Parent = text
	end
	text.Parent = parent
	return text
end

-- Draws the player's line on a board's strip (the part under its screen).
local function buildStrip(board: Leaderboards.Board, part: BasePart, playerGui: Instance): Strip
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard" .. board.id
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Adornee = part
	gui.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Name = "Line"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = INK
	frame.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = rgb(board.light)
	stroke.Thickness = 4
	stroke.Parent = frame

	label(frame, {
		name = "Yours",
		text = board.yours,
		font = Enum.Font.GothamBold,
		color = SOFT,
		size = 20,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(18, 0),
		box = UDim2.new(0.45, -18, 1, 0),
	})
	local value = label(frame, {
		name = "Value",
		font = Enum.Font.LuckiestGuy,
		color = rgb(board.light),
		size = 34,
		stroke = 2.5,
		align = Enum.TextXAlignment.Right,
		position = UDim2.new(0.45, 0, 0, 2),
		box = UDim2.fromScale(0.33, 1),
	})
	local rank = label(frame, {
		name = "Rank",
		font = Enum.Font.LuckiestGuy,
		color = Color3.new(1, 1, 1),
		size = 30,
		stroke = 2.5,
		position = UDim2.new(0.78, 0, 0, 2),
		box = UDim2.new(0.22, -10, 1, 0),
	})

	gui.Parent = playerGui
	return { gui = gui, value = value, rank = rank }
end

-- Draws strips for boards that have arrived, and writes the player's numbers on them.
local function refresh()
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Leaderboards")
	if playerGui == nil or folder == nil then
		return
	end
	for _, board in Leaderboards.active() do
		local strip = strips[board.id]
		if strip == nil or strip.gui.Parent == nil or strip.gui.Adornee == nil or strip.gui.Adornee.Parent == nil then
			local model = folder:FindFirstChild(board.id)
			local part = model and model:FindFirstChild("YouStrip")
			if part and part:IsA("BasePart") then
				if strip then
					strip.gui:Destroy()
				end
				strip = buildStrip(board, part, playerGui)
				strips[board.id] = strip
			else
				continue
			end
		end
		local score = localPlayer:GetAttribute(Leaderboards.scoreAttribute(board))
		local rank = localPlayer:GetAttribute(Leaderboards.rankAttribute(board))
		local current = strip :: Strip
		current.value.Text = Leaderboards.formatScore(board, if typeof(score) == "number" then score else 0)
		current.rank.Text = Leaderboards.formatRank(if typeof(rank) == "number" then rank else 0)
	end
end

function LeaderboardController.Init()
	RunService.Heartbeat:Connect(function(deltaTime: number)
		sinceRefresh += deltaTime
		if sinceRefresh >= REFRESH_INTERVAL then
			sinceRefresh = 0
			refresh()
		end
	end)
end

return LeaderboardController
