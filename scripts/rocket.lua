-- 发射火箭的惩罚 + 载荷公告：每把一发 cargo pod 送上太空，本轮自动跃迁时间 -1 分钟。
-- 设计意图：跃迁是"从头再来"的核心节奏，把资源送上太空会拖慢/逃避这个节奏，故施加时间惩罚。
-- 2.0 SA：货物不在火箭本体，而在它发射的 cargo pod 的 cargo_unit 库存里。on_rocket_launched 那一刻
-- pod 往往还没挂上货（读出来是空），所以改在 on_cargo_pod_finished_ascending 读——此刻 pod 已带货
-- 升空完成、尚未在目的地卸货；其 launched_by_rocket 字段又能精确区分"火箭发射"与玩家手动 pod 旅行。
local constants = require('scripts.constants')
local util = require('scripts.util')

local M = {}

local PENALTY_MINUTES = 1

-- 读取 cargo pod 货舱内容，拼成富文本；空舱返回 "—"。
local function payload_text(pod)
    if not (pod and pod.valid) then return '—' end
    local inv = pod.get_inventory(defines.inventory.cargo_unit)
    if not inv then return '—' end
    local parts = {}
    for _, c in pairs(inv.get_contents()) do
        parts[#parts + 1] = ' [item=' .. c.name .. ',quality=' .. c.quality .. ']×' .. c.count
    end
    if #parts == 0 then return '—' end
    return table.concat(parts, ' ')
end

script.on_event(defines.events.on_cargo_pod_finished_ascending, function(event)
    if not event.launched_by_rocket then return end   -- 仅火箭发射的 pod（排除玩家手动 pod 旅行/下行）

    storage.warp_hours = (storage.warp_hours or 1) - PENALTY_MINUTES / 60

    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local rh, rm = util.hm(storage.warp_hours * constants.hour_to_tick - last_run_ticks)

    game.print({'wn.rocket-penalty',
                payload_text(event.cargo_pod),
                PENALTY_MINUTES,
                rh, rm})
end)

return M
