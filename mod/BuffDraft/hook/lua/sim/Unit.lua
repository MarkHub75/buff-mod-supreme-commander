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
    local BuffDraftEffectsModule = false

    local function BuffDraftEffects()
        if not BuffDraftEffectsModule then
            BuffDraftEffectsModule = import('/mods/BuffDraft/lua/effects.lua')
        end
        return BuffDraftEffectsModule
    end

    local function BuffDraftCall(hookName, fn)
        local ok, err = pcall(fn)
        if not ok then
            WARN("FAF_BUFF_DRAFT: unit hook " .. hookName .. " error: " .. tostring(err))
        end
    end

    Unit = Class(oldUnit) {
        GetBuildCosts = function(self, targetBlueprint)
            local time, energy, mass = oldUnit.GetBuildCosts(self, targetBlueprint)
            local mult = 1
            BuffDraftCall("GetBuildCosts", function()
                mult = BuffDraftEffects().GetExperimentalBuildCostMultiplier(self, targetBlueprint)
            end)
            return time, energy * mult, mass * mult
        end,

        GetReclaimCosts = function(self, target)
            local time, energy, mass = oldUnit.GetReclaimCosts(self, target)
            local mult = 1
            -- Props have their own hook because Unit.OnStartReclaim calls the
            -- prop directly for its reclaim accounting. Avoid multiplying twice
            -- when oldUnit.GetReclaimCosts delegated to that prop.
            local buffs = self.Buffs and self.Buffs.BuffTable
            local hasReclaimBuff = buffs and buffs.BUFFDRAFTRECLAIMRATE
                and buffs.BUFFDRAFTRECLAIMRATE.BuffDraftReclaimRate1
            if target and target.IsUnit and hasReclaimBuff then
                BuffDraftCall("GetReclaimCosts", function()
                    mult = BuffDraftEffects().GetReclaimYieldMultiplier(self)
                end)
            end
            return time, energy * mult, mass * mult
        end,

        OnCreate = function(self)
            local result = oldUnit.OnCreate(self)
            BuffDraftCall("OnCreate", function()
                BuffDraftEffects().OnUnitCreated(self)
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
                    BuffDraftEffects().OnUnitBuilt(self)
                end)
            end
            return result
        end,

        CreateShield = function(self, bpShield)
            local result = oldUnit.CreateShield(self, bpShield)
            BuffDraftCall("CreateShield", function()
                BuffDraftEffects().OnUnitShieldCreated(self)
            end)
            return result
        end,

        OnShieldEnabled = function(self)
            local result = oldUnit.OnShieldEnabled(self)
            BuffDraftCall("OnShieldEnabled", function()
                BuffDraftEffects().OnUnitShieldCreated(self)
            end)
            return result
        end,

        OnDamage = function(self, instigator, amount, vector, damageType)
            BuffDraftCall("OnDamage", function()
                BuffDraftEffects().OnUnitDamaged(self, amount, damageType)
            end)
            return oldUnit.OnDamage(self, instigator, amount, vector, damageType)
        end,

        CreateWreckage = function(self, overkillRatio)
            local wreckage = oldUnit.CreateWreckage(self, overkillRatio)
            BuffDraftCall("CreateWreckage", function()
                BuffDraftEffects().OnWreckageCreated(self, wreckage)
            end)
            return wreckage
        end,

        OnStartBuild = function(self, built, order)
            -- the return value is the success flag StructureUnit checks; pass it on
            local result = oldUnit.OnStartBuild(self, built, order)
            if result then
                BuffDraftCall("OnStartBuild", function()
                    BuffDraftEffects().OnUnitStartBuild(self, built)
                end)
            end
            return result
        end,

        OnStopBuild = function(self, built, order)
            local result = oldUnit.OnStopBuild(self, built, order)
            BuffDraftCall("OnStopBuild", function()
                BuffDraftEffects().OnUnitStopBuild(self)
            end)
            return result
        end,

        OnFailedToBuild = function(self)
            local result = oldUnit.OnFailedToBuild(self)
            BuffDraftCall("OnFailedToBuild", function()
                BuffDraftEffects().OnUnitStopBuild(self)
            end)
            return result
        end,

        OnKilledUnit = function(self, unitKilled, experience)
            local result = oldUnit.OnKilledUnit(self, unitKilled, experience)
            BuffDraftCall("OnKilledUnit", function()
                BuffDraftEffects().OnUnitKilledUnit(self, unitKilled)
            end)
            return result
        end,

        OnStartReclaim = function(self, target)
            -- Apply before the base method so its prop reclaim accounting sees
            -- both the faster build rate and the increased resource yield.
            BuffDraftCall("OnStartReclaim", function()
                BuffDraftEffects().OnUnitStartReclaim(self)
            end)
            return oldUnit.OnStartReclaim(self, target)
        end,

        OnStopReclaim = function(self, target)
            local result = oldUnit.OnStopReclaim(self, target)
            BuffDraftCall("OnStopReclaim", function()
                BuffDraftEffects().OnUnitStopReclaim(self)
            end)
            return result
        end,
    }
end
