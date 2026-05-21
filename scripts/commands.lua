-- 命令注册：管理/调试用。
-- 玩家从控制台调用时 player_index 为 nil，此时视作管理员。
local constants = require('scripts.constants')
local gui = require('scripts.gui')
local reset = require('scripts.reset')
local players = require('scripts.players')

-- 包装：仅管理员可执行；返回 player 或 nil
local function require_admin(command)
    local player = game.get_player(command.player_index)
    if not player then return nil end  -- 控制台
    if player.admin then return player end
    player.print(constants.not_admin_text)
    return nil
end

commands.add_command('reset', {'wn.run-reset-help'}, function(command)
    if not command.player_index then return end
    local player = game.get_player(command.player_index)
    if not player or player.admin then
        reset.reset()
    else
        player.print(constants.not_admin_text)
    end
end)

commands.add_command('players_gui', {'wn.players-gui-help'}, function(command)
    local player = game.get_player(command.player_index)
    if not player or player.admin then
        gui.players_gui()
    else
        player.print(constants.not_admin_text)
    end
end)

-- 显示当前轮剩余跃迁时长（小时，保留 2 位小数）。任何人可用。
commands.add_command('life', '显示距离下次自动跃迁剩余的小时数', function(command)
    local player = command.player_index and game.get_player(command.player_index)
    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local life_total = (storage.hour_auto_reset or 1) * constants.hour_to_tick
    local life_hours = (life_total - last_run_ticks) / constants.hour_to_tick
    local msg = string.format('life=%.2fh / %dh', life_hours, storage.hour_auto_reset or 1)
    if player then player.print(msg) else game.print(msg) end
end)

-- /exp  显示自己的科技瓶经验
commands.add_command('exp', '显示自己累积的所有科技瓶经验', function(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then return end
    players.print_science_exp(player)
end)

-- /exp_clear  管理员清空所有玩家经验（测试用）
commands.add_command('exp_clear', '清空所有玩家的科技瓶经验（测试用）', function(command)
    if not require_admin(command) then return end
    storage.science_exp = {}
    game.print('science_exp cleared')
end)
