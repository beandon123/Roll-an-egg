-- Riding pets: a player picks one of their pets to ride (the Ride button on its card) and it appears under them,
-- carrying them at its own speed (Shared/PetWorth: rarer pets, and Silver, Gold and Rainbow ones, are faster).
--
-- The pet is welded under the character's root part, so wherever the player runs it comes along, on every screen.
-- The character is lifted (Humanoid.HipHeight) so the pet's feet are on the ground and the rider sits on its back,
-- and runs at the pet's speed (Humanoid.WalkSpeed). Clients make it walk when its rider moves and seat the rider
-- (MountController).
--
-- Jumping from a pet onto an egg sends the pet away; it comes back a few seconds after the player leaves the egg.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local PetRig = require(Shared.PetRig)
local PetWorth = require(Shared.PetWorth)

local DataService = require(script.Parent.DataService)
local Hatchery = require(script.Parent.Parent.Logic.Hatchery)

-- How far above the pet's seat the rider's root part sits.
local SEAT_RISE = 1.5

local MountService = {}

type Riding = {
	-- The player wants to be on their pet (they pressed Ride and have not got off).
	wants: boolean,
	-- On an egg, so the pet is away for now.
	onEgg: boolean,
	model: Model?,
	-- The humanoid's own numbers, put back when the pet goes.
	hipHeight: number,
	walkSpeed: number,
	-- Bumped whenever the pet is sent away, so a pending return can tell it is out of date.
	token: number,
}

local riding: { [Player]: Riding } = {}
local folder: Folder

local function stateOf(player: Player): Riding
	local state = riding[player]
	if state == nil then
		state = { wants = false, onEgg = false, model = nil, hipHeight = 0, walkSpeed = 16, token = 0 }
		riding[player] = state
	end
	return state
end

local function humanoidAndRoot(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function tell(player: Player, uid: string, speed: number)
	Net.MountChanged:FireClient(player, uid, speed)
end

-- Sends the pet away (if it is out) and puts the rider back on their own feet.
local function unsummon(player: Player)
	local state = stateOf(player)
	state.token += 1
	if state.model then
		state.model:Destroy()
		state.model = nil
		local humanoid = humanoidAndRoot(player)
		if humanoid then
			humanoid.HipHeight = state.hipHeight
			humanoid.WalkSpeed = state.walkSpeed
		end
	end
	tell(player, "", 0)
end

-- Brings the player's chosen pet out under them.
local function summon(player: Player)
	local state = stateOf(player)
	local data = DataService.GetData(player)
	local pet = data and Hatchery.mount(data)
	local humanoid, root = humanoidAndRoot(player)
	if pet == nil or humanoid == nil or root == nil or state.onEgg then
		return
	end
	if state.model then
		unsummon(player)
	end
	local model = PetRig.build(pet.kind, pet.variant)
	if model == nil then
		return
	end
	local petRoot = model.PrimaryPart :: BasePart
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.Massless = true
		end
	end
	local seat = (model:GetAttribute("SeatOffset") or Vector3.zero) :: Vector3
	local groundOffset = (model:GetAttribute("GroundOffset") or 0) :: number
	-- The pet's seat just under the rider, facing the way they face.
	petRoot.CFrame = root.CFrame * CFrame.new(-seat - Vector3.new(0, SEAT_RISE, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Name = "MountWeld"
	weld.Part0 = root
	weld.Part1 = petRoot
	weld.Parent = petRoot
	model.Name = pet.kind
	model:SetAttribute("Rider", player.UserId)
	model.Parent = folder

	state.model = model
	state.hipHeight = humanoid.HipHeight
	state.walkSpeed = humanoid.WalkSpeed
	-- High enough that the pet's feet touch the ground with the rider on its back.
	humanoid.HipHeight = math.max(state.hipHeight, groundOffset + seat.Y + SEAT_RISE - root.Size.Y / 2)
	local speed = PetWorth.mountSpeed(pet)
	humanoid.WalkSpeed = speed
	tell(player, pet.uid, speed)
end

-- The player asked to ride a pet (its uid), or to get off (""). Riding a pet chooses it as the one they ride.
function MountService.Ride(player: Player, uid: string)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	local state = stateOf(player)
	if uid == "" then
		state.wants = false
		unsummon(player)
		return
	end
	if not Hatchery.setMount(data, uid) then
		return
	end
	state.wants = true
	summon(player)
end

-- Whether the player is on their pet right now.
function MountService.IsMounted(player: Player): boolean
	return stateOf(player).model ~= nil
end

-- After the player's pets change (one was sold): sends away a pet they no longer have.
function MountService.Refresh(player: Player)
	local data = DataService.GetData(player)
	if data and Hatchery.mount(data) == nil then
		stateOf(player).wants = false
		unsummon(player)
	end
end

-- Called by RunwayService when the player gets on an egg: the pet goes away while they ride it.
function MountService.OnRideStarted(player: Player)
	local state = stateOf(player)
	state.onEgg = true
	if state.model then
		state.model:Destroy()
		state.model = nil
		local humanoid = humanoidAndRoot(player)
		if humanoid then
			humanoid.HipHeight = state.hipHeight
			humanoid.WalkSpeed = state.walkSpeed
		end
		tell(player, "", 0)
	end
end

-- Called by RunwayService when the player's egg ride ends: the pet comes back a few seconds later.
function MountService.OnRideEnded(player: Player)
	local state = stateOf(player)
	state.onEgg = false
	if not state.wants then
		return
	end
	state.token += 1
	local token = state.token
	task.delay(Economy.RESUMMON_DELAY, function()
		if riding[player] == state and state.token == token and state.wants and not state.onEgg then
			summon(player)
		end
	end)
end

function MountService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Mounts"
	folder.Parent = Workspace

	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			local state = stateOf(player)
			-- The old character's pet went with it; a new character gets it back shortly.
			if state.model then
				state.model:Destroy()
				state.model = nil
			end
			state.onEgg = false
			if state.wants then
				state.token += 1
				local token = state.token
				task.delay(1, function()
					if state.token == token and state.wants then
						summon(player)
					end
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local state = riding[player]
		if state and state.model then
			state.model:Destroy()
		end
		riding[player] = nil
	end)
end

return MountService
