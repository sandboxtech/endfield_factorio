-- 跃迁主流程：清场 → 重置玩家/科技 → 随机新参数。
local constants = require('scripts.constants')
local util = require('scripts.util')
local gui = require('scripts.gui')
local players = require('scripts.players')

local M = {}

-- 扫描在线玩家背包里的科技瓶，按品质和"组数"换算成经验存入 storage.science_exp。
-- 必须在玩家被杀/背包被清空之前调用。
local function collect_science_exp(player)
    if not player.connected then return end
    local inventory = player.get_inventory(defines.inventory.character_main)
    if not inventory then return end

    storage.science_exp = storage.science_exp or {}
    storage.science_exp[player.index] = storage.science_exp[player.index] or {}
    local player_exp = storage.science_exp[player.index]

    for _, item in pairs(inventory.get_contents()) do
        if string.sub(item.name, -13) == '-science-pack' then
            local proto = prototypes.item[item.name]
            local mult = constants.quality_exp[item.quality] or 0
            if proto and mult > 0 then
                local gained = math.floor(item.count / proto.stack_size) * mult
                if gained > 0 then
                    local key = item.name .. '/' .. item.quality
                    player_exp[key] = (player_exp[key] or 0) + gained
                    player.print({'wn.exp-gain', item.name, item.quality, gained})
                end
            end
        end
    end
end

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

    -- 飞船老化：storage.platform_age[idx] 记录该平台已经历的跃迁次数。
    -- 每次跃迁计数 +1，并在船名前追加一个 skull 作为可视化倒计时；
    -- 计数超过 storage.platform_lifetime 时摧毁。
    storage.platform_age = storage.platform_age or {}
    storage.platform_lifetime = storage.platform_lifetime or 3
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

    -- 先扫描所有在线玩家的科技瓶累积经验（必须在清背包之前）
    for _, player in pairs(game.players) do
        collect_science_exp(player)
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

    -- 科技进度全部清零，不再保留无限科技 level
    force.reset()
    force.friendly_fire = true

    -- 跃迁倒计时重置为 1 小时，需研究科技瓶相关科技来延长
    storage.warp_hours = 1

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
