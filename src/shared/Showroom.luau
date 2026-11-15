--!strict
-- The Model Showroom: a floor far from the hub where every pet and egg model stands on display, to look at in the
-- game. Admins get there from the admin panel's Teleport tab; a prompt there takes anyone back to the hub.
--
-- What stands there is set up by the server's ShowroomService: the pet and egg folders imported into the place
-- from tools/export-models, moved here as they are laid out, or models built from the game's own code for any
-- folder that was not imported. Pets stand to the left of an aisle down the middle (-X), eggs to the right (+X),
-- starting at the front edge (Z) and going back (+Z). Pets face -Z, so visitors arrive at the front, facing them.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.

local Runway = require(script.Parent.Runway)

local Showroom = {}

-- The middle of the front edge of the displays: 3,000 studs to the side of the hub, well out of sight of it.
Showroom.X = -3000
Showroom.Z = 0
-- The floor's top: level with the hub.
Showroom.FLOOR_Y = Runway.BASE_Y

-- Studs across the aisle between the pets and the eggs.
Showroom.AISLE = 24
-- Studs of floor beyond the models at the sides and back, and in front of them where visitors arrive.
Showroom.MARGIN = 30
Showroom.ARRIVAL_SPACE = 44
-- The smallest the floor gets (across, deep), so an empty showroom still has room to stand.
Showroom.MIN_WIDTH = 240
Showroom.MIN_DEPTH = 160

-- Anything within this many studs of (X, Z) counts as being in the showroom (the HUD names it).
Showroom.RADIUS = 600

-- The folders tools/export-models writes, which Studio's Import Roblox Model adds to the place.
Showroom.PET_FOLDER = "Roll an Egg Pets"
Showroom.EGG_FOLDER = "Roll an Egg Eggs"

-- Whether a point (x, z) is in the showroom.
function Showroom.contains(x: number, z: number): boolean
	return math.abs(x - Showroom.X) <= Showroom.RADIUS and math.abs(z - Showroom.Z) <= Showroom.RADIUS
end

-- Where a visitor arrives: on the floor in front of the displays, in the middle of the aisle, facing them (+Z).
-- Returns the point (x, y, z) to stand the character's feet on.
function Showroom.arrivalPoint(): (number, number, number)
	return Showroom.X, Showroom.FLOOR_Y, Showroom.Z - Showroom.ARRIVAL_SPACE / 2
end

return Showroom
