-- 经验 → 玩家被动加成。
--
-- 公式：能力倍率 = 0.25 * (log10(exp) + 2)，初始（exp=0）裁到 0.25x。
-- 对应 Factorio 修改器（vanilla = 1，modifier 加在 1 上）：
--   modifier = 0.25 * log10(exp) - 0.5     （exp >= 1）
--   modifier = -0.75                       （exp <= 0）
--
-- 经验对照：
--   exp     ability   modifier
--    0       0.25x    -0.75
--    1       0.50x    -0.50
--   10       0.75x    -0.25
--   100      1.00x     0.00   ← 原版水平
--   1000     1.25x    +0.25
--   10000    1.50x    +0.50

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

-- 把经验值映射为 Factorio modifier（加在 vanilla=1 上的偏移）。
function M.bonus_factor(exp)
    if exp <= 0 then return -0.75 end
    return 0.25 * math.log(exp) / LOG10 - 0.5
end

-- 12 种瓶子 → 对应能力的描述、locale key、应用函数、格式化函数。
-- apply(player, factor)：把 modifier 写到角色或 force 上。nil 表示尚未实装。
-- fmt(factor)：返回 tooltip 里 __2__ 的显示文本，nil → '—'。
local function pct(factor)  return string.format('%+d%%',   math.floor((factor) * 100 + 0.5)) end
local function flat(factor, base) return string.format('%+d', math.floor(base * factor + 0.5)) end

M.skills = {
    {
        pack = 'automation-science-pack', locale = 'wn.skill-automation',
        apply = function(p, f) p.character_crafting_speed_modifier = f end,
        fmt   = function(f) return pct(f) end,
    },
    {
        pack = 'logistic-science-pack', locale = 'wn.skill-logistic',
        apply = function(p, f) p.character_running_speed_modifier = f end,
        fmt   = function(f) return pct(f) end,
    },
    {
        pack = 'military-science-pack', locale = 'wn.skill-military',
        apply = function(p, f) p.character_mining_speed_modifier = f end,
        fmt   = function(f) return pct(f) end,
    },
    {
        pack = 'chemical-science-pack', locale = 'wn.skill-chemical',
        -- 生命上限：vanilla 250，按倍率换算成 flat bonus。
        apply = function(p, f) p.character_health_bonus = 250 * f end,
        fmt   = function(f) return flat(f, 250) end,
    },
    {
        pack = 'production-science-pack', locale = 'wn.skill-production',
        apply = nil,
        fmt   = function(_) return nil end,
    },
    {
        pack = 'utility-science-pack', locale = 'wn.skill-utility',
        apply = nil,
        fmt   = function(_) return nil end,
    },
    {
        pack = 'space-science-pack', locale = 'wn.skill-space',
        apply = nil,
        fmt   = function(_) return nil end,
    },
    {
        pack = 'metallurgic-science-pack', locale = 'wn.skill-metallurgic',
        apply = nil,
        fmt   = function(_) return nil end,
    },
    {
        pack = 'electromagnetic-science-pack', locale = 'wn.skill-electromagnetic',
        apply = nil,
        fmt   = function(_) return nil end,
    },
    {
        pack = 'agricultural-science-pack', locale = 'wn.skill-agricultural',
        apply = nil,
        fmt   = function(_) return nil end,
    },
    {
        pack = 'cryogenic-science-pack', locale = 'wn.skill-cryogenic',
        apply = nil,
        fmt   = function(_) return nil end,
    },
    {
        pack = 'promethium-science-pack', locale = 'wn.skill-promethium',
        apply = nil,
        fmt   = function(_) return nil end,
    },
}

-- 对单个玩家重算并写入所有 character 级被动。无 character 时跳过（如死亡/平台上无身体）。
function M.apply(player)
    if not player or not player.character then return end
    for _, skill in pairs(M.skills) do
        if skill.apply then
            local exp = M.exp_total_for_pack(player.index, skill.pack)
            skill.apply(player, M.bonus_factor(exp))
        end
    end
end

return M
