-- Everything the admin panel shows, as Fusion values. AdminController writes to these; the panel redraws itself
-- when they change. (The runway cycle comes from UiState, which the HUD keeps up to date.)

local UiState = require(script.Parent.UiState)

local scope = UiState.scope

export type InventoryLine = { kind: string, name: string, zone: number, rarity: string, count: number }
export type Inventory = { eggs: { InventoryLine }, pets: { InventoryLine }, eggCount: number, petCount: number }
export type OtherPlayer = { userId: number, name: string }

local AdminState = {
	-- Set by the server (the IsAdmin attribute); the panel only shows for admins.
	isAdmin = scope:Value(false),

	open = scope:Value(false),
	-- "Eggs" | "Pets" | "Me" | "Events" | "Teleport"
	tab = scope:Value("Eggs"),
	-- The zone picked on the Eggs and Pets tabs.
	eggZone = scope:Value(1),
	petZone = scope:Value(1),
	-- Where eggs drop: "Here" (in front of you, on the runway) or "Chute" (their zone's chute).
	dropWhere = scope:Value("Here"),

	-- The server's answer to the last command.
	status = scope:Value("Pick something to do."),
	statusGood = scope:Value(true),

	-- From the player's attributes and Workspace's.
	flying = scope:Value(false),
	flySpeed = scope:Value(80),
	walkSpeed = scope:Value(16),
	-- The server event running now ("Avalanche"), or nil.
	event = scope:Value(nil :: string?),

	inventory = scope:Value(nil :: Inventory?),
	-- Everyone else in the server, for teleporting to.
	players = scope:Value({} :: { OtherPlayer }),
}

return AdminState
