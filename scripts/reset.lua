-- 跃迁主流程：清场 → 重置玩家/科技 → 随机新参数。
local constants = require('scripts.constants')
local util = require('scripts.util')
local gui = require('scripts.gui')
local players = require('scripts.players')
local passives = require('scripts.passives')
local science_exp = require('scripts.science_exp')

local M = {}

-- 每次跃迁后所有星球被清空、重建，玩家死亡，飞船保留一周期。
-- storage.run 从 1 开始计数（on_init 中会调用一次 reset()，对应第 1 轮）。
function M.reset()
    game.speed = 1
    constants.ensure_defaults()   -- 补齐默认值：新档初始化 / 老档迁移 / 每轮兜底（幂等，不覆盖已调参数）
    storage.run = (storage.run or 0) + 1

    local last_run_ticks = (game.tick - (storage.run_start_tick or game.tick))
    game.print({'wn.warp-success-time',
                math.floor(last_run_ticks / constants.hour_to_tick),
                math.floor(last_run_ticks / constants.min_to_tick) % 60})
    storage.run_start_tick = game.tick

    -- 飞船老化：storage.platform_age[idx] 记录该平台已经历的跃迁次数。
    -- 每次跃迁计数 +1，并在船名前追加一个 skull 作为可视化倒计时；
    -- 计数超过 storage.platform_lifetime 时摧毁。（默认值见 constants.ensure_defaults）
    for _, space_platform in pairs(game.forces.player.platforms) do
        local age = (storage.platform_age[space_platform.index] or 0) + 1
        space_platform.name = '[virtual-signal=signal-skull]' .. space_platform.name
        if age > storage.platform_lifetime then
            storage.platform_age[space_platform.index] = nil
            space_platform.destroy()
            game.print({'wn.platform-destroyed', space_platform.name})
        else
            storage.platform_age[space_platform.index] = age
            game.print({'wn.platform-aged', space_platform.name})
        end
    end

    -- 先扫描所有在线玩家的科技瓶累积经验（必须在清背包之前），同时统计本轮结算
    local summaries = {}
    for _, player in pairs(game.players) do
        local gain = science_exp.collect(player)
        if gain then
            local total, parts = 0, {}
            for _, pack in ipairs(constants.science_packs) do
                if (gain[pack] or 0) > 0 then
                    total = total + gain[pack]
                    parts[#parts + 1] = '[img=item/' .. pack .. ']+' .. gain[pack]
                end
            end
            if total > 0 then
                summaries[#summaries + 1] = {name = player.name, total = total, detail = table.concat(parts, '  ')}
            end
        end
    end
    -- 本轮结算：按本轮带走经验从多到少广播（顺带成了小排行榜）
    if #summaries > 0 then
        table.sort(summaries, function(a, b) return a.total > b.total end)
        game.print({'wn.summary-title'})
        for _, s in ipairs(summaries) do
            game.print({'wn.summary-player', s.name, s.total, s.detail})
        end
    end

    -- 清理长期不活跃玩家（3 天没上线）：删除其玩家对象，释放蓝图/快捷键等存档膨胀。
    -- 经验/统计按【名字】存储（player_stats / science_exp），删玩家不动这些数据；
    -- 玩家用同名回归时自动继承。
    local INACTIVE_TICKS = 3 * 86400 * 60   -- 3 天（1 天 = 86400 秒 × 60 tick）
    local stale = {}
    for _, player in pairs(game.players) do
        if not player.connected and (game.tick - player.last_online) > INACTIVE_TICKS then
            stale[#stale + 1] = player
        end
    end
    if #stale > 0 then
        game.remove_offline_players(stale)
    end

    -- 重置所有玩家（含飞船上的）：有 character 的传送回母星并杀死 → 在母星复活领奖励；
    -- 否则清空背包。这样每轮跃迁人人重置、背包必空，杜绝"待在飞船上跨轮保留背包、反复白嫖经验"。
    -- 飞船本身仍按 platform_lifetime 老化（见上方循环），与玩家死亡解耦。
    for _, player in pairs(game.players) do
        if player.surface then
            local inventory = player.get_inventory(defines.inventory.character_main)
            if player.character then
                players.kill_on_nauvis(player)
            elseif inventory then
                inventory.clear()
            else
                player.clear_items_inside()
            end
            players.player_reset(player)
        end
    end


    -- 清空所有星球上的地图标记
    for _, surface in pairs(game.surfaces) do
        for _, tag in pairs(game.forces.player.find_chart_tags(surface)) do
            tag.destroy()
        end
    end

    -- 清空星球（会触发 surface.lua 的 on_surface_cleared 重新生成）
    for _, surface_name in pairs({'nauvis', 'vulcanus', 'gleba', 'fulgora', 'aquilo'}) do
        if game.surfaces[surface_name] ~= nil then
            game.surfaces[surface_name].clear(true)
        end
    end

    local force = game.forces.player

    -- 科技进度全部清零，不再保留无限科技 level
    force.reset()
    force.friendly_fire = true

    -- 跃迁倒计时重置为 30 分钟(0.5 小时)，需研究科技瓶相关科技来延长（每项 +1 小时）
    storage.warp_hours = 0.5

    -- 飞船全部瞬移回母星轨道并暂停
    for _, platform in pairs(force.platforms) do
        platform.space_location = 'nauvis'
        platform.paused = true
    end

    game.reset_time_played()

    -- 污染/敌人/腐败等【影响玩法节奏】的全局参数：大概率正常值，小概率小幅偏离（util.mostly_normal）。
    -- 不再大幅随机——极端的污染/虫子/腐败速度会毁掉一局的可玩性。（difficulty 默认值见 constants.ensure_defaults）
    game.forces.enemy.reset_evolution()
    game.map_settings.enemy_expansion.enabled = false
    game.map_settings.pollution.enabled = true
    game.map_settings.pollution.ageing = util.mostly_normal()
    game.map_settings.pollution.enemy_attack_pollution_consumption_modifier =
        util.mostly_normal() / storage.difficulty

    game.map_settings.asteroids.spawning_rate = util.mostly_normal()
    game.difficulty_settings.spoil_time_modifier = util.mostly_normal()   -- 腐败速度：大概率正常
    game.difficulty_settings.technology_price_multiplier = 2              -- 每个世界科技成本恒为 2 倍

    -- 经验更新后，对所有有 character 的玩家重算被动加成
    -- （星球上的会随 on_player_respawned 自然触发；飞船上的需要在这里手动应用）
    for _, player in pairs(game.connected_players) do
        passives.apply(player)
    end

    gui.players_gui()
end

return M
