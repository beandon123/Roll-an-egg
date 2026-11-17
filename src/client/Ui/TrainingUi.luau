-- Everything on screen for the training stick (Config/Sticks), built with Fusion in the house style (Ui/Widgets):
--
--     hud        while rolling: a card at the bottom (the tier, what each roll gives, a Stop button), the 2x boost
--                bar, and the "2x" bubbles to tap
--     stickCard  "UPGRADE STICK!": the stick now and the next tier, turning in 3D, what the next one gives, and its
--                price in Robux and in dollars. In the shop's Featured section and in the upgrade panel
--     panel      the upgrade panel the sign beside the stick opens: the card, and all eight tiers in a row
--
-- Like the rest of the HUD these only read UiState; TrainingController fills it in and does what the buttons ask.
-- The 3D previews are turned by TrainingController each frame (TrainingUi.step).

local Load = require(script.Parent.Parent.Load)
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")
local Rarities = Load.shared("Config", "Rarities")
local Shop = Load.shared("Config", "Shop")
local StickModels = Load.shared("StickModels")
local Sticks = Load.shared("Config", "Sticks")
local Trails = Load.shared("Config", "Trails")

local Theme = require(script.Parent.Theme)
local UiState = require(script.Parent.UiState)
local Widgets = require(script.Parent.Widgets)

local Fusion = UiState.Fusion
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

local TrainingUi = {}

-- The card's sky, like a bright day over the plaza.
local SKY_LIGHT = Color3.fromRGB(132, 214, 255)
local SKY_DEEP = Color3.fromRGB(58, 140, 236)
local PANEL_DARK = Color3.fromRGB(26, 28, 36)
local BOOST_GOLD = Color3.fromRGB(255, 206, 60)
local BOOST_DEEP = Color3.fromRGB(255, 132, 30)
local STAMINA_BLUE = Color3.fromRGB(120, 220, 255)
local LOCKED_TINT = Color3.fromRGB(90, 96, 112)
-- The letters of "UPGRADE" on the card, each its own colour.
local RAINBOW = { "#FF5A6E", "#FF9F1C", "#FFD93D", "#5BE37D", "#4DB2FF", "#B57BFF", "#FF7AD9" }

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function rainbow(word: string): string
	local letters = {}
	for index = 1, #word do
		table.insert(
			letters,
			`<font color="{RAINBOW[(index - 1) % #RAINBOW + 1]}">{string.sub(word, index, index)}</font>`
		)
	end
	return table.concat(letters)
end

-- What a rep's Max Stamina is multiplied by: the player's stamina doublings and their trail.
local function multiplierOf(use): number
	local trail = Trails.ById[use(UiState.trailEquipped)]
	return use(UiState.staminaMultiplier) * (if trail then trail.stamina else 1)
end

local function abbreviate(value: number): string
	return NumberFormat.amount(value)
end

----------------------------------------------------------------------------------------------------------------
-- 3D previews of the tiers

type Preview = { viewport: ViewportFrame, camera: Camera, model: Model?, level: number, angle: number }
local previews: { Preview } = {}

local function fill(preview: Preview, level: number)
	if preview.model then
		preview.model:Destroy()
	end
	local model = StickModels.buildRoller(level)
	-- On its own, the long axle makes the roller look skewered.
	local axle = model:FindFirstChild("Axle")
	if axle then
		axle:Destroy()
	end
	model.Parent = preview.viewport
	preview.model = model
	preview.level = level
	local tier = Sticks.tier(level)
	local distance = tier.length * 1.05 + 4
	preview.camera.CFrame = CFrame.lookAt(Vector3.new(1, 0.62, 1.2).Unit * distance, Vector3.zero)
end

-- A ViewportFrame showing a tier's roller, turning slowly. `Level` may be a number or a Fusion state.
local function preview(scope, props)
	local camera = scope:New("Camera")({ FieldOfView = 34 })
	local viewport = scope:New("ViewportFrame")({
		Name = props.Name or "Preview",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		CurrentCamera = camera,
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -1.6, -0.6),
		ImageColor3 = props.ImageColor3,
		ZIndex = props.ZIndex,
		[Children] = { camera },
	})
	local entry: Preview = { viewport = viewport, camera = camera, model = nil, level = 0, angle = props.Angle or 0 }
	table.insert(previews, entry)
	local level = props.Level
	if typeof(level) == "number" then
		fill(entry, level)
	else
		fill(entry, Fusion.peek(level))
		scope:Observer(level):onChange(function()
			fill(entry, Fusion.peek(level))
		end)
	end
	return viewport
end

local function isShown(instance: Instance): boolean
	local current: Instance? = instance
	while current and current:IsA("GuiObject") do
		if not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

-- Turns the rollers in the previews that are on screen, and cycles the rainbow crystal's colours. Called every
-- frame by TrainingController.
function TrainingUi.step(deltaTime: number, clock: number)
	for _, entry in previews do
		local model = entry.model
		if model and model.Parent and isShown(entry.viewport) then
			entry.angle += deltaTime * 1.1
			model:PivotTo(StickModels.spin(entry.angle))
			if entry.level == Sticks.MAX_LEVEL then
				local color = Color3.fromHSV((clock * 0.15) % 1, 0.45, 1)
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") and part:GetAttribute("Rainbow") then
						part.Color = color
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------------------
-- The upgrade card

-- A small rounded chip: "LVL 3".
local function levelChip(scope, props)
	return scope:New("Frame")({
		Name = props.Name or "Level",
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0),
		Position = props.Position,
		Size = props.Size or UDim2.fromOffset(74, 26),
		Visible = props.Visible,
		BackgroundColor3 = props.Color,
		[Children] = {
			Widgets.round(scope),
			Widgets.stroke(scope, 2.5),
			Widgets.text(scope, {
				Name = "Label",
				Text = props.Text,
				TextColor3 = Theme.WHITE,
				TextSize = 17,
				Stroke = 2,
			}),
		},
	})
end

-- One side of the card: the roller of a tier turning in 3D, a glow behind it, its name and its level.
local function tierShowcase(scope, props)
	local level = props.Level
	local tier = scope:Computed(function(use)
		return Sticks.tier(use(level))
	end)
	return scope:New("Frame")({
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = props.Position,
		Size = UDim2.fromOffset(210, 176),
		Visible = props.Visible,
		BackgroundTransparency = 1,
		[Children] = {
			scope:New("Frame")({
				Name = "Glow",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.38),
				Size = UDim2.fromOffset(150, 120),
				BackgroundColor3 = Theme.WHITE,
				BackgroundTransparency = 0.6,
				[Children] = { Widgets.round(scope) },
			}),
			preview(scope, {
				Name = "Preview",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(210, 132),
				Level = level,
				Angle = props.Angle,
			}),
			Widgets.text(scope, {
				Name = "TierName",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 120),
				Size = UDim2.fromOffset(210, 30),
				Font = Theme.TITLE_FONT,
				Text = scope:Computed(function(use)
					return use(tier).name
				end),
				TextColor3 = Theme.WHITE,
				TextScaled = true,
				MaxTextSize = 28,
				Stroke = 3,
			}),
			levelChip(scope, {
				Position = UDim2.new(0.5, 0, 0, 150),
				Text = scope:Computed(function(use)
					return `LVL {use(tier).level}`
				end),
				Color = scope:Computed(function(use)
					return rgb(Rarities.Info[use(tier).rarity].color):Lerp(Color3.new(0, 0, 0), 0.15)
				end),
			}),
		},
	})
end

-- "<Robux icon> 99": the price from Roblox once loaded, Config/Shop's until then.
local function robuxText(scope, nextLevel)
	return scope:Computed(function(use)
		local level = use(nextLevel)
		local price = use(UiState.prices)["StickLevel" .. level]
		local stickLevel = Shop.StickLevels[level]
		return `{Theme.ROBUX} {price or (if stickLevel then stickLevel.robux else 0)}`
	end)
end

-- "UPGRADE STICK!": the stick the player has and the next tier, what it gives, and what it costs.
function TrainingUi.stickCard(scope, layoutOrder: number?)
	local level = UiState.stickLevel
	local isMax = scope:Computed(function(use)
		return use(level) >= Sticks.MAX_LEVEL
	end)
	local notMax = scope:Computed(function(use)
		return not use(isMax)
	end)
	local nextLevel = scope:Computed(function(use)
		return math.min(use(level) + 1, Sticks.MAX_LEVEL)
	end)

	return scope:New("Frame")({
		Name = "StickUpgrade",
		LayoutOrder = layoutOrder or 1,
		Size = UDim2.new(1, -8, 0, 318),
		BackgroundColor3 = Theme.WHITE,
		[Children] = {
			Widgets.corner(scope, 26),
			Widgets.gradient(scope, SKY_LIGHT, SKY_DEEP),
			Widgets.stroke(scope, 4),
			Widgets.speckles(scope, {
				{ 0.06, 0.18, 26 },
				{ 0.94, 0.12, 16 },
				{ 0.5, 0.95, 12 },
				{ 0.03, 0.76, 12 },
				{ 0.97, 0.66, 22 },
			}),
			scope:New("TextLabel")({
				Name = "Headline",
				Position = UDim2.fromOffset(10, 8),
				Size = UDim2.new(1, -20, 0, 46),
				BackgroundTransparency = 1,
				Font = Theme.TITLE_FONT,
				RichText = true,
				Text = scope:Computed(function(use)
					return if use(isMax) then "STICK MAXED OUT!" else rainbow("UPGRADE") .. " STICK!"
				end),
				TextColor3 = Theme.WHITE,
				TextSize = 40,
				[Children] = { Widgets.stroke(scope, 4) },
			}),

			tierShowcase(scope, {
				Name = "Current",
				Level = level,
				Position = scope:Computed(function(use)
					return if use(isMax) then UDim2.new(0.5, 0, 0, 54) else UDim2.new(0.2, 0, 0, 54)
				end),
			}),
			Widgets.text(scope, {
				Name = "Arrow",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 82),
				Size = UDim2.fromOffset(120, 74),
				Visible = notMax,
				Text = "➜",
				TextColor3 = Theme.CORAL,
				TextSize = 84,
				Stroke = 4,
			}),
			Widgets.text(scope, {
				Name = "Gain",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 164),
				Size = UDim2.fromOffset(200, 50),
				Visible = notMax,
				Font = Theme.TITLE_FONT,
				Text = scope:Computed(function(use)
					local gain = Sticks.tier(use(nextLevel)).perRep * multiplierOf(use)
					return `+{abbreviate(gain)} STAMINA\nPER ROLL`
				end),
				TextColor3 = Theme.YOLK,
				TextSize = 22,
				Stroke = 3,
			}),
			tierShowcase(scope, {
				Name = "Next",
				Level = nextLevel,
				Angle = 1.2,
				Position = UDim2.new(0.8, 0, 0, 54),
				Visible = notMax,
			}),

			scope:New("Frame")({
				Name = "Buttons",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -14),
				Size = UDim2.new(1, -40, 0, 56),
				Visible = notMax,
				BackgroundTransparency = 1,
				[Children] = {
					Widgets.list(scope, {
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = 16,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
					}),
					Widgets.button(scope, {
						Name = "BuyRobux",
						LayoutOrder = 1,
						Size = UDim2.fromScale(0.42, 1),
						Color = Theme.GREEN,
						Deep = Theme.GREEN_DEEP,
						Text = robuxText(scope, nextLevel),
						TextColor3 = Theme.WHITE,
						TextSize = 30,
						Stroke = 3,
						OnActivated = function()
							Net.RequestPurchase:FireServer(Shop.STICK_UPGRADE_ID)
						end,
					}),
					Widgets.button(scope, {
						Name = "BuyDollars",
						LayoutOrder = 2,
						Size = UDim2.fromScale(0.42, 1),
						Color = Theme.CORAL,
						Deep = Theme.CORAL_DEEP,
						Text = scope:Computed(function(use)
							return "$" .. NumberFormat.abbreviate(Sticks.tier(use(nextLevel)).price)
						end),
						TextColor3 = Theme.WHITE,
						TextSize = 30,
						Stroke = 3,
						OnActivated = function()
							Net.BuyWithDollars:FireServer(Shop.STICK_UPGRADE_ID)
						end,
					}),
				},
			}),
			scope:New("Frame")({
				Name = "Maxed",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -18),
				Size = UDim2.fromOffset(220, 50),
				Visible = isMax,
				BackgroundColor3 = Theme.GREEN,
				[Children] = {
					Widgets.corner(scope, 14),
					Widgets.stroke(scope, 3),
					Widgets.text(scope, {
						Text = "MAXED ✔",
						TextColor3 = Theme.WHITE,
						TextSize = 26,
						Stroke = 2.5,
					}),
				},
			}),
		},
	})
end

----------------------------------------------------------------------------------------------------------------
-- The upgrade panel (from the sign beside the stick)

-- All eight tiers in a row: the ones the player has passed lit up, the one they have ringed, the rest in shadow.
local function ladder(scope)
	local chips = {}
	for _, tier in Sticks.Tiers do
		local state = scope:Computed(function(use)
			local level = use(UiState.stickLevel)
			return if tier.level < level then "Passed" elseif tier.level == level then "Current" else "Locked"
		end)
		table.insert(
			chips,
			scope:New("Frame")({
				Name = tier.id,
				LayoutOrder = tier.level,
				Size = UDim2.fromOffset(72, 104),
				BackgroundColor3 = scope:Computed(function(use)
					return if use(state) == "Locked" then Theme.SHELL_DARK else Theme.CREAM
				end),
				[Children] = {
					Widgets.corner(scope, 14),
					scope:New("UIStroke")({
						Color = scope:Computed(function(use)
							return if use(state) == "Current" then Theme.YOLK_DEEP else Theme.INK
						end),
						Thickness = scope:Computed(function(use)
							return if use(state) == "Current" then 4 else 2.5
						end),
					}),
					preview(scope, {
						Name = "Preview",
						Position = UDim2.fromOffset(2, 4),
						Size = UDim2.new(1, -4, 0, 56),
						Level = tier.level,
						Angle = tier.level * 0.7,
						ImageColor3 = scope:Computed(function(use)
							return if use(state) == "Locked" then LOCKED_TINT else Theme.WHITE
						end),
					}),
					Widgets.text(scope, {
						Name = "TierLevel",
						Position = UDim2.fromOffset(0, 60),
						Size = UDim2.new(1, 0, 0, 18),
						Text = `Lvl {tier.level}`,
						TextColor3 = rgb(Rarities.Info[tier.rarity].color):Lerp(Theme.INK, 0.5),
						TextSize = 16,
					}),
					Widgets.text(scope, {
						Name = "TierName",
						Position = UDim2.fromOffset(4, 78),
						Size = UDim2.new(1, -8, 0, 22),
						Font = Theme.SMALL_FONT,
						Text = tier.name,
						TextScaled = true,
						MaxTextSize = 13,
						TextWrapped = true,
					}),
				},
			})
		)
	end
	return scope:New("Frame")({
		Name = "Ladder",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 108),
		BackgroundTransparency = 1,
		[Children] = {
			Widgets.list(scope, {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = 6,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
			chips,
		},
	})
end

function TrainingUi.panel(scope)
	return Widgets.panel(scope, {
		Name = "Stick",
		Title = "TRAINING STICK",
		Icon = "🪵",
		Size = UDim2.new(0, 700, 0.9, 0),
		MaxSize = Vector2.new(math.huge, 620),
		Visible = scope:Computed(function(use)
			return use(UiState.openPanel) == "Stick"
		end),
		OnClose = function()
			UiState.openPanel:set(nil)
		end,
		Body = {
			Widgets.scroller(scope, {
				Name = "Scroll",
				Padding = 10,
				Children = {
					TrainingUi.stickCard(scope, 1),
					ladder(scope),
					Widgets.text(scope, {
						Name = "HowItWorks",
						LayoutOrder = 3,
						Size = UDim2.new(1, -20, 0, 44),
						Font = Theme.SMALL_FONT,
						Text = scope:Computed(function(use)
							local tier = Sticks.tier(use(UiState.stickLevel))
							local perSecond = Sticks.perSecond(tier.level) * multiplierOf(use)
							return `Roll on your {tier.name} for +{abbreviate(perSecond)} Max Stamina a second, kept `
								.. "forever. Tap the 2x bubbles to double it!"
						end),
						TextColor3 = Color3.fromRGB(130, 96, 70),
						TextSize = 15,
						TextWrapped = true,
					}),
				},
			}),
		},
	})
end

----------------------------------------------------------------------------------------------------------------
-- While rolling

-- The "2x" bubble: pops in where it appears, pulses, its outer ring shrinking as its time runs out. Tapping it
-- doubles the next reps.
local function bubble(scope)
	local current = UiState.trainingBubble
	local grow = scope:Spring(scope:Value(1), 28, 0.42)
	local lastId = 0
	scope:Observer(current):onChange(function()
		local value = Fusion.peek(current)
		if value and value.id ~= lastId then
			-- Pops in from nothing each time a new one appears, overshooting a little.
			lastId = value.id
			grow:setPosition(0)
		end
	end)

	return scope:New("CanvasGroup")({
		Name = "Bubble",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = scope:Computed(function(use)
			local value = use(current)
			return if value then UDim2.fromScale(value.x, value.y) else UDim2.fromScale(0.5, 0.4)
		end),
		Size = UDim2.fromOffset(180, 180),
		Visible = scope:Computed(function(use)
			return use(current) ~= nil
		end),
		BackgroundTransparency = 1,
		ZIndex = 12,
		GroupTransparency = scope:Computed(function(use)
			local fading = math.clamp((0.15 - use(UiState.bubbleLeft)) / 0.15, 0, 1)
			return math.max(use(UiState.bubblePop), fading)
		end),
		[Children] = {
			scope:New("UIScale")({
				Scale = scope:Computed(function(use)
					return math.max(0, use(grow)) * (1 + 0.05 * use(UiState.pulse)) * (1 + 0.7 * use(UiState.bubblePop))
				end),
			}),
			-- The countdown ring.
			scope:New("Frame")({
				Name = "Ring",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = scope:Computed(function(use)
					-- (Kept inside the group, outline and all, so none of it is clipped.)
					local size = 0.66 + 0.26 * use(UiState.bubbleLeft)
					return UDim2.fromScale(size, size)
				end),
				BackgroundTransparency = 1,
				[Children] = {
					Widgets.round(scope),
					Widgets.stroke(scope, 5, Theme.WHITE, 0.15),
				},
			}),
			scope:New("Frame")({
				Name = "Body",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.62, 0.62),
				BackgroundColor3 = Theme.WHITE,
				[Children] = {
					Widgets.round(scope),
					Widgets.gradient(scope, BOOST_GOLD, BOOST_DEEP),
					Widgets.stroke(scope, 4),
					scope:New("Frame")({
						Name = "Shine",
						Position = UDim2.fromScale(0.2, 0.12),
						Size = UDim2.fromScale(0.34, 0.2),
						Rotation = -25,
						BackgroundColor3 = Theme.WHITE,
						BackgroundTransparency = 0.35,
						[Children] = { Widgets.round(scope) },
					}),
					Widgets.text(scope, {
						Name = "Label",
						Position = UDim2.fromScale(0, 0.04),
						Font = Theme.TITLE_FONT,
						Text = "2x",
						TextColor3 = Theme.WHITE,
						TextSize = 50,
						Stroke = 3.5,
					}),
				},
			}),
			scope:New("TextButton")({
				Name = "Tap",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.9, 0.9),
				BackgroundTransparency = 1,
				Text = "",
				ZIndex = 13,
				[OnEvent("Activated")] = function()
					local value = Fusion.peek(current)
					if value and not value.popped then
						UiState.actions.claimBubble(value.id)
					end
				end,
			}),
		},
	})
end

-- The bar over the training card while a 2x boost runs.
local function boostBar(scope)
	return scope:New("Frame")({
		Name = "Boost",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.new(1, -40, 0, 34),
		Visible = scope:Computed(function(use)
			return use(UiState.boostLeft) > 0
		end),
		BackgroundColor3 = PANEL_DARK,
		[Children] = {
			Widgets.round(scope),
			Widgets.stroke(scope, 3),
			scope:New("UIScale")({
				Scale = scope:Computed(function(use)
					return 1 + 0.04 * use(UiState.pulse)
				end),
			}),
			scope:New("Frame")({
				Name = "Fill",
				Size = scope:Computed(function(use)
					return UDim2.fromScale(math.clamp(use(UiState.boostLeft), 0, 1), 1)
				end),
				BackgroundColor3 = Theme.WHITE,
				[Children] = {
					Widgets.round(scope),
					Widgets.gradient(scope, BOOST_GOLD, BOOST_DEEP),
				},
			}),
			Widgets.text(scope, {
				Name = "Label",
				Font = Theme.TITLE_FONT,
				Text = "2x STAMINA!",
				TextColor3 = Theme.WHITE,
				TextSize = 26,
				Stroke = 3,
				ZIndex = 2,
			}),
		},
	})
end

-- Everything on screen while the player rolls on their stick.
function TrainingUi.hud(scope)
	local level = UiState.stickLevel
	local tier = scope:Computed(function(use)
		return Sticks.tier(use(level))
	end)
	local boosted = scope:Computed(function(use)
		return use(UiState.boostLeft) > 0
	end)
	local perRep = scope:Computed(function(use)
		local gain = use(tier).perRep * multiplierOf(use)
		return if use(boosted) then gain * Sticks.BOOST_MULTIPLIER else gain
	end)

	return scope:New("Frame")({
		Name = "Training",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = UiState.training,
		[Children] = {
			bubble(scope),
			scope:New("Frame")({
				Name = "Card",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -50),
				Size = UDim2.fromOffset(440, 96),
				BackgroundColor3 = PANEL_DARK,
				BackgroundTransparency = 0.08,
				[Children] = {
					Widgets.corner(scope, 22),
					Widgets.stroke(scope, 3),
					boostBar(scope),
					Widgets.text(scope, {
						Name = "Hint",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 0, -44),
						Size = UDim2.new(1, 0, 0, 20),
						Font = Theme.SMALL_FONT,
						Text = "Tap the 2x bubbles for double stamina  •  Jump to stop",
						TextColor3 = Theme.WHITE,
						TextSize = 15,
						Stroke = 2,
						Visible = scope:Computed(function(use)
							return not use(boosted)
						end),
					}),
					-- The tier's badge: its level, in its colour.
					scope:New("Frame")({
						Name = "Badge",
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 14, 0.5, 0),
						Size = UDim2.fromOffset(66, 66),
						BackgroundColor3 = scope:Computed(function(use)
							return rgb(use(tier).color)
						end),
						[Children] = {
							Widgets.round(scope),
							Widgets.stroke(scope, 3.5),
							Widgets.text(scope, {
								Name = "Level",
								Position = UDim2.fromOffset(0, 2),
								Font = Theme.TITLE_FONT,
								Text = scope:Computed(function(use)
									return tostring(use(tier).level)
								end),
								TextColor3 = Theme.WHITE,
								TextSize = 38,
								Stroke = 3,
							}),
						},
					}),
					Widgets.text(scope, {
						Name = "TierName",
						Position = UDim2.fromOffset(92, 10),
						Size = UDim2.new(1, -230, 0, 34),
						Font = Theme.TITLE_FONT,
						Text = scope:Computed(function(use)
							return string.upper(use(tier).name)
						end),
						TextColor3 = Theme.WHITE,
						TextScaled = true,
						MaxTextSize = 30,
						TextXAlignment = Enum.TextXAlignment.Left,
						Stroke = 3,
					}),
					Widgets.text(scope, {
						Name = "Rate",
						Position = UDim2.fromOffset(92, 44),
						Size = UDim2.new(1, -230, 0, 22),
						Text = scope:Computed(function(use)
							local gain = use(perRep)
							return `⚡ +{abbreviate(gain)} a roll  •  +{abbreviate(gain / Sticks.REP_INTERVAL)}/s`
						end),
						TextColor3 = scope:Computed(function(use)
							return if use(boosted) then BOOST_GOLD else STAMINA_BLUE
						end),
						TextScaled = true,
						MaxTextSize = 20,
						TextXAlignment = Enum.TextXAlignment.Left,
						Stroke = 2,
					}),
					Widgets.text(scope, {
						Name = "Gained",
						Position = UDim2.fromOffset(92, 68),
						Size = UDim2.new(1, -230, 0, 18),
						Font = Theme.SMALL_FONT,
						Text = scope:Computed(function(use)
							return `+{NumberFormat.abbreviate(math.floor(use(UiState.trainingGained)))} Max Stamina so far`
						end),
						TextColor3 = Color3.fromRGB(150, 255, 130),
						TextSize = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
						Stroke = 1.5,
					}),
					Widgets.button(scope, {
						Name = "Stop",
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -14, 0.5, 0),
						Size = UDim2.fromOffset(118, 60),
						Color = Theme.CORAL,
						Deep = Theme.CORAL_DEEP,
						Text = "STOP",
						TextColor3 = Theme.WHITE,
						TextSize = 30,
						Stroke = 3,
						OnActivated = function()
							UiState.actions.stopTraining()
						end,
					}),
				},
			}),
		},
	})
end

return TrainingUi
