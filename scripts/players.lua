-- 玩家生命周期：创建/加入/离开/重生/死亡。
local constants = require('scripts.constants')
local gui = require('scripts.gui')
local passives = require('scripts.passives')
local respawn_gifts = require('scripts.respawn_gifts')

local M = {}

-- 列出玩家所有非零科技瓶经验。broadcast=true 时用 game.print 让所有人看到。
-- 没有任何经验时静默（不打印空提示）。
function M.print_science_exp(player, broadcast)
    local sink = broadcast and game or player
    local prefix = broadcast and (player.name .. ' ') or ''
    local exp = storage.science_exp and storage.science_exp[player.index]
    if not exp then return end
    for pack, val in pairs(exp) do
        if val > 0 then
            sink.print({'wn.exp-entry', prefix, pack, val})
        end
    end
end

-- 把 target 的统计数据打印给 viewer：4 项技能 + 在线时长 + 各瓶累计经验。
function M.print_inspection(target, viewer)
    viewer.print({'wn.inspect-header', target.name})
    -- 角色技能（实时值，每次 /inspect 现算）：手搓/移动/挖矿/生命
    for _, ab in ipairs(passives.abilities) do
        local val = passives.get_stat(target.index, ab.stat)
        viewer.print({ab.locale, math.floor(val), ab.fmt(passives.skill_factor(target.index, ab))})
    end
    -- 累计在线时长（统计，不再换金币）
    viewer.print({'wn.ability-online', passives.get_stat(target.index, 'online_minutes')})
    -- 科技瓶经验（→ 下次开局直接发的代表物资）
    local exp = storage.science_exp and storage.science_exp[target.index]
    if exp then
        local prefix = target.name .. ' '
        for pack, val in pairs(exp) do
            if val > 0 then
                viewer.print({'wn.exp-entry', prefix, pack, val})
            end
        end
    end
end


-- 跃迁/创建时对玩家做的状态清理。
function M.player_reset(player)
    if not player then
        return
    end
    player.disable_flashlight()
end

-- 把玩家瞬移到母星上一个无碰撞位置，更新 force 的复活点为该位置，然后杀死。
-- 用于所有需要"死亡 → 在母星合适位置复活"的入口。无 character 时跳过。
function M.kill_on_nauvis(player)
    if not player or not player.character then return end
    local nauvis = game.surfaces['nauvis']
    if nauvis then
        local force = player.force
        local origin = force.get_spawn_position(nauvis)
        local pos = nauvis.find_non_colliding_position('character', origin, 64, 1) or origin
        force.set_spawn_position(pos, nauvis)
        player.teleport(pos, nauvis)
    end
    player.character.die()
end

-- 玩家本世界（storage.run）首次拥有 character 时发放起手装备 + 经验奖励。
-- 同时被 on_player_created（开局直接领）和 on_player_respawned（跃迁后第一次死亡复活）调用。
local function try_gift_first_in_world(player)
    if not player or not player.character then return end
    storage.last_respawn_run = storage.last_respawn_run or {}
    if storage.last_respawn_run[player.index] == storage.run then return end
    storage.last_respawn_run[player.index] = storage.run
    respawn_gifts.on_first_respawn(player)
end

script.on_event(defines.events.on_player_respawned, function(event)
    local player = game.get_player(event.player_index)
    player.disable_flashlight()
    passives.apply(player)
    try_gift_first_in_world(player)
end)

-- 玩家离开前死掉，避免角色尸体留在飞船里阻塞跃迁清场。
script.on_event(defines.events.on_pre_player_left_game, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    if player.character then
        M.kill_on_nauvis(player)
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
    passives.apply(player)
    try_gift_first_in_world(player)
end)

script.on_event(defines.events.on_player_left_game, function(event)
    if not event.player then
        return
    end
    event.player.gui.top.clear()
    -- 离线后名册变了，刷新所有人 HUD
    gui.players_gui()
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    -- 名册变了，刷新所有人 HUD（自然包含自己）
    gui.players_gui()

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
