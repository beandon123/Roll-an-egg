--!nocheck
-- Checks the hub layout (Shared/HubLayout): the stations fit in the plaza without overlapping each other, the
-- spawn, the start zone or the players' plots (Shared/Plots), and the terraced cliffs ring the hub without spilling
-- onto the plots, the stations or the runway.

return function(harness)
	local describe, it, expect = harness.describe, harness.it, harness.expect

	local HubLayout = harness.load("src/shared/HubLayout")
	local Plots = harness.load("src/shared/Plots")
	local Runway = harness.load("src/shared/Runway")

	-- The painted start zone at the front of the hub, and the spawn pad in the middle of the plaza.
	local START_ZONE = { x = 0, z = -15, sizeX = Runway.START_WIDTH + 4, sizeZ = 30 }
	local SPAWN = { x = 0, z = -Runway.HUB_LENGTH / 2 }

	-- Each player's plot, as big as it gets.
	local function plotRects()
		local rects = {}
		for index = 1, Plots.COUNT do
			local x, z, sizeX, sizeZ = Plots.rect(index)
			table.insert(rects, { x = x, z = z, sizeX = sizeX, sizeZ = sizeZ })
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

	describe("Hub cliffs", function()
		local terraces = HubLayout.TERRACES
		local tiers = HubLayout.TERRACE_TIERS

		local function corners(rect)
			local minX, maxX, minZ, maxZ = HubLayout.bounds(rect)
			return { { x = minX, z = minZ }, { x = maxX, z = minZ }, { x = maxX, z = maxZ }, { x = minX, z = maxZ } }
		end

		-- Whether two convex outlines overlap (more than `slack` studs), by looking for a line that separates them.
		local function overlap(a, b, slack)
			for _, shape in { a, b } do
				for index = 1, #shape do
					local p, q = shape[index], shape[index % #shape + 1]
					local nx, nz = q.z - p.z, p.x - q.x
					local length = math.sqrt(nx * nx + nz * nz)
					nx, nz = nx / length, nz / length
					local function span(points)
						local low, high = math.huge, -math.huge
						for _, point in points do
							local d = point.x * nx + point.z * nz
							low, high = math.min(low, d), math.max(high, d)
						end
						return low, high
					end
					local aLow, aHigh = span(a)
					local bLow, bHigh = span(b)
					if aHigh <= bLow + slack or bHigh <= aLow + slack then
						return false
					end
				end
			end
			return true
		end

		-- How far a point is from a convex outline (0 inside it: on the same side of every edge).
		local function distanceTo(point, shape)
			local left, right = false, false
			local nearest = math.huge
			for index = 1, #shape do
				local p, q = shape[index], shape[index % #shape + 1]
				local ex, ez = q.x - p.x, q.z - p.z
				local cross = ex * (point.z - p.z) - ez * (point.x - p.x)
				if cross > 0 then
					left = true
				elseif cross < 0 then
					right = true
				end
				local t = math.clamp(((point.x - p.x) * ex + (point.z - p.z) * ez) / (ex * ex + ez * ez), 0, 1)
				local dx, dz = point.x - (p.x + ex * t), point.z - (p.z + ez * t)
				nearest = math.min(nearest, math.sqrt(dx * dx + dz * dz))
			end
			return if left and right then nearest else 0
		end

		it("builds the same cliffs every time", function()
			local again = HubLayout.generateTerraces()
			expect.equal(#again, #terraces)
			for index, terrace in terraces do
				expect.equal(again[index].x, terrace.x)
				expect.equal(again[index].height, terrace.height)
				expect.equal(again[index].seed, terrace.seed)
			end
		end)

		it("climbs in tiers, each step further out and higher than the one below it", function()
			expect.equal(#terraces % tiers, 0)
			expect.truthy(#terraces / tiers >= 60, "columns of steps all round: " .. #terraces / tiers)
			local highest = 0
			for start = 1, #terraces, tiers do
				local offset, height = 0, 0
				for tier = 1, tiers do
					local terrace = terraces[start + tier - 1]
					expect.equal(terrace.tier, tier)
					expect.near(terrace.offset, offset, 1e-6, "steps sit side by side")
					expect.truthy(terrace.height >= height + 12, "each step at least 12 studs higher")
					expect.truthy(terrace.depth >= 14 and terrace.length > 0, "a step deep enough to see")
					offset += terrace.depth
					height = terrace.height
				end
				highest = math.max(highest, height)
				expect.truthy(height >= 100, "a high crest")
			end
			expect.truthy(highest >= 130, "the crest rises to " .. highest)
		end)

		it("never spills onto the plots, the stations, the spawn, the start zone or the runway", function()
			local keepOut = {}
			for index, rect in plotRects() do
				table.insert(keepOut, { name = "plot " .. index, outline = corners(rect) })
			end
			for _, thing in plazaThings() do
				table.insert(keepOut, { name = thing.name, outline = corners(thing.rect) })
			end
			for index, rect in HubLayout.CLIFF_KEEP_OUT do
				table.insert(keepOut, { name = "runway " .. index, outline = corners(rect) })
			end
			for index, terrace in terraces do
				local outline = HubLayout.terraceCorners(terrace)
				for _, thing in keepOut do
					expect.falsy(
						overlap(outline, thing.outline, 0),
						`cliff {index} (tier {terrace.tier}) on {thing.name}`
					)
				end
			end
		end)

		it("rings the hub on both sides and at the back, with no gaps", function()
			-- The foot of the cliffs is unbroken: each block of the lowest step touches the next.
			local feet = {}
			for _, terrace in terraces do
				if terrace.tier == 1 then
					table.insert(feet, HubLayout.terraceCorners(terrace))
				end
			end
			for index = 2, #feet do
				expect.truthy(overlap(feet[index - 1], feet[index], -0.5), "gap in the foot of the cliffs at " .. index)
			end

			-- Walk round the hub's sides and back: the cliffs are right there everywhere, except in the back corners,
			-- which they round off. (At the front, beside the runway, the first zone's banks and backdrop rise instead.)
			local half, length = HubLayout.HALF_WIDTH, HubLayout.LENGTH
			local radius = HubLayout.CLIFF_CORNER_RADIUS
			local edge = {}
			for z = 0, -length, -10 do
				table.insert(edge, { x = -half - 1, z = z })
				table.insert(edge, { x = half + 1, z = z })
			end
			for x = -half, half, 10 do
				table.insert(edge, { x = x, z = -length - 1 })
			end
			for _, point in edge do
				local nearest = math.huge
				for _, outline in feet do
					nearest = math.min(nearest, distanceTo(point, outline))
				end
				local inCorner = point.z < -length + radius and math.abs(point.x) > half - radius
				local allowed = if inCorner then radius * (math.sqrt(2) - 1) + 2 else 2
				expect.truthy(nearest < allowed, `gap in the cliffs near ({point.x}, {point.z}): {nearest}`)
			end
		end)

		it("runs the scenery ground under all of the cliffs", function()
			local minX, maxX, minZ, maxZ = HubLayout.bounds(HubLayout.OUTER_GROUND)
			for _, terrace in terraces do
				for _, corner in HubLayout.terraceCorners(terrace) do
					local slack = 0.5
					expect.truthy(corner.x >= minX - slack and corner.x <= maxX + slack, "x " .. corner.x)
					expect.truthy(corner.z >= minZ - slack and corner.z <= maxZ + slack, "z " .. corner.z)
				end
			end
		end)
	end)
end
