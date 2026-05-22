-- PvPEnemy: Track your killers, get your revenge.
local addonName, ns = ...

-- Default database structure
local DEFAULT_DB = {
    enemies = {},   -- ["Name-Realm"] = { kills = N, lastKill = time, level = N, class = "", race = "", myLevel = N }
    settings = {
        soundEnabled = true,
        flashEnabled = true,
        alertDuration = 5,
        ignorePvPInstances = true,  -- disable tracking in BGs and arenas
    },
}

-- Addon frame
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialize saved variables
        if not PvPEnemyDB then
            PvPEnemyDB = CopyTable(DEFAULT_DB)
        end
        -- Migrate: ensure all keys exist
        for k, v in pairs(DEFAULT_DB) do
            if PvPEnemyDB[k] == nil then
                PvPEnemyDB[k] = CopyTable(v)
            end
        end
        for k, v in pairs(DEFAULT_DB.settings) do
            if PvPEnemyDB.settings[k] == nil then
                PvPEnemyDB.settings[k] = v
            end
        end

        ns.db = PvPEnemyDB

        -- Initialize subsystems
        if ns.InitTracker then ns.InitTracker() end
        if ns.InitScanner then ns.InitScanner() end
        if ns.InitUI then ns.InitUI() end

        self:UnregisterEvent("ADDON_LOADED")
        print("|cffff4444PvP Enemy|r loaded. Type |cff00ff00/pvpenemy|r for commands.")
    end
end)

-- Expose namespace
ns.frame = frame

---------------------------------------------------------------------------
-- Instance helpers
---------------------------------------------------------------------------
function ns.IsInPvPInstance()
    local _, instanceType = IsInInstance()
    return instanceType == "pvp" or instanceType == "arena"
end

---------------------------------------------------------------------------
-- Database helpers
---------------------------------------------------------------------------
function ns.AddEnemy(name, info)
    local entry = ns.db.enemies[name]
    if entry then
        entry.kills = entry.kills + 1
        entry.lastKill = time()
        if info.level then entry.level = info.level end
        if info.class then entry.class = info.class end
        if info.race then entry.race = info.race end
        if info.myLevel then entry.myLevel = info.myLevel end
        if info.zone then entry.lastZone = info.zone end
    else
        ns.db.enemies[name] = {
            kills = 1,
            lastKill = time(),
            level = info.level,
            class = info.class or "Unknown",
            race = info.race or "Unknown",
            myLevel = info.myLevel,
            lastZone = info.zone,
        }
    end
    print("|cffff4444PvP Enemy|r: |cffff8800" .. name .. "|r added to kill list.")
end

function ns.RemoveEnemy(name)
    if ns.db.enemies[name] then
        ns.db.enemies[name] = nil
        print("|cffff4444PvP Enemy|r: |cff00ff00" .. name .. "|r removed from kill list.")
        return true
    end
    return false
end

function ns.IsEnemy(name)
    return ns.db.enemies[name] ~= nil
end

function ns.GetEnemy(name)
    return ns.db.enemies[name]
end

---------------------------------------------------------------------------
-- Class colors helper
---------------------------------------------------------------------------
local CLASS_COLORS = {
    WARRIOR     = "ffc79c6e",
    PALADIN     = "fff58cba",
    HUNTER      = "ffabd473",
    ROGUE       = "fffff569",
    PRIEST      = "ffffffff",
    SHAMAN      = "ff0070de",
    MAGE        = "ff69ccf0",
    WARLOCK     = "ff9482c9",
    DRUID       = "ffff7d0a",
    DEATHKNIGHT = "ffc41f3b",
}

function ns.ClassColor(class)
    return CLASS_COLORS[class and class:upper()] or "ffffffff"
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_PVPENEMY1 = "/pvpenemy"
SlashCmdList["PVPENEMY"] = function(msg)
    local cmd, arg = msg:match("^(%S+)%s*(.*)")
    cmd = cmd and cmd:lower() or msg:lower()

    if cmd == "add" and arg ~= "" then
        local name = arg
        if not name:find("-") then
            name = name .. "-" .. (GetRealmName() or "Unknown")
        end
        if ns.IsEnemy(name) then
            print("|cffff4444PvP Enemy|r: |cffff8800" .. name .. "|r already on kill list.")
        else
            ns.AddEnemy(name, {})
        end

    elseif cmd == "note" then
        local name, note = arg:match("^(%S+)%s+(.*)")
        if not name or note == "" then
            print("|cffff4444PvP Enemy|r: Usage: /pvpenemy note <Name-Realm> <text>")
        else
            local enemy = ns.GetEnemy(name)
            if not enemy then
                -- case-insensitive fallback
                for n, _ in pairs(ns.db.enemies) do
                    if n:lower() == name:lower() then enemy = ns.db.enemies[n]; name = n; break end
                end
            end
            if enemy then
                enemy.note = (note ~= "" and note or nil)
                if enemy.note then
                    print("|cffff4444PvP Enemy|r: Note set for |cffff8800" .. name .. "|r: " .. note)
                else
                    print("|cffff4444PvP Enemy|r: Note cleared for |cffff8800" .. name .. "|r.")
                end
            else
                print("|cffff4444PvP Enemy|r: '" .. name .. "' not found on kill list.")
            end
        end

    elseif cmd == "list" then
        local count = 0
        print("|cffff4444PvP Enemy|r — Kill List:")
        for name, data in pairs(ns.db.enemies) do
            local color = ns.ClassColor(data.class)
            local killerLvl = (data.level and data.level > 0) and tostring(data.level) or "??"
            local myLvl = data.myLevel and tostring(data.myLevel) or "??"
            local zonePart = data.lastZone and (" @ " .. data.lastZone) or ""
            print(string.format("  |c%s%s|r — Killed you %dx [Lvl %s vs your %s], last: %s%s",
                color, name, data.kills, killerLvl, myLvl, date("%Y-%m-%d %H:%M", data.lastKill), zonePart))
            if data.note then
                print("    |cffffff00Note:|r " .. data.note)
            end
            count = count + 1
        end
        if count == 0 then
            print("  (empty)")
        else
            print(string.format("  Total: %d enemies", count))
        end

    elseif cmd == "remove" and arg ~= "" then
        if not ns.RemoveEnemy(arg) then
            -- Try case-insensitive search
            for name in pairs(ns.db.enemies) do
                if name:lower() == arg:lower() then
                    ns.RemoveEnemy(name)
                    return
                end
            end
            print("|cffff4444PvP Enemy|r: '" .. arg .. "' not found on kill list.")
        end

    elseif cmd == "clear" then
        wipe(ns.db.enemies)
        print("|cffff4444PvP Enemy|r: Kill list cleared.")

    elseif cmd == "sound" then
        ns.db.settings.soundEnabled = not ns.db.settings.soundEnabled
        print("|cffff4444PvP Enemy|r: Sound " .. (ns.db.settings.soundEnabled and "enabled" or "disabled"))

    elseif cmd == "flash" then
        ns.db.settings.flashEnabled = not ns.db.settings.flashEnabled
        print("|cffff4444PvP Enemy|r: Flash " .. (ns.db.settings.flashEnabled and "enabled" or "disabled"))

    elseif cmd == "alert" and arg ~= "" then
        local n = tonumber(arg)
        if n and n >= 1 and n <= 30 then
            ns.db.settings.alertDuration = n
            print("|cffff4444PvP Enemy|r: Alert duration set to |cff00ff00" .. n .. "|r seconds.")
        else
            print("|cffff4444PvP Enemy|r: Usage: /pvpenemy alert <1-30>")
        end

    elseif cmd == "bg" then
        ns.db.settings.ignorePvPInstances = not ns.db.settings.ignorePvPInstances
        if ns.db.settings.ignorePvPInstances then
            print("|cffff4444PvP Enemy|r: Tracking |cffff8800disabled|r in battlegrounds and arenas.")
        else
            print("|cffff4444PvP Enemy|r: Tracking |cff00ff00enabled|r in battlegrounds and arenas.")
        end

    else
        print("|cffff4444PvP Enemy|r commands:")
        print("  |cff00ff00/pvpenemy list|r — Show kill list")
        print("  |cff00ff00/pvpenemy add <Name[-Realm]>|r — Manually add enemy")
        print("  |cff00ff00/pvpenemy remove <Name-Realm>|r — Remove from list")
        print("  |cff00ff00/pvpenemy clear|r — Clear entire list")
        print("  |cff00ff00/pvpenemy note <Name-Realm> <text>|r — Set a note for an enemy")
        print("  |cff00ff00/pvpenemy sound|r — Toggle warning sound")
        print("  |cff00ff00/pvpenemy flash|r — Toggle screen flash")
        print("  |cff00ff00/pvpenemy alert <1-30>|r — Set warning banner duration in seconds")
        print("  |cff00ff00/pvpenemy bg|r — Toggle tracking in battlegrounds/arenas (default: off)")
    end
end
