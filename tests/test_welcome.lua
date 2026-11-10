package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")
local report = print

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local NOTES = {
    { version = "1.3.0", items = { { text = "Quick play.", page = "General" } } },
    { version = "1.2.0", items = { "Flights." } },
}

-- A fresh copy of the addon's own settings, read and written by the rows.
local function rows(db, extra)
    local list = {
        { key = "flights", label = "On a flight", since = "1.3.0",
          subtext = "A few questions to pass the time on a taxi.",
          choices = {
              { value = "ask", label = "Ask me", sub = "Offer at takeoff", tip = "Offer questions at takeoff." },
              { value = "auto", label = "Auto-start", sub = "Starts by itself" },
              { value = "off", label = "Off", sub = "No questions" },
          },
          get = function() return db.flights end,
          set = function(value) db.flights = value end },
        { key = "old", label = "Old choice", since = "1.0.0",
          choices = { { value = true, label = "On" }, { value = false, label = "Off" } },
          get = function() return db.old end,
          set = function(value) db.old = value end },
        { key = "base", label = "Hosting",
          choices = { { value = "a", label = "A" }, { value = "b", label = "B" } },
          get = function() return db.base end,
          set = function(value) db.base = value end },
    }
    for _, row in ipairs(extra or {}) do list[#list + 1] = row end
    return list
end

local function load(name, version)
    local ns = wow.LoadHammerCore("src", name)
    return ns.HammerCore
end

-- Installs the stand-in client and starts one addon.  opts: saved, db,
-- version, combat, extraRows, welcome (spec overrides), noWelcome.
local function start(opts)
    opts = opts or {}
    wow.Install({ TestAddon = { Version = opts.version or "1.3.0" }, OtherAddon = { Version = "2.0.0" } })
    C_Timer = nil
    IsLoggedIn = nil
    ConsecratedHammerWelcome = nil
    InCombatLockdown = function() return opts.combat and opts.combat() or false end
    local saved = opts.saved or {}
    local db = opts.db or { flights = "ask", old = true, base = "a" }
    local HC = load("TestAddon")
    HC:Init({ name = "TestAddon", command = "testaddon", db = function() return saved end, whatsNew = NOTES })
    HC.Settings:NewPage({ name = "General" }, function(panel, y) return HC.Welcome:AddSettings(panel, y) end)
    if not opts.noWelcome then
        local spec = { banner = "Interface\\AddOns\\TestAddon\\Textures\\welcome-banner.tga",
            bannerSize = { 1024, 256 }, tagline = "You read the quest text, right?",
            intro = "Host trivia for your party.", update = "New in 1.3: Quick play.",
            rows = rows(db, opts.extraRows), footer = "You can change these in settings." }
        for key, value in pairs(opts.welcome or {}) do spec[key] = value end
        HC.Welcome:Register(spec)
    end
    HC:Start()
    return HC, saved, db
end

local function fire(frame, event)
    if frame and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event) end
end

local function login(HC)
    fire(HC.Welcome.eventFrame, "PLAYER_ENTERING_WORLD")
    fire(HC.WhatsNew.eventFrame, "PLAYER_ENTERING_WORLD")
end

local function shown(HC)
    return HC.Welcome.frame ~= nil and HC.Welcome.frame.shown == true
end

local function whatsNewShown(HC)
    return HC.WhatsNew.frame ~= nil and HC.WhatsNew.frame.shown == true
end

local function labels(HC)
    local list = {}
    for _, entry in ipairs(HC.Welcome.rowFrames) do list[#list + 1] = entry.spec.label end
    return table.concat(list, ",")
end

local function button(HC, rowIndex, choiceIndex)
    return HC.Welcome.rowFrames[rowIndex].buttons[choiceIndex]
end

-- A new install shows every row with the intro, a few seconds after loading in.
do
    local HC, saved, db = start()
    equal(shown(HC), false, "nothing before the world loads")
    login(HC)
    equal(shown(HC), true, "a new install shows the welcome")
    equal(labels(HC), "On a flight,Old choice,Hosting", "every row on a new install")
    equal(HC.Welcome.frame.intro.text, "Host trivia for your party.", "the intro for new players")
    equal(HC.Welcome.frame.tagline.text, "You read the quest text, right?", "the tagline sits under the banner")
    equal(HC.Welcome.frame.banner.height, 115, "the banner keeps its 4:1 shape")
    equal(HC.Welcome.frame.width, 460, "the window is 460 wide")
    assert(wow.FindText("A few questions to pass the time on a taxi."), "row subtext shows")
    assert(wow.FindText("Offer at takeoff"), "choice sub lines show")
    equal(HC.Welcome.frame.footer.text, "You can change these in settings.", "the footer shows")
    equal(whatsNewShown(HC), false, "a new install never gets What's new")
    equal(saved.hammerCore.welcomeSeen, "1.3.0", "the version is recorded")
    equal(saved.hammerCore.welcomePending, nil, "and the new install is handled")

    -- The current value is highlighted; a click applies it straight away.
    equal(button(HC, 1, 1).active, true, "the current value is highlighted")
    equal(button(HC, 1, 2).active, false, "other choices are not")
    wow.Click(button(HC, 1, 2))
    equal(db.flights, "auto", "a click applies the choice")
    equal(button(HC, 1, 2).active, true, "and moves the highlight")
    equal(button(HC, 1, 1).active, false, "off the old choice")
    wow.Click(button(HC, 2, 2))
    equal(db.old, false, "false values apply too")
    assert(button(HC, 1, 1).hcHint, "choices with a tip have a tooltip")

    -- Done closes without touching anything else.
    wow.Click(HC.Welcome.frame.done)
    equal(shown(HC), false, "Done closes it")
    equal(db.base, "a", "closing never changes a setting")
    equal(ConsecratedHammerWelcome.open, nil, "and frees the shared slot")
    equal(ConsecratedHammerWelcome.busy, 0, "and the login claim")
end

-- A new install that logs out before it shows still gets it next time.
do
    local saved = {}
    local HC = start({ saved = saved })
    equal(saved.hammerCore.welcomePending, true, "the new install waits for its welcome")
    local HC2 = start({ saved = saved })
    login(HC2)
    equal(labels(HC2), "On a flight,Old choice,Hosting", "the next login is still a new install")
end

-- Esc closes it: the frame is on UISpecialFrames, which hides it.
do
    local HC, _, db = start()
    login(HC)
    local listed = false
    for _, name in ipairs(UISpecialFrames) do
        if name == HC.Welcome.frame:GetName() then listed = true end
    end
    equal(listed, true, "Esc closes the welcome")
    HC.Welcome.frame:Hide()
    equal(shown(HC), false, "hidden by Esc")
    equal(db.flights, "ask", "Esc keeps the defaults")
    wow.Click(wow.FindButton("Done") or HC.Welcome.frame.done)
    HC.Welcome:Show(true)
    equal(shown(HC), true, "Show reopens it")
    wow.Click(HC.Welcome.frame.close)
    equal(shown(HC), false, "the close button closes it")
end

-- An update shows only the new rows with the update text, in place of What's new.
do
    local HC, saved = start({ saved = { hammerCore = { startupMessage = false,
        whatsNewSeen = "1.2.0", whatsNewSeenItems = 1 } } })
    login(HC)
    equal(shown(HC), true, "an update with a new row shows the welcome")
    equal(labels(HC), "On a flight", "only rows newer than the last release")
    equal(HC.Welcome.frame.intro.text, "New in 1.3: Quick play.", "updating players get the update text")
    equal(whatsNewShown(HC), false, "the What's new popup is replaced")
    equal(saved.hammerCore.whatsNewSeen, "1.3.0", "and the release counts as seen")
    equal(HC.WhatsNew:Releases()[1].version, "1.3.0", "the release is still on the What's new page")
    equal(HC.WhatsNew:Unread(), true, "with its unread !")
    HC.Welcome.frame:Hide()
    equal(whatsNewShown(HC), false, "closing the welcome doesn't bring the popup back")
    equal(saved.hammerCore.welcomeSeen, "1.3.0", "the welcome's release is recorded")
    equal(#saved.hammerCore.welcomeKeys, 3, "with every row it knows")
end

-- An update with nothing new shows no welcome and the usual What's new.
do
    local HC, saved = start({ saved = { hammerCore = { startupMessage = false, whatsNewSeen = "1.2.0",
        whatsNewSeenItems = 1, welcomeSeen = "1.3.0", welcomeKeys = { "flights", "old", "base" } } } })
    login(HC)
    equal(HC.Welcome.frame, nil, "nothing new, no welcome")
    equal(whatsNewShown(HC), true, "What's new pops up as usual")
    equal(saved.hammerCore.whatsNewSeen, "1.3.0", "and records the release")
end

-- An older profile with no record of either only sees this release's rows.
do
    local HC = start({ saved = { hammerCore = { startupMessage = false } } })
    login(HC)
    equal(labels(HC), "On a flight", "no record: only this release's rows")
end

-- A row added to the release already seen (a later dev build) shows on its own.
do
    local daily = { key = "daily", label = "Daily question", since = "1.3.0",
        choices = { { value = true, label = "On" }, { value = false, label = "Off" } },
        get = function() return true end, set = function() end }
    local HC, saved = start({ version = "1.3.0-dev3", extraRows = { daily },
        saved = { hammerCore = { startupMessage = false, whatsNewSeen = "1.3.0", whatsNewSeenItems = 1,
            welcomeSeen = "1.3.0", welcomeKeys = { "flights", "old", "base" } } } })
    login(HC)
    equal(labels(HC), "Daily question", "the new dev-build row shows by itself")
    equal(#saved.hammerCore.welcomeKeys, 4, "and joins the record")
end

-- Never in combat: it waits, and combat starting hides it until it ends.
do
    local combat = true
    local HC = start({ combat = function() return combat end })
    login(HC)
    equal(HC.Welcome.frame, nil, "not in combat")
    combat = false
    fire(HC.Welcome.eventFrame, "PLAYER_REGEN_ENABLED")
    equal(shown(HC), true, "it opens once combat ends")
    combat = true
    fire(HC.Welcome.eventFrame, "PLAYER_REGEN_DISABLED")
    equal(shown(HC), false, "combat hides it")
    equal(ConsecratedHammerWelcome.open, "TestAddon", "without counting as closed")
    combat = false
    fire(HC.Welcome.eventFrame, "PLAYER_REGEN_ENABLED")
    equal(shown(HC), true, "and it comes back afterwards")

    -- Show in combat waits too, and says so.
    HC.Welcome.frame:Hide()
    combat = true
    equal(HC.Welcome:Show(true), false, "Show waits in combat")
    assert(wow.LastPrint():find("after combat", 1, true), "and says so")
    combat = false
    fire(HC.Welcome.eventFrame, "PLAYER_REGEN_ENABLED")
    equal(shown(HC), true, "then opens")
end

-- "Setup on new features" off: no automatic window, What's new as usual.
do
    local HC, saved = start({ saved = { hammerCore = { startupMessage = false, welcomeAuto = false,
        whatsNewSeen = "1.2.0", whatsNewSeenItems = 1 } } })
    login(HC)
    equal(HC.Welcome.frame, nil, "the setting stops the login window")
    equal(whatsNewShown(HC), true, "What's new shows instead")
    equal(saved.hammerCore.welcomeSeen, "1.3.0", "the rows still count as seen")
    equal(HC.Welcome:AutoShow(), false, "the getter reads it")

    -- The settings row and Run setup again.
    HC.WhatsNew.frame:Hide()
    HC.Settings:Show("General")
    assert(wow.FindText("Setup on new features"), "the setting has a row")
    HC.Welcome:SetAutoShow(true)
    equal(saved.hammerCore.welcomeAuto, true, "the setter writes it")
    wow.Click(wow.FindButton("Run setup again"))
    equal(shown(HC), true, "Run setup again opens it with the setting off or on")
    equal(labels(HC), "On a flight,Old choice,Hosting", "with every row")
    equal(HC.Welcome.frame.intro.text, "Host trivia for your party.", "and the intro")
end

-- The spec can default the setting off.
do
    local HC = start({ welcome = { auto = false } })
    login(HC)
    equal(HC.Welcome.frame, nil, "auto = false defaults the setting off")
end

-- Two addons: one welcome at a time, and another addon's What's new waits.
do
    wow.Install({ TestAddon = { Version = "1.3.0" }, OtherAddon = { Version = "2.0.0" } })
    C_Timer, IsLoggedIn, ConsecratedHammerWelcome = nil, nil, nil
    local function make(name, saved, withWelcome)
        local HC = load(name)
        HC:Init({ name = name, command = name:lower(), db = function() return saved end,
            whatsNew = { { version = (name == "TestAddon") and "1.3.0" or "2.0.0", items = { "New." } } } })
        if withWelcome then
            HC.Welcome:Register({ intro = name, rows = { { key = "k", label = name .. " row",
                choices = { { value = 1, label = "One" } }, get = function() return 1 end, set = function() end } } })
        end
        HC:Start()
        return HC
    end
    local first = make("TestAddon", {}, true)
    local second = make("OtherAddon", {}, true)
    local third = make("ThirdAddon", { hammerCore = { startupMessage = false, whatsNewSeen = "1.0.0" } }, false)
    login(first); login(second); login(third)
    equal(shown(first), true, "the first welcome opens")
    equal(shown(second), false, "the second waits its turn")
    equal(whatsNewShown(third), false, "another addon's What's new waits too")
    first.Welcome.frame:Hide()
    equal(shown(second), true, "the second opens after the first closes")
    equal(whatsNewShown(third), false, "What's new still waits")
    second.Welcome.frame:Hide()
    local any = whatsNewShown(first) or whatsNewShown(second) or whatsNewShown(third)
    equal(any, true, "What's new opens once the welcomes are done")
end

-- No welcome registered: What's new is untouched.
do
    local HC = start({ noWelcome = true, saved = { hammerCore = { startupMessage = false,
        whatsNewSeen = "1.2.0", whatsNewSeenItems = 1 } } })
    login(HC)
    equal(whatsNewShown(HC), true, "addons without a welcome keep What's new")
    equal(HC.Welcome:Show(), false, "Show does nothing without a welcome")
end

report("welcome tests passed")
