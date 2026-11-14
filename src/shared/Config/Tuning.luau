--!strict
-- First-pass gameplay numbers that are not tied to a zone or rarity. Adjust these in playtests.
-- Pure data (no Roblox APIs) so the test runner can load it outside Studio.

local Tuning = {}

-- Stamina
Tuning.BASE_MAX_STAMINA = 100
-- Fraction of Max Stamina regained per second while not riding.
Tuning.STAMINA_REGEN_FRACTION = 0.12
-- Riding an egg to a full claim drains this fraction of the egg's stamina requirement.
-- 0.8 leaves a player who exactly meets the requirement a 20% buffer for mistakes.
Tuning.DRAIN_FRACTION = 0.8

-- Eggs
-- Radius in studs of a 1.0x egg. Eggs lie on their side and roll like a barrel.
Tuning.EGG_BASE_RADIUS = 3
-- How much longer the egg is (side to side) than its rolling diameter.
Tuning.EGG_LENGTH_RATIO = 1.3
-- How many eggs each zone rolls for its lineup at sunrise (the start of each cycle). Each lineup egg rolls from
-- its zone's chute to a quarter of the way into the next zone (Runway.fadeZ), fades out, and drops from the chute
-- again, over and over until the runway closes. One that is claimed or cracks comes back on its next lap.
Tuning.EGGS_PER_ZONE = 8
-- Seconds between lineup eggs leaving the chute at sunrise.
Tuning.LINEUP_LAUNCH_GAP = 5
-- Mid-cycle drops: now and then a zone drops an extra egg that rolls once and fades. It is rolled like a lineup egg,
-- except that every rarity from WILD_RARE_FROM up is WILD_RARE_ODDS times as likely.
Tuning.WILD_DROP_INTERVAL = 30
Tuning.WILD_DROP_MAX = 3
Tuning.WILD_RARE_ODDS = 0.1
Tuning.WILD_RARE_FROM = "Secret"
-- Studs past the start of its zone where an egg lands.
Tuning.EGG_SPAWN_OFFSET = 12
-- Eggs drop in from above when they spawn.
Tuning.EGG_DROP_TIME = 0.6
Tuning.EGG_DROP_HEIGHT = 24
-- The hop an egg makes when it is left without a rider.
Tuning.HOP_DURATION = 0.7
Tuning.HOP_HEIGHT = 5

-- Riding
-- Studs per second a rider can steer the egg sideways before upgrades.
Tuning.BASE_AGILITY = 14
-- How close (studs beyond the egg's radius) a jumping player must be for the client to ask to mount.
Tuning.MOUNT_REACH = 2.5
-- How far (studs beyond the egg's radius) the server lets the player be from the egg when it checks a mount.
-- Looser than MOUNT_REACH to forgive network delay.
Tuning.MOUNT_TOLERANCE = 16
-- Minimum seconds between mount requests the server will accept from one player.
Tuning.MOUNT_REQUEST_COOLDOWN = 0.2
-- Seconds a player cannot mount after being thrown off.
Tuning.STUN_TIME = 1.5
-- Land on a new egg within this many seconds of jumping off one to get the hop bonus.
Tuning.HOP_COMBO_WINDOW = 1.0
-- Fraction of Max Stamina refunded by a hop.
Tuning.HOP_COMBO_REFUND = 0.10
-- How often the rider's client reports its sideways position (per second).
Tuning.LATERAL_SEND_RATE = 10

-- Obstacles (see Config/Obstacles)
-- Stamina a Bump costs, as a fraction of the egg's stamina requirement.
Tuning.BUMP_STAMINA = 0.1
-- The rider's device spots hits; the server accepts its report if the egg was near the obstacle within this many
-- seconds of when the report arrived.
Tuning.HIT_REPORT_SLACK = 0.75
-- The server also checks on its own, but it only knows where the rider steered a moment ago, so it counts a hit
-- only when the egg is this many studs into the obstacle (a near miss on the rider's screen is not a hit).
Tuning.HIT_BACKUP_INSET = 4
-- How much the rider's device forgives a graze, in studs.
Tuning.HIT_GRAZE = 0.6

-- Characters
Tuning.RESPAWN_TIME = 2
-- A character this many studs below the runway surface has fallen off and dies.
Tuning.FALL_KILL_DEPTH = 45

return Tuning
