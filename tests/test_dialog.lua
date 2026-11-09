package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

wow.Install({ TestAddon = { Version = "1.0.0" } })
local ns = wow.LoadHammerCore("src", "TestAddon")
local HC = ns.HammerCore
HC:Init({ name = "TestAddon", command = "testaddon", icon = "Interface\\Icons\\TestLogo",
    db = function() return {} end })

local url = "https://buymeacoffee.com/consecratedhammer"
HC.Dialog:Link({ title = "Buy me a coffee", url = url, icon = "Coffee.tga" })
local f = HC.Dialog.frame
equal(f.box:GetText(), url, "the whole link is in the box")
equal(f.width, 420, "a link dialog is wide enough for the URL")
equal(f.logo:IsShown(), true, "the addon logo shows")
equal(f.badge:IsShown(), true, "the destination badge shows")
equal(f.badge.texture, HC.Theme.Media("Coffee.tga"), "the badge is the destination's icon")

HC.Dialog:Confirm({ text = "Sure?" })
equal(f.width, 340, "a plain question keeps its size")
equal(f.logo:IsShown(), false, "no logo on a plain question")
equal(f.badge:IsShown(), false, "no badge on a plain question")

HC.Dialog:Link({ title = "Somewhere", url = url })
equal(f.badge:IsShown(), false, "a link without an icon shows the logo alone")
print("test_dialog: ok")

-- Section headers can lead with an icon; a function icon can come and go.
do
    local panel = CreateFrame("Frame")
    panel.hcRefresh = {}
    local plain = HC.UI.Header(panel, "Plain", -4)
    equal(plain.hcIcon, nil, "a header without an icon draws none")
    local fixed = HC.UI.Header(panel, "Macro", -40, "Interface\\Icons\\INV_Misc_Note_01")
    equal(fixed.hcIcon.texture, "Interface\\Icons\\INV_Misc_Note_01", "a header draws its icon")
    local value = nil
    local dynamic = HC.UI.Header(panel, "Racial", -80, function() return value end)
    equal(dynamic.hcIcon:IsShown(), false, "no icon yet hides it")
    value = 12345
    for _, fn in ipairs(panel.hcRefresh) do fn() end
    equal(dynamic.hcIcon:IsShown(), true, "the icon appears on refresh")
    equal(dynamic.hcIcon.texture, 12345, "and shows the new texture")
end
print("test_dialog headers: ok")
