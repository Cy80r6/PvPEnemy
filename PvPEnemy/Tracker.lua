-- Tracker: Monitors combat log for enemy player kills on you.
local addonName, ns = ...

local lastAttacker = nil  -- { name, guid, class, race, level }
local DAMAGE_EVENTS = {
    SWING_DAMAGE = true,
    RANGE_DAMAGE = true,
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    SPELL_BUILDING_DAMAGE = true,
}

local frame = CreateFrame("Frame")

function ns.InitTracker()
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("PLAYER_DEAD")
    frame:SetScript("OnEvent", function(self, event)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            ns.OnCombatLogEvent()
        elseif event == "PLAYER_DEAD" then
            ns.OnPlayerDead()
        end
    end)
end

function ns.OnCombatLogEvent()
    local timestamp, subevent, hideCaster,
        sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

    -- We only care about enemy players hitting us
    if destGUID ~= UnitGUID("player") then return end
    if not sourceGUID or sourceGUID == "" then return end

    -- Check if source is an enemy player (flags: COMBATLOG_OBJECT_TYPE_PLAYER + COMBATLOG_OBJECT_REACTION_HOSTILE)
    local isPlayer = bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0
    local isHostile = bit.band(sourceFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0
    if not (isPlayer and isHostile) then return end

    if DAMAGE_EVENTS[subevent] then
        -- Extract class and race from GUID
        -- Player GUID format: Player-ServerID-CharacterID
        local _, class, race, level = ns.GetInfoFromGUID(sourceGUID)

        lastAttacker = {
            name = sourceName,
            guid = sourceGUID,
            class = class or "Unknown",
            race = race or "Unknown",
            level = level or "??",
        }
    end
end

function ns.OnPlayerDead()
    if not lastAttacker then return end
    if ns.db.settings.ignorePvPInstances and ns.IsInPvPInstance() then
        lastAttacker = nil
        return
    end

    local name = lastAttacker.name
    if not name then return end

    lastAttacker.myLevel = UnitLevel("player")
    lastAttacker.zone = GetZoneText()

    -- Already on kill list? Just increment.
    if ns.IsEnemy(name) then
        ns.AddEnemy(name, lastAttacker)
        lastAttacker = nil
        return
    end

    -- Show confirmation popup
    if ns.ShowAddEnemyPopup then
        ns.ShowAddEnemyPopup(lastAttacker)
    end

    lastAttacker = nil
end

-- Extract info from GUID. Works best if we can inspect/target.
-- Falls back to limited info.
function ns.GetInfoFromGUID(guid)
    if not guid then return nil end
    local _, engClass, _, engRace, _, name, realm = GetPlayerInfoByGUID(guid)
    local level = nil
    -- Try to get level from unit IDs if they match this GUID
    for _, unitId in ipairs({"target", "mouseover", "focus"}) do
        if UnitGUID(unitId) == guid then
            level = UnitLevel(unitId)
            if not engClass or engClass == "" then
                _, engClass = UnitClass(unitId)
            end
            break
        end
    end
    return name, engClass, engRace, level
end
