-- 左上角 HUD：跃迁轮次按钮（点击=弹出玩法教程）+ 跃迁倒计时 + 角色面板。
local constants = require('scripts.constants')
local util = require('scripts.util')
local classes = require('scripts.classes')

local M = {}

local CLASS_MAX_LEVEL = constants.MAX_LEVEL   -- 职业满级基准=最大等级（单一来源 constants.MAX_LEVEL）

-- 玩家人物等级 = floor(√在线分钟)（与 respawn_gifts.coin_reward 同公式）。用于按等级显隐 HUD 元素。
local function player_level(player)
    local st = storage.player_stats and storage.player_stats[player.name]
    return math.floor(math.sqrt((st and st.online_minutes) or 0))
end
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
    local lvl = player_level(player)   -- 用于按等级显隐（星星按钮仅 star_unlock_level 级以上显示）

    -- HUD 按钮【放最前】：位置固定，不会被后面变长的世界标签挤动。点击由 tick.on_gui_click 路由。
    --   玩法&指令（弹窗）  |间隔|  角色面板 / 跃迁(投同意✓) / 停留(投反对✗)。
    for _, b in ipairs({
        -- 信息组：玩法（最左）+ 功能菜单。玩法按钮 tooltip【就是其正文】，与点开的窗口完全同一段 description。
        -- 每个按钮的 tooltip = 标题 + 它打开窗口顶部的同一段简介（共用 *-help，两处一致）。
        {name = 'wn_btn_gameplay', sprite = 'virtual-signal/signal-info',  tip = {'description', storage.warp_initial_minutes or 10, storage.platform_lifetime or 10}},
        {name = 'wn_btn_actions',  sprite = 'item/blueprint-book',  tip = {'', {'wn.btn-actions-title'}, '\n', {'wn.actions-help'}}},
        {spacer = true},
        -- 个人组：科技瓶经验 / 统计 / 职业 / 星星。
        {name = 'wn_btn_stats',    sprite = 'entity/character',                 tip = {'', {'wn.btn-stats-title'}, '\n', {'wn.stats-btn-tip'}}},
        {name = 'wn_btn_class',    sprite = 'virtual-signal/signal-mining',     tip = {'', {'wn.btn-class-title'}, '\n', {'wn.class-help'}}},
        {name = 'wn_btn_star',     sprite = 'virtual-signal/signal-star',       tip = {'', {'wn.btn-star-title'}, '\n', {'wn.star-help'}}, min_level = storage.star_unlock_level or 0},
        {spacer = true},
        -- 跃迁规则组：跃迁投票 / 停留投票（放一起，都是对"是否提前跃迁"投票）。
        {name = 'wn_btn_warp',     sprite = 'virtual-signal/signal-trash-bin',  tip = {'wn.btn-warp-tip'},  min_level = storage.vote_unlock_level or 10},
        {name = 'wn_btn_stay',     sprite = 'virtual-signal/signal-white-flag', tip = {'wn.btn-stay-tip'}, min_level = storage.vote_unlock_level or 10},
    }) do
        if b.spacer then
            player.gui.top.add{type = 'empty-widget'}.style.width = 12   -- 玩法 与 操作组 之间的间隔
        else
            -- 等级不足 → 按钮【置灰不可点】，tooltip 提示"X 级解锁"（不隐藏，让玩家看到目标）。
            local locked = b.min_level and lvl < b.min_level
            local btn = player.gui.top.add{type = 'sprite-button', name = b.name, sprite = b.sprite,
                tooltip = locked and {'wn.locked-level', b.min_level} or b.tip}
            btn.enabled = not locked
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
        tooltip = {'description', storage.warp_initial_minutes or 10, storage.platform_lifetime or 10},
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
function M.show_popup(player, title, lines, buttons, buttons_at_bottom, bottom_buttons, columns)
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
    local function add_buttons(list, cols)
        if not list then return end
        -- cols>1 时按钮放进 table 多列平铺；label 始终单独成行（加到 pane，不进网格）。
        local box = (cols and cols > 1) and pane.add{type = 'table', column_count = cols} or pane
        for _, b in ipairs(list) do
            if b.label then
                local l = pane.add{type = 'label', caption = b.caption}
                l.style.font = 'default-bold'
                l.style.top_margin = 6
            elseif b.newrow then
                -- 空职业/分隔占位：加一条分隔线 + 开新 table，后面按钮另起一组。单列也画线（如在线玩家列表"查看自己"与其他人之间）。
                pane.add{type = 'line'}
                box = (cols and cols > 1) and pane.add{type = 'table', column_count = cols} or pane
            else
                -- enabled=false → 按钮置灰且不触发 on_gui_click（如本轮关闭的星球）。tooltip 说明为何不可点。
                local btn = box.add{type = 'button', name = b.name, caption = b.caption, tags = b.tags,
                        enabled = b.enabled, tooltip = b.tooltip}
                if cols and cols > 1 then btn.style.width = 220 end   -- 网格按钮统一【固定】宽(非最小宽)：英文长短不一也强制对齐、加宽防截断
            end
        end
    end
    if not buttons_at_bottom then add_buttons(buttons, columns) end
    for _, line in ipairs(lines) do
        pane.add{type = 'label', caption = line}.style.single_line = false
    end
    if buttons_at_bottom then add_buttons(buttons, columns) end
    add_buttons(bottom_buttons)   -- 永远在文本行之后（不分列）
    frame.force_auto_center()
    player.opened = frame   -- Esc/E 关闭

    return frame
end

-- 弹出【简介】：与玩法窗口、倒计时标签悬停【共用同一段 description】（含场景背景 + 核心玩法）。
function M.show_intro(player)
    M.show_popup(player, {'wn.intro-title'},
        {{'description', storage.warp_initial_minutes or 10, storage.platform_lifetime or 10}})
end

-- 弹出【游戏玩法】（HUD 第一个按钮）：纯玩法说明文字。功能按钮在 show_actions（第二个按钮）。
function M.show_tutorial(player)
    M.show_popup(player, {'wn.tutorial-title'}, {
        {'description', storage.warp_initial_minutes or 10, storage.platform_lifetime or 10},
    })
end

-- 弹出【功能菜单】（HUD 第二个按钮）。科技瓶经验/跃迁/停留/预览 已各有独立入口，这里不再重复。
--   保留：上局排行 / 自杀；再按【前往星球】【出生星球】两组分块。
function M.show_actions(player)
    if not player then return end
    -- 真按钮：name 复用 HUD 同名按钮 或 wn_act_* / tags，点击经 tick.on_gui_click 路由到 commands.* 。
    local buttons = {
        {name = 'wn_act_preview',  caption = {'wn.act-preview'},  tooltip = {'wn.act-preview-tip'}},
        {name = 'wn_act_lastrank', caption = {'wn.act-lastrank'}, tooltip = {'wn.act-lastrank-tip'}},
        {name = 'wn_act_suicide',  caption = {'wn.act-suicide'},  tooltip = {'wn.act-suicide-tip'}},
    }
    -- 【前往星球】组：总开关 storage.travel_enabled 开启后 5 个星球全显示；本轮未开放的置灰不可点。
    if storage.travel_enabled then
        buttons[#buttons + 1] = {label = true, caption = {'wn.actions-travel-group'}}
        local open, tc = storage.travel_open or {}, storage.travel_chance or {}
        for _, p in ipairs({'nauvis', 'vulcanus', 'gleba', 'fulgora', 'aquilo'}) do
            buttons[#buttons + 1] = {name = 'wn_act_travel_' .. p, caption = {'wn.act-travel', p}, tags = {wn_travel = p},
                enabled = open[p] or false,
                tooltip = open[p] and {'wn.act-travel-tip'} or {'wn.travel-closed', math.floor((tc[p] or 0.5) * 100)}}
        end
    end
    -- 【出生星球】组：设定下次跃迁复活 + 领起手装备的星球。不传送、全星球可选、当前选中标 ✓。
    buttons[#buttons + 1] = {label = true, caption = {'wn.actions-home-group'}}
    local home = (storage.respawn_surface or {})[player.name] or 'nauvis'
    for _, p in ipairs({'nauvis', 'vulcanus', 'gleba', 'fulgora', 'aquilo'}) do
        buttons[#buttons + 1] = {name = 'wn_act_home_' .. p,
            caption = {p == home and 'wn.act-home-cur' or 'wn.act-home', p}, tags = {wn_home = p}, tooltip = {'wn.act-home-tip'}}
    end
    -- 顶部放与按钮 tooltip 同一段简介（buttons_at_bottom=true → 说明在上、操作按钮在下）。
    M.show_popup(player, {'wn.actions-title'}, {{'wn.actions-help'}, ''}, buttons, true)
end

-- 弹出【职业】窗口（HUD 独立按钮）：每个职业一个按钮，当前职业标 ✓、悬停说明专精瓶。
-- 点击经 tick.on_gui_click（tags.wn_class）路由到 commands.set_class。同时只能一种职业。
function M.show_classes(player)
    if not player then return end
    local cur = classes.selected_key(player)
    -- 分区标题中文 → locale key 映射（英文环境走 wn.class-section-*，中文 fallback def.section）。
    local SECTION_KEY = {['基础生产'] = 'basic', ['能源 · 物流'] = 'energy', ['战斗'] = 'combat',
                         ['装备护甲'] = 'gear', ['农牧'] = 'farm', ['星球专精'] = 'planet'}
    local buttons = {}
    for _, def in ipairs(classes.all()) do
        if not def.key or def.key == '' then
            if def.section then
                local skey = SECTION_KEY[def.section] or def.section
                buttons[#buttons + 1] = {label = true, caption = classes.text_loc('wn.class-section-' .. skey, nil, def.section)}   -- 分区标题：locale 优先(英文友好)，fallback def.section 中文
            end
            buttons[#buttons + 1] = {newrow = true}   -- 空职业（无 key 的 {}/{section=} 占位）= UI 换行/分组分隔
        else
        -- 职业名三层兜底：locale 词条 wn.class-name-<key>(英文友好) → 动态表 storage.class_names[key](/c 热改) → def.name(中文默认)。
        local name_loc = classes.text_loc('wn.class-name-' .. def.key, (storage.class_names or {})[def.key], def.name or def.key)
        -- tooltip：白送(starter)每物品一行"+N [img]"；奖励(rewards)每条一行"每 a 级 [瓶] b 个 [物品]"。两者都换行。
        -- 按钮图标 starter_img 取第一件白送物品；a:b 为 满级:满级总个数 的最简比(gcd 约分)。
        local starter_img = (def.starter and def.starter[1]) and ('[img=item/' .. def.starter[1].item .. ']') or ''
        local tip = {''}
        for _, s in ipairs(def.starter or {}) do
            local proto = prototypes.item[s.item]
            -- 白送总个数 = count 个，或 groups 组 × 堆叠（默认 1 组）。每条一行，只显示算好的总数。
            local total = s.count or (((proto and proto.stack_size) or 1) * (s.groups or 1))
            tip[#tip + 1] = {'wn.class-tip-head', total, '[img=item/' .. s.item .. ']'}
        end
        for _, r in ipairs(def.rewards or {}) do
            local proto = prototypes.item[r.item]
            local total = ((proto and proto.stack_size) or 1) * (r.groups or 1)   -- 达到 full 级时该物品最多拿多少个
            tip[#tip + 1] = {'wn.class-tip-reward',
                '[img=item/' .. r.pack .. ']',       -- 等级来源：哪种科技瓶
                def.full or CLASS_MAX_LEVEL,         -- 该职业满级线：此瓶练到这级即拿满
                total,                               -- 满时最多给多少个
                '[img=item/' .. r.item .. ']'}
        end
        -- 解锁条件（需全部满足）：附在 tooltip 末尾，显示 需求瓶/等级 + 当前等级。
        for _, u in ipairs(def.unlock or {}) do
            tip[#tip + 1] = {'wn.class-tip-unlock', '[img=item/' .. u.pack .. ']', u.level, classes.pack_level(player, u.pack)}
        end
        -- 未解锁 → 按钮置灰(enabled=false，不可点)，但 tooltip 仍显示解锁条件。
        buttons[#buttons + 1] = {name = 'wn_act_class_' .. def.key,
            caption = {def.key == cur and 'wn.class-cur' or 'wn.class-pick', name_loc, starter_img},
            tooltip = tip, enabled = classes.unlocked(player, def), tags = {wn_class = def.key}}
        end
    end
    -- 顶部自带说明（buttons_at_bottom=true → 说明在上、职业按钮在下）。
    M.show_popup(player, {'wn.class-title'}, {{'wn.class-help'}}, buttons, true, nil, 3)   -- 职业按钮 3 列平铺
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
