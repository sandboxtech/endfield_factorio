-- 左上角 HUD：跃迁轮次 + 星系词条 + 经验加成 + 在线名册 + 管理员按钮。
local passives = require('scripts.passives')
local respawn_gifts = require('scripts.respawn_gifts')

-- 未实装能力的 tooltip 物品列：按玩家当前该瓶经验对应的等级，
-- 把累计能拿到的物品展开成 "[item=foo]×N [item=bar]×M"。
-- exp=0 时所有物品显示 ×0；表里没东西则回退成瓶子图标。
local function todo_items_for(pack, player_index)
    local exp = passives.exp_total_for_pack(player_index, pack)
    local level = respawn_gifts.level_for(exp)
    local list = respawn_gifts.cumulative_items(pack, level)
    if #list == 0 then return '[item=' .. pack .. ']' end
    local parts = {}
    for _, it in ipairs(list) do
        table.insert(parts, '[item=' .. it.name .. ']×' .. it.count)
    end
    return table.concat(parts, ' ')
end

local M = {}

-- 构建能力面板 tooltip：标题 + 所有已实装能力 + 空行 + 所有瓶子的开局物品。
local function build_skills_tooltip(player)
    local lines = {'', {'wn.skills-title'}}
    -- 第一段：所有已实装的基础能力（按玩家行为统计计算）
    for _, ability in ipairs(passives.abilities) do
        if ability.apply then
            local val = passives.get_stat(player.index, ability.stat)
            local factor = ability.curve(val)
            table.insert(lines, {ability.locale, val, ability.fmt(factor)})
        end
    end
    -- 段间空行
    table.insert(lines, '\n')
    -- 第二段：每个科技瓶一行开局物品（仍由背包里的瓶子经验决定）
    local gift_packs = {
        'automation-science-pack', 'logistic-science-pack', 'chemical-science-pack',
        'military-science-pack', 'production-science-pack', 'utility-science-pack',
        'space-science-pack', 'metallurgic-science-pack', 'electromagnetic-science-pack',
        'agricultural-science-pack', 'cryogenic-science-pack', 'promethium-science-pack',
    }
    for _, pack in ipairs(gift_packs) do
        local exp = passives.exp_total_for_pack(player.index, pack)
        table.insert(lines, {'wn.ability-item', pack, exp, todo_items_for(pack, player.index)})
    end
    return lines
end

-- 渲染单个玩家的 HUD。
function M.player_gui(player)
    player.gui.top.clear()

    local intro = player.gui.top.add {
        type = 'sprite-button',
        caption = {'run', storage.run or 0},
        name = 'introduction',
        tooltip = {'description', ''}
    }
    intro.style.font = 'heading-1'
    intro.style.font_color = {222, 222, 222}
    intro.style.minimal_height = 38
    intro.style.maximal_height = 38
    intro.style.minimal_width = 288
    intro.style.padding = -2

    if not storage.traits then
        storage.traits = {''}
    end
    player.gui.top.add {
        type = 'sprite-button',
        sprite = 'space-location/solar-system-edge',
        name = 'traits',
        tooltip = {'', storage.traits, {'wn.traits-legend'}}
    }

    -- 被动技能面板（基于自己的累计经验）
    player.gui.top.add {
        type = 'sprite-button',
        sprite = 'virtual-signal/signal-science-pack',
        name = 'skills',
        tooltip = build_skills_tooltip(player)
    }

    if player.admin then
        player.gui.top.add {
            type = 'sprite-button',
            sprite = 'item/raw-fish',
            name = 'admin',
            tooltip = {'wn.admin-tooltip'}
        }
    end
end

-- 刷新所有玩家 HUD；离线玩家清空 GUI。
function M.players_gui()
    for _, player in pairs(game.players) do
        if player.connected then
            M.player_gui(player)
        else
            player.gui.top.clear()
        end
    end
end

return M
