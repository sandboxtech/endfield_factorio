-- 母星出生点的金币市场（仅一个）：用挂机赚的金币(√在线分钟)买各种普通装备零件。
-- 卖装备而非建筑/瓶子——是个人增益，不替代"建工厂"的核心循环。
-- 每轮跃迁后由 surface.lua 的 on_surface_cleared（母星分支、clear 结算后）放置；不可摧毁/挖取。
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

-- 每轮跃迁后调用：在出生点正北放一个金币市场并上架装备。
function M.place_on_nauvis()
    local nauvis = game.surfaces['nauvis']
    if not nauvis then return end
    local force = game.forces.player
    local s = force.get_spawn_position(nauvis)
    local bx, by = math.floor(s.x), math.floor(s.y - 8)   -- 出生点正北 8 格（北 = -Y）

    -- 紧接 surface.clear 之后，必须强制生成市场所在区块，否则 create_entity 会失败
    nauvis.request_to_generate_chunks({bx, by}, 1)
    nauvis.force_generate_chunk_requests()

    -- 安全网：重复调用时清掉旧市场
    for _, old in pairs(nauvis.find_entities_filtered{name = 'market', position = {bx, by}, radius = 8}) do
        old.destroy()
    end
    -- 清掉挡路实体（树/悬崖/石头；矿脉不挡建筑，保留）
    for _, e in pairs(nauvis.find_entities_filtered{position = {bx, by}, radius = 3, type = {'tree', 'cliff', 'simple-entity'}}) do
        if e.valid then e.destroy() end
    end
    -- 铺一块 5×5 混凝土地坪，去掉水/不平地形保证放置成功
    local tiles = {}
    for dx = -2, 2 do
        for dy = -2, 2 do
            tiles[#tiles + 1] = {name = 'refined-concrete', position = {bx + dx, by + dy}}
        end
    end
    nauvis.set_tiles(tiles)

    local ent = nauvis.create_entity{name = 'market', position = {bx, by}, force = force}
    if not ent then return end
    ent.destructible = false   -- 不可摧毁
    ent.minable = false        -- 不可挖取
    stock(ent)
end

return M
