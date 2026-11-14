# Roll an Egg

A Roblox game: eggs roll down a long shared runway, players jump on and ride them to claim them, then hatch them
into pets back at their plot. The full design is in [docs/REQUEST.md](docs/REQUEST.md).

## What works so far

The first playable slice: **the runway, riding, and hatching**.

- The map: the hub, then a level, 120-stud-wide runway through six zones (Forest, Desert, Snow, Ocean, Volcano,
  Prehistoric), each with its own checkered ground, stepped cliffs (a boardwalk over a reef in the Ocean), plants
  and rocks, distant hills, and a gate with the zone's name (see [The runway](#the-runway)).
- Day and night: each runway cycle is one day. At sunrise every zone rolls a lineup of eggs that roll down the
  runway lap after lap; now and then an extra egg drops mid-cycle. Rarity sets their size, speed and stamina
  requirement. Rolling eggs kick up dust.
- Zone-themed obstacles on the runway. Eggs nobody is riding steer round them; riders have to steer clear
  themselves, or get bumped, thrown off, or burned.
- Every zone has 8 eggs, each with its own blocky model built from parts (see below).
- Blocky pet models for all 48 zone pets, rigged with joints so they can be animated (see below).
- Jump next to an egg to get on. Steer left/right. Stay on until the claim meter fills and the egg is yours.
- Stamina drains while riding. If it runs out first, you are thrown off and stunned.
- Leaving an egg makes it hop and lose a bounce; at zero bounces it cracks.
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
- A simple HUD: dollars (and what your pen earns a second), runway timer, zone, eggs held, stamina bar, claim meter.

The eggs, pets, runway and plots have their real look; the hub's plaza is still plain. Not built yet: duels, other
upgrades (Max Stamina and the rest), offline earnings, teleport pads, server events, the tutorial, and all sound.

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

Press **Play**. To keep editing code while Studio is open, use `rojo serve` with the Rojo Studio plugin instead.

Saving works in Studio only if the place is published and *Game Settings > Security > Enable Studio Access to API
Services* is on. Otherwise the game still runs and simply does not save.

### Controls

| Action | Keyboard | Phone / tablet | Gamepad |
| --- | --- | --- | --- |
| Get on an egg | Jump (Space) next to it | Jump button | A |
| Steer | A / D | Thumbstick | Left stick |
| Hop off | Jump again | Jump button | A |
| Eggs and pets | Click the **Eggs** / **Pets** tabs on the right | Tap them | Select them |
| Ride / get off your pet | **Ride** on its card, then the **RIDE** / **GET OFF** button | Tap them | Select them |
| Buy a bigger pen | Walk up to the green button by your gate, hold E | Hold its prompt | Hold X |

### Studio test tools

In Studio a small panel appears on the left of the screen. Its buttons only work in Studio, never in a live game:

- **Max stamina x5**: lets you ride eggs in deeper zones before upgrades exist.
- **Reset stamina**: back to 100.
- **Drop best egg here**: drops the rarest egg of the zone you are standing in.
- **Drop each egg here**: drops each of the zone's 8 eggs in turn.
- **Show this zone's pets**: stands the pets of the zone you are in (those with models so far) in front of you.
- **Get this zone's eggs**: puts one of each of the zone's 8 eggs straight into your inventory.
- **Hatch my eggs now**: finishes hatching every egg in your pen.
- **Give $1M**: a million dollars, to try buying a bigger pen.

## Eggs, pens and pets

Every egg you claim on the runway goes into your inventory. Open the **Eggs** tab on the right of the screen to see
them, each with its rarity and how long it takes to hatch, and a 3D preview of the one you pick.

**Your pen.** Your plot is one of 8 fenced pens at the hub, four down each side of the plaza, with your name over
the gate (`src/shared/Plots.luau` lays them out; `src/server/Services/PlotService.luau` hands them out and builds
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

## The runway

The runway is level and 120 studs wide, 600 studs per zone (`src/shared/Runway.luau`).

**Eggs.** Each runway cycle (3 minutes) is one day (`src/shared/CycleClock.luau`): the sun rises as a cycle
begins, night falls 70% of the way through, and the runway closes for the last 10 seconds before dawn. At sunrise
every zone rolls a lineup of 8 eggs with its usual odds. They leave the zone's chute 5 seconds apart, roll to a
quarter of the way into the next zone (the last zone's roll to the end cliff), fade out, and drop from the chute
again, lap after lap, until the runway closes. A lineup egg that is claimed or cracks comes back on its next lap.
About every 30 seconds a zone also drops an extra, mid-cycle egg that rolls once; Secret and Eternal eggs are 10
times rarer mid-cycle than at sunrise. A ridden egg rolls on past its fade line until its rider leaves it. The
numbers are in `src/shared/Config/Tuning.luau`; the rules are in `src/server/Logic/RunwaySim.luau`.

**Obstacles.** Each zone has its own obstacles in rows across the runway, laid out from a fixed seed so every
server and player gets the same runway (`src/shared/Obstacles.luau`; kinds, sizes and mixes in
`src/shared/Config/Obstacles.luau`). Every row leaves a gap wide enough for the biggest egg. What happens to the
rider of an egg that hits one:

| Zone | Bump (stamina lost, egg knocked aside) | Knock-off (thrown off, egg loses a bounce) | Lethal (rider dies) |
| --- | --- | --- | --- |
| Forest | fallen logs, stumps, bushes, toadstools | boulders, trees | |
| Desert | cacti, tumbleweeds, skulls | sandstone rocks, sand geysers* | |
| Snow | snowdrifts, snowmen | pines, ice boulders | |
| Ocean | coral, barrels | sea rocks, giant clams* | |
| Volcano | obsidian spikes | basalt columns, smoking rocks | lava pools, lava vents* |
| Prehistoric | giant ferns, dinosaur skulls | giant ribcages, mossy boulders | tar pits |

\* These go off now and then: a few seconds of warning (puffing smoke or sand, or a trembling shell), then a burst
or a snap. They are harmless in between. A Bump costs 10% of the egg's stamina requirement. Players on foot walk
round the solid ones and die in lava and tar.

An egg nobody is riding steers round every obstacle on its own, along a path worked out the same way on the server
and on every device. A ridden egg goes where its rider steers. The rider's device spots a hit at once and reports
it; the server checks the report, and also catches hits on its own when an egg is well inside an obstacle.

**The look** (`src/server/Map/`): `Scenery` builds each zone's checkered ground (blending into the next zone's
colours), stepped cliffs that players cannot climb (in the Ocean, a railed boardwalk over a reef with islets and a
lighthouse), the zone's plants and rocks on the banks, distant hills, mesas, mountains or volcanoes, and the gate.
`ObstacleModels` builds each obstacle, in the same blocky style as the eggs and pets, sized to the footprint the
rules use. The client adds the dust behind rolling eggs (`EggController`), animates the obstacles that go off
(`ObstacleController`), and runs the day and night (`DayNightController`).

To look at the map without opening Studio:

```bash
lune run tools/map-preview
```

Then open `tools/out/map-preview.html` in a browser: buttons along the top jump to each zone, drag to look round.

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

In Studio, **Drop each egg here** on the test panel drops all 8 of the zone's eggs, one after another. To see every
egg in 3D without opening Studio:

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

In Studio, **Show this zone's pets** on the test panel stands the zone's pets in front of you. They move as they would in
the game; set a pet's `Move` attribute in the Properties window (for example to `Fly`) to see its other moves.

To work on the models by hand in Studio, export them as model files:

```bash
lune run tools/export-models
```

This writes `tools/out/RollAnEgg-Pets.rbxm` and `tools/out/RollAnEgg-Eggs.rbxm`: every pet and every egg, built by
the game's own code (`PetRig`, `EggRig`), in a folder per zone, standing in rows on the ground (swimmers float). In
Studio, right-click Workspace in the Explorer, choose **Insert > Import Roblox Model**, and pick a file (older
Studios call it **Insert from File...**; or drag the file into the viewport). The pets come rigged, with a `Motor6D` per limb; they move when the game plays their animations.

## Project layout

```
default.project.json   How the folders below map into the Roblox place (read by Rojo)
docs/REQUEST.md        The agreed game design
src/shared/            ReplicatedStorage.Shared: config and math used by both server and client
  Config/                Zones, rarities, tuning numbers. Change game balance here.
src/server/            ServerScriptService.Server
  Logic/                 The rules of the game, with no Roblox objects, so they can be tested outside Studio
  Map/                   Builds the look of the map: zone scenery, obstacle models, the players' plots
  Services/              Connect the rules to players, saved data, the map, and remotes
src/client/            StarterPlayerScripts.Client
  Controllers/           Egg drawing, riding, HUD updates
  Ui/                    The Fusion HUD
tests/                 Automated tests (see below)
tools/                 egg-gallery.luau: a web page that shows every egg and pet model in 3D;
                       map-preview.luau: a web page that shows the map in 3D;
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
  stamina, bounces, closures), and that every egg and pet model exists, is unique and has nothing floating loose,
  and that every egg stays within its part budget. Pets have none. They are also checked for the limbs their skeleton needs, and for differently coloured
  blocks sharing a face (which flicker in Roblox).
- **Smoke tests** build the place with Rojo and run the real server and client scripts against a stand-in for
  Roblox Studio (`tests/studio.luau`). They catch misspelled properties and wiring mistakes.

The tests cannot check anything that needs the real engine: physics, animation, input, how things look and feel.
Those need a play test in Studio.

Code style and lint:

```bash
stylua src tests
```

```bash
selene src tests
```
