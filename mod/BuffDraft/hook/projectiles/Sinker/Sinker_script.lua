-- The sinker starts after a delay. If another death path destroyed its target in
-- the meantime, the stock AttachBoneTo call errors. Finish the callback cleanly.

do
    local oldStartSinking = Sinker.StartSinking

    Sinker.StartSinking = function(self, targetEntity, targetBone)
        if IsDestroyed(targetEntity) then
            self:Destroy()
            return
        end
        local ok, result = pcall(oldStartSinking, self, targetEntity, targetBone)
        if ok then
            return result
        end

        LOG("FAF_BUFF_DRAFT: sinker attachment failed; completing unit destruction: "
            .. tostring(result))
        self:Destroy()
        if self.callback then
            ForkThread(self.callback)
        end
    end
end
