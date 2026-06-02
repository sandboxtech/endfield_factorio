-- 全局常量 + 默认值兜底。常量部分无副作用，可被任意模块 require；
-- ensure_defaults() 是唯一会写 storage 的函数（仅在 on_init / on_configuration_changed 调用）。
local M = {
    hour_to_tick = 216000,
    min_to_tick = 3600,
    MAX_LEVEL = 100000,   -- 最大等级 = 瓶等级封顶 = 职业 full 上限（单一来源；classes/gui/respawn_gifts 都引用它，改这一处即全改）

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
    -- 每种瓶 → 对应一个职业领域（决定该职业开局发什么物品）见 classes.lua。
    science_packs = {
        'automation-science-pack', 'logistic-science-pack', 'chemical-science-pack',
        'production-science-pack', 'utility-science-pack', 'space-science-pack',
        'metallurgic-science-pack', 'electromagnetic-science-pack', 'agricultural-science-pack',
        'cryogenic-science-pack', 'promethium-science-pack', 'military-science-pack',
    },

    -- 星球列表（多处共用：reset 清表/进化度、gui 前往/出生、travel 开放概率）。改这一处即全改，避免各处漂移。
    PLANETS = {'nauvis', 'vulcanus', 'gleba', 'fulgora', 'aquilo'},   -- 母星 + 4 外星（标准顺序）
    OFF_PLANETS = {'vulcanus', 'gleba', 'fulgora', 'aquilo'},         -- 仅外星（travel 开放概率、本轮可达判定用）
    -- 星球门槛：前往该星球 / 设其为出生星球，需对应科技瓶达 PLANET_REQ_LEVEL 级（否则按钮置灰）。母星(nauvis)无门槛。
    PLANET_PACK = {
        vulcanus = 'metallurgic-science-pack',      -- 火山 → 金属瓶
        gleba    = 'agricultural-science-pack',     -- 草星 → 农业瓶
        fulgora  = 'electromagnetic-science-pack',  -- 电浆星 → 电磁瓶
        aquilo   = 'cryogenic-science-pack',        -- 极地 → 低温瓶
    },
    PLANET_REQ_LEVEL = 10,            -- 星球门槛等级：对应科技瓶需达此级

    -- 跃迁计时相关的可调值【不在这里】，它们放进 storage（见 ensure_defaults），以便 /c 热改、持久、同步：
    --   storage.warp_initial_minutes / warp_extend_default_minutes / warp_extend_minutes[瓶] / warp_vote_target_minutes
    -- 常量表 M 里的值是模块级 Lua 数据，/c 改了不持久(读档复位)且多人会 desync，故跃迁可调值一律入 storage。

    -- 世界变体调参【一览表】：概率/权重的硬编码基数集中于此，方便统一调平衡。
    -- 纯表现性的内部曲线（染地 alpha 立方、noise threshold、亮度/昼夜抖动）留在 surface.lua 原地。
    balance = {
        -- 各变体【出现概率】（再乘动态乘数 storage.prob_xxx）
        ground_tint = {base = 0.1, exotic = 0.25},   -- 出现率 = base + exotic × knobs.exotic
        tile_remap  = {base = 0.6,  exotic = 0.3},    -- 出现率 = base + exotic × knobs.exotic
        -- 源天然自限（find 只命中该星球实际存在的障碍），目标跨类/跨星球 → 概率可放高，不会误伤。
        obstacle_remap = {base = 0.60},               -- 统一障碍互换世界出现率（树/石/遗迹/冰山/叠层岩跨类，噪声门控）
        fluid_remap    = {base = 0.24},               -- 流体资源互换世界出现率（原油/锂卤水/氟喷口/硫酸喷泉 整星换成另一种喷口，小概率）
        -- 出现率 = base；选中哪种事件按 weights 加权(缺省 1)，drones/tech 更低 → 无人机/科技世界更罕见
        event       = {base = 0.1, weights = {drones = 0.3, tech = 0.3}},
        -- tile 替换内部权重
        tile_mask_all      = 0.45,   -- mask 取 all(整片) 的概率，否则 noise/tree/rock/ore
        tile_to_exotic     = 0.3,    -- noise mask 下目标取 exotic(岩浆/油海/氨海/虚空) 的概率（全星统一，母星不额外加成）
        tile_to_artificial = 0.4,    -- ore mask 下目标取 artificial(人造铺装) 的概率
        tile_same_class    = 0.7,    -- 部分替换时目标保持同类(水↔水/地↔地) 的概率
        -- 母星/草星【宁和模式】抽奖：1/N 概率开启
        peaceful_one_in = 5,
    },
}

-- 给 storage 里的可调常量/必需表设默认值（仅当缺失时）。幂等 → on_init 与
-- on_configuration_changed 都可安全调用，老存档改版后迁移也能补齐新增字段。
-- 注意：warp_hours 等"每轮重置的运行时状态"不在此处，由 on_init / reset 负责。
function M.ensure_defaults()
    -- 重构清理（每次调用都跑，幂等）：删除已废弃的 storage 键，并修正类型已变更的键。
    -- on_init / on_configuration_changed / 每轮 reset 都会触发 → 老存档无需手动迁移，加载/跃迁即自愈。
    for _, k in ipairs({'radius', 'radius_of', 'tree_remap', 'prob_tree_remap', 'schema_version',
                        'prob_danger', 'danger_density', 'danger_theme', 'wreck_density',
                        'loot_density_outpost', 'loot_density_perp', 'encounter_perp', 'encounter_empty',
                        'enemy_death_push_minutes'}) do
        storage[k] = nil
    end
    -- travel_chance 曾是标量、现改为【按星球的表】；旧标量会让 tc[星球] 索引数字崩服 → 非表一律清掉，由下方按星球重建。
    if type(storage.travel_chance) ~= 'table' then storage.travel_chance = nil end
    -- 科技瓶经验改名+换刻度：旧 storage.science_exp(以"组"计) → 新 storage.exp(以"瓶"计；1 组 = 200 瓶，故 ×200)。
    -- 幂等：靠旧键 science_exp 是否存在；搬完置 nil，后续不再跑（故可常驻 ensure_defaults，不怕重复）。
    if storage.science_exp then
        storage.exp = storage.exp or {}
        for name, packs in pairs(storage.science_exp) do
            local d = storage.exp[name] or {}
            for pk, v in pairs(packs) do d[pk] = (d[pk] or 0) + v * 200 end
            storage.exp[name] = d
        end
        storage.science_exp = nil
    end
    -- enemy_autoplace_spread 拆成 freq/size 各自幅度：把旧统一键(含管理员 /c 改过的值)搬到两个新键，再删旧键。
    -- 必须在【下方补默认】之前做 → 迁移值优先于新默认 4。幂等：旧键删掉后不再触发，老存档加载即自愈。
    if storage.enemy_autoplace_spread ~= nil then
        storage.enemy_freq_spread = storage.enemy_freq_spread or storage.enemy_autoplace_spread
        storage.enemy_size_spread = storage.enemy_size_spread or storage.enemy_autoplace_spread
        storage.enemy_autoplace_spread = nil
    end
    -- enemy_respawn_ticks 改名 respawn_ticks_by_enemy：把旧值(含管理员 /c 改过的)搬到新键，再删旧键。
    -- 必须在【下方补默认】之前 → 迁移值优先于新默认。幂等：旧键删掉后不再触发，老档加载即自愈。
    if storage.enemy_respawn_ticks ~= nil then
        storage.respawn_ticks_by_enemy = storage.respawn_ticks_by_enemy or storage.enemy_respawn_ticks
        storage.enemy_respawn_ticks = nil
    end

    -- 标量默认（用 nil 判定，布尔 false/0 也能被正确保留）
    local d = {
        richness_multiplier = 8,          -- 矿更富（每格储量）· rail world：原 4 的 ×2
        size_multiplier = 4,              -- 矿脉更大 · rail world：原 1 的 ×4
        frequency_multiplier = 1,       
        local_specialty_multiplier = 0.25,
        radius_standard = 768,            -- 标准(基准)半径：每星球真实半径 = clamp(standard × random_exp(2), radius_min, radius_max)
        radius_min = 256,                 -- 真实半径下限
        radius_max = 1536,                -- 真实半径上限
        planet_eccentricity = 0.2,        -- 星球椭圆离心系数(原 0.35)：越小越圆，0=全圆。实际 ecc=(rand-rand)×此值，长短轴比最大 (1+e):(1-e)
        platform_lifetime = 10,
        difficulty = 1,
        debug = true,                     -- 向管理员打印每次世界生成的属性
        prob_ground_tint = 2,             -- 染地世界出现概率乘数（0=关）
        prob_tile_remap = 3,              -- tile 替换世界
        prob_obstacle_remap = 1,          -- 障碍换障碍世界（0=关）
        prob_fluid_remap = 1,             -- 流体资源互换世界（0=关）
        prob_event = 1,                   -- 事件世界出现概率乘数
        replicant_chance = 0.5,           -- 复制虫：玩家建筑被虫破坏时，按此概率原地冒新虫（全局，world_fx 开关另控）
        enemy_dmg_max = 12,               -- 敌人武器伤害上限倍率：每种伤害类型各自独立随机加成 [0, 此值]，线性递减分布（12=最高+1200%，越高越罕见）
        enemy_evo_max = 1,                -- 敌人进化度上限：每局随机 evo = min(1, 此值×(1-√r))，线性递减（>1 把分布推向高进化、更多猛虫；<1 压低上限）
        -- 战利品密度：全局乘数 × 各类乘数（相乘共同影响）。默认全 1，可 /c 单独热改：2 更多、0.5 更少、0 不刷。
        -- 遭遇出现率乘数：全局 × 各类（默认全 1，相乘）。基础频率见 map_features.ENCOUNTER_BASE；实际率还乘每世界 random² 密度。
        loot_density           = 0.5,        -- 全局总乘数（五类一起生效）
        loot_density_material  = 1,        -- 钢箱（材料）
        loot_density_equipment = 1,        -- 铁箱（设备）
        loot_density_treasure  = 1,        -- 木箱（宝箱）
        loot_density_perpetual = 1,        -- 永续箱遭遇
        loot_density_empty     = 1,        -- 空据点遭遇（纯敌人）
        chest_map_tags         = true,     -- 据点生成宝箱时，在中心打一个【该箱类型图标】的地图标签（无文本）。关：/c storage.chest_map_tags=false
        -- 永续箱（infinity-chest）三个属性，默认全 false=现状。/c storage.perpetual_xxx=true 开。
        perpetual_operable     = false,    -- 可打开 GUI/重配（默认否）
        perpetual_minable      = false,    -- 可手挖拆走（默认否）
        perpetual_destructible = false,    -- 可被摧毁（默认否；开了 fulgora 闪电/火炮会劈烂它）
        -- 据点战斗规则（map_features）：① 敌方炮塔击杀友军 → 给该据点炮塔补弹 + EEI 补电；② 据点炮塔全灭 → 连同 EEI+变电站一起摧毁。关：/c storage.outpost_combat=false
        outpost_combat         = true,
        event_chance = 0.5,               -- 每分钟【全服】发生一次世界事件的固定概率（与人数无关；命中后随机挑 1 名玩家）
        -- 科技世界(事件世界的一种)：每次从所有科技随机抽一个
        tech_world_lose_chance = 0.125,    -- 抽中【已研究】科技时，失去它的概率
        tech_world_gain_chance = 0.1,      -- 抽中【未研究】科技时，研究它的概率（调低：免费解锁科技更少）
        event_intensity = 1,              -- 每分钟事件的落点数
        tile_remap_rules = 6,             -- tile 替换世界最多几条规则
        -- 跃迁计时（全部可 /c storage.xxx 热改、持久、多人同步）：
        warp_initial_minutes = 30,        -- 每轮开局跃迁倒计时（分钟）
        warp_extend_default_minutes = 60, -- 完成未列入 warp_extend_minutes 的科技瓶科技 → 延长分钟数
        warp_vote_target_minutes = 5,     -- /warp 投票通过后，本世界倒计时直接设为剩余的分钟数（不杀玩家）
        -- 复活等待 tick（可 /c 热改）：脚本死亡(跃迁清场/离场/自杀)与环境死亡用 respawn_ticks；被敌方打死用 respawn_ticks_by_enemy。
        respawn_ticks = 600,              -- 默认复活：600 tick = 10 秒
        respawn_ticks_by_enemy = 1800,    -- 被敌方打死：1800 tick = 30 秒
        respawn_step_ticks = 300,         -- 跃迁致死：出生星球每远一个，复活多等的 tick（300 = 5 秒）
        warp_vote_divisor = 5,            -- 跃迁投票阈值除数：净同意 > ceil(在线人数/此值) 才推进（5=1/5，越大越易过）
        travel_enabled = true,           -- 前往星球【总开关】（默认开）。关闭：/c storage.travel_enabled=false。开启后每轮每个外星球还要各自过 travel_chance。
        action_cd_minutes = 3,            -- 投票+传送共享冷却（分钟），防止玩家频繁刷动作
        charge_max_hours = 30,            -- 星星充能上限（游戏内小时）：随游戏时间累积、封顶此值（1 星星=1 分钟=3600 tick；满充=30h=1800 星星）
        star_unlock_level = 20,           -- 显示【星星按钮及其窗口】所需的人物等级(=floor√在线分钟)；20 级≈在线 6.7 小时(400 分钟)，低于此不显示星星按钮
        vote_unlock_level = 10,           -- 显示【提前跃迁/停留投票】两个按钮所需的人物等级(=floor√在线分钟)；10 级=在线 100 分钟
        class_cd_minutes = 0.5,           -- 切换职业的冷却（分钟）：纯防刷消息，切换本就要下次跃迁才生效
        grant_trigger_techs = false,      -- 开局是否赠送所有【触发科技】（捕获虫巢/扔物入太空那类）。默认关；开：/c storage.grant_trigger_techs=true
        unlock_all_planets = true,        -- 开局是否自动解锁所有星球【传送点】（可前往，但不点亮 planet-discovery 发现科技）。关：/c storage.unlock_all_planets=false
        class_tech_stack = true,         -- 多个职业指向同一【无限科技】时：false=固定研究第一级(level=2,不累加)；true=每个职业各 +1 级(累加叠高)
        -- 敌方据点 / 网络限制 / 雷暴（map_features.lua / roboport_limit.lua / tick.lua 读取）
        enemy_invincible_chance = 1,      -- 敌方 substation/避雷针 无敌概率（1=全无敌，0=全可摧毁）
        enemy_freq_spread = 4,            -- 敌人巢穴 frequency 浮动幅度：对数三角分布，值域 [1/n, n]（默认 4=1/4~4），峰在 1。越大世界间虫【频率】差异越极端
        enemy_size_spread = 4,            -- 敌人巢穴 size 浮动幅度：同上（独立掷），控制世界间团块【大小】离散度
        enemy_freq_mul = 1,               -- 敌人巢穴 frequency 全局倍率：在 spread 浮动结果上再乘（>1 普遍更密、<1 更稀；与 spread 叠乘，值域变 [mul/n, mul×n]）
        enemy_size_mul = 1,               -- 敌人巢穴 size 全局倍率：在 spread 浮动结果上再乘（>1 团更大、<1 更小）

        roboport_limit = 10000,           -- 单个机器人网络最多 roboport 数，超出则摧毁刚放的并退还
        thunder_chance = 1 / 36000,       -- 雷暴星球每玩家每 tick 被闪电直击概率（期望约 10 分钟一次）
    }
    M.scalar_defaults = d   -- 暴露标量默认值（供 /config 命令对比当前 storage 与默认）
    for k, v in pairs(d) do
        if storage[k] == nil then storage[k] = v end
    end
    -- 各科技瓶【解锁延长跃迁的分钟数】。缺失才补 → 保留管理员 /c 的调整，并自动纳入将来新增的瓶。
    -- 热改示例：/c storage.warp_extend_minutes['cryogenic-science-pack'] = 90
    storage.warp_extend_minutes = storage.warp_extend_minutes or {}
    local warp_ext = {
        ['automation-science-pack'] = 30, ['logistic-science-pack'] = 60,
        ['military-science-pack'] = 60,   ['chemical-science-pack'] = 60,
        ['production-science-pack'] = 60, ['utility-science-pack'] = 60,
        ['space-science-pack'] = 60,     ['metallurgic-science-pack'] = 60,
        ['electromagnetic-science-pack'] = 60, ['agricultural-science-pack'] = 60,
        ['cryogenic-science-pack'] = 120, ['promethium-science-pack'] = 120,
    }
    for pack, m in pairs(warp_ext) do
        if storage.warp_extend_minutes[pack] == nil then storage.warp_extend_minutes[pack] = m end
    end
    -- 每个【外星球】单独的开放概率：每次跃迁各自掷一次决定本轮能否前往（"外星来人帮忙"）。默认 1.0（恒开）。
    -- 缺失才补 → 保留管理员 /c 的单独调整。热改示例：/c storage.travel_chance['fulgora'] = 0.6
    storage.travel_chance = storage.travel_chance or {}
    for _, p in ipairs(M.OFF_PLANETS) do
        if storage.travel_chance[p] == nil then storage.travel_chance[p] = 1.0 end
    end
    -- 开局额外【解锁的科技/配方】白名单（数组，默认空）：reset 每轮据此标记科技已研究 / 启用配方。
    -- 缺失才补空表 → 保留 /c 的填充。热改示例：/c storage.unlock_techs = {'logistics-2', 'steel-processing'}
    --                                          /c storage.unlock_recipes = {'rail', 'pistol'}
    storage.unlock_techs = storage.unlock_techs or {}
    storage.unlock_recipes = storage.unlock_recipes or {'iron-stick', 'steel-plate', 'ice-melting',
        'lubricant', 'concrete', 'refined-concrete',
        'solar-panel', 'accumulator',
        'medium-electric-pole', 'big-electric-pole'
    }
    -- 开局额外解锁的【品质】白名单（数组，默认四档全开）：reset 每轮对 force 调 unlock_quality，无需研发 quality 科技。
    -- 热改示例：/c storage.unlock_quality = {'uncommon', 'rare'}   清空：/c storage.unlock_quality = {}
    storage.unlock_quality = storage.unlock_quality or {'uncommon', 'rare', 'epic', 'legendary'}
    -- 必需表（累积数据 / 每星球状态 / 运行时缓存），缺失则建空表。
    -- 这是所有 storage 表的【唯一出生地】，各模块不再各自 `storage.x = storage.x or {}`，统一在此补齐。
    for _, key in ipairs({'width_of', 'height_of', 'shape_of', 'exp', 'player_stats', 'platform_age',
                          'ground_tint', 'tile_remap', 'event_world', 'loot_style', 'members',
                          'last_respawn_run', 'move_pos', 'bad_items', 'bad_entities', 'gen_debug', 'warp_vote',
                          'obstacle_remap', 'fluid_remap', 'last_leaderboard', 'market_run', 'respawn_surface', 'chat_bubble', 'enemy_floor', 'action_cd', 'travel_open', 'event_period_min', 'charge', 'star', 'player_class', 'class_cd', 'travel_cd', 'vote_cd'}) do
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
    local event_defaults = {raid = true, meteor = true, supply = true, coinfall = true, drones = true, barrage = true, tech = true}
    for et, on in pairs(event_defaults) do
        if storage.event_types[et] == nil then storage.event_types[et] = on end
    end
end

return M
