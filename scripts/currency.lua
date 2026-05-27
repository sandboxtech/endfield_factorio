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

-- 单个在线统计值 → 奖励品质瓶子数量。
function M.reward_amount(stat)
    if not stat or stat < 1 then return 0 end
    return math.floor(math.sqrt(stat) * (constants.reward_amount_mult or 1))
end

return M
