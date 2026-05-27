-- 角色被动技能：边玩边练，动作即时升级。
--   手搓 → 手搓速度；移动(步行) → 移动速度；采矿/拆除 → 挖矿速度；死亡 → 生命上限。
-- 曲线自带 -50% 下限：对应统计为 0 时该项 -50%，做动作累计后爬升、超过原版。
-- 科技瓶经验由 science_exp 累积，只用于"下次开局的初始物品"，不驱动技能。
-- 本模块独占 on_player_crafted_item / on_player_mined_entity / on_player_changed_position /
-- on_player_died（player_stats 不再注册这些，避免双重注册互相覆盖）。
local player_stats = require('scripts.player_stats')
local science_exp = require('scripts.science_exp')

local M = {}

local LOG10 = math.log(10)
local MOVE_MAX_STEP = 50   -- 单次采样位移上限（格）：超过视为瞬移/换面，不计入移动距离

-- 某瓶累计科技瓶经验（→ 下次开局初始物品），供 gui / respawn_gifts / inspect 读取。
function M.exp_total_for_pack(player_index, pack_name)
    local player = game.get_player(player_index)
    if not player then return 0 end
    local exp = science_exp.player_exp(player)
    return (exp and exp[pack_name]) or 0
end

function M.get_stat(player_index, stat_name)
    return player_stats.get(player_index)[stat_name] or 0
end

-- 速度技能曲线：stat=0 → -0.5（-50%）；stat=to_zero → 0（原版）；之后继续 log 缓升。
-- f = -0.5 + 0.5×log10(1 + 9×stat/to_zero)。to_zero 越大升级越慢——设大让"玩几天才到 0%"，
-- 到 +50% 需 11×to_zero（老玩家级），杜绝"随便做点就 +50%"。
local function speed_curve(to_zero)
    return function(stat) return -0.5 + 0.5 * math.log(1 + 9 * stat / to_zero) / LOG10 end
end
-- 生命（加法系）：死亡越多上限越高。deaths<1 → 0；否则 0.5×(log10(deaths)+1)，×250 HP。
local function health_curve(deaths)
    if deaths < 1 then return 0 else return 0.5 * (math.log(deaths) / LOG10 + 1) end
end

local function pct(f)  return string.format('%+d%%', math.floor(f * 100 + 0.5)) end
local function flat(f) return string.format('%+d',   math.floor(250 * f + 0.5)) end

-- 4 个技能。factor(stat) → 修正系数。★ to_zero（达到 0% 所需统计）越大越慢，按需调。
M.abilities = {
    {locale = 'wn.ability-crafting', stat = 'craft_count',  factor = speed_curve(5000),
     apply = function(p, f) p.character_crafting_speed_modifier = f end, fmt = pct},
    {locale = 'wn.ability-running',  stat = 'move_distance', factor = speed_curve(100000), cap = 1.0,
     apply = function(p, f) p.character_running_speed_modifier = f end, fmt = pct},
    {locale = 'wn.ability-mining',   stat = 'mining_count',  factor = speed_curve(5000),
     apply = function(p, f) p.character_mining_speed_modifier = f end, fmt = pct},
    {locale = 'wn.ability-health',   stat = 'deaths',        factor = health_curve,
     apply = function(p, f) p.character_health_bonus = 250 * f end, fmt = flat},
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
-- 动作 → 即时升级
-- ---------------------------------------------------------------------------
script.on_event(defines.events.on_player_crafted_item, function(e)
    local s = player_stats.get(e.player_index)
    local st = e.item_stack
    s.craft_count = s.craft_count + ((st and st.valid_for_read and st.count) or 1)
    apply_one(game.get_player(e.player_index), M.abilities[1])
end)

script.on_event(defines.events.on_player_mined_entity, function(e)
    if not e.player_index then return end
    local s = player_stats.get(e.player_index)
    s.mining_count = s.mining_count + 1
    apply_one(game.get_player(e.player_index), M.abilities[3])
end)

-- 移动（步行）：on_player_changed_position 走路时每 tick 触发；累加位移，过滤瞬移/换面/载具。
script.on_event(defines.events.on_player_changed_position, function(e)
    local p = game.get_player(e.player_index)
    if not (p and p.character) then return end
    storage.move_pos = storage.move_pos or {}
    local pos, si = p.position, p.surface.index
    local a = storage.move_pos[p.index]
    if a and a.si == si and not p.vehicle then
        -- 曼哈顿距离 |dx|+|dy|，免开方。
        local d = math.abs(pos.x - a.x) + math.abs(pos.y - a.y)
        -- 阈值放宽到 50：传奇装甲+大量机械腿单 tick 也就几格，远低于 50；
        -- 真正的瞬移（跃迁/死亡传送回出生点）通常几百上千格、或换 surface（已被 si 过滤）。
        if d < MOVE_MAX_STEP then
            local s = player_stats.get(p.index)
            s.move_distance = s.move_distance + d
            apply_one(p, M.abilities[2])
        end
    end
    storage.move_pos[p.index] = {x = pos.x, y = pos.y, si = si}
end)

script.on_event(defines.events.on_player_died, function(e)
    player_stats.get(e.player_index).deaths = player_stats.get(e.player_index).deaths + 1
    -- 生命上限在复活后(新角色)由 players.lua 的 passives.apply 生效。
end)

return M
