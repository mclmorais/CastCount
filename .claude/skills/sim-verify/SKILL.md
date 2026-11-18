---
name: sim-verify
description: Verify Cast Count in wow-ui-sim, by test run and by looking at a rendered action bar. Use after changing CastCount.lua, tests, or anything that affects the pips or numbers drawn on action buttons, and before saying a change works.
---

# Verify Cast Count in the simulator

The script is `scripts/sim.ps1` (PowerShell). It finds the simulator through `-Sim`, `$env:WOW_SIM`, then `WOW_SIM=` in `.env` at the repo root. If none is set, stop and ask the user for the path to the Forever build's `wow-sim.exe`. Each run takes about 30 seconds.

## 1. Tests

```powershell
.\scripts\sim.ps1 test
```

Exit 0 means every test passed and `CastCount.lua` raised no Lua error. On failure the output names the failed test and its assertion, or lists `CastCount.lua:<line>: <message>`. Errors from `Blizzard_*` addons (SocialToast, ScriptErrors) come from the simulator and are not ours.

## 2. Look at it

```powershell
.\scripts\sim.ps1 screenshot -Crop bar -Output .sim\bar.png
```

Then open `.sim\bar.png` with the Read tool and check it with your own eyes. The scene comes from `scripts/sim-demo.lua`: a mage at 400 / 5000 mana, Auto Attack (no cost) in slot 1, Fireball (cost 50) in slot 2, Frostbolt (cost 100) in slot 3. The default display is the pip bar with 6 pips. The image is 600x70, so crop the first few buttons and upscale them 4x (PIL, nearest neighbour) before reading it, or the pips are too small to count.

Expected: slot 1 has no pips. Slot 2 has a column of 6 blue pips at its left edge, all lit, and a small white **+** beside the bottom pip (8 casts). Slot 3 has the top 4 pips lit and the bottom 2 dark (4 casts). The column must not cover the keybind number in the top-right corner. With the number display, slots 2 and 3 show **8** and **4**. Other buttons hold whatever the simulator's default character has and may show their own pips. The gryphon art covers the left edge of slot 1, which is why slot 1 holds the spell with no cost.

Use `.\scripts\sim.ps1 screenshot` with no `-Crop` for the full 1600x1200 UI (`.sim\screenshot.png`), when you need the bars around the main one.

To check another case, change `scripts/sim-demo.lua` (power, spells, slots) and render again. `A_Admin` calls available: `SetPlayerPower(cur, max, type)`, `SetActionSlot(slot, spellId)`, `ClearActionSlot(slot)`, `FireEvent(name, ...)`, `SetInCombat(bool)`. Put the demo back unless the user wants the new scene kept, and update the expected values above if they keep it.

## 3. Report

Say which of the two steps ran and what you saw: the test summary line, and the pips or numbers you read off the image. If a step could not run, say so. Do not report the change as working from the tests alone when it changes what is drawn.

## Limits

The simulator does not hide the player's power the way Forever does, so neither step covers the secret-power path through `UnitPowerPercent`. Say this when the change touches that path.

`.\scripts\sim.ps1 gui` opens a live window for the user. You cannot see that window, so use the screenshot.
