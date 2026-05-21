-- 研究完成时：若该科技名以 -science-pack 结尾（解锁了新科技瓶），
-- 把本轮跃迁倒计时延长 1 小时。其它科技无效果。
script.on_event(defines.events.on_research_finished, function(event)
    if event.by_script then
        return
    end
    local research = event.research
    -- 严格匹配后缀，避免误伤可能的 "*-science-pack-*" 变体
    if string.sub(research.name, -13) ~= '-science-pack' then
        return
    end

    storage.warp_hours = (storage.warp_hours or 1) + 1
    game.print({'wn.warp-extend-tech', research.name, storage.warp_hours})
end)
