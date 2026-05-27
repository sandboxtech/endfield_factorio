-- 货币换算：把累计经验 / 行为统计折算成实物货币。
--   1) 科技瓶经验 → 同种科技瓶的实物（品质阶梯），用于生产建筑市场。
--   2) 在线行为统计 → 品质科技瓶（uncommon+，不发可量产的 normal）。
-- 两条曲线都用 √（凹函数）：越攒越多，但边际递减，防止滚雪球。
local constants = require('scripts.constants')

local M = {}

-- 货币一：累计经验 exp → 携带奖励瓶子（epic、legendary 两档）{{quality=, count=}, ...}。
-- 每档独立用平方根曲线：count = floor(√exp / divisor)，再封顶 cap。
--   epic：divisor=1，cap=1800（9 组）；legendary：divisor=10，cap=200（1 组）。
function M.reward_for_exp(exp)
    exp = exp or 0
    local result = {}
    if exp < 1 then return result end
    local root = math.sqrt(exp)
    for _, r in ipairs(constants.carry_rewards) do
        local n = math.min(math.floor(root / r.divisor), r.cap)
        if n > 0 then
            result[#result + 1] = {quality = r.quality, count = n}
        end
    end
    return result
end

-- 累计经验 exp → 进度信息，供玩家 UI 显示"等级 + 当前经验/升级经验"。
--   level   = 当前累计能换到的瓶子总数（= 奖励数量，奖励正比于等级）
--   into    = 已累积、朝向下一瓶的经验（0 ≤ into < need）
--   need    = 升到下一级（再换 1 瓶）所需经验
--   quality = 下一瓶的品质（正在填充的品质阶梯）；满级时为 nil
function M.progress_for_exp(exp)
    exp = exp or 0
    local root = math.sqrt(exp)
    local level, next_exp, next_q = 0, nil, nil
    for _, r in ipairs(constants.carry_rewards) do
        local n = math.min(math.floor(root / r.divisor), r.cap)
        level = level + n
        if n < r.cap then
            -- 下一个该档瓶子（第 n+1 个）出现在 exp = ((n+1) × divisor)²
            local base = (n + 1) * r.divisor
            local cand = base * base
            if not next_exp or cand < next_exp then
                next_exp = cand
                next_q = r.quality
            end
        end
    end
    if not next_exp then
        return {level = level, into = 0, need = 0, quality = nil}  -- epic+legendary 都满
    end
    return {level = level, into = math.floor(exp), need = math.floor(next_exp), quality = next_q}
end

-- 单个在线统计值 → 奖励品质瓶子数量。
function M.reward_amount(stat)
    if not stat or stat < 1 then return 0 end
    return math.floor(math.sqrt(stat) * (constants.reward_amount_mult or 1))
end

return M
