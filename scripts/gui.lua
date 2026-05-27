-- 左上角 HUD：跃迁轮次 + 星系词条 + 经验加成 + 在线名册 + 管理员按钮。
local constants = require('scripts.constants')
local passives = require('scripts.passives')
local currency = require('scripts.currency')

local M = {}

-- 构建能力面板 tooltip。先收集所有行，再折叠成嵌套 localised string：
-- 单层 localised string 最多 ~20 个参数，本面板（能力 + 12 瓶进度 + 金币）会超，
-- 故每攒满 18 个就把整张表嵌进 {'', old} 再继续，沿用 util.try_add_trait 的手法。
local function build_skills_tooltip(player)
    local parts = {{'wn.skills-title'}}

    -- 第一段：所有已实装的基础能力（按玩家行为统计计算）
    for _, ability in ipairs(passives.abilities) do
        if ability.apply then
            local val = passives.get_stat(player.index, ability.stat)
            parts[#parts + 1] = {ability.locale, val, ability.fmt(ability.curve(val))}
        end
    end

    -- 第二段：每个科技瓶的货币进度（等级 + 当前经验/升级经验，奖励正比于等级）
    parts[#parts + 1] = '\n'
    for _, pack in ipairs(constants.science_packs) do
        local p = currency.progress_for_exp(passives.exp_total_for_pack(player.index, pack))
        if p.need > 0 then
            parts[#parts + 1] = {'wn.ability-reward', pack, p.level, p.into, p.need, p.quality}
        else
            parts[#parts + 1] = {'wn.ability-reward-max', pack, p.level}
        end
    end

    -- 第三段：在线行为 → 品质金币（装备市场货币）
    parts[#parts + 1] = '\n'
    for _, src in ipairs(constants.coin_sources) do
        local stat = passives.get_stat(player.index, src.stat)
        parts[#parts + 1] = {'wn.ability-coin', src.quality, {src.label}, stat, currency.coin_amount(stat)}
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
