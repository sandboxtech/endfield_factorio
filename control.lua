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
require('scripts.warp_fx')

local constants = require('scripts.constants')
local reset = require('scripts.reset')

-- 第一次运行场景时触发：执行第 1 轮跃迁（默认值由 reset 内部的 ensure_defaults 补齐）。
script.on_init(function()
    game.speed = 1
    reset.reset()
end)

-- 场景脚本/版本变化后加载老存档时触发：补齐新增的默认字段，保证迁移平稳。
script.on_configuration_changed(function()
    constants.ensure_defaults()
end)
