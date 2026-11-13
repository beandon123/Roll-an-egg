-- The look shared by every screen: a warm "farmyard" palette (eggshell cream, yolk yellow, dark brown ink
-- instead of black outlines), chunky rounded fonts, and one color pair per shop section.
--
-- Placeholder art: icons are emoji until the art phase delivers images.

local Theme = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Theme.INK = rgb(46, 30, 22)
Theme.WHITE = rgb(255, 255, 255)
Theme.CREAM = rgb(255, 246, 228)
Theme.SHELL = rgb(255, 234, 196)
Theme.SHELL_DARK = rgb(233, 205, 160)
Theme.YOLK = rgb(255, 200, 46)
Theme.YOLK_DEEP = rgb(255, 150, 30)
Theme.GREEN = rgb(86, 214, 120)
Theme.GREEN_DEEP = rgb(36, 160, 88)
Theme.CORAL = rgb(255, 98, 86)
Theme.CORAL_DEEP = rgb(214, 58, 64)
Theme.SKY = rgb(92, 170, 255)
Theme.SKY_DEEP = rgb(52, 110, 230)
Theme.COIN = rgb(255, 205, 50)
Theme.COIN_DEEP = rgb(208, 132, 20)
Theme.TRACK = rgb(222, 196, 156)
Theme.BACKDROP = rgb(30, 18, 10)

-- Fonts: a bouncy display face for titles, a rounded face for everything else.
Theme.TITLE_FONT = Enum.Font.LuckiestGuy
Theme.FONT = Enum.Font.FredokaOne
Theme.SMALL_FONT = Enum.Font.GothamBold

-- The Robux icon. Roblox's fonts draw this private-use character as the Robux symbol.
Theme.ROBUX = utf8.char(0xE002)

export type Accent = { name: string, icon: string, light: Color3, deep: Color3, blurb: string }

-- One accent per shop section: a light and a deep shade for gradients, plus its icon and a one-line pitch.
Theme.Sections = {
	Featured = {
		name = "Featured",
		icon = "⭐",
		light = rgb(255, 160, 96),
		deep = rgb(255, 88, 104),
		blurb = "Make room for more pets",
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
	Coins = {
		name = "Coins",
		icon = "💰",
		light = rgb(255, 222, 92),
		deep = rgb(246, 150, 30),
		blurb = "Spend them on upgrades and pens",
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
