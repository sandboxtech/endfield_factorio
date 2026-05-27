-- 记录每个玩家的行为统计，驱动 passives 被动加成与金币奖励。
-- 字段：
--   online_minutes  在线累计分钟数（每分钟采样一次，在线即 +1）
--   online_research 在线时完成的科技数量
--   mining_count    手动采矿/拆除次数
--   craft_count     手搓完成的配方数量
--   craft_seconds   手搓累计耗时（按 recipe.energy × count 估算）
--   deaths          死亡次数
--   online_warps    在线时经历的跃迁次数（→ rare 金币）
-- 数据跨跃迁保留（与 storage.science_exp 一致，是终身累积）。
--
-- 注意：奖励只看"是否在线"，不看是否挂机（is_afk）——否则会反向鼓励玩家在线挂机不干活。

local M = {}

local DEFAULTS = {
    online_minutes  = 0,
    online_research = 0,
    mining_count    = 0,
    craft_count     = 0,
    craft_seconds   = 0,
    deaths          = 0,
    online_warps    = 0,
}

-- 旧存档字段迁移：afk_* → online_*（语义从"挂机"改为"在线"）。
local RENAMES = {
    afk_minutes  = 'online_minutes',
    afk_research = 'online_research',
    afk_warps    = 'online_warps',
}

function M.get(player_index)
    storage.player_stats = storage.player_stats or {}
    local s = storage.player_stats[player_index]
    if not s then
        s = {}
        for k, v in pairs(DEFAULTS) do s[k] = v end
        storage.player_stats[player_index] = s
    else
        -- 兼容旧存档：先迁移改名字段，再给缺失字段补 0
        for old, new in pairs(RENAMES) do
            if s[new] == nil and s[old] ~= nil then
                s[new] = s[old]
                s[old] = nil
            end
        end
        for k, v in pairs(DEFAULTS) do
            if s[k] == nil then s[k] = v end
        end
    end
    return s
end

-- 研究完成时调用：所有在线玩家 online_research +1（任何科技都算）。
function M.on_research_finished_for_online_players()
    for _, player in pairs(game.connected_players) do
        local s = M.get(player.index)
        s.online_research = s.online_research + 1
    end
end

-- 跃迁时调用：所有在线玩家 online_warps +1（→ rare 金币）。
function M.on_warp_for_online_players()
    for _, player in pairs(game.connected_players) do
        local s = M.get(player.index)
        s.online_warps = s.online_warps + 1
    end
end

-- 每分钟采样一次：所有在线玩家 online_minutes +1。
-- 由 tick.lua 的统一 on_nth_tick(3600) 调用——本文件不再单独注册，避免覆盖。
function M.sample_online()
    if not storage.player_stats then storage.player_stats = {} end
    for _, player in pairs(game.connected_players) do
        local s = M.get(player.index)
        s.online_minutes = s.online_minutes + 1
    end
end

script.on_event(defines.events.on_player_mined_entity, function(event)
    if not event.player_index then return end
    local s = M.get(event.player_index)
    s.mining_count = s.mining_count + 1
end)

script.on_event(defines.events.on_player_crafted_item, function(event)
    local s = M.get(event.player_index)
    local stack = event.item_stack
    local count = (stack and stack.valid_for_read and stack.count) or 1
    s.craft_count = s.craft_count + count
    local recipe = event.recipe
    if recipe and recipe.energy then
        s.craft_seconds = s.craft_seconds + recipe.energy * count
    end
end)

script.on_event(defines.events.on_player_died, function(event)
    local s = M.get(event.player_index)
    s.deaths = s.deaths + 1
end)

return M
