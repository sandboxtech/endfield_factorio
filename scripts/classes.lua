-- 职业系统：每个职业专精 1~2 种科技瓶，对应一个现实领域。
-- 玩家随时可在【职业】按钮窗口里切换职业（独立 HUD 按钮），同时只能是一种职业。
--   · 选择存 storage.player_class[名]，切换带短冷却防刷（冷却逻辑在 commands.set_class）。
--
-- 设计意图：选了职业 → 开局多发一些该领域的对应物品（专精瓶相关建筑）。
-- 【效果暂未实现】：当前只落地"选择"骨架，is_pack_boosted 已备好，
-- 将来在 respawn_gifts 接入即可。先不动开局赠品逻辑。
local M = {}

-- 12 职业，与 constants.science_packs 一一对应（顺序即面板显示顺序）。
--   key    内部稳定标识（存档/路由用，不随语言变）
--   packs  专精的科技瓶（1~2 种）→ 将来的赠品加成作用在这些瓶
M.list = {
    {key = 'mining',        packs = {'automation-science-pack'}},
    {key = 'logistics',     packs = {'logistic-science-pack'}},
    {key = 'chemistry',     packs = {'chemical-science-pack'}},
    {key = 'manufacturing', packs = {'production-science-pack'}},
    {key = 'engineering',   packs = {'utility-science-pack'}},
    {key = 'aerospace',     packs = {'space-science-pack'}},
    {key = 'metallurgy',    packs = {'metallurgic-science-pack'}},
    {key = 'electronics',   packs = {'electromagnetic-science-pack'}},
    {key = 'biology',       packs = {'agricultural-science-pack'}},
    {key = 'physics',       packs = {'cryogenic-science-pack'}},
    {key = 'astronomy',     packs = {'promethium-science-pack'}},
    {key = 'military',      packs = {'military-science-pack'}},
}

-- key → 定义；以及某瓶 → 哪个职业专精它（供将来 respawn_gifts 反查）。
M.by_key = {}
local pack_to_class = {}
for _, def in ipairs(M.list) do
    M.by_key[def.key] = def
    for _, pack in ipairs(def.packs) do pack_to_class[pack] = def.key end
end

-- 玩家当前选择的职业 key（没选则 nil）。
function M.selected_key(player)
    return player and (storage.player_class or {})[player.name]
end

-- 玩家当前职业是否专精了某瓶（供将来发开局物品用）。
function M.is_pack_boosted(player, pack)
    local key = M.selected_key(player)
    return key ~= nil and pack_to_class[pack] == key
end

-- 设定玩家选择的职业（仅校验 key 合法 + 写存储；冷却/广播由 commands 处理）。
-- key 传 nil 或非法则不改、返回 false。
function M.set(player, key)
    if not (player and key and M.by_key[key]) then return false end
    storage.player_class = storage.player_class or {}
    storage.player_class[player.name] = key
    return true
end

return M
