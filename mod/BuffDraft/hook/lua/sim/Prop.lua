-- BuffDraft: side-specific reclaim yield for wreckage and map props.
-- Prop.GetReclaimCosts already receives the concrete reclaimer, allowing the
-- resource values to be changed without mutating this prop for other armies.

local BuffDraftOldProp = Prop
local BuffDraftEffectsModule = false

local function BuffDraftEffects()
    if not BuffDraftEffectsModule then
        BuffDraftEffectsModule = import('/mods/BuffDraft/lua/effects.lua')
    end
    return BuffDraftEffectsModule
end

Prop = Class(BuffDraftOldProp) {
    GetReclaimCosts = function(self, reclaimer)
        local time, energy, mass = BuffDraftOldProp.GetReclaimCosts(self, reclaimer)
        local mult = 1
        local buffs = reclaimer and reclaimer.Buffs and reclaimer.Buffs.BuffTable
        local hasReclaimBuff = buffs and buffs.BUFFDRAFTRECLAIMRATE
            and buffs.BUFFDRAFTRECLAIMRATE.BuffDraftReclaimRate1
        if hasReclaimBuff then
            local ok, err = pcall(function()
                mult = BuffDraftEffects().GetReclaimYieldMultiplier(reclaimer)
            end)
            if not ok then
                WARN("FAF_BUFF_DRAFT: prop reclaim hook error: " .. tostring(err))
            end
        end
        return time, energy * mult, mass * mult
    end,
}
