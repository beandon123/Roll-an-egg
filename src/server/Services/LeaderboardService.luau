-- The leaderboard board beside the start zone: the all-time top egg claimers.
--
-- Scores come from a global OrderedDataStore, so the board shows the best players across every server. Players in
-- this server are merged in with their live score, so a claim shows up without waiting for the store. Where the
-- store cannot be reached (Studio without API access, an outage), the board ranks the players in this server.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local NumberFormat = require(Shared.NumberFormat)
local Runway = require(Shared.Runway)

local DataService = require(script.Parent.DataService)

-- Bump the version only to wipe the board.
local STORE_NAME = "TopEggClaimers_v1"
local ROWS = 10
-- Seconds between reads of the global store, and between redraws with live scores.
local FETCH_INTERVAL = 60
local REDRAW_INTERVAL = 5

local BOARD_WIDTH = 30
local BOARD_HEIGHT = 24
local POST_HEIGHT = 5
local PIXELS_PER_STUD = 25

local INK = Color3.fromRGB(46, 30, 22)
local CREAM = Color3.fromRGB(255, 246, 228)
local YOLK = Color3.fromRGB(255, 196, 40)
local MEDALS = {
	Color3.fromRGB(255, 205, 50),
	Color3.fromRGB(205, 215, 228),
	Color3.fromRGB(226, 150, 90),
}

local LeaderboardService = {}

local store: OrderedDataStore? = nil
-- userId -> score, from the last successful read of the store.
local globalScores: { [number]: number } = {}
-- What each player's score was when last written to the store.
local lastWritten: { [Player]: number } = {}
local names: { [number]: string } = {}
local rows: { { frame: Frame, rank: TextLabel, medal: Frame, face: ImageLabel, name: TextLabel, score: TextLabel } } =
	{}
local emptyLabel: TextLabel

local function scoreOf(player: Player): number?
	local data = DataService.GetData(player)
	return if data then data.Stats.EggsClaimed else nil
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.Name
	end
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok and typeof(name) == "string" then name else "Player"
	return names[userId]
end

----------------------------------------------------------------------------------------------------------------
-- The board

local function label(parent: Instance, props): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = props.font or Enum.Font.FredokaOne
	text.TextColor3 = props.color or INK
	text.TextScaled = true
	text.TextXAlignment = props.align or Enum.TextXAlignment.Center
	text.Text = props.text or ""
	text.Position = props.position
	text.Size = props.size
	text.Name = props.name or "Label"
	text.Parent = parent
	return text
end

local function corner(parent: Instance, scale: number)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(scale, 0)
	round.Parent = parent
end

local function buildRow(list: Frame, index: number)
	local frame = Instance.new("Frame")
	frame.Name = "Row" .. index
	frame.LayoutOrder = index
	frame.Size = UDim2.new(1, 0, 1 / ROWS, -4)
	frame.BackgroundColor3 = if index % 2 == 0 then Color3.fromRGB(255, 238, 205) else CREAM
	frame.Visible = false
	frame.Parent = list
	corner(frame, 0.3)

	local medal = Instance.new("Frame")
	medal.Name = "Medal"
	medal.AnchorPoint = Vector2.new(0, 0.5)
	medal.Position = UDim2.new(0, 6, 0.5, 0)
	medal.Size = UDim2.fromScale(0.08, 0.8)
	medal.BackgroundColor3 = MEDALS[index] or Color3.fromRGB(240, 222, 190)
	medal.Parent = frame
	corner(medal, 0.5)
	local rank = label(medal, {
		name = "Rank",
		text = tostring(index),
		position = UDim2.fromScale(0.1, 0.1),
		size = UDim2.fromScale(0.8, 0.8),
	})

	local face = Instance.new("ImageLabel")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0, 0.5)
	face.Position = UDim2.fromScale(0.11, 0.5)
	face.Size = UDim2.fromScale(0.08, 0.86)
	face.BackgroundColor3 = Color3.fromRGB(255, 226, 170)
	face.Parent = frame
	corner(face, 0.5)

	local name = label(frame, {
		name = "PlayerName",
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromScale(0.22, 0.14),
		size = UDim2.fromScale(0.5, 0.72),
	})
	local score = label(frame, {
		name = "Score",
		align = Enum.TextXAlignment.Right,
		color = Color3.fromRGB(214, 110, 20),
		position = UDim2.fromScale(0.7, 0.14),
		size = UDim2.fromScale(0.27, 0.72),
	})

	rows[index] = { frame = frame, rank = rank, medal = medal, face = face, name = name, score = score }
end

local function buildBoard(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Leaderboard"

	local function part(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Anchored = true
		piece.Size = size
		piece.CFrame = cframe
		piece.Color = color
		piece.Material = Enum.Material.SmoothPlastic
		piece.TopSurface = Enum.SurfaceType.Smooth
		piece.BottomSurface = Enum.SurfaceType.Smooth
		piece.Parent = model
		return piece
	end

	-- Left of the start zone (as seen from the hub), turned to face the spawn.
	local base = Vector3.new(Runway.WIDTH / 2 + 18, Runway.BASE_Y, -12)
	local center = base + Vector3.new(0, POST_HEIGHT + BOARD_HEIGHT / 2, 0)
	local facing = CFrame.lookAt(center, Vector3.new(0, center.Y, -Runway.HUB_LENGTH / 2))

	local frame = part(
		"Frame",
		Vector3.new(BOARD_WIDTH + 2, BOARD_HEIGHT + 2, 1.6),
		facing * CFrame.new(0, 0, 0.5),
		Color3.fromRGB(122, 74, 44)
	)
	local board = part("Board", Vector3.new(BOARD_WIDTH, BOARD_HEIGHT, 1), facing, CREAM)
	model.PrimaryPart = board
	for _, side in { -1, 1 } do
		part(
			"Post",
			Vector3.new(2, POST_HEIGHT + 2, 2),
			facing * CFrame.new(side * (BOARD_WIDTH / 2 - 3), -(BOARD_HEIGHT + POST_HEIGHT) / 2, 0.5),
			frame.Color
		)
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Parent = board

	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Size = UDim2.fromScale(1, 0.17)
	banner.BackgroundColor3 = YOLK
	banner.Parent = gui
	local title = label(banner, {
		name = "Title",
		text = "TOP EGG CLAIMERS",
		font = Enum.Font.LuckiestGuy,
		color = Color3.new(1, 1, 1),
		position = UDim2.fromScale(0.05, 0.08),
		size = UDim2.fromScale(0.9, 0.62),
	})
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 5
	stroke.Parent = title
	label(banner, {
		name = "Subtitle",
		text = "All servers  •  all time",
		font = Enum.Font.GothamBold,
		position = UDim2.fromScale(0.05, 0.7),
		size = UDim2.fromScale(0.9, 0.24),
	})

	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.new(0, 14, 0.19, 0)
	list.Size = UDim2.new(1, -28, 0.79, 0)
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	for index = 1, ROWS do
		buildRow(list, index)
	end

	emptyLabel = label(gui, {
		name = "Empty",
		text = "No eggs claimed yet. Be the first!",
		position = UDim2.fromScale(0.1, 0.45),
		size = UDim2.fromScale(0.8, 0.1),
	})

	model.Parent = parent
end

----------------------------------------------------------------------------------------------------------------
-- Scores

-- The top scores right now: the last read of the store, with live scores of players in this server on top.
local function ranking(): { { userId: number, score: number } }
	local merged = table.clone(globalScores)
	for _, player in Players:GetPlayers() do
		local score = scoreOf(player)
		if score then
			merged[player.UserId] = math.max(merged[player.UserId] or 0, score)
		end
	end
	local list = {}
	for userId, score in merged do
		if score > 0 then
			table.insert(list, { userId = userId, score = score })
		end
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.userId < b.userId
	end)
	while #list > ROWS do
		table.remove(list)
	end
	return list
end

local function draw()
	local list = ranking()
	emptyLabel.Visible = #list == 0
	for index, row in rows do
		local entry = list[index]
		row.frame.Visible = entry ~= nil
		if entry then
			row.name.Text = nameOf(entry.userId)
			row.score.Text = NumberFormat.abbreviate(entry.score) .. " 🥚"
			row.face.Image = `rbxthumb://type=AvatarHeadShot&id={entry.userId}&w=150&h=150`
		end
	end
end

-- Writes changed scores of players in this server, then reads the global top list.
local function fetch()
	if store == nil then
		return
	end
	for _, player in Players:GetPlayers() do
		local score = scoreOf(player)
		if score and score > (lastWritten[player] or 0) then
			local ok = pcall(function()
				(store :: OrderedDataStore):SetAsync(tostring(player.UserId), score)
			end)
			if ok then
				lastWritten[player] = score
			end
		end
	end

	local ok, page = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, ROWS):GetCurrentPage()
	end)
	if ok and typeof(page) == "table" then
		local scores = {}
		for _, entry in page do
			local userId = tonumber(entry.key)
			if userId then
				scores[userId] = entry.value
			end
		end
		globalScores = scores
	end
end

-- Redraws the board now (other services and tests can call this after a score changes).
function LeaderboardService.Refresh()
	draw()
end

function LeaderboardService.Init()
	local map = Workspace:FindFirstChild("Map") or Workspace
	buildBoard(map)

	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(STORE_NAME)
	end)
	store = if ok then result else nil

	Players.PlayerRemoving:Connect(function(player)
		lastWritten[player] = nil
	end)
	draw()
end

function LeaderboardService.Start()
	local sinceFetch = math.huge
	while true do
		if sinceFetch >= FETCH_INTERVAL then
			sinceFetch = 0
			fetch()
		end
		draw()
		task.wait(REDRAW_INTERVAL)
		sinceFetch += REDRAW_INTERVAL
	end
end

return LeaderboardService
