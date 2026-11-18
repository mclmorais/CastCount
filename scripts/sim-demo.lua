-- Puts a mage with 400 / 5000 mana and some spells on the main bar, so Cast Count has something to draw.
-- Expected with the pip bar (default, 6 pips): Auto Attack (slot 1, no cost) no pips,
-- Fireball (slot 2, 8 casts) all 6 lit and a +, Frostbolt (slot 3, 4 casts) the top 4 lit.
-- With the number display: nothing, 8, 4.
local FIREBALL, FROSTBOLT, AUTO_ATTACK = 133, 116, 6603

A_Admin.SetPlayerPower(400, 5000, 0)
for slot, spellId in ipairs({ AUTO_ATTACK, FIREBALL, FROSTBOLT }) do
    A_Admin.SetActionSlot(slot, spellId)
    A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", slot)
end
A_Admin.FireEvent("UNIT_POWER_UPDATE", "player", "MANA")
