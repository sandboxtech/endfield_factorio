-- 周期性事件：自动跃迁倒计时 + 点击 HUD 弹教程。
-- 本文件统一调度【每分钟周期任务】：经 events 总线挂 on_tick + tick 整除门控（不用 on_nth_tick，避免被覆盖、间隔可扩展）。
-- player_stats 的每分钟采样通过 player_stats.sample_online 在此调用，不再各自注册定时器。
local constants = require('scripts.constants')
local player_stats = require('scripts.player_stats')
local map_features = require('scripts.map_features')
local gui = require('scripts.gui')
local events = require('scripts.events')
local commands = require('scripts.commands')   -- HUD 按钮点击路由到其导出的 show_panel / cast_warp_vote

-- 前向声明：科技世界的"得到科技"helper，下方虫巢死亡 1% 奖励与 WORLD_EVENTS 也用它（定义在文件后半）。
local grant_random_tech

-- 各星球【特色虫巢】死亡额外掉落的对应星球瓶：草星虫巢 → 农业瓶（草瓶）。以后加别的星球虫巢在此补。
local SPAWNER_PACK = {
    ['gleba-spawner']       = 'agricultural-science-pack',
    ['gleba-spawner-small'] = 'agricultural-science-pack',
}
-- 消灭虫巢(unit-spawner)：原地爆金币（开关 storage.nest_coin，0=不掉）+ 随机基础瓶 + 特色虫巢额外爆对应星球瓶。
-- on_entity_died 高频 → 先按类型早退；走事件总线，不与 world_fx 的 on_entity_died 互相覆盖。多人各端确定性一致。
events.on(defines.events.on_entity_died, function(e)
    local ent = e.entity
    if not (ent and ent.valid) or ent.type ~= 'unit-spawner' or ent.force.name ~= 'enemy' then return end
    local surface, pos = ent.surface, ent.position
    local coins = storage.nest_coin or 6
    if coins > 0 then
        surface.spill_item_stack{position = pos, stack = {name = 'coin', count = coins}, enable_looted = true}
    end
    -- 科技瓶：从 constants.nest_science_packs（基础 6 瓶，含军事、不含 space/星球瓶）里随机掉。
    for _ = 1, math.random(1, 2) do
        local pack = constants.nest_science_packs[math.random(#constants.nest_science_packs)]
        surface.spill_item_stack{position = pos, stack = {name = pack, count = math.random(1, 6)}, enable_looted = true}
    end
    -- 特色虫巢（草星等）额外爆对应星球瓶。
    local sp_pack = SPAWNER_PACK[ent.name]
    if sp_pack then
        surface.spill_item_stack{position = pos, stack = {name = sp_pack, count = math.random(1, 6)}, enable_looted = true}
    end
    -- 由【玩家方】消灭虫巢（角色/炮塔/机器人/火炮等，只要死因实体属于 player 方即可）：
    -- 以本世界概率 storage.nest_tech_chance（每轮 reset 滚定，0.1%~1%）触发"获得科技"（随机解锁一个未研究科技），全服广播。
    local cause = e.cause
    if cause and cause.valid and cause.force and cause.force.name == 'player'
        and math.random() < (storage.nest_tech_chance or 0.005) then
        grant_random_tech()
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
-- 落点附近(半径4)已有散落物品(item-on-ground)则 true → 跳过本次 spill，避免物品越堆越多/卡顿/难看。
local function has_ground_items(surface, lp)
    return surface.count_entities_filtered{position = lp, radius = 4, type = 'item-entity', limit = 1} > 0
end

local DRONE_SKIP_MAX        = 1.0    -- 100 格处跳过概率（最不容易刷）
local DRONE_SKIP_MIN        = 0.2    -- 1000 格及更远跳过概率（最容易刷）
local DRONE_MAX             = 10     -- 单次最多无人机数（距离越远越接近上限）
-- barrage 重炮：每次世界事件触发再以此概率【跳过不落弹】，大幅拉长落弹间隔（0.9 = 仅 1/10 触发真落弹）。
local BARRAGE_SKIP          = 0.9
-- 单次世界事件【落点/生成数硬上限】：兜底防 /c storage.event_intensity 填超大数 → 一 tick 狂建实体卡死。
local EVENT_MAX_SPAWN       = 50

-- 每分钟事件世界的【分发表】：键 = 事件类型，值 = 处理器(player, surface, ch, danger, k)。
-- 加新事件类型只需在此表增一项，并在 surface.lua 的 event_world 候选里列上同名键。
-- raid 撒【虫卵】用的有效物品（懒构建，按本游戏实际存在的原型过滤）：
--   biter-egg 30min→大型虫 / pentapod-egg 15min→五足虫 / captive-biter-spawner 30min→巨型虫。
local RAID_EGGS
local function raid_eggs()
    if not RAID_EGGS then
        RAID_EGGS = {}
        for _, n in ipairs({'biter-egg', 'pentapod-egg', 'captive-biter-spawner'}) do
            if prototypes.item[n] then RAID_EGGS[#RAID_EGGS + 1] = n end
        end
    end
    return RAID_EGGS
end

local WORLD_EVENTS = {
    -- raid 空降【虫卵】(延迟危险)：在玩家四周地上撒虫卵/五足虫卵/虫巢孵化器，随机【不同新鲜度】。
    -- 蛋会随时间腐败孵化成虫(spoil_percent 越高孵得越快)；玩家可抢在孵化前捡走 → 抢救=资源、放任=刷怪。
    raid = function(_, surface, ch, danger, k)
        local eggs = raid_eggs()
        if #eggs == 0 then return end
        for _ = 1, math.min(EVENT_MAX_SPAWN, math.max(1, math.floor((1 + danger * 2) * k + 0.5))) do
            if math.random() < 0.7 then
                local lp = rand_near(ch, 20, 70)
                local egg = eggs[math.random(#eggs)]
                local cnt = (egg == 'captive-biter-spawner') and 1 or math.random(2, 6)   -- 孵化器 stack_size=1
                surface.spill_item_stack{
                    position = lp,
                    stack = {name = egg, count = cnt, spoil_percent = math.random()},   -- 线性随机新鲜度：越高越快孵化
                    enable_looted = math.random() < 0.5,   -- 随机：一半可被自动拾取/机器人收，一半留地上(更易孵化)
                }
            end
        end
    end,
    -- meteor 矿石陨石雨(奖励)：落点炸开 + 撒一堆矿。落点半径立方分布 → 大概率近(好捡)、小概率远(范围大)。
    -- 落点已有散落物则跳过这一发，避免矿越堆越多。
    meteor = function(_, surface, ch, _, k)
        for _ = 1, math.min(EVENT_MAX_SPAWN, math.max(1, math.floor(3 * k + 0.5))) do
            local lp = rand_near_cubic(ch, 90)
            if not has_ground_items(surface, lp) then
                surface.create_entity{name = 'big-explosion', position = lp}
                surface.spill_item_stack{position = lp, stack = {name = METEOR_ORE[math.random(#METEOR_ORE)], count = math.random(20, 80)}, enable_looted = true}
            end
        end
    end,
    -- supply 物资空投(奖励)：玩家附近撒中级材料。
    supply = function(_, surface, ch, _, k)
        for _ = 1, math.min(EVENT_MAX_SPAWN, math.max(1, math.floor(2 * k + 0.5))) do
            local lp = rand_near(ch, 8, 28)
            surface.spill_item_stack{position = lp, stack = {name = SUPPLY_ITEMS[math.random(#SUPPLY_ITEMS)], count = math.random(10, 40)}, enable_looted = true}
        end
    end,
    -- coinfall 金币雨(奖励)：在玩家周围地上像雨点般洒落金币（走过/机器人可拾取），不再直接进背包。
    -- 落点已有散落物则跳过这一次，避免金币越堆越多。
    coinfall = function(_, surface, ch, _, k)
        for _ = 1, math.min(EVENT_MAX_SPAWN, math.max(1, math.floor(8 * k + 0.5))) do
            local lp = rand_near(ch, 4, 18)
            if not has_ground_items(surface, lp) then
                surface.spill_item_stack{position = lp, stack = {name = 'coin', count = 1}, enable_looted = true}
            end
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
        local radius = storage.radius_standard or 2048
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
        if math.random() < BARRAGE_SKIP then return end   -- 大幅降低炮弹出现概率/频率，落弹间隔拉长很多
        for _ = 1, math.min(EVENT_MAX_SPAWN, math.max(1, math.floor((1 + danger) * k + 0.5))) do
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
    -- tech 科技世界（对全 force，忽略落点/玩家/危险度）：从【所有科技】(排除星球发现科技)随机抽一个，
    -- 不看是否已研究，已研究则以 tech_world_lose_chance 概率【失去】，未研究则以 tech_world_gain_chance 概率【得到】。
    tech = function()
        local force = game.forces.player
        local pool = {}
        for _, t in pairs(force.technologies) do
            if t.enabled and string.sub(t.name, 1, 16) ~= 'planet-discovery' then pool[#pool + 1] = t end
        end
        if #pool == 0 then return end
        local t = pool[math.random(#pool)]
        if t.researched then
            if math.random() < (storage.tech_world_lose_chance or 0.25) then
                t.researched = false
                game.print({'wn.tech-lose', t.name, t.localised_name})
            end
        else
            if math.random() < (storage.tech_world_gain_chance or 0.5) then
                t.researched = true
                game.print({'wn.tech-gain', t.name, t.localised_name})
            end
        end
    end,
}

-- 每分钟事件世界：先用【全局固定概率 storage.event_chance】判定这一分钟全服是否发生事件；
-- 发生则在【符合条件的在线玩家】里随机挑【一个】，对其所在星球的事件类型触发一次（强度随 event_intensity）。
-- 全服每分钟最多一次事件（频率只由 event_chance 决定、与人数无关）；每种事件另有【独立跳过钮】可单独放缓/关闭某类。
local function run_world_events()
    if not storage.event_world then return end
    if math.random() >= (storage.event_chance or 0.5) then return end   -- 全局概率：这一分钟不发生事件
    local danger = map_features.knobs().danger
    local k = storage.event_intensity or 1
    -- 当前第几分钟（run_world_events 仅在整分钟被调用，故为整数）；用于各事件类型的独立周期跳过。Lua 5.2 无 //，用 floor。
    local minute = math.floor(game.tick / (60 * 60))
    local periods = storage.event_period_min or {}
    -- 候选 = 有 character、所在星球配了事件类型、该类型未被 /c storage.event_types.x=false 禁用、且本分钟轮到该类型的在线玩家
    local candidates = {}
    for _, player in pairs(game.connected_players) do
        local ch = player.character
        local et = ch and storage.event_world[player.surface.name]
        if et and storage.event_types and storage.event_types[et] == false then et = nil end
        -- 【单独跳过钮】：该类型每 event_period_min[et] 分钟才参与一次（默认 1=每分钟；/c storage.event_period_min.raid=3 → 每3分钟才可能）。
        if et and minute % (periods[et] or 1) ~= 0 then et = nil end
        if et and WORLD_EVENTS[et] then
            candidates[#candidates + 1] = {player = player, ch = ch, et = et}
        end
    end
    if #candidates == 0 then return end
    local pick = candidates[math.random(#candidates)]   -- math.random 多端同步，挑选确定性一致
    WORLD_EVENTS[pick.et](pick.player, pick.player.surface, pick.ch, danger, k)
end

-- 雷暴星球(thunder)：身处该星球的在线玩家，被闪电直击（lightning：100 伤害+震屏，有护盾/护甲可扛）。
-- 高效判定：先收集雷暴星球上的在线玩家(n 人)，整体只滚【一次】random < 单人概率×n，命中才随机抽一人劈。
-- 等价于逐人独立判定但只 1 次 random：单玩家期望仍 36000 tick = 10 分钟一次；全局频率随人数线性增多。
events.on(defines.events.on_tick, events.safe('thunder', function()
    if not storage.event_world then return end
    local victims = {}
    for _, player in pairs(game.connected_players) do
        if player.character and storage.event_world[player.surface.name] == 'thunder' then
            victims[#victims + 1] = player
        end
    end
    local n = #victims
    if n > 0 and math.random() < (storage.thunder_chance or 1 / 36000) * n then
        local p = victims[math.random(n)]
        p.surface.create_entity{name = 'lightning', position = p.position}
    end
end))

-- HUD 6 按钮点击路由（简介/玩法/指令/角色面板/跃迁/停留）；点弹窗 × = 关闭。（自杀脱困改用 /suicide /zisha 命令）
script.on_event(defines.events.on_gui_click, events.safe('gui_click', function(event)
    local player = game.get_player(event.player_index)
    if not (player and event.element and event.element.valid) then
        return
    end
    local name = event.element.name
    if name == 'warp_countdown' then
        gui.show_intro(player)                      -- 点世界标签 = 弹出简介（即其悬停内容）
    elseif name == 'wn_btn_gameplay' then
        gui.show_tutorial(player)                   -- 第一个按钮：纯玩法&指令说明文字
    elseif name == 'wn_btn_actions' then
        gui.show_actions(player)                    -- 第二个按钮：所有功能按钮（面板/投票/预览/排行/自杀/前往/出生星球）
    elseif name == 'wn_admin_gen' then
        commands.admin_gen(player)                  -- 管理员红按钮：各星生成 debug
    elseif name == 'wn_admin_diff' then
        commands.admin_diff(player)                 -- 管理员红按钮：ensure_defaults + 参数对比
    elseif name == 'wn_btn_stats' then
        commands.show_stats(player)                 -- 状态按钮 = 人物等级 + 三能力 + 统计
    elseif name == 'wn_btn_class' then
        gui.show_classes(player)                    -- 职业按钮：弹出职业选择窗口
    elseif name == 'wn_btn_star' then
        commands.show_star(player)                  -- 星星按钮：弹出星星窗口（余额/充能/领取）
    elseif name == 'wn_claim_star' then
        commands.claim_charge(player)               -- 星星窗口里"领取星星充能"按钮
    elseif event.element.tags and event.element.tags.wn_stats_view then
        local t = game.get_player(event.element.tags.wn_stats_view)   -- 统计列表里点某玩家 = 看其详细统计
        if t then commands.show_stats_of(player, t) end
    elseif name == 'wn_btn_warp' then
        commands.cast_warp_vote(player, 'agree')    -- 跃迁/停留 = 对应投票
    elseif name == 'wn_btn_stay' then
        commands.cast_warp_vote(player, 'oppose')
    elseif name == 'wn_act_extend' then
        commands.buy_warp_extend(player)            -- 星星窗口"花星星延长倒计时"按钮
    elseif name == 'wn_act_preview' then
        commands.show_preview(player)               -- 教程弹窗里的功能按钮（原 /预览 等指令已改按钮）
    elseif name == 'wn_act_lastrank' then
        commands.show_lastrank(player)
    elseif name == 'wn_act_suicide' then
        commands.do_suicide(player)
    elseif event.element.tags and event.element.tags.wn_travel then
        commands.travel(player, event.element.tags.wn_travel)   -- 前往星球按钮（tags 带星球名）
    elseif event.element.tags and event.element.tags.wn_home then
        commands.set_home_planet(player, event.element.tags.wn_home)   -- 出生星球按钮（设复活+领装备的星球）
    elseif event.element.tags and event.element.tags.wn_class then
        commands.set_class(player, event.element.tags.wn_class)   -- 选择职业按钮（设本人职业，下次跃迁生效）
    elseif name == gui.POPUP_CLOSE_NAME then
        gui.close_popup(player)
    end
end))

-- 按 Esc/E 关闭临时弹窗（player.opened 指向它时触发）→ 销毁，避免残留。
script.on_event(defines.events.on_gui_closed, events.safe('gui_closed', function(event)
    if event.element and event.element.valid and event.element.name == gui.POPUP_NAME then
        event.element.destroy()
    end
end))

-- 撤离提醒触发的分钟数集合：最后 1/3/5/10/20/30 分钟，以及之前每整点小时。
local warn_minutes = {[1] = true, [3] = true, [5] = true, [10] = true, [20] = true, [30] = true}

-- "得到科技"：从所有【已启用且未研究】科技(排除星球发现科技)里随机抽一个直接研究(不看前置)并广播全服。
-- 供科技世界 gain 与"消灭虫巢 1% 奖励"复用。脚本设 researched 触发的是 by_script 事件，research.lua 早退 → 不改跃迁倒计时。
function grant_random_tech()
    local force = game.forces.player
    local pool = {}
    for _, tech in pairs(force.technologies) do
        if tech.enabled and not tech.researched and string.sub(tech.name, 1, 16) ~= 'planet-discovery' then
            pool[#pool + 1] = tech
        end
    end
    if #pool == 0 then return end
    local tech = pool[math.random(#pool)]
    tech.researched = true
    game.print({'wn.tech-gain', tech.name, tech.localised_name})
end

-- 每分钟统一处理：在线时长采样 + 跃迁倒计时 + 撤离提醒。
-- 【不再用 on_nth_tick】：on_nth_tick 每个间隔只能挂一个 handler、易被后注册者覆盖且间隔写死；
-- 改走 events 总线的 on_tick（多订阅安全，与 warp_fx 的 on_tick 并存），开头用 tick 整除【门控】——
-- 绝大多数 tick 在此一句廉价返回，效率与 on_nth_tick 等同。将来要加别的周期任务，
-- 再写一段 `if game.tick % 间隔 == 0 then ... end` 即可，互不覆盖、间隔随意。
local PER_MINUTE = 60 * 60
events.on(defines.events.on_tick, function()
    if game.tick % PER_MINUTE ~= 0 then return end   -- 非整分钟：立即返回（廉价门控，省去整个每分钟处理）
    player_stats.sample_online()
    -- 事件世界（刷怪/落点/科技世界）碰大量原型、最易出错，单独兜底，出错不影响倒计时/跃迁。
    events.safe('world_events', run_world_events)()

    -- （金币不再每分钟发放：只在每轮首次复活按 floor(√在线分钟) 一次性发，见 respawn_gifts.gift_list。）
    -- （科技世界已并入事件世界：tech 作为 WORLD_EVENTS 的一种，由 run_world_events 统一按事件机制触发，此处不再单独判定。）

    -- 刷新顶部跃迁倒计时标签（精确到分钟，每分钟一次）。
    gui.refresh_countdown()

    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local life = (storage.warp_hours or 1) * constants.hour_to_tick - last_run_ticks

    -- 跃迁触发已收口到 warp_fx（截止前 10 秒倒计时、归零调 reset）；本处只负责【临近告警】。
    if life <= 0 then return end

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
