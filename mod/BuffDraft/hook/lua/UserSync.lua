-- BuffDraft MVP 5: forward sim draft events to the mod UI. Concatenated to the end
-- of /lua/UserSync.lua; same wrap pattern as the U4S mod's UserSync hook.

do
    local oldOnSync = OnSync
    function OnSync()
        oldOnSync()
        if Sync.BuffDraft then
            import('/mods/BuffDraft/lua/ui/draftui.lua').ProcessEvents(Sync.BuffDraft)
        end
    end
end
