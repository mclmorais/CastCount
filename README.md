# Cast Count

A World of Warcraft: Forever addon that shows, in the top-left corner of each action button, how many times you can cast that spell with your current power.

It is built to be light on CPU:

- Action slots and spell costs are read only when the bars change, and a burst of changes is merged into one pass 0.2 seconds later.
- A power change reads no slots and no costs. It evaluates one curve per distinct spell cost and updates the labels.
- Forever hides the player's power from addons, so the count is computed by the client through `UnitPowerPercent` and a curve from power fraction to casts. The hidden result goes straight to the label.

Supports the Blizzard action bars, Bartender4, Dominos and ElvUI.

## Install

Copy this folder into `World of Warcraft\_forever_\Interface\AddOns\CastCount` and `/reload`. Turn off MissingPower, which draws its count in the same corner.

## Debug

`/castcount` prints how many buttons were found, how many have a cost, whether power is hidden, and what the client returns for the first three filled buttons.

## Type check

`.\scripts\check.ps1` checks `CastCount.lua` with [lua-language-server](https://github.com/LuaLS/lua-language-server) against [Ketho's WoW API annotations](https://github.com/Ketho/vscode-wow-api). The first run downloads both, at the versions pinned in the script, into `.tools/` (gitignored). It fails on unknown globals and on calls with missing, extra or wrongly typed arguments. It does not catch a misspelled method on a frame, because the annotations type `CreateFrame`'s result as a plain table too. The annotations follow the retail API, which Forever shares for the most part.

Editors that use lua-language-server pick up the same settings from `.luarc.json` once the script has run.

To run it before every commit that touches a `.lua` file or `.luarc.json`, turn on the repo's hooks once per clone:

```
git config core.hooksPath .githooks
```

The hook checks the files on disk, not only what is staged.

## Verify in the simulator

Cast Count is checked in [wow-ui-sim](https://github.com/Osso/wow-ui-sim). Download its Forever build (`wow-ui-sim-<version>-forever-windows-x86_64.zip` from the releases page), unzip it, and point `WOW_SIM` at `wow-sim.exe` in a `.env` file at the repo root (gitignored):

```
WOW_SIM=C:\path\to\wow-ui-sim-forever\wow-sim.exe
```

`$env:WOW_SIM` and `-Sim` override the file.

Then, from this folder:

| Command | What it does |
| --- | --- |
| `.\scripts\sim.ps1 test` | Runs `tests/*.lua` headless. Fails on a failed test or on any Lua error raised in `CastCount.lua`, which the simulator's test runner alone does not count as a failure. |
| `.\scripts\sim.ps1 gui` | Opens the simulator window with Cast Count loaded and [scripts/sim-demo.lua](scripts/sim-demo.lua) applied: a mage at 1000 mana, Fireball in slots 1 and 3 (shows 20), Frostbolt in slot 2 (shows 10). |
| `.\scripts\sim.ps1 screenshot` | Renders that scene headless to `.sim/screenshot.png` (`-Output` to change it, `-Crop bar` for just the main action bar). |

`-Class Warrior` picks another class; `-Sim` overrides `WOW_SIM`. The script links this folder into a temp addons root as `CastCount`, so the checkout can have any name.

Claude Code sessions in this repo have a `sim-verify` skill ([.claude/skills/sim-verify](.claude/skills/sim-verify/SKILL.md)). It runs the tests, renders the action bar, and has Claude read the numbers off the image.

The simulator does not hide the player's power, so these checks cover the readable-power path only.
