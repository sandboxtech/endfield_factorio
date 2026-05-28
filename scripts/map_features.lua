-- 地图风味（原则：用噪声【修改 2.0 原生生成】，不用手动 stamp 去【覆盖】——原生地貌更自然）。
-- 因此本模块只做原生【做不到】的事；地貌(石/树/矿/水…)交回原生，由 surface.lua 用气候偏置/autoplace 调本轮风味。
--   · M.knobs()：本轮整局气质连续旋钮(繁茂/岩石/危险/富庶/异物)，与 surface.lua 共用 → 全局气质一致渐变。
--   · PLANET：目前空（手动放矿/废料表现不如原生，全交原生）；EXOTIC：跨星异物(原生无法跨星)，稀疏散布。
--   · 每特征从种子(storage.run+off)派生 strength：~60% 不出现，出现时立方偏置(多半小、极少大)。
--   · 树木主题 theme_trees：对【原生树】按本轮强度从原版色插值到目标色(连续，非离散世界) → 改原生，不覆盖。
--   · 通用风味：worm 虫群(force='enemy',仅母星)、随机木/铁/钢战利品箱(force='player',加权+品质)。
-- 由 surface.lua 的 on_chunk_generated 对各真实星球圆内区块调用 M.generate。
local noise = require('scripts.noise')

local M = {}

local function wseed(off) return (storage.run or 0) * 1009 + off end

-- 本轮【整局气质】连续旋钮（由 storage.run 确定性派生）：每个都是 [0,1) 连续量，不是硬编码离散概率——
-- 每轮整体氛围（繁茂↔荒芜、危险↔安宁、富庶↔贫瘠、寻常↔诡异）都是渐变的。
-- 同时供 surface.lua 调【2.0 原生 autoplace】(树/石密度) 与本模块手动特征门控共用 → 全局气质一致。
--   verdancy 植被繁茂  rockiness 岩石  danger 虫群危险(偏低)  riches 战利品(偏低)  exotic 异物倾向(很罕见)
function M.knobs()
    local function k(off, power)
        local v = noise.hash01(wseed(off) * 6.1)
        return power and v ^ power or v
    end
    -- 中心化：两个独立哈希之差 → 三角分布、集中在 0.5。多半接近原版，极端(极干极湿/极秃极茂)很罕见。
    local function kc(off)
        return 0.5 + (noise.hash01(wseed(off) * 6.1) - noise.hash01(wseed(off) * 3.7)) * 0.5
    end
    local exotic = k(809, 3)   -- 跨星球异物倾向（立方偏置，诡异世界很罕见）
    return {
        verdancy  = kc(801),      -- 树/草繁茂度（中心化：多半正常，极干/极茂罕见）
        rockiness = kc(803),      -- 岩石密度（中心化）
        riches    = k(807, 1.6),  -- 战利品丰度（曲线偏低）
        exotic    = exotic,
        -- 危险度：曲线偏低 + 与异物倾向【正相关】（诡异世界往往也更危险）。
        danger    = math.min(1, k(805, 2) * 0.7 + exotic * 0.7),
    }
end

-- 本轮该特征强度：~60% 为 0(不出现)；出现时走【立方偏置】——绝大多数小规模、极小概率大规模。
-- （r³ 把均匀随机压向 0：r=0.5→0.125、0.8→0.51、0.95→0.86，所以大规模很罕见。）
local function strength(off)
    if noise.hash01(wseed(off) * 7.3) < 0.60 then return 0 end
    local r = noise.hash01(wseed(off) * 3.1)
    return 0.1 + r * r * r * 0.9
end

-- 通用放置：def = {name, off, amount={lo,hi}(资源才填), density(0~1, 默认1), threshold(默认0.72),
--   force(默认player), rare(true=异星物，额外加一道小概率门)}
-- A/S/Z = 本轮【全局共享】的朝向/拉伸/缩放（所有特征一致，不互相打架）；def.off 决定各自的噪声场(位置不同)。
-- 两条路径：① 资源(def.amount) 需连续成片 → 逐格按噪声填；② 普通实体(稀疏) → 不逐格，而是【随机采样】
--   若干位置、命中噪声区才放（性能远好于 1024 格逐格判噪声）。
local function place_feature(surface, lt, def, A, S, Z, W)
    -- 异星物出现概率随【本轮异物倾向】连续变化（不再硬编码 15%）：寻常世界几乎没有，诡异世界才多。
    if def.rare and noise.hash01(wseed(def.off) * 9.9) > 0.03 + 0.5 * (W and W.exotic or 0) then return end
    local s = strength(def.off)
    if s == 0 then return end
    local fseed = wseed(def.off)
    -- 阈值高→覆盖小；s 多半很小(立方曲线)→大多数是小斑块，极少 s 大才铺成片
    local threshold = (def.threshold or 0.72) - s * 0.32

    if def.amount then
        -- 资源：逐格按噪声填（需要连续矿块）。
        for x = 0, 31 do
            for y = 0, 31 do
                local px, py = lt.x + x, lt.y + y
                if noise.fractal_warped(noise.octaves.scrap, px, py, fseed, A, S, Z) > threshold then
                    local pos = {x = px + 0.5, y = py + 0.5}
                    if surface.can_place_entity{name = def.name, position = pos} then
                        local rn = (noise.fractal(noise.octaves.scrap, px, py, fseed + 50000) + 1) * 0.5
                        surface.create_entity{name = def.name, force = def.force or 'player', position = pos,
                            amount = math.max(50, math.floor((def.amount[1] + (def.amount[2] - def.amount[1]) * rn) * (0.5 + s)))}
                    end
                end
            end
        end
    else
        -- 普通实体：随机采样 N 个位置，命中噪声区才放（N 随 density+本轮强度，几个而已）。
        local samples = math.random(0, math.ceil((def.density or 0.3) * 30 * (0.4 + s)))
        for _ = 1, samples do
            local px, py = lt.x + math.random(0, 31), lt.y + math.random(0, 31)
            if noise.fractal_warped(noise.octaves.scrap, px, py, fseed, A, S, Z) > threshold then
                local pos = {x = px + 0.5, y = py + 0.5}
                if surface.can_place_entity{name = def.name, position = pos} then
                    surface.create_entity{name = def.name, force = def.force or 'player', position = pos}
                end
            end
        end
    end
end

-- 手动放置的本地特色：目前为空。
--   矿/石/树/水/废料等手动 stamp 表现大多不如原生（连母星 scrap 也移除了）→ 全部交回 2.0 原生，
--   由 surface.lua 用「气候偏置 + autoplace」按本轮气质调风味（修改原生，而非覆盖）。
--   若以后要放"原生绝对没有"的本地特产，再在此按 {name, off, amount/density, threshold} 添加。
local PLANET = {}

-- 跨星球异物：原生 autoplace 无法把 A 星之物长到 B 星，这点"违和惊喜"只能手动。
-- 全 rare + 低密度高阈值 → 仅零星几个散布(不成片)；出现概率随【异物倾向】渐变。仅保留实体型(树/石/遗迹/冰山)，
-- 不放废料矿(手动废料表现差)。
local EXOTIC = {
    {name = 'ashland-lichen-tree', off = 313, rare = true, density = 0.06, threshold = 0.84},
    {name = 'fulgoran-ruin-small', off = 317, rare = true, density = 0.05, threshold = 0.86},
    {name = 'lithium-iceberg-big', off = 319, rare = true, density = 0.05, threshold = 0.86},
    {name = 'huge-volcanic-rock', off = 321, rare = true, density = 0.06, threshold = 0.86},
}

-- 战利品（坠机点/宝箱）。仿 RedMew 加权表：weight 高=常见便宜，低=稀有贵重；含部分 SA 中后期物品。
local LOOT = {
    {w = 10, name = 'iron-plate', lo = 50, hi = 300},
    {w = 10, name = 'copper-plate', lo = 50, hi = 300},
    {w = 8,  name = 'coal', lo = 40, hi = 200},
    {w = 6,  name = 'steel-plate', lo = 20, hi = 120},
    {w = 6,  name = 'electronic-circuit', lo = 30, hi = 160},
    {w = 5,  name = 'iron-gear-wheel', lo = 30, hi = 160},
    {w = 4,  name = 'transport-belt', lo = 40, hi = 160},
    {w = 4,  name = 'inserter', lo = 10, hi = 40},
    {w = 3,  name = 'advanced-circuit', lo = 10, hi = 60},
    {w = 2,  name = 'fast-inserter', lo = 5, hi = 25},
    {w = 2,  name = 'assembling-machine-2', lo = 1, hi = 4},
    {w = 1,  name = 'processing-unit', lo = 3, hi = 20},
    {w = 1,  name = 'speed-module', lo = 1, hi = 3},
    {w = 1,  name = 'productivity-module', lo = 1, hi = 3},
    {w = 1,  name = 'construction-robot', lo = 5, hi = 20},
}
local LOOT_TOTAL = 0
for _, l in ipairs(LOOT) do LOOT_TOTAL = LOOT_TOTAL + l.w end

-- 随机品质（2.0 SA 特性，1.0 战利品没有）：多数 normal，小概率 uncommon/rare → 开箱偶有惊喜。
local function roll_quality()
    local r = math.random()
    if r < 0.0003 then return 'legendary' end
    if r < 0.003 then return 'epic' end
    if r < 0.03 then return 'rare' end
    if r < 0.15 then return 'uncommon' end
    return 'normal'
end

-- 可机器人拆除的随机箱体：木/铁/钢（不再只钢箱）。
local CHESTS = {'wooden-chest', 'iron-chest', 'steel-chest'}

local function fill_loot(chest, n)
    local inv = chest.get_inventory(defines.inventory.chest)
    if not inv then return end
    for _ = 1, n do
        local roll, acc = math.random() * LOOT_TOTAL, 0
        for _, l in ipairs(LOOT) do
            acc = acc + l.w
            if roll <= acc then
                inv.insert{name = l.name, count = math.random(l.lo, l.hi), quality = roll_quality()}
                break
            end
        end
    end
end

-- 测试箱奖励（罕见）：永续箱(随机物品无限供应) 或 无底箱(无限垃圾桶)。设为【不可打开/不可拆走、可摧毁】，
-- 防止滥用又能就地用（接机械臂/传送带）。force=player。
local function spawn_test_chest(surface, pos)
    local chest = surface.create_entity{name = 'infinity-chest', force = 'player', position = pos}
    if not chest then return end
    if math.random() < 0.7 then                                   -- 永续箱：随机一种物品无限供应
        local item = LOOT[math.random(#LOOT)].name
        local ss = prototypes.item[item] and prototypes.item[item].stack_size or 50
        chest.infinity_container_filters = {{index = 1, name = item, count = ss, mode = 'exactly'}}
    else                                                          -- 无底箱：移除一切（无限垃圾桶）
        chest.remove_unfiltered_items = true
    end
    chest.operable = false        -- 不可打开/重配
    chest.minable_flag = false    -- 不可拆走
    chest.destructible = true     -- 可摧毁
end

-- 放一个战利品箱：小概率是测试箱奖励，否则普通木/铁/钢箱 + 加权战利品。pos = {x+0.5, y+0.5}。
local function place_loot_chest(surface, pos, n)
    if not surface.can_place_entity{name = 'steel-chest', position = pos} then return end
    -- 每世界独立的战利品风格（surface.lua 滚定）：哪些箱体 + 测试箱概率。无则兜底默认。
    local style = storage.loot_style and storage.loot_style[surface.name]
    local chests = (style and style.chests) or CHESTS
    local test = (style and style.test) or (storage.test_chest_chance or 0.06)   -- 0 也是合法值(本世界不出测试箱)
    if math.random() < test then
        spawn_test_chest(surface, pos)
    else
        local chest = surface.create_entity{name = chests[math.random(#chests)], force = 'player', position = pos}
        if chest then fill_loot(chest, n) end
    end
end

-- 区块级确定性随机 [0,1)：点状稀有风味用。
local function chunk_rng(lt, off)
    return noise.hash01(lt.x * 0.1234 + lt.y * 0.3717 + off * 1.7 + (storage.run or 0) * 0.011)
end

-- 物资箱（原"坠机点"）：战利品多些。force=player。频率随【富庶度】渐变。
local function feat_crash_site(surface, lt, W)
    local s = strength(503)
    if s == 0 or chunk_rng(lt, 503) > s * (0.02 + 0.06 * (W and W.riches or 0)) then return end
    place_loot_chest(surface, {lt.x + math.random(7, 25) + 0.5, lt.y + math.random(7, 25) + 0.5}, math.random(5, 9))
end

-- 宝箱缓存（单个箱）：更稀有。force=player。频率随【富庶度】渐变。
local function feat_treasure(surface, lt, W)
    local s = strength(601)
    if s == 0 or chunk_rng(lt, 601) > s * (0.015 + 0.05 * (W and W.riches or 0)) then return end
    place_loot_chest(surface, {lt.x + math.random(2, 29) + 0.5, lt.y + math.random(2, 29) + 0.5}, math.random(2, 4))
end

-- 按本星【独立开关】theme 构建敌人池（worm/spawner/turret/mine/art 各自有无）。
--   带弹的：gun-turret 用本星弹种 theme.mag(mag=true)，artillery-turret 固定炮弹；无标记的不填弹。
local function danger_pool(t)
    local pool = {}
    if t.worm then pool[#pool + 1] = 'small-worm-turret'; pool[#pool + 1] = 'medium-worm-turret'; pool[#pool + 1] = 'big-worm-turret' end
    if t.spawner then pool[#pool + 1] = 'biter-spawner'; pool[#pool + 1] = 'spitter-spawner' end
    if t.mine then pool[#pool + 1] = 'land-mine' end
    if t.turret then pool[#pool + 1] = {name = 'gun-turret', mag = true, n = 20} end
    if t.art then pool[#pool + 1] = {name = 'artillery-turret', ammo = 'artillery-shell', n = 4} end
    return pool
end
-- 远离出生点(>96格)随机采样放敌人；数量随危险度 × storage.danger_density。force='enemy'。
local function feat_danger(surface, lt, A, S, Z, W)
    local theme = storage.danger_theme and storage.danger_theme[surface.name]
    if not theme then return end
    local pool = danger_pool(theme)
    if #pool == 0 then return end
    local danger = W.danger
    local thr = 0.78 - 0.25 * danger
    for _ = 1, math.random(0, math.ceil(danger * 12 * (storage.danger_density or 1))) do
        local px, py = lt.x + math.random(0, 31), lt.y + math.random(0, 31)
        if px * px + py * py > 96 * 96
           and noise.fractal_warped(noise.octaves.blob, px, py, wseed(811), A, S, Z) > thr then
            local def = pool[math.random(#pool)]
            local name = type(def) == 'table' and def.name or def
            local pos = {x = px + 0.5, y = py + 0.5}
            if surface.can_place_entity{name = name, position = pos} then
                local e = surface.create_entity{name = name, force = 'enemy', position = pos}
                if e and type(def) == 'table' then
                    local ammo = def.mag and theme.mag or def.ammo   -- 机枪用本星弹种；重炮用炮弹
                    if ammo then e.insert{name = ammo, count = def.n} end
                end
            end
        end
    end
end

-- 危险世界偶现飞船残骸：机器人无法拆除 → 阻碍蓝图，作为障碍风味。force='neutral'。
local WRECKS = {
    'crash-site-spaceship-wreck-big-1', 'crash-site-spaceship-wreck-big-2',
    'crash-site-spaceship-wreck-medium-1', 'crash-site-spaceship-wreck-medium-2', 'crash-site-spaceship-wreck-medium-3',
    'crash-site-spaceship-wreck-small-1', 'crash-site-spaceship-wreck-small-2', 'crash-site-spaceship-wreck-small-3',
}
local function feat_wrecks(surface, lt, W)
    if not (storage.danger_theme and storage.danger_theme[surface.name]) then return end
    if chunk_rng(lt, 813) > 0.05 * W.danger * (storage.danger_density or 1) then return end
    local name = WRECKS[math.random(#WRECKS)]
    local pos = surface.find_non_colliding_position(name, {lt.x + math.random(4, 27), lt.y + math.random(4, 27)}, 12, 1)
    if pos then surface.create_entity{name = name, position = pos, force = 'neutral'} end
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
                local v = math.floor(t.tree_gray_stage_index + (target - t.tree_gray_stage_index) * strength + 0.5)
                t.tree_gray_stage_index = math.max(0, math.min(gmax, v))   -- 灰度 0-based [0,gmax]
            end
            local cmax = t.tree_color_index_max
            if cmax and cmax > 0 then
                -- 颜色随位置平滑变化(低频噪声) → 成片同色；幅度由 color_spread 控制
                local n = (noise.fractal(noise.octaves.blob, t.position.x, t.position.y, gseed) + 1) * 0.5
                local cc = (base_color + (n - 0.5) * color_spread) % 1
                local target = cc * cmax
                local v = math.floor(t.tree_color_index + (target - t.tree_color_index) * strength + 0.5)
                t.tree_color_index = math.max(1, math.min(cmax, v))        -- 颜色 1-based [1,cmax]，0 会报错
            end
        end
    end
end

local REAL_PLANETS = {nauvis = true, vulcanus = true, fulgora = true, gleba = true, aquilo = true}

-- 每个真实星球的圆内区块都调用。只做原生做不到的事：母星废料/跨星异物(手动) + 树木调色(改原生树) +
-- 通用风味(虫/物资箱)。地貌(石/树/矿/水…)本身交回 2.0 原生，本轮风味由 surface.lua 的气候偏置/autoplace 决定。
function M.generate(surface, lt)
    if not REAL_PLANETS[surface.name] then return end   -- 飞船平台等跳过
    local W = M.knobs()
    -- 本轮【全局共享】的朝向/拉伸/缩放：各特征方向一致、不互相打架（绝大多数圆团，~15% 轮次才整体拉长）
    local A, S, Z = noise.seeded_transform(wseed(7))
    local home = PLANET[surface.name]
    if home then
        for _, def in ipairs(home) do place_feature(surface, lt, def, A, S, Z, W) end
    end
    for _, def in ipairs(EXOTIC) do place_feature(surface, lt, def, A, S, Z, W) end
    theme_trees(surface, lt)
    feat_crash_site(surface, lt, W)
    feat_treasure(surface, lt, W)
    -- 危险世界（按 W.danger，与 exotic 正相关）：成簇敌方实体 + 偶现飞船残骸障碍。原版 enemy-base 仍自然出虫。
    feat_danger(surface, lt, A, S, Z, W)
    feat_wrecks(surface, lt, W)
end

return M
