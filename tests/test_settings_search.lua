package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local ARROW = " \226\128\186 "

local function addon(saved)
    wow.Install({ TestAddon = { Version = "1.0.0" } })
    saved = saved or {}
    local ns = wow.LoadHammerCore("src", "TestAddon")
    local HC = ns.HammerCore
    local values = { scale = 1, sound = true, colour = "RED" }
    HC:Init({ name = "TestAddon", command = "testaddon", icon = "icon", db = function() return saved end })
    HC.Settings:NewPage({ name = "General", description = "The basics." }, function(panel, y)
        _, y = HC.UI.Check(panel, "Play sound", "Play a chime when a buff drops.", y,
            function() return values.sound end, function(value) values.sound = value end)
        _, y = HC.UI.Slider(panel, "Icon scale", "How big the icons are.", y, 0.5, 2, 0.1,
            function() return values.scale end, function(value) values.scale = value end)
        return y
    end)
    HC.Settings:NewPage({ name = "Display", tabs = {
        { name = "Bars", build = function(panel, y)
            _, y = HC.UI.Dropdown(panel, "Bar colour", "Colour of the |cffff0000cooldown|r bar.", y,
                { "RED", "BLUE" }, { "Red", "Blue" },
                function() return values.colour end, function(value) values.colour = value end)
            return y
        end },
        { name = "Icons", build = function(panel, y)
            local row
            row, y = HC.UI.Check(panel, "Hidden row", "Never matches.", y, function() return false end, function() end)
            row:Hide()
            _, y = HC.UI.Check(panel, "Desaturate", "Grey out on cooldown.", y,
                function() return false end, function() end)
            return y
        end },
    } })
    HC:Start()
    return HC, saved
end

local function texts(matches)
    local list = {}
    for _, match in ipairs(matches) do list[#list + 1] = match.text end
    return table.concat(list, "|")
end

-- The index: labels, tooltips, tabs and pages, best match first.
do
    local HC = addon()
    equal(#HC.Settings:Search("sound"), 0, "nothing before the window is built")
    HC.Settings:Show()
    equal(texts(HC.Settings:Search("icon scale")), "General" .. ARROW .. "Icon scale", "a label")
    equal(texts(HC.Settings:Search("chime")), "General" .. ARROW .. "Play sound", "tooltip text")
    equal(texts(HC.Settings:Search("COOLDOWN bar")), "Display" .. ARROW .. "Bars" .. ARROW .. "Bar colour",
        "colour codes are stripped and case ignored")
    local desaturate
    for _, match in ipairs(HC.Settings:Search("icons")) do
        if match.label == "Desaturate" then desaturate = match end
    end
    equal(desaturate ~= nil, true, "a tab name finds its rows")
    equal(desaturate.tab, "Icons", "the match knows its tab")
    equal(texts(HC.Settings:Search("hidden row")), "", "hidden rows are left out")
    local scale = HC.Settings:Search("scale")
    equal(scale[1].label, "Icon scale", "a label match ranks above a tooltip match")
    equal(#HC.Settings:Search("   "), 0, "blank finds nothing")
    equal(#HC.Settings:Search("e", 3), 3, "the limit applies")
    equal(#HC.Settings:Search("e") <= HC.Settings.SEARCH_LIMIT, true, "at most eight by default")
    equal(texts(HC.Settings:Search("startup message")), "Visibility" .. ARROW .. "Show startup message",
        "shared pages are indexed")
end

-- The box: typing lists matches, picking one focuses the row, Esc clears.
do
    local HC = addon()
    HC.Settings:Show("General")
    local box, results = HC.Settings.searchBox, HC.Settings.searchResults
    equal(box:IsShown(), true, "the box shows by default")
    equal(box.placeholder.text, "Search settings", "placeholder text")
    box:SetText("desat")
    box.scripts.OnTextChanged(box, true)
    equal(results:IsShown(), true, "typing opens the results")
    equal(box.placeholder:IsShown(), false, "the placeholder hides while typing")
    local first = results.rows[1]
    equal(first.label.text, "Display" .. ARROW .. "Icons" .. ARROW .. "Desaturate", "the result reads Page > Tab > Label")
    local focused
    local focus = HC.Settings.Focus
    HC.Settings.Focus = function(self, page, setting, tab)
        focused = page .. "/" .. setting .. "/" .. tostring(tab)
        return focus(self, page, setting, tab)
    end
    wow.Click(first)
    equal(focused, "Display/Desaturate/Icons", "picking calls Focus with page, label and tab")
    equal(HC.Settings.selected, "Display", "the page opens")
    equal(HC.Settings.pages.Display.selectedTab, "Icons", "on the right tab")
    equal(results:IsShown(), false, "picking closes the results")
    equal(box:GetText(), "", "and clears the box")

    box:SetText("nothing like this")
    box.scripts.OnTextChanged(box, true)
    equal(results:IsShown(), true, "no matches still answers")
    equal(results.empty:IsShown(), true, "with No matches")
    box.scripts.OnEscapePressed(box)
    equal(box:GetText(), "", "Esc clears the text")
    equal(results:IsShown(), false, "Esc closes the results")

    box:SetText("play")
    box.scripts.OnTextChanged(box, true)
    box.scripts.OnEnterPressed(box)
    equal(HC.Settings.selected, "General", "Enter opens the first match")

    box:SetText("play")
    box.scripts.OnTextChanged(box, true)
    HC.Settings:Hide()
    equal(results:IsShown(), false, "closing the window closes the results")
    equal(box:GetText(), "", "and clears the search")
end

-- The setting: off hides the box, and it lives on Visibility.
do
    local HC, saved = addon()
    equal(HC.State().settingsSearch, true, "search defaults on")
    HC.Settings:Show("Visibility")
    local row = HC.Settings.pages.Visibility.bodies.Visibility.hcRows["Settings search"]
    equal(row ~= nil, true, "Visibility has a Settings search row")
    row.hcCheckbox.scripts.OnClick(row.hcCheckbox)
    equal(saved.hammerCore.settingsSearch, false, "the switch turns search off")
    equal(HC.Settings.searchBox:IsShown(), false, "the box hides")
    row.hcCheckbox.scripts.OnClick(row.hcCheckbox)
    equal(HC.Settings.searchBox:IsShown(), true, "and comes back")
end
do
    local HC = addon({ hammerCore = { settingsSearch = false } })
    HC.Settings:Show()
    equal(HC.Settings.searchBox:IsShown(), false, "a saved off keeps the box hidden on build")
end

-- Header tools share a row with space for tabs and the description.
do
    local HC = addon()
    local settings = HC.Settings
    settings:Show("General")
    settings.pages.General.spec.headerAction = { text = "Show preview", onClick = function() end }
    settings:RefreshHeaderAction()
    local box, action = settings.searchBox, settings.headerAction
    local anchor = box.points[1]
    equal(anchor[1], "TOPRIGHT", "search sits in the header control row")
    assert(-anchor[5] + box:GetHeight() <= settings.header:GetHeight() - settings.tabBar:GetHeight() - 4,
        "search stays above the tab row with a gap")
    equal(action.points[1][2], box, "preview sits beside search")
    equal(action.points[1][3], "LEFT", "preview stays to the left of search")
    assert(action.points[1][4] < 0, "the controls have a gap")
    equal(action:GetHeight(), box:GetHeight(), "the controls align in height")
    local both = settings.pageDescription:GetWidth()
    settings:Select("Display")
    assert(settings.pageDescription:GetWidth() > both, "description gets room when the action is absent")
    settings:Select("General")
    HC.State().settingsSearch = false
    settings:RefreshSearch()
    equal(action.points[1][1], "TOPRIGHT", "preview moves to the right when search is off")
    equal(action.points[1][2], settings.header, "preview anchors to the header without search")
    assert(settings.pageDescription:GetWidth() > both, "turning search off reclaims description space")
    HC.State().settingsSearch = true
    settings:RefreshSearch()
    equal(action.points[1][2], box, "turning search on restores the shared row")
    equal(settings.pageDescription:GetWidth(), both, "the original space reservation returns")
end

-- Hidden dependent sections stay searchable and focus their visible switch.
do
    local HC = addon()
    local parent, group, nestedParent, nested
    HC.Settings:NewPage({ name = "Dependent" }, function(panel, y)
        parent, y = HC.UI.Check(panel, "Role icons", nil, y, function() return false end, function() end)
        group = CreateFrame("Frame", nil, panel)
        group.hcHeaderOwner, group.hcParentRow = panel.hcHeaderOwner, parent
        group:Hide()
        nestedParent = HC.UI.Check(group, "Role details", nil, 0, function() return false end, function() end)
        nested = CreateFrame("Frame", nil, group)
        nested.hcHeaderOwner, nested.hcParentRow = panel.hcHeaderOwner, nestedParent
        nested:Hide()
        HC.UI.Slider(nested, "Role icon size", nil, 0, 8, 32, 1, function() return 12 end, function() end)
        local orphan = CreateFrame("Frame", nil, panel)
        orphan.hcHeaderOwner = panel.hcHeaderOwner
        orphan:Hide()
        HC.UI.Check(orphan, "Unavailable detail", nil, 0, function() return false end, function() end)
        return y
    end)
    HC.Settings:Show("General")
    equal(#HC.Settings:Search("role icon size"), 1, "hidden nested setting is indexed")
    equal(#HC.Settings:Search("unavailable detail"), 0, "hidden section without a parent is excluded")
    equal(HC.Settings:Focus("Dependent", "Role icon size"), parent, "hidden nested setting focuses visible ancestor")
    equal(HC.Settings.pulser.row, parent, "visible parent pulses")
    group:Show()
    equal(HC.Settings:Focus("Dependent", "Role icon size"), nestedParent, "nearest visible parent is preferred")
    nested:Show()
    local row = HC.Settings.pages.Dependent.bodies.Dependent.hcRows["Role icon size"]
    equal(HC.Settings:Focus("Dependent", "Role icon size"), row, "visible setting focuses itself")
    row:Hide()
    equal(#HC.Settings:Search("role icon size"), 0, "directly hidden row without a parent remains excluded")
    row.hcParentRow = parent
    equal(HC.Settings:Focus("Dependent", "Role icon size"), parent, "directly gated row can name its parent")
    row.hcParentRow = row
    equal(HC.Settings:Focus("Dependent", "Role icon size"), nil, "invalid parent cycle is safely excluded")
end

-- Action buttons and the custom bindings editor participate in search too.
do
    local HC = addon()
    HC.Settings:NewPage({ name = "Bindings" }, function(panel, y)
        _, y = HC.UI.ActionButton(panel, y, "Reset test position", function() end, "Restore placement.")
        return HC.Bindings.Page(panel, y, {
            poolTitle = "Your spells", poolHint = "Mouseover dispel and both dispels.",
            bound = function() return {} end, pool = function() return {} end,
            unbind = function() end, bind = function() return true end, clearAll = function() end,
        })
    end)
    HC.Settings:Show("Bindings")
    assert(not HC.Settings.errors.Bindings, "bindings search fixture builds")
    equal(#HC.Settings:Search("reset test position"), 1, "action buttons register automatically")
    equal(#HC.Settings:Search("mouseover dispel"), 1, "binding pool hints are indexed")
    equal(#HC.Settings:Search("clear all bindings"), 1, "empty binding list still explains clear all")
    local body = HC.Settings.pages.Bindings.bodies.Bindings
    equal(HC.Settings:Focus("Bindings", "Clear all bindings"), body.hcRows["Active bindings"],
        "hidden clear action focuses the binding list")
end

io.write("test_settings_search: ok\n")
