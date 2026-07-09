-- BuffDraft part 2: AI pressure director. Problem: after ~30 minutes on Dual Gap
-- the allied Sorian AIs hoard land armies that cannot cross water, idle and load
-- the sim without pressuring Mark.
-- MVP 0 (survey): once the game passes AIDirectorStartSeconds this thread logs,
-- every AIDirectorIntervalSeconds, one line per AI army on Artem's side with
-- what that army has available.
-- MVP D1 (land waves): after the survey each tick runs lua/ai_director/
-- land_waves.lua per AI army - gather idle land combat units, attack a scored
-- target near Mark once thresholds are met.
-- MVP D2 (experimental missions): each idle land experimental gets its own
-- aggressive-move mission (lua/ai_director/experimental_mission.lua).
-- MVP D3 (forward fortify): idle AI engineers build defense packages at the
-- base and owned mex clusters (lua/ai_director/fortify.lua).
-- All order modules are dry-run (no orders) until AIDirectorOrdersEnabled = true.
-- Never touches human armies, Mark's side, ACUs or civilians.
-- Confirmed sim APIs and design notes: docs/AI_DIRECTOR.md.
--
-- ISOLATION CONTRACT: all AI director code lives in lua/ai_director/ and is
-- reached only through the guarded one-liner in hook/lua/simInit.lua plus the
-- AIDirector*/EnableAIDirector knobs in lua/config.lua. Deleting this folder
-- and setting EnableAIDirector = false removes part 2 completely; no
-- buff/draft/effects/UI file may import anything from here.

LOG("FAF_AI_DIRECTOR: loaded from lua/ai_director")

local BuffDraftConfig = import('/mods/BuffDraft/lua/config.lua')

-- nil-safe knob read (same pattern as effects.lua)
local function Knob(name, default)
    local value = BuffDraftConfig[name]
    if value == nil then
        return default
    end
    return value
end

local EnableAIDirector = Knob('EnableAIDirector', false)
local StartSeconds = Knob('AIDirectorStartSeconds', 1800)
local IntervalSeconds = Knob('AIDirectorIntervalSeconds', 60)
local LandWavesEnabled = Knob('AIDirectorLandWavesEnabled', false)
local ExperimentalMissionEnabled = Knob('AIDirectorExperimentalMissionEnabled', false)
local FortifyEnabled = Knob('AIDirectorFortifyEnabled', false)

-- Survey categories. ACU carries COMMAND and ENGINEER; the director must never
-- touch ACUs, so COMMAND is excluded everywhere (FINDINGS idiom for engineers).
local LandCombatCat = categories.LAND * categories.MOBILE
    - categories.ENGINEER - categories.COMMAND - categories.EXPERIMENTAL
local TransportCat = categories.TRANSPORTATION
local ExperimentalCat = categories.EXPERIMENTAL
local EngineerCat = categories.ENGINEER - categories.COMMAND

-- GetListOfUnits' third (requireBuilt) parameter is not functional (FINDINGS),
-- so unfinished and dead units are filtered here.
local function CountFinished(units)
    local count = 0
    if units then
        for _, unit in units do
            if not unit.Dead and unit:GetFractionComplete() == 1 then
                count = count + 1
            end
        end
    end
    return count
end

local function SurveyArmy(brain)
    local land = CountFinished(brain:GetListOfUnits(LandCombatCat, false))
    local landIdle = CountFinished(brain:GetListOfUnits(LandCombatCat, true))
    local transports = CountFinished(brain:GetListOfUnits(TransportCat, false))
    local experimentals = CountFinished(brain:GetListOfUnits(ExperimentalCat, false))
    local engineers = CountFinished(brain:GetListOfUnits(EngineerCat, false))
    LOG(string.format(
        "FAF_AI_DIRECTOR: army=%d ai=%s land=%d landIdle=%d transports=%d experimentals=%d experimentalsIdle=%d engineers=%d engineersIdle=%d",
        brain.Army, tostring(brain.Nickname), land, landIdle, transports,
        experimentals, CountFinished(brain:GetListOfUnits(ExperimentalCat, true)),
        engineers, CountFinished(brain:GetListOfUnits(EngineerCat, true))))
end

local function DirectorThread(aiArmies, markArmies)
    -- WaitSeconds waits game seconds, so the threshold follows game time
    while GetGameTimeSeconds() < StartSeconds do
        WaitSeconds(10)
    end
    LOG(string.format("FAF_AI_DIRECTOR: survey active at %d game seconds", GetGameTimeSeconds()))

    -- Land waves and experimental missions need the navigational mesh for
    -- reachability checks. Generate() is a no-op when an AI brain already
    -- generated it (base-ai.lua does); on a legacy-AI game this builds it once,
    -- here, before the first order tick.
    local wantOrders = LandWavesEnabled or ExperimentalMissionEnabled
    local navReady = false
    if wantOrders and table.getn(markArmies) > 0 then
        local ok, err = pcall(import('/lua/sim/navutils.lua').Generate)
        navReady = ok
        if not ok then
            WARN("FAF_AI_DIRECTOR: nav mesh generation failed, order modules disabled: " .. tostring(err))
        end
    elseif wantOrders then
        LOG("FAF_AI_DIRECTOR: order modules disabled, no Mark armies detected")
    end
    local runLandWaves = LandWavesEnabled and navReady
    local runExperimentals = ExperimentalMissionEnabled and navReady

    while true do
        for _, index in aiArmies do
            if not ArmyIsOutOfGame(index) then
                local ok, err = pcall(SurveyArmy, ArmyBrains[index])
                if not ok then
                    WARN("FAF_AI_DIRECTOR: survey failed for army " .. tostring(index) .. ": " .. tostring(err))
                end
                if runLandWaves then
                    local okWave, errWave = pcall(
                        import('/mods/BuffDraft/lua/ai_director/land_waves.lua').Tick,
                        ArmyBrains[index], markArmies)
                    if not okWave then
                        WARN("FAF_AI_DIRECTOR: land wave tick failed for army " .. tostring(index) .. ": " .. tostring(errWave))
                    end
                end
                if runExperimentals then
                    local okExp, errExp = pcall(
                        import('/mods/BuffDraft/lua/ai_director/experimental_mission.lua').Tick,
                        ArmyBrains[index], markArmies)
                    if not okExp then
                        WARN("FAF_AI_DIRECTOR: experimental tick failed for army " .. tostring(index) .. ": " .. tostring(errExp))
                    end
                end
                -- fortify needs no nav mesh and no Mark armies: gated only by its flag
                if FortifyEnabled then
                    local okFort, errFort = pcall(
                        import('/mods/BuffDraft/lua/ai_director/fortify.lua').Tick,
                        ArmyBrains[index])
                    if not okFort then
                        WARN("FAF_AI_DIRECTOR: fortify tick failed for army " .. tostring(index) .. ": " .. tostring(errFort))
                    end
                end
            end
        end
        WaitSeconds(IntervalSeconds)
    end
end

-- Called once from the simInit hook at BeginSession with the side mapping
-- produced by slot detection ({ mark = {...}, artem = {...} } or nil).
function Start(sides)
    if not EnableAIDirector then
        LOG("FAF_AI_DIRECTOR: disabled by config")
        return
    end
    if not sides or not sides.artem then
        LOG("FAF_AI_DIRECTOR: no side mapping (slot detection failed), director not started")
        return
    end

    local aiArmies = {}
    local info = {}
    for _, index in sides.artem do
        local brain = ArmyBrains[index]
        if brain and brain.BrainType == 'AI' and not brain.Civilian then
            table.insert(aiArmies, index)
            table.insert(info, string.format("%d (%s)", index, tostring(brain.Nickname)))
        end
    end

    if table.getn(aiArmies) == 0 then
        LOG("FAF_AI_DIRECTOR: no AI armies on Artem's side, director not started")
        return
    end

    local markArmies = {}
    for _, index in (sides.mark or {}) do
        local brain = ArmyBrains[index]
        if brain and not brain.Civilian then
            table.insert(markArmies, index)
        end
    end

    LOG(string.format("FAF_AI_DIRECTOR: armed, start=%ds interval=%ds landWaves=%s experimentals=%s fortify=%s orders=%s, AI armies: %s",
        StartSeconds, IntervalSeconds, tostring(LandWavesEnabled), tostring(ExperimentalMissionEnabled),
        tostring(FortifyEnabled), tostring(Knob('AIDirectorOrdersEnabled', false)), table.concat(info, "; ")))
    ForkThread(DirectorThread, aiArmies, markArmies)
end
