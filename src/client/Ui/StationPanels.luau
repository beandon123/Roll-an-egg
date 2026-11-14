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

local function trailRow(scope, trail, order: number)
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

	local keypoints = {}
	for index, color in trail.colors do
		local time = if #trail.colors == 1 then 0 else (index - 1) / (#trail.colors - 1)
		table.insert(keypoints, ColorSequenceKeypoint.new(time, rgb(color)))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, rgb(trail.colors[1])))
	end

	return row(scope, {
		Name = trail.id,
		LayoutOrder = order,
		Children = {
			scope:New("Frame")({
				Name = "Swatch",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 14, 0.5, 0),
				Size = UDim2.fromOffset(54, 54),
				BackgroundColor3 = Theme.WHITE,
				[Children] = {
					Widgets.round(scope),
					Widgets.stroke(scope, 3),
					scope:New("UIGradient")({ Color = ColorSequence.new(keypoints) }),
				},
			}),
			Widgets.text(scope, {
				Name = "TrailName",
				Position = UDim2.fromOffset(82, 12),
				Size = UDim2.new(1, -270, 0, 30),
				Text = trail.name,
				TextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Widgets.text(scope, {
				Name = "Boost",
				Position = UDim2.fromOffset(82, 44),
				Size = UDim2.new(1, -270, 0, 24),
				Font = Theme.SMALL_FONT,
				Text = `Max Stamina x{trail.stamina}`,
				TextColor3 = Theme.SKY_DEEP,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Widgets.button(scope, {
				Name = "Action",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(160, 56),
				Color = scope:Computed(function(use)
					local current = use(state)
					if current == "Equipped" then
						return Theme.SHELL_DARK
					elseif current == "Owned" then
						return Theme.SKY
					elseif current == "Affordable" then
						return Theme.GREEN
					end
					return Theme.TRACK
				end),
				Deep = scope:Computed(function(use)
					local current = use(state)
					if current == "Owned" then
						return Theme.SKY_DEEP
					elseif current == "Affordable" then
						return Theme.GREEN_DEEP
					end
					return Theme.SHELL_DARK
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
				TextSize = 24,
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
	table.insert(
		rows,
		note(scope, {
			Name = "Footer",
			LayoutOrder = #Trails.List + 1,
			Text = scope:Computed(function(use)
				local equipped = Trails.ById[use(UiState.trailEquipped)]
				local boost = if equipped then equipped.stamina else 1
				return `You have {money(math.floor(use(UiState.dollars)))}.  Trail boost: Max Stamina x{boost}`
			end),
		})
	)
	return Widgets.panel(scope, {
		Name = "Trails",
		Title = "TRAILS",
		Icon = "✨",
		Size = PANEL_SIZE,
		MaxSize = PANEL_MAX,
		Visible = isOpen(scope, "Trails"),
		OnClose = close,
		Body = { Widgets.scroller(scope, { Children = rows }) },
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
