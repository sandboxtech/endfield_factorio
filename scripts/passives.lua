-- 角色被动：固定惩罚，不随任何统计/升级变化。
--   所有玩家 -50% 手搓速度、-50% 移动速度、-50% 挖矿/拆除速度。
--   生命值上限、背包容量保持原版（不加修正）。
-- 科技瓶经验仍由 science_exp 累积，但只用于"携带奖励瓶子"（currency.reward_for_exp），不再驱动被动。
local player_stats = require('scripts.player_stats')

local M = {}

M.craft_penalty  = -0.5   -- 手搓速度 -50%
M.run_penalty    = -0.5   -- 移动速度 -50%
M.mining_penalty = -0.5   -- 挖矿/拆除速度 -50%

-- 某瓶累计科技瓶经验（→ 携带奖励），供 gui / respawn_gifts / inspect 读取。
-- key 就是瓶名（12 种），各品质已在 science_exp.collect 里累加进同一 key。
function M.exp_total_for_pack(player_index, pack_name)
    local exp = storage.science_exp and storage.science_exp[player_index]
    if not exp then return 0 end
    return exp[pack_name] or 0
end

-- 某玩家某行为统计值（如 online_minutes → 金币奖励），供展示读取。
function M.get_stat(player_index, stat_name)
    return player_stats.get(player_index)[stat_name] or 0
end

-- 对有 character 的玩家施加固定惩罚。新建/复活/跃迁后都需调用（角色换新后修正会清零）。
function M.apply(player)
    if not player or not player.character then return end
    player.character_crafting_speed_modifier = M.craft_penalty
    player.character_running_speed_modifier = M.run_penalty
    player.character_mining_speed_modifier = M.mining_penalty
end

return M
