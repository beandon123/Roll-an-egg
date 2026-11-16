--!strict
-- The obstacles on the runway: what each kind does when a ridden egg runs into it, how big it is, and which kinds
-- turn up in which zone. Shared/Obstacles lays them out; MapService builds them (src/server/Map/ObstacleModels).
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.
--
-- tier:    what happens to the rider of an egg that hits it.
--              Bump      the egg is knocked aside and the rider loses Tuning.BUMP_STAMINA of the egg's requirement
--              KnockOff  the rider is thrown off (stunned, and the egg loses a bounce)
--              Lethal    the rider dies (and the egg loses a bounce); players on foot die in it too
-- hx, hz:  half its footprint in studs: hx across the runway, hz along it. Eggs without a rider steer round it.
-- grow:    the largest random enlargement of the footprint (1.3 = up to 30% bigger), so no two look alike.
-- timing:  for obstacles that go off now and then (a geyser, a lava vent, a snapping clam): every `period`
--          seconds it gives `warn` seconds of warning, then is dangerous for `active` seconds. The rest of the
--          time it is harmless. Eggs without a rider steer round it all the same.
-- flat:    lies in the ground rather than standing on it, so players on foot walk over it.
-- name:    how a toast refers to it ("Bumped into a boulder!").
-- hitText: what the toast says when it kills a rider, for Lethal kinds.

export type Tier = "Bump" | "KnockOff" | "Lethal"

export type Timing = { period: number, warn: number, active: number }

export type Kind = {
	tier: Tier,
	hx: number,
	hz: number,
	grow: number,
	timing: Timing?,
	flat: boolean,
	name: string,
	hitText: string?,
}

export type ZoneMix = {
	-- Each kind's share of the zone's obstacles.
	weights: { [string]: number },
}

local Obstacles = {}

local function kind(tier: Tier, hx: number, hz: number, name: string, extra: { [string]: any }?): Kind
	local options = extra or {}
	return {
		tier = tier,
		hx = hx,
		hz = hz,
		grow = options.grow or 1,
		timing = options.timing,
		flat = options.flat == true,
		name = name,
		hitText = options.hitText,
	}
end

Obstacles.Kinds = {
	-- Forest
	Log = kind("Bump", 10, 1.8, "a fallen log", { grow = 1.3 }),
	Boulder = kind("KnockOff", 4.5, 4, "a boulder", { grow = 1.35 }),
	Stump = kind("Bump", 2.4, 2.4, "a tree stump", { grow = 1.2 }),
	Oak = kind("KnockOff", 3, 3, "a tree", { grow = 1.2 }),
	Bush = kind("Bump", 3.6, 3, "a bush", { grow = 1.3 }),
	Toadstools = kind("Bump", 3.4, 3.4, "the toadstools", { grow = 1.2 }),
	-- Desert
	Cactus = kind("Bump", 3.2, 2.2, "a cactus", { grow = 1.2 }),
	Sandstone = kind("KnockOff", 5.5, 4.5, "a sandstone rock", { grow = 1.3 }),
	Tumbleweed = kind("Bump", 2.4, 2.4, "a tumbleweed", { grow = 1.2 }),
	SandGeyser = kind(
		"KnockOff",
		3.6,
		3.6,
		"a sand geyser",
		{ flat = true, timing = { period = 6, warn = 1.4, active = 1.6 } }
	),
	Skull = kind("Bump", 3, 3.4, "an old skull", { grow = 1.2 }),
	-- Snow
	Pine = kind("KnockOff", 3.6, 3.6, "a pine tree", { grow = 1.25 }),
	IceBoulder = kind("KnockOff", 4.5, 4, "an ice boulder", { grow = 1.3 }),
	Snowdrift = kind("Bump", 7, 3, "a snowdrift", { grow = 1.3 }),
	Snowman = kind("Bump", 2.8, 2.8, "a snowman", { grow = 1.15 }),
	-- Ocean
	Coral = kind("Bump", 3.6, 3.2, "the coral", { grow = 1.3 }),
	SeaRock = kind("KnockOff", 5, 4.5, "a sea rock", { grow = 1.3 }),
	GiantClam = kind(
		"KnockOff",
		4.2,
		3.8,
		"a giant clam",
		{ grow = 1.1, timing = { period = 5, warn = 1.1, active = 1.4 } }
	),
	Barrel = kind("Bump", 2.2, 2.2, "a barrel", { grow = 1.15 }),
	-- Volcano
	LavaPool = kind("Lethal", 6.5, 5, "the lava", { grow = 1.3, flat = true, hitText = "Burned up in the lava!" }),
	Basalt = kind("KnockOff", 4.5, 4, "basalt columns", { grow = 1.3 }),
	LavaVent = kind(
		"Lethal",
		3.6,
		3.6,
		"a lava burst",
		{ flat = true, timing = { period = 7, warn = 1.6, active = 1.8 }, hitText = "Caught in a lava burst!" }
	),
	ObsidianSpikes = kind("Bump", 3.2, 2.8, "obsidian spikes", { grow = 1.25 }),
	MagmaRock = kind("KnockOff", 4.2, 3.8, "a smoking rock", { grow = 1.3 }),
	-- Prehistoric
	TarPit = kind("Lethal", 7, 5, "the tar pit", { grow = 1.3, flat = true, hitText = "Sunk in the tar pit!" }),
	Fern = kind("Bump", 4, 3.6, "a giant fern", { grow = 1.25 }),
	Ribcage = kind("KnockOff", 6, 4.5, "a giant ribcage", { grow = 1.2 }),
	MossyBoulder = kind("KnockOff", 4.5, 4, "a mossy boulder", { grow = 1.35 }),
	DinoSkull = kind("Bump", 3.4, 3.8, "a dinosaur skull", { grow = 1.15 }),
}

-- The kinds in each zone (by zone id, matching Config/Zones) and how often each turns up.
Obstacles.Zones = {
	{ weights = { Log = 2, Boulder = 2, Stump = 2, Oak = 3, Bush = 3, Toadstools = 2 } },
	{ weights = { Cactus = 4, Sandstone = 3, Tumbleweed = 2, SandGeyser = 3, Skull = 1.5 } },
	{ weights = { Pine = 4, IceBoulder = 3, Snowdrift = 3, Snowman = 2 } },
	{ weights = { Coral = 4, SeaRock = 3, GiantClam = 3, Barrel = 3 } },
	{ weights = { LavaPool = 3, Basalt = 3, LavaVent = 3, ObsidianSpikes = 2, MagmaRock = 2 } },
	{ weights = { TarPit = 3, Fern = 4, Ribcage = 2, MossyBoulder = 3, DinoSkull = 2 } },
} :: { ZoneMix }

-- Layout. Obstacles stand in rows across the runway, a row every ROW_GAP_MIN to ROW_GAP_MAX studs.
-- The first row of a zone is FIRST_ROW studs past its start, so eggs land from their chute on clear ground.
Obstacles.FIRST_ROW = 90
-- No row within this many studs of the end of a zone.
Obstacles.LAST_ROW = 40
Obstacles.ROW_GAP_MIN = 54
Obstacles.ROW_GAP_MAX = 74
-- How far an obstacle may sit in front of or behind the middle of its row.
Obstacles.ROW_JITTER = 4
-- Every row leaves at least one gap this wide, so the biggest egg can always get through.
Obstacles.MIN_GAP = 28
-- Room kept between an egg without a rider and an obstacle it steers round, in studs.
Obstacles.STEER_MARGIN = 1.5

return Obstacles
