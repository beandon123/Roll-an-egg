--!strict
-- Rarity tiers and the egg tuning that depends only on rarity.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.

export type RarityInfo = {
	order: number,
	-- Egg size multiplier; rarer eggs are bigger.
	size: number,
	-- Seconds of riding needed to claim the egg.
	claimTime: number,
	-- Studs per second the egg rolls down the runway.
	rollSpeed: number,
	-- How many times the egg can be left without a rider before it cracks.
	bounces: number,
	-- Rhythm duel length and tempo (beats per minute).
	duelBeats: number,
	duelTempo: number,
	-- Seconds to hatch in a nest at normal speed.
	hatchTime: number,
	-- RGB 0-255.
	color: { number },
	-- Whether every player gets an on-screen message (where and when) when one spawns.
	announce: boolean,
}

local Rarities = {}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Eternal" }

local info: { [string]: RarityInfo } = {
	Common = {
		order = 1,
		size = 1.0,
		claimTime = 5,
		rollSpeed = 12,
		bounces = 1,
		duelBeats = 6,
		duelTempo = 90,
		hatchTime = 30,
		color = { 205, 210, 215 },
		announce = false,
	},
	Uncommon = {
		order = 2,
		size = 1.1,
		claimTime = 7,
		rollSpeed = 13,
		bounces = 1,
		duelBeats = 6,
		duelTempo = 100,
		hatchTime = 2 * 60,
		color = { 95, 205, 95 },
		announce = false,
	},
	Rare = {
		order = 3,
		size = 1.25,
		claimTime = 9,
		rollSpeed = 14,
		bounces = 2,
		duelBeats = 8,
		duelTempo = 110,
		hatchTime = 5 * 60,
		color = { 70, 140, 255 },
		announce = false,
	},
	Epic = {
		order = 4,
		size = 1.4,
		claimTime = 12,
		rollSpeed = 16,
		bounces = 2,
		duelBeats = 8,
		duelTempo = 125,
		hatchTime = 15 * 60,
		color = { 170, 90, 230 },
		announce = false,
	},
	Legendary = {
		order = 5,
		size = 1.6,
		claimTime = 15,
		rollSpeed = 17,
		bounces = 3,
		duelBeats = 10,
		duelTempo = 135,
		hatchTime = 45 * 60,
		color = { 255, 190, 40 },
		announce = false,
	},
	Mythic = {
		order = 6,
		size = 1.8,
		claimTime = 18,
		rollSpeed = 19,
		bounces = 3,
		duelBeats = 10,
		duelTempo = 150,
		hatchTime = 2 * 60 * 60,
		color = { 255, 70, 110 },
		announce = false,
	},
	Secret = {
		order = 7,
		size = 2.0,
		claimTime = 22,
		rollSpeed = 20,
		bounces = 3,
		duelBeats = 12,
		duelTempo = 160,
		hatchTime = 4 * 60 * 60,
		color = { 45, 45, 60 },
		announce = true,
	},
	Eternal = {
		order = 8,
		size = 2.3,
		claimTime = 26,
		rollSpeed = 21,
		bounces = 4,
		duelBeats = 12,
		duelTempo = 170,
		hatchTime = 6 * 60 * 60,
		color = { 150, 255, 245 },
		announce = true,
	},
}

Rarities.Info = info

return Rarities
