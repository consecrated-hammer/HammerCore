package.path = "./tests/hammercore/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- Load the addon exactly as its TOC does, then fire ADDON_LOADED.
wow.Install({ {{NAME}} = { Version = "0.1.0" } })
local ns = wow.LoadHammerCore("Libs/HammerCore", "{{NAME}}")
for _, file in ipairs({ "Core.lua", "Options.lua" }) do
    assert(loadfile(file))("{{NAME}}", ns)
end
local loader
for _, frame in ipairs(wow.frames) do
    if frame.scripts.OnEvent then loader = frame end
end
loader.scripts.OnEvent(loader, "ADDON_LOADED", "{{NAME}}")

equal(wow.LastPrint(), "{{NAME}} v0.1.0 loaded - type /{{COMMAND}} for settings, /{{COMMAND}} help for commands",
    "the standard login message prints")
SlashCmdList.{{KEY}}("")
equal(ns.HammerCore.Settings:IsShown(), true, "the bare command opens settings")
equal(next(ns.HammerCore.Settings.errors), nil, "every settings page builds")
SlashCmdList.{{KEY}}("hello")
equal(wow.LastPrint(), "{{NAME}}: hello", "addon commands run")

io.write("{{SLUG}} tests passed\n")
