-- BuffDraft MVP 5: forward sim draft events to the mod UI. Concatenated to the end
-- of /lua/UserSync.lua; same wrap pattern as the U4S mod's UserSync hook.

do
    local oldOnSync = OnSync
    function OnSync()
        oldOnSync()

        -- OnSync runs from the beginning of the match, before the first draft
        -- event. Initialize the persistent panel here instead of waiting for the
        -- first pending/history event five minutes into the game.
        import('/mods/BuffDraft/lua/ui/history.lua').Initialize()

        if Sync.BuffDraft then
            import('/mods/BuffDraft/lua/ui/draftui.lua').ProcessEvents(Sync.BuffDraft)
        end
    end
end
