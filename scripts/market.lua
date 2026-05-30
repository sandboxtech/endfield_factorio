-- 各星球出生点的金币市场（母星 + 其余 4 个星球，共 5 个，内容相同）：用挂机赚的金币(√在线分钟)买各种普通装备零件。
-- 卖装备而非建筑/瓶子——是个人增益，不替代"建工厂"的核心循环。
-- 每轮跃迁后由 surface.lua 的 on_surface_cleared（每个 PLANET_GEN 星球、clear 结算后）放置；不可摧毁/挖取。
local M = {}

-- 出售清单：{物品, 数量, 金币价}。金币来自在线（开局 √在线分钟 + 每分钟 +1）。
M.offers = {
    -- 【分级装备】按梯度定价：高级档每点属性更贵（性价比明显更低），换取同/更省装甲格。
    --   电池每档都占 2 格：mk1 20MJ / mk2 100MJ / mk3 250MJ；每 MJ 单价 6.7→3.3→2.1，越高越亏但越省格。
    {'battery-equipment',                1,   3},   -- 20MJ  · 2 格
    {'battery-mk2-equipment',            1,  50},   -- 100MJ · 2 格
    {'battery-mk3-equipment',            1, 300},   -- 250MJ · 2 格

    {'energy-shield-equipment',          1,  5},   -- 50 护盾  · 4 格
    {'energy-shield-mk2-equipment',      1,  100},   -- 150 护盾 · 4 格
    {'personal-roboport-equipment',      1,  10},   -- 35MJ 缓冲 · 4 格
    {'personal-roboport-mk2-equipment',  1,  100},   -- 更快更多机器人 · 4 格

    -- 护甲格子（装零件用）
    {'modular-armor',                    1, 5},
    {'power-armor',                      1, 50},   
    {'power-armor-mk2',                  1, 500},
    {'mech-armor',                       1, 2000},

    -- 【单级装备】无分级，价格自行配置
    {'night-vision-equipment',           1,   1},   -- 夜视仪：暗世界/永夜看路用，便宜
    {'exoskeleton-equipment',            1,  30},
    {'personal-laser-defense-equipment', 1,  50},
    {'toolbelt-equipment',               1,  100},

    -- 电源：按功率定价，功率越高每瓦越贵（高级件性价比更低）。功率假设 100 / 750 / 2500。
    {'solar-panel-equipment',            1,   3},   -- 100
    {'fission-reactor-equipment',        1,  50},   -- 750
    {'fusion-reactor-equipment',         1, 300},   -- 2500
}

local function stock(ent)
    for _, o in ipairs(M.offers) do
        ent.add_market_item{
            price = {{name = 'coin', count = o[3]}},                 -- 金币价（normal）
            offer = {type = 'give-item', item = o[1], count = o[2]}, -- 产出 normal 装备
        }
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
-- 故不再强制生成区块——此时出生区块已存在。每轮每星只放一次（storage.market_run 记录）。
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
    -- 清掉挡路实体（树/悬崖/石头；矿脉不挡建筑，保留）
    for _, e in pairs(surface.find_entities_filtered{position = {bx, by}, radius = 3, type = {'tree', 'cliff', 'simple-entity'}}) do
        if e.valid then e.destroy() end
    end
    -- 铺一块 5×5 混凝土地坪，去掉水/不平地形保证放置成功
    local tiles = {}
    for dx = -2, 2 do
        for dy = -2, 2 do
            tiles[#tiles + 1] = {name = 'refined-concrete', position = {bx + dx, by + dy}}
        end
    end
    surface.set_tiles(tiles)

    local ent = surface.create_entity{name = 'market', position = {bx, by}, force = force}
    if not ent then return nil end
    ent.destructible = false   -- 不可摧毁
    ent.minable = false        -- 不可挖取
    stock(ent)
    return ent                 -- 放置成功（调用方据此标记本轮已放、不再重试）
end

return M
