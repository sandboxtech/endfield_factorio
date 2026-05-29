-- 全局常量 + 默认值兜底。常量部分无副作用，可被任意模块 require；
-- ensure_defaults() 是唯一会写 storage 的函数（仅在 on_init / on_configuration_changed 调用）。
local M = {
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

    -- 12 种科技瓶：跃迁经验种类、奖励物资遍历顺序、角色面板显示顺序的唯一来源。
    -- 每种瓶 → 下次开局直接发的 2 种代表物资见 respawn_gifts.pack_gifts。
    science_packs = {
        'automation-science-pack', 'logistic-science-pack', 'chemical-science-pack',
        'production-science-pack', 'utility-science-pack', 'space-science-pack',
        'metallurgic-science-pack', 'electromagnetic-science-pack', 'agricultural-science-pack',
        'cryogenic-science-pack', 'promethium-science-pack', 'military-science-pack',
    },

    -- 跃迁计时相关的可调值【不在这里】——它们放进 storage（见 ensure_defaults），以便 /c 热改、持久、同步：
    --   storage.warp_initial_minutes / warp_extend_default_minutes / warp_extend_minutes[瓶] / warp_push_ticks / warp_push_respawn_ticks
    -- 常量表 M 里的值是模块级 Lua 数据，/c 改了不持久(读档复位)且多人会 desync，故跃迁可调值一律入 storage。

    -- 世界变体调参【一览表】：概率/权重的硬编码基数集中于此，方便统一调平衡。
    -- 纯表现性的内部曲线（染地 alpha 立方、noise threshold、亮度/昼夜抖动）留在 surface.lua 原地。
    balance = {
        -- 各变体【出现概率】（再乘动态乘数 storage.prob_xxx）
        ground_tint = {base = 0.06, exotic = 0.25},   -- 出现率 = base + exotic × knobs.exotic
        tile_remap  = {base = 0.5,  exotic = 0.4},    -- 出现率 = base + exotic × knobs.exotic
        -- 出现率 = base；选中哪种事件按 weights 加权(缺省 1)，drones 更低 → 无人机世界更罕见
        event       = {base = 0.1, weights = {drones = 0.3}},
        -- tile 替换内部权重
        tile_mask_all      = 0.45,   -- mask 取 all(整片) 的概率，否则 noise/tree/rock/ore
        tile_to_exotic     = 0.3,    -- noise mask 下目标取 exotic(岩浆/油海/虚空) 的概率
        tile_to_artificial = 0.4,    -- ore mask 下目标取 artificial(人造铺装) 的概率
        tile_same_class    = 0.7,    -- 部分替换时目标保持同类(水↔水/地↔地) 的概率
        -- 危险世界各敌人类型【独立开关】概率
        danger = {worm = 0.6, spawner = 0.4, turret = 0.4, mine = 0.4,
                  art_base = 0.12, art_danger = 0.3, replicant = 0.35},
        -- 母星/草星【宁和模式】抽奖：1/N 概率开启
        peaceful_one_in = 5,
    },
}

-- 给 storage 里的可调常量/必需表设默认值（仅当缺失时）。幂等 → on_init 与
-- on_configuration_changed 都可安全调用，老存档改版后迁移也能补齐新增字段。
-- 注意：warp_hours 等"每轮重置的运行时状态"不在此处，由 on_init / reset 负责。
function M.ensure_defaults()
    -- 标量默认（用 nil 判定，布尔 false/0 也能被正确保留）
    local d = {
        richness_multiplier = 8,          -- 矿更富（每格储量）· rail world：原 4 的 ×2
        size_multiplier = 4,              -- 矿脉更大 · rail world：原 1 的 ×4
        frequency_multiplier = 0.5,       -- 矿脉更稀疏 · rail world：原 1 的 ×1/2（少而大的矿，逼玩家修铁路）
        local_specialty_multiplier = 0.25,
        radius = 2048,
        radius_min = 256,
        radius_max = 4096,
        platform_lifetime = 10,
        difficulty = 1,
        debug = true,                     -- 向管理员打印每次世界生成的属性
        prob_ground_tint = 2,             -- 染地世界出现概率乘数（0=关）
        prob_tile_remap = 3,              -- tile 替换世界
        prob_danger = 1,                  -- 危险世界
        prob_event = 1,                   -- 每分钟事件世界
        danger_density = 1,               -- 危险世界里敌人/残骸的密度
        loot_density = 1,                  -- 战利品箱(物资/宝/永续)全局密度乘数：2 更多、0.5 更少
        event_intensity = 1,              -- 每分钟事件的落点数
        tile_remap_rules = 6,             -- tile 替换世界最多几条规则
        -- 跃迁计时（全部可 /c storage.xxx 热改、持久、多人同步）：
        warp_initial_minutes = 10,        -- 每轮开局跃迁倒计时（分钟）
        warp_extend_default_minutes = 60, -- 完成未列入 warp_extend_minutes 的科技瓶科技 → 延长分钟数
        warp_push_ticks = 3600,           -- /warp 主动跃迁每次把倒计时提前的 tick（3600 = 1 分钟）
        warp_push_respawn_ticks = 5400,   -- /warp 使用后本人复活等待 tick（5400 = 90 秒）
        -- 复活等待 tick（可 /c 热改）：脚本死亡(跃迁清场/离场/自杀)与环境死亡用 respawn_ticks；被敌方打死用 enemy_respawn_ticks。
        respawn_ticks = 180,              -- 默认复活：180 tick = 3 秒
        enemy_respawn_ticks = 1800,       -- 被敌方打死：1800 tick = 30 秒
        enemy_death_push_minutes = 1,     -- 被敌方打死时本轮跃迁倒计时提前的分钟数
    }
    for k, v in pairs(d) do
        if storage[k] == nil then storage[k] = v end
    end
    -- 各科技瓶【解锁延长跃迁的分钟数】。缺失才补 → 保留管理员 /c 的调整，并自动纳入将来新增的瓶。
    -- 热改示例：/c storage.warp_extend_minutes['cryogenic-science-pack'] = 90
    storage.warp_extend_minutes = storage.warp_extend_minutes or {}
    local warp_ext = {
        ['automation-science-pack'] = 20, ['logistic-science-pack'] = 30,
        ['military-science-pack'] = 60,   ['chemical-science-pack'] = 60,
        ['production-science-pack'] = 60, ['utility-science-pack'] = 60,
        ['space-science-pack'] = 60,      ['metallurgic-science-pack'] = 60,
        ['electromagnetic-science-pack'] = 60, ['agricultural-science-pack'] = 60,
        ['cryogenic-science-pack'] = 120, ['promethium-science-pack'] = 120,
    }
    for pack, m in pairs(warp_ext) do
        if storage.warp_extend_minutes[pack] == nil then storage.warp_extend_minutes[pack] = m end
    end
    -- 必需表（累积数据 / 每星球状态 / 运行时缓存），缺失则建空表。
    -- 这是所有 storage 表的【唯一出生地】——各模块不再各自 `storage.x = storage.x or {}`，统一在此补齐。
    for _, key in ipairs({'radius_of', 'science_exp', 'player_stats', 'platform_age',
                          'ground_tint', 'tile_remap', 'danger_theme', 'event_world', 'loot_style', 'members',
                          'last_respawn_run', 'move_pos', 'bad_items', 'gen_debug'}) do
        storage[key] = storage[key] or {}
    end
    -- world_fx 全局开关（默认开；/c storage.world_fx.xxx=false 单独禁用某事件驱动效果）。
    -- 加新 fx 时在此列表补上同名键，并在 world_fx.lua register 对应逻辑。
    storage.world_fx = storage.world_fx or {}
    for _, fx in ipairs({'replicant'}) do
        if storage.world_fx[fx] == nil then storage.world_fx[fx] = true end
    end
    -- 每分钟"事件世界"各类型开关（false=不再被滚到/触发）。运行时也可 /c storage.event_types.xxx=true/false。
    -- 下表的值即各类型的【初始启用状态】：coinfall(金币雨) 默认禁用，按需改 true/false。
    storage.event_types = storage.event_types or {}
    local event_defaults = {raid = true, meteor = true, supply = true, coinfall = true, drones = true, barrage = true}
    for et, on in pairs(event_defaults) do
        if storage.event_types[et] == nil then storage.event_types[et] = on end
    end
end

return M
