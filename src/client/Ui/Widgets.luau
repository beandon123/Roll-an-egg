-- Small building blocks for the UI, in the shared look (Ui/Theme). Each takes a Fusion scope and returns an
-- instance (or a list of instances) ready to drop into [Children].
--
-- Props may be plain values or Fusion state objects, as usual with Fusion.

local Theme = require(script.Parent.Theme)
local UiState = require(script.Parent.UiState)

local Fusion = UiState.Fusion
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

local Widgets = {}

function Widgets.corner(scope, radius: number | UDim)
	return scope:New("UICorner")({
		CornerRadius = if typeof(radius) == "UDim" then radius else UDim.new(0, radius :: number),
	})
end

-- A rounded-pill corner, whatever the size.
function Widgets.round(scope)
	return Widgets.corner(scope, UDim.new(0.5, 0))
end

-- An outline. Inside a TextLabel it outlines the text; inside a frame, the frame's border.
function Widgets.stroke(scope, thickness: number?, color: Color3?, transparency: number?)
	return scope:New("UIStroke")({
		Color = color or Theme.INK,
		Thickness = thickness or 3,
		Transparency = transparency or 0,
	})
end

-- A frame outline (as opposed to a text outline) for TextButtons and TextLabels.
function Widgets.border(scope, thickness: number?, color: Color3?)
	return scope:New("UIStroke")({
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color or Theme.INK,
		Thickness = thickness or 3,
	})
end

-- Top-to-bottom color fade, from `light` to `deep`.
function Widgets.gradient(scope, light: Color3, deep: Color3, rotation: number?)
	return scope:New("UIGradient")({
		Color = ColorSequence.new(light, deep),
		Rotation = rotation or 90,
	})
end

function Widgets.padding(scope, top: number, side: number?, bottom: number?)
	return scope:New("UIPadding")({
		PaddingTop = UDim.new(0, top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, side or top),
		PaddingRight = UDim.new(0, side or top),
	})
end

function Widgets.list(scope, props)
	return scope:New("UIListLayout")({
		FillDirection = props.FillDirection or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, props.Padding or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = props.HorizontalAlignment or Enum.HorizontalAlignment.Left,
		VerticalAlignment = props.VerticalAlignment or Enum.VerticalAlignment.Top,
	})
end

-- A text label in the house style: white unless told otherwise. `Stroke` (a thickness) gives it a dark navy
-- outline.
function Widgets.text(scope, props)
	return scope:New("TextLabel")({
		Name = props.Name,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or UDim2.fromScale(1, 1),
		AutomaticSize = props.AutomaticSize,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		Rotation = props.Rotation,
		BackgroundTransparency = 1,
		Font = props.Font or Theme.FONT,
		Text = props.Text,
		TextColor3 = props.TextColor3 or Theme.WHITE,
		TextSize = props.TextSize or 20,
		TextScaled = props.TextScaled,
		TextWrapped = props.TextWrapped,
		TextXAlignment = props.TextXAlignment,
		TextYAlignment = props.TextYAlignment,
		[Children] = {
			if props.Stroke then Widgets.stroke(scope, props.Stroke, props.StrokeColor) else nil,
			if props.TextScaled and props.MaxTextSize
				then scope:New("UITextSizeConstraint")({ MaxTextSize = props.MaxTextSize })
				else nil,
		},
	})
end

-- A green dollar badge, for prices and the wallet. `Size` is its width in pixels.
function Widgets.dollar(scope, props)
	local size = props.Size or 28
	return scope:New("Frame")({
		Name = props.Name or "Dollar",
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = props.Position,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = props.LayoutOrder,
		BackgroundColor3 = Theme.DOLLAR,
		[Children] = {
			Widgets.round(scope),
			Widgets.stroke(scope, math.max(2, size / 12), Theme.DOLLAR_DEEP),
			Widgets.text(scope, {
				Name = "Sign",
				Text = "$",
				TextColor3 = Theme.WHITE,
				TextSize = math.floor(size * 0.7),
				Stroke = math.max(1.5, size / 16),
			}),
		},
	})
end

-- Soft dots scattered over a card, like the speckles on an egg. `spots` is a list of { x, y, size } (x and y as
-- fractions of the parent).
function Widgets.speckles(scope, spots: { { number } }, color: Color3?, transparency: number?)
	local dots = {}
	for index, spot in spots do
		table.insert(
			dots,
			scope:New("Frame")({
				Name = "Speckle" .. index,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spot[1], spot[2]),
				Size = UDim2.fromOffset(spot[3], spot[3]),
				BackgroundColor3 = color or Theme.WHITE,
				BackgroundTransparency = transparency or 0.78,
				[Children] = { Widgets.round(scope) },
			})
		)
	end
	return dots
end

-- A chunky button (purple unless told otherwise, like the reference's main button): a glossy colored face sitting
-- on a darker "lip", with a little squash when pressed. Its text is white with a navy outline unless told otherwise.
-- props: Name, Size, Position, AnchorPoint, LayoutOrder, Visible, Color, Deep, Text, TextColor3, TextSize,
-- Stroke (text outline thickness; 0 for none), Content (children to show instead of Text), Radius, OnActivated.
function Widgets.button(scope, props)
	local squash = scope:Value(1)
	local scale = scope:Spring(squash, 45, 0.55)
	local radius = props.Radius or UDim.new(0, 14)

	return scope:New("TextButton")({
		Name = props.Name,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		[OnEvent("Activated")] = function()
			squash:set(0.9)
			task.delay(0.08, function()
				squash:set(1)
			end)
			if props.OnActivated then
				props.OnActivated()
			end
		end,
		[Children] = {
			scope:New("UIScale")({ Scale = scale }),
			scope:New("Frame")({
				Name = "Lip",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = props.Deep or Theme.VIOLET_DEEP,
				[Children] = {
					Widgets.corner(scope, radius),
					Widgets.stroke(scope, 3),
				},
			}),
			scope:New("Frame")({
				Name = "Face",
				Size = UDim2.new(1, 0, 1, -5),
				BackgroundColor3 = props.Color or Theme.VIOLET,
				[Children] = {
					Widgets.corner(scope, radius),
					-- Lighter at the top, a little deeper at the bottom.
					scope:New("UIGradient")({
						Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(214, 214, 224)),
						Rotation = 90,
					}),
					-- A soft shine across the top.
					scope:New("Frame")({
						Name = "Shine",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 3),
						Size = UDim2.new(1, -12, 0.38, 0),
						BackgroundColor3 = Theme.WHITE,
						BackgroundTransparency = 0.72,
						[Children] = { Widgets.corner(scope, radius) },
					}),
					props.Content or Widgets.text(scope, {
						Name = "Label",
						Text = props.Text,
						TextColor3 = props.TextColor3 or Theme.WHITE,
						TextSize = props.TextSize or 22,
						Stroke = if props.Stroke == 0 then nil else props.Stroke or 2.5,
					}),
				},
			}),
		},
	})
end

-- The "x" button in a panel's corner.
function Widgets.closeButton(scope, onClose: () -> ())
	return Widgets.button(scope, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 8, 0, 4),
		Size = UDim2.fromOffset(54, 54),
		Color = Theme.CORAL,
		Deep = Theme.CORAL_DEEP,
		Radius = UDim.new(0.5, 0),
		Text = "✕",
		TextColor3 = Theme.WHITE,
		TextSize = 28,
		Stroke = 2.5,
		OnActivated = onClose,
	})
end

-- A panel's frame, shared with the panels that build their own insides: a thick white rim round a deep indigo
-- body that darkens towards the bottom.
function Widgets.panelSkin(scope)
	return {
		Widgets.corner(scope, 28),
		scope:New("UIStroke")({
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.RIM,
			Thickness = 6,
		}),
		Widgets.gradient(scope, Theme.PANEL, Theme.PANEL_DEEP),
	}
end

-- A panel's glossy title band: white fading to lavender, its bottom edge squared off against the body, and a big
-- white title outlined in navy (on the left, or in the middle if `Centered`). `Text` may be state; other children
-- (a close button) go in `Extra`.
function Widgets.titleBand(scope, props)
	return scope:New("Frame")({
		Name = props.Name or "TitleBar",
		Size = UDim2.new(1, 0, 0, props.Height or 70),
		BackgroundColor3 = Theme.WHITE,
		ZIndex = props.ZIndex,
		[Children] = {
			Widgets.corner(scope, 28),
			Widgets.gradient(scope, Theme.HEADER_TOP, Theme.HEADER_BOTTOM),
			-- Squares off the band's bottom corners, so it meets the body in a straight line.
			scope:New("Frame")({
				Name = "Foot",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = Theme.HEADER_BOTTOM,
				BorderSizePixel = 0,
			}),
			scope:New("Frame")({
				Name = "Edge",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 3),
				BackgroundColor3 = Theme.CARD_EDGE,
				BorderSizePixel = 0,
			}),
			Widgets.text(scope, {
				Name = "Title",
				Position = UDim2.fromOffset(if props.Centered then 0 else 22, 4),
				Size = if props.Centered then UDim2.new(1, 0, 1, -10) else UDim2.new(1, -100, 1, -10),
				Font = Theme.TITLE_FONT,
				Text = props.Text,
				TextColor3 = Theme.WHITE,
				TextSize = props.TextSize or 38,
				TextXAlignment = if props.Centered then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
				Stroke = 4,
			}),
			props.Extra,
		},
	})
end

-- A panel: white rim, glossy title band, deep indigo body, close button. `body` children go under the title.
-- props: Name, Title, Icon, Size, Visible (state), OnClose, Body (children).
function Widgets.panel(scope, props)
	local open = props.Visible
	local scale = scope:Spring(
		scope:Computed(function(use)
			return if use(open) then 1 else 0.8
		end),
		32,
		0.7
	)

	return scope:New("Frame")({
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = props.Size,
		Visible = open,
		BackgroundColor3 = Theme.WHITE,
		ZIndex = 20,
		[Children] = {
			scope:New("UIScale")({ Scale = scale }),
			scope:New("UISizeConstraint")({ MaxSize = props.MaxSize or Vector2.new(math.huge, 600) }),
			Widgets.panelSkin(scope),
			Widgets.titleBand(scope, {
				Text = `{props.Icon}  {props.Title}`,
				Extra = Widgets.closeButton(scope, props.OnClose),
			}),

			scope:New("Frame")({
				Name = "Body",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 74),
				Size = UDim2.new(1, 0, 1, -78),
				[Children] = props.Body,
			}),
		},
	})
end

-- A scrolling list for a panel body.
function Widgets.scroller(scope, props)
	return scope:New("ScrollingFrame")({
		Name = props.Name or "Scroll",
		Position = props.Position,
		Size = props.Size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.TEXT_SOFT,
		ScrollBarImageTransparency = 0.3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		[Children] = {
			Widgets.padding(scope, 12, 18, 18),
			Widgets.list(scope, {
				Padding = props.Padding or 12,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
			props.Children,
		},
	})
end

-- A section heading: its icon and name in capitals on the left, a thin line running off to the right, and a line
-- of small print under it. `Light` colours the line's start (the section's accent).
function Widgets.sectionHeader(scope, props)
	local width = props.Width or 260
	return scope:New("Frame")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, if props.Blurb then 58 else 36),
		BackgroundTransparency = 1,
		[Children] = {
			scope:New("Frame")({
				Name = "Ribbon",
				Size = UDim2.fromOffset(width, 34),
				BackgroundTransparency = 1,
				[Children] = {
					Widgets.text(scope, {
						Name = "Label",
						Text = `{props.Icon}  {string.upper(props.Title)}`,
						TextColor3 = Theme.WHITE,
						TextSize = 24,
						TextXAlignment = Enum.TextXAlignment.Left,
						Stroke = 2.5,
					}),
				},
			}),
			scope:New("Frame")({
				Name = "Line",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(width + 8, 17),
				Size = UDim2.new(1, -width - 8, 0, 4),
				BackgroundColor3 = Theme.WHITE,
				[Children] = {
					Widgets.round(scope),
					scope:New("UIGradient")({
						Color = ColorSequence.new(props.Light or Theme.TEXT_SOFT, Theme.TEXT_SOFT),
						Transparency = NumberSequence.new(0.1, 0.85),
					}),
				},
			}),
			if props.Blurb
				then Widgets.text(scope, {
					Name = "Blurb",
					Position = UDim2.fromOffset(2, 36),
					Size = UDim2.new(1, 0, 0, 20),
					Font = Theme.SMALL_FONT,
					Text = props.Blurb,
					TextColor3 = Theme.TEXT_SOFT,
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Left,
				})
				else nil,
		},
	})
end

-- How a card is painted, for a frame whose BackgroundColor3 is white: `deep` fading darker towards the bottom, with
-- a bright `light` edge, like the reference's mint cards. Each shop section's accent paints its cards this way.
function Widgets.cardSkin(scope, light: Color3, deep: Color3, radius: number?)
	return {
		Widgets.corner(scope, radius or 22),
		scope:New("UIGradient")({
			Color = ColorSequence.new(deep, deep:Lerp(Theme.PANEL_DEEP, 0.62)),
			Rotation = 90,
		}),
		scope:New("UIStroke")({
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = light,
			Thickness = 3,
		}),
	}
end

-- A highlight card like the reference's: a dark gradient of `Color` (mint unless told otherwise) with a bright edge
-- and a bright bar down its left side. Children go in `Children`.
-- props: Name, Size, Position, AnchorPoint, LayoutOrder, Visible, Color, Deep, Edge, Children.
function Widgets.card(scope, props)
	local edge = props.Edge or Theme.MINT
	return scope:New("Frame")({
		Name = props.Name,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		BackgroundColor3 = Theme.WHITE,
		[Children] = {
			Widgets.corner(scope, 16),
			Widgets.gradient(scope, props.Color or Theme.MINT_CARD, props.Deep or Theme.MINT_DEEP),
			scope:New("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = edge,
				Thickness = 3,
			}),
			scope:New("Frame")({
				Name = "Bar",
				Position = UDim2.fromOffset(0, 10),
				Size = UDim2.new(0, 6, 1, -20),
				BackgroundColor3 = edge,
				[Children] = { Widgets.round(scope) },
			}),
			props.Children,
		},
	})
end

-- A tilted sticker like the reference's "NEW!" and "UNLOCKED!": a bright pill with chunky white lettering.
-- props: Name, Text, Position, AnchorPoint, Size, Color, Deep, Rotation, TextSize, ZIndex, Visible.
function Widgets.tag(scope, props)
	return scope:New("Frame")({
		Name = props.Name or "Tag",
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = props.Position,
		Size = props.Size or UDim2.fromOffset(74, 30),
		Rotation = props.Rotation or 6,
		ZIndex = props.ZIndex,
		Visible = props.Visible,
		BackgroundColor3 = Theme.WHITE,
		[Children] = {
			Widgets.corner(scope, 9),
			Widgets.gradient(scope, props.Color or Theme.CORAL, props.Deep or Theme.CORAL_DEEP),
			scope:New("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.WHITE,
				Thickness = 2.5,
			}),
			Widgets.text(scope, {
				Name = "Label",
				Font = Theme.TITLE_FONT,
				Text = props.Text,
				TextSize = props.TextSize or 18,
				ZIndex = props.ZIndex,
				Stroke = 2,
			}),
		},
	})
end

return Widgets
