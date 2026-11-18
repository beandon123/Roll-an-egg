-- Builds the training stick stand in front of each plot (Config/Sticks; where it stands is in Shared/Plots, and the
-- placement maths in Shared/StickModels). A stand is a Model named "TrainingStick" in the plot:
--
--     Base       a wooden water trough on a stone plinth, with a glowing strip round its foot in the tier's colour,
--                a lily pad and a rubber duck
--     Frame      the two posts holding the axle; they grow with the tier, from timber to steel, marble and crystal
--     Roller     the tier's roller (Shared/StickModels), its parts welded to its anchored Root, so each client turns
--                the whole roller by turning the Root alone
--     Seat       an invisible part on top of the roller: the "Start rolling" prompt
--     Fx         invisible parts carrying the splashes (on while someone rolls) and the 2x boost's sparkles and light
--     Nameplate  the tier's name and level, floating above
--     Sign       a signboard at the stand's front corner: what the next tier is, what it gives, and what it costs, with
--                an "Upgrade" prompt that opens the upgrade panel on the owner's device
--
-- Attributes on the stand: Level (the tier shown), Rider (the UserId of the player rolling on it, 0 for nobody), and
-- BoostUntil (server time a 2x boost ends). Clients read them to spin the roller and play its effects
-- (TrainingController). The server builds the stands (PlotService) and TrainingService keeps them up to date.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Plots = require(Shared.Plots)
local StickModels = require(Shared.StickModels)
local Sticks = require(Shared.Config.Sticks)

local TrainingStand = {}

TrainingStand.NAME = "TrainingStick"

-- The trough: its outside size (inward, along), how high its walls stand, and how thick they are.
local TROUGH_X, TROUGH_Z = 9, 15.4
local WALL_TOP = 1.45
local WALL = 0.8
local PLINTH_HEIGHT = 0.4

local WOOD = { 156, 108, 66 }
local WOOD_LIGHT = { 196, 146, 94 }
local WOOD_DARK = { 116, 80, 50 }
local IRON = { 66, 68, 78 }
local STONE = { 112, 116, 128 }
local WATER = { 74, 178, 232 }

-- What the sign says (TrainingService fills it in): the title, the tier it names (its level, name and colour), a
-- line of rates, and the two prices (nil hides a price).
export type SignText = {
	title: string,
	level: number,
	name: string,
	color: { number },
	rates: string,
	dollars: string?,
	robux: string?,
}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function newPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: { number }, material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material or Enum.Material.SmoothPlastic
	part.Size = size
	part.CFrame = cframe
	part.Color = rgb(color)
	part.Parent = parent
	return part
end

-- An upright cylinder.
local function pillar(parent: Instance, name: string, diameter: number, height: number, cframe: CFrame, color, material)
	local part = newPart(parent, name, Vector3.new(height, diameter, diameter), cframe, color, material)
	part.Shape = Enum.PartType.Cylinder
	part.CFrame = cframe * CFrame.Angles(0, 0, math.pi / 2)
	return part
end

-- A cylinder lying along the stand's Z axis (the axle's way).
local function alongZ(parent: Instance, name: string, diameter: number, length: number, cframe: CFrame, color, material)
	local part = newPart(parent, name, Vector3.new(length, diameter, diameter), cframe, color, material)
	part.Shape = Enum.PartType.Cylinder
	part.CFrame = cframe * CFrame.Angles(0, math.pi / 2, 0)
	return part
end

local function invisible(part: BasePart): BasePart
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	return part
end

local function label(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextScaled = true
	for key, value in props do
		(text :: any)[key] = value
	end
	text.Parent = parent
	return text
end

local function corner(parent: Instance, radius: UDim)
	local round = Instance.new("UICorner")
	round.CornerRadius = radius
	round.Parent = parent
end

local function outline(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

local function textOutline(parent: Instance, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 16, 24)
	stroke.Thickness = thickness
	stroke.Parent = parent
end

----------------------------------------------------------------------------------------------------------------
-- The trough

local function buildBase(stand: Model, at: CFrame)
	local base = Instance.new("Folder")
	base.Name = "Base"
	base.Parent = stand
	local halfX, halfZ = TROUGH_X / 2, TROUGH_Z / 2

	-- A stone plinth a little bigger than the trough, then the trough's floor, seen through the water.
	newPart(
		base,
		"Plinth",
		Vector3.new(TROUGH_X + 1, PLINTH_HEIGHT, TROUGH_Z + 1),
		at * CFrame.new(0, PLINTH_HEIGHT / 2, 0),
		STONE,
		Enum.Material.Slate
	)
	newPart(
		base,
		"Floor",
		Vector3.new(TROUGH_X - WALL, 0.1, TROUGH_Z - WALL),
		at * CFrame.new(0, PLINTH_HEIGHT + 0.05, 0),
		{ 46, 112, 156 },
		Enum.Material.Pebble
	)

	-- Plank walls with a broad rail along their tops.
	local wallHeight = WALL_TOP - PLINTH_HEIGHT
	for _, side in { -1, 1 } do
		newPart(
			base,
			"Wall",
			Vector3.new(WALL, wallHeight, TROUGH_Z - 0.6),
			at * CFrame.new(side * (halfX - WALL / 2), PLINTH_HEIGHT + wallHeight / 2, 0),
			WOOD,
			Enum.Material.WoodPlanks
		)
		newPart(
			base,
			"Wall",
			Vector3.new(TROUGH_X - 0.6, wallHeight, WALL),
			at * CFrame.new(0, PLINTH_HEIGHT + wallHeight / 2, side * (halfZ - WALL / 2)),
			WOOD,
			Enum.Material.WoodPlanks
		)
		newPart(
			base,
			"Rail",
			Vector3.new(WALL + 0.3, 0.22, TROUGH_Z - 0.6),
			at * CFrame.new(side * (halfX - WALL / 2), WALL_TOP + 0.11, 0),
			WOOD_LIGHT,
			Enum.Material.Wood
		)
		newPart(
			base,
			"Rail",
			Vector3.new(TROUGH_X - 0.6, 0.22, WALL + 0.3),
			at * CFrame.new(0, WALL_TOP + 0.11, side * (halfZ - WALL / 2)),
			WOOD_LIGHT,
			Enum.Material.Wood
		)
		-- Iron straps round the long walls.
		for _, z in { -halfZ * 0.5, halfZ * 0.5 } do
			newPart(
				base,
				"Strap",
				Vector3.new(WALL + 0.1, wallHeight + 0.02, 0.3),
				at * CFrame.new(side * (halfX - WALL / 2), PLINTH_HEIGHT + wallHeight / 2, z),
				IRON,
				Enum.Material.Metal
			)
		end
	end
	-- Round corner posts.
	for _, cornerX in { -1, 1 } do
		for _, cornerZ in { -1, 1 } do
			pillar(
				base,
				"Corner",
				1.2,
				WALL_TOP + 0.35 - PLINTH_HEIGHT,
				at * CFrame.new(cornerX * (halfX - 0.5), (WALL_TOP + 0.35 + PLINTH_HEIGHT) / 2, cornerZ * (halfZ - 0.5)),
				WOOD_DARK,
				Enum.Material.Wood
			)
		end
	end

	-- The water.
	local water = newPart(
		base,
		"Water",
		Vector3.new(TROUGH_X - WALL * 2 + 0.1, 0.2, TROUGH_Z - WALL * 2 + 0.1),
		at * CFrame.new(0, Sticks.WATER_HEIGHT - 0.1, 0),
		WATER,
		Enum.Material.Glass
	)
	water.Transparency = 0.3
	water.Reflectance = 0.25
	water.CanCollide = false

	-- A lily pad with a flower, and a rubber duck bobbing in the corners.
	local pad = at * CFrame.new(2.6, Sticks.WATER_HEIGHT + 0.03, 5.2)
	pillar(base, "LilyPad", 1.5, 0.06, pad, { 92, 176, 74 })
	newPart(base, "Flower", Vector3.new(0.34, 0.24, 0.34), pad * CFrame.new(0.2, 0.12, 0.1), { 255, 160, 200 })
	local duck = at * CFrame.new(-2.5, Sticks.WATER_HEIGHT, -5.4) * CFrame.Angles(0, math.rad(35), 0)
	local yellow = { 255, 214, 60 }
	local body = newPart(base, "DuckBody", Vector3.one * 0.9, duck * CFrame.new(0, 0.28, 0), yellow)
	body.Shape = Enum.PartType.Ball
	local head = newPart(base, "DuckHead", Vector3.one * 0.56, duck * CFrame.new(0, 0.86, -0.26), yellow)
	head.Shape = Enum.PartType.Ball
	newPart(base, "DuckBeak", Vector3.new(0.26, 0.1, 0.26), duck * CFrame.new(0, 0.8, -0.58), { 255, 140, 40 })
	for _, side in { -1, 1 } do
		newPart(
			base,
			"DuckEye",
			Vector3.new(0.08, 0.1, 0.06),
			duck * CFrame.new(side * 0.15, 0.95, -0.5),
			{ 30, 24, 20 }
		)
	end
	newPart(base, "DuckTail", Vector3.new(0.3, 0.24, 0.24), duck * CFrame.new(0, 0.5, 0.42), yellow)

	-- The glowing strip round the plinth's foot, in the tier's colour (setLevel colours it).
	local outX, outZ = TROUGH_X / 2 + 0.56, TROUGH_Z / 2 + 0.56
	for _, side in { -1, 1 } do
		local glowX = newPart(
			base,
			"Glow",
			Vector3.new(0.14, 0.16, TROUGH_Z + 1.26),
			at * CFrame.new(side * outX, 0.12, 0),
			{ 255, 255, 255 },
			Enum.Material.Neon
		)
		glowX.CanCollide = false
		local glowZ = newPart(
			base,
			"Glow",
			Vector3.new(TROUGH_X + 1.26, 0.16, 0.14),
			at * CFrame.new(0, 0.12, side * outZ),
			{ 255, 255, 255 },
			Enum.Material.Neon
		)
		glowZ.CanCollide = false
	end
end

----------------------------------------------------------------------------------------------------------------
-- The posts, which change with the tier

-- How a tier's posts look: timber for the wooden rollers, steel for the pipe and girder, marble for the column,
-- and dark crystal for the last.
local function postStyle(level: number)
	if level <= 4 then
		return { body = WOOD_DARK, cap = WOOD_LIGHT, material = Enum.Material.Wood, capMaterial = Enum.Material.Wood }
	elseif level <= 6 then
		return {
			body = { 120, 126, 140 },
			cap = { 74, 78, 90 },
			material = Enum.Material.DiamondPlate,
			capMaterial = Enum.Material.Metal,
		}
	elseif level == 7 then
		return {
			body = { 240, 236, 228 },
			cap = { 240, 186, 64 },
			material = Enum.Material.Marble,
			capMaterial = Enum.Material.Metal,
		}
	end
	return {
		body = { 44, 40, 70 },
		cap = { 150, 255, 245 },
		material = Enum.Material.Slate,
		capMaterial = Enum.Material.Neon,
	}
end

local function buildFrame(stand: Model, at: CFrame, level: number)
	local old = stand:FindFirstChild("Frame")
	if old then
		old:Destroy()
	end
	local frame = Instance.new("Folder")
	frame.Name = "Frame"
	frame.Parent = stand

	local tier = Sticks.tier(level)
	local style = postStyle(level)
	local axle = Sticks.axleHeight(level)
	local top = axle + 0.9
	for _, side in { -1, 1 } do
		local z = side * Sticks.POST_SPAN / 2
		local height = top - WALL_TOP
		newPart(
			frame,
			"Post",
			Vector3.new(1.6, height, 1.2),
			at * CFrame.new(0, WALL_TOP + height / 2, z),
			style.body,
			style.material
		)
		newPart(
			frame,
			"Foot",
			Vector3.new(2.5, 0.3, 1.5),
			at * CFrame.new(0, WALL_TOP + 0.37, z),
			style.cap,
			style.capMaterial
		)
		newPart(
			frame,
			"Cap",
			Vector3.new(1.95, 0.4, 1.5),
			at * CFrame.new(0, top + 0.2, z),
			style.cap,
			style.capMaterial
		)
		-- The bearing the axle turns in, ringed in the tier's colour.
		alongZ(frame, "Bearing", 1.2, 1.4, at * CFrame.new(0, axle, z), IRON, Enum.Material.Metal)
		local ring =
			alongZ(frame, "BearingRing", 0.85, 1.46, at * CFrame.new(0, axle, z), tier.color, Enum.Material.Neon)
		ring.CanCollide = false
		-- Timber posts get braces down to the rail.
		if level <= 4 then
			for _, brace in { -1, 1 } do
				newPart(
					frame,
					"Brace",
					Vector3.new(0.3, 1.5, 0.3),
					at * CFrame.new(brace * 1.1, WALL_TOP + 0.8, z) * CFrame.Angles(0, 0, brace * 0.6),
					style.body,
					style.material
				)
			end
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- The roller

-- Puts a tier's roller on the stand: its parts welded to its anchored Root, so turning the Root turns it all.
local function placeRoller(stand: Model, index: number, level: number)
	local old = stand:FindFirstChild("Roller")
	if old then
		old:Destroy()
	end
	local roller = StickModels.buildRoller(level)
	roller.Name = "Roller"
	roller:PivotTo(StickModels.axleCFrame(index, level))
	local root = roller.PrimaryPart :: BasePart
	for _, part in roller:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part.Anchored = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	-- The roller streams in whole, so a client never turns half of it.
	roller.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	roller.Parent = stand
end

----------------------------------------------------------------------------------------------------------------
-- The sign

local function buildSign(stand: Model, at: CFrame)
	local sign = Instance.new("Model")
	sign.Name = "Sign"
	sign.Parent = stand

	local offsetIn = Plots.STICK_SIGN_SPOT[1] - Plots.STICK_SPOT[1]
	local offsetAlong = Plots.STICK_SIGN_SPOT[2] - Plots.STICK_SPOT[2]
	-- Facing out to the plaza (the stand's -X), turned a little towards the gate (+Z).
	local spot = at * CFrame.new(offsetIn, 0, offsetAlong) * CFrame.Angles(0, math.pi / 2 + Plots.STICK_SIGN_TURN, 0)

	local post =
		newPart(sign, "Post", Vector3.new(0.6, 2.6, 0.6), spot * CFrame.new(0, 1.3, 0.3), WOOD_DARK, Enum.Material.Wood)
	sign.PrimaryPart = post
	newPart(
		sign,
		"Backing",
		Vector3.new(6.2, 4.2, 0.3),
		spot * CFrame.new(0, 4.3, 0.35),
		{ 46, 30, 22 },
		Enum.Material.Wood
	)
	local board = newPart(sign, "Board", Vector3.new(5.9, 3.9, 0.3), spot * CFrame.new(0, 4.3, 0.1), { 26, 30, 48 })

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.Parent = board

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(22, 26, 42)
	card.Parent = gui
	corner(card, UDim.new(0, 26))
	outline(card, Color3.new(1, 1, 1), 8)

	label(card, "Title", {
		Position = UDim2.fromScale(0.06, 0.05),
		Size = UDim2.fromScale(0.88, 0.2),
		Text = "UPGRADE STICK",
	})

	local nextRow = Instance.new("Frame")
	nextRow.Name = "Next"
	nextRow.BackgroundTransparency = 1
	nextRow.Position = UDim2.fromScale(0.06, 0.28)
	nextRow.Size = UDim2.fromScale(0.88, 0.22)
	nextRow.Parent = card
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.fromScale(0, 0.5)
	badge.Size = UDim2.fromScale(0.16, 1)
	badge.BackgroundColor3 = Color3.new(1, 1, 1)
	badge.Parent = nextRow
	corner(badge, UDim.new(0.5, 0))
	outline(badge, Color3.new(1, 1, 1), 4)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = badge
	label(badge, "Level", { Size = UDim2.fromScale(1, 1), Text = "2" })
	local name = label(nextRow, "TierName", {
		Position = UDim2.fromScale(0.21, 0),
		Size = UDim2.fromScale(0.79, 1),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	textOutline(name, 3)

	label(card, "Rates", {
		Position = UDim2.fromScale(0.06, 0.53),
		Size = UDim2.fromScale(0.88, 0.13),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(150, 255, 120),
	})

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Position = UDim2.fromScale(0.06, 0.71)
	buttons.Size = UDim2.fromScale(0.88, 0.22)
	buttons.Parent = card
	for order, button in { { "Dollars", { 232, 58, 58 } }, { "Robux", { 150, 84, 236 } } } do
		local frame = Instance.new("Frame")
		frame.Name = button[1]
		frame.Position = UDim2.fromScale(if order == 1 then 0 else 0.53, 0)
		frame.Size = UDim2.fromScale(0.47, 1)
		frame.BackgroundColor3 = rgb(button[2])
		frame.Parent = buttons
		corner(frame, UDim.new(0, 14))
		outline(frame, Color3.new(1, 1, 1), 3)
		local text = label(frame, "Price", {
			Position = UDim2.fromScale(0.06, 0.12),
			Size = UDim2.fromScale(0.88, 0.76),
			Text = "",
		})
		textOutline(text, 2)
	end

	-- The back of the board.
	local back = Instance.new("SurfaceGui")
	back.Name = "Back"
	back.Face = Enum.NormalId.Back
	back.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	back.PixelsPerStud = 30
	back.LightInfluence = 0
	back.Parent = board
	local backText = label(back, "Text", {
		Position = UDim2.fromScale(0.08, 0.3),
		Size = UDim2.fromScale(0.84, 0.4),
		Text = "TRAINING STICK",
	})
	textOutline(backText, 2)

	-- Opens the upgrade panel on the owner's device (TrainingController); the server buys nothing from it.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Upgrade"
	prompt.ActionText = "Upgrade"
	prompt.ObjectText = "Training Stick"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("StickSign", true)
	prompt.Parent = board
end

-- Shows what the sign says (see SignText).
function TrainingStand.setSign(stand: Model, text: SignText)
	local sign = stand:FindFirstChild("Sign")
	local board = sign and sign:FindFirstChild("Board")
	local face = board and board:FindFirstChild("Face")
	if face == nil then
		return
	end
	local card = (face :: any).Card
	card.Title.Text = text.title
	card.Next.TierName.Text = text.name
	card.Next.TierName.TextColor3 = rgb(text.color)
	card.Next.Badge.BackgroundColor3 = rgb(text.color)
	card.Next.Badge.Level.Text = tostring(text.level)
	card.Rates.Text = text.rates
	card.Buttons.Dollars.Visible = text.dollars ~= nil
	card.Buttons.Dollars.Price.Text = text.dollars or ""
	card.Buttons.Robux.Visible = text.robux ~= nil
	card.Buttons.Robux.Price.Text = text.robux or ""
end

----------------------------------------------------------------------------------------------------------------
-- The stand

-- Puts the stand's seat, nameplate and effects where a tier's roller needs them, and colours its glow.
local function fitToLevel(stand: Model, index: number, level: number)
	local tier = Sticks.tier(level)
	local at = StickModels.standCFrame(index)
	local axle = Sticks.axleHeight(level)
	local top = axle + Sticks.maxTop(level)

	local seat = stand:FindFirstChild("Seat") :: BasePart
	seat.CFrame = at * CFrame.new(0, top, 0)
	local prompt = seat:FindFirstChild("Train") :: ProximityPrompt
	prompt.ObjectText = `{tier.name}  (+{tier.perRep} Stamina a roll)`

	local splash = stand:FindFirstChild("SplashFx") :: BasePart
	splash.CFrame = at * CFrame.new(0, Sticks.WATER_HEIGHT + 0.05, 0)
	splash.Size = Vector3.new(tier.reach * 2, 0.1, tier.length)
	local boost = stand:FindFirstChild("BoostFx") :: BasePart
	boost.CFrame = at * CFrame.new(0, axle, 0)
	boost.Size = Vector3.new(tier.reach * 2, tier.reach * 2, tier.length)

	local plate = stand:FindFirstChild("Nameplate") :: BasePart
	plate.CFrame = at * CFrame.new(0, top + 7.4, 0)
	local gui = plate:FindFirstChild("Tag") :: BillboardGui
	local nameLabel = gui:FindFirstChild("TierName") :: TextLabel
	nameLabel.Text = tier.name
	nameLabel.TextColor3 = rgb(tier.color)
	local levelLabel = gui:FindFirstChild("TierLevel") :: TextLabel
	levelLabel.Text = `Lvl {tier.level} Training Stick`

	for _, glow in (stand:FindFirstChild("Base") :: Folder):GetChildren() do
		if glow.Name == "Glow" and glow:IsA("BasePart") then
			glow.Color = rgb(tier.color)
		end
	end
end

-- What the sign on a free plot's stand says.
TrainingStand.FREE_SIGN = {
	title = "TRAINING STICK",
	level = 1,
	name = Sticks.tier(1).name,
	color = Sticks.tier(1).color,
	rates = "Free plot",
	dollars = nil,
	robux = nil,
} :: SignText

-- Puts a plot's stand back as it is on a free plot: the first tier, nobody on it, and the free plot's sign.
function TrainingStand.reset(stand: Model, index: number)
	stand:SetAttribute("Rider", 0)
	stand:SetAttribute("BoostUntil", 0)
	TrainingStand.setLevel(stand, index, 1)
	TrainingStand.setSign(stand, TrainingStand.FREE_SIGN)
end

-- Builds a plot's stand, showing the first tier.
function TrainingStand.build(parent: Instance, index: number): Model
	local stand = Instance.new("Model")
	stand.Name = TrainingStand.NAME
	stand:SetAttribute("PlotIndex", index)
	stand:SetAttribute("Level", 1)
	stand:SetAttribute("Rider", 0)
	stand:SetAttribute("BoostUntil", 0)
	stand.Parent = parent

	local at = StickModels.standCFrame(index)
	buildBase(stand, at)
	stand.PrimaryPart = (stand:FindFirstChild("Base") :: Folder):FindFirstChild("Plinth") :: BasePart

	local seat = invisible(newPart(stand, "Seat", Vector3.new(2, 0.2, 2), at, { 255, 255, 255 }))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Train"
	prompt.ActionText = "Start rolling"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("TrainingStick", true)
	prompt.Parent = seat

	-- Splashes under the roller while someone rolls; sparkles and a light round it during a 2x boost. Each client
	-- switches them on and off (TrainingController).
	local splash = invisible(newPart(stand, "SplashFx", Vector3.one, at, { 255, 255, 255 }))
	local drops = Instance.new("ParticleEmitter")
	drops.Name = "Splash"
	drops.Texture = "rbxasset://textures/particles/smoke_main.dds"
	drops.Color = ColorSequence.new(Color3.fromRGB(235, 250, 255), Color3.fromRGB(150, 210, 255))
	drops.LightEmission = 0.3
	drops.Rate = 18
	drops.Lifetime = NumberRange.new(0.35, 0.6)
	drops.Speed = NumberRange.new(5, 9)
	drops.SpreadAngle = Vector2.new(25, 25)
	drops.EmissionDirection = Enum.NormalId.Top
	drops.Acceleration = Vector3.new(0, -45, 0)
	drops.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	drops.Transparency = NumberSequence.new(0.2, 1)
	drops.Enabled = false
	drops.Parent = splash

	local boost = invisible(newPart(stand, "BoostFx", Vector3.one, at, { 255, 255, 255 }))
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 170, 40))
	sparkles.LightEmission = 1
	sparkles.Rate = 40
	sparkles.Lifetime = NumberRange.new(0.5, 0.9)
	sparkles.Speed = NumberRange.new(2, 5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.RotSpeed = NumberRange.new(-180, 180)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Enabled = false
	sparkles.Parent = boost
	local light = Instance.new("PointLight")
	light.Name = "BoostLight"
	light.Color = Color3.fromRGB(255, 210, 90)
	light.Brightness = 2
	light.Range = 16
	light.Shadows = false
	light.Enabled = false
	light.Parent = boost

	local plate = invisible(newPart(stand, "Nameplate", Vector3.one, at, { 255, 255, 255 }))
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromScale(9, 2.4)
	tag.LightInfluence = 0
	tag.MaxDistance = 90
	tag.Parent = plate
	local tierName = label(tag, "TierName", { Size = UDim2.fromScale(1, 0.62), Text = "" })
	textOutline(tierName, 3)
	local levelLabel = label(tag, "TierLevel", {
		Position = UDim2.fromScale(0, 0.62),
		Size = UDim2.fromScale(1, 0.38),
		Font = Enum.Font.GothamBold,
		Text = "",
	})
	textOutline(levelLabel, 2)

	buildSign(stand, at)
	TrainingStand.reset(stand, index)
	return stand
end

-- Shows a tier on a plot's stand: its roller, its posts, and its name. Does nothing if it already shows it.
function TrainingStand.setLevel(stand: Model, index: number, level: number)
	level = Sticks.tier(level).level
	if stand:FindFirstChild("Roller") and stand:GetAttribute("Level") == level then
		return
	end
	stand:SetAttribute("Level", level)
	local at = StickModels.standCFrame(index)
	buildFrame(stand, at, level)
	placeRoller(stand, index, level)
	fitToLevel(stand, index, level)
end

return TrainingStand
