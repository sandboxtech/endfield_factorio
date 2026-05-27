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
| `respawn_gifts.lua` | 每个世界（`storage.run`）首次复活时发放起手护甲 + **货币品质瓶子**：携带经验换的瓶子 + 在线奖励瓶子（uncommon+）。不再直接发建筑、不发金币，改由市场购买。 |
| `currency.lua` | 货币换算（纯函数）：`reward_for_exp` 经验→品质瓶子（√曲线）、`progress_for_exp` 经验→等级/升级进度、`reward_amount` 在线统计→奖励瓶子数量。 |
| `market.lua` | Nauvis 出生点的 13 个原版 market 实体（每轮重放，不可摧毁/挖取）。每个只卖一种货币的 5 品质货物，用 `add_market_item` 上架（价格+产出都带 quality，付 Q 得 Q）。12 瓶市场 3×4 网格，金币市场在最上方。无自定义 GUI，用原版交易界面。 |
| `passives.lua` | **行为统计**（player_stats）→ character 被动加成（手搓/移速/挖矿/HP/格子）；曲线为 log。另保留 `exp_total_for_pack`/`get_stat` 供货币与 GUI 读取。 |
| `science_exp.lua` | 跃迁前扫描玩家背包里的科技瓶，按 `每组 × 品质倍率` 累加进 `storage.science_exp`。 |
| `research.lua` | 研究完含 `-science-pack` 名字的科技时，把本轮跃迁倒计时延长 1 小时。 |
| `surface.lua` | 跃迁后随机生成各星球：地图设定、资源分布、圆形边界。 |
| `reset.lua` | 跃迁主流程：清场 → 收集经验 → 杀玩家 → 清星球 → 重置科技 → 随机参数。 |
| `tick.lua` | `on_gui_click` 与 `on_nth_tick(3600)` 的**唯一注册点**：每分钟在线采样（调 `player_stats.sample_online`）+ 跃迁倒计时 + 撤离提醒；点击 HUD 自杀脱困。 |
| `player_stats.lua` | 玩家行为统计（手搓/挖矿/死亡/在线分钟/在线研究/在线跃迁次数）。**只看是否在线、不看是否挂机**，避免鼓励在线挂机。跨跃迁累积，驱动 passives 与在线奖励瓶子。**不再自注册 on_nth_tick**（统一到 tick.lua）。旧存档 `afk_*` 字段在 `M.get` 中迁移为 `online_*`。 |
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
- `storage.player_stats[player_index]`：行为统计（驱动 passives + 在线奖励瓶子）。含 `online_warps`（在线跃迁次数）。

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
        respawn_gifts.on_first_respawn(player)  -- 起手护甲 + 货币瓶子（携带经验换 + 在线奖励 uncommon+）

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
- UI 等级 = 累计能换到的瓶子总数；`progress_for_exp` 给 `level / into(当前exp) / need(下一瓶所需exp) / quality`。

### 货币二：在线奖励品质瓶子（`currency.reward_amount` + `constants.online_rewards`）

按在线行为统计换算成**品质科技瓶**（数量 = `floor(√统计 × reward_amount_mult)`）。
普通(normal)瓶子玩家可量产，会让初期量产瓶子刷货币，故在线奖励**只发 uncommon+ 品质瓶**：

| 来源统计 | 奖励品质 | 默认瓶子（可改） |
| --- | --- | --- |
| `online_minutes`（在线分钟） | uncommon | automation |
| `online_research`（在线研究科技数） | rare | logistic |
| `online_warps`（在线经历的跃迁次数） | epic | military |
| （legendary 默认留空，需自行指定来源/瓶子） | legendary | — |

每项发哪种瓶子/品质在 `constants.online_rewards` 配置。只看"是否在线"、不看是否挂机。

> 金币(coin)**不作为任何奖励**发放——只能在普罗米修斯市场用普罗米修斯瓶按品质兑换
> （epic/legendary 金币 ⇐ epic/legendary 普罗米修斯瓶）。

### 市场（`market.lua`）

出生点放 13 个原版 market 实体（12 瓶市场 3×4 网格 + 金币市场在最上方，3 格间距）。
每个用 `add_market_item` 把该货币的"物品 × 5 品质"全上架——`MarketIngredient`（价格）和
give-item offer 都带 `quality`，所以**付什么品质货币，得什么品质物品**。

`M.sections` 是**手动配置区（占位待填）**：每个市场只收一种货币，science-pack 市场卖
"该瓶对应科技阶段的商品"；金币市场卖装备；普罗米修斯市场兑金币（已预填，金币唯一来源）。
逐项填 `{name=物品, price=该品质货币个数}`。

## 角色被动能力（`passives.lua`）

每条能力由一个 **player_stats 行为统计**驱动（不再是科技瓶），曲线用 log10：统计越多越强，1 点回到原版水平。
`exp_total_for_pack` / `get_stat` 仍保留，供货币系统与 GUI 读取（瓶子经验现在只用于市场货币，不再驱动被动）。

### 两种曲线

| 类型 | stat<1（含 0） | 公式 f(stat) | stat=1 | 每 ×10 |
| --- | --- | --- | --- | --- |
| `factor_multiplier`（乘法系） | -0.5（0.5×，惩罚） | `0.5 × log10(stat)` | 0（基准 1×） | +0.5（+50%） |
| `factor_additive`（加法系） | 0（无加成） | `0.5 × (log10(stat) + 1)` | +0.5 × base | +0.5 × base |

### 当前 ability 列表（5 条，全部已实装）

| locale 键 | 驱动统计 | 曲线 | 效果 |
| --- | --- | --- | --- |
| `wn.ability-crafting` | `craft_count` | multiplier | `character_crafting_speed_modifier = f` |
| `wn.ability-running` | `online_minutes` | multiplier | `character_running_speed_modifier = f` |
| `wn.ability-mining` | `mining_count` | multiplier | `character_mining_speed_modifier = f` |
| `wn.ability-health` | `deaths` | additive | `character_health_bonus = 250 × f` |
| `wn.ability-inventory` | `online_research` | additive | `character_inventory_slots_bonus = floor(10 × f)` |

### 应用时机

- `passives.apply(player)`：对单个有 `character` 的玩家重算所有 ability 写入 `LuaPlayer.character`。
- 触发点：`on_player_created` / `on_player_respawned`（刚拿到新 character）；`reset.reset()` 末尾
  （跃迁后对在线玩家批量重算，飞船上的玩家不死、不触发 respawn，需手动应用）。
- 统计更新发生在 `player_stats` 的各事件处理器（手搓/挖矿/死亡/研究）与每分钟 `sample_online`。

### GUI 展示（`gui.lua` → `build_skills_tooltip`）

左上 HUD 🧪 按钮 tooltip 三段：① 5 条被动 `{locale, 统计值, fmt(factor)}` ② 12 瓶货币进度（等级/升级经验）
③ 在线奖励瓶子。所有行先收集成 flat 列表，再折叠成嵌套 localised string（突破单层 ~20 参数上限，沿用 `util` 手法）。
格式化：`pct(f)` → `"+25%"`（乘法系）；`flat(f, base)` → `"+125"`（加法系）。

### 扩展新 ability

往 `M.abilities` 追加一项（新统计需先在 `player_stats.lua` 的 `DEFAULTS` 加字段并在相应事件里累加）：

```lua
{
    locale = 'wn.ability-xxx',
    stat   = 'some_player_stat',           -- player_stats 字段名
    curve  = M.factor_multiplier,           -- 或 M.factor_additive
    apply  = function(p, f) p.character_xxx_modifier = f end,
    fmt    = function(f) return pct(f) end,
}
```
