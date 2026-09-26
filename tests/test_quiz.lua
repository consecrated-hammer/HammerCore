package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true,
    MAGE = true, WARLOCK = true, DRUID = true, DEATHKNIGHT = true, MONK = true, DEMONHUNTER = true, EVOKER = true }
local RACES = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Draenei = true, Worgen = true,
    Orc = true, Scourge = true, Tauren = true, Troll = true, BloodElf = true, Goblin = true, Pandaren = true,
    Dracthyr = true, EarthenDwarf = true }

local function addon(label, class, race)
    wow.Install({ TestAddon = { Version = "1.0.0" } })
    UnitClass = function() return class, class end
    UnitRace = function() return race, race end
    local saved = {}
    local ns = wow.LoadHammerCore("src", "TestAddon")
    ns.HammerCore:Init({ name = "TestAddon", command = "testaddon", db = function() return saved end,
        clientLabel = function() return label end })
    return ns.HammerCore, saved
end

-- ── The library itself ─────────────────────────────────────────────────────
do
    local HC = addon("Retail", "PRIEST", "Human")
    local seen = {}
    equal(#HC.QUIZ >= 100, true, "the library holds at least 100 questions")
    for index, entry in ipairs(HC.QUIZ) do
        local where = "question " .. index .. " (" .. tostring(entry[1]) .. ")"
        equal(type(entry[1]), "string", where .. " has text")
        local choices = {}
        for i = 2, 5 do
            equal(type(entry[i]) == "string" and entry[i] ~= "", true, where .. " choice " .. (i - 1) .. " is text")
            equal(choices[entry[i]], nil, where .. " choices are distinct")
            choices[entry[i]] = true
        end
        equal(entry[6], nil, where .. " has exactly four choices")
        local era = entry.era or "both"
        equal(era == "both" or era == "classic" or era == "retail", true, where .. " has a known era")
        equal(entry.class == nil or CLASSES[entry.class] == true, true, where .. " names a real class token")
        equal(entry.race == nil or RACES[entry.race] == true, true, where .. " names a real race token")
        local key = entry[1] .. "|" .. era .. "|" .. tostring(entry.class) .. "|" .. tostring(entry.race)
        equal(seen[key], nil, where .. " is not a duplicate")
        seen[key] = true
    end
end

-- ── Who sees what ─────────────────────────────────────────────────────────
do
    local HC = addon("WoW Forever", "PRIEST", "Human")
    equal(HC.Quiz.Era(), "classic", "WoW Forever draws Classic questions")
    local sawRetail, sawOther = false, false
    for _ = 1, 60 do
        for _, item in ipairs(HC.Quiz.Draw()) do
            for _, entry in ipairs(HC.QUIZ) do
                if entry[1] == item.question then
                    if entry.era == "retail" then sawRetail = true end
                    if (entry.class and entry.class ~= "PRIEST") or (entry.race and entry.race ~= "Human") then sawOther = true end
                end
            end
        end
    end
    equal(sawRetail, false, "Forever never sees Retail questions")
    equal(sawOther, false, "a human priest never sees another class or race's questions")
    local priestQuestions = 0
    for _, entry in ipairs(HC.QUIZ) do
        if entry.class == "PRIEST" and HC.Quiz.Eligible(entry, "classic", "PRIEST", "Human") then
            priestQuestions = priestQuestions + 1
        end
    end
    equal(priestQuestions > 0, true, "a priest can see priest questions")

    local run = HC.Quiz.Draw()
    equal(#run, 5, "a run has five questions")
    local questions = {}
    for _, item in ipairs(run) do
        equal(questions[item.question], nil, "questions do not repeat in a run")
        questions[item.question] = true
        for _, entry in ipairs(HC.QUIZ) do
            if entry[1] == item.question then
                equal(item.choices[item.correct], entry[2], "the marked answer is the correct one")
            end
        end
    end
end

do
    local HC = addon("Retail", "PALADIN", "Draenei")
    equal(HC.Quiz.Era(), "retail", "Retail draws Retail questions")
    local eligible = 0
    for _, entry in ipairs(HC.QUIZ) do
        if HC.Quiz.Eligible(entry, "retail", "PALADIN", "Draenei") then eligible = eligible + 1 end
        if entry.race == "Draenei" then
            equal(HC.Quiz.Eligible(entry, "retail", "PALADIN", "Draenei"), true, "a draenei sees draenei questions")
            equal(HC.Quiz.Eligible(entry, "retail", "PALADIN", "Human"), false, "a human does not")
        end
        if entry.era == "classic" then
            equal(HC.Quiz.Eligible(entry, "retail", "PALADIN", "Draenei"), false, "Retail skips Classic-only questions")
        end
    end
    equal(eligible >= 5, true, "every character has enough questions")
end

-- ── A run from start to finish ─────────────────────────────────────────────
do
    local HC, saved = addon("Retail", "MAGE", "Gnome")
    HC.Quiz:Start()
    local quiz, frame = HC.Quiz, HC.Quiz.frame
    equal(frame:IsShown(), true, "the quiz opens")
    equal(frame.progress:GetText(), "1 of 5", "progress starts at one")

    wow.Click(frame.answers[quiz.run[1].correct])
    equal(quiz.score, 1, "a right answer scores")
    equal(frame.feedback:GetText(), "Correct!", "and says so")
    frame.scripts.OnUpdate(frame, 2)
    equal(frame.progress:GetText(), "2 of 5", "the reveal moves on to the next question")

    frame.scripts.OnUpdate(frame, 9)
    equal(frame.feedback:GetText(), "Out of time!", "eight seconds runs out")
    equal(quiz.score, 1, "a timeout does not score")
    frame.scripts.OnUpdate(frame, 2)

    for question = 3, 5 do
        local wrong = quiz.run[question].correct % 4 + 1
        wow.Click(frame.answers[wrong])
        frame.scripts.OnUpdate(frame, 2)
    end
    equal(quiz.phase, "done", "the quiz finishes after five")
    equal(saved.hammerCore.quizBest, 1, "the best score is saved")
    wow.Click(frame.share)
    equal(frame.destinationPopup:IsShown(), true, "share opens the destination popup")
    equal(#wow.printed, 0, "opening the popup does not share")
    wow.Click(frame.destinations.TEXT)
    equal(wow.LastPrint(), "TestAddon: Lore quiz: 1/5. A fresh recruit. Everyone starts somewhere.",
        "text shares the concise result through addon chat")

    local result = "Lore quiz: 1/5. A fresh recruit. Everyone starts somewhere."
    local say, party = frame.destinations.SAY, frame.destinations.PARTY

    -- Say and Party are secure macro buttons armed when the popout opens.
    IsInGroup = function() return false end
    wow.Click(frame.share)
    equal(say.template, "SecureActionButtonTemplate,BackdropTemplate", "Say is a secure button")
    equal(say:GetAttribute("type"), "macro", "Say runs a macro")
    equal(say:GetAttribute("macrotext"), "/s " .. result, "Say's macro posts the result")
    equal(say:GetAttribute("useOnKeyDown"), false, "Say fires on mouse-up like its click registration")
    equal(party.enabled, false, "Party is disabled when solo")
    equal(party:GetAttribute("macrotext"), nil, "and has no macro")
    equal(rawget(say.scripts, "OnClick"), nil, "the secure template keeps OnClick")
    say.scripts.PostClick(say)
    equal(frame.destinationPopup:IsShown(), false, "clicking Say closes the popout")
    equal(#wow.sentMessages, 0, "the addon itself never calls the chat API")

    IsInGroup = function() return true end
    wow.Click(frame.share)
    equal(party.enabled, true, "Party is enabled in a group")
    equal(party:GetAttribute("macrotext"), "/p " .. result, "Party's macro posts the result")
    wow.Click(frame.share)

    -- Share is disabled while chat is restricted, and re-enabled after.
    InCombatLockdown = function() return true end
    frame.scripts.OnEvent(frame, "PLAYER_REGEN_DISABLED")
    equal(frame.share.enabled, false, "Share is disabled in combat")
    wow.Click(frame.share)
    equal(frame.destinationPopup:IsShown(), false, "and cannot open")
    InCombatLockdown = function() return false end
    frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
    equal(frame.share.enabled, true, "Share returns after combat")

    Enum = Enum or {}
    Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4 }
    local active = {}
    C_RestrictedActions = { IsAddOnRestrictionActive = function(kind) return active[kind] == true end }
    active[2] = true
    frame.scripts.OnEvent(frame, "ADDON_RESTRICTION_STATE_CHANGED")
    equal(frame.share.enabled, false, "Share is disabled during a keystone")
    active[2] = nil
    active[4] = true
    frame.scripts.OnEvent(frame, "ADDON_RESTRICTION_STATE_CHANGED")
    equal(frame.share.enabled, true, "map restrictions alone do not block chat")
    C_RestrictedActions = nil
end

-- ── The hidden timer setting ───────────────────────────────────────────────
do
    local HC, saved = addon("Retail", "MAGE", "Gnome")
    SlashCmdList.TESTADDON("quiz timer 12")
    equal(saved.hammerCore.quizSeconds, 12, "the timer can be changed")
    equal(HC.Quiz.Seconds(), 12, "and is used")
    SlashCmdList.TESTADDON("quiz timer 99")
    equal(wow.LastPrint(), "TestAddon: usage: /testaddon quiz timer <3-30|off>", "out-of-range values are refused")
    SlashCmdList.TESTADDON("quiz timer off")
    equal(HC.Quiz.Seconds(), nil, "the timer can be switched off")
    HC.Quiz:Start()
    HC.Quiz.frame.scripts.OnUpdate(HC.Quiz.frame, 60)
    equal(HC.Quiz.phase, "asking", "with no timer a question waits")

    wow.printed = {}
    SlashCmdList.TESTADDON("help")
    local listed, hidden = false, false
    for _, line in ipairs(wow.printed) do
        local plain = wow.Plain(line)
        if plain:find("/testaddon quiz - ", 1, true) then listed = true end
        if plain:find("quiz timer", 1, true) then hidden = true end
    end
    equal(listed, true, "quiz is listed in help")
    equal(hidden, false, "quiz timer stays hidden")
end

io.write("hammercore quiz tests passed\n")
