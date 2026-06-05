-- 发射火箭的惩罚 + 载荷公告：每把一发 cargo pod 送上太空，本轮自动跃迁时间 -1 分钟。
-- 设计意图：跃迁是"从头再来"的核心节奏，把资源送上太空会拖慢/逃避这个节奏，故施加时间惩罚。
-- 2.0 SA：货物不在火箭本体，而在它发射的 cargo pod 的 cargo_unit 库存里。on_rocket_launched 那一刻
-- pod 往往还没挂上货（读出来是空），所以改在 on_cargo_pod_finished_ascending 读，此刻 pod 已带货
-- 升空完成、尚未在目的地卸货；其 launched_by_rocket 字段又能精确区分"火箭发射"与玩家手动 pod 跃迁。
local constants = require('scripts.constants')
local util = require('scripts.util')
local gui = require('scripts.gui')
local events = require('scripts.events')

local M = {}

local PENALTY_MINUTES = 1

-- 全服统计（功能菜单"统计数据"查看）：火箭发射次数 + 送上太空的科技瓶数（按瓶种类、跨世界永久累加，跃迁不清零）。
-- 只认 constants.science_packs 的 12 种瓶；品质不区分，按个数合并累计。
local SCIENCE_PACK_SET = {}
for _, p in ipairs(constants.science_packs) do SCIENCE_PACK_SET[p] = true end

local function count_launched_packs(pod)
    if not (pod and pod.valid) then return end
    local inv = pod.get_inventory(defines.inventory.cargo_unit)
    if not inv then return end
    storage.rocket_packs = storage.rocket_packs or {}
    for _, c in pairs(inv.get_contents()) do
        if SCIENCE_PACK_SET[c.name] then
            storage.rocket_packs[c.name] = (storage.rocket_packs[c.name] or 0) + c.count
        end
    end
end

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

-- events.safe 包裹：handler 内任何报错（读 cargo_pod_origin/surface 等意外）被 pcall 兜住、报管理员，不崩服。
script.on_event(defines.events.on_cargo_pod_finished_ascending, events.safe('rocket_penalty', function(event)
    if not event.launched_by_rocket then return end   -- 仅火箭发射的 pod（排除玩家手动 pod 跃迁/下行）

    storage.warp_hours = (storage.warp_hours or 1) - PENALTY_MINUTES / 60

    local last_run_ticks = game.tick - (storage.run_start_tick or game.tick)
    local rh, rm = util.hm(storage.warp_hours * constants.hour_to_tick - last_run_ticks)

    -- 发射井位置 GPS（cargo_pod_origin = 发射它的井/枢纽/着陆台）：拼成可点击的地图 ping，公告里指出谁在哪发射。
    -- 全程判空：pod / origin 可能 nil 或失效，surface 也可能取不到 → 任一缺失就退回空串，绝不让公告本身崩。
    local pod = event.cargo_pod
    -- 全服统计：发射次数 +1（每个火箭发射的 pod 算一次，与上面惩罚的口径一致），并累计舱内科技瓶。
    storage.rocket_launches = (storage.rocket_launches or 0) + 1
    count_launched_packs(pod)
    local origin = pod and pod.valid and pod.cargo_pod_origin
    local gps = ''
    if origin and origin.valid and origin.position and origin.surface then
        local p = origin.position
        gps = '[gps=' .. math.floor(p.x) .. ',' .. math.floor(p.y) .. ',' .. origin.surface.name .. ']'
    end

    game.print({'wn.rocket-penalty',
                payload_text(pod),
                PENALTY_MINUTES,
                rh, rm, gps})
    gui.refresh_countdown()   -- 倒计时已变 → 立刻刷新所有人头顶 UI
end))

return M
