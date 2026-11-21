-- The revive offer: when a player who has revives misses their leap, the screen dims and a card asks whether to use
-- one, with a bar running down the time left to answer. REVIVE carries on from the air above the nearest egg; No
-- thanks (or letting the time run out) goes back to the hub as usual. RideController holds the player where they fell
-- meanwhile and does what the buttons ask (UiState.actions); HudController runs the timer.

local Theme = require(script.Parent.Theme)
local UiState = require(script.Parent.UiState)
local Widgets = require(script.Parent.Widgets)

local Fusion = UiState.Fusion
local Children = Fusion.Children

local ReviveUi = {}

local HEART = Color3.fromRGB(255, 120, 160)
local HEART_DEEP = Color3.fromRGB(220, 46, 100)

function ReviveUi.build(scope)
	local pop = scope:Spring(
		scope:Computed(function(use)
			return if use(UiState.reviveOffered) then 1 else 0.7
		end),
		30,
		0.6
	)

	return scope:New("Frame")({
		Name = "Revive",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Visible = UiState.reviveOffered,
		BackgroundColor3 = Theme.BACKDROP,
		BackgroundTransparency = 0.5,
		[Children] = {
			scope:New("Frame")({
				Name = "Card",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.48),
				Size = UDim2.fromOffset(440, 330),
				ZIndex = 31,
				BackgroundColor3 = Theme.WHITE,
				[Children] = {
					scope:New("UIScale")({ Scale = pop }),
					Widgets.panelSkin(scope),
					Widgets.titleBand(scope, {
						Text = "  YOU FELL!",
						ZIndex = 32,
					}),
					-- A big heart, the revives left on it.
					scope:New("Frame")({
						Name = "Heart",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 82),
						Size = UDim2.fromOffset(96, 96),
						ZIndex = 32,
						BackgroundColor3 = Theme.WHITE,
						[Children] = {
							Widgets.round(scope),
							Widgets.gradient(scope, HEART, HEART_DEEP),
							Widgets.border(scope, 4, Theme.WHITE),
							Widgets.text(scope, {
								Name = "Icon",
								Position = UDim2.fromOffset(0, 6),
								Size = UDim2.new(1, 0, 0, 50),
								Text = "💖",
								TextSize = 44,
								ZIndex = 33,
							}),
							Widgets.text(scope, {
								Name = "Count",
								Position = UDim2.fromOffset(0, 56),
								Size = UDim2.new(1, 0, 0, 30),
								Font = Theme.TITLE_FONT,
								Text = scope:Computed(function(use)
									return `x{use(UiState.revives)}`
								end),
								TextSize = 28,
								Stroke = 2.5,
								ZIndex = 33,
							}),
						},
					}),
					Widgets.text(scope, {
						Name = "Question",
						Position = UDim2.fromOffset(20, 184),
						Size = UDim2.new(1, -40, 0, 26),
						Text = scope:Computed(function(use)
							return `Use a revive and carry on?  {use(UiState.reviveSeconds)}`
						end),
						TextSize = 22,
						Stroke = 2,
						ZIndex = 32,
					}),
					-- The time left to answer, running down.
					scope:New("Frame")({
						Name = "Timer",
						Position = UDim2.fromOffset(30, 216),
						Size = UDim2.new(1, -60, 0, 12),
						ZIndex = 32,
						BackgroundColor3 = Theme.WELL,
						[Children] = {
							Widgets.round(scope),
							scope:New("Frame")({
								Name = "Fill",
								Size = scope:Computed(function(use)
									return UDim2.fromScale(math.clamp(use(UiState.reviveLeft), 0, 1), 1)
								end),
								ZIndex = 33,
								BackgroundColor3 = HEART,
								[Children] = { Widgets.round(scope) },
							}),
						},
					}),
					Widgets.button(scope, {
						Name = "Use",
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.new(0, 24, 1, -20),
						Size = UDim2.new(0.58, -24, 0, 60),
						ZIndex = 32,
						Color = Theme.GREEN,
						Deep = Theme.GREEN_DEEP,
						Text = "REVIVE",
						TextSize = 32,
						OnActivated = function()
							UiState.actions.useRevive()
						end,
					}),
					Widgets.button(scope, {
						Name = "Decline",
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.new(1, -24, 1, -20),
						Size = UDim2.new(0.42, -24, 0, 60),
						ZIndex = 32,
						Color = Theme.CARD,
						Deep = Theme.CARD_DEEP,
						Text = "No thanks",
						TextSize = 22,
						OnActivated = function()
							UiState.actions.declineRevive()
						end,
					}),
				},
			}),
		},
	})
end

return ReviveUi
