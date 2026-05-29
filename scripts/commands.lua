-- 命令注册：管理/调试用。
-- 玩家从控制台调用时 player_index 为 nil，此时视作管理员。
local constants = require('scripts.constants')
local gui = require('scripts.gui')
local reset = require('scripts.reset')
local players = require('scripts.players')
local science_exp = require('scripts.science_exp')
local util = require('scripts.util')

-- 包装：仅管理员可执行；返回 player 或 nil（控制台也算管理员）
local function require_admin(command)
    local player = game.get_player(command.player_index)
    if not player then return nil end
    if player.admin then return player end
    player.print(constants.not_admin_text)
    return nil
end

-- 任何自定义指令被使用时，公告给【所有在线玩家】：谁用了什么指令（含参数）。
-- 控制台调用（无 player_index）不公告。
local function announce_command(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then return end
    local what = '/' .. command.name
    if command.parameter then what = what .. ' ' .. command.parameter end
    game.print({'wn.cmd-used', player.name, what})
end

-- 用本函数代替 commands.add_command 注册：执行前先公告一条"谁用了什么"给全体玩家。
local function add_command(name, help, fn)
    commands.add_command(name, help, function(command)
        announce_command(command)
        fn(command)
    end)
end

-- ── 会员系统 ───────────────────────────────────────────────────────────────
-- 会员名单存 storage.members[玩家名]=true。管理员永远算会员（用来发展第一批会员）。
local function is_member(player)
    storage.members = storage.members or {}
    if not player then return false end
    if player.admin then return true end
    return storage.members[player.name] or false
end

-- 取参数里的第一个玩家名。
local function arg_name(command)
    return command.parameter and string.match(command.parameter, '%S+')
end

-- 解析参数里的目标玩家；找不到则向 sink 打印 member-no-such 并返回 nil。
-- 会员授予/撤销/踢人三处共用，避免各写一遍取名+查玩家+报错。
local function resolve_target(command, sink)
    local name = arg_name(command)
    local target = name and game.get_player(name)
    if not target then sink.print({'wn.member-no-such', name or ''}); return end
    return target
end

-- 会员命令通用入口：校验执行者是会员 + 解析目标玩家。
--   返回 actor(控制台为 nil), target, sink(打印对象)；执行者非会员或目标不存在则返回 nil。
local function member_cmd_targets(command)
    local actor = command.player_index and game.get_player(command.player_index)
    local sink = actor or game
    if actor and not is_member(actor) then actor.print({'wn.not-member'}); return end
    local target = resolve_target(command, sink)
    if not target then return end
    return actor, target, sink
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

-- /gen（/shengcheng 同功能）：管理员查看各星球【最近一次世界生成】缓存的 debug 摘要。
-- 故意用【原始】commands.add_command 注册（不走 add_command 的公告包装）→ 查看【不告知其他玩家】，
-- 结果只打给调用的管理员。摘要在 surface.lua 生成时始终缓存进 storage.gen_debug，与 storage.debug 无关。
local GEN_DEBUG_PLANETS = {'nauvis', 'vulcanus', 'fulgora', 'gleba', 'aquilo'}
local function gen_debug_cmd(command)
    local player = command.player_index and game.get_player(command.player_index)
    if player and not player.admin then player.print(constants.not_admin_text); return end
    local sink = player or game
    sink.print({'wn.gen-debug-header', storage.run or 0})
    local any = false
    for _, name in ipairs(GEN_DEBUG_PLANETS) do
        local line = storage.gen_debug and storage.gen_debug[name]
        if line then any = true; sink.print(line) end
    end
    if not any then sink.print({'wn.gen-debug-none'}) end
end
commands.add_command('gen', {'wn.gen-debug-help'}, gen_debug_cmd)
commands.add_command('shengcheng', {'wn.gen-debug-help'}, gen_debug_cmd)

-- 显示距下次自动跃迁的剩余时间。主名 /countdown，/life 作旧别名保留。
local function countdown_cmd(command)
    local player = command.player_index and game.get_player(command.player_index)
    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local total_ticks = (storage.warp_hours or 1) * constants.hour_to_tick
    local rh, rm = util.hm(total_ticks - last_run_ticks)   -- 剩余
    local th, tm = util.hm(total_ticks)                    -- 本轮共
    local msg = {'wn.life-status', rh, rm, th, tm}
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

-- （/settle、/jiesuan 已移除：只有【自动跃迁】才结算科技瓶经验，不再支持提前手动结算。）

-- /suicide（/zisha 同功能）：自杀脱困。死后按权重随机在某个星球复活（见 players.lua）。
local function suicide_cmd(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player or not player.character then return end
    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local life = (storage.warp_hours or 1) * constants.hour_to_tick - last_run_ticks
    players.kill_on_nauvis(player)
    local h, m = util.hm(life)
    game.print({'wn.suicide-notice', player.name, h, m})
end

add_command('suicide', {'wn.suicide-help'}, suicide_cmd)
add_command('zisha', {'wn.suicide-help'}, suicide_cmd)

-- /member <玩家名>（/huiyuan 同功能）：授予会员资格。仅会员/管理员可用。
local function member_grant_cmd(command)
    local _, target, sink = member_cmd_targets(command)
    if not target then return end
    if is_member(target) then sink.print({'wn.member-already', target.name}); return end
    storage.members[target.name] = true
    game.print({'wn.member-granted', target.name})
end

add_command('member', {'wn.member-help'}, member_grant_cmd)
add_command('huiyuan', {'wn.member-help'}, member_grant_cmd)

-- /unmember <玩家名>（/chehuiyuan 同功能）：撤销会员资格。【仅管理员】，可撤销任何会员。
local function member_revoke_cmd(command)
    local actor = command.player_index and game.get_player(command.player_index)
    if actor and not actor.admin then actor.print(constants.not_admin_text); return end   -- 仅管理员可撤销
    local sink = actor or game
    local target = resolve_target(command, sink)
    if not target then return end
    storage.members = storage.members or {}
    if not storage.members[target.name] then sink.print({'wn.member-not', target.name}); return end
    storage.members[target.name] = nil
    game.print({'wn.member-revoked', target.name})
end

add_command('unmember', {'wn.unmember-help'}, member_revoke_cmd)
add_command('chehuiyuan', {'wn.unmember-help'}, member_revoke_cmd)

-- /kickout <玩家名>（/tichu 同功能）：踢出一名【非会员】玩家。仅会员/管理员可用。不能踢自己/会员/管理员。
local function member_kick_cmd(command)
    local actor, target, sink = member_cmd_targets(command)
    if not target then return end
    if actor and target.index == actor.index then sink.print({'wn.kickout-self'}); return end
    if is_member(target) then sink.print({'wn.kickout-protected', target.name}); return end
    if not target.connected then sink.print({'wn.kickout-offline', target.name}); return end
    local by = actor and actor.name or '<console>'
    game.kick_player(target, {'wn.kickout-reason', by})
    game.print({'wn.member-kicked', target.name, by})
end

add_command('kickout', {'wn.kickout-help'}, member_kick_cmd)
add_command('tichu', {'wn.kickout-help'}, member_kick_cmd)
