-- 母星出生点的金币市场（仅一个）：用挂机赚的金币(√在线分钟)买各种普通装备零件。
-- 卖装备而非建筑/瓶子——是个人增益，不替代"建工厂"的核心循环。
-- 每轮跃迁后由 surface.lua 的 on_surface_cleared（母星分支、clear 结算后）放置；不可摧毁/挖取。
local M = {}

-- 出售清单：{物品, 数量, 金币价}。价格相对挂机金币（√在线分钟，约每局 7~100 枚）合理，可自由增删/调价。
M.offers = {
    {'solar-panel-equipment',            1, 2},
    {'battery-equipment',                1, 2},
    {'battery-mk2-equipment',            1, 6},
    {'battery-mk3-equipment',            1, 12},
    {'personal-roboport-equipment',      1, 4},
    {'personal-roboport-mk2-equipment',  1, 12},
    {'night-vision-equipment',           1, 2},
    {'belt-immunity-equipment',          1, 3},
    {'toolbelt-equipment',               1, 5},
    {'exoskeleton-equipment',            1, 5},
    {'energy-shield-equipment',          1, 4},
    {'energy-shield-mk2-equipment',      1, 10},
    {'discharge-defense-equipment',      1, 6},
    {'personal-laser-defense-equipment', 1, 8},
    {'fusion-reactor-equipment',         1, 15},
    -- 配套护甲（装备零件需要装甲格子才能装上用）
    {'power-armor',                      1, 20},
    {'power-armor-mk2',                  1, 60},
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
