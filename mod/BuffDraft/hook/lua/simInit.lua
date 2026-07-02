-- BuffDraft MVP 1: log a marker to game.log every 5 game minutes.
-- This file is concatenated to the end of /lua/simInit.lua by the mod hook system.

local function BuffDraftTimerThread()
    local tick = 0
    while true do
        WaitSeconds(300)
        tick = tick + 1
        LOG(string.format("FAF_BUFF_DRAFT: timer tick %d at %d minutes", tick, tick * 5))
    end
end

-- introduce new scope to guarantee our local variables don't overwrite anything in another mod
do
    local oldBeginSession = BeginSession
    function BeginSession()
        -- preserve original behavior or another mod's changes
        oldBeginSession()

        LOG("FAF_BUFF_DRAFT: mod active, starting timer thread")
        ForkThread(BuffDraftTimerThread)
    end
end
