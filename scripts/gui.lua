-- 左上角 HUD：跃迁轮次按钮（点击=弹出玩法教程）+ 跃迁倒计时 + 角色面板。
local constants = require('scripts.constants')
local util = require('scripts.util')

local M = {}

-- 距下次跃迁剩余（整数小时, 整数分钟）；与 tick.lua 告警同一公式。
function M.warp_hm()
    local last = game.tick - (storage.run_start_tick or game.tick)
    return util.hm((storage.warp_hours or 1) * constants.hour_to_tick - last)
end

-- 顶部合并标签的文案：「世界 N　[img]距跃迁 H 小时 M 分钟」。run 与 warp-countdown 已合并为单键 world-status。
function M.countdown_caption()
    local h, m = M.warp_hm()
    return {'wn.world-status', storage.run or 0, h, m}
end

-- 刷新所有在线玩家顶部的跃迁倒计时标签（由 tick.lua 每分钟调用）。
function M.refresh_countdown()
    local caption = M.countdown_caption()
    for _, player in pairs(game.connected_players) do
        local el = player.gui.top.warp_countdown
        if el and el.valid then el.caption = caption end
    end
end

-- 渲染单个玩家的 HUD。
function M.player_gui(player)
    player.gui.top.clear()

    -- HUD 按钮【放最前】：位置固定，不会被后面变长的世界标签挤动。点击由 tick.on_gui_click 路由。
    --   玩法&指令（弹窗）  |间隔|  角色面板 / 跃迁(投同意✓) / 停留(投反对✗)。
    for _, b in ipairs({
        {name = 'wn_btn_gameplay', sprite = 'virtual-signal/signal-info',  tip = {'wn.btn-gameplay-tip'}},
        -- {spacer = true},
        {name = 'skills',          sprite = 'entity/character',            tip = {'wn.skills-btn-tip'}},
        {name = 'wn_btn_warp',     sprite = 'virtual-signal/signal-trash-bin',  tip = {'wn.btn-warp-tip'}},
        {name = 'wn_btn_stay',     sprite = 'virtual-signal/signal-white-flag', tip = {'wn.btn-stay-tip'}},
    }) do
        if b.spacer then
            player.gui.top.add{type = 'empty-widget'}.style.width = 12   -- 玩法 与 操作组 之间的间隔
        else
            player.gui.top.add{type = 'sprite-button', name = b.name, sprite = b.sprite, tooltip = b.tip}
        end
    end

    -- 世界轮次 + 跃迁倒计时合并标签【放最后】：随轮次/时间变长，放末尾才不挤动前面的按钮。
    -- 用 button（label 不触发 on_gui_click）：悬停显示简介，点击弹出简介窗口（tick.on_gui_click → show_intro）。
    -- 倒计时每分钟由 refresh_countdown 刷新 caption。
    local cd = player.gui.top.add {
        type = 'button',
        name = 'warp_countdown',
        caption = M.countdown_caption(),
        tooltip = {'description', ''},
        style = 'transparent_button',   -- 内置全透明 button 样式：外观如 label，但可点击（label 不触发 on_gui_click）
    }
    cd.style.font = 'heading-1'
    cd.style.font_color = {255, 210, 120}
    cd.style.left_margin = 10
    cd.style.top_margin = 6
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
-- buttons（可选）：数组，每项 {name=, caption=, tags=}，渲染成滚动区顶部的可点击按钮（用于"查看他人/返回/玩家列表"）。
function M.show_popup(player, title, lines, buttons)
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
    -- 内容：滚动区。顶部先放可选按钮（查看他人/返回/玩家名），再放文本行。
    local pane = frame.add{type = 'scroll-pane', direction = 'vertical'}
    pane.style.maximal_height = 460
    pane.style.minimal_width = 380
    if buttons then
        for _, b in ipairs(buttons) do
            pane.add{type = 'button', name = b.name, caption = b.caption, tags = b.tags}
        end
    end
    for _, line in ipairs(lines) do
        pane.add{type = 'label', caption = line}.style.single_line = false
    end
    frame.force_auto_center()
    player.opened = frame   -- Esc/E 关闭

    return frame
end

-- 弹出【简介】：本场景的故事背景（即左上 run 标签的悬停内容，搬成可读弹窗）。
function M.show_intro(player)
    M.show_popup(player, {'wn.intro-title'}, {{'description', ''}})
end

-- 弹出【游戏玩法 & 指令】（玩法与指令两个按钮已合并为一个弹窗）：
--   玩法机制段（参数：起步分钟/飞船寿命由 storage 实时填入）+ 控制台指令段；会员/管理员再追加会员指令段。
function M.show_tutorial(player)
    local lines = {
        {'wn.guide-gameplay', storage.warp_initial_minutes or 10, storage.platform_lifetime or 10},
        '',
        {'wn.guide-commands'},
    }
    if player and (player.admin or (storage.members and storage.members[player.name])) then
        lines[#lines + 1] = {'wn.tutorial-member'}
    end
    M.show_popup(player, {'wn.tutorial-title'}, lines)
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
