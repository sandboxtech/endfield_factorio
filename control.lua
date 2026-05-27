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

    reset.reset()
end)
