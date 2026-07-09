-- BuffDraft AI control (sim side): the "Take AI units" tool for the owner
-- player. The owner clicks a map point; every allied AI land unit around it is
-- transferred to the owner's army through the stock FAF transfer path -
-- SimUtils.TransferUnitsOwnership, the same function the diplomacy "give units"
-- feature uses (SimUtils.GiveUnitsToPlayer), so veterancy/upgrades/silo ammo
-- survive and no blueprint or army state is touched by hand.
--
-- The UI sends ONLY a point; everything is validated here sim-side:
-- sender is the configured owner (nickname re-checked against the brain),
-- source units belong to allied non-civilian AI armies (never Mark - he is an
-- enemy and fails IsAlly; never human allies; never the sender's own units),
-- ACUs and experimentals are excluded by config, one click is capped.
--
-- ISOLATION: the tool lives in lua/ai_control/; outside touch points are the
-- AIControl*/EnableAIControl config knobs, one callback in
-- hook/lua/SimCallbacks.lua and one button in ui/admin.lua. Deleting this
-- folder + EnableAIControl = false removes it (the callback and button bail out).

local BuffDraftConfig = import('/mods/BuffDraft/lua/config.lua')

local function Knob(name, default)
    local value = BuffDraftConfig[name]
    if value == nil then
        return default
    end
    return value
end

local EnableAIControl = Knob('EnableAIControl', false)
local TakeRadius = Knob('AIControlTakeRadius', 30)
local MaxUnitsPerTake = Knob('AIControlMaxUnitsPerTake', 60)
local AllowACU = Knob('AIControlAllowACU', false)
local IncludeExperimentals = Knob('AIControlIncludeExperimentals', false)
local OwnerNickname = Knob('AdminOwnerNickname', "")

-- what a click may take: mobile land units; INSIGNIFICANTUNIT never transfers
-- anyway (SimUtils filters it), excluded here so it is not counted as skipped.
-- With experimentals enabled, mobile experimentals of ANY layer are included
-- (Czar/Tempest too, not just land ones). COMMAND is subtracted last: ACU stays
-- untakeable regardless (SCUs are SUBCOMMANDER, they transfer fine).
local function BuildTakeCategory()
    local cat = categories.LAND * categories.MOBILE - categories.INSIGNIFICANTUNIT
    if IncludeExperimentals then
        cat = cat + categories.EXPERIMENTAL * categories.MOBILE
    else
        cat = cat - categories.EXPERIMENTAL
    end
    if not AllowACU then
        cat = cat - categories.COMMAND
    end
    return cat
end
local TakeCat = BuildTakeCategory()

local function UnitLabel(unit)
    return string.format("%s#%s", tostring(unit:GetBlueprint().BlueprintId),
        tostring(unit:GetEntityId()))
end

-- UI payload is raw: validate types, NaN and map bounds before use
local function ValidPoint(data)
    if type(data) ~= 'table' then
        return nil
    end
    local x, z = data.x, data.z
    if type(x) ~= 'number' or type(z) ~= 'number' or x ~= x or z ~= z then
        return nil
    end
    local size = ScenarioInfo.size
    if not size or x < 0 or z < 0 or x > size[1] or z > size[2] then
        return nil
    end
    return { x, GetSurfaceHeight(x, z), z }
end

-- nil when the unit may be taken, otherwise the skip reason.
-- Callers must handle Dead before asking for a label: entity methods
-- (GetBlueprint/GetEntityId) are not safe on a destroyed unit.
local function SkipReason(unit, senderArmy)
    if unit.Dead then
        return 'dead'
    end
    local army = unit.Army
    local brain = ArmyBrains[army]
    if not brain or brain.Civilian then
        return 'civilian'
    end
    if brain.BrainType ~= 'AI' then
        return 'human_ally'
    end
    if not IsAlly(senderArmy, army) then
        return 'not_allied'
    end
    if unit:GetFractionComplete() < 1 then
        return 'under_construction'
    end
    if unit:IsUnitState('Attached') then
        return 'attached'
    end
    return nil
end

--- Sim entry point, called from the BuffDraftTakeAIUnits callback with the
--- command-source army (never UI data) and the raw clicked point.
function TakeAIUnitsAtPoint(senderArmy, data)
    if not EnableAIControl then
        LOG("FAF_AI_CONTROL: disabled by config")
        return
    end
    local senderBrain = ArmyBrains[senderArmy]
    if not senderBrain or senderBrain.BrainType ~= 'Human' or senderBrain.Civilian then
        LOG("FAF_AI_CONTROL: request rejected army=" .. tostring(senderArmy) .. " reason=not_human")
        return
    end
    if OwnerNickname ~= "" and senderBrain.Nickname ~= OwnerNickname then
        LOG("FAF_AI_CONTROL: request rejected army=" .. tostring(senderArmy)
            .. " nickname=" .. tostring(senderBrain.Nickname) .. " reason=not_owner")
        return
    end
    local pos = ValidPoint(data)
    if not pos then
        LOG("FAF_AI_CONTROL: request rejected army=" .. tostring(senderArmy) .. " reason=bad_point")
        return
    end

    local candidates = {}
    local skipped = 0
    local around = senderBrain:GetUnitsAroundPoint(TakeCat, pos, TakeRadius, 'Ally')
    for _, unit in around or {} do
        if unit.Army ~= senderArmy then -- own units are not part of the request
            local reason = SkipReason(unit, senderArmy)
            if reason == 'dead' then
                skipped = skipped + 1 -- no label: entity methods are unsafe on dead units
            elseif reason then
                skipped = skipped + 1
                LOG(string.format("FAF_AI_CONTROL: skipped unit=%s reason=%s", UnitLabel(unit), reason))
            else
                local unitPos = unit:GetPosition()
                table.insert(candidates, {
                    unit = unit,
                    dist = VDist2(unitPos[1], unitPos[3], pos[1], pos[3]),
                    id = tostring(unit:GetEntityId()),
                })
            end
        end
    end

    -- deterministic: nearest to the click first, entity id as the tie break
    table.sort(candidates, function(a, b)
        if a.dist ~= b.dist then
            return a.dist < b.dist
        end
        return a.id < b.id
    end)
    local overCap = table.getn(candidates) - MaxUnitsPerTake
    if overCap > 0 then
        skipped = skipped + overCap
        LOG(string.format("FAF_AI_CONTROL: skipped %d units reason=over_cap (max %d per take)",
            overCap, MaxUnitsPerTake))
        while table.getn(candidates) > MaxUnitsPerTake do
            table.remove(candidates)
        end
    end

    local count = table.getn(candidates)
    LOG(string.format("FAF_AI_CONTROL: request take army=%d at=%d,%d radius=%d take=%d skipped=%d",
        senderArmy, pos[1], pos[3], TakeRadius, count, skipped))
    if count == 0 then
        return
    end

    local units = {}
    for _, candidate in candidates do
        table.insert(units, candidate.unit)
        LOG(string.format("FAF_AI_CONTROL: transferred unit=%s from army=%d to army=%d",
            UnitLabel(candidate.unit), candidate.unit.Army, senderArmy))
    end
    local newUnits = import('/lua/SimUtils.lua').TransferUnitsOwnership(units, senderArmy)
    local got = (newUnits and table.getn(newUnits)) or 0
    LOG(string.format("FAF_AI_CONTROL: transfer done army=%d requested=%d transferred=%d",
        senderArmy, count, got))
    if got < count then
        WARN("FAF_AI_CONTROL: transfer filtered " .. tostring(count - got)
            .. " units (see SimUtils.TransferUnitsOwnership restrictions)")
    end
end
