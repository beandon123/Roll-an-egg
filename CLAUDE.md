# Roll an Egg: notes for Claude

Read this before starting work. It gathers what earlier Claude sessions (all in the cloud, 5-21 Nov 2026) learned about
the project and how its owner likes to work. The game itself is described in two files that stay the real source of
truth:

- `docs/REQUEST.md`: the agreed design. Items marked **(decided)** were confirmed by the owner; **(proposed)** items
  are defaults that can still change. Anything built is recorded there too.
- `README.md`: what works so far, controls, how each system works, project layout, tests.

## Working with the owner

- The owner is building their first Roblox game with Claude and is not a programmer. Explain in plain words, give
  exact step-by-step instructions (which window, which button), and put any command they should run in its own code
  block. They use **Windows** with PowerShell and Roblox Studio.
- They often send **reference screenshots** from other Roblox games to show the look or feel they want. Match the
  idea in the game's own original style; never copy another game's names, art or characters.
- When a request is ambiguous (odds, sizes, which egg they mean), build the most likely reading, then ask a short
  question naming the alternative. Record the answer as (decided) in `docs/REQUEST.md`.
- After a change, tell them what to look for in a Studio play test. The automated tests cannot check physics,
  animation, input or how things look.
- Retired content is **shelved, not deleted** (for example the shelved eggs and pets, and the Eternal Phoenix) so it
  can come back later.

## How changes reach Studio

The code syncs into Studio with **Rojo** (`default.project.json`). There are two ways:

- **Live sync (preferred):** run `rojo serve` in the repo folder, open the place in Studio and press **Connect** in
  the Rojo plugin. Every file change shows up in Studio at once, whatever branch is checked out. Install the plugin
  once with `rojo plugin install`.
- **Rebuild:** `rojo build -o RollAnEgg.rbxl`, then open it with *File > Open from File*.

In a session on the owner's own computer, edits reach Studio straight away and nothing needs merging or pushing to
test them. Edits made in a cloud session reach Studio only once they are pushed and pulled into the local folder.
Publishing to the live game is done from Studio (*File > Publish to Roblox*) and has nothing to do with git.

Tools are pinned in `rokit.toml` (Rojo 7.7.1, Selene, StyLua, Lune); `rokit install` gets them all.

## Before you finish a change

```bash
lune run tests/run
```

```bash
stylua src tests
```

```bash
selene src tests
```

- All tests must pass. Add or update rule tests in `tests/specs/` for any rule or number you change.
- Update `docs/REQUEST.md` (mark what was decided or built) and `README.md` (what works, how it works) in the same
  change.
- Commit messages are one plain sentence saying what changed for the player, for example "Make riders run on their
  eggs, reacting to steering, bumps and stamina".

## Ground rules in the code

- **The server decides everything that matters** (mounts, stamina, claims, purchases, prices, saved data). Clients
  only ask and steer, and never send currency, rarity or time values. Every remote is in `src/shared/Net.luau`.
- **Rules live in `src/server/Logic/` and `src/shared/`** as plain Luau with no Roblox objects, so Lune can test them
  outside Studio. Services in `src/server/Services/` wire them to players, data and remotes.
- **Balance numbers live in config** (`src/shared/Config/`, especially `Tuning.luau`), not scattered in code.
- **Eggs are not server parts.** Each device draws them from the shared server clock (`Shared/EggMotion`).
- **Timers are timestamps**, never running counters, so hatching and offline progress survive restarts.
- **Models are built from parts in code**, in a blocky voxel style: eggs in `src/shared/EggModels`, pets in
  `src/shared/PetModels`. No meshes. Secret and Eternal pets are showpieces with much more detail (angled parts,
  wedges, sphere meshes and Fire are allowed there). Egg part budgets are enforced by the tests.
- Preview pages for checking looks without Studio: `lune run tools/egg-gallery`, `tools/map-preview`,
  `tools/ui-preview`, `tools/rider-preview`.
- `vendor/` (Fusion, ProfileStore) is copied in unchanged. Don't edit it.
- Audience is ages 8-14: keep everything under-13 compliant (filtered text, cartoon splats, no off-platform links).

## Branches (as of 21 Nov 2026)

- The default branch is **`claude/epic-hamilton-ggi63x`**. There is no `main`. Finished work is merged into it,
  usually through a pull request.
- Two branches have work that is **not yet merged** into it:
  - `claude/blissful-pascal-w94kha`: the **Jungle zone** (added after Snow) with its 8 chosen pets and their eggs (4
    more candidates shelved), the reworked Mantis Empress, the Titan Anaconda's coil-and-slither, the Prehistoric
    pets redrawn in the showpiece style, livelier Leviathan and Kraken, and smoother pet movement. This is the
    newest and largest piece of work.
  - `claude/stoic-cerf-af3jxa`: Secret-and-above egg alerts shown as shiny white lines along the top of the screen,
    with a sparkle sound.
- Every other `claude/...` branch is already contained in the default branch.
- If the owner wants these in the game, merge them into the default branch and run the tests. Both changed
  overlapping files, so expect to resolve conflicts.

## Not built yet

From `README.md` and `docs/REQUEST.md`: egg duels (PvP), other upgrades, offline earnings, teleport pads, the Titan
Egg event, the tutorial, the Growing Eggs menu with Grow All and Skip, and sound beyond the Secret egg alert. Fusing
has tested rules (`src/server/Logic/Fuse.luau`) but no working machine in the game yet.
