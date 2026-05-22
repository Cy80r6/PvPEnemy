-- Share: Broadcasts enemy alerts to guild members who also have PvPEnemy.
-- Uses random delay + deduplication to prevent broadcast storms.
local addonName, ns = ...

local CHANNEL = "PvPEnemy"
local SEND_DELAY_MIN = 1.0
local SEND_DELAY_MAX = 3.0

local frame = CreateFrame("Frame")
local pendingSends = {}  -- [name] = timer handle; cancelled if guild beats us to it
local recentlyReceived = {}  -- [name] = true; suppresses our own pending send

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
    -- Already have a pending send for this enemy, skip
    if pendingSends[name] then return end
    -- Someone in guild already announced this recently, skip
    if recentlyReceived[name] then return end

    local msg = string.format("ALERT\t%s\t%d\t%s", name, enemyData.kills, enemyData.class or "Unknown")
    local delay = SEND_DELAY_MIN + math.random() * (SEND_DELAY_MAX - SEND_DELAY_MIN)

    pendingSends[name] = C_Timer.NewTimer(delay, function()
        pendingSends[name] = nil
        -- Double-check: someone may have sent while we were waiting
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
    -- Mark as recently received so we don't re-send on next spot
    recentlyReceived[name] = true
    C_Timer.NewTimer(30, function() recentlyReceived[name] = nil end)

    local color = ns.ClassColor(class)
    print(string.format("|cffff4444PvP Enemy|r: |cffffff00%s|r spotted |c%s%s|r (killed them %sx)",
        sender, color, name, kills))
end
