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

-- Registered once (module import is cached). Our mode is tagged buffDraftTakeAI.
-- Left click ends 'ping' with isCancel=false while the mouse is still over the
-- clicked target, so GetRolloverInfo() still identifies that unit/structure.
CommandMode.AddEndBehavior(function(mode, data)
    if mode ~= 'ping' or (not data) or (not data.buffDraftTakeAI) then
        return
    end
    if data.isCancel then
        LOG("FAF_BUFF_DRAFT_AI_CONTROL_UI: take cancelled")
        return
    end

    local info = GetRolloverInfo()
    if not info or not info.entityId then
        LOG("FAF_BUFF_DRAFT_AI_CONTROL_UI: take aborted, no rollover entity")
        return
    end

    LOG("FAF_BUFF_DRAFT_AI_CONTROL_UI: take target sent id=" .. tostring(info.entityId)
        .. " bp=" .. tostring(info.blueprintId))
    SimCallback({
        Func = 'BuffDraftTakeAIUnits',
        Args = {
            entityId = info.entityId,
            blueprintId = info.blueprintId, -- stale-id guard; sim re-reads the real blueprint
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
    LOG("FAF_BUFF_DRAFT_AI_CONTROL_UI: take mode started")
    CommandMode.StartCommandMode('ping', {
        cursor = 'RULEUCC_Guard',
        buffDraftTakeAI = true,
    })
end
