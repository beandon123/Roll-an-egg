# Roll an Egg

A Roblox game: eggs roll down a long shared runway, players jump on and ride them to claim them, then hatch them
into pets back at their plot. The full design is in [docs/REQUEST.md](docs/REQUEST.md).

## What works so far

The first playable slice: **the runway and riding**, plus **the hub** with its shops.

- A placeholder map: five zone slabs (Forest, Desert, Snow, Ocean, Volcano) and their signs, and the hub behind the
  start of the runway: the START ZONE pad, the Trails stall, the Sell stall, the fuse machine, eight fenced pens,
  and a ring of low-poly mountains round it all (the only way out is the runway).
- Eggs drop in every zone and roll down the runway. Rarity sets their size, speed, color and stamina requirement.
- Jump next to an egg to get on. Steer left/right. Stay on until the claim meter fills and the egg is yours.
- Stamina drains while riding. If it runs out first, you are thrown off and stunned.
- Leaving an egg makes it hop and lose a bounce; at zero bounces it cracks.
- The 3-minute runway cycle: a warning, then a 10-second closure that clears every egg without a rider.
- Claimed eggs are saved to the player's data (ProfileStore).
- **Sell stall**: sell eggs you don't want for coins (half the egg's stamina requirement each).
- **Trails shop**: buy trails with coins. The equipped trail streams behind you and multiplies your Max Stamina.
- **Fuse machine**: its panel explains it (3 of the same pet -> an egg of that pet, one size bigger; each pet put in
  has a 1 in 3 chance to pass on its variant and to set the size). The rules are written and tested
  (`Logic/Fuse`); fusing itself arrives with pets.
- A simple HUD: runway timer, zone, coins, eggs held, stamina bar, claim meter, and the station panels.

Everything visual is a placeholder made of plain parts. Not built yet: obstacles, duels, pen ownership and nests,
hatching, pets and mounts, fusing, selling pets, upgrades, teleport pads, server events, the tutorial, and all final
art and sound.

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
| Use a stall or the fuse machine | E next to it | Tap its prompt | X |

### Studio test tools

In Studio a small panel appears on the right of the screen. Its buttons only work in Studio, never in a live game:

- **Max stamina x5**: lets you ride eggs in deeper zones before upgrades exist.
- **Reset stamina**: back to normal (100, times your trail's boost).
- **Drop best egg here**: drops the rarest egg of the zone you are standing in.
- **+10K coins**: coins to try the Trails shop with.

## Project layout

```
default.project.json   How the folders below map into the Roblox place (read by Rojo)
docs/REQUEST.md        The agreed game design
src/shared/            ReplicatedStorage.Shared: config and math used by both server and client
  Config/                Zones, rarities, tuning numbers, trails, sell prices. Change game balance here.
  HubLayout.luau         Where everything at the hub is (stations, pens, mountains). Change the hub's layout here.
src/server/            ServerScriptService.Server
  Logic/                 The rules of the game, with no Roblox objects, so they can be tested outside Studio
  Map/                   Builds the placeholder hub, mountains, and shared part helpers
  Services/              Connect the rules to players, saved data, the map, and remotes
src/client/            StarterPlayerScripts.Client
  Controllers/           Egg drawing, riding, the hub stations, HUD updates
  Ui/                    The Fusion HUD and the station panels
tests/                 Automated tests (see below)
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
  stamina, bounces, closures, the hub layout, buying trails, selling eggs, fusing).
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
