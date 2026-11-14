-- Runs the day and night: each runway cycle is one day (Shared/CycleClock), so the sun rises as each zone sends
-- out its fresh lineup of eggs, sets later in the cycle, and the runway closes in the dark before the next dawn.
-- Worked out from the shared clock on this device, so everyone sees the same sky without the server sending it.
-- Nights are moonlit rather than black, so the runway stays playable (and glowing eggs stand out).

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local CycleClock = Load.shared("CycleClock")

local DayNightController = {}

local DAY = {
	brightness = 2.6,
	ambient = Color3.fromRGB(112, 112, 120),
	outdoor = Color3.fromRGB(146, 146, 154),
	haze = Color3.fromRGB(199, 220, 236),
}
local NIGHT = {
	brightness = 1.1,
	ambient = Color3.fromRGB(58, 64, 96),
	outdoor = Color3.fromRGB(92, 102, 148),
	haze = Color3.fromRGB(52, 62, 104),
}

local function update()
	local now = Workspace:GetServerTimeNow()
	local daylight = CycleClock.daylight(now)
	Lighting.ClockTime = CycleClock.clockTime(now)
	Lighting.Brightness = NIGHT.brightness + (DAY.brightness - NIGHT.brightness) * daylight
	Lighting.Ambient = NIGHT.ambient:Lerp(DAY.ambient, daylight)
	Lighting.OutdoorAmbient = NIGHT.outdoor:Lerp(DAY.outdoor, daylight)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Color = NIGHT.haze:Lerp(DAY.haze, daylight)
	end
end

function DayNightController.Start()
	update()
	RunService.RenderStepped:Connect(update)
end

return DayNightController
