-- Nauvis 出生点的市场群：13 个原版 market 实体，每个只卖一种货币的 5 品质货物。
--   · 12 个科技瓶市场排成 3 列 × 4 行（3 格间距），金币市场在最上方居中。
--   · 直接用原版 add_market_item 上架 offer：价格和产出都带 quality（付 Q 品质货币得 Q 品质物品）。
--   · 生产建筑用对应品质科技瓶购买；装备用品质金币购买；普罗米修斯瓶兑金币。
-- 用原版交易界面，本模块不注册任何事件，只提供 place_on_nauvis() 供 reset 调用。
local constants = require('scripts.constants')

local M = {}

-- 每个市场占 3×3 格（market 选择框正好 3×3），按 3 格间距平铺。
local CELL = 3
local COLS = 3            -- 12 个科技瓶市场 = 3 列 × 4 行（3 列正好关于出生点居中）
local NORTH_GAP = 6      -- 最南一行距出生点的格数（北 = -Y）

-- ★★★ 手动配置区：填写每个市场出售什么 ★★★
-- 规则：
--   · 每个市场只收一种货币(currency)。science-pack 市场卖"该瓶对应科技阶段的商品"（保持通用）。
--   · 每个物品按 5 个品质各上架一条 offer：付 Q 品质货币 → 得 Q 品质物品。
--   · price = 购买所需的"该品质货币"个数。普通(normal)瓶子可量产，不作为奖励来源。
--   · 金币(coin)不作为任何奖励发放——只能在普罗米修斯市场用普罗米修斯瓶兑换；金币市场卖装备。
-- 物品格式：{name = '物品原型名', price = 数字}
-- 示例（automation 市场）：items = {{name = 'electric-mining-drill', price = 5}, {name = 'assembling-machine-1', price = 5}}
M.sections = {
    -- 红瓶 · 自动化基础：采矿/组装/传送带/机械臂/电杆/管道
    {currency = 'automation-science-pack', items = {
        {name = 'electric-mining-drill', price = 3}, {name = 'assembling-machine-1', price = 3},
        {name = 'transport-belt', price = 1}, {name = 'inserter', price = 1},
        {name = 'small-electric-pole', price = 1}, {name = 'pipe', price = 1},
    }},
    -- 绿瓶 · 物流升级：2 级组装/快速带/地下带/分流器/快爪/中型电杆
    {currency = 'logistic-science-pack', items = {
        {name = 'assembling-machine-2', price = 4}, {name = 'fast-transport-belt', price = 2},
        {name = 'underground-belt', price = 2}, {name = 'splitter', price = 2},
        {name = 'fast-inserter', price = 2}, {name = 'medium-electric-pole', price = 2},
    }},
    -- 黑瓶 · 防御（保护工厂，非个人装备）：枪炮塔/激光塔/墙/闸门/雷达
    {currency = 'military-science-pack', items = {
        {name = 'gun-turret', price = 3}, {name = 'laser-turret', price = 6},
        {name = 'stone-wall', price = 1}, {name = 'gate', price = 2}, {name = 'radar', price = 4},
    }},
    -- 蓝瓶 · 化工/石油：化工厂/炼油厂/抽油机/电炉/储液罐/大型配电
    {currency = 'chemical-science-pack', items = {
        {name = 'chemical-plant', price = 4}, {name = 'oil-refinery', price = 6},
        {name = 'pumpjack', price = 4}, {name = 'electric-furnace', price = 5},
        {name = 'storage-tank', price = 2}, {name = 'substation', price = 4},
    }},
    -- 紫瓶 · 量产：3 级组装/信标/模块/特快带
    {currency = 'production-science-pack', items = {
        {name = 'assembling-machine-3', price = 8}, {name = 'beacon', price = 8},
        {name = 'productivity-module', price = 6}, {name = 'speed-module', price = 6},
        {name = 'efficiency-module', price = 5}, {name = 'express-transport-belt', price = 3},
    }},
    -- 黄瓶 · 机器人物流：机器人塔/建设/物流机器人/请求箱/供应箱/大电杆
    {currency = 'utility-science-pack', items = {
        {name = 'roboport', price = 8}, {name = 'construction-robot', price = 2},
        {name = 'logistic-robot', price = 2}, {name = 'requester-chest', price = 4},
        {name = 'passive-provider-chest', price = 3}, {name = 'big-electric-pole', price = 3},
    }},
    -- 白瓶 · 大规模运输：火车/车厢/铁轨/车站/集装机械臂/2 级速度模块
    {currency = 'space-science-pack', items = {
        {name = 'locomotive', price = 6}, {name = 'cargo-wagon', price = 4},
        {name = 'rail', price = 1}, {name = 'train-stop', price = 3},
        {name = 'bulk-inserter', price = 5}, {name = 'speed-module-2', price = 12},
    }},
    -- 火星瓶 · 冶金（Vulcanus）：铸造厂/大型采矿机/2 级产能模块/特快地下带
    {currency = 'metallurgic-science-pack', items = {
        {name = 'foundry', price = 8}, {name = 'big-mining-drill', price = 8},
        {name = 'productivity-module-2', price = 12}, {name = 'express-underground-belt', price = 4},
    }},
    -- 雷星瓶 · 电磁（Fulgora）：电磁工厂/回收机/蓄电池/大型配电
    {currency = 'electromagnetic-science-pack', items = {
        {name = 'electromagnetic-plant', price = 8}, {name = 'recycler', price = 6},
        {name = 'accumulator', price = 3}, {name = 'substation', price = 4},
    }},
    -- 草星瓶 · 农业（Gleba）：生化舱/农业塔/特快分流器
    {currency = 'agricultural-science-pack', items = {
        {name = 'biochamber', price = 6}, {name = 'agricultural-tower', price = 6},
        {name = 'express-splitter', price = 4},
    }},
    -- 极地瓶 · 低温（Aquilo）：低温工厂/供暖塔/热管/热交换器
    {currency = 'cryogenic-science-pack', items = {
        {name = 'cryogenic-plant', price = 8}, {name = 'heating-tower', price = 6},
        {name = 'heat-pipe', price = 1}, {name = 'heat-exchanger', price = 4},
    }},
    -- 普罗米修斯市场：兑换金币（金币唯一来源；付 Q 品质普罗米修斯瓶得 Q 品质金币）。
    {currency = 'promethium-science-pack', items = {{name = 'coin', price = 1}}},
    -- 金币市场：卖个人装备（用金币购买）。
    {currency = 'coin', items = {
        {name = 'solar-panel-equipment', price = 5}, {name = 'battery-equipment', price = 5},
        {name = 'personal-roboport-equipment', price = 8}, {name = 'exoskeleton-equipment', price = 10},
        {name = 'energy-shield-equipment', price = 10}, {name = 'night-vision-equipment', price = 3},
        {name = 'belt-immunity-equipment', price = 3},
    }},
}

local function section_for(currency)
    for _, sec in ipairs(M.sections) do
        if sec.currency == currency then return sec end
    end
end

-- 13 个市场相对出生点的偏移：12 科技瓶 3 列 × 4 行，金币市场在最上方居中。
-- 列 x = -3,0,3（居中）；行从北到南，最南行在 -NORTH_GAP。
function M.layout()
    local out = {}
    local rows = math.ceil(#constants.science_packs / COLS)   -- 4
    for i, pack in ipairs(constants.science_packs) do
        local col = (i - 1) % COLS                            -- 0,1,2
        local row = math.floor((i - 1) / COLS)                -- 0..3
        local dx = (col - (COLS - 1) / 2) * CELL              -- -3,0,3
        local dy = -(NORTH_GAP + (rows - 1 - row) * CELL)     -- row0 最北
        out[#out + 1] = {currency = pack, dx = dx, dy = dy}
    end
    out[#out + 1] = {currency = 'coin', dx = 0, dy = -(NORTH_GAP + rows * CELL)}  -- 金币市场最北
    return out
end

-- 上架某货币的全部货物：每个物品 × 每种品质一个 offer，价格和产出都带品质。
local function stock_market(ent, currency)
    local sec = section_for(currency)
    if not sec then return end
    for _, e in ipairs(sec.items) do
        for _, q in ipairs(constants.quality_order) do
            ent.add_market_item{
                price = {{name = currency, count = e.price, quality = q}},
                offer = {type = 'give-item', item = e.name, count = 1, quality = q},
            }
        end
    end
end

-- 每轮跃迁后调用：在出生点重放 13 个市场并上架货物。
function M.place_on_nauvis()
    local nauvis = game.surfaces['nauvis']
    if not nauvis then return end
    local force = game.forces.player
    local s = force.get_spawn_position(nauvis)
    local bx, by = math.floor(s.x), math.floor(s.y)  -- 取整锚点，保证整数坐标对齐

    nauvis.request_to_generate_chunks({bx, by}, 2)
    nauvis.force_generate_chunk_requests()

    -- 清掉旧市场（surface.clear 已删，这里是重复调用时的安全网）
    for _, old in pairs(nauvis.find_entities_filtered{name = 'market', position = {bx, by}, radius = 64}) do
        old.destroy()
    end

    for _, m in ipairs(M.layout()) do
        local ent = nauvis.create_entity{name = 'market', position = {x = bx + m.dx, y = by + m.dy}, force = force}
        if ent then
            ent.destructible = false   -- 不可摧毁
            ent.minable = false        -- 不可挖取
            stock_market(ent, m.currency)
        end
    end

    force.chart(nauvis, {{bx - 12, by - 22}, {bx + 12, by + 6}})
end

return M
