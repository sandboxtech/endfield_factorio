-- 事件驱动的"世界效果"(world_fx)：监听游戏事件，在满足条件的世界里触发。
-- 走 scripts/events 事件总线订阅 → 不会与其它同事件注册互相覆盖。
-- 每个 fx 有一个【全局开关】storage.world_fx[name]（默认开；游戏内 /c storage.world_fx.xxx=false 即可禁用）。
-- 开关只是总闸；具体哪一轮/哪颗星出现，仍由各 fx 自身条件（如 danger_theme[星球].replicant）滚定。
-- 加新 fx：在此 register 一个，并到 constants.ensure_defaults 的 world_fx 默认列表补上同名键。
local events = require('scripts.events')
local util = require('scripts.util')

local M = {}

-- 注册一个 world_fx：name=全局开关键；event=监听事件；run=效果逻辑（仅开关开启时调用）。
local function register(name, event, run)
    events.on(event, function(e)
        if storage.world_fx and storage.world_fx[name] == false then return end
        run(e)
    end)
end

-- 复制虫（danger_theme[星球].replicant）：玩家建筑被【虫】破坏时，原地冒出新虫 →
-- 防御被打穿会滚雪球。on_entity_died 高频，先做最便宜的早退。
register('replicant', defines.events.on_entity_died, function(e)
    if not storage.danger_theme then return end
    local ent = e.entity
    if not (ent and ent.valid) then return end
    local theme = storage.danger_theme[ent.surface.name]
    if not (theme and theme.replicant) then return end
    -- 仅"玩家方建筑、被敌对方杀死"才触发
    if not (ent.force and ent.force.name == 'player') then return end
    local cause = e.cause
    if not (cause and cause.valid and cause.force and cause.force.name == 'enemy') then return end
    local surface = ent.surface
    local evo = game.forces.enemy.get_evolution_factor(surface)
    for _ = 1, math.random(1, 2) do
        local name = util.evo_biter(evo)
        local p = surface.find_non_colliding_position(name, ent.position, 6, 1)
        if p then surface.create_entity{name = name, position = p, force = 'enemy'} end
    end
end)

return M
