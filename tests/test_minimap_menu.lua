package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function addon(overrides, profiles)
    wow.Install({ TestAddon = { Version = "1.0.0" } })
    local saved = {}
    local ns = wow.LoadHammerCore("src", "TestAddon")
    local HC = ns.HammerCore
    local spec = { name = "TestAddon", command = "testaddon", icon = "icon", db = function() return saved end }
    for key, value in pairs(overrides or {}) do spec[key] = value end
    HC:Init(spec)
    if profiles then
        UnitName = function() return "Tester" end
        GetRealmName = function() return "Realm" end
        IsInRaid = function() return false end
        GetNumGroupMembers = function() return 0 end
        IsInInstance = function() return false, "none" end
        HC.Profiles:Setup({ groups = { { key = "all", label = "All", keys = { "size" } } },
            defaults = function() return { size = 1 } end, seed = { { name = "Main", values = {} } },
            active = "Main", apply = function() end })
        HC.Profiles:NewPage({})
        HC.Profiles:Ready()
    end
    HC:Start()
    return HC, saved
end

-- The labels of the open menu's shown rows, with "-" for each line.
local function menuLabels(HC)
    local labels = {}
    for _, item in ipairs(HC.Menu.items) do
        if item:IsShown() then labels[#labels + 1] = item.label.text end
    end
    return table.concat(labels, "|")
end

local function menuRow(HC, text)
    for _, item in ipairs(HC.Menu.items) do
        if item:IsShown() and item.label.text == text then return item end
    end
end

local function rulesShown(HC)
    local count = 0
    for _, rule in ipairs(HC.Menu.rules) do
        if rule:IsShown() then count = count + 1 end
    end
    return count
end

-- Defaults: right-click opens the menu with settings first.
do
    local HC = addon()
    equal(HC.State().minimapRightClick, "menu", "right-click defaults to the menu")
    equal(HC.Minimap.RightClickLabel(), "menu", "tooltip says menu")
    wow.Click(HC.Minimap.button, "RightButton")
    equal(HC.Menu:IsShown(), true, "right-click opens the menu")
    equal(menuLabels(HC), "TestAddon settings", "settings only, without profiles or addon items")
    equal(rulesShown(HC), 0, "no line without addon items")
    wow.Click(menuRow(HC, "TestAddon settings"))
    equal(HC.Settings:IsShown(), true, "the settings item opens settings")
    equal(HC.Menu:IsShown(), false, "choosing closes the menu")
end

-- Addon items follow a line.
do
    local ran = 0
    local HC = addon({ minimap = { menu = function()
        return { { text = "Hall of Fame", func = function() ran = ran + 1 end },
            { text = "Flight", disabled = true } }
    end } })
    wow.Click(HC.Minimap.button, "RightButton")
    equal(menuLabels(HC), "TestAddon settings|Hall of Fame|Flight", "addon items come after settings")
    equal(rulesShown(HC), 1, "a line before the addon items")
    wow.Click(menuRow(HC, "Hall of Fame"))
    equal(ran, 1, "an addon item runs")
    -- The same menu opens from an addon's own frame.
    HC.Minimap:OpenMenu(UIParent)
    equal(menuLabels(HC), "TestAddon settings|Hall of Fame|Flight", "OpenMenu shows the same items")
end

-- A static table works too, and a broken menu function still leaves settings.
do
    local HC = addon({ minimap = { menu = { { text = "Static" } } } })
    wow.Click(HC.Minimap.button, "RightButton")
    equal(menuLabels(HC), "TestAddon settings|Static", "a table of items")
    local reported
    geterrorhandler = function() return function(err) reported = err end end
    HC = addon({ minimap = { menu = function() error("boom") end } })
    wow.Click(HC.Minimap.button, "RightButton")
    equal(menuLabels(HC), "TestAddon settings", "a failing menu function keeps the defaults")
    equal(reported ~= nil, true, "the error is reported")
    geterrorhandler = nil
end

-- Profiles: an item that opens the profiles page.
do
    local HC = addon(nil, true)
    wow.Click(HC.Minimap.button, "RightButton")
    equal(menuLabels(HC), "TestAddon settings|Profiles", "profiles addons get a Profiles item")
    wow.Click(menuRow(HC, "Profiles"))
    equal(HC.Settings.selected, "Profiles", "the item opens the profiles page")
end

-- The setting: Settings makes right-click open settings.
do
    local HC = addon()
    HC.Settings:Show("Visibility")
    local row = HC.Settings.pages.Visibility.bodies.Visibility.hcRows["Minimap right-click"]
    equal(row ~= nil, true, "Visibility has a Minimap right-click row")
    HC.Settings:Hide()
    HC.State().minimapRightClick = "settings"
    equal(HC.Minimap.RightClickLabel(), "settings", "tooltip follows the setting")
    wow.Click(HC.Minimap.button, "RightButton")
    equal(HC.Settings:IsShown(), true, "right-click opens settings")
    equal(HC.Menu:IsShown(), false, "no menu in Settings mode")
    wow.Click(HC.Minimap.button, "RightButton")
    equal(HC.Settings:IsShown(), false, "right-click again closes settings")
    HC.State().minimapRightClick = "bogus"
    equal(HC.State().minimapRightClick, "menu", "a bad value is repaired")
end

-- An addon's own rightClick still wins, and HammerCore's setting stays out of the way.
do
    local clicks = 0
    local HC = addon({ minimap = { rightClick = function() clicks = clicks + 1 end, rightClickLabel = "profiles",
        menu = function() return { { text = "Unused" } } end } })
    wow.Click(HC.Minimap.button, "RightButton")
    equal(clicks, 1, "the addon's rightClick runs")
    equal(HC.Menu:IsShown(), false, "no default menu")
    equal(HC.Minimap.RightClickLabel(), "profiles", "the addon's label is kept")
    HC.Settings:Show("Visibility")
    local rows = HC.Settings.pages.Visibility.bodies.Visibility.hcRows
    equal(rows["Minimap right-click"], nil, "no HammerCore right-click row")
end

io.write("test_minimap_menu: ok\n")
