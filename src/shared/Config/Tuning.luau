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
-- the start of its zone to a quarter of the way into the next zone (Runway.fadeZ), fades out, and appears at the
-- start of its zone again, over and over until the runway closes. One that is claimed comes back on its next lap;
-- one that cracks or goes off the side comes back EGG_RESPAWN_DELAY later. So each zone always has about this many
-- lineup eggs on the runway.
Tuning.EGGS_PER_ZONE = 12
-- Seconds between lineup eggs leaving the start of their zone at sunrise: short enough for the whole lineup to be out
-- within one lap of the zone's most common egg (about 20 s in the last zone), so the zone soon has all its eggs.
Tuning.LINEUP_LAUNCH_GAP = 1.75
-- Mid-cycle drops: now and then (about every WILD_DROP_INTERVAL seconds, up to WILD_DROP_MAX on the runway at once) a
-- zone drops an extra egg that rolls once and fades. It is rolled like a lineup egg, except that every rarity from
-- WILD_RARE_FROM up is WILD_RARE_ODDS times as likely. The faster eggs roll, the sooner each one is gone, so the more
-- often they must drop to keep as many on the runway.
Tuning.WILD_DROP_INTERVAL = 13
Tuning.WILD_DROP_MAX = 5
Tuning.WILD_RARE_ODDS = 0.1
Tuning.WILD_RARE_FROM = "Secret"
-- During an Egg Avalanche, eggs drop this many times as often (and up to this many times as many per zone).
Tuning.AVALANCHE_EGG_MULTIPLIER = 2
-- Eggs appear on the ground at the start of their zone. This is the gap in studs between the zone's start line
-- and the back of a new egg.
Tuning.EGG_SPAWN_GAP = 2
-- New eggs appear at least this many studs in from where an egg would touch the side walls.
Tuning.EGG_SPAWN_EDGE_MARGIN = 4
-- When a rider runs out of stamina the egg makes one small bounce, then cracks open.
Tuning.CRACK_BOUNCE_TIME = 0.6
Tuning.CRACK_BOUNCE_HEIGHT = 2.5
-- Seconds after an egg cracks or falls off the side before the same egg appears again at the start of its zone.
Tuning.EGG_RESPAWN_DELAY = 5
-- Studs an egg is knocked back toward the middle when its rider crashes it into a wall.
Tuning.WALL_KNOCKBACK = 6

-- Riding
-- Studs per second a rider can steer the egg sideways before upgrades. Tuned with the eggs' roll speeds
-- (Config/Rarities): the faster eggs roll, the sooner the next row of obstacles arrives, so the quicker a rider has to
-- be able to move over.
Tuning.BASE_AGILITY = 31.5
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

-- Leaping. Players never walk on the runway: stepping onto it from the hub, or jumping off an egg, starts a long,
-- floaty leap, and they must land on an egg before touching the runway or before LEAP_TIME runs out.
Tuning.LEAP_TIME = 3.5
-- Upward speed at the start of a leap, and the fraction of normal gravity during it.
Tuning.LEAP_UP_SPEED = 45
Tuning.LEAP_GRAVITY = 0.2
-- Forward speed when leaping off the hub onto the runway: half as fast again as the slowest egg rolls
-- (Config/Rarities), so the leap carries a player in among the eggs rolling away from the start.
Tuning.LEAP_FORWARD_SPEED = 40.5
-- A character whose root part is lower than this above the runway is standing on it.
Tuning.STANDING_HEIGHT = 3.4
-- Extra seconds the server allows before it kills a player who is still on the runway without an egg (the
-- player's own device normally does it first, the moment they touch the runway).
Tuning.LEAP_SERVER_GRACE = 1.5
-- Seconds a rider who goes off the side through a gap falls before they die.
Tuning.FALL_OFF_TIME = 0.8

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

-- Hatching (times are per rarity, in Config/Rarities)
-- How many times as fast eggs hatch while the runway is closed.
Tuning.HATCH_BOOST = 30

-- Characters
Tuning.RESPAWN_TIME = 2
-- A character this many studs below the runway surface has fallen off and dies.
Tuning.FALL_KILL_DEPTH = 45

return Tuning
