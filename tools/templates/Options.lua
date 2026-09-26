local addonName, ns = ...
local HC = ns.HammerCore
local UI = HC.UI

-- {{NAME}}'s own settings pages.  Standard pages are added by HammerCore.

HC.Settings:NewPage({ name = "General", description = "What {{NAME}} does." }, function(panel, y)
    _, y = UI.Header(panel, "{{NAME}}", y)
    _, y = UI.Check(panel, "Enabled", "Turn {{NAME}} on or off.", y,
        function() return ns.db.enabled end,
        function(value) ns.db.enabled = value end)
    return y
end)
