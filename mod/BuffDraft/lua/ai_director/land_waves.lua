-- BuffDraft AI director D1: staged land waves. Per AI army on Artem's side:
-- gather idle land combat units until the wave is big enough (unit count AND
-- total build-cost mass), pick the best visible, land-reachable, not-overdefended
-- structure target near Mark, then send the whole wave with one aggressive move.
-- Design borrowed as ideas (not code) from M28AI - see docs/AI_DIRECTOR.md:
-- no single-unit suicide, wave cooldown, order dedup (one order per wave, at most
-- one retarget), per-wave stuck counter instead of per-tick command spam.
--
-- With AIDirectorOrdersEnabled = false (default) this is a dry run: everything
-- is computed and logged, no order is ever issued. Never touches human armies,
-- Mark's side, ACUs, engineers, experimentals, transports or attached units.

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
local MinWaveUnits = Knob('AIDirectorMinWaveUnits', 12)
local MinWaveMass = Knob('AIDirectorMinWaveMass', 2000)
local MaxWaveUnits = Knob('AIDirectorMaxWaveUnits', 40)
local WaveCooldownSeconds = Knob('AIDirectorWaveCooldownSeconds', 180)
local LateGameSeconds = Knob('AIDirectorLateGameSeconds', 2400)
local T1SpamLimit = Knob('AIDirectorT1SpamLimit', 5)
local MaxTargetThreatFactor = Knob('AIDirectorMaxTargetThreatFactor', 0.5)
local StuckTicks = Knob('AIDirectorStuckTicks', 3)

-- wave units: mobile land combat only - no ACU/engineers (COMMAND/ENGINEER),
-- no experimentals (they get their own missions, D2), no transports
local WaveCat = categories.LAND * categories.MOBILE
    - categories.ENGINEER - categories.COMMAND - categories.EXPERIMENTAL
    - categories.TRANSPORTATION

-- per army: { cooldownUntil, waveCount, active = { id, unitsById, targetPos,
--             targetLabel, lastBestDist, noProgressTicks, retargeted } }
local WaveState = {}

local UnitMass = Targeting.UnitMass

-- Only take genuinely free units from the AI ArmyPool. IsIdleState alone is not
-- enough: a unit in a running FAF platoon can be momentarily idle between plan
-- steps, and issuing a direct order then corrupts the stock platoon's lifecycle.
local function IsAvailablePoolUnit(unit, brain)
    return not unit.Dead
        and unit.Army == brain.Army
        and unit:GetFractionComplete() == 1
        and unit:IsIdleState()
        and not unit:IsUnitState('Attached')
        and unit.PlatoonHandle
        and unit.PlatoonHandle.ArmyPool
end

-- Deterministic gather: idle finished ArmyPool wave units, heaviest first,
-- late-game T1 cap, hard cap at MaxWaveUnits. Returns sorted records.
local function GatherCandidates(brain, state)
    local records = {}
    local units = brain:GetListOfUnits(WaveCat, true)
    if units then
        for _, unit in units do
            if IsAvailablePoolUnit(unit, brain) then
                local id = tostring(unit:GetEntityId())
                if not (state.active and state.active.unitsById[id]) then
                    table.insert(records, { unit = unit, mass = UnitMass(unit), id = id })
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

    -- late game: cap weak T1 units so waves are not useless spam
    if GetGameTimeSeconds() >= LateGameSeconds then
        local kept, t1Count, filtered = {}, 0, 0
        for _, record in records do
            if EntityCategoryContains(categories.TECH1, record.unit) then
                if t1Count < T1SpamLimit then
                    t1Count = t1Count + 1
                    table.insert(kept, record)
                else
                    filtered = filtered + 1
                end
            else
                table.insert(kept, record)
            end
        end
        if filtered > 0 then
            LOG(string.format("FAF_AI_DIRECTOR: late-game filtered weak_t1=%d army=%d", filtered, brain.Army))
        end
        records = kept
    end

    while table.getn(records) > MaxWaveUnits do
        table.remove(records)
    end
    return records
end

local function ReleaseWave(brain, state, wave)
    if wave.platoon and brain:PlatoonExists(wave.platoon) then
        wave.platoon:PlatoonDisband()
    end
    state.active = nil
end

-- Stuck safety for the one active wave of an army: released when everyone is
-- dead or idle again; if the closest unit stops closing on the target for
-- StuckTicks director ticks, retarget once (re-path the survivors to the same
-- point), the second time release the units (clear our own orders, they return
-- to the gather pool). No per-tick command spam.
local function CheckActiveWave(brain, state)
    local wave = state.active
    local alive, allIdle = {}, true
    for _, unit in wave.unitsById do
        if not unit.Dead and unit.Army == brain.Army then
            table.insert(alive, unit)
            if not unit:IsIdleState() then
                allIdle = false
            end
        end
    end
    if table.getn(alive) == 0 or allIdle then
        ReleaseWave(brain, state, wave)
        return
    end

    local bestDist = nil
    for _, unit in alive do
        local pos = unit:GetPosition()
        local dist = VDist2(pos[1], pos[3], wave.targetPos[1], wave.targetPos[3])
        if not bestDist or dist < bestDist then
            bestDist = dist
        end
    end
    if bestDist <= 30 then -- close enough: they are fighting at the target
        wave.noProgressTicks = 0
        wave.lastBestDist = bestDist
        return
    end
    if wave.lastBestDist and wave.lastBestDist - bestDist < 2 then
        wave.noProgressTicks = wave.noProgressTicks + 1
    else
        wave.noProgressTicks = 0
    end
    wave.lastBestDist = bestDist

    if wave.noProgressTicks >= StuckTicks then
        if not wave.retargeted then
            wave.retargeted = true
            wave.noProgressTicks = 0
            LOG(string.format("FAF_AI_DIRECTOR: wave stuck army=%d wave=%d action=retarget target=%s",
                brain.Army, wave.id, wave.targetLabel))
            IssueClearCommands(alive)
            IssueAggressiveMove(alive, wave.targetPos)
        else
            LOG(string.format("FAF_AI_DIRECTOR: wave stuck army=%d wave=%d action=release target=%s",
                brain.Army, wave.id, wave.targetLabel))
            ReleaseWave(brain, state, wave)
            -- without this the released units are re-gathered next tick and sent
            -- to the same deterministic target again (endless stuck/order loop)
            state.cooldownUntil = GetGameTimeSeconds() + WaveCooldownSeconds
        end
    end
end

-- One director tick for one AI army. Called under pcall from director.lua.
function Tick(brain, markArmies)
    local army = brain.Army
    local state = WaveState[army]
    if not state then
        state = { cooldownUntil = 0, waveCount = 0 }
        WaveState[army] = state
    end

    if state.active then
        CheckActiveWave(brain, state)
    end

    local records = GatherCandidates(brain, state)
    local count = table.getn(records)
    local mass = 0
    for _, record in records do
        mass = mass + record.mass
    end
    LOG(string.format("FAF_AI_DIRECTOR: wave candidate army=%d units=%d mass=%d threshold=%d/%d",
        army, count, mass, MinWaveUnits, MinWaveMass))

    if state.active then
        LOG(string.format("FAF_AI_DIRECTOR: skipped wave army=%d reason=wave_active", army))
        return
    end
    if count < MinWaveUnits or mass < MinWaveMass then
        LOG(string.format("FAF_AI_DIRECTOR: skipped wave army=%d reason=below_threshold", army))
        return
    end
    if GetGameTimeSeconds() < state.cooldownUntil then
        LOG(string.format("FAF_AI_DIRECTOR: skipped wave army=%d reason=cooldown", army))
        return
    end

    local wavePos = records[1].unit:GetPosition()
    local target, reason = Targeting.SelectTarget(brain, markArmies, wavePos, mass,
        MaxTargetThreatFactor, 'Land')
    if not target then
        LOG(string.format("FAF_AI_DIRECTOR: skipped wave army=%d reason=%s", army, reason))
        return
    end

    local targetPos = Targeting.SurfacePoint(target.pos[1], target.pos[3])
    if not OrdersEnabled then
        LOG(string.format("FAF_AI_DIRECTOR: dry-run wave army=%d target=%s units=%d",
            army, target.label, count))
        return
    end

    local waveUnits, unitsById = {}, {}
    for _, record in records do
        table.insert(waveUnits, record.unit)
        unitsById[record.id] = record.unit
    end
    -- Move units out of ArmyPool before ordering them. This is the stock FAF
    -- pattern (tech-ai ExpansionHelpThread) and prevents another AI builder from
    -- assigning the same units while the director owns the wave.
    local platoon = brain:MakePlatoon('', '')
    platoon.BuilderName = 'FAF_BUFF_DRAFT_LAND_WAVE'
    brain:AssignUnitsToPlatoon(platoon, waveUnits, 'Attack', 'GrowthFormation')
    IssueAggressiveMove(waveUnits, targetPos)
    state.cooldownUntil = GetGameTimeSeconds() + WaveCooldownSeconds
    state.waveCount = state.waveCount + 1
    state.active = {
        id = state.waveCount,
        unitsById = unitsById,
        targetPos = targetPos,
        targetLabel = target.label,
        lastBestDist = nil,
        noProgressTicks = 0,
        retargeted = false,
        platoon = platoon,
    }
    LOG(string.format("FAF_AI_DIRECTOR: issued land wave army=%d wave=%d units=%d target=%s",
        army, state.waveCount, count, target.label))
end
