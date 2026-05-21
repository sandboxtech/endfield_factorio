-- 研究完成时：若该科技解锁了新科技瓶（科技名以 -science-pack 结尾），
-- 把本轮自动跃迁的时长延长 1 小时。其它科技无效果。
local constants = require('scripts.constants')

script.on_event(defines.events.on_research_finished, function(event)
    if event.by_script then
        return
    end
    local research = event.research
    -- 严格匹配后缀，避免误伤可能的 "*-science-pack-*" 变体
    if string.sub(research.name, -13) ~= '-science-pack' then
        return
    end

    storage.hour_auto_reset = (storage.hour_auto_reset or 1) + 1
    local remaining_hours = storage.hour_auto_reset -
        (game.tick - (storage.run_start_tick or game.tick)) / constants.hour_to_tick
    game.print(string.format('[item=%s] +1h  剩余 %.2fh', research.name, remaining_hours))
end)
