local constants = require('scripts.constants')

local M = {}

-- 扫描在线玩家背包里的科技瓶，按品质和"组数"换算成经验存入 storage.science_exp。
-- 必须在玩家被杀/背包被清空之前调用。
function M.collect(player)
    if not player.connected then return end
    local inventory = player.get_inventory(defines.inventory.character_main)
    if not inventory then return end

    storage.science_exp = storage.science_exp or {}
    storage.science_exp[player.index] = storage.science_exp[player.index] or {}
    local player_exp = storage.science_exp[player.index]

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
                    game.print({'wn.exp-gain', player.name .. ' ', item.name, item.quality, gained})
                end
            end
        end
    end
end

return M
