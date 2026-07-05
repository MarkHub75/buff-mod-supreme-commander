-- BuffDraft: data-only buff catalog, shared by SIM (draft pool) and UI (tooltips).
-- No gameplay logic here. `target` is a hint about what the buff affects; `effect`
-- is the human-readable effect detail shown in the history tooltip and must stay in
-- sync with the multiplier constants in effects.lua. Buffs whose effect says
-- "Not implemented" are draftable but currently do nothing (effects.lua logs why).

BuffCatalog = {
    -- original buffs (multipliers boosted for the 10-minute draft cadence)
    { id = "engineer_build_speed_1", title = "Engineer Rush", description = "Engineers of this side build 500% faster.", effect = "x5 build rate on engineers (not the ACU).", target = "engineers" },
    { id = "land_rate_of_fire_1", title = "Land Rate of Fire I", description = "Land units fire twice as fast.", effect = "x2 rate of fire on direct-fire weapons of mobile land units.", target = "land" },
    { id = "shield_health_1", title = "Shield Health I", description = "Shield generators project much stronger shields.", effect = "x2 shield HP on structure shield generators.", target = "shields" },
    { id = "tactical_range_1", title = "Tactical Range I", description = "Tactical missile launchers have double range.", effect = "x2 weapon range on tactical missile launchers.", target = "tactical" },
    { id = "eco_overclock_1", title = "Eco Overclock I", description = "Mass and energy production is greatly increased.", effect = "x2.5 mass and energy production on structures.", target = "economy" },
    { id = "air_speed_1", title = "Air Speed I", description = "Air units move twice as fast.", effect = "x2 speed, acceleration and turn rate on mobile air units.", target = "air" },
    { id = "naval_armor_1", title = "Naval Armor I", description = "Naval units are much tougher.", effect = "x2.5 max HP on mobile naval units.", target = "naval" },
    { id = "acu_regen_1", title = "ACU Regeneration I", description = "The ACU regenerates health much faster.", effect = "+60 HP/s regeneration on the ACU.", target = "acu" },
    { id = "artillery_range_1", title = "Artillery Range I", description = "Artillery has more range.", effect = "x1.5 range on indirect-fire weapons of artillery.", target = "artillery" },
    { id = "factory_build_speed_1", title = "Factory Build Speed I", description = "Factories build three times faster.", effect = "x3 build rate on factories.", target = "factories" },
    { id = "radar_vision_1", title = "Radar Vision I", description = "Radar and vision radius is doubled.", effect = "x2 radar radius on radar units; x2 vision radius on scouts.", target = "intel" },
    { id = "experimentals_health_1", title = "Experimental Health I", description = "Experimental units are twice as tough.", effect = "x2 max HP on experimentals.", target = "experimentals" },
    { id = "mobile_shields_1", title = "Mobile Shields I", description = "Mobile shield generators are much stronger.", effect = "x2 shield HP on mobile shield units.", target = "mobile_shields" },
    { id = "anti_air_damage_1", title = "Anti-Air Damage I", description = "Anti-air weapons deal much more damage.", effect = "x2.5 damage on anti-air weapons.", target = "anti_air" },
    { id = "reclaim_bonus_1", title = "Reclaim Bonus I", description = "Reclaiming yields more resources.", effect = "Not implemented: reclaim yield lives on props, no per-unit API.", target = "reclaim" },

    -- new buffs
    { id = "drone_foundry_1", title = "Drone Foundry", description = "Land factories periodically field a free light tank.", effect = "Every 45s up to 4 finished land factories each spawn a free faction T1 tank nearby.", target = "factories" },
    { id = "engineer_swarm_1", title = "Engineer Swarm", description = "Land factories periodically field a free T1 engineer.", effect = "Every 60s up to 2 finished land factories each spawn a free T1 engineer nearby.", target = "factories" },
    { id = "emergency_fabrication_1", title = "Emergency Fabrication", description = "Engineers raise defensive structures far faster.", effect = "x3 build rate while an engineer is building a defensive structure.", target = "engineers" },
    { id = "overcharged_shields_1", title = "Overcharged Shields", description = "All shields are massively reinforced.", effect = "x2.5 shield HP on all shielded units. Recharge unchanged (no safe API).", target = "shields" },
    { id = "napalm_rounds_1", title = "Napalm Rounds", description = "Tank and artillery shells splash over a small area.", effect = "+1 damage radius on direct-fire land weapons and artillery. No DoT (blueprint-only).", target = "land" },
    { id = "teleport_doctrine_1", title = "Teleport Doctrine", description = "Command units and engineers redeploy far faster.", effect = "x2 movement speed on ACU, SCUs and engineers. Teleport itself has no safe API.", target = "engineers" },
    { id = "missile_storm_1", title = "Missile Storm", description = "Tactical launchers fire multiple missiles per volley.", effect = "Not implemented: salvo size is weapon blueprint data, no per-instance API.", target = "tactical" },
    { id = "orbital_lance_1", title = "Orbital Lance", description = "Call down an orbital beam on a target point.", effect = "Not implemented: needs target-point UI and a custom strike. TODO.", target = "special" },
    { id = "nano_swarm_1", title = "Nano Swarm", description = "Nanobots slowly repair all your units.", effect = "+5 HP/s regeneration on all units, always on (out-of-combat detection unsafe).", target = "all" },
    { id = "experimental_discount_1", title = "Experimental Assembly", description = "Experimental construction is much faster.", effect = "x2.5 build rate while building an experimental. Cost unchanged (blueprint-only).", target = "experimentals" },
    { id = "rapid_deployment_1", title = "Rapid Deployment", description = "Freshly built units surge out at double speed.", effect = "x2 speed for 60s on mobile units built after this pick.", target = "mobile" },
    { id = "fortress_protocol_1", title = "Fortress Protocol", description = "Structures become bastions; your army slows slightly.", effect = "x3 max HP on structures; x0.85 speed on mobile units.", target = "structures" },
    { id = "hunter_protocol_1", title = "Hunter Protocol", description = "Mobile units see farther and move faster.", effect = "x2 vision on mobile units, x2 radar on mobile radar units, x1.5 speed.", target = "mobile" },
    { id = "black_market_economy_1", title = "Black Market Economy", description = "Kills pay out: destroyed enemies grant resources.", effect = "Killing an enemy unit grants 10% of its mass and energy cost.", target = "economy" },
    { id = "chain_lightning_weapons_1", title = "Chain Lightning", description = "Energy weapons arc to nearby enemies.", effect = "Not implemented: chaining needs custom projectile scripts. TODO.", target = "land" },
    { id = "tactical_supremacy_1", title = "Tactical Supremacy", description = "Tactical launchers dominate the map.", effect = "x3 range and x2 missile build rate on tactical missile launchers.", target = "tactical" },
    { id = "air_superiority_1", title = "Air Superiority", description = "A fast, hard-hitting but fragile air force.", effect = "Air units: x2 speed, x1.5 damage, x0.75 max HP.", target = "air" },
    { id = "naval_dreadnoughts_1", title = "Naval Dreadnoughts", description = "Warships become floating fortresses.", effect = "Naval units: x3 max HP, x1.5 weapon range.", target = "naval" },
    { id = "radar_omniscience_1", title = "Radar Omniscience", description = "Your intel network sees almost everything.", effect = "x3 omni radius on ACU and T3 radar; x2.5 radar radius on T3 radar.", target = "intel" },
    { id = "salvage_explosion_1", title = "Salvage Explosion", description = "Destroyed enemies leave richer salvage.", effect = "Not implemented: wreckage values come from the victim blueprint at death.", target = "economy" },
}
