-- Public warning markers for game-ending long-range weapons.
-- Gameplay detection and marker lifetime live in SIM; no unit intel is granted.

local Entity = import('/lua/sim/entity.lua').Entity

local WarningCategory =
    (categories.ARTILLERY * categories.STRUCTURE * categories.TECH3)
    + ((categories.ARTILLERY * categories.EXPERIMENTAL * categories.STRATEGIC) - categories.FACTORY)
    + categories.xsb2401 -- Yolona Oss

local function TrackWarningMarker(unit, marker)
    local time = 0

    while IsEntity(unit) and not unit.Dead and IsEntity(marker) do
        local position = unit:GetPosition()
        Warp(marker, Vector(position[1], position[2] + 2, position[3]))

        -- Same pulse used by the stock FAF ping mesh.
        marker:SetScale(MATH_Lerp(math.sin(time), -0.5, 0.5, 0.3, 0.5))
        time = time + 0.3
        WaitSeconds(0.1)
    end

    if IsEntity(marker) then
        marker:Destroy()
    end
end

function OnUnitCreated(unit)
    if unit.BuffDraftStrategicWarning or not EntityCategoryContains(WarningCategory, unit) then
        return
    end

    local position = unit:GetPosition()
    local marker = Entity { Owner = unit.Army - 1, Location = position }
    Warp(marker, Vector(position[1], position[2] + 2, position[3]))

    -- Deliberately public: the warning remains visible through fog of war.
    marker:SetVizToFocusPlayer('Always')
    marker:SetVizToEnemies('Always')
    marker:SetVizToAllies('Always')
    marker:SetVizToNeutrals('Always')
    marker:SetMesh('/meshes/game/ping_nuke_marker')

    unit.BuffDraftStrategicWarning = marker
    unit.Trash:Add(marker)
    unit.Trash:Add(ForkThread(TrackWarningMarker, unit, marker))

    LOG('FAF_BUFF_DRAFT: strategic warning marker created for '
        .. tostring(unit.UnitId) .. ' entity=' .. tostring(unit.EntityId))
end
