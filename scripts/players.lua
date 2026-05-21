-- 玩家生命周期：创建/加入/离开/重生/死亡。
local constants = require('scripts.constants')
local gui = require('scripts.gui')

local M = {}

-- 列出玩家所有非零科技瓶经验。broadcast=true 时用 game.print 让所有人看到。
function M.print_science_exp(player, broadcast)
    local sink = broadcast and game or player
    -- 在 broadcast 模式下，前缀带玩家名；私聊模式下前缀为空。
    local prefix = broadcast and ('[player]' .. player.name .. ' ') or ''
    local exp = storage.science_exp and storage.science_exp[player.index]
    if not exp then
        sink.print({'wn.exp-empty', prefix})
        return
    end
    local has_any = false
    for key, val in pairs(exp) do
        if val > 0 then
            has_any = true
            local name, quality = string.match(key, '([^/]+)/(.+)')
            sink.print({'wn.exp-entry', prefix, name, quality, val})
        end
    end
    if not has_any then
        sink.print({'wn.exp-empty', prefix})
    end
end

-- 随机让玩家进入一艘己方太空平台。
function M.try_enter_space_platform(player)
    local size = table_size(game.forces.player.platforms)
    if size < 1 then
        return
    end
    local index = math.random(size)
    local i = 1
    for _, space_platform in pairs(game.forces.player.platforms) do
        if index == i and space_platform then
            player.enter_space_platform(space_platform)
            return
        end
        i = i + 1
    end
end

-- 跃迁/创建时对玩家做的状态清理。
function M.player_reset(player)
    if not player then
        return
    end
    player.disable_flashlight()
end

script.on_event(defines.events.on_player_respawned, function(event)
    local player = game.get_player(event.player_index)
    player.disable_flashlight()
end)

-- 玩家离开前死掉，避免角色尸体留在飞船里阻塞跃迁清场。
script.on_event(defines.events.on_pre_player_left_game, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    if player.character then
        player.character.die()
        -- 删除可能落在飞船原点附近的尸体
        for _, space_platform in pairs(game.forces.player.platforms) do
            if space_platform.surface then
                local corpses = space_platform.surface.find_entities_filtered {
                    area = {{-8, -8}, {8, 8}},
                    type = 'character-corpse'
                }
                for _, corpse in pairs(corpses) do
                    corpse.destroy()
                end
            end
        end
    else
        player.clear_items_inside()
    end
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    M.player_reset(player)
    gui.player_gui(player)
    M.try_enter_space_platform(player)
end)

script.on_event(defines.events.on_player_left_game, function(event)
    if not event.player then
        return
    end
    event.player.gui.top.clear()
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    gui.player_gui(player)

    local welcome
    if player.online_time > 0 then
        local last_delta = math.max(0, math.floor((game.tick - player.last_online) / constants.hour_to_tick))
        local total_time = math.max(0, math.floor(player.online_time / constants.hour_to_tick))
        welcome = {'wn.welcome-player', player.name, total_time, last_delta, player.locale}
    else
        welcome = {'wn.welcome-new-player', player.name, player.locale}
    end
    game.print(welcome)

    M.print_science_exp(player, true)
end)

return M
