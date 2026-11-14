--!strict
-- The player's settings: what the Settings panel shows, their defaults, and the checks the server runs before
-- saving one. Pure data (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Values are saved in the player's data, so they follow the player to any device.

export type Setting = {
	key: string,
	section: string,
	label: string,
	-- An emoji drawn next to the label until icon art exists.
	icon: string,
	kind: "Slider" | "Toggle",
	-- 0-1 for sliders, true/false for toggles.
	default: number | boolean,
}

local Settings = {}

-- Sections in the order the panel shows them.
Settings.Sections = { "Audio", "Pets", "Comfort" }

local list: { Setting } = {
	{ key = "MusicVolume", section = "Audio", label = "Music", icon = "🎵", kind = "Slider", default = 1 },
	{ key = "EffectsVolume", section = "Audio", label = "Effects", icon = "💥", kind = "Slider", default = 1 },
	{ key = "AmbienceVolume", section = "Audio", label = "Nature", icon = "🌿", kind = "Slider", default = 1 },
	{
		key = "ShowOthersPets",
		section = "Pets",
		label = "Show Others' Pets",
		icon = "👀",
		kind = "Toggle",
		default = true,
	},
	{ key = "ShowMyPets", section = "Pets", label = "Show Your Pets", icon = "🐾", kind = "Toggle", default = true },
	{
		key = "ReduceCameraShake",
		section = "Comfort",
		label = "Reduce Camera Shake",
		icon = "🎥",
		kind = "Toggle",
		default = false,
	},
	{ key = "Vibration", section = "Comfort", label = "Vibration", icon = "📳", kind = "Toggle", default = true },
}

local byKey: { [string]: Setting } = {}
for _, setting in list do
	byKey[setting.key] = setting
end

Settings.List = list
Settings.ByKey = byKey

-- The settings in one section, in display order.
function Settings.inSection(section: string): { Setting }
	local found = {}
	for _, setting in list do
		if setting.section == section then
			table.insert(found, setting)
		end
	end
	return found
end

-- A value for `key` made safe to save, or nil if it cannot be (unknown key, wrong type, not a number).
-- Sliders are clamped to 0-1 and rounded to whole percent.
function Settings.sanitize(key: unknown, value: unknown): (number | boolean)?
	if typeof(key) ~= "string" then
		return nil
	end
	local setting = byKey[key :: string]
	if setting == nil then
		return nil
	end
	if setting.kind == "Toggle" then
		return if typeof(value) == "boolean" then value :: boolean else nil
	end
	if typeof(value) ~= "number" or value ~= value then
		return nil
	end
	return math.floor(math.clamp(value :: number, 0, 1) * 100 + 0.5) / 100
end

-- Every setting, taking saved values where they are valid and defaults everywhere else.
function Settings.withDefaults(saved: { [string]: any }?): { [string]: number | boolean }
	local values = {}
	for _, setting in list do
		local value = if saved then Settings.sanitize(setting.key, saved[setting.key]) else nil
		if value == nil then
			values[setting.key] = setting.default
		else
			values[setting.key] = value
		end
	end
	return values
end

return Settings
