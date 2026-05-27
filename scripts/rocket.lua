-- 发射火箭惩罚：每发射一次，本轮自动跃迁时间 -1 分钟，向所有玩家公告并打印火箭载荷。
-- 设计意图：跃迁是"从头再来"的核心节奏，发火箭把资源送上太空会拖慢/逃避这个节奏，
-- 因此对其施加时间惩罚。
local constants = require('scripts.constants')

local M = {}

local PENALTY_MINUTES = 1

-- 读取火箭货舱内容，拼成富文本；空舱返回 "—"。
local function payload_text(rocket)
    if not (rocket and rocket.valid) then return '—' end
    local inv = rocket.get_inventory(defines.inventory.rocket)
    if not inv then return '—' end
    local parts = {}
    for _, c in pairs(inv.get_contents()) do
        parts[#parts + 1] = '[item=' .. c.name .. ',quality=' .. c.quality .. ']×' .. c.count
    end
    if #parts == 0 then return '—' end
    return table.concat(parts, ' ')
end

script.on_event(defines.events.on_rocket_launched, function(event)
    -- 惩罚：本轮自动跃迁时间 -1 分钟（warp_hours 以小时计，1 分钟 = 1/60 小时）
    storage.warp_hours = (storage.warp_hours or 1) - PENALTY_MINUTES / 60

    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local life_hours = (storage.warp_hours * constants.hour_to_tick - last_run_ticks) / constants.hour_to_tick

    game.print({'wn.rocket-penalty',
                payload_text(event.rocket),
                PENALTY_MINUTES,
                math.floor(life_hours * 100) / 100})
end)

return M
