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

-- 内部：统计背包里整组科技瓶 → 经验存入 storage.science_exp（按瓶名累加，各品质合并；每组按品质 normal=1…legendary=5）。
-- remove=true 时把【已计入经验的整组瓶子】从背包移除（提前结算用：消耗掉 → 跃迁时无可重复结算）。
-- 必须在玩家被杀/背包被清空之前调用。返回本轮各瓶获得经验 {瓶名=经验}；无背包返回 nil。
local function tally(player, remove)
    local inventory = player.get_inventory(defines.inventory.character_main)
    if not inventory then return nil end

    local player_exp = M.player_exp(player, true)
    local round_gain = {}
    for _, item in pairs(inventory.get_contents()) do
        if string.sub(item.name, -13) == '-science-pack' then
            local proto = prototypes.item[item.name]
            local mult = constants.quality_exp[item.quality] or 0
            if proto and mult > 0 then
                local stacks = math.floor(item.count / proto.stack_size)
                local gained = stacks * mult
                if gained > 0 then
                    player_exp[item.name] = (player_exp[item.name] or 0) + gained
                    round_gain[item.name] = (round_gain[item.name] or 0) + gained
                    if remove then
                        inventory.remove{name = item.name, count = stacks * proto.stack_size, quality = item.quality}
                    end
                end
            end
        end
    end
    return round_gain
end

-- 跃迁结算：扫描【在线】玩家背包换经验（不移除——跃迁本就清空背包）。
function M.collect(player)
    if not player.connected then return nil end
    return tally(player, false)
end

-- 提前结算：当前整组瓶子换经验【并移除】→ 本轮已结算的不会在跃迁时再算一次。
-- 用于坚持不到跃迁就要下线的玩家（/settle 指令、on_pre_player_left_game 离线前自动调用）。不要求 connected。
function M.settle(player)
    return tally(player, true)
end

-- 预览：若现在跃迁，背包里的科技瓶各能换多少经验（按瓶汇总，不写入 storage、不打印）。
-- 返回 { [瓶名] = 经验, ... }，只含 >0 的项；与 M.collect 的算法一致。
function M.preview(player)
    local out = {}
    local inventory = player and player.get_inventory(defines.inventory.character_main)
    if not inventory then return out end
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

return M
