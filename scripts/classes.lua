-- 职业系统：每个职业是一个【专精领域】，决定开局发什么物品。
-- 玩家随时可在【职业】按钮窗口里切换（同时只能一种，存 storage.player_class[名]，带短冷却）。
-- 进服默认职业 = 平民（未选择时按平民对待，见 M.DEFAULT / selected_key 兜底）。
--
-- 【职业表存 storage.classes，可热改】：DEFAULT_CLASSES 只是初始默认，M.ensure() 把它深拷贝进 storage.classes。
--   之后管理员可 /c 动态改，即时生效（职业数少、不缓存，每次遍历查），例：
--     /c storage.classes[2].rewards[1].groups = 5     改某职业奖励的满级组数
--     /c table.remove(storage.classes, 3)             删第 3 个职业
--     /c storage.classes = nil                        清空 → 下次加载(on_configuration_changed)恢复默认
--
-- 每个职业的字段：
--   name     职业显示名（中文字符串，直接显示、绕过 locale）；缺省则查 locale class-name-<key>。
--   starter  无条件初始物品列表：每条 {item=物品, groups=组数(默认1)}，每轮开局直接发、不看等级；可多种。
--   rewards  经验奖励物品列表：每条 {pack=瓶, item=物品, groups=满级组数}。
--            按该瓶等级线性发：个数 = floor(堆叠 × groups × 等级 / 满级(10000))【向下取整】。可 0~多条（多瓶职业）。
--   unlock   解锁条件列表（可选）：每条 {pack=瓶, level=级}，需【全部满足】才能选；无则人人可选。
local passives = require('scripts.passives')

local M = {}

M.DEFAULT = 'civilian'
M.MAX_LEVEL = 10000   -- 满级基准（与 respawn_gifts.MAX_LEVEL / gui CLASS_MAX_LEVEL 一致）

-- 默认职业表（顺序即面板显示顺序）：平民 + 12 瓶单瓶职业（每种科技瓶一个领域）+ 4 双瓶职业。
-- 单瓶满级送 10 组、双瓶各 5 组（满级合计 10 组）。带 unlock 的需练到对应瓶等级才能选。
local DEFAULT_CLASSES = {
    {key = 'civilian',     name = '平民',       starter = {
        {item = 'iron-plate', groups = 10},
        {item = 'copper-plate', groups = 10},
        {item = 'burner-mining-drill'},
        {item = 'wooden-chest'},
        {item = 'transport-belt'}
    }},

    -- ── 12 瓶单瓶职业（每种科技瓶一个领域）──
    {key = 'miner',        name = '矿工',       starter = {{item = 'electric-mining-drill'}}, rewards = {
        {pack = 'automation-science-pack',      item = 'big-mining-drill',     groups = 10}}},
    {key = 'artisan',      name = '匠人',       starter = {{item = 'assembling-machine-2'}}, rewards = {
        {pack = 'logistic-science-pack',        item = 'assembling-machine-3', groups = 10}}},
    {key = 'smelter',      name = '炉工',       starter = {{item = 'electric-furnace'}}, rewards = {
        {pack = 'chemical-science-pack',        item = 'steam-turbine',        groups = 10}}},
    {key = 'soldier',      name = '军人',       starter = {{item = 'tank'}}, rewards = {
        {pack = 'military-science-pack',        item = 'power-armor-mk2',      groups = 10}}},
    {key = 'worker',       name = '工人',       starter = {{item = 'medium-electric-pole'}}, rewards = {
        {pack = 'production-science-pack',      item = 'beacon',               groups = 10}}},
    {key = 'merchant',     name = '商人',       starter = {{item = 'passive-provider-chest'}}, rewards = {
        {pack = 'utility-science-pack',         item = 'roboport',             groups = 10}}},
    {key = 'crew',         name = '船员',       starter = {{item = 'rocket-silo'}},
        unlock = {{pack = 'space-science-pack', level = 5}}, rewards = {
        {pack = 'space-science-pack',           item = 'space-platform-starter-pack', groups = 10}}},
    {key = 'metallurgist', name = '冶金大师',   starter = {{item = 'foundry'}},
        unlock = {{pack = 'metallurgic-science-pack', level = 5}}, rewards = {
        {pack = 'metallurgic-science-pack',     item = 'speed-module-3',       groups = 10}}},
    {key = 'electrician',  name = '电气大师',   starter = {{item = 'electromagnetic-plant'}},
        unlock = {{pack = 'electromagnetic-science-pack', level = 5}}, rewards = {
        {pack = 'electromagnetic-science-pack', item = 'quality-module-3',     groups = 10}}},
    {key = 'biologist',    name = '生物大师',   starter = {{item = 'agricultural-tower'}},
        unlock = {{pack = 'agricultural-science-pack', level = 5}}, rewards = {
        {pack = 'agricultural-science-pack',    item = 'efficiency-module-3',  groups = 10}}},
    {key = 'physicist',    name = '物理大师',   starter = {{item = 'cryogenic-plant'}},
        unlock = {{pack = 'cryogenic-science-pack', level = 5}}, rewards = {
        {pack = 'cryogenic-science-pack',       item = 'productivity-module-3', groups = 10}}},
    {key = 'astronomer',   name = '天文大师',   starter = {{item = 'lab'}},
        unlock = {{pack = 'promethium-science-pack', level = 10}}, rewards = {
        {pack = 'promethium-science-pack',      item = 'biolab',               groups = 10}}},

    -- ── 4 双瓶职业（受两种瓶加成；解锁需两瓶都达标，各按对应瓶发一种奖励，各 5 组）──
    {key = 'quartermaster', name = '后勤官',    starter = {{item = 'active-provider-chest'}},
        unlock = {{pack = 'logistic-science-pack', level = 8}, {pack = 'utility-science-pack', level = 8}}, rewards = {
        {pack = 'logistic-science-pack', item = 'logistic-robot',     groups = 5},
        {pack = 'utility-science-pack',  item = 'construction-robot', groups = 5}}},
    {key = 'warsmith',      name = '军工专家',  starter = {{item = 'laser-turret'}},
        unlock = {{pack = 'military-science-pack', level = 8}, {pack = 'production-science-pack', level = 8}}, rewards = {
        {pack = 'military-science-pack',   item = 'artillery-turret', groups = 5},
        {pack = 'production-science-pack', item = 'spidertron',       groups = 5}}},
    {key = 'powermaster',   name = '能源大师',  starter = {{item = 'substation'}},
        unlock = {{pack = 'chemical-science-pack', level = 8}, {pack = 'electromagnetic-science-pack', level = 8}}, rewards = {
        {pack = 'chemical-science-pack',        item = 'nuclear-reactor', groups = 5},
        {pack = 'electromagnetic-science-pack', item = 'accumulator',     groups = 5}}},
    {key = 'pioneer',       name = '拓荒者',    starter = {{item = 'heating-tower'}},
        unlock = {{pack = 'agricultural-science-pack', level = 8}, {pack = 'cryogenic-science-pack', level = 8}}, rewards = {
        {pack = 'agricultural-science-pack', item = 'biochamber',     groups = 5},
        {pack = 'cryogenic-science-pack',    item = 'fusion-reactor', groups = 5}}},

    -- ── 主题专精职业（与上面按瓶领域的职业并存，玩法侧重不同；key 加后缀避开 miner/soldier 重名）──
    {key = 'mining_expert',  name = '采矿专家',   starter = {{item = 'burner-mining-drill'}}, rewards = {
        {pack = 'automation-science-pack',  item = 'electric-mining-drill', groups = 2},
        {pack = 'metallurgic-science-pack', item = 'big-mining-drill',      groups = 1}}},
    {key = 'automator',      name = '自动化专家', starter = {{item = 'assembling-machine-1'}}, rewards = {
        {pack = 'automation-science-pack', item = 'assembling-machine-2', groups = 2},
        {pack = 'automation-science-pack', item = 'fast-transport-belt',       groups = 1},
        {pack = 'automation-science-pack', item = 'fast-inserter',        groups = 1},
        {pack = 'automation-science-pack', item = 'steel-furnace',        groups = 2}}},
    {key = 'roboticist',     name = '机器人专家', starter = {{item = 'passive-provider-chest'}}, rewards = {
        {pack = 'logistic-science-pack', item = 'construction-robot',    groups = 2},
        {pack = 'logistic-science-pack', item = 'logistic-robot',        groups = 2},
        {pack = 'logistic-science-pack', item = 'roboport',              groups = 1},
        {pack = 'logistic-science-pack', item = 'storage-chest',         groups = 1},
        {pack = 'utility-science-pack',  item = 'active-provider-chest', groups = 1},
        {pack = 'utility-science-pack',  item = 'requester-chest',       groups = 1},
        {pack = 'utility-science-pack',  item = 'buffer-chest',          groups = 1}}},
    {key = 'soldier_expert', name = '军事专家',   starter = {{item = 'gun-turret'}}, rewards = {
        {pack = 'military-science-pack', item = 'laser-turret',    groups = 2},
        {pack = 'military-science-pack', item = 'tank',            groups = 1},
        {pack = 'military-science-pack', item = 'rocket-launcher', groups = 1},
        {pack = 'military-science-pack', item = 'gun-turret',      groups = 2}}},
    {key = 'xeno',           name = '外星专家',   starter = {{item = 'foundry'}}, rewards = {
        {pack = 'metallurgic-science-pack',     item = 'foundry',               groups = 1},
        {pack = 'electromagnetic-science-pack', item = 'electromagnetic-plant', groups = 1},
        {pack = 'agricultural-science-pack',    item = 'agricultural-tower',    groups = 1},
        {pack = 'cryogenic-science-pack',       item = 'cryogenic-plant',       groups = 1}}},
    {key = 'scholar',        name = '博学专家',   starter = {{item = 'assembling-machine-2'}}, rewards = {
        {pack = 'chemical-science-pack',        item = 'chemical-plant',              groups = 1},
        {pack = 'production-science-pack',      item = 'assembling-machine-3',        groups = 1},
        {pack = 'utility-science-pack',         item = 'roboport',                    groups = 1},
        {pack = 'space-science-pack',           item = 'space-platform-starter-pack', groups = 1},
        {pack = 'metallurgic-science-pack',     item = 'foundry',                     groups = 1},
        {pack = 'electromagnetic-science-pack', item = 'electromagnetic-plant',       groups = 1},
        {pack = 'agricultural-science-pack',    item = 'biochamber',                  groups = 1},
        {pack = 'cryogenic-science-pack',       item = 'cryogenic-plant',             groups = 1},
        {pack = 'promethium-science-pack',      item = 'biolab',                      groups = 1},
        {pack = 'military-science-pack',        item = 'artillery-turret',            groups = 1}}},
}

-- 纯数据深拷贝（DEFAULT_CLASSES 无函数/元表，递归拷贝即可）。
local function deepcopy(t)
    if type(t) ~= 'table' then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepcopy(v) end
    return c
end

-- 把默认职业表深拷贝进 storage.classes（仅当缺失）。on_init / on_configuration_changed 调用。
-- 之后管理员可 /c 改 storage.classes 动态调整职业；想恢复默认就 /c storage.classes=nil 再触发一次本函数。
function M.ensure()
    storage.classes = storage.classes or deepcopy(DEFAULT_CLASSES)
end

-- 当前生效的职业表（读 storage；未初始化则退回默认常量兜底）。各处遍历用它。
function M.all()
    return storage.classes or DEFAULT_CLASSES
end

-- 按 key 找职业定义（遍历当前表；职业数少、不缓存，确保 /c 改 storage.classes 后即时生效）。
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

-- 玩家某瓶当前等级（= floor√经验；与 respawn_gifts.pack_level 同公式，解锁等级远小于满级故不需封顶）。
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

-- 设定玩家选择的职业（校验 key 合法 + 已解锁 + 写存储；冷却/广播由 commands 处理）。
-- 返回 true=成功；'locked'=未解锁；nil=非法 key。
function M.set(player, key)
    local def = M.def_for_key(key)
    if not (player and def) then return nil end
    if not M.unlocked(player, def) then return 'locked' end
    storage.player_class = storage.player_class or {}
    storage.player_class[player.name] = key
    return true
end

return M
