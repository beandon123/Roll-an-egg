-- The panels the hub stations open: the Trails stall, the Sell stall, and the fuse machine. Built with Fusion, in
-- the same style as the shop (Ui/Widgets). Like the rest of the HUD they only read UiState; their buttons call
-- UiState.actions, which StationController fills in. StationController also opens and closes them
-- (UiState.openPanel is the station's key while its panel is open).

local Load = require(script.Parent.Parent.Load)
local EggModels = Load.shared("EggModels")
local Economy = Load.shared("Config", "Economy")
local NumberFormat = Load.shared("NumberFormat")
local Rarities = Load.shared("Config", "Rarities")
local Trails = Load.shared("Config", "Trails")

local Theme = require(script.Parent.Theme)
local UiState = require(script.Parent.UiState)
local Widgets = require(script.Parent.Widgets)

local Fusion = UiState.Fusion
local Children = Fusion.Children

local ROW_HEIGHT = 84
local PANEL_SIZE = UDim2.new(0, 600, 0.8, 0)
local PANEL_MAX = Vector2.new(math.huge, 560)

local StationPanels = {}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function money(amount: number): string
	return "$" .. NumberFormat.abbreviate(amount)
end

local function isOpen(scope, key: string)
	return scope:Computed(function(use)
		return use(UiState.openPanel) == key
	end)
end

local function close()
	UiState.openPanel:set(nil)
end

-- A cream card for one row of a list.
local function row(scope, props)
	return scope:New("Frame")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = Theme.SHELL,
		[Children] = {
			Widgets.corner(scope, 18),
			Widgets.stroke(scope, 3),
			props.Children,
		},
	})
end

-- A line of small print under a list.
local function note(scope, props)
	return Widgets.text(scope, {
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, props.Height or 40),
		Visible = props.Visible,
		Text = props.Text,
		TextSize = props.TextSize or 18,
		TextColor3 = props.TextColor3,
		TextWrapped = true,
	})
end

----------------------------------------------------------------------------------------------------------------
-- Trails stall
--
-- A dark panel under a lavender header, with a card for every trail in a row that scrolls sideways: its name, its
-- level and rarity, a picture of it streaming behind a runner, its stamina boost, and a big button (its price, or
-- Equip once owned).

local TRAILS_PANEL = Color3.fromRGB(54, 54, 66)
local TRAILS_PANEL_DEEP = Color3.fromRGB(38, 38, 48)
local TRAILS_HEADER = Color3.fromRGB(190, 182, 244)
local TRAILS_HEADER_DEEP = Color3.fromRGB(132, 120, 212)
local CARD_WIDTH = 196
local CARD_HEIGHT = 368
local BOOST_GREEN = "#8CFF5A"
local PICTURE_CREAM = Color3.fromRGB(250, 238, 214)
local BUTTON_GREY = Color3.fromRGB(150, 150, 166)
local BUTTON_GREY_DEEP = Color3.fromRGB(98, 98, 114)

local function hex(color: { number }): string
	return string.format("#%02X%02X%02X", color[1], color[2], color[3])
end

local function trailSequence(colors: { { number } }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(rgb(colors[1]))
	end
	local keypoints = {}
	for index, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), rgb(color)))
	end
	return ColorSequence.new(keypoints)
end

-- A small piece of a picture: a coloured frame, optionally round, turned and outlined.
local function bit(scope, props)
	return scope:New("Frame")({
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.Position,
		Size = props.Size,
		Rotation = props.Rotation or 0,
		ZIndex = props.ZIndex,
		BackgroundColor3 = props.Color,
		BackgroundTransparency = props.Transparency or 0,
		[Children] = {
			if props.Round then Widgets.round(scope) else Widgets.corner(scope, props.Radius or 3),
			if props.Outline then Widgets.stroke(scope, props.Outline) else nil,
			props.Children,
		},
	})
end

-- Where the bits of a trail's particles go in its picture, along the ribbon behind the runner (fractions of the
-- picture), and how big each is.
local SPECK_SPOTS = {
	{ 0.14, 0.32, 1 },
	{ 0.26, 0.7, 0.8 },
	{ 0.35, 0.22, 0.7 },
	{ 0.42, 0.62, 1.1 },
	{ 0.08, 0.55, 0.7 },
	{ 0.52, 0.3, 0.8 },
	{ 0.2, 0.48, 0.6 },
	{ 0.56, 0.78, 0.6 },
}

-- A picture of a trail: a blocky runner on the right with the trail streaming out behind it, plus its halo, its
-- particles and its glow for the fancier trails.
local function trailPicture(scope, trail)
	local lead = trail.colors[1]
	local children = {}

	-- A soft glow behind the runner, brighter for trails that carry a light.
	table.insert(
		children,
		bit(scope, {
			Name = "Glow",
			Position = UDim2.fromScale(0.68, 0.52),
			Size = UDim2.fromScale(0.7, 0.8),
			Color = rgb(trail.light or lead),
			Transparency = if trail.light then 0.45 else 0.75,
			Round = true,
		})
	)

	-- The halo, then the ribbon: from the runner's back out to the left, fading away.
	local function streak(name: string, height: number, colors, startTransparency: number)
		local sequence = trailSequence(colors)
		return bit(scope, {
			Name = name,
			Position = UDim2.fromScale(0.36, 0.53),
			Size = UDim2.new(0.66, 0, 0, height),
			Rotation = -8,
			Color = Color3.new(1, 1, 1),
			Radius = math.floor(height / 2),
			Children = scope:New("UIGradient")({
				-- The lead colour at the runner (the right-hand end).
				Color = sequence,
				Rotation = 180,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, startTransparency),
					NumberSequenceKeypoint.new(0.75, math.min(1, startTransparency + 0.35)),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end
	if trail.halo then
		table.insert(children, streak("Halo", math.floor(trail.width * 22), { trail.halo }, 0.45))
	end
	table.insert(children, streak("Ribbon", math.floor(trail.width * 14), trail.colors, 0))

	-- Particles scattered along the ribbon: twinkling diamonds, or round bubbles, puffs and embers.
	if trail.particles then
		local spec = trail.particles
		local round = spec.kind == "Bubble" or spec.kind == "Dust" or spec.kind == "Ember"
		local count = math.clamp(math.floor(spec.rate / 5), 3, #SPECK_SPOTS)
		for index = 1, count do
			local spot = SPECK_SPOTS[index]
			local size = math.floor((if round then 11 else 10) * spot[3] * (spec.size / 0.8 + 0.4))
			table.insert(
				children,
				bit(scope, {
					Name = "Speck" .. index,
					Position = UDim2.fromScale(spot[1], spot[2]),
					Size = UDim2.fromOffset(size, size),
					Rotation = if round then 0 else 45,
					Color = rgb(spec.colors[(index - 1) % #spec.colors + 1]),
					Transparency = if spec.kind == "Bubble" then 0.35 else 0,
					Round = round,
					Outline = if spec.kind == "Bubble" then 1.5 else nil,
				})
			)
		end
	end

	-- The runner, mid-stride, facing right, in the trail's deepest colour with a lighter head.
	local body = rgb(trail.colors[#trail.colors])
	local head = body:Lerp(Color3.new(1, 1, 1), 0.45)
	local runner = {
		{ "BackLeg", UDim2.new(0.73, -6, 0.72, 0), UDim2.fromOffset(13, 30), 28 },
		{ "BackArm", UDim2.new(0.73, -12, 0.46, 0), UDim2.fromOffset(11, 28), -34 },
		{ "Torso", UDim2.new(0.73, 0, 0.5, 0), UDim2.fromOffset(26, 30), 8 },
		{ "FrontLeg", UDim2.new(0.73, 6, 0.72, 0), UDim2.fromOffset(13, 30), -30 },
		{ "FrontArm", UDim2.new(0.73, 12, 0.46, 0), UDim2.fromOffset(11, 28), 38 },
		{ "Head", UDim2.new(0.73, 3, 0.25, 0), UDim2.fromOffset(22, 22), 8 },
	}
	for index, piece in runner do
		table.insert(
			children,
			bit(scope, {
				Name = piece[1],
				Position = piece[2],
				Size = piece[3],
				Rotation = piece[4],
				ZIndex = 2 + index,
				Color = if piece[1] == "Head" then head else body,
				Radius = 4,
				Outline = 2.5,
			})
		)
	end

	return scope:New("Frame")({
		Name = "Picture",
		Position = UDim2.fromOffset(12, 74),
		Size = UDim2.new(1, -24, 0, 156),
		BackgroundColor3 = PICTURE_CREAM,
		ClipsDescendants = true,
		[Children] = {
			Widgets.corner(scope, 8),
			Widgets.stroke(scope, 3),
			Widgets.speckles(scope, {
				{ 0.1, 0.12, 14 },
				{ 0.88, 0.16, 10 },
				{ 0.92, 0.86, 16 },
				{ 0.06, 0.9, 9 },
				{ 0.5, 0.08, 7 },
			}, Color3.fromRGB(226, 206, 170), 0.4),
			children,
		},
	})
end

local function trailCard(scope, trail, order: number)
	local state = scope:Computed(function(use)
		if use(UiState.trailEquipped) == trail.id then
			return "Equipped"
		elseif use(UiState.trailsOwned)[trail.id] then
			return "Owned"
		elseif use(UiState.dollars) >= trail.price then
			return "Affordable"
		end
		return "TooExpensive"
	end)
	local rarity = Rarities.Info[trail.rarity]
	local rarityColor = if rarity then rarity.color else { 255, 255, 255 }
	-- Diagonal gloss across the card, like the shine on a trading card.
	local function shine(name: string, x: number, width: number, transparency: number)
		return scope:New("Frame")({
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.5),
			Size = UDim2.new(0, width, 1.6, 0),
			Rotation = 28,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
		})
	end

	return scope:New("Frame")({
		Name = trail.id,
		LayoutOrder = order,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundColor3 = Theme.INK,
		[Children] = {
			Widgets.corner(scope, 14),
			-- The coloured face, in the trail's own colours, with a white rim.
			scope:New("Frame")({
				Name = "Face",
				Position = UDim2.fromOffset(3, 3),
				Size = UDim2.new(1, -6, 1, -6),
				BackgroundColor3 = Color3.new(1, 1, 1),
				ClipsDescendants = true,
				[Children] = {
					Widgets.corner(scope, 11),
					scope:New("UIGradient")({ Color = trailSequence(trail.colors), Rotation = 60 }),
					scope:New("UIStroke")({
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = Color3.new(1, 1, 1),
						Thickness = 3,
						Transparency = 0.15,
					}),
					shine("Shine", 0.3, 26, 0.8),
					shine("ShineThin", 0.52, 9, 0.84),
					shine("ShineFar", 0.86, 16, 0.86),
				},
			}),
			Widgets.text(scope, {
				Name = "TrailName",
				Position = UDim2.fromOffset(10, 10),
				Size = UDim2.new(1, -20, 0, 24),
				Text = trail.name,
				TextColor3 = Theme.WHITE,
				TextScaled = true,
				MaxTextSize = 22,
				Stroke = 2.5,
			}),
			scope:New("TextLabel")({
				Name = "Level",
				Position = UDim2.fromOffset(10, 38),
				Size = UDim2.new(1, -20, 0, 30),
				BackgroundTransparency = 1,
				Font = Theme.FONT,
				RichText = true,
				Text = `Lvl {trail.level} <font color="{hex(rarityColor)}">{trail.rarity}</font>`,
				TextColor3 = Theme.WHITE,
				TextScaled = true,
				[Children] = {
					Widgets.stroke(scope, 2.5),
					scope:New("UITextSizeConstraint")({ MaxTextSize = 28 }),
				},
			}),
			trailPicture(scope, trail),
			-- The boost, on a dark strip: "x1.5 Stamina".
			scope:New("TextLabel")({
				Name = "Boost",
				Position = UDim2.fromOffset(12, 240),
				Size = UDim2.new(1, -24, 0, 44),
				BackgroundColor3 = Color3.fromRGB(20, 20, 28),
				BackgroundTransparency = 0.45,
				Font = Theme.FONT,
				RichText = true,
				Text = `<font color="{BOOST_GREEN}">x{trail.stamina}</font> Stamina`,
				TextColor3 = Theme.WHITE,
				TextScaled = true,
				[Children] = {
					Widgets.corner(scope, 6),
					Widgets.stroke(scope, 2.5),
					Widgets.padding(scope, 6, 8),
					scope:New("UITextSizeConstraint")({ MaxTextSize = 30 }),
				},
			}),
			Widgets.button(scope, {
				Name = "Action",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -14),
				Size = UDim2.new(1, -28, 0, 58),
				Radius = UDim.new(0, 8),
				Color = scope:Computed(function(use)
					local current = use(state)
					if current == "Equipped" then
						return Theme.YOLK
					elseif current == "TooExpensive" then
						return BUTTON_GREY
					end
					return Theme.GREEN
				end),
				Deep = scope:Computed(function(use)
					local current = use(state)
					if current == "Equipped" then
						return Theme.YOLK_DEEP
					elseif current == "TooExpensive" then
						return BUTTON_GREY_DEEP
					end
					return Theme.GREEN_DEEP
				end),
				Text = scope:Computed(function(use)
					local current = use(state)
					if current == "Equipped" then
						return "Equipped"
					elseif current == "Owned" then
						return "Equip"
					end
					return money(trail.price)
				end),
				TextColor3 = Theme.WHITE,
				TextSize = 30,
				Stroke = 2.5,
				OnActivated = function()
					if Fusion.peek(UiState.trailsOwned)[trail.id] then
						UiState.actions.equipTrail(trail.id)
					else
						UiState.actions.buyTrail(trail.id)
					end
				end,
			}),
		},
	})
end

local function trailsPanel(scope)
	local open = isOpen(scope, "Trails")
	local scale = scope:Spring(
		scope:Computed(function(use)
			return if use(open) then 1 else 0.8
		end),
		32,
		0.7
	)
	local cards = {}
	for index, trail in Trails.List do
		table.insert(cards, trailCard(scope, trail, index))
	end

	return scope:New("Frame")({
		Name = "Trails",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.new(0.92, 0, 0, 500),
		Visible = open,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 20,
		[Children] = {
			scope:New("UIScale")({ Scale = scale }),
			scope:New("UISizeConstraint")({ MaxSize = Vector2.new(900, 500) }),
			Widgets.corner(scope, 22),
			Widgets.gradient(scope, TRAILS_PANEL, TRAILS_PANEL_DEEP),
			scope:New("UIStroke")({ Color = Color3.fromRGB(214, 210, 240), Thickness = 5 }),
			Widgets.speckles(scope, {
				{ 0.04, 0.3, 8 },
				{ 0.97, 0.42, 6 },
				{ 0.5, 0.97, 7 },
				{ 0.22, 0.96, 5 },
				{ 0.8, 0.95, 9 },
			}, Color3.new(1, 1, 1), 0.92),

			-- The header: a lavender band with the title, a lightning badge on its corner and a red close button.
			scope:New("Frame")({
				Name = "TitleBar",
				Size = UDim2.new(1, 0, 0, 70),
				BackgroundColor3 = Color3.new(1, 1, 1),
				[Children] = {
					Widgets.corner(scope, 22),
					Widgets.gradient(scope, TRAILS_HEADER, TRAILS_HEADER_DEEP),
					Widgets.stroke(scope, 4),
					Widgets.speckles(scope, {
						{ 0.2, 0.3, 12 },
						{ 0.27, 0.72, 7 },
						{ 0.74, 0.32, 16 },
						{ 0.8, 0.74, 8 },
					}, Color3.new(1, 1, 1), 0.7),
					Widgets.text(scope, {
						Name = "Title",
						Size = UDim2.fromScale(1, 1),
						Font = Theme.TITLE_FONT,
						Text = "TRAILS",
						TextColor3 = Theme.WHITE,
						TextSize = 52,
						Stroke = 4,
					}),
					Widgets.text(scope, {
						Name = "Badge",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(16, 10),
						Size = UDim2.fromOffset(70, 70),
						Rotation = -12,
						Text = "⚡",
						TextSize = 58,
					}),
					Widgets.button(scope, {
						Name = "Close",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, 6, 0, -6),
						Size = UDim2.fromOffset(60, 60),
						Color = Theme.CORAL,
						Deep = Theme.CORAL_DEEP,
						Radius = UDim.new(0, 10),
						Text = "X",
						TextColor3 = Theme.WHITE,
						TextSize = 36,
						Stroke = 3,
						OnActivated = close,
					}),
				},
			}),

			-- The cards, in a row that scrolls sideways.
			scope:New("Frame")({
				Name = "Body",
				Position = UDim2.fromOffset(0, 80),
				Size = UDim2.new(1, 0, 1, -122),
				BackgroundTransparency = 1,
				[Children] = {
					scope:New("ScrollingFrame")({
						Name = "Scroll",
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						AutomaticCanvasSize = Enum.AutomaticSize.X,
						CanvasSize = UDim2.new(),
						ScrollingDirection = Enum.ScrollingDirection.X,
						ScrollBarThickness = 10,
						ScrollBarImageColor3 = Color3.fromRGB(200, 200, 214),
						ScrollBarImageTransparency = 0.2,
						VerticalScrollBarInset = Enum.ScrollBarInset.None,
						[Children] = {
							Widgets.padding(scope, 4, 18, 14),
							Widgets.list(scope, {
								FillDirection = Enum.FillDirection.Horizontal,
								Padding = 14,
								VerticalAlignment = Enum.VerticalAlignment.Top,
							}),
							cards,
						},
					}),
				},
			}),

			-- What the player has, and the boost from the trail they wear.
			Widgets.text(scope, {
				Name = "Footer",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10),
				Size = UDim2.new(1, -40, 0, 28),
				Text = scope:Computed(function(use)
					local equipped = Trails.ById[use(UiState.trailEquipped)]
					local boost = if equipped then equipped.stamina else 1
					return `You have {money(math.floor(use(UiState.dollars)))}.  Trail boost: Max Stamina x{boost}`
				end),
				TextColor3 = Theme.WHITE,
				TextSize = 20,
				Stroke = 2,
			}),
		},
	})
end

----------------------------------------------------------------------------------------------------------------
-- Sell stall

-- The player's eggs, counted by kind, in runway order and rarest last: { kind, zone, rarity, count }.
local function eggGroups(eggs: { any }): { any }
	local byKind = {}
	local groups = {}
	for _, egg in eggs do
		local group = byKind[egg.kind]
		if group == nil then
			group = { kind = egg.kind, zone = egg.zone, rarity = egg.rarity, count = 0 }
			byKind[egg.kind] = group
			table.insert(groups, group)
		end
		group.count += 1
	end
	table.sort(groups, function(a, b)
		if a.zone ~= b.zone then
			return a.zone < b.zone
		end
		local orderA = Rarities.Info[a.rarity] and Rarities.Info[a.rarity].order or 0
		local orderB = Rarities.Info[b.rarity] and Rarities.Info[b.rarity].order or 0
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a.kind < b.kind
	end)
	return groups
end

local function eggRow(scope, group, order: number)
	local about = EggModels.describe(group.kind)
	local rarity = Rarities.Info[group.rarity]
	local value = Economy.eggSellValue(group.zone, group.rarity) or 0

	return row(scope, {
		Name = "Egg_" .. group.kind,
		LayoutOrder = order,
		Children = {
			scope:New("Frame")({
				Name = "Swatch",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 18, 0.5, 0),
				Size = UDim2.fromOffset(44, 56),
				BackgroundColor3 = if rarity then rgb(rarity.color) else Theme.WHITE,
				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
					Widgets.stroke(scope, 3),
				},
			}),
			Widgets.text(scope, {
				Name = "EggName",
				Position = UDim2.fromOffset(78, 12),
				Size = UDim2.new(1, -330, 0, 30),
				Text = if about then about.name else group.kind,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Widgets.text(scope, {
				Name = "Details",
				Position = UDim2.fromOffset(78, 44),
				Size = UDim2.new(1, -330, 0, 24),
				Font = Theme.SMALL_FONT,
				Text = `{group.rarity}  x{group.count}   {money(value)} each`,
				TextColor3 = if rarity then rgb(rarity.color):Lerp(Theme.INK, 0.45) else Theme.INK,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Widgets.button(scope, {
				Name = "SellOne",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -140, 0.5, 0),
				Size = UDim2.fromOffset(104, 56),
				Color = Theme.YOLK,
				Deep = Theme.YOLK_DEEP,
				Text = "Sell 1",
				TextSize = 22,
				OnActivated = function()
					UiState.actions.sellEggs(group.kind, 1)
				end,
			}),
			Widgets.button(scope, {
				Name = "SellAll",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(116, 56),
				Color = Theme.CORAL,
				Deep = Theme.CORAL_DEEP,
				Text = "Sell all",
				TextColor3 = Theme.WHITE,
				TextSize = 22,
				Stroke = 2,
				OnActivated = function()
					UiState.actions.sellEggs(group.kind, group.count)
				end,
			}),
		},
	})
end

local function sellPanel(scope)
	local groups = scope:Computed(function(use)
		return eggGroups(use(UiState.eggs))
	end)
	return Widgets.panel(scope, {
		Name = "Sell",
		Title = "SELL EGGS",
		Icon = "💵",
		Size = PANEL_SIZE,
		MaxSize = PANEL_MAX,
		Visible = isOpen(scope, "Sell"),
		OnClose = close,
		Body = {
			Widgets.scroller(scope, {
				Children = {
					note(scope, {
						Name = "Empty",
						LayoutOrder = 0,
						Height = 80,
						Text = "No eggs to sell. Claim eggs on the runway, then come back!",
						TextSize = 20,
						Visible = scope:Computed(function(use)
							return #use(groups) == 0
						end),
					}),
					scope:ForPairs(groups, function(_use, rowScope, index, group)
						return index, eggRow(rowScope, group, index)
					end),
					note(scope, {
						Name = "PetsNote",
						LayoutOrder = 100000,
						Text = "Eggs in your inventory sell here. Sell pets from the Pets tab on the right.",
						TextSize = 16,
					}),
				},
			}),
		},
	})
end

----------------------------------------------------------------------------------------------------------------
-- Fuse machine

local function fusePanel(scope)
	return Widgets.panel(scope, {
		Name = "Fuse",
		Title = "FUSE MACHINE",
		Icon = "🔮",
		Size = PANEL_SIZE,
		MaxSize = PANEL_MAX,
		Visible = isOpen(scope, "Fuse"),
		OnClose = close,
		Body = {
			Widgets.scroller(scope, {
				Children = {
					note(scope, {
						Name = "HowItWorks",
						LayoutOrder = 1,
						Height = 70,
						Text = "Put in 3 of the same pet and get back an egg of that pet, usually one size bigger.",
						TextSize = 22,
					}),
					note(scope, {
						Name = "Odds",
						LayoutOrder = 2,
						Height = 120,
						Text = "Mix any variants and sizes. Each pet you put in has a 1 in 3 chance to pass on its "
							.. "variant, and a 1 in 3 chance to set the size, which then grows one step. Growing past "
							.. "Big gets harder: 90% to Huge, 80% to Giant, 70% to Colossal, 60% to Titanic.",
						TextColor3 = Theme.SKY_DEEP,
						TextSize = 18,
					}),
					note(scope, {
						Name = "Soon",
						LayoutOrder = 3,
						Height = 60,
						Text = "The fuse machine is warming up: fusing opens soon!",
						TextColor3 = Theme.CORAL_DEEP,
						TextSize = 20,
					}),
				},
			}),
		},
	})
end

-- The three panels, to go inside the HUD's scaled root frame.
function StationPanels.build(scope)
	return {
		trailsPanel(scope),
		sellPanel(scope),
		fusePanel(scope),
	}
end

return StationPanels
