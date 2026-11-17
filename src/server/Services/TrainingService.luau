-- The training stick: players roll on the stick in front of their pen to build Max Stamina (Config/Sticks; the
-- rules are in Logic/Training, the stand is built by Map/TrainingStand).
--
-- Using the "Start rolling" prompt on their own stand puts a player on top of the roller: their character is held
-- there (its root part anchored) facing the plaza, and every device poses it running on the spot and spins the
-- roller under it (the client's TrainingController). They stay as long as they like; jumping, the Stop button, dying
-- or leaving gets them off. Every rep adds Max Stamina for good and tells their device ("+1" over their head), and
-- now and then a "2x" bubble comes up on their screen: tapping it in time doubles the next reps.
--
-- Upgrading the stick (dollars from the sign's panel or the shop, Robux from the shop) is asked for through
-- ShopService, which calls UpgradeWithDollars and RaiseStick here.
--
-- Nothing a client sends is trusted: reps come from the server's clock alone, a bubble only counts if it is the one
-- the server put up and it is still in time, and only a stand's owner can get on it.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local NumberFormat = require(Shared.NumberFormat)
local Shop = require(Shared.Config.Shop)
local StickModels = require(Shared.StickModels)
local Sticks = require(Shared.Config.Sticks)

local Training = require(script.Parent.Parent.Logic.Training)
local TrainingStand = require(script.Parent.Parent.Map.TrainingStand)

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local MountService = require(script.Parent.MountService)
local PlotService = require(script.Parent.PlotService)
local RunwayService = require(script.Parent.RunwayService)

-- How far from their stand (studs, across the ground) a player may be when they get on; the prompt reaches 12.
local START_REACH = 18
-- Where a player is put down when they get off: in front of the trough, on the plaza side (stand studs: X inward).
local STEP_OFF = CFrame.new(-7.5, 3.2, 0) * CFrame.Angles(0, math.pi / 2, 0)
-- How often each owner's sign is checked against what it should say (their multipliers can change it).
local SIGN_CHECK_INTERVAL = 1

local ROBUX = utf8.char(0xE002)

local TrainingService = {}

type Trainer = {
	index: number,
	stand: Model,
	character: Model,
	root: BasePart,
	session: Training.Session,
	connections: { RBXScriptConnection },
}

local trainers: { [Player]: Trainer } = {}
-- What each owner's sign says now, so it is only rewritten when that changes.
local signKeys: { [Player]: string } = {}
-- Robux prices of the stick's tiers loaded from Roblox (Config/Shop's until then).
local robuxPrices: { [number]: number } = {}

local rng = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function money(amount: number): string
	return "$" .. NumberFormat.abbreviate(amount)
end

local function rate(perSecond: number): string
	return `+{NumberFormat.amount(perSecond)}/s`
end

local function liveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil, nil, nil
end

-- How far a character's root part is above the soles of its feet.
local function legHeight(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	-- R6 legs are 2 studs long, and R6 characters have no hip height.
	return root.Size.Y / 2 + 2
end

----------------------------------------------------------------------------------------------------------------
-- The stand and its sign

-- What a player's sign says: the next tier and what it costs, or that the stick is as good as it gets.
local function signText(data): TrainingStand.SignText
	local level = Training.levelOf(data)
	local multiplier = Training.multiplier(data)
	local now_ = Sticks.perSecond(level) * multiplier
	local nextTier = Sticks.nextTier(level)
	if nextTier == nil then
		local tier = Sticks.tier(level)
		return {
			title = "MAX LEVEL!",
			level = level,
			name = tier.name,
			color = tier.color,
			rates = `{rate(now_)} Stamina`,
		}
	end
	local robux = robuxPrices[nextTier.level] or Shop.StickLevels[nextTier.level].robux
	return {
		title = "UPGRADE STICK",
		level = nextTier.level,
		name = nextTier.name,
		color = nextTier.color,
		rates = `{rate(now_)}  ➜  {rate(Sticks.perSecond(nextTier.level) * multiplier)} Stamina`,
		dollars = money(nextTier.price),
		robux = `{ROBUX} {robux}`,
	}
end

-- Brings a player's stand up to date with their data: the tier shown, and the sign.
function TrainingService.RefreshStand(player: Player)
	local stand, index = PlotService.GetStand(player)
	local data = DataService.GetData(player)
	if stand == nil or index == nil or data == nil then
		return
	end
	TrainingStand.setLevel(stand, index, Training.levelOf(data))
	local text = signText(data)
	local key = `{text.title}|{text.name}|{text.rates}|{text.dollars}|{text.robux}`
	if signKeys[player] ~= key then
		signKeys[player] = key
		TrainingStand.setSign(stand, text)
	end
	-- What others' devices show over the rider's head for each rep.
	stand:SetAttribute("RepGain", Training.gainPerRep(data))
end

----------------------------------------------------------------------------------------------------------------
-- Getting on and off

local function endConnections(trainer: Trainer)
	for _, connection in trainer.connections do
		connection:Disconnect()
	end
	table.clear(trainer.connections)
end

-- Takes a player off their stick. `reason` is what their device is told: "Stopped" (they got off), "Died", "Left"
-- or "Moved" (teleported away). Unless their character died or is going, it is put down in front of the trough.
function TrainingService.Stop(player: Player, reason: string)
	local trainer = trainers[player]
	if trainer == nil then
		return
	end
	trainers[player] = nil
	endConnections(trainer)
	trainer.stand:SetAttribute("Rider", 0)
	trainer.stand:SetAttribute("BoostUntil", 0)
	player:SetAttribute("TrainingStick", nil)

	local root = trainer.root
	if root.Parent ~= nil then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
		if reason == "Stopped" then
			trainer.character:PivotTo(StickModels.standCFrame(trainer.index) * STEP_OFF)
		end
		-- The character is the player's to move again.
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end
	MountService.BringBack(player)
	if player.Parent == Players then
		Net.TrainingEnded:FireClient(player, reason)
	end
end

-- Stands the player's character on top of their stick's roller, facing the plaza.
local function seat(trainer: Trainer, level: number)
	local humanoid = trainer.character:FindFirstChildOfClass("Humanoid")
	local legs = if humanoid then legHeight(humanoid, trainer.root) else 3
	trainer.root.Anchored = true
	trainer.root.AssemblyLinearVelocity = Vector3.zero
	trainer.character:PivotTo(StickModels.riderCFrame(trainer.index, level, legs))
end

local function tellStarted(player: Player, trainer: Trainer)
	Net.TrainingStarted:FireClient(player, {
		level = trainer.session.level,
		plot = trainer.index,
		startedAt = trainer.session.startedAt,
	})
end

-- The player used the prompt on their own stand (PlotService checks it is theirs).
local function start(player: Player, index: number)
	if trainers[player] then
		return
	end
	local data = DataService.GetData(player)
	local stand, ownIndex = PlotService.GetStand(player)
	local character, humanoid, root = liveCharacter(player)
	if data == nil or stand == nil or ownIndex ~= index or character == nil or humanoid == nil or root == nil then
		return
	end
	if RunwayService.IsRiding(player) then
		return
	end
	local spot = StickModels.standCFrame(index).Position
	local offset = root.CFrame.Position - spot
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > START_REACH then
		return
	end

	-- Off their pet first, so the character stands at its own height.
	MountService.PutAway(player)
	local level = Training.levelOf(data)
	local trainer: Trainer = {
		index = index,
		stand = stand,
		character = character,
		root = root,
		session = Training.start(level, now(), function()
			return rng:NextNumber()
		end),
		connections = {},
	}
	trainers[player] = trainer
	TrainingService.RefreshStand(player)
	seat(trainer, level)
	stand:SetAttribute("Rider", player.UserId)
	stand:SetAttribute("BoostUntil", 0)
	player:SetAttribute("TrainingStick", index)

	table.insert(
		trainer.connections,
		humanoid.Died:Connect(function()
			TrainingService.Stop(player, "Died")
		end)
	)
	table.insert(
		trainer.connections,
		player.CharacterRemoving:Connect(function()
			TrainingService.Stop(player, "Died")
		end)
	)
	tellStarted(player, trainer)
end

-- Whether the player is rolling on their stick now.
function TrainingService.IsTraining(player: Player): boolean
	return trainers[player] ~= nil
end

----------------------------------------------------------------------------------------------------------------
-- Rolling

local function stepTrainer(player: Player, trainer: Trainer, time: number)
	local data = DataService.GetData(player)
	local character, _, root = liveCharacter(player)
	if data == nil or character ~= trainer.character or root ~= trainer.root then
		TrainingService.Stop(player, "Died")
		return
	end
	if not root.Anchored then
		-- Something else let go of the character (it was moved or flown away).
		TrainingService.Stop(player, "Moved")
		return
	end

	local result = Training.step(trainer.session, time)
	if #result.reps > 0 then
		for _, boosted in result.reps do
			Net.TrainingRep:FireClient(player, Training.addRep(data, boosted), boosted)
		end
		RunwayService.RefreshMaxStamina(player)
	end
	if result.bubble then
		Net.TrainingBubble:FireClient(player, result.bubble.id, result.bubble.endsAt)
	end
end

local function onClaimBoost(player: Player, bubbleId: unknown)
	local trainer = trainers[player]
	if trainer == nil or typeof(bubbleId) ~= "number" or bubbleId ~= bubbleId then
		return
	end
	if Training.claim(trainer.session, bubbleId :: number, now()) then
		trainer.stand:SetAttribute("BoostUntil", trainer.session.boostUntil)
		Net.TrainingBoost:FireClient(player, trainer.session.boostUntil)
	end
end

local function onStop(player: Player)
	TrainingService.Stop(player, "Stopped")
end

----------------------------------------------------------------------------------------------------------------
-- Upgrades (asked for through ShopService)

local function upgraded(player: Player, data): string
	local tier = Sticks.tier(Training.levelOf(data))
	TrainingService.RefreshStand(player)
	local trainer = trainers[player]
	if trainer then
		-- The new roller is a different size: stand on top of it.
		trainer.session.level = tier.level
		seat(trainer, tier.level)
		tellStarted(player, trainer)
	end
	return `Your stick is now a {tier.name}! +{NumberFormat.amount(Training.gainPerRep(data))} Stamina a roll`
end

-- Buys the next tier of the player's stick with dollars. Returns whether it worked and what to tell them.
function TrainingService.UpgradeWithDollars(player: Player): (boolean, string)
	local data = DataService.GetData(player)
	if data == nil then
		return false, "Your data has not loaded yet."
	end
	local ok, result, price = Training.upgrade(data)
	if ok then
		InventoryService.RefreshDollars(player)
		return true, upgraded(player, data)
	elseif result == "NotEnoughDollars" and price then
		local nextTier = Sticks.nextTier(Training.levelOf(data)) :: Sticks.Tier
		return false, `The {nextTier.name} costs {money(price)}: you have {money(math.floor(data.Dollars))}`
	end
	return false, "Your stick is as good as it gets!"
end

-- Raises the player's stick a tier without dollars (bought with Robux). Returns what to tell them, or nil if it is
-- already as good as it gets.
function TrainingService.RaiseStick(player: Player): string?
	local data = DataService.GetData(player)
	if data == nil then
		error("data not loaded")
	end
	if not Training.raise(data) then
		return nil
	end
	return upgraded(player, data)
end

-- Sets the player's stick to a tier (the admin panel).
function TrainingService.SetLevel(player: Player, level: number): string
	local data = DataService.GetData(player)
	if data == nil then
		return "Your data has not loaded yet."
	end
	data.StickLevel = Sticks.tier(level).level
	upgraded(player, data)
	local tier = Sticks.tier(data.StickLevel)
	return `Stick: level {tier.level}, {tier.name}.`
end

-- Forgets the Max Stamina the player has trained (the admin panel).
function TrainingService.ClearTrained(player: Player)
	local data = DataService.GetData(player)
	if data then
		data.TrainedStamina = 0
		RunwayService.RefreshMaxStamina(player)
	end
end

----------------------------------------------------------------------------------------------------------------

-- Asks Roblox for the real Robux price of each tier with a product ID, so the signs match the shop.
local function loadPrices()
	for level, stickLevel in Shop.StickLevels do
		if stickLevel.productId ~= 0 then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(stickLevel.productId, Enum.InfoType.Product)
			end)
			if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
				robuxPrices[level] = info.PriceInRobux
			end
		end
	end
	for _, player in Players:GetPlayers() do
		signKeys[player] = nil
		TrainingService.RefreshStand(player)
	end
end

function TrainingService.Init()
	PlotService.OnTrainPressed(start)
	Net.StopTraining.OnServerEvent:Connect(onStop)
	Net.ClaimTrainingBoost.OnServerEvent:Connect(onClaimBoost)

	DataService.OnLoaded(function(player)
		TrainingService.RefreshStand(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		TrainingService.Stop(player, "Left")
		signKeys[player] = nil
	end)
end

function TrainingService.Start()
	local lastSignCheck = 0
	RunService.Heartbeat:Connect(function()
		local time = now()
		for player, trainer in trainers do
			stepTrainer(player, trainer, time)
		end
		-- Signs follow the owner's multipliers (a new trail, a stamina doubling) without every service calling here.
		if time - lastSignCheck >= SIGN_CHECK_INTERVAL then
			lastSignCheck = time
			for _, player in Players:GetPlayers() do
				TrainingService.RefreshStand(player)
			end
		end
	end)
	task.spawn(loadPrices)
end

return TrainingService
