-- BuffDraft: data shared by SIM and UI for the mythic Commander Apotheosis buff.
-- These are four independent upgrade packages. Their cost/time is calculated in
-- SIM from the listed stock ACU enhancement blueprints; effects are instance-only
-- equivalents that are safe on every faction's commander chassis.

CommanderUpgradePackages = {
    {
        id = 'uef', title = 'UEF Complete Arsenal', sourceUnit = 'uel0001',
        description = 'Safe equivalents for all 12 UEF enhancements: +75% max HP, +40 HP/s regen, +50% build rate, +12 mass/s, +3500 energy/s, +50% weapon damage, +25% range and teleport.',
        enhancements = {
            'AdvancedEngineering', 'DamageStabilization', 'HeavyAntiMatterCannon',
            'LeftPod', 'ResourceAllocation', 'RightPod', 'Shield',
            'ShieldGeneratorField', 'T3Engineering', 'TacticalMissile',
            'TacticalNukeMissile', 'Teleporter',
        },
        buffName = 'BuffDraftCommanderUEFPackage',
        buffType = 'BUFFDRAFTCOMMANDERUEF',
        healthMult = 1.75, regenAdd = 40, buildRateMult = 1.5,
        massProductionAdd = 12, energyProductionAdd = 3500,
        damageMult = 1.5, rateOfFireMult = 1.0, rangeMult = 1.25,
        visionMult = 1.25, omniMult = 1.0, teleport = true,
    },
    {
        id = 'aeon', title = 'Aeon Complete Ascension', sourceUnit = 'ual0001',
        description = 'Safe equivalents for all 12 Aeon enhancements: +75% max HP, +30 HP/s regen, +50% build rate, +16 mass/s, +5000 energy/s, +50% damage, rate of fire and range, +100% vision and omni, and teleport.',
        enhancements = {
            'AdvancedEngineering', 'ChronoDampener', 'CrysalisBeam',
            'EnhancedSensors', 'FAF_CrysalisBeamAdvanced', 'HeatSink',
            'ResourceAllocation', 'ResourceAllocationAdvanced', 'Shield',
            'ShieldHeavy', 'T3Engineering', 'Teleporter',
        },
        buffName = 'BuffDraftCommanderAeonPackage',
        buffType = 'BUFFDRAFTCOMMANDERAEON',
        healthMult = 1.75, regenAdd = 30, buildRateMult = 1.5,
        massProductionAdd = 16, energyProductionAdd = 5000,
        damageMult = 1.5, rateOfFireMult = 1.5, rangeMult = 1.5,
        visionMult = 2.0, omniMult = 2.0, teleport = true,
    },
    {
        id = 'cybran', title = 'Cybran Complete Evolution', sourceUnit = 'url0001',
        description = 'Safe equivalents for all 10 Cybran enhancements: +25% max HP, +100 HP/s regen, +50% build rate, +12 mass/s, +3500 energy/s, +75% damage, +50% rate of fire, +20% range, +50% vision, cloak, stealth and teleport.',
        enhancements = {
            'AdvancedEngineering', 'CloakingGenerator', 'CoolingUpgrade',
            'FAF_SelfRepairSystem', 'MicrowaveLaserGenerator',
            'NaniteTorpedoTube', 'ResourceAllocation', 'StealthGenerator',
            'T3Engineering', 'Teleporter',
        },
        buffName = 'BuffDraftCommanderCybranPackage',
        buffType = 'BUFFDRAFTCOMMANDERCYBRAN',
        healthMult = 1.25, regenAdd = 100, buildRateMult = 1.5,
        massProductionAdd = 12, energyProductionAdd = 3500,
        damageMult = 1.75, rateOfFireMult = 1.5, rangeMult = 1.2,
        visionMult = 1.5, omniMult = 1.0, teleport = true, cloak = true,
    },
    {
        id = 'seraphim', title = 'Seraphim Complete Apotheosis', sourceUnit = 'xsl0001',
        description = 'Safe equivalents for all 12 Seraphim enhancements: +75% max HP, +150 HP/s regen, +50% build rate, +16 mass/s, +5000 energy/s, +50% damage and rate of fire, +20% range, +50% vision, teleport and +25 HP/s allied aura in radius 30.',
        enhancements = {
            'AdvancedEngineering', 'AdvancedRegenAura', 'BlastAttack',
            'DamageStabilization', 'DamageStabilizationAdvanced', 'Missile',
            'RateOfFire', 'RegenAura', 'ResourceAllocation',
            'ResourceAllocationAdvanced', 'T3Engineering', 'Teleporter',
        },
        buffName = 'BuffDraftCommanderSeraphimPackage',
        buffType = 'BUFFDRAFTCOMMANDERSERAPHIM',
        healthMult = 1.75, regenAdd = 150, buildRateMult = 1.5,
        massProductionAdd = 16, energyProductionAdd = 5000,
        damageMult = 1.5, rateOfFireMult = 1.5, rangeMult = 1.2,
        visionMult = 1.5, omniMult = 1.0, teleport = true,
        auraRegen = 25, auraRadius = 30,
    },
}

function FindCommanderUpgradePackage(id)
    for _, package in CommanderUpgradePackages do
        if package.id == id then
            return package
        end
    end
    return nil
end
