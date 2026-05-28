-- 周期性事件：自动跃迁倒计时 + 点击 HUD 弹教程。
-- 本文件是 on_gui_click 与 on_nth_tick(3600) 的唯一注册点；player_stats 的每分钟采样
-- 通过 player_stats.sample_online 接入，避免多文件重复注册 on_nth_tick 互相覆盖。
local constants = require('scripts.constants')
local reset = require('scripts.reset')
local player_stats = require('scripts.player_stats')
local map_features = require('scripts.map_features')
local util = require('scripts.util')
local gui = require('scripts.gui')

local METEOR_ORE = {'iron-ore', 'copper-ore', 'stone', 'coal'}
local SUPPLY_ITEMS = {'electronic-circuit', 'iron-gear-wheel', 'steel-plate', 'advanced-circuit', 'inserter', 'transport-belt', 'fast-inserter'}

-- 玩家周围 [lo,hi] 距离的随机落点。
local function rand_near(ch, lo, hi)
    local ang, dist = math.random() * 2 * math.pi, lo + math.random() * (hi - lo)
    return {x = ch.position.x + math.cos(ang) * dist, y = ch.position.y + math.sin(ang) * dist}
end

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
}

-- 每分钟事件世界：按本星 storage.event_world 的事件类型，对该星上每个在线玩家触发。强度随 event_intensity。
local function run_world_events()
    if not storage.event_world then return end
    local danger = map_features.knobs().danger
    local k = storage.event_intensity or 1
    for _, player in pairs(game.connected_players) do
        local ch = player.character
        local et = ch and storage.event_world[player.surface.name]
        -- 尊重事件类型开关：即便本轮已滚到该类型，禁用后(/c storage.event_types.x=false)也立即停触发
        if et and storage.event_types and storage.event_types[et] == false then et = nil end
        local handler = et and WORLD_EVENTS[et]
        if handler then handler(player, player.surface, ch, danger, k) end
    end
end

-- 点击左上 run 按钮 = 弹出游戏教程（自杀脱困改用 /suicide /zisha 命令）。
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    if event.element.name == 'introduction' then
        player.print({'wn.tutorial'})
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
