-- Minimal stand-in for the WoW API, enough to load PvPEnemy outside the game
-- and drive it through events. Not a simulator — just the surface the addon
-- actually touches, plus hooks so tests can fire events and inspect output.

local W = {}

-- Kept before the global print is replaced by the capturing stub, so the test
-- runner can still write to the console.
W.realPrint = print

local scriptDir = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
-- Override to run the suite against a different copy of the addon, e.g. an
-- older revision, to confirm the tests actually fail on the bugs they cover.
W.addonDir = os.getenv("PVPE_ADDON_DIR") or (scriptDir .. "/../PvPEnemy")

---------------------------------------------------------------------------
-- Mutable world state, reset between scenarios
---------------------------------------------------------------------------
function W.Reset()
    W.printed = {}
    W.realm = "Golemagg"
    W.playerName = "Cy"
    W.playerGUID = "Player-1-CY"
    W.zone = "Hillsbrad Foothills"
    W.instanceType = "none"
    W.inGuild = true
    W.guild = {}            -- { { name = "X-Golemagg", online = true }, ... }
    W.units = {
        player = { name = W.playerName, realm = "", guid = "Player-1-CY", level = 60, class = "WARRIOR" },
    }
    W.guids = {}            -- [guid] = { class =, race =, name =, realm = }
    W.combatLog = {}
    W.timers = {}
    W.now = 1000
    W.addonMessages = {}
    W.whispers = {}
    W.registeredPrefixes = {}
    W.sounds = 0
    W.frames = {}

    _G.PvPEnemyDB = nil
    _G.SlashCmdList = {}
    math.randomseed(42)
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
-- Any method we did not think of becomes a no-op returning the object, which
-- is enough for the layout calls in UI.lua.
local frameMeta = {
    __index = function(t, k)
        local f = function(self) return self end
        rawset(t, k, f)
        return f
    end,
}

local function NewFrame(_, name)
    local f = { _events = {}, _scripts = {}, _attributes = {} }
    function f:RegisterEvent(e) self._events[e] = true end
    function f:UnregisterEvent(e) self._events[e] = nil end
    function f:IsEventRegistered(e) return self._events[e] == true end
    function f:SetScript(s, fn) self._scripts[s] = fn end
    function f:GetScript(s) return self._scripts[s] end
    -- Secure-button attributes (type, unit, macrotext, ...). The generic
    -- no-op catch-all below would silently swallow these, so they need
    -- explicit storage for tests to assert against.
    function f:SetAttribute(k, v) self._attributes[k] = v end
    function f:GetAttribute(k) return self._attributes[k] end
    setmetatable(f, frameMeta)
    table.insert(W.frames, f)
    if name then _G[name] = f end
    return f
end

-- Returns a list of error strings; empty means every handler ran clean.
function W.FireEvent(event, ...)
    local errors = {}
    local snapshot = {}
    for i, f in ipairs(W.frames) do snapshot[i] = f end
    for _, f in ipairs(snapshot) do
        if f._events[event] and f._scripts.OnEvent then
            local ok, err = pcall(f._scripts.OnEvent, f, event, ...)
            if not ok then table.insert(errors, tostring(err)) end
        end
    end
    return errors
end

---------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------
function W.Advance(seconds)
    W.now = W.now + seconds
    local due, remaining = {}, {}
    for _, t in ipairs(W.timers) do
        if t._cancelled then
            -- drop
        elseif t._at <= W.now then
            table.insert(due, t)
        else
            table.insert(remaining, t)
        end
    end
    W.timers = remaining
    local errors = {}
    for _, t in ipairs(due) do
        local ok, err = pcall(t._fn)
        if not ok then table.insert(errors, tostring(err)) end
    end
    return errors
end

---------------------------------------------------------------------------
-- Global API surface
---------------------------------------------------------------------------
_G.CreateFrame = NewFrame
_G.UIParent = setmetatable({}, frameMeta)

_G.C_Timer = {
    NewTimer = function(delay, fn)
        local t = { _fn = fn, _at = W.now + delay, _cancelled = false }
        function t:Cancel() self._cancelled = true end
        table.insert(W.timers, t)
        return t
    end,
}
_G.C_Timer.After = function(delay, fn) return _G.C_Timer.NewTimer(delay, fn) end

_G.GetTime = function() return W.now end
_G.time = os.time
_G.date = os.date

_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    table.insert(W.printed, table.concat(parts, " "))
end

_G.CopyTable = function(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = type(v) == "table" and _G.CopyTable(v) or v
    end
    return out
end

_G.wipe = function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

_G.GetRealmName = function() return W.realm end
_G.GetNormalizedRealmName = function() return (W.realm:gsub("%s+", "")) end
_G.GetZoneText = function() return W.zone end
_G.IsInInstance = function() return W.instanceType ~= "none", W.instanceType end

_G.UnitExists = function(id) return W.units[id] ~= nil end
_G.UnitIsPlayer = function(id) local u = W.units[id]; return u ~= nil and u.isPlayer ~= false end
_G.UnitIsEnemy = function(_, id) local u = W.units[id]; return u ~= nil and u.isEnemy == true end
_G.UnitName = function(id)
    local u = W.units[id]
    if not u then return nil end
    return u.name, u.realm
end
_G.UnitLevel = function(id) local u = W.units[id]; return u and u.level or 0 end
_G.UnitClass = function(id) local u = W.units[id]; return u and u.class, u and u.class end
_G.UnitGUID = function(id)
    if id == "player" then return W.playerGUID end
    local u = W.units[id]
    return u and u.guid or nil
end

_G.GetPlayerInfoByGUID = function(guid)
    local g = W.guids[guid]
    if not g then return nil end
    return g.class, g.class, g.race, g.race, "male", g.name, g.realm
end

_G.CombatLogGetCurrentEventInfo = function() return unpack(W.combatLog, 1, 11) end
_G.COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400
_G.COMBATLOG_OBJECT_REACTION_HOSTILE = 0x00000040

_G.IsInGuild = function() return W.inGuild end
_G.GetNumGuildMembers = function() return #W.guild end
_G.GetGuildRosterInfo = function(i)
    local m = W.guild[i]
    if not m then return nil end
    return m.name, "Member", 4, 60, "Warrior", "Orgrimmar", "", "", m.online
end

_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix)
        W.registeredPrefixes[prefix] = true
        return true
    end,
    SendAddonMessage = function(prefix, msg, channel)
        table.insert(W.addonMessages, { prefix = prefix, msg = msg, channel = channel })
    end,
}

_G.SendChatMessage = function(msg, chatType, _, target)
    table.insert(W.whispers, { msg = msg, chatType = chatType, target = target })
end

_G.PlaySound = function() W.sounds = W.sounds + 1 end
_G.CLASS_ICON_TCOORDS = {}
_G.GameTooltip = setmetatable({}, frameMeta)

if not _G.bit then
    _G.bit = { band = function(a, b) return ((a % (2 * b)) >= b) and b or 0 end }
end

---------------------------------------------------------------------------
-- Loading the addon
---------------------------------------------------------------------------
local FILES = { "Core.lua", "Tracker.lua", "Scanner.lua", "UI.lua", "Share.lua" }

-- Loads the addon files in TOC order against a fresh namespace.
function W.LoadAddon()
    local ns = {}
    for _, name in ipairs(FILES) do
        local path = W.addonDir .. "/" .. name
        local chunk, err = loadfile(path)
        if not chunk then
            error("syntax error in " .. name .. ": " .. tostring(err), 0)
        end
        local ok, runErr = pcall(chunk, "PvPEnemy", ns)
        if not ok then
            error("load-time error in " .. name .. ": " .. tostring(runErr), 0)
        end
    end
    return ns
end

-- Full startup: load files, fire ADDON_LOADED and PLAYER_LOGIN.
-- Returns the namespace and any handler errors.
function W.Startup(savedVars)
    W.Reset()
    if savedVars then _G.PvPEnemyDB = savedVars end
    local ns = W.LoadAddon()
    local errors = W.FireEvent("ADDON_LOADED", "PvPEnemy")
    for _, e in ipairs(W.FireEvent("PLAYER_LOGIN")) do table.insert(errors, e) end
    return ns, errors
end

function W.Output()
    return table.concat(W.printed, "\n")
end

function W.Slash(cmd)
    local handler = _G.SlashCmdList["PVPENEMY"]
    if not handler then return { "no slash handler registered" } end
    local ok, err = pcall(handler, cmd)
    return ok and {} or { tostring(err) }
end

W.Reset()
return W
