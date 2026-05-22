-- 玩家在某个世界（storage.run）第一次复活时发放的初始物品。
-- 由 players.lua 在 on_player_respawned 中调用。
local passives = require('scripts.passives')

local M = {}

local LOG10 = math.log(10)

-- 每个瓶子的"等级"= 1 + floor(log10(exp))，exp<1 计 0 级。
-- 等级 N 时累计发放 1..N 级的所有物品。
function M.level_for(exp)
    if exp < 1 then return 0 end
    return 1 + math.floor(math.log(exp) / LOG10)
end
local level_for = M.level_for

-- 把某瓶子在某等级时累计能拿到的物品列出来。
-- level=0 也会返回该瓶子表里出现过的所有物品（count=0），用于 tooltip 展示。
-- 顺序按物品在 gifts_per_level 中首次出现的顺序保持稳定。
function M.cumulative_items(pack, level)
    local levels = M.gifts_per_level[pack]
    if not levels then return {} end
    local max_level = 0
    for l, _ in pairs(levels) do if l > max_level then max_level = l end end

    local agg, index = {}, {}
    for l = 1, max_level do
        local items = levels[l]
        if items then
            for _, it in ipairs(items) do
                if not index[it.name] then
                    table.insert(agg, {name = it.name, count = 0})
                    index[it.name] = #agg
                end
            end
        end
    end
    for l = 1, level do
        local items = levels[l]
        if items then
            for _, it in ipairs(items) do
                agg[index[it.name]].count = agg[index[it.name]].count + (it.count or 1)
            end
        end
    end
    return agg
end

-- ----------------------------------------------------------------------------
-- 所有人无条件获得的起手套装：
--   modular-armor + 1 roboport(2x2,(0,0)) + 4 solar(1x1,(2,0)/(3,0)/(2,1)/(3,1)) + 1 battery-mk1(1x2,(4,0))
--   背包里再塞 5 个建设机器人，配合 roboport 用。
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

-- ----------------------------------------------------------------------------
-- 每个瓶子每级发放的物品。键格式：
--   gifts_per_level[pack_name][level] = { {name=..., count=..., quality=...}, ... }
-- 暂只填了占位示例，后续按需补全。quality 可省，默认 normal。
-- ----------------------------------------------------------------------------
M.gifts_per_level = {
    -- 自动化：电力矿机 + 1 型组装机
    ['automation-science-pack'] = {
        [1] = {
            {name = 'electric-mining-drill', count = 1},
            {name = 'assembling-machine-1',  count = 1},
        },
    },
    -- 物流：2 型组装机 + 太阳能板
    ['logistic-science-pack'] = {
        [1] = {
            {name = 'assembling-machine-2', count = 1},
            {name = 'solar-panel',          count = 1},
        },
    },
    -- 军事：枪炮塔 + 子弹
    ['military-science-pack'] = {
        [1] = {
            {name = 'gun-turret',        count = 1},
            {name = 'firearm-magazine',  count = 10},
        },
    },
    -- 化工：广域配电站 + 电炉
    ['chemical-science-pack'] = {
        [1] = {
            {name = 'substation',       count = 1},
            {name = 'electric-furnace', count = 1},
        },
    },
    -- 生产：插件塔 + 3 型组装机
    ['production-science-pack'] = {
        [1] = {
            {name = 'beacon',               count = 1},
            {name = 'assembling-machine-3', count = 1},
        },
    },
    -- 通用：随身太阳能 + 建设机器人
    ['utility-science-pack'] = {
        [1] = {
            {name = 'solar-panel-equipment', count = 1},
            {name = 'construction-robot',    count = 1},
        },
    },
    -- 太空：物流机器人 + 黄箱子（storage-chest）
    ['space-science-pack'] = {
        [1] = {
            {name = 'logistic-robot', count = 1},
            {name = 'storage-chest',  count = 1},
        },
    },
    -- 冶金/Vulcanus：铸造厂 + 大型采矿机
    ['metallurgic-science-pack'] = {
        [1] = {
            {name = 'foundry',          count = 1},
            {name = 'big-mining-drill', count = 1},
        },
    },
    -- 电磁/Fulgora：电磁工厂 + 回收机
    ['electromagnetic-science-pack'] = {
        [1] = {
            {name = 'electromagnetic-plant', count = 1},
            {name = 'recycler',              count = 1},
        },
    },
    -- 农业/Gleba：生化舱 + 农业塔
    ['agricultural-science-pack'] = {
        [1] = {
            {name = 'biochamber',         count = 1},
            {name = 'agricultural-tower', count = 1},
        },
    },
    -- 低温/Aquilo：低温工厂 + 供暖塔（Aquilo 的另一标志：让设备不冻坏）
    ['cryogenic-science-pack'] = {
        [1] = {
            {name = 'cryogenic-plant', count = 1},
            {name = 'heating-tower',   count = 1},
        },
    },
    -- 普罗米修斯/碎裂行星：金币（终极货币 / 彩蛋）
    ['promethium-science-pack'] = {
        [1] = { {name = 'coin', count = 1} },
    },
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
    -- 配套发放给所有人的物品（建设机器人等），需要 armor + bot 才有用
    local main = player.get_inventory(defines.inventory.character_main)
    if main then
        for _, it in ipairs(M.starter_inventory) do
            main.insert{name = it.name, count = it.count, quality = it.quality}
        end
    end
end

local function give_science_exp_gifts(player)
    local main = player.get_inventory(defines.inventory.character_main)
    if not main then return end
    for pack, levels in pairs(M.gifts_per_level) do
        local lvl = level_for(passives.exp_total_for_pack(player.index, pack))
        for l = 1, lvl do
            local items = levels[l]
            if items then
                for _, it in ipairs(items) do
                    main.insert{name = it.name, count = it.count, quality = it.quality}
                end
            end
        end
    end
end

-- 玩家在本世界（storage.run）首次复活时调用。
function M.on_first_respawn(player)
    if not player or not player.character then return end
    give_starter_armor(player)
    give_science_exp_gifts(player)
end

return M
