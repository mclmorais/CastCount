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

## Tests

`tests/castcount.lua` runs in [wow-ui-sim](https://github.com/Osso/wow-ui-sim) with its Forever build:

```
wow-sim --no-saved-vars --allow-ui-version-mismatch --addons-path <folder containing CastCount> run-tests CastCount
```

The simulator does not hide the player's power, so these tests cover the readable-power path only.
