-- BuffDraft AI director: shared target selection for land waves (D1) and
-- experimental missions (D2). Deterministic and intel-fair: only finished Mark
-- structures the asking AI army has ever identified (blip seen) are candidates;
-- defense pressure around a candidate is measured with the intel-aware 'Enemy'
-- unit filter. The caller supplies its "budget" mass and threat tolerance.

local NavUtils = import('/lua/sim/navutils.lua')
local BuffDraftConfig = import('/mods/BuffDraft/lua/config.lua')

local function Knob(name, default)
    local value = BuffDraftConfig[name]
    if value == nil then
        return default
    end
    return value
end

local TargetDefenseRadius = Knob('AIDirectorTargetDefenseRadius', 40)

-- what counts as "defense mass" around a candidate target: PD, indirect-fire
-- defenses and shield structures; walls and AA are irrelevant to a ground attack
local ThreatCat = categories.STRUCTURE * categories.DEFENSE
        * (categories.DIRECTFIRE + categories.INDIRECTFIRE) - categories.WALL
    + categories.STRUCTURE * categories.SHIELD

-- candidate target classes, checked in order (first match wins), value is the
-- deterministic base score before the defense penalty
local TargetClasses = {
    { name = 'gameender', value = 400, cat = categories.STRUCTURE
        * (categories.ARTILLERY * categories.TECH3 + categories.NUKE + categories.EXPERIMENTAL) },
    { name = 'factory', value = 250, cat = categories.STRUCTURE * categories.FACTORY },
    { name = 'mex', value = 150, cat = categories.STRUCTURE
        * (categories.MASSEXTRACTION + categories.MASSFABRICATION) },
    { name = 'energy', value = 120, cat = categories.STRUCTURE * categories.ENERGYPRODUCTION },
    { name = 'structure', value = 40, cat = categories.STRUCTURE },
}

function UnitMass(unit)
    local economy = unit:GetBlueprint().Economy
    return (economy and economy.BuildCostMass) or 0
end

function PosLabel(pos)
    return string.format("%d,%d", pos[1], pos[3])
end

function SurfacePoint(x, z)
    return { x, GetSurfaceHeight(x, z), z }
end

-- true if the AI army has ever identified this enemy unit (FINDINGS: no blip =
-- never seen). GetBlip can error on odd entities, hence pcall.
local function SeenByArmy(unit, armyIndex)
    local ok, blip = pcall(unit.GetBlip, unit, armyIndex)
    if not ok or not blip then
        return false
    end
    local okSeen, seen = pcall(blip.IsSeenEver, blip, armyIndex)
    return okSeen and seen
end

-- Defense mass the AI army can see around a point (intel-aware 'Enemy' filter)
local function ThreatMassAround(brain, pos)
    local total = 0
    local defenses = brain:GetUnitsAroundPoint(ThreatCat, pos, TargetDefenseRadius, 'Enemy')
    if defenses then
        for _, unit in defenses do
            if not unit.Dead then
                total = total + UnitMass(unit)
            end
        end
    end
    return total
end

local function ClassifyTarget(unit)
    for _, class in TargetClasses do
        if EntityCategoryContains(class.cat, unit) then
            return class.name, class.value
        end
    end
    return nil, nil
end

-- Deterministic target pick: every finished Mark structure this AI army has
-- ever seen, scored value-first, defense-mass scan for the best 12 only, then
-- threat and path gates in score order.
--   budgetMass * threatFactor - defense mass the attacker tolerates near the target
--   pathLayer - NavUtils layer for reachability ('Land' for waves, 'Amphibious'
--   for experimentals)
-- Returns candidate { unit, pos, label, typeName, score, threat } or
-- nil + reason (no_target / high_threat / no_path).
function SelectTarget(brain, markArmies, fromPos, budgetMass, threatFactor, pathLayer)
    local candidates = {}
    for _, markIndex in markArmies do
        local markBrain = ArmyBrains[markIndex]
        if markBrain and not ArmyIsOutOfGame(markIndex) then
            local structures = markBrain:GetListOfUnits(categories.STRUCTURE - categories.WALL, false)
            if structures then
                for _, unit in structures do
                    if not unit.Dead and unit:GetFractionComplete() == 1
                            and SeenByArmy(unit, brain.Army) then
                        local typeName, value = ClassifyTarget(unit)
                        if typeName then
                            table.insert(candidates, {
                                unit = unit,
                                typeName = typeName,
                                value = value,
                                id = tostring(unit:GetEntityId()),
                            })
                        end
                    end
                end
            end
        end
    end
    if table.getn(candidates) == 0 then
        return nil, 'no_target'
    end

    table.sort(candidates, function(a, b)
        if a.value ~= b.value then
            return a.value > b.value
        end
        return a.id < b.id
    end)
    while table.getn(candidates) > 12 do
        table.remove(candidates)
    end

    for _, candidate in candidates do
        candidate.pos = candidate.unit:GetPosition()
        candidate.threat = ThreatMassAround(brain, candidate.pos)
        candidate.score = candidate.value - candidate.threat / 10
    end
    table.sort(candidates, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.id < b.id
    end)

    local reason = 'no_target'
    for _, candidate in candidates do
        local label = string.format("%s@%s",
            tostring(candidate.unit:GetBlueprint().BlueprintId), PosLabel(candidate.pos))
        LOG(string.format("FAF_AI_DIRECTOR: target score army=%d target=%s type=%s score=%d threat=%d",
            brain.Army, label, candidate.typeName, math.floor(candidate.score), math.floor(candidate.threat)))
        if candidate.threat >= budgetMass * threatFactor then
            reason = 'high_threat'
        elseif not NavUtils.CanPathTo(pathLayer, fromPos, candidate.pos) then
            if reason ~= 'high_threat' then
                reason = 'no_path'
            end
        else
            candidate.label = label
            return candidate, nil
        end
    end
    return nil, reason
end
