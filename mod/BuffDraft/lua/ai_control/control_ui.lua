-- BuffDraft AI control (UI side): input only. StartTakeMode enters the 'ping'
-- command mode (the same multifunction ping-button pattern as orbital lance
-- targeting in ui/history.lua); the next left click sends the entity id under
-- the cursor to the BuffDraftTakeAIUnits sim callback. Esc / another command cancels.
-- No gameplay logic here - the sim validates the sender and target entity on
-- its own copy of the config, so this file cannot be used to cheat.
--
-- Manual open (besides the admin panel button):
--   ui_lua import('/mods/BuffDraft/lua/ai_control/control_ui.lua').StartTakeMode()

local CommandMode = import('/lua/ui/game/commandmode.lua')
local BuffDraftConfig = import('/mods/BuffDraft/lua/config.lua')
local TakeModeGeneration = 0
local LastRolloverTarget = nil

-- The engine can clear GetRolloverInfo during the same click that ends ping
-- mode. Keep the last valid target seen while the mode is active, with a
-- userUnit fallback for clients that omit entityId from the rollover table.
local function ReadRolloverTarget()
    local info = GetRolloverInfo()
    if not info then
        return nil
    end
    local userUnit = info.userUnit
    local entityId = info.entityId
    if (not entityId) and userUnit and not IsDestroyed(userUnit) then
        entityId = userUnit:GetEntityId()
    end
    if not entityId then
        return nil
    end
    local blueprintId = info.blueprintId
    if (not blueprintId or blueprintId == 'unknown')
            and userUnit and not IsDestroyed(userUnit) then
        local bp = userUnit:GetBlueprint()
        blueprintId = bp and bp.BlueprintId
    end
    if blueprintId == 'unknown' then
        blueprintId = nil -- do not turn an unidentified UI value into a false stale-id rejection
    end
    return {
        entityId = entityId,
        blueprintId = blueprintId,
    }
end

local function TrackRolloverTarget(generation)
    while TakeModeGeneration == generation do
        local mode = CommandMode.GetCommandMode()
        local data = mode and mode[2]
        if (not mode) or mode[1] ~= 'ping' or (not data) or (not data.buffDraftTakeAI) then
            return
        end
        local target = ReadRolloverTarget()
        if target then
            LastRolloverTarget = target
        end
        WaitFrames(1)
    end
end

-- Registered once (module import is cached). Our mode is tagged buffDraftTakeAI.
-- Left click ends 'ping' with isCancel=false. Prefer the rollover still under
-- the cursor, then use the tracked one-frame fallback if the engine cleared it.
CommandMode.AddEndBehavior(function(mode, data)
    if mode ~= 'ping' or (not data) or (not data.buffDraftTakeAI) then
        return
    end
    TakeModeGeneration = TakeModeGeneration + 1 -- stop the rollover tracker
    if data.isCancel then
        LastRolloverTarget = nil
        LOG("FAF_BUFF_DRAFT_AI_CONTROL_UI: take cancelled")
        return
    end

    local target = ReadRolloverTarget()
    local usedCachedRollover = false
    if not target then
        target = LastRolloverTarget
        usedCachedRollover = target and true or false
    end
    LastRolloverTarget = nil
    if not target then
        LOG("FAF_BUFF_DRAFT_AI_CONTROL_UI: take aborted, no rollover entity")
        print("Take AI: no unit under the cursor")
        return
    end

    local mouse = GetMouseWorldPos()
    local clickPosition = mouse and { mouse[1], mouse[2], mouse[3] } or nil

    LOG("FAF_BUFF_DRAFT_AI_CONTROL_UI: take target sent id=" .. tostring(target.entityId)
        .. " bp=" .. tostring(target.blueprintId)
        .. " cached=" .. tostring(usedCachedRollover))
    print("Take AI: transfer requested")
    SimCallback({
        Func = 'BuffDraftTakeAIUnits',
        Args = {
            entityId = target.entityId,
            blueprintId = target.blueprintId, -- stale-id guard; sim re-reads the real blueprint
            cachedRollover = usedCachedRollover,
            clickPosition = clickPosition,
        },
    })
end, 'BuffDraftTakeAI')

--- Enter the take-units targeting mode; the next left click takes allied AI
--- unit/structure under the cursor (validated sim-side).
function StartTakeMode()
    if not BuffDraftConfig.EnableAIControl then
        LOG("FAF_BUFF_DRAFT_AI_CONTROL_UI: disabled by config")
        return
    end
    TakeModeGeneration = TakeModeGeneration + 1
    local generation = TakeModeGeneration
    LastRolloverTarget = nil
    LOG("FAF_BUFF_DRAFT_AI_CONTROL_UI: take mode started")
    print("Take AI: click an allied AI unit")
    CommandMode.StartCommandMode('ping', {
        cursor = 'RULEUCC_Guard',
        buffDraftTakeAI = true,
    })
    ForkThread(TrackRolloverTarget, generation)
end

local ResultMessages = {
    disabled = 'tool disabled in config',
    not_human = 'sender is not a human player',
    not_owner = 'admin nickname mismatch',
    bad_payload = 'bad request payload',
    missing_entity = 'no unit under the cursor',
    bad_entity = 'invalid unit id',
    entity_not_found = 'unit no longer exists',
    not_unit = 'target is not a unit',
    entity_mismatch = 'stale unit id',
    bad_click_position = 'invalid click position',
    stale_rollover = 'cursor moved off the unit',
    dead = 'unit is dead',
    own_unit = 'unit already belongs to you',
    civilian = 'civilian units cannot be taken',
    human_ally = 'target belongs to a human ally',
    not_allied = 'target is not allied',
    not_transferable = 'unit type cannot be transferred',
    acu = 'ACU transfer is disabled',
    experimental = 'experimental transfer is disabled',
    under_construction = 'unit is under construction',
    attached = 'attached units cannot be transferred',
    transfer_filtered = 'FAF transfer rules rejected the unit',
}

--- Receives the SIM result through draftui.ProcessEvents so a rejected click is
--- visible to the player instead of failing silently.
function ProcessResult(event)
    if (not event) or GetFocusArmy() ~= event.army then
        return
    end
    if event.success then
        print('Take AI: unit transferred (' .. tostring(event.unit or 'unknown') .. ')')
        return
    end
    local message = ResultMessages[event.reason] or tostring(event.reason or 'unknown error')
    if event.reason == 'not_owner' and event.unit then
        message = message .. ': current nickname is ' .. tostring(event.unit)
    end
    print('Take AI failed: ' .. message)
end
