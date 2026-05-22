-- 记录每个玩家的行为统计，驱动 passives 里的角色被动加成。
-- 字段：
--   afk_minutes   挂机累计分钟数（每分钟采样一次，afk_time ≥ 阈值时 +1）
--   afk_research  挂机时完成的科技数量
--   mining_count  手动采矿/拆除次数
--   craft_count   手搓完成的配方数量
--   craft_seconds 手搓累计耗时（按 recipe.energy × count 估算）
--   deaths        死亡次数
-- 数据跨跃迁保留（与 storage.science_exp 一致，是终身累积）。

local M = {}

-- 玩家被视为"挂机"的阈值：连续 30 秒无任何输入即开始计数。
local AFK_THRESHOLD_TICKS = 30 * 60

local DEFAULTS = {
    afk_minutes   = 0,
    afk_research  = 0,
    mining_count  = 0,
    craft_count   = 0,
    craft_seconds = 0,
    deaths        = 0,
}

function M.get(player_index)
    storage.player_stats = storage.player_stats or {}
    local s = storage.player_stats[player_index]
    if not s then
        s = {}
        for k, v in pairs(DEFAULTS) do s[k] = v end
        storage.player_stats[player_index] = s
    else
        -- 兼容旧存档：缺字段时补 0
        for k, v in pairs(DEFAULTS) do
            if s[k] == nil then s[k] = v end
        end
    end
    return s
end

function M.is_afk(player)
    return player.connected and player.afk_time and player.afk_time >= AFK_THRESHOLD_TICKS
end

function M.on_research_finished_for_afk_players()
    for _, player in pairs(game.connected_players) do
        if M.is_afk(player) then
            local s = M.get(player.index)
            s.afk_research = s.afk_research + 1
        end
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

-- 每分钟采样：处于挂机状态的在线玩家 afk_minutes +1。
script.on_nth_tick(60 * 60, function()
    if not storage.player_stats then storage.player_stats = {} end
    for _, player in pairs(game.connected_players) do
        if M.is_afk(player) then
            local s = M.get(player.index)
            s.afk_minutes = s.afk_minutes + 1
        end
    end
end)

return M
