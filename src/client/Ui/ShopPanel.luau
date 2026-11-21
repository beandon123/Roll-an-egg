-- The shop panel: packs (a pet, dollars, stamina, a trail and revives at once), featured upgrades (the training
-- stick's next tier, and the pen's next level), server luck boosts, Max Stamina, revives, dollar packs, and game
-- passes (Config/Shop). Buttons only ask the server; the server checks prices and shows Roblox's purchase prompt.

local Load = require(script.Parent.Parent.Load)
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")
local PetWorth = Load.shared("PetWorth")
local Shop = Load.shared("Config", "Shop")
local Trails = Load.shared("Config", "Trails")

local Panels = require(script.Parent.Panels)
local Theme = require(script.Parent.Theme)
local TrainingUi = require(script.Parent.TrainingUi)
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
			Widgets.gradient(scope, Theme.WHITE, Color3.fromRGB(214, 214, 224)),
			Widgets.stroke(scope, 2.5, Theme.WHITE),
			Widgets.text(scope, {
				Name = "Label",
				Text = text,
				TextSize = 17,
				Font = Theme.TITLE_FONT,
				Stroke = 2,
				ZIndex = 3,
			}),
		},
	})
end

local function productCard(scope, product, accent)
	local children = {
		Widgets.cardSkin(scope, accent.light, accent.deep, 22),

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

local function productGrid(scope, section: string, accent, columns: number, layoutOrder: number?)
	local cards = {}
	for _, product in Shop.productsIn(section) do
		table.insert(cards, productCard(scope, product, accent))
	end
	return scope:New("Frame")({
		Name = "Grid",
		LayoutOrder = layoutOrder or 2,
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

-- One side of the pen upgrade: a dark tile showing a pen level and how many pets it holds.
local function penTile(scope, props)
	return scope:New("Frame")({
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = props.Position,
		Size = UDim2.fromOffset(156, 116),
		Visible = props.Visible,
		BackgroundColor3 = Theme.CARD_DEEP,
		[Children] = {
			Widgets.corner(scope, 22),
			Widgets.stroke(scope, 3, Theme.CARD_EDGE),
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
				TextColor3 = Theme.TEXT_SOFT,
				TextSize = 16,
			}),
		},
	})
end

-- The featured card: buy the next pen level with Robux or with dollars (the same as the green button by the pen).
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
		LayoutOrder = 3,
		Size = UDim2.new(1, -8, 0, 262),
		BackgroundColor3 = Theme.WHITE,
		[Children] = {
			Widgets.cardSkin(scope, accent.light, accent.deep, 26),
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
				Text = "+1 PET  +1 EGG",
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
						Name = "BuyDollars",
						LayoutOrder = 2,
						Size = UDim2.fromScale(0.42, 1),
						Color = Theme.GREEN,
						Deep = Theme.GREEN_DEEP,
						Content = {
							Widgets.dollar(scope, { Position = UDim2.new(0.5, -52, 0.5, 0), Size = 30 }),
							Widgets.text(scope, {
								Name = "Label",
								Position = UDim2.fromOffset(20, 0),
								Text = scope:Computed(function(use)
									return NumberFormat.abbreviate(use(nextLevel).dollars)
								end),
								TextSize = 26,
							}),
						},
						OnActivated = function()
							Net.BuyWithDollars:FireServer(Shop.PEN_UPGRADE_ID)
						end,
					}),
				},
			}),
		},
	})
end

-- "Double your Max Stamina": the multiplier now, what the next purchase makes it, and that purchase's price.
local function doublingCard(scope)
	local accent = Theme.Sections.Stamina
	local multiplier = UiState.staminaMultiplier
	local isMax = scope:Computed(function(use)
		return use(multiplier) >= Shop.MAX_STAMINA_MULTIPLIER
	end)
	local notMax = scope:Computed(function(use)
		return not use(isMax)
	end)
	local nextStep = scope:Computed(function(use)
		return Shop.StaminaDoublings[math.min(use(multiplier) * 2, Shop.MAX_STAMINA_MULTIPLIER)]
	end)

	return scope:New("Frame")({
		Name = "StaminaDoubling",
		LayoutOrder = 2,
		Size = UDim2.new(1, -8, 0, 150),
		BackgroundColor3 = Theme.WHITE,
		[Children] = {
			Widgets.cardSkin(scope, accent.light, accent.deep, 24),

			scope:New("Frame")({
				Name = "Seal",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 16, 0.5, 0),
				Size = UDim2.fromOffset(108, 108),
				BackgroundColor3 = Theme.CARD_DEEP,
				[Children] = {
					Widgets.round(scope),
					Widgets.stroke(scope, 3.5, accent.light),
					Widgets.text(scope, {
						Name = "Icon",
						Position = UDim2.fromOffset(0, 10),
						Size = UDim2.new(1, 0, 0, 40),
						Text = "⚡",
						TextSize = 36,
					}),
					Widgets.text(scope, {
						Name = "Multiplier",
						Position = UDim2.fromOffset(0, 54),
						Size = UDim2.new(1, 0, 0, 40),
						Font = Theme.TITLE_FONT,
						Text = "x2",
						TextColor3 = accent.light,
						TextSize = 40,
						Stroke = 3,
					}),
				},
			}),

			Widgets.text(scope, {
				Name = "Title",
				Position = UDim2.fromOffset(140, 14),
				Size = UDim2.new(1, -320, 0, 36),
				Font = Theme.TITLE_FONT,
				Text = scope:Computed(function(use)
					return if use(isMax) then "STAMINA MAXED OUT!" else "DOUBLE YOUR STAMINA!"
				end),
				TextColor3 = Theme.WHITE,
				TextScaled = true,
				MaxTextSize = 32,
				TextXAlignment = Enum.TextXAlignment.Left,
				Stroke = 3,
			}),
			-- "x32 ▸ x64": the multiplier now and after this purchase.
			scope:New("Frame")({
				Name = "Multipliers",
				Position = UDim2.fromOffset(140, 54),
				Size = UDim2.new(1, -320, 0, 58),
				BackgroundTransparency = 1,
				[Children] = {
					Widgets.list(scope, {
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = 8,
						VerticalAlignment = Enum.VerticalAlignment.Center,
					}),
					Widgets.text(scope, {
						Name = "From",
						LayoutOrder = 1,
						Size = UDim2.fromOffset(118, 50),
						Font = Theme.TITLE_FONT,
						Text = scope:Computed(function(use)
							return `x{use(multiplier)}`
						end),
						TextColor3 = Theme.WHITE,
						TextScaled = true,
						MaxTextSize = 44,
						TextXAlignment = Enum.TextXAlignment.Right,
						Stroke = 3,
					}),
					Widgets.text(scope, {
						Name = "Arrow",
						LayoutOrder = 2,
						Size = UDim2.fromOffset(34, 50),
						Visible = notMax,
						Text = "▸",
						TextColor3 = Theme.WHITE,
						TextSize = 40,
						Stroke = 3,
					}),
					Widgets.text(scope, {
						Name = "To",
						LayoutOrder = 3,
						Size = UDim2.fromOffset(150, 58),
						Visible = notMax,
						Font = Theme.TITLE_FONT,
						Text = scope:Computed(function(use)
							return `x{use(nextStep).to}`
						end),
						TextColor3 = Theme.YOLK,
						TextScaled = true,
						MaxTextSize = 54,
						TextXAlignment = Enum.TextXAlignment.Left,
						Stroke = 3.5,
					}),
				},
			}),
			Widgets.text(scope, {
				Name = "Note",
				Position = UDim2.fromOffset(140, 114),
				Size = UDim2.new(1, -320, 0, 22),
				Font = Theme.SMALL_FONT,
				Text = `Kept forever  •  up to x{Shop.MAX_STAMINA_MULTIPLIER}`,
				TextColor3 = Theme.WHITE,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				Stroke = 1.5,
			}),

			Widgets.button(scope, {
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -18, 0.5, 0),
				Size = UDim2.fromOffset(150, 58),
				Visible = notMax,
				Text = robuxText(
					scope,
					scope:Computed(function(use)
						return "StaminaDoubling" .. use(nextStep).to
					end),
					scope:Computed(function(use)
						return use(nextStep).robux
					end)
				),
				TextSize = 26,
				OnActivated = function()
					buy(Shop.STAMINA_DOUBLING_ID)
				end,
			}),
			scope:New("Frame")({
				Name = "Maxed",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -18, 0.5, 0),
				Size = UDim2.fromOffset(150, 54),
				Visible = isMax,
				BackgroundColor3 = Theme.GREEN,
				[Children] = {
					Widgets.corner(scope, 14),
					Widgets.stroke(scope, 3),
					Widgets.text(scope, {
						Text = "MAXED ✔",
						TextColor3 = Theme.WHITE,
						TextSize = 24,
						Stroke = 2.5,
					}),
				},
			}),
		},
	})
end

-- The colour a pack's pet's name is written in, by its variant.
local PACK_PET_COLORS = {
	Molten = Color3.fromRGB(255, 150, 60),
	Crystal = Color3.fromRGB(150, 245, 255),
}

-- One thing in a pack, on a dark tile: an icon, a value ("+$250K") and what it is ("CASH"), and a tag such as
-- "FOREVER" on its corner.
local function packTile(scope, props)
	return scope:New("Frame")({
		Name = props.Name,
		LayoutOrder = props.Order,
		BackgroundColor3 = Theme.CARD_DEEP,
		[Children] = {
			Widgets.corner(scope, 12),
			Widgets.stroke(scope, 2.5, Theme.CARD_EDGE),
			Widgets.text(scope, {
				Name = "Icon",
				Position = UDim2.fromOffset(0, 4),
				Size = UDim2.new(1, 0, 0, 30),
				Text = props.Icon,
				TextSize = 26,
			}),
			Widgets.text(scope, {
				Name = "Value",
				Position = UDim2.fromOffset(4, 34),
				Size = UDim2.new(1, -8, 0, 22),
				Text = props.Value,
				TextColor3 = props.Color or Theme.WHITE,
				TextScaled = true,
				MaxTextSize = 20,
				Stroke = 2,
			}),
			Widgets.text(scope, {
				Name = "Label",
				Position = UDim2.fromOffset(4, 56),
				Size = UDim2.new(1, -8, 0, 16),
				Font = Theme.SMALL_FONT,
				Text = props.Label,
				TextColor3 = Theme.TEXT_SOFT,
				TextScaled = true,
				MaxTextSize = 13,
			}),
			if props.Tag
				then Widgets.tag(scope, {
					Name = "Tag",
					Text = props.Tag,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 6, 0, 0),
					Size = UDim2.fromOffset(84, 22),
					Rotation = 6,
					Color = Theme.YOLK,
					Deep = Theme.YOLK_DEEP,
					TextSize = 13,
					ZIndex = 3,
				})
				else nil,
		},
	})
end

-- A pack (Config/Shop): its pet turning on the left over a burst of rays (the model is put in by ShopController),
-- its name, a tile for each thing in it, what those would cost on their own crossed out, and its price.
local function packCard(scope, pack)
	local colors = Theme.Packs[pack.id] or { light = Theme.VIOLET, deep = Theme.VIOLET_DEEP, ray = Theme.WHITE }
	local owned = scope:Computed(function(use)
		return use(UiState.ownedPacks)[pack.id] == true
	end)
	local origin = Shop.petOrigin(pack.pet.kind)
	local income = if origin
		then PetWorth.income({ zone = origin.zone, rarity = origin.rarity, variant = pack.pet.variant })
		else 0
	local trail = Trails.ById[pack.trail]
	local trailName = if trail then string.upper((string.gsub(trail.name, " Trail$", ""))) else pack.trail

	local rays = {}
	for index = 1, 6 do
		table.insert(
			rays,
			scope:New("Frame")({
				Name = "Ray" .. index,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.55),
				Size = UDim2.fromOffset(640, 30),
				Rotation = index * 30,
				BackgroundColor3 = colors.ray,
				BackgroundTransparency = 0.72,
				BorderSizePixel = 0,
			})
		)
	end

	local tiles = {
		packTile(scope, {
			Name = "Pet",
			Order = 1,
			Icon = "🐾",
			Value = `${NumberFormat.abbreviate(income)}/s`,
			Color = Theme.GREEN,
			Label = string.upper(Panels.petName(pack.pet.kind)),
		}),
		packTile(scope, {
			Name = "Cash",
			Order = 2,
			Icon = "💵",
			Value = `+${NumberFormat.abbreviate(pack.dollars)}`,
			Color = Theme.GREEN,
			Label = "CASH",
		}),
		packTile(scope, {
			Name = "Stamina",
			Order = 3,
			Icon = "⚡",
			Value = `x{pack.stamina}`,
			Label = "STAMINA",
			Tag = "FOREVER",
		}),
		packTile(scope, {
			Name = "Trail",
			Order = 4,
			Icon = "✨",
			Value = trailName,
			Label = "TRAIL",
		}),
		packTile(scope, {
			Name = "Revives",
			Order = 5,
			Icon = "💖",
			Value = `+{pack.revives}`,
			Label = "REVIVES",
		}),
	}
	if pack.luck then
		table.insert(
			tiles,
			packTile(scope, {
				Name = "Luck",
				Order = 6,
				Icon = "🍀",
				Value = `x{pack.luck.multiplier}`,
				Label = "LUCK",
				Tag = `{math.floor(pack.luck.duration / 60)} MIN`,
			})
		)
	end

	local worth = Shop.packWorth(pack)
	return scope:New("Frame")({
		Name = pack.id,
		LayoutOrder = pack.order,
		Size = UDim2.new(1, -8, 0, 340),
		BackgroundColor3 = Theme.WHITE,
		[Children] = {
			Widgets.corner(scope, 24),
			Widgets.gradient(scope, colors.light, colors.deep, 120),
			scope:New("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.WHITE,
				Thickness = 4,
			}),
			-- Rays fanning out behind the pet, and the pet itself.
			scope:New("Frame")({
				Name = "Burst",
				Size = UDim2.fromScale(0.42, 1),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				[Children] = rays,
			}),
			scope:New("ViewportFrame")({
				Name = "PetView",
				Position = UDim2.fromOffset(8, 36),
				Size = UDim2.new(0.42, -8, 1, -44),
				BackgroundTransparency = 1,
				Ambient = Color3.fromRGB(180, 176, 196),
				LightColor = Color3.fromRGB(255, 250, 240),
				LightDirection = Vector3.new(-1, -1.5, -1),
				[Children] = { scope:New("WorldModel")({ Name = "World" }) },
			}),
			Widgets.tag(scope, {
				Name = "Badge",
				Text = pack.badge,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(-10, 18),
				Size = UDim2.fromOffset(200, 40),
				Rotation = -7,
				Color = if pack.order == 1 then Theme.YOLK else Theme.CORAL,
				Deep = if pack.order == 1 then Theme.YOLK_DEEP else Theme.CORAL_DEEP,
				TextSize = 22,
				ZIndex = 3,
			}),

			scope:New("Frame")({
				Name = "Info",
				Position = UDim2.new(0.42, 0, 0, 12),
				Size = UDim2.new(0.58, -16, 1, -24),
				BackgroundTransparency = 1,
				[Children] = {
					Widgets.text(scope, {
						Name = "Title",
						Size = UDim2.new(1, 0, 0, 46),
						Font = Theme.TITLE_FONT,
						Text = pack.title,
						TextColor3 = Theme.YOLK,
						TextSize = 44,
						Stroke = 4,
					}),
					Widgets.text(scope, {
						Name = "PetName",
						Position = UDim2.fromOffset(0, 46),
						Size = UDim2.new(1, 0, 0, 24),
						Text = string.upper(Panels.fullPetName(pack.pet.kind, pack.pet.variant)),
						TextColor3 = PACK_PET_COLORS[pack.pet.variant] or Theme.WHITE,
						TextScaled = true,
						MaxTextSize = 22,
						Stroke = 2.5,
					}),
					scope:New("Frame")({
						Name = "Items",
						Position = UDim2.fromOffset(0, 80),
						Size = UDim2.new(1, 0, 0, 172),
						BackgroundTransparency = 1,
						[Children] = {
							scope:New("UIGridLayout")({
								CellSize = UDim2.new(1 / 3, -8, 0, 80),
								CellPadding = UDim2.fromOffset(10, 10),
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								SortOrder = Enum.SortOrder.LayoutOrder,
							}),
							tiles,
						},
					}),

					-- "WORTH <Robux> 514" struck through, the button with "-71%" on a sticker, and the price.
					scope:New("Frame")({
						Name = "Worth",
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.fromScale(0, 1),
						Size = UDim2.new(0.5, 0, 0, 56),
						BackgroundTransparency = 1,
						[Children] = {
							Widgets.text(scope, {
								Name = "Label",
								Size = UDim2.fromOffset(64, 30),
								Font = Theme.SMALL_FONT,
								Text = "WORTH",
								TextSize = 15,
								TextXAlignment = Enum.TextXAlignment.Left,
								Stroke = 1.5,
							}),
							Widgets.text(scope, {
								Name = "Old",
								Position = UDim2.fromOffset(64, 0),
								Size = UDim2.new(1, -64, 0, 30),
								Text = `{Theme.ROBUX} {worth}`,
								TextColor3 = Theme.TEXT_SOFT,
								TextScaled = true,
								MaxTextSize = 22,
								TextXAlignment = Enum.TextXAlignment.Left,
								Stroke = 2,
							}),
							-- Struck through.
							scope:New("Frame")({
								Name = "Strike",
								AnchorPoint = Vector2.new(0, 0.5),
								Position = UDim2.fromOffset(60, 15),
								Size = UDim2.fromOffset(72, 3),
								Rotation = -8,
								BackgroundColor3 = Theme.CORAL,
								BorderSizePixel = 0,
							}),
							Widgets.text(scope, {
								Name = "Once",
								Position = UDim2.fromOffset(0, 32),
								Size = UDim2.new(1, 0, 0, 18),
								Font = Theme.SMALL_FONT,
								Text = "One per player",
								TextColor3 = Theme.WHITE,
								TextSize = 13,
								TextXAlignment = Enum.TextXAlignment.Left,
								Stroke = 1.5,
							}),
						},
					}),
					Widgets.button(scope, {
						Name = "Buy",
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.fromScale(1, 1),
						Size = UDim2.new(0.48, 0, 0, 56),
						Visible = scope:Computed(function(use)
							return not use(owned)
						end),
						Color = Theme.GREEN,
						Deep = Theme.GREEN_DEEP,
						Text = robuxText(scope, pack.id, pack.robux),
						TextSize = 30,
						OnActivated = function()
							buy(pack.id)
						end,
					}),
					Widgets.tag(scope, {
						Name = "Discount",
						Text = `-{Shop.packDiscount(pack)}%`,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(1, -8, 1, -58),
						Size = UDim2.fromOffset(74, 30),
						Rotation = 10,
						TextSize = 20,
						ZIndex = 4,
					}),
					scope:New("Frame")({
						Name = "Owned",
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.fromScale(1, 1),
						Size = UDim2.new(0.48, 0, 0, 52),
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
			}),
		},
	})
end

-- How many revives the player has, over the revive products.
local function revivesNote(scope)
	return Widgets.text(scope, {
		Name = "Have",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 26),
		Text = scope:Computed(function(use)
			local count = use(UiState.revives)
			return `💖 You have {count} {if count == 1 then "revive" else "revives"}`
		end),
		TextSize = 20,
		Stroke = 2,
	})
end

-- Icons for pass seals, by pass id.
local PASS_ICONS = { DoubleDollars = "💵" }

local function passCard(scope, pass)
	local accent = Theme.Sections.Passes
	local owned = scope:Computed(function(use)
		return use(UiState.ownedPasses)[pass.id] == true
	end)
	local icon = PASS_ICONS[pass.id] or "🎟️"

	return scope:New("Frame")({
		Name = pass.id,
		LayoutOrder = pass.order,
		Size = UDim2.new(1, -8, 0, 132),
		BackgroundColor3 = Theme.WHITE,
		[Children] = {
			Widgets.cardSkin(scope, accent.light, accent.deep, 24),

			-- The badge on the left: "x2" over the pass's icon.
			scope:New("Frame")({
				Name = "Seal",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 16, 0.5, 0),
				Size = UDim2.fromOffset(100, 100),
				BackgroundColor3 = Theme.CARD_DEEP,
				[Children] = {
					Widgets.round(scope),
					Widgets.stroke(scope, 3.5, accent.light),
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
						TextColor3 = accent.light,
						TextSize = 36,
						Stroke = 3,
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
					Widgets.text(scope, { Text = pass.tagline, TextSize = 16, Stroke = 2 }),
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

	local packs = {}
	for _, pack in Shop.Packs do
		table.insert(packs, packCard(scope, pack))
	end
	local packList = scope:New("Frame")({
		Name = "List",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		[Children] = {
			-- Room for the tilted stickers that poke out of the top corners.
			Widgets.padding(scope, 10, 8, 4),
			Widgets.list(scope, { Padding = 22, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
			packs,
		},
	})

	local contents = {
		Packs = packList,
		Featured = { TrainingUi.stickCard(scope, 2), penCard(scope) },
		Luck = productGrid(scope, "Luck", Theme.Sections.Luck, 2),
		Stamina = { doublingCard(scope), productGrid(scope, "Stamina", Theme.Sections.Stamina, 3, 3) },
		Revives = { revivesNote(scope), productGrid(scope, "Revives", Theme.Sections.Revives, 3, 3) },
		Dollars = productGrid(scope, "Dollars", Theme.Sections.Dollars, 3),
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
					return if use(isSelected) then accent.light else Theme.CARD
				end),
				Deep = scope:Computed(function(use)
					return if use(isSelected) then accent.deep else Theme.CARD_DEEP
				end),
				Text = `{accent.icon} {accent.name}`,
				TextSize = if #Shop.Sections > 5 then 15 else 18,
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
