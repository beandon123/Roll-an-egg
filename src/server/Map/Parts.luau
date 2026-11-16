-- Small helpers for building the hub's stations and mountains out of plain parts (the zones use Map/Build).

local Parts = {}

-- Faces drawn with `triangle` are wedges this thick.
local TRIANGLE_THICKNESS = 0.4

function Parts.rgb(color: { number }, shade: number?): Color3
	local scale = shade or 1
	return Color3.fromRGB(
		math.clamp(math.floor(color[1] * scale), 0, 255),
		math.clamp(math.floor(color[2] * scale), 0, 255),
		math.clamp(math.floor(color[3] * scale), 0, 255)
	)
end

-- An anchored, smooth part with the given properties. `Shape` is applied before the rest, because it can change
-- the size.
function Parts.part(parent: Instance, name: string, properties: { [string]: any }, className: string?): BasePart
	local part = Instance.new(className or "Part") :: any
	part.Name = name
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	if part:IsA("Part") then
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if properties.Shape then
			part.Shape = properties.Shape
		end
	end
	for key, value in properties do
		if key ~= "Shape" then
			part[key] = value
		end
	end
	part.Parent = parent
	return part
end

-- Makes a part pure scenery: nothing collides with it, touches it, or hits it with a raycast.
function Parts.scenery(part: BasePart): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- A cylinder standing upright (Roblox cylinders lie along their X axis).
function Parts.disc(parent: Instance, name: string, at: CFrame, diameter: number, height: number, color: Color3)
	return Parts.part(parent, name, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = at * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
	})
end

-- Big text on one face of a part. `subtitle` adds a smaller second line.
function Parts.signText(part: BasePart, face: Enum.NormalId, title: string, subtitle: string?, color: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = part

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, if subtitle then 0.62 else 1)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.Text = title
	titleLabel.TextColor3 = color or Color3.new(1, 1, 1)
	titleLabel.TextScaled = true
	titleLabel.TextStrokeTransparency = 0.5
	titleLabel.Parent = gui

	if subtitle then
		local subtitleLabel = Instance.new("TextLabel")
		subtitleLabel.BackgroundTransparency = 1
		subtitleLabel.Position = UDim2.fromScale(0, 0.62)
		subtitleLabel.Size = UDim2.fromScale(1, 0.34)
		subtitleLabel.Font = Enum.Font.GothamBold
		subtitleLabel.Text = subtitle
		subtitleLabel.TextColor3 = Color3.new(1, 1, 1)
		subtitleLabel.TextScaled = true
		subtitleLabel.Parent = gui
	end
	return gui
end

-- A floating name tag over a part, readable from any side: white text on a rounded colored plate.
-- `width` and `height` are in studs.
function Parts.nameTag(part: BasePart, text: string, color: Color3, width: number, height: number, offsetY: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromScale(width, height)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 320
	gui.Parent = part

	local plate = Instance.new("Frame")
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = color
	plate.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.Parent = plate

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.05, 0.08)
	label.Size = UDim2.fromScale(0.9, 0.84)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.3
	label.Parent = plate
	return gui
end

-- A ProximityPrompt that opens a hub station on the player's device (see the client's ShopController).
function Parts.stationPrompt(part: BasePart, stationKey: string, objectText: string, reach: number)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = reach
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Station", stationKey)
	prompt.Parent = part
	return prompt
end

-- A flat triangle between three points, drawn as two wedges (Roblox has no triangle part). The longest edge is
-- split at the foot of the opposite corner's height, making two right-angled triangles; a wedge's side face is
-- exactly such a triangle. Very thin slivers are skipped.
function Parts.triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, color: Color3)
	-- Arrange the corners so that bc is the longest edge.
	local ab, ac, bc = b - a, c - a, c - b
	local abLength, acLength, bcLength = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abLength > acLength and abLength > bcLength then
		a, c = c, a
	elseif acLength > bcLength and acLength > abLength then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b

	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-3 then
		return
	end
	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.05 then
		return
	end

	local function wedge(center: Vector3, length: number, x: Vector3, z: Vector3)
		if length < 0.05 then
			return
		end
		local part = Parts.part(parent, "Face", {
			Size = Vector3.new(TRIANGLE_THICKNESS, height, length),
			CFrame = CFrame.fromMatrix(center, x, up, z),
			Color = color,
		}, "WedgePart")
		Parts.scenery(part)
	end

	wedge((a + b) / 2, math.abs(ab:Dot(back)), right, back)
	wedge((a + c) / 2, math.abs(ac:Dot(back)), -right, -back)
end

return Parts
