-- 职业系统：每个职业对应一个领域，决定开局发什么物品。
-- 玩家随时可在【职业】按钮窗口里切换（同时只能一种，存 storage.player_class[名]，带短冷却）。
-- 进服默认职业 = 平民（未选择时按平民对待，见 M.DEFAULT / selected_key 兜底）。
--
-- 每个职业的字段：
--   starter  无条件初始物品：每轮开局直接发 1 组（= 堆叠数）。
--   rewards  经验奖励物品列表：每条 {pack=瓶, item=物品, groups=满级组数}。
--            按该瓶等级线性发：个数 = ceil(堆叠 × groups × 等级 / 满级(10000))。可 0~多条（多瓶职业）。
--   unlock   解锁条件列表（可选）：每条 {pack=瓶, level=级}，需【全部满足】才能选此职业；无则人人可选。
local passives = require('scripts.passives')

local M = {}

M.DEFAULT = 'civilian'
M.MAX_LEVEL = 10000   -- 满级基准（与 respawn_gifts.MAX_LEVEL / gui CLASS_MAX_LEVEL 一致）

-- 职业表（顺序即面板显示顺序）。前段为单瓶/无瓶职业，末段为受多种瓶子加成的双瓶职业。
M.list = {
    {key = 'civilian',     starter = 'burner-mining-drill'},
    {key = 'miner',        starter = 'electric-mining-drill', rewards = {{pack = 'automation-science-pack',      item = 'big-mining-drill',  groups = 2}}},
    {key = 'artisan',      starter = 'assembling-machine-2',  rewards = {{pack = 'logistic-science-pack',        item = 'assembling-machine-3', groups = 4}}},
    {key = 'smelter',      starter = 'medium-electric-pole',  rewards = {{pack = 'chemical-science-pack',        item = 'steam-turbine',     groups = 4}}},
    {key = 'soldier',      starter = 'tank',                  rewards = {{pack = 'military-science-pack',        item = 'power-armor-mk2',   groups = 1}}},
    {key = 'worker',       starter = 'electric-furnace',      rewards = {{pack = 'production-science-pack',      item = 'beacon',            groups = 4}}},
    {key = 'merchant',     starter = 'passive-provider-chest', rewards = {{pack = 'utility-science-pack',        item = 'roboport',          groups = 2}}},
    {key = 'crew',         starter = 'rocket-silo',           unlock = {{pack = 'space-science-pack', level = 5}},
        rewards = {{pack = 'space-science-pack', item = 'space-platform-starter-pack', groups = 1}}},
    {key = 'metallurgist', starter = 'foundry',               unlock = {{pack = 'metallurgic-science-pack', level = 5}},
        rewards = {{pack = 'metallurgic-science-pack', item = 'speed-module-3', groups = 4}}},
    {key = 'electrician',  starter = 'electromagnetic-plant', unlock = {{pack = 'electromagnetic-science-pack', level = 5}},
        rewards = {{pack = 'electromagnetic-science-pack', item = 'quality-module-3', groups = 4}}},
    {key = 'biologist',    starter = 'agricultural-tower',    unlock = {{pack = 'agricultural-science-pack', level = 5}},
        rewards = {{pack = 'agricultural-science-pack', item = 'efficiency-module-3', groups = 4}}},
    {key = 'physicist',    starter = 'cryogenic-plant',       unlock = {{pack = 'cryogenic-science-pack', level = 5}},
        rewards = {{pack = 'cryogenic-science-pack', item = 'productivity-module-3', groups = 4}}},
    {key = 'astronomer',   starter = 'lab',                   unlock = {{pack = 'promethium-science-pack', level = 10}},
        rewards = {{pack = 'promethium-science-pack', item = 'biolab', groups = 2}}},
    -- 双瓶职业（受两种瓶子加成；解锁需【两个瓶都】达标，各按对应瓶等级发一种后者物品）：
    {key = 'quartermaster', starter = 'active-provider-chest',
        unlock = {{pack = 'logistic-science-pack', level = 8}, {pack = 'utility-science-pack', level = 8}},
        rewards = {
            {pack = 'logistic-science-pack', item = 'logistic-robot',     groups = 4},
            {pack = 'utility-science-pack',  item = 'construction-robot', groups = 4}}},
    {key = 'warsmith',      starter = 'laser-turret',
        unlock = {{pack = 'military-science-pack', level = 8}, {pack = 'production-science-pack', level = 8}},
        rewards = {
            {pack = 'military-science-pack',   item = 'artillery-turret', groups = 2},
            {pack = 'production-science-pack', item = 'spidertron',       groups = 1}}},
    {key = 'powermaster',   starter = 'substation',
        unlock = {{pack = 'chemical-science-pack', level = 8}, {pack = 'electromagnetic-science-pack', level = 8}},
        rewards = {
            {pack = 'chemical-science-pack',        item = 'nuclear-reactor', groups = 2},
            {pack = 'electromagnetic-science-pack', item = 'accumulator',     groups = 4}}},
    {key = 'pioneer',       starter = 'heating-tower',
        unlock = {{pack = 'agricultural-science-pack', level = 8}, {pack = 'cryogenic-science-pack', level = 8}},
        rewards = {
            {pack = 'agricultural-science-pack', item = 'biochamber',      groups = 2},
            {pack = 'cryogenic-science-pack',    item = 'fusion-reactor',  groups = 1}}},
}

-- key → 定义。
M.by_key = {}
for _, def in ipairs(M.list) do M.by_key[def.key] = def end

-- 玩家当前选择的职业 key（未选 → 默认平民）。
function M.selected_key(player)
    return player and ((storage.player_class or {})[player.name] or M.DEFAULT)
end

-- 玩家当前职业定义（一定返回一个，兜底平民）。
function M.def_of(player)
    return M.by_key[M.selected_key(player)] or M.by_key[M.DEFAULT]
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
    local def = key and M.by_key[key]
    if not (player and def) then return nil end
    if not M.unlocked(player, def) then return 'locked' end
    storage.player_class = storage.player_class or {}
    storage.player_class[player.name] = key
    return true
end

return M
