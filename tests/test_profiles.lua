package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- A world the auto-switch can read: group, size and instance.
local world
local function installWorld()
    world = { group = "SOLO", size = 1, inInstance = false, kind = "none", maxPlayers = 0, id = 0,
        combat = false }
    IsInRaid = function() return world.group == "RAID" end
    IsInGroup = function() return world.group ~= "SOLO" end
    GetNumGroupMembers = function() return world.group == "SOLO" and 0 or world.size end
    IsInInstance = function() return world.inInstance, world.kind end
    GetInstanceInfo = function() return "Somewhere", world.kind, 1, "Normal", world.maxPlayers, 0, false, world.id end
    UnitName = function() return "Tester" end
    GetRealmName = function() return "Realm" end
    C_Timer = nil
end

local DEFAULTS = { point = { "CENTER", "CENTER", 0, 0 }, columns = 5, scale = 1, showNames = false,
    previewUnits = 5 }

local function addon(saved)
    wow.Install({ TestAddon = { Version = "1.0.0" } })
    installWorld()
    local ns = wow.LoadHammerCore("src", "TestAddon")
    local HC = ns.HammerCore
    saved = saved or { point = { "CENTER", "CENTER", 10, 20 }, columns = 8, scale = 1.2, showNames = true,
        previewUnits = 5 }
    HC:Init({ name = "TestAddon", command = "testaddon", db = function() return saved end })
    local applied = {}
    local P = HC.Profiles
    P:Setup({
        groups = {
            { key = "position", label = "Position", keys = { "point" }, default = true },
            { key = "grid", label = "Grid", keys = { "columns", "scale", "previewUnits" }, default = true },
            { key = "names", label = "Names", keys = { "showNames" }, default = false },
        },
        defaults = function() return DEFAULTS end,
        seed = {
            { name = "Party", values = { previewUnits = 5 } },
            { name = "Raid 20", values = { previewUnits = 20 } },
            { name = "Raid 40", values = { previewUnits = 40 } },
        },
        active = "Party",
        rules = {
            { profile = "Party", min = 1, max = 5 },
            { profile = "Raid 20", min = 6, max = 20 },
            { profile = "Raid 40", min = 21, max = 40 },
        },
        apply = function(name, reason) applied[#applied + 1] = name .. ":" .. reason end,
        unsafe = function() return world.combat end,
    })
    P:Ready()
    return HC, P, saved, applied
end

-- Seeding keeps the current layout and applies each seed's overrides.
do
    local HC, P, saved = addon()
    equal(table.concat(P:Names(), ","), "Party,Raid 20,Raid 40", "starter profiles")
    equal(P:Loaded(), "Party", "starts on the seeded active profile")
    equal(saved.hcProfiles.list["Raid 40"].columns, 8, "seeds copy the current layout")
    equal(saved.hcProfiles.list["Raid 40"].previewUnits, 40, "seed overrides apply")
    equal(saved.hcProfiles.list.Party.showNames, nil, "excluded groups are not stored")
    equal(#saved.hcProfiles.auto.rules, 3, "starter rules")
    equal(saved.hcProfiles.auto.mode, "OFF", "auto-switch starts off")
    assert(HC.Commands.byName.profile, "profile command registered")
end

-- Switching captures the outgoing profile and loads the new one.
do
    local _, P, saved, applied = addon()
    saved.point = { "BOTTOMLEFT", "BOTTOMLEFT", 100, 50 }
    saved.columns = 10
    assert(P:Switch("Raid 40", "manual"), "switch succeeds")
    equal(saved.previewUnits, 40, "target values loaded")
    equal(saved.hcProfiles.list.Party.columns, 10, "outgoing profile captured")
    equal(saved.hcProfiles.list.Party.point[3], 100, "dragged position captured")
    saved.columns = 4
    P:Switch("Party", "manual")
    equal(saved.columns, 10, "round trip restores the layout")
    equal(saved.hcProfiles.list["Raid 40"].columns, 4, "second profile kept its own change")
    equal(applied[#applied], "Party:manual", "addon told to refresh")
    -- Tables are copies, never shared with the live keys.
    saved.point[3] = 999
    equal(saved.hcProfiles.list.Party.point[3], 100, "positions are deep copies")
end

-- Combat defers the switch until FlushPending.
do
    local _, P, saved = addon()
    world.combat = true
    P:Switch("Raid 20", "manual")
    equal(P:Loaded(), "Party", "no switch in combat")
    world.combat = false
    P:FlushPending()
    equal(P:Loaded(), "Raid 20", "switch after combat")
    equal(saved.previewUnits, 20, "values loaded after combat")
end

-- Create, rename, delete, copy and reset.
do
    local _, P, saved = addon()
    local name, problem = P:Create("  ")
    equal(name, nil, "blank names refused")
    equal(problem, "Enter a name.", "blank name reason")
    equal(select(2, P:Create("party")), "That name is taken.", "names are unique ignoring case")
    saved.columns = 3
    equal(P:Create("Mythic"), "Mythic", "created")
    equal(P:Loaded(), "Mythic", "new profile becomes active")
    equal(saved.hcProfiles.list.Mythic.columns, 3, "new profile copies the active one")
    saved.hcProfiles.newFrom = "DEFAULTS"
    P:Create("Fresh")
    equal(saved.columns, 5, "defaults source starts fresh")
    assert(P:Rename("Fresh", "Clean"), "rename")
    equal(P:Loaded(), "Clean", "rename follows the active profile")
    saved.hcProfiles.auto.rules[1].profile = "Clean"
    P:Rename("Clean", "Spotless")
    equal(saved.hcProfiles.auto.rules[1].profile, "Spotless", "rename updates rules")
    assert(P:Delete("Spotless"), "delete")
    equal(saved.hcProfiles.auto.rules[1].profile, "", "deleted profile's rule becomes No change")
    assert(P:Exists(P:Loaded()), "a replacement profile is loaded")
    P:Switch("Party", "manual")
    P:CopyFrom("Mythic")
    equal(saved.columns, 3, "copy from loads the other profile's values")
    P:Reset()
    equal(saved.columns, 5, "reset to defaults")
    for _, other in ipairs(P:Names()) do if other ~= "Party" then P:Delete(other) end end
    equal(P:Count(), 1, "deleted down to one")
    local ok = P:Delete("Party")
    equal(ok, false, "the last profile cannot be deleted")
end

-- Including a group gives every profile the shared value; excluding drops it.
do
    local _, P, saved = addon()
    saved.showNames = true
    P:SetIncluded("names", true)
    equal(saved.hcProfiles.list["Raid 40"].showNames, true, "included groups seed every profile")
    P:Switch("Raid 40", "manual")
    saved.showNames = false
    P:Switch("Party", "manual")
    equal(saved.showNames, true, "an included group now switches")
    P:SetIncluded("names", false)
    equal(saved.hcProfiles.list.Party.showNames, nil, "excluded groups are dropped")
    saved.showNames = false
    P:Switch("Raid 40", "manual")
    equal(saved.showNames, false, "an excluded group is shared")
end

-- Per-character profiles remember each character's own choice.
do
    local _, P, saved = addon()
    P:SetPerCharacter(true)
    P:Switch("Raid 20", "manual")
    equal(saved.hcProfiles.characters["Tester-Realm"], "Raid 20", "character choice saved")
    equal(saved.hcProfiles.active, "Party", "account choice untouched")
    UnitName = function() return "Alt" end
    P:Ready()
    equal(P:Loaded(), "Party", "another character loads the account profile")
end

-- Rule matching.
do
    local _, P = addon()
    local Auto = P.Auto
    local rules = P:Data().auto.rules
    local function pick(context)
        local _, rule = Auto.Match(rules, context)
        return rule and rule.profile
    end
    equal(pick({ group = "SOLO", size = 1, instance = "NONE", maxPlayers = 0 }), "Party", "solo")
    equal(pick({ group = "RAID", size = 12, instance = "NONE", maxPlayers = 0 }), "Raid 20", "raid of 12")
    equal(pick({ group = "RAID", size = 8, instance = "RAID", maxPlayers = 40 }), "Raid 40",
        "instance size wins inside a 40-player raid")
    rules[2].source, rules[3].source = "GROUP", "GROUP"
    equal(pick({ group = "RAID", size = 8, instance = "RAID", maxPlayers = 40 }), "Raid 20",
        "group size ignores the instance")
    table.insert(rules, 1, { profile = "Party", group = "RAID", instance = "PVP", min = 1, max = 40,
        source = "GROUP" })
    equal(pick({ group = "RAID", size = 30, instance = "PVP", maxPlayers = 40 }), "Party",
        "first matching rule wins")
end

-- Automatic mode switches on triggers and respects a manual pick.
do
    local _, P, saved = addon()
    local Auto = P.Auto
    Auto:SetMode("AUTO")
    equal(P:Loaded(), "Party", "turning on in the open world keeps Party")
    world.group, world.size = "RAID", 25
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    equal(P:Loaded(), "Raid 40", "a 25-player raid switches to Raid 40")
    P:Switch("Party", "manual")
    world.size = 26
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    equal(P:Loaded(), "Party", "a manual pick holds while the rule is unchanged")
    world.size = 10
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    equal(P:Loaded(), "Raid 20", "the hold ends when the rule changes")
    saved.hcProfiles.auto.onSize = false
    world.size = 30
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    equal(P:Loaded(), "Raid 20", "a disabled trigger does nothing")
    world.group, world.size = "PARTY", 5
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    equal(P:Loaded(), "Party", "group type changes still fire")
end

-- Manual picks that last until the next instance.
do
    local _, P, saved = addon()
    local Auto = P.Auto
    Auto:SetMode("AUTO")
    saved.hcProfiles.auto.manual = "INSTANCE"
    P:Switch("Raid 40", "manual")
    world.group, world.size = "PARTY", 3
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    equal(P:Loaded(), "Raid 40", "held until the next instance")
    world.inInstance, world.kind, world.maxPlayers, world.id = true, "party", 5, 33
    Auto:OnEvent("PLAYER_ENTERING_WORLD")
    equal(P:Loaded(), "Party", "a new instance ends the hold")
end

-- Ask first: Switch, Not now and the combat options.
do
    local HC, P, saved = addon()
    local Auto = P.Auto
    Auto:SetMode("ASK")
    world.group, world.size = "RAID", 30
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    assert(HC.Dialog:IsShown(), "asks before switching")
    equal(P:Loaded(), "Party", "nothing changes until answered")
    wow.Click(HC.Dialog.frame.cancel)
    world.size = 31
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    equal(HC.Dialog:IsShown(), false, "a declined rule does not ask again")
    world.size = 12
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    assert(HC.Dialog:IsShown(), "a new rule asks again")
    wow.Click(HC.Dialog.frame.accept)
    equal(P:Loaded(), "Raid 20", "Switch switches")

    saved.hcProfiles.auto.afterNo = "ASK"
    world.size = 35
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    wow.Click(HC.Dialog.frame.cancel)
    world.size = 36
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    assert(HC.Dialog:IsShown(), "Ask again next time asks again")
    HC.Dialog:Dismiss()

    saved.hcProfiles.auto.combatAsk = "AFTER"
    world.combat = true
    world.size = 37
    Auto:OnEvent("GROUP_ROSTER_UPDATE")
    equal(HC.Dialog:IsShown(), false, "waits for combat to end before asking")
    world.combat = false
    Auto:OnEvent("PLAYER_REGEN_ENABLED")
    assert(HC.Dialog:IsShown(), "asks after combat")
    wow.Click(HC.Dialog.frame.accept)
    equal(P:Loaded(), "Raid 40", "switches after the late prompt")
end

-- Bad saved data recovers.
do
    local saved = { point = { "CENTER", "CENTER", 0, 0 }, columns = 5, scale = 1, previewUnits = 5,
        hcProfiles = { list = { Good = { columns = 7 }, [""] = {}, Bad = "x" }, active = "Missing",
            auto = { mode = "SIDEWAYS", rules = { { profile = "Gone", min = 30, max = 2 }, "junk" } } } }
    local _, P = addon(saved)
    equal(table.concat(P:Names(), ","), "Good", "bad profiles dropped")
    equal(P:Loaded(), "Good", "a missing active profile falls back")
    equal(saved.columns, 7, "fallback profile loaded")
    local auto = saved.hcProfiles.auto
    equal(auto.mode, "OFF", "bad mode reset")
    equal(#auto.rules, 1, "junk rules dropped")
    equal(auto.rules[1].profile, "", "missing profile becomes No change")
    equal(auto.rules[1].min .. "-" .. auto.rules[1].max, "2-30", "reversed bounds put in order")
end

-- The command lists and switches, ignoring case.
do
    local HC, P = addon()
    HC.Commands:Dispatch("profile")
    local found = false
    for _, line in ipairs(wow.printed) do
        if wow.Plain(line):find("Party (active)", 1, true) then found = true end
    end
    assert(found, "profile lists profiles")
    HC.Commands:Dispatch("profile raid 40")
    equal(P:Loaded(), "Raid 40", "profile <name> switches")
end

-- The page and selector build, and their buttons work.
do
    local HC, P = addon()
    P:NewPage({ extra = function(frame, y) return y - 30 end })
    HC.Settings:NewPage({ name = "Layout" }, function(panel, y)
        local _, nextY = P:Selector(panel, y)
        return nextY
    end)
    assert(HC.Settings:Show("Profiles"), "settings open")
    assert(HC.Settings.pages.Profiles, "profiles page built")
    assert(HC.Settings.pages.Layout, "selector page built")
    wow.Click(wow.FindButton("New..."))
    assert(HC.Dialog:IsShown(), "New opens a name prompt")
    HC.Dialog.frame.box:SetText("Arena")
    wow.Click(HC.Dialog.frame.accept)
    equal(P:Loaded(), "Arena", "the prompt creates the profile")
    wow.Click(wow.FindButton("Add rule"))
    equal(#P.Auto:Rules(), 4, "Add rule appends")
    equal(P.Auto:Rules()[4].profile, "Arena", "new rules use the active profile")
    wow.Click(wow.FindButton("Delete"))
    wow.Click(HC.Dialog.frame.accept)
    equal(P:Exists("Arena"), false, "Delete removes after confirming")
    HC.Menu:Open(P:MenuItems())
    assert(HC.Menu:IsShown(), "profile menu opens")
end

print("profiles tests passed")

-- Each main page says which profile is active and whether it saves to it.
do
    local HC, P = addon()
    P:NewPage({})
    HC.Settings:NewPage({ name = "Layout", profileGroups = { "grid" } }, function(_, y) return y end)
    HC.Settings:NewPage({ name = "Text", profileGroups = { "names" } }, function(_, y) return y end)
    HC.Settings:NewPage({ name = "Alerts" }, function(_, y) return y end)
    local tag = function() return HC.Settings.profileTag end
    assert(HC.Settings:Show("Layout"), "settings open")
    equal(tag().Text:GetText(), "Saved to profile: Party", "a profile page names its profile")
    HC.Settings:Select("Text")
    equal(tag().Text:GetText(), "Shared by all profiles (active: Party)", "an unticked group is shared")
    P:SetIncluded("names", true)
    P.RefreshSettings()
    equal(tag().Text:GetText(), "Saved to profile: Party", "ticking the group saves it per profile")
    HC.Settings:Select("Alerts")
    equal(tag().Text:GetText(), "Shared by all profiles (active: Party)", "a page outside profiles is shared")
    P:Switch("Raid 20", "manual")
    P.RefreshSettings()
    equal(tag().Text:GetText(), "Shared by all profiles (active: Raid 20)", "the tag follows a switch")
    HC.Settings:Select("Profiles")
    equal(tag():IsShown(), false, "the Profiles page needs no tag")
end
