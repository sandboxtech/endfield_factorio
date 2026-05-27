-- 命令注册：管理/调试用。
-- 玩家从控制台调用时 player_index 为 nil，此时视作管理员。
local constants = require('scripts.constants')
local gui = require('scripts.gui')
local reset = require('scripts.reset')
local players = require('scripts.players')

-- 包装：仅管理员可执行；返回 player 或 nil（控制台也算管理员）
local function require_admin(command)
    local player = game.get_player(command.player_index)
    if not player then return nil end
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

commands.add_command('life', {'wn.life-help'}, function(command)
    local player = command.player_index and game.get_player(command.player_index)
    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local total_hours = storage.warp_hours or 1
    local life_hours = (total_hours * constants.hour_to_tick - last_run_ticks) / constants.hour_to_tick
    local msg = {'wn.life-status', math.floor(life_hours * 100) / 100, total_hours}
    if player then player.print(msg) else game.print(msg) end
end)

-- （/exp 已删除：与 /inspect（无参数=看自己）重复。print_science_exp 仍由玩家加入时的广播使用。）

-- /inspect <玩家名>（/chakan 同功能，中文拼音别名）：打印目标玩家的科技瓶经验。
-- 省略玩家名 = 查看自己。查看别人会用 game.print 公告；查看自己时不公告。
local function inspect_cmd(command)
    local viewer = command.player_index and game.get_player(command.player_index)
    if not viewer then return end
    local name = command.parameter and string.match(command.parameter, '%S+')
    local target = name and game.get_player(name) or viewer
    if not target then
        viewer.print({'wn.inspect-no-such-player', name or ''})
        return
    end
    players.print_inspection(target, viewer)
    -- 向所有玩家公告：谁用什么指令查看了谁（command.name 是 'inspect' 或 'chakan'）
    game.print({'wn.inspect-notice', viewer.name, command.name, target.name})
end

commands.add_command('inspect', {'wn.inspect-help'}, inspect_cmd)
commands.add_command('chakan', {'wn.inspect-help'}, inspect_cmd)

commands.add_command('exp_clear', {'wn.exp-clear-help'}, function(command)
    if not require_admin(command) then return end
    storage.science_exp = {}
    game.print({'wn.exp-cleared'})
end)
