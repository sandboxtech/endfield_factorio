-- 玩家在某个世界（storage.run）第一次复活时发放的初始物资。
-- 由 players.lua 在 on_player_respawned / on_player_created 中调用。
--
-- 发放分两部分：
--   ① 固定起手护甲（give_starter_armor，发到护甲格，不占主格）。
--   ② 主格物品清单（M.gift_list）= 起手基础物资 + 开局金币 + 【职业】starter(无条件按组发) + rewards(按瓶等级 floor 发)。
--      背包格数加成已改为 force 级固定 +50（见 reset.lua，随机器人跟随上限一起每轮重设），不再按礼包格数 per-player 动态扩。
local passives = require('scripts.passives')
local classes = require('scripts.classes')
local constants = require('scripts.constants')
local util = require('scripts.util')

local M = {}

-- 等级 = floor(√经验)，封顶 100000（经验本身无上限；升下一级需 (lv+1)² 经验）。
-- 经验 = 累计瓶数×品质系数（每个瓶 1 点）；满级(100000 级)需该瓶累计 1×10^10 经验。
M.MAX_LEVEL = constants.MAX_LEVEL

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
        -- starter 无条件：有 count 按个数，否则 groups 组(默认 1 组=1 堆叠)。可选 p：每件独立 p 概率获得 → 实发 ~ B(总数, p)。
        for _, s in ipairs(def.starter or {}) do
            local total = s.count or (stack_size(s.item) * (s.groups or 1))
            if (s.p or 1) < 1 then total = util.binomial(total, s.p) end
            add(s.item, total)
        end
        -- rewards（可多条 → 多瓶职业）：各按对应瓶等级线性发。职业级满级线 def.full：该职业每种瓶练到 full 级，
        -- 即拿满该条【满级配额】——是这个职业的“完美追求”目标。满级配额 = count 个 或 堆叠×groups 组(默认 1 组)。
        -- 个数 = floor(满级配额 × min(瓶等级,full) / full)【向下取整】：full 越小越快满。可选 p 同 starter（按应发数二项采样）。
        local class_full = def.full or M.MAX_LEVEL
        for _, r in ipairs(def.rewards or {}) do
            local full = r.full or class_full   -- 每条 reward 可带自己的 full 覆盖职业 full（nil 则继承职业），单独控制该条满级速度
            local lv = math.min(M.pack_level(passives.exp_total_for_pack(player.index, r.pack)), full)
            local cap = r.count or (stack_size(r.item) * (r.groups or 1))   -- 满级配额：有 count 按个数，否则 堆叠×groups
            local cnt = math.floor(cap * lv / full)
            if (r.p or 1) < 1 then cnt = util.binomial(cnt, r.p) end
            add(r.item, cnt)
        end
    end
    return list
end

-- 背包格数加成已移到 force 级固定 +50（reset.lua 里随机器人跟随上限一起每轮重设），此处不再 per-player 计算。

-- ----------------------------------------------------------------------------
-- 固定起手护甲（不随等级变化）：modular-armor 内置 1 个人机器人端口 + 1 夜视仪 + 1 个 1 级电池 + 10 块太阳能板。
-- 背包另发起手基础物资。（旧的"随等级提高护甲品质 + 太阳能板数目/品质"机制已移除。）
-- ----------------------------------------------------------------------------
-- 起手基础物资：现在只发【建设机器人】给所有职业（配合护甲的机器人端口）；
M.starter_inventory = {
    {name = 'construction-robot', count = 10},
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
    classes.commit_current(player)   -- 本世界首次发装备 = 预约职业正式生效 → 落定为【当前】职业（装备也按预约职业发）
    give_starter_armor(player)
    local main = player.get_inventory(defines.inventory.character_main)
    if not main then return end
    local list = M.gift_list(player)
    for _, it in ipairs(list) do
        main.insert{name = it.name, count = it.count}
    end
end

return M
