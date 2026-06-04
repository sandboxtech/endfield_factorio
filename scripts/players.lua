-- 玩家生命周期：创建/加入/离开/重生/死亡。
local constants = require('scripts.constants')
local events = require('scripts.events')
local gui = require('scripts.gui')
local passives = require('scripts.passives')
local respawn_gifts = require('scripts.respawn_gifts')
local player_stats = require('scripts.player_stats')

local M = {}

-- 复活等待时间改由 storage 配置（可 /c storage.respawn_ticks / respawn_ticks_by_enemy 热改、持久、同步）；
-- 默认值见 constants.ensure_defaults（respawn_ticks=600=10 秒，respawn_ticks_by_enemy=1800=30 秒）。

-- 把 target 的统计数据打印给 viewer：4 项技能 + 在线时长 + 各瓶累计经验。
-- 文字进度条：BAR_N 个 █，按比例 frac∈[0,1] 前段染 acid(已得)、后段染深灰(待补)。
-- 只用 █ 一种字形(靠颜色区分)，规避罕见字形缺字渲染成豆腐块的风险。
local BAR_N = 12
local function progress_bar(frac)
    frac = math.max(0, math.min(1, frac))
    local f = math.ceil(frac * BAR_N)   -- 向上取整：只要有进度(frac>0)就至少 1 格，哪怕只攒了 1 星星
    return '[color=acid]' .. string.rep('█', f) .. '[/color][color=70,70,70]' .. string.rep('█', BAR_N - f) .. '[/color]'
end
M.progress_bar = progress_bar   -- 导出供 commands.show_panel 的星星充能进度条复用（同款方块字符条）

-- 每种科技瓶一行：【瓶 + 累计等级 + 累计经验】。供【角色面板】（科技瓶经验窗口）用，看自己/他人皆可。
function M.print_exp(target, viewer)
    for _, pack in ipairs(constants.science_packs) do
        local pexp = passives.exp_total_for_pack(target.index, pack)
        local need = respawn_gifts.exp_for_next_level(pexp)        -- 升下一级所需累计经验；满级=nil
        local diff = need and (need - pexp) or 0                   -- 距下一级还差的经验；满级=0
        viewer.print({'wn.exp-detail', pack, respawn_gifts.pack_level(pexp), math.floor(pexp), math.floor(diff)})
    end
end

-- 无限产能/武器科技经验（storage.prod_exp_techs 配置的科技，研究每升一级给全体在线 +1，存 storage.exp）。
-- 只列【已获得(>0)】的，未刷到的不显示，避免十几项全 0 刷屏；按科技名排序保证多人/多次查看顺序稳定。
-- 复用 exp_total_for_pack（按 key 取值，与瓶名无关）；科技真名取自原型 localised_name。
function M.print_prod_exp(target, viewer)
    local names = {}
    for name in pairs(storage.prod_exp_techs or {}) do
        if passives.exp_total_for_pack(target.index, name) > 0 then names[#names + 1] = name end
    end
    if #names == 0 then return end
    table.sort(names)
    viewer.print({'wn.prod-exp-header'})
    for _, name in ipairs(names) do
        local proto = prototypes.technology[name]
        viewer.print({'wn.prod-exp-detail', name, proto and proto.localised_name or name,
                      math.floor(passives.exp_total_for_pack(target.index, name))})
    end
end

-- 个人数据（供【在线玩家】窗口看自己/他人）。【按段输出，调整顺序只需上下移动整段、互不影响】：
--   ① 人物等级(在线分钟/开局金币) → ② 三能力(手搓/移动/采矿拆除) → ③ 12 瓶经验 → ④ 6 项战绩(放最后)。
function M.print_status(target, viewer)
    local function s(k) return passives.get_stat(target.index, k) end
    local function blank() viewer.print('') end

    -- ① 人物等级 = 开局金币 = floor(√在线分钟)
    local om = s('online_minutes')
    viewer.print({'wn.ability-online', om, respawn_gifts.coin_reward(om)})
    blank()

    -- ② 三能力：统计值 · 等级(floor√统计) · 当前实际速度%(开局 50%)
    for _, ab in ipairs(passives.abilities) do
        local val = s(ab.stat)
        viewer.print({ab.locale, math.floor(val), math.floor(math.sqrt(val)),
                      math.floor((1 + passives.skill_factor(target.index, ab)) * 100 + 0.5)})
    end
    -- 额外生命值：与上面三能力【同格式】（统计值 · 等级=floor√统计 · 当前能力值）。
    -- __1__ 阵亡数，__2__ 等级(=floor√阵亡，沿用面板通用约定)，__3__ 当前额外生命值(=100×log10(阵亡+1))
    local deaths = s('death_count')
    viewer.print({'wn.ability-health', deaths, math.floor(math.sqrt(deaths)),
                  math.floor(passives.health_bonus(target.index) + 0.5)})
    blank()

    -- ③ 12 种科技瓶经验
    M.print_exp(target, viewer)
    blank()
    -- ③b 无限产能/武器科技经验（只列已获得的；空则整段不输出）
    M.print_prod_exp(target, viewer)
    blank()

    -- ④ 6 项战绩（纯纪录、无功能）放最后
    viewer.print({'wn.stat-kill',     s('kill_count')})
    viewer.print({'wn.stat-nest',     s('nest_count')})
    viewer.print({'wn.stat-death',    s('death_count')})
    viewer.print({'wn.stat-warps',    s('warps')})
    -- 拜访世界总次数 + 5 星球开局细分（顺序同 constants.PLANETS：母星/火山/草星/电浆/极地）
    viewer.print({'wn.stat-visit', s('visit_total'),
                  s('visit_nauvis'), s('visit_vulcanus'), s('visit_gleba'),
                  s('visit_fulgora'), s('visit_aquilo')})
    viewer.print({'wn.stat-research', s('research')})
    viewer.print({'wn.stat-key',      s('key_research')})
end


-- 跃迁/创建时对玩家做的状态清理。
function M.player_reset(player)
    if not player then
        return
    end
    player.disable_flashlight()
end

-- 脚本杀死玩家：在玩家【当前所在位置】直接处死，尸体(背包货物)留在死亡原地、不搬运。
-- 不会被带回母星：自杀走"其他死法"，由 place_on_respawn 判定在【当前星球】复活，货要取回得回原地。
-- 复活去哪由 on_player_respawned → place_on_respawn 决定（玩家的复活星球，默认母星）；这里只设个母星 force 兜底。
-- 用于所有"杀死玩家"的入口（跃迁清场 / 自杀 / 离场 等）。无 character 时跳过。
function M.kill_player(player)
    if not player or not player.character then return end
    local force = player.force
    -- force 出生点兜底设母星（实际复活落点以 place_on_respawn 为准）
    local nauvis = game.surfaces['nauvis']
    if nauvis then
        local norigin = force.get_spawn_position(nauvis)
        force.set_spawn_position(nauvis.find_non_colliding_position('character', norigin, 64, 1) or norigin, nauvis)
    end
    player.character.die()
end

-- ── 蓝图权限：跃迁满 BLUEPRINT_WARPS 次（warps 统计）才解锁【蓝图库 + 导入蓝图字符串 + 红图(拆除规划器)】──
-- 用 permission group 实现：未达次数(或新玩家)放进 'no_blueprint' 受限组，禁掉进库/取库/导入字符串/拆除框选等动作；
-- 达标后(及管理员)放回 'Default' 组。本地框选创建、使用自己手上的蓝图仍允许。
-- 注意：手上【已持有】的蓝图去放 ghost 走的是普通建造动作，服务端无法在此单独拦截，这点挡不住。
local BLUEPRINT_WARPS = 1   -- 解锁蓝图/红图所需的跃迁次数（默认值；运行时以 storage.blueprint_warps 优先，可 /c 热改）
local BLUEPRINT_BLOCKED = {
    'open_blueprint_library_gui',   -- 打开蓝图库
    'grab_blueprint_record',        -- 从库里取出蓝图到手
    'import_blueprint',             -- 导入蓝图（进库）
    'import_blueprint_string',      -- 粘贴蓝图字符串
    'import_blueprints_filtered',   -- 过滤导入
    'deconstruct',                  -- 红图(拆除规划器)框选标记拆除；手动采矿不受影响
}
-- 取（缺则建）受限组并重设禁用动作（幂等）。permission group 持久存档，create 重复会返回 nil，故 get 优先。
local function blueprint_locked_group()
    local perms = game.permissions
    local g = perms.get_group('no_blueprint') or perms.create_group('no_blueprint')
    if g then
        for _, name in ipairs(BLUEPRINT_BLOCKED) do
            g.set_allows_action(defines.input_action[name], false)
        end
    end
    return g
end

-- 按玩家 warps 把其分到 受限组 / Default 组。管理员永不受限；【会员】(storage.members) 直接解锁，无需跃迁次数。
local function update_blueprint_perm(player)
    if not (player and player.valid) then return end
    local unlocked = player.admin or (storage.members or {})[player.name]
                     or passives.get_stat(player.index, 'warps') >= (storage.blueprint_warps or BLUEPRINT_WARPS)
    local g = unlocked and game.permissions.get_group('Default') or blueprint_locked_group()
    if g then player.permission_group = g end
end
M.update_blueprint_perm = update_blueprint_perm

-- 刷新所有在线玩家蓝图权限（每次跃迁 warps+1 后由 reset 调用，让刚满 2 次的玩家即时解锁）。
function M.refresh_blueprint_perms()
    for _, p in pairs(game.connected_players) do update_blueprint_perm(p) end
end

-- 玩家本世界（storage.run）首次拥有 character 时发放起手装备 + 经验奖励。
-- 同时被 on_player_created（开局直接领）和 on_player_respawned（跃迁后第一次死亡复活）调用。
local function try_gift_first_in_world(player)
    if not player or not player.character then return end
    storage.last_respawn_run = storage.last_respawn_run or {}
    if storage.last_respawn_run[player.index] == storage.run then return end
    storage.last_respawn_run[player.index] = storage.run
    -- 拜访世界统计：本世界首次发放起手装备 = 本玩家首次"来到"这个世界（含开局直接领、跃迁后复活领、
    -- 以及【后进服】首次拥有角色领），比"跃迁时只数在线玩家"更全更准。按开局所在星球(出生星球)细分，
    -- 同时记一次总次数（总数与 5 星球各自计数都在此 +1，互不相加）。
    -- 用 M.respawn_surface_name：局部 respawn_surface_name 在本函数之后才定义，此处引用不到。
    player_stats.bump_visit(player.index, M.respawn_surface_name(player))
    respawn_gifts.on_first_respawn(player)
end

-- 把玩家安全送到【指定星球】出生点：先生成出生区块、找无碰撞落点、传送，再揭图周围 256。
-- 复活落点(place_on_respawn) 与 /前往星球 命令共用。无 character 或星球不存在则跳过。
function M.place_on_surface(player, surface_name)
    if not player or not player.character then return end
    local surface = game.surfaces[surface_name]
    if not surface then return end
    local origin = player.force.get_spawn_position(surface)
    surface.request_to_generate_chunks(origin, 3)   -- 仅【异步排队】生成出生区，不强制同步（避免卡顿）
    local pos = surface.find_non_colliding_position('character', origin, 128, 1) or origin
    player.teleport(pos, surface)
    -- 玩家落地后，引擎会自动在其周围生成区块；这里只异步排队 + chart（chart 只揭示已生成的区块）。
    surface.request_to_generate_chunks(pos, 4)   -- 4 区块 ≈ 128 格（异步，不强制；缩小以减少区块生成、压低存档体积）
    player.force.chart(surface, {{pos.x - 128, pos.y - 128}, {pos.x + 128, pos.y + 128}})
end

-- 玩家的【默认复活星球】：前往某星球时由命令记入 storage.respawn_surface[玩家名]。
-- 复活时去那里；若该星球 surface 不存在（没生成）则回母星 nauvis。
local function respawn_surface_name(player)
    local s = storage.respawn_surface and storage.respawn_surface[player.name]
    if s and game.surfaces[s] then return s end
    return 'nauvis'
end
M.respawn_surface_name = respawn_surface_name   -- 导出：在线玩家列表显示各玩家出生星球（commands.show_stats）

-- 出生星球在 PLANETS 标准顺序里的序号：nauvis=1 / vulcanus=2 / gleba=3 / fulgora=4 / aquilo=5。
-- 不新增 storage 变量，直接复用星球列表位置作为【跃迁致死复活时间】的缩放因子（越靠后/越远的星球，复活越久）。
local function respawn_planet_rank(player)
    local name = respawn_surface_name(player)
    for i, p in ipairs(constants.PLANETS) do
        if p == name then return i end
    end
    return 1   -- 兜底按母星算
end

-- 死亡复活落点，分两种：
--   · 跃迁清场(reset 打了 storage.respawn_home 标记，含跃迁时已死的玩家) → 回【出生星球】(respawn_surface，兜底母星)。
--   · 其他死法(自杀/退出/被敌人杀/环境死) → 在【当前所在星球】出生点复活(死在哪星球就在那复活)。
-- 区分目的：防止玩家靠死亡在星球间搬运物资——平时死了留在本星，只有跃迁(已清空全图)才统一回出生星球。
local function place_on_respawn(player)
    if not player then return end
    if storage.respawn_home and storage.respawn_home[player.index] then
        storage.respawn_home[player.index] = nil                       -- 一次性消费：仅本次(跃迁后)复活生效
        M.place_on_surface(player, respawn_surface_name(player))        -- 跃迁清场 → 出生星球
    else
        local s = player.surface
        M.place_on_surface(player, (s and s.valid and s.name) or 'nauvis')   -- 其他死法 → 当前所在星球
    end
end

-- 死亡：按死法设复活倒计时（环境/自杀默认 10 秒、被敌方 30 秒、跃迁致死按出生星球序号递增，见下）；
-- 只把【有 cause 的真实死亡】（被敌人/环境打死）计入该玩家 death_count，
-- 跃迁清场 / 离场 / 自杀脱困走的是脚本 die()（cause 为 nil），不计入。
script.on_event(defines.events.on_player_died, function(event)
    local player = game.get_player(event.player_index)
    local cause = event.cause
    -- 被【敌方】打死 → 30 秒复活惩罚；脚本死亡(跃迁清场/离场/自杀, cause 为 nil)与环境死亡 → 默认 10 秒。
    local by_enemy = cause and cause.valid and cause.force and cause.force.name == 'enemy'
    if player then
        local base = storage.respawn_ticks or 600
        if by_enemy then
            player.ticks_to_respawn = storage.respawn_ticks_by_enemy or 1800   -- 被敌方打死：固定惩罚
        elseif storage.respawn_home and storage.respawn_home[player.index] then
            -- 跃迁致死复活：母星=base(10 秒)，每远一个出生星球多等 storage.respawn_step_ticks（默认 300=5 秒）。
            player.ticks_to_respawn = base + (respawn_planet_rank(player) - 1) * (storage.respawn_step_ticks or 300)
        else
            player.ticks_to_respawn = base   -- 环境死 / 自杀 / 离场：默认时间
        end
        -- 尸体一律留在【死亡原地】，任何死法都不搬运；要取回背包货物需自行回倒地处。
        -- 镜头瞬移到出生点：死后玩家无 character，teleport 移动的是观察镜头（不影响尸体），
        -- 视角立刻从野外死亡处拉回【当前星球出生点中心】，不用盯着倒地处等复活。
        local surface = player.surface
        if surface and surface.valid then
            player.teleport(player.force.get_spawn_position(surface), surface)
        end
    end
    if cause then player_stats.bump(event.player_index, 'death_count') end
end)

script.on_event(defines.events.on_player_respawned, function(event)
    local player = game.get_player(event.player_index)
    place_on_respawn(player)   -- 回玩家的复活星球出生点（默认/兜底母星）+ chart 256
    player.disable_flashlight()
    passives.apply(player)     -- 重算手搓/移动/挖矿速度技能（换新角色后 modifier 清零，需重设）
    try_gift_first_in_world(player)
end)

-- 玩家离开前死掉，避免角色尸体留在飞船里阻塞跃迁清场。
script.on_event(defines.events.on_pre_player_left_game, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    -- 离线杀死玩家的总开关（storage.kill_on_leave，默认 true）：杀死=尸体/货物留在当地、杜绝
    -- "外星捡货下线、改天上线带回母星"。设 false 则离线保留角色与背包（/c storage.kill_on_leave=false）。
    if storage.kill_on_leave == false then return end

    if player.character then
        M.kill_player(player)
        -- 删除可能落在飞船原点附近的尸体
        for _, space_platform in pairs(game.forces.player.platforms) do
            if space_platform.surface then
                local corpses = space_platform.surface.find_entities_filtered {
                    area = {{-8, -8}, {8, 8}},
                    type = 'character-corpse'
                }
                for _, corpse in pairs(corpses) do
                    corpse.destroy()
                end
            end
        end
    else
        player.clear_items_inside()
    end
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    M.player_reset(player)
    gui.player_gui(player)
    passives.apply(player)     -- 施加手搓/移动/挖矿速度技能（新角色 modifier 默认 0）
    try_gift_first_in_world(player)
    update_blueprint_perm(player)   -- 新玩家 warps=0 → 进受限组，禁蓝图库/导入字符串
    gui.show_intro(player)   -- 新玩家首次进服自动弹简介（即世界标签的悬停内容）
end)

script.on_event(defines.events.on_player_left_game, function(event)
    if not event.player then
        return
    end
    event.player.gui.top.clear()
    -- 离线后名册变了，刷新所有人 HUD
    gui.players_gui()
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    -- 星星充能基准：首次见到该玩家时锚定为当前 tick（之后随游戏时间累积；不重置已有值）。
    storage.charge = storage.charge or {}
    storage.charge[player.name] = storage.charge[player.name] or game.tick
    storage.session_join = storage.session_join or {}
    storage.session_join[player.name] = game.tick   -- 本次上线时刻（在线玩家列表按本次在线时长排序用；重连覆盖）
    update_blueprint_perm(player)   -- 重连时按当前 warps 重新判定蓝图权限
    -- 名册变了，刷新所有人 HUD（自然包含自己）
    gui.players_gui()

    -- 星星提醒：待领 ≥ 20 小时（接近满充）→ 上线时提示领取，免得溢出浪费（star_unlock_level 已废弃，人人提醒）。
    local pend = math.min(game.tick - storage.charge[player.name], (storage.charge_max_hours or 30) * constants.hour_to_tick)
    if pend >= 20 * constants.hour_to_tick then player.print({'wn.star-remind'}) end

    local welcome
    if player.online_time > 0 then
        local last_delta = math.max(0, math.floor((game.tick - player.last_online) / constants.hour_to_tick))
        local total_time = math.max(0, math.floor(player.online_time / constants.hour_to_tick))
        welcome = {'wn.welcome-player', player.name, total_time, last_delta, player.locale}
    else
        welcome = {'wn.welcome-new-player', player.name, player.locale}
    end
    game.print(welcome)
end)

-- 玩家聊天 → 头顶冒【对话气泡】，跟随角色、约 10 秒后自动淡出（compi-speech-bubble 的 lifetime 处理，无需手动定时）。
-- 连发会先销毁上一个气泡，避免叠加。无角色(旁观/未生成)不冒。文本截断防刷屏。
-- 开关 storage.chat_bubble_enabled（默认 false 关闭，可 /c 热改）。
local CHAT_BUBBLE_TICKS = 600   -- 气泡寿命（10 秒 = 600 tick）
-- 走事件总线：on_console_chat 在 chat.lua 也有总线订阅，直接 script.on_event 会互相覆盖（本 handler 曾被顶掉）。
events.on(defines.events.on_console_chat, events.safe('chat_bubble', function(event)
    if not storage.chat_bubble_enabled then return end
    if not (event.player_index and event.message) then return end
    local player = game.get_player(event.player_index)
    local char = player and player.character
    if not (char and char.valid) then return end
    storage.chat_bubble = storage.chat_bubble or {}
    local old = storage.chat_bubble[player.index]
    if old and old.valid then old.destroy() end
    -- 必须锚定到 character 自身的 surface/position：玩家跨星(传送/复活)的那一瞬 player.surface
    -- 已切到新星球而 character 仍在旧星球，用 player.surface + source=character 会跨表面崩档。
    storage.chat_bubble[player.index] = char.surface.create_entity{
        name = 'compi-speech-bubble',
        position = char.position,
        source = char,
        text = string.sub(event.message, 1, 120),
        lifetime = CHAT_BUBBLE_TICKS,
    }
end))

return M
