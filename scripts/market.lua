-- Nauvis 出生点的市场群：13 个原版 market 实体（每轮跃迁后延迟重放）。
--   · 12 个科技瓶市场排成 3 列 × 4 行，金币市场在最上方；每个铺混凝土地坪、整齐对齐。
--   · 货物产出固定 normal 品质；价格按物品的 q 品质货币——epic 买大需求散件、legendary 买设备/插件。
--   · 装备用普通金币买；普罗米修斯瓶兑金币。
-- 用原版交易界面。本模块注册 on_tick：到 storage.market_place_tick 时放置（避开 surface.clear 的异步结算）。
local constants = require('scripts.constants')

local M = {}

-- 市场按整齐网格平铺。CELL = 网格间距（格），每个市场会铺一块 CELL×CELL 的混凝土地坪，
-- 间距 = CELL 时地坪刚好连成一整片广场。market 选择框 3×3，CELL=5 留约 2 格走道。
local CELL = 5
local COLS = 3            -- 12 个科技瓶市场 = 3 列 × 4 行（3 列正好关于出生点居中）
local NORTH_GAP = 6      -- 最南一行距出生点的格数（北 = -Y）

-- ★★★ 市场货物配置 ★★★
-- 每个市场只收一种货币(currency = 科技瓶 / coin)。每件物品三个字段：
--   q     = 购买所需的"货币品质"。规则：
--             epic      → normal 品质的【大需求散件】（传送带/电杆/管道/墙/铁轨…，量大价低）
--             legendary → normal 品质的【设备/插件】（机器/模块/机械臂…，量小）
--             （coin 市场用 normal：在线赚的普通金币买装备）
--   price = 需要几个该品质货币
--   count = 一次买到几个；**产出固定 normal 品质**
M.sections = {
    -- 红瓶 · 自动化基础
    {currency = 'automation-science-pack', items = {
        {name = 'transport-belt',        q = 'epic',      price = 1, count = 50},
        {name = 'underground-belt',      q = 'epic',      price = 1, count = 10},
        {name = 'splitter',              q = 'epic',      price = 1, count = 10},
        {name = 'small-electric-pole',   q = 'legendary',      price = 1, count = 10},
        {name = 'assembling-machine-1',  q = 'legendary', price = 1, count = 1},
        {name = 'inserter',              q = 'legendary', price = 1, count = 5},
        {name = 'electric-mining-drill', q = 'legendary', price = 1, count = 1},
    }},
    -- 绿瓶 · 物流升级
    {currency = 'logistic-science-pack', items = {
        {name = 'fast-transport-belt',  q = 'epic',      price = 1, count = 50},
        {name = 'fast-underground-belt',q = 'epic',      price = 1, count = 10},
        {name = 'fast-splitter',        q = 'epic',      price = 1, count = 10},
        {name = 'medium-electric-pole', q = 'legendary',      price = 1, count = 10},
        {name = 'assembling-machine-2', q = 'legendary', price = 1, count = 1},
        {name = 'fast-inserter',        q = 'legendary', price = 1, count = 5},
        {name = 'solar-panel', q = 'legendary', price = 1, count = 1},
    }},
    -- 黑瓶 · 防御
    {currency = 'military-science-pack', items = {
        {name = 'firearm-magazine',  q = 'epic',      price = 1, count = 50},
        {name = 'stone-wall',  q = 'epic',      price = 1, count = 25},
        {name = 'gun-turret',  q = 'legendary', price = 1, count = 2},
        {name = 'laser-turret',q = 'legendary', price = 1, count = 1},
        {name = 'flamethrower-turret',q = 'legendary', price = 1, count = 1},
        {name = 'radar',       q = 'legendary', price = 1, count = 1},
    }},
    -- 蓝瓶 · 化工/石油
    {currency = 'chemical-science-pack', items = {
        {name = 'pipe',             q = 'epic',      price = 1, count = 50},
        {name = 'substation',       q = 'epic',      price = 1, count = 10},
        {name = 'big-electric-pole',q = 'epic',      price = 1, count = 10},
        {name = 'chemical-plant',   q = 'legendary', price = 1, count = 1},
        {name = 'oil-refinery',     q = 'legendary', price = 1, count = 1},
        {name = 'pumpjack',         q = 'legendary', price = 1, count = 1},
        {name = 'electric-furnace', q = 'legendary', price = 1, count = 1},
    }},
    -- 紫瓶 · 量产
    {currency = 'production-science-pack', items = {
        {name = 'express-transport-belt', q = 'epic',      price = 1, count = 50},
        {name = 'express-underground-belt', q = 'epic',      price = 1, count = 10},
        {name = 'express-splitter', q = 'epic',      price = 1, count = 50},
        {name = 'assembling-machine-3',   q = 'legendary', price = 1, count = 1},
        {name = 'beacon',                 q = 'legendary', price = 1, count = 1},
        {name = 'productivity-module',    q = 'legendary', price = 1, count = 1},
        {name = 'speed-module',           q = 'legendary', price = 1, count = 1},
        {name = 'efficiency-module',      q = 'legendary', price = 1, count = 1},
    }},
    -- 黄瓶 · 机器人物流
    {currency = 'utility-science-pack', items = {
        {name = 'roboport',                q = 'epic', price = 1, count = 1},
        {name = 'construction-robot',      q = 'epic', price = 1, count = 10},
        {name = 'logistic-robot',          q = 'epic', price = 1, count = 10},
        {name = 'requester-chest',         q = 'epic', price = 1, count = 1},
        {name = 'passive-provider-chest',  q = 'epic', price = 1, count = 1},
    }},
    -- 白瓶 · 太空科技，飞船设备
    {currency = 'space-science-pack', items = {
        -- [item=space-platform-starter-pack][item=crusher][item=asteroid-collector][item=thruster][item=cargo-bay]
        {name = 'speed-module-2',q = 'legendary', price = 2, count = 1},
    }},
    -- 火星瓶 · 冶金（Vulcanus）
    {currency = 'metallurgic-science-pack', items = {
        {name = 'turbo-transport-belt', q = 'epic',      price = 1, count = 10},
        {name = 'foundry',                  q = 'legendary', price = 1, count = 1},
        {name = 'big-mining-drill',         q = 'legendary', price = 1, count = 1},
        {name = 'productivity-module-2',    q = 'legendary', price = 2, count = 1},
    }},
    -- 雷星瓶 · 电磁（Fulgora）
    {currency = 'electromagnetic-science-pack', items = {
        {name = 'substation',           q = 'epic',      price = 1, count = 10},
        {name = 'electromagnetic-plant',q = 'legendary', price = 1, count = 1},
        {name = 'recycler',             q = 'legendary', price = 1, count = 1},
        {name = 'accumulator',          q = 'legendary', price = 1, count = 2},
    }},
    -- 草星瓶 · 农业（Gleba）
    {currency = 'agricultural-science-pack', items = {
        {name = 'express-splitter',   q = 'epic',      price = 1, count = 10},
        {name = 'biochamber',         q = 'legendary', price = 1, count = 1},
        {name = 'agricultural-tower', q = 'legendary', price = 1, count = 1},
    }},
    -- 极地瓶 · 低温（Aquilo）
    {currency = 'cryogenic-science-pack', items = {
        {name = 'heat-pipe',       q = 'epic',      price = 1, count = 50},
        {name = 'cryogenic-plant', q = 'legendary', price = 1, count = 1},
        {name = 'heating-tower',   q = 'legendary', price = 1, count = 1},
        {name = 'heat-exchanger',  q = 'legendary', price = 1, count = 2},
    }},
    -- 普罗米修斯市场：用普罗米修斯瓶兑换金币（金币的高级来源）。
    {currency = 'promethium-science-pack', items = {
        {name = 'coin', q = 'epic',      price = 1, count = 10},
        {name = 'coin', q = 'legendary', price = 1, count = 100},
    }},
    -- 金币市场：用在线赚的普通金币买个人装备。
    {currency = 'coin', items = {
        {name = 'solar-panel-equipment',       q = 'normal', price = 5,  count = 1},
        {name = 'battery-equipment',           q = 'normal', price = 5,  count = 1},
        {name = 'personal-roboport-equipment', q = 'normal', price = 8,  count = 1},
        {name = 'exoskeleton-equipment',       q = 'normal', price = 10, count = 1},
        {name = 'energy-shield-equipment',     q = 'normal', price = 10, count = 1},
        {name = 'night-vision-equipment',      q = 'normal', price = 3,  count = 1},
        {name = 'belt-immunity-equipment',     q = 'normal', price = 3,  count = 1},
    }},
}

local function section_for(currency)
    for _, sec in ipairs(M.sections) do
        if sec.currency == currency then return sec end
    end
end

-- 13 个市场相对出生点的偏移：12 科技瓶 3 列 × 4 行，金币市场在最上方居中。
-- 列 x = -CELL,0,+CELL（居中）；行从北到南，最南行在 -NORTH_GAP。
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

-- 上架某货币的全部货物：每件一条 offer——价格按物品的 q 品质货币，产出固定 normal。
local function stock_market(ent, currency)
    local sec = section_for(currency)
    if not sec then return end
    for _, e in ipairs(sec.items) do
        ent.add_market_item{
            price = {{name = currency, count = e.price, quality = e.q}},
            offer = {type = 'give-item', item = e.name, count = e.count or 1},  -- 产出 normal
        }
    end
end

-- 每轮跃迁后调用：在出生点重放 13 个市场并上架货物。
function M.place_on_nauvis()
    local nauvis = game.surfaces['nauvis']
    if not nauvis then return end
    local force = game.forces.player
    local s = force.get_spawn_position(nauvis)
    local bx, by = math.floor(s.x), math.floor(s.y)  -- 取整锚点，保证整数坐标对齐

    -- 紧接 surface.clear 之后，必须强制生成市场所在区块，否则 create_entity 会失败
    nauvis.request_to_generate_chunks({bx, by}, 2)
    nauvis.force_generate_chunk_requests()
    force.chart(nauvis, {{bx - 16, by - 24}, {bx + 16, by + 8}})

    -- 清掉旧市场（surface.clear 已删，这里是重复调用时的安全网）
    for _, old in pairs(nauvis.find_entities_filtered{name = 'market', position = {bx, by}, radius = 64}) do
        old.destroy()
    end

    local half = math.floor(CELL / 2)
    local placed = 0
    local total = #M.layout()
    for _, m in ipairs(M.layout()) do
        local pos = {x = bx + m.dx, y = by + m.dy}
        -- 清掉挡路实体（树/悬崖/石头；矿脉不挡建筑，保留）
        for _, e in pairs(nauvis.find_entities_filtered{position = pos, radius = half + 1, type = {'tree', 'cliff', 'simple-entity'}}) do
            if e.valid then e.destroy() end
        end
        -- 铺一块 CELL×CELL 混凝土地坪：去掉水/不平地形，保证精确网格对齐放置
        local tiles = {}
        for dx = -half, CELL - 1 - half do
            for dy = -half, CELL - 1 - half do
                tiles[#tiles + 1] = {name = 'refined-concrete', position = {pos.x + dx, pos.y + dy}}
            end
        end
        nauvis.set_tiles(tiles)
        -- 精确放在网格点，不再就近挪位 → 整齐
        local ent = nauvis.create_entity{name = 'market', position = pos, force = force}
        if ent then
            ent.destructible = false   -- 不可摧毁
            ent.minable = false        -- 不可挖取
            stock_market(ent, m.currency)
            force.add_chart_tag(nauvis, {position = pos, icon = {type = 'item', name = m.currency}})
            placed = placed + 1
        end
    end

    -- 报出锚点坐标 + 数量，玩家可打开地图(M)看图标，或 /c 传送过去
    game.print({'wn.market-ready', placed .. '/' .. total, bx, by})
end

-- 延迟放置：reset 设置 storage.market_place_tick；到点后放市场。
-- 必须晚于 reset 那一 tick，否则 surface.clear() 的异步结算会把市场清掉。
script.on_event(defines.events.on_tick, function()
    local t = storage.market_place_tick
    if t and game.tick >= t then
        storage.market_place_tick = nil
        M.place_on_nauvis()
    end
end)

return M
