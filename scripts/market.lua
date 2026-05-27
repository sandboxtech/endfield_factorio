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

-- 商店分区。currency 为科技瓶名或 'coin'；price 单位为该货币的"个数"。
M.sections = {
    {currency = 'automation-science-pack',     items = {{name = 'electric-mining-drill', price = 5}, {name = 'assembling-machine-1', price = 5}}},
    {currency = 'logistic-science-pack',       items = {{name = 'assembling-machine-2', price = 5}, {name = 'solar-panel', price = 5}}},
    {currency = 'military-science-pack',        items = {{name = 'gun-turret', price = 5}, {name = 'firearm-magazine', price = 2}}},
    {currency = 'chemical-science-pack',        items = {{name = 'substation', price = 8}, {name = 'electric-furnace', price = 5}}},
    {currency = 'production-science-pack',      items = {{name = 'beacon', price = 10}, {name = 'assembling-machine-3', price = 10}}},
    {currency = 'utility-science-pack',         items = {{name = 'logistic-robot', price = 3}, {name = 'construction-robot', price = 2}}},
    {currency = 'space-science-pack',           items = {{name = 'storage-chest', price = 3}, {name = 'requester-chest', price = 5}}},
    {currency = 'metallurgic-science-pack',     items = {{name = 'foundry', price = 10}, {name = 'big-mining-drill', price = 10}}},
    {currency = 'electromagnetic-science-pack', items = {{name = 'electromagnetic-plant', price = 10}, {name = 'recycler', price = 8}}},
    {currency = 'agricultural-science-pack',    items = {{name = 'biochamber', price = 8}, {name = 'agricultural-tower', price = 8}}},
    {currency = 'cryogenic-science-pack',       items = {{name = 'cryogenic-plant', price = 10}, {name = 'heating-tower', price = 8}}},
    -- 普罗米修斯（终极货币）：按品质兑换金币，是 epic/legendary 金币的唯一来源 → 高级装备。
    {currency = 'promethium-science-pack',      items = {{name = 'coin', price = 1}}},
    -- 金币市场：用品质金币购买装备（normal/uncommon/rare 来自在线行为，epic/legendary 来自普罗米修斯兑换）。
    {currency = 'coin', items = {
        {name = 'solar-panel-equipment',        price = 5},
        {name = 'battery-equipment',            price = 5},
        {name = 'personal-roboport-equipment',  price = 8},
        {name = 'exoskeleton-equipment',        price = 10},
        {name = 'energy-shield-equipment',      price = 10},
        {name = 'night-vision-equipment',       price = 3},
        {name = 'belt-immunity-equipment',      price = 3},
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
