--!strict
-- Sounds the game plays. Pure data (no Roblox APIs) so the test runner can load it outside Studio.
--
-- The ids are sounds that ship with every Roblox client (rbxasset://), so they play without uploading anything. To
-- use a sound of your own, upload it (Creator Dashboard > Audio, or Studio's Asset Manager) and put its
-- "rbxassetid://<id>" here instead.

local Sounds = {}

export type Alert = {
	id: string,
	-- 0 to 1, before the player's Effects volume setting.
	volume: number,
	-- Seconds each note is left to ring before it is cleaned up.
	length: number,
	-- When each note plays (seconds after the alert starts), how high (1 = as recorded), and how loud (times
	-- `volume`; 1 if left out).
	notes: { { at: number, pitch: number, volume: number? } },
}

-- Everyone in the server hears this when a Secret or rarer egg spawns: a sparkle. A short ping, played high and fast
-- up a five-note (pentatonic) scale so it glitters rather than beeps, then a few higher twinkles that die away.
-- Several notes ring at once, which is what makes it shimmer. If you upload a sparkle sound of your own, put its id
-- here with a single note: { { at = 0, pitch = 1 } }.
Sounds.SECRET_ALERT = {
	id = "rbxasset://sounds/electronicpingshort.wav",
	volume = 0.75,
	length = 1.5,
	notes = {
		-- The run up.
		{ at = 0, pitch = 1.25, volume = 0.55 },
		{ at = 0.035, pitch = 1.5, volume = 0.6 },
		{ at = 0.07, pitch = 1.68, volume = 0.65 },
		{ at = 0.105, pitch = 2, volume = 0.7 },
		{ at = 0.14, pitch = 2.25, volume = 0.75 },
		{ at = 0.175, pitch = 2.52, volume = 0.8 },
		{ at = 0.21, pitch = 3, volume = 0.9 },
		{ at = 0.245, pitch = 3.36, volume = 1 },
		-- The twinkles, fading.
		{ at = 0.36, pitch = 2.52, volume = 0.6 },
		{ at = 0.44, pitch = 3.36, volume = 0.5 },
		{ at = 0.52, pitch = 2.25, volume = 0.42 },
		{ at = 0.61, pitch = 3, volume = 0.34 },
		{ at = 0.72, pitch = 2.52, volume = 0.26 },
		{ at = 0.85, pitch = 3.36, volume = 0.18 },
	},
} :: Alert

return Sounds
