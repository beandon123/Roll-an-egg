--!strict
-- The leaderboard boards beside the start zone (decided: the same three as the owner's reference, in the game's
-- own look): the players with the most Max Stamina, the most different pets found, and the most dollars a second.
-- Each board ranks players across every server (LeaderboardService keeps an OrderedDataStore per board).
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.

local NumberFormat = require(script.Parent.Parent.NumberFormat)

-- How a board's scores are written: a plain number ("24.8T"), a count with commas ("1,629"), or dollars ("$851.2B").
export type Format = "Number" | "Count" | "Dollars"

export type Board = {
	id: string,
	title: string,
	-- Small print under the title: what is counted.
	subtitle: string,
	-- The word under each score, and the start of the player's own line under the board ("YOUR STAMINA: 1.2K").
	unit: string,
	yours: string,
	format: Format,
	-- The OrderedDataStore that holds its scores. Bump the version only to wipe the board.
	store: string,
	-- The crest on top of the board (LeaderboardService builds it from parts): a lightning bolt, a paw, or a coin.
	emblem: "Bolt" | "Paw" | "Coin",
	-- RGB 0-255: the board's own colour, light and deep.
	light: { number },
	deep: { number },
	-- Out of the game for now (kept so it can come back).
	shelved: boolean?,
}

local Leaderboards = {}

-- Rows on each board, and how far down the global list a player's own rank is looked for (below that it reads
-- "100+").
Leaderboards.ROWS = 8
Leaderboards.RANKED = 100
-- Seconds between reads of the global stores (and writes of changed scores), and between redraws with live scores.
Leaderboards.FETCH_INTERVAL = 60
Leaderboards.REDRAW_INTERVAL = 5

-- Left to right, as seen walking from the plots to the start zone.
Leaderboards.List = {
	{
		id = "Stamina",
		title = "TOP STAMINA",
		subtitle = "MAX STAMINA",
		unit = "STAMINA",
		yours = "YOUR STAMINA",
		format = "Number",
		store = "TopStamina_v1",
		emblem = "Bolt",
		light = { 255, 214, 70 },
		deep = { 255, 132, 26 },
	},
	{
		id = "Collectors",
		title = "TOP COLLECTORS",
		subtitle = "PETS FOUND (EVERY VARIANT COUNTS)",
		unit = "FOUND",
		yours = "YOUR COLLECTION",
		format = "Count",
		store = "TopCollectors_v1",
		emblem = "Paw",
		light = { 120, 236, 255 },
		deep = { 70, 118, 255 },
	},
	{
		id = "Earners",
		title = "TOP EARNERS",
		subtitle = "DOLLARS A SECOND",
		unit = "/ SEC",
		yours = "YOUR PEN EARNS",
		format = "Dollars",
		store = "TopEarners_v1",
		emblem = "Coin",
		light = { 130, 240, 120 },
		deep = { 28, 160, 88 },
	},
	-- The first board (eggs claimed on the runway), shelved for the three above (decided).
	{
		id = "EggClaimers",
		title = "TOP EGG CLAIMERS",
		subtitle = "EGGS CLAIMED",
		unit = "EGGS",
		yours = "YOUR EGGS",
		format = "Count",
		store = "TopEggClaimers_v1",
		emblem = "Coin",
		light = { 255, 214, 70 },
		deep = { 255, 132, 26 },
		shelved = true,
	},
} :: { Board }

-- The boards in the game, left to right.
function Leaderboards.active(): { Board }
	local list = {}
	for _, board in Leaderboards.List do
		if not board.shelved then
			table.insert(list, board)
		end
	end
	return list
end

local byId: { [string]: Board } = {}
for _, board in Leaderboards.List do
	byId[board.id] = board
end
Leaderboards.ById = byId

-- "1629" -> "1,629".
local function withCommas(value: number): string
	local text = tostring(math.floor(value))
	local result = text
	repeat
		local count
		result, count = string.gsub(result, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return result
end

-- A score as the board writes it.
function Leaderboards.formatScore(board: Board, value: number): string
	if board.format == "Dollars" then
		return "$" .. NumberFormat.abbreviate(value)
	elseif board.format == "Count" and value < 1000000 then
		return withCommas(value)
	end
	return NumberFormat.abbreviate(value)
end

-- A rank as the player's own line writes it: "#4", "#100+" below the ranks looked at, or "-" for not ranked (0:
-- nothing to count yet).
function Leaderboards.formatRank(rank: number): string
	if rank <= 0 then
		return "-"
	elseif rank > Leaderboards.RANKED then
		return `#{Leaderboards.RANKED}+`
	end
	return `#{rank}`
end

-- The Player attributes the server keeps a player's own score and rank in, for their device to show under each
-- board.
function Leaderboards.scoreAttribute(board: Board): string
	return `Leaderboard{board.id}Score`
end

function Leaderboards.rankAttribute(board: Board): string
	return `Leaderboard{board.id}Rank`
end

return Leaderboards
