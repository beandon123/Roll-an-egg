-- The leaderboard boards beside the start zone (Config/Leaderboards): Top Stamina, Top Collectors and Top Earners.
--
-- Each board ranks the best players across every server, from its own global OrderedDataStore. Players in this
-- server are merged in with their live score, so a change shows up without waiting for the store (Logic/Rankings).
-- Where a store cannot be reached (Studio without API access, an outage), a board ranks the players in this server.
--
-- The boards are built from parts in the game's blocky style: a stone plinth, a white rim between two banded
-- pillars topped with glowing lamps, and a big egg on top bearing the board's emblem (a lightning bolt, a paw, a
-- coin). The screen is drawn like the game's panels: a glossy title band over a deep indigo body, one row a player,
-- gold, silver and bronze for the top three. Each player's own score and rank go on a strip under the screen, drawn
-- by their own device (LeaderboardController) from attributes kept on their Player.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local HubLayout = require(Shared.HubLayout)
local Leaderboards = require(Shared.Config.Leaderboards)
local Runway = require(Shared.Runway)

local Hatchery = require(script.Parent.Parent.Logic.Hatchery)
local Rankings = require(script.Parent.Parent.Logic.Rankings)
local Stats = require(script.Parent.Parent.Logic.Stats)

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)

local PIXELS_PER_STUD = 25
-- The screen and the strip under it, in studs.
local SCREEN_WIDTH = 21
local SCREEN_HEIGHT = 25
local STRIP_HEIGHT = 3
-- How high the plinth stands, and the rim on it.
local PLINTH_HEIGHT = 3
local RIM_HEIGHT = 30

local INK = Color3.fromRGB(22, 18, 44)
local WHITE = Color3.fromRGB(255, 255, 255)
local SOFT = Color3.fromRGB(200, 194, 236)
local RIM = Color3.fromRGB(240, 236, 252)
local STONE = Color3.fromRGB(214, 204, 186)
local STONE_TOP = Color3.fromRGB(232, 224, 208)
local SHELL = Color3.fromRGB(252, 248, 238)
local PANEL = Color3.fromRGB(54, 49, 96)
local PANEL_DEEP = Color3.fromRGB(30, 27, 58)
local CARD = Color3.fromRGB(74, 68, 126)
local CARD_DEEP = Color3.fromRGB(46, 42, 86)
-- The top three rows: gold, silver and bronze, light and deep.
local MEDALS = {
	{ Color3.fromRGB(255, 220, 90), Color3.fromRGB(240, 150, 30) },
	{ Color3.fromRGB(232, 238, 250), Color3.fromRGB(150, 160, 192) },
	{ Color3.fromRGB(246, 182, 120), Color3.fromRGB(180, 98, 56) },
}

type Row = {
	frame: Frame,
	rank: TextLabel,
	badge: Frame,
	face: ImageLabel,
	name: TextLabel,
	handle: TextLabel,
	score: TextLabel,
}

type BoardState = {
	info: Leaderboards.Board,
	store: OrderedDataStore?,
	-- userId -> score, from the last successful read of the store.
	globalScores: { [number]: number },
	-- What each player's score was when last written to the store.
	lastWritten: { [Player]: number },
	rows: { Row },
	empty: TextLabel?,
}

local LeaderboardService = {}

local boards: { BoardState } = {}
local names: { [number]: string } = {}

-- Each board's score for a player, from their saved data.
local SCORES: { [string]: (Player, any) -> number } = {
	Stamina = function(_player, data)
		return Stats.maxStamina(data)
	end,
	Collectors = function(_player, data)
		return Hatchery.discoveredCount(data)
	end,
	Earners = function(player, _data)
		return InventoryService.GetIncome(player)
	end,
	EggClaimers = function(_player, data)
		return data.Stats.EggsClaimed or 0
	end,
}

local function scoreOf(board: BoardState, player: Player): number?
	local data = DataService.GetData(player)
	local score = SCORES[board.info.id]
	if data == nil or score == nil then
		return nil
	end
	return math.floor(score(player, data))
end

-- A player's username (without asking Roblox again once known).
local function usernameOf(userId: number): string
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

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

----------------------------------------------------------------------------------------------------------------
-- The board's screen

local function label(parent: Instance, props): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = props.name or "Label"
	text.BackgroundTransparency = 1
	text.Font = props.font or Enum.Font.FredokaOne
	text.TextColor3 = props.color or WHITE
	text.TextSize = props.size or 24
	text.TextXAlignment = props.align or Enum.TextXAlignment.Center
	text.Text = props.text or ""
	text.Position = props.position or UDim2.new()
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

local function corner(parent: Instance, radius: UDim)
	local round = Instance.new("UICorner")
	round.CornerRadius = radius
	round.Parent = parent
end

local function gradient(parent: Instance, light: Color3, deep: Color3, rotation: number?)
	local fade = Instance.new("UIGradient")
	fade.Color = ColorSequence.new(light, deep)
	fade.Rotation = rotation or 90
	fade.Parent = parent
end

local function outline(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
end

local function buildRow(list: Frame, index: number, info: Leaderboards.Board): Row
	local medal = MEDALS[index]
	local frame = Instance.new("Frame")
	frame.Name = "Row" .. index
	frame.LayoutOrder = index
	frame.Size = UDim2.new(1, 0, 0, 52)
	frame.BackgroundColor3 = WHITE
	frame.Visible = false
	frame.Parent = list
	corner(frame, UDim.new(0, 12))
	gradient(frame, if medal then medal[1] else CARD, if medal then medal[2] else CARD_DEEP)
	outline(frame, if medal then WHITE else rgb(info.light), if medal then 2.5 else 1.5)

	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, 8, 0.5, 0)
	badge.Size = UDim2.fromOffset(38, 38)
	badge.BackgroundColor3 = if medal then WHITE else INK
	badge.Parent = frame
	corner(badge, UDim.new(0.5, 0))
	outline(badge, INK, 2)
	local rank = label(badge, {
		name = "Rank",
		text = tostring(index),
		font = Enum.Font.LuckiestGuy,
		color = if medal then medal[2] else WHITE,
		size = 24,
		position = UDim2.fromOffset(0, 2),
		box = UDim2.fromScale(1, 1),
	})

	local face = Instance.new("ImageLabel")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0, 0.5)
	face.Position = UDim2.new(0, 54, 0.5, 0)
	face.Size = UDim2.fromOffset(42, 42)
	face.BackgroundColor3 = PANEL_DEEP
	face.Parent = frame
	corner(face, UDim.new(0.5, 0))
	outline(face, WHITE, 2)

	local name = label(frame, {
		name = "PlayerName",
		align = Enum.TextXAlignment.Left,
		size = 24,
		stroke = 2,
		position = UDim2.fromOffset(104, 3),
		box = UDim2.new(0.56, -104, 0, 28),
	})
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local handle = label(frame, {
		name = "Handle",
		align = Enum.TextXAlignment.Left,
		font = Enum.Font.GothamBold,
		color = if medal then INK else SOFT,
		size = 14,
		position = UDim2.fromOffset(104, 30),
		box = UDim2.new(0.56, -104, 0, 18),
	})
	handle.TextTruncate = Enum.TextTruncate.AtEnd
	local score = label(frame, {
		name = "Score",
		align = Enum.TextXAlignment.Right,
		font = Enum.Font.LuckiestGuy,
		color = if medal then WHITE else rgb(info.light),
		size = 28,
		stroke = 2.5,
		position = UDim2.new(0.56, 0, 0, 4),
		box = UDim2.new(0.44, -12, 0, 30),
	})
	label(frame, {
		name = "Unit",
		align = Enum.TextXAlignment.Right,
		font = Enum.Font.GothamBold,
		color = if medal then INK else SOFT,
		size = 12,
		text = info.unit,
		position = UDim2.new(0.56, 0, 0, 34),
		box = UDim2.new(0.44, -12, 0, 14),
	})

	return {
		frame = frame,
		rank = rank,
		badge = badge,
		face = face,
		name = name,
		handle = handle,
		score = score,
	}
end

-- The shared screen: the title band, a row a player, and a note at the foot.
local function buildDisplay(screen: BasePart, state: BoardState)
	local info = state.info
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Parent = screen

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, 1)
	body.BackgroundColor3 = WHITE
	body.Parent = gui
	gradient(body, PANEL, PANEL_DEEP)

	local header = Instance.new("Frame")
	header.Name = "Banner"
	header.Size = UDim2.new(1, 0, 0, 118)
	header.BackgroundColor3 = WHITE
	header.Parent = gui
	gradient(header, WHITE, Color3.fromRGB(204, 198, 232))
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.AnchorPoint = Vector2.new(0, 1)
	edge.Position = UDim2.fromScale(0, 1)
	edge.Size = UDim2.new(1, 0, 0, 6)
	edge.BackgroundColor3 = rgb(info.deep)
	edge.BorderSizePixel = 0
	edge.Parent = header

	local tag = Instance.new("Frame")
	tag.Name = "Tag"
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 0, 8)
	tag.Size = UDim2.fromOffset(190, 24)
	tag.BackgroundColor3 = WHITE
	tag.Parent = header
	corner(tag, UDim.new(0.5, 0))
	gradient(tag, rgb(info.light), rgb(info.deep))
	outline(tag, INK, 2)
	label(tag, {
		name = "Label",
		text = "EVERY SERVER",
		font = Enum.Font.GothamBold,
		size = 14,
		stroke = 1.5,
		box = UDim2.fromScale(1, 1),
	})
	label(header, {
		name = "Title",
		text = info.title,
		font = Enum.Font.LuckiestGuy,
		size = 50,
		stroke = 4,
		position = UDim2.fromOffset(0, 34),
		box = UDim2.new(1, 0, 0, 52),
	})
	label(header, {
		name = "Subtitle",
		text = info.subtitle,
		font = Enum.Font.GothamBold,
		color = rgb(info.deep),
		size = 16,
		position = UDim2.fromOffset(0, 88),
		box = UDim2.new(1, 0, 0, 20),
	})

	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(14, 130)
	list.Size = UDim2.new(1, -28, 0, Leaderboards.ROWS * 56)
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	for index = 1, Leaderboards.ROWS do
		state.rows[index] = buildRow(list, index, info)
	end

	state.empty = label(gui, {
		name = "Empty",
		text = "Nobody yet. Be the first!",
		color = SOFT,
		size = 26,
		stroke = 2,
		position = UDim2.fromScale(0.05, 0.45),
		box = UDim2.fromScale(0.9, 0.1),
	})
	label(gui, {
		name = "Note",
		text = "Updates every minute",
		font = Enum.Font.GothamBold,
		color = SOFT,
		size = 14,
		position = UDim2.new(0, 0, 1, -30),
		box = UDim2.new(1, 0, 0, 22),
	})
end

----------------------------------------------------------------------------------------------------------------
-- The board's model

local function newPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material): Part
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Anchored = true
	piece.Size = size
	piece.CFrame = cframe
	piece.Color = color
	piece.Material = material or Enum.Material.SmoothPlastic
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.Parent = model
	return piece
end

-- A pillar beside the rim: blocks in bands of white and the board's colour, a glowing lamp on top.
local function buildPillar(model: Model, frame: CFrame, side: number, info: Leaderboards.Board)
	local x = side * (SCREEN_WIDTH / 2 + 2.8)
	local band = 3
	for step = 0, RIM_HEIGHT / band - 1 do
		local even = step % 2 == 0
		newPart(
			model,
			"Pillar",
			Vector3.new(if even then 3.4 else 3, band, if even then 3.4 else 3),
			frame * CFrame.new(x, PLINTH_HEIGHT + band * (step + 0.5), 0.6),
			if even then RIM else rgb(info.deep)
		)
	end
	local top = PLINTH_HEIGHT + RIM_HEIGHT
	newPart(model, "PillarCap", Vector3.new(4, 1, 4), frame * CFrame.new(x, top + 0.5, 0.6), RIM)
	local lamp = newPart(
		model,
		"Lamp",
		Vector3.new(2.4, 2.4, 2.4),
		frame * CFrame.new(x, top + 2.2, 0.6) * CFrame.Angles(0, math.rad(45), 0),
		rgb(info.light),
		Enum.Material.Neon
	)
	local light = Instance.new("PointLight")
	light.Color = rgb(info.light)
	light.Range = 14
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = lamp
end

-- The emblem on the egg's front, built from blocks: a lightning bolt, a paw, or a coin.
local function buildEmblem(model: Model, at: CFrame, info: Leaderboards.Board)
	local light, deep = rgb(info.light), rgb(info.deep)
	if info.emblem == "Bolt" then
		newPart(
			model,
			"Emblem",
			Vector3.new(1.3, 3.4, 0.6),
			at * CFrame.new(0.7, 1.3, 0) * CFrame.Angles(0, 0, math.rad(-25)),
			light,
			Enum.Material.Neon
		)
		newPart(model, "Emblem", Vector3.new(3, 1.1, 0.6), at * CFrame.new(0, 0, 0), light, Enum.Material.Neon)
		newPart(
			model,
			"Emblem",
			Vector3.new(1.3, 3.4, 0.6),
			at * CFrame.new(-0.7, -1.3, 0) * CFrame.Angles(0, 0, math.rad(-25)),
			light,
			Enum.Material.Neon
		)
	elseif info.emblem == "Paw" then
		newPart(model, "Emblem", Vector3.new(2.8, 2.2, 0.6), at * CFrame.new(0, -0.8, 0), deep)
		for index, toe in { { -1.6, 0.6 }, { -0.6, 1.5 }, { 0.6, 1.5 }, { 1.6, 0.6 } } do
			newPart(model, "Toe" .. index, Vector3.new(1, 1.2, 0.6), at * CFrame.new(toe[1], toe[2], 0), deep)
		end
	else
		local coin = newPart(
			model,
			"Emblem",
			Vector3.new(0.6, 4, 4),
			at * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(255, 206, 60),
			Enum.Material.SmoothPlastic
		)
		coin.Shape = Enum.PartType.Cylinder
		local inner = newPart(
			model,
			"EmblemInner",
			Vector3.new(0.7, 3, 3),
			at * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(240, 170, 30),
			Enum.Material.SmoothPlastic
		)
		inner.Shape = Enum.PartType.Cylinder
		local sign = newPart(model, "Sign", Vector3.new(2.4, 2.4, 0.1), at * CFrame.new(0, 0, -0.4), WHITE)
		sign.Transparency = 1
		sign.CanCollide = false
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = sign
		label(gui, {
			name = "Dollar",
			text = "$",
			font = Enum.Font.LuckiestGuy,
			size = 80,
			color = Color3.fromRGB(255, 250, 220),
			stroke = 4,
			box = UDim2.fromScale(1, 1),
		})
	end
end

-- The egg on top of the board: a blocky egg of stacked slabs, a band of the board's colour round its middle, and
-- the emblem on its front.
local function buildCrest(model: Model, frame: CFrame, info: Leaderboards.Board)
	local base = PLINTH_HEIGHT + RIM_HEIGHT
	local widths = { 5, 7, 8.2, 8.8, 8.8, 8.4, 7.6, 6.4, 4.8, 3 }
	local slab = 1.2
	for index, width in widths do
		local banded = index == 4 or index == 5
		newPart(
			model,
			"Crest",
			Vector3.new(width, slab, math.min(width, 4.4)),
			frame * CFrame.new(0, base + slab * (index - 0.5), 0.4),
			if banded then rgb(info.light) else SHELL
		)
	end
	buildEmblem(model, frame * CFrame.new(0, base + slab * 5, -1.9), info)
end

-- Builds board `index` in `parent`. Returns the strip under the screen (for each player's own line).
local function buildBoard(parent: Instance, index: number, state: BoardState)
	local info = state.info
	local model = Instance.new("Model")
	model.Name = info.id
	model:SetAttribute("Leaderboard", info.id)

	local spot = HubLayout.leaderboardSpot(index)
	local ground = Vector3.new(spot.x, Runway.BASE_Y, spot.z)
	-- Facing -z, into the hub: the front of every part is towards the plaza.
	local frame = CFrame.lookAt(ground, ground + Vector3.new(0, 0, -1))

	newPart(
		model,
		"Plinth",
		Vector3.new(HubLayout.LEADERBOARD_WIDTH, PLINTH_HEIGHT - 1, HubLayout.LEADERBOARD_DEPTH),
		frame * CFrame.new(0, (PLINTH_HEIGHT - 1) / 2, 0),
		STONE,
		Enum.Material.Slate
	)
	newPart(
		model,
		"PlinthTop",
		Vector3.new(HubLayout.LEADERBOARD_WIDTH - 3, 1, HubLayout.LEADERBOARD_DEPTH - 2),
		frame * CFrame.new(0, PLINTH_HEIGHT - 0.5, 0),
		STONE_TOP,
		Enum.Material.Slate
	)
	newPart(
		model,
		"Rim",
		Vector3.new(SCREEN_WIDTH + 2, RIM_HEIGHT, 1.6),
		frame * CFrame.new(0, PLINTH_HEIGHT + RIM_HEIGHT / 2, 0.6),
		RIM
	)
	local screenY = PLINTH_HEIGHT + 0.6 + STRIP_HEIGHT + 0.6 + SCREEN_HEIGHT / 2
	local screen = newPart(
		model,
		"Screen",
		Vector3.new(SCREEN_WIDTH, SCREEN_HEIGHT, 0.4),
		frame * CFrame.new(0, screenY, -0.4),
		PANEL_DEEP
	)
	model.PrimaryPart = screen
	local strip = newPart(
		model,
		"YouStrip",
		Vector3.new(SCREEN_WIDTH, STRIP_HEIGHT, 0.4),
		frame * CFrame.new(0, PLINTH_HEIGHT + 0.6 + STRIP_HEIGHT / 2, -0.4),
		INK
	)
	strip:SetAttribute("Leaderboard", info.id)
	for _, side in { -1, 1 } do
		buildPillar(model, frame, side, info)
	end
	buildCrest(model, frame, info)
	buildDisplay(screen, state)

	pcall(function()
		-- Always loaded on every device, like the rest of the hub.
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	model.Parent = parent
	return strip
end

----------------------------------------------------------------------------------------------------------------
-- Scores

local function liveScores(state: BoardState): { [number]: number }
	local live = {}
	for _, player in Players:GetPlayers() do
		local score = scoreOf(state, player)
		if score then
			live[player.UserId] = score
		end
	end
	return live
end

local function draw(state: BoardState)
	local ranking = Rankings.rank(state.globalScores, liveScores(state))
	if state.empty then
		state.empty.Visible = #ranking == 0
	end
	for index, row in state.rows do
		local entry = ranking[index]
		row.frame.Visible = entry ~= nil
		if entry then
			local player = Players:GetPlayerByUserId(entry.userId)
			local username = usernameOf(entry.userId)
			row.name.Text = if player and player.DisplayName ~= "" then player.DisplayName else username
			row.handle.Text = "@" .. username
			row.score.Text = Leaderboards.formatScore(state.info, entry.score)
			row.face.Image = `rbxthumb://type=AvatarHeadShot&id={entry.userId}&w=150&h=150`
		end
	end
	-- Each player's own score and place, for the strip under the board on their device.
	for _, player in Players:GetPlayers() do
		local score = scoreOf(state, player)
		if score then
			player:SetAttribute(Leaderboards.scoreAttribute(state.info), score)
			player:SetAttribute(Leaderboards.rankAttribute(state.info), Rankings.rankOf(ranking, player.UserId))
		end
	end
end

-- Writes changed scores of players in this server, then reads the board's global top list.
local function fetch(state: BoardState)
	local store = state.store
	if store == nil then
		return
	end
	for _, player in Players:GetPlayers() do
		local score = scoreOf(state, player)
		if score and Rankings.stored(score) ~= state.lastWritten[player] then
			local value = Rankings.stored(score)
			local ok = pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
			if ok then
				state.lastWritten[player] = value
			end
		end
	end

	local ok, page = pcall(function()
		return store:GetSortedAsync(false, Leaderboards.RANKED):GetCurrentPage()
	end)
	if ok and typeof(page) == "table" then
		local scores = {}
		for _, entry in page do
			local userId = tonumber(entry.key)
			if userId and typeof(entry.value) == "number" then
				scores[userId] = entry.value
			end
		end
		state.globalScores = scores
	end
end

-- Redraws every board now (other services and tests can call this after a score changes).
function LeaderboardService.Refresh()
	for _, state in boards do
		draw(state)
	end
end

function LeaderboardService.Init()
	local map = Workspace:FindFirstChild("Map") or Workspace
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = map

	for index, info in Leaderboards.active() do
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(info.store)
		end)
		local state: BoardState = {
			info = info,
			store = if ok then result else nil,
			globalScores = {},
			lastWritten = {},
			rows = {},
			empty = nil,
		}
		buildBoard(folder, index, state)
		table.insert(boards, state)
	end

	Players.PlayerRemoving:Connect(function(player)
		for _, state in boards do
			state.lastWritten[player] = nil
		end
	end)
	LeaderboardService.Refresh()
end

function LeaderboardService.Start()
	local sinceFetch = math.huge
	while true do
		if sinceFetch >= Leaderboards.FETCH_INTERVAL then
			sinceFetch = 0
			for _, state in boards do
				fetch(state)
			end
		end
		LeaderboardService.Refresh()
		task.wait(Leaderboards.REDRAW_INTERVAL)
		sinceFetch += Leaderboards.REDRAW_INTERVAL
	end
end

return LeaderboardService
