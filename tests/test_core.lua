package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function contains(list, needle, label)
    for _, line in ipairs(list) do
        if wow.Plain(line):find(needle, 1, true) then return end
    end
    error(label .. ": no printed line contains " .. needle, 2)
end

local META = { TestAddon = { Version = "1.2.3-dev4", ["X-ReleaseDate"] = "2026-09-26" },
    OtherAddon = { Version = "9.9.9" } }

-- Builds an addon around a fresh HammerCore copy.
local function addon(overrides)
    wow.Install(META)
    local saved = { showStartupMessage = false, minimapAngle = 90, unrelated = true }
    local ns = wow.LoadHammerCore("src", "TestAddon")
    local HC = ns.HammerCore
    local calls = {}
    local spec = {
        name = "TestAddon", command = "testaddon", aliases = { "ta" },
        savedVariable = "TestAddonDB", icon = "icon",
        db = function() return saved end,
        legacy = { startupMessage = "showStartupMessage", minimapAngle = "minimapAngle" },
        diagnostics = function() return "Addon line" end,
        status = function() return "All good" end,
        resetPosition = function() calls.resetPosition = true end,
        toggle = { help = "Show or hide the thing", run = function() calls.toggle = true end },
        minimap = { rightClick = function() calls.rightClick = true end, rightClickLabel = "lock" },
    }
    for key, value in pairs(overrides or {}) do spec[key] = value end
    HC:Init(spec)
    return HC, saved, calls
end

-- ── State migration ───────────────────────────────────────────────────────
do
    local HC, saved = addon()
    local state = HC.State()
    equal(state.startupMessage, false, "legacy startup choice is adopted")
    equal(saved.showStartupMessage, nil, "legacy startup key is removed")
    equal(state.minimapAngle, 90, "legacy minimap angle is adopted")
    equal(state.minimap, true, "missing values take defaults")
    equal(state.theme, "modern", "theme defaults to modern")
    equal(saved.unrelated, true, "unrelated addon keys are untouched")
    saved.hammerCore.settingsPoint = { "NOWHERE", "CENTER", 1, 2 }
    equal(HC.State().settingsPoint, nil, "an invalid settings position is discarded")
    saved.hammerCore.settingsPoint = { "TOPLEFT", "TOPLEFT", 40, -60 }
    equal(HC.State().settingsPoint[3], 40, "a valid settings position is kept")
    saved.hammerCore.theme = "bogus"
    equal(HC.State().theme, "modern", "an unknown theme is repaired")
end

-- ── Login message and chat prefix ─────────────────────────────────────────
do
    local HC = addon()
    equal(HC.LoginMessage(),
        "TestAddon v1.2.3-dev4 loaded - type /testaddon for settings, /testaddon help for commands",
        "login message follows the standard format")
    equal(HC.LoginMessage(true):sub(1, 10), "|cffd4af37", "the login name uses the chat colour")
    HC:Start()
    equal(#wow.printed, 0, "a disabled startup message stays silent")
    HC.State().startupMessage = true
    HC:Start()
    equal(wow.LastPrint(), HC.LoginMessage(), "an enabled startup message prints once")
    HC.Print("hello")
    equal(wow.printed[#wow.printed], "|cffd4af37TestAddon:|r hello", "messages use the gold name prefix")
end

-- ── Slash registration and dispatch ───────────────────────────────────────
do
    local HC, _, calls = addon()
    equal(SLASH_TESTADDON1, "/testaddon", "primary slash command is registered")
    equal(SLASH_TESTADDON2, "/ta", "aliases are registered")
    HC:Start()
    local slash = SlashCmdList.TESTADDON

    slash("")
    equal(HC.Settings:IsShown(), true, "the bare command opens settings")
    HC.Settings:Hide()

    slash("startup off")
    equal(HC.State().startupMessage, false, "startup off")
    slash("STARTUP")
    equal(HC.State().startupMessage, true, "startup with no argument toggles; case is ignored")
    slash("startup maybe")
    equal(wow.LastPrint(), "TestAddon: usage: /testaddon startup [on|off]", "bad arguments print usage")

    slash("minimap off")
    equal(HC.State().minimap, false, "minimap off")
    equal(HC.Minimap.button:IsShown(), false, "minimap off hides the button")
    slash("minimap on")
    equal(HC.Minimap.button:IsShown(), true, "minimap on shows the button")

    slash("theme classic")
    equal(HC.State().theme, "modern", "an unavailable theme is refused")
    equal(wow.LastPrint(), "TestAddon: Classic is not available yet", "the refusal says why")
    slash("theme")
    equal(wow.LastPrint(), "TestAddon: theme modern", "theme with no argument reports the current one")

    slash("reset position")
    equal(calls.resetPosition, true, "reset position runs the addon's reset")
    slash("reset settings")
    equal(wow.popups[#wow.popups], "TESTADDON_HAMMERCORE_RESET", "reset settings asks first")
    StaticPopupDialogs.TESTADDON_HAMMERCORE_RESET.OnAccept()
    equal(wow.reloads > 0, true, "confirming the reset reloads")

    slash("toggle")
    equal(calls.toggle, true, "shared verbs run the addon's handler")
    slash("frobnicate")
    equal(wow.LastPrint(), "TestAddon: unknown command. Type /testaddon help for the list.", "unknown commands point to help")

    slash("version")
    equal(wow.LastPrint(), "TestAddon: v1.2.3-dev4, HammerCore " .. HC.VERSION, "version names both builds")
    slash("about")
    equal(HC.Settings.selected, "About", "about opens the About page")
end

-- ── Addon commands, two-word names and help ───────────────────────────────
do
    local HC = addon()
    local cleared, listed = false, false
    HC.Commands:Add({ name = "learned", section = "Learning", help = "List recorded auras",
        run = function() listed = true end })
    HC.Commands:Add({ name = "learned clear", section = "Learning", help = "Clear recorded auras",
        run = function() cleared = true end })
    SlashCmdList.TESTADDON("learned clear")
    equal(cleared and not listed, true, "the two-word command wins")
    SlashCmdList.TESTADDON("learned")
    equal(listed, true, "the one-word command still works")
    local ok = pcall(HC.Commands.Add, HC.Commands, { name = "help", run = function() end })
    equal(ok, false, "a duplicate command is rejected")

    wow.printed = {}
    SlashCmdList.TESTADDON("help")
    local plain = {}
    for _, line in ipairs(wow.printed) do plain[#plain + 1] = wow.Plain(line) end
    equal(plain[1], "TestAddon: commands", "help starts with a heading")
    equal(plain[2], "Core", "Core is the first section")
    equal(plain[3], "  /testaddon - Open settings", "the bare command is listed first")
    contains(plain, "/testaddon startup [on|off] - Show the startup message", "core commands show arguments")
    local display, learning
    for index, line in ipairs(plain) do
        if line == "Display" then display = index end
        if line == "Learning" then learning = index end
    end
    equal(display ~= nil and learning ~= nil and display < learning, true, "Display precedes addon sections")
end

-- ── Settings window ────────────────────────────────────────────────────────
do
    local HC = addon()
    HC.Settings:NewPage({ name = "Panel" }, function(panel, y) return y - 40 end)
    HC.Settings:NewPage({ name = "Broken" }, function() error("boom") end)
    HC.Settings:NewPage({ name = "Learned", group = "reference" }, function(panel, y) return y end)
    HC:Start()
    HC.Settings:Show()
    local names = {}
    for _, spec in ipairs(HC.Settings.order) do names[#names + 1] = spec.name end
    equal(table.concat(names, ","), "Panel,Broken,Visibility,Learned,Theme,Commands,Troubleshooting,About",
        "main pages, Visibility, then addon and standard reference pages")
    equal(#HC.Settings.dividers, 1, "one divider separates the two sections")
    equal(HC.Settings.selected, "Panel", "the first page opens by default")
    equal(HC.Settings.errors.Broken:find("boom", 1, true) ~= nil, true, "a failing page is recorded")
    equal(HC.Settings.pages.About ~= nil, true, "pages after a failure still build")
    HC.Settings:Show("Troubleshooting")
    equal(HC.Settings.pages.Troubleshooting:IsShown(), true, "a named page opens")
    equal(HC.Settings.pages.Panel:IsShown(), false, "other pages hide")
    equal(UISpecialFrames[1], "TestAddonSettingsFrame", "Escape closes the window")

    local report = HC.DiagnosticReport()
    equal(report:find("Settings page failed: Broken", 1, true) ~= nil, true, "page failures reach diagnostics")
    equal(report:find("Addon line", 1, true) ~= nil, true, "addon diagnostics are appended")
end

do
    local HC = addon()
    HC.Settings:NewPage({ name = "Panel" }, function(panel, y) return y end)
    HC.Settings:AddVisibility()
    HC.Settings:NewPage({ name = "Alerts" }, function(panel, y) return y end)
    HC.Settings:Create()
    equal(HC.Settings.order[2].name, "Visibility", "an addon can place Visibility")
    equal(HC.Settings.order[3].name, "Alerts", "pages after it keep their order")
end

do
    local HC = addon({ canOpen = function() return false, "not in combat" end })
    equal(HC.Settings:Show(), false, "canOpen can refuse")
    equal(wow.LastPrint(), "TestAddon: not in combat", "the refusal is explained")
end

-- ── Inverted legacy keys, actions, pinned areas and page resets ────────────
do
    local HC, saved = addon({ legacy = { minimap = { key = "hide_minimap", invert = true } } })
    saved.hide_minimap = true
    equal(HC.State().minimap, false, "an inverted legacy key is adopted the right way round")
    equal(saved.hide_minimap, nil, "the inverted legacy key is removed")

    HC.Commands:AddAction({ section = "Grid", usage = "Left-click a cell", help = "Apply its marker" })
    wow.printed = {}
    SlashCmdList.TESTADDON("help")
    local found = false
    for _, line in ipairs(wow.printed) do
        if wow.Plain(line) == "  Left-click a cell - Apply its marker" then found = true end
    end
    equal(found, true, "actions appear in help without a slash prefix")
    SlashCmdList.TESTADDON("left-click")
    equal(wow.LastPrint(), "TestAddon: unknown command. Type /testaddon help for the list.", "actions are not commands")

    local pinned, resetClicked, resetButton
    HC.Settings:NewPage({ name = "Panel" }, function(panel, y)
        pinned = panel.hcCreatePinned(120)
        resetButton, y = HC.UI.PageReset(panel, y, function() resetClicked = true end, "Reset panel")
        return y
    end)
    HC:Start()
    HC.Settings:Show()
    equal(pinned:GetHeight(), 120, "a pinned area is created")
    equal(pinned.hcRefresh == HC.Settings.pages.Panel.hcRefresh, true, "the pinned area shares the page refresh")
    wow.Click(resetButton)
    equal(resetClicked, true, "the page reset runs")
    equal(resetButton:GetText(), "Reset panel", "the reset button is labelled")
end

-- ── Visibility and About layouts ───────────────────────────────────────────
do
    local applied = 0
    local HC = addon({
        about = { note = "FROM THE FORGE", tips = { "Tip one", "Tip two" }, action = "Polish the anvil",
            onApply = function() applied = applied + 1 end },
    })
    local headings = {}
    local header = HC.UI.Header
    HC.UI.Header = function(panel, text, y)
        headings[#headings + 1] = text
        return header(panel, text, y)
    end
    HC.spec.visibility = function(panel, y) return select(2, HC.UI.Header(panel, "Bar", y)) end
    HC:Start()
    HC.Settings:Show("Visibility")
    equal(headings[1] .. "," .. headings[2], "Bar,Other", "addon sections come first, Other last")
    HC.UI.Header = header

    HC.Settings:Show("About")
    wow.Click(HC.Pages.aboutIcon)
    local said = wow.LastPrint()
    equal(said == "TestAddon: Tip one" or said == "TestAddon: Tip two", true, "the icon prints a tip to chat")
    equal(applied, 1, "the icon runs the addon's apply hook")
end

do
    local HC = addon({ about = { tips = { "Only tip" }, chat = { "You apply TestAddon." } } })
    HC:Start()
    HC.Settings:Show("About")
    wow.Click(HC.Pages.aboutIcon)
    equal(wow.LastPrint(), "TestAddon: You apply TestAddon.", "chat lines replace the tip in chat")
end

-- ── Dynamic dropdown and dropdown pair ─────────────────────────────────────
do
    local HC = addon()
    local spells, chosen, rows, columns = { "Cleanse" }, "Cleanse", "LEFT", "TOP"
    local dynamic, pairLeft
    HC.Settings:NewPage({ name = "Actions" }, function(panel, y)
        _, y, dynamic = HC.UI.DynamicDropdown(panel, "Spell", nil, y,
            function() return spells, spells end,
            function() return chosen end, function(value) chosen = value end)
        pairLeft, _, y = HC.UI.DropdownPair(panel, "Grid flow", y,
            { label = "Rows grow from", values = { "LEFT", "RIGHT" }, labels = { "Left", "Right" },
              get = function() return rows end, set = function(value) rows = value end },
            { label = "Columns grow from", values = { "TOP", "BOTTOM" }, labels = { "Top", "Bottom" },
              get = function() return columns end, set = function(value) columns = value end })
        return y
    end)
    HC:Start()
    HC.Settings:Show()
    equal(dynamic:GetText(), "Cleanse", "the dynamic select shows the current choice")
    spells = { "Cleanse", "Blessing of Freedom" }
    wow.Click(dynamic)
    local freedom
    for _, frame in ipairs(wow.frames) do
        if frame.value == "Blessing of Freedom" and frame:IsShown() then freedom = frame end
    end
    equal(freedom ~= nil, true, "new choices appear when the menu opens")
    wow.Click(freedom)
    equal(chosen, "Blessing of Freedom", "choosing sets the value")
    equal(pairLeft:GetText(), "Left", "the pair shows its current choice")
end

-- ── Multi-select menu ──────────────────────────────────────────────────────
do
    local HC = addon()
    local mode = "ALWAYS"
    local select
    HC.Settings:NewPage({ name = "Bar" }, function(panel, y)
        select, y = HC.UI.MultiSelect(panel, "Show", nil, y, {
            items = {
                { label = "Always", radio = true, get = function() return mode == "ALWAYS" end,
                  set = function() mode = "ALWAYS" end },
                { label = "Never", radio = true, get = function() return mode == "NEVER" end,
                  set = function() mode = "NEVER" end },
            },
            summary = function() return mode end,
        })
        return y
    end)
    HC:Start()
    HC.Settings:Show()
    wow.Click(select)
    local never
    for _, frame in ipairs(wow.frames) do
        if frame.item and frame.item.label == "Never" then never = frame end
    end
    equal(never.check:IsMouseEnabled(), false, "the tick passes clicks to its row")
    never.item.disabled = function() return true end
    never.item.label = function() return "Never (missing)" end
    select.scripts.OnClick(select)
    select.scripts.OnClick(select)
    equal(never.check.Text:GetText(), "Never (missing)", "labels are re-read when the menu opens")
    wow.Click(never)
    equal(mode, "ALWAYS", "a disabled entry cannot be chosen")
    never.item.disabled, never.item.label = nil, "Never"
    wow.Click(never)
    equal(mode, "NEVER", "clicking the row chooses it")
    equal(select:GetText(), "NEVER", "the summary updates")
    equal(HC.Settings.window and HC.Settings.rail ~= nil, true, "window built")
end

-- ── Minimap button ─────────────────────────────────────────────────────────
do
    local HC, _, calls = addon()
    HC:Start()
    local button = HC.Minimap.button
    equal(button:GetName(), "TestAddonMinimapButton", "the button name is addon-prefixed")
    wow.Click(button, "RightButton")
    equal(calls.rightClick, true, "right-click runs the addon action")
    wow.Click(button, "LeftButton")
    equal(HC.Settings:IsShown(), true, "left-click opens settings")
    wow.Click(button, "LeftButton")
    equal(HC.Settings:IsShown(), false, "left-click again closes settings")
end

-- ── Rail button and combat hiding ─────────────────────────────────────────
do
    local previewing = false
    local HC = addon({
        hideInCombat = true,
        railButton = {
            label = function() return previewing and "Hide preview" or "Preview on screen" end,
            run = function() previewing = not previewing end,
            active = function() return previewing end,
        },
    })
    HC:Start()
    HC.Settings:Show()
    local rail = HC.Settings.railButton
    equal(rail:GetText(), "Preview on screen", "the rail button shows its label")
    wow.Click(rail)
    equal(previewing, true, "the rail button runs its action")
    equal(rail:GetText(), "Hide preview", "the label follows the action's state")

    InCombatLockdown = function() return true end
    HC.combatFrame.scripts.OnEvent(HC.combatFrame, "PLAYER_REGEN_DISABLED")
    equal(HC.Settings:IsShown(), false, "combat hides settings")
    equal(HC.Minimap.button:IsShown(), false, "combat hides the minimap button")
    equal(HC.Settings:Show(), false, "settings refuse to open in combat")
    InCombatLockdown = function() return false end
    HC.combatFrame.scripts.OnEvent(HC.combatFrame, "PLAYER_REGEN_ENABLED")
    equal(HC.Minimap.button:IsShown(), true, "the minimap button returns after combat")
end

-- ── Search picker and text input ───────────────────────────────────────────
do
    local HC = addon()
    local chosen, message = "THANK", "Thanks!"
    local picker, input
    HC.Settings:NewPage({ name = "Thanks" }, function(panel, y)
        _, y, picker = HC.UI.SearchPicker(panel, "Emote", nil, y, {
            items = function() return { { value = "THANK", label = "Thank" }, { value = "BOW", label = "Bow" },
                { value = "CHEER", label = "Cheer" } } end,
            get = function() return chosen end,
            set = function(value) chosen = value end,
        })
        _, y, input = HC.UI.TextInput(panel, "Message", nil, y,
            function() return message end, function(value) message = value end)
        return y
    end)
    HC:Start()
    HC.Settings:Show()
    equal(picker:GetText(), "Thank", "the picker shows the current label")
    wow.Click(picker)
    local list
    for _, frame in ipairs(wow.frames) do
        if frame.search then list = frame end
    end
    list.search:SetText("bo")
    list.search.scripts.OnTextChanged(list.search)
    local visible = {}
    for _, frame in ipairs(wow.frames) do
        if frame.parent == list.content and frame:IsShown() then visible[#visible + 1] = frame end
    end
    equal(#visible, 1, "typing filters the list")
    wow.Click(visible[1])
    equal(chosen, "BOW", "clicking an entry chooses it")
    equal(picker:GetText(), "Bow", "the picker shows the new choice")
    equal(list:IsShown(), false, "choosing closes the list")

    equal(input:GetText(), "Thanks!", "the input shows the saved text")
    input:SetText("Cheers, {player}")
    input.scripts.OnEnterPressed(input)
    equal(message, "Cheers, {player}", "Enter saves the text")
end

-- ── Two addons, two private copies ─────────────────────────────────────────
do
    wow.Install(META)
    local nsA = wow.LoadHammerCore("src", "TestAddon")
    local nsB = wow.LoadHammerCore("src", "OtherAddon")
    local dbA, dbB = {}, {}
    nsA.HammerCore:Init({ name = "TestAddon", command = "testaddon", db = function() return dbA end })
    nsB.HammerCore:Init({ name = "OtherAddon", command = "other", db = function() return dbB end })
    equal(nsA.HammerCore ~= nsB.HammerCore, true, "each addon has its own instance")
    equal(rawget(_G, "HammerCore"), nil, "no global is created")
    nsA.HammerCore.State().theme = "modern"
    SlashCmdList.OTHERADDON("startup off")
    equal(dbA.hammerCore.startupMessage, true, "one addon's command never touches another")
    equal(dbB.hammerCore.startupMessage, false, "the other addon's state changed")
    equal(nsB.HammerCore.LoginMessage():sub(1, 16), "OtherAddon v9.9.", "each reads its own metadata")
end

io.write("hammercore core tests passed\n")
