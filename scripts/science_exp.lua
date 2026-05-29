local constants = require('scripts.constants')

local M = {}

-- 取某玩家的累计经验表（按【玩家名】存储）。create=true 时确保表存在（用于写入）；
-- 否则没经验时返回 nil。
function M.player_exp(player, create)
    storage.science_exp = storage.science_exp or {}
    local exp = storage.science_exp[player.name]
    if not exp and create then
        exp = {}
        storage.science_exp[player.name] = exp
    end
    return exp
end

-- 遍历背包里的整组科技瓶 → 按瓶名汇总经验：floor(数量/堆叠数) × 品质系数(normal=1…legendary=5)。
-- 返回 { [瓶名] = 经验 }，只含 >0 的项。collect 与 preview 共用，避免两处算法各自漂移。
local function sum_packs(inventory)
    local out = {}
    for _, item in pairs(inventory.get_contents()) do
        if string.sub(item.name, -13) == '-science-pack' then
            local proto = prototypes.item[item.name]
            local mult = constants.quality_exp[item.quality] or 0
            if proto and mult > 0 then
                local gained = math.floor(item.count / proto.stack_size) * mult
                if gained > 0 then
                    out[item.name] = (out[item.name] or 0) + gained
                end
            end
        end
    end
    return out
end

-- 跃迁结算：统计【在线】玩家背包里整组科技瓶 → 经验累加进 storage.science_exp（按瓶名，各品质合并）。
-- 不移除瓶子——跃迁本就清空背包。只有自动跃迁会调用（无提前结算）。必须在背包被清空之前调用。
-- 返回本轮各瓶获得经验 {瓶名=经验}；离线/无背包返回 nil。
function M.collect(player)
    if not player.connected then return nil end
    local inventory = player.get_inventory(defines.inventory.character_main)
    if not inventory then return nil end

    local player_exp = M.player_exp(player, true)
    local round_gain = sum_packs(inventory)
    for pack, gained in pairs(round_gain) do
        player_exp[pack] = (player_exp[pack] or 0) + gained
    end
    return round_gain
end

-- 预览：若现在跃迁，背包里的科技瓶各能换多少经验（按瓶汇总，不写入 storage、不打印）。
-- 返回 { [瓶名] = 经验, ... }，只含 >0 的项；与 M.collect 同一算法（sum_packs）。
function M.preview(player)
    local inventory = player and player.get_inventory(defines.inventory.character_main)
    if not inventory then return {} end
    return sum_packs(inventory)
end

return M
