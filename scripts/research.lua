local constants = require('scripts.constants')

-- 研究完成时：若该科技名以 -science-pack 结尾且不是 trigger 科技，把本轮跃迁倒计时延长 1 小时。
--   红瓶（automation-science-pack）是 trigger 科技，不延长。
script.on_event(defines.events.on_research_finished, function(event)
    if event.by_script then
        return
    end

    local research = event.research
    -- 严格匹配后缀，避免误伤可能的 "*-science-pack-*" 变体
    if string.sub(research.name, -13) ~= '-science-pack' then
        return
    end
    -- trigger 科技（如红瓶）不延长跃迁时长
    if research.prototype and research.prototype.research_trigger then
        return
    end

    storage.warp_hours = (storage.warp_hours or 1) + 1
    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local life_hours = (storage.warp_hours * constants.hour_to_tick - last_run_ticks) / constants.hour_to_tick
    game.print({'wn.warp-extend-tech', research.name, storage.warp_hours,
                math.floor(life_hours * 100) / 100})
end)
