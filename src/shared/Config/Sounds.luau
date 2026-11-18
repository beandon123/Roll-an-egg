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
	-- When each note plays (seconds after the alert starts) and how high (1 = as recorded).
	notes: { { at: number, pitch: number } },
}

-- Everyone in the server hears this when a Secret or rarer egg spawns: three rising chimes, twice over.
Sounds.SECRET_ALERT = {
	id = "rbxasset://sounds/electronicpingshort.wav",
	volume = 0.9,
	length = 2,
	notes = {
		{ at = 0, pitch = 1 },
		{ at = 0.16, pitch = 1.26 },
		{ at = 0.32, pitch = 1.5 },
		{ at = 0.62, pitch = 1 },
		{ at = 0.78, pitch = 1.26 },
		{ at = 0.94, pitch = 1.5 },
	},
} :: Alert

return Sounds
