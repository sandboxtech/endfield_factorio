-- 经验 → 玩家被动加成。
-- 每个 ability 由 1~N 个瓶子驱动，组合方式：factor 用 log 相加，等价于经验相乘。
-- 例：手搓速度 = log10(red) + log10(purple)，所以 red=10 + purple=10 等同 single=100。
--
-- 两类曲线：
--   multiplier  乘法系（移速/手搓/挖矿）：exp=0 → 0.5x，exp=1 → 1x，每 10× → +50%
--   additive    加法系（HP）：exp=0 → 0（无加成），exp=1 → +50% × base，每 10× → +50% × base

local M = {}

local LOG10 = math.log(10)

-- 累计某种瓶子的全品质经验。
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

-- 把多个瓶子的 exp 折成单一 log 值。exp<1 的瓶子不计入（贡献 0）。
local function combined_log(packs, player_index)
    local total_log = 0
    local any_active = false
    for _, pack in ipairs(packs) do
        local exp = M.exp_total_for_pack(player_index, pack)
        if exp >= 1 then
            total_log = total_log + math.log(exp) / LOG10
            any_active = true
        end
    end
    return total_log, any_active
end

-- 乘法系：所有瓶子都为 0 时回到 0.5x，每 10× 经验 +50%。
function M.combined_factor_multiplier(packs, player_index)
    local log_sum, any = combined_log(packs, player_index)
    if not any then return -0.5 end
    return 0.5 * log_sum
end

-- 加法系：所有瓶子都为 0 时无加成，每 10× 经验 +50% × base。
function M.combined_factor_additive(packs, player_index)
    local log_sum, any = combined_log(packs, player_index)
    if not any then return 0 end
    return 0.5 * (log_sum + 1)
end

local function pct(f)        return string.format('%+d%%', math.floor(f * 100 + 0.5)) end
local function flat(f, base) return string.format('%+d',   math.floor(base * f + 0.5)) end

-- 在 tooltip 里显示每个瓶子的经验。
function M.build_exp_breakdown(packs, player_index)
    local parts = {}
    for _, pack in ipairs(packs) do
        table.insert(parts, tostring(M.exp_total_for_pack(player_index, pack)))
    end
    return table.concat(parts, ' + ')
end

-- 12 个瓶子对应的能力。apply = nil 表示暂未实装，仅在 tooltip 显示经验。
M.abilities = {
    {
        locale = 'wn.ability-crafting',
        packs  = {'automation-science-pack'},
        curve  = M.combined_factor_multiplier,
        apply  = function(p, f) p.character_crafting_speed_modifier = f end,
        fmt    = function(f) return pct(f) end,
    },
    {
        locale = 'wn.ability-running',
        packs  = {'logistic-science-pack'},
        curve  = M.combined_factor_multiplier,
        apply  = function(p, f) p.character_running_speed_modifier = f end,
        fmt    = function(f) return pct(f) end,
    },
    {
        locale = 'wn.ability-mining',
        packs  = {'chemical-science-pack'},
        curve  = M.combined_factor_multiplier,
        apply  = function(p, f) p.character_mining_speed_modifier = f end,
        fmt    = function(f) return pct(f) end,
    },
    {
        locale = 'wn.ability-health',
        packs  = {'military-science-pack'},
        curve  = M.combined_factor_additive,
        apply  = function(p, f) p.character_health_bonus = 250 * f end,
        fmt    = function(f) return flat(f, 250) end,
    },
    -- 暂未实装：tooltip 显示经验占位，apply 跳过
    { packs = {'production-science-pack'}    },
    { packs = {'utility-science-pack'}       },
    { packs = {'space-science-pack'}         },
    { packs = {'metallurgic-science-pack'}   },
    { packs = {'electromagnetic-science-pack'} },
    { packs = {'agricultural-science-pack'}  },
    { packs = {'cryogenic-science-pack'}     },
    { packs = {'promethium-science-pack'}    },
}

-- 对单个玩家重算并写入所有 character 级被动。无 character 时跳过。
function M.apply(player)
    if not player or not player.character then return end
    for _, ability in ipairs(M.abilities) do
        if ability.apply then
            ability.apply(player, ability.curve(ability.packs, player.index))
        end
    end
end

return M
