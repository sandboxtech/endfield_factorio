-- 每次跃迁后随机生成各星球：地图设定、资源、自然要素、圆形边界。
local util = require('scripts.util')
local market = require('scripts.market')
local map_features = require('scripts.map_features')
local noise = require('scripts.noise')
local constants = require('scripts.constants')
local events = require('scripts.events')

-- 资源原型名 → 是否流体资源（开采产物含流体）。原型跨存档不变，模块级懒缓存（tile 替换 ore mask 用）。
local FLUID_RES = {}

-- 铺虚空的 tiles 条目【模块级复用缓冲】：每个虚空块原本新建 ~2300 个小表（1156 条目×{外表+position}），
-- 大片虚空海域生成时 GC 分配洪峰可观。条目只建一次、逐块改坐标（set_tiles 调用期间引擎即拷贝，复用安全）。
-- VOID_BUF：全虚空块专用，恒 1156 条不truncate；EDGE_BUF：跨边界块用，按需增长 + 显式截断到本块数量。
local VOID_BUF
local EDGE_BUF, EDGE_LEN = {}, 0
local function void_tiles_full(left_top)
    if not VOID_BUF then
        VOID_BUF = {}
        for i = 1, 34 * 34 do VOID_BUF[i] = {name = 'empty-space', position = {0, 0}} end
    end
    local i = 0
    for x = -1, 32 do
        for y = -1, 32 do
            i = i + 1
            local pos = VOID_BUF[i].position
            pos[1] = left_top.x + x
            pos[2] = left_top.y + y
        end
    end
    return VOID_BUF
end

-- 各"世界变体"出现概率的可调常量（默认 1，游戏内 /c storage.prob_tile_remap=3 之类即可动态调）。
local function prob(key) return storage['prob_' .. key] or 1 end

-- debug 打印：只发给在线管理员，不刷屏所有玩家。
local function debug_print(msg)
    for _, p in pairs(game.connected_players) do
        if p.admin then p.print(msg) end
    end
end

-- autoplace 控制名 → 中文短名（/gen 摘要显示用；不在表内回退原名）。
local CTRL_CN = {
    ['iron-ore'] = '铁', ['copper-ore'] = '铜', ['stone'] = '石', ['coal'] = '煤',
    ['uranium-ore'] = '铀', ['crude-oil'] = '油', ['water'] = '水', ['trees'] = '树',
    ['rocks'] = '岩', ['enemy-base'] = '虫巢', ['nauvis_cliff'] = '悬崖',
    ['vulcanus_coal'] = '煤', ['calcite'] = '方解石', ['sulfuric_acid_geyser'] = '硫酸泉',
    ['tungsten_ore'] = '钨', ['vulcanus_volcanism'] = '火山',
    ['scrap'] = '废料', ['fulgora_islands'] = '岛屿', ['fulgora_cliff'] = '悬崖',
    ['gleba_stone'] = '石', ['gleba_water'] = '水', ['gleba_cliff'] = '悬崖',
    ['gleba_plants'] = '植被', ['gleba_enemy_base'] = '虫巢',
    ['lithium_brine'] = '锂卤水', ['fluorine_vent'] = '氟喷口', ['aquilo_crude_oil'] = '油',
}
local function cn(name) return CTRL_CN[name] or name end

-- 资源档位：丰度/面积/频率各抽一个 1..9 的随机整数 N，乘数 = 1.3^(N-中心) × 全局倍率：
--   丰度 = 1.3^(N-7) × richness_multiplier；面积 = 1.3^(N-6) × size_multiplier；频率 = 1.3^(N-5) × frequency_multiplier。
-- 底数用 1.3（不是 2）→ 浮动温和（约 0.27~2.9 倍），避免极端的巨型矿区。
-- 全局倍率：richness=4（矿更富）、size=frequency=1（大小/数量正常）。
-- specialty_mult：地方特产额外降低【丰度】（只乘丰度，不动面积/频率）。
-- 返回 debug 短串"名 丰N面N频N"（档位 1..9，5≈中位），由调用方拼成一行进 /gen。
local function set_resource(name, mgs, specialty_mult)
    local nr, ns, nf = math.random(1, 9), math.random(1, 9), math.random(1, 9)
    local ac = mgs.autoplace_controls[name]
    ac.richness  = 3 ^ (nr - 7) * storage.richness_multiplier * (specialty_mult or 1)
    ac.size      = 1.5 ^ (ns - 6) * storage.size_multiplier
    ac.frequency = 1.3 ^ (nf - 5) * storage.frequency_multiplier
    return string.format('%s 丰%d面%d频%d', cn(name), nr, ns, nf)
end

-- 自然要素（水/悬崖/火山/岛屿）。dbg_add 可选：传入则上报"自然"类一行。
local function random_nature_mgs(mgs, name, value, dbg_add)
    if not value then value = 3 end
    local ac = mgs.autoplace_controls[name]
    if not ac then return end
    ac.frequency = util.random_exp(value)
    ac.size      = util.random_exp(value)
    ac.richness  = util.random_exp(value)
    if dbg_add then dbg_add('自然', string.format('%s 频×%.2f 团×%.2f 量×%.2f', cn(name), ac.frequency, ac.size, ac.richness)) end
end

-- 水域：frequency/size 保底 0.5，避免 random_exp 抽到极小值（可低至 0.125）导致"缺水世界"。
local function random_water_mgs(mgs, name, value, dbg_add)
    if not value then value = 3 end
    local ac = mgs.autoplace_controls[name]
    if not ac then return end
    ac.frequency = math.max(0.5, util.random_exp(value) + 0.25)
    ac.size      = math.max(0.5, util.random_exp(value))
    ac.richness  = util.random_exp(value) + 0.25
    if dbg_add then dbg_add('水域', string.format('%s 频×%.2f 团×%.2f 量×%.2f', cn(name), ac.frequency, ac.size, ac.richness)) end
end

-- 影响难度/节奏的要素（敌人巢穴）：frequency/size 用对数三角分布（值域 [1/spread, spread]，峰在 1）
-- 拉大世界间虫量差异（有的几乎无虫、有的虫海）；richness 仍 mostly_normal 只小幅浮动。
local function balance_mgs(mgs, name, dbg_add)
    local fsp = storage.enemy_freq_spread or 4   -- frequency 浮动幅度：值域 [1/fsp, fsp]
    local ssp = storage.enemy_size_spread or 4   -- size 浮动幅度：值域 [1/ssp, ssp]
    local ac = mgs.autoplace_controls[name]
    ac.richness = util.mostly_normal()
    ac.frequency = util.log_tri(fsp) * (storage.enemy_freq_mul or 1)
    ac.size = util.log_tri(ssp) * (storage.enemy_size_mul or 1)
    if dbg_add then dbg_add('敌巢', string.format('%s 频×%.2f 团×%.2f', cn(name), ac.frequency, ac.size)) end
end

-- 树/石/植被等纯地貌：本轮密度由整局气质 mood∈[0,1] 连续决定；个体规模走"多半小、偶尔大"曲线
-- （立方把规模压向小，避免到处大团）。这是【调原生 autoplace】让原生自己长，不是手动 stamp → 排布天然。
local function nature_by_knob(mgs, name, mood, dbg_add)
    local ac = mgs.autoplace_controls[name]
    if not ac then return end
    ac.frequency = 0.6 + mood * 1.4   -- 下限抬高 → 低繁茂世界也不至于太秃
    ac.size      = 0.3 + mood * 0.6 + (math.random() ^ 3) * 1.3
    ac.richness  = 0.6 + math.random() * 0.8
    if dbg_add then dbg_add('自然', string.format('%s 频×%.2f 团×%.2f 量×%.2f', cn(name), ac.frequency, ac.size, ac.richness)) end
end

-- 用命名噪声输入的【偏置】修改原生气候（2.0 干净杠杆：常量数字串即可，运行时无法编译公式）。
-- 整颗星偏湿/干/冷/热，原生生成器据此自然长出对应草/沙/树/水比例，是"修改原生"而非"覆盖"。
-- 偏置多半接近 0(≈原版)、偶尔明显 → 寻常世界居多、剧变世界罕见。值必须是字符串。
local function bias_climate(mgs, knobs, dbg_add)
    mgs.property_expression_names = mgs.property_expression_names or {}
    local pen = mgs.property_expression_names
    local function tri() return math.random() - math.random() end   -- ∈(-1,1)，偏中间
    -- 干湿整体偏湿（基线 +0.12）：多半略湿润，几乎不会强偏干 → 不再"湿度经常太低/满地荒漠"。
    local mb = 0.12 + (knobs.verdancy - 0.5) * 0.4
    local ab = tri() * 0.35                  -- 副维：沙/红沙调色
    local tb = tri() * 12                    -- 温度：±~12°C 改变生物群系
    local mf = 0.6 + math.random() * 0.9     -- 生物群系斑块大小(连续)
    pen['control:moisture:bias']      = tostring(mb)
    pen['control:aux:bias']           = tostring(ab)
    pen['control:temperature:bias']   = tostring(tb)
    pen['control:moisture:frequency'] = tostring(mf)
    if dbg_add then dbg_add('气候', string.format('湿%+.2f 副维%+.2f 温%+.0f° 斑块×%.2f', mb, ab, tb, mf)) end
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
--   voidspace(empty-space/out-of-map) 仅 noise mask 可选；artificial(混凝土系等) noise(成片人造地表) 或 ore(跟随矿脉) mask 可选。
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
        'artificial-yumako-soil', 'overgrowth-yumako-soil', 'artificial-jellynut-soil', 'overgrowth-jellynut-soil',  -- 草星人造/过度生长土(铺装性质，非自然地表)
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
--   noise(成片) → 一定概率取 exotic(岩浆/油海/氨海/虚空/太空)，否则再以一定概率取 artificial(人造铺装)；
--   ore → 一定概率取 artificial；其余走常规自然(水/地)。tree/rock 只会落到自然。
local function pick_target(src, mask)
    if mask == 'noise' then
        if math.random() < constants.balance.tile_to_exotic then return rand_tile('exotic') end
        if math.random() < constants.balance.tile_to_artificial then return rand_tile('artificial') end
    elseif mask == 'ore' and math.random() < constants.balance.tile_to_artificial then
        return rand_tile('artificial')
    end
    return rand_tile(pick_natural_class(src.class))
end

-- 各星球悬崖【基线】（抄自原版 planet-map-gen.lua，2.0.76 核实；aquilo 无悬崖不在表内）。
-- 每轮以"基线×倍率"【绝对值】写入 cliff_settings，不在上一轮结果上累乘（否则逐轮复利跑飞）。
-- 只动 cliff_elevation_interval(行距，反比于 GUI 频率) 和 richness(连续度)；
-- name/control/cliff_elevation_0/cliff_smoothing 不碰（fulgora 的 elevation_0=80 与海岸线耦合，smoothing=0 是悬崖正确放置的前提）。
local CLIFF_BASE = {
    nauvis   = {interval = 40,  richness = 1},      -- interval/richness 原型未显式给 → 引擎默认 40 / 1
    vulcanus = {interval = 120, richness = 1},      -- 注意：vulcanus 悬崖没有 autoplace control，这是它唯一的悬崖杠杆
    fulgora  = {interval = 40,  richness = 0.95},
    gleba    = {interval = 60,  richness = 0.80},
}

-- 悬崖随机化：大概率正常微浮动，偏向简单（稀疏=行距拉大+连续度打折→缺口多好走），小概率温和加密。
-- 概率 storage 可调：cliff_easy_chance(默认 0.35)/cliff_hard_chance(默认 0.1)，0=该分支不出现。
local function random_cliff_mgs(mgs, sname, dbg_add)
    local base = CLIFF_BASE[sname]
    local cs = base and mgs.cliff_settings
    if not cs then return end
    local r = math.random()
    local imul, rmul, tag
    if r < (storage.cliff_easy_chance or 0.35) then
        imul = 1 + math.random() * 2          -- 行距 ×1~3（崖排更稀）
        rmul = 0.2 + math.random() * 0.8      -- 连续度 ×0.2~1（缺口更多）
        tag = '稀'
    elseif r < (storage.cliff_easy_chance or 0.35) + (storage.cliff_hard_chance or 0.1) then
        imul = 0.6 + math.random() * 0.4      -- 行距 ×0.6~1（崖排略密）
        rmul = 1 + math.random() * 0.15       -- 连续度 ×1~1.15（温和上限，不会离谱难）
        tag = '密'
    else
        imul = 0.85 + math.random() * 0.3     -- 正常 ±15% 微浮动
        rmul = 0.9 + math.random() * 0.2
    end
    cs.cliff_elevation_interval = base.interval * imul
    cs.richness = base.richness * rmul
    if tag then dbg_add('悬崖', string.format('%s 行距×%.2f 连续度×%.2f', tag, imul, rmul)) end
end

-- 巨虫领地随机化（territory_settings.units 非空才生效 → 实际只有 Vulcanus）：
-- 大概率原版三档，其余全是【偏简单】变体（从不更难）。概率 storage 可调（见 ensure_defaults）。
-- 机制（2.0.76 prototype 文档核实）：minimum_territory_size=低于此区块数的领地直接删除（设超大=全图无巨虫，纯数字最安全）；
-- territory_variation_expression 的结果会被 clamp 进 units 数组下标 → 缩短 units 即封顶巨虫档次。
local function random_territory_mgs(mgs, sname, dbg_add)
    local ts = mgs.territory_settings
    if not (ts and ts.units and #ts.units > 0) then return end
    -- 每轮先回到原版基线（units 子集化/巨大 minimum 是破坏性修改，读到的是上一轮的结果）
    ts.units = {'small-demolisher', 'medium-demolisher', 'big-demolisher'}
    -- 领地门槛：每轮在 [10, storage.min_territory_size] 均匀随机（原版 10；不足门槛区块数的领地被引擎删除 → 门槛越高巨虫越稀）。
    ts.minimum_territory_size = math.random(10, math.max(10, storage.min_territory_size or 120))
    -- 领地【删除率】：每轮 p = territory_cull_max × random^territory_cull_pow（默认 0.5×r²，偏 0：大概率几乎不删、
    -- 小概率删近半），存进 storage.territory_cull[星球]，on_territory_created 按 p 对每个新领地掷骰删除（连巨虫一起）。
    storage.territory_cull = storage.territory_cull or {}   -- 老存档兜底
    local cull = (storage.territory_cull_max or 0.5) * math.random() ^ (storage.territory_cull_pow or 2)
    storage.territory_cull[sname] = cull
    dbg_add('巨虫', string.format('领地门槛=%d 删除率=%.0f%%', ts.minimum_territory_size, cull * 100))
    local r = math.random()
    local none_c  = storage.demolisher_none_chance or 0.15
    local small_c = storage.demolisher_small_chance or 0.2
    local mid_c   = storage.demolisher_mid_chance or 0.15
    if r < none_c then
        ts.minimum_territory_size = 4294967295   -- 所有领地都小于它 → 全删 → 无巨虫
        dbg_add('巨虫', '无')
    elseif r < none_c + small_c then
        ts.units = {'small-demolisher'}          -- variation 自动 clamp → 全图只刷小型
        dbg_add('巨虫', '仅小型')
    elseif r < none_c + small_c + mid_c then
        ts.units = {'small-demolisher', 'medium-demolisher'}
        dbg_add('巨虫', '小+中')
    end
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

    -- gen debug【分组】收集（定义在 handler 最前，昼夜/形状/资源各段才都能上报）：按类别归组
    -- （order 记首次出现序，bycat 存每类多条），供 /gen 弹窗分段显示。渲染时按固定类目顺序排（见下方摘要）。
    local dbg = {order = {}, bycat = {}}
    local function dbg_add(cat, text)
        local g = dbg.bycat[cat]
        if not g then g = {}; dbg.bycat[cat] = g; dbg.order[#dbg.order + 1] = cat end
        g[#g + 1] = text
    end

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
    surface.min_brightness = 0.15 * math.random()        -- 夜晚黑暗程度 0~0.15（越小越黑）。影响渲染+虫子视野，不影响太阳能
    surface.show_clouds = math.random(1, 5) > 1          -- 1/5 概率无云，纯表现
    -- 阳光强度影响太阳能发电（玩法）→ 大概率正常、小概率小幅偏离
    surface.solar_power_multiplier = util.mostly_normal()

    -- aquilo 不参与永夜/永昼抽奖（本来就极地气候）。永昼调稀（原 1/3 太多、总是白天）、永夜略多，
    -- 绝大多数世界【正常昼夜循环】：永昼 ≈ 1/10；永夜 ≈ (剩余 9/10) × 1/6 ≈ 15%；其余正常昼夜。
    local polar = surface == game.surfaces.aquilo
    if not polar and math.random(1, 10) == 1 then
        surface.freeze_daytime = true
        surface.daytime = 0      -- 永昼
        dbg_add('昼夜', '永昼')
    elseif not polar and math.random(1, 6) == 1 then
        surface.freeze_daytime = true
        surface.daytime = 0.56   -- 永夜
        surface.min_brightness = math.max(surface.min_brightness, 0.05)   -- 永夜世界兜底下限：避免"永夜×纯黑"叠加整局摸黑
        dbg_add('昼夜', '永夜')
    end
    -- 夜色汇总进 /gen：夜亮=min_brightness(深夜渲染下限)，夜色=LUT 三通道权重，太阳能倍率联动展示。
    -- 注意引擎机制：太阳能只跟昼夜曲线(长短/占比/永昼永夜)和 solar_power_multiplier 走，夜亮/夜色是纯视觉(+虫视野)。
    dbg_add('昼夜', string.format('夜亮%.2f 夜色(%.2f/%.2f/%.2f) 太阳能×%.2f',
        surface.min_brightness, cr, cg, cb, surface.solar_power_multiplier))

    -- 刷新星球【形状】：基准半径 r → 旋转椭圆（长轴 a、短轴 b、旋转角 angle）+ 噪声粗糙边缘 + 偏心中心。
    local r = storage.radius_standard * util.random_exp(2)
    r = math.max(storage.radius_min, math.min(storage.radius_max, r))
    r = math.ceil(r)
    -- 离心率 ecc ∈ [0, spread]，大部分时候很小（random^3 强烈偏 0 → 多半近圆，偶尔才明显椭圆）。
    -- spread = storage.planet_eccentricity（默认 0.2），可 /c 调，0=恒圆。
    local ecc = (storage.planet_eccentricity or 0.2) * math.random() ^ 3
    local a = math.ceil(r * (1 + ecc))   -- 长轴半轴
    local b = math.ceil(r * (1 - ecc))   -- 短轴半轴
    -- 主轴任意旋转 0~2π（椭圆 D₂ 对称下 π~2π 与前半圈重复，但全圆更直白，也免得新增低对称分量时误踩半圆）。
    local angle = math.random() * 2 * math.pi
    -- 边缘粗糙度 rough(归一化，边界半径 = 1 + rough×噪声)：下限 0.1 → 大多数世界【明显】有起伏(不再近完美椭圆)，多在 0.1~0.45。
    local rough = 0.1 + math.random() ^ 2 * 0.35
    -- 碎度 jag ∈ [0,1] 连续(random^2.5 → 大概率小=平滑、小概率接近 1=很碎，之间平滑过渡)：控制叠加的高频海岸细节占比。
    local jag = math.random() ^ 2.5

    -- ── 形状【统一距离场】连续参数：每项强度 = 上限 × random()【线性】→ 各档强度等概率，
    --    变体常见且经常叠加（任意中间值/组合都合法 = 形状空间里的连续插值）。
    --    低于【跳过阈值】的强度直接归中性值，区块端按中性零开销跳过该项计算（见 on_chunk_generated）。──
    -- 超椭圆指数 n = 2 + 三角（线性，正侧×4 → 最高 6 近矩形；负侧×0.7 → 最低 1.3 菱形，无截断堆积）。
    -- |n−2|<0.15 视觉无差 → 吸附回 2（走 sqrt 快路径）。
    local tt = math.random() - math.random()
    local se_n = 2 + (tt > 0 and tt * 4 or tt * 0.7)
    if math.abs(se_n - 2) < 0.15 then se_n = 2 end
    -- 角向谐波【最多 3 条独立叠加】：边界半径 ×(1 + Σ aᵢ·cos(kᵢθ + φᵢ))。单条 = 规则花瓣/蛋形(k=1)/花生(k=2)；
    -- 多条不同 k 叠加 = 不规则瘤状轮廓（傅里叶描述子）。叠加近乎免费：三条共享同一次 atan2，只各多一个 cos。
    local pa1, pk1, pph1 = 0.18 * math.random(), 0, 0
    local pa2, pk2, pph2 = 0.12 * math.random(), 0, 0
    local pa3, pk3, pph3 = 0.08 * math.random(), 0, 0
    if pa1 < 0.02 then pa1 = 0 else pk1 = math.random(1, 7);  pph1 = math.random() * 2 * math.pi end
    if pa2 < 0.02 then pa2 = 0 else pk2 = math.random(2, 9);  pph2 = math.random() * 2 * math.pi end
    if pa3 < 0.02 then pa3 = 0 else pk3 = math.random(3, 11); pph3 = math.random() * 2 * math.pi end
    local pa_total = pa1 + pa2 + pa3   -- ≤0.38：进 in/out_mul 界控与出生膨胀系数
    -- 螺旋 sp（有谐波时 35% 附加，随机旋向=手性）：谐波相位随径向扭转 → 旋臂海岸。
    local sp = 0
    if pa_total > 0 and math.random() < 0.35 then sp = (0.5 + math.random() * 1.5) * (math.random() < 0.5 and 1 or -1) end
    -- 多叶融合【最多 3 瓣独立叠加】：每瓣半径 = 0.5×random（<0.08 跳过），中心距 0.5~0.95；逐瓣 smin 平滑并入。
    local blobs = {}
    for _ = 1, 3 do
        local r2 = 0.5 * math.random()
        if r2 >= 0.08 then
            local bd, bpsi = 0.5 + math.random() * 0.45, math.random() * 2 * math.pi
            blobs[#blobs + 1] = {u = math.cos(bpsi) * bd, v = math.sin(bpsi) * bd, r = r2}
        end
    end
    if #blobs == 0 then blobs = nil end
    -- 域扭曲 warp = 0.14×random（<0.015 跳过）：归一化坐标加低频噪声位移 → 有机轮廓。
    local warp, wseed = 0.14 * math.random(), 0
    if warp < 0.015 then warp = 0 else wseed = math.random(1, 1000000) end

    -- 出生点(地图原点 0,0)不在椭圆正中心：取落在【omax×椭圆】内的偏移 d，椭圆中心 C = 原点 − d。
    -- 半径 t = omax×random^B 非线性(B=storage.spawn_offset_pow，默认 2)：B 越大越贴中心；B=1 退回线性；B<1 偏向外缘。
    -- omax=storage.spawn_offset_max(默认 0.5)，并按形状的【最坏膨胀系数】收紧（n<2 对角收缩、花瓣谷底、
    -- 扭曲位移都会把椭圆度量下的同一点推得更"靠外"），保证 spawn 处最终 d ≤ edge_noise_start−0.05 必为陆地。
    local infl = (se_n < 2 and 2 ^ (1 / se_n - 0.5) or 1) / (1 - pa_total)
    local omax = math.max(0, math.min(storage.spawn_offset_max or 0.5,
        ((storage.edge_noise_start or 0.8) - 0.05) / infl - warp))
    local t = omax * math.random() ^ (storage.spawn_offset_pow or 2)
    local phi = math.random() * 2 * math.pi
    local su, sv = t * a * math.cos(phi), t * b * math.sin(phi)   -- 主轴系偏移
    local ca, sa = math.cos(angle), math.sin(angle)
    local cx = -(su * ca - sv * sa)      -- 椭圆中心地图坐标（spawn 在原点 → C = −d）
    local cy = -(su * sa + sv * ca)
    -- （环礁分量已删除：它是唯一在中心挖洞的形状，与"中心实心"的要求根本冲突。）
    -- 老存档兜底：ensure_defaults 没补到也不崩（索引 nil 表会先崩，必须在写入点保证表存在）。
    storage.width_of, storage.height_of, storage.shape_of =
        storage.width_of or {}, storage.height_of or {}, storage.shape_of or {}
    storage.width_of[surface.name] = a                                               -- 长轴半轴
    storage.height_of[surface.name] = b                                              -- 短轴半轴
    storage.shape_of[surface.name] = {rough = rough, seed = math.random(1, 1000000), jag = jag, -- 边缘噪声/碎度
                                      angle = angle, cx = cx, cy = cy,               -- 旋转角 + 偏心中心
                                      n = se_n, sp = sp,                               -- 超椭圆 + 螺旋
                                      pa1 = pa1, pk1 = pk1, pph1 = pph1,               -- 角向谐波 ×3
                                      pa2 = pa2, pk2 = pk2, pph2 = pph2,
                                      pa3 = pa3, pk3 = pk3, pph3 = pph3,
                                      blobs = blobs, warp = warp, wseed = wseed}       -- 多叶/域扭曲
    -- /gen：形状变体一行（全中性=纯椭圆则不报）。
    local sparts = {}
    if se_n ~= 2 then sparts[#sparts + 1] = string.format('超椭圆n=%.1f', se_n) end
    if pa_total > 0 then sparts[#sparts + 1] = string.format('%s谐波Σ%.2f', sp ~= 0 and '螺旋' or '', pa_total) end
    if blobs then sparts[#sparts + 1] = '多叶×' .. #blobs end
    if warp > 0 then sparts[#sparts + 1] = string.format('扭曲%.2f', warp) end
    if #sparts > 0 then dbg_add('形状', table.concat(sparts, ' ')) end
    -- mapgen 区域要罩住【偏心 + 旋转 + 粗糙 + 形状外扩】后的整体：
    -- 外扩系数 = max(超椭圆对角×(1+花瓣), 双叶中心距+半径) + 扭曲位移。
    local se_max = se_n > 2 and 2 ^ (0.5 - 1 / se_n) or 1
    local out_norm = se_max * (1 + pa_total)
    for _, bb in ipairs(blobs or {}) do
        out_norm = math.max(out_norm, math.sqrt(bb.u * bb.u + bb.v * bb.v) + bb.r)
    end
    local reach = math.ceil(a * (out_norm + warp + omax + rough))
    mgs.width = reach * 2 + 64
    mgs.height = reach * 2 + 64
    mgs.starting_area = 1 + 2 * util.random_exp(2)

    -- 本轮整局气质（繁茂/岩石/危险/富庶/异物），与 map_features 共用同一套确定性旋钮 → 全局气质一致。
    local knobs = map_features.knobs()
    dbg_add('气质', string.format('繁茂%.2f 岩石%.2f 富庶%.2f 危险%.2f 异物%.2f',
        knobs.verdancy, knobs.rockiness, knobs.riches, knobs.danger, knobs.exotic))

    -- 各"世界变体"出现概率都乘以一个 storage 常量(默认 1，可游戏内 /c storage.prob_xxx=N 动态调)。

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
        machine   = math.random() ^ 2,   -- 传说生产建筑据点
    }
    -- 遭遇【空间聚簇】噪声：amp = random²×0.9（多半近均匀、偶尔强聚簇成"敌占区/安全区"）。
    -- map_features.place_encounter 按区块中心采样低频噪声调制全部 6 类出现率。
    storage.loot_noise = storage.loot_noise or {}   -- 老存档兜底
    storage.loot_noise[surface.name] = {seed = math.random(1, 1000000), amp = math.random() ^ 2 * 0.9}
    -- debug 摘要：五类遭遇各自的本世界密度（占各自上限的百分比）。
    local ls = storage.loot_style[surface.name]
    dbg_add('遭遇', string.format('材料%d%% 装备%d%% 宝箱%d%% 永续%d%% 空据%d%% 机器%d%% 聚簇±%d%%',
        ls.material * 100 + 0.5, ls.equipment * 100 + 0.5, ls.treasure * 100 + 0.5,
        ls.perpetual * 100 + 0.5, ls.empty * 100 + 0.5, ls.machine * 100 + 0.5,
        storage.loot_noise[surface.name].amp * 100 + 0.5))

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

    -- 昼夜随机化（每次世界生成都执行；基线首次读到时缓存原版值，每轮【绝对值】写入，不逐轮复利）：
    -- ① 昼夜长短：ticks_per_day = 基线 × A^(t³)，t∈(-1,1) 均匀，A=storage.day_len_spread(默认 8)。
    --    t³ 强烈偏 0 → 大概率 ≈1×(一半世界在 ±30% 内)，小概率逼近 A 或 1/A(约 7% 超 5×/快于 1/5)。
    storage.base_ticks_per_day = storage.base_ticks_per_day or {}   -- 老存档兜底
    local btpd = storage.base_ticks_per_day[surface.name] or surface.ticks_per_day
    storage.base_ticks_per_day[surface.name] = btpd
    local dt = math.random() * 2 - 1
    local dmul = (storage.day_len_spread or 8) ^ (dt * dt * dt)
    surface.ticks_per_day = math.max(60, math.floor(btpd * dmul + 0.5))
    if dmul > 1.5 or dmul < 1 / 1.5 then dbg_add('昼夜', string.format('一天长度 ×%.2f', dmul)) end
    -- ② 昼夜占比：小概率(storage.day_shape_chance，默认 0.25)重塑 daytime_parameters——
    --    白天半宽 hd∈[0.1,0.4](原版 0.25) → 白天占比 20%~80%；暮光占夜侧 40%~90%(原版 80%)，对称构造，
    --    天然满足引擎的严格顺序校验 dusk<evening<morning<dawn。必须整表一次写入(改返回表的单字段无效)。
    --    未命中则回写基线——上一轮可能改过，必须每轮归位。
    storage.base_daytime_params = storage.base_daytime_params or {}   -- 老存档兜底
    local bdp = storage.base_daytime_params[surface.name]
    if not bdp then
        local p = surface.daytime_parameters
        bdp = {dusk = p.dusk, evening = p.evening, morning = p.morning, dawn = p.dawn}
        storage.base_daytime_params[surface.name] = bdp
    end
    if math.random() < (storage.day_shape_chance or 0.25) then
        local hd = 0.1 + math.random() * 0.3
        local ev = hd + (0.5 - hd) * (0.4 + math.random() * 0.5)
        surface.daytime_parameters = {dusk = hd, evening = ev, morning = 1 - ev, dawn = 1 - hd}
        dbg_add('昼夜', string.format('白天占比 %.0f%%', hd * 200))
    else
        surface.daytime_parameters = {dusk = bdp.dusk, evening = bdp.evening, morning = bdp.morning, dawn = bdp.dawn}
    end

    -- 悬崖/巨虫领地随机化：两者都自带门控（CLIFF_BASE 有该星球 / territory units 非空 → 实际只有 Vulcanus），
    -- 平台已在前面 return。
    random_cliff_mgs(mgs, surface.name, dbg_add)
    random_territory_mgs(mgs, surface.name, dbg_add)

    -- 生成摘要【不再实时刷屏】给管理员；随时用 /gen 弹窗查看（缓存进 storage.gen_debug，见下方 cfg 块之后）。
    -- 仅在 debug 模式下把无效 tile 名【一次性】提示管理员（拼错预警；INVALID_REPORTED 保证整局只报一次）。
    if storage.debug and not INVALID_REPORTED and #INVALID_TILES > 0 then
        INVALID_REPORTED = true
        debug_print('[gen] 无效 tile 名(已忽略): ' .. table.concat(INVALID_TILES, ', '))
    end

    -- 按 PLANET_GEN 配置生成各星球资源/自然/气候（飞船平台等不在表内 → 跳过）。
    local cfg = PLANET_GEN[surface.name]
    if cfg then
        if cfg.peaceful then
            surface.peaceful_mode = math.random(1, constants.balance.peaceful_one_in) == 1
            if surface.peaceful_mode then dbg_add('敌巢', '宁和模式（虫不主动攻击）') end
        end
        local res_dbg = {}   -- 各资源档位短串拼一行（多种资源 │ 分隔，比逐条分行紧凑）
        for _, res in ipairs(cfg.res or {}) do res_dbg[#res_dbg + 1] = set_resource(res, mgs) end
        for _, sp in ipairs(cfg.specialty or {}) do
            res_dbg[#res_dbg + 1] = set_resource(sp[1], mgs, storage.local_specialty_multiplier * sp[2])
        end
        if #res_dbg > 0 then dbg_add('资源', table.concat(res_dbg, ' │ ')) end
        for _, w in ipairs(cfg.water or {}) do random_water_mgs(mgs, w, nil, dbg_add) end
        for _, n in ipairs(cfg.nature or {}) do random_nature_mgs(mgs, n, nil, dbg_add) end
        for _, kn in ipairs(cfg.knob or {}) do nature_by_knob(mgs, kn[1], knobs[kn[2]], dbg_add) end
        for _, b in ipairs(cfg.balance or {}) do balance_mgs(mgs, b, dbg_add) end
        if cfg.climate then bias_climate(mgs, knobs, dbg_add) end
    end

    -- 本表面生成摘要：【始终】缓存进 storage.gen_debug[星球]（与 storage.debug 无关），供 /gen 弹窗查看。
    -- 放在 handler 末尾 = 所有随机段（昼夜/形状/变体/资源/气候/悬崖/巨虫）都已上报完。
    -- 多行数组：首行 = 星球 + 半轴尺寸 + 形状参数；其后每类一行（多条的分行缩进），类目按固定顺序排。
    local head = string.format('%s %d×%d  粗糙%.2f 离心%.2f 碎度%.2f 起始区×%.1f',
        surface.name, a, b, rough, ecc, jag, mgs.starting_area)
    local glines = {head}
    local CAT_ORDER = {'气质', '昼夜', '气候', '资源', '水域', '自然', '敌巢', '悬崖', '巨虫',
                       '遭遇', '染地', '地表', '障碍', '喷口'}
    local cats, seen = {}, {}
    for _, c in ipairs(CAT_ORDER) do if dbg.bycat[c] then cats[#cats + 1] = c; seen[c] = true end end
    for _, c in ipairs(dbg.order) do if not seen[c] then cats[#cats + 1] = c end end   -- 新类目兜底：按首次出现序排在最后
    if #cats == 0 then glines[#glines + 1] = '  （普通，无变体）' end
    for _, cat in ipairs(cats) do
        local items = dbg.bycat[cat]
        if #items == 1 then
            glines[#glines + 1] = '  ' .. cat .. '：' .. items[1]
        else
            glines[#glines + 1] = '  ' .. cat .. '：'   -- 多条（如多条 tile 替换规则）分行列出
            for _, it in ipairs(items) do glines[#glines + 1] = '      └ ' .. it end
        end
    end
    storage.gen_debug[surface.name] = glines

    surface.map_gen_settings = mgs

    -- 市场不在这里放（出生区块此刻尚未生成）：改由下方 on_chunk_generated 在出生区块自然生成时惰性放置，
    -- 避免强制生成区块。chart 同理改到出生区块生成后（见 on_chunk_generated 母星分支）。
    -- 初始世界(on_init 首轮)的出生区块是场景预生成的、不会自然重生 → 首轮无市场，这是预期行为、不补。
end))

-- 巨虫领地生成时按本轮删除率掷骰删除（destroy 连守卫巨虫一起删）：
-- 删除率 storage.territory_cull[星球] 由 random_territory_mgs 每轮滚定（默认 0.5×random²，偏 0）；
-- 表/值缺失（老存档、首轮未滚定、非 Vulcanus）→ 不删，行为同原版。
script.on_event(defines.events.on_territory_created, events.safe('territory_created', function(event)
    local t = event.territory
    if not (t and t.valid) then return end
    local p = storage.territory_cull and storage.territory_cull[t.surface.name]
    if p and math.random() < p then t.destroy() end
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

    -- 统一距离场边界：椭圆基形 + 域扭曲/超椭圆/花瓣/双叶 连续叠加得归一化距离 d（中性参数=纯椭圆），
    -- 边界半径 = 1 + rough×噪声×距离权重，d 超过即虚空（中心恒实心：无任何分量会在内部挖洞）。
    -- 老存档兜底：width_of/height_of/shape_of 可能尚未由 ensure_defaults 补齐（旧档继承会 nil）。
    -- 索引 nil 表会先崩→被 events.safe 的 pcall 吞掉→handler 中途夭折、后续 math.random 消耗不一致→desync。
    -- 故此处对【表】本身取兜底（`(t or {})[k]`），而非只对取值结果 `or`。
    local a = (storage.width_of or {})[surface.name] or storage.radius_standard or 2048   -- 长轴半轴
    local b = (storage.height_of or {})[surface.name] or a                                -- 短轴半轴
    local sh = (storage.shape_of or {})[surface.name]
    local rough = (sh and sh.rough) or 0
    local seed = (sh and sh.seed) or 0
    local angle = (sh and sh.angle) or 0
    local cx = (sh and sh.cx) or 0
    local cy = (sh and sh.cy) or 0
    local jag = (sh and sh.jag) or 0   -- 碎度 [0,1]：叠加的高频海岸细节占比（连续插值）
    -- 统一距离场参数（缺省=中性值=纯椭圆，老存档自动退化为原行为）。
    local se_n = (sh and sh.n) or 2                              -- 超椭圆指数
    local pa1, pk1, pph1 = (sh and sh.pa1) or 0, (sh and sh.pk1) or 0, (sh and sh.pph1) or 0   -- 角向谐波 ×3
    local pa2, pk2, pph2 = (sh and sh.pa2) or 0, (sh and sh.pk2) or 0, (sh and sh.pph2) or 0
    local pa3, pk3, pph3 = (sh and sh.pa3) or 0, (sh and sh.pk3) or 0, (sh and sh.pph3) or 0
    local pa_total = pa1 + pa2 + pa3
    local sp = (sh and sh.sp) or 0                               -- 螺旋相位（谐波的径向扭转）
    local blobs = sh and sh.blobs                                -- 多叶 {{u,v,r},...}（主轴系归一化）
    local warp, wseed = (sh and sh.warp) or 0, (sh and sh.wseed) or 0   -- 域扭曲
    local ca, sa = math.cos(angle), math.sin(angle)   -- 把世界点旋转 −angle 回主轴系：u=dx*ca+dy*sa, v=−dx*sa+dy*ca
    local amax, bmin = math.max(a, b), math.min(a, b)  -- 外接圆 / 内切圆半径
    -- 出生安全盘【硬保证】：以出生点(地图原点)为圆心、半短轴×spawn_safe_frac(默认 0.3) 为半径的圆盘内
    -- 【绝不铺虚空】——不依赖扭曲/噪声等各自的解析约束，逐格最后一道闸直接豁免。
    -- （默认参数下盘缘归一化距离 ≤ omax+0.3 ≤ 0.8 = edge_noise_start，正常根本碰不到边界，此闸只防极端配置/组合。）
    local safe_sq = ((storage.spawn_safe_frac or 0.3) * bmin) ^ 2
    -- 圆近似快判的保守系数：内界乘"形状最小收缩"（n<2 对角收缩、花瓣谷底、扭曲位移），
    -- 外界乘"形状最大外扩"（n>2 对角外凸、花瓣峰顶、双叶外缘、扭曲位移）。
    local se_min = se_n < 2 and 2 ^ (0.5 - 1 / se_n) or 1
    local se_max = se_n > 2 and 2 ^ (0.5 - 1 / se_n) or 1
    local in_mul  = math.max(0, se_min * (1 - pa_total) - warp)
    local out_mul = se_max * (1 + pa_total)
    if blobs then
        for i = 1, #blobs do
            local bb = blobs[i]
            out_mul = math.max(out_mul, math.sqrt(bb.u * bb.u + bb.v * bb.v) + bb.r)
        end
    end
    out_mul = out_mul + warp
    local inner, outer = (1 - rough) * in_mul, (1 + rough) * out_mul

    -- chunk 级【圆近似】快速判定（旋转椭圆的内切/外接圆，保守）：到偏心中心 (cx,cy) 的欧氏距离。
    local lx, hx = left_top.x - 1, left_top.x + 32
    local ly, hy = left_top.y - 1, left_top.y + 32
    local fx = math.max(math.abs(lx - cx), math.abs(hx - cx))
    local fy = math.max(math.abs(ly - cy), math.abs(hy - cy))
    local nx = (lx <= cx and hx >= cx) and 0 or math.min(math.abs(lx - cx), math.abs(hx - cx))
    local ny = (ly <= cy and hy >= cy) and 0 or math.min(math.abs(ly - cy), math.abs(hy - cy))
    local far, near = fx * fx + fy * fy, nx * nx + ny * ny

    if far <= (bmin * inner) ^ 2 then
        -- 整块在内切圆内 → 必为陆地，跳过
    elseif near >= (amax * outer) ^ 2 then
        -- 整块在外接圆外 → 必在椭圆外，整块铺虚空 + 跳过所有细节（map_features/市场/tile替换 对纯虚空块无用；染地已在最前画过）。
        surface.set_tiles(void_tiles_full(left_top))   -- 复用缓冲：零新表分配
        return
    else
        -- 跨边界：逐格判定，把点旋转回主轴系再算归一化椭圆距离 + 噪声扰动边缘（smooth 倍频，平滑海湾/半岛）。
        -- 噪声权重随距离渐进：归一化距离 < edge_noise_start(默认 0.8) 时权重 0(必为陆地)，到 1 处线性升满，>1 恒满。
        -- 效果：内侧不再被噪声打出虚空洞（洞只能出现在边界带内），外侧起伏/半岛保留原有幅度。
        local nstart = storage.edge_noise_start or 0.8
        local nspan = math.max(0.01, 1 - nstart)
        local outer_d = 1 + rough   -- 噪声所能外扩的极限边界：d 超过它噪声救不回 → 免噪声直判虚空
        local cnt = 0   -- 本块虚空格数（EDGE_BUF 复用缓冲的有效长度）
        -- 域扭曲【降采样】：噪声波长 ~167 格 >> 采样步长 4 格 → 每区块只采 10×10 网格点（200 次 fractal，
        -- 对比逐格 2312 次），逐格双线性插值，视觉无差。两通道(u/v 位移)各一张网格。
        local wgu, wgv
        if warp > 0 then
            wgu, wgv = {}, {}
            for gy = 0, 9 do
                local rowu, rowv = {}, {}
                local wy = left_top.y - 1 + gy * 4
                for gx = 0, 9 do
                    local wx = left_top.x - 1 + gx * 4
                    rowu[gx] = noise.fractal(noise.octaves.smooth, wx, wy, wseed)
                    rowv[gx] = noise.fractal(noise.octaves.smooth, wx, wy, wseed + 333)
                end
                wgu[gy], wgv[gy] = rowu, rowv
            end
        end
        for x = -1, 32 do
            for y = -1, 32 do
                local px, py = left_top.x + x, left_top.y + y
                local ddx, ddy = px - cx, py - cy
                local u, v = ddx * ca + ddy * sa, -ddx * sa + ddy * ca   -- 旋转 −angle 回主轴系
                local nu, nv = u / a, v / b
                -- ── 统一距离场：椭圆为中性基形，依次叠加 域扭曲/超椭圆/花瓣/双叶（参数中性时零开销跳过）──
                if warp > 0 then   -- 域扭曲：从降采样网格双线性插值取位移（见上，不再逐格调 fractal）
                    local fx, fy = (x + 1) * 0.25, (y + 1) * 0.25
                    local ix, iy = math.floor(fx), math.floor(fy)
                    local tx, ty = fx - ix, fy - iy
                    local r0, r1 = wgu[iy], wgu[iy + 1]
                    nu = nu + warp * ((r0[ix] * (1 - tx) + r0[ix + 1] * tx) * (1 - ty) + (r1[ix] * (1 - tx) + r1[ix + 1] * tx) * ty)
                    r0, r1 = wgv[iy], wgv[iy + 1]
                    nv = nv + warp * ((r0[ix] * (1 - tx) + r0[ix + 1] * tx) * (1 - ty) + (r1[ix] * (1 - tx) + r1[ix + 1] * tx) * ty)
                end
                local d
                if se_n == 2 then d = math.sqrt(nu * nu + nv * nv)   -- 纯椭圆走 sqrt 快路径
                else d = (math.abs(nu) ^ se_n + math.abs(nv) ^ se_n) ^ (1 / se_n) end   -- 超椭圆
                if pa_total > 0 then   -- 角向谐波叠加（共享一次 atan2；sp≠0 时相位随径向扭转=螺旋）
                    local ang = math.atan2(nv, nu) + sp * d * 6.2832
                    local mo = 1
                    if pa1 > 0 then mo = mo + pa1 * math.cos(pk1 * ang + pph1) end
                    if pa2 > 0 then mo = mo + pa2 * math.cos(pk2 * ang + pph2) end
                    if pa3 > 0 then mo = mo + pa3 * math.cos(pk3 * ang + pph3) end
                    d = d / mo
                end
                if blobs then   -- 多叶：逐瓣圆形距离场，多项式 smin(k=0.25) 平滑并集
                    for i = 1, #blobs do
                        local bb = blobs[i]
                        local du, dv = nu - bb.u, nv - bb.v
                        local d2 = math.sqrt(du * du + dv * dv) / bb.r
                        local hsm = math.max(0, 1 - math.abs(d - d2) / 0.25)
                        d = math.min(d, d2) - 0.0625 * hsm * hsm
                    end
                end
                local void = false
                if d > outer_d then
                    void = true   -- 超过噪声外扩极限：免噪声直判（肥保守壳层的主要省耗点）
                elseif rough > 0.01 and d > nstart then   -- d ≤ nstart 必为陆地，噪声都不用算
                    -- 海岸边缘用【低频主导】的 coast（大尺度平滑起伏），jag 细节走 coast_detail（比 fine 低频，碎而不锯齿）。
                    -- jag 连续插值：jag=0 纯平滑 ↔ jag=1 最碎；除以(1+jag)归一化保振幅。
                    local mix = noise.fractal(noise.octaves.coast, px, py, seed)
                    if jag > 0.02 then
                        mix = (mix + jag * noise.fractal(noise.octaves.coast_detail, px, py, seed + 777)) / (1 + jag)
                    end
                    void = d > 1 + rough * mix * math.min(1, (d - nstart) / nspan)
                else
                    void = d > 1
                end
                if void and px * px + py * py > safe_sq then   -- 出生安全盘内豁免（硬保证不被虚空覆盖）
                    cnt = cnt + 1
                    local e = EDGE_BUF[cnt]
                    if not e then e = {name = 'empty-space', position = {0, 0}}; EDGE_BUF[cnt] = e end
                    e.position[1], e.position[2] = px, py
                end
            end
        end
        if cnt > 0 then
            for i = cnt + 1, EDGE_LEN do EDGE_BUF[i] = nil end   -- 截断到本块数量（上块更长时清掉残留）
            EDGE_LEN = cnt
            surface.set_tiles(EDGE_BUF)
        end
    end

    -- tile 替换【先于实体放置】：先把本块地砖换成最终形态，下面 map_features/市场的 find_non_colliding 才会
    -- 避开水/熔岩/虚空，实体落在最终地砖上、不会被随后的 set_tiles 删（根治"水面上有标记/守卫残留"）。
    -- tile 替换：本轮该表面每条规则，把匹配到的源 tile 按 mask 换成目标 tile。圆外已是虚空、不匹配。
    -- mask=all 整片；noise 平滑噪声区；tree/rock/ore 跟随原生树/石/矿分布（在其 tile 及邻近替换）。
    local remap = storage.tile_remap and storage.tile_remap[surface.name]
    if remap then
        local nsamp_cache = {}   -- noise mask 降采样器（按 rule.seed 缓存；smooth 波长 167 >> 步长 4，视觉无差）
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
                            fluid_res = FLUID_RES[e.name]
                            if fluid_res == nil then   -- 原型不变 → 模块级缓存（纯由 prototypes 派生，无 desync 风险）
                                fluid_res = false
                                local mp = e.prototype.mineable_properties
                                for _, pr in ipairs(mp and mp.products or {}) do
                                    if pr.type == 'fluid' then fluid_res = true; break end
                                end
                                FLUID_RES[e.name] = fluid_res
                            end
                        end
                        if not fluid_res then
                            local ex, ey = math.floor(e.position.x), math.floor(e.position.y)
                            -- 数值 key：ex*100000+ey（|坐标|≤地图半径 4096 < 5万 → 唯一，省字符串拼接/分配）
                            for dx = -R, R do
                                for dy = -R, R do mark[(ex + dx) * 100000 + (ey + dy)] = true end
                            end
                            -- R+1 处随机点几个 → 软化方块硬边、增加不规则感（不再是大矩形）
                            for _ = 1, math.random(2, 5) do
                                local dx, dy = math.random(-(R + 1), R + 1), math.random(-(R + 1), R + 1)
                                mark[(ex + dx) * 100000 + (ey + dy)] = true
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
                        -- 匹配地砖多（>120）才建降采样网格（固定 100 次 fractal 换 N 次取值）；少量直接逐点。
                        local nsamp = nsamp_cache[rule.seed]
                        if nsamp == nil then
                            nsamp = #found > 120 and noise.chunk_sampler(noise.octaves.smooth, left_top, rule.seed) or false
                            nsamp_cache[rule.seed] = nsamp
                        end
                        ok = (nsamp and nsamp(p.x, p.y) or noise.fractal(noise.octaves.smooth, p.x, p.y, rule.seed)) > rule.threshold
                    else
                        ok = mark[math.floor(p.x) * 100000 + math.floor(p.y)] or false
                    end
                    if ok then tiles[#tiles + 1] = {name = rule.to, position = p} end
                end
                -- set_tiles 会把被盖住的原地形自动存为 hidden_tile：玩家拆掉人造铺装后露出该格原本的地形。
                if #tiles > 0 then surface.set_tiles(tiles) end
            end
        end
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

    -- 注意：不要在这里刷 GUI。区块生成极高频（每轮跃迁成百上千次），
    -- HUD 不依赖区块，刷新由 reset/玩家事件触发即可。（染地已提到本处理器最前。）
end))

-- 区块被勘探(charted)时：补打该块待办的宝箱地图标签（add_chart_tag 要求区块已 charted，故 on_chunk_generated
-- 时打不上的标签存了待办，到这里 player 力量看到该块时补上）。只关心 player 力量的勘探。
script.on_event(defines.events.on_chunk_charted, events.safe('chunk_charted', function(event)
    if event.force and event.force.name ~= 'player' then return end
    local surface = game.surfaces[event.surface_index]
    if surface then map_features.flush_chunk_tags(surface, event.position.x, event.position.y) end
end))

-- 场景加载即构建并校验 tile 池（2.0 控制阶段加载期 prototypes 可用）；无效名记入 log。
-- pcall 兜底（万一加载期不可用），运行时 valid_pools 也会懒构建。
pcall(valid_pools)
