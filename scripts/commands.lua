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

commands.add_command('exp', {'wn.exp-help'}, function(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then return end
    players.print_science_exp(player)
end)

commands.add_command('exp_clear', {'wn.exp-clear-help'}, function(command)
    if not require_admin(command) then return end
    storage.science_exp = {}
    game.print({'wn.exp-cleared'})
end)

-- /productivity <tech_name> <level>
-- 例：/productivity steel-plate-productivity 5  → 钢板产能科技升到 5 级
-- 仅对无限产能科技（type=change-recipe-productivity）有效。
commands.add_command('productivity', '测试用：设置某个无限产能科技的等级', function(command)
    if not require_admin(command) then return end
    local args = {}
    for w in string.gmatch(command.parameter or '', '%S+') do
        table.insert(args, w)
    end
    local tech_name, level = args[1], tonumber(args[2])
    if not tech_name or not level then
        game.print('用法：/productivity <tech_name> <level>，例如 /productivity steel-plate-productivity 5')
        return
    end
    local tech = game.forces.player.technologies[tech_name]
    if not tech then
        game.print('找不到科技：' .. tech_name)
        return
    end
    tech.researched = true
    tech.level = level
    game.print(string.format('[technology=%s] level = %d', tech_name, level))
end)
