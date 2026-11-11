--!strict
-- Short number text for the HUD: 950 -> "950", 1250 -> "1.25K", 30000 -> "30K", 4500000 -> "4.5M".
-- Pure (no Roblox APIs) so the test runner can load it outside Studio.

local NumberFormat = {}

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

-- Rounds down, so a player is never shown more than they have.
local function trim(value: number, decimals: number): string
	local scale = 10 ^ decimals
	local text = string.format("%." .. decimals .. "f", math.floor(value * scale + 1e-9) / scale)
	if decimals > 0 then
		text = (text:gsub("0+$", ""))
		text = (text:gsub("%.$", ""))
	end
	return text
end

function NumberFormat.abbreviate(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	local value = math.abs(n)
	if value < 1000 then
		return sign .. tostring(math.floor(value))
	end

	local tier = math.min(#SUFFIXES, math.floor(math.log10(value) / 3))
	local scaled = value / 1000 ^ tier
	-- Guard against log10 rounding (e.g. 999999.9999 reading as tier 2).
	if scaled < 1 then
		tier -= 1
		scaled = value / 1000 ^ tier
	end

	local decimals = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
	return sign .. trim(scaled, decimals) .. SUFFIXES[tier]
end

-- Seconds as "m:ss".
function NumberFormat.clock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

return NumberFormat
