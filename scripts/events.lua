-- 轻量事件总线：解决 script.on_event 每个事件只保留最后一次注册、会互相覆盖的问题。
-- 同一事件可由多处 events.on() 订阅，内部对该事件只 script.on_event 注册【一次】，触发时依次调用所有订阅者。
-- 用法：local events = require('scripts.events'); events.on(defines.events.on_entity_died, function(e) ... end)
-- 约定：凡是可能被多方监听的事件，都走本总线，不要再直接 script.on_event 同一事件（否则仍会覆盖总线）。
-- 订阅须在控制阶段加载时（模块 require 顶层）完成，保证每次加载注册一致、无多人不同步。
local M = {}

local handlers = {}   -- [event_id] = { fn1, fn2, ... }

function M.on(event_id, fn)
    local list = handlers[event_id]
    if not list then
        list = {}
        handlers[event_id] = list
        script.on_event(event_id, function(e)
            for _, h in ipairs(list) do h(e) end
        end)
    end
    list[#list + 1] = fn
end

return M
