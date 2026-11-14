# Roll an Egg

A Roblox game: eggs roll down a long shared runway, players jump on and ride them to claim them, then hatch them
into pets back at their plot. The full design is in [docs/REQUEST.md](docs/REQUEST.md).

## What works so far

The first playable slice: **the runway and riding**.

- A placeholder map: the hub, five zone slabs (Forest, Desert, Snow, Ocean, Volcano) and their signs.
- Eggs appear on the ground at the start of every zone and roll down the runway, leaving a small trail of dust.
  Rarity sets their size, speed, color and stamina requirement.
- When a Secret or Eternal egg spawns, every player gets an on-screen message saying where and when. Other eggs
  spawn quietly.
- Jump next to an egg to get on. Steer left/right. Stay on until the claim meter fills and the egg is yours.
- Stamina drains while riding. If it runs out first, you are thrown off and stunned.
- Leaving an egg makes it hop and lose a bounce; at zero bounces it cracks.
- The 3-minute runway cycle: a warning, then a 10-second closure that clears every egg without a rider.
- Claimed eggs are saved to the player's data (ProfileStore).
- A simple HUD: runway timer, zone, coins, eggs held, stamina bar, claim meter.

Everything visual is a placeholder made of plain parts. Not built yet: obstacles, duels, plots and pens, hatching,
pets and mounts, coins and upgrades, teleport pads, server events, the tutorial, and all final art and sound.

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

### Studio test tools

In Studio a small panel appears on the right of the screen. Its buttons only work in Studio, never in a live game:

- **Max stamina x5**: lets you ride eggs in deeper zones before upgrades exist.
- **Reset stamina**: back to 100.
- **Drop best egg here**: drops the rarest egg of the zone you are standing in.

## Project layout

```
default.project.json   How the folders below map into the Roblox place (read by Rojo)
docs/REQUEST.md        The agreed game design
src/shared/            ReplicatedStorage.Shared: config and math used by both server and client
  Config/                Zones, rarities, tuning numbers. Change game balance here.
src/server/            ServerScriptService.Server
  Logic/                 The rules of the game, with no Roblox objects, so they can be tested outside Studio
  Services/              Connect the rules to players, saved data, the map, and remotes
src/client/            StarterPlayerScripts.Client
  Controllers/           Egg drawing, riding, HUD updates
  Ui/                    The Fusion HUD
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
  stamina, bounces, closures).
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
