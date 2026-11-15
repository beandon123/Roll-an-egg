-- Builds the endless repeat of the last zone past the end of the runway: its ground, its side walls, and its gate
-- once per loop (see Shared/Runway). Nobody ever gets that far, because everything is carried back one loop before
-- reaching it, but it is always in view ahead, so the runway never seems to end. It is built on this device rather
-- than by the server, so it is always there however far away it is. The fog (set by the server's MapService) hides
-- where it stops.

local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local MapParts = Load.shared("MapParts")
local Runway = Load.shared("Runway")

local WorldController = {}

function WorldController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "EndlessRunway"

	local fromZ, toZ = Runway.LENGTH, Runway.LENGTH + Runway.RUNOUT
	MapParts.ground(folder, Runway.ZONE_COUNT, fromZ, toZ)
	MapParts.walls(folder, fromZ, toZ)
	local gateZ = Runway.FINAL_ZONE_START + Runway.LOOP_LENGTH
	while gateZ <= toZ do
		MapParts.gate(folder, Runway.ZONE_COUNT, gateZ)
		gateZ += Runway.LOOP_LENGTH
	end

	folder.Parent = Workspace
end

return WorldController
