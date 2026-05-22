-- 玩家行为统计 → 角色被动加成。
-- 经验来源不再是科技瓶，而是 player_stats 记录的行为次数/时间。
-- 曲线沿用 log10：
--   multiplier  乘法系（移速/手搓/挖矿）：stat=0 → 0.5x，stat=1 → 1x，每 10× → +50%
--   additive    加法系（HP/格子）：stat=0 → 无加成，stat=1 → +50% × base，每 10× → +50% × base

local player_stats = require('scripts.player_stats')

local M = {}

local LOG10 = math.log(10)

-- 兼容 gui/respawn_gifts：科技瓶经验仍由 science_exp 累积，用于开局物品发放。
function M.exp_total_for_pack(player_index, pack_name)
    local exp = storage.science_exp and storage.science_exp[player_index]
    if not exp then return 0 end
    local total = 0
    local prefix = pack_name .. '/'
    for key, val in pairs(exp) do
        if string.sub(key, 1, #prefix) == prefix then
            total = total + val
        end
    end
    return total
end

function M.get_stat(player_index, stat_name)
    return player_stats.get(player_index)[stat_name] or 0
end

-- 单一统计值 → factor。stat<1 时按 0 处理。
function M.factor_multiplier(stat)
    if stat < 1 then return -0.5 end
    return 0.5 * (math.log(stat) / LOG10)
end

function M.factor_additive(stat)
    if stat < 1 then return 0 end
    return 0.5 * (math.log(stat) / LOG10 + 1)
end

local function pct(f)        return string.format('%+d%%', math.floor(f * 100 + 0.5)) end
local function flat(f, base) return string.format('%+d',   math.floor(base * f + 0.5)) end

-- 5 项已实装能力，每项绑定一个 player_stats 字段。
M.abilities = {
    {
        locale = 'wn.ability-crafting',
        stat   = 'craft_count',
        curve  = M.factor_multiplier,
        apply  = function(p, f) p.character_crafting_speed_modifier = f end,
        fmt    = function(f) return pct(f) end,
    },
    {
        locale = 'wn.ability-running',
        stat   = 'afk_minutes',
        curve  = M.factor_multiplier,
        apply  = function(p, f) p.character_running_speed_modifier = f end,
        fmt    = function(f) return pct(f) end,
    },
    {
        locale = 'wn.ability-mining',
        stat   = 'mining_count',
        curve  = M.factor_multiplier,
        apply  = function(p, f) p.character_mining_speed_modifier = f end,
        fmt    = function(f) return pct(f) end,
    },
    {
        locale = 'wn.ability-health',
        stat   = 'deaths',
        curve  = M.factor_additive,
        apply  = function(p, f) p.character_health_bonus = 250 * f end,
        fmt    = function(f) return flat(f, 250) end,
    },
    {
        locale = 'wn.ability-inventory',
        stat   = 'afk_research',
        curve  = M.factor_additive,
        apply  = function(p, f) p.character_inventory_slots_bonus = math.floor(10 * f + 0.5) end,
        fmt    = function(f) return flat(f, 10) end,
    },
}

function M.apply(player)
    if not player or not player.character then return end
    for _, ability in ipairs(M.abilities) do
        local val = M.get_stat(player.index, ability.stat)
        ability.apply(player, ability.curve(val))
    end
end

return M
