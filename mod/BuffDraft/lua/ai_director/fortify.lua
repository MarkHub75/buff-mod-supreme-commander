-- BuffDraft AI director D3: forward fortify. Idle engineers of the AI armies on
-- Artem's side reinforce owned territory: the base and every owned mex cluster
-- get a small defense package (radar, AA, PD, TMD, shield - scaled by the
-- engineer's tech). One engineer = one build task; every area has a cooldown and
-- a per-structure "already defended" check, so nothing is spammed.
--
-- Build path (FAF-native, no Sorian builder managers touched):
--   brain:DecideWhatToBuild(eng, buildingType, BuildingTemplates[faction])
--     -> faction/tech-correct blueprint id (engine/Sim/CAiBrain.lua:101)
--   brain:CanBuildStructureAt(bpId, pos) -> placement check (CAiBrain.lua:71,
--     may return false positives - a failed order just leaves the engineer idle)
--   IssueBuildMobile({eng}, pos, bpId, {}) -> the build order (engine/Sim.lua:768)
-- AIExecuteBuildStructure was rejected on purpose: it depends on builder-manager
-- data and calls GetFocusArmy() from sim code.
--
-- With AIDirectorOrdersEnabled = false (default) this is a dry run: packages are
-- planned and logged, no order is issued. Never touches human armies, Mark's
-- side, ACUs, pods or attached units.

local BuffDraftConfig = import('/mods/BuffDraft/lua/config.lua')

local function Knob(name, default)
    local value = BuffDraftConfig[name]
    if value == nil then
        return default
    end
    return value
end

local OrdersEnabled = Knob('AIDirectorOrdersEnabled', false)
local StartSeconds = Knob('AIDirectorFortifyStartSeconds', 1200)
local IntervalSeconds = Knob('AIDirectorFortifyIntervalSeconds', 90)
local MaxEngineersPerTick = Knob('AIDirectorFortifyMaxEngineersPerTick', 3)
local AreaCooldownSeconds = Knob('AIDirectorFortifyAreaCooldownSeconds', 300)

-- builders: mobile engineers without the ACU (COMMAND) and without assist-only
-- drones (ENGINEER - POD is FAF's own idiom, sorianutilities.lua:913)
local EngineerCat = categories.MOBILE * categories.ENGINEER
    - categories.COMMAND - categories.POD - categories.INSIGNIFICANTUNIT

local MexCat = categories.STRUCTURE * categories.MASSEXTRACTION

-- The defense package, checked in order; the first unsatisfied item wins.
-- `have` is what counts as "this need is already covered" near the point
-- (allied units count too - do not duplicate a teammate's defense).
-- TMD: ANTIMISSILE * TECH2 so SMDs (TECH3 SILO) do not satisfy the check.
local Package = {
    { key = 'radar', types = { 'T1Radar' }, minTech = 1, want = 1, radius = 30,
        have = categories.STRUCTURE * categories.RADAR },
    { key = 'aa', types = { 'T1AADefense' }, minTech = 1, want = 2, radius = 24,
        have = categories.STRUCTURE * categories.DEFENSE * categories.ANTIAIR },
    { key = 'pd', types = { 'T1GroundDefense' }, minTech = 1, want = 2, radius = 24,
        have = categories.STRUCTURE * categories.DEFENSE * categories.DIRECTFIRE },
    { key = 'tmd', types = { 'T2MissileDefense' }, minTech = 2, want = 1, radius = 24,
        have = categories.STRUCTURE * categories.DEFENSE * categories.ANTIMISSILE * categories.TECH2 },
    { key = 'shield', types = { 'T3ShieldDefense', 'T2ShieldDefense' }, minTech = 2, want = 1, radius = 24,
        have = categories.STRUCTURE * categories.SHIELD },
}

-- deterministic search offsets around a fortify point for a buildable spot
local BuildOffsets = {
    { 0, 0 }, { 6, 0 }, { -6, 0 }, { 0, 6 }, { 0, -6 },
    { 6, 6 }, { -6, 6 }, { 6, -6 }, { -6, -6 },
    { 12, 0 }, { -12, 0 }, { 0, 12 }, { 0, -12 },
    { 12, 12 }, { -12, 12 }, { 12, -12 }, { -12, -12 },
}

-- per army: { lastRun = gameSeconds, areaCooldown = { [pointKey] = untilSeconds } }
local FortifyState = {}

local function UnitLabel(unit)
    return string.format("%s#%s", tostring(unit:GetBlueprint().BlueprintId),
        tostring(unit:GetEntityId()))
end

local function EngineerTech(eng)
    if EntityCategoryContains(categories.TECH3 + categories.SUBCOMMANDER, eng) then
        return 3
    end
    if EntityCategoryContains(categories.TECH2, eng) then
        return 2
    end
    return 1
end

-- Fortify points: the army base plus one point per owned mex cluster (mex
-- positions deduplicated on a 32-unit grid). Deterministic order: base first,
-- then clusters sorted by key.
local function FortifyPoints(brain)
    local points = {}
    local startX, startZ = brain:GetArmyStartPos()
    table.insert(points, { key = 'base', pos = { startX, GetSurfaceHeight(startX, startZ), startZ } })

    local clusters = {}
    for _, mex in brain:GetListOfUnits(MexCat, false) or {} do
        if not mex.Dead and mex:GetFractionComplete() == 1 then
            local pos = mex:GetPosition()
            local key = string.format("mex:%d:%d", math.floor(pos[1] / 32), math.floor(pos[3] / 32))
            if not clusters[key] then
                clusters[key] = { key = key, pos = pos }
            end
        end
    end
    local keys = {}
    for key, _ in clusters do
        table.insert(keys, key)
    end
    table.sort(keys)
    for _, key in keys do
        table.insert(points, clusters[key])
    end
    return points
end

-- The first package item this point still needs and this engineer can build,
-- or nil + whether everything was already covered.
local function NextMissingItem(brain, point, tech)
    local covered = true
    for _, item in Package do
        local existing = 0
        for _, unit in brain:GetUnitsAroundPoint(item.have, point.pos, item.radius, 'Ally') or {} do
            if not unit.Dead then
                existing = existing + 1
            end
        end
        if existing < item.want then
            covered = false
            if tech >= item.minTech then
                return item, false
            end
        end
    end
    return nil, covered
end

-- Faction/tech-correct blueprint for the item, via the engine template decision.
-- Tries the item's types in order (e.g. T3 shield falls back to T2).
local function DecideBlueprint(brain, eng, item, tech)
    local template = import('/lua/BuildingTemplates.lua').BuildingTemplates[brain:GetFactionIndex()]
    if not template then
        return nil
    end
    for _, buildingType in item.types do
        if not (buildingType == 'T3ShieldDefense' and tech < 3) then
            local bpId = brain:DecideWhatToBuild(eng, buildingType, template)
            if bpId then
                return bpId, buildingType
            end
        end
    end
    return nil
end

local function FindBuildSpot(brain, bpId, point)
    for _, offset in BuildOffsets do
        local x = point.pos[1] + offset[1]
        local z = point.pos[3] + offset[2]
        local pos = { x, GetTerrainHeight(x, z), z }
        if brain:CanBuildStructureAt(bpId, pos) then
            return pos
        end
    end
    return nil
end

-- A build order issued while the engineer stays in ArmyPool can race the stock
-- platoon former. Hold it in a dedicated platoon until the task finishes, then
-- return it through the normal PlatoonDisband path.
local function ReleaseEngineerWhenIdle(brain, platoon, eng)
    WaitSeconds(1)
    while brain:PlatoonExists(platoon)
            and not eng.Dead
            and eng.Army == brain.Army
            and not eng:IsIdleState() do
        WaitSeconds(2)
    end
    if brain:PlatoonExists(platoon) then
        platoon:PlatoonDisband()
    end
end

local function IssueFortifyBuild(brain, eng, spot, bpId)
    local platoon = brain:MakePlatoon('', '')
    platoon.BuilderName = 'FAF_BUFF_DRAFT_FORTIFY'
    brain:AssignUnitsToPlatoon(platoon, { eng }, 'Support', 'None')
    IssueBuildMobile({ eng }, spot, bpId, {})
    ForkThread(ReleaseEngineerWhenIdle, brain, platoon, eng)
end

-- One director tick for one AI army. Called under pcall from director.lua.
-- Runs on its own cadence (StartSeconds/IntervalSeconds) inside the director's
-- tick loop, so it needs no thread of its own.
function Tick(brain)
    local now = GetGameTimeSeconds()
    if now < StartSeconds then
        return
    end
    local army = brain.Army
    local state = FortifyState[army]
    if not state then
        state = { lastRun = -IntervalSeconds, areaCooldown = {} }
        FortifyState[army] = state
    end
    if now - state.lastRun < IntervalSeconds then
        return
    end
    state.lastRun = now

    -- idle finished engineers, deterministic order (tech desc, entity id asc)
    local engineers = {}
    for _, eng in brain:GetListOfUnits(EngineerCat, true) or {} do
        if not eng.Dead
                and eng.Army == brain.Army
                and eng:GetFractionComplete() == 1
                and eng:IsIdleState()
                and not eng:IsUnitState('Attached')
                and eng.PlatoonHandle
                and eng.PlatoonHandle.ArmyPool then
            table.insert(engineers, {
                unit = eng,
                tech = EngineerTech(eng),
                id = tostring(eng:GetEntityId()),
            })
        end
    end
    if table.getn(engineers) == 0 then
        LOG(string.format("FAF_AI_DIRECTOR: fortify skipped army=%d reason=no_engineer", army))
        return
    end
    table.sort(engineers, function(a, b)
        if a.tech ~= b.tech then
            return a.tech > b.tech
        end
        return a.id < b.id
    end)

    local points = FortifyPoints(brain)
    local issued = 0
    local pointIndex = 1
    local sawCooldown, sawCovered = false, false

    for _, record in engineers do
        if issued >= MaxEngineersPerTick then
            break
        end
        local eng = record.unit
        -- walk the points from where the previous engineer left off, so several
        -- engineers fortify several areas in one tick instead of piling on one
        local assigned = false
        while pointIndex <= table.getn(points) and not assigned do
            local point = points[pointIndex]
            pointIndex = pointIndex + 1
            if (state.areaCooldown[point.key] or 0) > now then
                sawCooldown = true
            else
                local item, covered = NextMissingItem(brain, point, record.tech)
                if covered then
                    sawCovered = true
                elseif item then
                    LOG(string.format("FAF_AI_DIRECTOR: fortify candidate army=%d eng=%s point=%s item=%s",
                        army, UnitLabel(eng), point.key, item.key))
                    local bpId, buildingType = DecideBlueprint(brain, eng, item, record.tech)
                    if not bpId then
                        LOG(string.format("FAF_AI_DIRECTOR: fortify skipped army=%d reason=no_build_api point=%s item=%s",
                            army, point.key, item.key))
                    else
                        local spot = FindBuildSpot(brain, bpId, point)
                        if not spot then
                            LOG(string.format("FAF_AI_DIRECTOR: fortify skipped army=%d reason=no_spot point=%s bp=%s",
                                army, point.key, tostring(bpId)))
                        elseif not OrdersEnabled then
                            LOG(string.format("FAF_AI_DIRECTOR: fortify planned structure=%s (%s) pos=%d,%d point=%s eng=%s",
                                tostring(bpId), tostring(buildingType), spot[1], spot[3], point.key, UnitLabel(eng)))
                            assigned = true -- keep the walk moving in dry-run too
                        else
                            IssueFortifyBuild(brain, eng, spot, bpId)
                            state.areaCooldown[point.key] = now + AreaCooldownSeconds
                            issued = issued + 1
                            assigned = true
                            LOG(string.format("FAF_AI_DIRECTOR: fortify issued army=%d eng=%s structure=%s pos=%d,%d point=%s",
                                army, UnitLabel(eng), tostring(bpId), spot[1], spot[3], point.key))
                        end
                    end
                end
            end
        end
        if pointIndex > table.getn(points) then
            break -- no points left for the remaining engineers this tick
        end
    end

    if issued == 0 and OrdersEnabled then
        if sawCooldown then
            LOG(string.format("FAF_AI_DIRECTOR: fortify skipped army=%d reason=cooldown", army))
        elseif sawCovered then
            LOG(string.format("FAF_AI_DIRECTOR: fortify skipped army=%d reason=duplicate (all points covered)", army))
        end
    end
end
