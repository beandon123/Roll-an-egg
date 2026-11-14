-- Client entry point: loads every controller, then starts them in order.
--
-- A controller is a ModuleScript in Controllers/ that may define:
--     Init()   set up state and connect events; must not yield
--     Start()  begin running (may yield)

local Controllers = script.Controllers

local ORDER = {
	"EggController",
	"InventoryController",
	"RideController",
	"HudController",
	"PetAnimationController",
	"ObstacleController",
	"DayNightController",
	"HatchController",
	"PenController",
	"MountController",
	"ShopController",
	"SettingsController",
	"FlyController",
	"AdminController",
}

local loaded = {}
for _, name in ORDER do
	loaded[name] = require(Controllers[name])
end

for _, name in ORDER do
	local controller = loaded[name]
	if controller.Init then
		controller.Init()
	end
end

for _, name in ORDER do
	local controller = loaded[name]
	if controller.Start then
		task.spawn(controller.Start)
	end
end
