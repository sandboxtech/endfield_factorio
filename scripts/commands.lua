-- 命令注册：管理/调试用。
-- 玩家从控制台调用时 player_index 为 nil，此时视作管理员。
local constants = require('scripts.constants')
local gui = require('scripts.gui')
local reset = require('scripts.reset')
local players = require('scripts.players')
local science_exp = require('scripts.science_exp')
local util = require('scripts.util')

local M = {}   -- 导出给 HUD 按钮复用（gui 点击经 tick 路由到这里）

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
-- 故意用【原始】commands.add_command 注册（不走 add_command 的公告包装）→ 查看【不告知其他玩家】。
-- 输出【只走 GUI 弹窗】(gui.show_popup，每行可换行、可关闭，同 /inspect /preview)；控制台(无玩家)不打印。
-- 摘要在 surface.lua 生成时始终缓存进 storage.gen_debug（每星球一个【多行数组】），与 storage.debug 无关。
local GEN_DEBUG_PLANETS = {'nauvis', 'vulcanus', 'fulgora', 'gleba', 'aquilo'}
local function gen_debug_cmd(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then return end          -- 只弹窗给玩家，控制台不打印
    if not player.admin then player.print(constants.not_admin_text); return end
    -- 各星球缓存的多行数组直接逐行铺开（每个变体已各占一行）。
    local lines = {}
    for _, name in ipairs(GEN_DEBUG_PLANETS) do
        local entry = storage.gen_debug and storage.gen_debug[name]
        if type(entry) == 'table' then   -- 多行数组（旧单行字符串格式已对线上老档用一次性 /c 统一）
            for _, l in ipairs(entry) do lines[#lines + 1] = l end
        end
    end
    if #lines == 0 then lines[1] = {'wn.gen-debug-none'} end
    gui.show_popup(player, {'wn.gen-debug-header', storage.run or 0}, lines)
end
commands.add_command('gen', {'wn.gen-debug-help'}, gen_debug_cmd)
commands.add_command('shengcheng', {'wn.gen-debug-help'}, gen_debug_cmd)

-- （/fixstats、/xiufutongji 已移除：玩家统计字段补齐改为对线上老档跑一次性 /c 脚本，代码里不再常驻。）

-- （/countdown、/daojishi、/life 已移除：顶部 HUD 常驻显示跃迁倒计时，无需再用命令查询。）

-- （/exp 已删除：与 /inspect（无参数=看自己）重复。print_science_exp 仍由玩家加入时的广播使用。）

-- （/inspect /chakan /查看 指令已移除：顶部"角色面板"按钮 + "查看他人能力"列表等价。
--   print_inspection 仍由 M.show_panel（按钮）调用。）

add_command('exp_clear', {'wn.exp-clear-help'}, function(command)
    if not require_admin(command) then return end
    storage.science_exp = {}
    game.print({'wn.exp-cleared'})
end)

-- （/tutorial /教程 指令已移除：顶部"玩法"按钮等价。gui.show_tutorial 仍由该按钮调用。）

-- 以下原"控制台指令"(预览/排行/自杀/前往星球)已【改为教程弹窗里的按钮】，指令注册移除；
-- 核心逻辑抽成 M.* 供按钮点击调用（tick.on_gui_click → 这里）。

-- 预览：若现在立即跃迁，背包里的科技瓶各能换多少经验。
function M.show_preview(player)
    if not player then return end
    local gain = science_exp.preview(player)
    local lines = {}
    for _, pack in ipairs(constants.science_packs) do
        if (gain[pack] or 0) > 0 then
            lines[#lines + 1] = {'wn.preview-entry', pack, gain[pack]}
        end
    end
    if #lines == 0 then lines[1] = {'wn.preview-none'} end
    gui.show_popup(player, {'wn.preview-header'}, lines)
end

-- /lastrank（/paihang 同功能，中文别名 /排行）：查看【上一个世界】每人带走的科技瓶经验排行榜。
-- 数据在跃迁时由 reset.lua 存进 storage.last_leaderboard（只保留上一个世界这一份，每次跃迁覆盖）。
function M.show_lastrank(player)
    if not player then return end
    local lines = {}
    for _, s in ipairs(storage.last_leaderboard or {}) do
        lines[#lines + 1] = {'wn.summary-player', s.name, s.total, s.detail}
    end
    if #lines == 0 then lines[1] = {'wn.lastrank-none'} end
    gui.show_popup(player, {'wn.lastrank-header', storage.last_leaderboard_run or 0}, lines)
end

-- ── 前往星球 ─────────────────────────────────────────────────────────────────
-- /nauvis /vulcanus /gleba /fulgora /aquilo：把自己直接传送到对应星球出生点（每次跃迁已自动解锁所有星球）。
-- 要求【鼠标 / 背包 / 物流(回收) / 弹药】四个区都为空——不为空则拒绝，防止跨星球夹带物资（不主动清空，避免误删）。
local function travel_inventories_empty(player)
    local cur = player.cursor_stack
    if cur and cur.valid_for_read then return false end
    for _, inv in ipairs({defines.inventory.character_main,
                          defines.inventory.character_trash,
                          defines.inventory.character_ammo}) do
        local i = player.get_inventory(inv)
        if i and not i.is_empty() then return false end
    end
    return true
end

function M.travel(player, planet)
    if not player then return end
    if not storage.travel_enabled then return end   -- 开关关闭时禁用（即便按钮意外存在也不生效）
    if not player.character then player.print('你现在没有角色，无法前往星球'); return end
    if not game.surfaces[planet] then player.print('星球 ' .. planet .. ' 还没生成'); return end
    if not travel_inventories_empty(player) then
        player.print('前往星球前，请先清空：鼠标、背包、物流(回收)、弹药 这四个区')
        return
    end
    players.place_on_surface(player, planet)
    storage.respawn_surface[player.name] = planet   -- 前往后，该星球成为默认复活星球
end

-- （/settle、/jiesuan 已移除：只有【自动跃迁】才结算科技瓶经验，不再支持提前手动结算。）

-- 自杀脱困：死后在当前星球留尸、回复活星球(默认母星)复活（见 players.lua kill_player）。
function M.do_suicide(player)
    if not player or not player.character then return end
    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local life = (storage.warp_hours or 1) * constants.hour_to_tick - last_run_ticks
    players.kill_player(player)
    local h, m = util.hm(life)
    game.print({'wn.suicide-notice', player.name, h, m})
end

-- ── 跃迁投票 ───────────────────────────────────────────────────────────────
-- 不建 GUI，纯命令投票"本世界是否提前跃迁"：/yueqian(=/warp) 同意、/tingliu 反对。不投票=忽视。
-- 票存 storage.warp_vote[玩家名]='agree'|'oppose'（再投覆盖；跃迁 reset 时清空）。
-- 结算（每次投票后）：净同意 = 同意人数 - 反对人数（每个反对抵消 1 个同意）；
--   净同意 > ceil(在线人数 / storage.warp_vote_divisor[默认5]) → 把本世界倒计时【直接设为剩余 storage.warp_vote_target_minutes 分钟(默认5)】，
--   不杀任何玩家，并【清空所有票】（需重新投票才能再推一次）。仅当当前剩余【多于】目标分钟才生效（否则会反而延长倒计时）。
local function warp_vote_eval()
    storage.warp_vote = storage.warp_vote or {}
    local agree, oppose = 0, 0
    for _, v in pairs(storage.warp_vote) do
        if v == 'agree' then agree = agree + 1 elseif v == 'oppose' then oppose = oppose + 1 end
    end
    local n = #game.connected_players
    local threshold = math.ceil(n / (storage.warp_vote_divisor or 5))   -- 默认 1/5，可 /c storage.warp_vote_divisor 热改
    local net = agree - oppose
    game.print({'wn.warp-vote-status', agree, oppose, net, threshold})
    if net >= threshold then   -- 达到阈值即过（含单人/少数人：threshold 最低为 1，1 净同意即可）
        local last = game.tick - (storage.run_start_tick or game.tick)
        local remain = (storage.warp_hours or 1) * constants.hour_to_tick - last
        local target = (storage.warp_vote_target_minutes or 5) * constants.min_to_tick   -- 目标剩余分钟（可 /c 热改）
        if remain > target then
            -- 直接把倒计时改成剩余 target：warp_hours 反解使 (warp_hours*小时 - 已用) = target。不杀玩家。
            storage.warp_hours = (last + target) / constants.hour_to_tick
            game.print({'wn.warp-vote-pass', target / constants.min_to_tick})
            gui.refresh_countdown()
        end
        storage.warp_vote = {}   -- 推进后清空，需重新投票才能再推
    end
end

-- （/warp /yueqian /跃迁 /tingliu /停留 投票指令已移除：顶部 ✓跃迁 / ✗停留 按钮等价，经 M.cast_warp_vote 投票。）

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
    -- 注意：kick_player 的 reason 只接受【纯字符串】，传 localised string(table) 会崩。
    game.kick_player(target, '被会员 ' .. by .. ' 踢出')
    game.print({'wn.member-kicked', target.name, by})
end

add_command('kickout', {'wn.kickout-help'}, member_kick_cmd)
add_command('tichu', {'wn.kickout-help'}, member_kick_cmd)

-- ── 中文命令名（与拼音/英文同功能）────────────────────────────────────────────
-- 命令名是 UTF-8 字符串，中文可注册；玩家需用输入法在控制台敲中文。
-- 用 pcall 兜底：万一某版本/环境不接受中文命令名，只是中文别名不生效，不影响其余命令与场景加载。
local function zh_alias(name, help, fn) pcall(add_command, name, help, fn) end
zh_alias('给会员', {'wn.member-help'}, member_grant_cmd)
zh_alias('撤会员', {'wn.unmember-help'}, member_revoke_cmd)
zh_alias('踢出', {'wn.kickout-help'}, member_kick_cmd)

-- ── 供 HUD 按钮调用（gui 点击经 tick.on_gui_click 路由到这里）──────────────────
-- 弹出角色面板：target 省略=看自己。看自己→底部带"查看他人能力"按钮；看别人→带"返回"按钮（回玩家列表）。
function M.show_panel(player, target)
    if not player then return end
    target = target or player
    local sink = gui.popup_sink()
    players.print_inspection(target, sink)
    local title = table.remove(sink.lines, 1)   -- 首行 inspect-header 提作弹窗标题
    local btn = (target.index == player.index)
        and {name = 'wn_panel_others', caption = {'wn.panel-others'}}   -- 看自己：去看他人
        or  {name = 'wn_panel_others', caption = {'wn.panel-back'}}     -- 看别人：返回玩家列表
    gui.show_popup(player, title, sink.lines, {btn})
end

-- 弹出【在线玩家列表】：每个在线玩家一个名字按钮，点击查看其能力面板。
function M.show_player_list(player)
    if not player then return end
    local buttons, i = {}, 0
    for _, p in pairs(game.connected_players) do
        i = i + 1
        buttons[#buttons + 1] = {name = 'wn_view_player_' .. i, caption = p.name, tags = {wn_view = p.name}}
    end
    gui.show_popup(player, {'wn.panel-list-title'}, {}, buttons)
end

-- 投跃迁票（vote='agree'/'oppose'，等同 /跃迁 /停留）并结算广播。
function M.cast_warp_vote(player, vote)
    if not player then return end
    storage.warp_vote = storage.warp_vote or {}
    storage.warp_vote[player.name] = vote
    warp_vote_eval()
end

return M
