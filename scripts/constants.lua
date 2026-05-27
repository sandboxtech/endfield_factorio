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

    -- 品质由低到高。货币（实物科技瓶）随累计经验逐级解锁更高品质。
    quality_order = {'normal', 'uncommon', 'rare', 'epic', 'legendary'},

    -- 每品质的"成本倍率"：第 q 品质的第 k 瓶奖励需要 cost_mult[q] × k 经验。
    -- 因此填满某品质 1 组(200)需要 cost_mult[q] × (1+2+...+200) = cost_mult[q] × 20100 经验。
    quality_cost_mult = {
        normal    = 1,
        uncommon  = 10,
        rare      = 100,
        epic      = 1000,
        legendary = 10000,
    },

    -- 每瓶每品质最多奖励 1 组 = 200。5 品质 × 12 瓶 = 60 组上限。
    reward_quality_cap = 200,

    -- 金币（第二货币，用于装备市场）。品质由在线行为来源决定，数量按 √统计 给出。
    --   只看"是否在线"，不看是否挂机，避免反向鼓励在线挂机。
    --   在线分钟 → normal 金币；在线研究科技 → uncommon 金币；在线跃迁次数 → rare 金币。
    coin_sources = {
        {stat = 'online_minutes',  quality = 'normal',   label = 'wn.coin-src-minutes'},
        {stat = 'online_research', quality = 'uncommon', label = 'wn.coin-src-research'},
        {stat = 'online_warps',    quality = 'rare',     label = 'wn.coin-src-warps'},
    },
    -- 金币数量 = floor(sqrt(stat) × coin_curve_mult)。
    coin_curve_mult = 1,
}
