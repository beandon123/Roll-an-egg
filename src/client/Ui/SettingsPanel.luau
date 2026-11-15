-- The settings panel: volume sliders and on/off switches (Config/Settings). It only changes UiState.settings;
-- the SettingsController applies and saves them.

local UserInputService = game:GetService("UserInputService")

local Load = require(script.Parent.Parent.Load)
local Settings = Load.shared("Config", "Settings")

local Theme = require(script.Parent.Theme)
local UiState = require(script.Parent.UiState)
local Widgets = require(script.Parent.Widgets)

local Fusion = UiState.Fusion
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local peek = Fusion.peek

local SECTION_COLORS = {
	Audio = { icon = "🔊", light = Color3.fromRGB(104, 200, 255), deep = Color3.fromRGB(52, 120, 240) },
	Pets = { icon = "🐣", light = Color3.fromRGB(120, 232, 140), deep = Color3.fromRGB(32, 170, 98) },
	Comfort = { icon = "💛", light = Color3.fromRGB(200, 140, 255), deep = Color3.fromRGB(118, 72, 240) },
}

local SettingsPanel = {}

local function isPress(input): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- The knob on sliders and switches: a little speckled egg.
local function eggKnob(scope, props)
	return scope:New("Frame")({
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.Position,
		Size = props.Size,
		ZIndex = 3,
		BackgroundColor3 = Theme.WHITE,
		[Children] = {
			Widgets.corner(scope, UDim.new(0.5, 0)),
			Widgets.stroke(scope, 3),
			Widgets.gradient(scope, Theme.WHITE, Theme.SHELL),
			Widgets.speckles(scope, { { 0.32, 0.36, 5 }, { 0.66, 0.58, 4 }, { 0.42, 0.74, 3 } }, Theme.SHELL_DARK, 0),
		},
	})
end

-- A 0-100% slider. Press or drag anywhere on the track.
local function slider(scope, setting)
	local value = UiState.settings[setting.key]
	local dragging = false
	local track: TextButton

	local function setFromX(x: number)
		local position, size = track.AbsolutePosition, track.AbsoluteSize
		if position == nil or size == nil or size.X <= 0 then
			return
		end
		value:set(Settings.sanitize(setting.key, (x - position.X) / size.X))
	end

	local fillScale = scope:Computed(function(use)
		return math.clamp(use(value), 0, 1)
	end)

	track = scope:New("TextButton")({
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, -74, 0, 44),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		[OnEvent("InputBegan")] = function(input)
			if isPress(input) then
				dragging = true
				setFromX(input.Position.X)
			end
		end,
		[Children] = {
			scope:New("Frame")({
				Name = "Bar",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundColor3 = Theme.TRACK,
				[Children] = {
					Widgets.round(scope),
					Widgets.stroke(scope, 2.5),
					scope:New("Frame")({
						Name = "Fill",
						Size = scope:Computed(function(use)
							return UDim2.fromScale(use(fillScale), 1)
						end),
						BackgroundColor3 = Theme.WHITE,
						[Children] = {
							Widgets.round(scope),
							Widgets.gradient(scope, Theme.YOLK, Theme.YOLK_DEEP),
						},
					}),
				},
			}),
			eggKnob(scope, {
				Position = scope:Computed(function(use)
					return UDim2.fromScale(use(fillScale), 0.5)
				end),
				Size = UDim2.fromOffset(28, 34),
			}),
		},
	})

	table.insert(
		scope,
		UserInputService.InputChanged:Connect(function(input)
			if
				dragging
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				setFromX(input.Position.X)
			end
		end)
	)
	table.insert(
		scope,
		UserInputService.InputEnded:Connect(function(input)
			if isPress(input) then
				dragging = false
			end
		end)
	)

	return scope:New("Frame")({
		Name = "Slider",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromScale(0.5, 1),
		BackgroundTransparency = 1,
		[Children] = {
			track,
			Widgets.text(scope, {
				Name = "Percent",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.fromOffset(62, 30),
				Text = scope:Computed(function(use)
					return `{math.floor(use(value) * 100 + 0.5)}%`
				end),
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		},
	})
end

-- An on/off switch: green with the egg on the right when on.
local function switch(scope, setting)
	local value = UiState.settings[setting.key]
	local slide = scope:Spring(
		scope:Computed(function(use)
			return if use(value) then 1 else 0
		end),
		35,
		0.75
	)

	return scope:New("TextButton")({
		Name = "Toggle",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(118, 46),
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = scope:Computed(function(use)
			return if use(value) then Theme.GREEN else Theme.TRACK
		end),
		[OnEvent("Activated")] = function()
			value:set(not peek(value))
		end,
		[Children] = {
			Widgets.round(scope),
			Widgets.border(scope, 3),
			Widgets.text(scope, {
				Name = "State",
				Position = scope:Computed(function(use)
					return if use(value) then UDim2.fromOffset(12, 0) else UDim2.fromOffset(50, 0)
				end),
				Size = UDim2.new(0, 56, 1, 0),
				Text = scope:Computed(function(use)
					return if use(value) then "ON" else "OFF"
				end),
				TextColor3 = Theme.WHITE,
				TextSize = 22,
				Stroke = 2.5,
			}),
			eggKnob(scope, {
				Position = scope:Computed(function(use)
					return UDim2.new(0, 24 + 70 * use(slide), 0.5, 0)
				end),
				Size = UDim2.fromOffset(36, 38),
			}),
		},
	})
end

local function row(scope, setting, order: number)
	return scope:New("Frame")({
		Name = setting.key,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 70),
		BackgroundColor3 = Theme.SHELL,
		[Children] = {
			Widgets.corner(scope, 20),
			Widgets.stroke(scope, 3),
			scope:New("Frame")({
				Name = "IconBubble",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 12, 0.5, 0),
				Size = UDim2.fromOffset(48, 48),
				BackgroundColor3 = Theme.WHITE,
				[Children] = {
					Widgets.round(scope),
					Widgets.stroke(scope, 2.5),
					Widgets.text(scope, { Name = "Icon", Text = setting.icon, TextSize = 26 }),
				},
			}),
			Widgets.text(scope, {
				Name = "Label",
				Position = UDim2.fromOffset(72, 0),
				Size = UDim2.new(0.5, -72, 1, 0),
				Text = setting.label,
				TextScaled = true,
				MaxTextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			if setting.kind == "Slider" then slider(scope, setting) else switch(scope, setting),
		},
	})
end

function SettingsPanel.build(scope)
	local open = scope:Computed(function(use)
		return use(UiState.openPanel) == "Settings"
	end)

	local items = {}
	local order = 0
	for _, sectionName in Settings.Sections do
		local colors = SECTION_COLORS[sectionName]
		order += 1
		table.insert(
			items,
			Widgets.sectionHeader(scope, {
				Name = sectionName,
				LayoutOrder = order,
				Title = sectionName,
				Icon = colors.icon,
				Light = colors.light,
				Deep = colors.deep,
				Width = 220,
			})
		)
		for _, setting in Settings.inSection(sectionName) do
			order += 1
			table.insert(items, row(scope, setting, order))
		end
	end
	table.insert(
		items,
		Widgets.text(scope, {
			Name = "Footer",
			LayoutOrder = order + 1,
			Size = UDim2.new(1, 0, 0, 24),
			Font = Theme.SMALL_FONT,
			Text = "Settings save to your account automatically",
			TextColor3 = Color3.fromRGB(150, 110, 80),
			TextSize = 14,
		})
	)

	return Widgets.panel(scope, {
		Name = "SettingsPanel",
		Title = "SETTINGS",
		Icon = "⚙️",
		Size = UDim2.new(0, 600, 0.88, 0),
		MaxSize = Vector2.new(math.huge, 640),
		Visible = open,
		OnClose = function()
			UiState.openPanel:set(nil)
		end,
		Body = {
			Widgets.scroller(scope, { Name = "Scroll", Padding = 10, Children = items }),
		},
	})
end

return SettingsPanel
