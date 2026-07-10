-- XRA0105 can hit water before AirUnit.OnKilled initialized its crash weapon and
-- collider projectile. Repair just this unit's missing transient state before
-- forwarding to the stock AirUnit.OnImpact implementation.

do
    local oldXRA0105 = TypeClass

    TypeClass = Class(oldXRA0105) {
        OnImpact = function(self, with)
            if (not self.deathWep) or self.DeathCrashDamage == nil then
                for _, weapon in self.Blueprint.Weapon or {} do
                    if weapon.Label == 'DeathImpact' then
                        self.deathWep = weapon
                        self.DeathCrashDamage = weapon.Damage or 0
                        break
                    end
                end
            end

            if with == 'Water' and ((not self.colliderProj) or (not self.colliderProj.Destroy)) then
                self.colliderProj = { Destroy = function() end }
            end

            return oldXRA0105.OnImpact(self, with)
        end,
    }
end
