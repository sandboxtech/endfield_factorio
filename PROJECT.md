# endfield_factorio 场景结构

异星工厂 (Factorio 2.0 + Space Age) 自定义场景。核心玩法：每隔一段时间（起步约 `warp_initial_minutes`(默认30) 分钟，随解锁新科技瓶延长、发射火箭/投票缩短）触发一次"跃迁"，所有星球清空重建、玩家死亡复活、飞船保留有限轮次。**跨跃迁的永久进度**有两条：

1. **科技瓶经验** → 跃迁前背包里的科技瓶累加为各瓶经验（**每个瓶 1 点**、按品质加成），用于角色面板展示等级（`floor(√经验)`，上限 10000 级、经验无上限）。经验用途：**职业系统**按所选职业用到的各科技瓶等级，线性发开局奖励物品（见『跨跃迁进度 2』）。
2. **角色技能**（边玩边练）→ 手搓/移动/挖矿做得越多，对应速度越快（开局 -50%、log 缓升、移动封顶 +100%）。

（手搓/移动/挖矿能力 + 人物等级 + 击杀等统计都在 HUD【状态】按钮窗口查看；科技瓶经验在【角色面板】按钮窗口。）

每一轮的各星球还会随机出**世界变体**（地表换皮 / 染地 / 据点遭遇(箱+敌人) / 世界事件 / 障碍·流体互换…），
追求"大概率寻常、小概率新奇但有意义"，让反复跃迁不重样。

## 顶层文件

- `control.lua`：场景入口，按顺序 require 各子模块；`on_init` 执行第一轮跃迁、`on_configuration_changed` 补齐新增默认字段，二者的 storage 默认值统一经 `constants.ensure_defaults`（亦在每轮 `reset` 开头调用，幂等不覆盖已调参数）。`ensure_defaults` 开头有**常驻清理**：删除已废弃的 storage 键（如 `danger_theme`/`wreck_density`/`loot_density_outpost`…）并修正类型已变更的键（`travel_chance` 标量→表）→ 老存档加载/跃迁即自愈。（更早的一次性数据格式规范化，如 `radius_of` 拆 `width_of`/`height_of`，是用 `/c` 脚本处理的。）
- `info.json` / `description.json`：场景元数据。
- `locale/`：本地化字符串（`wn.*` 键由代码引用，en + zh-CN）。

## scripts/

| 文件 | 职责 |
| --- | --- |
| `constants.lua` | 全局常量：tick 换算、品质→经验倍率、12 种科技瓶顺序；`balance` 表集中各世界变体的出现概率/权重（一眼看全、统一调）；`ensure_defaults()` 设 storage 默认值 + 清理废弃键/修类型（迁移），是默认值的唯一出生地。 |
| `util.lua` | 通用工具：`readable`、`random_exp` 指数分布、`random_nature`、`mostly_normal`、`evo_biter`（按进化度挑虫）。 |
| `events.lua` | **事件总线**：同一事件多处 `events.on()` 订阅、内部只 `script.on_event` 注册一次再分发 → 避免单事件被多处注册互相覆盖。可能被多方监听的事件都走它。 |
| `noise.lua` | 2D simplex + 分形多倍频 + 种子派生变换（旋转/拉伸/缩放）。供运行时手动铺设噪声地物（移植自 ComfyFactorio）。 |
| `players.lua` | 玩家生命周期（创建/加入/离开/复活/死亡）。`kill_player`：先把玩家移到**当前所在表面**的出生点再杀死（**尸体/货物留在当前星球**，杜绝"外星捡货→自杀带回母星"）；**复活落点** `place_on_respawn` 去玩家的**复活星球** `storage.respawn_surface[名]`（前往某星球时由命令记下；该星球 surface 不存在则回**母星**），`place_on_surface` 仅**异步**请求生成区块、不强制。`print_inspection` 面板。 |
| `respawn_gifts.lua` | 每世界首次复活时发：**固定**起手护甲（modular-armor 内置 1 机器人端口 + 1 夜视仪 + 1 个 1 级电池 + 10 块太阳能板，不随等级变）+ 起手基础物资 + **开局金币**(`floor(√在线分钟)`) + **职业开局物品**(`gift_list`)：所选职业的无条件起手物(`starter`，可多种·各几组) + 按职业用到的各科技瓶等级线性发的奖励物(`floor(堆叠×组数×等级/满级)`)。背包格数加成 = 首发清单总格数(`gift_slots`，`apply_inventory_bonus` 读存值保持)。 |
| `classes.lua` | **职业系统**：每个职业是一个**专精主题**（采矿/自动化/机器人/军事/外星/博学…），决定开局发什么物品；HUD 独立按钮窗口选择（同时只能一种，存 `storage.player_class`，带短冷却）。`starter` 无条件起手物列表(可多种·各几组)；`rewards` 多条，每条用一种瓶等级**线性发**一种物品(`floor` 向下取整)；`unlock` 可选门槛(当前全部无门槛、人人可选)。**职业表存 `storage.classes`**(由 `M.ensure()` 从 `DEFAULT_CLASSES` 深拷贝，on_init/on_configuration_changed 调用)，**可 /c 热改**(改 groups/加减条目即时生效；`/c storage.classes=nil` 恢复默认)；读取走 `M.all()`/`M.def_for_key(key)`。详见『跨跃迁进度 2』。 |
| `market.lua` | **5 个**金币市场（母星 + 其余 4 个星球，凡 `PLANET_GEN` 有配置，内容相同，不可摧毁/挖取）。**惰性放置**：由 `surface.lua` 的 `on_chunk_generated` 在**出生区块自然生成时**（玩家复活/传送到该星触发）调一次，**不强制生成区块**；每轮每星一次（`storage.market_run` 记录，成功才记）。同时做**出生点保底**：中心抽 16 点，过半不可通行(`collides_with('player')`：水/熔岩/油海/虚空…)就铺 64×64 精炼混凝土。 |
| `passives.lua` | **动作即时升级的速度技能**：手搓/移动(封顶 +100%)/挖矿，曲线 -50% 下限、log 缓升；同时累积击杀/毁巢等统计。独占 craft/mine/changed_position 事件 + died(经总线)。展示在【状态】窗口。 |
| `science_exp.lua` | `collect`（跃迁结算在线玩家背包科技瓶 = **每个瓶 1 点 × 品质系数**，不移除瓶子）/ `preview`（同算法预览，不写入）。经验按**玩家名**存 `storage.exp`（直接是经验值、不再做任何缩放；旧 `science_exp` 以"组"计的存档迁移时 ×200 转"瓶"刻度，见 `ensure_defaults`）。（提前结算 `/settle` 已移除：只有跃迁才结算。） |
| `research.lua` | 研究含 `-science-pack` 名（非 trigger）的科技 → 本轮倒计时延长 `warp_extend_minutes[瓶]`(默认60) 分钟、公告、并 `gui.refresh_countdown()` 立刻刷新头顶倒计时。 |
| `map_features.lua` | **每轮地图风味**（手动放置原生做不到的东西）：`M.knobs()` 本轮整局气质连续旋钮；跨星球 `EXOTIC` 异物（稀疏 simplex 散布）；`theme_trees` 改原生树颜色/灰度（连续插值）；**遭遇优先链** `place_encounter`（每地块**至多一个**，按稀有度依次尝试、命中即停）：永续箱 → 木箱 → 铁箱 → 钢箱 → 空据点(纯敌人)。箱均 `destructible=false` 不受伤但**可手拆**；每个遭遇都经**统一 `place_guards(danger)`** 放敌人（仅 danger 不同：永续/空据点高、普通箱低；出生点 96 格内只放箱不放敌、越远越猛）：`OUTPOST_GUARDS` 统一守卫池（激光/特斯拉/喷火/机枪/火箭/磁轨 + 沙虫/地雷/重炮，每种各自**非线性**数量；电炮首次出现才**惰性**建 enemy 子电网 substation+供电接口）+ **非线性飞船残骸**（neutral，不铺人造地板）。五类出现率统一经 `encounter_chance`(世界密度×`ENCOUNTER_BASE`×`loot_density`×各类乘数)。`M.generate` 逐区块调用。（原 `feat_material/equipment/treasure/outpost`、零星 `feat_danger`、散布 `feat_wrecks`、独立 `feat_perpetual`+`guard_perpetual` 已**全部并入** `place_encounter`；电网核心用 **legendary substation** 扩大供电范围。） |
| `world_fx.lua` | 事件驱动的世界效果（经 `events` 总线）的**注册表**：`register(name,event,run)` 每项带全局开关 `storage.world_fx[name]`（默认开，`/c storage.world_fx.xxx=false` 禁用）。现有 **复制虫**(`replicant`)，玩家建筑被虫破坏时按**全局常数概率** `storage.replicant_chance`(默认0.5) 原地冒虫（不再按星球 danger_theme 滚，呼应 Comfy infested）。加新 fx 只动本文件 + `ensure_defaults` 开关列表。 |
| `surface.lua` | 跃迁后逐星球生成：原生 autoplace 调参 + **气候噪声偏置**（`control:moisture/aux/temperature:bias` 修改原生而非覆盖）+ **世界变体**滚定（染地/tile 替换/事件/遭遇密度/障碍/流体）+ **椭圆+噪声粗糙虚空边界**（每星滚定椭圆半轴 `width_of`/`height_of` 与边缘粗糙度 `shape_of={rough,seed}`，归一化椭圆距离超 `1+rough×噪声` 即铺虚空 → 海湾/半岛/锯齿边）；逐区块应用 tile 替换与染地精灵；**逐区块惰性放各星球市场**（出生区块生成时）。各星球资源/自然/气候由声明式 `PLANET_GEN` 表驱动。debug 时向**管理员**打印每次生成的属性。 |
| `reset.lua` | 跃迁主流程：飞船老化(命数前缀) → 收集经验/存排行榜 → 清理不活跃玩家 → 杀玩家(尸体留当地) → 广播结算 → 清星球 → 重置科技 → **解锁所有星球+发现科技** → 飞船回母星轨道+**清陨石** → 随机参数。 |
| `tick.lua` | `on_gui_click`(经 `events.safe` 包裹) + **每分钟周期任务**（不再用 `on_nth_tick`，改走 `events` 总线的 `on_tick` + `game.tick % 3600` 整除门控：多订阅安全、不被覆盖、间隔可扩展）：在线采样 + 倒计时/提醒 + **事件世界** `run_world_events`（按 `WORLD_EVENTS` 分发表：raid 撒虫卵/meteor/supply/coinfall/drones/barrage/tech；每分钟全服 `event_chance` 掷一次、命中挑一个事件世界玩家触发其星球事件；每种事件另有独立跳过钮 `storage.event_period_min[et]`)。 |
| `player_stats.lua` | 行为统计存储（craft/mining/move/deaths/online_minutes，按玩家名，跨跃迁累积）；递增在 `passives.lua`。 |
| `rocket.lua` | 发射火箭惩罚：每次 `on_rocket_launched` 令本轮 `warp_hours` -1 分钟，公告 + 打印载荷。 |
| `commands.lua` | 命令（**全英文名、无中文/拼音别名**）：管理员 `/reset`（破坏性，保留打字命令；清空经验改用控制台 `/c storage.exp = {}`）；会员管理 `/member`/`/unmember`(仅管理员)/`/kickout`。**管理员的 gen / diff(=ensure_defaults+参数对比) / 刷新玩家界面 已改为左上角【红按钮】**（仅管理员可见，`M.admin_gen`/`admin_diff`/`admin_players_gui`）；查看/预览/排行/自杀/教程/前往/出生星球 = HUD 或功能菜单弹窗按钮。**前往星球** `M.travel`：受总开关 `storage.travel_enabled`(默认关) + 每轮每外星独立 `storage.travel_chance[星球]`(默认0.5，reset 滚定 `travel_open`) 双重控制，要求鼠标/背包/物流/弹药四区为空；**出生星球** `M.set_home_planet` 设 `respawn_surface[名]`(下次跃迁在此复活并领起手装备)。**跃迁投票** `M.cast_warp_vote`→`warp_vote_eval`：净同意 ≥ ceil(在线/`warp_vote_divisor`) 即把倒计时**砍到剩 `warp_vote_target_minutes`(默认5) 分钟**并记缩减量 `warp_vote_delta`；**票持续生效不清空**，改票跌破阈值则把时间**加回(取消提前)**，reset 清空、不杀玩家。**投票+前往共享每玩家冷却** `action_cd`(默认3分钟，`action_cd_minutes`)。`add_command` 包装层在执行前公告全体"谁用了什么"。 |
| `gui.lua` | 左上角 HUD：**① 玩法&指令按钮**(`show_tutorial`，纯说明文字) **② 功能菜单按钮**(`show_actions`：角色面板/跃迁/停留/预览/排行/自杀/前往星球(未开放置灰)/出生星球(当前标✓)) + 角色面板/跃迁/停留快捷 sprite + **管理员专属红按钮 GEN/DIFF/玩家**（`style='red_button'`，仅 `player.admin` 创建 → 普通玩家看不到，点击经 tick 路由到 `commands.admin_*`）+ 轮次·倒计时标签。屏幕中央临时弹窗 `show_popup`(支持按钮 `enabled`/`tooltip`)。 |

## 世界变体系统（`surface.lua` + `map_features.lua` + `noise.lua` + `tick.lua` + `world_fx.lua`）

设计原则：**用噪声修改 2.0 原生生成，不用手动 stamp 覆盖**（原生地貌更自然）；每个变体大概率不出现、
小概率温和、极小概率明显（非线性曲线）；可调常量见下。每星球每轮独立滚，互不绑定。

- **整局气质旋钮** `M.knobs()`（按 `storage.run` 派生、整轮缓存）：`verdancy/rockiness/exotic/riches` 四者**各自独立**（不同种子哈希）；`danger` 是**派生**的：`min(1, riches×0.8 + exotic×0.4)`——**与 riches 正相关(主)、exotic 正相关(次)**（富庶/诡异世界更危险=高风险高回报）。各旋钮取值 [0,1]。驱动：verdancy→湿度偏置+树/草 autoplace、rockiness→石 autoplace、exotic→染地/tile替换概率+跨星异物、**riches→遭遇箱数量**、**danger→敌人伤害+事件强度+据点守卫规模**。
- **原生调参**（`surface.lua`）：`set_resource`（丰度/面积/频率 1~9 档）、`nature_by_knob`（树/石/草密度随气质、
  规模"多半小偶尔大"）、`bias_climate`（`control:moisture/aux/temperature:bias` 偏置整星干湿冷热 → 原生自然铺开）。
- **染地世界** `ground_tint`：地面层盖半透明染色精灵（`rendering.draw_sprite`，不改地块），alpha 立方曲线 → 多半淡染、极少浓染（infested 感）。
- **tile 替换**：每世界 1~N 条规则 `源家族 → 目标 tile + mask`。
  - 源 `PLANET_SRC[星球]`：只取该星实际存在的 tile 子家族（否则空转）。
  - 目标白名单 `TILE_CLASS` 四类：`water`(常规水) / `ground`(自然地表) / `exotic`(岩浆·油海·氨海·虚空·太空) / `artificial`(混凝土系+9 色套色+铺路/landfill/地基)。`valid_pools` 按 `prototypes.tile` 过滤拼错名。
  - mask：`all`(整片，仅安全自然：水→可泵水、地→任意地) / `noise`(平滑成片，**exotic 仅此可选**) / `tree`/`rock`/`ore`(跟随原生树/石/矿分布，**artificial 可 noise(成片人造地表)/ore**)。规则数与覆盖面非线性偏小。
  - 约束：整片替换不让星球缺资源；exotic/artificial 只部分替换（原 tile 仍保留）。exotic 出现率全星统一（`tile_mask_all` × `tile_to_exotic`），母星不额外加成。
- **遭遇优先链** `map_features.place_encounter`（原"危险世界 `danger_theme`、零星 `feat_danger`/`feat_wrecks`、独立 `feat_perpetual`、`feat_material/equipment/treasure/outpost`"已全部并入）：每地块**至多一个遭遇**，按稀有度依次试、命中即停——永续箱→木箱→铁箱→钢箱→空据点(纯敌人)。非空据点放 **1~16 个同类箱**（`floor(1+15·random^6 × (0.5+riches))`，富庶世界更多）。每个遭遇都经**统一 `place_guards(danger × (0.5+世界danger))`** 放敌人（仅 danger 不同：永续/空据点高、普通箱低；出生点 96 格内只放箱不放敌、越远+越危险世界越猛）+ 非线性飞船残骸。电炮首次出现才惰性建 **legendary substation** 子电网（功率 10~100MW）。地砖：空据点不铺、普通箱用 `enemy_floor`、永续用第二种 `enemy_floor2`。**复制虫**改为全局常数 `storage.replicant_chance`（见 world_fx）。原版 enemy-base 仍自然出虫。
- **事件世界** `event_world[星球]`：每星球每轮 **10%**(`balance.event.base 0.1 × prob_event`) 成为事件世界，命中则从下列类型**按权重抽一个**存入（**至多一种**；权重 `balance.event.weights`：drones=0.3、tech=0.3，余默认1 → 无人机/科技世界更罕见）。触发见 `tick.run_world_events`：每分钟先掷全局 `event_chance`(默认0.5) 决定**全服**是否发生，命中则随机挑一个"身处事件世界星球的在线玩家"，触发其星球的事件**一次**。类型：
  - `raid` 撒**虫卵**(biter-egg/pentapod-egg/captive-biter-spawner，随机新鲜度+数量+是否可拾取，掉地上延迟孵化成虫) / `meteor` 矿石陨石雨 / `supply` 物资空投 / `coinfall` 金币雨 / `drones` 敌方战斗机器人(defender/distractor/destroyer) / `barrage` 重炮落点(artillery-projectile，会砸自家建筑)。
  - `tech` **科技世界**（也是事件世界的一种，效果对**全 force**）：从**所有科技**(排除 4 个星球发现科技)**随机抽一个，不看是否已研究**，已研究则以 `tech_world_lose_chance`(默认0.125) **失去**(`researched=false`)，未研究则以 `tech_world_gain_chance`(默认0.1) **得到**(`researched=true`)，全服广播 `tech-gain`/`tech-lose`。脚本改 `researched` 是 `by_script` 事件，`research.lua` 早退 → 不会顺带改跃迁倒计时。
  - 另：**玩家亲手消灭虫巢**(`tick.lua` 的 spawner `on_entity_died`)有 **1%** 概率触发一次"得到科技"(同 grant 逻辑)。
  - 注意：染地/地表替换/危险/障碍/流体是**各自独立**的非事件世界变体（见下），可与事件世界叠加；事件世界本身只有一种、特征是"每分钟可能发生一些事情"。
- **遭遇密度** `loot_style[星球]`：每星独立滚 5 类遭遇(材料/设备/宝/永续/空据点)各自密度(random²)；某类某区块出现率 = 密度 × `ENCOUNTER_BASE` × `loot_density` × `loot_density_<类>`（见 `map_features.encounter_chance`，被 `place_encounter` 统一使用）。
- **障碍互换** `obstacle_remap[星球]`（原 `tree_remap` 已并入）：把本星【现地所有带碰撞盒障碍：树/石/遗迹/冰山/叠层岩…】(`type=tree/simple-entity`)在**噪声大团**内**跨类**原位替换，树↔石↔遗迹皆可，不看脚下 tile。**大概率(85%)整片统一换成同一种**(单一主题、协调)，小概率(15%)每个各自随机换成另一种(跨类大杂烩)。源天然自限(`find` 只命中本星现有实体)、目标跨星球。目标池 `OBSTACLE_TARGETS`(树+石+fulgora 遗迹) 运行时按 `entity_ok` 校验(无效**报告管理员**并剔除)。见 `map_features.feature_entity_remap`。**不做固体矿替换。**
- **流体资源互换** `fluid_remap[星球]`（小概率激活）：把产流体的资源(原油/锂卤水/氟喷口/硫酸喷泉)变成**随机另一种喷口**，二选一门控，`{p}` 每喷口各自以概率 p 突变(零星，p∈[0.08,0.88] 每星每世界不同) 或 `{seed,threshold}` noise 大团内整体突变(成片)。源自动识别(`type=resource` 且开采产物含 `fluid`，固体矿/废料不动)；含量按目标喷口 `minimum_resource_amount × 1.5~5.5` 生成。同片油田可能混出多种。见 `map_features.feature_fluid_remap`。

## 关键 storage 字段

- `storage.run` / `run_start_tick` / `warp_hours`：轮次序号 / 本轮起始 / 本轮总时长。
- `storage.platform_age[idx]` / `platform_lifetime`：飞船经历跃迁数 / 上限。船名前缀显示**剩余命数**(`[item=parameter-N][virtual-signal=signal-heart]` = 还剩 N 命 = `lifetime-age+1`)，每跃迁剥旧前缀换新；归零(`age>lifetime`)即摧毁。
- `storage.exp[玩家名][瓶名] = exp`：每瓶累计经验（12 key，瓶数×品质，直接数值；等级=floor√exp）。
- `storage.classes`：职业表（`M.ensure()` 从 `DEFAULT_CLASSES` 深拷贝；可 /c 热改，`=nil` 恢复默认）。
- `storage.player_stats[玩家名]`：行为统计（驱动技能 + 金币）。
- `storage.last_respawn_run[idx]`：上次复活的 `run`，判"本世界是否首次复活"。
- `storage.last_leaderboard` / `last_leaderboard_run`：上个世界经验排行榜（经排行榜按钮查看）及其世界号。
- `storage.market_run[星球]`：该星本轮市场已放置的 `run`（惰性放置去重）。
- `storage.warp_vote[玩家名]`：跃迁投票（`agree`/`oppose`，**持续生效、只在跃迁 reset 时清空**）；`storage.warp_vote_delta`：投票通过时砍掉的小时数，改票跌破阈值则加回（取消提前），reset 清空。
- 地图：`storage.radius_standard / radius_min / radius_max / difficulty / *_multiplier / local_specialty_multiplier`。每星球形状 `width_of`/`height_of`(椭圆半轴) + `shape_of={rough,seed}`(边缘噪声) 每轮重滚（替代原圆形 `radius_of`）。
- 世界变体（每星球，每轮重滚）：`ground_tint / tile_remap / event_world / loot_style / obstacle_remap({seed,threshold[,to]}) / fluid_remap`（树替换已并入 `obstacle_remap`；`danger_theme`/`wreck_density` 已随危险世界/散布残骸移除）。
- **可调常量**（默认值由 `constants.ensure_defaults` 设，on_init / on_configuration_changed / 每轮 reset 都调用，幂等不覆盖；游戏内 `/c storage.xxx=N` 动态调）：
  - `debug`(默认 true，向管理员打印每次生成属性)
  - 概率乘数（0=关）：`prob_ground_tint / prob_tile_remap / prob_obstacle_remap / prob_fluid_remap / prob_event`
  - 强度：`event_intensity`(事件落点) / `tile_remap_rules`(最多规则数) / `replicant_chance`(复制虫冒虫概率，默认0.5)
  - 遭遇密度（**全局乘数 × 各类乘数，相乘**）：`loot_density`(全局) × `loot_density_<material/equipment/treasure/perpetual/empty>`(各类，默认1)
  - 每星每外星【前往】概率 `travel_chance[星球]`(默认0.5) / 投票+前往共享冷却 `action_cd_minutes`(默认3) / 每事件独立周期 `event_period_min[et]`(默认1分钟)
  - 上限钳（防 /c 填超大数一 tick 卡死）：事件落点 `EVENT_MAX_SPAWN=50`、tile 规则 `≤20`
  - `storage.world_fx.<name>`(默认 true)：事件驱动效果总闸，false 全局禁用（如 `replicant` 复制虫）
  - `storage.event_types.<raid/meteor/supply/coinfall/drones/barrage/tech>`(默认 true)：事件世界各类型开关，`/c` 设 false 即排除某类型
  - `storage.event_chance`(默认0.5)：每分钟全服发生一次事件的概率 / `storage.tech_world_lose_chance`(默认0.125，抽中已研究科技时失去它的概率) / `storage.tech_world_gain_chance`(默认0.1，抽中未研究科技时得到它的概率)
  - 跃迁投票：`warp_vote_divisor`(默认5，阈值=ceil(在线/此值)) / `warp_vote_target_minutes`(默认5，通过后倒计时砍到的剩余分钟)

## 数据流速览

```
reset.reset():
    science_exp.collect(每在线玩家) -> storage.science_exp（扫背包瓶子累加，不移除）
    杀/清玩家、清星球(异步)、force.reset(科技清零)、随机污染/小行星参数、清地图标记
    passives.apply(在线玩家)

on_surface_cleared（每星球，clear 结算后）:
    随机昼夜/形状(椭圆 width_of/height_of + 粗糙度 shape_of)/资源档位 + 气候偏置(bias_climate) + 原生 autoplace 调参
    滚世界变体: ground_tint / tile_remap / event_world(含 tech) / loot_style / obstacle_remap / fluid_remap（debug 打印给管理员）
    (市场不在此放，出生区块尚未生成，改由 on_chunk_generated 惰性放置)

on_chunk_generated（每区块）:
    椭圆+噪声边界外铺虚空 -> map_features.generate（异物/障碍互换/树调色/place_encounter 遭遇链：箱/敌人/残骸）
    -> 应用 tile 替换（按 mask）-> 画染地精灵
    -> 若是出生区块: 惰性放该星市场 market.place_on_surface（每轮每星一次，不强制生成区块）

on_player_respawned / on_player_created: passives.apply；本世界首次 -> respawn_gifts.on_first_respawn
on_pre_player_left_game: kill_player（当前表面出生点死亡，尸体留当地；复活回其复活星球/母星）
on_tick(经 events 总线)+整除门控: 每分钟 在线采样 + 倒计时/提醒 + run_world_events（事件世界，含 tech 得/失科技）；另 warp_fx 每 tick 看跃迁倒计时
on_entity_died（world_fx 经总线）: 玩家建筑被虫毁 -> 按 replicant_chance 原地冒虫
```

## ⚠️ 易错点

- **跨表面（surface）错配会崩服**：跃迁瞬间玩家正被传送，`player.surface` 与 `player.character.surface` 会**短暂不一致**。凡 `rendering.*` / `create_entity` 同时要 `surface=` 和**实体**（`target=`/`source=` 角色等）时，surface 必须取**实体自己的 surface**（如 `char.surface`），否则报 "entity belongs to surface X but Y expected"。已踩坑两次：`players.lua` 聊天气泡、`warp_fx.lua` 倒计时大字（均已修）。新增此类代码务必遵守。
- **裸 `script.on_event` 不防崩**：高频/会碰原型的 handler 一律走 `events` 总线（多订阅、逐个 pcall）或 `events.safe(tag, fn)` 包裹，避免一处出错崩掉整服（已发生过多次）。
- **Lua 5.2**：无整除 `//`，用 `math.floor(a/b)`；无 `goto` 之外的新语法。

## 跨跃迁进度

### 1. 科技瓶经验（`science_exp` + 面板展示）

跃迁前背包里的科技瓶由 `science_exp.collect` 按瓶累加经验（**只在跃迁结算**，无提前结算）：**每个瓶 1 点**，乘品质系数（normal 1 … legendary 5）。

- 等级 = `floor(√经验)`，封顶 **10000**（经验无上限；`10^8` 经验 = `10^4` 级）。
- 🧪 角色面板每瓶一行：`瓶图标 · N 级 · 经验M`。
- 经验用途：**职业系统**的奖励物品(`rewards`)按所选职业用到的各科技瓶等级**线性发放**（`floor(堆叠×组数×等级/满级)`，见下"职业系统"）。

### 2. 职业系统（`classes.lua` + `respawn_gifts.gift_list`）

进服默认【平民】。HUD「职业」按钮窗口随时切换（同时只能一种，存 `storage.player_class`，切换即时生效、带短冷却）。
职业不与单一瓶一一对应，而是围绕一个**专精主题**；每个职业开局发两类物品（发到背包主格，见 `gift_list`）：

- **starter**（无条件起手物列表）：每条 `{item, groups=组数(默认1)}`，每轮开局直接发、不看等级；可列多种、各自组数。
- **rewards**（经验奖励物品列表）：每条 `{pack=瓶, item, groups=满级组数}`，按该瓶等级线性发，
  `个数 = floor(堆叠 × groups × 等级 / 满级(10000))`【向下取整】——满 N 级才出第 1 个（N=满级÷满级总个数）。
  一个职业可挂多条 rewards、各用不同瓶 → 练哪种瓶就出哪种货。
- `unlock`（可选门槛，每条 `{pack, level}` 需全满足）：当前所有职业**无门槛**、人人可选。

**背包格联动**（`gift_slots`）：开局清单占多少格，就把 `character_inventory_slots_bonus` 设多少（首发存 `storage.gift_slots[名]`，后续复活由 `apply_inventory_bonus` 读存值保持）→ 刚好装下、不溢出。

当前职业表（起手 starter / 奖励 rewards：练哪种瓶 → 出什么）：
- **平民** 热能采矿机 / 无
- **采矿专家** 热能采矿机 / 红瓶→电力采矿机、橙瓶(火山)→大型采矿机
- **自动化专家** 组装机1 / 红瓶→组装机2·传送带·快爪·石炉
- **机器人专家** 被动供应箱 / 绿瓶→建设机器人·物流机器人·机器人平台·存储箱，黄瓶→主动供应箱·请求箱·缓冲箱
- **军事专家** 机枪炮塔 / 黑瓶→激光炮塔·坦克·火箭筒·机枪炮塔
- **外星专家** 铸造厂 / 四外星瓶各→铸造厂·电磁工厂·农业塔·低温工厂
- **博学专家** 组装机2 / 后 10 种瓶(去掉红绿)各→一组该阶段代表机器

## 金币经济

来源：开局 `floor(√在线分钟)`（= 人物等级，每轮首次复活发放）+（罕见 coinfall 事件）+（消灭虫巢原地爆少量）。**不再每分钟发 +1 金币**。用途：母星金币市场买普通装备零件。
装备是个人增益，不替代"建工厂"核心循环。

## 星星（挂机时长货币，`commands.lua` 的 `show_star`/`claim_charge`/`give_star`）

与金币独立的第二种货币：**1 星星 = 1 分钟游戏时间**，离线也在攒（惰性计算：`storage.charge[名]`=上次结算 tick，待领封顶 `charge_max_hours`(默认30h)）。HUD【星星】按钮（人物等级 < `star_unlock_level`(默认20，≈在线6.7h) 时置灰、悬停提示等级解锁；投票按钮同理用 `vote_unlock_level` 默认10）窗口看余额 + 充能进度条 + 领取；满 1 颗才能领整颗（`claim_charge`，保留不足 1 颗的余数），`/givestar <玩家> <数量>` 转给他人（独立冷却）。余额存 `storage.star[名]`（内部按 tick、恒为分钟整数倍）。**注意：星星目前只能攒/领/转，尚无消费用途**（待补，见 TODO）。

## 星球资源档位（`surface.lua`）

每种资源的丰度/面积/频率各抽一个 1~9 整数 N：丰度 `3^(N-7)`、面积 `1.5^(N-6)`、频率 `1.3^(N-5)`，
再乘全局 `richness_multiplier`(默认 8)/`size_multiplier`(2)/`frequency_multiplier`(0.5)。**rail world 基线**：矿少而大且富（频率减半、面积/丰度翻倍），逼玩家修铁路连远矿。
地方特产（铀/钨/废料/gleba 石/aquilo 流体）用 `local_specialty_multiplier` 额外压低丰度。椭圆+噪声边界外铺虚空。
