-- Builds the runway's placeholder parts: ground, side walls, and the gate at the start of each zone.
--
-- The server builds the zones themselves (MapService). Each player's device builds the endless repeat of the last
-- zone past the end (the client's WorldController), so that stretch is always there however far away it is.
-- Both use these functions, so the two halves join up exactly. Final art will replace all of this.

local Runway = require(script.Parent.Runway)
local NumberFormat = require(script.Parent.NumberFormat)
local Rarities = require(script.Parent.Config.Rarities)
local Zones = require(script.Parent.Config.Zones)

local SLAB_THICKNESS = 4
local SIGN_HEIGHT = 26
-- The longest a single part may be (Roblox's limit is 2048).
local MAX_PART_LENGTH = 2000

local MapParts = {}

MapParts.SLAB_THICKNESS = SLAB_THICKNESS

local angle = math.atan(Runway.SLOPE)
-- Unit vectors along the slope (downhill) and straight out of its surface.
local ALONG = Vector3.new(0, -math.sin(angle), math.cos(angle))
local NORMAL = Vector3.new(0, math.cos(angle), math.sin(angle))

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

function MapParts.newPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

-- A part lying along the slope between fromZ and toZ: `width` across, `height` out of the surface, standing on it
-- (or sunk into it, for negative `lift`), centred at `x`.
local function slopedPart(
	name: string,
	parent: Instance,
	fromZ: number,
	toZ: number,
	x: number,
	width: number,
	height: number,
	lift: number
): Part
	local part = MapParts.newPart(name, parent)
	local middleZ = (fromZ + toZ) / 2
	part.Size = Vector3.new(width, height, (toZ - fromZ) / math.cos(angle))
	local surface = Vector3.new(x, Runway.surfaceY(middleZ), middleZ)
	local center = surface + NORMAL * (lift + height / 2)
	part.CFrame = CFrame.lookAt(center, center + ALONG, NORMAL)
	return part
end

-- The ground of a zone between fromZ and toZ, split into parts no longer than Roblox allows.
function MapParts.ground(parent: Instance, zoneId: number, fromZ: number, toZ: number)
	local color = rgb(Zones.List[zoneId].ground)
	local pieces = math.ceil((toZ - fromZ) / MAX_PART_LENGTH)
	local step = (toZ - fromZ) / pieces
	for index = 1, pieces do
		local a = fromZ + (index - 1) * step
		local slab = slopedPart("Ground", parent, a, a + step, 0, Runway.WIDTH, SLAB_THICKNESS, -SLAB_THICKNESS)
		slab.Color = color
	end
end

-- The side walls between fromZ and toZ (see Runway.wallsBetween), in the colors of the zones they stand in.
function MapParts.walls(parent: Instance, fromZ: number, toZ: number)
	for _, side in { -1, 1 } do
		local x = side * (Runway.WIDTH / 2 + Runway.WALL_THICKNESS / 2)
		for _, segment in Runway.wallsBetween(side, fromZ, toZ) do
			local wall =
				slopedPart("Wall", parent, segment.startZ, segment.endZ, x, Runway.WALL_THICKNESS, segment.height, -1)
			wall.Material = Enum.Material.Slate
			local zoneId = Runway.zoneAt((segment.startZ + segment.endZ) / 2) or 1
			wall.Color = rgb(Zones.List[zoneId].accent)
		end
	end
end

local function addSignText(part: Part, face: Enum.NormalId, title: string, subtitle: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = part

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, 0.62)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.Text = title
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextScaled = true
	titleLabel.Parent = gui

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

-- The lowest and highest stamina requirement of a zone's eggs.
local function staminaRange(zone): (number, number)
	local low, high = math.huge, 0
	for rarity in Rarities.Info do
		local requirement = zone.stamina[rarity]
		if requirement then
			low = math.min(low, requirement)
			high = math.max(high, requirement)
		end
	end
	return low, high
end

-- The gate over the start of a zone: two posts and a sign with its name and the stamina its eggs need. The
-- endless last zone repeats its gate every loop.
function MapParts.gate(parent: Instance, zoneId: number, z: number)
	local zone = Zones.List[zoneId]
	local surface = Runway.surfaceY(z)
	for _, side in { -1, 1 } do
		local post = MapParts.newPart("SignPost", parent)
		post.Size = Vector3.new(3, SIGN_HEIGHT + 8, 3)
		post.CFrame = CFrame.new(side * (Runway.WIDTH / 2 + 3), surface + (SIGN_HEIGHT + 8) / 2 - 4, z)
		post.Color = rgb(zone.accent)
	end

	local sign = MapParts.newPart("Sign", parent)
	sign.Size = Vector3.new(Runway.WIDTH + 9, 9, 1.5)
	sign.CFrame = CFrame.new(0, surface + SIGN_HEIGHT, z)
	sign.Color = rgb(zone.accent)
	local low, high = staminaRange(zone)
	local subtitle = `Eggs need {NumberFormat.abbreviate(low)} - {NumberFormat.abbreviate(high)} stamina`
	-- Front faces players coming from the hub; Back faces the other way.
	addSignText(sign, Enum.NormalId.Front, string.upper(zone.name), subtitle)
	addSignText(sign, Enum.NormalId.Back, string.upper(zone.name), subtitle)
end

return MapParts
