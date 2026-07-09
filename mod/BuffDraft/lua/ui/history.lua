-- BuffDraft MVP 7: BuffDraft panel (UI side). Draggable Window on the right (same
-- maui class the minimap uses) with two sections: the pending-choices indicator with
-- a Choose button that opens the choice window, and the list of buffs the local
-- player's side has picked. Pure display: all state lives sim-side and arrives via
-- Sync ("pending" and "history" events).

local UIUtil = import('/lua/ui/uiutil.lua')
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Window = import('/lua/maui/window.lua').Window
local Tooltip = import('/lua/ui/game/tooltip.lua')
local CommandMode = import('/lua/ui/game/commandmode.lua')
local BuffDraftConfig = import('/mods/BuffDraft/lua/config.lua')
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

-- active-buff section (between the Choose button and the history rows): one row
-- per owned active buff with a cooldown label and an Activate button. Display and
-- input only - state arrives via "active" sync events (once a second), the button
-- just sends BuffDraftUseActive; the sim validates ownership and cooldown.
local activeArea = nil -- fixed anchor Group; history rows hang below it
local activeRows = {} -- buffId -> { label, button }
local activeIdsKey = "" -- concat of currently shown buff ids, to detect set changes
local activeHeight = 0

-- Window drags keep whatever height we set last, so set it explicitly: full title
-- bar + content when expanded, title bar only when collapsed.
local function ApplyPanelHeight()
    local client = panel:GetClientGroup()
    local inner = pendingHeight + activeHeight + rowsHeight + LayoutHelpers.ScaleNumber(6)
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

    -- debug-only Admin button in its own row below the Choose button. Only the
    -- /BUTTON/medium/ and /BUTTON/large/ texture sets exist in FAF ('small'
    -- renders as an unclickable floating label). The sim validates the same
    -- DebugAdmin flag; this only saves typing the ui_lua console command.
    local activeAnchor = chooseButton
    local adminHeight = 0
    -- visible only for the configured admin owner; AccessAllowed also checks the
    -- DebugAdmin flag (and the sim validates the same rules on every callback)
    if import('/mods/BuffDraft/lua/ui/admin.lua').AccessAllowed() then
        local adminButton = UIUtil.CreateButtonWithDropshadow(client, '/BUTTON/medium/', 'Admin')
        LayoutHelpers.Below(adminButton, chooseButton, 2)
        LayoutHelpers.AtLeftIn(adminButton, client, 8)
        adminButton.OnClick = function(self, modifiers)
            import('/mods/BuffDraft/lua/ui/admin.lua').Open()
        end
        activeAnchor = adminButton
        adminHeight = LayoutHelpers.ScaleNumber(2) + adminButton.Height()
    end

    -- fixed anchor for the active-buff rows; zero height until a buff is owned.
    -- History rows anchor below it, so they move down when rows appear.
    activeArea = import('/lua/maui/group.lua').Group(client, "buffDraftActiveArea")
    LayoutHelpers.Below(activeArea, activeAnchor, 6)
    LayoutHelpers.AtLeftIn(activeArea, client, 8)
    activeArea.Right:Set(function() return client.Right() - LayoutHelpers.ScaleNumber(8) end)
    activeArea.Height:Set(0)

    pendingHeight = LayoutHelpers.ScaleNumber(6) + pendingLabel:Height()
        + LayoutHelpers.ScaleNumber(4) + chooseButton.Height() + adminHeight
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
    local rarity = (entry and entry.rarity) or "common"
    local body = "Rarity: " .. rarity .. ". " .. ((entry and entry.description) or "")
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
            LayoutHelpers.Below(titleText, activeArea, 8)
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

local function ActiveBuffTitle(buffId)
    local entry = CatalogEntry(buffId)
    return (entry and entry.title) or tostring(buffId)
end

-- Active buffs that want a target point: Activate starts a 'ping'-style command
-- mode (the multifunction ping-button pattern) and the next left click on the map
-- sends the world position to the sim. Other active buffs activate immediately.
local ActiveBuffNeedsTarget = { orbital_lance_1 = true }

-- Registered once for all command modes; our own modes are tagged with
-- buffDraftActiveBuff. Left click ends 'ping' mode with isCancel=false and the
-- click position is still under the mouse (exactly how DoPing reads it); Esc or
-- another command cancels - then nothing is sent and the cooldown stays unspent.
CommandMode.AddEndBehavior(function(mode, data)
    if mode ~= 'ping' or (not data) or (not data.buffDraftActiveBuff) then
        return
    end
    if data.isCancel then
        LOG("FAF_BUFF_DRAFT_UI: targeting cancelled for " .. tostring(data.buffDraftActiveBuff))
        return
    end
    local position = GetMouseWorldPos()
    for _, v in position do
        if v ~= v then -- NaN: the click hit no world position (same check as DoPing)
            LOG("FAF_BUFF_DRAFT_UI: targeting aborted for "
                .. tostring(data.buffDraftActiveBuff) .. ", no world position")
            return
        end
    end
    LOG("FAF_BUFF_DRAFT_UI: target point sent for " .. tostring(data.buffDraftActiveBuff))
    SimCallback({
        Func = 'BuffDraftUseActive',
        Args = {
            buffId = data.buffDraftActiveBuff,
            payload = { x = position[1], z = position[3] },
        },
    })
end, 'BuffDraftActiveTarget')

-- Recreate the active rows (set of owned active buffs changed - normally once,
-- when the buff is picked).
local function BuildActiveRows(states)
    for _, row in activeRows do
        row.label:Destroy()
        row.button:Destroy()
    end
    activeRows = {}

    local prev = nil
    local total = 0
    for _, state in states do
        local buffId = state.buffId
        local button = UIUtil.CreateButtonWithDropshadow(activeArea, '/BUTTON/medium/', 'Activate')
        LayoutHelpers.AtRightIn(button, activeArea, 0)
        if prev then
            LayoutHelpers.AnchorToBottom(button, prev, 4)
        else
            LayoutHelpers.AtTopIn(button, activeArea, 0)
        end
        button.OnClick = function(self, modifiers)
            if ActiveBuffNeedsTarget[buffId] then
                LOG("FAF_BUFF_DRAFT_UI: targeting mode started for " .. tostring(buffId))
                CommandMode.StartCommandMode('ping', {
                    cursor = 'RULEUCC_Attack', -- the attack-ping cursor (multifunction.lua)
                    buffDraftActiveBuff = buffId,
                })
            else
                LOG("FAF_BUFF_DRAFT_UI: activate pressed for " .. tostring(buffId))
                SimCallback({ Func = 'BuffDraftUseActive', Args = { buffId = buffId } })
            end
        end

        local label = UIUtil.CreateText(activeArea, "", 14, UIUtil.bodyFont)
        label:DisableHitTest()
        LayoutHelpers.AtLeftIn(label, activeArea, 0)
        LayoutHelpers.AtVerticalCenterIn(label, button)

        activeRows[buffId] = { label = label, button = button }
        total = total + button.Height() + LayoutHelpers.ScaleNumber(4)
        prev = button
    end

    activeArea.Height:Set(math.floor(total))
    activeHeight = total
end

local function UpdateActiveRow(row, state)
    if state.ready then
        row.label:SetText(ActiveBuffTitle(state.buffId) .. ": READY")
        row.button:Enable()
    else
        row.label:SetText(ActiveBuffTitle(state.buffId) .. ": "
            .. tostring(state.remaining) .. "s")
        row.button:Disable()
    end
end

--- Called from draftui.ProcessEvents with an "active" sync event (arrives about
--- once a second): { states = { {army, buffId, ready, remaining, cooldown}, ... } }.
--- Shows only the local player's own active buffs.
function UpdateActive(event)
    local myArmy = GetFocusArmy()
    local mine = {}
    for _, state in event.states or {} do
        if state.army == myArmy then
            table.insert(mine, state)
        end
    end
    if table.getn(mine) == 0 then
        -- all active buffs gone (admin remove): clear the section
        if activeIdsKey ~= "" and panel then
            BuildActiveRows({})
            activeIdsKey = ""
            ApplyPanelHeight()
            LOG("FAF_BUFF_DRAFT_UI: active buff rows cleared")
        end
        return
    end
    table.sort(mine, function(a, b) return a.buffId < b.buffId end)

    -- periodic updates must not fight a manual close, so no panel:Show() here
    -- unless the panel does not exist yet
    if not panel then
        CreatePanel()
        panel:Show()
    end

    local ids = {}
    for _, state in mine do
        table.insert(ids, tostring(state.buffId))
    end
    local key = table.concat(ids, "|")
    if key ~= activeIdsKey then
        BuildActiveRows(mine)
        activeIdsKey = key
        ApplyPanelHeight()
        LOG("FAF_BUFF_DRAFT_UI: active buff rows rebuilt: " .. key)
    end
    for _, state in mine do
        UpdateActiveRow(activeRows[state.buffId], state)
    end
end

--- Called from draftui.ProcessEvents with a "pending" sync event (already filtered
--- to the local player): { side, chooserArmy, count, first }.
function UpdatePending(event)
    EnsurePanel()
    panel:SetTitle("Buff Draft: " .. tostring(event.side))
    local count = event.count or 0
    pendingLabel:SetText("Pending choices: " .. tostring(count))
    if count > 0 then
        chooseButton:Enable()
    else
        chooseButton:Disable()
    end
    ApplyPanelHeight()
    LOG("FAF_BUFF_DRAFT_UI: pending count updated side=" .. tostring(event.side)
        .. " count=" .. tostring(count))
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
