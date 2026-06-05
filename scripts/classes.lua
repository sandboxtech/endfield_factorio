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
--            可选 p=(默认 1)：每【件】物品独立按 p 概率获得，实发数 ~ B(总数, p)（util.binomial 采样，开局物资随机化）。
--   rewards  经验奖励列表：每条 {pack=瓶, item=物品, groups=满配额组数}；按该瓶等级线性发，
--            个数 = floor(堆叠 × groups × min(瓶等级, full) / full)。pack 按物品在科技树的解锁层级配。
--            可选 full=：单条 reward 自带 full 则覆盖职业 full（仅算这一条），nil 则继承职业 full。
--            用于让同职业里某些奖励满得更快/更慢，互不影响。满级配额(stack×groups)不变，只改逼近速度。
--            可选 p=(默认 1)：同 starter，每件独立 p 概率，按当前应发数二项采样。
--   unlock   解锁条件(可选)：每条 {pack=瓶, level=级}，需全满足；无则人人可选。
--   techs    职业【专属科技】(可选，数组)：只要存在选了该职业的玩家(含离线)，开局把这些科技标记已研究(reset 调 M.active_class_unlocks)。
--            条目两种写法：'科技名' = 恒解锁；{'科技名', p = 0.5} = 每轮开局按概率解锁——
--            有限科技：每个选该职业的玩家独立掷 p，任一命中即解锁 → 有效概率 1-(1-p)^人数，未中本轮不解锁。
--            无限科技(叠级模式)：每个玩家独立掷 p、各自 +1 级 → 实加级数 ~ B(人数, p)（与初始物品同口径）。
--            如 techs = {'logistics', {'automation-2', p = 0.3}}。【勿用 name= 键】：gen_set_classes.py 按 name= 抓职业名，会误抓。
--   recipes  职业【专属配方】(可选，数组)：同上，但开局解锁配方(force 级 enabled，无需对应科技。reset 调 M.active_class_unlocks)。
--            条目格式与 techs 相同：'配方名' = 恒解锁；{'配方名', p = 0.5} = 每轮按概率解锁(有效概率同 techs = 1-(1-p)^人数)。
--            如 recipes = {'rail', {'pistol', p = 0.5}}。
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

-- 默认职业表（顺序即面板显示顺序），分组：市民 / 杂货商人 / 生产 / 能源 / 物流 / 航天 / 星球专精 / 战斗 / 装备护甲 / 农牧（{section='key'} 分隔，key 即 locale 词条）。
local DEFAULT_CLASSES = {
    -- ── 基础生产组（红瓶起步：矿/板/齿轮/电路，满级线低 full=100，开局速成大宗）──
    -- 默认职业。
    {section = 'civilian'},

    {key = 'civilian', name = '市民', full = FULL_LOW, starter = {
        {item = 'automation-science-pack',   count = 1},
        {item = 'car', count = 1},
        {item = 'nuclear-fuel', groups = 1},
        {item = 'coin', count = 1},
    }, rewards = {
        {pack = 'automation-science-pack', item = 'coin',   count = 100, full = FULL_MID},
    }},

    {key = 'afker', techs = {
        {'health', p = 0.5},
        {'research-productivity', p = 0.5},
    }, name = '挂机大师', full = FULL_MAX, starter = {
        {item = 'logistic-science-pack',   count = 1},
    }, rewards = {

    }},

    {key = 'philosopher',  techs = {
    }, recipes = {
        {'biolab', p = 0.5},
    }, name = '哲学大师', full = FULL_LOW, starter = {
        {item = 'chemical-science-pack',   count = 1},
    }, rewards = {
        {pack = 'logistic-science-pack', item = 'automation-science-pack',   count=10},
    }},

    {key = 'artist', recipes = {
        'small-lamp','arithmetic-combinator', 'decider-combinator',
        'constant-combinator', 'power-switch', 'programmable-speaker',
        'display-panel', 'selector-combinator',
    }, name = '艺术大师', full = FULL_LOW, starter = {
        {item = 'small-lamp', groups = 1},
        {item = 'constant-combinator', count = 1},
    }, unlock = {{pack = 'logistic-science-pack', level = 100}}, rewards = {

        {pack = 'logistic-science-pack',  item = 'small-lamp', groups = 5, full = FULL_LOW},
        {pack = 'logistic-science-pack',   item = 'decider-combinator', groups = 5, full = FULL_MID},
        {pack = 'logistic-science-pack',   item = 'arithmetic-combinator', groups = 5, full = FULL_MID},
        {pack = 'automation-science-pack',    item = 'constant-combinator', groups = 5, full = FULL_MID},
        {pack = 'promethium-science-pack',   item = 'selector-combinator', groups = 5, full = FULL_MAX},
        {pack = 'logistic-science-pack',    item = 'display-panel',        groups = 5, full = FULL_MAX},
        {pack = 'promethium-science-pack',    item = 'programmable-speaker', groups = 5, full = FULL_MAX},
    }},

    {key = 'inventor', techs = {
        'research-speed-1',
        'research-speed-2',
        'research-speed-3',
        'research-speed-4',
        'research-speed-5',
        'research-speed-6',
    }, name = '发明大师', full = FULL_LOW, starter = {
        {item = 'lab', groups = 1},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'lab', groups = 10, full = FULL_LOW},
        {pack = 'space-science-pack', item = 'lab', groups = 10, full = FULL_MID},
        {pack = 'promethium-science-pack', item = 'lab', groups = 10, full = FULL_MAX},
    }},

    {key = 'civilengineer', recipes = {
        'cliff-explosives',
    }, name = '土木大师', full = FULL_LOW, starter = {
        {item = 'cliff-explosives', groups = 1},
        {item = 'foundation', groups = 1},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'stone-brick', groups = 5, full = FULL_LOW},
        {pack = 'logistic-science-pack', item = 'concrete', groups = 5, full = FULL_MID},
        {pack = 'space-science-pack', item = 'refined-concrete', groups = 5, full = FULL_MID},
        {pack = 'cryogenic-science-pack', item = 'foundation', groups = 10, full = FULL_MAX},
        {pack = 'metallurgic-science-pack', item = 'cliff-explosives', groups = 10, full = FULL_MAX},
    }},

    {section = 'merchant'},
    -- 矿物
    {key = 'oreman', techs = {'mining-productivity-1', 'mining-productivity-2'}, name = '矿物商人', full = FULL_LOW, starter = {
        {item = 'iron-ore', groups = 6},
        {item = 'copper-ore', groups = 6},
        {item = 'stone', groups = 6},
        {item = 'coal', groups = 6},
    }, unlock = {{pack = 'automation-science-pack', level = 1}}, rewards = {
        {pack = 'space-science-pack', item = 'uranium-ore', groups = 4},

        {pack = 'metallurgic-science-pack',     item = 'tungsten-ore', groups = 4},
        {pack = 'metallurgic-science-pack',     item = 'calcite', groups = 4},
        {pack = 'electromagnetic-science-pack', item = 'holmium-ore', groups = 4},
        {pack = 'electromagnetic-science-pack', item = 'scrap',        groups = 4},
        {pack = 'agricultural-science-pack', item = 'stone', groups = 4},
        {pack = 'agricultural-science-pack', item = 'carbon', groups = 4},
        {pack = 'cryogenic-science-pack', item = 'lithium', groups = 4},
        {pack = 'promethium-science-pack', item = 'promethium-asteroid-chunk', groups = 1},
    }},

    -- 材料
    {key = 'material', recipes = {
        'low-density-structure',
    }, name = '材料商人', full = FULL_LOW, starter = {
        {item = 'iron-plate', groups = 8},
        {item = 'copper-plate', groups = 2},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'iron-plate', groups = 1, full = FULL_LOW},
        {pack = 'logistic-science-pack', item = 'copper-plate', groups = 1, full = FULL_LOW},
        {pack = 'military-science-pack', item = 'stone-brick', groups = 1, full = FULL_LOW},
        {pack = 'chemical-science-pack', item = 'plastic-bar', groups = 1, full = FULL_LOW},
        {pack = 'production-science-pack', item = 'steel-plate', groups = 1, full = FULL_LOW},
        {pack = 'utility-science-pack', item = 'sulfur', groups = 1, full = FULL_MID},
        {pack = 'space-science-pack', item = 'uranium-238', groups = 1, full = FULL_MID},
        --
        {pack = 'metallurgic-science-pack',     item = 'tungsten-carbide', groups = 1, full = FULL_MAX},
        {pack = 'metallurgic-science-pack',     item = 'tungsten-plate', groups = 1, full = FULL_MAX},
        {pack = 'electromagnetic-science-pack', item = 'holmium-plate', groups = 1, full = FULL_MAX},
        {pack = 'agricultural-science-pack', item = 'carbon-fiber', groups = 1, full = FULL_MAX},
        {pack = 'cryogenic-science-pack', item = 'lithium-plate', groups = 1, full = FULL_MAX},
        {pack = 'promethium-science-pack', item = 'uranium-235', groups = 1, full = FULL_MAX},
    }},

    -- 能源
    {key = 'energytrader', recipes = {
        'rocket-fuel',  'solid-fuel-from-petroleum-gas', 'solid-fuel-from-heavy-oil', 'solid-fuel-from-light-oil',
    }, name = '能源商人', full = FULL_LOW, starter = {
        {item = 'coal', groups = 10},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'coal', groups = 5, full = FULL_LOW},
        {pack = 'logistic-science-pack', item = 'solid-fuel', groups = 5, full = FULL_LOW},
        {pack = 'chemical-science-pack', item = 'rocket-fuel', groups = 5, full = FULL_MID},
        {pack = 'space-science-pack', item = 'carbon', groups = 5, full = FULL_MID},
        {pack = 'promethium-science-pack', item = 'nuclear-fuel', groups = 5, full = FULL_MAX},
    }},

    {key = 'partstrader', recipes = {
        'advanced-circuit', 'processing-unit',
    },  name = '零件商人', full = FULL_LOW, starter = {
        {item = 'electronic-circuit', count = 200},
        {item = 'iron-gear-wheel', count = 200},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'iron-gear-wheel', groups = 5, full = FULL_LOW},
        {pack = 'logistic-science-pack', item = 'electronic-circuit', groups = 5, full = FULL_LOW},
        {pack = 'military-science-pack', item = 'engine-unit', groups = 2, full = FULL_MID},
        {pack = 'chemical-science-pack', item = 'advanced-circuit', groups = 2, full = FULL_MID},
        {pack = 'production-science-pack', item = 'electric-engine-unit', groups = 2, full = FULL_MID},
        {pack = 'utility-science-pack', item = 'flying-robot-frame', groups = 2, full = FULL_MAX},
        {pack = 'cryogenic-science-pack', item = 'processing-unit', groups = 2, full = FULL_MAX},
    }},

    -- 军火
    {key = 'armsdealer', name = '军火商人', full = FULL_LOW, starter = {
        {item = 'firearm-magazine', count = 200},
        {item = 'grenade', count = 50},
    }, unlock = {{pack = 'automation-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'piercing-shotgun-shell', groups = 2, full = FULL_LOW},
        {pack = 'logistic-science-pack',   item = 'piercing-rounds-magazine', groups = 2, full = FULL_LOW},
        {pack = 'military-science-pack',   item = 'flamethrower-ammo', groups = 2, full = FULL_LOW},
        {pack = 'chemical-science-pack',   item = 'rocket',                   groups = 2, full = FULL_MID},
        {pack = 'production-science-pack', item = 'cannon-shell', groups = 2, full = FULL_MID},
        {pack = 'utility-science-pack',    item = 'explosive-uranium-cannon-shell', groups = 2, full = FULL_MID},
        {pack = 'space-science-pack',      item = 'uranium-rounds-magazine', groups = 2, full = FULL_MID},
        --
        {pack = 'metallurgic-science-pack',     item = 'artillery-shell', groups = 2, full = FULL_MAX},
        {pack = 'electromagnetic-science-pack', item = 'tesla-ammo', groups = 2, full = FULL_MAX},
        {pack = 'agricultural-science-pack',    item = 'explosive-rocket', groups = 2, full = FULL_MAX},
        {pack = 'cryogenic-science-pack',       item = 'railgun-ammo', groups = 2, full = FULL_MAX},
        {pack = 'promethium-science-pack',      item = 'atomic-bomb', groups = 1, full = FULL_MAX},
    }},

    -- 大资本家压轴：全瓶种发金币（从市民组移入，商人组的终极形态）
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

    {section = 'basic'},   -- 分区标题（无 key，职业窗口里渲染成粗体小标题）

    {key = 'miner', recipes = {
        'electric-mining-drill',
    }, techs = {'mining-productivity-3'}, name = '采矿工人', full = FULL_MID, starter = {
        {item = 'burner-mining-drill', groups = 2},
    }, rewards = {
        {pack = 'automation-science-pack',     item = 'electric-mining-drill', groups = 20, full = FULL_LOW},
        {pack = 'metallurgic-science-pack', item = 'big-mining-drill', groups = 20, full = FULL_MAX},
    }},

    {key = 'smelter', recipes = {
        'steel-furnace', 'electric-furnace',
    }, techs = {'steel-plate-productivity'}, name = '煅烧工人', full = FULL_MID, starter = {
        {item = 'stone-furnace', groups = 6},
    }, rewards = {
        {pack = 'logistic-science-pack', item = 'steel-furnace', groups = 20, full = FULL_LOW},
        {pack = 'chemical-science-pack', item = 'electric-furnace', groups = 20, full = FULL_MAX},
    }},

    {key = 'artisan', recipes = {
        'assembling-machine-1',  'assembling-machine-2', 'assembling-machine-3',
    }, name = '装配工人', full = FULL_MID, starter = {
        {item = 'assembling-machine-1', groups = 1},
    }, rewards = {
        {pack = 'automation-science-pack', item = 'assembling-machine-1', groups = 10, full = FULL_LOW},
        {pack = 'logistic-science-pack',   item = 'assembling-machine-2', groups = 10, full = FULL_MID},
        {pack = 'production-science-pack', item = 'assembling-machine-3', groups = 10, full = FULL_MAX},
    }},

    {key = 'oilman', recipes = {
        'pumpjack', 'oil-refinery', 'chemical-plant', 'basic-oil-processing',
        'advanced-oil-processing', 'heavy-oil-cracking', 'light-oil-cracking',
    }, name = '石化工人', full = FULL_LOW, starter = {
        {item = 'pumpjack', groups = 1},
        {item = 'oil-refinery', groups = 1},
        {item = 'chemical-plant', groups = 1},
    }, unlock = {{pack = 'logistic-science-pack', level = 10}}, rewards = {
        {pack = 'logistic-science-pack',   item = 'pumpjack', groups = 10, full = FULL_LOW},
        {pack = 'logistic-science-pack',   item = 'oil-refinery', groups = 10, full = FULL_LOW},
        {pack = 'logistic-science-pack',   item = 'chemical-plant', groups = 10, full = FULL_LOW},
        {pack = 'agricultural-science-pack',   item = 'biochamber', groups = 2, full = FULL_MID},
        {pack = 'cryogenic-science-pack',   item = 'cryogenic-plant', groups = 2, full = FULL_MAX},
    }},

    {key = 'foundryman', recipes = {
        'foundry', 'molten-iron', 'molten-copper',
        'casting-iron', 'casting-copper', 'casting-steel',
    }, name = '冶金工人', full = FULL_LOW, starter = {
        {item = 'foundry', count = 5},
    }, unlock = {{pack = 'metallurgic-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'calcite', groups = 10, full = FULL_LOW},
        {pack = 'space-science-pack', item = 'calcite', groups = 10, full = FULL_MID},
        {pack = 'metallurgic-science-pack', item = 'calcite', groups = 10, full = FULL_MID},
        {pack = 'promethium-science-pack', item = 'calcite', groups = 10, full = FULL_MAX},
    }},
    {key = 'electromagneticman', recipes = {
        'electromagnetic-plant', 'superconductor', 'supercapacitor', 'electrolyte',
    }, name = '电子工人', full = FULL_LOW, starter = {
        {item = 'electromagnetic-plant', count = 5},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'copper-cable', groups = 10, full = FULL_LOW},
        {pack = 'space-science-pack', item = 'copper-cable', groups = 10, full = FULL_MID},
        {pack = 'electromagnetic-science-pack', item = 'copper-cable', groups = 10, full = FULL_MID},
        {pack = 'promethium-science-pack', item = 'copper-cable', groups = 10, full = FULL_MAX},
    }},
    {key = 'recyclerman', recipes = {
        'recycler',
    }, techs = {}, name = '回收工人', full = FULL_LOW, starter = {
        {item = 'recycler', count = 5},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 10}}, rewards = {
        {pack = 'automation-science-pack', item = 'scrap', groups = 10, full = FULL_LOW},
        {pack = 'space-science-pack', item = 'scrap', groups = 10, full = FULL_MID},
        {pack = 'electromagnetic-science-pack', item = 'scrap', groups = 10, full = FULL_MID},
        {pack = 'promethium-science-pack', item = 'scrap', groups = 10, full = FULL_MAX},
    }},

    {key = 'moduler', recipes = {
        'beacon',
        'quality-module',
        'speed-module',
        'efficiency-module',
        'productivity-module',
    }, techs = {

    }, name = '插件工人', full = FULL_MID, starter = {
        {item = 'beacon', groups = 10},
        {item = 'speed-module-2', groups = 1},
        {item = 'efficiency-module-2', groups = 1},
    }, unlock = {{pack = 'production-science-pack', level = 10}}, rewards = {
        {pack = 'production-science-pack', item = 'beacon', groups = 10, full = FULL_LOW},
        {pack = 'space-science-pack', item = 'beacon', groups = 10, full = FULL_MID},
        {pack = 'promethium-science-pack', item = 'beacon', groups = 10, full = FULL_MAX},
        --
        {pack = 'metallurgic-science-pack',     item = 'speed-module-2', groups = 5, full = FULL_MID},
        {pack = 'electromagnetic-science-pack',     item = 'quality-module-2', groups = 5, full = FULL_MID},
        {pack = 'agricultural-science-pack', item = 'efficiency-module-2', groups = 5, full = FULL_MID},
        {pack = 'cryogenic-science-pack', item = 'quality-module-2', groups = 5, full = FULL_MID},
    }},

    {key = 'qualityman', recipes = {
        'quality-module', 'quality-module-2', 'quality-module-3',
    }, name = '品质大师', full = FULL_MAX, starter = {
        {item = 'quality-module', groups = 1},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 10}}, rewards = {
        {pack = 'chemical-science-pack',        item = 'quality-module', groups = 10, full = FULL_LOW},
        {pack = 'space-science-pack',           item = 'quality-module-2', groups = 10, full = FULL_MID},
        {pack = 'electromagnetic-science-pack', item = 'quality-module-3', groups = 10, full = FULL_MAX},
    }},
    {key = 'speedman', recipes = {
        'speed-module', 'speed-module-2', 'speed-module-3',
    }, name = '速度大师', full = FULL_MAX, starter = {
        {item = 'speed-module', groups = 1},
    }, unlock = {{pack = 'metallurgic-science-pack', level = 10}}, rewards = {
        {pack = 'chemical-science-pack',    item = 'speed-module', groups = 10, full = FULL_LOW},
        {pack = 'space-science-pack',       item = 'speed-module-2', groups = 10, full = FULL_MID},
        {pack = 'metallurgic-science-pack', item = 'speed-module-3', groups = 10, full = FULL_MAX},
    }},
    {key = 'efficiencyman', recipes = {
        'efficiency-module', 'efficiency-module-2', 'efficiency-module-3',
    }, name = '节能大师', full = FULL_MAX, starter = {
        {item = 'efficiency-module', groups = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 10}}, rewards = {
        {pack = 'chemical-science-pack',     item = 'efficiency-module', groups = 10, full = FULL_LOW},
        {pack = 'space-science-pack',        item = 'efficiency-module-2', groups = 10, full = FULL_MID},
        {pack = 'agricultural-science-pack', item = 'efficiency-module-3', groups = 10, full = FULL_MAX},
    }},
    {key = 'productivityman', recipes = {
        'productivity-module', 'productivity-module-2', 'productivity-module-3',
    }, name = '产能大师', full = FULL_MAX, starter = {
        {item = 'productivity-module', groups = 1},
    }, unlock = {{pack = 'cryogenic-science-pack', level = 10}}, rewards = {
        {pack = 'chemical-science-pack',  item = 'productivity-module', groups = 10, full = FULL_LOW},
        {pack = 'space-science-pack',     item = 'productivity-module-2', groups = 10, full = FULL_MID},
        {pack = 'cryogenic-science-pack', item = 'productivity-module-3', groups = 10, full = FULL_MAX},
    }},


    {section = 'energy'},
    -- 分组换行：基础生产 ↔ 能源
    -- ── 能源组（热能/光能/核能发电）──
    -- 热能拆分：锅炉工人=烧火侧（锅炉/蒸汽机/加热塔），涡轮工人=热交换侧（汽轮机/热管/热交换器，配核电/聚变）。
    {key = 'boilerman', recipes = {
        'heating-tower',
    }, name = '锅炉工人', full = FULL_MID, starter = {
        {item = 'boiler', groups = 2},
        {item = 'steam-engine', groups = 1},
    }, rewards = {
        {pack = 'automation-science-pack', item = 'boiler',        groups = 20,  full = FULL_LOW},
        {pack = 'automation-science-pack',   item = 'steam-engine', groups = 10, full = FULL_LOW},
    }},
    {key = 'turbineman', recipes = {
        'steam-turbine', 'heat-pipe', 'heat-exchanger',
    }, name = '涡轮工人', full = FULL_MID, starter = {
        {item = 'steam-turbine', groups = 10},
        {item = 'heat-exchanger', count = 10},
        {item = 'heat-pipe', count = 50},
    }, rewards = {
        {pack = 'chemical-science-pack', item = 'heat-pipe', groups = 10, full = FULL_MID},
        {pack = 'chemical-science-pack', item = 'heat-exchanger', groups = 10,  full = FULL_MID},
        {pack = 'chemical-science-pack',     item = 'steam-turbine', groups = 10, full = FULL_MID},
    }},
    {key = 'greentech', recipes = {
        'solar-panel', 'accumulator',
    }, name = '光能工人', full = FULL_MID, starter = {
        {item = 'solar-panel', groups = 1},
        {item = 'accumulator', groups = 1},
    }, rewards = {
        {pack = 'logistic-science-pack',        item = 'solar-panel', groups = 20, full = FULL_MID},
        {pack = 'chemical-science-pack',      item = 'accumulator', groups = 20, full = FULL_MID},
        --
        {pack = 'electromagnetic-science-pack', item = 'lightning-rod', groups = 2, full = FULL_MAX},
        {pack = 'electromagnetic-science-pack', item = 'lightning-collector', groups = 2, full = FULL_MAX},
    }},
    {key = 'fissionman', recipes = {
        'nuclear-reactor', 'uranium-fuel-cell',
    }, name = '裂变工人', full = FULL_MAX, starter = {
        {item = 'uranium-fuel-cell', groups = 1},
    }, rewards = {
        {pack = 'chemical-science-pack', item = 'nuclear-reactor', groups = 20, full = FULL_MAX},
        {pack = 'chemical-science-pack', item = 'uranium-fuel-cell', groups = 20, full = FULL_MAX},
    }},
    {key = 'fusionman', recipes = {
        'fusion-reactor', 'fusion-generator', 'fusion-power-cell',
    }, name = '聚变工人', full = FULL_MAX, starter = {
        {item = 'fusion-power-cell', count = 1},
    }, rewards = {
        {pack = 'cryogenic-science-pack', item = 'fusion-reactor', groups = 10,  full = FULL_MAX},
        {pack = 'cryogenic-science-pack', item = 'fusion-generator', groups = 10,  full = FULL_MAX},
        {pack = 'cryogenic-science-pack', item = 'fusion-power-cell', groups = 20, full = FULL_MAX},
    }},

    {section = 'logistics'},
    -- ── 物流组（管道/电网/传送带/装卸/仓储/机械臂/火车/机器人）──
    {key = 'plumber', recipes = {
        'storage-tank', 'pump',
    }, name = '管道工人', full = FULL_LOW, starter = {
        {item = 'pipe', groups = 10},
        {item = 'pipe-to-ground', groups = 1},
        {item = 'offshore-pump', groups = 1},
        {item = 'pump', groups = 1},
    }, rewards = {
        {pack = 'automation-science-pack', item = 'pipe', groups = 10},
        {pack = 'automation-science-pack', item = 'pipe-to-ground', groups = 10},
        {pack = 'logistic-science-pack',   item = 'pump', groups = 5},
        {pack = 'logistic-science-pack',   item = 'storage-tank', groups = 5},
    }},
    {key = 'gridman', recipes = {
        'medium-electric-pole', 'big-electric-pole', 'substation',
    }, name = '电网工人', full = FULL_MID, starter = {
        {item = 'small-electric-pole', groups = 10},
        {item = 'power-switch', groups = 1},
    }, rewards = {
        -- {pack = 'automation-science-pack', item = 'small-electric-pole', groups = 5, full = FULL_LOW},
        {pack = 'logistic-science-pack', item = 'medium-electric-pole', groups = 10, full = FULL_LOW},
        {pack = 'logistic-science-pack',   item = 'big-electric-pole', groups = 10, full = FULL_MID},
        {pack = 'chemical-science-pack', item = 'substation', groups = 10, full = FULL_MAX},
    }},
    {key = 'belter', recipes = {
        'underground-belt', 'splitter',
    }, name = '运输工人', full = FULL_MID, starter = {
        {item = 'transport-belt', groups = 5},
        {item = 'splitter', groups = 2},
        {item = 'underground-belt', groups = 2},
    }, rewards = {
        {pack = 'logistic-science-pack',    item = 'fast-transport-belt', groups = 5, full = FULL_LOW},
        {pack = 'logistic-science-pack',    item = 'fast-splitter', groups = 2, full = FULL_LOW},
        {pack = 'logistic-science-pack',    item = 'fast-underground-belt', groups = 2, full = FULL_LOW},
        --
        {pack = 'production-science-pack',    item = 'express-transport-belt', groups = 5, full = FULL_MID},
        {pack = 'production-science-pack',    item = 'express-splitter', groups = 2, full = FULL_MID},
        {pack = 'production-science-pack',    item = 'express-underground-belt', groups = 2, full = FULL_MID},
        --
        {pack = 'metallurgic-science-pack',    item = 'turbo-transport-belt', groups = 5, full = FULL_MAX},
        {pack = 'metallurgic-science-pack',    item = 'turbo-splitter', groups = 2, full = FULL_MAX},
        {pack = 'metallurgic-science-pack',    item = 'turbo-underground-belt', groups = 2, full = FULL_MAX},
    }},

    {key = 'loaderman', recipes = {

    }, name = '装卸工人', full = FULL_MID, starter = {
        {item = 'loader', count = 1},
    }, rewards = {
        {pack = 'logistic-science-pack',    item = 'loader', groups = 10, full = FULL_LOW},
        {pack = 'logistic-science-pack',    item = 'fast-loader', groups = 10, full = FULL_LOW},
        {pack = 'production-science-pack',  item = 'express-loader', groups = 10, full = FULL_MID},
        {pack = 'metallurgic-science-pack', item = 'turbo-loader', groups = 10, full = FULL_MAX},
    }},
    {key = 'inserter', recipes = {
        'long-handed-inserter', 'fast-inserter', 'bulk-inserter', 'stack-inserter',
    }, name = '斜教', full = FULL_MID, starter = {
        {item = 'burner-inserter', groups = 1},
        {item = 'inserter', groups = 1},
        {item = 'long-handed-inserter', groups = 1},
        {item = 'fast-inserter', groups = 1},
    }, rewards = {
        {pack = 'automation-science-pack',    item = 'inserter', groups = 10, full = FULL_LOW},
        {pack = 'automation-science-pack',    item = 'long-handed-inserter', groups = 10, full = FULL_LOW},
        {pack = 'automation-science-pack',  item = 'fast-inserter', groups = 10, full = FULL_LOW},
        {pack = 'logistic-science-pack', item = 'bulk-inserter', groups = 5, full = FULL_MID},
        {pack = 'agricultural-science-pack', item = 'stack-inserter', groups = 5, full = FULL_MAX},
    }},

    {key = 'traindriver', recipes = {
        'rail', 'locomotive', 'cargo-wagon', 'train-stop',
        'rail-signal', 'rail-chain-signal',
        'rail-ramp', 'rail-support',   -- 高架铁路组件（elevated-rails DLC）
    }, name = '火车司机', full = FULL_LOW, starter = {
        {item = 'locomotive', groups = 1},
        {item = 'cargo-wagon', groups = 1},
        {item = 'fluid-wagon', groups = 1},
    }, rewards = {
        {pack = 'logistic-science-pack',   item = 'rail', groups = 20},
        {pack = 'logistic-science-pack',   item = 'train-stop',        groups = 2},
        {pack = 'logistic-science-pack',   item = 'rail-signal', groups = 2},
        {pack = 'logistic-science-pack',   item = 'rail-chain-signal', groups = 2},
        {pack = 'production-science-pack', item = 'rail-ramp', groups = 5, full = FULL_MID},
        {pack = 'production-science-pack', item = 'rail-support', groups = 5, full = FULL_MID},
    }},

    {key = 'roboticist', recipes = {
        'roboport',
        'storage-chest',
        'flying-robot-frame',
        'construction-robot',
        'logistic-robot',
    }, name = '机械师', full = FULL_MID, starter = {
        {item = 'roboport', count = 1},
        {item = 'construction-robot', count = 10},
    }, rewards = {
        {pack = 'logistic-science-pack',   item = 'construction-robot', groups = 10, full = FULL_LOW},
        {pack = 'logistic-science-pack',   item = 'storage-chest', groups = 10, full = FULL_MID},
        {pack = 'logistic-science-pack',   item = 'roboport', groups = 10, full = FULL_MAX},
        {pack = 'promethium-science-pack',   item = 'logistic-robot', groups = 10, full = FULL_MAX},
    }},

    {key = 'warehouser', recipes = {
        'steel-chest', 'storage-chest', 'passive-provider-chest',
        'active-provider-chest', 'requester-chest', 'buffer-chest',
    }, name = '仓库管理员', full = FULL_MID, starter = {
        {item = 'wooden-chest', groups = 1},
        {item = 'iron-chest', groups = 1},
        {item = 'steel-chest', groups = 1},
        {item = 'storage-chest', groups = 1},
    }, rewards = {
        {pack = 'logistic-science-pack', item = 'storage-chest', groups = 20, full = FULL_MID},
        {pack = 'logistic-science-pack', item = 'passive-provider-chest', groups = 5, full = FULL_MID},
        {pack = 'utility-science-pack',  item = 'requester-chest',        groups = 5, full = FULL_MAX},
        {pack = 'utility-science-pack',  item = 'buffer-chest', groups = 5, full = FULL_MAX},
        {pack = 'utility-science-pack',  item = 'active-provider-chest', groups = 5, full = FULL_MAX},
    }},

    {section = 'space'},

    {key = 'captain', recipes = {
        'rocket-silo', 'cargo-landing-pad',   -- satellite 已被 SA 移除，不列
        'thruster',    -- 由原 techs 转换而来
        'thruster-fuel',
        'thruster-oxidizer',
        {'advanced-thruster-fuel', p = 0.5},
        {'advanced-thruster-oxidizer', p = 0.5},
    }, name = '飞船船长', full = FULL_MID, starter = {
        {item = 'space-platform-starter-pack', count = 1},
    }, unlock = {{pack = 'space-science-pack', level = 100}}, rewards = {
        {pack = 'metallurgic-science-pack',   item = 'low-density-structure',                    groups = 10},
        {pack = 'electromagnetic-science-pack',   item = 'processing-unit',                    groups = 5},
        {pack = 'agricultural-science-pack',   item = 'rocket-fuel',                    groups = 25},
        {pack = 'production-science-pack', item = 'space-platform-foundation', groups = 10},
    }},

    -- 注意：不再送 asteroid-reprocessing / advanced-asteroid-processing 科技（科技会整包解锁下列配方，概率就失效了），改为逐配方概率控制。
    {key = 'asteroidminer', recipes = {
        'metallic-asteroid-crushing',
        'carbonic-asteroid-crushing',
        'oxide-asteroid-crushing',
        {'metallic-asteroid-reprocessing', p = 0.8},
        {'carbonic-asteroid-reprocessing', p = 0.8},
        {'oxide-asteroid-reprocessing', p = 0.8},
        {'advanced-metallic-asteroid-crushing', p = 0.5},
        {'advanced-carbonic-asteroid-crushing', p = 0.5},
        {'advanced-oxide-asteroid-crushing', p = 0.5},
    }, techs = {
        {'asteroid-productivity', p = 0.5},   -- 星岩产能（无限科技）：是科技不是配方，放 techs 才生效
    }, name = '小行星带矿工', full = FULL_MAX, starter = {
        {item = 'space-platform-starter-pack', count = 1},
    }, unlock = {{pack = 'space-science-pack', level = 100}}, rewards = {
        {pack = 'space-science-pack',   item = 'asteroid-collector', groups = 10, full = FULL_MAX},
        {pack = 'space-science-pack',   item = 'crusher',                     groups = 10, full = FULL_MAX},
        {pack = 'space-science-pack',   item = 'cargo-bay',                   groups = 10, full = FULL_MAX},
        {pack = 'space-science-pack',   item = 'thruster',                    groups = 10, full = FULL_MAX},
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
        {pack = 'metallurgic-science-pack', item = 'tungsten-ore', groups = 10, full = FULL_LOW},
        {pack = 'metallurgic-science-pack', item = 'tungsten-plate', groups = 5,  full = FULL_MID},
        {pack = 'metallurgic-science-pack', item = 'big-mining-drill', groups = 2, full = FULL_MAX},
        {pack = 'metallurgic-science-pack', item = 'foundry', groups = 2, full = FULL_MAX},
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
        {pack = 'electromagnetic-science-pack', item = 'scrap', groups = 10, full = FULL_LOW},
        {pack = 'electromagnetic-science-pack', item = 'holmium-plate', groups = 5,  full = FULL_MID},
        {pack = 'electromagnetic-science-pack', item = 'electromagnetic-plant', groups = 2,  full = FULL_MAX},
        {pack = 'electromagnetic-science-pack', item = 'recycler', groups = 2,  full = FULL_MAX},
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
        {pack = 'agricultural-science-pack', item = 'bioflux', groups = 10, full = FULL_LOW},
        {pack = 'agricultural-science-pack', item = 'biochamber', groups = 2,  full = FULL_MAX},
        {pack = 'agricultural-science-pack', item = 'agricultural-tower', groups = 2,  full = FULL_MAX},
    }},

    {key = 'aquilo', techs = {
        'planet-discovery-aquilo',
        'lithium-processing',
        'cryogenic-plant',
    }, recipes = {'heating-tower',}, name = '冰原开拓者', full = FULL_MAX, starter = {
        {item = 'cryogenic-plant', count = 1},
        {item = 'heating-tower', count = 1},
    }, unlock = {{pack = 'military-science-pack', level = 10}}, rewards = {
        {pack = 'cryogenic-science-pack', item = 'lithium-plate', groups = 5, full = FULL_MID},
        {pack = 'cryogenic-science-pack', item = 'cryogenic-plant', groups = 2, full = FULL_MAX},
        {pack = 'cryogenic-science-pack', item = 'heating-tower', groups = 2, full = FULL_MAX},
    }},

    {section = 'planet'},

    {key = 'nuclear', recipes = {
        'centrifuge',                  -- 原 uranium-processing 科技
        'uranium-processing',
        'kovarex-enrichment-process',  -- 原 kovarex-enrichment-process 科技
        'nuclear-fuel',
        'nuclear-fuel-reprocessing',   -- 原 nuclear-fuel-reprocessing 科技
    }, name = '核能专家', full = FULL_MAX, starter = {
        {item = 'centrifuge', groups = 1},
    }, unlock = {{pack = 'production-science-pack', level = 500}}, rewards = {
        {pack = 'chemical-science-pack', item = 'uranium-238', groups = 10, full = FULL_MID},
        {pack = 'chemical-science-pack', item = 'uranium-235', groups = 10, full = FULL_MID},
        {pack = 'chemical-science-pack',   item = 'centrifuge',        groups = 10, full = FULL_MAX},
    }},

    {key = 'metallurgist', recipes = {
        'coal-liquefaction', -- 煤炭液化
    }, techs = {'low-density-structure-productivity'}, name = '铸造专家', full = FULL_MAX, starter = {

    }, unlock = {{pack = 'metallurgic-science-pack', level = 500}}, rewards = {
        {pack = 'metallurgic-science-pack', item = 'foundry', groups = 10},
        {pack = 'metallurgic-science-pack', item = 'big-mining-drill', groups = 10},
    }},
    {key = 'electromancer', recipes = {
        'scrap-recycling', -- 垃圾回收
    }, techs = {'processing-unit-productivity'}, name = '电磁专家', full = FULL_MAX, starter = {

    }, unlock = {{pack = 'electromagnetic-science-pack', level = 500}}, rewards = {
        {pack = 'electromagnetic-science-pack', item = 'electromagnetic-plant', groups = 10},
        {pack = 'electromagnetic-science-pack', item = 'recycler', groups = 10},
    }},
    {key = 'biologist', recipes = {
        'coal-synthesis', -- 煤合成
    }, techs = {'rocket-fuel-productivity'}, name = '生物专家', full = FULL_MAX, starter = {

    }, unlock = {{pack = 'agricultural-science-pack', level = 500}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'biochamber', groups = 10},
        {pack = 'agricultural-science-pack', item = 'agricultural-tower', groups = 10},
    }},
    {key = 'physicist', recipes = {
        'fluoroketone-cooling', -- 氟酮冷却
    }, techs = {'rocket-part-productivity'}, name = '物理专家', full = FULL_MAX, starter = {

    }, unlock = {{pack = 'cryogenic-science-pack', level = 500}}, rewards = {
        {pack = 'cryogenic-science-pack', item = 'cryogenic-plant', groups = 10},
        {pack = 'cryogenic-science-pack', item = 'heating-tower', groups = 10},
    }},
    {key = 'astronomer', techs = {'research-productivity'}, name = '天文专家', full = FULL_MAX, starter = {

    }, unlock = {{pack = 'promethium-science-pack', level = 1000}}, rewards = {
        {pack = 'promethium-science-pack', item = 'biolab', groups = 20},
    }},

    {section = 'combat'},
    -- 分组换行：物流 ↔ 战斗
    -- ── 战斗组（弹药/手雷/核弹；练灰瓶 military，部分另练蓝瓶 chemical）──
    {key = 'guard', recipes = {
         'stone-wall', 'gate', 'radar', 'gun-turret', 'laser-turret', 'flamethrower-turret',
    }, name = '保安', full = FULL_MID, starter = {
        {item = 'stone-wall', groups = 10},
        {item = 'gate', groups = 1},
        {item = 'radar', groups = 1},
    }, rewards = {
        {pack = 'automation-science-pack', item = 'stone-wall', groups = 10, full = FULL_LOW},
        {pack = 'automation-science-pack',        item = 'gun-turret', groups = 10, full = FULL_LOW},
        {pack = 'chemical-science-pack',        item = 'laser-turret',        groups = 10, full = FULL_MAX},
    }},
    {key = 'gunner', recipes = {
        'submachine-gun',
        'firearm-magazine',
        'piercing-rounds-magazine',
        'uranium-rounds-magazine',
    }, name = '田明建', full = FULL_MID, starter = {
        {item = 'submachine-gun', count = 1},
        {item = 'firearm-magazine', groups = 10},
    }, rewards = {
        {pack = 'automation-science-pack', item = 'firearm-magazine', groups = 10, full = FULL_LOW},
        {pack = 'military-science-pack', item = 'piercing-rounds-magazine', groups = 10, full = FULL_MID},
        {pack = 'utility-science-pack', item = 'uranium-rounds-magazine', groups = 10, full = FULL_MAX},
    }},

    {key = 'shotgunner', recipes = {
        'shotgun', 'combat-shotgun',
        'shotgun-shell', 'piercing-shotgun-shell',
    }, name = '山上彻也', full = FULL_LOW, starter = {
        {item = 'combat-shotgun', count = 1},
        {item = 'shotgun-shell', groups = 10},
    }, rewards = {
        {pack = 'military-science-pack', item = 'shotgun-shell', groups = 10, full = FULL_LOW},
        {pack = 'utility-science-pack', item = 'piercing-shotgun-shell', groups = 10, full = FULL_MID},
    }},

    {key = 'flametrooper', recipes = {
        'flamethrower', 'flamethrower-ammo', 'flamethrower-turret',
    }, name = '李梅', full = FULL_MID, starter = {
        {item = 'flamethrower', count = 1},
        {item = 'flamethrower-ammo', groups = 1},
    }, rewards = {
        {pack = 'military-science-pack', item = 'flamethrower-ammo', groups = 10, full = FULL_LOW},
        {pack = 'military-science-pack', item = 'flamethrower-turret', groups = 10, full = FULL_MID},
        {pack = 'utility-science-pack',  item = 'flamethrower-turret', groups = 10, full = FULL_MAX},
    }},

    {key = 'grenadier', recipes = {
        'explosives',
        'grenade',
        'cluster-grenade',
    }, name = '爆破队', full = FULL_MID, starter = {
        {item = 'grenade', groups = 1},
    }, rewards = {
        {pack = 'military-science-pack', item = 'grenade', groups = 20, full = FULL_LOW},
        {pack = 'utility-science-pack',  item = 'cluster-grenade', groups = 20, full = FULL_MID},
    }},
    {key = 'poisoner', recipes = {
        'poison-capsule', 'slowdown-capsule',
    }, name = '毒师', full = FULL_MID, starter = {
        {item = 'poison-capsule', groups = 1},
        {item = 'slowdown-capsule', groups = 1},
    }, rewards = {
        {pack = 'military-science-pack', item = 'poison-capsule', groups = 10, full = FULL_LOW},
        {pack = 'chemical-science-pack', item = 'slowdown-capsule', groups = 10, full = FULL_MID},
        {pack = 'utility-science-pack',  item = 'poison-capsule', groups = 10, full = FULL_MAX},
    }},
    {key = 'droner', recipes = {
        'defender-capsule', {'distractor-capsule', p = 0.8}, {'destroyer-capsule', p = 0.5},
    }, name = 'DJI顾客', full = FULL_MID, starter = {
        {item = 'defender-capsule', count = 20},
    }, rewards = {
        {pack = 'military-science-pack',  item = 'defender-capsule', groups = 10, full = FULL_LOW},
        {pack = 'chemical-science-pack',  item = 'distractor-capsule', groups = 10, full = FULL_MID},
        {pack = 'utility-science-pack',   item = 'destroyer-capsule', groups = 10, full = FULL_MAX},
    }},

    {key = 'minelayer', recipes = {
        'land-mine',
    }, name = '雷神', full = FULL_MID, starter = {
        {item = 'land-mine', count = 200},
    }, unlock = {{pack = 'military-science-pack', level = 100}}, rewards = {
        {pack = 'military-science-pack', item = 'land-mine', groups = 40},
    }},

    {key = 'tanker', recipes = {
        'tank', 'cannon-shell', 'explosive-cannon-shell',
    }, name = '大运司机', full = FULL_MID, starter = {
        {item = 'tank', count = 1},
    }, unlock = {{pack = 'military-science-pack', level = 100}}, rewards = {
        {pack = 'military-science-pack', item = 'tank', groups = 1, full = FULL_MAX},
        --
        {pack = 'military-science-pack', item = 'cannon-shell', groups = 10, full = FULL_LOW},
        {pack = 'chemical-science-pack', item = 'explosive-cannon-shell', groups = 10, full = FULL_MID},
        {pack = 'utility-science-pack', item = 'uranium-cannon-shell', groups = 10, full = FULL_MAX},
        {pack = 'space-science-pack',   item = 'explosive-uranium-cannon-shell', groups = 10, full = FULL_MAX},
    }},
    {key = 'rocketeer', recipes = {
        'rocket-launcher','rocket', 'explosive-rocket', 'atomic-bomb', 
    }, name = '胖子发射器', full = FULL_MAX, starter = {
        {item = 'rocket-launcher', count = 1},
        {item = 'rocket', count = 100},
    }, unlock = {{pack = 'chemical-science-pack', level = 100}}, rewards = {
        {pack = 'military-science-pack', item = 'rocket', groups = 10, full = FULL_LOW},
        {pack = 'chemical-science-pack', item = 'explosive-rocket', groups = 10, full = FULL_MID},
        {pack = 'utility-science-pack',  item = 'atomic-bomb', groups = 10, full = FULL_MAX},
        {pack = 'agricultural-science-pack', item = 'rocket-turret',        groups = 10, full = FULL_MAX},
        --
    }},
    {key = 'artillerist', recipes = {
        'artillery-wagon', 'artillery-turret', 'artillery-shell',
    }, name = '李云龙', full = FULL_MAX, starter = {
        {item = 'artillery-turret', count = 1},
        {item = 'artillery-shell', count = 10},
    }, unlock = {{pack = 'metallurgic-science-pack', level = 100}}, rewards = {
        {pack = 'military-science-pack', item = 'artillery-shell', groups = 20, full = FULL_MID},
        {pack = 'metallurgic-science-pack',  item = 'artillery-wagon', groups = 10, full = FULL_MAX},
        {pack = 'metallurgic-science-pack', item = 'artillery-turret', groups = 10, full = FULL_MAX},
    }},
    {key = 'teslatrooper', recipes = {
        'teslagun', 'tesla-turret', 'tesla-ammo',
    }, name = '杨永信', full = FULL_MAX, starter = {
        {item = 'teslagun', count = 1},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 100}}, rewards = {
        {pack = 'electromagnetic-science-pack', item = 'tesla-ammo', groups = 10, full = FULL_MID},
        {pack = 'electromagnetic-science-pack', item = 'tesla-turret', groups = 10, full = FULL_MAX},
    }},
    {key = 'railgunner', recipes = {
        'railgun', 'railgun-turret', 'railgun-ammo',
    }, name = '御坂美琴', full = FULL_MAX, starter = {
        {item = 'railgun', count = 1},
    }, unlock = {{pack = 'cryogenic-science-pack', level = 500}}, rewards = {
        {pack = 'cryogenic-science-pack', item = 'railgun-ammo', groups = 20, full = FULL_MID},
        {pack = 'cryogenic-science-pack', item = 'railgun-turret', groups = 10, full = FULL_MAX},
    }},

    {key = 'spidertron', recipes = {
        'spidertron',
    }, name = '蜘蛛侠', full = FULL_MAX, starter = {
        {item = 'spidertron', count = 1},
    }, unlock = {{pack = 'utility-science-pack', level = 1000}}, rewards = {

    }},

    {key = 'mechpilot', recipes = {
        'mech-armor',
    }, name = '变形金刚', full = FULL_MAX, starter = {   -- 终极机甲：粉瓶 1000 级解锁
        {item = 'mech-armor', count = 1},
    }, unlock = {{pack = 'electromagnetic-science-pack', level = 1000}}, rewards = {

    }},

    {section = 'gear'},
    -- 分组换行：战斗 ↔ 装备护甲
    -- ── 装备护甲组（护甲网格组件 + 终极机甲；按各组件解锁科技配瓶）──
    -- 角色网格分工：每个职业专精一类护甲网格组件。
    {key = 'shielder', recipes = {
        'energy-shield-equipment',
        'energy-shield-mk2-equipment',
    }, name = '肉盾', full = FULL_MAX, starter = {   -- 全是盾
        {item = 'energy-shield-equipment', count = 20},
    }, rewards = {
        {pack = 'military-science-pack', item = 'energy-shield-equipment', groups = 10, full = FULL_LOW},
        {pack = 'utility-science-pack',  item = 'energy-shield-mk2-equipment', groups = 10, full = FULL_MAX},
    }},
    {key = 'powergear', recipes = {
        'solar-panel-equipment',
        'fission-reactor-equipment',
        'fusion-reactor-equipment',
        'battery-equipment',
        'battery-mk2-equipment',
        'battery-mk3-equipment',
    }, name = '奶妈', full = FULL_MAX, starter = {   -- 发电+储能装置
        {item = 'fission-reactor-equipment', count = 1},
    }, rewards = {
        {pack = 'logistic-science-pack',  item = 'solar-panel-equipment', groups = 10, full = FULL_LOW},
        {pack = 'chemical-science-pack',  item = 'fission-reactor-equipment', groups = 5, full = FULL_MID},
        {pack = 'cryogenic-science-pack', item = 'fusion-reactor-equipment', groups = 2, full = FULL_MAX},
        --
        {pack = 'military-science-pack',  item = 'battery-equipment', groups = 10, full = FULL_LOW},
        {pack = 'utility-science-pack',   item = 'battery-mk2-equipment', groups = 5, full = FULL_MID},
        {pack = 'utility-science-pack',   item = 'battery-mk3-equipment', groups = 2, full = FULL_MAX},
    }},
    {key = 'laserdefense', recipes = {
        'personal-laser-defense-equipment',
    }, name = '输出', full = FULL_MAX, starter = {   -- 全是激光
        {item = 'personal-laser-defense-equipment', count = 3},
    }, rewards = {
        {pack = 'chemical-science-pack', item = 'personal-laser-defense-equipment', groups = 10},
        {pack = 'military-science-pack', item = 'personal-laser-defense-equipment', groups = 10},
    }},
    {key = 'roboportgear', recipes = {
        'personal-roboport-equipment',
        'personal-roboport-mk2-equipment',
    }, name = '辅助', full = FULL_MAX, starter = {   -- 全是机器人
        {item = 'personal-roboport-equipment', count = 5},
        {item = 'personal-roboport-equipment', groups = 1},
    }, rewards = {
        {pack = 'chemical-science-pack', item = 'personal-roboport-equipment', groups = 10, full = FULL_MID},
        {pack = 'electromagnetic-science-pack',  item = 'personal-roboport-mk2-equipment', count = 10, full = FULL_MAX},
    }},
    {key = 'exoskeleton', recipes = {
        'exoskeleton-equipment',
    }, name = '快递员', full = FULL_MAX, starter = {   -- 全是外骨骼
        {item = 'exoskeleton-equipment', count = 2},
    }, rewards = {
        {pack = 'chemical-science-pack', item = 'exoskeleton-equipment', groups = 20},
    }},
    {key = 'toolbelt', recipes = {
        'toolbelt-equipment',
    }, name = '吃货', full = FULL_MAX, starter = {   -- 全是工具腰带
        {item = 'toolbelt-equipment', count = 1},
    }, rewards = {
        {pack = 'agricultural-science-pack', item = 'toolbelt-equipment', groups = 20},
    }},

    {section = 'farm'},
    -- 分组换行：装备护甲 ↔ 农牧
    -- ── 农牧组（鱼/虫卵/种子/腐败物，Gleba 生态，主练草瓶 agricultural）──
    {key = 'hunter', recipes = {
        'capture-robot-rocket', 'biter-egg', 'nutrients-from-biter-egg',
    }, name = '猎手', full = FULL_MID, starter = {
        {item = 'biter-egg', count = 1},
        {item = 'rocket-launcher', count = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'capture-robot-rocket', groups = 10},
        {pack = 'space-science-pack', item = 'bioflux', groups = 10},
        {pack = 'agricultural-science-pack', item = 'bioflux', groups = 10},
        {pack = 'promethium-science-pack', item = 'bioflux', groups = 10},
    }},
    {key = 'herder', recipes = {
        'pentapod-egg', 'nutrients-from-bioflux', 'biochamber'
    }, name = '牧民', full = FULL_MID, starter = {
        {item = 'pentapod-egg', count = 1},
        {item = 'biochamber', count = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'bioflux', groups = 40},
    }},

    {key = 'fisher', recipes = {
        'fish-breeding', 'nutrients-from-fish',
        'copper-bacteria-cultivation', 'iron-bacteria-cultivation',
    }, name = '渔夫', full = FULL_LOW, starter = {
        {item = 'raw-fish', groups = 1},
        {item = 'biochamber', count = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'space-science-pack', item = 'raw-fish', groups = 10},
        {pack = 'agricultural-science-pack', item = 'raw-fish', groups = 10},
        {pack = 'promethium-science-pack', item = 'raw-fish', groups = 10},
        {pack = 'agricultural-science-pack', item = 'iron-bacteria', groups = 2},
        {pack = 'agricultural-science-pack', item = 'copper-bacteria', groups = 2},
    }},

    {key = 'farmer', recipes = {
        'agricultural-tower', 'nutrients-from-spoilage', 'jellynut-processing', 'yumako-processing',
    }, name = '农民', full = FULL_MID, starter = {
        {item = 'yumako-seed', groups = 2},
        {item = 'jellynut-seed', groups = 2},
        {item = 'agricultural-tower', count = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'artificial-yumako-soil', groups = 10},
        {pack = 'agricultural-science-pack', item = 'overgrowth-yumako-soil', groups = 10},
        {pack = 'agricultural-science-pack', item = 'artificial-jellynut-soil', groups = 10},
        {pack = 'agricultural-science-pack', item = 'overgrowth-jellynut-soil', groups = 10},
    }},
    {key = 'forester', recipes = {
        'wood-processing',
    }, name = '护林员', full = FULL_MID, starter = {
        {item = 'wood', groups = 2},
        {item = 'tree-seed', groups = 2},
        {item = 'agricultural-tower', count = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'automation-science-pack', item = 'wood', groups = 10, full = FULL_LOW},
        {pack = 'space-science-pack', item = 'landfill', groups = 10, full = FULL_MID},
        {pack = 'agricultural-science-pack', item = 'landfill', groups = 10, full = FULL_MID},
        {pack = 'promethium-science-pack', item = 'landfill', groups = 10, full = FULL_MAX},
    }},
    {key = 'chef', recipes = {
        'bioflux', 'nutrients-from-bioflux', 'nutrients-from-spoilage', 'jellynut-processing',  'yumako-processing',
    }, name = '厨师', full = FULL_MID, starter = {
        {item = 'biochamber', groups = 1},
    }, unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'yumako', groups = 10},
        {pack = 'agricultural-science-pack', item = 'yumako-mash', groups = 10},
        {pack = 'agricultural-science-pack', item = 'jellynut', groups = 10},
        {pack = 'agricultural-science-pack', item = 'jelly', groups = 10},
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

-- techs/recipes 条目归一化：'名'（恒解锁）或 {'名', p = 0~1}（每轮按概率解锁）。
-- 返回 科技名, 解锁概率（缺省 1）。所有遍历 techs 的地方统一经此取名，避免各处自判类型。
function M.tech_entry(t)
    if type(t) == 'table' then return t[1], t.p or 1 end
    return t, 1
end

-- 按 key 找职业定义（遍历当前表；职业数少、不缓存，确保 /c 改后即时生效）。
function M.def_for_key(key)
    if not key then return nil end
    for _, def in ipairs(M.all()) do
        if def.key == key then return def end
    end
    return nil
end

-- 玩家【预约】职业 key（storage.player_class，下次跃迁/下次开局生效；未选 → 默认职业 civilian）。
-- 历史名 selected_key 保留：它一直就是"玩家选的、待生效"的职业，现明确语义为【预约】。
function M.selected_key(player)
    return player and ((storage.player_class or {})[player.name] or M.DEFAULT)
end

-- 玩家【当前】职业 key（storage.player_class_current，本世界实际生效的职业；未落定 → 默认 civilian）。
-- 在【发放起手装备】时由 commit_current 落定（装备按预约职业发，故当前职业 = 那一刻的预约职业）。
function M.current_key(player)
    return player and ((storage.player_class_current or {})[player.name] or M.DEFAULT)
end

-- 把【预约】职业落定为【当前】职业：发起手装备时调用（见 respawn_gifts.on_first_respawn）。
-- 覆盖所有"进入本世界"的情形：跃迁后复活、开局直接进、后进服首次拥有角色——都在发装备那一刻落定。
function M.commit_current(player)
    if not player then return end
    storage.player_class_current = storage.player_class_current or {}
    storage.player_class_current[player.name] = M.selected_key(player)
end

-- 职业【专属解锁】明细：返回当前【有在线玩家选用、且配了 techs/recipes】的职业列表，
--   每项 {key=, name=, techs={...}, recipes={...}}。
-- reset 据此开局解锁科技/配方【并按职业广播】"什么职业解锁了什么" → 故按职业分组、不在此处去重。
function M.active_class_unlocks()
    -- 按职业 key 统计【跃迁此刻在线】且预约了该职业的玩家人数（预约职业 = 本轮生效职业，
    -- 与 reset 的掷点通报同一匹配口径）。【只数在线】：无限科技按人数叠级（class_tech_stack），
    -- 若按 player_class 名单累计（含离线/已流失玩家，按名字存、从不清理），等级会随服务器生涯单调爬升。
    -- 离线成员回归后，下次跃迁自然重新计入；职业预约(player_class)本身不清，回归仍是原职业。
    local count = {}
    for _, pl in pairs(game.connected_players) do
        local key = (storage.player_class or {})[pl.name]
        if key then count[key] = (count[key] or 0) + 1 end
    end
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

-- 玩家【预约】职业定义（下次生效，一定返回一个，兜底默认职业 civilian）。
-- 发起手装备(respawn_gifts)按此发 → 决定本世界的当前职业。
function M.def_of(player)
    return M.def_for_key(M.selected_key(player)) or M.def_for_key(M.DEFAULT)
end

-- 玩家【当前】职业定义（本世界实际生效，一定返回一个，兜底默认）。玩家列表显示用。
function M.current_def(player)
    return M.def_for_key(M.current_key(player)) or M.def_for_key(M.DEFAULT)
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
