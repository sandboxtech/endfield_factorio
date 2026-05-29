# endfield_factorio 场景结构

异星工厂 (Factorio 2.0 + Space Age) 自定义场景。核心玩法：每隔约 1 小时触发一次"跃迁"——
所有星球清空重建、玩家死亡复活、飞船保留有限轮次。**跨跃迁的永久进度**有两条：

1. **科技瓶经验** → 下次开局直接发该瓶对应的代表物资（带得越多、开局越富）。
2. **角色技能**（边玩边练）→ 手搓/移动/挖矿越多越快、死亡越多血上限越高。

每一轮的各星球还会随机出**世界变体**（地表换皮 / 染地 / 危险敌群 / 每分钟事件 / 战利品风格…），
追求"大概率寻常、小概率新奇但有意义"，让反复跃迁不重样。

## 顶层文件

- `control.lua`：场景入口，按顺序 require 各子模块；`on_init` 执行第一轮跃迁、`on_configuration_changed` 兜底老存档迁移，二者的 storage 默认值统一经 `constants.ensure_defaults`（亦在每轮 `reset` 开头调用，幂等）。
- `info.json` / `description.json`：场景元数据。
- `locale/`：本地化字符串（`wn.*` 键由代码引用，en + zh-CN）。

## scripts/

| 文件 | 职责 |
| --- | --- |
| `constants.lua` | 全局常量：tick 换算、品质→经验倍率、12 种科技瓶顺序；`balance` 表集中各世界变体的出现概率/权重（一眼看全、统一调）；`ensure_defaults()` 设 storage 默认值，是唯一会写 storage 的函数。 |
| `util.lua` | 通用工具：`readable`、`random_exp` 指数分布、`random_nature`、`mostly_normal`、`evo_biter`（按进化度挑虫）。 |
| `events.lua` | **事件总线**：同一事件多处 `events.on()` 订阅、内部只 `script.on_event` 注册一次再分发 → 避免单事件被多处注册互相覆盖。可能被多方监听的事件都走它。 |
| `noise.lua` | 2D simplex + 分形多倍频 + 种子派生变换（旋转/拉伸/缩放）。供运行时手动铺设噪声地物（移植自 ComfyFactorio）。 |
| `players.lua` | 玩家生命周期（创建/加入/离开/复活/死亡）；**所有死亡一律回母星 nauvis 出生点复活**（`place_on_nauvis`，不再随机散落各星球）并 chart；`print_inspection` 面板。 |
| `respawn_gifts.lua` | 每世界首次复活时发：起手护甲 + 起手物资 + **每瓶 2 种代表物资**（随经验、按堆叠封顶 5 组）+ **开局金币**(`√在线分钟`)。 |
| `market.lua` | 母星出生点的**一个**金币市场（不可摧毁/挖取）。`surface.lua` 在 clear 结算后放置。 |
| `passives.lua` | **动作即时升级的 4 技能**：手搓/移动(封顶 +100%)/挖矿/生命上限。曲线 -50% 下限、log 缓升。独占 craft/mine/changed_position/died 事件。 |
| `science_exp.lua` | `collect`（跃迁结算在线玩家，不移除）/ `settle`（提前结算：换经验**并移除**整组瓶子，防跃迁重复）/ `preview`（预览）。经验按**玩家名**存 `storage.science_exp`。 |
| `research.lua` | 研究含 `-science-pack` 名（非 trigger）的科技 → 本轮倒计时 +1 小时并公告。 |
| `map_features.lua` | **每轮地图风味**（手动放置原生做不到的东西）：`M.knobs()` 本轮整局气质连续旋钮；跨星球 `EXOTIC` 异物（稀疏 simplex 散布）；`theme_trees` 改原生树颜色/灰度（连续插值）；**4 类独立战利品箱**（钢=材料 / 铁=设备 / 木=宝箱，各按 `loot_style` 密度滚、带品质）+ 罕见**永续箱**（infinity 无底，不可开不可拆可摧毁，周围放 enemy 守卫）+ 远处**防御据点** `feat_outpost`（无限箱 + enemy 子电网 substation/供电接口 + 激光/喷火/机枪守卫塔）；`feat_danger` 危险敌群（独立开关 worm/巢/机枪炮塔+弹/地雷/重炮+弹，force=enemy）；`feat_wrecks` 飞船残骸障碍（仅 25% 世界、密度 random³ 偏小，独立于危险世界，见 `storage.wreck_density`）。`M.generate` 逐区块调用。 |
| `world_fx.lua` | 事件驱动的世界效果（经 `events` 总线）的**注册表**：`register(name,event,run)` 每项带全局开关 `storage.world_fx[name]`（默认开，`/c storage.world_fx.xxx=false` 禁用）。现有 **复制虫**(`replicant`)——玩家建筑被虫破坏时原地冒虫（呼应 Comfy infested）。加新 fx 只动本文件 + `ensure_defaults` 开关列表。 |
| `surface.lua` | 跃迁后逐星球生成：原生 autoplace 调参 + **气候噪声偏置**（`control:moisture/aux/temperature:bias` 修改原生而非覆盖）+ **世界变体**滚定（染地/tile 替换/危险/事件/战利品风格）+ 圆形虚空边界；逐区块应用 tile 替换与染地精灵；母星放市场。各星球资源/自然/气候由声明式 `PLANET_GEN` 表驱动。debug 时向**管理员**打印每次生成的属性。 |
| `reset.lua` | 跃迁主流程：收集经验 → 杀玩家 → 清星球(异步) → 重置科技 → 随机参数 → 清地图标记。 |
| `tick.lua` | `on_gui_click` 与 `on_nth_tick(3600)` 的**唯一注册点**：每分钟在线采样 + 给在线玩家各 +1 金币 + 倒计时/提醒 + **事件世界**(`run_world_events` 按 `WORLD_EVENTS` 分发表：raid/meteor/supply/coinfall/drones/barrage)。 |
| `player_stats.lua` | 行为统计存储（craft/mining/move/deaths/online_minutes，按玩家名，跨跃迁累积）；递增在 `passives.lua`。 |
| `rocket.lua` | 发射火箭惩罚：每次 `on_rocket_launched` 令本轮 `warp_hours` -1 分钟，公告 + 打印载荷。 |
| `commands.lua` | 命令：管理员 `/reset`/`/players_gui`/`/exp_clear`/`/gen`(=`/shengcheng`,查生成)/`/fixstats`(=`/xiufutongji`)；玩家 `/inspect`(=`/chakan`)、`/preview`(=`/yulan`)、`/tutorial`(=`/jiaocheng`)、`/suicide`(=`/zisha`)；**跃迁投票** `/warp`(=`/yueqian` 同意)/`/tingliu`(反对) → `warp_vote_eval` 结算；会员 `/member`(=`/huiyuan`)/`/unmember`(=`/chehuiyuan`)/`/kickout`(=`/tichu`)。自定义指令使用时公告全体。 |
| `gui.lua` | 左上角 HUD：轮次按钮、星系词条、🧪 面板、在线名册、管理员按钮。 |

## 世界变体系统（`surface.lua` + `map_features.lua` + `noise.lua` + `tick.lua` + `world_fx.lua`）

设计原则：**用噪声修改 2.0 原生生成，不用手动 stamp 覆盖**（原生地貌更自然）；每个变体大概率不出现、
小概率温和、极小概率明显（非线性曲线）；可调常量见下。每星球每轮独立滚，互不绑定。

- **整局气质旋钮** `M.knobs()`：`verdancy/rockiness/danger/riches/exotic`，由 `storage.run` 确定性派生，
  全局共用 → 气质一致。`danger` 与 `exotic` 正相关（诡异世界更危险）。
- **原生调参**（`surface.lua`）：`set_resource`（丰度/面积/频率 1~9 档）、`nature_by_knob`（树/石/草密度随气质、
  规模"多半小偶尔大"）、`bias_climate`（`control:moisture/aux/temperature:bias` 偏置整星干湿冷热 → 原生自然铺开）。
- **染地世界** `ground_tint`：地面层盖半透明染色精灵（`rendering.draw_sprite`，不改地块），alpha 立方曲线 → 多半淡染、极少浓染（infested 感）。
- **tile 替换**：每世界 1~N 条规则 `源家族 → 目标 tile + mask`。
  - 源 `PLANET_SRC[星球]`：只取该星实际存在的 tile 子家族（否则空转）。
  - 目标白名单 `TILE_CLASS` 四类：`water`(常规水) / `ground`(自然地表) / `exotic`(岩浆·油海·氨海·虚空·太空) / `artificial`(混凝土系+9 色套色+铺路/landfill/地基)。`valid_pools` 按 `prototypes.tile` 过滤拼错名。
  - mask：`all`(整片，仅安全自然：水→可泵水、地→任意地) / `noise`(平滑成片，**exotic 仅此可选**) / `tree`/`rock`/`ore`(跟随原生树/石/矿分布，**artificial 仅 ore 可选**)。规则数与覆盖面非线性偏小。
  - 约束：整片替换不让星球缺资源；exotic/artificial 只部分替换（原 tile 仍保留）。exotic 出现率全星统一（`tile_mask_all` × `tile_to_exotic`），母星不额外加成。
- **危险世界** `danger_theme[星球]`：各敌人类型**独立开关**（worm/spawner/机枪炮塔+弹/地雷/重炮+弹）+ 机枪弹种(随危险度) + 35% 复制虫。`map_features.feat_danger` 远离出生点采样放置（force=enemy）。（`feat_wrecks` 残骸已独立成自己的 25% 世界滚定，不再绑危险世界。）
- **每分钟事件世界** `event_world[星球]`（`tick.run_world_events`）：`raid` 空降虫 / `meteor` 矿石陨石雨 / `supply` 物资空投 / `coinfall` 金币雨 / `drones` 敌方战斗机器人(defender/distractor/destroyer) / `barrage` 重炮落点(artillery-projectile，会砸自家建筑)。
- **战利品风格** `loot_style[星球]`：每星独立滚 4 类箱(材料/设备/宝/永续)各自密度(random²)；某类某区块出现率 = 密度 × `LOOT_FREQ` × `loot_density`。
- **障碍互换** `obstacle_remap[星球]`（原 `tree_remap` 已并入）：把本星【现地所有带碰撞盒障碍：树/石/遗迹/冰山/叠层岩…】(`type=tree/simple-entity`)在**噪声大团**内**跨类**原位替换——树↔石↔遗迹皆可，不看脚下 tile。**大概率(85%)整片统一换成同一种**(单一主题、协调)，小概率(15%)每个各自随机换成另一种(跨类大杂烩)。源天然自限(`find` 只命中本星现有实体)、目标跨星球。目标池 `OBSTACLE_TARGETS`(树+石+fulgora 遗迹) 运行时按 `entity_ok` 校验(无效**报告管理员**并剔除)。见 `map_features.feat_entity_remap`。**不做矿石替换。**

## 关键 storage 字段

- `storage.run` / `run_start_tick` / `warp_hours`：轮次序号 / 本轮起始 / 本轮总时长。
- `storage.platform_age[idx]` / `platform_lifetime`：飞船经历跃迁数 / 上限。船名前缀显示**剩余命数**(`[item=parameter-N][virtual-signal=signal-heart]` = 还剩 N 命 = `lifetime-age+1`)，每跃迁剥旧前缀换新；归零(`age>lifetime`)即摧毁。
- `storage.science_exp[玩家名][瓶名] = exp`：每瓶累计经验（12 key，不分品质）。
- `storage.player_stats[玩家名]`：行为统计（驱动技能 + 金币）。
- `storage.last_respawn_run[idx]`：上次复活的 `run`，判"本世界是否首次复活"。
- 地图：`storage.radius / radius_min / radius_max / radius_of / difficulty / *_multiplier / local_specialty_multiplier`。
- 世界变体（每星球，每轮重滚）：`ground_tint / tile_remap / danger_theme / event_world / loot_style / obstacle_remap({seed,threshold[,to]}) / wreck_density`（`tree_remap` 已并入 `obstacle_remap`，仅兼容保留）。
- **可调常量**（默认值由 `constants.ensure_defaults` 设 —— on_init / on_configuration_changed / 每轮 reset 都调用，幂等不覆盖；游戏内 `/c storage.xxx=N` 动态调）：
  - `debug`(默认 true，向管理员打印每次生成属性)
  - 概率乘数（0=关）：`prob_ground_tint / prob_tile_remap / prob_obstacle_remap / prob_danger / prob_event`（`prob_tree_remap` 已并入障碍）
  - 强度：`danger_density`(敌人/残骸密度) / `loot_density`(战利品箱全局密度) / `event_intensity`(事件落点) / `tile_remap_rules`(最多规则数)
  - `storage.world_fx.<name>`(默认 true)：事件驱动效果总闸，false 全局禁用（如 `replicant` 复制虫）
  - `storage.event_types.<raid/meteor/supply/coinfall/drones/barrage>`(默认 true)：每分钟事件世界各类型开关，`/c` 设 false 即排除某类型

## 数据流速览

```
reset.reset():
    science_exp.collect(每在线玩家) -> storage.science_exp（扫背包瓶子累加，不移除）
    杀/清玩家、清星球(异步)、force.reset(科技清零)、随机污染/小行星参数、清地图标记
    passives.apply(在线玩家)

on_surface_cleared（每星球，clear 结算后）:
    随机昼夜/半径/资源档位 + 气候偏置(bias_climate) + 原生 autoplace 调参
    滚世界变体: ground_tint / tile_remap / danger_theme / event_world / loot_style / obstacle_remap（debug 打印给管理员）
    母星: market.place_on_nauvis()

on_chunk_generated（每区块）:
    圆外铺虚空 -> map_features.generate（异物/障碍互换/树调色/战利品箱/危险敌群/残骸）
    -> 应用 tile 替换（按 mask）-> 画染地精灵

on_player_respawned / on_player_created: passives.apply；本世界首次 -> respawn_gifts.on_first_respawn
on_pre_player_left_game: science_exp.settle（离线前结算）-> 杀角色
on_nth_tick(3600): 在线采样 + 各 +1 金币 + 倒计时/提醒 + run_world_events（事件世界）
on_entity_died（world_fx 经总线）: 复制虫世界里玩家建筑被虫毁 -> 原地冒虫
```

## 跨跃迁进度

### 1. 科技瓶经验 → 开局直接发物资（`respawn_gifts`）

跃迁前背包里的科技瓶由 `science_exp.collect` 按瓶累加经验（也可玩家 `/settle` 提前结算并消耗）。
开局**直接**发每瓶对应的 **2 种代表物资**（`M.pack_gifts`）：

- 单种数量 = `floor(堆叠数 × 5 × √(exp/CAP_EXP))`，封顶 5 组；所有物品在 `CAP_EXP` 同时触顶。
- 🧪 面板每瓶一行：`瓶图标 经验N · 右侧=下局会发的 2 种物资×数量`。

### 2. 角色技能（`passives.lua`，边玩边练）

| 动作 | 技能 | 曲线 |
| --- | --- | --- |
| 手搓 | 手搓速度 | -50% 起，log 缓升 |
| 移动 | 移动速度 | 同上，封顶 +100% |
| 采矿/拆除 | 挖矿速度 | 同上 |
| 死亡 | 生命上限 | 死越多血上限越高 |

## 金币经济

来源：开局 `floor(√在线分钟)` + 每分钟在线 +1 +（罕见 coinfall 事件）。用途：母星金币市场买普通装备零件。
装备是个人增益，不替代"建工厂"核心循环。

## 星球资源档位（`surface.lua`）

每种资源的丰度/面积/频率各抽一个 1~9 整数 N：丰度 `3^(N-7)`、面积 `1.5^(N-6)`、频率 `1.3^(N-5)`，
再乘全局 `richness_multiplier`(默认 8)/`size_multiplier`(2)/`frequency_multiplier`(0.5)。**rail world 基线**：矿少而大且富（频率减半、面积/丰度翻倍），逼玩家修铁路连远矿。
地方特产（铀/钨/废料/gleba 石/aquilo 流体）用 `local_specialty_multiplier` 额外压低丰度。圆半径外铺虚空。
