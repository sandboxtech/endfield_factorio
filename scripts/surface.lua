-- 每次跃迁后随机生成各星球：地图设定、资源、自然要素、圆形边界。
local util = require('scripts.util')
local market = require('scripts.market')
local noise = require('scripts.noise')

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

    -- 母星
    if surface == game.surfaces.nauvis then
        surface.peaceful_mode = math.random(1, 5) == 1

        for _, res in pairs({'iron-ore', 'copper-ore', 'stone', 'coal', 'crude-oil'}) do
            set_resource(res, mgs)
        end
        for _, res in pairs({'uranium-ore'}) do
            set_resource(res, mgs, storage.local_specialty_multiplier)
        end
        for _, res in pairs({'water', 'trees', 'rocks', 'nauvis_cliff', 'starting_area_moisture'}) do
            random_nature_mgs(mgs, res)
        end
        balance_mgs(mgs, 'enemy-base')   -- 虫巢密度影响难度 → 大概率正常

        -- 地表主题（纯表现，大幅改观）：靠 property_expression_names 抑制某些地块家族
        -- （常量 -1000 = 该地块永不生成，是该字段的标准运行时用法），让每局母星调色板大变。
        --   1 草原（去沙/红沙→偏绿）  2 荒漠（去草→偏沙）  3 焦土（去草+沙→偏土/红）  4 默认混合
        mgs.property_expression_names = mgs.property_expression_names or {}
        local function suppress(...)
            for _, t in ipairs({...}) do
                mgs.property_expression_names['tile:' .. t .. ':probability'] = -1000
            end
        end
        local theme = math.random(1, 4)
        if theme == 1 then
            suppress('sand-1', 'sand-2', 'sand-3', 'red-desert-0', 'red-desert-1', 'red-desert-2', 'red-desert-3')
        elseif theme == 2 then
            suppress('grass-1', 'grass-2', 'grass-3', 'grass-4')
        elseif theme == 3 then
            suppress('grass-1', 'grass-2', 'grass-3', 'grass-4', 'sand-1', 'sand-2', 'sand-3')
        end
        if math.random(1, 4) == 1 then suppress('deepwater') end   -- 1/4 额外"少深水"
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
        random_nature_mgs(mgs, 'gleba_plants')
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

-- 母星撒废料：【逐格】用 simplex 分形噪声（scripts/noise，scrapyard 倍频）判断，超阈值就放 scrap。
-- simplex 平滑、不重复、跨区块连续 → 废料连成自然矿场（不是每块一个方块、也无正弦条纹）。
-- 按本轮 storage.run 派生种子 → 本轮全图同一噪声场（团块跨区块连片），每轮布局不同。
-- scrap 需回收机才能拆 → 中后期福利。SCRAP_THRESHOLD 越高越稀；储量随噪声值由中心向外递减。
local SCRAP_THRESHOLD = 0.58   -- 分形输出约 [-1,1] 集中在 0 附近；阈值越高废料越稀、团块越小

local function scatter_scrap(surface, left_top)
    local seed = (storage.run or 0) * 1009 + 31
    -- "偶尔的风味"：只有约 40% 的轮次有废料，其余轮次完全没有
    if noise.hash01(seed * 5.1) >= 0.4 then return end
    -- 本轮专属变换：决定矿脉是圆团还是长条、朝哪个方向、多大（同一轮全图一致 → 团块跨区块连片）
    local angle, stretch, zoom = noise.seeded_transform(seed)
    for x = 0, 31 do
        for y = 0, 31 do
            local px, py = left_top.x + x, left_top.y + y
            local nv = noise.fractal_warped(noise.octaves.scrapyard, px, py, seed, angle, stretch, zoom)
            if nv > SCRAP_THRESHOLD then
                local pos = {x = px + 0.5, y = py + 0.5}
                if surface.can_place_entity{name = 'scrap', position = pos} then
                    surface.create_entity{name = 'scrap', amount = math.floor(200 + (nv - SCRAP_THRESHOLD) * 4000), position = pos}
                end
            end
        end
    end
end

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

    -- 母星撒废料：放在铺虚空【之后】，can_place_entity 会自动跳过虚空/水，无需判断边界
    if surface == game.surfaces.nauvis then
        scatter_scrap(surface, left_top)
    end
    -- 注意：不要在这里刷 GUI。区块生成极高频（每轮跃迁成百上千次），
    -- HUD 不依赖区块，刷新由 reset/玩家事件触发即可。
end)
