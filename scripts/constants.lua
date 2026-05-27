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
    -- 顺序 = 市场网格位置（3 列 × 4 行）。军事(灰瓶)放最后一格。
    science_packs = {
        'automation-science-pack', 'logistic-science-pack', 'chemical-science-pack',
        'production-science-pack', 'utility-science-pack', 'space-science-pack',
        'metallurgic-science-pack', 'electromagnetic-science-pack', 'agricultural-science-pack',
        'cryogenic-science-pack', 'promethium-science-pack', 'military-science-pack',
    },

    -- 货币一（携带经验奖励 reward_for_exp）：epic、legendary 两档，都用平方根曲线、独立计算。
    --   epic 数量 = floor(√exp / 1)，最多 4 组(800)。
    --   legendary 数量 = floor(√exp / 10)，最多 1 组(200)。legendary 独立给（非 epic 溢出）。
    carry_rewards = {
        {quality = 'epic',      divisor = 1,  cap = 4 * 200},
        {quality = 'legendary', divisor = 10, cap = 1 * 200},
    },

    -- 在线奖励（货币二）：在线/挂机时长 → 普通金币，复活（每局开始）时发放。
    --   数量 = floor(√online_minutes × reward_amount_mult)。
    --   更高品质金币（uncommon+）不在此发放——只能在普罗米修斯市场用普罗米修斯瓶兑换。
    online_coin_stat = 'online_minutes',
    online_coin_label = 'wn.coin-src-minutes',
    reward_amount_mult = 1,
}
