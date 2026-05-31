-- 左上角 HUD：跃迁轮次按钮（点击=弹出玩法教程）+ 跃迁倒计时 + 角色面板。
local constants = require('scripts.constants')
local util = require('scripts.util')
local classes = require('scripts.classes')

local M = {}

local CLASS_MAX_LEVEL = 10000   -- 职业后者满级基准（与 respawn_gifts.MAX_LEVEL 一致）
local function gcd(a, b) while b ~= 0 do a, b = b, a % b end return a end

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
        {name = 'wn_btn_actions',  sprite = 'item/blueprint-book',  tip = {'wn.btn-actions-tip'}},
        -- {spacer = true},
        {name = 'wn_btn_skills',          sprite = 'entity/character',            tip = {'wn.skills-btn-tip'}},
        {name = 'wn_btn_stats',    sprite = 'item/exoskeleton-equipment',       tip = {'wn.btn-stats-tip'}},
        {name = 'wn_btn_class',    sprite = 'virtual-signal/signal-science-pack', tip = {'wn.btn-class-tip'}},
        {name = 'wn_btn_star',     sprite = 'virtual-signal/signal-star',       tip = {'wn.btn-star-tip'}},
        {name = 'wn_btn_warp',     sprite = 'virtual-signal/signal-trash-bin',  tip = {'wn.btn-warp-tip'}},
        {name = 'wn_btn_stay',     sprite = 'virtual-signal/signal-white-flag', tip = {'wn.btn-stay-tip'}},
    }) do
        if b.spacer then
            player.gui.top.add{type = 'empty-widget'}.style.width = 12   -- 玩法 与 操作组 之间的间隔
        else
            player.gui.top.add{type = 'sprite-button', name = b.name, sprite = b.sprite, tooltip = b.tip}
        end
    end

    -- 管理员专属【红按钮】：仅管理员可见可点（普通玩家不创建 → 看不到）。点击经 tick.on_gui_click 路由到 commands.admin_*。
    if player.admin then
        player.gui.top.add{type = 'empty-widget'}.style.width = 12
        for _, b in ipairs({
            {name = 'wn_admin_gen',     caption = 'GEN',   tip = {'wn.admin-gen-tip'}},
            {name = 'wn_admin_diff',    caption = 'DIFF',  tip = {'wn.admin-diff-tip'}},
        }) do
            player.gui.top.add{type = 'button', name = b.name, caption = b.caption, tooltip = b.tip, style = 'red_button'}
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
-- buttons（可选）：数组，每项 {name=, caption=, tags=}，渲染成滚动区里的可点击按钮（查看他人/返回/玩家名/跃迁停留等）。
--   点击由 tick.on_gui_click 按 name 路由，复用 HUD 同名按钮的处理（skills/wn_btn_warp/wn_btn_stay 等）。
-- buttons_at_bottom：true 时 buttons 放在文本行【之后】（用于教程末尾的"其它按钮"），否则放最前（用于面板导航）。
-- bottom_buttons（可选）：与 buttons_at_bottom 无关，永远渲染在【所有文本行之后】。用于"顶部导航按钮 + 底部操作按钮"两段式布局
--   （如角色面板：顶部"查看他人能力"，底部"领取星星"）。
function M.show_popup(player, title, lines, buttons, buttons_at_bottom, bottom_buttons)
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
    -- 内容：滚动区。按钮可放在文本之前（默认）或之后（buttons_at_bottom）。
    local pane = frame.add{type = 'scroll-pane', direction = 'vertical'}
    pane.style.maximal_height = 460
    pane.style.minimal_width = 380
    local function add_buttons(list)
        if not list then return end
        for _, b in ipairs(list) do
            -- enabled=false → 按钮置灰且不触发 on_gui_click（如本轮关闭的星球）。tooltip 说明为何不可点。
            pane.add{type = 'button', name = b.name, caption = b.caption, tags = b.tags,
                     enabled = b.enabled, tooltip = b.tooltip}
        end
    end
    if not buttons_at_bottom then add_buttons(buttons) end
    for _, line in ipairs(lines) do
        pane.add{type = 'label', caption = line}.style.single_line = false
    end
    if buttons_at_bottom then add_buttons(buttons) end
    add_buttons(bottom_buttons)   -- 永远在文本行之后
    frame.force_auto_center()
    player.opened = frame   -- Esc/E 关闭

    return frame
end

-- 弹出【简介】：本场景的故事背景（即左上 run 标签的悬停内容，搬成可读弹窗）。
function M.show_intro(player)
    M.show_popup(player, {'wn.intro-title'}, {{'description', ''}})
end

-- 弹出【游戏玩法】（HUD 第一个按钮）：纯玩法说明文字。功能按钮在 show_actions（第二个按钮）。
function M.show_tutorial(player)
    M.show_popup(player, {'wn.tutorial-title'}, {
        {'wn.guide-gameplay', storage.warp_initial_minutes or 10, storage.platform_lifetime or 10},
    })
end

-- 弹出【功能按钮】（HUD 第二个按钮）：把原先挤在教程弹窗末尾的一堆操作按钮单独成窗。
--   角色面板 / 跃迁(✓) / 停留(✗) / 预览 / 上局排行 / 自杀脱困 + 前往星球（按本轮开放置灰）+ 起始星球（当前标 ✓）。
function M.show_actions(player)
    if not player then return end
    -- 真按钮：name 复用 HUD 同名按钮 或 wn_act_* / tags，点击经 tick.on_gui_click 路由到 commands.* 。
    local buttons = {
        {name = 'wn_btn_skills',   caption = {'wn.act-panel'}},
        {name = 'wn_btn_warp',     caption = {'wn.act-warp'}},
        {name = 'wn_btn_stay',     caption = {'wn.act-stay'}},
        {name = 'wn_act_preview',  caption = {'wn.act-preview'}},
        {name = 'wn_act_lastrank', caption = {'wn.act-lastrank'}},
        {name = 'wn_act_suicide',  caption = {'wn.act-suicide'}},
    }
    -- "前往星球"按钮：总开关 storage.travel_enabled（默认关）开启后，5 个星球【全部显示】；本轮未开放(storage.travel_open[星球]=false)的【置灰】不可点。
    if storage.travel_enabled then
        local open, tc = storage.travel_open or {}, storage.travel_chance or {}
        for _, p in ipairs({'nauvis', 'vulcanus', 'gleba', 'fulgora', 'aquilo'}) do
            buttons[#buttons + 1] = {name = 'wn_act_travel_' .. p, caption = {'wn.act-travel', p}, tags = {wn_travel = p},
                enabled = open[p] or false,
                tooltip = (not open[p]) and {'wn.travel-closed', math.floor((tc[p] or 0.5) * 100)} or nil}   -- 传该星真实开放概率%
        end
    end
    -- "起始星球"按钮：设定【下次跃迁复活+领起手装备】的星球（即 storage.respawn_surface[玩家名]）。不传送、全星球可选、当前选中标 ✓。
    local home = (storage.respawn_surface or {})[player.name] or 'nauvis'
    for _, p in ipairs({'nauvis', 'vulcanus', 'gleba', 'fulgora', 'aquilo'}) do
        buttons[#buttons + 1] = {name = 'wn_act_home_' .. p,
            caption = {p == home and 'wn.act-home-cur' or 'wn.act-home', p}, tags = {wn_home = p}}
    end
    M.show_popup(player, {'wn.actions-title'}, {}, buttons)
end

-- 弹出【职业】窗口（HUD 独立按钮）：每个职业一个按钮，当前职业标 ✓、悬停说明专精瓶。
-- 点击经 tick.on_gui_click（tags.wn_class）路由到 commands.set_class。同时只能一种职业。
function M.show_classes(player)
    if not player then return end
    local cur = classes.selected_key(player)
    local buttons = {}
    for _, def in ipairs(classes.list) do
        local name_loc = {'wn.class-name-' .. def.key}
        local starter_img = def.starter and ('[img=item/' .. def.starter .. ']') or ''
        -- tooltip 用空键拼接：首行"无条件送 1 组 X"，再每条后者一行"[瓶] 每 a 级送 b 个 [物品]"。
        -- a:b = 满级:满级总个数(堆叠×groups) 的【最简比】(gcd 约分)，并标明是哪种瓶的等级。
        local tip = {'', {'wn.class-tip-head', starter_img}}
        for _, r in ipairs(def.rewards or {}) do
            local proto = prototypes.item[r.item]
            local total = ((proto and proto.stack_size) or 1) * (r.groups or 1)   -- 满级该发的总个数
            local g = gcd(CLASS_MAX_LEVEL, total)
            tip[#tip + 1] = {'wn.class-tip-reward',
                '[img=item/' .. r.pack .. ']',      -- 等级来源：哪种科技瓶
                math.floor(CLASS_MAX_LEVEL / g),    -- 每 a 级
                math.floor(total / g),              -- 送 b 个
                '[img=item/' .. r.item .. ']'}
        end
        -- 解锁条件（需全部满足）：附在 tooltip 末尾，显示 需求瓶/等级 + 当前等级。
        for _, u in ipairs(def.unlock or {}) do
            tip[#tip + 1] = {'wn.class-tip-unlock', '[img=item/' .. u.pack .. ']', u.level, classes.pack_level(player, u.pack)}
        end
        -- 未解锁 → 按钮置灰(enabled=false，不可点)，但 tooltip 仍显示解锁条件。
        buttons[#buttons + 1] = {name = 'wn_act_class_' .. def.key,
            caption = {def.key == cur and 'wn.class-cur' or 'wn.class-pick', name_loc},
            tooltip = tip, enabled = classes.unlocked(player, def), tags = {wn_class = def.key}}
    end
    -- 顶部自带说明（buttons_at_bottom=true → 说明在上、职业按钮在下）。
    M.show_popup(player, {'wn.class-title'}, {{'wn.class-help'}}, buttons, true)
end

function M.close_popup(player)
    if player and player.valid then
        local f = player.gui.screen[POPUP_NAME]
        if f and f.valid then f.destroy() end
    end
end

-- "打印汇集器"：仿 player/game 的 .print(msg)，把行收集进 sink.lines，交给 show_popup。
-- 让原本 viewer.print 多行的函数(如 players.print_exp / print_status)无需改写即可输出到弹窗。
function M.popup_sink()
    local sink = {lines = {}}
    function sink.print(msg) sink.lines[#sink.lines + 1] = msg end
    return sink
end

return M
