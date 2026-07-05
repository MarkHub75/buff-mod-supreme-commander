-- BuffDraft: apply drafted buffs to units created/completed after a buff was picked.
-- This file is concatenated to the end of /lua/sim/Unit.lua by the mod hook system.
-- Wrapping the class is FAF's own end-of-Unit.lua pattern ("Backwards compatibility
-- with mods" block); subclasses are derived later, so they inherit the wrapped methods.
-- OnCreate covers build-rate style buffs (same spot FAF applies AI cheat buffs);
-- OnStopBeingBuilt covers buffs that need the finished unit (health, shields - the
-- base Unit.OnStopBeingBuilt creates MyShield before our code runs - intel, weapons).
-- OnStartBuild/OnStopBuild/OnFailedToBuild drive the conditional build-rate buffs
-- (emergency fabrication, experimental assembly); OnKilledUnit drives the black
-- market kill bounty.

do
    local oldUnit = Unit
    Unit = Class(oldUnit) {
        OnCreate = function(self)
            oldUnit.OnCreate(self)
            import('/mods/BuffDraft/lua/effects.lua').OnUnitCreated(self)
        end,

        OnStopBeingBuilt = function(self, builder, layer)
            oldUnit.OnStopBeingBuilt(self, builder, layer)
            import('/mods/BuffDraft/lua/effects.lua').OnUnitBuilt(self)
        end,

        OnStartBuild = function(self, built, order)
            oldUnit.OnStartBuild(self, built, order)
            import('/mods/BuffDraft/lua/effects.lua').OnUnitStartBuild(self, built)
        end,

        OnStopBuild = function(self, built, order)
            oldUnit.OnStopBuild(self, built, order)
            import('/mods/BuffDraft/lua/effects.lua').OnUnitStopBuild(self)
        end,

        OnFailedToBuild = function(self)
            oldUnit.OnFailedToBuild(self)
            import('/mods/BuffDraft/lua/effects.lua').OnUnitStopBuild(self)
        end,

        OnKilledUnit = function(self, unitKilled, experience)
            oldUnit.OnKilledUnit(self, unitKilled, experience)
            import('/mods/BuffDraft/lua/effects.lua').OnUnitKilledUnit(self, unitKilled)
        end,
    }
end
