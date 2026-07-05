-- BuffDraft MVP 7: BuffDraft panel (UI side). Draggable Window on the right (same
-- maui class the minimap uses) with two sections: the pending-choices indicator with
-- a Choose button that opens the choice window, and the list of buffs the local
-- player's side has picked. Pure display: all state lives sim-side and arrives via
-- Sync ("pending" and "history" events).

local UIUtil = import('/lua/ui/uiutil.lua')
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Window = import('/lua/maui/window.lua').Window
local Tooltip = import('/lua/ui/game/tooltip.lua')
-- data-only catalog, shared with the sim: used here only for tooltip text
local BuffCatalog = import('/mods/BuffDraft/lua/buffs.lua').BuffCatalog

local PANEL_WIDTH = 280 -- unscaled pixels
local TOOLTIP_WIDTH = 300

local panel = nil
local pendingLabel = nil
local chooseButton = nil
local rows = {} -- text controls of the current history rows
local collapsed = false
local pendingHeight = 0
local rowsHeight = 0

-- Window drags keep whatever height we set last, so set it explicitly: full title
-- bar + content when expanded, title bar only when collapsed.
local function ApplyPanelHeight()
    local client = panel:GetClientGroup()
    local inner = pendingHeight + rowsHeight + LayoutHelpers.ScaleNumber(6)
    if collapsed then
        client:Hide()
        inner = 0
    else
        client:Show()
    end
    panel.Bottom:Set(math.floor(client.Top() + inner + LayoutHelpers.ScaleNumber(8)))
end

local function CreatePanel()
    local frame = GetFrame(0)
    local scaledWidth = LayoutHelpers.ScaleNumber(PANEL_WIDTH)
    local defaultPosition = {
        -- lazy functions: keep the default spot anchored to the right screen edge
        Left = function() return frame.Right() - scaledWidth - LayoutHelpers.ScaleNumber(20) end,
        Top = function() return frame.Top() + LayoutHelpers.ScaleNumber(180) end,
        Right = function() return frame.Right() - LayoutHelpers.ScaleNumber(20) end,
        Bottom = function() return frame.Top() + LayoutHelpers.ScaleNumber(280) end,
    }
    -- pin button doubles as collapse toggle; size locked, position draggable and
    -- remembered in the profile under the pref id
    panel = Window(frame, "Buff Draft", nil, true, false, true, false, 'BuffDraftHistory', defaultPosition)

    -- enforce our fixed width regardless of what was restored from the prefs
    panel.Right:Set(math.floor(panel.Left() + scaledWidth))

    panel.OnPinCheck = function(self, checked)
        collapsed = checked
        ApplyPanelHeight()
        LOG("FAF_BUFF_DRAFT: UI panel " .. (collapsed and "collapsed" or "expanded"))
    end
    panel.OnClose = function(self)
        self:Hide() -- reappears on the next pending/history update
    end

    -- pending-choices section at the top of the client area
    local client = panel:GetClientGroup()
    pendingLabel = UIUtil.CreateText(client, "Pending choices: 0", 14, UIUtil.bodyFont)
    pendingLabel:DisableHitTest()
    LayoutHelpers.AtLeftTopIn(pendingLabel, client, 8, 6)

    chooseButton = UIUtil.CreateButtonWithDropshadow(client, '/BUTTON/medium/', 'Open pending choice')
    LayoutHelpers.Below(chooseButton, pendingLabel, 4)
    LayoutHelpers.AtLeftIn(chooseButton, client, 8)
    chooseButton.OnClick = function(self, modifiers)
        import('/mods/BuffDraft/lua/ui/draftui.lua').OpenPendingChoice()
    end
    chooseButton:Disable()

    pendingHeight = LayoutHelpers.ScaleNumber(6) + pendingLabel:Height()
        + LayoutHelpers.ScaleNumber(4) + chooseButton.Height()
end

local function EnsurePanel()
    if not panel then
        CreatePanel()
    end
    panel:Show()
end

local function CatalogEntry(id)
    for _, buff in BuffCatalog do
        if buff.id == id then
            return buff
        end
    end
    return nil
end

-- Full-detail tooltip for an already picked buff. Display only: the catalog text is
-- static data; no gameplay logic runs here.
local function AddBuffTooltip(control, pick)
    local entry = CatalogEntry(pick.id)
    local title = (entry and entry.title) or tostring(pick.title)
    local body = ((entry and entry.description) or "")
    if entry and entry.effect then
        body = body .. " Effect: " .. entry.effect
    end
    control.HandleEvent = function(self, event)
        if event.Type == 'MouseEnter' then
            -- forced=true: show even if the game-options tooltip toggle is off
            Tooltip.CreateMouseoverDisplay(self, { text = title, body = body },
                0, true, TOOLTIP_WIDTH, true)
            LOG("FAF_BUFF_DRAFT_UI: tooltip shown for " .. tostring(pick.id))
        elseif event.Type == 'MouseExit' then
            Tooltip.DestroyMouseoverDisplay()
        end
        return true -- consume so hovering a row does not start a window drag
    end
end

local function RebuildRows(sideName, picks)
    local client = panel:GetClientGroup()
    for _, control in rows do
        control:Destroy()
    end
    rows = {}

    local prev = nil
    local total = 0
    local index = 1
    for _, pick in picks do
        local titleText = UIUtil.CreateText(client,
            tostring(index) .. ". " .. tostring(pick.title), 14, UIUtil.bodyFont)
        -- hit test stays enabled: the row shows the full-detail tooltip on hover
        AddBuffTooltip(titleText, pick)
        if prev then
            LayoutHelpers.Below(titleText, prev, 6)
        else
            LayoutHelpers.Below(titleText, chooseButton, 8)
        end
        LayoutHelpers.AtLeftIn(titleText, client, 8)

        local subText = UIUtil.CreateText(client,
            tostring(pick.id) .. "  |  " .. tostring(sideName), 10, UIUtil.bodyFont)
        subText:SetColor('ff96a6b0')
        subText:DisableHitTest()
        LayoutHelpers.Below(subText, titleText, 1)
        LayoutHelpers.AtLeftIn(subText, client, 8)

        total = total + titleText:Height() + subText:Height() + LayoutHelpers.ScaleNumber(7)
        table.insert(rows, titleText)
        table.insert(rows, subText)
        prev = subText
        index = index + 1
    end

    rowsHeight = total
end

--- Called from draftui.ProcessEvents with a "pending" sync event (already filtered
--- to the local player): { side, chooserArmy, count, first }.
function UpdatePending(event)
    EnsurePanel()
    panel:SetTitle("Buff Draft: " .. tostring(event.side))
    pendingLabel:SetText("Pending choices: " .. tostring(event.count))
    if event.count > 0 then
        chooseButton:Enable()
    else
        chooseButton:Disable()
    end
    ApplyPanelHeight()
    LOG("FAF_BUFF_DRAFT: UI pending indicator side=" .. tostring(event.side)
        .. " count=" .. tostring(event.count))
end

--- Called from draftui.ProcessEvents with a "history" sync event:
--- { side, chooserArmy, picks = {{id, title}, ...} }.
function Update(event)
    -- the panel only shows the local player's own history
    if GetFocusArmy() ~= event.chooserArmy then
        return
    end
    EnsurePanel()
    panel:SetTitle("Buff Draft: " .. tostring(event.side))
    RebuildRows(event.side, event.picks)
    ApplyPanelHeight()
    LOG("FAF_BUFF_DRAFT: UI history panel updated, "
        .. tostring(table.getn(event.picks)) .. " picks")
end
