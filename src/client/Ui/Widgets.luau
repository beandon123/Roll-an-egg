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

-- A text label in the house style. `Stroke` (a thickness) gives it a dark outline.
function Widgets.text(scope, props)
	return scope:New("TextLabel")({
		Name = props.Name,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or UDim2.fromScale(1, 1),
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		Rotation = props.Rotation,
		BackgroundTransparency = 1,
		Font = props.Font or Theme.FONT,
		Text = props.Text,
		TextColor3 = props.TextColor3 or Theme.INK,
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

-- A chunky button: a colored face sitting on a darker "lip", with a little squash when pressed.
-- props: Name, Size, Position, AnchorPoint, LayoutOrder, Visible, Color, Deep, Text, TextColor3, TextSize,
-- Stroke (text outline thickness), Content (children to show instead of Text), Radius, OnActivated.
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
				BackgroundColor3 = props.Deep or Theme.YOLK_DEEP,
				[Children] = {
					Widgets.corner(scope, radius),
					Widgets.stroke(scope, 3),
				},
			}),
			scope:New("Frame")({
				Name = "Face",
				Size = UDim2.new(1, 0, 1, -5),
				BackgroundColor3 = props.Color or Theme.YOLK,
				[Children] = {
					Widgets.corner(scope, radius),
					-- A glossy top half.
					scope:New("UIGradient")({
						Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(230, 230, 230)),
						Rotation = 90,
					}),
					props.Content or Widgets.text(scope, {
						Name = "Label",
						Text = props.Text,
						TextColor3 = props.TextColor3 or Theme.INK,
						TextSize = props.TextSize or 22,
						Stroke = props.Stroke,
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

-- A panel: cream body, yolk title band, close button. `body` children go under the title.
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
		BackgroundColor3 = Theme.CREAM,
		ZIndex = 20,
		[Children] = {
			scope:New("UIScale")({ Scale = scale }),
			scope:New("UISizeConstraint")({ MaxSize = props.MaxSize or Vector2.new(math.huge, 600) }),
			Widgets.corner(scope, 28),
			Widgets.stroke(scope, 4),
			Widgets.speckles(scope, {
				{ 0.06, 0.92, 26 },
				{ 0.94, 0.86, 18 },
				{ 0.9, 0.97, 10 },
				{ 0.12, 0.8, 12 },
			}, Theme.SHELL_DARK, 0.55),

			-- Title band.
			scope:New("Frame")({
				Name = "TitleBar",
				Size = UDim2.new(1, 0, 0, 70),
				BackgroundColor3 = Theme.WHITE,
				[Children] = {
					Widgets.corner(scope, 28),
					Widgets.gradient(scope, Theme.YOLK, Theme.YOLK_DEEP),
					Widgets.stroke(scope, 4),
					Widgets.speckles(scope, {
						{ 0.62, 0.3, 14 },
						{ 0.7, 0.72, 9 },
						{ 0.8, 0.35, 20 },
						{ 0.86, 0.75, 8 },
					}),
					Widgets.text(scope, {
						Name = "Title",
						Position = UDim2.fromOffset(22, 6),
						Size = UDim2.new(1, -100, 1, -10),
						Font = Theme.TITLE_FONT,
						Text = `{props.Icon}  {props.Title}`,
						TextColor3 = Theme.WHITE,
						TextSize = 38,
						TextXAlignment = Enum.TextXAlignment.Left,
						Stroke = 3.5,
					}),
					Widgets.closeButton(scope, props.OnClose),
				},
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
		ScrollBarImageColor3 = Theme.INK,
		ScrollBarImageTransparency = 0.4,
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

-- A ribbon heading for a section: colored pill with an icon and the section name, and a line of small print.
function Widgets.sectionHeader(scope, props)
	return scope:New("Frame")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, if props.Blurb then 70 else 46),
		BackgroundTransparency = 1,
		[Children] = {
			scope:New("Frame")({
				Name = "Ribbon",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(props.Width or 260, 44),
				BackgroundColor3 = Theme.WHITE,
				[Children] = {
					Widgets.round(scope),
					Widgets.gradient(scope, props.Light, props.Deep),
					Widgets.stroke(scope, 3),
					Widgets.text(scope, {
						Name = "Label",
						Text = `{props.Icon}  {string.upper(props.Title)}`,
						TextColor3 = Theme.WHITE,
						TextSize = 28,
						Stroke = 3,
					}),
				},
			}),
			if props.Blurb
				then Widgets.text(scope, {
					Name = "Blurb",
					Position = UDim2.fromOffset(0, 48),
					Size = UDim2.new(1, 0, 0, 20),
					Font = Theme.SMALL_FONT,
					Text = props.Blurb,
					TextColor3 = Color3.fromRGB(130, 96, 70),
					TextSize = 15,
				})
				else nil,
		},
	})
end

return Widgets
