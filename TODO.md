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

- [ ] **起始夜视仪**
  首次复活礼包里加夜视仪（`night-vision-equipment`）+ 对应电池/装备栏，保证能直接用。
  落点：`respawn_gifts.lua`（`on_first_respawn` 的护甲/起手物资段）。
  注意：要塞进护甲装备网格，确认护甲有格子。

- [ ] **角色等级 → 更好初始装备**
  以现有跨跃迁统计（`storage.player_stats`：online_minutes / deaths 等）派生一个"等级"，
  等级越高首发护甲/装备越好（梯度：基础护甲 → 模块护甲 → 动力护甲，逐级解锁夜视/电池/外骨骼）。
  落点：`respawn_gifts.lua` + 可能在 `player_stats.lua` 加 `level_of(name)` 工具。
  与"科技瓶经验发物资"并行，互不冲突。

---

## P2 — 世界变体扩展（复用 map_features / surface 的 remap 框架）

现有只有 `tile_remap`。按同样"源家族 → 目标 + mask + 非线性偏小概率"模式扩 3 类 remap。

- [ ] **ore_remap：矿物替换**
  某种原生矿 + 噪声 → 替换为另一种矿，小概率外星矿。
  复用 `tile_remap` 的 `mask=ore`（跟随原生矿分布）思路，但替换的是 resource 实体而非 tile。
  落点：`surface.lua`（滚定 + `PLANET_GEN`/`PLANET_SRC` 风格的源池）+ `map_features.lua`（区块内执行）+ `constants.balance` 加概率/`prob_ore_remap`。
  约束：别把保命矿（铁/铜）整片换没，沿用 tile_remap"不让星球缺资源"约束。

- [ ] **tree_remap：树木换皮**
  navis 原生树 → gleba / vulcanus 的树。比现有 `theme_trees`（只调色）更进一步，换实体原型。
  落点：`map_features.lua`（现有 `theme_trees` 旁加 `tree_remap`）+ `constants.balance`。
  源/目标用 `prototypes.entity` 过滤实际存在的树原型，防拼错空转。

- [ ] **障碍物 / 装饰 remap**
  母星石头 / 树 → 外星障碍（vulcanus 雷击木、gleba 树、巨型石等）。
  与 tree_remap 同框架，目标池扩到障碍类实体。落点同上。

> 三者都接 `surface.lua` 滚定 + debug 时给管理员打印（与现有变体一致），并进 P0 的"世界特征提示文字"。

---

## P2 — 事件世界扩展（复用 tick.run_world_events / WORLD_EVENTS）

现有 `raid/meteor/supply/coinfall`。新增两类，走同一分发表 + `storage.event_types.<name>` 开关。

- [ ] **敌方无人机来袭**
  每分钟事件：在远离出生点处刷敌对无人机/小队（spitter/小飞机式），向玩家推进。
  落点：`tick.lua`（`WORLD_EVENTS` 加 `drones`）+ `constants.ensure_defaults`（`event_types.drones=true`）。

- [ ] **重炮落点**
  每分钟事件：在玩家附近随机落点来一发重炮/陨石式爆炸（呼应 `feat_danger` 的重炮）。
  强度跟 `storage.event_intensity`。落点同上（`WORLD_EVENTS` 加 `barrage`）。

---

## P2 — 防御设施 / 测试箱周边（复用 map_features 战利品箱逻辑）

- [ ] **无限箱 + 守卫塔，可放远**
  在现有"测试箱"（永续无底）基础上，偶发生成一个**无限箱 + 守卫**的据点，刻意放离出生点远一点（给探索奖励）。
  守卫塔类型：激光炮塔 / 喷火炮塔（带燃料），force 设中立或敌对待定。
  落点：`map_features.lua`（战利品/测试箱段旁加 `feat_outpost`）+ `constants.balance` 概率。
  验收：能在远处区块刷出，守卫会攻击靠近的敌人/或作为挑战。

---

## P3 — 跃迁投票机制（新系统，改动较大，最后做）

让"何时跃迁"部分交给玩家，做成两个"会员/角色能力"（命名 `yueqian` / `tingliu`）。

- [ ] **`yueqian`：提前发起跃迁**
  当本轮已有 ≥ 1/5 在线玩家同意启动跃迁程序时，可触发跃迁。
  需要：投票状态 storage（`storage.warp_vote`）、命令/GUI 投票入口、达阈值调 `reset.reset()`。

- [ ] **`tingliu`：否决跃迁**
  当投否决的人数 > 存活玩家的 1/5 时，阻止/推迟本次跃迁。
  与 yueqian 共用投票状态，否决优先级高于同意。

  落点：新增 `scripts/warp_vote.lua`（生命周期 + 阈值判定）+ `commands.lua` 投票命令 + `gui.lua` 投票按钮 + `reset.lua` 接入触发 + `constants.ensure_defaults` 默认值。
  注意：阈值用"在线/存活玩家数"动态算；处理 0 人、单人、整除取整等边界。

---

## 备注

- 每改完 `.lua` 跑 `~/.local/bin/luac -p <file>` 体检。
- 新 storage 字段一律在 `constants.ensure_defaults` 加默认值（幂等、不覆盖老存档）。
- 校验原型名走正版 Steam 安装路径（见 memory: factorio-data-paths）。
