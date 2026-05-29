-- 每次跃迁后随机生成各星球：地图设定、资源、自然要素、圆形边界。
local util = require('scripts.util')
local market = require('scripts.market')
local map_features = require('scripts.map_features')
local noise = require('scripts.noise')
local constants = require('scripts.constants')

-- 各"世界变体"出现概率的可调常量（默认 1，游戏内 /c storage.prob_danger=3 之类即可动态调）。
local function prob(key) return storage['prob_' .. key] or 1 end

-- debug 打印：只发给在线管理员，不刷屏所有玩家。
local function debug_print(msg)
    for _, p in pairs(game.connected_players) do
        if p.admin then p.print(msg) end
    end
end

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
local function random_nature_mgs(mgs, name, value)
    if not value then value = 3 end
    local ac = mgs.autoplace_controls[name]
    if not ac then return end
    ac.frequency = util.random_exp(value)
    ac.size      = util.random_exp(value)
    ac.richness  = util.random_exp(value)
end

-- 水域：frequency/size 保底 0.5，避免 random_exp 抽到极小值（可低至 0.125）导致"缺水世界"。
local function random_water_mgs(mgs, name, value)
    if not value then value = 3 end
    local ac = mgs.autoplace_controls[name]
    if not ac then return end
    ac.frequency = math.max(0.5, util.random_exp(value) + 0.25)
    ac.size      = math.max(0.5, util.random_exp(value))
    ac.richness  = util.random_exp(value) + 0.25
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

-- "染地世界"调色板：在地面层盖半透明染色精灵，不改地块本身
-- （寻路/属性/资源都不变），只改观感 → 属"修改观感"而非"覆盖地形"。
local GROUND_TINT_PALETTE = {
    {r = 0.75, g = 0.0,  b = 0.15},  -- 血红
    {r = 0.6,  g = 0.0,  b = 0.6},   -- 紫（感染）
    {r = 0.1,  g = 0.5,  b = 0.05},  -- 毒绿
    {r = 0.35, g = 0.2,  b = 0.0},   -- 锈褐
}

-- 清理染地精灵（换图前调用，避免跨轮累积）。染地 sprite 是本场景【唯一】的 rendering 对象，
-- 故直接一次清空全部即可，不必按 surface 过滤；新一轮的染色在 on_chunk_generated 重绘。
local function clear_ground_tint()
    rendering.clear()
end

-- ── tile 替换（世界变体）──────────────────────────────────────────────────────
-- 把地形分几类，规则形如「源家族 → 目标 tile」：
--   · 同类替换(水→另一种水, 某地表→另一种地表) = 自然，高概率，整片替换、不用噪声；
--   · 跨类替换(地→水/熔岩/虚空 等) = 戏剧化，低概率，用平滑大团噪声成片、不满图。
-- 目标池【白名单穷举】各星自然 tile（排除法挡不住套色生成的彩色混凝土等人造 tile，故改穷举）。
-- valid_pools 会按 prototypes.tile 过滤掉拼错/不存在的，所以这里宁可多列。人造 tile 一律不在列。
-- void/space 与 artificial(人造) 不在此白名单——它们是【受 mask 限制】的特殊目标池，由 valid_pools 另建：
--   voidspace(empty-space/out-of-map) 仅 noise mask 可选；artificial(混凝土系等) 仅 ore mask 可选。
local TILE_CLASS = {
    water  = {  -- 常规水(可整片替换的安全自然水：仍可泵/可作 all 目标)
        'water', 'deepwater', 'water-green', 'deepwater-green', 'water-shallow', 'water-mud', 'gleba-deep-lake',
    },
    exotic = {  -- 危险/异界液体 + 虚空太空（合并 hazard+void）：仅 noise mask 作目标，成片部分替换
        'lava', 'lava-hot',                                 -- 岩浆（lava-2 是 tile-effect 不是 tile，勿加）
        'oil-ocean-deep', 'oil-ocean-shallow',              -- 油海（oil-deep 是 tile-effect 不是 tile）
        'ammoniacal-ocean', 'ammoniacal-ocean-2',           -- 氨海
        'empty-space', 'out-of-map',                        -- 虚空/太空
    },
    artificial = {  -- 人造铺装（仅 ore mask 作目标）：混凝土系 + 9 色套色精制混凝土 + 铺路/landfill/地基
        'concrete', 'refined-concrete', 'hazard-concrete-left', 'hazard-concrete-right',
        'refined-hazard-concrete-left', 'refined-hazard-concrete-right',
        'stone-path', 'landfill', 'foundation', 'space-platform-foundation',
        'blue-refined-concrete', 'orange-refined-concrete', 'yellow-refined-concrete', 'pink-refined-concrete',
        'purple-refined-concrete', 'black-refined-concrete', 'brown-refined-concrete', 'cyan-refined-concrete', 'acid-refined-concrete',
    },
    ground = {                                      -- 可走地表(各星)
        -- 母星
        'grass-1', 'grass-2', 'grass-3', 'grass-4',
        'dry-dirt', 'dirt-1', 'dirt-2', 'dirt-3', 'dirt-4', 'dirt-5', 'dirt-6', 'dirt-7',
        'sand-1', 'sand-2', 'sand-3', 'red-desert-0', 'red-desert-1', 'red-desert-2', 'red-desert-3', 'nuclear-ground',
        -- 火星
        'volcanic-jagged-ground', 'volcanic-cracks', 'volcanic-cracks-hot', 'volcanic-cracks-warm',
        'volcanic-folds', 'volcanic-folds-flat', 'volcanic-folds-warm',
        'volcanic-ash-light', 'volcanic-ash-dark', 'volcanic-ash-flats', 'volcanic-ash-cracks', 'volcanic-ash-soil',
        'volcanic-pumice-stones', 'volcanic-smooth-stone', 'volcanic-smooth-stone-warm', 'volcanic-soil-dark', 'volcanic-soil-light',
        -- 雷星
        'fulgoran-dunes', 'fulgoran-sand', 'fulgoran-rock', 'fulgoran-paving', 'fulgoran-walls', 'fulgoran-conduit', 'fulgoran-machinery',
        -- 草星
        'artificial-yumako-soil', 'overgrowth-yumako-soil', 'artificial-jellynut-soil', 'overgrowth-jellynut-soil',
        'natural-yumako-soil', 'natural-jellynut-soil',
        'lowland-olive-blubber', 'lowland-olive-blubber-2', 'lowland-olive-blubber-3', 'lowland-brown-blubber',
        'lowland-pale-green', 'lowland-cream-cauliflower', 'lowland-cream-cauliflower-2', 'lowland-dead-skin', 'lowland-dead-skin-2',
        'lowland-cream-red', 'lowland-red-vein', 'lowland-red-vein-2', 'lowland-red-vein-3', 'lowland-red-vein-4', 'lowland-red-vein-dead', 'lowland-red-infection',
        'midland-cracked-lichen', 'midland-cracked-lichen-dull', 'midland-cracked-lichen-dark',
        'midland-turquoise-bark', 'midland-turquoise-bark-2',
        'midland-yellow-crust', 'midland-yellow-crust-2', 'midland-yellow-crust-3', 'midland-yellow-crust-4',
        'highland-dark-rock', 'highland-dark-rock-2', 'highland-yellow-rock', 'pit-rock',
        'wetland-yumako', 'wetland-jellynut', 'wetland-dead-skin', 'wetland-light-dead-skin',
        'wetland-green-slime', 'wetland-light-green-slime', 'wetland-red-tentacle', 'wetland-pink-tentacle', 'wetland-blue-slime',
        -- 极地
        'snow-flat', 'snow-crests', 'snow-lumpy', 'snow-patchy', 'dust-flat', 'dust-crests', 'dust-lumpy', 'dust-patchy',
        'ice-rough', 'ice-smooth', 'ice-platform', 'brash-ice',   -- brash-ice-2 是 tile-effect 不是 tile
    },
}
-- 源家族【按星球分类】：只从该星球实际存在的 tile 里选源（否则像在 Nauvis 替换 Fulgora 地形 → 永不发生）。
-- 每个 = {class(water/ground), tiles=子家族}；替换其一仍保留其他 → 地貌不单调。目标用全局自动目标池（跨星变样）。
local PLANET_SRC = {
    nauvis = {
        -- full = 整片替换时的安全目标（只换成仍可泵的真水，排除浅水/泥 → 不会让母星缺水）
        {class = 'water',  tiles = {'water', 'deepwater', 'water-green', 'deepwater-green', 'water-shallow', 'water-mud'},
            full = {'water', 'deepwater', 'water-green', 'deepwater-green'}},
        {class = 'ground', tiles = {'grass-1', 'grass-2', 'grass-3', 'grass-4'}},
        {class = 'ground', tiles = {'dry-dirt', 'dirt-1', 'dirt-2', 'dirt-3', 'dirt-4', 'dirt-5', 'dirt-6', 'dirt-7'}},
        {class = 'ground', tiles = {'sand-1', 'sand-2', 'sand-3', 'red-desert-0', 'red-desert-1', 'red-desert-2', 'red-desert-3'}},
    },
    vulcanus = {
        {class = 'water',  tiles = {'lava', 'lava-hot'}},
        {class = 'ground', tiles = {'volcanic-ash-flats', 'volcanic-ash-dark', 'volcanic-ash-light', 'volcanic-ash-soil'}},
        {class = 'ground', tiles = {'volcanic-soil-dark', 'volcanic-soil-light', 'volcanic-jagged-ground', 'volcanic-pumice-stones', 'volcanic-smooth-stone'}},
        {class = 'ground', tiles = {'volcanic-cracks', 'volcanic-cracks-hot', 'volcanic-cracks-warm', 'volcanic-folds', 'volcanic-folds-flat', 'volcanic-folds-warm'}},
    },
    fulgora = {
        {class = 'water',  tiles = {'oil-ocean-deep', 'oil-ocean-shallow'}},
        {class = 'ground', tiles = {'fulgoran-dunes', 'fulgoran-sand', 'fulgoran-dust'}},
        {class = 'ground', tiles = {'fulgoran-rock', 'fulgoran-conduit', 'fulgoran-machinery', 'fulgoran-paving', 'fulgoran-walls'}},
    },
    gleba = {
        {class = 'water',  tiles = {'gleba-deep-lake'}},
        {class = 'ground', tiles = {'lowland-olive-blubber', 'lowland-brown-blubber', 'lowland-pale-green', 'lowland-cream-cauliflower', 'lowland-dead-skin'}},
        {class = 'ground', tiles = {'midland-yellow-crust', 'midland-cracked-lichen', 'midland-turquoise-bark'}},
        {class = 'ground', tiles = {'highland-dark-rock', 'highland-yellow-rock', 'natural-yumako-soil', 'natural-jellynut-soil'}},
    },
    aquilo = {
        {class = 'water',  tiles = {'ammoniacal-ocean', 'ammoniacal-ocean-2'}},
        {class = 'ground', tiles = {'snow-flat', 'snow-lumpy', 'snow-patchy', 'snow-crests'}},
        {class = 'ground', tiles = {'ice-rough', 'ice-smooth', 'brash-ice', 'ice-platform'}},
        {class = 'ground', tiles = {'dust-flat', 'dust-lumpy', 'dust-patchy', 'dust-crests'}},
    },
}
-- 常规自然目标类：同类高概率、水↔地次之（exotic 与 artificial 不在这里——它们各受 mask 限制，见 pick_target）。
local function pick_natural_class(src_class)
    if math.random() < constants.balance.tile_same_class then return src_class end
    return src_class == 'water' and 'ground' or 'water'
end
-- 运行时按 prototypes.tile 过滤掉无效 tile 名（拼错的自动丢弃，避免 set_tiles/find_tiles 报 unknown tile）。
-- prototypes 不变 → 建一次缓存。被丢弃的无效名记入 INVALID_TILES，debug 时进游戏打印一次（提示拼错）。
local VALID_TILES
local INVALID_TILES = {}
local INVALID_REPORTED = false
local function valid_pools()
    if VALID_TILES then return VALID_TILES end
    -- 按 prototypes.tile 过滤白名单(拼错/不存在的丢弃并记入 INVALID_TILES)。
    local function filt(list)
        local out = {}
        for _, n in ipairs(list) do
            if prototypes.tile[n] then out[#out + 1] = n else INVALID_TILES[#INVALID_TILES + 1] = n end
        end
        return out
    end
    -- 目标池：穷举白名单 TILE_CLASS（water/ground/exotic/artificial），过滤后只含存在的 tile。
    local class = {}
    for k, v in pairs(TILE_CLASS) do class[k] = filt(v) end
    -- 源：PLANET_SRC 同样按星球过滤
    local src = {}
    for planet, families in pairs(PLANET_SRC) do
        local fs = {}
        for _, s in ipairs(families) do
            local t = filt(s.tiles)
            if #t > 0 then fs[#fs + 1] = {class = s.class, tiles = t, full = s.full and filt(s.full)} end
        end
        src[planet] = fs
    end
    VALID_TILES = {class = class, src = src}
    if #INVALID_TILES > 0 then log('[endfield] 无效源 tile 名(已忽略): ' .. table.concat(INVALID_TILES, ', ')) end
    return VALID_TILES
end
local function rand_tile(class)
    local p = valid_pools().class[class]
    if not p or #p == 0 then return nil end
    return p[math.random(#p)]
end

-- 部分替换(非 all)时选目标，按 mask 限制特殊池：
--   noise → 一定概率取 exotic(岩浆/油海/氨海/虚空/太空)；ore → 一定概率取 artificial(人造铺装)；
--   其余走常规自然(水/地)。tree/rock 只会落到自然。
local function pick_target(src, mask)
    if mask == 'noise' and math.random() < constants.balance.tile_to_exotic then return rand_tile('exotic') end
    if mask == 'ore' and math.random() < constants.balance.tile_to_artificial then return rand_tile('artificial') end
    return rand_tile(pick_natural_class(src.class))
end

-- 各星球【资源/自然/气候】声明式配置（替代原先每星球一段 if 链）。逐字段含义：
--   res       普通资源名列表（用全局倍率，set_resource 默认 specialty_mult=1）
--   specialty {资源名, 额外丰度系数}：丰度再乘 local_specialty_multiplier × 系数（地方特产压低）
--   water     random_water_mgs（频率/丰度略抬，保证可泵水）
--   nature    random_nature_mgs（悬崖/火山/岛屿等自然要素）
--   knob      {autoplace名, 旋钮名}：nature_by_knob，密度随本轮整局气质（树/石/植被）
--   balance   balance_mgs（敌人巢：大概率正常密度）
--   peaceful  true → 1/balance.peaceful_one_in 概率开宁和模式
--   climate   true → bias_climate（仅母星，噪声偏置整星干湿冷热）
-- 飞船平台等不在表内的表面直接跳过。starting_area_moisture 一律用原版默认（出生区本就湿润）。
local PLANET_GEN = {
    nauvis = {
        peaceful = true,
        res       = {'iron-ore', 'copper-ore', 'stone', 'coal', 'crude-oil'},
        specialty = {{'uranium-ore', 1}},
        water     = {'water'},
        nature    = {'nauvis_cliff'},
        knob      = {{'trees', 'verdancy'}, {'rocks', 'rockiness'}},
        balance   = {'enemy-base'},
        climate   = true,
    },
    vulcanus = {
        res       = {'vulcanus_coal', 'calcite', 'sulfuric_acid_geyser'},
        specialty = {{'tungsten_ore', 1}},
        nature    = {'vulcanus_volcanism'},
    },
    fulgora = {
        specialty = {{'scrap', 1}},
        nature    = {'fulgora_islands', 'fulgora_cliff'},
    },
    gleba = {
        peaceful  = true,
        specialty = {{'gleba_stone', 2}},
        water     = {'gleba_water'},
        nature    = {'gleba_cliff'},
        knob      = {{'gleba_plants', 'verdancy'}},
        balance   = {'gleba_enemy_base'},
    },
    aquilo = {
        specialty = {{'lithium_brine', 0.5}, {'fluorine_vent', 0.5}, {'aquilo_crude_oil', 0.5}},
    },
}

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
    -- 随机当地时间作为本轮起点（非冻结世界之后照常昼夜循环）：大概率落在白天，避免一跃迁就摸黑。
    -- daytime：0=正午最亮，0.5=午夜最暗，0.25/0.75≈晨昏。（下方永昼/永夜分支会覆盖此值）
    if math.random() < 0.8 then
        surface.daytime = ((math.random() - 0.5) * 0.3) % 1   -- 80%：落在正午附近 [0,0.15]∪[0.85,1) = 全白天
    else
        surface.daytime = math.random()                       -- 20%：完全随机（含晨昏/夜，保留多样性）
    end
    surface.wind_speed = 0.02 * (0.5 + math.random())
    surface.wind_orientation = math.random()
    surface.wind_orientation_change = 0.0001 * (0.5 + math.random())

    -- 外观随机（纯表现）：brightness_visual_weights = 昼夜明暗(brightness)对各通道 LUT 的【影响权重】。
    --   引擎公式 LUT ×= (1-w) + brightness×w：w 越大 → 画面越紧贴昼夜曲线、非正午越暗；
    --   默认 {0,0,0} = 完全不受影响、永远全亮。【所以权重越大越暗，不是越亮】——故只取很小的值：
    --   常态白天基本全亮、只在晨昏/夜里透出极淡色调；1/6 概率色调略强（仍只在非正午显现）。
    local cr, cg, cb
    if math.random(1, 6) == 1 then
        cr = 0.15 + math.random() * 0.5   -- 0.15~0.65 各自独立 → 通道差异大 = 较强色调（晨昏/夜显现）
        cg = 0.15 + math.random() * 0.5
        cb = 0.15 + math.random() * 0.5
    else
        local base = 0.08 + 0.12 * math.random()   -- 0.08~0.20 极弱影响 → 白天几乎全亮
        cr = base + (math.random() - 0.5) * 0.10    -- 通道间小幅错开 → 极淡色调
        cg = base + (math.random() - 0.5) * 0.10
        cb = base + (math.random() - 0.5) * 0.10
    end
    surface.brightness_visual_weights = {r = cr, g = cg, b = cb}
    surface.min_brightness = 0.4 * math.random()         -- 夜晚黑暗程度 0~0.4（0=漆黑），纯表现
    surface.show_clouds = math.random(1, 5) > 1          -- 1/5 概率无云，纯表现
    -- 阳光强度影响太阳能发电（玩法）→ 大概率正常、小概率小幅偏离
    surface.solar_power_multiplier = util.mostly_normal()

    -- aquilo 不参与永夜/永昼抽奖（本来就极地气候）。永昼优先且概率更高，永夜更稀有：
    --   永昼 ≈ 1/3；永夜 ≈ (剩余 2/3) × 1/10 ≈ 6.7%；其余为正常昼夜循环。
    local polar = surface == game.surfaces.aquilo
    if not polar and math.random(1, 3) == 1 then
        surface.freeze_daytime = true
        surface.daytime = 0      -- 永昼
    elseif not polar and math.random(1, 10) == 1 then
        surface.freeze_daytime = true
        surface.daytime = 0.56   -- 永夜
    end

    -- 刷新星球半径，箝制在 [radius_min, radius_max]（默认值见 constants.ensure_defaults）
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

    -- 各"世界变体"出现概率都乘以一个 storage 常量(默认 1，可游戏内 /c storage.prob_xxx=N 动态调)。
    local dbg = {}   -- debug 模式下汇总本表面生成的变体属性

    -- 染地世界：小概率出现（诡异世界更可能）。出现时 alpha 走立方曲线 → 大概率温和淡染、
    -- 小概率浓重。先清掉本表面上一轮的染色精灵，再决定本轮是否/如何染。
    clear_ground_tint()
    storage.ground_tint[surface.name] = nil
    local bt = constants.balance.ground_tint
    if math.random() < (bt.base + bt.exotic * knobs.exotic) * prob('ground_tint') then
        local c = GROUND_TINT_PALETTE[math.random(#GROUND_TINT_PALETTE)]
        local a = 0.05 + (math.random() ^ 3) * 0.32   -- 多半 ~0.05–0.12 淡染；极少 ~0.37 浓染
        storage.ground_tint[surface.name] = {r = c.r, g = c.g, b = c.b, a = a}
        dbg[#dbg + 1] = string.format('tint a=%.2f', a)
    end

    -- tile 替换世界：较常见（多为自然同类替换），本轮 1~3 条规则。每条 = 源家族 → 目标 tile + 一种 mask：
    --   all  整片换(自然同类多用，不结合噪声)   noise 平滑大团噪声成片
    --   tree/rock/ore 跟随【2.0 原生的树/石/矿分布】替换 → 森林地面/岩屑带/矿脉晕染，非常组织化。
    storage.tile_remap[surface.name] = nil
    local srcs = valid_pools().src[surface.name]
    local br = constants.balance.tile_remap
    if srcs and #srcs > 0 and math.random() < (br.base + br.exotic * knobs.exotic) * prob('tile_remap') then
        local rules = {}
        local nrules = 1 + math.floor(math.random() ^ 2 * (storage.tile_remap_rules or 3))   -- 偏向少：多半 1 条
        for _ = 1, nrules do
            local src = srcs[math.random(#srcs)]
            -- 先定 mask：~45% all(整片自然，安全)，否则 noise/跟随树石矿。
            local mask = (math.random() < constants.balance.tile_mask_all) and 'all'
                or ({'noise', 'noise', 'tree', 'rock', 'ore'})[math.random(5)]
            -- 选目标。【约束】all 整片替换不能让星球缺资源：水源→同功能水(full，仍可泵)、地源→任意地表；
            -- exotic(岩浆/油海/氨海/虚空) 只走 noise、artificial(人造铺装) 只走 ore，且都是部分替换(原 tile 仍保留)。
            local to
            if mask == 'all' then
                if src.class == 'water' then
                    local fp = src.full or src.tiles
                    to = fp[math.random(#fp)]
                else
                    to = rand_tile('ground')
                end
            else
                to = pick_target(src, mask)
            end
            if to then
                rules[#rules + 1] = {
                    from = src.tiles, to = to, mask = mask,
                    seed = math.random(1, 4294967295),
                    -- noise mask 覆盖面非线性：多半小斑块(阈值高)、极小概率大片(阈值低)。
                    threshold = 0.45 - math.random() ^ 3 * 0.6,
                }
                dbg[#dbg + 1] = string.format('%s→%s/%s', src.tiles[1], to, mask)
            end
        end
        if #rules > 0 then storage.tile_remap[surface.name] = rules end
    end

    -- 危险世界：每星球独立滚（概率 = knobs.danger × prob_danger，prob_danger=0 即关闭）。
    -- 各敌人类型【独立】开关 → 组合多样(只沙虫 / 只机枪炮塔 / 虫+重炮 …)；机枪弹种随危险度；
    -- 35% 还带"复制虫"(建筑被虫破坏冒虫，事件驱动见 world_fx.lua)。具体放置在 map_features.feat_danger。
    storage.danger_theme[surface.name] = nil
    if math.random() < knobs.danger * prob('danger') then
        local bd = constants.balance.danger
        -- 机枪炮塔弹种不再全星统一，改为每个炮塔各自随机（见 map_features.pick_mag），故 theme 不再存 mag。
        local t = {
            worm    = math.random() < bd.worm,       -- 沙虫炮塔
            spawner = math.random() < bd.spawner,    -- 虫巢
            turret  = math.random() < bd.turret,     -- 敌方机枪炮塔(带弹)
            mine    = math.random() < bd.mine,       -- 敌方地雷
            art     = math.random() < bd.art_base + bd.art_danger * knobs.danger,   -- 敌方重炮(更稀，随危险度)
            replicant = math.random() < bd.replicant,
        }
        if not (t.worm or t.spawner or t.turret or t.mine or t.art) then t.worm = true end   -- 至少一种
        storage.danger_theme[surface.name] = t
        local on = {}
        for _, k in ipairs({'worm', 'spawner', 'turret', 'mine', 'art'}) do if t[k] then on[#on + 1] = k end end
        if t.replicant then on[#on + 1] = 'replicant' end
        dbg[#dbg + 1] = 'danger:' .. table.concat(on, '+')
    end

    -- 事件世界：每分钟触发一种事件（独立于危险度，奖励/危险皆有）。详见 tick.lua run_world_events。
    --   raid 空降虫 / meteor 矿石陨石雨 / supply 物资空投 / coinfall 金币雨 / drones 无人机来袭 / barrage 重炮落点。
    storage.event_world[surface.name] = nil
    if math.random() < constants.balance.event.base * prob('event') then
        -- 只从【已启用】的事件类型里【按权重】滚（false 排除；权重见 balance.event.weights，缺省 1，drones 更低 → 更罕见）
        local weights = constants.balance.event.weights or {}
        local pool, total = {}, 0
        for _, et in ipairs({'raid', 'meteor', 'supply', 'coinfall', 'drones', 'barrage'}) do
            if storage.event_types[et] ~= false then   -- nil/true 启用，仅显式 false 排除
                local w = weights[et] or 1
                pool[#pool + 1] = {et = et, w = w}
                total = total + w
            end
        end
        if total > 0 then
            local r, acc = math.random() * total, 0
            for _, e in ipairs(pool) do
                acc = acc + e.w
                if r <= acc then
                    storage.event_world[surface.name] = e.et
                    dbg[#dbg + 1] = 'event:' .. e.et
                    break
                end
            end
        end
    end

    -- 战利品风格：四类箱子(钢=材料/铁=设备/木=宝箱/永续)各自【独立】的本世界密度，分布 = random()^2：
    -- 大概率低密度(箱子少)、小概率高密度(遍地)，四者互不相关。箱子外观=内容含义已固定，不再随机选箱体。
    storage.loot_style[surface.name] = {
        material  = math.random() ^ 2,   -- 钢箱(材料箱)
        equipment = math.random() ^ 2,   -- 铁箱(设备箱)
        treasure  = math.random() ^ 2,   -- 木箱(宝箱)
        perp      = math.random() ^ 2,   -- 永续(无底)箱
    }
    -- debug 摘要：四类箱子各自的本世界密度[0,1]。
    local ls = storage.loot_style[surface.name]
    dbg[#dbg + 1] = string.format('loot material=%.2f equip=%.2f treasure=%.2f perp=%.2f',
        ls.material, ls.equipment, ls.treasure, ls.perp)

    -- 本表面生成摘要：【始终】缓存进 storage.gen_debug[星球]（与 storage.debug 无关），
    -- 供管理员随时用 /gen 查看（不公告其他玩家）。storage.debug 仅控制是否【实时】打给在线管理员。
    local summary = string.format('[gen] %s r=%d: verdancy=%.2f rockiness=%.2f riches=%.2f danger=%.2f exotic=%.2f | %s',
        surface.name, storage.radius_of[surface.name] or 0,
        knobs.verdancy, knobs.rockiness, knobs.riches, knobs.danger, knobs.exotic,
        #dbg > 0 and table.concat(dbg, ', ') or '普通')
    storage.gen_debug[surface.name] = summary

    if storage.debug then
        if not INVALID_REPORTED and #INVALID_TILES > 0 then
            INVALID_REPORTED = true
            debug_print('[gen] 无效 tile 名(已忽略): ' .. table.concat(INVALID_TILES, ', '))
        end
        debug_print(summary)
    end

    -- 按 PLANET_GEN 配置生成各星球资源/自然/气候（飞船平台等不在表内 → 跳过）。
    local cfg = PLANET_GEN[surface.name]
    if cfg then
        if cfg.peaceful then surface.peaceful_mode = math.random(1, constants.balance.peaceful_one_in) == 1 end
        for _, res in ipairs(cfg.res or {}) do set_resource(res, mgs) end
        for _, sp in ipairs(cfg.specialty or {}) do
            set_resource(sp[1], mgs, storage.local_specialty_multiplier * sp[2])
        end
        for _, w in ipairs(cfg.water or {}) do random_water_mgs(mgs, w) end
        for _, n in ipairs(cfg.nature or {}) do random_nature_mgs(mgs, n) end
        for _, kn in ipairs(cfg.knob or {}) do nature_by_knob(mgs, kn[1], knobs[kn[2]]) end
        for _, b in ipairs(cfg.balance or {}) do balance_mgs(mgs, b) end
        if cfg.climate then bias_climate(mgs, knobs) end
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

    local r = storage.radius_of[surface.name] or storage.radius or 2048

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
        if #tiles > 0 then   -- tiles 是 table.insert 连续数组、无空洞，# 与 table_size 等价且更快
            surface.set_tiles(tiles)
        end
    end

    -- 各星球地图风味（本地特色矿/石/树/遗迹/冰山 + 跨星球异物 + 树木主题 + 虫群/物资箱）：
    -- 放在铺虚空【之后】，can_place_entity 自动跳过虚空/水/障碍。generate 内部按 PLANET[表面名]
    -- 自行判断，未定义的表面（飞船平台）直接跳过。详见 scripts/map_features.lua。
    map_features.generate(surface, left_top)

    -- tile 替换：本轮该表面每条规则，把匹配到的源 tile 按 mask 换成目标 tile。圆外已是虚空、不匹配。
    -- mask=all 整片；noise 平滑噪声区；tree/rock/ore 跟随原生树/石/矿分布（在其 tile 及邻近替换）。
    local remap = storage.tile_remap and storage.tile_remap[surface.name]
    if remap then
        local area = {{left_top.x, left_top.y}, {left_top.x + 32, left_top.y + 32}}
        for _, rule in ipairs(remap) do
            local found = prototypes.tile[rule.to] and surface.find_tiles_filtered{name = rule.from, area = area} or {}
            if #found > 0 then
                local mark   -- entity-mask 时：可替换位置集合（"x:y"→true）
                if rule.mask == 'tree' or rule.mask == 'rock' or rule.mask == 'ore' then
                    local etype = rule.mask == 'ore' and 'resource' or (rule.mask == 'rock' and 'simple-entity' or 'tree')
                    local R = rule.mask == 'rock' and 2 or 1
                    mark = {}
                    for _, e in pairs(surface.find_entities_filtered{type = etype, area = area}) do
                        local ex, ey = math.floor(e.position.x), math.floor(e.position.y)
                        for dx = -R, R do
                            for dy = -R, R do mark[(ex + dx) .. ':' .. (ey + dy)] = true end
                        end
                        -- R+1 处随机点几个 → 软化方块硬边、增加不规则感（不再是大矩形）
                        for _ = 1, math.random(2, 5) do
                            local dx, dy = math.random(-(R + 1), R + 1), math.random(-(R + 1), R + 1)
                            mark[(ex + dx) .. ':' .. (ey + dy)] = true
                        end
                    end
                end
                local tiles = {}
                for _, t in pairs(found) do
                    local p, ok = t.position, false
                    if rule.mask == 'all' then
                        ok = true
                    elseif rule.mask == 'noise' then
                        ok = noise.fractal(noise.octaves.smooth, p.x, p.y, rule.seed) > rule.threshold
                    else
                        ok = mark[math.floor(p.x) .. ':' .. math.floor(p.y)] or false
                    end
                    if ok then tiles[#tiles + 1] = {name = rule.to, position = p} end
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

-- 场景加载即构建并校验 tile 池（2.0 控制阶段加载期 prototypes 可用）；无效名记入 log。
-- pcall 兜底（万一加载期不可用），运行时 valid_pools 也会懒构建。
pcall(valid_pools)
