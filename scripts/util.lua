-- 通用工具函数。除了读写 storage 外无副作用。
local M = {}

-- 追加一条 trait 到左上角 tooltip 列表。
-- 本地化字符串单层最多 20 个参数，超过 18 时把整张表嵌进
-- 一个新表 {'', old} 作为单个元素，再继续追加，从而突破单层上限。
function M.try_add_trait(trait)
    if not trait then
        return
    end
    storage.traits = storage.traits or {''}
    if table_size(storage.traits) >= 18 then
        storage.traits = {'', storage.traits}
    end
    table.insert(storage.traits, trait)
end

-- 数字格式化为人类可读的"档位"。
function M.readable(x)
    if x < 0 then
        return 0
    elseif x < 0.1 then
        return math.ceil(x * 100) * 0.01
    elseif x < 3 then
        return math.floor(x * 10) * 0.1
    elseif x < 10 then
        return math.floor(x)
    elseif x < 100 then
        return math.floor(x / 10) * 10
    elseif x < 1000 then
        return math.floor(x / 100) * 100
    else
        return math.floor(x / 1000) * 1000
    end
end

-- 指数分布，方差由 x 控制。
function M.random_exp(x)
    return math.pow(2, (math.random() - math.random()) * x)
end

-- 自然要素（水/树/敌人基地等）使用 nature 而非全局 frequency/size/richness。
function M.random_nature()
    storage.nature = storage.nature or 3
    return M.readable(math.pow(2, (math.random() - math.random()) * storage.nature))
end

return M
