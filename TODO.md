# TODO / 开发计划

> 按"能复用现有系统 / 改动面 / 价值"排序。每条标注**落点文件**与**验收**。
> 总原则不变：大概率寻常、小概率新奇但有意义；噪声改原生、少手动 stamp；storage 默认值统一走 `constants.ensure_defaults`。

---

## P0 — 文案与可发现性（改动小、收益大，先做）

玩法已经很多，但玩家"看不见"。这一档纯文字/GUI，无逻辑风险。

- [x] **教程文案接真实 storage 数据**
  `wn.tutorial` 改成带参数 `__1__`=起步分钟、`__2__`=飞船寿命；`commands.lua:tutorial_cmd` 传
  `storage.warp_initial_minutes` / `storage.platform_lifetime`。修了写死的"5 次跃迁"（实际默认 10）。
  验收：`/c storage.platform_lifetime=N` 后教程数字跟着变。

- [x] **教程覆盖所有玩法（保持模糊，不写细节/公式）**
  口径：教程只点到玩法存在，**不**列具体世界特征（染地/事件…）、**不**写公式或经验明细，让玩家自己探索。
  中文补齐到英文版水平：加死亡→生命上限技能行；世界段只说"地图/矿藏/世界特征都不一样，自己探索"。

- [x] **命令说明覆盖所有命令**
  每条命令本就有 `help` 字符串（Factorio 内置 `/help <cmd>` 可查）；教程的常用指令清单补上会员
  `/huiyuan`、踢人 `/tichu`（en: `/member`/`/kickout`）。玩家可见命令现都能查到。

- [x] **更多世界特征提示文字（"文字游戏"）**
  注意：`gui.lua:84` 明确注释"星系词条已删除，让玩家自己探索"——故**不**加回 GUI 词条。
  改为在教程里点明"有随机世界特征（染地/外星地形/危险敌群/空投），自己去探索"。
  若以后想要每轮氛围提示，可在 `surface.lua` 滚定变体后做一条**进入星球时的一次性提示**（不常驻 UI）。

---

## P1 — 起始装备 / 跨跃迁进度（复用 respawn_gifts + passives）

- [x] **起始夜视仪 + 等级驱动护甲（合并实现）**
  起手护甲随人物等级（=floor(√在线分钟)=开局金币）成长，落点 `respawn_gifts.lua:give_starter_armor`：
  - 固定 1 个机器人端口(2x2) + 1 夜视仪(2x2) = 8 格，**无电池**；其余格全塞 1x1 个人太阳能板。
  - 太阳能板数 = min(等级, 92)；护甲品质自动取装得下的最小品质（品质放大网格，容量兜底用真实 `grid.width*height-8`）。
  - 品质网格容量(扣8)：normal 17 / uncommon 28 / rare 41 / epic 56 / legendary 92。
    → 升绿甲在 **18 级**（normal 实容 17，非用户估的 16）；**92 级**装满 92 板（非 96）。
  - 等级 ≥100 起逐步升太阳能板品质：192 全绿、292 全蓝、392 全紫、492 全橙(传说)（线性过渡，`solar_quality_queue`）。

---

## P2 — 世界变体扩展：同类实体替换（每世界概率规则）

把整片原生实体**整体换成另一种【同类】原型**（不混类）。每世界独立滚：大概率不换、换则全星统一一种目标，
debug 打印给管理员。**不做 ore_remap（矿石不换）。**

- [ ] **tree_remap：树换树**
  本世界以一定概率把所有原生【树】替换成另一种树原型（nauvis/gleba/vulcanus 等树）。同类换同类。
  滚定：`surface.lua` 存 `storage.tree_remap[星球] = 目标树名`（无则不换）。
  执行：`map_features.lua` 区块内 `find_entities_filtered{type='tree'}`，逐棵在原位换成目标树（`can_place` 才换）。
  目标池用 `prototypes.entity` 过滤实际存在的树名，防拼错空转。比 `theme_trees`（只调色）更进一步。

- [ ] **obstacle_remap：障碍换障碍**
  本世界以一定概率把所有原生【障碍】（石/巨石）替换成另一种障碍原型（huge-volcanic-rock、外星石/树桩等）。同类换同类。
  滚定：`surface.lua` 存 `storage.obstacle_remap[星球] = 目标障碍名`。
  执行：`map_features.lua` 区块内 `find_entities_filtered{type='simple-entity'}`（母星石头）逐个原位替换。
  目标池同样用 `prototypes.entity` 过滤。

> 两者都接 `surface.lua` 滚定 + `constants.ensure_defaults` 加 storage 表/概率 + debug 打印（与现有变体一致）。
> 概率曲线沿用"大概率不出现、出现则温和"原则。

---

## P2 — 事件世界扩展（复用 tick.run_world_events / WORLD_EVENTS）

现有 `raid/meteor/supply/coinfall`。新增两类，走同一分发表 + `storage.event_types.<name>` 开关。

- [x] **敌方无人机来袭** (`drones`)
  在玩家附近(攻击射程内)投放敌方战斗机器人 `defender`/`distractor`/`destroyer`(enemy force)，
  靠自身 AI 自动攻击玩家方、寿命到自然消失。**不设 owner/target**(运行时只读) → 无崩溃。
  落点 `tick.lua:WORLD_EVENTS.drones` + `constants` `event_types.drones=true` + `surface.lua` 候选池。

- [x] **重炮落点** (`barrage`)
  玩家周围 20–60 格落几发真炮弹 `artillery-projectile`(从上方飞入)，范围伤害+爆炸(会砸自家建筑)。
  数量随 `event_intensity` × 危险度。落点同上(`WORLD_EVENTS.barrage`)。

---

## P2 — 防御设施 / 测试箱周边（复用 map_features 战利品箱逻辑）

- [x] **无限箱 + 守卫塔据点** (`feat_outpost`)
  距出生点 >300 格、约 0.4%/区块罕见生成。组成：enemy `substation`+`electric-energy-interface`
  (满缓冲+发电)子电网 → 给 enemy `laser-turret` 供电；enemy `flamethrower-turret`(灌原油)/`gun-turret`(填弹)；
  neutral `infinity-chest` 奖励。守卫全在供电半径内、数量随离中心距离 3→9 增长。
  落点 `map_features.lua:feat_outpost` + 接入 `M.generate`。
  ⚠️ 待游戏内验证：enemy 激光塔在 enemy 子电网下是否真能持续开火。

---

## P3 — 跃迁投票机制（新系统，改动较大，最后做）

让"何时跃迁"部分交给玩家，做成两个"会员/角色能力"（命名 `yueqian` / `tingliu`）。

- [x] **跃迁投票（命令式，无 GUI）**
  `/yueqian`(=`/warp`) 投同意、`/tingliu` 投反对；不投=忽视。票存 `storage.warp_vote[名]='agree'|'oppose'`，
  reset 时清空。每次投票后 `warp_vote_eval`：净同意(同意−反对) > ceil(在线人数 / `storage.warp_vote_divisor`[默认5=1/5])
  → 倒计时 −1 分钟 + **所有投同意者死亡**(传回母星，复活等待 90 秒) + 清空票(需重投再推)。剩余 ≤3 分钟不推。
  落点 `commands.lua`(投票命令+结算) + `constants`(默认值) + `reset.lua`(清空) + locale(`warp-vote-status/pass`)。

---

## 备注

- 每改完 `.lua` 跑 `~/.local/bin/luac -p <file>` 体检。
- 新 storage 字段一律在 `constants.ensure_defaults` 加默认值（幂等、不覆盖老存档）。
- 校验原型名走正版 Steam 安装路径（见 memory: factorio-data-paths）。
