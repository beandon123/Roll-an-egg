-- The shop panel: a featured pen upgrade, server luck boosts, Max Stamina, coin packs, and game passes
-- (Config/Shop). Buttons only ask the server; the server checks prices and shows Roblox's purchase prompt.

local Load = require(script.Parent.Parent.Load)
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")
local Shop = Load.shared("Config", "Shop")

local Theme = require(script.Parent.Theme)
local UiState = require(script.Parent.UiState)
local Widgets = require(script.Parent.Widgets)

local Fusion = UiState.Fusion
local Children = Fusion.Children

local ShopPanel = {}

local function buy(itemId: string)
	Net.RequestPurchase:FireServer(itemId)
end

-- "<Robux icon> 99": the price from Roblox once loaded, Config/Shop's until then.
local function robuxText(scope, priceKey: string | any, fallback: number | any)
	return scope:Computed(function(use)
		local key = use(priceKey)
		local price = use(UiState.prices)[key]
		return `{Theme.ROBUX} {price or use(fallback)}`
	end)
end

-- A tilted tag in a card's corner.
local function badge(scope, text, color)
	return scope:New("Frame")({
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 8, 0, -10),
		Size = UDim2.fromOffset(112, 30),
		Rotation = 8,
		ZIndex = 3,
		BackgroundColor3 = color or Theme.YOLK,
		[Children] = {
			Widgets.round(scope),
			Widgets.stroke(scope, 2.5),
			Widgets.text(scope, {
				Name = "Label",
				Text = text,
				TextSize = 17,
				ZIndex = 3,
			}),
		},
	})
end

local function productCard(scope, product, accent)
	local children = {
		Widgets.corner(scope, 22),
		Widgets.gradient(scope, accent.light, accent.deep),
		Widgets.stroke(scope, 3),
		Widgets.speckles(scope, { { 0.15, 0.12, 16 }, { 0.86, 0.4, 10 }, { 0.2, 0.55, 8 }, { 0.78, 0.18, 22 } }),

		-- A soft glow behind the icon.
		scope:New("Frame")({
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 58),
			Size = UDim2.fromOffset(92, 92),
			BackgroundColor3 = Theme.WHITE,
			BackgroundTransparency = 0.65,
			[Children] = { Widgets.round(scope) },
		}),
		Widgets.text(scope, {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 58),
			Size = UDim2.fromOffset(100, 90),
			Text = accent.icon,
			-- Bigger packs get a bigger icon.
			TextSize = 44 + product.order * 9,
		}),
		Widgets.text(scope, {
			Name = "Title",
			Position = UDim2.fromOffset(0, 104),
			Size = UDim2.new(1, 0, 0, 38),
			Text = product.title,
			TextColor3 = Theme.WHITE,
			TextSize = 36,
			Stroke = 3,
		}),
		Widgets.text(scope, {
			Name = "Subtitle",
			Position = UDim2.fromOffset(0, 140),
			Size = UDim2.new(1, 0, 0, 22),
			Text = product.subtitle,
			TextColor3 = Theme.WHITE,
			TextSize = 19,
			Stroke = 2,
		}),
		Widgets.button(scope, {
			Name = "Buy",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 48),
			Text = robuxText(scope, product.id, product.robux),
			TextSize = 24,
			OnActivated = function()
				buy(product.id)
			end,
		}),
	}

	if product.grant.kind == "Luck" then
		-- Shows the time left while this boost is the one in effect.
		local active = scope:Computed(function(use)
			return use(UiState.luck) == product.grant.multiplier and use(UiState.luckSeconds) > 0
		end)
		table.insert(
			children,
			badge(
				scope,
				scope:Computed(function(use)
					if use(active) then
						return `ON  {NumberFormat.clock(use(UiState.luckSeconds))}`
					end
					return product.badge or ""
				end),
				scope:Computed(function(use)
					return if use(active) then Theme.GREEN else Theme.YOLK
				end)
			)
		)
	elseif product.badge then
		table.insert(children, badge(scope, product.badge))
	end

	return scope:New("Frame")({
		Name = product.id,
		LayoutOrder = product.order,
		BackgroundColor3 = Theme.WHITE,
		[Children] = children,
	})
end

local function productGrid(scope, section: string, accent, columns: number)
	local cards = {}
	for _, product in Shop.productsIn(section) do
		table.insert(cards, productCard(scope, product, accent))
	end
	return scope:New("Frame")({
		Name = "Grid",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		[Children] = {
			-- Room for the tilted badges that poke out of the top corners.
			Widgets.padding(scope, 12, 6, 4),
			scope:New("UIGridLayout")({
				CellSize = UDim2.new(1 / columns, -12, 0, 226),
				CellPadding = UDim2.fromOffset(14, 18),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			cards,
		},
	})
end

-- One side of the pen upgrade: a cream tile showing a pen level and how many pets it holds.
local function penTile(scope, props)
	return scope:New("Frame")({
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = props.Position,
		Size = UDim2.fromOffset(156, 116),
		Visible = props.Visible,
		BackgroundColor3 = Theme.CREAM,
		[Children] = {
			Widgets.corner(scope, 22),
			Widgets.stroke(scope, 3),
			Widgets.text(scope, {
				Name = "Icon",
				Position = UDim2.fromOffset(0, 4),
				Size = UDim2.new(1, 0, 0, 50),
				Text = props.Icon,
				TextSize = 44,
			}),
			Widgets.text(scope, {
				Name = "Level",
				Position = UDim2.fromOffset(0, 54),
				Size = UDim2.new(1, 0, 0, 28),
				Text = props.Level,
				TextSize = 26,
			}),
			Widgets.text(scope, {
				Name = "Capacity",
				Position = UDim2.fromOffset(0, 84),
				Size = UDim2.new(1, 0, 0, 20),
				Font = Theme.SMALL_FONT,
				Text = props.Capacity,
				TextColor3 = Color3.fromRGB(150, 100, 60),
				TextSize = 16,
			}),
		},
	})
end

-- The featured card: buy the next pen level with Robux or with coins.
local function penCard(scope)
	local accent = Theme.Sections.Featured
	local level = UiState.penLevel
	local isMax = scope:Computed(function(use)
		return use(level) >= Shop.MAX_PEN_LEVEL
	end)
	local notMax = scope:Computed(function(use)
		return not use(isMax)
	end)
	local nextLevel = scope:Computed(function(use)
		return Shop.PenLevels[math.min(use(level) + 1, Shop.MAX_PEN_LEVEL)]
	end)

	return scope:New("Frame")({
		Name = "PenUpgrade",
		LayoutOrder = 2,
		Size = UDim2.new(1, -8, 0, 262),
		BackgroundColor3 = Theme.WHITE,
		[Children] = {
			Widgets.corner(scope, 26),
			Widgets.gradient(scope, accent.light, accent.deep, 120),
			Widgets.stroke(scope, 4),
			Widgets.speckles(scope, {
				{ 0.08, 0.2, 22 },
				{ 0.93, 0.15, 14 },
				{ 0.5, 0.92, 12 },
				{ 0.04, 0.7, 10 },
				{ 0.96, 0.62, 20 },
			}),
			Widgets.text(scope, {
				Name = "Headline",
				Position = UDim2.fromOffset(0, 10),
				Size = UDim2.new(1, 0, 0, 40),
				Font = Theme.TITLE_FONT,
				Text = scope:Computed(function(use)
					return if use(isMax) then "YOUR PEN IS MAXED!" else "UPGRADE YOUR PEN!"
				end),
				TextColor3 = Theme.WHITE,
				TextSize = 34,
				Stroke = 3.5,
			}),

			penTile(scope, {
				Name = "Current",
				Position = scope:Computed(function(use)
					return if use(isMax) then UDim2.new(0.5, 0, 0, 58) else UDim2.new(0.22, 0, 0, 58)
				end),
				Icon = "🏡",
				Level = scope:Computed(function(use)
					return `LEVEL {use(level)}`
				end),
				Capacity = scope:Computed(function(use)
					return `{Shop.penCapacity(use(level))} pets`
				end),
			}),
			Widgets.text(scope, {
				Name = "Arrow",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 62),
				Size = UDim2.fromOffset(120, 60),
				Visible = notMax,
				Text = "➜",
				TextColor3 = Theme.WHITE,
				TextSize = 64,
				Stroke = 4,
			}),
			Widgets.text(scope, {
				Name = "Gain",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 128),
				Size = UDim2.fromOffset(170, 30),
				Visible = notMax,
				Text = "+1 PET SLOT",
				TextColor3 = Theme.YOLK,
				TextSize = 24,
				Stroke = 3,
			}),
			penTile(scope, {
				Name = "Next",
				Position = UDim2.new(0.78, 0, 0, 58),
				Visible = notMax,
				Icon = "🏡✨",
				Level = scope:Computed(function(use)
					return `LEVEL {use(nextLevel).level}`
				end),
				Capacity = scope:Computed(function(use)
					return `{Shop.penCapacity(use(nextLevel).level)} pets`
				end),
			}),

			scope:New("Frame")({
				Name = "Buttons",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -14),
				Size = UDim2.new(1, -40, 0, 52),
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
						Text = robuxText(
							scope,
							scope:Computed(function(use)
								return "PenLevel" .. use(nextLevel).level
							end),
							scope:Computed(function(use)
								return use(nextLevel).robux
							end)
						),
						TextSize = 26,
						OnActivated = function()
							buy(Shop.PEN_UPGRADE_ID)
						end,
					}),
					Widgets.button(scope, {
						Name = "BuyCoins",
						LayoutOrder = 2,
						Size = UDim2.fromScale(0.42, 1),
						Color = Theme.CREAM,
						Deep = Theme.SHELL_DARK,
						Content = {
							Widgets.coin(scope, { Position = UDim2.new(0.5, -52, 0.5, 0), Size = 30 }),
							Widgets.text(scope, {
								Name = "Label",
								Position = UDim2.fromOffset(20, 0),
								Text = scope:Computed(function(use)
									return NumberFormat.abbreviate(use(nextLevel).coins)
								end),
								TextSize = 26,
							}),
						},
						OnActivated = function()
							Net.BuyWithCoins:FireServer(Shop.PEN_UPGRADE_ID)
						end,
					}),
				},
			}),
		},
	})
end

local function passCard(scope, pass)
	local accent = Theme.Sections.Passes
	local owned = scope:Computed(function(use)
		return use(UiState.ownedPasses)[pass.id] == true
	end)
	local icon = if pass.id == "DoubleStamina" then "⚡" else "💰"

	return scope:New("Frame")({
		Name = pass.id,
		LayoutOrder = pass.order,
		Size = UDim2.new(1, -8, 0, 132),
		BackgroundColor3 = Theme.WHITE,
		[Children] = {
			Widgets.corner(scope, 24),
			Widgets.gradient(scope, accent.light, accent.deep, 100),
			Widgets.stroke(scope, 3),
			Widgets.speckles(scope, { { 0.3, 0.2, 14 }, { 0.62, 0.85, 10 }, { 0.55, 0.15, 8 } }),

			-- The badge on the left: "x2" over the pass's icon.
			scope:New("Frame")({
				Name = "Seal",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 16, 0.5, 0),
				Size = UDim2.fromOffset(100, 100),
				BackgroundColor3 = Theme.CREAM,
				[Children] = {
					Widgets.round(scope),
					Widgets.stroke(scope, 3.5),
					Widgets.text(scope, {
						Name = "Icon",
						Position = UDim2.fromOffset(0, 10),
						Size = UDim2.new(1, 0, 0, 36),
						Text = icon,
						TextSize = 32,
					}),
					Widgets.text(scope, {
						Name = "Multiplier",
						Position = UDim2.fromOffset(0, 52),
						Size = UDim2.new(1, 0, 0, 36),
						Font = Theme.TITLE_FONT,
						Text = "x2",
						TextColor3 = accent.deep,
						TextSize = 36,
					}),
				},
			}),

			Widgets.text(scope, {
				Name = "Title",
				Position = UDim2.fromOffset(132, 16),
				Size = UDim2.new(1, -310, 0, 38),
				Font = Theme.TITLE_FONT,
				Text = pass.title,
				TextColor3 = Theme.WHITE,
				TextScaled = true,
				MaxTextSize = 32,
				TextXAlignment = Enum.TextXAlignment.Left,
				Stroke = 3,
			}),
			scope:New("Frame")({
				Name = "Forever",
				Position = UDim2.fromOffset(132, 58),
				Size = UDim2.fromOffset(110, 26),
				BackgroundColor3 = Theme.YOLK,
				[Children] = {
					Widgets.round(scope),
					Widgets.stroke(scope, 2.5),
					Widgets.text(scope, { Text = pass.tagline, TextSize = 16 }),
				},
			}),
			Widgets.text(scope, {
				Name = "Description",
				Position = UDim2.fromOffset(132, 90),
				Size = UDim2.new(1, -310, 0, 30),
				Font = Theme.SMALL_FONT,
				Text = pass.description,
				TextColor3 = Theme.WHITE,
				TextScaled = true,
				MaxTextSize = 16,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Stroke = 1.5,
			}),

			Widgets.button(scope, {
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -18, 0.5, 0),
				Size = UDim2.fromOffset(150, 56),
				Visible = scope:Computed(function(use)
					return not use(owned)
				end),
				Text = robuxText(scope, pass.id, pass.robux),
				TextSize = 26,
				OnActivated = function()
					buy(pass.id)
				end,
			}),
			scope:New("Frame")({
				Name = "Owned",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -18, 0.5, 0),
				Size = UDim2.fromOffset(150, 52),
				Visible = owned,
				BackgroundColor3 = Theme.GREEN,
				[Children] = {
					Widgets.corner(scope, 14),
					Widgets.stroke(scope, 3),
					Widgets.text(scope, {
						Text = "OWNED ✔",
						TextColor3 = Theme.WHITE,
						TextSize = 24,
						Stroke = 2.5,
					}),
				},
			}),
		},
	})
end

local function section(scope, name: string, order: number, content)
	local accent = Theme.Sections[name]
	return scope:New("Frame")({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		[Children] = {
			Widgets.list(scope, { Padding = 6, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
			Widgets.sectionHeader(scope, {
				Name = "Header",
				LayoutOrder = 1,
				Title = accent.name,
				Icon = accent.icon,
				Light = accent.light,
				Deep = accent.deep,
				Blurb = accent.blurb,
			}),
			content,
		},
	})
end

function ShopPanel.build(scope)
	local open = scope:Computed(function(use)
		return use(UiState.openPanel) == "Shop"
	end)
	local selected = scope:Value(Shop.Sections[1])
	local sections: { [string]: Instance } = {}
	local scroll: ScrollingFrame

	local function jump(name: string)
		selected:set(name)
		local target = sections[name]
		if scroll == nil or target == nil then
			return
		end
		-- Needs the layout engine (absolute positions), so it does nothing outside a real game.
		pcall(function()
			local offset = target.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
			scroll.CanvasPosition = Vector2.new(0, math.max(0, offset - 8))
		end)
	end

	local passes = {}
	for _, pass in Shop.Passes do
		table.insert(passes, passCard(scope, pass))
	end
	local passList = scope:New("Frame")({
		Name = "List",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		[Children] = {
			Widgets.list(scope, { Padding = 12, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
			passes,
		},
	})

	local contents = {
		Featured = penCard(scope),
		Luck = productGrid(scope, "Luck", Theme.Sections.Luck, 2),
		Stamina = productGrid(scope, "Stamina", Theme.Sections.Stamina, 3),
		Coins = productGrid(scope, "Coins", Theme.Sections.Coins, 3),
		Passes = passList,
	}
	local sectionFrames = {}
	local chips = {}
	for order, name in Shop.Sections do
		local frame = section(scope, name, order, contents[name])
		sections[name] = frame
		table.insert(sectionFrames, frame)

		local accent = Theme.Sections[name]
		local isSelected = scope:Computed(function(use)
			return use(selected) == name
		end)
		table.insert(
			chips,
			Widgets.button(scope, {
				Name = name,
				LayoutOrder = order,
				Size = UDim2.new(1 / #Shop.Sections, -8, 1, 0),
				Color = scope:Computed(function(use)
					return if use(isSelected) then accent.light else Theme.CREAM
				end),
				Deep = scope:Computed(function(use)
					return if use(isSelected) then accent.deep else Theme.SHELL_DARK
				end),
				Text = `{accent.icon} {accent.name}`,
				TextSize = 18,
				OnActivated = function()
					jump(name)
				end,
			})
		)
	end

	scroll = Widgets.scroller(scope, {
		Name = "Scroll",
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		Padding = 22,
		Children = sectionFrames,
	})

	-- The "+" buttons on the HUD open the shop at a section.
	scope:Observer(UiState.shopSection):onChange(function()
		local name = Fusion.peek(UiState.shopSection)
		if name then
			-- Wait a moment so the newly shown panel has been laid out.
			task.delay(0.05, jump, name)
		end
	end)

	return Widgets.panel(scope, {
		Name = "ShopPanel",
		Title = "COOP SHOP",
		Icon = "🥚",
		Size = UDim2.new(0, 720, 0.88, 0),
		MaxSize = Vector2.new(math.huge, 640),
		Visible = open,
		OnClose = function()
			UiState.openPanel:set(nil)
		end,
		Body = {
			scope:New("Frame")({
				Name = "Sections",
				Position = UDim2.fromOffset(18, 4),
				Size = UDim2.new(1, -36, 0, 46),
				BackgroundTransparency = 1,
				[Children] = {
					Widgets.list(scope, {
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = 8,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
					}),
					chips,
				},
			}),
			scroll,
		},
	})
end

return ShopPanel
