-- BuffDraft MVP 5: sim callback that receives the player's buff pick from the UI.
-- This file is concatenated to the end of /lua/SimCallbacks.lua before it runs, so
-- the file-local `Callbacks` table of the original script is visible here.

Callbacks.BuffDraftPick = function(data, units)
    import('/mods/BuffDraft/lua/draft.lua').ReceivePick(data)
end
