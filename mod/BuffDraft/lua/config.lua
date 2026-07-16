-- BuffDraft: static mod configuration, shared by SIM and UI. Deterministic data
-- only: both layers import the same file on every peer, and the SIM validates
-- against its own copy, so no UI input can bypass it and nothing can desync.

-- Debug buff admin panel (UI button + BuffDraftAdminGrantBuff/RemoveBuff sim
-- callbacks). false = the Admin button is not created and the sim rejects both
-- admin callbacks.
DebugAdmin = true

-- Only the player with this nickname may see/open the admin panel and use the
-- admin callbacks. UI checks GetArmiesTable().armiesTable[focus].nickname; the
-- sim independently checks ArmyBrains[senderArmy].Nickname, so a modified UI
-- cannot bypass it. Empty string = no nickname restriction (DebugAdmin only).
AdminOwnerNickname = "Mnogoruchka"

-- AI unit transfer tool (lua/ai_control/): "Take AI" button in the admin panel
-- for the AdminOwnerNickname player - click any allied AI unit/structure (land,
-- naval, air, or building), and that exact entity transfers to the player
-- (stock SimUtils.TransferUnitsOwnership).
-- The sim re-validates everything; deleting lua/ai_control/ + false here
-- removes the tool (the callback and the button bail out).
EnableAIControl = true
AIControlTakeRadius = 30 -- legacy point-mode knob; exact-target mode does not read it
AIControlMaxUnitsPerTake = 60 -- legacy point-mode knob; exact-target mode transfers one entity
AIControlAllowACU = false -- never transfer AI ACUs unless explicitly enabled
AIControlIncludeExperimentals = true -- land/naval/air experimentals can be taken too

--#region balance knobs
-- Every consumer reads these with a fallback to the same default, so a deleted
-- field cannot crash anything. The catalog tooltips (buffs.lua) are built from
-- these values too, so tuning here updates what the player reads.

-- draft pacing
DraftIntervalSeconds = 300 -- one draft per 5 min
OptionsPerTick = 3 -- buffs offered per draft choice

-- AI pressure director (part 2, survey scaffold). Logs-only for now: after
-- AIDirectorStartSeconds of game time a sim thread logs what each AI army on
-- Artem's side has (land, idle land, transports, experimentals, engineers).
-- It issues no orders and never touches human armies, Mark's side or ACUs.
EnableAIDirector = true
AIDirectorStartSeconds = 60 -- SMOKE TEST value; real cadence: 1800 (30 min)
AIDirectorIntervalSeconds = 60 -- game seconds between survey ticks

-- D1: staged land waves (lua/ai_director/land_waves.lua). Idle land combat units
-- of every AI army on Artem's side gather until the wave thresholds are met,
-- then attack one scored, land-reachable, not-overdefended target near Mark.
AIDirectorOrdersEnabled = true -- SMOKE TEST: real orders ON; false = dry-run (log only, no orders)
AIDirectorLandWavesEnabled = true
AIDirectorMinWaveUnits = 12 -- wave launches only with at least this many units...
AIDirectorMinWaveMass = 2000 -- ...and at least this much total build-cost mass
AIDirectorMaxWaveUnits = 40 -- heaviest units first; the rest keep gathering
AIDirectorWaveCooldownSeconds = 180 -- per army, between issued waves
AIDirectorLateGameSeconds = 2400 -- after this, weak T1 land units are capped per wave
AIDirectorT1SpamLimit = 5 -- max T1 land units per wave once late game starts
AIDirectorTargetDefenseRadius = 40 -- radius around a candidate target scanned for defenses
AIDirectorMaxTargetThreatFactor = 0.5 -- defense mass near target must be < wave mass * this
AIDirectorStuckTicks = 3 -- director ticks without wave progress before retarget, then release

-- D2: experimental missions (lua/ai_director/experimental_mission.lua). Every
-- idle land experimental of an AI army gets its own aggressive-move mission to
-- a scored target (amphibious pathing, softer threat gate than land waves).
AIDirectorExperimentalMissionEnabled = true
AIDirectorExperimentalThreatFactor = 1.0 -- defense mass near target must be < experimental mass * this

-- D3: forward fortify (lua/ai_director/fortify.lua). Idle AI engineers build a
-- small defense package (radar/AA/PD/TMD/shield, scaled by engineer tech) at the
-- AI base and owned mex clusters. Respects AIDirectorOrdersEnabled (dry-run).
AIDirectorFortifyEnabled = true
AIDirectorFortifyStartSeconds = 1200 -- game seconds before fortify starts; test: 60
AIDirectorFortifyIntervalSeconds = 90 -- per army, between fortify passes
AIDirectorFortifyMaxEngineersPerTick = 3 -- build tasks issued per army per pass
AIDirectorFortifyAreaCooldownSeconds = 300 -- per area, after a task was issued there

-- rarity gating (choice number = picks + queued choices + 1, per side)
RareUnlockPickNumber = 6 -- rare options possible starting with this choice
LegendaryUnlockPickNumber = 6 -- legendary options possible starting with this choice
LegendaryOfferCooldownChoices = 3 -- resolved choices without legendary after one was offered
RareChancePercent = 35 -- per-slot chance once unlocked
LegendaryChancePercent = 20 -- per-slot chance once unlocked (max 1 legendary per choice)
MythicUnlockPickNumber = 10 -- mythic options are late-game, after both lower tiers
MythicOfferCooldownChoices = 10 -- resolved choices without mythic after one was offered
MythicChancePercent = 5 -- per-slot chance once unlocked (max 1 mythic per choice)

-- passive multipliers
ENGINEER_BUILD_RATE_MULT = 5.0
FACTORY_BUILD_RATE_MULT = 3.0
AIR_SPEED_MULT = 1.25
NAVAL_ARMOR_MULT = 2.5
EXPERIMENTAL_HEALTH_MULT = 2.0
ACU_REGEN_ADD = 60 -- flat hp/s
RADAR_RADIUS_MULT = 2.0
SCOUT_VISION_MULT = 2.0
ECO_PRODUCTION_MULT = 2.5
ANTIAIR_DAMAGE_MULT = 2.5
LAND_ROF_MULT = 2.0
ARTILLERY_RANGE_MULT = 1.5
TACTICAL_RANGE_MULT = 2.0
SHIELD_HEALTH_MULT = 2.0
MOBILE_SHIELD_HEALTH_MULT = 2.0
EMERGENCY_FAB_BUILD_MULT = 3.0 -- while building defenses
OVERCHARGED_SHIELD_MULT = 2.5
NAPALM_RADIUS_ADD = 1.0 -- flat damage-radius add, world units
TELEPORT_SPEED_MULT = 2.0 -- ACU/SCU/engineers
NANO_REGEN_ADD = 5 -- flat hp/s, all units
EXP_DISCOUNT_BUILD_MULT = 2.5 -- while building experimentals
RAPID_SPEED_MULT = 2.0
RAPID_DURATION = 60 -- seconds of bonus speed on newly built mobiles
FORTRESS_HP_MULT = 3.0
FORTRESS_SPEED_MULT = 0.85 -- mobility cost, < 1
HUNTER_VISION_MULT = 2.0
HUNTER_RADAR_MULT = 2.0
HUNTER_SPEED_MULT = 1.5
BLACK_MARKET_MASS_FRACTION = 0.1 -- of victim cost per kill
BLACK_MARKET_ENERGY_FRACTION = 0.1
CHAIN_BEAM_DAMAGE_MULT = 1.5
CHAIN_BEAM_RADIUS_ADD = 1.5
RECLAIM_RATE_MULT = 2.0 -- while reclaiming
TAC_SUPREMACY_RANGE_MULT = 3.0
TAC_SUPREMACY_BUILD_MULT = 2.0
MISSILE_STORM_ROF_MULT = 2.5
MISSILE_STORM_BUILD_MULT = 2.5
AIR_SUP_SPEED_MULT = 2.0
AIR_SUP_DAMAGE_MULT = 1.5
AIR_SUP_HP_MULT = 0.75 -- armor cost, < 1
DREADNOUGHT_HP_MULT = 3.0
DREADNOUGHT_RANGE_MULT = 1.5
OMNISCIENCE_OMNI_MULT = 3.0
OMNISCIENCE_RADAR_MULT = 2.5

-- mythic buffs
PARAGON_MIN_MASS_PER_SECOND = 20
PARAGON_MIN_ENERGY_PER_SECOND = 1000
PARAGON_MAX_MASS_PER_SECOND = 10000
PARAGON_MAX_ENERGY_PER_SECOND = 1000000
NUCLEAR_DAMAGE_MULT = 6.0
NUCLEAR_RADIUS_MULT = 3.0
NUCLEAR_BUILD_RATE_MULT = 1.5

-- free unit spawns
DRONE_FOUNDRY_INTERVAL = 45 -- game seconds between waves
DRONE_FOUNDRY_MAX_PER_WAVE = 4 -- factories that spawn per wave
ENGINEER_SWARM_INTERVAL = 60
ENGINEER_SWARM_MAX_PER_WAVE = 2

-- salvage explosion
SALVAGE_EXPLOSION_CHANCE = 25 -- percent per enemy kill
SALVAGE_EXPLOSION_RADIUS = 3
SALVAGE_EXPLOSION_DAMAGE = 150

-- orbital lance (active)
ORBITAL_LANCE_COOLDOWN = 90 -- game seconds
ORBITAL_LANCE_TICKS = 5 -- damage pulses per strike
ORBITAL_LANCE_TICK_DAMAGE = 800 -- per pulse
ORBITAL_LANCE_RADIUS = 5 -- per pulse impact
ORBITAL_LANCE_TICK_INTERVAL = 0.4 -- seconds between pulses

--#endregion
