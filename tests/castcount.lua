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

local function casts(mana, spellId)
    return tostring(math.floor(mana / costOf(spellId)))
end

local OPTION_DEFAULTS = { enabled = true, display = "pips", pips = 6, decimals = 0, font = "Fonts\\ARIALN.TTF", color = "ffffffff", size = 12, x = 2, y = 2 }

local function option(key)
    return Settings.GetSetting("CastCount_" .. key)
end

local function resetOptions()
    for key, default in pairs(OPTION_DEFAULTS) do option(key):SetValue(default) end
    A_Admin.AdvanceTime(SETTLE)
end

local function labelOf(button)
    for _, child in ipairs({ button:GetChildren() }) do
        local regions = { child:GetRegions() }
        if #regions == 1 and regions[1]:GetObjectType() == "FontString" then return regions[1], child end
    end
end

local function withOptions(fn)
    local ok, err = pcall(fn)
    resetOptions()
    assertEquals("ok", ok and "ok" or tostring(err))
end

-- The number display, for the tests written against it. The pip bar is the default.
local function withNumber(fn)
    withOptions(function()
        option("display"):SetValue("number")
        fn()
    end)
end

local function numberTest(name, fn)
    test(name, function() withNumber(fn) end)
end

test("simulator gives Fireball and Frostbolt a mana cost", function()
    print("Fireball cost", costOf(FIREBALL), "Frostbolt cost", costOf(FROSTBOLT))
    assertTrue((costOf(FIREBALL) or 0) > 0)
    assertTrue((costOf(FROSTBOLT) or 0) > 0)
end)

numberTest("counts casts on action buttons after bars change", function()
    setPower(1000)
    placeSpell(1, FIREBALL)
    placeSpell(2, FROSTBOLT)
    A_Admin.AdvanceTime(SETTLE)
    assertEquals(casts(1000, FIREBALL), labelText(ActionButton1))
    assertEquals(casts(1000, FROSTBOLT), labelText(ActionButton2))
end)

numberTest("bar changes wait for the debounce before rebuilding", function()
    setPower(1000)
    placeSpell(4, FROSTBOLT)
    assertEquals("", labelText(ActionButton4) or "")
    A_Admin.AdvanceTime(SETTLE)
    assertEquals(casts(1000, FROSTBOLT), labelText(ActionButton4))
end)

numberTest("power change updates counts immediately", function()
    placeSpell(1, FIREBALL)
    A_Admin.AdvanceTime(SETTLE)
    setPower(costOf(FIREBALL) * 2 + 1)
    assertEquals("2", labelText(ActionButton1))
    setPower(0)
    assertEquals("0", labelText(ActionButton1))
end)

numberTest("emptied slot clears its number", function()
    setPower(1000)
    placeSpell(3, FIREBALL)
    A_Admin.AdvanceTime(SETTLE)
    assertEquals(casts(1000, FIREBALL), labelText(ActionButton3))
    A_Admin.ClearActionSlot(3)
    A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 3)
    A_Admin.AdvanceTime(SETTLE)
    assertEquals("", labelText(ActionButton3) or "")
end)

numberTest("counts stay right through combat", function()
    placeSpell(1, FIREBALL)
    A_Admin.AdvanceTime(SETTLE)
    A_Admin.SetInCombat(true)
    setPower(1000)
    assertEquals(casts(1000, FIREBALL), labelText(ActionButton1))
    A_Admin.SetInCombat(false)
    A_Admin.AdvanceTime(SETTLE)
    assertEquals(casts(1000, FIREBALL), labelText(ActionButton1))
end)

test("options panel registers a Cast Count category with all its settings", function()
    local found
    for _, category in ipairs(SettingsPanel:GetAllCategories()) do
        if category:GetName() == "Cast Count" then found = category end
    end
    assertTrue(found ~= nil)
    for key in pairs(OPTION_DEFAULTS) do
        assertTrue(option(key) ~= nil)
        assertEquals(OPTION_DEFAULTS[key], option(key):GetValue())
        assertEquals(OPTION_DEFAULTS[key], CastCountDB[key])
    end
end)

test("disabling hides the numbers and re-enabling restores them", function()
    withNumber(function()
        setPower(1000)
        placeSpell(1, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        local _, holder = labelOf(ActionButton1)
        assertTrue(holder:IsShown())
        option("enabled"):SetValue(false)
        assertTrue(not holder:IsShown())
        placeSpell(2, FROSTBOLT)
        A_Admin.AdvanceTime(SETTLE)
        setPower(500)
        option("enabled"):SetValue(true)
        assertTrue(holder:IsShown())
        assertEquals(casts(500, FIREBALL), labelText(ActionButton1))
        assertEquals(casts(500, FROSTBOLT), labelText(ActionButton2))
    end)
end)

test("size, color and offsets restyle existing labels", function()
    withNumber(function()
        placeSpell(1, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        local label = labelOf(ActionButton1)
        local _, size = label:GetFont()
        assertEquals(12, size)
        option("size"):SetValue(18)
        local _, newSize = label:GetFont()
        assertEquals(18, newSize)
        option("color"):SetValue("ffff0000")
        local r, g, b = label:GetTextColor()
        assertEquals(1, r)
        assertEquals(0, g)
        assertEquals(0, b)
        option("x"):SetValue(9)
        option("y"):SetValue(7)
        local point, _, _, x, y = label:GetPoint(1)
        assertEquals("TOPLEFT", point)
        assertEquals(9, x)
        assertEquals(-7, y)
    end)
end)

test("a label created after a style change uses the saved style", function()
    withNumber(function()
        option("size"):SetValue(20)
        option("x"):SetValue(5)
        placeSpell(7, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        local label = labelOf(ActionButton7)
        local _, size = label:GetFont()
        local _, _, _, x = label:GetPoint(1)
        assertEquals(20, size)
        assertEquals(5, x)
    end)
end)

test("font option switches the font of existing labels", function()
    withNumber(function()
        placeSpell(1, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        local label = labelOf(ActionButton1)
        option("font"):SetValue("Fonts\\FRIZQT__.TTF")
        local path, size = label:GetFont()
        assertEquals("fonts\\frizqt__.ttf", path:lower())
        assertEquals(12, size)
    end)
end)

numberTest("counts round down, so a cast just out of reach shows 0", function()
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
    withNumber(function()
        placeSpell(1, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        local cost = costOf(FIREBALL)
        setPower(cost * 2 - 1)
        option("decimals"):SetValue(1)
        assertEquals("1.9", labelText(ActionButton1))
        option("decimals"):SetValue(2)
        assertEquals(string.format("%.2f", math.floor((cost * 2 - 1) * 100 / cost) / 100), labelText(ActionButton1))
        setPower(cost * 2)
        assertEquals("2.00", labelText(ActionButton1))
        setPower(0)
        assertEquals("0.00", labelText(ActionButton1))
        option("decimals"):SetValue(0)
        assertEquals("0", labelText(ActionButton1))
    end)
end)

-- The pip column is the frame whose first region is the "+" FontString.
local function pipColumn(button)
    for _, holder in ipairs({ button:GetChildren() }) do
        for _, column in ipairs({ holder:GetChildren() }) do
            local plus = column:GetRegions()
            if plus and plus:GetObjectType() == "FontString" and plus:GetText() == "+" then return column, plus end
        end
    end
end

-- Returns "lit/total" pips, plus "+" when the overflow mark shows, or "none" when no column is shown.
local function pipText(button)
    local column, plus = pipColumn(button)
    if not column or not column:IsShown() then return "none" end
    local lit, total, litAfterDark = 0, 0, false
    for _, pip in ipairs({ column:GetChildren() }) do
        if pip:IsShown() then
            total = total + 1
            local fill = select(3, pip:GetRegions())
            if fill:GetAlpha() > 0.5 then
                if lit < total - 1 then litAfterDark = true end
                lit = lit + 1
            end
        end
    end
    assertTrue(not litAfterDark)
    return lit .. "/" .. total .. (plus:GetAlpha() > 0.5 and "+" or "")
end

test("pip bar is the default and lights one pip per cast", function()
    withOptions(function()
        placeSpell(1, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        local cost = costOf(FIREBALL)
        setPower(cost * 4)
        assertEquals("4/6", pipText(ActionButton1))
        setPower(cost * 4 - 1)
        assertEquals("3/6", pipText(ActionButton1))
        setPower(0)
        assertEquals("0/6", pipText(ActionButton1))
        assertEquals("", labelText(ActionButton1) or "")
    end)
end)

test("pip bar caps at the maximum and shows + past it", function()
    withOptions(function()
        placeSpell(1, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        local cost = costOf(FIREBALL)
        setPower(cost * 6)
        assertEquals("6/6", pipText(ActionButton1))
        setPower(cost * 7)
        assertEquals("6/6+", pipText(ActionButton1))
        setPower(cost * 20)
        assertEquals("6/6+", pipText(ActionButton1))
    end)
end)

test("maximum pips option resizes existing columns", function()
    withOptions(function()
        placeSpell(1, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        local cost = costOf(FIREBALL)
        setPower(cost * 5)
        assertEquals("5/6", pipText(ActionButton1))
        option("pips"):SetValue(3)
        assertEquals("3/3+", pipText(ActionButton1))
        option("pips"):SetValue(10)
        assertEquals("5/10", pipText(ActionButton1))
    end)
end)

test("pip column stays inside the button with the first pip at the top-left", function()
    withOptions(function()
        option("pips"):SetValue(10)
        placeSpell(1, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        local column = pipColumn(ActionButton1)
        local point, _, _, x, y = column:GetPoint(1)
        assertEquals("TOPLEFT", point)
        assertEquals(2, x)
        assertEquals(-2, y)
        assertTrue(column:GetHeight() <= ActionButton1:GetHeight() - 4)
        assertTrue(column:GetHeight() >= ActionButton1:GetHeight() / 2)
    end)
end)

test("an emptied slot hides its pips", function()
    withOptions(function()
        setPower(1000)
        placeSpell(3, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        assertEquals("6/6+", pipText(ActionButton3))
        A_Admin.ClearActionSlot(3)
        A_Admin.FireEvent("ACTIONBAR_SLOT_CHANGED", 3)
        A_Admin.AdvanceTime(SETTLE)
        assertEquals("none", pipText(ActionButton3))
    end)
end)

test("switching display swaps pips and number", function()
    withOptions(function()
        local cost = costOf(FIREBALL)
        setPower(cost * 2)
        placeSpell(1, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        assertEquals("2/6", pipText(ActionButton1))
        option("display"):SetValue("number")
        assertEquals("none", pipText(ActionButton1))
        assertEquals("2", labelText(ActionButton1))
        option("display"):SetValue("pips")
        assertEquals("2/6", pipText(ActionButton1))
        local label = labelOf(ActionButton1)
        assertTrue(not label:IsShown() or (label:GetText() or "") == "")
    end)
end)

test("color option colors the lit pips and the +", function()
    withOptions(function()
        setPower(1000)
        placeSpell(1, FIREBALL)
        A_Admin.AdvanceTime(SETTLE)
        option("color"):SetValue("ffff8000")
        local column, plus = pipColumn(ActionButton1)
        local fill = select(3, column:GetChildren():GetRegions())
        local r, g, b = fill:GetVertexColor()
        assertEquals("1.00 0.50 0.00", string.format("%.2f %.2f %.2f", r, g, b))
        local pr, pg, pb = plus:GetTextColor()
        assertEquals("1.00 0.50 0.00", string.format("%.2f %.2f %.2f", pr, pg, pb))
    end)
end)
