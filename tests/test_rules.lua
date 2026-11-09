package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

wow.Install({ TestAddon = { Version = "1.0.0" } })
local ns = wow.LoadHammerCore("src", "TestAddon")
local Auto = ns.HammerCore.Profiles.Auto

-- Sets: several groups or places per rule; none ticked is any.
local rule = { profile = "P", group = { PARTY = true, RAID = true }, instance = { PARTY = true },
    min = 1, max = 40, source = "GROUP" }
local function picks(context) local _, r = Auto.Match({ rule }, context); return r ~= nil end
equal(picks({ group = "PARTY", size = 5, instance = "PARTY", maxPlayers = 5 }), true, "party in a dungeon")
equal(picks({ group = "RAID", size = 5, instance = "PARTY", maxPlayers = 5 }), true, "raid in a dungeon")
equal(picks({ group = "SOLO", size = 1, instance = "PARTY", maxPlayers = 5 }), false, "solo isn't ticked")
equal(picks({ group = "PARTY", size = 5, instance = "NONE", maxPlayers = 0 }), false, "open world isn't ticked")
rule.group, rule.instance = {}, {}
equal(picks({ group = "SOLO", size = 1, instance = "NONE", maxPlayers = 0 }), true, "empty sets match anything")

-- Older single-value rules still read.
rule.group, rule.instance = "RAID", "ANY"
equal(picks({ group = "RAID", size = 10, instance = "NONE", maxPlayers = 0 }), true, "old string still matches")
equal(picks({ group = "PARTY", size = 5, instance = "NONE", maxPlayers = 0 }), false, "old string still excludes")
equal(next(Auto.CleanSet("ANY", Auto.GROUPS)), nil, "old ANY becomes the empty set")
equal(Auto.CleanSet("RAID", Auto.GROUPS).RAID, true, "old value becomes a one-item set")
equal(next(Auto.CleanSet({ SOLO = true, PARTY = true, RAID = true }, Auto.GROUPS)), nil,
    "everything ticked is the same as any")
equal(Auto.CleanSet({ BOGUS = true, RAID = true }, Auto.GROUPS).BOGUS, nil, "unknown choices are dropped")

-- Summaries.
equal(Auto.Describe({ group = { PARTY = true, RAID = true }, instance = {}, min = 1, max = 5 }),
    "Party or raid, 1-5 players, anywhere", "two groups read naturally")
equal(Auto.Describe({ group = "ANY", instance = "RAID", min = 10, max = 10 }),
    "Any group, 10 players, raid", "old strings still describe")
print("test_rules: ok")
