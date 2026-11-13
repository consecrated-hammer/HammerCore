package.path = "./tests/?.lua;" .. package.path
local wow = require("wow")
wow.Install({ DockTest = { Version = "1" } })
local HC = wow.LoadHammerCore("src", "DockTest").HammerCore
local savedDB = {}
HC:Init({ name = "DockTest", command = "docktest", db = function() return savedDB end, icon = "icon", previewDock = true })
local S = HC.Settings
local function eq(a, b, note) assert(a == b, note .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function bounds(left, top, width, height)
    return { left = left, top = top, right = left + width, bottom = top - height, width = width, height = height }
end
local h = bounds(500, 800, 600, 600)
eq(S.PreviewSnapSide(bounds(192, 790, 300, 200), h), "LEFT", "left edge")
eq(S.PreviewSnapSide(bounds(1108, 790, 300, 200), h), "RIGHT", "right edge")
eq(S.PreviewSnapSide(bounds(510, 908, 300, 100), h), "TOP", "top edge")
eq(S.PreviewSnapSide(bounds(510, 192, 300, 100), h), "BOTTOM", "bottom edge")
eq(S.PreviewSnapSide(bounds(150, 790, 300, 200), h), nil, "outside snap range")
eq(S.PreviewSnapSide(bounds(192, 100, 300, 50), h), nil, "no perpendicular overlap")
eq(S.PreviewDockPlan(bounds(0, 0, 300, 200), bounds(20, 800, 600, 600), 1600, 900, "LEFT", 0).side,
    "RIGHT", "flip to room at left screen edge")
eq(S.PreviewDockPlan(bounds(0, 0, 300, 200), h, 1600, 900, "RIGHT", 400).top, 892, "top clamped")
eq(S.PreviewDockPlan(bounds(0, 0, 300, 200), h, 0, 900, "RIGHT", 0), nil, "defer missing screen geometry")

UIParent:SetSize(1600, 900)
local function window(data, factor)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(data.width / factor, data.height / factor)
    f.GetLeft = function() return data.left / factor end
    f.GetTop = function() return data.top / factor end
    f.GetEffectiveScale = function() return factor end
    return f
end
local hostData, previewData = h, bounds(192, 790, 300, 200)
S.window = window(hostData, 1.3)
local preview = window(previewData, 0.7)
local saved = { "TOPLEFT", "TOPLEFT", 60, -80 }
local writes, active = 0, true
local dock = S:PreviewDock(preview, { getPoint = function() return saved end,
    setPoint = function(p) saved = p; writes = writes + 1 end, isActive = function() return active end })
dock:Restore()
eq(dock:IsAttached(), false, "opening does not autoattach")
dock:BeginDrag()
eq(writes, 0, "drag start does not overwrite the old free position")
eq(dock:EndDrag(), true, "near edge attaches")
eq(writes, 0, "attachment preserves free saved position")
eq(select(2, preview:GetPoint()), S.window, "attached frame anchors to host")
eq(HC.State().previewDockSide, "LEFT", "side persists")
hostData.left, hostData.right = 20, 620
dock:Refresh()
eq(select(4, preview:GetPoint()) > 0, true, "screen edge flips preview to right")
hostData.left, hostData.right = 500, 1100
dock:BeginDrag()
previewData.left, previewData.top = 70, 700
eq(dock:EndDrag(), false, "drag away detaches")
eq(select(2, preview:GetPoint()), UIParent, "detached frame is independent")
eq(writes, 1, "detached position is saved once")
HC.State().previewDockSide = "LEFT"
dock:Restore()
eq(dock:IsAttached(), true, "reopen restores attachment")
HC.State().previewSnap = false
dock:Refresh()
eq(dock:IsAttached(), false, "switch disables attachment")
eq(HC.State().previewDockSide, nil, "disabled snap does not silently reattach")
active = false
local old = #preview.points
dock:Restore(); dock:Refresh()
eq(#preview.points, old, "inactive on-screen preview is not repositioned")
active = true
dock:BeginDrag(); preview:Hide()
eq(dock.dragging, false, "hide cancels drag")
preview:Show()
HC.State().previewSnap, HC.State().previewDockSide = true, "LEFT"
dock:Restore()
local freeBefore, writesBefore = saved, writes
preview:Hide()
HC.State().previewSnap = false
S:RefreshPreviewDocks()
eq(HC.State().previewDockSide, nil, "disabling while hidden clears saved attachment")
eq(saved, freeBefore, "disable does not replace independent saved position")
eq(writes, writesBefore, "disable does not persist docked coordinates")
preview:Show()
HC.State().previewSnap = true
dock:Restore()
eq(dock:IsAttached(), false, "re-enable after hidden disable does not autoattach")
HC.State().previewDockSide = "LEFT"; dock:Restore()
S.window:Hide(); dock:Refresh()
eq(select(2, preview:GetPoint()), UIParent, "hidden host leaves no stale anchor")
eq(dock:BeginDrag(), true, "independent preview can still be dragged without settings")
eq(dock:EndDrag(), false, "hostless drop remains independent")
eq(HC.State().previewDockSide, "LEFT", "hostless mode preserves side")
S.window:Show(); dock:Restore()
active = false; dock:Refresh()
eq(select(2, preview:GetPoint()), UIParent, "inactive mode detaches stale settings anchor")
active = true; dock:Restore()
local planning = 0
local plan = S.PreviewDockPlan
S.PreviewDockPlan = function(...) planning = planning + 1; return plan(...) end
dock:Refresh(); dock:Refresh()
eq(planning, 0, "idle geometry is cached before planning allocations")
S.PreviewDockPlan = function() return nil end
dock:BeginDrag()
previewData.left, previewData.top = 192, 790
eq(dock:EndDrag(), false, "unready plan is not reported as an attachment")
eq(HC.State().previewDockSide, nil, "failed snap clears uncommitted side")
S.PreviewDockPlan = plan
io.write("preview docking tests passed\n")
