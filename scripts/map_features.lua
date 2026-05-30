-- 地图风味（原则：用噪声【修改 2.0 原生生成】，不用手动 stamp 去【覆盖】，原生地貌更自然）。
-- 因此本模块只做原生【做不到】的事；地貌(石/树/矿/水…)交回原生，由 surface.lua 用气候偏置/autoplace 调本轮风味。
--   · M.knobs()：本轮整局气质连续旋钮(繁茂/岩石/危险/富庶/异物)，与 surface.lua 共用 → 全局气质一致渐变。
--   · PLANET：目前空（手动放矿/废料表现不如原生，全交原生）；EXOTIC：跨星异物(原生无法跨星)，稀疏散布。
--   · 每特征从种子(storage.run+off)派生 strength：~60% 不出现，出现时立方偏置(多半小、极少大)。
--   · 树木主题 theme_trees：对【原生树】按本轮强度从原版色插值到目标色(连续，非离散世界) → 改原生，不覆盖。
--   · 通用风味：worm 虫群(force='enemy',仅母星)、随机木/铁/钢战利品箱(force='player',加权+品质)。
-- 由 surface.lua 的 on_chunk_generated 对各真实星球圆内区块调用 M.generate。
local noise = require('scripts.noise')
local constants = require('scripts.constants')

local M = {}

local function wseed(off) return (storage.run or 0) * 1009 + off end

-- 本轮【整局气质】连续旋钮（由 storage.run 确定性派生）：每个都是 [0,1) 连续量，不是硬编码离散概率，-- 每轮整体氛围（繁茂↔荒芜、危险↔安宁、富庶↔贫瘠、寻常↔诡异）都是渐变的。
-- 同时供 surface.lua 调【2.0 原生 autoplace】(树/石密度) 与本模块手动特征门控共用 → 全局气质一致。
--   verdancy 植被繁茂  rockiness 岩石  danger 虫群危险(偏低)  riches 战利品(偏低)  exotic 异物倾向(很罕见)
-- 按 run 号缓存：knobs() 会被【每个区块】调用，但结果整轮恒定（纯派生自 storage.run）。
-- 算一次即可，省下每区块 ~10 次 sin。多人各端/存档重载都会算出同值 → 缓存对确定性无影响。
local knobs_cache, knobs_cache_run
function M.knobs()
    local run = storage.run or 0
    if knobs_cache and knobs_cache_run == run then return knobs_cache end
    local function k(off, power)
        local v = noise.hash01(wseed(off) * 6.1)
        return power and v ^ power or v
    end
    -- 中心化：两个独立哈希之差 → 三角分布、集中在 0.5。多半接近原版，极端(极干极湿/极秃极茂)很罕见。
    local function kc(off)
        return 0.5 + (noise.hash01(wseed(off) * 6.1) - noise.hash01(wseed(off) * 3.7)) * 0.5
    end
    local exotic = k(809, 3)   -- 跨星球异物倾向（立方偏置，诡异世界很罕见）
    knobs_cache = {
        verdancy  = kc(801),      -- 树/草繁茂度（中心化：多半正常，极干/极茂罕见）
        rockiness = kc(803),      -- 岩石密度（中心化）
        riches    = k(807, 1.6),  -- 战利品丰度倾向（仅打印给管理员参考；箱子密度已改由 loot_style 三类独立 random^2 决定）
        exotic    = exotic,
        -- 危险度：曲线偏低 + 与异物倾向【正相关】（诡异世界往往也更危险）。
        danger    = math.min(1, k(805, 2) * 0.7 + exotic * 0.7),
    }
    knobs_cache_run = run
    return knobs_cache
end

-- 本轮【全局共享】的噪声变换(朝向/拉伸/缩放)同样整轮恒定，按 run 缓存，也被每区块调用。
local xform_cache, xform_cache_run
local function run_transform()
    local run = storage.run or 0
    if xform_cache and xform_cache_run == run then
        return xform_cache[1], xform_cache[2], xform_cache[3]
    end
    local a, s, z = noise.seeded_transform(wseed(7))
    xform_cache, xform_cache_run = {a, s, z}, run
    return a, s, z
end

-- 本轮该特征强度：~60% 为 0(不出现)；出现时走【立方偏置】，绝大多数小规模、极小概率大规模。
-- （r³ 把均匀随机压向 0：r=0.5→0.125、0.8→0.51、0.95→0.86，所以大规模很罕见。）
local function strength(off)
    if noise.hash01(wseed(off) * 7.3) < 0.60 then return 0 end
    local r = noise.hash01(wseed(off) * 3.1)
    return 0.1 + r * r * r * 0.9
end

-- 通用放置：def = {name, off, amount={lo,hi}(资源才填), density(0~1, 默认1), threshold(默认0.72),
--   force(默认player), rare(true=异星物，额外加一道小概率门)}
-- A/S/Z = 本轮【全局共享】的朝向/拉伸/缩放（所有特征一致，不互相打架）；def.off 决定各自的噪声场(位置不同)。
-- 两条路径：① 资源(def.amount) 需连续成片 → 逐格按噪声填；② 普通实体(稀疏) → 不逐格，而是【随机采样】
--   若干位置、命中噪声区才放（性能远好于 1024 格逐格判噪声）。
local function place_feature(surface, lt, def, A, S, Z, W)
    -- 异星物出现概率随【本轮异物倾向】连续变化（不再硬编码 15%）：寻常世界几乎没有，诡异世界才多。
    if def.rare and noise.hash01(wseed(def.off) * 9.9) > 0.03 + 0.5 * (W and W.exotic or 0) then return end
    local s = strength(def.off)
    if s == 0 then return end
    local fseed = wseed(def.off)
    -- 阈值高→覆盖小；s 多半很小(立方曲线)→大多数是小斑块，极少 s 大才铺成片
    local threshold = (def.threshold or 0.72) - s * 0.32

    if def.amount then
        -- 资源：逐格按噪声填（需要连续矿块）。
        for x = 0, 31 do
            for y = 0, 31 do
                local px, py = lt.x + x, lt.y + y
                if noise.fractal_warped(noise.octaves.scrap, px, py, fseed, A, S, Z) > threshold then
                    local pos = {x = px + 0.5, y = py + 0.5}
                    if surface.can_place_entity{name = def.name, position = pos} then
                        local rn = (noise.fractal(noise.octaves.scrap, px, py, fseed + 50000) + 1) * 0.5
                        surface.create_entity{name = def.name, force = def.force or 'player', position = pos,
                            amount = math.max(50, math.floor((def.amount[1] + (def.amount[2] - def.amount[1]) * rn) * (0.5 + s)))}
                    end
                end
            end
        end
    else
        -- 普通实体：随机采样 N 个位置，命中噪声区才放（N 随 density+本轮强度，几个而已）。
        local samples = math.random(0, math.ceil((def.density or 0.3) * 30 * (0.4 + s)))
        for _ = 1, samples do
            local px, py = lt.x + math.random(0, 31), lt.y + math.random(0, 31)
            if noise.fractal_warped(noise.octaves.scrap, px, py, fseed, A, S, Z) > threshold then
                local pos = {x = px + 0.5, y = py + 0.5}
                if surface.can_place_entity{name = def.name, position = pos} then
                    surface.create_entity{name = def.name, force = def.force or 'player', position = pos}
                end
            end
        end
    end
end

-- 手动放置的本地特色：目前为空。
--   矿/石/树/水/废料等手动 stamp 表现大多不如原生（连母星 scrap 也移除了）→ 全部交回 2.0 原生，
--   由 surface.lua 用「气候偏置 + autoplace」按本轮气质调风味（修改原生，而非覆盖）。
--   若以后要放"原生绝对没有"的本地特产，再在此按 {name, off, amount/density, threshold} 添加。
local PLANET = {}

-- 跨星球异物：原生 autoplace 无法把 A 星之物长到 B 星，这点"违和惊喜"只能手动。
-- 全 rare + 低密度高阈值 → 仅零星几个散布(不成片)；出现概率随【异物倾向】渐变。仅保留实体型(树/石/遗迹/冰山)，
-- 不放废料矿(手动废料表现差)。
local EXOTIC = {
    {name = 'ashland-lichen-tree', off = 313, rare = true, density = 0.06, threshold = 0.84},
    {name = 'fulgoran-ruin-small', off = 317, rare = true, density = 0.05, threshold = 0.86},
    {name = 'lithium-iceberg-big', off = 319, rare = true, density = 0.05, threshold = 0.86},
    {name = 'huge-volcanic-rock', off = 321, rare = true, density = 0.06, threshold = 0.86},
}

-- 战利品池：手动穷举的全物品名单（从游戏数据导出，不在运行时枚举 prototypes），按【类】分组。
-- 不再带全局权重 w，每种箱子用各自的【类权重表】(见 LOOT_WEIGHTS)抽取，掉落构成因箱而异。
local LOOT = {
    -- 原料/矿
    {cat = 'raw',        items = {
        'iron-ore',  'copper-ore',  'uranium-ore',  'tungsten-ore',  'holmium-ore',   -- 金属矿
        'coal',  'stone',  'calcite',  'lithium',                                      -- 非金属/化工矿
        'scrap',  'carbon',  'wood',  'raw-fish',  'ice',  'spoilage',                          -- 其它原料（spoilage 不腐烂、可作化学燃料）
        -- 'carbonic-asteroid-chunk', 'metallic-asteroid-chunk',  'oxide-asteroid-chunk',  'promethium-asteroid-chunk',
    }},
    -- 材料/中间品
    {cat = 'material',   items = {
        'iron-plate',  'copper-plate',  'steel-plate',  'plastic-bar',  'stone-brick',  -- 基础板材
        'iron-gear-wheel',  'copper-cable',  'iron-stick',  'engine-unit',  'electric-engine-unit',  -- 基础中间件
        'electronic-circuit',  'advanced-circuit',  'processing-unit',  'quantum-processor',  -- 电路
        'flying-robot-frame',  'low-density-structure',  'battery',  'explosives',  'sulfur',  -- 高级中间件
        'rocket-fuel',  'solid-fuel',  'nuclear-fuel',                                -- 燃料
        'uranium-235',  'uranium-238',  'uranium-fuel-cell',  'depleted-uranium-fuel-cell',  'fusion-power-cell',  -- 核
        'tungsten-carbide',  'tungsten-plate',  'holmium-plate',  'lithium-plate',  'carbon-fiber',  'superconductor',  'supercapacitor',  -- 星球特产材料
        'concrete',  'refined-concrete',  'hazard-concrete',  'refined-hazard-concrete',  'landfill',  -- 铺地
        'barrel', 'water-barrel', 'crude-oil-barrel',  'heavy-oil-barrel',  'light-oil-barrel',  'petroleum-gas-barrel',
        'lubricant-barrel',  'sulfuric-acid-barrel', 'fluoroketone-hot-barrel', 'fluoroketone-cold-barrel',                                                                       -- 桶装液体（仅这 9 种有桶：base 7 种 + 草星 fluoroketone 冷热 2 种；lava/氨/molten 等 auto_barrel=false 无桶）
    }},
    -- 物流(带/臂/管/箱/轨/机器人)
    {cat = 'logistics',  items = {
        'transport-belt',  'fast-transport-belt',  'express-transport-belt',  'turbo-transport-belt',  -- 传送带
        'underground-belt',  'fast-underground-belt',  'express-underground-belt',  'turbo-underground-belt',  -- 地下带
        'splitter',  'fast-splitter',  'express-splitter',  'turbo-splitter',           -- 分流器
        'loader',  'fast-loader',  'express-loader', 'turbo-loader',                                   -- 装卸器
        'inserter',  'burner-inserter',  'long-handed-inserter',  'fast-inserter',  'bulk-inserter',  'stack-inserter',  -- 机械臂
        'pipe',  'pipe-to-ground',  'pump',  'offshore-pump',  'storage-tank',          -- 管道/流体
        'wooden-chest',  'iron-chest',  'steel-chest',  'active-provider-chest',  'passive-provider-chest',  'storage-chest',  'buffer-chest',  'requester-chest',  -- 箱
        'construction-robot',  'logistic-robot',  'roboport',  'repair-pack',            -- 机器人
        'rail',  'rail-signal',  'rail-chain-signal',  'rail-ramp',  'rail-support',  'train-stop',  'locomotive',  'cargo-wagon',  'fluid-wagon',  -- 铁路
    }},
    -- 电路信号
    {cat = 'circuit',    items = {
        'arithmetic-combinator',  'decider-combinator',  'constant-combinator',  'selector-combinator',  -- 组合器
        'programmable-speaker',  'display-panel',  'small-lamp',                         -- 信号输出
    }},
    -- 电力(发电/蓄电/电杆/热)
    {cat = 'power',      items = {
        'boiler',  'steam-engine',  'steam-turbine',  'heat-exchanger',  'heat-pipe',  'heating-tower',  -- 蒸汽/热
        'nuclear-reactor',  'fusion-reactor',  'fusion-generator',                      -- 核/聚变
        'solar-panel',  'accumulator',                                                  -- 太阳能/蓄电
        'lightning-collector',  'lightning-rod',                                        -- 雷电(Fulgora)
        'power-switch',  'small-electric-pole',  'medium-electric-pole',  'big-electric-pole',  'substation',  -- 电杆/开关
    }},
    -- 生产机器
    {cat = 'production', items = {
        'assembling-machine-1',  'assembling-machine-2',  'assembling-machine-3',      -- 组装机
        'stone-furnace',  'steel-furnace',  'electric-furnace',                         -- 熔炉
        'burner-mining-drill',  'electric-mining-drill',  'big-mining-drill',  'pumpjack',  -- 采矿
        'oil-refinery',  'chemical-plant',  'centrifuge',  'crusher',                   -- 化工/处理
        'lab',  'biolab',  'beacon',                                                    -- 实验室/信标
        'foundry',  'recycler',  'electromagnetic-plant',  'cryogenic-plant',  'biochamber',  'agricultural-tower',  -- 星球特产机器
        'rocket-silo',                                                                  -- 火箭发射井
    }},
    -- 模块
    {cat = 'module',     items = {
        'speed-module',  'speed-module-2',  'speed-module-3',                           -- 速度
        'efficiency-module',  'efficiency-module-2',  'efficiency-module-3',            -- 节能
        'productivity-module',  'productivity-module-2',  'productivity-module-3',      -- 产能
        'quality-module',  'quality-module-2',  'quality-module-3',                     -- 品质
    }},
    -- 军事(炮塔/枪/弹/胶囊/墙)
    {cat = 'military',   items = {
        'gun-turret',  'laser-turret',  'flamethrower-turret',  'artillery-turret',  'rocket-turret',  'railgun-turret',  'tesla-turret',  'artillery-wagon',  -- 炮塔/火炮车
        'stone-wall',  'gate',  'radar',  'land-mine',                                  -- 防御工事
        'pistol',  'submachine-gun',  'shotgun',  'combat-shotgun',  'flamethrower',  'rocket-launcher',  'railgun',  'teslagun',  -- 武器
        'firearm-magazine',  'piercing-rounds-magazine',  'uranium-rounds-magazine',  'shotgun-shell',  'piercing-shotgun-shell',  -- 枪弹
        'cannon-shell',  'explosive-cannon-shell',  'uranium-cannon-shell',  'explosive-uranium-cannon-shell',  -- 炮弹
        'rocket',  'explosive-rocket',  'flamethrower-ammo',  'artillery-shell',  'railgun-ammo',  'tesla-ammo',  'atomic-bomb',  -- 弹药/导弹
        'grenade',  'cluster-grenade',  'poison-capsule',  'slowdown-capsule',  'defender-capsule',  'distractor-capsule',  'destroyer-capsule',  'capture-robot-rocket',  -- 投掷/胶囊
        'cliff-explosives',  'discharge-defense-remote',  'artillery-targeting-remote',  -- 工具/遥控
    }},
    -- 护甲与装备
    -- 护甲与装备（含重型载具）
    {cat = 'equipment',  items = {
        'light-armor',  'heavy-armor',  'modular-armor',  'power-armor',  'power-armor-mk2',  'mech-armor',  -- 护甲
        'solar-panel-equipment',  'fission-reactor-equipment',  'fusion-reactor-equipment',  'battery-equipment',  'battery-mk2-equipment',  'battery-mk3-equipment',  -- 能源/蓄电装备
        'energy-shield-equipment',  'energy-shield-mk2-equipment',  'personal-laser-defense-equipment',  'discharge-defense-equipment',  -- 护盾/防御装备
        'exoskeleton-equipment',  'personal-roboport-equipment',  'personal-roboport-mk2-equipment',  'belt-immunity-equipment',  'night-vision-equipment',  'toolbelt-equipment',  -- 功能装备
        'spidertron',  'tank',  'car',                                                        -- 重型载具
    }},
    -- 科技瓶(永续箱不出)
    {cat = 'science',    items = {   -- 已删可腐的 agricultural-science-pack
        'automation-science-pack',  'logistic-science-pack',  'military-science-pack',  'chemical-science-pack',  -- 基础四瓶(红绿黑蓝)
        'production-science-pack',  'utility-science-pack',  'space-science-pack',      -- 紫/黄/白
        'metallurgic-science-pack',  'electromagnetic-science-pack',  'cryogenic-science-pack',  'promethium-science-pack',  -- 星球科技瓶
    }},
    -- 生物/农业（已删蛋与一切可腐物，只留不腐烂的种子/土壤）
    {cat = 'gleba',      items = {
        'jellynut-seed',  'yumako-seed',  'tree-seed',                                  -- 种子
        'artificial-jellynut-soil',  'artificial-yumako-soil',  'overgrowth-jellynut-soil',  'overgrowth-yumako-soil',  -- 土壤
    }},
    -- 太空/平台
    {cat = 'space',      items = {
        'space-platform-starter-pack', 'rocket-part',                                 -- 平台起步包
        'foundation',  'space-platform-foundation',  'ice-platform',                   -- 平台地基
        'cargo-bay',  'cargo-landing-pad',  'asteroid-collector',  'thruster',          -- 平台部件
    }},
}

-- 各【按外观区分】的箱子对 LOOT 各【类】的权重：先按权重选类、再类内等概率选物品。
-- 每表都【列全所有类】(顺序同 LOOT)，不要的标 0 方便手调，0 与省略等价，不影响运算。
-- 木箱(宝箱)走单独精选池 TREASURE_POOL，不在这里。
local LOOT_WEIGHTS = {
    -- 钢箱 = 材料箱：基础材料/原料 + 大概率普通科技瓶。普通品质、常见、装得多。
    material = {
        raw = 25, material = 60, logistics = 10,  circuit = 1,  power = 1,
        production = 0,  module = 2,  military = 1,  equipment = 1,  science = 3,
        gleba = 1,  space = 1,
    },
    -- 铁箱 = 设备箱：实用设备/机器为主，含载具/太空件，少量科技瓶。普通品质、中等数量。
    equipment = {
        raw = 1,  material = 5,  logistics = 35,  circuit = 8,  power = 14,
        production = 30,  module = 15,  military = 12,  equipment = 10,  science = 10,
        gleba = 4,  space = 15,
    },
    -- 永续(无底)箱：基础材料/矿物为主。注意 science>0 = 无限科技瓶(很强，慎调)。
    perp = {
        raw = 90,  material = 120,  logistics = 15,  circuit = 1,  power = 5,
        production = 3,  module = 5,  military = 1,  equipment = 1,  science = 0,
        gleba = 1,  space = 1,
    },
}

-- 木箱(宝箱)精选池：每箱 1~2 件高品质高价值物品。只放【玩家初始奖励(respawn_gifts.pack_gifts)里
-- 没有的】顶级物品，顶级插件(3级，初始奖励只给基础级) + rocket-silo。
-- foundry/electromagnetic-plant/biochamber/cryogenic-plant/recycler/big-mining-drill 已作为初始
-- 奖励发放，宝箱再给等于重复 → 移除。不放科技瓶(瓶子走科技瓶经验体系，不作宝箱奖励)。
-- (mech-armor/power-armor-mk2/spidertron/tank 已归 equipment，beacon 归 production)
local TREASURE_POOL = {
    'rocket-fuel', 'processing-unit','low-density-structure', 'rocket-part',
    'productivity-module-2', 'speed-module-2', 'efficiency-module-2', 'quality-module-2',  -- 顶级插件
    'productivity-module-3', 'speed-module-3', 'efficiency-module-3', 'quality-module-3',  -- 顶级插件
    'rocket-silo',
}

-- 按给定【类权重表】选类、类内等概率选物品。weights[cat] 为 0/nil 即跳过该类。
-- 用 ipairs 顺序确定 → 多人各端一致，math.random 取值不会 desync。
local function pick_loot(weights)
    local total = 0
    for _, c in ipairs(LOOT) do
        total = total + (weights[c.cat] or 0)
    end
    if total <= 0 then return LOOT[1].items[1] end   -- 权重表为空时的兜底
    local roll = math.random() * total
    for _, c in ipairs(LOOT) do
        local w = weights[c.cat] or 0
        if w > 0 then
            roll = roll - w
            if roll <= 0 then return c.items[math.random(#c.items)] end
        end
    end
    return LOOT[1].items[1]   -- 浮点误差兜底
end

-- 单件数量：1 到该物品 1 组(堆叠数) × random^exp。exp 越大越偏低：
--   exp=1 均匀(偏多，钢箱)、exp=2 偏低(铁箱)、exp=4 极偏低(多为几个，木箱)。
local function loot_count(name, exp)
    local proto = prototypes.item[name]
    local ss = (proto and proto.stack_size) or 1
    return math.max(1, math.ceil(ss * math.random() ^ (exp or 2)))
end

-- 品质：以概率 p 停在当前档、否则升一档（几何分布）。p 越小越易出高品质。常见优先，normal 大概率第一次就返回。
--   p=0.9(默认，普通箱)：normal/uncommon/rare/epic/legendary ≈ 0.9/0.09/0.009/0.0009/0.0001（与原分布一致）。
--   p=0.7(敌人/敌方弹药)：更常出高品质（normal≈0.7、uncommon≈0.21、rare≈0.063…）。
local QUALITY_TIERS = {'uncommon', 'rare', 'epic', 'legendary'}
local function roll_quality(p)
    p = p or 0.9
    local q = 'normal'
    for _, tier in ipairs(QUALITY_TIERS) do
        if math.random() < p then return q end
        q = tier
    end
    return q
end

-- 宝箱(木箱)专用品质（高品质惊喜，与"宝"匹配）。常见优先。
local function roll_treasure_quality()
    local r = math.random()
    if r >= 0.3 then return 'normal' end
    if r >= 0.09 then return 'uncommon' end
    if r >= 0.0027 then return 'rare' end
    if r >= 0.00081 then return 'epic' end
    return 'legendary'
end

-- 物品名有效性校验：LOOT 表是手动穷举的，某些名字会随 DLC/版本失效
-- （如 Space Age 删了 'satellite'），运行时 insert 不存在的物品会报 "unknown item name" 崩档。
-- 此处统一拦截：无效则跳过，并把名字报告给所有【在线管理员】（同名只报一次，避免刷屏）。
local function item_ok(name)
    if prototypes.item[name] then return true end
    storage.bad_items = storage.bad_items or {}
    if not storage.bad_items[name] then
        storage.bad_items[name] = true
        log('endfield: 跳过无效战利品物品名: ' .. tostring(name))
        for _, p in pairs(game.players) do
            if p.connected and p.admin then
                p.print('[战利品] 跳过无效物品名（LOOT 表需更新）: ' .. tostring(name))
            end
        end
    end
    return false
end

-- 往箱子塞普通品质战利品：抽 n 次，每次 count = loot_count(name, exp)。
--   kinds 给定 → 先选定 kinds 种物品，n 次都在这几种里抽（少种类、同种叠多组 → 材料箱）；
--   kinds 为 nil → 每次重新抽（种类杂 → 设备箱）。
local function fill_loot(chest, n, weights, exp, kinds)
    local inv = chest.get_inventory(defines.inventory.chest)
    if not inv then return end
    n = math.min(n, #inv)   -- 抽取次数不超过箱子格数：小箱(木16)也能装满，又不溢出浪费
    local pool
    if kinds then
        pool = {}
        for _ = 1, kinds do
            local name = pick_loot(weights)
            if item_ok(name) then pool[#pool + 1] = name end
        end
        if #pool == 0 then return end
    end
    for _ = 1, n do
        local name = pool and pool[math.random(#pool)] or pick_loot(weights)
        if item_ok(name) then
            inv.insert{name = name, count = loot_count(name, exp), quality = roll_quality()}
        end
    end
end

-- 永续箱周围铺地砖的【兜底】类型（正常用本星敌人地砖 storage.enemy_floor[星球]，未设时退回此值）。
local PERP_FLOOR = 'hazard-concrete-left'

-- 永续箱奖励（罕见）：随机一种物品无限供应。设为【不可打开/不可拆走、可摧毁】，
-- 防止滥用又能就地用（接机械臂/传送带）。force=neutral（不进蓝图；机械臂仍可从中抽货）。
-- 返回 true=成功放置（可继续放守卫），false=失败（已清理，不放守卫）。
local function spawn_perpetual_chest(surface, pos)
    local chest = surface.create_entity{name = 'infinity-chest', force = 'neutral', position = pos}
    if not chest then return false end
    -- 氛围：箱子周围 7×7 铺一圈【第二种】地砖 storage.enemy_floor2[星球]（永续据点专用，与普通据点地砖区分），未设退回 PERP_FLOOR。
    -- pos 同时兼容 {x=,y=} 与数组式 {a,b} 两种写法。
    local floor = (storage.enemy_floor2 and storage.enemy_floor2[surface.name]) or PERP_FLOOR
    local cx, cy = math.floor(pos.x or pos[1]), math.floor(pos.y or pos[2])
    local tiles = {}
    for dx = -3, 3 do
        for dy = -3, 3 do tiles[#tiles + 1] = {name = floor, position = {cx + dx, cy + dy}} end
    end
    surface.set_tiles(tiles)
    -- 永续箱只出基础材料/矿物(LOOT_WEIGHTS.perp)；选到无效物品名（item_ok 会报告管理员）就重抽，全失败则不放。
    local item
    for _ = 1, 8 do
        local cand = pick_loot(LOOT_WEIGHTS.perp)
        if item_ok(cand) then item = cand; break end
    end
    if not item then chest.destroy(); return false end
    local ss = prototypes.item[item].stack_size
    chest.infinity_container_filters = {{index = 1, name = item, count = ss, mode = 'exactly'}}
    chest.operable = false        -- 不可打开/重配
    chest.minable_flag = false    -- 不可拆走
    chest.destructible = false    -- 不可摧毁（否则 fulgora 闪电/火炮会把它劈烂）
    return true
end

-- 给【非虫子类】敌人(炮塔/地雷等；排除 worm/虫巢/虫)脚下铺一小块【随机矩形】地砖 floor。
-- floor 由调用方决定（空据点传 nil=不铺；普通箱传本星地砖；永续传第二种地砖）。矩形大小随机、中心≈实体位置。
-- 实体在区块边缘时，跨到未生成相邻区块的那部分会被 set_tiles 静默丢弃（无所谓）。
local function enemy_floor_patch(surface, ent, floor)
    if not floor then return end                       -- 不传地砖 → 不铺（空据点）
    if not (ent and ent.valid) then return end
    -- 虫子类(虫巢/虫/沙虫) 与 地雷 都不铺（地雷铺了会暴露陷阱）。
    if ent.type == 'unit-spawner' or ent.type == 'unit' or ent.type == 'land-mine'
        or string.find(ent.name, 'worm', 1, true) then return end
    local cx, cy = math.floor(ent.position.x), math.floor(ent.position.y)
    local rw, rh = math.random(1, 3), math.random(1, 3)   -- 半宽/半高随机 → 矩形大小随机
    local tiles = {}
    for dx = -rw, rw do
        for dy = -rh, rh do tiles[#tiles + 1] = {name = floor, position = {cx + dx, cy + dy}} end
    end
    surface.set_tiles(tiles)
end

-- 把炮塔弹药一次性【加满】：按 堆叠数 × 槽数 插入，多余自动丢弃。
--   gun-turret 用 turret_ammo 槽、artillery-turret 用 artillery_turret_ammo 槽；ammo 为 nil 则跳过。
-- count 省略=加满所有弹槽；指定则只塞该数量（如核弹少量）。
local function fill_turret_ammo(e, ammo, count)
    if not (ammo and prototypes.item[ammo]) then return end
    local inv = e.get_inventory(defines.inventory.turret_ammo)
             or e.get_inventory(defines.inventory.artillery_turret_ammo)
    if not inv then return end
    inv.insert{name = ammo, count = count or (prototypes.item[ammo].stack_size * #inv), quality = roll_quality(0.7)}
end

-- 加权随机抽弹药：list 每项 {权重, 弹名[, 数量lo, 数量hi]}（无 lo/hi = 加满）。返回 弹名, 数量(or nil)。
-- 所有敌方炮塔填弹统一用它（纯随机、不挂 danger）；伤害随 danger 缩放已由 reset 的 set_ammo_damage_modifier 处理。
local function pick_ammo(list)
    local total = 0
    for _, o in ipairs(list) do total = total + o[1] end
    local r = math.random() * total
    for _, o in ipairs(list) do
        r = r - o[1]
        if r <= 0 then return o[2], o[3] and math.random(o[3], o[4]) end
    end
    return list[1][2]   -- 浮点兜底（理论到不了）
end
-- 机枪弹(所有机枪塔通用)：普通/穿甲/铀(加满)；火箭炮：普通/爆破火箭(加满) + 极小概率核弹(1~3发)。
local MAG_AMMO       = {{60, 'firearm-magazine'}, {32, 'piercing-rounds-magazine'}, {8, 'uranium-rounds-magazine'}}
local OUTPOST_ROCKET = {{65, 'rocket'}, {32, 'explosive-rocket'}, {3, 'atomic-bomb', 1, 3}}

-- 据点守卫塔【统一池】(force=enemy，唯一的野外敌人系统)：电炮(靠据点子电网)/枪炮(填弹)/沙虫·地雷·重炮(无需电)。
-- 每种在 feat_outpost 各自非线性数量。带 variants 的随机取一档(沙虫三档)；
-- mag=每个随机弹种 / ammo=固定弹 / rocket=随机火箭 / fluid=灌液；无标记(沙虫/地雷)不填。弹药一律加满。
local OUTPOST_GUARDS = {
    {name = 'laser-turret', electric = true},             -- 激光：electric-turret，靠 substation+供电接口子电网
    {name = 'tesla-turret', electric = true},             -- 特斯拉枪：electric-turret，同样靠子电网供电（无弹药）
    {name = 'flamethrower-turret', fluid = 'crude-oil'},  -- 喷火：fluid_box 无 filter，灌原油即可开火
    {name = 'gun-turret', mag = true},                    -- 机枪：per 个随机弹种、加满
    {name = 'rocket-turret', rocket = true},              -- 火箭炮：ammo-turret，随机普通/爆破火箭，极小概率核弹(少量)
    {name = 'railgun-turret', ammo = 'railgun-ammo'},     -- 磁轨炮：ammo-turret，塞磁轨弹
    {variants = {'small-worm-turret', 'medium-worm-turret', 'big-worm-turret'}},  -- 沙虫：随机一档，无需弹/电
    {name = 'land-mine'},                                 -- 地雷：无需弹
    {name = 'artillery-turret', ammo = 'artillery-shell'},-- 重炮：炮弹
}

-- （原 guard_perpetual / GUARD_KINDS 已并入 feat_outpost 的统一守卫池 OUTPOST_GUARDS：
--   永续箱不再单独成特征、也不再各自带守卫环；敌人统一由据点生成。）


-- 区块级确定性随机 [0,1)：点状稀有风味用。
local function chunk_rng(left_top, offset)
    return noise.hash01(left_top.x * 0.1234 + left_top.y * 0.3717 + offset * 1.7 + (storage.run or 0) * 0.011)
end

-- 五类遭遇【每区块基础频率】（世界密度=1 时的上限）。常→稀：空据点 > 钢(材料) > 铁(设备) > 木(宝箱) ≈ 永续箱。
local ENCOUNTER_BASE = {material = 0.03, equipment = 0.015, treasure = 0.0075, perpetual = 0.0075, empty = 0.08}

-- 本世界本类遭遇的【每区块实际出现概率】，五类【统一口径】：
--   世界密度(surface.lua 滚的 random^2，每星每类独立) × 基础频率 ENCOUNTER_BASE × 全局乘数 storage.loot_density × 该类乘数 storage.loot_density_<类型>。
--   后两者默认 1、可 /c 单独热改（loot_density 全局；loot_density_material/equipment/treasure/perpetual/empty 各类）。无世界密度则兜底 0.3。
local function encounter_chance(surface, kind)
    local style = storage.loot_style and storage.loot_style[surface.name]
    local wd = (style and style[kind]) or 0.3
    return wd * ENCOUNTER_BASE[kind] * (storage.loot_density or 1) * (storage['loot_density_' .. kind] or 1)
end

-- 钢箱 = 材料箱填充：1~3 种材料、接近装满。高效填法：每种【一次性 insert 满堆叠×分到的格数】，整箱只需 1~3 次 insert。普通品质。
local function fill_material_chest(inv)
    -- 选 1~3 种材料（无效名跳过）
    local kinds = {}
    for _ = 1, math.random(1, 3) do
        local name = pick_loot(LOOT_WEIGHTS.material)
        if item_ok(name) then kinds[#kinds + 1] = name end
    end
    if #kinds == 0 then return end
    -- 接近装满：填 random(0.85~1.0) 比例的格子，按种类均分（最后一种吃余数）
    local slots = #inv
    local fill = math.max(#kinds, math.floor(slots * (0.85 + math.random() * 0.15) + 0.5))
    local per = math.floor(fill / #kinds)
    for i, name in ipairs(kinds) do
        local n_slots = (i == #kinds) and (fill - per * (#kinds - 1)) or per   -- 最后一种吃掉余数
        local ss = prototypes.item[name].stack_size
        if n_slots > 0 then inv.insert{name = name, count = ss * n_slots, quality = roll_quality()} end
    end
end

-- 木箱 = 宝箱：稀有。1~2 种高价值物品，每件【几个】(count = ss×random^4，极偏低)
local TREASURE_BOTTLE_CHANCE = 0.5   -- 木箱额外掉【科技瓶】的概率

-- 给一个木箱填宝：1~2 种高价值物品 + 概率额外一种科技瓶。
local function fill_treasure_chest(inv)
    for _ = 1, math.random(1, 2) do
        local name = TREASURE_POOL[math.random(#TREASURE_POOL)]
        if item_ok(name) then
            inv.insert{name = name, count = loot_count(name, 4), quality = roll_treasure_quality()}
        end
    end
    -- 可能额外给某种科技瓶：1~5 组(满堆叠)，组数走 random^2(偏低，多为 1~2 组)，随机(宝箱)品质。
    if math.random() < TREASURE_BOTTLE_CHANCE then
        local pack = constants.science_packs[math.random(#constants.science_packs)]
        if item_ok(pack) then
            local proto = prototypes.item[pack]
            local ss = (proto and proto.stack_size) or 200
            local groups = 1 + math.floor(math.random() ^ 2 * 3)   -- 1~3 组（random^2 偏低）
            inv.insert{name = pack, count = groups * ss, quality = roll_treasure_quality()}
        end
    end
end

-- 据点奖励箱：按种类放一个箱并填充。material/equipment/treasure = 普通可拆箱(destructible=false 不受伤、仍可手拆收取)；perpetual = 无限箱。
local function place_reward_chest(surface, pos, kind)
    if kind == 'perpetual' then
        local p = surface.find_non_colliding_position('steel-chest', pos, 4, 1)
        if p then spawn_perpetual_chest(surface, p) end
        return
    end
    local chest_name = (kind == 'equipment' and 'iron-chest') or (kind == 'treasure' and 'wooden-chest') or 'steel-chest'
    local p = surface.find_non_colliding_position(chest_name, pos, 4, 1)
    if not p then return end
    local chest = surface.create_entity{name = chest_name, force = 'neutral', position = p}
    if not chest then return end
    chest.destructible = false
    local inv = chest.get_inventory(defines.inventory.chest)
    if not inv then return end
    if kind == 'equipment' then fill_loot(chest, math.random(10, 24), LOOT_WEIGHTS.equipment, 2)
    elseif kind == 'treasure' then fill_treasure_chest(inv)
    else fill_material_chest(inv) end
end

-- 飞船残骸外观池（big/medium/small）。force=neutral：机器人拆不掉，作障碍/点缀。
local WRECKS = {
    'crash-site-spaceship-wreck-big-1', 'crash-site-spaceship-wreck-big-2',
    'crash-site-spaceship-wreck-medium-1', 'crash-site-spaceship-wreck-medium-2', 'crash-site-spaceship-wreck-medium-3',
    'crash-site-spaceship-wreck-small-1', 'crash-site-spaceship-wreck-small-2', 'crash-site-spaceship-wreck-small-3',
    'crash-site-spaceship-wreck-small-4', 'crash-site-spaceship-wreck-small-5', 'crash-site-spaceship-wreck-small-6',
}
-- 非线性数量：大概率 0、小概率几个、极小概率接近 max（random^power × (max+1) 下取整，power 越大越偏 0）。
local function nonlinear_count(max, power)
    if max < 1 then return 0 end
    return math.floor(math.random() ^ (power or 3) * (max + 1))
end

-- 电网核心：substation + 满电 EEI（给电炮供电）。返回 substation 位置或 nil（放不下）。
local function build_power_core(surface, center)
    local sp = surface.find_non_colliding_position('substation', center, 5, 1)
    if not sp then return nil end
    -- legendary 品质 substation：供电范围更大 → 环上 6~11 格的电炮都能覆盖到、不会没电。
    if not surface.create_entity{name = 'substation', force = 'enemy', position = sp, quality = 'legendary'} then return nil end
    local ip = surface.find_non_colliding_position('electric-energy-interface', sp, 4, 1)
    if ip then
        local eei = surface.create_entity{name = 'electric-energy-interface', force = 'enemy', position = ip}
        if eei then
            eei.electric_buffer_size = 1e9                         -- 1 GJ 缓冲
            eei.power_production = math.random(10, 100) * 6e4 -- 够电炮用、不过大）
            eei.energy = 1e9                                 -- 开局满能量
        end
    end
    return sp
end

-- 【统一放敌人逻辑】(所有遭遇共用，只是 danger 不同)：在 center 周围按 danger 放守卫塔 + 飞船残骸。
--   danger(0~1+)：越大守卫越多越猛、残骸越多。每种炮塔各自【非线性】数量(大概率0、极小概率很多)，放在半径6~11 环上。
--   电炮(electric)首次要放时才【惰性】建电网核心；建不出则本类电炮跳过。残骸 force=neutral、不铺人造地板。
local function place_guards(surface, center, danger, floor)
    local tmax = math.max(1, math.floor(1 + danger * 7 + 0.5))
    local core, core_tried = nil, false
    for _, def in ipairs(OUTPOST_GUARDS) do
        for _ = 1, nonlinear_count(tmax, 3) do
            if def.electric and not core then
                if not core_tried then core, core_tried = build_power_core(surface, center), true end
                if not core then break end                 -- 无电网 → 本类电炮全跳过
            end
            local anchor = (def.electric and core) or center
            local name = def.name or def.variants[math.random(#def.variants)]   -- variants(沙虫)随机取一档
            local ang, r = math.random() * 2 * math.pi, 6 + math.random() * 5
            local gp = {x = anchor.x + math.cos(ang) * r, y = anchor.y + math.sin(ang) * r}
            local gsp = surface.find_non_colliding_position(name, gp, 3, 1)
            if gsp then
                local e = surface.create_entity{name = name, force = 'enemy', position = gsp, direction = math.random(0, 3) * 4, quality = roll_quality(0.7)}
                enemy_floor_patch(surface, e, floor)
                if e then
                    if def.mag then fill_turret_ammo(e, pick_ammo(MAG_AMMO)) end
                    if def.ammo then fill_turret_ammo(e, def.ammo) end
                    if def.rocket then fill_turret_ammo(e, pick_ammo(OUTPOST_ROCKET)) end
                    if def.fluid then e.insert_fluid{name = def.fluid, amount = 100} end
                end
            end
        end
    end
    for _ = 1, nonlinear_count(math.floor(danger * 6), 3) do   -- 残骸随 danger
        local name = WRECKS[math.random(#WRECKS)]
        local ang, r = math.random() * 2 * math.pi, 4 + math.random() * 12
        local wp = surface.find_non_colliding_position(name, {x = center.x + math.cos(ang) * r, y = center.y + math.sin(ang) * r}, 8, 1)
        if wp then surface.create_entity{name = name, position = wp, force = 'neutral'} end
    end
end

-- 【单地块至多一个遭遇】：按稀有度优先级依次尝试，命中即放置(箱/敌人)并 return，后面不再试。
-- 顺序(稀→常)：永续箱 → 木箱 → 铁箱 → 钢箱 → 空据点(纯敌人)。永续箱/空据点 danger 高(更多更猛)，普通箱 danger 低。
-- 敌人统一走 place_guards，只是 danger 不同。出生点 96 格内：放箱不放敌人(保护新手)；距中心越远 danger 越高。
-- 遭遇表（声明式，按【稀→常】排序，命中即停）：seed=chunk_rng 独立种子, kind=类型(查 encounter_chance), danger=守卫危险基数。
--   仅【永续箱】高危(稀有大奖配重兵)，普通箱与空据点都低危；empty=纯敌人无箱。
local ENCOUNTERS = {
    {seed = 605, kind = 'perpetual', danger = 0.9},
    {seed = 601, kind = 'treasure',  danger = 0.12},
    {seed = 557, kind = 'equipment', danger = 0.08},
    {seed = 503, kind = 'material',  danger = 0.05},
    {seed = 701, kind = 'empty',     danger = 0.12},
}
local function place_encounter(surface, lt)
    local ccx, ccy = lt.x + 16, lt.y + 16
    local d2 = ccx * ccx + ccy * ccy
    local _w, _h = storage.width_of and storage.width_of[surface.name], storage.height_of and storage.height_of[surface.name]
    local R = (_w and _h) and (_w + _h) / 2 or storage.radius_standard or 2048   -- 椭圆等效半径；老存档兜底
    local frac = math.min(1, math.sqrt(d2) / R)
    local near_spawn = d2 < 96 * 96
    local center = {x = lt.x + math.random(6, 25) + 0.5, y = lt.y + math.random(6, 25) + 0.5}

    for _, e in ipairs(ENCOUNTERS) do
        if chunk_rng(lt, e.seed) <= encounter_chance(surface, e.kind) then   -- 命中此遭遇
            -- 奖励：非空据点放【1~16 个同类箱】，数量非线性 floor(1+15·random^6)：期望≈3、多数 1~3、极小概率十几个。
            if e.kind ~= 'empty' then
                for _ = 1, math.floor(1 + 15 * math.random() ^ 6) do place_reward_chest(surface, center, e.kind) end
            end
            -- 敌人：出生点 96 格内不放（保护新手）；地砖按类型选——空据点不铺、永续用第二种、普通箱用本星地砖。
            if not near_spawn then
                local floor
                if e.kind == 'perpetual' then floor = (storage.enemy_floor2 or {})[surface.name]
                elseif e.kind ~= 'empty' then floor = (storage.enemy_floor or {})[surface.name] end
                place_guards(surface, center, e.danger * (0.4 + 0.6 * frac), floor)
            end
            return   -- 每地块至多一个遭遇，命中即停
        end
    end
end

-- （原零星 feat_danger 与散布 feat_wrecks 已移除：野外敌人/残骸统一改由 place_encounter→place_guards 据点式生成。）

-- 树木主题（连续插值，不是离散几种世界）：把每棵树【从原版色/灰度插值到本轮目标】，插值量 = strength。
--   strength 立方偏置：绝大多数 ≈0（几乎原版）、极小概率接近 1（大改）。所以"特殊树世界"很罕见。
--   颜色目标按【位置低频噪声】取 → 相邻树同色、成片（像原版按地貌变化），不会每棵乱跳；
--   color_spread 连续控制"单一色 ↔ 多样"，gray_target 连续控制枯灰程度。含原生树一起调。
local function theme_trees(surface, lt)
    local gseed = wseed(401)
    local strength = noise.hash01(gseed * 8.1)
    strength = strength * strength * strength        -- 立方偏置 → 多数接近 0
    if strength < 0.05 then return end               -- 太弱当作原版，不动(也省开销)
    local gray_target  = noise.hash01(gseed * 4.7)   -- 本轮枯灰目标 0~1
    local base_color   = noise.hash01(gseed * 2.2)   -- 本轮基色
    local color_spread = noise.hash01(gseed * 5.3)   -- 颜色随位置变化幅度：0=单一 ↔ 1=多样（连续）
    local trees = surface.find_entities_filtered{area = {{lt.x, lt.y}, {lt.x + 32, lt.y + 32}}, type = 'tree'}
    for _, t in pairs(trees) do
        if t.valid then
            local gmax = t.tree_gray_stage_index_max
            if gmax and gmax > 0 then
                local target = gray_target * gmax
                local v = math.floor(t.tree_gray_stage_index + (target - t.tree_gray_stage_index) * strength + 0.5)
                t.tree_gray_stage_index = math.max(0, math.min(gmax, v))   -- 灰度 0-based [0,gmax]
            end
            local cmax = t.tree_color_index_max
            if cmax and cmax > 0 then
                -- 颜色随位置平滑变化(低频噪声) → 成片同色；幅度由 color_spread 控制
                local n = (noise.fractal(noise.octaves.blob, t.position.x, t.position.y, gseed) + 1) * 0.5
                local cc = (base_color + (n - 0.5) * color_spread) % 1
                local target = cc * cmax
                local v = math.floor(t.tree_color_index + (target - t.tree_color_index) * strength + 0.5)
                t.tree_color_index = math.max(1, math.min(cmax, v))        -- 颜色 1-based [1,cmax]，0 会报错
            end
        end
    end
end

-- ── 障碍互换世界变体（树/石/遗迹/冰山 跨类互换，噪声门控）────────────────────
-- 每世界小概率滚定一条规则(surface.lua 存 storage.obstacle_remap[星球]={seed,threshold[,to]})；
-- 区块内把现地带碰撞盒障碍在噪声大团里原位换成另一种(跨类)。目标池运行时按 entity_ok 校验(无效报告管理员并剔除)。
-- 下面三表(TREE_TARGETS/ROCK_CANDIDATES/OTHER_OBSTACLES)合并成 OBSTACLE_TARGETS 作为【目标】候选。
local TREE_TARGETS = {
    -- nauvis（含 -red/-brown 色变体，原只列了 tree-01..09 主色）
    'tree-01', 'tree-02', 'tree-02-red', 'tree-03', 'tree-04', 'tree-05',
    'tree-06', 'tree-06-brown', 'tree-07', 'tree-08', 'tree-08-brown', 'tree-08-red',
    'tree-09', 'tree-09-brown', 'tree-09-red',
    'dead-tree-desert', 'dead-grey-trunk', 'dry-tree', 'dry-hairy-tree', 'dead-dry-hairy-tree',  -- 枯/荒漠
    'ashland-lichen-tree', 'ashland-lichen-tree-flaming',                                         -- vulcanus（含燃烧态）
    'boompuff', 'cuttlepop', 'funneltrunk', 'hairyclubnub', 'lickmaw', 'slipstack', 'stingfrond', 'sunnycomb', 'teflilly',  -- gleba（不含需水的 water-cane）
}
-- 石头/障碍：既是替换【源】(find 用)也是【目标】候选。跨星球互换 → 母星可冒出锂冰/火山石/雷击熔岩等异星障碍。
-- 注：medium/small/tiny-rock 是 optimized-decorative【不是 entity】，已移除（曾被静默丢弃，现 build_pool 会报告管理员）。
local ROCK_CANDIDATES = {
    'big-rock', 'huge-rock', 'big-sand-rock',                                    -- nauvis
    'big-volcanic-rock', 'huge-volcanic-rock',                                   -- vulcanus 火山石
    'vulcanus-chimney', 'vulcanus-chimney-cold', 'vulcanus-chimney-faded', 'vulcanus-chimney-short', 'vulcanus-chimney-truncated',  -- vulcanus 烟囱石
    'fulgurite', 'fulgurite-small',                                              -- fulgora 雷击熔岩（雷击木）
    'copper-stromatolite', 'iron-stromatolite',                                  -- gleba 铜/铁叠层岩（铜铁石头）
    'lithium-iceberg-big', 'lithium-iceberg-huge',                               -- aquilo 锂冰
}
-- 其它带碰撞盒障碍（非树非石）：fulgora 遗迹（simple-entity；-tiny 是装饰物、-attractor 是避雷针，已排除）。
local OTHER_OBSTACLES = {
    'fulgoran-ruin-small', 'fulgoran-ruin-medium', 'fulgoran-ruin-big', 'fulgoran-ruin-huge',
}
-- 统一【障碍目标池】= 树 + 石/障碍 + 其它障碍。源不靠此表（feature_entity_remap 按 type 过滤现地实体），
-- 此表只决定"换成什么"，可跨类互换（树↔石↔遗迹↔冰山…）。运行时按 entity_ok 校验。
local OBSTACLE_TARGETS = {}
for _, list in ipairs({TREE_TARGETS, ROCK_CANDIDATES, OTHER_OBSTACLES}) do
    for _, n in ipairs(list) do OBSTACLE_TARGETS[#OBSTACLE_TARGETS + 1] = n end
end

-- 替换池实体名【运行时校验】：池是手动穷举的，DLC/版本变动或拼错会让某些名失效。
-- 无效则跳过，并报告给所有【在线管理员】（同名只报一次，逻辑同 item_ok）。
local function entity_ok(name)
    if prototypes.entity[name] then return true end
    storage.bad_entities = storage.bad_entities or {}
    if not storage.bad_entities[name] then
        storage.bad_entities[name] = true
        log('endfield: 跳过无效替换实体名: ' .. tostring(name))
        for _, p in pairs(game.players) do
            if p.connected and p.admin then
                p.print('[替换] 跳过无效实体名（替换池需更新）: ' .. tostring(name))
            end
        end
    end
    return false
end

local function build_pool(names)
    local out = {}
    for _, n in ipairs(names) do if entity_ok(n) then out[#out + 1] = n end end
    return out
end
local obstacle_pool   -- 懒构建的有效名缓存（prototypes 不变，建一次）
local function obstacles_pool() obstacle_pool = obstacle_pool or build_pool(OBSTACLE_TARGETS); return obstacle_pool end
function M.pick_entity_target() local p = obstacles_pool(); return #p > 0 and p[math.random(#p)] or nil end

-- 统一【障碍互换】：把现地所有带碰撞盒障碍（type=tree/simple-entity：树/石/遗迹/冰山/叠层岩…）按噪声门控原位
-- 替换，不看脚下 tile。源天然自限（find 只命中本星球现有实体），目标跨类（可树↔石↔遗迹）。
--   rm = storage.obstacle_remap[星球]，本轮该星滚定（surface.lua）：
--     · {to=名, seed, threshold} → 噪声区内统一换成同一种（大概率；单一主题斑块、协调）
--     · {seed, threshold}      → 噪声区内每个各自随机换成【另一种】（小概率；跨类大杂烩异界带）
-- （旧纯字符串格式已对线上老档用一次性 /c 统一成表；新档只产出表格式，此处不再判型。）
local function feature_entity_remap(surface, lt)
    local rm = storage.obstacle_remap and storage.obstacle_remap[surface.name]
    if not rm then return end
    local pool = obstacles_pool()
    if #pool == 0 then return end
    local seed, thr = rm.seed, rm.threshold or 0
    for _, e in pairs(surface.find_entities_filtered{area = {{lt.x, lt.y}, {lt.x + 32, lt.y + 32}}, type = {'tree', 'simple-entity'}}) do
        if e.valid then
            local p = e.position
            -- 无 seed(旧格式) → 全替换；有 seed → 仅噪声大团内替换（成片斑块，多半小、极少大）
            if (not seed) or noise.fractal(noise.octaves.smooth, p.x, p.y, seed) > thr then
                local to = rm.to or pool[math.random(#pool)]   -- 固定目标 或 每个随机取另一种
                if to ~= e.name and prototypes.entity[to] then
                    e.destroy()
                    if surface.can_place_entity{name = to, position = p} then
                        surface.create_entity{name = to, position = p}
                    end
                end
            end
        end
    end
end

-- 流体资源互换：小概率把本星【所有产流体的资源】(原油/锂卤水/氟喷口/硫酸喷泉)整体换成另一种喷口。
-- 源自动识别（find resource → 开采产物含 fluid 的才算，固体矿/废料不动）；目标由本星本轮滚定(surface.lua)。
-- 含量【按目标喷口的最小值生成】(minimum × 1.5~5.5 随机)，量级随目标自适应、不受源贫富影响。
local FLUID_RESOURCES = {'crude-oil', 'sulfuric-acid-geyser', 'fluorine-vent', 'lithium-brine'}
local fluid_pool   -- 懒构建有效名缓存
local function fluids_pool() fluid_pool = fluid_pool or build_pool(FLUID_RESOURCES); return fluid_pool end
-- 从有效喷口池里随机取一个【不是 current 的】其它喷口。
local function pick_other_fluid(current)
    local pool, others = fluids_pool(), {}
    for _, n in ipairs(pool) do if n ~= current then others[#others + 1] = n end end
    return #others > 0 and others[math.random(#others)] or nil
end

-- 该资源原型开采是否产流体（区分喷口 vs 固体矿；比 resource_category 命名可靠）。
local function yields_fluid(proto)
    local mp = proto.mineable_properties
    for _, pr in ipairs(mp and mp.products or {}) do
        if pr.type == 'fluid' then return true end
    end
    return false
end

-- 流体资源互换：rm = storage.fluid_remap[星球]（surface.lua 滚定），命中的喷口变成【随机另一种】喷口。
--   两种门控二选一：
--     · {p=概率}        → 每个产流体资源【各自】以概率 p 突变（零星散布，每星每世界 p 不同）
--     · {seed,threshold} → 仅落在 noise 大团内的喷口整体突变（成片，多半小斑块）
--   含量按目标喷口 minimum × 1.5~5.5 生成（量级随目标自适应）。同片油田可能混出多种喷口。
local function feature_fluid_remap(surface, lt)
    local rm = storage.fluid_remap and storage.fluid_remap[surface.name]
    if not rm then return end
    -- （旧裸 p 数值格式已对线上老档用一次性 /c 统一成 {p=…} 表；新档只产出表格式，此处不再判型。）
    for _, e in pairs(surface.find_entities_filtered{area = {{lt.x, lt.y}, {lt.x + 32, lt.y + 32}}, type = 'resource'}) do
        if e.valid and yields_fluid(e.prototype) then
            local pos = e.position
            local hit = rm.p and (math.random() < rm.p)
                or (rm.seed and noise.fractal(noise.octaves.smooth, pos.x, pos.y, rm.seed) > (rm.threshold or 0))
            if hit then
                local target = pick_other_fluid(e.name)
                if target and prototypes.entity[target] then
                    -- 含量基于目标喷口 normal（恒正：油/硫酸 30万、氟 10万、锂卤 5万）；硬下限保证 >0。
                    -- 注意 minimum_resource_amount 可能为 0，且 Lua 中 0 是真值、`or` 兜不住 → 必须 max(1,…)。
                    local base = prototypes.entity[target].normal_resource_amount
                    if not base or base <= 0 then base = 100000 end
                    local amount = math.max(1, math.floor(base * (0.5 + math.random())))   -- normal × 0.5~1.5
                    e.destroy()
                    if surface.can_place_entity{name = target, position = pos} then
                        surface.create_entity{name = target, position = pos, amount = amount}
                    end
                end
            end
        end
    end
end

local REAL_PLANETS = {nauvis = true, vulcanus = true, fulgora = true, gleba = true, aquilo = true}

-- 每个真实星球的圆内区块都调用。只做原生做不到的事：母星废料/跨星异物(手动) + 树木调色(改原生树) +
-- 通用风味(虫/物资箱)。地貌(石/树/矿/水…)本身交回 2.0 原生，本轮风味由 surface.lua 的气候偏置/autoplace 决定。
function M.generate(surface, lt)
    if not REAL_PLANETS[surface.name] then return end   -- 飞船平台等跳过
    local W = M.knobs()
    -- 本轮【全局共享】的朝向/拉伸/缩放：各特征方向一致、不互相打架（绝大多数圆团，~15% 轮次才整体拉长）
    local A, S, Z = run_transform()
    local home = PLANET[surface.name]
    if home then
        for _, def in ipairs(home) do place_feature(surface, lt, def, A, S, Z, W) end
    end
    for _, def in ipairs(EXOTIC) do place_feature(surface, lt, def, A, S, Z, W) end
    feature_entity_remap(surface, lt)    -- 统一障碍互换（树/石/遗迹跨类，噪声门控）；在调色前，让换出来的新树也被 theme_trees 调色
    feature_fluid_remap(surface, lt)     -- 流体资源互换（原油/锂卤水/氟喷口/硫酸喷泉 小概率整星换成另一种）
    theme_trees(surface, lt)
    -- 单地块【至多一个遭遇】：永续→木→铁→钢箱→空据点，命中即停；敌人统一 place_guards（perpetual/empty danger 高）。
    place_encounter(surface, lt)
    -- （原零星 feat_danger 敌群 + 散布 feat_wrecks 残骸 + 独立 feat_perpetual 已全部并入 place_encounter。原版 enemy-base 仍自然出虫。）
end

return M
