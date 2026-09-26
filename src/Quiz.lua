local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI

-- A five-question lore quiz, opened from the quest icon on About or with
-- /<cmd> quiz.  Questions come from HC.QUIZ, filtered to this client's era
-- and the character's class and race.  The per-question timer is HammerCore's
-- to own: 8 seconds, changed only by the hidden /<cmd> quiz timer command.

local Quiz = { LENGTH = 5, REVEAL = 1.4, DEFAULT_SECONDS = 8 }
HC.Quiz = Quiz

Quiz.Prompts = {
    "Could you be Khadgar’s next assistant?",
    "Can you settle an argument in the Archivist’s library?",
    "Do you remember more than quest objectives?",
    "Which tavern tale did you dismiss too quickly?",
    "Has a bronze dragon already asked you this?",
    "Can you find the missing Kirin Tor footnote?",
    "Is one of these answers secretly a murloc?",
    "Will your innkeeper be impressed?",
    "How dusty is your adventurer’s handbook?",
    "Can you help a wandering scholar?",
    "Are the dragons testing a future historian?",
    "Why is there a question mark over your head?",
    "Will you lead the next campfire lore debate?",
    "Can you prove you read the dialogue?",
    "Should a goblin bet on your answer?",
    "Why is the library suddenly so quiet?",
    "How well do you know your favourite zone?",
    "Can you decipher this Titan tablet?",
    "Will this knowledge help in a raid?",
    "Are you ready for a little Azeroth trivia?",
}

local VERDICTS = {
    [0] = "Have you considered reading the quest text?",
    [1] = "A fresh recruit. Everyone starts somewhere.",
    [2] = "Promising. The librarians are cautiously optimistic.",
    [3] = "Well travelled. Your hearthstone has seen things.",
    [4] = "A seasoned adventurer. Bards may yet sing of you.",
    [5] = "Keeper of the Archives. Khadgar would approve.",
}

-- Forever is the Classic world; everything else is Retail.  An addon can
-- override this with spec.era.
function Quiz.Era()
    if HC.spec.era then return HC.spec.era() end
    local label = HC.spec.clientLabel and HC.spec.clientLabel() or ""
    return tostring(label):find("Forever", 1, true) and "classic" or "retail"
end

function Quiz.Seconds()
    local state = HC.State()
    local seconds = state and state.quizSeconds
    if seconds == false then return nil end
    return tonumber(seconds) or Quiz.DEFAULT_SECONDS
end

function Quiz.Eligible(entry, era, class, race)
    local entryEra = entry.era or "both"
    if entryEra ~= "both" and entryEra ~= era then return false end
    if entry.class and entry.class ~= class then return false end
    if entry.race and entry.race ~= race then return false end
    return true
end

-- Draws a run: distinct questions, each with its choices shuffled.
function Quiz.Draw(random)
    random = random or math.random
    local era = Quiz.Era()
    local _, class = UnitClass and UnitClass("player")
    local _, race = UnitRace and UnitRace("player")
    local pool = {}
    for _, entry in ipairs(HC.QUIZ or {}) do
        if Quiz.Eligible(entry, era, class, race) then pool[#pool + 1] = entry end
    end
    local run = {}
    for _ = 1, math.min(Quiz.LENGTH, #pool) do
        local entry = table.remove(pool, random(#pool))
        local choices = { entry[2], entry[3], entry[4], entry[5] }
        for i = #choices, 2, -1 do
            local j = random(i)
            choices[i], choices[j] = choices[j], choices[i]
        end
        local correct
        for index, choice in ipairs(choices) do
            if choice == entry[2] then correct = index end
        end
        run[#run + 1] = { question = entry[1], choices = choices, correct = correct }
    end
    return run
end

-- ── Window ─────────────────────────────────────────────────────────────────

local WIDTH = 460
local DESTINATIONS = { "TEXT", "SAY", "PARTY" }
local DESTINATION_LABELS = { TEXT = "Text", SAY = "Say", PARTY = "Party" }

function Quiz:ResultText()
    return "Lore quiz: " .. self.score .. "/" .. #self.run .. ". " .. self.verdict
end

local function sendChat(message, channel)
    if C_ChatInfo and type(C_ChatInfo.SendChatMessage) == "function" then
        C_ChatInfo.SendChatMessage(message, channel)
        return true
    end
    if type(SendChatMessage) == "function" then
        SendChatMessage(message, channel)
        return true
    end
end

function Quiz:Publish(destination)
    local text = self:ResultText()
    if destination == "TEXT" then
        HC.Print(text)
    elseif destination == "PARTY" and not (IsInGroup and IsInGroup()) then
        HC.Print("You are not in a party. " .. text)
    elseif sendChat(text, destination) then
        return
    else
        HC.Print(text)
    end
end

function Quiz:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", HC.FrameName("Quiz"), UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 340)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    T.Surface(frame, "outer", "edge")
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 16, -14)
    icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    local title = UI.FontString(frame, "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText(HC.name .. " lore quiz")
    frame.progress = UI.FontString(frame, "GameFontHighlightSmall", "muted")
    frame.progress:SetPoint("TOPRIGHT", -40, -18)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() frame:Hide() end)

    local track = T.Fill(frame:CreateTexture(nil, "BACKGROUND"), "rail")
    track:SetPoint("TOPLEFT", 16, -46)
    track:SetSize(WIDTH - 32, 4)
    frame.timer = T.Fill(frame:CreateTexture(nil, "ARTWORK"), "selected")
    frame.timer:SetPoint("TOPLEFT", track, "TOPLEFT")
    frame.timer:SetSize(WIDTH - 32, 4)
    frame.timerTrack = track

    frame.question = UI.FontString(frame, "GameFontHighlight")
    frame.question:SetPoint("TOPLEFT", 16, -64)
    frame.question:SetWidth(WIDTH - 32)
    frame.question:SetJustifyH("LEFT")

    frame.answers = {}
    for index = 1, 4 do
        local button = UI.Button(frame, WIDTH - 32, 30)
        button:SetPoint("TOPLEFT", 16, -104 - (index - 1) * 36)
        button:SetScript("OnClick", function() Quiz:Answer(index) end)
        frame.answers[index] = button
    end

    frame.feedback = UI.FontString(frame, "GameFontNormal", "flavour")
    frame.feedback:SetPoint("BOTTOM", 0, 52)
    frame.feedback:SetWidth(WIDTH - 32)

    frame.destinationPopup = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.destinationPopup:SetSize(114, 82)
    frame.destinationPopup:SetPoint("BOTTOM", frame, "BOTTOM", 0, 48)
    T.Surface(frame.destinationPopup, "raised", "edge")
    frame.destinationPopup:Hide()
    frame.destinations = {}
    for index, destination in ipairs(DESTINATIONS) do
        local button = UI.Button(frame.destinationPopup, 98, 22)
        button:SetPoint("TOP", 0, -6 - (index - 1) * 24)
        button:SetText(DESTINATION_LABELS[destination])
        button:SetScript("OnClick", function()
            frame.destinationPopup:Hide()
            Quiz:Publish(destination)
        end)
        frame.destinations[destination] = button
    end

    frame.again = UI.Button(frame, 104, 24)
    frame.again:SetPoint("BOTTOMLEFT", 16, 16)
    frame.again:SetText("Again")
    frame.again:SetScript("OnClick", function() Quiz:Start() end)
    frame.share = UI.Button(frame, 130, 24, "primary")
    frame.share:SetPoint("BOTTOM", 0, 16)
    frame.share:SetText("Share result")
    frame.share:SetScript("OnClick", function()
        frame.destinationPopup:SetShown(not frame.destinationPopup:IsShown())
    end)
    frame.done = UI.Button(frame, 104, 24)
    frame.done:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.done:SetText("Close")
    frame.done:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnUpdate", function(_, elapsed) Quiz:Tick(elapsed) end)
    frame:SetScript("OnHide", function()
        Quiz.phase = nil
        frame.destinationPopup:Hide()
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = frame:GetName() end
    self.frame = frame
    return frame
end

function Quiz:Start()
    local frame = self:Create()
    self.run, self.index, self.score = Quiz.Draw(), 0, 0
    frame:Show()
    frame:Raise()
    frame.again:Hide()
    frame.share:Hide()
    frame.destinationPopup:Hide()
    frame.done:Hide()
    if #self.run == 0 then
        self.phase = "done"
        frame.question:SetText("The archives are empty for this character.")
        for _, button in ipairs(frame.answers) do button:Hide() end
        return
    end
    self:Next()
end

function Quiz:Next()
    local frame = self.frame
    self.index = self.index + 1
    local item = self.run[self.index]
    if not item then return self:Finish() end
    self.phase, self.remaining, self.limit = "asking", Quiz.Seconds(), Quiz.Seconds()
    frame.progress:SetText(self.index .. " of " .. #self.run)
    frame.question:SetText(item.question)
    for index, button in ipairs(frame.answers) do
        button:SetText(item.choices[index])
        T.Border(button, "edge")
        button:SetEnabled(true)
        button:Show()
    end
    frame.feedback:SetText("")
    frame.timerTrack:SetShown(self.limit ~= nil)
    frame.timer:SetShown(self.limit ~= nil)
    frame.timer:SetWidth(WIDTH - 32)
end

-- index is the chosen answer, or nil when the timer ran out.
function Quiz:Answer(index)
    if self.phase ~= "asking" then return end
    local frame, item = self.frame, self.run[self.index]
    local right = index == item.correct
    if right then self.score = self.score + 1 end
    for _, button in ipairs(frame.answers) do button:SetEnabled(false) end
    T.Border(frame.answers[item.correct], "accent")
    if index and not right then T.Border(frame.answers[index], "danger") end
    frame.feedback:SetText(right and "Correct!" or (index and "Not quite." or "Out of time!"))
    self.phase, self.remaining = "reveal", Quiz.REVEAL
end

function Quiz:Tick(elapsed)
    if self.phase == "asking" and self.limit then
        self.remaining = self.remaining - elapsed
        local share = math.max(0, self.remaining / self.limit)
        self.frame.timer:SetWidth(math.max(1, (WIDTH - 32) * share))
        if self.remaining <= 0 then self:Answer(nil) end
    elseif self.phase == "reveal" then
        self.remaining = self.remaining - elapsed
        if self.remaining <= 0 then self:Next() end
    end
end

function Quiz:Finish()
    local frame = self.frame
    self.phase = "done"
    local state = HC.State()
    local best = math.max(tonumber(state.quizBest) or 0, self.score)
    state.quizBest = best
    local total = #self.run
    local verdict = VERDICTS[math.floor(self.score / math.max(1, total) * 5 + 0.5)] or VERDICTS[0]
    frame.progress:SetText("Best " .. best .. " of " .. total)
    frame.question:SetText(self.score .. " of " .. total .. ". " .. verdict)
    for _, button in ipairs(frame.answers) do button:Hide() end
    frame.timerTrack:Hide()
    frame.timer:Hide()
    frame.feedback:SetText("")
    frame.again:Show()
    frame.share:Show()
    frame.destinationPopup:Hide()
    frame.done:Show()
    self.verdict = verdict
end

function Quiz.Verdicts() return VERDICTS end
