-- 通用工具函数。除了读写 storage 外无副作用。
local constants = require('scripts.constants')

local M = {}

-- 剩余 ticks → (整数小时, 整数分钟)；负数按 0。倒计时统一显示"X 小时 Y 分钟"，不要小数小时。
function M.hm(ticks)
    local t = math.max(0, ticks)
    return math.floor(t / constants.hour_to_tick), math.floor((t % constants.hour_to_tick) / constants.min_to_tick)
end

-- 数字格式化为人类可读的"档位"。
function M.readable(x)
    if x < 0 then
        return 0
    elseif x < 0.1 then
        return math.ceil(x * 100) * 0.01
    elseif x < 3 then
        return math.floor(x * 10) * 0.1
    elseif x < 10 then
        return math.floor(x)
    elseif x < 100 then
        return math.floor(x / 10) * 10
    elseif x < 1000 then
        return math.floor(x / 100) * 100
    else
        return math.floor(x / 1000) * 1000
    end
end

-- 指数分布，方差由 x 控制。
function M.random_exp(x)
    return math.pow(2, (math.random() - math.random()) * x)
end


-- 按敌人进化度挑一种虫（空降/复制虫等共用）。
function M.evo_biter(evo)
    local r = math.random()
    if evo > 0.9 and r < 0.4 then return 'behemoth-biter' end
    if evo > 0.5 and r < 0.5 then return 'big-biter' end
    if evo > 0.2 and r < 0.6 then return 'medium-biter' end
    return 'small-biter'
end

-- 影响玩法节奏的参数（腐败速度、敌人密度、阳光、污染等）：大概率正常值 1，小概率小幅偏离。
-- 70% 直接返回 1；其余 2^(三角随机×0.6) ≈ 0.66~1.5。避免极端值毁掉一局的可玩性。
function M.mostly_normal()
    if math.random() < 0.7 then return 1 end
    return M.readable(2 ^ ((math.random() - math.random()) * 0.6))
end

return M
