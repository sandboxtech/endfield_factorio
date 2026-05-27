-- 事件驱动的"世界效果"：监听游戏事件，在带相应主题标记的世界里触发。
-- 走 scripts/events 事件总线订阅 → 不会与其它 on_entity_died 注册互相覆盖。
local events = require('scripts.events')
local util = require('scripts.util')

-- 复制虫世界（danger_theme[星球].replicant）：玩家建筑被【虫】破坏时，原地冒出新虫 →
-- 防御被打穿会滚雪球，呼应 Comfy journey 的 infested/replicant。on_entity_died 高频，先做最便宜的早退。
events.on(defines.events.on_entity_died, function(e)
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

return {}
