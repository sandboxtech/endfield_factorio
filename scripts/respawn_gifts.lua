-- 玩家在某个世界（storage.run）第一次复活时发放的初始物资。
-- 由 players.lua 在 on_player_respawned / on_player_created 中调用。
--
-- 发放分两部分：
--   ① 固定起手护甲（give_starter_armor，发到护甲格，不占主格）。
--   ② 主格物品清单（M.gift_list）= 起手基础物资 + 开局金币 + 【职业】starter(无条件按组发) + rewards(按瓶等级 floor 发)。
--      背包格数加成 = 该清单总格数 → 初始给多少格物品就扩多少格背包、刚好装下（见 apply_inventory_bonus）。
local passives = require('scripts.passives')
local classes = require('scripts.classes')

local M = {}

-- 等级 = floor(√经验)，封顶 10000（经验本身无上限；升下一级需 (lv+1)² 经验）。
-- 经验 = 累计瓶数×品质系数（每个瓶 1 点）；满级(10000 级)需该瓶累计 1×10^8 经验。
M.MAX_LEVEL = 10000

local function stack_size(item_name)
    local proto = prototypes.item[item_name]
    return (proto and proto.stack_size) or 1
end

-- 累计经验 → 等级：floor(√exp)，封顶 MAX_LEVEL。与 ability-online 的人物等级 floor(√分钟) 同一公式。
function M.pack_level(exp)
    if not exp or exp <= 0 then return 0 end
    return math.min(M.MAX_LEVEL, math.floor(math.sqrt(exp)))
end

-- 升到下一级所需累计经验；已满级返回 nil。由 √e=lv+1 反解：e = (lv+1)²。
function M.exp_for_next_level(exp)
    local lv = M.pack_level(exp)
    if lv >= M.MAX_LEVEL then return nil end
    return (lv + 1) * (lv + 1)
end

-- 挂机/在线金币：每轮首次复活时发放 floor(√在线分钟)。在线越久开局金币越多。
function M.coin_reward(online_minutes)
    if not online_minutes or online_minutes <= 0 then return 0 end
    return math.floor(math.sqrt(online_minutes))
end

-- 本轮首次复活【发到背包主格】的完整物品清单：起手基础物资 + 金币 + 职业 starter(无条件按组) + rewards(按瓶等级 floor)。
-- 发放与背包格数加成共用它 → 保证"给多少格物品就扩多少格背包"。
function M.gift_list(player)
    local list = {}
    local function add(name, count) if count and count > 0 then list[#list + 1] = {name = name, count = count} end end
    local def = classes.def_of(player)
    for _, it in ipairs(M.starter_inventory) do add(it.name, it.count) end
    add('coin', M.coin_reward(passives.get_stat(player.index, 'online_minutes')))
    if def then
        for _, s in ipairs(def.starter or {}) do add(s.item, stack_size(s.item) * (s.groups or 1)) end   -- 前者：无条件按组发（可多种）
        -- 后者（可多条 → 多瓶职业）：各按对应瓶等级线性发。满级(MAX_LEVEL) 发 r.groups 组(=堆叠×groups 个)，
        -- 个数 = floor(堆叠 × groups × 等级 / 满级)【向下取整】：满 N 级才给第 1 个（不足 N 级给 0），
        -- 例 N=20 时 0~19 级 0 个、20 级 1 个、40 级 2 个。groups 逐物品配置（见 classes.lua）。
        for _, r in ipairs(def.rewards or {}) do
            local lv = M.pack_level(passives.exp_total_for_pack(player.index, r.pack))
            add(r.item, math.floor(stack_size(r.item) * (r.groups or 1) * lv / M.MAX_LEVEL))
        end
    end
    return list
end

-- gift_list 占用的背包格数（每种 = ceil(数量/堆叠)）。
local function gift_slot_count(list)
    local slots = 0
    for _, it in ipairs(list) do slots = slots + math.ceil(it.count / stack_size(it.name)) end
    return slots
end

-- 背包格数加成 = 本轮首发清单的总格数（首发时存进 storage.gift_slots[名]）。
-- 每次复活/创建重设（新角色加成清零），读存值即可、不重算（避免本轮切职业后格数与已发物品不符）。
function M.apply_inventory_bonus(player)
    if not player or not player.character then return end
    player.character_inventory_slots_bonus = (storage.gift_slots or {})[player.name] or 0
end

-- ----------------------------------------------------------------------------
-- 固定起手护甲（不随等级变化）：modular-armor 内置 1 个人机器人端口 + 1 夜视仪 + 1 个 1 级电池 + 10 块太阳能板。
-- 背包另发起手基础物资。（旧的"随等级提高护甲品质 + 太阳能板数目/品质"机制已移除。）
-- ----------------------------------------------------------------------------
M.starter_inventory = {
    {name = 'construction-robot', count = 10},
    {name = 'iron-plate',         count = 200},
    {name = 'copper-plate',       count = 100},
    {name = 'coal',               count = 50},
    {name = 'stone',              count = 50},
    {name = 'wood',               count = 50},
}

local function give_starter_armor(player)
    local armor_inv = player.get_inventory(defines.inventory.character_armor)
    if not armor_inv or not armor_inv.is_empty() then return end

    armor_inv.insert{name = 'modular-armor', count = 1}
    local stack = armor_inv[1]
    if stack and stack.valid_for_read and stack.grid then
        local grid = stack.grid
        -- 固定内置：1 个人机器人端口 + 1 夜视仪 + 1 个 1 级电池 + 10 块太阳能板。
        -- 不带 position，由引擎自动布局（modular-armor 5x5=25 格，占 4+4+2+10=20，放得下）。
        grid.put{name = 'personal-roboport-equipment'}
        grid.put{name = 'night-vision-equipment'}
        grid.put{name = 'battery-equipment'}
        for _ = 1, 10 do grid.put{name = 'solar-panel-equipment'} end
    end
end

-- 玩家在本世界（storage.run）首次拥有 character 时调用：发护甲 + 主格物品清单，并把背包格数设到刚好装下。
function M.on_first_respawn(player)
    if not player or not player.character then return end
    give_starter_armor(player)
    local main = player.get_inventory(defines.inventory.character_main)
    if not main then return end
    local list = M.gift_list(player)
    local slots = gift_slot_count(list)
    storage.gift_slots = storage.gift_slots or {}
    storage.gift_slots[player.name] = slots
    player.character_inventory_slots_bonus = slots   -- 首发当场设格；后续复活由 apply_inventory_bonus 读存值保持
    for _, it in ipairs(list) do
        main.insert{name = it.name, count = it.count}
    end
end

return M
