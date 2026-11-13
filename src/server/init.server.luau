-- Server entry point: loads every service, then starts them in order.
--
-- A service is a ModuleScript in Services/ that may define:
--     Init()   set up state and connect to other services; must not yield
--     Start()  begin running (loops, player handling)

local Services = script.Services

local ORDER = {
	"DataService",
	"RunwayService",
	"MapService",
	"ShopService",
	"SettingsService",
	"LeaderboardService",
	"DevService",
}

local loaded = {}
for _, name in ORDER do
	loaded[name] = require(Services[name])
end

for _, name in ORDER do
	local service = loaded[name]
	if service.Init then
		service.Init()
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service.Start then
		task.spawn(service.Start)
	end
end
