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

-- 命令文本 "/名 参数"（公告/回显共用）。
local function cmd_text(command)
    local what = '/' .. command.name
    if command.parameter then what = what .. ' ' .. command.parameter end
    return what
end

-- 任何自定义指令被使用时，公告给【所有在线玩家】：谁用了什么指令（含参数）。
-- 控制台调用（无 player_index）不公告。
local function announce_command(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then return end
    game.print({'wn.cmd-used', player.name, cmd_text(command)})
end

-- 用本函数代替 commands.add_command 注册：执行前先公告一条"谁用了什么"给全体玩家。
local function add_command(name, help, fn)
    commands.add_command(name, help, function(command)
        announce_command(command)
        fn(command)
    end)
end

-- 【管理员命令】注册器，与 add_command 两点不同：
--   1) 集中校验管理员（控制台调用无 player_index 视作管理员），非管理员拒绝并提示，不进 fn；
--   2) "谁用了什么"只回显给执行者本人，【不】全服公告——管理操作的反馈不刷其他玩家的屏。
local function add_admin_command(name, help, fn)
    commands.add_command(name, help, function(command)
        local player = command.player_index and game.get_player(command.player_index)
        if player and not player.admin then player.print(constants.not_admin_text); return end
        if player then player.print({'wn.cmd-used', player.name, cmd_text(command)}) end
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

add_admin_command('reset', {'wn.run-reset-help'}, function(command)
    if not command.player_index then return end   -- 仍禁止控制台触发（防误触全服跃迁），与原行为一致
    reset.reset()
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
    -- 加宽到 680：资源/气候等单行信息密，380 宽逐行折行很难读
    gui.show_popup(player, {'wn.gen-debug-header', storage.run or 0}, lines, nil, nil, nil, nil, 680)
end

-- （玩家加入时由 players.lua 的 on_player_joined_game → gui.show_intro 弹场景简介。）

-- 全部迁移/默认补齐的【单一入口】：标量与必需表(constants.ensure_defaults) + 职业表(classes.ensure) + 战利品权重(map_features.ensure_loot)。
-- on_init / on_configuration_changed / /config 红按钮 / /ensureall 命令统一走它 → 三个 ensure 不再各处散调、不会漏跑。三者各自幂等。
function M.ensure_all()
    constants.ensure_defaults()
    classes.ensure()
    map_features.ensure_loot()
    market.ensure_prices()
end

-- 手动跑全部 ensure（控制台或管理员）：补齐新增默认、迁移老存档、修类型。管理员校验在 add_admin_command 集中做。
add_admin_command('ensureall', '补齐全部默认/迁移：标量+必需表+职业表+战利品权重', function(command)
    local player = command.player_index and game.get_player(command.player_index)
    M.ensure_all()
    ;(player or game).print('ensure_all 已执行：默认值/必需表/职业表/战利品权重均已补齐。')
end)

-- ── 开局解锁白名单：管理员增删【初始科技 / 初始配方】（addtech/deltech/addrecipe/delrecipe）─────
-- 直接 append / remove 到 storage.unlock_techs / unlock_recipes（reset 每轮据此标记科技已研究、启用配方）。
-- 逐个校验原型是否存在(prototypes.technology / prototypes.recipe)，不存在的【跳过并报错】，不污染清单。
-- 仅管理员（add_admin_command 集中校验，控制台视作管理员）。改动【下次跃迁生效】。
local function edit_unlock(command, kind, add)
    local player = command.player_index and game.get_player(command.player_index)
    local out     = player or game
    local is_tech = (kind == 'tech')
    local key     = is_tech and 'unlock_techs' or 'unlock_recipes'
    local protos  = is_tech and prototypes.technology or prototypes.recipe
    local word    = is_tech and '科技' or '配方'
    local list = storage[key] or {}
    storage[key] = list                         -- 老档兜底：ensure_defaults 没补到也不崩
    if not command.parameter or command.parameter == '' then
        out.print('用法：/' .. command.name .. ' <' .. word .. '名...>（可空格分隔多个）')
        return
    end
    for name in string.gmatch(command.parameter, '%S+') do
        if not protos[name] then
            out.print('找不到' .. word .. '【' .. name .. '】，已跳过')
        else
            local idx
            for i, v in ipairs(list) do if v == name then idx = i; break end end
            if add then
                if idx then out.print(word .. '【' .. name .. '】已在开局清单中')
                else list[#list + 1] = name; out.print('已加入开局' .. word .. '：' .. name .. '（下次跃迁生效）') end
            else
                if idx then table.remove(list, idx); out.print('已移出开局' .. word .. '：' .. name .. '（下次跃迁生效）')
                else out.print(word .. '【' .. name .. '】本就不在开局清单中') end
            end
        end
    end
end
add_admin_command('addtech',   '管理员：把科技加入开局解锁清单 /addtech <科技名...>',   function(c) edit_unlock(c, 'tech',   true)  end)
add_admin_command('deltech',   '管理员：从开局解锁清单移除科技 /deltech <科技名...>',   function(c) edit_unlock(c, 'tech',   false) end)
add_admin_command('addrecipe', '管理员：把配方加入开局解锁清单 /addrecipe <配方名...>', function(c) edit_unlock(c, 'recipe', true)  end)
add_admin_command('delrecipe', '管理员：从开局解锁清单移除配方 /delrecipe <配方名...>', function(c) edit_unlock(c, 'recipe', false) end)

-- 参数 diff（合并了原 /ensuredefaults + /config）：先跑一次 M.ensure_all（补默认/必需表/职业表/战利品权重 + 清废弃键/修类型，
-- 迁移），再弹窗对比【当前 storage】与【默认值】、改过的高亮。仅标量常量(constants.scalar_defaults)；
-- 表型(travel_chance/loot_planet_mul…)不在此列。只弹给本人、不公告。
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

-- 以下原"控制台指令"(排行/自杀/前往星球)已【改为教程弹窗里的按钮】，指令注册移除；
-- 核心逻辑抽成 M.* 供按钮点击调用（tick.on_gui_click → 这里）。
-- （"跃迁经验预览"按钮已删除：science_exp.preview 一并移除。）

-- 世界荣誉榜：历史上【全员带走经验总量】最高的前 30 个世界（reset 每次跃迁结算时记录）。
-- 天数 = 该世界结束时的 game.tick 换算成现实天（60 tick/秒 × 86400 秒/天 = 5184000 tick/天）。
function M.show_halloffame(player)
    if not player then return end
    local lines = {}
    for i, w in ipairs(storage.hall_of_fame or {}) do
        lines[#lines + 1] = {'wn.hof-entry', i, w.run, string.format('%g', w.exp), string.format('%.1f', w.tick / 5184000)}
    end
    if #lines == 0 then lines[1] = {'wn.hof-none'} end
    gui.show_popup(player, {'wn.hof-header'}, lines)
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

-- 统计数据（功能菜单按钮）：全服累计的火箭发射次数 + 送上太空的科技瓶（按瓶种类）。
-- 数据由 rocket.lua 在 on_cargo_pod_finished_ascending 累加（storage.rocket_launches / storage.rocket_packs），跨世界永久累计。
function M.show_server_stats(player)
    if not player then return end
    local lines = {{'wn.serverstats-rockets', storage.rocket_launches or 0}}
    local packs, total = storage.rocket_packs or {}, 0
    lines[#lines + 1] = {'wn.serverstats-packs-title'}
    for _, name in ipairs(constants.science_packs) do   -- 固定按 12 瓶标准顺序列出，没发过的不显示
        local n = packs[name]
        if n and n > 0 then
            total = total + n
            lines[#lines + 1] = {'wn.serverstats-pack', name, n}
        end
    end
    lines[#lines + 1] = {'wn.serverstats-packs-total', total}
    gui.show_popup(player, {'wn.serverstats-header'}, lines)
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
        player.print({'wn.travel-fail-closed', util.planet_name(planet), math.floor(((storage.travel_chance or {})[planet] or 0.5) * 100)})
        return
    end
    if not player.character then player.print({'wn.travel-no-char'}); return end
    if not game.surfaces[planet] then player.print({'wn.travel-not-generated', util.planet_name(planet)}); return end
    if not travel_inventories_empty(player) then
        player.print({'wn.travel-clear-first'})
        return
    end
    if on_cooldown(player, 'travel_cd', 'wn.cd-travel') then return end   -- 前往星球独立冷却；校验全过后才查，被拒不占冷却
    players.place_on_surface(player, planet)
    storage.respawn_surface = storage.respawn_surface or {}   -- 老存档兜底：ensure_defaults 没补到也不崩
    storage.respawn_surface[player.name] = planet   -- 前往后，该星球成为默认复活星球
    mark_action(player, 'travel_cd')
    game.print({'wn.travel-notice', player.name, planet, util.planet_name(planet)})
end

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
-- 投票/加时间态势 + 各动作可用性【单一真相源】：show_star 据此置灰按钮、cast_warp_vote/buy_warp_extend 据此服务端校验。
-- GUI 与服务端共用同一判定，杜绝"按钮看着能点、点了被拒"。规则（投票判定只看 net 与 threshold，不掺剩余时间）：
--   · can_agree  支持：净同意 < threshold(成功线)才可投。提前触发时 net==threshold → 由此条自动锁死支持(5分钟内无需另判时间)。
--   · can_oppose 反对：净同意 > 0 才可投(可抵消/拉回)。净票已为 0 再反对会压成负数、纯浪费 → 禁。
--   · can_extend 加时间：仅此项需"未处于投票提前(5分钟)倒计时状态"；已提前则倒计时被钳 5分钟、加时间无意义 → 禁。
-- 注：threshold 随在线人数变化，net 可能短暂落在 [0,threshold] 之外（如人数骤减使 threshold 降到 net 之下），属合理边缘、不另处理。
local function warp_vote_state()
    storage.warp_vote = storage.warp_vote or {}
    local agree, oppose = 0, 0
    for _, v in pairs(storage.warp_vote) do
        if v == 'agree' then agree = agree + 1 elseif v == 'oppose' then oppose = oppose + 1 end
    end
    local net = agree - oppose
    local threshold = math.ceil(#game.connected_players / (storage.warp_vote_divisor or 5))
    local in_countdown = storage.warp_vote_delta ~= nil   -- 已进入投票提前(5分钟)倒计时状态
    return {
        agree = agree, oppose = oppose, net = net, threshold = threshold, in_countdown = in_countdown,
        can_agree  = net < threshold,
        can_oppose = net > 0,
        can_extend = not in_countdown,
    }
end

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

-- /member <玩家名>（/huiyuan 同功能）：授予会员资格。仅会员/管理员可用。
local function member_grant_cmd(command)
    local _, target, sink = member_cmd_targets(command)
    if not target then return end
    if is_member(target) then sink.print({'wn.member-already', target.name}); return end
    storage.members[target.name] = true
    players.update_blueprint_perm(target)   -- 会员直通蓝图/红图：授予即解锁，不等跃迁次数
    game.print({'wn.member-granted', target.name})
end

add_command('member', {'wn.member-help'}, member_grant_cmd)

-- /unmember <玩家名>（/chehuiyuan 同功能）：撤销会员资格。【仅管理员】，可撤销任何会员。
local function member_revoke_cmd(command)
    local actor = command.player_index and game.get_player(command.player_index)   -- 仅管理员可撤销（add_admin_command 集中校验）
    local sink = actor or game
    local target = resolve_target(command, sink)
    if not target then return end
    storage.members = storage.members or {}
    if not storage.members[target.name] then sink.print({'wn.member-not', target.name}); return end
    storage.members[target.name] = nil
    players.update_blueprint_perm(target)   -- 撤销会员后按跃迁次数重新判定蓝图权限
    game.print({'wn.member-revoked', target.name})
end

add_admin_command('unmember', {'wn.unmember-help'}, member_revoke_cmd)

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
-- 弹出【统计】窗口（HUD 独立按钮）：列出所有在线玩家（名字 + 等级 + 职业），点某人看其详细统计。
function M.show_stats(player)
    if not player then return end
    if #game.connected_players <= 1 then return M.show_stats_of(player, player) end   -- 只有自己在线：跳过列表，直接看自己的面板
    local STATS_BTN_MIN_W = 240   -- 玩家条目按钮最小宽（像职业按钮，但用最小宽可随表伸展，整窗更宽更整齐；4 列后调窄，实际宽随内容伸展）
    local buttons = {
        {name = 'wn_stats_view_self', caption = {'wn.stats-view-self'}, tags = {wn_stats_view = player.name}, min_width = STATS_BTN_MIN_W},  -- 最上方：查看自己（name 固定唯一，避免与列表里自己那项重名崩溃；路由靠 tags）
        {newrow = true},   -- 分隔线：自己 / 其他在线玩家
    }
    -- 按【本次在线时长】从长到短排（session_join=本次上线 tick，越小在线越久；老档无记录视作 0=排最前）。
    local plist = {}
    for _, p in pairs(game.connected_players) do plist[#plist + 1] = p end
    local sj = storage.session_join or {}
    table.sort(plist, function(a, b) return (sj[a.name] or 0) < (sj[b.name] or 0) end)
    for _, p in ipairs(plist) do
        local lv = respawn_gifts.coin_reward(passives.get_stat(p.index, 'online_minutes'))
        local stars = math.floor(((storage.star or {})[p.name] or 0) / constants.min_to_tick)
        local planet = players.respawn_surface_name(p)   -- 出生星球（space-location 图标名）
        local def = classes.current_def(p)   -- 显示【当前】职业（本世界生效），非预约/下次
        -- 职业名三层兜底：locale 词条 → storage.class_names 热改 → def.name 中文默认。
        local cname = def and classes.text_loc('wn.class-name-' .. def.key, (storage.class_names or {})[def.key], def.name or def.key) or ''
        buttons[#buttons + 1] = {name = 'wn_stats_view_' .. p.index,   -- 名称 语言 星球 职业 等级 星星
            caption = {'wn.stats-entry', p.name, p.locale, planet, cname, lv, stars}, tags = {wn_stats_view = p.name},
            min_width = STATS_BTN_MIN_W}
    end
    -- 列数随在线人数：每满 20 人加一列，封顶 4 列（≤20→1 列、21~40→2、41~60→3、≥61→4）。
    local cols = math.min(4, math.ceil(#game.connected_players / 20))
    gui.show_popup(player, {'wn.stats-title', #game.connected_players}, {}, buttons, nil, nil, cols)   -- 标题带在线人数
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

-- 弹出【星星】窗口（HUD 独立按钮）：星星余额 + 充能进度条 + 领取按钮 + 消费按钮（投票/延长）。所有人可用，无等级门槛。
-- 原先嵌在角色面板里，现单独成窗。领取走 wn_claim_star（tick 路由 → M.claim_charge）。
function M.show_star(player)
    if not player then return end
    local bal = math.floor(((storage.star or {})[player.name] or 0) / constants.min_to_tick)
    local pend = M.charge_pending(player)
    local maxt = (storage.charge_max_hours or 30) * constants.hour_to_tick
    local claimable = math.floor(pend / constants.min_to_tick)   -- 可领整数颗
    local maxstars = math.floor(maxt / constants.min_to_tick)    -- 满充颗数
    -- 进度按【整数颗】算（不按 tick）：可领 <1 颗时 claimable=0 → frac=0 → progress_bar 第一格暗，不再被零头点亮。
    local frac = (maxstars > 0) and (claimable / maxstars) or 0
    local vc = storage.star_vote_cost or 100
    local ec, em = storage.star_extend_cost or 100, storage.star_extend_minutes or 10
    local cap, used = storage.star_extend_cap or 60, storage.star_extend_used or 0
    local st = warp_vote_state()   -- 投票/加时间可用性：余额够仍要满足态势条件，否则按钮置灰（见 warp_vote_state 规则）
    local voted = (storage.warp_vote or {})[player.name] ~= nil   -- 本轮已投过 → 两个投票按钮都置灰（不可改票）
    -- 说明区：show_popup 顶部 lines（通用说明，花费说明已移到花费区）。
    local lines = {{'wn.star-help'}}
    -- 星星区 + 花费区放 bottom_buttons（label 做文本、button 做按钮）：区首行默认 top_pad=16 与上一区换行，区内 top_pad 小=紧凑。
    local bottom_buttons = {
        -- ── 星星区（当前星星 / 进度条 / 领取按钮）──
        {label = true, plain = true, caption = {'wn.panel-star', bal}},                  -- 当前星星（区首行 → 与说明区换行）
        {label = true, plain = true, top_pad = 2, caption = {'wn.panel-star-charge',
            players.progress_bar(frac), claimable, maxstars}},                           -- 进度条 + 可领 X/Y（紧跟）
        {name = 'wn_claim_star', caption = {'wn.act-claim-star'},                         -- 领取按钮（领不了置灰，tooltip 说明）
            enabled = pend >= constants.min_to_tick,
            tooltip = (pend < constants.min_to_tick) and {'wn.star-none-yet'} or nil},
        -- ── 花费区（花费说明 + 投跃迁/停留/延长）──
        {label = true, caption = {'wn.star-spend-help'}},                                -- 花费说明（区首行 → 与星星区换行）
        {name = 'wn_btn_warp',   caption = {'wn.star-btn-warp', vc},
            enabled = (bal >= vc) and st.can_agree and not voted, tooltip = {'wn.star-btn-warp-tip', vc}},
        {name = 'wn_btn_stay',   caption = {'wn.star-btn-stay', vc},
            enabled = (bal >= vc) and st.can_oppose and not voted, tooltip = {'wn.star-btn-stay-tip', vc}},
        {name = 'wn_act_extend', caption = {'wn.star-btn-extend', em, ec},
            enabled = (bal >= ec) and (used < cap) and st.can_extend, tooltip = {'wn.star-btn-extend-tip', em, ec, used, cap}},
    }
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
    player.print({'wn.home-set', planet, util.planet_name(planet)})
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

-- 当前整数颗星星余额（storage.star 内部存 tick，1 颗 = min_to_tick）。
local function star_balance(player)
    return math.floor(((storage.star or {})[player.name] or 0) / star_tick())
end
M.star_balance = star_balance   -- 导出：星星窗口按钮显示花费 / 判断禁用

-- 扣 cost 颗星星：余额够则扣、返回 true；不足返回 false（不扣，调用方负责提示）。
local function spend_stars(player, cost)
    storage.star = storage.star or {}
    if star_balance(player) < cost then return false end
    storage.star[player.name] = (storage.star[player.name] or 0) - cost * star_tick()
    return true
end

-- 人物等级 = floor(√在线分钟)（= 开局金币 coin_reward）。
local function player_level(player)
    return respawn_gifts.coin_reward(passives.get_stat(player.index, 'online_minutes'))
end
-- 星星功能对所有人开放（star_unlock_level 已废弃，不再设等级门槛）。保留函数名供各调用点兜底。
function M.star_unlocked(player)
    return player ~= nil
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
commands.add_command('givestar', {'wn.givestar-help'}, function(command)
    local player = command.player_index and game.get_player(command.player_index)
    if not player then return end
    local name, n = string.match(command.parameter or '', '^%s*(%S+)%s+(%S+)')
    M.give_star(player, name, tonumber(n))
end)

-- 投跃迁票（vote='agree'/'oppose'，等同 /跃迁 /停留）并结算广播。
function M.cast_warp_vote(player, vote)
    if not player then return end
    -- 每人本轮只能投一次、不可改票：已投过 → 拒绝、不扣星星，刷新窗口并提示已锁定。
    if (storage.warp_vote or {})[player.name] ~= nil then
        player.print({'wn.warp-vote-locked'})
        M.show_star(player)
        return
    end
    -- 态势校验（与 show_star 置灰同源）：玩家开窗后态势可能被别人投票改变 → 本应置灰的按钮被点到。
    -- 此时不生效、不扣星星，刷新该玩家窗口并提示"按钮状态已变"。
    local st = warp_vote_state()
    local allowed = (vote == 'agree' and st.can_agree) or (vote == 'oppose' and st.can_oppose)
    if not allowed then
        player.print({'wn.btn-state-changed'})
        M.show_star(player)
        return
    end
    if on_cooldown(player, 'vote_cd', 'wn.cd-vote') then return end   -- 投票冷却（被拒不扣星星）
    local cost = storage.star_vote_cost or 100
    if not spend_stars(player, cost) then player.print({'wn.star-need', cost}); return end   -- 星星不足：不投、不占冷却
    storage.warp_vote = storage.warp_vote or {}
    storage.warp_vote[player.name] = vote
    storage.warp_vote_cost = storage.warp_vote_cost or {}
    storage.warp_vote_cost[player.name] = cost   -- 记录【实际】花费：star_vote_cost 可能被 /c 改，返还须按当时花费退
    mark_action(player, 'vote_cd')
    game.print({vote == 'agree' and 'wn.warp-vote-cast-agree' or 'wn.warp-vote-cast-oppose', player.name})
    warp_vote_eval()
    M.show_star(player)   -- 投票后刷新自己的窗口（净票/按钮态随之变化）
end

-- 花星星给【本世界】倒计时延长 star_extend_minutes 分钟。每星系累计上限 star_extend_cap，达上限按钮禁用。
-- 处于投票提前(5分钟)倒计时状态时禁止加时间（倒计时已被钳 target、加时间无意义、浪费星星）：按钮置灰；
-- 若玩家开窗后才进入该状态、点了过期按钮 → 不生效、不扣星星，刷新窗口并提示"按钮状态已变"。
function M.buy_warp_extend(player)
    if not player then return end
    if warp_vote_state().in_countdown then   -- 已进入投票提前倒计时：竞态拦截（与 show_star 置灰同源）
        player.print({'wn.btn-state-changed'})
        M.show_star(player)
        return
    end
    local cap = storage.star_extend_cap or 60
    storage.star_extend_used = storage.star_extend_used or 0
    if storage.star_extend_used >= cap then player.print({'wn.warp-extend-cap', cap}); return end
    local cost = storage.star_extend_cost or 100
    if not spend_stars(player, cost) then player.print({'wn.star-need', cost}); return end
    local add_min = storage.star_extend_minutes or 10
    storage.star_extend_used = storage.star_extend_used + add_min
    storage.warp_hours = (storage.warp_hours or ((storage.warp_initial_minutes or 10) / 60)) + add_min / 60
    game.print({'wn.warp-extend-star', player.name, add_min, storage.star_extend_used, cap})
    gui.refresh_countdown()
    M.show_star(player)   -- 刷新星星窗口（余额 / 已延长 / 倒计时）
end

return M
