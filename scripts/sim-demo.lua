-- Puts a mage with 1000 / 5000 mana and some spells on the main bar, so Cast Count has numbers to draw.
-- Expected: Fireball (slots 1 and 3) shows 20, Frostbolt (slot 2) shows 10.
local FIREBALL, FROSTBOLT = 133, 116

A_Admin.SetPlayerPower(1000, 5000, 0)
for slot, spellId in ipairs({ FIREBALL, FROSTBOLT, FIREBALL }) do
    A_Admin.SetActionSlot(slot, spellId)
    A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", slot)
end
A_Admin.FireEvent("UNIT_POWER_UPDATE", "player", "MANA")
