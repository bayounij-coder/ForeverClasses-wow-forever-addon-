--[[
    ForeverClasses - ForeverClasses.lua
    Core HUD: Dynamic Health, Power (Mana/Rage/Energy), Upcoming Heals, and Movable Frame
    Engineered for WoW Forever Beta (build 16001 / Midnight 12.0 architecture)
    Includes strict defense against "Secret Value" taint restrictions on combat APIs.
]]--

ForeverClasses = ForeverClasses or {}
local FC = ForeverClasses

local BackdropTemplateString = BackdropTemplateMixin and "BackdropTemplate" or nil

local issecretvalue = _G.issecretvalue or issecretvalue
local issecrettable = _G.issecrettable or issecrettable
local canaccessvalue = _G.canaccessvalue or canaccessvalue

-- Detection helper for WoW 12.0+ / Midnight Secret Values
local function IsSecret(v)
    if v == nil then return false end
    if issecretvalue then
        local ok, res = pcall(issecretvalue, v)
        if ok and res == true then return true end
    end
    if canaccessvalue then
        local ok, res = pcall(canaccessvalue, v)
        if ok and res == false then return true end
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
FC.IsSecret = IsSecret

-- ============================================================================
-- Shield Debug Logger & Copy Window
-- ============================================================================
FC.shieldLogs = FC.shieldLogs or {}
FC.shieldLogEnabled = true
FC.shieldLogChat = false

local function SanitizeForLog(v)
    if v == nil then return "nil" end
    if IsSecret(v) then
        local t = type(v)
        return "<secret " .. tostring(t) .. ">"
    end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        return "<table>"
    else
        return "<" .. tostring(t) .. ">"
    end
end

function FC:Log(tag, fmt, ...)
    if not FC.shieldLogEnabled then return end
    local safeTag = SanitizeForLog(tag or "DEBUG")
    local safeMsg = ""

    local n = select("#", ...)
    if n > 0 then
        local safeArgs = {}
        for i = 1, n do
            local a = select(i, ...)
            table.insert(safeArgs, SanitizeForLog(a))
        end
        local ok, res = pcall(string.format, fmt, unpack(safeArgs))
        if ok and res and not IsSecret(res) then
            safeMsg = res
        else
            safeMsg = tostring(fmt) .. " [" .. table.concat(safeArgs, ", ") .. "]"
        end
    else
        safeMsg = SanitizeForLog(fmt)
    end

    local t = date and date("%H:%M:%S") or tostring(math.floor(GetTime()))
    local line = string.format("[%s][%s] %s", t, safeTag, safeMsg)

    if not IsSecret(line) then
        table.insert(FC.shieldLogs, line)
        if #FC.shieldLogs > 800 then
            table.remove(FC.shieldLogs, 1)
        end
    end

    if FC.shieldLogChat and DEFAULT_CHAT_FRAME and not IsSecret(line) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[FC-Log]|r " .. line)
    end
end
FC.LogShield = FC.Log

function FC:ShowLogDialog()
    if not FC.LogCopyFrame then
        local f = CreateFrame("Frame", "ForeverClassesLogCopyFrame", UIParent, BackdropTemplateString)
        f:SetSize(640, 440)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        f:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
        f:SetBackdropBorderColor(0.2, 0.6, 0.9, 0.8)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        title:SetPoint("TOPLEFT", 16, -12)
        title:SetText("|cff00ccffForeverClasses|r - Combat, Buffs & Cooldowns Debug Logs")

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -4, -4)

        local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        sub:SetTextColor(0.8, 0.8, 0.8)
        sub:SetText("Press |cffffcc00Ctrl+A|r then |cffffcc00Ctrl+C|r to copy all logs:")

        local scroll = CreateFrame("ScrollFrame", "ForeverClassesLogScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -55)
        scroll:SetPoint("BOTTOMRIGHT", -32, 45)

        local editBox = CreateFrame("EditBox", "ForeverClassesLogEditBox", scroll)
        editBox:SetMultiLine(true)
        editBox:SetFontObject("GameFontHighlightSmall")
        editBox:SetWidth(570)
        editBox:SetAutoFocus(false)
        editBox:SetScript("OnEscapePressed", function(self) f:Hide() end)
        scroll:SetScrollChild(editBox)

        local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        clearBtn:SetSize(90, 24)
        clearBtn:SetPoint("BOTTOMLEFT", 16, 12)
        clearBtn:SetText("Clear Logs")
        clearBtn:SetScript("OnClick", function()
            table.wipe(FC.shieldLogs)
            editBox:SetText("")
            FC:Log("SYS", "Logs cleared by user")
            editBox:SetText(table.concat(FC.shieldLogs, "\n"))
        end)

        local copyAllBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        copyAllBtn:SetSize(110, 24)
        copyAllBtn:SetPoint("BOTTOMRIGHT", -16, 12)
        copyAllBtn:SetText("Select All")
        copyAllBtn:SetScript("OnClick", function()
            editBox:SetFocus()
            editBox:HighlightText()
        end)

        f.editBox = editBox
        FC.LogCopyFrame = f
    end

    local cleanLines = {}
    if FC.shieldLogs then
        for i = 1, #FC.shieldLogs do
            local l = FC.shieldLogs[i]
            if l and not IsSecret(l) then
                table.insert(cleanLines, tostring(l))
            end
        end
    end
    local text = (#cleanLines > 0) and table.concat(cleanLines, "\n") or "[No logs recorded yet. Activate a Seal or spell in combat to generate logs.]"
    FC.LogCopyFrame.editBox:SetText(text)
    FC.LogCopyFrame:Show()
    FC.LogCopyFrame.editBox:SetFocus()
    FC.LogCopyFrame.editBox:HighlightText()
end

-- Heal Prediction Calculator for WoW 12.0+ / Midnight
local function InitHealCalculator()
    if FC.healCalculator then return FC.healCalculator end
    if CreateUnitHealPredictionCalculator then
        local ok, calc = pcall(CreateUnitHealPredictionCalculator)
        if ok and calc then
            pcall(function()
                if Enum and Enum.UnitDamageAbsorbClampMode then
                    calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
                end
                if Enum and Enum.UnitHealAbsorbClampMode then
                    calc:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.MaximumHealth)
                end
                if Enum and Enum.UnitHealAbsorbMode then
                    calc:SetHealAbsorbMode(Enum.UnitHealAbsorbMode.Total)
                end
                if Enum and Enum.UnitIncomingHealClampMode then
                    calc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
                end
                if calc.SetIncomingHealOverflowPercent then
                    calc:SetIncomingHealOverflowPercent(1)
                end
            end)
            FC.healCalculator = calc
            return calc
        end
    end
    return nil
end

local function GetIncomingHeal(unit)
    unit = unit or "player"

    local calc = FC.healCalculator or InitHealCalculator()
    if calc and UnitGetDetailedHealPrediction then
        local ok, inc
        local callOk = pcall(function()
            UnitGetDetailedHealPrediction(unit, nil, calc)
            inc = calc:GetTotalIncomingHeals()
        end)
        if callOk and inc ~= nil then
            return inc
        end
    end

    if UnitGetIncomingHeals then
        local ok, inc = pcall(UnitGetIncomingHeals, unit)
        if ok and inc ~= nil then
            return inc
        end
        local ok2, inc2 = pcall(UnitGetIncomingHeals, unit, unit)
        if ok2 and inc2 ~= nil then
            return inc2
        end
    end

    return 0
end

-- Known Damage Absorption Shield Spell Database (Classic / WoW Forever)
local KNOWN_SHIELD_SPELLS = {
    -- Priest: Power Word: Shield
    [17]    = { base = 44,   spell = "Power Word: Shield", rank = 1 },
    [592]   = { base = 88,   spell = "Power Word: Shield", rank = 2 },
    [600]   = { base = 158,  spell = "Power Word: Shield", rank = 3 },
    [3747]  = { base = 234,  spell = "Power Word: Shield", rank = 4 },
    [6065]  = { base = 301,  spell = "Power Word: Shield", rank = 5 },
    [6066]  = { base = 381,  spell = "Power Word: Shield", rank = 6 },
    [10898] = { base = 484,  spell = "Power Word: Shield", rank = 7 },
    [10899] = { base = 605,  spell = "Power Word: Shield", rank = 8 },
    [10900] = { base = 763,  spell = "Power Word: Shield", rank = 9 },
    [10901] = { base = 942,  spell = "Power Word: Shield", rank = 10 },
    [25217] = { base = 1115, spell = "Power Word: Shield", rank = 11 },
    [25218] = { base = 1260, spell = "Power Word: Shield", rank = 12 },

    -- Mage: Ice Barrier
    [11426] = { base = 438,  spell = "Ice Barrier", rank = 1 },
    [13031] = { base = 549,  spell = "Ice Barrier", rank = 2 },
    [13032] = { base = 678,  spell = "Ice Barrier", rank = 3 },
    [13033] = { base = 818,  spell = "Ice Barrier", rank = 4 },
    [27134] = { base = 964,  spell = "Ice Barrier", rank = 5 },
    [33405] = { base = 1077, spell = "Ice Barrier", rank = 6 },

    -- Mage: Mana Shield
    [1463]  = { base = 120,  spell = "Mana Shield", rank = 1 },
    [8494]  = { base = 210,  spell = "Mana Shield", rank = 2 },
    [8495]  = { base = 300,  spell = "Mana Shield", rank = 3 },
    [10191] = { base = 390,  spell = "Mana Shield", rank = 4 },
    [10192] = { base = 480,  spell = "Mana Shield", rank = 5 },
    [10193] = { base = 570,  spell = "Mana Shield", rank = 6 },

    -- Warlock: Shadow Ward
    [6229]  = { base = 290,  spell = "Shadow Ward", rank = 1 },
    [11739] = { base = 470,  spell = "Shadow Ward", rank = 2 },
    [11740] = { base = 675,  spell = "Shadow Ward", rank = 3 },
    [28610] = { base = 875,  spell = "Shadow Ward", rank = 4 },

    -- Warlock: Sacrifice (Voidwalker Shield)
    [7812]  = { base = 305,  spell = "Sacrifice", rank = 1 },
    [19438] = { base = 510,  spell = "Sacrifice", rank = 2 },
    [19440] = { base = 770,  spell = "Sacrifice", rank = 3 },
    [19441] = { base = 1085, spell = "Sacrifice", rank = 4 },
    [19442] = { base = 1460, spell = "Sacrifice", rank = 5 },
    [19443] = { base = 1905, spell = "Sacrifice", rank = 6 },
    [22355] = { base = 2390, spell = "Sacrifice", rank = 7 },
}
FC.KNOWN_SHIELD_SPELLS = KNOWN_SHIELD_SPELLS

local PWS_RANK_SPELLS = { 25218, 25217, 10901, 10900, 10899, 10898, 6066, 6065, 3747, 600, 592, 17 }
local ICE_BARRIER_RANK_SPELLS = { 33405, 27134, 13033, 13032, 13031, 11426 }
local MANA_SHIELD_RANK_SPELLS = { 10193, 10192, 10191, 8495, 8494, 1463 }
local SHADOW_WARD_RANK_SPELLS = { 28610, 11740, 11739, 6229 }

local function IsShieldSpell(cleanName)
    if not cleanName then return false end
    cleanName = string.lower(cleanName)
    return cleanName == "power word: shield"
        or cleanName == "ice barrier"
        or cleanName == "mana shield"
        or cleanName == "shadow ward"
        or cleanName == "divine aegis"
        or cleanName == "contingency plan"
        or cleanName == "sacrifice"
        or cleanName:find("protection") ~= nil
end
FC.IsShieldSpell = IsShieldSpell

function FC:ResolveShieldMaxAmount(spellID, spellName)
    local clean = string.lower(tostring(spellName or ""))

    -- 1. If spellID is a specific higher rank spell ID
    if spellID and KNOWN_SHIELD_SPELLS[spellID] and spellID ~= 17 and spellID ~= 11426 and spellID ~= 1463 and spellID ~= 6229 then
        return KNOWN_SHIELD_SPELLS[spellID].base
    end

    -- 2. Out of combat: Try C_TooltipInfo scanning for live exact amount (captures SP / talent bonuses)
    if not (InCombatLockdown and InCombatLockdown()) and C_TooltipInfo and C_TooltipInfo.GetSpellByID and spellID and spellID > 0 then
        local ok, data = pcall(C_TooltipInfo.GetSpellByID, spellID)
        if ok and data and data.lines then
            for _, line in ipairs(data.lines) do
                local txt = line.leftText
                if txt then
                    local num = txt:match("absorb[s]?%s+(%d+)")
                             or txt:match("absorbe[s]?%s+(%d+)")
                             or txt:match("(%d+)%s+[dD]amage")
                    if num then
                        local val = tonumber(num)
                        if val and val > 0 then return val end
                    end
                end
            end
        end
    end

    -- 3. Priest: Power Word: Shield rank resolution
    if clean:find("power word: shield") or spellID == 17 or (spellID and KNOWN_SHIELD_SPELLS[spellID] and KNOWN_SHIELD_SPELLS[spellID].spell == "Power Word: Shield") then
        for _, id in ipairs(PWS_RANK_SPELLS) do
            if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
                return KNOWN_SHIELD_SPELLS[id] and KNOWN_SHIELD_SPELLS[id].base or 44
            end
        end
        -- Fallback to character level if spellbook rank check is ambiguous
        local lvl = (UnitLevel and UnitLevel("player")) or 1
        if lvl >= 60 then return 942
        elseif lvl >= 54 then return 763
        elseif lvl >= 48 then return 605
        elseif lvl >= 42 then return 484
        elseif lvl >= 36 then return 381
        elseif lvl >= 30 then return 301
        elseif lvl >= 24 then return 234
        elseif lvl >= 18 then return 158
        elseif lvl >= 12 then return 88
        else return 44 end
    end

    -- 4. Mage: Ice Barrier rank resolution
    if clean:find("ice barrier") or spellID == 11426 or (spellID and KNOWN_SHIELD_SPELLS[spellID] and KNOWN_SHIELD_SPELLS[spellID].spell == "Ice Barrier") then
        for _, id in ipairs(ICE_BARRIER_RANK_SPELLS) do
            if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
                return KNOWN_SHIELD_SPELLS[id] and KNOWN_SHIELD_SPELLS[id].base or 438
            end
        end
        local lvl = (UnitLevel and UnitLevel("player")) or 1
        if lvl >= 58 then return 818
        elseif lvl >= 52 then return 678
        elseif lvl >= 46 then return 549
        else return 438 end
    end

    -- 5. Mage: Mana Shield rank resolution
    if clean:find("mana shield") or spellID == 1463 or (spellID and KNOWN_SHIELD_SPELLS[spellID] and KNOWN_SHIELD_SPELLS[spellID].spell == "Mana Shield") then
        for _, id in ipairs(MANA_SHIELD_RANK_SPELLS) do
            if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
                return KNOWN_SHIELD_SPELLS[id] and KNOWN_SHIELD_SPELLS[id].base or 120
            end
        end
        local lvl = (UnitLevel and UnitLevel("player")) or 1
        if lvl >= 60 then return 570
        elseif lvl >= 52 then return 480
        elseif lvl >= 44 then return 390
        elseif lvl >= 36 then return 300
        elseif lvl >= 28 then return 210
        else return 120 end
    end

    -- 6. Warlock: Shadow Ward rank resolution
    if clean:find("shadow ward") or spellID == 6229 or (spellID and KNOWN_SHIELD_SPELLS[spellID] and KNOWN_SHIELD_SPELLS[spellID].spell == "Shadow Ward") then
        for _, id in ipairs(SHADOW_WARD_RANK_SPELLS) do
            if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
                return KNOWN_SHIELD_SPELLS[id] and KNOWN_SHIELD_SPELLS[id].base or 290
            end
        end
        local lvl = (UnitLevel and UnitLevel("player")) or 1
        if lvl >= 60 then return 875
        elseif lvl >= 52 then return 675
        elseif lvl >= 42 then return 470
        else return 290 end
    end

    -- Default fallback for any known spellID
    if spellID and KNOWN_SHIELD_SPELLS[spellID] then
        return KNOWN_SHIELD_SPELLS[spellID].base
    end

    return 44
end

local function GetAbsorbData(unit)
    unit = unit or "player"

    -- 1. Blizzard native UnitGetTotalAbsorbs (Authoritative remaining damage absorb on unit)
    if UnitGetTotalAbsorbs then
        local ok, abs = pcall(UnitGetTotalAbsorbs, unit)
        if ok and abs ~= nil then
            if IsSecret(abs) then
                -- Secret value in combat: pass through directly to C++ widget (StatusBar)
                return abs, false, nil
            elseif type(abs) == "number" then
                if abs > 0 then
                    FC.currentShieldRemaining = abs
                    if not FC.currentShieldMax or FC.currentShieldMax < abs then
                        FC.currentShieldMax = abs
                    end
                    return abs, false, FC.currentShieldMax
                else
                    FC.currentShieldRemaining = 0
                    return 0, false, 0
                end
            end
        end
    end

    -- 2. Modern 12.0 HealPredictionCalculator
    if unit == "player" and FC.healCalculator and UnitGetDetailedHealPrediction then
        local ok = pcall(UnitGetDetailedHealPrediction, "player", nil, FC.healCalculator)
        if ok then
            local okA, abs = pcall(FC.healCalculator.GetDamageAbsorbs, FC.healCalculator)
            if okA and abs ~= nil then
                if IsSecret(abs) then
                    return abs, false, nil
                elseif type(abs) == "number" then
                    if abs > 0 then
                        FC.currentShieldRemaining = abs
                        if not FC.currentShieldMax or FC.currentShieldMax < abs then
                            FC.currentShieldMax = abs
                        end
                        return abs, false, FC.currentShieldMax
                    else
                        FC.currentShieldRemaining = 0
                        return 0, false, 0
                    end
                end
            end
        end
    end

    -- 3. Modern 12.0 Direct UnitGetDetailedHealPrediction fallback
    if UnitGetDetailedHealPrediction then
        local ok, dmgAbs, _, totAbs = pcall(UnitGetDetailedHealPrediction, unit)
        local val = totAbs or dmgAbs
        if ok and val ~= nil then
            if IsSecret(val) then
                return val, false, nil
            elseif type(val) == "number" then
                if val > 0 then
                    FC.currentShieldRemaining = val
                    if not FC.currentShieldMax or FC.currentShieldMax < val then
                        FC.currentShieldMax = val
                    end
                    return val, false, FC.currentShieldMax
                else
                    FC.currentShieldRemaining = 0
                    return 0, false, 0
                end
            end
        end
    end

    -- 4. Blizzard native PlayerFrameTotalAbsorbBar width ratio fallback
    if (unit == "player" or unit == nil) and PlayerFrameTotalAbsorbBar and PlayerFrameTotalAbsorbBar.IsShown then
        local ok, shown = pcall(PlayerFrameTotalAbsorbBar.IsShown, PlayerFrameTotalAbsorbBar)
        if ok and shown then
            local w = PlayerFrameTotalAbsorbBar:GetWidth()
            local pw = (PlayerFrameHealthBar and PlayerFrameHealthBar:GetWidth()) or 120
            if w and pw and w > 0 and pw > 0 then
                local ratio = w / pw
                local maxH = (FC.HealthBar and select(2, FC.HealthBar:GetMinMaxValues())) or 100
                local eff = math.floor(ratio * maxH + 0.5)
                FC.currentShieldRemaining = eff
                return eff, false, eff
            end
        end
    end

    -- 5. Fallback: Live event-driven shield detection
    if unit == "player" and FC.currentShieldRemaining and not IsSecret(FC.currentShieldRemaining) and FC.currentShieldRemaining > 0 then
        return FC.currentShieldRemaining, false, FC.currentShieldMax or FC.currentShieldRemaining
    end

    return 0, false, 0
end
FC.GetAbsorbData = GetAbsorbData

local function GetTotalAbsorbs(unit)
    local abs, _, tot = GetAbsorbData(unit)
    return abs
end

-- ============================================================================
-- Health Colors & Resolution (Classic Emerald Green or Player Class Color)
-- ============================================================================

function FC:GetHealthColor()
    if ForeverClassesDB and ForeverClassesDB.classColorHealth then
        local _, classToken = UnitClass("player")
        if classToken then
            if C_ClassColor and C_ClassColor.GetClassColor then
                local ok, color = pcall(C_ClassColor.GetClassColor, classToken)
                if ok and color and color.r then
                    return color.r, color.g, color.b
                end
            end
            if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                local c = RAID_CLASS_COLORS[classToken]
                return c.r, c.g, c.b
            end
        end
    end
    -- Default classic emerald green
    return 0.12, 0.82, 0.24
end

function FC:GetHealPredictionColor()
    if ForeverClassesDB and ForeverClassesDB.classColorHealth then
        local hr, hg, hb = FC:GetHealthColor()
        return hr, hg, hb, 0.55
    end
    -- Default subtle emerald green prediction
    return 0.25, 1.00, 0.50, 0.70
end

-- ============================================================================
-- Power Colors & Resolution (Mana Blue, Rage Red, Energy Yellow)
-- ============================================================================

function FC:GetPowerColor()
    -- 1. Check active shapeshift form for Druids
    local _, classToken = UnitClass("player")
    if classToken == "DRUID" then
        local form = GetShapeshiftForm and GetShapeshiftForm()
        if form == 1 then
            return 0.90, 0.20, 0.20, 1 -- Bear Form (Rage)
        elseif form == 3 then
            return 1.00, 0.85, 0.10, 3 -- Cat Form (Energy)
        else
            return 0.00, 0.55, 1.00, 0 -- Caster / Travel / Moonkin (Mana)
        end
    end

    -- 2. Fixed pure classes (Classic / Forever specs)
    if classToken == "WARRIOR" then
        return 0.90, 0.20, 0.20, 1 -- Rage
    elseif classToken == "ROGUE" then
        return 1.00, 0.85, 0.10, 3 -- Energy
    elseif classToken == "PALADIN" or classToken == "PRIEST" or classToken == "MAGE" or classToken == "WARLOCK" or classToken == "HUNTER" or classToken == "SHAMAN" then
        return 0.00, 0.55, 1.00, 0 -- Mana
    end

    -- 3. Dynamic unit power check (guarded against secret values)
    local powerType, powerToken
    pcall(function() powerType, powerToken = UnitPowerType("player") end)
    if not IsSecret(powerToken) and not IsSecret(powerType) then
        if powerToken == "RAGE" or powerType == 1 or (Enum and Enum.PowerType and powerType == Enum.PowerType.Rage) then
            return 0.90, 0.20, 0.20, 1
        elseif powerToken == "ENERGY" or powerType == 3 or (Enum and Enum.PowerType and powerType == Enum.PowerType.Energy) then
            return 1.00, 0.85, 0.10, 3
        elseif powerToken == "MANA" or powerType == 0 or (Enum and Enum.PowerType and powerType == Enum.PowerType.Mana) then
            return 0.00, 0.55, 1.00, 0
        end
    end

    -- 4. Blizzard global table fallback
    if powerToken and not IsSecret(powerToken) and PowerBarColor and PowerBarColor[powerToken] then
        local c = PowerBarColor[powerToken]
        return c.r or c[1], c.g or c[2], c.b or c[3], powerType or 0
    end
    if powerType and not IsSecret(powerType) and PowerBarColor and PowerBarColor[powerType] then
        local c = PowerBarColor[powerType]
        return c.r or c[1], c.g or c[2], c.b or c[3], powerType
    end

    -- Default fallback: Classic Mana Blue (Never white)
    return 0.00, 0.55, 1.00, 0
end

-- ============================================================================
-- Number Formatting & Safe Secret-Aware Text Display
-- ============================================================================

local function FormatValue(val)
    if IsSecret(val) or val == nil then return val end
    local num = tonumber(val)
    if not num or num < 0 then return "0" end
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 10000 then
        return string.format("%.1fk", num / 1000)
    else
        return tostring(math.floor(num + 0.5))
    end
end

-- ============================================================================
-- Secret-Safe Percentage Helpers (uses Blizzard's ScaleTo100 curve where available)
-- ============================================================================

local function GetHealthPercent(current, max)
    -- 1. Blizzard 12.0+ native secret-safe percentage with ScaleTo100 curve
    if UnitHealthPercent then
        local curve = CurveConstants and CurveConstants.ScaleTo100
        if curve then
            local ok, val = pcall(UnitHealthPercent, "player", true, curve)
            if ok and val ~= nil then
                return val
            end
        end
        local ok, val = pcall(UnitHealthPercent, "player", true)
        if ok and val ~= nil then
            if not IsSecret(val) then
                local num = tonumber(val)
                if num and num <= 1 and num >= 0 then
                    return num * 100
                end
            end
            return val
        end
    end

    -- 2. Regular Lua math when values are not secret
    if current and max and not IsSecret(current) and not IsSecret(max) then
        local curNum = tonumber(current) or 0
        local maxNum = tonumber(max) or 1
        if maxNum > 0 then
            return (curNum / maxNum) * 100
        end
    end

    return nil
end

local function GetPowerPercent(powerType, current, max)
    powerType = powerType or 0

    -- 1. Blizzard 12.0+ native secret-safe power percentage with ScaleTo100 curve
    if UnitPowerPercent then
        local curve = CurveConstants and CurveConstants.ScaleTo100
        if curve then
            local ok, val = pcall(UnitPowerPercent, "player", powerType, false, curve)
            if ok and val ~= nil then
                return val
            end
        end
        local ok, val = pcall(UnitPowerPercent, "player", powerType, false)
        if ok and val ~= nil then
            if not IsSecret(val) then
                local num = tonumber(val)
                if num and num <= 1 and num >= 0 then
                    return num * 100
                end
            end
            return val
        end
    end

    -- 2. Regular Lua math when values are not secret
    if current and max and not IsSecret(current) and not IsSecret(max) then
        local curNum = tonumber(current) or 0
        local maxNum = tonumber(max) or 1
        if maxNum > 0 then
            return (curNum / maxNum) * 100
        end
    end

    return nil
end

-- ============================================================================
-- Safe Status Text Updaters (Health & Power)
-- ============================================================================

local function UpdateHealthText(fontString, current, max, mode)
    if not fontString then return end
    mode = mode or (ForeverClassesDB and ForeverClassesDB.textMode) or "BOTH"

    if mode == "NONE" then
        fontString:SetText("")
        return
    end

    local pct = GetHealthPercent(current, max)

    if mode == "PERCENT" then
        if pct ~= nil then
            local ok = pcall(fontString.SetFormattedText, fontString, "%.0f%%", pct)
            if not ok then
                pcall(fontString.SetFormattedText, fontString, "%s%%", pct)
            end
            return
        end
        pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
        return
    end

    if mode == "NUMERIC" then
        local ok = pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
        if not ok then
            pcall(fontString.SetText, fontString, current)
        end
        return
    end

    if mode == "SYNC" then
        local showText = GetCVar and GetCVar("statusText")
        if showText == "0" then
            fontString:SetText("")
            return
        end
        local displayMode = (GetCVar and GetCVar("statusTextDisplay")) or "BOTH"
        if displayMode == "NUMERIC" then
            pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
        elseif displayMode == "PERCENT" then
            if pct ~= nil then
                local ok = pcall(fontString.SetFormattedText, fontString, "%.0f%%", pct)
                if not ok then pcall(fontString.SetFormattedText, fontString, "%s%%", pct) end
            else
                pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
            end
        elseif displayMode == "NONE" then
            fontString:SetText("")
        else -- "BOTH"
            if pct ~= nil then
                local ok = pcall(fontString.SetFormattedText, fontString, "%s / %s (%.0f%%)", current, max or "", pct)
                if ok then return end
            end
            pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
        end
        return
    end

    -- "BOTH" (Default)
    if pct ~= nil then
        local ok = pcall(fontString.SetFormattedText, fontString, "%s / %s (%.0f%%)", current, max or "", pct)
        if ok then return end
        local ok2 = pcall(fontString.SetFormattedText, fontString, "%s / %s (%s%%)", current, max or "", pct)
        if ok2 then return end
    end
    pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
end

local function UpdatePowerText(fontString, current, max, powerType, mode)
    if not fontString then return end
    mode = mode or (ForeverClassesDB and ForeverClassesDB.textMode) or "BOTH"

    if mode == "NONE" then
        fontString:SetText("")
        return
    end

    local pct = GetPowerPercent(powerType, current, max)

    if mode == "PERCENT" then
        if pct ~= nil then
            local ok = pcall(fontString.SetFormattedText, fontString, "%.0f%%", pct)
            if not ok then
                pcall(fontString.SetFormattedText, fontString, "%s%%", pct)
            end
            return
        end
        pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
        return
    end

    if mode == "NUMERIC" then
        local ok = pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
        if not ok then
            pcall(fontString.SetText, fontString, current)
        end
        return
    end

    if mode == "SYNC" then
        local showText = GetCVar and GetCVar("statusText")
        if showText == "0" then
            fontString:SetText("")
            return
        end
        local displayMode = (GetCVar and GetCVar("statusTextDisplay")) or "BOTH"
        if displayMode == "NUMERIC" then
            pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
        elseif displayMode == "PERCENT" then
            if pct ~= nil then
                local ok = pcall(fontString.SetFormattedText, fontString, "%.0f%%", pct)
                if not ok then pcall(fontString.SetFormattedText, fontString, "%s%%", pct) end
            else
                pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
            end
        elseif displayMode == "NONE" then
            fontString:SetText("")
        else -- "BOTH"
            if pct ~= nil then
                local ok = pcall(fontString.SetFormattedText, fontString, "%s / %s (%.0f%%)", current, max or "", pct)
                if ok then return end
            end
            pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
        end
        return
    end

    -- "BOTH" (Default)
    if pct ~= nil then
        local ok = pcall(fontString.SetFormattedText, fontString, "%s / %s (%.0f%%)", current, max or "", pct)
        if ok then return end
        local ok2 = pcall(fontString.SetFormattedText, fontString, "%s / %s (%s%%)", current, max or "", pct)
        if ok2 then return end
    end
    pcall(fontString.SetFormattedText, fontString, "%s / %s", current, max or "")
end

-- ============================================================================
-- Authentic Blizzard Combo Points Texture Resolver
-- ============================================================================

local function ApplyComboPointTextures(bgTex, fillTex)
    local candidates = {
        { bg = "ComboPoints-PointBg", fill = "ComboPoints-ComboPoint" },
        { bg = "uf-roguecp-bg", fill = "uf-roguecp-icon-red" },
        { bg = "ClassOverlay-ComboPoint-Off", fill = "ClassOverlay-ComboPoint" },
    }

    local chosenBg = "ComboPoints-PointBg"
    local chosenFill = "ComboPoints-ComboPoint"

    if C_Texture and C_Texture.GetAtlasInfo then
        for _, c in ipairs(candidates) do
            local okBg, infoBg = pcall(C_Texture.GetAtlasInfo, c.bg)
            local okFill, infoFill = pcall(C_Texture.GetAtlasInfo, c.fill)
            if okBg and infoBg and okFill and infoFill then
                chosenBg = c.bg
                chosenFill = c.fill
                break
            end
        end
    end

    FC.resolvedComboBgAtlas = chosenBg
    FC.resolvedComboFillAtlas = chosenFill

    local ok1 = pcall(bgTex.SetAtlas, bgTex, chosenBg, false)
    local ok2 = pcall(fillTex.SetAtlas, fillTex, chosenFill, false)

    if not ok1 or not bgTex:GetTexture() then
        bgTex:SetTexture("Interface\\ComboFrame\\ComboPoint")
        bgTex:SetTexCoord(0, 0.5, 0, 1)
    end
    if not ok2 or not fillTex:GetTexture() then
        fillTex:SetTexture("Interface\\ComboFrame\\ComboPoint")
        fillTex:SetTexCoord(0.5, 1, 0, 1)
    end
end

local function SetupScale(scaleAnim, fromX, fromY, toX, toY)
    if scaleAnim.SetScaleFrom then
        scaleAnim:SetScaleFrom(fromX, fromY)
    elseif scaleAnim.SetFromScale then
        scaleAnim:SetFromScale(fromX, fromY)
    end

    if scaleAnim.SetScaleTo then
        scaleAnim:SetScaleTo(toX, toY)
    elseif scaleAnim.SetToScale then
        scaleAnim:SetToScale(toX, toY)
    end

    pcall(scaleAnim.SetOrigin, scaleAnim, "CENTER", 0, 0)
end

-- ============================================================================
-- Auto-Anchor Blizzard Native Cooldown Manager (EssentialCooldownViewer)
-- ============================================================================

function FC:AttachEssentialCooldowns()
    if InCombatLockdown and InCombatLockdown() then return end
    if not ForeverClassesDB or ForeverClassesDB.attachCooldownManager == false then return end
    if not FC.Frame then return end

    -- Load Blizzard_CooldownViewer module if not yet loaded
    if not EssentialCooldownViewer and not _G["EssentialCooldownViewer"] then
        if C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
        elseif UIParentLoadAddOn then
            pcall(UIParentLoadAddOn, "Blizzard_CooldownViewer")
        end
    end

    local viewer = EssentialCooldownViewer or _G["EssentialCooldownViewer"]
    if viewer then
        local offset = (ForeverClassesDB and ForeverClassesDB.cdAttachOffset) or 4
        viewer:ClearAllPoints()
        viewer:SetPoint("BOTTOM", FC.Frame, "TOP", 0, offset)
        pcall(viewer.SetUserPlaced, viewer, true)
    end
end

-- ============================================================================
-- Out-of-Combat Auto Fade (Resting Opacity Controller)
-- ============================================================================

local fadeCheckTimer = 0
local targetFadeAlpha = 1.0

function FC:GetTargetAutoFadeAlpha(debugReasons)
    -- 1. Feature disabled: always full brightness
    if not ForeverClassesDB or not ForeverClassesDB.autoFade then
        if debugReasons then table.insert(debugReasons, "autoFade DISABLED (type /fc fade or enable in GUI)") end
        return 1.0
    end

    -- 2. Test Simulations (keep solid 1.0 during active previews)
    if FC.testLowHealth or FC.testIncomingHeal or FC.testComboPoints or FC.testTotems or FC.testAbsorb then
        if debugReasons then table.insert(debugReasons, "Test preview active") end
        return 1.0
    end

    -- 3. Dedicated fade test simulation (/fc testfade)
    if FC.testAutoFade then
        if debugReasons then table.insert(debugReasons, "Test fade simulation active (/fc testfade)") end
        return ForeverClassesDB.autoFadeAlpha or 0.35
    end

    -- 4. Actively dragging frame or Config window open
    if FC.Frame and FC.Frame.isMoving then
        if debugReasons then table.insert(debugReasons, "Frame is being dragged") end
        return 1.0
    end
    if FC.ConfigWindow and FC.ConfigWindow:IsShown() then
        if debugReasons then table.insert(debugReasons, "Config window is open") end
        return 1.0
    end

    -- 5. Quick-swap drawer is open
    if FC.FlyoutBar and FC.FlyoutBar:IsShown() then
        if debugReasons then table.insert(debugReasons, "Flyout quick-swap bar is open") end
        return 1.0
    end

    -- 6. In Combat: ALWAYS 1.0 (Strictly taint-free check)
    if (InCombatLockdown and InCombatLockdown()) or FC.inCombat or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        if debugReasons then table.insert(debugReasons, "In Combat (Lockdown or UnitAffectingCombat)") end
        return 1.0
    end

    -- 7. Player has an active Target: 1.0
    if UnitExists and UnitExists("target") then
        if debugReasons then table.insert(debugReasons, "Target selected (UnitExists('target') == true)") end
        return 1.0
    end

    -- 8. Player is Dead or Ghost
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        if debugReasons then table.insert(debugReasons, "Player is Dead or Ghost") end
        return 1.0
    end

    -- 9. Player is Wounded (Health < MaxHealth)
    local curH, maxH
    pcall(function()
        curH = UnitHealth("player")
        maxH = UnitHealthMax("player")
    end)
    if curH and maxH and not (IsSecret and (IsSecret(curH) or IsSecret(maxH))) then
        local numCur = tonumber(curH)
        local numMax = tonumber(maxH)
        if numCur and numMax and numMax > 0 then
            local missingH = numMax - numCur
            if missingH >= 5 and missingH > (numMax * 0.01) then
                if debugReasons then table.insert(debugReasons, string.format("Wounded: %d/%d HP (missing %d)", numCur, numMax, missingH)) end
                return 1.0
            end
        end
    end

    -- 10. Player's Power is not at resting state:
    -- Rage (1) or Runic Power (6): active if > 5
    -- Mana (0), Energy (3), Focus (2): active if missing >= 15 and > 2%
    local curPower, maxPower, powerType
    pcall(function()
        curPower = UnitPower("player")
        maxPower = UnitPowerMax("player")
        powerType = UnitPowerType("player")
    end)
    if curPower and not (IsSecret and IsSecret(curPower)) then
        local numP = tonumber(curPower)
        local numMaxP = tonumber(maxPower)
        if numP then
            if powerType == 1 or powerType == 6 then
                if numP >= 5 then
                    if debugReasons then table.insert(debugReasons, string.format("Rage/RP active: %d", numP)) end
                    return 1.0
                end
            else
                if numMaxP and numMaxP > 0 then
                    local missingP = numMaxP - numP
                    if missingP >= 15 and missingP > (numMaxP * 0.02) then
                        if debugReasons then table.insert(debugReasons, string.format("Power missing: %d/%d (missing %d)", numP, numMaxP, missingP)) end
                        return 1.0
                    end
                end
            end
        end
    end

    -- 11. Player is Casting or Channeling
    local isCasting = false
    pcall(function()
        if UnitCastingInfo and UnitCastingInfo("player") then isCasting = true end
        if not isCasting and UnitChannelInfo and UnitChannelInfo("player") then isCasting = true end
    end)
    if isCasting then
        if debugReasons then table.insert(debugReasons, "Player is casting or channeling") end
        return 1.0
    end

    -- Resting / Idle state: return configured resting opacity
    if debugReasons then table.insert(debugReasons, "Resting / Idle state: Auto-Fade ACTIVE") end
    return ForeverClassesDB.autoFadeAlpha or 0.35
end

function FC:RequestFadeCheck()
    fadeCheckTimer = 10
    if (InCombatLockdown and InCombatLockdown()) or FC.inCombat then
        if FC.Frame then FC.Frame:SetAlpha(1.0) end
        targetFadeAlpha = 1.0
    end
end

function FC:ProcessAutoFade(elapsed)
    if not FC.Frame then return end

    -- 1. If feature disabled: ensure full opacity
    if not ForeverClassesDB or not ForeverClassesDB.autoFade then
        if FC.Frame:GetAlpha() ~= 1.0 then
            FC.Frame:SetAlpha(1.0)
        end
        return
    end

    -- 2. In Combat Lockdown: Instant snap to 1.0, no lerp delay
    if (InCombatLockdown and InCombatLockdown()) or FC.inCombat then
        if FC.Frame:GetAlpha() ~= 1.0 then
            FC.Frame:SetAlpha(1.0)
        end
        targetFadeAlpha = 1.0
        return
    end

    -- 3. Throttle state conditions to ~12 times a second (virtually 0% CPU)
    fadeCheckTimer = fadeCheckTimer + (elapsed or 0.016)
    if fadeCheckTimer >= 0.08 then
        fadeCheckTimer = 0
        targetFadeAlpha = FC:GetTargetAutoFadeAlpha()
    end

    -- 4. Smooth 60fps exponential interpolation
    local currentAlpha = FC.Frame:GetAlpha()
    local diff = targetFadeAlpha - currentAlpha
    if math.abs(diff) > 0.005 then
        local step = (elapsed or 0.016) * 6.0
        if step > 1 then step = 1 end
        FC.Frame:SetAlpha(currentAlpha + (diff * step))
    elseif currentAlpha ~= targetFadeAlpha then
        FC.Frame:SetAlpha(targetFadeAlpha)
    end
end

-- ============================================================================
-- Create Main Resource Frame
-- ============================================================================

function FC:CreateHUD()
    if FC.Frame then return end

    local db = ForeverClassesDB
    local totalHeight = db.healthHeight + db.powerHeight + 5

    -- Main Container Frame
    local frame = CreateFrame("Frame", "ForeverClassesFrame", UIParent, BackdropTemplateString)
    frame:SetSize(db.barWidth + 6, totalHeight + 6)
    frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER", db.x or 0, db.y or -140)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    -- Clean Dark Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
    frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.9)

    -- Drag & Move Handlers
    frame:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local mode = ForeverClassesDB.movementMode

        if mode == "LOCKED" then
            return
        elseif mode == "MODIFIER" then
            local mod = ForeverClassesDB.modifierKey
            if (mod == "ALT" and IsAltKeyDown()) or
               (mod == "SHIFT" and IsShiftKeyDown()) or
               (mod == "CTRL" and IsControlKeyDown()) then
                self:StartMoving()
                self.isMoving = true
            end
        elseif mode == "FREE" then
            self:StartMoving()
            self.isMoving = true
        end
    end)

    frame:SetScript("OnMouseUp", function(self, button)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
            local point, _, relPoint, x, y = self:GetPoint()
            ForeverClassesDB.point = point or "CENTER"
            ForeverClassesDB.relativePoint = relPoint or "CENTER"
            ForeverClassesDB.x = math.floor(x + 0.5)
            ForeverClassesDB.y = math.floor(y + 0.5)
            if FC.AttachEssentialCooldowns then
                pcall(FC.AttachEssentialCooldowns, FC)
            end
        end
    end)

    frame:SetScript("OnHide", function(self)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
        end
    end)

    -- Out-of-Combat Auto Fade & Real-Time Combat Shield Tracker (25 FPS live engine poll)
    local shieldUpdateTicker = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        if FC.ProcessAutoFade then
            FC:ProcessAutoFade(elapsed)
        end

        -- Real-time Combat Shield Tracker
        -- When a shield is active or in combat, poll every 0.04s so absorbed hits dynamically shrink the bar immediately!
        local inCombat = (InCombatLockdown and InCombatLockdown())
        if inCombat or FC.hasActiveShield or (FC.currentShieldRemaining and not IsSecret(FC.currentShieldRemaining) and FC.currentShieldRemaining > 0) then
            shieldUpdateTicker = shieldUpdateTicker + elapsed
            if shieldUpdateTicker >= 0.04 then
                shieldUpdateTicker = 0
                if FC.UpdateHealth then
                    FC:UpdateHealth()
                end
                if FC.needsCooldownRefresh then
                    FC.needsCooldownRefresh = false
                    if FC.UpdateCooldowns then
                        pcall(FC.UpdateCooldowns, FC)
                    end
                end
            end
        else
            shieldUpdateTicker = 0
        end
    end)

    -- Tooltip on hover when unlocked
    frame:SetScript("OnEnter", function(self)
        if ForeverClassesDB.movementMode ~= "LOCKED" then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("|cff00ccffForeverClasses|r Resource Bar", 1, 1, 1)
            if ForeverClassesDB.movementMode == "FREE" then
                GameTooltip:AddLine("Left-click and drag to move panel.", 0.2, 1, 0.2)
            else
                GameTooltip:AddLine(string.format("Hold %s and left-click to move.", ForeverClassesDB.modifierKey), 1, 0.8, 0.2)
            end
            GameTooltip:AddLine("Type |cff00ff00/fc|r for settings or /fc lock to lock.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Initialize Modern 12.0 HealPredictionCalculator
    if not FC.healCalculator and CreateUnitHealPredictionCalculator then
        local ok, calc = pcall(CreateUnitHealPredictionCalculator)
        if ok and calc then
            FC.healCalculator = calc
        end
    end

    -- ========================================================================
    -- Health Bar (Primary)
    -- ========================================================================
    local healthBar = CreateFrame("StatusBar", nil, frame)
    healthBar:SetSize(db.barWidth, db.healthHeight)
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:GetStatusBarTexture():SetHorizTile(false)
    local hr, hg, hb = FC:GetHealthColor()
    healthBar:SetStatusBarColor(hr, hg, hb)
    if healthBar:GetStatusBarTexture() then
        healthBar:GetStatusBarTexture():SetVertexColor(hr, hg, hb)
    end
    healthBar:SetFrameLevel(frame:GetFrameLevel() + 2)
    healthBar:SetClipsChildren(true)

    -- Health Background
    local healthBg = frame:CreateTexture(nil, "BACKGROUND")
    healthBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    healthBg:SetSize(db.barWidth, db.healthHeight)
    healthBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBg:SetVertexColor(hr * 0.22, hg * 0.22, hb * 0.22, 0.75)

    -- Upcoming Heals (StatusBar widget anchored to current health)
    local healPrediction = CreateFrame("StatusBar", "ForeverClassesHealPredictionBar", healthBar)
    healPrediction:SetSize(db.barWidth, db.healthHeight)
    healPrediction:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local predR, predG, predB, predA = FC:GetHealPredictionColor()
    healPrediction:SetStatusBarColor(predR, predG, predB, predA)
    if healPrediction:GetStatusBarTexture() then
        healPrediction:GetStatusBarTexture():SetHorizTile(false)
        healPrediction:GetStatusBarTexture():SetVertexColor(predR, predG, predB, predA)
    end
    healPrediction:SetFrameLevel(healthBar:GetFrameLevel() + 1)

    local healthTex = healthBar:GetStatusBarTexture()
    if healthTex then
        healPrediction:SetPoint("TOPLEFT", healthTex, "TOPRIGHT", 0, 0)
        healPrediction:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMRIGHT", 0, 0)
    else
        healPrediction:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        healPrediction:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
    end
    healPrediction:SetWidth(db.barWidth)
    healPrediction:Hide()

    -- Damage Absorption Shields (StatusBar widget matching modern WoW Midnight / 12.0)
    local absorbBar = CreateFrame("StatusBar", "ForeverClassesAbsorbBar", healthBar)
    absorbBar:SetSize(db.barWidth, db.healthHeight)
    absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    absorbBar:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Fill")
    local absorbTex = absorbBar:GetStatusBarTexture()
    if absorbTex then
        absorbTex:SetHorizTile(false)
        absorbTex:SetVertexColor(0.35, 0.65, 1.0, 0.85)
    end

    local absorbOverlay = absorbBar:CreateTexture("ForeverClassesAbsorbOverlay", "ARTWORK")
    if absorbTex then
        absorbOverlay:SetPoint("TOPLEFT", absorbTex, "TOPLEFT")
        absorbOverlay:SetPoint("BOTTOMRIGHT", absorbTex, "BOTTOMRIGHT")
    else
        absorbOverlay:SetAllPoints(absorbBar)
    end
    pcall(function()
        absorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)
        if absorbOverlay.SetHorizTile then absorbOverlay:SetHorizTile(true) end
        if absorbOverlay.SetVertTile then absorbOverlay:SetVertTile(true) end
    end)
    absorbOverlay.tileSize = 32
    absorbOverlay:SetVertexColor(1, 1, 1, 0.90)
    absorbBar.overlay = absorbOverlay

    if healthTex then
        absorbBar:SetPoint("TOPLEFT", healthTex, "TOPRIGHT", 0, 0)
        absorbBar:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMRIGHT", 0, 0)
    else
        absorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        absorbBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
    end
    absorbBar:SetWidth(db.barWidth)
    absorbBar:Hide()

    local overAbsorbGlow = frame:CreateTexture("ForeverClassesOverAbsorbGlow", "OVERLAY", nil, 7)
    overAbsorbGlow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
    overAbsorbGlow:SetBlendMode("ADD")
    overAbsorbGlow:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMRIGHT", -7, 0)
    overAbsorbGlow:SetPoint("TOPLEFT", healthBar, "TOPRIGHT", -7, 0)
    overAbsorbGlow:SetWidth(16)
    overAbsorbGlow:SetVertexColor(0.2, 0.85, 1.0, 1.0)
    overAbsorbGlow:Hide()

    -- ========================================================================
    -- Power Bar (Secondary: Dynamic Mana / Rage / Energy)
    -- ========================================================================
    local powerBar = CreateFrame("StatusBar", nil, frame)
    powerBar:SetSize(db.barWidth, db.powerHeight)
    powerBar:SetPoint("TOPLEFT", healthBar, "BOTTOMLEFT", 0, -2)
    powerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    powerBar:GetStatusBarTexture():SetHorizTile(false)
    powerBar:SetFrameLevel(frame:GetFrameLevel() + 2)

    -- Resolve power color immediately so it is never white
    local initR, initG, initB, initPowerType = FC:GetPowerColor()
    FC.currentPowerType = initPowerType
    powerBar:SetStatusBarColor(initR, initG, initB)
    if powerBar:GetStatusBarTexture() then
        powerBar:GetStatusBarTexture():SetVertexColor(initR, initG, initB)
    end

    -- Power Background
    local powerBg = powerBar:CreateTexture(nil, "BACKGROUND")
    powerBg:SetAllPoints(powerBar)
    powerBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    powerBg:SetVertexColor(initR * 0.22, initG * 0.22, initB * 0.22, 0.85)

    -- Smooth Power Bar Animation Loop (WoW Forever Continuous Flow)
    powerBar:SetScript("OnUpdate", function(self, elapsed)
        if FC.ProcessSmoothPower then
            FC:ProcessSmoothPower(elapsed)
        end
    end)

    -- ========================================================================
    -- Dedicated Text Overlay Frame (renders above StatusBars)
    -- ========================================================================
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(frame)
    textOverlay:SetFrameLevel(frame:GetFrameLevel() + 10)

    local fontFile = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

    -- Health Text
    local healthText = textOverlay:CreateFontString(nil, "OVERLAY")
    healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
    healthText:SetFont(fontFile, 11, "OUTLINE")
    healthText:SetTextColor(1, 1, 1, 1)
    healthText:SetShadowColor(0, 0, 0, 0.9)
    healthText:SetShadowOffset(1, -1)

    -- Power Text
    local powerText = textOverlay:CreateFontString(nil, "OVERLAY")
    powerText:SetPoint("CENTER", powerBar, "CENTER", 0, 0)
    powerText:SetFont(fontFile, 10, "OUTLINE")
    powerText:SetTextColor(1, 1, 1, 1)
    powerText:SetShadowColor(0, 0, 0, 0.9)
    powerText:SetShadowOffset(1, -1)

    -- ========================================================================
    -- Combo Points Bar (Rogue / Feral - In Combat - Authentic Target Points)
    -- ========================================================================
    local comboFrame = CreateFrame("Frame", "ForeverClassesComboFrame", frame)
    comboFrame:SetSize(db.barWidth, 24)
    comboFrame:SetPoint("TOPLEFT", powerBar, "BOTTOMLEFT", 0, -4)
    comboFrame:SetFrameLevel(frame:GetFrameLevel() + 5)
    comboFrame:EnableMouse(false)
    comboFrame:Hide()

    local pips = {}
    local MAX_COMBO_POINTS = 5
    local circleSize = 16
    local gap = 4
    local totalWidth = (MAX_COMBO_POINTS * circleSize) + ((MAX_COMBO_POINTS - 1) * gap)
    local startLeft = math.floor((db.barWidth - totalWidth) / 2 + 0.5)

    for i = 1, MAX_COMBO_POINTS do
        local pip = CreateFrame("Frame", nil, comboFrame)
        pip:SetSize(circleSize, circleSize)
        pip:EnableMouse(false)
        local left = startLeft + ((i - 1) * (circleSize + gap))
        pip:SetPoint("LEFT", comboFrame, "LEFT", left, 0)

        -- Inactive socket background: Bronze/gold metallic ring with dark interior
        local bg = pip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(pip)
        pip.bg = bg

        -- Active point fill container (scales and animates on appearance)
        local fillHolder = CreateFrame("Frame", nil, pip)
        fillHolder:SetAllPoints(pip)
        fillHolder:Hide()
        pip.fillHolder = fillHolder

        local fill = fillHolder:CreateTexture(nil, "ARTWORK")
        fill:SetAllPoints(fillHolder)
        pip.fill = fill

        -- Apply Blizzard Combo Point Atlases (matches target unit frame points)
        ApplyComboPointTextures(bg, fill)

        -- Pop-in appearance animation (rapid scale pop from 0.3x -> 1.35x, then settle to 1.0x)
        pcall(function()
            local animGroup = fillHolder:CreateAnimationGroup()
            animGroup:SetLooping("NONE")
            pcall(animGroup.SetToFinalAlpha, animGroup, true)

            -- Order 1: Rapid Scale Pop & Fade-In (0.16s)
            local scaleUp = animGroup:CreateAnimation("Scale")
            scaleUp:SetOrder(1)
            scaleUp:SetDuration(0.16)
            SetupScale(scaleUp, 0.3, 0.3, 1.35, 1.35)

            local fadeIn = animGroup:CreateAnimation("Alpha")
            fadeIn:SetOrder(1)
            fadeIn:SetDuration(0.14)
            fadeIn:SetFromAlpha(0.0)
            fadeIn:SetToAlpha(1.0)

            -- Order 2: Smooth settle from 1.35x back to 1.0x (0.10s)
            local scaleDown = animGroup:CreateAnimation("Scale")
            scaleDown:SetOrder(2)
            scaleDown:SetDuration(0.10)
            SetupScale(scaleDown, 1.35, 1.35, 1.0, 1.0)

            animGroup:SetScript("OnFinished", function()
                fillHolder:SetScale(1.0)
                fillHolder:SetAlpha(1.0)
            end)
            animGroup:SetScript("OnStop", function()
                fillHolder:SetScale(1.0)
                fillHolder:SetAlpha(1.0)
            end)

            pip.animGroup = animGroup
        end)

        -- Subtle finisher glow on 5 CP readiness
        local glow = pip:CreateTexture(nil, "OVERLAY")
        glow:SetPoint("CENTER", pip, "CENTER", 0, 0)
        glow:SetSize(circleSize * 1.5, circleSize * 1.5)
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("uf-roguecp-frame-glow") then
            pcall(glow.SetAtlas, glow, "uf-roguecp-frame-glow", false)
        else
            glow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        end
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(1.0, 0.25, 0.10, 0.85)
        glow:Hide()
        pip.glow = glow

        pips[i] = pip
    end

    comboFrame.pips = pips

    -- ========================================================================
    -- Rogue Poison Tracking Dock (Sub-Bar Flanking Combo Points)
    -- ========================================================================
    local poisonBar = CreateFrame("Frame", "ForeverClassesPoisonBar", frame)
    poisonBar:SetSize(db.barWidth, 24)
    poisonBar:SetPoint("TOPLEFT", powerBar, "BOTTOMLEFT", 0, -4)
    poisonBar:SetFrameLevel(frame:GetFrameLevel() + 5)
    poisonBar:Hide()

    local function CreatePoisonSlot(parent, slotID, handLabel, alignPoint, xOffset)
        local slot = CreateFrame("Button", "ForeverClassesPoisonSlot" .. handLabel, parent, BackdropTemplateString)
        slot:SetSize(64, 22)
        slot:SetPoint(alignPoint, parent, alignPoint, xOffset, 0)
        slot.slotID = slotID
        slot.handLabel = handLabel
        slot.state = "MISSING"

        slot:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false,
            tileSize = 0,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        slot:SetBackdropColor(0.08, 0.10, 0.14, 0.95)
        slot:SetBackdropBorderColor(0.0, 0.95, 0.60, 0.95)

        local glyph = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        glyph:SetPoint("LEFT", slot, "LEFT", 4, 0)
        glyph:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        glyph:SetText(handLabel)
        glyph:SetTextColor(0.70, 0.75, 0.85, 0.9)
        slot.glyph = glyph

        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", glyph, "RIGHT", 3, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.icon = icon

        local chargesText = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chargesText:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        chargesText:SetJustifyH("LEFT")
        chargesText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        chargesText:SetText("")
        chargesText:SetTextColor(0.0, 0.95, 0.60, 1.0)
        chargesText:SetShadowColor(0, 0, 0, 0.9)
        chargesText:SetShadowOffset(1, -1)
        slot.chargesText = chargesText

        local plusIcon = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        plusIcon:SetPoint("CENTER", icon, "CENTER", 0, 1)
        plusIcon:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        plusIcon:SetText("+")
        plusIcon:SetTextColor(1.0, 0.25, 0.25, 1.0)
        plusIcon:Hide()
        slot.plusIcon = plusIcon

        local glow = slot:CreateTexture(nil, "OVERLAY")
        glow:SetAllPoints(slot)
        glow:SetColorTexture(1.0, 0.70, 0.10, 0.25)
        glow:Hide()
        slot.glow = glow

        local durationBar = CreateFrame("StatusBar", nil, slot)
        durationBar:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 1, 1)
        durationBar:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
        durationBar:SetHeight(2)
        durationBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        durationBar:SetMinMaxValues(0, 1800)
        durationBar:SetValue(0)
        durationBar:Hide()
        slot.durationBar = durationBar

        slot:RegisterForClicks("RightButtonUp", "LeftButtonUp")
        slot:RegisterForDrag("LeftButton")
        slot:SetScript("OnDragStart", function()
            if frame.StartMoving and (not ForeverClassesDB.movementMode or ForeverClassesDB.movementMode == "FREE" or IsAltKeyDown()) then
                frame:StartMoving()
                frame.isMoving = true
            end
        end)
        slot:SetScript("OnDragStop", function()
            if frame.StopMovingOrSizing and frame.isMoving then
                frame:StopMovingOrSizing()
                frame.isMoving = false
                if FC.SavePosition then FC:SavePosition() end
            end
        end)

        slot:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if InCombatLockdown and InCombatLockdown() then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[ForeverClasses]|r |cffff2020Cannot change poisons while in combat!|r")
                    return
                end
                if FC.TogglePoisonFlyout then
                    FC:TogglePoisonFlyout(self, self.slotID)
                end
            end
        end)

        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            local hand = (self.slotID == 16) and "Main Hand" or "Off Hand"
            GameTooltip:AddLine("|cff00ccffForeverClasses|r - " .. hand .. " Poison", 1, 1, 1)
            if self.poisonName then
                GameTooltip:AddLine("Active: |cffffffff" .. self.poisonName .. "|r", 0, 1, 0.6)
                if self.currentCharges and self.currentCharges > 0 then
                    GameTooltip:AddLine("Charges remaining: |cffffd100" .. self.currentCharges .. "|r")
                end
                if self.currentExp then
                    local mins = math.floor(self.currentExp / 60)
                    local secs = self.currentExp % 60
                    GameTooltip:AddLine(string.format("Time remaining: |cffffd100%d min %02d sec|r", mins, secs))
                end
            else
                GameTooltip:AddLine("|cffff3333No active poison applied|r")
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00e5ffRight-Click:|r Open Poison Quick-Apply", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)

        slot:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        return slot
    end

    local poisonMH = CreatePoisonSlot(poisonBar, 16, "MH", "LEFT", 1)
    local poisonOH = CreatePoisonSlot(poisonBar, 17, "OH", "RIGHT", -1)
    poisonBar.MH = poisonMH
    poisonBar.OH = poisonOH
    FC.PoisonBar = poisonBar
    FC.PoisonMH = poisonMH
    FC.PoisonOH = poisonOH

    local poisonThrottle = 0
    poisonBar:SetScript("OnUpdate", function(self, elapsed)
        poisonThrottle = poisonThrottle + elapsed
        if poisonThrottle >= 1.0 then
            poisonThrottle = 0
            if FC.UpdatePoisonTracker then
                FC:UpdatePoisonTracker()
            end
        end
    end)

    -- ========================================================================
    -- Totem Bar (Shaman Only - Docked beneath Power Bar)
    -- ========================================================================
    local totemBar = CreateFrame("Frame", "ForeverClassesTotemBar", frame)
    totemBar:SetSize(db.barWidth, 44)
    totemBar:SetPoint("TOPLEFT", powerBar, "BOTTOMLEFT", 0, -4)
    totemBar:SetFrameLevel(frame:GetFrameLevel() + 5)
    totemBar:Hide()

    local totemButtons = {}
    local MAX_TOTEM_SLOTS = 4
    local totemSize = 26

    for i = 1, MAX_TOTEM_SLOTS do
        local btn = CreateFrame("Button", "ForeverClassesTotemButton" .. i, totemBar)
        btn:SetSize(totemSize, totemSize)
        btn:EnableMouse(true)

        local icon = btn:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints(btn)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon

        local mask = nil
        if btn.CreateMaskTexture and icon.AddMaskTexture then
            pcall(function()
                mask = btn:CreateMaskTexture()
                mask:SetTexture("Interface\\Masks\\CircleMaskScalable")
                mask:SetAllPoints(icon)
                icon:AddMaskTexture(mask)
                btn.mask = mask
            end)
        end

        local cd = CreateFrame("Cooldown", "$parentCooldown", btn, "CooldownFrameTemplate")
        cd:SetAllPoints(btn)
        cd:SetReverse(true)
        cd:SetDrawEdge(true)
        pcall(cd.SetHideCountdownNumbers, cd, true)
        if mask and cd.AddMaskTexture then
            pcall(cd.AddMaskTexture, cd, mask)
        end
        btn.cooldown = cd

        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetPoint("TOPLEFT", btn, "TOPLEFT", -5, 5)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 5, -5)
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("totem-border") then
            pcall(border.SetAtlas, border, "totem-border")
        else
            border:SetTexture("Interface\\CharacterFrame\\TotemBorder")
        end
        btn.border = border

        local timeText = btn:CreateFontString(nil, "OVERLAY")
        timeText:SetPoint("TOP", btn, "BOTTOM", 0, -2)
        timeText:SetFont(fontFile, 10, "OUTLINE")
        timeText:SetTextColor(1, 1, 1, 1)
        timeText:SetShadowColor(0, 0, 0, 0.9)
        timeText:SetShadowOffset(1, -1)
        btn.timeText = timeText

        btn:SetScript("OnEnter", function(self)
            if not self.slot and not self.testName then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            if self.testName then
                GameTooltip:AddLine(self.testName, 1, 1, 1)
                if self.testElement then
                    GameTooltip:AddLine(self.testElement .. " Totem", 0.7, 0.7, 0.7)
                end
                if self.duration and self.startTime and FC.FormatTotemTime then
                    local rem = math.max(0, (self.startTime + self.duration) - GetTime())
                    GameTooltip:AddLine(string.format("Remaining: %s", FC:FormatTotemTime(rem)), 0.2, 1, 0.2)
                end
                if self.isOutOfRange then
                    GameTooltip:AddLine("Out of Range", 1.0, 0.25, 0.25)
                end
                GameTooltip:Show()
                return
            end
            local ok = false
            if self.slot and GameTooltip.SetTotem then
                ok = pcall(GameTooltip.SetTotem, GameTooltip, self.slot)
            end
            if not ok and self.totemName then
                GameTooltip:AddLine(self.totemName, 1, 1, 1)
                local elemNames = { [1] = "Earth", [2] = "Fire", [3] = "Water", [4] = "Air" }
                local elem = elemNames[self.slot] or "Totem"
                GameTooltip:AddLine(elem .. " Totem", 0.7, 0.7, 0.7)
                if self.duration and self.startTime and self.duration > 0 and FC.FormatTotemTime then
                    local rem = math.max(0, (self.startTime + self.duration) - GetTime())
                    GameTooltip:AddLine(string.format("Remaining: %s", FC:FormatTotemTime(rem)), 0.2, 1, 0.2)
                end
            end
            if self.isOutOfRange then
                GameTooltip:AddLine("Out of Range", 1.0, 0.25, 0.25)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        totemButtons[i] = btn
    end

    totemBar.buttons = totemButtons
    totemBar.timer = 0
    totemBar:SetScript("OnUpdate", function(self, elapsed)
        self.timer = (self.timer or 0) + (elapsed or 0.05)
        if self.timer >= 0.15 then
            self.timer = 0
            if FC.UpdateTotemTimes then
                FC:UpdateTotemTimes()
            end
        end
    end)

    -- ========================================================================
    -- Docking Anchor for Phase 2 (Abilities Tracker)
    -- ========================================================================
    local abilityAnchor = CreateFrame("Frame", "ForeverClassesAbilityAnchor", frame)
    abilityAnchor:SetSize(db.barWidth, 38)
    abilityAnchor:SetPoint("BOTTOM", frame, "TOP", 0, 1)

    -- ========================================================================
    -- Low Health Warning Overlay (Pulsing Crimson Border & Bar Alert Glow)
    -- ========================================================================
    local lowHealthFrame = CreateFrame("Frame", "ForeverClassesLowHealthWarning", frame, BackdropTemplateString)
    lowHealthFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
    lowHealthFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
    lowHealthFrame:SetFrameStrata("HIGH")
    lowHealthFrame:SetFrameLevel(frame:GetFrameLevel() + 15)
    lowHealthFrame:EnableMouse(false)

    -- Pulsing Crimson Border Alert
    lowHealthFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    lowHealthFrame:SetBackdropBorderColor(1.0, 0.12, 0.12, 1.0)

    -- Pulse Overlay Child Frame (holds the flashing texture and animation)
    local pulseOverlay = CreateFrame("Frame", nil, lowHealthFrame)
    pulseOverlay:SetAllPoints(lowHealthFrame)
    pulseOverlay:SetFrameLevel(lowHealthFrame:GetFrameLevel() + 1)
    lowHealthFrame.pulseOverlay = pulseOverlay

    -- Pulsing Danger Flash across Health Bar
    local healthFlash = pulseOverlay:CreateTexture(nil, "ARTWORK")
    healthFlash:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
    healthFlash:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    healthFlash:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthFlash:SetVertexColor(1.0, 0.08, 0.08, 0.40)
    healthFlash:SetBlendMode("ADD")
    lowHealthFrame.healthFlash = healthFlash

    -- Looping Heartbeat Pulse Animation Group on pulseOverlay (smooth 0.7s cycle)
    pcall(function()
        local animGroup = pulseOverlay:CreateAnimationGroup()
        animGroup:SetLooping("REPEAT")

        local pulseUp = animGroup:CreateAnimation("Alpha")
        pulseUp:SetOrder(1)
        pulseUp:SetDuration(0.35)
        if pulseUp.SetFromAlpha then pulseUp:SetFromAlpha(0.20) end
        if pulseUp.SetToAlpha then pulseUp:SetToAlpha(1.00) end

        local pulseDown = animGroup:CreateAnimation("Alpha")
        pulseDown:SetOrder(2)
        pulseDown:SetDuration(0.35)
        if pulseDown.SetFromAlpha then pulseDown:SetFromAlpha(1.00) end
        if pulseDown.SetToAlpha then pulseDown:SetToAlpha(0.20) end

        lowHealthFrame.animGroup = animGroup
    end)

    lowHealthFrame:SetAlpha(0)
    lowHealthFrame:Hide()

    -- ========================================================================
    -- Harmful Debuffs Tray (docked to right of panel)
    -- ========================================================================
    local debuffTray = CreateFrame("Frame", "ForeverClassesDebuffTray", frame)
    debuffTray:SetSize(140, 24)
    debuffTray:SetPoint("LEFT", frame, "RIGHT", 6, 0)
    debuffTray:SetFrameLevel(frame:GetFrameLevel() + 5)
    debuffTray:Show()

    local debuffButtons = {}
    local MAX_DEBUFF_ICONS = 5
    local iconSize = 24
    local iconGap = 4

    for i = 1, MAX_DEBUFF_ICONS do
        local btn = CreateFrame("Button", "ForeverClassesDebuffIcon" .. i, debuffTray)
        btn:SetSize(iconSize, iconSize)
        btn:SetPoint("LEFT", debuffTray, "LEFT", (i - 1) * (iconSize + iconGap), 0)
        btn:EnableMouse(true)
        btn:RegisterForClicks("AnyUp")

        local icon = btn:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints(btn)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon

        local cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cooldown:SetAllPoints(btn)
        cooldown:SetReverse(true)
        cooldown:SetDrawEdge(true)
        pcall(cooldown.SetHideCountdownNumbers, cooldown, false)
        btn.cooldown = cooldown

        local border = CreateFrame("Frame", nil, btn, BackdropTemplateString)
        border:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
        border:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
        })
        border:SetBackdropBorderColor(0.8, 0.1, 0.1, 1.0)
        border:SetFrameLevel(btn:GetFrameLevel() + 4)
        btn.border = border

        local countText = border:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        countText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        countText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        countText:SetTextColor(1, 1, 1, 1)
        btn.countText = countText

        btn:SetScript("OnEnter", function(self)
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.auraSlot and GameTooltip.SetUnitAuraBySlot then
                    local ok = pcall(GameTooltip.SetUnitAuraBySlot, GameTooltip, "player", self.auraSlot)
                    if ok then
                        GameTooltip:Show()
                        return
                    end
                end
                if self.auraInstanceID and GameTooltip.SetUnitAuraByAuraInstanceID then
                    local ok = pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, "player", self.auraInstanceID)
                    if ok then
                        GameTooltip:Show()
                        return
                    end
                end
                if self.debuffIndex and GameTooltip.SetUnitDebuff then
                    local ok = pcall(GameTooltip.SetUnitDebuff, GameTooltip, "player", self.debuffIndex)
                    if ok then
                        GameTooltip:Show()
                        return
                    end
                end
                if self.spellId and GameTooltip.SetSpellByID then
                    local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellId)
                    if ok then
                        GameTooltip:Show()
                        return
                    end
                end
                if self.testSpellName then
                    GameTooltip:AddLine(self.testSpellName, 1, 0.2, 0.2)
                    if self.testSpellDesc then
                        GameTooltip:AddLine(self.testSpellDesc, 1, 1, 1, true)
                    end
                    GameTooltip:Show()
                    return
                end
                if self.spellName then
                    GameTooltip:AddLine(self.spellName, 1, 0.2, 0.2)
                    GameTooltip:Show()
                end
            end)
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn:Hide()
        debuffButtons[i] = btn
    end

    debuffTray.buttons = debuffButtons

    -- Store references on FC
    FC.Frame = frame
    FC.HealthBar = healthBar
    FC.HealthBg = healthBg
    FC.HealPrediction = healPrediction
    FC.AbsorbBar = absorbBar
    FC.OverAbsorbGlow = overAbsorbGlow
    FC.HealthText = healthText
    FC.PowerBar = powerBar
    FC.PowerBg = powerBg
    FC.PowerText = powerText
    FC.ComboFrame = comboFrame
    FC.TotemBar = totemBar
    FC.PoisonBar = poisonBar
    FC.AbilityAnchor = abilityAnchor
    FC.LowHealthFrame = lowHealthFrame
    FC.DebuffTray = debuffTray
    pcall(function()
        if FC.SyncIgnoredDebuffSpellIDs then pcall(FC.SyncIgnoredDebuffSpellIDs, FC) end
        FC:SetupDebuffAuraContainer()
    end)

    -- Cooldown & Ability Bar (Phase 2)
    local cooldownBar = FC:CreateCooldownBar(abilityAnchor)
    FC.CooldownBar = cooldownBar
    pcall(function() if FC.UpdateCooldownBarLayout then FC:UpdateCooldownBarLayout() end end)

    -- Safe initial updates
    pcall(function() FC:UpdatePowerType() end)
    pcall(function() FC:UpdateHealth() end)
    pcall(function() FC:UpdatePower() end)
    pcall(function() FC:UpdateComboPoints() end)
    pcall(function() FC:UpdateTotems() end)
    pcall(function() FC:UpdateDebuffs() end)
    pcall(function() FC:UpdateCooldowns() end)
end

-- ============================================================================
-- Low Health Warning Controller (<= threshold HP, default 35%)
-- ============================================================================

function FC:SetLowHealthWarning(active, curveAlpha)
    local f = FC.LowHealthFrame
    if not f then return end

    if not ForeverClassesDB or not ForeverClassesDB.lowHealthWarning then
        if f.animGroup and f.animGroup:IsPlaying() then
            pcall(f.animGroup.Stop, f.animGroup)
        end
        f:SetAlpha(0)
        f:Hide()
        return
    end

    -- Test mode simulation (/fc testlow)
    if FC.testLowHealth then
        f:SetAlpha(1.0)
        f:Show()
        if f.animGroup and not f.animGroup:IsPlaying() then
            pcall(f.animGroup.Play, f.animGroup)
        end
        return
    end

    -- Native secret curve alpha mode (Midnight combat):
    if curveAlpha ~= nil and IsSecret(curveAlpha) then
        f:Show()
        pcall(f.SetAlpha, f, curveAlpha)
        if f.animGroup and not f.animGroup:IsPlaying() then
            pcall(f.animGroup.Play, f.animGroup)
        end
        return
    end

    -- Explicit boolean / non-secret mode:
    if active then
        f:SetAlpha(1.0)
        f:Show()
        if f.animGroup and not f.animGroup:IsPlaying() then
            pcall(f.animGroup.Play, f.animGroup)
        end
    else
        if f.animGroup and f.animGroup:IsPlaying() then
            pcall(f.animGroup.Stop, f.animGroup)
        end
        f:SetAlpha(0)
        f:Hide()
    end
end

-- ============================================================================
-- Update Health & Upcoming Heals
-- ============================================================================

function FC:UpdateHealth()
    if not FC.HealthBar then return end

    -- Apply Health Bar Color (Class-colored or Classic Emerald Green)
    local hr, hg, hb = FC:GetHealthColor()
    FC.HealthBar:SetStatusBarColor(hr, hg, hb)
    local barTex = FC.HealthBar:GetStatusBarTexture()
    if barTex then
        barTex:SetVertexColor(hr, hg, hb)
    end
    if FC.HealthBg then
        FC.HealthBg:SetVertexColor(hr * 0.22, hg * 0.22, hb * 0.22, 0.75)
    end

    local currentHealth, maxHealth
    pcall(function()
        currentHealth = UnitHealth("player")
        maxHealth = UnitHealthMax("player")
    end)

    -- Handle Test Mode Simulations:
    local isTestingLow = (FC.testLowHealth == true)
    local isTestingHeal = (FC.testIncomingHeal ~= nil)
    local testIncoming = FC.testIncomingHeal
    local isTestingAbsorb = (FC.testAbsorb ~= nil)
    local testAbsorbs = FC.testAbsorb

    if isTestingLow then
        if not IsSecret(maxHealth) and maxHealth and maxHealth > 0 then
            currentHealth = math.floor(maxHealth * 0.18)
        else
            maxHealth = 1000
            currentHealth = 180
        end
    elseif isTestingHeal and testIncoming then
        if not IsSecret(maxHealth) and maxHealth and maxHealth > 0 then
            currentHealth = math.floor(maxHealth * 0.55)
        else
            maxHealth = 1000
            currentHealth = 550
        end
    elseif isTestingAbsorb and testAbsorbs then
        if not IsSecret(maxHealth) and maxHealth and maxHealth > 0 then
            currentHealth = math.floor(maxHealth * 0.80)
        else
            maxHealth = 1000
            currentHealth = 800
        end
    end

    if maxHealth then
        pcall(FC.HealthBar.SetMinMaxValues, FC.HealthBar, 0, maxHealth)
    end
    if currentHealth then
        pcall(FC.HealthBar.SetValue, FC.HealthBar, currentHealth)
    end

    -- Update Health Text
    UpdateHealthText(FC.HealthText, currentHealth, maxHealth, ForeverClassesDB.textMode)

    -- Evaluate Low Health Warning (<= threshold HP, default 33%)
    local isLow = false
    local curveAlpha = nil

    if isTestingLow then
        isLow = true
    elseif ForeverClassesDB and ForeverClassesDB.lowHealthWarning then
        local isDead = false
        pcall(function() isDead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") end)
        if not isDead then
            local threshold = ForeverClassesDB.lowHealthThreshold or 33

            -- 1. Try Blizzard native Step Color Curve (Midnight / 12.0 secret-safe)
            if C_CurveUtil and C_CurveUtil.CreateColorCurve and UnitHealthPercent then
                local threshDec = threshold / 100
                if not FC.lowHealthCurve or FC.lowHealthCurveThreshold ~= threshDec then
                    local okCurve, c = pcall(function()
                        local curve = C_CurveUtil.CreateColorCurve()
                        curve:SetType(Enum.LuaCurveType.Step)
                        curve:AddPoint(0, CreateColor(1, 0, 0, 1))
                        curve:AddPoint(threshDec, CreateColor(0, 0, 0, 0))
                        return curve
                    end)
                    if okCurve and c then
                        FC.lowHealthCurve = c
                        FC.lowHealthCurveThreshold = threshDec
                    end
                end

                if FC.lowHealthCurve then
                    local okCol, col = pcall(UnitHealthPercent, "player", true, FC.lowHealthCurve)
                    if okCol and col and col.GetRGBA then
                        local okA, _, _, _, a = pcall(col.GetRGBA, col)
                        if okA and a ~= nil then
                            if not IsSecret(a) then
                                local aNum = tonumber(a)
                                if aNum and aNum > 0.01 then
                                    isLow = true
                                else
                                    isLow = false
                                end
                            else
                                curveAlpha = a
                            end
                        end
                    end
                end
            end

            -- 2. Fallback to standard Lua math when values are not secret
            if not isLow and curveAlpha == nil and currentHealth and maxHealth then
                if not IsSecret(currentHealth) and not IsSecret(maxHealth) then
                    local cur = tonumber(currentHealth)
                    local mx = tonumber(maxHealth)
                    if cur and mx and mx > 0 then
                        local pct = (cur / mx) * 100
                        if pct <= threshold and cur > 0 then
                            isLow = true
                        end
                    end
                end
            end
        end
    end

    if FC.SetLowHealthWarning then
        FC:SetLowHealthWarning(isLow, curveAlpha)
    end

    -- Upcoming Heals (Heal Prediction StatusBar)
    local incoming = 0

    if FC.HealPrediction then
        if ForeverClassesDB.showIncomingHeals then
            if isTestingHeal and testIncoming then
                incoming = testIncoming
            else
                incoming = GetIncomingHeal("player")
            end

            -- Update Heal Prediction Color dynamically (Class-colored or Classic Emerald Green)
            local predR, predG, predB, predA = FC:GetHealPredictionColor()
            FC.HealPrediction:SetStatusBarColor(predR, predG, predB, predA)
            local predTex = FC.HealPrediction:GetStatusBarTexture()
            if predTex then
                predTex:SetVertexColor(predR, predG, predB, predA)
            end

            -- Anchor HealPrediction to current health bar fill texture's right edge
            local healthTex = FC.HealthBar:GetStatusBarTexture()
            FC.HealPrediction:ClearAllPoints()
            if healthTex then
                FC.HealPrediction:SetPoint("TOPLEFT", healthTex, "TOPRIGHT", 0, 0)
                FC.HealPrediction:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMRIGHT", 0, 0)
            else
                FC.HealPrediction:SetPoint("TOPLEFT", FC.HealthBar, "TOPLEFT", 0, 0)
                FC.HealPrediction:SetPoint("BOTTOMLEFT", FC.HealthBar, "BOTTOMLEFT", 0, 0)
            end
            FC.HealPrediction:SetWidth(ForeverClassesDB.barWidth or 240)

            if maxHealth then
                pcall(FC.HealPrediction.SetMinMaxValues, FC.HealPrediction, 0, maxHealth)
            end
            pcall(FC.HealPrediction.SetValue, FC.HealPrediction, incoming)

            if incoming and not IsSecret(incoming) and type(incoming) == "number" then
                if incoming > 0 then
                    FC.HealPrediction:Show()
                    FC.HealPrediction:SetAlpha(1.0)
                else
                    FC.HealPrediction:Hide()
                end
            elseif incoming and IsSecret(incoming) then
                pcall(FC.HealPrediction.SetAlpha, FC.HealPrediction, incoming)
                FC.HealPrediction:Show()
            else
                FC.HealPrediction:Hide()
            end
        else
            FC.HealPrediction:Hide()
        end
    end

    -- Absorb Shields & Overshield Glow
    if FC.AbsorbBar then
        if ForeverClassesDB.showAbsorbs ~= false then
            local barW = (ForeverClassesDB and ForeverClassesDB.barWidth) or (FC.HealthBar and FC.HealthBar:GetWidth()) or 240
            local barH = (ForeverClassesDB and ForeverClassesDB.healthHeight) or (FC.HealthBar and FC.HealthBar:GetHeight()) or 22
            local rawAbsorbs, isClamped, totalAbs
            if isTestingAbsorb and testAbsorbs then
                rawAbsorbs = testAbsorbs
                isClamped = (testAbsorbs >= (maxHealth or 1000) * 0.20)
                totalAbs = testAbsorbs
            else
                rawAbsorbs, isClamped, totalAbs = GetAbsorbData("player")
            end

            -- Anchor directly to HealthBar texture's right edge
            local healthTex = FC.HealthBar:GetStatusBarTexture()
            FC.AbsorbBar:ClearAllPoints()
            if healthTex then
                FC.AbsorbBar:SetPoint("TOPLEFT", healthTex, "TOPRIGHT", 0, 0)
                FC.AbsorbBar:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMRIGHT", 0, 0)
            else
                FC.AbsorbBar:SetPoint("TOPLEFT", FC.HealthBar, "TOPLEFT", 0, 0)
                FC.AbsorbBar:SetPoint("BOTTOMLEFT", FC.HealthBar, "BOTTOMLEFT", 0, 0)
            end
            FC.AbsorbBar:SetWidth(barW)
            FC.AbsorbBar:SetHeight(barH)

            local isSecretAbs = IsSecret(rawAbsorbs)
            local hasShield = false

            if isSecretAbs then
                -- In combat / secret context: rawAbsorbs is an opaque secret number from Blizzard's C++ engine.
                -- It represents ALL active damage absorbs on the player (whether cast by player or ANY party/raid member).
                -- We pass it directly to the C++ StatusBar (FC.AbsorbBar).
                -- If rawAbsorbs == 0, C++ renders 0px width & 0 alpha (completely invisible).
                -- If rawAbsorbs > 0, C++ renders at full alpha with the exact shield width.
                hasShield = true
                FC.hasActiveShield = true
            elseif rawAbsorbs and type(rawAbsorbs) == "number" and rawAbsorbs > 0 then
                hasShield = true
                FC.hasActiveShield = true
                FC.currentShieldRemaining = rawAbsorbs
            else
                hasShield = false
                FC.hasActiveShield = false
                FC.currentShieldRemaining = 0
                if FC.currentShieldSpell and FC.activeBuffs and FC.activeBuffs[FC.currentShieldSpell] then
                    FC.activeBuffs[FC.currentShieldSpell] = nil
                    FC.needsCooldownRefresh = true
                end
                FC.currentShieldSpell = nil
            end

            if FC.lastLoggedShieldActive ~= hasShield then
                FC.lastLoggedShieldActive = hasShield
                FC:LogShield("SHIELD_STATE", "active=%s isSec=%s rawAbs=%s rem=%s",
                    tostring(hasShield), tostring(isSecretAbs), tostring(rawAbsorbs), tostring(FC.currentShieldRemaining))
            end

            if hasShield then
                if maxHealth then
                    pcall(FC.AbsorbBar.SetMinMaxValues, FC.AbsorbBar, 0, maxHealth)
                end
                pcall(FC.AbsorbBar.SetValue, FC.AbsorbBar, rawAbsorbs)

                if isSecretAbs then
                    pcall(FC.AbsorbBar.SetAlpha, FC.AbsorbBar, rawAbsorbs)
                    FC.AbsorbBar:Show()
                else
                    FC.AbsorbBar:SetAlpha(1.0)
                    FC.AbsorbBar:Show()
                end

                if FC.AbsorbBar.overlay then FC.AbsorbBar.overlay:Show() end

                -- Overshield glow: Shown whenever (Current HP + Absorb Shield) reaches/exceeds Max HP
                if FC.OverAbsorbGlow then
                    if not isSecretAbs and rawAbsorbs and currentHealth and maxHealth and not IsSecret(currentHealth) and not IsSecret(maxHealth) then
                        local curH = tonumber(currentHealth) or 0
                        local maxHVal = tonumber(maxHealth) or 1
                        if (curH + rawAbsorbs) >= (maxHVal - 0.5) then
                            FC.OverAbsorbGlow:SetAlpha(1.0)
                            FC.OverAbsorbGlow:Show()
                        else
                            FC.OverAbsorbGlow:Hide()
                        end
                    else
                        FC.OverAbsorbGlow:Hide()
                    end
                end
            else
                FC.AbsorbBar:Hide()
                if FC.OverAbsorbGlow then
                    FC.OverAbsorbGlow:Hide()
                end
            end
        else
            FC.AbsorbBar:Hide()
            if FC.OverAbsorbGlow then
                FC.OverAbsorbGlow:Hide()
            end
        end
    end
end

-- ============================================================================
-- Harmful Debuffs Tray Controller (Right of Panel)
-- ============================================================================

local MAX_DEBUFF_ICONS = 5

local function GetDebuffColor(debuffType)
    if not debuffType or IsSecret(debuffType) then return 0.80, 0.10, 0.10 end
    local ok, r, g, b = pcall(function()
        if DebuffTypeColor and DebuffTypeColor[debuffType] then
            local c = DebuffTypeColor[debuffType]
            if c and c.r then return c.r, c.g, c.b end
        end
        if debuffType == "Magic" then
            return 0.20, 0.60, 1.00     -- Arcane Blue
        elseif debuffType == "Curse" then
            return 0.60, 0.00, 1.00     -- Shadow Purple
        elseif debuffType == "Disease" then
            return 0.60, 0.40, 0.10     -- Necrotic Brown/Orange
        elseif debuffType == "Poison" then
            return 0.00, 0.65, 0.10     -- Toxic Green
        elseif debuffType == "Bleed" then
            return 0.85, 0.15, 0.15     -- Deep Crimson
        else
            return 0.80, 0.10, 0.10     -- Physical / Harmful Red
        end
    end)
    if ok and r then return r, g, b end
    return 0.80, 0.10, 0.10
end

FC.DEFAULT_IGNORED_DEBUFFS = {
    ["boosted rest"] = true,
    ["boosted_rest"] = true,
    ["exhaustion"] = true,
    ["campfire exhaustion"] = true,
    ["well rested exhaustion"] = true,
    ["camp tent"] = true,
    ["camp tent rest"] = true,
    ["tent exhaustion"] = true,
    ["recently bandaged"] = true,
    ["resurrection sickness"] = true,
    ["honorless target"] = true,
    ["deserter"] = true,
    ["dungeon deserter"] = true,
    ["dungeon cooldown"] = true,
    ["sated"] = true,
    ["temporal displacement"] = true,
    ["fatigued"] = true,
}

function FC:IsDebuffIgnored(name)
    if not name or IsSecret(name) then return false end
    local clean = string.lower((strtrim and strtrim(name)) or string.match(name, "^%s*(.-)%s*$") or name)
    if FC.DEFAULT_IGNORED_DEBUFFS and FC.DEFAULT_IGNORED_DEBUFFS[clean] then
        return true
    end
    if ForeverClassesDB and ForeverClassesDB.ignoredDebuffs and ForeverClassesDB.ignoredDebuffs[clean] then
        return true
    end
    -- Substring pattern matching for resting/camp/tent/exhaustion debuffs
    if string.find(clean, "boosted rest", 1, true)
        or string.find(clean, "exhaustion", 1, true)
        or string.find(clean, "camp tent", 1, true)
        or string.find(clean, "campfire", 1, true) then
        return true
    end
    return false
end

local function SafeCreateColor(r, g, b, a)
    if _G.CreateColor then
        return _G.CreateColor(r, g, b, a)
    end
    return {
        r = r, g = g, b = b, a = a or 1,
        GetRGBA = function(s) return s.r, s.g, s.b, s.a end,
        GetRGB = function(s) return s.r, s.g, s.b end,
    }
end

FC.ignoredTextureCache = FC.ignoredTextureCache or {
    [1001982] = true, -- Boosted Rest (WoW Forever / Turtle custom tent texture)
    ["1001982"] = true,
    [136087] = true,  -- Spell_Nature_Sleep
    ["136087"] = true,
    [132150] = true,
    ["132150"] = true,
    [134400] = true,  -- inv_misc_tent_01
    ["134400"] = true,
    ["interface\\icons\\spell_nature_sleep"] = true,
    ["interface\\icons\\spell_nature_resting"] = true,
    ["interface\\icons\\inv_misc_tent_01"] = true,
}

-- Excluded spell IDs for native AuraContainer candidateFilters (must be [spellId] = true dictionary, NOT an array)
FC.excludedDebuffSpellIDs = FC.excludedDebuffSpellIDs or {
    [1229451] = true, -- Boosted Rest (WoW Forever / Turtle custom tent debuff)
    [1001982] = true, -- Fallback texture/fileID
}

local function SafeIsShown(f)
    if not f then return false end
    local ok, shown = pcall(f.IsShown, f)
    if not ok then return false end
    if IsSecret(shown) then return true end
    return shown == true
end

function FC:SetupDebuffAuraContainer()
    if FC.AuraContainer then return true end
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")) then
        return false
    end
    if not FC.DebuffTray then
        return false
    end

    local ok, container = pcall(CreateFrame, "AuraContainer", "ForeverClassesDebuffAuraContainer", FC.DebuffTray, "CustomAuraContainerTemplate")
    if not ok or not container then
        return false
    end

    FC.AuraContainer = container
    container:SetSize(140, 24)
    container:SetPoint("LEFT", FC.DebuffTray, "LEFT", 0, 0)
    container:SetFrameLevel(FC.DebuffTray:GetFrameLevel() + 2)

    local sortMethod = (_G.AuraContainerSortMethod and _G.AuraContainerSortMethod.Expiration)
        or (_G.Enum and _G.Enum.AuraContainerSortMethod and _G.Enum.AuraContainerSortMethod.Expiration)
        or 0
    local sortDirection = (_G.AuraContainerSortDirection and _G.AuraContainerSortDirection.Normal)
        or (_G.Enum and _G.Enum.AuraContainerSortDirection and _G.Enum.AuraContainerSortDirection.Normal)
        or 0
    local dispelStyle = (_G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle and _G.Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset) or 0

    local candidateFilters = {
        excludeSpellIDs = FC.excludedDebuffSpellIDs,
    }

    local auraFrameOptions = {
        maxFrameCount = 5,
        sortMethod = sortMethod,
        sortDirection = sortDirection,
        candidateFilters = candidateFilters,
        layout = {
            elementSpacing = 4,
            lineSpacing = 4,
            elementWidth = 24,
            elementHeight = 24,
            maximumLineSize = 200,
        },
        initializeFrame = function(auraButton)
            auraButton:SetSize(24, 24)
            pcall(auraButton.SetMouseMotionEnabled, auraButton, true)

            -- Icon texture
            local icon = auraButton.Icon or auraButton:CreateTexture(nil, "BACKGROUND")
            icon:SetAllPoints(auraButton)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            auraButton.Icon = icon
            if auraButton.SetIcon then
                auraButton:SetIcon(icon)
            end

            -- Cooldown frame
            local cd = auraButton.Cooldown or CreateFrame("Cooldown", "$parentCooldown", auraButton, "CooldownFrameTemplate")
            cd:SetAllPoints(auraButton)
            cd:SetReverse(true)
            cd:SetDrawEdge(true)
            pcall(cd.SetHideCountdownNumbers, cd, false)
            auraButton.Cooldown = cd
            if auraButton.SetDurationCooldown then
                auraButton:SetDurationCooldown(cd)
            end

            -- Application stack count
            local countFrame = auraButton.CountFrame or CreateFrame("Frame", "$parentCountFrame", auraButton)
            countFrame:SetAllPoints(auraButton)
            countFrame:EnableMouse(false)
            local countText = countFrame.Count or countFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            countText:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", -1, 1)
            countText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            countText:SetTextColor(1, 1, 1, 1)
            countFrame.Count = countText
            auraButton.Count = countText
            auraButton.CountFrame = countFrame
            if auraButton.SetApplicationCount then
                auraButton:SetApplicationCount(countText)
            end

            -- Dispel Border
            local border = auraButton.Border or auraButton:CreateTexture(nil, "OVERLAY")
            border:SetAllPoints(auraButton)
            border:SetTexture([[Interface\Tooltips\UI-Tooltip-Border]])
            if border.SetTextureSliceMargins then
                border:SetTextureSliceMargins(8, 8, 8, 8)
            end
            auraButton.Border = border

            local borderOptions = {
                showIcon = false,
                showWhenHarmful = true,
                showWhenHelpful = true,
                showWithoutDispelType = true,
                style = dispelStyle,
                customDispelColorMap = {
                    ["None"]    = SafeCreateColor(0.8, 0.1, 0.1, 1),
                    ["Magic"]   = SafeCreateColor(0.2, 0.6, 1.0, 1),
                    ["Curse"]   = SafeCreateColor(0.6, 0.0, 1.0, 1),
                    ["Disease"] = SafeCreateColor(0.6, 0.4, 0.0, 1),
                    ["Poison"]  = SafeCreateColor(0.0, 0.6, 0.0, 1),
                    ["Bleed"]   = SafeCreateColor(1.0, 0.0, 0.0, 1),
                }
            }
            if auraButton.SetAuraBorder then
                auraButton:SetAuraBorder(border, borderOptions)
            elseif auraButton.AddDispelTypeTexture then
                pcall(auraButton.ClearDispelTypeTextures, auraButton)
                auraButton:AddDispelTypeTexture(border, borderOptions)
            end
        end,
    }

    if container.AddAuraGroup then
        container:AddAuraGroup("debuffGroup", "HARMFUL", auraFrameOptions)
    end
    if container.SetAuraGroupCandidateFilters then
        pcall(container.SetAuraGroupCandidateFilters, container, "debuffGroup", candidateFilters)
    end
    if container.SetAuraGroupLayout then
        container:SetAuraGroupLayout("debuffGroup", auraFrameOptions.layout)
    end

    local anchorFlow = _G.AnchorUtil and _G.AnchorUtil.FlowDirection
    local flowRight = (anchorFlow and anchorFlow.Right) or 1
    local flowDown = (anchorFlow and anchorFlow.Down) or 2
    if container.SetFlowLayoutAnchorPoint then
        container:SetFlowLayoutAnchorPoint("LEFT")
    end
    if container.SetFlowLayoutGrowthDirection then
        container:SetFlowLayoutGrowthDirection(flowRight, flowDown)
    end
    if container.SetFlowLayoutMaximumLineSize then
        container:SetFlowLayoutMaximumLineSize(200)
    end

    if container.SetUnit then
        container:SetUnit("player")
    end
    if container.SetEnabled then
        container:SetEnabled(true)
    end
    container:Show()
    FC.hasAuraContainers = true
    return true
end

function FC:SyncIgnoredDebuffSpellIDs()
    if InCombatLockdown and InCombatLockdown() then return end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end

    local updated = false
    pcall(function()
        for i = 1, 40 do
            local okCall, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
            if not okCall or not aura then break end

            local rawName = aura.name
            local isIgn = false
            if rawName and not IsSecret(rawName) and FC:IsDebuffIgnored(rawName) then
                isIgn = true
            elseif aura.icon and (aura.icon == 1001982 or tostring(aura.icon) == "1001982") then
                isIgn = true
            end

            if isIgn and aura.spellId then
                if not FC.excludedDebuffSpellIDs[aura.spellId] then
                    FC.excludedDebuffSpellIDs[aura.spellId] = true
                    updated = true
                end
            end
        end
    end)

    if updated then
        if ForeverClassesDB then
            ForeverClassesDB.excludedDebuffSpellIDs = FC.excludedDebuffSpellIDs
        end
        if FC.AuraContainer then
            if FC.AuraContainer.SetAuraGroupCandidateFilters then
                pcall(FC.AuraContainer.SetAuraGroupCandidateFilters, FC.AuraContainer, "debuffGroup", {
                    excludeSpellIDs = FC.excludedDebuffSpellIDs,
                })
            end
            if FC.AuraContainer.UpdateAllAuras then
                pcall(FC.AuraContainer.UpdateAllAuras, FC.AuraContainer)
            end
        end
    end
end

function FC:SyncIgnoredDebuffTextures()
    if InCombatLockdown and InCombatLockdown() then return end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    pcall(function()
        for i = 1, 40 do
            local okCall, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
            if not okCall or not aura then break end
            local rawName = aura.name
            if rawName and not IsSecret(rawName) and FC:IsDebuffIgnored(rawName) then
                if aura.icon then
                    FC.ignoredTextureCache[aura.icon] = true
                    FC.ignoredTextureCache[tostring(aura.icon)] = true
                    if type(aura.icon) == "string" then
                        FC.ignoredTextureCache[string.lower(aura.icon)] = true
                    end
                end
                if aura.auraInstanceID then
                    FC.ignoredInstanceCache[aura.auraInstanceID] = true
                end
                if aura.spellId and not FC.excludedDebuffSpellIDs[aura.spellId] then
                    FC.excludedDebuffSpellIDs[aura.spellId] = true
                end
            end
        end
    end)
end

local staticDebuffList = {}
local staticDebuffPool = {}
for i = 1, (MAX_DEBUFF_ICONS or 8) do
    staticDebuffPool[i] = {}
end

function FC:ScanDebuffs()
    table.wipe(staticDebuffList)
    local list = staticDebuffList
    local inCombat = InCombatLockdown and InCombatLockdown()

    -- 1. When OUT OF COMBAT: Use native aura APIs (100% legal, 0 taint) to get true names and sync ignore caches
    if not inCombat then
        -- 1A. Modern C_UnitAuras
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok = pcall(function()
                for i = 1, 40 do
                    local okCall, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
                    if not okCall or not aura then break end
                    local rawName = aura.name
                    local isIgnored = false
                    if rawName and not IsSecret(rawName) then
                        isIgnored = FC:IsDebuffIgnored(rawName)
                    end
                    if not isIgnored and aura.spellId and FC.excludedDebuffSpellIDs and FC.excludedDebuffSpellIDs[aura.spellId] then
                        isIgnored = true
                    end
                    if not isIgnored and aura.icon then
                        local numI = tonumber(aura.icon)
                        if aura.icon == 1001982 or numI == 1001982 or tostring(aura.icon) == "1001982" then
                            isIgnored = true
                        elseif FC.ignoredTextureCache and (FC.ignoredTextureCache[aura.icon] or (numI and FC.ignoredTextureCache[numI])) then
                            isIgnored = true
                        end
                    end

                    if isIgnored then
                        if aura.icon then
                            FC.ignoredTextureCache[aura.icon] = true
                            FC.ignoredTextureCache[tostring(aura.icon)] = true
                            if type(aura.icon) == "string" then
                                FC.ignoredTextureCache[string.lower(aura.icon)] = true
                            end
                        end
                        if aura.auraInstanceID then
                            FC.ignoredInstanceCache[aura.auraInstanceID] = true
                        end
                        if aura.spellId and not FC.excludedDebuffSpellIDs[aura.spellId] then
                            FC.excludedDebuffSpellIDs[aura.spellId] = true
                        end
                    elseif aura.icon then
                        local dispel = aura.dispelName
                        if IsSecret(dispel) then dispel = nil end
                        local count = aura.applications
                        if IsSecret(count) then count = 0 end
                        local dur = aura.duration
                        if IsSecret(dur) then dur = 0 end
                        local exp = aura.expirationTime
                        if IsSecret(exp) then exp = 0 end

                        local entry = staticDebuffPool[#list + 1]
                        if not entry then
                            entry = {}
                            staticDebuffPool[#list + 1] = entry
                        end
                        entry.key = aura.auraInstanceID or i
                        entry.name = (rawName and not IsSecret(rawName)) and rawName or (dispel or "Debuff")
                        entry.icon = aura.icon
                        entry.count = count or 0
                        entry.debuffType = dispel or "none"
                        entry.duration = dur or 0
                        entry.expirationTime = exp or 0
                        entry.auraInstanceID = aura.auraInstanceID
                        entry.spellId = aura.spellId
                        entry.index = i
                        entry.source = "GetAuraDataByIndex"

                        table.insert(list, entry)
                        if #list >= MAX_DEBUFF_ICONS then break end
                    end
                end
            end)
            if ok and #list > 0 then
                FC.activeDebuffs = list
                FC.combatDebuffs = FC.combatDebuffs or {}
                table.wipe(FC.combatDebuffs)
                for _, d in ipairs(list) do
                    local cl = string.lower(d.name or "")
                    FC.combatDebuffs[cl] = {
                        name = d.name,
                        icon = d.icon,
                        count = d.count,
                        debuffType = d.debuffType,
                        duration = d.duration,
                        expirationTime = d.expirationTime,
                        spellId = d.spellId,
                    }
                end
                return list, "GetAuraDataByIndex"
            end
        end

        -- 1B. Classic Era UnitDebuff
        if UnitDebuff then
            local ok = pcall(function()
                for i = 1, 40 do
                    local okCall, name, icon, count, debuffType, duration, expirationTime = pcall(UnitDebuff, "player", i)
                    if not okCall or (not name and not icon) then break end
                    local isIgnored = false
                    if name and not IsSecret(name) then
                        isIgnored = FC:IsDebuffIgnored(name)
                    end
                    if not isIgnored and icon then
                        local numI = tonumber(icon)
                        if icon == 1001982 or numI == 1001982 or tostring(icon) == "1001982" then
                            isIgnored = true
                        elseif FC.ignoredTextureCache and (FC.ignoredTextureCache[icon] or (numI and FC.ignoredTextureCache[numI])) then
                            isIgnored = true
                        end
                    end

                    if isIgnored then
                        if icon then
                            FC.ignoredTextureCache[icon] = true
                            FC.ignoredTextureCache[tostring(icon)] = true
                            if type(icon) == "string" then
                                FC.ignoredTextureCache[string.lower(icon)] = true
                            end
                        end
                    elseif icon then
                        local dispel = debuffType
                        if IsSecret(dispel) then dispel = nil end
                        local c = count
                        if IsSecret(c) then c = 0 end
                        local dur = duration
                        if IsSecret(dur) then dur = 0 end
                        local exp = expirationTime
                        if IsSecret(exp) then exp = 0 end

                        local entry = staticDebuffPool[#list + 1]
                        if not entry then
                            entry = {}
                            staticDebuffPool[#list + 1] = entry
                        end
                        entry.key = i
                        entry.name = (name and not IsSecret(name)) and name or (dispel or "Debuff")
                        entry.icon = icon
                        entry.count = c or 0
                        entry.debuffType = dispel or "none"
                        entry.duration = dur or 0
                        entry.expirationTime = exp or 0
                        entry.index = i
                        entry.source = "UnitDebuff"

                        table.insert(list, entry)
                        if #list >= MAX_DEBUFF_ICONS then break end
                    end
                end
            end)
            if ok and #list > 0 then
                FC.activeDebuffs = list
                FC.combatDebuffs = FC.combatDebuffs or {}
                table.wipe(FC.combatDebuffs)
                for _, d in ipairs(list) do
                    local cl = string.lower(d.name or "")
                    FC.combatDebuffs[cl] = {
                        name = d.name,
                        icon = d.icon,
                        count = d.count,
                        debuffType = d.debuffType,
                        duration = d.duration,
                        expirationTime = d.expirationTime,
                        spellId = d.spellId,
                    }
                end
                return list, "UnitDebuff"
            end
        end

        if #list == 0 and FC.combatDebuffs then
            table.wipe(FC.combatDebuffs)
        end
    end

    -- 2. When IN COMBAT:
    -- Query internal FC.combatDebuffs table (populated by PLAYER_REGEN_DISABLED snapshot & COMBAT_LOG_EVENT_UNFILTERED).
    -- NEVER queries native aura APIs or secret frames during combat -> 100% TAINT FREE!
    if inCombat then
        FC.combatDebuffs = FC.combatDebuffs or {}
        local now = GetTime()
        for k, d in pairs(FC.combatDebuffs) do
            if d.expirationTime and d.expirationTime > 0 and now >= d.expirationTime then
                FC.combatDebuffs[k] = nil
            else
                table.insert(list, d)
                if #list >= MAX_DEBUFF_ICONS then break end
            end
        end

        if #list > 1 then
            table.sort(list, function(a, b)
                local expA = a.expirationTime or 0
                local expB = b.expirationTime or 0
                if expA > 0 and expB > 0 then
                    return expA < expB
                elseif expA > 0 then
                    return true
                elseif expB > 0 then
                    return false
                end
                return tostring(a.name or "") < tostring(b.name or "")
            end)
        end

        FC.activeDebuffs = list
        return list, "CombatLog"
    end

    FC.activeDebuffs = list
    return list, (list[1] and list[1].source or "None")
end

function FC:RunDebuffDiagnostics()
    print("|cff00ccff[ForeverClasses]|r === DEBUFF RUNTIME DIAGNOSTICS ===")
    local inCombat = InCombatLockdown and InCombatLockdown() or false
    print(string.format("  InCombatLockdown: %s", tostring(inCombat)))

    local shouldSecret = false
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        pcall(function() shouldSecret = C_Secrets.ShouldAurasBeSecret() end)
    end
    print(string.format("  C_Secrets.ShouldAurasBeSecret: %s", tostring(shouldSecret)))
    print(string.format("  FC.hasAuraContainers: %s, AuraContainer: %s, shown=%s", tostring(FC.hasAuraContainers), tostring(FC.AuraContainer ~= nil), tostring(FC.AuraContainer and FC.AuraContainer:IsShown() or false)))

    -- 1. Inspect Combat Debuffs table
    local cDebuffCount = 0
    if FC.combatDebuffs then
        for k, v in pairs(FC.combatDebuffs) do
            cDebuffCount = cDebuffCount + 1
            print(string.format("    combatDebuff: name=%s, spellId=%s, count=%s, type=%s, dur=%s", tostring(v.name), tostring(v.spellId), tostring(v.count), tostring(v.debuffType), tostring(v.duration)))
        end
    end
    print(string.format("  FC.combatDebuffs: count=%d", cDebuffCount))

    -- 1B. Excluded Debuff Spell IDs
    local excludedCount = 0
    local excludedList = {}
    if FC.excludedDebuffSpellIDs then
        for k, v in pairs(FC.excludedDebuffSpellIDs) do
            if type(k) == "number" and v == true then
                excludedCount = excludedCount + 1
                table.insert(excludedList, tostring(k))
            end
        end
    end
    print(string.format("  FC.excludedDebuffSpellIDs: count=%d, ids=[%s]", excludedCount, table.concat(excludedList, ", ")))

    -- 1C. Inspect FC.DebuffTray manual buttons
    if FC.DebuffTray and FC.DebuffTray.buttons then
        local shownCount = 0
        for i, btn in ipairs(FC.DebuffTray.buttons) do
            if btn and btn:IsShown() then shownCount = shownCount + 1 end
        end
        print(string.format("  FC.DebuffTray.buttons: total=%d, shown=%d", #FC.DebuffTray.buttons, shownCount))
        for i, btn in ipairs(FC.DebuffTray.buttons) do
            if btn and btn:IsShown() then
                print(string.format("    manualBtn #%d: shown=true, spellName=%s, tex=%s", i, tostring(btn.spellName), tostring(btn.icon and btn.icon:GetTexture())))
            end
        end
    end

    -- 2. Blizzard Default UI Frame Inspection
    local df = _G["DebuffFrame"]
    if df then
        local dfChildren = (df.GetLayoutChildren and df:GetLayoutChildren()) or {}
        local dfRegChildren = (df.GetChildren and {df:GetChildren()}) or {}
        print(string.format("  DebuffFrame: exists=true, shown=%s, layoutChildren=%d, regChildren=%d", tostring(df:IsShown()), #dfChildren, #dfRegChildren))
        if #dfChildren > 0 then
            for idx, ch in ipairs(dfChildren) do
                local itex = ch.Icon or ch.icon
                print(string.format("    dfChild #%d: shown=%s, tex=%s, instanceID=%s", idx, tostring(ch:IsShown()), tostring(itex and itex.GetTexture and itex:GetTexture()), tostring(ch.auraInstanceID)))
            end
        end
    else
        print("  DebuffFrame: NOT PRESENT")
    end

    local bf = _G["BuffFrame"]
    if bf then
        local bfChildren = (bf.GetLayoutChildren and bf:GetLayoutChildren()) or {}
        print(string.format("  BuffFrame: exists=true, shown=%s, layoutChildren=%d", tostring(bf:IsShown()), #bfChildren))
    else
        print("  BuffFrame: NOT PRESENT")
    end

    -- 3. UnitDebuff test
    if UnitDebuff then
        local ok, name, icon, count, debuffType, dur, exp = pcall(UnitDebuff, "player", 1)
        if ok then
            print(string.format("  UnitDebuff(1): OK -> name=%s, icon=%s, type=%s, dur=%s", tostring(name), tostring(icon), tostring(debuffType), tostring(dur)))
        else
            print(string.format("  UnitDebuff(1): ERROR -> %s", tostring(name)))
        end
    else
        print("  UnitDebuff: NOT PRESENT")
    end

    -- 4. C_UnitAuras.GetAuraDataByIndex test
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HARMFUL")
        if ok and aura then
            print(string.format("  GetAuraDataByIndex(1, HARMFUL): OK -> name=%s, icon=%s, spellId=%s", tostring(aura.name), tostring(aura.icon), tostring(aura.spellId)))
        else
            print(string.format("  GetAuraDataByIndex(1, HARMFUL): ERROR / NIL -> %s", tostring(aura)))
        end
    else
        print("  C_UnitAuras.GetAuraDataByIndex: NOT PRESENT")
    end

    -- 5. C_UnitAuras.ForEachAura test
    if C_UnitAuras and C_UnitAuras.ForEachAura then
        local forEachCount = 0
        local okFE, errFE = pcall(C_UnitAuras.ForEachAura, "player", "HARMFUL", 10, function(aura)
            forEachCount = forEachCount + 1
            print(string.format("    ForEachAura #%d: name=%s, icon=%s", forEachCount, tostring(aura and aura.name), tostring(aura and aura.icon)))
        end)
        print(string.format("  ForEachAura(HARMFUL): ok=%s, count=%d, err=%s", tostring(okFE), forEachCount, tostring(errFE)))
    else
        print("  C_UnitAuras.ForEachAura: NOT PRESENT")
    end

    -- 6. FC:ScanDebuffs result
    local list, src = FC:ScanDebuffs()
    print(string.format("  FC:ScanDebuffs result: count=%d, source=%s", #(list or {}), tostring(src)))
    if list and #list > 0 then
        for i, d in ipairs(list) do
            print(string.format("    #%d: %s (type=%s, dur=%s, src=%s)", i, tostring(d.name), tostring(d.debuffType), tostring(d.duration), tostring(d.source)))
        end
    end

    -- Save to DB
    if ForeverClassesDB then
        ForeverClassesDB.lastDebuffDebug = {
            time = date and date("%Y-%m-%d %H:%M:%S") or "now",
            inCombat = inCombat,
            shouldSecret = shouldSecret,
            hasAuraContainerTemplate = hasAuraContainerTemplate,
            hasAuraContainers = FC.hasAuraContainers,
            scanCount = #(list or {}),
            scanSource = src,
        }
    end
end

function FC:UpdateDebuffs()
    pcall(function()
        if not FC.DebuffTray then return end

        local show = ForeverClassesDB and ForeverClassesDB.showDebuffs
        local isDead = false
        pcall(function() isDead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") end)

        -- If debuffs disabled in settings or player is dead:
        if not show or isDead then
            if FC.AuraContainer and FC.AuraContainer:IsShown() then
                FC.AuraContainer:Hide()
                pcall(FC.AuraContainer.SetEnabled, FC.AuraContainer, false)
            end
            if FC.DebuffTray.buttons then
                for i = 1, MAX_DEBUFF_ICONS do
                    local btn = FC.DebuffTray.buttons[i]
                    if btn then btn:Hide() end
                end
            end
            return
        end

        -- Simulated Test Mode (/fc testdebuff)
        if FC.testDebuffsActive then
            if FC.AuraContainer and FC.AuraContainer:IsShown() then
                FC.AuraContainer:Hide()
            end
            local testList = {
                {
                    name = "Deadly Poison",
                    desc = "Inflicts Nature damage over 12 sec. Stacks up to 5 times.",
                    icon = 136243, -- Ability_Rogue_DualWeild
                    count = 3,
                    debuffType = "Poison",
                    duration = 12,
                },
                {
                    name = "Rend",
                    desc = "Wounds the target, causing Bleed damage over 15 sec.",
                    icon = 132155, -- Ability_Gouge
                    count = 0,
                    debuffType = "Bleed",
                    duration = 15,
                },
                {
                    name = "Curse of Agony",
                    desc = "Curses the target, inflicting Shadow damage over 24 sec.",
                    icon = 136139, -- Spell_Shadow_CurseOfSargeras
                    count = 0,
                    debuffType = "Curse",
                    duration = 24,
                },
            }

            local now = GetTime()
            for i = 1, MAX_DEBUFF_ICONS do
                local btn = FC.DebuffTray.buttons[i]
                local d = testList[i]
                if d and btn then
                    btn.icon:SetTexture(d.icon)
                    btn.testSpellName = d.name
                    btn.testSpellDesc = d.desc
                    btn.spellName = nil
                    btn.auraInstanceID = nil
                    btn.auraSlot = nil
                    btn.debuffIndex = nil

                    local r, g, b = GetDebuffColor(d.debuffType)
                    btn.border:SetBackdropBorderColor(r, g, b, 1.0)

                    if d.count and d.count > 1 then
                        btn.countText:SetText(tostring(d.count))
                        btn.countText:Show()
                    else
                        btn.countText:SetText("")
                        btn.countText:Hide()
                    end

                    btn.cooldown:SetCooldown(now, d.duration)
                    btn.cooldown:Show()
                    btn:Show()
                else
                    if btn then btn:Hide() end
                end
            end
            return
        end

        -- 1. Modern Engine with CustomAuraContainerTemplate (WoW 12.0+ / Midnight / WoW Forever)
        if FC.hasAuraContainers and FC.AuraContainer then
            -- Hide legacy manual buttons so they never overlap with native AuraContainer
            if FC.DebuffTray.buttons then
                for i = 1, MAX_DEBUFF_ICONS do
                    local btn = FC.DebuffTray.buttons[i]
                    if btn and btn:IsShown() then btn:Hide() end
                end
            end

            if not FC.AuraContainer:IsShown() then
                pcall(FC.AuraContainer.SetEnabled, FC.AuraContainer, true)
                pcall(FC.AuraContainer.SetUnit, FC.AuraContainer, "player")
                FC.AuraContainer:Show()
            end
            return
        end

        -- 2. Legacy / Classic Era Fallback (Manual Buttons)
        local debuffList = FC:ScanDebuffs()
        for i = 1, MAX_DEBUFF_ICONS do
            local btn = FC.DebuffTray.buttons and FC.DebuffTray.buttons[i]
            local d = debuffList and debuffList[i]
            if d and btn then
                btn.icon:SetTexture(d.icon)
                btn.spellName = d.name
                btn.spellId = d.spellId
                btn.auraInstanceID = d.auraInstanceID
                btn.auraSlot = d.auraSlot
                btn.debuffIndex = d.index
                btn.testSpellName = nil
                btn.testSpellDesc = nil

                local r, g, b = GetDebuffColor(d.debuffType)
                btn.border:SetBackdropBorderColor(r, g, b, 1.0)

                if d.count and not IsSecret(d.count) and d.count > 1 then
                    btn.countText:SetText(tostring(d.count))
                    btn.countText:Show()
                else
                    btn.countText:SetText("")
                    btn.countText:Hide()
                end

                if d.duration and d.expirationTime and not IsSecret(d.duration) and not IsSecret(d.expirationTime) then
                    if d.duration > 0 and d.expirationTime > 0 then
                        local start = d.expirationTime - d.duration
                        pcall(btn.cooldown.SetCooldown, btn.cooldown, start, d.duration)
                        btn.cooldown:Show()
                    else
                        btn.cooldown:Hide()
                    end
                else
                    btn.cooldown:Hide()
                end

                btn:Show()
            else
                if btn then btn:Hide() end
            end
        end
    end)
end

-- ============================================================================
-- Phase 2: Ability & Cooldown Management Controller (Docked Above Health Bar)
-- ============================================================================

local MAX_COOLDOWN_SLOTS = 7
FC.MAX_COOLDOWN_SLOTS = MAX_COOLDOWN_SLOTS

local function FormatCooldownTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds < 10 then
        return string.format("%.1f", seconds)
    elseif seconds < 60 then
        return string.format("%ds", math.floor(seconds))
    elseif seconds < 3600 then
        return string.format("%dm", math.ceil(seconds / 60))
    else
        return string.format("%dh", math.ceil(seconds / 3600))
    end
end

function FC:FindSpellInSpellBook(spellIdentifier)
    if not spellIdentifier then return nil end
    local cleanTarget = type(spellIdentifier) == "string" and string.lower((strtrim and strtrim(spellIdentifier)) or string.match(spellIdentifier, "^%s*(.-)%s*$") or spellIdentifier) or nil
    local targetID = type(spellIdentifier) == "number" and spellIdentifier or nil
    local bestMatch = nil

    -- 1. Modern C_SpellBook (11.0+ / 12.0 Midnight)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
        local okLines, numSkillLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        if okLines and numSkillLines and numSkillLines > 0 then
            for i = 1, numSkillLines do
                local okLine, sLine = pcall(C_SpellBook.GetSpellBookSkillLineInfo, i)
                if okLine and sLine and not sLine.isGuild then
                    local numItems = sLine.numSpellBookItems or 0
                    local offset = sLine.itemIndexOffset or 0
                    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
                    for s = offset + 1, offset + numItems do
                        local okName, sName = pcall(C_SpellBook.GetSpellBookItemName, s, bank)
                        local itemType, actionID = nil, nil
                        if C_SpellBook.GetSpellBookItemInfo then
                            local okInfo, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, s, bank)
                            if okInfo and type(itemInfo) == "table" then
                                actionID = itemInfo.actionID or itemInfo.spellID
                                if itemInfo.name and not sName then sName = itemInfo.name end
                            end
                        end
                        if not actionID and C_SpellBook.GetSpellBookItemType then
                            pcall(function() itemType, actionID = C_SpellBook.GetSpellBookItemType(s, bank) end)
                        end
                        if targetID and actionID and actionID == targetID then
                            local icon = nil
                            if C_SpellBook.GetSpellBookItemTexture then
                                pcall(function() icon = C_SpellBook.GetSpellBookItemTexture(s, bank) end)
                            end
                            if not icon and actionID and C_Spell and C_Spell.GetSpellTexture then
                                pcall(function() icon = C_Spell.GetSpellTexture(actionID) end)
                            end
                            return {
                                name = sName,
                                id = actionID,
                                icon = icon,
                                slot = s,
                            }
                        elseif cleanTarget and okName and sName and string.lower(sName) == cleanTarget then
                            local icon = nil
                            if C_SpellBook.GetSpellBookItemTexture then
                                pcall(function() icon = C_SpellBook.GetSpellBookItemTexture(s, bank) end)
                            end
                            if not icon and actionID and C_Spell and C_Spell.GetSpellTexture then
                                pcall(function() icon = C_Spell.GetSpellTexture(actionID) end)
                            end
                            bestMatch = {
                                name = sName,
                                id = actionID or targetID,
                                icon = icon,
                                slot = s,
                            }
                        end
                    end
                end
            end
        end
    end

    if bestMatch then return bestMatch end

    -- 2. Classic / Legacy GetNumSpellTabs & GetSpellTabInfo
    if GetNumSpellTabs and GetSpellTabInfo then
        local okTabs, numTabs = pcall(GetNumSpellTabs)
        if okTabs and numTabs and numTabs > 0 then
            for t = 1, numTabs do
                local okTab, _, _, offset, numSpells = pcall(GetSpellTabInfo, t)
                if okTab and offset and numSpells then
                    for s = offset + 1, offset + numSpells do
                        local sName, itemType, actionID, icon = nil, nil, nil, nil
                        if GetSpellBookItemName then
                            pcall(function() sName = GetSpellBookItemName(s, "spell") end)
                        end
                        if GetSpellBookItemInfo then
                            pcall(function() itemType, actionID = GetSpellBookItemInfo(s, "spell") end)
                        end
                        if targetID and actionID and actionID == targetID then
                            if GetSpellBookItemTexture then
                                pcall(function() icon = GetSpellBookItemTexture(s, "spell") end)
                            end
                            return {
                                name = sName,
                                id = actionID,
                                icon = icon,
                                slot = s,
                            }
                        elseif cleanTarget and sName and string.lower(sName) == cleanTarget then
                            if GetSpellBookItemTexture then
                                pcall(function() icon = GetSpellBookItemTexture(s, "spell") end)
                            end
                            bestMatch = {
                                name = sName,
                                id = actionID or targetID,
                                icon = icon,
                                slot = s,
                            }
                        end
                    end
                end
            end
        end
    end

    return bestMatch
end

function FC:IsSpellLearned(spellIdentifier)
    if not spellIdentifier then return false end

    -- 1. If numeric spell ID, check direct Blizzard APIs
    if type(spellIdentifier) == "number" and spellIdentifier > 0 then
        local known = false
        if IsPlayerSpell then pcall(function() known = IsPlayerSpell(spellIdentifier) end) end
        if known then return true end
        if IsSpellKnown then pcall(function() known = IsSpellKnown(spellIdentifier) end) end
        if known then return true end
        if C_SpellBook and C_SpellBook.IsSpellKnown then pcall(function() known = C_SpellBook.IsSpellKnown(spellIdentifier) end) end
        if known then return true end
        if C_SpellBook and C_SpellBook.IsSpellKnownOrOverrides then pcall(function() known = C_SpellBook.IsSpellKnownOrOverrides(spellIdentifier) end) end
        if known then return true end
        if IsSpellKnownOrOverrides then pcall(function() known = IsSpellKnownOrOverrides(spellIdentifier) end) end
        if known then return true end
    end

    -- 2. Check active SpellBook
    local bookInfo = FC:FindSpellInSpellBook(spellIdentifier)
    if bookInfo then
        return true, bookInfo
    end

    -- 3. If identifier is string, try resolving ID and re-checking IsPlayerSpell / IsSpellKnown
    if type(spellIdentifier) == "string" then
        local sInfo = FC:ResolveSpellInfo(spellIdentifier)
        if sInfo and sInfo.id and type(sInfo.id) == "number" and sInfo.id > 100 then
            local known = false
            if IsPlayerSpell then pcall(function() known = IsPlayerSpell(sInfo.id) end) end
            if known then return true, sInfo end
            if IsSpellKnown then pcall(function() known = IsSpellKnown(sInfo.id) end) end
            if known then return true, sInfo end
            if C_SpellBook and C_SpellBook.IsSpellKnown then pcall(function() known = C_SpellBook.IsSpellKnown(sInfo.id) end) end
            if known then return true, sInfo end
        end
    end

    return false
end

function FC:ResolveSpellInfo(identifier)
    if not identifier then return nil end

    local name, icon, spellID

    -- 1. If string, check active SpellBook first (most accurate for player's current learned rank)
    if type(identifier) == "string" then
        local bookInfo = FC:FindSpellInSpellBook(identifier)
        if bookInfo and bookInfo.name then
            return {
                name = bookInfo.name,
                icon = bookInfo.icon,
                id = bookInfo.id,
            }
        end
    end

    -- 2. Modern C_Spell.GetSpellInfo (table in 11.0+)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, identifier)
        if ok and info and type(info) == "table" and info.name then
            name = info.name
            icon = info.iconID or info.originalIconID
            spellID = info.spellID
            return {
                name = name,
                icon = icon,
                id = spellID,
            }
        end
    end

    -- 3. Legacy GetSpellInfo
    if GetSpellInfo then
        local ok, n, _, ic, _, _, _, sID = pcall(GetSpellInfo, identifier)
        if ok and n then
            name = n
            icon = ic
            spellID = (type(sID) == "number" and sID > 0) and sID or (type(identifier) == "number" and identifier > 100 and identifier)
            return {
                name = name,
                icon = icon,
                id = spellID or identifier,
            }
        end
    end

    -- 4. Spellbook scan fallback
    local bookInfo2 = FC:FindSpellInSpellBook(identifier)
    if bookInfo2 then
        return {
            name = bookInfo2.name,
            icon = bookInfo2.icon,
            id = bookInfo2.id,
        }
    end

    return nil
end

function FC:SanitizeCooldownSlots()
    if InCombatLockdown and InCombatLockdown() then return end
    if not ForeverClassesDB then return end

    local slots = FC.GetCooldownSlots and FC:GetCooldownSlots() or ForeverClassesDB.cooldownSlots
    if not slots then return end

    if FC.UpdateSpellRanksCache then
        pcall(FC.UpdateSpellRanksCache, FC)
    end
    if FC.UpdateActionSlotCache then
        pcall(FC.UpdateActionSlotCache, FC)
    end

    local function SanitizeSingleSlot(slot)
        if not slot then return end
        if slot.type == "spell" then
            if not slot.icon or not slot.id then
                local sInfo = FC:ResolveSpellInfo(slot.id or slot.name)
                if sInfo then
                    slot.id = sInfo.id or slot.id
                    slot.name = sInfo.name or slot.name
                    slot.icon = sInfo.icon or slot.icon
                end
            end
            if slot.name and FC.highestRankBySpellName then
                local clean = string.lower((strtrim and strtrim(slot.name)) or slot.name)
                local highest = FC.highestRankBySpellName[clean]
                if highest and highest > 0 and slot.id ~= highest then
                    slot.id = highest
                    slot.actionSlot = nil
                    slot.noRange = nil
                end
            end
        elseif slot.type == "item" then
            if not slot.id or not slot.icon then
                local iInfo = FC:ResolveItemInfo(slot.id)
                if iInfo then
                    slot.name = iInfo.name or slot.name
                    slot.icon = iInfo.icon or slot.icon
                end
            end
        end
    end

    for i = 1, MAX_COOLDOWN_SLOTS do
        SanitizeSingleSlot(slots[i])
    end

    local allSwaps = FC.GetCooldownSwapSlots and FC:GetCooldownSwapSlots() or (ForeverClassesDB and ForeverClassesDB.cooldownSwapSlots)
    if allSwaps then
        for _, pool in pairs(allSwaps) do
            if type(pool) == "table" then
                for _, s in ipairs(pool) do
                    SanitizeSingleSlot(s)
                end
            end
        end
    end
end


function FC:ResolveItemInfo(identifier)
    if not identifier then return nil end

    if C_Item and C_Item.GetItemInfo then
        local ok, name, _, _, _, _, _, _, _, _, icon = pcall(C_Item.GetItemInfo, identifier)
        if ok and name then
            return {
                name = name,
                icon = icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(identifier)),
                id = identifier,
            }
        end
    end

    if GetItemInfo then
        local ok, name, _, _, _, _, _, _, _, _, icon = pcall(GetItemInfo, identifier)
        if ok and name then
            return {
                name = name,
                icon = icon,
                id = identifier,
            }
        end
    end

    return nil
end

-- ============================================================================
-- Action Bar & Spellbook Rank Caches (Universal Engine Compatibility)
-- ============================================================================

FC.actionSlotsBySpell = FC.actionSlotsBySpell or {}
FC.actionSlotsBySpellID = FC.actionSlotsBySpellID or {}
FC.actionSlotsByItem = FC.actionSlotsByItem or {}
FC.spellRanksCache = FC.spellRanksCache or {}
FC.highestRankBySpellName = FC.highestRankBySpellName or {}

function FC:UpdateActionSlotCache()
    FC.actionSlotsBySpell = {}
    FC.actionSlotsBySpellID = {}
    FC.actionSlotsByItem = {}
    FC.actionSlotsLastUpdate = GetTime()

    for slot = 1, 120 do
        local has = false
        if HasAction then
            pcall(function() has = HasAction(slot) end)
        end
        if has then
            local aType, id, subType = nil, nil, nil
            if GetActionInfo then
                pcall(function() aType, id, subType = GetActionInfo(slot) end)
            end

            if aType == "spell" and id and id > 0 then
                FC.actionSlotsBySpellID[id] = FC.actionSlotsBySpellID[id] or {}
                table.insert(FC.actionSlotsBySpellID[id], slot)

                local sInfo = FC:ResolveSpellInfo(id)
                local sName = sInfo and sInfo.name
                if not sName and GetSpellInfo then
                    pcall(function()
                        local ok, n = pcall(GetSpellInfo, id)
                        if ok and n then sName = n end
                    end)
                end
                if sName then
                    local clean = string.lower((strtrim and strtrim(sName)) or sName)
                    FC.actionSlotsBySpell[clean] = FC.actionSlotsBySpell[clean] or {}
                    table.insert(FC.actionSlotsBySpell[clean], slot)
                end

            elseif aType == "macro" and id and id > 0 then
                local mSpell = nil
                if GetMacroSpell then
                    pcall(function() mSpell = GetMacroSpell(id) end)
                end
                if mSpell then
                    local sInfo = FC:ResolveSpellInfo(mSpell)
                    local sName = (sInfo and sInfo.name) or (type(mSpell) == "string" and mSpell)
                    local sID = sInfo and sInfo.id
                    if sID and sID > 0 then
                        FC.actionSlotsBySpellID[sID] = FC.actionSlotsBySpellID[sID] or {}
                        table.insert(FC.actionSlotsBySpellID[sID], slot)
                    end
                    if sName then
                        local clean = string.lower((strtrim and strtrim(sName)) or sName)
                        FC.actionSlotsBySpell[clean] = FC.actionSlotsBySpell[clean] or {}
                        table.insert(FC.actionSlotsBySpell[clean], slot)
                    end
                end

            elseif aType == "item" and id and id > 0 then
                FC.actionSlotsByItem[id] = FC.actionSlotsByItem[id] or {}
                table.insert(FC.actionSlotsByItem[id], slot)
            end
        end
    end

    -- Invalidate cached action slots and range flags so they re-resolve to new action bar slots
    local cdSlots = FC.GetCooldownSlots and FC:GetCooldownSlots() or (ForeverClassesDB and ForeverClassesDB.cooldownSlots)
    if cdSlots then
        for _, s in pairs(cdSlots) do
            if type(s) == "table" then
                s.actionSlot = nil
                s.noRange = nil
            end
        end
    end
end

function FC:LearnSliceAndDiceDuration(dur)
    if not dur or dur < 8 or dur > 35 then return end
    local baseDurs = { 9, 12, 15, 18, 21 }
    for _, base in ipairs(baseDurs) do
        local ratio = dur / base
        if math.abs(ratio - 1.45) < 0.06 then
            FC.improvedSliceAndDiceRank = 3
            FC.improvedSliceAndDiceMult = 1.45
            FC.improvedSliceAndDiceSource = "ObservedBuff(" .. tostring(math.floor(dur + 0.5)) .. "s)"
            local charData = FC.GetCharData and FC:GetCharData()
            if charData then
                charData.improvedSliceAndDiceRank = 3
                charData.improvedSliceAndDiceMult = 1.45
                charData.improvedSliceAndDiceSource = FC.improvedSliceAndDiceSource
            end
            return
        elseif math.abs(ratio - 1.30) < 0.06 then
            FC.improvedSliceAndDiceRank = 2
            FC.improvedSliceAndDiceMult = 1.30
            FC.improvedSliceAndDiceSource = "ObservedBuff(" .. tostring(math.floor(dur + 0.5)) .. "s)"
            local charData = FC.GetCharData and FC:GetCharData()
            if charData then
                charData.improvedSliceAndDiceRank = 2
                charData.improvedSliceAndDiceMult = 1.30
                charData.improvedSliceAndDiceSource = FC.improvedSliceAndDiceSource
            end
            return
        elseif math.abs(ratio - 1.15) < 0.06 then
            FC.improvedSliceAndDiceRank = 1
            FC.improvedSliceAndDiceMult = 1.15
            FC.improvedSliceAndDiceSource = "ObservedBuff(" .. tostring(math.floor(dur + 0.5)) .. "s)"
            local charData = FC.GetCharData and FC:GetCharData()
            if charData then
                charData.improvedSliceAndDiceRank = 1
                charData.improvedSliceAndDiceMult = 1.15
                charData.improvedSliceAndDiceSource = FC.improvedSliceAndDiceSource
            end
            return
        end
    end
end

function FC:UpdateTalentCache()
    if InCombatLockdown and InCombatLockdown() then return end

    local _, classToken = UnitClass("player")
    local charData = FC.GetCharData and FC:GetCharData()

    -- Shaman: Detect Improved Stormstrike (Rank 1 = 50%, Rank 2 = 100% chance to reset Stormstrike cooldown on Dodge or Parry)
    if classToken == "SHAMAN" then
        if not FC.improvedStormstrikeRank then
            if charData and charData.improvedStormstrikeRank then
                FC.improvedStormstrikeRank = charData.improvedStormstrikeRank
                FC.improvedStormstrikeSource = charData.improvedStormstrikeSource or "SavedDB"
            end
        end

        local stormRank = nil
        local stormSource = nil

        -- 1. Check TalentsForeverBookDB SavedVariables directly
        if _G.TalentsForeverBookDB and _G.TalentsForeverBookDB.chars then
            local pName = UnitName and UnitName("player")
            local pRealm = GetRealmName and GetRealmName()
            local charKey = (pName and pRealm) and (pName .. "-" .. pRealm) or nil
            local cData = charKey and _G.TalentsForeverBookDB.chars[charKey]
            if cData and cData.plan and cData.plan.ranks and cData.plan.ranks[2] then
                local r = cData.plan.ranks[2][16]
                if type(r) == "number" then
                    stormRank = r
                    stormSource = "TalentsForeverBookDB"
                end
            end
        end

        -- 2. Check TalentsForeverBook runtime table
        if (not stormRank) and _G.TalentsForeverBook and _G.TalentsForeverBook.Game then
            local G = _G.TalentsForeverBook.Game
            if G.Rank then
                local ok, r = pcall(G.Rank, 2, 16)
                if ok and type(r) == "number" then
                    stormRank = r
                    stormSource = "TalentsForeverBook.Rank"
                end
            end
            if (not stormRank) and G.live and G.live.bySpell and G.live.bySpell[1223031] then
                local n = G.live.bySpell[1223031]
                if n and n.rank then
                    stormRank = n.rank
                    stormSource = "TalentsForeverBook.bySpell"
                end
            end
            if (not stormRank) and G.live and G.live.byNode and G.live.byNode[104742] then
                local n = G.live.byNode[104742]
                if n and n.rank then
                    stormRank = n.rank
                    stormSource = "TalentsForeverBook.byNode"
                end
            end
        end

        -- 3. Check modern C_Traits / C_ClassTalents (node 104742, tree 1082)
        if (not stormRank) and C_Traits and C_Traits.GetNodeInfo then
            local cfg = nil
            if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
                local ok, id = pcall(C_ClassTalents.GetActiveConfigID)
                if ok and id and id > 0 then cfg = id end
            end
            if (not cfg or cfg <= 0) and C_Traits.GetConfigIDByTreeID then
                local ok, id = pcall(C_Traits.GetConfigIDByTreeID, 1082)
                if ok and id and id > 0 then cfg = id end
            end
            if (not cfg or cfg <= 0) and C_Traits.GetConfigIDBySystemID then
                for sys = 1, 40 do
                    local okSys, testCfg = pcall(C_Traits.GetConfigIDBySystemID, sys)
                    if okSys and testCfg and testCfg > 0 then
                        local okN, n = pcall(C_Traits.GetNodeInfo, testCfg, 104742)
                        if okN and n and (n.activeRank or n.ranksPurchased or n.currentRank) then
                            cfg = testCfg
                            break
                        end
                    end
                end
            end
            if cfg and cfg > 0 then
                local okN, n = pcall(C_Traits.GetNodeInfo, cfg, 104742)
                if okN and n then
                    local r = n.activeRank or n.ranksPurchased or n.currentRank
                    if type(r) == "number" then
                        stormRank = r
                        stormSource = "C_Traits(104742)"
                    end
                end
            end
        end

        -- 4. Check IsPlayerSpell / IsSpellKnown (Spell ID 1223031)
        if (not stormRank) then
            local hasSpell = false
            if IsPlayerSpell and pcall(IsPlayerSpell, 1223031) then
                hasSpell = IsPlayerSpell(1223031)
            elseif IsSpellKnown and pcall(IsSpellKnown, 1223031) then
                hasSpell = IsSpellKnown(1223031)
            end
            if hasSpell then
                stormRank = 2
                stormSource = "IsPlayerSpell(1223031)"
            end
        end

        -- 5. Classic Era / Vanilla GetTalentInfo fallback
        if (not stormRank) and GetTalentInfo then
            pcall(function()
                local numTabs = 3
                if GetNumTalentTabs then
                    local okTabs, count = pcall(GetNumTalentTabs)
                    if okTabs and type(count) == "number" and count > 0 then numTabs = count end
                end
                for tab = 1, numTabs do
                    local numTalents = 25
                    if GetNumTalents then
                        local okNum, count = pcall(GetNumTalents, tab)
                        if okNum and type(count) == "number" and count > 0 then numTalents = count end
                    end
                    for t = 1, numTalents do
                        local ok1, name, icon, tier, col, rank, maxRank = pcall(GetTalentInfo, tab, t)
                        if ok1 and name and type(name) == "string" then
                            local clean = string.lower(strtrim and strtrim(name) or name)
                            if clean:find("improved stormstrike") then
                                stormRank = tonumber(rank) or 0
                                stormSource = "GetTalentInfo(" .. tab .. "," .. t .. ")"
                                return
                            end
                        end
                    end
                    if stormRank then return end
                end
            end)
        end

        if stormRank ~= nil then
            FC.improvedStormstrikeRank = stormRank
            FC.improvedStormstrikeSource = stormSource or "Detected"
            if charData then
                charData.improvedStormstrikeRank = stormRank
                charData.improvedStormstrikeSource = FC.improvedStormstrikeSource
            end
        else
            FC.improvedStormstrikeRank = (charData and charData.improvedStormstrikeRank) or FC.improvedStormstrikeRank or 0
            FC.improvedStormstrikeSource = (charData and charData.improvedStormstrikeSource) or FC.improvedStormstrikeSource or "None"
        end
        return
    end

    if classToken ~= "ROGUE" then return end

    -- 1. Preserve existing multiplier from memory or character DB
    if not FC.improvedSliceAndDiceMult or FC.improvedSliceAndDiceMult <= 1.0 then
        if charData and charData.improvedSliceAndDiceMult and charData.improvedSliceAndDiceMult > 1.0 then
            FC.improvedSliceAndDiceMult = charData.improvedSliceAndDiceMult
            FC.improvedSliceAndDiceRank = charData.improvedSliceAndDiceRank or 3
            FC.improvedSliceAndDiceSource = charData.improvedSliceAndDiceSource or "SavedDB"
        end
    end

    local detectedRank = nil
    local detectedMaxRank = nil
    local detectionMethod = nil

    -- 2. Classic Era / Vanilla GetTalentInfo (Try clean 2-arg first, then 5-arg)
    if GetTalentInfo then
        pcall(function()
            local numTabs = 3
            if GetNumTalentTabs then
                local okTabs, count = pcall(GetNumTalentTabs)
                if okTabs and type(count) == "number" and count > 0 then
                    numTabs = count
                end
            end
            for tab = 1, numTabs do
                local numTalents = 25
                if GetNumTalents then
                    local okNum, count = pcall(GetNumTalents, tab)
                    if okNum and type(count) == "number" and count > 0 then
                        numTalents = count
                    end
                end
                for t = 1, numTalents do
                    -- 2a. Clean 2-arg call (canonical Classic API)
                    local ok1, name, icon, tier, col, rank, maxRank = pcall(GetTalentInfo, tab, t)
                    if ok1 and name and type(name) == "string" then
                        local clean = string.lower(strtrim and strtrim(name) or name)
                        if clean:find("improved slice") and clean:find("dice") then
                            detectedRank = tonumber(rank) or 0
                            detectedMaxRank = tonumber(maxRank) or 3
                            detectionMethod = "GetTalentInfo(2-arg)"
                            return
                        end
                    end
                    -- 2b. 5-arg call with activeGroup
                    local activeGroup = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
                    local ok2, name2, icon2, tier2, col2, rank2, maxRank2 = pcall(GetTalentInfo, tab, t, false, false, activeGroup)
                    if ok2 and name2 and type(name2) == "string" then
                        local clean = string.lower(strtrim and strtrim(name2) or name2)
                        if clean:find("improved slice") and clean:find("dice") then
                            detectedRank = tonumber(rank2) or 0
                            detectedMaxRank = tonumber(maxRank2) or 3
                            detectionMethod = "GetTalentInfo(5-arg)"
                            return
                        end
                    end
                end
                if detectedRank then return end
            end
        end)
    end

    -- 3. Modern C_Traits / C_ClassTalents (10.0+ / 11.0+ / 12.0)
    if not detectedRank and C_ClassTalents and C_Traits and C_ClassTalents.GetActiveConfigID and C_Traits.GetTreesForConfig then
        pcall(function()
            local configID = C_ClassTalents.GetActiveConfigID()
            if not configID or configID == 0 then return end
            local trees = C_Traits.GetTreesForConfig(configID) or {}
            for _, treeID in ipairs(trees) do
                local nodes = C_Traits.GetTreeNodes(treeID) or {}
                for _, nodeID in ipairs(nodes) do
                    local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                    if nodeInfo and nodeInfo.currentRank and nodeInfo.currentRank > 0 then
                        local entryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
                        if entryID then
                            local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
                            if entryInfo and entryInfo.definitionID then
                                local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                                if defInfo and defInfo.spellID then
                                    local sName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(defInfo.spellID))
                                        or (GetSpellInfo and GetSpellInfo(defInfo.spellID))
                                    if sName then
                                        local clean = string.lower(strtrim and strtrim(sName) or sName)
                                        if clean:find("improved slice") and clean:find("dice") then
                                            detectedRank = nodeInfo.currentRank
                                            detectedMaxRank = nodeInfo.maxRanks or 3
                                            detectionMethod = "C_Traits"
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if detectedRank then return end
            end
        end)
    end

    -- 4. Tooltip Scan of Slice and Dice (1 point : 13 sec / 9 sec)
    if not detectedRank then
        pcall(function()
            local text = nil
            if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
                local ok, data = pcall(C_TooltipInfo.GetSpellByID, 5171)
                if ok and data and data.lines then
                    for _, line in ipairs(data.lines) do
                        if line.leftText then
                            text = (text and (text .. "\n") or "") .. line.leftText
                        end
                    end
                end
            end
            if not text then
                if not FC.scanTooltip then
                    FC.scanTooltip = CreateFrame("GameTooltip", "FCScanTooltip", UIParent, "GameTooltipTemplate")
                    FC.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
                end
                FC.scanTooltip:ClearLines()
                if FC.scanTooltip.SetSpellByID then
                    pcall(FC.scanTooltip.SetSpellByID, FC.scanTooltip, 5171)
                    for i = 1, 10 do
                        local line = _G["FCScanTooltipTextLeft" .. i]
                        local t = line and line:GetText()
                        if t then
                            text = (text and (text .. "\n") or "") .. t
                        end
                    end
                end
            end
            if text then
                local lower = string.lower(text)
                local s1 = lower:match("1%s*point[^%d]*(%d+)%s*sec") or lower:match("1%s*pt[^%d]*(%d+)%s*sec") or lower:match("1%s*point[^%d]*(%d+)")
                local num1 = tonumber(s1)
                if num1 and num1 >= 9 and num1 <= 15 then
                    if num1 == 13 then
                        detectedRank = 3
                        detectedMaxRank = 3
                    elseif num1 == 12 then
                        detectedRank = 2
                        detectedMaxRank = 3
                    elseif num1 == 10 or num1 == 11 then
                        detectedRank = 1
                        detectedMaxRank = 3
                    elseif num1 == 9 then
                        detectedRank = 0
                        detectedMaxRank = 3
                    end
                    detectionMethod = "TooltipScan(" .. num1 .. "s)"
                end
            end
        end)
    end

    -- 5. Calculate and apply multiplier
    if detectedRank ~= nil then
        local maxR = detectedMaxRank or 3
        local perRank = (maxR == 2) and 0.25 or 0.15
        local mult = 1.0 + (detectedRank * perRank)
        FC.improvedSliceAndDiceRank = detectedRank
        FC.improvedSliceAndDiceMult = mult
        FC.improvedSliceAndDiceSource = detectionMethod
        if charData then
            charData.improvedSliceAndDiceRank = detectedRank
            charData.improvedSliceAndDiceMult = mult
            charData.improvedSliceAndDiceSource = detectionMethod
        end
    elseif not FC.improvedSliceAndDiceMult or FC.improvedSliceAndDiceMult <= 1.0 then
        if charData and charData.improvedSliceAndDiceMult and charData.improvedSliceAndDiceMult > 1.0 then
            FC.improvedSliceAndDiceMult = charData.improvedSliceAndDiceMult
            FC.improvedSliceAndDiceRank = charData.improvedSliceAndDiceRank or 3
            FC.improvedSliceAndDiceSource = charData.improvedSliceAndDiceSource or "SavedDB"
        else
            FC.improvedSliceAndDiceMult = 1.0
            FC.improvedSliceAndDiceRank = 0
            FC.improvedSliceAndDiceSource = "Default"
        end
    end
end

function FC:UpdateSpellRanksCache()
    FC.spellRanksCache = {}
    FC.highestRankBySpellName = {}
    FC.spellRanksLastUpdate = GetTime()

    -- 1. Modern C_SpellBook (11.0+)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
        local okLines, numSkillLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        if okLines and numSkillLines and numSkillLines > 0 then
            for i = 1, numSkillLines do
                local okLine, sLine = pcall(C_SpellBook.GetSpellBookSkillLineInfo, i)
                if okLine and sLine and not sLine.isGuild then
                    local numItems = sLine.numSpellBookItems or 0
                    local offset = sLine.itemIndexOffset or 0
                    local bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
                    for s = offset + 1, offset + numItems do
                        local spellName = nil
                        local spellID = nil

                        if C_SpellBook.GetSpellBookItemInfo then
                            local okInfo, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, s, bank)
                            if okInfo and type(itemInfo) == "table" then
                                spellName = itemInfo.name
                                spellID = itemInfo.actionID or itemInfo.spellID
                            end
                        end
                        if not spellID and C_SpellBook.GetSpellBookItemType then
                            local okType, iType, aID = pcall(C_SpellBook.GetSpellBookItemType, s, bank)
                            if okType and aID and aID > 0 then
                                spellID = aID
                            end
                        end
                        if not spellName and C_SpellBook.GetSpellBookItemName then
                            local okN, n = pcall(C_SpellBook.GetSpellBookItemName, s, bank)
                            if okN and n and n ~= "" then
                                spellName = n
                            end
                        end
                        if not spellName and spellID and C_Spell and C_Spell.GetSpellInfo then
                            local okInf, inf = pcall(C_Spell.GetSpellInfo, spellID)
                            if okInf and inf and inf.name then spellName = inf.name end
                        end

                        if spellName and spellID and spellID > 0 then
                            local clean = string.lower((strtrim and strtrim(spellName)) or spellName)
                            FC.spellRanksCache[clean] = FC.spellRanksCache[clean] or {}
                            table.insert(FC.spellRanksCache[clean], spellID)
                            FC.highestRankBySpellName[clean] = spellID
                        end
                    end
                end
            end
        end
    end

    -- 2. Classic / Legacy GetNumSpellTabs & GetSpellTabInfo
    if GetNumSpellTabs and GetSpellTabInfo then
        local okTabs, numTabs = pcall(GetNumSpellTabs)
        if okTabs and numTabs and numTabs > 0 then
            for t = 1, numTabs do
                local okTab, _, _, offset, numSpells = pcall(GetSpellTabInfo, t)
                if okTab and offset and numSpells then
                    for s = offset + 1, offset + numSpells do
                        local spellName = nil
                        local spellID = nil

                        if GetSpellBookItemInfo then
                            local okInfo, iType, aID = pcall(GetSpellBookItemInfo, s, "spell")
                            if okInfo and aID and aID > 0 then
                                spellID = aID
                            end
                        end
                        if GetSpellBookItemName then
                            local okN, n = pcall(GetSpellBookItemName, s, "spell")
                            if okN and n and n ~= "" then
                                spellName = n
                            end
                        end
                        if not spellName and spellID and GetSpellInfo then
                            local okN, n = pcall(GetSpellInfo, spellID)
                            if okN and n and n ~= "" then spellName = n end
                        end

                        if spellName and spellID and spellID > 0 then
                            local clean = string.lower((strtrim and strtrim(spellName)) or spellName)
                            FC.spellRanksCache[clean] = FC.spellRanksCache[clean] or {}
                            table.insert(FC.spellRanksCache[clean], spellID)
                            FC.highestRankBySpellName[clean] = spellID
                        end
                    end
                end
            end
        end
    end
end

local GetPlayerBuffs

local function QueryCooldownAPI(func, arg, arg2)
    if not func or not arg then return nil end
    local ok, a1, a2, a3, a4 = false, nil, nil, nil, nil
    if arg2 ~= nil then
        ok, a1, a2, a3, a4 = pcall(func, arg, arg2)
    else
        ok, a1, a2, a3, a4 = pcall(func, arg)
    end
    if not ok or not a1 then return nil end

    -- Table return (Modern C_Spell or modern wrapper)
    if type(a1) == "table" then
        local st = a1.startTime or a1.start or a1[1] or 0
        local dur = a1.duration or a1.dur or a1[2] or 0
        local en = (a1.isEnabled ~= false and a1.enable ~= false)
        local mr = a1.modRate or 1
        local isAct = (a1.isActive == true)
        local sec = IsSecret(st) or IsSecret(dur)
        if sec then
            return st, dur, en, mr, true, isAct
        end
        return (tonumber(st) or 0), (tonumber(dur) or 0), en, (tonumber(mr) or 1), false, isAct
    end

    -- Multiple values return (Classic GetSpellCooldown / GetItemCooldown / GetActionCooldown)
    if type(a1) == "number" or IsSecret(a1) then
        local st = a1
        local dur = a2 or 0
        local en = (a3 ~= false and a3 ~= 0)
        local mr = a4 or 1
        local sec = IsSecret(st) or IsSecret(dur)
        if sec then
            return st, dur, en, mr, true, false
        end
        return (tonumber(st) or 0), (tonumber(dur) or 0), en, (tonumber(mr) or 1), false, false
    end

    return nil
end

FC.activeCooldowns = FC.activeCooldowns or {}
FC.cachedDurations = FC.cachedDurations or {}
FC.activeTotemSlots = FC.activeTotemSlots or {}
FC.totemPositions = FC.totemPositions or {}
FC.cachedTotemDurations = FC.cachedTotemDurations or (ForeverClassesDB and ForeverClassesDB.cachedTotemDurations) or {}

local function CleanTotemName(name)
    if not name then return "" end
    local s = string.lower(name)
    s = s:gsub("%s*%b()", "")
    s = s:gsub("%s+[ivxlcdm]+$", "")
    s = s:gsub("%s+%d+$", "")
    return (strtrim and strtrim(s)) or s:match("^%s*(.-)%s*$") or s
end

local TOTEM_SPELL_SLOTS = {
    -- Fire Totems (Slot 1)
    ["searing totem"] = 1,
    ["magma totem"] = 1,
    ["fire nova totem"] = 1,
    ["flametongue totem"] = 1,
    ["frost resistance totem"] = 1,
    ["fire elemental totem"] = 1,

    -- Earth Totems (Slot 2)
    ["stoneskin totem"] = 2,
    ["strength of earth totem"] = 2,
    ["stoneclaw totem"] = 2,
    ["earthbind totem"] = 2,
    ["tremor totem"] = 2,
    ["earth elemental totem"] = 2,

    -- Water Totems (Slot 3)
    ["healing stream totem"] = 3,
    ["mana spring totem"] = 3,
    ["poison cleansing totem"] = 3,
    ["disease cleansing totem"] = 3,
    ["fire resistance totem"] = 3,
    ["mana tide totem"] = 3,

    -- Air Totems (Slot 4)
    ["windfury totem"] = 4,
    ["grace of air totem"] = 4,
    ["nature resistance totem"] = 4,
    ["windwall totem"] = 4,
    ["grounding totem"] = 4,
    ["sentry totem"] = 4,
    ["tranquil air totem"] = 4,
    ["wrath of air totem"] = 4,
}

local STANDARD_TOTEM_DURATIONS = {
    -- Earth Totems (5 min in WoW Forever)
    ["stoneskin totem"] = 300,
    ["strength of earth totem"] = 300,
    ["tremor totem"] = 300,
    ["stoneclaw totem"] = 15,
    ["earthbind totem"] = 45,
    ["earth elemental totem"] = 120,

    -- Fire Totems (5 min in WoW Forever)
    ["searing totem"] = 300,
    ["magma totem"] = 20,
    ["fire nova totem"] = 5,
    ["flametongue totem"] = 300,
    ["frost resistance totem"] = 300,
    ["fire elemental totem"] = 120,

    -- Water Totems (5 min in WoW Forever)
    ["healing stream totem"] = 300,
    ["mana spring totem"] = 300,
    ["poison cleansing totem"] = 300,
    ["disease cleansing totem"] = 300,
    ["fire resistance totem"] = 300,
    ["mana tide totem"] = 12,

    -- Air Totems (5 min in WoW Forever)
    ["windfury totem"] = 300,
    ["grace of air totem"] = 300,
    ["nature resistance totem"] = 300,
    ["windwall totem"] = 300,
    ["grounding totem"] = 45,
    ["sentry totem"] = 300,
    ["tranquil air totem"] = 300,
    ["wrath of air totem"] = 300,
}

local TOTEM_RANGE_DATA = {
    -- Earth Totems
    ["stoneskin totem"] = { buff = "stoneskin", range = 20 },
    ["strength of earth totem"] = { buff = "strength of earth", range = 20 },
    ["stoneclaw totem"] = { range = 100 },
    ["earthbind totem"] = { range = 100 },
    ["tremor totem"] = { range = 30 },
    ["earth elemental totem"] = { range = 100 },

    -- Fire Totems
    ["searing totem"] = { range = 100 },
    ["magma totem"] = { range = 100 },
    ["fire nova totem"] = { range = 100 },
    ["flametongue totem"] = { buff = "flametongue", range = 20 },
    ["frost resistance totem"] = { buff = "frost resistance", range = 20 },
    ["fire elemental totem"] = { range = 100 },

    -- Water Totems
    ["healing stream totem"] = { buff = "healing stream", range = 20 },
    ["mana spring totem"] = { buff = "mana spring", range = 20 },
    ["poison cleansing totem"] = { range = 30 },
    ["disease cleansing totem"] = { range = 30 },
    ["fire resistance totem"] = { buff = "fire resistance", range = 20 },
    ["mana tide totem"] = { buff = "mana tide", altBuff = "mana tide totem", range = 30 },

    -- Air Totems
    ["windfury totem"] = { buff = "windfury", altBuff = "windfury totem", range = 20 },
    ["grace of air totem"] = { buff = "grace of air", range = 20 },
    ["nature resistance totem"] = { buff = "nature resistance", range = 20 },
    ["windwall totem"] = { buff = "windwall", range = 20 },
    ["grounding totem"] = { buff = "grounding totem effect", altBuff = "grounding totem", range = 30 },
    ["sentry totem"] = { range = 100 },
    ["tranquil air totem"] = { buff = "tranquil air", range = 20 },
    ["wrath of air totem"] = { buff = "wrath of air", range = 20 },
}

function FC:GetTotemData(spellName, cleanName)
    if not spellName then return nil end
    local sClean = cleanName or CleanTotemName(spellName)
    if not sClean:find("totem") then return nil end

    local now = GetTime()
    local inCombat = InCombatLockdown and InCombatLockdown()

    -- 1. If out of combat and GetTotemInfo is available, sync into FC.activeTotemSlots
    if not inCombat and GetTotemInfo then
        local maxSlots = MAX_TOTEMS or 4
        for slot = 1, maxSlots do
            local ok, haveTotem, totemName, startTime, duration, icon = pcall(GetTotemInfo, slot)
            if ok and haveTotem and not IsSecret(haveTotem) and haveTotem == true and totemName and not IsSecret(totemName) and totemName ~= "" then
                local numDur = (not IsSecret(duration) and tonumber(duration)) or 0
                local numStart = (not IsSecret(startTime) and tonumber(startTime)) or 0
                local tClean = CleanTotemName(totemName)
                if numDur > 0 then
                    FC.cachedTotemDurations = FC.cachedTotemDurations or {}
                    FC.cachedTotemDurations[tClean] = numDur
                    if ForeverClassesDB then
                        ForeverClassesDB.cachedTotemDurations = ForeverClassesDB.cachedTotemDurations or {}
                        ForeverClassesDB.cachedTotemDurations[tClean] = numDur
                    end
                else
                    numDur = (FC.cachedTotemDurations and FC.cachedTotemDurations[tClean]) or STANDARD_TOTEM_DURATIONS[tClean] or 300
                end
                if numStart <= 0 then
                    numStart = now
                end
                local rem = (numStart + numDur) - now
                if rem > 0 then
                    FC.activeTotemSlots = FC.activeTotemSlots or {}
                    FC.activeTotemSlots[slot] = {
                        slot = slot,
                        name = totemName,
                        startTime = numStart,
                        duration = numDur,
                        icon = icon,
                    }
                else
                    if FC.activeTotemSlots then FC.activeTotemSlots[slot] = nil end
                end
            else
                if FC.activeTotemSlots then FC.activeTotemSlots[slot] = nil end
            end
        end
    end

    -- 2. Query from FC.activeTotemSlots (always safe in combat & out of combat)
    if FC.activeTotemSlots then
        for slot = 1, 4 do
            local tData = FC.activeTotemSlots[slot]
            if tData and tData.name then
                local tClean = CleanTotemName(tData.name)
                if sClean == tClean or sClean:find(tClean, 1, true) or tClean:find(sClean, 1, true) then
                    local rem = (tData.startTime + tData.duration) - now
                    if rem > 0 then
                        return {
                            slot = slot,
                            name = tData.name,
                            start = tData.startTime,
                            duration = tData.duration,
                            remaining = rem,
                            icon = tData.icon,
                        }
                    end
                end
            end
        end
    end

    return nil
end

local OFF_GCD_SPELLS = {
    ["pummel"] = true,
    ["shield bash"] = true,
    ["kick"] = true,
    ["counterspell"] = true,
    ["wind shear"] = true,
    ["bloodrage"] = true,
    ["berserker rage"] = true,
    ["shield wall"] = true,
    ["retaliation"] = true,
    ["recklessness"] = true,
    ["last stand"] = true,
    ["ice block"] = true,
    ["cold blood"] = true,
    ["preparation"] = true,
    ["inner focus"] = true,
    ["nature's swiftness"] = true,
    ["elemental mastery"] = true,
    ["heroic strike"] = true,
    ["cleave"] = true,
    ["raptor strike"] = true,
    ["evasion"] = true,
    ["sprint"] = true,
    ["vanish"] = true,
    ["cloak of shadows"] = true,
}

function FC:GetBaseGCDDuration()
    local _, class = UnitClass("player")
    if class == "ROGUE" then
        return 1.0
    elseif class == "DRUID" then
        local form = GetShapeshiftForm and GetShapeshiftForm()
        if form == 3 then -- Cat form
            return 1.0
        end
    end

    local haste = (GetHaste and GetHaste()) or (UnitSpellHaste and UnitSpellHaste("player")) or 0
    if haste and not IsSecret(haste) and haste > 0 then
        return math.max(0.75, 1.5 / (1 + (haste / 100)))
    end

    return 1.5
end

function FC:TriggerGCD(spellName)
    if spellName then
        local clean = string.lower((strtrim and strtrim(spellName)) or spellName)
        if OFF_GCD_SPELLS[clean] then
            return -- Off-GCD spell does not trigger GCD
        end
    end

    local now = GetTime()
    local dur = FC:GetBaseGCDDuration()

    FC.gcdStart = now
    FC.gcdDuration = dur
    FC.needsCooldownRefresh = true
end

function FC:GetGCDData()
    local now = GetTime()

    -- 1. Query native Blizzard GCD spell (61304) when out of combat / unsecret
    if not (InCombatLockdown and InCombatLockdown()) then
        if GetSpellCooldown then
            local ok, st, dur = pcall(GetSpellCooldown, 61304)
            if ok and st and dur and not IsSecret(st) and not IsSecret(dur) then
                local numSt = tonumber(st)
                local numDur = tonumber(dur)
                if numSt and numDur and numDur > 0 and numDur <= 1.5 then
                    local rem = (numSt + numDur) - now
                    if rem > 0.02 then
                        return numSt, numDur, rem
                    end
                end
            end
        elseif C_Spell and C_Spell.GetSpellCooldown then
            local ok, info = pcall(C_Spell.GetSpellCooldown, 61304)
            if ok and info and type(info) == "table" then
                local st = tonumber(info.startTime)
                local dur = tonumber(info.duration)
                if st and dur and dur > 0 and dur <= 1.5 then
                    local rem = (st + dur) - now
                    if rem > 0.02 then
                        return st, dur, rem
                    end
                end
            end
        end
    end

    -- 2. Event-driven GCD Tracker (Immune to secret values in combat)
    if FC.gcdStart and FC.gcdDuration then
        local rem = (FC.gcdStart + FC.gcdDuration) - now
        if rem > 0.02 then
            return FC.gcdStart, FC.gcdDuration, rem
        else
            FC.gcdStart = nil
            FC.gcdDuration = nil
        end
    end

    return nil, nil, 0
end

local function GetShadowmeldKey()
    if FC.shadowmeldKey then return FC.shadowmeldKey end
    local name
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, 20580)
        if ok and info and info.name then name = info.name end
        if not name then
            local ok2, info2 = pcall(C_Spell.GetSpellInfo, 58984)
            if ok2 and info2 and info2.name then name = info2.name end
        end
    end
    if not name and GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, 20580)
        if ok and n then name = n end
        if not name then
            local ok2, n2 = pcall(GetSpellInfo, 58984)
            if ok2 and n2 then name = n2 end
        end
    end
    if name then
        FC.shadowmeldKey = string.lower((strtrim and strtrim(name)) or string.match(name, "^%s*(.-)%s*$") or name)
        FC.shadowmeldName = name
    else
        FC.shadowmeldKey = "shadowmeld"
        FC.shadowmeldName = "Shadowmeld"
    end
    return FC.shadowmeldKey
end

function FC:GetSpellCooldownDuration(spellID, cleanName)
    if not cleanName then return 0 end

    -- 1. Totems: Only specific totems have spell cooldowns (Grounding, Earthbind, Stoneclaw, Mana Tide)
    if cleanName:find("totem") then
        local cName = CleanTotemName(cleanName)
        local totemCDs = {
            ["grounding totem"] = 15,
            ["earthbind totem"] = 15,
            ["stoneclaw totem"] = 30,
            ["mana tide totem"] = 300,
            ["fire elemental totem"] = 600,
            ["earth elemental totem"] = 600,
        }
        if totemCDs[cName] or totemCDs[cleanName] then
            return totemCDs[cName] or totemCDs[cleanName]
        else
            return 0 -- Non-cooldown totems have 0 spell cooldown!
        end
    end

    -- 2. Cached Durations
    if FC.cachedDurations and FC.cachedDurations[cleanName] then
        return FC.cachedDurations[cleanName]
    end

    -- 3. Base Cooldown from WoW API
    if spellID and GetSpellBaseCooldown then
        local ok, baseMS = pcall(GetSpellBaseCooldown, spellID)
        if ok and baseMS and baseMS > 1500 then
            return baseMS / 1000
        end
    end

    -- 4. Known Cooldowns
    local known = {
        ["stormstrike"] = 8,
        ["earth shock"] = 6,
        ["flame shock"] = 6,
        ["frost shock"] = 6,
        ["fire nova"] = 10,
        ["lava burst"] = 8,
        ["chain lightning"] = 6,
        ["wind shear"] = 6,
        ["lava lash"] = 6,
        ["riptide"] = 6,
        ["unleash elements"] = 15,
        ["shamanistic rage"] = 60,
        ["feral spirit"] = 120,
        ["elemental mastery"] = 180,
        ["nature's swiftness"] = 180,
        ["bloodlust"] = 300,
        ["heroism"] = 300,
        ["kick"] = 10,
        ["pummel"] = 10,
        ["shield slam"] = 6,
        ["concussion blow"] = 45,
        ["bloodrage"] = 60,
        ["whirlwind"] = 10,
        ["mortal strike"] = 6,
        ["overpower"] = 5,
        ["mind blast"] = 8,
        ["shadow word: death"] = 10,
        ["psychic scream"] = 30,
        ["crusader strike"] = 6,
        ["judgement"] = 10,
        ["hammer of justice"] = 60,
        ["arcane shot"] = 6,
        ["concussive shot"] = 12,
        ["aimed shot"] = 6,
        ["multi-shot"] = 10,
        ["fire blast"] = 8,
        ["counterspell"] = 24,
        ["cone of cold"] = 10,
        ["blink"] = 15,
        ["frost nova"] = 25,
        ["stealth"] = 10,
        ["prowl"] = 10,
        ["shadowmeld"] = 10,
    }

    if known[cleanName] then
        return known[cleanName]
    end

    local baseName = CleanTotemName(cleanName)
    if known[baseName] then
        return known[baseName]
    end

    local smKey = FC.shadowmeldKey or GetShadowmeldKey()
    if smKey and (cleanName == smKey or baseName == smKey) then
        return 10
    end

    return 0
end

function FC:IsPlayerShadowmelded()
    if not (InCombatLockdown and InCombatLockdown()) then
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, 20580)
            if ok and aura then return true end
            local ok2, aura2 = pcall(C_UnitAuras.GetPlayerAuraBySpellID, 58984)
            if ok2 and aura2 then return true end
        end
        if AuraUtil and AuraUtil.FindAuraByName then
            local ok, name = pcall(AuraUtil.FindAuraByName, "Shadowmelded", "player")
            if ok and name then return true end
            local ok2, name2 = pcall(AuraUtil.FindAuraByName, "Shadowmeld", "player")
            if ok2 and name2 then return true end
        end
        if GetPlayerBuffs then
            local buffs = GetPlayerBuffs()
            local smKey = FC.shadowmeldKey or (GetShadowmeldKey and GetShadowmeldKey()) or "shadowmeld"
            if buffs["shadowmelded"] or buffs["shadowmeld"] or (smKey and (buffs[smKey] or buffs[smKey .. "ed"])) then
                return true
            end
        end
        return false
    else
        return FC.isShadowmelded or false
    end
end

function FC:CheckStealthStateChange()
    local now = GetTime()

    -- 1. Class Stealth (Rogue Stealth / Druid Prowl)
    local _, classToken = UnitClass("player")
    if classToken == "ROGUE" or classToken == "DRUID" then
        local isCurrentlyStealthed = false
        if IsStealthed and IsStealthed() then
            isCurrentlyStealthed = true
        elseif GetShapeshiftForm and classToken == "ROGUE" and GetShapeshiftForm() == 1 then
            isCurrentlyStealthed = true
        end

        local wasStealthed = FC.isStealthed
        local spellKey = (classToken == "DRUID") and "prowl" or "stealth"
        local spellName = (classToken == "DRUID") and "Prowl" or "Stealth"

        if wasStealthed == nil then
            -- First initialization on login/reload: record state without triggering exit cooldown
            FC.isStealthed = isCurrentlyStealthed
            if isCurrentlyStealthed then
                if FC.activeCooldowns then
                    FC.activeCooldowns[spellKey] = nil
                end
                FC.activeBuffs = FC.activeBuffs or {}
                FC.activeBuffs[spellKey] = { start = now, duration = 0, expires = now + 999999 }
            end
        elseif isCurrentlyStealthed ~= wasStealthed then
            if isCurrentlyStealthed and not wasStealthed then
                -- ENTERED STEALTH: In stealth, the Stealth ability has NO cooldown and shows as active buff
                FC.isStealthed = true
                if FC.activeCooldowns then
                    FC.activeCooldowns[spellKey] = nil
                end
                FC.activeBuffs = FC.activeBuffs or {}
                FC.activeBuffs[spellKey] = { start = now, duration = 0, expires = now + 999999 }
                FC.needsCooldownRefresh = true
                pcall(function() FC:UpdateCooldowns() end)
            elseif not isCurrentlyStealthed and wasStealthed then
                -- EXITED STEALTH: Cooldown starts at the exact moment stealth is broken
                FC.isStealthed = false
                if FC.activeBuffs and FC.activeBuffs[spellKey] then
                    FC.activeBuffs[spellKey] = nil
                end
                local dur = (FC.cachedDurations and FC.cachedDurations[spellKey]) or 10
                if not (InCombatLockdown and InCombatLockdown()) then
                    local st, d
                    if C_Spell and C_Spell.GetSpellCooldown then
                        local sId = (spellKey == "stealth") and 1784 or 5215
                        local ok, info = pcall(C_Spell.GetSpellCooldown, sId)
                        if ok and type(info) == "table" and info.duration and tonumber(info.duration) and tonumber(info.duration) > 1.5 then
                            st = info.startTime
                            d = info.duration
                        end
                    end
                    if (not d or d <= 1.5) and GetSpellCooldown then
                        local ok, s, durSpell = pcall(GetSpellCooldown, spellName)
                        if ok and durSpell and tonumber(durSpell) and tonumber(durSpell) > 1.5 then
                            st = s
                            d = durSpell
                        end
                    end
                    if d and tonumber(d) and tonumber(d) > 1.5 then
                        dur = tonumber(d)
                        if st and tonumber(st) and tonumber(st) > 0 then
                            now = tonumber(st)
                        end
                    end
                end
                FC.activeCooldowns = FC.activeCooldowns or {}
                FC.activeCooldowns[spellKey] = { start = now, duration = dur }
                FC.cachedDurations = FC.cachedDurations or {}
                FC.cachedDurations[spellKey] = dur
                FC.needsCooldownRefresh = true
                pcall(function() FC:UpdateCooldowns() end)
            end
        end
    end

    -- 2. Racial Stealth (Night Elf Shadowmeld)
    local isMelded = FC:IsPlayerShadowmelded()
    local wasMelded = FC.wasShadowmelded
    local smKey = FC.shadowmeldKey or (GetShadowmeldKey and GetShadowmeldKey()) or "shadowmeld"

    if wasMelded == nil then
        FC.wasShadowmelded = isMelded
        FC.isShadowmelded = isMelded
    elseif isMelded ~= wasMelded then
        FC.wasShadowmelded = isMelded
        FC.isShadowmelded = isMelded
        if isMelded and not wasMelded then
            -- ENTERED SHADOWMELD: While melded, ability has NO cooldown
            if FC.activeCooldowns then
                FC.activeCooldowns["shadowmeld"] = nil
                FC.activeCooldowns["shadowmelded"] = nil
                if smKey then FC.activeCooldowns[smKey] = nil end
            end
            FC.needsCooldownRefresh = true
            pcall(function() FC:UpdateCooldowns() end)
        elseif not isMelded and wasMelded then
            -- EXITED SHADOWMELD: 10s cooldown starts AT THE EXACT MOMENT meld is broken
            local dur = 10
            local st = now
            if not (InCombatLockdown and InCombatLockdown()) then
                local d = nil
                if C_Spell and C_Spell.GetSpellCooldown then
                    local ok, info = pcall(C_Spell.GetSpellCooldown, 20580)
                    if ok and type(info) == "table" and info.duration and tonumber(info.duration) and tonumber(info.duration) > 1.5 then
                        st = info.startTime or st
                        d = info.duration
                    end
                end
                if (not d or d <= 1.5) and GetSpellCooldown then
                    local ok, s, durSpell = pcall(GetSpellCooldown, 20580)
                    if ok and durSpell and tonumber(durSpell) and tonumber(durSpell) > 1.5 then
                        st = s or st
                        d = durSpell
                    end
                end
                if (not d or d <= 1.5) and GetSpellCooldown then
                    local ok, s, durSpell = pcall(GetSpellCooldown, "Shadowmeld")
                    if ok and durSpell and tonumber(durSpell) and tonumber(durSpell) > 1.5 then
                        st = s or st
                        d = durSpell
                    end
                end
                if d and tonumber(d) and tonumber(d) > 1.5 then
                    dur = tonumber(d)
                end
            end
            FC.activeCooldowns = FC.activeCooldowns or {}
            FC.activeCooldowns["shadowmeld"] = { start = st, duration = dur }
            FC.activeCooldowns["shadowmelded"] = { start = st, duration = dur }
            if smKey then FC.activeCooldowns[smKey] = { start = st, duration = dur } end
            FC.cachedDurations = FC.cachedDurations or {}
            FC.cachedDurations["shadowmeld"] = dur
            if smKey then FC.cachedDurations[smKey] = dur end
            FC.needsCooldownRefresh = true
            pcall(function() FC:UpdateCooldowns() end)
        end
    end
end

function FC:GetCooldownData(slotData)
    if not slotData then return 0, 0, false, 1, false, false end

    local now = GetTime()
    local sName = slotData.name
    if sName and (not slotData.cleanName or slotData._cachedForName ~= sName) then
        slotData.cleanName = string.lower((strtrim and strtrim(sName)) or string.match(sName, "^%s*(.-)%s*$") or sName)
        slotData.baseName = (CleanTotemName and CleanTotemName(sName)) or slotData.cleanName
        slotData._cachedForName = sName
    end
    local cleanName = slotData.cleanName
    local baseName = slotData.baseName or cleanName
    local sID = (type(slotData.id) == "number" and slotData.id > 100) and slotData.id or nil

    -- While actively in stealth, the Stealth / Prowl ability has NO cooldown
    if (cleanName == "stealth" or cleanName == "prowl") and FC.isStealthed then
        if FC.activeCooldowns and FC.activeCooldowns[cleanName] then
            FC.activeCooldowns[cleanName] = nil
        end
        return 0, 0, false, 1, false, false
    end

    -- While actively Shadowmelded, Shadowmeld has NO cooldown
    local smKey = FC.shadowmeldKey or (GetShadowmeldKey and GetShadowmeldKey()) or "shadowmeld"
    local isShadowmeld = (cleanName == "shadowmeld" or cleanName == "shadowmelded" or cleanName == smKey or baseName == "shadowmeld" or baseName == smKey)
    if isShadowmeld and FC.isShadowmelded then
        if FC.activeCooldowns then
            FC.activeCooldowns["shadowmeld"] = nil
            FC.activeCooldowns["shadowmelded"] = nil
            if smKey then FC.activeCooldowns[smKey] = nil end
        end
        return 0, 0, false, 1, false, false
    end

    -- Clean up non-cooldown totems from activeCooldowns
    if cleanName and cleanName:find("totem") then
        local dur = FC:GetSpellCooldownDuration(sID, cleanName)
        if dur == 0 then
            if FC.activeCooldowns and FC.activeCooldowns[cleanName] then
                FC.activeCooldowns[cleanName] = nil
            end
            return 0, 0, false, 1, false, false
        end
    end

    -- 1. Items
    if slotData.type == "item" then
        local iID = slotData.id
        if iID then
            local st, dur, en, mr = nil, nil, nil, nil
            if C_Item and C_Item.GetItemCooldown then
                st, dur, en, mr = QueryCooldownAPI(C_Item.GetItemCooldown, iID)
            end
            if (not dur or dur == 0) and GetItemCooldown then
                st, dur, en, mr = QueryCooldownAPI(GetItemCooldown, iID)
            end
            local numDur = tonumber(dur) or 0
            local numSt = tonumber(st) or 0
            if numDur > 1.5 and numSt > 0 then
                return numSt, numDur, (en ~= false and en ~= 0), tonumber(mr) or 1, false, false
            end
        end
        return 0, 0, false, 1, false, false
    end

    -- 2. Spells: OUT OF COMBAT -> Query Native Classic/Retail APIs first!
    -- This guarantees 100% synchronization with Blizzard's action bar for all spells,
    -- racials (Shadowmeld), cooldown resets (Preparation/Cold Snap), etc.
    if not (InCombatLockdown and InCombatLockdown()) then
        local st, dur, en, mr = nil, nil, nil, nil
        if sID and GetSpellCooldown then
            st, dur, en, mr = QueryCooldownAPI(GetSpellCooldown, sID)
        end
        if (not dur or dur == 0) and sID and C_Spell and C_Spell.GetSpellCooldown then
            st, dur, en, mr = QueryCooldownAPI(C_Spell.GetSpellCooldown, sID)
        end
        if (not dur or dur == 0) and sName and GetSpellCooldown then
            st, dur, en, mr = QueryCooldownAPI(GetSpellCooldown, sName)
        end
        if (not dur or dur == 0) and baseName and baseName ~= "" and baseName ~= sName and GetSpellCooldown then
            st, dur, en, mr = QueryCooldownAPI(GetSpellCooldown, baseName)
        end
        if (not dur or dur == 0) and isShadowmeld and GetSpellCooldown then
            st, dur, en, mr = QueryCooldownAPI(GetSpellCooldown, 20580)
            if (not dur or dur == 0) and C_Spell and C_Spell.GetSpellCooldown then
                st, dur, en, mr = QueryCooldownAPI(C_Spell.GetSpellCooldown, 20580)
            end
            if (not dur or dur == 0) then
                st, dur, en, mr = QueryCooldownAPI(GetSpellCooldown, "Shadowmeld")
            end
        end

        local numDur = tonumber(dur) or 0
        local numSt = tonumber(st) or 0
        if numDur > 1.5 and numSt > 0 then
            local rem = (numSt + numDur) - now
            if rem > 0.05 then
                if cleanName then
                    FC.activeCooldowns = FC.activeCooldowns or {}
                    local cd = FC.activeCooldowns[cleanName]
                    if cd then
                        cd.start = numSt
                        cd.duration = numDur
                    else
                        FC.activeCooldowns[cleanName] = { start = numSt, duration = numDur }
                    end
                    FC.cachedDurations = FC.cachedDurations or {}
                    FC.cachedDurations[cleanName] = numDur
                end
                if baseName and baseName ~= cleanName then
                    FC.activeCooldowns = FC.activeCooldowns or {}
                    local cd = FC.activeCooldowns[baseName]
                    if cd then
                        cd.start = numSt
                        cd.duration = numDur
                    else
                        FC.activeCooldowns[baseName] = { start = numSt, duration = numDur }
                    end
                end
                if isShadowmeld then
                    FC.activeCooldowns = FC.activeCooldowns or {}
                    local cd1 = FC.activeCooldowns["shadowmeld"]
                    if cd1 then cd1.start = numSt cd1.duration = numDur else FC.activeCooldowns["shadowmeld"] = { start = numSt, duration = numDur } end
                    local cd2 = FC.activeCooldowns["shadowmelded"]
                    if cd2 then cd2.start = numSt cd2.duration = numDur else FC.activeCooldowns["shadowmelded"] = { start = numSt, duration = numDur } end
                    if smKey then
                        local cd3 = FC.activeCooldowns[smKey]
                        if cd3 then cd3.start = numSt cd3.duration = numDur else FC.activeCooldowns[smKey] = { start = numSt, duration = numDur } end
                    end
                end
                return numSt, numDur, (en ~= false and en ~= 0), tonumber(mr) or 1, false, false
            end
        elseif numDur == 0 then
            -- Native engine says no cooldown out of combat: clear any stale event tracker entry
            if cleanName and FC.activeCooldowns then FC.activeCooldowns[cleanName] = nil end
            if baseName and FC.activeCooldowns then FC.activeCooldowns[baseName] = nil end
            if isShadowmeld and FC.activeCooldowns then
                FC.activeCooldowns["shadowmeld"] = nil
                FC.activeCooldowns["shadowmelded"] = nil
                if smKey then FC.activeCooldowns[smKey] = nil end
            end
            return 0, 0, false, 1, false, false
        end
    end

    -- 3. Combat / Event Cooldown Tracker (Used during InCombatLockdown to prevent Lua taint)
    local cd = nil
    if cleanName and FC.activeCooldowns and FC.activeCooldowns[cleanName] then
        cd = FC.activeCooldowns[cleanName]
    elseif baseName and FC.activeCooldowns and FC.activeCooldowns[baseName] then
        cd = FC.activeCooldowns[baseName]
    elseif isShadowmeld and FC.activeCooldowns then
        cd = FC.activeCooldowns["shadowmeld"] or FC.activeCooldowns["shadowmelded"] or (smKey and FC.activeCooldowns[smKey])
    end

    if cd and cd.start and cd.duration then
        local rem = (cd.start + cd.duration) - now
        if rem > 0.05 then
            return cd.start, cd.duration, true, 1, false, false
        else
            FC:Log("CD_EXPIRED", "spell=%s finished (dur=%.1f)", tostring(cleanName), tonumber(cd.duration) or 0)
            if cleanName and FC.activeCooldowns then FC.activeCooldowns[cleanName] = nil end
            if baseName and FC.activeCooldowns then FC.activeCooldowns[baseName] = nil end
            if isShadowmeld and FC.activeCooldowns then
                FC.activeCooldowns["shadowmeld"] = nil
                FC.activeCooldowns["shadowmelded"] = nil
                if smKey then FC.activeCooldowns[smKey] = nil end
            end
        end
    end

    return 0, 0, false, 1, false, false
end


function FC:GetCharges(slotData)
    if not slotData or slotData.type == "item" then return nil end
    if C_Spell and C_Spell.GetSpellCharges then
        local ok, cInfo = pcall(C_Spell.GetSpellCharges, slotData.id or slotData.name)
        if ok and cInfo then
            if type(cInfo) == "table" and cInfo.currentCharges then
                return cInfo.currentCharges, cInfo.maxCharges
            elseif type(cInfo) == "number" then
                return cInfo, select(2, C_Spell.GetSpellCharges(slotData.id or slotData.name))
            end
        end
    elseif GetSpellCharges then
        local ok, cur, max = pcall(GetSpellCharges, slotData.id or slotData.name)
        if ok and cur then return cur, max end
    end
    return nil
end

local function GetActionSlotForSlotData(slotData)
    if not slotData then return nil end
    if slotData.actionSlot then return slotData.actionSlot end
    local found = nil
    if slotData.id and FC.actionSlotsBySpellID and FC.actionSlotsBySpellID[slotData.id] then
        local t = FC.actionSlotsBySpellID[slotData.id]
        if t and t[1] then found = t[1] end
    end
    if not found and slotData.name and FC.actionSlotsBySpell then
        local clean = string.lower((strtrim and strtrim(slotData.name)) or slotData.name)
        local t = FC.actionSlotsBySpell[clean]
        if t and t[1] then found = t[1] end
    end
    if not found and slotData.id and slotData.type == "item" and FC.actionSlotsByItem and FC.actionSlotsByItem[slotData.id] then
        local t = FC.actionSlotsByItem[slotData.id]
        if t and t[1] then found = t[1] end
    end
    if found then
        slotData.actionSlot = found
    end
    return found
end

function FC:IsSlotOutOfRange(slotData)
    if not slotData then return false end
    if slotData.noRange then return false end
    if not UnitExists or not UnitExists("target") then return false end
    if UnitIsDead and UnitIsDead("target") then return false end

    -- 1. Action Slot Check (Direct native WoW ActionButton engine)
    local actSlot = GetActionSlotForSlotData(slotData)
    if actSlot and IsActionInRange then
        local ok, inRange = pcall(IsActionInRange, actSlot)
        if ok and not IsSecret(inRange) then
            if inRange ~= nil then
                return (inRange == false or inRange == 0)
            else
                -- IsActionInRange returned nil -> action has no target range requirement (e.g. self-buff)
                slotData.noRange = true
                return false
            end
        end
    end

    -- 2. Spells (C_Spell.IsSpellInRange / IsSpellInRange)
    if slotData.type == "spell" or not slotData.type then
        local sID = (type(slotData.id) == "number" and slotData.id > 100) and slotData.id or nil
        local sName = slotData.name
        local hasChecked = false

        if C_Spell and C_Spell.IsSpellInRange then
            if sID then
                local ok, inRange = pcall(C_Spell.IsSpellInRange, sID, "target")
                if ok and not IsSecret(inRange) then
                    if inRange ~= nil then
                        return (inRange == false or inRange == 0)
                    else
                        hasChecked = true
                    end
                end
            end
            if sName then
                local ok, inRange = pcall(C_Spell.IsSpellInRange, sName, "target")
                if ok and not IsSecret(inRange) then
                    if inRange ~= nil then
                        return (inRange == false or inRange == 0)
                    else
                        hasChecked = true
                    end
                end
            end
        elseif IsSpellInRange then
            if sID then
                local ok, inRange = pcall(IsSpellInRange, sID, "target")
                if ok and not IsSecret(inRange) then
                    if inRange ~= nil then
                        return (inRange == false or inRange == 0)
                    else
                        hasChecked = true
                    end
                end
            end
            if sName then
                local ok, inRange = pcall(IsSpellInRange, sName, "target")
                if ok and not IsSecret(inRange) then
                    if inRange ~= nil then
                        return (inRange == false or inRange == 0)
                    else
                        hasChecked = true
                    end
                end
            end
        end

        if hasChecked then
            slotData.noRange = true
        end
    end

    -- 3. Items (C_Item.IsItemInRange / IsItemInRange)
    if slotData.type == "item" and slotData.id then
        if C_Item and C_Item.IsItemInRange then
            local ok, inRange = pcall(C_Item.IsItemInRange, slotData.id, "target")
            if ok and not IsSecret(inRange) and inRange ~= nil then
                return (inRange == false or inRange == 0)
            end
        elseif IsItemInRange then
            local ok, inRange = pcall(IsItemInRange, slotData.id, "target")
            if ok and not IsSecret(inRange) and inRange ~= nil then
                return (inRange == false or inRange == 0)
            end
        end
    end

    return false
end

function FC:IsSlotOutOfPower(slotData)
    if not slotData then return false, false end

    -- 1. Action Slot Check
    local actSlot = GetActionSlotForSlotData(slotData)
    if actSlot and IsUsableAction then
        local ok, isUsable, notEnoughMana = pcall(IsUsableAction, actSlot)
        if ok and not IsSecret(notEnoughMana) and not IsSecret(isUsable) and isUsable ~= nil then
            if notEnoughMana == true or notEnoughMana == 1 then
                return true, false
            elseif isUsable == false or isUsable == 0 then
                return false, true
            else
                return false, false
            end
        end
    end

    -- 2. Spells (C_Spell.IsSpellUsable / IsUsableSpell)
    if slotData.type == "spell" or not slotData.type then
        local sID = (type(slotData.id) == "number" and slotData.id > 100) and slotData.id or nil
        local sName = slotData.name

        if C_Spell and C_Spell.IsSpellUsable then
            if sID then
                local ok, isUsable, notEnoughMana = pcall(C_Spell.IsSpellUsable, sID)
                if ok and not IsSecret(notEnoughMana) and not IsSecret(isUsable) and isUsable ~= nil then
                    if notEnoughMana == true or notEnoughMana == 1 then
                        return true, false
                    elseif isUsable == false or isUsable == 0 then
                        return false, true
                    else
                        return false, false
                    end
                end
            end
            if sName then
                local ok, isUsable, notEnoughMana = pcall(C_Spell.IsSpellUsable, sName)
                if ok and not IsSecret(notEnoughMana) and not IsSecret(isUsable) and isUsable ~= nil then
                    if notEnoughMana == true or notEnoughMana == 1 then
                        return true, false
                    elseif isUsable == false or isUsable == 0 then
                        return false, true
                    else
                        return false, false
                    end
                end
            end
        elseif IsUsableSpell then
            if sID then
                local ok, isUsable, notEnoughMana = pcall(IsUsableSpell, sID)
                if ok and not IsSecret(notEnoughMana) and not IsSecret(isUsable) and isUsable ~= nil then
                    if notEnoughMana == true or notEnoughMana == 1 then
                        return true, false
                    elseif isUsable == false or isUsable == 0 then
                        return false, true
                    else
                        return false, false
                    end
                end
            end
            if sName then
                local ok, isUsable, notEnoughMana = pcall(IsUsableSpell, sName)
                if ok and not IsSecret(notEnoughMana) and not IsSecret(isUsable) and isUsable ~= nil then
                    if notEnoughMana == true or notEnoughMana == 1 then
                        return true, false
                    elseif isUsable == false or isUsable == 0 then
                        return false, true
                    else
                        return false, false
                    end
                end
            end
        end
    end

    -- 3. Items
    if slotData.type == "item" and slotData.id then
        if C_Item and C_Item.IsUsableItem then
            local ok, isUsable, notEnoughMana = pcall(C_Item.IsUsableItem, slotData.id)
            if ok and not IsSecret(notEnoughMana) and not IsSecret(isUsable) and isUsable ~= nil then
                if notEnoughMana == true or notEnoughMana == 1 then
                    return true, false
                elseif isUsable == false or isUsable == 0 then
                    return false, true
                else
                    return false, false
                end
            end
        elseif IsUsableItem then
            local ok, isUsable, notEnoughMana = pcall(IsUsableItem, slotData.id)
            if ok and not IsSecret(notEnoughMana) and not IsSecret(isUsable) and isUsable ~= nil then
                if notEnoughMana == true or notEnoughMana == 1 then
                    return true, false
                elseif isUsable == false or isUsable == 0 then
                    return false, true
                else
                    return false, false
                end
            end
        end
    end

    return false, false
end

local STANDARD_BUFF_DURATIONS = {
    -- Paladin
    ["seal of righteousness"] = 30,
    ["seal of the crusader"] = 30,
    ["seal of command"] = 30,
    ["seal of wisdom"] = 30,
    ["seal of light"] = 30,
    ["seal of justice"] = 30,
    ["seal of fury"] = 30,
    ["divine protection"] = 8,
    ["divine shield"] = 12,
    ["blessing of protection"] = 10,
    ["blessing of freedom"] = 10,
    ["blessing of sacrifice"] = 30,
    ["holy shield"] = 10,
    ["righteous fury"] = 1800,

    -- Rogue
    ["sprint"] = 15,
    ["evasion"] = 15,
    ["blade flurry"] = 15,
    ["adrenaline rush"] = 15,
    ["ghostly strike"] = 7,

    -- Warrior
    ["bloodrage"] = 10,
    ["berserker rage"] = 10,
    ["shield wall"] = 10,
    ["retaliation"] = 15,
    ["recklessness"] = 15,
    ["last stand"] = 20,
    ["death wish"] = 30,
    ["sweeping strikes"] = 20,
    ["shield block"] = 5,

    -- Shaman
    ["lightning shield"] = 600,
    ["water shield"] = 600,
    ["earth shield"] = 600,
    ["elemental mastery"] = 30,
    ["nature's swiftness"] = 30,

    -- Mage
    ["ice barrier"] = 60,
    ["mana shield"] = 60,
    ["ice block"] = 10,
    ["arcane power"] = 15,
    ["icy veins"] = 20,
    ["combustion"] = 30,

    -- Priest
    ["power word: shield"] = 30,
    ["renew"] = 15,
    ["fade"] = 10,
    ["inner fire"] = 600,
    ["inner focus"] = 30,
    ["vampiric embrace"] = 60,

    -- Druid
    ["barkskin"] = 12,
    ["innervate"] = 20,
    ["tiger's fury"] = 6,
    ["dash"] = 15,
    ["frenzied regeneration"] = 10,

    -- Hunter
    ["rapid fire"] = 15,
    ["bestial wrath"] = 18,
    ["deterrence"] = 10,
}

local DEFAULT_BUFF_STACKS = {
    ["lightning shield"] = 3,
    ["water shield"] = 3,
    ["earth shield"] = 6,
    ["inner fire"] = 20,
    ["shield block"] = 2,
    ["sweeping strikes"] = 5,
}
FC.DEFAULT_BUFF_STACKS = DEFAULT_BUFF_STACKS

local DEFAULT_BUFF_ICD = {
    ["lightning shield"] = 3.5,
    ["water shield"] = 3.0,
    ["earth shield"] = 3.5,
    ["shield block"] = 0.5,
    ["inner fire"] = 1.0,
    ["sweeping strikes"] = 0.5,
}
FC.DEFAULT_BUFF_ICD = DEFAULT_BUFF_ICD

function FC:GetSpellBuffDuration(cleanName)
    if not cleanName then return nil end
    if FC.knownBuffDurations and FC.knownBuffDurations[cleanName] then
        return FC.knownBuffDurations[cleanName]
    end
    if STANDARD_BUFF_DURATIONS[cleanName] then
        return STANDARD_BUFF_DURATIONS[cleanName]
    end
    if cleanName:find("^seal of ") then
        return 30
    end
    return nil
end

local playerBuffCache = {}
FC.buffsDirty = true

local function SyncShieldFromBuffs(buffs)
    if not buffs then return end
    local shieldSpell = nil
    for buffName in pairs(buffs) do
        if IsShieldSpell(buffName) then
            shieldSpell = buffName
            break
        end
    end

    if shieldSpell then
        if not FC.currentShieldRemaining or (not IsSecret(FC.currentShieldRemaining) and FC.currentShieldRemaining <= 0) then
            local maxVal = FC:ResolveShieldMaxAmount(17, shieldSpell)
            FC.currentShieldRemaining = maxVal
            FC.currentShieldMax = maxVal
            FC.currentShieldSpell = shieldSpell
        end
    else
        FC.currentShieldRemaining = 0
        FC.currentShieldSpell = nil
    end
end
FC.SyncShieldFromBuffs = SyncShieldFromBuffs

GetPlayerBuffs = function()
    if not FC.buffsDirty and next(playerBuffCache) then
        SyncShieldFromBuffs(playerBuffCache)
        return playerBuffCache
    end

    -- In combat lockdown or secret context: Return cached buff data without wiping (zero taint)
    if (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) or (InCombatLockdown and InCombatLockdown()) then
        return playerBuffCache
    end

    FC.buffsDirty = false
    local now = GetTime()
    table.wipe(playerBuffCache)

    FC.auraInstanceToBuff = FC.auraInstanceToBuff or {}
    FC.buffToAuraInstance = FC.buffToAuraInstance or {}

    -- 1. Blizzard AuraUtil.ForEachAura (Most reliable modern scanner)
    if AuraUtil and AuraUtil.ForEachAura then
        local okAuraUtil = pcall(AuraUtil.ForEachAura, "player", "HELPFUL", nil, function(aura)
            if aura and aura.name and not IsSecret(aura.name) then
                local clean = string.lower((strtrim and strtrim(aura.name)) or aura.name)
                local dur = (aura.duration and not IsSecret(aura.duration)) and aura.duration or 0
                local exp = (aura.expirationTime and not IsSecret(aura.expirationTime)) and aura.expirationTime or 0
                local bStart = (exp > 0 and dur > 0) and (exp - dur) or now
                local count = (aura.applications and not IsSecret(aura.applications)) and aura.applications or 0
                local st = (count > 0) and count or (DEFAULT_BUFF_STACKS and DEFAULT_BUFF_STACKS[clean])
                local instID = aura.auraInstanceID

                if instID then
                    FC.auraInstanceToBuff[instID] = clean
                    FC.buffToAuraInstance[clean] = instID
                end

                playerBuffCache[clean] = { expires = exp, duration = dur, start = bStart, count = st, instanceID = instID }

                FC.activeBuffs = FC.activeBuffs or {}
                local ab = FC.activeBuffs[clean]
                if ab then
                    ab.start = bStart
                    ab.duration = dur
                    ab.expires = (exp > 0) and exp or (now + 999999)
                    if ab.stacks ~= st then
                        ab.stacks = st
                        ab.lastStackDecrement = 0
                    end
                    ab.instanceID = instID
                else
                    FC.activeBuffs[clean] = {
                        start = bStart,
                        duration = dur,
                        expires = (exp > 0) and exp or (now + 999999),
                        stacks = st,
                        instanceID = instID,
                        lastStackDecrement = 0,
                    }
                end
                if dur and dur > 0 and dur < 1800 then
                    FC.knownBuffDurations = FC.knownBuffDurations or {}
                    FC.knownBuffDurations[clean] = dur
                end
                if clean == "slice and dice" and FC.LearnSliceAndDiceDuration then
                    FC:LearnSliceAndDiceDuration(dur)
                end
            end
        end, true)
        if okAuraUtil and next(playerBuffCache) then
            SyncShieldFromBuffs(playerBuffCache)
            return playerBuffCache
        end
    end

    -- 2. Modern C_UnitAuras.GetAuraDataByIndex
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        pcall(function()
            for i = 1, 40 do
                local okCall, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
                if not okCall or not aura then break end
                if aura.name and not IsSecret(aura.name) then
                    local clean = string.lower((strtrim and strtrim(aura.name)) or aura.name)
                    local dur = (aura.duration and not IsSecret(aura.duration)) and aura.duration or 0
                    local exp = (aura.expirationTime and not IsSecret(aura.expirationTime)) and aura.expirationTime or 0
                    local bStart = (exp > 0 and dur > 0) and (exp - dur) or now
                    local count = (aura.applications and not IsSecret(aura.applications)) and aura.applications or 0
                    local st = (count > 0) and count or (DEFAULT_BUFF_STACKS and DEFAULT_BUFF_STACKS[clean])
                    local instID = aura.auraInstanceID
                    if instID then
                        FC.auraInstanceToBuff[instID] = clean
                        FC.buffToAuraInstance[clean] = instID
                    end

                    playerBuffCache[clean] = { expires = exp, duration = dur, start = bStart, count = st, instanceID = instID }

                    FC.activeBuffs = FC.activeBuffs or {}
                    local ab = FC.activeBuffs[clean]
                    if ab then
                        ab.start = bStart
                        ab.duration = dur
                        ab.expires = (exp > 0) and exp or (now + 999999)
                        if ab.stacks ~= st then
                            ab.stacks = st
                            ab.lastStackDecrement = 0
                        end
                        ab.instanceID = instID
                    else
                        FC.activeBuffs[clean] = {
                            start = bStart,
                            duration = dur,
                            expires = (exp > 0) and exp or (now + 999999),
                            stacks = st,
                            instanceID = instID,
                            lastStackDecrement = 0,
                        }
                    end
                    if dur and dur > 0 and dur < 1800 then
                        FC.knownBuffDurations = FC.knownBuffDurations or {}
                        FC.knownBuffDurations[clean] = dur
                    end
                    if clean == "slice and dice" and FC.LearnSliceAndDiceDuration then
                        FC:LearnSliceAndDiceDuration(dur)
                    end
                end
            end
        end)
        if next(playerBuffCache) then
            SyncShieldFromBuffs(playerBuffCache)
            return playerBuffCache
        end
    end

    -- 3. Legacy UnitBuff fallback
    if UnitBuff then
        pcall(function()
            for i = 1, 40 do
                local okCall, name, _, count, _, dur, exp = pcall(UnitBuff, "player", i)
                if not okCall or not name then break end
                if not IsSecret(name) then
                    local clean = string.lower((strtrim and strtrim(name)) or name)
                    local numDur = (dur and not IsSecret(dur)) and dur or 0
                    local numExp = (exp and not IsSecret(exp)) and exp or 0
                    local bStart = (numExp > 0 and numDur > 0) and (numExp - numDur) or now
                    local numCount = (count and not IsSecret(count)) and count or 0
                    local st = (numCount > 0) and numCount or (DEFAULT_BUFF_STACKS and DEFAULT_BUFF_STACKS[clean])

                    playerBuffCache[clean] = { expires = numExp, duration = numDur, start = bStart, count = st }

                    FC.activeBuffs = FC.activeBuffs or {}
                    local ab = FC.activeBuffs[clean]
                    if ab then
                        ab.start = bStart
                        ab.duration = numDur
                        ab.expires = (numExp > 0) and numExp or (now + 999999)
                        if ab.stacks ~= st then
                            ab.stacks = st
                            ab.lastStackDecrement = 0
                        end
                    else
                        FC.activeBuffs[clean] = {
                            start = bStart,
                            duration = numDur,
                            expires = (numExp > 0) and numExp or (now + 999999),
                            stacks = st,
                            lastStackDecrement = 0,
                        }
                    end
                end
            end
        end)
    end

    SyncShieldFromBuffs(playerBuffCache)
    return playerBuffCache
end

function FC:GetPlayerBuffDuration(spellName, cleanName)
    if not spellName or IsSecret(spellName) then return nil end
    local cleanTarget = cleanName or string.lower((strtrim and strtrim(spellName)) or string.match(spellName, "^%s*(.-)%s*$") or spellName)
    local now = GetTime()

    -- 1. Native Aura Query (Out of combat / unsecret)
    if not (InCombatLockdown and InCombatLockdown()) and not (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) then
        local buffs = GetPlayerBuffs()
        local b = buffs[cleanTarget]
        if b then
            local rem = 999
            if b.expires and b.expires > 0 then
                rem = b.expires - now
                if rem <= 0.05 then
                    return nil
                end
            end
            local st = (b.count and b.count > 0) and b.count or (DEFAULT_BUFF_STACKS and DEFAULT_BUFF_STACKS[cleanTarget])
            return rem, b.duration, b.start, st, b.instanceID
        else
            -- If native engine says buff is not present while out of combat, clear from activeBuffs
            if FC.activeBuffs and FC.activeBuffs[cleanTarget] then
                FC:Log("BUFF_OOC_DROP", "clean=%s dropped in native buffs (OOC)", cleanTarget)
                FC.activeBuffs[cleanTarget] = nil
            end
        end
    end

    -- 2. Combat / Event-driven Active Buff Tracker (Fallback)
    if FC.activeBuffs and FC.activeBuffs[cleanTarget] then
        local data = FC.activeBuffs[cleanTarget]
        if data and data.expires then
            local rem = data.expires - now
            if rem > 0.05 then
                return rem, data.duration or 0, data.start, data.stacks, data.instanceID
            else
                FC:Log("BUFF_EXPIRED", "clean=%s duration expired (dur=%.1f)", cleanTarget, tonumber(data.duration) or 0)
                FC.activeBuffs[cleanTarget] = nil
            end
        end
    end

    return nil
end

function FC:PopulateDefaultCooldowns(force)
    local charData = FC.GetCharData and FC:GetCharData()
    local slots = FC.GetCooldownSlots and FC:GetCooldownSlots() or ForeverClassesDB.cooldownSlots
    if not slots then
        slots = {}
        ForeverClassesDB.cooldownSlots = slots
    end

    -- If slots already has any ability configured, never overwrite unless forced
    local hasAny = false
    for i = 1, MAX_COOLDOWN_SLOTS do
        if slots[i] then
            hasAny = true
            break
        end
    end
    if hasAny and not force then
        if charData then charData.cooldownDefaultsPopulated = true end
        return
    end

    -- Only populate defaults once per character unless explicitly forced (e.g. by /fc cd reset)
    if charData and charData.cooldownDefaultsPopulated and not force then
        return
    end

    local _, class = UnitClass("player")
    local defaultClassSpells = {
        ["ROGUE"] = { "Sinister Strike", "Gouge", "Evasion", "Sprint", "Kick", "Vanish", "Stealth" },
        ["WARRIOR"] = { "Charge", "Bloodrage", "Rend", "Overpower", "Thunder Clap", "Battle Shout", "Heroic Strike" },
        ["MAGE"] = { "Frost Nova", "Fire Blast", "Blink", "Counterspell", "Arcane Intellect", "Mana Shield", "Cone of Cold" },
        ["PRIEST"] = { "Power Word: Shield", "Renew", "Shadow Word: Pain", "Psychic Scream", "Fade", "Inner Fire", "Smite" },
        ["WARLOCK"] = { "Corruption", "Immolate", "Life Tap", "Fear", "Drain Life", "Create Healthstone", "Demon Armor" },
        ["HUNTER"] = { "Hunter's Mark", "Serpent Sting", "Arcane Shot", "Concussive Shot", "Aspect of the Hawk", "Aspect of the Cheetah", "Mongoose Bite" },
        ["DRUID"] = { "Moonfire", "Wrath", "Rejuvenation", "Healing Touch", "Mark of the Wild", "Thorns", "Bear Form" },
        ["PALADIN"] = { "Judgement", "Seal of Righteousness", "Blessing of Might", "Holy Light", "Lay on Hands", "Divine Protection", "Hammer of Justice" },
        ["SHAMAN"] = { "Lightning Shield", "Flame Shock", "Earth Shock", "Tremor Totem", "Grounding Totem", "Ghost Wolf", "Purge" },
    }

    local spells = defaultClassSpells[class] or { "Attack" }
    local populatedCount = 0

    for i = 1, MAX_COOLDOWN_SLOTS do
        if (not slots[i] or force) and spells[i] then
            local sName = spells[i]
            local isKnown, bookInfo = FC:IsSpellLearned(sName)
            if isKnown then
                local realID = bookInfo and bookInfo.id
                local realIcon = bookInfo and bookInfo.icon
                local realName = (bookInfo and bookInfo.name) or sName

                if not realID or not realIcon then
                    local sInfo = FC:ResolveSpellInfo(sName)
                    if sInfo then
                        realID = realID or sInfo.id
                        realIcon = realIcon or sInfo.icon
                        realName = sInfo.name or realName
                    end
                end

                if realID and realIcon then
                    slots[i] = {
                        type = "spell",
                        id = realID,
                        name = realName,
                        icon = realIcon,
                    }
                    populatedCount = populatedCount + 1
                end
            end
        end
    end

    if charData and (populatedCount > 0 or hasAny) then
        charData.cooldownDefaultsPopulated = true
    end
    ForeverClassesDB.cooldownDefaultsPopulated = true
end

-- ============================================================================
-- Quick Ability Swap System (Sub-slots Flyout)
-- ============================================================================

local MAX_SWAP_SLOTS = 5

function FC:GetCursorSlotData()
    local cType, id, subType, spellID = GetCursorInfo()
    if not cType then return nil end

    local slotData = nil

    if cType == "action" then
        local actionType, actionID = nil, nil
        if GetActionInfo then
            pcall(function() actionType, actionID = GetActionInfo(id) end)
        end
        if actionType == "spell" and actionID and actionID > 0 then
            cType = "spell"
            id = actionID
            spellID = actionID
        elseif actionType == "item" and actionID and actionID > 0 then
            cType = "item"
            id = actionID
        elseif actionType == "macro" and actionID and actionID > 0 then
            local mSpell = nil
            if GetMacroSpell then
                pcall(function() mSpell = GetMacroSpell(actionID) end)
            end
            if mSpell then
                cType = "spell"
                id = mSpell
                spellID = (type(mSpell) == "number" and mSpell > 0) and mSpell or nil
            end
        end
    end

    if cType == "spell" then
        local realSpellID = spellID
        local sName, sIcon

        -- A. If id is already a real numeric spell ID (> 1000)
        if type(id) == "number" and id > 1000 and not realSpellID then
            realSpellID = id
        end

        -- B. If id is a spellbook slot index (<= 1000)
        if type(id) == "number" and id <= 1000 then
            if GetSpellBookItemInfo then
                local ok, itemType, actionID = pcall(GetSpellBookItemInfo, id, subType or "spell")
                if ok and actionID and actionID > 0 then
                    realSpellID = actionID
                end
            end
            if not realSpellID and C_SpellBook and C_SpellBook.GetSpellBookItemType then
                local ok, itemType, actionID = pcall(C_SpellBook.GetSpellBookItemType, id, subType or Enum.SpellBookSpellBank.Player)
                if ok and actionID and actionID > 0 then
                    realSpellID = actionID
                end
            end
            if GetSpellBookItemName then
                local ok, bName = pcall(GetSpellBookItemName, id, subType or "spell")
                if ok and bName and bName ~= "" then
                    sName = bName
                end
            end
            if GetSpellBookItemTexture then
                local ok, tex = pcall(GetSpellBookItemTexture, id, subType or "spell")
                if ok and tex then sIcon = tex end
            end
        end

        -- C. If we have realSpellID, resolve full info
        if realSpellID then
            local info = FC:ResolveSpellInfo(realSpellID)
            if info then
                sName = sName or info.name
                sIcon = sIcon or info.icon
                realSpellID = info.id or realSpellID
            end
        end

        -- D. If we have sName, resolve realSpellID and icon
        if sName then
            local info = FC:ResolveSpellInfo(sName)
            if info then
                sName = info.name
                sIcon = sIcon or info.icon
                realSpellID = info.id or realSpellID
            end
        end

        -- E. Fallback spellbook search
        if sName and (not realSpellID or not sIcon) then
            local bookInfo = FC:FindSpellInSpellBook(sName)
            if bookInfo then
                realSpellID = realSpellID or bookInfo.id
                sIcon = sIcon or bookInfo.icon
                sName = bookInfo.name or sName
            end
        end

        if sName and sIcon then
            local assignedID = realSpellID
            if FC.highestRankBySpellName then
                local clean = string.lower((strtrim and strtrim(sName)) or sName)
                local highest = FC.highestRankBySpellName[clean]
                if highest and highest > 0 then
                    assignedID = highest
                end
            end
            slotData = {
                type = "spell",
                id = assignedID,
                name = sName,
                icon = sIcon,
            }
        end

    elseif cType == "item" then
        local iID = id
        local iInfo = FC:ResolveItemInfo(iID)
        slotData = {
            type = "item",
            id = iID,
            name = (iInfo and iInfo.name) or ("Item " .. tostring(iID)),
            icon = (iInfo and iInfo.icon),
        }
    end

    if slotData and slotData.icon then
        return slotData
    end
    return nil
end

function FC:HandleSlotDrop(slotIndex)
    if not slotIndex or slotIndex < 1 or slotIndex > (MAX_COOLDOWN_SLOTS or 7) then return end
    local slotData = FC:GetCursorSlotData()
    if slotData then
        ClearCursor()
        local slots = FC.GetCooldownSlots and FC:GetCooldownSlots() or ForeverClassesDB.cooldownSlots
        if not slots then
            slots = {}
            ForeverClassesDB.cooldownSlots = slots
        end
        slots[slotIndex] = slotData
        local sound = (SOUNDKIT and SOUNDKIT.IG_ABILITY_ICON_DROP) or 856
        pcall(PlaySound, sound)
        print(string.format("|cff00ccff[ForeverClasses]|r Assigned |cff00ff00%s|r to Ability Slot %d.", slotData.name, slotIndex))
        if FC.UpdateCooldowns then FC:UpdateCooldowns() end
        if FC.UpdateCooldownIndicators then FC:UpdateCooldownIndicators() end
    end
end

function FC:ClearSlot(slotIndex)
    if not slotIndex or slotIndex < 1 or slotIndex > (MAX_COOLDOWN_SLOTS or 7) then return end
    local slots = FC.GetCooldownSlots and FC:GetCooldownSlots() or ForeverClassesDB.cooldownSlots
    if slots then
        local oldName = slots[slotIndex] and slots[slotIndex].name
        slots[slotIndex] = nil
        if oldName then
            print(string.format("|cff00ccff[ForeverClasses]|r Cleared |cffff4444%s|r from Ability Slot %d.", oldName, slotIndex))
        end
        if FC.UpdateCooldowns then FC:UpdateCooldowns() end
        if FC.UpdateCooldownIndicators then FC:UpdateCooldownIndicators() end
    end
end

function FC:GetCooldownSwapSlots(slotIndex)
    local charData = FC.GetCharData and FC:GetCharData()
    if charData and charData ~= FC.tempCharData then
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

    if not ForeverClassesDB.cooldownSwapSlots then
        ForeverClassesDB.cooldownSwapSlots = {}
    end
    if slotIndex then
        if not ForeverClassesDB.cooldownSwapSlots[slotIndex] then
            ForeverClassesDB.cooldownSwapSlots[slotIndex] = {}
        end
        return ForeverClassesDB.cooldownSwapSlots[slotIndex]
    end
    return ForeverClassesDB.cooldownSwapSlots
end

function FC:HandleSwapSlotDrop(mainSlotIndex, swapIndex)
    if not mainSlotIndex or mainSlotIndex < 1 or mainSlotIndex > (MAX_COOLDOWN_SLOTS or 7) then return end
    local slotData = FC:GetCursorSlotData()
    if not slotData then return end

    ClearCursor()
    local swapSlots = FC:GetCooldownSwapSlots(mainSlotIndex)
    if not swapSlots then
        swapSlots = {}
    end

    if not swapIndex or swapIndex > #swapSlots then
        swapIndex = #swapSlots + 1
    end

    swapSlots[swapIndex] = slotData
    local sound = (SOUNDKIT and SOUNDKIT.IG_ABILITY_ICON_DROP) or 856
    pcall(PlaySound, sound)
    print(string.format("|cff00ccff[ForeverClasses]|r Added |cff00ff00%s|r to Slot %d quick swap pool.", slotData.name, mainSlotIndex))

    if FC.RefreshFlyout then FC:RefreshFlyout(mainSlotIndex) end
    if FC.UpdateCooldownIndicators then FC:UpdateCooldownIndicators() end
end

function FC:SwapSlotAbility(mainSlotIndex, swapIndex)
    if not mainSlotIndex or not swapIndex then return end
    local slots = FC.GetCooldownSlots and FC:GetCooldownSlots() or ForeverClassesDB.cooldownSlots
    local swapSlots = FC:GetCooldownSwapSlots(mainSlotIndex)
    if not slots or not swapSlots then return end

    local currentMain = slots[mainSlotIndex]
    local targetSwap = swapSlots[swapIndex]
    if not targetSwap then return end

    -- Perform SWAP
    slots[mainSlotIndex] = targetSwap
    if currentMain then
        swapSlots[swapIndex] = currentMain
    else
        table.remove(swapSlots, swapIndex)
    end

    local sound = (SOUNDKIT and SOUNDKIT.IG_ABILITY_ICON_DROP) or 856
    pcall(PlaySound, sound)
    if currentMain then
        print(string.format("|cff00ccff[ForeverClasses]|r Swapped to |cff00ff00%s|r in Slot %d (stored |cff888888%s|r).", targetSwap.name, mainSlotIndex, currentMain.name))
    else
        print(string.format("|cff00ccff[ForeverClasses]|r Activated |cff00ff00%s|r in Slot %d.", targetSwap.name, mainSlotIndex))
    end

    if FC.UpdateCooldowns then FC:UpdateCooldowns() end
    if FC.UpdateCooldownIndicators then FC:UpdateCooldownIndicators() end
    if FC.HideFlyout then FC:HideFlyout() end
end

function FC:RemoveSwapSlotAbility(mainSlotIndex, swapIndex)
    local swapSlots = FC:GetCooldownSwapSlots(mainSlotIndex)
    if not swapSlots or not swapSlots[swapIndex] then return end
    local removedName = swapSlots[swapIndex].name
    table.remove(swapSlots, swapIndex)
    print(string.format("|cff00ccff[ForeverClasses]|r Removed |cffff4444%s|r from Slot %d swap pool.", removedName or "Ability", mainSlotIndex))
    if FC.RefreshFlyout then FC:RefreshFlyout(mainSlotIndex) end
    if FC.UpdateCooldownIndicators then FC:UpdateCooldownIndicators() end
end

function FC:CreateFlyoutBar()
    if FC.FlyoutBar then return FC.FlyoutBar end

    local flyout = CreateFrame("Frame", "ForeverClassesFlyoutBar", UIParent, BackdropTemplateString)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetFrameLevel(100)
    flyout:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    flyout:SetBackdropColor(0.06, 0.06, 0.08, 0.94)
    flyout:SetBackdropBorderColor(0.28, 0.28, 0.32, 0.9)
    flyout:EnableMouse(true)
    flyout:Hide()

    if tinsert and UISpecialFrames then
        pcall(tinsert, UISpecialFrames, "ForeverClassesFlyoutBar")
    end

    -- Top Tab (cap handle with down arrow 'v' to close)
    local topTab = CreateFrame("Button", nil, flyout, BackdropTemplateString)
    topTab:SetHeight(7)
    topTab:SetPoint("TOPLEFT", flyout, "TOPLEFT", 1, -1)
    topTab:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", -1, -1)
    topTab:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    topTab:SetBackdropColor(0.10, 0.10, 0.12, 0.95)
    topTab:SetBackdropBorderColor(0.28, 0.28, 0.32, 0.9)
    topTab:EnableMouse(true)
    topTab:RegisterForClicks("AnyUp")

    local downArrow = topTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    downArrow:SetPoint("CENTER", topTab, "CENTER", 0, 1)
    downArrow:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    downArrow:SetText("v")
    downArrow:SetTextColor(0.85, 0.85, 0.85, 0.9)
    topTab.arrow = downArrow

    topTab:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1.0)
        self.arrow:SetTextColor(1.0, 1.0, 1.0, 1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Click to close drawer", 1, 1, 1)
        GameTooltip:Show()
    end)
    topTab:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.28, 0.28, 0.32, 0.9)
        self.arrow:SetTextColor(0.85, 0.85, 0.85, 0.9)
        GameTooltip:Hide()
    end)
    topTab:SetScript("OnClick", function()
        FC:HideFlyout()
    end)
    flyout.topTab = topTab

    flyout.buttons = {}

    for i = 1, MAX_SWAP_SLOTS do
        local btn = CreateFrame("Button", "ForeverClassesFlyoutSlot" .. i, flyout, BackdropTemplateString)
        btn:EnableMouse(true)
        btn:RegisterForClicks("AnyUp")
        btn:RegisterForDrag("LeftButton")
        btn.subIndex = i

        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            tileSize = 0,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        btn:SetBackdropColor(0.12, 0.12, 0.14, 0.9)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

        local icon = btn:CreateTexture(nil, "BACKGROUND")
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon

        local hilight = btn:CreateTexture(nil, "HIGHLIGHT")
        hilight:SetAllPoints(btn)
        hilight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hilight:SetBlendMode("ADD")

        local plusText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        plusText:SetPoint("CENTER", btn, "CENTER", 0, 0)
        plusText:SetText("+")
        plusText:SetTextColor(0.4, 1.0, 0.4, 0.9)
        plusText:Hide()
        btn.plusText = plusText

        btn:SetScript("OnReceiveDrag", function(self)
            if FC.activeFlyoutSlot then
                FC:HandleSwapSlotDrop(FC.activeFlyoutSlot, self.subIndex)
            end
        end)

        btn:SetScript("OnClick", function(self, mouseButton)
            if not FC.activeFlyoutSlot then return end
            local cType = GetCursorInfo()
            if cType then
                FC:HandleSwapSlotDrop(FC.activeFlyoutSlot, self.subIndex)
            elseif mouseButton == "RightButton" and IsShiftKeyDown() then
                FC:RemoveSwapSlotAbility(FC.activeFlyoutSlot, self.subIndex)
            elseif mouseButton == "LeftButton" then
                if self.isAddButton then
                    print("|cff00ccff[ForeverClasses]|r Drag an ability from your Spellbook (P) or item to add to this slot.")
                else
                    FC:SwapSlotAbility(FC.activeFlyoutSlot, self.subIndex)
                end
            end
        end)

        btn:SetScript("OnEnter", function(self)
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.isAddButton then
                    GameTooltip:AddLine("Add Quick Swap Ability", 0.4, 1.0, 0.4)
                    GameTooltip:AddLine("Drag & drop any ability from your Spellbook (P) or item here.", 0.8, 0.8, 0.8, true)
                    GameTooltip:Show()
                elseif self.spellID then
                    if GameTooltip.SetSpellByID then
                        GameTooltip:SetSpellByID(self.spellID)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff00ff00<Left-Click to Swap with Active Slot>|r", 0, 1, 0)
                    GameTooltip:AddLine("|cffff4444<Shift-Right-Click to Remove from Pool>|r", 1, 0.3, 0.3)
                    GameTooltip:Show()
                elseif self.itemID then
                    if GameTooltip.SetItemByID then
                        GameTooltip:SetItemByID(self.itemID)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff00ff00<Left-Click to Swap with Active Slot>|r", 0, 1, 0)
                    GameTooltip:AddLine("|cffff4444<Shift-Right-Click to Remove from Pool>|r", 1, 0.3, 0.3)
                    GameTooltip:Show()
                elseif self.spellName then
                    GameTooltip:AddLine(self.spellName, 1, 1, 1)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff00ff00<Left-Click to Swap with Active Slot>|r", 0, 1, 0)
                    GameTooltip:AddLine("|cffff4444<Shift-Right-Click to Remove from Pool>|r", 1, 0.3, 0.3)
                    GameTooltip:Show()
                end
            end)
        end)

        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        flyout.buttons[i] = btn
    end

    -- Helper to safely check if mouse is over a frame
    local function SafeIsMouseOver(f)
        if not f then return false end
        local ok, res = pcall(function()
            return f:IsShown() and f:IsMouseOver()
        end)
        return ok and res
    end

    -- Smart check: is mouse over flyout, cooldown bar, or spell/item sources (SpellBook, Bags)?
    local function IsMouseOverFlyoutOrSource()
        -- 1. Flyout itself and its elements
        if FC.FlyoutBar and FC.FlyoutBar:IsShown() then
            if SafeIsMouseOver(FC.FlyoutBar) then return true end
            if SafeIsMouseOver(FC.FlyoutBar.topTab) then return true end
            if FC.FlyoutBar.buttons then
                for _, b in ipairs(FC.FlyoutBar.buttons) do
                    if SafeIsMouseOver(b) then return true end
                end
            end
        end

        -- 2. CooldownBar and its slots / tabs
        if FC.CooldownBar and FC.CooldownBar:IsShown() then
            if SafeIsMouseOver(FC.CooldownBar) then return true end
            if FC.CooldownBar.slots then
                for _, slot in ipairs(FC.CooldownBar.slots) do
                    if SafeIsMouseOver(slot) then return true end
                    if SafeIsMouseOver(slot.flyoutTab) then return true end
                end
            end
        end

        -- 3. SpellBook (Classic & Modern)
        if SafeIsMouseOver(SpellBookFrame) or SafeIsMouseOver(PlayerSpellsFrame) then
            return true
        end

        -- 4. Bags / Containers
        if SafeIsMouseOver(ContainerFrameCombinedBags) then
            return true
        end
        local numBags = NUM_CONTAINER_FRAMES or 13
        for b = 1, numBags do
            local bagFrame = _G["ContainerFrame" .. b]
            if SafeIsMouseOver(bagFrame) then
                return true
            end
        end

        -- 5. Macros & Character Equipment
        if SafeIsMouseOver(MacroFrame) or SafeIsMouseOver(CharacterFrame) then
            return true
        end

        return false
    end

    -- Hook GLOBAL_MOUSE_DOWN to dismiss when clicking anywhere outside
    flyout:SetScript("OnShow", function(self)
        pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)

    flyout:SetScript("OnHide", function(self)
        pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)

    flyout:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" and self:IsShown() then
            if GetCursorInfo and GetCursorInfo() ~= nil then return end
            if IsMouseOverFlyoutOrSource() then return end
            FC:HideFlyout()
        end
    end)

    -- Fallback/complementary hook on WorldFrame for 3D world clicks
    if WorldFrame and WorldFrame.HookScript and not FC._worldFrameFlyoutHooked then
        FC._worldFrameFlyoutHooked = true
        pcall(WorldFrame.HookScript, WorldFrame, "OnMouseDown", function()
            if FC.FlyoutBar and FC.FlyoutBar:IsShown() then
                if GetCursorInfo and GetCursorInfo() ~= nil then return end
                if IsMouseOverFlyoutOrSource() then return end
                FC:HideFlyout()
            end
        end)
    end

    FC.FlyoutBar = flyout
    return flyout
end

function FC:HideFlyout()
    if FC.FlyoutBar and FC.FlyoutBar:IsShown() then
        FC.FlyoutBar:Hide()
        FC.activeFlyoutSlot = nil
        if FC.UpdateCooldownIndicators then
            FC:UpdateCooldownIndicators()
        end
    end
end

function FC:ToggleFlyout(mainSlotIndex)
    if FC.activeFlyoutSlot == mainSlotIndex and FC.FlyoutBar and FC.FlyoutBar:IsShown() then
        FC:HideFlyout()
    else
        FC:ShowFlyout(mainSlotIndex)
    end
end

function FC:ShowFlyout(mainSlotIndex)
    if not mainSlotIndex or not FC.CooldownBar or not FC.CooldownBar.slots then return end
    local mainBtn = FC.CooldownBar.slots[mainSlotIndex]
    if not mainBtn or not mainBtn:IsShown() then return end

    local flyout = FC:CreateFlyoutBar()
    FC.activeFlyoutSlot = mainSlotIndex

    FC:RefreshFlyout(mainSlotIndex)
    flyout:Show()
    pcall(PlaySound, SOUNDKIT.U_CHAT_SCROLL_BUTTON or 856)
    if FC.UpdateCooldownIndicators then FC:UpdateCooldownIndicators() end
end

function FC:RefreshFlyout(mainSlotIndex)
    if not FC.FlyoutBar then return end
    mainSlotIndex = mainSlotIndex or FC.activeFlyoutSlot
    if not mainSlotIndex then return end

    local mainBtn = FC.CooldownBar and FC.CooldownBar.slots and FC.CooldownBar.slots[mainSlotIndex]
    if not mainBtn then return end

    local swapSlots = FC:GetCooldownSwapSlots(mainSlotIndex) or {}
    local storedCount = #swapSlots

    local hasAddButton = (storedCount < MAX_SWAP_SLOTS)
    local totalDisplay = storedCount + (hasAddButton and 1 or 0)
    if totalDisplay == 0 then totalDisplay = 1 end

    local topTabH = 7
    local pad = 1
    local gap = 2
    local mainW = mainBtn:GetWidth()
    local btnSize = mainW - (pad * 2)
    local flyoutWidth = mainW
    local flyoutHeight = topTabH + (totalDisplay * btnSize) + ((totalDisplay - 1) * gap) + (pad * 2) + 2

    FC.FlyoutBar:SetSize(flyoutWidth, flyoutHeight)
    FC.FlyoutBar:ClearAllPoints()
    FC.FlyoutBar:SetPoint("BOTTOM", mainBtn, "TOP", 0, 0)

    if FC.FlyoutBar.topTab then
        FC.FlyoutBar.topTab:ClearAllPoints()
        FC.FlyoutBar.topTab:SetPoint("TOPLEFT", FC.FlyoutBar, "TOPLEFT", 1, -1)
        FC.FlyoutBar.topTab:SetPoint("TOPRIGHT", FC.FlyoutBar, "TOPRIGHT", -1, -1)
        FC.FlyoutBar.topTab:SetHeight(topTabH)
    end

    for i = 1, MAX_SWAP_SLOTS do
        local btn = FC.FlyoutBar.buttons[i]
        if i <= totalDisplay then
            btn:SetSize(btnSize, btnSize)
            btn:ClearAllPoints()

            local offsetBottom = pad + ((i - 1) * (btnSize + gap))
            btn:SetPoint("BOTTOM", FC.FlyoutBar, "BOTTOM", 0, offsetBottom)

            if i <= storedCount then
                local data = swapSlots[i]
                btn.isAddButton = false
                btn.subIndex = i
                btn.spellID = (data.type == "spell") and data.id or nil
                btn.spellName = data.name
                btn.itemID = (data.type == "item") and data.id or nil

                btn.icon:SetTexture(data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                btn.icon:Show()
                btn.plusText:Hide()
                btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
            else
                btn.isAddButton = true
                btn.subIndex = i
                btn.spellID = nil
                btn.spellName = nil
                btn.itemID = nil

                btn.icon:Hide()
                btn.plusText:Show()
                btn:SetBackdropBorderColor(0.2, 0.6, 0.2, 0.8)
            end
            btn:Show()
        else
            btn:Hide()
        end
    end
end

function FC:UpdateCooldownIndicators()
    if not FC.CooldownBar or not FC.CooldownBar.slots then return end
    local isFlyoutOpen = FC.FlyoutBar and FC.FlyoutBar:IsShown()
    for i = 1, (MAX_COOLDOWN_SLOTS or 7) do
        local btn = FC.CooldownBar.slots[i]
        if btn and btn.flyoutTab then
            local hasSpell = (btn.spellID ~= nil or btn.spellName ~= nil or btn.itemID ~= nil)
            local swapSlots = FC.GetCooldownSwapSlots and FC:GetCooldownSwapSlots(i)
            local hasSwaps = (swapSlots and #swapSlots > 0)

            if isFlyoutOpen and FC.activeFlyoutSlot == i then
                btn.flyoutTab:Hide()
            elseif hasSpell or hasSwaps then
                btn.flyoutTab:Show()
            else
                btn.flyoutTab:Hide()
            end
        end
    end
end

function FC:PlayCooldownReadyPulse(btn)
    if not btn or not btn:IsShown() then return end
    if ForeverClassesDB and ForeverClassesDB.cooldownPulse == false then return end
    if not btn.flashFrame then return end

    FC:Log("PULSE", "slot=%s spell=%s pulse animation triggered", tostring(btn.slotIndex or "?"), tostring(btn.spellName or "?"))

    btn.flashStartTime = GetTime()
    btn.flashDuration = 0.38
    btn.flashFrame:SetAlpha(1.0)
    btn.flashFrame:Show()

    local baseW, baseH = btn:GetSize()
    if not baseW or baseW <= 0 then baseW = 40 end
    if not baseH or baseH <= 0 then baseH = 40 end

    if btn.flashTex then
        btn.flashTex:SetSize(baseW * 1.1, baseH * 1.1)
    end
    if btn.flashGlow then
        btn.flashGlow:SetColorTexture(1, 1, 1, 0.7)
    end

    btn.flashFrame:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime()
        local elapsedSince = now - (btn.flashStartTime or now)
        local progress = elapsedSince / (btn.flashDuration or 0.38)
        if progress >= 1.0 then
            self:Hide()
            self:SetScript("OnUpdate", nil)
        else
            -- 1. Smooth fade out
            local alpha = (1.0 - progress)
            self:SetAlpha(alpha)

            -- 2. Scale starburst from 1.1x to 1.7x
            if btn.flashTex then
                local scale = 1.1 + (progress * 0.6)
                btn.flashTex:SetSize(baseW * scale, baseH * scale)
            end

            -- 3. Fade glow overlay faster
            if btn.flashGlow then
                local glowAlpha = math.max(0, (1.0 - (progress * 1.6))) * 0.7
                btn.flashGlow:SetColorTexture(1, 1, 1, glowAlpha)
            end
        end
    end)
end

function FC:UpdateCooldowns()
    pcall(function()
        if not FC.CooldownBar or not FC.CooldownBar.slots then return end

        local slotCount = (FC.GetCooldownSlotCount and FC:GetCooldownSlotCount()) or (ForeverClassesDB and ForeverClassesDB.cooldownSlotCount)
        if slotCount == nil then
            slotCount = (ForeverClassesDB and ForeverClassesDB.showCooldowns == false) and 0 or 7
            if ForeverClassesDB then ForeverClassesDB.cooldownSlotCount = slotCount end
        end

        local isDead = false
        pcall(function() isDead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") end)

        if slotCount == 0 or (ForeverClassesDB and ForeverClassesDB.showCooldowns == false) or isDead or (ForeverClassesDB and ForeverClassesDB.attachCooldownManager) then
            if FC.HideFlyout then FC:HideFlyout() end
            FC.CooldownBar:Hide()
            return
        end

        FC.CooldownBar:Show()

        local now = GetTime()
        local isUnlocked = (ForeverClassesDB.movementMode ~= "LOCKED")

        -- Simulated Test Mode (/fc testcd)
        if FC.testCooldownsActive then
            local testList = {
                { name = "Kick", icon = 132219, cd = 4.2, maxCD = 10, buff = nil },
                { name = "Gouge", icon = 132155, cd = 0, maxCD = 10, buff = nil },
                { name = "Sprint", icon = 132307, cd = 8.5, maxCD = 15, buff = 8.5 },
                { name = "Evasion", icon = 136177, cd = 45, maxCD = 300, buff = nil },
                { name = "Vanish", icon = 132331, cd = 120, maxCD = 300, buff = nil },
                { name = "Blind", icon = 136175, cd = 75, maxCD = 120, buff = nil },
                { name = "Cold Blood", icon = 135988, cd = 0, maxCD = 180, buff = nil },
            }

            for i = 1, MAX_COOLDOWN_SLOTS do
                local btn = FC.CooldownBar.slots[i]
                local d = testList[i]
                if i <= slotCount and d and btn then
                    btn.icon:SetTexture(d.icon)
                    btn.icon:Show()
                    btn.emptyText:Hide()
                    btn.spellName = d.name
                    btn.spellID = nil
                    btn.itemID = nil

                    if d.buff then
                        -- Active Buff State: Golden border & gold duration
                        btn.border:SetBackdropBorderColor(1.00, 0.82, 0.00, 1.0)
                        btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                        btn.cooldownText:SetText(FormatCooldownTime(d.buff))
                        btn.cooldownText:SetTextColor(1.0, 0.88, 0.2, 1.0)
                        btn.cooldownText:Show()
                        btn.cooldown:SetCooldown(now, d.buff)
                        btn.cooldown:Show()
                    elseif d.cd > 0 then
                        -- On Cooldown State: Dimmed icon & white countdown
                        btn.border:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
                        btn.icon:SetVertexColor(0.40, 0.40, 0.40)
                        btn.cooldownText:SetText(FormatCooldownTime(d.cd))
                        btn.cooldownText:SetTextColor(1.0, 1.0, 1.0, 1.0)
                        btn.cooldownText:Show()
                        btn.cooldown:SetCooldown(now - (d.maxCD - d.cd), d.maxCD)
                        btn.cooldown:Show()
                    else
                        -- Ready State: Full brightness, no numbers
                        btn.border:SetBackdropBorderColor(0.20, 0.20, 0.20, 0.8)
                        btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                        btn.cooldownText:Hide()
                        btn.cooldown:Hide()
                    end

                    btn:Show()
                else
                    if btn then btn:Hide() end
                end
            end
            return
        end

        -- Real Player Cooldowns
        local gcdStart, gcdDur, gcdRemaining = FC:GetGCDData()
        local isGCDActive = (gcdRemaining and gcdRemaining > 0.02)
        local hasActiveAny = isGCDActive
        local hasTarget = UnitExists and UnitExists("target") and not (UnitIsDead and UnitIsDead("target"))

        local slots = FC.GetCooldownSlots and FC:GetCooldownSlots() or ForeverClassesDB.cooldownSlots
        for i = 1, MAX_COOLDOWN_SLOTS do
            local btn = FC.CooldownBar.slots[i]
            if i > slotCount then
                if btn then btn:Hide() end
            else
                local slotData = slots and slots[i]

            -- In-flight icon resolution if missing (non-blocking, no spellbook iteration in combat)
            if slotData and not slotData.icon then
                if slotData.type == "spell" then
                    local sInfo = FC:ResolveSpellInfo(slotData.name or slotData.id)
                    if sInfo and sInfo.icon then
                        slotData.icon = sInfo.icon
                        slotData.id = sInfo.id or slotData.id
                    end
                elseif slotData.type == "item" then
                    local iInfo = FC:ResolveItemInfo(slotData.id)
                    if iInfo and iInfo.icon then
                        slotData.name = iInfo.name or slotData.name
                        slotData.icon = iInfo.icon
                    end
                end
            end

            if slotData and (slotData.id or slotData.name) and slotData.icon and slotData.icon ~= "Interface\\Icons\\INV_Misc_QuestionMark" then
                local displayIcon = slotData.icon
                if slotData.name and (not slotData.cleanName or slotData._cachedForName ~= slotData.name) then
                    slotData.cleanName = string.lower((strtrim and strtrim(slotData.name)) or string.match(slotData.name, "^%s*(.-)%s*$") or slotData.name)
                    slotData.baseName = (CleanTotemName and CleanTotemName(slotData.name)) or slotData.cleanName
                    slotData._cachedForName = slotData.name
                end
                local cleanSlot = slotData.cleanName or (slotData.name and string.lower(slotData.name))
                local isStealthSlot = (cleanSlot == "stealth") or (slotData.id and (slotData.id == 1784 or slotData.id == 1785 or slotData.id == 1786 or slotData.id == 1787))
                local isProwlSlot = (cleanSlot == "prowl") or (slotData.id and (slotData.id == 5215 or slotData.id == 6783 or slotData.id == 9913))

                if (isStealthSlot or isProwlSlot) and FC.isStealthed then
                    local activeIcon = nil
                    if GetShapeshiftFormInfo and GetNumShapeshiftForms and GetNumShapeshiftForms() > 0 then
                        local formIcon = GetShapeshiftFormInfo(1)
                        if formIcon and formIcon ~= slotData.icon then
                            activeIcon = formIcon
                        end
                    end
                    if not activeIcon and isStealthSlot then
                        activeIcon = 135994 -- "Interface\\Icons\\Spell_Magic_LesserInvisibilty" (Active Stealth stance icon)
                    end
                    if activeIcon then
                        displayIcon = activeIcon
                    end
                end

                if btn.lastDisplayedIcon ~= displayIcon then
                    btn.lastDisplayedIcon = displayIcon
                    btn.icon:SetTexture(displayIcon)
                end
                btn.icon:Show()
                btn.emptyText:Hide()
                btn.spellID = (slotData.type == "spell") and slotData.id or nil
                btn.spellName = slotData.name
                btn.itemID = (slotData.type == "item") and slotData.id or nil

                -- 1. Check Active Buff (e.g. Bloodlust, Lightning Shield, Sprint, Evasion, Paladin Seals)
                local buffRemaining, buffDuration, buffStart, buffStacks, buffInstanceID = FC:GetPlayerBuffDuration(slotData.name, cleanSlot)
                local isActiveBuff = (buffRemaining ~= nil and buffRemaining > 0)

                -- 2. Query Cooldown
                local cdStart, cdDuration, cdEnable, cdModRate = FC:GetCooldownData(slotData)
                local isOnCooldown = false
                local remCD = 0

                local numCD = tonumber(cdDuration) or 0
                local numStart = tonumber(cdStart) or 0
                if numCD > 1.5 and numStart > 0 then
                    remCD = (numStart + numCD) - now
                    if remCD > 0.05 then
                        isOnCooldown = true
                    end
                end

                -- Cooldown Ready Flash detection
                if isOnCooldown then
                    btn.wasOnCooldown = true
                    btn.lastCooldownDuration = numCD
                elseif btn.wasOnCooldown then
                    btn.wasOnCooldown = false
                    local lastDur = tonumber(btn.lastCooldownDuration) or 0
                    if lastDur > 1.5 and not isActiveBuff and (not ForeverClassesDB or ForeverClassesDB.cooldownPulse ~= false) then
                        FC:Log("PULSE_READY", "slot=%d spell=%s cdDur=%.1f gcdActive=%s", i, tostring(slotData.name), lastDur, tostring(isGCDActive))
                        FC:PlayCooldownReadyPulse(btn)
                    end
                    btn.lastCooldownDuration = nil
                end

                -- 3. Check Active Totem in the world
                local totemData = nil
                if cleanSlot and cleanSlot:find("totem", 1, true) then
                    totemData = FC:GetTotemData(slotData.name, slotData.baseName or cleanSlot)
                end

                if isActiveBuff or isOnCooldown or (totemData and totemData.remaining > 0) then
                    hasActiveAny = true
                end

                -- Visual States
                if isActiveBuff then
                    btn.isSecretOnCD = false
                    if btn.visualState ~= "buff" then
                        btn.visualState = "buff"
                        btn.border:SetBackdropBorderColor(1.00, 0.82, 0.00, 1.0)
                        btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                    end
                    if buffRemaining < 900 then
                        local txt = FormatCooldownTime(buffRemaining)
                        if btn.lastCdText ~= txt then
                            btn.lastCdText = txt
                            btn.cooldownText:SetText(txt)
                        end
                        btn.cooldownText:SetTextColor(1.0, 0.88, 0.2, 1.0)
                        btn.cooldownText:Show()
                    else
                        btn.lastCdText = nil
                        btn.cooldownText:Hide()
                    end
                    pcall(btn.cooldown.SetHideCountdownNumbers, btn.cooldown, true)

                    local isIndefiniteBuff = (not buffDuration or buffDuration <= 0 or (buffRemaining and buffRemaining >= 900))
                    local bStart = not isIndefiniteBuff and (buffStart or (buffDuration and buffDuration > 0 and (now - (buffDuration - buffRemaining)))) or nil
                    local bDur = not isIndefiniteBuff and buffDuration or nil
                    if bStart and bDur and bStart > 0 and bDur > 0 then
                        if btn.lastCdStart ~= bStart or btn.lastCdDur ~= bDur or btn.needsCooldownRefresh or FC.needsCooldownRefresh then
                            btn.lastCdStart = bStart
                            btn.lastCdDur = bDur
                            btn.needsCooldownRefresh = false
                            pcall(btn.cooldown.SetCooldown, btn.cooldown, bStart, bDur)
                        end
                        btn.cooldown:Show()
                    else
                        btn.lastCdStart = nil
                        btn.lastCdDur = nil
                        btn.cooldown:Hide()
                    end

                elseif isOnCooldown then
                    -- On Cooldown State: Dimmed icon & clean white countdown timer & sweep
                    btn.isSecretOnCD = false
                    if btn.visualState ~= "cooldown" then
                        btn.visualState = "cooldown"
                        btn.border:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
                        btn.icon:SetVertexColor(0.40, 0.40, 0.40) -- Dim icon while on cooldown
                    end
                    pcall(btn.cooldown.SetHideCountdownNumbers, btn.cooldown, true)

                    local txt = FormatCooldownTime(remCD)
                    if btn.lastCdText ~= txt then
                        btn.lastCdText = txt
                        btn.cooldownText:SetText(txt)
                    end
                    btn.cooldownText:SetTextColor(1.0, 1.0, 1.0, 1.0)
                    btn.cooldownText:Show()

                    if btn.lastCdStart ~= numStart or btn.lastCdDur ~= numCD or btn.needsCooldownRefresh or FC.needsCooldownRefresh then
                        btn.lastCdStart = numStart
                        btn.lastCdDur = numCD
                        btn.needsCooldownRefresh = false
                        pcall(btn.cooldown.SetCooldown, btn.cooldown, numStart, numCD, cdModRate or 1)
                    end
                    btn.cooldown:Show()

                elseif totemData and totemData.remaining > 0 then
                    -- Active Totem State: Amber / Warm Gold border, full brightness icon, remaining duration text & sweep
                    btn.isSecretOnCD = false
                    if btn.visualState ~= "totem" then
                        btn.visualState = "totem"
                        btn.border:SetBackdropBorderColor(1.00, 0.75, 0.15, 1.0)
                        btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                    end
                    pcall(btn.cooldown.SetHideCountdownNumbers, btn.cooldown, true)

                    local txt = FormatCooldownTime(totemData.remaining)
                    if btn.lastCdText ~= txt then
                        btn.lastCdText = txt
                        btn.cooldownText:SetText(txt)
                    end
                    btn.cooldownText:SetTextColor(1.00, 0.85, 0.20, 1.0) -- Gold countdown text
                    btn.cooldownText:Show()

                    local tStart = tonumber(totemData.start) or 0
                    local tDur = tonumber(totemData.duration) or 0
                    if tStart > 0 and tDur > 0 then
                        if btn.lastCdStart ~= tStart or btn.lastCdDur ~= tDur or btn.needsCooldownRefresh or FC.needsCooldownRefresh then
                            btn.lastCdStart = tStart
                            btn.lastCdDur = tDur
                            btn.needsCooldownRefresh = false
                            pcall(btn.cooldown.SetCooldown, btn.cooldown, tStart, tDur)
                        end
                        btn.cooldown:Show()
                    else
                        btn.cooldown:Hide()
                    end

                else
                    -- Off-Cooldown State: Check Range, Power & Usability
                    btn.isSecretOnCD = false
                    btn.lastCdText = nil
                    btn.cooldownText:Hide()

                    local cleanSlotName = slotData.name and string.lower((strtrim and strtrim(slotData.name)) or slotData.name)
                    local isOffGCD = cleanSlotName and OFF_GCD_SPELLS and OFF_GCD_SPELLS[cleanSlotName]
                    local slotGCD = (isGCDActive and not isOffGCD and gcdStart and gcdDur)

                    if slotGCD then
                        -- Global Cooldown (GCD) active: Radial sweep without numbers
                        pcall(btn.cooldown.SetHideCountdownNumbers, btn.cooldown, true)
                        if btn.lastCdStart ~= gcdStart or btn.lastCdDur ~= gcdDur then
                            btn.lastCdStart = gcdStart
                            btn.lastCdDur = gcdDur
                            pcall(btn.cooldown.SetCooldown, btn.cooldown, gcdStart, gcdDur)
                        end
                        btn.cooldown:Show()
                    else
                        btn.lastCdStart = nil
                        btn.lastCdDur = nil
                        btn.cooldown:Hide()
                    end

                    -- Range and Power evaluation throttled to 0.20s or on events
                    if (now - (btn.lastCheckTime or 0) >= 0.20) or FC.needsCooldownRefresh or btn.needsCooldownRefresh then
                        btn.lastCheckTime = now
                        btn.cachedOutOfRange = hasTarget and FC:IsSlotOutOfRange(slotData) or false
                        btn.cachedOutOfPower, btn.cachedUnusable = FC:IsSlotOutOfPower(slotData)
                    end

                    local isOutOfRange = btn.cachedOutOfRange
                    local isOutOfPower = btn.cachedOutOfPower
                    local isUnusable = btn.cachedUnusable

                    if isOutOfRange then
                        if btn.visualState ~= "oor" then
                            btn.visualState = "oor"
                            btn.border:SetBackdropBorderColor(0.20, 0.20, 0.20, 0.8)
                            btn.icon:SetVertexColor(0.85, 0.20, 0.20)
                        end
                    elseif isOutOfPower then
                        if btn.visualState ~= "oop" then
                            btn.visualState = "oop"
                            btn.border:SetBackdropBorderColor(0.20, 0.20, 0.20, 0.8)
                            btn.icon:SetVertexColor(0.40, 0.40, 0.55)
                        end
                    elseif isUnusable then
                        if btn.visualState ~= "unusable" then
                            btn.visualState = "unusable"
                            btn.border:SetBackdropBorderColor(0.20, 0.20, 0.20, 0.8)
                            btn.icon:SetVertexColor(0.40, 0.40, 0.40)
                        end
                    else
                        if btn.visualState ~= "ready" then
                            btn.visualState = "ready"
                            btn.border:SetBackdropBorderColor(0.20, 0.20, 0.20, 0.8)
                            btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                        end
                    end
                end

                -- Debug logging for Seal or Cooldown slots
                if (cleanSlot and (cleanSlot:find("^seal of ") or cleanSlot == "judgement")) or isOnCooldown or isActiveBuff then
                    local inC = (InCombatLockdown and InCombatLockdown()) and true or false
                    if btn.lastLoggedState ~= btn.visualState or (now - (btn.lastLoggedTime or 0) >= 3.0) then
                        btn.lastLoggedState = btn.visualState
                        btn.lastLoggedTime = now
                        FC:Log("SLOT", "slot=%d name=%s state=%s remCD=%.1f remBuff=%.1f inCombat=%s",
                            i, tostring(slotData.name), tostring(btn.visualState),
                            tonumber(remCD) or 0, tonumber(buffRemaining) or 0, tostring(inC))
                    end
                end

                -- Charges / Stacks (Only check when slot is not on cooldown or active buff or when refresh requested)
                if isActiveBuff or not isOnCooldown or FC.needsCooldownRefresh then
                    local displayedStack = false

                    -- 1. Midnight 12.0 Secret-Safe Native Stack Display via C_UnitAuras.GetAuraApplicationDisplayCount
                    local instID = buffInstanceID or (FC.buffToAuraInstance and FC.buffToAuraInstance[cleanSlot])
                    if isActiveBuff and instID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
                        local okDisp, dispCount = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, instID)
                        if okDisp and dispCount ~= nil then
                            local isZeroOrEmpty = false
                            if not IsSecret(dispCount) then
                                if dispCount == "" or dispCount == 0 or dispCount == "0" then
                                    isZeroOrEmpty = true
                                end
                            end
                            if not isZeroOrEmpty then
                                btn.countText:SetText(dispCount)
                                btn.countText:Show()
                                displayedStack = true
                            end
                        end
                    end

                    -- 2. Fallback to cached stacks if native display count was not used
                    if not displayedStack and isActiveBuff and buffStacks and (not IsSecret(buffStacks)) and (buffStacks > 1 or (buffStacks == 1 and DEFAULT_BUFF_STACKS and DEFAULT_BUFF_STACKS[cleanSlot])) then
                        btn.countText:SetText(tostring(buffStacks))
                        btn.countText:Show()
                        displayedStack = true
                    end

                    -- 3. Spell Charges (e.g. Conflagrate, Charge) if no buff stacks displayed
                    if not displayedStack then
                        local charges = FC:GetCharges(slotData)
                        if charges and not IsSecret(charges) and charges > 1 then
                            btn.countText:SetText(tostring(charges))
                            btn.countText:Show()
                        else
                            btn.countText:SetText("")
                            btn.countText:Hide()
                        end
                    end
                end

                btn:Show()

            else
                btn.spellID = nil
                btn.spellName = nil
                btn.itemID = nil
                btn.visualState = nil
                btn.lastCdText = nil
                btn.lastDisplayedIcon = nil
                btn.cooldownText:Hide()
                btn.countText:Hide()
                btn.cooldown:Hide()
                btn.icon:Hide()
                btn.wasOnCooldown = nil
                btn.lastCooldownDuration = nil

                local inCombat = FC.inCombat or (InCombatLockdown and InCombatLockdown())
                if isUnlocked or not inCombat then
                    btn.emptyText:SetText(tostring(i))
                    btn.emptyText:Show()
                    btn.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
                    btn:Show()
                else
                    btn.emptyText:Hide()
                    btn:Hide()
                end
            end
            end
        end
        FC.hasActiveCooldowns = hasActiveAny
        FC.needsCooldownRefresh = false
    end)
end

local function GetSlotDimensions(count)
    local availW = (ForeverClassesDB and ForeverClassesDB.barWidth) or 240
    local gap = 2

    -- For 4, 5, 6, 7 slots: span 100% of the health bar width with modern 2px gap
    if count >= 4 then
        local totalGap = (count - 1) * gap
        local size = (availW - totalGap) / count
        if size > 64 then size = 64 end
        return size, gap
    elseif count == 3 then
        local size = math.min(54, (availW - (2 * gap)) / 3)
        return size, gap
    elseif count == 2 then
        local size = math.min(52, (availW - gap) / 2)
        return size, gap
    else -- count == 1
        return 48, 0
    end
end

function FC:UpdateCooldownBarLayout()
    if not FC.CooldownBar or not FC.CooldownBar.slots then return end

    local count = (FC.GetCooldownSlotCount and FC:GetCooldownSlotCount()) or (ForeverClassesDB and ForeverClassesDB.cooldownSlotCount)
    if count == nil then
        count = (ForeverClassesDB and ForeverClassesDB.showCooldowns == false) and 0 or 7
        if ForeverClassesDB then ForeverClassesDB.cooldownSlotCount = count end
    end

    if count == 0 or (ForeverClassesDB and ForeverClassesDB.showCooldowns == false) then
        if FC.HideFlyout then FC:HideFlyout() end
        FC.CooldownBar:Hide()
        return
    end

    FC.CooldownBar:Show()
    count = math.max(1, math.min(MAX_COOLDOWN_SLOTS or 7, count))
    local size, gap = GetSlotDimensions(count)
    local totalW = (count * size) + ((count - 1) * gap)

    FC.CooldownBar:SetSize(totalW, size)
    FC.CooldownBar:ClearAllPoints()
    if FC.AbilityAnchor and FC.Frame then
        FC.AbilityAnchor:ClearAllPoints()
        FC.AbilityAnchor:SetPoint("BOTTOM", FC.Frame, "TOP", 0, 1)
        FC.AbilityAnchor:SetSize((ForeverClassesDB and ForeverClassesDB.barWidth) or 240, math.max(38, size + 8))
        FC.CooldownBar:SetPoint("BOTTOM", FC.AbilityAnchor, "BOTTOM", 0, 0)
    elseif FC.AbilityAnchor then
        FC.CooldownBar:SetPoint("BOTTOM", FC.AbilityAnchor, "BOTTOM", 0, 0)
        FC.AbilityAnchor:SetHeight(math.max(38, size + 8))
    else
        FC.CooldownBar:SetPoint("CENTER", FC.CooldownBar:GetParent(), "CENTER", 0, 0)
    end

    local fontSize = math.max(12, math.min(18, math.floor(size * 0.38)))
    local countFontSize = math.max(10, fontSize - 3)
    for i = 1, (MAX_COOLDOWN_SLOTS or 7) do
        local btn = FC.CooldownBar.slots[i]
        if btn then
            if i <= count then
                btn:SetSize(size, size)
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", FC.CooldownBar, "LEFT", (i - 1) * (size + gap), 0)
                if btn.cooldownText then
                    btn.cooldownText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
                end
                if btn.emptyText then
                    btn.emptyText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
                end
                if btn.countText then
                    btn.countText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", countFontSize, "OUTLINE")
                end
                if btn.flashTex then
                    btn.flashTex:SetSize(size * 1.5, size * 1.5)
                end
            else
                btn:Hide()
            end
        end
    end

    if FC.UpdateCooldownIndicators then pcall(FC.UpdateCooldownIndicators, FC) end
    if FC.RefreshFlyout and FC.activeFlyoutSlot then pcall(FC.RefreshFlyout, FC, FC.activeFlyoutSlot) end

    FC.needsCooldownRefresh = true
    if FC.UpdateCooldowns then pcall(FC.UpdateCooldowns, FC) end
end

function FC:CreateCooldownBar(parent)
    local bar = CreateFrame("Frame", "ForeverClassesCooldownBar", parent)
    local iconSize = 40
    local iconGap = 2
    local numSlots = MAX_COOLDOWN_SLOTS
    local totalWidth = (numSlots * iconSize) + ((numSlots - 1) * iconGap)
    local barHeight = iconSize

    bar:SetSize(totalWidth, barHeight)
    bar:SetPoint("CENTER", parent, "CENTER", 0, 0)
    bar:SetFrameLevel(parent:GetFrameLevel() + 5)

    local slots = {}
    for i = 1, numSlots do
        local btn = CreateFrame("Button", "ForeverClassesCooldownSlot" .. i, bar)
        btn:SetSize(iconSize, iconSize)
        btn:SetPoint("LEFT", bar, "LEFT", (i - 1) * (iconSize + iconGap), 0)
        btn:EnableMouse(true)
        btn:RegisterForClicks("AnyUp")
        btn:RegisterForDrag("LeftButton")
        btn.slotIndex = i

        local icon = btn:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints(btn)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon

        local border = CreateFrame("Frame", nil, btn, BackdropTemplateString)
        border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        border:SetBackdropBorderColor(0.18, 0.18, 0.20, 0.85)
        border:SetFrameLevel(btn:GetFrameLevel() + 2)
        btn.border = border

        local cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cooldown:SetAllPoints(btn)
        cooldown:SetReverse(false)
        cooldown:SetDrawEdge(true)
        pcall(cooldown.SetHideCountdownNumbers, cooldown, true)
        cooldown:SetFrameLevel(btn:GetFrameLevel() + 4)
        btn.cooldown = cooldown

        local textOverlay = CreateFrame("Frame", nil, btn)
        textOverlay:SetAllPoints(btn)
        textOverlay:SetFrameLevel(btn:GetFrameLevel() + 10)
        textOverlay:EnableMouse(false)
        btn.textOverlay = textOverlay

        local cooldownText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cooldownText:SetPoint("CENTER", textOverlay, "CENTER", 0, 0)
        cooldownText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        cooldownText:SetTextColor(1, 1, 1, 1)
        btn.cooldownText = cooldownText

        local countText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        countText:SetPoint("BOTTOMRIGHT", textOverlay, "BOTTOMRIGHT", -1, 1)
        countText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        countText:SetTextColor(1, 1, 1, 1)
        btn.countText = countText

        local emptyText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        emptyText:SetPoint("CENTER", textOverlay, "CENTER", 0, 0)
        emptyText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        emptyText:SetTextColor(0.5, 0.5, 0.5, 0.7)
        btn.emptyText = emptyText

        -- Cooldown Ready Flash overlay & expanding starburst
        local flashFrame = CreateFrame("Frame", nil, btn)
        flashFrame:SetAllPoints(btn)
        flashFrame:SetFrameLevel(btn:GetFrameLevel() + 15)
        flashFrame:EnableMouse(false)
        flashFrame:Hide()
        btn.flashFrame = flashFrame

        local flashGlow = flashFrame:CreateTexture(nil, "BACKGROUND")
        flashGlow:SetAllPoints(flashFrame)
        flashGlow:SetColorTexture(1, 1, 1, 0.7)
        flashGlow:SetBlendMode("ADD")
        btn.flashGlow = flashGlow

        local flashTex = flashFrame:CreateTexture(nil, "OVERLAY")
        flashTex:SetPoint("CENTER", flashFrame, "CENTER", 0, 0)
        flashTex:SetSize(40 * 1.5, 40 * 1.5)
        flashTex:SetTexture("Interface\\Cooldown\\star4")
        flashTex:SetBlendMode("ADD")
        flashTex:SetVertexColor(1, 1, 1, 0.95)
        btn.flashTex = flashTex

        local flyoutTab = CreateFrame("Button", "ForeverClassesCooldownTab" .. i, btn, BackdropTemplateString)
        flyoutTab:SetHeight(7)
        flyoutTab:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 0)
        flyoutTab:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", 0, 0)
        flyoutTab:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            tileSize = 0,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        flyoutTab:SetBackdropColor(0.10, 0.10, 0.12, 0.90)
        flyoutTab:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.85)
        flyoutTab:SetFrameLevel(btn:GetFrameLevel() + 5)
        flyoutTab:EnableMouse(true)
        flyoutTab:RegisterForClicks("AnyUp")

        local tabArrow = flyoutTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tabArrow:SetPoint("CENTER", flyoutTab, "CENTER", 0, -1)
        tabArrow:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        tabArrow:SetText("^")
        tabArrow:SetTextColor(0.75, 0.75, 0.75, 0.9)
        flyoutTab.arrow = tabArrow

        flyoutTab:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0.45, 0.45, 0.45, 1.0)
            self.arrow:SetTextColor(1.0, 1.0, 1.0, 1.0)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local swapSlots = FC.GetCooldownSwapSlots and FC:GetCooldownSwapSlots(i)
            local count = swapSlots and #swapSlots or 0
            if count > 0 then
                GameTooltip:AddLine(string.format("Quick Swap (%d stored)", count), 1, 1, 1)
                GameTooltip:AddLine("Click to open ability drawer.", 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("Quick Swap", 1, 1, 1)
                GameTooltip:AddLine("Click to open ability drawer and add abilities.", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)

        flyoutTab:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.85)
            self.arrow:SetTextColor(0.75, 0.75, 0.75, 0.9)
            GameTooltip:Hide()
        end)

        flyoutTab:SetScript("OnClick", function()
            FC:ToggleFlyout(i)
        end)

        flyoutTab:SetScript("OnReceiveDrag", function()
            FC:HandleSlotDrop(i)
        end)

        flyoutTab:Hide()
        btn.flyoutTab = flyoutTab

        -- Drag and drop handlers
        btn:SetScript("OnReceiveDrag", function(self)
            FC:HandleSlotDrop(self.slotIndex)
        end)

        btn:SetScript("OnClick", function(self, mouseButton)
            local cType = GetCursorInfo()
            if cType then
                FC:HandleSlotDrop(self.slotIndex)
            elseif mouseButton == "RightButton" and (IsShiftKeyDown() or ForeverClassesDB.movementMode ~= "LOCKED") then
                FC:ClearSlot(self.slotIndex)
            elseif mouseButton == "LeftButton" then
                FC:ToggleFlyout(self.slotIndex)
            end
        end)

        -- Tooltip handling
        btn:SetScript("OnEnter", function(self)
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                local swapSlots = FC.GetCooldownSwapSlots and FC:GetCooldownSwapSlots(self.slotIndex)
                local swapCount = swapSlots and #swapSlots or 0

                if self.spellID then
                    if GameTooltip.SetSpellByID then
                        GameTooltip:SetSpellByID(self.spellID)
                    end
                    GameTooltip:AddLine(" ")
                    if swapCount > 0 then
                        GameTooltip:AddLine(string.format("|cff00ffff[Quick Swap: %d abilities stored]|r", swapCount), 0.2, 0.9, 1.0)
                        GameTooltip:AddLine("|cff00ff00<Left-Click to Quick Swap>|r", 0, 1, 0)
                    else
                        GameTooltip:AddLine("|cff00ff00<Left-Click to open Quick Swap flyout>|r", 0, 1, 0)
                    end
                    GameTooltip:AddLine("|cff888888(Shift-Right-Click to clear)|r", 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                elseif self.itemID then
                    if GameTooltip.SetItemByID then
                        GameTooltip:SetItemByID(self.itemID)
                    end
                    GameTooltip:AddLine(" ")
                    if swapCount > 0 then
                        GameTooltip:AddLine(string.format("|cff00ffff[Quick Swap: %d items stored]|r", swapCount), 0.2, 0.9, 1.0)
                        GameTooltip:AddLine("|cff00ff00<Left-Click to Quick Swap>|r", 0, 1, 0)
                    else
                        GameTooltip:AddLine("|cff00ff00<Left-Click to open Quick Swap flyout>|r", 0, 1, 0)
                    end
                    GameTooltip:AddLine("|cff888888(Shift-Right-Click to clear)|r", 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                elseif self.spellName then
                    GameTooltip:AddLine(self.spellName, 1, 1, 1)
                    GameTooltip:AddLine(" ")
                    if swapCount > 0 then
                        GameTooltip:AddLine(string.format("|cff00ffff[Quick Swap: %d abilities stored]|r", swapCount), 0.2, 0.9, 1.0)
                        GameTooltip:AddLine("|cff00ff00<Left-Click to Quick Swap>|r", 0, 1, 0)
                    else
                        GameTooltip:AddLine("|cff00ff00<Left-Click to open Quick Swap flyout>|r", 0, 1, 0)
                    end
                    GameTooltip:AddLine("|cff888888(Shift-Right-Click to clear)|r", 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                else
                    GameTooltip:AddLine("Ability Slot " .. self.slotIndex, 1, 1, 1)
                    GameTooltip:AddLine("Drag & drop any ability from your Spellbook (P) or an item here.", 0.7, 0.7, 0.7, true)
                    GameTooltip:AddLine("|cff00ff00<Left-Click to open Quick Swap pool>|r", 0, 1, 0)
                    GameTooltip:Show()
                end
            end)
        end)

        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        slots[i] = btn
    end

    bar.slots = slots
    FC.CooldownBar = bar
    if FC.UpdateCooldownBarLayout then
        pcall(FC.UpdateCooldownBarLayout, FC)
    end

    -- OnUpdate ticker for smooth countdown timers
    local elapsedTicker = 0
    bar:SetScript("OnUpdate", function(self, elapsed)
        elapsedTicker = elapsedTicker + elapsed
        local throttle = (FC.hasActiveCooldowns or FC.gcdStart) and 0.10 or 0.25
        if elapsedTicker >= throttle then
            elapsedTicker = 0
            FC:UpdateCooldowns()
        end
    end)

    return bar
end

-- ============================================================================
-- Update Power (Dynamic Mana, Rage, Energy — WoW Forever Continuous Engine)
-- ============================================================================

function FC:UpdatePowerType()
    if not FC.PowerBar then return end

    local r, g, b, powerType = FC:GetPowerColor()

    FC.PowerBar:SetStatusBarColor(r, g, b)
    local tex = FC.PowerBar:GetStatusBarTexture()
    if tex then
        tex:SetVertexColor(r, g, b)
    end
    if FC.PowerBg then
        FC.PowerBg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 0.85)
    end

    -- If power type changed (e.g. Druid shapeshift), snap visual power immediately
    if FC.currentPowerType ~= powerType then
        FC.visualPower = nil
        FC.targetPower = nil
    end

    FC.currentPowerType = powerType
end

function FC:UpdatePower()
    if not FC.PowerBar then return end

    if not FC.currentPowerType then
        FC:UpdatePowerType()
    end

    local powerType = FC.currentPowerType or 0
    local currentPower, maxPower
    pcall(function()
        currentPower = UnitPower("player", powerType)
        maxPower = UnitPowerMax("player", powerType)
    end)

    if maxPower then
        FC.maxPower = maxPower
        pcall(FC.PowerBar.SetMinMaxValues, FC.PowerBar, 0, maxPower)
    end

    if currentPower then
        if IsSecret(currentPower) then
            -- Pass Midnight secret numbers directly to native C++ widget
            pcall(FC.PowerBar.SetValue, FC.PowerBar, currentPower)
            FC.visualPower = nil
            FC.targetPower = nil
        else
            local numCur = tonumber(currentPower) or 0
            FC.targetPower = numCur

            -- First-time initialization or major jump: snap immediately
            if not FC.visualPower or math.abs(numCur - (FC.visualPower or 0)) > ((maxPower and maxPower * 0.5) or 300) then
                FC.visualPower = numCur
                pcall(FC.PowerBar.SetValue, FC.PowerBar, numCur)
            end
        end
    end

    UpdatePowerText(FC.PowerText, currentPower, maxPower, powerType, ForeverClassesDB.textMode)
end

function FC:ProcessSmoothPower(elapsed)
    if not FC.PowerBar then return end

    local target = FC.targetPower
    local visual = FC.visualPower
    if not target or not visual or IsSecret(target) or IsSecret(visual) then
        return
    end

    local diff = target - visual
    if math.abs(diff) > 0.05 then
        -- Fast snap on large downward spend (ability cost > 12)
        -- so combat actions feel immediate and punchy
        if diff < -12 then
            FC.visualPower = target
            pcall(FC.PowerBar.SetValue, FC.PowerBar, target)
            return
        end

        -- Smooth continuous interpolation (WoW Forever 60-144 FPS smooth flow)
        -- For continuous energy (~10/s) and mana regeneration, this creates
        -- a completely fluid liquid progress bar without discrete staircase stepping
        local speed = 18 * elapsed
        if speed > 1 then speed = 1 end
        visual = visual + (diff * speed)
        FC.visualPower = visual
        pcall(FC.PowerBar.SetValue, FC.PowerBar, visual)
    elseif visual ~= target then
        FC.visualPower = target
        pcall(FC.PowerBar.SetValue, FC.PowerBar, target)
    end
end

-- ============================================================================
-- Rogue & Feral Combo Points (Below Resource Bar - In Combat)
-- ============================================================================

function FC:LayoutComboPips()
    if not FC.ComboFrame or not FC.ComboFrame.pips then return end
    local barWidth = (ForeverClassesDB and ForeverClassesDB.barWidth) or 240
    FC.ComboFrame:SetSize(barWidth, 24)

    local MAX_COMBO_POINTS = 5
    local circleSize = 16
    local gap = 4
    local totalWidth = (MAX_COMBO_POINTS * circleSize) + ((MAX_COMBO_POINTS - 1) * gap)
    local startLeft = math.floor((barWidth - totalWidth) / 2 + 0.5)

    for i = 1, MAX_COMBO_POINTS do
        local pip = FC.ComboFrame.pips[i]
        if pip then
            pip:SetSize(circleSize, circleSize)
            pip:ClearAllPoints()
            local left = startLeft + ((i - 1) * (circleSize + gap))
            pip:SetPoint("LEFT", FC.ComboFrame, "LEFT", left, 0)
        end
    end
end

function FC:GetComboPoints()
    if FC.testComboPoints ~= nil then
        return FC.testComboPoints
    end

    local cp = 0

    -- 1. Classic target-based combo points
    if GetComboPoints then
        local ok, pts = pcall(GetComboPoints, "player", "target")
        if ok and pts and not IsSecret(pts) and pts > 0 then
            return pts
        end
    end

    -- 2. Modern engine combo points (UnitPower with ComboPoints power type = 4)
    if UnitPower then
        local cpType = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
        local ok, pts = pcall(UnitPower, "player", cpType)
        if ok and pts and not IsSecret(pts) and pts > 0 then
            return pts
        end
    end

    return 0
end

function FC:UpdateComboPoints()
    if not FC.ComboFrame then return end

    if ForeverClassesDB and ForeverClassesDB.showComboPoints == false then
        FC.ComboFrame:Hide()
        return
    end

    local isTesting = (FC.testComboPoints ~= nil)
    local _, classToken = UnitClass("player")
    local isRogue = (classToken == "ROGUE")
    local isCatDruid = false
    if classToken == "DRUID" then
        local form = GetShapeshiftForm and GetShapeshiftForm()
        if form == 3 then
            isCatDruid = true
        end
    end

    if not isRogue and not isCatDruid and not isTesting then
        FC.ComboFrame:Hide()
        return
    end

    -- Combat Visibility: Show after entering combat, hide out of combat
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or FC.inCombat

    if not inCombat and not isTesting then
        FC.ComboFrame:Hide()
        return
    end

    -- Visible in combat (or during test preview)
    FC.ComboFrame:Show()

    local cp = FC:GetComboPoints() or 0
    if type(cp) ~= "number" or cp < 0 then cp = 0 end
    if cp > 5 then cp = 5 end

    local previousCP = FC.previousComboPoints or 0
    FC.previousComboPoints = cp
    if cp > 0 then
        FC.comboPointsBeforeFinisher = cp
    end

    for i = 1, 5 do
        local pip = FC.ComboFrame.pips[i]
        if pip then
            if i <= cp then
                if pip.fillHolder then
                    pip.fillHolder:Show()
                else
                    pip.fill:Show()
                end

                -- Play the pop-in appearance animation for newly earned points
                if i > previousCP and pip.animGroup then
                    pcall(function()
                        pip.animGroup:Stop()
                        pip.animGroup:Play()
                    end)
                end

                if cp == 5 then
                    if pip.glow then pip.glow:Show() end
                else
                    if pip.glow then pip.glow:Hide() end
                end
            else
                if pip.fillHolder then
                    pip.fillHolder:Hide()
                else
                    pip.fill:Hide()
                end
                if pip.animGroup then
                    pcall(pip.animGroup.Stop, pip.animGroup)
                end
                if pip.glow then pip.glow:Hide() end
            end
        end
    end
end

-- ============================================================================
-- Rogue Poison Tracking Engine (Passive Weapon Enchant & Charges HUD)
-- ============================================================================

local KNOWN_POISON_IDS = {
    -- Instant Poison (Ranks 1 to 7)
    [6947] = true, [6949] = true, [6950] = true, [8926] = true, [8927] = true, [8928] = true, [21927] = true,
    -- Deadly Poison (Ranks 1 to 5)
    [2892] = true, [2893] = true, [8984] = true, [8985] = true, [20844] = true,
    -- Crippling Poison (Ranks 1 & 2)
    [3775] = true, [3776] = true,
    -- Mind-numbing Poison (Ranks 1 to 3)
    [5237] = true, [6951] = true, [9186] = true,
    -- Wound Poison (Ranks 1 to 5)
    [10918] = true, [10920] = true, [10921] = true, [10922] = true, [22055] = true,
    -- Anesthetic Poison (Ranks 1 & 2)
    [21835] = true, [43231] = true,
}
FC.KNOWN_POISON_IDS = KNOWN_POISON_IDS

FC.poisonCache = {}
FC.poisonEnchantCache = {}

local POISON_REJECT_PATTERNS = {
    "anti%-venom", "antidote", "potion", "elixir", "flask", "water", "bread",
    "meat", "roast", "stew", "food", "drink", "scroll", "bandage", "stone", "oil"
}

local poisonScanTooltip = CreateFrame("GameTooltip", "ForeverClassesPoisonScanTooltip", nil, "GameTooltipTemplate")
poisonScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function SafeGetItemInfo(item)
    if not item then return nil end
    local fn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if not fn then return nil end
    local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17 = pcall(fn, item)
    if ok then
        return a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17
    end
    return nil
end

function FC:IsPoisonItem(itemID, itemLink)
    if not itemID then return false end

    if KNOWN_POISON_IDS[itemID] then
        local name, _, quality, _, _, _, _, _, _, texture = SafeGetItemInfo(itemID)
        return true, name, texture, quality
    end

    if FC.poisonCache[itemID] ~= nil then
        if FC.poisonCache[itemID] == false then
            return false
        else
            local name, _, quality, _, _, _, _, _, _, texture = SafeGetItemInfo(itemID)
            return true, name, texture, quality
        end
    end

    local itemName, _, itemQuality, _, _, _, itemSubType, _, _, itemTexture = SafeGetItemInfo(itemLink or itemID)

    if itemName then
        local lowerName = string.lower(itemName)
        for _, pat in ipairs(POISON_REJECT_PATTERNS) do
            if string.find(lowerName, pat) then
                FC.poisonCache[itemID] = false
                return false
            end
        end
    end

    if itemSubType and itemSubType ~= "Poison" and itemSubType ~= "Consumable" and itemSubType ~= "Other" then
        FC.poisonCache[itemID] = false
        return false
    end

    local isPoison = false
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local data = C_TooltipInfo.GetItemByID(itemID)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local text = line.leftText
                if text then
                    local lower = string.lower(text)
                    if string.find(lower, "coats your weapon") or string.find(lower, "coats a weapon") or
                       string.find(lower, "coat your weapon") or string.find(lower, "apply a poison to your weapon") then
                        isPoison = true
                        break
                    end
                end
            end
        end
    else
        poisonScanTooltip:ClearLines()
        if itemLink then
            poisonScanTooltip:SetHyperlink(itemLink)
        else
            poisonScanTooltip:SetItemByID(itemID)
        end
        for i = 1, poisonScanTooltip:NumLines() do
            local line = _G["ForeverClassesPoisonScanTooltipTextLeft" .. i]
            if line then
                local text = line:GetText()
                if text then
                    local lower = string.lower(text)
                    if string.find(lower, "coats your weapon") or string.find(lower, "coats a weapon") or
                       string.find(lower, "coat your weapon") or string.find(lower, "apply a poison to your weapon") then
                        isPoison = true
                        break
                    end
                end
            end
        end
    end

    FC.poisonCache[itemID] = isPoison
    if isPoison then
        return true, itemName or ("Poison #" .. itemID), itemTexture, itemQuality
    end
    return false
end

function FC:ScanPoisonsInBags()
    local poisonsFound = {}
    local itemCounts = {}

    local getNumSlots = C_Container and C_Container.GetContainerNumSlots or _G.GetContainerNumSlots
    local getItemID   = C_Container and C_Container.GetContainerItemID or _G.GetContainerItemID
    local getItemLink = C_Container and C_Container.GetContainerItemLink or _G.GetContainerItemLink
    local getItemInfo = C_Container and C_Container.GetContainerItemInfo or _G.GetContainerItemInfo

    local numBags = NUM_BAG_SLOTS or 4
    for bag = 0, numBags do
        local numSlots = getNumSlots and getNumSlots(bag) or 0
        for slot = 1, numSlots do
            local itemID = getItemID and getItemID(bag, slot)
            if itemID then
                local link = getItemLink and getItemLink(bag, slot)
                local isPoison, name, texture, quality = FC:IsPoisonItem(itemID, link)
                if isPoison then
                    local stackCount = 1
                    local info = getItemInfo and getItemInfo(bag, slot)
                    if type(info) == "table" and info.stackCount then
                        stackCount = info.stackCount
                    elseif type(info) == "number" then
                        stackCount = info
                    end

                    if not itemCounts[itemID] then
                        itemCounts[itemID] = {
                            itemID = itemID,
                            name = name or ("Poison " .. itemID),
                            texture = texture or "Interface\\Icons\\Ability_Poisons",
                            quality = quality or 1,
                            count = stackCount,
                            link = link,
                        }
                    else
                        itemCounts[itemID].count = itemCounts[itemID].count + stackCount
                    end
                end
            end
        end
    end

    for _, data in pairs(itemCounts) do
        table.insert(poisonsFound, data)
    end

    table.sort(poisonsFound, function(a, b)
        local isLastA = (a.itemID == ForeverClassesDB.lastPoisonMH or a.itemID == ForeverClassesDB.lastPoisonOH)
        local isLastB = (b.itemID == ForeverClassesDB.lastPoisonMH or b.itemID == ForeverClassesDB.lastPoisonOH)
        if isLastA ~= isLastB then return isLastA end
        return (a.name or "") < (b.name or "")
    end)

    return poisonsFound
end

function FC:GetWeaponEnchantNameAndIcon(slotID, enchantID)
    if not enchantID then return nil, nil end

    if FC.poisonEnchantCache[enchantID] then
        return FC.poisonEnchantCache[enchantID].name, FC.poisonEnchantCache[enchantID].icon
    end

    if InCombatLockdown and InCombatLockdown() then
        local lastID = (slotID == 16) and ForeverClassesDB.lastPoisonMH or ForeverClassesDB.lastPoisonOH
        if lastID then
            local name, _, _, _, _, _, _, _, _, icon = SafeGetItemInfo(lastID)
            return name, icon
        end
        return "Poison", "Interface\\Icons\\Ability_Poisons"
    end

    local enchantName = nil
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local data = C_TooltipInfo.GetInventoryItem("player", slotID)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local text = line.leftText
                local r, g, b = line.leftColor and line.leftColor.r, line.leftColor and line.leftColor.g, line.leftColor and line.leftColor.b
                if text and r and g and b and (g > 0.7 and r < 0.35 and b < 0.35) then
                    local clean = string.match(text, "^(.-)%s*%(") or text
                    clean = string.gsub(clean, "%s+$", "")
                    enchantName = clean
                    break
                end
            end
        end
    end

    if not enchantName then
        poisonScanTooltip:ClearLines()
        poisonScanTooltip:SetInventoryItem("player", slotID)
        for i = 1, poisonScanTooltip:NumLines() do
            local line = _G["ForeverClassesPoisonScanTooltipTextLeft" .. i]
            if line then
                local r, g, b = line:GetTextColor()
                local text = line:GetText()
                if text and (g > 0.7 and r < 0.35 and b < 0.35) then
                    local clean = string.match(text, "^(.-)%s*%(") or text
                    clean = string.gsub(clean, "%s+$", "")
                    enchantName = clean
                    break
                end
            end
        end
    end

    local icon = nil
    if enchantName then
        local _, _, _, _, _, _, _, _, _, itemTexture = SafeGetItemInfo(enchantName)
        if itemTexture then
            icon = itemTexture
        else
            local lower = string.lower(enchantName)
            if string.find(lower, "deadly") then
                icon = "Interface\\Icons\\Ability_Rogue_DualWeild"
            elseif string.find(lower, "crippling") then
                icon = "Interface\\Icons\\Ability_Poison"
            elseif string.find(lower, "wound") then
                icon = "Interface\\Icons\\INV_Misc_Herb_16"
            elseif string.find(lower, "mind") then
                icon = "Interface\\Icons\\Spell_Nature_NullifyDisease"
            elseif string.find(lower, "anesthetic") then
                icon = "Interface\\Icons\\Spell_Nature_SlowPoison"
            else
                icon = "Interface\\Icons\\Ability_Poisons"
            end
        end
    end

    if enchantName and icon then
        FC.poisonEnchantCache[enchantID] = { name = enchantName, icon = icon }
    end

    return enchantName, icon
end

function FC:UpdatePoisonSlot(slot, hasEnchant, expirationMs, charges, enchantID)
    if not slot then return end

    if hasEnchant then
        local secondsLeft = math.floor((expirationMs or 0) / 1000)
        slot.currentExp = secondsLeft
        slot.currentCharges = charges

        if slot.lastEnchantID ~= enchantID or not slot.poisonName then
            slot.lastEnchantID = enchantID
            local name, icon = FC:GetWeaponEnchantNameAndIcon(slot.slotID, enchantID)
            slot.poisonName = name
            slot.poisonIcon = icon
        end

        if slot.poisonIcon then
            slot.icon:SetTexture(slot.poisonIcon)
        else
            slot.icon:SetTexture("Interface\\Icons\\Ability_Poisons")
        end
        slot.icon:SetDesaturated(false)
        slot.plusIcon:Hide()

        local threshold = ForeverClassesDB.poisonAlertThreshold or 15
        local isLow = false
        if charges and charges > 0 and charges <= threshold then
            isLow = true
        elseif secondsLeft > 0 and secondsLeft <= 120 then
            isLow = true
        end

        if isLow then
            slot.state = "LOW"
            slot:SetBackdropBorderColor(1.0, 0.72, 0.1, 0.95)
            slot.glow:Show()

            if ForeverClassesDB.poisonSoundAlert and (slot.lastCharges and slot.lastCharges > threshold) then
                PlaySound(8959, "Master")
            end
        else
            slot.state = "ACTIVE"
            slot:SetBackdropBorderColor(0.0, 0.95, 0.6, 0.95)
            slot.glow:Hide()
        end

        if charges and charges > 0 then
            slot.chargesText:SetText(charges)
            if charges > 20 then
                slot.chargesText:SetTextColor(0.2, 1.0, 0.4)
            elseif charges > threshold then
                slot.chargesText:SetTextColor(1.0, 0.85, 0.1)
            else
                slot.chargesText:SetTextColor(1.0, 0.25, 0.25)
            end
        else
            slot.chargesText:SetText("")
        end

        if slot.durationBar then
            slot.durationBar:Show()
            slot.durationBar:SetValue(math.min(secondsLeft, 1800))
            if isLow then
                slot.durationBar:SetStatusBarColor(1.0, 0.70, 0.10, 0.9)
            else
                slot.durationBar:SetStatusBarColor(0.0, 0.95, 0.60, 0.85)
            end
        end

        slot.lastCharges = charges
    else
        slot.poisonName = nil
        slot.poisonIcon = nil
        slot.currentExp = nil
        slot.currentCharges = nil
        slot.lastEnchantID = nil
        slot.lastCharges = nil
        slot.state = "MISSING"

        local equipTexture = GetInventoryItemTexture and GetInventoryItemTexture("player", slot.slotID)
        if equipTexture then
            slot.icon:SetTexture(equipTexture)
        else
            if slot.slotID == 16 then
                slot.icon:SetTexture("Interface\\Icons\\INV_Sword_04")
            else
                slot.icon:SetTexture("Interface\\Icons\\INV_Weapon_ShortBlade_05")
            end
        end
        slot.icon:SetDesaturated(true)
        slot.plusIcon:Show()

        slot.chargesText:SetText("")
        if slot.durationBar then slot.durationBar:Hide() end
        slot.glow:Hide()
        slot:SetBackdropBorderColor(0.9, 0.2, 0.2, 0.95)
    end
end

function FC:UpdatePoisonTracker()
    if not FC.PoisonBar then return end

    local _, classToken = UnitClass("player")
    if classToken ~= "ROGUE" then
        FC.PoisonBar:Hide()
        return
    end

    if ForeverClassesDB and ForeverClassesDB.showPoisonTracker == false then
        FC.PoisonBar:Hide()
        return
    end

    local hasMH, mhExp, mhCharges, mhEnchantID, hasOH, ohExp, ohCharges, ohEnchantID = GetWeaponEnchantInfo()
    FC:UpdatePoisonSlot(FC.PoisonMH, hasMH, mhExp, mhCharges, mhEnchantID)
    FC:UpdatePoisonSlot(FC.PoisonOH, hasOH, ohExp, ohCharges, ohEnchantID)

    if ForeverClassesDB.poisonAutoHide then
        local mhActive = FC.PoisonMH and FC.PoisonMH.state == "ACTIVE"
        local ohActive = FC.PoisonOH and FC.PoisonOH.state == "ACTIVE"
        if mhActive and ohActive then
            if FC.PoisonBar:IsShown() and not (FC.PoisonFlyout and FC.PoisonFlyout:IsShown()) then
                FC.PoisonBar:Hide()
            end
            return
        end
    end

    FC.PoisonBar:Show()
end

-- ============================================================================
-- Rogue Quick-Apply Flyout Menu (SecureActionButton Macro Executor)
-- ============================================================================

local poisonFlyoutButtons = {}

function FC:GetOrCreatePoisonFlyout()
    if FC.PoisonFlyout then return FC.PoisonFlyout end

    local flyout = CreateFrame("Frame", "ForeverClassesPoisonFlyout", UIParent, BackdropTemplateString)
    flyout:SetClampedToScreen(true)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetFrameLevel(50)
    flyout:EnableMouse(true)
    flyout:Hide()

    flyout:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    flyout:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    flyout:SetBackdropBorderColor(0.0, 0.95, 0.60, 0.95)

    local title = flyout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOP", flyout, "TOP", 0, -4)
    title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    title:SetJustifyH("CENTER")
    title:SetText("MH")
    title:SetTextColor(0, 1, 0.6)
    flyout.title = title

    local emptyText = flyout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("CENTER", flyout, "CENTER", 0, -4)
    emptyText:SetText("|cffff4444No poisons in bags!|r")
    emptyText:Hide()
    flyout.emptyText = emptyText

    tinsert(UISpecialFrames, "ForeverClassesPoisonFlyout")

    local dismiss = CreateFrame("Button", "ForeverClassesPoisonFlyoutDismiss", UIParent)
    dismiss:SetAllPoints(UIParent)
    dismiss:SetFrameStrata("HIGH")
    dismiss:SetFrameLevel(10)
    dismiss:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
    dismiss:Hide()
    dismiss:SetScript("OnClick", function()
        FC:HidePoisonFlyout()
    end)
    flyout.dismiss = dismiss

    flyout:SetScript("OnShow", function(self)
        dismiss:Show()
    end)
    flyout:SetScript("OnHide", function()
        dismiss:Hide()
    end)

    FC.PoisonFlyout = flyout
    return flyout
end

local function GetPoisonFlyoutButton(index, parent)
    if poisonFlyoutButtons[index] then
        return poisonFlyoutButtons[index]
    end

    local template = "SecureActionButtonTemplate" .. (BackdropTemplateString and (", " .. BackdropTemplateString) or "")
    local btn = CreateFrame("Button", "ForeverClassesPoisonApplyBtn" .. index, parent, template)
    btn:SetSize(32, 32)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    btn:RegisterForClicks("AnyUp", "AnyDown")

    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    btn:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local countText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 1)
    countText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    countText:SetTextColor(1, 0.82, 0.1)
    btn.countText = countText

    local activeMark = btn:CreateTexture(nil, "OVERLAY")
    activeMark:SetSize(8, 8)
    activeMark:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
    activeMark:SetColorTexture(0.0, 1.0, 0.8, 1.0)
    activeMark:Hide()
    btn.activeMark = activeMark

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    hl:SetColorTexture(0, 1, 0.6, 0.25)

    btn:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        elseif self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn:SetScript("PostClick", function(self)
        if self.itemID and parent.currentTargetSlot then
            if parent.currentTargetSlot == 16 then
                ForeverClassesDB.lastPoisonMH = self.itemID
            else
                ForeverClassesDB.lastPoisonOH = self.itemID
            end
        end
        FC:HidePoisonFlyout()
    end)

    poisonFlyoutButtons[index] = btn
    return btn
end

function FC:HidePoisonFlyout()
    if FC.PoisonFlyout and FC.PoisonFlyout:IsShown() then
        FC.PoisonFlyout:Hide()
    end
end

function FC:PopulatePoisonFlyoutItems()
    local menu = FC.PoisonFlyout
    if not menu or not menu.currentTargetSlot then return end

    local poisons = FC:ScanPoisonsInBags()
    local numPoisons = #poisons

    for _, btn in ipairs(poisonFlyoutButtons) do
        btn:Hide()
    end

    if numPoisons == 0 then
        menu:SetSize(140, 48)
        menu.emptyText:Show()
        return
    end

    menu.emptyText:Hide()

    local btnSize = 34
    local spacing = 3
    local padding = 3
    local headerH = 16

    local totalHeight = headerH + (numPoisons * (btnSize + spacing)) + padding
    menu:SetSize(40, totalHeight)

    local currentSlot = (menu.currentTargetSlot == 16) and FC.PoisonMH or FC.PoisonOH
    local activeName = currentSlot and currentSlot.poisonName

    for i, poison in ipairs(poisons) do
        local btn = GetPoisonFlyoutButton(i, menu)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", padding, -headerH - ((i - 1) * (btnSize + spacing)))
        btn:SetSize(btnSize, btnSize)

        btn.itemID = poison.itemID
        btn.itemLink = poison.link
        btn.icon:SetTexture(poison.texture)
        btn.countText:SetText(poison.count > 1 and ("x" .. poison.count) or "")

        local isActive = (activeName and string.find(poison.name, activeName, 1, true))
        if isActive then
            btn.activeMark:Show()
            btn:SetBackdropBorderColor(0.0, 1.0, 0.8, 1.0)
        else
            btn.activeMark:Hide()
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
        end

        local macroText = string.format("/use item:%d\n/use %d", poison.itemID, menu.currentTargetSlot)
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", macroText)

        btn:Show()
    end
end

function FC:TogglePoisonFlyout(anchorFrame, targetSlotID)
    if InCombatLockdown and InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[ForeverClasses]|r |cffff2020Cannot modify poisons in combat!|r")
        return
    end

    local menu = FC:GetOrCreatePoisonFlyout()
    if menu:IsShown() and menu.currentTargetSlot == targetSlotID then
        menu:Hide()
        return
    end

    menu.currentTargetSlot = targetSlotID
    menu.anchorFrame = anchorFrame

    local handName = (targetSlotID == 16) and "MH" or "OH"
    menu.title:SetText(handName)

    menu:ClearAllPoints()
    local frameTop = anchorFrame:GetTop() or 0
    local screenHeight = GetScreenHeight and GetScreenHeight() or 768
    local openDownwards = (frameTop > (screenHeight - 180))

    if openDownwards then
        menu:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4)
    else
        menu:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 4)
    end

    FC:PopulatePoisonFlyoutItems()
    menu:Show()
end

function FC:OnBagUpdateDelayed()
    if InCombatLockdown and InCombatLockdown() then return end
    if FC.PoisonFlyout and FC.PoisonFlyout:IsShown() and FC.PoisonFlyout.currentTargetSlot then
        FC:PopulatePoisonFlyoutItems()
    end
end

function FC:CheckMissingPoisonReminder(triggerContext)
    if not ForeverClassesDB or ForeverClassesDB.poisonReminders == false then return end
    local _, classToken = UnitClass("player")
    if classToken ~= "ROGUE" then return end

    local hasMH, _, _, _, hasOH = GetWeaponEnchantInfo()
    if not hasMH or not hasOH then
        local missing = {}
        if not hasMH then table.insert(missing, "Main-Hand") end
        if not hasOH then table.insert(missing, "Off-Hand") end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[ForeverClasses]|r |cffffd100Poison Reminder (%s):|r Missing poison on |cffff4444%s|r weapon!", triggerContext or "Notice", table.concat(missing, " & ")))
        if ForeverClassesDB.poisonSoundAlert ~= false then
            PlaySound(8959, "Master")
        end
    end
end

function FC:FormatTotemTime(s)
    if not s or s <= 0 then return "" end
    if s >= 60 then
        return string.format("%d m", math.ceil(s / 60))
    elseif s >= 10 then
        return string.format("%d s", math.floor(s))
    else
        return string.format("%.1f s", s)
    end
end

local function GetPlayerWorldCoordinates()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition or not C_Map.GetWorldPosFromMapPos then
        return nil, nil, nil
    end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not mapID then return nil, nil, nil end

    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok2 or not pos then return nil, nil, nil end

    local ok3, continentID, worldPos = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
    if not ok3 or not worldPos then return nil, nil, nil end

    local ok4, x, y = pcall(function()
        if worldPos.GetXY then
            return worldPos:GetXY()
        else
            return worldPos.x, worldPos.y
        end
    end)
    if ok4 and x and y then
        return x, y, continentID
    end
    return nil, nil, nil
end

function FC:HasTotemicMastery()
    -- 1. Modern / Classic spell known check (spell ID 16189)
    if (IsPlayerSpell and IsPlayerSpell(16189)) or (IsSpellKnown and IsSpellKnown(16189)) then
        return true
    end

    -- 2. TalentsForeverBookDB SavedVariables (Restoration tree 3, talent 8)
    if _G.TalentsForeverBookDB and _G.TalentsForeverBookDB.chars then
        local pName = UnitName and UnitName("player")
        local pRealm = GetRealmName and GetRealmName()
        local charKey = (pName and pRealm) and (pName .. "-" .. pRealm) or nil
        local cData = charKey and _G.TalentsForeverBookDB.chars[charKey]
        if cData and cData.plan and cData.plan.ranks and cData.plan.ranks[3] then
            local r = cData.plan.ranks[3][8]
            if type(r) == "number" and r > 0 then
                return true
            end
        end
    end

    -- 3. TalentsForeverBook runtime table
    if _G.TalentsForeverBook and _G.TalentsForeverBook.Game and _G.TalentsForeverBook.Game.Rank then
        local ok, r = pcall(_G.TalentsForeverBook.Game.Rank, 3, 8)
        if ok and type(r) == "number" and r > 0 then
            return true
        end
    end

    return false
end

function FC:IsTotemOutOfRange(slot, totemName, startTime)
    if not totemName or totemName == "" then return false end
    local now = GetTime()
    local sTime = tonumber(startTime) or now

    -- Grace period: Allow 2.0s after placement
    if (now - sTime) < 2.0 then
        return false
    end

    local clean = CleanTotemName(totemName)
    local rangeInfo = TOTEM_RANGE_DATA[clean]
    if not rangeInfo then
        for k, v in pairs(TOTEM_RANGE_DATA) do
            if clean:find(k, 1, true) or k:find(clean, 1, true) then
                rangeInfo = v
                break
            end
        end
    end

    local maxRange = (rangeInfo and rangeInfo.range) or 30
    if FC:HasTotemicMastery() and maxRange < 100 then
        maxRange = maxRange + 10
    end

    -- 1. Physical distance check via player world coordinates (Universal ground truth)
    local tPos = slot and FC.totemPositions and FC.totemPositions[slot]
    if tPos and tPos.x and tPos.y and tPos.continentID then
        local curX, curY, contID = GetPlayerWorldCoordinates()
        if curX and curY and contID and contID == tPos.continentID then
            local dx = curX - tPos.x
            local dy = curY - tPos.y
            local dist = math.sqrt(dx * dx + dy * dy)
            return dist > maxRange
        end
    end

    -- 2. Out of combat fallback: Check authoritative player buff for beneficial aura totems
    local inCombat = InCombatLockdown and InCombatLockdown()
    if not inCombat and rangeInfo and rangeInfo.buff then
        if GetPlayerBuffs then
            local buffs = GetPlayerBuffs()
            if buffs then
                local b1 = rangeInfo.buff
                local b2 = rangeInfo.altBuff
                if buffs[b1] or (b2 and buffs[b2]) then
                    return false
                end
                for k in pairs(buffs) do
                    if k == b1 or (b2 and k == b2) or k:find(b1, 1, true) or (b2 and k:find(b2, 1, true)) then
                        return false
                    end
                end
                -- Buff is missing out of combat after grace period
                return true
            end
        end
    end

    -- If in combat or coordinates not available in current instance, default to IN RANGE
    return false
end

function FC:UpdateTotemTimes()
    if not FC.TotemBar or not FC.TotemBar:IsShown() then return end
    local now = GetTime()
    local hasExpired = false
    local isTesting = (FC.testTotems ~= nil)

    for i = 1, 4 do
        local btn = FC.TotemBar.buttons and FC.TotemBar.buttons[i]
        if btn and btn:IsShown() and btn.startTime and btn.duration and btn.duration > 0 then
            local rem = (btn.startTime + btn.duration) - now
            if rem <= 0 then
                hasExpired = true
                btn.timeText:SetText("")
            else
                btn.timeText:SetText(FC:FormatTotemTime(rem))
            end

            -- Check out-of-range state
            local isOutOfRange = false
            if isTesting then
                isOutOfRange = (btn.testOutOfRange == true)
            else
                isOutOfRange = FC:IsTotemOutOfRange(btn.slot, btn.totemName, btn.startTime)
            end

            if btn.isOutOfRange ~= isOutOfRange then
                btn.isOutOfRange = isOutOfRange
                if isOutOfRange then
                    btn.icon:SetVertexColor(1.0, 0.25, 0.25)
                    btn.border:SetVertexColor(1.0, 0.35, 0.35)
                    btn.timeText:SetTextColor(1.0, 0.35, 0.35, 1.0)
                else
                    btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                    btn.border:SetVertexColor(1.0, 1.0, 1.0)
                    btn.timeText:SetTextColor(1.0, 1.0, 1.0, 1.0)
                end
            end
        end
    end

    if hasExpired and not isTesting then
        FC:UpdateTotems()
    end
end

function FC:UpdateTotems()
    if not FC.TotemBar then return end

    if ForeverClassesDB and ForeverClassesDB.showTotems == false then
        FC.TotemBar:Hide()
        return
    end

    local _, classToken = UnitClass("player")
    local isShaman = (classToken == "SHAMAN")
    local isTesting = (FC.testTotems ~= nil)

    if not isShaman and not isTesting then
        FC.TotemBar:Hide()
        return
    end

    local activeTotems = {}
    local now = GetTime()

    if isTesting and FC.testTotems then
        for _, t in ipairs(FC.testTotems) do
            table.insert(activeTotems, t)
        end
    else
        local inCombat = InCombatLockdown and InCombatLockdown()
        FC.activeTotemSlots = FC.activeTotemSlots or {}
        FC.totemPositions = FC.totemPositions or {}

        if not inCombat and GetTotemInfo then
            -- Out of combat: Safely sync from native GetTotemInfo
            for slot = 1, 4 do
                local ok, haveTotem, totemName, startTime, duration, icon = pcall(GetTotemInfo, slot)
                if ok and haveTotem and not IsSecret(haveTotem) and haveTotem == true and totemName and not IsSecret(totemName) and totemName ~= "" then
                    local numDur = (not IsSecret(duration) and tonumber(duration)) or 0
                    local numStart = (not IsSecret(startTime) and tonumber(startTime)) or 0
                    local sClean = CleanTotemName(totemName)
                    if numDur > 0 then
                        FC.cachedTotemDurations = FC.cachedTotemDurations or {}
                        FC.cachedTotemDurations[sClean] = numDur
                        if ForeverClassesDB then
                            ForeverClassesDB.cachedTotemDurations = ForeverClassesDB.cachedTotemDurations or {}
                            ForeverClassesDB.cachedTotemDurations[sClean] = numDur
                        end
                    else
                        numDur = (FC.cachedTotemDurations and FC.cachedTotemDurations[sClean]) or STANDARD_TOTEM_DURATIONS[sClean] or 300
                    end
                    if numStart <= 0 then
                        numStart = now
                    end
                    local rem = (numStart + numDur) - now
                    if rem > 0 then
                        FC.activeTotemSlots[slot] = {
                            slot = slot,
                            name = totemName,
                            startTime = numStart,
                            duration = numDur,
                            icon = icon,
                        }
                        local prevPos = FC.totemPositions[slot]
                        if not prevPos or prevPos.startTime ~= numStart or prevPos.name ~= totemName then
                            local curX, curY, contID = GetPlayerWorldCoordinates()
                            if curX and curY and contID then
                                FC.totemPositions[slot] = {
                                    x = curX,
                                    y = curY,
                                    continentID = contID,
                                    startTime = numStart,
                                    name = totemName,
                                }
                            else
                                FC.totemPositions[slot] = nil
                            end
                        end
                    else
                        FC.activeTotemSlots[slot] = nil
                        FC.totemPositions[slot] = nil
                    end
                else
                    FC.activeTotemSlots[slot] = nil
                    FC.totemPositions[slot] = nil
                end
            end
        end

        -- Collect currently active totems from FC.activeTotemSlots (used both in combat & out of combat)
        for slot = 1, 4 do
            local tData = FC.activeTotemSlots[slot]
            if tData and tData.startTime and tData.duration then
                local rem = (tData.startTime + tData.duration) - now
                if rem > 0 then
                    table.insert(activeTotems, tData)
                else
                    FC.activeTotemSlots[slot] = nil
                    FC.totemPositions[slot] = nil
                end
            end
        end
    end

    if #activeTotems == 0 then
        FC.TotemBar:Hide()
        for i = 1, 4 do
            local btn = FC.TotemBar.buttons and FC.TotemBar.buttons[i]
            if btn then
                btn.slot = nil
                btn.totemName = nil
                btn.testName = nil
                btn.testElement = nil
                btn.testOutOfRange = nil
                btn.isOutOfRange = nil
                btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                btn.border:SetVertexColor(1.0, 1.0, 1.0)
                btn.timeText:SetTextColor(1.0, 1.0, 1.0, 1.0)
                btn:Hide()
            end
        end
        return
    end

    FC.TotemBar:Show()
    local iconSize = 26
    local gap = 8
    local totalWidth = (#activeTotems * iconSize) + ((#activeTotems - 1) * gap)
    local barWidth = (ForeverClassesDB and ForeverClassesDB.barWidth) or 240
    local startX = math.floor((barWidth - totalWidth) / 2)

    for i = 1, 4 do
        local btn = FC.TotemBar.buttons and FC.TotemBar.buttons[i]
        if btn then
            if i <= #activeTotems then
                local data = activeTotems[i]
                btn.slot = data.slot
                btn.totemName = data.name
                btn.testName = data.testName
                btn.testElement = data.element
                btn.testOutOfRange = data.testOutOfRange
                btn.startTime = data.startTime
                btn.duration = data.duration

                if data.icon then
                    btn.icon:SetTexture(data.icon)
                end

                if data.startTime and data.duration and data.duration > 0 then
                    btn.cooldown:SetCooldown(data.startTime, data.duration)
                    local rem = math.max(0, (data.startTime + data.duration) - now)
                    btn.timeText:SetText(FC:FormatTotemTime(rem))
                else
                    btn.cooldown:Clear()
                    btn.timeText:SetText("")
                end

                -- Range check on setup
                local isOutOfRange = false
                if isTesting then
                    isOutOfRange = (data.testOutOfRange == true)
                else
                    isOutOfRange = FC:IsTotemOutOfRange(data.slot, data.name, data.startTime)
                end
                btn.isOutOfRange = isOutOfRange
                if isOutOfRange then
                    btn.icon:SetVertexColor(1.0, 0.25, 0.25)
                    btn.border:SetVertexColor(1.0, 0.35, 0.35)
                    btn.timeText:SetTextColor(1.0, 0.35, 0.35, 1.0)
                else
                    btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                    btn.border:SetVertexColor(1.0, 1.0, 1.0)
                    btn.timeText:SetTextColor(1.0, 1.0, 1.0, 1.0)
                end

                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", FC.TotemBar, "TOPLEFT", startX + ((i - 1) * (iconSize + gap)), 0)
                btn:Show()
            else
                btn.slot = nil
                btn.totemName = nil
                btn.testName = nil
                btn.testElement = nil
                btn.testOutOfRange = nil
                btn.isOutOfRange = nil
                btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                btn.border:SetVertexColor(1.0, 1.0, 1.0)
                btn.timeText:SetTextColor(1.0, 1.0, 1.0, 1.0)
                btn:Hide()
            end
        end
    end
end

-- ============================================================================
-- Apply Configuration Changes
-- ============================================================================

function FC:ApplyConfig()
    if not FC.Frame then return end

    local db = ForeverClassesDB
    FC.Frame:ClearAllPoints()
    FC.Frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER", db.x or 0, db.y or -140)
    FC.Frame:SetSize(db.barWidth + 6, db.healthHeight + db.powerHeight + 11)

    if FC.HealthBar then
        FC.HealthBar:SetSize(db.barWidth, db.healthHeight)
    end
    if FC.HealPrediction then
        FC.HealPrediction:SetSize(db.barWidth, db.healthHeight)
    end
    if FC.AbsorbBar then
        FC.AbsorbBar:SetHeight(db.healthHeight)
    end
    if FC.PowerBar then
        FC.PowerBar:SetSize(db.barWidth, db.powerHeight)
    end
    if FC.TotemBar then
        FC.TotemBar:SetWidth(db.barWidth)
    end

    pcall(function() FC:LayoutComboPips() end)
    pcall(function() FC:UpdatePowerType() end)
    pcall(function() FC:UpdateHealth() end)
    pcall(function() FC:UpdatePower() end)
    pcall(function() FC:UpdateComboPoints() end)
    pcall(function() FC:UpdateTotems() end)
    pcall(function() FC:UpdateDebuffs() end)
    if FC.UpdateCooldownBarLayout then
        pcall(FC.UpdateCooldownBarLayout, FC)
    end
    pcall(function() FC:UpdateCooldowns() end)
    if FC.UpdateMinimapVisibility then
        pcall(FC.UpdateMinimapVisibility, FC)
    end
    if FC.RequestFadeCheck then
        pcall(FC.RequestFadeCheck, FC)
    end
    if ForeverClassesDB and not ForeverClassesDB.autoFade and FC.Frame then
        FC.Frame:SetAlpha(1.0)
    end
    if FC.SyncActiveCharSettings then
        pcall(FC.SyncActiveCharSettings, FC)
    end
end

-- ============================================================================
-- Event Listener Frame
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("UNIT_HEALTH")
pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_HEALTH_FREQUENT")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_ABSORB_AMOUNT_CHANGED")
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "player")
pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_POWER_FREQUENT")
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_POWER_FREQUENT", "player")
eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
eventFrame:RegisterEvent("UNIT_MAXPOWER")
eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_HEAL_PREDICTION")
eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
eventFrame:RegisterEvent("CVAR_UPDATE")
pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_COMBO_POINTS")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("PLAYER_UNGHOST")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
eventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
pcall(eventFrame.RegisterEvent, eventFrame, "ACTIONBAR_UPDATE_COOLDOWN")
pcall(eventFrame.RegisterEvent, eventFrame, "BAG_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELLS_CHANGED")
pcall(eventFrame.RegisterEvent, eventFrame, "ACTIONBAR_SLOT_CHANGED")
pcall(eventFrame.RegisterEvent, eventFrame, "ACTIONBAR_PAGE_CHANGED")
pcall(eventFrame.RegisterEvent, eventFrame, "UPDATE_VEHICLE_ACTION_BAR")
pcall(eventFrame.RegisterEvent, eventFrame, "ACTIONBAR_UPDATE_STATE")
pcall(eventFrame.RegisterEvent, eventFrame, "LEARNED_SPELL_IN_TAB")
pcall(eventFrame.RegisterEvent, eventFrame, "CHARACTER_POINTS_CHANGED")
pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_TALENT_UPDATE")
pcall(eventFrame.RegisterEvent, eventFrame, "EDIT_MODE_LAYOUTS_UPDATED")
pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_TOTEM_UPDATE")
pcall(eventFrame.RegisterEvent, eventFrame, "ACTIONBAR_UPDATE_USABLE")
pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_COMBAT")
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_COMBAT", "player")
pcall(eventFrame.RegisterEvent, eventFrame, "COMBAT_TEXT_UPDATE")
pcall(eventFrame.RegisterEvent, eventFrame, "TRAIT_CONFIG_UPDATED")
pcall(eventFrame.RegisterEvent, eventFrame, "TRAIT_NODE_CHANGED")
pcall(eventFrame.RegisterEvent, eventFrame, "ACTIVE_COMBAT_CONFIG_CHANGED")
pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_INVENTORY_CHANGED")
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_INVENTORY_CHANGED", "player")
pcall(eventFrame.RegisterEvent, eventFrame, "BAG_UPDATE_DELAYED")
pcall(eventFrame.RegisterEvent, eventFrame, "READY_CHECK")

local function HandleStormstrikeDodgeOrParry()
    local _, classToken = UnitClass("player")
    if classToken ~= "SHAMAN" then return end

    if not (FC.activeCooldowns and FC.activeCooldowns["stormstrike"]) then
        return
    end

    local rank = FC.improvedStormstrikeRank
    local charData = FC.GetCharData and FC:GetCharData()
    if rank == nil and charData then
        rank = charData.improvedStormstrikeRank
    end

    -- If rank is not yet known or 0, attempt a quick lookup
    if rank == nil or rank == 0 then
        if _G.TalentsForeverBookDB and _G.TalentsForeverBookDB.chars then
            local pName = UnitName and UnitName("player")
            local pRealm = GetRealmName and GetRealmName()
            local charKey = (pName and pRealm) and (pName .. "-" .. pRealm) or nil
            local cData = charKey and _G.TalentsForeverBookDB.chars[charKey]
            if cData and cData.plan and cData.plan.ranks and cData.plan.ranks[2] then
                local r = cData.plan.ranks[2][16]
                if type(r) == "number" and r > 0 then rank = r end
            end
        end
        if (not rank or rank == 0) and _G.TalentsForeverBook and _G.TalentsForeverBook.Game and _G.TalentsForeverBook.Game.Rank then
            local ok, r = pcall(_G.TalentsForeverBook.Game.Rank, 2, 16)
            if ok and type(r) == "number" and r > 0 then rank = r end
        end
        if (not rank or rank == 0) and ((IsPlayerSpell and IsPlayerSpell(1223031)) or (IsSpellKnown and IsSpellKnown(1223031))) then
            rank = 2
        end
        if rank and rank > 0 then
            FC.improvedStormstrikeRank = rank
            if charData then charData.improvedStormstrikeRank = rank end
        end
    end

    local finalRank = rank or 0
    if finalRank >= 2 then
        -- Rank 2/2: 100% deterministic reset!
        FC.activeCooldowns["stormstrike"] = nil
        FC.needsCooldownRefresh = true
        pcall(function() FC:UpdateCooldowns() end)
    elseif finalRank == 1 then
        -- Rank 1/2: 50% chance, verify on server SPELL_UPDATE_COOLDOWN
        FC.pendingStormstrikeCheck = GetTime()
    end
end

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, ...)
    if event == "ADDON_LOADED" then
        if arg1 == "ForeverClasses" then
            FC:InitDB()
            FC:CreateHUD()
            if FC.CreateMinimapButton then
                pcall(FC.CreateMinimapButton, FC)
            end
            if FC.AttachEssentialCooldowns then
                pcall(FC.AttachEssentialCooldowns, FC)
            end
        elseif arg1 == "Blizzard_CooldownViewer" then
            if FC.AttachEssentialCooldowns then
                pcall(FC.AttachEssentialCooldowns, FC)
            end
        end
    elseif event == "PLAYER_LOGIN" then
        FC.playerCharKey = nil
        FC.playerGUID = UnitGUID and UnitGUID("player")
        FC.improvedSliceAndDiceMult = nil
        FC.improvedSliceAndDiceRank = nil
        FC.improvedSliceAndDiceSource = nil
        if not FC.Frame then
            FC:InitDB()
            FC:CreateHUD()
        end
        if FC.LoadCharacterCooldowns then pcall(FC.LoadCharacterCooldowns, FC) end
        if FC.SanitizeCooldownSlots then pcall(FC.SanitizeCooldownSlots, FC) end
        if FC.UpdateTalentCache then pcall(FC.UpdateTalentCache, FC) end
        if FC.CheckStealthStateChange then pcall(FC.CheckStealthStateChange, FC) end
        pcall(GetPlayerBuffs)
        FC:UpdatePowerType()
        FC:UpdateHealth()
        FC:UpdatePower()
        pcall(function() FC:UpdateComboPoints() end)
        pcall(function() FC:UpdateTotems() end)
        pcall(function() FC:UpdatePoisonTracker() end)
        pcall(function() FC:UpdateDebuffs() end)
        pcall(function() FC:UpdateCooldowns() end)
        if FC.CreateMinimapButton then
            pcall(FC.CreateMinimapButton, FC)
        end
        if FC.AttachEssentialCooldowns then
            pcall(FC.AttachEssentialCooldowns, FC)
        end
        local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("ForeverClasses", "Version"))
            or (GetAddOnMetadata and GetAddOnMetadata("ForeverClasses", "Version"))
            or "1.0.3"
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[ForeverClasses (Beta-Test)]|r v%s Loaded. Type |cff00ff00/fc|r or click the Minimap icon for settings.", ver))
    elseif event == "PLAYER_ENTERING_WORLD" then
        FC.playerCharKey = nil
        FC.playerGUID = UnitGUID and UnitGUID("player")
        FC.improvedSliceAndDiceMult = nil
        FC.improvedSliceAndDiceRank = nil
        FC.improvedSliceAndDiceSource = nil
        FC.buffsDirty = true
        if not FC.Frame then
            FC:InitDB()
            FC:CreateHUD()
        end
        if FC.LoadCharacterCooldowns then pcall(FC.LoadCharacterCooldowns, FC) end
        if FC.SanitizeCooldownSlots then pcall(FC.SanitizeCooldownSlots, FC) end
        if FC.UpdateTalentCache then pcall(FC.UpdateTalentCache, FC) end
        if FC.CheckStealthStateChange then pcall(FC.CheckStealthStateChange, FC) end
        pcall(GetPlayerBuffs)
        FC:UpdatePowerType()
        FC:UpdateHealth()
        FC:UpdatePower()
        pcall(function() FC:UpdateComboPoints() end)
        pcall(function() FC:UpdateTotems() end)
        pcall(function() FC:UpdatePoisonTracker() end)
        pcall(function() FC:UpdateDebuffs() end)
        pcall(function() FC:UpdateCooldowns() end)
        if FC.CreateMinimapButton then
            pcall(FC.CreateMinimapButton, FC)
        end
        if FC.AttachEssentialCooldowns then
            pcall(FC.AttachEssentialCooldowns, FC)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                if FC.CheckMissingPoisonReminder then pcall(FC.CheckMissingPoisonReminder, FC, "Entered World") end
            end)
        end
        collectgarbage("collect")
    elseif event == "PLAYER_LOGOUT" then
        if FC.SyncActiveCharSettings then
            pcall(FC.SyncActiveCharSettings, FC)
        end
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        if FC.AttachEssentialCooldowns then
            pcall(FC.AttachEssentialCooldowns, FC)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if FC.HideFlyout then FC:HideFlyout() end
        if FC.HidePoisonFlyout then FC:HidePoisonFlyout() end
        FC.inCombat = true
        FC.previousComboPoints = 0
        FC.needsCooldownRefresh = true
        FC.buffsDirty = true
        FC:LogShield("COMBAT", "ENTER (PLAYER_REGEN_DISABLED)")
        if FC.Frame then FC.Frame:SetAlpha(1.0) end
        if FC.RequestFadeCheck then FC:RequestFadeCheck() end

        FC:UpdateHealth()
        pcall(function() FC:UpdateComboPoints() end)
        pcall(function() FC:UpdateDebuffs() end)
        pcall(function() FC:UpdateCooldowns() end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        FC.inCombat = false
        FC.previousComboPoints = 0
        FC.comboPointsBeforeFinisher = 0
        FC.needsCooldownRefresh = true
        FC.buffsDirty = true
        FC:LogShield("COMBAT", "LEAVE (PLAYER_REGEN_ENABLED)")
        if FC.RequestFadeCheck then FC:RequestFadeCheck() end

        FC:UpdateHealth()
        pcall(function() FC:UpdateComboPoints() end)
        pcall(function() FC:UpdateDebuffs() end)
        if FC.SanitizeCooldownSlots then pcall(FC.SanitizeCooldownSlots, FC) end
        pcall(function() FC:UpdateCooldowns() end)
        pcall(function() FC:UpdateTotems() end)
        pcall(function() FC:UpdatePoisonTracker() end)
        if FC.CheckMissingPoisonReminder then pcall(FC.CheckMissingPoisonReminder, FC, "Exited Combat") end
        if FC.AttachEssentialCooldowns then
            pcall(FC.AttachEssentialCooldowns, FC)
        end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" or arg1 == nil then
            if FC.UpdatePoisonTracker then pcall(FC.UpdatePoisonTracker, FC) end
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if FC.OnBagUpdateDelayed then pcall(FC.OnBagUpdateDelayed, FC) end
    elseif event == "READY_CHECK" then
        if FC.CheckMissingPoisonReminder then pcall(FC.CheckMissingPoisonReminder, FC, "Ready Check") end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "UNIT_COMBO_POINTS" then
        if event == "PLAYER_TARGET_CHANGED" then
            FC.previousComboPoints = 0
            FC.needsCooldownRefresh = true
            if UnitExists and UnitExists("target") and FC.Frame then
                FC.Frame:SetAlpha(1.0)
            end
            if FC.RequestFadeCheck then FC:RequestFadeCheck() end
            pcall(function() FC:UpdateCooldowns() end)
        end
        pcall(function() FC:UpdateComboPoints() end)
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
        if arg1 == "player" or arg1 == nil then
            FC.lastAbsorbEventTime = GetTime()
            local rawAbs = nil
            local isSec = false
            if UnitGetTotalAbsorbs then
                local ok, abs = pcall(UnitGetTotalAbsorbs, "player")
                if ok and abs ~= nil then
                    isSec = IsSecret(abs)
                    if not isSec and type(abs) == "number" then
                        rawAbs = abs
                        FC.currentShieldRemaining = abs
                        FC.hasActiveShield = (abs > 0)
                    else
                        FC.hasActiveShield = true
                    end
                end
            end
            FC:Log("ABSORB_EVT", "%s unit=%s abs=%s isSec=%s rem=%s hasShield=%s",
                tostring(event), tostring(arg1), tostring(rawAbs), tostring(isSec),
                tostring(FC.currentShieldRemaining), tostring(FC.hasActiveShield))
            FC:UpdateHealth()
            if FC.RequestFadeCheck then FC:RequestFadeCheck() end
        end
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_HEALTH_FREQUENT" then
        if arg1 == "player" or arg1 == nil then
            FC:UpdateHealth()
            if FC.RequestFadeCheck then FC:RequestFadeCheck() end
        end
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        FC.buffsDirty = true
        if event == "PLAYER_DEAD" then
            FC.comboPointsBeforeFinisher = 0
            FC.isStealthed = false
            FC.isShadowmelded = false
            FC.shadowmeldCastTime = nil
            if FC.activeBuffs then
                table.wipe(FC.activeBuffs)
            end
            if FC.combatDebuffs then
                table.wipe(FC.combatDebuffs)
            end
        end
        FC:UpdateHealth()
        pcall(function() FC:UpdateDebuffs() end)
        pcall(function() FC:UpdateCooldowns() end)
    elseif event == "UNIT_COMBAT" or event == "COMBAT_TEXT_UPDATE" then
        local isPlayerEvent = false
        local isAbsorb = false
        local numAbsorbAmount = 0
        local isSecretAbsorb = false

        if event == "UNIT_COMBAT" then
            if arg1 == "player" then
                isPlayerEvent = true
                FC.lastCombatDamageTime = GetTime()
                local a2 = (arg2 and not IsSecret(arg2)) and string.upper(tostring(arg2)) or ""
                local a3 = (arg3 and not IsSecret(arg3)) and string.upper(tostring(arg3)) or ""
                local a4 = (arg4 and not IsSecret(arg4)) and tostring(arg4) or (IsSecret(arg4) and "<secret number>" or "")
                local a5 = (arg5 and not IsSecret(arg5)) and tostring(arg5) or ""
                FC:LogShield("UNIT_COMBAT", "a2=%s a3=%s a4=%s a5=%s rem=%s", a2, a3, a4, a5, tostring(FC.currentShieldRemaining))

                if a2 == "ABSORB" or a3 == "ABSORB" or a2:find("ABSORB") or a3:find("ABSORB") then
                    isAbsorb = true
                    FC.lastAbsorbEventTime = GetTime()
                    FC.hasActiveShield = true
                    local rawAmt = (arg4 ~= nil and arg4) or arg3
                    if IsSecret(rawAmt) then
                        isSecretAbsorb = true
                        numAbsorbAmount = 0
                    else
                        local n = tonumber(rawAmt)
                        if n and not IsSecret(n) then
                            numAbsorbAmount = n
                        else
                            numAbsorbAmount = 0
                        end
                    end
                elseif a2 == "DODGE" or a2 == "PARRY" then
                    HandleStormstrikeDodgeOrParry()
                end
            end
        else -- COMBAT_TEXT_UPDATE
            isPlayerEvent = true
            local a1 = (arg1 and not IsSecret(arg1)) and string.upper(tostring(arg1)) or ""
            local a2 = (arg2 and not IsSecret(arg2)) and tostring(arg2) or (IsSecret(arg2) and "<secret number>" or "")
            FC:LogShield("COMBAT_TEXT", "a1=%s a2=%s rem=%s", a1, a2, tostring(FC.currentShieldRemaining))

            if a1 == "ABSORB_ADDED" then
                FC.hasActiveShield = true
                FC.lastAbsorbEventTime = GetTime()
                FC:UpdateHealth()
            elseif a1 == "ABSORB" or a1:find("ABSORB") then
                isAbsorb = true
                FC.lastAbsorbEventTime = GetTime()
                FC.hasActiveShield = true
                if IsSecret(arg2) then
                    isSecretAbsorb = true
                    numAbsorbAmount = 0
                else
                    local n = tonumber(arg2)
                    if n and not IsSecret(n) then
                        numAbsorbAmount = n
                    else
                        numAbsorbAmount = 0
                    end
                end
            elseif a1 == "DAMAGE" or a1:find("DAMAGE") then
                FC.lastCombatDamageTime = GetTime()
            elseif a1 == "SPELL_AURA_END" then
                local now = GetTime()
                local hasShield = (FC.hasActiveShield and FC.currentShieldSpell ~= nil)
                local shieldSpell = FC.currentShieldSpell

                -- SPELL_AURA_END from Floating Combat Text is ONLY used to detect if an active absorb shield broke or expired.
                -- It MUST NEVER touch non-shield buffs (Paladin Seals, Blessings, Auras, etc.) because anonymous SPELL_AURA_END
                -- fires for arbitrary procs, mob buffs, and combat events.
                if hasShield then
                    local shieldExpiredNaturally = false
                    if FC.activeBuffs and FC.activeBuffs[shieldSpell] then
                        local sData = FC.activeBuffs[shieldSpell]
                        if sData and sData.expires and not IsSecret(sData.expires) and sData.expires > 0 and (now >= sData.expires - 0.75) then
                            shieldExpiredNaturally = true
                        end
                    end

                    if shieldExpiredNaturally then
                        FC:Log("SHIELD_EXPIRED", "Shield %s naturally expired at %s", tostring(shieldSpell), tostring(now))
                        FC.hasActiveShield = false
                        FC.currentShieldRemaining = 0
                        if FC.activeBuffs and FC.activeBuffs[shieldSpell] then
                            FC.activeBuffs[shieldSpell] = nil
                            FC.needsCooldownRefresh = true
                        end
                        FC.currentShieldSpell = nil
                        FC:UpdateHealth()
                        pcall(function() FC:UpdateCooldowns() end)
                    else
                        local isRecentDamageOrAbsorb = ((now - (FC.lastCombatDamageTime or 0)) < 0.15)
                            or ((now - (FC.lastAbsorbEventTime or 0)) < 0.15)
                            or (isAbsorb == true)
                        if isRecentDamageOrAbsorb then
                            FC:Log("SHIELD_BROKE", "Combat damage broke shield %s! Ended at %s.", tostring(shieldSpell), tostring(now))
                            FC.hasActiveShield = false
                            FC.currentShieldRemaining = 0
                            if FC.activeBuffs and FC.activeBuffs[shieldSpell] then
                                FC.activeBuffs[shieldSpell] = nil
                                FC.needsCooldownRefresh = true
                            end
                            FC.currentShieldSpell = nil
                            FC:UpdateHealth()
                            pcall(function() FC:UpdateCooldowns() end)
                        end
                    end
                end
            elseif a1 == "SPELL_AURA_END_HARMFUL" then
                FC.lastHarmfulAuraEndTime = GetTime()
                FC:Log("DEBUFF_END", "Harmful aura ended (shield unaffected)")
            end
        end

        if isPlayerEvent and isAbsorb then
            local now = GetTime()
            FC.lastAbsorbTime = now
            FC.lastAbsorbEventTime = now
            FC.hasActiveShield = true

            local amtDisplay = isSecretAbsorb and "<secret number>" or tostring(numAbsorbAmount)
            FC:LogShield("ABSORB_PROC", "amt=%s isSec=%s remBefore=%s", amtDisplay, tostring(isSecretAbsorb), tostring(FC.currentShieldRemaining))

            -- In Midnight 12.0: If the absorb amount is a secret number, we CANNOT and MUST NOT perform Lua arithmetic or comparisons.
            -- Instead, the C++ StatusBar (FC.AbsorbBar) automatically reads and renders the updated absorb from the engine via FC:UpdateHealth().
            -- Only if both the absorb amount and currentShieldRemaining are known, non-secret plain Lua numbers do we decrement in Lua:
            local canDoLuaMath = (not isSecretAbsorb)
                and (numAbsorbAmount > 0)
                and (FC.currentShieldRemaining ~= nil)
                and (not IsSecret(FC.currentShieldRemaining))
                and (type(FC.currentShieldRemaining) == "number")
                and (FC.currentShieldRemaining > 0)

            if canDoLuaMath then
                FC.lastAbsorbAmount = numAbsorbAmount
                FC.currentShieldRemaining = math.max(0, FC.currentShieldRemaining - numAbsorbAmount)
                FC:LogShield("ABSORB_AFTER", "remAfter=%s", tostring(FC.currentShieldRemaining))
                if FC.currentShieldRemaining <= 0 then
                    FC:LogShield("SHIELD_BROKE", "Depleted by absorb hit! Clearing buff: %s", tostring(FC.currentShieldSpell))
                    FC.hasActiveShield = false
                    if FC.currentShieldSpell and FC.activeBuffs and FC.activeBuffs[FC.currentShieldSpell] then
                        FC.activeBuffs[FC.currentShieldSpell] = nil
                        FC.needsCooldownRefresh = true
                    end
                    FC.currentShieldSpell = nil
                end
                pcall(function() FC:UpdateCooldowns() end)
            end

            -- Always update health so the C++ widget queries the engine and refreshes the absorb bar immediately!
            FC:UpdateHealth()
        end
    elseif event == "UNIT_AURA" then
        if arg1 == "player" or arg1 == nil then
            FC.buffsDirty = true
            local updateInfo = arg2
            local changed = false

            -- Out of combat: Sync full native buff cache immediately (0 taint)
            if not (InCombatLockdown and InCombatLockdown()) and not (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) then
                pcall(GetPlayerBuffs)
            end

            -- 1. Process incremental updateInfo if provided by the engine
            if updateInfo and type(updateInfo) == "table" then
                FC.auraInstanceToBuff = FC.auraInstanceToBuff or {}
                FC.buffToAuraInstance = FC.buffToAuraInstance or {}
                local now = GetTime()

                local isSecAdded = IsSecret(updateInfo.addedAuras)
                local isSecUpdated = IsSecret(updateInfo.updatedAuraInstanceIDs)
                local isSecRemoved = IsSecret(updateInfo.removedAuraInstanceIDs)
                local isSecFull = IsSecret(updateInfo.isFullUpdate)

                local numAdded = (updateInfo.addedAuras and not isSecAdded) and #updateInfo.addedAuras or (isSecAdded and -1 or 0)
                local numUpdated = (updateInfo.updatedAuraInstanceIDs and not isSecUpdated) and #updateInfo.updatedAuraInstanceIDs or (isSecUpdated and -1 or 0)
                local numRemoved = (updateInfo.removedAuraInstanceIDs and not isSecRemoved) and #updateInfo.removedAuraInstanceIDs or (isSecRemoved and -1 or 0)
                local isFull = (not isSecFull and updateInfo.isFullUpdate == true) and "true" or (isSecFull and "secret" or "false")

                FC:LogShield("UNIT_AURA", "adds=%d upds=%d rems=%d isFull=%s secRem=%s",
                    numAdded, numUpdated, numRemoved, isFull, tostring(isSecRemoved))

                -- A. Added Auras (Map new buffs and their instance IDs)
                if updateInfo.addedAuras then
                    if not IsSecret(updateInfo.addedAuras) then
                        for _, aura in ipairs(updateInfo.addedAuras) do
                            local aName = aura and aura.name
                            if (not aName or IsSecret(aName)) and aura and aura.spellId and not IsSecret(aura.spellId) and C_Spell and C_Spell.GetSpellInfo then
                                local ok, sInfo = pcall(C_Spell.GetSpellInfo, aura.spellId)
                                if ok and sInfo and sInfo.name and not IsSecret(sInfo.name) then
                                    aName = sInfo.name
                                end
                            end
                            if aName and not IsSecret(aName) then
                                local clean = string.lower((strtrim and strtrim(aName)) or aName)
                                local instID = aura.auraInstanceID
                                if instID then
                                    FC.auraInstanceToBuff[instID] = clean
                                    FC.buffToAuraInstance[clean] = instID
                                end

                                local app = aura.applications
                                local st = (app and not IsSecret(app) and app > 0) and app or (DEFAULT_BUFF_STACKS and DEFAULT_BUFF_STACKS[clean])
                                local dur = (aura.duration and not IsSecret(aura.duration)) and aura.duration or 0
                                local exp = (aura.expirationTime and not IsSecret(aura.expirationTime)) and aura.expirationTime or 0

                                local pts = nil
                                if aura and aura.points then
                                    if type(aura.points) == "table" and aura.points[1] and not IsSecret(aura.points[1]) then
                                        pts = tonumber(aura.points[1])
                                    elseif type(aura.points) == "number" and not IsSecret(aura.points) then
                                        pts = tonumber(aura.points)
                                    end
                                end

                                FC:Log("AURA_ADD", "clean=%s sID=%s instID=%s dur=%s exp=%s pts=%s",
                                    tostring(clean), tostring(aura.spellId), tostring(instID),
                                    tostring(dur), tostring(exp), tostring(pts))

                                if (dur and dur > 0 and exp and exp > 0) then
                                    FC.activeBuffs = FC.activeBuffs or {}
                                    FC.activeBuffs[clean] = {
                                        start = (exp > dur) and (exp - dur) or now,
                                        duration = dur,
                                        expires = exp,
                                        stacks = st,
                                        instanceID = instID,
                                        lastStackDecrement = 0,
                                    }
                                    changed = true
                                    FC:Log("BUFF_SET", "clean=%s dur=%.1f exp=%.1f instID=%s", clean, dur, exp, tostring(instID))
                                elseif FC.activeBuffs and FC.activeBuffs[clean] and (FC.activeBuffs[clean].duration or 0) > 0 and FC.activeBuffs[clean].expires and FC.activeBuffs[clean].expires > now then
                                    -- Keep existing active duration and link instID (do not wipe known duration with 0)
                                    local existing = FC.activeBuffs[clean]
                                    existing.instanceID = instID
                                    if st then existing.stacks = st end
                                    changed = true
                                    FC:Log("BUFF_LINK", "clean=%s preservedDur=%.1f rem=%.1f instID=%s", clean, existing.duration or 0, existing.expires - now, tostring(instID))
                                else
                                    local knownDur = FC:GetSpellBuffDuration(clean)
                                    FC.activeBuffs = FC.activeBuffs or {}
                                    if knownDur and knownDur > 0 then
                                        FC.activeBuffs[clean] = {
                                            start = now,
                                            duration = knownDur,
                                            expires = now + knownDur,
                                            stacks = st,
                                            instanceID = instID,
                                            lastStackDecrement = 0,
                                        }
                                        changed = true
                                        FC:Log("BUFF_RESOLVED", "clean=%s knownDur=%.1f instID=%s", clean, knownDur, tostring(instID))
                                    else
                                        FC.activeBuffs[clean] = {
                                            start = now,
                                            duration = 0,
                                            expires = now + 999999,
                                            stacks = st,
                                            instanceID = instID,
                                            lastStackDecrement = 0,
                                        }
                                        changed = true
                                        FC:Log("BUFF_INDEFINITE", "clean=%s instID=%s", clean, tostring(instID))
                                    end
                                end

                                if IsShieldSpell(clean) then
                                    FC.currentShieldSpell = clean
                                    if not FC.currentShieldRemaining or (not IsSecret(FC.currentShieldRemaining) and FC.currentShieldRemaining <= 0) then
                                        local sID = (aura and aura.spellId and not IsSecret(aura.spellId) and aura.spellId > 0) and aura.spellId or 17
                                        local maxVal = (pts and not IsSecret(pts) and pts > 0) and pts or FC:ResolveShieldMaxAmount(sID, clean)
                                        FC.currentShieldRemaining = maxVal
                                        FC.currentShieldMax = maxVal
                                        FC.hasActiveShield = true
                                        changed = true
                                        FC:LogShield("SHIELD_SET_BY_AURA", "clean=%s rem=%s", clean, tostring(maxVal))
                                    end
                                end
                            else
                                FC:LogShield("AURA_ADD_SECRET_OR_NIL", "sID=%s instID=%s",
                                    tostring(aura and aura.spellId), tostring(aura and aura.auraInstanceID))
                            end
                        end
                    else
                        FC:LogShield("AURA_ADD_SECRET", "addedAuras table is secret")
                    end
                end

                -- B. Updated Aura Instance IDs (Stack/charge count changes)
                if updateInfo.updatedAuraInstanceIDs then
                    if not IsSecret(updateInfo.updatedAuraInstanceIDs) then
                        for _, instID in ipairs(updateInfo.updatedAuraInstanceIDs) do
                            local clean = FC.auraInstanceToBuff[instID]
                            if not clean and FC.activeBuffs then
                                for k, v in pairs(FC.activeBuffs) do
                                    if v and v.instanceID == instID then
                                        clean = k
                                        FC.auraInstanceToBuff[instID] = clean
                                        break
                                    end
                                end
                            end

                            if clean and FC.activeBuffs and FC.activeBuffs[clean] then
                                local updatedStacks = nil
                                if not (InCombatLockdown and InCombatLockdown()) and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
                                    local ok, aData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instID)
                                    if ok and aData and aData.applications and not IsSecret(aData.applications) then
                                        updatedStacks = aData.applications
                                    end
                                end

                                FC:LogShield("AURA_UPD", "instID=%s clean=%s st=%s", tostring(instID), tostring(clean), tostring(updatedStacks))

                                if updatedStacks ~= nil then
                                    if updatedStacks > 0 then
                                        FC.activeBuffs[clean].stacks = updatedStacks
                                        FC.activeBuffs[clean].lastStackDecrement = now
                                    else
                                        FC.activeBuffs[clean] = nil
                                    end
                                    changed = true
                                else
                                    local buffData = FC.activeBuffs[clean]
                                    local lastDec = buffData.lastStackDecrement or 0
                                    local icd = (DEFAULT_BUFF_ICD and DEFAULT_BUFF_ICD[clean]) or 0.5
                                    if (now - lastDec) >= icd then
                                        buffData.lastStackDecrement = now
                                        local cur = buffData.stacks or (DEFAULT_BUFF_STACKS and DEFAULT_BUFF_STACKS[clean]) or 3
                                        cur = cur - 1
                                        if cur > 0 then
                                            buffData.stacks = cur
                                        else
                                            FC.activeBuffs[clean] = nil
                                        end
                                        changed = true
                                    end
                                end
                            end
                        end
                    else
                        FC:LogShield("AURA_UPD_SECRET", "updatedAuraInstanceIDs table is secret")
                        -- In Secret / Combat Lockdown Context:
                        -- An aura charge was consumed on the player! Decrement active charge-based buffs
                        -- Debounce with buff-specific ICD (e.g. 3.5s for Lightning Shield) so rapid hits do NOT consume orbs prematurely.
                        if FC.activeBuffs then
                            for clean, buffData in pairs(FC.activeBuffs) do
                                if DEFAULT_BUFF_STACKS and DEFAULT_BUFF_STACKS[clean] then
                                    local lastDec = buffData.lastStackDecrement or 0
                                    local icd = (DEFAULT_BUFF_ICD and DEFAULT_BUFF_ICD[clean]) or 0.5
                                    if (now - lastDec) >= icd then
                                        buffData.lastStackDecrement = now
                                        local cur = buffData.stacks or DEFAULT_BUFF_STACKS[clean] or 3
                                        cur = cur - 1
                                        if cur > 0 then
                                            buffData.stacks = cur
                                        else
                                            FC.activeBuffs[clean] = nil
                                        end
                                        changed = true
                                    end
                                end
                            end
                        end
                    end
                end

                -- C. Removed Aura Instance IDs (Aura dropped / faded / dispelled)
                if updateInfo.removedAuraInstanceIDs then
                    if not IsSecret(updateInfo.removedAuraInstanceIDs) then
                        for _, instID in ipairs(updateInfo.removedAuraInstanceIDs) do
                            local clean = FC.auraInstanceToBuff[instID]
                            if not clean and FC.activeBuffs then
                                for k, v in pairs(FC.activeBuffs) do
                                    if v and v.instanceID == instID then
                                        clean = k
                                        break
                                    end
                                end
                            end

                            FC:LogShield("AURA_REM", "instID=%s mappedClean=%s curShield=%s inActiveBuffs=%s",
                                tostring(instID), tostring(clean), tostring(FC.currentShieldSpell),
                                tostring(FC.activeBuffs and clean and FC.activeBuffs[clean] ~= nil))

                            if clean then
                                if FC.activeBuffs and FC.activeBuffs[clean] then
                                    FC:Log("BUFF_REM", "clean=%s removed (instID=%s)", clean, tostring(instID))
                                    FC.activeBuffs[clean] = nil
                                    changed = true
                                end
                                if FC.combatDebuffs and FC.combatDebuffs[clean] then
                                    FC.combatDebuffs[clean] = nil
                                    changed = true
                                end
                                if IsShieldSpell(clean) or clean == FC.currentShieldSpell then
                                    FC:LogShield("SHIELD_CLEARED_BY_AURA_REM", "clean=%s dropped", tostring(clean))
                                    FC.currentShieldRemaining = 0
                                    FC.currentShieldSpell = nil
                                    FC.hasActiveShield = false
                                    changed = true
                                end
                                FC.auraInstanceToBuff[instID] = nil
                                FC.buffToAuraInstance[clean] = nil
                            end
                        end
                    else
                        local buffKeys = {}
                        if FC.activeBuffs then
                            for k in pairs(FC.activeBuffs) do table.insert(buffKeys, k) end
                        end
                        FC:LogShield("AURA_REM_SECRET", "hasShield=%s curShield=%s activeBuffs=[%s]",
                            tostring(FC.hasActiveShield), tostring(FC.currentShieldSpell), table.concat(buffKeys, ", "))

                        -- In Secret / Combat Lockdown Context:
                        -- An aura was removed from the player in secret context.
                        -- Note: We do NOT break absorb shields here because secret aura removals fire
                        -- for harmless expiring debuffs (Weakened Soul, enemy dots, daze, etc.).
                        -- Shield breaks are cleanly handled by SPELL_AURA_END in COMBAT_TEXT_UPDATE.
                        if FC.activeBuffs then
                            for clean, buffData in pairs(FC.activeBuffs) do
                                if DEFAULT_BUFF_STACKS and DEFAULT_BUFF_STACKS[clean] then
                                    local cur = buffData.stacks or 1
                                    local isExpired = buffData.expires and (now >= buffData.expires)
                                    if isExpired or cur <= 1 then
                                        local lastDec = buffData.lastStackDecrement or 0
                                        local icd = (DEFAULT_BUFF_ICD and DEFAULT_BUFF_ICD[clean]) or 0.5
                                        if isExpired or (now - lastDec) >= icd then
                                            FC.activeBuffs[clean] = nil
                                            changed = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            else
                FC:LogShield("UNIT_AURA", "no updateInfo table")
            end

            -- 2. Direct instance ID verification for all activeBuffs (Out of combat only to prevent taint)
            if not (InCombatLockdown and InCombatLockdown()) and FC.activeBuffs and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
                for cleanName, buffData in pairs(FC.activeBuffs) do
                    if buffData and buffData.instanceID then
                        local ok, aData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", buffData.instanceID)
                        if ok and not aData then
                            FC.activeBuffs[cleanName] = nil
                            changed = true
                        elseif ok and aData and aData.applications and not IsSecret(aData.applications) then
                            if buffData.stacks ~= aData.applications then
                                buffData.stacks = aData.applications
                                changed = true
                            end
                        end
                    end
                end
            end

            if changed then
                FC.needsCooldownRefresh = true
            end

            if FC.CheckStealthStateChange then pcall(FC.CheckStealthStateChange, FC) end
            pcall(function() FC:UpdateDebuffs() end)
            pcall(function() FC:UpdateCooldowns() end)
            pcall(function() FC:UpdateHealth() end)
        end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_POWER_FREQUENT" then
        if arg1 == "player" then
            FC:UpdatePower()
            pcall(function() FC:UpdateComboPoints() end)
            pcall(function() FC:UpdateCooldowns() end)
            if FC.RequestFadeCheck then FC:RequestFadeCheck() end
        end
    elseif event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM" then
        if FC.CheckStealthStateChange then pcall(FC.CheckStealthStateChange, FC) end
        FC:UpdatePowerType()
        FC:UpdatePower()
        pcall(function() FC:UpdateComboPoints() end)
        if FC.RequestFadeCheck then FC:RequestFadeCheck() end
    elseif event == "ACTIONBAR_SLOT_CHANGED"
        or event == "ACTIONBAR_PAGE_CHANGED"
        or event == "UPDATE_BONUS_ACTION_BAR"
        or event == "UPDATE_VEHICLE_ACTION_BAR"
        or event == "ACTIONBAR_UPDATE_STATE" then
        if FC.UpdateActionSlotCache then pcall(FC.UpdateActionSlotCache, FC) end
        pcall(function() FC:UpdateCooldowns() end)
    elseif event == "SPELL_UPDATE_COOLDOWN"
        or event == "SPELL_UPDATE_CHARGES"
        or event == "SPELL_UPDATE_USABLE"
        or event == "ACTIONBAR_UPDATE_USABLE"
        or event == "ACTIONBAR_UPDATE_COOLDOWN"
        or event == "BAG_UPDATE_COOLDOWN"
        or event == "SPELLS_CHANGED"
        or event == "LEARNED_SPELL_IN_TAB"
        or event == "CHARACTER_POINTS_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "TRAIT_NODE_CHANGED"
        or event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
        if FC.CheckStealthStateChange then pcall(FC.CheckStealthStateChange, FC) end
        FC.needsCooldownRefresh = true
        if FC.pendingStormstrikeCheck and (GetTime() - FC.pendingStormstrikeCheck) <= 0.4 then
            FC.pendingStormstrikeCheck = nil
            if FC.activeCooldowns and FC.activeCooldowns["stormstrike"] then
                FC.activeCooldowns["stormstrike"] = nil
            end
        end
        if (event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" or event == "TRAIT_NODE_CHANGED" or event == "ACTIVE_COMBAT_CONFIG_CHANGED") then
            if FC.UpdateTalentCache then pcall(FC.UpdateTalentCache, FC) end
            local charData = FC.GetCharData and FC:GetCharData()
            if charData and not charData.cooldownDefaultsPopulated and FC.PopulateDefaultCooldowns then
                pcall(FC.PopulateDefaultCooldowns, FC)
            end
            if FC.SanitizeCooldownSlots then
                pcall(FC.SanitizeCooldownSlots, FC)
            end
        end
        pcall(function() FC:UpdateCooldowns() end)
    elseif event == "PLAYER_TOTEM_UPDATE" then
        FC.needsCooldownRefresh = true
        pcall(function() FC:UpdateCooldowns() end)
        pcall(function() FC:UpdateTotems() end)
    elseif event == "UNIT_HEAL_PREDICTION" 
        or event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_DELAYED"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        if arg1 == "player" then
            FC:UpdateHealth()
            if FC.RequestFadeCheck then FC:RequestFadeCheck() end

            if event == "UNIT_SPELLCAST_START" then
                if FC.isShadowmelded then
                    FC.isShadowmelded = false
                    FC.wasShadowmelded = false
                    local now = GetTime()
                    local smK = FC.shadowmeldKey or "shadowmeld"
                    FC.activeCooldowns = FC.activeCooldowns or {}
                    FC.activeCooldowns["shadowmeld"] = { start = now, duration = 10 }
                    FC.activeCooldowns["shadowmelded"] = { start = now, duration = 10 }
                    FC.activeCooldowns[smK] = { start = now, duration = 10 }
                end
                local castSpellName = type(arg2) == "string" and arg2 or nil
                local castSpellID = arg3
                if not castSpellName and castSpellID and C_Spell and C_Spell.GetSpellInfo then
                    local ok, sInfo = pcall(C_Spell.GetSpellInfo, castSpellID)
                    if ok and sInfo and sInfo.name then castSpellName = sInfo.name end
                end
                FC:TriggerGCD(castSpellName)
                FC.needsCooldownRefresh = true
                pcall(function() FC:UpdateCooldowns() end)

            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                if FC.CheckStealthStateChange then pcall(FC.CheckStealthStateChange, FC) end
                local castSpellID = (type(arg3) == "number" and arg3) or (type(arg2) == "number" and arg2)
                local castSpellName = nil
                if castSpellID and C_Spell and C_Spell.GetSpellInfo then
                    local ok, sInfo = pcall(C_Spell.GetSpellInfo, castSpellID)
                    if ok and sInfo and sInfo.name then castSpellName = sInfo.name end
                end
                if not castSpellName and castSpellID and GetSpellInfo then
                    local ok, n = pcall(GetSpellInfo, castSpellID)
                    if ok and n then castSpellName = n end
                end
                if not castSpellName and type(arg2) == "string" and not arg2:find("^Cast%-") then
                    castSpellName = arg2
                end

                FC:TriggerGCD(castSpellName)

                if castSpellName then
                    local clean = string.lower((strtrim and strtrim(castSpellName)) or castSpellName)
                    local dur = FC:GetSpellCooldownDuration(castSpellID, clean)
                    local now = GetTime()
                    local inC = (InCombatLockdown and InCombatLockdown()) and true or false

                    FC:Log("CAST", "spell=%s id=%s cdDur=%s inCombat=%s", tostring(clean), tostring(castSpellID), tostring(dur), tostring(inC))

                    FC.activeCooldowns = FC.activeCooldowns or {}

                    if FC.isShadowmelded and clean ~= "shadowmeld" and clean ~= "shadowmelded" and clean ~= (FC.shadowmeldKey or "shadowmeld") then
                        FC.isShadowmelded = false
                        FC.wasShadowmelded = false
                        local smK = FC.shadowmeldKey or "shadowmeld"
                        FC.activeCooldowns["shadowmeld"] = { start = now, duration = 10 }
                        FC.activeCooldowns["shadowmelded"] = { start = now, duration = 10 }
                        FC.activeCooldowns[smK] = { start = now, duration = 10 }
                        FC.needsCooldownRefresh = true
                    end

                    if clean == "totemic recall" then
                        for k in pairs(FC.activeCooldowns) do
                            if k:find("totem") and not (k:find("grounding") or k:find("earthbind") or k:find("stoneclaw") or k:find("mana tide")) then
                                FC.activeCooldowns[k] = nil
                            end
                        end
                        FC.activeTotemSlots = {}
                        FC.totemPositions = {}
                    elseif clean:find("totem") then
                        local sClean = CleanTotemName(clean)
                        local slot = TOTEM_SPELL_SLOTS[sClean]
                        if not slot then
                            for name, s in pairs(TOTEM_SPELL_SLOTS) do
                                if sClean:find(name, 1, true) or name:find(sClean, 1, true) then
                                    slot = s
                                    break
                                end
                            end
                        end
                        if not slot then
                            if sClean:find("fire") or sClean:find("flame") or sClean:find("searing") or sClean:find("magma") then
                                slot = 1
                            elseif sClean:find("earth") or sClean:find("stone") or sClean:find("tremor") then
                                slot = 2
                            elseif sClean:find("water") or sClean:find("healing") or sClean:find("mana") or sClean:find("poison") or sClean:find("disease") then
                                slot = 3
                            elseif sClean:find("air") or sClean:find("wind") or sClean:find("grounding") or sClean:find("nature") or sClean:find("sentry") or sClean:find("wrath") then
                                slot = 4
                            end
                        end
                        if slot then
                            local totemDur = (FC.cachedTotemDurations and (FC.cachedTotemDurations[sClean] or FC.cachedTotemDurations[clean]))
                                or STANDARD_TOTEM_DURATIONS[sClean]
                                or 300
                            local icon = nil
                            if C_Spell and C_Spell.GetSpellTexture then
                                icon = C_Spell.GetSpellTexture(castSpellID)
                            elseif GetSpellTexture then
                                icon = GetSpellTexture(castSpellID)
                            end
                            FC.activeTotemSlots = FC.activeTotemSlots or {}
                            FC.activeTotemSlots[slot] = {
                                slot = slot,
                                name = castSpellName or clean,
                                startTime = now,
                                duration = totemDur,
                                icon = icon,
                            }
                            local curX, curY, contID = GetPlayerWorldCoordinates()
                            FC.totemPositions = FC.totemPositions or {}
                            if curX and curY and contID then
                                FC.totemPositions[slot] = {
                                    x = curX,
                                    y = curY,
                                    continentID = contID,
                                    startTime = now,
                                    name = castSpellName or clean,
                                }
                            else
                                FC.totemPositions[slot] = nil
                            end
                        end
                        if dur and dur > 1.5 then
                            FC.activeCooldowns[clean] = { start = now, duration = dur }
                            FC:Log("CD_START", "totem=%s dur=%.1f", clean, dur)
                            local baseClean = CleanTotemName(clean)
                            if baseClean and baseClean ~= clean then
                                FC.activeCooldowns[baseClean] = { start = now, duration = dur }
                            end
                        end
                    elseif clean == "earth shock" or clean == "flame shock" or clean == "frost shock" then
                        FC.activeCooldowns["earth shock"] = { start = now, duration = 6 }
                        FC.activeCooldowns["flame shock"] = { start = now, duration = 6 }
                        FC.activeCooldowns["frost shock"] = { start = now, duration = 6 }
                    elseif clean == "slice and dice" then
                        local cp = (FC.comboPointsBeforeFinisher and FC.comboPointsBeforeFinisher > 0 and FC.comboPointsBeforeFinisher)
                            or (FC.previousComboPoints and FC.previousComboPoints > 0 and FC.previousComboPoints)
                            or 1
                        if type(cp) ~= "number" or cp < 1 then cp = 1 end
                        if cp > 5 then cp = 5 end
                        local baseDur = 6 + (cp * 3)
                        local mult = FC.improvedSliceAndDiceMult or 1.0
                        if mult <= 1.0 then
                            local charData = FC.GetCharData and FC:GetCharData()
                            if charData and charData.improvedSliceAndDiceMult and charData.improvedSliceAndDiceMult > 1.0 then
                                mult = charData.improvedSliceAndDiceMult
                                FC.improvedSliceAndDiceMult = mult
                            end
                        end
                        local dur = baseDur * mult
                        FC.activeBuffs = FC.activeBuffs or {}
                        FC.activeBuffs["slice and dice"] = {
                            start = now,
                            duration = dur,
                            expires = now + dur,
                        }
                        FC.comboPointsBeforeFinisher = 0
                    elseif clean == "stealth" or clean == "prowl" then
                        FC.isStealthed = true
                        if FC.activeCooldowns then
                            FC.activeCooldowns[clean] = nil
                        end
                        FC.activeBuffs = FC.activeBuffs or {}
                        FC.activeBuffs[clean] = {
                            start = now,
                            duration = 0,
                            expires = now + 999999,
                        }
                        FC.needsCooldownRefresh = true
                    elseif clean == "shadowmeld" or clean == "shadowmelded" or clean == (FC.shadowmeldKey or "shadowmeld") then
                        FC.isShadowmelded = true
                        FC.wasShadowmelded = true
                        local smK = FC.shadowmeldKey or "shadowmeld"
                        if FC.activeCooldowns then
                            FC.activeCooldowns["shadowmeld"] = nil
                            FC.activeCooldowns["shadowmelded"] = nil
                            FC.activeCooldowns[smK] = nil
                        end
                        FC.needsCooldownRefresh = true
                    elseif dur and dur > 1.5 then
                        FC.activeCooldowns[clean] = { start = now, duration = dur }
                        FC:Log("CD_START", "spell=%s dur=%.1f", clean, dur)
                        local baseClean = CleanTotemName(clean)
                        if baseClean and baseClean ~= clean then
                            FC.activeCooldowns[baseClean] = { start = now, duration = dur }
                        end
                    end

                    -- Buff Tracking (Paladin Seals, self-buffs)
                    FC.activeBuffs = FC.activeBuffs or {}

                    local buffDur = FC:GetSpellBuffDuration(clean)
                    if buffDur and buffDur > 0 and clean ~= "slice and dice" then
                        local isSelfBuff = clean:find("^seal of ")
                        if not isSelfBuff then
                            local selfOnly = {
                                ["divine shield"] = true, ["divine protection"] = true, ["holy shield"] = true, ["righteous fury"] = true,
                                ["sprint"] = true, ["evasion"] = true, ["blade flurry"] = true, ["adrenaline rush"] = true, ["ghostly strike"] = true,
                                ["bloodrage"] = true, ["berserker rage"] = true, ["shield wall"] = true, ["retaliation"] = true,
                                ["recklessness"] = true, ["last stand"] = true, ["death wish"] = true, ["sweeping strikes"] = true, ["shield block"] = true,
                                ["lightning shield"] = true, ["water shield"] = true, ["earth shield"] = true, ["elemental mastery"] = true, ["nature's swiftness"] = true,
                                ["ice barrier"] = true, ["mana shield"] = true, ["ice block"] = true, ["arcane power"] = true, ["icy veins"] = true, ["combustion"] = true,
                                ["barkskin"] = true, ["tiger's fury"] = true, ["dash"] = true, ["frenzied regeneration"] = true,
                                ["rapid fire"] = true, ["bestial wrath"] = true, ["deterrence"] = true, ["inner focus"] = true, ["inner fire"] = true,
                                ["fade"] = true,
                            }
                            if selfOnly[clean] then
                                isSelfBuff = true
                            elseif not UnitExists("target") or (UnitIsUnit and UnitIsUnit("target", "player")) then
                                isSelfBuff = true
                            elseif UnitExists("target") and ((UnitCanAssist and not UnitCanAssist("player", "target")) or (UnitIsEnemy and UnitIsEnemy("player", "target"))) then
                                -- Target is hostile/enemy mob: beneficial buffs auto-self-cast on player!
                                isSelfBuff = true
                            end
                        end

                        if isSelfBuff then
                            -- Paladin rule: Only 1 seal can be active at a time; new seal replaces previous seal
                            if clean:find("^seal of ") then
                                for k in pairs(FC.activeBuffs) do
                                    if k:find("^seal of ") then
                                        FC:Log("SEAL_REPLACED", "previous seal=%s removed", k)
                                        FC.activeBuffs[k] = nil
                                    end
                                end
                            end

                            -- Shaman rule: Only 1 elemental shield (Lightning / Water / Earth Shield) active at a time
                            if clean == "lightning shield" or clean == "water shield" or clean == "earth shield" then
                                FC.activeBuffs["lightning shield"] = nil
                                FC.activeBuffs["water shield"] = nil
                                FC.activeBuffs["earth shield"] = nil
                            end

                            FC.activeBuffs[clean] = {
                                start = now,
                                duration = buffDur,
                                expires = now + buffDur,
                                stacks = DEFAULT_BUFF_STACKS and DEFAULT_BUFF_STACKS[clean] or nil,
                                lastStackDecrement = 0,
                            }
                            FC:Log("BUFF_CAST_SET", "clean=%s dur=%.1f exp=%.1f", clean, buffDur, now + buffDur)
                        end
                    end

                    -- Damage Absorption Shield Initialization on cast
                    local isShieldSpell = IsShieldSpell(clean) or (castSpellID and KNOWN_SHIELD_SPELLS[castSpellID])

                    if isShieldSpell then
                        local isCastOnPlayer = true
                        if UnitExists("target") and not (UnitIsUnit and UnitIsUnit("target", "player")) and UnitCanAssist and UnitCanAssist("player", "target") then
                            isCastOnPlayer = false
                        end
                        FC:LogShield("SHIELD_CAST", "spell=%s id=%s onPlayer=%s", clean, tostring(castSpellID), tostring(isCastOnPlayer))
                        if isCastOnPlayer then
                            local maxVal = FC:ResolveShieldMaxAmount(castSpellID, clean)
                            FC.currentShieldRemaining = maxVal
                            FC.currentShieldMax = maxVal
                            FC.currentShieldSpell = clean
                            FC.hasActiveShield = true
                            FC:LogShield("SHIELD_INIT", "spell=%s maxVal=%s", clean, tostring(maxVal))
                            pcall(function() FC:UpdateHealth() end)
                        end
                    end
                end

                FC.needsCooldownRefresh = true
                pcall(function() FC:UpdateCooldowns() end)
                pcall(function() FC:UpdateTotems() end)
            end
        end
    elseif event == "CVAR_UPDATE" then
        if ForeverClassesDB and ForeverClassesDB.textMode == "SYNC" then
            FC:UpdateHealth()
            FC:UpdatePower()
        end
    end
end)
