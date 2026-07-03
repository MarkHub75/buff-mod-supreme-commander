-- BuffDraft MVP 4: sim-side buff effects. First real buff: engineer_build_speed_1
-- ("Engineer Rush"). Uses the stock FAF buff system (/lua/sim/Buff.lua + the global
-- BuffBlueprint registry) — same pattern as BaseManagerEngineerDefaultBuildRate in
-- /lua/sim/OpBuffDefinitions.lua and the AI cheat buffs in /lua/ai/aiutilities.lua.

local Buff = import('/lua/sim/Buff.lua')

local ENGINEER_BUFF_NAME = 'BuffDraftEngineerBuildSpeed1'
local ENGINEER_BUFF_TYPE = 'BUFFDRAFTBUILDRATE'

-- FAF idiom for "engineers without the ACU" (the ACU carries the ENGINEER category
-- too, see lua/platoon.lua: GetListOfUnits(categories.ENGINEER - categories.COMMAND)).
local EngineerCategory = categories.ENGINEER - categories.COMMAND

BuffBlueprint {
    Name = ENGINEER_BUFF_NAME,
    DisplayName = 'Engineer Rush',
    BuffType = ENGINEER_BUFF_TYPE,
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ENGINEER',
    Affects = {
        BuildRate = {
            Add = 0,
            Mult = 5.0, -- engineers build at 500% of their blueprint build rate
        },
    },
}

-- armyIndex -> true for armies whose side picked engineer_build_speed_1. Import
-- caching keeps this table alive for the whole sim session; the /hook/lua/sim/Unit.lua
-- OnCreate hook reads it for every newly created unit.
local EngineerBuffArmies = {}

local function UnitLabel(unit)
    return tostring(unit.UnitId) .. " entity " .. tostring(unit.EntityId)
end

-- Buff.HasBuff indexes BuffTable[BuffType] without a nil check and errors on units
-- that never had a buff of this type, so do the double-apply check ourselves.
local function HasEngineerBuff(unit)
    local buffs = unit.Buffs
    if (not buffs) or (not buffs.BuffTable) then
        return false
    end
    local byType = buffs.BuffTable[ENGINEER_BUFF_TYPE]
    return byType and byType[ENGINEER_BUFF_NAME] and true or false
end

local function ApplyEngineerBuffToUnit(unit)
    if HasEngineerBuff(unit) then
        LOG("FAF_BUFF_DRAFT: engineer buff skipped already applied " .. UnitLabel(unit))
        return
    end
    Buff.ApplyBuff(unit, ENGINEER_BUFF_NAME)
    LOG("FAF_BUFF_DRAFT: engineer buff applied to unit " .. UnitLabel(unit))
end

local function ActivateEngineerBuildSpeed(armies)
    local ids = {}
    for _, armyIndex in armies do
        table.insert(ids, tostring(armyIndex))
    end
    LOG("FAF_BUFF_DRAFT: applying engineer_build_speed_1 to armies: " .. table.concat(ids, ","))

    -- future units: mark the armies so the Unit OnCreate hook buffs new engineers
    for _, armyIndex in armies do
        EngineerBuffArmies[armyIndex] = true
    end
    LOG("FAF_BUFF_DRAFT: engineer buff future units hook active")

    -- existing units, including engineers still under construction
    for _, armyIndex in armies do
        local brain = ArmyBrains[armyIndex]
        if brain then
            for _, unit in brain:GetListOfUnits(EngineerCategory, false, false) or {} do
                if not unit.Dead then
                    ApplyEngineerBuffToUnit(unit)
                end
            end
        end
    end
end

--- Called from draft.lua when a side auto-picks a buff. `armies` is the side's
--- army index list from slot detection.
function ApplyPickedBuff(sideName, armies, buffId)
    if buffId == "engineer_build_speed_1" then
        ActivateEngineerBuildSpeed(armies)
    else
        LOG("FAF_BUFF_DRAFT: buff " .. tostring(buffId) .. " not implemented yet")
    end
end

--- Called from the /hook/lua/sim/Unit.lua OnCreate hook for every new unit.
function OnUnitCreated(unit)
    if not EngineerBuffArmies[unit.Army] then
        return
    end
    if not EntityCategoryContains(EngineerCategory, unit) then
        return
    end
    ApplyEngineerBuffToUnit(unit)
end
