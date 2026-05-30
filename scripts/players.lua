-- 玩家生命周期：创建/加入/离开/重生/死亡。
local constants = require('scripts.constants')
local gui = require('scripts.gui')
local passives = require('scripts.passives')
local respawn_gifts = require('scripts.respawn_gifts')
local player_stats = require('scripts.player_stats')

local M = {}

-- 复活等待时间改由 storage 配置（可 /c storage.respawn_ticks / enemy_respawn_ticks 热改、持久、同步）；
-- 默认值见 constants.ensure_defaults（respawn_ticks=180=3 秒，enemy_respawn_ticks=1800=30 秒）。

-- 把 target 的统计数据打印给 viewer：4 项技能 + 在线时长 + 各瓶累计经验。
function M.print_inspection(target, viewer)
    viewer.print({'wn.inspect-header', target.name})
    -- 人物等级 = 开局金币 = floor(√在线分钟)；升到下一级需 (等级+1)² 分钟在线
    local om = passives.get_stat(target.index, 'online_minutes')
    local lv = respawn_gifts.coin_reward(om)
    viewer.print({'wn.ability-online', om, lv, (lv + 1) * (lv + 1) - om})
    -- 角色技能（实时值，每次 /inspect 现算）：手搓/移动/挖矿/生命
    for _, ab in ipairs(passives.abilities) do
        local val = passives.get_stat(target.index, ab.stat)
        viewer.print({ab.locale, math.floor(val), ab.fmt(passives.skill_factor(target.index, ab))})
    end
    -- 每种科技瓶：等级(0-1000) + 当前开局奖励 + 还差多少经验升级（仿人物等级那一行，去掉繁琐的下一档预览）
    for _, pack in ipairs(constants.science_packs) do
        local items = respawn_gifts.pack_gifts[pack]
        if items then
            local pexp = passives.exp_total_for_pack(target.index, pack)
            local lv = respawn_gifts.pack_level(pexp)
            local cur = {}
            for _, item in ipairs(items) do
                cur[#cur + 1] = '[img=item/' .. item .. ']×' .. respawn_gifts.gift_count(pexp, item)
            end
            local nx = respawn_gifts.exp_for_next_level(pexp)
            if nx then
                viewer.print({'wn.exp-detail', pack, lv, table.concat(cur, ' '), pexp, nx - pexp})
            else
                viewer.print({'wn.exp-detail-max', pack, lv, table.concat(cur, ' '), pexp})
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

-- 死亡处理：先把玩家移到【当前所在表面】的出生点再杀死 —— 尸体(背包货物)留在当前星球，
-- 不会被带回母星（杜绝"在外星捡货 → /suicide 把货带回母星"）。复活点设到母星，复活由 on_player_respawned 统一送回。
-- 用于所有"杀死玩家"的入口（跃迁清场 / 自杀 / 离场 / 投票等）。无 character 时跳过。
function M.kill_on_nauvis(player)
    if not player or not player.character then return end
    local force = player.force
    -- ① 在当前表面出生点处死亡（尸体留在当前星球）
    local surface = player.surface
    local origin = force.get_spawn_position(surface)
    local pos = surface.find_non_colliding_position('character', origin, 64, 1) or origin
    player.teleport(pos, surface)
    -- ② 复活点设回母星（on_player_respawned 也会兜底把玩家送回母星出生点）
    local nauvis = game.surfaces['nauvis']
    if nauvis then
        local norigin = force.get_spawn_position(nauvis)
        force.set_spawn_position(nauvis.find_non_colliding_position('character', norigin, 64, 1) or norigin, nauvis)
    end
    -- ③ 杀死
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

-- 把玩家安全送到【指定星球】出生点：先生成出生区块、找无碰撞落点、传送，再揭图周围 256。
-- 复活落点(place_on_nauvis) 与 /前往星球 命令共用。无 character 或星球不存在则跳过。
function M.place_on_surface(player, surface_name)
    if not player or not player.character then return end
    local surface = game.surfaces[surface_name]
    if not surface then return end
    local origin = player.force.get_spawn_position(surface)
    surface.request_to_generate_chunks(origin, 3)   -- 仅【异步排队】生成出生区，不强制同步（避免卡顿）
    local pos = surface.find_non_colliding_position('character', origin, 128, 1) or origin
    player.teleport(pos, surface)
    -- 玩家落地后，引擎会自动在其周围生成区块；这里只异步排队 + chart（chart 只揭示已生成的区块）。
    surface.request_to_generate_chunks(pos, 8)   -- 8 区块 ≈ 256 格（异步，不强制）
    player.force.chart(surface, {{pos.x - 256, pos.y - 256}, {pos.x + 256, pos.y + 256}})
end

-- 死亡复活落点：一律回母星 nauvis 出生点（不再随机散落到各星球）——
-- 被杀/下线/自杀/warp 死亡的玩家都回家集结。
local function place_on_nauvis(player)
    M.place_on_surface(player, 'nauvis')
end

-- 死亡：把复活倒计时压到 3 秒；只把【有 cause 的真实死亡】（被敌人/环境打死）计入该玩家 death_count，
-- 跃迁清场 / 离场 / 自杀脱困走的是脚本 die()（cause 为 nil），不计入。
script.on_event(defines.events.on_player_died, function(event)
    local player = game.get_player(event.player_index)
    local cause = event.cause
    -- 被【敌方】打死 → 30 秒复活惩罚；脚本死亡(跃迁清场/离场/自杀, cause 为 nil)与环境死亡 → 默认 3 秒。
    local by_enemy = cause and cause.valid and cause.force and cause.force.name == 'enemy'
    if player then
        player.ticks_to_respawn = by_enemy and (storage.enemy_respawn_ticks or 1800) or (storage.respawn_ticks or 180)
    end
    if by_enemy then
        -- 被敌方打死：本轮跃迁倒计时提前（默认 1 分钟，可 /c storage.enemy_death_push_minutes 热改）
        storage.warp_hours = (storage.warp_hours or 1) - (storage.enemy_death_push_minutes or 1) / 60
        gui.refresh_countdown()   -- 倒计时已变 → 立刻刷新所有人头顶 UI
    end
    if cause then player_stats.bump(event.player_index, 'death_count') end
end)

script.on_event(defines.events.on_player_respawned, function(event)
    local player = game.get_player(event.player_index)
    place_on_nauvis(player)   -- 一律回母星出生点 + chart 256
    player.disable_flashlight()
    passives.apply(player)
    respawn_gifts.apply_inventory_bonus(player)   -- 背包格数加成（按赠品总组数，每组 +1 格）
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
    respawn_gifts.apply_inventory_bonus(player)   -- 背包格数加成（按赠品总组数，每组 +1 格）
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
end)

return M
