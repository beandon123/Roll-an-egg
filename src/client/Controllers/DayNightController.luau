-- Runs the day and night: each runway cycle is one day (Shared/CycleClock), so the sun rises as each zone sends
-- out its fresh lineup of eggs, sinks through the last of the day, and sets as the runway closes; the short night
-- passes while it is closed, and the sun is up again as it reopens.
-- Worked out from the shared clock on this device, so everyone sees the same sky without the server sending it.
-- Nights are moonlit rather than black, so the runway stays playable (and glowing eggs stand out).
-- The fog in the distance (MapService sets how far off it starts and ends) is a bright, milky white-blue by day, so
-- the runway ahead fades into pale light, and a deep blue by night.

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
	fog = Color3.fromRGB(220, 233, 245),
}
local NIGHT = {
	brightness = 1.1,
	ambient = Color3.fromRGB(58, 64, 96),
	outdoor = Color3.fromRGB(92, 102, 148),
	fog = Color3.fromRGB(44, 54, 92),
}

local function update()
	local now = Workspace:GetServerTimeNow()
	local daylight = CycleClock.daylight(now)
	Lighting.ClockTime = CycleClock.clockTime(now)
	Lighting.Brightness = NIGHT.brightness + (DAY.brightness - NIGHT.brightness) * daylight
	Lighting.Ambient = NIGHT.ambient:Lerp(DAY.ambient, daylight)
	Lighting.OutdoorAmbient = NIGHT.outdoor:Lerp(DAY.outdoor, daylight)
	Lighting.FogColor = NIGHT.fog:Lerp(DAY.fog, daylight)
end

function DayNightController.Start()
	update()
	RunService.RenderStepped:Connect(update)
end

return DayNightController
