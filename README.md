# Roll an Egg

A Roblox game: eggs roll down a long shared runway, players jump on and ride them to claim them, then hatch them
into pets back at their plot. The full design is in [docs/REQUEST.md](docs/REQUEST.md).

## What works so far

The first playable slice: **the runway, riding, hatching and pens**, plus **the shop, settings and admin panel**.

- The map: the hub with a painted START ZONE where the runway begins, then a long runway that winds from side to
  side and rolls over hills through six zones (Forest, Desert, Snow, Ocean, Volcano, Prehistoric). Every zone is
  longer and wider than the one before, from 800 studs long and 140 wide in the Forest to 2,600 long and 240 wide
  in the Prehistoric zone (10,200 studs in all). Each has its own checkered ground, massive stepped walls up both
  sides (a boardwalk humping over a reef in the Ocean), plants and rocks, distant hills, and a gate with the zone's
  name (see [The runway](#the-runway)). The walls are broken by large gaps (marked with red strips).
- The runway never ends. The last zone repeats seamlessly past the end (ground, walls, gate and obstacles), and
  riders are quietly carried back one repeat at a time, so nobody ever reaches an end or sees one.
- The hub's stations, in the plaza between the plots: the **Trails** stall (nine trails that stream behind you and
  multiply your Max Stamina), the **Sell** stall (sell eggs you don't want), and the **fuse machine** (its panel
  explains fusing; fusing itself is not switched on yet). Terraced cliffs of pale stone and grass ring the hub. See
  [Hub stations](#hub-stations).
- A "Top Egg Claimers" leaderboard board beside the start zone (all servers, from an OrderedDataStore; it falls
  back to the players in the server when the store cannot be reached).
- Day and night: each runway cycle is one day. At sunrise every zone rolls a lineup of eggs that appear on the
  ground at the start of their zone and roll down the runway lap after lap; now and then an extra egg drops
  mid-cycle. Rarity sets their size, speed (18 studs a second for a Common egg up to 32 for an Eternal one; walking
  is 16) and stamina requirement. Rolling eggs leave a small trail of dust.
- When a Secret or Eternal egg spawns, every player gets an on-screen message saying where and when (a lineup egg on
  its first lap of the day only). Other eggs spawn quietly.
- Zone-themed obstacles on the runway, more to a row where it is wider, and now and then a giant rock. Eggs nobody
  is riding steer round them; riders have to steer clear themselves, or get bumped, thrown off, or burned.
- Every zone has 8 eggs, each with its own blocky model built from parts (see below).
- Blocky pet models for all 48 zone pets, rigged with joints so they can be animated (see below).
- Players never walk on the runway. Walking past the start zone, or jumping off an egg, launches a floaty leap with
  3.5 seconds to land on an egg. Touching the runway first, or running out of time, kills you (back to your plot).
  Riding a pet is not walking: a player on their pet can ride it down the runway and jump from it onto an egg.
- On an egg: steer left/right and stay on until the claim meter fills. Your camera turns with the runway round its
  bends. Steering into a wall kills you; steering into a gap sends you and the egg over the edge.
- A claimed egg goes into your inventory straight away, but you keep rolling on it (no stamina cost) until you jump
  off; then it disappears (a lineup egg comes back on its next lap). Nobody else can get on it.
- Stamina drains while riding. If it runs out first, you lose your balance and tumble off, and the egg bounces
  slightly and cracks. A cracked egg, or one that went over the edge, comes back at the start of its zone a few
  seconds later. Jumping off an unclaimed egg (or being knocked off, or dying on it) leaves it rolling for anyone.
- The 3-minute runway cycle: a warning, then a 10-second closure before dawn that clears every egg without a
  rider.
- Claimed eggs go into your inventory (the **Eggs** tab on the right). Stand anywhere in your pen and **Place** one:
  it hatches there on a timer, faster while the runway is closed, sometimes into a Silver, Gold or Rainbow pet.
- The **Pets** tab shows the eggs hatching and every pet you have. Put pets in your pen or take them out, or
  **Equip best**. Pets in the pen roam it and earn dollars every second. Sell pets for dollars.
- The green button at the front of your pen buys a bigger pen: room for more eggs at once and more pets.
- Ride any of your pets: it carries you faster than walking, and you can jump from it onto an egg.
- Each player gets one of 8 plots when they join, with their name over the gate, and respawns there. Everything is
  saved (ProfileStore). See [Eggs, pens and pets](#eggs-pens-and-pets).
- The HUD: runway timer and zone (top), Shop and Settings tabs on the left edge, eggs, Max Stamina and dollars (with
  what your pen earns a second) at the bottom left as big numbers on dark bands (the green "+" buttons open the shop
  at that section), the Eggs, Pets and Ride tabs on the right edge, the day and night clock at the bottom right (a
  moon and "in 1m 20s" until night by day, a sun and the time until sunrise by night), a timer while a server luck
  boost runs, the stamina and claim meters (bottom centre), a "Land on an egg!" countdown while leaping, and the
  banner for Secret and rarer eggs.
- **Shop** ("Coop Shop"): the next pen level for Robux or dollars (the same upgrade as the green button), x2 / x4
  server luck for 15 minutes (rarer eggs for everyone), Max Stamina packs, Double Your Stamina (each purchase doubles
  Max Stamina, from x2 up to x1024), dollar packs, and the x2 Dollars pass (every pet in your pen earns double).
  Robux purchases are granted exactly once, and only reported to Roblox once saved.
- **Settings**: Music / Effects / Nature volume, show others' pets / your pets, reduce camera shake, vibration.
  Saved to the player's account.
- The Egg Avalanche server event: twice the eggs in every zone for one runway cycle, once an hour.
- An admin panel for testing (see below), and a Model Showroom far from the hub where every pet and egg stands on
  display.

The eggs, pets, runway, plots, hub stations and the cliffs round the hub have their real look; the UI uses emoji
for icons. Not built yet: duels, other upgrades, offline earnings, teleport pads, the Titan Egg event, the tutorial, and
all sound. The pet and comfort settings are saved for the systems that will read them.

## Try it in Roblox Studio

You need [Rojo](https://rojo.space/docs/v7/getting-started/installation/) 7.7 (the command-line tool).
The easiest way to get the right versions of everything is [Rokit](https://github.com/rojo-rbx/rokit):

```bash
rokit install
```

Then build a place file and open it in Studio:

```bash
rojo build -o RollAnEgg.rbxl
```

Open it with *File > Open from File* and press **Play**.

### Keeping Studio up to date

The code lives in this repository; a place file is a snapshot of it. Two ways to get new changes into Studio:

- **Rebuild** (simplest): get the latest code (`git pull`), run `rojo build -o RollAnEgg.rbxl` again, and open the
  new file. Anything you built by hand in the old place file is not in the new one.
- **Live sync** (keeps your place): install the Rojo plugin once (`rojo plugin install`, then restart Studio), open
  your place, run `rojo serve` in this folder, and press **Connect** in Studio's Rojo plugin. Studio then picks up
  every change to the code as soon as it lands in the folder (after a `git pull`, too). Rojo only replaces the
  scripts it manages (`ReplicatedStorage.Shared` and `.Packages`, `ServerScriptService.Server` and
  `.ServerPackages`, `StarterPlayer.StarterPlayerScripts.Client`); parts and models you added yourself are left
  alone. Publish from Studio as usual when you are happy with it.

Saving works in Studio only if the place is published and *Game Settings > Security > Enable Studio Access to API
Services* is on. Otherwise the game still runs and simply does not save.

### Controls

| Action | Keyboard | Phone / tablet | Gamepad |
| --- | --- | --- | --- |
| Land on an egg | Steer onto it while leaping | Thumbstick | Left stick |
| Steer | A / D | Thumbstick | Left stick |
| Leap off an egg | Jump | Jump button | A |
| Eggs and pets | Click the **Eggs** / **Pets** tabs on the right | Tap them | Select them |
| Ride / get off your pet | **Ride** on its card, then the **RIDE** / **GET OFF** button | Tap them | Select them |
| Buy a bigger pen | Walk up to the green button by your gate, hold E | Hold its prompt | Hold X |

### Selling things for Robux

Every price and amount is in `src/shared/Config/Shop.luau`. Each Robux item needs its ID from the Creator
Dashboard (*Monetization > Developer Products* or *Passes*), pasted into its `productId` / `gamePassId`. There is
one developer product per pen level and one per stamina doubling (x1 to x2, x2 to x4 ...), because a product's
price is fixed.

While an ID is `0`, the item cannot be bought in a live game ("This isn't for sale yet"). In Studio, buying it grants
it straight away, so the whole shop can be tried before the products exist. The price shown comes from Roblox once an
ID is set, so changing a price on the dashboard is enough.

### Admin panel

Admins get a red **ADMIN** button at the top right of the screen. In Studio everyone is an admin. In a live game the
experience's owner is (the user who owns it, or the owner of the community that owns it), plus anyone whose user ID
is listed in `src/server/Config/Admins.luau`. The server checks every command, so nobody else can use them.

| Tab | What it does |
| --- | --- |
| Eggs | Pick a zone, then **Drop** any of its eggs on the runway or **Give** it to your inventory. Eggs drop in front of you (on the runway) or at the start of their zone. Drop a random egg, every egg of the zone, or clear the runway. |
| Pets | Pick a zone, then **Spawn** any of its pets next to you or **Give** it to your inventory. Stand all of the zone's pets in front of you, or remove the ones you spawned. |
| Me | **Fly** (move to fly where the camera looks; Space or E to rise, Q or Ctrl to sink) at 40 to 320 studs a second. Walk speed. Stamina: Max x5, 10M, refill, and reset (back to 100 plus what you bought in the shop). Dollars: add $1K, $1M or $1B, or reset to 0. What is in your inventory, clearing it, and **Hatch eggs now** (finishes every egg hatching in your pen). |
| Events | Start or stop an **Egg Avalanche**. Close the runway now, or open it now (skipping the rest of a closure). |
| Teleport | The hub, the **Model Showroom**, the end of the last zone, the start of any zone, or any other player. |

Eggs and pets given to you are saved like any others: eggs go into your inventory, ready to place in your pen, and
pets go straight into your pen if there is room. The Titan Egg event is not built yet, so the panel cannot start one.

### Model Showroom

A floor 3,000 studs to the side of the hub where every pet and egg model stands on display, with a name over each.
Get there from the admin panel's Teleport tab; a prompt on the pad where you arrive takes you back to the hub.

If you imported the pet and egg models into the place (see *Pet models* below), they are moved onto the showroom floor
when the game starts, laid out as you left them and with any changes you made: pets on the left of the yellow aisle,
eggs on the right. Whatever was not imported is built from the game's code the first time someone goes there (it
takes a few seconds), so the showroom always has everything.

That move only lasts while the game runs. To move the imported models out of the hub for good, so they are out of the
way while you build too, stop the game, run this once in Studio's command bar (*View > Command Bar*), and save:

```lua
require(game.ServerScriptService.Server.Services.ShowroomService).MoveImportedModels()
```

## Eggs, pens and pets

Every egg you claim on the runway goes into your inventory. Open the **Eggs** tab on the right of the screen to see
them, each with its rarity and how long it takes to hatch, and a 3D preview of the one you pick.

**Your pen.** Your plot is one of 8 fenced pens at the hub, four across the back facing the runway and two down
each side of the plaza, with your name over the gate (`src/shared/Plots.luau` lays them out; `src/server/Services/PlotService.luau` hands them out and builds
them). It is open grass: walk in, stand anywhere and press **Place**, and the egg goes down just in front of you
(not too close to another one), on a little straw bed with a countdown above it. A new pen hatches 2 eggs at once
and holds 10 pets.

**Hatching.** Hatch times go by rarity, from 30 seconds for a Common egg to 6 hours for an Eternal one
(`src/shared/Config/Rarities.luau`). They are worked out from timestamps (`src/shared/HatchMath.luau`), so eggs keep
hatching while you are offline. While the runway is closed every egg in the server hatches 30 times as fast, and that
extra time is kept when the next cycle starts. When an egg hatches it bursts open. Its pet is Normal, or with luck
**Silver** (8%), **Gold** (2.5%) or **Rainbow** (0.5%): recoloured, shinier (Gold and Rainbow sparkle), worth 2, 5
or 15 times as much, and a little faster to ride.

**Pets and dollars.** The **Pets** tab lists the eggs hatching and every pet you have, each with what it earns. Pets
in your pen wander round it and earn dollars every second, more for rarer pets, pets from deeper zones (10 times the
zone before) and variants. **Put in pen** / **In pen** chooses which pets are in it; **Equip best** fills it with
the ones that earn the most. **Sell** (tap twice) pays 150 seconds of the pet's earnings. Dollars show at the top
left, with what your pen earns a second.

**A bigger pen.** The green button at the front of your pen, beside the gate, buys the next size up (the price is
over it): the fence moves out 10 studs, and the pen hatches one more egg at once and holds one more pet, up to 10 eggs
and 18 pets at level 9. The numbers are in `src/shared/Config/Economy.luau`.

**Riding pets.** **Ride** on a pet's card brings it out under you; then the **RIDE** / **GET OFF** button below the
tabs gets you on and off it. A pet carries you faster than walking (22 studs a second for a Common pet, up to 44
for an Eternal one, plus a little for variants), round the hub and down the runway. Jump from it onto an egg as usual:
the pet goes away while you ride the egg and comes back 3 seconds after you leave it
(`src/server/Services/MountService.luau`).

The rules are in `src/server/Logic/Hatchery.luau` and `src/shared/PetWorth.luau`, run by
`src/server/Services/InventoryService.luau`.

## Hub stations

Walk up to a station in the plaza and use its prompt (tap it, or press E): its panel opens in the middle of the
screen, and closes again when you walk away. Where they stand is in `src/shared/HubLayout.luau`, along with the
terraced cliffs round the hub; `src/server/Map/Stations.luau` and `src/server/Map/Cliffs.luau` build them.

The Trails and Sell stalls are market booths: a plank deck on a stone base, carved posts, a counter, a striped
awning with pennants, a framed signboard and lanterns that light up at night. The Trails stall has a sample of every
trail hanging on its back wall, glass cases with glowing orbs, and ribbons of light arching over its sign; the Sell
stall has coin stacks, a balance, a money bag and crates of eggs. The fuse machine is a glass chamber on gold-trimmed
steps with the golden "?" egg floating inside, gears, four lamp pillars and three glowing pads in front.

- **Trails**: trails cost dollars, are kept for good, and one is equipped at a time. The equipped trail streams
  behind your character and multiplies your Max Stamina, on top of Max Stamina bought in the shop and its
  doublings. There are nine, each dearer, stronger and fancier than the one before:

  | Lvl | Trail | Rarity | Price | Max Stamina | Looks |
  | --- | --- | --- | --- | --- | --- |
  | 1 | Leaf | Common | $100 | x1.5 | a plain green ribbon |
  | 2 | Sunbeam | Common | $1K | x2 | a glowing golden ribbon |
  | 3 | Sandstorm | Uncommon | $7.5K | x3 | sand, kicking up dust |
  | 4 | Bubble | Uncommon | $50K | x4 | aqua, trailing bubbles |
  | 5 | Frost | Rare | $300K | x6 | ice, with a halo and snowflake sparkles |
  | 6 | Ember | Epic | $2M | x9 | fire, with embers and a warm light |
  | 7 | Thunder | Legendary | $15M | x13 | crackling blue-white, throwing sparks |
  | 8 | Galaxy | Mythic | $100M | x18 | deep space, full of stars |
  | 9 | Rainbow | Eternal | $750M | x25 | a wide rainbow with a white halo, rainbow stars and a light |

  The stall's panel shows a card for each in a row that scrolls sideways: its name, level and rarity, a picture of
  it streaming behind a runner, its boost, and a big button (its price, Equip, or Equipped). The list is in
  `src/shared/Config/Trails.luau`; `StationService` draws them on characters.
- **Sell**: sell 1 or all of a kind of egg from your inventory, for half its stamina requirement in dollars (a
  Forest Common egg sells for $25). Eggs already hatching in your pen are not for sale; pets sell from the Pets tab.
- **Fuse machine**: three of the same pet go in, and an egg of that pet comes out, usually hatching a size bigger.
  The rules are written and tested (`src/server/Logic/Fuse.luau`, sizes in `src/shared/Config/PetTraits.luau`), but
  pets do not have sizes yet, so for now the machine's panel only explains how it will work.

The rules are in `src/server/Logic/Stalls.luau` (and `Logic/Stats.luau` for Max Stamina), run by
`src/server/Services/StationService.luau`; the panels are `src/client/Ui/StationPanels.luau`.

## The runway

The runway winds and rolls: it bends left and right between massive walls, climbs and drops over hills, and gets
longer and wider zone by zone (`src/shared/Runway.luau`):

| Zone | Length (studs) | Width | Ground | Lineup eggs |
| --- | --- | --- | --- | --- |
| Forest | 800 | 140 | rolling meadows, gently downhill | 11 |
| Desert | 1,160 | 160 | dunes | 15 |
| Snow | 1,520 | 180 | down off the mountain to the shore | 20 |
| Ocean | 1,880 | 200 | a level boardwalk that humps up over the reef | 25 |
| Volcano | 2,240 | 220 | up the mountainside | 30 |
| Prehistoric | 2,600 | 240 | a rolling valley | 35 |

- **Bends.** Each zone swings out to one side and back across to the other, two to four times, up to 34 degrees
  from dead ahead, easing into and out of every bend. A bend is never tighter than the zone's width plus 90 studs
  in radius, so the walls on its inside always have room. The runway never doubles back, and it is dead ahead and
  level again at the start of every zone, where the gate hangs square across it.
- **Hills.** Slopes of 190 to 330 studs, up to 15% steep (less in the gentler zones). The Forest, Desert and Snow
  run mostly downhill, the Volcano climbs, and the Ocean's boardwalk only ever humps up from the level of its sea.
- **Width.** A zone is one width from its gate on, and widens to the next zone's over its last 120 studs.

The shape comes from a fixed seed per zone, so the server, every player and the map builder all get the same
runway without sending it anywhere. The rules never deal with it: they work in *runway coordinates* (how far down
the runway along its centre line, and how far across it), in which the runway is still a straight strip.
`Runway.toWorld` and `Runway.fromWorld` bend that strip into the world and back (as CFrames and Vector3s in
`src/shared/RunwayFrame.luau`), and only what is drawn or built, or read off a character's position, goes through
them. While you ride an egg, your camera turns with the runway, so "ahead" stays ahead round every bend.

The runway has no end: whatever the last zone is, it repeats past the end of the runway (the map builds a copy of
it, obstacles and all; the zone ends heading the way it started, so the copy is the same zone moved along, not
turned), and anything reaching the end of the loop is carried back one repeat to a spot that looks exactly the
same. Each device draws the eggs there at their copy nearest the player, so nothing seems to move.

**Walls and gaps.** Massive walls run down both sides: a sheer face about 35 to 60 studs high rising straight from
the kerb, and two more tiers stepping up and back behind it to between 70 and 120 studs, with the zone's plants and
rocks on top. They are broken by gaps of 50 to 110 studs at irregular spacing (none by a zone's gate), more of them the
longer the zone. A rider who steers their egg into a wall dies; one who steers it into a gap goes over the edge
with it. Players never walk on the runway: walking past the start zone, or jumping off an egg, starts a floaty leap
with 3.5 seconds to land on an egg, and touching the runway first kills them. In the Ocean the sides are railings
over the sea, and anyone who ends up in the water drowns.

**Eggs.** Each runway cycle (3 minutes) is one day (`src/shared/CycleClock.luau`): the sun rises as a cycle
begins, night falls 70% of the way through, and the runway closes for the last 10 seconds before dawn. At sunrise
every zone rolls a lineup of eggs with its usual odds: one egg for every 75 studs the zone is long (the table
above), so the long zones are as full of eggs as the short ones. They appear on the ground at the start of the zone
a few seconds apart (5 seconds, or less in the longest zones, so that the whole lineup is out within one lap), roll
to a quarter of the way into the next zone (the last zone's into its first copy), fade out, and appear at the start
again, lap after lap, until the runway closes. A lineup egg that is claimed comes back on its
next lap; one that cracks (only when its rider runs out of stamina) or goes over the edge comes back 5 seconds
later.
About every 30 seconds a zone also drops an extra, mid-cycle egg that rolls once; Secret and Eternal eggs are 10
times rarer mid-cycle than at sunrise. A ridden egg rolls on past its fade line until its rider leaves it. The
numbers are in `src/shared/Config/Tuning.luau`; the rules are in `src/server/Logic/RunwaySim.luau`.

**Obstacles.** Each zone has its own obstacles in rows across the runway, laid out from a fixed seed so every
server and player gets the same runway (`src/shared/Obstacles.luau`; kinds, sizes and mixes in
`src/shared/Config/Obstacles.luau`). A row has one to three obstacles for every 120 studs the runway is wide, so
the wide zones are as crowded as the narrow ones, and about one big rock in seven comes up giant, up to twice the
size again. Every row leaves a gap wide enough for the biggest egg, and there are always at least 44 studs of open
runway between one row and the next. What happens to the rider of an egg that hits one:

| Zone | Bump (stamina lost, egg knocked aside) | Knock-off (thrown off, egg rolls on) | Lethal (rider dies) |
| --- | --- | --- | --- |
| Forest | fallen logs, stumps, bushes, toadstools | boulders, trees | |
| Desert | cacti, tumbleweeds, skulls | sandstone rocks, sand geysers* | |
| Snow | snowdrifts, snowmen | pines, ice boulders | |
| Ocean | coral, barrels | sea rocks, giant clams* | |
| Volcano | obsidian spikes | basalt columns, smoking rocks | lava pools, lava vents* |
| Prehistoric | giant ferns, dinosaur skulls | giant ribcages, mossy boulders | tar pits |

\* These go off now and then: a few seconds of warning (puffing smoke or sand, or a trembling shell), then a burst
or a snap. They are harmless in between. A Bump costs 10% of the egg's stamina requirement. Lava and tar also kill
anyone who lands in them.

An egg nobody is riding steers round every obstacle on its own, along a path worked out the same way on the server
and on every device. A ridden egg goes where its rider steers. The rider's device spots a hit at once and reports
it; the server checks the report, and also catches hits on its own when an egg is well inside an obstacle.

**The look** (`src/server/Map/`): `Scenery` builds each zone's checkered ground (blending into the next zone's
colours), laid in short rows that turn with the bends and tip with the slopes; the massive stepped walls (in the
Ocean, a railed boardwalk on piles over a reef with islets and a lighthouse); the zone's plants and rocks on top of
the walls; distant hills, mesas, mountains or volcanoes; and the gate.
`ObstacleModels` builds each obstacle, in the same blocky style as the eggs and pets, sized to the footprint the
rules use. The client adds the dust behind rolling eggs (`EggController`), animates the obstacles that go off
(`ObstacleController`), and runs the day and night (`DayNightController`).

To look at the map without opening Studio:

```bash
lune run tools/map-preview
```

Then open `tools/out/map-preview.html` in a browser: buttons along the top jump to each zone, the left and right
arrow keys move along the runway 100 studs at a time (or put `#at=2500` on the address to look down it from 2,500
studs along), and dragging looks round.

To look at the on-screen UI without opening Studio:

```bash
lune run tools/ui-preview trails
```

Then open `tools/out/ui-preview.html`. The scenes are `hud`, `trails`, `trails-end` (the panel scrolled to the last
trails), `sell` and `shop`. It runs the game's own client scripts and draws their GUI objects in HTML: a close sketch,
not Roblox's renderer (fonts and emoji are the browser's).

## Egg models

Eggs are blocky, voxel-style models built from parts in code, so they need no uploaded meshes. Each zone has 8 eggs,
listed in `src/shared/Config/Zones.luau` with their rarity (a zone can have two eggs of the same rarity). A drop
picks a rarity with the zone's odds, then one of the zone's eggs of that rarity. Every egg has its own design in
`src/shared/EggModels/Designs.luau`:

- **Common**: plain, the zone's colour and one simple mark.
- **Uncommon, Rare**: a zone pattern with a hint of the pets inside (an acorn, a turtle shell, a knitted sweater).
- **Epic and up**: the egg looks like its pet: ears, horns, tusks, fins and markings, like the Great Shark's fin,
  gills and teeth or the Lava Golem's glowing cracks and boulder shoulders.
- **Legendary and up** glow in their rarity colour; **Mythic and up** also give off particles.

Designs are drawn standing up on a voxel grid (layers 1-16 from the round bottom to the point; x and z from -6 to 5).
On the runway the egg lies on its side and rolls. A design marked `shelved` is out of the game for now (the Frost
Dragon and Magma Dragon eggs, among others); put it back in a zone's list to bring it back.

In the game, the admin panel's Eggs tab drops any egg, or all 8 of a zone's eggs one after another, and the Model
Showroom stands every egg on end. To see every egg in 3D without opening Studio:

```bash
lune run tools/egg-gallery
```

Then open `tools/out/egg-gallery.html` in a browser.

## Pet models

Pets are built the same blocky way, in `src/shared/PetModels/Designs.luau`, one design per pet. Each egg in
`Config/Zones.luau` names the pet that hatches from it. Every pet has its model:

- Forest: Squirrel, Bunny, Hedgehog, Fox, Owl, Bear, Moss Stag, Treant
- Desert: Meerkat, Armadillo, Fennec Fox, Camel, Giant Scorpion, Pharaoh Jackal, Sphinx, Golden Scarab
- Snow: Snow Hare, Arctic Fox, Reindeer, Frost Wolf, Sabertooth Cat, Aurora Owl, Woolly Mammoth, Yeti
- Ocean: Sea Turtle, Dolphin, Manta Ray, Great Shark, Narwhal, Hippocampus, Kraken, Leviathan
- Volcano: Obsidian Goat, Cinder Boar, Volcano Tortoise, Fire Salamander, Chimera, Lava Golem, Cerberus, Lava Dragon
- Prehistoric: Velociraptor, Pteranodon, Triceratops, Stegosaurus, Brachiosaurus, T-Rex, Mosasaurus, Lunar Dragon

The rarer the pet, the more detailed it is. There is no block budget: quality comes first. Secret and Eternal pets
are the showpieces, built in the finest detail (the tests require at least 150 blocks each).

The more common pets are built from blocks placed by hand. The rarer four of each zone (and a few more) are
sculpted: `newSculpt` models each limb cell by cell out of rounded shapes (`ellipsoid`, and `rod` for tapering tubes
such as necks, tails and tentacles, with `curl` for a spiral at the end), colours it by rules (`coat` for patterns
like stripes, dapples, belly plates and lava seams, `trace` for lines), and packs it into as few blocks as it can.
Thin details leave the grid altogether and are built from parts at any angle (`blade`, `taper` for points, `egg` for
balls and eyes, `triangle` for a flat sheet such as a wing membrane or fin, and `feather` for a banded feather),
placed in the design's own units with `inUnits`, so horns, claws, fangs, wings, fins and eyes stay crisp however big
a pet is shown. Some carry Roblox `Fire` too: the Lava Dragon's flames, the Lunar Dragon's blue moonfire, the
Chimera's breath, the Volcano Tortoise's crater and the Fire Salamander's tail. (The Eternal Phoenix, built wholly
from angled parts, is shelved for now, its design kept.) `PetRig` builds the angled parts as turned parts,
`WedgePart`s, parts with a sphere `SpecialMesh`, and small welded parts holding each `Fire`.

Each pet is made of limbs (Body, Head, legs, wings, tail...) on one of a few shared skeletons: four legs, low and
four-legged, winged, dragon (four legs and wings), two legs, theropod (two legs, small arms and a tail: the raptor
and the T-Rex), six legs, swimmer (fins and a tail; these float), eight tentacles, or serpent (a chain of coils). `Shared/PetRig` builds the Roblox model: every limb turns on a
`Motor6D` at its joint, so pets that share a skeleton can share their animations.

How pets move is in `src/shared/PetAnimations.luau`: for each skeleton, a few moves (Idle, Walk, Stomp, Hop,
Crawl, Swim, and Roar for theropods), each a set of waves that turn or shift its limbs. Winged pets (the owls and the
Pteranodon) and dragons (the Lava and Lunar Dragons) also
**Fly** (up off the ground, tipped forward, wings beating in long strokes, legs tucked back) and **Hover** (flying
on the spot, upright, rising with each beat). A winged design says how far its wings turn out to be spread
(`wingSpread`), so owls that fold their wings at their sides open them to fly. The same moves drive the gallery
(pick one with the buttons under a pet) and the game: `PetAnimationController` on the client plays them on rigged
pets by setting each joint's `Motor6D.Transform`. A pet plays its `Move` attribute, or by default hovers if it can
fly and walks (or swims, or crawls) on the spot if not.

In the game, the admin panel's Pets tab stands any pet, or all of a zone's pets, in front of you, and the Model
Showroom has them all. They move as they would in the game; set a pet's `Move` attribute in the Properties window
(for example to `Fly`) to see its other moves.

To work on the models by hand in Studio, export them as model files:

```bash
lune run tools/export-models
```

This writes `tools/out/RollAnEgg-Pets.rbxm` and `tools/out/RollAnEgg-Eggs.rbxm`: every pet and every egg, built by
the game's own code (`PetRig`, `EggRig`), in a folder per zone, standing in rows on the ground (swimmers float). In
Studio, right-click Workspace in the Explorer, choose **Insert > Import Roblox Model**, and pick a file (older
Studios call it **Insert from File...**; or drag the file into the viewport). The pets come rigged, with a `Motor6D` per limb; they move when the game plays their animations.
Keep the folder names (`Roll an Egg Pets`, `Roll an Egg Eggs`): that is how the game finds them to move them into the
Model Showroom (see above).

## Project layout

```
default.project.json   How the folders below map into the Roblox place (read by Rojo)
docs/REQUEST.md        The agreed game design
src/shared/            ReplicatedStorage.Shared: config and math used by both server and client
  Config/                Zones, rarities, tuning numbers. Change game balance here.
src/server/            ServerScriptService.Server
  Config/                Server-only settings: who the admins are
  Logic/                 The rules of the game, with no Roblox objects, so they can be tested outside Studio
  Map/                   Builds the look of the map: zone scenery, obstacle models, the players' plots, the hub's
                         stations and the cliffs round it
  Services/              Connect the rules to players, saved data, the map, and remotes; events, teleports,
                         the Model Showroom, and the admin panel's commands
src/client/            StarterPlayerScripts.Client
  Controllers/           Egg drawing, riding, HUD updates, the shop and settings, pet animation, admin flight,
                         the admin panel
  Ui/                    The Fusion HUD; the Eggs and Pets panels; the Shop, Settings and hub station panels
                         (Theme and Widgets hold the shared look); and the admin panel
tests/                 Automated tests (see below)
tools/                 egg-gallery.luau: a web page that shows every egg and pet model in 3D;
                       map-preview.luau: a web page that shows the map in 3D;
                       ui-preview.luau: a web page that sketches the HUD and its panels;
                       export-models.luau: every pet and egg as Studio model files (.rbxm)
vendor/                Fusion and ProfileStore, copied in unchanged (see vendor/README.md)
```

How the pieces talk to each other:

- **Eggs are not parts on the server.** The server sends "an egg appeared / was mounted / was left / is gone", and
  every device draws the eggs itself from the shared server clock (`Shared/EggMotion`). Eggs stay smooth and use
  almost no network traffic.
- **The server decides everything that matters**: whether a mount counts, stamina, claims, what gets saved.
  Clients only ask and steer. Every remote is listed in `Shared/Net`.

## Tests

```bash
lune run tests/run
```

There are two kinds:

- **Rule tests** check the game's rules and numbers directly (config, egg movement, the runway cycle, riding,
  stamina, cracking, the runway's bends, hills, walls and gaps, the endless last zone, closures, shop prices,
  settings, luck boosts), and that every
  egg and pet model exists, is unique and has nothing floating loose, and that every egg stays within its part
  budget. Pets have none. They are also checked for the limbs their skeleton needs, and for differently coloured
  blocks sharing a face (which flicker in Roblox).
- **Smoke tests** build the place with Rojo and run the real server and client scripts against a stand-in for
  Roblox Studio (`tests/studio.luau`). They catch misspelled properties and wiring mistakes. Purchases are tested
  by calling the game's own ProcessReceipt with made-up receipts.

The tests cannot check anything that needs the real engine: physics, animation, input, how things look and feel.
Those need a play test in Studio.

Code style and lint:

```bash
stylua src tests
```

```bash
selene src tests
```
