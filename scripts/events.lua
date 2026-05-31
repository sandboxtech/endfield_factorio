-- 轻量事件总线：解决 script.on_event 每个事件只保留最后一次注册、会互相覆盖的问题。
-- 同一事件可由多处 events.on() 订阅，内部对该事件只 script.on_event 注册【一次】，触发时依次调用所有订阅者。
-- 用法：local events = require('scripts.events'); events.on(defines.events.on_entity_died, function(e) ... end)
-- 约定：凡是可能被多方监听的事件，都走本总线，不要再直接 script.on_event 同一事件（否则仍会覆盖总线）。
-- 订阅须在控制阶段加载时（模块 require 顶层）完成，保证每次加载注册一致、无多人不同步。
local M = {}

local handlers = {}   -- [event_id] = { fn1, fn2, ... }
local reported = {}   -- 去重：同一 (标签|错误信息) 一次会话只播报一次，防每 tick 刷屏

-- 统一错误兜底：handler 抛错时不让它崩掉整个多人服务器，改为写 log + 通知在线管理员。
-- 纯读 game.connected_players、确定性，多人下各客户端表现一致、不会不同步。
local function report(tag, err)
    log('[wn] handler error @' .. tostring(tag) .. ': ' .. tostring(err))
    local key = tostring(tag) .. '|' .. tostring(err)
    local now = game and game.tick or 0
    if reported[key] and now - reported[key] < 3600 then return end   -- 同一错误每分钟最多报一次（持续可见、又不刷屏）
    reported[key] = now
    if game then
        for _, p in pairs(game.connected_players) do
            if p.admin then
                p.print('[wn] 脚本出错(' .. tostring(tag) .. ')，已拦截未崩服：' .. tostring(err))
            end
        end
    end
end

-- 把任意 handler 包成"出错只播报不崩服"的安全版。
-- 直接 script.on_event 注册的高危 handler（逐区块生成等）可用：script.on_event(id, events.safe('chunk', fn))。
-- tag 仅用于报错定位，省略则用事件 id。
function M.safe(tag, fn)
    if fn == nil then fn, tag = tag, 'event' end   -- 允许只传 fn
    return function(e)
        local ok, err = pcall(fn, e)
        if not ok then report(tag, err) end
    end
end

function M.on(event_id, fn)
    local list = handlers[event_id]
    if not list then
        list = {}
        handlers[event_id] = list
        script.on_event(event_id, function(e)
            -- 逐个 handler 兜底：一个订阅者抛错不影响同事件的其他订阅者，也不崩服。
            for _, h in ipairs(list) do
                local ok, err = pcall(h, e)
                if not ok then report('event ' .. tostring(event_id), err) end
            end
        end)
    end
    list[#list + 1] = fn
end

return M
