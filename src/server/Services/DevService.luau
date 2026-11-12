-- Testing shortcuts that only work inside Roblox Studio. In a live server every command is ignored, so these
-- cannot be used to cheat even though the remote exists.
--
-- The buttons for these are on the client's Studio-only test panel (see Ui/Hud).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)

local RunwayService = require(script.Parent.RunwayService)

local MAX_TEST_STAMINA = 1e7
-- Seconds between eggs for DropEachEgg, so they spread out down the runway instead of landing in a pile.
local EACH_EGG_GAP = 0.8

local DevService = {}

local commands: { [string]: (Player) -> () } = {
	-- Multiplies Max Stamina by 5, so deeper zones can be tested before upgrades exist.
	StaminaUp = function(player)
		local current = RunwayService.GetMaxStamina(player)
		RunwayService.SetMaxStamina(player, math.min(MAX_TEST_STAMINA, current * 5))
	end,
	StaminaReset = function(player)
		RunwayService.SetMaxStamina(player, Tuning.BASE_MAX_STAMINA)
	end,
	-- Drops the rarest egg of the zone the player is standing in.
	DropBestEgg = function(player)
		local zone = Zones.List[RunwayService.GetZoneOf(player)]
		local best, bestRequirement = "Common", 0
		for rarity, requirement in zone.stamina do
			if requirement > bestRequirement then
				best, bestRequirement = rarity, requirement
			end
		end
		RunwayService.DropEgg(zone.id, best)
	end,
	-- Drops each of the zone's eggs in turn, a moment apart, so all of them can be looked at on the runway.
	DropEachEgg = function(player)
		local zone = Zones.List[RunwayService.GetZoneOf(player)]
		for index, entry in zone.eggs do
			task.delay((index - 1) * EACH_EGG_GAP, function()
				RunwayService.DropEgg(zone.id, nil, entry.egg)
			end)
		end
	end,
}

function DevService.Init()
	if not RunService:IsStudio() then
		return
	end
	Net.DevCommand.OnServerEvent:Connect(function(player: Player, command: unknown)
		if typeof(command) ~= "string" then
			return
		end
		local handler = commands[command]
		if handler then
			handler(player)
		end
	end)
end

return DevService
