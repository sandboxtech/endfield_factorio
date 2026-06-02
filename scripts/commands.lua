-- 命令注册：管理/调试用。
-- 玩家从控制台调用时 player_index 为 nil，此时视作管理员。
local constants = require('scripts.constants')
local gui = require('scripts.gui')
local reset = require('scripts.reset')
local players = require('scripts.players')
local science_exp = require('scripts.science_exp')
local passives = require('scripts.passives')
local respawn_gifts = require('scripts.respawn_gifts')
local classes = require('scripts.classes')
local map_features = require('scripts.map_features')
local market = require('scripts.market')
local util = require('scripts.util')

local M = {}   -- 导出给 HUD 按钮复用（gui 点击经 tick 路由到这里）

-- （require_admin 已随 /exp_clear 一并移除：现有管理操作改用 player.admin 内联校验。）

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

-- ── 管理员功能：改由【HUD 左上角红按钮】触发（仅管理员可见可点），不再注册为命令。───────────────
-- 按钮点击经 tick.on_gui_click 路由到这些 M.* 函数；函数内再校验 player.admin 兜底。

-- 查看各星球【最近一次世界生成】的 debug 摘要（surface.lua 每轮缓存进 storage.gen_debug 的多行数组）。
local GEN_DEBUG_PLANETS = {'nauvis', 'vulcanus', 'fulgora', 'gleba', 'aquilo'}
function M.admin_gen(player)
    if not (player and player.admin) then return end
    local lines = {}
    for _, name in ipairs(GEN_DEBUG_PLANETS) do
        local entry = storage.gen_debug and storage.gen_debug[name]
        if type(entry) == 'table' then for _, l in ipairs(entry) do lines[#lines + 1] = l end end
    end
    if #lines == 0 then lines[1] = {'wn.gen-debug-none'} end
    gui.show_popup(player, {'wn.gen-debug-header', storage.run or 0}, lines)
end

-- （/fixstats、/xiufutongji 已移除：玩家统计字段补齐改为对线上老档跑一次性 /c 脚本，代码里不再常驻。）

-- （/countdown、/daojishi、/life 已移除：顶部 HUD 常驻显示跃迁倒计时，无需再用命令查询。）

-- （玩家加入时由 players.lua 的 on_player_joined_game → gui.show_intro 弹场景简介。）

-- （/inspect /查看 指令已移除：顶部"角色面板"按钮(科技瓶经验) + "查看他人能力"列表等价；
--   个人能力/统计在【状态】按钮窗口。print_exp / print_status 由 M.show_panel / M.show_stats 调用。）

-- （/exp_clear 已移除：清空所有人瓶子经验改用控制台 /c storage.exp = {}。）

-- 全部迁移/默认补齐的【单一入口】：标量与必需表(constants.ensure_defaults) + 职业表(classes.ensure) + 战利品权重(map_features.ensure_loot)。
-- on_init / on_configuration_changed / /config 红按钮 / /ensureall 命令统一走它 → 三个 ensure 不再各处散调、不会漏跑。三者各自幂等。
function M.ensure_all()
    constants.ensure_defaults()
    classes.ensure()
    map_features.ensure_loot()
    market.ensure_prices()
end

-- 手动跑全部 ensure（控制台或管理员）：补齐新增默认、迁移老存档、修类型。控制台调用(player_index 为 nil)视作管理员。
add_command('ensureall', '补齐全部默认/迁移：标量+必需表+职业表+战利品权重', function(command)
    local player = command.player_index and game.get_player(command.player_index)
    if player and not player.admin then player.print(constants.not_admin_text); return end
    M.ensure_all()
    ;(player or game).print('ensure_all 已执行：默认值/必需表/职业表/战利品权重均已补齐。')
end)

-- 参数 diff（合并了原 /ensuredefaults + /config）：先跑一次 M.ensure_all（补默认/必需表/职业表/战利品权重 + 清废弃键/修类型，
-- 迁移），再弹窗对比【当前 storage】与【默认值】、改过的高亮。仅标量常量(constants.scalar_defaults)；
-- 表型(travel_chance/event_types…)不在此列。只弹给本人、不公告。
function M.admin_diff(player)
    if not (player and player.admin) then return end
    M.ensure_all()
    local defs = constants.scalar_defaults or {}
    local keys = {}
    for k in pairs(defs) do keys[#keys + 1] = k end
    table.sort(keys)
    local lines, changed = {}, 0
    for _, k in ipairs(keys) do
        local cur, def = storage[k], defs[k]
        if cur == def then
            lines[#lines + 1] = k .. ' = ' .. tostring(cur)
        else
            changed = changed + 1
            lines[#lines + 1] = '[color=acid]' .. k .. ' = ' .. tostring(cur) .. '[/color]（默认 ' .. tostring(def) .. '）'
        end
    end
    table.insert(lines, 1, '已跑 ensure_all；已改 [color=acid]' .. changed .. '[/color] 项（高亮），共 ' .. #keys .. ' 项：')
    gui.show_popup(player, '参数：当前值 vs 默认值', lines)
end

-- （/tutorial /教程 指令已移除：顶部"玩法"按钮等价。gui.show_tutorial 仍由该按钮调用。）

-- 以下原"控制台指令"(预览/排行/自杀/前往星球)已【改为教程弹窗里的按钮】，指令注册移除；
-- 核心逻辑抽成 M.* 供按钮点击调用（tick.on_gui_click → 这里）。

-- 预览：若现在立即跃迁，背包里的科技瓶各能换多少经验。
function M.show_preview(player)
    if not player then return end
    local gain = science_exp.preview(player)   -- 各瓶预计可得经验（瓶数×品质）
    local lines = {}
    for _, pack in ipairs(constants.science_packs) do
        if (gain[pack] or 0) > 0 then
            lines[#lines + 1] = {'wn.preview-entry', pack, string.format('%g', gain[pack])}
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

-- ── 动作冷却（按【桶】区分，每玩家独立计时）──────────────────────────────────────
-- 前往星球(travel_cd)、投票跃迁/停留(vote_cd)、转账星星(action_cd) 各用一条【独立】冷却，互不挤占。
-- 时长统一读 storage.action_cd_minutes（默认 3 分钟，可 /c 热改）。
-- 时间戳按玩家名存 storage[桶][名]=tick；只有【成功执行】才计时，被拒（无角色/背包没清空等）不占冷却。
local function on_cooldown(player, bucket, msg_key)
    storage[bucket] = storage[bucket] or {}
    local last = storage[bucket][player.name]
    local cd = (storage.action_cd_minutes or 3) * constants.min_to_tick
    if last and game.tick - last < cd then
        player.print({msg_key or 'wn.action-cd', math.ceil((cd - (game.tick - last)) / 60)})
        return true
    end
    return false
end
local function mark_action(player, bucket)
    storage[bucket] = storage[bucket] or {}
    storage[bucket][player.name] = game.tick
end

-- ── 前往星球 ─────────────────────────────────────────────────────────────────
-- /nauvis /vulcanus /gleba /fulgora /aquilo：把自己直接传送到对应星球出生点（每次跃迁已自动解锁所有星球）。
-- 要求【鼠标 / 背包 / 物流(回收) / 弹药】四个区都为空，不为空则拒绝，防止跨星球夹带物资（不主动清空，避免误删）。
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
    if not storage.travel_enabled then return end   -- 总开关关闭时禁用（即便按钮意外存在也不生效）
    local gmet, _, gcur, greq = classes.planet_gate(player, planet)   -- 星球瓶门槛（服务端校验，防绕过灰按钮）
    if not gmet then player.print({'wn.planet-locked-msg', planet, greq, gcur}); return end
    if not (storage.travel_open and storage.travel_open[planet]) then
        player.print({'wn.travel-fail-closed', planet, math.floor(((storage.travel_chance or {})[planet] or 0.5) * 100)})
        return
    end
    if not player.character then player.print({'wn.travel-no-char'}); return end
    if not game.surfaces[planet] then player.print({'wn.travel-not-generated', planet}); return end
    if not travel_inventories_empty(player) then
        player.print({'wn.travel-clear-first'})
        return
    end
    if on_cooldown(player, 'travel_cd', 'wn.cd-travel') then return end   -- 前往星球独立冷却；校验全过后才查，被拒不占冷却
    players.place_on_surface(player, planet)
    storage.respawn_surface = storage.respawn_surface or {}   -- 老存档兜底：ensure_defaults 没补到也不崩
    storage.respawn_surface[player.name] = planet   -- 前往后，该星球成为默认复活星球
    mark_action(player, 'travel_cd')
    game.print({'wn.travel-notice', player.name, planet})
end

-- （/settle、/jiesuan 已移除：只有【自动跃迁】才结算科技瓶经验，不再支持提前手动结算。）

-- 自杀脱困：死后在当前星球留尸、回复活星球(默认母星)复活（见 players.lua kill_player）。
function M.do_suicide(player)
    if not player or not player.character then return end
    players.kill_player(player)
end

-- ── 跃迁投票 ───────────────────────────────────────────────────────────────
-- 不建 GUI，纯命令投票"本世界是否提前跃迁"：/yueqian(=/warp) 同意、/tingliu 反对。不投票=忽视。
-- 票存 storage.warp_vote[玩家名]='agree'|'oppose'（再投覆盖；跃迁 reset 时清空）。
-- 结算（每次投票后）：净同意 = 同意人数 - 反对人数（每个反对抵消 1 个同意）；阈值 = ceil(在线人数 / warp_vote_divisor[默认5])。
-- 【可取消提前】票持续生效，不在通过后清空：
--   · 净同意 ≥ 阈值且当前未施加 → 把倒计时【直接设为剩余 warp_vote_target_minutes 分钟(默认5)】，
--     并把被砍掉的小时数记入 storage.warp_vote_delta（仅当当前剩余【多于】目标才砍，否则反而延长 → 不动）。
--   · 净同意 < 阈值且此前施加过 → 把 warp_vote_delta 加回 warp_hours（取消提前、恢复倒计时），清除 delta；需再投票才能再推。
--   delta 与期间研究/敌人死亡对 warp_hours 的增减解耦（记的是"投票净缩减量"），reset 时随 warp_vote 一并清空。不杀任何玩家。
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
        if storage.warp_vote_delta == nil then   -- 尚未施加才施加（避免二次缩减）
            local last = game.tick - (storage.run_start_tick or game.tick)
            local remain = (storage.warp_hours or 1) * constants.hour_to_tick - last
            local target = (storage.warp_vote_target_minutes or 5) * constants.min_to_tick   -- 目标剩余分钟（可 /c 热改）
            if remain > target then
                -- 倒计时改成剩余 target：warp_hours 反解使 (warp_hours*小时 - 已用) = target。记录被砍掉的小时数以便撤销。
                local new_hours = (last + target) / constants.hour_to_tick
                storage.warp_vote_delta = (storage.warp_hours or 1) - new_hours
                storage.warp_hours = new_hours
                game.print({'wn.warp-vote-pass', target / constants.min_to_tick})
                gui.refresh_countdown()
            end
        end
    -- 安全不变量：取消只把 delta(本次砍掉的量)原样加回 → warp_hours 至多回到自然值，绝不超过。
    -- 故投票【只能缩短或还原到自然倒计时，永远无法延长/阻止跃迁】。改这段务必保持"加回的 ≤ 砍掉的"。
    elseif storage.warp_vote_delta ~= nil then   -- 跌破阈值且此前施加过 → 把缩减的时间加回去（取消提前）
        storage.warp_hours = (storage.warp_hours or 1) + storage.warp_vote_delta
        storage.warp_vote_delta = nil
        local last = game.tick - (storage.run_start_tick or game.tick)
        local remain = (storage.warp_hours or 1) * constants.hour_to_tick - last
        game.print({'wn.warp-vote-cancel', math.max(0, math.floor(remain / constants.min_to_tick))})
        gui.refresh_countdown()
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
-- 所有命令统一【只用英文名】，不再注册中文/拼音别名。

-- ── 供 HUD 按钮调用（gui 点击经 tick.on_gui_click 路由到这里）──────────────────
-- （show_panel / show_player_list 已删：瓶子经验已合并进【在线玩家】数据页，不再单独成窗。）

-- 弹出【统计】窗口（HUD 独立按钮）：列出所有在线玩家（名字 + 等级 + 职业），点某人看其详细统计。
function M.show_stats(player)
    if not player then return end
    if #game.connected_players <= 1 then return M.show_stats_of(player, player) end   -- 只有自己在线：跳过列表，直接看自己的面板
    local buttons = {
        {name = 'wn_stats_view_self', caption = {'wn.stats-view-self'}, tags = {wn_stats_view = player.name}},  -- 最上方：查看自己（name 固定唯一，避免与列表里自己那项重名崩溃；路由靠 tags）
        {newrow = true},   -- 分隔线：自己 / 其他在线玩家
    }
    for _, p in pairs(game.connected_players) do
        local lv = respawn_gifts.coin_reward(passives.get_stat(p.index, 'online_minutes'))
        local stars = math.floor(((storage.star or {})[p.name] or 0) / constants.min_to_tick)
        local planet = players.respawn_surface_name(p)   -- 出生星球（space-location 图标名）
        local def = classes.def_of(p)
        -- 职业名三层兜底：locale 词条 → storage.class_names 热改 → def.name 中文默认。
        local cname = def and classes.text_loc('wn.class-name-' .. def.key, (storage.class_names or {})[def.key], def.name or def.key) or ''
        buttons[#buttons + 1] = {name = 'wn_stats_view_' .. p.index,   -- 名称 语言 星球 职业 等级 星星
            caption = {'wn.stats-entry', p.name, p.locale, planet, cname, lv, stars}, tags = {wn_stats_view = p.name}}
    end
    gui.show_popup(player, {'wn.stats-title'}, {}, buttons)
end

-- 看某玩家的详细统计（顶部说明 + 人物等级 + 三能力 + 6 项战绩）；底部【返回】回到玩家列表。
function M.show_stats_of(player, target)
    if not (player and target) then return end
    local sink = gui.popup_sink()
    sink.lines[#sink.lines + 1] = {'wn.stats-help'}
    sink.lines[#sink.lines + 1] = ''
    players.print_status(target, sink)
    -- 多人时给【返回】回玩家列表；只有自己在线（无列表可返回）则不加，靠标题栏关闭。
    local btns = (#game.connected_players > 1) and {{name = 'wn_btn_stats', caption = {'wn.panel-back'}}} or {}
    gui.show_popup(player, {'wn.stats-of-header', target.name}, sink.lines, btns)
end

-- 弹出【星星】窗口（HUD 独立按钮）：星星余额（所有等级都显示）+ 充能进度条 + 领取按钮（仅达 star_unlock_level）。
-- 原先嵌在角色面板里，现单独成窗。领取走 wn_claim_star（tick 路由 → M.claim_charge）。
function M.show_star(player)
    if not player then return end
    local lines = {{'wn.star-help'}, ''}                            -- 顶部自带说明 + 空行
    local bal = math.floor(((storage.star or {})[player.name] or 0) / constants.min_to_tick)
    lines[#lines + 1] = {'wn.panel-star', bal}                      -- 星星余额（整数）
    local bottom_buttons = {}
    if M.star_unlocked(player) then
        local pend = M.charge_pending(player)
        local maxt = (storage.charge_max_hours or 30) * constants.hour_to_tick
        local frac = (maxt > 0) and (pend / maxt) or 0
        lines[#lines + 1] = {'wn.panel-star-charge',
            players.progress_bar(frac),
            math.floor(pend / constants.min_to_tick),                         -- 当前可领整数星星
            math.floor(maxt / constants.min_to_tick)}                         -- 能领的最大值（=满充星星数）
        if pend >= constants.min_to_tick then   -- 攒够至少 1 颗(3600 tick)才显示领取按钮，不足 1 颗只显示进度条
            bottom_buttons[#bottom_buttons + 1] = {name = 'wn_claim_star', caption = {'wn.act-claim-star'}}
        end
    end
    gui.show_popup(player, {'wn.star-title'}, lines, nil, false, bottom_buttons)
end


-- 设定【出生星球】：下次跃迁复活 + 领起手装备的星球（即 storage.respawn_surface[玩家名]）。
-- 纯个人设置——不传送、不广播、不占冷却；任何星球可选（不受前往 30% 限制）。点完刷新教程弹窗让 ✓ 跟着动。
function M.set_home_planet(player, planet)
    if not player then return end
    local gmet, _, gcur, greq = classes.planet_gate(player, planet)   -- 出生星球同样需瓶门槛（服务端校验）
    if not gmet then player.print({'wn.planet-locked-msg', planet, greq, gcur}); return end
    storage.respawn_surface = storage.respawn_surface or {}
    storage.respawn_surface[player.name] = planet
    player.print({'wn.home-set', planet})
    gui.show_actions(player)   -- 重开功能弹窗 → 当前出生星球按钮标 ✓
end

-- 选择职业（HUD 独立按钮窗口）：改 storage.player_class[名] + 全服公告切换；不传送（下次开局生效）。
-- 同时只能一种职业；未解锁的职业不可选（按钮已置灰，这里兜底）。带短冷却防刷消息/防刷屏。
function M.set_class(player, key)
    local def = classes.def_for_key(key)
    if not (player and def) then return end
    if not classes.unlocked(player, def) then   -- 兜底：按钮置灰已拦截，命令/异常仍校验
        player.print({'wn.class-locked-msg', classes.text_loc('wn.class-name-' .. key, (storage.class_names or {})[key], def.name or key)})
        return
    end
    storage.class_cd = storage.class_cd or {}
    local last = storage.class_cd[player.name]
    local cd = (storage.class_cd_minutes or 0.5) * constants.min_to_tick
    if last and game.tick - last < cd then
        player.print({'wn.action-cd', math.ceil((cd - (game.tick - last)) / 60)})
        return
    end
    classes.set(player, key)
    storage.class_cd[player.name] = game.tick
    game.print({'wn.class-changed', player.name, classes.text_loc('wn.class-name-' .. key, (storage.class_names or {})[key], def.name or key)})   -- 全服公告切换
    gui.show_classes(player)   -- 重开职业弹窗 → 当前职业按钮标 ✓
end

-- ⭐ 星星充能（懒计算）：storage.charge[名]=上次结算到的 game.tick；storage.star[名]=星星余额(内部存 tick，恒为 min_to_tick 整数倍)。
-- 单位：1 星星 = 1 分钟 = min_to_tick(3600) tick。显示一律 floor(值/min_to_tick) → 整数星星。
-- 领取：只能领【整数颗】星星——N = floor(待领 tick / min_to_tick)（待领封顶 charge_max_hours 小时），余额 += N×min_to_tick，
--       记录前移 last += N×min_to_tick（保留不足 1 颗的余数，下次接着攒，不浪费、不漂移）。
local STAR = nil   -- = constants.min_to_tick，下方惰性取（避免顶层依赖顺序问题）
local function star_tick() STAR = STAR or constants.min_to_tick; return STAR end

-- 人物等级 = floor(√在线分钟)（= 开局金币 coin_reward）。
local function player_level(player)
    return respawn_gifts.coin_reward(passives.get_stat(player.index, 'online_minutes'))
end
-- 是否已解锁充能进度条 + 领取按钮（达到 star_unlock_level，默认 0=人人解锁）。
function M.star_unlocked(player)
    return player and player_level(player) >= (storage.star_unlock_level or 0)
end

function M.charge_pending(player)   -- 返回 待领 tick（封顶 charge_max_hours 小时）
    local maxt = (storage.charge_max_hours or 30) * constants.hour_to_tick
    local last = (storage.charge or {})[player.name] or game.tick
    return math.min(game.tick - last, maxt)
end
function M.claim_charge(player)
    if not player then return end
    if not M.star_unlocked(player) then return end   -- 等级不够：按钮本不该出现，这里兜底拦截
    storage.charge, storage.star = storage.charge or {}, storage.star or {}
    local unit = star_tick()
    local last = storage.charge[player.name] or game.tick
    local maxt = (storage.charge_max_hours or 30) * constants.hour_to_tick
    local pend = math.min(game.tick - last, maxt)
    local n = math.floor(pend / unit)                  -- 整数星星数（只领整颗）
    if n <= 0 then player.print({'wn.star-none-yet'}); return end
    storage.star[player.name] = (storage.star[player.name] or 0) + n * unit
    -- 记录前移：基准取 max(老记录, 当前-封顶)，再加 N 颗的量。
    -- 溢出（离线超 charge_max_hours）时把基准抬到 game.tick-maxt，避免领完后剩余仍 > 封顶、可立刻反复领（封顶失效）。
    -- 非溢出时 last >= game.tick-maxt，等价于 last + n*unit，照常保留不足 1 颗的余数。
    storage.charge[player.name] = math.max(last, game.tick - maxt) + n * unit
    game.print({'wn.star-claimed', player.name, n})
    M.show_star(player)   -- 刷新星星窗口（充能减少、余额更新）
end
-- 把 stars 颗（整数）星星转给目标玩家（余额不足则转全部整颗）。内部按 颗×min_to_tick 存。
-- 转账有【自己一条独立冷却 action_cd】：校验全过（目标存在/非自己/数额有效/余额足）后才查冷却，被拒不占冷却；成功才 mark_action。
function M.give_star(player, target_name, stars)
    if not player then return end
    storage.star = storage.star or {}
    local target = target_name and game.get_player(target_name)
    if not target then player.print({'wn.member-no-such', target_name or ''}); return end
    if target.index == player.index then player.print({'wn.star-self'}); return end
    local unit = star_tick()
    local n = math.floor(tonumber(stars) or 0)         -- 只转整数颗
    if n <= 0 then player.print({'wn.star-bad-amount'}); return end
    local have = math.floor((storage.star[player.name] or 0) / unit)   -- 余额有多少整颗
    if have <= 0 then player.print({'wn.star-insufficient'}); return end
    n = math.min(n, have)                              -- 余额不足则转全部整颗
    if on_cooldown(player, 'action_cd', 'wn.cd-star') then return end   -- 转账独立冷却；校验全过后才查，被拒不占冷却
    storage.star[player.name] = (storage.star[player.name] or 0) - n * unit
    storage.star[target.name] = (storage.star[target.name] or 0) + n * unit
    mark_action(player, 'action_cd')   -- 转账独立冷却
    game.print({'wn.star-given', player.name, n, target.name})
end
-- /givestar <玩家> <星星>：转星星给他人（用原始注册、不走公告包装；give_star 自身已全服广播）。
commands.add_command('givestar', '把星星转给其他玩家：/givestar <玩家> <星星>', function(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then return end
    local name, n = string.match(command.parameter or '', '^%s*(%S+)%s+(%S+)')
    M.give_star(player, name, tonumber(n))
end)

-- 投跃迁票（vote='agree'/'oppose'，等同 /跃迁 /停留）并结算广播。
function M.cast_warp_vote(player, vote)
    if not player then return end
    if on_cooldown(player, 'vote_cd', 'wn.cd-vote') then return end   -- 投票跃迁/停留独立冷却
    storage.warp_vote = storage.warp_vote or {}
    storage.warp_vote[player.name] = vote
    mark_action(player, 'vote_cd')
    game.print({vote == 'agree' and 'wn.warp-vote-cast-agree' or 'wn.warp-vote-cast-oppose', player.name})
    warp_vote_eval()
end

return M
