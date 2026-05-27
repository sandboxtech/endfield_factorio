-- 全局常量。无副作用，可被任意模块 require。
return {
    hour_to_tick = 216000,
    min_to_tick = 3600,

    not_admin_text = {'wn.permission-denied'},

    -- 跃迁时玩家背包里每"组"科技瓶按品质换算成的经验点数
    quality_exp = {
        normal    = 1,
        uncommon  = 2,
        rare      = 3,
        epic      = 4,
        legendary = 5,
    },

    -- 12 种科技瓶，作为"货币种类"和奖励/商店遍历顺序的唯一来源。
    science_packs = {
        'automation-science-pack', 'logistic-science-pack', 'military-science-pack',
        'chemical-science-pack', 'production-science-pack', 'utility-science-pack',
        'space-science-pack', 'metallurgic-science-pack', 'electromagnetic-science-pack',
        'agricultural-science-pack', 'cryogenic-science-pack', 'promethium-science-pack',
    },

    -- 品质由低到高（市场按 5 品质各上架一条 offer 时遍历用）。
    quality_order = {'normal', 'uncommon', 'rare', 'epic', 'legendary'},

    -- 货币一（携带经验奖励 reward_for_exp）：epic、legendary 两档，都用平方根曲线、独立计算。
    --   epic 数量 = floor(√exp / 1)，最多 4 组(800)。
    --   legendary 数量 = floor(√exp / 10)，最多 1 组(200)。legendary 独立给（非 epic 溢出）。
    carry_rewards = {
        {quality = 'epic',      divisor = 1,  cap = 4 * 200},
        {quality = 'legendary', divisor = 10, cap = 1 * 200},
    },

    -- 在线奖励：在线行为统计 → 品质科技瓶（复活时发放，作为市场货币）。
    --   普通(normal)瓶子玩家可量产，会让初期量产瓶子刷货币，故奖励**只发四档品质瓶**：
    --   uncommon / rare / epic / legendary，绝不发 normal。
    --   数量 = floor(sqrt(stat) × reward_amount_mult)。
    -- ★ 可配置：每个在线统计发"哪种瓶子(pack) + 哪档品质(quality)"。只有 3 个在线统计，
    --   legendary 档默认留空（注释），你可以指定来源后启用。
    online_rewards = {
        {stat = 'online_minutes',  quality = 'uncommon',  pack = 'automation-science-pack', label = 'wn.coin-src-minutes'},
        {stat = 'online_research', quality = 'rare',      pack = 'logistic-science-pack',   label = 'wn.coin-src-research'},
        {stat = 'online_warps',    quality = 'epic',      pack = 'military-science-pack',   label = 'wn.coin-src-warps'},
        -- {stat = 'online_warps', quality = 'legendary', pack = 'production-science-pack', label = 'wn.coin-src-warps'},  -- legendary：自行指定来源/瓶子后启用
    },
    reward_amount_mult = 1,
}
