-- 各星球出生点的金币市场（母星 + 其余 4 个星球，共 5 个，内容相同）：用金币买各种普通装备零件。
-- 卖装备而非建筑/瓶子，是个人增益，不替代"建工厂"的核心循环。
-- 每轮跃迁后由 surface.lua 的 on_surface_cleared（每个 PLANET_GEN 星球、clear 结算后）放置；不可摧毁/挖取。
local M = {}

-- 出售清单：{物品, 数量, 金币价}。金币只来自每轮开局 floor(√在线分钟)（不再每分钟发），数量很小，
-- 故整体定价压得很低，让玩家开局就买得起一套基础装备；但【分级装备】高级档每单位属性的单价仍递增
-- （越高越亏），低级件性价比始终更优 → 鼓励多买低级、把高级件当"省格子"的奢侈选项。
-- 商品按【组】排列，组间用 'sep' 标记分隔。市场货架每行 10 格，stock() 在每个 'sep' 处
-- 补足 type='nothing' 的空占位到 10 的倍数 → 下一组从新的一行开始（同职业窗口的 {} 换行思路）。
-- 定价原则：整体偏贵（金币是稀缺货币），且【越高级性价比越低】——每升一档价格陡升(远超战力提升)，
-- 逼玩家权衡"多买低级 vs 攒大钱上顶级"。顶级锚点 mech-armor=1000。
M.offers = {
    -- 护甲格子（装零件用）：格子越多越贵，单格单价【陡升】。
    {'modular-armor',                    1,    5},
    {'power-armor',                      1,   50},
    {'power-armor-mk2',                  1,  250},
    {'mech-armor',                       1, 1000},   -- 顶级锚点
    'sep',

    -- 【单级装备】无分级。
    {'night-vision-equipment',           1,    2},   -- 夜视仪：暗世界/永夜看路用，最便宜
    {'exoskeleton-equipment',            1,   25},
    {'personal-laser-defense-equipment', 1,   40},
    {'toolbelt-equipment',               1,   50},
    'sep',

    -- 电源（发电）：太阳能 / 裂变 / 聚变，越高级单位功率越贵。
    {'solar-panel-equipment',            1,    5},
    {'fission-reactor-equipment',        1,   60},
    {'fusion-reactor-equipment',         1,  300},
    'sep',

    -- 电池(储电)：mk1 / mk2 / mk3，越高级每 MJ 越贵 → 多买低级更划算。
    {'battery-equipment',                1,    5},   -- 20MJ  · 2 格
    {'battery-mk2-equipment',            1,   40},   -- 100MJ · 2 格
    {'battery-mk3-equipment',            1,  250},   -- 250MJ · 2 格
    'sep',

    -- 护盾：50 / 150 点，越高级每点越贵。
    {'energy-shield-equipment',          1,   10},   -- 50 护盾  · 4 格
    {'energy-shield-mk2-equipment',      1,   70},   -- 150 护盾 · 4 格
    -- 个人机器人端口：mk2 更快、容纳更多机器人，溢价更高。
    {'personal-roboport-equipment',      1,   15},   -- 35MJ 缓冲 · 4 格
    {'personal-roboport-mk2-equipment',  1,  120},
    'sep',

    -- 矿石补给：2 金币换 50 矿石（1 组），开局/缺料时应急补给（性价比已下调）。
    {'iron-ore',                        50,    2},
    {'copper-ore',                      50,    2},
    {'stone',                           50,    2},
    {'coal',                            50,    2},
    {'wood',                            50,    2},
}

-- 价格存进 storage.market_prices（item → 金币价），可运行时热改：
--   /c storage.market_prices['mech-armor'] = 2000      改单价
--   /c storage.market_prices = nil; remote... 或 reset 重新播种恢复默认
-- M.offers 的第 3 列只是【默认价种子】；缺失才补 → 保留管理员热改。由 commands.ensure_all 调用。
function M.ensure_prices()
    storage.market_prices = storage.market_prices or {}
    for _, o in ipairs(M.offers) do
        if type(o) == 'table' and storage.market_prices[o[1]] == nil then
            storage.market_prices[o[1]] = o[3]
        end
    end
end

local ROW = 10   -- 市场货架每行格数：每组补空占位到此倍数实现换行

local function stock(ent)
    local n = 0   -- 已上架格数（含空占位）
    local function fill_row()   -- 补占位到整行：price 与 offer 都用 base 内置的空物品 'no-item'（专为占位设计）。
        -- no-item 玩家既给不出也拿不到 → 天然是个买不了的空格子，比天价 coin/nothing 红叉都干净，不崩不刷 4.2G。
        while n % ROW ~= 0 do
            ent.add_market_item{
                price = {{name = 'no-item', count = 1}},
                offer = {type = 'give-item', item = 'no-item', count = 1},
            }
            n = n + 1
        end
    end
    local prices = storage.market_prices or {}
    for _, o in ipairs(M.offers) do
        if o == 'sep' then
            fill_row()   -- 分组换行：补满当前行
        else
            ent.add_market_item{
                price = {{name = 'coin', count = prices[o[1]] or o[3]}},  -- 金币价：优先 storage 热改值，缺失退默认 o[3]
                offer = {type = 'give-item', item = o[1], count = o[2]},  -- 产出 normal 装备
            }
            n = n + 1
        end
    end
end

-- 出生点【保底铺地】：以出生点(地图中心)为心抽 4×4=16 个采样点（散布在 64×64 内），
-- 若【(>4)】落在不可通行地形(水/深水/熔岩/油海/氨海/虚空…，按 tile.collides_with('player') 判定)，
-- 说明这是个水/exotic 世界、开局没立足之地 → 铺一整块 64×64 精炼混凝土保底。否则(多半是陆地)不动。
local SAFE_HALF = 32                         -- 64×64 的半边
local SAMPLE_OFFSETS = {-24, -8, 8, 24}      -- 采样网格偏移（4×4 共 16 点，均匀铺在 64×64 内）
local function ensure_spawn_ground(surface, sx, sy)
    local bad = 0
    for _, dx in ipairs(SAMPLE_OFFSETS) do
        for _, dy in ipairs(SAMPLE_OFFSETS) do
            local t = surface.get_tile(sx + dx, sy + dy)
            if t and t.valid and t.collides_with('player') then bad = bad + 1 end
        end
    end
    if bad <= 4 then return end              -- 过半可通行 → 无需保底
    local tiles = {}
    for dx = -SAFE_HALF, SAFE_HALF - 1 do
        for dy = -SAFE_HALF, SAFE_HALF - 1 do
            tiles[#tiles + 1] = {name = 'refined-concrete', position = {sx + dx, sy + dy}}
        end
    end
    surface.set_tiles(tiles)
end

-- 在【指定星球】出生点正北放一个金币市场并上架装备。母星 + 其余 4 个星球各放一个同样的市场。
-- 【惰性放置】：由 surface.lua 的 on_chunk_generated 在【出生区块自然生成时】调用（玩家复活/传送到该星触发），
-- 故不再强制生成区块，此时出生区块已存在。每轮每星只放一次（storage.market_run 记录）。
function M.place_on_surface(surface_name)
    local surface = game.surfaces[surface_name]
    if not surface then return end
    local force = game.forces.player
    local s = force.get_spawn_position(surface)
    local sx, sy = math.floor(s.x), math.floor(s.y)
    local bx, by = sx, sy - 8   -- 市场放出生点正北 8 格（北 = -Y）

    -- 市场所在区块还没生成 → 放弃（不强制生成）；on_chunk_generated 会在它生成后再调一次重试。返回 nil 表示未放成。
    if not surface.is_chunk_generated({math.floor(bx / 32), math.floor(by / 32)}) then return nil end

    -- 出生点保底铺地（极端水/exotic 世界用；判过半不可通行才铺）
    ensure_spawn_ground(surface, sx, sy)

    -- 安全网：重复调用时清掉旧市场
    for _, old in pairs(surface.find_entities_filtered{name = 'market', position = {bx, by}, radius = 8}) do
        old.destroy()
    end
    -- 清掉市场地坪上【任何会挡住放置】的实体（树/悬崖/石头/战利品箱…），只保留矿脉(resource，不挡建筑)和玩家(character)。
    -- 注意：map_features 在本区块【先于】市场运行、可能在出生点附近落一个战利品箱(container)正好压在市场点上，
    -- 导致 create_entity('market') 碰撞返回 nil、市场放不出，这正是"有时没市场"的主因。故按区域清干净、不再只清树石。
    for _, e in pairs(surface.find_entities_filtered{area = {{bx - 2, by - 2}, {bx + 2, by + 2}}}) do
        if e.valid and e.type ~= 'resource' and e.type ~= 'character' then e.destroy() end
    end
    -- 铺一块 5×5 混凝土地坪，去掉水/岩浆/油海/不平地形保证放置成功。
    -- set_tiles 是脚本级、不受建造限制：mineable 的 refined-concrete 铺到 non-mineable 的岩浆/油海/水上时，
    -- 液体变成 hidden_tile（藏到底下）、混凝土成为可走表层，故能直接盖住，无需 foundation/landfill。
    local tiles = {}
    for dx = -2, 2 do
        for dy = -2, 2 do
            tiles[#tiles + 1] = {name = 'refined-concrete', position = {bx + dx, by + dy}}
        end
    end
    surface.set_tiles(tiles)

    local ent = surface.create_entity{name = 'market', position = {bx, by}, force = force}
    if not ent then
        -- 兜底：万一原位仍被占，就近找个不冲突的位置放，保证市场一定出现（不再"有时没有"）。
        local p = surface.find_non_colliding_position('market', {bx, by}, 8, 0.5)
        if p then ent = surface.create_entity{name = 'market', position = p, force = force} end
    end
    if not ent then return nil end
    ent.destructible = false   -- 不可摧毁
    ent.minable = false        -- 不可挖取
    stock(ent)
    return ent                 -- 放置成功（调用方据此标记本轮已放、不再重试）
end

return M
