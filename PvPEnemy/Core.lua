-- PvPEnemy: Track your killers, get your revenge.
local addonName, ns = ...

local DB_VERSION = 2

-- Default database structure
local DEFAULT_DB = {
    dbVersion = DB_VERSION,
    enemies = {},   -- ["Name-Realm"] = { kills = N, lastKill = time, level = N, class = "", race = "", myLevel = N }
    settings = {
        soundEnabled = true,
        flashEnabled = true,
        alertDuration = 5,
        ignorePvPInstances = true,
        shareEnabled = false,
    },
}

-- A subsystem that blows up during init must not take the rest of the addon
-- with it (a nil global in Share.lua used to silently kill everything after it).
local function SafeInit(label, fn)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn)
    if not ok then
        print("|cffff4444PvP Enemy|r: |cffff0000" .. label .. " failed to initialize:|r " .. tostring(err))
    end
end

-- Addon frame
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialize saved variables
        local freshInstall = (PvPEnemyDB == nil)
        if freshInstall then
            PvPEnemyDB = CopyTable(DEFAULT_DB)
        end
        -- Ensure all keys exist. dbVersion is deliberately excluded: filling it
        -- in from the defaults would stamp the current version onto a legacy
        -- database and skip the migration it still needs.
        for k, v in pairs(DEFAULT_DB) do
            if k ~= "dbVersion" and PvPEnemyDB[k] == nil then
                PvPEnemyDB[k] = type(v) == "table" and CopyTable(v) or v
            end
        end
        for k, v in pairs(DEFAULT_DB.settings) do
            if PvPEnemyDB.settings[k] == nil then
                PvPEnemyDB.settings[k] = v
            end
        end
        if PvPEnemyDB.dbVersion == nil then
            PvPEnemyDB.dbVersion = freshInstall and DB_VERSION or 1
        end

        ns.db = PvPEnemyDB

        -- Initialize subsystems
        SafeInit("Tracker", ns.InitTracker)
        SafeInit("Scanner", ns.InitScanner)
        SafeInit("UI", ns.InitUI)
        SafeInit("Share", ns.InitShare)

        self:UnregisterEvent("ADDON_LOADED")
        print("|cffff4444PvP Enemy|r loaded. Type |cff00ff00/pvpenemy|r for commands.")

    elseif event == "PLAYER_LOGIN" then
        -- Realm name is only reliable from PLAYER_LOGIN onwards, and the
        -- migration needs it to canonicalize bare names.
        SafeInit("Database migration", ns.MigrateDB)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Expose namespace
ns.frame = frame

---------------------------------------------------------------------------
-- Name canonicalization
--
-- The combat log hands us "Celu" for same-realm players but "Celu-Golemagg"
-- for cross-realm ones. Storing both shapes meant lookups had to fall back to
-- fuzzy matching on the part before the dash, which fired the alert for any
-- stranger who happened to share a name. Every name is now canonicalized to
-- "Name-Realm" on the way in, so lookups are exact.
---------------------------------------------------------------------------
function ns.MyRealm()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    if type(realm) ~= "string" or realm == "" then return nil end
    return (realm:gsub("%s+", ""))
end

function ns.Canon(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    local realm = ns.MyRealm()
    if not realm then return name end
    return name .. "-" .. realm
end

-- Display form: drop the realm suffix when it is our own realm.
function ns.ShortName(name)
    if type(name) ~= "string" or name == "" then return "?" end
    local base, realm = name:match("^([^-]+)%-?(.*)$")
    if not base then return name end
    if realm == "" or realm == ns.MyRealm() then return base end
    return name
end

---------------------------------------------------------------------------
-- Database migration
---------------------------------------------------------------------------
local function NewerOf(a, b)
    if (a.lastKill or 0) >= (b.lastKill or 0) then return a, b end
    return b, a
end

local function Prefer(newer, older, key, unknown)
    local v = newer[key]
    if v ~= nil and v ~= unknown then return v end
    local w = older[key]
    if w ~= nil and w ~= unknown then return w end
    return v ~= nil and v or w
end

function ns.MigrateDB()
    if not ns.db then return end
    if ns.db.dbVersion == DB_VERSION then return end

    local migrated, moved, merged = {}, 0, 0
    for key, data in pairs(ns.db.enemies) do
        if type(data) == "table" then
            local canon = ns.Canon(key) or key
            local existing = migrated[canon]
            if existing then
                -- Two records for one player (a bare "Celu" and a "Celu-Realm").
                -- Sums are order-independent; descriptive fields come from
                -- whichever record was touched most recently.
                local newer, older = NewerOf(existing, data)
                migrated[canon] = {
                    kills    = (existing.kills or 0) + (data.kills or 0),
                    wins     = (existing.wins or 0) + (data.wins or 0),
                    lastKill = newer.lastKill,
                    level    = Prefer(newer, older, "level"),
                    myLevel  = Prefer(newer, older, "myLevel"),
                    class    = Prefer(newer, older, "class", "Unknown") or "Unknown",
                    race     = Prefer(newer, older, "race", "Unknown") or "Unknown",
                    lastZone = Prefer(newer, older, "lastZone"),
                    note     = newer.note or older.note,
                    migratedFrom = existing.migratedFrom or key,
                }
                merged = merged + 1
            else
                if canon ~= key then
                    -- Keep the original key so the rewrite stays auditable.
                    data.migratedFrom = key
                    moved = moved + 1
                end
                migrated[canon] = data
            end
        end
    end

    ns.db.enemies = migrated
    ns.db.dbVersion = DB_VERSION

    if moved > 0 or merged > 0 then
        print(string.format("|cffff4444PvP Enemy|r: kill list upgraded — %d name%s given a realm, %d duplicate%s merged.",
            moved, moved == 1 and "" or "s", merged, merged == 1 and "" or "s"))
    end
end

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
    name = ns.Canon(name)
    if not name then return end
    info = info or {}

    local entry = ns.db.enemies[name]
    if entry then
        entry.kills = (entry.kills or 0) + 1
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
    print("|cffff4444PvP Enemy|r: |cffff8800" .. ns.ShortName(name) .. "|r added to kill list.")
end

function ns.RemoveEnemy(name)
    name = ns.Canon(name)
    if name and ns.db.enemies[name] then
        ns.db.enemies[name] = nil
        print("|cffff4444PvP Enemy|r: |cff00ff00" .. ns.ShortName(name) .. "|r removed from kill list.")
        return true
    end
    return false
end

function ns.IsEnemy(name)
    return ns.GetEnemy(name) ~= nil
end

function ns.GetEnemy(name)
    name = ns.Canon(name)
    if not name then return nil end
    return ns.db.enemies[name]
end

-- Case-insensitive lookup, used by the slash commands so typing
-- "/pvpenemy remove celu" still works.
function ns.FindEnemy(name)
    local canon = ns.Canon(name)
    if not canon then return nil end
    if ns.db.enemies[canon] then return ns.db.enemies[canon], canon end
    local lowered = canon:lower()
    for storedName, data in pairs(ns.db.enemies) do
        if storedName:lower() == lowered then return data, storedName end
    end
    return nil
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
    return CLASS_COLORS[type(class) == "string" and class:upper() or ""] or "ffffffff"
end

function ns.IsKnownClass(class)
    return type(class) == "string" and CLASS_COLORS[class:upper()] ~= nil
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_PVPENEMY1 = "/pvpenemy"
SLASH_PVPENEMY2 = "/pvpe"
SlashCmdList["PVPENEMY"] = function(msg)
    msg = msg or ""
    local cmd, arg = msg:match("^(%S+)%s*(.*)")
    cmd = cmd and cmd:lower() or msg:lower()
    arg = arg or ""

    if cmd == "add" and arg ~= "" then
        local name = ns.Canon(arg)
        if not name then
            print("|cffff4444PvP Enemy|r: Usage: /pvpenemy add <Name[-Realm]>")
        elseif ns.IsEnemy(name) then
            print("|cffff4444PvP Enemy|r: |cffff8800" .. ns.ShortName(name) .. "|r already on kill list.")
        else
            ns.AddEnemy(name, {})
        end

    elseif cmd == "note" then
        local name, note = arg:match("^(%S+)%s+(.*)")
        if not name or note == "" then
            print("|cffff4444PvP Enemy|r: Usage: /pvpenemy note <Name-Realm> <text>")
        else
            local enemy, storedName = ns.FindEnemy(name)
            if enemy then
                enemy.note = note
                print("|cffff4444PvP Enemy|r: Note set for |cffff8800" .. ns.ShortName(storedName) .. "|r: " .. note)
            else
                print("|cffff4444PvP Enemy|r: '" .. name .. "' not found on kill list.")
            end
        end

    elseif cmd == "list" then
        local count = 0
        print("|cffff4444PvP Enemy|r — Kill List:")
        for name, data in pairs(ns.db.enemies) do
            local color = ns.ClassColor(data.class)
            local killerLvl = (type(data.level) == "number" and data.level > 0) and tostring(data.level) or "??"
            local myLvl = (type(data.myLevel) == "number" and data.myLevel > 0) and tostring(data.myLevel) or "??"
            local zonePart = data.lastZone and (" @ " .. tostring(data.lastZone)) or ""
            local deaths = tonumber(data.kills) or 0
            local wins = tonumber(data.wins) or 0
            local lastKill = tonumber(data.lastKill)
            local when = lastKill and date("%Y-%m-%d %H:%M", lastKill) or "unknown"
            print(string.format("  |c%s%s|r — |cffff6060Deaths: %d|r  |cff60ff60Wins: %d|r  [Lvl %s vs your %s], last: %s%s",
                color, ns.ShortName(name), deaths, wins, killerLvl, myLvl, when, zonePart))
            if data.note then
                print("    |cffffff00Note:|r " .. tostring(data.note))
            end
            count = count + 1
        end
        if count == 0 then
            print("  (empty)")
        else
            print(string.format("  Total: %d enemies", count))
        end

    elseif cmd == "remove" and arg ~= "" then
        local _, storedName = ns.FindEnemy(arg)
        if storedName then
            ns.RemoveEnemy(storedName)
        else
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

    elseif cmd == "share" then
        ns.db.settings.shareEnabled = not ns.db.settings.shareEnabled
        if ns.db.settings.shareEnabled then
            print("|cffff4444PvP Enemy|r: Guild sharing |cff00ff00enabled|r — enemy alerts will be broadcast to online guild members.")
        else
            print("|cffff4444PvP Enemy|r: Guild sharing |cffff8800disabled|r.")
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
        print("  |cff00ff00/pvpenemy share|r — Toggle sharing enemy alerts with guild (default: off)")
        print("  |cff00ff00/pvpenemy bg|r — Toggle tracking in battlegrounds/arenas (default: off)")
    end
end
