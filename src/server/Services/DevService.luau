-- Testing shortcuts that only work inside Roblox Studio. In a live server every command is ignored, so these
-- cannot be used to cheat even though the remote exists.
--
-- The buttons for these are on the client's Studio-only test panel (see Ui/Hud).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local PetRig = require(Shared.PetRig)
local Runway = require(Shared.Runway)
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)

local RunwayService = require(script.Parent.RunwayService)

local MAX_TEST_STAMINA = 1e7
-- Seconds between eggs for DropEachEgg, so they spread out down the runway instead of landing in a pile.
local EACH_EGG_GAP = 0.8
-- Where ShowPets stands the zone's pets: two rows of four in front of the player, in studs.
local PET_COLUMNS = { -18, -6, 6, 18 }
local PET_ROWS = { 18, 32 }

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
	-- Stands the pets that hatch from the zone's eggs in front of the player, facing them, to look at.
	-- Pets without a model yet are left out. Showing them again replaces the last lot.
	ShowPets = function(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		local old = Workspace:FindFirstChild("StudioPets")
		if old then
			old:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = "StudioPets"
		folder.Parent = Workspace

		local zone = Zones.List[RunwayService.GetZoneOf(player)]
		local slot = 0
		for _, entry in zone.eggs do
			local pet = PetRig.build(entry.pet)
			if pet then
				slot += 1
				local x = root.Position.X + PET_COLUMNS[(slot - 1) % 4 + 1]
				local z = root.Position.Z + PET_ROWS[(slot - 1) // 4 + 1]
				local y = Runway.surfaceY(z) + pet:GetAttribute("GroundOffset")
				-- Pets face -Z, which is back towards the player.
				pet:PivotTo(CFrame.new(x, y, z))
				pet.Parent = folder
			end
		end
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
