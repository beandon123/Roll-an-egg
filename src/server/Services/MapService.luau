-- Builds the placeholder map out of plain parts: the hub (Map/Hub), the mountains round it (Map/Mountains), and
-- the runway's five zone slabs and signs. Final art will replace this; gameplay does not depend on any of these
-- parts (it reads positions from Shared/Runway and Shared/HubLayout), so swapping the map never breaks the rules.
--
-- Also handles falling: a character well below the runway surface has fallen off and dies.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local NumberFormat = require(Shared.NumberFormat)
local Rarities = require(Shared.Config.Rarities)
local Runway = require(Shared.Runway)
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)

local MapFolder = script.Parent.Parent.Map
local Build = require(MapFolder.Build)
local Hub = require(MapFolder.Hub)
local Mountains = require(MapFolder.Mountains)

local SLAB_THICKNESS = 4
local SIGN_HEIGHT = 26

local MapService = {}

-- The lowest and highest stamina requirement of a zone's eggs.
local function staminaRange(zone): (number, number)
	local low, high = math.huge, 0
	for rarity in Rarities.Info do
		local requirement = zone.stamina[rarity]
		if requirement then
			low = math.min(low, requirement)
			high = math.max(high, requirement)
		end
	end
	return low, high
end

local function buildRunway(map: Instance)
	local angle = math.atan(Runway.SLOPE)
	-- Unit vectors along the slope (downhill) and straight out of its surface.
	local along = Vector3.new(0, -math.sin(angle), math.cos(angle))
	local normal = Vector3.new(0, math.cos(angle), math.sin(angle))

	for _, zone in Zones.List do
		local folder = Instance.new("Folder")
		folder.Name = zone.key
		folder.Parent = map

		local startZ = Runway.zoneStartZ(zone.id)
		local middleZ = startZ + Runway.ZONE_LENGTH / 2

		local slab = Build.part(folder, "Ground", {})
		slab.Size = Vector3.new(Runway.WIDTH, SLAB_THICKNESS, Runway.ZONE_LENGTH / math.cos(angle))
		local surfaceMiddle = Vector3.new(0, Runway.surfaceY(middleZ), middleZ)
		local center = surfaceMiddle - normal * (SLAB_THICKNESS / 2)
		slab.CFrame = CFrame.lookAt(center, center + along, normal)
		slab.Color = Build.rgb(zone.ground)

		-- A sign over the start of the zone: its name and the stamina its eggs need.
		local surfaceStart = Runway.surfaceY(startZ)
		for _, side in { -1, 1 } do
			local post = Build.part(folder, "SignPost", {})
			post.Size = Vector3.new(3, SIGN_HEIGHT + 8, 3)
			post.Position = Vector3.new(side * (Runway.WIDTH / 2 + 3), surfaceStart + (SIGN_HEIGHT + 8) / 2 - 4, startZ)
			post.Color = Build.rgb(zone.accent)
		end

		local sign = Build.part(folder, "Sign", {})
		sign.Size = Vector3.new(Runway.WIDTH + 9, 9, 1.5)
		sign.Position = Vector3.new(0, surfaceStart + SIGN_HEIGHT, startZ)
		sign.Color = Build.rgb(zone.accent)
		local low, high = staminaRange(zone)
		local subtitle = `Eggs need {NumberFormat.abbreviate(low)} - {NumberFormat.abbreviate(high)} stamina`
		local textColor = Color3.new(1, 1, 1)
		-- Front faces players coming from the hub; Back faces players walking home.
		Build.signText(sign, Enum.NormalId.Front, string.upper(zone.name), subtitle, textColor)
		Build.signText(sign, Enum.NormalId.Back, string.upper(zone.name), subtitle, textColor)
	end

	-- A warning stripe before the cliff at the end of the runway.
	local warningZ = Runway.LENGTH - 60
	local stripe = Build.part(map, "EdgeWarning", {})
	stripe.Size = Vector3.new(Runway.WIDTH, 0.3, 6)
	local stripeCenter = Vector3.new(0, Runway.surfaceY(warningZ) + 0.1, warningZ)
	stripe.CFrame = CFrame.lookAt(stripeCenter, stripeCenter + along, normal)
	stripe.Color = Color3.fromRGB(255, 60, 60)
	stripe.Material = Enum.Material.Neon
	stripe.CanCollide = false
end

-- Kills characters that have fallen off the runway or the hub.
local function watchForFalls()
	while true do
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
				local position = root.Position
				if position.Y < Runway.surfaceY(position.Z) - Tuning.FALL_KILL_DEPTH then
					humanoid.Health = 0
				end
			end
		end
		task.wait(0.25)
	end
end

function MapService.Init()
	local map = Instance.new("Folder")
	map.Name = "Map"

	Hub.build(map)
	Mountains.build(map)
	buildRunway(map)

	map.Parent = Workspace

	Players.RespawnTime = Tuning.RESPAWN_TIME
	Lighting.ClockTime = 14
	-- A light haze, so the mountains and the far end of the runway fade into the distance.
	if Lighting:FindFirstChildOfClass("Atmosphere") == nil then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.28
		atmosphere.Offset = 0.15
		atmosphere.Color = Color3.fromRGB(226, 234, 244)
		atmosphere.Decay = Color3.fromRGB(150, 170, 195)
		atmosphere.Glare = 0
		atmosphere.Haze = 1.2
		atmosphere.Parent = Lighting
	end
end

function MapService.Start()
	watchForFalls()
end

return MapService
