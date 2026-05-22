-- Share: Broadcasts enemy alerts to party/raid members who also have PvPEnemy.
local addonName, ns = ...

local CHANNEL = "PvPEnemy"
local frame = CreateFrame("Frame")

function ns.InitShare()
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
        if prefix ~= CHANNEL then return end
        if sender == UnitName("player") then return end
        ns.OnShareMessage(message, sender)
    end)
    RegisterAddonMessagePrefix(CHANNEL)
end

-- Called by Scanner when an enemy is spotted, if share is enabled
function ns.ShareAlert(name, enemyData)
    if not ns.db.settings.shareEnabled then return end
    if not (IsInGroup() or IsInRaid()) then return end
    local dist = IsInRaid() and "RAID" or "PARTY"
    local msg = string.format("ALERT\t%s\t%d\t%s", name, enemyData.kills, enemyData.class or "Unknown")
    SendAddonMessage(CHANNEL, msg, dist)
end

function ns.OnShareMessage(message, sender)
    local msgType, name, kills, class = message:match("^(%S+)\t([^\t]+)\t(%d+)\t([^\t]*)")
    if msgType ~= "ALERT" then return end
    local color = ns.ClassColor(class)
    print(string.format("|cffff4444PvP Enemy|r: |cffffff00%s|r spotted |c%s%s|r (killed them %sx)",
        sender, color, name, kills))
end
