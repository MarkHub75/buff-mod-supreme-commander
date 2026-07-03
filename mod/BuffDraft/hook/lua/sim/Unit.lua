-- BuffDraft MVP 4: apply drafted buffs to units created after a buff was picked.
-- This file is concatenated to the end of /lua/sim/Unit.lua by the mod hook system.
-- Wrapping the class is FAF's own end-of-Unit.lua pattern ("Backwards compatibility
-- with mods" block); subclasses are derived later, so they inherit the wrapped OnCreate.

do
    local oldUnit = Unit
    Unit = Class(oldUnit) {
        OnCreate = function(self)
            oldUnit.OnCreate(self)
            import('/mods/BuffDraft/lua/effects.lua').OnUnitCreated(self)
        end,
    }
end
