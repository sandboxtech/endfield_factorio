-- 地图风味（原则：用噪声【修改 2.0 原生生成】，不用手动 stamp 去【覆盖】——原生地貌更自然）。
-- 因此本模块只做原生【做不到】的事；地貌(石/树/矿/水…)交回原生，由 surface.lua 用气候偏置/autoplace 调本轮风味。
--   · M.knobs()：本轮整局气质连续旋钮(繁茂/岩石/危险/富庶/异物)，与 surface.lua 共用 → 全局气质一致渐变。
--   · PLANET：目前空（手动放矿/废料表现不如原生，全交原生）；EXOTIC：跨星异物(原生无法跨星)，稀疏散布。
--   · 每特征从种子(storage.run+off)派生 strength：~60% 不出现，出现时立方偏置(多半小、极少大)。
--   · 树木主题 theme_trees：对【原生树】按本轮强度从原版色插值到目标色(连续，非离散世界) → 改原生，不覆盖。
--   · 通用风味：worm 虫群(force='enemy',仅母星)、随机木/铁/钢战利品箱(force='player',加权+品质)。
-- 由 surface.lua 的 on_chunk_generated 对各真实星球圆内区块调用 M.generate。
local noise = require('scripts.noise')

local M = {}

local function wseed(off) return (storage.run or 0) * 1009 + off end

-- 本轮【整局气质】连续旋钮（由 storage.run 确定性派生）：每个都是 [0,1) 连续量，不是硬编码离散概率——
-- 每轮整体氛围（繁茂↔荒芜、危险↔安宁、富庶↔贫瘠、寻常↔诡异）都是渐变的。
-- 同时供 surface.lua 调【2.0 原生 autoplace】(树/石密度) 与本模块手动特征门控共用 → 全局气质一致。
--   verdancy 植被繁茂  rockiness 岩石  danger 虫群危险(偏低)  riches 战利品(偏低)  exotic 异物倾向(很罕见)
function M.knobs()
    local function k(off, power)
        local v = noise.hash01(wseed(off) * 6.1)
        return power and v ^ power or v
    end
    -- 中心化：两个独立哈希之差 → 三角分布、集中在 0.5。多半接近原版，极端(极干极湿/极秃极茂)很罕见。
    local function kc(off)
        return 0.5 + (noise.hash01(wseed(off) * 6.1) - noise.hash01(wseed(off) * 3.7)) * 0.5
    end
    local exotic = k(809, 3)   -- 跨星球异物倾向（立方偏置，诡异世界很罕见）
    return {
        verdancy  = kc(801),      -- 树/草繁茂度（中心化：多半正常，极干/极茂罕见）
        rockiness = kc(803),      -- 岩石密度（中心化）
        riches    = k(807, 1.6),  -- 战利品丰度（曲线偏低）
        exotic    = exotic,
        -- 危险度：曲线偏低 + 与异物倾向【正相关】（诡异世界往往也更危险）。
        danger    = math.min(1, k(805, 2) * 0.7 + exotic * 0.7),
    }
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
-- 每类一个权重 w：先按 w 选类，再类内等概率选物品。【改 w 即调该类整体掉率】。永续箱排除 'science' 类。
local LOOT = {
    -- 原料/矿
    {cat = 'raw',        w = 10, items = {
        'iron-ore',  'copper-ore',  'coal',  'stone',  'uranium-ore',
        'holmium-ore',  'tungsten-ore',  'lithium',  'calcite',  'scrap',
        'raw-fish',  'carbon',  'wood',  
        -- 'ice',  'carbonic-asteroid-chunk',
        -- 'metallic-asteroid-chunk',  'oxide-asteroid-chunk',  'promethium-asteroid-chunk',
    }},
    -- 材料/中间品
    {cat = 'material',   w = 30, items = {
        'iron-plate',  'copper-plate',  'steel-plate',  'plastic-bar',  'stone-brick',
        'iron-gear-wheel',  'copper-cable',  'iron-stick',  'electronic-circuit',  'advanced-circuit',
        'processing-unit',  'engine-unit',  'electric-engine-unit',  'flying-robot-frame',  'low-density-structure',
        'rocket-fuel',  'solid-fuel',  'battery',  'explosives',  'sulfur',
        'uranium-235',  'uranium-238',  'uranium-fuel-cell',  'depleted-uranium-fuel-cell',  'fusion-power-cell',
        'tungsten-carbide',  'tungsten-plate',  'holmium-plate',  'lithium-plate',  'carbon-fiber',
        'superconductor',  'supercapacitor',  'quantum-processor',  'concrete',  'refined-concrete',
        'hazard-concrete',  'refined-hazard-concrete',  'landfill',  'barrel',  'nuclear-fuel',
    }},
    -- 物流(带/臂/管/箱/轨/机器人)
    {cat = 'logistics',  w =  15, items = {
        'transport-belt',  'fast-transport-belt',  'express-transport-belt',  'turbo-transport-belt',  'underground-belt',
        'fast-underground-belt',  'express-underground-belt',  'turbo-underground-belt',  'splitter',  'fast-splitter',
        'express-splitter',  'turbo-splitter',  'loader',  'fast-loader',  'express-loader',
        'inserter',  'burner-inserter',  'long-handed-inserter',  'fast-inserter',  'bulk-inserter',
        'stack-inserter',  'pipe',  'pipe-to-ground',  'pump',  'offshore-pump',
        'storage-tank',  'wooden-chest',  'iron-chest',  'steel-chest',  'active-provider-chest',
        'passive-provider-chest',  'storage-chest',  'buffer-chest',  'requester-chest',  'construction-robot',
        'logistic-robot',  'roboport',  'rail',  'rail-signal',  'rail-chain-signal',
        'rail-ramp',  'rail-support',  'train-stop',  'locomotive',  'cargo-wagon',
        'fluid-wagon',  'repair-pack',
    }},
    -- 电路信号
    {cat = 'circuit',    w =  2, items = {
        'arithmetic-combinator',  'decider-combinator',  'constant-combinator',  'selector-combinator',  'programmable-speaker', 'display-panel', 'small-lamp',
    }},
    -- 电力(发电/蓄电/电杆/热)
    {cat = 'power',      w =  7, items = {
        'boiler',  'steam-engine',  'steam-turbine',  'heat-exchanger',  'heat-pipe',
        'nuclear-reactor',  'solar-panel',  'accumulator',  'fusion-reactor',  'fusion-generator',
        'power-switch',  'small-electric-pole',  'medium-electric-pole',  'big-electric-pole',  'substation',
        'lightning-collector',  'lightning-rod',  'heating-tower',
    }},
    -- 生产机器
    {cat = 'production', w =  15, items = {
        'assembling-machine-1',  'assembling-machine-2',  'assembling-machine-3',  'stone-furnace',  'steel-furnace',
        'electric-furnace',  'electric-mining-drill',  'big-mining-drill',  'burner-mining-drill',  'pumpjack',
        'oil-refinery',  'chemical-plant',  'centrifuge',  'lab',  'biolab',
        'beacon',  'foundry',  'recycler',  'electromagnetic-plant',  'cryogenic-plant',
        'biochamber',  'crusher',  'agricultural-tower',  'rocket-silo',
    }},
    -- 模块
    {cat = 'module',     w =  15, items = {
        'speed-module',  'speed-module-2',  'speed-module-3',  'efficiency-module',  'efficiency-module-2',
        'efficiency-module-3',  'productivity-module',  'productivity-module-2',  'productivity-module-3',  'quality-module',
        'quality-module-2',  'quality-module-3',
    }},
    -- 军事(炮塔/枪/弹/胶囊/墙)
    {cat = 'military',   w =  8, items = {
        'gun-turret',  'laser-turret',  'flamethrower-turret',  'artillery-turret',  'rocket-turret',
        'railgun-turret',  'tesla-turret',  'land-mine',  'stone-wall',  'gate',
        'radar',  'artillery-wagon',  'pistol',  'submachine-gun',  'shotgun',
        'combat-shotgun',  'flamethrower',  'rocket-launcher',  'railgun',  'teslagun',
        'firearm-magazine',  'piercing-rounds-magazine',  'uranium-rounds-magazine',  'shotgun-shell',  'piercing-shotgun-shell',
        'cannon-shell',  'explosive-cannon-shell',  'uranium-cannon-shell',  'explosive-uranium-cannon-shell',  'rocket',
        'explosive-rocket',  'flamethrower-ammo',  'artillery-shell',  'railgun-ammo',  'tesla-ammo',
        'atomic-bomb',  'grenade',  'cluster-grenade',  'poison-capsule',  'slowdown-capsule',
        'defender-capsule',  'distractor-capsule',  'destroyer-capsule',  'capture-robot-rocket',  'cliff-explosives',
        'discharge-defense-remote',  'artillery-targeting-remote',
    }},
    -- 护甲与装备
    {cat = 'equipment',  w =  3, items = {
        'light-armor',  'heavy-armor',  'modular-armor',  'power-armor',  'power-armor-mk2',
        'mech-armor',  'solar-panel-equipment',  'battery-equipment',  'battery-mk2-equipment',  'battery-mk3-equipment',
        'belt-immunity-equipment',  'energy-shield-equipment',  'energy-shield-mk2-equipment',  'exoskeleton-equipment',  'personal-roboport-equipment',
        'personal-roboport-mk2-equipment',  'personal-laser-defense-equipment',  'night-vision-equipment',  'discharge-defense-equipment',  'fission-reactor-equipment',
        'fusion-reactor-equipment',  'toolbelt-equipment',
    }},
    -- 科技瓶(永续箱不出)
    {cat = 'science',    w =  36, items = {   -- 已删可腐的 agricultural-science-pack
        'automation-science-pack',  'logistic-science-pack',  'military-science-pack',  'chemical-science-pack',  'production-science-pack',
        'utility-science-pack',  'space-science-pack',  'metallurgic-science-pack',  'electromagnetic-science-pack',
        'cryogenic-science-pack',  'promethium-science-pack',
    }},
    -- 生物/农业（已删蛋与一切可腐物，只留不腐烂的种子/土壤）
    {cat = 'gleba',      w =  5, items = {
        'jellynut-seed',  'yumako-seed',  'tree-seed',  'artificial-jellynut-soil',  'artificial-yumako-soil',
        'overgrowth-jellynut-soil',  'overgrowth-yumako-soil',
    }},
    -- 太空/平台
    {cat = 'space',      w =  1, items = {
        'foundation',  'space-platform-foundation',  'space-platform-starter-pack',  'ice-platform',  'cargo-bay',
        'cargo-landing-pad',  'asteroid-collector',  'thruster',  'satellite',
    }},
    -- 载具
    {cat = 'vehicle',    w =  1, items = {
        'car',  'tank',  'spidertron',
    }},
}

-- 按【类权重 w】选类、类内等概率选物品；skip_cat 跳过某类（永续箱传 'science' → 不出科技瓶）。
-- 用 ipairs 顺序确定 → 多人各端一致，math.random 取值不会 desync。
local function pick_loot(skip_cat)
    local total = 0
    for _, c in ipairs(LOOT) do
        if c.cat ~= skip_cat then total = total + c.w end
    end
    local roll = math.random() * total
    for _, c in ipairs(LOOT) do
        if c.cat ~= skip_cat then
            roll = roll - c.w
            if roll <= 0 then return c.items[math.random(#c.items)] end
        end
    end
    return LOOT[1].items[1]   -- 理论到不了的兜底
end

-- 单件数量：1 到该物品 1 组(堆叠数)，按 random()² 偏低分布（多数小堆，偶尔接近满堆）。
local function loot_count(name)
    local proto = prototypes.item[name]
    local ss = (proto and proto.stack_size) or 1
    return math.max(1, math.ceil(ss * math.random() ^ 2))
end

-- 随机品质（2.0 SA 特性，1.0 战利品没有）：多数 normal，小概率 uncommon/rare → 开箱偶有惊喜。
local function roll_quality()
    local r = math.random()
    if r < 0.0003 then return 'legendary' end
    if r < 0.003 then return 'epic' end
    if r < 0.03 then return 'rare' end
    if r < 0.15 then return 'uncommon' end
    return 'normal'
end

-- 可机器人拆除的随机箱体：木/铁/钢（不再只钢箱）。
local CHESTS = {'wooden-chest', 'iron-chest', 'steel-chest'}

local function fill_loot(chest, n)
    local inv = chest.get_inventory(defines.inventory.chest)
    if not inv then return end
    n = math.min(n, #inv)   -- 抽取次数不超过箱子格数：小箱(木16)也能装满，又不溢出浪费
    for _ = 1, n do
        local name = pick_loot()
        inv.insert{name = name, count = loot_count(name), quality = roll_quality()}
    end
end

-- 永续箱奖励（罕见）：随机一种物品无限供应。设为【不可打开/不可拆走、可摧毁】，
-- 防止滥用又能就地用（接机械臂/传送带）。force=neutral（不进蓝图；机械臂仍可从中抽货）。
local function spawn_perpetual_chest(surface, pos)
    local chest = surface.create_entity{name = 'infinity-chest', force = 'neutral', position = pos}
    if not chest then return end
    local item = pick_loot('science')   -- 永续箱不出科技瓶
    local ss = prototypes.item[item] and prototypes.item[item].stack_size or 50
    chest.infinity_container_filters = {{index = 1, name = item, count = ss, mode = 'exactly'}}
    chest.operable = false        -- 不可打开/重配
    chest.minable_flag = false    -- 不可拆走
    chest.destructible = true     -- 可摧毁
end

-- 永续箱守卫：只在【永续箱】四周放敌人(force=enemy)，普通箱【不放】。从 机枪炮塔/沙虫/地雷/重炮 随机抽，数量较多。
--   机枪炮塔用本星弹种(theme.mag，兜底机枪弹)、重炮用炮弹；沙虫/地雷不用弹。出生点附近(<64格)不放（保护新手）。
local PERP_GUARD_POOL = {
    {name = 'gun-turret', mag = true, n = 20},                     -- 机枪炮塔（本星弹）
    'small-worm-turret', 'medium-worm-turret', 'big-worm-turret',  -- 沙虫
    'land-mine',                                                   -- 地雷
    {name = 'artillery-turret', ammo = 'artillery-shell', n = 4},  -- 重炮（炮弹）
}
local function guard_perpetual(surface, pos)
    local dist = math.sqrt(pos.x * pos.x + pos.y * pos.y)
    if dist < 64 then return end                          -- 出生点保护半径内不放
    local theme = storage.danger_theme and storage.danger_theme[surface.name]
    local mag = theme and theme.mag                       -- 本星弹种
    for _ = 1, math.random(6, 12) do
        local def = PERP_GUARD_POOL[math.random(#PERP_GUARD_POOL)]
        local name = type(def) == 'table' and def.name or def
        local ang, r = math.random() * 2 * math.pi, 3 + math.random() * 5
        local gp = {x = pos.x + math.cos(ang) * r, y = pos.y + math.sin(ang) * r}
        local sp = surface.find_non_colliding_position(name, gp, 5, 1)
        if sp then
            local e = surface.create_entity{name = name, force = 'enemy', position = sp}
            if e and type(def) == 'table' then
                local ammo = def.mag and (mag or 'firearm-magazine') or def.ammo   -- 机枪用本星弹；重炮用炮弹
                if ammo then e.insert{name = ammo, count = def.n} end
            end
        end
    end
end

-- 放一个战利品箱：小概率是永续箱奖励(四周放敌人守卫)，否则普通木/铁/钢箱 + 战利品(不放敌人)。pos = {x+0.5, y+0.5}。
-- test_scale(默认1)缩放本次永续箱概率：宝箱传 <1 让它更难刷出永续箱。
local function place_loot_chest(surface, pos, n, test_scale)
    if not surface.can_place_entity{name = 'steel-chest', position = pos} then return end
    -- 每世界独立的战利品风格（surface.lua 滚定）：哪些箱体 + 永续箱概率。无则兜底默认。
    local style = storage.loot_style and storage.loot_style[surface.name]
    local chests = (style and style.chests) or CHESTS
    local test = ((style and style.test) or (storage.test_chest_chance or 0.06)) * (test_scale or 1)   -- 0 也是合法值(本世界不出永续箱)
    if math.random() < test then
        spawn_perpetual_chest(surface, pos)
        guard_perpetual(surface, pos)   -- 只有永续箱周围放敌人
    else
        local chest = surface.create_entity{name = chests[math.random(#chests)], force = 'neutral', position = pos}
        if chest then fill_loot(chest, n) end
    end
end

-- 区块级确定性随机 [0,1)：点状稀有风味用。
local function chunk_rng(lt, off)
    return noise.hash01(lt.x * 0.1234 + lt.y * 0.3717 + off * 1.7 + (storage.run or 0) * 0.011)
end

-- 每世界战利品密度乘数（surface.lua 滚定，恒 >0 → 每个世界都有箱子，只是概率不等）。无则兜底 1。
local function loot_rate(surface)
    local style = storage.loot_style and storage.loot_style[surface.name]
    return (style and style.rate) or 1
end

-- 物资箱（原"坠机点"）：战利品多、装得满。箱子 force=neutral（可开/可拿/可手拆，但不进蓝图；永续箱接机械臂照常）。
-- 频率随【本世界密度 × 富庶度】渐变（每世界都有，概率不等）。
local function feat_crash_site(surface, lt, W)
    if chunk_rng(lt, 503) > loot_rate(surface) * (0.02 + 0.06 * (W and W.riches or 0)) then return end
    place_loot_chest(surface, {lt.x + math.random(7, 25) + 0.5, lt.y + math.random(7, 25) + 0.5}, math.random(24, 50))
end

-- 宝箱缓存（单个箱）：更稀有但也装得满些。箱子 force=neutral。频率随【本世界密度 × 富庶度】渐变。
-- 永续箱概率额外 ×0.3（比物资箱更难出永续箱）。
local function feat_treasure(surface, lt, W)
    if chunk_rng(lt, 601) > loot_rate(surface) * (0.015 + 0.05 * (W and W.riches or 0)) then return end
    place_loot_chest(surface, {lt.x + math.random(2, 29) + 0.5, lt.y + math.random(2, 29) + 0.5}, math.random(12, 28), 0.3)
end

-- 按本星【独立开关】theme 构建敌人池（worm/spawner/turret/mine/art 各自有无）。
--   带弹的：gun-turret 用本星弹种 theme.mag(mag=true)，artillery-turret 固定炮弹；无标记的不填弹。
local function danger_pool(t)
    local pool = {}
    if t.worm then pool[#pool + 1] = 'small-worm-turret'; pool[#pool + 1] = 'medium-worm-turret'; pool[#pool + 1] = 'big-worm-turret' end
    if t.spawner then pool[#pool + 1] = 'biter-spawner'; pool[#pool + 1] = 'spitter-spawner' end
    if t.mine then pool[#pool + 1] = 'land-mine' end
    if t.turret then pool[#pool + 1] = {name = 'gun-turret', mag = true, n = 20} end
    if t.art then pool[#pool + 1] = {name = 'artillery-turret', ammo = 'artillery-shell', n = 4} end
    return pool
end
-- 远离出生点(>96格)随机采样放敌人；数量随危险度 × storage.danger_density。force='enemy'。
local function feat_danger(surface, lt, A, S, Z, W)
    local theme = storage.danger_theme and storage.danger_theme[surface.name]
    if not theme then return end
    local pool = danger_pool(theme)
    if #pool == 0 then return end
    local danger = W.danger
    local thr = 0.78 - 0.25 * danger
    for _ = 1, math.random(0, math.ceil(danger * 12 * (storage.danger_density or 1))) do
        local px, py = lt.x + math.random(0, 31), lt.y + math.random(0, 31)
        if px * px + py * py > 96 * 96
           and noise.fractal_warped(noise.octaves.blob, px, py, wseed(811), A, S, Z) > thr then
            local def = pool[math.random(#pool)]
            local name = type(def) == 'table' and def.name or def
            local pos = {x = px + 0.5, y = py + 0.5}
            if surface.can_place_entity{name = name, position = pos} then
                local e = surface.create_entity{name = name, force = 'enemy', position = pos}
                if e and type(def) == 'table' then
                    local ammo = def.mag and theme.mag or def.ammo   -- 机枪用本星弹种；重炮用炮弹
                    if ammo then e.insert{name = ammo, count = def.n} end
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
    local A, S, Z = noise.seeded_transform(wseed(7))
    local home = PLANET[surface.name]
    if home then
        for _, def in ipairs(home) do place_feature(surface, lt, def, A, S, Z, W) end
    end
    for _, def in ipairs(EXOTIC) do place_feature(surface, lt, def, A, S, Z, W) end
    theme_trees(surface, lt)
    feat_crash_site(surface, lt, W)
    feat_treasure(surface, lt, W)
    -- 危险世界（按 W.danger，与 exotic 正相关）：成簇敌方实体 + 偶现飞船残骸障碍。原版 enemy-base 仍自然出虫。
    feat_danger(surface, lt, A, S, Z, W)
    feat_wrecks(surface, lt, W)
end

return M
