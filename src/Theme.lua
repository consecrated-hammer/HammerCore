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
        colours = {
            outer = { 0.043, 0.051, 0.063, 0.98 },
            rail = { 0.071, 0.082, 0.102, 1 },
            content = { 0.086, 0.098, 0.118, 1 },
            raised = { 0.110, 0.125, 0.153, 1 },
            edge = { 0.169, 0.192, 0.227, 1 },
            menu = { 0.020, 0.027, 0.039, 1 },
            menuEdge = { 0.337, 0.416, 0.522, 1 },
            menuActive = { 0.075, 0.125, 0.190, 1 },
            accent = { 0.298, 0.604, 0.478, 1 },
            selected = { 0.247, 0.604, 0.925, 1 },
            muted = { 0.553, 0.584, 0.639, 1 },
            section = { 0.82, 0.85, 0.90, 1 },
            text = { 1, 1, 1, 1 },
            danger = { 0.788, 0.337, 0.306, 1 },
            transparent = { 0, 0, 0, 0 },
        },
    },
    classic = {
        label = "Classic",
        -- Designed for, not yet built.  Selecting it is refused until it is.
        available = false,
    },
}

Theme.order = { "modern", "classic" }

-- The theme is fixed when the settings window is built.  Changing it takes
-- effect after a reload, which keeps every control free of re-skin logic.
function Theme.Active()
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

-- A flat panel: background role plus an optional 1px border role.
function Theme.Surface(frame, background, border)
    if not frame.SetBackdrop then return frame end
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = border and WHITE or nil, edgeSize = border and 1 or nil })
    frame:SetBackdropColor(Theme.Unpack(background))
    if border then frame:SetBackdropBorderColor(Theme.Unpack(border)) end
    return frame
end

function Theme.Border(frame, border)
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(Theme.Unpack(border)) end
end

function Theme.Fill(texture, role)
    texture:SetColorTexture(Theme.Unpack(role))
    return texture
end

function Theme.Text(fontString, role)
    fontString:SetTextColor(Theme.Unpack(role or "text"))
    return fontString
end

-- Inline colour code for text that mixes roles in one string.
function Theme.Code(role)
    local c = Theme.Colour(role)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

function Theme.Set(key)
    local theme = Theme.registry[key]
    if not theme then return false, "unknown theme" end
    if not theme.available then return false, theme.label .. " is not available yet" end
    HC.State().theme = key
    return true
end
