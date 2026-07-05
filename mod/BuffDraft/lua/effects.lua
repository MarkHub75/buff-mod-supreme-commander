-- BuffDraft: sim-side buff effects. Every implemented buff is described as one or
-- more "parts". A part either goes through the stock FAF buff system (/lua/sim/Buff.lua
-- + BuffBlueprint, kind = "buff") or calls a safe per-instance engine API directly
-- (kind = "custom": weapon Change*/AddDamageRadiusMod methods used by BuffEffects
-- themselves, or the shield entity). Some buffs additionally have an army-level
-- apply (spawn threads, kill-bounty flags). No blueprints are mutated; everything
-- is per unit instance or per army brain.
--
-- Application phases:
--  * when = "create": applied from the Unit.OnCreate hook (the spot FAF applies AI
--    cheat buffs) - used for build-rate buffs so engineers/factories under
--    construction benefit immediately;
--  * when = "built": applied from the Unit.OnStopBeingBuilt hook, after the base
--    Unit.OnStopBeingBuilt created MyShield and the unit has its final health. The
--    pick-time sweep skips unfinished units for these; the hook catches them later.
--  * futureOnly parts skip the pick-time sweep entirely (only units built after
--    the pick get them - used by rapid_deployment_1).

local Buff = import('/lua/sim/Buff.lua')

--#region tuning constants
-- Tuned for the 10-minute draft cadence: one pick should feel significant.
-- Keep the `effect` strings in buffs.lua in sync with these values.

local ENGINEER_BUILD_RATE_MULT = 5.0
local FACTORY_BUILD_RATE_MULT = 3.0
local AIR_SPEED_MULT = 2.0
local NAVAL_ARMOR_MULT = 2.5
local EXPERIMENTAL_HEALTH_MULT = 2.0
local ACU_REGEN_ADD = 60
local RADAR_RADIUS_MULT = 2.0
local SCOUT_VISION_MULT = 2.0
local ECO_PRODUCTION_MULT = 2.5
local ANTIAIR_DAMAGE_MULT = 2.5
local LAND_ROF_MULT = 2.0
local ARTILLERY_RANGE_MULT = 1.5
local TACTICAL_RANGE_MULT = 2.0
local SHIELD_HEALTH_MULT = 2.0
local MOBILE_SHIELD_HEALTH_MULT = 2.0

local DRONE_FOUNDRY_INTERVAL = 45 -- game seconds between spawn waves
local DRONE_FOUNDRY_MAX_PER_WAVE = 4 -- at most this many factories spawn per wave
local ENGINEER_SWARM_INTERVAL = 60
local ENGINEER_SWARM_MAX_PER_WAVE = 2
local EMERGENCY_FAB_BUILD_MULT = 3.0
local OVERCHARGED_SHIELD_MULT = 2.5
local NAPALM_RADIUS_ADD = 1.0 -- flat damage-radius add, world units
local TELEPORT_SPEED_MULT = 2.0
local NANO_REGEN_ADD = 5
local EXP_DISCOUNT_BUILD_MULT = 2.5
local RAPID_SPEED_MULT = 2.0
local RAPID_DURATION = 60 -- seconds (buff system Duration is in game seconds)
local FORTRESS_HP_MULT = 3.0
local FORTRESS_SPEED_MULT = 0.85
local HUNTER_VISION_MULT = 2.0
local HUNTER_RADAR_MULT = 2.0
local HUNTER_SPEED_MULT = 1.5
local BLACK_MARKET_MASS_FRACTION = 0.1
local BLACK_MARKET_ENERGY_FRACTION = 0.1
local TAC_SUPREMACY_RANGE_MULT = 3.0
local TAC_SUPREMACY_BUILD_MULT = 2.0
local AIR_SUP_SPEED_MULT = 2.0
local AIR_SUP_DAMAGE_MULT = 1.5
local AIR_SUP_HP_MULT = 0.75
local DREADNOUGHT_HP_MULT = 3.0
local DREADNOUGHT_RANGE_MULT = 1.5
local OMNISCIENCE_OMNI_MULT = 3.0
local OMNISCIENCE_RADAR_MULT = 2.5

-- faction index (1 UEF, 2 Aeon, 3 Cybran, 4 Seraphim) -> blueprint id
local DRONE_TANK_BPS = { 'uel0201', 'ual0201', 'url0107', 'xsl0201' }
local SWARM_ENGINEER_BPS = { 'uel0105', 'ual0105', 'url0105', 'xsl0105' }

--#endregion

--#region buff blueprints (buff-system parts)
-- ApplyBuff re-checks EntityCategory via ParseEntityCategory and silently skips
-- non-matching units, so keep it broad ('ALLUNITS') where the precise targeting
-- is done by the part's sim category object.

BuffBlueprint {
    Name = 'BuffDraftEngineerBuildSpeed1',
    DisplayName = 'Engineer Rush',
    BuffType = 'BUFFDRAFTBUILDRATE',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ENGINEER',
    Affects = { BuildRate = { Add = 0, Mult = ENGINEER_BUILD_RATE_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftFactoryBuildSpeed1',
    DisplayName = 'Factory Build Speed I',
    BuffType = 'BUFFDRAFTFACTORYBUILDRATE',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'FACTORY',
    Affects = { BuildRate = { Add = 0, Mult = FACTORY_BUILD_RATE_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftAirSpeed1',
    DisplayName = 'Air Speed I',
    BuffType = 'BUFFDRAFTAIRSPEED',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'AIR MOBILE',
    Affects = { MoveMult = { Mult = AIR_SPEED_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftNavalArmor1',
    DisplayName = 'Naval Armor I',
    BuffType = 'BUFFDRAFTNAVALARMOR',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'NAVAL MOBILE',
    Affects = { MaxHealth = { Add = 0, Mult = NAVAL_ARMOR_MULT } }, -- fills current health by the same delta
}

BuffBlueprint {
    Name = 'BuffDraftExperimentalHealth1',
    DisplayName = 'Experimental Health I',
    BuffType = 'BUFFDRAFTEXPHEALTH',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'EXPERIMENTAL',
    Affects = { MaxHealth = { Add = 0, Mult = EXPERIMENTAL_HEALTH_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftAcuRegen1',
    DisplayName = 'ACU Regeneration I',
    BuffType = 'BUFFDRAFTACUREGEN',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'COMMAND',
    -- Regen mults use MaxHp as base and must be < 1 (see Buff.lua), so use a flat add
    Affects = { Regen = { Add = ACU_REGEN_ADD } },
}

BuffBlueprint {
    Name = 'BuffDraftRadarRadius1',
    DisplayName = 'Radar Radius I',
    BuffType = 'BUFFDRAFTRADAR',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'RADAR',
    Affects = { RadarRadius = { Add = 0, Mult = RADAR_RADIUS_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftScoutVision1',
    DisplayName = 'Scout Vision I',
    BuffType = 'BUFFDRAFTVISION',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'SCOUT',
    Affects = { VisionRadius = { Add = 0, Mult = SCOUT_VISION_MULT } },
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
        EnergyProduction = { Mult = ECO_PRODUCTION_MULT },
        MassProduction = { Mult = ECO_PRODUCTION_MULT },
    },
}

-- conditional build-rate buffs, applied on OnStartBuild / removed on OnStopBuild
BuffBlueprint {
    Name = 'BuffDraftEmergencyFab1',
    DisplayName = 'Emergency Fabrication',
    BuffType = 'BUFFDRAFTEMERGENCYFAB',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ENGINEER',
    Affects = { BuildRate = { Add = 0, Mult = EMERGENCY_FAB_BUILD_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftExpDiscount1',
    DisplayName = 'Experimental Assembly',
    BuffType = 'BUFFDRAFTEXPDISCOUNT',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ALLUNITS',
    Affects = { BuildRate = { Add = 0, Mult = EXP_DISCOUNT_BUILD_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftTeleportDoctrine1',
    DisplayName = 'Teleport Doctrine',
    BuffType = 'BUFFDRAFTTELEPORT',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ALLUNITS',
    Affects = { MoveMult = { Mult = TELEPORT_SPEED_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftNanoSwarm1',
    DisplayName = 'Nano Swarm',
    BuffType = 'BUFFDRAFTNANOSWARM',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ALLUNITS',
    Affects = { Regen = { Add = NANO_REGEN_ADD } },
}

BuffBlueprint {
    Name = 'BuffDraftRapidDeploy1',
    DisplayName = 'Rapid Deployment',
    BuffType = 'BUFFDRAFTRAPIDDEPLOY',
    Stacks = 'IGNORE',
    Duration = RAPID_DURATION, -- timed buff: Buff.lua removes it after this many game seconds
    EntityCategory = 'MOBILE',
    Affects = { MoveMult = { Mult = RAPID_SPEED_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftFortressHP1',
    DisplayName = 'Fortress Protocol',
    BuffType = 'BUFFDRAFTFORTRESSHP',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'STRUCTURE',
    Affects = { MaxHealth = { Add = 0, Mult = FORTRESS_HP_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftFortressSlow1',
    DisplayName = 'Fortress Protocol (mobility cost)',
    BuffType = 'BUFFDRAFTFORTRESSSLOW',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'MOBILE',
    Affects = { MoveMult = { Mult = FORTRESS_SPEED_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftHunterVision1',
    DisplayName = 'Hunter Protocol (vision)',
    BuffType = 'BUFFDRAFTHUNTERVISION',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'MOBILE',
    Affects = { VisionRadius = { Add = 0, Mult = HUNTER_VISION_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftHunterRadar1',
    DisplayName = 'Hunter Protocol (radar)',
    BuffType = 'BUFFDRAFTHUNTERRADAR',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ALLUNITS',
    Affects = { RadarRadius = { Add = 0, Mult = HUNTER_RADAR_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftHunterSpeed1',
    DisplayName = 'Hunter Protocol (speed)',
    BuffType = 'BUFFDRAFTHUNTERSPEED',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'MOBILE',
    Affects = { MoveMult = { Mult = HUNTER_SPEED_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftTacSupremacyBuild1',
    DisplayName = 'Tactical Supremacy (missile build)',
    BuffType = 'BUFFDRAFTTACBUILD',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ALLUNITS',
    Affects = { BuildRate = { Add = 0, Mult = TAC_SUPREMACY_BUILD_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftAirSupSpeed1',
    DisplayName = 'Air Superiority (speed)',
    BuffType = 'BUFFDRAFTAIRSUPSPEED',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'AIR MOBILE',
    Affects = { MoveMult = { Mult = AIR_SUP_SPEED_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftAirSupHP1',
    DisplayName = 'Air Superiority (armor cost)',
    BuffType = 'BUFFDRAFTAIRSUPHP',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'AIR MOBILE',
    Affects = { MaxHealth = { Add = 0, Mult = AIR_SUP_HP_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftDreadnoughtHP1',
    DisplayName = 'Naval Dreadnoughts',
    BuffType = 'BUFFDRAFTDREADNOUGHTHP',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'NAVAL MOBILE',
    Affects = { MaxHealth = { Add = 0, Mult = DREADNOUGHT_HP_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftOmniRadius1',
    DisplayName = 'Radar Omniscience (omni)',
    BuffType = 'BUFFDRAFTOMNI',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ALLUNITS',
    Affects = { OmniRadius = { Add = 0, Mult = OMNISCIENCE_OMNI_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftOmniRadarRadius1',
    DisplayName = 'Radar Omniscience (radar)',
    BuffType = 'BUFFDRAFTOMNIRADAR',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ALLUNITS',
    Affects = { RadarRadius = { Add = 0, Mult = OMNISCIENCE_RADAR_MULT } },
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
            fn(wep, bp, i)
        end
    end
end

-- Several different buffs may scale the same weapon stat (e.g. tactical_range_1 and
-- tactical_supremacy_1), so track the combined multiplier per unit + weapon + stat
-- and always recompute from the blueprint value: deterministic, stacks correctly,
-- and a repeat application of the same buff is already blocked by the part guard.
local function CombinedWeaponMult(unit, statKey, index, mult)
    local key = statKey .. tostring(index)
    unit.BuffDraftWeaponMults = unit.BuffDraftWeaponMults or {}
    local combined = (unit.BuffDraftWeaponMults[key] or 1) * mult
    unit.BuffDraftWeaponMults[key] = combined
    return combined
end

-- wep:ChangeDamage / ChangeRateOfFire / ChangeMaxRadius are the same engine calls
-- the stock BuffEffects use. Blueprint RateOfFire is shots per second.
local function WeaponDamageMult(rangeCategory, mult)
    return function(unit)
        ForEachWeapon(unit, rangeCategory, function(wep, bp, i)
            wep:ChangeDamage((bp.Damage or 0) * CombinedWeaponMult(unit, 'dmg', i, mult))
        end)
    end
end

local function WeaponRateOfFireMult(rangeCategory, mult)
    return function(unit)
        ForEachWeapon(unit, rangeCategory, function(wep, bp, i)
            wep:ChangeRateOfFire((bp.RateOfFire or 1) * CombinedWeaponMult(unit, 'rof', i, mult))
        end)
    end
end

local function WeaponRangeMult(rangeCategory, mult)
    return function(unit)
        ForEachWeapon(unit, rangeCategory, function(wep, bp, i)
            wep:ChangeMaxRadius((bp.MaxRadius or 0) * CombinedWeaponMult(unit, 'rng', i, mult))
        end)
    end
end

-- wep:AddDamageRadiusMod adds a flat amount to the DamageRadius of the weapon's
-- damage table (per weapon instance, cumulative by design - the part guard keeps
-- it to one application per unit per buff).
local function WeaponDamageRadiusAdd(rangeCategory, add)
    return function(unit)
        ForEachWeapon(unit, rangeCategory, function(wep, bp, i)
            wep:AddDamageRadiusMod(add)
        end)
    end
end

-- The shield is a separate entity (unit.MyShield, created by the base
-- Unit.OnStopBeingBuilt) with the standard entity health API. Recomputes from the
-- current max, so different shield buffs stack multiplicatively.
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

--#region army-level effects (spawn threads, kill bounty)

-- armies with black_market_economy_1 active; consulted by the OnKilledUnit hook
local BlackMarketArmies = {}

local function FactionBlueprint(brain, bpByFaction)
    return bpByFaction[brain:GetFactionIndex()] or bpByFaction[1]
end

-- Periodically spawns free units next to finished land factories. CreateUnitHPR is
-- the standard sim spawn call (scenario scripts, pods, external factories).
local function FactorySpawnThread(buffId, armyIndex, bpByFaction, interval, maxPerWave)
    local brain = ArmyBrains[armyIndex]
    if not brain then
        return
    end
    local bpId = FactionBlueprint(brain, bpByFaction)
    LOG("FAF_BUFF_DRAFT: " .. buffId .. " spawn thread started army=" .. tostring(armyIndex)
        .. " bp=" .. tostring(bpId) .. " interval=" .. tostring(interval))
    while ArmyBrains[armyIndex] do
        WaitSeconds(interval)
        brain = ArmyBrains[armyIndex]
        if not brain then
            break
        end
        local factories = brain:GetListOfUnits(
            categories.STRUCTURE * categories.FACTORY * categories.LAND, false, false) or {}
        local spawned = 0
        for _, fac in factories do
            if spawned >= maxPerWave then
                break
            end
            if (not fac.Dead) and fac:GetFractionComplete() >= 1 then
                local pos = fac:GetPosition()
                local x = pos[1] + Random(0, 8) - 4
                local z = pos[3] + Random(4, 8)
                CreateUnitHPR(bpId, armyIndex, x, GetTerrainHeight(x, z), z, 0, 0, 0)
                spawned = spawned + 1
            end
        end
        if spawned > 0 then
            LOG("FAF_BUFF_DRAFT: " .. buffId .. " spawned " .. tostring(spawned)
                .. "x " .. tostring(bpId) .. " for army " .. tostring(armyIndex))
        end
    end
end

--#endregion

--#region buff specs

-- Each part: name (unique; blueprint name for kind="buff"), kind ("buff"|"custom"),
-- buffType (kind="buff" only), apply (kind="custom" only), category (sim category
-- object), when ("create"|"built"), futureOnly (skip pick-time sweep), active
-- (armyIndex -> true, filled on pick). A spec may also have armyApply(buffId,
-- armyIndex), run once per army per buff, and must have a `method` string for the
-- "implemented via" log.
local BuffSpecs = {
    engineer_build_speed_1 = { method = "buff system BuildRate", parts = { {
        name = 'BuffDraftEngineerBuildSpeed1', kind = 'buff', buffType = 'BUFFDRAFTBUILDRATE',
        category = categories.ENGINEER - categories.COMMAND, when = 'create',
    } } },
    factory_build_speed_1 = { method = "buff system BuildRate", parts = { {
        name = 'BuffDraftFactoryBuildSpeed1', kind = 'buff', buffType = 'BUFFDRAFTFACTORYBUILDRATE',
        category = categories.FACTORY, when = 'create',
    } } },
    air_speed_1 = { method = "buff system MoveMult", parts = { {
        name = 'BuffDraftAirSpeed1', kind = 'buff', buffType = 'BUFFDRAFTAIRSPEED',
        category = categories.AIR * categories.MOBILE, when = 'built',
    } } },
    naval_armor_1 = { method = "buff system MaxHealth", parts = { {
        name = 'BuffDraftNavalArmor1', kind = 'buff', buffType = 'BUFFDRAFTNAVALARMOR',
        category = categories.NAVAL * categories.MOBILE, when = 'built',
    } } },
    experimentals_health_1 = { method = "buff system MaxHealth", parts = { {
        name = 'BuffDraftExperimentalHealth1', kind = 'buff', buffType = 'BUFFDRAFTEXPHEALTH',
        category = categories.EXPERIMENTAL, when = 'built',
    } } },
    acu_regen_1 = { method = "buff system Regen", parts = { {
        name = 'BuffDraftAcuRegen1', kind = 'buff', buffType = 'BUFFDRAFTACUREGEN',
        category = categories.COMMAND, when = 'built',
    } } },
    eco_overclock_1 = { method = "buff system Energy/MassProduction", parts = { {
        name = 'BuffDraftEcoOverclock1', kind = 'buff', buffType = 'BUFFDRAFTECO',
        category = categories.STRUCTURE * (categories.MASSPRODUCTION + categories.ENERGYPRODUCTION),
        when = 'built',
    } } },
    -- "Radar and vision": radar radius on units that already have radar, vision on
    -- scouts. Restricting to RADAR avoids BuffEffects.RadarRadius granting radar to
    -- units that never had it (it calls InitIntel for non-radar units).
    radar_vision_1 = { method = "buff system Radar/VisionRadius", parts = {
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
    anti_air_damage_1 = { method = "per-weapon ChangeDamage", parts = { {
        name = 'BuffDraftAntiAirDamage1', kind = 'custom',
        apply = WeaponDamageMult('UWRC_AntiAir', ANTIAIR_DAMAGE_MULT),
        category = categories.ANTIAIR, when = 'built',
    } } },
    land_rate_of_fire_1 = { method = "per-weapon ChangeRateOfFire", parts = { {
        name = 'BuffDraftLandRateOfFire1', kind = 'custom',
        apply = WeaponRateOfFireMult('UWRC_DirectFire', LAND_ROF_MULT),
        category = categories.LAND * categories.MOBILE, when = 'built',
    } } },
    artillery_range_1 = { method = "per-weapon ChangeMaxRadius", parts = { {
        name = 'BuffDraftArtilleryRange1', kind = 'custom',
        apply = WeaponRangeMult('UWRC_IndirectFire', ARTILLERY_RANGE_MULT),
        category = categories.ARTILLERY, when = 'built',
    } } },
    tactical_range_1 = { method = "per-weapon ChangeMaxRadius", parts = { {
        name = 'BuffDraftTacticalRange1', kind = 'custom',
        apply = WeaponRangeMult(nil, TACTICAL_RANGE_MULT), -- TML structures have a single weapon
        category = categories.TACTICALMISSILEPLATFORM, when = 'built',
    } } },
    shield_health_1 = { method = "shield entity SetMaxHealth", parts = { {
        name = 'BuffDraftShieldHealth1', kind = 'custom',
        apply = ShieldMaxHealthMult(SHIELD_HEALTH_MULT),
        category = categories.STRUCTURE * categories.SHIELD, when = 'built',
    } } },
    mobile_shields_1 = { method = "shield entity SetMaxHealth", parts = { {
        name = 'BuffDraftMobileShields1', kind = 'custom',
        apply = ShieldMaxHealthMult(MOBILE_SHIELD_HEALTH_MULT),
        category = categories.MOBILE * categories.SHIELD, when = 'built',
    } } },

    -- new buffs
    drone_foundry_1 = {
        method = "CreateUnitHPR spawn thread (free T1 tanks at land factories)",
        armyApply = function(buffId, armyIndex)
            ForkThread(FactorySpawnThread, buffId, armyIndex, DRONE_TANK_BPS,
                DRONE_FOUNDRY_INTERVAL, DRONE_FOUNDRY_MAX_PER_WAVE)
        end,
    },
    engineer_swarm_1 = {
        method = "CreateUnitHPR spawn thread (free T1 engineers at land factories)",
        armyApply = function(buffId, armyIndex)
            ForkThread(FactorySpawnThread, buffId, armyIndex, SWARM_ENGINEER_BPS,
                ENGINEER_SWARM_INTERVAL, ENGINEER_SWARM_MAX_PER_WAVE)
        end,
    },
    -- conditional build-rate buffs: activation only sets the army flag; the actual
    -- apply/remove happens in OnUnitStartBuild/OnUnitStopBuild below
    emergency_fabrication_1 = {
        method = "OnStartBuild-conditional buff system BuildRate (defense targets)",
        conditionalBuild = {
            name = 'BuffDraftEmergencyFab1', buffType = 'BUFFDRAFTEMERGENCYFAB',
            builderCategory = categories.ENGINEER,
            targetCategory = categories.STRUCTURE * categories.DEFENSE,
            active = {},
        },
    },
    experimental_discount_1 = {
        method = "OnStartBuild-conditional buff system BuildRate (experimental targets);"
            .. " cheaper cost not implemented (blueprint economy is global)",
        conditionalBuild = {
            name = 'BuffDraftExpDiscount1', buffType = 'BUFFDRAFTEXPDISCOUNT',
            builderCategory = categories.ENGINEER + categories.FACTORY,
            targetCategory = categories.EXPERIMENTAL,
            active = {},
        },
    },
    overcharged_shields_1 = {
        method = "shield entity SetMaxHealth; longer recharge not implemented"
            .. " (shield spec is fixed at creation)",
        parts = { {
            name = 'BuffDraftOverchargedShields1', kind = 'custom',
            apply = ShieldMaxHealthMult(OVERCHARGED_SHIELD_MULT),
            category = categories.SHIELD, when = 'built',
        } },
    },
    napalm_rounds_1 = {
        method = "per-weapon AddDamageRadiusMod; DoT not implemented"
            .. " (DoTTime/DoTPulses are blueprint-only)",
        parts = {
            {
                name = 'BuffDraftNapalmDirect1', kind = 'custom',
                apply = WeaponDamageRadiusAdd('UWRC_DirectFire', NAPALM_RADIUS_ADD),
                category = categories.LAND * categories.MOBILE, when = 'built',
            },
            {
                name = 'BuffDraftNapalmArtillery1', kind = 'custom',
                apply = WeaponDamageRadiusAdd('UWRC_IndirectFire', NAPALM_RADIUS_ADD),
                category = categories.ARTILLERY, when = 'built',
            },
        },
    },
    teleport_doctrine_1 = {
        method = "buff system MoveMult; teleport not implemented"
            .. " (needs blueprint enhancement + teleport UI)",
        parts = { {
            name = 'BuffDraftTeleportDoctrine1', kind = 'buff', buffType = 'BUFFDRAFTTELEPORT',
            category = categories.ENGINEER + categories.COMMAND + categories.SUBCOMMANDER,
            when = 'built',
        } },
    },
    nano_swarm_1 = {
        method = "buff system Regen (passive; out-of-combat detection unsafe)",
        parts = { {
            name = 'BuffDraftNanoSwarm1', kind = 'buff', buffType = 'BUFFDRAFTNANOSWARM',
            category = categories.ALLUNITS, when = 'built',
        } },
    },
    rapid_deployment_1 = {
        method = "buff system MoveMult with Duration (new units only)",
        parts = { {
            name = 'BuffDraftRapidDeploy1', kind = 'buff', buffType = 'BUFFDRAFTRAPIDDEPLOY',
            category = categories.MOBILE, when = 'built', futureOnly = true,
        } },
    },
    fortress_protocol_1 = {
        method = "buff system MaxHealth (structures) + MoveMult penalty (mobile)",
        parts = {
            {
                name = 'BuffDraftFortressHP1', kind = 'buff', buffType = 'BUFFDRAFTFORTRESSHP',
                category = categories.STRUCTURE, when = 'built',
            },
            {
                name = 'BuffDraftFortressSlow1', kind = 'buff', buffType = 'BUFFDRAFTFORTRESSSLOW',
                category = categories.MOBILE, when = 'built',
            },
        },
    },
    hunter_protocol_1 = {
        method = "buff system VisionRadius + RadarRadius + MoveMult",
        parts = {
            {
                name = 'BuffDraftHunterVision1', kind = 'buff', buffType = 'BUFFDRAFTHUNTERVISION',
                category = categories.MOBILE, when = 'built',
            },
            {
                -- restricted to RADAR so RadarRadius does not grant radar to units without it
                name = 'BuffDraftHunterRadar1', kind = 'buff', buffType = 'BUFFDRAFTHUNTERRADAR',
                category = categories.MOBILE * categories.RADAR, when = 'built',
            },
            {
                name = 'BuffDraftHunterSpeed1', kind = 'buff', buffType = 'BUFFDRAFTHUNTERSPEED',
                category = categories.MOBILE, when = 'built',
            },
        },
    },
    black_market_economy_1 = {
        method = "Unit.OnKilledUnit hook + brain:GiveResource",
        armyApply = function(buffId, armyIndex)
            BlackMarketArmies[armyIndex] = true
        end,
    },
    tactical_supremacy_1 = {
        method = "per-weapon ChangeMaxRadius + buff system BuildRate (missile construction)",
        parts = {
            {
                name = 'BuffDraftTacSupremacyRange1', kind = 'custom',
                apply = WeaponRangeMult(nil, TAC_SUPREMACY_RANGE_MULT),
                category = categories.TACTICALMISSILEPLATFORM, when = 'built',
            },
            {
                name = 'BuffDraftTacSupremacyBuild1', kind = 'buff', buffType = 'BUFFDRAFTTACBUILD',
                category = categories.TACTICALMISSILEPLATFORM, when = 'create',
            },
        },
    },
    air_superiority_1 = {
        method = "buff system MoveMult + MaxHealth, per-weapon ChangeDamage",
        parts = {
            {
                name = 'BuffDraftAirSupSpeed1', kind = 'buff', buffType = 'BUFFDRAFTAIRSUPSPEED',
                category = categories.AIR * categories.MOBILE, when = 'built',
            },
            {
                name = 'BuffDraftAirSupHP1', kind = 'buff', buffType = 'BUFFDRAFTAIRSUPHP',
                category = categories.AIR * categories.MOBILE, when = 'built',
            },
            {
                name = 'BuffDraftAirSupDamage1', kind = 'custom',
                apply = WeaponDamageMult(nil, AIR_SUP_DAMAGE_MULT),
                category = categories.AIR * categories.MOBILE, when = 'built',
            },
        },
    },
    naval_dreadnoughts_1 = {
        method = "buff system MaxHealth + per-weapon ChangeMaxRadius",
        parts = {
            {
                name = 'BuffDraftDreadnoughtHP1', kind = 'buff', buffType = 'BUFFDRAFTDREADNOUGHTHP',
                category = categories.NAVAL * categories.MOBILE, when = 'built',
            },
            {
                name = 'BuffDraftDreadnoughtRange1', kind = 'custom',
                apply = WeaponRangeMult(nil, DREADNOUGHT_RANGE_MULT),
                category = categories.NAVAL * categories.MOBILE, when = 'built',
            },
        },
    },
    radar_omniscience_1 = {
        method = "buff system OmniRadius + RadarRadius",
        parts = {
            {
                -- OMNI intersection: only units that already have omni get the mult
                name = 'BuffDraftOmniRadius1', kind = 'buff', buffType = 'BUFFDRAFTOMNI',
                category = (categories.COMMAND + categories.STRUCTURE * categories.RADAR * categories.TECH3)
                    * categories.OMNI,
                when = 'built',
            },
            {
                name = 'BuffDraftOmniRadarRadius1', kind = 'buff', buffType = 'BUFFDRAFTOMNIRADAR',
                category = categories.STRUCTURE * categories.RADAR * categories.TECH3, when = 'built',
            },
        },
    },
}

-- initialize per-part activation state
for _, spec in BuffSpecs do
    for _, part in spec.parts or {} do
        part.active = {}
    end
end

-- conditional-build entries collected for the OnStartBuild/OnStopBuild hooks
local ConditionalBuildEntries = {}
for _, spec in BuffSpecs do
    if spec.conditionalBuild then
        table.insert(ConditionalBuildEntries, spec.conditionalBuild)
    end
end

local NotImplementedReasons = {
    reclaim_bonus_1 = "reclaim yield lives on props / the engine reclaim command, no per-unit"
        .. " instance API; scaling build rate instead would also change build speed",
    missile_storm_1 = "MuzzleSalvoSize is weapon blueprint data; no per-instance salvo-size API",
    orbital_lance_1 = "needs a target-point UI and a custom strike weapon; TODO",
    chain_lightning_weapons_1 = "chaining needs custom projectile/weapon scripts, no safe"
        .. " per-instance hook; TODO",
    salvage_explosion_1 = "wreckage mass/explosions are computed from the victim blueprint at"
        .. " death; buffing our side gives no safe handle on enemy wrecks",
}

--#endregion

--#region generic application

-- Buff.HasBuff indexes BuffTable[BuffType] without a nil check and errors on units
-- that never had a buff of this type, so do the double-apply check ourselves.
local function HasBuffOfType(unit, buffType, name)
    local buffs = unit.Buffs
    if (not buffs) or (not buffs.BuffTable) then
        return false
    end
    local byType = buffs.BuffTable[buffType]
    return byType and byType[name] and true or false
end

local function HasBuffApplied(unit, part)
    if part.kind == 'buff' then
        return HasBuffOfType(unit, part.buffType, part.name)
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

    LOG("FAF_BUFF_DRAFT: " .. buffId .. " implemented via " .. spec.method)
    LOG("FAF_BUFF_DRAFT: applying " .. buffId .. " to armies: " .. ArmiesToString(armies))

    for _, part in spec.parts or {} do
        -- future units: mark the armies so the Unit hooks buff new matching units
        for _, armyIndex in armies do
            part.active[armyIndex] = true
        end

        -- existing units; "built"-phase parts skip unfinished units, the
        -- OnStopBeingBuilt hook picks those up on completion. futureOnly parts
        -- never sweep (only units built after the pick qualify).
        if not part.futureOnly then
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
    end

    if spec.conditionalBuild then
        for _, armyIndex in armies do
            spec.conditionalBuild.active[armyIndex] = true
        end
    end

    if spec.armyApply then
        spec.armyApplied = spec.armyApplied or {}
        for _, armyIndex in armies do
            if not spec.armyApplied[armyIndex] then
                spec.armyApplied[armyIndex] = true
                spec.armyApply(buffId, armyIndex)
            end
        end
    end

    LOG("FAF_BUFF_DRAFT: " .. buffId .. " future units hook active")
end

local function ApplyActivePartsToUnit(unit, when)
    for buffId, spec in BuffSpecs do
        for _, part in spec.parts or {} do
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

--- Called from the Unit.OnStartBuild hook: applies conditional build-rate buffs
--- while the builder is working on a matching target (Stacks='IGNORE' makes a
--- repeated apply for queued targets a no-op).
function OnUnitStartBuild(builder, built)
    if not built then
        return
    end
    for _, entry in ConditionalBuildEntries do
        if entry.active[builder.Army]
            and EntityCategoryContains(entry.builderCategory, builder)
            and EntityCategoryContains(entry.targetCategory, built) then
            Buff.ApplyBuff(builder, entry.name)
        end
    end
end

--- Called from the Unit.OnStopBuild and OnFailedToBuild hooks: removes any
--- conditional build-rate buff (Buff.RemoveBuff recalculates the rate from the
--- remaining buffs). Guarded by our own check - RemoveBuff indexes the BuffTable
--- without nil checks.
function OnUnitStopBuild(builder)
    for _, entry in ConditionalBuildEntries do
        if entry.active[builder.Army] and HasBuffOfType(builder, entry.buffType, entry.name) then
            Buff.RemoveBuff(builder, entry.name, true)
        end
    end
end

--- Called from the Unit.OnKilledUnit hook. Black market bounty: killing an enemy
--- grants a fraction of its blueprint cost (GiveResource caps at storage).
function OnUnitKilledUnit(killer, victim)
    if not BlackMarketArmies[killer.Army] then
        return
    end
    if (not victim) or (not victim.Army) or (not IsEnemy(killer.Army, victim.Army)) then
        return
    end
    local brain = ArmyBrains[killer.Army]
    if not brain then
        return
    end
    local eco = victim:GetBlueprint().Economy or {}
    local mass = math.floor((eco.BuildCostMass or 0) * BLACK_MARKET_MASS_FRACTION)
    local energy = math.floor((eco.BuildCostEnergy or 0) * BLACK_MARKET_ENERGY_FRACTION)
    if mass > 0 then
        brain:GiveResource('MASS', mass)
    end
    if energy > 0 then
        brain:GiveResource('ENERGY', energy)
    end
end

--#endregion
