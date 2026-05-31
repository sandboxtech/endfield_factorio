-- 角色统计累积：手搓秒数 / 移动格数 / 采矿次数 / 击杀 / 毁巢，仅用于角色面板【统计展示】。
-- （旧的"手搓/移动/挖矿动作即时提速"功能已移除，这些指标不再驱动任何速度加成。）
-- 科技瓶经验由 science_exp 累积；本模块独占 on_player_crafted_item / on_player_mined_entity /
-- on_player_changed_position（player_stats 不再注册这些，避免双重注册互相覆盖）。
local constants = require('scripts.constants')
local player_stats = require('scripts.player_stats')
local science_exp = require('scripts.science_exp')
local events = require('scripts.events')

local M = {}

local MOVE_MAX_STEP = 50   -- 单次采样位移上限（格）：超过视为瞬移/换面，不计入移动距离

-- 某瓶累计科技瓶经验（= 存的瓶数 ÷ bottles_per_exp，现 =1 故即瓶数×品质）。供 gui / respawn_gifts / inspect 读取。
function M.exp_total_for_pack(player_index, pack_name)
    local player = game.get_player(player_index)
    if not player then return 0 end
    local exp = science_exp.player_exp(player)
    return ((exp and exp[pack_name]) or 0) / constants.bottles_per_exp
end

function M.get_stat(player_index, stat_name)
    return player_stats.get(player_index)[stat_name] or 0
end

-- ---------------------------------------------------------------------------
-- 动作 → 统计累积（仅记录，不提速）
-- ---------------------------------------------------------------------------
script.on_event(defines.events.on_player_crafted_item, function(e)
    -- 手搓按【配方基础时间】(recipe.energy，速度=1 时的秒数) 累积，而非物品数量：搓慢/复杂的涨得多。
    local s = player_stats.get(e.player_index)
    s.craft_count = s.craft_count + ((e.recipe and e.recipe.energy) or 0)
end)

script.on_event(defines.events.on_player_mined_entity, function(e)
    if not e.player_index then return end
    -- 拆蓝图虚影/虚影地块不算"采矿"（本就没实体、不产物）。
    local ent = e.entity
    if ent and (ent.type == 'entity-ghost' or ent.type == 'tile-ghost') then return end
    local s = player_stats.get(e.player_index)
    s.mining_count = s.mining_count + 1
end)

-- 移动：on_player_changed_position 走路时每 tick 触发；累加位移，过滤瞬移/换面/载具。
script.on_event(defines.events.on_player_changed_position, function(e)
    local p = game.get_player(e.player_index)
    if not (p and p.character) then return end
    storage.move_pos = storage.move_pos or {}
    local pos, si = p.position, p.surface.index
    local a = storage.move_pos[p.index]
    if a and a.si == si then
        if not p.vehicle then
            -- 曼哈顿距离 |dx|+|dy|，免开方。阈值 50 过滤跃迁/复活的远距瞬移（换 surface 已被 si 过滤）。
            local d = math.abs(pos.x - a.x) + math.abs(pos.y - a.y)
            if d < MOVE_MAX_STEP then
                local s = player_stats.get(p.index)
                s.move_distance = s.move_distance + d
            end
        end
        a.x, a.y = pos.x, pos.y   -- 原地更新坐标，复用同一张表（省 GC）
    else
        storage.move_pos[p.index] = {x = pos.x, y = pos.y, si = si}
    end
end)

-- 个人成就统计：仅记录【玩家角色亲手】击杀的敌人（炮塔/机器人击杀不计），虫巢额外记 nest_count。
-- 只写 storage、不展示驱动。走事件总线（on_entity_died 多方监听）。
events.on(defines.events.on_entity_died, function(e)
    local ent = e.entity
    if not (ent and ent.valid) or ent.force.name ~= 'enemy' then return end
    local cause = e.cause
    if not (cause and cause.valid and cause.type == 'character') then return end
    local p = cause.player
    if not p then return end
    local s = player_stats.get(p.index)
    s.kill_count = s.kill_count + 1
    if ent.type == 'unit-spawner' then s.nest_count = s.nest_count + 1 end
end)

return M
