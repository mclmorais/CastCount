local FIREBALL, FROSTBOLT = 133, 116
local SETTLE = 0.3

pcall(A_Admin.SetManualClock, GetTime())

local function costOf(spellId)
    local costs = C_Spell.GetSpellPowerCost(spellId)
    return costs and costs[1] and costs[1].cost
end

local function topLeftNumber(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            local point = region:GetPoint(1)
            local text = region:GetText()
            if point == "TOPLEFT" and text and text:match("^[%d.]*$") then return text end
        end
    end
end

local function labelText(button)
    for _, child in ipairs({ button:GetChildren() }) do
        local text = topLeftNumber(child)
        if text then return text end
    end
    return topLeftNumber(button)
end

local function setPower(mana)
    A_Admin.SetPlayerPower(mana, 5000, 0)
    A_Admin.FireEvent("UNIT_POWER_UPDATE", "player", "MANA")
end

local function placeSpell(slot, spellId)
    A_Admin.SetActionSlot(slot, spellId)
    A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", slot)
end

local function setDecimals(decimals)
    Settings.GetSetting("CastCount_Decimals"):SetValue(decimals)
end

local function casts(mana, spellId)
    return tostring(math.floor(mana / costOf(spellId)))
end

test("simulator gives Fireball and Frostbolt a mana cost", function()
    print("Fireball cost", costOf(FIREBALL), "Frostbolt cost", costOf(FROSTBOLT))
    assertTrue((costOf(FIREBALL) or 0) > 0)
    assertTrue((costOf(FROSTBOLT) or 0) > 0)
end)

test("counts casts on action buttons after bars change", function()
    setPower(1000)
    placeSpell(1, FIREBALL)
    placeSpell(2, FROSTBOLT)
    A_Admin.AdvanceTime(SETTLE)
    assertEquals(casts(1000, FIREBALL), labelText(ActionButton1))
    assertEquals(casts(1000, FROSTBOLT), labelText(ActionButton2))
end)

test("bar changes wait for the debounce before rebuilding", function()
    setPower(1000)
    placeSpell(4, FROSTBOLT)
    assertEquals("", labelText(ActionButton4) or "")
    A_Admin.AdvanceTime(SETTLE)
    assertEquals(casts(1000, FROSTBOLT), labelText(ActionButton4))
end)

test("power change updates counts immediately", function()
    placeSpell(1, FIREBALL)
    A_Admin.AdvanceTime(SETTLE)
    setPower(costOf(FIREBALL) * 2 + 1)
    assertEquals("2", labelText(ActionButton1))
    setPower(0)
    assertEquals("0", labelText(ActionButton1))
end)

test("emptied slot clears its number", function()
    setPower(1000)
    placeSpell(3, FIREBALL)
    A_Admin.AdvanceTime(SETTLE)
    assertEquals(casts(1000, FIREBALL), labelText(ActionButton3))
    A_Admin.ClearActionSlot(3)
    A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 3)
    A_Admin.AdvanceTime(SETTLE)
    assertEquals("", labelText(ActionButton3) or "")
end)

test("counts stay right through combat", function()
    placeSpell(1, FIREBALL)
    A_Admin.AdvanceTime(SETTLE)
    A_Admin.SetInCombat(true)
    setPower(1000)
    assertEquals(casts(1000, FIREBALL), labelText(ActionButton1))
    A_Admin.SetInCombat(false)
    A_Admin.AdvanceTime(SETTLE)
    assertEquals(casts(1000, FIREBALL), labelText(ActionButton1))
end)

test("counts round down, so a cast just out of reach shows 0", function()
    placeSpell(1, FIREBALL)
    A_Admin.AdvanceTime(SETTLE)
    local cost = costOf(FIREBALL)
    setPower(cost - 1)
    assertEquals("0", labelText(ActionButton1))
    setPower(cost * 2 - 1)
    assertEquals("1", labelText(ActionButton1))
    setPower(cost * 2)
    assertEquals("2", labelText(ActionButton1))
end)

test("decimal places option shows fractions, still rounded down", function()
    placeSpell(1, FIREBALL)
    A_Admin.AdvanceTime(SETTLE)
    local cost = costOf(FIREBALL)
    setPower(cost * 2 - 1)
    setDecimals(1)
    assertEquals("1.9", labelText(ActionButton1))
    setDecimals(2)
    assertEquals(string.format("%.2f", math.floor((cost * 2 - 1) * 100 / cost) / 100), labelText(ActionButton1))
    setPower(cost * 2)
    assertEquals("2.00", labelText(ActionButton1))
    setPower(0)
    assertEquals("0.00", labelText(ActionButton1))
    setDecimals(0)
    assertEquals("0", labelText(ActionButton1))
end)
