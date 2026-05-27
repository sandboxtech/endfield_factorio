-- 每次跃迁后随机生成各星球：地图设定、资源、自然要素、圆形边界。
local util = require('scripts.util')
local market = require('scripts.market')
local map_features = require('scripts.map_features')
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

-- 自然要素（水/悬崖/火山/岛屿）。
local function random_nature_mgs(mgs, name)
    local ac = mgs.autoplace_controls[name]
    if not ac then return end
    ac.frequency = util.random_nature()
    ac.size      = util.random_nature()
    ac.richness  = util.random_nature()
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
    ac.frequency = 0.6 + mood * 1.4   -- 下限抬高 → 低繁茂世界也不至于太秃
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
    -- 干湿整体偏湿（基线 +0.12）：多半略湿润，几乎不会强偏干 → 不再"湿度经常太低/满地荒漠"。
    pen['control:moisture:bias']      = tostring(0.12 + (knobs.verdancy - 0.5) * 0.4)
    pen['control:aux:bias']           = tostring(tri() * 0.35)                   -- 副维：沙/红沙调色
    pen['control:temperature:bias']   = tostring(tri() * 12)                     -- 温度：±~12°C 改变生物群系
    pen['control:moisture:frequency'] = tostring(0.6 + math.random() * 0.9)      -- 生物群系斑块大小(连续)
end

-- "染地世界"调色板（学 Comfy journey 'infested'）：在地面层盖半透明染色精灵，不改地块本身
-- （寻路/属性/资源都不变），只改观感 → 属"修改观感"而非"覆盖地形"。
local GROUND_TINT_PALETTE = {
    {r = 0.75, g = 0.0,  b = 0.15},  -- 血红
    {r = 0.6,  g = 0.0,  b = 0.6},   -- 紫（感染）
    {r = 0.1,  g = 0.5,  b = 0.05},  -- 毒绿
    {r = 0.35, g = 0.2,  b = 0.0},   -- 锈褐
}

-- 销毁某表面上现存的染地精灵（换图前清理，避免跨轮累积）。
local function clear_ground_tint(surface)
    for _, obj in pairs(rendering.get_all_objects()) do
        if obj.valid and obj.surface and obj.surface.index == surface.index then
            obj.destroy()
        end
    end
end

-- ── 噪声 tile 替换（罕见世界变体）─────────────────────────────────────────────
-- 每个世界可能有几条规则；每条 = {源 tile 家族 + 随机噪声通道 + 目标 tile}。噪声区(平滑大团)内的
-- 源 tile 换成目标 tile → 成片、部分替换。源取 Nauvis 自然 tile，目标取精选池（外星地表/液体/熔岩/虚空），
-- 不用字面全部 tile（避免随机出实验室/混凝土/过渡 tile 这种难看的）。
local REMAP_SRC = {   -- 随机选一个家族整体作为 from
    {'water', 'deepwater', 'water-green', 'deepwater-green', 'water-shallow', 'water-mud'},  -- 水族
    {'grass-1', 'grass-2', 'grass-3', 'grass-4'},                                            -- 草
    {'dry-dirt', 'dirt-1', 'dirt-2', 'dirt-3', 'dirt-4', 'dirt-5', 'dirt-6', 'dirt-7'},      -- 土
    {'sand-1', 'sand-2', 'sand-3'},                                                          -- 沙
    {'red-desert-0', 'red-desert-1', 'red-desert-2', 'red-desert-3'},                        -- 红沙
}
-- 目标池带权重：可走"换皮"地表常见；液体/熔岩中等稀有；虚空最稀有（不可走/危险）。
local REMAP_DST = {
    {w = 8, t = 'volcanic-ash-flats'}, {w = 8, t = 'volcanic-soil-dark'}, {w = 6, t = 'volcanic-jagged-ground'},
    {w = 8, t = 'fulgoran-dunes'},     {w = 6, t = 'fulgoran-sand'},
    {w = 8, t = 'snow-flat'},          {w = 6, t = 'dust-flat'},          {w = 6, t = 'ice-rough'},
    {w = 6, t = 'wetland-green'},      {w = 6, t = 'lowland-olive-blubber'}, {w = 6, t = 'midland-yellow-crust'},
    {w = 6, t = 'natural-yumako-soil'}, {w = 5, t = 'nuclear-ground'},
    {w = 4, t = 'oil-ocean-deep'},     {w = 3, t = 'ammoniacal-ocean'},   {w = 3, t = 'gleba-deep-lake'},  -- 液体(不可走)
    {w = 2, t = 'lava'},                                                                                  -- 熔岩(烧人)
    {w = 1, t = 'empty-space'},                                                                           -- 虚空(掉落)
}
local REMAP_DST_TOTAL = 0
for _, d in ipairs(REMAP_DST) do REMAP_DST_TOTAL = REMAP_DST_TOTAL + d.w end
local function pick_remap_dst()
    local r, acc = math.random() * REMAP_DST_TOTAL, 0
    for _, d in ipairs(REMAP_DST) do
        acc = acc + d.w
        if r <= acc then return d.t end
    end
    return REMAP_DST[1].t
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

    -- 染地世界：小概率出现（诡异世界更可能）。出现时 alpha 走立方曲线 → 大概率温和淡染、
    -- 小概率浓重得像 infested。先清掉本表面上一轮的染色精灵，再决定本轮是否/如何染。
    clear_ground_tint(surface)
    storage.ground_tint = storage.ground_tint or {}
    storage.ground_tint[surface.name] = nil
    if math.random() < 0.06 + 0.25 * knobs.exotic then
        local c = GROUND_TINT_PALETTE[math.random(#GROUND_TINT_PALETTE)]
        local a = 0.05 + (math.random() ^ 3) * 0.32   -- 多半 ~0.05–0.12 淡染；极少 ~0.37 浓染(infested 感)
        storage.ground_tint[surface.name] = {r = c.r, g = c.g, b = c.b, a = a}
    end

    -- 噪声 tile 替换：小概率世界，本轮生成 1~3 条随机规则(源家族 + 噪声 + 目标 tile)。
    storage.tile_remap = storage.tile_remap or {}
    storage.tile_remap[surface.name] = nil
    if math.random() < 0.05 + 0.25 * knobs.exotic then
        local rules = {}
        for _ = 1, math.random(1, 3) do
            rules[#rules + 1] = {
                from = REMAP_SRC[math.random(#REMAP_SRC)],
                to = pick_remap_dst(),
                seed = math.random(1, 4294967295),
                threshold = -0.15 + math.random() * 0.55,   -- 低=大片替换，高=零星斑块
            }
        end
        storage.tile_remap[surface.name] = rules
    end

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
        -- starting_area_moisture 用原版默认（出生区本就湿润），不再随机到极干
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

    -- 噪声 tile 替换：本轮该表面的每条规则，把噪声区(平滑大团)内的源 tile 换成目标 tile。
    -- 只动匹配到的 tile（圆外已是虚空、不匹配），成片部分替换。仅替换世界(罕见)才进此分支。
    local remap = storage.tile_remap and storage.tile_remap[surface.name]
    if remap then
        for _, rule in ipairs(remap) do
            local found = surface.find_tiles_filtered{name = rule.from, area = {{left_top.x, left_top.y}, {left_top.x + 32, left_top.y + 32}}}
            if #found > 0 then
                local tiles = {}
                for _, t in pairs(found) do
                    local p = t.position
                    if noise.fractal(noise.octaves.smooth, p.x, p.y, rule.seed) > rule.threshold then
                        tiles[#tiles + 1] = {name = rule.to, position = p}
                    end
                end
                if #tiles > 0 then surface.set_tiles(tiles) end
            end
        end
    end

    -- 染地世界：本轮该表面若被选中，在地面层盖一张缩放到整块(32×32)的半透明染色精灵。
    -- 不改地块本身，只改观感。仅圆内区块绘制（圆外多是虚空，跳过省开销）。
    local gt = storage.ground_tint and storage.ground_tint[surface.name]
    if gt then
        local cx, cy = left_top.x + 16, left_top.y + 16
        if cx * cx + cy * cy <= r * r then
            rendering.draw_sprite{
                sprite = 'tile/lab-dark-2', x_scale = 32, y_scale = 32,
                target = {cx, cy}, surface = surface,
                tint = gt, render_layer = 'ground-layer-1',
            }
        end
    end
    -- 注意：不要在这里刷 GUI。区块生成极高频（每轮跃迁成百上千次），
    -- HUD 不依赖区块，刷新由 reset/玩家事件触发即可。
end)
