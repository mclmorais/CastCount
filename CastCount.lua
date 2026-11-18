-- Expensive reads (action slots, spell costs) happen only when the bars change, debounced.
-- A power change only divides the cached costs of that power type and touches labels or pips that changed.

local floor, max, min, format = math.floor, math.max, math.min, string.format
local pairs, pcall, type, tonumber, tostring, wipe = pairs, pcall, type, tonumber, tostring, wipe
local UnitPower, UnitPowerMax, UnitPowerPercent, GetActionInfo = UnitPower, UnitPowerMax, UnitPowerPercent, GetActionInfo
local HasAction = C_ActionBar.HasAction
local GetCost = C_Spell.GetSpellPowerCost
local GetMacroSpell = GetMacroSpell
local issecret = issecretvalue or function() return false end

local REBUILD_DELAY = 0.2
local MAX_DECIMALS = 2
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
    { key = "display", varType = Settings.VarType.String, name = "Display", default = "pips", control = "dropdown",
      tooltip = "Pip bar: a column of pips, one per cast. Number: the count as text." },
    { key = "pips", varType = Settings.VarType.Number, name = "Maximum pips", default = 6, control = "slider", min = 1, max = 10,
      tooltip = "Pips in the pip bar. With more casts than pips, all are lit and a + shows below them." },
    { key = "decimals", varType = Settings.VarType.Number, name = "Decimal places", default = 0, control = "dropdown",
      tooltip = "How many decimal places the number shows. Counts are always rounded down, so 0.9 casts shows as 0." },
    { key = "font", varType = Settings.VarType.String, name = "Font", default = DEFAULT_FONT, control = "dropdown",
      tooltip = "Font of the number and of the pip bar's +. Lists fonts registered with LibSharedMedia when another addon loads it." },
    { key = "color", varType = Settings.VarType.String, name = "Color", default = "ffffffff", control = "color",
      tooltip = "Color of the number, or of the lit pips and the + of the pip bar." },
    { key = "size", varType = Settings.VarType.Number, name = "Font size", default = 12, control = "slider", min = 6, max = 24,
      tooltip = "Height of the number in pixels." },
    { key = "x", varType = Settings.VarType.Number, name = "Horizontal offset", default = 2, control = "slider", min = 0, max = 40,
      tooltip = "Distance of the number or pip bar from the left edge of the button." },
    { key = "y", varType = Settings.VarType.Number, name = "Vertical offset", default = 2, control = "slider", min = 0, max = 40,
      tooltip = "Distance of the number or pip bar from the top edge of the button. The pip bar keeps the same gap at the bottom." },
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
local scale, textFormat = 1, "%.0f"

local function setDecimals(v)
    local decimals = max(0, min(MAX_DECIMALS, floor(tonumber(v) or 0)))
    scale, textFormat = 10 ^ decimals, "%." .. decimals .. "f"
end

local costOf = {}  -- button -> { powerType, amount }; nil when the button costs nothing
local byType = {}  -- powerType -> { [button] = amount }
local holders = {} -- button -> Frame over the button that holds its label and pip column
local labels = {}  -- button -> FontString
local columns = {} -- button -> pip column Frame, with .pips (Frames, each with .fill) and .plus (FontString)
local shown = {}   -- button -> what it shows now: label text, or lit pip count (pips + 1 means the + too)
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

local function holderOf(button)
    local holder = holders[button]
    if not holder then
        holder = CreateFrame("Frame", nil, button)
        holder:SetAllPoints(button)
        holder:SetFrameLevel(button:GetFrameLevel() + 10)
        holders[button] = holder
    end
    return holder
end

local function labelOf(button)
    local label = labels[button]
    if not label then
        label = holderOf(button):CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
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

-- Sizes are for a 45px button and scale with it.
local BASE_SIZE, PIP_WIDTH, PIP_GAP, PLUS_SIZE = 45, 7, 2, 10
local SLOT_SHADE = 0.12
local STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar" -- the health and mana bars' gradient, tinted by Color

local function newPip(column)
    local pip = CreateFrame("Frame", nil, column)
    local outline = pip:CreateTexture(nil, "BACKGROUND")
    outline:SetPoint("TOPLEFT", -1, 1)
    outline:SetPoint("BOTTOMRIGHT", 1, -1)
    outline:SetColorTexture(0, 0, 0, 1)
    local slot = pip:CreateTexture(nil, "BORDER")
    slot:SetAllPoints()
    slot:SetColorTexture(SLOT_SHADE, SLOT_SHADE, SLOT_SHADE, 1)
    pip.fill = pip:CreateTexture(nil, "ARTWORK")
    pip.fill:SetAllPoints()
    pip.fill:SetTexture(STATUSBAR)
    pip.fill:SetAlpha(0)
    return pip
end

-- Whole pixels, so every pip and gap draws the same height. Pip 1 is at the top.
local function layoutColumn(column)
    local size = column:GetParent():GetHeight()
    if not size or size <= 0 then size = BASE_SIZE end
    local count = db.pips
    local width = max(3, floor(size * PIP_WIDTH / BASE_SIZE + 0.5))
    local gap = max(1, floor(size * PIP_GAP / BASE_SIZE + 0.5))
    local height = max(1, floor((size - 2 * db.y - gap * (count - 1)) / count))
    column:ClearAllPoints()
    column:SetPoint("TOPLEFT", db.x, -db.y)
    column:SetSize(width, count * height + (count - 1) * gap)
    for k = 1, max(count, #column.pips) do
        local pip = column.pips[k]
        if k <= count then
            pip = pip or newPip(column)
            column.pips[k] = pip
            pip:ClearAllPoints()
            pip:SetPoint("TOPLEFT", 0, -(k - 1) * (height + gap))
            pip:SetSize(width, height)
            pip:Show()
        else
            pip:Hide()
        end
    end
    local plus = column.plus
    if not plus:SetFont(db.font, PLUS_SIZE, fontFlags) then plus:SetFont(DEFAULT_FONT, PLUS_SIZE, fontFlags) end
    local r, g, b = CreateColorFromHexString(db.color):GetRGB()
    plus:SetTextColor(r, g, b)
    for _, pip in ipairs(column.pips) do pip.fill:SetVertexColor(r, g, b) end
end

local function columnOf(button)
    local column = columns[button]
    if not column then
        column = CreateFrame("Frame", nil, holderOf(button))
        column.pips = {}
        column.plus = column:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        column.plus:SetPoint("BOTTOMLEFT", column, "BOTTOMRIGHT", 1, -1)
        column.plus:SetText("+")
        column.plus:SetAlpha(0)
        if not fontFlags then fontFlags = select(3, column.plus:GetFont()) end
        layoutColumn(column)
        columns[button] = column
    end
    return column
end

-- lit counts the + as one more pip, so it runs 0 .. db.pips + 1.
local function showPips(button, lit)
    if shown[button] == lit then return end
    shown[button] = lit
    local column = columnOf(button)
    for k = 1, db.pips do column.pips[k].fill:SetAlpha(k <= lit and 1 or 0) end
    column.plus:SetAlpha(lit > db.pips and 1 or 0)
    column:Show()
end

local function clear(button)
    if shown[button] == nil then return end
    shown[button] = nil
    if labels[button] then labels[button]:SetText("") end
    if columns[button] then columns[button]:Hide() end
end

-- Forever hides UnitPower from addons. A curve over the power fraction (0..1 -> 0..max/cost) lets the client
-- compute power/cost itself, and the hidden result goes straight to the label through textFormat.
-- The format rounds, so the curve runs half a display step low to make it round down instead. It stays 1e-6 above
-- that so an exact count (power = 4 * cost) does not land a hair under 4, and it flattens at 0 so it never prints -0.
local curves = {} -- "cost:max" -> curve for the current decimals
local HIDDEN = {}

local function curveFor(amount, powerMax)
    local key = amount .. ":" .. powerMax
    local curve = curves[key]
    if not curve then
        curve = C_CurveUtil.CreateCurve()
        if curve.SetType and Enum.LuaCurveType then curve:SetType(Enum.LuaCurveType.Linear) end
        local full, shift = powerMax / amount, 0.5 / scale - 1e-6
        curve:AddPoint(0, 0)
        if full > shift then
            curve:AddPoint(shift / full, 0)
            curve:AddPoint(1, full - shift)
        else
            curve:AddPoint(1, 0)
        end
        curves[key] = curve
    end
    return curve
end

local function showHidden(button, value)
    shown[button] = HIDDEN
    local label = labelOf(button)
    if not pcall(label.SetFormattedText, label, textFormat, value) then pcall(label.SetText, label, value) end
end

-- Pip k is lit once power reaches k * cost. Its curve is 0 up to one power point below that and 1 from it on,
-- so whole power values only ever give 0 or 1. The hidden result goes to the fill's alpha, which takes secrets.
local steps = {} -- "need:max" -> curve
local LINEAR = Enum.LuaCurveType and Enum.LuaCurveType.Linear

local function stepFor(need, powerMax)
    local key = need .. ":" .. powerMax
    local curve = steps[key]
    if not curve then
        curve = C_CurveUtil.CreateCurve()
        if curve.SetType and LINEAR then curve:SetType(LINEAR) end
        curve:AddPoint(0, 0)
        if need > powerMax then
            curve:AddPoint(1, 0)
        else
            if need > 1 then curve:AddPoint((need - 1) / powerMax, 0) end
            curve:AddPoint(need / powerMax, 1)
            if need < powerMax then curve:AddPoint(1, 1) end
        end
        steps[key] = curve
    end
    return curve
end

local alphas = {} -- reused: pip k -> hidden alpha, k = db.pips + 1 is the +

local function showPipsHidden(button)
    shown[button] = HIDDEN
    local column = columnOf(button)
    for k = 1, db.pips do pcall(column.pips[k].fill.SetAlpha, column.pips[k].fill, alphas[k]) end
    pcall(column.plus.SetAlpha, column.plus, alphas[db.pips + 1])
    column:Show()
end

local function refresh(powerType)
    if not db.enabled then return end
    local byCost = byType[powerType]
    if not byCost then return end
    local pips = db.display == "pips"
    local power = readNumber(UnitPower("player", powerType))
    if power then
        for amount, buttons in pairs(byCost) do
            if pips then
                local lit = min(floor(power / amount), db.pips + 1)
                for button in pairs(buttons) do showPips(button, lit) end
            else
                local text = format(textFormat, floor(power * scale / amount) / scale)
                for button in pairs(buttons) do show(button, text) end
            end
        end
        return
    end
    local powerMax = readNumber(UnitPowerMax("player", powerType))
    if not powerMax or powerMax <= 0 or not UnitPowerPercent or not C_CurveUtil then return end
    for amount, buttons in pairs(byCost) do
        if pips then
            local ok = true
            for k = 1, db.pips + 1 do
                local value
                ok, value = pcall(UnitPowerPercent, "player", powerType, false, stepFor(k * amount, powerMax))
                if not ok or value == nil then ok = false break end
                alphas[k] = value
            end
            if ok then
                for button in pairs(buttons) do showPipsHidden(button) end
            end
        else
            local ok, casts = pcall(UnitPowerPercent, "player", powerType, false, curveFor(amount, powerMax))
            if ok and casts ~= nil then
                for button in pairs(buttons) do showHidden(button, casts) end
            end
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
            else
                clear(button)
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

local function refreshAll()
    for powerType in pairs(byType) do refresh(powerType) end
end

local function restyleAll()
    for _, label in pairs(labels) do style(label) end
    for _, column in pairs(columns) do layoutColumn(column) end
end

local function setPipCount()
    restyleAll()
    wipe(shown)
    refreshAll()
end

-- Blanks every label and column so the next refresh draws only the chosen display.
local function setDisplay()
    for button in pairs(shown) do clear(button) end
    for _, label in pairs(labels) do label:SetShown(db.display ~= "pips") end
    refreshAll()
end

local function setEnabled(on)
    for _, holder in pairs(holders) do holder:SetShown(on) end
    if on then rebuild() end
end

local function applyDecimals(v)
    setDecimals(v)
    wipe(curves)
    refreshAll()
end

local function displayChoices()
    local choices = Settings.CreateControlTextContainer()
    choices:Add("pips", "Pip bar")
    choices:Add("number", "Number")
    return choices:GetData()
end

local function decimalChoices()
    local choices = Settings.CreateControlTextContainer()
    choices:Add(0, "None (3)")
    choices:Add(1, "One (3.7)")
    choices:Add(2, "Two (3.75)")
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
    display = setDisplay,
    pips = setPipCount,
}
local choicesOf = { font = fontChoices, decimals = decimalChoices, display = displayChoices }

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
