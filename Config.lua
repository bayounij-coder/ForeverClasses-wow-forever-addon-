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
-- Options GUI Window (Modern Obsidian Midnight 12.0 Redesign)
-- ============================================================================

local BackdropTemplateString = BackdropTemplateMixin and "BackdropTemplate" or nil

local function HasClassSupport(classToken)
    return (classToken == "SHAMAN" or classToken == "ROGUE" or classToken == "DRUID")
end

local function ApplyWHITE8X8Backdrop(frame, bgR, bgG, bgB, bgA, edgeR, edgeG, edgeB, edgeA, edgeSize)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = edgeSize or 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(bgR or 0.08, bgG or 0.09, bgB or 0.12, bgA or 0.95)
    frame:SetBackdropBorderColor(edgeR or 0.18, edgeG or 0.20, edgeB or 0.26, edgeA or 0.8)
end

-- Backward-compatible checkbox helper
local function CreateCheckbox(parent, labelText, getFunc, setFunc, settingKey)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)

    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    cb.text:SetText(labelText)

    cb:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked() and true or false
        PlaySound((SOUNDKIT and SOUNDKIT.IG_MAINOPTION_CHECKBOX_ON) or 856)
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

    local _, playerClass = UnitClass("player")
    playerClass = playerClass or "WARRIOR"
    local hasClassSupport = HasClassSupport(playerClass)

    -- Main Window Shell (Modern Midnight Obsidian Dashboard: 640x620)
    local f = CreateFrame("Frame", "ForeverClassesConfigFrame", UIParent, BackdropTemplateString)
    f:SetSize(640, 620)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    -- Obsidian Deep Background with subtle Gold Trim Border
    ApplyWHITE8X8Backdrop(f, 0.045, 0.048, 0.063, 0.98, 0.78, 0.61, 0.24, 0.35, 1)

    table.insert(UISpecialFrames, "ForeverClassesConfigFrame")

    -- ========================================================================
    -- Window Header
    -- ========================================================================
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -10)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -10)
    header:SetHeight(32)

    -- Emblem Icon (Player Class Crest or FC Monogram)
    local emblem = header:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(26, 26)
    emblem:SetPoint("LEFT", header, "LEFT", 0, 0)
    local coords = CLASS_ICON_TCOORDS and playerClass and CLASS_ICON_TCOORDS[playerClass]
    if coords then
        emblem:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        emblem:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        emblem:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    titleText:SetPoint("LEFT", emblem, "RIGHT", 10, 5)
    titleText:SetText("|cff00ccffForeverClasses|r |cffffaa00(Beta)|r Settings")

    local subtitleText = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitleText:SetPoint("LEFT", emblem, "RIGHT", 10, -8)
    subtitleText:SetText("Next-Gen Modern Midnight 12.0 Settings Interface")

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINOPTION_CLOSE or 857)
        f:Hide()
    end)

    -- ========================================================================
    -- TOP SECTION: Live In-Game HUD Preview Sandbox
    -- ========================================================================
    local previewSandbox = CreateFrame("Frame", nil, f, BackdropTemplateString)
    previewSandbox:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -46)
    previewSandbox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -46)
    previewSandbox:SetHeight(138)
    ApplyWHITE8X8Backdrop(previewSandbox, 0.032, 0.036, 0.048, 0.95, 0.12, 0.14, 0.18, 1.0, 1)

    -- Main HUD Cluster Center Anchor
    local hudCluster = CreateFrame("Frame", nil, previewSandbox)
    hudCluster:SetSize(240, 84)
    hudCluster:SetPoint("CENTER", previewSandbox, "CENTER", 0, -2)

    -- 1. Docked Ability Slots (Above Health Bar)
    local previewSlotsDock = CreateFrame("Frame", nil, hudCluster)
    previewSlotsDock:SetHeight(20)
    previewSlotsDock:SetPoint("BOTTOM", hudCluster, "TOP", 0, -20)

    local previewSlotBtns = {}
    for i = 1, 7 do
        local slot = CreateFrame("Frame", nil, previewSlotsDock, BackdropTemplateString)
        slot:SetSize(20, 20)
        slot:SetPoint("LEFT", previewSlotsDock, "LEFT", (i - 1) * 23, 0)
        ApplyWHITE8X8Backdrop(slot, 0.12, 0.14, 0.18, 0.95, 0.24, 0.28, 0.36, 0.8, 1)

        local slotNum = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slotNum:SetPoint("CENTER", slot, "CENTER", 0, 0)
        slotNum:SetText(tostring(i))
        slotNum:SetTextColor(0.6, 0.65, 0.75, 1)

        previewSlotBtns[i] = slot
    end

    -- 2. Health Bar Container
    local previewHealthContainer = CreateFrame("Frame", nil, hudCluster, BackdropTemplateString)
    previewHealthContainer:SetSize(240, 22)
    previewHealthContainer:SetPoint("TOPLEFT", hudCluster, "TOPLEFT", 0, -24)
    ApplyWHITE8X8Backdrop(previewHealthContainer, 0.02, 0.02, 0.02, 0.9, 0.18, 0.20, 0.26, 0.8, 1)

    -- Health Fill
    local previewHealthFill = previewHealthContainer:CreateTexture(nil, "BORDER")
    previewHealthFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    previewHealthFill:SetPoint("TOPLEFT", previewHealthContainer, "TOPLEFT", 1, -1)
    previewHealthFill:SetPoint("BOTTOMLEFT", previewHealthContainer, "BOTTOMLEFT", 1, 1)
    previewHealthFill:SetWidth(238 * 0.78)
    previewHealthFill:SetVertexColor(0.10, 0.75, 0.40, 1.0)

    -- Upcoming Heals Prediction Fill
    local previewHealFill = previewHealthContainer:CreateTexture(nil, "ARTWORK")
    previewHealFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    previewHealFill:SetPoint("TOPLEFT", previewHealthFill, "TOPRIGHT", 0, 0)
    previewHealFill:SetPoint("BOTTOMLEFT", previewHealthFill, "BOTTOMRIGHT", 0, 0)
    previewHealFill:SetWidth(238 * 0.14)
    previewHealFill:SetVertexColor(0.30, 0.85, 0.55, 0.45)

    -- Health Text
    local previewHealthText = previewHealthContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewHealthText:SetPoint("CENTER", previewHealthContainer, "CENTER", 0, 0)
    previewHealthText:SetText("2,145 / 2,750 (78%)")
    previewHealthText:SetShadowColor(0, 0, 0, 0.9)
    previewHealthText:SetShadowOffset(1, -1)

    -- 3. Power Bar Container
    local previewPowerContainer = CreateFrame("Frame", nil, hudCluster, BackdropTemplateString)
    previewPowerContainer:SetSize(240, 12)
    previewPowerContainer:SetPoint("TOPLEFT", previewHealthContainer, "BOTTOMLEFT", 0, -1)
    ApplyWHITE8X8Backdrop(previewPowerContainer, 0.02, 0.02, 0.02, 0.95, 0.14, 0.16, 0.20, 0.9, 1)

    local previewPowerFill = previewPowerContainer:CreateTexture(nil, "BORDER")
    previewPowerFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    previewPowerFill:SetPoint("TOPLEFT", previewPowerContainer, "TOPLEFT", 1, -1)
    previewPowerFill:SetPoint("BOTTOMLEFT", previewPowerContainer, "BOTTOMLEFT", 1, 1)
    previewPowerFill:SetWidth(238 * 0.85)
    previewPowerFill:SetVertexColor(0.15, 0.45, 0.95, 1.0)

    local previewPowerText = previewPowerContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewPowerText:SetPoint("CENTER", previewPowerContainer, "CENTER", 0, 0)
    previewPowerText:SetText("3,320 / 3,900 (85%)")
    previewPowerText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    previewPowerText:SetShadowColor(0, 0, 0, 0.9)
    previewPowerText:SetShadowOffset(1, -1)

    -- 4. Class Sub-Bars Container (Docked below Power Bar)
    local previewSubBar = CreateFrame("Frame", nil, hudCluster)
    previewSubBar:SetSize(240, 24)
    previewSubBar:SetPoint("TOP", previewPowerContainer, "BOTTOM", 0, -4)

    -- Shaman Totem Bar Preview (Real Blizzard Icons & Totem Borders)
    local previewTotemBar = CreateFrame("Frame", nil, previewSubBar)
    previewTotemBar:SetSize(220, 24)
    previewTotemBar:SetPoint("CENTER", previewSubBar, "CENTER", 0, 0)

    local TOTEM_PREVIEW_DATA = {
        { name = "Earth", fileID = 136098, path = "Interface\\Icons\\Spell_Nature_EarthBindTotem", time = "14m", r = 0.55, g = 0.35, b = 0.17 },
        { name = "Fire",  fileID = 135824, path = "Interface\\Icons\\Spell_Fire_SearingTotem",     time = "1m 45s", r = 1.0, g = 0.27, b = 0.0 },
        { name = "Water", fileID = 136053, path = "Interface\\Icons\\Spell_Nature_ManaRegenTotem", time = "42s", r = 0.0, g = 0.75, b = 1.0 },
        { name = "Air",   fileID = 136018, path = "Interface\\Icons\\Spell_Nature_Windfury",       time = "28s", r = 0.13, g = 0.70, b = 0.67 },
    }

    local previewTotemBtns = {}
    for i, tData in ipairs(TOTEM_PREVIEW_DATA) do
        local btn = CreateFrame("Frame", nil, previewTotemBar, BackdropTemplateString)
        btn:SetSize(50, 22)
        btn:SetPoint("LEFT", previewTotemBar, "LEFT", (i - 1) * 55, 0)
        ApplyWHITE8X8Backdrop(btn, 0.08, 0.09, 0.12, 0.9, tData.r, tData.g, tData.b, 0.6, 1)

        local dot = btn:CreateTexture(nil, "OVERLAY")
        dot:SetSize(6, 6)
        dot:SetPoint("LEFT", btn, "LEFT", 5, 0)
        dot:SetTexture("Interface\\Buttons\\WHITE8X8")
        dot:SetVertexColor(tData.r, tData.g, tData.b, 1)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", dot, "RIGHT", 3, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if not pcall(icon.SetTexture, icon, tData.fileID) or not icon:GetTexture() then
            icon:SetTexture(tData.path)
        end

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        lbl:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        lbl:SetText(tData.time)
        lbl:SetTextColor(1, 1, 1, 1)

        previewTotemBtns[i] = btn
    end

    -- Rogue / Druid Combo Points Preview (Real Blizzard Atlases)
    local previewCPBar = CreateFrame("Frame", nil, previewSubBar)
    previewCPBar:SetSize(100, 18)
    previewCPBar:SetPoint("CENTER", previewSubBar, "CENTER", 0, 0)

    local previewCPPips = {}
    for i = 1, 5 do
        local pip = CreateFrame("Frame", nil, previewCPBar)
        pip:SetSize(16, 16)
        pip:SetPoint("LEFT", previewCPBar, "LEFT", (i - 1) * 20, 0)

        local bg = pip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(pip)
        local fill = pip:CreateTexture(nil, "OVERLAY")
        fill:SetAllPoints(pip)

        if FC.resolvedComboBgAtlas and FC.resolvedComboFillAtlas then
            pcall(bg.SetAtlas, bg, FC.resolvedComboBgAtlas, false)
            pcall(fill.SetAtlas, fill, FC.resolvedComboFillAtlas, false)
        elseif C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("ComboPoints-ComboPoint") then
            pcall(bg.SetAtlas, bg, "ComboPoints-PointBg", false)
            pcall(fill.SetAtlas, fill, "ComboPoints-ComboPoint", false)
        else
            bg:SetTexture("Interface\\ComboFrame\\ComboPoint")
            bg:SetTexCoord(0, 0.5, 0, 1)
            fill:SetTexture("Interface\\ComboFrame\\ComboPoint")
            fill:SetTexCoord(0.5, 1, 0, 1)
        end

        -- 3 Active filled pips, 2 empty pips
        if i <= 3 then
            fill:Show()
        else
            fill:Hide()
        end
        previewCPPips[i] = pip
    end

    -- Preview Update Engine
    local function UpdateHUDPreview()
        local isClassColor = ForeverClassesDB.classColorHealth and true or false
        local showHeals = ForeverClassesDB.showIncomingHeals and true or false
        local showTotems = ForeverClassesDB.showTotems and true or false
        local showCP = ForeverClassesDB.showComboPoints and true or false
        local textMode = ForeverClassesDB.textMode or "BOTH"
        local slotCount = ForeverClassesDB.cooldownSlotCount
        if slotCount == nil then
            slotCount = (ForeverClassesDB.showCooldowns == false) and 0 or 7
        end

        -- 1. Slots Dock
        if slotCount == 0 then
            previewSlotsDock:Hide()
        else
            previewSlotsDock:Show()
            for i = 1, 7 do
                if i <= slotCount then
                    previewSlotBtns[i]:Show()
                else
                    previewSlotBtns[i]:Hide()
                end
            end
            local totalW = (slotCount * 20) + ((slotCount - 1) * 3)
            previewSlotsDock:SetWidth(math.max(20, totalW))
        end

        -- 2. Health Bar Color
        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[playerClass]
        if isClassColor and classColor then
            previewHealthFill:SetVertexColor(classColor.r, classColor.g, classColor.b, 1.0)
            previewHealFill:SetVertexColor(classColor.r, classColor.g, classColor.b, 0.45)
        else
            previewHealthFill:SetVertexColor(0.10, 0.75, 0.40, 1.0)
            previewHealFill:SetVertexColor(0.30, 0.85, 0.55, 0.45)
        end

        -- 3. Upcoming Heals Positioning
        if showHeals then
            previewHealFill:Show()
            previewHealFill:ClearAllPoints()
            previewHealFill:SetPoint("TOPLEFT", previewHealthFill, "TOPRIGHT", 0, 0)
            previewHealFill:SetPoint("BOTTOMLEFT", previewHealthFill, "BOTTOMRIGHT", 0, 0)
            previewHealFill:SetWidth(238 * 0.14)
        else
            previewHealFill:Hide()
        end

        -- 4. Status Text: Health Bar
        if textMode == "BOTH" then
            previewHealthText:SetText("2,145 / 2,750 (78%)")
        elseif textMode == "NUMERIC" then
            previewHealthText:SetText("2,145 / 2,750")
        elseif textMode == "PERCENT" then
            previewHealthText:SetText("78%")
        elseif textMode == "SYNC" then
            previewHealthText:SetText("2,145 (78%)")
        else
            previewHealthText:SetText("")
        end

        -- 5. Power Bar Color, Width & Text
        if playerClass == "SHAMAN" then
            previewPowerFill:SetVertexColor(0.15, 0.45, 0.95, 1.0)
            previewPowerFill:SetWidth(238 * 0.85)
            if textMode == "BOTH" then previewPowerText:SetText("3,320 / 3,900 (85%)")
            elseif textMode == "NUMERIC" then previewPowerText:SetText("3,320 / 3,900")
            elseif textMode == "PERCENT" then previewPowerText:SetText("85%")
            elseif textMode == "SYNC" then previewPowerText:SetText("3,320 (85%)")
            else previewPowerText:SetText("") end
        elseif playerClass == "ROGUE" then
            previewPowerFill:SetVertexColor(0.95, 0.85, 0.10, 1.0)
            previewPowerFill:SetWidth(238 * 0.85)
            if textMode == "BOTH" then previewPowerText:SetText("85 / 100 (85%)")
            elseif textMode == "NUMERIC" then previewPowerText:SetText("85 / 100")
            elseif textMode == "PERCENT" then previewPowerText:SetText("85%")
            elseif textMode == "SYNC" then previewPowerText:SetText("85 (85%)")
            else previewPowerText:SetText("") end
        elseif playerClass == "WARRIOR" then
            previewPowerFill:SetVertexColor(0.85, 0.15, 0.15, 1.0)
            previewPowerFill:SetWidth(238 * 0.45)
            if textMode == "BOTH" then previewPowerText:SetText("45 / 100 (45%)")
            elseif textMode == "NUMERIC" then previewPowerText:SetText("45 / 100")
            elseif textMode == "PERCENT" then previewPowerText:SetText("45%")
            elseif textMode == "SYNC" then previewPowerText:SetText("45 (45%)")
            else previewPowerText:SetText("") end
        else
            -- Universal Mana/Energy Fallback
            previewPowerFill:SetVertexColor(0.15, 0.45, 0.95, 1.0)
            previewPowerFill:SetWidth(238 * 0.80)
            if textMode == "NONE" then previewPowerText:SetText("")
            else previewPowerText:SetText("2,500 / 3,000 (83%)") end
        end

        -- 6. Class Sub-Bars
        if playerClass == "SHAMAN" and showTotems then
            previewTotemBar:Show()
            previewCPBar:Hide()
        elseif (playerClass == "ROGUE" or playerClass == "DRUID") and showCP then
            previewCPBar:Show()
            previewTotemBar:Hide()
        else
            previewTotemBar:Hide()
            previewCPBar:Hide()
        end
    end

    -- ========================================================================
    -- BOTTOM SECTION: 2-Column Dashboard (Sidebar Tabs + Content Area)
    -- ========================================================================

    -- Left Sidebar
    local sidebar = CreateFrame("Frame", nil, f, BackdropTemplateString)
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -192)
    sidebar:SetSize(175, 380)
    ApplyWHITE8X8Backdrop(sidebar, 0.040, 0.045, 0.055, 0.8, 0.12, 0.14, 0.18, 0.7, 1)

    local sidebarTitle = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sidebarTitle:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 12, -10)
    sidebarTitle:SetText("|cff666666CONFIGURATION|r")

    -- Right Content Area Container
    local contentArea = CreateFrame("Frame", nil, f)
    contentArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
    contentArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 48)

    local contentPanels = {}
    local tabButtons = {}
    local currentTab = "display"

    -- Reusable Widget Constructors
    local function CreateCard(parent, height, yOffset)
        local card = CreateFrame("Frame", nil, parent, BackdropTemplateString)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset or 0)
        card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset or 0)
        card:SetHeight(height)
        ApplyWHITE8X8Backdrop(card, 0.08, 0.09, 0.12, 0.95, 0.18, 0.20, 0.26, 0.8, 1)
        return card
    end

    local function CreateToggleSwitchCard(parent, titleText, descText, yOffset, getFunc, setFunc, settingKey, onChange)
        local card = CreateCard(parent, 56, yOffset)

        local sw = CreateFrame("Button", nil, card, BackdropTemplateString)
        sw:SetSize(38, 20)
        sw:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        ApplyWHITE8X8Backdrop(sw, 0.16, 0.18, 0.24, 1.0, 0.26, 0.30, 0.38, 1.0, 1)

        local thumb = sw:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(14, 14)
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumb:SetPoint("LEFT", sw, "LEFT", 3, 0)
        sw.thumb = thumb

        local title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -9)
        title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -60, -9)
        title:SetJustifyH("LEFT")
        title:SetText(titleText)

        local desc = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        desc:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -3)
        desc:SetWordWrap(true)
        desc:SetJustifyH("LEFT")
        desc:SetText(descText)

        sw.UpdateValue = function(self)
            local val = getFunc() and true or false
            if val then
                self:SetBackdropColor(0.0, 0.60, 0.85, 1.0)
                self:SetBackdropBorderColor(0.0, 0.80, 1.0, 1.0)
                thumb:ClearAllPoints()
                thumb:SetPoint("RIGHT", self, "RIGHT", -3, 0)
                thumb:SetVertexColor(1, 1, 1, 1)
            else
                self:SetBackdropColor(0.16, 0.18, 0.24, 1.0)
                self:SetBackdropBorderColor(0.26, 0.30, 0.38, 1.0)
                thumb:ClearAllPoints()
                thumb:SetPoint("LEFT", self, "LEFT", 3, 0)
                thumb:SetVertexColor(0.65, 0.68, 0.75, 1)
            end
        end

        sw:SetScript("OnClick", function(self)
            local newVal = not (getFunc() and true or false)
            PlaySound(newVal and (SOUNDKIT.IG_MAINOPTION_CHECKBOX_ON or 856) or (SOUNDKIT.IG_MAINOPTION_CHECKBOX_OFF or 857))
            setFunc(newVal)
            if settingKey and FC.SaveCharSetting then
                FC:SaveCharSetting(settingKey, newVal)
            end
            self:UpdateValue()
            UpdateHUDPreview()
            if onChange then onChange(newVal) end
        end)

        card.sw = sw
        sw:UpdateValue()
        return card
    end

    local function CreateSliderCard(parent, titleText, descText, yOffset, minVal, maxVal, step, getFunc, setFunc, formatFunc, settingKey, onChange)
        local card = CreateCard(parent, 68, yOffset)

        local readout = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        readout:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -8)

        local title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -8)
        title:SetPoint("TOPRIGHT", readout, "TOPLEFT", -8, 0)
        title:SetJustifyH("LEFT")
        title:SetText(titleText)

        local desc = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        desc:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -22)
        desc:SetWordWrap(true)
        desc:SetJustifyH("LEFT")
        desc:SetText(descText)

        local sliderName = "ForeverClassesCfgSlider_" .. tostring(settingKey or math.random(1000, 9999))
        local slider = CreateFrame("Slider", sliderName, card, "OptionsSliderTemplate")
        slider:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 8)
        slider:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 8)
        slider:SetHeight(14)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step or 1)
        slider:SetObeyStepOnDrag(true)

        local low = _G[sliderName .. "Low"]
        local high = _G[sliderName .. "High"]
        local text = _G[sliderName .. "Text"]
        if low then low:Hide() end
        if high then high:Hide() end
        if text then text:Hide() end

        local isUpdating = false
        card.UpdateValue = function(self)
            isUpdating = true
            local cur = getFunc() or minVal
            slider:SetValue(cur)
            if formatFunc then
                readout:SetText(formatFunc(cur))
            else
                readout:SetText(tostring(cur))
            end
            isUpdating = false
        end

        slider:SetScript("OnValueChanged", function(self, val)
            val = math.floor(val + 0.5)
            if formatFunc then
                readout:SetText(formatFunc(val))
            else
                readout:SetText(tostring(val))
            end
            if not isUpdating then
                setFunc(val)
                if settingKey and FC.SaveCharSetting then
                    FC:SaveCharSetting(settingKey, val)
                end
                UpdateHUDPreview()
                if onChange then onChange(val) end
            end
        end)

        card.slider = slider
        card:UpdateValue()
        return card
    end

    -- Tab Switch Engine
    local function SelectTab(tabId)
        if tabId == "class" and not hasClassSupport then
            return
        end

        currentTab = tabId
        PlaySound(SOUNDKIT.IG_MAINOPTION_TAB or 841)

        for id, panel in pairs(contentPanels) do
            if id == tabId then
                panel:Show()
            else
                panel:Hide()
            end
        end

        for id, btn in pairs(tabButtons) do
            if id == tabId then
                btn:SetBackdropColor(0.10, 0.12, 0.16, 0.95)
                btn:SetBackdropBorderColor(0.78, 0.61, 0.24, 0.6)
                btn.label:SetTextColor(0.0, 0.80, 1.0, 1.0)
                if btn.icon then btn.icon:SetVertexColor(1, 1, 1, 1) end
            else
                local isDis = (id == "class" and not hasClassSupport)
                if isDis then
                    btn:SetBackdropColor(0.05, 0.05, 0.06, 0.4)
                    btn:SetBackdropBorderColor(0.12, 0.14, 0.18, 0.4)
                    btn.label:SetTextColor(0.35, 0.38, 0.45, 1.0)
                    if btn.icon then btn.icon:SetVertexColor(0.35, 0.38, 0.45, 0.6) end
                else
                    btn:SetBackdropColor(0.05, 0.05, 0.06, 0.7)
                    btn:SetBackdropBorderColor(0.12, 0.14, 0.18, 0.6)
                    btn.label:SetTextColor(0.65, 0.68, 0.75, 1.0)
                    if btn.icon then btn.icon:SetVertexColor(0.8, 0.8, 0.8, 1) end
                end
            end
        end
    end

    -- Create 5 Sidebar Tabs (No Emojis - Real Blizzard Textures)
    local TAB_DEFS = {
        { id = "display",   label = "HUD & Appearance",     icon = "Interface\\Icons\\INV_Misc_Eye_01" },
        { id = "abilities", label = "Abilities & Cooldowns", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
        { id = "class",     label = "Class Support",        icon = "Interface\\Icons\\INV_Misc_Book_09" },
        { id = "alerts",    label = "Alerts & Debuffs",     icon = "Interface\\Icons\\Spell_Shadow_Skull" },
        { id = "position",  label = "Position & Movement",  icon = "Interface\\Icons\\Ability_Hunter_Pathfinding" },
    }

    for i, tDef in ipairs(TAB_DEFS) do
        local btn = CreateFrame("Button", nil, sidebar, BackdropTemplateString)
        btn:SetSize(155, 36)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -28 - ((i - 1) * 42))
        btn.tabId = tDef.id

        ApplyWHITE8X8Backdrop(btn, 0.05, 0.05, 0.06, 0.7, 0.12, 0.14, 0.18, 0.6, 1)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        if tDef.id == "class" and coords then
            icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            icon:SetTexture(tDef.icon)
        end
        btn.icon = icon

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        label:SetText(tDef.label)
        btn.label = label

        -- Class Support Tab: Handle Unsupported Classes
        if tDef.id == "class" and not hasClassSupport then
            local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            badge:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            badge:SetText("|cff555555[N/A]|r")
            btn.badge = badge

            btn:SetAlpha(0.4)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("|cffffd100Class Support|r", 1, 1, 1)
                GameTooltip:AddLine("|cffffaa00Your class doesn't have special support yet|r", 1, 0.8, 0.2)
                GameTooltip:AddLine("Your class utilizes the core universal ForeverClasses HUD engine without requiring dedicated sub-bars.", 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn:SetScript("OnClick", function()
                PlaySound(SOUNDKIT.IG_MAINOPTION_CHECKBOX_OFF or 857)
            end)
        else
            btn:SetScript("OnEnter", function(self)
                if self.tabId ~= currentTab then
                    self:SetBackdropBorderColor(0.35, 0.40, 0.50, 0.8)
                    self.label:SetTextColor(1, 1, 1, 1)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if self.tabId ~= currentTab then
                    self:SetBackdropBorderColor(0.12, 0.14, 0.18, 0.6)
                    self.label:SetTextColor(0.65, 0.68, 0.75, 1.0)
                end
            end)
            btn:SetScript("OnClick", function(self)
                SelectTab(self.tabId)
            end)
        end

        tabButtons[tDef.id] = btn
    end

    -- ========================================================================
    -- PANEL 1: HUD & Appearance
    -- ========================================================================
    local panelDisplay = CreateFrame("Frame", nil, contentArea)
    panelDisplay:SetAllPoints(contentArea)
    contentPanels["display"] = panelDisplay

    local titleDisplay = panelDisplay:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    titleDisplay:SetPoint("TOPLEFT", panelDisplay, "TOPLEFT", 0, -2)
    titleDisplay:SetText("HUD & Appearance")

    local subDisplay = panelDisplay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subDisplay:SetPoint("TOPLEFT", titleDisplay, "BOTTOMLEFT", 0, -2)
    subDisplay:SetPoint("RIGHT", panelDisplay, "RIGHT", -12, 0)
    subDisplay:SetWordWrap(true)
    subDisplay:SetJustifyH("LEFT")
    subDisplay:SetText("Control visual colors, heal prediction, text formatting, and resting opacity.")

    -- Option 1: Class-Colored Health Bar
    local cardClassColor = CreateToggleSwitchCard(panelDisplay, "Class-Colored Health Bar",
        "Tint health bar with your active class color instead of Emerald Green.", -40,
        function() return ForeverClassesDB.classColorHealth end,
        function(val)
            ForeverClassesDB.classColorHealth = val
            if FC.UpdateHealth then FC:UpdateHealth() end
        end,
        "classColorHealth"
    )

    -- Option 2: Upcoming Heals Prediction
    local cardHeals = CreateToggleSwitchCard(panelDisplay, "Upcoming Heals Prediction",
        "Visualizes incoming direct and HoT heals in real-time before they land.", -102,
        function() return ForeverClassesDB.showIncomingHeals end,
        function(val)
            ForeverClassesDB.showIncomingHeals = val
            if FC.UpdateHealth then FC:UpdateHealth() end
        end,
        "showIncomingHeals"
    )

    -- Option 3: Status Text Display Mode (Segmented Button Group)
    local cardTextMode = CreateCard(panelDisplay, 62, -164)

    local txtTitle = cardTextMode:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txtTitle:SetPoint("TOPLEFT", cardTextMode, "TOPLEFT", 12, -8)
    txtTitle:SetPoint("RIGHT", cardTextMode, "RIGHT", -12, 0)
    txtTitle:SetJustifyH("LEFT")
    txtTitle:SetText("Status Text Display Mode")

    local textModes = {
        { id = "BOTH",    label = "Both" },
        { id = "NUMERIC", label = "Numeric" },
        { id = "PERCENT", label = "Percent" },
        { id = "SYNC",    label = "Sync" },
        { id = "NONE",    label = "Hide" },
    }
    local textModeBtns = {}
    for i, tm in ipairs(textModes) do
        local btn = CreateFrame("Button", nil, cardTextMode, BackdropTemplateString)
        btn:SetSize(76, 22)
        btn:SetPoint("TOPLEFT", cardTextMode, "TOPLEFT", 12 + ((i - 1) * 81), -30)
        btn.tmId = tm.id
        ApplyWHITE8X8Backdrop(btn, 0.05, 0.06, 0.08, 0.8, 0.15, 0.17, 0.22, 0.8, 1)

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btnText:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btnText:SetText(tm.label)
        btn.btnText = btnText

        btn:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINOPTION_CHECKBOX_ON or 856)
            ForeverClassesDB.textMode = tm.id
            if FC.SaveCharSetting then FC:SaveCharSetting("textMode", tm.id) end
            if FC.ApplyConfig then FC:ApplyConfig() end
            cardTextMode:UpdateValue()
            UpdateHUDPreview()
        end)
        textModeBtns[tm.id] = btn
    end

    cardTextMode.UpdateValue = function()
        local cur = ForeverClassesDB.textMode or "BOTH"
        for id, btn in pairs(textModeBtns) do
            if id == cur then
                btn:SetBackdropColor(0.0, 0.50, 0.70, 0.35)
                btn:SetBackdropBorderColor(0.0, 0.80, 1.0, 0.9)
                btn.btnText:SetTextColor(0.0, 0.80, 1.0, 1.0)
            else
                btn:SetBackdropColor(0.05, 0.06, 0.08, 0.8)
                btn:SetBackdropBorderColor(0.15, 0.17, 0.22, 0.8)
                btn.btnText:SetTextColor(0.65, 0.68, 0.75, 1.0)
            end
        end
    end
    cardTextMode:UpdateValue()

    -- Option 4: Out-of-Combat Auto Fade (Slider 10-80%)
    local cardFade = CreateSliderCard(panelDisplay, "Out-of-Combat Auto Fade",
        "Dims HUD when at 100% health & mana with no target.", -232,
        10, 80, 5,
        function() return math.floor(((ForeverClassesDB.autoFadeAlpha) or 0.35) * 100) end,
        function(val)
            ForeverClassesDB.autoFadeAlpha = val / 100
            ForeverClassesDB.autoFade = true
            if FC.RequestFadeCheck then FC:RequestFadeCheck() end
        end,
        function(val) return string.format("|cff00ccff%d%%|r", val) end,
        "autoFadeAlpha"
    )

    -- Option 5: Permanent Core Shield Notice
    local cardShieldNotice = CreateCard(panelDisplay, 72, -306)
    local shieldNoticeTitle = cardShieldNotice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shieldNoticeTitle:SetPoint("TOPLEFT", cardShieldNotice, "TOPLEFT", 12, -8)
    shieldNoticeTitle:SetText("|cffddddddNative Damage Absorption & Overshield Engine|r")

    local shieldNoticeBadge = cardShieldNotice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shieldNoticeBadge:SetPoint("TOPRIGHT", cardShieldNotice, "TOPRIGHT", -12, -8)
    shieldNoticeBadge:SetText("|cff00ff88Native Core|r")

    shieldNoticeTitle:SetPoint("RIGHT", shieldNoticeBadge, "LEFT", -8, 0)
    shieldNoticeTitle:SetJustifyH("LEFT")

    local shieldNoticeDesc = cardShieldNotice:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    shieldNoticeDesc:SetPoint("TOPLEFT", shieldNoticeTitle, "BOTTOMLEFT", 0, -3)
    shieldNoticeDesc:SetPoint("TOPRIGHT", cardShieldNotice, "TOPRIGHT", -12, -23)
    shieldNoticeDesc:SetWordWrap(true)
    shieldNoticeDesc:SetJustifyH("LEFT")
    shieldNoticeDesc:SetText("Real-time shields (PW:S, Ice Barrier, Mana Shield) and dynamic overshield cyan glow are permanent core HUD features. Non-toggleable to ensure complete combat awareness.")

    -- ========================================================================
    -- PANEL 2: Abilities & Cooldowns
    -- ========================================================================
    local panelAbilities = CreateFrame("Frame", nil, contentArea)
    panelAbilities:SetAllPoints(contentArea)
    panelAbilities:Hide()
    contentPanels["abilities"] = panelAbilities

    local titleAbilities = panelAbilities:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    titleAbilities:SetPoint("TOPLEFT", panelAbilities, "TOPLEFT", 0, -2)
    titleAbilities:SetText("Ability & Cooldown Dock")

    local subAbilities = panelAbilities:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subAbilities:SetPoint("TOPLEFT", titleAbilities, "BOTTOMLEFT", 0, -2)
    subAbilities:SetPoint("RIGHT", panelAbilities, "RIGHT", -12, 0)
    subAbilities:SetWordWrap(true)
    subAbilities:SetJustifyH("LEFT")
    subAbilities:SetText("Configure ability dock slots (0 to 7) and flash pulse effects.")

    -- Option 1: Active Ability Slots Selector (0 to 7)
    local cardSlots = CreateCard(panelAbilities, 96, -40)

    local slotsReadout = cardSlots:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    slotsReadout:SetPoint("TOPRIGHT", cardSlots, "TOPRIGHT", -12, -8)

    local slotsTitle = cardSlots:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    slotsTitle:SetPoint("TOPLEFT", cardSlots, "TOPLEFT", 12, -8)
    slotsTitle:SetPoint("TOPRIGHT", slotsReadout, "TOPLEFT", -8, 0)
    slotsTitle:SetJustifyH("LEFT")
    slotsTitle:SetText("Active Ability Slots")

    local slotsDesc = cardSlots:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    slotsDesc:SetPoint("TOPLEFT", slotsTitle, "BOTTOMLEFT", 0, -2)
    slotsDesc:SetPoint("TOPRIGHT", cardSlots, "TOPRIGHT", -12, -22)
    slotsDesc:SetWordWrap(true)
    slotsDesc:SetJustifyH("LEFT")
    slotsDesc:SetText("Number of spell/ability buttons docked directly above the health bar.")

    local slotBtns = {}
    local slotConfig = {
        { num = 0, label = "0 Off", w = 48 },
        { num = 1, label = "1",     w = 34 },
        { num = 2, label = "2",     w = 34 },
        { num = 3, label = "3",     w = 34 },
        { num = 4, label = "4",     w = 34 },
        { num = 5, label = "5",     w = 34 },
        { num = 6, label = "6",     w = 34 },
        { num = 7, label = "7",     w = 34 },
    }
    local curX = 12
    for _, sc in ipairs(slotConfig) do
        local btn = CreateFrame("Button", nil, cardSlots, BackdropTemplateString)
        btn:SetSize(sc.w, 22)
        btn:SetPoint("TOPLEFT", cardSlots, "TOPLEFT", curX, -38)
        btn.slotNum = sc.num
        ApplyWHITE8X8Backdrop(btn, 0.05, 0.06, 0.08, 0.8, 0.15, 0.17, 0.22, 0.8, 1)

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btnText:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btnText:SetText(sc.label)
        btn.btnText = btnText

        btn:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINOPTION_CHECKBOX_ON or 856)
            FC:SetCooldownSlotCount(sc.num)
            cardSlots:UpdateValue()
            UpdateHUDPreview()
        end)
        slotBtns[sc.num] = btn
        curX = curX + sc.w + 5
    end

    local slotsFootnote = cardSlots:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    slotsFootnote:SetPoint("TOPLEFT", cardSlots, "TOPLEFT", 12, -68)
    slotsFootnote:SetPoint("TOPRIGHT", cardSlots, "TOPRIGHT", -12, -68)
    slotsFootnote:SetWordWrap(true)
    slotsFootnote:SetJustifyH("LEFT")
    slotsFootnote:SetText("ForeverClasses supports exactly up to 7 slots spanning the 240px unit frame width.")

    cardSlots.UpdateValue = function()
        local cur = FC:GetCooldownSlotCount()
        for num, btn in pairs(slotBtns) do
            if num == cur then
                btn:SetBackdropColor(0.0, 0.50, 0.70, 0.35)
                btn:SetBackdropBorderColor(0.0, 0.80, 1.0, 0.9)
                btn.btnText:SetTextColor(0.0, 0.80, 1.0, 1.0)
            else
                btn:SetBackdropColor(0.05, 0.06, 0.08, 0.8)
                btn:SetBackdropBorderColor(0.15, 0.17, 0.22, 0.8)
                btn.btnText:SetTextColor(0.65, 0.68, 0.75, 1.0)
            end
        end
        if cur == 0 then
            slotsReadout:SetText("|cffff44440 Off (Disabled)|r")
        else
            slotsReadout:SetText(string.format("|cff00ff88%d Active|r", cur))
        end
    end
    cardSlots:UpdateValue()

    -- Option 2: Cooldown Ready Pulse
    local cardPulse = CreateToggleSwitchCard(panelAbilities, "Cooldown Ready Pulse",
        "Flash high-contrast starburst animation when an ability comes off cooldown.", -142,
        function() return ForeverClassesDB.cooldownPulse ~= false end,
        function(val) ForeverClassesDB.cooldownPulse = val end,
        "cooldownPulse"
    )

    -- Option 3: Built-in Active Buff Overlay Notice
    local cardBuffNotice = CreateCard(panelAbilities, 88, -204)
    local buffIcon = cardBuffNotice:CreateTexture(nil, "ARTWORK")
    buffIcon:SetSize(22, 22)
    buffIcon:SetPoint("TOPLEFT", cardBuffNotice, "TOPLEFT", 12, -12)
    buffIcon:SetTexture("Interface\\Icons\\Spell_Holy_MagicalSentry")
    buffIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local buffNoticeText = cardBuffNotice:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    buffNoticeText:SetPoint("TOPLEFT", buffIcon, "TOPRIGHT", 10, 2)
    buffNoticeText:SetPoint("TOPRIGHT", cardBuffNotice, "TOPRIGHT", -12, -10)
    buffNoticeText:SetWordWrap(true)
    buffNoticeText:SetJustifyH("LEFT")
    buffNoticeText:SetText("|cffffd100Built-in Active Buff Overlay:|r When a tracked ability grants a self-buff (e.g. |cffffffffSprint, Blade Flurry, Ice Barrier, Lightning Shield|r), its button automatically illuminates with a radiant golden border and real-time countdown timer without requiring separate configuration.")

    -- ========================================================================
    -- PANEL 3: Class Support (Context-Sensitive to Active Class)
    -- ========================================================================
    local panelClass = CreateFrame("Frame", nil, contentArea)
    panelClass:SetAllPoints(contentArea)
    panelClass:Hide()
    contentPanels["class"] = panelClass

    local titleClass = panelClass:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    titleClass:SetPoint("TOPLEFT", panelClass, "TOPLEFT", 0, -2)
    if playerClass == "SHAMAN" then
        titleClass:SetText("Shaman Support Module")
    elseif playerClass == "ROGUE" or playerClass == "DRUID" then
        titleClass:SetText("Rogue & Feral Support Module")
    else
        titleClass:SetText("Class Support Module")
    end

    local subClass = panelClass:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subClass:SetPoint("TOPLEFT", titleClass, "BOTTOMLEFT", 0, -2)
    subClass:SetPoint("RIGHT", panelClass, "RIGHT", -12, 0)
    subClass:SetWordWrap(true)
    subClass:SetJustifyH("LEFT")
    subClass:SetText("Context-sensitive mechanics and sub-bars tailored specifically for your active class.")

    local cardClassEngine = nil
    if playerClass == "SHAMAN" then
        cardClassEngine = CreateCard(panelClass, 96, -40)
        cardClassEngine:SetBackdropBorderColor(0.0, 0.44, 0.87, 0.6)

        local ceHeader = cardClassEngine:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ceHeader:SetPoint("TOPLEFT", cardClassEngine, "TOPLEFT", 12, -10)
        ceHeader:SetText("|cff0070DESHAMAN SUPPORT ENGINE|r")

        local ceBadge = cardClassEngine:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        ceBadge:SetPoint("TOPRIGHT", cardClassEngine, "TOPRIGHT", -12, -10)
        ceBadge:SetText("|cff00ccffActive Class|r")

        local ceDivider = cardClassEngine:CreateTexture(nil, "ARTWORK")
        ceDivider:SetHeight(1)
        ceDivider:SetPoint("TOPLEFT", cardClassEngine, "TOPLEFT", 12, -26)
        ceDivider:SetPoint("TOPRIGHT", cardClassEngine, "TOPRIGHT", -12, -26)
        ceDivider:SetTexture("Interface\\Buttons\\WHITE8X8")
        ceDivider:SetVertexColor(0.2, 0.24, 0.32, 0.8)

        local swTotem = CreateFrame("Button", nil, cardClassEngine, BackdropTemplateString)
        swTotem:SetSize(38, 20)
        swTotem:SetPoint("TOPRIGHT", cardClassEngine, "TOPRIGHT", -12, -34)
        ApplyWHITE8X8Backdrop(swTotem, 0.16, 0.18, 0.24, 1.0, 0.26, 0.30, 0.38, 1.0, 1)

        local thumbT = swTotem:CreateTexture(nil, "OVERLAY")
        thumbT:SetSize(14, 14)
        thumbT:SetTexture("Interface\\Buttons\\WHITE8X8")
        swTotem.thumb = thumbT

        local tTitle = cardClassEngine:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        tTitle:SetPoint("TOPLEFT", ceDivider, "BOTTOMLEFT", 0, -10)
        tTitle:SetPoint("TOPRIGHT", cardClassEngine, "TOPRIGHT", -60, -37)
        tTitle:SetJustifyH("LEFT")
        tTitle:SetText("Shaman Totem Bar")

        local tDesc = cardClassEngine:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tDesc:SetPoint("TOPLEFT", tTitle, "BOTTOMLEFT", 0, -3)
        tDesc:SetPoint("TOPRIGHT", tTitle, "BOTTOMRIGHT", 0, -3)
        tDesc:SetWordWrap(true)
        tDesc:SetJustifyH("LEFT")
        tDesc:SetText("Docks 4 elemental slots (Earth, Fire, Water, Air) below the HUD with live expiration timers.")

        swTotem.UpdateValue = function(self)
            local val = ForeverClassesDB.showTotems and true or false
            if val then
                self:SetBackdropColor(0.0, 0.44, 0.87, 1.0)
                self:SetBackdropBorderColor(0.0, 0.70, 1.0, 1.0)
                thumbT:ClearAllPoints()
                thumbT:SetPoint("RIGHT", self, "RIGHT", -3, 0)
                thumbT:SetVertexColor(1, 1, 1, 1)
            else
                self:SetBackdropColor(0.16, 0.18, 0.24, 1.0)
                self:SetBackdropBorderColor(0.26, 0.30, 0.38, 1.0)
                thumbT:ClearAllPoints()
                thumbT:SetPoint("LEFT", self, "LEFT", 3, 0)
                thumbT:SetVertexColor(0.65, 0.68, 0.75, 1)
            end
        end

        swTotem:SetScript("OnClick", function(self)
            local newVal = not (ForeverClassesDB.showTotems and true or false)
            PlaySound(newVal and (SOUNDKIT.IG_MAINOPTION_CHECKBOX_ON or 856) or (SOUNDKIT.IG_MAINOPTION_CHECKBOX_OFF or 857))
            ForeverClassesDB.showTotems = newVal
            if FC.SaveCharSetting then FC:SaveCharSetting("showTotems", newVal) end
            if FC.UpdateTotems then FC:UpdateTotems() end
            self:UpdateValue()
            UpdateHUDPreview()
        end)
        cardClassEngine.sw = swTotem
        swTotem:UpdateValue()

    elseif playerClass == "ROGUE" or playerClass == "DRUID" then
        cardClassEngine = CreateCard(panelClass, 96, -40)
        cardClassEngine:SetBackdropBorderColor(1.0, 0.96, 0.41, 0.6)

        local ceHeader = cardClassEngine:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ceHeader:SetPoint("TOPLEFT", cardClassEngine, "TOPLEFT", 12, -10)
        ceHeader:SetText("|cfffff569ROGUE & FERAL SUPPORT ENGINE|r")

        local ceBadge = cardClassEngine:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        ceBadge:SetPoint("TOPRIGHT", cardClassEngine, "TOPRIGHT", -12, -10)
        ceBadge:SetText("|cfffff569Active Class|r")

        local ceDivider = cardClassEngine:CreateTexture(nil, "ARTWORK")
        ceDivider:SetHeight(1)
        ceDivider:SetPoint("TOPLEFT", cardClassEngine, "TOPLEFT", 12, -26)
        ceDivider:SetPoint("TOPRIGHT", cardClassEngine, "TOPRIGHT", -12, -26)
        ceDivider:SetTexture("Interface\\Buttons\\WHITE8X8")
        ceDivider:SetVertexColor(0.2, 0.24, 0.32, 0.8)

        local swCP = CreateFrame("Button", nil, cardClassEngine, BackdropTemplateString)
        swCP:SetSize(38, 20)
        swCP:SetPoint("TOPRIGHT", cardClassEngine, "TOPRIGHT", -12, -34)
        ApplyWHITE8X8Backdrop(swCP, 0.16, 0.18, 0.24, 1.0, 0.26, 0.30, 0.38, 1.0, 1)

        local thumbCP = swCP:CreateTexture(nil, "OVERLAY")
        thumbCP:SetSize(14, 14)
        thumbCP:SetTexture("Interface\\Buttons\\WHITE8X8")
        swCP.thumb = thumbCP

        local cTitle = cardClassEngine:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cTitle:SetPoint("TOPLEFT", ceDivider, "BOTTOMLEFT", 0, -10)
        cTitle:SetPoint("TOPRIGHT", cardClassEngine, "TOPRIGHT", -60, -37)
        cTitle:SetJustifyH("LEFT")
        cTitle:SetText("Combo Points Bar")

        local cDesc = cardClassEngine:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cDesc:SetPoint("TOPLEFT", cTitle, "BOTTOMLEFT", 0, -3)
        cDesc:SetPoint("TOPRIGHT", cTitle, "BOTTOMRIGHT", 0, -3)
        cDesc:SetWordWrap(true)
        cDesc:SetJustifyH("LEFT")
        cDesc:SetText("Renders 5 high-contrast combo point orbs directly beneath the power bar during combat.")

        swCP.UpdateValue = function(self)
            local val = ForeverClassesDB.showComboPoints and true or false
            if val then
                self:SetBackdropColor(0.85, 0.75, 0.10, 1.0)
                self:SetBackdropBorderColor(1.0, 0.90, 0.20, 1.0)
                thumbCP:ClearAllPoints()
                thumbCP:SetPoint("RIGHT", self, "RIGHT", -3, 0)
                thumbCP:SetVertexColor(1, 1, 1, 1)
            else
                self:SetBackdropColor(0.16, 0.18, 0.24, 1.0)
                self:SetBackdropBorderColor(0.26, 0.30, 0.38, 1.0)
                thumbCP:ClearAllPoints()
                thumbCP:SetPoint("LEFT", self, "LEFT", 3, 0)
                thumbCP:SetVertexColor(0.65, 0.68, 0.75, 1)
            end
        end

        swCP:SetScript("OnClick", function(self)
            local newVal = not (ForeverClassesDB.showComboPoints and true or false)
            PlaySound(newVal and (SOUNDKIT.IG_MAINOPTION_CHECKBOX_ON or 856) or (SOUNDKIT.IG_MAINOPTION_CHECKBOX_OFF or 857))
            ForeverClassesDB.showComboPoints = newVal
            if FC.SaveCharSetting then FC:SaveCharSetting("showComboPoints", newVal) end
            if FC.UpdateComboPoints then FC:UpdateComboPoints() end
            self:UpdateValue()
            UpdateHUDPreview()
        end)
        cardClassEngine.sw = swCP
        swCP:UpdateValue()
    else
        -- Unsupported Class Message Card
        cardClassEngine = CreateCard(panelClass, 120, -40)
        local unIcon = cardClassEngine:CreateTexture(nil, "ARTWORK")
        unIcon:SetSize(28, 28)
        unIcon:SetPoint("TOP", cardClassEngine, "TOP", 0, -14)
        unIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        unIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local unTitle = cardClassEngine:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        unTitle:SetPoint("TOP", unIcon, "BOTTOM", 0, -6)
        unTitle:SetText("No Custom Class Modules Required")

        local unDesc = cardClassEngine:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        unDesc:SetPoint("TOP", unTitle, "BOTTOM", 0, -4)
        unDesc:SetPoint("LEFT", cardClassEngine, "LEFT", 20, 0)
        unDesc:SetPoint("RIGHT", cardClassEngine, "RIGHT", -20, 0)
        unDesc:SetWordWrap(true)
        unDesc:SetJustifyH("CENTER")
        unDesc:SetText("Your class utilizes the core universal ForeverClasses HUD engine without requiring dedicated sub-bars. All core features (Resource Bars, Absorbs, Heals, and Ability Docks) are fully active.")
    end

    -- ========================================================================
    -- PANEL 4: Alerts & Debuffs
    -- ========================================================================
    local panelAlerts = CreateFrame("Frame", nil, contentArea)
    panelAlerts:SetAllPoints(contentArea)
    panelAlerts:Hide()
    contentPanels["alerts"] = panelAlerts

    local titleAlerts = panelAlerts:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    titleAlerts:SetPoint("TOPLEFT", panelAlerts, "TOPLEFT", 0, -2)
    titleAlerts:SetText("Alerts & Debuffs")

    local subAlerts = panelAlerts:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subAlerts:SetPoint("TOPLEFT", titleAlerts, "BOTTOMLEFT", 0, -2)
    subAlerts:SetPoint("RIGHT", panelAlerts, "RIGHT", -12, 0)
    subAlerts:SetWordWrap(true)
    subAlerts:SetJustifyH("LEFT")
    subAlerts:SetText("Low health warnings and harmful combat debuffs.")

    -- Option 1: Low Health Danger Pulse Slider (15-50%)
    local cardLowHp = CreateSliderCard(panelAlerts, "Low Health Danger Pulse",
        "Triggers red perimeter alert pulse and warning audio chime.", -40,
        15, 50, 1,
        function() return ForeverClassesDB.lowHealthThreshold or 33 end,
        function(val)
            ForeverClassesDB.lowHealthThreshold = val
            ForeverClassesDB.lowHealthWarning = true
            if FC.SaveCharSetting then FC:SaveCharSetting("lowHealthWarning", true) end
            if FC.UpdateHealth then FC:UpdateHealth() end
        end,
        function(val) return string.format("|cffff4444<= %d%% HP|r", val) end,
        "lowHealthThreshold"
    )

    -- Option 2: Harmful Debuffs Tray Toggle
    local cardDebuffs = CreateToggleSwitchCard(panelAlerts, "Harmful Debuffs Tray",
        "Docked to the right of the HUD with Magic, Curse, Poison & Disease borders.", -114,
        function() return ForeverClassesDB.showDebuffs end,
        function(val)
            ForeverClassesDB.showDebuffs = val
            if FC.UpdateDebuffs then FC:UpdateDebuffs() end
        end,
        "showDebuffs"
    )

    -- ========================================================================
    -- PANEL 5: Position & Movement
    -- ========================================================================
    local panelPosition = CreateFrame("Frame", nil, contentArea)
    panelPosition:SetAllPoints(contentArea)
    panelPosition:Hide()
    contentPanels["position"] = panelPosition

    local titlePosition = panelPosition:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    titlePosition:SetPoint("TOPLEFT", panelPosition, "TOPLEFT", 0, -2)
    titlePosition:SetText("Position & Locking")

    local subPosition = panelPosition:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subPosition:SetPoint("TOPLEFT", titlePosition, "BOTTOMLEFT", 0, -2)
    subPosition:SetPoint("RIGHT", panelPosition, "RIGHT", -12, 0)
    subPosition:SetWordWrap(true)
    subPosition:SetJustifyH("LEFT")
    subPosition:SetText("Lock your HUD or move it anywhere across your screen.")

    -- Radio Options for Movement
    local moveCards = {}

    local function CreateRadioCard(parent, titleText, descText, yOffset, modeKey)
        local card = CreateFrame("Button", nil, parent, BackdropTemplateString)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
        card:SetHeight(52)
        ApplyWHITE8X8Backdrop(card, 0.08, 0.09, 0.12, 0.95, 0.18, 0.20, 0.26, 0.8, 1)

        local radioCircle = CreateFrame("Frame", nil, card, BackdropTemplateString)
        radioCircle:SetSize(16, 16)
        radioCircle:SetPoint("RIGHT", card, "RIGHT", -14, 0)
        ApplyWHITE8X8Backdrop(radioCircle, 0.05, 0.06, 0.08, 1.0, 0.28, 0.32, 0.40, 1.0, 1)

        local dot = radioCircle:CreateTexture(nil, "OVERLAY")
        dot:SetSize(8, 8)
        dot:SetPoint("CENTER", radioCircle, "CENTER", 0, 0)
        dot:SetTexture("Interface\\Buttons\\WHITE8X8")
        dot:SetVertexColor(0.0, 0.80, 1.0, 1.0)
        radioCircle.dot = dot

        local title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -8)
        title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -40, -8)
        title:SetJustifyH("LEFT")
        title:SetText(titleText)

        local desc = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        desc:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -2)
        desc:SetWordWrap(true)
        desc:SetJustifyH("LEFT")
        desc:SetText(descText)

        card.UpdateValue = function(self)
            local isSel = (ForeverClassesDB.movementMode == modeKey)
            if isSel then
                card:SetBackdropColor(0.10, 0.12, 0.16, 0.95)
                card:SetBackdropBorderColor(0.0, 0.65, 0.85, 0.7)
                radioCircle:SetBackdropBorderColor(0.0, 0.80, 1.0, 1.0)
                dot:Show()
            else
                card:SetBackdropColor(0.08, 0.09, 0.12, 0.95)
                card:SetBackdropBorderColor(0.18, 0.20, 0.26, 0.8)
                radioCircle:SetBackdropBorderColor(0.24, 0.28, 0.36, 1.0)
                dot:Hide()
            end
        end

        card:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINOPTION_CHECKBOX_ON or 856)
            ForeverClassesDB.movementMode = modeKey
            if FC.ApplyConfig then FC:ApplyConfig() end
            f:Refresh()
        end)

        moveCards[modeKey] = card
        return card
    end

    CreateRadioCard(panelPosition, "Free Move", "Left-click and drag anywhere on the bar to reposition.", -40, "FREE")

    -- Hold Modifier Key Card (with embedded ALT/SHIFT/CTRL buttons)
    local cardMod = CreateFrame("Frame", nil, panelPosition, BackdropTemplateString)
    cardMod:SetPoint("TOPLEFT", panelPosition, "TOPLEFT", 0, -98)
    cardMod:SetPoint("TOPRIGHT", panelPosition, "TOPRIGHT", 0, -98)
    cardMod:SetHeight(74)
    ApplyWHITE8X8Backdrop(cardMod, 0.08, 0.09, 0.12, 0.95, 0.18, 0.20, 0.26, 0.8, 1)

    local modRadio = CreateFrame("Button", nil, cardMod, BackdropTemplateString)
    modRadio:SetSize(16, 16)
    modRadio:SetPoint("TOPRIGHT", cardMod, "TOPRIGHT", -14, -12)
    ApplyWHITE8X8Backdrop(modRadio, 0.05, 0.06, 0.08, 1.0, 0.28, 0.32, 0.40, 1.0, 1)

    local modDot = modRadio:CreateTexture(nil, "OVERLAY")
    modDot:SetSize(8, 8)
    modDot:SetPoint("CENTER", modRadio, "CENTER", 0, 0)
    modDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    modDot:SetVertexColor(0.0, 0.80, 1.0, 1.0)

    local modTitle = cardMod:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    modTitle:SetPoint("TOPLEFT", cardMod, "TOPLEFT", 12, -8)
    modTitle:SetPoint("TOPRIGHT", cardMod, "TOPRIGHT", -40, -8)
    modTitle:SetJustifyH("LEFT")
    modTitle:SetText("Hold Modifier Key")

    local modDesc = cardMod:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    modDesc:SetPoint("TOPLEFT", modTitle, "BOTTOMLEFT", 0, -2)
    modDesc:SetPoint("TOPRIGHT", modTitle, "BOTTOMRIGHT", 0, -2)
    modDesc:SetWordWrap(true)
    modDesc:SetJustifyH("LEFT")
    modDesc:SetText("Only drags when holding Alt, Shift, or Ctrl.")

    local modClickArea = CreateFrame("Button", nil, cardMod)
    modClickArea:SetPoint("TOPLEFT", cardMod, "TOPLEFT", 0, 0)
    modClickArea:SetPoint("BOTTOMRIGHT", cardMod, "TOPRIGHT", 0, -32)
    modClickArea:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINOPTION_CHECKBOX_ON or 856)
        ForeverClassesDB.movementMode = "MODIFIER"
        if FC.ApplyConfig then FC:ApplyConfig() end
        f:Refresh()
    end)

    -- Keys: ALT / SHIFT / CTRL
    local modKeyBtns = {}
    local modKeys = { "ALT", "SHIFT", "CTRL" }
    for i, k in ipairs(modKeys) do
        local btn = CreateFrame("Button", nil, cardMod, BackdropTemplateString)
        btn:SetSize(60, 20)
        btn:SetPoint("TOPLEFT", cardMod, "TOPLEFT", 12 + ((i - 1) * 66), -46)
        ApplyWHITE8X8Backdrop(btn, 0.05, 0.06, 0.08, 0.8, 0.15, 0.17, 0.22, 0.8, 1)

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btnText:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btnText:SetText(k)
        btn.btnText = btnText

        btn:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINOPTION_CHECKBOX_ON or 856)
            ForeverClassesDB.movementMode = "MODIFIER"
            ForeverClassesDB.modifierKey = k
            if FC.ApplyConfig then FC:ApplyConfig() end
            f:Refresh()
        end)
        modKeyBtns[k] = btn
    end

    cardMod.UpdateValue = function()
        local isSel = (ForeverClassesDB.movementMode == "MODIFIER")
        if isSel then
            cardMod:SetBackdropColor(0.10, 0.12, 0.16, 0.95)
            cardMod:SetBackdropBorderColor(0.0, 0.65, 0.85, 0.7)
            modRadio:SetBackdropBorderColor(0.0, 0.80, 1.0, 1.0)
            modDot:Show()
        else
            cardMod:SetBackdropColor(0.08, 0.09, 0.12, 0.95)
            cardMod:SetBackdropBorderColor(0.18, 0.20, 0.26, 0.8)
            modRadio:SetBackdropBorderColor(0.24, 0.28, 0.36, 1.0)
            modDot:Hide()
        end
        local curKey = ForeverClassesDB.modifierKey or "ALT"
        for k, btn in pairs(modKeyBtns) do
            if isSel and k == curKey then
                btn:SetBackdropColor(0.0, 0.50, 0.70, 0.35)
                btn:SetBackdropBorderColor(0.0, 0.80, 1.0, 0.9)
                btn.btnText:SetTextColor(0.0, 0.80, 1.0, 1.0)
            else
                btn:SetBackdropColor(0.05, 0.06, 0.08, 0.8)
                btn:SetBackdropBorderColor(0.15, 0.17, 0.22, 0.8)
                btn.btnText:SetTextColor(0.65, 0.68, 0.75, 1.0)
            end
        end
    end
    moveCards["MODIFIER"] = cardMod

    CreateRadioCard(panelPosition, "Locked", "Completely locked in place, clicks pass through.", -178, "LOCKED")

    -- Reset Position Button
    local resetBtn = CreateFrame("Button", nil, panelPosition, BackdropTemplateString)
    resetBtn:SetPoint("TOPLEFT", panelPosition, "TOPLEFT", 0, -236)
    resetBtn:SetPoint("TOPRIGHT", panelPosition, "TOPRIGHT", 0, -236)
    resetBtn:SetHeight(32)
    ApplyWHITE8X8Backdrop(resetBtn, 0.25, 0.08, 0.08, 0.6, 0.65, 0.18, 0.18, 0.7, 1)

    local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    resetText:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
    resetText:SetText("|cffff6666Reset Frame to Screen Center (X: 0, Y: -140)|r")

    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.35, 0.10, 0.10, 0.8)
        self:SetBackdropBorderColor(0.85, 0.25, 0.25, 0.9)
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.25, 0.08, 0.08, 0.6)
        self:SetBackdropBorderColor(0.65, 0.18, 0.18, 0.7)
    end)
    resetBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINOPTION_OK or 856)
        ForeverClassesDB.point = FC.Defaults.point
        ForeverClassesDB.relativePoint = FC.Defaults.relativePoint
        ForeverClassesDB.x = FC.Defaults.x
        ForeverClassesDB.y = FC.Defaults.y
        if FC.ApplyConfig then FC:ApplyConfig() end
        print("|cff00ccff[ForeverClasses]|r Position reset to center.")
    end)

    -- ========================================================================
    -- Window Footer Action Bar
    -- ========================================================================
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    footer:SetHeight(30)

    local footerNote = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerNote:SetPoint("LEFT", footer, "LEFT", 0, 0)
    footerNote:SetText("Slash Commands: |cff00ccff/fc|r • Version 1.0.3")

    -- Discard Button
    local discardBtn = CreateFrame("Button", nil, footer, BackdropTemplateString)
    discardBtn:SetSize(80, 24)
    discardBtn:SetPoint("RIGHT", footer, "RIGHT", -124, 0)
    ApplyWHITE8X8Backdrop(discardBtn, 0.14, 0.16, 0.20, 0.9, 0.25, 0.28, 0.35, 0.8, 1)

    local discardText = discardBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    discardText:SetPoint("CENTER", discardBtn, "CENTER", 0, 0)
    discardText:SetText("Discard")

    discardBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.22, 0.28, 1.0)
    end)
    discardBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.14, 0.16, 0.20, 0.9)
    end)
    discardBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINOPTION_CLOSE or 857)
        f:Hide()
    end)

    -- Save & Apply Button
    local saveBtn = CreateFrame("Button", nil, footer, BackdropTemplateString)
    saveBtn:SetSize(114, 24)
    saveBtn:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    ApplyWHITE8X8Backdrop(saveBtn, 0.10, 0.55, 0.32, 1.0, 0.15, 0.75, 0.45, 1.0, 1)

    local saveText = saveBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    saveText:SetPoint("CENTER", saveBtn, "CENTER", 0, 0)
    saveText:SetText("Save & Apply")

    saveBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.14, 0.65, 0.38, 1.0)
    end)
    saveBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.10, 0.55, 0.32, 1.0)
    end)
    saveBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINOPTION_OK or 856)
        if FC.SyncActiveCharSettings then pcall(FC.SyncActiveCharSettings, FC) end
        if FC.ApplyConfig then FC:ApplyConfig() end
        f:Hide()
        print("|cff00ccff[ForeverClasses]|r Settings saved & applied.")
    end)

    -- Master Refresh Method
    f.Refresh = function()
        UpdateHUDPreview()

        if cardClassColor and cardClassColor.sw then cardClassColor.sw:UpdateValue() end
        if cardHeals and cardHeals.sw then cardHeals.sw:UpdateValue() end
        if cardTextMode then cardTextMode:UpdateValue() end
        if cardFade then cardFade:UpdateValue() end

        if cardSlots then cardSlots:UpdateValue() end
        if cardPulse and cardPulse.sw then cardPulse.sw:UpdateValue() end

        if cardClassEngine and cardClassEngine.sw then cardClassEngine.sw:UpdateValue() end

        if cardLowHp then cardLowHp:UpdateValue() end
        if cardDebuffs and cardDebuffs.sw then cardDebuffs.sw:UpdateValue() end

        for _, card in pairs(moveCards) do
            if card.UpdateValue then card:UpdateValue() end
        end

        SelectTab(currentTab)
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
