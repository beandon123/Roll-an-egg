# Roll an Egg

This is the agreed game design and build request. It is the source of truth for what gets built.
Items marked (decided) were confirmed by the game's owner; items marked (proposed) are defaults that can still change.

## Game Description
Genre: Skill-based obstacle runner + collect-and-hatch plot tycoon, with light PvP.

Core loop:
1. One long straight runway passes through five zones in order: Forest, Desert, Snow, Ocean, Volcano.
   Anyone can go anywhere; deeper zones drop rarer, bigger eggs that need more stamina to hold on to.
2. The runway runs in 3-minute cycles: eggs drop and roll, then the runway closes for 10 seconds. Every egg without a
   rider disappears, every nest hatches 30x faster, and a fresh lineup of eggs starts.
3. Players chase eggs on foot or riding a pet and jump on. While riding they steer to dodge obstacles as stamina drains,
   staying on to fill the Claim meter. If their stamina is below the egg's requirement, they'll fall off before claiming it.
   Leaving an egg makes it bounce and crack; rarer eggs survive more bounces.
4. Another player can jump onto the same egg to challenge the rider -> a rhythm-tap duel graded Perfect / Great / Good / Poor;
   the better score wins. A winning challenger steals the egg and its progress, but must have the stamina to cover it.
5. Claimed eggs go straight to inventory. Players place them in nests in their pet pen; eggs hatch over real time,
   including while offline.
6. Hatched pets roam the pen, earn coins, and double as rideable mounts. Rarer pets earn more and run faster.
7. Coins (from pets, and from selling unwanted eggs and pets at the hub) buy upgrades (above all Max Stamina),
   stamina-boosting trails, and zone teleports -> hold on to bigger, rarer eggs deeper down the runway -> better pets.

Session length: 15-30 min target. First claimed egg in under 60 s, first hatch in about 2 min.

What makes it unique: a "rodeo on a rolling egg." Every ride is a race between your claim meter and your stamina while
dodging obstacles, and every time you leave an egg it cracks a little more. The runway is shared and live, so any
unlocked egg can be stolen mid-ride in a rhythm duel. The world changes as you roll deeper, and so does the prize:
Forest up to Legendary, Desert up to Mythic, Snow and Ocean up to Secret, Volcano up to Eternal.
Original theme, art, and creatures.

## Target Audience
- Ages 8-14 (core 9-12) -> full under-13 compliance
- Casual players + light grinders; social through the shared runway, duels, and server events
- Platforms: Mobile-first (touch), PC (keyboard/mouse), Console (gamepad). VR not supported.
- Server size: 8 players / 8 plots

## Desired Features
### Runway & Zones
- [ ] One straight runway (~3,000 studs) holding five zones in order (decided): 1 Forest, 2 Desert, 3 Snow, 4 Ocean,
      5 Volcano; ends at a cliff after the Volcano; more zones added later (decided)
    - [ ] Anyone can walk or ride into any zone (decided); the scenery, music, and obstacles change zone by zone
    - [ ] Hub + all 8 plots at the start of the runway; players spawn at their plot (see Hub below)
    - [ ] Zone signposts show the stamina you'll want for that zone's eggs
- [ ] Teleport pads at the hub, one per zone, bought with coins (decided)
    - [ ] Bought in order (Desert, then Snow, then Ocean, then Volcano); prices rise steeply so they track progress
          (decided; exact prices set during economy tuning)
- [ ] Each zone has an egg chute at its start; eggs roll on down the runway from there and keep their own zone's
      rarity and stamina requirement wherever they roll
- [ ] Zone rarity caps (decided):
    - [ ] Forest: Common-Legendary
    - [ ] Desert: Common-Mythic
    - [ ] Snow: Common-Secret (1 Secret pet)
    - [ ] Ocean: Common-Secret (2 Secret pets)
    - [ ] Volcano: Common-Eternal (1 Secret + 1 Eternal pet)
- [ ] Eggs: lineup rolled per zone at the start of each cycle; down-runway movement fixed by spawn time (decided);
      ~8 active eggs per zone (12 during Egg Avalanche)
- [ ] Egg lifecycle
    - [ ] Never jumped on: fades out after ~60 s (decided)
    - [ ] Jumped on: loses a bounce each time it's left with no rider; cracks and splats at 0 (see Riding)
    - [ ] An egg going over the cliff at the end splats, along with its rider
    - [ ] At each runway closure, every egg without a rider disappears; ridden eggs stay and keep rolling (decided)
- [ ] Rarities: Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret, Eternal (decided) + Titan Egg (event) + Robux egg
    - [ ] Rarer eggs are bigger and need more stamina (decided)
    - [ ] Readable from a distance: zone-themed shell + rarity color/glow/particles + size; icon/shape for colorblind players
    - [ ] Secret and Eternal pets show as "???" in the collection book until hatched (proposed)
    - [ ] Server-wide announcement when a Legendary+ egg is in the cycle's lineup

First-pass egg tuning by rarity (same in every zone; adjust in playtests):

    Rarity     Size   Claim time  Roll speed  Bounces  Duel (beats @ tempo)
    Common     1.0x   5 s         12 st/s     1        6 @ 90 bpm
    Uncommon   1.1x   7 s         13 st/s     1        6 @ 100 bpm
    Rare       1.25x  9 s         14 st/s     2        8 @ 110 bpm
    Epic       1.4x   12 s        16 st/s     2        8 @ 125 bpm
    Legendary  1.6x   15 s        17 st/s     3        10 @ 135 bpm
    Mythic     1.8x   18 s        19 st/s     3        10 @ 150 bpm
    Secret     2.0x   22 s        20 st/s     3        12 @ 160 bpm
    Eternal    2.3x   26 s        21 st/s     4        12 @ 170 bpm

First-pass stamina requirement per egg (base Max Stamina 100; zone baselines 500 / 2,000 decided, rest proposed):

    Zone        Common  Uncommon  Rare    Epic    Legendary  Mythic   Secret   Eternal
    1 Forest    50      80        120     200     350        -        -        -
    2 Desert    500     650       850     1,100   1,400      1,800    -        -
    3 Snow      2,000   2,500     3,200   4,000   5,000      6,200    7,500    -
    4 Ocean     8,000   10,000    12,500  16,000  20,000     25,000   30,000   -
    5 Volcano   35,000  45,000    55,000  70,000  85,000     100,000  125,000  150,000

    Riding drains 80% of the egg's requirement over its claim time; bumps cost extra.
    Meeting the requirement leaves a 20% buffer for mistakes; below it, you fall off before the claim finishes.

### Runway Cycle (decided)
- [ ] Every 3 min the runway closes for 10 s, then a new cycle starts with a fresh egg lineup
- [ ] 10 s on-screen warning before each closure (proposed)
- [ ] At closing: every egg without a rider disappears; anyone riding stays on and keeps going; players stay on the track
    - [ ] An egg that loses its rider during the closure disappears too (proposed)
- [ ] During the 10 s closure every nest in the server hatches 30x faster (10 s = 5 min of hatch progress)
- [ ] HUD shows the time left until the runway closes

### Hub (decided; layout based on the owner's reference screenshot)
- [ ] One grass plaza behind the start of the runway, walled in; seen from the start zone looking back into the hub:
    - [ ] START ZONE pad where the runway leaves the hub
    - [ ] Trails shop stall on the left and Sell stall on the right, facing each other across the plaza near the start
          zone (the reference's "Auras" stall became the Trails shop; "Sell Dinos" became just "Sell")
    - [ ] Fuse machine in the middle, between and behind the two stalls (a golden "?" egg on a pedestal)
    - [ ] Shared spawn behind the fuse machine, facing the runway (used until plots are assigned on join; then
          players spawn at their own pen)
    - [ ] The 8 pens round the plaza: 3 down each side and 2 at the back, gates facing the plaza
    - [ ] Large mountains surround the pens and the hub on every side; the only way out is the runway
- [ ] Each station opens its panel from a prompt (tap on mobile, E on keyboard, X on gamepad); walking away closes it
- [ ] Final art for the stalls, fuse machine, pens and mountains (placeholder parts for now)

### Hub Stations
- [ ] Trails shop (decided): buy trails with coins; the equipped trail streams behind your character and multiplies
      your Max Stamina while equipped
    - [ ] Bought once, kept for good; one equipped at a time; a newly bought trail is equipped unless the current one
          boosts more (proposed)
    - [ ] First-pass trails (proposed; tune with the economy):

          Trail       Price    Max Stamina
          Leaf        100      x1.2
          Sunbeam     500      x1.5
          Sandstorm   2.5K     x2
          Frost       15K      x3
          Bubble      75K      x4.5
          Ember       400K     x6
          Rainbow     2.5M     x8

    - [ ] Trails stack with Max Stamina upgrades once those are built (upgrades x trail)
- [ ] Sell stall (decided): sell eggs or pets you don't want, for coins
    - [ ] Eggs: sell 1 or all of a kind; an egg is worth half its stamina requirement (proposed: Forest Common 25,
          Desert Mythic 900, Volcano Eternal 75K)
    - [ ] Pets: once hatching exists (price by zone, rarity and variant; set during economy tuning)
- [ ] Fuse machine (decided): put in 3 of the same pet -> get that pet's egg
    - [ ] Proposed details: the 3 pets must be the same species and variant; the egg is that pet's zone + rarity egg,
          goes to inventory, and hatches normally (a fresh roll of that tier's pets and of Golden/Rainbow), so spare
          duplicates become another try at the pets you are missing
    - [ ] Built together with pets and hatching (until then its panel only explains it)

### Riding & Claiming
- [ ] Mount: anyone can jump onto any egg (decided) -> riding pose; one rider per egg (Titan Egg excepted);
      the server decides who landed first
    - [ ] The egg's stamina requirement is shown on it; below it, you'll fall off before claiming (decided)
- [ ] Riding is steering only (decided): move left/right across the runway width to dodge obstacles; no taps while riding
    - [ ] Agility upgrade increases steering speed
- [ ] Stamina drains while riding (see table) and regenerates on foot or on a pet
- [ ] Claim meter fills while you stay on; 100% = "CLAIMED!" -> egg flies into inventory
- [ ] Obstacle tiers (decided): Bump (lose a chunk of stamina + wobble) / Knock-off (thrown off) / Lethal (death)
    - [ ] Zone-themed obstacles (proposed): Forest: rolling logs, swinging vines; Desert: tumbleweeds, sand geysers;
          Snow: giant snowballs, ice patches (slide sideways); Ocean: crashing waves, snapping clams;
          Volcano: lava bursts (lethal), falling rocks; every obstacle is telegraphed before it arrives
- [ ] Leaving an egg (decided)
    - [ ] Whenever an egg is left with no rider (jumped off, knocked off, out of stamina, rider died), it bounces once
          in the air and loses a bounce; at 0 bounces it cracks and splats
    - [ ] Bounces by rarity (decided for now): Common/Uncommon 1, Rare/Epic 2, Legendary/Mythic/Secret 3, Eternal 4
    - [ ] An egg with bounces left keeps rolling, and anyone can jump on (claim progress starts from 0)
- [ ] Thrown off (stamina at 0, knock-off obstacle, losing a duel): ragdoll + 1.5 s stun, claim progress lost
- [ ] Death (lethal obstacle, falling off the runway's side edge, riding over the end cliff, resetting): cartoon splat,
      respawn at your plot; current ride lost; no coins or items lost
- [ ] Egg-to-egg hopping: progress resets on the new egg; landing within 1 s of leaving the last one refunds 10% stamina
      and builds a hop-combo counter (the egg you left still loses a bounce)
- [ ] Claim feedback: burst VFX, fanfare, "+1 RARE EGG" popup

### Egg Duels (PvP)
- [ ] Jumping onto an egg someone else is riding starts a duel while their claim is under 75% (decided);
      at 75%+ the egg is "Locked In" and challengers bounce off
- [ ] Anyone can challenge (decided), whatever their stamina
- [ ] Rhythm-tap duel (decided): both players get the same beat pattern; each beat graded Perfect / Great / Good / Poor
    - [ ] Points: Perfect 3, Great 2, Good 1, Poor 0; a missed beat or a mashed tap counts as Poor
    - [ ] Highest total wins; ties go to the defender
    - [ ] Beat count + tempo scale with egg rarity (table above): about 4-5 s per duel after a 1.5 s "Ready..." intro
    - [ ] Timing windows (first pass): Perfect +/-45 ms, Great +/-90 ms, Good +/-140 ms, anything else Poor
    - [ ] Stamina and upgrades play no part in the duel itself (decided)
- [ ] During the duel: claim progress and stamina drain pause; the egg keeps rolling but ignores obstacles;
      duels can't start in the last 100 studs before the end cliff
- [ ] A winning challenger takes over with the defender's progress -> "STOLEN!" (decided); loser is thrown off
      (stun, not death); the egg doesn't lose a bounce because it still has a rider
    - [ ] On takeover, the winner immediately pays the stamina for the progress they inherited; if they can't cover it,
          they're thrown off (decided), so low-stamina players can win duels but can't keep high-tier eggs
- [ ] Anti-grief: 15 s challenge cooldown per player; can't challenge the same player again for 30 s;
      tutorial eggs and players still in the tutorial can't be challenged
- [ ] Server announcements: "Alex stole a Legendary egg from Sam!"

### Pets
- [ ] Each pet: species, zone, rarity, variant (Normal / Golden / Rainbow mutation chance on hatch), Income/sec, Mount Speed
    - [ ] Each zone's pets out-earn the zone before it (a new zone's Commons roughly match the previous zone's best)
- [ ] Mounts: equip one pet as your active mount; summon/unsummon from the HUD
    - [ ] Riding a pet sets your run speed to its Mount Speed
    - [ ] Jump from your pet onto an egg; the pet unsummons; 3 s resummon cooldown after leaving the egg
    - [ ] The mounted pet keeps earning while you ride it (decided)
- [ ] Starter pet (a Forest Common) given during the tutorial so new players learn mounting early
- [ ] 8 pets per zone (decided), themed to their zone, more fantastic deeper down -> 40 core pets at launch;
      more zones and pets added later (decided)
- [ ] 1 Robux egg with 5 unique pets on top of the core set (decided) -> 45 pets at launch; event pets later
- [ ] All pets rideable, built on ~7 shared skeletons (four-legged, two-legged, winged, low-slung, many-legged,
      floating/swimming for Ocean pets, special) so animations are reused
- [ ] Sell pets for coins; pet inventory cap (upgradeable)

Draft roster (edit freely; Robux-egg pets designed during the art phase):

    1 Forest:   Common: Bunny, Squirrel | Uncommon: Fox, Hedgehog | Rare: Owl, Deer | Epic: Bear
                Legendary: Moss Stag
    2 Desert:   Common: Lizard, Meerkat | Uncommon: Fennec Fox, Armadillo | Rare: Camel | Epic: Giant Scorpion
                Legendary: Pharaoh Jackal | Mythic: Sphinx
    3 Snow:     Common: Penguin, Snow Hare | Uncommon: Arctic Fox | Rare: Reindeer | Epic: Woolly Mammoth
                Legendary: Sabertooth Cat | Mythic: Yeti | Secret: Frost Dragon
    4 Ocean:    Common: Hermit Crab | Uncommon: Sea Turtle | Rare: Dolphin | Epic: Manta Ray | Legendary: Narwhal
                Mythic: Kraken | Secret: Leviathan, Hippocampus
    5 Volcano:  Common: Fire Salamander | Uncommon: Magma Toad | Rare: Obsidian Goat | Epic: Cinder Boar
                Legendary: Cerberus | Mythic: Chimera | Secret: Magma Dragon | Eternal: Eternal Phoenix

### Plot & Pen
- [ ] 8 plots around the hub; assigned on join, released on leave; plots can't be raided
- [ ] One pet pen per plot (decided)
    - [ ] Capacity: 10 pets at Pen Level 1, +1 per level, up to 18 for now (decided)
    - [ ] Each level bought with coins, or buy the next level with Robux (decided)
    - [ ] Every pet in the pen roams freely
    - [ ] Nests inside the pen: place eggs here to hatch; start with 2, buy up to 10
    - [ ] Hatched pets pop out of the nest and start roaming
    - [ ] Coins pile up at the pen's collect pad; walk over it to collect
- [ ] Hatch times: Common 30 s, Uncommon 2 m, Rare 5 m, Epic 15 m, Legendary 45 m, Mythic 2 h, Secret 4 h, Eternal 6 h
      (Titan/Robux eggs set per egg)
    - [ ] Hatching continues offline at normal speed; 30x during each runway closure while you're in a server (decided);
          that works out to ~2.6x faster while online (e.g., Legendary ~17 min)
    - [ ] Hatch animation + rarity reveal on completion
- [ ] Getting home (decided): ride back up, or reset/die to respawn at your plot (~2 s)
    - [ ] Optional on-screen Reset shortcut, because Roblox's built-in reset is buried in the menu on mobile

### Progression
- [ ] Single soft currency: Coins
- [ ] Upgrades: Max Stamina (main progression stat: lets you hold on to bigger eggs deeper down), Stamina Regen,
      Agility, Run Speed, Jump, Nests, Pen Level, Hatch Speed, Inventory Size
- [ ] Trails from the Trails shop multiply Max Stamina (see Hub Stations)
    - [ ] Costs rise steeply; big numbers shown abbreviated (1.2K, 30K, 4.5M)
- [ ] Zone teleport pads bought with coins, in order (decided)
- [ ] Collection book (index) with per-rarity, per-zone, and full-completion rewards
- [ ] Rebirth: on hold for now (decided); first candidate for a post-launch update

### Onboarding / FTUE
- [ ] Guided first ride in the Forest on a slow tutorial egg (guaranteed claim) that teaches steering and stamina
- [ ] Practice duel against an NPC coach that teaches Perfect / Great / Good / Poor timing
- [ ] Arrow to your plot -> place egg in a nest -> 30 s hatch -> starter pet -> teaches mounting and pet income
- [ ] First runway closure explained with a quick popup ("Nests hatch 30x faster right now!")
- [ ] First time a player tries an egg above their stamina, a tip explains the requirement number
- [ ] Tutorial unlocks HUD elements step by step; skippable for returning players

### Retention
- [ ] Daily login streak rewards
- [ ] Playtime gifts (5 / 10 / 20 / 30 min)
- [ ] Daily quests (e.g., claim 5 eggs, win 2 duels, claim a Desert egg, hatch 2 Rares, get 3 Perfects in one duel)
- [ ] Offline earnings (capped) + "Welcome back" summary
- [ ] Global leaderboards: eggs claimed, eggs stolen, total coins, rarest hatch
- [ ] Community-join reward; opt-in Roblox experience notifications ("Your Mythic egg hatched!")

### Server Events (decided: Titan Egg + Egg Avalanche; Shiny Hour on hold)
- [ ] Rotation (decided): each event happens once an hour, alternating every 30 min
      (Titan Egg on cycle 0 of every 20, Egg Avalanche on cycle 10); HUD shows the next event's countdown
- [ ] Titan Egg: a much larger egg that can land in any zone, with an equal chance per zone (decided)
    - [ ] Announced 60 s ahead with a map marker showing where it will land; zone-themed giant shell
    - [ ] Up to 4 players ride it together and share one claim meter; no duels; 5 bounces
    - [ ] Riders' stamina drains at that zone's Common rate (decided)
    - [ ] Everyone still on at 100% gets a Titan egg that can only hatch pets from that zone,
          with odds tilted toward the zone's rarer pets (decided)
- [ ] Egg Avalanche: once an hour, one full cycle with 2x eggs in every zone (decided)

### Social
- [ ] Egg duels + steal announcements (above)
- [ ] Friends-in-server luck bonus
- [ ] Trading: not planned (decided)

### Monetization
- [ ] Robux egg (decided): 1 premium egg with 5 unique pets, bought in the shop, goes straight to inventory
    - [ ] It never appears on the runway, so a paid egg can't be stolen or cracked
    - [ ] Odds shown before purchase; hidden where PolicyService reports paid random items are restricted
- [ ] Game passes: VIP (tag + x1.5 coins), x2 Coins, +2 Nests, Auto-Collect, Faster Hatch, Lucky (better Golden/Rainbow
      chance on hatches)
- [ ] Developer products: Next Pen Level (decided), Instant Hatch, Server Luck boost (helps everyone), Call the Titan
      (an extra Titan Egg for the server, limited frequency), coin packs
- [ ] Premium player perk + Premium payouts
- [ ] Nothing sold affects duels; they're decided by timing alone

## Design Requests
- [ ] Art style: original, bright, stylized low-poly cartoon
- [ ] All 3D art made by Claude in Blender (decided): pets, eggs, obstacles, zone kits, hub, plots, pens, nests,
      teleport pads
    - [ ] Hub: Trails stall, Sell stall, fuse machine, pens, low-poly mountains (placeholders are built from parts)
    - [ ] Eggs: one base shape x zone material (moss, sandstone, ice, coral, obsidian) x rarity color/glow/size
          (33 combinations), plus 5 zone-themed Titan Eggs and the Robux egg; bounce squash + crack + cartoon yolk splat
          (no gore)
    - [ ] Pets: 40 core + 5 Robux-egg pets, all rideable; shared skeletons with identical bone names;
          animations per skeleton: idle, walk (or swim), run, jump, ride pose
    - [ ] Pet portraits rendered in Blender for inventory, shop, and collection book icons
    - [ ] Built in batches that follow the roadmap
- [ ] Map: hub (plaza with the start zone, Trails stall, Sell stall, fuse machine, 8 pens round it, ringed by
      mountains; see Hub) and the teleport pads at the start -> one straight runway: Forest -> Desert -> Snow
      -> Ocean (a causeway over a shallow reef) -> Volcano -> end cliff; each zone has its own palette, props, lighting,
      and music, with a smooth blend where zones meet
- [ ] Runway closure moment: horn, eggs without riders pop and vanish in a wave, nests glow and pulse during the 30x hatch
- [ ] UI/UX: mobile-first, large touch targets; main HUD = coins, stamina, inventory, shop, index, mount, Reset shortcut,
      runway-closing timer, next-event timer
    - [ ] Riding HUD (only while riding): stamina bar, claim meter, bounces-left pips, obstacle warning markers
    - [ ] Marker above every egg: its stamina requirement, green if you have enough and red if not;
          above ridden eggs: crossed swords = you can challenge, gold lock = Locked In (75%+)
    - [ ] Duel UI: both players shown wrestling on the egg; beat track at center screen; Perfect/Great/Good/Poor pop-ups;
          live scores side by side; result banner (shows the stamina cost of a steal)
    - [ ] Mobile: left thumb steers, right thumb has Jump; during a duel the right half of the screen becomes the tap area
    - [ ] Keyboard/gamepad prompts swap automatically by input type
- [ ] Audio (proposed: licensed tracks and sounds from Roblox's Creator Store): music per zone; rolling rumble;
      bounce boing + crack; per-rarity cues; claim fanfare; duel beat track + grade sounds; splat; closing horn;
      Titan Egg alarm
- [ ] VFX: rarity glows, dust trails, bounce/crack, claim burst, splat, hatch reveal, duel flash, Titan Egg landing,
      closure pop wave
- [ ] Accessibility: rarity icons as well as colors; reduce camera shake; haptics toggle; duel timing calibration;
      duels playable with sound off (visual beat first)

## Technical Notes
- Toolchain: Rojo + StyLua + Selene, code in this git repo; Fusion and ProfileStore are committed under `vendor/`
  (see `vendor/README.md`)
- Structure:
    - ReplicatedStorage/Shared: Config (zones, rarity tuning, stamina requirements, spawn odds per zone, hatch times,
      upgrade and teleport costs, trails, sell prices, obstacles, pets, events), HubLayout (where every station, pen
      and mountain is), Types, EggMotion (down-runway position from time + bounce
      events), ObstacleTimeline, DuelChart (beat pattern from a seed), NumberFormat (1.2K / 4.5M), Net
    - ServerScriptService/Server/Services: Data, Cycle, Runway, Zone, Teleport, Ride, Duel, Plot, Pen, Hatch, Pet,
      Fuse, Economy, Shop (trails + selling), Quest, Event, Leaderboard, AntiCheat
    - StarterPlayerScripts/Client/Controllers: Ride, Steering, Duel, Mount, Pen (roaming), Camera, Input, UI, VFX, Sound
    - UI: Fusion
- Persistence (decided): ProfileStore with session locking; versioned schema + migrations; store timestamps
  (placedAt, lastCollect), never running timers; pets stored with unique IDs; teleport pads and trails owned
- Hub stations: buying, equipping, selling and fusing are decided on the server; clients ask with the item's id and
  are told the result; never prices, coins or stamina; per-player rate limit
- Runway cycle: CycleService derives the cycle number and phase (open / warning / closed) from the server clock, so every
  client and late joiner agrees; at each cycle start the server rolls each zone's egg lineup and sends it to clients;
  at closure it removes every egg without a rider
- Closure hatch boost: at each closure the server adds 290 s of bonus progress (29 x 10 s) to every nest of players
  in that server; stored on the nest, so hatch math stays timestamp-based
- Egg motion (decided): down-runway position = EggMotion(serverTime - spawnTime), fixed by time; side-to-side position is
  steered by the rider: the rider's client predicts it and sends updates ~10x/s, the server caps them at the rider's
  Agility speed and replicates them; riderless eggs hold their last side-to-side position; bounces are recorded as timed
  events so every client plays the same hop; clients only render eggs in zones near them
- Riders on eggs: each client attaches rider characters to its own local copy of the egg (the server publishes who rides
  which egg), so riders don't drift off eggs on other players' screens
- Obstacle hits: client detects hits for instant feedback; the server runs a rough backup check (known obstacle timeline
  vs. the rider's side-to-side position) so cheaters can't ignore hits; near-misses within lag tolerance go to the client
- Ride validation: server owns ride sessions, stamina drain, and claim math; enforces each rarity's minimum claim time;
  mounting is checked against the egg's computed position + player position (with lag tolerance)
- Duels: the server checks the 75% lock when a challenge starts; picks the beat-pattern seed and a start time on the
  shared server clock; each client plays the pattern locally and sends its tap timestamps; the server grades every tap and
  totals the points itself, so connection speed doesn't decide the winner; ties go to the defender; on takeover the server
  charges the inherited-progress stamina; accounts with inhumanly perfect timing across many duels get flagged
- Teleport pads: purchase checked and recorded on the server; the server performs the teleport only for owned pads
- Events: EventService schedules the Titan Egg on cycle 0 of every 20 and Egg Avalanche on cycle 10 (each once an hour);
  the server picks the Titan's zone and drop spot and announces them ahead of time
- Movement checks: Roblox lets each client move its own character, so the server samples positions ~4x/s and pulls back
  anything faster than the current mount/egg speed + tolerance (lag-aware to avoid false positives)
- Remotes: one Net module; type and range checks; per-player rate limits; client never sends currency, rarity, or time values
- Purchases: ProcessReceipt records each handled purchase ID in the player's profile, so every Robux purchase is granted
  exactly once even if a server crashes mid-purchase; one developer product per pen level (developer product prices are fixed)
- Hatching & income: calculated from timestamps (plus closure bonus) on demand; offline earnings capped
- Pens: roaming is cosmetic and runs only on each player's device (the server only stores which pets are in the pen);
  up to 18 pets x 8 pens; only nearby pens animate; distant pets freeze or switch to low-detail models
- StreamingEnabled on: client code tolerates parts that haven't loaded yet; hub, plots, teleport pads, and zone signposts
  set to Persistent
- Performance: reuse egg/VFX objects; cap active eggs per zone; eggs <= 1k triangles, pets <= 4k triangles with LODs;
  VFX on players' devices only; test on low-end mobile
- Art pipeline: Claude scripts models in Blender (Python) -> shared skeletons -> FBX -> import/upload to Roblox ->
  asset IDs in Shared/Config/Assets; meshes can't sync through Rojo, so models live in the repo as .rbxm files that
  reference uploaded assets; uploads happen under the community, either by importing in Studio or with an
  Open Cloud upload script (needs an API key)
- Ownership (decided): a Roblox Community (formerly called a Group) owns the experience, meshes, and animations
  (by default Roblox only plays animations owned by the experience's owner)
- Analytics: AnalyticsService funnel for tutorial steps + economy sources/sinks; first claim per zone; teleport purchase
  timing; duel win rates and grade spread; falls from low stamina; deaths and knock-offs by zone and obstacle

## Other Notes
- IP: same genre and mechanics as similar Roblox games; all names, art, creatures, map, and UI are original;
  no dinosaurs in the launch roster, so the game stands apart
- Under-13 compliance: TextService filtering on any player text (e.g., pet nicknames); PolicyService checks;
  no off-platform links; complete Roblox's maturity questionnaire; splats stay cartoonish
- Roadmap:
    - MVP (internal playtest, placeholder art): Forest + Desert zones, runway cycle + closures, steering rides,
      obstacles, bounces/cracking, claiming, rhythm duels, pen + nests + hatching, ~6 pets with mounting, coins,
      core upgrades, saving, tutorial
    - Launch: all 5 zones, 40 core pets + Robux egg (5 pets), teleport pads, final art, retention features,
      Titan Egg + Egg Avalanche, monetization, compliance pass, analytics
    - Post-launch: more zones and pets (8 per zone), rebirth, Shiny Hour, event pets, more pen levels, seasonal events
