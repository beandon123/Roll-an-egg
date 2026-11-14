-- The admin panel's client side: puts the panel on screen (it only shows for admins: the server sets the IsAdmin
-- attribute), sends the commands its buttons pick to the server, and keeps AdminState in step with the player's
-- and the server's attributes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local AdminTools = Load.shared("Config", "AdminTools")
local CycleClock = Load.shared("CycleClock")
local Net = Load.shared("Net")

local AdminPanel = require(script.Parent.Parent.Ui.AdminPanel)
local AdminState = require(script.Parent.Parent.Ui.AdminState)

local localPlayer = Players.LocalPlayer

local AdminController = {}

-- Sends a command to the server. Its answer shows in the panel's status line.
function AdminController.Run(command: string, args: { [string]: any }?)
	task.spawn(function()
		local ok, success, message, data = pcall(function()
			return Net.AdminCommand:InvokeServer(command, args or {})
		end)
		if not ok then
			AdminState.status:set("The server did not answer.")
			AdminState.statusGood:set(false)
			return
		end
		if typeof(message) == "string" and message ~= "" then
			AdminState.status:set(message)
			AdminState.statusGood:set(success == true)
		end
		if typeof(data) == "table" and typeof(data.eggs) == "table" and typeof(data.pets) == "table" then
			AdminState.inventory:set(data)
		end
	end)
end

-- Attributes are cheap to read, so they are simply read every frame.
local function readAttributes()
	AdminState.isAdmin:set(localPlayer:GetAttribute(AdminTools.IS_ADMIN) == true)
	AdminState.flying:set(localPlayer:GetAttribute(AdminTools.FLYING) == true)
	local flySpeed = localPlayer:GetAttribute(AdminTools.FLY_SPEED)
	AdminState.flySpeed:set(if typeof(flySpeed) == "number" then flySpeed else AdminTools.DEFAULT_FLY_SPEED)
	local walkSpeed = localPlayer:GetAttribute(AdminTools.WALK_SPEED)
	AdminState.walkSpeed:set(if typeof(walkSpeed) == "number" then walkSpeed else AdminTools.DEFAULT_WALK_SPEED)
	local event = Workspace:GetAttribute(CycleClock.EVENT_ATTRIBUTE)
	AdminState.event:set(if typeof(event) == "string" then event else nil)
end

local function refreshPlayers()
	local list = {}
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			table.insert(list, { userId = player.UserId, name = player.Name })
		end
	end
	table.sort(list, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	AdminState.players:set(list)
end

function AdminController.Init()
	RunService.RenderStepped:Connect(readAttributes)
	Players.PlayerAdded:Connect(refreshPlayers)
	Players.PlayerRemoving:Connect(function()
		-- The leaving player is still listed until this event has run.
		task.defer(refreshPlayers)
	end)
end

function AdminController.Start()
	readAttributes()
	refreshPlayers()
	AdminPanel.mount(localPlayer:WaitForChild("PlayerGui"), AdminController.Run)
end

return AdminController
