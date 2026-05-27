-- 周期性事件：自动跃迁倒计时 + 点击 HUD 自杀脱困。
-- 本文件是 on_gui_click 与 on_nth_tick(3600) 的唯一注册点；player_stats 的每分钟采样
-- 通过 player_stats.sample_online 接入，避免多文件重复注册 on_nth_tick 互相覆盖。
local constants = require('scripts.constants')
local reset = require('scripts.reset')
local players = require('scripts.players')
local player_stats = require('scripts.player_stats')

-- 点击左上 run 按钮 = 自杀回母星（用于卡死时脱困）。
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    if event.element.name == 'introduction' then
        local last_run_ticks = (game.tick - (storage.run_start_tick or game.tick))
        local life_total = ((storage.warp_hours or 1) * constants.hour_to_tick)
        local life = life_total - last_run_ticks

        if player.character then
            players.kill_on_nauvis(player)
            game.print({'wn.suicide-notice', player.name,
                        math.floor(100 * life / constants.hour_to_tick) / 100})
        end
    end
end)

-- 撤离提醒触发的分钟数集合：最后 1/3/5/10/20/30 分钟，以及之前每整点小时。
local warn_minutes = {[1] = true, [3] = true, [5] = true, [10] = true, [20] = true, [30] = true}

-- 每分钟统一处理：在线时长采样 + 跃迁倒计时 + 撤离提醒。
-- （player_stats 不再单独注册 on_nth_tick，统一在此调度，避免后注册者覆盖前者。）
script.on_nth_tick(60 * 60, function()
    player_stats.sample_online()

    -- 每分钟尝试给每个在线玩家塞 1 个普通金币（背包满则塞不进，忽略即可）。
    for _, player in pairs(game.connected_players) do
        if player.character then
            local main = player.get_inventory(defines.inventory.character_main)
            if main then main.insert{name = 'coin', count = 1} end
        end
    end

    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local life = (storage.warp_hours or 1) * constants.hour_to_tick - last_run_ticks

    if life <= 0 then
        reset.reset()
        return
    end

    local minutes = math.floor(life / constants.min_to_tick)
    if warn_minutes[minutes] or (minutes > 30 and minutes % 60 == 0) then
        local label
        if minutes >= 60 and minutes % 60 == 0 then
            label = {'wn.duration-hours', minutes / 60}
        else
            label = {'wn.duration-minutes', minutes}
        end
        game.print({'wn.warp-warning', label})
    end
end)
