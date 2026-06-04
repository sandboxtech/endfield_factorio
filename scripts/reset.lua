-- 跃迁主流程：清场 → 重置玩家/科技 → 随机新参数。
local constants = require('scripts.constants')
local util = require('scripts.util')
local gui = require('scripts.gui')
local players = require('scripts.players')
local passives = require('scripts.passives')
local science_exp = require('scripts.science_exp')
local respawn_gifts = require('scripts.respawn_gifts')
local player_stats = require('scripts.player_stats')
local classes = require('scripts.classes')             -- 职业专属解锁（M.active_class_unlocks）

local M = {}

-- ── 飞船命数前缀（剩余跃迁次数的可视化）─────────────────────────────────────
local HEART = '[img=virtual-signal/signal-heart]'
-- 向所有在线管理员打印红色告警（如职业配置了不存在的科技/配方名 → 提示去 classes.lua 修正）。
local function admin_warn(text)
    for _, p in pairs(game.connected_players) do
        if p.admin then p.print('[color=red]' .. text .. '[/color]') end
    end
end
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
    players.refresh_blueprint_perms()      -- warps 刚 +1：刷新在线玩家蓝图权限，让满 2 次的即时解锁

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
    -- 在船名前打【剩余命数 + 心】前缀(如 [img=item/parameter-4][img=virtual-signal/signal-heart] = 还剩 4 条命)，
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

    -- 世界荣誉榜：记录【全员带走经验总量】最高的前 N 个世界（世界号 + 总经验 + 结束时 game.tick）。
    -- 总量 = 本轮所有玩家、所有瓶种经验之和；天数显示时由 tick 换算（commands.show_halloffame）。
    -- 开关 storage.hall_of_fame_enabled（默认开，false=停止记录）；条数上限 storage.hall_of_fame_max（默认 30）。
    local world_total = 0
    for _, s in ipairs(summaries) do world_total = world_total + s.total end
    if storage.hall_of_fame_enabled ~= false and world_total > 0 then
        storage.hall_of_fame = storage.hall_of_fame or {}   -- 老存档兜底
        local hof = storage.hall_of_fame
        hof[#hof + 1] = {run = storage.run - 1, exp = world_total, tick = game.tick}
        table.sort(hof, function(a, b) return a.exp > b.exp end)
        for i = #hof, (storage.hall_of_fame_max or 30) + 1, -1 do hof[i] = nil end   -- 超出上限裁队尾
    end

    -- 清理长期不活跃玩家（storage.player_cleanup_hours 小时没上线，默认 32，可 /c 热改）：
    -- 删除其玩家对象，释放蓝图/快捷键等存档膨胀。
    -- 经验/统计按【名字】存储（player_stats / science_exp），删玩家不动这些数据；
    -- 玩家用同名回归时自动继承。
    local INACTIVE_TICKS = (storage.player_cleanup_hours or 32) * constants.hour_to_tick
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
    storage.respawn_home = storage.respawn_home or {}
    for _, player in pairs(game.players) do
        if player.surface then
            -- 跃迁清场：这次复活去【出生星球】(含此刻已是死亡状态、待复活的玩家)。一次性，复活时消费(见 players.place_on_respawn)。
            storage.respawn_home[player.index] = true
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
    storage.pending_chest_tags = {}   -- 清空未勘探宝箱标签的待办（新一轮星球会重新生成据点/标签）
    storage.outposts, storage.outpost_of = {}, {}   -- 清空据点"守卫全灭解锁箱"登记（旧世界实体已失效，新世界重建）

    -- 清空星球（会触发 surface.lua 的 on_surface_cleared 重新生成）
    for _, surface_name in ipairs(constants.PLANETS) do
        if game.surfaces[surface_name] ~= nil then
            game.surfaces[surface_name].clear(true)
        end
    end

    local force = game.forces.player

    -- 科技进度全部清零，不再保留无限科技 level
    force.reset()
    -- 【关键】force.reset() 只把科技置回未研究、modifier 归零，【不会】退无限科技的 level（实测确认）：
    -- 上一轮玩家自研/事件送的级数会残留（永生计划 health、各产能/伤害科技…），跨跃迁越滚越高。
    -- 故全量扫多级科技压回自身最低级 proto.level（不能写死 1：physical-projectile-damage-7 最低 7 级）。
    -- 下方 class_infinite_lvl 只压【职业表指向】的科技，覆盖不到其余无限科技，且老存档 storage.classes
    -- 可能缺新加条目，必须在这里兜底。放在所有开局解锁/职业发放之前：先全量归零，再按本轮配置重发。
    for _, tech in pairs(force.technologies) do
        local proto = tech.prototype
        if proto.level and proto.max_level and proto.level < proto.max_level and tech.level > proto.level then
            tech.level = proto.level
        end
    end
    -- 清空生产/流体/击杀/建造统计（force.reset 只清科技+modifier、不含统计；2.0 起统计按表面分开）：
    -- 每个新世界的生产图表从 0 开始，不累积上一轮。遍历全部表面（含太空平台）。
    for _, surface in pairs(game.surfaces) do
        force.get_item_production_statistics(surface).clear()
        force.get_fluid_production_statistics(surface).clear()
        force.get_kill_count_statistics(surface).clear()
        force.get_entity_build_count_statistics(surface).clear()
    end
    force.friendly_fire = false   -- 禁止友军伤害：玩家的武器/爆炸不再伤到自家(同 force)建筑与队友
    force.maximum_following_robot_count = 50   -- 战斗无人机跟随上限提到 50（force.reset 会打回默认，故每次跃迁后重设）
    force.character_inventory_slots_bonus = 50   -- 每个玩家固定 +50 背包格（同上，force.reset 会清，故每轮重设；取代旧的按礼包格数动态扩）

    -- 每次跃迁后自动解锁所有星球【传送点】：无需研究 planet-discovery 即可前往，但【不】点亮发现科技（科技树里仍显示未发现）。
    -- 受开关 storage.unlock_all_planets 控制（默认 true，可 /c 关）。必须放在 force.reset() 之后，reset 会清空解锁状态，先解锁会被冲掉。
    if storage.unlock_all_planets then
        for name in pairs(game.planets) do
            force.unlock_space_location(name)
        end
    end
    -- 开局赠送所有【触发科技】：这类科技靠特定动作触发(捕获虫巢/扔物入太空…)而非投瓶，
    -- 直接标记已研究，省去玩家逐个触发的繁琐。research_trigger 非 nil 即触发科技。
    -- 受开关 storage.grant_trigger_techs 控制（默认 true，可 /c 热改关闭）。
    if storage.grant_trigger_techs then
        for _, tech in pairs(force.technologies) do
            if tech.prototype.research_trigger and not tech.researched then
                tech.researched = true
            end
        end
    end
    -- 开局额外解锁的【科技】白名单（storage.unlock_techs，默认空）：列出的科技直接标记已研究。
    for _, name in ipairs(storage.unlock_techs or {}) do
        local tech = force.technologies[name]
        if tech then tech.researched = true end
    end
    -- 开局额外解锁的【配方】白名单（storage.unlock_recipes，默认空）：列出的配方直接启用，无需对应科技。
    for _, name in ipairs(storage.unlock_recipes or {}) do
        local recipe = force.recipes[name]
        if recipe then recipe.enabled = true end
    end
    -- 开局额外解锁的【品质】白名单（storage.unlock_quality，默认四档全开）：直接对 force 放开品质等级，无需研发 quality 科技。
    for _, name in ipairs(storage.unlock_quality or {}) do
        if prototypes.quality[name] and not force.is_quality_unlocked(name) then
            force.unlock_quality(name)
        end
    end
    -- 职业【专属科技】：若存在选了某职业的玩家（含离线），解锁该职业配置的 tech（每职业 0~1 个，见 classes.lua 的 tech 字段）。
    -- 职业【专属解锁】：按职业逐个应用 techs(标记已研究)/recipes(force 级 enabled)，并【全服广播】哪个职业解锁了什么。
    -- 职业【专属解锁】：有该职业玩家则开局解锁其 techs/recipes（不广播）。找不到的名字向管理员告警。
    --
    -- 无限/多级【职业科技】跨跃迁【幂等重算】，不再随跃迁次数/玩家自研无限涨：
    --   1) 先扫【所有职业定义】(不只在场)，把它们指向的无限科技统一压回【科技自身最低级 proto.level】(=未研究 floor)；
    --      这样玩家自研出的高级、以及相关职业全员退出的情形，都会在跃迁时回落到该科技最低级。
    --   2) 再按【在场】职业人数累加（同一无限科技可被多个职业指向，如 research-productivity 同属
    --      挂机大师+天文专家，故先收集到 class_infinite_lvl、最后统一【设级】，避免边算边写互相覆盖）。
    -- class_tech_stack 开 = 最低级 + 各相关职业人数之和（每个选该职业的玩家各 +1 级）；关 = 最低级 + 1（固定首研级，不随人数变）。
    -- 【关键】floor 一律用 proto.level，不能写死 1/2：物理伤害等科技最低级是 7，设更低引擎报错崩档。
    local class_infinite_lvl = {}
    for _, def in ipairs(classes.all()) do
        for _, t in ipairs(def.techs or {}) do
            local tname = classes.tech_entry(t)   -- 条目可为 '名' 或 {'名', p=}：基准重置不看概率，所有候选都压回 floor
            local tech = tname and force.technologies[tname]
            if tech then
                local proto = tech.prototype
                if proto.level and proto.max_level and proto.level < proto.max_level then
                    class_infinite_lvl[tname] = proto.level   -- 基准=科技自身最低级(未研究 floor)。不能写死 1：如 physical-projectile-damage-7 最低 7 级，设更低会被引擎拒绝→进游戏崩
                end
            end
        end
    end
    for _, u in ipairs(classes.active_class_unlocks()) do
        -- 概率掷点【结果通报】：发给该职业的所有在线玩家（按预约职业=本轮生效职业匹配）。
        -- 懒求值：本职业没有任何 p<1 条目就不扫玩家列表。本段跑在"杀玩家"之后，不会被死亡刷屏顶掉。
        local recips
        local function roll_notify(msg)
            if recips == nil then
                recips = {}
                for _, pl in pairs(game.connected_players) do
                    if (storage.player_class or {})[pl.name] == u.key then recips[#recips + 1] = pl end
                end
            end
            for _, pl in ipairs(recips) do pl.print(msg) end
        end
        for _, t in ipairs(u.techs) do
            local tname, p = classes.tech_entry(t)
            local tech = tname and force.technologies[tname]
            if not tech then
                admin_warn('职业 ' .. u.key .. ' 配置的科技不存在：' .. tostring(tname))
            elseif class_infinite_lvl[tname] and storage.class_tech_stack then
                -- 无限科技【叠级模式】：每个选该职业的玩家独立掷 p、各自 +1 级 → 实加级数 ~ B(人数, p)（与初始物品同口径）。
                local add = (p >= 1) and u.count or util.binomial(u.count, p)
                class_infinite_lvl[tname] = class_infinite_lvl[tname] + add
                if p < 1 then
                    roll_notify({add > 0 and 'wn.class-roll-hit-levels' or 'wn.class-roll-miss',
                                 '[technology=' .. tname .. ']', tech.localised_name, add})
                end
            else
                -- 有限科技 / 无限科技【固定首级模式】：整体掷一次，任一玩家命中即解锁 → 有效概率 1-(1-p)^人数；p 缺省 1=恒中。
                local hit = p >= 1 or math.random() < (1 - (1 - p) ^ u.count)
                if hit then
                    if class_infinite_lvl[tname] then
                        class_infinite_lvl[tname] = tech.prototype.level + 1   -- stack 关：固定首研级（多职业指向也不叠）
                    elseif not tech.researched then
                        tech.researched = true
                    end
                end
                if p < 1 then roll_notify({hit and 'wn.class-roll-hit' or 'wn.class-roll-miss', '[technology=' .. tname .. ']', tech.localised_name}) end
            end
        end
        for _, rc in ipairs(u.recipes) do
            local rname, p = classes.tech_entry(rc)   -- 配方条目与 techs 同格式：'名' 或 {'名', p=}
            local recipe = rname and force.recipes[rname]
            if not recipe then
                admin_warn('职业 ' .. u.key .. ' 配置的配方不存在：' .. tostring(rname))
            else
                local hit = p >= 1 or math.random() < (1 - (1 - p) ^ u.count)   -- 同有限科技：任一玩家命中即解锁 = 1-(1-p)^人数
                if hit then recipe.enabled = true end
                if p < 1 then roll_notify({hit and 'wn.class-roll-hit' or 'wn.class-roll-miss', '[recipe=' .. rname .. ']', recipe.localised_name}) end
            end
        end
    end
    -- 统一【设级】(直接赋值、非取大)：把无限职业科技无条件归位到算出的目标级，封顶 max_level。
    -- 直接赋值才能在跃迁时把上一轮残留的高级压下来；只有这里有权降级，别处不动 force 研究。
    for t, lvl in pairs(class_infinite_lvl) do
        local tech = force.technologies[t]
        tech.level = math.min(tech.prototype.max_level, lvl)
    end

    -- 跃迁倒计时重置为初始值（storage.warp_initial_minutes 分钟，可 /c 热改）；研究科技瓶科技按
    -- storage.warp_extend_minutes 各自延长。内部以小时记账，故 /60。
    storage.warp_hours = (storage.warp_initial_minutes or 10) / 60
    -- 提前跃迁投票【返还】：跃迁发生时退还"输的一方"已花的投票星星（star sink 只消耗赢家、补偿输家）。
    --   · 提前跃迁达成(warp_vote_delta ~= nil) → 退还所有投【反对】的人（他们没拦住）；
    --   · 自然倒计时结束(delta == nil，反对方赢) → 退还所有投【支持】的人（没推成）。
    -- 必须在下面清空 warp_vote/warp_vote_cost 之前结算；离线玩家也按名字加回 storage.star，下次上线即得。
    do
        local refund_side = (storage.warp_vote_delta ~= nil) and 'oppose' or 'agree'
        local cost = storage.warp_vote_cost or {}
        storage.star = storage.star or {}
        for name, v in pairs(storage.warp_vote or {}) do
            if v == refund_side then
                local c = cost[name] or 0
                if c > 0 then storage.star[name] = (storage.star[name] or 0) + c * constants.min_to_tick end
            end
        end
    end
    storage.warp_vote = {}        -- 新世界清空跃迁投票（上一世界的同意/反对作废）
    storage.warp_vote_cost = {}   -- 投票花费记录一并清空（已在上面结算返还）
    storage.warp_vote_delta = nil -- 投票缩减量作废（warp_hours 已重置，无可恢复）
    storage.star_extend_used = 0  -- 新世界花星星延长额度清零（每星系上限 star_extend_cap）

    -- 本轮【能否前往各外星球】独立滚定：母星恒开，其余 4 星各自按 storage.travel_chance[星球](默认 1.0=恒开，由 ensure_defaults 补齐) 概率开放。
    -- 仅 travel_enabled 总开关开启时这套才生效（见 commands.travel / gui 按钮）。
    storage.travel_open = {nauvis = true}
    local tc = storage.travel_chance or {}
    for _, planet in ipairs(constants.OFF_PLANETS) do
        storage.travel_open[planet] = math.random() < (tc[planet] or 1.0)
    end
    storage.chat_bubble = {} -- 清空聊天气泡引用（角色已死、气泡已随之销毁，避免残留无效引用）

    -- 跃迁时飞船去向由 storage.platform_warp_mode 控制（默认 'stay'，可 /c 热改）：
    --   'stay'   = 停留原地，保持航行状态继续跑（不动它）
    --   'home'   = 瞬移回母星轨道并暂停（旧行为）
    --   'random' = 每艘各自随机挑一个星球轨道停靠并暂停
    -- 无论哪种模式都清空平台 surface 上的所有陨石(asteroid + asteroid-chunk)，避免上一轮的陨石跨轮残留/继续砸船。
    local pmode = storage.platform_warp_mode or 'stay'
    for _, platform in pairs(force.platforms) do
        if pmode == 'home' then
            platform.space_location = 'nauvis'
            platform.paused = true
        elseif pmode == 'random' then
            platform.space_location = constants.PLANETS[math.random(#constants.PLANETS)]
            platform.paused = true
        end
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
    -- 本世界【全局敌人进化度】随机滚定：evo = min(1, enemy_evo_max×(1-√r))，分布【线性递减】(evo=0 处概率密度最高、线性降到上限处为 0)。
    -- evolution 在 2.0 是 per-surface 标量，先 reset_evolution 清累积贡献，再逐星球表面写同一值 → 全局一致(影响虫种/攻击波规模/复制虫选种)。
    game.forces.enemy.reset_evolution()
    local evo = math.min(1, (storage.enemy_evo_max or 1) * (1 - math.sqrt(math.random())))
    for _, surface_name in ipairs(constants.PLANETS) do
        local s = game.surfaces[surface_name]
        if s then game.forces.enemy.set_evolution_factor(evo, s) end
    end

    -- 本世界【敌人武器伤害】：每种伤害类型【各自独立】随机加成，范围 +0% ~ +(enemy_dmg_max×100)%。
    -- 分布【线性递减】：+0% 概率最高、越高越罕见（PDF ∝ (max-x)，逆变换采样 x = max×(1-√r)）。对敌方常见弹种(机枪/激光/喷火塔+虫/沙虫)生效。
    local dmg_max = storage.enemy_dmg_max or 12
    for _, cat in ipairs({'bullet', 'laser', 'flamethrower', 'melee', 'biological', 'rocket', 'electric', 'tesla', 'capsule', 'grenade'}) do
        if prototypes.ammo_category[cat] then
            local dmg = dmg_max * (1 - math.sqrt(math.random()))
            game.forces.enemy.set_ammo_damage_modifier(cat, dmg)
        end
    end

    -- 本世界"玩家消灭虫巢获随机科技"的概率
    -- 本世界"杀虫巢得科技"概率：在 [nest_tech_chance_min, max] 内随机滚定（范围可 /config 查看、/c 热改）。
    local ntc_min, ntc_max = storage.nest_tech_chance_min or 0.001, storage.nest_tech_chance_max or 0.01
    storage.nest_tech_chance = ntc_min + math.random() * math.max(0, ntc_max - ntc_min)

    game.map_settings.enemy_expansion.enabled = false
    game.map_settings.pollution.enabled = true
    game.map_settings.pollution.ageing = util.mostly_normal()
    game.map_settings.pollution.enemy_attack_pollution_consumption_modifier =
        util.mostly_normal() / storage.difficulty

    game.map_settings.asteroids.spawning_rate = util.mostly_normal()
    game.difficulty_settings.spoil_time_modifier = util.mostly_normal()   -- 腐败速度：大概率正常
    game.difficulty_settings.technology_price_multiplier = 2              -- 每个世界科技成本恒为 2 倍

    -- 对在线玩家重算速度技能（背包格数加成已改 force 级，见上 force 段，无需 per-player 处理）。
    for _, player in pairs(game.connected_players) do
        passives.apply(player)
    end

    gui.players_gui()

    -- 返回本轮是否有人拿到科技瓶经验（summaries 只收 total>0 的玩家）→ 供 warp_fx 选成功/普通音效。
    return #summaries > 0
end

return M
