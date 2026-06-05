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

    -- 杀死虫巢掉落的科技瓶池（基础 6 瓶：含【军事】、不含 space 与各 SA 星球瓶）。独立于 science_packs，改这里不影响经验/面板。
    nest_science_packs = {
        'automation-science-pack', 'logistic-science-pack', 'military-science-pack',
        'chemical-science-pack', 'production-science-pack', 'utility-science-pack',
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
        fluid_remap    = {base = 0},                  -- 流体资源互换世界【已禁用】(原 0.24)：base=0 → 该世界变体永不触发(对所有存档即时生效)。恢复改回 0.24。
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
    -- （历史的一次性迁移代码——废弃键清理 / science_exp→exp 改名 / enemy_autoplace_spread 拆分 /
    --   enemy_respawn_ticks 改名 / travel_chance 类型修正——已删除：线上所有存档均已跑过新代码完成迁移。）

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
        edge_noise_start = 0.8,           -- 星球边界噪声起作用的归一化半径：小于它必为陆地(噪声权重 0)，向 1 线性升满 → 内侧不再有虚空噪声洞（调小=洞可更深入，0=旧行为；接近 1=近纯椭圆）
        spawn_offset_pow = 2,             -- 出生点偏离星球中心的非线性指数 B：归一化距离 = spawn_offset_max×random^B。越大越贴中心；1=线性；<1 偏向外缘
        spawn_offset_max = 0.5,           -- 出生点偏离星球中心的最大归一化距离（实际还会钳到 edge_noise_start−0.05 以内，保证出生必踩陆地）
        spawn_safe_frac = 0.3,            -- 出生安全盘半径 = 半短轴×此值：盘内【绝不】铺虚空（环礁/月牙/扭曲/噪声全部豁免，硬保证）
        -- 悬崖随机化（surface.random_cliff_mgs，nauvis/vulcanus/fulgora/gleba）：大概率正常微浮动，偏向简单。
        cliff_easy_chance = 0.35,         -- 【稀崖世界】概率：行距×1~3 + 连续度×0.2~1（缺口多更好走）。0=关
        cliff_hard_chance = 0.1,          -- 【密崖世界】概率：行距×0.6~1 + 连续度×1~1.15（温和上限）。0=关
        -- Vulcanus 巨虫领地（surface.random_territory_mgs）：三个概率互斥相加，其余=原版三档（从不更难）。
        demolisher_none_chance  = 0.15,   -- 全图无巨虫（领地全删）
        demolisher_small_chance = 0.2,    -- 全图只刷小型
        demolisher_mid_chance   = 0.15,   -- 只刷小型+中型
        min_territory_size = 120,         -- 领地门槛上限：每轮 minimum_territory_size 在 [10,此值] 均匀随机（原版恒 10；不足门槛区块数的领地被删 → 越高巨虫越稀）
        -- 昼夜随机化（surface.lua 每次世界生成执行，基线=各星原版值）：
        day_len_spread = 8,               -- 昼夜长短浮动界 A：ticks_per_day = 原版 × A^(t³)，t∈(-1,1) 均匀 → 大概率≈1×，小概率逼近 A 或 1/A（1=不浮动）
        day_shape_chance = 0.25,          -- 昼夜占比重塑概率：命中时白天占比在 20%~80% 随机（原版 50%），暮光对称收放；未命中回原版
        territory_cull_max = 0.5,         -- 领地删除率上限 A：每轮删除率 p = A×random^B，新领地生成时按 p 掷骰删除（连巨虫）。0=关
        territory_cull_pow = 2,           -- 领地删除率指数 B：越大 p 越偏 0（大概率几乎不删、小概率删近 A）
        platform_lifetime = 30,
        difficulty = 1,
        debug = true,                     -- 向管理员打印每次世界生成的属性
        prob_ground_tint = 2,             -- 染地世界出现概率乘数（0=关）
        prob_tile_remap = 3,              -- tile 替换世界
        prob_obstacle_remap = 1,          -- 障碍换障碍世界（0=关）
        prob_fluid_remap = 1,             -- 流体资源互换世界（0=关）
        replicant_chance = 0.5,           -- 复制虫：玩家建筑被虫破坏时，按此概率原地冒新虫（全局，world_fx 开关另控）
        nest_coin = 6,                    -- 杀死虫巢掉落的金币数（开关：0=不掉金币）。可 /c storage.nest_coin=N 热改
        -- 玩家方杀虫巢触发"获得随机科技"的概率：每轮 reset 在 [min,max] 内随机滚定本世界值（存 storage.nest_tech_chance）。
        nest_tech_chance_min = 0.001,     -- 下限（0.1%）。两值设相等=固定概率；都设 0=关闭
        nest_tech_chance_max = 0.01,      -- 上限（1%）
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
        loot_density_machine   = 1,        -- 传说生产建筑据点（机器三锁、必带敌方电网核心）
        chest_count_pow        = 2,        -- 据点奖励箱【数量】公式 floor(1+4·random^此值·riches) 的指数：越大越偏向少箱（1=接近均匀，2=默认，6=极偏 1 箱）
        chest_map_tags         = true,     -- 据点生成宝箱时，在中心打一个【该箱类型图标】的地图标签（无文本）。关：/c storage.chest_map_tags=false
        -- 永续箱（infinity-chest）三个属性，默认全 false=现状。/c storage.perpetual_xxx=true 开。
        perpetual_operable     = false,    -- 可打开 GUI/重配（默认否）
        perpetual_minable      = false,    -- 可手挖拆走（默认否）
        perpetual_destructible = false,    -- 可被摧毁（默认否；开了 fulgora 闪电/火炮会劈烂它）
        -- 据点战斗规则（map_features）：① 敌方炮塔击杀友军 → 给该据点炮塔补弹 + EEI 补电；② 据点炮塔全灭 → 连同 EEI+变电站一起摧毁。关：/c storage.outpost_combat=false
        outpost_combat         = true,
        outpost_pave_prob      = 0.5,      -- 据点【强制铺地】概率：命中的据点，箱/守卫/变电站放不下时先铺对应地砖再硬放（水/熔岩/虚空旁不再缺斤短两）。0=关，1=全部强制
        -- 世界荣誉榜（reset 跃迁结算记录、功能菜单查看）：
        hall_of_fame_enabled   = true,     -- 总开关：false=不再记录新世界、功能菜单隐藏荣誉榜按钮（已有记录保留不删）
        hall_of_fame_max       = 30,       -- 最大保留条数（按全员带走经验排序，超出裁掉队尾）
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
        -- 星星消费（投跃迁/停留票、买延长）：均在【星星窗口】里花。可 /c 热改。
        star_vote_cost = 100,             -- 投一次跃迁/停留票花的星星数
        star_extend_cost = 100,           -- 花星星给本世界倒计时延长一次的星星数
        star_extend_minutes = 10,         -- 每次延长加的分钟
        star_extend_cap = 60,             -- 每星系（run）花星星延长的累计上限（分钟），达到后按钮禁用
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
        platform_warp_mode = 'stay',      -- 跃迁时飞船去向：'stay'=停留原地继续跑；'home'=瞬移回母星轨道并暂停；'random'=各自随机挑一个星球轨道停靠并暂停
        chat_bubble_enabled = false,      -- 玩家聊天头顶冒对话气泡（默认关）。开：/c storage.chat_bubble_enabled=true
        player_cleanup_hours = 32,        -- 跃迁时清理多少小时没上线的玩家对象（释放蓝图/快捷键等存档膨胀；经验/统计按名字存，不丢）
        kill_on_leave = true,             -- 玩家离线时杀死其角色（尸体/货物留当地，防外星捡货下线带回）。false=离线保留角色与背包
        blueprint_warps = 1,              -- 解锁蓝图库/导入/红图所需的跃迁次数（0=进服即解锁；会员/管理员恒解锁不看此值）
    }
    M.scalar_defaults = d   -- 暴露标量默认值（供 /config 命令对比当前 storage 与默认）
    for k, v in pairs(d) do
        if storage[k] == nil then storage[k] = v end
    end
    -- 据点【箱子遭遇】出现率的每星球乘数（material/equipment/treasure/perpetual 四类一起乘，【不含】空据点）。
    -- 热改示例：/c storage.loot_planet_mul.gleba = 5
    storage.loot_planet_mul = storage.loot_planet_mul or {nauvis = 1, vulcanus = 1, fulgora = 3, gleba = 3, aquilo = 3}
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
    storage.unlock_techs = storage.unlock_techs or {
        -- 'oil-processing', 'uranium-processing', 'biter-egg-handling',
        -- 'planet-discovery-vulcanus', 'planet-discovery-gleba',
        -- 'planet-discovery-fulgora', 'planet-discovery-aquilo',
        'epic-quality', 'legendary-quality',
    }
    storage.unlock_recipes = storage.unlock_recipes or {
        'iron-stick', 'steel-plate', 'ice-melting',
        'solar-panel', 'accumulator',
        'concrete', 'refined-concrete',
        'lubricant', 'light-oil-cracking', 'heavy-oil-cracking',
    }

    -- 开局额外解锁的【品质】白名单（数组，默认四档全开）：reset 每轮对 force 调 unlock_quality，无需研发 quality 科技。
    -- 热改示例：/c storage.unlock_quality = {'uncommon', 'rare'}   清空：/c storage.unlock_quality = {}
    storage.unlock_quality = storage.unlock_quality or {'uncommon', 'rare', 'epic', 'legendary'}
    -- 研究【连带自动解锁】映射 {源科技 = 目标科技}：研完源科技 → research.lua 自动把目标科技标记已研究。
    -- 缺失才补 → 保留 /c 的增删。热改示例：/c storage.auto_research['kovarex-enrichment-process'] = 'nuclear-fuel-reprocessing'
    storage.auto_research = storage.auto_research or {
        ['uranium-mining'] = 'uranium-processing',     -- 铀矿采集 → 铀矿加工
        ['oil-gathering']  = 'oil-processing',         -- 原油采集 → 原油加工
        ['captivity']      = 'biter-egg-handling',     -- 捕获 → 虫卵处理（SA）
    }
    -- 【无限产能科技经验】集合 {科技名 = true}：研究完这些【真·无限】科技时，每完成一级给【全体在线玩家】
    --   各 +1 经验，存进 storage.exp[玩家名][科技名]（与科技瓶经验同一张表、不同键，故不污染 12 瓶面板）。
    --   研究产能越高、刷得越快 → 这类经验涨得越多（挂机大师等高产能职业受益）。缺失才补 → 保留 /c 增删。
    --   热改：/c storage.prod_exp_techs['steel-plate-productivity'] = true   删：…= nil
    storage.prod_exp_techs = storage.prod_exp_techs or {
        ['research-productivity']             = true,
        ['mining-productivity-3']             = true,
        ['asteroid-productivity']             = true,
        ['low-density-structure-productivity'] = true,
        ['plastic-bar-productivity']          = true,
        ['processing-unit-productivity']      = true,
        ['rocket-fuel-productivity']          = true,
        ['rocket-part-productivity']          = true,
        ['scrap-recycling-productivity']      = true,
        ['steel-plate-productivity']          = true,
        -- 武器【伤害】无限科技（射程/射速类不计入；要加自行 /c）：
        ['physical-projectile-damage-7']      = true,   -- 实弹
        ['laser-weapons-damage-7']            = true,   -- 激光
        ['electric-weapons-damage-4']         = true,   -- 电磁/特斯拉
        ['stronger-explosives-7']             = true,   -- 爆炸物
        ['refined-flammables-7']              = true,   -- 火焰
        ['artillery-shell-damage-1']          = true,   -- 火炮弹
        ['railgun-damage-1']                  = true,   -- 电磁炮
    }
    -- 必需表（累积数据 / 每星球状态 / 运行时缓存），缺失则建空表。
    -- 这是所有 storage 表的【唯一出生地】，各模块不再各自 `storage.x = storage.x or {}`，统一在此补齐。
    for _, key in ipairs({'width_of', 'height_of', 'shape_of', 'exp', 'player_stats', 'platform_age',
                          'ground_tint', 'tile_remap', 'loot_style', 'members',
                          'last_respawn_run', 'move_pos', 'bad_items', 'bad_entities', 'gen_debug', 'warp_vote', 'warp_vote_cost',
                          'obstacle_remap', 'fluid_remap', 'last_leaderboard', 'market_run', 'respawn_surface', 'chat_bubble', 'enemy_floor', 'action_cd', 'travel_open', 'charge', 'star', 'player_class', 'player_class_current', 'class_cd', 'travel_cd', 'vote_cd', 'session_join',
                          -- 补登记（原先散落在各模块 or {} 自建；标量和有专属 ensure 的键不在此列——classes/loot/loot_weights/market_prices 由各自 ensure 用 `or` 初始化，先建空表会让它们永不填充）：
                          'enemy_floor2', 'outposts', 'outpost_of', 'pending_chest_tags', 'bad_loot_cats', 'respawn_home', 'class_names',
                          'hall_of_fame', 'base_ticks_per_day', 'base_daytime_params', 'territory_cull', 'loot_noise'}) do
        storage[key] = storage[key] or {}
    end
    -- world_fx 全局开关（默认开；/c storage.world_fx.xxx=false 单独禁用某事件驱动效果）。
    -- 加新 fx 时在此列表补上同名键，并在 world_fx.lua register 对应逻辑。
    storage.world_fx = storage.world_fx or {}
    for _, fx in ipairs({'replicant'}) do
        if storage.world_fx[fx] == nil then storage.world_fx[fx] = true end
    end
end

return M
