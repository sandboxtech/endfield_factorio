local day_to_tick = 5184000
local hour_to_tick = 216000
local min_to_tick = 3600

local nauvis = 'nauvis'

local normal = 'normal'

local not_admin_text = {'wn.permission-denied'}

-- 追加一条 trait 到 tooltip 列表。
-- 本地化字符串单层最多 20 个参数，超过 18 时把整张表嵌进
-- 一个新表 {'', old} 作为单个元素，再继续追加，从而突破单层上限。
local function try_add_trait(trait)
    if not trait then
        return
    end
    storage.traits = storage.traits or {''}
    if table_size(storage.traits) >= 18 then
        storage.traits = {'', storage.traits}
    end
    table.insert(storage.traits, trait)
end

-- 跃迁后 level 会被 force.reset() 清零，需要在 reset 前后记录并恢复。
local persistent_infinite_tech_names = {'steel-plate-productivity', 'plastic-bar-productivity',
                                        'low-density-structure-productivity', 'rocket-fuel-productivity',
                                        'processing-unit-productivity', 'rocket-part-productivity',
                                        'research-productivity', 'mining-productivity-3'}

-- 左上角信息内容
local function player_gui(player)

    if not storage.dynamic_introduction then
        storage.dynamic_introduction = ''
    end
    player.gui.top.clear()
    local intro = player.gui.top.add {
        type = 'sprite-button',
        caption = {'run', storage.run or 0},
        name = 'introduction',
        tooltip = {'description', storage.dynamic_introduction}
    }
    intro.style.font = 'heading-1'
    intro.style.font_color = {222, 222, 222}
    intro.style.minimal_height = 38
    intro.style.maximal_height = 38
    intro.style.minimal_width = 288
    intro.style.padding = -2

    if not storage.traits then
        storage.traits = {''}
    end
    player.gui.top.add {
        type = 'sprite-button',
        sprite = 'space-location/solar-system-edge',
        name = 'traits',
        tooltip = storage.traits
    }

    if player.admin then
        player.gui.top.add {
            type = 'sprite-button',
            sprite = 'item/raw-fish',
            name = 'admin',
            tooltip = '管理员输入 /reset 手动跃迁'
        }
    end
end

local function players_gui()
    for _, player in pairs(game.players) do
        if player.connected then
            player_gui(player)
        else
            player.gui.top.clear()
        end
    end
end

-- 手动重置players_gui
commands.add_command('players_gui', {'wn.players-gui-help'}, function(command)
    local player = game.get_player(command.player_index)
    if not player or player.admin then
        players_gui()
    else
        player.print(not_admin_text)
    end
end)

local function try_enter_space_platform(player)
    local size = table_size(game.forces.player.platforms)
    if size >= 1 then
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
end

-- 重置玩家
local function player_reset(player)
    if not player then
        return
    end
    player.disable_flashlight()
end

-- 开图
script.on_event(defines.events.on_player_respawned, function(event)
    local player = game.get_player(event.player_index)
    player.disable_flashlight()
end)

-- 开图
script.on_event(defines.events.on_pre_player_left_game, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    if player.character then
        player.character.die()
        -- 删除尸体
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

-- 创建玩家
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    player_reset(player)
    player_gui(player)
    try_enter_space_platform(player)
end)

-- 数字格式
local function readable(x)
    if x < 0 then
        return 0
    elseif x < 0.1 then
        return math.ceil(x * 100) * 0.01
    elseif x < 3 then
        return math.floor(x * 10) * 0.1
    elseif x < 10 then
        return math.floor(x)
    elseif x < 100 then
        return math.floor(x / 10) * 10
    elseif x < 1000 then
        return math.floor(x / 100) * 100
    else
        return math.floor(x / 1000) * 1000
    end
end

-- 指数分布
local function random_exp(x)
    return math.pow(2, (math.random() - math.random()) * x)
end

-- 资源属性 = 0.1 + 指数分布 * 全局缩放，exp 越大方差越大
local function random_attr(scale_key, exp)
    return readable(0.1 + random_exp(exp) * storage[scale_key])
end

local function random_frequency() return random_attr('frequency', 3) end
local function random_size()      return random_attr('size', 3) end
local function random_richness()  return random_attr('richness', 6) end

-- 自然要素（水/树/敌人基地等）使用 nature 而非全局 frequency/size/richness
local function random_nature()
    storage.nature = storage.nature or 3
    return readable(math.pow(2, (math.random() - math.random()) * storage.nature))
end

-- 创建随机表面
script.on_event(defines.events.on_surface_created, function(event)
    local surface = game.get_surface(event.surface_index)
    if not surface then
        return
    end

    local mgs = surface.map_gen_settings
    mgs.seed = math.random(1, 4294967295)

    surface.map_gen_settings = mgs
end)

local renames = {}
renames['crude-oil'] = 'fluid/crude-oil'
renames['vulcanus_coal'] = 'item/coal'
renames['sulfuric_acid_geyser'] = 'fluid/sulfuric-acid'
renames['lithium_brine'] = 'fluid/lithium-brine'
renames['fluorine_vent'] = 'fluid/fluorine'
renames['aquilo_crude_oil'] = 'fluid/crude-oil'
renames['tungsten_ore'] = 'item/tungsten-ore'
renames['gleba_stone'] = 'item/stone'

local function set_resource(name, mgs, richness_multiplier)

    local size = random_size()
    local richness = readable(random_richness() * 1 / (1 + storage.run * 0.05))
    richness = math.max(0.01, richness)

    local frequency = random_frequency()
    local value = size * richness * frequency / storage.size / storage.richness / storage.frequency

    local value_string = nil
    if value < 0.01 then
        value_string = {'wn.very-low'}
    elseif value < 0.1 then
        value_string = {'wn.low'}
    elseif value > 100 then
        value_string = {'wn.very-high'}
    elseif value > 10 then
        value_string = {'wn.high'}
    else
        value_string = {'wn.medium'}
    end

    try_add_trait({'wn.traits-richness-size-frequency', renames[name] or ('item/' .. name), richness, size, frequency,
                   value_string})

    richness_multiplier = richness_multiplier or 1
    mgs.autoplace_controls[name].size = size
    mgs.autoplace_controls[name].richness = richness * richness_multiplier
    mgs.autoplace_controls[name].frequency = frequency
end

local function random_nature_mgs(mgs, name)
    mgs.autoplace_controls[name].richness = random_nature()
    mgs.autoplace_controls[name].frequency = random_nature()
    mgs.autoplace_controls[name].size = random_nature()
end

-- 创建随机表面
script.on_event(defines.events.on_surface_cleared, function(event)

    local surface = game.get_surface(event.surface_index)
    if not surface then
        return
    end

    -- 跳过平台
    local platform = surface.platform
    if platform then
        return
    end

    local mgs = surface.map_gen_settings
    mgs.seed = math.random(1, 4294967295)

    -- 星球昼夜
    surface.always_day = false
    surface.freeze_daytime = false
    surface.min_brightness = 0
    surface.wind_speed = 0.02 * (0.5 + math.random())
    surface.wind_orientation = math.random()
    surface.wind_orientation_change = 0.0001 * (0.5 + math.random())
    surface.solar_power_multiplier = 1

    try_add_trait({'wn.traits-planet', surface.name})

    if math.random(1, 6) == 1 and surface ~= game.surfaces.aquilo then
        -- 潮汐锁定，永夜
        surface.freeze_daytime = true
        surface.daytime = 0.56
        try_add_trait({'wn.traits-eternal-night'})
    elseif math.random(1, 4) == 1 then
        -- 潮汐锁定，永昼
        surface.freeze_daytime = true
        surface.daytime = 0
        try_add_trait({'wn.traits-eternal-day'})
    end

    storage.radius_min = storage.radius_min or 256
    storage.radius_max = storage.radius_max or 4096
    storage.radius = storage.radius or 2048
    -- 刷新星球半径
    local r = storage.radius * random_exp(2)
    r = math.max(storage.radius_min, r)
    r = math.min(storage.radius_max, r)
    r = math.ceil(r)
    storage.radius_of[surface.name] = r
    try_add_trait({'wn.traits-radius', r})

    mgs.width = r * 2 + 32
    mgs.height = r * 2 + 32

    mgs.starting_area = 1 + 2 * random_exp(2)

    -- 母星
    if surface == game.surfaces.nauvis then

        surface.peaceful_mode = math.random(1, 5) == 1
        if surface.peaceful_mode then
            try_add_trait({'wn.traits-peaceful-nauvis'})
        end

        for _, res in pairs({'iron-ore', 'copper-ore', 'stone', 'coal', 'crude-oil'}) do
            set_resource(res, mgs)
        end

        for _, res in pairs({'uranium-ore'}) do
            set_resource(res, mgs, storage.local_specialty_multiplier)
        end

        for _, res in pairs({'water', 'trees', 'enemy-base', 'rocks', 'nauvis_cliff', 'starting_area_moisture'}) do
            random_nature_mgs(mgs, res)
        end
    end

    -- 火星
    if surface == game.surfaces.vulcanus then

        for _, res in pairs({'vulcanus_coal', 'calcite', 'sulfuric_acid_geyser'}) do
            set_resource(res, mgs)
        end
        for _, res in pairs({'tungsten_ore'}) do
            set_resource(res, mgs, storage.local_specialty_multiplier)
        end
        random_nature_mgs(mgs, 'vulcanus_volcanism')
    end

    -- 雷星
    if surface == game.surfaces.fulgora then
        for _, res in pairs({'scrap'}) do
            set_resource(res, mgs, storage.local_specialty_multiplier)
        end

        random_nature_mgs(mgs, 'fulgora_islands')
        random_nature_mgs(mgs, 'fulgora_cliff')
    end

    -- 草星
    if surface == game.surfaces.gleba then
        surface.peaceful_mode = math.random(1, 5) == 1
        if surface.peaceful_mode then
            try_add_trait({'wn.traits-peaceful-gleba'})
        end

        set_resource('gleba_stone', mgs, storage.local_specialty_multiplier * 2)

        mgs.autoplace_controls['gleba_enemy_base'].richness = math.random() * 6
        mgs.autoplace_controls['gleba_enemy_base'].size = math.random() * 6
        mgs.autoplace_controls['gleba_enemy_base'].frequency = math.random() * 6

        random_nature_mgs(mgs, 'gleba_water')
        random_nature_mgs(mgs, 'gleba_plants')
        random_nature_mgs(mgs, 'gleba_cliff')
    end

    if surface == game.surfaces.aquilo then
        for _, res in pairs({'lithium_brine', 'fluorine_vent', 'aquilo_crude_oil'}) do
            set_resource(res, mgs, storage.local_specialty_multiplier * 0.5)
        end
    end

    surface.map_gen_settings = mgs

    players_gui()

    if surface ~= game.surfaces.nauvis then
        return
    end
    local radius = math.floor(storage.radius * 0.2)
    game.forces.player.chart(game.surfaces.nauvis, {{
        x = -radius,
        y = -radius
    }, {
        x = radius,
        y = radius
    }})
end)

-- 跃迁
-- 每次跃迁后所有星球被清空、重建，玩家死亡，飞船保留一周期。
-- storage.run 从 1 开始计数（on_init 中会调用一次 reset()，对应第 1 轮）。
local function reset()
    game.speed = 1

    storage.run = (storage.run or 0) + 1

    -- 清除星球前
    local last_run_ticks = (game.tick - (storage.run_start_tick or game.tick))
    game.print({'wn.warp-success-time', math.floor(last_run_ticks / hour_to_tick),
                math.floor(last_run_ticks / min_to_tick) % 60})
    storage.run_start_tick = game.tick

    -- 飞船存活两个跃迁周期：本轮首次见到的标 skull，第二次见到时摧毁。
    -- 玩家可借此提前撤离即将报废的飞船。
    if not storage.rust then
        storage.rust = {}
    end
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
            player_reset(player)
        end
    end

    -- 删除星球前
    storage.traits = {'', {'wn.traits-title', storage.run}}

    -- 清空标记
    for _, surface in pairs(game.surfaces) do
        for _, tag in pairs(game.forces.player.find_chart_tags(surface)) do
            tag.destroy()
        end
    end

    for _, surface_name in pairs({'nauvis', 'vulcanus', 'gleba', 'fulgora', 'aquilo'}) do
        if game.surfaces[surface_name] ~= nil then
            game.surfaces[surface_name].clear(true)
        end
    end

    local force = game.forces.player

    -- force.reset() 会清掉所有科技进度，先记录无限科技 level，重置后再恢复。
    storage.infinite_tech_levels = storage.infinite_tech_levels or {}
    for _, tech_name in pairs(persistent_infinite_tech_names) do
        local tech = force.technologies[tech_name]
        storage.infinite_tech_levels[tech_name] = math.max(tech.prototype.level, tech.level)
    end

    force.reset()
    force.friendly_fire = true

    for _, tech_name in pairs(persistent_infinite_tech_names) do
        force.technologies[tech_name].level = storage.infinite_tech_levels[tech_name]
    end

    -- 瞬移飞船
    for _, platform in pairs(force.platforms) do
        platform.space_location = 'nauvis'
        platform.paused = true
    end

    game.reset_time_played()

    -- 母星污染
    if not storage.difficulty then
        storage.difficulty = 1
    end
    game.forces.enemy.reset_evolution()
    game.map_settings.enemy_expansion.enabled = false
    game.map_settings.pollution.enabled = true
    game.map_settings.pollution.ageing = readable(random_exp(4))
    game.map_settings.pollution.enemy_attack_pollution_consumption_modifier = readable(random_exp(3)) /
                                                                                  storage.difficulty
    try_add_trait({'wn.galaxy-trait-pollution-ageing', game.map_settings.pollution.ageing})
    try_add_trait({'wn.galaxy-trait-enemy_attack_pollution_consumption_modifier',
                   game.map_settings.pollution.enemy_attack_pollution_consumption_modifier})

    game.map_settings.asteroids.spawning_rate = readable(random_exp(4))
    game.difficulty_settings.spoil_time_modifier = readable(0.5 + random_exp(4))

    game.difficulty_settings.technology_price_multiplier = 1

    try_add_trait({'', '\n', {'wn.galaxy-trait-spawning_rate', game.map_settings.asteroids.spawning_rate},
                   {'wn.galaxy-trait-spoil_time_modifier', game.difficulty_settings.spoil_time_modifier}})

    -- 更新UI信息
    players_gui()
end

-- 第一次运行场景时触发
script.on_init(function()
    game.speed = 1

    storage.richness = 1
    storage.frequency = 1
    storage.size = 1
    storage.local_specialty_multiplier = 0.25

    storage.radius = 2048
    storage.radius_of = {}

    reset()
end)

script.on_event(defines.events.on_player_left_game, function(event)
    if not event.player then
        return
    end
    event.player.gui.top.clear()
end)

-- 玩家进入游戏
script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    player_gui(player)

    local welcome = {}
    if player.online_time > 0 then
        local last_delta = math.max(0, math.floor((game.tick - player.last_online) / hour_to_tick))
        local total_time = math.max(0, math.floor(player.online_time / hour_to_tick))
        welcome = {'wn.welcome-player', player.name, total_time, last_delta, player.locale}
    else
        welcome = {'wn.welcome-new-player', player.name, player.locale}
    end
    game.print(welcome)
end)

-- 星球圆形地块生成
script.on_event(defines.events.on_chunk_generated, function(event)
    local surface = event.surface
    -- local chunk_position = event.position
    local left_top = event.area.left_top

    -- 圆形地图
    local r = storage.radius_of[surface.name]
    r = r or storage.radius

    if left_top.x * left_top.x + left_top.y * left_top.y < r * r / 2 then
        return
    end

    local chunk_size = 32

    local tiles = {}
    local cx = 0.5
    local cy = 0.5
    for x = -1, chunk_size, 1 do
        for y = -1, chunk_size, 1 do
            local px = left_top.x + x
            local py = left_top.y + y

            if (px - cx) * (px - cx) + (py - cy) * (py - cy) > r * r then
                local p = {
                    x = px,
                    y = py
                }
                table.insert(tiles, {
                    name = 'empty-space',
                    position = p
                })
            end
        end
    end
    if table_size(tiles) > 0 then
        surface.set_tiles(tiles)
    end
    players_gui() -- 更新...
end)

script.on_event(defines.events.on_research_finished, function(event)
    local research = event.research
    local research_name = research.name

    if not event.by_script then
        local force = game.forces.player
        for _, tech_name in pairs(persistent_infinite_tech_names) do
            if tech_name == research_name then
                game.print({'wn.persistent-tech', research.name, research.level})
                reset()
            else
                -- 自动添加非产能无限科技
                if research.level > research.prototype.level then
                    local queue = game.forces.player.research_queue
                    queue[table_size(queue) + 1] = research
                    game.forces.player.research_queue = queue
                    game.print({'wn.start-tech', research.name, research.level + 1})
                end
            end
        end
    end

end)

-- 手动重置
commands.add_command('reset', {'wn.run-reset-help'}, function(command)
    if not command.player_index then
        return
    end

    local player = game.get_player(command.player_index)
    if not player or player.admin then
        reset()
    else
        player.print(not_admin_text)
    end
end)

script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    -- 点击左上 run 按钮 = 自杀回母星（用于卡死时脱困）
    if event.element.name == 'introduction' then
        local last_run_ticks = (game.tick - (storage.run_start_tick or game.tick))
        local life_total = ((storage.hour_auto_reset or 50) * hour_to_tick)
        local life = life_total - last_run_ticks

        if player.character then
            player.teleport({0, 0}, nauvis)
            player.character.die()

            game.print({'wn.suicide-notice', player.name, math.floor(100 * life / hour_to_tick) / 100})
        end
    end
end)

-- 每分钟检查：临近跃迁时降低游戏速度，给玩家撤离时间；到时强制跃迁。
script.on_nth_tick(60 * 60 * 60, function()
    local last_run_ticks = (game.tick - (storage.run_start_tick or game.tick))
    local life_total = ((storage.hour_auto_reset or 100) * hour_to_tick)
    local life = life_total - last_run_ticks

    if life <= 0 then
        reset()
        return
    end

    -- 剩 1/25 寿命降到 0.25 倍速，剩 1/5 寿命降到 0.5 倍速
    local new_speed
    if life < life_total / 25 then
        new_speed = 0.25
    elseif life < life_total / 5 then
        new_speed = 0.5
    end
    if new_speed and game.speed > new_speed then
        game.speed = new_speed
        game.print({'wn.game-speed-notice', game.speed})
    end
end)
