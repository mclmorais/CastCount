-- Expensive reads (action slots, spell costs) happen only when the bars change, debounced.
-- A power change only divides the cached costs of that power type and touches text that changed.

local floor, format = math.floor, string.format
local pairs, pcall, type, tonumber, tostring, wipe = pairs, pcall, type, tonumber, tostring, wipe
local UnitPower, UnitPowerMax, UnitPowerPercent, GetActionInfo = UnitPower, UnitPowerMax, UnitPowerPercent, GetActionInfo
local HasAction = C_ActionBar.HasAction
local GetCost = C_Spell.GetSpellPowerCost
local GetMacroSpell = GetMacroSpell
local issecret = issecretvalue or function() return false end

local REBUILD_DELAY = 0.2
local TYPE_OF_TOKEN = { MANA = 0, RAGE = 1, FOCUS = 2, ENERGY = 3, RUNIC_POWER = 6 }
local BARS = {
    "Action", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
    "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
}

local DEFAULT_FONT = "Fonts\\ARIALN.TTF"
local BUILTIN_FONTS = {
    { name = "Arial Narrow", path = DEFAULT_FONT },
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

local OPTIONS = {
    { key = "enabled", varType = Settings.VarType.Boolean, name = "Show cast counts", default = true,
      tooltip = "Show how many casts each action button can afford." },
    { key = "decimals", varType = Settings.VarType.Number, name = "Decimal places", default = 0, control = "dropdown",
      tooltip = "How many decimal places each count shows. Counts are always rounded down, so 0.9 casts shows as 0. \"Only below 1\" shows whole numbers, and a fraction only when you cannot afford one full cast." },
    { key = "font", varType = Settings.VarType.String, name = "Font", default = DEFAULT_FONT, control = "dropdown",
      tooltip = "Font of the number. Lists fonts registered with LibSharedMedia when another addon loads it." },
    { key = "color", varType = Settings.VarType.String, name = "Color", default = "ffffffff", control = "color",
      tooltip = "Color of the number." },
    { key = "size", varType = Settings.VarType.Number, name = "Font size", default = 12, control = "slider", min = 6, max = 24,
      tooltip = "Height of the number in pixels." },
    { key = "x", varType = Settings.VarType.Number, name = "Horizontal offset", default = 2, control = "slider", min = 0, max = 40,
      tooltip = "Distance from the left edge of the button." },
    { key = "y", varType = Settings.VarType.Number, name = "Vertical offset", default = 2, control = "slider", min = 0, max = 40,
      tooltip = "Distance from the top edge of the button." },
}

local db = {}

local function readable(v)
    return v ~= nil and not issecret(v)
end

local function readNumber(v)
    if readable(v) and type(v) == "number" then return v end
end

local buttonNames = {}
for _, bar in pairs(BARS) do
    for i = 1, 12 do buttonNames[#buttonNames + 1] = bar .. "Button" .. i end
end
for i = 1, 180 do buttonNames[#buttonNames + 1] = "BT4Button" .. i end
for i = 1, 180 do buttonNames[#buttonNames + 1] = "DominosActionButton" .. i end
for bar = 1, 15 do
    for i = 1, 12 do buttonNames[#buttonNames + 1] = "ElvUI_Bar" .. bar .. "Button" .. i end
end

-- Counts are always rounded down: 0.9 casts left is a cast you cannot make, so it shows 0, not 1.
local DISPLAYS = {
    [0] = { decimals = 0, label = "None (3)" },
    [1] = { decimals = 1, label = "One (3.7)" },
    [2] = { decimals = 2, label = "Two (3.75)" },
    [3] = { decimals = 1, belowOne = true, label = "Only below 1 (3, .7)" },
}

local display, scale, textFormat

local function setDecimals(v)
    display = DISPLAYS[v] or DISPLAYS[0]
    scale = 10 ^ display.decimals
    textFormat = display.belowOne and "%g" or "%." .. display.decimals .. "f"
end

local function countText(power, amount)
    if not display.belowOne then return format(textFormat, floor(power * scale / amount) / scale) end
    local tenths = floor(power * 10 / amount)
    if tenths >= 10 then return tostring(floor(tenths / 10)) end
    if tenths == 0 then return "0" end
    return "." .. tenths
end

local costOf = {}  -- button -> { powerType, amount }; nil when the button costs nothing
local byType = {}  -- powerType -> { [button] = amount }
local labels = {}  -- button -> FontString
local shown = {}   -- button -> count on its label now
local fontFlags

local function validSlot(v)
    v = readNumber(tonumber(v))
    if v and v ~= 0 then return v end
end

local function callSlot(button, method)
    local f = button[method]
    if not f then return end
    local ok, v = pcall(f, button)
    if ok then return validSlot(v) end
end

local function slotOf(button)
    return callSlot(button, "GetPagedID") or callSlot(button, "CalculateAction") or validSlot(button.action)
        or (button.GetAttribute and validSlot(button:GetAttribute("action")))
end

local function hasAction(slot)
    local ok, has = pcall(HasAction, slot)
    return ok and (issecret(has) or has == true or has == 1)
end

local function spellOf(slot)
    local kind, id, subType = GetActionInfo(slot)
    if not readable(kind) then return end
    if kind == "spell" then return readNumber(id) end
    if kind == "macro" then
        if readable(subType) and subType == "spell" and readNumber(id) then return id end
        if GetMacroSpell and readable(id) then return readNumber(GetMacroSpell(id)) end
    end
end

-- Returns false when the client hides the cost (combat secrets), so the cached cost is kept.
local function readCost(spellId)
    local ok, costs = pcall(GetCost, spellId)
    if not ok or costs == nil then return nil end
    if not readable(costs) then return false end
    for i = 1, 8 do
        local row = costs[i]
        if row == nil then break end
        local cost, minCost = row.cost, row.minCost
        if (cost ~= nil and not readable(cost)) or (minCost ~= nil and not readable(minCost)) then return false end
        local amount = readNumber(cost) or 0
        if amount <= 0 then amount = readNumber(minCost) or 0 end
        local powerType = readNumber(row.type)
        if powerType == nil and readable(row.name) then powerType = TYPE_OF_TOKEN[row.name] end
        if amount > 0 and powerType then return { powerType = powerType, amount = amount } end
    end
end

local function style(label)
    local r, g, b = CreateColorFromHexString(db.color):GetRGB()
    if not label:SetFont(db.font, db.size, fontFlags) then label:SetFont(DEFAULT_FONT, db.size, fontFlags) end
    label:SetTextColor(r, g, b)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", db.x, -db.y)
end

local function labelOf(button)
    local label = labels[button]
    if not label then
        local holder = CreateFrame("Frame", nil, button)
        holder:SetAllPoints(button)
        holder:SetFrameLevel(button:GetFrameLevel() + 10)
        label = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        if not fontFlags then fontFlags = select(3, label:GetFont()) end
        style(label)
        labels[button] = label
    end
    return label
end

local function show(button, count)
    if shown[button] == count then return end
    shown[button] = count
    labelOf(button):SetText(count or "")
end

-- Forever hides UnitPower from addons. A curve over the power fraction (0..1 -> 0..max/cost) lets the client
-- compute power/cost itself, and the hidden result goes straight to the label through textFormat.
-- The format rounds, so the curve runs half a display step low to make it round down instead. It stays 1e-6 above
-- that so an exact count (power = 4 * cost) does not land a hair under 4, and it flattens at 0 so it never prints -0.
-- Only-below-1 cannot branch on the hidden number, so its curve is a step function that already outputs the
-- displayed value. A number cannot print without its leading zero, so this path shows 0.9 where the readable path shows .9.
local curves = {} -- "cost:max" -> curve for the current decimals
local HIDDEN = {}

local function buildStepCurve(curve, full)
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, 0)
    for tenth = 1, 9 do
        if tenth / 10 <= full then curve:AddPoint((tenth / 10 - 1e-6) / full, tenth / 10) end
    end
    for whole = 1, floor(full) do curve:AddPoint((whole - 1e-6) / full, whole) end
end

local function buildLinearCurve(curve, full)
    if curve.SetType and Enum.LuaCurveType then curve:SetType(Enum.LuaCurveType.Linear) end
    local shift = 0.5 / scale - 1e-6
    curve:AddPoint(0, 0)
    if full > shift then
        curve:AddPoint(shift / full, 0)
        curve:AddPoint(1, full - shift)
    else
        curve:AddPoint(1, 0)
    end
end

local function curveFor(amount, powerMax)
    local key = amount .. ":" .. powerMax
    local curve = curves[key]
    if not curve then
        curve = C_CurveUtil.CreateCurve()
        local build = display.belowOne and buildStepCurve or buildLinearCurve
        build(curve, powerMax / amount)
        curves[key] = curve
    end
    return curve
end

local function showHidden(button, value)
    shown[button] = HIDDEN
    local label = labelOf(button)
    if not pcall(label.SetFormattedText, label, textFormat, value) then pcall(label.SetText, label, value) end
end

local function refresh(powerType)
    if not db.enabled then return end
    local byCost = byType[powerType]
    if not byCost then return end
    local power = readNumber(UnitPower("player", powerType))
    if power then
        for amount, buttons in pairs(byCost) do
            local text = countText(power, amount)
            for button in pairs(buttons) do show(button, text) end
        end
        return
    end
    local powerMax = readNumber(UnitPowerMax("player", powerType))
    if not powerMax or powerMax <= 0 or not UnitPowerPercent or not C_CurveUtil then return end
    for amount, buttons in pairs(byCost) do
        local ok, casts = pcall(UnitPowerPercent, "player", powerType, false, curveFor(amount, powerMax))
        if ok and casts ~= nil then
            for button in pairs(buttons) do showHidden(button, casts) end
        end
    end
end

local function rebuild()
    if not db.enabled then return end
    wipe(byType)
    for _, name in pairs(buttonNames) do
        local button = _G[name]
        if button then
            local slot = slotOf(button)
            local cost
            if slot and hasAction(slot) then
                local spellId = spellOf(slot)
                if spellId then cost = readCost(spellId) end
            end
            if cost == false then cost = costOf[button] end
            costOf[button] = cost or nil
            if cost then
                local byCost = byType[cost.powerType] or {}
                byType[cost.powerType] = byCost
                byCost[cost.amount] = byCost[cost.amount] or {}
                byCost[cost.amount][button] = true
            elseif shown[button] then
                show(button, nil)
            end
        end
    end
    for powerType in pairs(byType) do refresh(powerType) end
end

local pending = false
local function scheduleRebuild()
    if pending then return end
    pending = true
    C_Timer.After(REBUILD_DELAY, function()
        pending = false
        rebuild()
    end)
end

local function restyleAll()
    for _, label in pairs(labels) do style(label) end
end

local function setEnabled(on)
    for _, label in pairs(labels) do label:GetParent():SetShown(on) end
    if on then rebuild() end
end

local function applyDecimals(v)
    setDecimals(v)
    wipe(curves)
    for powerType in pairs(byType) do refresh(powerType) end
end

local function decimalChoices()
    local choices = Settings.CreateControlTextContainer()
    for value = 0, #DISPLAYS do choices:Add(value, DISPLAYS[value].label) end
    return choices:GetData()
end

local function fontChoices()
    local choices = Settings.CreateControlTextContainer()
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    if media then
        for _, name in ipairs(media:List("font")) do choices:Add(media:Fetch("font", name), name) end
    else
        for _, font in ipairs(BUILTIN_FONTS) do choices:Add(font.path, font.name) end
    end
    return choices:GetData()
end

local onChange = {
    enabled = function(_, on) setEnabled(on) end,
    decimals = function(_, v) applyDecimals(v) end,
}
local choicesOf = { font = fontChoices, decimals = decimalChoices }

local function registerOptions()
    CastCountDB = CastCountDB or {}
    db = CastCountDB
    setDecimals(db.decimals)
    local category = Settings.RegisterVerticalLayoutCategory("Cast Count")
    for _, option in ipairs(OPTIONS) do
        if db[option.key] == nil then db[option.key] = option.default end
        local setting = Settings.RegisterAddOnSetting(category, "CastCount_" .. option.key, option.key, db,
            option.varType, option.name, option.default)
        setting:SetValueChangedCallback(onChange[option.key] or restyleAll)
        if option.control == "slider" then
            local range = Settings.CreateSliderOptions(option.min, option.max, 1)
            range:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            Settings.CreateSlider(category, setting, range, option.tooltip)
        elseif option.control == "dropdown" then
            Settings.CreateDropdown(category, setting, choicesOf[option.key], option.tooltip)
        elseif option.control == "color" then
            Settings.CreateColorSwatch(category, setting, option.tooltip)
        else
            Settings.CreateCheckbox(category, setting, option.tooltip)
        end
    end
    Settings.RegisterAddOnCategory(category)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, arg1, token)
    if event == "ADDON_LOADED" then
        if arg1 == "CastCount" then
            frame:UnregisterEvent("ADDON_LOADED")
            registerOptions()
        end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        local powerType = TYPE_OF_TOKEN[token]
        if powerType then refresh(powerType) end
    else
        scheduleRebuild()
    end
end)
frame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
frame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
for _, event in pairs({
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED", "UPDATE_MACROS", "PLAYER_TALENT_UPDATE",
    "PLAYER_REGEN_ENABLED",
}) do
    pcall(frame.RegisterEvent, frame, event)
end

local function describe(v)
    if v == nil then return "nil" end
    if issecret(v) then return "<secret>" end
    return tostring(v)
end

SLASH_CASTCOUNT1 = "/castcount"
SlashCmdList.CASTCOUNT = function()
    local found, withCost = 0, 0
    for _, name in pairs(buttonNames) do
        local button = _G[name]
        if button then
            found = found + 1
            if costOf[button] then withCost = withCost + 1 end
        end
    end
    print("CastCount: buttons found", found, "with a cost", withCost)
    print("  mana", describe(UnitPower("player", 0)), "max", describe(UnitPowerMax("player", 0)),
        "percent fn", UnitPowerPercent and "yes" or "no", "curves", C_CurveUtil and "yes" or "no")
    local printed = 0
    for _, name in pairs(buttonNames) do
        local button = _G[name]
        local slot = button and slotOf(button)
        if slot and hasAction(slot) and printed < 3 then
            printed = printed + 1
            local kind, id, subType = GetActionInfo(slot)
            print(name, "slot", slot, "action", describe(kind), describe(id), describe(subType))
            local spellId = spellOf(slot)
            local ok, costs = pcall(GetCost, spellId)
            print("  spell", describe(spellId), "cost call ok", ok, "result", describe(costs))
            if ok and readable(costs) and costs[1] then
                for key, value in pairs(costs[1]) do print("   ", key, "=", describe(value)) end
            end
            print("  shown", shown[button] == HIDDEN and "<hidden>" or describe(shown[button]),
                "label", labels[button] and "yes" or "no")
        end
    end
    rebuild()
end
