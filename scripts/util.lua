-- 通用工具函数。除了读写 storage 外无副作用。
local constants = require('scripts.constants')

local M = {}

-- 星球的【本地化名】(localised string)：按每个玩家自己的语言显示官方译名（中文=新地星/祝融星/句芒星/雷神星/玄冥星）。
-- 用作 wn.* 消息的【文本】参数；[img=space-location/x] 图标参数仍须传内部名。原型缺失兜底内部名。
function M.planet_name(planet)
    local p = game.planets and game.planets[planet]
    return p and p.prototype.localised_name or planet
end

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
    return 2 ^ ((math.random() - math.random()) * x)
end

-- 对数三角分布：值域 [1/n, n]，几何对称、峰在 1（指数 (rand−rand) 是三角分布，n^0=1）。
-- n 越大浮动越大（n=4 → 1/4~4）。等价 random_exp(log2(n))，但用倍率界 n 表达更直观。
function M.log_tri(n)
    return n ^ (math.random() - math.random())
end

-- 最大公约数：把 满级线:满级总数 约成最简比（→ "每 P 级得 Q 个"）。
function M.gcd(a, b)
    a, b = math.floor(math.abs(a)), math.floor(math.abs(b))
    while b ~= 0 do a, b = b, a % b end
    return a == 0 and 1 or a
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

-- 二项分布采样：n 次独立试验、每次成功率 p，返回成功数（"每件物品独立 p 概率获得"时的获得件数 ~ B(n,p)）。
-- np 与 n(1-p) 都 ≥10 时用正态近似 + Box-Muller（O(1)，两次 random）；否则逐次掷（此时期望偏小或 n 小，仅跃迁发装备时调用，开销可接受）。
function M.binomial(n, p)
    if n <= 0 or p <= 0 then return 0 end
    if p >= 1 then return n end
    local mu = n * p
    if mu < 10 or (n - mu) < 10 then
        local k = 0
        for _ = 1, n do if math.random() < p then k = k + 1 end end
        return k
    end
    local z = math.sqrt(-2 * math.log(1 - math.random())) * math.cos(2 * math.pi * math.random())   -- 1-random() ∈ (0,1]：避免 log(0)
    local k = math.floor(mu + math.sqrt(mu * (1 - p)) * z + 0.5)
    if k < 0 then return 0 elseif k > n then return n end
    return k
end

return M
