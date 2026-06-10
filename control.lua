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
local players = require('scripts.players')

-- 第一次运行场景时触发：先 ensure_all 补齐默认/职业表/战利品权重，再执行第 1 轮跃迁（reset 内部还会再跑 ensure_defaults，幂等）。
script.on_init(function()
    game.speed = 1
    commands.ensure_all()
    players.setup_perm_groups()     -- 一次性：配置 A/C/D 默认禁用动作（之后不覆盖，管理员用 /permissions 手动调）
    reset.reset()
end)

-- 场景脚本/版本变化后加载老存档时触发：单点 ensure_all 补齐全部新增默认字段 + 迁移，保证迁移平稳。
script.on_configuration_changed(function()
    commands.ensure_all()
    players.setup_perm_groups()     -- 一次性：首次加载本版本时套用 A/C/D 默认禁用动作；之后不再覆盖
    players.migrate_perm_groups()   -- 旧权限组玩家迁移到新组（no_blueprint→A 新手、Default/voyager→C 老兵；幂等）
end)
