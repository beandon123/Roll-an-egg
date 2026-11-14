-- Moves players around the map: to the hub, to the start of a zone, to the end cliff, to another player.
-- Used by the admin panel and the Model Showroom's way back to the hub. (Zone teleport pads, bought with coins, will
-- use it too once they are built.)
--
-- The map streams in around players (StreamingEnabled), so a teleport first asks for the area at the destination
-- to be sent to the player, then moves the character, so they do not land where the floor has not loaded yet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Runway = require(Shared.Runway)
local Zones = require(Shared.Config.Zones)

local RunwayService = require(script.Parent.RunwayService)

-- How high above the ground a character's HumanoidRootPart stands (R6 and R15 both stand about 3 studs up); a
-- teleport puts it a little higher and lets it drop.
local ROOT_HEIGHT = 3.5
-- Seconds to wait at most for the destination to stream in.
local STREAM_TIMEOUT = 3
-- Studs past the start of a zone where a zone teleport lands, clear of the eggs dropping in at its chute.
local ZONE_LANDING = 40
-- Studs before the end cliff where the cliff teleport lands.
local CLIFF_LANDING = 90

local DOWN_THE_RUNWAY = Vector3.new(0, 0, 1)

local TeleportService = {}

local function getCharacter(player: Player): (Model?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return character, root
end

-- Stands a player's character with its feet at `feet`, facing `facing` (a direction; only its heading counts).
-- Takes them off any egg they are riding first. Returns whether there was a living character to move.
function TeleportService.To(player: Player, feet: Vector3, facing: Vector3?): boolean
	local character, root = getCharacter(player)
	if character == nil or root == nil then
		return false
	end
	RunwayService.Dismount(player)

	-- Not every place streams (and the test stand-in has no streaming at all), so a failure here is not fatal.
	pcall(function()
		player:RequestStreamAroundAsync(feet, STREAM_TIMEOUT)
	end)
	-- The player may have left or died while that waited.
	character, root = getCharacter(player)
	if character == nil or root == nil then
		return false
	end

	local heading = if facing then Vector3.new(facing.X, 0, facing.Z) else Vector3.zero
	if heading.Magnitude < 1e-3 then
		heading = DOWN_THE_RUNWAY
	end
	local position = feet + Vector3.new(0, ROOT_HEIGHT, 0)
	character:PivotTo(CFrame.lookAt(position, position + heading.Unit))
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

-- To the spawn pad in the middle of the hub, facing down the runway.
function TeleportService.ToHub(player: Player): boolean
	return TeleportService.To(player, Vector3.new(0, Runway.BASE_Y + 1, -Runway.HUB_LENGTH / 2), DOWN_THE_RUNWAY)
end

-- To the middle of the runway just past the start of a zone, facing down the runway.
function TeleportService.ToZone(player: Player, zoneId: number): boolean
	if Zones.List[zoneId] == nil then
		return false
	end
	local z = Runway.zoneStartZ(zoneId) + ZONE_LANDING
	return TeleportService.To(player, Vector3.new(0, Runway.surfaceY(z), z), DOWN_THE_RUNWAY)
end

-- To the end of the runway, just before the cliff, facing it.
function TeleportService.ToCliff(player: Player): boolean
	local z = Runway.LENGTH - CLIFF_LANDING
	return TeleportService.To(player, Vector3.new(0, Runway.surfaceY(z), z), DOWN_THE_RUNWAY)
end

-- Next to another player, facing the same way they are. Returns false if either has no character.
function TeleportService.ToPlayer(player: Player, target: Player): boolean
	if target == player or target.Parent ~= Players then
		return false
	end
	local _, targetRoot = getCharacter(target)
	if targetRoot == nil then
		return false
	end
	local look = targetRoot.CFrame.LookVector
	local beside = targetRoot.CFrame.Position + targetRoot.CFrame.RightVector * 5
	return TeleportService.To(player, beside - Vector3.new(0, ROOT_HEIGHT - 0.5, 0), look)
end

return TeleportService
