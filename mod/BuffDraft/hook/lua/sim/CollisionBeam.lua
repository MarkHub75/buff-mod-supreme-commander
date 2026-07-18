-- BuffDraft: true secondary-target damage for Chain Lightning.
-- The stock collision beam already knows the concrete weapon, launcher, target
-- and per-shot damage table, making this a side-safe SIM hook.

local BuffDraftOldCollisionBeam = CollisionBeam
local BuffDraftEffectsModule = false

local function BuffDraftEffects()
    if not BuffDraftEffectsModule then
        BuffDraftEffectsModule = import('/mods/BuffDraft/lua/effects.lua')
    end
    return BuffDraftEffectsModule
end

CollisionBeam = Class(BuffDraftOldCollisionBeam) {
    DoDamage = function(self, instigator, damageData, targetEntity)
        local unit = self.Weapon and self.Weapon.unit
        local applied = unit and unit.BuffDraftApplied
        if applied and applied.BuffDraftChainLightning1 then
            local ok, err = pcall(function()
                BuffDraftEffects().OnCollisionBeamDamage(self, instigator, damageData, targetEntity)
            end)
            if not ok then
                WARN("FAF_BUFF_DRAFT: collision beam hook error: " .. tostring(err))
            end
        end
        return BuffDraftOldCollisionBeam.DoDamage(
            self, instigator, damageData, targetEntity)
    end,
}
