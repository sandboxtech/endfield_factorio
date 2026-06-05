-- 周期性事件：自动跃迁倒计时 + 点击 HUD 弹教程。
-- 本文件统一调度【每分钟周期任务】：经 events 总线挂 on_tick + tick 整除门控（不用 on_nth_tick，避免被覆盖、间隔可扩展）。
-- player_stats 的每分钟采样通过 player_stats.sample_online 在此调用，不再各自注册定时器。
local constants = require('scripts.constants')
local player_stats = require('scripts.player_stats')
local map_features = require('scripts.map_features')
local gui = require('scripts.gui')
local events = require('scripts.events')
local commands = require('scripts.commands')   -- HUD 按钮点击路由到其导出的 show_panel / cast_warp_vote

-- 前向声明："得到科技"helper，虫巢死亡的小概率奖励用它（定义在文件后半）。
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
        gui.show_actions(player)                    -- 第二个按钮：所有功能按钮（荣誉榜/排行/自杀/前往/出生星球）
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
    elseif name == 'wn_act_hof' then
        commands.show_halloffame(player)            -- 功能菜单"世界荣誉榜"按钮
    elseif name == 'wn_act_lastrank' then
        commands.show_lastrank(player)
    elseif name == 'wn_act_serverstats' then
        commands.show_server_stats(player)          -- 功能菜单"统计数据"按钮：全服火箭/瓶子统计

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
-- 供"消灭虫巢小概率奖励"使用。脚本设 researched 触发的是 by_script 事件，research.lua 早退 → 不改跃迁倒计时。
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
    -- （世界事件系统已整体移除：raid/meteor/supply/coinfall/drones/barrage/tech/thunder。）
    -- （金币不再每分钟发放：只在每轮首次复活按 floor(√在线分钟) 一次性发，见 respawn_gifts.gift_list。）

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
