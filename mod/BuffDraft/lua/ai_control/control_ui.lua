-- BuffDraft AI control (UI side): input only. StartTakeMode enters the 'ping'
-- command mode (the same multifunction ping-button pattern as orbital lance
-- targeting in ui/history.lua); the next left click on the map sends the world
-- point to the BuffDraftTakeAIUnits sim callback. Esc / another command cancels.
-- No gameplay logic here - the sim validates the sender, the point and every
-- unit on its own copy of the config, so this file cannot be used to cheat.
--
-- Manual open (besides the admin panel button):
--   ui_lua import('/mods/BuffDraft/lua/ai_control/control_ui.lua').StartTakeMode()

local CommandMode = import('/lua/ui/game/commandmode.lua')
local BuffDraftConfig = import('/mods/BuffDraft/lua/config.lua')

-- Registered once (module import is cached). Our mode is tagged buffDraftTakeAI;
-- left click ends 'ping' with isCancel=false while the mouse is still on the
-- clicked point (exactly how ping.lua DoPing reads it).
CommandMode.AddEndBehavior(function(mode, data)
    if mode ~= 'ping' or (not data) or (not data.buffDraftTakeAI) then
        return
    end
    if data.isCancel then
        LOG("FAF_AI_CONTROL_UI: take cancelled")
        return
    end
    local position = GetMouseWorldPos()
    for _, v in position do
        if v ~= v then -- NaN: the click hit no world position (same check as DoPing)
            LOG("FAF_AI_CONTROL_UI: take aborted, no world position")
            return
        end
    end
    LOG("FAF_AI_CONTROL_UI: take point sent")
    SimCallback({
        Func = 'BuffDraftTakeAIUnits',
        Args = { x = position[1], z = position[3] },
    })
end, 'BuffDraftTakeAI')

--- Enter the take-units targeting mode; the next left click takes allied AI
--- land units around the clicked point (validated sim-side).
function StartTakeMode()
    if not BuffDraftConfig.EnableAIControl then
        LOG("FAF_AI_CONTROL_UI: disabled by config")
        return
    end
    LOG("FAF_AI_CONTROL_UI: take mode started")
    CommandMode.StartCommandMode('ping', {
        cursor = 'RULEUCC_Guard',
        buffDraftTakeAI = true,
    })
end
