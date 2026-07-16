-- BuffDraft: per-projectile nuclear scaling for Nuclear Apocalypse.
-- This wraps the stock constructor after it created the projectile's NukeAOE
-- rings. No weapon or projectile blueprint is mutated, so other armies are safe.

local BuffDraftOldWeapon = Weapon

Weapon = Class(BuffDraftOldWeapon) {
    CreateProjectileForWeapon = function(self, bone)
        local projectile = BuffDraftOldWeapon.CreateProjectileForWeapon(self, bone)
        if projectile and (not projectile:BeenDestroyed())
                and self.unit and EntityCategoryContains(categories.NUKE, self.unit)
                and projectile.InnerRing and projectile.OuterRing then
            local effects = import('/mods/BuffDraft/lua/effects.lua')
            local damageMult, radiusMult = effects.GetNuclearStrikeMultipliers(self.Army)
            if damageMult ~= 1 or radiusMult ~= 1 then
                projectile.InnerRing.Damage = projectile.InnerRing.Damage * damageMult
                projectile.InnerRing.Radius = projectile.InnerRing.Radius * radiusMult
                projectile.OuterRing.Damage = projectile.OuterRing.Damage * damageMult
                projectile.OuterRing.Radius = projectile.OuterRing.Radius * radiusMult
                LOG("FAF_BUFF_DRAFT: nuclear projectile scaled army=" .. tostring(self.Army)
                    .. " damage=x" .. tostring(damageMult)
                    .. " radius=x" .. tostring(radiusMult))
            end
        end
        return projectile
    end,
}
