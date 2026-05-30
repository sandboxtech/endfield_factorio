# endfield_factorio 场景结构

异星工厂 (Factorio 2.0 + Space Age) 自定义场景。核心玩法：每隔一段时间（起步约 `warp_initial_minutes`(默认30) 分钟，随解锁新科技瓶延长、发射火箭/投票/被杀缩短）触发一次"跃迁"——
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
| `players.lua` | 玩家生命周期（创建/加入/离开/复活/死亡）。`kill_player`：先把玩家移到**当前所在表面**的出生点再杀死（**尸体/货物留在当前星球**，杜绝"外星捡货→自杀带回母星"）；**复活落点** `place_on_respawn` 去玩家的**复活星球** `storage.respawn_surface[名]`（前往某星球时由命令记下；该星球 surface 不存在则回**母星**），`place_on_surface` 仅**异步**请求生成区块、不强制。`print_inspection` 面板。 |
| `respawn_gifts.lua` | 每世界首次复活时发：起手护甲 + 起手物资 + **每瓶 2 种代表物资**（数量 = `ceil(堆叠数 × 等级/100)`，等级 = `floor(√exp)`，封顶 `MAX_GROUPS=10` 组）+ **开局金币**(`√在线分钟`)。 |
| `market.lua` | **5 个**金币市场（母星 + 其余 4 个星球，凡 `PLANET_GEN` 有配置，内容相同，不可摧毁/挖取）。**惰性放置**：由 `surface.lua` 的 `on_chunk_generated` 在**出生区块自然生成时**（玩家复活/传送到该星触发）调一次，**不强制生成区块**；每轮每星一次（`storage.market_run` 记录，成功才记）。同时做**出生点保底**：中心抽 16 点，过半不可通行(`collides_with('player')`：水/熔岩/油海/虚空…)就铺 64×64 精炼混凝土。 |
| `passives.lua` | **动作即时升级的 4 技能**：手搓/移动(封顶 +100%)/挖矿/生命上限。曲线 -50% 下限、log 缓升。独占 craft/mine/changed_position/died 事件。 |
| `science_exp.lua` | `collect`（跃迁结算在线玩家**整组**科技瓶 = `floor(数量/堆叠) × 品质系数`，不移除瓶子）/ `preview`（同算法预览，不写入）。经验按**玩家名**存 `storage.science_exp`。（提前结算 `/settle` 已移除：只有跃迁才结算。） |
| `research.lua` | 研究含 `-science-pack` 名（非 trigger）的科技 → 本轮倒计时延长 `warp_extend_minutes[瓶]`(默认60) 分钟、公告、并 `gui.refresh_countdown()` 立刻刷新头顶倒计时。 |
| `map_features.lua` | **每轮地图风味**（手动放置原生做不到的东西）：`M.knobs()` 本轮整局气质连续旋钮；跨星球 `EXOTIC` 异物（稀疏 simplex 散布）；`theme_trees` 改原生树颜色/灰度（连续插值）；**4 类独立战利品箱**（钢=材料 / 铁=设备 / 木=宝箱，各按 `loot_style` 密度滚、带品质）+ 罕见**永续箱**（infinity 无底，不可开不可拆可摧毁，周围放 enemy 守卫）+ 远处**防御据点** `feat_outpost`（无限箱 + enemy 子电网 substation/供电接口 + 激光/喷火/机枪守卫塔）；`feat_danger` 危险敌群（独立开关 worm/巢/机枪炮塔+弹/地雷/重炮+弹，force=enemy）；`feat_wrecks` 飞船残骸障碍（仅 25% 世界、密度 random³ 偏小，独立于危险世界，见 `storage.wreck_density`）。`M.generate` 逐区块调用。 |
| `world_fx.lua` | 事件驱动的世界效果（经 `events` 总线）的**注册表**：`register(name,event,run)` 每项带全局开关 `storage.world_fx[name]`（默认开，`/c storage.world_fx.xxx=false` 禁用）。现有 **复制虫**(`replicant`)——玩家建筑被虫破坏时原地冒虫（呼应 Comfy infested）。加新 fx 只动本文件 + `ensure_defaults` 开关列表。 |
| `surface.lua` | 跃迁后逐星球生成：原生 autoplace 调参 + **气候噪声偏置**（`control:moisture/aux/temperature:bias` 修改原生而非覆盖）+ **世界变体**滚定（染地/tile 替换/危险/事件/战利品风格/障碍/流体）+ 圆形虚空边界；逐区块应用 tile 替换与染地精灵；**逐区块惰性放各星球市场**（出生区块生成时）。各星球资源/自然/气候由声明式 `PLANET_GEN` 表驱动。debug 时向**管理员**打印每次生成的属性。 |
| `reset.lua` | 跃迁主流程：飞船老化(命数前缀) → 收集经验/存排行榜 → 清理不活跃玩家 → 杀玩家(尸体留当地) → 广播结算 → 清星球 → 重置科技 → **解锁所有星球+发现科技** → 飞船回母星轨道+**清陨石** → 随机参数。 |
| `tick.lua` | `on_gui_click` 与 `on_nth_tick(3600)` 的**唯一注册点**：每分钟在线采样 + 给在线玩家各 +1 金币 + 倒计时/提醒 + **事件世界**(`run_world_events` 按 `WORLD_EVENTS` 分发表：raid/meteor/supply/coinfall/drones/barrage/tech；每分钟全服 `event_chance` 掷一次、命中挑一个事件世界玩家触发其星球事件)。 |
| `player_stats.lua` | 行为统计存储（craft/mining/move/deaths/online_minutes，按玩家名，跨跃迁累积）；递增在 `passives.lua`。 |
| `rocket.lua` | 发射火箭惩罚：每次 `on_rocket_launched` 令本轮 `warp_hours` -1 分钟，公告 + 打印载荷。 |
| `commands.lua` | 命令：管理员 `/reset`/`/players_gui`/`/exp_clear`/`/gen`(=`/shengcheng`)/`/fixstats`(=`/xiufutongji`)；玩家 `/inspect`(=`/chakan`)、`/preview`(=`/yulan`)、`/lastrank`(=`/paihang`/`/排行`，看上个世界经验排行)、`/tutorial`(=`/jiaocheng`)、`/suicide`(=`/zisha`)、**前往星球** `/nauvis`/`/vulcanus`/`/gleba`/`/fulgora`/`/aquilo`(要求鼠标/背包/物流/弹药四区为空)；**跃迁投票** `/warp`(=`/yueqian` 同意)/`/tingliu`(反对) → `warp_vote_eval`：净同意 ≥ ceil(在线/`warp_vote_divisor`) 即过，**把本世界倒计时直接设为剩余 `warp_vote_target_minutes`(默认5) 分钟、不杀玩家**（已不足该值则不动）；会员 `/member`(=`/huiyuan`)/`/unmember`(=`/chehuiyuan`)/`/kickout`(=`/tichu`)。自定义指令使用时公告全体。 |
| `gui.lua` | 左上角 HUD：轮次按钮、跃迁倒计时、🧪 角色面板（含每瓶开局奖励）、在线名册；屏幕中央临时弹窗 `show_popup`(教程/inspect/preview/排行/gen 共用)；教程 `show_tutorial`（会员指令段仅会员/管理员可见）。 |

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
- **事件世界** `event_world[星球]`：每星球每轮 **10%**(`balance.event.base 0.1 × prob_event`) 成为事件世界，命中则从下列类型**按权重抽一个**存入（**至多一种**；权重 `balance.event.weights`：drones=0.3，余默认1）。触发见 `tick.run_world_events`：每分钟先掷全局 `event_chance`(默认0.5) 决定**全服**是否发生，命中则随机挑一个"身处事件世界星球的在线玩家"，触发其星球的事件**一次**。类型：
  - `raid` 空降虫 / `meteor` 矿石陨石雨 / `supply` 物资空投 / `coinfall` 金币雨 / `drones` 敌方战斗机器人(defender/distractor/destroyer) / `barrage` 重炮落点(artillery-projectile，会砸自家建筑)。
  - `tech` **科技世界**（也是事件世界的一种，效果对**全 force**）：从**所有科技**(排除 4 个星球发现科技)**随机抽一个，不看是否已研究**——已研究则以 `tech_world_lose_chance`(默认0.25) **失去**(`researched=false`)，未研究则以 `tech_world_gain_chance`(默认0.5) **得到**(`researched=true`)，全服广播 `tech-gain`/`tech-lose`。脚本改 `researched` 是 `by_script` 事件，`research.lua` 早退 → 不会顺带改跃迁倒计时。
  - 另：**玩家亲手消灭虫巢**(`tick.lua` 的 spawner `on_entity_died`)有 **1%** 概率触发一次"得到科技"(同 grant 逻辑)。
  - 注意：染地/地表替换/危险/障碍/流体是**各自独立**的非事件世界变体（见下），可与事件世界叠加；事件世界本身只有一种、特征是"每分钟可能发生一些事情"。
- **战利品风格** `loot_style[星球]`：每星独立滚 4 类箱(材料/设备/宝/永续)各自密度(random²)；某类某区块出现率 = 密度 × `LOOT_FREQ` × `loot_density`。
- **障碍互换** `obstacle_remap[星球]`（原 `tree_remap` 已并入）：把本星【现地所有带碰撞盒障碍：树/石/遗迹/冰山/叠层岩…】(`type=tree/simple-entity`)在**噪声大团**内**跨类**原位替换——树↔石↔遗迹皆可，不看脚下 tile。**大概率(85%)整片统一换成同一种**(单一主题、协调)，小概率(15%)每个各自随机换成另一种(跨类大杂烩)。源天然自限(`find` 只命中本星现有实体)、目标跨星球。目标池 `OBSTACLE_TARGETS`(树+石+fulgora 遗迹) 运行时按 `entity_ok` 校验(无效**报告管理员**并剔除)。见 `map_features.feat_entity_remap`。**不做固体矿替换。**
- **流体资源互换** `fluid_remap[星球]`（小概率激活）：把产流体的资源(原油/锂卤水/氟喷口/硫酸喷泉)变成**随机另一种喷口**，二选一门控——`{p}` 每喷口各自以概率 p 突变(零星，p∈[0.08,0.88] 每星每世界不同) 或 `{seed,threshold}` noise 大团内整体突变(成片)。源自动识别(`type=resource` 且开采产物含 `fluid`，固体矿/废料不动)；含量按目标喷口 `minimum_resource_amount × 1.5~5.5` 生成。同片油田可能混出多种。见 `map_features.feat_fluid_remap`。

## 关键 storage 字段

- `storage.run` / `run_start_tick` / `warp_hours`：轮次序号 / 本轮起始 / 本轮总时长。
- `storage.platform_age[idx]` / `platform_lifetime`：飞船经历跃迁数 / 上限。船名前缀显示**剩余命数**(`[item=parameter-N][virtual-signal=signal-heart]` = 还剩 N 命 = `lifetime-age+1`)，每跃迁剥旧前缀换新；归零(`age>lifetime`)即摧毁。
- `storage.science_exp[玩家名][瓶名] = exp`：每瓶累计经验（12 key，不分品质）。
- `storage.player_stats[玩家名]`：行为统计（驱动技能 + 金币）。
- `storage.last_respawn_run[idx]`：上次复活的 `run`，判"本世界是否首次复活"。
- `storage.last_leaderboard` / `last_leaderboard_run`：上个世界经验排行榜（`/lastrank` 查）及其世界号。
- `storage.market_run[星球]`：该星本轮市场已放置的 `run`（惰性放置去重）。
- `storage.warp_vote[玩家名]`：跃迁投票（`agree`/`oppose`，跃迁/通过后清空）。
- 地图：`storage.radius / radius_min / radius_max / radius_of / difficulty / *_multiplier / local_specialty_multiplier`。
- 世界变体（每星球，每轮重滚）：`ground_tint / tile_remap / danger_theme / event_world / loot_style / obstacle_remap({seed,threshold[,to]}) / fluid_remap / wreck_density`（`tree_remap` 已并入 `obstacle_remap`，仅兼容保留）。
- **可调常量**（默认值由 `constants.ensure_defaults` 设 —— on_init / on_configuration_changed / 每轮 reset 都调用，幂等不覆盖；游戏内 `/c storage.xxx=N` 动态调）：
  - `debug`(默认 true，向管理员打印每次生成属性)
  - 概率乘数（0=关）：`prob_ground_tint / prob_tile_remap / prob_obstacle_remap / prob_fluid_remap / prob_danger / prob_event`（`prob_tree_remap` 已并入障碍）
  - 强度：`danger_density`(敌人/残骸密度) / `event_intensity`(事件落点) / `tile_remap_rules`(最多规则数)
  - 战利品密度（**全局乘数 × 各类乘数，相乘**）：`loot_density`(全局) × `loot_density_<material/equipment/treasure/perp/outpost>`(各类，默认1)
  - 上限钳（防 /c 填超大数一 tick 卡死）：事件落点 `EVENT_MAX_SPAWN=50`、危险刷怪 `DANGER_MAX_PER_CHUNK×4`、tile 规则 `≤20`
  - `storage.world_fx.<name>`(默认 true)：事件驱动效果总闸，false 全局禁用（如 `replicant` 复制虫）
  - `storage.event_types.<raid/meteor/supply/coinfall/drones/barrage/tech>`(默认 true)：事件世界各类型开关，`/c` 设 false 即排除某类型
  - `storage.event_chance`(默认0.5)：每分钟全服发生一次事件的概率 / `storage.tech_world_lose_ratio`(默认0.25)：tech 事件触发时"失去科技"的概率（其余为得到）

## 数据流速览

```
reset.reset():
    science_exp.collect(每在线玩家) -> storage.science_exp（扫背包瓶子累加，不移除）
    杀/清玩家、清星球(异步)、force.reset(科技清零)、随机污染/小行星参数、清地图标记
    passives.apply(在线玩家)

on_surface_cleared（每星球，clear 结算后）:
    随机昼夜/半径/资源档位 + 气候偏置(bias_climate) + 原生 autoplace 调参
    滚世界变体: ground_tint / tile_remap / danger_theme / event_world(含 tech) / loot_style / obstacle_remap / fluid_remap（debug 打印给管理员）
    (市场不在此放——出生区块尚未生成，改由 on_chunk_generated 惰性放置)

on_chunk_generated（每区块）:
    圆外铺虚空 -> map_features.generate（异物/障碍互换/树调色/战利品箱/危险敌群/残骸）
    -> 应用 tile 替换（按 mask）-> 画染地精灵
    -> 若是出生区块: 惰性放该星市场 market.place_on_surface（每轮每星一次，不强制生成区块）

on_player_respawned / on_player_created: passives.apply；本世界首次 -> respawn_gifts.on_first_respawn
on_pre_player_left_game: kill_player（当前表面出生点死亡，尸体留当地；复活回其复活星球/母星）
on_nth_tick(3600): 在线采样 + 各 +1 金币 + 倒计时/提醒 + run_world_events（事件世界，含 tech 得/失科技）
on_entity_died（world_fx 经总线）: 复制虫世界里玩家建筑被虫毁 -> 原地冒虫
```

## 跨跃迁进度

### 1. 科技瓶经验 → 开局直接发物资（`respawn_gifts`）

跃迁前背包里的科技瓶由 `science_exp.collect` 按瓶累加经验（**只在跃迁结算**，无提前结算）。
开局**直接**发每瓶对应的 **2 种代表物资**（`M.pack_gifts`）：

- 等级 = `floor(√exp)`，封顶 1000；单种数量 = `ceil(堆叠数 × 等级/100)`（等级100=1组、1000=10组，封顶 `MAX_GROUPS=10`）。
- 🧪 面板每瓶一行：`瓶图标 经验N · 右侧=下局会发的 2 种物资×数量`。

### 2. 角色技能（`passives.lua`，边玩边练）

| 动作 | 技能 | 曲线 |
| --- | --- | --- |
| 手搓 | 手搓速度 | -50% 起，log 缓升 |
| 移动 | 移动速度 | 同上，封顶 +100% |
| 采矿/拆除 | 挖矿速度 | 同上 |

## 金币经济

来源：开局 `floor(√在线分钟)` + 每分钟在线 +1 +（罕见 coinfall 事件）。用途：母星金币市场买普通装备零件。
装备是个人增益，不替代"建工厂"核心循环。

## 星球资源档位（`surface.lua`）

每种资源的丰度/面积/频率各抽一个 1~9 整数 N：丰度 `3^(N-7)`、面积 `1.5^(N-6)`、频率 `1.3^(N-5)`，
再乘全局 `richness_multiplier`(默认 8)/`size_multiplier`(2)/`frequency_multiplier`(0.5)。**rail world 基线**：矿少而大且富（频率减半、面积/丰度翻倍），逼玩家修铁路连远矿。
地方特产（铀/钨/废料/gleba 石/aquilo 流体）用 `local_specialty_multiplier` 额外压低丰度。圆半径外铺虚空。
