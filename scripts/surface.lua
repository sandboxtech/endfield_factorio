-- 每次跃迁后随机生成各星球：地图设定、资源、自然要素、圆形边界。
local util = require('scripts.util')
local market = require('scripts.market')
local map_features = require('scripts.map_features')
local noise = require('scripts.noise')
local constants = require('scripts.constants')
local events = require('scripts.events')

-- 各"世界变体"出现概率的可调常量（默认 1，游戏内 /c storage.prob_tile_remap=3 之类即可动态调）。
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
-- 整颗星偏湿/干/冷/热，原生生成器据此自然长出对应草/沙/树/水比例，是"修改原生"而非"覆盖"。
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
-- 染地颜色【随机色相生成】（不再只从固定调色板抽）：HSV→RGB，h/s/v ∈ [0,1]，返回 0~1 的 r,g,b。
local function hsv2rgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end
-- 色相 h∈[0,1] → 粗略中文色名（仅 debug 显示用，12 档）。
local HUE_NAMES = {'红', '橙', '黄', '黄绿', '绿', '青', '青蓝', '蓝', '靛', '紫', '品红', '红'}
local function hue_name(h) return HUE_NAMES[(math.floor(h * 12) % 12) + 1] end
-- 大概率落常规区间 [lo,hi]（线性），极小概率(p_wild)放飞到全 [0,1] → 偶尔出现近灰/死黑/荧光等"离谱"色。
local function band_or_wild(lo, hi, p_wild)
    if math.random() < p_wild then return math.random() end
    return lo + math.random() * (hi - lo)
end

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
-- void/space 与 artificial(人造) 不在此白名单，它们是【受 mask 限制】的特殊目标池，由 valid_pools 另建：
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
-- 常规自然目标类：同类高概率、水↔地次之（exotic 与 artificial 不在这里，它们各受 mask 限制，见 pick_target）。
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
script.on_event(defines.events.on_surface_created, events.safe('surface_created', function(event)
    local surface = game.get_surface(event.surface_index)
    if not surface then
        return
    end
    local mgs = surface.map_gen_settings
    mgs.seed = math.random(1, 4294967295)
    surface.map_gen_settings = mgs
end))

-- 表面被 clear（跃迁触发）时执行完整随机生成。
script.on_event(defines.events.on_surface_cleared, events.safe('surface_cleared', function(event)
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
    surface.wind_speed = 0.01 + 0.5 * math.random()^8
    surface.wind_orientation = math.random()
    surface.wind_orientation_change = 0.0001 * (0.5 + math.random())

    -- 外观随机（纯表现）：brightness_visual_weights = 昼夜明暗(brightness)对各通道 LUT 的【影响权重】。
    --   引擎公式 LUT ×= (1-w) + brightness×w：w 越大 → 画面越紧贴昼夜曲线、夜晚越暗。
    --   要【恢复黑夜】故取较大权重：常态 0.8~0.95（夜晚明显变暗、淡色调）；1/6 概率冷暖偏色更强。
    local cr, cg, cb
    if math.random(1, 6) == 1 then
        cr = 0.6 + math.random() * 0.4   -- 0.6~1.0 各自独立 → 通道差异大 = 较强冷暖色调
        cg = 0.6 + math.random() * 0.4
        cb = 0.6 + math.random() * 0.4
    else
        local base = 0.8 + 0.15 * math.random()    -- 0.8~0.95 → 夜晚正常变暗
        cr = base + (math.random() - 0.5) * 0.10   -- 通道间小幅错开 → 淡色调
        cg = base + (math.random() - 0.5) * 0.10
        cb = base + (math.random() - 0.5) * 0.10
    end
    surface.brightness_visual_weights = {r = cr, g = cg, b = cb}
    surface.min_brightness = 0.15 * math.random()        -- 夜晚黑暗程度 0~0.15（越小越黑），纯表现
    surface.show_clouds = math.random(1, 5) > 1          -- 1/5 概率无云，纯表现
    -- 阳光强度影响太阳能发电（玩法）→ 大概率正常、小概率小幅偏离
    surface.solar_power_multiplier = util.mostly_normal()

    -- aquilo 不参与永夜/永昼抽奖（本来就极地气候）。永昼调稀（原 1/3 太多、总是白天）、永夜略多，
    -- 绝大多数世界【正常昼夜循环】：永昼 ≈ 1/10；永夜 ≈ (剩余 9/10) × 1/6 ≈ 15%；其余正常昼夜。
    local polar = surface == game.surfaces.aquilo
    if not polar and math.random(1, 10) == 1 then
        surface.freeze_daytime = true
        surface.daytime = 0      -- 永昼
    elseif not polar and math.random(1, 6) == 1 then
        surface.freeze_daytime = true
        surface.daytime = 0.56   -- 永夜
    end

    -- 刷新星球【形状】：基准半径 r(clamp 到 [min,max]) → 椭圆 rw/rh(正相关、多半近圆) + 噪声粗糙边缘。
    local r = storage.radius_standard * util.random_exp(2)
    r = math.max(storage.radius_min, math.min(storage.radius_max, r))
    r = math.ceil(r)
    -- 椭圆离心 ecc：(rand−rand)×0.35 三角分布，多半≈0(圆)、偶尔明显(椭圆)；rw,rh 都随 r 缩放 → 正相关(偏圆)。
    local ecc = (math.random() - math.random()) * 0.35
    local rw = math.ceil(r * (1 + ecc))
    local rh = math.ceil(r * (1 - ecc))
    -- 边缘粗糙度 rough(归一化，边界半径 = 1 + rough×噪声)：random^6 × 0.6 → 大概率≈0(光滑)、小概率小、极小概率大(海湾/锯齿)。
    local rough = math.random() ^ 6 * 0.6
    -- 老存档兜底：ensure_defaults 没补到也不崩（索引 nil 表会先崩，光靠下游 `or` 救不了 → 必须在写入点保证表存在）。
    storage.width_of, storage.height_of, storage.shape_of =
        storage.width_of or {}, storage.height_of or {}, storage.shape_of or {}
    storage.width_of[surface.name] = rw                                              -- 椭圆 X 半轴（替代原 radius_of）
    storage.height_of[surface.name] = rh                                             -- 椭圆 Y 半轴
    storage.shape_of[surface.name] = {rough = rough, seed = math.random(1, 1000000)} -- 边缘噪声参数

    -- mapgen 区域按【最大外凸】(1+rough) 留足，保证粗糙边缘外凸的半岛也能正常生成。
    mgs.width = math.ceil(rw * (1 + rough)) * 2 + 32
    mgs.height = math.ceil(rh * (1 + rough)) * 2 + 32
    mgs.starting_area = 1 + 2 * util.random_exp(2)

    -- 本轮整局气质（繁茂/岩石/危险/富庶/异物），与 map_features 共用同一套确定性旋钮 → 全局气质一致。
    local knobs = map_features.knobs()

    -- 各"世界变体"出现概率都乘以一个 storage 常量(默认 1，可游戏内 /c storage.prob_xxx=N 动态调)。
    -- gen debug【分组】收集：按类别归组（order 记首次出现序，bycat 存每类多条），
    -- 供 /gen 弹窗分段显示 + 实时一行汇总。每类可含多条（如 tile 替换多条规则）。
    local dbg = {order = {}, bycat = {}}
    local function dbg_add(cat, text)
        local g = dbg.bycat[cat]
        if not g then g = {}; dbg.bycat[cat] = g; dbg.order[#dbg.order + 1] = cat end
        g[#g + 1] = text
    end

    -- 染地世界：小概率出现（诡异世界更可能）。出现时 alpha 走立方曲线 → 大概率温和淡染、
    -- 小概率浓重。先清掉本表面上一轮的染色精灵，再决定本轮是否/如何染。
    clear_ground_tint()
    storage.ground_tint[surface.name] = nil
    local bt = constants.balance.ground_tint
    if math.random() < (bt.base + bt.exotic * knobs.exotic) * prob('ground_tint') then
        -- alpha 很关键：大概率很淡、小概率稍浓（偏小 + 长尾），范围 [0.02,0.32]，多半 ~0.02–0.06。
        local a = 0.02 + (math.random() ^ 5) * 0.60
        -- 颜色：色相【纯随机】；饱和度/明度大概率在好看区间，极小概率(8%)放飞到离谱(近灰/死黑/荧光)。
        local h = math.random()
        local s = band_or_wild(0.55, 1.0, 0.08)
        local v = band_or_wild(0.40, 0.85, 0.08)
        local r, g, b = hsv2rgb(h, s, v)
        storage.ground_tint[surface.name] = {r = r, g = g, b = b, a = a}
        dbg_add('染地', string.format('%s a=%.2f rgb(%d,%d,%d)', hue_name(h), a,
            math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)))
    end

    -- tile 替换世界：较常见（多为自然同类替换），本轮 1~3 条规则。每条 = 源家族 → 目标 tile + 一种 mask：
    --   all  整片换(自然同类多用，不结合噪声)   noise 平滑大团噪声成片
    --   tree/rock/ore 跟随【2.0 原生的树/石/矿分布】替换 → 森林地面/岩屑带/矿脉晕染，非常组织化。
    storage.tile_remap[surface.name] = nil
    local srcs = valid_pools().src[surface.name]
    local br = constants.balance.tile_remap
    if srcs and #srcs > 0 and math.random() < (br.base + br.exotic * knobs.exotic) * prob('tile_remap') then
        local rules = {}
        -- 封顶 20：兜底防 /c storage.tile_remap_rules 填超大数 → 替换规则循环过多。
        local nrules = 1 + math.min(20, math.floor(math.random() ^ 2 * (storage.tile_remap_rules or 6)))   -- 偏向少：多半 1 条
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
                dbg_add('地表', string.format('%s→%s/%s', src.tiles[1], to, mask))
            end
        end
        if #rules > 0 then storage.tile_remap[surface.name] = rules end
    end


    -- 事件世界：每分钟触发一种事件（独立于危险度，奖励/危险皆有）。详见 tick.lua run_world_events。
    --   raid 空降虫 / meteor 矿石陨石雨 / supply 物资空投 / coinfall 金币雨 / drones 无人机来袭 / barrage 重炮落点。
    storage.event_world[surface.name] = nil
    if math.random() < constants.balance.event.base * prob('event') then
        -- 只从【已启用】的事件类型里【按权重】滚（false 排除；权重见 balance.event.weights，缺省 1，drones 更低 → 更罕见）
        local weights = constants.balance.event.weights or {}
        local pool, total = {}, 0
        for _, et in ipairs({'raid', 'meteor', 'supply', 'coinfall', 'drones', 'barrage', 'tech'}) do
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
                    dbg_add('事件', e.et)
                    break
                end
            end
        end
    end

    -- 战利品风格：四类箱子(钢=材料/铁=设备/木=宝箱/永续)各自【独立】的本世界密度，分布 = random()^2：
    -- 大概率低密度(箱子少)、小概率高密度(遍地)，四者互不相关。箱子外观=内容含义已固定，不再随机选箱体。
    -- 据点地砖：本星本轮从【人造地砖】滚两种——enemy_floor 普通据点用、enemy_floor2 永续据点专用（取不同的一种以作区分）。
    storage.enemy_floor2 = storage.enemy_floor2 or {}   -- 老档兜底：ensure_defaults 没补到也不崩
    local art = TILE_CLASS.artificial
    local n = #art
    local i1 = math.random(n)
    local i2 = n > 1 and ((i1 - 1 + math.random(n - 1)) % n + 1) or i1   -- 保证 i2 ≠ i1（n=1 时退化）
    storage.enemy_floor[surface.name] = art[i1]
    storage.enemy_floor2[surface.name] = art[i2]

    -- 五类遭遇各自【本世界密度】= random()^2（多半低、偶尔高），map_features.encounter_chance 统一用它。
    storage.loot_style[surface.name] = {
        material  = math.random() ^ 2,   -- 钢箱(材料)
        equipment = math.random() ^ 2,   -- 铁箱(设备)
        treasure  = math.random() ^ 2,   -- 木箱(宝箱)
        perpetual = math.random() ^ 2,   -- 永续箱遭遇
        empty     = math.random() ^ 2,   -- 空据点遭遇(纯敌人)
    }
    -- debug 摘要：五类遭遇各自的本世界密度[0,1]。
    local ls = storage.loot_style[surface.name]
    dbg_add('遭遇', string.format('material=%.2f equip=%.2f treasure=%.2f perp=%.2f empty=%.2f',
        ls.material, ls.equipment, ls.treasure, ls.perpetual, ls.empty))

    -- （飞船残骸 wreck_density 滚定已移除：残骸改由 map_features.feat_outpost 在据点处非线性生成。）

    -- 障碍互换（统一）：小概率把本星【现地所有带碰撞盒障碍：树/石/遗迹/冰山…】在噪声大团内跨类互换。
    --   大概率整片统一换成同一种(单一主题、协调)；小概率每个各自随机(跨类大杂烩)。应用见 map_features.feat_entity_remap。
    storage.obstacle_remap = storage.obstacle_remap or {}    -- 老存档兜底
    storage.obstacle_remap[surface.name] = nil
    if math.random() < constants.balance.obstacle_remap.base * prob('obstacle_remap') then
        local rule = {
            seed = math.random(1, 4294967295),
            threshold = 0.45 - math.random() ^ 3 * 0.6,   -- 同 tile_remap：多半小斑块、极小概率大片
        }
        -- 大概率(85%)整片统一成一种(单一主题)，小概率(15%)每个各自随机(跨类大杂烩)
        if math.random() < 0.85 then rule.to = map_features.pick_entity_target() end
        storage.obstacle_remap[surface.name] = rule
        dbg_add('障碍', rule.to and ('→' .. rule.to) or 'mixed(每个随机)')
    end

    -- 流体资源互换：小概率激活；激活时【二选一】门控，产流体的资源(原油/锂卤水/氟喷口/硫酸喷泉)变成随机另一种喷口。
    --   模式A 每喷口各自小概率 p (零星散布，每星每世界 p 不同)；模式B noise 大团内整体突变 (成片)。应用见 map_features.feat_fluid_remap。
    storage.fluid_remap = storage.fluid_remap or {}          -- 老存档兜底
    storage.fluid_remap[surface.name] = nil
    if math.random() < constants.balance.fluid_remap.base * prob('fluid_remap') then
        local rule
        if math.random() < 0.5 then
            rule = {p = 0.08 + math.random() ^ 2 * 0.8}   -- 模式A：单喷口突变概率 [0.08,0.88]，偏小
        else
            rule = {seed = math.random(1, 4294967295), threshold = 0.45 - math.random() ^ 3 * 0.6}   -- 模式B：noise 成片(多半小斑块)
        end
        storage.fluid_remap[surface.name] = rule
        dbg_add('喷口', rule.p and string.format('p=%.2f', rule.p) or 'noise')
    end

    -- 本表面生成摘要：【始终】缓存进 storage.gen_debug[星球]（与 storage.debug 无关），供 /gen 弹窗查看。
    -- 缓存为【多行数组】：首行 = 星球+半径+气质旋钮；其后每个变体各占一行（缩进）→ 窗口里逐行换行，不再逗号挤一行。
    local sh = (storage.shape_of or {})[surface.name] or {}   -- 老存档兜底：索引 nil 表会先崩
    local head = string.format('%s %dx%d rough=%.2f  verdancy=%.2f rockiness=%.2f riches=%.2f danger=%.2f exotic=%.2f',
        surface.name, (storage.width_of or {})[surface.name] or 0, (storage.height_of or {})[surface.name] or 0, sh.rough or 0,
        knobs.verdancy, knobs.rockiness, knobs.riches, knobs.danger, knobs.exotic)
    local glines = {head}
    if #dbg.order == 0 then
        glines[#glines + 1] = '  （普通，无变体）'
    else
        for _, cat in ipairs(dbg.order) do
            local items = dbg.bycat[cat]
            if #items == 1 then
                glines[#glines + 1] = '  ' .. cat .. '：' .. items[1]
            else
                glines[#glines + 1] = '  ' .. cat .. '：'   -- 多条（如多条 tile 替换规则）分行列出
                for _, it in ipairs(items) do glines[#glines + 1] = '      └ ' .. it end
            end
        end
    end
    storage.gen_debug[surface.name] = glines

    -- 生成摘要【不再实时刷屏】给管理员；随时用 /gen 弹窗查看（已缓存进 storage.gen_debug）。
    -- 仅在 debug 模式下把无效 tile 名【一次性】提示管理员（拼错预警；INVALID_REPORTED 保证整局只报一次）。
    if storage.debug and not INVALID_REPORTED and #INVALID_TILES > 0 then
        INVALID_REPORTED = true
        debug_print('[gen] 无效 tile 名(已忽略): ' .. table.concat(INVALID_TILES, ', '))
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
    -- 市场不在这里放（出生区块此刻尚未生成）：改由下方 on_chunk_generated 在出生区块自然生成时惰性放置，
    -- 避免强制生成区块。chart 同理改到出生区块生成后（见 on_chunk_generated 母星分支）。
    -- 初始世界(on_init 首轮)的出生区块是场景预生成的、不会自然重生 → 首轮无市场，这是预期行为、不补。
end))

-- 圆形地图：超出半径的格子全部铺成虚空。
script.on_event(defines.events.on_chunk_generated, events.safe('chunk_generated', function(event)
    local surface = event.surface
    local left_top = event.area.left_top

    -- 染地世界：本轮该表面若被选中，在地面层盖一张缩放到整块(32×32)的半透明染色精灵（不改地块，只改观感）。
    -- 【提到最前 + 每块都画】：圆外虚空也染 → 整图色调一致；且下面"整块在外"分支会提前 return 跳过细节，染地须在其之前。
    local gt = storage.ground_tint and storage.ground_tint[surface.name]
    if gt then
        rendering.draw_sprite{
            sprite = 'tile/lab-dark-2', x_scale = 32, y_scale = 32,
            target = {left_top.x + 16, left_top.y + 16}, surface = surface,
            tint = gt, render_layer = 'ground-layer-1',
        }
    end

    -- 椭圆 + 噪声边界：归一化椭圆距离 (px/rw)²+(py/rh)²，边界半径² = (1 + rough×噪声)²，超过即铺虚空。
    -- 老存档兜底：width_of/height_of/shape_of 可能尚未由 ensure_defaults 补齐（旧档继承会 nil）。
    -- 索引 nil 表会先崩→被 events.safe 的 pcall 吞掉→handler 中途夭折、后续 math.random 消耗不一致→desync。
    -- 故此处对【表】本身取兜底（`(t or {})[k]`），而非只对取值结果 `or`。
    local rw = (storage.width_of or {})[surface.name] or storage.radius_standard or 2048
    local rh = (storage.height_of or {})[surface.name] or rw
    local sh = (storage.shape_of or {})[surface.name]
    local rough = (sh and sh.rough) or 0
    local seed = (sh and sh.seed) or 0
    local cx, cy = 0.5, 0.5
    local inner, outer = 1 - rough, 1 + rough

    -- 先按 chunk 整体判定（含 ±1 边缘重叠）：算最近/最远角的归一化椭圆距离。
    local lx, hx = left_top.x - 1 - cx, left_top.x + 32 - cx
    local ly, hy = left_top.y - 1 - cy, left_top.y + 32 - cy
    local nxmax, nymax = math.max(math.abs(lx), math.abs(hx)) / rw, math.max(math.abs(ly), math.abs(hy)) / rh
    local nxmin = ((lx <= 0 and hx >= 0) and 0 or math.min(math.abs(lx), math.abs(hx))) / rw
    local nymin = ((ly <= 0 and hy >= 0) and 0 or math.min(math.abs(ly), math.abs(hy))) / rh
    local far, near = nxmax * nxmax + nymax * nymax, nxmin * nxmin + nymin * nymin

    if far <= inner * inner then
        -- 整块在内：不铺虚空（跳过）
    elseif near >= outer * outer then
        -- 整块在外：整块铺虚空，然后【跳过所有细节】，map_features/市场/tile替换 对纯虚空块都是无用功。染地已在最前画过。
        local tiles = {}
        for x = -1, 32 do
            for y = -1, 32 do
                tiles[#tiles + 1] = {name = 'empty-space', position = {x = left_top.x + x, y = left_top.y + y}}
            end
        end
        surface.set_tiles(tiles)
        return
    else
        -- 跨边界：逐格判定（rough>0 时加噪声扰动边缘 → 平滑海湾/半岛）。用 smooth 倍频（低频大团块）避免边缘密集锯齿。
        local tiles = {}
        for x = -1, 32 do
            for y = -1, 32 do
                local px, py = left_top.x + x, left_top.y + y
                local dx, dy = (px - cx) / rw, (py - cy) / rh
                local edge = 1
                if rough > 0 then edge = 1 + rough * noise.fractal(noise.octaves.smooth, px, py, seed) end
                if dx * dx + dy * dy > edge * edge then
                    tiles[#tiles + 1] = {name = 'empty-space', position = {x = px, y = py}}
                end
            end
        end
        if #tiles > 0 then surface.set_tiles(tiles) end
    end

    -- 各星球地图风味（本地特色矿/石/树/遗迹/冰山 + 跨星球异物 + 树木主题 + 虫群/物资箱）：
    -- 放在铺虚空【之后】，can_place_entity 自动跳过虚空/水/障碍。generate 内部按 PLANET[表面名]
    -- 自行判断，未定义的表面（飞船平台）直接跳过。详见 scripts/map_features.lua。
    map_features.generate(surface, left_top)

    -- 惰性放置出生点市场（母星 + 其余 4 个星球，凡 PLANET_GEN 有配置）：当出生点附近区块生成时尝试放，
    -- 每轮每星只放一次（成功才记 storage.market_run，否则邻块生成时重试）。不再强制生成区块。
    if PLANET_GEN[surface.name] then
        storage.market_run = storage.market_run or {}
        if storage.market_run[surface.name] ~= storage.run then
            local s = game.forces.player.get_spawn_position(surface)
            -- 本区块在出生点周围 3×3 区块范围内才尝试（块中心距出生点 ≤48 格）
            if math.abs((left_top.x + 16) - s.x) <= 48 and math.abs((left_top.y + 16) - s.y) <= 48 then
                if market.place_on_surface(surface.name) then
                    storage.market_run[surface.name] = storage.run
                    -- 母星：市场就绪后顺带 chart 出生点 ±128，落地即看清地形
                    if surface == game.surfaces.nauvis then
                        game.forces.player.chart(surface, {{x = -128, y = -128}, {x = 128, y = 128}})
                    end
                end
            end
        end
    end

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
                        -- ore mask 跳过【流体类资源】(原油/锂卤水/氟喷口…)：它们稀疏点状、非成脉固体矿，不当晕染锚点。
                        -- 判定：开采产物含流体即视为流体资源（比 resource_category 命名可靠）。
                        local fluid_res = false
                        if etype == 'resource' then
                            local mp = e.prototype.mineable_properties
                            for _, pr in ipairs(mp and mp.products or {}) do
                                if pr.type == 'fluid' then fluid_res = true; break end
                            end
                        end
                        if not fluid_res then
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

    -- 注意：不要在这里刷 GUI。区块生成极高频（每轮跃迁成百上千次），
    -- HUD 不依赖区块，刷新由 reset/玩家事件触发即可。（染地已提到本处理器最前。）
end))

-- 场景加载即构建并校验 tile 池（2.0 控制阶段加载期 prototypes 可用）；无效名记入 log。
-- pcall 兜底（万一加载期不可用），运行时 valid_pools 也会懒构建。
pcall(valid_pools)
