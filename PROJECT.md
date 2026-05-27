# endfield_factorio 场景结构

异星工厂 (Factorio 2.0 + Space Age) 自定义场景。核心玩法：每隔约 1 小时触发一次"跃迁"——
所有星球清空重建、玩家死亡复活、飞船保留有限轮次。**跨跃迁的永久进度**有两条：

1. **科技瓶经验** → 下次开局直接发该瓶对应的代表物资（带得越多、开局越富）。
2. **角色技能**（边玩边练）→ 手搓/移动/挖矿越多越快、死亡越多血上限越高。

## 顶层文件

- `control.lua`：场景入口，按顺序 require 各子模块，`on_init` 初始化 `storage` 并执行第一轮跃迁。
- `info.json` / `description.json`：场景元数据。
- `locale/`：本地化字符串（`wn.*` 键由代码引用）。

## scripts/

| 文件 | 职责 |
| --- | --- |
| `constants.lua` | 全局常量：tick 换算、品质→经验倍率、12 种科技瓶顺序。无副作用。 |
| `util.lua` | 通用工具：`try_add_trait` 追加左上 HUD 词条、`readable`、随机指数分布、`random_nature`。 |
| `players.lua` | 玩家生命周期事件（创建/加入/离开/复活/死亡）；`print_inspection` 打印 `/inspect` 面板。 |
| `respawn_gifts.lua` | 每世界首次复活时发：起手护甲 + 起手物资（铁/铜板、煤、石、机器人）+ **每瓶 2 种代表物资**（数量随经验、按堆叠封顶 5 组）+ **开局金币**(`√在线分钟`)。 |
| `market.lua` | 母星出生点的**一个**金币市场：用金币买各种普通装备零件（不可摧毁/挖取）。由 `surface.lua` 在 clear 结算后放置。 |
| `passives.lua` | **动作即时升级的 4 技能**：手搓→手搓速度、步行→移动速度(封顶 +100%)、采矿/拆除→挖矿速度、死亡→生命上限。曲线自带 -50% 下限、log 缓升。独占 craft/mine/changed_position/died 事件。`gift_count`/`next_threshold`/`coin_reward` 也在 `respawn_gifts`。 |
| `science_exp.lua` | 跃迁前扫描背包里的科技瓶，按 `floor(组数) × 品质倍率` 累加进 `storage.science_exp`（每瓶一个 key，12 个）。 |
| `research.lua` | 研究含 `-science-pack` 名（非 trigger）的科技时，本轮跃迁倒计时 +1 小时并公告。 |
| `surface.lua` | 跃迁后随机生成各星球：地图设定、资源档位（1~9 随机档）、圆形虚空边界；母星放市场。 |
| `reset.lua` | 跃迁主流程：收集经验 → 杀玩家 → 清星球(异步) → 重置科技 → 随机参数 → 清地图标记。 |
| `tick.lua` | `on_gui_click` 与 `on_nth_tick(3600)` 的**唯一注册点**：每分钟在线采样 + **给在线玩家各 +1 金币** + 跃迁倒计时 + 撤离提醒；点 HUD 自杀脱困。 |
| `player_stats.lua` | 行为统计**数据存储**：craft_count/mining_count/move_distance/deaths/online_minutes。只管 get/默认值/旧档迁移 + 在线采样；递增在 `passives.lua`。跨跃迁累积。 |
| `rocket.lua` | 发射火箭惩罚：每次 `on_rocket_launched` 令本轮 `warp_hours` -1 分钟，公告 + 打印载荷。 |
| `commands.lua` | 命令：`/reset`、`/players_gui`、`/life`、`/inspect`(=`/chakan`)、`/exp_clear`。 |
| `gui.lua` | 左上角 HUD：轮次按钮、星系词条、🧪 面板（每瓶经验+下局发的物资）、在线名册、管理员按钮。 |

> `currency.lua` 已废弃（功能并入 `respawn_gifts`），不再被 require，可删除。

## 关键 storage 字段

- `storage.run`：当前世界序号，从 1 开始，每次 `reset.reset()` +1。
- `storage.run_start_tick` / `storage.warp_hours`：本轮起始 tick / 本轮总时长（研究可延长）。
- `storage.platform_age[idx]` / `storage.platform_lifetime`：飞船经历的跃迁数 / 上限。
- `storage.science_exp[player_index][pack_name] = exp`：每瓶累计经验（12 个 key，不分品质）。
- `storage.player_stats[player_index]`：行为统计（驱动技能 + 金币）。
- `storage.last_respawn_run[player_index]`：上次复活时的 `run`，判定"本世界是否首次复活"。
- `storage.traits`：左上 HUD 的本轮星系词条（本地化字符串数组）。
- `storage.move_pos[idx]`：上次采样的位置（算移动距离）。
- 地图参数：`storage.radius / radius_of / difficulty / local_specialty_multiplier`。

## 数据流速览

```
reset.reset():
    science_exp.collect(每玩家)  -> storage.science_exp（扫背包瓶子累加经验）
    kill / clear 玩家、清星球(异步)、force.reset(科技清零)、随机污染/小行星参数、清地图标记
    passives.apply(在线玩家)

on_surface_cleared（clear 结算后，每星球）:
    随机昼夜/半径/资源档位(1~9) -> mgs；gui.players_gui() 刷新词条
    母星：market.place_on_nauvis()  -> 出生点放金币市场

on_player_respawned / on_player_created:
    passives.apply(player)
    若本世界首次：respawn_gifts.on_first_respawn(player)
        = 起手护甲 + 起手物资 + 每瓶 2 种代表物资(按经验) + 开局金币(√在线分钟)

on_nth_tick(3600，每分钟): 在线采样 + 给在线玩家各 +1 金币 + 倒计时/提醒
```

## 跨跃迁进度

### 1. 科技瓶经验 → 开局直接发物资（`respawn_gifts`）

跃迁前背包里的科技瓶由 `science_exp.collect` 按瓶累加经验。开局**直接**发放每瓶对应的
**2 种代表物资**（`M.pack_gifts`，可自由改），不再发瓶子、不经市场：

- 单种数量 = `floor(堆叠数 × 5 × √(exp/CAP_EXP))`，封顶 `5 × 堆叠数`（5 组）。
- 所有物品在 `CAP_EXP` 同时触顶；堆叠小的物品同经验下绝对数量更少（更稀有）。
- 🧪 面板每瓶一行：`瓶图标 经验N · 右侧=下局会发的 2 种物资×数量`。

### 2. 角色技能（`passives.lua`，边玩边练）

| 动作 | 技能 | 曲线 |
| --- | --- | --- |
| 手搓 | 手搓速度 | -50% 起，log 缓升，需玩很久回正常 |
| 步行 | 移动速度 | 同上，**封顶 +100%** |
| 采矿/拆除 | 挖矿速度 | 同上 |
| 死亡 | 生命上限 | 死越多血上限越高 |

对应动作事件即时递增统计并施加修正。角色换新后（创建/复活）由 `passives.apply` 重算。

## 金币经济

金币来源：开局 `floor(√在线分钟)` + 每分钟在线 +1。用途：母星**一个**金币市场买各种普通
装备零件（`market.offers`）。定价原则：**分级装备**高级档每点属性更贵（性价比低、但省装甲格）；
**单级装备**价格手动配置。装备是个人增益，不替代"建工厂"的核心循环。

## 星球资源档位（`surface.lua`）

每种资源的丰度/面积/频率各抽一个 1~9 随机整数 N，乘数 `2^(N-中心)`（丰度中心 7、面积 6、频率 5）。
星系词条用 `[virtual-signal=signal-N]` 显示。地方特产（铀/钨/废料/gleba 石/aquilo 流体）用
`richness_multiplier` 额外压低丰度（只压丰度，不动面积/频率）。圆半径外铺虚空。
