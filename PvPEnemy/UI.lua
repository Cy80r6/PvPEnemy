-- UI: Popup dialog for adding enemies + on-screen warning display.
local addonName, ns = ...

---------------------------------------------------------------------------
-- Warning frame (top of screen alert)
---------------------------------------------------------------------------
local warningFrame = CreateFrame("Frame", "PvPEnemyWarningFrame", UIParent, "BackdropTemplate")
warningFrame:SetSize(400, 60)
warningFrame:SetPoint("TOP", UIParent, "TOP", 0, -100)
warningFrame:SetFrameStrata("HIGH")
warningFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
warningFrame:SetBackdropColor(0.4, 0, 0, 0.9)
warningFrame:SetBackdropBorderColor(1, 0, 0, 1)
warningFrame:Hide()

local warningIcon = warningFrame:CreateTexture(nil, "ARTWORK")
warningIcon:SetSize(32, 32)
warningIcon:SetPoint("LEFT", 10, 0)
warningIcon:SetTexture("Interface\\Icons\\Ability_DualWield")

local warningText = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
warningText:SetPoint("LEFT", warningIcon, "RIGHT", 10, 6)
warningText:SetPoint("RIGHT", warningFrame, "RIGHT", -10, 0)
warningText:SetJustifyH("LEFT")

local warningSubtext = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
warningSubtext:SetPoint("TOPLEFT", warningText, "BOTTOMLEFT", 0, -2)
warningSubtext:SetPoint("RIGHT", warningFrame, "RIGHT", -10, 0)
warningSubtext:SetJustifyH("LEFT")
warningSubtext:SetTextColor(0.8, 0.8, 0.8)

local warningNote = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
warningNote:SetPoint("TOPLEFT", warningSubtext, "BOTTOMLEFT", 0, -2)
warningNote:SetPoint("RIGHT", warningFrame, "RIGHT", -10, 0)
warningNote:SetJustifyH("LEFT")
warningNote:SetTextColor(1, 0.82, 0)

-- Flash overlay (full screen red flash)
local flashFrame = CreateFrame("Frame", "PvPEnemyFlashFrame", UIParent)
flashFrame:SetAllPoints(UIParent)
flashFrame:SetFrameStrata("BACKGROUND")
flashFrame:Hide()

local flashTexture = flashFrame:CreateTexture(nil, "BACKGROUND")
flashTexture:SetAllPoints()
flashTexture:SetColorTexture(1, 0, 0, 0.3)

local flashAnim = flashFrame:CreateAnimationGroup()
local fadeIn = flashAnim:CreateAnimation("Alpha")
fadeIn:SetFromAlpha(0)
fadeIn:SetToAlpha(1)
fadeIn:SetDuration(0.15)
fadeIn:SetOrder(1)
local fadeOut = flashAnim:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1)
fadeOut:SetToAlpha(0)
fadeOut:SetDuration(0.4)
fadeOut:SetOrder(2)
flashAnim:SetScript("OnFinished", function() flashFrame:Hide() end)

local hideTimer = nil

function ns.InitUI()
    -- Nothing extra needed, frames are created above
end

function ns.ShowWarning(name, enemyData, unitId)
    local color = ns.ClassColor(enemyData.class)
    warningText:SetText("|c" .. color .. name .. "|r")

    local levelStr = enemyData.level or "??"
    local classStr = enemyData.class or "Unknown"
    local zonePart = enemyData.lastZone and (" — " .. enemyData.lastZone) or ""
    warningSubtext:SetText(string.format("Level %s %s — Killed you %dx%s", levelStr, classStr, enemyData.kills, zonePart))

    if enemyData.note then
        warningNote:SetText("Note: " .. enemyData.note)
        warningNote:Show()
        warningFrame:SetHeight(80)
    else
        warningNote:Hide()
        warningFrame:SetHeight(60)
    end

    -- Try to set class icon
    local classFile = enemyData.class and enemyData.class:upper()
    if classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
        warningIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = CLASS_ICON_TCOORDS[classFile]
        warningIcon:SetTexCoord(unpack(coords))
    else
        warningIcon:SetTexture("Interface\\Icons\\Ability_DualWield")
        warningIcon:SetTexCoord(0, 1, 0, 1)
    end

    warningFrame:Show()

    -- Play sound
    if ns.db.settings.soundEnabled then
        PlaySound(8959, "Master") -- PVP flag taken sound
    end

    -- Screen flash
    if ns.db.settings.flashEnabled then
        flashFrame:Show()
        flashAnim:Stop()
        flashAnim:Play()
    end

    -- Auto-hide after duration
    if hideTimer then
        hideTimer:Cancel()
    end
    hideTimer = C_Timer.NewTimer(ns.db.settings.alertDuration, function()
        warningFrame:Hide()
    end)
end

---------------------------------------------------------------------------
-- Add Enemy popup (shown on death)
---------------------------------------------------------------------------
local popupFrame = CreateFrame("Frame", "PvPEnemyPopupFrame", UIParent, "BackdropTemplate")
popupFrame:SetSize(350, 120)
popupFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
popupFrame:SetFrameStrata("DIALOG")
popupFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
popupFrame:SetBackdropColor(0.1, 0, 0, 0.95)
popupFrame:SetBackdropBorderColor(0.8, 0, 0, 1)
popupFrame:EnableMouse(true)
popupFrame:SetMovable(true)
popupFrame:RegisterForDrag("LeftButton")
popupFrame:SetScript("OnDragStart", popupFrame.StartMoving)
popupFrame:SetScript("OnDragStop", popupFrame.StopMovingOrSizing)
popupFrame:Hide()

local popupTitle = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
popupTitle:SetPoint("TOP", 0, -12)
popupTitle:SetText("|cffff4444PvP Enemy|r")

local popupText = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
popupText:SetPoint("TOP", popupTitle, "BOTTOM", 0, -8)
popupText:SetWidth(310)
popupText:SetJustifyH("CENTER")

local addButton = CreateFrame("Button", nil, popupFrame, "UIPanelButtonTemplate")
addButton:SetSize(120, 24)
addButton:SetPoint("BOTTOMLEFT", 20, 12)
addButton:SetText("Add to List")

local ignoreButton = CreateFrame("Button", nil, popupFrame, "UIPanelButtonTemplate")
ignoreButton:SetSize(120, 24)
ignoreButton:SetPoint("BOTTOMRIGHT", -20, 12)
ignoreButton:SetText("Ignore")

local pendingAttacker = nil

ignoreButton:SetScript("OnClick", function()
    pendingAttacker = nil
    popupFrame:Hide()
end)

addButton:SetScript("OnClick", function()
    if pendingAttacker then
        ns.AddEnemy(pendingAttacker.name, pendingAttacker)
        pendingAttacker = nil
    end
    popupFrame:Hide()
end)

-- Auto-hide popup after 30 seconds
local popupTimer = nil

function ns.ShowAddEnemyPopup(attackerInfo)
    pendingAttacker = attackerInfo
    local color = ns.ClassColor(attackerInfo.class)
    local killerLvl = (attackerInfo.level and attackerInfo.level > 0) and tostring(attackerInfo.level) or "?? (too high to inspect)"
    local myLvl = attackerInfo.myLevel and tostring(attackerInfo.myLevel) or "??"
    popupText:SetText(string.format(
        "|c%s%s|r killed you!\nLevel %s %s (you were level %s)\n\nAdd to your kill list?",
        color,
        attackerInfo.name,
        killerLvl,
        attackerInfo.class or "Unknown",
        myLvl
    ))
    popupFrame:Show()

    if popupTimer then
        popupTimer:Cancel()
    end
    popupTimer = C_Timer.NewTimer(30, function()
        popupFrame:Hide()
        pendingAttacker = nil
    end)
end
