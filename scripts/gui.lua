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
    local lvl = player_level(player)   -- 供按钮 min_level 等级门槛判断（目前无按钮设 min_level，保留机制备用）

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
        {name = 'wn_btn_star',     sprite = 'virtual-signal/signal-star',       tip = {'', {'wn.btn-star-title'}, '\n', {'wn.star-help'}}},
        -- 跃迁/停留投票 + 花星星延长 已移入【星星窗口】（见 commands.show_star），HUD 不再单独放这些按钮。
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
-- 把信息类指令(教程/查看/倒计时/荣誉榜等)的输出从聊天框搬到屏幕中央的独立窗口：不刷屏、可关闭。
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
-- min_width（可选）：滚动区最小宽度，默认 380。宽内容窗口（/gen 生成摘要）传更大值避免逐行折行。
function M.show_popup(player, title, lines, buttons, buttons_at_bottom, bottom_buttons, columns, min_width)
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
    -- 高度上限随屏幕自适应：屏幕逻辑高度(物理/缩放) 减标题栏+边距，下限保底 460。长内容(职业面板)更高，短内容仍自适应。
    pane.style.maximal_height = math.max(460, math.floor(player.display_resolution.height / player.display_scale) - 200)
    pane.style.minimal_width = min_width or 380
    local function add_buttons(list, cols)
        if not list then return end
        -- cols>1 时按钮放进 table 多列平铺；label 始终单独成行（加到 pane，不进网格）。
        local box = (cols and cols > 1) and pane.add{type = 'table', column_count = cols} or pane
        for _, b in ipairs(list) do
            if b.label then
                local l = pane.add{type = 'label', caption = b.caption}
                if not b.plain then l.style.font = 'default-bold' end   -- plain=true：数据行不加粗（区内文本用）
                l.style.top_margin = b.top_pad or 16   -- 默认 16=区/组之间换行；top_pad 小=区内紧凑
            elseif b.newrow then
                -- 空职业/分隔占位：加一条分隔线 + 开新 table，后面按钮另起一组。单列也画线（如在线玩家列表"查看自己"与其他人之间）。
                pane.add{type = 'line'}
                box = (cols and cols > 1) and pane.add{type = 'table', column_count = cols} or pane
            else
                -- enabled=false → 按钮置灰且不触发 on_gui_click（如本轮关闭的星球）。tooltip 说明为何不可点。
                local btn = box.add{type = 'button', name = b.name, caption = b.caption, tags = b.tags,
                        enabled = b.enabled, tooltip = b.tooltip}
                if b.min_width then
                    btn.style.minimal_width = b.min_width                 -- 【最小宽】（可随内容/列宽伸展）：玩家列表用，像职业但允许加宽
                    btn.style.horizontally_stretchable = true
                    btn.style.horizontal_align = 'left'   -- 列表按钮文字左对齐（图标/名字逐行对齐，好扫读）
                    btn.style.left_padding = 12           -- 左侧留白，别贴着按钮边
                elseif cols and cols > 1 then
                    btn.style.width = b.width or 220   -- 网格按钮统一【固定】宽(非最小宽)：英文长短不一也强制对齐、加宽防截断；b.width 可按钮级覆盖（职业 6 列用窄按钮）
                    btn.style.horizontal_align = 'left'   -- 网格按钮（职业/前往星球等）同样左对齐
                    btn.style.left_padding = 12           -- 左侧留白，别贴着按钮边
                end
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

-- 弹出【功能菜单】（HUD 第二个按钮）。科技瓶经验/跃迁/停留 已各有独立入口，这里不再重复。
--   保留：上局排行 / 自杀；再按【前往星球】【出生星球】两组分块。
function M.show_actions(player)
    if not player then return end
    -- 真按钮：name 复用 HUD 同名按钮 或 wn_act_* / tags，点击经 tick.on_gui_click 路由到 commands.* 。
    local buttons = {}
    if storage.hall_of_fame_enabled ~= false then   -- 荣誉榜可选（storage 开关，关=隐藏按钮、reset 也停止记录）
        buttons[#buttons + 1] = {name = 'wn_act_hof', caption = {'wn.act-hof'}, tooltip = {'wn.act-hof-tip'}}
    end
    buttons[#buttons + 1] = {name = 'wn_act_lastrank', caption = {'wn.act-lastrank'}, tooltip = {'wn.act-lastrank-tip'}}
    buttons[#buttons + 1] = {name = 'wn_act_serverstats', caption = {'wn.act-serverstats'}, tooltip = {'wn.act-serverstats-tip'}}
    buttons[#buttons + 1] = {name = 'wn_act_suicide',  caption = {'wn.act-suicide'},  tooltip = {'wn.act-suicide-tip'}}
    -- 【前往星球】组：总开关 storage.travel_enabled 开启后 5 个星球全显示；本轮未开放的置灰不可点。
    if storage.travel_enabled then
        buttons[#buttons + 1] = {label = true, caption = {'wn.actions-travel-group'}}
        local open, tc = storage.travel_open or {}, storage.travel_chance or {}
        for _, p in ipairs(constants.PLANETS) do
            local met, pack, cur, req = classes.planet_gate(player, p)   -- 星球瓶门槛
            local tip
            if not met then tip = {'wn.planet-need-pack', '[img=item/' .. pack .. ']', req, cur}   -- 瓶不够：显示需求
            elseif open[p] then tip = {'wn.act-travel-tip'}
            else tip = {'wn.travel-closed', math.floor((tc[p] or 0.5) * 100)} end
            buttons[#buttons + 1] = {name = 'wn_act_travel_' .. p, caption = {'wn.act-travel', p, util.planet_name(p)}, tags = {wn_travel = p},
                enabled = (open[p] or false) and met,   -- 需本轮开放【且】瓶达标
                tooltip = tip}
        end
    end
    -- 【出生星球】组：设定下次跃迁复活 + 领起手装备的星球。不传送、全星球可选、当前选中标 ✓。
    buttons[#buttons + 1] = {label = true, caption = {'wn.actions-home-group'}}
    local home = (storage.respawn_surface or {})[player.name] or 'nauvis'
    for _, p in ipairs(constants.PLANETS) do
        local met, pack, cur, req = classes.planet_gate(player, p)   -- 出生星球同样要瓶门槛
        buttons[#buttons + 1] = {name = 'wn_act_home_' .. p,
            caption = {p == home and 'wn.act-home-cur' or 'wn.act-home', p, util.planet_name(p)}, tags = {wn_home = p},
            enabled = met,
            tooltip = met and {'wn.act-home-tip'} or {'wn.planet-need-pack', '[img=item/' .. pack .. ']', req, cur}}
    end
    -- 功能菜单所有【可点按钮】统一【最小宽】→ 等宽对齐加宽（短的撑到此宽、长的随内容/面板再伸展，
    -- 复用 add_buttons 的 min_width 分支：minimal_width + horizontally_stretchable）。label/分隔无 name 不受影响。
    local ACTIONS_BTN_MIN_W = 260
    for _, b in ipairs(buttons) do
        if b.name then b.min_width = ACTIONS_BTN_MIN_W end
    end
    -- 顶部放与按钮 tooltip 同一段简介（buttons_at_bottom=true → 说明在上、操作按钮在下）。
    M.show_popup(player, {'wn.actions-title'}, {{'wn.actions-help'}, ''}, buttons, true)
end

-- 弹出【职业】窗口（HUD 独立按钮）：每个职业一个按钮，标出当前/预约职业、悬停说明专精瓶。
-- 点击经 tick.on_gui_click（tags.wn_class）路由到 commands.set_class。同时只能一种职业。
-- 标记规则（格式：左signal 职业图标 职业名 右signal，左右可不同）：
--   · 当前职业 == 预约职业：两侧 [signal-mining]，名字 acid 色（已生效、无变更）。
--   · 不一致：当前职业 [signal-output]…[signal-deny]、红色（本世界生效中、即将换走）；
--             预约职业 [signal-input]…[signal-check]、蓝色（下次跃迁换上）。
function M.show_classes(player)
    if not player then return end
    local cur = classes.current_key(player)    -- 当前职业（本世界生效）
    local res = classes.selected_key(player)   -- 预约职业（下次跃迁生效）
    -- 分区标题：section 值就是 locale key（如 {section = 'energy'}），查 wn.class-section-<key>，
    -- locale 缺词条时 fallback 显示 key 原文。
    local buttons = {}
    for _, def in ipairs(classes.all()) do
        if not def.key or def.key == '' then
            if def.section then
                buttons[#buttons + 1] = {label = true, caption = classes.text_loc('wn.class-section-' .. def.section, nil, def.section)}
            end
            buttons[#buttons + 1] = {newrow = true}   -- 空职业（无 key 的 {}/{section=} 占位）= UI 换行/分组分隔
        else
        -- 职业名三层兜底：locale 词条 wn.class-name-<key>(英文友好) → 动态表 storage.class_names[key](/c 热改) → def.name(中文默认)。
        local name_loc = classes.text_loc('wn.class-name-' .. def.key, (storage.class_names or {})[def.key], def.name or def.key)
        -- tooltip：白送(starter)每物品一行"+N [img]"；奖励(rewards)每条一行"每 a 级 [瓶] b 个 [物品]"。两者都换行。
        -- 按钮图标 starter_img 取第一件白送物品；a:b 为 满级:满级总个数 的最简比(gcd 约分)。
        -- 按钮图标物品：优先第一件白送(starter)，starter 为空则退用第一项奖励(rewards)物品。
        local icon_item = (def.starter and def.starter[1] and def.starter[1].item)
                       or (def.rewards and def.rewards[1] and def.rewards[1].item)
        local starter_img = icon_item and ('[img=item/' .. icon_item .. ']') or ''
        -- tooltip 按【区域】分组收集，相邻非空区域间插一个空行，最后再分块嵌套（见下）。
        -- 4 区域：① 开局解锁（科技每个一行=图标+Localised 名；配方一行平铺图标）② 白送物品 ③ 满级奖励 ④ 解锁条件。
        local regions = {}
        -- 区域① 开局解锁：科技【逐个一行】，用 {''} 空键拼接「图标 + 本地化名」(无需新 locale 键)；配方仍一行平铺图标。
        local r_unlock = {}
        if def.techs and #def.techs > 0 then
            r_unlock[#r_unlock + 1] = {'wn.class-tip-tech'}   -- 区域标题（纯标签，无参数）
            for _, t in ipairs(def.techs) do
                local tname, p = classes.tech_entry(t)   -- 条目可为 '名' 或 {'名', p=}
                local proto = tname and prototypes.technology[tname]
                local line = {'', '\n[technology=' .. (tname or '?') .. '] ', proto and proto.localised_name or tname or '?'}
                if p < 1 then line[#line + 1] = {'wn.class-tip-tech-chance', math.floor(p * 100 + 0.5)} end   -- 概率解锁的科技：名后标注 %
                r_unlock[#r_unlock + 1] = line
            end
        end
        if def.recipes and #def.recipes > 0 then
            r_unlock[#r_unlock + 1] = {'wn.class-tip-recipe'}   -- 区域标题（纯标签，无参数）
            for _, rc in ipairs(def.recipes) do
                local rname, p = classes.tech_entry(rc)   -- 配方条目与 techs 同格式：'名' 或 {'名', p=}
                local proto = rname and prototypes.recipe[rname]
                local line = {'', '\n[recipe=' .. (rname or '?') .. '] ', proto and proto.localised_name or rname or '?'}
                if p < 1 then line[#line + 1] = {'wn.class-tip-tech-chance', math.floor(p * 100 + 0.5)} end   -- 概率解锁标注 %（与科技共用同一词条）
                r_unlock[#r_unlock + 1] = line
            end
        end
        if #r_unlock > 0 then regions[#regions + 1] = r_unlock end
        -- 区域② 白送物品：每物品一行 "+N [img]"。总个数 = count 个，或 groups 组 × 堆叠（默认 1 组）。
        -- 可选 p<1 时物品是随机的（每件独立 p 概率，实发 ~ B(总数,p)），行尾标注"每件 %"。
        local r_starter = {}
        for _, s in ipairs(def.starter or {}) do
            local proto = prototypes.item[s.item]
            local total = s.count or (((proto and proto.stack_size) or 1) * (s.groups or 1))
            local line = {'wn.class-tip-head', total, '[img=item/' .. s.item .. ']'}
            if (s.p or 1) < 1 then line = {'', line, {'wn.class-tip-item-p', math.floor(s.p * 100 + 0.5)}} end
            r_starter[#r_starter + 1] = line
        end
        if #r_starter > 0 then regions[#regions + 1] = r_starter end
        -- 区域③ 满级奖励：每条 "每 P 级得 Q 个 [物品] 当前/满级"。
        local r_reward = {}
        for _, r in ipairs(def.rewards or {}) do
            local proto = prototypes.item[r.item]
            local total = r.count or (((proto and proto.stack_size) or 1) * (r.groups or 1))   -- 满级最多给多少个(M)：有 count 按个数(与 respawn_gifts 发放口径一致)，否则 堆叠×groups
            local full = r.full or def.full or CLASS_MAX_LEVEL                    -- 满级线：每条 reward 的 full 可覆盖职业 full（与发放口径一致）
            local lv = math.min(classes.pack_level(player, r.pack), full)        -- 玩家该瓶当前等级(封顶 full)
            local current = math.floor(total * lv / full)                        -- 当前能拿到的数量(yyy，与 respawn_gifts 发放公式一致)
            local g = util.gcd(full, total)                                       -- 约分 满级线:满级总数 → 每 P 级得 Q 个
            local line = {'wn.class-tip-reward',
                '[img=item/' .. r.pack .. ']',       -- 瓶图标(等级来源)
                math.floor(full / g),                -- P：每多少级得一批
                math.floor(total / g),               -- Q：每批给多少个
                '[img=item/' .. r.item .. ']',       -- 物品图标
                current,                             -- __5__ yyy：当前等级能拿到的数量(动态)
                total}                               -- __6__ xxx：满级最多(不变)
            if (r.p or 1) < 1 then line = {'', line, {'wn.class-tip-item-p', math.floor(r.p * 100 + 0.5)}} end   -- 随机物品：行尾标注"每件 %"
            r_reward[#r_reward + 1] = line
        end
        if #r_reward > 0 then regions[#regions + 1] = r_reward end
        -- 区域④ 解锁条件（需全部满足）：需求瓶/等级 + 当前等级。
        local r_cond = {}
        for _, u in ipairs(def.unlock or {}) do
            r_cond[#r_cond + 1] = {'wn.class-tip-unlock', '[img=item/' .. u.pack .. ']', u.level, classes.pack_level(player, u.pack)}
        end
        if #r_cond > 0 then regions[#regions + 1] = r_cond end
        -- 合并：相邻非空区域间插一个 '\n'（空行）。每条本身以 \n 起，额外一个 \n 即得一空行分隔。
        local parts = {}
        for ri, reg in ipairs(regions) do
            if ri > 1 then parts[#parts + 1] = '\n' end
            for _, p in ipairs(reg) do parts[#parts + 1] = p end
        end
        -- 分块嵌套：localised string 单层最多 20 参数，超了会崩（"too many parameters for localized string"）。
        -- 把 parts 串成嵌套结构——每层放 ≤19 个真实参数 + 第 20 个参数指向下一层 → 任意条数都安全。
        local tip = {''}
        local node = tip
        for _, p in ipairs(parts) do
            if #node >= 20 then            -- 本层已 '' + 19 参数，开新嵌套层接在第 20 个参数
                local nxt = {''}
                node[#node + 1] = nxt
                node = nxt
            end
            node[#node + 1] = p
        end
        -- 按钮文案：当前/预约职业按规则加信号+染色；普通职业沿用 class-pick（图标+名）。左右信号可不同。
        local sigl, sigr, col
        if def.key == cur and def.key == res then sigl, sigr, col = 'signal-mining', 'signal-mining', 'acid'   -- 已生效、无变更
        elseif def.key == cur then sigl, sigr, col = 'signal-output', 'signal-deny', 'red'                      -- 当前(即将换走)
        elseif def.key == res then sigl, sigr, col = 'signal-input', 'signal-check', 'blue'                     -- 预约(下次换上)
        end
        local caption
        if sigl then
            -- 左signal 职业图标 [色]职业名[/色] 右signal
            caption = {'', '[virtual-signal=' .. sigl .. '] ' .. starter_img .. ' [color=' .. col .. ']', name_loc,
                       '[/color] [virtual-signal=' .. sigr .. ']'}
        else
            caption = {'wn.class-pick', name_loc, starter_img}
        end
        -- 未解锁 → 按钮置灰(enabled=false，不可点)，但 tooltip 仍显示解锁条件。
        buttons[#buttons + 1] = {name = 'wn_act_class_' .. def.key,
            caption = caption, width = 180,   -- 6 列平铺用窄按钮（默认网格 220）
            tooltip = tip, enabled = classes.unlocked(player, def), tags = {wn_class = def.key}}
        end
    end
    -- 顶部自带说明（buttons_at_bottom=true → 说明在上、职业按钮在下）。
    M.show_popup(player, {'wn.class-title'}, {{'wn.class-help'}}, buttons, true, nil, 6)   -- 职业按钮 6 列平铺
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
