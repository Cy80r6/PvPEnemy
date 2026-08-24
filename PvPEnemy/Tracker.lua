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
local playerGUID

local frame = CreateFrame("Frame")

-- UnitGUID("player") is not reliable at ADDON_LOADED, so resolve it lazily and
-- refresh it at PLAYER_LOGIN.
local function PlayerGUID()
    if not playerGUID then
        playerGUID = UnitGUID("player")
    end
    return playerGUID
end

function ns.InitTracker()
    playerGUID = UnitGUID("player")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("PLAYER_DEAD")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self, event)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            ns.OnCombatLogEvent()
        elseif event == "PLAYER_DEAD" then
            ns.OnPlayerDead()
        elseif event == "PLAYER_LOGIN" then
            playerGUID = UnitGUID("player")
        end
    end)
end

function ns.OnCombatLogEvent()
    local timestamp, subevent, hideCaster,
        sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

    local myGUID = PlayerGUID()

    -- Case 1: we landed the killing blow.
    -- UNIT_DIED carries no source (sourceGUID is 0000000000000000), so it can
    -- never tell us who did the killing. PARTY_KILL is the subevent that does.
    if subevent == "PARTY_KILL" and myGUID and sourceGUID == myGUID and destName then
        local enemy, storedName = ns.FindEnemy(destName)
        if enemy then
            enemy.wins = (enemy.wins or 0) + 1
            print("|cffff4444PvP Enemy|r: You killed |cffff8800" .. ns.ShortName(storedName)
                .. "|r. Revenge! (" .. enemy.wins .. " win" .. (enemy.wins == 1 and "" or "s") .. ")")
            if ns.OnEnemyKilled then ns.OnEnemyKilled(storedName) end
        end
        return
    end

    -- Case 2: enemy player is hitting us
    if not myGUID or destGUID ~= myGUID then return end
    if not sourceGUID or sourceGUID == "" then return end

    local isPlayer = bit.band(sourceFlags or 0, COMBATLOG_OBJECT_TYPE_PLAYER) > 0
    local isHostile = bit.band(sourceFlags or 0, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0
    if not (isPlayer and isHostile) then return end

    if DAMAGE_EVENTS[subevent] then
        local _, class, race, level = ns.GetInfoFromGUID(sourceGUID)
        lastAttacker = {
            name = sourceName,
            guid = sourceGUID,
            class = class or "Unknown",
            race = race or "Unknown",
            level = level,
        }
    end
end

function ns.OnPlayerDead()
    if not lastAttacker then return end
    if ns.db.settings.ignorePvPInstances and ns.IsInPvPInstance() then
        lastAttacker = nil
        return
    end

    local name = ns.Canon(lastAttacker.name)
    if not name then
        lastAttacker = nil
        return
    end

    lastAttacker.name = name
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
