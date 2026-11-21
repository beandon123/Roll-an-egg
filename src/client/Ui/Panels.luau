-- The Eggs and Pets tabs on the right of the screen, built with Fusion, and the Ride button under them:
--     Eggs  the eggs the player has claimed (they are in the Roblox inventory too); Hold puts one in their hand,
--           ready to click a spot in their pen
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

local Theme = require(script.Parent.Theme)
local UiState = require(script.Parent.UiState)
local Widgets = require(script.Parent.Widgets)

local Fusion = UiState.Fusion
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

-- The shared look (Ui/Theme): a deep indigo panel with a glossy title band, cards a shade lighter, white lettering
-- outlined in navy, and glossy buttons.
local WHITE = Theme.WHITE
local PANEL = Theme.WELL
local CARD = Theme.CARD
local MUTED = Theme.TEXT_SOFT
local GO = Theme.GREEN
local OFF = Theme.CARD_EDGE
local SELL = Theme.CORAL
local EGGS_COLOR = Theme.SKY
local PETS_COLOR = Theme.YOLK_DEEP
local RIDE_COLOR = Theme.GREEN

local MUTATION_COLORS = {
	Silver = Color3.fromRGB(214, 222, 236),
	Gold = Color3.fromRGB(255, 205, 70),
	Diamond = Color3.fromRGB(150, 235, 255),
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

-- Lettering in the house style: white, outlined in navy (a little thicker with `Stroke`).
local function label(scope, props)
	return scope:New("TextLabel")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		BackgroundTransparency = 1,
		Font = props.Font or Theme.FONT,
		Text = props.Text,
		TextColor3 = props.Color or WHITE,
		TextSize = props.TextSize or 14,
		TextWrapped = true,
		TextXAlignment = props.XAlignment or Enum.TextXAlignment.Center,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New("UIStroke")({ Color = Theme.INK, Thickness = if props.Stroke then 2 else 1.5 }),
		},
	})
end

-- What a small button wears: rounded corners, a glossy fade, a navy edge, and its lettering outlined in navy.
local function buttonSkin(scope, radius: number)
	return {
		corner(scope, radius),
		scope:New("UIGradient")({
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 214)),
			Rotation = 90,
		}),
		scope:New("UIStroke")({ ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Theme.INK, Thickness = 2 }),
		scope:New("UIStroke")({ ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Color = Theme.INK, Thickness = 1.5 }),
	}
end

-- A card's shading: a shade darker towards its bottom.
local function cardShade(scope)
	return scope:New("UIGradient")({
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 196)),
		Rotation = 90,
	})
end

-- How wide an egg is at each height, from its narrow top (v = -1) to its round bottom (v = 1): half its width, as a
-- fraction of its widest.
local function eggHalfWidth(v: number): number
	return math.sqrt(math.max(0, 1 - v * v)) * (0.8 + 0.14 * v) / 0.84
end

-- An egg shape drawn from thin horizontal slices (no image needed), filling its parent (best about 0.78 as wide as
-- it is tall), in one colour.
local function eggSlices(scope, name: string, color: Color3, slices: number, inset: number)
	local parts = {}
	for index = 0, slices - 1 do
		local v = (index + 0.5) / slices * 2 - 1
		local width = eggHalfWidth(v) * (1 - inset * 2)
		table.insert(
			parts,
			scope:New("Frame")({
				Name = "Slice" .. index,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, inset + (1 - inset * 2) * index / slices),
				-- A hair taller than its share, so no line shows between slices.
				Size = UDim2.new(width, 0, (1 - inset * 2) / slices, 1),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			})
		)
	end
	return scope:New("Frame")({
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		[Children] = parts,
	})
end

-- A shine on the egg's upper left.
local function eggShine(scope)
	return scope:New("Frame")({
		Name = "Shine",
		Position = UDim2.fromScale(0.24, 0.2),
		Size = UDim2.fromScale(0.17, 0.27),
		Rotation = 18,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.35,
		[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }) },
	})
end

-- The Eggs tab's picture: a speckled cream egg with a dark outline and a shine.
function Panels.eggPicture(scope, props: { Size: UDim2, Position: UDim2?, AnchorPoint: Vector2? })
	local speckles = {}
	for index, spot in { { 0.62, 0.38, 0.1 }, { 0.42, 0.62, 0.08 }, { 0.68, 0.7, 0.07 }, { 0.3, 0.45, 0.06 } } do
		table.insert(
			speckles,
			scope:New("Frame")({
				Name = "Speckle" .. index,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spot[1], spot[2]),
				Size = UDim2.fromScale(spot[3], spot[3] * 0.78),
				BackgroundColor3 = Color3.fromRGB(196, 150, 104),
				BorderSizePixel = 0,
				[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }) },
			})
		)
	end
	return scope:New("Frame")({
		Name = "EggPicture",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		BackgroundTransparency = 1,
		[Children] = {
			eggSlices(scope, "Outline", Color3.fromRGB(46, 34, 30), 28, 0),
			eggSlices(scope, "Shell", Color3.fromRGB(255, 244, 222), 28, 0.07),
			speckles,
			eggShine(scope),
		},
	})
end

-- The Pets tab's picture: a paw print, a big pad and four toe pads, each with a dark outline.
function Panels.pawPicture(scope, props: { Size: UDim2, Position: UDim2?, AnchorPoint: Vector2? })
	local fill = Color3.fromRGB(255, 240, 222)
	-- Each pad twice: its outline underneath, its fill on top, so where pads overlap no outline shows inside.
	local function pad(name: string, x: number, y: number, width: number, height: number, rotation: number, outline)
		return scope:New("Frame")({
			Name = name .. (if outline then "Outline" else ""),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(width, height),
			Rotation = rotation,
			BackgroundColor3 = fill,
			ZIndex = if outline then 1 else 2,
			[Children] = {
				scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				if outline then scope:New("UIStroke")({ Color = Color3.fromRGB(70, 34, 20), Thickness = 3 }) else nil,
			},
		})
	end
	local pads = {
		-- The big pad: two overlapping rounds make it wider at the top, like a real one.
		{ "PadBottom", 0.5, 0.74, 0.46, 0.34, 0 },
		{ "PadTop", 0.5, 0.64, 0.56, 0.34, 0 },
		{ "ToeOuterLeft", 0.14, 0.4, 0.18, 0.25, -28 },
		{ "ToeLeft", 0.36, 0.17, 0.19, 0.27, -10 },
		{ "ToeRight", 0.64, 0.17, 0.19, 0.27, 10 },
		{ "ToeOuterRight", 0.86, 0.4, 0.18, 0.25, 28 },
	}
	local parts = {}
	for _, outline in { true, false } do
		for _, spec in pads do
			table.insert(parts, pad(spec[1], spec[2], spec[3], spec[4], spec[5], spec[6], outline))
		end
	end
	return scope:New("Frame")({
		Name = "PawPicture",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		BackgroundTransparency = 1,
		[Children] = parts,
	})
end

-- An egg shape in its rarity colour, with a shine.
local function eggIcon(scope, rarity: string, size: number)
	return scope:New("Frame")({
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(size * 0.78, size),
		BackgroundTransparency = 1,
		[Children] = {
			eggSlices(scope, "Shell", Panels.rarityColor(rarity), 14, 0),
			eggShine(scope),
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
			scope:New("UIStroke")({ Color = Theme.INK, Thickness = 2 }),
			label(scope, {
				Size = UDim2.fromScale(1, 1),
				Text = string.upper(string.sub(name, 1, 1)),
				Font = Theme.FONT,
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
			cardShade(scope),
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
				Name = "Hold",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -6),
				Size = UDim2.new(1, -12, 0, 26),
				BackgroundColor3 = GO,
				Font = Theme.FONT,
				Text = "Hold",
				TextColor3 = WHITE,
				TextSize = 14,
				[OnEvent("Activated")] = function()
					UiState.actions.holdEgg(item.kind)
				end,
				[Children] = buttonSkin(scope, 8),
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
				Font = Theme.FONT,
				Text = "Put an egg down",
				TextColor3 = WHITE,
				TextSize = 13,
				[OnEvent("Activated")] = function()
					UiState.actions.openPanel("Eggs")
				end,
				[Children] = buttonSkin(scope, 8),
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
			cardShade(scope),
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
						[Children] = buttonSkin(scope, 8),
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
		Font = Theme.FONT,
		Text = props.Text,
		TextColor3 = WHITE,
		TextSize = 12,
		TextWrapped = true,
		[OnEvent("Activated")] = props.Activated,
		[Children] = buttonSkin(scope, 7),
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
			cardShade(scope),
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
				Color = MUTATION_COLORS[variant] or Panels.rarityColor(pet.rarity),
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
				Font = Theme.FONT,
				Text = scope:Computed(function(use)
					return if use(riding) then "Riding" else "Ride"
				end),
				TextColor3 = WHITE,
				TextSize = 12,
				[OnEvent("Activated")] = function()
					UiState.actions.ridePet(if Fusion.peek(riding) then "" else pet.uid)
				end,
				[Children] = buttonSkin(scope, 7),
			}),
			scope:New("TextButton")({
				Name = "Sell",
				Position = UDim2.new(0.5, 2, 0, 140),
				Size = UDim2.new(0.5, -8, 0, 24),
				BackgroundColor3 = SELL,
				Font = Theme.FONT,
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
				[Children] = buttonSkin(scope, 7),
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
		BackgroundColor3 = WHITE,
		Visible = scope:Computed(function(use)
			return use(UiState.panel) ~= "None"
		end),
		[Children] = {
			Widgets.panelSkin(scope),
			-- The glossy band behind the title and the close button.
			Widgets.titleBand(scope, { Name = "Band", Text = "", Height = 50, ZIndex = 0 }),
			label(scope, {
				Name = "Title",
				Position = UDim2.fromOffset(18, 6),
				Size = UDim2.new(1, -70, 0, 38),
				Font = Theme.TITLE_FONT,
				Text = scope:Computed(function(use)
					if use(UiState.panel) == "Eggs" then
						return `Your eggs ({#use(UiState.eggs)})`
					end
					return `Your pets ({#use(UiState.pets)})`
				end),
				TextSize = 28,
				Stroke = true,
				XAlignment = Enum.TextXAlignment.Left,
			}),
			scope:New("TextButton")({
				Name = "Close",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 6, 0, 6),
				Size = UDim2.fromOffset(42, 42),
				BackgroundColor3 = Theme.CORAL,
				Font = Theme.FONT,
				Text = "✕",
				TextColor3 = WHITE,
				TextSize = 22,
				[OnEvent("Activated")] = function()
					UiState.actions.openPanel("None")
				end,
				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
					scope:New("UIStroke")({
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = Theme.WHITE,
						Thickness = 3,
					}),
					scope:New("UIStroke")({
						ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
						Color = Theme.INK,
						Thickness = 2,
					}),
				},
			}),

			-- The selected egg or pet, turning slowly (the model is put in by InventoryController).
			scope:New("ViewportFrame")({
				Name = "Preview",
				Position = UDim2.fromOffset(12, 58),
				Size = UDim2.new(1, -24, 0, 146),
				BackgroundColor3 = Theme.CARD_DEEP,
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
								then "Claim eggs on the runway, then put them down in your pen to hatch."
								else "Put eggs down in your pen: they hatch into pets."
						end),
						Color = MUTED,
						TextSize = 14,
					}),
				},
			}),

			scope:New("ScrollingFrame")({
				Name = "List",
				Position = UDim2.fromOffset(12, 214),
				Size = UDim2.new(1, -24, 1, -226),
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
									return `Hold an egg, then click a spot in your pen ({math.max(0, free)} of {use(
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
										Font = Theme.FONT,
										Text = "Equip best",
										TextColor3 = WHITE,
										TextSize = 14,
										[OnEvent("Activated")] = function()
											UiState.actions.equipBest()
										end,
										[Children] = buttonSkin(scope, 8),
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

-- A big button down the right edge that opens a panel: its picture, its name under it, and a count badge.
local function tabButton(scope, name: string, order: number, color: Color3, badge, picture)
	return scope:New("TextButton")({
		Name = name .. "Tab",
		LayoutOrder = order,
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = color,
		Text = "",
		[OnEvent("Activated")] = function()
			local current = Fusion.peek(UiState.panel)
			UiState.actions.openPanel(if current == name then "None" else name)
		end,
		[Children] = {
			picture,
			scope:New("TextLabel")({
				Name = "Label",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -3),
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Font = Theme.FONT,
				Text = string.upper(name),
				TextColor3 = WHITE,
				TextSize = 16,
				[Children] = { scope:New("UIStroke")({ Color = Theme.INK, Thickness = 2 }) },
			}),
			corner(scope, 16),
			cardShade(scope),
			scope:New("UIStroke")({
				Color = Theme.INK,
				Thickness = 3,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			scope:New("TextLabel")({
				Name = "Badge",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 6, 0, -6),
				ZIndex = 3,
				Size = UDim2.fromOffset(30, 26),
				BackgroundColor3 = Theme.CORAL,
				Font = Theme.FONT,
				Text = scope:Computed(function(use)
					return tostring(use(badge))
				end),
				TextColor3 = WHITE,
				TextSize = 14,
				Visible = scope:Computed(function(use)
					return use(badge) > 0
				end),
				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
					scope:New("UIStroke")({
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = Theme.WHITE,
						Thickness = 2,
					}),
					scope:New("UIStroke")({ Color = Theme.INK, Thickness = 1.5 }),
				},
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
					end),
					Panels.eggPicture(scope, {
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 7),
						Size = UDim2.fromOffset(44, 56),
					})
				),
				tabButton(
					scope,
					"Pets",
					2,
					PETS_COLOR,
					UiState.newPets,
					Panels.pawPicture(scope, {
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, 9),
						Size = UDim2.fromOffset(54, 52),
					})
				),
				-- Get on the chosen pet, or off it (only once one has been chosen).
				scope:New("TextButton")({
					Name = "RideTab",
					LayoutOrder = 3,
					Size = UDim2.fromOffset(84, 60),
					BackgroundColor3 = RIDE_COLOR,
					Font = Theme.FONT,
					Text = scope:Computed(function(use)
						return if use(UiState.riddenPet) ~= "" then "GET OFF" else "RIDE"
					end),
					TextColor3 = WHITE,
					TextSize = 18,
					Visible = scope:Computed(function(use)
						return use(UiState.mountChoice) ~= ""
					end),
					[OnEvent("Activated")] = function()
						local riding = Fusion.peek(UiState.riddenPet) ~= ""
						UiState.actions.ridePet(if riding then "" else Fusion.peek(UiState.mountChoice))
					end,
					[Children] = buttonSkin(scope, 16),
				}),
			},
		}),
		panel(scope),
	}
end

return Panels
