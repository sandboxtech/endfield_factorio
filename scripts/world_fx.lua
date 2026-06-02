-- 事件驱动的"世界效果"(world_fx)：监听游戏事件，在满足条件的世界里触发。
-- 走 scripts/events 事件总线订阅 → 不会与其它同事件注册互相覆盖。
-- 每个 fx 有一个【全局开关】storage.world_fx[name]（默认开；游戏内 /c storage.world_fx.xxx=false 即可禁用）。
-- 开关只是总闸；具体触发由各 fx 自身条件/概率控制（如 replicant 按常数 storage.replicant_chance 滚）。
-- 加新 fx：在此 register 一个，并到 constants.ensure_defaults 的 world_fx 默认列表补上同名键。
local events = require('scripts.events')
local util = require('scripts.util')
local map_features = require('scripts.map_features')

local M = {}

-- 注册一个 world_fx：name=全局开关键；event=监听事件；run=效果逻辑（仅开关开启时调用）。
local function register(name, event, run)
    events.on(event, function(e)
        if storage.world_fx and storage.world_fx[name] == false then return end
        run(e)
    end)
end

-- 复制虫：玩家建筑被【虫】破坏时，按【全局常数概率】storage.replicant_chance 原地冒出新虫 → 防御被打穿会滚雪球。
-- 全局生效（不分星球），由 world_fx 开关 + 该概率控制。on_entity_died 高频，先做最便宜的早退。
register('replicant', defines.events.on_entity_died, function(e)
    local ent = e.entity
    if not (ent and ent.valid) then return end
    -- 仅"玩家方【建筑】、被敌对方杀死"才触发（过滤掉绝大多数 entity 死亡）
    if not (ent.force and ent.force.name == 'player') then return end
    if not ent.prototype.is_building then return end   -- 只认建筑：排除玩家角色/机器人/载具，否则玩家被虫打死会在尸体处冒虫
    local cause = e.cause
    if not (cause and cause.valid and cause.force and cause.force.name == 'enemy') then return end
    if math.random() >= map_features.knobs().danger then return end   -- 概率 = 本轮危险度 danger（危险世界爆虫多、易滚雪球）
    local surface = ent.surface
    local evo = game.forces.enemy.get_evolution_factor(surface)
    for _ = 1, math.random(1, 2) do
        local name = util.evo_biter(evo)
        local p = surface.find_non_colliding_position(name, ent.position, 6, 1)
        if p then surface.create_entity{name = name, position = p, force = 'enemy'} end
    end
end)

return M
