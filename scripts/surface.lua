-- 每次跃迁后随机生成各星球：地图设定、资源、自然要素、圆形边界。
local util = require('scripts.util')
local market = require('scripts.market')
local map_features = require('scripts.map_features')

-- 资源档位：丰度/面积/频率各抽一个 1..9 的随机整数 N，乘数 = 1.3^(N-中心) × 全局倍率：
--   丰度 = 1.3^(N-7) × richness_multiplier；面积 = 1.3^(N-6) × size_multiplier；频率 = 1.3^(N-5) × frequency_multiplier。
-- 底数用 1.3（不是 2）→ 浮动温和（约 0.27~2.9 倍），避免极端的巨型矿区。
-- 全局倍率：richness=4（矿更富）、size=frequency=1（大小/数量正常）。
-- specialty_mult：地方特产额外降低【丰度】（只乘丰度，不动面积/频率）。
local function set_resource(name, mgs, specialty_mult)
    local nr, ns, nf = math.random(1, 9), math.random(1, 9), math.random(1, 9)
    local ac = mgs.autoplace_controls[name]
    ac.richness  = 3 ^ (nr - 7) * storage.richness_multiplier * (specialty_mult or 1)
    ac.size      = 1.5 ^ (ns - 6) * storage.size_multiplier
    ac.frequency = 1.3 ^ (nf - 5) * storage.frequency_multiplier
end

-- 纯地貌要素（树/石/水/悬崖/湿度/植物）：大幅浮动，长歪了也只是地貌不同。
local function random_nature_mgs(mgs, name)
    mgs.autoplace_controls[name].richness = util.random_nature()
    mgs.autoplace_controls[name].frequency = util.random_nature()
    mgs.autoplace_controls[name].size = util.random_nature()
end

-- 影响难度/节奏的要素（敌人巢穴）：大概率正常、小概率小幅偏离，避免随机出"虫海"或"无虫"。
local function balance_mgs(mgs, name)
    mgs.autoplace_controls[name].richness = util.mostly_normal()
    mgs.autoplace_controls[name].frequency = util.mostly_normal()
    mgs.autoplace_controls[name].size = util.mostly_normal()
end

-- 树/石/植被等纯地貌：本轮密度由整局气质 mood∈[0,1] 连续决定；个体规模走"多半小、偶尔大"曲线
-- （立方把规模压向小，避免到处大团）。这是【调原生 autoplace】让原生自己长，不是手动 stamp → 排布天然。
local function nature_by_knob(mgs, name, mood)
    local ac = mgs.autoplace_controls[name]
    if not ac then return end
    ac.frequency = 0.4 + mood * 1.6
    ac.size      = 0.3 + mood * 0.6 + (math.random() ^ 3) * 1.3
    ac.richness  = 0.6 + math.random() * 0.8
end

-- 用命名噪声输入的【偏置】修改原生气候（2.0 干净杠杆：常量数字串即可，运行时无法编译公式）。
-- 整颗星偏湿/干/冷/热，原生生成器据此自然长出对应草/沙/树/水比例——是"修改原生"而非"覆盖"。
-- 偏置多半接近 0(≈原版)、偶尔明显 → 寻常世界居多、剧变世界罕见。值必须是字符串。
local function bias_climate(mgs, knobs)
    mgs.property_expression_names = mgs.property_expression_names or {}
    local pen = mgs.property_expression_names
    local function tri() return math.random() - math.random() end   -- ∈(-1,1)，偏中间
    pen['control:moisture:bias']      = tostring((knobs.verdancy - 0.5) * 0.5)  -- 干湿：由繁茂度连续决定
    pen['control:aux:bias']           = tostring(tri() * 0.35)                   -- 副维：沙/红沙调色
    pen['control:temperature:bias']   = tostring(tri() * 12)                     -- 温度：±~12°C 改变生物群系
    pen['control:moisture:frequency'] = tostring(0.6 + math.random() * 0.9)      -- 生物群系斑块大小(连续)
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
    surface.daytime = math.random()   -- 随机当地时间：到达时清晨/正午/黄昏/深夜随机（下方永昼/永夜会覆盖）
    surface.wind_speed = 0.02 * (0.5 + math.random())
    surface.wind_orientation = math.random()
    surface.wind_orientation_change = 0.0001 * (0.5 + math.random())

    -- 外观随机（纯表现，可大幅浮动）：每颗星每次跃迁"长相"都不同，强化旅行新鲜感。
    --   brightness_visual_weights：按 RGB 给白天光照染色，是运行时最接近"改土地颜色"的手段。
    --   大部分时候低饱和（三通道围绕同一亮度小幅抖动，只是淡淡色调）；1/6 概率夸张（血红/幽绿/冷蓝）。
    local cr, cg, cb
    if math.random(1, 6) == 1 then
        cr = 0.35 + math.random()   -- 0.35~1.35 各自独立 → 高饱和强色调
        cg = 0.35 + math.random()
        cb = 0.35 + math.random()
    else
        local base = 0.9 + 0.2 * math.random()   -- 共同亮度 0.9~1.1
        cr = base + (math.random() - 0.5) * 0.12  -- ±0.06 抖动 → 低饱和
        cg = base + (math.random() - 0.5) * 0.12
        cb = base + (math.random() - 0.5) * 0.12
    end
    surface.brightness_visual_weights = {r = cr, g = cg, b = cb}
    surface.min_brightness = 0.4 * math.random()         -- 夜晚黑暗程度 0~0.4（0=漆黑），纯表现
    surface.show_clouds = math.random(1, 5) > 1          -- 1/5 概率无云，纯表现
    -- 阳光强度影响太阳能发电（玩法）→ 大概率正常、小概率小幅偏离
    surface.solar_power_multiplier = util.mostly_normal()

    -- aquilo 不参与永夜/永昼抽奖（本来就极地气候）
    if math.random(1, 6) == 1 and surface ~= game.surfaces.aquilo then
        surface.freeze_daytime = true
        surface.daytime = 0.56   -- 永夜
    elseif math.random(1, 4) == 1 then
        surface.freeze_daytime = true
        surface.daytime = 0      -- 永昼
    end

    storage.radius_min = storage.radius_min or 256
    storage.radius_max = storage.radius_max or 4096
    storage.radius = storage.radius or 2048
    -- 全局资源倍率（老存档兜底；新档由 control.lua on_init 设为 4）
    storage.richness_multiplier = storage.richness_multiplier or 4
    storage.size_multiplier = storage.size_multiplier or 1
    storage.frequency_multiplier = storage.frequency_multiplier or 1
    -- 刷新星球半径，箝制在 [radius_min, radius_max]
    local r = storage.radius * util.random_exp(2)
    r = math.max(storage.radius_min, r)
    r = math.min(storage.radius_max, r)
    r = math.ceil(r)
    storage.radius_of[surface.name] = r

    mgs.width = r * 2 + 32
    mgs.height = r * 2 + 32
    mgs.starting_area = 1 + 2 * util.random_exp(2)

    -- 本轮整局气质（繁茂/岩石/危险/富庶/异物），与 map_features 共用同一套确定性旋钮 → 全局气质一致。
    local knobs = map_features.knobs()

    -- 母星
    if surface == game.surfaces.nauvis then
        surface.peaceful_mode = math.random(1, 5) == 1

        for _, res in pairs({'iron-ore', 'copper-ore', 'stone', 'coal', 'crude-oil'}) do
            set_resource(res, mgs)
        end
        for _, res in pairs({'uranium-ore'}) do
            set_resource(res, mgs, storage.local_specialty_multiplier)
        end
        random_nature_mgs(mgs, 'water')
        random_nature_mgs(mgs, 'nauvis_cliff')
        random_nature_mgs(mgs, 'starting_area_moisture')
        nature_by_knob(mgs, 'trees', knobs.verdancy)    -- 树：密度随繁茂度，规模多半小偶尔大
        nature_by_knob(mgs, 'rocks', knobs.rockiness)
        balance_mgs(mgs, 'enemy-base')   -- 虫巢密度影响难度 → 大概率正常

        -- 本轮气候用噪声【偏置】修改原生（连续，非离散主题）：偏湿→偏绿多树、偏干→偏沙、控温改群系，
        -- 由原生生成器自然铺开（不再硬抑制某地块家族）。每局母星调色板因此连续渐变。
        bias_climate(mgs, knobs)
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

        set_resource('gleba_stone', mgs, storage.local_specialty_multiplier * 2)

        balance_mgs(mgs, 'gleba_enemy_base')   -- 五足兽巢密度影响难度 → 大概率正常

        random_nature_mgs(mgs, 'gleba_water')
        nature_by_knob(mgs, 'gleba_plants', knobs.verdancy)   -- 草星植被同样随本轮繁茂度
        random_nature_mgs(mgs, 'gleba_cliff')
    end

    if surface == game.surfaces.aquilo then
        for _, res in pairs({'lithium_brine', 'fluorine_vent', 'aquilo_crude_oil'}) do
            set_resource(res, mgs, storage.local_specialty_multiplier * 0.5)
        end
    end

    surface.map_gen_settings = mgs

    -- 仅母星预先 chart 一块区域，方便玩家落地后立刻看清地形
    if surface ~= game.surfaces.nauvis then
        return
    end
    -- 每次跃迁后预先 chart 母星出生点附近（半径约 128），落地即可看清周围地形
    local radius = 128
    game.forces.player.chart(game.surfaces.nauvis, {{x = -radius, y = -radius}, {x = radius, y = radius}})

    -- 在出生点放金币市场。此时 surface.clear 已结算，放置的实体不会再被清掉。
    market.place_on_nauvis()
end)

-- 圆形地图：超出半径的格子全部铺成虚空。
script.on_event(defines.events.on_chunk_generated, function(event)
    local surface = event.surface
    local left_top = event.area.left_top

    local r = storage.radius_of[surface.name] or storage.radius

    -- 圆外格子铺虚空（整块都在圆内则跳过此段）
    if left_top.x * left_top.x + left_top.y * left_top.y >= r * r / 2 then
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
    end

    -- 各星球地图风味（本地特色矿/石/树/遗迹/冰山 + 跨星球异物 + 树木主题 + 虫群/物资箱）：
    -- 放在铺虚空【之后】，can_place_entity 自动跳过虚空/水/障碍。generate 内部按 PLANET[表面名]
    -- 自行判断，未定义的表面（飞船平台）直接跳过。详见 scripts/map_features.lua。
    map_features.generate(surface, left_top)
    -- 注意：不要在这里刷 GUI。区块生成极高频（每轮跃迁成百上千次），
    -- HUD 不依赖区块，刷新由 reset/玩家事件触发即可。
end)
