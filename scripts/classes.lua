-- 职业系统：每个职业对应一个领域，决定开局发什么物品。
-- 玩家随时可在【职业】按钮窗口里切换（同时只能一种，存 storage.player_class[名]，带短冷却）。
-- 进服默认职业 = 平民（未选择时按平民对待，见 M.DEFAULT / selected_key 兜底）。
--
-- 每个职业两类物品（见 respawn_gifts.gift_list 发放）：
--   starter 无条件初始物品：每轮开局直接发 1 组（= 堆叠数）。
--   reward  经验奖励物品：按该职业【专精瓶】等级，每 100 级发 1 组（floor(等级/100) 组）。
-- 平民无专精瓶、无 reward；天文大师只有 starter、无 reward。
local M = {}

M.DEFAULT = 'civilian'

-- 职业表（顺序即面板显示顺序）：
--   key     内部稳定标识（存档/路由用，不随语言变；显示名见 locale class-name-<key>）
--   packs   专精的科技瓶（决定 reward 按哪个瓶的经验发；平民为空）
--   starter 无条件初始物品（开局发 1 组）
--   reward  经验奖励物品（每 100 级发 1 组；nil = 无）
M.list = {
    {key = 'civilian',     packs = {},                                starter = 'burner-mining-drill'},
    {key = 'miner',        packs = {'automation-science-pack'},       starter = 'electric-mining-drill', reward = 'big-mining-drill'},
    {key = 'artisan',      packs = {'logistic-science-pack'},         starter = 'assembling-machine-2',  reward = 'assembling-machine-3'},
    {key = 'smelter',      packs = {'chemical-science-pack'},         starter = 'medium-electric-pole',  reward = 'steam-turbine'},
    {key = 'soldier',      packs = {'military-science-pack'},         starter = 'tank',                  reward = 'power-armor-mk2'},
    {key = 'worker',       packs = {'production-science-pack'},       starter = 'electric-furnace',      reward = 'beacon'},
    {key = 'merchant',     packs = {'utility-science-pack'},          starter = 'passive-provider-chest', reward = 'roboport'},
    {key = 'crew',         packs = {'space-science-pack'},            starter = 'rocket-silo',           reward = 'space-platform-starter-pack'},
    {key = 'metallurgist', packs = {'metallurgic-science-pack'},      starter = 'foundry',               reward = 'speed-module-3'},
    {key = 'electrician',  packs = {'electromagnetic-science-pack'},  starter = 'electromagnetic-plant', reward = 'quality-module-3'},
    {key = 'biologist',    packs = {'agricultural-science-pack'},     starter = 'agricultural-tower',    reward = 'efficiency-module-3'},
    {key = 'physicist',    packs = {'cryogenic-science-pack'},        starter = 'cryogenic-plant',       reward = 'productivity-module-3'},
    {key = 'astronomer',   packs = {'promethium-science-pack'},       starter = 'lab',                   reward = 'biolab'},
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
