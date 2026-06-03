local constants = require('scripts.constants')
local util = require('scripts.util')
local player_stats = require('scripts.player_stats')
local science_exp = require('scripts.science_exp')
local gui = require('scripts.gui')

-- 研究完成时：给在线玩家各记一次研究；若该科技名以 -science-pack 结尾（关键科技），额外记一次并把本轮跃迁倒计时延长一段（分钟数按 warp_extend_minutes 各瓶配置，缺省 warp_extend_default_minutes；含 SA 的 trigger 解锁瓶）。
script.on_event(defines.events.on_research_finished, function(event)
    if event.by_script then
        return
    end

    player_stats.bump_connected('research')   -- 在线玩家各记一次"研究完成"

    local research = event.research

    -- 【无限产能科技经验】：完成 storage.prod_exp_techs 里的科技时（每升一级触发一次）→ 全体在线玩家各 +1，
    -- 记进 storage.exp[玩家名][科技名]（与科技瓶经验同表、不同键）。研究产能越高、升级越快 → 这类经验涨得越多。
    if (storage.prod_exp_techs or {})[research.name] then
        for _, player in pairs(game.connected_players) do
            local pexp = science_exp.player_exp(player, true)
            pexp[research.name] = (pexp[research.name] or 0) + 1
        end
    end

    -- 研究【连带自动解锁】：研完源科技 → 自动研究映射表里的目标科技（storage.auto_research，可 /c 热改）。
    -- 目标科技存在且未研究才设；by_script 触发的二次 on_research_finished 会被本函数开头的 by_script 挡掉，不递归。
    local auto = storage.auto_research and storage.auto_research[research.name]
    if auto then
        local target = research.force.technologies[auto]
        if target and not target.researched then
            target.researched = true   -- 直接置已研究 → 该科技全部 effects（解锁的配方等）立即生效
        end
    end

    -- 严格匹配后缀，避免误伤可能的 "*-science-pack-*" 变体
    if string.sub(research.name, -13) ~= '-science-pack' then
        return
    end

    player_stats.bump_connected('key_research')   -- 关键科技：解锁科技瓶 → 延长跃迁时间
    -- 每种瓶延长的分钟数存 storage.warp_extend_minutes（可 /c 热改）；表里没有的用 warp_extend_default_minutes。
    local add_min = (storage.warp_extend_minutes and storage.warp_extend_minutes[research.name])
                    or storage.warp_extend_default_minutes or 60
    storage.warp_hours = (storage.warp_hours or ((storage.warp_initial_minutes or 10) / 60)) + add_min / 60
    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    -- 若此刻跃迁投票处于"想跃迁"状态（warp_vote_delta 已施加），把刚加的时间也并入【投票缩减】，
    -- 倒计时仍钳在 target(默认5分钟)——否则研发加时会让"已投票通过要跃迁"的倒计时又被拉长。
    -- delta 累加本次新砍量 → 日后改票取消时仍能把"自然总时长(含本次研发)"完整加回（投票永不能阻止跃迁的不变量保持）。
    if storage.warp_vote_delta ~= nil then
        local target = (storage.warp_vote_target_minutes or 5) * constants.min_to_tick
        local new_hours = (last_run_ticks + target) / constants.hour_to_tick
        storage.warp_vote_delta = storage.warp_vote_delta + (storage.warp_hours - new_hours)
        storage.warp_hours = new_hours
    end
    local total_ticks = storage.warp_hours * constants.hour_to_tick
    local th, tm = util.hm(total_ticks)                 -- 本轮共
    local rh, rm = util.hm(total_ticks - last_run_ticks)   -- 剩余
    game.print({'wn.warp-extend-tech', research.name, add_min, th, tm, rh, rm})
    gui.refresh_countdown()   -- 倒计时已变 → 立刻刷新所有人头顶 UI（否则要等下一分钟整点才更新）
end)
