-- Scanner: Detects known enemies via nameplates, target, and mouseover.
local addonName, ns = ...

local frame = CreateFrame("Frame")
local recentAlerts = {} -- throttle: [name] = timestamp of last alert
local ALERT_COOLDOWN = 30 -- seconds between repeated alerts for the same player

local function CleanupRecentAlerts()
    local now = GetTime()
    for name, t in pairs(recentAlerts) do
        if (now - t) > ALERT_COOLDOWN then
            recentAlerts[name] = nil
        end
    end
end

function ns.InitScanner()
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_TARGET_CHANGED" then
            ns.CheckUnit("target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            ns.CheckUnit("mouseover")
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            local unitId = ...
            ns.CheckUnit(unitId)
        end
    end)
end

function ns.CheckUnit(unitId)
    if ns.db.settings.ignorePvPInstances and ns.IsInPvPInstance() then return end
    if not UnitExists(unitId) then return end
    if not UnitIsPlayer(unitId) then return end
    if not UnitIsEnemy("player", unitId) then return end

    local name, realm = UnitName(unitId)
    if not name then return end
    if realm and realm ~= "" then
        name = name .. "-" .. realm
    end

    -- Exact lookup: ns.GetEnemy canonicalizes to "Name-Realm", so a stranger
    -- from another realm who happens to share a name no longer matches.
    name = ns.Canon(name)
    if not name then return end
    local enemy = ns.db.enemies[name]
    if not enemy then return end

    -- Throttle alerts
    local now = GetTime()
    if recentAlerts[name] and (now - recentAlerts[name]) < ALERT_COOLDOWN then
        return
    end
    CleanupRecentAlerts()
    recentAlerts[name] = now

    -- Update level and zone
    local level = UnitLevel(unitId)
    if level and level > 0 then
        enemy.level = level
    end
    enemy.lastZone = GetZoneText()

    -- Fire alert
    ns.ShowWarning(name, enemy, unitId)
    if ns.ShareAlert then ns.ShareAlert(name, enemy) end
end
