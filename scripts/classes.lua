-- 职业系统：每个职业是一个【专精主题】，决定开局发什么物品。
-- 玩家随时可在【职业】按钮窗口里切换（同时只能一种，存 storage.player_class[名]，带短冷却）。
-- 进服默认职业 = 平民（未选择时按平民对待，见 M.DEFAULT / selected_key 兜底）。
--
-- 设计：职业不再与单一瓶一一对应，而是围绕一个主题（采矿/机器人/某阶段/外星…）。
--   一个职业可挂【多条 rewards】，每条用一种瓶的等级出一种物品 → 练对应的瓶就出对应的货。
--
-- 每个职业的字段：
--   starter  无条件初始物品列表：每条 {item=物品, groups=组数(默认1)}，每轮开局直接发（不看等级）。
--            可列多种、各自不同组数。
--   rewards  经验奖励物品列表：每条 {pack=瓶, item=物品, groups=满级组数}。
--            按该瓶等级线性发：个数 = floor(堆叠 × groups × 等级 / 满级(10000))【向下取整】。
--            满 N 级才给第 1 个（N=满级/总个数）；可 0~多条（多瓶职业）。
--   unlock   解锁条件列表（可选）：每条 {pack=瓶, level=级}，需【全部满足】才能选；无则人人可选（当前全部无门槛）。
local passives = require('scripts.passives')

local M = {}

M.DEFAULT = 'civilian'
M.MAX_LEVEL = 10000   -- 满级基准（与 respawn_gifts.MAX_LEVEL / gui CLASS_MAX_LEVEL 一致）

-- 职业表（顺序即面板显示顺序）。当前均无 unlock 门槛，人人可选。
M.list = {
    -- 平民：默认职业。只白送热能采矿机起步，无经验奖励。
    {key = 'civilian', starter = {{item = 'burner-mining-drill'}}},

    -- 采矿专家：专精采矿。热能矿机起步；练【红瓶】出电力采矿机、练【橙瓶(火山)】出大型采矿机。
    {key = 'miner', starter = {{item = 'burner-mining-drill'}}, rewards = {
        {pack = 'automation-science-pack',  item = 'electric-mining-drill', groups = 2},
        {pack = 'metallurgic-science-pack', item = 'big-mining-drill',      groups = 1}}},

    -- 自动化专家：专精红瓶阶段。组装机1起步；练【红瓶】出整套早期自动化特产（组装机2/传送带/快爪/石炉）。
    {key = 'automator', starter = {{item = 'assembling-machine-1'}}, rewards = {
        {pack = 'automation-science-pack', item = 'assembling-machine-2', groups = 2},
        {pack = 'automation-science-pack', item = 'transport-belt',       groups = 1},
        {pack = 'automation-science-pack', item = 'fast-inserter',        groups = 1},
        {pack = 'automation-science-pack', item = 'stone-furnace',        groups = 2}}},

    -- 机器人专家：专精物流网络。被动供应箱起步；练【绿瓶】出机器人+收发箱+机器人平台，练【黄瓶】出进阶物流箱。
    {key = 'roboticist', starter = {{item = 'passive-provider-chest'}}, rewards = {
        {pack = 'logistic-science-pack', item = 'construction-robot',    groups = 2},
        {pack = 'logistic-science-pack', item = 'logistic-robot',        groups = 2},
        {pack = 'logistic-science-pack', item = 'roboport',              groups = 1},
        {pack = 'logistic-science-pack', item = 'storage-chest',         groups = 1},
        {pack = 'utility-science-pack',  item = 'active-provider-chest', groups = 1},
        {pack = 'utility-science-pack',  item = 'requester-chest',       groups = 1},
        {pack = 'utility-science-pack',  item = 'buffer-chest',          groups = 1}}},

    -- 军事专家：专精军事。机枪炮塔起步；练【黑瓶】出激光炮塔/坦克/火箭筒/更多机枪炮塔。
    {key = 'soldier', starter = {{item = 'gun-turret'}}, rewards = {
        {pack = 'military-science-pack', item = 'laser-turret',    groups = 2},
        {pack = 'military-science-pack', item = 'tank',            groups = 1},
        {pack = 'military-science-pack', item = 'rocket-launcher', groups = 1},
        {pack = 'military-science-pack', item = 'gun-turret',      groups = 2}}},

    -- 外星专家：专精四个外星瓶。铸造厂起步；四瓶各练出对应星球的招牌机器
    --   （火山→铸造厂、电浆星→电磁工厂、Gleba→农业塔、Aquilo→低温工厂）。
    {key = 'xeno', starter = {{item = 'foundry'}}, rewards = {
        {pack = 'metallurgic-science-pack',     item = 'foundry',               groups = 1},
        {pack = 'electromagnetic-science-pack', item = 'electromagnetic-plant', groups = 1},
        {pack = 'agricultural-science-pack',    item = 'agricultural-tower',    groups = 1},
        {pack = 'cryogenic-science-pack',       item = 'cryogenic-plant',       groups = 1}}},

    -- 博学专家：通才。组装机2起步；后 10 种瓶子（去掉红/绿）各练出该阶段的一组代表机器。
    {key = 'scholar', starter = {{item = 'assembling-machine-2'}}, rewards = {
        {pack = 'chemical-science-pack',        item = 'chemical-plant',              groups = 1},
        {pack = 'production-science-pack',      item = 'assembling-machine-3',        groups = 1},
        {pack = 'utility-science-pack',         item = 'roboport',                    groups = 1},
        {pack = 'space-science-pack',           item = 'space-platform-starter-pack', groups = 1},
        {pack = 'metallurgic-science-pack',     item = 'foundry',                     groups = 1},
        {pack = 'electromagnetic-science-pack', item = 'electromagnetic-plant',       groups = 1},
        {pack = 'agricultural-science-pack',    item = 'biochamber',                  groups = 1},
        {pack = 'cryogenic-science-pack',       item = 'cryogenic-plant',             groups = 1},
        {pack = 'promethium-science-pack',      item = 'biolab',                      groups = 1},
        {pack = 'military-science-pack',        item = 'artillery-turret',            groups = 1}}},
}

-- key → 定义。
M.by_key = {}
for _, def in ipairs(M.list) do M.by_key[def.key] = def end

-- 玩家当前选择的职业 key（未选 → 默认平民）。
function M.selected_key(player)
    return player and ((storage.player_class or {})[player.name] or M.DEFAULT)
end

-- 玩家当前职业定义（一定返回一个，兜底平民）。
function M.def_of(player)
    return M.by_key[M.selected_key(player)] or M.by_key[M.DEFAULT]
end

-- 玩家某瓶当前等级（= floor√经验；与 respawn_gifts.pack_level 同公式，解锁等级远小于满级故不需封顶）。
function M.pack_level(player, pack)
    return math.floor(math.sqrt(passives.exp_total_for_pack(player.index, pack)))
end

-- 该职业对该玩家是否已解锁（unlock 列表里每条都需满足；无 unlock = 人人可选）。
function M.unlocked(player, def)
    if not (def and def.unlock) then return true end
    for _, u in ipairs(def.unlock) do
        if M.pack_level(player, u.pack) < u.level then return false end
    end
    return true
end

-- 设定玩家选择的职业（校验 key 合法 + 已解锁 + 写存储；冷却/广播由 commands 处理）。
-- 返回 true=成功；'locked'=未解锁；nil=非法 key。
function M.set(player, key)
    local def = key and M.by_key[key]
    if not (player and def) then return nil end
    if not M.unlocked(player, def) then return 'locked' end
    storage.player_class = storage.player_class or {}
    storage.player_class[player.name] = key
    return true
end

return M
