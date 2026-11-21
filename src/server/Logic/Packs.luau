--!strict
-- The rules for the shop's packs (Config/Shop): what buying one gives. Each pack holds its own pet (in a variant only
-- packs give), dollars, a Max Stamina boost kept for good (the biggest pack's counts; they do not add up), a trail
-- only that pack gives, revives, and sometimes a server luck boost (ShopService starts that one, since it is the
-- whole server's). A player can buy each pack once.
--
-- Like the other rules in Logic/, this works on a player's saved data with no players, parts or remotes, so it is
-- covered by tests outside Studio. ShopService runs it when a purchase goes through.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Shop = require(Shared.Config.Shop)

local Hatchery = require(script.Parent.Hatchery)
local Revives = require(script.Parent.Revives)
local Stalls = require(script.Parent.Stalls)

local Packs = {}

-- Whether the player has bought this pack.
function Packs.owns(data, packId: string): boolean
	return data.Packs ~= nil and data.Packs[packId] == true
end

-- Gives the player everything in a pack, apart from its server luck. `petUid` is the new pet's id. Returns the pet
-- given (it goes into the pen if there is room).
function Packs.grant(data, pack: Shop.Pack, petUid: string, now: number): Hatchery.Pet?
	data.Packs = data.Packs or {}
	data.Packs[pack.id] = true

	data.Dollars += pack.dollars
	data.PackStamina = math.max(data.PackStamina or 1, pack.stamina)
	Stalls.giveTrail(data, pack.trail)
	Revives.add(data, pack.revives)

	local origin = Shop.petOrigin(pack.pet.kind)
	if origin == nil then
		return nil
	end
	local pet: Hatchery.Pet = {
		uid = petUid,
		kind = pack.pet.kind,
		egg = origin.egg,
		zone = origin.zone,
		rarity = origin.rarity,
		variant = pack.pet.variant,
		inPen = false,
		hatchedAt = now,
	}
	table.insert(data.Pets, pet)
	Hatchery.discover(data, pet)
	Hatchery.setInPen(data, pet.uid, true)
	return pet
end

return Packs
