-- The panels the hub stations open: the Trails shop, the Sell stall, and the fuse machine. Built with Fusion.
-- Like the rest of the HUD they only read UiState; their buttons call UiState.actions, which ShopController fills
-- in. ShopController also decides which panel is open (UiState.openPanel).
--
-- Placeholder look, sized for phones first (large rows and buttons). Final UI art comes later.

local Load = require(script.Parent.Parent.Load)
local Economy = Load.shared("Config", "Economy")
local NumberFormat = Load.shared("NumberFormat")
local Rarities = Load.shared("Config", "Rarities")
local Trails = Load.shared("Config", "Trails")
local Zones = Load.shared("Config", "Zones")

local UiState = require(script.Parent.UiState)

local Fusion = UiState.Fusion
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(26, 28, 36)
local ROW = Color3.fromRGB(42, 45, 58)
local MUTED = Color3.fromRGB(175, 180, 195)
local BOOST = Color3.fromRGB(150, 225, 255)
local BUY = Color3.fromRGB(70, 185, 90)
local EQUIP = Color3.fromRGB(70, 135, 230)
local EQUIPPED = Color3.fromRGB(45, 110, 60)
local CANNOT_AFFORD = Color3.fromRGB(88, 90, 102)
local CLOSE = Color3.fromRGB(220, 70, 70)

local TRAILS_COLOR = Color3.fromRGB(170, 95, 230)
local SELL_COLOR = Color3.fromRGB(230, 70, 70)
local FUSE_COLOR = Color3.fromRGB(245, 175, 30)

local PANEL_WIDTH = 560
local PANEL_HEIGHT = 440
local ROW_HEIGHT = 72
local BUTTON_HEIGHT = 52

local StationPanels = {}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function corner(scope, radius: number)
	return scope:New("UICorner")({ CornerRadius = UDim.new(0, radius) })
end

local function text(scope, props)
	return scope:New("TextLabel")({
		Name = props.Name,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		BackgroundTransparency = 1,
		Font = props.Font or Enum.Font.GothamBold,
		Text = props.Text,
		TextColor3 = props.Color or WHITE,
		TextSize = props.TextSize or 18,
		TextWrapped = props.Wrapped,
		TextXAlignment = props.XAlignment or Enum.TextXAlignment.Left,
	})
end

local function button(scope, props)
	return scope:New("TextButton")({
		Name = props.Name,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		BackgroundColor3 = props.Color,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		Text = props.Text,
		TextColor3 = WHITE,
		TextSize = props.TextSize or 20,
		[OnEvent("Activated")] = props.OnActivated,
		[Children] = {
			corner(scope, 12),
			scope:New("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.new(0, 0, 0),
				Thickness = 2,
				Transparency = 0.5,
			}),
		},
	})
end

-- The frame every station panel shares: a title, a close button, a scrolling list of rows, and a footer line.
local function panel(scope, props)
	return scope:New("Frame")({
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.04,
		Visible = scope:Computed(function(use)
			return use(UiState.openPanel) == props.Name
		end),
		ZIndex = 5,
		[Children] = {
			corner(scope, 16),
			scope:New("UIStroke")({ Color = props.Color, Thickness = 3 }),
			text(scope, {
				Name = "Title",
				Position = UDim2.fromOffset(20, 10),
				Size = UDim2.new(1, -100, 0, 46),
				Font = Enum.Font.FredokaOne,
				Text = props.Title,
				Color = props.Color,
				TextSize = 34,
			}),
			button(scope, {
				Name = "Close",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 10),
				Size = UDim2.fromOffset(BUTTON_HEIGHT, BUTTON_HEIGHT),
				Color = CLOSE,
				Text = "X",
				TextSize = 26,
				OnActivated = function()
					UiState.actions.closePanel()
				end,
			}),
			scope:New("ScrollingFrame")({
				Name = "List",
				Position = UDim2.fromOffset(14, 70),
				Size = UDim2.new(1, -28, 1, -70 - 48),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarThickness = 8,
				[Children] = {
					scope:New("UIListLayout")({
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					props.Rows,
				},
			}),
			text(scope, {
				Name = "Footer",
				Position = UDim2.new(0, 20, 1, -42),
				Size = UDim2.new(1, -40, 0, 32),
				Text = props.Footer,
				Color = MUTED,
				TextSize = 18,
			}),
		},
	})
end

----------------------------------------------------------------------------------------------------------------
-- Trails shop

local function trailRow(scope, trail, order: number)
	local state = scope:Computed(function(use)
		if use(UiState.trailEquipped) == trail.id then
			return "Equipped"
		elseif use(UiState.trailsOwned)[trail.id] then
			return "Owned"
		elseif use(UiState.coins) >= trail.price then
			return "Affordable"
		end
		return "TooExpensive"
	end)

	local keypoints = {}
	for index, color in trail.colors do
		local time = if #trail.colors == 1 then 0 else (index - 1) / (#trail.colors - 1)
		table.insert(keypoints, ColorSequenceKeypoint.new(time, rgb(color)))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, rgb(trail.colors[1])))
	end

	return scope:New("Frame")({
		Name = trail.id,
		LayoutOrder = order,
		Size = UDim2.new(1, -10, 0, ROW_HEIGHT),
		BackgroundColor3 = ROW,
		[Children] = {
			corner(scope, 12),
			scope:New("Frame")({
				Name = "Swatch",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 12, 0.5, 0),
				Size = UDim2.fromOffset(48, 48),
				BackgroundColor3 = WHITE,
				[Children] = {
					corner(scope, 24),
					scope:New("UIGradient")({ Color = ColorSequence.new(keypoints) }),
				},
			}),
			text(scope, {
				Name = "TrailName",
				Position = UDim2.fromOffset(74, 10),
				Size = UDim2.new(1, -260, 0, 28),
				Font = Enum.Font.FredokaOne,
				Text = trail.name,
				TextSize = 22,
			}),
			text(scope, {
				Name = "Boost",
				Position = UDim2.fromOffset(74, 38),
				Size = UDim2.new(1, -260, 0, 22),
				Text = `Stamina x{trail.stamina}`,
				Color = BOOST,
				TextSize = 17,
			}),
			button(scope, {
				Name = "Action",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(160, BUTTON_HEIGHT),
				Color = scope:Computed(function(use)
					local current = use(state)
					if current == "Equipped" then
						return EQUIPPED
					elseif current == "Owned" then
						return EQUIP
					elseif current == "Affordable" then
						return BUY
					end
					return CANNOT_AFFORD
				end),
				Text = scope:Computed(function(use)
					local current = use(state)
					if current == "Equipped" then
						return "Equipped"
					elseif current == "Owned" then
						return "Equip"
					end
					return `{NumberFormat.abbreviate(trail.price)} coins`
				end),
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
	local rows = {}
	for index, trail in Trails.List do
		table.insert(rows, trailRow(scope, trail, index))
	end
	return panel(scope, {
		Name = "Trails",
		Title = "Trails",
		Color = TRAILS_COLOR,
		Rows = rows,
		Footer = scope:Computed(function(use)
			local equipped = Trails.ById[use(UiState.trailEquipped)]
			local boost = if equipped then equipped.stamina else 1
			return `Coins: {NumberFormat.abbreviate(use(UiState.coins))}     Stamina boost: x{boost}`
		end),
	})
end

----------------------------------------------------------------------------------------------------------------
-- Sell stall

local function eggRow(scope, group, order: number)
	local zone = Zones.List[group.zone]
	local rarity = Rarities.Info[group.rarity]
	local value = Economy.eggSellValue(group.zone, group.rarity) or 0
	local zoneName = if zone then zone.name else "?"

	return scope:New("Frame")({
		Name = `Egg_{group.zone}_{group.rarity}`,
		LayoutOrder = order,
		Size = UDim2.new(1, -10, 0, ROW_HEIGHT),
		BackgroundColor3 = ROW,
		[Children] = {
			corner(scope, 12),
			scope:New("Frame")({
				Name = "Swatch",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 14, 0.5, 0),
				Size = UDim2.fromOffset(40, 50),
				BackgroundColor3 = if rarity then rgb(rarity.color) else WHITE,
				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
					scope:New("UIStroke")({
						Color = if zone then rgb(zone.accent) else WHITE,
						Thickness = 3,
					}),
				},
			}),
			text(scope, {
				Name = "EggName",
				Position = UDim2.fromOffset(70, 10),
				Size = UDim2.new(1, -300, 0, 28),
				Font = Enum.Font.FredokaOne,
				Text = `{group.rarity} {zoneName} egg`,
				TextSize = 21,
			}),
			text(scope, {
				Name = "Details",
				Position = UDim2.fromOffset(70, 38),
				Size = UDim2.new(1, -300, 0, 22),
				Text = `x{group.count}   {NumberFormat.abbreviate(value)} coins each`,
				Color = MUTED,
				TextSize = 16,
			}),
			button(scope, {
				Name = "SellOne",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -128, 0.5, 0),
				Size = UDim2.fromOffset(92, BUTTON_HEIGHT),
				Color = SELL_COLOR,
				Text = "Sell 1",
				OnActivated = function()
					UiState.actions.sellEggs(group.zone, group.rarity, 1)
				end,
			}),
			button(scope, {
				Name = "SellAll",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(108, BUTTON_HEIGHT),
				Color = Color3.fromRGB(170, 45, 45),
				Text = "Sell all",
				OnActivated = function()
					UiState.actions.sellEggs(group.zone, group.rarity, group.count)
				end,
			}),
		},
	})
end

local function sellPanel(scope)
	return panel(scope, {
		Name = "Sell",
		Title = "Sell",
		Color = SELL_COLOR,
		Rows = {
			text(scope, {
				Name = "Empty",
				LayoutOrder = 0,
				Size = UDim2.new(1, -10, 0, 80),
				Text = "No eggs to sell yet. Claim eggs on the runway, then come back!",
				Color = MUTED,
				TextSize = 20,
				Wrapped = true,
				XAlignment = Enum.TextXAlignment.Center,
				Visible = scope:Computed(function(use)
					return #use(UiState.inventory) == 0
				end),
			}),
			scope:ForPairs(UiState.inventory, function(_use, rowScope, index, group)
				return index, eggRow(rowScope, group, index)
			end),
			text(scope, {
				Name = "PetsNote",
				LayoutOrder = 100000,
				Size = UDim2.new(1, -10, 0, 30),
				Text = "Pets you hatch can be sold here too.",
				Color = MUTED,
				TextSize = 15,
				XAlignment = Enum.TextXAlignment.Center,
			}),
		},
		Footer = scope:Computed(function(use)
			return `Coins: {NumberFormat.abbreviate(use(UiState.coins))}`
		end),
	})
end

----------------------------------------------------------------------------------------------------------------
-- Fuse machine

local function fusePanel(scope)
	return panel(scope, {
		Name = "Fuse",
		Title = "Fuse Machine",
		Color = FUSE_COLOR,
		Rows = {
			text(scope, {
				Name = "HowItWorks",
				LayoutOrder = 1,
				Size = UDim2.new(1, -10, 0, 90),
				Text = "Put in 3 of the same pet and get that pet's egg back.",
				TextSize = 22,
				Wrapped = true,
				XAlignment = Enum.TextXAlignment.Center,
			}),
			text(scope, {
				Name = "NoPets",
				LayoutOrder = 2,
				Size = UDim2.new(1, -10, 0, 90),
				Text = "You don't have any pets to fuse yet. Hatch eggs in your pen first!",
				Color = MUTED,
				TextSize = 19,
				Wrapped = true,
				XAlignment = Enum.TextXAlignment.Center,
			}),
		},
		Footer = "",
	})
end

-- The three panels, to go inside the HUD's scaled root frame.
function StationPanels.create(scope)
	return {
		trailsPanel(scope),
		sellPanel(scope),
		fusePanel(scope),
	}
end

return StationPanels
