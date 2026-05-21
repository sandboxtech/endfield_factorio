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
                local gained = math.floor(item.count / proto.stack_size) * mult
                if gained > 0 then
                    local key = item.name .. '/' .. item.quality
                    player_exp[key] = (player_exp[key] or 0) + gained
                    game.print({'wn.exp-gain', player.name .. ' ', item.name, item.quality, gained})
                end
            end
        end
    end
end

return M
