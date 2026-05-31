-- 玩家生命周期：创建/加入/离开/重生/死亡。
local constants = require('scripts.constants')
local events = require('scripts.events')
local gui = require('scripts.gui')
local passives = require('scripts.passives')
local respawn_gifts = require('scripts.respawn_gifts')
local player_stats = require('scripts.player_stats')

local M = {}

-- 复活等待时间改由 storage 配置（可 /c storage.respawn_ticks / enemy_respawn_ticks 热改、持久、同步）；
-- 默认值见 constants.ensure_defaults（respawn_ticks=180=3 秒，enemy_respawn_ticks=1800=30 秒）。

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
    blank()

    -- ③ 12 种科技瓶经验
    M.print_exp(target, viewer)
    blank()
    blank()

    -- ④ 6 项战绩（纯纪录、无功能）放最后
    viewer.print({'wn.stat-kill',     s('kill_count')})
    viewer.print({'wn.stat-nest',     s('nest_count')})
    viewer.print({'wn.stat-death',    s('death_count')})
    viewer.print({'wn.stat-warps',    s('warps')})
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

-- 脚本杀死玩家：先把玩家移到【当前所在表面】的出生点再杀死，尸体(背包货物)留在当前星球，
-- 不会被带回母星（杜绝"在外星捡货 → /suicide 把货带回母星"）。
-- 复活去哪由 on_player_respawned → place_on_respawn 决定（玩家的复活星球，默认母星）；这里只设个母星 force 兜底。
-- 用于所有"杀死玩家"的入口（跃迁清场 / 自杀 / 离场 等）。无 character 时跳过。
function M.kill_player(player)
    if not player or not player.character then return end
    local force = player.force
    -- ① 在当前表面出生点处死亡（尸体留在当前星球）
    local surface = player.surface
    local origin = force.get_spawn_position(surface)
    local pos = surface.find_non_colliding_position('character', origin, 64, 1) or origin
    player.teleport(pos, surface)
    -- ② force 出生点兜底设母星（实际复活落点以 place_on_respawn 为准）
    local nauvis = game.surfaces['nauvis']
    if nauvis then
        local norigin = force.get_spawn_position(nauvis)
        force.set_spawn_position(nauvis.find_non_colliding_position('character', norigin, 64, 1) or norigin, nauvis)
    end
    -- ③ 杀死
    player.character.die()
end

-- 玩家本世界（storage.run）首次拥有 character 时发放起手装备 + 经验奖励。
-- 同时被 on_player_created（开局直接领）和 on_player_respawned（跃迁后第一次死亡复活）调用。
local function try_gift_first_in_world(player)
    if not player or not player.character then return end
    storage.last_respawn_run = storage.last_respawn_run or {}
    if storage.last_respawn_run[player.index] == storage.run then return end
    storage.last_respawn_run[player.index] = storage.run
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

-- 死亡复活落点：回玩家的默认复活星球出生点（默认/兜底＝母星）。
local function place_on_respawn(player)
    M.place_on_surface(player, respawn_surface_name(player))
end

-- 死亡：把复活倒计时压到 3 秒；只把【有 cause 的真实死亡】（被敌人/环境打死）计入该玩家 death_count，
-- 跃迁清场 / 离场 / 自杀脱困走的是脚本 die()（cause 为 nil），不计入。
script.on_event(defines.events.on_player_died, function(event)
    local player = game.get_player(event.player_index)
    local cause = event.cause
    -- 被【敌方】打死 → 30 秒复活惩罚；脚本死亡(跃迁清场/离场/自杀, cause 为 nil)与环境死亡 → 默认 3 秒。
    local by_enemy = cause and cause.valid and cause.force and cause.force.name == 'enemy'
    if player then
        player.ticks_to_respawn = by_enemy and (storage.enemy_respawn_ticks or 1800) or (storage.respawn_ticks or 180)
    end
    if cause then player_stats.bump(event.player_index, 'death_count') end
end)

script.on_event(defines.events.on_player_respawned, function(event)
    local player = game.get_player(event.player_index)
    place_on_respawn(player)   -- 回玩家的复活星球出生点（默认/兜底母星）+ chart 256
    player.disable_flashlight()
    passives.apply(player)     -- 重算手搓/移动/挖矿速度技能（换新角色后 modifier 清零，需重设）
    respawn_gifts.apply_inventory_bonus(player)   -- 背包格数加成（按本轮首发清单格数，读存值保持）
    try_gift_first_in_world(player)
end)

-- 玩家离开前死掉，避免角色尸体留在飞船里阻塞跃迁清场。
script.on_event(defines.events.on_pre_player_left_game, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

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
    respawn_gifts.apply_inventory_bonus(player)   -- 背包格数加成（按本轮首发清单格数，读存值保持）
    try_gift_first_in_world(player)
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
    -- 名册变了，刷新所有人 HUD（自然包含自己）
    gui.players_gui()

    -- 星星提醒：达 star_unlock_level 级 且 待领 ≥ 20 小时（接近满充）→ 上线时提示领取，免得溢出浪费。
    local star_lv = respawn_gifts.coin_reward(passives.get_stat(player.index, 'online_minutes'))
    if star_lv >= (storage.star_unlock_level or 0) then
        local pend = math.min(game.tick - storage.charge[player.name], (storage.charge_max_hours or 30) * constants.hour_to_tick)
        if pend >= 20 * constants.hour_to_tick then player.print({'wn.star-remind'}) end
    end

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

-- 玩家聊天 → 头顶冒【对话气泡】，跟随角色、约 5 秒后自动淡出（compi-speech-bubble 的 lifetime 处理，无需手动定时）。
-- 连发会先销毁上一个气泡，避免叠加。无角色(旁观/未生成)不冒。文本截断防刷屏。
local CHAT_BUBBLE_TICKS = 600   -- 气泡寿命（5 秒）
script.on_event(defines.events.on_console_chat, events.safe('chat_bubble', function(event)
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
