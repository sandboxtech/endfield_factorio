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

-- 扫描在线玩家背包里的科技瓶，按品质和"组数"换算成经验存入 storage.science_exp。
-- 必须在玩家被杀/背包被清空之前调用。返回本轮各瓶获得的经验 {瓶名=经验}（供结算用）；
-- 离线/无背包返回 nil。不再逐条打印，改由 reset 汇总成一份本轮结算。
function M.collect(player)
    if not player.connected then return nil end
    local inventory = player.get_inventory(defines.inventory.character_main)
    if not inventory then return nil end

    local player_exp = M.player_exp(player, true)

    local round_gain = {}
    for _, item in pairs(inventory.get_contents()) do
        if string.sub(item.name, -13) == '-science-pack' then
            local proto = prototypes.item[item.name]
            local mult = constants.quality_exp[item.quality] or 0
            if proto and mult > 0 then
                -- 每组(stack)按品质给经验：normal=1 … legendary=5。
                -- key 只用瓶名（12 种），不分品质——各品质累加到同一瓶的经验里。
                local gained = math.floor(item.count / proto.stack_size) * mult
                if gained > 0 then
                    player_exp[item.name] = (player_exp[item.name] or 0) + gained
                    round_gain[item.name] = (round_gain[item.name] or 0) + gained
                end
            end
        end
    end
    return round_gain
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
