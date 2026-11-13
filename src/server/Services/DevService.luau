-- Testing shortcuts that only work inside Roblox Studio. In a live server every command is ignored, so these
-- cannot be used to cheat even though the remote exists.
--
-- The buttons for these are on the client's Studio-only test panel (see Ui/Hud).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Zones = require(Shared.Config.Zones)

local RunwayService = require(script.Parent.RunwayService)

local MAX_TEST_STAMINA = 1e7

local DevService = {}

local commands: { [string]: (Player) -> () } = {
	-- Multiplies Max Stamina by 5, so deeper zones can be tested before upgrades exist.
	StaminaUp = function(player)
		local current = RunwayService.GetMaxStamina(player)
		RunwayService.SetMaxStamina(player, math.min(MAX_TEST_STAMINA, current * 5))
	end,
	-- Back to what the player really has (the base plus anything bought in the shop).
	StaminaReset = function(player)
		RunwayService.RefreshMaxStamina(player)
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
