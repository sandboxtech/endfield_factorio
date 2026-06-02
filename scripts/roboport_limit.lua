-- 限制机器人网络规模：roboport 放置时，若它所在的 logistic 网络已【超过上限】个 roboport，
-- 就摧毁刚放的这一个并退还（玩家手放退背包、机器人建则原地洒落），防止超大机器人网络拖慢服务器。
-- 上限存 storage.roboport_limit（默认 10000，可 /c 随时调）。超限会全服广播，但 1 分钟内只播一次防刷屏。
local events = require('scripts.events')

local M = {}

local WARN_COOLDOWN = 60 * 60   -- 广播节流：1 分钟（tick）

-- roboport 放置事件统一处理（on_built_entity 玩家手放 / on_robot_built_entity 机器人建）。
local function check(e)
    local ent = e.entity
    if not (ent and ent.valid and ent.type == 'roboport') then return end   -- 高频事件，先按类型早退
    local net = ent.logistic_network
    local limit = storage.roboport_limit or 10000
    -- net.cells = 该网络全部 roboport 单元；#cells 即网络内 roboport 数量。
    if not (net and #net.cells > limit) then return end

    -- 退还刚放的 roboport（保留品质）
    local q = ent.quality and ent.quality.name
    if e.player_index then
        local p = game.get_player(e.player_index)
        if p then p.insert{name = ent.name, count = 1, quality = q} end
    else
        ent.surface.spill_item_stack{position = ent.position, stack = {name = ent.name, count = 1, quality = q}}
    end
    ent.destroy()

    -- 全服广播（WARN_COOLDOWN 内已播过则跳过，防刷屏）
    local now = game.tick
    if not storage.roboport_warn_tick or now - storage.roboport_warn_tick >= WARN_COOLDOWN then
        storage.roboport_warn_tick = now
        game.print({'wn.roboport-limit', limit})
    end
end

events.on(defines.events.on_built_entity, check)
events.on(defines.events.on_robot_built_entity, check)

return M
