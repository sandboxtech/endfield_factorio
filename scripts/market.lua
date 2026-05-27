-- Nauvis 出生点的装备/建筑市场。
--   · 每次跃迁后在出生点放一个 market 实体（surface 被清空会一并删除，故每轮重放）。
--   · 玩家打开它时拦截原版 GUI，弹出自定义商店：付 Q 品质货币 → 得 Q 品质物品。
--   · 生产建筑用"对应品质科技瓶"购买；装备用"品质金币"购买。
-- 事件登记：on_gui_opened / on_gui_closed 本模块独占；on_gui_click 由 tick.lua 统一转发，
-- 避免多文件重复注册 on_gui_click 互相覆盖。
local constants = require('scripts.constants')

local M = {}

local FRAME = 'endfield_shop'
local BUY_PREFIX = 'efbuy|'

-- 商店分区。currency 为科技瓶名或 'coin'；price 单位为该货币的"个数"。
-- 物品名沿用原 respawn_gifts 的初始物品表，外加一组装备（用金币购买）。
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
    -- 装备市场：用品质金币购买（normal/uncommon/rare 来自在线行为，epic/legendary 来自普罗米修斯兑换）。
    {currency = 'coin', is_equipment = true, items = {
        {name = 'solar-panel-equipment',        price = 5},
        {name = 'battery-equipment',            price = 5},
        {name = 'personal-roboport-equipment',  price = 8},
        {name = 'exoskeleton-equipment',        price = 10},
        {name = 'energy-shield-equipment',      price = 10},
        {name = 'night-vision-equipment',       price = 3},
        {name = 'belt-immunity-equipment',      price = 3},
    }},
}

-- ----------------------------------------------------------------------------
-- 库存查询/扣费小工具
-- ----------------------------------------------------------------------------
local function count_q(inv, name, quality)
    local total = 0
    for _, c in pairs(inv.get_contents()) do
        if c.name == name and c.quality == quality then total = total + c.count end
    end
    return total
end

local function price_of(currency, item)
    for _, sec in ipairs(M.sections) do
        if sec.currency == currency then
            for _, e in ipairs(sec.items) do
                if e.name == item then return e.price end
            end
        end
    end
end

-- 某货币玩家各品质余额，拼成富文本；全 0 返回 "—"。
local function balance_str(inv, currency)
    if not inv then return '—' end
    local parts = {}
    for _, q in ipairs(constants.quality_order) do
        local n = count_q(inv, currency, q)
        if n > 0 then parts[#parts + 1] = '[item=' .. currency .. ',quality=' .. q .. ']×' .. n end
    end
    if #parts == 0 then return '—' end
    return table.concat(parts, ' ')
end

-- ----------------------------------------------------------------------------
-- 购买
-- ----------------------------------------------------------------------------
function M.try_buy(player, item, quality, currency)
    if not (player and player.valid) then return end
    local inv = player.get_main_inventory()
    if not inv then return end
    local price = price_of(currency, item)
    if not price then return end

    if count_q(inv, currency, quality) < price then
        player.create_local_flying_text{text = {'wn.shop-poor'}, create_at_cursor = true}
        return
    end
    local removed = inv.remove{name = currency, count = price, quality = quality}
    if removed < price then
        if removed > 0 then inv.insert{name = currency, count = removed, quality = quality} end
        return
    end
    local got = inv.insert{name = item, count = 1, quality = quality}
    if got < 1 then
        inv.insert{name = currency, count = price, quality = quality}  -- 背包满，退款
        player.create_local_flying_text{text = {'wn.shop-full'}, create_at_cursor = true}
    end
end

-- ----------------------------------------------------------------------------
-- 商店 GUI
-- ----------------------------------------------------------------------------
function M.open_shop(player)
    local screen = player.gui.screen
    if screen[FRAME] then screen[FRAME].destroy() end

    local frame = screen.add{type = 'frame', name = FRAME, direction = 'vertical'}
    frame.auto_center = true

    -- 标题栏（可拖动 + 关闭按钮）
    local bar = frame.add{type = 'flow', direction = 'horizontal'}
    local title = bar.add{type = 'label', caption = {'wn.shop-title'}}
    title.style.font = 'heading-1'
    local drag = bar.add{type = 'empty-widget', style = 'draggable_space_header'}
    drag.style.horizontally_stretchable = true
    drag.style.minimal_width = 120
    drag.style.height = 24
    drag.drag_target = frame
    bar.add{type = 'sprite-button', name = 'efshop_close', sprite = 'utility/close',
            style = 'frame_action_button', tooltip = {'wn.shop-close'}}

    frame.add{type = 'label', caption = {'wn.shop-hint'}}

    local scroll = frame.add{type = 'scroll-pane', direction = 'vertical'}
    scroll.style.maximal_height = 640
    scroll.style.minimal_width = 560

    local inv = player.get_main_inventory()
    local ncol = 1 + #constants.quality_order

    for _, sec in ipairs(M.sections) do
        -- 分区标题：货币图标 + 余额
        local label = sec.is_equipment and {'wn.shop-section-equip', balance_str(inv, sec.currency)}
                                        or  {'wn.shop-section', '[item=' .. sec.currency .. ']', balance_str(inv, sec.currency)}
        local hdr = scroll.add{type = 'label', caption = label}
        hdr.style.font = 'default-bold'
        hdr.style.top_padding = 6

        local tbl = scroll.add{type = 'table', column_count = ncol}
        -- 表头：空 + 各品质图标
        tbl.add{type = 'label', caption = ''}
        for _, q in ipairs(constants.quality_order) do
            tbl.add{type = 'label', caption = '[quality=' .. q .. ']'}
        end
        -- 每个物品一行：物品图标+价 + 各品质购买按钮
        for _, e in ipairs(sec.items) do
            tbl.add{type = 'label', caption = '[item=' .. e.name .. '] ' .. e.price}
            for _, q in ipairs(constants.quality_order) do
                tbl.add{
                    type = 'sprite-button',
                    name = BUY_PREFIX .. e.name .. '|' .. q .. '|' .. sec.currency,
                    sprite = 'item/' .. e.name,
                    number = e.price,
                    tooltip = {'wn.shop-buy-tip',
                               '[item=' .. e.name .. ',quality=' .. q .. ']',
                               e.price,
                               '[item=' .. sec.currency .. ',quality=' .. q .. ']'},
                }
            end
        end
    end

    player.opened = frame  -- 关闭实体原版 GUI 并以本框为当前打开窗（ESC 可关）
end

-- ----------------------------------------------------------------------------
-- 市场实体放置（每轮跃迁后调用）
-- ----------------------------------------------------------------------------
function M.place_on_nauvis()
    local nauvis = game.surfaces['nauvis']
    if not nauvis then return end
    local force = game.forces.player
    local origin = force.get_spawn_position(nauvis)

    nauvis.request_to_generate_chunks(origin, 1)
    nauvis.force_generate_chunk_requests()

    for _, old in pairs(nauvis.find_entities_filtered{name = 'market', position = origin, radius = 64}) do
        old.destroy()
    end

    local pos = nauvis.find_non_colliding_position('market', origin, 32, 1) or origin
    local market = nauvis.create_entity{name = 'market', position = pos, force = force}
    if market then
        market.destructible = false
        market.minable = false
        storage.market_unit_number = market.unit_number
        force.chart(nauvis, {{pos.x - 16, pos.y - 16}, {pos.x + 16, pos.y + 16}})
    end
end

-- ----------------------------------------------------------------------------
-- 事件
-- ----------------------------------------------------------------------------
-- 打开市场实体 → 弹自定义商店。
script.on_event(defines.events.on_gui_opened, function(event)
    if event.gui_type ~= defines.gui_type.entity then return end
    local e = event.entity
    if not (e and e.valid and e.unit_number == storage.market_unit_number) then return end
    local player = game.get_player(event.player_index)
    if player then M.open_shop(player) end
end)

-- ESC 关闭商店框时销毁它。
script.on_event(defines.events.on_gui_closed, function(event)
    local el = event.element
    if el and el.valid and el.name == FRAME then el.destroy() end
end)

-- 由 tick.lua 的 on_gui_click 统一转发。
function M.on_gui_click(event)
    local el = event.element
    if not (el and el.valid) then return end
    local player = game.get_player(event.player_index)
    if not player then return end

    if el.name == 'efshop_close' then
        if player.gui.screen[FRAME] then player.gui.screen[FRAME].destroy() end
        return
    end
    if string.sub(el.name, 1, #BUY_PREFIX) == BUY_PREFIX then
        local item, quality, currency = string.match(el.name, '^efbuy|([^|]+)|([^|]+)|([^|]+)$')
        if item then
            M.try_buy(player, item, quality, currency)
            if player.gui.screen[FRAME] then M.open_shop(player) end  -- 刷新余额
        end
    end
end

return M
