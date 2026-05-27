-- 货币换算：把累计经验 / 行为统计折算成实物货币。
--   1) 科技瓶经验 → 同种科技瓶的实物（品质阶梯），用于生产建筑市场。
--   2) 在线行为统计 → 品质金币，用于装备市场。
-- 两条曲线都用 √（凹函数）：越攒越多，但边际递减，防止滚雪球。
local constants = require('scripts.constants')

local M = {}

-- 累计经验 exp → 该瓶各品质奖励数量 {{quality=, count=}, ...}。
-- 第 q 品质的第 k 瓶成本 = cost_mult[q] × k 经验（三角成本 ⇒ 数量 ∝ √经验）。
-- 先用最便宜的品质填满 cap(=200) 再进入下一品质；填不满即停止（不跳级）。
function M.reward_for_exp(exp)
    local result = {}
    local remaining = exp or 0
    local cap = constants.reward_quality_cap
    for _, q in ipairs(constants.quality_order) do
        local m = constants.quality_cost_mult[q]
        -- 最大 n ≤ cap 使 m × n(n+1)/2 ≤ remaining
        local n = math.floor((math.sqrt(8 * remaining / m + 1) - 1) / 2)
        if n > cap then n = cap end
        if n > 0 then
            result[#result + 1] = {quality = q, count = n}
            remaining = remaining - m * n * (n + 1) / 2
        end
        if n < cap then break end
    end
    return result
end

-- 累计经验 exp → 进度信息，供玩家 UI 显示"等级 + 当前经验/升级经验"。
--   level   = 当前累计能换到的瓶子总数（= 奖励数量，奖励正比于等级）
--   into    = 已累积、朝向下一瓶的经验（0 ≤ into < need）
--   need    = 升到下一级（再换 1 瓶）所需经验
--   quality = 下一瓶的品质（正在填充的品质阶梯）；满级时为 nil
function M.progress_for_exp(exp)
    local remaining = exp or 0
    local cap = constants.reward_quality_cap
    local level = 0
    for _, q in ipairs(constants.quality_order) do
        local m = constants.quality_cost_mult[q]
        local n = math.floor((math.sqrt(8 * remaining / m + 1) - 1) / 2)
        if n > cap then n = cap end
        if n > 0 then
            level = level + n
            remaining = remaining - m * n * (n + 1) / 2
        end
        if n < cap then
            -- 下一瓶是本品质的第 (n+1) 个，成本 m×(n+1)
            return {level = level, into = math.floor(remaining), need = m * (n + 1), quality = q}
        end
    end
    return {level = level, into = 0, need = 0, quality = nil}  -- 满级（5 品质各 1 组）
end

-- 单个在线统计值 → 金币数量。
function M.coin_amount(stat)
    if not stat or stat < 1 then return 0 end
    return math.floor(math.sqrt(stat) * (constants.coin_curve_mult or 1))
end

return M
