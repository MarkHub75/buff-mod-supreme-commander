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
-- All balance values live in /mods/BuffDraft/lua/config.lua; each read falls
-- back to the same default, so a missing config field cannot crash the sim.
-- The catalog tooltips (buffs.lua) are built from the same config values.

local BuffDraftConfig = import('/mods/BuffDraft/lua/config.lua')

-- nil-safe knob read
local function Knob(name, default)
    local value = BuffDraftConfig[name]
    if value == nil then
        return default
    end
    return value
end

local ENGINEER_BUILD_RATE_MULT = Knob('ENGINEER_BUILD_RATE_MULT', 5.0)
local FACTORY_BUILD_RATE_MULT = Knob('FACTORY_BUILD_RATE_MULT', 3.0)
local AIR_SPEED_MULT = Knob('AIR_SPEED_MULT', 1.25)
local NAVAL_ARMOR_MULT = Knob('NAVAL_ARMOR_MULT', 2.5)
local EXPERIMENTAL_HEALTH_MULT = Knob('EXPERIMENTAL_HEALTH_MULT', 2.0)
local ACU_REGEN_ADD = Knob('ACU_REGEN_ADD', 60)
local RADAR_RADIUS_MULT = Knob('RADAR_RADIUS_MULT', 2.0)
local SCOUT_VISION_MULT = Knob('SCOUT_VISION_MULT', 2.0)
local ECO_PRODUCTION_MULT = Knob('ECO_PRODUCTION_MULT', 2.5)
local ANTIAIR_DAMAGE_MULT = Knob('ANTIAIR_DAMAGE_MULT', 2.5)
local LAND_ROF_MULT = Knob('LAND_ROF_MULT', 2.0)
local ARTILLERY_RANGE_MULT = Knob('ARTILLERY_RANGE_MULT', 1.5)
local TACTICAL_RANGE_MULT = Knob('TACTICAL_RANGE_MULT', 2.0)
local SHIELD_HEALTH_MULT = Knob('SHIELD_HEALTH_MULT', 2.0)
local MOBILE_SHIELD_HEALTH_MULT = Knob('MOBILE_SHIELD_HEALTH_MULT', 2.0)

local DRONE_FOUNDRY_INTERVAL = Knob('DRONE_FOUNDRY_INTERVAL', 45)
local DRONE_FOUNDRY_MAX_PER_WAVE = Knob('DRONE_FOUNDRY_MAX_PER_WAVE', 4)
local ENGINEER_SWARM_INTERVAL = Knob('ENGINEER_SWARM_INTERVAL', 60)
local ENGINEER_SWARM_MAX_PER_WAVE = Knob('ENGINEER_SWARM_MAX_PER_WAVE', 2)
local EMERGENCY_FAB_BUILD_MULT = Knob('EMERGENCY_FAB_BUILD_MULT', 3.0)
local OVERCHARGED_SHIELD_MULT = Knob('OVERCHARGED_SHIELD_MULT', 2.5)
local NAPALM_RADIUS_ADD = Knob('NAPALM_RADIUS_ADD', 1.0)
local TELEPORT_SPEED_MULT = Knob('TELEPORT_SPEED_MULT', 2.0)
local NANO_REGEN_ADD = Knob('NANO_REGEN_ADD', 5)
local EXP_DISCOUNT_BUILD_MULT = Knob('EXP_DISCOUNT_BUILD_MULT', 2.5)
local RAPID_SPEED_MULT = Knob('RAPID_SPEED_MULT', 2.0)
local RAPID_DURATION = Knob('RAPID_DURATION', 60) -- buff Duration is in game seconds
local FORTRESS_HP_MULT = Knob('FORTRESS_HP_MULT', 3.0)
local FORTRESS_SPEED_MULT = Knob('FORTRESS_SPEED_MULT', 0.85)
local HUNTER_VISION_MULT = Knob('HUNTER_VISION_MULT', 2.0)
local HUNTER_RADAR_MULT = Knob('HUNTER_RADAR_MULT', 2.0)
local HUNTER_SPEED_MULT = Knob('HUNTER_SPEED_MULT', 1.5)
local BLACK_MARKET_MASS_FRACTION = Knob('BLACK_MARKET_MASS_FRACTION', 0.1)
local BLACK_MARKET_ENERGY_FRACTION = Knob('BLACK_MARKET_ENERGY_FRACTION', 0.1)
local SALVAGE_EXPLOSION_CHANCE = Knob('SALVAGE_EXPLOSION_CHANCE', 25)
local SALVAGE_EXPLOSION_RADIUS = Knob('SALVAGE_EXPLOSION_RADIUS', 3)
local SALVAGE_EXPLOSION_DAMAGE = Knob('SALVAGE_EXPLOSION_DAMAGE', 150)
local ORBITAL_LANCE_COOLDOWN = Knob('ORBITAL_LANCE_COOLDOWN', 90)
local ORBITAL_LANCE_TICKS = Knob('ORBITAL_LANCE_TICKS', 5)
local ORBITAL_LANCE_TICK_DAMAGE = Knob('ORBITAL_LANCE_TICK_DAMAGE', 800)
local ORBITAL_LANCE_RADIUS = Knob('ORBITAL_LANCE_RADIUS', 5)
local ORBITAL_LANCE_TICK_INTERVAL = Knob('ORBITAL_LANCE_TICK_INTERVAL', 0.4)
local ORBITAL_LANCE_SHIELD_SCAN_RADIUS = 160 -- covers stock bubble shields incl. shield boats
local CHAIN_BEAM_DAMAGE_MULT = Knob('CHAIN_BEAM_DAMAGE_MULT', 1.5)
local CHAIN_BEAM_RADIUS_ADD = Knob('CHAIN_BEAM_RADIUS_ADD', 1.5)
local RECLAIM_RATE_MULT = Knob('RECLAIM_RATE_MULT', 2.0)
local TAC_SUPREMACY_RANGE_MULT = Knob('TAC_SUPREMACY_RANGE_MULT', 3.0)
local TAC_SUPREMACY_BUILD_MULT = Knob('TAC_SUPREMACY_BUILD_MULT', 2.0)
local MISSILE_STORM_ROF_MULT = Knob('MISSILE_STORM_ROF_MULT', 2.5)
local MISSILE_STORM_BUILD_MULT = Knob('MISSILE_STORM_BUILD_MULT', 2.5)
local AIR_SUP_SPEED_MULT = Knob('AIR_SUP_SPEED_MULT', 2.0)
local AIR_SUP_DAMAGE_MULT = Knob('AIR_SUP_DAMAGE_MULT', 1.5)
local AIR_SUP_HP_MULT = Knob('AIR_SUP_HP_MULT', 0.75)
local DREADNOUGHT_HP_MULT = Knob('DREADNOUGHT_HP_MULT', 3.0)
local DREADNOUGHT_RANGE_MULT = Knob('DREADNOUGHT_RANGE_MULT', 1.5)
local OMNISCIENCE_OMNI_MULT = Knob('OMNISCIENCE_OMNI_MULT', 3.0)
local OMNISCIENCE_RADAR_MULT = Knob('OMNISCIENCE_RADAR_MULT', 2.5)

LOG("FAF_BUFF_DRAFT: orbital_lance config cooldown=" .. tostring(ORBITAL_LANCE_COOLDOWN)
    .. " ticks=" .. tostring(ORBITAL_LANCE_TICKS)
    .. " dmg=" .. tostring(ORBITAL_LANCE_TICK_DAMAGE)
    .. " r=" .. tostring(ORBITAL_LANCE_RADIUS))

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
    Name = 'BuffDraftEcoOverclockEnergy1',
    DisplayName = 'Eco Overclock I (energy)',
    BuffType = 'BUFFDRAFTECOENERGY',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'STRUCTURE',
    -- same instance-level path adjacency bonuses use (unit.*ProdAdjMod)
    Affects = {
        EnergyProduction = { Add = 0, Mult = ECO_PRODUCTION_MULT },
    },
}

BuffBlueprint {
    Name = 'BuffDraftEcoOverclockMass1',
    DisplayName = 'Eco Overclock I (mass)',
    BuffType = 'BUFFDRAFTECOMASS',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'STRUCTURE',
    -- same instance-level path adjacency bonuses use (unit.*ProdAdjMod)
    Affects = {
        MassProduction = { Add = 0, Mult = ECO_PRODUCTION_MULT },
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
    Name = 'BuffDraftReclaimRate1',
    DisplayName = 'Reclaim Bonus (speed)',
    BuffType = 'BUFFDRAFTRECLAIMRATE',
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ALLUNITS',
    Affects = { BuildRate = { Add = 0, Mult = RECLAIM_RATE_MULT } },
}

BuffBlueprint {
    Name = 'BuffDraftMissileStormBuild1',
    DisplayName = 'Missile Storm (missile build)',
    BuffType = 'BUFFDRAFTMSSTORMBUILD', -- own type: stacks with BUFFDRAFTTACBUILD
    Stacks = 'IGNORE',
    Duration = -1,
    EntityCategory = 'ALLUNITS',
    Affects = { BuildRate = { Add = 0, Mult = MISSILE_STORM_BUILD_MULT } },
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

-- Chain-lightning approximation: beam/laser weapons only. Every beam weapon
-- blueprint has BeamLifetime (DefaultBeamWeapon aborts setup without it), so its
-- presence is a reliable per-blueprint "this is a beam" marker. Beam damage goes
-- through the weapon damage table, so ChangeDamage and AddDamageRadiusMod both
-- apply (CollisionBeam:DoDamage uses DamageData.DamageRadius via DamageArea).
local function BeamWeaponBoost(damageMult, radiusAdd)
    return function(unit)
        ForEachWeapon(unit, nil, function(wep, bp, i)
            if bp.BeamLifetime ~= nil then
                wep:ChangeDamage((bp.Damage or 0) * CombinedWeaponMult(unit, 'dmg', i, damageMult))
                wep:AddDamageRadiusMod(radiusAdd)
            end
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

local function RefreshProductionValuesNextTick(unit)
    local thread = ForkThread(function()
        WaitTicks(1)
        if (not unit) or unit.Dead then
            return
        end
        unit:UpdateProductionValues()
    end)
    if unit.Trash then
        unit.Trash:Add(thread)
    end
end

--#endregion

--#region army-level effects (spawn threads, kill bounty)

-- armies with black_market_economy_1 / salvage_explosion_1 active; consulted by
-- the OnKilledUnit hook
local BlackMarketArmies = {}
local SalvageExplosionArmies = {}

-- "<buffId>:<armyIndex>" -> generation counter. A spawn thread only keeps running
-- while its own generation is the current one; both the admin remove AND a
-- re-grant bump the counter, so a remove+re-grant inside one wait interval can
-- never leave two threads spawning for the same buff+army.
local SpawnThreadGeneration = {}

local function BumpSpawnGeneration(buffId, armyIndex)
    local key = buffId .. ":" .. tostring(armyIndex)
    SpawnThreadGeneration[key] = (SpawnThreadGeneration[key] or 0) + 1
    return SpawnThreadGeneration[key]
end

local function FactionBlueprint(brain, bpByFaction)
    return bpByFaction[brain:GetFactionIndex()] or bpByFaction[1]
end

-- Periodically spawns free units next to finished land factories. CreateUnitHPR is
-- the standard sim spawn call (scenario scripts, pods, external factories).
local function FactorySpawnThread(buffId, armyIndex, bpByFaction, interval, maxPerWave, myGeneration)
    local brain = ArmyBrains[armyIndex]
    if not brain then
        return
    end
    local flagKey = buffId .. ":" .. tostring(armyIndex)
    local bpId = FactionBlueprint(brain, bpByFaction)
    LOG("FAF_BUFF_DRAFT: " .. buffId .. " spawn thread started army=" .. tostring(armyIndex)
        .. " bp=" .. tostring(bpId) .. " interval=" .. tostring(interval))
    while ArmyBrains[armyIndex] and SpawnThreadGeneration[flagKey] == myGeneration do
        WaitSeconds(interval)
        brain = ArmyBrains[armyIndex]
        if (not brain) or (SpawnThreadGeneration[flagKey] ~= myGeneration) then
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
    LOG("FAF_BUFF_DRAFT: " .. buffId .. " spawn thread stopped army=" .. tostring(armyIndex))
end

local function FindOrbitalInstigator(brain)
    local priority = {
        categories.COMMAND + categories.SUBCOMMANDER,
        categories.ALLUNITS - categories.WALL,
    }
    for _, cat in priority do
        for _, unit in brain:GetListOfUnits(cat, false, false) or {} do
            if unit and (not unit.Dead) and IsEntity(unit) then
                return unit
            end
        end
    end
    return nil
end

local function PointInShieldBubble(pos, shield)
    if (not shield) or shield.ShieldType == "Personal" or (not shield.Size) or shield.Size <= 0 then
        return false
    end
    if (not shield.IsUp) or (not shield:IsUp()) then
        return false
    end
    local spos = shield:GetPosition()
    local dx = spos[1] - pos[1]
    local dz = spos[3] - pos[3]
    local radius = 0.5 * shield.Size
    return dx * dx + dz * dz <= radius * radius
end

local function GetCoveringShieldBubbles(brain, pos)
    local shields = {}
    for _, shieldUnit in brain:GetUnitsAroundPoint(
        categories.SHIELD, pos, ORBITAL_LANCE_SHIELD_SCAN_RADIUS) or {} do
        local shield = shieldUnit.MyShield
        if shieldUnit and (not shieldUnit.Dead) and PointInShieldBubble(pos, shield) then
            table.insert(shields, { unit = shieldUnit, shield = shield })
        end
    end
    return shields
end

local function PlayOrbitalPointFx(armyIndex, pos)
    local Entity = import('/lua/sim/entity.lua').Entity
    local EffectTemplates = import('/lua/EffectTemplates.lua')
    local fxEntity = Entity()
    Warp(fxEntity, pos)
    for _, effect in EffectTemplates.ExplosionLarge do
        CreateEmitterAtEntity(fxEntity, armyIndex, effect)
    end
    CreateLightParticle(fxEntity, -1, armyIndex, 8, 12, 'glow_03', 'ramp_red_06')
    WaitSeconds(2)
    fxEntity:Destroy()
end

local function DebugWatchUnits(brain, pos)
    local debugOn = import('/mods/BuffDraft/lua/config.lua').DebugAdmin
    if not debugOn then
        return nil
    end
    local watched = {}
    local enemies = brain:GetUnitsAroundPoint(
        categories.ALLUNITS, pos, ORBITAL_LANCE_RADIUS, 'Enemy') or {}
    LOG("FAF_BUFF_DRAFT: orbital_lance_1 debug units before: enemies="
        .. tostring(table.getn(enemies)))
    for _, unit in enemies do
        if not unit.Dead then
            LOG("FAF_BUFF_DRAFT: orbital_lance_1 debug units before enemy "
                .. UnitLabel(unit) .. " hp=" .. tostring(unit:GetHealth()))
            table.insert(watched, { unit = unit, hp = unit:GetHealth() })
        end
    end
    return watched
end

local function DebugReportUnits(watched)
    if not watched then
        return
    end
    local affected = 0
    for _, entry in watched do
        local unit = entry.unit
        if unit.Dead then
            affected = affected + 1
        else
            local hp = unit:GetHealth()
            LOG("FAF_BUFF_DRAFT: orbital_lance_1 debug units after enemy "
                .. UnitLabel(unit) .. " hp=" .. tostring(hp))
            if hp < entry.hp then
                affected = affected + 1
            end
        end
    end
    LOG("FAF_BUFF_DRAFT: orbital_lance_1 debug affected enemies="
        .. tostring(affected) .. " of " .. tostring(table.getn(watched)))
end

local function ApplyShieldAwareOrbitalDamage(instigator, brain, pos, amount, tick)
    local remaining = amount
    local shields = GetCoveringShieldBubbles(brain, pos)
    LOG("FAF_BUFF_DRAFT: orbital_lance_1 shield check tick=" .. tostring(tick)
        .. " covering=" .. tostring(table.getn(shields))
        .. " incoming=" .. tostring(amount))

    for _, entry in shields do
        if remaining <= 0 then
            break
        end
        local shield = entry.shield
        if PointInShieldBubble(pos, shield) then
            local before = shield:GetHealth()
            local after = before
            local okShield, errShield = pcall(function()
                shield:ApplyDamage(instigator, remaining, Vector(0, -1, 0), 'Normal', false)
                after = math.max(0, shield:GetHealth())
            end)
            if not okShield then
                WARN("FAF_BUFF_DRAFT: orbital_lance_1 shield damage API failed; blocking ground damage: "
                    .. tostring(errShield))
                remaining = 0
                break
            end
            local absorbed = math.max(0, before - after)
            remaining = math.max(0, remaining - absorbed)
            LOG("FAF_BUFF_DRAFT: orbital_lance_1 shield absorbed/blocked tick="
                .. tostring(tick) .. " by " .. UnitLabel(entry.unit)
                .. " hp=" .. tostring(before) .. "->" .. tostring(after)
                .. " absorbed=" .. tostring(absorbed)
                .. " remaining=" .. tostring(remaining))
            if shield:IsUp() and shield:GetHealth() > 0 then
                remaining = 0
                break
            end
        end
    end

    if remaining > 0 then
        LOG("FAF_BUFF_DRAFT: orbital_lance_1 spill damage tick=" .. tostring(tick)
            .. " amount=" .. tostring(remaining)
            .. " r=" .. tostring(ORBITAL_LANCE_RADIUS))
        DamageArea(instigator, pos, ORBITAL_LANCE_RADIUS, remaining, 'Normal', true, true)
    end
end

-- Stable strike thread. Visuals use only point FX on a temporary bare entity.
-- Damage is shield-aware DamageArea: covering bubble shields take the pulse first;
-- ground damage happens only when no shield covers the point or the shield is
-- depleted by the pulse. No projectiles or temporary beam attachments are used.
local function OrbitalDamageAreaThread(armyIndex, brain, pos, instigator)
    local watched = DebugWatchUnits(brain, pos)
    for tick = 1, ORBITAL_LANCE_TICKS do
        -- ChangeUnitArmy and death replace/destroy unit entities. A strike keeps
        -- running for ~2 seconds, so never pass a stale instigator to the engine
        -- damage API (it raises "Expected a game object" in shield.lua).
        if (not instigator) or instigator.Dead or (not IsEntity(instigator))
                or instigator.Army ~= armyIndex then
            instigator = FindOrbitalInstigator(brain)
            if not instigator then
                WARN("FAF_BUFF_DRAFT: orbital_lance_1 stopped: no live instigator")
                return
            end
        end
        ForkThread(PlayOrbitalPointFx, armyIndex, pos)
        ApplyShieldAwareOrbitalDamage(instigator, brain, pos, ORBITAL_LANCE_TICK_DAMAGE, tick)
        WaitSeconds(ORBITAL_LANCE_TICK_INTERVAL)
    end
    DebugReportUnits(watched)
end

-- Starts the strike at a position. Returns success immediately after the strike
-- thread is forked (the caller charges the cooldown then); everything async
-- happens in OrbitalDamageAreaThread.
local function ExecuteOrbitalStrike(armyIndex, brain, pos)
    local instigator = FindOrbitalInstigator(brain)
    if not instigator then
        return false, "no valid instigator unit"
    end
    LOG("FAF_BUFF_DRAFT: orbital_lance_1 unsafe projectile path disabled; using DamageArea")
    LOG("FAF_BUFF_DRAFT: orbital_lance_1 damage-area strike started at "
        .. tostring(pos[1]) .. "," .. tostring(pos[3]) .. " army=" .. tostring(armyIndex)
        .. " (" .. tostring(ORBITAL_LANCE_TICKS) .. " ticks x "
        .. tostring(ORBITAL_LANCE_TICK_DAMAGE) .. " dmg, r=" .. tostring(ORBITAL_LANCE_RADIUS)
        .. ", over ~2s)")
    ForkThread(OrbitalDamageAreaThread, armyIndex, brain, pos, instigator)
    return true, nil
end

-- Orbital lance strike (triggered via the active-buff framework). With a valid
-- payload point ({x, z} world coords from the targeting UI, validated here) the
-- strike hits that point; without one it falls back to a random enemy structure
-- this army has identified (GetBlip + IsSeenEver - the SimObjectives "has been
-- seen" pattern). Returns success plus a reason on failure; a failed strike does
-- not charge the cooldown.
local function OrbitalLanceStrike(armyIndex, payload)
    local brain = ArmyBrains[armyIndex]
    if not brain then
        return false, "no army brain"
    end
    local sizeX = ScenarioInfo.size[1]
    local sizeZ = ScenarioInfo.size[2]

    -- manual target point from the UI (sim-side validation: numbers, map bounds)
    local px = payload and tonumber(payload.x)
    local pz = payload and tonumber(payload.z)
    if px and pz then
        if px < 0 or px > sizeX or pz < 0 or pz > sizeZ then
            return false, "target point out of map bounds"
        end
        local pos = Vector(px, GetSurfaceHeight(px, pz), pz)
        LOG("FAF_BUFF_DRAFT: orbital_lance_1 strike at point "
            .. tostring(px) .. "," .. tostring(pz) .. " army=" .. tostring(armyIndex))
        return ExecuteOrbitalStrike(armyIndex, brain, pos)
    end

    -- auto-target fallback (no or invalid point payload)
    local center = Vector(sizeX / 2, 0, sizeZ / 2)
    local scanRadius = math.max(sizeX, sizeZ)
    local candidates = brain:GetUnitsAroundPoint(
        categories.STRUCTURE, center, scanRadius, 'Enemy') or {}
    local visible = {}
    for _, target in candidates do
        if not target.Dead then
            local blip = target:GetBlip(armyIndex)
            if blip and blip:IsSeenEver(armyIndex) then
                table.insert(visible, target)
            end
        end
    end
    local count = table.getn(visible)
    if count == 0 then
        return false, "no identified enemy structure"
    end
    local target = visible[Random(1, count)]
    local pos = target:GetPosition()
    if (not pos) or target.Dead then
        return false, "target lost"
    end
    LOG("FAF_BUFF_DRAFT: orbital_lance_1 auto-target strike at " .. UnitLabel(target)
        .. " army=" .. tostring(armyIndex))
    return ExecuteOrbitalStrike(armyIndex, brain, pos)
end

--#endregion

--#region active buffs (player-triggered abilities with a per-army cooldown)
-- Generic framework, currently used only by orbital_lance_1. The UI shows an
-- Activate button per owned active buff and sends BuffDraftUseActive; everything
-- (ownership, cooldown, effect) is validated and executed sim-side. Cooldowns are
-- game-time (GetGameTimeSeconds); state is pushed to the UI once a second so the
-- countdown ticks without any UI-side timekeeping.

-- buffId -> { cooldown (game seconds), use = fn(armyIndex, payload) -> ok, reason }
local ActiveBuffDefs = {
    orbital_lance_1 = {
        cooldown = ORBITAL_LANCE_COOLDOWN,
        use = OrbitalLanceStrike,
    },
}

-- armyIndex -> buffId -> { cooldownUntil = gameSeconds, lastUsed = gameSeconds|nil }
local ActiveBuffState = {}
local ActiveSyncThreadStarted = false

--- SIM API: current state of every registered active buff, as plain data.
function GetActiveBuffSyncState()
    local now = GetGameTimeSeconds()
    local states = {}
    for armyIndex, buffs in ActiveBuffState do
        for buffId, state in buffs do
            local remaining = math.max(0, math.ceil(state.cooldownUntil - now))
            table.insert(states, {
                army = armyIndex,
                buffId = buffId,
                ready = remaining == 0,
                remaining = remaining,
                cooldown = ActiveBuffDefs[buffId].cooldown,
                lastUsed = state.lastUsed,
            })
        end
    end
    return states
end

local function SyncActiveBuffStates()
    Sync.BuffDraft = Sync.BuffDraft or {}
    table.insert(Sync.BuffDraft, { event = "active", states = GetActiveBuffSyncState() })
end

-- one broadcaster for all armies/buffs; started on the first registration
local function ActiveSyncThread()
    while true do
        WaitSeconds(1)
        SyncActiveBuffStates()
    end
end

local function RegisterActiveBuff(armyIndex, buffId)
    ActiveBuffState[armyIndex] = ActiveBuffState[armyIndex] or {}
    if ActiveBuffState[armyIndex][buffId] then
        return
    end
    ActiveBuffState[armyIndex][buffId] = { cooldownUntil = 0, lastUsed = nil }
    LOG("FAF_BUFF_DRAFT: active buff " .. tostring(buffId) .. " registered for army "
        .. tostring(armyIndex) .. ", ready")
    if not ActiveSyncThreadStarted then
        ActiveSyncThreadStarted = true
        ForkThread(ActiveSyncThread)
    end
    SyncActiveBuffStates()
end

local function UnregisterActiveBuff(armyIndex, buffId)
    local byArmy = ActiveBuffState[armyIndex]
    if byArmy and byArmy[buffId] then
        byArmy[buffId] = nil
        SyncActiveBuffStates()
        LOG("FAF_BUFF_DRAFT: active buff " .. tostring(buffId) .. " unregistered for army "
            .. tostring(armyIndex))
    end
end

--- SIM API: can this army use this active buff right now?
function CanUseActiveBuff(armyIndex, buffId)
    local def = ActiveBuffDefs[buffId]
    if not def then
        return false, "not an active buff"
    end
    local byArmy = ActiveBuffState[armyIndex]
    local state = byArmy and byArmy[buffId]
    if not state then
        return false, "army does not own this buff"
    end
    local now = GetGameTimeSeconds()
    if now < state.cooldownUntil then
        return false, "on cooldown, " .. tostring(math.ceil(state.cooldownUntil - now)) .. "s left"
    end
    return true, nil
end

--- SIM API: validate and execute an active buff. Called from the BuffDraftUseActive
--- SimCallback with the sender's army - the UI cannot use another army's buff.
--- A use that had no effect (e.g. no visible target) does not charge the cooldown.
function UseActiveBuff(armyIndex, buffId, payload)
    local ok, reason = CanUseActiveBuff(armyIndex, buffId)
    if not ok then
        LOG("FAF_BUFF_DRAFT: active use rejected army=" .. tostring(armyIndex)
            .. " buff=" .. tostring(buffId) .. ": " .. tostring(reason))
        return
    end
    local def = ActiveBuffDefs[buffId]
    -- def.use behind pcall: a bug inside the effect must fail this one activation
    -- (cooldown not charged), not abort the whole sim callback
    local okCall, success, failReason = pcall(def.use, armyIndex, payload)
    if not okCall then
        WARN("FAF_BUFF_DRAFT: " .. tostring(buffId) .. " activation errored: " .. tostring(success))
        success = false
        failReason = "internal error"
    end
    if success then
        local now = GetGameTimeSeconds()
        local state = ActiveBuffState[armyIndex][buffId]
        state.lastUsed = now
        state.cooldownUntil = now + def.cooldown
        LOG("FAF_BUFF_DRAFT: " .. tostring(buffId) .. " activated by army "
            .. tostring(armyIndex) .. ", cooldown " .. tostring(def.cooldown) .. "s")
    else
        LOG("FAF_BUFF_DRAFT: " .. tostring(buffId) .. " activation had no effect: "
            .. tostring(failReason) .. " (cooldown not charged)")
    end
    SyncActiveBuffStates()
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
    eco_overclock_1 = { method = "buff system EnergyProduction/MassProduction", parts = {
        {
            name = 'BuffDraftEcoOverclockEnergy1', kind = 'buff', buffType = 'BUFFDRAFTECOENERGY',
            category = categories.STRUCTURE * categories.ENERGYPRODUCTION,
            when = 'built', refreshProduction = true,
        },
        {
            name = 'BuffDraftEcoOverclockMass1', kind = 'buff', buffType = 'BUFFDRAFTECOMASS',
            category = categories.STRUCTURE * categories.MASSPRODUCTION,
            when = 'built', refreshProduction = true,
        },
    } },
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
    -- custom parts carry `unapply` (the same helper with the inverse value) so the
    -- admin remove can restore current units; helpers recompute from the blueprint
    -- via the combined-mult table, so apply+unapply lands back on the stock value
    anti_air_damage_1 = { method = "per-weapon ChangeDamage", parts = { {
        name = 'BuffDraftAntiAirDamage1', kind = 'custom',
        apply = WeaponDamageMult('UWRC_AntiAir', ANTIAIR_DAMAGE_MULT),
        unapply = WeaponDamageMult('UWRC_AntiAir', 1 / ANTIAIR_DAMAGE_MULT),
        category = categories.ANTIAIR, when = 'built',
    } } },
    land_rate_of_fire_1 = { method = "per-weapon ChangeRateOfFire", parts = { {
        name = 'BuffDraftLandRateOfFire1', kind = 'custom',
        apply = WeaponRateOfFireMult('UWRC_DirectFire', LAND_ROF_MULT),
        unapply = WeaponRateOfFireMult('UWRC_DirectFire', 1 / LAND_ROF_MULT),
        category = categories.LAND * categories.MOBILE, when = 'built',
    } } },
    artillery_range_1 = { method = "per-weapon ChangeMaxRadius", parts = { {
        name = 'BuffDraftArtilleryRange1', kind = 'custom',
        apply = WeaponRangeMult('UWRC_IndirectFire', ARTILLERY_RANGE_MULT),
        unapply = WeaponRangeMult('UWRC_IndirectFire', 1 / ARTILLERY_RANGE_MULT),
        category = categories.ARTILLERY, when = 'built',
    } } },
    tactical_range_1 = { method = "per-weapon ChangeMaxRadius", parts = { {
        name = 'BuffDraftTacticalRange1', kind = 'custom',
        apply = WeaponRangeMult(nil, TACTICAL_RANGE_MULT), -- TML structures have a single weapon
        unapply = WeaponRangeMult(nil, 1 / TACTICAL_RANGE_MULT),
        category = categories.TACTICALMISSILEPLATFORM, when = 'built',
    } } },
    shield_health_1 = { method = "shield entity SetMaxHealth", parts = { {
        name = 'BuffDraftShieldHealth1', kind = 'custom',
        apply = ShieldMaxHealthMult(SHIELD_HEALTH_MULT),
        unapply = ShieldMaxHealthMult(1 / SHIELD_HEALTH_MULT),
        category = categories.STRUCTURE * categories.SHIELD, when = 'built',
    } } },
    mobile_shields_1 = { method = "shield entity SetMaxHealth", parts = { {
        name = 'BuffDraftMobileShields1', kind = 'custom',
        apply = ShieldMaxHealthMult(MOBILE_SHIELD_HEALTH_MULT),
        unapply = ShieldMaxHealthMult(1 / MOBILE_SHIELD_HEALTH_MULT),
        category = categories.MOBILE * categories.SHIELD, when = 'built',
    } } },

    -- new buffs
    drone_foundry_1 = {
        method = "CreateUnitHPR spawn thread (free T1 tanks at land factories)",
        armyApply = function(buffId, armyIndex)
            ForkThread(FactorySpawnThread, buffId, armyIndex, DRONE_TANK_BPS,
                DRONE_FOUNDRY_INTERVAL, DRONE_FOUNDRY_MAX_PER_WAVE,
                BumpSpawnGeneration(buffId, armyIndex))
        end,
        armyRemove = function(buffId, armyIndex)
            BumpSpawnGeneration(buffId, armyIndex) -- invalidates the running thread
        end,
    },
    engineer_swarm_1 = {
        method = "CreateUnitHPR spawn thread (free T1 engineers at land factories)",
        armyApply = function(buffId, armyIndex)
            ForkThread(FactorySpawnThread, buffId, armyIndex, SWARM_ENGINEER_BPS,
                ENGINEER_SWARM_INTERVAL, ENGINEER_SWARM_MAX_PER_WAVE,
                BumpSpawnGeneration(buffId, armyIndex))
        end,
        armyRemove = function(buffId, armyIndex)
            BumpSpawnGeneration(buffId, armyIndex) -- invalidates the running thread
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
            unapply = ShieldMaxHealthMult(1 / OVERCHARGED_SHIELD_MULT),
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
                unapply = WeaponDamageRadiusAdd('UWRC_DirectFire', -NAPALM_RADIUS_ADD),
                category = categories.LAND * categories.MOBILE, when = 'built',
            },
            {
                name = 'BuffDraftNapalmArtillery1', kind = 'custom',
                apply = WeaponDamageRadiusAdd('UWRC_IndirectFire', NAPALM_RADIUS_ADD),
                unapply = WeaponDamageRadiusAdd('UWRC_IndirectFire', -NAPALM_RADIUS_ADD),
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
        armyRemove = function(buffId, armyIndex)
            BlackMarketArmies[armyIndex] = nil
        end,
    },
    salvage_explosion_1 = {
        method = "Unit.OnKilledUnit hook + DamageArea (explosion only, "
            .. SALVAGE_EXPLOSION_CHANCE .. "% chance)",
        armyApply = function(buffId, armyIndex)
            SalvageExplosionArmies[armyIndex] = true
            LOG("FAF_BUFF_DRAFT: salvage_explosion_1 reclaim bonus skipped: wreckage"
                .. " values come from the victim blueprint at death, no safe per-instance API")
        end,
        armyRemove = function(buffId, armyIndex)
            SalvageExplosionArmies[armyIndex] = nil
        end,
    },
    orbital_lance_1 = {
        method = "active buff framework: Activate -> click map -> shield-aware DamageArea"
            .. " pulses (unsafe sky projectile/beam path disabled), "
            .. ORBITAL_LANCE_COOLDOWN .. "s cooldown; auto-target fallback without a point",
        armyApply = function(buffId, armyIndex)
            RegisterActiveBuff(armyIndex, buffId)
        end,
        armyRemove = function(buffId, armyIndex)
            UnregisterActiveBuff(armyIndex, buffId)
        end,
    },
    chain_lightning_weapons_1 = {
        method = "per-weapon ChangeDamage + AddDamageRadiusMod on beam weapons"
            .. " (BeamLifetime blueprint marker)",
        skipped = "skipped true chaining because arcing needs custom projectile/collision"
            .. " scripts; approximated with x" .. CHAIN_BEAM_DAMAGE_MULT .. " damage"
            .. " + " .. CHAIN_BEAM_RADIUS_ADD .. " splash on beam/laser weapons",
        parts = { {
            name = 'BuffDraftChainLightning1', kind = 'custom',
            apply = BeamWeaponBoost(CHAIN_BEAM_DAMAGE_MULT, CHAIN_BEAM_RADIUS_ADD),
            unapply = BeamWeaponBoost(1 / CHAIN_BEAM_DAMAGE_MULT, -CHAIN_BEAM_RADIUS_ADD),
            category = categories.ALLUNITS, when = 'built',
        } },
    },
    -- reclaim SPEED, not yield: reclaim rate is driven by build rate, so a
    -- conditional BuildRate buff while the reclaim command runs makes reclaiming
    -- faster; the total amount reclaimed does not change
    reclaim_bonus_1 = {
        method = "OnStartReclaim-conditional buff system BuildRate (x"
            .. RECLAIM_RATE_MULT .. " reclaim speed)",
        skipped = "skipped yield increase because reclaim value lives on props / the"
            .. " engine reclaim command; approximated with faster reclaiming only",
        conditionalReclaim = {
            name = 'BuffDraftReclaimRate1', buffType = 'BUFFDRAFTRECLAIMRATE',
            builderCategory = categories.ENGINEER,
            active = {},
        },
    },
    -- approximation: true multi-missile salvos are blueprint-only (MuzzleSalvoSize),
    -- so emulate "more missiles in the air" with faster firing + faster missile
    -- construction. RoF goes through CombinedWeaponMult, so it stacks with the
    -- range mults of tactical_range_1 / tactical_supremacy_1 on the same weapon.
    missile_storm_1 = {
        method = "per-weapon ChangeRateOfFire + buff system BuildRate (missile construction)",
        skipped = "MuzzleSalvoSize skipped: weapon blueprint data, no per-instance salvo API;"
            .. " approximated with x" .. MISSILE_STORM_ROF_MULT .. " rate of fire"
            .. " + x" .. MISSILE_STORM_BUILD_MULT .. " missile build rate",
        parts = {
            {
                name = 'BuffDraftMissileStormRoF1', kind = 'custom',
                apply = WeaponRateOfFireMult(nil, MISSILE_STORM_ROF_MULT),
                unapply = WeaponRateOfFireMult(nil, 1 / MISSILE_STORM_ROF_MULT),
                category = categories.TACTICALMISSILEPLATFORM, when = 'built',
            },
            {
                name = 'BuffDraftMissileStormBuild1', kind = 'buff', buffType = 'BUFFDRAFTMSSTORMBUILD',
                category = categories.TACTICALMISSILEPLATFORM, when = 'create',
            },
        },
    },
    tactical_supremacy_1 = {
        method = "per-weapon ChangeMaxRadius + buff system BuildRate (missile construction)",
        parts = {
            {
                name = 'BuffDraftTacSupremacyRange1', kind = 'custom',
                apply = WeaponRangeMult(nil, TAC_SUPREMACY_RANGE_MULT),
                unapply = WeaponRangeMult(nil, 1 / TAC_SUPREMACY_RANGE_MULT),
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
                unapply = WeaponDamageMult(nil, 1 / AIR_SUP_DAMAGE_MULT),
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
                unapply = WeaponRangeMult(nil, 1 / DREADNOUGHT_RANGE_MULT),
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
-- conditional-reclaim entries for the OnStartReclaim/OnStopReclaim hooks
local ConditionalReclaimEntries = {}
for _, spec in BuffSpecs do
    if spec.conditionalBuild then
        table.insert(ConditionalBuildEntries, spec.conditionalBuild)
    end
    if spec.conditionalReclaim then
        table.insert(ConditionalReclaimEntries, spec.conditionalReclaim)
    end
end

-- every catalog buff currently has a spec; kept for future buffs without a safe API
local NotImplementedReasons = {}

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
    if part.refreshProduction then
        RefreshProductionValuesNextTick(unit)
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
    if spec.skipped then
        -- part of the described effect has no safe API; say what and why
        LOG("FAF_BUFF_DRAFT: " .. buffId .. " " .. spec.skipped)
    end
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

    if spec.conditionalReclaim then
        for _, armyIndex in armies do
            spec.conditionalReclaim.active[armyIndex] = true
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

local function RemovePartFromUnit(buffId, part, unit)
    if part.kind == 'buff' then
        Buff.RemoveBuff(unit, part.name, true) -- guarded by HasBuffApplied at the call site
    else
        if not part.unapply then
            return false
        end
        part.unapply(unit)
        if unit.BuffDraftApplied then
            unit.BuffDraftApplied[part.name] = nil
        end
    end
    return true
end

--- SIM API (admin): inverse of ApplyPickedBuff. Deactivates the buff for future
--- units and strips it from current units; army-level effects (spawn threads,
--- kill flags, active abilities) are stopped via the spec's armyRemove. Returns
--- fullyRemoved plus a notes string for the log. Already-spawned free units,
--- already-granted resources and running timed buffs (they expire on their own)
--- are NOT rolled back.
function RemovePickedBuff(sideName, armies, buffId)
    local spec = BuffSpecs[buffId]
    if not spec then
        return false, "no effect spec - nothing was ever applied"
    end

    local fully = true
    local notes = {}

    for _, part in spec.parts or {} do
        -- future units: deactivate the army flags first
        for _, armyIndex in armies do
            part.active[armyIndex] = nil
        end
        -- current units
        if part.kind == 'custom' and not part.unapply then
            fully = false
            table.insert(notes, part.name .. " has no unapply, disabled for future units only")
        else
            for _, armyIndex in armies do
                local brain = ArmyBrains[armyIndex]
                if brain then
                    for _, unit in brain:GetListOfUnits(part.category, false, false) or {} do
                        if (not unit.Dead) and HasBuffApplied(unit, part) then
                            RemovePartFromUnit(buffId, part, unit)
                        end
                    end
                end
            end
        end
    end

    -- conditional build/reclaim buffs: deactivate and strip from anyone holding one
    for _, entry in { spec.conditionalBuild, spec.conditionalReclaim } do
        for _, armyIndex in armies do
            entry.active[armyIndex] = nil
            local brain = ArmyBrains[armyIndex]
            if brain then
                for _, unit in brain:GetListOfUnits(entry.builderCategory, false, false) or {} do
                    if (not unit.Dead) and HasBuffOfType(unit, entry.buffType, entry.name) then
                        Buff.RemoveBuff(unit, entry.name, true)
                    end
                end
            end
        end
    end

    -- army-level effects
    if spec.armyApply then
        if spec.armyRemove then
            for _, armyIndex in armies do
                spec.armyRemove(buffId, armyIndex)
                if spec.armyApplied then
                    spec.armyApplied[armyIndex] = nil -- allow a later re-grant to re-apply
                end
            end
        else
            fully = false
            table.insert(notes, "army-level effect has no remove")
        end
    end

    if buffId == 'drone_foundry_1' or buffId == 'engineer_swarm_1' then
        table.insert(notes, "already spawned units stay")
    end
    if buffId == 'rapid_deployment_1' then
        table.insert(notes, "running 60s speed buffs expire on their own")
    end

    return fully, table.concat(notes, "; ")
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

--- Called from the Unit.OnStartReclaim hook: engineers with reclaim_bonus_1 get a
--- BuildRate buff for the duration of the reclaim (reclaim rate follows build rate).
function OnUnitStartReclaim(unit)
    if (not unit) or (not unit.Army) then
        return
    end
    for _, entry in ConditionalReclaimEntries do
        if entry.active[unit.Army] and EntityCategoryContains(entry.builderCategory, unit) then
            Buff.ApplyBuff(unit, entry.name)
        end
    end
end

--- Called from the Unit.OnStopReclaim hook: removes the reclaim-speed buff.
function OnUnitStopReclaim(unit)
    if (not unit) or (not unit.Army) then
        return
    end
    for _, entry in ConditionalReclaimEntries do
        if entry.active[unit.Army] and HasBuffOfType(unit, entry.buffType, entry.name) then
            Buff.RemoveBuff(unit, entry.name, true)
        end
    end
end

--- Called from the Unit.OnKilledUnit hook.
--- Black market bounty: killing an enemy grants a fraction of its blueprint cost
--- (GiveResource caps at storage). Salvage explosion: chance that the killed enemy
--- detonates - a plain DamageArea at the victim position (same call DefaultDamage /
--- EffectUtilities use); wreckage/reclaim values are untouched.
function OnUnitKilledUnit(killer, victim)
    if (not killer) or (not killer.Army) or (not victim) or (not victim.Army) then
        return
    end
    if not IsEnemy(killer.Army, victim.Army) then
        return
    end

    if BlackMarketArmies[killer.Army] then
        local brain = ArmyBrains[killer.Army]
        if brain then
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
    end

    if SalvageExplosionArmies[killer.Army] and Random(1, 100) <= SALVAGE_EXPLOSION_CHANCE then
        local pos = victim:GetPosition()
        if pos then
            -- damageFriendly=false: the killer's own side takes no damage
            DamageArea(killer, pos, SALVAGE_EXPLOSION_RADIUS, SALVAGE_EXPLOSION_DAMAGE,
                'Normal', false)
            LOG("FAF_BUFF_DRAFT: salvage_explosion_1 explosion triggered at victim "
                .. UnitLabel(victim) .. " (r=" .. tostring(SALVAGE_EXPLOSION_RADIUS)
                .. " dmg=" .. tostring(SALVAGE_EXPLOSION_DAMAGE) .. ")")
        end
    end
end

--#endregion
