-- 玩家在某个世界（storage.run）第一次复活时发放的初始物资。
-- 由 players.lua 在 on_player_respawned / on_player_created 中调用。
--
-- 设计：不再往背包塞成品建筑（会爆背包、且对数曲线在 1 级后失效）。
-- 改为发放"货币"，玩家到 Nauvis 出生点的市场按需购买：
--   · 品质科技瓶 —— 按各瓶累计经验经 √ 曲线换算（见 currency.reward_for_exp）。
--   · 品质金币   —— 按在线行为统计换算（见 currency.coin_amount + constants.coin_sources）。
local constants = require('scripts.constants')
local currency = require('scripts.currency')
local passives = require('scripts.passives')
local player_stats = require('scripts.player_stats')

local M = {}

-- ----------------------------------------------------------------------------
-- 所有人无条件获得的起手套装（保命用，不卖）：
--   modular-armor + 1 roboport(2x2,(0,0)) + 4 solar(1x1) + 1 battery-mk1(1x2)
--   背包里再塞 5 个建设机器人，配合 roboport 修缮/拆除用。
-- ----------------------------------------------------------------------------
M.starter_armor = {
    armor = 'modular-armor',
    equipment = {
        {name = 'personal-roboport-equipment', position = {0, 0}},
        {name = 'solar-panel-equipment',       position = {2, 0}},
        {name = 'solar-panel-equipment',       position = {3, 0}},
        {name = 'solar-panel-equipment',       position = {2, 1}},
        {name = 'solar-panel-equipment',       position = {3, 1}},
        {name = 'battery-equipment',           position = {4, 0}},
    },
}

M.starter_inventory = {
    {name = 'construction-robot', count = 5},
}

local function give_starter_armor(player)
    local armor_inv = player.get_inventory(defines.inventory.character_armor)
    if not armor_inv or not armor_inv.is_empty() then return end
    armor_inv.insert{name = M.starter_armor.armor, count = 1}
    local stack = armor_inv[1]
    if stack and stack.valid_for_read and stack.grid then
        for _, eq in ipairs(M.starter_armor.equipment) do
            stack.grid.put{name = eq.name, position = eq.position}
        end
    end
    local main = player.get_inventory(defines.inventory.character_main)
    if main then
        for _, it in ipairs(M.starter_inventory) do
            main.insert{name = it.name, count = it.count, quality = it.quality}
        end
    end
end

-- 发放货币：品质科技瓶（按经验）+ 品质金币（按在线统计）。
local function give_currency(player)
    local main = player.get_inventory(defines.inventory.character_main)
    if not main then return end

    -- 品质科技瓶：每瓶种按累计经验给一串 {quality,count}。每(瓶,品质)封顶 1 组(200)，不爆背包。
    for _, pack in ipairs(constants.science_packs) do
        local exp = passives.exp_total_for_pack(player.index, pack)
        for _, r in ipairs(currency.reward_for_exp(exp)) do
            main.insert{name = pack, count = r.count, quality = r.quality}
        end
    end

    -- 品质金币：金币堆叠极大，至多 3 种品质 → ≤3 格，永不爆背包。
    local stats = player_stats.get(player.index)
    for _, src in ipairs(constants.coin_sources) do
        local amount = currency.coin_amount(stats[src.stat])
        if amount > 0 then
            main.insert{name = 'coin', count = amount, quality = src.quality}
        end
    end
end

-- 玩家在本世界（storage.run）首次拥有 character 时调用。
function M.on_first_respawn(player)
    if not player or not player.character then return end
    give_starter_armor(player)
    give_currency(player)
end

return M
