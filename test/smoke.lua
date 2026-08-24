-- Smoke tests for PvPEnemy. Run from the repo root:
--   luajit test/smoke.lua
-- Every scenario that used to ship a silent crash to testers has a case here.

local W = dofile((arg[0]:match("^(.*)[/\\][^/\\]*$") or ".") .. "/stubs.lua")

local say = W.realPrint
local passed, failed = 0, 0
local function check(label, cond, detail)
    if cond then
        passed = passed + 1
        say(string.format("  ok  %s", label))
    else
        failed = failed + 1
        say(string.format("  FAIL %s%s", label, detail and ("  -> " .. tostring(detail)) or ""))
    end
end

local function noErrors(label, errors)
    check(label, #errors == 0, errors[1])
end

local HOSTILE_PLAYER = 0x400 + 0x40

local function clog(t)
    W.combatLog = {
        0, t.subevent, false,
        t.sourceGUID, t.sourceName, t.sourceFlags or 0, 0,
        t.destGUID, t.destName, t.destFlags or 0, 0,
    }
    return W.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

local function v2db(enemies)
    return { dbVersion = 2, enemies = enemies, settings = {} }
end

---------------------------------------------------------------------------
say("\n-- startup --")
---------------------------------------------------------------------------
do
    local ns, errors = W.Startup()
    noErrors("addon loads and initializes without errors", errors)
    check("login message is printed", W.Output():find("loaded", 1, true) ~= nil, W.Output())
    check("addon message prefix registered via C_ChatInfo", W.registeredPrefixes["PvPEnemy"] == true)
    check("Share subsystem reports ready", ns.shareReady == true)
end

---------------------------------------------------------------------------
say("\n-- database migration --")
---------------------------------------------------------------------------
do
    local ns = W.Startup({
        enemies = { ["Celu"] = { kills = 3, wins = 1, lastKill = 100, class = "ROGUE", race = "Orc" } },
        settings = {},
    })
    local db = ns.db
    check('migrace: "Celu" -> "Celu-Golemagg"', db.enemies["Celu-Golemagg"] ~= nil)
    check("bare key is gone", db.enemies["Celu"] == nil)
    check("dbVersion bumped to 2", db.dbVersion == 2, db.dbVersion)
    check("original key kept for audit", db.enemies["Celu-Golemagg"].migratedFrom == "Celu")
    check("counts survive the rewrite", db.enemies["Celu-Golemagg"].kills == 3)
end

do
    local function seed()
        return {
            enemies = {
                ["Celu"] = { kills = 3, wins = 1, lastKill = 100, class = "Unknown", lastZone = "Barrens" },
                ["Celu-Golemagg"] = { kills = 1, wins = 2, lastKill = 200, class = "ROGUE", note = "ganker" },
            },
            settings = {},
        }
    end

    local ns = W.Startup(seed())
    local e = ns.db.enemies["Celu-Golemagg"]
    local n = 0
    for _ in pairs(ns.db.enemies) do n = n + 1 end
    check("migrace slije duplicity do jednoho zaznamu", n == 1, n)
    check("migrace slije duplicity (kills 3+1=4)", e and e.kills == 4, e and e.kills)
    check("wins secteny (1+2=3)", e and e.wins == 3, e and e.wins)
    check("popisne pole bere novejsi zaznam (class ROGUE)", e and e.class == "ROGUE", e and e.class)
    check("note se neztrati", e and e.note == "ganker", e and e.note)

    -- pairs() order is undefined, so the merge must not depend on it.
    local stable = true
    for _ = 1, 25 do
        local n2 = W.Startup(seed())
        local m = n2.db.enemies["Celu-Golemagg"]
        if not m or m.kills ~= 4 or m.wins ~= 3 or m.class ~= "ROGUE" then stable = false break end
    end
    check("merge je nezavisly na poradi iterace (25x)", stable)
end

do
    local ns = W.Startup(v2db({ ["Celu-Golemagg"] = { kills = 4, wins = 3, lastKill = 200 } }))
    ns.MigrateDB()
    ns.MigrateDB()
    check("migrace je idempotentni (uz hotova DB se nemeni)", ns.db.enemies["Celu-Golemagg"].kills == 4)
end

---------------------------------------------------------------------------
say("\n-- kill list --")
---------------------------------------------------------------------------
do
    W.Startup(v2db({
        ["Celu-Golemagg"] = { kills = 2, wins = 1, lastKill = 1700000000, class = "ROGUE", level = 60, myLevel = 58 },
    }))
    W.printed = {}
    noErrors("/pvpenemy list projde bez erroru", W.Slash("list"))
    local out = W.Output()
    check("list vypise zaznam", out:find("Deaths: 2", 1, true) ~= nil, out)
    check("list vypise Total", out:find("Total: 1 enemies", 1, true) ~= nil, out)
    check("jmeno na vlastnim realmu se zobrazi bez realmu", out:find("Celu|r", 1, true) ~= nil, out)
end

do
    -- The exact shape that crashed before: non-number level, and friends.
    W.Startup(v2db({
        ["Celu-Golemagg"] = { kills = "3", wins = "1", lastKill = nil, level = "60", myLevel = "59", note = "x" },
    }))
    W.printed = {}
    noErrors('list s level="60" (string) neshodi', W.Slash("list"))
    check("neznamy level se vypise jako ??", W.Output():find("Lvl ??", 1, true) ~= nil, W.Output())
end

do
    W.Startup(v2db({}))
    W.printed = {}
    noErrors("prazdny list neshodi", W.Slash("list"))
    check("prazdny list vypise (empty)", W.Output():find("(empty)", 1, true) ~= nil, W.Output())
end

---------------------------------------------------------------------------
say("\n-- win tracking --")
---------------------------------------------------------------------------
do
    local ns = W.Startup(v2db({ ["Celu-Golemagg"] = { kills = 1, lastKill = 100, class = "ROGUE" } }))
    noErrors("PARTY_KILL handler bezi bez erroru", clog{
        subevent = "PARTY_KILL", sourceGUID = W.playerGUID, sourceName = "Cy",
        destGUID = "Player-2-CELU", destName = "Celu",
    })
    check("PARTY_KILL zvysuje wins", ns.db.enemies["Celu-Golemagg"].wins == 1,
        ns.db.enemies["Celu-Golemagg"].wins)
end

do
    local ns = W.Startup(v2db({ ["Celu-Golemagg"] = { kills = 1, lastKill = 100 } }))
    clog{ subevent = "UNIT_DIED", sourceGUID = "0000000000000000", sourceName = nil,
          destGUID = "Player-2-CELU", destName = "Celu" }
    check("UNIT_DIED bez zdroje wins nezvysuje", (ns.db.enemies["Celu-Golemagg"].wins or 0) == 0)
end

do
    -- UnitGUID("player") can be nil at ADDON_LOADED; it must recover at login.
    W.Reset()
    W.playerGUID = nil
    local ns = W.LoadAddon()
    _G.PvPEnemyDB = v2db({ ["Celu-Golemagg"] = { kills = 1, lastKill = 100 } })
    noErrors("init s nil playerGUID nespadne", W.FireEvent("ADDON_LOADED", "PvPEnemy"))
    W.playerGUID = "Player-1-CY"
    W.units.player.guid = W.playerGUID
    noErrors("PLAYER_LOGIN dozene playerGUID", W.FireEvent("PLAYER_LOGIN"))
    clog{ subevent = "PARTY_KILL", sourceGUID = W.playerGUID, sourceName = "Cy",
          destGUID = "Player-2-CELU", destName = "Celu" }
    check("wins funguji i po nil GUID pri loadu", ns.db.enemies["Celu-Golemagg"].wins == 1)
end

---------------------------------------------------------------------------
say("\n-- scanner --")
---------------------------------------------------------------------------
do
    local ns = W.Startup(v2db({ ["Celu-Golemagg"] = { kills = 1, lastKill = 100, class = "ROGUE" } }))
    local alerted = nil
    ns.ShowWarning = function(name) alerted = name end

    W.units.target = { name = "Celu", realm = "JinyRealm", guid = "g-other", level = 60, class = "ROGUE", isEnemy = true }
    W.FireEvent("PLAYER_TARGET_CHANGED")
    check("cizi Celu-JinyRealm nespusti alert", alerted == nil, alerted)

    W.units.target = { name = "Celu", realm = "", guid = "g-real", level = 60, class = "ROGUE", isEnemy = true }
    W.FireEvent("PLAYER_TARGET_CHANGED")
    check("vlastni Celu alert spusti", alerted == "Celu-Golemagg", alerted)
end

do
    local ns = W.Startup(v2db({ ["Celu-Golemagg"] = { kills = 1, lastKill = 100 } }))
    local alerts = 0
    ns.ShowWarning = function() alerts = alerts + 1 end
    W.units.target = { name = "Celu", realm = "", guid = "g", level = 60, isEnemy = true }
    W.FireEvent("PLAYER_TARGET_CHANGED")
    W.FireEvent("PLAYER_TARGET_CHANGED")
    check("30s cooldown potlaci druhy alert", alerts == 1, alerts)
    W.Advance(31)
    W.FireEvent("PLAYER_TARGET_CHANGED")
    check("po cooldownu alert zase projde", alerts == 2, alerts)
end

---------------------------------------------------------------------------
say("\n-- click to target --")
---------------------------------------------------------------------------
do
    local ns = W.Startup(v2db({}))
    local btn = _G.PvPEnemyWarningFrame
    check("warning frame secure action type is macro", btn ~= nil and btn:GetAttribute("type") == "macro",
        btn and btn:GetAttribute("type"))

    ns.ShowWarning("Xyz-JinyRealm", { class = "ROGUE", kills = 1, wins = 0 })
    check("cross-realm jmeno: macrotext nese cely Name-Realm tvar",
        btn:GetAttribute("macrotext") == "/targetexact Xyz-JinyRealm", btn:GetAttribute("macrotext"))

    ns.ShowWarning("Celu-Golemagg", { class = "ROGUE", kills = 1, wins = 0 })
    check("vlastni realm: macrotext pouzije hole jmeno (ns.ShortName)",
        btn:GetAttribute("macrotext") == "/targetexact Celu", btn:GetAttribute("macrotext"))
end

---------------------------------------------------------------------------
say("\n-- death -> popup --")
---------------------------------------------------------------------------
do
    local ns = W.Startup(v2db({}))
    W.guids["Player-2-XYZ"] = { class = "ROGUE", race = "Orc", name = "Xyz", realm = "" }
    local captured = nil
    ns.ShowAddEnemyPopup = function(info) captured = info end

    clog{ subevent = "SPELL_DAMAGE", sourceGUID = "Player-2-XYZ", sourceName = "Xyz",
          sourceFlags = HOSTILE_PLAYER, destGUID = W.playerGUID, destName = "Cy" }
    noErrors("PLAYER_DEAD handler bezi bez erroru", W.FireEvent("PLAYER_DEAD"))
    check("popup dostane kanonicke jmeno", captured and captured.name == "Xyz-Golemagg",
        captured and captured.name)

    ns.AddEnemy(captured.name, captured)
    check("AddEnemy uklada kanonicky klic", ns.db.enemies["Xyz-Golemagg"] ~= nil)
    check("zona se ulozi", ns.db.enemies["Xyz-Golemagg"].lastZone == "Hillsbrad Foothills")
end

do
    local ns = W.Startup(v2db({}))
    W.instanceType = "pvp"
    W.guids["Player-2-XYZ"] = { class = "ROGUE", race = "Orc", name = "Xyz" }
    local captured = nil
    ns.ShowAddEnemyPopup = function(info) captured = info end
    clog{ subevent = "SPELL_DAMAGE", sourceGUID = "Player-2-XYZ", sourceName = "Xyz",
          sourceFlags = HOSTILE_PLAYER, destGUID = W.playerGUID, destName = "Cy" }
    W.FireEvent("PLAYER_DEAD")
    check("smrt v battlegroundu se defaultne ignoruje", captured == nil)
end

---------------------------------------------------------------------------
say("\n-- guild sharing --")
---------------------------------------------------------------------------
do
    local ns = W.Startup(v2db({ ["Celu-Golemagg"] = { kills = 2, lastKill = 100, class = "ROGUE" } }))
    ns.db.settings.shareEnabled = true
    ns.ShowWarning = function() end
    W.units.target = { name = "Celu", realm = "", guid = "g", level = 60, class = "ROGUE", isEnemy = true }
    W.FireEvent("PLAYER_TARGET_CHANGED")
    noErrors("odeslani alertu nespadne", W.Advance(5))
    local sent = W.addonMessages[1]
    check("alert odesel pres C_ChatInfo", sent ~= nil and sent.prefix == "PvPEnemy" and sent.channel == "GUILD")
    check("zprava nese verzi protokolu", sent ~= nil and sent.msg:match("^1\tALERT\t") ~= nil, sent and sent.msg)
    check("zprava nese kanonicke jmeno", sent ~= nil and sent.msg:find("Celu-Golemagg", 1, true) ~= nil, sent and sent.msg)
end

do
    local ns = W.Startup(v2db({}))
    W.printed = {}
    W.FireEvent("CHAT_MSG_ADDON", "PvPEnemy", "1\tALERT\t|cffff0000Evil|Hitem:1:0|h[hack]|h\t5\tROGUE", "GUILD", "Guildie-Golemagg")
    local out = W.Output()
    check("prijaty alert se vypise", out:find("spotted", 1, true) ~= nil, out)
    check("escape sekvence jsou odstranene (|h)", out:find("|h", 1, true) == nil, out)
    check("escape sekvence jsou odstranene (|H)", out:find("|H", 1, true) == nil, out)
end

do
    W.Startup(v2db({}))
    W.printed = {}
    W.FireEvent("CHAT_MSG_ADDON", "PvPEnemy", "2\tALERT\tCelu-Golemagg\t5\tROGUE", "GUILD", "Guildie-Golemagg")
    check("jina verze protokolu se ignoruje", W.Output():find("spotted", 1, true) == nil, W.Output())

    W.printed = {}
    W.FireEvent("CHAT_MSG_ADDON", "PvPEnemy", "1\tGARBAGE\tnonsense", "GUILD", "Guildie-Golemagg")
    check("nesmyslna zprava se ignoruje", W.Output():find("spotted", 1, true) == nil, W.Output())
end

do
    W.Startup(v2db({}))
    W.printed = {}
    -- Our own broadcast comes back as "Cy-Golemagg" while UnitName gives "Cy".
    W.FireEvent("CHAT_MSG_ADDON", "PvPEnemy", "1\tALERT\tCelu-Golemagg\t5\tROGUE", "GUILD", "Cy-Golemagg")
    check("vlastni zprava se ignoruje i s realmem v senderovi", W.Output():find("spotted", 1, true) == nil, W.Output())
end

do
    W.Startup(v2db({}))
    W.printed = {}
    W.FireEvent("CHAT_MSG_ADDON", "PvPEnemy", "1\tALERT\tAaa-Golemagg\t5\tROGUE", "GUILD", "Spammer-Golemagg")
    W.FireEvent("CHAT_MSG_ADDON", "PvPEnemy", "1\tALERT\tBbb-Golemagg\t5\tROGUE", "GUILD", "Spammer-Golemagg")
    W.FireEvent("CHAT_MSG_ADDON", "PvPEnemy", "1\tALERT\tCcc-Golemagg\t5\tROGUE", "GUILD", "Spammer-Golemagg")
    local n = select(2, W.Output():gsub("spotted", ""))
    check("throttle na odesilatele omezi spam (1 z 3)", n == 1, n)
end

do
    local ns = W.Startup(v2db({ ["Celu-Golemagg"] = { kills = 1, lastKill = 100 } }))
    W.guild = { { name = "Guildie-Golemagg", online = true } }
    local popup = nil
    ns.ShowRevengePopup = function(enemy, friend) popup = { enemy = enemy, friend = friend } end
    W.FireEvent("CHAT_MSG_ADDON", "PvPEnemy", "1\tALERT\tCelu-Golemagg\t5\tROGUE", "GUILD", "Guildie-Golemagg")
    clog{ subevent = "PARTY_KILL", sourceGUID = W.playerGUID, sourceName = "Cy",
          destGUID = "Player-2-CELU", destName = "Celu" }
    check("zabiti sdileneho nepritele otevre revenge popup", popup ~= nil and popup.friend == "Guildie-Golemagg",
        popup and popup.friend)

    ns.SendRevengeWhisper("Celu-Golemagg", "Guildie-Golemagg")
    check("whisper odesel online guildmatovi", W.whispers[1] ~= nil and W.whispers[1].target == "Guildie-Golemagg")

    W.guild = { { name = "Guildie-Golemagg", online = false } }
    local before = #W.whispers
    ns.SendRevengeWhisper("Celu-Golemagg", "Guildie-Golemagg")
    check("offline guildmatovi se whisper neposila", #W.whispers == before)
end

---------------------------------------------------------------------------
say(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
