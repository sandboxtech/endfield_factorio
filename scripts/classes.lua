-- 职业系统：每个职业对应一个领域，决定开局发什么物品。
-- 玩家随时可在【职业】按钮窗口里切换（同时只能一种，存 storage.player_class[名]，带短冷却）。
-- 进服默认职业 = 平民（未选择时按平民对待，见 M.DEFAULT / selected_key 兜底）。
--
-- 每个职业的物品（见 respawn_gifts.gift_list 发放）：
--   starter  无条件初始物品：每轮开局直接发 1 组（= 堆叠数）。
--   rewards  经验奖励物品列表：每条 {pack=瓶, item=物品}，按该瓶等级发，个数 = ceil(等级×堆叠/100)
--            （即 100 级 1 组、按堆叠摊到每级）。可有 0~多条 → 支持【受多种瓶子加成】的多瓶职业。
local M = {}

M.DEFAULT = 'civilian'

-- 职业表（顺序即面板显示顺序）。前段为单瓶/无瓶职业，末段为受多种瓶子加成的双瓶职业。
M.list = {
    {key = 'civilian',     starter = 'burner-mining-drill'},
    {key = 'miner',        starter = 'electric-mining-drill', rewards = {{pack = 'automation-science-pack',      item = 'big-mining-drill'}}},
    {key = 'artisan',      starter = 'assembling-machine-2',  rewards = {{pack = 'logistic-science-pack',        item = 'assembling-machine-3'}}},
    {key = 'smelter',      starter = 'medium-electric-pole',  rewards = {{pack = 'chemical-science-pack',        item = 'steam-turbine'}}},
    {key = 'soldier',      starter = 'tank',                  rewards = {{pack = 'military-science-pack',        item = 'power-armor-mk2'}}},
    {key = 'worker',       starter = 'electric-furnace',      rewards = {{pack = 'production-science-pack',      item = 'beacon'}}},
    {key = 'merchant',     starter = 'passive-provider-chest', rewards = {{pack = 'utility-science-pack',        item = 'roboport'}}},
    {key = 'crew',         starter = 'rocket-silo',           rewards = {{pack = 'space-science-pack',           item = 'space-platform-starter-pack'}}},
    {key = 'metallurgist', starter = 'foundry',               rewards = {{pack = 'metallurgic-science-pack',     item = 'speed-module-3'}}},
    {key = 'electrician',  starter = 'electromagnetic-plant', rewards = {{pack = 'electromagnetic-science-pack', item = 'quality-module-3'}}},
    {key = 'biologist',    starter = 'agricultural-tower',    rewards = {{pack = 'agricultural-science-pack',    item = 'efficiency-module-3'}}},
    {key = 'physicist',    starter = 'cryogenic-plant',       rewards = {{pack = 'cryogenic-science-pack',       item = 'productivity-module-3'}}},
    {key = 'astronomer',   starter = 'lab',                   rewards = {{pack = 'promethium-science-pack',      item = 'biolab'}}},
    -- 双瓶职业（受两种瓶子加成，各按对应瓶等级发一种后者物品）：
    {key = 'quartermaster', starter = 'active-provider-chest', rewards = {
        {pack = 'logistic-science-pack', item = 'logistic-robot'},
        {pack = 'utility-science-pack',  item = 'construction-robot'}}},
    {key = 'warsmith',      starter = 'laser-turret',          rewards = {
        {pack = 'military-science-pack',   item = 'artillery-turret'},
        {pack = 'production-science-pack', item = 'spidertron'}}},
    {key = 'powermaster',   starter = 'substation',            rewards = {
        {pack = 'chemical-science-pack',        item = 'nuclear-reactor'},
        {pack = 'electromagnetic-science-pack', item = 'accumulator'}}},
    {key = 'pioneer',       starter = 'heating-tower',         rewards = {
        {pack = 'agricultural-science-pack', item = 'biochamber'},
        {pack = 'cryogenic-science-pack',    item = 'fusion-reactor'}}},
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

-- 设定玩家选择的职业（仅校验 key 合法 + 写存储；冷却/广播由 commands 处理）。
function M.set(player, key)
    if not (player and key and M.by_key[key]) then return false end
    storage.player_class = storage.player_class or {}
    storage.player_class[player.name] = key
    return true
end

return M
