-- 玩家在某个世界（storage.run）第一次复活时发放的初始物资。
-- 由 players.lua 在 on_player_respawned / on_player_created 中调用。
--
-- 设计（去掉市场/金币这层中间商，降低认知负担）：
--   你跃迁前背包里某种科技瓶带得越多（累计经验越高），下次开局就【直接】发放
--   该瓶对应的 2 种代表物资，数量随经验增长（√ 曲线，封顶 GIFT_CAP）。
--   "带红瓶→下局直接给矿机+组装机"，一秒就懂，不必再去市场用瓶子换。
local constants = require('scripts.constants')
local passives = require('scripts.passives')

local M = {}

-- 每种科技瓶 → 下次开局直接发放的 2 种代表物资。可自由增删/替换。
M.pack_gifts = {
    ['automation-science-pack']      = {'electric-mining-drill', 'assembling-machine-1'},
    ['logistic-science-pack']        = {'assembling-machine-2', 'fast-transport-belt'},
    ['chemical-science-pack']        = {'chemical-plant', 'oil-refinery'},
    ['production-science-pack']      = {'assembling-machine-3', 'productivity-module'},
    ['utility-science-pack']         = {'construction-robot', 'roboport'},
    ['space-science-pack']           = {'rail', 'locomotive'},
    ['metallurgic-science-pack']     = {'foundry', 'big-mining-drill'},
    ['electromagnetic-science-pack'] = {'electromagnetic-plant', 'recycler'},
    ['agricultural-science-pack']    = {'biochamber', 'agricultural-tower'},
    ['cryogenic-science-pack']       = {'cryogenic-plant', 'heating-tower'},
    ['promethium-science-pack']      = {'productivity-module-3', 'speed-module-3'},
    ['military-science-pack']        = {'gun-turret', 'firearm-magazine'},
}

-- 单种物资单局发放数量 = floor(√exp)，封顶 GIFT_CAP（避免爆背包/过度碾压）。
-- exp=0→0、=100→10、=400→20、≥2500→50（封顶）。供 gui 面板预览复用。
local GIFT_CAP = 50
function M.gift_count(exp)
    if not exp or exp <= 0 then return 0 end
    local n = math.floor(math.sqrt(exp))
    if n > GIFT_CAP then n = GIFT_CAP end
    return n
end

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
    {name = 'construction-robot', count = 10},
    {name = 'iron-plate',         count = 200},
    {name = 'copper-plate',       count = 100},
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

-- 按累计科技瓶经验，直接发放每种瓶对应的 2 种代表物资（数量 = gift_count(exp)）。
local function give_pack_gifts(player)
    local main = player.get_inventory(defines.inventory.character_main)
    if not main then return end
    for _, pack in ipairs(constants.science_packs) do
        local items = M.pack_gifts[pack]
        if items then
            local n = M.gift_count(passives.exp_total_for_pack(player.index, pack))
            if n > 0 then
                for _, item in ipairs(items) do
                    main.insert{name = item, count = n}
                end
            end
        end
    end
end

-- 玩家在本世界（storage.run）首次拥有 character 时调用。
function M.on_first_respawn(player)
    if not player or not player.character then return end
    give_starter_armor(player)
    give_pack_gifts(player)
end

return M
