# Roll an Egg

A Roblox game: eggs roll down a long shared runway, players jump on and ride them to claim them, then hatch them
into pets back at their plot. The full design is in [docs/REQUEST.md](docs/REQUEST.md).

## What works so far

The first playable slice: **the runway, riding, hatching and pens**, plus **the shop, settings and admin panel**.

- The map: the hub with a painted START ZONE where the runway begins, then a level runway that winds through six
  zones (Forest, Desert, Snow, Ocean, Volcano, Prehistoric) like a canyon, each longer and wider than the one before
  (800 studs long and 120 wide in the Forest, up to 2,600 by 320 in the Prehistoric zone), each with its own checkered
  ground, tall stepped cliffs capped with grass hanging over their edges (a boardwalk over a reef in the Ocean),
  plants and rocks, distant hills, and a gate with the zone's name (see [The runway](#the-runway)). The cliffs down
  both sides are broken by fairly large gaps that look out over a valley, with a low railing across.
- The runway never ends. The last zone repeats seamlessly past the end (ground, banks, gate and obstacles), and
  riders are quietly carried back one repeat at a time, so nobody ever reaches an end or sees one.
- The hub's stations, in the plaza between the plots: the **Trails** stall (nine trails that stream behind you and
  multiply your Max Stamina), the **Sell** stall (sell eggs you don't want), and the **fuse machine** (its panel
  explains fusing; fusing itself is not switched on yet). Terraced cliffs of pale stone and grass ring the hub. See
  [Hub stations](#hub-stations).
- A "Top Egg Claimers" leaderboard board beside the start zone (all servers, from an OrderedDataStore; it falls
  back to the players in the server when the store cannot be reached).
- Day and night: each runway cycle is one day. At sunrise every zone rolls a lineup of eggs that appear on the
  ground at the start of their zone and roll down the runway lap after lap; now and then an extra egg drops
  mid-cycle. There is always an egg at the start of every zone to jump on: one leaves it at least every 4 seconds.
  Rarity sets their size, speed (27 studs a second for a Common egg up to 54 for an Eternal one; walking is 16) and
  stamina requirement. Rolling eggs kick up a thick cloud of dust.
- When a Secret or Eternal egg spawns, every player sees a line of shiny white text along the top of the screen for
  5 seconds ("Secret egg has spawned in Volcano!"), each new one beneath any still up, and hears a sparkle (a lineup
  egg on its first lap of the day only). Other eggs spawn quietly.
- Zone-themed obstacles on the runway, small and big (giant stumps, rock outcrops, buttes, walls of ice blocks,
  shipwrecks, obsidian crags). Eggs nobody is riding steer round them; riders have to steer clear themselves, or
  lose stamina and slow down. No obstacle or wall kills anyone.
- Every zone has 8 eggs, each with its own blocky model built from parts (see below).
- Blocky pet models for all 48 zone pets, rigged with joints so they can be animated and ridden (see below). The
  Forest's and Desert's pets are redrawn in the new showpiece style (sculpted voxels, glowing Neon, auras, with bloom
  in the lighting); the other zones follow one at a time.
- Players never walk on the runway. Walking past the start zone, or jumping off an egg, launches a floaty leap with
  3.5 seconds to land on an egg. Touching the runway first, or running out of time, kills you (back to your plot).
  That goes for pet riders too: a pet never goes on the runway, so riding one past the start zone sends it away and
  launches the same leap.
- On an egg: steer left/right and stay on until the claim meter fills. Steering into the side of the runway (a bank,
  or the railing across a gap) bounces the egg back off it, which costs some stamina.
- Riders run on top of their egg as it rolls, faster on faster eggs. They lean into their steering and stumble when
  the egg bumps into something. As their stamina is about to run out they wobble and windmill their arms. Once the
  egg is theirs they punch the air, and when they are thrown off they tumble away. Players rolling on their training
  stick run the same way (see [Riding animation](#riding-animation)).
- A claimed egg goes into your inventory straight away, but you keep rolling on it (no stamina cost) until you jump
  off; then it disappears (a lineup egg comes back on its next lap). Nobody else can get on it.
- Stamina drains while riding. If it runs out first, you lose your balance and tumble off, and the egg bounces
  slightly and cracks. A cracked egg comes back at the start of its zone a few seconds later. Jumping off an
  unclaimed egg (or dying on it) leaves it rolling for anyone.
- The 5-minute runway cycle: the runway is open all day (4 minutes 50 seconds), then, after a warning, closes for
  the 10-second night, which clears every egg without a rider.
- Claimed eggs go into your Roblox inventory (the hotbar at the bottom of the screen, one tool per kind of egg, such
  as "Acorn Egg x3") and the **Eggs** tab on the right. Hold one and click (or tap) a spot in your pen to put it
  down: it hatches there on a timer, faster while the runway is closed, sometimes into a Silver, Gold or Rainbow pet.
- The **Pets** tab shows the eggs hatching and every pet you have. Put pets in your pen or take them out, or
  **Equip best**. Pets in the pen roam it and earn dollars every second. Sell pets for dollars.
- The green button at the front of your pen buys a bigger pen: room for more eggs at once and more pets.
- Ride any of your pets round the hub: it carries you faster than walking, but costs stamina while you ride, and
  bucks you off when your stamina runs out.
- Each player gets one of 8 plots when they join, with their name over the gate, and respawns there. Everything is
  saved (ProfileStore). See [Eggs, pens and pets](#eggs-pens-and-pets).
- A **training stick** in front of every pen: a roller over a trough of water. Step up and roll on it (birling) for
  as long as you like: every quarter of a second adds Max Stamina for good, with a "+1" floating over your head, and
  "2x" bubbles pop up to tap for a burst of double stamina. Eight tiers, from a twig to a rainbow crystal, bought with
  dollars or Robux. See [The training stick](#the-training-stick).
- The HUD: Shop and Settings tabs on the left edge, eggs, Max Stamina and dollars (with what your pen earns a
  second) at the bottom left as big numbers on dark bands (the green "+" buttons open the shop at that section), the
  Eggs (an egg), Pets (a paw) and Ride tabs on the right edge, the day and night clock at the bottom right (a moon and
  "in 3m 20s" until night by day, a sun and the time until sunrise by night), a timer while a server luck boost runs,
  the stamina and claim meters (bottom centre), a "Land on an egg!" countdown while leaping, and the shiny white
  lines along the top when Secret and rarer eggs spawn. There is no runway timer or zone name across the top: a
  short message says when the runway is about to close, and when it closes.
- **Shop** ("Coop Shop"): the next tier of the training stick and the next pen level, each for Robux or dollars (the
  same upgrades as the stick's sign and the pen's green button), x2 / x4
  server luck for 15 minutes (rarer eggs for everyone), Max Stamina packs, Double Your Stamina (each purchase doubles
  Max Stamina, from x2 up to x1024), dollar packs, and the x2 Dollars pass (every pet in your pen earns double).
  Robux purchases are granted exactly once, and only reported to Roblox once saved.
- **Settings**: Music / Effects / Nature volume, show others' pets / your pets, reduce camera shake, vibration.
  Saved to the player's account.
- The Egg Avalanche server event: twice the eggs in every zone for one runway cycle, once an hour.
- An admin panel for testing (see below), and a Model Showroom far from the hub where every pet and egg stands on
  display.

The eggs, pets, runway, plots, hub stations and the cliffs round the hub have their real look; the UI uses emoji
for most icons (the Eggs and Pets tabs have pictures drawn from frames). Not built yet: duels, other upgrades,
offline earnings, teleport pads, the Titan Egg event, the tutorial, and all sound apart from the Secret egg alert. The
pet and comfort settings are saved for the systems that will read them.

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
| Put an egg down | Pick it in the hotbar (1-9), or **Hold** on its card in the Eggs tab, then click a spot in your pen | Tap it in the hotbar, then tap a spot in your pen | Pick it, aim at the spot, R2 |
| Eggs and pets | Click the **Eggs** / **Pets** tabs on the right | Tap them | Select them |
| Ride / get off your pet | **Ride** on its card, then the **RIDE** / **GET OFF** button | Tap them | Select them |
| Buy a bigger pen | Walk up to the green button by your gate, hold E | Hold its prompt | Hold X |
| Roll on your training stick | Walk up to it, E | Tap its prompt | X |
| Tap a "2x" bubble | Click it | Tap it | Select it |
| Get off the training stick | Jump, or **STOP** | Jump button, or **STOP** | A |
| Upgrade the training stick | E at the sign beside it, or the shop | Tap the sign's prompt | X |

### Selling things for Robux

Every price and amount is in `src/shared/Config/Shop.luau`. Each Robux item needs its ID from the Creator
Dashboard (*Monetization > Developer Products* or *Passes*), pasted into its `productId` / `gamePassId`. There is
one developer product per pen level, one per training stick tier, and one per stamina doubling (x1 to x2, x2 to x4
...), because a product's price is fixed.

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
| Me | **Fly** (move to fly where the camera looks; Space or E to rise, Q or Ctrl to sink) at 40 to 320 studs a second. Walk speed. Stamina: Max x5, 10M, refill, and reset (back to 100 plus what you bought in the shop and trained). Dollars: add $1K, $1M or $1B, or reset to 0. Training stick: a tier down or up, the last tier, or clear the Max Stamina trained on it. What is in your inventory, clearing it, and **Hatch eggs now** (finishes every egg hatching in your pen). |
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

Every egg you claim on the runway goes into your Roblox inventory: the hotbar at the bottom of the screen has a tool
for each kind of egg you hold, named with how many you have ("Acorn Egg x3"); holding one puts the egg in your hand.
The **Eggs** tab on the right of the screen lists them too, each with its rarity and how long it takes to hatch, and a
3D preview of the one you pick (its **Hold** button puts that egg in your hand). `EggToolService` keeps the tools
in step with your saved eggs (they come back when you respawn); `EggToolController` puts them down.

**Your pen.** Your plot is one of 8 fenced pens at the hub, four across the back facing the runway and two down
each side of the plaza, with your name over the gate (`src/shared/Plots.luau` lays them out; `src/server/Services/PlotService.luau` hands them out and builds
them). It is open grass: hold an egg and click (or tap) anywhere in it, and the egg goes down right there (or as near
as it can without crowding another one), on a little straw bed with a countdown above it. While you hold an egg, a
see-through egg on a ring shows where it would go: green in your pen, red anywhere else. A new pen hatches 2 eggs at
once and holds 10 pets.

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
tabs gets you on and off it. A pet carries you faster than walking (33 studs a second for a Common pet, up to 66
for an Eternal one, plus a little for variants) round the hub. Riding costs 5 stamina a second (20 seconds at the
starting 100): when your stamina runs out, the pet bucks you off, and you have to rest until you have at least 10
again before it will carry you. Your stamina comes back as usual once you are off. Pets never go on the runway:
ride one past the start zone and it goes away and you leap like anyone else; getting on an egg sends it away too.
Either way it stays away until you ride it again (`src/server/Services/MountService.luau`, the stamina rules in
`src/server/Logic/RunwaySim.luau`).

The rules are in `src/server/Logic/Hatchery.luau` and `src/shared/PetWorth.luau`, run by
`src/server/Services/InventoryService.luau`.

## The training stick

Every plot has a training stick in the plaza in front of its pen, on the other side of the gate from the green
button: a roller held between two posts over a wooden trough of water (with a lily pad and a rubber duck), a glowing
strip round its foot in the tier's colour, the tier's name floating above, and a sign at its front corner.

**Rolling.** Walk up to your stick and use its prompt (**Start rolling**): you are stood on top of the roller,
facing the plaza, and run on the spot while it spins under your feet (birling), the same way riders run on the eggs
(see [Riding animation](#riding-animation)): a steady run, and a flat-out sprint during a 2x boost. Stay as long as you like; jump, or press **STOP**, to step off. Only the plot's
owner can use its stick, so nobody else sees its prompts.

- Every quarter of a second is a **rep**: 4 a second. Each rep adds Max Stamina for good, and the amount floats up
  over your head ("+1" on the first tier). Other players see your numbers too.
- What a rep adds goes through your multipliers like the rest of your Max Stamina: (base + bought + trained) x
  doublings x trail. With the x1.5 Leaf Trail, a first-tier rep shows "+1.5".
- Every few seconds (2.5 to 5) a **"2x" bubble** pops up somewhere round the middle of the screen, its ring
  shrinking as its 2.5 seconds run out. Tap it in time and every rep for the next 1.5 seconds counts double: the
  numbers turn gold, the roller spins faster, sparkles and a warm light burst from it, and a "2x STAMINA!" bar drains
  over the card at the bottom of the screen.
- While rolling, a card above the stamina bar shows the tier, what each roll and each second gives, the Max Stamina
  gained so far, and the **STOP** button. The water splashes under the roller, and a plank or a girder rocks its rider
  up and down as it turns.

**Upgrading.** Eight tiers, each dearer, stronger and better-looking than the one before. Upgrade one tier at a time
with dollars or Robux: from the sign beside the stick (its prompt opens the upgrade panel: the stick now and the
next tier turning in 3D, what it gives, the two prices, and all eight tiers in a row) or from the shop's Featured
section. The sign itself shows the next tier, the stamina a second now and after, and both prices. A stick that
upgrades bursts with sparkles; if you are rolling at the time, you carry on, on top of the new one.

| Lvl | Tier | Rarity | Per rep | Per second | Dollars | Robux | Looks |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Stick | Common | +1 | +4 | free | | a crooked twig with knots, two shoots and leaves |
| 2 | Plank | Uncommon | +2 | +8 | $500 | 29 | three nailed boards with iron bands |
| 3 | Short Log | Rare | +5 | +20 | $5K | 59 | a stubby log with ridged bark, tree rings and a toadstool |
| 4 | Tree Trunk | Epic | +12 | +48 | $50K | 99 | a long, mossy trunk with bark plates, branch stubs and a sapling |
| 5 | Metal Pipe | Legendary | +30 | +120 | $500K | 179 | a steel pipe with bolted flanges, gold bands and rivets |
| 6 | Steel Girder | Mythic | +75 | +300 | $5M | 299 | a riveted red I-beam with holes, end plates and a stencil |
| 7 | Marble Column | Secret | +200 | +800 | $50M | 499 | a fluted marble column with gold bands, capitals and gems |
| 8 | Rainbow Crystal | Eternal | +500 | +2K | $500M | 799 | rainbow glass facets round a glowing core, with sparkles |

The posts change with the tier too: timber for the wooden rollers, steel for the pipe and girder, marble for the
column, dark crystal for the last. Per rep and per second are before multipliers. The tiers, gains and timings are in
`src/shared/Config/Sticks.luau` (first-pass numbers, to tune with the economy), the Robux prices in
`src/shared/Config/Shop.luau`.

How it is built:

- The rules (reps, the bubbles, upgrades) are in `src/server/Logic/Training.luau`, run by
  `src/server/Services/TrainingService.luau`. The server decides everything: reps come from its clock alone, a bubble
  only counts if it is the one it put up and is still in time, and it holds the rider's character in place.
  Max Stamina trained is saved as `TrainedStamina`, the tier as `StickLevel`.
- The rollers are built from parts in `src/shared/StickModels.luau` (shared, so the upgrade panel can show them in
  3D); the stand round them in `src/server/Map/TrainingStand.luau`; where it stands in `src/shared/Plots.luau`.
- Each device spins the rollers and floats the numbers (`src/client/Controllers/TrainingController`), and runs the
  riders with the riding animation (`RiderAnimationController`, see [Riding animation](#riding-animation)); how hard
  they run, normally and in a boost, is `RUN_PACE` and `BOOST_RUN_PACE` in `Config/Sticks.luau`. The screens are in
  `src/client/Ui/TrainingUi.luau`.

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

The runway is level, and gets longer and wider the further it goes, the banks stepping out at each gate
(`src/shared/Runway.luau`):

| Zone | Length | Width | Eggs in its lineup |
| --- | --- | --- | --- |
| Forest | 800 | 120 | 11 |
| Desert | 1,160 | 140 | 15 |
| Snow | 1,520 | 160 | 20 |
| Ocean | 1,880 | 200 | 25 |
| Volcano | 2,240 | 260 | 30 |
| Prehistoric | 2,600 | 320 | 35 |

The first three zones are each 20 studs wider than the one before; from the Ocean (zone 4) on, each is a quarter wider
than the one before, to the nearest whole 20-stud ground tile, up to zone 7 (zones added after that would stay as
wide as it). The last zone's endless repeats keep its width. Wider zones get more obstacles to a row, and longer ones
more rows, so none is emptier than the first.

A bright, milky fog hangs over everything, like the owner's reference: close by is crisp, and from 40 studs away
everything fades into pale white-blue, half gone by about 300 studs and lost in it by 600 (Lighting's own fog, set in
studs by `MapService`; there is no `Atmosphere`, which would hide it). It turns deep blue at night
(`DayNightController`).

**It winds** like a canyon: its centre line swings out to one side and back, or across from one side to the other
(`Runway.BENDS`), up to about 70 studs, once for every 650 studs or so of each zone, and is back in the middle,
running straight, at every zone's start. Gameplay never sees the bends: eggs, obstacles and steering all work in
runway space (distance down the runway, and how far across it from the centre line), and only drawing and checking
characters turns that into the world (`Runway.worldX`, `Runway.lateralOf`). It has no end: whatever the last zone
is, it repeats past the end of the runway (the map builds a copy of it, obstacles and bends and all), and anything
reaching the end of the loop is carried back one repeat to a spot that looks exactly the same. Each device draws the
eggs there at their copy nearest the player, so nothing seems to move.

**Banks and gaps.** Tall stepped cliffs run down both sides, three steps of stone capped with grass (or sand, snow or
rock) hanging over their edges: the wall beside the runway stands 46 to 54 studs high, the step behind it 28 to 36
studs higher and the back step 38 to 50 higher again (the Ocean has a 7-stud boardwalk railing instead). The runway
widens zone by zone, from 120 studs in the Forest to 320 in the Prehistoric zone, the banks stepping out at each gate.
The banks are broken by gaps of 40 to 80 studs at irregular spacing (none by a zone's gate). Each gap looks out over
a valley, with a low wooden railing across it and an invisible wall above. Nothing at the edge kills: a rider who
steers their egg into a bank or a railing bounces back off it, losing 10% of the egg's stamina requirement and slowing
for a moment. Players never walk on the runway:
walking past the start zone, or jumping off an egg, starts a floaty leap with 3.5 seconds to land on an egg, and
touching the runway first sends them back to the hub.

**Landing.** While a player is in the air, a red circle around an egg shows which one they are heading for: the egg
nearest where their jump will come down, allowing for the egg drifting sideways round the bends
(`src/shared/JumpAim.luau`). Once they are close to it, they are drawn onto it like a magnet, so a landing never has
to be pixel-perfect; the circle tightens when it has hold of them.

**Eggs.** Each runway cycle (5 minutes) is one day and one night (`src/shared/CycleClock.luau`): the sun rises as
a cycle begins, the day lasts the 4 minutes 50 seconds the runway is open (long enough for an egg to roll right
through the longest zone twice), and night falls as the runway closes, for the last 10 seconds before the next
sunrise. At sunrise every zone rolls a lineup of eggs with its usual odds: one egg for every 75 studs the zone is long
(the table above), so the long zones are as full of eggs as the short ones. They appear on the ground at the start of
the zone a few seconds apart (5 seconds, or less in the longest zones, so that the whole lineup is out within one
lap), roll to a quarter of the way into the next zone (the last zone's into its first copy), fade out, and appear at
the start again, lap after lap, until the runway closes. So that there is always an egg to jump on at the start of
every zone, whenever none has left it for 4 seconds the zone's lineup egg due next leaves at once. A lineup egg that
is claimed comes back on its next lap; one that cracks (only when its rider runs out of stamina) comes back 5
seconds later.
About every 30 seconds a zone also drops an extra, mid-cycle egg that rolls once; Secret and Eternal eggs are 10
times rarer mid-cycle than at sunrise. A ridden egg rolls on past its fade line until its rider leaves it. The
numbers are in `src/shared/Config/Tuning.luau`; the rules are in `src/server/Logic/RunwaySim.luau`.

**Obstacles.** Each zone has its own obstacles in rows across the runway, laid out from a fixed seed so every
server and player gets the same runway (`src/shared/Obstacles.luau`; kinds, sizes and mixes in
`src/shared/Config/Obstacles.luau`). Every row leaves a gap wide enough for the biggest egg. No obstacle kills
anyone. What happens to the rider of an egg that hits one (the egg is always knocked aside, clear of the row):

| Zone | Bump (10% of the egg's stamina) | Crash (20%, and the egg slows for 1.2 s) | Slow (12%, and the egg slows for 2 s) |
| --- | --- | --- | --- |
| Forest | fallen logs, stumps, bushes, toadstools | boulders, trees, giant stumps, rock outcrops | |
| Desert | cacti, tumbleweeds, skulls | sandstone rocks, buttes, sand geysers* | |
| Snow | snowdrifts, snowmen | pines, ice boulders, walls of ice blocks | |
| Ocean | coral, barrels | sea rocks, shipwrecks, giant clams* | |
| Volcano | obsidian spikes | basalt columns, smoking rocks, obsidian crags | lava pools, lava vents* |
| Prehistoric | giant ferns, dinosaur skulls | giant ribcages, mossy boulders, giant stumps, rock outcrops | tar pits |

\* These go off now and then: a few seconds of warning (puffing smoke or sand, or a trembling shell), then a burst
or a snap. They are harmless in between. A slowed egg rolls at 40% of its speed (`Shared/EggMotion` works it out from
the clock, so every device draws it in the same place). The numbers are `Tuning.HIT_EFFECTS`.

An egg nobody is riding steers round every obstacle on its own, along a path worked out the same way on the server
and on every device. A ridden egg goes where its rider steers. The rider's device spots a hit at once and reports
it; the server checks the report, and also catches hits on its own when an egg is well inside an obstacle.

### Riding animation

Everyone riding an egg runs on top of it as it rolls under them, and so does everyone rolling on their
[training stick](#the-training-stick). Every player sees it, and R15 and R6 characters both work.

- **Running:** quick steps on the spot, leaning forwards, arms pumping, bobbing up between steps. The feet are
  quicker on faster eggs (2.4 strides a second on a Common egg, the slowest, up to 3.2 on an Eternal one, the
  fastest) and the strides longer.
- **On the training stick:** the same run, at a steady pace, and flat out during a 2x boost. A plank or a girder
  rocks its rider up and down as it turns.
- **Landing** on an egg: a quick squash, then straight into the run.
- **Steering:** they lean into the turn and look where they are going, with the outside arm out for balance.
- **Bumps:** they rock with the egg, arms thrown out, and run on.
- **Running out of stamina:** in the last 3 seconds before it runs out they hunch over, wobble more and more and
  windmill their arms. Other players see this too: the server keeps the time each rider's stamina will run out on
  their Player (the `StaminaRunsOutAt` attribute).
- **Claimed:** one fist punched up high, pumping, for the rest of the ride.
- **Thrown off** (out of stamina): arms and legs flailing as they tumble through the air, until they get their
  balance back.

The poses are worked out in `src/shared/RiderPose.luau` (pure math, tested outside Studio). On each device,
`src/client/Controllers/RiderAnimationController.luau` sets them on every rider's joints every frame, blending in and
out so nothing snaps. Characters come with one of two kinds of joint, and both work:

- **AnimationConstraint** (Roblox's avatar joint upgrade, the default for new experiences): the pose is set on each
  joint's `Transform` in `RunService.PreSimulation`, after Roblox's own animations have set theirs, as Roblox's
  documentation says to.
- **Motor6D** (older characters): Roblox's animations set every joint's `Transform` each frame, so the pose goes into
  each joint's `C0` instead, just before the frame is drawn, cancelling out whatever those animations are doing; every
  `C0` is put back when the ride is over.

Riders stand on the egg (`EggController`), as high above it as they would stand above the ground.

To watch it without opening Studio:

```bash
lune run tools/rider-preview
```

Then open `tools/out/rider-preview.html` in a browser. It shows a rider in every situation above, on an egg or a
training stick, on an R15 or R6 character, from behind (as in the game), the side or the front, in slow motion if you
like.

**The look** (`src/server/Map/`): `Scenery` builds each zone's checkered ground (blending into the next zone's
colours, each row of tiles centred on the runway where it is), tall stepped cliffs that players cannot climb, built
in short segments that follow the bends, with valleys beyond the gaps (in the Ocean, a railed boardwalk over a reef
with islets and a lighthouse), the zone's plants and rocks on the banks, distant hills, mesas, mountains or
volcanoes, and the gate.
`ObstacleModels` builds each obstacle, in the same blocky style as the eggs and pets, sized to the footprint the
rules use. The client adds the dust behind rolling eggs (`EggController`), animates the obstacles that go off
(`ObstacleController`), and runs the day and night (`DayNightController`).

To look at the map without opening Studio:

```bash
lune run tools/map-preview
```

Then open `tools/out/map-preview.html` in a browser: buttons along the top jump to each zone, drag to look round. Each
plot's training stick shows a different tier (plot 1 the first, plot 8 the last), some with a player rolling on it.

To look at the on-screen UI without opening Studio:

```bash
lune run tools/ui-preview trails
```

Then open `tools/out/ui-preview.html`. The scenes are `hud`, `trails`, `trails-end` (the panel scrolled to the last
trails), `sell`, `shop`, `eggs` (the Eggs panel), `secret` (the shiny lines along the top when Secret and Eternal
eggs spawn), `stick` (the training stick's upgrade panel) and `training` (rolling on the stick, with a 2x boost and a
bubble). It runs the game's own client scripts and draws their GUI objects in HTML, and the models in 3D previews as
flat-shaded drawings: a close sketch, not Roblox's renderer (fonts and emoji are the browser's).

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

Pets are built the same blocky way, one design per pet. Each egg in `Config/Zones.luau` names the pet that hatches
from it. Every pet has its model:

- Forest: Squirrel, Bunny, Hedgehog, Fox, Owl, Bear, Moss Stag, Treant
- Desert: Meerkat, Armadillo, Fennec Fox, Camel, Giant Scorpion, Pharaoh Jackal, Sphinx, Golden Scarab
- Snow: Snow Hare, Arctic Fox, Reindeer, Frost Wolf, Sabertooth Cat, Aurora Owl, Woolly Mammoth, Yeti
- Ocean: Sea Turtle, Dolphin, Manta Ray, Great Shark, Narwhal, Hippocampus, Kraken, Leviathan
- Volcano: Obsidian Goat, Cinder Boar, Volcano Tortoise, Fire Salamander, Chimera, Lava Golem, Cerberus, Lava Dragon
- Prehistoric: Velociraptor, Pteranodon, Triceratops, Stegosaurus, Brachiosaurus, T-Rex, Mosasaurus, Lunar Dragon

**The showpiece style.** Pets are being redrawn, a zone at a time, to look like the big showpiece pets of Roblox
simulator games: part-built voxel models with real proportions, light baked into their colours (lighter tops,
darker undersides), crisp angled claws, fangs, horns, quills and tufts of fur, and, the rarer they are, more that
glows. Each redrawn zone has its own file beside `Designs.luau`; so far `PetModels/Forest.luau` and
`PetModels/Desert.luau`:

| Rarity | Size (a player is 5 studs) | What glows |
| --- | --- | --- |
| Common, Uncommon | About a player's height | Nothing: natural animals with glossy eyes |
| Rare | Taller than a player (the Owl, 9 studs; the Camel, 10) | A first touch: the Owl's eyes, the Camel's harness jewels |
| Epic | Twice a player's height, long (the Bear, 14 studs long; the Giant Scorpion, 16) | Eyes and markings: the Bear's claw-mark runes and mushrooms, the Scorpion's eyes and venom |
| Legendary | Three times (the Moss Stag, 17 studs to its antler tips; the Pharaoh Jackal, 13) | Eyes, markings and tips, a light, fireflies or sparkles, and an aura swirling at its feet |
| Mythic | Three to five times (the Treant, 26 studs; the Sphinx, 18; the Golden Scarab and its sun, 15) | All of that, more of it: the Treant's cracks and heart, the Sphinx's cracks, inscription and ankh, the Scarab's blazing sun disc |

The game's Lighting has a `BloomEffect` (named `Bloom`, set up by `MapService`), so Neon throws a soft halo the way
it does round the showpiece pets of other games. Only light brighter than sunlit ground blooms. To try the game
without it, delete `Lighting.Bloom` in Studio, or remove it from `MapService`.

Every pet is rideable: a design sets where the rider sits (`pet:seat`), and the mount lifts the rider to it at any
size. Pets bigger than about 10 studs are built from coarser cells (a design's `U`), so they keep their detail
with fewer, larger blocks and build quickly: no Forest pet takes more than a second to build or has more than about
1,000 blocks. The size a pet hatches at (Tiny to Titanic) is not decided yet; the models are built to be scaled.

The drawing tools are in `src/shared/PetModels/Kit.luau`, shared by every design. `newSculpt` models each limb cell
by cell out of rounded shapes (`ellipsoid`, and `rod` for tapering tubes such as necks, tails and tentacles, with
`curl` for a spiral at the end), colours it by rules (`coat` for patterns like stripes, belly plates and lava seams,
`patches` for soft patches of moss or grizzled fur, `nearPath` for the pale fringe of a tail, `trace` for lines, and
`bake` for the light from above), and packs it into as few blocks as it can. `surface` lists the cells on its
outside with the way each faces, for setting quills, tufts of fur and moss over it. Thin details leave the grid
altogether and are built from parts at any angle (`blade`, `taper` for points, `egg` for balls and eyes, `triangle`
for a flat sheet such as a wing membrane or leaf, and `feather` for a banded feather), placed in the design's own
units with `inUnits`, so horns, claws, fangs, wings, fins and eyes stay crisp however big a pet is shown. Some carry
Roblox `Fire` too: the Lava Dragon's flames, the Lunar Dragon's blue moonfire, the Chimera's breath, the Volcano
Tortoise's crater and the Fire Salamander's tail. (The Eternal Phoenix, built wholly from angled parts, is shelved
for now, its design kept.) `PetRig` builds the angled parts as turned parts, `WedgePart`s, parts with a sphere
`SpecialMesh`, and small welded parts holding each `Fire`.

Rare pets give off light and particles (`pet:light`, `pet:particles`: sparkles, embers, bubbles, snow, or fireflies
that blink as they drift), and the rarest an aura (`pet:aura`): wisps of light winding up from a ring round their
feet, a soft glow pooled under them and sparks thrown up, built by `ModelEffects.addAura` on a flat invisible disc
welded to the pet's root.

To see a zone's pets without opening Studio, on a grassy stage beside a player, with their glow, flames and auras:

```bash
lune run tools/pet-preview 1
```

Then open `tools/out/pet-preview.html` in a browser (leave out the zone number for every pet).

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
  Controllers/           Egg drawing, riding and the riders' running animation (eggs and training sticks), HUD
                         updates, the shop and settings, pet animation, admin flight, the admin panel
  Ui/                    The Fusion HUD; the Eggs and Pets panels; the Shop, Settings and hub station panels
                         (Theme and Widgets hold the shared look); and the admin panel
tests/                 Automated tests (see below)
tools/                 egg-gallery.luau: a web page that shows every egg and pet model in 3D;
                       pet-preview.luau: a web page that stands a zone's pets on a Roblox-like stage;
                       map-preview.luau: a web page that shows the map in 3D;
                       ui-preview.luau: a web page that sketches the HUD and its panels;
                       rider-preview.luau: a web page that shows riders running on a rolling egg or training stick;
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
  stamina, cracking, the banks, the endless last zone, closures, shop prices, settings, luck boosts, the training
  stick's reps, bubbles, upgrades and rider's pose), and that every
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
