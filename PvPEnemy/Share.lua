-- Share: Broadcasts enemy alerts to guild members who also have PvPEnemy.
-- Uses random delay + deduplication to prevent broadcast storms.
local addonName, ns = ...

local CHANNEL = "PvPEnemy"
local PROTOCOL = "1"        -- bumped whenever the wire format changes
local SEND_DELAY_MIN = 1.0
local SEND_DELAY_MAX = 3.0
local SENDER_COOLDOWN = 5   -- seconds; one printed alert per guildmate

local MAX_NAME_LEN = 48
local MAX_KILLS = 99999

-- RegisterAddonMessagePrefix / SendAddonMessage were moved into C_ChatInfo in
-- 8.0.1 and the globals no longer exist on the Classic client. The fallbacks
-- are only there in case an old client still has them.
local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
local SendAddonMsg = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage

local frame = CreateFrame("Frame")
local pendingSends = {}     -- [name] = timer handle
local recentlyReceived = {} -- [name] = true; suppresses re-send for 30s
local sharedBy = {}         -- [enemyName] = senderName (guild member who spotted them)
local senderLastAlert = {}  -- [sender] = GetTime() of last alert we printed

function ns.InitShare()
    if type(RegisterPrefix) ~= "function" or type(SendAddonMsg) ~= "function" then
        error("addon message API unavailable on this client")
    end
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
        if prefix ~= CHANNEL then return end
        -- sender arrives as "Name-Realm"; our own name may not, so compare canonically.
        if ns.Canon(sender) == ns.Canon(UnitName("player")) then return end
        ns.OnShareMessage(message, sender)
    end)
    RegisterPrefix(CHANNEL)
    ns.shareReady = true
end

---------------------------------------------------------------------------
-- Untrusted input handling
--
-- Anything arriving over the addon channel was written by another player's
-- client. Strip the UI escape marker so a crafted name cannot inject
-- hyperlinks or textures into our chat frame, and bound the lengths.
---------------------------------------------------------------------------
local function Sanitize(s, maxLen)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|", ""):gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" or #s > maxLen then return nil end
    return s
end

-- Called by Scanner when a known enemy is spotted
function ns.ShareAlert(name, enemyData)
    if not ns.shareReady then return end
    if not ns.db.settings.shareEnabled then return end
    if not IsInGuild() then return end
    if pendingSends[name] then return end
    if recentlyReceived[name] then return end

    local kills = math.min(math.max(math.floor(tonumber(enemyData.kills) or 0), 0), MAX_KILLS)
    local class = ns.IsKnownClass(enemyData.class) and enemyData.class or "Unknown"
    local msg = string.format("%s\tALERT\t%s\t%d\t%s", PROTOCOL, name, kills, class)
    local delay = SEND_DELAY_MIN + math.random() * (SEND_DELAY_MAX - SEND_DELAY_MIN)

    pendingSends[name] = C_Timer.NewTimer(delay, function()
        pendingSends[name] = nil
        if recentlyReceived[name] then return end
        SendAddonMsg(CHANNEL, msg, "GUILD")
    end)
end

function ns.OnShareMessage(message, sender)
    if type(message) ~= "string" then return end

    local version, msgType, rest = message:match("^(%d+)\t(%u+)\t(.*)$")
    if version ~= PROTOCOL then return end   -- silently ignore other protocol versions
    if msgType ~= "ALERT" then return end

    local rawName, rawKills, rawClass = rest:match("^([^\t]+)\t(%d+)\t([^\t]*)$")
    local name = Sanitize(rawName, MAX_NAME_LEN)
    if not name or name:find("%s") then return end

    local kills = tonumber(rawKills)
    if not kills or kills < 0 or kills > MAX_KILLS then return end
    kills = math.floor(kills)

    local class = Sanitize(rawClass, 16)
    if not ns.IsKnownClass(class) then class = "Unknown" end

    -- Cancel our own pending send for this enemy
    if pendingSends[name] then
        pendingSends[name]:Cancel()
        pendingSends[name] = nil
    end
    recentlyReceived[name] = true
    C_Timer.NewTimer(30, function() recentlyReceived[name] = nil end)

    -- Remember who shared this enemy so we can whisper them if we get revenge
    sharedBy[name] = sender

    -- One printed alert per guildmate per cooldown, so a misbehaving client
    -- cannot flood the chat frame by cycling names.
    local now = GetTime()
    if senderLastAlert[sender] and (now - senderLastAlert[sender]) < SENDER_COOLDOWN then
        return
    end
    senderLastAlert[sender] = now

    local color = ns.ClassColor(class)
    print(string.format("|cffff4444PvP Enemy|r: |cffffff00%s|r spotted |c%s%s|r — killed them %dx. Get revenge!",
        ns.ShortName(sender), color, ns.ShortName(name), kills))
end

-- Called by Tracker when we kill a tracked enemy
function ns.OnEnemyKilled(enemyName)
    local friend = sharedBy[enemyName]
    if not friend then return end
    sharedBy[enemyName] = nil
    if ns.ShowRevengePopup then
        ns.ShowRevengePopup(enemyName, friend)
    end
end

-- Returns true/false when we can tell, or nil when the roster is not loaded.
local function IsGuildMemberOnline(name)
    local numMembers = GetNumGuildMembers()
    if not numMembers or numMembers == 0 then return nil end

    local target = ns.Canon(name)
    for i = 1, numMembers do
        local memberName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if memberName and ns.Canon(memberName) == target then
            return online and true or false
        end
    end
    return false
end

function ns.SendRevengeWhisper(enemyName, friendName)
    if IsGuildMemberOnline(friendName) == false then
        print("|cffff4444PvP Enemy|r: |cffffff00" .. ns.ShortName(friendName) .. "|r is offline — can't send revenge message.")
        return
    end
    local msg = "I avenged you! " .. ns.ShortName(enemyName) .. " is dead."
    SendChatMessage(msg, "WHISPER", nil, friendName)
    print("|cffff4444PvP Enemy|r: Whisper sent to |cffffff00" .. ns.ShortName(friendName) .. "|r.")
end
