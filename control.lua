-- endfield_factorio scenario 入口。
-- 各子模块在 require 时自行注册 script.on_event / commands.add_command。
require('scripts.gui')
require('scripts.players')
require('scripts.surface')
require('scripts.reset')
require('scripts.research')
require('scripts.commands')
require('scripts.tick')

local reset = require('scripts.reset')

-- 第一次运行场景时触发：初始化全局参数并执行第 1 轮跃迁。
script.on_init(function()
    game.speed = 1

    storage.richness = 1
    storage.frequency = 1
    storage.size = 1
    storage.local_specialty_multiplier = 0.25

    storage.radius = 2048
    storage.radius_of = {}

    storage.platform_lifetime = 3

    reset.reset()
end)
