-- BuffDraft MVP 7: sim-side draft pipeline with a pending-choice queue. Every draft
-- tick rolls options for both sides; human sides get a pending choice added to their
-- queue (no auto-pick, no timeout) and pick whenever they press Choose in the UI.
-- AI-only sides still auto-pick the first option immediately. All rules are
-- validated sim-side; the UI only displays queue state and sends picks/rerolls.

local BuffCatalog = import('/mods/BuffDraft/lua/buffs.lua').BuffCatalog
local AdminAccess = import('/mods/BuffDraft/lua/admin_access.lua')

-- knobs from config.lua; nil-safe fallbacks keep the historical defaults
local BuffDraftConfig = import('/mods/BuffDraft/lua/config.lua')
local OPTIONS_PER_TICK = BuffDraftConfig.OptionsPerTick or 3
local RARE_UNLOCK_PICK = BuffDraftConfig.RareUnlockPickNumber or 6
local LEGENDARY_UNLOCK_PICK = BuffDraftConfig.LegendaryUnlockPickNumber or 6
local MYTHIC_UNLOCK_PICK = BuffDraftConfig.MythicUnlockPickNumber or 10
local LEGENDARY_COOLDOWN_CHOICES = BuffDraftConfig.LegendaryOfferCooldownChoices or 3
local MYTHIC_COOLDOWN_CHOICES = BuffDraftConfig.MythicOfferCooldownChoices or 10
local RARE_CHANCE_PERCENT = BuffDraftConfig.RareChancePercent or 35
local LEGENDARY_CHANCE_PERCENT = BuffDraftConfig.LegendaryChancePercent or 20
local MYTHIC_CHANCE_PERCENT = BuffDraftConfig.MythicChancePercent or 5

-- sideName -> resolved choices left before a top-tier offer may appear again;
-- set when an option is offered, then decremented by later resolved choices.
local LegendaryCooldownRemaining = {
    Mark = 0,
    Artem = 0,
}
local MythicCooldownRemaining = {
    Mark = 0,
    Artem = 0,
}

-- Sim-side draft state. Import caching keeps this module (and therefore these
-- tables) alive for the whole sim session.
local PickedHistory = {
    Mark = {},
    Artem = {},
}

-- sideName -> ordered queue of { tick, options, armies, chooserArmy }
local PendingChoices = {
    Mark = {},
    Artem = {},
}

-- One rarity-neutral reroll per human side for the whole sim session.
local RerollUsed = {
    Mark = false,
    Artem = false,
}

local function IsPicked(sideName, id)
    for _, pickedId in PickedHistory[sideName] do
        if pickedId == id then
            return true
        end
    end
    return false
end

-- Buff ids currently offered in any pending choice of this side, so the same buff
-- cannot be rolled into two queued choices at once.
local function PendingBuffIds(sideName, ignoredChoice)
    local ids = {}
    for _, choice in PendingChoices[sideName] do
        if choice ~= ignoredChoice then
            for _, option in choice.options do
                table.insert(ids, option.id)
            end
        end
    end
    return ids
end

local function ListContains(list, id)
    for _, entry in list do
        if entry == id then
            return true
        end
    end
    return false
end

-- Buffs this side can still roll: prerequisite already picked, not in its picked
-- history and not sitting in any pending choice. A buff picked by one side can
-- still roll for the other.
-- Returns the available list plus the pending id list (for logging).
local function AvailableBuffs(sideName, ignoredChoice)
    local pendingIds = PendingBuffIds(sideName, ignoredChoice)
    local available = {}
    for _, buff in BuffCatalog do
        local prerequisiteMet = (not buff.prerequisite)
            or IsPicked(sideName, buff.prerequisite)
        if prerequisiteMet and (not IsPicked(sideName, buff.id))
                and (not ListContains(pendingIds, buff.id)) then
            table.insert(available, buff)
        end
    end
    return available, pendingIds
end

--#region rarity-aware option generation
-- All rolls use Random(), the synchronized sim RNG, in a fixed order (pattern
-- first, then Mark's options, then Artem's), so every peer generates the same
-- draft. Rarity/cooldown logic lives entirely sim-side; the UI only displays
-- the `rarity` field that rides along on each option (a catalog entry).

local function BuffRarity(buff)
    return (buff and buff.rarity) or "common"
end

-- The choice number a newly generated choice would have for this side: resolved
-- picks + still-pending choices + 1.
local function ChoiceNumber(sideName)
    return table.getn(PickedHistory[sideName]) + table.getn(PendingChoices[sideName]) + 1
end

-- What this side may be offered right now, plus reasons for downgrade logs.
local function SideRarityAllowance(sideName)
    local choiceNum = ChoiceNumber(sideName)
    local allow = {
        rare = choiceNum >= RARE_UNLOCK_PICK,
        legendary = choiceNum >= LEGENDARY_UNLOCK_PICK
            and LegendaryCooldownRemaining[sideName] <= 0,
        mythic = choiceNum >= MYTHIC_UNLOCK_PICK
            and MythicCooldownRemaining[sideName] <= 0,
    }
    if choiceNum < LEGENDARY_UNLOCK_PICK then
        allow.legendaryReason = "locked until choice " .. tostring(LEGENDARY_UNLOCK_PICK)
    elseif LegendaryCooldownRemaining[sideName] > 0 then
        allow.legendaryReason = "legendary cooldown ("
            .. tostring(LegendaryCooldownRemaining[sideName]) .. " choices left)"
    end
    allow.rareReason = "locked until choice " .. tostring(RARE_UNLOCK_PICK)
    if choiceNum < MYTHIC_UNLOCK_PICK then
        allow.mythicReason = "locked until choice " .. tostring(MYTHIC_UNLOCK_PICK)
    elseif MythicCooldownRemaining[sideName] > 0 then
        allow.mythicReason = "mythic cooldown ("
            .. tostring(MythicCooldownRemaining[sideName]) .. " choices left)"
    end
    LOG("FAF_BUFF_DRAFT: rarity unlock side=" .. sideName
        .. " picks=" .. tostring(table.getn(PickedHistory[sideName]))
        .. " choice#=" .. tostring(choiceNum)
        .. " rare=" .. tostring(allow.rare) .. " legendary=" .. tostring(allow.legendary)
        .. " mythic=" .. tostring(allow.mythic))
    return allow
end

-- Shared rarity pattern of the tick: one list of slot rarities used by BOTH
-- sides (same rarity, not same buff). A slot may be legendary/rare when at
-- least one side is eligible; the other side downgrades its slot with a log.
-- At most one legendary and one mythic slot per choice.
local function RollRarityPattern(allowRare, allowLegendary, allowMythic)
    local pattern = {}
    local legendaryUsed = false
    local mythicUsed = false
    for i = 1, OPTIONS_PER_TICK do
        local roll = Random(1, 100)
        -- Every tier owns a fixed, non-overlapping roll window. If a tier is
        -- locked/on cooldown, its window stays common instead of inflating a
        -- lower tier's probability.
        if allowMythic and (not mythicUsed) and roll <= MYTHIC_CHANCE_PERCENT then
            pattern[i] = "mythic"
            mythicUsed = true
        elseif allowLegendary and (not legendaryUsed)
                and roll > MYTHIC_CHANCE_PERCENT
                and roll <= MYTHIC_CHANCE_PERCENT + LEGENDARY_CHANCE_PERCENT then
            pattern[i] = "legendary"
            legendaryUsed = true
        elseif allowRare and roll > MYTHIC_CHANCE_PERCENT + LEGENDARY_CHANCE_PERCENT
                and roll <= MYTHIC_CHANCE_PERCENT + LEGENDARY_CHANCE_PERCENT
                    + RARE_CHANCE_PERCENT then
            pattern[i] = "rare"
        else
            pattern[i] = "common"
        end
    end
    return pattern
end

-- Remove and return a weighted random buff of the bucket, preferring ids not in
-- avoidIds (options already used by the other side this tick). Tier-II catalog
-- entries use a larger draftWeight, but rarity-slot probabilities stay unchanged.
local function TakeRandomBuff(bucket, avoidIds)
    local count = table.getn(bucket)
    if count == 0 then
        return nil
    end
    local preferred = {}
    for i = 1, count do
        if not avoidIds[bucket[i].id] then
            table.insert(preferred, i)
        end
    end
    local candidates = preferred
    if table.getn(candidates) == 0 then
        -- only overlapping candidates left: identical id across sides is allowed
        candidates = {}
        for i = 1, count do
            table.insert(candidates, i)
        end
    end
    local totalWeight = 0
    for _, candidateIndex in candidates do
        local weight = math.max(1, math.floor(bucket[candidateIndex].draftWeight or 1))
        totalWeight = totalWeight + weight
    end
    local roll = Random(1, totalWeight)
    local index = candidates[table.getn(candidates)]
    for _, candidateIndex in candidates do
        local weight = math.max(1, math.floor(bucket[candidateIndex].draftWeight or 1))
        roll = roll - weight
        if roll <= 0 then
            index = candidateIndex
            break
        end
    end
    return table.remove(bucket, index)
end

-- Fill the side's options following the shared pattern, downgrading slots this
-- side cannot honor (lock/cooldown/no candidates). Picked/pending no-repeat
-- filters are already applied by AvailableBuffs.
local function FillSideOptions(sideName, pattern, allow, avoidIds, ignoredChoice)
    local available = AvailableBuffs(sideName, ignoredChoice)
    local buckets = { common = {}, rare = {}, legendary = {}, mythic = {} }
    for _, buff in available do
        table.insert(buckets[BuffRarity(buff)], buff)
    end

    local options = {}
    local usedRarity = { legendary = false, mythic = false }
    for _, wanted in pattern do
        local rarity = wanted
        -- side-specific eligibility downgrades
        if rarity == "mythic" and not allow.mythic then
            local fallback = allow.legendary and (not usedRarity.legendary) and "legendary"
                or (allow.rare and "rare" or "common")
            LOG("FAF_BUFF_DRAFT: rarity downgrade side=" .. sideName
                .. " from=mythic to=" .. fallback
                .. " reason=" .. tostring(allow.mythicReason))
            rarity = fallback
        elseif rarity == "legendary" and not allow.legendary then
            LOG("FAF_BUFF_DRAFT: rarity downgrade side=" .. sideName
                .. " from=legendary to=" .. (allow.rare and "rare" or "common")
                .. " reason=" .. tostring(allow.legendaryReason))
            rarity = allow.rare and "rare" or "common"
        elseif rarity == "rare" and not allow.rare then
            LOG("FAF_BUFF_DRAFT: rarity downgrade side=" .. sideName
                .. " from=rare to=common reason=" .. tostring(allow.rareReason))
            rarity = "common"
        end
        -- Candidate fallbacks must not accidentally create a second top-tier
        -- option after the shared rarity pattern already used that tier.
        if rarity == "mythic" and usedRarity.mythic then
            rarity = allow.legendary and (not usedRarity.legendary) and "legendary"
                or (allow.rare and "rare" or "common")
        elseif rarity == "legendary" and usedRarity.legendary then
            rarity = allow.rare and "rare" or "common"
        end
        -- candidate downgrades when a bucket is empty
        local chosen = nil
        while true do
            chosen = TakeRandomBuff(buckets[rarity], avoidIds)
            if chosen then
                break
            end
            if rarity == "mythic" then
                local fallback = allow.legendary and (not usedRarity.legendary) and "legendary"
                    or (allow.rare and "rare" or "common")
                LOG("FAF_BUFF_DRAFT: rarity downgrade side=" .. sideName
                    .. " from=mythic to=" .. fallback
                    .. " reason=no mythic candidates left")
                rarity = fallback
            elseif rarity == "legendary" then
                LOG("FAF_BUFF_DRAFT: rarity downgrade side=" .. sideName
                    .. " from=legendary to=rare reason=no legendary candidates left")
                rarity = "rare"
            elseif rarity == "rare" then
                LOG("FAF_BUFF_DRAFT: rarity downgrade side=" .. sideName
                    .. " from=rare to=common reason=no rare candidates left")
                rarity = "common"
            else
                break -- common bucket empty; upward fallback below
            end
        end
        -- commons exhausted (late game): fall back upward, but only into tiers
        -- this side has already unlocked
        if (not chosen) and allow.rare then
            chosen = TakeRandomBuff(buckets.rare, avoidIds)
            if chosen then
                LOG("FAF_BUFF_DRAFT: rarity downgrade side=" .. sideName
                    .. " from=common to=rare reason=no common candidates left")
            end
        end
        if (not chosen) and allow.legendary and (not usedRarity.legendary) then
            chosen = TakeRandomBuff(buckets.legendary, avoidIds)
            if chosen then
                LOG("FAF_BUFF_DRAFT: rarity downgrade side=" .. sideName
                    .. " from=common to=legendary reason=only legendary candidates left")
            end
        end
        if (not chosen) and allow.mythic and (not usedRarity.mythic) then
            chosen = TakeRandomBuff(buckets.mythic, avoidIds)
            if chosen then
                LOG("FAF_BUFF_DRAFT: rarity downgrade side=" .. sideName
                    .. " from=common to=mythic reason=only mythic candidates left")
            end
        end
        if chosen then
            table.insert(options, chosen)
            local chosenRarity = BuffRarity(chosen)
            if usedRarity[chosenRarity] ~= nil then
                usedRarity[chosenRarity] = true
            end
            avoidIds[chosen.id] = true -- steer the other side away from this id
        end
    end
    return options
end

--#endregion

-- table.concat in SupCom's Lua only accepts strings, so convert everything with
-- tostring first. Accepts a list of buff tables or plain ids; "none" for nil/empty.
local function BuffIdsToString(list)
    if (not list) or table.getn(list) == 0 then
        return "none"
    end
    local ids = {}
    for _, entry in list do
        if type(entry) == "table" then
            table.insert(ids, tostring(entry.id))
        else
            table.insert(ids, tostring(entry))
        end
    end
    return table.concat(ids, ", ")
end

local function ArmiesToString(armies)
    local ids = {}
    for _, index in armies do
        table.insert(ids, tostring(index))
    end
    return table.concat(ids, ",")
end

-- The Sync table is flushed to the UI (and reset) every sim beat; accumulate events
-- in a list under one key so several events from the same beat all arrive.
local function SyncDraftEvent(event)
    Sync.BuffDraft = Sync.BuffDraft or {}
    table.insert(Sync.BuffDraft, event)
end

-- The chooser of a side is its human player; AI armies never choose.
local function FindHumanChooser(armies)
    for _, index in armies do
        local brain = ArmyBrains[index]
        if brain and brain.BrainType == 'Human' and not brain.Civilian then
            return index
        end
    end
    return nil
end

-- Picked history as plain data for the UI history panel: { {id, title}, ... }
local function HistoryPicksForSync(sideName)
    local picks = {}
    for _, pickedId in PickedHistory[sideName] do
        local title = pickedId
        for _, buff in BuffCatalog do
            if buff.id == pickedId then
                title = buff.title
                break
            end
        end
        table.insert(picks, { id = pickedId, title = title })
    end
    return picks
end

-- Publish the side's current queue state: the count for the indicator and the first
-- choice of the queue for the choice window.
local function SyncPendingState(sideName, chooserArmy)
    local queue = PendingChoices[sideName]
    local first = queue[1]
    SyncDraftEvent({
        event = "pending",
        side = sideName,
        chooserArmy = chooserArmy,
        count = table.getn(queue),
        rerollAvailable = not RerollUsed[sideName],
        first = first and {
            tick = first.tick,
            revision = first.revision or 0,
            options = first.options,
        } or nil,
    })
end

-- Common tail of every pick: record it, update the player's history panel and
-- apply the gameplay effect.
local function ApplyResolvedPick(sideName, choice, buffId, reason)
    table.insert(PickedHistory[sideName], buffId)
    LOG("FAF_BUFF_DRAFT: " .. sideName .. " picked: " .. tostring(buffId) .. " (" .. reason .. ")")

    -- Resolved choices after the offer count down the top-tier cooldowns. The
    -- choice containing the offer itself does not consume one cooldown step;
    -- admin grants are not draft choices either.
    local offeredLegendary = false
    local offeredMythic = false
    for _, option in choice.options or {} do
        offeredLegendary = offeredLegendary or BuffRarity(option) == "legendary"
        offeredMythic = offeredMythic or BuffRarity(option) == "mythic"
    end
    if reason ~= "admin grant" and (not offeredLegendary)
            and LegendaryCooldownRemaining[sideName] > 0 then
        LegendaryCooldownRemaining[sideName] = LegendaryCooldownRemaining[sideName] - 1
        LOG("FAF_BUFF_DRAFT: legendary cooldown side=" .. sideName
            .. " remaining=" .. tostring(LegendaryCooldownRemaining[sideName]))
    end
    if reason ~= "admin grant" and (not offeredMythic)
            and MythicCooldownRemaining[sideName] > 0 then
        MythicCooldownRemaining[sideName] = MythicCooldownRemaining[sideName] - 1
        LOG("FAF_BUFF_DRAFT: mythic cooldown side=" .. sideName
            .. " remaining=" .. tostring(MythicCooldownRemaining[sideName]))
    end
    LOG("FAF_BUFF_DRAFT: " .. sideName .. " picked history: " .. BuffIdsToString(PickedHistory[sideName]))

    if choice.chooserArmy then
        SyncDraftEvent({
            event = "history",
            side = sideName,
            chooserArmy = choice.chooserArmy,
            picks = HistoryPicksForSync(sideName),
        })
    end

    import('/mods/BuffDraft/lua/effects.lua').ApplyPickedBuff(sideName, choice.armies, buffId)
end

local function DraftSide(tick, sideName, armies, pattern, allow, avoidIds)
    LOG("FAF_BUFF_DRAFT: " .. sideName .. " armies: " .. ArmiesToString(armies))

    local _, pendingIds = AvailableBuffs(sideName)
    LOG("FAF_BUFF_DRAFT: unavailable buffs side=" .. sideName
        .. ": picked=" .. BuffIdsToString(PickedHistory[sideName])
        .. " pending=" .. BuffIdsToString(pendingIds))

    -- fewer candidates than pattern slots: offer as many as there are
    local options = FillSideOptions(sideName, pattern, allow, avoidIds)

    -- a legendary was actually offered: block further legendaries for this side
    -- until enough choices have been resolved
    for _, option in options do
        if BuffRarity(option) == "legendary" then
            LegendaryCooldownRemaining[sideName] = LEGENDARY_COOLDOWN_CHOICES
            LOG("FAF_BUFF_DRAFT: legendary cooldown side=" .. sideName
                .. " remaining=" .. tostring(LEGENDARY_COOLDOWN_CHOICES))
        elseif BuffRarity(option) == "mythic" then
            MythicCooldownRemaining[sideName] = MYTHIC_COOLDOWN_CHOICES
            LOG("FAF_BUFF_DRAFT: mythic cooldown side=" .. sideName
                .. " remaining=" .. tostring(MYTHIC_COOLDOWN_CHOICES))
        end
    end

    if table.getn(options) == 0 then
        LOG("FAF_BUFF_DRAFT: no buffs available for side=" .. sideName)
        return
    end
    LOG("FAF_BUFF_DRAFT: options side=" .. sideName .. ": " .. BuffIdsToString(options))

    local chooserArmy = FindHumanChooser(armies)
    if not chooserArmy then
        -- AI-only side: nobody to wait for, auto-pick immediately
        LOG("FAF_BUFF_DRAFT: " .. sideName .. " has no human chooser, auto-picking first option")
        ApplyResolvedPick(sideName,
            { tick = tick, armies = armies, chooserArmy = nil, options = options },
            options[1].id, "no human chooser")
        return
    end

    -- human side: queue the choice, the player picks whenever they want
    table.insert(PendingChoices[sideName], {
        tick = tick,
        revision = 0,
        options = options,
        armies = armies,
        chooserArmy = chooserArmy,
        rarityAllowance = allow,
    })
    LOG("FAF_BUFF_DRAFT: pending choice added side=" .. sideName .. " tick=" .. tick)
    LOG("FAF_BUFF_DRAFT: pending choices side=" .. sideName
        .. " count=" .. table.getn(PendingChoices[sideName]))
    SyncPendingState(sideName, chooserArmy)
end

--- Called from the SimCallbacks hook when a player presses Choose in the UI.
--- data = { side = "Mark"|"Artem", buffId = "...", tick = number }. Everything is
--- validated here: the pending choice must exist (matched by tick), the sender must
--- be the side's chooser and the buff id must be one of that choice's options.
function ReceivePick(data)
    local sideName = data.side
    local buffId = data.buffId
    local senderArmy = import('/lua/simutils.lua').GetCurrentCommandSourceArmy()

    local queue = sideName and PendingChoices[sideName]
    if not queue then
        LOG("FAF_BUFF_DRAFT: pick rejected: unknown side " .. tostring(sideName))
        return
    end

    local index, choice
    for i, entry in queue do
        if entry.tick == data.tick then
            index = i
            choice = entry
            break
        end
    end
    if not choice then
        LOG("FAF_BUFF_DRAFT: pick rejected: no pending choice side=" .. tostring(sideName)
            .. " tick=" .. tostring(data.tick))
        return
    end
    if senderArmy ~= choice.chooserArmy then
        LOG("FAF_BUFF_DRAFT: pick rejected: army " .. tostring(senderArmy)
            .. " is not the chooser for " .. tostring(sideName))
        return
    end

    local valid = false
    for _, option in choice.options do
        if option.id == buffId then
            valid = true
            break
        end
    end
    if not valid then
        LOG("FAF_BUFF_DRAFT: pick rejected: buff " .. tostring(buffId)
            .. " is not in the options of choice tick=" .. tostring(data.tick))
        return
    end

    table.remove(queue, index)
    LOG("FAF_BUFF_DRAFT: player picked side=" .. sideName .. " buff=" .. tostring(buffId))
    LOG("FAF_BUFF_DRAFT: pick resolved pending choice side=" .. sideName
        .. " tick=" .. tostring(data.tick) .. " remaining=" .. table.getn(queue))

    ApplyResolvedPick(sideName, choice, buffId, "player pick")
    SyncPendingState(sideName, choice.chooserArmy)
end

--- Replaces the currently displayed choice once per side per game. The rarity
--- pattern is copied from the existing options instead of being rolled again,
--- so this cannot improve or reduce rare/legendary/mythic probabilities.
function ReceiveReroll(data)
    local sideName = data and data.side
    local senderArmy = import('/lua/simutils.lua').GetCurrentCommandSourceArmy()
    local queue = sideName and PendingChoices[sideName]
    if not queue then
        LOG("FAF_BUFF_DRAFT: reroll rejected: unknown side " .. tostring(sideName))
        return
    end
    if RerollUsed[sideName] then
        LOG("FAF_BUFF_DRAFT: reroll rejected: already used side=" .. tostring(sideName))
        return
    end

    local choice = queue[1]
    if (not choice) or choice.tick ~= data.tick then
        LOG("FAF_BUFF_DRAFT: reroll rejected: choice is not first pending side="
            .. tostring(sideName) .. " tick=" .. tostring(data and data.tick))
        return
    end
    if senderArmy ~= choice.chooserArmy then
        LOG("FAF_BUFF_DRAFT: reroll rejected: army " .. tostring(senderArmy)
            .. " is not the chooser for " .. tostring(sideName))
        return
    end

    local pattern = {}
    local avoidOldIds = {}
    for _, option in choice.options do
        table.insert(pattern, BuffRarity(option))
        avoidOldIds[option.id] = true
    end

    -- Ignore this choice in the pending filter so its old options remain legal
    -- fallbacks, while avoidOldIds makes new ids win whenever alternatives exist.
    local options = FillSideOptions(sideName, pattern,
        choice.rarityAllowance or { rare = true, legendary = true, mythic = true },
        avoidOldIds, choice)
    if table.getn(options) == 0 then
        LOG("FAF_BUFF_DRAFT: reroll rejected: no replacement options side=" .. sideName)
        return
    end

    choice.options = options
    choice.revision = (choice.revision or 0) + 1
    RerollUsed[sideName] = true
    LOG("FAF_BUFF_DRAFT: reroll used side=" .. sideName
        .. " tick=" .. tostring(choice.tick)
        .. " options=" .. BuffIdsToString(options))
    SyncPendingState(sideName, choice.chooserArmy)
end

-- Side->armies mapping cached for the admin panel; set from the simInit hook at
-- BeginSession and refreshed on every draft tick.
local KnownSides = nil

function SetSides(sides)
    KnownSides = sides
end

local function SideArmies(sideName)
    if not KnownSides then
        return nil
    end
    if sideName == "Mark" then
        return KnownSides.mark
    elseif sideName == "Artem" then
        return KnownSides.artem
    end
    return nil
end

-- Admin access: DebugAdmin flag + the sender's brain Nickname must match one of
-- AdminOwnerNicknames. The nickname lives on the army brain
-- (brain.Nickname, set in OnCreateArmyBrain), so the sim validates it without
-- trusting anything the UI sent.
local function AdminAccessAllowed(senderArmy)
    local config = import('/mods/BuffDraft/lua/config.lua')
    if not config.DebugAdmin then
        LOG("FAF_BUFF_DRAFT_ADMIN: access denied DebugAdmin disabled in config")
        return false
    end
    local brain = ArmyBrains[senderArmy]
    local nickname = brain and brain.Nickname
    if not AdminAccess.IsNicknameAllowed(nickname) then
        LOG("FAF_BUFF_DRAFT_ADMIN: access denied " .. tostring(nickname)
            .. " (army " .. tostring(senderArmy) .. "; owners: "
            .. AdminAccess.ConfiguredOwnersText() .. ")")
        return false
    end
    LOG("FAF_BUFF_DRAFT_ADMIN: access allowed " .. tostring(nickname))
    return true
end

--- Admin (debug) grant: same path as a normal pick - records history, syncs the
--- panel and applies the effect - so no-repeat and the UI stay consistent.
--- data = { side = "Mark"|"Artem", buffId = "..." }; senderArmy from the callback.
function AdminGrantBuff(data, senderArmy)
    if not AdminAccessAllowed(senderArmy) then
        return
    end
    local sideName = data.side
    local buffId = data.buffId
    if not PickedHistory[sideName] then
        LOG("FAF_BUFF_DRAFT_ADMIN: grant rejected: unknown side " .. tostring(sideName))
        return
    end
    local knownBuff = nil
    for _, buff in BuffCatalog do
        if buff.id == buffId then
            knownBuff = buff
            break
        end
    end
    if not knownBuff then
        LOG("FAF_BUFF_DRAFT_ADMIN: grant rejected: unknown buff " .. tostring(buffId))
        return
    end
    if knownBuff.prerequisite and not IsPicked(sideName, knownBuff.prerequisite) then
        LOG("FAF_BUFF_DRAFT_ADMIN: grant rejected: " .. tostring(buffId)
            .. " requires " .. tostring(knownBuff.prerequisite) .. " for " .. sideName)
        return
    end
    if IsPicked(sideName, buffId) then
        LOG("FAF_BUFF_DRAFT_ADMIN: grant rejected: " .. tostring(buffId)
            .. " already picked by " .. sideName)
        return
    end
    if ListContains(PendingBuffIds(sideName), buffId) then
        LOG("FAF_BUFF_DRAFT_ADMIN: grant rejected: " .. tostring(buffId)
            .. " is an option in a pending choice of " .. sideName)
        return
    end
    local armies = SideArmies(sideName)
    if not armies then
        LOG("FAF_BUFF_DRAFT_ADMIN: grant rejected: side armies unknown (before BeginSession?)")
        return
    end

    LOG("FAF_BUFF_DRAFT_ADMIN: grant " .. tostring(buffId) .. " to " .. sideName
        .. " (by army " .. tostring(senderArmy) .. ")")
    ApplyResolvedPick(sideName,
        { tick = 0, armies = armies, chooserArmy = FindHumanChooser(armies) },
        buffId, "admin grant")
end

--- Admin (debug) remove: strips the effect via effects.RemovePickedBuff and takes
--- the buff out of the side's history so it can roll or be granted again.
function AdminRemoveBuff(data, senderArmy)
    if not AdminAccessAllowed(senderArmy) then
        return
    end
    local sideName = data.side
    local buffId = data.buffId
    local history = PickedHistory[sideName]
    if not history then
        LOG("FAF_BUFF_DRAFT_ADMIN: remove rejected: unknown side " .. tostring(sideName))
        return
    end
    if not IsPicked(sideName, buffId) then
        LOG("FAF_BUFF_DRAFT_ADMIN: remove rejected: " .. tostring(buffId)
            .. " is not picked by " .. sideName)
        return
    end
    local pendingIds = PendingBuffIds(sideName)
    for _, buff in BuffCatalog do
        if buff.prerequisite == buffId then
            if IsPicked(sideName, buff.id) then
                LOG("FAF_BUFF_DRAFT_ADMIN: remove rejected: " .. tostring(buffId)
                    .. " is required by picked buff " .. tostring(buff.id))
                return
            elseif ListContains(pendingIds, buff.id) then
                LOG("FAF_BUFF_DRAFT_ADMIN: remove rejected: " .. tostring(buffId)
                    .. " is required by pending option " .. tostring(buff.id))
                return
            end
        end
    end
    local armies = SideArmies(sideName)
    if not armies then
        LOG("FAF_BUFF_DRAFT_ADMIN: remove rejected: side armies unknown")
        return
    end

    local fully, notes = import('/mods/BuffDraft/lua/effects.lua')
        .RemovePickedBuff(sideName, armies, buffId)
    if not fully then
        LOG("FAF_BUFF_DRAFT_ADMIN: remove skipped " .. tostring(buffId) .. " because "
            .. tostring(notes ~= "" and notes or "no full unapply; disabled for future units only"))
    elseif notes and notes ~= "" then
        LOG("FAF_BUFF_DRAFT_ADMIN: remove notes for " .. tostring(buffId) .. ": " .. notes)
    end

    for i, pickedId in history do
        if pickedId == buffId then
            table.remove(history, i)
            break
        end
    end
    LOG("FAF_BUFF_DRAFT_ADMIN: remove " .. tostring(buffId) .. " from " .. sideName
        .. " (by army " .. tostring(senderArmy) .. ")")
    LOG("FAF_BUFF_DRAFT: " .. sideName .. " picked history: " .. BuffIdsToString(history))

    local chooserArmy = FindHumanChooser(armies)
    if chooserArmy then
        SyncDraftEvent({
            event = "history",
            side = sideName,
            chooserArmy = chooserArmy,
            picks = HistoryPicksForSync(sideName),
        })
    end
end

--- Runs one draft tick for both sides. `sides` comes from slot detection at
--- BeginSession: { mark = {armyIndex...}, artem = {armyIndex...} }, or nil when
--- side detection did not complete.
function RunDraftTick(tick, sides)
    if not sides then
        LOG("FAF_BUFF_DRAFT: draft skipped: side detection incomplete")
        return
    end
    KnownSides = sides

    LOG("FAF_BUFF_DRAFT: draft tick " .. tick .. " started")

    -- one shared rarity pattern per tick: both sides see the same slot rarities
    -- (same rarity, not same buff). A tier enters the pattern when at least one
    -- side is eligible; the other side downgrades its slot with a logged reason.
    local allowMark = SideRarityAllowance("Mark")
    local allowArtem = SideRarityAllowance("Artem")
    local pattern = RollRarityPattern(
        allowMark.rare or allowArtem.rare,
        allowMark.legendary or allowArtem.legendary,
        allowMark.mythic or allowArtem.mythic)
    local patternIds = {}
    for _, rarity in pattern do
        table.insert(patternIds, tostring(rarity))
    end
    LOG("FAF_BUFF_DRAFT: rarity pattern tick=" .. tostring(tick)
        .. " pattern=" .. table.concat(patternIds, ","))

    -- shared avoid-set: sides should not offer identical buff ids on the same
    -- tick when avoidable (falls back to duplicates when nothing else is left)
    local avoidIds = {}
    DraftSide(tick, "Mark", sides.mark, pattern, allowMark, avoidIds)
    DraftSide(tick, "Artem", sides.artem, pattern, allowArtem, avoidIds)
    LOG("FAF_BUFF_DRAFT: draft tick " .. tick .. " complete")
end
