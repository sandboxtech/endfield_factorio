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
    ['logistic-science-pack']        = {'solar-panel', 'assembling-machine-2'},
    ['chemical-science-pack']        = {'substation', 'electric-furnace'},
    ['production-science-pack']      = {'beacon', 'assembling-machine-3'},
    ['utility-science-pack']         = {'construction-robot', 'roboport'},
    ['space-science-pack']           = {'logistic-robot', 'buffer-chest'},
    ['metallurgic-science-pack']     = {'foundry', 'big-mining-drill'},
    ['electromagnetic-science-pack'] = {'electromagnetic-plant', 'recycler'},
    ['agricultural-science-pack']    = {'biochamber', 'heating-tower'},
    ['cryogenic-science-pack']       = {'cryogenic-plant', 'productivity-module'},
    ['promethium-science-pack']      = {'efficiency-module', 'speed-module'},
    ['military-science-pack']        = {'gun-turret', 'firearm-magazine'},
}

-- 等级 = floor(√经验)，封顶 1000（与人物等级 floor(√在线分钟) 同一公式；升下一级需 (lv+1)² 经验）。
-- 【赠品数量】= ceil(堆叠数 × 等级/100)：随等级连续增长——等级 100 = 1 组、等级 1000(封顶) = 10 组。
-- 满级(1000 级)需该瓶累计 1,000,000 经验；100 级(1 组)需 10,000 经验。
-- 注：level_groups(阶梯式 ceil(等级/100)，封顶 10) 现仅用于【背包格数加成】，与赠品数量公式分离。
M.MAX_LEVEL = 1000
M.MAX_GROUPS = 10
local LEVELS_PER_GROUP = 100

local function stack_size(item_name)
    local proto = prototypes.item[item_name]
    return (proto and proto.stack_size) or 1
end

-- 累计经验 → 等级：floor(√exp)，封顶 1000。与 ability-online 的人物等级 floor(√分钟) 同一公式。
function M.pack_level(exp)
    if not exp or exp <= 0 then return 0 end
    return math.min(M.MAX_LEVEL, math.floor(math.sqrt(exp)))
end

-- 等级 → 组数：ceil(等级/100)，封顶 10。等级 0 → 0 组。
function M.level_groups(level)
    if level <= 0 then return 0 end
    return math.min(M.MAX_GROUPS, math.ceil(level / LEVELS_PER_GROUP))
end

-- 升到下一级所需累计经验；已满级(1000)返回 nil。由 √e=lv+1 反解：e = (lv+1)²。
function M.exp_for_next_level(exp)
    local lv = M.pack_level(exp)
    if lv >= M.MAX_LEVEL then return nil end
    return (lv + 1) * (lv + 1)
end

-- 发放数 = ceil(堆叠数 × 等级/100)：随等级【连续】缩放（不再每 100 级阶梯跳整组）。
--   等级 0 → 0 件；等级 1 → ceil(堆叠×0.01)（多为 1 件）；等级 100 → 1 整组；等级 1000(封顶) → 10 组。
function M.gift_count(exp, item_name)
    local level = M.pack_level(exp)
    if level <= 0 then return 0 end
    return math.ceil(stack_size(item_name) * level / 100)
end

-- 玩家所有开局赠品总组数（每件 = 其瓶组数 × 件数）。供背包格数加成用。
function M.total_gift_groups(player_index)
    local total = 0
    for _, pack in ipairs(constants.science_packs) do
        local items = M.pack_gifts[pack]
        if items then
            total = total + M.level_groups(M.pack_level(passives.exp_total_for_pack(player_index, pack))) * #items
        end
    end
    return total
end

-- 背包格数加成 = 开局赠品总组数（每 1 组 +1 格）。每次复活/开局重设（新角色加成会清零）。
function M.apply_inventory_bonus(player)
    if not player or not player.character then return end
    player.character_inventory_slots_bonus = M.total_gift_groups(player.index)
end

-- 挂机/在线金币：每轮首次复活时发放 floor(√在线分钟)。在线越久开局金币越多。
function M.coin_reward(online_minutes)
    if not online_minutes or online_minutes <= 0 then return 0 end
    return math.floor(math.sqrt(online_minutes))
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
    {name = 'coal',               count = 50},
    {name = 'stone',              count = 50},
    {name = 'wood',              count = 50},
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

-- 按累计科技瓶经验，直接发放每种瓶对应的 2 种代表物资（数量按各自堆叠数逐个算）。
local function give_pack_gifts(player)
    local main = player.get_inventory(defines.inventory.character_main)
    if not main then return end
    for _, pack in ipairs(constants.science_packs) do
        local items = M.pack_gifts[pack]
        if items then
            local exp = passives.exp_total_for_pack(player.index, pack)
            for _, item in ipairs(items) do
                local n = M.gift_count(exp, item)
                if n > 0 then
                    main.insert{name = item, count = n}
                end
            end
        end
    end
end

-- 在线金币：开局发放 floor(√在线分钟)，用于母星金币市场买装备零件。
local function give_coins(player)
    local n = M.coin_reward(passives.get_stat(player.index, 'online_minutes'))
    if n <= 0 then return end
    local main = player.get_inventory(defines.inventory.character_main)
    if main then main.insert{name = 'coin', count = n} end
end

-- 玩家在本世界（storage.run）首次拥有 character 时调用。
function M.on_first_respawn(player)
    if not player or not player.character then return end
    give_starter_armor(player)
    give_pack_gifts(player)
    give_coins(player)
end

return M
