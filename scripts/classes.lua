-- 职业系统：每个职业决定开局发什么物品。玩家随时在【职业】窗口切换（同时只能一种，存 storage.player_class[名]，带短冷却）。
-- 进服默认 = 出租司机 civilian（未选 → 按默认职业，见 M.DEFAULT / selected_key 兜底）。
--
-- 【职业表存 storage.classes，可热改】：DEFAULT_CLASSES 只是初始默认，M.ensure() 深拷贝进 storage.classes。
--   /c storage.classes[2].full = 1000   改某职业满级线；  /c storage.classes = nil  清空恢复默认。
--   也可整体热更：把 set_classes.txt 全文粘进控制台（/sc storage.classes = {...}）。
--
-- 字段：
--   name     职业显示名（中文字符串，直接显示、绕过 locale）。
--   full     职业级满级线（可选，默认 MAX_LEVEL=100000=最大等级10万）：该职业每种相关瓶练到 full 级，即拿满所有 rewards 的
--            groups 组——这就是这个职业的“完美追求”目标等级。full 三档：基础速成 1000 / 进阶 10000 / 终极 100000(默认)；
--            full 越大越难满、满级回报越丰厚。价值高低主要靠物品档次体现(廉价职业=低 full，稀有/终极职业=高 full)。
--   starter  无条件初始物品列表：每条 {item=物品, count=个数 或 groups=组数}；count 个 > groups 组 > 默认 1 组。
--   rewards  经验奖励列表：每条 {pack=瓶, item=物品, groups=满配额组数}；按该瓶等级线性发，
--            个数 = floor(堆叠 × groups × min(瓶等级, full) / full)。pack 按物品在科技树的解锁层级配。
--   unlock   解锁条件(可选)：每条 {pack=瓶, level=级}，需全满足；无则人人可选。
--   techs    职业【专属科技】(可选，数组)：只要存在选了该职业的玩家(含离线)，开局把这些科技标记已研究(reset 调 M.active_class_unlocks)。
--            如 techs = {'logistics', 'automation-2'}。
--   recipes  职业【专属配方】(可选，数组)：同上，但开局解锁配方(force 级 enabled，无需对应科技。reset 调 M.active_class_unlocks)。如 recipes = {'rail', 'pistol'}。
--   {}       空表 = 占位，在职业窗口里作【换行/分组】分隔（无 key，选不到）。
--
-- 【容量约束】每个职业「满级资源含量」（starter 固定组 + 各 rewards 满级 groups 之和）控制在 50 组以内。
--
local constants = require('scripts.constants')
local passives = require('scripts.passives')

local M = {}

M.DEFAULT = 'civilian'
M.MAX_LEVEL = constants.MAX_LEVEL   -- 满级基准=最大等级（单一来源 constants.MAX_LEVEL）；未配 full 的职业兜底用它

-- 职业满级线 full 三档常量（DEFAULT_CLASSES 引用；gen_set_classes.py 生成 set_classes 时会自动替换成数字）。
local FULL_LOW = 1000         -- 基础速成档
local FULL_MID = 10000        -- 进阶档
local FULL_MAX = 100000       -- 终极档（= MAX_LEVEL，练到满级正好拿满）

-- 默认职业表（顺序即面板显示顺序），分组：基础生产 / 能源化工 / 物流 / 战斗 / 装备护甲 / 农牧 / 星球专精，空职业 {} 分隔。
local DEFAULT_CLASSES = {
    -- ── 基础生产组（红瓶起步：矿/板/齿轮/电路，满级线低 full=100，开局速成大宗）──
    -- 默认职业。
    {section = '市民'}, 

    {key = 'civilian', name = '核能出租司机', full = FULL_LOW, starter = {
        {item = 'car', count = 1},
        {item = 'nuclear-fuel', groups = 1},
        {item = 'automation-science-pack',   count = 1},
    }, rewards = {
        {pack = 'automation-science-pack', item = 'nuclear-fuel',   groups = 10},
        {pack = 'space-science-pack', item = 'nuclear-fuel',   groups = 10},
        {pack = 'promethium-science-pack', item = 'nuclear-fuel',   groups = 10},
    }},

    {key = 'afker', techs = {'research-productivity'}, name = '挂机大师', full = FULL_MAX, starter = {
        {item = 'logistic-science-pack',   count = 1},
    }, rewards = {
        
    }},

    {key = 'philosopher', techs = {'biolab'}, name = '哲学大师', full = FULL_LOW, starter = {
        {item = 'chemical-science-pack',   count = 1},
    }, rewards = {
        {pack = 'logistic-science-pack', item = 'logistic-science-pack',   count=10},
    }},

    {key = 'artist', techs = {'circuit-network'}, name = '艺术大师', full = FULL_LOW, starter = {
        {item = 'small-lamp', groups = 1},
        {item = 'constant-combinator', count = 1},
    }, rewards = {
        {pack = 'automation-science-pack',    item = 'constant-combinator',  groups = 5},   -- 绿：常量运算器(配色信号)
        {pack = 'logistic-science-pack',  item = 'small-lamp',           groups = 5},  -- 红：小灯(像素画)
        {pack = 'logistic-science-pack',    item = 'display-panel',        groups = 5},  -- 绿：显示屏
        {pack = 'promethium-science-pack',    item = 'programmable-speaker', groups = 5},
    }},

    {key = 'programmer', techs = {'advanced-combinators'}, name = '计算机专家', full = FULL_LOW, starter = {
        {item = 'selector-combinator', groups = 1},
        {item = 'arithmetic-combinator', groups = 1},
        {item = 'decider-combinator', groups = 1},
    }, rewards = {
        {pack = 'automation-science-pack',  item = 'constant-combinator',   groups = 5},  -- 紫：常量运算器
        {pack = 'logistic-science-pack',   item = 'decider-combinator',    groups = 5},  -- 绿：判断运算器
        {pack = 'logistic-science-pack',   item = 'arithmetic-combinator', groups = 5},  -- 绿：算术运算器
        {pack = 'promethium-science-pack',   item = 'selector-combinator',   groups = 5},  -- 蓝：选择运算器(高级运算器)
    }},

    {key = 'inventor', techs = {
        'research-speed-1',
        'research-speed-2',
        'research-speed-3',
        'research-speed-4',
        'research-speed-5',
        'research-speed-6',
    }, name = '发明家', full = FULL_LOW, starter = {
        {item = 'lab', groups = 1},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'lab',                 groups = 10},
        {pack = 'space-science-pack', item = 'lab',                 groups = 10},
        {pack = 'promethium-science-pack', item = 'lab',                 groups = 10},
    }},

    {key = 'civilengineer', techs = {'cliff-explosives'}, name = '建筑大师', full = FULL_LOW, starter = {
        {item = 'cliff-explosives', groups = 1},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'stone-brick',                 groups = 10},
        {pack = 'logistic-science-pack', item = 'concrete',                 groups = 10},
        {pack = 'space-science-pack', item = 'refined-concrete',                 groups = 10},
        {pack = 'promethium-science-pack', item = 'foundation',                 groups = 10},
    }},

    {key = 'banker', name = '大资本家', full = FULL_MAX, starter = {

    }, unlock = {{pack = 'automation-science-pack', level = 1000}}, rewards = {
        {pack = 'automation-science-pack', item = 'coin',   count = 100},
        {pack = 'logistic-science-pack', item = 'coin',   count = 100},
        {pack = 'military-science-pack', item = 'coin',   count = 100},
        {pack = 'chemical-science-pack', item = 'coin',   count = 100},
        {pack = 'production-science-pack', item = 'coin',   count = 100},
        {pack = 'utility-science-pack', item = 'coin',   count = 100},
        {pack = 'space-science-pack', item = 'coin', count = 100},
        --
        {pack = 'metallurgic-science-pack',     item = 'coin', count = 100},
        {pack = 'electromagnetic-science-pack', item = 'coin',  count = 100},
        {pack = 'agricultural-science-pack', item = 'coin', count = 100},
        {pack = 'cryogenic-science-pack', item = 'coin', count = 100},
        {pack = 'promethium-science-pack', item = 'coin', count = 100},
    }},

    {section = '杂货商人'}, 
    -- 矿物
    {key = 'oreman', techs = {'mining-productivity-1', 'mining-productivity-2'}, name = '矿物商人', full = FULL_LOW, starter = {
        {item = 'iron-ore', groups = 6},
        {item = 'copper-ore', groups = 6},
        {item = 'stone', groups = 6},
        {item = 'coal', groups = 6},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        -- {pack = 'automation-science-pack',      item = 'iron-ore',     groups = 1},   -- 红：铁矿
        -- {pack = 'logistic-science-pack',        item = 'copper-ore',   groups = 1},   -- 绿：铜矿
        -- {pack = 'military-science-pack',        item = 'coal',         groups = 1},   -- 灰：煤
        -- {pack = 'chemical-science-pack',        item = 'stone',  groups = 1},   -- 蓝：铀矿(需硫酸,蓝瓶时代)
        -- {pack = 'production-science-pack',      item = 'iron-ore',        groups = 1},   -- 紫：石头
        -- {pack = 'utility-science-pack',      item = 'copper-ore',        groups = 1},   -- 紫：石头
        {pack = 'space-science-pack', item = 'uranium-ore', groups = 4},

        {pack = 'metallurgic-science-pack',     item = 'tungsten-ore', groups = 4},   -- 橙：钨矿(火山)
        {pack = 'metallurgic-science-pack',     item = 'calcite',      groups = 4},   -- 橙：方解石(火山)
        {pack = 'electromagnetic-science-pack', item = 'holmium-ore',  groups = 4},   -- 粉：钬矿(电浆星)
        {pack = 'electromagnetic-science-pack', item = 'scrap',        groups = 4},   -- 粉：废料(电浆星)
        {pack = 'agricultural-science-pack', item = 'stone', groups = 4},
        {pack = 'agricultural-science-pack', item = 'carbon', groups = 4},
        {pack = 'cryogenic-science-pack', item = 'lithium', groups = 4},
        {pack = 'promethium-science-pack', item = 'promethium-asteroid-chunk', groups = 1},
    }},

    -- 材料
    {key = 'material', techs = {'low-density-structure', 'kovarex-enrichment-process'}, name = '材料商人', full = FULL_LOW, starter = {
        {item = 'iron-plate', groups = 8},
        {item = 'copper-plate', groups = 2},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'iron-plate',   groups = 1},
        {pack = 'logistic-science-pack', item = 'copper-plate',   groups = 1},
        {pack = 'military-science-pack', item = 'stone-brick',   groups = 1},
        {pack = 'chemical-science-pack', item = 'plastic-bar',   groups = 1},
        {pack = 'production-science-pack', item = 'steel-plate',   groups = 1},
        {pack = 'utility-science-pack', item = 'sulfur',   groups = 1},
        {pack = 'space-science-pack', item = 'uranium-238', groups = 1},
        --
        {pack = 'metallurgic-science-pack',     item = 'tungsten-carbide', groups = 1},
        {pack = 'metallurgic-science-pack',     item = 'tungsten-plate', groups = 1},
        {pack = 'electromagnetic-science-pack', item = 'holmium-plate',  groups = 1},
        {pack = 'agricultural-science-pack', item = 'carbon-fiber', groups = 1},
        {pack = 'cryogenic-science-pack', item = 'lithium-plate', groups = 1},
        {pack = 'promethium-science-pack', item = 'uranium-235', groups = 1},
    }},

    -- 能源
    {key = 'energytrader', techs = {'rocket-fuel', 'kovarex-enrichment-process'}, name = '能源商人', full = FULL_LOW, starter = {
        {item = 'coal', groups = 10},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'coal',      groups = 5},
        {pack = 'logistic-science-pack', item = 'solid-fuel',      groups = 5},
        {pack = 'chemical-science-pack', item = 'rocket-fuel', groups = 5},
        {pack = 'space-science-pack', item = 'carbon', groups = 5},
        {pack = 'promethium-science-pack', item = 'nuclear-fuel', groups = 5},
    }},

    {key = 'producttrader', techs = {'electronics', 'advanced-circuit', 'processing-unit'},  name = '产品商人', full = FULL_LOW, starter = {
        {item = 'electronic-circuit', count = 200},
        {item = 'iron-gear-wheel', count = 200},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'iron-gear-wheel',   groups = 5},
        {pack = 'logistic-science-pack', item = 'electronic-circuit',   groups = 5},
        {pack = 'military-science-pack', item = 'engine-unit',   groups = 2},
        {pack = 'chemical-science-pack', item = 'advanced-circuit',   groups = 2},
        {pack = 'production-science-pack', item = 'electric-engine-unit',   groups = 2},
        {pack = 'utility-science-pack', item = 'flying-robot-frame',   groups = 2},
        {pack = 'cryogenic-science-pack', item = 'processing-unit', groups = 2},
    }},

    {section = '生产'},   -- 分区标题（无 key，职业窗口里渲染成粗体小标题）

    {key = 'miner', techs = {'electric-mining-drill'}, name = '采矿工人', full = FULL_MID, starter = {
        {item = 'burner-mining-drill', groups = 2},
        -- {item = 'electric-mining-drill', groups = 1},
        -- {item = 'big-mining-drill', groups = 1},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack',     item = 'electric-mining-drill', groups = 20},
        {pack = 'metallurgic-science-pack', item = 'big-mining-drill', groups = 2},
    }},

    {key = 'smelter', techs = {'advanced-material-processing', 'advanced-material-processing-2'}, name = '煅烧工人', full = FULL_MID, starter = {
        {item = 'stone-furnace', groups = 6},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'stone-furnace',       groups = 20},
        {pack = 'logistic-science-pack', item = 'steel-furnace',       groups = 5},
        {pack = 'chemical-science-pack', item = 'electric-furnace',   groups = 2},
    }},

    {key = 'artisan', techs = {'automation', 'automation-2'}, name = '装配工人', full = FULL_MID, starter = {
        {item = 'assembling-machine-1', groups = 1},
        -- {item = 'assembling-machine-2', groups = 1},
        -- {item = 'assembling-machine-3', groups = 1},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'assembling-machine-1', groups = 10},
        {pack = 'logistic-science-pack',   item = 'assembling-machine-2', groups = 10},
        {pack = 'production-science-pack', item = 'assembling-machine-3', groups = 10},
    }},

    {key = 'foundryman', techs = {'foundry'}, name = '冶金工人', full = FULL_LOW, starter = {
        {item = 'foundry', count = 5},
    }, unlock = {{pack = 'metallurgic-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'calcite',                 groups = 10},
        {pack = 'space-science-pack', item = 'calcite',                 groups = 10},
        {pack = 'metallurgic-science-pack', item = 'calcite',                 groups = 10},
        {pack = 'promethium-science-pack', item = 'calcite',                 groups = 10},
    }},
    {key = 'electromagneticman', techs = {'electromagnetic-plant'}, name = '电子工人', full = FULL_LOW, starter = {
        {item = 'electromagnetic-plant', count = 5},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'copper-cable',                 groups = 10},
        {pack = 'space-science-pack', item = 'copper-cable',                 groups = 10},
        {pack = 'electromagnetic-science-pack', item = 'copper-cable',                 groups = 10},
        {pack = 'promethium-science-pack', item = 'copper-cable',                 groups = 10},
    }},
    {key = 'recyclerman', techs = {'recycling'}, name = '回收工人', full = FULL_LOW, starter = {
        {item = 'recycler', count = 5},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'scrap',                 groups = 10},
        {pack = 'space-science-pack', item = 'scrap',                 groups = 10},
        {pack = 'electromagnetic-science-pack', item = 'scrap',                 groups = 10},
        {pack = 'promethium-science-pack', item = 'scrap',                 groups = 10},
    }},
    {key = 'oilman', techs = {'oil-gathering', 'oil-processing', 'advanced-oil-processing'}, name = '石化工人', full = FULL_LOW, starter = {
        {item = 'pumpjack', groups = 1},
        {item = 'oil-refinery', groups = 1},
        {item = 'chemical-plant', groups = 1},
    }, unlock = {{pack = 'logistic-science-pack', level = 10}}, rewards = {
        {pack = 'logistic-science-pack',   item = 'pumpjack',       groups = 10}, 
        {pack = 'logistic-science-pack',   item = 'oil-refinery',   groups = 10}, 
        {pack = 'logistic-science-pack',   item = 'chemical-plant', groups = 10}, 
        {pack = 'agricultural-science-pack',   item = 'biochamber', groups = 2}, 
        {pack = 'cryogenic-science-pack',   item = 'cryogenic-plant', groups = 2}, 
    }},

    {key = 'moduler', techs = {'modules'}, name = '插件工人', full = FULL_MID, starter = {
        {item = 'beacon', count = 10},
        {item = 'speed-module', count = 10},
        {item = 'efficiency-module', count = 10},
    }, unlock = {{pack = 'production-science-pack', level = 10}}, rewards = {
        {pack = 'production-science-pack', item = 'beacon', groups = 10},
        {pack = 'space-science-pack', item = 'beacon', groups = 10},
        {pack = 'promethium-science-pack', item = 'beacon', groups = 10},
        --
        {pack = 'metallurgic-science-pack',     item = 'speed-module-2', groups = 2},
        {pack = 'agricultural-science-pack', item = 'efficiency-module-2', groups = 2},
    }},

    {key = 'qualityman', techs = {'quality-module', 'processing-unit-productivity'}, name = '品质大师', full = FULL_MAX, starter = {
        {item = 'quality-module', groups = 1},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 10}}, rewards = {
        {pack = 'chemical-science-pack',        item = 'quality-module',     groups = 10},   -- 蓝：1级
        {pack = 'space-science-pack',           item = 'quality-module-2',   groups = 5},   -- 白：2级
        {pack = 'electromagnetic-science-pack', item = 'quality-module-3',   groups = 2},   -- 粉：3级(电浆星)
    }},
    {key = 'speedman', techs = {'speed-module', 'low-density-structure-productivity'}, name = '速度大师', full = FULL_MAX, starter = {
        {item = 'speed-module', groups = 1},
    }, unlock = {{pack = 'metallurgic-science-pack', level = 10}}, rewards = {
        {pack = 'chemical-science-pack',    item = 'speed-module',     groups = 10},   -- 蓝：1级
        {pack = 'space-science-pack',       item = 'speed-module-2',   groups = 5},   -- 白：2级
        {pack = 'metallurgic-science-pack', item = 'speed-module-3',   groups = 2},   -- 橙：3级(火山)
    }},
    {key = 'efficiencyman', techs = {'efficiency-module', 'rocket-fuel-productivity'}, name = '节能大师', full = FULL_MAX, starter = {
        {item = 'efficiency-module', groups = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 10}}, rewards = {
        {pack = 'chemical-science-pack',     item = 'efficiency-module',     groups = 10},   -- 蓝：1级
        {pack = 'space-science-pack',        item = 'efficiency-module-2',   groups = 5},   -- 白：2级
        {pack = 'agricultural-science-pack', item = 'efficiency-module-3',   groups = 2},   -- 草：3级(Gleba)
    }},
    {key = 'productivityman', techs = {'productivity-module', 'processing-unit-productivity'}, name = '产能大师', full = FULL_MAX, starter = {
        {item = 'productivity-module', groups = 1},
    }, unlock = {{pack = 'cryogenic-science-pack', level = 10}}, rewards = {
        {pack = 'chemical-science-pack',  item = 'productivity-module',     groups = 10},   -- 蓝：1级
        {pack = 'space-science-pack',     item = 'productivity-module-2',   groups = 5},   -- 白：2级
        {pack = 'cryogenic-science-pack', item = 'productivity-module-3',   groups = 2},   -- 靛：3级(Aquilo)
    }},


    {section = '能源 · 物流'},
    -- 分组换行：基础生产 ↔ 能源化工
    -- ── 能源化工组（电力/蒸汽/太阳能/化工/石油/管道/核能/回收）──
    {key = 'electrician', techs = {'steam-power'}, name = '热能工人', full = FULL_MID, starter = {
        {item = 'boiler', groups = 1},
        {item = 'steam-engine', groups = 1},
    }, unlock = {{pack = 'logistic-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'boiler',      groups = 1},   -- 红：蒸汽机
        {pack = 'logistic-science-pack', item = 'steam-engine',      groups = 10},   -- 红：蒸汽机
        {pack = 'chemical-science-pack',   item = 'steam-turbine',    groups = 10},   -- 蓝：蒸汽涡轮机(高级)
        --
        {pack = 'agricultural-science-pack', item = 'heat-exchanger',  groups = 2},   -- 紫：热交换器
        {pack = 'cryogenic-science-pack',  item = 'heating-tower',   groups = 2},   -- 靛：供热塔(寒星)
    }},
    {key = 'greentech', techs = {'solar-energy', 'electric-energy-accumulators'}, name = '光能工人', full = FULL_MID, starter = {
        {item = 'solar-panel', groups = 1},
        {item = 'accumulator', groups = 1},
    }, unlock = {{pack = 'logistic-science-pack', level = 10}}, rewards = {
        {pack = 'logistic-science-pack',        item = 'solar-panel',         groups = 10},  -- 绿：太阳能板
        {pack = 'chemical-science-pack',      item = 'accumulator',         groups = 10},   -- 紫：蓄电器
        --
        {pack = 'electromagnetic-science-pack', item = 'lightning-rod', groups = 2},   -- 粉：避雷针(电浆星雷电)
        {pack = 'electromagnetic-science-pack', item = 'lightning-collector', groups = 2},   -- 粉：避雷针(电浆星雷电)
    }},
    {key = 'nuclearman', techs = {'nuclear-power'}, name = '核能工人', full = FULL_MAX, starter = {
        {item = 'centrifuge', count = 2},
    }, unlock = {{pack = 'chemical-science-pack', level = 100}}, rewards = {
        {pack = 'chemical-science-pack',   item = 'centrifuge',        groups = 5},   -- 蓝：离心机
        {pack = 'chemical-science-pack',   item = 'nuclear-reactor',        groups = 5},   -- 蓝：离心机
        {pack = 'chemical-science-pack',   item = 'uranium-fuel-cell',        groups = 5},   -- 蓝：离心机
        --
        {pack = 'cryogenic-science-pack',  item = 'fusion-reactor', groups = 2},   -- 靛：聚变发电机(顶级)
        {pack = 'cryogenic-science-pack',  item = 'fusion-generator', groups = 2},   -- 靛：聚变发电机(顶级)
        {pack = 'cryogenic-science-pack',   item = 'fusion-power-cell',        groups = 2},   -- 蓝：离心机
    }},

    {key = 'plumber', techs = {'fluid-handling'}, name = '管道工人', full = FULL_LOW, starter = {
        {item = 'pipe',  groups = 10},
        {item = 'pipe-to-ground',  groups = 1},
        {item = 'offshore-pump',  groups = 1},
        {item = 'pump', groups = 1},
    }, rewards = {
        {pack = 'automation-science-pack', item = 'pipe',           groups = 10},
        {pack = 'automation-science-pack', item = 'pipe-to-ground', groups = 10},
        {pack = 'logistic-science-pack',   item = 'pump',           groups = 5},
        {pack = 'logistic-science-pack',   item = 'storage-tank',   groups = 5},
    }},
    {key = 'gridman', techs = {'electric-energy-distribution-1', 'electric-energy-distribution-2'}, name = '电网工人', full = FULL_MID, starter = {
        {item = 'small-electric-pole', groups = 5},
        {item = 'power-switch', groups = 1},
    }, rewards = {
        {pack = 'automation-science-pack', item = 'small-electric-pole',  groups = 5},   -- 红：小电杆
        {pack = 'logistic-science-pack', item = 'medium-electric-pole', groups = 10},   -- 红：中电杆
        {pack = 'chemical-science-pack',   item = 'big-electric-pole',    groups = 10},   -- 绿：大电杆
        {pack = 'chemical-science-pack', item = 'substation',           groups = 10},   -- 紫：变电站
    }},
    {key = 'belter', techs = {'logistics', 'logistics-2'}, name = '运输工人', full = FULL_MID, starter = {
        {item = 'transport-belt', groups = 5},
        {item = 'splitter', groups = 2},
        {item = 'underground-belt', groups = 2},
    }, rewards = {
        {pack = 'logistic-science-pack',    item = 'fast-transport-belt',         groups = 5},
        {pack = 'logistic-science-pack',    item = 'fast-splitter',         groups = 2},
        {pack = 'logistic-science-pack',    item = 'fast-underground-belt',         groups = 2},
        --
        {pack = 'production-science-pack',    item = 'express-transport-belt',         groups = 5},
        {pack = 'production-science-pack',    item = 'express-splitter',         groups = 2},
        {pack = 'production-science-pack',    item = 'express-underground-belt',         groups = 2},
        --
        {pack = 'metallurgic-science-pack',    item = 'turbo-transport-belt',         groups = 5},
        {pack = 'metallurgic-science-pack',    item = 'turbo-splitter',         groups = 2},
        {pack = 'metallurgic-science-pack',    item = 'turbo-underground-belt',         groups = 2},
    }},

    {key = 'loaderman', techs = {'logistics-3'}, name = '装卸工人', full = FULL_MID, starter = {
        {item = 'loader', count = 1},
    }, unlock = {{pack = 'logistic-science-pack', level = 10}}, rewards = {
        {pack = 'logistic-science-pack',    item = 'loader',         groups = 10},   -- 绿：装卸机
        {pack = 'logistic-science-pack',    item = 'fast-loader',    groups = 5},   -- 绿：快速装卸机
        {pack = 'production-science-pack',  item = 'express-loader', groups = 2},   -- 紫：极速装卸机
        {pack = 'metallurgic-science-pack', item = 'turbo-loader',   groups = 1},   -- 橙：涡轮装卸机(火山)
    }},
    {key = 'warehouser', techs = {'logistic-system'}, name = '仓库管理员', full = FULL_MID, starter = {
        {item = 'wooden-chest', groups = 1},
        {item = 'iron-chest', groups = 1},
        {item = 'steel-chest', groups = 1},
        {item = 'storage-chest', groups = 1},
    }, rewards = {
        {pack = 'logistic-science-pack', item = 'steel-chest',            groups = 10},
        {pack = 'logistic-science-pack', item = 'storage-chest',          groups = 10},
        {pack = 'logistic-science-pack', item = 'passive-provider-chest', groups = 10},
        {pack = 'utility-science-pack',  item = 'requester-chest',        groups = 5},
        {pack = 'utility-science-pack',  item = 'buffer-chest',           groups = 5},
    }},
    {key = 'inserter', techs = {'fast-inserter', 'bulk-inserter'}, name = '斜教', full = FULL_MID, starter = {
        {item = 'burner-inserter', groups = 1},
        {item = 'inserter', groups = 1},
        {item = 'long-handed-inserter', groups = 1},
        {item = 'fast-inserter', groups = 1},
        -- {item = 'stack-inserter', groups = 1},
        -- {item = 'bulk-inserter', groups = 1},
    }, rewards = {
        {pack = 'automation-science-pack',    item = 'inserter',         groups = 8},
        {pack = 'automation-science-pack',    item = 'long-handed-inserter',         groups = 8},
        {pack = 'automation-science-pack',  item = 'fast-inserter', groups = 8},
        {pack = 'logistic-science-pack', item = 'bulk-inserter',   groups = 8},
        {pack = 'agricultural-science-pack', item = 'stack-inserter',   groups = 8},
    }},

    {key = 'traindriver', techs = {'railway', 'automated-rail-transportation'}, name = '火车司机', full = FULL_LOW, starter = {
        {item = 'locomotive', groups = 1},
        {item = 'cargo-wagon', groups = 1},
        {item = 'fluid-wagon', groups = 1},
        {item = 'rail', groups = 1},
    }, unlock = {{pack = 'logistic-science-pack', level = 10}}, rewards = {
        {pack = 'logistic-science-pack',   item = 'rail',              groups = 20},   -- 绿：铁轨
        {pack = 'logistic-science-pack',   item = 'train-stop',        groups = 1},    -- 绿：火车站
        {pack = 'logistic-science-pack',   item = 'rail-signal',       groups = 1},    -- 绿：铁路信号
        {pack = 'logistic-science-pack',   item = 'rail-chain-signal', groups = 1},    -- 绿：链式信号
    }},

    {key = 'roboticist', techs = {'robotics', 'construction-robotics', 'logistic-robotics'}, name = '机械师', full = FULL_MAX, starter = {
        {item = 'roboport', count = 1},
        {item = 'storage-chest', count = 1}, 
        {item = 'construction-robot', count = 10},
    }, rewards = {
        {pack = 'logistic-science-pack',   item = 'roboport',               groups = 10},   -- 绿：机器人港
        {pack = 'logistic-science-pack',   item = 'construction-robot',     groups = 10},  -- 绿：建造机器人
        {pack = 'logistic-science-pack',   item = 'storage-chest',          groups = 5},   -- 绿：存储箱
        {pack = 'logistic-science-pack',   item = 'passive-provider-chest', groups = 5},   -- 绿：被动供应箱
        --
        {pack = 'space-science-pack',    item = 'active-provider-chest',  groups = 2},   -- 白：主动供应箱
        {pack = 'space-science-pack',    item = 'requester-chest',        groups = 2},   -- 白：请求箱
        {pack = 'space-science-pack',    item = 'buffer-chest',           groups = 2},   -- 白：缓冲箱
        {pack = 'space-science-pack',   item = 'logistic-robot',         groups = 10},  -- 绿：物流机器人
    }},

    {section = '航天'},

    {key = 'TODO', techs = {'processing-unit-productivity'}, name = '飞船控制大师', full = FULL_MAX, starter = {
        {item = 'processing-unit', groups = 1},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 10}}, rewards = {

    }},
    {key = 'TODO', techs = {'low-density-structure-productivity'}, name = '飞船结构大师', full = FULL_MAX, starter = {
        {item = 'low-density-structure', groups = 1},
    }, unlock = {{pack = 'metallurgic-science-pack', level = 10}}, rewards = {

    }},
    {key = 'TODO', techs = {'rocket-fuel-productivity'}, name = '飞船燃料大师', full = FULL_MAX, starter = {
        {item = 'rocket-fuel', groups = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 10}}, rewards = {
)
    }},

    {key = 'TODO', techs = {'rocket-silo'}, name = '发射专家', full = FULL_MID, starter = {
        {item = 'rocket-part', count = 1},
    }, unlock = {{pack = 'space-science-pack', level = 100}}, rewards = {
        {pack = 'metallurgic-science-pack',   item = 'low-density-structure',                    groups = 10},
        {pack = 'electromagnetic-science-pack',   item = 'processing-unit',                    groups = 5},
        {pack = 'agricultural-science-pack',   item = 'rocket-fuel',                    groups = 25},
    }},

    {key = 'captain', techs = {'space-platform-thruster'}, name = '船长', full = FULL_MAX, starter = {
        {item = 'space-platform-starter-pack', count = 1},
    }, unlock = {{pack = 'space-science-pack', level = 100}}, rewards = {
        {pack = 'production-science-pack', item = 'space-platform-foundation',   groups = 20},
        {pack = 'space-science-pack',   item = 'cargo-bay',                   groups = 10},
        {pack = 'space-science-pack',   item = 'thruster',                    groups = 10},
    }},

    {key = 'asteroidminer', techs = {'advanced-asteroid-processing'}, name = '小行星带矿工', full = FULL_MAX, starter = {
        {item = 'space-platform-starter-pack', count = 1},
    }, unlock = {{pack = 'space-science-pack', level = 100}}, rewards = {
        {pack = 'space-science-pack',   item = 'asteroid-collector',          groups = 5},
        {pack = 'space-science-pack',   item = 'crusher',                     groups = 5},
    }},

    -- 宇航·四星开拓者：起始科技 = 各星球发现科技；starter/rewards/recipes 待填。
    {key = 'vulcanus', techs = {
        'planet-discovery-vulcanus', 
        'calcite-processing',
        'tungsten-carbide', 
        'foundry', 
        'big-mining-drill', 
        'tungsten-steel', 
    }, recipes = {}, name = '火山开拓者', full = FULL_MID, starter = {
        {item = 'big-mining-drill', count = 1},
        {item = 'foundry', count = 1},
    }, unlock = {{pack = 'metallurgic-science-pack', level = 10}}, rewards = {
        --
    }},

    {key = 'fulgora', techs = {
        'planet-discovery-fulgora',
        'recycling',
        'holmium-processing', 
        'electromagnetic-plant', 
    }, recipes = {}, name = '废土开拓者', full = FULL_MID, starter = {
        {item = 'recycler', count = 1},
        {item = 'electromagnetic-plant', count = 1},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 10}}, rewards = {
        --
    }},

    {key = 'gleba', techs = {
        'planet-discovery-gleba', 
        'heating-tower', 
        'agriculture', 
        'yumako', 
        'jellynut', 
        'bioflux', 
        'bioflux-processing', 
        'bacteria-cultivation', 
        'artificial-soil', 
        'biochamber', 
    'biter-egg-handling'}, recipes = {}, name = '雨林开拓者', full = FULL_MID, starter = {
        {item = 'agricultural-tower', count = 1},
        {item = 'biochamber', count = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 10}}, rewards = {
        --
    }},

    {key = 'aquilo', techs = {
        'planet-discovery-aquilo', 
        'heating-tower', 
        'lithium-processing', 
        'cryogenic-plant', 
    }, recipes = {}, name = '冰原开拓者', full = FULL_MAX, starter = {
        {item = 'cryogenic-plant', count = 1},
        {item = 'heating-tower', count = 1},
    }, unlock = {{pack = 'military-science-pack', level = 10}}, rewards = {

    }},

    {section = '星球专精'},
    -- 分组换行：农牧 ↔ 科学/星球
    -- ── 星球专精组（各星球招牌机器/材料 + 太空平台；满级线 1000，需对应高级瓶 100 级解锁）──
    {key = 'metallurgist', techs = {'low-density-structure-productivity'}, name = '冶金专家', full = FULL_MAX, starter = {

    }, unlock = {{pack = 'metallurgic-science-pack', level = 500}}, rewards = {
        {pack = 'metallurgic-science-pack', item = 'foundry',         groups = 10},
        {pack = 'metallurgic-science-pack', item = 'big-mining-drill', groups = 10},
    }},
    {key = 'electromancer', techs = {'processing-unit-productivity'}, name = '电磁专家', full = FULL_MAX, starter = {

    }, unlock = {{pack = 'electromagnetic-science-pack', level = 500}}, rewards = {
        {pack = 'electromagnetic-science-pack', item = 'electromagnetic-plant', groups = 10},
        {pack = 'electromagnetic-science-pack', item = 'recycler',    groups = 10},
    }},
    {key = 'biologist', techs = {'rocket-fuel-productivity'}, name = '生物专家', full = FULL_MAX, starter = {

    }, unlock = {{pack = 'agricultural-science-pack', level = 500}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'biochamber',         groups = 10},
        {pack = 'agricultural-science-pack', item = 'agricultural-tower', groups = 10},
    }},
    {key = 'physicist', techs = {'rocket-part-productivity'}, name = '物理专家', full = FULL_MAX, starter = {

    }, unlock = {{pack = 'cryogenic-science-pack', level = 500}}, rewards = {
        {pack = 'cryogenic-science-pack', item = 'cryogenic-plant',   groups = 10},
        {pack = 'cryogenic-science-pack', item = 'heating-tower',   groups = 10},
    }},
    {key = 'astronomer', techs = {'research-productivity'}, name = '天文专家', full = FULL_MAX, starter = {

    }, unlock = {{pack = 'promethium-science-pack', level = 1000}}, rewards = {
        {pack = 'promethium-science-pack', item = 'biolab',            groups = 20},
    }},

    {section = '战斗'},
    -- 分组换行：物流 ↔ 战斗
    -- ── 战斗组（弹药/手雷/核弹；练灰瓶 military，部分另练蓝瓶 chemical）──
    {key = 'guard', techs = {'gun-turret', 'stone-wall'}, name = '保安', full = FULL_MID, starter = {
        {item = 'stone-wall', groups = 10},
    }, rewards = {
        {pack = 'automation-science-pack', item = 'stone-wall',       groups = 20},   -- 灰：石墙
        {pack = 'automation-science-pack', item = 'radar',            groups = 1},   -- 灰：雷达
        {pack = 'logistic-science-pack', item = 'gate',             groups = 1},   -- 灰：闸门

        {pack = 'automation-science-pack',        item = 'gun-turret',          groups = 5},   -- 灰：机枪炮塔
        {pack = 'military-science-pack',        item = 'flamethrower-turret', groups = 1},   -- 蓝：喷火炮塔
        {pack = 'chemical-science-pack',        item = 'laser-turret',        groups = 1},   -- 灰：激光炮塔
        {pack = 'agricultural-science-pack', item = 'rocket-turret',        groups = 1},   -- 灰：火箭炮塔
    }},
    {key = 'gunner', techs = {'military'}, name = '田明建', full = FULL_MID, starter = {
        {item = 'submachine-gun', count = 1},
        {item = 'firearm-magazine', groups = 10},
    }, rewards = {
        {pack = 'automation-science-pack', item = 'firearm-magazine',         groups = 10},  -- 灰：普通弹匣
        {pack = 'military-science-pack', item = 'piercing-rounds-magazine', groups = 10},  -- 灰：穿甲弹
        {pack = 'utility-science-pack', item = 'uranium-rounds-magazine',  groups = 10},  -- 灰：铀弹
    }},

    {key = 'shotgunner', techs = {'military'}, name = '山上彻也', full = FULL_LOW, starter = {
        {item = 'combat-shotgun', count = 1},
        {item = 'shotgun-shell', groups = 10},
    }, rewards = {
        {pack = 'military-science-pack', item = 'shotgun-shell',          groups = 10},  -- 灰：霰弹
        {pack = 'utility-science-pack', item = 'piercing-shotgun-shell', groups = 10},  -- 灰：穿甲霰弹
    }},
    {key = 'bomber', techs = {'explosives'}, name = '拆迁队', full = FULL_MID, starter = {
        {item = 'grenade', groups = 1},
    }, rewards = {
        {pack = 'military-science-pack', item = 'grenade',         groups = 5},  -- 灰：手雷
        {pack = 'utility-science-pack',  item = 'cluster-grenade', groups = 5},  -- 黄：集束手雷
        --
        {pack = 'chemical-science-pack', item = 'poison-capsule',    groups = 5},   -- 灰：毒气胶囊
        {pack = 'chemical-science-pack', item = 'slowdown-capsule',  groups = 5},   -- 蓝：减速胶囊

        {pack = 'military-science-pack',  item = 'defender-capsule', groups = 5},
        {pack = 'chemical-science-pack',  item = 'distractor-capsule', groups = 2},
        {pack = 'utility-science-pack',  item = 'destroyer-capsule', groups = 1},
    }},

    {key = 'minelayer', techs = {'land-mine'}, name = '雷神', full = FULL_MID, starter = {
        {item = 'land-mine', count = 200},
    }, unlock = {{pack = 'military-science-pack', level = 100}}, rewards = {
        {pack = 'military-science-pack', item = 'land-mine', groups = 40},   -- 灰：地雷(海量布雷)
    }},

    {key = 'tanker', techs = {'tank'}, name = '大运司机', full = FULL_MID, starter = {
        {item = 'tank', count = 1},
    }, unlock = {{pack = 'military-science-pack', level = 100}}, rewards = {
        {pack = 'military-science-pack', item = 'tank',       groups = 1},   -- 灰：坦克
        --
        {pack = 'military-science-pack', item = 'cannon-shell',           groups = 10},  -- 灰：炮弹
        {pack = 'chemical-science-pack', item = 'explosive-cannon-shell', groups = 10},  -- 灰：爆破炮弹
        {pack = 'utility-science-pack', item = 'uranium-cannon-shell',   groups = 10},  -- 灰：铀炮弹
    }},
    {key = 'rocketeer', techs = {'rocketry'}, name = '胖子发射器', full = FULL_MAX, starter = {
        {item = 'rocket-launcher', count = 1},
        {item = 'rocket', count = 100},
    }, unlock = {{pack = 'chemical-science-pack', level = 100}}, rewards = {
        {pack = 'military-science-pack', item = 'rocket',               groups = 10},  -- 灰：火箭弹
        {pack = 'chemical-science-pack', item = 'explosive-rocket',     groups = 10},  -- 蓝：爆破火箭
        {pack = 'utility-science-pack',  item = 'atomic-bomb',          groups = 2},   -- 黄：核弹
        --
    }},
    {key = 'artillerist', techs = {'artillery'}, name = '李云龙', full = FULL_MAX, starter = {
        {item = 'artillery-turret', count = 1},
        {item = 'artillery-shell', count = 10},
    }, unlock = {{pack = 'metallurgic-science-pack', level = 100}}, rewards = {
        {pack = 'military-science-pack', item = 'artillery-shell',  groups = 40},
        {pack = 'metallurgic-science-pack',  item = 'artillery-wagon',  groups = 1}, 
        {pack = 'metallurgic-science-pack', item = 'artillery-turret', groups = 1},
    }},
    {key = 'teslatrooper', techs = {'tesla-weapons'}, name = '杨永信', full = FULL_MAX, starter = {
        {item = 'teslagun', count = 1},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 100}}, rewards = {
        {pack = 'electromagnetic-science-pack', item = 'teslagun',   groups = 1},
        {pack = 'electromagnetic-science-pack', item = 'tesla-ammo',   groups = 10},
        {pack = 'electromagnetic-science-pack', item = 'tesla-turret', groups = 10},
    }},
    {key = 'railgunner', techs = {'railgun'}, name = '御坂美琴', full = FULL_MAX, starter = {
        {item = 'railgun-ammo', count = 1},
    }, unlock = {{pack = 'cryogenic-science-pack', level = 500}}, rewards = {
        -- {pack = 'cryogenic-science-pack', item = 'railgun', groups = 1},
        {pack = 'cryogenic-science-pack', item = 'railgun-ammo',   groups = 20},   -- stack10：1组=10发
        {pack = 'cryogenic-science-pack', item = 'railgun-turret', groups = 2},
    }},

    {key = 'spidertron', techs = {'spidertron'}, name = '蜘蛛侠', full = FULL_MAX, starter = {
        {item = 'spidertron', count = 1},
    }, unlock = {{pack = 'utility-science-pack', level = 1000}}, rewards = {

    }},

    {key = 'mecharmor', techs = {'mech-armor'}, name = '变形金刚', full = FULL_MAX, starter = {   -- 终极机甲：粉瓶 1000 级解锁
        {item = 'mech-armor', count = 1},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 1000}}, rewards = {

    }},

    {section = '装备护甲'},
    -- 分组换行：战斗 ↔ 装备护甲
    -- ── 装备护甲组（护甲网格组件 + 终极机甲；按各组件解锁科技配瓶）──
    -- 角色网格分工：每个职业专精一类护甲网格组件。
    {key = 'shielder', techs = {'energy-shield-equipment'}, name = '肉盾', full = FULL_MID, starter = {   -- 全是盾
        {item = 'energy-shield-equipment', count = 20},
    }, rewards = {
        {pack = 'military-science-pack', item = 'energy-shield-equipment',     groups = 5},   -- 灰：能量盾
        {pack = 'utility-science-pack',  item = 'energy-shield-mk2-equipment', groups = 5},   -- 黄：能量盾 mk2
    }},
    {key = 'powergear', techs = {'solar-panel-equipment'}, name = '奶妈', full = FULL_MID, starter = {   -- 发电+储能装置
        -- {item = 'fusion-reactor-equipment', count = 1},
        {item = 'fission-reactor-equipment', count = 1},
        {item = 'battery-mk3-equipment', count = 1},
    }, rewards = {
        {pack = 'logistic-science-pack',  item = 'solar-panel-equipment',     groups = 6},  -- 绿：太阳能板
        {pack = 'chemical-science-pack',  item = 'fission-reactor-equipment', count = 10},   -- 蓝：裂变反应堆
        {pack = 'cryogenic-science-pack', item = 'fusion-reactor-equipment',  count = 10},   -- 靛：聚变反应堆
        --
        {pack = 'military-science-pack',  item = 'battery-equipment',         groups = 1},   -- 灰：电池(储能)
        {pack = 'utility-science-pack',   item = 'battery-mk2-equipment',     groups = 1},   -- 黄：电池 mk2
    }},
    {key = 'laserdefense', techs = {'personal-laser-defense-equipment'}, name = '输出', full = FULL_MID, starter = {   -- 全是激光
        {item = 'personal-laser-defense-equipment', count = 3},
    }, rewards = {
        {pack = 'military-science-pack', item = 'personal-laser-defense-equipment', groups = 2},  -- 灰：个人激光防御
    }},
    {key = 'roboportgear', techs = {'personal-roboport-equipment'}, name = '辅助', full = FULL_MID, starter = {   -- 全是机器人
        {item = 'personal-roboport-equipment', count = 5},
    }, rewards = {
        {pack = 'logistic-science-pack', item = 'construction-robot',            groups = 10},  -- 绿：建造机器人
        {pack = 'chemical-science-pack', item = 'personal-roboport-equipment',     groups = 5},   -- 蓝：个人机器人网格
        {pack = 'utility-science-pack',  item = 'personal-roboport-mk2-equipment', count = 20},   -- 黄：网格 mk2
    }},
    {key = 'exoskeleton', techs = {'exoskeleton-equipment'}, name = '快递员', full = FULL_MID, starter = {   -- 全是外骨骼
        {item = 'exoskeleton-equipment', count = 3},
    }, rewards = {
        {pack = 'chemical-science-pack', item = 'exoskeleton-equipment', groups = 5},   -- 蓝：外骨骼(移动加速)
    }},
    {key = 'toolbelt', techs = {'toolbelt-equipment'}, name = '吃货', full = FULL_MID, starter = {   -- 全是工具腰带
        {item = 'toolbelt-equipment', count = 10},
    }, rewards = {
        {pack = 'logistic-science-pack', item = 'toolbelt-equipment', groups = 5},   -- 绿：工具腰带(扩快捷栏)
    }},

    {section = '农牧'},
    -- 分组换行：装备护甲 ↔ 农牧
    -- ── 农牧组（鱼/虫卵/种子/腐败物，Gleba 生态，主练草瓶 agricultural）──
    {key = 'hunter', techs = {'captivity'}, name = '猎手', full = FULL_MID, starter = {
        {item = 'biter-egg', count = 1},
        {item = 'rocket-launcher', count = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'capture-robot-rocket',     groups = 10},
        {pack = 'space-science-pack', item = 'bioflux',     groups = 10},
        {pack = 'agricultural-science-pack', item = 'bioflux',     groups = 10},
        {pack = 'promethium-science-pack', item = 'bioflux',     groups = 10},
    }},
    {key = 'herder', techs = {'captivity'}, name = '牧民', full = FULL_MID, starter = {
        {item = 'pentapod-egg', count = 1},
        {item = 'biochamber', count = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'bioflux',     groups = 10},
        {pack = 'agricultural-science-pack', item = 'capture-robot-rocket',     groups = 10},
    }},

    {key = 'fisher', techs = {'fish-breeding'}, name = '渔夫', full = FULL_LOW, starter = {
        {item = 'raw-fish', groups = 1},
        {item = 'biochamber', count = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'space-science-pack', item = 'raw-fish',  groups = 10},
        {pack = 'agricultural-science-pack', item = 'raw-fish',  groups = 10},
        {pack = 'promethium-science-pack', item = 'raw-fish',  groups = 10},
    }},
    {key = 'farmer', techs = {'agriculture', 'jellynut', 'yumako'}, name = '农民', full = FULL_MAX, starter = {
        {item = 'yumako-seed', groups = 2},
        {item = 'jellynut-seed', groups = 2},
        {item = 'agricultural-tower', count = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'artificial-yumako-soil',     groups = 10},
        {pack = 'agricultural-science-pack', item = 'overgrowth-yumako-soil',         groups = 10},
        {pack = 'agricultural-science-pack', item = 'artificial-jellynut-soil', groups = 10},
        {pack = 'agricultural-science-pack', item = 'overgrowth-jellynut-soil', groups = 10},
    }},
    {key = 'forester', techs = {'tree-seeding'}, name = '护林员', full = FULL_MAX, starter = {
        {item = 'wood', groups = 2},
        {item = 'tree-seed', groups = 2},
        {item = 'agricultural-tower', count = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'automation-science-pack', item = 'wood',       groups = 10},
        {pack = 'space-science-pack', item = 'landfill',       groups = 10},
        {pack = 'agricultural-science-pack', item = 'landfill',       groups = 10},
        {pack = 'promethium-science-pack', item = 'landfill',       groups = 10},
    }},
    {key = 'chef', techs = {'bioflux', 'bioflux-processing', 'jellynut', 'yumako'}, name = '厨师', full = FULL_MID, starter = {
        {item = 'biochamber', groups = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'yumako',  groups = 10},
        {pack = 'agricultural-science-pack', item = 'yumako-mash',     groups = 10},
        {pack = 'agricultural-science-pack', item = 'jellynut',  groups = 10},
        {pack = 'agricultural-science-pack', item = 'jelly',     groups = 10},
    }},
    {key = 'pharmacist', techs = {'bacteria-cultivation'}, name = '培养员', full = FULL_MID, starter = {
        {item = 'biochamber', groups = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'iron-bacteria',  groups = 2},
        {pack = 'agricultural-science-pack', item = 'copper-bacteria',  groups = 2},
        {pack = 'agricultural-science-pack', item = 'bioflux',     groups = 40},
    }},

}

-- 纯数据深拷贝（DEFAULT_CLASSES 无函数/元表，递归即可）。
local function deepcopy(t)
    if type(t) ~= 'table' then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepcopy(v) end
    return c
end

-- 把默认职业表深拷贝进 storage.classes（仅当缺失）。on_init / on_configuration_changed 调用。
function M.ensure()
    storage.classes = storage.classes or deepcopy(DEFAULT_CLASSES)
end

-- 当前生效的职业表（读 storage；未初始化则退回默认常量兜底）。
function M.all()
    return storage.classes or DEFAULT_CLASSES
end

-- 按 key 找职业定义（遍历当前表；职业数少、不缓存，确保 /c 改后即时生效）。
function M.def_for_key(key)
    if not key then return nil end
    for _, def in ipairs(M.all()) do
        if def.key == key then return def end
    end
    return nil
end

-- 玩家当前选择的职业 key（未选 → 默认职业 civilian）。
function M.selected_key(player)
    return player and ((storage.player_class or {})[player.name] or M.DEFAULT)
end

-- 职业【专属解锁】明细：返回当前【有玩家选用、且配了 techs/recipes】的职业列表，
--   每项 {key=, name=, techs={...}, recipes={...}}。谁选了职业看 storage.player_class（持久，含离线）。
-- reset 据此开局解锁科技/配方【并按职业广播】"什么职业解锁了什么" → 故按职业分组、不在此处去重。
function M.active_class_unlocks()
    -- 按职业 key 统计【选了该职业的玩家人数】(player_class 按玩家名存，含离线)。
    local count = {}
    for _, key in pairs(storage.player_class or {}) do count[key] = (count[key] or 0) + 1 end
    local out = {}
    for _, def in ipairs(M.all()) do
        local has = (def.techs and #def.techs > 0) or (def.recipes and #def.recipes > 0)
        if def.key and count[def.key] and has then
            -- count = 选该职业的人数；无限科技按人数叠加等级（见 reset.lua），普通科技/配方仍只需解锁一次。
            out[#out + 1] = {key = def.key, name = def.name, count = count[def.key], techs = def.techs or {}, recipes = def.recipes or {}}
        end
    end
    return out
end

-- 玩家当前职业定义（一定返回一个，兜底默认职业 civilian）。
function M.def_of(player)
    return M.def_for_key(M.selected_key(player)) or M.def_for_key(M.DEFAULT)
end

-- 玩家某瓶当前等级（= floor√经验，封顶 MAX_LEVEL=10万，与 respawn_gifts.pack_level 一致）。
function M.pack_level(player, pack)
    return math.min(M.MAX_LEVEL, math.floor(math.sqrt(passives.exp_total_for_pack(player.index, pack))))
end

-- 星球门槛：前往 / 设出生星球需对应科技瓶达 constants.PLANET_REQ_LEVEL 级。母星(无 pack)恒通过。
-- 返回 met(bool 是否达标), pack(瓶名 or nil), cur(玩家当前该瓶等级), req(门槛等级)。
function M.planet_gate(player, planet)
    local pack = constants.PLANET_PACK[planet]
    local req = constants.PLANET_REQ_LEVEL
    if not pack then return true, nil, 0, req end
    local cur = M.pack_level(player, pack)
    return cur >= req, pack, cur, req
end

-- 该职业对该玩家是否已解锁（unlock 列表里每条都需满足；无 unlock = 人人可选）。
function M.unlocked(player, def)
    if not (def and def.unlock) then return true end
    for _, u in ipairs(def.unlock) do
        if M.pack_level(player, u.pack) < u.level then return false end
    end
    return true
end

-- 设定玩家选择的职业（校验 key 合法 + 已解锁 + 写存储）。返回 true=成功；'locked'=未解锁；nil=非法 key。
function M.set(player, key)
    local def = M.def_for_key(key)
    if not (player and def) then return nil end
    if not M.unlocked(player, def) then return 'locked' end
    storage.player_class = storage.player_class or {}
    storage.player_class[player.name] = key
    return true
end

-- 显示文本三层兜底（i18n + 动态 + 默认）：利用 localised-string 的 '?' fallback 依次尝试，第一个能解析的生效。
--   ① locale_key 词条（有翻译则按玩家语言显示，英文友好）；② 失败则 dyn（动态表值，/c 可热改，nil 则跳过）；
--   ③ 再失败用 default（纯字符串恒成功，保底）。例：name = text_loc('wn.class-name-civilian', storage.class_names.civilian, '出租司机')。
function M.text_loc(locale_key, dyn, default)
    return {'?', {locale_key}, dyn or default or ''}
end

return M
