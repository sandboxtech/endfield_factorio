-- 玩家行为统计的数据存储。技能用的统计（craft_count/mining_count/move_distance/deaths）
-- 由 passives.lua 在对应动作事件里递增并即时施加；本文件只负责 get/默认值 +
-- 在线类统计（online_minutes 等）的采样。
-- 字段：
--   online_minutes  在线累计分钟数（每分钟采样，在线即 +1 → 金币奖励）
--   craft_count     手搓完成的物品数（→ 手搓速度技能）
--   mining_count    手动采矿/拆除次数（→ 挖矿速度技能）
--   move_distance   移动累计格数（→ 移动速度技能）
--   deaths          死亡次数（→ 生命上限技能）
-- 数据跨跃迁保留（终身累积）。

local M = {}

local DEFAULTS = {
    online_minutes = 0,
    craft_count    = 0,
    mining_count   = 0,
    move_distance  = 0,
    deaths         = 0,
}

-- 统计按【玩家名】存储：名字跨 index 稳定，被删玩家用同名回归即自动继承，删玩家时无需动 storage。
function M.get(player_index)
    storage.player_stats = storage.player_stats or {}
    local player = game.get_player(player_index)
    local key = player and player.name or player_index
    local s = storage.player_stats[key]
    if not s then
        s = {}
        for k, v in pairs(DEFAULTS) do s[k] = v end
        storage.player_stats[key] = s
    end
    return s
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

-- 手搓/采矿/移动/死亡的事件处理已移到 passives.lua（在那里递增统计并即时升级技能）。

return M
