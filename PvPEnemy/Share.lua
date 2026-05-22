-- Share: Broadcasts enemy alerts to guild members who also have PvPEnemy.
-- Uses random delay + deduplication to prevent broadcast storms.
local addonName, ns = ...

local CHANNEL = "PvPEnemy"
local SEND_DELAY_MIN = 1.0
local SEND_DELAY_MAX = 3.0

local frame = CreateFrame("Frame")
local pendingSends = {}     -- [name] = timer handle
local recentlyReceived = {} -- [name] = true; suppresses re-send for 30s
local sharedBy = {}         -- [enemyName] = senderName (guild member who spotted them)

function ns.InitShare()
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
        if prefix ~= CHANNEL then return end
        if sender == UnitName("player") then return end
        ns.OnShareMessage(message, sender)
    end)
    RegisterAddonMessagePrefix(CHANNEL)
end

-- Called by Scanner when a known enemy is spotted
function ns.ShareAlert(name, enemyData)
    if not ns.db.settings.shareEnabled then return end
    if not IsInGuild() then return end
    if pendingSends[name] then return end
    if recentlyReceived[name] then return end

    local msg = string.format("ALERT\t%s\t%d\t%s", name, enemyData.kills, enemyData.class or "Unknown")
    local delay = SEND_DELAY_MIN + math.random() * (SEND_DELAY_MAX - SEND_DELAY_MIN)

    pendingSends[name] = C_Timer.NewTimer(delay, function()
        pendingSends[name] = nil
        if recentlyReceived[name] then return end
        SendAddonMessage(CHANNEL, msg, "GUILD")
    end)
end

function ns.OnShareMessage(message, sender)
    local msgType, name, kills, class = message:match("^(%S+)\t([^\t]+)\t(%d+)\t([^\t]*)")
    if msgType ~= "ALERT" then return end

    -- Cancel our own pending send for this enemy
    if pendingSends[name] then
        pendingSends[name]:Cancel()
        pendingSends[name] = nil
    end
    recentlyReceived[name] = true
    C_Timer.NewTimer(30, function() recentlyReceived[name] = nil end)

    -- Remember who shared this enemy so we can whisper them if we get revenge
    sharedBy[name] = sender

    local color = ns.ClassColor(class)
    print(string.format("|cffff4444PvP Enemy|r: |cffffff00%s|r spotted |c%s%s|r — killed them %sx. Get revenge!",
        sender, color, name, kills))
end

-- Called by Tracker when we kill a tracked enemy
function ns.OnEnemyKilled(enemyName)
    local friend = sharedBy[enemyName]
    if not friend then return end
    sharedBy[enemyName] = nil
    ns.ShowRevengePopup(enemyName, friend)
end

local function IsGuildMemberOnline(name)
    local baseName = name:match("^([^-]+)") or name
    local numMembers = GetNumGuildMembers()
    for i = 1, numMembers do
        local memberName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if memberName then
            local memberBase = memberName:match("^([^-]+)") or memberName
            if memberBase == baseName then
                return online
            end
        end
    end
    return false
end

function ns.SendRevengeWhisper(enemyName, friendName)
    if not IsGuildMemberOnline(friendName) then
        print("|cffff4444PvP Enemy|r: |cffffff00" .. friendName .. "|r is offline — can't send revenge message.")
        return
    end
    local msg = "I avenged you! " .. enemyName .. " is dead."
    SendChatMessage(msg, "WHISPER", nil, friendName)
    print("|cffff4444PvP Enemy|r: Whisper sent to |cffffff00" .. friendName .. "|r.")
end
