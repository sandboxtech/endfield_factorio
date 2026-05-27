-- 地图风味：每次跃迁给各星球随机点缀本地特色（矿/石/树/遗迹/冰山…）+ 树木主题 + 偶现异星之物。
-- 架构（数据驱动、多星球）：
--   · PLANET[表面名] 列出该星球的特色特征；EXOTIC 是跨星球"异物"（小概率长到别处）。
--   · 每个特征从本轮种子(storage.run+off)派生【频率分档】strength：~60% 不出现 / ~30% 小 / ~10% 大。
--   · 用 simplex 噪声(scripts/noise)成片放置；每轮形状/方向不同；多种特征重叠 → 天然混合矿。
--   · 玩家可拆的实体一律 force='player'；敌对(虫)用 force='enemy'。
--   · 树木主题：按本轮整局风格批量调树的颜色/灰度（灰树世界 / 单一 / 多样 / 原生）。
-- 由 surface.lua 的 on_chunk_generated 对各星球圆内区块调用 M.generate。调参见各表 off/threshold/density/amount。
local noise = require('scripts.noise')

local M = {}

local function wseed(off) return (storage.run or 0) * 1009 + off end

-- 本轮该特征强度：~60% 为 0(不出现)；出现时走【立方偏置】——绝大多数小规模、极小概率大规模。
-- （r³ 把均匀随机压向 0：r=0.5→0.125、0.8→0.51、0.95→0.86，所以大规模很罕见。）
local function strength(off)
    if noise.hash01(wseed(off) * 7.3) < 0.60 then return 0 end
    local r = noise.hash01(wseed(off) * 3.1)
    return 0.1 + r * r * r * 0.9
end

-- 通用放置：def = {name, off, amount={lo,hi}(资源才填), density(0~1, 默认1=成片实心), threshold(默认0.78),
--   force(默认player), rare(true=异星物，额外加一道小概率门)}
-- A/S/Z = 本轮【全局共享】的朝向/拉伸/缩放（所有特征一致，不互相打架）；def.off 决定各自的噪声场(位置不同)。
local function place_feature(surface, lt, def, A, S, Z)
    if def.rare and noise.hash01(wseed(def.off) * 9.9) > 0.15 then return end  -- 异星物：再压到 ~15% 轮次
    local s = strength(def.off)
    if s == 0 then return end
    local fseed = wseed(def.off)
    -- 阈值高→覆盖小；s 多半很小(立方曲线)→大多数是小斑块，极少 s 大才铺成片
    local threshold = (def.threshold or 0.72) - s * 0.32
    local density = def.density or 1
    for x = 0, 31 do
        for y = 0, 31 do
            local px, py = lt.x + x, lt.y + y
            if noise.fractal_warped(noise.octaves.scrap, px, py, fseed, A, S, Z) > threshold
               and (density >= 1 or math.random() < density) then
                local pos = {x = px + 0.5, y = py + 0.5}
                if surface.can_place_entity{name = def.name, position = pos} then
                    if def.amount then   -- 资源：储量按本轮强度 × 第二层噪声起伏
                        local rn = (noise.fractal(noise.octaves.scrap, px, py, fseed + 50000) + 1) * 0.5
                        surface.create_entity{name = def.name, force = def.force or 'player', position = pos,
                            amount = math.max(50, math.floor((def.amount[1] + (def.amount[2] - def.amount[1]) * rn) * (0.5 + s)))}
                    else                 -- 普通实体（石/树/遗迹/冰山…）
                        surface.create_entity{name = def.name, force = def.force or 'player', position = pos}
                    end
                end
            end
        end
    end
end

-- 各星球本地特色（off 各不相同 → 独立分档/形状；多个重叠 → 混合矿）
local PLANET = {
    nauvis = {
        {name = 'iron-ore', off = 11, amount = {300, 2000}},
        {name = 'copper-ore', off = 23, amount = {300, 2000}},
        {name = 'coal', off = 37, amount = {300, 1800}},
        {name = 'stone', off = 41, amount = {200, 1500}},
        {name = 'uranium-ore', off = 53, amount = {100, 800}},
        {name = 'scrap', off = 31, amount = {200, 3000}},
        {name = 'big-rock', off = 101, density = 0.4, threshold = 0.7},
        {name = 'huge-rock', off = 103, density = 0.25, threshold = 0.72},
    },
    vulcanus = {
        {name = 'tungsten-ore', off = 121, amount = {100, 800}},
        {name = 'ashland-lichen-tree', off = 131, density = 0.5, threshold = 0.6},   -- 灰烬树
        {name = 'big-volcanic-rock', off = 137, density = 0.4, threshold = 0.65},
        {name = 'huge-volcanic-rock', off = 139, density = 0.2, threshold = 0.7},
        {name = 'vulcanus-chimney', off = 141, density = 0.15, threshold = 0.72},
    },
    fulgora = {
        {name = 'scrap', off = 151, amount = {300, 3000}},
        {name = 'fulgoran-rock', off = 153, density = 0.4, threshold = 0.62},
        {name = 'fulgoran-gravewort', off = 155, density = 0.4, threshold = 0.6},     -- 雷击木/坟草
        {name = 'fulgoran-ruin-small', off = 157, density = 0.25, threshold = 0.72},  -- 遗迹
        {name = 'fulgoran-ruin-medium', off = 159, density = 0.12, threshold = 0.78},
    },
    gleba = {
        {name = 'copper-stromatolite', off = 163, amount = {200, 1500}},
        {name = 'iron-stromatolite', off = 167, amount = {200, 1500}},
        {name = 'stone', off = 169, amount = {200, 1200}},
    },
    aquilo = {
        {name = 'floating-iceberg-large', off = 173, density = 0.3, threshold = 0.65},  -- 冰块
        {name = 'lithium-iceberg-big', off = 179, density = 0.2, threshold = 0.7},
    },
}

-- 跨星球异物：小概率(rare)长到别的星球上，制造"违和的惊喜"。
local EXOTIC = {
    {name = 'scrap', off = 311, amount = {200, 2000}, rare = true},
    {name = 'ashland-lichen-tree', off = 313, density = 0.5, rare = true},
    {name = 'fulgoran-ruin-small', off = 317, density = 0.2, rare = true},
    {name = 'lithium-iceberg-big', off = 319, density = 0.2, rare = true},
    {name = 'huge-volcanic-rock', off = 321, density = 0.3, rare = true},
}

-- 战利品（坠机点/宝箱）
local LOOT = {
    {'iron-plate', 50, 250}, {'copper-plate', 50, 250}, {'steel-plate', 10, 80},
    {'electronic-circuit', 20, 120}, {'iron-gear-wheel', 20, 120}, {'coal', 40, 200},
    {'inserter', 5, 25}, {'transport-belt', 30, 120}, {'advanced-circuit', 5, 40},
    {'assembling-machine-1', 1, 4}, {'fast-inserter', 3, 15},
}
local function fill_loot(chest, n)
    local inv = chest.get_inventory(defines.inventory.chest)
    if not inv then return end
    for _ = 1, n do
        local l = LOOT[math.random(#LOOT)]
        inv.insert{name = l[1], count = math.random(l[2], l[3])}
    end
end

-- 区块级确定性随机 [0,1)：点状稀有风味用。
local function chunk_rng(lt, off)
    return noise.hash01(lt.x * 0.1234 + lt.y * 0.3717 + off * 1.7 + (storage.run or 0) * 0.011)
end

-- 物资箱（原"坠机点"）：飞船残骸机器人拆不了、挡蓝图，已移除；只留可拆的钢箱（战利品多些）。force=player。
local function feat_crash_site(surface, lt)
    local s = strength(503)
    if s == 0 or chunk_rng(lt, 503) > s * 0.05 then return end
    local cx, cy = lt.x + math.random(7, 25), lt.y + math.random(7, 25)
    if surface.can_place_entity{name = 'steel-chest', position = {cx + 0.5, cy + 0.5}} then
        local chest = surface.create_entity{name = 'steel-chest', force = 'player', position = {cx + 0.5, cy + 0.5}}
        if chest then fill_loot(chest, math.random(5, 9)) end
    end
end

-- 宝箱缓存（单个箱子）：更稀有。force=player。
local function feat_treasure(surface, lt)
    local s = strength(601)
    if s == 0 or chunk_rng(lt, 601) > s * 0.04 then return end
    local cx, cy = lt.x + math.random(2, 29), lt.y + math.random(2, 29)
    if surface.can_place_entity{name = 'iron-chest', position = {cx + 0.5, cy + 0.5}} then
        local chest = surface.create_entity{name = 'iron-chest', force = 'player', position = {cx + 0.5, cy + 0.5}}
        if chest then fill_loot(chest, math.random(2, 4)) end
    end
end

-- 虫群前哨（worm 炮塔）：tier 门控，远离出生点。force='enemy'（必须敌对）。
local WORMS = {'small-worm-turret', 'small-worm-turret', 'medium-worm-turret', 'big-worm-turret'}
local function feat_worms(surface, lt, A, S, Z)
    local s = strength(709)
    if s == 0 then return end
    for x = 0, 31, 4 do
        for y = 0, 31, 4 do
            local px, py = lt.x + x, lt.y + y
            if px * px + py * py > 80 * 80
               and noise.fractal_warped(noise.octaves.blob, px, py, wseed(709), A, S, Z) > (0.7 - s * 0.2)
               and math.random() < 0.35 then
                local w = WORMS[math.random(#WORMS)]
                local pos = {x = px + 0.5, y = py + 0.5}
                if surface.can_place_entity{name = w, position = pos} then
                    surface.create_entity{name = w, force = 'enemy', position = pos}
                end
            end
        end
    end
end

-- 树木主题（连续插值，不是离散几种世界）：把每棵树【从原版色/灰度插值到本轮目标】，插值量 = strength。
--   strength 立方偏置：绝大多数 ≈0（几乎原版）、极小概率接近 1（大改）。所以"特殊树世界"很罕见。
--   颜色目标按【位置低频噪声】取 → 相邻树同色、成片（像原版按地貌变化），不会每棵乱跳；
--   color_spread 连续控制"单一色 ↔ 多样"，gray_target 连续控制枯灰程度。含原生树一起调。
local function theme_trees(surface, lt)
    local gseed = wseed(401)
    local strength = noise.hash01(gseed * 8.1)
    strength = strength * strength * strength        -- 立方偏置 → 多数接近 0
    if strength < 0.05 then return end               -- 太弱当作原版，不动(也省开销)
    local gray_target  = noise.hash01(gseed * 4.7)   -- 本轮枯灰目标 0~1
    local base_color   = noise.hash01(gseed * 2.2)   -- 本轮基色
    local color_spread = noise.hash01(gseed * 5.3)   -- 颜色随位置变化幅度：0=单一 ↔ 1=多样（连续）
    local trees = surface.find_entities_filtered{area = {{lt.x, lt.y}, {lt.x + 32, lt.y + 32}}, type = 'tree'}
    for _, t in pairs(trees) do
        if t.valid then
            local gmax = t.tree_gray_stage_index_max
            if gmax and gmax > 0 then
                local target = gray_target * gmax
                t.tree_gray_stage_index = math.floor(t.tree_gray_stage_index + (target - t.tree_gray_stage_index) * strength + 0.5)
            end
            local cmax = t.tree_color_index_max
            if cmax and cmax > 0 then
                -- 颜色随位置平滑变化(低频噪声) → 成片同色；幅度由 color_spread 控制
                local n = (noise.fractal(noise.octaves.blob, t.position.x, t.position.y, gseed) + 1) * 0.5
                local cc = (base_color + (n - 0.5) * color_spread) % 1
                local target = cc * cmax
                t.tree_color_index = math.floor(t.tree_color_index + (target - t.tree_color_index) * strength + 0.5)
            end
        end
    end
end

-- 每个星球的圆内区块都调用：放本地特色 + 跨星球异物 + 树木主题 + 通用风味（坠机/宝箱/虫）。
function M.generate(surface, lt)
    local locals = PLANET[surface.name]
    if not locals then return end   -- 未定义的表面（如飞船平台）不处理
    -- 本轮【全局共享】的朝向/拉伸/缩放：各特征方向一致、不互相打架（绝大多数圆团，~15% 轮次才整体拉长）
    local A, S, Z = noise.seeded_transform(wseed(7))
    for _, def in ipairs(locals) do place_feature(surface, lt, def, A, S, Z) end
    for _, def in ipairs(EXOTIC) do place_feature(surface, lt, def, A, S, Z) end
    theme_trees(surface, lt)
    feat_worms(surface, lt, A, S, Z)
    feat_crash_site(surface, lt)
    feat_treasure(surface, lt)
end

return M
