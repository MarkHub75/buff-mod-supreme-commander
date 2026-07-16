-- BuffDraft MVP 5: sim callback that receives the player's buff pick from the UI.
-- This file is concatenated to the end of /lua/SimCallbacks.lua before it runs, so
-- the file-local `Callbacks` table of the original script is visible here.

Callbacks.BuffDraftPick = function(data, units)
    import('/mods/BuffDraft/lua/draft.lua').ReceivePick(data)
end

-- Debug admin panel (gated by DebugAdmin in /mods/BuffDraft/lua/config.lua; the
-- sim re-validates the flag and everything else in draft.lua - the UI is input only).
Callbacks.BuffDraftAdminGrantBuff = function(data, units)
    local senderArmy = import('/lua/simutils.lua').GetCurrentCommandSourceArmy()
    if not senderArmy then
        LOG("FAF_BUFF_DRAFT_ADMIN: grant ignored: no command source army (observer/replay)")
        return
    end
    import('/mods/BuffDraft/lua/draft.lua').AdminGrantBuff(data, senderArmy)
end

Callbacks.BuffDraftAdminRemoveBuff = function(data, units)
    local senderArmy = import('/lua/simutils.lua').GetCurrentCommandSourceArmy()
    if not senderArmy then
        LOG("FAF_BUFF_DRAFT_ADMIN: remove ignored: no command source army (observer/replay)")
        return
    end
    import('/mods/BuffDraft/lua/draft.lua').AdminRemoveBuff(data, senderArmy)
end

-- AI control "Take AI units": the owner clicks an allied AI unit/structure and
-- that exact entity transfers to the owner. Army comes from the command source
-- only; owner nickname and target entity are validated in ai_control/control.lua.
Callbacks.BuffDraftTakeAIUnits = function(data, units)
    local senderArmy = import('/lua/simutils.lua').GetCurrentCommandSourceArmy()
    if not senderArmy then
        LOG("FAF_BUFF_DRAFT_AI_CONTROL: take ignored: no command source army (observer/replay)")
        return
    end
    local ok, err = pcall(function()
        import('/mods/BuffDraft/lua/ai_control/control.lua').TakeAIUnitsAtPoint(senderArmy, data)
    end)
    if not ok then
        WARN("FAF_BUFF_DRAFT_AI_CONTROL: take failed: " .. tostring(err))
    end
end

-- Active buff use (e.g. orbital lance). The army is taken from the command source,
-- never from the UI data, so a player can only activate their own army's buffs;
-- ownership and cooldown are validated in effects.UseActiveBuff.
Callbacks.BuffDraftUseActive = function(data, units)
    local senderArmy = import('/lua/simutils.lua').GetCurrentCommandSourceArmy()
    LOG("FAF_BUFF_DRAFT: BuffDraftUseActive received: buff=" .. tostring(data.buffId)
        .. " army=" .. tostring(senderArmy)
        .. " payload=" .. (data.payload and "point" or "none"))
    if not senderArmy then
        LOG("FAF_BUFF_DRAFT: active use ignored: no command source army (observer/replay)")
        return
    end
    import('/mods/BuffDraft/lua/effects.lua').UseActiveBuff(senderArmy, data.buffId, data.payload)
end

-- Mythic Commander Apotheosis: UI chooses one of the four faction packages,
-- while SIM owns army identity, costs, availability and the actual effects.
Callbacks.BuffDraftCommanderUpgrade = function(data, units)
    local senderArmy = import('/lua/simutils.lua').GetCurrentCommandSourceArmy()
    if not senderArmy then
        LOG("FAF_BUFF_DRAFT: commander upgrade ignored: no command source army")
        return
    end
    local ok, err = pcall(function()
        import('/mods/BuffDraft/lua/effects.lua').RequestCommanderUpgrade(
            senderArmy, data and data.packageId)
    end)
    if not ok then
        WARN("FAF_BUFF_DRAFT: commander upgrade callback failed: " .. tostring(err))
    end
end

Callbacks.BuffDraftCommanderUpgradeSync = function(data, units)
    local senderArmy = import('/lua/simutils.lua').GetCurrentCommandSourceArmy()
    if not senderArmy then
        return
    end
    import('/mods/BuffDraft/lua/effects.lua').RequestCommanderUpgradeSync(senderArmy)
end
