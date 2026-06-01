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
require('scripts.chat')
require('scripts.roboport_limit')

local commands = require('scripts.commands')
local reset = require('scripts.reset')

-- 第一次运行场景时触发：先 ensure_all 补齐默认/职业表/战利品权重，再执行第 1 轮跃迁（reset 内部还会再跑 ensure_defaults，幂等）。
script.on_init(function()
    game.speed = 1
    commands.ensure_all()
    reset.reset()
end)

-- 场景脚本/版本变化后加载老存档时触发：单点 ensure_all 补齐全部新增默认字段 + 迁移，保证迁移平稳。
script.on_configuration_changed(function()
    commands.ensure_all()
end)
