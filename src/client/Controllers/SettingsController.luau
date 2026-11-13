-- Loads the player's saved settings, applies them, and saves changes a moment after the player stops fiddling.
--
-- Volumes go to three SoundGroups in SoundService ("Music", "Effects", "Nature"): every sound the game adds later
-- should be put in one of them, so these sliders control it. Other settings are read from UiState.settings by
-- whichever system they belong to (pets, camera shake, vibration) once that system exists.

local SoundService = game:GetService("SoundService")

local Load = require(script.Parent.Parent.Load)
local Net = Load.shared("Net")
local Settings = Load.shared("Config", "Settings")

local UiState = require(script.Parent.Parent.Ui.UiState)

-- Seconds after the last change before the settings are sent to the server.
local SAVE_DELAY = 1.5

-- Which SoundGroup each volume slider controls.
local SOUND_GROUPS = {
	MusicVolume = "Music",
	EffectsVolume = "Effects",
	AmbienceVolume = "Nature",
}

local SettingsController = {}

local loaded = false
local saveToken = 0

local function soundGroup(name: string): SoundGroup
	local group = SoundService:FindFirstChild(name)
	if group and group:IsA("SoundGroup") then
		return group
	end
	local created = Instance.new("SoundGroup")
	created.Name = name
	created.Parent = SoundService
	return created
end

local function apply(key: string)
	local groupName = SOUND_GROUPS[key]
	if groupName then
		soundGroup(groupName).Volume = UiState.Fusion.peek(UiState.settings[key])
	end
end

local function scheduleSave()
	if not loaded then
		return
	end
	saveToken += 1
	local token = saveToken
	task.delay(SAVE_DELAY, function()
		if token ~= saveToken then
			return
		end
		local values = {}
		for key, value in UiState.settings do
			values[key] = UiState.Fusion.peek(value)
		end
		Net.SaveSettings:FireServer(values)
	end)
end

-- The current value of a setting, for systems that need one.
function SettingsController.Get(key: string): any
	local value = UiState.settings[key]
	return if value then UiState.Fusion.peek(value) else nil
end

function SettingsController.Init()
	for key, value in UiState.settings do
		apply(key)
		UiState.scope:Observer(value):onChange(function()
			apply(key)
			scheduleSave()
		end)
	end
end

function SettingsController.Start()
	local saved = Settings.withDefaults(Net.GetSettings:InvokeServer())
	for key, value in saved do
		local state = UiState.settings[key]
		if state then
			state:set(value)
		end
	end
	-- Only changes the player makes from here on are saved.
	loaded = true
end

return SettingsController
