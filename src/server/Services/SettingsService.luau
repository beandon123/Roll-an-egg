-- Saves each player's settings (volume, pet visibility, comfort options) in their data, so they follow the player
-- to any device. Every value is checked against Config/Settings before it is stored.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Settings = require(Shared.Config.Settings)

local DataService = require(script.Parent.DataService)

local SettingsService = {}

local function onSaveSettings(player: Player, values: unknown)
	if typeof(values) ~= "table" then
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	-- Only known keys are read, so a client cannot fill the saved data with junk.
	for _, setting in Settings.List do
		local value = Settings.sanitize(setting.key, (values :: any)[setting.key])
		if value ~= nil then
			data.Settings[setting.key] = value
		end
	end
end

local function onGetSettings(player: Player)
	local data = DataService.WaitForData(player, 10)
	return Settings.withDefaults(if data then data.Settings else nil)
end

function SettingsService.Init()
	Net.SaveSettings.OnServerEvent:Connect(onSaveSettings)
	Net.GetSettings.OnServerInvoke = onGetSettings
end

return SettingsService
