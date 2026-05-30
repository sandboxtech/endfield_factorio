-- 跃迁仪式特效（纯表现层 + 跃迁触发收口）：跃迁截止前 LEAD 秒起屏幕中央大字倒计时 + 每秒提示音，
-- 归零那刻才真正执行 reset（结算/清场/重生），并据"本轮是否有人拿到经验"播放成功/普通音效 + 白闪。
--
-- 跃迁触发【唯一收口】：本模块的 on_tick 每 tick 看距跃迁还剩多少，≤LEAD 秒即起倒计时、归零调 reset。
-- 故 tick.lua 不再自行 reset（避免双 owner 重复跃迁）。/reset 命令与 on_init 仍直接调 reset.reset()（管理/开局，无需仪式）。
--
-- 状态存 storage.warp_fx（瞬态，nil=未进行；倒计时结束即置 nil）。画面对象全部带 time_to_live 自动销毁，
-- 不写入存档长期占位、不泄露存档体积。【绝不用 rendering.clear()】——那会连染地精灵一起抹掉。
local events    = require('scripts.events')
local constants = require('scripts.constants')
local reset     = require('scripts.reset')

local M = {}

local LEAD_SECONDS = 10                           -- 跃迁前几秒开始倒计时
local TICK_SOUND    = 'utility/scenario_message'  -- 每秒一声（占位可换）
local SUCCESS_SOUND = 'utility/game_won'          -- 本轮有人拿到经验 → 成功音
local PLAIN_SOUND   = 'utility/console_message'   -- 本轮无人拿到经验 → 普通音

-- 距下次跃迁剩余 tick（与 gui.warp_hm / tick.lua 告警同一公式）。
local function warp_remaining()
    local elapsed = game.tick - (storage.run_start_tick or game.tick)
    return (storage.warp_hours or 1) * constants.hour_to_tick - elapsed
end

-- play 包了 pcall：utility 路径无效也不崩、不报错（可放心换音效路径）。
local function play(path)
    pcall(function() game.play_sound{path = path} end)
end

-- 给每个在线玩家在视野中央画一行大字。follow=true 挂角色（随走动平滑跟随，用于逐秒数字）；
-- follow=false 挂固定地面坐标（reset 会杀角色 → 归零"跃迁!"大字必须用坐标，否则随角色一起消失）。
-- 一律带 time_to_live 自动消失，免手动清理、不留存档。
local function draw_center(text, color, scale, ttl, follow)
    for _, player in pairs(game.connected_players) do
        local target = (follow ~= false and player.character) or player.position
        rendering.draw_text{
            text = text,
            surface = player.surface,
            target = target,
            color = color,
            scale = scale,
            alignment = 'center',
            vertical_alignment = 'middle',
            players = {player},
            time_to_live = ttl,
        }
    end
end

-- 跃迁微光参数：柔和青白、峰值很低（不晃眼），随后由 on_tick 平滑淡出。
local GLOW_COLOR = {r = 0.6, g = 0.9, b = 1.0}   -- 柔和青白（想要纯白改 {1,1,1}，想黑场眨眼改 {0,0,0}）
local GLOW_PEAK  = 0.3                            -- 峰值透明度（越小越不晃眼；硬闪是 0.7）
local GLOW_TICKS = 24                             -- 淡出时长（tick），约 0.4 秒

-- 当前淡出进度对应的一帧（alpha 从 GLOW_PEAK 线性降到 0）。挂固定坐标、只该玩家可见、ttl 短随即重画。
local function draw_glow(alpha)
    for _, player in pairs(game.connected_players) do
        local p = player.position
        rendering.draw_rectangle{
            left_top     = {p.x - 256, p.y - 256},
            right_bottom = {p.x + 256, p.y + 256},
            color = {r = GLOW_COLOR.r * alpha, g = GLOW_COLOR.g * alpha, b = GLOW_COLOR.b * alpha, a = alpha},
            filled = true,
            surface = player.surface,
            players = {player},
            time_to_live = 3,
        }
    end
end

-- 归零收尾：大字"跃迁!" + 启动柔和微光淡出（共用：真跃迁与测试都走这里）。
local function finale()
    draw_center({'wn.warp-fx-go'}, {r = 1, g = 0.85, b = 0.2}, 14, 90, false)
    storage.warp_glow = {start = game.tick}   -- 由 on_tick 逐帧淡出，几 tick 后自动结束
end

-- 倒计时数字配色：从橘色平滑插值到红色（剩余秒越少越红）。sec 从 LEAD→1 映射 t 从 0→1。
local CD_ORANGE = {1, 0.55, 0.20}
local CD_RED    = {1, 0.15, 0.15}
local function lerp(a, b, t) return a + (b - a) * t end
local function countdown_color(sec)
    local t = math.min(1, math.max(0, (LEAD_SECONDS - sec) / math.max(1, LEAD_SECONDS - 1)))
    return {r = lerp(CD_ORANGE[1], CD_RED[1], t), g = lerp(CD_ORANGE[2], CD_RED[2], t), b = lerp(CD_ORANGE[3], CD_RED[3], t)}
end

-- on_tick 驱动：未在倒计时则看是否临近真跃迁；在倒计时则逐秒刷帧、归零收尾（结算+清场+重生）。
events.on(defines.events.on_tick, function()
    -- 跃迁微光淡出（与倒计时状态独立，可在 reset 后继续几 tick）：alpha 从 GLOW_PEAK 线性降到 0。
    local glow = storage.warp_glow
    if glow then
        local t = game.tick - glow.start
        if t >= GLOW_TICKS then
            storage.warp_glow = nil
        else
            draw_glow(GLOW_PEAK * (1 - t / GLOW_TICKS))
        end
    end

    local fx = storage.warp_fx
    if not fx then
        -- 空闲：无需每 tick 探测——每秒探一次足够（倒计时窗口 10 秒，绝不会错过）。
        -- 临近真跃迁（剩余 ≤ LEAD 秒且还没到）→ 起一段倒计时，end_tick 对齐真实截止 → 归零正好是跃迁时刻。
        if game.tick % 60 == 0 then
            local remaining = warp_remaining()
            if remaining > 0 and remaining <= LEAD_SECONDS * 60 then
                storage.warp_fx = {end_tick = game.tick + remaining, last = nil}
            end
        end
        return
    end

    local remain = fx.end_tick - game.tick
    if remain <= 0 then
        storage.warp_fx = nil          -- 先清状态：reset 会重置 run_start_tick，下个 tick 不会误判再起一轮
        finale()
        local gained = reset.reset()                       -- 真跃迁：结算 + 清场 + 重生；返回本轮是否有人拿到经验
        play(gained and SUCCESS_SOUND or PLAIN_SOUND)
        return
    end

    -- 每跨过一个整数秒刷一帧（ttl=60，正好等于刷新间隔 → 旧字消失同刻新字出现，无缝、零重叠）。
    local sec = math.ceil(remain / 60)
    if fx.last ~= sec then
        fx.last = sec
        draw_center(tostring(sec), countdown_color(sec), 12, 60, true)
        play(TICK_SOUND)
    end
end)

return M
