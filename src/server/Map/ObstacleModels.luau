-- Builds each kind of obstacle out of parts, in the same blocky style as the eggs and pets.
--
-- Every builder fills a Model standing on the ground at `base` (a CFrame on the runway surface, facing down the
-- runway), sized to the obstacle's footprint: `hx` across the runway and `hz` along it, half-widths in studs, as in
-- Shared/Obstacles. What a rider can hit stays inside that footprint up to riding height; only things well above
-- the riders (tree canopies) reach past it. The same builders dress the banks beside the runway with scenery.
--
-- Obstacles that go off now and then (sand geysers, lava vents, giant clams) carry the parts the client animates
-- (see the client's ObstacleController):
--     Burst   a column that shoots up while the obstacle is active (hidden otherwise), maybe with a PointLight
--     Warn    a ParticleEmitter that puffs while it warns
--     Lid     the clam's top shell, hinged on the back edge of Shell; open when idle, shut when active

local Build = require(script.Parent.Build)

local block, wedge, ball, column, log = Build.block, Build.wedge, Build.ball, Build.column, Build.log
local shade, vary, between = Build.shade, Build.vary, Build.between

type Random = Build.Random
type Builder = (model: Model, base: CFrame, hx: number, hz: number, random: Random) -> ()

local M = Enum.Material

-- Shared colours.
local BARK = { 108, 76, 50 }
local WOOD_END = { 200, 162, 112 }
local LEAF = { 76, 150, 64 }
local MOSS = { 92, 150, 60 }
local STONE = { 134, 134, 128 }
local BONE = { 236, 226, 202 }
local SAND = { 226, 196, 132 }
local SNOW = { 244, 248, 252 }

local function at(base: CFrame, x: number, y: number, z: number): CFrame
	return base * CFrame.new(x, y, z)
end

-- A small random tilt and turn, for rocks.
local function tumble(random: Random, tilt: number, turn: number): CFrame
	return CFrame.Angles((random() * 2 - 1) * tilt, (random() * 2 - 1) * turn, (random() * 2 - 1) * tilt)
end

local function emitter(parent: BasePart, name: string, color: { number }, options: { [string]: any }): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Name = name .. "Point"
	attachment.Position = options.offset or Vector3.zero
	attachment.Parent = parent
	local particles = Instance.new("ParticleEmitter")
	particles.Name = name
	particles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	particles.Color = ColorSequence.new(Build.color(color))
	particles.LightEmission = options.glow or 0
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, options.size or 1.5),
		NumberSequenceKeypoint.new(1, (options.size or 1.5) * 2.5),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Lifetime = NumberRange.new(options.life or 1, (options.life or 1) * 1.6)
	particles.Rate = options.rate or 12
	particles.Speed = NumberRange.new(options.speed or 4, (options.speed or 4) * 1.6)
	particles.SpreadAngle = Vector2.new(options.spread or 25, options.spread or 25)
	particles.Acceleration = Vector3.new(0, options.lift or 2, 0)
	particles.EmissionDirection = Enum.NormalId.Top
	particles.Enabled = options.enabled ~= false
	particles.Parent = attachment
	return particles
end

local function glow(parent: BasePart, color: { number }, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = Build.color(color)
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
	return light
end

-- A toadstool: a stem and a stepped red cap with white spots.
local function toadstool(model: Model, base: CFrame, size: number, random: Random)
	local stemHeight = size * 1.4
	column(model, size * 0.5, stemHeight, base, { 240, 230, 206 }, { collide = false })
	local cap = vary(random, { 214, 48, 46 }, 0.08)
	block(model, Vector3.new(size * 1.5, size * 0.45, size * 1.5), at(base, 0, stemHeight, 0), cap)
	block(model, Vector3.new(size * 1.05, size * 0.4, size * 1.05), at(base, 0, stemHeight + size * 0.4, 0), cap)
	for index = 1, 4 do
		local angle = index * math.pi / 2 + random()
		block(
			model,
			Vector3.new(size * 0.22, size * 0.12, size * 0.22),
			at(base, math.cos(angle) * size * 0.45, stemHeight + size * 0.62, math.sin(angle) * size * 0.45),
			{ 252, 250, 244 },
			{ collide = false }
		)
	end
end

-- A blocky boulder from three tumbled stones, with something growing on top.
local function boulder(model: Model, base: CFrame, hx: number, hz: number, random: Random, rock, top, topMaterial)
	local height = math.min(hx, hz) * 1.45
	local main = vary(random, rock, 0.06)
	local stones = {
		{ Vector3.new(hx * 1.25, height * 0.8, hz * 1.3), Vector3.new(-hx * 0.08, height * 0.36, 0), 0 },
		{ Vector3.new(hx * 0.95, height * 0.7, hz * 0.95), Vector3.new(hx * 0.32, height * 0.68, -hz * 0.12), 0.08 },
		{ Vector3.new(hx * 0.75, height * 0.55, hz * 0.8), Vector3.new(-hx * 0.5, height * 0.28, hz * 0.38), -0.1 },
		{ Vector3.new(hx * 0.6, height * 0.45, hz * 0.6), Vector3.new(hx * 0.55, height * 0.22, hz * 0.45), -0.04 },
		{ Vector3.new(hx * 0.55, height * 0.4, hz * 0.55), Vector3.new(-hx * 0.2, height * 0.95, hz * 0.1), 0.12 },
	}
	for _, stone in stones do
		block(
			model,
			stone[1],
			at(base, stone[2].X, stone[2].Y, stone[2].Z) * tumble(random, 0.2, 0.6),
			shade(main, stone[3]),
			{ material = M.Slate }
		)
	end
	if top then
		block(
			model,
			Vector3.new(hx * 0.85, 0.5, hz * 0.8),
			at(base, hx * 0.2, height * 1.06, -hz * 0.08) * tumble(random, 0.05, 0.4),
			vary(random, top, 0.06),
			{ material = topMaterial or M.Grass, collide = false }
		)
		block(
			model,
			Vector3.new(hx * 0.5, 0.45, hz * 0.45),
			at(base, -hx * 0.25, height * 1.16, hz * 0.12) * tumble(random, 0.05, 0.4),
			shade(vary(random, top, 0.06), 0.08),
			{ material = topMaterial or M.Grass, collide = false }
		)
	end
	return height
end

-- A tumbleweed-like ball of crossed twigs.
local function twigBall(model: Model, center: CFrame, radius: number, random: Random, color)
	for _ = 1, 20 do
		block(
			model,
			Vector3.new(0.32, 0.32, radius * 2 * between(random, 0.8, 1)),
			center * CFrame.Angles(random() * math.pi, random() * math.pi, random() * math.pi),
			vary(random, color, 0.14),
			{ collide = false }
		)
	end
	ball(model, radius * 1.3, center.Position, shade(color, -0.2), { transparency = 0.35, collide = true })
end

local builders: { [string]: Builder } = {}

----------------------------------------------------------------------------------------------------------------
-- Forest

builders.Log = function(model, base, hx, hz, random)
	local diameter = hz * 2
	local bark = vary(random, BARK, 0.08)
	local center = at(base, 0, diameter / 2, 0)
	log(model, diameter, hx * 2 - 0.5, center, bark, { material = M.Wood })
	for _, side in { -1, 1 } do
		log(model, diameter * 0.86, 0.5, center * CFrame.new(side * (hx - 0.3), 0, 0), WOOD_END, { material = M.Wood })
		log(model, diameter * 0.42, 0.62, center * CFrame.new(side * (hx - 0.28), 0, 0), shade(WOOD_END, -0.18))
	end
	-- Moss along the top, a broken-off branch, and a toadstool.
	block(
		model,
		Vector3.new(hx * 0.9, 0.45, diameter * 0.45),
		at(base, (random() - 0.5) * hx * 0.5, diameter - 0.05, 0),
		vary(random, MOSS, 0.06),
		{ material = M.Grass, collide = false }
	)
	block(
		model,
		Vector3.new(0.7, 2.6, 0.7),
		at(base, hx * between(random, -0.5, 0.5), diameter + 0.9, 0) * CFrame.Angles(0, 0, -0.55),
		bark,
		{ material = M.Wood }
	)
	toadstool(model, at(base, hx * between(random, -0.6, 0.6), diameter - 0.2, 0), 0.7, random)
end

builders.Boulder = function(model, base, hx, hz, random)
	boulder(model, base, hx, hz, random, STONE, MOSS)
end

builders.Stump = function(model, base, hx, _hz, random)
	local diameter = hx * 1.55
	local height = between(random, 2.4, 3.6)
	local bark = vary(random, BARK, 0.08)
	column(model, diameter, height, base, bark, { material = M.Wood })
	column(model, diameter * 0.9, 0.3, at(base, 0, height, 0), WOOD_END, { material = M.Wood, collide = false })
	column(model, diameter * 0.5, 0.36, at(base, 0, height, 0), shade(WOOD_END, -0.15), { collide = false })
	-- Roots spreading out at the foot.
	for index = 1, 4 do
		local angle = index * math.pi / 2 + random() * 0.6
		local root = CFrame.new(math.cos(angle) * diameter * 0.55, 0.6, math.sin(angle) * diameter * 0.55)
		block(
			model,
			Vector3.new(1, 1.2, (hx - diameter * 0.45) * 2),
			base * root * CFrame.Angles(0, -angle + math.pi / 2, 0),
			shade(bark, -0.08),
			{ material = M.Wood, collide = false }
		)
	end
	toadstool(model, at(base, diameter * 0.45, 0, -diameter * 0.3), 0.6, random)
end

builders.Oak = function(model, base, hx, _hz, random)
	local trunk = hx * 1.5
	local height = between(random, 30, 36)
	local bark = vary(random, BARK, 0.08)
	block(model, Vector3.new(trunk, height, trunk), at(base, 0, height / 2, 0), bark, { material = M.Wood })
	-- Root flare.
	for _, side in { -1, 1 } do
		wedge(
			model,
			Vector3.new(trunk * 0.6, 2.4, hx - trunk / 2 + 0.1),
			-- Full height against the trunk, sloping away from it.
			at(base, 0, 1.2, side * (trunk / 2 + (hx - trunk / 2) / 2))
				* CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
			shade(bark, -0.06),
			{ material = M.Wood, collide = false }
		)
	end
	-- Branches up into a big blocky canopy, well above anyone riding past.
	for _, side in { -1, 1 } do
		block(
			model,
			Vector3.new(1.4, 9, 1.4),
			at(base, side * 3, height - 3, 0) * CFrame.Angles(0, 0, side * -0.6),
			bark,
			{ material = M.Wood, collide = false }
		)
	end
	local leaf = vary(random, LEAF, 0.07)
	local width = between(random, 18, 23)
	local canopy = {
		{ Vector3.new(width, 7, width * 0.9), Vector3.new(0, height + 3, 0), 0 },
		{ Vector3.new(width * 0.75, 6, width * 0.8), Vector3.new(width * 0.12, height + 8.5, -width * 0.08), 0.12 },
		{ Vector3.new(width * 0.5, 4.5, width * 0.5), Vector3.new(-width * 0.06, height + 12.5, width * 0.05), -0.1 },
		{ Vector3.new(width * 0.55, 5, width * 0.5), Vector3.new(-width * 0.36, height + 1.5, width * 0.22), 0.08 },
		{ Vector3.new(width * 0.5, 4.5, width * 0.55), Vector3.new(width * 0.34, height + 0.8, -width * 0.3), -0.06 },
	}
	for index, piece in canopy do
		block(
			model,
			piece[1],
			at(base, piece[2].X, piece[2].Y, piece[2].Z) * CFrame.Angles(0, (random() - 0.5) * 0.5, 0),
			shade(leaf, piece[3] + (index % 2) * 0.03),
			{ material = M.Grass, collide = false }
		)
	end
	-- A few apples.
	for _ = 1, 4 do
		ball(
			model,
			0.9,
			(at(base, (random() - 0.5) * width * 0.8, height - 0.4, (random() - 0.5) * width * 0.7)).Position,
			{ 220, 52, 44 },
			{ collide = false }
		)
	end
end

builders.Bush = function(model, base, hx, hz, random)
	local leaf = vary(random, { 70, 146, 58 }, 0.06)
	local puffs = {
		{ 0, 0, hx * 1.25 },
		{ -hx * 0.45, -hz * 0.2, hx * 1.0 },
		{ hx * 0.45, hz * 0.15, hx * 1.05 },
		{ 0, hz * 0.35, hx * 0.85 },
	}
	for index, puff in puffs do
		local diameter = puff[3]
		ball(
			model,
			diameter,
			(at(base, puff[1], diameter * 0.42 + (if index == 1 then 0.6 else 0), puff[2])).Position,
			shade(leaf, (index - 2) * 0.05),
			{ material = M.Grass }
		)
	end
	-- Berries.
	for _ = 1, 6 do
		local angle = random() * math.pi * 2
		ball(
			model,
			0.55,
			(at(base, math.cos(angle) * hx * 0.6, between(random, 1.2, hx * 1.1), math.sin(angle) * hz * 0.6)).Position,
			Build.pick(random, { { 210, 40, 70 }, { 90, 60, 200 } }),
			{ collide = false }
		)
	end
end

builders.Toadstools = function(model, base, hx, hz, random)
	toadstool(model, base, hx * 0.62, random)
	toadstool(model, at(base, -hx * 0.55, 0, hz * 0.45), hx * 0.38, random)
	toadstool(model, at(base, hx * 0.5, 0, -hz * 0.5), hx * 0.3, random)
	block(
		model,
		Vector3.new(hx * 1.8, 0.3, hz * 1.8),
		at(base, 0, 0.15, 0),
		vary(random, MOSS, 0.05),
		{ material = M.Grass, collide = false }
	)
end

----------------------------------------------------------------------------------------------------------------
-- Desert

builders.Cactus = function(model, base, hx, _hz, random)
	local green = vary(random, { 82, 156, 80 }, 0.07)
	local height = between(random, 9, 14)
	local trunk = 2.3
	block(model, Vector3.new(trunk, height, trunk), at(base, 0, height / 2, 0), green, { material = M.Grass })
	block(model, Vector3.new(trunk * 0.75, 0.8, trunk * 0.75), at(base, 0, height + 0.4, 0), shade(green, 0.08))
	-- Ribs down two faces.
	for _, side in { -1, 1 } do
		block(
			model,
			Vector3.new(0.3, height * 0.95, 0.3),
			at(base, side * 0.55, height / 2, -trunk / 2 - 0.05),
			shade(green, -0.15),
			{ collide = false }
		)
	end
	-- Arms, kept inside the footprint.
	local reach = hx - 0.75
	for _, side in { -1, 1 } do
		if side < 0 or random() < 0.7 then
			local armY = height * between(random, 0.35, 0.55)
			block(model, Vector3.new(reach, 1.3, 1.3), at(base, side * reach / 2, armY, 0), green)
			local armHeight = between(random, 2.5, 4.5)
			block(model, Vector3.new(1.4, armHeight, 1.4), at(base, side * reach, armY + armHeight / 2, 0), green)
			block(model, Vector3.new(1, 0.5, 1), at(base, side * reach, armY + armHeight + 0.25, 0), shade(green, 0.08))
		end
	end
	block(model, Vector3.new(0.8, 0.6, 0.8), at(base, 0, height + 1.1, 0), { 250, 120, 170 }, { collide = false })
end

builders.Sandstone = function(model, base, hx, hz, random)
	local bands = { { 214, 152, 96 }, { 196, 130, 82 }, { 226, 172, 112 }, { 186, 120, 76 } }
	local y = 0
	local width, depth = hx * 1.9, hz * 1.9
	for index = 1, 4 do
		local height = between(random, 2.2, 3.6)
		block(
			model,
			Vector3.new(width, height, depth),
			at(base, (random() - 0.5) * 0.8, y + height / 2, (random() - 0.5) * 0.8)
				* CFrame.Angles(0, (random() - 0.5) * 0.25, 0),
			vary(random, bands[index], 0.04),
			{ material = M.Sandstone }
		)
		y += height
		width *= between(random, 0.72, 0.86)
		depth *= between(random, 0.72, 0.86)
	end
	block(
		model,
		Vector3.new(width * 1.5, 1.4, depth * 1.5),
		at(base, (random() - 0.5) * 0.6, y + 0.7, (random() - 0.5) * 0.6) * CFrame.Angles(0, random(), 0.06),
		{ 150, 92, 62 },
		{ material = M.Sandstone }
	)
	for _ = 1, 3 do
		local angle = random() * math.pi * 2
		block(
			model,
			Vector3.one * between(random, 0.9, 1.6),
			at(base, math.cos(angle) * hx * 0.9, 0.5, math.sin(angle) * hz * 0.9) * tumble(random, 0.5, 1),
			bands[2],
			{ material = M.Sandstone, collide = false }
		)
	end
end

builders.Tumbleweed = function(model, base, hx, _hz, random)
	twigBall(model, at(base, 0, hx * 0.95, 0), hx * 0.95, random, { 168, 128, 76 })
end

builders.SandGeyser = function(model, base, hx, _hz, random)
	column(model, hx * 2, 0.35, base, shade(SAND, -0.12), { material = M.Sand, collide = false })
	column(model, hx * 1.2, 0.45, base, shade(SAND, -0.25), { material = M.Sand, collide = false })
	for index = 1, 7 do
		local angle = index / 7 * math.pi * 2 + random() * 0.4
		block(
			model,
			Vector3.new(1.1, between(random, 0.6, 1.2), 1.1),
			at(base, math.cos(angle) * hx * 0.85, 0.4, math.sin(angle) * hx * 0.85) * tumble(random, 0.3, 1),
			vary(random, { 200, 160, 104 }, 0.08),
			{ material = M.Sandstone, collide = false }
		)
	end
	local vent = block(model, Vector3.new(1, 0.2, 1), at(base, 0, 0.3, 0), shade(SAND, -0.3), { collide = false })
	vent.Name = "Vent"
	emitter(vent, "Warn", SAND, { size = 1.2, rate = 22, speed = 6, spread = 30, life = 0.8, enabled = false })
	local burst = column(model, hx * 1.25, 20, base, { 232, 204, 146 }, { material = M.Sand, collide = false })
	burst.Name = "Burst"
	burst.Transparency = 1
end

builders.Skull = function(model, base, hx, hz, random)
	local bone = vary(random, BONE, 0.04)
	local turn = base * CFrame.Angles(0, (random() - 0.5) * 0.6, 0)
	block(model, Vector3.new(hx * 0.9, 2.2, hz * 0.9), at(turn, 0, 1.1, hz * 0.15), bone)
	block(model, Vector3.new(hx * 0.6, 1.6, hz * 0.8), at(turn, 0, 0.8, -hz * 0.55), bone)
	for _, side in { -1, 1 } do
		block(
			model,
			Vector3.new(0.6, 0.6, 0.3),
			at(turn, side * hx * 0.25, 1.5, -hz * 0.31),
			{ 62, 50, 40 },
			{ collide = false }
		)
		-- Horns curving out and up.
		block(
			model,
			Vector3.new(hx * 0.55, 0.6, 0.6),
			at(turn, side * hx * 0.62, 2.1, hz * 0.3) * CFrame.Angles(0, 0, side * 0.3),
			shade(bone, -0.08),
			{ collide = false }
		)
		block(
			model,
			Vector3.new(0.5, 1.4, 0.5),
			at(turn, side * hx * 0.86, 2.8, hz * 0.3),
			shade(bone, -0.12),
			{ collide = false }
		)
	end
end

----------------------------------------------------------------------------------------------------------------
-- Snow

local function pine(model: Model, base: CFrame, hx: number, random: Random, tiers: number, snowy: boolean)
	local needle = vary(random, { 38, 96, 70 }, 0.06)
	local trunkHeight = 3
	column(model, 1.6, trunkHeight + 2, base, BARK, { material = M.Wood })
	local y = trunkHeight
	for tier = 0, tiers - 1 do
		local width = hx * 2 * (1 - tier * 0.17)
		local height = 3.6
		-- The two lowest tiers are square to the runway, so they stay inside the footprint.
		local turn = if tier >= 2 then CFrame.Angles(0, (tier % 2) * math.pi / 4, 0) else CFrame.identity
		block(
			model,
			Vector3.new(width, height, width),
			at(base, 0, y + height / 2, 0) * turn,
			shade(needle, tier * 0.025),
			{ material = M.Grass }
		)
		if snowy then
			block(
				model,
				Vector3.new(width * 0.78, 0.6, width * 0.78),
				at(base, 0, y + height + 0.3, 0) * turn,
				SNOW,
				{ material = M.Snow, collide = false }
			)
		end
		y += height * 0.92
	end
	block(model, Vector3.new(1.2, 2, 1.2), at(base, 0, y + 1, 0), if snowy then SNOW else needle, { collide = false })
end

builders.Pine = function(model, base, hx, _hz, random)
	pine(model, base, hx, random, 5, true)
end

builders.IceBoulder = function(model, base, hx, hz, random)
	local ice = vary(random, { 150, 204, 240 }, 0.05)
	local height = math.min(hx, hz) * 1.1
	block(
		model,
		Vector3.new(hx * 1.7, height, hz * 1.6),
		at(base, 0, height * 0.45, 0) * tumble(random, 0.08, 0.3),
		shade(ice, -0.12),
		{ material = M.Ice, reflectance = 0.1 }
	)
	block(
		model,
		Vector3.new(hx * 1.5, 0.8, hz * 1.4),
		at(base, 0, height * 0.98, 0) * tumble(random, 0.05, 0.3),
		SNOW,
		{ material = M.Snow, collide = false }
	)
	-- Shards of clear ice standing up out of it.
	for index = 1, 4 do
		local tall = between(random, 3, 7)
		local thick = between(random, 1.1, 1.8)
		local angle = index * math.pi / 2 + random()
		block(
			model,
			Vector3.new(thick, tall, thick),
			at(base, math.cos(angle) * hx * 0.45, height * 0.7 + tall * 0.35, math.sin(angle) * hz * 0.45)
				* CFrame.Angles(math.sin(angle) * 0.35, random() * 3, -math.cos(angle) * 0.35),
			shade(ice, 0.12),
			{ material = M.Ice, transparency = 0.15, reflectance = 0.15 }
		)
	end
end

builders.Snowdrift = function(model, base, hx, hz, random)
	-- Sloping off at the front and back, like snow blown into a bank.
	for _, side in { -1, 1 } do
		wedge(
			model,
			Vector3.new(hx * 1.7, 2.6, hz * 0.55),
			at(base, 0, 1.3, side * hz * 0.72) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0),
			{ 232, 240, 250 },
			{ material = M.Snow }
		)
	end
	local layers = { { 1.95, 2.2, 1.2 }, { 1.45, 1.8, 0.95 }, { 0.8, 1.3, 0.6 } }
	local y = 0
	for index, layer in layers do
		block(
			model,
			Vector3.new(hx * layer[1], layer[2], hz * layer[3]),
			at(base, (random() - 0.5) * hx * 0.3, y + layer[2] / 2, (random() - 0.5) * 0.5),
			shade({ 236, 244, 252 }, -0.03 * (3 - index)),
			{ material = M.Snow }
		)
		y += layer[2] * 0.9
	end
	-- Something half-buried: a red sled.
	if random() < 0.5 then
		wedge(
			model,
			Vector3.new(2, 1, 3.2),
			at(base, hx * 0.55, 1.6, -hz * 0.1) * CFrame.Angles(0.3, 0.5, 0),
			{ 200, 50, 50 },
			{ collide = false }
		)
	end
end

builders.Snowman = function(model, base, hx, hz, random)
	local size = math.min(hx, hz) * 1.85
	local white = { 248, 250, 255 }
	ball(model, size, (at(base, 0, size * 0.45, 0)).Position, white, { material = M.Snow })
	ball(model, size * 0.75, (at(base, 0, size * 1.15, 0)).Position, white, { material = M.Snow })
	local headY = size * 1.7
	ball(model, size * 0.55, (at(base, 0, headY, 0)).Position, white, { material = M.Snow })
	-- Facing up the runway, at whoever is coming.
	wedge(
		model,
		Vector3.new(0.45, 0.45, size * 0.4),
		at(base, 0, headY, -size * 0.38),
		{ 245, 130, 30 },
		{ collide = false }
	)
	for _, side in { -1, 1 } do
		block(
			model,
			Vector3.new(0.35, 0.35, 0.2),
			at(base, side * size * 0.11, headY + size * 0.08, -size * 0.27),
			{ 30, 30, 34 },
			{ collide = false }
		)
		block(
			model,
			Vector3.new(size * 0.7, 0.25, 0.25),
			at(base, side * size * 0.6, size * 1.25, 0) * CFrame.Angles(0, 0, side * 0.5),
			BARK,
			{ collide = false }
		)
	end
	for index = 0, 2 do
		block(
			model,
			Vector3.new(0.35, 0.35, 0.2),
			at(base, 0, size * (0.95 + index * 0.17), -size * 0.37),
			{ 30, 30, 34 },
			{ collide = false }
		)
	end
	local scarf = vary(random, { 210, 50, 60 }, 0.1)
	block(
		model,
		Vector3.new(size * 0.55, 0.5, size * 0.55),
		at(base, 0, headY - size * 0.25, 0),
		scarf,
		{ collide = false }
	)
	block(
		model,
		Vector3.new(0.5, 1.4, 0.3),
		at(base, size * 0.18, headY - size * 0.45, -size * 0.28),
		scarf,
		{ collide = false }
	)
	column(model, size * 0.5, 0.2, at(base, 0, headY + size * 0.22, 0), { 30, 30, 34 }, { collide = false })
	column(model, size * 0.34, size * 0.4, at(base, 0, headY + size * 0.22, 0), { 30, 30, 34 }, { collide = false })
end

----------------------------------------------------------------------------------------------------------------
-- Ocean

local CORAL = { { 250, 110, 140 }, { 250, 160, 80 }, { 170, 100, 210 }, { 80, 200, 190 }, { 250, 220, 90 } }

builders.Coral = function(model, base, hx, hz, random)
	for _ = 1, 7 do
		local color = Build.pick(random, CORAL)
		local x, z = (random() - 0.5) * hx * 1.5, (random() - 0.5) * hz * 1.5
		local height = between(random, 1.8, 5.5)
		local thick = between(random, 0.7, 1.2)
		block(
			model,
			Vector3.new(thick, height, thick),
			at(base, x, height / 2, z) * CFrame.Angles((random() - 0.5) * 0.4, 0, (random() - 0.5) * 0.4),
			color,
			{ material = M.Pebble }
		)
		ball(model, thick * 1.35, (at(base, x, height, z)).Position, shade(color, 0.12), { collide = false })
	end
	ball(
		model,
		hx * 0.9,
		(at(base, -hx * 0.3, hx * 0.3, hz * 0.3)).Position,
		Build.pick(random, CORAL),
		{ material = M.Pebble }
	)
	-- A sea fan.
	block(
		model,
		Vector3.new(hx * 0.9, hx * 0.9, 0.25),
		at(base, hx * 0.3, hx * 0.5, -hz * 0.2) * CFrame.Angles(0, 0.4, 0),
		{ 180, 90, 200 },
		{ material = M.Fabric, collide = false }
	)
end

local function starfish(model: Model, center: CFrame, size: number)
	for index = 0, 4 do
		block(
			model,
			Vector3.new(0.5, 0.25, size),
			center * CFrame.Angles(0, index * math.pi * 2 / 5, 0) * CFrame.new(0, 0, size / 2),
			{ 250, 120, 60 },
			{ collide = false }
		)
	end
end

builders.SeaRock = function(model, base, hx, hz, random)
	local height = boulder(model, base, hx, hz, random, { 88, 98, 112 }, { 120, 132, 140 }, M.Slate)
	for _ = 1, 6 do
		local angle = random() * math.pi * 2
		ball(
			model,
			between(random, 0.5, 0.9),
			(at(base, math.cos(angle) * hx * 0.6, between(random, 0.6, height * 0.9), math.sin(angle) * hz * 0.75)).Position,
			{ 236, 232, 220 },
			{ collide = false }
		)
	end
	for _ = 1, 3 do
		local x = (random() - 0.5) * hx * 1.6
		local tall = between(random, 3, 6)
		block(
			model,
			Vector3.new(0.35, tall, 0.35),
			at(base, x, tall / 2, -hz * 0.8) * CFrame.Angles((random() - 0.5) * 0.3, 0, (random() - 0.5) * 0.3),
			{ 60, 150, 80 },
			{ collide = false }
		)
	end
	starfish(model, at(base, hx * 0.2, height * 0.95, -hz * 0.2), 1.2)
end

builders.GiantClam = function(model, base, hx, hz, random)
	local shell = vary(random, { 160, 128, 204 }, 0.05)
	local width, depth = hx * 1.95, hz * 1.95
	local shellPart = block(model, Vector3.new(width, 1.7, depth), at(base, 0, 0.85, 0), shell, { material = M.Pebble })
	shellPart.Name = "Shell"
	for index = -2, 2 do
		block(
			model,
			Vector3.new(0.35, 0.3, depth * 0.95),
			at(base, index * width * 0.18, 1.75, 0),
			shade(shell, -0.12),
			{ collide = false }
		)
	end
	ball(model, 1.7, (at(base, 0, 2.3, 0)).Position, { 252, 250, 246 }, { reflectance = 0.25, collide = false })
	block(
		model,
		Vector3.new(width * 0.8, 0.3, depth * 0.8),
		at(base, 0, 1.75, 0),
		{ 250, 170, 180 },
		{ collide = false }
	)
	local lid =
		block(model, Vector3.new(width, 1.2, depth), at(base, 0, 2.3, 0), shade(shell, 0.08), { material = M.Pebble })
	lid.Name = "Lid"
	-- Open, hinged on the back edge of the shell; the client snaps it shut when the clam goes off.
	local hinge = shellPart.CFrame * CFrame.new(0, 0.85, depth / 2)
	lid.CFrame = hinge * CFrame.Angles(math.rad(60), 0, 0) * CFrame.new(0, 0.6, -depth / 2)
end

builders.Barrel = function(model, base, hx, _hz, random)
	local wood = vary(random, { 150, 98, 58 }, 0.06)
	local diameter = hx * 1.2
	local height = diameter * 1.25
	local function barrel(cframe: CFrame)
		column(model, diameter, height, cframe, wood, { material = M.WoodPlanks })
		for _, y in { 0.18, 0.82 } do
			column(
				model,
				diameter * 1.04,
				0.3,
				cframe * CFrame.new(0, height * y - 0.15, 0),
				{ 74, 74, 78 },
				{ material = M.Metal, collide = false }
			)
		end
		column(model, diameter * 0.9, 0.2, cframe * CFrame.new(0, height, 0), shade(wood, 0.12), { collide = false })
	end
	barrel(at(base, -hx * 0.35, 0, 0))
	if random() < 0.6 then
		barrel(at(base, hx * 0.4, 0, hx * 0.3))
	else
		block(
			model,
			Vector3.new(diameter, diameter, diameter),
			at(base, hx * 0.4, diameter / 2, hx * 0.2),
			{ 176, 136, 88 },
			{ material = M.WoodPlanks }
		)
	end
end

----------------------------------------------------------------------------------------------------------------
-- Volcano

local LAVA = { 255, 112, 24 }
local LAVA_HOT = { 255, 196, 60 }
local BASALT = { 58, 54, 62 }

builders.LavaPool = function(model, base, hx, hz, random)
	local lava = block(
		model,
		Vector3.new(hx * 1.85, 0.3, hz * 1.85),
		at(base, 0, 0.12, 0),
		LAVA,
		{ material = M.Neon, collide = false }
	)
	glow(lava, LAVA, 18, 2)
	for _ = 1, 4 do
		block(
			model,
			Vector3.new(between(random, 1, 2.5), 0.32, between(random, 1, 2.5)),
			at(base, (random() - 0.5) * hx * 1.3, 0.14, (random() - 0.5) * hz * 1.3) * CFrame.Angles(0, random() * 3, 0),
			LAVA_HOT,
			{ material = M.Neon, collide = false }
		)
	end
	-- A rim of cooled rock round the edge.
	for index = 1, 12 do
		local angle = index / 12 * math.pi * 2
		block(
			model,
			Vector3.new(between(random, 2, 3.2), between(random, 0.6, 1.3), between(random, 1.4, 2.2)),
			at(base, math.cos(angle) * hx, 0.4, math.sin(angle) * hz) * CFrame.Angles(0, -angle, 0),
			vary(random, BASALT, 0.08),
			{ material = M.Basalt, collide = false }
		)
	end
end

builders.Basalt = function(model, base, hx, hz, random)
	local columns = {}
	for gx = -1, 1 do
		for gz = -1, 1 do
			if random() < 0.8 then
				table.insert(columns, { gx * hx * 0.6, gz * hz * 0.6 })
			end
		end
	end
	for _, spot in columns do
		local height = between(random, 5, 13)
		local width = between(random, 1.9, 2.6)
		local color = vary(random, BASALT, 0.07)
		block(
			model,
			Vector3.new(width, height, width),
			at(base, spot[1], height / 2, spot[2]),
			color,
			{ material = M.Basalt }
		)
		block(
			model,
			Vector3.new(width * 0.9, 0.2, width * 0.9),
			at(base, spot[1], height + 0.1, spot[2]),
			shade(color, 0.15),
			{ collide = false }
		)
	end
	block(
		model,
		Vector3.new(hx * 1.6, 0.2, 0.3),
		at(base, 0, 0.1, 0) * CFrame.Angles(0, random(), 0),
		LAVA,
		{ material = M.Neon, collide = false }
	)
end

builders.LavaVent = function(model, base, hx, _hz, random)
	for index = 1, 8 do
		local angle = index / 8 * math.pi * 2
		block(
			model,
			Vector3.new(1.8, between(random, 1, 1.7), 1.4),
			at(base, math.cos(angle) * hx * 0.82, 0.6, math.sin(angle) * hx * 0.82) * CFrame.Angles(0, -angle, 0.15),
			vary(random, BASALT, 0.08),
			{ material = M.Basalt, collide = false }
		)
	end
	local vent = column(model, hx * 1.3, 0.3, base, { 200, 70, 20 }, { material = M.Neon, collide = false })
	vent.Name = "Vent"
	emitter(
		vent,
		"Warn",
		{ 90, 80, 80 },
		{ size = 1.4, rate = 18, speed = 5, spread = 20, life = 1.2, enabled = false }
	)
	local burst = column(model, hx * 1.35, 24, base, LAVA, { material = M.Neon, collide = false })
	burst.Name = "Burst"
	burst.Transparency = 1
	glow(burst, LAVA, 24, 3).Enabled = false
end

builders.ObsidianSpikes = function(model, base, hx, hz, random)
	for _ = 1, 6 do
		local height = between(random, 3, 8)
		local width = between(random, 0.8, 1.5)
		local x, z = (random() - 0.5) * hx * 1.2, (random() - 0.5) * hz * 1.2
		block(
			model,
			Vector3.new(width, height, width),
			at(base, x, height * 0.45, z) * CFrame.Angles((random() - 0.5) * 0.5, random() * 3, (random() - 0.5) * 0.5),
			vary(random, { 36, 24, 52 }, 0.1),
			{ material = M.Glass, reflectance = 0.15 }
		)
	end
end

builders.MagmaRock = function(model, base, hx, hz, random)
	local height = boulder(model, base, hx, hz, random, { 64, 54, 54 }, nil)
	for _ = 1, 5 do
		block(
			model,
			Vector3.new(between(random, 1.5, 3), 0.25, 0.3),
			at(base, (random() - 0.5) * hx * 1.2, between(random, 0.5, height), -hz * 0.72)
				* CFrame.Angles(0, 0, random() * 2),
			LAVA,
			{ material = M.Neon, collide = false }
		)
	end
	local top = block(model, Vector3.new(0.5, 0.5, 0.5), at(base, 0, height, 0), { 64, 54, 54 }, { collide = false })
	emitter(top, "Smoke", { 70, 66, 66 }, { size = 2, rate = 4, speed = 3, life = 3, lift = 1 })
end

----------------------------------------------------------------------------------------------------------------
-- Prehistoric

local TAR = { 24, 22, 28 }

builders.TarPit = function(model, base, hx, hz, random)
	block(
		model,
		Vector3.new(hx * 1.85, 0.3, hz * 1.85),
		at(base, 0, 0.12, 0),
		TAR,
		{ material = M.Glass, reflectance = 0.12, collide = false }
	)
	for _ = 1, 5 do
		ball(
			model,
			between(random, 0.6, 1.3),
			(at(base, (random() - 0.5) * hx * 1.4, 0.2, (random() - 0.5) * hz * 1.4)).Position,
			shade(TAR, 0.08),
			{ material = M.Glass, collide = false }
		)
	end
	for index = 1, 12 do
		local angle = index / 12 * math.pi * 2
		block(
			model,
			Vector3.new(between(random, 2, 3.2), between(random, 0.5, 1), between(random, 1.4, 2)),
			at(base, math.cos(angle) * hx, 0.3, math.sin(angle) * hz) * CFrame.Angles(0, -angle, 0),
			vary(random, { 96, 74, 52 }, 0.08),
			{ material = M.Mud, collide = false }
		)
	end
	-- An old bone sticking out.
	block(
		model,
		Vector3.new(0.6, 3.5, 0.6),
		at(base, hx * 0.3, 1, -hz * 0.2) * CFrame.Angles(0.5, 0, 0.4),
		BONE,
		{ collide = false }
	)
end

local function fern(model: Model, base: CFrame, reach: number, random: Random, fronds: number)
	local green = vary(random, { 70, 146, 62 }, 0.06)
	for index = 1, fronds do
		local angle = index / fronds * math.pi * 2 + random() * 0.4
		local lean = between(random, 0.55, 0.95)
		local length = reach / math.cos(lean) * 0.95
		block(
			model,
			Vector3.new(1.5, 0.35, length),
			base
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, 0.6, 0)
				* CFrame.Angles(lean, 0, 0)
				* CFrame.new(0, 0, -length / 2),
			shade(green, (index % 3) * 0.05),
			{ material = M.Grass, collide = false }
		)
	end
	block(model, Vector3.new(1.4, 1.6, 1.4), at(base, 0, 0.8, 0), shade(green, -0.15), { material = M.Grass })
end

builders.Fern = function(model, base, hx, _hz, random)
	fern(model, base, hx, random, 8)
end

builders.Ribcage = function(model, base, hx, hz, random)
	local bone = vary(random, BONE, 0.03)
	local height = between(random, 8, 10)
	-- A great skeleton lying across the runway: the spine along the top, each rib arching down to the ground in
	-- front and behind.
	block(model, Vector3.new(hx * 1.9, 1.5, 1.5), at(base, 0, height, 0), bone)
	for index = -2, 2 do
		local x = index * hx * 0.38
		block(model, Vector3.new(1.3, 1.1, 1.3), at(base, x, height + 0.9, 0), shade(bone, -0.06))
		for _, side in { -1, 1 } do
			-- Out from the spine, down and round, and in a little at the foot.
			local segments = {
				{ z = 0.32, y = 0.96, length = hz * 0.62, angle = 1.25 },
				{ z = 0.72, y = 0.7, length = height * 0.42, angle = 0.45 },
				{ z = 0.82, y = 0.28, length = height * 0.5, angle = -0.15 },
			}
			for _, segment in segments do
				block(
					model,
					Vector3.new(0.75, segment.length, 0.75),
					at(base, x, height * segment.y, side * hz * segment.z) * CFrame.Angles(side * segment.angle, 0, 0),
					shade(bone, -0.03),
					{ collide = segment.y < 0.5 }
				)
			end
		end
	end
	-- The skull at one end, half sunk.
	block(model, Vector3.new(2.8, 2.6, 3.4), at(base, -hx * 0.95 + 1.4, 1.3, 0), bone)
	block(
		model,
		Vector3.new(0.7, 0.7, 0.3),
		at(base, -hx * 0.95 + 1.4, 1.8, -1.72),
		{ 50, 40, 34 },
		{ collide = false }
	)
end

builders.MossyBoulder = function(model, base, hx, hz, random)
	local height = boulder(model, base, hx, hz, random, { 120, 116, 104 }, { 96, 140, 60 })
	fern(model, at(base, hx * 0.4, height * 0.95, -hz * 0.1), 1.6, random, 5)
end

builders.DinoSkull = function(model, base, hx, hz, random)
	local bone = vary(random, BONE, 0.03)
	-- Facing up the runway, jaws open.
	block(model, Vector3.new(hx * 1.4, 3.2, hz * 0.9), at(base, 0, 1.8, hz * 0.4), bone)
	block(model, Vector3.new(hx * 0.95, 2.2, hz * 1.0), at(base, 0, 2.3, -hz * 0.45), bone)
	block(model, Vector3.new(hx * 0.85, 0.9, hz * 0.95), at(base, 0, 0.45, -hz * 0.4), shade(bone, -0.06))
	for _, side in { -1, 1 } do
		block(
			model,
			Vector3.new(0.9, 0.9, 0.3),
			at(base, side * hx * 0.38, 2.4, -hz * 0.06),
			{ 50, 40, 34 },
			{ collide = false }
		)
		for tooth = 0, 2 do
			wedge(
				model,
				Vector3.new(0.35, 0.8, 0.35),
				at(base, side * hx * 0.3, 0.95 + 0.4, -hz * (0.75 - tooth * 0.22)) * CFrame.Angles(math.pi, 0, 0),
				{ 250, 248, 240 },
				{ collide = false }
			)
		end
	end
	wedge(model, Vector3.new(0.7, 1.6, 1.4), at(base, 0, 4.1, -hz * 0.55), shade(bone, -0.04), { collide = false })
end

----------------------------------------------------------------------------------------------------------------

local ObstacleModels = {}

-- Fills `model` with an obstacle of this kind standing at `base`. Returns false for a kind with no builder.
function ObstacleModels.build(model: Model, kind: string, base: CFrame, hx: number, hz: number, seed: number): boolean
	local builder = builders[kind]
	if builder == nil then
		return false
	end
	builder(model, base, hx, hz, Build.random(1 + seed * 2147483000))
	return true
end

function ObstacleModels.has(kind: string): boolean
	return builders[kind] ~= nil
end

-- Scenery pieces for the banks that are not runway obstacles.
ObstacleModels.pine = pine
ObstacleModels.fern = fern
ObstacleModels.toadstool = toadstool
ObstacleModels.boulder = boulder
ObstacleModels.glow = glow
ObstacleModels.emitter = emitter

return ObstacleModels
