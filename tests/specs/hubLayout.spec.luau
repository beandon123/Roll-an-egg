--!nocheck
-- Checks the hub layout (Shared/HubLayout): the stations fit in the plaza without overlapping each other, the
-- spawn, the start zone or the players' plots (Shared/Plots), and the mountains ring the hub without spilling onto
-- it or the runway.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local HubLayout = harness.load("src/shared/HubLayout")
	local Plots = harness.load("src/shared/Plots")
	local Runway = harness.load("src/shared/Runway")

	-- The painted start zone at the front of the hub, and the spawn pad in the middle of the plaza.
	local START_ZONE = { x = 0, z = -15, sizeX = Runway.WIDTH + 4, sizeZ = 30 }
	local SPAWN = { x = 0, z = -Runway.HUB_LENGTH / 2 }

	-- Each player's plot, as big as it gets.
	local function plotRects()
		local rects = {}
		for index = 1, Plots.COUNT do
			local x, z = Plots.center(index)
			table.insert(rects, { x = x, z = z, sizeX = Plots.WIDTH, sizeZ = Plots.DEPTH })
		end
		return rects
	end

	local function circle(x, z, radius)
		return { x = x, z = z, sizeX = radius * 2, sizeZ = radius * 2 }
	end

	-- Everything standing on the plaza, as rectangles.
	local function plazaThings()
		local things = {
			{ name = "start zone", rect = START_ZONE },
			{ name = "spawn", rect = circle(SPAWN.x, SPAWN.z, 8) },
		}
		for key, station in HubLayout.STATIONS do
			table.insert(things, { name = key, rect = circle(station.x, station.z, HubLayout.STATION_RADIUS) })
		end
		return things
	end

	describe("Hub layout", function()
		it("covers the whole hub", function()
			local _, _, minZ, maxZ = HubLayout.bounds(HubLayout.GROUND)
			expect.near(maxZ, 0)
			expect.near(minZ, -Runway.HUB_LENGTH)
			expect.near(HubLayout.GROUND.sizeX, Runway.HUB_WIDTH)
		end)

		it("puts the Trails shop on the left and the Sell stall on the right, seen from the start zone", function()
			-- Looking from the start zone back into the hub (toward -z), left is -x.
			local stations = HubLayout.STATIONS
			expect.truthy(stations.Trails.x < 0, "Trails on the left")
			expect.truthy(stations.Sell.x > 0, "Sell on the right")
			expect.near(stations.Fuse.x, 0)
			-- The fuse machine stands further back than the two stalls, between them.
			expect.truthy(stations.Fuse.z < stations.Trails.z and stations.Fuse.z < stations.Sell.z)
			for key, station in stations do
				expect.near(station.facing.x * station.facing.x + station.facing.z * station.facing.z, 1, 1e-9, key)
				expect.equal(station.key, key)
			end
		end)

		it("keeps the stations, spawn and start zone apart and inside the hub", function()
			local things = plazaThings()
			for index, thing in things do
				local minX, maxX, minZ, maxZ = HubLayout.bounds(thing.rect)
				expect.truthy(minX >= -HubLayout.HALF_WIDTH and maxX <= HubLayout.HALF_WIDTH, thing.name .. " x")
				expect.truthy(minZ >= -HubLayout.LENGTH and maxZ <= 0, thing.name .. " z")
				for other = index + 1, #things do
					expect.falsy(
						HubLayout.rectsOverlap(thing.rect, things[other].rect),
						thing.name .. " overlaps " .. things[other].name
					)
				end
			end
		end)

		it("keeps the stations off every player's plot", function()
			for index, rect in plotRects() do
				for _, thing in plazaThings() do
					expect.falsy(HubLayout.rectsOverlap(rect, thing.rect), `plot {index} overlaps {thing.name}`)
				end
			end
		end)

		it("keeps the walk from the spawn to the start zone clear", function()
			-- A strip down the middle of the plaza, beside the fuse machine.
			local fuse = HubLayout.STATIONS.Fuse
			local path = {
				x = fuse.x + HubLayout.STATION_RADIUS + 6,
				z = SPAWN.z / 2,
				sizeX = 8,
				sizeZ = -SPAWN.z,
			}
			for index, rect in plotRects() do
				expect.falsy(HubLayout.rectsOverlap(path, rect), "plot " .. index)
			end
			for key, station in HubLayout.STATIONS do
				expect.falsy(HubLayout.rectsOverlap(path, circle(station.x, station.z, HubLayout.STATION_RADIUS)), key)
			end
		end)
	end)

	describe("Hub mountains", function()
		local mountains = HubLayout.MOUNTAINS

		it("builds the same ring every time", function()
			local again = HubLayout.generateMountains()
			expect.equal(#again, #mountains)
			for index, mountain in mountains do
				expect.equal(again[index].x, mountain.x)
				expect.equal(again[index].seed, mountain.seed)
			end
			local first = HubLayout.mountainTriangles(mountains[1])
			local second = HubLayout.mountainTriangles(mountains[1])
			expect.equal(first[5].a[1], second[5].a[1])
		end)

		it("has big mountains with smaller hills in front of them", function()
			local big, small = 0, 0
			for _, mountain in mountains do
				if mountain.big then
					big += 1
					expect.truthy(mountain.height >= 140, "big mountain height")
				else
					small += 1
				end
			end
			expect.truthy(big >= 12, "big mountains: " .. big)
			expect.truthy(small >= 10, "hills: " .. small)
		end)

		it("never spills onto the hub or the runway", function()
			for index, mountain in mountains do
				local widest = mountain.groundRadius * (1 + HubLayout.MOUNTAIN_ROUGHNESS)
				for _, rect in HubLayout.MOUNTAIN_KEEP_OUT do
					local room = HubLayout.distanceToRect(mountain.x, mountain.z, rect)
					expect.truthy(room >= widest + HubLayout.MOUNTAIN_CLEARANCE - 1e-6, "mountain " .. index)
				end
			end
		end)

		it("surrounds the hub on both sides and at the back", function()
			-- Walk round the hub's sides and back and make sure a mountain rises close by everywhere. (At the front,
			-- beside the runway, the first zone's banks and backdrop rise instead.)
			local half, length = HubLayout.HALF_WIDTH, HubLayout.LENGTH
			local edge = {}
			for z = 0, -length, -10 do
				table.insert(edge, { -half, z })
				table.insert(edge, { half, z })
			end
			for x = -half, half, 10 do
				table.insert(edge, { x, -length })
			end
			for _, point in edge do
				local nearest = math.huge
				for _, mountain in mountains do
					local dx, dz = mountain.x - point[1], mountain.z - point[2]
					nearest = math.min(nearest, math.sqrt(dx * dx + dz * dz) - mountain.groundRadius)
				end
				expect.truthy(nearest < 40, `gap in the mountains near ({point[1]}, {point[2]}): {nearest}`)
			end
		end)

		it("shapes each mountain from its base up to its peak", function()
			local snowy = 0
			for index, mountain in mountains do
				local triangles = HubLayout.mountainTriangles(mountain)
				local rings = if mountain.big then 5 else 3
				expect.equal(#triangles, rings * mountain.sides, "faces of mountain " .. index)
				local lowest, highest = math.huge, -math.huge
				for _, triangle in triangles do
					for _, point in { triangle.a, triangle.b, triangle.c } do
						for axis = 1, 3 do
							expect.truthy(point[axis] == point[axis] and math.abs(point[axis]) < 1e5, "finite point")
						end
						lowest = math.min(lowest, point[2])
						highest = math.max(highest, point[2])
					end
					expect.truthy(triangle.shade > 0.85 and triangle.shade < 1.1, "shade")
					if triangle.band == "Snow" then
						snowy += 1
						expect.truthy(mountain.big and mountain.height >= 170, "snow only on tall mountains")
					end
				end
				-- The base is buried below the hub's ground, and the peak is the top.
				expect.near(lowest, Runway.BASE_Y - mountain.sink, 1e-6)
				expect.near(highest, Runway.BASE_Y + mountain.height, 1e-6)
			end
			expect.truthy(snowy > 0, "some snowy peaks")
		end)
	end)
end
