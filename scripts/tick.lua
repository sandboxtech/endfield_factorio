-- 周期性事件：自动跃迁倒计时 + 点击 HUD 自杀脱困。
local constants = require('scripts.constants')
local reset = require('scripts.reset')

-- 点击左上 run 按钮 = 自杀回母星（用于卡死时脱困）。
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    if event.element.name == 'introduction' then
        local last_run_ticks = (game.tick - (storage.run_start_tick or game.tick))
        local life_total = ((storage.hour_auto_reset or 1) * constants.hour_to_tick)
        local life = life_total - last_run_ticks

        if player.character then
            player.teleport({0, 0}, 'nauvis')
            player.character.die()
            game.print({'wn.suicide-notice', player.name,
                        math.floor(100 * life / constants.hour_to_tick) / 100})
        end
    end
end)

-- 临近跃迁时提醒玩家撤离：最后 1/3/5/10/20/30 分钟，以及之前每整点小时。
local warn_minutes = {[1]=true, [3]=true, [5]=true, [10]=true, [20]=true, [30]=true}

-- 每分钟检查：到点跃迁；到撤离阈值时广播提醒。
script.on_nth_tick(60 * 60, function()
    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local life = (storage.hour_auto_reset or 1) * constants.hour_to_tick - last_run_ticks

    if life <= 0 then
        reset.reset()
        return
    end

    local minutes = math.floor(life / constants.min_to_tick)
    if warn_minutes[minutes] or (minutes > 30 and minutes % 60 == 0) then
        local label
        if minutes >= 60 and minutes % 60 == 0 then
            label = string.format('%d 小时', minutes / 60)
        else
            label = string.format('%d 分钟', minutes)
        end
        game.print('⚠ 距离跃迁还剩 ' .. label .. '，请准备撤离至飞船')
    end
end)
