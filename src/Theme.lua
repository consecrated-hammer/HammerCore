local addonName, ns = ...
local HC = ns.HammerCore

-- Every colour and surface in HammerCore's settings goes through a named
-- role here; controls never hard-code a colour.  A second theme (Classic:
-- Blizzard dialog frames, circa 2004) is therefore a new entry in `registry`
-- plus its own Surface/Text rules, not a rewrite of every page.

local Theme = {}
HC.Theme = Theme

local WHITE = "Interface\\Buttons\\WHITE8X8"

Theme.registry = {
    modern = {
        label = "Modern",
        available = true,
        -- Warm charcoal with a forge-gold accent.
        colours = {
            outer = { 0.063, 0.059, 0.055, 0.98 },
            rail = { 0.090, 0.082, 0.075, 1 },
            content = { 0.118, 0.110, 0.102, 1 },
            header = { 0.150, 0.137, 0.125, 1 },
            raised = { 0.157, 0.145, 0.133, 1 },
            -- Alternate setting rows; quiet enough to read as one block.
            stripe = { 0.141, 0.131, 0.121, 1 },
            hover = { 0.196, 0.180, 0.161, 1 },
            edge = { 0.235, 0.216, 0.192, 1 },
            field = { 0.078, 0.073, 0.067, 1 },
            menu = { 0.071, 0.067, 0.059, 1 },
            menuEdge = { 0.400, 0.349, 0.282, 1 },
            menuActive = { 0.220, 0.188, 0.141, 1 },
            accent = { 0.918, 0.733, 0.420, 1 },
            selected = { 0.918, 0.733, 0.420, 1 },
            link = { 0.918, 0.733, 0.420, 1 },
            linkHover = { 1, 0.882, 0.620, 1 },
            muted = { 0.612, 0.584, 0.545, 1 },
            section = { 0.690, 0.651, 0.596, 1 },
            text = { 0.957, 0.937, 0.906, 1 },
            danger = { 0.851, 0.380, 0.329, 1 },
            -- Client tags in What's new.
            retail = { 0.427, 0.667, 0.949, 1 },
            forever = { 0.918, 0.733, 0.420, 1 },
            -- Warm parchment for whimsical copy such as About tips.
            flavour = { 0.93, 0.85, 0.66, 1 },
            transparent = { 0, 0, 0, 0 },
        },
    },
    -- Blizzard's own look, circa 2004: dialog-framed windows, tooltip-bordered
    -- cards, gold headings, red panel buttons and the classic checkbox.
    -- Switched off (owner, 2026-09-26: "needs a LOT of work"); a saved choice
    -- falls back to Modern.  Tests switch it on to keep it building.
    classic = {
        label = "Classic",
        available = false,
        colours = {
            outer = { 1, 1, 1, 1 },
            rail = { 0.06, 0.06, 0.06, 0.92 },
            content = { 0, 0, 0, 0.35 },
            raised = { 0.09, 0.09, 0.09, 0.88 },
            edge = { 0.78, 0.78, 0.78, 1 },
            menu = { 0.04, 0.04, 0.04, 0.96 },
            menuEdge = { 0.85, 0.85, 0.85, 1 },
            menuActive = { 0.30, 0.24, 0.05, 0.9 },
            accent = { 1, 0.82, 0, 1 },
            selected = { 1, 0.82, 0, 1 },
            muted = { 0.72, 0.72, 0.72, 1 },
            section = { 1, 0.82, 0, 1 },
            text = { 1, 1, 1, 1 },
            danger = { 1, 0.32, 0.26, 1 },
            header = { 0.06, 0.06, 0.06, 0.92 },
            stripe = { 0.08, 0.08, 0.08, 0.6 },
            hover = { 0.20, 0.16, 0.05, 0.9 },
            field = { 0.04, 0.04, 0.04, 0.96 },
            link = { 1, 0.82, 0, 1 },
            linkHover = { 1, 0.93, 0.5, 1 },
            retail = { 0.427, 0.667, 0.949, 1 },
            forever = { 1, 0.82, 0, 1 },
            flavour = { 0.93, 0.85, 0.66, 1 },
            transparent = { 0, 0, 0, 0 },
        },
        -- Bordered surfaces use Blizzard's framed backdrops, chosen by the
        -- background role.  Borderless fills stay flat in every theme.
        surfaces = {
            outer = { bg = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edge = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32, inset = 11, tile = 32 },
            raised = { bg = "Interface\\Tooltips\\UI-Tooltip-Background",
                edge = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16, inset = 4, tile = 16 },
            rail = { bg = "Interface\\Tooltips\\UI-Tooltip-Background",
                edge = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, inset = 3, tile = 16 },
            menu = { bg = "Interface\\Tooltips\\UI-Tooltip-Background",
                edge = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16, inset = 4, tile = 16 },
        },
    },
}

Theme.order = { "modern", "classic" }

-- A scoped presentation, deliberately independent of the hidden saved theme.
-- Resolve only once the addon's character database exists. Speedster's secure
-- button is constructed before HC:Start, so Start alone is too late.
local presentation
function Theme.IsBlizzard()
    if presentation == nil and HC.spec and HC.spec.db and HC.spec.db() then
        presentation = HC.spec.presentation == "blizzard"
    end
    return presentation == true
end

local native = { label = "Blizzard", available = false, colours = {} }
for role, colour in pairs(Theme.registry.classic.colours) do native.colours[role] = colour end
for _, role in ipairs({ "outer", "rail", "content", "header", "raised", "field", "menu" }) do
    native.colours[role] = { 1, 1, 1, 1 }
end
native.colours.hover = { 1, 0.94, 0.75, 1 }
native.colours.menuActive = { 1, 0.94, 0.75, 1 }
Theme.registry.blizzard = native

-- Artwork comes from the client; all frames remain owned by this addon.
Theme.NATIVE = {
    background = "Interface\\DialogFrame\\UI-DialogBox-Background",
    dark = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    border = "Interface\\DialogFrame\\UI-DialogBox-Border",
    inset = "Interface\\Tooltips\\UI-Tooltip-Background",
    insetBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
    highlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    check = "Interface\\Buttons\\UI-CheckBox-Check",
    arrow = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
    thumb = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal",
    scrollThumb = "Interface\\Buttons\\UI-ScrollBar-Knob",
    progress = "Interface\\TargetingFrame\\UI-StatusBar",
}

-- These helpers replace art without inheriting scripts or automatic toggles.
function Theme.CheckArt(texture)
    if not Theme.IsBlizzard() then return end
    texture:SetTexture(Theme.NATIVE.check)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetSize(18, 18)
end

function Theme.ButtonArt(button)
    if not Theme.IsBlizzard() then return end
    button:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    button:SetDisabledTexture("Interface\\Buttons\\UI-Panel-Button-Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local texture = button[getter] and button[getter](button)
        if texture and texture.SetTexCoord then texture:SetTexCoord(0, 0.625, 0, 0.6875) end
    end
end

function Theme.SliderArt(slider, thumb, track, vertical)
    if not Theme.IsBlizzard() then return end
    if track then track:SetTexture("Interface\\Buttons\\UI-SliderBar-Background"); track:SetVertexColor(1, 1, 1, 1) end
    thumb:SetTexture(vertical and Theme.NATIVE.scrollThumb or Theme.NATIVE.thumb)
    thumb:SetVertexColor(1, 1, 1, 1)
    thumb:SetSize(vertical and 16 or 28, vertical and 24 or 28)
    if vertical then slider:SetWidth(16) end
end

function Theme.IconBorder(icon, parent)
    if not Theme.IsBlizzard() then return end
    if parent.SetPushedTexture then
        parent:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        parent:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        for _, getter in ipairs({ "GetPushedTexture", "GetHighlightTexture" }) do
            local texture = parent[getter] and parent[getter](parent)
            if texture then texture:ClearAllPoints(); texture:SetAllPoints(icon) end
        end
    end
    local border = parent:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -6, 6)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 6, -6)
    return border
end


-- The theme is fixed when the settings window is built.  Changing it takes
-- effect after a reload, which keeps every control free of re-skin logic.
function Theme.Active()
    if Theme.IsBlizzard() then return native, "blizzard" end
    local state = HC.State and HC.spec and HC.State()
    local key = state and state.theme or "modern"
    local theme = Theme.registry[key]
    if not (theme and theme.available) then key, theme = "modern", Theme.registry.modern end
    return theme, key
end

function Theme.Colour(role)
    local colours = Theme.Active().colours
    return colours[role] or colours.text
end

function Theme.Unpack(role)
    local c = Theme.Colour(role)
    return c[1], c[2], c[3], c[4]
end

function Theme.IsClassic()
    return Theme.IsBlizzard() or select(2, Theme.Active()) == "classic"
end

-- A panel: background role plus an optional border role.  Modern draws a
-- flat fill and a 1px line; a theme with framed surfaces swaps in its
-- textured backdrop for bordered panels of that background role.
function Theme.Surface(frame, background, border)
    if not frame.SetBackdrop then return frame end
    if Theme.IsBlizzard() then
        local outer = background == "outer"
        local clear = background == "transparent"
        frame:SetBackdrop({ bgFile = clear and Theme.NATIVE.highlight or (background == "field" or background == "menu") and Theme.NATIVE.inset or Theme.NATIVE.dark,
            edgeFile = border and (outer and Theme.NATIVE.border or Theme.NATIVE.insetBorder) or nil,
            tile = not clear, tileSize = 32, edgeSize = border and (outer and 32 or 8) or nil,
            insets = { left = outer and 11 or 3, right = outer and 11 or 3, top = outer and 11 or 3, bottom = outer and 11 or 3 } })
        frame:SetBackdropColor(Theme.Unpack(background))
        if border then frame:SetBackdropBorderColor(1, 1, 1, 1) end
        frame.hcPresentation = "blizzard"
        return frame
    end
    local theme = Theme.Active()
    local framed = border and theme.surfaces and theme.surfaces[background]
    if framed then
        frame:SetBackdrop({ bgFile = framed.bg, edgeFile = framed.edge, tile = true, tileSize = framed.tile,
            edgeSize = framed.edgeSize,
            insets = { left = framed.inset, right = framed.inset, top = framed.inset, bottom = framed.inset } })
        frame:SetBackdropColor(Theme.Unpack(background))
        frame:SetBackdropBorderColor(Theme.Unpack(border))
        return frame
    end
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = border and WHITE or nil, edgeSize = border and 1 or nil })
    frame:SetBackdropColor(Theme.Unpack(background))
    if border then frame:SetBackdropBorderColor(Theme.Unpack(border)) end
    return frame
end

function Theme.Border(frame, border)
    if Theme.IsBlizzard() then
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(1, 1, 1, 1) end
        -- Selection and quiz verdicts must remain visible even on native panel
        -- buttons, which may not expose SetBackdropBorderColor at all.
        local active = border == "accent" or border == "selected" or border == "danger"
        if active and not frame.hcNativeFeedback then
            local glow = frame:CreateTexture(nil, "OVERLAY")
            glow:SetTexture(Theme.NATIVE.highlight)
            glow:SetAllPoints()
            frame.hcNativeFeedback = glow
        end
        if frame.hcNativeFeedback then
            frame.hcNativeFeedback:SetShown(active)
            if active then
                local colour = Theme.Colour(border)
                frame.hcNativeFeedback:SetVertexColor(colour[1], colour[2], colour[3], 0.35)
            end
        end
        frame.hcNativeFeedbackRole = active and border or nil
        local label = rawget(frame, "Text")
        if label then
            if active then Theme.Text(label, border)
            elseif frame.hcNativeTextColour then label:SetTextColor(unpack(frame.hcNativeTextColour)) end
        end
        return
    end
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(Theme.Unpack(border)) end
end

function Theme.Fill(texture, role)
    if Theme.IsBlizzard() then
        local background = role == "rail" or role == "header" or role == "content" or role == "outer" or role == "field"
        texture:SetTexture(background and Theme.NATIVE.dark or Theme.NATIVE.highlight)
        if role == "stripe" or role == "transparent" then texture:SetVertexColor(1, 1, 1, 0)
        elseif background then texture:SetVertexColor(1, 1, 1, 1)
        else texture:SetVertexColor(Theme.Unpack(role)) end
        return texture
    end
    texture:SetColorTexture(Theme.Unpack(role))
    return texture
end

function Theme.Text(fontString, role)
    fontString:SetTextColor(Theme.Unpack(role or "text"))
    return fontString
end

-- HammerCore's own textures, vendored with it into Libs/HammerCore/Textures.
-- They're white so any role can tint them.
function Theme.Media(name)
    return "Interface\\AddOns\\" .. tostring(addonName) .. "\\Libs\\HammerCore\\Textures\\" .. name
end

-- A tinted HammerCore texture.
function Theme.Icon(texture, name, role)
    if Theme.IsBlizzard() then
        local file = name == "Chevron.tga" and Theme.NATIVE.arrow or name == "Circle.tga" and Theme.NATIVE.check
        if file then texture:SetTexture(file); texture:SetVertexColor(1, 1, 1, 1); return texture end
        if name == "Fade.tga" then texture:SetTexture(Theme.NATIVE.dark); texture:SetAlpha(0); return texture end
    end
    texture:SetTexture(Theme.Media(name))
    if role and texture.SetVertexColor then texture:SetVertexColor(Theme.Unpack(role)) end
    return texture
end

-- Resizes a font string while keeping its template's face.
function Theme.Font(fontString, size, flags)
    local face = fontString.GetFont and fontString:GetFont()
    face = face or STANDARD_TEXT_FONT
    if face and fontString.SetFont then fontString:SetFont(face, size, flags or "") end
    return fontString
end

-- Inline colour code for text that mixes roles in one string.
function Theme.Code(role)
    local c = Theme.Colour(role)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

function Theme.Set(key)
    if Theme.IsBlizzard() then return false, "this preview uses Blizzard presentation; reload the stable build to restore its appearance" end
    local theme = Theme.registry[key]
    if not theme then return false, "unknown theme" end
    if not theme.available then return false, theme.label .. " is not available yet" end
    HC.State().theme = key
    return true
end
