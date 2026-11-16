--!strict
-- Who gets the admin panel in a live game. While testing in Roblox Studio everyone does.
--
-- The experience's owner always does: the user who owns it or, if a community (group) owns it, its members with a
-- rank of GROUP_RANK or more (255 is the community's owner; lower it to let other roles in too).
-- Kept on the server only, so players cannot read who the admins are.

local Admins = {}

-- Roblox user IDs of anyone else who should be an admin, for example { 123456789, 987654321 }.
-- A user's ID is the number in the address of their profile page: roblox.com/users/<ID>/profile
Admins.UserIds = {} :: { number }

Admins.GROUP_RANK = 255

return Admins
