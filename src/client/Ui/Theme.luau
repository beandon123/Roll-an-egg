-- The look shared by every screen (decided, after the owner's reference of a glossy reward card): panels with a
-- thick white rim, a glossy white-to-lavender title band and a deep indigo body; cards that are darker gradients of
-- their colour with a bright edge (mint green for highlights); chunky white lettering with a dark navy outline
-- everywhere; a purple main button and gold, coral and green ones, each sitting on a darker lip.
--
-- Placeholder art: icons are emoji until the art phase delivers images.

local Theme = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Outlines round text, buttons and panels: a deep navy rather than black.
Theme.INK = rgb(22, 18, 44)
-- Lettering: white, with lavender for small print.
Theme.WHITE = rgb(255, 255, 255)
Theme.TEXT_SOFT = rgb(200, 194, 236)

-- Panels: a white rim, a glossy title band, and a deep indigo body fading darker towards the bottom.
Theme.RIM = rgb(246, 244, 255)
Theme.HEADER_TOP = rgb(255, 255, 255)
Theme.HEADER_BOTTOM = rgb(204, 198, 232)
Theme.PANEL = rgb(54, 49, 96)
Theme.PANEL_DEEP = rgb(30, 27, 58)

-- Cards inside a panel, and recessed wells (bar tracks, empty slots).
Theme.CARD = rgb(74, 68, 126)
Theme.CARD_DEEP = rgb(46, 42, 86)
Theme.CARD_EDGE = rgb(128, 120, 200)
Theme.WELL = rgb(24, 21, 46)

-- Highlight cards: dark teal fading from mint, with a bright mint edge.
Theme.MINT = rgb(104, 240, 168)
Theme.MINT_CARD = rgb(44, 160, 118)
Theme.MINT_DEEP = rgb(20, 70, 70)

-- Button colours, each a light face and a deep lip.
Theme.VIOLET = rgb(176, 112, 255)
Theme.VIOLET_DEEP = rgb(112, 58, 222)
Theme.YOLK = rgb(255, 204, 60)
Theme.YOLK_DEEP = rgb(255, 134, 26)
Theme.GREEN = rgb(84, 222, 128)
Theme.GREEN_DEEP = rgb(28, 150, 88)
Theme.CORAL = rgb(255, 86, 112)
Theme.CORAL_DEEP = rgb(204, 36, 78)
Theme.SKY = rgb(92, 170, 255)
Theme.SKY_DEEP = rgb(52, 110, 230)
Theme.DOLLAR = rgb(96, 206, 104)
Theme.DOLLAR_DEEP = rgb(30, 128, 62)

-- Behind an open panel.
Theme.BACKDROP = rgb(14, 10, 30)

-- Fonts: a bouncy display face for titles, a rounded face for everything else.
Theme.TITLE_FONT = Enum.Font.LuckiestGuy
Theme.FONT = Enum.Font.FredokaOne
Theme.SMALL_FONT = Enum.Font.GothamBold

-- The Robux icon. Roblox's fonts draw this private-use character as the Robux symbol.
Theme.ROBUX = utf8.char(0xE002)

-- The shop's pack cards (Config/Shop), by pack id: a bright face fading to a deep one, with rays behind the pet.
Theme.Packs = {
	EpicPack = { light = rgb(196, 110, 255), deep = rgb(98, 40, 200), ray = rgb(232, 196, 255) },
	SuperPack = { light = rgb(255, 196, 70), deep = rgb(255, 104, 40), ray = rgb(255, 238, 170) },
} :: { [string]: { light: Color3, deep: Color3, ray: Color3 } }

export type Accent = { name: string, icon: string, light: Color3, deep: Color3, blurb: string }

-- One accent per shop section: a light and a deep shade for gradients, plus its icon and a one-line pitch.
Theme.Sections = {
	Packs = {
		name = "Packs",
		icon = "🎁",
		light = rgb(255, 120, 214),
		deep = rgb(150, 70, 255),
		blurb = "A pet, dollars, stamina, a trail and revives, all at once",
	},
	Revives = {
		name = "Revives",
		icon = "💖",
		light = rgb(255, 140, 170),
		deep = rgb(230, 60, 110),
		blurb = "Missed your leap? Carry on instead of going back to the hub",
	},
	Featured = {
		name = "Featured",
		icon = "⭐",
		light = rgb(255, 160, 96),
		deep = rgb(255, 88, 104),
		blurb = "Better training sticks and bigger pens",
	},
	Luck = {
		name = "Luck",
		icon = "🍀",
		light = rgb(120, 232, 140),
		deep = rgb(32, 170, 98),
		blurb = "Rarer eggs drop for the whole server",
	},
	Stamina = {
		name = "Stamina",
		icon = "⚡",
		light = rgb(104, 220, 255),
		deep = rgb(52, 120, 240),
		blurb = "Hold on to bigger eggs, deeper down",
	},
	Dollars = {
		name = "Dollars",
		icon = "💵",
		light = rgb(130, 226, 120),
		deep = rgb(36, 160, 84),
		blurb = "Spend them on bigger pens",
	},
	Passes = {
		name = "Passes",
		icon = "🎟️",
		light = rgb(200, 140, 255),
		deep = rgb(118, 72, 240),
		blurb = "Buy once, keep forever",
	},
} :: { [string]: Accent }

return Theme
