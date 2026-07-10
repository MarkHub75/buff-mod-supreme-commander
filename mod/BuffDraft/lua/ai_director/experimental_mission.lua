-- BuffDraft AI director D2: experimental missions. Idle land experimentals of
-- the AI armies on Artem's side are the biggest hoarded damage; each one gets
-- its own independent mission: the shared target scoring (targeting.lua) with a
-- softer threat gate (an experimental tanks PD), pathing layer derived from the
-- unit's MotionType, and one aggressive move. Same stuck safety idea as D1: a
-- no-progress counter, one retarget, then release with a cooldown - never
-- per-tick command spam.
--
-- With AIDirectorOrdersEnabled = false (default) this is a dry run: missions
-- are planned and logged, no order is issued. Never touches human armies,
-- Mark's side, ACUs or attached units; non-experimental units are D1's job.

local Targeting = import('/mods/BuffDraft/lua/ai_director/targeting.lua')
local BuffDraftConfig = import('/mods/BuffDraft/lua/config.lua')

local function Knob(name, default)
    local value = BuffDraftConfig[name]
    if value == nil then
        return default
    end
    return value
end

local OrdersEnabled = Knob('AIDirectorOrdersEnabled', false)
local ThreatFactor = Knob('AIDirectorExperimentalThreatFactor', 1.0)
local StuckTicks = Knob('AIDirectorStuckTicks', 3)
-- after a stuck release the unit sits this long before getting a new mission,
-- otherwise it would immediately re-target the same deterministic pick (loop)
local ReleaseCooldownSeconds = Knob('AIDirectorWaveCooldownSeconds', 180)

-- land experimentals only: air/naval experimentals move fine without help
local ExperimentalCat = categories.EXPERIMENTAL * categories.LAND * categories.MOBILE

-- NavUtils layer per unit: GC/Monkeylord/Megalith walk through water
-- (RULEUMT_Amphibious*), but e.g. a Fatboy is land-only - checking 'Amphibious'
-- for it would accept targets it can never reach (endless stuck/release loop)
local function PathLayerFor(unit)
    local motion = unit:GetBlueprint().Physics.MotionType
    if motion == 'RULEUMT_Amphibious' or motion == 'RULEUMT_AmphibiousFloating' then
        return 'Amphibious'
    end
    if motion == 'RULEUMT_Hover' then
        return 'Hover'
    end
    return 'Land'
end

-- an experimental fights at the target rather than "is stuck" inside this range
local FightingRange = 35

-- per army: map entityId -> mission { unit, targetPos, targetLabel, lastDist,
-- noProgressTicks, retargeted }
local MissionState = {}
-- per army: map entityId -> game time before which the unit gets no new mission
local ReleasedUntil = {}

local function UnitLabel(unit, id)
    return string.format("%s#%s", tostring(unit:GetBlueprint().BlueprintId), id)
end

local function IsAvailablePoolUnit(unit, brain)
    return not unit.Dead
        and unit.Army == brain.Army
        and unit:GetFractionComplete() == 1
        and unit:IsIdleState()
        and not unit:IsUnitState('Attached')
        and unit.PlatoonHandle
        and unit.PlatoonHandle.ArmyPool
end

local function ReleaseMission(brain, mission)
    if mission.platoon and brain:PlatoonExists(mission.platoon) then
        mission.platoon:PlatoonDisband()
    end
end

-- Update one tracked mission; returns false when the mission ended and the
-- experimental should go back to the idle pool.
local function UpdateMission(brain, id, mission)
    local unit = mission.unit
    if unit.Dead or unit.Army ~= brain.Army then
        ReleaseMission(brain, mission)
        return false
    end
    if unit:IsIdleState() then -- arrived and cleaned up, or orders were lost
        ReleaseMission(brain, mission)
        return false
    end

    local pos = unit:GetPosition()
    local dist = VDist2(pos[1], pos[3], mission.targetPos[1], mission.targetPos[3])
    if dist <= FightingRange then
        mission.noProgressTicks = 0
        mission.lastDist = dist
        return true
    end
    if mission.lastDist and mission.lastDist - dist < 2 then
        mission.noProgressTicks = mission.noProgressTicks + 1
    else
        mission.noProgressTicks = 0
    end
    mission.lastDist = dist

    if mission.noProgressTicks >= StuckTicks then
        if not mission.retargeted then
            mission.retargeted = true
            mission.noProgressTicks = 0
            LOG(string.format("FAF_AI_DIRECTOR: experimental stuck army=%d unit=%s action=retarget target=%s",
                brain.Army, UnitLabel(unit, id), mission.targetLabel))
            IssueClearCommands({ unit })
            IssueAggressiveMove({ unit }, mission.targetPos)
        else
            LOG(string.format("FAF_AI_DIRECTOR: experimental stuck army=%d unit=%s action=release target=%s",
                brain.Army, UnitLabel(unit, id), mission.targetLabel))
            IssueClearCommands({ unit })
            ReleasedUntil[brain.Army][id] = GetGameTimeSeconds() + ReleaseCooldownSeconds
            ReleaseMission(brain, mission)
            return false
        end
    end
    return true
end

-- One director tick for one AI army. Called under pcall from director.lua.
function Tick(brain, markArmies)
    local army = brain.Army
    local missions = MissionState[army]
    if not missions then
        missions = {}
        MissionState[army] = missions
    end
    if not ReleasedUntil[army] then
        ReleasedUntil[army] = {}
    end

    for id, mission in missions do
        if not UpdateMission(brain, id, mission) then
            missions[id] = nil
        end
    end

    -- idle finished land experimentals without a mission, heaviest first
    local records = {}
    local units = brain:GetListOfUnits(ExperimentalCat, true)
    if units then
        for _, unit in units do
            if IsAvailablePoolUnit(unit, brain) then
                local id = tostring(unit:GetEntityId())
                if not missions[id] then
                    table.insert(records, { unit = unit, mass = Targeting.UnitMass(unit), id = id })
                end
            end
        end
    end
    table.sort(records, function(a, b)
        if a.mass ~= b.mass then
            return a.mass > b.mass
        end
        return a.id < b.id
    end)

    for _, record in records do
        local unit = record.unit
        local label = UnitLabel(unit, record.id)
        if (ReleasedUntil[army][record.id] or 0) > GetGameTimeSeconds() then
            LOG(string.format("FAF_AI_DIRECTOR: skipped experimental army=%d unit=%s reason=release_cooldown",
                army, label))
        else
            local target, reason = Targeting.SelectTarget(brain, markArmies, unit:GetPosition(),
                record.mass, ThreatFactor, PathLayerFor(unit))
            if not target then
                LOG(string.format("FAF_AI_DIRECTOR: skipped experimental army=%d unit=%s reason=%s",
                    army, label, reason))
            elseif not OrdersEnabled then
                LOG(string.format("FAF_AI_DIRECTOR: dry-run experimental mission army=%d unit=%s target=%s",
                    army, label, target.label))
            else
                local targetPos = Targeting.SurfacePoint(target.pos[1], target.pos[3])
                local platoon = brain:MakePlatoon('', '')
                platoon.BuilderName = 'FAF_BUFF_DRAFT_EXPERIMENTAL'
                brain:AssignUnitsToPlatoon(platoon, { unit }, 'Attack', 'GrowthFormation')
                IssueAggressiveMove({ unit }, targetPos)
                missions[record.id] = {
                    unit = unit,
                    targetPos = targetPos,
                    targetLabel = target.label,
                    lastDist = nil,
                    noProgressTicks = 0,
                    retargeted = false,
                    platoon = platoon,
                }
                LOG(string.format("FAF_AI_DIRECTOR: experimental mission army=%d unit=%s target=%s",
                    army, label, target.label))
            end
        end
    end
end
