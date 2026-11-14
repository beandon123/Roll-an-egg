-- The Eggs and Pets tabs on the right of the screen, built with Fusion:
--     Eggs  the eggs the player has claimed; Place puts one in a free nest on their plot
--     Pets  their nests, each with its egg's countdown, and the pets that have hatched
-- A 3D preview at the top of each panel shows the selected egg or pet (filled in by InventoryController).
-- Like the rest of the HUD, this only reads UiState; the buttons call UiState.actions.

local Load = require(script.Parent.Parent.Load)
local CycleClock = Load.shared("CycleClock")
local EggModels = Load.shared("EggModels")
local HatchMath = Load.shared("HatchMath")
local NumberFormat = Load.shared("NumberFormat")
local PetModels = Load.shared("PetModels")
local Plots = Load.shared("Plots")
local Rarities = Load.shared("Config", "Rarities")
local Tuning = Load.shared("Config", "Tuning")
local Zones = Load.shared("Config", "Zones")

local UiState = require(script.Parent.UiState)

local Fusion = UiState.Fusion
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(26, 28, 36)
local CARD = Color3.fromRGB(44, 47, 60)
local MUTED = Color3.fromRGB(170, 176, 192)
local GO = Color3.fromRGB(70, 190, 100)
local EGGS_COLOR = Color3.fromRGB(70, 140, 255)
local PETS_COLOR = Color3.fromRGB(255, 140, 60)

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

local function zoneName(zone: number): string
	local info = Zones.List[zone]
	return if info then info.name else ""
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

-- One nest: its egg, a bar filling as it hatches, and the time left. Or an empty nest.
local function nestRow(scope, slot: number, nest)
	if nest == nil then
		return scope:New("Frame")({
			Name = "Nest" .. slot,
			LayoutOrder = slot,
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = CARD,
			[Children] = {
				corner(scope, 10),
				label(scope, {
					Position = UDim2.fromOffset(12, 0),
					Size = UDim2.new(1, -140, 1, 0),
					Text = `Nest {slot}: empty`,
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
					Text = "Place an egg",
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

	local color = Panels.rarityColor(nest.rarity)
	local progress = scope:Computed(function(use)
		return HatchMath.progress(nest.placedAt, nest.bonus, nest.rarity, use(UiState.clock))
	end)
	local timeText = scope:Computed(function(use)
		local now = use(UiState.clock)
		local left = HatchMath.timeLeft(nest.placedAt, nest.bonus, nest.rarity, now)
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
		Name = "Nest" .. slot,
		LayoutOrder = slot,
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = CARD,
		AutoButtonColor = true,
		Text = "",
		[OnEvent("Activated")] = function()
			UiState.selected:set({ type = "Egg", kind = nest.kind, rarity = nest.rarity })
		end,
		[Children] = {
			corner(scope, 10),
			cardStroke(scope, nest.kind, nest.rarity),
			scope:New("Frame")({
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.fromOffset(40, 52),
				BackgroundTransparency = 1,
				[Children] = { eggIcon(scope, nest.rarity, 36) },
			}),
			label(scope, {
				Name = "Title",
				Position = UDim2.fromOffset(54, 4),
				Size = UDim2.new(1, -62, 0, 18),
				Text = `Nest {slot}: {Panels.eggName(nest.kind)}`,
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

local function petCard(scope, pet, inPen: boolean)
	local name = Panels.petName(pet.kind)
	return scope:New("TextButton")({
		Name = "Pet_" .. pet.uid,
		BackgroundColor3 = CARD,
		AutoButtonColor = true,
		Text = "",
		[OnEvent("Activated")] = function()
			UiState.selected:set({ type = "Pet", kind = pet.kind, rarity = pet.rarity })
		end,
		[Children] = {
			corner(scope, 10),
			cardStroke(scope, pet.kind, pet.rarity),
			petIcon(scope, name, pet.rarity, 42),
			label(scope, {
				Name = "Title",
				Position = UDim2.fromOffset(4, 54),
				Size = UDim2.new(1, -8, 0, 30),
				Text = name,
				TextSize = 13,
			}),
			label(scope, {
				Name = "Rarity",
				Position = UDim2.fromOffset(4, 84),
				Size = UDim2.new(1, -8, 0, 14),
				Text = pet.rarity,
				Color = Panels.rarityColor(pet.rarity),
				TextSize = 11,
			}),
			label(scope, {
				Name = "Where",
				Position = UDim2.fromOffset(4, 100),
				Size = UDim2.new(1, -8, 0, 14),
				Text = if inPen then "In your pen" else zoneName(pet.zone),
				Color = MUTED,
				TextSize = 10,
			}),
		},
	})
end

-- The pets that roam the pen: the rarest, then the newest (as the server picks them).
local function penUids(pets): { [string]: boolean }
	local sorted = table.clone(pets)
	table.sort(sorted, function(a, b)
		local orderA = if Rarities.Info[a.rarity] then Rarities.Info[a.rarity].order else 0
		local orderB = if Rarities.Info[b.rarity] then Rarities.Info[b.rarity].order else 0
		if orderA ~= orderB then
			return orderA > orderB
		end
		return a.hatchedAt > b.hatchedAt
	end)
	local chosen = {}
	for index = 1, math.min(Plots.PEN_CAPACITY, #sorted) do
		chosen[sorted[index].uid] = true
	end
	return chosen
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
	local name = if selected.type == "Egg" then Panels.eggName(selected.kind) else Panels.petName(selected.kind)
	local extra = if selected.type == "Egg"
		then `Hatches in {NumberFormat.duration(HatchMath.hatchTime(selected.rarity))}`
		else "Hatched pet"
	return `{name}\n{selected.rarity} - {extra}`
end

local function panel(scope)
	local eggsContent = scope:ForValues(UiState.eggs, function(_, innerScope, item)
		return eggCard(innerScope, item)
	end)

	local nestRows = scope:Computed(function(use, innerScope)
		local bySlot = {}
		for _, nest in use(UiState.nests) do
			bySlot[nest.slot] = nest
		end
		local rows = {}
		for slot = 1, use(UiState.nestCount) do
			table.insert(rows, nestRow(innerScope, slot, bySlot[slot]))
		end
		return rows
	end)

	local petCards = scope:Computed(function(use, innerScope)
		local pets = use(UiState.pets)
		local inPen = penUids(pets)
		local cards = {}
		-- Newest first.
		for index = #pets, 1, -1 do
			local card = petCard(innerScope, pets[index], inPen[pets[index].uid] == true)
			card.LayoutOrder = #pets - index
			table.insert(cards, card)
		end
		return cards
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
									local free = use(UiState.nestCount) - #use(UiState.nests)
									if #use(UiState.eggs) == 0 then
										return "No eggs yet: ride one to the end of its claim meter!"
									end
									return `Free nests: {math.max(0, free)} of {use(UiState.nestCount)}`
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
							sectionTitle(scope, 1, "Hatching"),
							scope:New("Frame")({
								Name = "Nests",
								LayoutOrder = 2,
								Size = UDim2.fromScale(1, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								BackgroundTransparency = 1,
								[Children] = {
									scope:New("UIListLayout")({
										Padding = UDim.new(0, 6),
										SortOrder = Enum.SortOrder.LayoutOrder,
									}),
									nestRows,
								},
							}),
							sectionTitle(
								scope,
								3,
								scope:Computed(function(use)
									local count = #use(UiState.pets)
									return if count == 0 then "No pets yet" else `Pets ({count})`
								end)
							),
							grid(scope, "Pets", 4, 120, petCards),
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
			Size = UDim2.fromOffset(84, 180),
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
			},
		}),
		panel(scope),
	}
end

return Panels
