-- 左上角 HUD：跃迁轮次 + 星系词条 + 经验加成 + 在线名册 + 管理员按钮。
local passives = require('scripts.passives')

local M = {}

-- 构建能力面板 tooltip：标题 + 每个 ability 一行。
-- 已实装：locale 接收 (经验明细, 当前数值)
-- 未实装：用 ability-todo 模板，接收 (瓶子 prototype 名, 经验)
local function build_skills_tooltip(player)
    local lines = {'', {'wn.skills-title'}}
    for _, ability in ipairs(passives.abilities) do
        if ability.apply then
            local breakdown = passives.build_exp_breakdown(ability.packs, player.index)
            local factor = ability.curve(ability.packs, player.index)
            table.insert(lines, {ability.locale, breakdown, ability.fmt(factor)})
        else
            local pack = ability.packs[1]
            local exp = passives.exp_total_for_pack(player.index, pack)
            table.insert(lines, {'wn.ability-todo', pack, exp})
        end
    end
    return lines
end

-- 构建在线名册 tooltip：标题 + 每位在线玩家一行（玩家名 / 总经验）。
local function build_roster_tooltip()
    local lines = {'', {'wn.roster-title'}}
    for _, player in pairs(game.connected_players) do
        local total = 0
        local exp = storage.science_exp and storage.science_exp[player.index]
        if exp then
            for _, val in pairs(exp) do total = total + val end
        end
        table.insert(lines, {'wn.roster-entry', player.name, total})
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

    -- 在线玩家经验面板
    player.gui.top.add {
        type = 'sprite-button',
        sprite = 'virtual-signal/signal-heart',
        name = 'roster',
        tooltip = build_roster_tooltip()
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
