-- Guard an engine adjacency edge case seen when external factories finish units:
-- OnAdjacentTo / OnNotAdjacentTo can receive an entity without an EntityId. The
-- stock method then indexes AdjacentUnits[nil] and aborts the entity callback.

do
    local oldStructureUnit = StructureUnit

    local function HasAdjacencyIdentity(unit)
        return unit and IsEntity(unit) and unit.EntityId
    end

    StructureUnit = Class(oldStructureUnit) {
        OnAdjacentTo = function(self, adjacentUnit, triggerUnit)
            if not HasAdjacencyIdentity(self) or not HasAdjacencyIdentity(adjacentUnit) then
                LOG("FAF_BUFF_DRAFT: skipped adjacency event with missing EntityId")
                return
            end
            return oldStructureUnit.OnAdjacentTo(self, adjacentUnit, triggerUnit)
        end,

        OnNotAdjacentTo = function(self, adjacentUnit)
            if not HasAdjacencyIdentity(self) or not HasAdjacencyIdentity(adjacentUnit) then
                LOG("FAF_BUFF_DRAFT: skipped adjacency removal with missing EntityId")
                return
            end
            if not self.AdjacentUnits or not adjacentUnit.AdjacentUnits then
                return
            end
            return oldStructureUnit.OnNotAdjacentTo(self, adjacentUnit)
        end,
    }
end
