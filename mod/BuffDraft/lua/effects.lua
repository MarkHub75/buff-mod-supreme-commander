-- BuffDraft: sim-side buff effects. Every implemented buff is described as one or
-- more "parts". A part either goes through the stock FAF buff system (/lua/sim/Buff.lua
-- + BuffBlueprint, kind = "buff") or calls a safe per-instance engine API directly
-- (kind = "custom": weapon Change* methods used by BuffEffects themselves, or the
-- shield entity). No blueprints are mutated; everything is per unit instance.
--
-- Application phases:
--  * when = "create": applied from the Unit.OnCreate hook (the spot FAF applies AI
--    cheat buffs) - used for build-rate buffs so engineers/factories under
--    construction benefit immediately;
--  * when = "built": applied from the Unit.OnStopBeingBuilt hook, after the base
--    Unit.OnStopBeingBuilt created MyShield and the unit has its final health. The
--    pick-time sweep skips unfinished units for these; the hook catches them later.

local Buff = import('/lua/sim/Buff.lua')

--#region buff blueprints (buff-system parts)

BuffBlueprint {
    Name = 'BuffDraftEngineerBuildSpeed1',
    DisplayName = 'Engineer Rush',
    BuffType = 'BUFFDRAFTBUILDRATE',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ENGINEER',
    Affects = { BuildRate = { Add = 0, Mult = 5.0 } },
}

BuffBlueprint {
    Name = 'BuffDraftFactoryBuildSpeed1',
    DisplayName = 'Factory Build Speed I',
    BuffType = 'BUFFDRAFTFACTORYBUILDRATE',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'FACTORY',
    Affects = { BuildRate = { Add = 0, Mult = 2.0 } },
}

BuffBlueprint {
    Name = 'BuffDraftAirSpeed1',
    DisplayName = 'Air Speed I',
    BuffType = 'BUFFDRAFTAIRSPEED',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'AIR MOBILE',
    Affects = { MoveMult = { Mult = 1.5 } },
}

BuffBlueprint {
    Name = 'BuffDraftNavalArmor1',
    DisplayName = 'Naval Armor I',
    BuffType = 'BUFFDRAFTNAVALARMOR',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'NAVAL MOBILE',
    Affects = { MaxHealth = { Add = 0, Mult = 1.5 } }, -- fills current health by the same delta
}

BuffBlueprint {
    Name = 'BuffDraftExperimentalHealth1',
    DisplayName = 'Experimental Health I',
    BuffType = 'BUFFDRAFTEXPHEALTH',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'EXPERIMENTAL',
    Affects = { MaxHealth = { Add = 0, Mult = 1.3 } },
}

BuffBlueprint {
    Name = 'BuffDraftAcuRegen1',
    DisplayName = 'ACU Regeneration I',
    BuffType = 'BUFFDRAFTACUREGEN',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'COMMAND',
    -- Regen mults use MaxHp as base and must be < 1 (see Buff.lua), so use a flat add
    Affects = { Regen = { Add = 20 } },
}

BuffBlueprint {
    Name = 'BuffDraftRadarRadius1',
    DisplayName = 'Radar Radius I',
    BuffType = 'BUFFDRAFTRADAR',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'RADAR',
    Affects = { RadarRadius = { Add = 0, Mult = 1.3 } },
}

BuffBlueprint {
    Name = 'BuffDraftScoutVision1',
    DisplayName = 'Scout Vision I',
    BuffType = 'BUFFDRAFTVISION',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'SCOUT',
    Affects = { VisionRadius = { Add = 0, Mult = 1.3 } },
}

BuffBlueprint {
    Name = 'BuffDraftEcoOverclock1',
    DisplayName = 'Eco Overclock I',
    BuffType = 'BUFFDRAFTECO',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'STRUCTURE',
    -- same instance-level path adjacency bonuses use (unit.*ProdAdjMod)
    Affects = {
        EnergyProduction = { Mult = 1.5 },
        MassProduction = { Mult = 1.5 },
    },
}

--#endregion

--#region custom apply helpers (per-instance engine APIs)

local function UnitLabel(unit)
    return tostring(unit.UnitId) .. " entity " .. tostring(unit.EntityId)
end

-- Loop the unit's weapons, optionally filtered by blueprint RangeCategory
-- ('UWRC_AntiAir', 'UWRC_DirectFire', 'UWRC_IndirectFire', ...).
local function ForEachWeapon(unit, rangeCategory, fn)
    for i = 1, unit:GetWeaponCount() do
        local wep = unit:GetWeapon(i)
        local bp = wep:GetBlueprint()
        if (not rangeCategory) or bp.RangeCategory == rangeCategory then
            fn(wep, bp)
        end
    end
end

-- wep:ChangeDamage / ChangeRateOfFire / ChangeMaxRadius are the same engine calls
-- the stock BuffEffects use; values recomputed from the weapon blueprint, so one
-- application per unit is deterministic. Blueprint RateOfFire is shots per second.
local function WeaponDamageMult(rangeCategory, mult)
    return function(unit)
        ForEachWeapon(unit, rangeCategory, function(wep, bp)
            wep:ChangeDamage((bp.Damage or 0) * mult)
        end)
    end
end

local function WeaponRateOfFireMult(rangeCategory, mult)
    return function(unit)
        ForEachWeapon(unit, rangeCategory, function(wep, bp)
            wep:ChangeRateOfFire((bp.RateOfFire or 1) * mult)
        end)
    end
end

local function WeaponRangeMult(rangeCategory, mult)
    return function(unit)
        ForEachWeapon(unit, rangeCategory, function(wep, bp)
            wep:ChangeMaxRadius((bp.MaxRadius or 0) * mult)
        end)
    end
end

-- The shield is a separate entity (unit.MyShield, created by the base
-- Unit.OnStopBeingBuilt) with the standard entity health API.
local function ShieldMaxHealthMult(mult)
    return function(unit)
        local shield = unit.MyShield
        if not shield then
            LOG("FAF_BUFF_DRAFT: no shield instance on " .. UnitLabel(unit) .. ", nothing to buff")
            return
        end
        local oldMax = shield:GetMaxHealth()
        local ratio = shield:GetHealth() / oldMax
        local newMax = math.floor(oldMax * mult)
        shield:SetMaxHealth(newMax)
        shield:SetHealth(shield, math.floor(newMax * ratio))
    end
end

--#endregion

--#region buff specs

-- Each part: name (unique; blueprint name for kind="buff"), kind ("buff"|"custom"),
-- buffType (kind="buff" only), apply (kind="custom" only), category (sim category
-- object), when ("create"|"built"), active (armyIndex -> true, filled on pick).
local BuffSpecs = {
    engineer_build_speed_1 = { parts = { {
        name = 'BuffDraftEngineerBuildSpeed1', kind = 'buff', buffType = 'BUFFDRAFTBUILDRATE',
        category = categories.ENGINEER - categories.COMMAND, when = 'create',
    } } },
    factory_build_speed_1 = { parts = { {
        name = 'BuffDraftFactoryBuildSpeed1', kind = 'buff', buffType = 'BUFFDRAFTFACTORYBUILDRATE',
        category = categories.FACTORY, when = 'create',
    } } },
    air_speed_1 = { parts = { {
        name = 'BuffDraftAirSpeed1', kind = 'buff', buffType = 'BUFFDRAFTAIRSPEED',
        category = categories.AIR * categories.MOBILE, when = 'built',
    } } },
    naval_armor_1 = { parts = { {
        name = 'BuffDraftNavalArmor1', kind = 'buff', buffType = 'BUFFDRAFTNAVALARMOR',
        category = categories.NAVAL * categories.MOBILE, when = 'built',
    } } },
    experimentals_health_1 = { parts = { {
        name = 'BuffDraftExperimentalHealth1', kind = 'buff', buffType = 'BUFFDRAFTEXPHEALTH',
        category = categories.EXPERIMENTAL, when = 'built',
    } } },
    acu_regen_1 = { parts = { {
        name = 'BuffDraftAcuRegen1', kind = 'buff', buffType = 'BUFFDRAFTACUREGEN',
        category = categories.COMMAND, when = 'built',
    } } },
    eco_overclock_1 = { parts = { {
        name = 'BuffDraftEcoOverclock1', kind = 'buff', buffType = 'BUFFDRAFTECO',
        category = categories.STRUCTURE * (categories.MASSPRODUCTION + categories.ENERGYPRODUCTION),
        when = 'built',
    } } },
    -- "Radar and vision": radar radius on units that already have radar, vision on
    -- scouts. Restricting to RADAR avoids BuffEffects.RadarRadius granting radar to
    -- units that never had it (it calls InitIntel for non-radar units).
    radar_vision_1 = { parts = {
        {
            name = 'BuffDraftRadarRadius1', kind = 'buff', buffType = 'BUFFDRAFTRADAR',
            category = categories.RADAR, when = 'built',
        },
        {
            name = 'BuffDraftScoutVision1', kind = 'buff', buffType = 'BUFFDRAFTVISION',
            category = categories.SCOUT, when = 'built',
        },
    } },
    -- weapon buffs: custom per-weapon application so only the intended weapon type
    -- is changed (the stock Damage/RateOfFire/MaxRadius affects hit ALL weapons of
    -- the unit, which is wrong e.g. for cruisers with AA + surface missiles)
    anti_air_damage_1 = { parts = { {
        name = 'BuffDraftAntiAirDamage1', kind = 'custom',
        apply = WeaponDamageMult('UWRC_AntiAir', 1.5),
        category = categories.ANTIAIR, when = 'built',
    } } },
    land_rate_of_fire_1 = { parts = { {
        name = 'BuffDraftLandRateOfFire1', kind = 'custom',
        apply = WeaponRateOfFireMult('UWRC_DirectFire', 1.25),
        category = categories.LAND * categories.MOBILE, when = 'built',
    } } },
    artillery_range_1 = { parts = { {
        name = 'BuffDraftArtilleryRange1', kind = 'custom',
        apply = WeaponRangeMult('UWRC_IndirectFire', 1.25),
        category = categories.ARTILLERY, when = 'built',
    } } },
    tactical_range_1 = { parts = { {
        name = 'BuffDraftTacticalRange1', kind = 'custom',
        apply = WeaponRangeMult(nil, 1.25), -- TML structures have a single weapon
        category = categories.TACTICALMISSILEPLATFORM, when = 'built',
    } } },
    shield_health_1 = { parts = { {
        name = 'BuffDraftShieldHealth1', kind = 'custom',
        apply = ShieldMaxHealthMult(1.5),
        category = categories.STRUCTURE * categories.SHIELD, when = 'built',
    } } },
    mobile_shields_1 = { parts = { {
        name = 'BuffDraftMobileShields1', kind = 'custom',
        apply = ShieldMaxHealthMult(1.5),
        category = categories.MOBILE * categories.SHIELD, when = 'built',
    } } },
}

-- initialize per-part activation state
for _, spec in BuffSpecs do
    for _, part in spec.parts do
        part.active = {}
    end
end

local NotImplementedReasons = {
    reclaim_bonus_1 = "reclaim yield lives on props / the engine reclaim command, no per-unit"
        .. " instance API; scaling build rate instead would also change build speed",
}

--#endregion

--#region generic application

-- Buff.HasBuff indexes BuffTable[BuffType] without a nil check and errors on units
-- that never had a buff of this type, so do the double-apply check ourselves.
local function HasBuffApplied(unit, part)
    if part.kind == 'buff' then
        local buffs = unit.Buffs
        if (not buffs) or (not buffs.BuffTable) then
            return false
        end
        local byType = buffs.BuffTable[part.buffType]
        return byType and byType[part.name] and true or false
    end
    -- custom parts: own marker table on the unit instance
    local applied = unit.BuffDraftApplied
    return applied and applied[part.name] and true or false
end

local function ApplyPartToUnit(buffId, part, unit)
    if HasBuffApplied(unit, part) then
        LOG("FAF_BUFF_DRAFT: " .. buffId .. " skipped already applied " .. UnitLabel(unit))
        return
    end
    if part.kind == 'buff' then
        Buff.ApplyBuff(unit, part.name)
    else
        unit.BuffDraftApplied = unit.BuffDraftApplied or {}
        unit.BuffDraftApplied[part.name] = true
        part.apply(unit)
    end
    LOG("FAF_BUFF_DRAFT: " .. buffId .. " applied to unit " .. UnitLabel(unit))
end

local function ArmiesToString(armies)
    local ids = {}
    for _, index in armies do
        table.insert(ids, tostring(index))
    end
    return table.concat(ids, ",")
end

--- Called from draft.lua when a side's pick is resolved. `armies` is the side's
--- army index list from slot detection.
function ApplyPickedBuff(sideName, armies, buffId)
    local spec = BuffSpecs[buffId]
    if not spec then
        LOG("FAF_BUFF_DRAFT: " .. tostring(buffId) .. " not implemented: "
            .. (NotImplementedReasons[buffId] or "no safe instance-level API identified"))
        return
    end

    LOG("FAF_BUFF_DRAFT: applying " .. buffId .. " to armies: " .. ArmiesToString(armies))

    for _, part in spec.parts do
        -- future units: mark the armies so the Unit hooks buff new matching units
        for _, armyIndex in armies do
            part.active[armyIndex] = true
        end

        -- existing units; "built"-phase parts skip unfinished units, the
        -- OnStopBeingBuilt hook picks those up on completion
        for _, armyIndex in armies do
            local brain = ArmyBrains[armyIndex]
            if brain then
                for _, unit in brain:GetListOfUnits(part.category, false, false) or {} do
                    if not unit.Dead then
                        if part.when == 'built' and unit:GetFractionComplete() < 1 then
                            -- caught later by OnUnitBuilt
                        else
                            ApplyPartToUnit(buffId, part, unit)
                        end
                    end
                end
            end
        end
    end

    LOG("FAF_BUFF_DRAFT: " .. buffId .. " future units hook active")
end

local function ApplyActivePartsToUnit(unit, when)
    for buffId, spec in BuffSpecs do
        for _, part in spec.parts do
            if part.when == when and part.active[unit.Army]
                and EntityCategoryContains(part.category, unit) then
                ApplyPartToUnit(buffId, part, unit)
            end
        end
    end
end

--- Called from the /hook/lua/sim/Unit.lua OnCreate hook for every new unit.
function OnUnitCreated(unit)
    ApplyActivePartsToUnit(unit, 'create')
end

--- Called from the /hook/lua/sim/Unit.lua OnStopBeingBuilt hook (after the base
--- implementation ran, so MyShield and final health already exist).
function OnUnitBuilt(unit)
    ApplyActivePartsToUnit(unit, 'built')
end

--#endregion
