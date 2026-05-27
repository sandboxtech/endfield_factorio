-- 命令注册：管理/调试用。
-- 玩家从控制台调用时 player_index 为 nil，此时视作管理员。
local constants = require('scripts.constants')
local gui = require('scripts.gui')
local reset = require('scripts.reset')
local players = require('scripts.players')
local science_exp = require('scripts.science_exp')

-- 包装：仅管理员可执行；返回 player 或 nil（控制台也算管理员）
local function require_admin(command)
    local player = game.get_player(command.player_index)
    if not player then return nil end
    if player.admin then return player end
    player.print(constants.not_admin_text)
    return nil
end

-- 任何自定义指令被使用时，私聊通知所有在线管理员：谁用了什么指令（含参数）。
-- 控制台调用（无 player_index）不通知；不通知使用者本人（即便他是管理员）。
local function notify_admins(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then return end
    local what = '/' .. command.name
    if command.parameter then what = what .. ' ' .. command.parameter end
    for _, admin in pairs(game.connected_players) do
        if admin.admin and admin.index ~= player.index then
            admin.print({'wn.cmd-used', player.name, what})
        end
    end
end

-- 用本函数代替 commands.add_command 注册：执行前先向管理员审计一条"谁用了什么"。
local function add_command(name, help, fn)
    commands.add_command(name, help, function(command)
        notify_admins(command)
        fn(command)
    end)
end

add_command('reset', {'wn.run-reset-help'}, function(command)
    if not command.player_index then return end
    local player = game.get_player(command.player_index)
    if not player or player.admin then
        reset.reset()
    else
        player.print(constants.not_admin_text)
    end
end)

add_command('players_gui', {'wn.players-gui-help'}, function(command)
    local player = game.get_player(command.player_index)
    if not player or player.admin then
        gui.players_gui()
    else
        player.print(constants.not_admin_text)
    end
end)

-- 显示距下次自动跃迁的剩余时间。主名 /countdown，/life 作旧别名保留。
local function countdown_cmd(command)
    local player = command.player_index and game.get_player(command.player_index)
    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local total_hours = storage.warp_hours or 1
    local life_hours = (total_hours * constants.hour_to_tick - last_run_ticks) / constants.hour_to_tick
    local msg = {'wn.life-status', math.floor(life_hours * 100) / 100, total_hours}
    if player then player.print(msg) else game.print(msg) end
end

add_command('countdown', {'wn.life-help'}, countdown_cmd)
add_command('daojishi', {'wn.life-help'}, countdown_cmd)
add_command('life', {'wn.life-help'}, countdown_cmd)

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

add_command('inspect', {'wn.inspect-help'}, inspect_cmd)
add_command('chakan', {'wn.inspect-help'}, inspect_cmd)

add_command('exp_clear', {'wn.exp-clear-help'}, function(command)
    if not require_admin(command) then return end
    storage.science_exp = {}
    game.print({'wn.exp-cleared'})
end)

-- /tutorial（/jiaocheng 同功能）：把游戏教程打给自己。（管理员审计由 add_command 统一处理）
local function tutorial_cmd(command)
    local viewer = command.player_index and game.get_player(command.player_index)
    if not viewer then return end
    viewer.print({'wn.tutorial'})
end

add_command('tutorial', {'wn.tutorial-help'}, tutorial_cmd)
add_command('jiaocheng', {'wn.tutorial-help'}, tutorial_cmd)

-- /preview（/yulan 同功能）：若现在立即跃迁，背包里的科技瓶各能换多少经验。
local function preview_cmd(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then return end
    local gain = science_exp.preview(player)
    player.print({'wn.preview-header'})
    local any = false
    for _, pack in ipairs(constants.science_packs) do
        if (gain[pack] or 0) > 0 then
            any = true
            player.print({'wn.preview-entry', pack, gain[pack]})
        end
    end
    if not any then player.print({'wn.preview-none'}) end
end

add_command('preview', {'wn.preview-help'}, preview_cmd)
add_command('yulan', {'wn.preview-help'}, preview_cmd)
