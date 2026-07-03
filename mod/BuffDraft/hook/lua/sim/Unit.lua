-- BuffDraft: apply drafted buffs to units created/completed after a buff was picked.
-- This file is concatenated to the end of /lua/sim/Unit.lua by the mod hook system.
-- Wrapping the class is FAF's own end-of-Unit.lua pattern ("Backwards compatibility
-- with mods" block); subclasses are derived later, so they inherit the wrapped methods.
-- OnCreate covers build-rate style buffs (same spot FAF applies AI cheat buffs);
-- OnStopBeingBuilt covers buffs that need the finished unit (health, shields - the
-- base Unit.OnStopBeingBuilt creates MyShield before our code runs - intel, weapons).

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
    }
end
