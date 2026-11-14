-- Builds the scenery round the hub: the ground beyond its walls and the ring of low-poly mountains from
-- Shared/HubLayout. Pure scenery: nothing collides with the mountains, and gameplay never reads them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local HubLayout = require(Shared.HubLayout)
local Runway = require(Shared.Runway)

local Build = require(script.Parent.Build)

-- RGB 0-255 for each band of a mountain's faces.
local BAND_COLORS: { [HubLayout.Band]: { number } } = {
	Grass = { 86, 162, 78 },
	Hilltop = { 112, 180, 90 },
	Rock = { 132, 128, 142 },
	Snow = { 246, 248, 255 },
}

local Mountains = {}

local function toVector(point: { number }): Vector3
	return Vector3.new(point[1], point[2], point[3])
end

function Mountains.build(map: Instance): Folder
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"

	-- Just below the hub's surface, so the two never flicker where they overlap.
	local outer = HubLayout.OUTER_GROUND
	Build.part(scenery, "OuterGround", {
		Size = Vector3.new(outer.sizeX, 4, outer.sizeZ),
		Position = Vector3.new(outer.x, Runway.BASE_Y - 0.3 - 2, outer.z),
		Color = Color3.fromRGB(88, 160, 76),
	})

	local folder = Instance.new("Folder")
	folder.Name = "Mountains"
	folder.Parent = scenery
	for index, mountain in HubLayout.MOUNTAINS do
		local model = Instance.new("Model")
		model.Name = "Mountain" .. index
		-- Stream each mountain in whole, never part of one.
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		for _, triangle in HubLayout.mountainTriangles(mountain) do
			local color = Build.rgb(BAND_COLORS[triangle.band], triangle.shade)
			Build.triangle(model, toVector(triangle.a), toVector(triangle.b), toVector(triangle.c), color)
		end
		model.Parent = folder
	end

	scenery.Parent = map
	return scenery
end

return Mountains
