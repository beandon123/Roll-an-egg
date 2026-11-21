--!nocheck
-- Builds a web page that shows the game's on-screen UI (the HUD and its panels), so its look can be checked without
-- opening Studio.
--
-- From the repository root:
--     lune run tools/ui-preview [scene]
-- writes tools/out/ui-preview.html. Open it in a browser. Scenes:
--     hud      the HUD on its own, with some dollars, stamina and eggs (the default)
--     trails   the Trails stall's panel open, a few trails owned (trails-end: scrolled to the last trails)
--     sell     the Sell stall's panel open
--     shop     the shop open
--     eggs     the Eggs panel open
--     secret   the shiny lines across the top when Secret and Eternal eggs spawn, a toast below them
--     stick    the training stick's upgrade panel (from the sign beside the stick), the stick at its third tier
--     training rolling on the training stick: its card, a 2x boost running and a "2x" bubble to tap
-- The page draws a 1280 x 720 screen; add #w=844&h=390 to the address for a phone held sideways.
--
-- It runs the game's own client scripts in the Studio stand-in (tests/studio), then turns the HUD's GUI objects into
-- HTML: frames, text, corners, outlines, gradients, list and grid layouts, padding, automatic sizes and scaling, and
-- the models in 3D previews (ViewportFrames) as flat-shaded drawings. It is a close sketch, not Roblox's renderer:
-- fonts are the nearest web fonts, emoji are the browser's, and text sizes are approximate.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Vector2 = roblox.Vector2
local Vector3new = roblox.Vector3.new
local Vector3zero = roblox.Vector3.zero

local Studio = require("../tests/studio")

local scene = process.args[1] or "hud"
local outPath = process.args[2] or "tools/out/ui-preview.html"

local place, reason = Studio.buildPlace()
assert(place, `could not build the place: {reason}`)
local session = Studio.open(place, { isServer = false })
session:createRemotes()
local player = session:addPlayer(7, "Me")
local playerGui = session:setLocalPlayer(player)

session.invokeHandlers.GetSnapshot = function()
	return {
		eggs = {},
		stamina = { value = 380, time = session.clock, rate = 0, max = 600 },
		agility = 14,
		inventory = {
			eggs = {
				{ uid = "a", zone = 1, rarity = "Common", kind = "Leafy", claimedAt = 0 },
				{ uid = "b", zone = 1, rarity = "Rare", kind = "Toadstool", claimedAt = 0 },
				{ uid = "c", zone = 2, rarity = "Epic", kind = "Scarab", claimedAt = 0 },
			},
			hatching = {},
			pets = {},
			penLevel = 1,
			eggCapacity = 2,
			petCapacity = 10,
			dollars = 75400,
			income = 1240,
			mount = "",
		},
		dollars = 75400,
	}
end
session.invokeHandlers.GetShopState = function()
	return { dollars = 75400, penLevel = 1, passes = {}, luck = {} }
end
session.invokeHandlers.GetSettings = function()
	return {}
end
session.invokeHandlers.GetTrails = function()
	return { owned = { "Leaf", "Sunbeam", "Sandstorm" }, equipped = "Sandstorm" }
end

session:run(session:service("StarterPlayer").StarterPlayerScripts.Client)
local UiState = session:require(session:service("StarterPlayer").StarterPlayerScripts.Client.Ui.UiState)
session:fromServer("DollarsChanged", 75400, 1240)
session:fromServer("StaminaChanged", 380, session.clock, 0, 600)
session:fromServer("TrailsUpdated", { "Leaf", "Sunbeam", "Sandstorm" }, "Sandstorm")
if scene == "trails" or scene == "trails-end" then
	UiState.openPanel:set("Trails")
elseif scene == "sell" then
	UiState.openPanel:set("Sell")
elseif scene == "shop" then
	UiState.openPanel:set("Shop")
elseif scene == "eggs" then
	UiState.actions.openPanel("Eggs")
elseif scene == "secret" then
	UiState.showAnnouncement("Secret egg has spawned in Volcano!", 60)
	UiState.showAnnouncement("Eternal egg has spawned in Prehistoric!", 60)
	UiState.showAnnouncement("Secret egg has spawned in Ocean!", 60)
	UiState.showToast("Runway closes in 30s!", roblox.Color3.fromRGB(255, 170, 70), 60)
elseif scene == "stick" then
	session:fromServer("PlayerStateUpdated", { stickLevel = 3 })
	UiState.openPanel:set("Stick")
elseif scene == "training" then
	session:fromServer("PlayerStateUpdated", { stickLevel = 3 })
	session:fromServer("TrainingStarted", { level = 3, plot = 1, startedAt = session.clock })
	for _ = 1, 37 do
		session:fromServer("TrainingRep", 7.5, false)
	end
	session:fromServer("TrainingBoost", session.clock + 60)
end
-- Long enough for the panels' springs to settle.
session:renderFrame(1 / 30, 90)
if scene == "training" then
	-- A bubble that has just finished popping in, up and to the left of the player.
	session:fromServer("TrainingBubble", 1, session.clock + 60)
	session:renderFrame(1 / 30, 30)
	UiState.trainingBubble:set({ id = 1, endsAt = session.clock + 60, x = 0.33, y = 0.36 })
	UiState.bubbleLeft:set(0.7)
	session:renderFrame(1 / 30)
end
if scene == "secret" then
	-- Settled in, with the glint part way across: the lines time themselves by the real clock, so pick the moment.
	local first = UiState.Fusion.peek(UiState.announcements)[1]
	UiState.announceClock:set(first.shownAt + 2 * 1.4 + 0.4)
end
if scene == "trails-end" then
	-- Scrolled along to the fanciest trails.
	playerGui.Hud.Root.Trails.Body.Scroll.CanvasPosition = Vector2.new(1100, 0)
end

----------------------------------------------------------------------------------------------------------------
-- GUI objects to HTML

local FONTS = {
	LuckiestGuy = "'Luckiest Guy', 'Arial Black', sans-serif",
	FredokaOne = "'Fredoka One', 'Fredoka', 'Arial Rounded MT Bold', sans-serif",
	GothamBold = "'Montserrat', 'Arial', sans-serif",
	GothamBlack = "'Montserrat', 'Arial Black', sans-serif",
}

local function css(color, transparency: number?): string
	return string.format(
		"rgba(%d,%d,%d,%.3f)",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255),
		1 - (transparency or 0)
	)
end

-- Plain pixels when there is no Scale part: inside a box whose height comes from its contents, a height such as
-- calc(0% + 70px) counts as auto, not 70px.
local function udim(value): string
	if value.Scale == 0 then
		return string.format("%.2fpx", value.Offset)
	end
	return string.format("calc(%.4f%% + %.2fpx)", value.Scale * 100, value.Offset)
end

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Roblox rich text to HTML: font colours become spans, everything else is left as text.
local function richText(text: string): string
	local out = escape(text)
	out = out:gsub('&lt;font color="(#%x+)"&gt;', '<span style="color:%1">')
	out = out:gsub("&lt;/font&gt;", "</span>")
	out = out:gsub("&lt;b&gt;", "<b>"):gsub("&lt;/b&gt;", "</b>")
	return out
end

local function childOfClass(instance, className: string)
	for _, child in instance:GetChildren() do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

-- A CSS gradient for a UIGradient over `base` (a colour and its transparency): Roblox multiplies the colour by the
-- gradient's colours. The gradient's Offset slides it along.
local function gradientCss(base, baseTransparency: number, gradient): string
	local times = {}
	local seen = {}
	for _, keypoint in gradient.Color.Keypoints do
		if not seen[keypoint.Time] then
			seen[keypoint.Time] = true
			table.insert(times, keypoint.Time)
		end
	end
	for _, keypoint in gradient.Transparency.Keypoints do
		if not seen[keypoint.Time] then
			seen[keypoint.Time] = true
			table.insert(times, keypoint.Time)
		end
	end
	table.sort(times)
	local function sample(keypoints, time, isColor)
		for index = 1, #keypoints - 1 do
			local a, b = keypoints[index], keypoints[index + 1]
			if time >= a.Time and time <= b.Time then
				local t = if b.Time > a.Time then (time - a.Time) / (b.Time - a.Time) else 0
				if isColor then
					return a.Value:Lerp(b.Value, t)
				end
				return a.Value + (b.Value - a.Value) * t
			end
		end
		return keypoints[#keypoints].Value
	end
	local stops = {}
	for _, time in times do
		local color = sample(gradient.Color.Keypoints, time, true)
		local transparency = sample(gradient.Transparency.Keypoints, time, false)
		local mixed = { R = base.R * color.R, G = base.G * color.G, B = base.B * color.B }
		local alpha = 1 - (1 - baseTransparency) * (1 - transparency)
		table.insert(stops, `{css(mixed, alpha)} {string.format("%.2f", (time + gradient.Offset.X) * 100)}%`)
	end
	return `linear-gradient({gradient.Rotation + 90}deg, {table.concat(stops, ", ")})`
end

local function textShadow(stroke): string
	local color = css(stroke.Color, stroke.Transparency)
	local t = stroke.Thickness
	local parts = {}
	for step = 0, 15 do
		local angle = step / 16 * math.pi * 2
		table.insert(parts, string.format("%.2fpx %.2fpx 0 %s", math.cos(angle) * t, math.sin(angle) * t, color))
	end
	return table.concat(parts, ", ")
end

-- A ViewportFrame's models, drawn from its camera as an SVG of flat-shaded faces, furthest first. Blocks are boxes;
-- cylinders and balls are twelve-sided prisms.
local SIDES = 12
local function viewportSvg(viewport): string
	-- (Lune cannot read CurrentCamera back; the previews keep their camera inside them.)
	local camera = viewport:FindFirstChildOfClass("Camera")
	if camera == nil then
		return ""
	end
	local width = if viewport.Size.X.Scale == 0 then viewport.Size.X.Offset else 68
	local height = viewport.Size.Y.Offset
	if width <= 0 or height <= 0 then
		return ""
	end
	local view = camera.CFrame
	local eye = view.Position
	local tanHalf = math.tan(math.rad(camera.FieldOfView) / 2)
	local light = viewport.LightDirection.Unit
	local tint = viewport.ImageColor3
	local faces = {}
	local function project(point)
		local p = view:PointToObjectSpace(point)
		local depth = -p.Z
		if depth <= 0.05 then
			return nil, depth
		end
		local x = p.X / (depth * tanHalf * width / height)
		local y = p.Y / (depth * tanHalf)
		return string.format("%.1f,%.1f", (x * 0.5 + 0.5) * width, (-y * 0.5 + 0.5) * height), depth
	end
	local function addFace(part, corners)
		local a, b, c = corners[1], corners[2], corners[3]
		local normal = (b - a):Cross(c - a)
		if normal.Magnitude < 1e-6 then
			return
		end
		normal = normal.Unit
		local middle = Vector3zero
		for _, corner in corners do
			middle += corner
		end
		middle /= #corners
		if normal:Dot(middle - eye) >= 0 then
			return
		end
		local points, depth = {}, 0
		for _, corner in corners do
			local point, d = project(corner)
			if point == nil then
				return
			end
			table.insert(points, point)
			depth += d
		end
		local shade = if part.Material.Name == "Neon" then 1 else 0.55 + 0.5 * math.max(0, -normal:Dot(light))
		local color = part.Color
		table.insert(faces, {
			depth = depth / #corners,
			svg = string.format(
				'<polygon points="%s" fill="rgb(%d,%d,%d)" fill-opacity="%.2f"/>',
				table.concat(points, " "),
				math.min(255, math.round(color.R * tint.R * shade * 255)),
				math.min(255, math.round(color.G * tint.G * shade * 255)),
				math.min(255, math.round(color.B * tint.B * shade * 255)),
				1 - part.Transparency * 0.6
			),
		})
	end
	for _, part in viewport:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local frame, size = part.CFrame, part.Size
			local shape = if part:IsA("Part") then part.Shape.Name else "Block"
			if shape == "Block" then
				local h = size / 2
				local function corner(x, y, z)
					return frame * Vector3new(x * h.X, y * h.Y, z * h.Z)
				end
				for _, face in
					{
						{ { 1, -1, -1 }, { 1, 1, -1 }, { 1, 1, 1 }, { 1, -1, 1 } },
						{ { -1, -1, 1 }, { -1, 1, 1 }, { -1, 1, -1 }, { -1, -1, -1 } },
						{ { -1, 1, -1 }, { -1, 1, 1 }, { 1, 1, 1 }, { 1, 1, -1 } },
						{ { -1, -1, 1 }, { -1, -1, -1 }, { 1, -1, -1 }, { 1, -1, 1 } },
						{ { -1, -1, 1 }, { 1, -1, 1 }, { 1, 1, 1 }, { -1, 1, 1 } },
						{ { 1, -1, -1 }, { -1, -1, -1 }, { -1, 1, -1 }, { 1, 1, -1 } },
					}
				do
					local corners = {}
					for _, c in face do
						table.insert(corners, corner(c[1], c[2], c[3]))
					end
					addFace(part, corners)
				end
			else
				-- Along the part's X axis; a ball is as long as it is wide.
				local radius = math.min(size.Y, size.Z) / 2
				local half = if shape == "Ball" then radius else size.X / 2
				local function ring(x)
					local points = {}
					for step = 0, SIDES - 1 do
						local angle = step / SIDES * math.pi * 2
						table.insert(points, frame * Vector3new(x, math.cos(angle) * radius, math.sin(angle) * radius))
					end
					return points
				end
				local near, far = ring(half), ring(-half)
				for step = 1, SIDES do
					local nextStep = step % SIDES + 1
					addFace(part, { near[step], far[step], far[nextStep], near[nextStep] })
				end
				addFace(part, near)
				local reversed = {}
				for index = SIDES, 1, -1 do
					table.insert(reversed, far[index])
				end
				addFace(part, reversed)
			end
		end
	end
	table.sort(faces, function(a, b)
		return a.depth > b.depth
	end)
	local svg = {}
	for _, face in faces do
		table.insert(svg, face.svg)
	end
	return string.format(
		'<svg viewBox="0 0 %d %d" preserveAspectRatio="xMidYMid meet" '
			.. 'style="position:absolute;inset:0;width:100%%;height:100%%;pointer-events:none">%s</svg>',
		width,
		height,
		table.concat(svg)
	)
end

local ALIGN_X = { Left = "flex-start", Center = "center", Right = "flex-end" }
local ALIGN_Y = { Top = "flex-start", Center = "center", Bottom = "flex-end" }

local render

-- The children of a GUI object, inside a box inset by its UIPadding and laid out by its UIListLayout or
-- UIGridLayout. `inFlow` is for an object sized by its children (AutomaticSize): their box then takes up room in it.
local function renderChildren(object, inFlow: boolean?): string
	local html = {}
	local list = childOfClass(object, "UIListLayout")
	local grid = childOfClass(object, "UIGridLayout")
	local padding = childOfClass(object, "UIPadding")
	local children = {}
	for index, child in object:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(children, { child = child, index = index })
		end
	end
	if #children == 0 then
		return ""
	end
	if list or grid then
		table.sort(children, function(a, b)
			if a.child.LayoutOrder ~= b.child.LayoutOrder then
				return a.child.LayoutOrder < b.child.LayoutOrder
			end
			return a.index < b.index
		end)
	end
	local layout = if list then "list" elseif grid then "grid" else nil
	for _, entry in children do
		table.insert(html, render(entry.child, layout))
	end
	local style = {}
	if inFlow then
		-- In the flow, so the object grows to fit. The padding becomes margins rather than CSS padding, so children
		-- placed by Position still measure from inside it, as they do in the inset box below.
		table.insert(style, "position:relative")
		if padding then
			local sides = { padding.PaddingTop, padding.PaddingRight, padding.PaddingBottom, padding.PaddingLeft }
			for index, side in sides do
				sides[index] = udim(side)
			end
			table.insert(style, `margin:{table.concat(sides, " ")}`)
		end
	else
		table.insert(style, "position:absolute")
		if padding then
			table.insert(style, `top:{udim(padding.PaddingTop)}`)
			table.insert(style, `bottom:{udim(padding.PaddingBottom)}`)
			table.insert(style, `left:{udim(padding.PaddingLeft)}`)
			table.insert(style, `right:{udim(padding.PaddingRight)}`)
		else
			table.insert(style, "inset:0")
		end
	end
	if list then
		local row = list.FillDirection.Name == "Horizontal"
		table.insert(style, `display:flex;flex-direction:{if row then "row" else "column"}`)
		table.insert(style, `gap:{udim(list.Padding)}`)
		local x, y = ALIGN_X[list.HorizontalAlignment.Name], ALIGN_Y[list.VerticalAlignment.Name]
		table.insert(style, `justify-content:{if row then x else y};align-items:{if row then y else x}`)
	elseif grid then
		-- Cells of CellSize, CellPadding apart, filling a line before starting the next. auto-fit fits as many cells
		-- on a line as there is room for and drops the unused ones, so the alignment centres the cells there are,
		-- as Roblox does. StartCorner is always drawn as TopLeft.
		local cell, gap = grid.CellSize, grid.CellPadding
		local maxCells = grid.FillDirectionMaxCells
		local count = if maxCells > 0 then tostring(math.min(maxCells, #children)) else "auto-fit"
		table.insert(style, `display:grid;gap:{udim(gap.Y)} {udim(gap.X)}`)
		if grid.FillDirection.Name == "Vertical" then
			table.insert(style, `grid-auto-flow:column;grid-template-rows:repeat({count}, {udim(cell.Y)})`)
			table.insert(style, `grid-auto-columns:{udim(cell.X)}`)
		else
			table.insert(style, `grid-template-columns:repeat({count}, {udim(cell.X)})`)
			table.insert(style, `grid-auto-rows:{udim(cell.Y)}`)
		end
		local x, y = ALIGN_X[grid.HorizontalAlignment.Name], ALIGN_Y[grid.VerticalAlignment.Name]
		table.insert(style, `justify-content:{x};align-content:{y}`)
	end
	if object:IsA("ScrollingFrame") then
		local scroll = object.CanvasPosition
		table.insert(style, `transform:translate({-scroll.X}px, {-scroll.Y}px)`)
	end
	return `<div class="content" style="{table.concat(style, ";")}">{table.concat(html)}</div>`
end

-- `layout` is "list" or "grid" when the object's parent has a UIListLayout or UIGridLayout, which places it instead
-- of its Position (and, for a grid, sizes it instead of its Size).
function render(object, layout: string?): string
	if not object.Visible then
		return ""
	end
	local style = {}
	local size = object.Size
	local automatic = if layout == "grid" then "None" else object.AutomaticSize.Name
	local autoX = automatic == "X" or automatic == "XY"
	local autoY = automatic == "Y" or automatic == "XY"
	local width = if layout == "grid" then "100%" elseif autoX then "max-content" else udim(size.X)
	local height = if layout == "grid" then "100%" elseif autoY then "max-content" else udim(size.Y)
	local constraint = childOfClass(object, "UISizeConstraint")
	if constraint then
		if constraint.MaxSize.X < 1e9 then
			table.insert(style, `max-width:{constraint.MaxSize.X}px`)
		end
		if constraint.MaxSize.Y < 1e9 then
			table.insert(style, `max-height:{constraint.MaxSize.Y}px`)
		end
	end
	table.insert(style, `width:{width};height:{height}`)
	-- An automatic size grows from Size, never shrinks below it.
	if autoX then
		table.insert(style, `min-width:{udim(size.X)}`)
	end
	if autoY then
		table.insert(style, `min-height:{udim(size.Y)}`)
	end
	local transforms = {}
	if layout == "list" then
		table.insert(style, "position:relative;flex-shrink:0")
	elseif layout == "grid" then
		table.insert(style, "position:relative")
	else
		table.insert(style, "position:absolute")
		table.insert(style, `left:{udim(object.Position.X)};top:{udim(object.Position.Y)}`)
		local anchor = object.AnchorPoint
		if anchor.X ~= 0 or anchor.Y ~= 0 then
			table.insert(transforms, `translate({-anchor.X * 100}%, {-anchor.Y * 100}%)`)
		end
	end
	if object.Rotation ~= 0 then
		table.insert(transforms, `rotate({object.Rotation}deg)`)
	end
	local scale = childOfClass(object, "UIScale")
	if scale and scale.Scale ~= 1 then
		table.insert(transforms, `scale({scale.Scale})`)
		table.insert(style, `transform-origin:{object.AnchorPoint.X * 100}% {object.AnchorPoint.Y * 100}%`)
	end
	if #transforms > 0 then
		table.insert(style, `transform:{table.concat(transforms, " ")}`)
	end
	table.insert(style, `z-index:{object.ZIndex}`)

	local gradient = childOfClass(object, "UIGradient")
	local isText = object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")
	if object.BackgroundTransparency < 1 then
		if gradient and not isText then
			table.insert(
				style,
				`background:{gradientCss(object.BackgroundColor3, object.BackgroundTransparency, gradient)}`
			)
		else
			table.insert(style, `background:{css(object.BackgroundColor3, object.BackgroundTransparency)}`)
		end
	end
	local corner = childOfClass(object, "UICorner")
	if corner then
		local radius = corner.CornerRadius
		if radius.Scale >= 0.5 then
			table.insert(style, "border-radius:9999px")
		else
			table.insert(style, `border-radius:calc({radius.Scale * 100}% + {radius.Offset}px)`)
		end
	end
	if object.ClipsDescendants or object:IsA("ScrollingFrame") then
		table.insert(style, "overflow:hidden")
	end

	local stroke = childOfClass(object, "UIStroke")
	local textHtml = ""
	if isText and object.Text ~= "" then
		local font = FONTS[object.Font.Name] or "sans-serif"
		local textStyle = { `font-family:{font}`, `color:{css(object.TextColor3, object.TextTransparency)}` }
		local sizeLimit = childOfClass(object, "UITextSizeConstraint")
		if object.TextScaled then
			local length = math.max(1, utf8.len((object.Text:gsub("<[^>]+>", ""))) or 1)
			local limit = if sizeLimit then sizeLimit.MaxTextSize else 100
			table.insert(textStyle, `font-size:min(82cqh, calc(170cqw / {length}), {limit}px)`)
			table.insert(style, "container-type:size")
		else
			table.insert(textStyle, `font-size:{object.TextSize}px`)
		end
		if stroke and stroke.ApplyStrokeMode.Name ~= "Border" then
			table.insert(textStyle, `text-shadow:{textShadow(stroke)}`)
		end
		table.insert(
			textStyle,
			`justify-content:{ALIGN_X[object.TextXAlignment.Name]};align-items:{ALIGN_Y[object.TextYAlignment.Name]}`
		)
		table.insert(textStyle, `text-align:{string.lower(object.TextXAlignment.Name)}`)
		if not object.TextWrapped then
			table.insert(textStyle, "white-space:nowrap")
		end
		local body = if object.RichText then richText(object.Text) else escape(object.Text)
		-- Text that sizes its label (AutomaticSize) has to take up room, not float over it.
		local class = if automatic == "None" then "text" else "text grow"
		textHtml = `<div class="{class}" style="{table.concat(textStyle, ";")}"><span>{body}</span></div>`
		-- A gradient on text colours the letters: drawn as a second copy over the outlined one, clipped to the letters.
		if gradient then
			local fill = gradientCss(object.TextColor3, object.TextTransparency, gradient)
			local overlay = {}
			for _, rule in textStyle do
				if not string.match(rule, "^text%-shadow:") and not string.match(rule, "^color:") then
					table.insert(overlay, rule)
				end
			end
			table.insert(overlay, "color:transparent")
			local clip = `background:{fill};-webkit-background-clip:text;background-clip:text;display:inline-block`
			textHtml ..= `<div class="text" style="{table.concat(overlay, ";")}"><span style="{clip}">{body}</span></div>`
		end
	end
	if stroke and (not isText or stroke.ApplyStrokeMode.Name == "Border") then
		table.insert(style, `box-shadow:0 0 0 {stroke.Thickness}px {css(stroke.Color, stroke.Transparency)}`)
	end

	-- A frame sized by its children has them in its flow. (Text that sizes its label is already in the flow above.)
	local children = renderChildren(object, (autoX or autoY) and not isText)
	local drawing = if object:IsA("ViewportFrame") then viewportSvg(object) else ""
	return `<div data-name="{escape(object.Name)}" style="{table.concat(style, ";")}">{drawing}{textHtml}{children}</div>`
end

local hud = playerGui:FindFirstChild("Hud")
assert(hud, "the HUD did not mount")
local body = renderChildren(hud)

local page = [[<!doctype html>
<html><head><meta charset="utf-8"><title>UI preview</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fredoka+One&family=Luckiest+Guy&family=Montserrat:wght@700;900&display=swap">
<style>
html, body { margin: 0; background: #222; font-family: sans-serif; }
#screen { position: relative; overflow: hidden; background: linear-gradient(#8fc4ef, #cfe8f7 55%, #6db35a 55%, #4f9a45); }
.text { position: absolute; inset: 0; display: flex; line-height: 1; pointer-events: none; }
.text > span { display: block; }
.text.grow { position: relative; height: 100%; }
#note { color: #ccc; padding: 8px 12px; font: 13px sans-serif; }
</style></head><body>
<div id="note">UI preview: SCENE. A sketch of the Roblox UI drawn in HTML, not the game's own renderer.</div>
<div id="screen">BODY</div>
<script>
const params = new URLSearchParams(location.hash.slice(1));
const w = Number(params.get("w") || 1280), h = Number(params.get("h") || 720);
const screen = document.getElementById("screen");
screen.style.width = w + "px"; screen.style.height = h + "px";
// The HUD is laid out for a 720-pixel-tall screen and scaled to fit (see Ui/Hud); match that here.
const scale = Math.min(Math.max(h / 720, 0.6), 1.4);
const root = screen.querySelector('[data-name="Root"]');
if (root) { root.style.width = (100 / scale) + "%"; root.style.height = (100 / scale) + "%"; root.style.transform = "scale(" + scale + ")"; root.style.transformOrigin = "0 0"; }
</script>
</body></html>]]
page = page:gsub("SCENE", scene)
page = page:gsub("BODY", function()
	return body
end)

local folder = string.match(outPath, "^(.*)/[^/]+$")
if folder and not fs.isDir(folder) then
	fs.writeDir(folder)
end
fs.writeFile(outPath, page)
print(`Wrote the {scene} scene to {outPath}`)
