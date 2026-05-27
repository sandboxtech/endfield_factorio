-- 玩家生命周期：创建/加入/离开/重生/死亡。
local constants = require('scripts.constants')
local gui = require('scripts.gui')
local passives = require('scripts.passives')
local respawn_gifts = require('scripts.respawn_gifts')
local science_exp = require('scripts.science_exp')

local M = {}

-- 列出玩家所有非零科技瓶经验。broadcast=true 时用 game.print 让所有人看到。
-- 没有任何经验时静默（不打印空提示）。
function M.print_science_exp(player, broadcast)
    local sink = broadcast and game or player
    local prefix = broadcast and (player.name .. ' ') or ''
    local exp = science_exp.player_exp(player)
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
    -- 累计在线时长 → 开局金币(√在线分钟)
    local om = passives.get_stat(target.index, 'online_minutes')
    viewer.print({'wn.ability-online', om, respawn_gifts.coin_reward(om)})
    -- 每种科技瓶：总经验 + 当前发的物资 + 距下一档还差多少经验、升到多少
    for _, pack in ipairs(constants.science_packs) do
        local items = respawn_gifts.pack_gifts[pack]
        if items then
            local pexp = passives.exp_total_for_pack(target.index, pack)
            local cur = {}
            for _, item in ipairs(items) do
                cur[#cur + 1] = '[img=item/' .. item .. ']×' .. respawn_gifts.gift_count(pexp, item)
            end
            local nx = respawn_gifts.next_threshold(pexp, items)
            if nx then
                local nxt = {}
                for _, item in ipairs(items) do
                    nxt[#nxt + 1] = '[img=item/' .. item .. ']×' .. respawn_gifts.gift_count(nx, item)
                end
                viewer.print({'wn.exp-detail', pack, pexp, table.concat(cur, ' '), nx - pexp, table.concat(nxt, ' ')})
            else
                viewer.print({'wn.exp-detail-max', pack, pexp, table.concat(cur, ' ')})
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

-- 死亡复活落点：按权重随机一个星球（母星 30% / 火星·草星·雷星各 20% / 极地 10%）。
-- 确保该星球出生区已生成，传送过去，并 chart 周围 128。出生点附近无落脚处则回母星兜底。
local RESPAWN_WEIGHTS = {
    {name = 'nauvis', w = 30}, {name = 'vulcanus', w = 20}, {name = 'gleba', w = 20},
    {name = 'fulgora', w = 20}, {name = 'aquilo', w = 10},
}

local function place_on_random_planet(player)
    if not player or not player.character then return end
    local roll, acc, target = math.random(1, 100), 0, 'nauvis'
    for _, p in ipairs(RESPAWN_WEIGHTS) do
        acc = acc + p.w
        if roll <= acc then target = p.name break end
    end
    local function settle(s)
        local origin = player.force.get_spawn_position(s)
        s.request_to_generate_chunks(origin, 3)
        s.force_generate_chunk_requests()
        return s.find_non_colliding_position('character', origin, 128, 1)
    end
    local surface = game.surfaces[target] or game.surfaces.nauvis
    local pos = settle(surface)
    if not pos then   -- 该星球出生点附近无落脚处 → 回母星兜底
        surface = game.surfaces.nauvis
        pos = settle(surface) or player.force.get_spawn_position(surface)
    end
    player.teleport(pos, surface)
    -- chart 只揭示【已生成】的区块；新星球除出生点外都没生成，所以先强制生成 ±256 再 chart。
    -- （生成母星区块会触发 map_features，较重；嫌卡把这里的 8 调小，如 4=±128。）
    surface.request_to_generate_chunks(pos, 8)   -- 8 区块 ≈ 256 格
    surface.force_generate_chunk_requests()
    player.force.chart(surface, {{pos.x - 256, pos.y - 256}, {pos.x + 256, pos.y + 256}})
end

script.on_event(defines.events.on_player_respawned, function(event)
    local player = game.get_player(event.player_index)
    place_on_random_planet(player)   -- 随机星球落点 + chart 128
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
