-- BuffDraft: data-only buff catalog, shared by SIM (draft pool) and UI (tooltips).
-- No gameplay logic here. `target` is a hint about what the buff affects; `effect`
-- is the human-readable effect detail shown in tooltips. Effect strings are built
-- from the balance knobs in config.lua (same nil-safe defaults as effects.lua),
-- so tuning a value there updates both the gameplay and what the player reads.
-- Buffs whose effect says "Not implemented" are draftable but do nothing.

local cfg = import('/mods/BuffDraft/lua/config.lua')

-- nil-safe knob read, same defaults as effects.lua
local function n(name, default)
    local value = cfg[name]
    if value == nil then
        return default
    end
    return value
end

-- Player-facing multiplier text. A multiplier of 2 means +100%, not +200%:
-- show the change from the original value so every percentage is unambiguous.
local function percentChange(mult)
    local value = (mult - 1) * 100
    if value > 0 then
        return "+" .. string.format("%g", value) .. "%"
    end
    return string.format("%g", value) .. "%"
end

local function percentValue(fraction)
    return string.format("%g", fraction * 100) .. "%"
end

BuffCatalog = {
    -- original buffs
    { id = "engineer_build_speed_1", title = "Engineer Rush", description = "Engineers (excluding ACUs) gain " .. percentChange(n('ENGINEER_BUILD_RATE_MULT', 5)) .. " build rate.", effect = percentChange(n('ENGINEER_BUILD_RATE_MULT', 5)) .. " engineer build rate; ACUs are not affected.", target = "engineers" },
    { id = "land_rate_of_fire_1", title = "Land Rate of Fire I", description = "Mobile land units gain " .. percentChange(n('LAND_ROF_MULT', 2)) .. " rate of fire on direct-fire weapons.", effect = percentChange(n('LAND_ROF_MULT', 2)) .. " direct-fire weapon rate of fire on mobile land units.", target = "land" },
    { id = "shield_health_1", title = "Shield Health I", description = "Structure shield generators gain " .. percentChange(n('SHIELD_HEALTH_MULT', 2)) .. " maximum shield HP.", effect = percentChange(n('SHIELD_HEALTH_MULT', 2)) .. " maximum shield HP on shield structures.", target = "shields" },
    { id = "tactical_range_1", title = "Tactical Range I", description = "Tactical missile launchers gain " .. percentChange(n('TACTICAL_RANGE_MULT', 2)) .. " weapon range.", effect = percentChange(n('TACTICAL_RANGE_MULT', 2)) .. " weapon range on tactical missile launchers.", target = "tactical" },
    { id = "eco_overclock_1", title = "Eco Overclock I", description = "Economy structures gain " .. percentChange(n('ECO_PRODUCTION_MULT', 2.5)) .. " mass and energy production.", effect = percentChange(n('ECO_PRODUCTION_MULT', 2.5)) .. " mass and energy production on the corresponding production structures.", target = "economy" },
    { id = "air_speed_1", title = "Air Speed I", description = "Mobile air units gain " .. percentChange(n('AIR_SPEED_MULT', 1.25)) .. " movement speed, acceleration and turn rate.", effect = percentChange(n('AIR_SPEED_MULT', 1.25)) .. " speed, acceleration and turn rate on mobile air units.", target = "air" },
    { id = "naval_armor_1", title = "Naval Armor I", description = "Mobile naval units gain " .. percentChange(n('NAVAL_ARMOR_MULT', 2.5)) .. " maximum HP.", effect = percentChange(n('NAVAL_ARMOR_MULT', 2.5)) .. " maximum HP on mobile naval units.", target = "naval" },
    { id = "acu_regen_1", title = "ACU Regeneration I", description = "ACUs gain +" .. n('ACU_REGEN_ADD', 60) .. " HP per second of regeneration.", effect = "+" .. n('ACU_REGEN_ADD', 60) .. " HP/s regeneration on ACUs (flat bonus, not a percentage).", target = "acu" },
    { id = "artillery_range_1", title = "Artillery Range I", description = "Artillery gains " .. percentChange(n('ARTILLERY_RANGE_MULT', 1.5)) .. " range on indirect-fire weapons.", effect = percentChange(n('ARTILLERY_RANGE_MULT', 1.5)) .. " indirect-fire weapon range on artillery.", target = "artillery" },
    { id = "factory_build_speed_1", title = "Factory Build Speed I", description = "Factories gain " .. percentChange(n('FACTORY_BUILD_RATE_MULT', 3)) .. " build rate.", effect = percentChange(n('FACTORY_BUILD_RATE_MULT', 3)) .. " factory build rate.", target = "factories" },
    { id = "radar_vision_1", title = "Radar Vision I", description = "Radar units gain " .. percentChange(n('RADAR_RADIUS_MULT', 2)) .. " radar radius; scouts gain " .. percentChange(n('SCOUT_VISION_MULT', 2)) .. " vision radius.", effect = percentChange(n('RADAR_RADIUS_MULT', 2)) .. " radar radius on radar units and " .. percentChange(n('SCOUT_VISION_MULT', 2)) .. " vision radius on scouts.", target = "intel" },
    { id = "experimentals_health_1", title = "Experimental Health I", description = "Experimental units gain " .. percentChange(n('EXPERIMENTAL_HEALTH_MULT', 2)) .. " maximum HP.", effect = percentChange(n('EXPERIMENTAL_HEALTH_MULT', 2)) .. " maximum HP on experimental units.", target = "experimentals" },
    { id = "mobile_shields_1", title = "Mobile Shields I", description = "Mobile shield generators gain " .. percentChange(n('MOBILE_SHIELD_HEALTH_MULT', 2)) .. " maximum shield HP.", effect = percentChange(n('MOBILE_SHIELD_HEALTH_MULT', 2)) .. " maximum shield HP on mobile shield units.", target = "mobile_shields" },
    { id = "anti_air_damage_1", title = "Anti-Air Damage I", description = "Anti-air weapons gain " .. percentChange(n('ANTIAIR_DAMAGE_MULT', 2.5)) .. " damage.", effect = percentChange(n('ANTIAIR_DAMAGE_MULT', 2.5)) .. " damage on anti-air weapons.", target = "anti_air" },
    { id = "reclaim_bonus_1", title = "Reclaim Bonus I", description = "Engineers gain " .. percentChange(n('RECLAIM_RATE_MULT', 2)) .. " reclaim speed; total reclaim yield is unchanged.", effect = percentChange(n('RECLAIM_RATE_MULT', 2)) .. " reclaim speed while engineers reclaim. Total mass and energy yield is unchanged.", target = "reclaim" },

    -- new buffs
    { id = "drone_foundry_1", title = "Drone Foundry", description = "Every " .. n('DRONE_FOUNDRY_INTERVAL', 45) .. " seconds, up to " .. n('DRONE_FOUNDRY_MAX_PER_WAVE', 4) .. " completed land factories each spawn one free faction T1 tank.", effect = "One free T1 tank per eligible factory every " .. n('DRONE_FOUNDRY_INTERVAL', 45) .. "s; maximum " .. n('DRONE_FOUNDRY_MAX_PER_WAVE', 4) .. " factories per wave.", target = "factories" },
    { id = "engineer_swarm_1", title = "Engineer Swarm", description = "Every " .. n('ENGINEER_SWARM_INTERVAL', 60) .. " seconds, up to " .. n('ENGINEER_SWARM_MAX_PER_WAVE', 2) .. " completed land factories each spawn one free T1 engineer.", effect = "One free T1 engineer per eligible factory every " .. n('ENGINEER_SWARM_INTERVAL', 60) .. "s; maximum " .. n('ENGINEER_SWARM_MAX_PER_WAVE', 2) .. " factories per wave.", target = "factories" },
    { id = "emergency_fabrication_1", title = "Emergency Fabrication", description = "Engineers gain " .. percentChange(n('EMERGENCY_FAB_BUILD_MULT', 3)) .. " build rate while constructing defensive structures.", effect = percentChange(n('EMERGENCY_FAB_BUILD_MULT', 3)) .. " engineer build rate only while the target is a defensive structure.", target = "engineers" },
    { id = "overcharged_shields_1", title = "Overcharged Shields", description = "All shielded units gain " .. percentChange(n('OVERCHARGED_SHIELD_MULT', 2.5)) .. " maximum shield HP; shield recharge is unchanged.", effect = percentChange(n('OVERCHARGED_SHIELD_MULT', 2.5)) .. " maximum shield HP on all shielded units. Recharge is unchanged.", target = "shields" },
    { id = "napalm_rounds_1", title = "Napalm Rounds", description = "Direct-fire land and artillery weapons gain +" .. n('NAPALM_RADIUS_ADD', 1) .. " splash radius; no damage-over-time effect.", effect = "+" .. n('NAPALM_RADIUS_ADD', 1) .. " world units of damage radius (flat bonus, not a percentage). No damage over time.", target = "land" },
    { id = "teleport_doctrine_1", title = "Teleport Doctrine", description = "ACUs, SCUs and engineers gain " .. percentChange(n('TELEPORT_SPEED_MULT', 2)) .. " movement speed; teleporting is unchanged.", effect = percentChange(n('TELEPORT_SPEED_MULT', 2)) .. " movement speed on ACUs, SCUs and engineers. This does not modify teleporting.", target = "engineers" },
    { id = "missile_storm_1", title = "Missile Storm", description = "Tactical missile launchers gain " .. percentChange(n('MISSILE_STORM_ROF_MULT', 2.5)) .. " rate of fire and " .. percentChange(n('MISSILE_STORM_BUILD_MULT', 2.5)) .. " missile build rate.", effect = percentChange(n('MISSILE_STORM_ROF_MULT', 2.5)) .. " rate of fire and " .. percentChange(n('MISSILE_STORM_BUILD_MULT', 2.5)) .. " missile construction rate. Salvo size is unchanged.", target = "tactical" },
    { id = "orbital_lance_1", title = "Orbital Lance", description = "Active strike: " .. n('ORBITAL_LANCE_TICKS', 5) .. " pulses of " .. n('ORBITAL_LANCE_TICK_DAMAGE', 800) .. " damage (" .. (n('ORBITAL_LANCE_TICKS', 5) * n('ORBITAL_LANCE_TICK_DAMAGE', 800)) .. " total), radius " .. n('ORBITAL_LANCE_RADIUS', 5) .. ", cooldown " .. n('ORBITAL_LANCE_COOLDOWN', 90) .. " seconds.", effect = "Activate and click the map: " .. n('ORBITAL_LANCE_TICKS', 5) .. " x " .. n('ORBITAL_LANCE_TICK_DAMAGE', 800) .. " damage pulses over about " .. string.format("%g", (n('ORBITAL_LANCE_TICKS', 5) - 1) * n('ORBITAL_LANCE_TICK_INTERVAL', 0.4)) .. "s, radius " .. n('ORBITAL_LANCE_RADIUS', 5) .. ", " .. n('ORBITAL_LANCE_COOLDOWN', 90) .. "s cooldown. Shields block or reduce ground damage; unshielded impact damages both sides.", target = "special" },
    { id = "nano_swarm_1", title = "Nano Swarm", description = "All units gain +" .. n('NANO_REGEN_ADD', 5) .. " HP per second of permanent regeneration.", effect = "+" .. n('NANO_REGEN_ADD', 5) .. " HP/s regeneration on all units (flat bonus, not a percentage; always active).", target = "all" },
    { id = "experimental_discount_1", title = "Experimental Assembly", description = "Builders gain " .. percentChange(n('EXP_DISCOUNT_BUILD_MULT', 2.5)) .. " build rate while constructing experimentals; resource cost is unchanged.", effect = percentChange(n('EXP_DISCOUNT_BUILD_MULT', 2.5)) .. " build rate only while building an experimental. Mass and energy cost is unchanged.", target = "experimentals" },
    { id = "rapid_deployment_1", title = "Rapid Deployment", description = "Mobile units completed after this pick gain " .. percentChange(n('RAPID_SPEED_MULT', 2)) .. " movement speed for " .. n('RAPID_DURATION', 60) .. " seconds.", effect = percentChange(n('RAPID_SPEED_MULT', 2)) .. " movement speed for " .. n('RAPID_DURATION', 60) .. "s on newly completed mobile units only.", target = "mobile" },
    { id = "fortress_protocol_1", title = "Fortress Protocol", description = "Structures gain " .. percentChange(n('FORTRESS_HP_MULT', 3)) .. " maximum HP; mobile units suffer " .. percentChange(n('FORTRESS_SPEED_MULT', 0.85)) .. " movement speed.", effect = percentChange(n('FORTRESS_HP_MULT', 3)) .. " maximum HP on structures and " .. percentChange(n('FORTRESS_SPEED_MULT', 0.85)) .. " movement speed on mobile units.", target = "structures" },
    { id = "hunter_protocol_1", title = "Hunter Protocol", description = "Mobile units gain " .. percentChange(n('HUNTER_VISION_MULT', 2)) .. " vision and " .. percentChange(n('HUNTER_SPEED_MULT', 1.5)) .. " speed; mobile radar units also gain " .. percentChange(n('HUNTER_RADAR_MULT', 2)) .. " radar radius.", effect = percentChange(n('HUNTER_VISION_MULT', 2)) .. " vision and " .. percentChange(n('HUNTER_SPEED_MULT', 1.5)) .. " movement speed on mobile units; " .. percentChange(n('HUNTER_RADAR_MULT', 2)) .. " radar radius on mobile radar units.", target = "mobile" },
    { id = "black_market_economy_1", title = "Black Market Economy", description = "Each enemy kill grants " .. percentValue(n('BLACK_MARKET_MASS_FRACTION', 0.1)) .. " of the victim's mass cost and " .. percentValue(n('BLACK_MARKET_ENERGY_FRACTION', 0.1)) .. " of its energy cost.", effect = percentValue(n('BLACK_MARKET_MASS_FRACTION', 0.1)) .. " of killed enemy mass cost and " .. percentValue(n('BLACK_MARKET_ENERGY_FRACTION', 0.1)) .. " of energy cost paid to the killer's army.", target = "economy" },
    { id = "chain_lightning_weapons_1", title = "Chain Lightning", description = "Beam and laser weapons gain " .. percentChange(n('CHAIN_BEAM_DAMAGE_MULT', 1.5)) .. " damage and +" .. n('CHAIN_BEAM_RADIUS_ADD', 1.5) .. " splash radius; damage does not chain.", effect = percentChange(n('CHAIN_BEAM_DAMAGE_MULT', 1.5)) .. " beam/laser damage and +" .. n('CHAIN_BEAM_RADIUS_ADD', 1.5) .. " world units of splash radius. No true chain effect.", target = "land" },
    { id = "tactical_supremacy_1", title = "Tactical Supremacy", description = "Tactical missile launchers gain " .. percentChange(n('TAC_SUPREMACY_RANGE_MULT', 3)) .. " range and " .. percentChange(n('TAC_SUPREMACY_BUILD_MULT', 2)) .. " missile build rate.", effect = percentChange(n('TAC_SUPREMACY_RANGE_MULT', 3)) .. " weapon range and " .. percentChange(n('TAC_SUPREMACY_BUILD_MULT', 2)) .. " missile construction rate on tactical launchers.", target = "tactical" },
    { id = "air_superiority_1", title = "Air Superiority", description = "Mobile air units gain " .. percentChange(n('AIR_SUP_SPEED_MULT', 2)) .. " speed and " .. percentChange(n('AIR_SUP_DAMAGE_MULT', 1.5)) .. " weapon damage, but suffer " .. percentChange(n('AIR_SUP_HP_MULT', 0.75)) .. " maximum HP.", effect = percentChange(n('AIR_SUP_SPEED_MULT', 2)) .. " movement speed, " .. percentChange(n('AIR_SUP_DAMAGE_MULT', 1.5)) .. " all-weapon damage and " .. percentChange(n('AIR_SUP_HP_MULT', 0.75)) .. " maximum HP on mobile air units.", target = "air" },
    { id = "naval_dreadnoughts_1", title = "Naval Dreadnoughts", description = "Mobile naval units gain " .. percentChange(n('DREADNOUGHT_HP_MULT', 3)) .. " maximum HP and " .. percentChange(n('DREADNOUGHT_RANGE_MULT', 1.5)) .. " weapon range.", effect = percentChange(n('DREADNOUGHT_HP_MULT', 3)) .. " maximum HP and " .. percentChange(n('DREADNOUGHT_RANGE_MULT', 1.5)) .. " range on all weapons of mobile naval units.", target = "naval" },
    { id = "radar_omniscience_1", title = "Radar Omniscience", description = "Omni-equipped ACUs and T3 radar gain " .. percentChange(n('OMNISCIENCE_OMNI_MULT', 3)) .. " omni radius; T3 radar also gains " .. percentChange(n('OMNISCIENCE_RADAR_MULT', 2.5)) .. " radar radius.", effect = percentChange(n('OMNISCIENCE_OMNI_MULT', 3)) .. " omni radius on omni-equipped ACUs and T3 radar structures; " .. percentChange(n('OMNISCIENCE_RADAR_MULT', 2.5)) .. " radar radius on T3 radar structures.", target = "intel" },
    { id = "salvage_explosion_1", title = "Salvage Explosion", description = "Enemy kills have a " .. n('SALVAGE_EXPLOSION_CHANCE', 25) .. "% chance to explode for " .. n('SALVAGE_EXPLOSION_DAMAGE', 150) .. " damage in radius " .. n('SALVAGE_EXPLOSION_RADIUS', 3) .. "; no friendly fire.", effect = n('SALVAGE_EXPLOSION_CHANCE', 25) .. "% chance per killed enemy: " .. n('SALVAGE_EXPLOSION_DAMAGE', 150) .. " area damage, radius " .. n('SALVAGE_EXPLOSION_RADIUS', 3) .. ", no friendly fire. Reclaim yield is unchanged.", target = "economy" },

    -- mythic buffs
    { id = "paragon_singularity_1", title = "Paragon Singularity", description = "Gain adaptive income exactly like a Paragon without constructing one: at least " .. n('PARAGON_MIN_MASS_PER_SECOND', 20) .. " mass/s and " .. n('PARAGON_MIN_ENERGY_PER_SECOND', 1000) .. " energy/s, scaling to current demand.", effect = "Continuously covers resource demand up to " .. n('PARAGON_MAX_MASS_PER_SECOND', 10000) .. " mass/s and " .. n('PARAGON_MAX_ENERGY_PER_SECOND', 1000000) .. " energy/s per affected army, using the stock Paragon production formula.", target = "economy" },
    { id = "commander_apotheosis_1", title = "Commander Apotheosis", description = "Unlocks four stackable packages representing all 46 ACU enhancements from every faction, including normally conflicting paths. The special panel shows every exact percentage, flat bonus, summed cost and build time.", effect = "All four packages can coexist. Chassis-specific upgrades use explicit per-instance equivalents for maximum HP, HP/s regeneration, build rate, resource production, weapon damage/rate/range, intel, cloak, teleport and regeneration aura without globally mutating commander blueprints.", target = "acu" },
    { id = "nuclear_apocalypse_1", title = "Nuclear Apocalypse", description = "All strategic nuclear warheads gain " .. percentChange(n('NUCLEAR_DAMAGE_MULT', 6)) .. " inner/outer-ring damage and " .. percentChange(n('NUCLEAR_RADIUS_MULT', 3)) .. " blast radius; nuclear launchers gain " .. percentChange(n('NUCLEAR_BUILD_RATE_MULT', 1.5)) .. " missile build rate.", effect = percentChange(n('NUCLEAR_DAMAGE_MULT', 6)) .. " nuclear ring damage, " .. percentChange(n('NUCLEAR_RADIUS_MULT', 3)) .. " inner and outer blast radius, and " .. percentChange(n('NUCLEAR_BUILD_RATE_MULT', 1.5)) .. " nuke construction rate. Applied per launcher/projectile without blueprint mutation.", target = "nuclear" },
}

-- Rarity tiers (see "Buff rarity tiers" in docs/FINDINGS.md). Anything not
-- listed here is "common". Merged into the catalog entries below, so both the
-- sim draft generation and the UI read `buff.rarity` from one source.
BuffRarityTiers = {
    -- mythic: unique game-warping systems; rolled only by the dedicated tier
    paragon_singularity_1 = "mythic",
    commander_apotheosis_1 = "mythic",
    nuclear_apocalypse_1 = "mythic",
    -- legendary: game-changing army-wide or free-unit effects
    orbital_lance_1 = "legendary",
    fortress_protocol_1 = "legendary",
    air_superiority_1 = "legendary",
    naval_dreadnoughts_1 = "legendary",
    tactical_supremacy_1 = "legendary",
    experimental_discount_1 = "legendary",
    drone_foundry_1 = "legendary",
    engineer_swarm_1 = "legendary",
    -- rare: strong broad bonuses / army-wide tempo
    engineer_build_speed_1 = "rare",
    factory_build_speed_1 = "rare",
    land_rate_of_fire_1 = "rare",
    eco_overclock_1 = "rare",
    naval_armor_1 = "rare",
    experimentals_health_1 = "rare",
    overcharged_shields_1 = "rare",
    napalm_rounds_1 = "rare",
    missile_storm_1 = "rare",
    nano_swarm_1 = "rare",
    rapid_deployment_1 = "rare",
    hunter_protocol_1 = "rare",
    black_market_economy_1 = "rare",
    -- everything else: common (narrow/utility/situational)
}

for _, buff in BuffCatalog do
    buff.rarity = BuffRarityTiers[buff.id] or "common"
end

-- Display-only implementation status for the admin panel; kept in sync with the
-- "Buff implementation matrix" in docs/FINDINGS.md. Anything not listed here is
-- "implemented". "active" = player-triggered ability with a cooldown.
BuffStatus = {
    orbital_lance_1 = "active",
    overcharged_shields_1 = "partial",
    napalm_rounds_1 = "partial",
    teleport_doctrine_1 = "partial",
    nano_swarm_1 = "partial",
    experimental_discount_1 = "partial",
    missile_storm_1 = "partial",
    salvage_explosion_1 = "partial",
    chain_lightning_weapons_1 = "partial",
    reclaim_bonus_1 = "partial",
}
