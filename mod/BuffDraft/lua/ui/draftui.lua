-- BuffDraft MVP 7: choice window (UI side). No more auto-popup: the sim publishes
-- the pending-choice queue state, the panel (history.lua) shows an indicator and a
-- Choose button, and this module opens the choice window for the first pending
-- choice on demand. The UI only displays sim data and sends the pick (with the
-- choice's tick) back via SimCallback; all validation lives sim-side.

local UIUtil = import('/lua/ui/uiutil.lua')
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Group = import('/lua/maui/group.lua').Group
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
local WrapText = import('/lua/maui/text.lua').WrapText
local Popup = import('/lua/ui/controls/popups/popup.lua').Popup

local DIALOG_WIDTH = 600 -- unscaled pixels
local BLOCK_WIDTH = 560

-- latest pending-state event for the local player: { side, chooserArmy, count, first }
local PendingState = nil

local ActivePopup = nil

local function ClosePopup()
    -- UI controls have no :IsDestroyed() method; FAF uses the global IsDestroyed()
    if ActivePopup and not IsDestroyed(ActivePopup) then
        ActivePopup:Close()
    end
    ActivePopup = nil
end

local function SendPick(side, buffId, tick)
    LOG("FAF_BUFF_DRAFT: UI sending pick " .. tostring(buffId) .. " for side "
        .. tostring(side) .. " tick " .. tostring(tick))
    SimCallback({ Func = 'BuffDraftPick', Args = { side = side, buffId = buffId, tick = tick } })
    ClosePopup()
end

-- One option block: solid background, title line, wrapped description (MultiLineText
-- has no word wrap, so wrap manually via maui text.lua WrapText like QuickDialog does)
-- and a large button on the right. Returns the block and its computed pixel height.
local function CreateOptionBlock(dialog, option, onPick)
    local block = Bitmap(dialog)
    block:SetSolidColor('78101820')
    LayoutHelpers.SetWidth(block, BLOCK_WIDTH)

    local button = UIUtil.CreateButtonWithDropshadow(block, '/BUTTON/large/', 'Choose')
    LayoutHelpers.AtRightIn(button, block, 10)
    LayoutHelpers.AtVerticalCenterIn(button, block)
    button.OnClick = function(self, modifiers)
        onPick()
    end

    local textWidth = block.Width() - button.Width() - LayoutHelpers.ScaleNumber(44)

    local title = UIUtil.CreateText(block, tostring(option.title), 18, UIUtil.titleFont)
    LayoutHelpers.AtLeftTopIn(title, block, 12, 8)

    local descTexts = {}
    descTexts[1] = UIUtil.CreateText(block, "", 14, UIUtil.bodyFont)
    LayoutHelpers.Below(descTexts[1], title, 4)
    LayoutHelpers.AtLeftIn(descTexts[1], block, 12)
    local lines = WrapText(tostring(option.description), textWidth, function(text)
        return descTexts[1]:GetStringAdvance(text)
    end)
    descTexts[1]:SetText(lines[1] or "")
    for i = 2, table.getn(lines) do
        local line = UIUtil.CreateText(block, lines[i], 14, UIUtil.bodyFont)
        LayoutHelpers.Below(line, descTexts[i - 1], 2)
        LayoutHelpers.AtLeftIn(line, block, 12)
        descTexts[i] = line
    end

    local textHeight = LayoutHelpers.ScaleNumber(8) + title:Height() + LayoutHelpers.ScaleNumber(4)
    for _, line in descTexts do
        textHeight = textHeight + line:Height() + LayoutHelpers.ScaleNumber(2)
    end
    textHeight = textHeight + LayoutHelpers.ScaleNumber(8)

    local blockHeight = math.max(textHeight, button.Height() + LayoutHelpers.ScaleNumber(16))
    block.Height:Set(math.floor(blockHeight))
    return block, blockHeight
end

local function ShowChoiceWindow(side, choice)
    ClosePopup()

    local parent = GetFrame(0)
    local dialog = Group(parent, "buffDraftDialog")
    LayoutHelpers.SetWidth(dialog, DIALOG_WIDTH)

    local header = UIUtil.CreateText(dialog,
        "BUFF DRAFT - " .. tostring(side) .. ": choose a buff (tick "
            .. tostring(choice.tick) .. ")",
        20, UIUtil.titleFont)
    LayoutHelpers.AtTopIn(header, dialog, 12)
    LayoutHelpers.AtHorizontalCenterIn(header, dialog)

    local totalHeight = LayoutHelpers.ScaleNumber(12) + header:Height()
    local prev = header
    local pickSent = false -- ignore repeated clicks on this dialog
    for _, option in choice.options do
        local optionId = option.id
        local block, blockHeight = CreateOptionBlock(dialog, option, function()
            if pickSent then
                return
            end
            pickSent = true
            SendPick(side, optionId, choice.tick)
        end)
        LayoutHelpers.AnchorToBottom(block, prev, 10)
        LayoutHelpers.AtHorizontalCenterIn(block, dialog)
        totalHeight = totalHeight + LayoutHelpers.ScaleNumber(10) + blockHeight
        prev = block
    end
    dialog.Height:Set(math.floor(totalHeight + LayoutHelpers.ScaleNumber(15)))

    local popup = Popup(parent, dialog)
    -- no auto-pick anymore, so the player may close the window and decide later
    popup.OnShadowClicked = function() ClosePopup() end
    popup.OnEscapePressed = function() ClosePopup() end

    ActivePopup = popup
    LOG("FAF_BUFF_DRAFT: UI choice window shown for side " .. tostring(side)
        .. " tick " .. tostring(choice.tick))
end

--- Called from the panel's Choose button: opens the first pending choice, if any.
function OpenPendingChoice()
    if (not PendingState) or PendingState.count == 0 or (not PendingState.first) then
        LOG("FAF_BUFF_DRAFT: UI no pending choices to open")
        return
    end
    ShowChoiceWindow(PendingState.side, PendingState.first)
end

--- Called from the UserSync hook with the list of draft events of this sim beat.
function ProcessEvents(events)
    for _, event in events do
        if event.event == "pending" then
            if GetFocusArmy() == event.chooserArmy then
                PendingState = event
                import('/mods/BuffDraft/lua/ui/history.lua').UpdatePending(event)
            end
        elseif event.event == "history" then
            import('/mods/BuffDraft/lua/ui/history.lua').Update(event)
        end
    end
end
