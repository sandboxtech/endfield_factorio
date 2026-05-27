-- 左上角 HUD：跃迁轮次 + 星系词条 + 经验加成 + 在线名册 + 管理员按钮。
local constants = require('scripts.constants')
local passives = require('scripts.passives')
local respawn_gifts = require('scripts.respawn_gifts')

local M = {}

-- 构建能力面板 tooltip。先收集所有行，再折叠成嵌套 localised string：
-- 单层 localised string 最多 ~20 个参数，本面板（12 种瓶各 1 行）会超，
-- 故每攒满 18 个就把整张表嵌进 {'', old} 再继续，沿用 util.try_add_trait 的手法。
local function build_skills_tooltip(player)
    local parts = {{'wn.skills-title'}}

    -- 注意：角色技能（手搓/移动/挖矿/生命）和在线时长都是实时变化的，而 tooltip 在建面板时就固定、
    -- 不会刷新，显示会过时；故这里只显示"下次跃迁直接发的初始物资"，其余用 /inspect（每次现算）查看。

    -- 每种科技瓶：下次跃迁直接发的 2 种代表物资 × 数量（即使为 0 也列出，方便玩家知道带它有什么用）
    parts[#parts + 1] = '\n'
    for _, pack in ipairs(constants.science_packs) do
        local items = respawn_gifts.pack_gifts[pack]
        if items then
            local exp = passives.exp_total_for_pack(player.index, pack)
            local t = {}
            for _, item in ipairs(items) do
                t[#t + 1] = '[item=' .. item .. ']×' .. respawn_gifts.gift_count(exp, item)
            end
            parts[#parts + 1] = {'wn.ability-reward', pack, exp, table.concat(t, '  ')}
        end
    end

    -- 折叠：突破单层参数上限
    local lines = {''}
    for _, part in ipairs(parts) do
        if #lines >= 19 then lines = {'', lines} end
        lines[#lines + 1] = part
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

    -- 星系词条按钮已隐藏：每局世界的矿物/昼夜/天色等不再摆在 UI 上，让玩家自己探索发现。
    -- （storage.traits 仍在后台累积，便于以后需要时再展示。）

    -- 被动技能面板（基于自己的累计经验）
    player.gui.top.add {
        type = 'sprite-button',
        sprite = 'entity/character',
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
