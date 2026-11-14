--!strict
-- Settings the admin panel (client) and AdminService (server) share. Who is an admin is decided on the server only
-- (ServerScriptService.Server.Config.Admins).
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.

local AdminTools = {}

-- Player attributes the server sets.
AdminTools.IS_ADMIN = "IsAdmin" -- true for admins: shows them the panel
AdminTools.FLYING = "Flying" -- true while the admin flies (Client/Controllers/FlyController)
AdminTools.FLY_SPEED = "FlySpeed" -- studs per second
AdminTools.WALK_SPEED = "WalkSpeed" -- studs per second on foot

-- The speeds the panel offers, in studs per second.
AdminTools.FLY_SPEEDS = { 40, 80, 160, 320 }
AdminTools.DEFAULT_FLY_SPEED = 80
AdminTools.WALK_SPEEDS = { 16, 32, 64, 120 }
AdminTools.DEFAULT_WALK_SPEED = 16

-- Max Stamina the panel's "Max" button sets.
AdminTools.MAX_STAMINA = 1e7

-- Most of one kind of egg or pet given at once, and most kept in an inventory in total, so a stuck button cannot
-- fill a player's saved data.
AdminTools.MAX_GIVE = 10
AdminTools.MAX_INVENTORY = 500

-- Most pets spawned in the world at once; the oldest go first.
AdminTools.MAX_SPAWNED_PETS = 40

-- Where a teleport can go, besides a zone (by number) and another player.
AdminTools.PLACES = { "Hub", "Showroom", "Cliff" }

return AdminTools
