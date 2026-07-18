-- BuffDraft: per-projectile nuclear scaling for Nuclear Apocalypse.
-- This wraps the stock constructor after it created the projectile's NukeAOE
-- rings. No weapon or projectile blueprint is mutated, so other armies are safe.

local BuffDraftOldWeapon = Weapon
local BuffDraftEffectsModule = false

local function BuffDraftEffects()
    if not BuffDraftEffectsModule then
        BuffDraftEffectsModule = import('/mods/BuffDraft/lua/effects.lua')
    end
    return BuffDraftEffectsModule
end

local function BuffDraftScaleNuclearProjectile(weapon, projectile)
    if projectile and (not projectile:BeenDestroyed())
            and weapon.unit and EntityCategoryContains(categories.NUKE, weapon.unit)
            and projectile.InnerRing and projectile.OuterRing then
        local ok, damageMult, radiusMult = pcall(function()
            return BuffDraftEffects().GetNuclearStrikeMultipliers(weapon.Army)
        end)
        if not ok then
            WARN("FAF_BUFF_DRAFT: nuclear projectile hook error: " .. tostring(damageMult))
            return projectile
        end
        if damageMult ~= 1 or radiusMult ~= 1 then
            projectile.InnerRing.Damage = projectile.InnerRing.Damage * damageMult
            projectile.InnerRing.Radius = projectile.InnerRing.Radius * radiusMult
            projectile.OuterRing.Damage = projectile.OuterRing.Damage * damageMult
            projectile.OuterRing.Radius = projectile.OuterRing.Radius * radiusMult
            LOG("FAF_BUFF_DRAFT: nuclear projectile scaled army=" .. tostring(weapon.Army)
                .. " damage=x" .. tostring(damageMult)
                .. " radius=x" .. tostring(radiusMult))
        end
    end
    return projectile
end

local function BuffDraftCreateProjectile(weapon, bone)
    return BuffDraftScaleNuclearProjectile(
        weapon, BuffDraftOldWeapon.CreateProjectileForWeapon(weapon, bone))
end

Weapon = Class(BuffDraftOldWeapon) {
    GetDamageTable = function(self)
        local damageTable = BuffDraftOldWeapon.GetDamageTable(self)
        local applied = self.unit and self.unit.BuffDraftApplied
        local active = applied and (applied.BuffDraftNapalmDirect1
            or applied.BuffDraftNapalmArtillery1) and true or false
        local dotTime, dotPulses
        if active then
            local ok
            ok, active, dotTime, dotPulses = pcall(function()
                return BuffDraftEffects().GetNapalmDamageProfile(self)
            end)
            if not ok then
                WARN("FAF_BUFF_DRAFT: napalm weapon hook error: " .. tostring(active))
                active = false
            end
        end
        if active then
            if not self.BuffDraftNapalmModified then
                self.BuffDraftNapalmOriginalDoTTime = damageTable.DoTTime
                self.BuffDraftNapalmOriginalDoTPulses = damageTable.DoTPulses
                self.BuffDraftNapalmModified = true
            end
            damageTable.DoTTime = dotTime
            damageTable.DoTPulses = dotPulses
        elseif self.BuffDraftNapalmModified then
            damageTable.DoTTime = self.BuffDraftNapalmOriginalDoTTime
            damageTable.DoTPulses = self.BuffDraftNapalmOriginalDoTPulses
            self.BuffDraftNapalmModified = nil
        end
        return damageTable
    end,

    CreateProjectileForWeapon = function(self, bone)
        local projectile = BuffDraftCreateProjectile(self, bone)
        local applied = self.unit and self.unit.BuffDraftApplied
        local count = 1
        if applied and applied.BuffDraftMissileStormRoF1 then
            local ok
            ok, count = pcall(function()
                return BuffDraftEffects().GetMissileStormProjectileCount(self)
            end)
            if not ok then
                WARN("FAF_BUFF_DRAFT: missile storm hook error: " .. tostring(count))
                count = 1
            end
        end
        for i = 2, count do
            BuffDraftCreateProjectile(self, bone)
        end
        return projectile
    end,
}
