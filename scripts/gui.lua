-- 左上角 HUD：跃迁轮次按钮（点击=自杀回母星脱困）+ 角色面板。
local constants = require('scripts.constants')
local passives = require('scripts.passives')
local respawn_gifts = require('scripts.respawn_gifts')
local util = require('scripts.util')

local M = {}

-- 构建能力面板 tooltip。先收集所有行，再折叠成嵌套 localised string：
-- 单层 localised string 最多 ~20 个参数，本面板（12 种瓶各 1 行）会超，
-- 故每攒满 18 个就把整张表嵌进 {'', old} 再继续，突破单层上限。
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

-- 距下次跃迁剩余（整数小时, 整数分钟）；与 tick.lua 告警同一公式。
function M.warp_hm()
    local last = game.tick - (storage.run_start_tick or game.tick)
    return util.hm((storage.warp_hours or 1) * constants.hour_to_tick - last)
end

-- 刷新所有在线玩家顶部的跃迁倒计时标签（由 tick.lua 每分钟调用）。
function M.refresh_countdown()
    local h, m = M.warp_hm()
    for _, player in pairs(game.connected_players) do
        local el = player.gui.top.warp_countdown
        if el and el.valid then el.caption = {'wn.warp-countdown', h, m} end
    end
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

    -- 跃迁倒计时（每分钟由 tick.lua 刷新）
    local cd = player.gui.top.add {
        type = 'label',
        name = 'warp_countdown',
        caption = {'wn.warp-countdown', M.warp_hm()}
    }
    cd.style.font = 'heading-1'
    cd.style.font_color = {255, 210, 120}
    cd.style.left_margin = 10
    cd.style.top_margin = 6

    -- 星系词条已删除：每局世界的矿物/昼夜/天色等不摆在 UI 上，让玩家自己探索发现。

    -- 被动技能面板（基于自己的累计经验）
    player.gui.top.add {
        type = 'sprite-button',
        sprite = 'entity/character',
        name = 'skills',
        tooltip = build_skills_tooltip(player)
    }
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

-- ── 临时弹窗 ────────────────────────────────────────────────────────────────
-- 把信息类指令(教程/查看/倒计时/预览)的输出从聊天框搬到屏幕中央的独立窗口：不刷屏、可关闭。
-- 关闭方式：点右上 × 或按 Esc/E（on_gui_closed）。重复打开自动替换旧窗，不堆叠。
local POPUP_NAME = 'wn_popup'
M.POPUP_NAME = POPUP_NAME
M.POPUP_CLOSE_NAME = POPUP_NAME .. '_close'

-- title：localised string 或纯文本；lines：数组，每项一行（localised string 或纯文本）。
function M.show_popup(player, title, lines)
    if not (player and player.valid) then return end
    local screen = player.gui.screen
    if screen[POPUP_NAME] then screen[POPUP_NAME].destroy() end   -- 重开即替换

    local frame = screen.add{type = 'frame', name = POPUP_NAME, direction = 'vertical'}
    -- 标题栏：标题 + 可拖动空白 + 关闭按钮
    local bar = frame.add{type = 'flow', direction = 'horizontal'}
    bar.drag_target = frame
    bar.add{type = 'label', caption = title, style = 'frame_title', ignored_by_interaction = true}
    local drag = bar.add{type = 'empty-widget', style = 'draggable_space_header', ignored_by_interaction = true}
    drag.style.horizontally_stretchable = true
    drag.style.height = 24
    drag.style.right_margin = 4
    bar.add{type = 'sprite-button', name = M.POPUP_CLOSE_NAME, sprite = 'utility/close',
            style = 'frame_action_button', tooltip = {'gui.close'}}
    -- 内容：滚动区，每行一个可换行 label
    local pane = frame.add{type = 'scroll-pane', direction = 'vertical'}
    pane.style.maximal_height = 460
    pane.style.minimal_width = 380
    for _, line in ipairs(lines) do
        pane.add{type = 'label', caption = line}.style.single_line = false
    end
    frame.force_auto_center()
    player.opened = frame   -- Esc/E 关闭

    return frame
end

-- 弹出玩法教程：文案里的【起步分钟】【飞船寿命】由 storage 实时填入。
-- HUD 左上 run 按钮(tick.lua) 与 /tutorial 命令(commands.lua) 共用，避免漏传参数。
function M.show_tutorial(player)
    M.show_popup(player, {'wn.tutorial-title'}, {{'wn.tutorial',
        storage.warp_initial_minutes or 10,   -- __1__ 跃迁倒计时起步分钟
        storage.platform_lifetime or 10}})    -- __2__ 飞船最多保留的跃迁次数
end

function M.close_popup(player)
    if player and player.valid then
        local f = player.gui.screen[POPUP_NAME]
        if f and f.valid then f.destroy() end
    end
end

-- "打印汇集器"：仿 player/game 的 .print(msg)，把行收集进 sink.lines，交给 show_popup。
-- 让原本 viewer.print 多行的函数(如 players.print_inspection)无需改写即可输出到弹窗。
function M.popup_sink()
    local sink = {lines = {}}
    function sink.print(msg) sink.lines[#sink.lines + 1] = msg end
    return sink
end

return M
