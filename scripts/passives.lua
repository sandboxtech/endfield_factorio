-- 角色被动技能：边玩边练，动作即时升级。
--   手搓 → 手搓速度；移动(步行) → 移动速度；采矿/拆除 → 挖矿速度。
-- 曲线自带 -50% 下限：对应统计为 0 时该项 -50%，做动作累计后爬升、超过原版。
-- 科技瓶经验由 science_exp 累积，不驱动这些技能。
-- 本模块独占 on_player_crafted_item / on_player_mined_entity / on_player_changed_position
-- （player_stats 不再注册这些，避免双重注册互相覆盖）。
local constants = require('scripts.constants')
local player_stats = require('scripts.player_stats')
local science_exp = require('scripts.science_exp')
local events = require('scripts.events')

local M = {}

local LOG10 = math.log(10)
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

-- 速度技能曲线：stat=0 → -0.5（-50%）；stat=to_zero → 0（原版）；之后继续 log 缓升。
-- f = -0.5 + 0.5×log10(1 + 9×stat/to_zero)。to_zero 越大升级越慢。
local function speed_curve(to_zero)
    return function(stat) return -0.5 + 0.5 * math.log(1 + 9 * stat / to_zero) / LOG10 end
end

local function pct(f) return string.format('%+d%%', math.floor(f * 100 + 0.5)) end

-- 3 个技能（手搓/移动/挖矿）。factor(stat) → 修正系数。★ to_zero 越大升级越慢。
M.abilities = {
    {locale = 'wn.ability-crafting', stat = 'craft_count',  factor = speed_curve(5000),
     apply = function(p, f) p.character_crafting_speed_modifier = f end, fmt = pct},
    {locale = 'wn.ability-running',  stat = 'move_distance', factor = speed_curve(100000), cap = 1.0,
     apply = function(p, f) p.character_running_speed_modifier = f end, fmt = pct},
    {locale = 'wn.ability-mining',   stat = 'mining_count',  factor = speed_curve(5000),
     apply = function(p, f) p.character_mining_speed_modifier = f end, fmt = pct},
}

-- 某玩家某技能当前的修正系数 f。cap 存在则封顶（移动速度封 +100%，避免走路过快）。
function M.skill_factor(player_index, ab)
    local f = ab.factor(M.get_stat(player_index, ab.stat))
    if ab.cap and f > ab.cap then f = ab.cap end
    return f
end

local function apply_one(player, ab)
    if player and player.character then ab.apply(player, M.skill_factor(player.index, ab)) end
end

-- 重算并施加全部技能（新建/复活/跃迁后角色换新需调用）。
function M.apply(player)
    if not player or not player.character then return end
    for _, ab in ipairs(M.abilities) do ab.apply(player, M.skill_factor(player.index, ab)) end
end

-- ---------------------------------------------------------------------------
-- 动作 → 即时升级（同时累积统计）
-- ---------------------------------------------------------------------------
script.on_event(defines.events.on_player_crafted_item, function(e)
    -- 手搓按【配方基础时间】(recipe.energy，速度=1 时的秒数) 累积，而非物品数量：搓慢/复杂的涨得多。
    local s = player_stats.get(e.player_index)
    s.craft_count = s.craft_count + ((e.recipe and e.recipe.energy) or 0)
    apply_one(game.get_player(e.player_index), M.abilities[1])
end)

script.on_event(defines.events.on_player_mined_entity, function(e)
    if not e.player_index then return end
    -- 拆蓝图虚影/虚影地块不算"采矿"（本就没实体、不产物）→ 不练拆除技能。
    local ent = e.entity
    if ent and (ent.type == 'entity-ghost' or ent.type == 'tile-ghost') then return end
    local s = player_stats.get(e.player_index)
    s.mining_count = s.mining_count + 1
    apply_one(game.get_player(e.player_index), M.abilities[3])
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
            -- 曼哈顿距离 |dx|+|dy|，免开方。阈值 50 过滤跃迁/复活远距瞬移（换 surface 已被 si 过滤）。
            local d = math.abs(pos.x - a.x) + math.abs(pos.y - a.y)
            if d < MOVE_MAX_STEP then
                local s = player_stats.get(p.index)
                s.move_distance = s.move_distance + d
                -- 移动技能修正随距离 log 缓升，单 tick 变化肉眼不可见 → 仅当较上次施加值变动 ≥0.1% 才写引擎 modifier。
                local ab = M.abilities[2]
                local f = ab.factor(s.move_distance)
                if ab.cap and f > ab.cap then f = ab.cap end
                if not a.f or f - a.f >= 0.001 then
                    ab.apply(p, f)
                    a.f = f
                end
            end
        end
        a.x, a.y = pos.x, pos.y   -- 原地更新坐标，复用同一张表（省 GC）
    else
        storage.move_pos[p.index] = {x = pos.x, y = pos.y, si = si}
    end
end)

-- 个人成就统计：仅记录【玩家角色亲手】击杀的敌人（炮塔/机器人击杀不计），虫巢额外记 nest_count。
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
