-- 跃迁主流程：清场 → 重置玩家/科技 → 随机新参数。
local constants = require('scripts.constants')
local util = require('scripts.util')
local gui = require('scripts.gui')
local players = require('scripts.players')
local passives = require('scripts.passives')
local science_exp = require('scripts.science_exp')
local respawn_gifts = require('scripts.respawn_gifts')
local player_stats = require('scripts.player_stats')
local map_features = require('scripts.map_features')   -- 本轮危险度 knobs().danger（敌人伤害缩放用）

local M = {}

-- ── 飞船命数前缀（剩余跃迁次数的可视化）─────────────────────────────────────
local HEART = '[img=virtual-signal/signal-heart]'
-- 数字 → parameter 物品图标串（逐位，用 img= 形式）：4 → [img=item/parameter-4]；10 → [img=item/parameter-1][img=item/parameter-0]。
-- 最多两位（parameter 图标只有 0~9）；>99 一律按 99 显示。
local function life_prefix(n)
    if n > 99 then n = 99 end
    local s, out = tostring(n), {}
    for i = 1, #s do out[i] = '[img=item/parameter-' .. s:sub(i, i) .. ']' end
    return table.concat(out) .. HEART
end
-- 反复剥掉船名开头的【命数(parameter)/心】前缀，以及老存档遗留的【骷髅】串 → 得到纯船名。
local function strip_life_prefix(name)
    local pats = {
        '^%[img=item/parameter%-%d%]',               -- 命数数字：life_prefix 产出并被引擎规范化后的 [img=item/parameter-N]（用 img= 而非 item=，否则剥不掉 → 每轮累加）
        '^%[item=parameter%-%d%]',                   -- 兼容：万一某处仍是 [item=parameter-N] 未规范化
        '^%[img=parameter%/%d+%]',                   -- 兼容更老格式
        '^%[img=virtual%-signal/signal%-heart%]',
        '^%[img=virtual%-signal/signal%-skull%]',   -- 兼容旧版累积的骷髅前缀
    }
    local again = true
    while again do
        again = false
        for _, p in ipairs(pats) do
            local n, cnt = name:gsub(p, '', 1)
            if cnt > 0 then name = n; again = true end
        end
    end
    return name
end

-- 每次跃迁后所有星球被清空、重建，玩家死亡，飞船保留一周期。
-- storage.run 从 1 开始计数（on_init 中会调用一次 reset()，对应第 1 轮）。
function M.reset()
    game.speed = 1
    constants.ensure_defaults()   -- 补齐默认值：新档初始化 / 老档迁移 / 每轮兜底（幂等，不覆盖已调参数）
    storage.run = (storage.run or 0) + 1
    player_stats.bump_connected('warps')   -- 给当前在线玩家各记一次"经历的跃迁"

    -- 跃迁时：人物等级(=floor√在线分钟) ≥ 50 的【在线】玩家自动成为会员（会员名单按玩家名存，见 commands.is_member）。
    storage.members = storage.members or {}
    for _, player in pairs(game.connected_players) do
        local om = player_stats.get(player.index).online_minutes or 0
        if respawn_gifts.coin_reward(om) >= 50 and not storage.members[player.name] then
            storage.members[player.name] = true
            game.print({'wn.member-granted', player.name})
        end
    end

    local last_run_ticks = (game.tick - (storage.run_start_tick or game.tick))
    game.print({'wn.warp-success-time',
                math.floor(last_run_ticks / constants.hour_to_tick),
                math.floor(last_run_ticks / constants.min_to_tick) % 60})
    storage.run_start_tick = game.tick

    -- 飞船老化：storage.platform_age[idx] 记录该平台已经历的跃迁次数。每次跃迁 +1。
    -- 在船名前打【剩余命数 + 心】前缀(如 [item=parameter-4][virtual-signal=signal-heart] = 还剩 4 条命)，
    -- 直观且只占一格；已有旧前缀(命数/心，或老存档遗留的骷髅串)则先剥掉再换新。
    -- 命数 = lifetime - age + 1（在世恒 ≥1）；age 超过 lifetime 即摧毁。（默认值见 constants.ensure_defaults）
    for _, space_platform in pairs(game.forces.player.platforms) do
        local age = (storage.platform_age[space_platform.index] or 0) + 1
        local base = strip_life_prefix(space_platform.name)
        if age > storage.platform_lifetime then
            storage.platform_age[space_platform.index] = nil
            space_platform.destroy()
            game.print({'wn.platform-destroyed', base})
        else
            storage.platform_age[space_platform.index] = age
            local lives = storage.platform_lifetime - age + 1
            space_platform.name = life_prefix(lives) .. base   -- 只更新船名前缀(剩余命数)，不再广播"完成跃迁"
        end
    end

    -- 先扫描所有在线玩家的科技瓶累积经验（collect 必须在清背包之前），同时统计本轮结算。
    -- 排行榜【存进 storage 保留上一个世界】（/lastrank 可查），广播则延迟到下方【杀玩家之后】再打印。
    local summaries = {}
    for _, player in pairs(game.players) do
        local gain = science_exp.collect(player)
        if gain then
            -- gain 是各瓶经验（瓶数×品质），直接显示（%g 去掉多余小数）。
            local total, parts = 0, {}
            for _, pack in ipairs(constants.science_packs) do
                if (gain[pack] or 0) > 0 then
                    total = total + gain[pack]
                    parts[#parts + 1] = '[img=item/' .. pack .. ']+' .. string.format('%g', gain[pack])
                end
            end
            if total > 0 then
                summaries[#summaries + 1] = {name = player.name, total = total, detail = table.concat(parts, '  ')}
            end
        end
    end
    -- 按本轮带走经验从多到少排序后存档：storage.last_leaderboard 只保留【上一个世界】这一份，
    -- 每次跃迁覆盖，供 /lastrank（/排行）随时查看。广播见下方杀玩家之后。
    table.sort(summaries, function(a, b) return a.total > b.total end)
    storage.last_leaderboard = summaries
    storage.last_leaderboard_run = storage.run - 1   -- 这份排行属于【刚结束的那个世界】(run 上面已 +1，故 -1)

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

    -- 重置所有玩家（含飞船上的）：有 character 的在当前星球杀死(尸体留当地) → 在其复活星球复活领奖励；
    -- 否则清空背包。这样每轮跃迁人人重置、背包必空，杜绝"待在飞船上跨轮保留背包、反复白嫖经验"。
    -- 飞船本身仍按 platform_lifetime 老化（见上方循环），与玩家死亡解耦。
    for _, player in pairs(game.players) do
        if player.surface then
            local inventory = player.get_inventory(defines.inventory.character_main)
            if player.character then
                players.kill_player(player)
            elseif inventory then
                inventory.clear()
            else
                player.clear_items_inside()
            end
            players.player_reset(player)
        end
    end

    -- 本轮结算广播：延迟到【杀死玩家之后】才打印，避免被满屏死亡/复活提示顶掉。
    -- （排行榜已在上方存进 storage.last_leaderboard，保留上一个世界，/lastrank 可查。）
    if #summaries > 0 then
        game.print({'wn.summary-title'})
        for _, s in ipairs(summaries) do
            game.print({'wn.summary-player', s.name, s.total, s.detail})
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
    force.friendly_fire = false   -- 禁止友军伤害：玩家的武器/爆炸不再伤到自家(同 force)建筑与队友
    force.maximum_following_robots_count = 50   -- 战斗无人机跟随上限提到 50（force.reset 会打回默认，故每次跃迁后重设）

    -- 每次跃迁后自动解锁所有星球：无需研究 planet-discovery 科技即可前往。
    -- 必须放在 force.reset() 之后，reset 会清空科技/解锁状态，先解锁会被冲掉。
    for name in pairs(game.planets) do
        force.unlock_space_location(name)
    end
    -- 同时把四个星球的【发现科技】直接标记为已研究（科技树里显示已发现）。
    for _, planet in ipairs({'vulcanus', 'gleba', 'fulgora', 'aquilo'}) do
        local tech = force.technologies['planet-discovery-' .. planet]
        if tech then tech.researched = true end
    end

    -- （科技世界已并入事件世界：tech 现作为事件类型之一，由 surface.lua 的事件世界 roll 按星球抽中、
    --   tick.lua 的 run_world_events 按事件机制每分钟触发，不再这里单独全局 roll。）

    -- 跃迁倒计时重置为初始值（storage.warp_initial_minutes 分钟，可 /c 热改）；研究科技瓶科技按
    -- storage.warp_extend_minutes 各自延长。内部以小时记账，故 /60。
    storage.warp_hours = (storage.warp_initial_minutes or 10) / 60
    storage.warp_vote = {}        -- 新世界清空跃迁投票（上一世界的同意/反对作废）
    storage.warp_vote_delta = nil -- 投票缩减量作废（warp_hours 已重置，无可恢复）

    -- 本轮【能否前往各外星球】独立滚定：母星恒开，其余 4 星各自按 storage.travel_chance[星球](默认50%) 概率开放。
    -- 仅 travel_enabled 总开关开启时这套才生效（见 commands.travel / gui 按钮）。
    storage.travel_open = {nauvis = true}
    local tc = storage.travel_chance or {}
    for _, planet in ipairs({'vulcanus', 'gleba', 'fulgora', 'aquilo'}) do
        storage.travel_open[planet] = math.random() < (tc[planet] or 0.5)
    end
    storage.chat_bubble = {} -- 清空聊天气泡引用（角色已死、气泡已随之销毁，避免残留无效引用）

    -- 飞船全部瞬移回母星轨道并暂停；顺带清空各平台 surface 上的所有陨石(asteroid + asteroid-chunk)，
    -- 避免上一轮飞来的陨石跨轮残留/继续砸船。
    for _, platform in pairs(force.platforms) do
        platform.space_location = 'nauvis'
        platform.paused = true
        local psurface = platform.surface
        if psurface and psurface.valid then
            for _, a in pairs(psurface.find_entities_filtered{type = {'asteroid', 'asteroid-chunk'}}) do
                a.destroy()
            end
        end
    end

    game.reset_time_played()

    -- 污染/敌人/腐败等【影响玩法节奏】的全局参数：大概率正常值，小概率小幅偏离（util.mostly_normal）。
    -- 不再大幅随机，极端的污染/虫子/腐败速度会毁掉一局的可玩性。（difficulty 默认值见 constants.ensure_defaults）
    game.forces.enemy.reset_evolution()

    -- 本世界【敌人武器伤害】随危险度 knobs().danger 缩放（danger 多半低 → 多数世界小幅加成，偶尔高危世界重伤）。
    -- 加法修正 = danger × enemy_dmg_scale（0=原版伤害、1=+100%）。对敌方常见弹种(机枪/激光/喷火塔+虫/沙虫)生效。
    local dmg = map_features.knobs().danger * (storage.enemy_dmg_scale or 2)
    for _, cat in ipairs({'bullet', 'laser', 'flamethrower', 'melee', 'biological', 'rocket', 'electric', 'tesla', 'capsule', 'grenade'}) do
        if prototypes.ammo_category[cat] then game.forces.enemy.set_ammo_damage_modifier(cat, dmg) end
    end

    -- 本世界"玩家消灭虫巢获随机科技"的概率
    storage.nest_tech_chance = 0.001 + math.random() * 0.009

    game.map_settings.enemy_expansion.enabled = false
    game.map_settings.pollution.enabled = true
    game.map_settings.pollution.ageing = util.mostly_normal()
    game.map_settings.pollution.enemy_attack_pollution_consumption_modifier =
        util.mostly_normal() / storage.difficulty

    game.map_settings.asteroids.spawning_rate = util.mostly_normal()
    game.difficulty_settings.spoil_time_modifier = util.mostly_normal()   -- 腐败速度：大概率正常
    game.difficulty_settings.technology_price_multiplier = 2              -- 每个世界科技成本恒为 2 倍

    -- 对在线玩家重算速度技能 + 背包格数加成（星球上的会随 on_player_respawned 自然触发；飞船上的在此手动应用）。
    for _, player in pairs(game.connected_players) do
        passives.apply(player)
        respawn_gifts.apply_inventory_bonus(player)
    end

    gui.players_gui()

    -- 返回本轮是否有人拿到科技瓶经验（summaries 只收 total>0 的玩家）→ 供 warp_fx 选成功/普通音效。
    return #summaries > 0
end

return M
