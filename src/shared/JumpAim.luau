--!strict
-- Landing on eggs without pixel-perfect timing: which egg a player in the air is heading for, and the "magnet" that
-- draws them onto it once they are close. RideController uses it every frame while the local player is in the air,
-- and EggController draws a red circle round the egg it picks.
-- Pure math (no Roblox APIs) so the test runner can load it outside Studio.
--
-- Aiming: a jumping player follows a curve (their speed, with gravity pulling them down). The egg they are heading
-- for is the one nearest the spot where that curve comes down to the height they would sit on it, measured where the
-- egg will be by then (eggs roll on while the player falls). It must be within Tuning.JUMP_AIM_RANGE of that spot.
--
-- The magnet: once the player is within Tuning.JUMP_MAGNET_RANGE of that egg across the ground (and not far above
-- it), they are drawn onto it. They move with the egg, plus a pull toward its top that closes in quickly but
-- smoothly, so it reads as being drawn in rather than snapped. Once on top, the usual mount request goes to the
-- server.

local JumpAim = {}

-- A player in the air: where they are, how fast they are going, and how hard gravity pulls them down (studs per
-- second squared; their leap is floaty). Speed and gravity 0: judged from where they are now.
export type Jumper = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	gravity: number,
}

-- An egg they could land on: where it is now, the height a rider sits at on top of it, how fast it rolls down the
-- runway (+z), and its footprint (halfLength across the runway, radius along it).
export type Target = {
	id: number,
	x: number,
	z: number,
	seatY: number,
	speed: number,
	halfLength: number,
	radius: number,
}

-- Seconds until something at height `y`, rising at `vy`, comes down to `height` under `gravity`. Something below
-- that height that will never rise to it is judged where it is now (0), as is anything with no gravity.
function JumpAim.timeToHeight(y: number, vy: number, gravity: number, height: number): number
	if gravity <= 0 then
		return 0
	end
	-- y + vy t - gravity t^2 / 2 = height, on the way down.
	local discriminant = vy * vy + 2 * gravity * (y - height)
	if discriminant < 0 then
		return 0
	end
	return math.max(0, (vy + math.sqrt(discriminant)) / gravity)
end

-- How far a spot on the ground is outside an egg's footprint, `dx` across and `dz` along the runway from its middle.
-- 0 inside it.
function JumpAim.footprintGap(dx: number, dz: number, halfLength: number, radius: number): number
	local outX = math.max(0, math.abs(dx) - halfLength)
	local outZ = math.max(0, math.abs(dz) - radius)
	return math.sqrt(outX * outX + outZ * outZ)
end

-- How far from an egg's footprint the jumper will come down, looking no more than `lookahead` seconds ahead.
function JumpAim.miss(jumper: Jumper, egg: Target, lookahead: number): number
	local t = math.min(JumpAim.timeToHeight(jumper.y, jumper.vy, jumper.gravity, egg.seatY), lookahead)
	local landX = jumper.x + jumper.vx * t
	local landZ = jumper.z + jumper.vz * t
	local eggZ = egg.z + egg.speed * t
	return JumpAim.footprintGap(landX - egg.x, landZ - eggZ, egg.halfLength, egg.radius)
end

-- The egg the jumper is heading for: the one they will come down nearest, if that is within `range` of it.
-- `currentId` is the egg picked last frame; another only takes over if it is `switchMargin` nearer, so the pick does
-- not flicker between two eggs side by side.
function JumpAim.pick(
	jumper: Jumper,
	eggs: { Target },
	currentId: number?,
	range: number,
	switchMargin: number,
	lookahead: number
): number?
	local bestId: number? = nil
	local bestMiss = math.huge
	local currentMiss = math.huge
	for _, egg in eggs do
		local miss = JumpAim.miss(jumper, egg, lookahead)
		if miss <= range then
			if miss < bestMiss then
				bestId, bestMiss = egg.id, miss
			end
			if egg.id == currentId then
				currentMiss = miss
			end
		end
	end
	if currentId ~= nil and currentMiss <= bestMiss + switchMargin then
		return currentId
	end
	return bestId
end

-- Whether the jumper is close enough to the egg for the magnet to take hold: within `range` of its footprint across
-- the ground, no more than `height` above where they would sit on it, and no lower than its middle.
function JumpAim.inMagnetRange(jumper: Jumper, egg: Target, range: number, height: number): boolean
	local above = jumper.y - egg.seatY
	if above > height or jumper.y < egg.seatY - egg.radius - 2 then
		return false
	end
	return JumpAim.footprintGap(jumper.x - egg.x, jumper.z - egg.z, egg.halfLength, egg.radius) <= range
end

-- The velocity that draws the jumper onto the egg: the egg's own (rolling down the runway), plus a pull toward its
-- top of `gain` times the distance per second, at most `maxSpeed`.
function JumpAim.pull(jumper: Jumper, egg: Target, gain: number, maxSpeed: number): (number, number, number)
	local dx, dy, dz = egg.x - jumper.x, egg.seatY - jumper.y, egg.z - jumper.z
	local px, py, pz = dx * gain, dy * gain, dz * gain
	local size = math.sqrt(px * px + py * py + pz * pz)
	if size > maxSpeed then
		local scale = maxSpeed / size
		px, py, pz = px * scale, py * scale, pz * scale
	end
	return px, py, pz + egg.speed
end

return JumpAim
