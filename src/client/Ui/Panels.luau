-- The Eggs and Pets tabs on the right of the screen, built with Fusion, and the Ride button under them:
--     Eggs  the eggs the player has claimed; Place puts one down where they stand in their pen
--     Pets  the eggs hatching in the pen, each with its countdown, and every pet that has hatched: put it in the
--           pen or take it out, ride it, or sell it; Equip best fills the pen with the best ones
--     Ride  gets on the chosen pet, or off it
-- A 3D preview at the top of each panel shows the selected egg or pet (filled in by InventoryController).
-- Like the rest of the HUD, this only reads UiState; the buttons call UiState.actions.

local Load = require(script.Parent.Parent.Load)
local CycleClock = Load.shared("CycleClock")
local EggModels = Load.shared("EggModels")
local HatchMath = Load.shared("HatchMath")
local NumberFormat = Load.shared("NumberFormat")
local PetModels = Load.shared("PetModels")
local PetWorth = Load.shared("PetWorth")
local Rarities = Load.shared("Config", "Rarities")
local Tuning = Load.shared("Config", "Tuning")

local UiState = require(script.Parent.UiState)

local Fusion = UiState.Fusion
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(26, 28, 36)
local CARD = Color3.fromRGB(44, 47, 60)
local MUTED = Color3.fromRGB(170, 176, 192)
local GO = Color3.fromRGB(70, 190, 100)
local OFF = Color3.fromRGB(84, 90, 110)
local SELL = Color3.fromRGB(205, 70, 70)
local EGGS_COLOR = Color3.fromRGB(70, 140, 255)
local PETS_COLOR = Color3.fromRGB(255, 140, 60)
local RIDE_COLOR = Color3.fromRGB(60, 190, 120)

local VARIANT_COLORS = {
	Silver = Color3.fromRGB(214, 222, 236),
	Gold = Color3.fromRGB(255, 205, 70),
	Rainbow = Color3.fromRGB(255, 120, 200),
}

local PANEL_WIDTH = 420
local PANEL_HEIGHT = 500

local Panels = {}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

function Panels.rarityColor(rarity: string): Color3
	local info = Rarities.Info[rarity]
	-- Secret's colour is nearly black; lighten it so it reads on a dark panel.
	if rarity == "Secret" then
		return Color3.fromRGB(190, 170, 255)
	end
	return if info then rgb(info.color) else WHITE
end

function Panels.eggName(kind: string): string
	local about = EggModels.describe(kind)
	return if about then about.name else "Egg"
end

function Panels.petName(kind: string): string
	local design = PetModels.get(kind)
	return if design then design.name else kind
end

-- "Gold Bear", or just "Bear" for a Normal one.
function Panels.fullPetName(kind: string, variant: string?): string
	local name = Panels.petName(kind)
	if variant and variant ~= "Normal" then
		return `{variant} {name}`
	end
	return name
end

function Panels.money(amount: number): string
	return "$" .. NumberFormat.abbreviate(amount)
end

local function corner(scope, radius: number)
	return scope:New("UICorner")({ CornerRadius = UDim.new(0, radius) })
end

local function label(scope, props)
	return scope:New("TextLabel")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		BackgroundTransparency = 1,
		Font = props.Font or Enum.Font.GothamBold,
		Text = props.Text,
		TextColor3 = props.Color or WHITE,
		TextSize = props.TextSize or 14,
		TextWrapped = true,
		TextXAlignment = props.XAlignment or Enum.TextXAlignment.Center,
		TextStrokeTransparency = props.Stroke or 1,
		ZIndex = props.ZIndex,
	})
end

-- An egg shape in its rarity colour, with a glint.
local function eggIcon(scope, rarity: string, size: number)
	return scope:New("Frame")({
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(size * 0.78, size),
		BackgroundColor3 = Panels.rarityColor(rarity),
		[Children] = {
			scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
			scope:New("UIStroke")({ Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.4 }),
			scope:New("Frame")({
				Position = UDim2.fromScale(0.22, 0.18),
				Size = UDim2.fromScale(0.2, 0.22),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.45,
				[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }) },
			}),
		},
	})
end

-- A round badge with the pet's initial, in its rarity colour.
local function petIcon(scope, name: string, rarity: string, size: number)
	return scope:New("Frame")({
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Panels.rarityColor(rarity),
		[Children] = {
			scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
			scope:New("UIStroke")({ Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.4 }),
			label(scope, {
				Size = UDim2.fromScale(1, 1),
				Text = string.upper(string.sub(name, 1, 1)),
				Font = Enum.Font.FredokaOne,
				TextSize = size * 0.55,
				Stroke = 0.3,
			}),
		},
	})
end

local function isSelected(use, kind: string, rarity: string): boolean
	local selected = use(UiState.selected)
	return selected ~= nil and selected.kind == kind and selected.rarity == rarity
end

local function cardStroke(scope, kind: string, rarity: string)
	return scope:New("UIStroke")({
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Panels.rarityColor(rarity),
		Thickness = scope:Computed(function(use)
			return if isSelected(use, kind, rarity) then 3 else 1
		end),
	})
end

----------------------------------------------------------------------------------------------------------------
-- Eggs

local function eggCard(scope, item)
	local name = Panels.eggName(item.kind)
	local hatch = NumberFormat.duration(HatchMath.hatchTime(item.rarity))
	return scope:New("TextButton")({
		Name = "Egg_" .. item.uid,
		BackgroundColor3 = CARD,
		AutoButtonColor = true,
		Text = "",
		[OnEvent("Activated")] = function()
			UiState.selected:set({ type = "Egg", kind = item.kind, rarity = item.rarity })
		end,
		[Children] = {
			corner(scope, 10),
			cardStroke(scope, item.kind, item.rarity),
			eggIcon(scope, item.rarity, 40),
			label(scope, {
				Name = "Title",
				Position = UDim2.fromOffset(4, 52),
				Size = UDim2.new(1, -8, 0, 30),
				Text = name,
				TextSize = 12,
			}),
			label(scope, {
				Name = "Rarity",
				Position = UDim2.fromOffset(4, 82),
				Size = UDim2.new(1, -8, 0, 14),
				Text = `{item.rarity} - {hatch}`,
				Color = Panels.rarityColor(item.rarity),
				TextSize = 11,
			}),
			scope:New("TextButton")({
				Name = "Place",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -6),
				Size = UDim2.new(1, -12, 0, 26),
				BackgroundColor3 = GO,
				Font = Enum.Font.GothamBold,
				Text = "Place",
				TextColor3 = WHITE,
				TextSize = 14,
				[OnEvent("Activated")] = function()
					UiState.actions.placeEgg(item.uid)
				end,
				[Children] = { corner(scope, 8) },
			}),
		},
	})
end

----------------------------------------------------------------------------------------------------------------
-- Nests and pets

-- A free spot for an egg in the pen.
local function freeRow(scope, order: number)
	return scope:New("Frame")({
		Name = "Free" .. order,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = CARD,
		[Children] = {
			corner(scope, 10),
			label(scope, {
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -140, 1, 0),
				Text = "Room for another egg",
				Color = MUTED,
				XAlignment = Enum.TextXAlignment.Left,
			}),
			scope:New("TextButton")({
				Name = "Fill",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(120, 34),
				BackgroundColor3 = EGGS_COLOR,
				Font = Enum.Font.GothamBold,
				Text = "Put an egg down",
				TextColor3 = WHITE,
				TextSize = 13,
				[OnEvent("Activated")] = function()
					UiState.actions.openPanel("Eggs")
				end,
				[Children] = { corner(scope, 8) },
			}),
		},
	})
end

-- An egg hatching in the pen: a bar filling as it hatches, and the time left.
local function hatchRow(scope, order: number, entry)
	local color = Panels.rarityColor(entry.rarity)
	local progress = scope:Computed(function(use)
		return HatchMath.progress(entry.placedAt, entry.bonus, entry.rarity, use(UiState.clock))
	end)
	local timeText = scope:Computed(function(use)
		local now = use(UiState.clock)
		local left = HatchMath.timeLeft(entry.placedAt, entry.bonus, entry.rarity, now)
		if left <= 0 then
			return "Hatching!"
		end
		local text = `{NumberFormat.duration(left)} left`
		if CycleClock.getState(now).phase == "Closed" then
			text ..= `  ({Tuning.HATCH_BOOST}x speed!)`
		end
		return text
	end)
	return scope:New("TextButton")({
		Name = "Egg_" .. entry.uid,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = CARD,
		AutoButtonColor = true,
		Text = "",
		[OnEvent("Activated")] = function()
			UiState.selected:set({ type = "Egg", kind = entry.kind, rarity = entry.rarity })
		end,
		[Children] = {
			corner(scope, 10),
			cardStroke(scope, entry.kind, entry.rarity),
			scope:New("Frame")({
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.fromOffset(40, 52),
				BackgroundTransparency = 1,
				[Children] = { eggIcon(scope, entry.rarity, 36) },
			}),
			label(scope, {
				Name = "Title",
				Position = UDim2.fromOffset(54, 4),
				Size = UDim2.new(1, -62, 0, 18),
				Text = Panels.eggName(entry.kind),
				XAlignment = Enum.TextXAlignment.Left,
				TextSize = 13,
			}),
			scope:New("Frame")({
				Name = "Bar",
				Position = UDim2.fromOffset(54, 25),
				Size = UDim2.new(1, -64, 0, 20),
				BackgroundColor3 = PANEL,
				[Children] = {
					corner(scope, 8),
					scope:New("Frame")({
						Name = "Fill",
						BackgroundColor3 = color,
						Size = scope:Computed(function(use)
							return UDim2.fromScale(use(progress), 1)
						end),
						[Children] = { corner(scope, 8) },
					}),
					label(scope, {
						Name = "Time",
						Size = UDim2.fromScale(1, 1),
						Text = timeText,
						TextSize = 12,
						Stroke = 0.3,
						ZIndex = 2,
					}),
				},
			}),
		},
	})
end

local function smallButton(scope, props)
	return scope:New("TextButton")({
		Name = props.Name,
		Position = props.Position,
		Size = props.Size,
		BackgroundColor3 = props.Color,
		Font = Enum.Font.GothamBold,
		Text = props.Text,
		TextColor3 = WHITE,
		TextSize = 12,
		TextWrapped = true,
		[OnEvent("Activated")] = props.Activated,
		[Children] = { corner(scope, 7) },
	})
end

local function petCard(scope, pet)
	local name = Panels.petName(pet.kind)
	local variant = pet.variant or "Normal"
	-- Selling takes two taps: the first asks "Sure?".
	local confirming = scope:Value(false)
	local riding = scope:Computed(function(use)
		return use(UiState.mountChoice) == pet.uid
	end)
	return scope:New("TextButton")({
		Name = "Pet_" .. pet.uid,
		BackgroundColor3 = CARD,
		AutoButtonColor = true,
		Text = "",
		[OnEvent("Activated")] = function()
			UiState.selected:set({
				type = "Pet",
				kind = pet.kind,
				rarity = pet.rarity,
				variant = variant,
				uid = pet.uid,
			})
		end,
		[Children] = {
			corner(scope, 10),
			cardStroke(scope, pet.kind, pet.rarity),
			petIcon(scope, name, pet.rarity, 40),
			label(scope, {
				Name = "Title",
				Position = UDim2.fromOffset(4, 50),
				Size = UDim2.new(1, -8, 0, 28),
				Text = name,
				TextSize = 13,
			}),
			label(scope, {
				Name = "Rarity",
				Position = UDim2.fromOffset(4, 78),
				Size = UDim2.new(1, -8, 0, 14),
				Text = if variant ~= "Normal" then `{variant} {pet.rarity}` else pet.rarity,
				Color = VARIANT_COLORS[variant] or Panels.rarityColor(pet.rarity),
				TextSize = 11,
			}),
			label(scope, {
				Name = "Income",
				Position = UDim2.fromOffset(4, 93),
				Size = UDim2.new(1, -8, 0, 14),
				Text = `{Panels.money(PetWorth.income(pet))}/s`,
				Color = Color3.fromRGB(140, 235, 140),
				TextSize = 11,
			}),
			smallButton(scope, {
				Name = "Pen",
				Position = UDim2.fromOffset(6, 112),
				Size = UDim2.new(1, -12, 0, 24),
				Color = if pet.inPen then GO else OFF,
				Text = if pet.inPen then "In pen" else "Put in pen",
				Activated = function()
					UiState.actions.setInPen(pet.uid, not pet.inPen)
				end,
			}),
			scope:New("TextButton")({
				Name = "Ride",
				Position = UDim2.fromOffset(6, 140),
				Size = UDim2.new(0.5, -8, 0, 24),
				BackgroundColor3 = scope:Computed(function(use)
					return if use(riding) then RIDE_COLOR else OFF
				end),
				Font = Enum.Font.GothamBold,
				Text = scope:Computed(function(use)
					return if use(riding) then "Riding" else "Ride"
				end),
				TextColor3 = WHITE,
				TextSize = 12,
				[OnEvent("Activated")] = function()
					UiState.actions.ridePet(if Fusion.peek(riding) then "" else pet.uid)
				end,
				[Children] = { corner(scope, 7) },
			}),
			scope:New("TextButton")({
				Name = "Sell",
				Position = UDim2.new(0.5, 2, 0, 140),
				Size = UDim2.new(0.5, -8, 0, 24),
				BackgroundColor3 = SELL,
				Font = Enum.Font.GothamBold,
				Text = scope:Computed(function(use)
					return if use(confirming) then "Sure?" else Panels.money(PetWorth.sellPrice(pet))
				end),
				TextColor3 = WHITE,
				TextSize = 11,
				TextWrapped = true,
				[OnEvent("Activated")] = function()
					if Fusion.peek(confirming) then
						confirming:set(false)
						UiState.actions.sellPet(pet.uid)
					else
						confirming:set(true)
						task.delay(3, function()
							confirming:set(false)
						end)
					end
				end,
				[Children] = { corner(scope, 7) },
			}),
		},
	})
end

----------------------------------------------------------------------------------------------------------------
-- The panel

local function sectionTitle(scope, order: number, text)
	return label(scope, {
		Name = "Section" .. order,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 22),
		Text = text,
		XAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
	})
end

local function grid(scope, name: string, order: number, cellHeight: number, items)
	return scope:New("Frame")({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		[Children] = {
			scope:New("UIGridLayout")({
				CellSize = UDim2.fromOffset(120, cellHeight),
				CellPadding = UDim2.fromOffset(8, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			items,
		},
	})
end

local function previewText(use): string
	local selected = use(UiState.selected)
	if selected == nil then
		return ""
	end
	if selected.type == "Egg" then
		local hatch = NumberFormat.duration(HatchMath.hatchTime(selected.rarity))
		return `{Panels.eggName(selected.kind)}\n{selected.rarity} - hatches in {hatch}`
	end
	local pet = { zone = selected.zone or 1, rarity = selected.rarity, variant = selected.variant }
	for _, owned in use(UiState.pets) do
		if owned.uid == selected.uid then
			pet = owned
		end
	end
	return `{Panels.fullPetName(selected.kind, selected.variant)}  ({selected.rarity})\n`
		.. `Earns {Panels.money(PetWorth.income(pet))}/s - runs {PetWorth.mountSpeed(pet)} studs/s`
end

local function panel(scope)
	local eggsContent = scope:ForValues(UiState.eggs, function(_, innerScope, item)
		return eggCard(innerScope, item)
	end)

	local hatchRows = scope:Computed(function(use, innerScope)
		local rows = {}
		local hatching = use(UiState.hatching)
		for index, entry in hatching do
			table.insert(rows, hatchRow(innerScope, index, entry))
		end
		for order = #hatching + 1, use(UiState.eggCapacity) do
			table.insert(rows, freeRow(innerScope, order))
		end
		return rows
	end)

	local petCards = scope:Computed(function(use, innerScope)
		local pets = use(UiState.pets)
		local cards = {}
		-- Pets in the pen first, then the rest; newest first within each.
		local order = 0
		for _, inPen in { true, false } do
			for index = #pets, 1, -1 do
				if pets[index].inPen == inPen then
					local card = petCard(innerScope, pets[index])
					order += 1
					card.LayoutOrder = order
					table.insert(cards, card)
				end
			end
		end
		return cards
	end)

	local penCount = scope:Computed(function(use)
		local count = 0
		for _, pet in use(UiState.pets) do
			if pet.inPen then
				count += 1
			end
		end
		return count
	end)

	local isEggs = scope:Computed(function(use)
		return use(UiState.panel) == "Eggs"
	end)
	local isPets = scope:Computed(function(use)
		return use(UiState.panel) == "Pets"
	end)

	return scope:New("Frame")({
		Name = "Inventory",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -104, 0.5, 0),
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.05,
		Visible = scope:Computed(function(use)
			return use(UiState.panel) ~= "None"
		end),
		[Children] = {
			corner(scope, 14),
			scope:New("UIStroke")({ Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.4 }),
			label(scope, {
				Name = "Title",
				Position = UDim2.fromOffset(16, 8),
				Size = UDim2.new(1, -70, 0, 30),
				Font = Enum.Font.FredokaOne,
				Text = scope:Computed(function(use)
					if use(UiState.panel) == "Eggs" then
						return `Your eggs ({#use(UiState.eggs)})`
					end
					return `Your pets ({#use(UiState.pets)})`
				end),
				TextSize = 24,
				XAlignment = Enum.TextXAlignment.Left,
			}),
			scope:New("TextButton")({
				Name = "Close",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 8),
				Size = UDim2.fromOffset(34, 34),
				BackgroundColor3 = Color3.fromRGB(200, 70, 70),
				Font = Enum.Font.GothamBold,
				Text = "X",
				TextColor3 = WHITE,
				TextSize = 18,
				[OnEvent("Activated")] = function()
					UiState.actions.openPanel("None")
				end,
				[Children] = { corner(scope, 8) },
			}),

			-- The selected egg or pet, turning slowly (the model is put in by InventoryController).
			scope:New("ViewportFrame")({
				Name = "Preview",
				Position = UDim2.fromOffset(12, 46),
				Size = UDim2.new(1, -24, 0, 150),
				BackgroundColor3 = Color3.fromRGB(56, 62, 82),
				Ambient = Color3.fromRGB(170, 170, 180),
				LightColor = Color3.fromRGB(255, 250, 240),
				LightDirection = Vector3.new(-1, -1.5, -1),
				[Children] = {
					corner(scope, 10),
					label(scope, {
						Name = "Caption",
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.new(0, 10, 1, -6),
						Size = UDim2.new(1, -20, 0, 34),
						Text = scope:Computed(previewText),
						XAlignment = Enum.TextXAlignment.Left,
						TextSize = 13,
						Stroke = 0.2,
						ZIndex = 2,
					}),
					label(scope, {
						Name = "Hint",
						Size = UDim2.fromScale(1, 1),
						Text = scope:Computed(function(use)
							if use(UiState.selected) ~= nil then
								return ""
							end
							return if use(UiState.panel) == "Eggs"
								then "Claim eggs on the runway, then place them here to hatch."
								else "Place eggs in your nests: they hatch into pets."
						end),
						Color = MUTED,
						TextSize = 14,
					}),
				},
			}),

			scope:New("ScrollingFrame")({
				Name = "List",
				Position = UDim2.fromOffset(12, 206),
				Size = UDim2.new(1, -24, 1, -216),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 6,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				[Children] = {
					scope:New("UIListLayout")({
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					-- Eggs
					scope:New("Frame")({
						Name = "EggsPage",
						LayoutOrder = 1,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Visible = isEggs,
						[Children] = {
							scope:New("UIListLayout")({
								Padding = UDim.new(0, 8),
								SortOrder = Enum.SortOrder.LayoutOrder,
							}),
							sectionTitle(
								scope,
								1,
								scope:Computed(function(use)
									local free = use(UiState.eggCapacity) - #use(UiState.hatching)
									if #use(UiState.eggs) == 0 then
										return "No eggs yet: ride one to the end of its claim meter!"
									end
									return `Stand in your pen to put eggs down ({math.max(0, free)} of {use(
										UiState.eggCapacity
									)} free)`
								end)
							),
							grid(scope, "Eggs", 2, 150, eggsContent),
						},
					}),
					-- Pets
					scope:New("Frame")({
						Name = "PetsPage",
						LayoutOrder = 2,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Visible = isPets,
						[Children] = {
							scope:New("UIListLayout")({
								Padding = UDim.new(0, 8),
								SortOrder = Enum.SortOrder.LayoutOrder,
							}),
							sectionTitle(
								scope,
								1,
								scope:Computed(function(use)
									return `Hatching ({#use(UiState.hatching)} of {use(UiState.eggCapacity)})`
								end)
							),
							scope:New("Frame")({
								Name = "Hatching",
								LayoutOrder = 2,
								Size = UDim2.fromScale(1, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								BackgroundTransparency = 1,
								[Children] = {
									scope:New("UIListLayout")({
										Padding = UDim.new(0, 6),
										SortOrder = Enum.SortOrder.LayoutOrder,
									}),
									hatchRows,
								},
							}),
							-- Pets, and the button that fills the pen with the best of them.
							scope:New("Frame")({
								Name = "PetsHeader",
								LayoutOrder = 3,
								Size = UDim2.new(1, 0, 0, 34),
								BackgroundTransparency = 1,
								[Children] = {
									label(scope, {
										Name = "Count",
										Size = UDim2.new(1, -130, 1, 0),
										Text = scope:Computed(function(use)
											local count = #use(UiState.pets)
											if count == 0 then
												return "No pets yet"
											end
											return `Pets ({count}) - in pen {use(penCount)} of {use(UiState.petCapacity)}`
										end),
										XAlignment = Enum.TextXAlignment.Left,
										TextSize = 14,
									}),
									scope:New("TextButton")({
										Name = "EquipBest",
										AnchorPoint = Vector2.new(1, 0),
										Position = UDim2.fromScale(1, 0),
										Size = UDim2.fromOffset(124, 34),
										BackgroundColor3 = GO,
										Font = Enum.Font.GothamBold,
										Text = "Equip best",
										TextColor3 = WHITE,
										TextSize = 14,
										[OnEvent("Activated")] = function()
											UiState.actions.equipBest()
										end,
										[Children] = { corner(scope, 8) },
									}),
								},
							}),
							grid(scope, "Pets", 4, 172, petCards),
						},
					}),
				},
			}),
		},
	})
end

-- A big button down the right edge that opens a panel, with a count badge.
local function tabButton(scope, name: string, order: number, color: Color3, badge)
	return scope:New("TextButton")({
		Name = name .. "Tab",
		LayoutOrder = order,
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = color,
		Font = Enum.Font.FredokaOne,
		Text = string.upper(name),
		TextColor3 = WHITE,
		TextSize = 20,
		TextStrokeTransparency = 0.5,
		[OnEvent("Activated")] = function()
			local current = Fusion.peek(UiState.panel)
			UiState.actions.openPanel(if current == name then "None" else name)
		end,
		[Children] = {
			corner(scope, 16),
			scope:New("UIStroke")({
				Color = Color3.new(0, 0, 0),
				Thickness = 3,
				Transparency = 0.3,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			scope:New("TextLabel")({
				Name = "Badge",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 6, 0, -6),
				Size = UDim2.fromOffset(30, 26),
				BackgroundColor3 = Color3.fromRGB(230, 50, 60),
				Font = Enum.Font.GothamBold,
				Text = scope:Computed(function(use)
					return tostring(use(badge))
				end),
				TextColor3 = WHITE,
				TextSize = 14,
				Visible = scope:Computed(function(use)
					return use(badge) > 0
				end),
				[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }) },
			}),
		},
	})
end

-- Everything on the right edge: the tab buttons and the panel they open.
function Panels.build(scope)
	return {
		scope:New("Frame")({
			Name = "SideTabs",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(84, 252),
			BackgroundTransparency = 1,
			[Children] = {
				scope:New("UIListLayout")({
					Padding = UDim.new(0, 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				tabButton(
					scope,
					"Eggs",
					1,
					EGGS_COLOR,
					scope:Computed(function(use)
						return #use(UiState.eggs)
					end)
				),
				tabButton(scope, "Pets", 2, PETS_COLOR, UiState.newPets),
				-- Get on the chosen pet, or off it (only once one has been chosen).
				scope:New("TextButton")({
					Name = "RideTab",
					LayoutOrder = 3,
					Size = UDim2.fromOffset(84, 60),
					BackgroundColor3 = RIDE_COLOR,
					Font = Enum.Font.FredokaOne,
					Text = scope:Computed(function(use)
						return if use(UiState.riddenPet) ~= "" then "GET OFF" else "RIDE"
					end),
					TextColor3 = WHITE,
					TextSize = 18,
					TextStrokeTransparency = 0.5,
					Visible = scope:Computed(function(use)
						return use(UiState.mountChoice) ~= ""
					end),
					[OnEvent("Activated")] = function()
						local riding = Fusion.peek(UiState.riddenPet) ~= ""
						UiState.actions.ridePet(if riding then "" else Fusion.peek(UiState.mountChoice))
					end,
					[Children] = {
						corner(scope, 16),
						scope:New("UIStroke")({
							Color = Color3.new(0, 0, 0),
							Thickness = 3,
							Transparency = 0.3,
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						}),
					},
				}),
			},
		}),
		panel(scope),
	}
end

return Panels
