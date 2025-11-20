local day_to_tick = 5184000
local hour_to_tick = 216000
local min_to_tick = 3600

local nauvis = 'nauvis'
local vulcanus = 'vulcanus'
local fulgora = 'fulgora'
local gleba = 'gleba'
local aquilo = 'aquilo'
local edge = 'solar-system-edge'
local shattered_planet = 'shattered-planet'

local normal = 'normal'
local uncommon = 'uncommon'
local rare = 'rare'
local epic = 'epic'
local legendary = 'legendary'
local qualities = {normal, uncommon, rare, epic, legendary}

local not_admin_text = {'wn.permission-denied'}

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

local persistent_infinite_tech_names = {'steel-plate-productivity', 'plastic-bar-productivity',
                                        'low-density-structure-productivity', 'rocket-fuel-productivity',
                                        'processing-unit-productivity', 'rocket-part-productivity',
                                        'research-productivity', 'mining-productivity-3'}

-- 左上角信息内容
local function player_gui(player)

    if not storage.dynamic_introduction then
        storage.dynamic_introduction =
            '版本号20251119\n[img=entity/big-wriggler-pentapod]BUG反馈 Q群 293280221 541826511\n\n'
    end
    player.gui.top.clear()
    player.gui.top.add {
        type = 'sprite-button',
        sprite = 'item/electric-mining-drill',
        name = 'info',
        tooltip = {'description', storage.dynamic_introduction}
    }

    if not storage.traits then
        storage.traits = {''}
    end
    player.gui.top.add {
        type = 'sprite-button',
        sprite = 'space-location/solar-system-edge',
        -- sprite = 'virtual-signal/signal-info',
        name = 'traits',
        tooltip = storage.traits
    }
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
    if game.tick - player.last_online > 48 * hour_to_tick then
        -- pass
    end
    player.disable_flashlight()
    try_enter_space_platform(player)
end

-- 开图
script.on_event(defines.events.on_player_respawned, function(event)
    local player = game.get_player(event.player_index)
    try_enter_space_platform(player)
end)

-- 开图
script.on_event(defines.events.on_pre_player_left_game, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    -- if player.surface and not player.surface.platform then
    if player.character then
        player.force.add_chart_tag(player.surface, {
            position = player.character.position,
            text = '[entity=character]'
        })
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

local function create_entity(name, x, y)
    local entity = game.surfaces.nauvis.create_entity {
        name = name,
        quality = normal,
        position = {
            x = x,
            y = y
        },
        force = 'player'
    }
    entity.minable = true
    entity.destructible = true
end

-- 重置母星
local function nauvis_reset()
    -- create_entity('rocket-silo', 5, 5)
    -- create_entity('cargo-landing-pad', 5, -7)
end

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
    end
end

-- 指数分布
local function random_exp(x)
    return math.pow(2, (math.random() - math.random()) * x)
end

local function random_frequency()
    return readable(0.1 + random_exp(3) * storage.frequency)
end

local function random_size()
    return readable(0.1 + random_exp(3) * storage.size)
end

local function random_richness()
    return readable(0.1 + random_exp(6) * storage.richness)
end

local function random_nature()
    if not storage.nature then
        storage.nature = 3
    end
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
    local richness = random_richness()
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

    if math.random(1, 6) == 1 then
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
    storage.radius = storage.radius or 1024
    -- 刷新星球半径
    local r = storage.radius * random_exp(2)
    r = math.max(storage.radius_min, r)
    r = math.min(storage.radius_max, r)
    r = math.ceil(r)
    storage.radius_of[surface.name] = r
    try_add_trait({'wn.traits-radius', r})

    mgs.width = r * 2 + 32
    mgs.height = r * 2 + 32

    mgs.starting_area = 2 * random_exp(2)

    -- 母星
    if surface == game.surfaces.nauvis then

        surface.peaceful_mode = math.random(1, 5) == 1
        if surface.peaceful_mode then
            try_add_trait({'wn.traits-peaceful-nauvis'})
        end

        local names = {''}
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
    nauvis_reset()
end)

-- 跃迁
local function reset()
    storage.run = (storage.run or 0) + 1

    -- 清除星球前
    local last_run_ticks = (game.tick - (storage.run_start_tick or game.tick))
    game.print({'wn.warp-success-time', math.floor(last_run_ticks / hour_to_tick),
                math.floor(last_run_ticks / min_to_tick) % 60})
    storage.run_start_tick = game.tick

    -- 重置玩家
    for _, player in pairs(game.players) do
        if player.surface and not player.surface.platform then
            -- if player.surface and player.surface.planet then
            local inventory = player.get_inventory(defines.inventory.character_main)

            if player.character then
                player.character.die()
            elseif inventory then
                inventory.clear()
            else
                player.clear_items_inside()
            end
            player_reset(player)
        else

        end
    end

    -- 删除星球前
    storage.traits = {'', {'wn.traits-title'}}

    -- 清空标记
    for _, surface in pairs(game.surfaces) do
        for _, tag in pairs(game.forces.player.find_chart_tags(surface)) do
            tag.destroy()
        end
    end

    game.surfaces['nauvis'].clear(true)
    if game.surfaces['vulcanus'] ~= nil then
        game.surfaces['vulcanus'].clear(true)
    end
    if game.surfaces['gleba'] ~= nil then
        game.surfaces['gleba'].clear(true)
    end
    if game.surfaces['fulgora'] ~= nil then
        game.surfaces['fulgora'].clear(true)
    end
    if game.surfaces['aquilo'] ~= nil then
        game.surfaces['aquilo'].clear(true)
    end

    local force = game.forces.player

    -- 产能保留
    storage.infinite_tech_levels = storage.infinite_tech_levels or {}

    for _, tech_name in pairs(persistent_infinite_tech_names) do
        local tech = force.technologies[tech_name]
        storage.infinite_tech_levels[tech_name] = math.max(tech.prototype.level, tech.level)
    end

    -- 重置玩家势力
    force.reset()
    force.friendly_fire = true

    -- 产能保留
    for _, tech_name in pairs(persistent_infinite_tech_names) do
        local level = storage.infinite_tech_levels[tech_name]
        local tech = force.technologies[tech_name]
        tech.level = level
    end

    -- 瞬移飞船
    for _, platform in pairs(force.platforms) do
        platform.space_location = 'nauvis'
        platform.paused = true
    end

    -- 重置科技

    game.reset_time_played()

    -- 母星污染
    game.forces.enemy.reset_evolution()
    game.map_settings.enemy_expansion.enabled = false
    game.map_settings.pollution.enabled = true
    game.map_settings.pollution.ageing = readable(random_exp(3))
    game.map_settings.pollution.enemy_attack_pollution_consumption_modifier = readable(random_exp(3))
    try_add_trait({'wn.galaxy-trait-pollution-ageing', game.map_settings.pollution.ageing})
    try_add_trait({'wn.galaxy-trait-enemy_attack_pollution_consumption_modifier',
                   game.map_settings.pollution.enemy_attack_pollution_consumption_modifier})

    game.map_settings.asteroids.spawning_rate = readable(random_exp(4))
    game.difficulty_settings.spoil_time_modifier = readable(0.5 + random_exp(4))

    game.difficulty_settings.technology_price_multiplier = 1

    try_add_trait({'', '\n', {'wn.galaxy-trait-spawning_rate', game.map_settings.asteroids.spawning_rate},
                   {'wn.galaxy-trait-spoil_time_modifier', game.difficulty_settings.spoil_time_modifier}})

    local force = game.forces.player
    local size = table_size(force.platforms)
    if size < 1 and not force.technologies['rocket-silo'].enabled then
        for _, tech_name in pairs(persistent_infinite_tech_names) do
            force.technologies[tech_name].enabled = true
            force.technologies[tech_name].visible_when_disabled = true
        end
    else
        for _, tech_name in pairs(persistent_infinite_tech_names) do
            force.technologies[tech_name].enabled = false
            force.technologies[tech_name].visible_when_disabled = true
        end
    end

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
        welcome = {'wn.welcome-player', player.name, total_time, last_delta}
    else
        welcome = {'wn.welcome-new-player', player.name}
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

local function can_reset()
    return game.forces.player.technologies['promethium-science-pack'].researched
end

script.on_event(defines.events.on_research_finished, function(event)

    local research = event.research
    local research_name = research.name

    if not event.by_script then
        -- 增加时间
        if research.prototype and not research.prototype.research_trigger then
            local delta_minutes = storage.warp_minutes_per_tech * (research_name == 'health' and 2 or 1)
            storage.warp_minutes_total = storage.warp_minutes_total + delta_minutes
            game.print({'wn.warp-time-tech', delta_minutes, get_warp_time_left()})
        end

        -- 自动添加无限科技
        if research.level > research.prototype.level then
            local queue = game.forces.player.research_queue
            queue[table_size(queue) + 1] = research
            game.forces.player.research_queue = queue
            game.print({'wn.start-tech', research.name, research.level + 1})
        end
    end

    players_gui()
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

script.on_event(defines.events.on_space_platform_changed_state, function(event)
    -- 平台上限
    local platform = event.platform
    if event.old_state == 0 then
        local force = platform.force
        if table_size(force.platforms) > storage.max_platform_count then
            platform.destroy(1)
            game.print({'wn.too-many-platforms', storage.max_platform_count})
        end
    end

    -- 首次到达
    local platform = event.platform
    local location = platform.space_location
    if not location then
        return
    end

    local name = location.name

    players_gui()

    -- 前往下一个地点
    if name == edge then
        if (can_reset()) then
            reset()
        end
    end
end)

script.on_event(defines.events.on_gui_click, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    if event.element.name == 'introduction' then
        -- suicide
        if player.character then
            player.character.die()
            game.print({'wn.suicide-notice', player.name})
        end
        return
    else
        return
    end
end)

-- 没有飞船 才能研究 飞船建造、无限科技
script.on_nth_tick(60 * 60, function()
    -- 通知 1分钟一次
    local force = game.forces.player
    local size = table_size(force.platforms)
    if size < 1 and not force.technologies[persistent_infinite_tech_names[1]].enabled then
        -- force.technologies['rocket-silo'].enabled = true
        for _, tech_name in pairs(persistent_infinite_tech_names) do
            force.technologies[tech_name].enabled = false
            force.technologies[tech_name].visible_when_disabled = true
        end
    end
end)

