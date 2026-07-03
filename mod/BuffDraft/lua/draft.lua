-- BuffDraft MVP 7: sim-side draft pipeline with a pending-choice queue. Every draft
-- tick rolls options for both sides; human sides get a pending choice added to their
-- queue (no auto-pick, no timeout) and pick whenever they press Choose in the UI.
-- AI-only sides still auto-pick the first option immediately. All rules are
-- validated sim-side; the UI only displays queue state and sends picks back.

local BuffCatalog = import('/mods/BuffDraft/lua/buffs.lua').BuffCatalog

local OPTIONS_PER_TICK = 3

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
local function PendingBuffIds(sideName)
    local ids = {}
    for _, choice in PendingChoices[sideName] do
        for _, option in choice.options do
            table.insert(ids, option.id)
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

-- Buffs this side can still roll: not in its picked history and not sitting in any
-- of its pending choices. A buff picked by one side can still roll for the other.
-- Returns the available list plus the pending id list (for logging).
local function AvailableBuffs(sideName)
    local pendingIds = PendingBuffIds(sideName)
    local available = {}
    for _, buff in BuffCatalog do
        if (not IsPicked(sideName, buff.id)) and (not ListContains(pendingIds, buff.id)) then
            table.insert(available, buff)
        end
    end
    return available, pendingIds
end

-- Roll up to OPTIONS_PER_TICK distinct options. Random() is the synchronized sim RNG,
-- so every peer rolls the same values (no os.time / real time involved).
local function RollOptions(available)
    local options = {}
    for i = 1, OPTIONS_PER_TICK do
        if table.getn(available) == 0 then
            break
        end
        table.insert(options, table.remove(available, Random(1, table.getn(available))))
    end
    return options
end

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
        first = first and { tick = first.tick, options = first.options } or nil,
    })
end

-- Common tail of every pick: record it, update the player's history panel and
-- apply the gameplay effect.
local function ApplyResolvedPick(sideName, choice, buffId, reason)
    table.insert(PickedHistory[sideName], buffId)
    LOG("FAF_BUFF_DRAFT: " .. sideName .. " picked: " .. tostring(buffId) .. " (" .. reason .. ")")
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

local function DraftSide(tick, sideName, armies)
    LOG("FAF_BUFF_DRAFT: " .. sideName .. " armies: " .. ArmiesToString(armies))

    local available, pendingIds = AvailableBuffs(sideName)
    LOG("FAF_BUFF_DRAFT: unavailable buffs side=" .. sideName
        .. ": picked=" .. BuffIdsToString(PickedHistory[sideName])
        .. " pending=" .. BuffIdsToString(pendingIds))

    -- fewer than OPTIONS_PER_TICK left: offer as many as there are
    local options = RollOptions(available)
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
            { tick = tick, armies = armies, chooserArmy = nil }, options[1].id, "no human chooser")
        return
    end

    -- human side: queue the choice, the player picks whenever they want
    table.insert(PendingChoices[sideName],
        { tick = tick, options = options, armies = armies, chooserArmy = chooserArmy })
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
    LOG("FAF_BUFF_DRAFT: pending choice removed side=" .. sideName
        .. " count=" .. table.getn(queue))

    ApplyResolvedPick(sideName, choice, buffId, "player pick")
    SyncPendingState(sideName, choice.chooserArmy)
end

--- Runs one draft tick for both sides. `sides` comes from slot detection at
--- BeginSession: { mark = {armyIndex...}, artem = {armyIndex...} }, or nil when
--- side detection did not complete.
function RunDraftTick(tick, sides)
    if not sides then
        LOG("FAF_BUFF_DRAFT: draft skipped: side detection incomplete")
        return
    end

    LOG("FAF_BUFF_DRAFT: draft tick " .. tick .. " started")
    DraftSide(tick, "Mark", sides.mark)
    DraftSide(tick, "Artem", sides.artem)
    LOG("FAF_BUFF_DRAFT: draft tick " .. tick .. " complete")
end
