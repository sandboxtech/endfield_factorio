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

local constants = require('scripts.constants')
local classes = require('scripts.classes')
local map_features = require('scripts.map_features')
local reset = require('scripts.reset')

-- 第一次运行场景时触发：执行第 1 轮跃迁（默认值由 reset 内部的 ensure_defaults 补齐）。
script.on_init(function()
    game.speed = 1
    classes.ensure()            -- 默认职业表写入 storage.classes（之后可 /c 动态改）
    map_features.ensure_loot()  -- 默认战利品权重写入 storage.loot_weights（之后可 /c 动态改）
    reset.reset()
end)

-- 场景脚本/版本变化后加载老存档时触发：补齐新增的默认字段，保证迁移平稳。
script.on_configuration_changed(function()
    constants.ensure_defaults()
    classes.ensure()            -- 老存档补 storage.classes（缺失才补，保留 /c 已改的）
    map_features.ensure_loot()  -- 老存档补 storage.loot_weights
end)
