-- BuffDraft AI control (sim side): the "Take AI units" tool for the owner
-- player. The owner clicks an allied AI unit/structure; that exact entity is
-- transferred to the owner's army through the stock FAF transfer path -
-- SimUtils.TransferUnitsOwnership, the same function the diplomacy "give units"
-- feature uses (SimUtils.GiveUnitsToPlayer), so veterancy/upgrades/silo ammo
-- survive and no blueprint or army state is touched by hand.
--
-- The UI sends ONLY an entity id; everything is validated here sim-side:
-- sender is the configured owner (nickname re-checked against the brain),
-- source entities belong to allied non-civilian AI armies and may be land,
-- naval, air or structures (never Mark - he is an enemy and fails IsAlly; never
-- human allies; never the sender's own units).
-- ACUs and experimentals still obey the config gates.
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
local AllowACU = Knob('AIControlAllowACU', false)
local IncludeExperimentals = Knob('AIControlIncludeExperimentals', false)
local OwnerNickname = Knob('AdminOwnerNickname', "")
local TransferableCat = categories.ALLUNITS - categories.INSIGNIFICANTUNIT

local function UnitLabel(unit)
    return string.format("%s#%s", tostring(unit:GetBlueprint().BlueprintId),
        tostring(unit:GetEntityId()))
end

-- UI payload is raw: validate the id, then resolve to the current sim entity.
local function ResolveTarget(data)
    if type(data) ~= 'table' then
        return nil, 'bad_payload'
    end
    local id = data.entityId
    if type(id) ~= 'number' and type(id) ~= 'string' then
        return nil, 'missing_entity'
    end
    if type(id) == 'string' then
        id = tonumber(id)
        if not id then
            return nil, 'bad_entity'
        end
    end
    local target = GetEntityById(id)
    if not target or not IsEntity(target) then
        return nil, 'entity_not_found'
    end
    if type(target.Army) ~= 'number' or not target.GetBlueprint or not target.GetEntityId
        or not target.GetFractionComplete or not target.IsUnitState then
        return nil, 'not_unit'
    end
    if type(data.blueprintId) == 'string' then
        local bp = target:GetBlueprint()
        if (not bp) or bp.BlueprintId ~= data.blueprintId then
            return nil, 'entity_mismatch'
        end
    end
    return target, nil
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
    if not EntityCategoryContains(TransferableCat, unit) then
        return 'not_transferable'
    end
    if (not AllowACU) and EntityCategoryContains(categories.COMMAND, unit) then
        return 'acu'
    end
    if (not IncludeExperimentals) and EntityCategoryContains(categories.EXPERIMENTAL, unit) then
        return 'experimental'
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
--- command-source army (never UI data) and the raw clicked entity id.
function TakeAIUnitsAtPoint(senderArmy, data)
    if not EnableAIControl then
        LOG("FAF_BUFF_DRAFT_AI_CONTROL: disabled by config")
        return
    end
    local senderBrain = ArmyBrains[senderArmy]
    if not senderBrain or senderBrain.BrainType ~= 'Human' or senderBrain.Civilian then
        LOG("FAF_BUFF_DRAFT_AI_CONTROL: request rejected army=" .. tostring(senderArmy) .. " reason=not_human")
        return
    end
    if OwnerNickname ~= "" and senderBrain.Nickname ~= OwnerNickname then
        LOG("FAF_BUFF_DRAFT_AI_CONTROL: request rejected army=" .. tostring(senderArmy)
            .. " nickname=" .. tostring(senderBrain.Nickname) .. " reason=not_owner")
        return
    end

    local target, resolveReason = ResolveTarget(data)
    if not target then
        LOG("FAF_BUFF_DRAFT_AI_CONTROL: request rejected army=" .. tostring(senderArmy)
            .. " reason=" .. tostring(resolveReason)
            .. " entity=" .. tostring(data and data.entityId))
        return
    end

    if target.Dead then
        LOG("FAF_BUFF_DRAFT_AI_CONTROL: request skipped unit="
            .. tostring(data.entityId) .. " reason=dead")
        return
    end

    if target.Army == senderArmy then
        LOG("FAF_BUFF_DRAFT_AI_CONTROL: request skipped own unit=" .. UnitLabel(target))
        return
    end

    local reason = SkipReason(target, senderArmy)
    if reason then
        LOG(string.format("FAF_BUFF_DRAFT_AI_CONTROL: request skipped unit=%s reason=%s",
            UnitLabel(target), reason))
        return
    end

    local fromArmy = target.Army
    LOG(string.format("FAF_BUFF_DRAFT_AI_CONTROL: request take unit=%s from army=%d to army=%d",
        UnitLabel(target), fromArmy, senderArmy))

    local newUnits = import('/lua/SimUtils.lua').TransferUnitsOwnership({ target }, senderArmy)
    local got = (newUnits and table.getn(newUnits)) or 0
    LOG(string.format("FAF_BUFF_DRAFT_AI_CONTROL: transfer done army=%d requested=%d transferred=%d",
        senderArmy, 1, got))
    if got < 1 then
        WARN("FAF_BUFF_DRAFT_AI_CONTROL: transfer filtered target unit (see SimUtils.TransferUnitsOwnership restrictions)")
    end
end
