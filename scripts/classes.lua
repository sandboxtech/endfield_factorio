-- 职业系统：每个职业决定开局发什么物品。玩家随时在【职业】窗口切换（同时只能一种，存 storage.player_class[名]，带短冷却）。
-- 进服默认 = 平民（未选 → 按平民，见 M.DEFAULT / selected_key 兜底）。
--
-- 【职业表存 storage.classes，可热改】：DEFAULT_CLASSES 只是初始默认，M.ensure() 深拷贝进 storage.classes。
--   /c storage.classes[2].full = 1000   改某职业满级线；  /c storage.classes = nil  清空恢复默认。
--   也可整体热更：把 set_classes.txt 全文粘进控制台（/sc storage.classes = {...}）。
--
-- 字段：
--   name     职业显示名（中文字符串，直接显示、绕过 locale）。
--   full     职业级满级线（可选，默认 MAX_LEVEL=10000）：该职业每种相关瓶练到 full 级，即拿满所有 rewards 的
--            groups 组——这就是这个职业的“完美追求”目标等级。full 三档：基础速成 100 / 进阶 1000 / 终极 10000(默认)；
--            full 越大越难满、满级回报越丰厚。价值高低主要靠物品档次体现(廉价职业=低 full，稀有/终极职业=高 full)。
--   starter  无条件初始物品列表：每条 {item=物品, count=个数 或 groups=组数}；count 个 > groups 组 > 默认 1 组。
--   rewards  经验奖励列表：每条 {pack=瓶, item=物品, groups=满配额组数}；按该瓶等级线性发，
--            个数 = floor(堆叠 × groups × min(瓶等级, full) / full)。pack 按物品在科技树的解锁层级配。
--   unlock   解锁条件(可选)：每条 {pack=瓶, level=级}，需全满足；无则人人可选。
--   {}       空表 = 占位，在职业窗口里作【换行/分组】分隔（无 key，选不到）。
--
-- 【容量约束】每个职业「满级资源含量」（starter 固定组 + 各 rewards 满级 groups 之和）控制在 50 组以内。
local passives = require('scripts.passives')

local M = {}

M.DEFAULT = 'civilian'
M.MAX_LEVEL = 10000   -- 满级基准（与 respawn_gifts.MAX_LEVEL / gui CLASS_MAX_LEVEL 一致）；未配 full 的职业兜底用它

-- 默认职业表（顺序即面板显示顺序），分组：生产 / 物流 / 战斗 / 装备 / 农牧 / 科学星球 / 太空 / 终极，空职业 {} 分隔。
local DEFAULT_CLASSES = {
    -- ── 生产组（基础材料/机器/流体/能源；满级线低，开局就能攒到大宗）──
    {key = 'civilian', name = '平民', full = 100, starter = {
        {item = 'burner-mining-drill', count = 1},
        {item = 'transport-belt'},
        {item = 'coal', groups = 3}, {item = 'iron-plate', groups = 3},
        {item = 'copper-plate', groups = 2}, {item = 'stone', groups = 2}}, rewards = {
        {pack = 'automation-science-pack', item = 'iron-ore',   groups = 10},
        {pack = 'automation-science-pack', item = 'copper-ore', groups = 8},
        {pack = 'automation-science-pack', item = 'coal',       groups = 5},
        {pack = 'automation-science-pack', item = 'stone',      groups = 5}}},
    {key = 'smelter', name = '炉工', full = 100, starter = {
        {item = 'stone-furnace', count = 50},
        {item = 'coal', groups = 5}, {item = 'iron-ore', groups = 3}, {item = 'copper-ore', groups = 2}}, rewards = {
        {pack = 'automation-science-pack', item = 'coal',       groups = 1},
        {pack = 'automation-science-pack', item = 'iron-ore',   groups = 10},
        {pack = 'automation-science-pack', item = 'copper-ore', groups = 5},
        {pack = 'automation-science-pack', item = 'stone',      groups = 2}}},
    {key = 'miner', name = '矿工', full = 100, starter = {
        {item = 'electric-mining-drill', count = 50},
        {item = 'stone', groups = 3}, {item = 'iron-plate', groups = 3}, {item = 'coal', groups = 3}}, rewards = {
        {pack = 'automation-science-pack',  item = 'electric-mining-drill', groups = 10},
        {pack = 'metallurgic-science-pack', item = 'big-mining-drill',      groups = 10},
        {pack = 'automation-science-pack',  item = 'iron-ore',   groups = 10},
        {pack = 'automation-science-pack',  item = 'copper-ore', groups = 8}}},
    {key = 'steelworker', name = '炼钢工', full = 100, starter = {
        {item = 'steel-furnace', count = 50},
        {item = 'coal', groups = 5}, {item = 'iron-ore', groups = 5}}, rewards = {
        {pack = 'automation-science-pack', item = 'coal',        groups = 1},
        {pack = 'automation-science-pack', item = 'iron-plate',  groups = 15},
        {pack = 'automation-science-pack', item = 'steel-plate', groups = 3},
        {pack = 'automation-science-pack', item = 'copper-plate', groups = 10}}},
    {key = 'artisan', name = '螺丝装配工', full = 100, starter = {
        {item = 'assembling-machine-1', count = 50},
        {item = 'iron-plate', groups = 5}, {item = 'iron-gear-wheel', groups = 3}}, rewards = {
        {pack = 'automation-science-pack', item = 'assembling-machine-1', groups = 1},
        {pack = 'automation-science-pack', item = 'iron-plate',      groups = 12},
        {pack = 'automation-science-pack', item = 'iron-gear-wheel', groups = 6},
        {pack = 'automation-science-pack', item = 'copper-plate',    groups = 5}}},
    {key = 'circuiter', name = '电路装配工', full = 100, starter = {
        {item = 'assembling-machine-1', count = 50},
        {item = 'iron-plate', groups = 4}, {item = 'copper-plate', groups = 4}, {item = 'copper-cable', groups = 3}}, rewards = {
        {pack = 'automation-science-pack', item = 'assembling-machine-1', groups = 1},
        {pack = 'automation-science-pack', item = 'copper-cable',       groups = 8},
        {pack = 'automation-science-pack', item = 'electronic-circuit', groups = 4},
        {pack = 'automation-science-pack', item = 'iron-plate',         groups = 2}}},
    {key = 'electrician', name = '烧煤工', full = 100, starter = {
        {item = 'coal', groups = 5},
        {item = 'small-electric-pole', groups = 1}, {item = 'iron-plate', groups = 2}}, rewards = {
        {pack = 'production-science-pack', item = 'small-electric-pole', groups = 5},
        {pack = 'automation-science-pack', item = 'boiler',             groups = 10},
        {pack = 'production-science-pack', item = 'steam-engine',       groups = 10}}},
    {key = 'greentech', name = '环保人士', full = 100, starter = {
        {item = 'medium-electric-pole', count = 50},
        {item = 'solar-panel', count = 25}, {item = 'iron-plate', groups = 2}}, rewards = {
        {pack = 'automation-science-pack', item = 'medium-electric-pole', groups = 2},
        {pack = 'logistic-science-pack',   item = 'solar-panel',          groups = 10},
        {pack = 'chemical-science-pack',   item = 'efficiency-module',     groups = 2},
        {pack = 'production-science-pack', item = 'accumulator',          groups = 5}}},
    {key = 'chemist', name = '化学家', full = 100, starter = {
        {item = 'chemical-plant', count = 50},
        {item = 'coal', groups = 3}, {item = 'iron-plate', groups = 2}}, rewards = {
        {pack = 'chemical-science-pack', item = 'plastic-bar', groups = 8},
        {pack = 'chemical-science-pack', item = 'sulfur',      groups = 8},
        {pack = 'chemical-science-pack', item = 'battery',     groups = 8}}},
    {key = 'oilman', name = '石油工人', full = 1000, starter = {
        {item = 'pumpjack', count = 10}, {item = 'oil-refinery', count = 5}, {item = 'pipe', groups = 3}}, rewards = {
        {pack = 'automation-science-pack', item = 'pipe',         groups = 10},
        {pack = 'logistic-science-pack',   item = 'pumpjack',     groups = 5},
        {pack = 'chemical-science-pack',   item = 'oil-refinery', groups = 5},
        {pack = 'logistic-science-pack',   item = 'storage-tank', groups = 3}}},
    {key = 'plumber', name = '管道工', full = 1000, starter = {
        {item = 'pipe', groups = 5}, {item = 'pipe-to-ground', count = 50}, {item = 'pump', count = 20}}, rewards = {
        {pack = 'automation-science-pack', item = 'pipe',           groups = 10},
        {pack = 'automation-science-pack', item = 'pipe-to-ground', groups = 8},
        {pack = 'logistic-science-pack',   item = 'pump',           groups = 5},
        {pack = 'logistic-science-pack',   item = 'storage-tank',   groups = 3},
        {pack = 'automation-science-pack', item = 'offshore-pump',  groups = 2}}},
    {key = 'uraniumminer', name = '铀矿工人', full = 1000, starter = {
        {item = 'electric-mining-drill', count = 20}, {item = 'pipe', groups = 3},
        {item = 'sulfuric-acid-barrel', count = 20}, {item = 'uranium-ore', groups = 2}}, rewards = {
        {pack = 'chemical-science-pack',   item = 'uranium-ore',           groups = 10},
        {pack = 'automation-science-pack', item = 'electric-mining-drill', groups = 5},
        {pack = 'chemical-science-pack',   item = 'sulfuric-acid-barrel',  groups = 3},
        {pack = 'automation-science-pack', item = 'pipe',                  groups = 5}}},
    {key = 'enricher', name = '铀浓缩工人', full = 1000, starter = {
        {item = 'centrifuge', count = 10}, {item = 'uranium-ore', groups = 3},
        {item = 'uranium-235', count = 5}, {item = 'uranium-238', groups = 1}}, rewards = {
        {pack = 'chemical-science-pack', item = 'centrifuge',  groups = 3},
        {pack = 'chemical-science-pack', item = 'uranium-ore', groups = 10},
        {pack = 'chemical-science-pack', item = 'uranium-235', groups = 5},
        {pack = 'chemical-science-pack', item = 'uranium-238', groups = 8}}},
    {key = 'nuclearman', name = '核电工人', full = 1000, starter = {
        {item = 'nuclear-reactor', count = 1}, {item = 'heat-pipe', groups = 1},
        {item = 'heat-exchanger', count = 10}, {item = 'steam-turbine', count = 20}}, rewards = {
        {pack = 'chemical-science-pack', item = 'uranium-fuel-cell',          groups = 8},
        {pack = 'chemical-science-pack', item = 'depleted-uranium-fuel-cell', groups = 8},
        {pack = 'chemical-science-pack', item = 'centrifuge',                 groups = 3}}},
    {key = 'recyclerman', name = '回收工人', full = 1000, starter = {{item = 'recycler', count = 1}}, rewards = {
        {pack = 'production-science-pack', item = 'recycler', groups = 5},
        {pack = 'production-science-pack', item = 'scrap',    groups = 15}}},

    {},   -- 分组换行：生产 ↔ 物流

    -- ── 物流组（机器人/传送带/箱子；练绿瓶 logistic）──
    {key = 'roboticist', name = '机械师', full = 1000, starter = {
        {item = 'roboport', count = 10},
        {item = 'construction-robot', count = 50}, {item = 'storage-chest', groups = 1}, {item = 'iron-plate', groups = 2}}, rewards = {
        {pack = 'logistic-science-pack', item = 'construction-robot',     groups = 10},
        {pack = 'logistic-science-pack', item = 'logistic-robot',         groups = 10},
        {pack = 'logistic-science-pack', item = 'storage-chest',          groups = 2},
        {pack = 'logistic-science-pack', item = 'passive-provider-chest', groups = 2},
        {pack = 'logistic-science-pack', item = 'active-provider-chest',  groups = 2},
        {pack = 'logistic-science-pack', item = 'requester-chest',        groups = 2},
        {pack = 'logistic-science-pack', item = 'buffer-chest',           groups = 2}}},
    {key = 'belter', name = '输送工', full = 100, starter = {   -- 低级款：黄传送带 + 黄机械臂
        {item = 'transport-belt'},
        {item = 'inserter', groups = 1}, {item = 'underground-belt', count = 20}, {item = 'splitter', count = 10}}, rewards = {
        {pack = 'logistic-science-pack',   item = 'transport-belt',   groups = 10},
        {pack = 'automation-science-pack', item = 'inserter',         groups = 10},
        {pack = 'automation-science-pack', item = 'underground-belt', groups = 5},
        {pack = 'automation-science-pack', item = 'splitter',         groups = 5}}},
    {key = 'warehouser', name = '仓库管理员', full = 1000, starter = {
        {item = 'wooden-chest', groups = 2}, {item = 'iron-chest', groups = 2},
        {item = 'steel-chest', groups = 2}, {item = 'storage-chest', groups = 1}}, rewards = {
        {pack = 'logistic-science-pack', item = 'steel-chest',            groups = 10},
        {pack = 'logistic-science-pack', item = 'storage-chest',          groups = 8},
        {pack = 'logistic-science-pack', item = 'passive-provider-chest', groups = 5},
        {pack = 'logistic-science-pack', item = 'requester-chest',        groups = 5},
        {pack = 'logistic-science-pack', item = 'buffer-chest',           groups = 5}}},

    {},   -- 分组换行：物流 ↔ 战斗

    -- ── 战斗组（弹药/手雷/核弹；练灰瓶 military，部分另练蓝瓶 chemical）──
    {key = 'guard', name = '守卫', full = 1000, starter = {
        {item = 'gun-turret', count = 1}, {item = 'firearm-magazine', groups = 1}}, rewards = {
        {pack = 'military-science-pack', item = 'gun-turret',               groups = 5},
        {pack = 'military-science-pack', item = 'firearm-magazine',         groups = 10},
        {pack = 'military-science-pack', item = 'piercing-rounds-magazine', groups = 10}}},
    {key = 'gunner', name = '机枪手', full = 1000, starter = {
        {item = 'submachine-gun', count = 1}, {item = 'firearm-magazine', groups = 1}}, rewards = {
        {pack = 'military-science-pack', item = 'firearm-magazine',         groups = 10},
        {pack = 'military-science-pack', item = 'piercing-rounds-magazine', groups = 10}}},
    {key = 'tanker', name = '坦克手', full = 1000, starter = {
        {item = 'tank', count = 1}, {item = 'rocket-fuel'}, {item = 'cannon-shell', groups = 1}}, rewards = {
        {pack = 'military-science-pack', item = 'cannon-shell',     groups = 10},
        {pack = 'chemical-science-pack', item = 'explosive-rocket', groups = 10}}},
    {key = 'rocketeer', name = '火箭筒兵', full = 1000, starter = {
        {item = 'rocket-launcher', count = 1}, {item = 'rocket', groups = 1}}, rewards = {
        {pack = 'military-science-pack', item = 'rocket',           groups = 10},
        {pack = 'chemical-science-pack', item = 'explosive-rocket', groups = 10}}},
    {key = 'artillerist', name = '炮兵', full = 1000, starter = {
        {item = 'artillery-turret', count = 1}, {item = 'artillery-shell', count = 5}}, rewards = {
        {pack = 'military-science-pack', item = 'artillery-shell',  groups = 10},
        {pack = 'military-science-pack', item = 'artillery-turret', groups = 3}}},
    {key = 'bomber', name = '投弹手', full = 1000, starter = {{item = 'grenade', groups = 2}}, rewards = {
        {pack = 'logistic-science-pack', item = 'grenade',         groups = 10},
        {pack = 'utility-science-pack',  item = 'cluster-grenade', groups = 10}}},
    {key = 'nuker', name = '核弹玩家', full = 10000, starter = {
        {item = 'rocket-launcher', count = 1}, {item = 'atomic-bomb', count = 2}},
        unlock = {{pack = 'utility-science-pack', level = 1000}}, rewards = {   -- 需黄瓶 1000 级解锁
        {pack = 'utility-science-pack', item = 'atomic-bomb', groups = 5}}},
    {key = 'transformer', name = '变形金刚', starter = {{item = 'mech-armor', count = 1}},
        unlock = {{pack = 'electromagnetic-science-pack', level = 1000}}},   -- 需粉瓶(电磁) 1000 级解锁
    {},   -- 分组换行：战斗 ↔ 装备

    -- ── 装备组（护甲网格组件；按各组件解锁科技配瓶）──
    {key = 'toolman', name = '工具人', full = 1000, starter = {{item = 'toolbelt-equipment', count = 1}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'toolbelt-equipment', groups = 5}}},
    {key = 'outfitter', name = '服装设计师', full = 1000, starter = {
        {item = 'solar-panel-equipment', count = 2}, {item = 'battery-equipment', count = 2}, {item = 'night-vision-equipment', count = 1}}, rewards = {
        {pack = 'logistic-science-pack', item = 'solar-panel-equipment',      groups = 3},
        {pack = 'logistic-science-pack', item = 'battery-equipment',          groups = 3},
        {pack = 'logistic-science-pack', item = 'night-vision-equipment',     groups = 2},
        {pack = 'chemical-science-pack', item = 'personal-roboport-equipment', groups = 3},
        {pack = 'chemical-science-pack', item = 'exoskeleton-equipment',      groups = 3},
        {pack = 'military-science-pack', item = 'energy-shield-equipment',    groups = 3}}},

    {},   -- 分组换行：装备 ↔ 农牧

    -- ── 农牧组（鱼/虫卵/种子/腐败物，Gleba 生态，主练草瓶 agricultural）──
    {key = 'bugkeeper', name = '虫师', full = 1000, starter = {{item = 'pentapod-egg', count = 1}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'raw-fish', groups = 10}}},
    {key = 'fisher', name = '渔夫', full = 1000, starter = {
        {item = 'raw-fish', groups = 2}, {item = 'spoilage', groups = 2}, {item = 'inserter', groups = 1}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'raw-fish',  groups = 10},
        {pack = 'agricultural-science-pack', item = 'spoilage',  groups = 8},
        {pack = 'automation-science-pack',   item = 'inserter',  groups = 5}}},
    {key = 'farmer', name = '农夫', full = 1000, starter = {
        {item = 'agricultural-tower', count = 5},
        {item = 'yumako-seed', groups = 2}, {item = 'jellynut-seed', groups = 2}, {item = 'tree-seed', groups = 2}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'yumako-seed',       groups = 8},
        {pack = 'agricultural-science-pack', item = 'jellynut-seed',     groups = 8},
        {pack = 'agricultural-science-pack', item = 'tree-seed',         groups = 5},
        {pack = 'agricultural-science-pack', item = 'agricultural-tower', groups = 5}}},

    {},   -- 分组换行：农牧 ↔ 科学/星球

    -- ── 科学/星球组（各星球招牌机器/材料；满级线 1000，需对应瓶 100 级解锁）──
    {key = 'astronaut', name = '宇航专家', full = 1000, starter = {
        {item = 'rocket-silo', count = 1}, {item = 'iron-plate', groups = 3}, {item = 'copper-plate', groups = 3}},
        unlock = {{pack = 'space-science-pack', level = 100}}, rewards = {  -- 白
        {pack = 'space-science-pack', item = 'space-platform-starter-pack', groups = 10}}},
    {key = 'metallurgist', name = '冶金学家', full = 1000, starter = {
        {item = 'foundry', count = 1}, {item = 'iron-ore', groups = 3}, {item = 'stone', groups = 3}, {item = 'coal', groups = 3}},
        unlock = {{pack = 'metallurgic-science-pack', level = 100}}, rewards = {  -- 橙(火山)
        {pack = 'metallurgic-science-pack', item = 'tungsten-plate', groups = 10},
        {pack = 'metallurgic-science-pack', item = 'tungsten-ore',   groups = 10}}},
    {key = 'electromancer', name = '电磁专家', full = 1000, starter = {
        {item = 'electromagnetic-plant', count = 1}, {item = 'iron-plate', groups = 3}, {item = 'copper-plate', groups = 3}},
        unlock = {{pack = 'electromagnetic-science-pack', level = 100}}, rewards = {  -- 粉(电浆星)
        {pack = 'electromagnetic-science-pack', item = 'accumulator',    groups = 10},
        {pack = 'electromagnetic-science-pack', item = 'supercapacitor', groups = 10},
        {pack = 'electromagnetic-science-pack', item = 'holmium-plate',  groups = 8}}},
    {key = 'biologist', name = '生物专家', full = 1000, starter = {
        {item = 'agricultural-tower', count = 1}, {item = 'iron-plate', groups = 3}},
        unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {  -- 草(Gleba)
        {pack = 'agricultural-science-pack', item = 'biochamber', groups = 10},
        {pack = 'agricultural-science-pack', item = 'carbon',     groups = 8}}},
    {key = 'physicist', name = '物理学家', full = 1000, starter = {
        {item = 'cryogenic-plant', count = 1}, {item = 'iron-plate', groups = 3}, {item = 'solid-fuel', groups = 2}},
        unlock = {{pack = 'cryogenic-science-pack', level = 100}}, rewards = {  -- 靛(Aquilo)
        {pack = 'cryogenic-science-pack', item = 'fusion-reactor', groups = 10},
        {pack = 'cryogenic-science-pack', item = 'lithium-plate',  groups = 8}}},
    {key = 'astronomer', name = '天文学家', full = 1000, starter = {
        {item = 'lab', count = 1}, {item = 'iron-plate', groups = 3}},
        unlock = {{pack = 'promethium-science-pack', level = 100}}, rewards = {  -- 黑(promethium)
        {pack = 'promethium-science-pack', item = 'biolab', groups = 10}}},

    {},   -- 分组换行：科学/星球 ↔ 太空

    -- ── 太空组（星际平台组件；触发式科技无瓶的按太空领域白瓶）──
    {key = 'pilot', name = '飞船驾驶员', full = 1000, starter = {
        {item = 'asteroid-collector', count = 2}, {item = 'thruster', count = 2},
        {item = 'cargo-bay', count = 2}, {item = 'crusher', count = 2}}, rewards = {
        {pack = 'space-science-pack',   item = 'thruster',                  groups = 5},
        {pack = 'utility-science-pack', item = 'space-platform-foundation', groups = 10},
        {pack = 'space-science-pack',   item = 'asteroid-collector',        groups = 5},
        {pack = 'space-science-pack',   item = 'crusher',                   groups = 5}}},
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

-- 玩家当前选择的职业 key（未选 → 默认平民）。
function M.selected_key(player)
    return player and ((storage.player_class or {})[player.name] or M.DEFAULT)
end

-- 玩家当前职业定义（一定返回一个，兜底平民）。
function M.def_of(player)
    return M.def_for_key(M.selected_key(player)) or M.def_for_key(M.DEFAULT)
end

-- 玩家某瓶当前等级（= floor√经验）。
function M.pack_level(player, pack)
    return math.floor(math.sqrt(passives.exp_total_for_pack(player.index, pack)))
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

return M
