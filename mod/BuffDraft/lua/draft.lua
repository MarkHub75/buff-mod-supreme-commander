-- BuffDraft MVP 3: sim-side draft pipeline. Rolls buff options and auto-picks them;
-- no gameplay effects are applied yet, everything only goes to game.log.

local BuffCatalog = import('/mods/BuffDraft/lua/buffs.lua').BuffCatalog

local OPTIONS_PER_TICK = 3

-- Sim-side draft state: picked buff ids per side, in pick order. Import caching keeps
-- this module (and therefore this table) alive for the whole sim session.
local PickedHistory = {
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

-- Buffs this side has not picked yet. A buff picked by one side can still roll
-- for the other side.
local function AvailableBuffs(sideName)
    local available = {}
    for _, buff in BuffCatalog do
        if not IsPicked(sideName, buff.id) then
            table.insert(available, buff)
        end
    end
    return available
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

local function DraftSide(sideName, armies)
    LOG("FAF_BUFF_DRAFT: " .. sideName .. " armies: " .. ArmiesToString(armies))

    local available = AvailableBuffs(sideName)
    if table.getn(available) < OPTIONS_PER_TICK then
        LOG(string.format("FAF_BUFF_DRAFT: warning: only %d buff options available for %s",
            table.getn(available), sideName))
    end

    local options = RollOptions(available)
    if table.getn(options) == 0 then
        LOG("FAF_BUFF_DRAFT: " .. sideName .. " options: none, nothing to pick")
        return
    end
    LOG("FAF_BUFF_DRAFT: " .. sideName .. " options: " .. BuffIdsToString(options))

    -- auto-pick: always the first option for now
    local picked = options[1]
    table.insert(PickedHistory[sideName], picked.id)
    LOG("FAF_BUFF_DRAFT: " .. sideName .. " auto-picked: " .. tostring(picked.id))
    LOG("FAF_BUFF_DRAFT: " .. sideName .. " picked history: " .. BuffIdsToString(PickedHistory[sideName]))
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
    DraftSide("Mark", sides.mark)
    DraftSide("Artem", sides.artem)
    LOG("FAF_BUFF_DRAFT: draft tick " .. tick .. " complete")
end
