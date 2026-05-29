-- 地图风味（原则：用噪声【修改 2.0 原生生成】，不用手动 stamp 去【覆盖】——原生地貌更自然）。
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

-- 本轮【整局气质】连续旋钮（由 storage.run 确定性派生）：每个都是 [0,1) 连续量，不是硬编码离散概率——
-- 每轮整体氛围（繁茂↔荒芜、危险↔安宁、富庶↔贫瘠、寻常↔诡异）都是渐变的。
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

-- 本轮【全局共享】的噪声变换(朝向/拉伸/缩放)同样整轮恒定，按 run 缓存——也被每区块调用。
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

-- 本轮该特征强度：~60% 为 0(不出现)；出现时走【立方偏置】——绝大多数小规模、极小概率大规模。
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
-- 不再带全局权重 w —— 每种箱子用各自的【类权重表】(见 LOOT_WEIGHTS)抽取，掉落构成因箱而异。
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
        'barrel',                                                                       -- 杂项
    }},
    -- 物流(带/臂/管/箱/轨/机器人)
    {cat = 'logistics',  items = {
        'transport-belt',  'fast-transport-belt',  'express-transport-belt',  'turbo-transport-belt',  -- 传送带
        'underground-belt',  'fast-underground-belt',  'express-underground-belt',  'turbo-underground-belt',  -- 地下带
        'splitter',  'fast-splitter',  'express-splitter',  'turbo-splitter',           -- 分流器
        'loader',  'fast-loader',  'express-loader',                                    -- 装卸器
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
        'space-platform-starter-pack',                                                 -- 平台起步包
        'foundation',  'space-platform-foundation',  'ice-platform',                   -- 平台地基
        'cargo-bay',  'cargo-landing-pad',  'asteroid-collector',  'thruster',          -- 平台部件
    }},
}

-- 各【按外观区分】的箱子对 LOOT 各【类】的权重：先按权重选类、再类内等概率选物品。
-- 每表都【列全所有类】(顺序同 LOOT)，不要的标 0 方便手调——0 与省略等价，不影响运算。
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
-- 没有的】顶级物品 —— 顶级插件(3级，初始奖励只给基础级) + rocket-silo。
-- foundry/electromagnetic-plant/biochamber/cryogenic-plant/recycler/big-mining-drill 已作为初始
-- 奖励发放，宝箱再给等于重复 → 移除。不放科技瓶(瓶子走科技瓶经验体系，不作宝箱奖励)。
-- (mech-armor/power-armor-mk2/spidertron/tank 已归 equipment，beacon 归 production)
local TREASURE_POOL = {
    'rocket-fuel', 'processing-unit','low-density-structure',   
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

-- 普通品质（材料箱/设备箱用）：多数 normal，小概率 uncommon/rare → 开箱偶有惊喜。
local function roll_quality()
    local r = math.random()
    if r < 0.0001 then return 'legendary' end
    if r < 0.001 then return 'epic' end
    if r < 0.01 then return 'rare' end
    if r < 0.1 then return 'uncommon' end
    return 'normal'
end

-- 宝箱(木箱)专用品质（高品质惊喜，与"宝"匹配）。
local function roll_treasure_quality()
    local r = math.random()
    if r < 0.00081 then return 'legendary' end
    if r < 0.0027 then return 'epic' end
    if r < 0.09 then return 'rare' end
    if r < 0.3 then return 'uncommon' end
    return 'normal'
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

-- 永续箱奖励（罕见）：随机一种物品无限供应。设为【不可打开/不可拆走、可摧毁】，
-- 防止滥用又能就地用（接机械臂/传送带）。force=neutral（不进蓝图；机械臂仍可从中抽货）。
-- 返回 true=成功放置（可继续放守卫），false=失败（已清理，不放守卫）。
local function spawn_perpetual_chest(surface, pos)
    local chest = surface.create_entity{name = 'infinity-chest', force = 'neutral', position = pos}
    if not chest then return false end
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
    chest.destructible = true     -- 可摧毁
    return true
end

-- 敌方机枪炮塔弹种：随世界危险度【偏向】更强的弹，但【每个炮塔各自随机】（不再全星统一一种）。
--   danger 越高 → 越可能穿甲/铀弹；低危险多为普通弹。
local MAGS = {'firearm-magazine', 'piercing-rounds-magazine', 'uranium-rounds-magazine'}
local function pick_mag(danger)
    local r = (danger or 0) * 0.7 + math.random() * 0.6
    if r > 1.0 then return MAGS[3] end    -- 铀弹
    if r > 0.55 then return MAGS[2] end   -- 穿甲弹
    return MAGS[1]                         -- 普通弹
end

-- 把炮塔弹药一次性【加满】：按 堆叠数 × 槽数 插入，多余自动丢弃。
--   gun-turret 用 turret_ammo 槽、artillery-turret 用 artillery_turret_ammo 槽；ammo 为 nil 则跳过。
local function fill_turret_ammo(e, ammo)
    if not (ammo and prototypes.item[ammo]) then return end
    local inv = e.get_inventory(defines.inventory.turret_ammo)
             or e.get_inventory(defines.inventory.artillery_turret_ammo)
    if not inv then return end
    inv.insert{name = ammo, count = prototypes.item[ammo].stack_size * #inv}
end

-- 永续箱守卫【可选种类】：每个永续箱只用其中【1~2 种】（同箱守卫种类统一），同种内可有尺寸变体(如沙虫三档)。
--   机枪炮塔每个各自随机弹种(pick_mag，随危险度)、重炮用炮弹；沙虫/地雷不用弹。弹药一律加满。
local GUARD_KINDS = {
    worm   = {'small-worm-turret', 'medium-worm-turret', 'big-worm-turret'},  -- 沙虫（三档随机）
    turret = {{name = 'gun-turret', mag = true}},                             -- 机枪炮塔（弹种 per 炮塔随机）
    mine   = {'land-mine'},                                                   -- 地雷
    art    = {{name = 'artillery-turret', ammo = 'artillery-shell'}},         -- 重炮（炮弹）
}
local GUARD_KIND_NAMES = {'worm', 'turret', 'mine', 'art'}

-- 永续箱守卫：只在【永续箱】四周放敌人(force=enemy)，普通箱【不放】。出生点附近(<64格)不放（保护新手）。
--   种类：本箱随机选 1~2 种，之后所有守卫只从这几种里出 → 同箱统一。
--   数量：随【离地图中心距离】半随机缩放——近中心少(约 2~3)、越往边缘越多(可到十来个)。
local function guard_perpetual(surface, pos)
    -- pos 可能是数组式 {x,y}（feat_perpetual 传入）也可能是 {x=,y=}，统一取坐标。
    local cx, cy = pos.x or pos[1], pos.y or pos[2]
    local dist = math.sqrt(cx * cx + cy * cy)
    if dist < 64 then return end                          -- 出生点保护半径内不放

    -- 选 1~2 种：对 GUARD_KIND_NAMES 做部分洗牌取前 pick 个，合并其变体成候选实体表。
    local names = {}
    for i, k in ipairs(GUARD_KIND_NAMES) do names[i] = k end
    local pick = math.random(1, 2)
    local variants = {}
    for i = 1, pick do
        local j = math.random(i, #names)
        names[i], names[j] = names[j], names[i]
        for _, v in ipairs(GUARD_KINDS[names[i]]) do variants[#variants + 1] = v end
    end

    -- 数量随离中心比例 frac∈[0,1] 增长：均值 2(中心)→10(边缘)，叠三角抖动 ±~3，下限 2。
    local R = storage.radius_of[surface.name] or storage.radius or 2048
    local frac = math.min(1, dist / R)
    local mean = 2 + frac * 8
    local count = math.max(2, math.floor(mean + (math.random() - math.random()) * 3 + 0.5))

    local danger = M.knobs().danger   -- 本轮危险度（缓存），决定机枪炮塔弹种偏向
    for _ = 1, count do
        local def = variants[math.random(#variants)]
        local name = type(def) == 'table' and def.name or def
        local ang, r = math.random() * 2 * math.pi, 3 + math.random() * 5
        local gp = {x = cx + math.cos(ang) * r, y = cy + math.sin(ang) * r}
        local sp = surface.find_non_colliding_position(name, gp, 5, 1)
        if sp then
            local e = surface.create_entity{name = name, force = 'enemy', position = sp}
            if e and type(def) == 'table' then
                -- 机枪炮塔 per 个随机弹种、重炮用炮弹；都加满
                fill_turret_ammo(e, def.mag and pick_mag(danger) or def.ammo)
            end
        end
    end
end

-- 放一个【指定外观】的箱子(外观=内容含义) 并按类权重填充。force=neutral（可开/可拿/可手拆，不进蓝图）。
local function place_filled_chest(surface, pos, chest_name, n, weights, exp, kinds)
    if not surface.can_place_entity{name = chest_name, position = pos} then return end
    local chest = surface.create_entity{name = chest_name, force = 'neutral', position = pos}
    if chest then fill_loot(chest, n, weights, exp, kinds) end
end

-- 区块级确定性随机 [0,1)：点状稀有风味用。
local function chunk_rng(lt, off)
    return noise.hash01(lt.x * 0.1234 + lt.y * 0.3717 + off * 1.7 + (storage.run or 0) * 0.011)
end

-- 四类箱子【每区块基础频率】（密度=1 时的频率上限）。钢(材料)最常见 > 铁(设备) > 木(宝箱)稀有 > 永续箱极低。
local LOOT_FREQ = {material = 0.04, equipment = 0.02, treasure = 0.01, perp = 0.005}

-- 本世界本类箱子的【每区块实际出现概率】= 世界密度(surface.lua 滚的 random^2) × 基础频率 × 全局乘数。
--   storage.loot_density(默认1) 调【全局最大密度】：2 更多、0.5 更少。无世界密度则兜底 0.3。
local function spawn_chance(surface, kind)
    local style = storage.loot_style and storage.loot_style[surface.name]
    local wd = (style and style[kind]) or 0.3
    return wd * LOOT_FREQ[kind] * (storage.loot_density or 1)
end

-- 钢箱 = 材料箱：常见。【1~2 种物品、很多组】(同种叠多格)。每件 count = ss×random^1(偏多)，普通品质。
local function feat_material(surface, lt)
    if chunk_rng(lt, 503) > spawn_chance(surface, 'material') then return end
    place_filled_chest(surface, {lt.x + math.random(7, 25) + 0.5, lt.y + math.random(7, 25) + 0.5},
        'steel-chest', math.random(24, 50), LOOT_WEIGHTS.material, 1, math.random(1, 2))
end

-- 铁箱 = 设备箱：居中、【种类最杂】。抽 10~24 次不同物品，每件 count = ss×random^2，普通品质。
local function feat_equipment(surface, lt)
    if chunk_rng(lt, 557) > spawn_chance(surface, 'equipment') then return end
    place_filled_chest(surface, {lt.x + math.random(5, 27) + 0.5, lt.y + math.random(5, 27) + 0.5},
        'iron-chest', math.random(10, 24), LOOT_WEIGHTS.equipment, 2)
end

-- 木箱 = 宝箱：稀有。1~2 种高价值物品，每件【几个】(count = ss×random^4，极偏低)
local TREASURE_BOTTLE_CHANCE = 0.5   -- 木箱额外掉【科技瓶】的概率

local function feat_treasure(surface, lt)
    if chunk_rng(lt, 601) > spawn_chance(surface, 'treasure') then return end
    local pos = {lt.x + math.random(2, 29) + 0.5, lt.y + math.random(2, 29) + 0.5}
    if not surface.can_place_entity{name = 'wooden-chest', position = pos} then return end
    local chest = surface.create_entity{name = 'wooden-chest', force = 'neutral', position = pos}
    local inv = chest and chest.get_inventory(defines.inventory.chest)
    if not inv then return end
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

-- 永续(无底)箱：【独立特征】（不再寄生于普通箱的子概率）。频率很低；出生点保护由 guard_perpetual 内部处理。
local function feat_perpetual(surface, lt)
    if chunk_rng(lt, 605) > spawn_chance(surface, 'perp') then return end
    local pos = {lt.x + math.random(4, 27) + 0.5, lt.y + math.random(4, 27) + 0.5}
    if not surface.can_place_entity{name = 'steel-chest', position = pos} then return end
    if spawn_perpetual_chest(surface, pos) then
        guard_perpetual(surface, pos)   -- 永续箱周围放敌人守卫
    end
end

-- 按本星【独立开关】theme 构建敌人池（worm/spawner/turret/mine/art 各自有无）。
--   带弹的：gun-turret 每个各自随机弹种(mag=true，pick_mag)，artillery-turret 固定炮弹；无标记的不填弹。弹药加满。
local function danger_pool(t)
    local pool = {}
    if t.worm then pool[#pool + 1] = 'small-worm-turret'; pool[#pool + 1] = 'medium-worm-turret'; pool[#pool + 1] = 'big-worm-turret' end
    if t.spawner then pool[#pool + 1] = 'biter-spawner'; pool[#pool + 1] = 'spitter-spawner' end
    if t.mine then pool[#pool + 1] = 'land-mine' end
    if t.turret then pool[#pool + 1] = {name = 'gun-turret', mag = true} end
    if t.art then pool[#pool + 1] = {name = 'artillery-turret', ammo = 'artillery-shell'} end
    return pool
end
-- 单区块敌人放置【尝试】上限：哪怕最危险 + 最边缘也封顶，不致铺满整片。
local DANGER_MAX_PER_CHUNK = 10
-- 远离出生点(>96格)随机采样放敌方炮塔/虫巢/地雷/重炮。强度随【危险度 × 离地图中心比例】增长：
--   越靠近中心越少、越往边缘【刷新概率越高、数量越多】；但有 DANGER_MAX_PER_CHUNK 封顶。force='enemy'。
local function feat_danger(surface, lt, A, S, Z, W)
    local theme = storage.danger_theme and storage.danger_theme[surface.name]
    if not theme then return end
    local pool = danger_pool(theme)
    if #pool == 0 then return end

    -- 离中心比例 frac∈[0,1]（按区块中心算）。出生点 96 格内整块跳过。
    local ccx, ccy = lt.x + 16, lt.y + 16
    if ccx * ccx + ccy * ccy < 96 * 96 then return end
    local R = storage.radius_of[surface.name] or storage.radius or 2048
    local frac = math.min(1, math.sqrt(ccx * ccx + ccy * ccy) / R)

    -- 强度 = 危险度 × (0.25 + 0.75×离中心比例)，封顶 1：近中心弱、边缘强。
    local intensity = math.min(1, W.danger * (0.25 + 0.75 * frac))
    -- 尝试次数 = random(0, 上限)：半随机（有的区块空、有的成簇）；上限随 intensity 增长且封顶。
    local attempts = math.random(0, math.floor(intensity * DANGER_MAX_PER_CHUNK * (storage.danger_density or 1) + 0.5))
    if attempts <= 0 then return end
    local thr = 0.80 - 0.30 * intensity   -- intensity 越高 → 噪声门槛越低 → 命中概率越高（刷新概率越高）

    for _ = 1, attempts do
        local px, py = lt.x + math.random(0, 31), lt.y + math.random(0, 31)
        if px * px + py * py > 96 * 96
           and noise.fractal_warped(noise.octaves.blob, px, py, wseed(811), A, S, Z) > thr then
            local def = pool[math.random(#pool)]
            local name = type(def) == 'table' and def.name or def
            local pos = {x = px + 0.5, y = py + 0.5}
            if surface.can_place_entity{name = name, position = pos} then
                local e = surface.create_entity{name = name, force = 'enemy', position = pos}
                if e and type(def) == 'table' then
                    -- 机枪炮塔 per 个随机弹种(随本世界危险度)、重炮用炮弹；都加满
                    fill_turret_ammo(e, def.mag and pick_mag(W.danger) or def.ammo)
                end
            end
        end
    end
end

-- 危险世界偶现飞船残骸：机器人无法拆除 → 阻碍蓝图，作为障碍风味。force='neutral'。
local WRECKS = {
    'crash-site-spaceship-wreck-big-1', 'crash-site-spaceship-wreck-big-2',
    'crash-site-spaceship-wreck-medium-1', 'crash-site-spaceship-wreck-medium-2', 'crash-site-spaceship-wreck-medium-3',
    'crash-site-spaceship-wreck-small-1', 'crash-site-spaceship-wreck-small-2', 'crash-site-spaceship-wreck-small-3',
}
local function feat_wrecks(surface, lt, W)
    if not (storage.danger_theme and storage.danger_theme[surface.name]) then return end
    if chunk_rng(lt, 813) > 0.05 * W.danger * (storage.danger_density or 1) then return end
    local name = WRECKS[math.random(#WRECKS)]
    local pos = surface.find_non_colliding_position(name, {lt.x + math.random(4, 27), lt.y + math.random(4, 27)}, 12, 1)
    if pos then surface.create_entity{name = name, position = pos, force = 'neutral'} end
end

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
    theme_trees(surface, lt)
    -- 四类箱子各自独立(外观=内容)：每世界密度 random^2（surface.lua 滚定），频率互不相关。
    feat_material(surface, lt)    -- 钢箱：材料
    feat_equipment(surface, lt)   -- 铁箱：设备
    feat_treasure(surface, lt)    -- 木箱：宝箱
    feat_perpetual(surface, lt)   -- 永续箱：基础材料/矿物
    -- 危险世界（按 W.danger，与 exotic 正相关）：成簇敌方实体 + 偶现飞船残骸障碍。原版 enemy-base 仍自然出虫。
    feat_danger(surface, lt, A, S, Z, W)
    feat_wrecks(surface, lt, W)
end

return M
