-- The on-screen HUD, built with Fusion. It only reads UiState; controllers change UiState and the HUD follows.
--
-- Placeholder look: clear and readable, sized for phones first. Final UI art comes later.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local Net = Load.shared("Net")
local NumberFormat = Load.shared("NumberFormat")

local UiState = require(script.Parent.UiState)

local Fusion = UiState.Fusion
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(26, 28, 36)
local STAMINA_COLOR = Color3.fromRGB(90, 200, 255)
local CLAIM_COLOR = Color3.fromRGB(120, 230, 120)
local DANGER_COLOR = Color3.fromRGB(255, 95, 95)
local WARNING_COLOR = Color3.fromRGB(255, 160, 50)

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

local function devButton(scope, text: string, command: string, order: number)
	return scope:New("TextButton")({
		Name = command,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Color3.fromRGB(60, 64, 84),
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = WHITE,
		TextSize = 14,
		[OnEvent("Activated")] = function()
			Net.DevCommand:FireServer(command)
		end,
		[Children] = { corner(scope, 8) },
	})
end

-- Buttons that only appear (and only work) inside Roblox Studio, for testing.
local function devPanel(scope)
	return scope:New("Frame")({
		Name = "StudioTestPanel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.4, 0),
		Size = UDim2.fromOffset(170, 228),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.2,
		[Children] = {
			corner(scope, 10),
			scope:New("UIPadding")({
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
			}),
			scope:New("UIListLayout")({
				Padding = UDim.new(0, 5),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			scope:New("TextLabel")({
				LayoutOrder = 0,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 16),
				Font = Enum.Font.GothamBold,
				Text = "Studio test tools",
				TextColor3 = WHITE,
				TextSize = 12,
			}),
			devButton(scope, "Max stamina x5", "StaminaUp", 1),
			devButton(scope, "Reset stamina", "StaminaReset", 2),
			devButton(scope, "Drop best egg here", "DropBestEgg", 3),
			devButton(scope, "Drop each egg here", "DropEachEgg", 4),
			devButton(scope, "Show this zone's pets", "ShowPets", 5),
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
			return `Runway closed - nests hatch 30x!  {clock}`
		elseif phase == "Warning" then
			return `Runway closing in {clock}!`
		end
		return `Runway closes in {clock}`
	end)

	local cycleColor = scope:Computed(function(use)
		local phase = use(UiState.cyclePhase)
		if phase == "Closed" then
			return DANGER_COLOR
		elseif phase == "Warning" then
			return WARNING_COLOR
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

					-- Top left: coins and eggs held.
					scope:New("Frame")({
						Name = "Wallet",
						Position = UDim2.fromOffset(10, 8),
						Size = UDim2.fromOffset(150, 80),
						BackgroundTransparency = 1,
						[Children] = {
							scope:New("UIListLayout")({
								Padding = UDim.new(0, 6),
								SortOrder = Enum.SortOrder.LayoutOrder,
							}),
							pill(scope, {
								Name = "Coins",
								LayoutOrder = 1,
								Size = UDim2.new(1, 0, 0, 34),
								Text = scope:Computed(function(use)
									return `Coins  {NumberFormat.abbreviate(use(UiState.coins))}`
								end),
								TextSize = 16,
							}),
							pill(scope, {
								Name = "Eggs",
								LayoutOrder = 2,
								Size = UDim2.new(1, 0, 0, 34),
								Text = scope:Computed(function(use)
									return `Eggs  {use(UiState.eggCount)}`
								end),
								TextSize = 16,
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

					if RunService:IsStudio() then devPanel(scope) else nil,
				},
			}),
		},
	})
end

return Hud
