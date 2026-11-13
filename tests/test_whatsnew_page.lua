package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local NOTES = {
    { version = "1.3.0", date = "2026-11-09", items = {
        { text = "Profiles.", page = "General" },
        "A plain note.",
        { title = "Faster", text = "Loads quicker.", kind = "improved", client = "forever" },
        { text = "Fixed a thing.", kind = "fix", client = "retail" },
    } },
    { version = "1.2.0", date = "2026-11-01", items = { { text = "A fix.", page = "General" } } },
    { version = "1.0.0", date = "2026-08-16", history = true, items = { "First stable release." } },
}

local function start(saved, notes)
    wow.Install({ TestAddon = { Version = "1.3.0-dev2" } })
    C_Timer = nil
    local ns = wow.LoadHammerCore("src", "TestAddon")
    local HC = ns.HammerCore
    HC:Init({ name = "TestAddon", command = "testaddon", db = function() return saved end,
        whatsNew = notes or NOTES })
    HC.Settings:NewPage({ name = "General" }, function(_, y) return y end)
    HC:Start()
    return HC
end

-- A font string whose text contains `needle` (colour codes stripped).
local function findContaining(needle)
    for _, region in ipairs(wow.regions) do
        if region.text and wow.Plain(region.text):find(needle, 1, true) then return region end
    end
end

local function names(HC)
    local list = {}
    for _, spec in ipairs(HC.Settings.order) do list[#list + 1] = spec.name end
    return table.concat(list, ",")
end

-- The page leads REFERENCE and lists every release with dates.
do
    local saved = { hammerCore = { startupMessage = false } }
    local HC = start(saved)
    HC.Settings:Show("General")
    equal(names(HC), "General,Visibility,What's new,Commands,Troubleshooting,About", "rail order")
    local badge = HC.Settings.buttons["What's new"].unreadBadge
    assert(badge, "the What's new rail button has a badge")
    equal(badge.shown, true, "the badge shows before the page is visited")
    assert(wow.FindText("TestAddon 1.3.0"), "newest release listed")
    assert(wow.FindText("Latest"), "the newest release is tagged Latest")
    assert(findContaining("9 November 2026"), "release dates are written out")
    assert(findContaining("Minor release     New features: 2     Improvements: 1     Bug fixes: 1"),
        "the card header counts features and fixes")
    assert(wow.FindText("EARLIER RELEASES"), "history entries sit under Earlier releases")
    assert(wow.FindText("First stable release."), "history lines listed")
    assert(wow.FindText("NEW FEATURES") and wow.FindText("IMPROVEMENTS") and wow.FindText("BUG FIXES"),
        "items are grouped by kind")
    assert(findContaining("WoW Forever  -  Faster"), "client tags lead their item")
    assert(wow.FindText("Loads quicker."), "a titled item shows its text below")
    assert(findContaining("Retail  -  Fixed a thing."), "fixes are tagged too")
    assert(wow.FindButton("Open General"), "highlights link their page")

    -- Only the newest card starts open; clicking a header toggles it.
    local cards = HC.Pages.whatsNewCards
    equal(cards[1].body.shown, true, "the newest release starts open")
    equal(cards[2].body.shown, false, "older releases start collapsed")
    wow.Click(cards[2].head)
    equal(cards[2].body.shown, true, "clicking a header opens it")
    wow.Click(cards[2].head)
    equal(cards[2].body.shown, false, "and clicking again closes it")

    equal(badge.texture, "Interface\\GossipFrame\\AvailableQuestIcon", "unread shows the quest-giver !")
    local played = {}
    PlaySound = function(kit, channel) played[#played + 1] = kit .. ":" .. channel; return true end
    HC.Settings:Show("What's new")
    equal(badge.texture, "Interface\\GossipFrame\\ActiveQuestIcon", "opening the page plays the turn-in ?")
    equal(table.concat(played, ","), "878:SFX", "and the quest turn-in sound")
    equal(badge.shown, true, "the turn-in shows while it fades")
    badge.complete.scripts.OnFinished()
    equal(badge.shown, false, "the badge clears once the turn-in fades")
    equal(badge.texture, "Interface\\GossipFrame\\AvailableQuestIcon", "the badge resets for next time")
    HC.Settings:Show("General")
    HC.Settings:Show("What's new")
    equal(#played, 1, "the sound plays only when the ! clears")
    equal(saved.hammerCore.whatsNewPageSeen, "1.3.0:4", "the visit is remembered")
    HC.Settings:Show("General")
    equal(badge.shown, false, "the badge stays clear on other pages")
    wow.Click(wow.FindButton("Open General"))
    equal(HC.Settings.selected, "General", "Open buttons go to their page")
end

-- A new highlight, or a newer release, brings the badge back; the setting hides it.
do
    local saved = { hammerCore = { startupMessage = false, whatsNewPageSeen = "1.3.0:1" } }
    local HC = start(saved)
    HC.Settings:Show("General")
    local badge = HC.Settings.buttons["What's new"].unreadBadge
    equal(badge.shown, true, "a highlight added to the seen release counts as unread")
    HC.State().whatsNewDot = false
    HC.Settings:RefreshBadges()
    equal(badge.shown, false, "Mark unread What's new off hides the badge")
    HC.Settings:Show("Visibility")
    assert(wow.FindText("Show unread marker"), "the badge setting is on Visibility")
    assert(wow.FindText("What's new sound"), "the sound setting is on Visibility")

    -- whatsnew reset steps back a release and brings the badge back.
    HC.State().whatsNewDot = true
    saved.hammerCore.whatsNewPageSeen = "1.3.0:4"
    HC.Settings:RefreshBadges()
    equal(badge.shown, false, "badge clear before the reset")
    HC.Commands:Dispatch("whatsnew reset")
    equal(badge.shown, true, "whatsnew reset brings the badge back")
    equal(saved.hammerCore.whatsNewPageSeen, nil, "and forgets the page visit")
    local newest = HC.WhatsNew:Releases()[2]
    equal(saved.hammerCore.whatsNewSeen, tostring(HC.WhatsNew.Base(newest.version)),
        "and steps the seen release back one, so the popup shows on reload")

    -- Sound falls back to the file when the kit is refused, and says so.
    local files = {}
    PlaySound = function() return false end
    PlaySoundFile = function(file, channel) files[#files + 1] = file; return true end
    HC.Commands:Dispatch("whatsnew sound")
    equal(files[1], "Sound\\Interface\\iQuestComplete.ogg", "the turn-in falls back to the sound file")
    equal(HC.WhatsNew.lastSound, "sound file Sound\\Interface\\iQuestComplete.ogg", "and records which played")
    PlaySound, PlaySoundFile = nil, nil
end

-- History entries never pop up after an update, even for an old seen version.
do
    local saved = { hammerCore = { startupMessage = false, whatsNewSeen = "0.9.0" } }
    local HC = start(saved)
    local unseen = HC.WhatsNew:Unseen("0.9.0", "1.3.0", 0)
    equal(#unseen, 2, "only the two normal releases are unseen")
    equal(unseen[2].version, "1.2.0", "history is left for the page")
end

-- About's What's new button opens the page.
do
    local HC = start({ hammerCore = { startupMessage = false } })
    HC.Settings:Show("About")
    wow.Click(wow.FindButton("What's new"))
    equal(HC.Settings.selected, "What's new", "About opens the What's new page")
end

-- Addons without highlights get no page.
do
    wow.Install({ TestAddon = { Version = "1.0.0" } })
    local ns = wow.LoadHammerCore("src", "TestAddon")
    local HC = ns.HammerCore
    local saved = {}
    HC:Init({ name = "TestAddon", command = "testaddon", db = function() return saved end })
    HC:Start()
    HC.Settings:Show()
    equal(HC.Settings.pages["What's new"], nil, "no highlights, no page")
end

print("what's new page tests passed")
