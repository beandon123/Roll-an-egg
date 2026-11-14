-- The admin panel, built with Fusion: an ADMIN button at the top right (for admins only) that opens a window with
-- five tabs.
--     Eggs      drop any egg on the runway, in front of you or at its zone's chute, or put it in your inventory
--     Pets      spawn any pet next to you, stand a whole zone's pets in front of you, or put a pet in your inventory
--     Me        flight, walk speed, stamina, and what is in your inventory
--     Events    start or stop an Egg Avalanche; close or open the runway now
--     Teleport  the hub, the Model Showroom, the end cliff, any zone, any other player
-- It only reads AdminState (and UiState for the runway cycle). Its buttons call the `run` function it is given,
-- which sends the command to the server and puts the answer in the status line (see AdminController).

local Workspace = game:GetService("Workspace")

local Load = require(script.Parent.Parent.Load)
local AdminTools = Load.shared("Config", "AdminTools")
local CycleClock = Load.shared("CycleClock")
local EggModels = Load.shared("EggModels")
local NumberFormat = Load.shared("NumberFormat")
local PetModels = Load.shared("PetModels")
local Rarities = Load.shared("Config", "Rarities")
local Zones = Load.shared("Config", "Zones")

local AdminState = require(script.Parent.AdminState)
local UiState = require(script.Parent.UiState)

local Fusion = UiState.Fusion
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local peek = Fusion.peek

local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(170, 176, 196)
local PANEL = Color3.fromRGB(26, 28, 36)
local CARD = Color3.fromRGB(40, 43, 56)
local BUTTON = Color3.fromRGB(64, 68, 90)
local SELECTED = Color3.fromRGB(255, 200, 80)
local GOOD = Color3.fromRGB(130, 230, 140)
local BAD = Color3.fromRGB(255, 125, 125)
local ADMIN_RED = Color3.fromRGB(214, 64, 76)
local FLYING_GREEN = Color3.fromRGB(46, 150, 90)

-- Laid out for a 720-pixel-tall screen and scaled to fit others, like the HUD.
local REFERENCE_HEIGHT = 720
local WINDOW_WIDTH = 384
local WINDOW_HEIGHT = 476
local TABS = { "Eggs", "Pets", "Me", "Events", "Teleport" }
-- Inventory lines listed at most (the rest are summed up in one line).
local MAX_INVENTORY_LINES = 24

type Run = (command: string, args: { [string]: any }?) -> ()

local AdminPanel = {}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function corner(scope, radius: number)
	return scope:New("UICorner")({ CornerRadius = UDim.new(0, radius) })
end

local function padding(scope, pixels: number)
	return scope:New("UIPadding")({
		PaddingTop = UDim.new(0, pixels),
		PaddingBottom = UDim.new(0, pixels),
		PaddingLeft = UDim.new(0, pixels),
		PaddingRight = UDim.new(0, pixels),
	})
end

local function column(scope, gap: number)
	return scope:New("UIListLayout")({
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- A button. `Selected` (true, or a state) outlines it in gold; `Text` and `Color` may be states too.
local function button(scope, props)
	return scope:New("TextButton")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = props.Color or BUTTON,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		Text = props.Text,
		TextColor3 = WHITE,
		TextSize = props.TextSize or 13,
		TextWrapped = true,
		TextStrokeTransparency = if props.Stroke then 0.5 else 1,
		[OnEvent("Activated")] = props.OnClick,
		[Children] = {
			corner(scope, 8),
			scope:New("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = SELECTED,
				Thickness = 2,
				Enabled = props.Selected or false,
			}),
		},
	})
end

local function label(scope, props)
	return scope:New("TextLabel")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Position = props.Position,
		Size = props.Size or UDim2.fromScale(1, 0),
		AutomaticSize = if props.Size then nil else Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = props.Font or Enum.Font.GothamBold,
		Text = props.Text,
		TextColor3 = props.Color or WHITE,
		TextSize = props.TextSize or 13,
		TextWrapped = true,
		TextXAlignment = props.XAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
end

-- A titled card in the panel, as tall as what is in it.
local function section(scope, name: string, title: string, order: number, contents: { any })
	return scope:New("Frame")({
		Name = name,
		LayoutOrder = order,
		BackgroundColor3 = CARD,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Children] = {
			corner(scope, 10),
			padding(scope, 8),
			column(scope, 6),
			label(scope, { Name = "Title", Text = title, LayoutOrder = 0, Color = MUTED, TextSize = 12 }),
			contents,
		},
	})
end

-- Buttons in equal cells, `columns` to a line, wrapping onto as many lines as they need.
local function grid(scope, name: string, order: number, columns: number, contents: { any })
	return scope:New("Frame")({
		Name = name,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Children] = {
			scope:New("UIGridLayout")({
				CellPadding = UDim2.fromOffset(6, 6),
				CellSize = UDim2.new(1 / columns, -6 * (columns - 1) / columns, 0, 30),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			contents,
		},
	})
end

-- One button per option; the one matching `current` is outlined.
local function choices(scope, name: string, order: number, options: { { text: string, value: any } }, current, pick)
	local buttons = {}
	for index, option in options do
		table.insert(
			buttons,
			button(scope, {
				Name = tostring(option.value),
				LayoutOrder = index,
				Text = option.text,
				Selected = scope:Computed(function(use)
					return use(current) == option.value
				end),
				OnClick = function()
					pick(option.value)
				end,
			})
		)
	end
	return grid(scope, name, order, math.min(#options, 4), buttons)
end

-- The six zones as buttons in their colours; clicking one picks it.
local function zonePicker(scope, order: number, selected)
	local buttons = {}
	for _, zone in Zones.List do
		table.insert(
			buttons,
			button(scope, {
				Name = zone.key,
				LayoutOrder = zone.id,
				Text = zone.name,
				Color = rgb(zone.accent),
				Stroke = true,
				Selected = scope:Computed(function(use)
					return use(selected) == zone.id
				end),
				OnClick = function()
					selected:set(zone.id)
				end,
			})
		)
	end
	return grid(scope, "Zones", order, 3, buttons)
end

-- One egg or pet: a dot in its rarity's colour, its name and rarity, and small buttons on the right.
local function itemRow(scope, props)
	local info = Rarities.Info[props.rarity]
	local color = if info then rgb(info.color) else WHITE
	local buttonWidth = 54
	local buttonsWidth = #props.buttons * (buttonWidth + 6)
	local contents = {
		scope:New("Frame")({
			Name = "Dot",
			Position = UDim2.new(0, 0, 0.5, -5),
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = color,
			[Children] = { corner(scope, 5) },
		}),
		label(scope, {
			Name = "Title",
			Position = UDim2.fromOffset(16, 0),
			Size = UDim2.new(1, -16 - buttonsWidth, 0, 17),
			Text = props.title,
		}),
		label(scope, {
			Name = "Rarity",
			Position = UDim2.fromOffset(16, 16),
			Size = UDim2.new(1, -16 - buttonsWidth, 0, 14),
			Text = props.rarity,
			Color = color,
			TextSize = 11,
			Font = Enum.Font.Gotham,
		}),
	}
	for index, spec in props.buttons do
		table.insert(
			contents,
			button(scope, {
				Name = spec.text,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -(#props.buttons - index) * (buttonWidth + 6), 0.5, 0),
				Size = UDim2.fromOffset(buttonWidth, 26),
				Text = spec.text,
				TextSize = 12,
				OnClick = spec.onClick,
			})
		)
	end
	return scope:New("Frame")({
		Name = props.name,
		LayoutOrder = props.order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 32),
		[Children] = contents,
	})
end

----------------------------------------------------------------------------------------------------------------
-- Tabs

local function eggsTab(scope, run: Run)
	return {
		section(scope, "Zone", "Zone", 1, { zonePicker(scope, 1, AdminState.eggZone) }),
		section(scope, "Where", "Drop eggs", 2, {
			choices(
				scope,
				"DropWhere",
				1,
				{
					{ text = "In front of me", value = "Here" },
					{ text = "At the zone's chute", value = "Chute" },
				},
				AdminState.dropWhere,
				function(value)
					AdminState.dropWhere:set(value)
				end
			),
		}),
		section(scope, "EggList", "Eggs: drop on the runway, or give to your inventory", 3, {
			scope:Computed(function(use, inner)
				local zone = Zones.List[use(AdminState.eggZone)]
				local rows = {}
				for index, entry in zone.eggs do
					local about = EggModels.describe(entry.egg)
					table.insert(
						rows,
						itemRow(inner, {
							name = entry.egg,
							order = index,
							title = if about then about.name else entry.egg,
							rarity = entry.rarity,
							buttons = {
								{
									text = "Drop",
									onClick = function()
										run("DropEgg", { egg = entry.egg, where = peek(AdminState.dropWhere) })
									end,
								},
								{
									text = "Give",
									onClick = function()
										run("GiveEgg", { egg = entry.egg })
									end,
								},
							},
						})
					)
				end
				return rows
			end),
		}),
		section(scope, "WholeZone", "Whole zone", 4, {
			grid(scope, "Buttons", 1, 3, {
				button(scope, {
					Name = "DropRandom",
					LayoutOrder = 1,
					Text = "Drop a random egg",
					OnClick = function()
						run("DropRandomEgg", { zone = peek(AdminState.eggZone), where = peek(AdminState.dropWhere) })
					end,
				}),
				button(scope, {
					Name = "DropAll",
					LayoutOrder = 2,
					Text = "Drop every egg",
					OnClick = function()
						run("DropZoneEggs", { zone = peek(AdminState.eggZone), where = peek(AdminState.dropWhere) })
					end,
				}),
				button(scope, {
					Name = "ClearRunway",
					LayoutOrder = 3,
					Text = "Clear the runway",
					OnClick = function()
						run("ClearRunway")
					end,
				}),
			}),
		}),
	}
end

local function petsTab(scope, run: Run)
	return {
		section(scope, "Zone", "Zone", 1, { zonePicker(scope, 1, AdminState.petZone) }),
		section(scope, "PetList", "Pets: spawn next to you, or give to your inventory", 2, {
			scope:Computed(function(use, inner)
				local zone = Zones.List[use(AdminState.petZone)]
				local rows = {}
				for index, entry in zone.eggs do
					local about = PetModels.describe(entry.pet)
					local buttons = {
						{
							text = "Give",
							onClick = function()
								run("GivePet", { pet = entry.pet })
							end,
						},
					}
					if about then
						table.insert(buttons, 1, {
							text = "Spawn",
							onClick = function()
								run("SpawnPet", { pet = entry.pet })
							end,
						})
					end
					table.insert(
						rows,
						itemRow(inner, {
							name = entry.pet,
							order = index,
							title = if about then about.name else `{entry.pet} (no model yet)`,
							rarity = entry.rarity,
							buttons = buttons,
						})
					)
				end
				return rows
			end),
		}),
		section(scope, "PetActions", "Pets in the world", 3, {
			grid(scope, "Buttons", 1, 2, {
				button(scope, {
					Name = "ShowZone",
					LayoutOrder = 1,
					Text = "Show this zone's pets",
					OnClick = function()
						run("ShowZonePets", { zone = peek(AdminState.petZone) })
					end,
				}),
				button(scope, {
					Name = "ClearPets",
					LayoutOrder = 2,
					Text = "Remove spawned pets",
					OnClick = function()
						run("ClearPets")
					end,
				}),
			}),
		}),
	}
end

local function speedOptions(speeds: { number }): { { text: string, value: number } }
	local options = {}
	for _, speed in speeds do
		table.insert(options, { text = tostring(speed), value = speed })
	end
	return options
end

local function meTab(scope, run: Run)
	local inventoryLines = scope:Computed(function(use, inner)
		local inventory = use(AdminState.inventory)
		if inventory == nil then
			return { label(inner, { Name = "Loading", LayoutOrder = 1, Text = "Loading...", Color = MUTED }) }
		end
		local lines = {
			label(inner, {
				Name = "Summary",
				LayoutOrder = 1,
				Text = `{inventory.eggCount} egg{if inventory.eggCount == 1 then "" else "s"}, {inventory.petCount} pet{if inventory.petCount
						== 1
					then ""
					else "s"}`,
			}),
		}
		local all = {}
		for _, line in inventory.eggs do
			table.insert(all, line)
		end
		for _, line in inventory.pets do
			table.insert(all, line)
		end
		for index, line in all do
			if index > MAX_INVENTORY_LINES then
				table.insert(
					lines,
					label(inner, {
						Name = "More",
						LayoutOrder = index + 1,
						Text = `... and {#all - MAX_INVENTORY_LINES} more kinds`,
						Color = MUTED,
					})
				)
				break
			end
			local info = Rarities.Info[line.rarity]
			table.insert(
				lines,
				label(inner, {
					Name = "Line" .. index,
					LayoutOrder = index + 1,
					Text = `{line.name}  x{line.count}`,
					Color = if info then rgb(info.color) else WHITE,
					Font = Enum.Font.Gotham,
				})
			)
		end
		return lines
	end)

	return {
		section(scope, "Flight", "Flight", 1, {
			button(scope, {
				Name = "FlyToggle",
				LayoutOrder = 1,
				Text = scope:Computed(function(use)
					return if use(AdminState.flying) then "Flying: tap to land" else "Fly"
				end),
				Color = scope:Computed(function(use)
					return if use(AdminState.flying) then FLYING_GREEN else BUTTON
				end),
				OnClick = function()
					run("SetFlying", { on = not peek(AdminState.flying) })
				end,
			}),
			label(scope, {
				Name = "Help",
				LayoutOrder = 2,
				Text = "Move to fly where the camera looks. Space or E to rise, Q or Ctrl to sink.",
				Color = MUTED,
				TextSize = 12,
				Font = Enum.Font.Gotham,
			}),
			choices(scope, "FlySpeed", 3, speedOptions(AdminTools.FLY_SPEEDS), AdminState.flySpeed, function(speed)
				run("SetFlySpeed", { speed = speed })
			end),
		}),
		section(scope, "Walking", "Walk speed", 2, {
			choices(scope, "WalkSpeed", 1, speedOptions(AdminTools.WALK_SPEEDS), AdminState.walkSpeed, function(speed)
				run("SetWalkSpeed", { speed = speed })
			end),
		}),
		section(scope, "Stamina", "Stamina", 3, {
			grid(scope, "Buttons", 1, 4, {
				button(scope, {
					Name = "Times5",
					LayoutOrder = 1,
					Text = "Max x5",
					OnClick = function()
						run("Stamina", { action = "Times5" })
					end,
				}),
				button(scope, {
					Name = "Max",
					LayoutOrder = 2,
					Text = `{NumberFormat.abbreviate(AdminTools.MAX_STAMINA)}`,
					OnClick = function()
						run("Stamina", { action = "Max" })
					end,
				}),
				button(scope, {
					Name = "Refill",
					LayoutOrder = 3,
					Text = "Refill",
					OnClick = function()
						run("Stamina", { action = "Refill" })
					end,
				}),
				button(scope, {
					Name = "Reset",
					LayoutOrder = 4,
					Text = "Reset",
					OnClick = function()
						run("Stamina", { action = "Reset" })
					end,
				}),
			}),
		}),
		section(scope, "Inventory", "Your inventory", 4, {
			scope:New("Frame")({
				Name = "Lines",
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				[Children] = { column(scope, 2), inventoryLines },
			}),
			grid(scope, "Buttons", 2, 3, {
				button(scope, {
					Name = "Refresh",
					LayoutOrder = 1,
					Text = "Refresh",
					OnClick = function()
						run("GetInventory")
					end,
				}),
				button(scope, {
					Name = "ClearEggs",
					LayoutOrder = 2,
					Text = "Clear eggs",
					OnClick = function()
						run("ClearInventory", { what = "Eggs" })
					end,
				}),
				button(scope, {
					Name = "ClearPets",
					LayoutOrder = 3,
					Text = "Clear pets",
					OnClick = function()
						run("ClearInventory", { what = "Pets" })
					end,
				}),
			}),
		}),
	}
end

local function eventsTab(scope, run: Run)
	return {
		section(scope, "Runway", "Runway cycle", 1, {
			label(scope, {
				Name = "Status",
				LayoutOrder = 1,
				Text = scope:Computed(function(use)
					local clock = NumberFormat.clock(use(UiState.cycleSeconds))
					local phase = use(UiState.cyclePhase)
					if phase == "Closed" then
						return `Closed: opens again in {clock}`
					end
					return `Open: closes in {clock}`
				end),
			}),
			grid(scope, "Buttons", 2, 2, {
				button(scope, {
					Name = "CloseRunway",
					LayoutOrder = 1,
					Text = "Close the runway now",
					OnClick = function()
						run("CloseRunway")
					end,
				}),
				button(scope, {
					Name = "OpenRunway",
					LayoutOrder = 2,
					Text = "Open the runway now",
					OnClick = function()
						run("OpenRunway")
					end,
				}),
			}),
		}),
		section(scope, "Events", "Server events", 2, {
			label(scope, {
				Name = "Status",
				LayoutOrder = 1,
				Text = scope:Computed(function(use)
					local event = use(AdminState.event)
					if event == nil then
						return "No event running."
					end
					return `Running: {CycleClock.EVENT_NAMES[event] or event}, until the runway closes`
				end),
			}),
			grid(scope, "Buttons", 2, 2, {
				button(scope, {
					Name = "StartAvalanche",
					LayoutOrder = 1,
					Text = "Start an Egg Avalanche",
					OnClick = function()
						run("StartEvent", { event = "Avalanche" })
					end,
				}),
				button(scope, {
					Name = "StopEvent",
					LayoutOrder = 2,
					Text = "Stop the event",
					OnClick = function()
						run("StopEvent")
					end,
				}),
			}),
			label(scope, {
				Name = "Note",
				LayoutOrder = 3,
				Text = "Egg Avalanche: twice the eggs in every zone. The Titan Egg event is not built yet.",
				Color = MUTED,
				TextSize = 12,
				Font = Enum.Font.Gotham,
			}),
		}),
	}
end

local function teleportTab(scope, run: Run)
	local places = {
		{ name = "Hub", text = "Hub" },
		{ name = "Showroom", text = "Model Showroom" },
		{ name = "Cliff", text = "End cliff" },
	}
	local placeButtons = {}
	for index, place in places do
		table.insert(
			placeButtons,
			button(scope, {
				Name = place.name,
				LayoutOrder = index,
				Text = place.text,
				OnClick = function()
					run("Teleport", { to = place.name })
				end,
			})
		)
	end
	local zoneButtons = {}
	for _, zone in Zones.List do
		table.insert(
			zoneButtons,
			button(scope, {
				Name = zone.key,
				LayoutOrder = zone.id,
				Text = zone.name,
				Color = rgb(zone.accent),
				Stroke = true,
				OnClick = function()
					run("Teleport", { to = "Zone", zone = zone.id })
				end,
			})
		)
	end

	return {
		section(scope, "Places", "Places", 1, { grid(scope, "Buttons", 1, 3, placeButtons) }),
		section(scope, "Zones", "Zones (the start of each)", 2, { grid(scope, "Buttons", 1, 3, zoneButtons) }),
		section(scope, "Players", "Players", 3, {
			scope:Computed(function(use, inner)
				local players = use(AdminState.players)
				if #players == 0 then
					return {
						label(
							inner,
							{ Name = "Nobody", LayoutOrder = 1, Text = "No one else is here.", Color = MUTED }
						),
					}
				end
				local rows = {}
				for index, other in players do
					table.insert(
						rows,
						inner:New("Frame")({
							Name = other.name,
							LayoutOrder = index,
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 30),
							[Children] = {
								label(inner, {
									Name = "Name",
									Size = UDim2.new(1, -90, 1, 0),
									Text = other.name,
								}),
								button(inner, {
									Name = "GoTo",
									AnchorPoint = Vector2.new(1, 0),
									Position = UDim2.fromScale(1, 0),
									Size = UDim2.new(0, 84, 1, 0),
									Text = "Go to",
									OnClick = function()
										run("TeleportToPlayer", { userId = other.userId })
									end,
								}),
							},
						})
					)
				end
				return rows
			end),
		}),
	}
end

local TAB_BUILDERS = {
	Eggs = eggsTab,
	Pets = petsTab,
	Me = meTab,
	Events = eventsTab,
	Teleport = teleportTab,
}

----------------------------------------------------------------------------------------------------------------

function AdminPanel.mount(playerGui: Instance, run: Run)
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

	local function openTab(name: string)
		AdminState.tab:set(name)
		if name == "Me" then
			run("GetInventory")
		end
	end

	local tabButtons = {}
	for index, name in TABS do
		table.insert(
			tabButtons,
			button(scope, {
				Name = name,
				LayoutOrder = index,
				Size = UDim2.new(1 / #TABS, -5, 1, 0),
				Text = name,
				Color = scope:Computed(function(use)
					return if use(AdminState.tab) == name then ADMIN_RED else BUTTON
				end),
				OnClick = function()
					openTab(name)
				end,
			})
		)
	end

	return scope:New("ScreenGui")({
		Name = "AdminPanel",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = AdminState.isAdmin,
		Parent = playerGui,
		[Children] = {
			scope:New("Frame")({
				Name = "Root",
				BackgroundTransparency = 1,
				Size = scope:Computed(function(use)
					return UDim2.fromScale(1 / use(uiScale), 1 / use(uiScale))
				end),
				[Children] = {
					scope:New("UIScale")({ Scale = uiScale }),

					button(scope, {
						Name = "Toggle",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -10, 0, 8),
						Size = UDim2.fromOffset(92, 36),
						Color = ADMIN_RED,
						Text = "ADMIN",
						TextSize = 16,
						OnClick = function()
							local open = not peek(AdminState.open)
							AdminState.open:set(open)
							if open and peek(AdminState.tab) == "Me" then
								run("GetInventory")
							end
						end,
					}),

					scope:New("Frame")({
						Name = "Window",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -10, 0, 52),
						Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT),
						BackgroundColor3 = PANEL,
						BackgroundTransparency = 0.04,
						Visible = AdminState.open,
						[Children] = {
							corner(scope, 12),
							scope:New("UIStroke")({ Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.5 }),
							label(scope, {
								Name = "Heading",
								Position = UDim2.fromOffset(12, 8),
								Size = UDim2.new(1, -60, 0, 26),
								Text = "Admin panel",
								TextSize = 18,
								Font = Enum.Font.FredokaOne,
							}),
							button(scope, {
								Name = "Close",
								AnchorPoint = Vector2.new(1, 0),
								Position = UDim2.new(1, -8, 0, 8),
								Size = UDim2.fromOffset(28, 26),
								Text = "X",
								OnClick = function()
									AdminState.open:set(false)
								end,
							}),
							scope:New("Frame")({
								Name = "Tabs",
								Position = UDim2.fromOffset(10, 40),
								Size = UDim2.new(1, -20, 0, 30),
								BackgroundTransparency = 1,
								[Children] = {
									scope:New("UIListLayout")({
										FillDirection = Enum.FillDirection.Horizontal,
										Padding = UDim.new(0, 5),
										SortOrder = Enum.SortOrder.LayoutOrder,
									}),
									tabButtons,
								},
							}),
							scope:New("ScrollingFrame")({
								Name = "Body",
								Position = UDim2.fromOffset(10, 78),
								Size = UDim2.new(1, -20, 1, -78 - 44),
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								CanvasSize = UDim2.new(),
								AutomaticCanvasSize = Enum.AutomaticSize.Y,
								ScrollBarThickness = 6,
								ScrollingDirection = Enum.ScrollingDirection.Y,
								[Children] = {
									column(scope, 8),
									scope:New("UIPadding")({ PaddingRight = UDim.new(0, 10) }),
									scope:Computed(function(use, inner)
										return TAB_BUILDERS[use(AdminState.tab)](inner, run)
									end),
								},
							}),
							label(scope, {
								Name = "StatusLine",
								Position = UDim2.new(0, 12, 1, -40),
								Size = UDim2.new(1, -24, 0, 34),
								Text = AdminState.status,
								Color = scope:Computed(function(use)
									return if use(AdminState.statusGood) then GOOD else BAD
								end),
								TextSize = 12,
							}),
						},
					}),
				},
			}),
		},
	})
end

return AdminPanel
