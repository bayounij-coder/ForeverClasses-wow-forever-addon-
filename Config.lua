--[[
    ForeverClasses - Config.lua
    Configuration, SavedVariables management, and Settings GUI
]]--

ForeverClasses = ForeverClasses or {}
local FC = ForeverClasses

local function IsSecret(v)
    if FC and FC.IsSecret then return FC.IsSecret(v) end
    if v == nil then return false end
    if issecretvalue then
        local ok, res = pcall(issecretvalue, v)
        if ok and res then return true end
    end
    if canaccessvalue then
        local ok, res = pcall(canaccessvalue, v)
        if ok and not res then return true end
    end
    if C_Secrets and C_Secrets.IsSecret then
        local ok, res = pcall(C_Secrets.IsSecret, v)
        if ok and res == true then return true end
    end
    local t = type(v)
    if t == "secret" or t == "userdata" then
        return true
    elseif t == "number" then
        local okComp = pcall(function() return v > 0 end)
        if not okComp then return true end
    elseif t == "string" then
        local okStr = pcall(function() return #v >= 0 end)
        if not okStr then return true end
    elseif t == "boolean" then
        local okBool = pcall(function() if v then end end)
        if not okBool then return true end
    end
    return false
end

FC.Defaults = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -140,
    movementMode = "FREE",     -- "FREE", "MODIFIER", "LOCKED"
    modifierKey = "ALT",       -- "ALT", "SHIFT", "CTRL"
    showIncomingHeals = true,  -- Show upcoming heals
    showMinimapIcon = true,    -- Show minimap button
    minimapAngle = 220,        -- Minimap angle around circular rim
    showComboPoints = true,    -- Show Rogue/Feral combo points below panel in combat
    classColorHealth = false,   -- Class-colored health bar
    lowHealthWarning = true,   -- Flash warning pulse when HP <= threshold%
    lowHealthThreshold = 33,   -- Low health trigger percentage (default 33%)
    showDebuffs = true,        -- Show harmful debuff icons docked to right of bar
    showCooldowns = true,      -- Show internal customizable ability bar docked above health bar
    cooldownSlotCount = 7,     -- Number of ability & cooldown slots to display (0-7, 0 = Off)
    cooldownPulse = true,      -- Flash starburst pulse when ability comes off cooldown
    attachCooldownManager = false, -- Auto-anchor Blizzard EssentialCooldownViewer above Health Bar (disabled)
    cdAttachOffset = 4,        -- Gap between Health Bar and Cooldown Manager
    textMode = "BOTH",         -- "BOTH", "NUMERIC", "PERCENT", "SYNC", "NONE"
    barWidth = 240,
    healthHeight = 22,
    powerHeight = 12,
    autoFade = true,           -- Fade HUD when out of combat, at full health/power, no target
    autoFadeAlpha = 0.35,      -- Resting alpha when faded out (default 35%)
    showTotems = true,         -- Show Shaman Totem Bar below panel when totems are active
    showAbsorbs = true,        -- Show damage absorption shields on health bar
}

-- ============================================================================
-- Character Profile Management (Per-Character Cooldown & Ability Bars)
-- ============================================================================

function FC:GetCharKey()
    if FC.playerCharKey then return FC.playerCharKey end

    local name, realm = nil, nil
    if UnitFullName then
        pcall(function() name, realm = UnitFullName("player") end)
    end
    if not name or name == "" or name == "Unknown" or name == "UNKNOWN" then
        if UnitName then
            pcall(function() name = UnitName("player") end)
        end
    end
    if not realm or realm == "" then
        if GetNormalizedRealmName then
            pcall(function() realm = GetNormalizedRealmName() end)
        end
        if not realm or realm == "" then
            if GetRealmName then
                pcall(function() realm = GetRealmName() end)
            end
        end
    end

    if name and name ~= "" and name ~= "Unknown" and name ~= "UNKNOWN" then
        local key = name
        if realm and realm ~= "" then
            key = name .. " - " .. realm
        end
        FC.playerCharKey = key
        return key
    end

    local guid = UnitGUID and UnitGUID("player")
    if guid and guid ~= "" then
        return guid
    end

    return "Unknown"
end

function FC:GetCharData()
    if not ForeverClassesDB then ForeverClassesDB = {} end
    if not ForeverClassesDB.characters then ForeverClassesDB.characters = {} end

    local charKey = FC:GetCharKey()
    local guid = UnitGUID and UnitGUID("player")
    local name = UnitName and UnitName("player")

    -- 1. Look up by active charKey
    local charData = nil
    if charKey ~= "Unknown" then
        charData = ForeverClassesDB.characters[charKey]
    end

    -- 2. Fallback: check GUID or pure Name (handles migration and early load)
    if not charData and guid and guid ~= "" and ForeverClassesDB.characters[guid] then
        charData = ForeverClassesDB.characters[guid]
        if charKey ~= "Unknown" then
            ForeverClassesDB.characters[charKey] = charData
        end
    end
    if not charData and name and name ~= "" and name ~= "Unknown" and ForeverClassesDB.characters[name] then
        charData = ForeverClassesDB.characters[name]
        if charKey ~= "Unknown" then
            ForeverClassesDB.characters[charKey] = charData
        end
    end

    -- 3. If charKey is still Unknown (very early before name/GUID are available)
    if not charData and charKey == "Unknown" then
        if not FC.tempCharData then
            FC.tempCharData = {
                cooldownSlots = {},
                cooldownSwapSlots = {},
                cooldownDefaultsPopulated = false,
            }
        end
        return FC.tempCharData
    end

    -- 4. Create new character record if first time seen
    if not charData then
        charData = {
            cooldownSlots = {},
            cooldownSwapSlots = {},
            cooldownDefaultsPopulated = false,
            class = select(2, UnitClass("player")),
        }
        if charKey ~= "Unknown" then
            ForeverClassesDB.characters[charKey] = charData
        end
    end

    if not charData.cooldownSwapSlots then
        charData.cooldownSwapSlots = {}
    end

    if not charData.class and UnitClass then
        local _, cl = UnitClass("player")
        charData.class = cl
    end

    return charData
end

function FC:GetCooldownSlots()
    local charData = FC:GetCharData()
    if not charData.cooldownSlots then
        charData.cooldownSlots = {}
    end
    -- Keep ForeverClassesDB.cooldownSlots referencing this character's table
    ForeverClassesDB.cooldownSlots = charData.cooldownSlots
    return charData.cooldownSlots
end

function FC:GetCooldownSwapSlots(slotIndex)
    local charData = FC:GetCharData()
    if not charData.cooldownSwapSlots then
        charData.cooldownSwapSlots = {}
    end
    ForeverClassesDB.cooldownSwapSlots = charData.cooldownSwapSlots
    if slotIndex then
        if not charData.cooldownSwapSlots[slotIndex] then
            charData.cooldownSwapSlots[slotIndex] = {}
        end
        return charData.cooldownSwapSlots[slotIndex]
    end
    return charData.cooldownSwapSlots
end

FC.PER_CHAR_SETTINGS = {
    "cooldownSlotCount",
    "showCooldowns",
    "cooldownPulse",
    "classColorHealth",
    "showIncomingHeals",
    "showAbsorbs",
    "showComboPoints",
    "showTotems",
    "lowHealthWarning",
    "lowHealthThreshold",
    "showDebuffs",
    "autoFade",
    "autoFadeAlpha",
    "textMode",
}

function FC:SaveCharSetting(key, val)
    if not key then return end
    local charData = FC.GetCharData and FC:GetCharData()
    if charData and charData ~= FC.tempCharData then
        if not charData.settings then charData.settings = {} end
        charData.settings[key] = val
        if key == "cooldownSlotCount" then
            charData.cooldownSlotCount = val
            charData.showCooldowns = (val > 0)
        elseif key == "showCooldowns" then
            charData.showCooldowns = val
        end
    end
end

function FC:SyncActiveCharSettings()
    local charData = FC.GetCharData and FC:GetCharData()
    if not charData or charData == FC.tempCharData then return end
    if not charData.settings then charData.settings = {} end
    if FC.PER_CHAR_SETTINGS and ForeverClassesDB then
        for _, k in ipairs(FC.PER_CHAR_SETTINGS) do
            if ForeverClassesDB[k] ~= nil then
                charData.settings[k] = ForeverClassesDB[k]
            end
        end
    end
    if ForeverClassesDB and ForeverClassesDB.cooldownSlotCount ~= nil then
        charData.cooldownSlotCount = ForeverClassesDB.cooldownSlotCount
        charData.showCooldowns = (ForeverClassesDB.cooldownSlotCount > 0)
    end
end

function FC:GetCooldownSlotCount()
    local charData = FC.GetCharData and FC:GetCharData()
    if charData and charData ~= FC.tempCharData and charData.cooldownSlotCount ~= nil then
        return charData.cooldownSlotCount
    end
    local count = ForeverClassesDB and ForeverClassesDB.cooldownSlotCount
    if count == nil then
        count = (ForeverClassesDB and ForeverClassesDB.showCooldowns == false) and 0 or 7
    end
    return count
end

function FC:SetCooldownSlotCount(num)
    num = tonumber(num) or 0
    if num < 0 then num = 0 elseif num > (FC.MAX_COOLDOWN_SLOTS or 7) then num = (FC.MAX_COOLDOWN_SLOTS or 7) end
    if ForeverClassesDB then
        ForeverClassesDB.cooldownSlotCount = num
        ForeverClassesDB.showCooldowns = (num > 0)
    end
    FC:SaveCharSetting("cooldownSlotCount", num)
    FC:SaveCharSetting("showCooldowns", (num > 0))

    if FC.UpdateCooldownBarLayout then FC:UpdateCooldownBarLayout() end
    if FC.UpdateCooldowns then FC:UpdateCooldowns() end
    if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
    if FC.ApplyConfig then FC:ApplyConfig() end
end

function FC:LoadCharacterCooldowns()
    local charData = FC:GetCharData()
    if not charData or charData == FC.tempCharData then return end

    if not charData.cooldownSwapSlots then
        charData.cooldownSwapSlots = {}
    end
    ForeverClassesDB.cooldownSlots = charData.cooldownSlots
    ForeverClassesDB.cooldownSwapSlots = charData.cooldownSwapSlots
    FC.currentCharData = charData

    -- 1. Restore per-character cooldown slot count & visibility
    if charData.cooldownSlotCount ~= nil then
        ForeverClassesDB.cooldownSlotCount = charData.cooldownSlotCount
        ForeverClassesDB.showCooldowns = (charData.cooldownSlotCount > 0)
    elseif ForeverClassesDB.cooldownSlotCount ~= nil then
        charData.cooldownSlotCount = ForeverClassesDB.cooldownSlotCount
        charData.showCooldowns = (ForeverClassesDB.cooldownSlotCount > 0)
    else
        charData.cooldownSlotCount = 7
        charData.showCooldowns = true
        ForeverClassesDB.cooldownSlotCount = 7
        ForeverClassesDB.showCooldowns = true
    end

    -- 2. Restore per-character general settings
    if charData.settings then
        for k, v in pairs(charData.settings) do
            ForeverClassesDB[k] = v
        end
    else
        charData.settings = {}
        if FC.PER_CHAR_SETTINGS then
            for _, k in ipairs(FC.PER_CHAR_SETTINGS) do
                if ForeverClassesDB[k] ~= nil then
                    charData.settings[k] = ForeverClassesDB[k]
                end
            end
        end
    end

    local hasAnySlot = false
    if charData.cooldownSlots then
        for i = 1, (FC.MAX_COOLDOWN_SLOTS or 7) do
            if charData.cooldownSlots[i] then
                hasAnySlot = true
                break
            end
        end
    end

    -- Only populate defaults if brand new character with 0 assigned slots
    if not charData.cooldownDefaultsPopulated and not hasAnySlot then
        if FC.PopulateDefaultCooldowns then
            pcall(FC.PopulateDefaultCooldowns, FC)
        end
    elseif hasAnySlot then
        charData.cooldownDefaultsPopulated = true
    end

    if FC.SanitizeCooldownSlots then
        pcall(FC.SanitizeCooldownSlots, FC)
    end

    if FC.UpdateCooldownBarLayout then
        pcall(FC.UpdateCooldownBarLayout, FC)
    end
    if FC.UpdateCooldowns then
        pcall(FC.UpdateCooldowns, FC)
    end
    if FC.ConfigWindow and FC.ConfigWindow.Refresh and FC.ConfigWindow:IsShown() then
        pcall(FC.ConfigWindow.Refresh, FC.ConfigWindow)
    end
end

function FC:InitDB()
    if not ForeverClassesDB then
        ForeverClassesDB = {}
    end
    -- Explicitly switch to internal customizable cooldown bar
    ForeverClassesDB.attachCooldownManager = false
    if ForeverClassesDB.cooldownSlotCount == nil then
        if ForeverClassesDB.showCooldowns == false then
            ForeverClassesDB.cooldownSlotCount = 0
        else
            ForeverClassesDB.cooldownSlotCount = 7
        end
    end
    ForeverClassesDB.showCooldowns = (ForeverClassesDB.cooldownSlotCount > 0)
    if ForeverClassesDB.cdAttachOffset == nil then
        ForeverClassesDB.cdAttachOffset = 4
    end
    if ForeverClassesDB.cooldownPulse == nil then
        ForeverClassesDB.cooldownPulse = true
    end
    if ForeverClassesDB.showTotems == nil then
        ForeverClassesDB.showTotems = true
    end
    if ForeverClassesDB.showAbsorbs == nil then
        ForeverClassesDB.showAbsorbs = true
    end
    if ForeverClassesDB.cachedTotemDurations == nil then
        ForeverClassesDB.cachedTotemDurations = {}
    end
    FC.cachedTotemDurations = ForeverClassesDB.cachedTotemDurations

    if ForeverClassesDB.showDebuffs == nil and ForeverClassesDB.showDebuffHighlight ~= nil then
        ForeverClassesDB.showDebuffs = ForeverClassesDB.showDebuffHighlight
    end

    -- If threshold is not set (or was 25 or 35 from previous defaults), default to 33%
    if ForeverClassesDB.lowHealthThreshold == nil or ForeverClassesDB.lowHealthThreshold == 25 or ForeverClassesDB.lowHealthThreshold == 35 then
        ForeverClassesDB.lowHealthThreshold = 33
    end

    if ForeverClassesDB.ignoredDebuffs == nil then
        ForeverClassesDB.ignoredDebuffs = {}
    end

    if ForeverClassesDB.excludedDebuffSpellIDs == nil then
        ForeverClassesDB.excludedDebuffSpellIDs = {}
    end
    -- Always ensure default excluded spells are present and clean up any array keys
    FC.excludedDebuffSpellIDs = FC.excludedDebuffSpellIDs or {}
    FC.excludedDebuffSpellIDs[1229451] = true -- Boosted Rest (WoW Forever / Turtle custom tent debuff)
    FC.excludedDebuffSpellIDs[1001982] = true
    for k, v in pairs(ForeverClassesDB.excludedDebuffSpellIDs) do
        if type(k) == "number" and k > 10 and (v == true or type(v) == "boolean") then
            FC.excludedDebuffSpellIDs[k] = true
        end
    end
    if wipe then
        wipe(ForeverClassesDB.excludedDebuffSpellIDs)
    else
        ForeverClassesDB.excludedDebuffSpellIDs = {}
    end
    for k, v in pairs(FC.excludedDebuffSpellIDs) do
        if type(k) == "number" and v == true then
            ForeverClassesDB.excludedDebuffSpellIDs[k] = true
        end
    end
    FC.excludedDebuffSpellIDs = ForeverClassesDB.excludedDebuffSpellIDs

    if ForeverClassesDB.characters == nil then
        ForeverClassesDB.characters = {}
    end

    if ForeverClassesDB.cooldownSlots == nil then
        ForeverClassesDB.cooldownSlots = {}
    end

    if ForeverClassesDB.cooldownSwapSlots == nil then
        ForeverClassesDB.cooldownSwapSlots = {}
    end

    for k, v in pairs(FC.Defaults) do
        if ForeverClassesDB[k] == nil then
            ForeverClassesDB[k] = v
        end
    end

    if not ForeverClassesDB.autoFadeMigrated then
        ForeverClassesDB.autoFade = true
        ForeverClassesDB.autoFadeMigrated = true
    end
    if ForeverClassesDB.autoFadeAlpha == nil then
        ForeverClassesDB.autoFadeAlpha = 0.35
    end

    ForeverClassesDB.showMinimapIcon = true

    if FC.LoadCharacterCooldowns then
        pcall(FC.LoadCharacterCooldowns, FC)
    end
end

-- ============================================================================
-- Options GUI Window
-- ============================================================================

local BackdropTemplateString = BackdropTemplateMixin and "BackdropTemplate" or nil

local function CreateCheckbox(parent, labelText, getFunc, setFunc, settingKey)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.text:SetText(labelText)

    cb:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked() and true or false
        local sound = (SOUNDKIT and SOUNDKIT.IG_MAINOPTION_CHECKBOX_ON) or 856
        PlaySound(sound)
        setFunc(isChecked)
        if settingKey and FC.SaveCharSetting then
            FC:SaveCharSetting(settingKey, isChecked)
        end
        if FC.ApplyConfig then FC:ApplyConfig() end
    end)

    cb.UpdateValue = function(self)
        self:SetChecked(getFunc() and true or false)
    end
    cb:UpdateValue()

    return cb
end

function FC:CreateConfigWindow()
    if FC.ConfigWindow then return FC.ConfigWindow end

    local f = CreateFrame("Frame", "ForeverClassesConfigFrame", UIParent, BackdropTemplateString)
    f:SetSize(380, 695)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText("|cff00ccffForeverClasses|r |cffffaa00(Beta-Test)|r Settings")

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)
    table.insert(UISpecialFrames, "ForeverClassesConfigFrame")

    -- Section 1: Movement & Locking
    local moveTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    moveTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -50)
    moveTitle:SetText("Frame Movement:")

    -- Movement Mode Checkboxes (Radio behavior)
    local moveFree, moveMod, moveLock

    moveFree = CreateCheckbox(f, "Free Move (Drag freely without keys)", 
        function() return ForeverClassesDB.movementMode == "FREE" end,
        function()
            ForeverClassesDB.movementMode = "FREE"
            FC.ConfigWindow:Refresh()
        end
    )
    moveFree:SetPoint("TOPLEFT", moveTitle, "BOTTOMLEFT", 0, -6)

    moveMod = CreateCheckbox(f, "Hold Key to Move", 
        function() return ForeverClassesDB.movementMode == "MODIFIER" end,
        function()
            ForeverClassesDB.movementMode = "MODIFIER"
            FC.ConfigWindow:Refresh()
        end
    )
    moveMod:SetPoint("TOPLEFT", moveFree, "BOTTOMLEFT", 0, -4)

    -- Modifier Key Selection buttons (Alt / Shift / Ctrl)
    local keyGroup = CreateFrame("Frame", nil, f)
    keyGroup:SetSize(280, 26)
    keyGroup:SetPoint("TOPLEFT", moveMod, "BOTTOMLEFT", 24, -4)

    local keys = { "ALT", "SHIFT", "CTRL" }
    local keyBtns = {}
    for i, k in ipairs(keys) do
        local btn = CreateFrame("Button", nil, keyGroup, "UIPanelButtonTemplate")
        btn:SetSize(55, 22)
        btn:SetPoint("LEFT", keyGroup, "LEFT", (i - 1) * 60, 0)
        btn:SetText(k)
        btn:SetScript("OnClick", function()
            ForeverClassesDB.modifierKey = k
            FC.ConfigWindow:Refresh()
            if FC.ApplyConfig then FC:ApplyConfig() end
        end)
        keyBtns[k] = btn
    end

    moveLock = CreateCheckbox(f, "Locked (Cannot move frame)", 
        function() return ForeverClassesDB.movementMode == "LOCKED" end,
        function()
            ForeverClassesDB.movementMode = "LOCKED"
            FC.ConfigWindow:Refresh()
        end
    )
    moveLock:SetPoint("TOPLEFT", keyGroup, "BOTTOMLEFT", -24, -8)

    -- Section 2: General & Healing Options
    local generalTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    generalTitle:SetPoint("TOPLEFT", moveLock, "BOTTOMLEFT", 0, -16)
    generalTitle:SetText("General & Healing Options:")

    local classColorCb = CreateCheckbox(f, "Class-Colored Health Bar",
        function() return ForeverClassesDB.classColorHealth end,
        function(val)
            ForeverClassesDB.classColorHealth = val
            if FC.UpdateHealth then FC:UpdateHealth() end
        end,
        "classColorHealth"
    )
    classColorCb:SetPoint("TOPLEFT", generalTitle, "BOTTOMLEFT", 0, -6)

    local healCb = CreateCheckbox(f, "Show Upcoming Heals (Heal Prediction)",
        function() return ForeverClassesDB.showIncomingHeals end,
        function(val)
            ForeverClassesDB.showIncomingHeals = val
            if FC.UpdateHealth then FC:UpdateHealth() end
        end,
        "showIncomingHeals"
    )
    healCb:SetPoint("TOPLEFT", classColorCb, "BOTTOMLEFT", 0, -4)

    local absorbCb = CreateCheckbox(f, "Show Shield / Absorb Bar",
        function() return ForeverClassesDB.showAbsorbs ~= false end,
        function(val)
            ForeverClassesDB.showAbsorbs = val
            if FC.UpdateHealth then FC:UpdateHealth() end
        end,
        "showAbsorbs"
    )
    absorbCb:SetPoint("TOPLEFT", healCb, "BOTTOMLEFT", 0, -4)

    local _, pClass = UnitClass("player")
    local isComboClass = (pClass == "ROGUE" or pClass == "DRUID")
    local isShaman = (pClass == "SHAMAN")

    local cpCb = CreateCheckbox(f, "Show Combo Points",
        function() return ForeverClassesDB.showComboPoints end,
        function(val)
            ForeverClassesDB.showComboPoints = val
            if FC.UpdateComboPoints then FC:UpdateComboPoints() end
        end,
        "showComboPoints"
    )
    if isComboClass then
        cpCb:SetPoint("TOPLEFT", absorbCb, "BOTTOMLEFT", 0, -4)
        cpCb:Show()
    else
        cpCb:Hide()
    end

    local totemCb = CreateCheckbox(f, "Show Totem Bar (Shaman)",
        function() return ForeverClassesDB.showTotems end,
        function(val)
            ForeverClassesDB.showTotems = val
            if FC.UpdateTotems then FC:UpdateTotems() end
        end,
        "showTotems"
    )
    if isShaman then
        totemCb:SetPoint("TOPLEFT", absorbCb, "BOTTOMLEFT", 0, -4)
        totemCb:Show()
    else
        totemCb:Hide()
    end

    local lowHealthCb = CreateCheckbox(f, string.format("Low Health Warning Flash (<= %d%% HP)", ForeverClassesDB.lowHealthThreshold or 33),
        function() return ForeverClassesDB.lowHealthWarning end,
        function(val)
            ForeverClassesDB.lowHealthWarning = val
            if FC.UpdateHealth then FC:UpdateHealth() end
        end,
        "lowHealthWarning"
    )
    if isComboClass then
        lowHealthCb:SetPoint("TOPLEFT", cpCb, "BOTTOMLEFT", 0, -4)
    elseif isShaman then
        lowHealthCb:SetPoint("TOPLEFT", totemCb, "BOTTOMLEFT", 0, -4)
    else
        lowHealthCb:SetPoint("TOPLEFT", absorbCb, "BOTTOMLEFT", 0, -4)
    end
    local origLowHealthUpdate = lowHealthCb.UpdateValue
    lowHealthCb.UpdateValue = function(self)
        if origLowHealthUpdate then origLowHealthUpdate(self) end
        local t = ForeverClassesDB.lowHealthThreshold or 33
        if self.text then
            self.text:SetText(string.format("Low Health Warning Flash (<= %d%% HP)", t))
        end
    end

    local debuffCb = CreateCheckbox(f, "Show Harmful Debuffs (Icons on Right of Bar)",
        function() return ForeverClassesDB.showDebuffs end,
        function(val)
            ForeverClassesDB.showDebuffs = val
            if FC.UpdateDebuffs then FC:UpdateDebuffs() end
        end,
        "showDebuffs"
    )
    debuffCb:SetPoint("TOPLEFT", lowHealthCb, "BOTTOMLEFT", 0, -4)

    local autoFadeCb = CreateCheckbox(f, "Out-of-Combat Auto Fade (Resting: 35%)",
        function() return ForeverClassesDB.autoFade end,
        function(val)
            ForeverClassesDB.autoFade = val
            if FC.RequestFadeCheck then FC:RequestFadeCheck() end
            if not val and FC.Frame then FC.Frame:SetAlpha(1.0) end
            if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        end,
        "autoFade"
    )
    autoFadeCb:SetPoint("TOPLEFT", debuffCb, "BOTTOMLEFT", 0, -4)
    local origAutoFadeUpdate = autoFadeCb.UpdateValue
    autoFadeCb.UpdateValue = function(self)
        if origAutoFadeUpdate then origAutoFadeUpdate(self) end
        local pct = math.floor(((ForeverClassesDB and ForeverClassesDB.autoFadeAlpha) or 0.35) * 100)
        if self.text then
            self.text:SetText(string.format("Out-of-Combat Auto Fade (Resting: %d%%)", pct))
        end
    end

    -- Ability & Cooldown Slots Selector (0 to 7)
    local cdTitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cdTitle:SetPoint("TOPLEFT", autoFadeCb, "BOTTOMLEFT", 0, -8)
    cdTitle:SetText("Ability & Cooldown Slots (0 - 7):")

    local cdStatusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cdStatusText:SetPoint("LEFT", cdTitle, "RIGHT", 6, 0)

    local cdGroup = CreateFrame("Frame", nil, f)
    cdGroup:SetSize(280, 24)
    cdGroup:SetPoint("TOPLEFT", cdTitle, "BOTTOMLEFT", 0, -4)

    local cdSlotBtns = {}
    local btnOffsets = {
        [0] = { x = 0,   w = 44, label = "0 (Off)" },
        [1] = { x = 48,  w = 25, label = "1" },
        [2] = { x = 76,  w = 25, label = "2" },
        [3] = { x = 104, w = 25, label = "3" },
        [4] = { x = 132, w = 25, label = "4" },
        [5] = { x = 160, w = 25, label = "5" },
        [6] = { x = 188, w = 25, label = "6" },
        [7] = { x = 216, w = 25, label = "7" },
    }

    for num = 0, 7 do
        local info = btnOffsets[num]
        local btn = CreateFrame("Button", nil, cdGroup, "UIPanelButtonTemplate")
        btn:SetSize(info.w, 22)
        btn:SetPoint("LEFT", cdGroup, "LEFT", info.x, 0)
        btn:SetText(info.label)
        btn:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINOPTION_CHECKBOX_ON or 856)
            FC:SetCooldownSlotCount(num)
        end)
        cdSlotBtns[num] = btn
    end

    local cdPulseCb = CreateCheckbox(f, "Cooldown Ready Pulse (Flash icon when ready)",
        function() return ForeverClassesDB.cooldownPulse ~= false end,
        function(val)
            ForeverClassesDB.cooldownPulse = val
            if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        end,
        "cooldownPulse"
    )
    cdPulseCb:SetPoint("TOPLEFT", cdGroup, "BOTTOMLEFT", 0, -6)

    -- Section 3: Text Display Mode
    local textTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textTitle:SetPoint("TOPLEFT", cdPulseCb, "BOTTOMLEFT", 0, -12)
    textTitle:SetText("Bar Text Display Mode:")

    local textModes = {
        { id = "SYNC", label = "Sync with Game Interface Settings" },
        { id = "BOTH", label = "Both (Values & Percentage: 1,500 | 100%)" },
        { id = "NUMERIC", label = "Numeric Only (Current / Max)" },
        { id = "PERCENT", label = "Percentage Only (100%)" },
        { id = "NONE", label = "Hide Text" },
    }

    local textCheckboxes = {}
    local lastAnchor = textTitle
    for _, tm in ipairs(textModes) do
        local cb = CreateCheckbox(f, tm.label,
            function() return ForeverClassesDB.textMode == tm.id end,
            function()
                ForeverClassesDB.textMode = tm.id
                if FC.SaveCharSetting then FC:SaveCharSetting("textMode", tm.id) end
                FC.ConfigWindow:Refresh()
            end
        )
        cb:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -4)
        lastAnchor = cb
        table.insert(textCheckboxes, cb)
    end

    -- Bottom Buttons: Reset Position & Close
    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(120, 24)
    resetBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 16)
    resetBtn:SetText("Reset Position")
    resetBtn:SetScript("OnClick", function()
        ForeverClassesDB.point = FC.Defaults.point
        ForeverClassesDB.relativePoint = FC.Defaults.relativePoint
        ForeverClassesDB.x = FC.Defaults.x
        ForeverClassesDB.y = FC.Defaults.y
        if FC.ApplyConfig then FC:ApplyConfig() end
        print("|cff00ccff[ForeverClasses]|r Position reset to center.")
    end)

    local doneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    doneBtn:SetSize(90, 24)
    doneBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
    doneBtn:SetText("Done")
    doneBtn:SetScript("OnClick", function() f:Hide() end)

    f.Refresh = function()
        moveFree:UpdateValue()
        moveMod:UpdateValue()
        moveLock:UpdateValue()
        classColorCb:UpdateValue()
        healCb:UpdateValue()
        absorbCb:UpdateValue()

        local _, playerClass = UnitClass("player")
        local isClassCombo = (playerClass == "ROGUE" or playerClass == "DRUID")
        local isClassShaman = (playerClass == "SHAMAN")

        if isClassCombo then
            totemCb:Hide()
            cpCb:ClearAllPoints()
            cpCb:SetPoint("TOPLEFT", absorbCb, "BOTTOMLEFT", 0, -4)
            cpCb:Show()
            cpCb:UpdateValue()

            lowHealthCb:ClearAllPoints()
            lowHealthCb:SetPoint("TOPLEFT", cpCb, "BOTTOMLEFT", 0, -4)
        elseif isClassShaman then
            cpCb:Hide()
            totemCb:ClearAllPoints()
            totemCb:SetPoint("TOPLEFT", absorbCb, "BOTTOMLEFT", 0, -4)
            totemCb:Show()
            totemCb:UpdateValue()

            lowHealthCb:ClearAllPoints()
            lowHealthCb:SetPoint("TOPLEFT", totemCb, "BOTTOMLEFT", 0, -4)
        else
            cpCb:Hide()
            totemCb:Hide()
            lowHealthCb:ClearAllPoints()
            lowHealthCb:SetPoint("TOPLEFT", absorbCb, "BOTTOMLEFT", 0, -4)
        end

        lowHealthCb:UpdateValue()
        debuffCb:UpdateValue()
        autoFadeCb:UpdateValue()
        cdPulseCb:UpdateValue()

        local curSlots = ForeverClassesDB.cooldownSlotCount
        if curSlots == nil then
            curSlots = (ForeverClassesDB.showCooldowns == false) and 0 or 7
        end
        for num, btn in pairs(cdSlotBtns) do
            if num == curSlots then
                btn:LockHighlight()
            else
                btn:UnlockHighlight()
            end
        end
        if curSlots == 0 then
            cdStatusText:SetText("|cffff4444(Disabled)|r")
        else
            cdStatusText:SetText(string.format("|cff00ff00(%d Active)|r", curSlots))
        end

        for _, cb in ipairs(textCheckboxes) do
            cb:UpdateValue()
        end

        for k, btn in pairs(keyBtns) do
            if ForeverClassesDB.movementMode == "MODIFIER" and ForeverClassesDB.modifierKey == k then
                btn:LockHighlight()
            else
                btn:UnlockHighlight()
            end
            if ForeverClassesDB.movementMode == "MODIFIER" then
                btn:Enable()
            else
                btn:Disable()
            end
        end
    end

    f:SetScript("OnShow", f.Refresh)
    f:SetScript("OnHide", function()
        if FC.SyncActiveCharSettings then pcall(FC.SyncActiveCharSettings, FC) end
        if FC.RequestFadeCheck then FC:RequestFadeCheck() end
    end)
    f:Hide()

    FC.ConfigWindow = f
    return f
end

-- ============================================================================
-- Minimap Button (Dynamic Class Crest)
-- ============================================================================

local function GetMinimapRadius()
    if not Minimap then return 70 end
    local w = Minimap:GetWidth() or 140
    local h = Minimap:GetHeight() or w
    return (math.min(w, h) / 2) - 2
end

function FC:UpdateMinimapPosition()
    if not FC.MinimapButton or not Minimap then return end
    local radius = GetMinimapRadius()
    local angle = math.rad(ForeverClassesDB.minimapAngle or 220)
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    FC.MinimapButton:ClearAllPoints()
    FC.MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function FC:UpdateMinimapVisibility()
    if not FC.MinimapButton then return end
    ForeverClassesDB.showMinimapIcon = true
    FC.MinimapButton:Show()
    FC:UpdateMinimapPosition()
end

function FC:ToggleConfig()
    local win = FC:CreateConfigWindow()
    if win:IsShown() then
        win:Hide()
    else
        win:Show()
    end
end

function FC:CreateMinimapButton()
    if FC.MinimapButton or not Minimap then return FC.MinimapButton end

    local btn = CreateFrame("Button", "ForeverClassesMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(20)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Background / Icon Texture with dynamic character class crest
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 1)

    local _, classToken = UnitClass("player")
    local coords = CLASS_ICON_TCOORDS and classToken and CLASS_ICON_TCOORDS[classToken]
    if coords then
        icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        icon:SetTexCoord(0, 1, 0, 1)
    end
    btn.icon = icon

    -- Circular mask so corners are neatly rounded
    pcall(function()
        local mask = btn:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end)

    -- Circular Tracking Border Overlay
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    btn.border = border

    -- Dragging around Minimap
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self.isDragging = true
        self:SetScript("OnUpdate", function(s)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            if not mx or not my or not px or not py or not scale or scale == 0 then return end
            px, py = px / scale, py / scale
            local deg = math.deg(math.atan2(py - my, px - mx))
            ForeverClassesDB.minimapAngle = deg
            FC:UpdateMinimapPosition()
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self.isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    -- Click Handlers (Left = Settings, Right = Lock Toggle)
    if btn.RegisterForClicks then
        pcall(btn.RegisterForClicks, btn, "LeftButtonUp", "RightButtonUp")
    end

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if ForeverClassesDB.movementMode == "LOCKED" then
                ForeverClassesDB.movementMode = "FREE"
                print("|cff00ccff[ForeverClasses]|r Panel is now |cff44ff44UNLOCKED (Free Move)|r. Left-click & drag to move.")
            else
                ForeverClassesDB.movementMode = "LOCKED"
                print("|cff00ccff[ForeverClasses]|r Panel is now |cffff4444LOCKED|r.")
            end
            if FC.ApplyConfig then FC:ApplyConfig() end
            if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        else
            FC:ToggleConfig()
        end
    end)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff00ccffForeverClasses|r |cffffaa00(Beta-Test)|r", 1, 1, 1)
        GameTooltip:AddLine("|cff00ff00Left-Click:|r Open Settings Window", 0.9, 0.9, 0.9)
        local lockStatus = (ForeverClassesDB.movementMode == "LOCKED") and "Unlock frame" or "Lock frame"
        GameTooltip:AddLine("|cff00ff00Right-Click:|r " .. lockStatus, 0.9, 0.9, 0.9)
        GameTooltip:AddLine("|cff00ff00Drag:|r Move around Minimap", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    if Minimap and Minimap.HookScript then
        pcall(function()
            Minimap:HookScript("OnSizeChanged", function()
                if FC.UpdateMinimapPosition then
                    FC:UpdateMinimapPosition()
                end
            end)
        end)
    end

    FC.MinimapButton = btn
    FC:UpdateMinimapPosition()
    FC:UpdateMinimapVisibility()

    return btn
end

function FC:RunDebuffDebug()
    if FC.RunDebuffDiagnostics then
        FC:RunDebuffDiagnostics()
    end
end

-- ============================================================================
-- Slash Command Handler (/fc, /foreverclasses, /forever)
-- ============================================================================

local function HandleSlashCommands(msg)
    local cleanMsg = ""
    if msg then
        cleanMsg = (strtrim and strtrim(msg)) or msg:match("^%s*(.-)%s*$") or ""
    end

    -- Split input into lowercase tokens (words)
    local tokens = {}
    for word in string.gmatch(cleanMsg, "%S+") do
        table.insert(tokens, string.lower(word))
    end

    local cmd = (tokens[1] or ""):gsub("^%-+", "")
    local arg1 = (tokens[2] or ""):gsub("^%-+", "")
    local arg2 = (tokens[3] or ""):gsub("^%-+", "")

    -- If no arguments or asking for config / menu / /forever classes
    if cmd == "" or cmd == "config" or cmd == "options" or cmd == "opt" or cmd == "menu" or cmd == "classes" then
        local win = FC:CreateConfigWindow()
        if win:IsShown() then
            win:Hide()
        else
            win:Show()
        end

    -- Lock command
    elseif cmd == "lock" then
        ForeverClassesDB.movementMode = "LOCKED"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Panel is now |cffff4444LOCKED|r.")

    -- Unlock / Free Move
    elseif cmd == "unlock" or cmd == "move" or cmd == "free" or (cmd == "free" and arg1 == "move") then
        ForeverClassesDB.movementMode = "FREE"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Panel is now |cff44ff44UNLOCKED (Free Move)|r. Left-click & drag to move.")

    -- Modifier Drag
    elseif cmd == "mod" or cmd == "modifier" or cmd == "hold" then
        ForeverClassesDB.movementMode = "MODIFIER"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print(string.format("|cff00ccff[ForeverClasses]|r Hold |cff00ff00%s|r while dragging to move.", ForeverClassesDB.modifierKey or "ALT"))

    -- Upcoming heals toggle
    elseif cmd == "heals" or cmd == "heal" then
        ForeverClassesDB.showIncomingHeals = not ForeverClassesDB.showIncomingHeals
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.showIncomingHeals and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Upcoming Heals prediction: " .. state)

    -- Class-colored health bar toggle
    elseif cmd == "classcolor" or cmd == "class" or cmd == "cc" or cmd == "classhealth" then
        ForeverClassesDB.classColorHealth = not ForeverClassesDB.classColorHealth
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.classColorHealth and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Class-colored health bar: " .. state)

    -- Minimap button
    elseif cmd == "icon" or cmd == "minimap" then
        ForeverClassesDB.showMinimapIcon = true
        if FC.UpdateMinimapVisibility then FC:UpdateMinimapVisibility() end
        print("|cff00ccff[ForeverClasses]|r Minimap button is permanently enabled.")

    -- Combo points toggle
    elseif cmd == "cp" or cmd == "combopoints" or cmd == "combo" then
        local _, classToken = UnitClass("player")
        if classToken ~= "ROGUE" and classToken ~= "DRUID" then
            print("|cff00ccff[ForeverClasses]|r Combo Points are only available for Rogue and Druid.")
            return
        end
        ForeverClassesDB.showComboPoints = not ForeverClassesDB.showComboPoints
        if FC.UpdateComboPoints then FC:UpdateComboPoints() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.showComboPoints and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Combo Points display: " .. state)

    -- Low health warning toggle
    elseif cmd == "lowhealth" or cmd == "low" or cmd == "warning" then
        ForeverClassesDB.lowHealthWarning = not ForeverClassesDB.lowHealthWarning
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.lowHealthWarning and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Low health warning flash: " .. state)

    -- Test low health warning simulation (/fc testlow or /fc-testlow)
    elseif cmd == "testlow" or (cmd == "test" and (arg1 == "low" or arg1 == "warning")) then
        print("|cff00ccff[ForeverClasses]|r Testing Low Health Warning Flash (simulating 18% HP for 6s)...")
        FC.testLowHealth = true
        if FC.UpdateHealth then FC:UpdateHealth() end
        if C_Timer and C_Timer.After then
            C_Timer.After(6, function()
                FC.testLowHealth = nil
                if FC.UpdateHealth then FC:UpdateHealth() end
                print("|cff00ccff[ForeverClasses]|r Low Health Warning test ended.")
            end)
        end

    -- Low health threshold setting (/fc threshold 33)
    elseif cmd == "threshold" or cmd == "hpthreshold" then
        local num = tonumber(arg1)
        if num and num >= 5 and num <= 90 then
            ForeverClassesDB.lowHealthThreshold = num
            if FC.SaveCharSetting then FC:SaveCharSetting("lowHealthThreshold", num) end
            if FC.UpdateHealth then FC:UpdateHealth() end
            if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
            print(string.format("|cff00ccff[ForeverClasses]|r Low health warning threshold set to: |cff00ff00%d%%|r", num))
        else
            local curr = ForeverClassesDB.lowHealthThreshold or 33
            print(string.format("|cff00ccff[ForeverClasses]|r Current threshold: |cff00ff00%d%%|r. Usage: /fc threshold 33 (range 5-90)", curr))
        end

    -- Harmful Debuffs diagnosis (/fc debugdebuff)
    elseif cmd == "debugdebuff" or cmd == "debuffdebug" or cmd == "checkdebuff" or ((cmd == "debuff" or cmd == "debuffs") and (arg1 == "debug" or arg1 == "check" or arg1 == "diag")) then
        if FC.RunDebuffDiagnostics then
            FC:RunDebuffDiagnostics()
        else
            print("|cff00ccff[ForeverClasses]|r Debuff diagnostics not available.")
        end

    -- Harmful Debuffs toggle
    elseif cmd == "debuff" or cmd == "debuffs" or cmd == "dispel" then
        ForeverClassesDB.showDebuffs = not ForeverClassesDB.showDebuffs
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.showDebuffs and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Harmful Debuff icons display: " .. state .. ". (Type |cffffd100/fc debugdebuff|r for diagnostics)")

    -- Test debuff simulation (/fc testdebuff or /fc-testdebuff)
    elseif cmd == "testdebuff" or (cmd == "test" and (arg1 == "debuff" or arg1 == "debuffs")) then
        print("|cff00ccff[ForeverClasses]|r Simulating Harmful Debuff Icons (Deadly Poison, Rend, Curse of Agony) on right of bar for 8 seconds...")
        FC.testDebuffsActive = true
        if FC.UpdateDebuffs then FC:UpdateDebuffs() end
        if C_Timer and C_Timer.After then
            C_Timer.After(8, function()
                FC.testDebuffsActive = nil
                if FC.UpdateDebuffs then FC:UpdateDebuffs() end
                print("|cff00ccff[ForeverClasses]|r Debuff icons test ended.")
            end)
        end

    -- Test combo points simulation (/fc testcp or /fc-testcp)
    elseif cmd == "testcp" or (cmd == "test" and (arg1 == "cp" or arg1 == "combo")) then
        print("|cff00ccff[ForeverClasses]|r Testing Rogue Circular Combo Points sequence (1 to 5 CP)...")
        print("|cff00ccff[ForeverClasses]|r Note: In normal gameplay, these circular orbs appear beneath the panel only while in combat.")
        FC.previousComboPoints = 0
        FC.testComboPoints = 1
        if FC.UpdateComboPoints then FC:UpdateComboPoints() end

        local step = 1
        local function RunStep()
            step = step + 1
            if step <= 5 then
                FC.testComboPoints = step
                if FC.UpdateComboPoints then FC:UpdateComboPoints() end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.9, RunStep)
                end
            else
                if C_Timer and C_Timer.After then
                    C_Timer.After(2.5, function()
                        FC.testComboPoints = nil
                        if FC.UpdateComboPoints then FC:UpdateComboPoints() end
                        print("|cff00ccff[ForeverClasses]|r Combo Points test ended.")
                    end)
                end
            end
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0.9, RunStep)
        end

    -- Test incoming heal simulation (/fc testheal or /fc-testheal)
    elseif cmd == "testheal" or (cmd == "test" and (arg1 == "heal" or arg1 == "")) then
        local maxH = 1000
        pcall(function()
            local mh = UnitHealthMax("player")
            if mh and not IsSecret(mh) and mh > 0 then
                maxH = mh
            end
        end)
        FC.testIncomingHeal = math.floor(maxH * 0.35)
        print("|cff00ccff[ForeverClasses]|r Simulating incoming heal (" .. FC.testIncomingHeal .. " HP) on wounded bar for 5 seconds...")
        print("|cff00ccff[ForeverClasses]|r Note: Incoming heals fill missing health up to 100%.")
        if FC.UpdateHealth then FC:UpdateHealth() end
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function()
                FC.testIncomingHeal = nil
                if FC.UpdateHealth then FC:UpdateHealth() end
                print("|cff00ccff[ForeverClasses]|r Test incoming heal ended.")
            end)
        end

    -- Ability & Cooldown Bar toggle & management (/fc cd, /fc cds, /fc cd <slot> <spell>, /fc clearcd <slot>, etc.)
    elseif cmd == "cd" or cmd == "cds" or cmd == "cooldown" or cmd == "cooldowns" then
        if arg1 == "list" or (arg1 == "show" and arg2 == "list") then
            local slots = FC:GetCooldownSlots()
            local charKey = FC:GetCharKey()
            print(string.format("|cff00ccff[ForeverClasses]|r Cooldown Slots for |cffffd100%s|r (1 - %d):", charKey, (FC.MAX_COOLDOWN_SLOTS or 7)))
            for i = 1, (FC.MAX_COOLDOWN_SLOTS or 7) do
                local d = slots and slots[i]
                if d and d.name then
                    print(string.format("  Slot %d: |cff00ff00%s|r (%s)", i, d.name, d.type or "spell"))
                else
                    print(string.format("  Slot %d: |cff888888(Empty - drag ability here)|r", i))
                end
            end
        elseif arg1 == "clear" or arg1 == "reset" then
            local slotIdx = tonumber(arg2)
            if slotIdx then
                FC:ClearSlot(slotIdx)
            else
                local slots = FC:GetCooldownSlots()
                if table.wipe then
                    table.wipe(slots)
                else
                    for k in pairs(slots) do slots[k] = nil end
                end
                local charData = FC:GetCharData()
                if arg1 == "reset" and FC.PopulateDefaultCooldowns then
                    FC:PopulateDefaultCooldowns(true)
                else
                    if charData then charData.cooldownDefaultsPopulated = true end
                    ForeverClassesDB.cooldownDefaultsPopulated = true
                end
                if FC.UpdateCooldowns then FC:UpdateCooldowns() end
                if arg1 == "reset" then
                    print("|cff00ccff[ForeverClasses]|r Reset ability slots to known class defaults.")
                else
                    print("|cff00ccff[ForeverClasses]|r Cleared all ability slots.")
                end
            end
        elseif tonumber(arg1) then
            -- /fc cd <slot> <spellName or spellID>
            local slotIdx = tonumber(arg1)
            local spellQuery = cleanMsg:match("^%s*%S+%s+%d+%s+(.-)%s*$")
            if spellQuery and spellQuery ~= "" then
                local sInfo = FC.ResolveSpellInfo and FC:ResolveSpellInfo(spellQuery)
                local iInfo = not sInfo and FC.ResolveItemInfo and FC:ResolveItemInfo(spellQuery)
                local slots = FC:GetCooldownSlots()
                if sInfo and sInfo.icon then
                    slots[slotIdx] = {
                        type = "spell",
                        id = sInfo.id,
                        name = sInfo.name,
                        icon = sInfo.icon,
                    }
                    print(string.format("|cff00ccff[ForeverClasses]|r Set slot %d to spell |cff00ff00%s|r.", slotIdx, sInfo.name))
                elseif iInfo and iInfo.icon then
                    slots[slotIdx] = {
                        type = "item",
                        id = iInfo.id,
                        name = iInfo.name,
                        icon = iInfo.icon,
                    }
                    print(string.format("|cff00ccff[ForeverClasses]|r Set slot %d to item |cff00ff00%s|r.", slotIdx, iInfo.name))
                else
                    print(string.format("|cff00ccff[ForeverClasses]|r Could not find valid spell or item '%s'.", spellQuery))
                end
                if FC.UpdateCooldowns then FC:UpdateCooldowns() end
            else
                -- Just query slot
                local d = ForeverClassesDB.cooldownSlots and ForeverClassesDB.cooldownSlots[slotIdx]
                if d and d.name then
                    print(string.format("|cff00ccff[ForeverClasses]|r Slot %d: |cff00ff00%s|r", slotIdx, d.name))
                else
                    print(string.format("|cff00ccff[ForeverClasses]|r Slot %d is empty.", slotIdx))
                end
            end
        else
            -- Toggle visibility
            if (ForeverClassesDB.cooldownSlotCount or 7) > 0 and ForeverClassesDB.showCooldowns ~= false then
                FC:SetCooldownSlotCount(0)
            else
                FC:SetCooldownSlotCount(7)
            end
            local state = ForeverClassesDB.showCooldowns and string.format("|cff44ff44Enabled (%d Slots)|r", ForeverClassesDB.cooldownSlotCount) or "|cffff4444Disabled|r"
            print("|cff00ccff[ForeverClasses]|r Ability & Cooldown Bar display: " .. state)
        end

    -- Cooldown slots command (/fc slots <0-7>)
    elseif cmd == "slots" or cmd == "barslots" then
        local targetNum = tonumber(arg1)
        if targetNum and targetNum >= 0 and targetNum <= 7 then
            FC:SetCooldownSlotCount(targetNum)
            if targetNum == 0 then
                print("|cff00ccff[ForeverClasses]|r Cooldown Bar is now |cffff4444Disabled (0 Slots)|r.")
            else
                print(string.format("|cff00ccff[ForeverClasses]|r Cooldown Bar set to: |cff00ff00%d Slots|r.", targetNum))
            end
        else
            local cur = ForeverClassesDB.cooldownSlotCount or 7
            print(string.format("|cff00ccff[ForeverClasses]|r Current slots: |cff00ff00%d|r. Usage: /fc slots <0-7> (0 = Off)", cur))
        end

    -- Clear Cooldown Slot (/fc clearcd <slot>)
    elseif cmd == "clearcd" or cmd == "clearslot" then
        local slotIdx = tonumber(arg1)
        if slotIdx then
            FC:ClearSlot(slotIdx)
        else
            print("|cff00ccff[ForeverClasses]|r Usage: /fc clearcd <1-7> (or /fc cd clear to reset defaults)")
        end

    -- List Cooldown Slots (/fc listcds)
    elseif cmd == "listcds" or cmd == "listcd" then
        print("|cff00ccff[ForeverClasses]|r Cooldown Slots (1 - " .. (FC.MAX_COOLDOWN_SLOTS or 7) .. "):")
        for i = 1, (FC.MAX_COOLDOWN_SLOTS or 7) do
            local d = ForeverClassesDB.cooldownSlots and ForeverClassesDB.cooldownSlots[i]
            if d and d.name then
                print(string.format("  Slot %d: |cff00ff00%s|r (%s)", i, d.name, d.type or "spell"))
            else
                print(string.format("  Slot %d: |cff888888(Empty - drag ability here)|r", i))
            end
        end

    -- Quick Swap pool info (/fc swap, /fc swap clear <slot>)
    elseif cmd == "swap" or cmd == "swaps" or cmd == "flyout" then
        if arg1 == "clear" then
            local slotIdx = tonumber(arg2)
            if slotIdx and slotIdx >= 1 and slotIdx <= (FC.MAX_COOLDOWN_SLOTS or 7) then
                local swapSlots = FC:GetCooldownSwapSlots(slotIdx)
                if swapSlots then
                    if table.wipe then
                        table.wipe(swapSlots)
                    else
                        for k in pairs(swapSlots) do swapSlots[k] = nil end
                    end
                end
                print(string.format("|cff00ccff[ForeverClasses]|r Cleared Quick Swap pool for Slot %d.", slotIdx))
                if FC.RefreshFlyout then FC:RefreshFlyout(slotIdx) end
                if FC.UpdateCooldownIndicators then FC:UpdateCooldownIndicators() end
            else
                print("|cff00ccff[ForeverClasses]|r Usage: /fc swap clear <1-7>")
            end
        else
            print("|cff00ccff[ForeverClasses]|r Quick Swap Pool Status:")
            for i = 1, (FC.MAX_COOLDOWN_SLOTS or 7) do
                local swapSlots = FC:GetCooldownSwapSlots(i)
                local mainSlot = ForeverClassesDB.cooldownSlots and ForeverClassesDB.cooldownSlots[i]
                local mainName = mainSlot and mainSlot.name or "Empty"
                local pool = {}
                if swapSlots and #swapSlots > 0 then
                    for _, s in ipairs(swapSlots) do
                        table.insert(pool, s.name or "Unknown")
                    end
                end
                local poolStr = (#pool > 0) and table.concat(pool, ", ") or "None (Left-Click slot to add)"
                print(string.format("  Slot %d [Active: |cff00ff00%s|r]: Stored: |cffffd100%s|r", i, mainName, poolStr))
            end
        end

    -- Test cooldown simulation (/fc testcd or /fc-testcd)
    elseif cmd == "testcd" or cmd == "testcds" or cmd == "testcooldown" or (cmd == "test" and (arg1 == "cd" or arg1 == "cooldown")) then
        print("|cff00ccff[ForeverClasses]|r Simulating Phase 2 Cooldown Bar (7 Slots) for 8 seconds...")
        print("  |cff88ff88Slot 1: Kick (On Cooldown - 4.2s)|r")
        print("  |cff88ff88Slot 2: Gouge (Ready - full color)|r")
        print("  |cff88ff88Slot 3: Sprint (Active Buff - gold border glow & timer)|r")
        print("  |cff88ff88Slot 4: Evasion (On Cooldown - 45s)|r")
        print("  |cff88ff88Slot 5: Vanish (On Cooldown - 2m)|r")
        print("  |cff88ff88Slot 6: Blind (On Cooldown - 1m 15s)|r")
        print("  |cff88ff88Slot 7: Cold Blood (Ready - full color)|r")
        FC.testCooldownsActive = true
        if FC.UpdateCooldowns then FC:UpdateCooldowns() end
        if C_Timer and C_Timer.After then
            C_Timer.After(8, function()
                FC.testCooldownsActive = nil
                if FC.UpdateCooldowns then FC:UpdateCooldowns() end
                print("|cff00ccff[ForeverClasses]|r Cooldown Bar test ended.")
            end)
        end

    -- Attach Blizzard Cooldown Manager (/fc attach, /fc snap, /fc anchor)
    elseif cmd == "attach" or cmd == "snap" or cmd == "anchor" then
        ForeverClassesDB.attachCooldownManager = true
        if FC.AttachEssentialCooldowns then
            pcall(FC.AttachEssentialCooldowns, FC)
        end
        print("|cff00ccff[ForeverClasses]|r Blizzard EssentialCooldownViewer anchored directly above Health Bar.")

    -- Detach Blizzard Cooldown Manager (/fc detach)
    elseif cmd == "detach" or cmd == "unsnap" then
        ForeverClassesDB.attachCooldownManager = false
        print("|cff00ccff[ForeverClasses]|r Blizzard EssentialCooldownViewer unanchored (freely movable in Edit Mode).")

    -- Slice and Dice talent / duration configuration (/fc snd, /fc snd <0-3>)
    elseif cmd == "snd" or cmd == "slice" or cmd == "snk" then
        local rankArg = tonumber(arg1)
        local charData = FC.GetCharData and FC:GetCharData()
        if rankArg ~= nil and rankArg >= 0 and rankArg <= 3 then
            local mult = 1.0 + (rankArg * 0.15)
            FC.improvedSliceAndDiceRank = rankArg
            FC.improvedSliceAndDiceMult = mult
            FC.improvedSliceAndDiceSource = "Manual"
            if charData then
                charData.improvedSliceAndDiceRank = rankArg
                charData.improvedSliceAndDiceMult = mult
                charData.improvedSliceAndDiceSource = "Manual"
            end
            print(string.format("|cff00ccff[ForeverClasses]|r Improved Slice and Dice set to |cff00ff00%d/3|r (Multiplier: |cffffd100%.2fx|r / +%d%% duration).",
                rankArg, mult, rankArg * 15))
            print(string.format("  |cff888888Durations: 1 CP = %.1fs, 2 CP = %.1fs, 3 CP = %.1fs, 4 CP = %.1fs, 5 CP = %.1fs|r",
                9 * mult, 12 * mult, 15 * mult, 18 * mult, 21 * mult))
        else
            if FC.UpdateTalentCache then pcall(FC.UpdateTalentCache, FC) end
            local r = FC.improvedSliceAndDiceRank or (charData and charData.improvedSliceAndDiceRank) or 0
            local m = FC.improvedSliceAndDiceMult or (charData and charData.improvedSliceAndDiceMult) or 1.0
            local src = FC.improvedSliceAndDiceSource or (charData and charData.improvedSliceAndDiceSource) or "Default"
            print(string.format("|cff00ccff[ForeverClasses]|r Improved Slice and Dice: |cff00ff00%d/3|r | Multiplier: |cffffd100%.2fx|r | Source: |cffaaaaaa%s|r",
                r, m, tostring(src)))
            print(string.format("  |cff888888Durations: 1 CP = %.1fs, 2 CP = %.1fs, 3 CP = %.1fs, 4 CP = %.1fs, 5 CP = %.1fs|r",
                9 * m, 12 * m, 15 * m, 18 * m, 21 * m))
            print("  |cff888888To set manually: /fc snd <0-3> (e.g. /fc snd 3 for 3/3)|r")
        end

    -- Cooldown Diagnostics (/fc cddebug)
    elseif cmd == "cddebug" or cmd == "cdsdebug" then
        print("|cff00ccff[ForeverClasses Cooldown Diagnostics]|r")
        local now = GetTime()
        for i = 1, (FC.MAX_COOLDOWN_SLOTS or 7) do
            local d = ForeverClassesDB.cooldownSlots and ForeverClassesDB.cooldownSlots[i]
            if d and (d.id or d.name) then
                local isKnown = (d.type == "spell") and (FC.IsSpellLearned and FC:IsSpellLearned(d.id or d.name) or false) or true
                local cdStart, cdDur, cdEn, modR, isSec, isAct = FC:GetCooldownData(d)
                local rem = 0
                if not isSec and cdStart and cdDur and (tonumber(cdStart) or 0) > 0 then
                    rem = math.max(0, ((tonumber(cdStart) or 0) + (tonumber(cdDur) or 0)) - now)
                end
                local isUsable, noMana = true, false
                local target = d.name or d.id
                if C_Spell and C_Spell.IsSpellUsable and target then
                    pcall(function() isUsable, noMana = C_Spell.IsSpellUsable(target) end)
                elseif IsUsableSpell and target then
                    pcall(function() isUsable, noMana = IsUsableSpell(target) end)
                end
                local clean = d.name and string.lower((strtrim and strtrim(d.name)) or d.name)
                local actSlots = (clean and FC.actionSlotsBySpell and FC.actionSlotsBySpell[clean]) or (d.id and FC.actionSlotsBySpellID and FC.actionSlotsBySpellID[d.id])
                local actStr = actSlots and table.concat(actSlots, ",") or "none"
                local ranks = clean and FC.spellRanksCache and FC.spellRanksCache[clean]
                local rankStr = ranks and (#ranks .. " (highest " .. tostring(FC.highestRankBySpellName[clean]) .. ")") or "n/a"
                if isSec then
                    print(string.format("  Slot %d: |cff00ff00%s|r [id: %s, actSlots: %s, ranks: %s] | SECRET: true, active: %s, en: %s, usable: %s",
                        i, tostring(d.name), tostring(d.id), actStr, rankStr, tostring(isAct), tostring(cdEn), tostring(isUsable)))
                else
                    print(string.format("  Slot %d: |cff00ff00%s|r [id: %s, actSlots: %s, ranks: %s] | cd: %.1fs (dur: %.1fs), active: %s, en: %s, usable: %s, noMana: %s, known: %s",
                        i, tostring(d.name), tostring(d.id), actStr, rankStr, rem, (tonumber(cdDur) or 0), tostring(isAct), tostring(cdEn), tostring(isUsable), tostring(noMana), tostring(isKnown)))
                end
            else
                print(string.format("  Slot %d: <Empty>", i))
            end
        end

    -- Text display: Both multi-word ("/fc text both"), hyphenated ("/fc-both"), or short ("/fc both")
    elseif cmd == "text" or cmd == "both" or cmd == "num" or cmd == "numeric" or cmd == "pct" or cmd == "percent" or cmd == "percentage" or cmd == "none" or cmd == "hide" or cmd == "sync" then
        local targetMode = nil
        local modeWord = (cmd == "text") and arg1 or cmd

        if modeWord == "both" then
            targetMode = "BOTH"
        elseif modeWord == "num" or modeWord == "numeric" then
            targetMode = "NUMERIC"
        elseif modeWord == "pct" or modeWord == "percent" or modeWord == "percentage" then
            targetMode = "PERCENT"
        elseif modeWord == "none" or modeWord == "hide" then
            targetMode = "NONE"
        elseif modeWord == "sync" then
            targetMode = "SYNC"
        elseif modeWord == "" then
            local modes = { "BOTH", "NUMERIC", "PERCENT", "NONE", "SYNC" }
            local current = ForeverClassesDB.textMode or "BOTH"
            for i, m in ipairs(modes) do
                if m == current then
                    targetMode = modes[(i % #modes) + 1]
                    break
                end
            end
            targetMode = targetMode or "BOTH"
        end

        if targetMode then
            ForeverClassesDB.textMode = targetMode
            if FC.ApplyConfig then FC:ApplyConfig() end
            if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
            print("|cff00ccff[ForeverClasses]|r Text display set to: |cff00ff00" .. targetMode .. "|r")
        else
            print("|cff00ccff[ForeverClasses]|r Usage: /fc-both, /fc-num, /fc-pct, /fc-sync, /fc-none")
        end

    -- Reset position
    elseif cmd == "reset" then
        ForeverClassesDB.point = FC.Defaults.point
        ForeverClassesDB.relativePoint = FC.Defaults.relativePoint
        ForeverClassesDB.x = FC.Defaults.x
        ForeverClassesDB.y = FC.Defaults.y
        if FC.ApplyConfig then FC:ApplyConfig() end
        print("|cff00ccff[ForeverClasses]|r Position reset to center.")

    -- Debug info
    elseif cmd == "debug" then
        local pType, pToken
        pcall(function() pType, pToken = UnitPowerType("player") end)
        local _, class = UnitClass("player")
        local r, g, b = FC:GetPowerColor()
        local isSecH = issecretvalue and issecretvalue(UnitHealth("player"))
        local isSecP = false
        pcall(function() isSecP = issecretvalue and issecretvalue(UnitPower("player", pType or 0)) end)
        local rawH = UnitHealth("player")
        local rawMax = UnitHealthMax("player")
        local thresh = ForeverClassesDB.lowHealthThreshold or 33
        local isLow = false
        local curHStr, maxHStr, pctStr = "secret", "secret", "secret"

        if not isSecH and rawH and rawMax then
            local curH = tonumber(rawH) or 0
            local maxH = tonumber(rawMax) or 1
            local pctH = (maxH > 0) and ((curH / maxH) * 100) or 0
            curHStr = tostring(curH)
            maxHStr = tostring(maxH)
            pctStr = string.format("%.1f%%", pctH)
            isLow = (pctH <= thresh and curH > 0)
        end

        local curveAlphaStr = "N/A"
        if C_CurveUtil and C_CurveUtil.CreateColorCurve and UnitHealthPercent then
            local threshDec = thresh / 100
            local okCurve, c = pcall(function()
                local curve = C_CurveUtil.CreateColorCurve()
                curve:SetType(Enum.LuaCurveType.Step)
                curve:AddPoint(0, CreateColor(1, 0, 0, 1))
                curve:AddPoint(threshDec, CreateColor(0, 0, 0, 0))
                return curve
            end)
            if okCurve and c then
                local okCol, col = pcall(UnitHealthPercent, "player", true, c)
                if okCol and col and col.GetRGBA then
                    local okA, _, _, _, a = pcall(col.GetRGBA, col)
                    if okA and a ~= nil then
                        curveAlphaStr = issecretvalue and issecretvalue(a) and "<secret alpha>" or tostring(a)
                        if not (issecretvalue and issecretvalue(a)) then
                            local aNum = tonumber(a)
                            if aNum and aNum > 0.01 then isLow = true end
                        end
                    end
                end
            end
        end

        print(string.format("|cff00ccff[ForeverClasses Debug]|r HP: %s/%s (%s) | Threshold: %d%% | WarnEnabled: %s | LowTriggered: %s | CurveAlpha: %s",
            curHStr, maxHStr, pctStr, thresh, tostring(ForeverClassesDB.lowHealthWarning), tostring(isLow), curveAlphaStr))
        print(string.format("|cff00ccff[ForeverClasses Debug]|r Combo Atlases: BG = %s, Point = %s",
            tostring(FC.resolvedComboBgAtlas or "none"), tostring(FC.resolvedComboFillAtlas or "none")))

        if class == "ROGUE" then
            local charData = FC.GetCharData and FC:GetCharData()
            local r = FC.improvedSliceAndDiceRank or (charData and charData.improvedSliceAndDiceRank) or 0
            local m = FC.improvedSliceAndDiceMult or (charData and charData.improvedSliceAndDiceMult) or 1.0
            local src = FC.improvedSliceAndDiceSource or (charData and charData.improvedSliceAndDiceSource) or "Default"
            print(string.format("|cff00ccff[ForeverClasses Debug]|r Rogue Slice and Dice: %d/3 (Mult: %.2fx, Source: %s)",
                r, m, tostring(src)))
        elseif class == "SHAMAN" then
            local charData = FC.GetCharData and FC:GetCharData()
            local r = FC.improvedStormstrikeRank or (charData and charData.improvedStormstrikeRank) or 0
            local src = FC.improvedStormstrikeSource or (charData and charData.improvedStormstrikeSource) or "Default"
            print(string.format("|cff00ccff[ForeverClasses Debug]|r Shaman Improved Stormstrike: %d/2 (Source: %s)",
                r, tostring(src)))
        end

    -- Debuff Diagnostics
    elseif cmd == "debuffdebug" or cmd == "debuffsdebug" or cmd == "auradebug" then
        if FC.RunDebuffDebug then
            FC:RunDebuffDebug()
        end

    -- Ignore / Exclude Debuffs
    elseif cmd == "ignore" or cmd == "exclude" or cmd == "blacklist" then
        local targetDebuff = cleanMsg:match("^%s*%S+%s+(.-)%s*$")
        if not targetDebuff or targetDebuff == "" or targetDebuff:lower() == "list" then
            print("|cff00ccff[ForeverClasses]|r Ignored / Excluded Debuffs List:")
            local defaultsList = {}
            if FC.DEFAULT_IGNORED_DEBUFFS then
                for k in pairs(FC.DEFAULT_IGNORED_DEBUFFS) do
                    table.insert(defaultsList, k)
                end
            end
            table.sort(defaultsList)
            print("  |cff88ccffDefault:|r " .. table.concat(defaultsList, ", "))
            local customList = {}
            if ForeverClassesDB and ForeverClassesDB.ignoredDebuffs then
                for k, v in pairs(ForeverClassesDB.ignoredDebuffs) do
                    if v then table.insert(customList, k) end
                end
            end
            if #customList > 0 then
                table.sort(customList)
                print("  |cff88ff88Custom:|r " .. table.concat(customList, ", "))
            else
                print("  |cff88ff88Custom:|r None (use |cff00ff00/fc ignore <name>|r to add)")
            end
        else
            local clean = targetDebuff:lower()
            ForeverClassesDB.ignoredDebuffs = ForeverClassesDB.ignoredDebuffs or {}
            ForeverClassesDB.ignoredDebuffs[clean] = true
            if FC.UpdateDebuffs then FC:UpdateDebuffs() end
            print("|cff00ccff[ForeverClasses]|r Added '|cffff7777" .. targetDebuff .. "|r' to ignored debuffs.")
        end

    -- Unignore / Include Debuffs
    elseif cmd == "unignore" or cmd == "whitelist" then
        local targetDebuff = cleanMsg:match("^%s*%S+%s+(.-)%s*$")
        if targetDebuff and targetDebuff ~= "" then
            local clean = targetDebuff:lower()
            if ForeverClassesDB and ForeverClassesDB.ignoredDebuffs then
                ForeverClassesDB.ignoredDebuffs[clean] = nil
            end
            if FC.UpdateDebuffs then FC:UpdateDebuffs() end
            print("|cff00ccff[ForeverClasses]|r Removed '|cff77ff77" .. targetDebuff .. "|r' from custom ignored debuffs.")
        else
            print("|cff00ccff[ForeverClasses]|r Usage: /fc unignore <Debuff Name>")
        end

    -- Script Errors toggle
    elseif cmd == "errors" or cmd == "bugs" then
        local current = GetCVar and GetCVar("scriptErrors")
        local newVal = (current == "1") and "0" or "1"
        if SetCVar then
            SetCVar("scriptErrors", newVal)
        end
        print("|cff00ccff[ForeverClasses]|r Lua scriptErrors is now: |cff00ff00" .. newVal .. "|r (1 = show error dialogs, 0 = hide)")

    -- Garbage Collection / Memory Check
    elseif cmd == "gc" or cmd == "memory" or cmd == "mem" then
        if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
            UpdateAddOnMemoryUsage()
            local before = GetAddOnMemoryUsage("ForeverClasses") or 0
            collectgarbage("collect")
            UpdateAddOnMemoryUsage()
            local after = GetAddOnMemoryUsage("ForeverClasses") or 0
            print(string.format("|cff00ccff[ForeverClasses]|r Memory cleaned: |cffff5555%.2f MB|r -> |cff00ff00%.2f MB|r (Freed: %.2f MB)", before / 1024, after / 1024, (before - after) / 1024))
        else
            collectgarbage("collect")
            print("|cff00ccff[ForeverClasses]|r Garbage collection executed.")
        end

    -- Cooldown Ready Flash / Pulse toggle
    elseif cmd == "pulse" or cmd == "flash" or cmd == "readyflash" then
        if ForeverClassesDB.cooldownPulse == nil then
            ForeverClassesDB.cooldownPulse = true
        end
        ForeverClassesDB.cooldownPulse = not ForeverClassesDB.cooldownPulse
        local st = ForeverClassesDB.cooldownPulse and "|cff00ff00ENABLED|r" or "|cffff4444DISABLED|r"
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Cooldown Ready Pulse: " .. st)

    -- Test Cooldown Ready Pulse animation (/fc testpulse)
    elseif cmd == "testpulse" or cmd == "testready" or cmd == "testflash" then
        if FC.CooldownBar and FC.CooldownBar.slots then
            local count = ForeverClassesDB.cooldownSlotCount or 7
            for i = 1, count do
                local b = FC.CooldownBar.slots[i]
                if b and b:IsShown() and FC.PlayCooldownReadyPulse then
                    if C_Timer and C_Timer.After then
                        C_Timer.After((i - 1) * 0.08, function()
                            FC:PlayCooldownReadyPulse(b)
                        end)
                    else
                        FC:PlayCooldownReadyPulse(b)
                    end
                end
            end
            print("|cff00ccff[ForeverClasses]|r Testing Cooldown Ready Pulse animation...")
        else
            print("|cff00ccff[ForeverClasses]|r Cooldown bar not active.")
        end

    -- Shaman Improved Stormstrike override / check (/fc ss, /fc ss 2, /fc ss 0)
    elseif cmd == "ss" or cmd == "stormstrike" or cmd == "improvedstormstrike" then
        local rNum = tonumber(arg1)
        local charData = FC.GetCharData and FC:GetCharData()
        if rNum and rNum >= 0 and rNum <= 2 then
            FC.improvedStormstrikeRank = rNum
            FC.improvedStormstrikeSource = "ManualOverride"
            if charData then
                charData.improvedStormstrikeRank = rNum
                charData.improvedStormstrikeSource = "ManualOverride"
            end
            print(string.format("|cff00ccff[ForeverClasses]|r Improved Stormstrike rank set to: |cff00ff00%d/2|r (100%% proc on dodge/parry: %s)",
                rNum, (rNum >= 2 and "|cff00ff00YES|r" or (rNum == 1 and "|cffffaa0050% Chance|r" or "|cffff4444NO|r"))))
        else
            if FC.UpdateTalentCache then pcall(FC.UpdateTalentCache, FC) end
            local cur = FC.improvedStormstrikeRank or (charData and charData.improvedStormstrikeRank) or 0
            local src = FC.improvedStormstrikeSource or (charData and charData.improvedStormstrikeSource) or "Unknown"
            print(string.format("|cff00ccff[ForeverClasses]|r Improved Stormstrike: |cff00ff00%d/2|r (Source: %s). Usage to override: |cff00ff00/fc ss <0-2>|r",
                cur, tostring(src)))
        end

    -- Shaman Totems toggle (/fc totems, /fc totem)
    elseif cmd == "totem" or cmd == "totems" or cmd == "totembar" then
        local _, classToken = UnitClass("player")
        if classToken ~= "SHAMAN" then
            print("|cff00ccff[ForeverClasses]|r Totem Bar is only available for Shaman.")
            return
        end
        ForeverClassesDB.showTotems = not ForeverClassesDB.showTotems
        if FC.UpdateTotems then FC:UpdateTotems() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.showTotems and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Shaman Totem Bar: " .. state)

    -- Test Totem Bar preview (/fc testtotem, /fc testtotems)
    elseif cmd == "testtotem" or cmd == "testtotems" then
        print("|cff00ccff[ForeverClasses]|r Simulating 4 active Totems (Windfury simulated |cffff3333Out of Range|r) for 10 seconds...")
        local now = GetTime()
        FC.testTotems = {
            { slot = 1, testName = "Stoneskin Totem", element = "Earth", icon = 136098, startTime = now, duration = 300, testOutOfRange = false },
            { slot = 2, testName = "Searing Totem", element = "Fire", icon = 135824, startTime = now, duration = 300, testOutOfRange = false },
            { slot = 3, testName = "Mana Spring Totem", element = "Water", icon = 136053, startTime = now, duration = 300, testOutOfRange = false },
            { slot = 4, testName = "Windfury Totem", element = "Air", icon = 136018, startTime = now - 81, duration = 120, testOutOfRange = true },
        }
        if FC.UpdateTotems then FC:UpdateTotems() end
        if FC.RequestFadeCheck then FC:RequestFadeCheck() end
        if C_Timer and C_Timer.After then
            C_Timer.After(10, function()
                FC.testTotems = nil
                if FC.UpdateTotems then FC:UpdateTotems() end
                if FC.RequestFadeCheck then FC:RequestFadeCheck() end
                print("|cff00ccff[ForeverClasses]|r Totem Bar test preview ended.")
            end)
        end

    -- Test Absorb Shield preview (/fc testabsorb, /fc testshield)
    elseif cmd == "testabsorb" or cmd == "testshield" or cmd == "testabsorbs" then
        print("|cff00ccff[ForeverClasses]|r Simulating Absorb Shield preview (8 seconds)...")
        print("  |cff00ff00[Phase 1: 0s-4s]|r: |cff33ccffWounded (80% HP) + Overshield (40%)|r -> Fills 20% gap + Cyan Glow Bracket!")
        print("  |cff00ff00[Phase 2: 4s-8s]|r: |cff33ccffWounded (80% HP) + Shrunk Shield (10%)|r -> Fills only 10%, no glow!")

        local maxH = 1000
        if UnitHealthMax and not IsSecret(UnitHealthMax("player")) and UnitHealthMax("player") > 0 then
            maxH = UnitHealthMax("player")
        end

        -- Phase 1 (0s - 4s): 80% HP + 40% Absorb Shield (Overshield: Fills the entire 20% missing gap + Cyan Glow)
        FC.testAbsorb = math.floor(maxH * 0.40)
        if FC.UpdateHealth then FC:UpdateHealth() end
        if FC.RequestFadeCheck then FC:RequestFadeCheck() end

        if C_Timer and C_Timer.After then
            -- Phase 2 (4s - 8s): 80% HP + 10% Absorb Shield (Shrunk shield: Fills only 10% of the 20% gap, Glow hidden)
            C_Timer.After(4, function()
                if FC.testAbsorb ~= nil then
                    FC.testAbsorb = math.floor(maxH * 0.10)
                    if FC.UpdateHealth then FC:UpdateHealth() end
                    if FC.RequestFadeCheck then FC:RequestFadeCheck() end
                    print("|cff00ccff[ForeverClasses]|r Phase 2: Shrunk Shield (10% fill, gap partially empty, glow off).")
                end
            end)

            -- End of simulation (8s)
            C_Timer.After(8, function()
                FC.testAbsorb = nil
                if FC.UpdateHealth then FC:UpdateHealth() end
                if FC.RequestFadeCheck then FC:RequestFadeCheck() end
                print("|cff00ccff[ForeverClasses]|r Absorb Shield test simulation finished.")
            end)
        end

    -- Absorb / Shield toggle (/fc absorb, /fc shield)
    elseif cmd == "absorb" or cmd == "absorbs" or cmd == "shield" or cmd == "shields" then
        ForeverClassesDB.showAbsorbs = not (ForeverClassesDB.showAbsorbs ~= false)
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        if FC.UpdateHealth then FC:UpdateHealth() end
        local state = (ForeverClassesDB.showAbsorbs ~= false) and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Shield / Absorb Bar: " .. state)

    -- Absorb / Shield Diagnostics (/fc absorbdebug, /fc debugabsorb)
    elseif cmd == "absorbdebug" or cmd == "debugabsorb" then
        if FC.UpdateHealth then FC:UpdateHealth() end
        print("|cff00ccff[ForeverClasses Shield Diagnostics]|r")

        -- 1. GetAbsorbData("player") & Health Values
        local curVal = FC.HealthBar and FC.HealthBar:GetValue() or 0
        local _, maxVal = FC.HealthBar and FC.HealthBar:GetMinMaxValues() or 1
        local rawAbs, isClamped, totAbs = 0, false, 0
        if FC.GetAbsorbData then
            rawAbs, isClamped, totAbs = FC.GetAbsorbData("player")
        end
        print(string.format("  |cff00ff00FC HealthBar|r: cur=%s, max=%s", tostring(curVal), tostring(maxVal)))
        print(string.format("  |cff00ff00FC.GetAbsorbData|r: raw=%s, clamped=%s, total=%s",
            tostring(rawAbs), tostring(isClamped), tostring(totAbs)))

        -- 2. Live Event Shield & FC.AbsorbBar Status
        print(string.format("  |cff00ff00Live Shield|r: rem=%s, max=%s, spell=%s",
            tostring(FC.currentShieldRemaining), tostring(FC.currentShieldMax), tostring(FC.currentShieldSpell)))
        if FC.ResolveShieldMaxAmount then
            local resolvedPWS = FC:ResolveShieldMaxAmount(17, "power word: shield")
            print(string.format("  |cff00ff00Resolved PW:S Max|r: %s", tostring(resolvedPWS)))
        end

        if FC.AbsorbBar then
            local isShown = FC.AbsorbBar:IsShown()
            local w = FC.AbsorbBar:GetWidth() or 0
            local h = FC.AbsorbBar:GetHeight() or 0
            local val = FC.AbsorbBar.GetValue and FC.AbsorbBar:GetValue() or "n/a"
            local glowShown = FC.OverAbsorbGlow and FC.OverAbsorbGlow:IsShown() or false
            print(string.format("  |cff00ff00FC.AbsorbBar|r: shown=%s, size=%.1fx%.1f, val=%s, glow=%s, hasShield=%s",
                tostring(isShown), w, h, tostring(val), tostring(glowShown), tostring(FC.hasActiveShield)))
        else
            print("  |cff00ff00FC.AbsorbBar|r: nil")
        end

        -- 3. Native UnitGetTotalAbsorbs
        local hasNat = (UnitGetTotalAbsorbs ~= nil)
        local valNat, isSecNat = "nil", "false"
        if hasNat then
            local ok, val = pcall(UnitGetTotalAbsorbs, "player")
            if ok then
                local isSec = IsSecret(val)
                valNat = isSec and "<secret>" or tostring(val)
                isSecNat = tostring(isSec)
            else
                valNat = "error"
            end
        end
        print(string.format("  |cff00ff00UnitGetTotalAbsorbs(\"player\")|r: %s (isSecret=%s)", valNat, isSecNat))

        -- 4. Calculator & Detailed Heal Prediction
        local hasCalc = (CreateUnitHealPredictionCalculator ~= nil)
        local hasPred = (UnitGetDetailedHealPrediction ~= nil)
        print(string.format("  |cff00ff00Calculator APIs|r: CreateUnitHealPredictionCalculator=%s, UnitGetDetailedHealPrediction=%s",
            tostring(hasCalc), tostring(hasPred)))
        if FC.healCalculator and UnitGetDetailedHealPrediction then
            local okPred = pcall(UnitGetDetailedHealPrediction, "player", nil, FC.healCalculator)
            local okA, calcAbs, calcClamp = pcall(FC.healCalculator.GetDamageAbsorbs, FC.healCalculator)
            print(string.format("  |cff00ff00FC.healCalculator|r: ok=%s, abs=%s (isSec=%s), clamp=%s (isSec=%s)",
                tostring(okA), tostring(calcAbs), tostring(IsSecret(calcAbs)), tostring(calcClamp), tostring(IsSecret(calcClamp))))
        end

        -- 5. Blizzard PlayerFrame TotalAbsorbBar Direct Check
        if PlayerFrameTotalAbsorbBar then
            local pShown = PlayerFrameTotalAbsorbBar.IsShown and PlayerFrameTotalAbsorbBar:IsShown()
            local pW = PlayerFrameTotalAbsorbBar.GetWidth and PlayerFrameTotalAbsorbBar:GetWidth() or 0
            print(string.format("  |cff00ff00PlayerFrameTotalAbsorbBar|r: shown=%s, w=%.1f", tostring(pShown), pW))
        end

        -- 5. Out-of-Combat Aura Check
        if not (InCombatLockdown and InCombatLockdown()) and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local KNOWN = { { 17, "Power Word: Shield" }, { 11426, "Ice Barrier" }, { 1463, "Mana Shield" } }
            for _, entry in ipairs(KNOWN) do
                local a = C_UnitAuras.GetPlayerAuraBySpellID(entry[1])
                if a then
                    local pts = a.points and a.points[1] or "no points"
                    print(string.format("  |cff00ff00Buff Detected|r: %s (id=%d), points=%s", entry[2], entry[1], tostring(pts)))
                end
            end
        end

    -- Auto Fade toggle & opacity setting (/fc fade, /fc fade <10-80>)
    elseif cmd == "fade" or cmd == "autofade" or cmd == "ooc" then
        local targetAlphaNum = tonumber(arg1)
        if targetAlphaNum and targetAlphaNum >= 5 and targetAlphaNum <= 100 then
            ForeverClassesDB.autoFadeAlpha = math.max(0.10, math.min(0.80, targetAlphaNum / 100))
            ForeverClassesDB.autoFade = true
            if FC.RequestFadeCheck then FC:RequestFadeCheck() end
            if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
            print(string.format("|cff00ccff[ForeverClasses]|r Out-of-Combat Auto Fade: |cff44ff44Enabled|r (Resting Opacity: %d%%)", math.floor(ForeverClassesDB.autoFadeAlpha * 100)))
        else
            ForeverClassesDB.autoFade = not ForeverClassesDB.autoFade
            if not ForeverClassesDB.autoFade and FC.Frame then FC.Frame:SetAlpha(1.0) end
            if FC.RequestFadeCheck then FC:RequestFadeCheck() end
            if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
            local state = ForeverClassesDB.autoFade and string.format("|cff44ff44Enabled (%d%% Opacity)|r", math.floor((ForeverClassesDB.autoFadeAlpha or 0.35) * 100)) or "|cffff4444Disabled|r"
            print("|cff00ccff[ForeverClasses]|r Out-of-Combat Auto Fade: " .. state)
        end

    -- Test Auto Fade simulation (/fc testfade)
    elseif cmd == "testfade" or (cmd == "test" and arg1 == "fade") then
        FC.testAutoFade = true
        if FC.RequestFadeCheck then FC:RequestFadeCheck() end
        local pct = math.floor(((ForeverClassesDB and ForeverClassesDB.autoFadeAlpha) or 0.35) * 100)
        print(string.format("|cff00ccff[ForeverClasses]|r Simulating Out-of-Combat Auto Fade (%d%% opacity) for 5 seconds...", pct))
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function()
                FC.testAutoFade = nil
                if FC.RequestFadeCheck then FC:RequestFadeCheck() end
                print("|cff00ccff[ForeverClasses]|r Auto Fade simulation ended.")
            end)
        end

    -- Auto Fade debug (/fc fadedebug)
    elseif cmd == "fadedebug" or cmd == "oocdebug" then
        local reasons = {}
        local target = FC.GetTargetAutoFadeAlpha and FC:GetTargetAutoFadeAlpha(reasons) or 1.0
        local curAlpha = FC.Frame and FC.Frame:GetAlpha() or 1.0
        local isEnabled = ForeverClassesDB and ForeverClassesDB.autoFade
        local restingPct = math.floor(((ForeverClassesDB and ForeverClassesDB.autoFadeAlpha) or 0.35) * 100)
        local inCombat = ((InCombatLockdown and InCombatLockdown()) or FC.inCombat or (UnitAffectingCombat and UnitAffectingCombat("player")))

        print("|cff00ccff[ForeverClasses]|r --- Auto-Fade Diagnostics ---")
        print(string.format("  Feature Enabled: %s", isEnabled and "|cff44ff44YES|r" or "|cffff4444NO|r"))
        print(string.format("  Current Opacity: |cffffff00%d%%|r | Target Opacity: |cffffff00%d%%|r (Resting Config: %d%%)", math.floor(curAlpha * 100), math.floor(target * 100), restingPct))
        print(string.format("  In Combat: %s", inCombat and "|cffff4444YES (Combat Lockdown)|r" or "|cff44ff44NO (Out of Combat)|r"))
        print(string.format("  Target: %s", (UnitExists and UnitExists("target")) and "|cffffaa00Target Active|r" or "|cff44ff44None|r"))
        print(string.format("  Status: |cff00ffcc%s|r", #reasons > 0 and table.concat(reasons, ", ") or "Normal"))
        print("|cff00ccff[ForeverClasses]|r -----------------------------")

    -- Shield & Combat Event Log Diagnostics (/fc log or /fc copylog)
    elseif cmd == "log" or cmd == "logs" or cmd == "copylog" or cmd == "debuglog" or cmd == "shieldlog" then
        if FC.ShowLogDialog then
            FC:ShowLogDialog()
        else
            print("|cffff4444[ForeverClasses]|r Log dialog is not available.")
        end

    elseif cmd == "logchat" then
        FC.shieldLogChat = not FC.shieldLogChat
        print("|cff00ccff[ForeverClasses]|r Live combat & cooldown debug logs to chat: " .. (FC.shieldLogChat and "|cff00ff00ENABLED|r" or "|cffff4444DISABLED|r"))

    elseif cmd == "clearlog" or cmd == "clearlogs" then
        FC.shieldLogs = {}
        if FC.LogCopyFrame and FC.LogCopyFrame.editBox then
            FC.LogCopyFrame.editBox:SetText("")
        end
        print("|cff00ccff[ForeverClasses]|r Combat & cooldown debug logs cleared.")

    -- Help fallback
    else
        print("|cff00ccff[ForeverClasses]|r Available Commands:")
        print("  |cff00ff00/fc|r or |cff00ff00/fc config|r - Open settings window")
        print("  |cff00ff00/fc both|r (or |cff00ff00/fc-both|r) - Show numbers & percentage")
        print("  |cff00ff00/fc num|r (or |cff00ff00/fc-num|r) - Show numbers only")
        print("  |cff00ff00/fc pct|r (or |cff00ff00/fc-pct|r) - Show percentage only")
        print("  |cff00ff00/fc sync|r (or |cff00ff00/fc-sync|r) - Sync with game settings")
        print("  |cff00ff00/fc none|r (or |cff00ff00/fc-none|r) - Hide text")
        print("  |cff00ff00/fc lock|r (or |cff00ff00/fc-lock|r) - Lock panel in place")
        print("  |cff00ff00/fc unlock|r (or |cff00ff00/fc-unlock|r) - Unlock panel (drag freely)")
        print("  |cff00ff00/fc icon|r (or |cff00ff00/fc-icon|r) - Toggle minimap button")
        print("  |cff00ff00/fc classcolor|r (or |cff00ff00/fc-classcolor|r) - Toggle class-colored health bar")
        print("  |cff00ff00/fc lowhealth|r (or |cff00ff00/fc-low|r) - Toggle low health warning (<= 33% HP)")
        print("  |cff00ff00/fc threshold <%>|r - Set low health trigger % (e.g. /fc threshold 33)")
        print("  |cff00ff00/fc testlow|r (or |cff00ff00/fc-testlow|r) - Test low health warning for 6s")
        print("  |cff00ff00/fc debuffs|r (or |cff00ff00/fc-debuffs|r) - Toggle debuff icons on right of bar")
        print("  |cff00ff00/fc testdebuff|r (or |cff00ff00/fc-testdebuff|r) - Simulate debuff icons for 8s")
        print("  |cff00ff00/fc debuffdebug|r (or |cff00ff00/fc-debuffdebug|r) - Diagnose live aura detection APIs")
        print("  |cff00ff00/fc ignore <name>|r - Exclude an exhaustion / non-combat debuff")
        print("  |cff00ff00/fc unignore <name>|r - Remove debuff from exclusion list")
        print("  |cff00ff00/fc cp|r (or |cff00ff00/fc-cp|r) - Toggle Rogue combo points")
        print("  |cff00ff00/fc testcp|r (or |cff00ff00/fc-testcp|r) - Test combo points animation (1-5 CP)")
        print("  |cff00ff00/fc cd|r (or |cff00ff00/fc-cds|r) - Toggle ability/cooldown bar above health")
        print("  |cff00ff00/fc testcd|r (or |cff00ff00/fc-testcd|r) - Simulate 7 cooldown states for 8s")
        print("  |cff00ff00/fc listcds|r - Show abilities assigned to slots 1-7")
        print("  |cff00ff00/fc cd <slot> <spell>|r - Assign ability to slot (e.g. /fc cd 1 Kick)")
        print("  |cff00ff00/fc clearcd <slot>|r - Clear slot 1-7 (or Shift-Right-Click on icon)")
        print("  |cff00ff00/fc cddebug|r (or |cff00ff00/fc-cddebug|r) - Diagnose live cooldown detection APIs")
        print("  |cff00ff00/fc ss [0-2]|r - Check or set Improved Stormstrike rank (Shaman)")
        print("  |cff00ff00/fc totems|r (or |cff00ff00/fc-totems|r) - Toggle Shaman totem bar below panel")
        print("  |cff00ff00/fc testtotem|r (or |cff00ff00/fc-testtotem|r) - Simulate 4 active totems for 10s")
        print("  |cff00ff00/fc absorb|r (or |cff00ff00/fc-absorb|r) - Toggle shield / absorb bar on health bar")
        print("  |cff00ff00/fc testabsorb|r (or |cff00ff00/fc-testabsorb|r) - Simulate absorb shields & overshield glow")
        print("  |cff00ff00/fc absorbdebug|r (or |cff00ff00/fc-absorbdebug|r) - Diagnose live shield & absorb detection APIs")
        print("  |cff00ff00/fc log|r (or |cff00ff00/fc copylog|r) - Open combat, buffs & cooldown debug log window")
        print("  |cff00ff00/fc logchat|r - Toggle printing combat & cooldown logs directly to chat")
        print("  |cff00ff00/fc clearlog|r - Clear all recorded debug logs")
        print("  |cff00ff00/fc heals|r (or |cff00ff00/fc-heals|r) - Toggle upcoming heals")
        print("  |cff00ff00/fc testheal|r (or |cff00ff00/fc-testheal|r) - Simulate incoming heal for 5s")
        print("  |cff00ff00/fc pulse|r (or |cff00ff00/fc-pulse|r) - Toggle cooldown ready flash")
        print("  |cff00ff00/fc testpulse|r (or |cff00ff00/fc-testpulse|r) - Test ready flash wave")
        print("  |cff00ff00/fc fade|r (or |cff00ff00/fc-fade|r) - Toggle out-of-combat auto fade (or /fc fade 35)")
        print("  |cff00ff00/fc testfade|r (or |cff00ff00/fc-testfade|r) - Simulate auto fade for 5s")
        print("  |cff00ff00/fc fadedebug|r (or |cff00ff00/fc-fadedebug|r) - Diagnose auto fade status & blockers")
        print("  |cff00ff00/fc reset|r (or |cff00ff00/fc-reset|r) - Reset position to center")
        print("  |cff00ff00/fc errors|r (or |cff00ff00/fc-errors|r) - Toggle Lua error dialogs")
        print("  |cff00ff00/fc debug|r - Show debug info")
    end
end

-- Primary slash commands
SLASH_FOREVERCLASSES1 = "/fc"
SLASH_FOREVERCLASSES2 = "/foreverclasses"
SLASH_FOREVERCLASSES3 = "/forever"
SlashCmdList["FOREVERCLASSES"] = HandleSlashCommands

-- Hyphenated standalone commands (/fc-both, /fc-lock, etc.)
local HYPHEN_COMMANDS = {
    ["fc-fade"] = function()
        ForeverClassesDB.autoFade = not ForeverClassesDB.autoFade
        if not ForeverClassesDB.autoFade and FC.Frame then FC.Frame:SetAlpha(1.0) end
        if FC.RequestFadeCheck then FC:RequestFadeCheck() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.autoFade and string.format("|cff44ff44Enabled (%d%% Opacity)|r", math.floor((ForeverClassesDB.autoFadeAlpha or 0.35) * 100)) or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Out-of-Combat Auto Fade: " .. state)
    end,
    ["fc-fadedebug"] = function()
        local reasons = {}
        local target = FC.GetTargetAutoFadeAlpha and FC:GetTargetAutoFadeAlpha(reasons) or 1.0
        local curAlpha = FC.Frame and FC.Frame:GetAlpha() or 1.0
        local isEnabled = ForeverClassesDB and ForeverClassesDB.autoFade
        local restingPct = math.floor(((ForeverClassesDB and ForeverClassesDB.autoFadeAlpha) or 0.35) * 100)
        local inCombat = ((InCombatLockdown and InCombatLockdown()) or FC.inCombat or (UnitAffectingCombat and UnitAffectingCombat("player")))

        print("|cff00ccff[ForeverClasses]|r --- Auto-Fade Diagnostics ---")
        print(string.format("  Feature Enabled: %s", isEnabled and "|cff44ff44YES|r" or "|cffff4444NO|r"))
        print(string.format("  Current Opacity: |cffffff00%d%%|r | Target Opacity: |cffffff00%d%%|r (Resting Config: %d%%)", math.floor(curAlpha * 100), math.floor(target * 100), restingPct))
        print(string.format("  In Combat: %s", inCombat and "|cffff4444YES (Combat Lockdown)|r" or "|cff44ff44NO (Out of Combat)|r"))
        print(string.format("  Target: %s", (UnitExists and UnitExists("target")) and "|cffffaa00Target Active|r" or "|cff44ff44None|r"))
        print(string.format("  Status: |cff00ffcc%s|r", #reasons > 0 and table.concat(reasons, ", ") or "Normal"))
        print("|cff00ccff[ForeverClasses]|r -----------------------------")
    end,
    ["fc-testfade"] = function()
        FC.testAutoFade = true
        if FC.RequestFadeCheck then FC:RequestFadeCheck() end
        local pct = math.floor(((ForeverClassesDB and ForeverClassesDB.autoFadeAlpha) or 0.35) * 100)
        print(string.format("|cff00ccff[ForeverClasses]|r Simulating Out-of-Combat Auto Fade (%d%% opacity) for 5 seconds...", pct))
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function()
                FC.testAutoFade = nil
                if FC.RequestFadeCheck then FC:RequestFadeCheck() end
                print("|cff00ccff[ForeverClasses]|r Auto Fade simulation ended.")
            end)
        end
    end,
    ["fc-pulse"] = function()
        if ForeverClassesDB.cooldownPulse == nil then
            ForeverClassesDB.cooldownPulse = true
        end
        ForeverClassesDB.cooldownPulse = not ForeverClassesDB.cooldownPulse
        local st = ForeverClassesDB.cooldownPulse and "|cff00ff00ENABLED|r" or "|cffff4444DISABLED|r"
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Cooldown Ready Pulse: " .. st)
    end,
    ["fc-testpulse"] = function()
        if FC.CooldownBar and FC.CooldownBar.slots then
            local count = ForeverClassesDB.cooldownSlotCount or 7
            for i = 1, count do
                local b = FC.CooldownBar.slots[i]
                if b and b:IsShown() and FC.PlayCooldownReadyPulse then
                    if C_Timer and C_Timer.After then
                        C_Timer.After((i - 1) * 0.08, function()
                            FC:PlayCooldownReadyPulse(b)
                        end)
                    else
                        FC:PlayCooldownReadyPulse(b)
                    end
                end
            end
            print("|cff00ccff[ForeverClasses]|r Testing Cooldown Ready Pulse animation...")
        end
    end,
    ["fc-gc"] = function()
        if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
            UpdateAddOnMemoryUsage()
            local before = GetAddOnMemoryUsage("ForeverClasses") or 0
            collectgarbage("collect")
            UpdateAddOnMemoryUsage()
            local after = GetAddOnMemoryUsage("ForeverClasses") or 0
            print(string.format("|cff00ccff[ForeverClasses]|r Memory cleaned: |cffff5555%.2f MB|r -> |cff00ff00%.2f MB|r (Freed: %.2f MB)", before / 1024, after / 1024, (before - after) / 1024))
        else
            collectgarbage("collect")
            print("|cff00ccff[ForeverClasses]|r Garbage collection executed.")
        end
    end,
    ["fc-both"] = function()
        ForeverClassesDB.textMode = "BOTH"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Text display set to: |cff00ff00BOTH|r")
    end,
    ["fc-num"] = function()
        ForeverClassesDB.textMode = "NUMERIC"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Text display set to: |cff00ff00NUMERIC|r")
    end,
    ["fc-pct"] = function()
        ForeverClassesDB.textMode = "PERCENT"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Text display set to: |cff00ff00PERCENT|r")
    end,
    ["fc-percent"] = function()
        ForeverClassesDB.textMode = "PERCENT"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Text display set to: |cff00ff00PERCENT|r")
    end,
    ["fc-sync"] = function()
        ForeverClassesDB.textMode = "SYNC"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Text display set to: |cff00ff00SYNC|r")
    end,
    ["fc-none"] = function()
        ForeverClassesDB.textMode = "NONE"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Text display set to: |cff00ff00NONE|r")
    end,
    ["fc-hide"] = function()
        ForeverClassesDB.textMode = "NONE"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Text display set to: |cff00ff00NONE|r")
    end,
    ["fc-lock"] = function()
        ForeverClassesDB.movementMode = "LOCKED"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Panel is now |cffff4444LOCKED|r.")
    end,
    ["fc-unlock"] = function()
        ForeverClassesDB.movementMode = "FREE"
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        print("|cff00ccff[ForeverClasses]|r Panel is now |cff44ff44UNLOCKED (Free Move)|r.")
    end,
    ["fc-heals"] = function()
        ForeverClassesDB.showIncomingHeals = not ForeverClassesDB.showIncomingHeals
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.showIncomingHeals and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Upcoming Heals prediction: " .. state)
    end,
    ["fc-testheal"] = function()
        local maxH = 1000
        pcall(function()
            local mh = UnitHealthMax("player")
            if mh and not IsSecret(mh) and mh > 0 then
                maxH = mh
            end
        end)
        FC.testIncomingHeal = math.floor(maxH * 0.35)
        print("|cff00ccff[ForeverClasses]|r Simulating incoming heal (" .. FC.testIncomingHeal .. " HP) on wounded bar for 5 seconds...")
        print("|cff00ccff[ForeverClasses]|r Note: Incoming heals fill missing health up to 100%.")
        if FC.UpdateHealth then FC:UpdateHealth() end
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function()
                FC.testIncomingHeal = nil
                if FC.UpdateHealth then FC:UpdateHealth() end
                print("|cff00ccff[ForeverClasses]|r Test incoming heal ended.")
            end)
        end
    end,
    ["fc-reset"] = function()
        ForeverClassesDB.point = FC.Defaults.point
        ForeverClassesDB.relativePoint = FC.Defaults.relativePoint
        ForeverClassesDB.x = FC.Defaults.x
        ForeverClassesDB.y = FC.Defaults.y
        if FC.ApplyConfig then FC:ApplyConfig() end
        print("|cff00ccff[ForeverClasses]|r Position reset to center.")
    end,
    ["fc-errors"] = function()
        local current = GetCVar and GetCVar("scriptErrors")
        local newVal = (current == "1") and "0" or "1"
        if SetCVar then
            SetCVar("scriptErrors", newVal)
        end
        print("|cff00ccff[ForeverClasses]|r Lua scriptErrors is now: |cff00ff00" .. newVal .. "|r (1 = show error dialogs, 0 = hide)")
    end,
    ["fc-debug"] = function()
        local pType, pToken
        pcall(function() pType, pToken = UnitPowerType("player") end)
        local _, class = UnitClass("player")
        local r, g, b = FC:GetPowerColor()
        local isSecH = issecretvalue and issecretvalue(UnitHealth("player"))
        local isSecP = false
        pcall(function() isSecP = issecretvalue and issecretvalue(UnitPower("player", pType or 0)) end)
        print(string.format("|cff00ccff[ForeverClasses Debug]|r Class: %s, PowerType: %s, Token: %s, Color: (%.2f, %.2f, %.2f), SecretHealth: %s, SecretPower: %s",
            tostring(class), tostring(pType), tostring(pToken), r, g, b, tostring(isSecH), tostring(isSecP)))
    end,
    ["fc-config"] = function()
        local win = FC:CreateConfigWindow()
        if win:IsShown() then win:Hide() else win:Show() end
    end,
    ["fc-icon"] = function()
        ForeverClassesDB.showMinimapIcon = true
        if FC.UpdateMinimapVisibility then FC:UpdateMinimapVisibility() end
        print("|cff00ccff[ForeverClasses]|r Minimap button is permanently enabled.")
    end,
    ["fc-minimap"] = function()
        ForeverClassesDB.showMinimapIcon = true
        if FC.UpdateMinimapVisibility then FC:UpdateMinimapVisibility() end
        print("|cff00ccff[ForeverClasses]|r Minimap button is permanently enabled.")
    end,
    ["fc-classcolor"] = function()
        ForeverClassesDB.classColorHealth = not ForeverClassesDB.classColorHealth
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.classColorHealth and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Class-colored health bar: " .. state)
    end,
    ["fc-classhealth"] = function()
        ForeverClassesDB.classColorHealth = not ForeverClassesDB.classColorHealth
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.classColorHealth and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Class-colored health bar: " .. state)
    end,
    ["fc-class"] = function()
        ForeverClassesDB.classColorHealth = not ForeverClassesDB.classColorHealth
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.classColorHealth and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Class-colored health bar: " .. state)
    end,
    ["fc-lowhealth"] = function()
        ForeverClassesDB.lowHealthWarning = not ForeverClassesDB.lowHealthWarning
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.lowHealthWarning and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Low health warning flash: " .. state)
    end,
    ["fc-low"] = function()
        ForeverClassesDB.lowHealthWarning = not ForeverClassesDB.lowHealthWarning
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.lowHealthWarning and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Low health warning flash: " .. state)
    end,
    ["fc-testlow"] = function()
        print("|cff00ccff[ForeverClasses]|r Testing Low Health Warning Flash (simulating 18% HP for 6s)...")
        FC.testLowHealth = true
        if FC.UpdateHealth then FC:UpdateHealth() end
        if C_Timer and C_Timer.After then
            C_Timer.After(6, function()
                FC.testLowHealth = nil
                if FC.UpdateHealth then FC:UpdateHealth() end
                print("|cff00ccff[ForeverClasses]|r Low Health Warning test ended.")
            end)
        end
    end,
    ["fc-threshold"] = function()
        print("|cff00ccff[ForeverClasses]|r Current low health threshold: " .. tostring(ForeverClassesDB.lowHealthThreshold or 33) .. "% (Change via: /fc threshold 33)")
    end,
    ["fc-debuff"] = function()
        ForeverClassesDB.showDebuffs = not ForeverClassesDB.showDebuffs
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.showDebuffs and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Harmful Debuff icons display: " .. state)
    end,
    ["fc-debuffs"] = function()
        ForeverClassesDB.showDebuffs = not ForeverClassesDB.showDebuffs
        if FC.ApplyConfig then FC:ApplyConfig() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.showDebuffs and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Harmful Debuff icons display: " .. state)
    end,
    ["fc-testdebuff"] = function()
        print("|cff00ccff[ForeverClasses]|r Simulating Harmful Debuff Icons (Deadly Poison, Rend, Curse of Agony) on right of bar for 8 seconds...")
        FC.testDebuffsActive = true
        if FC.UpdateDebuffs then FC:UpdateDebuffs() end
        if C_Timer and C_Timer.After then
            C_Timer.After(8, function()
                FC.testDebuffsActive = nil
                if FC.UpdateDebuffs then FC:UpdateDebuffs() end
                print("|cff00ccff[ForeverClasses]|r Debuff icons test ended.")
            end)
        end
    end,
    ["fc-debuffdebug"] = function()
        if FC.RunDebuffDebug then
            FC:RunDebuffDebug()
        end
    end,
    ["fc-ignore"] = function()
        SlashCmdList["FOREVERCLASSES"]("ignore")
    end,
    ["fc-cp"] = function()
        local _, classToken = UnitClass("player")
        if classToken ~= "ROGUE" and classToken ~= "DRUID" then
            print("|cff00ccff[ForeverClasses]|r Combo Points are only available for Rogue and Druid.")
            return
        end
        ForeverClassesDB.showComboPoints = not ForeverClassesDB.showComboPoints
        if FC.UpdateComboPoints then FC:UpdateComboPoints() end
        if FC.ConfigWindow and FC.ConfigWindow.Refresh then FC.ConfigWindow:Refresh() end
        local state = ForeverClassesDB.showComboPoints and "|cff44ff44Enabled|r" or "|cffff4444Disabled|r"
        print("|cff00ccff[ForeverClasses]|r Combo Points display: " .. state)
    end,
    ["fc-testcp"] = function()
        local _, classToken = UnitClass("player")
        if classToken ~= "ROGUE" and classToken ~= "DRUID" then
            print("|cff00ccff[ForeverClasses]|r Combo Points are only available for Rogue and Druid.")
            return
        end
        print("|cff00ccff[ForeverClasses]|r Testing Combo Points sequence (1 to 5 CP)...")
        print("|cff00ccff[ForeverClasses]|r Note: In normal gameplay, this bar appears beneath the panel only while in combat.")
        FC.testComboPoints = 1
        if FC.UpdateComboPoints then FC:UpdateComboPoints() end

        local step = 1
        local function RunStep()
            step = step + 1
            if step <= 5 then
                FC.testComboPoints = step
                if FC.UpdateComboPoints then FC:UpdateComboPoints() end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.9, RunStep)
                end
            else
                if C_Timer and C_Timer.After then
                    C_Timer.After(2.5, function()
                        FC.testComboPoints = nil
                        if FC.UpdateComboPoints then FC:UpdateComboPoints() end
                        print("|cff00ccff[ForeverClasses]|r Combo Points test ended.")
                    end)
                end
            end
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0.9, RunStep)
        end
    end,
    ["fc-cd"] = function()
        SlashCmdList["FOREVERCLASSES"]("cd")
    end,
    ["fc-cds"] = function()
        SlashCmdList["FOREVERCLASSES"]("cds")
    end,
    ["fc-testcd"] = function()
        SlashCmdList["FOREVERCLASSES"]("testcd")
    end,
    ["fc-listcd"] = function()
        SlashCmdList["FOREVERCLASSES"]("listcds")
    end,
    ["fc-listcds"] = function()
        SlashCmdList["FOREVERCLASSES"]("listcds")
    end,
    ["fc-cddebug"] = function()
        SlashCmdList["FOREVERCLASSES"]("cddebug")
    end,
    ["fc-totem"] = function()
        SlashCmdList["FOREVERCLASSES"]("totems")
    end,
    ["fc-totems"] = function()
        SlashCmdList["FOREVERCLASSES"]("totems")
    end,
    ["fc-testtotem"] = function()
        SlashCmdList["FOREVERCLASSES"]("testtotem")
    end,
    ["fc-testtotems"] = function()
        SlashCmdList["FOREVERCLASSES"]("testtotem")
    end,
    ["fc-absorb"] = function()
        SlashCmdList["FOREVERCLASSES"]("absorb")
    end,
    ["fc-shield"] = function()
        SlashCmdList["FOREVERCLASSES"]("absorb")
    end,
    ["fc-testabsorb"] = function()
        SlashCmdList["FOREVERCLASSES"]("testabsorb")
    end,
    ["fc-testshield"] = function()
        SlashCmdList["FOREVERCLASSES"]("testabsorb")
    end,
    ["fc-absorbdebug"] = function()
        SlashCmdList["FOREVERCLASSES"]("absorbdebug")
    end,
    ["fc-debugabsorb"] = function()
        SlashCmdList["FOREVERCLASSES"]("absorbdebug")
    end,
}

for name, handler in pairs(HYPHEN_COMMANDS) do
    local tag = string.upper(name):gsub("%-", "_")
    _G["SLASH_" .. tag .. "1"] = "/" .. name
    SlashCmdList[tag] = handler
end
