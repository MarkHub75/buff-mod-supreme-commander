-- BuffDraft MVP 1: log a timer marker to game.log on every draft interval.
-- BuffDraft MVP 2: log armies and detect the two sides (slot-based, heuristic fallback).
-- BuffDraft MVP 3: run the sim-side draft pipeline (lua/draft.lua) on every timer tick.
-- This file is concatenated to the end of /lua/simInit.lua by the mod hook system.

-- Draft cadence comes from /mods/BuffDraft/lua/config.lua (DraftIntervalSeconds:
-- 300 for the 5-minute cadence); nil-safe fallback.
local function BuffDraftIntervalSeconds()
    return import('/mods/BuffDraft/lua/config.lua').DraftIntervalSeconds or 300
end

-- Set once at BeginSession by slot detection; nil means side detection incomplete.
local BuffDraftSides = nil

local function BuffDraftTimerThread()
    local interval = BuffDraftIntervalSeconds()
    local tick = 0
    while true do
        WaitSeconds(interval)
        tick = tick + 1
        LOG(string.format("FAF_BUFF_DRAFT: timer tick %d at %d seconds", tick, tick * interval))
        import('/mods/BuffDraft/lua/draft.lua').RunDraftTick(tick, BuffDraftSides)
    end
end

local BuffDraftMarkSlot = "ARMY_8"

-- Primary detection: slot-based. Mark is the army in the fixed slot BuffDraftMarkSlot,
-- every other non-civilian army belongs to Artem's side (Artem + his AI allies).
-- Returns { mark = {armyIndex...}, artem = {armyIndex...} }, or nil if the slot
-- was not found.
local function BuffDraftDetectSidesSlotMode()
    local markArmy = nil
    local sides = { mark = {}, artem = {} }
    local artemInfo = {}
    for index, brain in ArmyBrains do
        if not brain.Civilian then
            if brain.Name == BuffDraftMarkSlot then
                markArmy = brain
                table.insert(sides.mark, index)
            else
                table.insert(sides.artem, index)
                table.insert(artemInfo, string.format("%d (%s, %s)", index, tostring(brain.Name), tostring(brain.Nickname)))
            end
        end
    end

    if not markArmy then
        return nil
    end

    LOG("FAF_BUFF_DRAFT: slot mode enabled")
    LOG(string.format("FAF_BUFF_DRAFT: Mark slot army: %d (%s, %s, %s)",
        markArmy.Army, tostring(markArmy.Name), tostring(markArmy.Nickname), tostring(markArmy.BrainType)))
    LOG("FAF_BUFF_DRAFT: Artem side armies: " .. table.concat(artemInfo, "; "))
    return sides
end

-- Fallback/debug heuristic: Mark plays alone, Artem plays with AI allies. The side of
-- each human is that human plus every army allied to it. Runs once, after
-- BeginSessionTeams has applied the lobby team setup, so IsAlly reflects real alliances.
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
                -- store as string: table.concat in SupCom's Lua only accepts strings
                table.insert(side, tostring(index))
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
        LOG("FAF_BUFF_DRAFT: config draftInterval=" .. tostring(BuffDraftIntervalSeconds())
            .. " options=" .. tostring(import('/mods/BuffDraft/lua/config.lua').OptionsPerTick or 3))
        BuffDraftSides = BuffDraftDetectSidesSlotMode()
        if not BuffDraftSides then
            LOG("FAF_BUFF_DRAFT: slot mode failed (" .. BuffDraftMarkSlot .. " not found), falling back to heuristic")
            BuffDraftLogSides()
        end
        -- the admin panel needs the side->armies mapping between draft ticks too
        import('/mods/BuffDraft/lua/draft.lua').SetSides(BuffDraftSides)
        ForkThread(BuffDraftTimerThread)
        -- part 2: AI pressure director, isolated in lua/ai_director/ (delete that
        -- folder + set EnableAIDirector = false in config.lua to remove part 2).
        -- The flag gates the import itself, so config-off never touches the folder.
        if import('/mods/BuffDraft/lua/config.lua').EnableAIDirector then
            import('/mods/BuffDraft/lua/ai_director/director.lua').Start(BuffDraftSides)
        else
            LOG("FAF_AI_DIRECTOR: disabled by config")
        end
    end
end
