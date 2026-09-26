local addonName, ns = ...
local HC = ns.HammerCore

-- HammerCore supplies settings, commands, the minimap button, the startup
-- message, Theme, Commands, Troubleshooting and About.  This file declares
-- what is specific to {{NAME}}.

ns.DEFAULTS = {
    enabled = true,
}

HC:Init({
    name = "{{NAME}}",
    command = "{{COMMAND}}",
    savedVariable = "{{NAME}}DB",
    icon = "Interface\\AddOns\\{{NAME}}\\Textures\\{{NAME}}",
    db = function() return ns.db end,
    diagnostics = function()
        return "Enabled: " .. tostring(ns.db.enabled)
    end,
    status = function()
        return "Enabled: " .. (ns.db.enabled and "yes" or "no")
    end,
    about = {
        note = "NOTE",
        tips = { "Freshly forged." },
    },
})
ns.Print = HC.Print

HC.Commands:Add({
    name = "hello", section = "{{NAME}}", help = "Say hello",
    run = function() HC.Print("hello") end,
})

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, loaded)
    if loaded ~= addonName then return end
    if type({{NAME}}DB) ~= "table" then {{NAME}}DB = {} end
    ns.db = {{NAME}}DB
    for key, value in pairs(ns.DEFAULTS) do
        if ns.db[key] == nil then ns.db[key] = value end
    end
    HC:Start()
    self:UnregisterEvent("ADDON_LOADED")
end)
