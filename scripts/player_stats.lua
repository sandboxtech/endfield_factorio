-- 玩家行为统计的数据存储。技能用的统计（craft_count/mining_count/move_distance）
-- 由 passives.lua 在对应动作事件里递增并即时施加；本文件只负责 get/默认值 +
-- 在线类统计（online_minutes 等）的采样。
-- 字段：
--   online_minutes  在线累计分钟数（每分钟采样，在线即 +1 → 金币奖励）
--   craft_count     手搓完成的物品数（→ 手搓速度技能）
--   mining_count    手动采矿/拆除次数（→ 挖矿速度技能）
--   move_distance   移动累计格数（→ 移动速度技能）
-- 个人成就类统计（只记录、不驱动技能、不展示，将来做成就/奖励再用）：
--   kill_count      亲手击杀敌人数
--   nest_count      亲手摧毁虫巢数（kill_count 的子集）
--   death_count     真实死亡数（被敌人/环境打死；脚本击杀不计）
--   warps           在线时经历的跃迁次数
--   research        在线时完成的科技研究次数
--   key_research    在线时完成的关键科技（科技瓶/延长跃迁时间）次数
--   visit_total     拜访世界【总次数】：每次发放起手装备(本世界首次拥有角色)记一次，见 players。
--   visit_<星球>    在该星球【开局】的次数（按出生星球细分）。总数与各星球计数发放时各自 +1，互不相加。
-- 数据跨跃迁保留（终身累积）。

local constants = require('scripts.constants')

local M = {}

local DEFAULTS = {
    online_minutes = 0,
    craft_count    = 0,
    mining_count   = 0,
    move_distance  = 0,
    kill_count     = 0,
    nest_count     = 0,
    death_count    = 0,
    warps          = 0,
    research       = 0,
    key_research   = 0,
    -- 拜访世界：总次数 + 5 星球开局细分（发放装备时各自 +1，不靠相加）
    visit_total    = 0,
    visit_nauvis   = 0,
    visit_vulcanus = 0,
    visit_gleba    = 0,
    visit_fulgora  = 0,
    visit_aquilo   = 0,
}

-- 星球名 → 开局统计键，按 constants.PLANETS 静态构建（不依赖玩家记录是否已有该字段，老档也正确）。
local VISIT_KEYS = {}
for _, p in ipairs(constants.PLANETS) do VISIT_KEYS[p] = 'visit_' .. p end

-- 统计按【玩家名】存储：名字跨 index 稳定，被删玩家用同名回归即自动继承，删玩家时无需动 storage。
-- storage.player_stats 由 constants.ensure_defaults 保证存在（on_init/on_configuration_changed）。
function M.get(player_index)
    storage.player_stats = storage.player_stats or {}
    local player = game.get_player(player_index)
    local key = player and player.name or player_index
    local s = storage.player_stats[key]
    if not s then
        s = {}
        for k, v in pairs(DEFAULTS) do s[k] = v end   -- 新建记录填全默认
        storage.player_stats[key] = s
    end
    return s
end

-- 新增统计字段（如 kill_count/nest_count）上线前创建的老记录没有这些键 → 直接 `s.kill_count + 1`
-- 会 nil+1 崩档。get() 只给【新建】记录填默认；老存档的存量记录用一次性 /c 脚本补齐缺失字段。

-- 某玩家某统计项 +n（默认 +1），返回累计值。供成就类统计在事件处直接调用。
function M.bump(player_index, key, n)
    local s = M.get(player_index)
    s[key] = (s[key] or 0) + (n or 1)
    return s[key]
end

-- 拜访世界：发放起手装备时调用，总次数 + 该星球开局数【各 +1】（不相加，独立计数）。
-- planet 非标准星球名时细分归入母星兜底，但总数照常 +1。
function M.bump_visit(player_index, planet)
    M.bump(player_index, 'visit_total')
    return M.bump(player_index, VISIT_KEYS[planet] or VISIT_KEYS.nauvis)
end

-- 所有在线玩家某统计项 +1：用于世界级事件（跃迁/研究）按"在线即记一次"分摊给每个在线玩家。
function M.bump_connected(key)
    for _, player in pairs(game.connected_players) do
        M.bump(player.index, key)
    end
end

-- 每分钟采样一次：所有在线玩家 online_minutes +1。
-- 由 tick.lua 的统一每分钟调度（events 总线 on_tick + 整除门控）调用，本文件不再单独注册定时器，避免覆盖。
function M.sample_online()
    for _, player in pairs(game.connected_players) do
        local s = M.get(player.index)
        s.online_minutes = s.online_minutes + 1
    end
end

-- 手搓/采矿/移动/死亡的事件处理已移到 passives.lua（在那里递增统计并即时升级技能）。

return M
