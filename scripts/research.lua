local constants = require('scripts.constants')
local util = require('scripts.util')

-- 研究完成时：若该科技名以 -science-pack 结尾，把本轮跃迁倒计时延长 1 小时（含 SA 的 trigger 解锁瓶）。
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
    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local total_ticks = storage.warp_hours * constants.hour_to_tick
    local th, tm = util.hm(total_ticks)                 -- 本轮共
    local rh, rm = util.hm(total_ticks - last_run_ticks)   -- 剩余
    game.print({'wn.warp-extend-tech', research.name, th, tm, rh, rm})
end)
