-- Expensive reads (action slots, spell costs) happen only when the bars change, debounced.
-- A power change only divides the cached costs of that power type and touches text that changed.

local floor, pairs, pcall, type, tostring, wipe = math.floor, pairs, pcall, type, tostring, wipe
local UnitPower, UnitPowerMax, UnitPowerPercent, GetActionInfo = UnitPower, UnitPowerMax, UnitPowerPercent, GetActionInfo
local HasAction = (C_ActionBar and C_ActionBar.HasAction) or HasAction
local GetCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
local GetMacroSpell = GetMacroSpell
local issecret = issecretvalue or function() return false end

local REBUILD_DELAY = 0.2
local TYPE_OF_TOKEN = { MANA = 0, RAGE = 1, FOCUS = 2, ENERGY = 3, RUNIC_POWER = 6 }
local BARS = {
    "Action", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
    "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
}

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

local costOf = {}  -- button -> { powerType, amount }; nil when the button costs nothing
local byType = {}  -- powerType -> { [button] = amount }
local labels = {}  -- button -> FontString
local shown = {}   -- button -> count on its label now

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

local function labelOf(button)
    local label = labels[button]
    if not label then
        local holder = CreateFrame("Frame", nil, button)
        holder:SetAllPoints(button)
        holder:SetFrameLevel(button:GetFrameLevel() + 10)
        label = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        label:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
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
-- compute power/cost itself; the hidden result goes straight to the label, and %d truncates it to whole casts.
local curves = {} -- "cost:max" -> curve
local HIDDEN = {}

local function curveFor(amount, max)
    local key = amount .. ":" .. max
    local curve = curves[key]
    if not curve then
        curve = C_CurveUtil.CreateCurve()
        if curve.SetType and Enum.LuaCurveType then curve:SetType(Enum.LuaCurveType.Linear) end
        -- The offset keeps an exact count (power = 4 * cost) from rounding to 3.9999 and truncating to 3.
        curve:AddPoint(0, 1e-6)
        curve:AddPoint(1, max / amount + 1e-6)
        curves[key] = curve
    end
    return curve
end

local function showHidden(button, value)
    shown[button] = HIDDEN
    local label = labelOf(button)
    if not pcall(label.SetFormattedText, label, "%d", value) then pcall(label.SetText, label, value) end
end

local function refresh(powerType)
    local byCost = byType[powerType]
    if not byCost then return end
    local power = readNumber(UnitPower("player", powerType))
    if power then
        for amount, buttons in pairs(byCost) do
            local count = floor(power / amount)
            for button in pairs(buttons) do show(button, count) end
        end
        return
    end
    local max = readNumber(UnitPowerMax("player", powerType))
    if not max or max <= 0 or not UnitPowerPercent or not C_CurveUtil then return end
    for amount, buttons in pairs(byCost) do
        local ok, casts = pcall(UnitPowerPercent, "player", powerType, false, curveFor(amount, max))
        if ok and casts ~= nil then
            for button in pairs(buttons) do showHidden(button, casts) end
        end
    end
end

local function rebuild()
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

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, _, token)
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
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
