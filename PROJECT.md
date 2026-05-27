# endfield_factorio 场景结构

异星工厂 (Factorio 2.0 + Space Age) 自定义场景。核心玩法：每隔一段时间触发一次"跃迁"——
所有星球清空重建、玩家死亡、飞船保留有限轮次；玩家通过累积科技瓶经验获得永久被动加成。

## 顶层文件

- `control.lua`：场景入口，按顺序 require 各子模块，`on_init` 时初始化 `storage` 并执行第一轮跃迁。
- `info.json` / `description.json`：场景元数据。
- `locale/`：本地化字符串（`wn.*` 键由代码引用）。

## scripts/

| 文件 | 职责 |
| --- | --- |
| `constants.lua` | 全局常量：tick 换算、品质 → 经验倍率。无副作用。 |
| `util.lua` | 通用工具：随机指数分布、`try_add_trait` 追加左上 HUD 词条等。 |
| `players.lua` | 玩家生命周期事件：创建/加入/离开/复活/死亡，调用 passives + gifts。 |
| `respawn_gifts.lua` | 每个世界（`storage.run`）首次复活时发放起手护甲 + **货币**：携带经验换的 epic/legendary 瓶子 + 在线时长换的普通金币。不再直接发建筑，改由市场购买。 |
| `currency.lua` | 货币换算（纯函数）：`reward_for_exp` 经验→epic/legendary 瓶子（√曲线）、`reward_amount` 在线统计→金币数量。 |
| `market.lua` | Nauvis 出生点的 13 个原版 market 实体（每轮跃迁后延迟重放，不可摧毁/挖取，铺混凝土地坪整齐对齐）。货物产出固定 normal；价格按物品 `q` 品质货币：epic 买大需求散件、legendary 买设备/插件。用原版交易界面；`on_tick` 延迟放置避开 `surface.clear` 异步结算。 |
| `passives.lua` | **动作即时升级的 4 技能**：手搓→手搓速度、步行→移动速度、采矿/拆除→挖矿速度、死亡→生命上限。曲线自带 -50% 下限（0 经验时 -50%，做动作爬升）。独占 craft/mine/changed_position/died 事件，递增统计并即时施加。保留 `exp_total_for_pack`/`get_stat`。 |
| `science_exp.lua` | 跃迁前扫描玩家背包里的科技瓶，按 `每组 × 品质倍率` 累加进 `storage.science_exp`。 |
| `research.lua` | 研究完含 `-science-pack` 名字的科技时，把本轮跃迁倒计时延长 1 小时。 |
| `surface.lua` | 跃迁后随机生成各星球：地图设定、资源分布、圆形边界。 |
| `reset.lua` | 跃迁主流程：清场 → 收集经验 → 杀玩家 → 清星球 → 重置科技 → 随机参数。 |
| `tick.lua` | `on_gui_click` 与 `on_nth_tick(3600)` 的**唯一注册点**：每分钟在线采样（调 `player_stats.sample_online`）+ 跃迁倒计时 + 撤离提醒；点击 HUD 自杀脱困。 |
| `player_stats.lua` | 行为统计**数据存储**（craft_count/mining_count/move_distance/deaths + online_minutes/research/warps）。只管 get/默认值/旧档迁移 + 在线类采样；技能统计的递增在 `passives.lua` 的动作事件里。跨跃迁累积。 |
| `rocket.lua` | 发射火箭惩罚：每次 `on_rocket_launched` 令本轮 `warp_hours` -1 分钟，公告并打印火箭载荷。 |
| `commands.lua` | 管理/调试命令（控制台调用视作管理员）。 |
| `gui.lua` | 左上角 HUD：轮次、星系词条、经验加成、在线名册、管理员按钮。 |

## 关键 storage 字段

- `storage.run`：当前世界序号，从 1 开始。每次 `reset.reset()` +1。
- `storage.run_start_tick`：本轮跃迁开始时的 tick。
- `storage.warp_hours`：本轮剩余跃迁时长，研究科技瓶相关科技可延长。
- `storage.platform_age[idx]`：飞船已经历的跃迁数；超过 `storage.platform_lifetime` 时摧毁。
- `storage.science_exp[player_index][pack_name '/' quality] = exp`：累计科技瓶经验。
- `storage.last_respawn_run[player_index]`：玩家上次复活时的 `storage.run`，用于判定"本世界是否首次复活"。
- `storage.player_stats[player_index]`：行为统计（驱动 passives + 在线金币奖励）。含 `online_warps`（在线跃迁次数）。

（市场用原版交易界面，offer 已带品质，无需额外 storage 状态。）
- `storage.traits`：左上 HUD 列出的本轮星系词条（本地化字符串数组）。
- 地图参数：`storage.richness / frequency / size / radius / difficulty / local_specialty_multiplier`。

## 数据流速览

```
跃迁前:
    各模块 -> storage           (经验累计、飞船年龄等)

reset.reset():
    science_exp.collect(每玩家)         -> storage.science_exp
    player_stats.on_warp_for_online_players() -> online_warps（在线玩家 +1）
    kill / clear 玩家
    surface.clear -> surface.lua 重新生成
    force.reset(科技清零)
    随机污染/小行星/腐烂参数
    passives.apply(在线玩家)
    market.place_on_nauvis()           -> 出生点重放市场实体

on_player_respawned:
    passives.apply(player)
    若 storage.run != last_respawn_run[idx]:
        respawn_gifts.on_first_respawn(player)  -- 起手护甲 + 货币（携带经验换 epic/legendary 瓶 + 在线换普通金币）

打开市场实体 -> 原版交易界面（offer 由 market.stock_market 上架，价格+产出都带品质）
```

## 货币经济（替代旧的"按等级发物品到背包"）

跃迁复活时不再往背包塞建筑（会爆背包，且旧的 `gifts_per_level` 只有 1 级、对数曲线形同虚设）。
改为发放两种**货币**，玩家到 Nauvis 出生点的市场（`market.lua`）按需购买，从根本上避免爆背包。

### 货币一：携带经验奖励（`currency.reward_for_exp`，epic / legendary 两档）

按各瓶累计经验（`storage.science_exp`，仍由 `science_exp.collect` 在跃迁前扫背包累加）换算。
**只发 epic、legendary 两档**（普通瓶可量产，不作为奖励品质），两档都用平方根曲线、**独立计算**：

- `epic 数 = floor(√exp)`，最多 **4 组(800)**。
- `legendary 数 = floor(√exp / 10)`，最多 **1 组(200)**；独立给，不是 epic 溢出才给。
- 例：exp=100 → 10 epic + 1 legendary；exp=640000 → 800 epic(满) + 80 legendary；exp≥4e6 → 满(800 epic + 200 legendary)。
- 理论上限每瓶 4+1=5 组 → `5 × 12 = 60 组`（≤ 背包约 80 格，基本不爆背包）。
- 🧪 面板每瓶直接显示"下次跃迁会给的瓶子数"（按品质，由 `reward_for_exp` 算出）。

### 货币二：在线奖励普通金币（`currency.reward_amount` + `constants.online_coin_stat`）

在线/挂机时长 → **普通(normal)金币**，复活（每局开始）时发放：`数量 = floor(√online_minutes × reward_amount_mult)`。
因为 `online_minutes` 是终身累积，所以越老的玩家每局开局金币越多。金币用于金币市场买装备。

> **更高品质金币（uncommon+）不作为奖励**——只能在普罗米修斯市场用普罗米修斯瓶按品质兑换
> （epic/legendary 金币 ⇐ epic/legendary 普罗米修斯瓶）。
> （`online_research`/`online_warps` 仍被统计，但目前只 research 驱动背包格子被动；warps 暂未使用。）

### 市场（`market.lua`）

出生点放 13 个原版 market 实体（12 瓶市场 3×4 网格 + 金币市场在最上方，3 格间距）。
每个用 `add_market_item` 把该货币的"物品 × 5 品质"全上架——`MarketIngredient`（价格）和
货物**产出固定 normal 品质**；价格按物品 `q` 字段所需的货币品质：**epic 买大需求散件**（传送带/电杆/管道/墙/铁轨，量大）、**legendary 买设备/插件**（机器/模块/机械臂，量小）。

`M.sections` 是**手动配置区（占位待填）**：每个市场只收一种货币，science-pack 市场卖
"该瓶对应科技阶段的商品"；金币市场卖装备；普罗米修斯市场兑金币（已预填，金币唯一来源）。
逐项填 `{name=物品, price=该品质货币个数}`。

## 角色被动（`passives.lua`）

**固定惩罚，不随任何统计/升级变化**。所有玩家：

- 手搓速度 `character_crafting_speed_modifier = -0.5`（-50%）
- 移动速度 `character_running_speed_modifier = -0.5`（-50%）
- 挖矿/拆除速度 `character_mining_speed_modifier = -0.5`（-50%）
- 生命值上限、背包容量：**保持原版**（不加修正）

由 `passives.apply(player)` 施加。角色换新（创建/复活/跃迁）后修正会清零，故
`on_player_created` / `on_player_respawned` / `reset.reset()` 末尾都重新调用。
`exp_total_for_pack` / `get_stat` 保留，供货币与 GUI 读取（科技瓶经验只用于携带奖励，不再驱动被动）。

### GUI 展示（`gui.lua` → `build_skills_tooltip`）

左上 HUD 🧪 按钮 tooltip：① 在线金币行 ② 12 瓶"跃迁给瓶数"（按品质）。
固定惩罚说明（`wn.skills-penalty`）改放在 🌐 星系词条按钮 tooltip 顶部（见下）。
所有行先收集成 flat 列表，再折叠成嵌套 localised string（突破单层 ~20 参数上限，沿用 `util` 手法）。
