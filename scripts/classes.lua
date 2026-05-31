-- 职业系统：每个职业决定开局发什么物品。玩家随时在【职业】窗口切换（同时只能一种，存 storage.player_class[名]，带短冷却）。
-- 进服默认 = 平民（未选 → 按平民，见 M.DEFAULT / selected_key 兜底）。
--
-- 【职业表存 storage.classes，可热改】：DEFAULT_CLASSES 只是初始默认，M.ensure() 深拷贝进 storage.classes。
--   /c storage.classes[2].rewards[1].groups = 5   改某条奖励组数；  /c storage.classes = nil  清空恢复默认。
--   也可整体热更：把 set_classes.txt 全文粘进控制台（/sc storage.classes = {...}）。
--
-- 字段：
--   name     职业显示名（中文字符串，直接显示、绕过 locale）。
--   starter  无条件初始物品列表：每条 {item=物品, count=个数 或 groups=组数}；
--            发放优先级 = count 个 > groups 组 > 默认 1 组(=1 堆叠)。机器/武器用 count，低价值原料用 groups。
--   rewards  经验奖励列表：每条 {pack=瓶, item=物品, groups=满级组数}；按该瓶等级线性发，
--            个数 = floor(堆叠 × groups × 等级 / 满级(10000))【向下取整，满 N 级才出第 1 个】。可 0~多条。
--            pack 选取原则：按该物品在科技树里的解锁层级配瓶（原始/触发物按其所属星球或领域代表瓶）。
--   unlock   解锁条件(可选)：每条 {pack=瓶, level=级}，需全满足；无则人人可选。
--   {}       空表 = 占位，在职业窗口里作【换行/分组】分隔（无 key，选不到）。
--
-- 【容量约束】每个职业「满级资源含量」（starter 固定组 + 各 rewards 满级 groups 之和）控制在 50 组以内。
local passives = require('scripts.passives')

local M = {}

M.DEFAULT = 'civilian'
M.MAX_LEVEL = 10000   -- 满级基准（与 respawn_gifts.MAX_LEVEL / gui CLASS_MAX_LEVEL 一致）

-- 默认职业表（顺序即面板显示顺序），分组：生产 / 物流 / 战斗 / 装备 / 农牧 / 科学星球 / 太空 / 终极，空职业 {} 分隔。
local DEFAULT_CLASSES = {
    -- ── 生产组（基础材料/机器/流体/能源；多练【红瓶 automation】，流体油气另练绿/蓝瓶）──
    {key = 'civilian', name = '平民', starter = {
        {item = 'burner-mining-drill', count = 1},
        {item = 'transport-belt'},
        {item = 'coal', groups = 3}, {item = 'iron-plate', groups = 3},
        {item = 'copper-plate', groups = 2}, {item = 'stone', groups = 2}}, rewards = {
        {pack = 'automation-science-pack', item = 'iron-ore',   groups = 10},
        {pack = 'automation-science-pack', item = 'copper-ore', groups = 8},
        {pack = 'automation-science-pack', item = 'coal',       groups = 5},
        {pack = 'automation-science-pack', item = 'stone',      groups = 5}}},
    {key = 'smelter', name = '炉工', starter = {
        {item = 'stone-furnace', count = 50},
        {item = 'coal', groups = 5}, {item = 'iron-ore', groups = 3}, {item = 'copper-ore', groups = 2}}, rewards = {
        {pack = 'automation-science-pack', item = 'coal',       groups = 1},
        {pack = 'automation-science-pack', item = 'iron-ore',   groups = 10},
        {pack = 'automation-science-pack', item = 'copper-ore', groups = 5},
        {pack = 'automation-science-pack', item = 'stone',      groups = 2}}},
    {key = 'miner', name = '矿工', starter = {
        {item = 'electric-mining-drill', count = 50},
        {item = 'stone', groups = 3}, {item = 'iron-plate', groups = 3}, {item = 'coal', groups = 3}}, rewards = {
        {pack = 'automation-science-pack',  item = 'electric-mining-drill', groups = 10},
        {pack = 'metallurgic-science-pack', item = 'big-mining-drill',      groups = 10},
        {pack = 'automation-science-pack',  item = 'iron-ore',   groups = 10},
        {pack = 'automation-science-pack',  item = 'copper-ore', groups = 8}}},
    {key = 'steelworker', name = '炼钢工', starter = {
        {item = 'steel-furnace', count = 50},
        {item = 'coal', groups = 5}, {item = 'iron-ore', groups = 5}}, rewards = {
        {pack = 'automation-science-pack', item = 'coal',        groups = 1},
        {pack = 'automation-science-pack', item = 'iron-plate',  groups = 15},
        {pack = 'automation-science-pack', item = 'steel-plate', groups = 3},
        {pack = 'automation-science-pack', item = 'copper-plate', groups = 10}}},
    {key = 'artisan', name = '螺丝装配工', starter = {
        {item = 'assembling-machine-1', count = 50},
        {item = 'iron-plate', groups = 5}, {item = 'iron-gear-wheel', groups = 3}}, rewards = {
        {pack = 'automation-science-pack', item = 'assembling-machine-1', groups = 1},
        {pack = 'automation-science-pack', item = 'iron-plate',      groups = 12},
        {pack = 'automation-science-pack', item = 'iron-gear-wheel', groups = 6},
        {pack = 'automation-science-pack', item = 'copper-plate',    groups = 5}}},
    {key = 'circuiter', name = '电路装配工', starter = {
        {item = 'assembling-machine-1', count = 50},
        {item = 'iron-plate', groups = 4}, {item = 'copper-plate', groups = 4}, {item = 'copper-cable', groups = 3}}, rewards = {
        {pack = 'automation-science-pack', item = 'assembling-machine-1', groups = 1},
        {pack = 'automation-science-pack', item = 'copper-cable',       groups = 8},
        {pack = 'automation-science-pack', item = 'electronic-circuit', groups = 4},
        {pack = 'automation-science-pack', item = 'iron-plate',         groups = 2}}},
    {key = 'electrician', name = '烧煤工', starter = {
        {item = 'coal', groups = 5},
        {item = 'small-electric-pole', groups = 1}, {item = 'iron-plate', groups = 2}}, rewards = {
        {pack = 'production-science-pack', item = 'small-electric-pole', groups = 5},
        {pack = 'automation-science-pack', item = 'boiler',             groups = 10},
        {pack = 'production-science-pack', item = 'steam-engine',       groups = 10}}},
    {key = 'greentech', name = '环保人士', starter = {
        {item = 'medium-electric-pole', count = 50},
        {item = 'solar-panel', count = 25}, {item = 'iron-plate', groups = 2}}, rewards = {
        {pack = 'automation-science-pack', item = 'medium-electric-pole', groups = 2},
        {pack = 'logistic-science-pack',   item = 'solar-panel',          groups = 10},
        {pack = 'chemical-science-pack',   item = 'efficiency-module',     groups = 2},
        {pack = 'production-science-pack', item = 'accumulator',          groups = 5}}},
    {key = 'chemist', name = '化学家', starter = {
        {item = 'chemical-plant', count = 50},
        {item = 'coal', groups = 3}, {item = 'iron-plate', groups = 2}}, rewards = {
        {pack = 'chemical-science-pack', item = 'plastic-bar', groups = 8},
        {pack = 'chemical-science-pack', item = 'sulfur',      groups = 8},
        {pack = 'chemical-science-pack', item = 'battery',     groups = 8}}},
    {key = 'oilman', name = '石油工人', starter = {
        {item = 'pumpjack', count = 10}, {item = 'oil-refinery', count = 5}, {item = 'pipe', groups = 3}}, rewards = {
        {pack = 'automation-science-pack', item = 'pipe',         groups = 10},   -- 早期红瓶
        {pack = 'logistic-science-pack',   item = 'pumpjack',     groups = 5},    -- 油气采集(绿)
        {pack = 'chemical-science-pack',   item = 'oil-refinery', groups = 5},    -- 炼油(蓝)
        {pack = 'logistic-science-pack',   item = 'storage-tank', groups = 3}}},
    {key = 'plumber', name = '管道工', starter = {
        {item = 'pipe', groups = 5}, {item = 'pipe-to-ground', count = 50}, {item = 'pump', count = 20}}, rewards = {
        {pack = 'automation-science-pack', item = 'pipe',           groups = 10},
        {pack = 'automation-science-pack', item = 'pipe-to-ground', groups = 8},
        {pack = 'logistic-science-pack',   item = 'pump',           groups = 5},
        {pack = 'logistic-science-pack',   item = 'storage-tank',   groups = 3},
        {pack = 'automation-science-pack', item = 'offshore-pump',  groups = 2}}},
    {key = 'nuclearman', name = '核电工人', starter = {
        {item = 'nuclear-reactor', count = 1}, {item = 'heat-pipe', groups = 1},
        {item = 'heat-exchanger', count = 10}, {item = 'steam-turbine', count = 20}}, rewards = {
        {pack = 'chemical-science-pack', item = 'nuclear-reactor',   groups = 2},  -- 核能链(蓝)
        {pack = 'chemical-science-pack', item = 'centrifuge',        groups = 3},
        {pack = 'chemical-science-pack', item = 'heat-exchanger',    groups = 3},
        {pack = 'chemical-science-pack', item = 'steam-turbine',     groups = 3},
        {pack = 'chemical-science-pack', item = 'uranium-fuel-cell', groups = 5},
        {pack = 'chemical-science-pack', item = 'uranium-ore',       groups = 10}}},   -- 原矿无瓶，按核能领域蓝瓶
    {key = 'recyclerman', name = '回收工人', starter = {{item = 'recycler', count = 1}}, rewards = {
        {pack = 'production-science-pack', item = 'recycler', groups = 5},   -- 回收(紫，quality 模组 recycling 科技)
        {pack = 'production-science-pack', item = 'scrap',    groups = 15}}},  -- 废料无瓶，按回收领域紫瓶

    {},   -- 分组换行：生产 ↔ 物流

    -- ── 物流组（练【绿瓶 logistic】出机器人/传送带/箱子）──
    {key = 'roboticist', name = '机械师', starter = {
        {item = 'roboport', count = 10},
        {item = 'construction-robot', count = 50}, {item = 'storage-chest', groups = 1}, {item = 'iron-plate', groups = 2}}, rewards = {
        {pack = 'logistic-science-pack', item = 'construction-robot',     groups = 10},
        {pack = 'logistic-science-pack', item = 'logistic-robot',         groups = 10},
        {pack = 'logistic-science-pack', item = 'storage-chest',          groups = 2},
        {pack = 'logistic-science-pack', item = 'passive-provider-chest', groups = 2},
        {pack = 'logistic-science-pack', item = 'active-provider-chest',  groups = 2},
        {pack = 'logistic-science-pack', item = 'requester-chest',        groups = 2},
        {pack = 'logistic-science-pack', item = 'buffer-chest',           groups = 2}}},
    {key = 'belter', name = '输送工', starter = {   -- 低级款：黄传送带 + 黄机械臂（非红蓝）
        {item = 'transport-belt'},
        {item = 'inserter', groups = 1}, {item = 'underground-belt', count = 20}, {item = 'splitter', count = 10}}, rewards = {
        {pack = 'logistic-science-pack',   item = 'transport-belt',   groups = 10},  -- 黄带（起始物，按物流绿瓶）
        {pack = 'automation-science-pack', item = 'inserter',         groups = 10},  -- 黄爪（红）
        {pack = 'automation-science-pack', item = 'underground-belt', groups = 5},
        {pack = 'automation-science-pack', item = 'splitter',         groups = 5}}},
    {key = 'warehouser', name = '仓库管理员', starter = {
        {item = 'wooden-chest', groups = 2}, {item = 'iron-chest', groups = 2},
        {item = 'steel-chest', groups = 2}, {item = 'storage-chest', groups = 1}}, rewards = {
        {pack = 'logistic-science-pack', item = 'steel-chest',            groups = 10},
        {pack = 'logistic-science-pack', item = 'storage-chest',          groups = 8},
        {pack = 'logistic-science-pack', item = 'passive-provider-chest', groups = 5},
        {pack = 'logistic-science-pack', item = 'requester-chest',        groups = 5},
        {pack = 'logistic-science-pack', item = 'buffer-chest',           groups = 5}}},

    {},   -- 分组换行：物流 ↔ 战斗

    -- ── 战斗组（练【灰瓶 military】出弹药/手雷；坦克手/火箭筒兵另练【蓝瓶 chemical】出爆破火箭弹）──
    {key = 'guard', name = '守卫', starter = {
        {item = 'gun-turret', count = 1}, {item = 'firearm-magazine', groups = 1}}, rewards = {
        {pack = 'military-science-pack', item = 'gun-turret',               groups = 5},
        {pack = 'military-science-pack', item = 'firearm-magazine',         groups = 10},
        {pack = 'military-science-pack', item = 'piercing-rounds-magazine', groups = 10}}},
    {key = 'gunner', name = '机枪手', starter = {
        {item = 'submachine-gun', count = 1}, {item = 'firearm-magazine', groups = 1}}, rewards = {
        {pack = 'military-science-pack', item = 'firearm-magazine',         groups = 10},
        {pack = 'military-science-pack', item = 'piercing-rounds-magazine', groups = 10}}},
    {key = 'tanker', name = '坦克手', starter = {
        {item = 'tank', count = 1}, {item = 'rocket-fuel'}, {item = 'cannon-shell', groups = 1}}, rewards = {
        {pack = 'military-science-pack', item = 'cannon-shell',     groups = 10},
        {pack = 'chemical-science-pack', item = 'explosive-rocket', groups = 10}}},
    {key = 'rocketeer', name = '火箭筒兵', starter = {
        {item = 'rocket-launcher', count = 1}, {item = 'rocket', groups = 1}}, rewards = {
        {pack = 'military-science-pack', item = 'rocket',           groups = 10},
        {pack = 'chemical-science-pack', item = 'explosive-rocket', groups = 10}}},
    {key = 'artillerist', name = '炮兵', starter = {
        {item = 'artillery-turret', count = 1}, {item = 'artillery-shell', count = 5}}, rewards = {
        {pack = 'military-science-pack', item = 'artillery-shell',  groups = 10},
        {pack = 'military-science-pack', item = 'artillery-turret', groups = 3}}},
    {key = 'bomber', name = '投弹手', starter = {{item = 'grenade', groups = 2}}, rewards = {
        {pack = 'logistic-science-pack', item = 'grenade',         groups = 10},   -- 手雷(绿，military-2)
        {pack = 'utility-science-pack',  item = 'cluster-grenade', groups = 10}}},  -- 集束手雷(黄，military-4)

    {},   -- 分组换行：战斗 ↔ 装备

    -- ── 装备组（护甲网格组件；按各组件解锁科技配瓶）──
    {key = 'toolman', name = '工具人', starter = {{item = 'toolbelt-equipment', count = 1}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'toolbelt-equipment', groups = 5}}},   -- 工具腰带(草，SA 重做)
    {key = 'outfitter', name = '服装设计师', starter = {
        {item = 'solar-panel-equipment', count = 2}, {item = 'battery-equipment', count = 2}, {item = 'night-vision-equipment', count = 1}}, rewards = {
        {pack = 'logistic-science-pack', item = 'solar-panel-equipment',      groups = 3},
        {pack = 'logistic-science-pack', item = 'battery-equipment',          groups = 3},
        {pack = 'logistic-science-pack', item = 'night-vision-equipment',     groups = 2},
        {pack = 'chemical-science-pack', item = 'personal-roboport-equipment', groups = 3},
        {pack = 'chemical-science-pack', item = 'exoskeleton-equipment',      groups = 3},
        {pack = 'military-science-pack', item = 'energy-shield-equipment',    groups = 3}}},

    {},   -- 分组换行：装备 ↔ 农牧

    -- ── 农牧组（鱼/虫卵/种子/腐败物，Gleba 生态，主练【草瓶 agricultural】）──
    {key = 'bugkeeper', name = '养虫人', starter = {{item = 'pentapod-egg', count = 1}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'raw-fish', groups = 10}}},   -- 等级越高送越多鱼
    {key = 'fisher', name = '渔夫', starter = {
        {item = 'raw-fish', groups = 2}, {item = 'spoilage', groups = 2}, {item = 'inserter', groups = 1}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'raw-fish',  groups = 10},
        {pack = 'agricultural-science-pack', item = 'spoilage',  groups = 8},
        {pack = 'automation-science-pack',   item = 'inserter',  groups = 5}}},
    {key = 'farmer', name = '农夫', starter = {
        {item = 'agricultural-tower', count = 5},
        {item = 'yumako-seed', groups = 2}, {item = 'jellynut-seed', groups = 2}, {item = 'tree-seed', groups = 2}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'yumako-seed',       groups = 8},
        {pack = 'agricultural-science-pack', item = 'jellynut-seed',     groups = 8},
        {pack = 'agricultural-science-pack', item = 'tree-seed',         groups = 5},
        {pack = 'agricultural-science-pack', item = 'agricultural-tower', groups = 5}}},

    {},   -- 分组换行：农牧 ↔ 科学/星球

    -- ── 科学/星球组（各星球招牌机器/材料；需对应瓶 100 级解锁，体现“该领域老手”）──
    {key = 'astronaut', name = '宇航专家', starter = {
        {item = 'rocket-silo', count = 1}, {item = 'iron-plate', groups = 3}, {item = 'copper-plate', groups = 3}},
        unlock = {{pack = 'space-science-pack', level = 100}}, rewards = {  -- 白
        {pack = 'space-science-pack', item = 'space-platform-starter-pack', groups = 10}}},
    {key = 'metallurgist', name = '冶金学家', starter = {
        {item = 'foundry', count = 1}, {item = 'iron-ore', groups = 3}, {item = 'stone', groups = 3}, {item = 'coal', groups = 3}},
        unlock = {{pack = 'metallurgic-science-pack', level = 100}}, rewards = {  -- 橙(火山)
        {pack = 'metallurgic-science-pack', item = 'tungsten-plate', groups = 10},
        {pack = 'metallurgic-science-pack', item = 'tungsten-ore',   groups = 10}}},
    {key = 'electromancer', name = '电磁专家', starter = {
        {item = 'electromagnetic-plant', count = 1}, {item = 'iron-plate', groups = 3}, {item = 'copper-plate', groups = 3}},
        unlock = {{pack = 'electromagnetic-science-pack', level = 100}}, rewards = {  -- 粉(电浆星)
        {pack = 'electromagnetic-science-pack', item = 'accumulator',    groups = 10},
        {pack = 'electromagnetic-science-pack', item = 'supercapacitor', groups = 10},
        {pack = 'electromagnetic-science-pack', item = 'holmium-plate',  groups = 8}}},
    {key = 'biologist', name = '生物专家', starter = {
        {item = 'agricultural-tower', count = 1}, {item = 'iron-plate', groups = 3}},
        unlock = {{pack = 'agricultural-science-pack', level = 100}}, rewards = {  -- 草(Gleba)
        {pack = 'agricultural-science-pack', item = 'biochamber', groups = 10},
        {pack = 'agricultural-science-pack', item = 'carbon',     groups = 8}}},
    {key = 'physicist', name = '物理学家', starter = {
        {item = 'cryogenic-plant', count = 1}, {item = 'iron-plate', groups = 3}, {item = 'solid-fuel', groups = 2}},
        unlock = {{pack = 'cryogenic-science-pack', level = 100}}, rewards = {  -- 靛(Aquilo)
        {pack = 'cryogenic-science-pack', item = 'fusion-reactor', groups = 10},
        {pack = 'cryogenic-science-pack', item = 'lithium-plate',  groups = 8}}},
    {key = 'astronomer', name = '天文学家', starter = {
        {item = 'lab', count = 1}, {item = 'iron-plate', groups = 3}},
        unlock = {{pack = 'promethium-science-pack', level = 100}}, rewards = {  -- 黑(promethium)
        {pack = 'promethium-science-pack', item = 'biolab', groups = 10}}},

    {},   -- 分组换行：科学/星球 ↔ 太空

    -- ── 太空组（星际平台组件；触发式科技无瓶的按太空领域白瓶）──
    {key = 'pilot', name = '飞船驾驶员', starter = {
        {item = 'asteroid-collector', count = 2}, {item = 'thruster', count = 2},
        {item = 'cargo-bay', count = 2}, {item = 'crusher', count = 2}}, rewards = {
        {pack = 'space-science-pack',   item = 'thruster',                  groups = 5},
        {pack = 'utility-science-pack', item = 'space-platform-foundation', groups = 10},
        {pack = 'space-science-pack',   item = 'asteroid-collector',        groups = 5},
        {pack = 'space-science-pack',   item = 'crusher',                   groups = 5}}},

    {},   -- 分组换行：太空 ↔ 终极

    -- ── 终极职业（极高解锁门槛）──
    {key = 'transformer', name = '变形金刚', starter = {{item = 'mech-armor', count = 1}},
        unlock = {{pack = 'electromagnetic-science-pack', level = 1000}}},   -- 需粉瓶(电磁) 1000 级解锁
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
