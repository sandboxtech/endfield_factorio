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
        local life_total = ((storage.hour_auto_reset or 50) * constants.hour_to_tick)
        local life = life_total - last_run_ticks

        if player.character then
            player.teleport({0, 0}, 'nauvis')
            player.character.die()
            game.print({'wn.suicide-notice', player.name,
                        math.floor(100 * life / constants.hour_to_tick) / 100})
        end
    end
end)

-- 每分钟检查：临近跃迁时降低游戏速度，给玩家撤离时间；到时强制跃迁。
script.on_nth_tick(60 * 60 * 60, function()
    local last_run_ticks = (game.tick - (storage.run_start_tick or game.tick))
    local life_total = ((storage.hour_auto_reset or 100) * constants.hour_to_tick)
    local life = life_total - last_run_ticks

    if life <= 0 then
        reset.reset()
        return
    end

    -- 剩 1/25 寿命降到 0.25 倍速，剩 1/5 寿命降到 0.5 倍速
    local new_speed
    if life < life_total / 25 then
        new_speed = 0.25
    elseif life < life_total / 5 then
        new_speed = 0.5
    end
    if new_speed and game.speed > new_speed then
        game.speed = new_speed
        game.print({'wn.game-speed-notice', game.speed})
    end
end)
