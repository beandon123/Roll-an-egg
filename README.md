# Roll an Egg

A Roblox game: eggs roll down a long shared runway, players jump on and ride them to claim them, then hatch them
into pets back at their plot. The full design is in [docs/REQUEST.md](docs/REQUEST.md).

## What works so far

The first playable slice: **the runway and riding**, plus **the shop and settings**.

- A placeholder map: the hub, a painted START ZONE where the runway begins, five zone slabs (Forest, Desert, Snow,
  Ocean, Volcano) and their signs. The runway is 120 studs wide, with walls down both sides that are broken by gaps
  (marked with red strips) where a player on foot can fall off.
- A "Top Egg Claimers" leaderboard board beside the start zone (all servers, from an OrderedDataStore; it falls
  back to the players in the server when the store cannot be reached).
- Eggs drop in every zone and roll down the runway. Rarity sets their size, speed, color and stamina requirement.
- Jump next to an egg to get on. Steer left/right. Stay on until the claim meter fills and the egg is yours.
- Stamina drains while riding. If it runs out first, you are thrown off and stunned.
- Leaving an egg makes it hop and lose a bounce; at zero bounces it cracks.
- The 3-minute runway cycle: a warning, then a 10-second closure that clears every egg without a rider.
- Claimed eggs are saved to the player's data (ProfileStore).
- The HUD: runway timer and zone (top), Shop and Settings tabs on the left edge with Max Stamina, coins and eggs
  under them (the "+" buttons open the shop at that section), a timer while a server luck boost runs, and the
  stamina and claim meters (bottom).
- **Shop** ("Coop Shop"): next pen level for Robux or coins, x2 / x4 server luck for 15 minutes (rarer eggs for
  everyone), Max Stamina packs, Double Your Stamina (each purchase doubles Max Stamina, from x2 up to x1024), coin
  packs, and the x2 Coins pass. Robux purchases are granted exactly once, and only reported to Roblox once saved.
- **Settings**: Music / Effects / Nature volume, show others' pets / your pets, reduce camera shake, vibration.
  Saved to the player's account.

The world is a placeholder made of plain parts and the UI uses emoji for icons. Not built yet: obstacles, duels,
plots and pens, hatching, pets and mounts, coin income and upgrades, teleport pads, server events, the tutorial, and
all final art and sound. So for now, pen levels and the x2 Coins pass are recorded but have nothing to act on, and
the pet and comfort settings are saved for the systems that will read them.

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

### Selling things for Robux

Every price and amount is in `src/shared/Config/Shop.luau`. Each Robux item needs its ID from the Creator
Dashboard (*Monetization > Developer Products* or *Passes*), pasted into its `productId` / `gamePassId`. There is
one developer product per pen level and one per stamina doubling (x1 to x2, x2 to x4 ...), because a product's
price is fixed.

While an ID is `0`, the item cannot be bought in a live game ("This isn't for sale yet"). In Studio, buying it grants
it straight away, so the whole shop can be tried before the products exist. The price shown comes from Roblox once an
ID is set, so changing a price on the dashboard is enough.

### Studio test tools

In Studio a small panel appears on the right of the screen. Its buttons only work in Studio, never in a live game:

- **Max stamina x5**: lets you ride eggs in deeper zones before upgrades exist.
- **Reset stamina**: back to normal (100, plus any Max Stamina bought in the shop, times any doublings).
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
  Ui/                    The Fusion HUD, Shop and Settings panels (Theme and Widgets hold the shared look)
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
  stamina, bounces, closures, shop prices, settings, luck boosts).
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
