-- BuffDraft: debug admin panel (UI side). Grants/removes buffs for a side through
-- the BuffDraftAdminGrantBuff/BuffDraftAdminRemoveBuff sim callbacks. Pure
-- display/input: every state change and validation happens sim-side; this panel
-- only shows static catalog data plus the picked lists it learns from "history"
-- sync events. Gated by DebugAdmin in config.lua - the sim checks the same flag
-- again, so the UI cannot bypass it.
--
-- Open: the Admin button in the Buff Draft panel (debug mode only), or console:
--   ui_lua import('/mods/BuffDraft/lua/ui/admin.lua').Open()
--
-- SupCom Lua gotcha (crashed MVP once): closures must NOT capture for-loop
-- variables directly - after the loop ends the captured value is nil. Copy into a
-- body-local first (FAF does the same: `local index = i` in multifunction.lua).

local UIUtil = import('/lua/ui/uiutil.lua')
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Window = import('/lua/maui/window.lua').Window
local BuffDraftConfig = import('/mods/BuffDraft/lua/config.lua')
local AdminAccess = import('/mods/BuffDraft/lua/admin_access.lua')
local BuffsModule = import('/mods/BuffDraft/lua/buffs.lua')
local BuffCatalog = BuffsModule.BuffCatalog
local BuffStatus = BuffsModule.BuffStatus

local PANEL_WIDTH = 380 -- unscaled pixels

local panel = nil
local rows = {} -- catalog order: { text, id, title, status }
local sideButtons = {} -- sideName -> Text control
local selectionLabel = nil
local grantButton = nil
local removeButton = nil

-- never nil: initialized here, only ever assigned side names, re-defaulted in Open
local selectedSide = "Artem"
local selectedBuffId = nil

-- sideName -> { [buffId] = true }; fed by the "history" sync events (the admin
-- panel tracks both sides, unlike the history panel which shows only the local one)
local PickedBySide = { Mark = {}, Artem = {} }

local function Refresh()
    if (not panel) or IsDestroyed(panel) then
        return
    end
    -- nil-proof every input: sync/event handlers may call this in any state
    if not PickedBySide[selectedSide] then
        selectedSide = "Artem"
    end
    local picked = PickedBySide[selectedSide] or {}

    for sideName, control in sideButtons do
        control:SetColor(sideName == selectedSide and 'FFFFD700' or 'FF98A8B8')
    end
    for _, row in rows do
        local prefix = picked[row.id] and "[P] " or ""
        row.text:SetText(prefix .. row.title .. "  [" .. row.status .. "]")
        if row.id == selectedBuffId then
            row.text:SetColor('FFFFD700') -- selected: gold
        elseif picked[row.id] then
            row.text:SetColor('FF80FF80') -- picked by selected side: green
        elseif row.rarity == 'mythic' then
            row.text:SetColor('FFFF4FD8') -- unique mythic tier color
        else
            row.text:SetColor('FFC0C8D0')
        end
    end
    selectionLabel:SetText("Side: " .. tostring(selectedSide)
        .. "  |  Selected: " .. tostring(selectedBuffId or "none"))

    -- Grant/Remove only make sense with a buff selected; the sim re-validates anyway
    if selectedBuffId then
        grantButton:Enable()
        removeButton:Enable()
    else
        grantButton:Disable()
        removeButton:Disable()
    end
end

local function SendAdmin(func)
    if (not selectedBuffId) or (not selectedSide) then
        LOG("FAF_BUFF_DRAFT_ADMIN: nothing selected, ignoring " .. tostring(func))
        return
    end
    LOG("FAF_BUFF_DRAFT_ADMIN: UI sending " .. func .. " " .. tostring(selectedBuffId)
        .. " side=" .. tostring(selectedSide))
    SimCallback({ Func = func, Args = { side = selectedSide, buffId = selectedBuffId } })
end

local function CreatePanel()
    local frame = GetFrame(0)
    local scaledWidth = LayoutHelpers.ScaleNumber(PANEL_WIDTH)
    local defaultPosition = {
        Left = function() return frame.Left() + LayoutHelpers.ScaleNumber(120) end,
        Top = function() return frame.Top() + LayoutHelpers.ScaleNumber(80) end,
        Right = function() return frame.Left() + LayoutHelpers.ScaleNumber(120) + scaledWidth end,
        Bottom = function() return frame.Top() + LayoutHelpers.ScaleNumber(400) end,
    }
    panel = Window(frame, "Buff Draft Admin (debug)", nil, false, false, true, false,
        'BuffDraftAdmin', defaultPosition)
    panel.Right:Set(math.floor(panel.Left() + scaledWidth))
    panel.OnClose = function(self)
        self:Hide()
    end

    local client = panel:GetClientGroup()

    -- side selector line
    local sideLabel = UIUtil.CreateText(client, "Side:", 14, UIUtil.bodyFont)
    sideLabel:DisableHitTest()
    LayoutHelpers.AtLeftTopIn(sideLabel, client, 8, 6)
    local prev = sideLabel
    for _, sideName in { "Mark", "Artem" } do
        -- body-local copy: the loop variable would be nil inside the closure later
        local side = sideName
        local control = UIUtil.CreateText(client, side, 14, UIUtil.bodyFont)
        LayoutHelpers.RightOf(control, prev, 12)
        control.HandleEvent = function(self, event)
            if event.Type == 'ButtonPress' then
                selectedSide = side
                Refresh()
                return true
            end
            return false
        end
        sideButtons[side] = control
        prev = control
    end

    -- one row per catalog buff; click selects
    local rowPrev = sideLabel
    local total = LayoutHelpers.ScaleNumber(6) + sideLabel:Height() + LayoutHelpers.ScaleNumber(6)
    for _, buff in BuffCatalog do
        local buffId = buff.id -- body-local copy for the closure (see header note)
        local text = UIUtil.CreateText(client, tostring(buff.title), 12, UIUtil.bodyFont)
        LayoutHelpers.Below(text, rowPrev, 3)
        LayoutHelpers.AtLeftIn(text, client, 8)
        text.HandleEvent = function(self, event)
            if event.Type == 'ButtonPress' then
                selectedBuffId = buffId
                Refresh()
                return true
            end
            return false
        end
        table.insert(rows, {
            text = text,
            id = buffId,
            title = tostring(buff.title) .. " (" .. buffId .. ")",
            status = ((BuffStatus and BuffStatus[buffId]) or "implemented")
                .. ", " .. (buff.rarity or "common"),
            rarity = buff.rarity or "common",
        })
        total = total + text:Height() + LayoutHelpers.ScaleNumber(3)
        rowPrev = text
    end

    selectionLabel = UIUtil.CreateText(client, "", 12, UIUtil.bodyFont)
    selectionLabel:DisableHitTest()
    LayoutHelpers.Below(selectionLabel, rowPrev, 8)
    LayoutHelpers.AtLeftIn(selectionLabel, client, 8)
    total = total + LayoutHelpers.ScaleNumber(8) + selectionLabel:Height()

    -- only /BUTTON/medium/ and /BUTTON/large/ texture sets exist in FAF;
    -- '/BUTTON/small/' renders as an unclickable floating label
    grantButton = UIUtil.CreateButtonWithDropshadow(client, '/BUTTON/medium/', 'Grant')
    LayoutHelpers.Below(grantButton, selectionLabel, 6)
    LayoutHelpers.AtLeftIn(grantButton, client, 2)
    grantButton.OnClick = function(self, modifiers)
        SendAdmin('BuffDraftAdminGrantBuff')
    end

    removeButton = UIUtil.CreateButtonWithDropshadow(client, '/BUTTON/medium/', 'Remove')
    LayoutHelpers.RightOf(removeButton, grantButton, 2)
    removeButton.OnClick = function(self, modifiers)
        SendAdmin('BuffDraftAdminRemoveBuff')
    end

    local closeButton = UIUtil.CreateButtonWithDropshadow(client, '/BUTTON/medium/', 'Close')
    LayoutHelpers.Below(closeButton, grantButton, 2)
    LayoutHelpers.AtLeftIn(closeButton, client, 2)
    closeButton.OnClick = function(self, modifiers)
        panel:Hide()
    end

    -- AI control: take the allied AI unit/structure clicked next (lua/ai_control/).
    -- Input only; the sim validates the owner and target entity on its own config.
    if BuffDraftConfig.EnableAIControl then
        local takeButton = UIUtil.CreateButtonWithDropshadow(client, '/BUTTON/medium/', 'Take AI')
        LayoutHelpers.RightOf(takeButton, closeButton, 2)
        takeButton.OnClick = function(self, modifiers)
            import('/mods/BuffDraft/lua/ai_control/control_ui.lua').StartTakeMode()
        end
    end

    total = total + LayoutHelpers.ScaleNumber(6) + grantButton.Height()
        + LayoutHelpers.ScaleNumber(2) + closeButton.Height() + LayoutHelpers.ScaleNumber(10)
    panel.Bottom:Set(math.floor(client.Top() + total))
end

--- Called from draftui.ProcessEvents for every "history" sync event (both sides).
--- Must be nil-safe in any panel state.
function OnHistoryEvent(event)
    if (not event) or (not event.side) or (not PickedBySide[event.side]) then
        return
    end
    local set = {}
    for _, pick in event.picks or {} do
        if pick and pick.id then
            set[pick.id] = true
        end
    end
    PickedBySide[event.side] = set
    Refresh()
end

--- Nickname of the local player (nil for observers). GetArmiesTable is the
--- standard UI-side army info source (score.lua uses the same fields).
function LocalNickname()
    local armiesInfo = GetArmiesTable()
    local focus = armiesInfo and armiesInfo.focusArmy
    local entry = focus and focus >= 1 and armiesInfo.armiesTable
        and armiesInfo.armiesTable[focus]
    return entry and entry.nickname or nil
end

--- True when the local player may use the admin panel. UI-side convenience only:
--- the sim independently validates the same config against the sender's brain.
function AccessAllowed()
    if not BuffDraftConfig.DebugAdmin then
        LOG("FAF_BUFF_DRAFT_ADMIN: access denied DebugAdmin=false in config.lua")
        return false
    end
    local nickname = LocalNickname()
    if not AdminAccess.IsNicknameAllowed(nickname) then
        LOG("FAF_BUFF_DRAFT_ADMIN: access denied " .. tostring(nickname)
            .. " (admin owners: " .. AdminAccess.ConfiguredOwnersText() .. ")")
        return false
    end
    LOG("FAF_BUFF_DRAFT_ADMIN: access allowed " .. tostring(nickname))
    return true
end

function Open()
    if not AccessAllowed() then
        return
    end
    -- default to the local player's detected side when we know it, else Artem
    local localSide = import('/mods/BuffDraft/lua/ui/draftui.lua').LocalSideName()
    if localSide and PickedBySide[localSide] then
        selectedSide = localSide
    elseif not PickedBySide[selectedSide] then
        selectedSide = "Artem"
    end
    if not panel then
        CreatePanel()
    end
    panel:Show()
    Refresh()
    LOG("FAF_BUFF_DRAFT_UI: admin opened side=" .. tostring(selectedSide))
end
