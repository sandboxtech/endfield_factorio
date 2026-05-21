-- 玩家在某个世界（storage.run）第一次复活时发放的初始物品。
-- 由 players.lua 在 on_player_respawned 中调用。
local passives = require('scripts.passives')

local M = {}

local LOG10 = math.log(10)

-- 每个瓶子的"等级"= 1 + floor(log10(exp))，exp<1 计 0 级。
-- 等级 N 时累计发放 1..N 级的所有物品。
local function level_for(exp)
    if exp < 1 then return 0 end
    return 1 + math.floor(math.log(exp) / LOG10)
end

-- ----------------------------------------------------------------------------
-- 起手套装：modular-armor + 1 个 personal-roboport + 2 个 solar-panel。
-- modular-armor 网格 5x5；roboport 2x2 占 (0,0)，两块太阳能 1x1 占 (2,0)/(3,0)。
-- ----------------------------------------------------------------------------
M.starter_armor = {
    armor = 'modular-armor',
    equipment = {
        {name = 'personal-roboport-equipment', position = {0, 0}},
        {name = 'solar-panel-equipment',       position = {2, 0}},
        {name = 'solar-panel-equipment',       position = {3, 0}},
    },
}

-- ----------------------------------------------------------------------------
-- 每个瓶子每级发放的物品。键格式：
--   gifts_per_level[pack_name][level] = { {name=..., count=..., quality=...}, ... }
-- 暂只填了占位示例，后续按需补全。quality 可省，默认 normal。
-- ----------------------------------------------------------------------------
M.gifts_per_level = {
    ['automation-science-pack'] = {
        -- [1] = { {name = 'iron-plate', count = 50} },
        -- [2] = { {name = 'assembling-machine-1', count = 2} },
    },
    ['logistic-science-pack']        = {},
    ['military-science-pack']        = {},
    ['chemical-science-pack']        = {},
    ['production-science-pack']      = {},
    ['utility-science-pack']         = {},
    ['space-science-pack']           = {},
    ['metallurgic-science-pack']     = {},
    ['electromagnetic-science-pack'] = {},
    ['agricultural-science-pack']    = {},
    ['cryogenic-science-pack']       = {},
    ['promethium-science-pack']      = {},
}

local function give_starter_armor(player)
    local armor_inv = player.get_inventory(defines.inventory.character_armor)
    if not armor_inv or not armor_inv.is_empty() then return end
    armor_inv.insert{name = M.starter_armor.armor, count = 1}
    local stack = armor_inv[1]
    if not (stack and stack.valid_for_read and stack.grid) then return end
    for _, eq in ipairs(M.starter_armor.equipment) do
        stack.grid.put{name = eq.name, position = eq.position}
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
