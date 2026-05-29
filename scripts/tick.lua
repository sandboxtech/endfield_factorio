-- 周期性事件：自动跃迁倒计时 + 点击 HUD 弹教程。
-- 本文件是 on_gui_click 与 on_nth_tick(3600) 的唯一注册点；player_stats 的每分钟采样
-- 通过 player_stats.sample_online 接入，避免多文件重复注册 on_nth_tick 互相覆盖。
local constants = require('scripts.constants')
local reset = require('scripts.reset')
local player_stats = require('scripts.player_stats')
local map_features = require('scripts.map_features')
local util = require('scripts.util')
local gui = require('scripts.gui')
local events = require('scripts.events')

-- 消灭虫巢(unit-spawner)：原地爆少量随机科技瓶 + 金币（落地可捡）。on_entity_died 高频 → 先按类型早退；
-- 走事件总线，不与 world_fx 的 on_entity_died 互相覆盖。多人各端确定性一致（死亡事件+math.random 同步）。
events.on(defines.events.on_entity_died, function(e)
    local ent = e.entity
    if not (ent and ent.valid) or ent.type ~= 'unit-spawner' or ent.force.name ~= 'enemy' then return end
    local surface, pos = ent.surface, ent.position
    surface.spill_item_stack{position = pos, stack = {name = 'coin', count = math.random(2, 10)}, enable_looted = true}
    for _ = 1, math.random(1, 2) do
        local pack = constants.science_packs[math.random(#constants.science_packs)]
        surface.spill_item_stack{position = pos, stack = {name = pack, count = math.random(1, 6)}, enable_looted = true}
    end
end)

local METEOR_ORE = {'iron-ore', 'copper-ore', 'stone', 'coal'}
local SUPPLY_ITEMS = {'electronic-circuit', 'iron-gear-wheel', 'steel-plate', 'advanced-circuit', 'inserter', 'transport-belt', 'fast-inserter'}
-- 敌方战斗机器人三种（combat-robot）：自带攻击参数+寿命，会自动锁定并攻击敌对阵营，数十秒后消失。
local DRONE_TYPES = {'defender', 'distractor', 'destroyer'}

-- 玩家周围 [lo,hi] 距离的随机落点。
local function rand_near(ch, lo, hi)
    local ang, dist = math.random() * 2 * math.pi, lo + math.random() * (hi - lo)
    return {x = ch.position.x + math.cos(ang) * dist, y = ch.position.y + math.sin(ang) * dist}
end

-- 玩家周围 max_r 内的落点，半径 = max_r × random()³ → 大概率近(近处高密度)、小概率远。
local function rand_near_cubic(ch, max_r)
    local ang, dist = math.random() * 2 * math.pi, max_r * (math.random() ^ 3)
    return {x = ch.position.x + math.cos(ang) * dist, y = ch.position.y + math.sin(ang) * dist}
end

-- 无人机危险度随【距出生点(地图中心)距离】变化：越靠中心越安全，越远刷得越多。
-- 跳过概率：<100 完全不刷；100→1000 格线性从 MAX 降到 MIN；1000 格起维持 MIN(最容易刷)。
local DRONE_NO_SPAWN_RADIUS = 100    -- 此格内完全不刷
local DRONE_RAMP_FAR        = 1000   -- 跳过概率降到最低的距离
local DRONE_SKIP_MAX        = 1.0    -- 100 格处跳过概率（最不容易刷）
local DRONE_SKIP_MIN        = 0.2    -- 1000 格及更远跳过概率（最容易刷）
local DRONE_MAX             = 10     -- 单次最多无人机数（距离越远越接近上限）

-- 每分钟事件世界的【分发表】：键 = 事件类型，值 = 处理器(player, surface, ch, danger, k)。
-- 加新事件类型只需在此表增一项，并在 surface.lua 的 event_world 候选里列上同名键。
local WORLD_EVENTS = {
    -- raid 空降虫(危险)：玩家外圈炸开并刷一波随进化度的虫。
    raid = function(_, surface, ch, danger, k)
        local evo = game.forces.enemy.get_evolution_factor(surface)
        for _ = 1, math.max(1, math.floor((1 + danger * 2) * k + 0.5)) do
            if math.random() < 0.7 then
                local lp = rand_near(ch, 30, 80)
                surface.create_entity{name = 'massive-explosion', position = lp}
                for _ = 1, math.random(3, 6) do
                    local name = util.evo_biter(evo)
                    local p = surface.find_non_colliding_position(name, lp, 8, 1)
                    if p then surface.create_entity{name = name, position = p, force = 'enemy'} end
                end
            end
        end
    end,
    -- meteor 矿石陨石雨(奖励)：落点炸开 + 撒一堆矿。
    meteor = function(_, surface, ch, _, k)
        for _ = 1, math.max(1, math.floor(3 * k + 0.5)) do
            local lp = rand_near(ch, 25, 90)
            surface.create_entity{name = 'big-explosion', position = lp}
            surface.spill_item_stack{position = lp, stack = {name = METEOR_ORE[math.random(#METEOR_ORE)], count = math.random(20, 80)}, enable_looted = true}
        end
    end,
    -- supply 物资空投(奖励)：玩家附近撒中级材料。
    supply = function(_, surface, ch, _, k)
        for _ = 1, math.max(1, math.floor(2 * k + 0.5)) do
            local lp = rand_near(ch, 8, 28)
            surface.spill_item_stack{position = lp, stack = {name = SUPPLY_ITEMS[math.random(#SUPPLY_ITEMS)], count = math.random(10, 40)}, enable_looted = true}
        end
    end,
    -- coinfall 金币雨(奖励)：在玩家周围地上像雨点般洒落金币（走过/机器人可拾取），不再直接进背包。
    coinfall = function(_, surface, ch, _, k)
        for _ = 1, math.max(1, math.floor(8 * k + 0.5)) do
            local lp = rand_near(ch, 4, 18)
            surface.spill_item_stack{position = lp, stack = {name = 'coin', count = 1}, enable_looted = true}
        end
    end,
    -- drones 无人机来袭(危险)：投放敌方战斗机器人(defender/distractor/destroyer，enemy force)。
    -- 它们靠自身 AI 自动攻击玩家方实体、寿命到自然消失；不设 owner/target（那俩运行时只读）→ 无崩溃风险。
    -- 危险度随【距出生点(中心)距离】分段：<100 不刷、100~200 降低概率、越远刷得越多(1~10)。落点在玩家四周散布。
    drones = function(_, surface, ch, danger, k)
        local c = ch.force.get_spawn_position(surface)            -- 地图中心 = 出生点
        local dx, dy = ch.position.x - c.x, ch.position.y - c.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < DRONE_NO_SPAWN_RADIUS then return end              -- 100 格内完全不刷
        -- 跳过概率：100 格 SKIP_MAX → 1000 格 SKIP_MIN 线性插值（更远维持 MIN）
        local t = math.min(1, (d - DRONE_NO_SPAWN_RADIUS) / (DRONE_RAMP_FAR - DRONE_NO_SPAWN_RADIUS))
        local skip = DRONE_SKIP_MAX - (DRONE_SKIP_MAX - DRONE_SKIP_MIN) * t
        if math.random() < skip then return end
        -- 数量随距离 1→DRONE_MAX(以本轮地图半径为远端参考)，乘强度并夹 [1,10]
        local radius = storage.radius or 2048
        local frac = math.min(1, (d - DRONE_NO_SPAWN_RADIUS) / math.max(1, radius - DRONE_NO_SPAWN_RADIUS))
        local count = math.max(1, math.min(DRONE_MAX, math.floor((1 + (DRONE_MAX - 1) * frac) * k + 0.5)))
        for _ = 1, count do
            local name = DRONE_TYPES[math.random(#DRONE_TYPES)]
            local lp = rand_near(ch, 8, 48)   -- 不必贴脸：玩家四周一定范围内散布
            local p = surface.find_non_colliding_position(name, lp, 6, 0.5) or lp
            surface.create_entity{name = name, position = p, force = 'enemy'}
        end
    end,
    -- barrage 重炮落点(危险)：玩家周围落几发真炮弹(artillery-projectile)，范围伤害+爆炸（会砸到自家建筑）。
    -- 落点半径 = 90 × random()³ → 大概率近(高密度砸玩家)、小概率远(保留远程骚扰)。
    barrage = function(_, surface, ch, danger, k)
        for _ = 1, math.max(1, math.floor((1 + danger) * k + 0.5)) do
            local lp = rand_near_cubic(ch, 90)
            surface.create_entity{
                name = 'artillery-projectile',
                position = {x = lp.x, y = lp.y - 24},   -- 从上方飞入落到 lp
                target = lp,
                speed = 1.5,
                force = 'enemy',
            }
        end
    end,
}

-- 每分钟事件世界：按本星 storage.event_world 的事件类型，对该星上每个在线玩家触发。强度随 event_intensity。
local function run_world_events()
    if not storage.event_world then return end
    local danger = map_features.knobs().danger
    local k = storage.event_intensity or 1
    -- 全服事件量 ∝ √(在线玩家数)：每玩家以 1/√N 概率触发 → 期望触发人数 = N×(1/√N) = √N。
    -- （N=1 必触发；人越多，单个玩家越不容易摊上事件，避免人多时全服事件量线性爆炸。）
    local n = #game.connected_players
    if n == 0 then return end
    local p_trigger = 1 / math.sqrt(n)
    for _, player in pairs(game.connected_players) do
        local ch = player.character
        local et = ch and storage.event_world[player.surface.name]
        -- 尊重事件类型开关：即便本轮已滚到该类型，禁用后(/c storage.event_types.x=false)也立即停触发
        if et and storage.event_types and storage.event_types[et] == false then et = nil end
        local handler = et and WORLD_EVENTS[et]
        if handler and math.random() < p_trigger then handler(player, player.surface, ch, danger, k) end
    end
end

-- 点击左上 run 按钮 = 弹出游戏教程；点弹窗 × = 关闭。（自杀脱困改用 /suicide /zisha 命令）
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    if not (player and event.element and event.element.valid) then
        return
    end
    local name = event.element.name
    if name == 'introduction' then
        gui.show_tutorial(player)
    elseif name == gui.POPUP_CLOSE_NAME then
        gui.close_popup(player)
    end
end)

-- 按 Esc/E 关闭临时弹窗（player.opened 指向它时触发）→ 销毁，避免残留。
script.on_event(defines.events.on_gui_closed, function(event)
    if event.element and event.element.valid and event.element.name == gui.POPUP_NAME then
        event.element.destroy()
    end
end)

-- 撤离提醒触发的分钟数集合：最后 1/3/5/10/20/30 分钟，以及之前每整点小时。
local warn_minutes = {[1] = true, [3] = true, [5] = true, [10] = true, [20] = true, [30] = true}

-- 每分钟统一处理：在线时长采样 + 跃迁倒计时 + 撤离提醒。
-- （player_stats 不再单独注册 on_nth_tick，统一在此调度，避免后注册者覆盖前者。）
script.on_nth_tick(60 * 60, function()
    player_stats.sample_online()
    run_world_events()

    -- 每分钟尝试给每个在线玩家塞 1 个普通金币（背包满则塞不进，忽略即可）。
    for _, player in pairs(game.connected_players) do
        if player.character then
            local main = player.get_inventory(defines.inventory.character_main)
            if main then main.insert{name = 'coin', count = 1} end
        end
    end

    -- 刷新顶部跃迁倒计时标签（精确到分钟，每分钟一次）。
    gui.refresh_countdown()

    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local life = (storage.warp_hours or 1) * constants.hour_to_tick - last_run_ticks

    if life <= 0 then
        reset.reset()
        return
    end

    local minutes = math.floor(life / constants.min_to_tick)
    if warn_minutes[minutes] or (minutes > 30 and minutes % 60 == 0) then
        local label
        if minutes >= 60 and minutes % 60 == 0 then
            label = {'wn.duration-hours', minutes / 60}
        else
            label = {'wn.duration-minutes', minutes}
        end
        game.print({'wn.warp-warning', label})
    end
end)
