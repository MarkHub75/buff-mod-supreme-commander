-- Shared deterministic nickname gate for the admin UI and SIM callbacks.
-- Keeping this in one module prevents UI visibility, buff admin actions and
-- Take AI from disagreeing about who owns the tools.

local Config = import('/mods/BuffDraft/lua/config.lua')

function IsNicknameAllowed(nickname)
    local owners = Config.AdminOwnerNicknames
    if type(owners) == 'table' and table.getn(owners) > 0 then
        for _, owner in owners do
            if nickname == owner then
                return true
            end
        end
        return false
    end

    -- Backwards-compatible fallback for older copies of config.lua.
    local legacyOwner = Config.AdminOwnerNickname
    if legacyOwner and legacyOwner ~= '' then
        return nickname == legacyOwner
    end
    return true -- no configured names: DebugAdmin is the only gate
end

function ConfiguredOwnersText()
    local owners = Config.AdminOwnerNicknames
    if type(owners) == 'table' and table.getn(owners) > 0 then
        local names = {}
        for _, owner in owners do
            table.insert(names, tostring(owner))
        end
        return table.concat(names, ', ')
    end
    return tostring(Config.AdminOwnerNickname or 'any nickname')
end
