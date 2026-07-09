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

BuffCatalog = {
    -- original buffs
    { id = "engineer_build_speed_1", title = "Engineer Rush", description = "Engineers of this side build " .. (n('ENGINEER_BUILD_RATE_MULT', 5) * 100) .. "% faster.", effect = "x" .. n('ENGINEER_BUILD_RATE_MULT', 5) .. " build rate on engineers (not the ACU).", target = "engineers" },
    { id = "land_rate_of_fire_1", title = "Land Rate of Fire I", description = "Land units fire much faster.", effect = "x" .. n('LAND_ROF_MULT', 2) .. " rate of fire on direct-fire weapons of mobile land units.", target = "land" },
    { id = "shield_health_1", title = "Shield Health I", description = "Shield generators project much stronger shields.", effect = "x" .. n('SHIELD_HEALTH_MULT', 2) .. " shield HP on structure shield generators.", target = "shields" },
    { id = "tactical_range_1", title = "Tactical Range I", description = "Tactical missile launchers shoot much farther.", effect = "x" .. n('TACTICAL_RANGE_MULT', 2) .. " weapon range on tactical missile launchers.", target = "tactical" },
    { id = "eco_overclock_1", title = "Eco Overclock I", description = "Mass and energy production is greatly increased.", effect = "x" .. n('ECO_PRODUCTION_MULT', 2.5) .. " mass and energy production on structures.", target = "economy" },
    { id = "air_speed_1", title = "Air Speed I", description = "Air units move faster.", effect = "x" .. n('AIR_SPEED_MULT', 1.25) .. " speed, acceleration and turn rate on mobile air units.", target = "air" },
    { id = "naval_armor_1", title = "Naval Armor I", description = "Naval units are much tougher.", effect = "x" .. n('NAVAL_ARMOR_MULT', 2.5) .. " max HP on mobile naval units.", target = "naval" },
    { id = "acu_regen_1", title = "ACU Regeneration I", description = "The ACU regenerates health much faster.", effect = "+" .. n('ACU_REGEN_ADD', 60) .. " HP/s regeneration on the ACU.", target = "acu" },
    { id = "artillery_range_1", title = "Artillery Range I", description = "Artillery has more range.", effect = "x" .. n('ARTILLERY_RANGE_MULT', 1.5) .. " range on indirect-fire weapons of artillery.", target = "artillery" },
    { id = "factory_build_speed_1", title = "Factory Build Speed I", description = "Factories build much faster.", effect = "x" .. n('FACTORY_BUILD_RATE_MULT', 3) .. " build rate on factories.", target = "factories" },
    { id = "radar_vision_1", title = "Radar Vision I", description = "Radar and vision radius is greatly increased.", effect = "x" .. n('RADAR_RADIUS_MULT', 2) .. " radar radius on radar units; x" .. n('SCOUT_VISION_MULT', 2) .. " vision radius on scouts.", target = "intel" },
    { id = "experimentals_health_1", title = "Experimental Health I", description = "Experimental units are much tougher.", effect = "x" .. n('EXPERIMENTAL_HEALTH_MULT', 2) .. " max HP on experimentals.", target = "experimentals" },
    { id = "mobile_shields_1", title = "Mobile Shields I", description = "Mobile shield generators are much stronger.", effect = "x" .. n('MOBILE_SHIELD_HEALTH_MULT', 2) .. " shield HP on mobile shield units.", target = "mobile_shields" },
    { id = "anti_air_damage_1", title = "Anti-Air Damage I", description = "Anti-air weapons deal much more damage.", effect = "x" .. n('ANTIAIR_DAMAGE_MULT', 2.5) .. " damage on anti-air weapons.", target = "anti_air" },
    { id = "reclaim_bonus_1", title = "Reclaim Bonus I", description = "Engineers reclaim wreckage much faster.", effect = "x" .. n('RECLAIM_RATE_MULT', 2) .. " reclaim speed while reclaiming (engineers). Total yield unchanged - true yield bonus has no per-unit API.", target = "reclaim" },

    -- new buffs
    { id = "drone_foundry_1", title = "Drone Foundry", description = "Land factories periodically field a free light tank.", effect = "Every " .. n('DRONE_FOUNDRY_INTERVAL', 45) .. "s up to " .. n('DRONE_FOUNDRY_MAX_PER_WAVE', 4) .. " finished land factories each spawn a free faction T1 tank nearby.", target = "factories" },
    { id = "engineer_swarm_1", title = "Engineer Swarm", description = "Land factories periodically field a free T1 engineer.", effect = "Every " .. n('ENGINEER_SWARM_INTERVAL', 60) .. "s up to " .. n('ENGINEER_SWARM_MAX_PER_WAVE', 2) .. " finished land factories each spawn a free T1 engineer nearby.", target = "factories" },
    { id = "emergency_fabrication_1", title = "Emergency Fabrication", description = "Engineers raise defensive structures far faster.", effect = "x" .. n('EMERGENCY_FAB_BUILD_MULT', 3) .. " build rate while an engineer is building a defensive structure.", target = "engineers" },
    { id = "overcharged_shields_1", title = "Overcharged Shields", description = "All shields are massively reinforced.", effect = "x" .. n('OVERCHARGED_SHIELD_MULT', 2.5) .. " shield HP on all shielded units. Recharge unchanged (no safe API).", target = "shields" },
    { id = "napalm_rounds_1", title = "Napalm Rounds", description = "Tank and artillery shells splash over a small area.", effect = "+" .. n('NAPALM_RADIUS_ADD', 1) .. " damage radius on direct-fire land weapons and artillery. No DoT (blueprint-only).", target = "land" },
    { id = "teleport_doctrine_1", title = "Teleport Doctrine", description = "Command units and engineers redeploy far faster.", effect = "x" .. n('TELEPORT_SPEED_MULT', 2) .. " movement speed on ACU, SCUs and engineers. Teleport itself has no safe API.", target = "engineers" },
    { id = "missile_storm_1", title = "Missile Storm", description = "Tactical launchers unleash missiles far more often.", effect = "Fires missiles much faster: x" .. n('MISSILE_STORM_ROF_MULT', 2.5) .. " rate of fire and x" .. n('MISSILE_STORM_BUILD_MULT', 2.5) .. " missile build rate on tactical launchers. True multi-salvo not implemented (blueprint-only).", target = "tactical" },
    { id = "orbital_lance_1", title = "Orbital Lance", description = "Call down an orbital strike on a target point.", effect = "Active ability: press Activate, then click the map - " .. n('ORBITAL_LANCE_TICKS', 5) .. " damage pulses x" .. n('ORBITAL_LANCE_TICK_DAMAGE', 800) .. " damage (radius " .. n('ORBITAL_LANCE_RADIUS', 5) .. ") over ~2s, " .. n('ORBITAL_LANCE_COOLDOWN', 90) .. "s cooldown. Ground damage is blocked/reduced by shields; unshielded impact hurts BOTH sides. Esc/right-click cancels without spending the cooldown. Without a valid point it auto-targets an identified enemy structure.", target = "special" },
    { id = "nano_swarm_1", title = "Nano Swarm", description = "Nanobots slowly repair all your units.", effect = "+" .. n('NANO_REGEN_ADD', 5) .. " HP/s regeneration on all units, always on (out-of-combat detection unsafe).", target = "all" },
    { id = "experimental_discount_1", title = "Experimental Assembly", description = "Experimental construction is much faster.", effect = "x" .. n('EXP_DISCOUNT_BUILD_MULT', 2.5) .. " build rate while building an experimental. Cost unchanged (blueprint-only).", target = "experimentals" },
    { id = "rapid_deployment_1", title = "Rapid Deployment", description = "Freshly built units surge out at high speed.", effect = "x" .. n('RAPID_SPEED_MULT', 2) .. " speed for " .. n('RAPID_DURATION', 60) .. "s on mobile units built after this pick.", target = "mobile" },
    { id = "fortress_protocol_1", title = "Fortress Protocol", description = "Structures become bastions; your army slows slightly.", effect = "x" .. n('FORTRESS_HP_MULT', 3) .. " max HP on structures; x" .. n('FORTRESS_SPEED_MULT', 0.85) .. " speed on mobile units.", target = "structures" },
    { id = "hunter_protocol_1", title = "Hunter Protocol", description = "Mobile units see farther and move faster.", effect = "x" .. n('HUNTER_VISION_MULT', 2) .. " vision on mobile units, x" .. n('HUNTER_RADAR_MULT', 2) .. " radar on mobile radar units, x" .. n('HUNTER_SPEED_MULT', 1.5) .. " speed.", target = "mobile" },
    { id = "black_market_economy_1", title = "Black Market Economy", description = "Kills pay out: destroyed enemies grant resources.", effect = "Killing an enemy unit grants " .. (n('BLACK_MARKET_MASS_FRACTION', 0.1) * 100) .. "% of its mass and " .. (n('BLACK_MARKET_ENERGY_FRACTION', 0.1) * 100) .. "% of its energy cost.", target = "economy" },
    { id = "chain_lightning_weapons_1", title = "Chain Lightning", description = "Energy beams overload and splash nearby enemies.", effect = "Beam/laser weapons: x" .. n('CHAIN_BEAM_DAMAGE_MULT', 1.5) .. " damage and +" .. n('CHAIN_BEAM_RADIUS_ADD', 1.5) .. " splash radius. True arcing not implemented (needs custom projectiles).", target = "land" },
    { id = "tactical_supremacy_1", title = "Tactical Supremacy", description = "Tactical launchers dominate the map.", effect = "x" .. n('TAC_SUPREMACY_RANGE_MULT', 3) .. " range and x" .. n('TAC_SUPREMACY_BUILD_MULT', 2) .. " missile build rate on tactical missile launchers.", target = "tactical" },
    { id = "air_superiority_1", title = "Air Superiority", description = "A fast, hard-hitting but fragile air force.", effect = "Air units: x" .. n('AIR_SUP_SPEED_MULT', 2) .. " speed, x" .. n('AIR_SUP_DAMAGE_MULT', 1.5) .. " damage, x" .. n('AIR_SUP_HP_MULT', 0.75) .. " max HP.", target = "air" },
    { id = "naval_dreadnoughts_1", title = "Naval Dreadnoughts", description = "Warships become floating fortresses.", effect = "Naval units: x" .. n('DREADNOUGHT_HP_MULT', 3) .. " max HP, x" .. n('DREADNOUGHT_RANGE_MULT', 1.5) .. " weapon range.", target = "naval" },
    { id = "radar_omniscience_1", title = "Radar Omniscience", description = "Your intel network sees almost everything.", effect = "x" .. n('OMNISCIENCE_OMNI_MULT', 3) .. " omni radius on ACU and T3 radar; x" .. n('OMNISCIENCE_RADAR_MULT', 2.5) .. " radar radius on T3 radar.", target = "intel" },
    { id = "salvage_explosion_1", title = "Salvage Explosion", description = "Destroyed enemies sometimes violently detonate.", effect = n('SALVAGE_EXPLOSION_CHANCE', 25) .. "% chance a killed enemy explodes (radius " .. n('SALVAGE_EXPLOSION_RADIUS', 3) .. ", " .. n('SALVAGE_EXPLOSION_DAMAGE', 150) .. " damage, no friendly fire). Extra reclaim not implemented (wreckage is blueprint-only).", target = "economy" },
}

-- Rarity tiers (see "Buff rarity tiers" in docs/FINDINGS.md). Anything not
-- listed here is "common". Merged into the catalog entries below, so both the
-- sim draft generation and the UI read `buff.rarity` from one source.
BuffRarityTiers = {
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
