--!strict
-- The training stick: every player's stamina trainer. It stands in the plaza in front of their pen (Shared/Plots
-- says where): a roller held over a little pool of water. The owner steps up, and rolls on it for as long as they
-- like, running on the spot while it spins under their feet (birling). Every quarter of a second of rolling is a
-- "rep" that adds Max Stamina for good, and a "+1" floats up over their head.
--
-- Every few seconds a "2x" bubble pops up on the trainer's screen: tapping it doubles what they earn for a moment.
--
-- The stick is upgraded with dollars (the sign beside it, or the shop) or with Robux (Config/Shop): eight tiers, each
-- dearer, stronger and better-looking than the one before, from a twig to a glowing rainbow crystal.
-- First-pass numbers; adjust in economy tuning.
-- Pure data and math (no Roblox APIs) so the test runner can load it outside Studio.

-- The shape the rider's feet meet, seen end on, for working out how high the top of the roller is as it turns:
-- a circle, a rectangle (flat on top when it is at rest), or a hexagon (a flat face on top at rest).
export type Profile =
	{ kind: "Round", radius: number }
	| { kind: "Box", halfWidth: number, halfHeight: number }
	| { kind: "Hex", radius: number }

export type Tier = {
	level: number,
	-- Short id, used for model names.
	id: string,
	name: string,
	-- A rarity from Config/Rarities, for its badge and the colours of its name.
	rarity: string,
	-- Max Stamina each rep adds, before the player's multipliers (stamina doublings and their trail).
	perRep: number,
	-- Dollars to upgrade to this tier (0 for the first, which everyone starts with).
	price: number,
	-- The shape under the rider's feet (see Profile), and the furthest any of it reaches from the axle (end caps,
	-- bark and flanges included), which sets how high the axle sits over the water.
	profile: Profile,
	reach: number,
	-- How long it is along the axle, in studs.
	length: number,
	-- Turns a second while someone rolls on it (faster during a 2x boost).
	spin: number,
	-- RGB 0-255: the glow round the stand's pool, and the tier's colour on signs and panels.
	color: { number },
}

local Sticks = {}

-- A rep every this many seconds while rolling: 4 a second.
Sticks.REP_INTERVAL = 0.25

-- The "2x" bubble: it appears this long after the player starts rolling, then again a random time (between the two
-- numbers, in seconds) after the last one went. It stays up for BUBBLE_LIFETIME seconds; tapping it in time doubles
-- every rep for BOOST_DURATION seconds. A tap that reaches the server a little late still counts (CLAIM_GRACE).
Sticks.FIRST_BUBBLE = 2
Sticks.BUBBLE_GAP = { 2.5, 5 }
Sticks.BUBBLE_LIFETIME = 2.5
Sticks.BOOST_DURATION = 1.5
Sticks.BOOST_MULTIPLIER = 2
Sticks.CLAIM_GRACE = 0.4
-- The roller spins this many times faster during a boost, and the rider's legs keep up.
Sticks.BOOST_SPIN = 1.6
-- How hard the rider runs on the roller, as in Shared/RiderPose (the same animation as riding an egg): 0 is as on the
-- slowest eggs, 1 the fastest. A steady run normally, a flat-out sprint during a boost.
Sticks.RUN_PACE = 0.15
Sticks.BOOST_RUN_PACE = 1

-- The stand: the pool's water is this high above the plaza, and the roller's lowest point hangs this far above it.
Sticks.WATER_HEIGHT = 1
Sticks.WATER_CLEARANCE = 0.25
-- How far apart the two posts holding the axle are (between their middles), and so how long the axle is.
Sticks.POST_SPAN = 14.4

-- In upgrade order.
local tiers: { Tier } = {
	{
		level = 1,
		id = "Stick",
		name = "Stick",
		rarity = "Common",
		perRep = 1,
		price = 0,
		profile = { kind = "Round", radius = 0.45 },
		reach = 0.6,
		length = 10,
		spin = 1.8,
		color = { 150, 215, 100 },
	},
	{
		level = 2,
		id = "Plank",
		name = "Plank",
		rarity = "Uncommon",
		perRep = 2,
		price = 500,
		profile = { kind = "Box", halfWidth = 1.25, halfHeight = 0.35 },
		reach = 1.32,
		length = 10.5,
		spin = 0.7,
		color = { 236, 184, 110 },
	},
	{
		level = 3,
		id = "ShortLog",
		name = "Short Log",
		rarity = "Rare",
		perRep = 5,
		price = 5_000,
		profile = { kind = "Round", radius = 0.95 },
		reach = 1.05,
		length = 7.5,
		spin = 1.2,
		color = { 214, 140, 76 },
	},
	{
		level = 4,
		id = "TreeTrunk",
		name = "Tree Trunk",
		rarity = "Epic",
		perRep = 12,
		price = 50_000,
		profile = { kind = "Round", radius = 1.3 },
		reach = 1.5,
		length = 11,
		spin = 0.85,
		color = { 130, 200, 84 },
	},
	{
		level = 5,
		id = "MetalPipe",
		name = "Metal Pipe",
		rarity = "Legendary",
		perRep = 30,
		price = 500_000,
		profile = { kind = "Round", radius = 1.15 },
		reach = 1.5,
		length = 11,
		spin = 1,
		color = { 255, 196, 60 },
	},
	{
		level = 6,
		id = "SteelGirder",
		name = "Steel Girder",
		rarity = "Mythic",
		perRep = 75,
		price = 5_000_000,
		profile = { kind = "Box", halfWidth = 1.15, halfHeight = 1.35 },
		reach = 1.85,
		length = 11,
		spin = 0.6,
		color = { 255, 96, 70 },
	},
	{
		level = 7,
		id = "MarbleColumn",
		name = "Marble Column",
		rarity = "Secret",
		perRep = 200,
		price = 50_000_000,
		profile = { kind = "Round", radius = 1.45 },
		reach = 1.85,
		length = 11,
		spin = 0.75,
		color = { 196, 160, 255 },
	},
	{
		level = 8,
		id = "RainbowCrystal",
		name = "Rainbow Crystal",
		rarity = "Eternal",
		perRep = 500,
		price = 500_000_000,
		profile = { kind = "Hex", radius = 1.5 },
		reach = 1.75,
		length = 11,
		spin = 0.9,
		color = { 150, 255, 245 },
	},
}

Sticks.Tiers = tiers
Sticks.MAX_LEVEL = #tiers

-- The tier of a level (levels outside 1..MAX_LEVEL are clamped into it).
function Sticks.tier(level: number): Tier
	return tiers[math.clamp(math.floor(level), 1, #tiers)]
end

-- The tier after a level, or nil once the stick is as good as it gets.
function Sticks.nextTier(level: number): Tier?
	return tiers[math.floor(level) + 1]
end

-- Max Stamina a second while rolling on a tier, before multipliers and boosts.
function Sticks.perSecond(level: number): number
	return Sticks.tier(level).perRep / Sticks.REP_INTERVAL
end

-- How high the axle is above the plaza.
function Sticks.axleHeight(level: number): number
	return Sticks.WATER_HEIGHT + Sticks.WATER_CLEARANCE + Sticks.tier(level).reach
end

-- How far above the axle the top of the roller is when it has turned `angle` radians from rest: where the rider's
-- feet are.
function Sticks.topHeight(level: number, angle: number): number
	local profile = Sticks.tier(level).profile
	if profile.kind == "Box" then
		return profile.halfWidth * math.abs(math.sin(angle)) + profile.halfHeight * math.abs(math.cos(angle))
	elseif profile.kind == "Hex" then
		-- Corners every 60 degrees, starting on the horizontal, so a flat face is on top at rest.
		local highest = -math.huge
		for corner = 0, 5 do
			highest = math.max(highest, math.sin(corner * math.pi / 3 + angle))
		end
		return profile.radius * highest
	end
	return profile.radius
end

-- The highest the top of the roller ever gets above the axle as it turns. The rider stands this high, and drops to
-- the real top as it turns (a plank or a girder rocks them up and down).
function Sticks.maxTop(level: number): number
	local profile = Sticks.tier(level).profile
	if profile.kind == "Box" then
		return math.sqrt(profile.halfWidth ^ 2 + profile.halfHeight ^ 2)
	elseif profile.kind == "Hex" then
		return profile.radius
	end
	return profile.radius
end

return Sticks
