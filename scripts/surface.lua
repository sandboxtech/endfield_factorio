-- 每次跃迁后随机生成各星球：地图设定、资源、自然要素、圆形边界。
local util = require('scripts.util')

-- autoplace control 名 → 用于 tooltip 显示的 sprite 路径
local renames = {
    ['crude-oil']             = 'fluid/crude-oil',
    ['vulcanus_coal']         = 'item/coal',
    ['sulfuric_acid_geyser']  = 'fluid/sulfuric-acid',
    ['lithium_brine']         = 'fluid/lithium-brine',
    ['fluorine_vent']         = 'fluid/fluorine',
    ['aquilo_crude_oil']      = 'fluid/crude-oil',
    ['tungsten_ore']          = 'item/tungsten-ore',
    ['gleba_stone']           = 'item/stone',
}

-- 把数值映射成 5 档品质图标（灰 normal < 绿 < 蓝 < 紫 < 橙 legendary，越高越丰）。
local function level_for(v)
    if v < 0.5 then return 'normal'
    elseif v < 1 then return 'uncommon'
    elseif v < 2 then return 'rare'
    elseif v < 4 then return 'epic'
    else return 'legendary' end
end

-- 写入一种资源的 size/richness/frequency，并把档位记入 trait（用 quality 星可视化）。
-- richness_multiplier 用于地方特产差异化。
local function set_resource(name, mgs, richness_multiplier)
    local size = util.random_size()
    local richness = math.max(0.01, util.readable(util.random_richness()))
    local frequency = util.random_frequency()

    util.try_add_trait({'wn.traits-richness-size-frequency',
                        renames[name] or ('item/' .. name),
                        level_for(richness), level_for(size), level_for(frequency)})

    richness_multiplier = richness_multiplier or 1
    mgs.autoplace_controls[name].size = size
    mgs.autoplace_controls[name].richness = richness * richness_multiplier
    mgs.autoplace_controls[name].frequency = frequency
end

local function random_nature_mgs(mgs, name)
    mgs.autoplace_controls[name].richness = util.random_nature()
    mgs.autoplace_controls[name].frequency = util.random_nature()
    mgs.autoplace_controls[name].size = util.random_nature()
end

-- 表面新建时只重置 seed（cleared 才会进入完整生成流程）。
script.on_event(defines.events.on_surface_created, function(event)
    local surface = game.get_surface(event.surface_index)
    if not surface then
        return
    end
    local mgs = surface.map_gen_settings
    mgs.seed = math.random(1, 4294967295)
    surface.map_gen_settings = mgs
end)

-- 表面被 clear（跃迁触发）时执行完整随机生成。
script.on_event(defines.events.on_surface_cleared, function(event)
    local surface = game.get_surface(event.surface_index)
    if not surface then
        return
    end
    -- 跳过飞船平台
    if surface.platform then
        return
    end

    local mgs = surface.map_gen_settings
    mgs.seed = math.random(1, 4294967295)

    -- 星球昼夜与气候
    surface.always_day = false
    surface.freeze_daytime = false
    surface.min_brightness = 0
    surface.wind_speed = 0.02 * (0.5 + math.random())
    surface.wind_orientation = math.random()
    surface.wind_orientation_change = 0.0001 * (0.5 + math.random())
    surface.solar_power_multiplier = 1

    util.try_add_trait({'wn.traits-planet', surface.name})

    -- aquilo 不参与永夜/永昼抽奖（本来就极地气候）
    if math.random(1, 6) == 1 and surface ~= game.surfaces.aquilo then
        surface.freeze_daytime = true
        surface.daytime = 0.56
        util.try_add_trait({'wn.traits-eternal-night'})
    elseif math.random(1, 4) == 1 then
        surface.freeze_daytime = true
        surface.daytime = 0
        util.try_add_trait({'wn.traits-eternal-day'})
    end

    storage.radius_min = storage.radius_min or 256
    storage.radius_max = storage.radius_max or 4096
    storage.radius = storage.radius or 2048
    -- 刷新星球半径，箝制在 [radius_min, radius_max]
    local r = storage.radius * util.random_exp(2)
    r = math.max(storage.radius_min, r)
    r = math.min(storage.radius_max, r)
    r = math.ceil(r)
    storage.radius_of[surface.name] = r
    util.try_add_trait({'wn.traits-radius', r})

    mgs.width = r * 2 + 32
    mgs.height = r * 2 + 32
    mgs.starting_area = 1 + 2 * util.random_exp(2)

    -- 母星
    if surface == game.surfaces.nauvis then
        surface.peaceful_mode = math.random(1, 5) == 1
        if surface.peaceful_mode then
            util.try_add_trait({'wn.traits-peaceful-nauvis'})
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
            util.try_add_trait({'wn.traits-peaceful-gleba'})
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
    -- 不在这里刷 GUI：on_surface_cleared 只由 reset.reset() 触发，其末尾会统一刷新。

    -- 仅母星预先 chart 一块区域，方便玩家落地后立刻看清地形
    if surface ~= game.surfaces.nauvis then
        return
    end
    local radius = math.floor(storage.radius * 0.2)
    game.forces.player.chart(game.surfaces.nauvis, {{x = -radius, y = -radius}, {x = radius, y = radius}})
end)

-- 圆形地图：超出半径的格子全部铺成虚空。
script.on_event(defines.events.on_chunk_generated, function(event)
    local surface = event.surface
    local left_top = event.area.left_top

    local r = storage.radius_of[surface.name] or storage.radius

    -- chunk 左上角距原点比 r^2/2 还近 → 整个 chunk 都在圆内，跳过
    if left_top.x * left_top.x + left_top.y * left_top.y < r * r / 2 then
        return
    end

    local chunk_size = 32
    local tiles = {}
    local cx, cy = 0.5, 0.5
    for x = -1, chunk_size, 1 do
        for y = -1, chunk_size, 1 do
            local px = left_top.x + x
            local py = left_top.y + y
            if (px - cx) * (px - cx) + (py - cy) * (py - cy) > r * r then
                table.insert(tiles, {name = 'empty-space', position = {x = px, y = py}})
            end
        end
    end
    if table_size(tiles) > 0 then
        surface.set_tiles(tiles)
    end
    -- 注意：不要在这里刷 GUI。区块生成极高频（每轮跃迁成百上千次），
    -- HUD 不依赖区块，刷新由 reset/玩家事件触发即可。
end)
