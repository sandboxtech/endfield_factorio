-- 跃迁主流程：清场 → 重置玩家/科技 → 随机新参数。
local constants = require('scripts.constants')
local util = require('scripts.util')
local gui = require('scripts.gui')
local players = require('scripts.players')

local M = {}

-- 每次跃迁后所有星球被清空、重建，玩家死亡，飞船保留一周期。
-- storage.run 从 1 开始计数（on_init 中会调用一次 reset()，对应第 1 轮）。
function M.reset()
    game.speed = 1
    storage.run = (storage.run or 0) + 1

    local last_run_ticks = (game.tick - (storage.run_start_tick or game.tick))
    game.print({'wn.warp-success-time',
                math.floor(last_run_ticks / constants.hour_to_tick),
                math.floor(last_run_ticks / constants.min_to_tick) % 60})
    storage.run_start_tick = game.tick

    -- 飞船存活两个跃迁周期：本轮首次见到的标 skull，第二次见到时摧毁。
    -- 玩家可借此提前撤离即将报废的飞船。
    storage.rust = storage.rust or {}
    for _, space_platform in pairs(game.forces.player.platforms) do
        if not storage.rust[space_platform.index] then
            storage.rust[space_platform.index] = true
            space_platform.name = '[virtual-signal=signal-skull]' .. space_platform.name
            game.print({'wn.about-to-rust-notice', space_platform.name})
        else
            storage.rust[space_platform.index] = nil
            space_platform.destroy()
            game.print({'wn.rust-destroy-notice', space_platform.name})
        end
    end

    -- 重置玩家：在星球上的杀死/清空背包，在飞船上的保留（飞船能存活一周期）
    for _, player in pairs(game.players) do
        if player.surface and not player.surface.platform then
            local inventory = player.get_inventory(defines.inventory.character_main)
            if player.character then
                player.character.die()
            elseif inventory then
                inventory.clear()
            else
                player.clear_items_inside()
            end
            players.player_reset(player)
        end
    end

    -- trait 列表从头开始，首项放本轮标题
    storage.traits = {'', {'wn.traits-title', storage.run}}

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

    -- force.reset() 会清掉所有科技进度，先记录无限科技 level，重置后再恢复。
    storage.infinite_tech_levels = storage.infinite_tech_levels or {}
    for _, tech_name in pairs(constants.persistent_infinite_tech_names) do
        local tech = force.technologies[tech_name]
        storage.infinite_tech_levels[tech_name] = math.max(tech.prototype.level, tech.level)
    end

    force.reset()
    force.friendly_fire = true

    for _, tech_name in pairs(constants.persistent_infinite_tech_names) do
        force.technologies[tech_name].level = storage.infinite_tech_levels[tech_name]
    end

    -- 飞船全部瞬移回母星轨道并暂停
    for _, platform in pairs(force.platforms) do
        platform.space_location = 'nauvis'
        platform.paused = true
    end

    game.reset_time_played()

    -- 母星污染/敌人参数随机化
    storage.difficulty = storage.difficulty or 1
    game.forces.enemy.reset_evolution()
    game.map_settings.enemy_expansion.enabled = false
    game.map_settings.pollution.enabled = true
    game.map_settings.pollution.ageing = util.readable(util.random_exp(4))
    game.map_settings.pollution.enemy_attack_pollution_consumption_modifier =
        util.readable(util.random_exp(3)) / storage.difficulty
    util.try_add_trait({'wn.galaxy-trait-pollution-ageing', game.map_settings.pollution.ageing})
    util.try_add_trait({'wn.galaxy-trait-enemy_attack_pollution_consumption_modifier',
                        game.map_settings.pollution.enemy_attack_pollution_consumption_modifier})

    game.map_settings.asteroids.spawning_rate = util.readable(util.random_exp(4))
    game.difficulty_settings.spoil_time_modifier = util.readable(0.5 + util.random_exp(4))
    game.difficulty_settings.technology_price_multiplier = 1

    util.try_add_trait({'', '\n',
                        {'wn.galaxy-trait-spawning_rate', game.map_settings.asteroids.spawning_rate},
                        {'wn.galaxy-trait-spoil_time_modifier', game.difficulty_settings.spoil_time_modifier}})

    gui.players_gui()
end

return M
