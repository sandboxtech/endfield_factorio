-- endfield_factorio scenario 入口。
-- 各子模块在 require 时自行注册 script.on_event / commands.add_command。
require('scripts.gui')
require('scripts.player_stats')
require('scripts.players')
require('scripts.surface')
require('scripts.market')
require('scripts.reset')
require('scripts.research')
require('scripts.rocket')
require('scripts.commands')
require('scripts.tick')
require('scripts.world_fx')

local reset = require('scripts.reset')

-- 第一次运行场景时触发：初始化全局参数并执行第 1 轮跃迁。
script.on_init(function()
    game.speed = 1

    storage.richness_multiplier = 4   -- 矿更富（每格储量）
    storage.size_multiplier = 1       -- 矿脉大小正常（=1 才不会糊成巨型矿区）
    storage.frequency_multiplier = 1  -- 矿脉数量正常
    storage.local_specialty_multiplier = 0.25

    storage.radius = 2048
    storage.radius_of = {}

    storage.platform_lifetime = 3
    storage.warp_hours = 0.5   -- 初始跃迁倒计时 30 分钟
    storage.science_exp = {}
    storage.player_stats = {}

    -- 调试与"世界变体"调参常量（游戏内 /c storage.xxx=N 动态调；0=关，1=默认，调大=更多/更强）：
    storage.debug = true              -- 向管理员打印每次世界生成的属性（tile 替换/染地/危险等）
    -- 出现概率（乘数，0=关闭该变体）
    storage.prob_ground_tint = 1      -- 染地世界
    storage.prob_tile_remap = 1       -- tile 替换世界
    storage.prob_danger = 1           -- 危险世界
    storage.prob_event = 1            -- 每分钟事件世界
    -- 强度/数量
    storage.danger_density = 1        -- 危险世界里敌人/残骸的密度
    storage.event_intensity = 1       -- 每分钟事件的落点数
    storage.tile_remap_rules = 6      -- tile 替换世界最多几条规则
    storage.test_chest_chance = 0.1  -- 战利品箱是测试箱(永续/无底)的概率

    reset.reset()
end)
