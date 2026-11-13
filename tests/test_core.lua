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

    slash("theme")
    equal(wow.LastPrint(), "TestAddon: theme modern", "theme with no argument reports the current one")
    slash("theme parchment")
    equal(wow.LastPrint(), "TestAddon: unknown theme", "an unknown theme is refused")
    slash("theme classic")
    equal(HC.State().theme, "modern", "classic is switched off for now")
    equal(wow.LastPrint(), "TestAddon: Classic is not available yet", "the refusal says why")

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
    equal(table.concat(names, ","), "Panel,Broken,Visibility,Learned,Commands,Troubleshooting,About",
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
    for _, line in ipairs(wow.printed) do
        equal(wow.Plain(line):find("/testaddon theme", 1, true), nil, "theme is hidden from help")
    end
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
    equal(resetClicked, nil, "the page reset waits for confirmation")
    equal(HC.Dialog.current.text, "Reset panel to defaults?", "confirmation names the reset scope")
    wow.Click(HC.Dialog.frame.cancel)
    equal(resetClicked, nil, "cancelling keeps settings")
    wow.Click(resetButton)
    wow.Click(HC.Dialog.frame.accept)
    equal(resetClicked, true, "accepting runs the page reset")
    equal(resetButton:GetText(), "Reset panel", "the reset button is labelled")
    local currentProfile = "First"
    HC.Profiles.Loaded = function() return currentProfile end
    resetClicked = false
    wow.Click(resetButton)
    currentProfile = "Second"
    wow.Click(HC.Dialog.frame.accept)
    equal(resetClicked, false, "a profile switch cancels a pending reset")
end

-- ── Visibility and About layouts ───────────────────────────────────────────
do
    local HC = addon()
    local control = CreateFrame("Frame", nil, UIParent)
    HC.UI.AttachHint(control, "First", "First hint")
    local enter, leave = control.scripts.OnEnter, control.scripts.OnLeave
    HC.UI.AttachHint(control, "Second", "Updated hint")
    equal(control.scripts.OnEnter, enter, "reattaching a hint keeps one enter handler")
    equal(control.scripts.OnLeave, leave, "reattaching a hint keeps one leave handler")
    equal(control.hcHint, "Updated hint", "reattaching refreshes the hint text")
end

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
    equal(table.concat({ headings[1], headings[2], headings[3], headings[4] }, ","), "Bar,Minimap button,Updates,Settings window", "addon sections precede shared groups")
    HC.UI.Header = header

    HC.Settings:Show("About")
    equal(wow.FindText("Puzzle time!") ~= nil, true, "About has the puzzle row")
    equal(#HC.Quiz.Prompts, 20, "About has twenty quiz invitations")
    for _, prompt in ipairs(HC.Quiz.Prompts) do
        equal(prompt:sub(-1), "?", "each quiz invitation is a question")
    end
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

-- ── Classic theme ──────────────────────────────────────────────────────────
do
    local HC, saved = addon()
    HC.Theme.registry.classic.available = true
    saved.hammerCore = { theme = "classic" }
    local checked
    HC.Settings:NewPage({ name = "Panel" }, function(panel, y)
        local row
        row, y = HC.UI.Check(panel, "Enabled", nil, y, function() return true end, function() end)
        checked = row.hcCheckbox
        _, y = HC.UI.Slider(panel, "Size", nil, y, 1, 10, 1, function() return 5 end, function() end)
        return y
    end)
    HC:Start()
    HC.Settings:Show()
    equal(HC.Theme.IsClassic(), true, "the saved classic theme is active")
    equal(HC.Settings.window.backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Border",
        "the window wears Blizzard's dialog frame")
    equal(checked.normalTexture, "Interface\\Buttons\\UI-CheckBox-Up", "checkboxes use Blizzard's checkbox art")
    local panelButton = false
    for _, frame in ipairs(wow.frames) do
        if frame.template == "UIPanelButtonTemplate" then panelButton = true end
    end
    equal(panelButton, true, "buttons use Blizzard's panel button")
    local failures = {}
    for name, err in pairs(HC.Settings.errors) do failures[#failures + 1] = name .. ": " .. err end
    equal(table.concat(failures, "; "), "", "every standard page builds in classic")
    HC.Settings:Show("About")
    HC.Quiz:Start()
    equal(HC.Quiz.frame.backdrop.edgeFile, "Interface\\DialogFrame\\UI-DialogBox-Border", "the quiz is framed too")
    HC.Theme.registry.classic.available = false
    equal(HC.Theme.IsClassic(), false, "with classic off, a saved classic choice falls back to modern")
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
    button.scripts.OnDragStop(button)
    -- Clients may skip OnClick on drag release. The next press is a new click.
    button.scripts.OnMouseDown(button)
    wow.Click(button, "LeftButton")
    equal(HC.Settings:IsShown(), true, "first real click after a drag still opens settings")
    button.scripts.OnDragStop(button)
    wow.Click(button, "LeftButton")
    equal(HC.Settings:IsShown(), true, "a click emitted by drag release is suppressed")
end

-- A minimap collector owns placement after reparenting a button into its tray.
do
    local HC = addon({ hideInCombat = true })
    HC:Start()
    local button = HC.Minimap.button
    local tray = CreateFrame("Frame", "CollectorTray", UIParent)
    -- The harness stores parent directly; this models the collector's SetParent.
    button.parent = tray
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", tray, "TOPLEFT", 8, -8)

    local function collected(label)
        local point, relative, relativePoint, x, y = button:GetPoint()
        equal(button:GetParent(), tray, label .. " keeps the tray parent")
        equal(point, "TOPLEFT", label .. " keeps the tray anchor")
        equal(relative, tray, label .. " keeps the tray reference")
        equal(relativePoint, "TOPLEFT", label .. " keeps the relative anchor")
        equal(x, 8, label .. " keeps the tray column")
        equal(y, -8, label .. " keeps the tray row")
    end
    local angle = HC.State().minimapAngle
    button.scripts.OnDragStart(button)
    equal(button.scripts.OnUpdate, nil, "collected drag does not start minimap tracking")
    equal(HC.State().minimapAngle, angle, "collected drag preserves saved angle")
    HC.Minimap:Update()
    collected("settings refresh")
    Minimap.scripts.OnSizeChanged(Minimap)
    collected("minimap resize")
    InCombatLockdown = function() return true end
    HC.combatFrame.scripts.OnEvent(HC.combatFrame, "PLAYER_REGEN_DISABLED")
    InCombatLockdown = function() return false end
    HC.combatFrame.scripts.OnEvent(HC.combatFrame, "PLAYER_REGEN_ENABLED")
    collected("combat exit")
    equal(button:IsShown(), true, "combat exit still restores intended visibility")
    HC.State().minimap = false
    HC.Minimap:Update()
    equal(button:IsShown(), false, "explicit hiding still works when collected")
    collected("explicit hide")

    button.parent = Minimap
    HC.State().minimap = true
    HC.Minimap:Update()
    local point, relative = button:GetPoint()
    equal(point, "CENTER", "uncollecting restores normal placement")
    equal(relative, Minimap, "uncollected placement uses the minimap")
    button.scripts.OnDragStart(button)
    local follow = button.scripts.OnUpdate
    equal(type(follow), "function", "standalone dragging still starts tracking")
    button.parent = tray
    follow(button)
    equal(button.scripts.OnUpdate, nil, "collection during a drag stops minimap tracking")
    equal(HC.State().minimapAngle, angle, "collection during a drag preserves saved angle")
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

-- Addons can make their primary task the left click without changing defaults.
do
    local left, right = 0, 0
    local HC = addon({ minimap = {
        leftClick = function() left = left + 1 end, leftClickLabel = "export",
        rightClick = function() right = right + 1 end, rightClickLabel = "settings",
    } })
    HC:Start()
    wow.Click(HC.Minimap.button, "LeftButton")
    wow.Click(HC.Minimap.button, "RightButton")
    equal(left, 1, "custom left click runs once")
    equal(right, 1, "custom right click runs once")
end

-- ── What's new ─────────────────────────────────────────────────────────────
do
    local notes = {
        { version = "1.2.3", items = {
            { text = "Cooldown icons.", page = "General" },
            "A plain note.",
            { text = "A cooldown bar.", page = "General" },
        } },
        { version = "1.1.0", items = { "An older highlight." } },
        { version = "1.0.5", items = {} },
    }
    local function start(saved, overrides)
        overrides = overrides or {}
        overrides.db = function() return saved end
        overrides.whatsNew = overrides.whatsNew or notes
        local HC = addon(overrides)
        HC.Settings:NewPage({ name = "General", title = "General" }, function(_, y) return y end)
        HC:Start()
        return HC
    end
    local function fire(HC, event)
        HC.WhatsNew.eventFrame.scripts.OnEvent(HC.WhatsNew.eventFrame, event)
    end
    local function shown(HC) return HC.WhatsNew.frame ~= nil and HC.WhatsNew.frame.shown end

    local W = addon().WhatsNew
    equal(W.Compare("1.2.3-dev4", "1.2.3"), 0, "a dev build counts as its base version")
    equal(W.Compare("1.10.0", "1.9.9"), 1, "versions compare numerically")
    equal(W.Compare("v1.2", "1.2.0"), 0, "a leading v and missing parts are ignored")
    equal(W.Base("1.2.3-dev4"), "1.2.3", "base version strips the dev suffix")

    -- A fresh install records the version and stays quiet.
    local fresh = {}
    local HC = start(fresh, { legacy = {} })
    equal(HC.WhatsNew.eventFrame, nil, "a fresh install schedules nothing")
    equal(fresh.hammerCore.whatsNewSeen, "1.2.3", "a fresh install records the version")

    -- An existing profile from before What's new: this release only.
    local existing = { hammerCore = { startupMessage = false } }
    HC = start(existing)
    fire(HC, "PLAYER_ENTERING_WORLD")
    equal(shown(HC), true, "an update shows what's new")
    equal(wow.FindText("TestAddon 1.2.3") ~= nil, true, "it lists this release")
    equal(wow.FindText("An older highlight."), nil, "older releases aren't assumed unseen")
    equal(existing.hammerCore.whatsNewSeen, "1.2.3", "showing records the version")
    equal(wow.FindButton("Open General") ~= nil, true, "a highlight can open its settings page")
    local buttons = 0
    for _, frame in ipairs(wow.frames) do
        local text = rawget(frame, "Text")
        if type(text) == "table" and text.text == "Open General" and wow.Visible(frame) then buttons = buttons + 1 end
    end
    equal(buttons, 2, "each highlight with a page links to it")
    equal(wow.FindText("A cooldown bar.") ~= nil, true, "grouped highlights are all listed")

    -- Seen before: only newer releases, and the empty one never counts.
    local seen = { hammerCore = { startupMessage = false, whatsNewSeen = "1.0.0" } }
    HC = start(seen)
    fire(HC, "PLAYER_ENTERING_WORLD")
    equal(wow.FindText("An older highlight.") ~= nil, true, "every unseen release is listed")
    equal(wow.FindText("TestAddon 1.0.5"), nil, "a release without highlights is left out")

    -- Up to date: nothing.
    local current = { hammerCore = { startupMessage = false, whatsNewSeen = "1.2.3", whatsNewSeenItems = 3 } }
    HC = start(current)
    equal(HC.WhatsNew.eventFrame, nil, "nothing new schedules nothing")

    -- A highlight added to a release already seen shows on its own.
    local added = { hammerCore = { startupMessage = false, whatsNewSeen = "1.2.3", whatsNewSeenItems = 2 } }
    HC = start(added)
    fire(HC, "PLAYER_ENTERING_WORLD")
    equal(shown(HC), true, "a new highlight for a seen release shows")
    equal(wow.Visible(wow.FindText("A cooldown bar.")), true, "the new highlight is listed")
    local old = wow.FindText("Cooldown icons.")
    equal(old ~= nil and wow.Visible(old), false, "highlights already seen aren't")
    equal(added.hammerCore.whatsNewSeenItems, 3, "then all three are recorded as seen")

    -- Combat holds it back until combat ends.
    local combat = { hammerCore = { startupMessage = false, whatsNewSeen = "1.1.0" } }
    HC = start(combat)
    InCombatLockdown = function() return true end
    fire(HC, "PLAYER_ENTERING_WORLD")
    equal(shown(HC), false, "it never opens in combat")
    equal(combat.hammerCore.whatsNewSeen, "1.1.0", "unshown highlights stay unseen")
    InCombatLockdown = function() return false end
    fire(HC, "PLAYER_REGEN_ENABLED")
    equal(shown(HC), true, "it opens once combat ends")
    equal(combat.hammerCore.whatsNewSeen, "1.2.3", "then records the version")

    -- Switched off: quiet, and the record still moves on.
    local off = { hammerCore = { startupMessage = false, whatsNewSeen = "1.1.0", whatsNew = false } }
    HC = start(off)
    equal(HC.WhatsNew.eventFrame, nil, "switched off schedules nothing")
    equal(off.hammerCore.whatsNewSeen, "1.2.3", "switched off still records the version")

    -- A dev build can carry the next release's highlights.
    local ahead = { hammerCore = { startupMessage = false, whatsNewSeen = "1.2.3", whatsNewSeenItems = 3 } }
    HC = start(ahead, { whatsNew = { { version = "1.3.0", items = { "Next release." } } } })
    fire(HC, "PLAYER_ENTERING_WORLD")
    equal(shown(HC), true, "a dev build shows the next release's highlights")
    equal(ahead.hammerCore.whatsNewSeen, "1.3.0", "and records that release as seen")

    -- The command, the toggle and the report.
    HC.WhatsNew:Hide()
    HC.Commands:Dispatch("whatsnew")
    equal(shown(HC), true, "the command opens it any time")
    contains({ HC.DiagnosticReport() }, "What's new: on, last seen 1.3.0", "the report shows the state")
    local plain = addon()
    equal(plain.Commands.byName.whatsnew, nil, "addons without highlights get no command")
end

-- ── One What's new window for every addon ──────────────────────────────────
do
    wow.Install(META)
    local nsA = wow.LoadHammerCore("src", "TestAddon")
    local nsB = wow.LoadHammerCore("src", "OtherAddon")
    local dbA = { hammerCore = { startupMessage = false, whatsNewSeen = "1.0.0" } }
    local dbB = { hammerCore = { startupMessage = false, whatsNewSeen = "9.0.0" } }
    local A, B = nsA.HammerCore, nsB.HammerCore
    A:Init({ name = "TestAddon", command = "testaddon", icon = "a", db = function() return dbA end,
        whatsNew = { { version = "1.2.3", items = { { text = "First addon news.", page = "General" } } } } })
    B:Init({ name = "OtherAddon", command = "other", icon = "b", minimap = { icon = "b-small" },
        db = function() return dbB end,
        whatsNew = { { version = "9.9.9", items = { { text = "Second addon news.", page = "Extras", tab = "Cells" } } } } })
    A.Settings:NewPage({ name = "General", title = "General" }, function(_, y) return y end)
    B.Settings:NewPage({ name = "Extras", title = "Extras" }, function(_, y) return y end)
    A:Start()
    B:Start()
    B.WhatsNew.eventFrame.scripts.OnEvent(B.WhatsNew.eventFrame, "PLAYER_ENTERING_WORLD")
    A.WhatsNew.eventFrame.scripts.OnEvent(A.WhatsNew.eventFrame, "PLAYER_ENTERING_WORLD")
    local windows = 0
    for _, W in ipairs({ A.WhatsNew, B.WhatsNew }) do
        if W.frame and W.frame.shown then windows = windows + 1 end
    end
    equal(windows, 1, "every addon's news shares one window")
    equal(wow.FindText("What's new in Consecrated Hammer addons") ~= nil, true, "the shared window names the family")
    equal(wow.FindText("First addon news.") ~= nil, true, "the first addon's news is listed")
    equal(wow.FindText("Second addon news.") ~= nil, true, "the second addon's news is listed")
    equal(wow.FindText("OtherAddon") ~= nil, true, "each addon has a heading")
    local frame = A.WhatsNew.frame.shown and A.WhatsNew.frame or B.WhatsNew.frame
    equal(frame.icon.texture, "Interface\\GossipFrame\\AvailableQuestIcon", "the shared window has a neutral icon")
    local headingIcons = {}
    for _, region in ipairs(wow.regions) do
        if region.parent == frame.content and (region.texture == "a" or region.texture == "b-small" or region.texture == "b") then
            headingIcons[region.texture] = (headingIcons[region.texture] or 0) + 1
        end
    end
    equal(headingIcons["b-small"], 1, "a heading uses the addon's minimap icon")
    equal(headingIcons["a"], 1, "or its own icon without one")
    equal(dbA.hammerCore.whatsNewSeen, "1.2.3", "the first addon records what it saw")
    equal(dbB.hammerCore.whatsNewSeen, "9.9.9", "the second addon records what it saw")
    local opened, openedTab
    B.Settings.Show = function(_, page, tab) opened, openedTab = page, tab end
    wow.Click(wow.FindButton("Open Extras"))
    equal(opened, "Extras", "a button opens its own addon's page")
    equal(openedTab, "Cells", "on the item's tab")

    -- Each addon's command still shows only its own news.
    A.WhatsNew:Hide()
    B.WhatsNew:Hide()
    B.Commands:Dispatch("whatsnew")
    equal(wow.FindText("What's new in OtherAddon") ~= nil, true, "the command shows its own addon")
end

-- ── Grid layout, default columns and the shared pinned area ───────────────
do
    local HC = addon()
    local UI = HC.UI
    local seen = {}
    HC.Settings:NewPage({ name = "Grid" }, function(panel, y)
        seen.columns = panel.hcColumns
        local _, next = UI.Check(panel, "Left cell", nil, y, function() return true end, function() end)
        equal(next, y, "a left cell leaves y on its row")
        local after = UI.Flush(panel, next - 4)
        equal(after < y - UI.CELL_H, true, "Flush with a nudged y still clears the half row")
        return after
    end)
    HC.Settings:NewPage({ name = "Notes", group = "reference" }, function(panel, y)
        seen.reference = panel.hcColumns
        return y
    end)
    HC.Settings:NewPage({
        name = "Tabbed",
        pinned = { height = 100, build = function(frame) seen.pinned = frame end },
        tabs = {
            { name = "One", build = function(panel, y) seen.one = seen.pinned; return y end },
            { name = "Two", columns = 1, build = function(panel, y) seen.two = panel.hcColumns; return y end },
        },
    })
    HC:Start()
    HC.Settings:Show("Grid")
    equal(seen.columns, 2, "settings pages default to two columns")
    equal(seen.reference, 1, "reference pages stay single column")
    equal(seen.one ~= nil, true, "the pinned area builds before the tabs")
    equal(seen.two, 1, "a tab can ask for one column")
    HC.Settings:Show("Tabbed", "Two")
    equal(HC.Settings.pages.Tabbed.pinned:IsShown(), true, "the pinned area stays on every tab")
end

-- The capture prompt can offer Replace for a key that's taken.
do
    local HC = addon()
    local Capture = HC.Bindings.Capture
    local taken, forced = 0, 0
    Capture:Start({
        title = "Test", inputs = { mouse = true },
        onKey = function()
            taken = taken + 1
            return "Right click is already assigned to Other.", function() forced = forced + 1 end
        end,
    })
    local catcher = Capture.frame
    equal(catcher.prompt.body:GetText():find("wheel", 1, true), nil, "mouse-only capture does not offer the wheel")
    catcher.scripts.OnMouseDown(catcher, "RightButton")
    equal(taken, 1, "a refused click reaches onKey")
    equal(Capture:IsActive(), true, "and keeps the prompt open")
    equal(catcher.prompt.error.text, "Right click is already assigned to Other.", "with the reason")
    equal(catcher.prompt.replace:IsShown(), true, "and a Replace button")
    wow.Click(catcher.prompt.replace)
    equal(forced, 1, "Replace takes the key anyway")
    equal(Capture:IsActive(), false, "and closes the prompt")
    Capture:Start({ title = "Again", inputs = { mouse = true }, onKey = function() return "Nope." end })
    equal(catcher.prompt.replace:IsShown(), false, "Replace only shows when it's offered")
    catcher.scripts.OnMouseDown(catcher, "LeftButton")
    equal(catcher.prompt.replace:IsShown(), false, "even after an error")
    local clicks = {}
    Capture:Start({ title = "Box", inputs = { mouse = true, wheel = true },
        onKey = function(key) clicks[#clicks + 1] = key end })
    equal(catcher.prompt.body:GetText():find("scroll the wheel", 1, true) ~= nil, true, "wheel capture explains the wheel")
    catcher.prompt.scripts.OnMouseDown(catcher.prompt, "RightButton")
    equal(clicks[1], "BUTTON2", "a click on the prompt box itself binds")
    Capture:Start({ title = "Box", inputs = { mouse = true, wheel = true },
        onKey = function(key) clicks[#clicks + 1] = key end })
    catcher.prompt.scripts.OnMouseWheel(catcher.prompt, 1)
    equal(clicks[2], "MOUSEWHEELUP", "and so does the wheel over it")
    Capture:Start({ title = "All", onKey = function() end })
    equal(catcher.prompt.body:GetText(), "Press a key, click a mouse button or scroll the wheel\nHold Shift, Ctrl or Alt to add them. Esc cancels.", "all supported inputs are named")
    Capture:Start({ title = "None", inputs = {}, onKey = function() end })
    equal(catcher.prompt.body:GetText():find("No inputs are enabled", 1, true), 1, "empty input sets explain why nothing can be bound")
    Capture:Stop()
end

-- Game key bindings for an addon command.
do
    local HC = addon()
    local B = HC.Bindings
    local map, saved, locked = { F = "TOGGLEMAP" }, 0, false
    local function keysFor(command)
        local out = {}
        for key, action in pairs(map) do if action == command then out[#out + 1] = key end end
        table.sort(out)
        return unpack(out)
    end
    local previous = { GetBindingKey, GetBindingAction, SetBinding, SaveBindings, GetBindingName, InCombatLockdown }
    GetBindingKey = keysFor
    GetBindingAction = function(key) return map[key] or "" end
    SetBinding = function(key, command) map[key] = command; return true end
    SaveBindings = function() saved = saved + 1 end
    GetBindingName = function(action) return action == "TOGGLEMAP" and "Open map" or action end
    InCombatLockdown = function() return locked end
    local cmd = "CLICK TestButton:LeftButton"

    equal(B.CommandLabel(cmd), "Not bound", "nothing bound yet")
    equal(B.BindCommand(cmd, "G"), true, "a free key binds")
    equal(B.CommandKey(cmd), "G", "and reads back")
    equal(saved, 1, "and is saved")
    local ok, message, conflict = B.BindCommand(cmd, "F")
    equal(ok, false, "a taken key is refused")
    equal(conflict, "conflict", "as a conflict")
    equal(message:find("Open map", 1, true) ~= nil, true, "naming what has it")
    equal(B.BindCommand(cmd, "F", true), true, "replace takes it")
    equal(map.G, nil, "the old key is released")
    equal(B.CommandKey(cmd), "F", "one key at a time")
    equal(B.BindCommand(cmd, "BUTTON1"), false, "bare left click is refused")
    equal(B.BindCommand(cmd, "SHIFT-BUTTON1"), true, "with a modifier it's fine")
    locked = true
    equal(B.BindCommand(cmd, "H"), false, "no changes in combat")
    equal(B.ClearCommand(cmd), false, "including clearing")
    locked = false
    equal(B.ClearCommand(cmd), true, "clears out of combat")
    equal(B.CommandKey(cmd), nil, "nothing left")
    GetBindingKey, GetBindingAction, SetBinding, SaveBindings, GetBindingName, InCombatLockdown = unpack(previous)
end

-- ── Footer links: CurseForge, then GitHub from the TOC ─────────────────────
do
    local HC = addon()
    local labels = function()
        local out = {}
        for _, link in ipairs(HC.Settings:Links()) do out[#out + 1] = link.label end
        return table.concat(out, ",")
    end
    equal(labels(), "Discord,Buy me a coffee", "no TOC pages, shared links only")
    META.TestAddon["X-CurseForge"] = "https://www.curseforge.com/wow/addons/test"
    META.TestAddon["X-Website"] = "https://github.com/consecrated-hammer/Test"
    equal(labels(), "CurseForge,GitHub,Discord,Buy me a coffee", "CurseForge then GitHub lead")
    equal(HC.Settings:Links()[2].icon, "GitHub.tga", "GitHub has its icon")
    META.TestAddon["X-Website"] = "https://example.com"
    equal(labels(), "CurseForge,Discord,Buy me a coffee", "only a GitHub website becomes a GitHub link")
    META.TestAddon["X-CurseForge"], META.TestAddon["X-Website"] = nil, nil
end

io.write("hammercore what's new tests passed\n")
