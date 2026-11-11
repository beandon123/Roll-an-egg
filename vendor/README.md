# Vendored libraries

These are other people's open-source libraries, copied into the repository unchanged so the project builds
straight after cloning (no package manager step). Do not edit them here; to update one, replace its folder with
a newer release.

| Library | Version | Used for | Source | License |
| --- | --- | --- | --- | --- |
| Fusion | 0.3 (tag `v0.3-beta`, commit `77e6035`) | UI | https://github.com/dphfox/Fusion | MIT (`Fusion/LICENSE`) |
| ProfileStore | 1.0.3 (commit `45c9847`) | Saving player data | https://github.com/MadStudioRoblox/ProfileStore | Apache 2.0 (`ProfileStore/LICENSE`) |

Where they end up in the game (see `default.project.json`):

- `vendor/Fusion/src` -> `ReplicatedStorage.Packages.Fusion`
- `vendor/ProfileStore/ProfileStore.luau` -> `ServerScriptService.ServerPackages.ProfileStore`
