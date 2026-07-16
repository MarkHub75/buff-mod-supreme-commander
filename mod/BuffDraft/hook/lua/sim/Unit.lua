-- BuffDraft: apply drafted buffs to units created/completed after a buff was picked.
-- This file is concatenated to the end of /lua/sim/Unit.lua by the mod hook system.
-- Wrapping the class is FAF's own end-of-Unit.lua pattern ("Backwards compatibility
-- with mods" block); subclasses are derived later, so they inherit the wrapped methods.
--
-- Two hard rules learned from a factory-breaking bug:
--  * ALWAYS forward the base method's return value. Unit.OnStartBuild returns
--    true/false and StructureUnit.OnStartBuild aborts ("death loop" check) when it
--    gets a falsy value - swallowing the return broke every factory build
--    (UnitBeingBuilt never set -> HideBone/rolloff crashes, stuck factories).
--  * our mod code runs behind pcall, so a bug in effects.lua can never abort the
--    base game's build/reclaim/kill flow mid-way.

do
    local oldUnit = Unit

    local function BuffDraftCall(hookName, fn)
        local ok, err = pcall(fn)
        if not ok then
            WARN("FAF_BUFF_DRAFT: unit hook " .. hookName .. " error: " .. tostring(err))
        end
    end

    Unit = Class(oldUnit) {
        OnCreate = function(self)
            local result = oldUnit.OnCreate(self)
            BuffDraftCall("OnCreate", function()
                import('/mods/BuffDraft/lua/effects.lua').OnUnitCreated(self)
            end)
            BuffDraftCall("StrategicWarning.OnCreate", function()
                import('/mods/BuffDraft/lua/strategic_warning.lua').OnUnitCreated(self)
            end)
            return result
        end,

        OnStopBeingBuilt = function(self, builder, layer)
            local result = oldUnit.OnStopBeingBuilt(self, builder, layer)
            if result then
                BuffDraftCall("OnStopBeingBuilt", function()
                    import('/mods/BuffDraft/lua/effects.lua').OnUnitBuilt(self)
                end)
            end
            return result
        end,

        CreateShield = function(self, bpShield)
            local result = oldUnit.CreateShield(self, bpShield)
            BuffDraftCall("CreateShield", function()
                import('/mods/BuffDraft/lua/effects.lua').OnUnitShieldCreated(self)
            end)
            return result
        end,

        OnShieldEnabled = function(self)
            local result = oldUnit.OnShieldEnabled(self)
            BuffDraftCall("OnShieldEnabled", function()
                import('/mods/BuffDraft/lua/effects.lua').OnUnitShieldCreated(self)
            end)
            return result
        end,

        OnStartBuild = function(self, built, order)
            -- the return value is the success flag StructureUnit checks; pass it on
            local result = oldUnit.OnStartBuild(self, built, order)
            if result then
                BuffDraftCall("OnStartBuild", function()
                    import('/mods/BuffDraft/lua/effects.lua').OnUnitStartBuild(self, built)
                end)
            end
            return result
        end,

        OnStopBuild = function(self, built, order)
            local result = oldUnit.OnStopBuild(self, built, order)
            BuffDraftCall("OnStopBuild", function()
                import('/mods/BuffDraft/lua/effects.lua').OnUnitStopBuild(self)
            end)
            return result
        end,

        OnFailedToBuild = function(self)
            local result = oldUnit.OnFailedToBuild(self)
            BuffDraftCall("OnFailedToBuild", function()
                import('/mods/BuffDraft/lua/effects.lua').OnUnitStopBuild(self)
            end)
            return result
        end,

        OnKilledUnit = function(self, unitKilled, experience)
            local result = oldUnit.OnKilledUnit(self, unitKilled, experience)
            BuffDraftCall("OnKilledUnit", function()
                import('/mods/BuffDraft/lua/effects.lua').OnUnitKilledUnit(self, unitKilled)
            end)
            return result
        end,

        OnStartReclaim = function(self, target)
            local result = oldUnit.OnStartReclaim(self, target)
            BuffDraftCall("OnStartReclaim", function()
                import('/mods/BuffDraft/lua/effects.lua').OnUnitStartReclaim(self)
            end)
            return result
        end,

        OnStopReclaim = function(self, target)
            local result = oldUnit.OnStopReclaim(self, target)
            BuffDraftCall("OnStopReclaim", function()
                import('/mods/BuffDraft/lua/effects.lua').OnUnitStopReclaim(self)
            end)
            return result
        end,
    }
end
