-- BuffDraft: UI-only panel for the mythic Commander Apotheosis packages.
-- It displays SIM state and sends a package id; all validation and gameplay live
-- in effects.lua. The four packages can coexist and ignore stock slot conflicts.

local UIUtil = import('/lua/ui/uiutil.lua')
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Window = import('/lua/maui/window.lua').Window
local Group = import('/lua/maui/group.lua').Group
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
local WrapText = import('/lua/maui/text.lua').WrapText

local PANEL_WIDTH = 740
local ROW_WIDTH = 700
local DESCRIPTION_WIDTH = 500

local panel = nil
local packageArea = nil
local stateLabel = nil
local latestState = nil
local rowControls = {}

local function DestroyRows()
    for _, control in rowControls do
        if control and not IsDestroyed(control) then
            control:Destroy()
        end
    end
    rowControls = {}
end

local function Keep(control)
    table.insert(rowControls, control)
    return control
end

local function PackageStatus(package, state)
    if package.installed then
        return 'INSTALLED', 'FF80FF80'
    elseif package.building then
        return 'INSTALLING', 'FFFFD700'
    elseif not state.owned then
        return 'MYTHIC BUFF NOT OWNED', 'FFFF7070'
    elseif not state.commanderAlive then
        return 'NO LIVING COMMANDER', 'FFFF7070'
    elseif state.busy then
        return 'WAIT FOR CURRENT PACKAGE', 'FF98A8B8'
    end
    return 'AVAILABLE', 'FFFF4FD8'
end

local function Rebuild()
    if not panel or IsDestroyed(panel) then
        return
    end
    DestroyRows()

    local state = latestState
    if not state then
        stateLabel:SetText('Requesting current SIM state...')
        panel.Bottom:Set(math.floor(panel:GetClientGroup().Top()
            + LayoutHelpers.ScaleNumber(100)))
        return
    end

    if state.owned then
        stateLabel:SetText('Four independent packages - original summed costs and time')
        stateLabel:SetColor('FFFFD700')
    else
        stateLabel:SetText('Commander Apotheosis is not owned by this army')
        stateLabel:SetColor('FFFF7070')
    end

    local previous = nil
    local total = 0
    for _, sourcePackage in state.packages or {} do
        -- Body-local copy: SupCom Lua closures must not capture the loop value.
        local package = sourcePackage
        local packageId = package.id
        local row = Keep(Bitmap(packageArea))
        row:SetSolidColor('B0200828')
        LayoutHelpers.SetWidth(row, ROW_WIDTH)
        LayoutHelpers.AtLeftIn(row, packageArea, 0)
        if previous then
            LayoutHelpers.Below(row, previous, 8)
        else
            LayoutHelpers.AtTopIn(row, packageArea, 0)
        end

        local accent = Keep(Bitmap(row))
        accent:SetSolidColor('FFFFD700')
        accent.Width:Set(LayoutHelpers.ScaleNumber(4))
        accent.Height:Set(function() return row.Height() end)
        LayoutHelpers.AtLeftTopIn(accent, row, 0, 0)
        accent:DisableHitTest()

        local title = Keep(UIUtil.CreateText(row, tostring(package.title), 17,
            'Arial Bold', true))
        title:SetColor('FFFF4FD8')
        title:DisableHitTest()
        LayoutHelpers.AtLeftTopIn(title, row, 12, 8)

        local install = Keep(UIUtil.CreateButtonWithDropshadow(
            row, '/BUTTON/medium/', package.installed and 'Installed'
                or (package.building and 'Installing' or 'Install')))
        LayoutHelpers.AtRightIn(install, row, 10)
        LayoutHelpers.AtTopIn(install, row, 10)
        install.OnClick = function(self, modifiers)
            self:Disable()
            LOG('FAF_BUFF_DRAFT_UI: commander package requested ' .. tostring(packageId))
            SimCallback({
                Func = 'BuffDraftCommanderUpgrade',
                Args = { packageId = packageId },
            })
        end

        local statusText, statusColor = PackageStatus(package, state)
        local status = Keep(UIUtil.CreateText(row, statusText, 12, 'Arial Bold'))
        status:SetColor(statusColor)
        status:DisableHitTest()
        LayoutHelpers.Below(status, title, 2)
        LayoutHelpers.AtLeftIn(status, row, 12)

        if package.installed or package.building or state.busy
                or (not state.owned) or (not state.commanderAlive) then
            install:Disable()
        end

        local cost = Keep(UIUtil.CreateText(row,
            'Mass ' .. tostring(math.floor(package.mass or 0))
                .. '  |  Energy ' .. tostring(math.floor(package.energy or 0))
                .. '  |  Current build time ~' .. tostring(package.seconds or 0) .. 's',
            12, UIUtil.bodyFont))
        cost:SetColor('FFFFD700')
        cost:DisableHitTest()
        LayoutHelpers.Below(cost, status, 3)
        LayoutHelpers.AtLeftIn(cost, row, 12)

        local lines = WrapText(tostring(package.description or ''),
            LayoutHelpers.ScaleNumber(DESCRIPTION_WIDTH), function(text)
                return cost:GetStringAdvance(text)
            end)
        local last = cost
        for _, lineText in lines do
            local line = Keep(UIUtil.CreateText(row, lineText, 12, UIUtil.bodyFont))
            line:SetColor('FFD0D8E0')
            line:DisableHitTest()
            LayoutHelpers.Below(line, last, 2)
            LayoutHelpers.AtLeftIn(line, row, 12)
            last = line
        end

        local rowHeight = LayoutHelpers.ScaleNumber(12) + title:Height()
            + status:Height() + cost:Height() + LayoutHelpers.ScaleNumber(13)
        for _ in lines do
            rowHeight = rowHeight + cost:Height() + LayoutHelpers.ScaleNumber(2)
        end
        rowHeight = math.max(rowHeight, install.Height() + LayoutHelpers.ScaleNumber(20))
        row.Height:Set(math.floor(rowHeight))
        total = total + rowHeight + LayoutHelpers.ScaleNumber(8)
        previous = row
    end

    packageArea.Height:Set(math.floor(total))
    panel.Bottom:Set(math.floor(panel:GetClientGroup().Top()
        + LayoutHelpers.ScaleNumber(64) + total))
end

local function CreatePanel()
    local frame = GetFrame(0)
    local width = LayoutHelpers.ScaleNumber(PANEL_WIDTH)
    local defaultPosition = {
        Left = function() return frame.Left() + LayoutHelpers.ScaleNumber(80) end,
        Top = function() return frame.Top() + LayoutHelpers.ScaleNumber(80) end,
        Right = function() return frame.Left() + LayoutHelpers.ScaleNumber(80) + width end,
        Bottom = function() return frame.Top() + LayoutHelpers.ScaleNumber(640) end,
    }
    panel = Window(frame, '[MYTHIC] Commander Apotheosis', nil, false, false,
        true, false, 'BuffDraftCommanderUpgrades', defaultPosition)
    panel.Right:Set(math.floor(panel.Left() + width))
    panel.OnClose = function(self)
        self:Hide()
    end

    local client = panel:GetClientGroup()
    local header = UIUtil.CreateText(client,
        'ALL FACTIONS. ALL PATHS. CONFLICTS ALLOWED.', 19, 'Arial Bold', true)
    header:SetColor('FFFF4FD8')
    header:DisableHitTest()
    LayoutHelpers.AtLeftTopIn(header, client, 12, 8)

    stateLabel = UIUtil.CreateText(client, '', 12, UIUtil.bodyFont)
    stateLabel:DisableHitTest()
    LayoutHelpers.Below(stateLabel, header, 3)
    LayoutHelpers.AtLeftIn(stateLabel, client, 12)

    packageArea = Group(client, 'buffDraftCommanderPackageArea')
    LayoutHelpers.Below(packageArea, stateLabel, 8)
    LayoutHelpers.AtLeftIn(packageArea, client, 12)
    packageArea.Width:Set(LayoutHelpers.ScaleNumber(ROW_WIDTH))
    packageArea.Height:Set(0)
end

function ProcessEvent(event)
    if (not event) or GetFocusArmy() ~= event.army then
        return
    end
    latestState = event
    Rebuild()
end

function Open()
    if not panel or IsDestroyed(panel) then
        CreatePanel()
    end
    panel:Show()
    Rebuild()
    SimCallback({ Func = 'BuffDraftCommanderUpgradeSync', Args = {} })
    LOG('FAF_BUFF_DRAFT_UI: commander upgrade panel opened')
end
