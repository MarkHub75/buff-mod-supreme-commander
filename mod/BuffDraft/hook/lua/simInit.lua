-- BuffDraft MVP 1: log a marker to game.log every 5 game minutes.
-- BuffDraft MVP 2: log armies and detect the two sides (solo human vs human with AI allies).
-- This file is concatenated to the end of /lua/simInit.lua by the mod hook system.

local function BuffDraftTimerThread()
    local tick = 0
    while true do
        WaitSeconds(300)
        tick = tick + 1
        LOG(string.format("FAF_BUFF_DRAFT: timer tick %d at %d minutes", tick, tick * 5))
    end
end

-- Expected game mode: Mark plays alone, Artem plays with AI allies. The side of each
-- human is that human plus every army allied to it. Runs once, after BeginSessionTeams
-- has applied the lobby team setup, so IsAlly reflects the real alliances.
local function BuffDraftLogSides()
    local humans = {}
    for index, brain in ArmyBrains do
        local setup = ScenarioInfo.ArmySetup[brain.Name] or {}
        LOG(string.format(
            "FAF_BUFF_DRAFT: army %d name=%s nickname=%s type=%s team=%s faction=%s civilian=%s",
            index,
            tostring(brain.Name),
            tostring(brain.Nickname),
            tostring(brain.BrainType),
            tostring(setup.Team),
            tostring(brain:GetFactionIndex()),
            tostring(brain.Civilian)
        ))
        if brain.BrainType == 'Human' and not brain.Civilian then
            table.insert(humans, index)
        end
    end

    local soloSide, alliedSide
    for _, humanIndex in humans do
        local side = {}
        for index, brain in ArmyBrains do
            if (not brain.Civilian) and IsAlly(humanIndex, index) then
                table.insert(side, index)
            end
        end
        if table.getn(side) == 1 then
            soloSide = side
        else
            alliedSide = side
        end
    end

    if table.getn(humans) == 2 and soloSide and alliedSide then
        LOG("FAF_BUFF_DRAFT: side Mark (solo human): armies " .. table.concat(soloSide, ", "))
        LOG("FAF_BUFF_DRAFT: side Artem (human + allies): armies " .. table.concat(alliedSide, ", "))
    else
        LOG("FAF_BUFF_DRAFT: side detection incomplete")
    end
end

-- introduce new scope to guarantee our local variables don't overwrite anything in another mod
do
    local oldBeginSession = BeginSession
    function BeginSession()
        -- preserve original behavior or another mod's changes
        oldBeginSession()

        LOG("FAF_BUFF_DRAFT: mod active, starting timer thread")
        BuffDraftLogSides()
        ForkThread(BuffDraftTimerThread)
    end
end
