-- One place for client code to load shared modules, waiting for them to arrive from the server first.
--     local Load = require(script.Parent.Parent.Load)
--     local Runway = Load.shared("Runway")
--     local Tuning = Load.shared("Config", "Tuning")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")

local Load = {}

function Load.shared(...: string): any
	local instance: Instance = sharedFolder
	for _, name in { ... } do
		instance = instance:WaitForChild(name)
	end
	return require(instance :: ModuleScript) :: any
end

return Load
