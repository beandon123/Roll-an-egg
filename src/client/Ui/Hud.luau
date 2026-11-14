-- The on-screen HUD, built with Fusion. It only reads UiState; controllers change UiState and the HUD follows.
--
-- Layout (phones first): runway timer and zone top centre; luck boost top left; Shop and Settings tabs on the
-- left edge with the wallet under them; Eggs, Pets and Ride tabs on the right edge (Ui/Panels); stamina and claim
-- meters bottom centre. The Shop and Settings panels open in the middle over a dimmed backdrop.

local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local CycleClock = Load.shared("CycleClock")
local NumberFormat = Load.shared("NumberFormat")

local Panels = require(script.Parent.Panels)
local SettingsPanel = require(script.Parent.SettingsPanel)
local ShopPanel = require(script.Parent.ShopPanel)
local StationPanels = require(script.Parent.StationPanels)
local Theme = require(script.Parent.Theme)
local UiState = require(script.Parent.UiState)
local Widgets = require(script.Parent.Widgets)

local Fusion = UiState.Fusion
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(26, 28, 36)
local STAMINA_COLOR = Color3.fromRGB(90, 200, 255)
local CLAIM_COLOR = Color3.fromRGB(120, 230, 120)
local DANGER_COLOR = Color3.fromRGB(255, 95, 95)
local WARNING_COLOR = Color3.fromRGB(255, 160, 50)
local EVENT_COLOR = Color3.fromRGB(130, 80, 200)

-- The design is laid out for a 720-pixel-tall screen and scaled to fit others.
local REFERENCE_HEIGHT = 720

local Hud = {}

local function corner(scope, radius: number)
	return scope:New("UICorner")({ CornerRadius = UDim.new(0, radius) })
end

local function outline(scope)
	return scope:New("UIStroke")({ Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.5 })
end

-- A rounded dark panel with one line of text.
local function pill(scope, props)
	return scope:New("Frame")({
		Name = props.Name,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		LayoutOrder = props.LayoutOrder,
		BackgroundColor3 = props.Color or PANEL,
		BackgroundTransparency = 0.1,
		[Children] = {
			corner(scope, 12),
			outline(scope),
			scope:New("TextLabel")({
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.GothamBold,
				Text = props.Text,
				TextColor3 = WHITE,
				TextSize = props.TextSize or 18,
			}),
		},
	})
end

-- A progress bar with text over it. `Fill` is a state object from 0 to 1.
local function bar(scope, props)
	return scope:New("Frame")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = props.Size,
		Visible = props.Visible,
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.1,
		[Children] = {
			corner(scope, 10),
			outline(scope),
			scope:New("Frame")({
				Name = "Fill",
				BackgroundColor3 = props.FillColor,
				Size = scope:Computed(function(use)
					return UDim2.fromScale(math.clamp(use(props.Fill), 0, 1), 1)
				end),
				[Children] = { corner(scope, 10) },
			}),
			scope:New("TextLabel")({
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 2,
				Font = Enum.Font.GothamBold,
				Text = props.Text,
				TextColor3 = WHITE,
				TextSize = 16,
				TextStrokeTransparency = 0.4,
			}),
		},
	})
end

-- A big tab on the left edge of the screen. Its left end hides off-screen, so it looks like it slides out.
local function tab(scope, props)
	return Widgets.button(scope, {
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromOffset(186, 64),
		Color = props.Light,
		Deep = props.Deep,
		Radius = UDim.new(0, 22),
		OnActivated = function()
			UiState.togglePanel(props.Name)
		end,
		Content = {
			Widgets.speckles(scope, { { 0.55, 0.25, 10 }, { 0.68, 0.72, 7 }, { 0.9, 0.35, 12 } }),
			scope:New("Frame")({
				Name = "Bubble",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 56, 0.5, 0),
				Size = UDim2.fromOffset(46, 46),
				BackgroundColor3 = Theme.WHITE,
				[Children] = {
					Widgets.round(scope),
					Widgets.stroke(scope, 3),
					Widgets.text(scope, { Name = "Icon", Text = props.Icon, TextSize = 26 }),
				},
			}),
			Widgets.text(scope, {
				Name = "Label",
				Position = UDim2.fromOffset(86, 0),
				Size = UDim2.new(1, -92, 1, 0),
				Text = props.Text,
				TextColor3 = Theme.WHITE,
				TextScaled = true,
				MaxTextSize = 28,
				TextXAlignment = Enum.TextXAlignment.Left,
				Stroke = 3,
			}),
		},
	})
end

-- One line of the wallet: an icon, a number, and (optionally) a "+" that opens the shop at `ShopSection`.
local function walletRow(scope, props)
	return scope:New("Frame")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromOffset(250, 46),
		BackgroundColor3 = Theme.CREAM,
		[Children] = {
			Widgets.round(scope),
			Widgets.stroke(scope, 3),
			props.Icon,
			Widgets.text(scope, {
				Name = "Value",
				Position = UDim2.fromOffset(48, 0),
				Size = UDim2.new(1, -96, 1, 0),
				Text = props.Value,
				TextScaled = true,
				MaxTextSize = 26,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			if props.ShopSection
				then Widgets.button(scope, {
					Name = "Add",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 8, 0.5, 0),
					Size = UDim2.fromOffset(44, 44),
					Color = Theme.GREEN,
					Deep = Theme.GREEN_DEEP,
					Radius = UDim.new(0.5, 0),
					Text = "+",
					TextColor3 = Theme.WHITE,
					TextSize = 32,
					Stroke = 2.5,
					OnActivated = function()
						UiState.openShop(props.ShopSection)
					end,
				})
				else nil,
		},
	})
end

-- An emoji in a white circle, for the left end of a wallet row.
local function emojiIcon(scope, emoji: string)
	return scope:New("Frame")({
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = Theme.WHITE,
		[Children] = {
			Widgets.round(scope),
			Widgets.stroke(scope, 3),
			Widgets.text(scope, { Text = emoji, TextSize = 26 }),
		},
	})
end

function Hud.mount(playerGui: Instance)
	local scope = UiState.scope

	local uiScale = scope:Value(1)
	local function updateScale()
		local camera = Workspace.CurrentCamera
		if camera then
			uiScale:set(math.clamp(camera.ViewportSize.Y / REFERENCE_HEIGHT, 0.6, 1.4))
		end
	end
	updateScale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	local cycleText = scope:Computed(function(use)
		local phase = use(UiState.cyclePhase)
		local clock = NumberFormat.clock(use(UiState.cycleSeconds))
		if phase == "Closed" then
			return `Runway closed - eggs hatch 30x!  {clock}`
		elseif phase == "Warning" then
			return `Runway closing in {clock}!`
		end
		local event = use(UiState.serverEvent)
		if event then
			return `{CycleClock.EVENT_NAMES[event] or event}!  Runway closes in {clock}`
		end
		return `Runway closes in {clock}`
	end)

	local cycleColor = scope:Computed(function(use)
		local phase = use(UiState.cyclePhase)
		if phase == "Closed" then
			return DANGER_COLOR
		elseif phase == "Warning" then
			return WARNING_COLOR
		elseif use(UiState.serverEvent) then
			return EVENT_COLOR
		end
		return PANEL
	end)

	local staminaFill = scope:Computed(function(use)
		local max = use(UiState.maxStamina)
		return if max > 0 then use(UiState.stamina) / max else 0
	end)

	local staminaText = scope:Computed(function(use)
		return `Stamina  {NumberFormat.abbreviate(use(UiState.stamina))} / {NumberFormat.abbreviate(
			use(UiState.maxStamina)
		)}`
	end)

	local claimText = scope:Computed(function(use)
		local percent = math.floor(use(UiState.claimProgress) * 100)
		if use(UiState.rideDoomed) then
			return `{use(UiState.rideTitle)}  {percent}%  - not enough stamina!`
		end
		return `Claiming {use(UiState.rideTitle)}  {percent}%`
	end)

	local claimColor = scope:Computed(function(use)
		return if use(UiState.rideDoomed) then DANGER_COLOR else CLAIM_COLOR
	end)

	return scope:New("ScreenGui")({
		Name = "Hud",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
		[Children] = {
			scope:New("Frame")({
				Name = "Root",
				BackgroundTransparency = 1,
				-- UIScale shrinks or grows everything; dividing the size keeps the frame filling the screen.
				Size = scope:Computed(function(use)
					return UDim2.fromScale(1 / use(uiScale), 1 / use(uiScale))
				end),
				[Children] = {
					scope:New("UIScale")({ Scale = uiScale }),

					-- Top centre: the runway cycle and the zone the player is in.
					pill(scope, {
						Name = "Cycle",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 8),
						Size = UDim2.fromOffset(340, 38),
						Color = cycleColor,
						Text = cycleText,
						TextSize = 17,
					}),
					scope:New("TextLabel")({
						Name = "Zone",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 50),
						Size = UDim2.fromOffset(300, 24),
						BackgroundTransparency = 1,
						Font = Enum.Font.FredokaOne,
						Text = UiState.zoneName,
						TextColor3 = WHITE,
						TextSize = 22,
						TextStrokeTransparency = 0.3,
					}),

					-- Top left: the server luck boost, while one is running.
					scope:New("Frame")({
						Name = "Luck",
						Position = UDim2.fromOffset(12, 10),
						Size = UDim2.fromOffset(236, 42),
						Visible = scope:Computed(function(use)
							return use(UiState.luck) > 1 and use(UiState.luckSeconds) > 0
						end),
						BackgroundColor3 = Theme.WHITE,
						[Children] = {
							Widgets.round(scope),
							Widgets.gradient(scope, Theme.Sections.Luck.light, Theme.Sections.Luck.deep),
							Widgets.stroke(scope, 3),
							Widgets.text(scope, {
								Name = "Label",
								Text = scope:Computed(function(use)
									local clock = NumberFormat.clock(use(UiState.luckSeconds))
									return `🍀 x{use(UiState.luck)} LUCK  {clock}`
								end),
								TextColor3 = Theme.WHITE,
								TextSize = 22,
								Stroke = 2.5,
							}),
						},
					}),

					-- Left edge: the tabs that open the panels.
					scope:New("Frame")({
						Name = "Tabs",
						AnchorPoint = Vector2.new(0, 0.5),
						-- Pushed off the left edge so each tab's rounded end is hidden.
						Position = UDim2.new(0, -26, 0.4, 0),
						Size = UDim2.fromOffset(186, 140),
						BackgroundTransparency = 1,
						[Children] = {
							Widgets.list(scope, { Padding = 10 }),
							tab(scope, {
								Name = "Shop",
								LayoutOrder = 1,
								Text = "Shop",
								Icon = "🛒",
								Light = Theme.Sections.Featured.light,
								Deep = Theme.Sections.Featured.deep,
							}),
							tab(scope, {
								Name = "Settings",
								LayoutOrder = 2,
								Text = "Settings",
								Icon = "⚙️",
								Light = Theme.SKY,
								Deep = Theme.SKY_DEEP,
							}),
						},
					}),

					-- Under the tabs: Max Stamina, dollars (and what the pen earns a second), and eggs held. "+" opens
					-- the shop at that section.
					scope:New("Frame")({
						Name = "Wallet",
						Position = UDim2.new(0, 18, 0.4, 92),
						Size = UDim2.fromOffset(250, 160),
						BackgroundTransparency = 1,
						[Children] = {
							Widgets.list(scope, { Padding = 9 }),
							walletRow(scope, {
								Name = "Stamina",
								LayoutOrder = 1,
								Icon = emojiIcon(scope, "⚡"),
								Value = scope:Computed(function(use)
									return NumberFormat.abbreviate(use(UiState.maxStamina))
								end),
								ShopSection = "Stamina",
							}),
							walletRow(scope, {
								Name = "Dollars",
								LayoutOrder = 2,
								Icon = Widgets.dollar(scope, {
									Name = "Icon",
									AnchorPoint = Vector2.new(0, 0.5),
									Position = UDim2.new(0, -6, 0.5, 0),
									Size = 46,
								}),
								Value = scope:Computed(function(use)
									local text = NumberFormat.abbreviate(math.floor(use(UiState.dollars)))
									local income = use(UiState.income)
									if income > 0 then
										text ..= `  +{NumberFormat.abbreviate(income)}/s`
									end
									return text
								end),
								ShopSection = "Dollars",
							}),
							walletRow(scope, {
								Name = "Eggs",
								LayoutOrder = 3,
								Icon = emojiIcon(scope, "🥚"),
								Value = scope:Computed(function(use)
									return tostring(use(UiState.eggCount))
								end),
							}),
						},
					}),

					-- Messages such as "CLAIMED!".
					scope:New("TextLabel")({
						Name = "Toast",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 96),
						Size = UDim2.new(0.9, 0, 0, 40),
						BackgroundTransparency = 1,
						Font = Enum.Font.FredokaOne,
						Text = UiState.toastText,
						TextColor3 = UiState.toastColor,
						TextSize = 32,
						TextStrokeTransparency = 0,
						Visible = UiState.toastVisible,
						-- Above the panels, so purchase messages show while the shop is open.
						ZIndex = 30,
					}),

					-- Bottom centre: claim meter (while riding) above the stamina bar.
					scope:New("Frame")({
						Name = "Meters",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -14),
						Size = UDim2.fromOffset(380, 96),
						BackgroundTransparency = 1,
						[Children] = {
							scope:New("UIListLayout")({
								Padding = UDim.new(0, 6),
								SortOrder = Enum.SortOrder.LayoutOrder,
								VerticalAlignment = Enum.VerticalAlignment.Bottom,
							}),
							scope:New("TextLabel")({
								Name = "RideHint",
								LayoutOrder = 1,
								Size = UDim2.new(1, 0, 0, 18),
								BackgroundTransparency = 1,
								Font = Enum.Font.GothamBold,
								Text = "Steer left / right  -  Jump to hop off",
								TextColor3 = WHITE,
								TextSize = 14,
								TextStrokeTransparency = 0.3,
								Visible = UiState.riding,
							}),
							bar(scope, {
								Name = "Claim",
								LayoutOrder = 2,
								Size = UDim2.new(1, 0, 0, 30),
								Visible = UiState.riding,
								Fill = UiState.claimProgress,
								FillColor = claimColor,
								Text = claimText,
							}),
							bar(scope, {
								Name = "Stamina",
								LayoutOrder = 3,
								Size = UDim2.new(1, 0, 0, 26),
								Fill = staminaFill,
								FillColor = STAMINA_COLOR,
								Text = staminaText,
							}),
						},
					}),

					-- Panels, over a backdrop that closes them when tapped.
					scope:New("TextButton")({
						Name = "Backdrop",
						Size = UDim2.fromScale(1, 1),
						ZIndex = 15,
						AutoButtonColor = false,
						Text = "",
						BackgroundColor3 = Theme.BACKDROP,
						BackgroundTransparency = 0.45,
						Visible = scope:Computed(function(use)
							return use(UiState.openPanel) ~= nil
						end),
						[OnEvent("Activated")] = function()
							UiState.openPanel:set(nil)
						end,
					}),
					ShopPanel.build(scope),
					SettingsPanel.build(scope),
					-- The Trails stall, Sell stall and fuse machine panels (hidden until a station is used).
					StationPanels.build(scope),

					-- Right edge: the Eggs, Pets and Ride tabs, and the panel they open.
					Panels.build(scope),
				},
			}),
		},
	})
end

return Hud
