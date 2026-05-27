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
| `respawn_gifts.lua` | 每个世界（`storage.run`）首次复活时发放起手护甲 + **货币**：品质科技瓶（按经验）+ 品质金币（按在线统计）。不再直接发建筑，改由市场购买。 |
| `currency.lua` | 货币换算（纯函数）：`reward_for_exp` 经验→品质瓶子（√曲线）、`progress_for_exp` 经验→等级/升级进度、`coin_amount` 在线统计→金币。 |
| `market.lua` | Nauvis 出生点的市场实体（不可摧毁/挖取，每轮重放）+ 自定义商店 GUI：付 Q 品质货币得 Q 品质物品。建筑用对应瓶子买、装备用金币买。 |
| `passives.lua` | **行为统计**（player_stats）→ character 被动加成（手搓/移速/挖矿/HP/格子）；曲线为 log。另保留 `exp_total_for_pack`/`get_stat` 供货币与 GUI 读取。 |
| `science_exp.lua` | 跃迁前扫描玩家背包里的科技瓶，按 `每组 × 品质倍率` 累加进 `storage.science_exp`。 |
| `research.lua` | 研究完含 `-science-pack` 名字的科技时，把本轮跃迁倒计时延长 1 小时。 |
| `surface.lua` | 跃迁后随机生成各星球：地图设定、资源分布、圆形边界。 |
| `reset.lua` | 跃迁主流程：清场 → 收集经验 → 杀玩家 → 清星球 → 重置科技 → 随机参数。 |
| `tick.lua` | `on_gui_click` 与 `on_nth_tick(3600)` 的**唯一注册点**：每分钟在线采样（调 `player_stats.sample_online`）+ 跃迁倒计时 + 撤离提醒；点击 HUD 自杀脱困；商店点击转发 `market.on_gui_click`。 |
| `player_stats.lua` | 玩家行为统计（手搓/挖矿/死亡/在线分钟/在线研究/在线跃迁次数）。**只看是否在线、不看是否挂机**，避免鼓励在线挂机。跨跃迁累积，驱动 passives 与金币。**不再自注册 on_nth_tick**（统一到 tick.lua）。旧存档 `afk_*` 字段在 `M.get` 中迁移为 `online_*`。 |
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
- `storage.player_stats[player_index]`：行为统计（驱动 passives + 金币）。含 `online_warps`（在线跃迁次数）。
- `storage.market_unit_number`：当前 Nauvis 市场实体的 unit_number，用于 `on_gui_opened` 识别并弹出商店。
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
        respawn_gifts.on_first_respawn(player)  -- 起手护甲 + 货币（品质瓶子 + 品质金币）

打开市场实体 (on_gui_opened) -> market.open_shop -> 自定义商店 GUI
点击购买按钮 (on_gui_click, 经 tick.lua 转发) -> market.try_buy
```

## 货币经济（替代旧的"按等级发物品到背包"）

跃迁复活时不再往背包塞建筑（会爆背包，且旧的 `gifts_per_level` 只有 1 级、对数曲线形同虚设）。
改为发放两种**货币**，玩家到 Nauvis 出生点的市场（`market.lua`）按需购买，从根本上避免爆背包。

### 货币一：品质科技瓶（`currency.reward_for_exp`）

按各瓶累计经验（`storage.science_exp`，仍由 `science_exp.collect` 在跃迁前扫背包累加）换算。
第 q 品质的第 k 瓶成本 = `quality_cost_mult[q] × k` 经验（三角成本 ⇒ 数量 ∝ √经验）：

- 先用 normal 填满 1 组(200)，需 `1×(1+2+…+200)=20100` 经验；再进 uncommon（×10）、rare（×100）…
- 每瓶每品质封顶 1 组(200)。`5 品质 × 12 瓶 = 60 组`上限。每(瓶,品质)≤1 格，普通玩家只占几格。
- UI 等级 = 累计能换到的瓶子总数（奖励正比于等级）；`progress_for_exp` 给出 `level / into / need / quality` 供进度条显示。

### 货币二：品质金币（`currency.coin_amount` + `constants.coin_sources`）

按在线行为统计换算，品质由来源决定（数量 = `floor(√统计)`）：

| 来源统计 | 金币品质 |
| --- | --- |
| `online_minutes`（在线分钟） | normal |
| `online_research`（在线研究科技数） | uncommon |
| `online_warps`（在线经历的跃迁次数） | rare |

只看"是否在线"、不看是否挂机（避免反向鼓励在线挂机）。金币堆叠极大（≤3 种品质 → ≤3 格），
永不爆背包。epic/legendary 金币只能用普罗米修斯瓶在市场兑换。

### 市场（`market.lua`）

`M.sections` 列出分区：生产建筑用对应品质科技瓶购买、装备用品质金币购买、普罗米修斯瓶兑金币。
**付什么品质，得什么品质**（自定义 GUI 实现，原版 market 的 give-item 不支持品质输出）。
价格可在 `M.sections` 内逐项调。

## 角色被动能力（`passives.lua`）

每种能力由 1 个或多个科技瓶驱动，组合方式是 **log 相加**，等价于经验相乘。例：
手搓速度若由红瓶 + 紫瓶共同决定，则 `red=10` + `purple=10` 与 `single=100` 等效。
经验 < 1 的瓶子不计入（贡献 0）。

### 两种曲线

| 类型 | 全 0 时 | 公式（f） | exp=1 | 每 ×10 经验 |
| --- | --- | --- | --- | --- |
| `multiplier`（乘法系） | -0.5（即 0.5×） | `0.5 × Σ log10(exp_i)` | 0（基准 1×） | +0.5（+50%） |
| `additive`（加法系） | 0 | `0.5 × (Σ log10(exp_i) + 1)` | +0.5 × base | +0.5 × base |

乘法系的 -0.5 是惩罚：没攒过任何相关瓶子时角色比 vanilla 慢 50%。
加法系的 0 是无加成：没经验时没奖励，也无惩罚。

### 当前 ability 列表

`passives.abilities` 是按顺序列出的 12 条（对应 12 种瓶子）。`apply = nil` 表示未实装，
GUI 仍会显示经验占位。

| # | locale 键 | 瓶子 | 曲线 | 效果 |
| --- | --- | --- | --- | --- |
| 1 | `wn.ability-crafting` | automation | multiplier | `character_crafting_speed_modifier = f` |
| 2 | `wn.ability-running` | logistic | multiplier | `character_running_speed_modifier = f` |
| 3 | `wn.ability-mining` | chemical | multiplier | `character_mining_speed_modifier = f` |
| 4 | `wn.ability-health` | military | additive | `character_health_bonus = 250 × f`（base=250） |
| 5–12 | — | production / utility / space / metallurgic / electromagnetic / agricultural / cryogenic / promethium | — | 未实装（仅 tooltip 展示经验） |

### 应用时机

- `passives.apply(player)`：对单个有 `character` 的玩家重算所有 ability 并写入 `LuaPlayer.character`。
- 触发点：
  - `on_player_created` / `on_player_respawned`：玩家刚拿到新 character。
  - `reset.reset()` 末尾：跃迁后对在线玩家批量重算（飞船上的玩家不死、不触发 respawn，需手动应用）。
- 经验更新发生在 `science_exp.collect()`（reset 前扫背包）和 `passives.exp_total_for_pack()` 读取。

### GUI 展示（`gui.lua` → `build_skills_tooltip`）

左上 HUD 的 🧪 按钮 tooltip 列出每条 ability：
- 已实装：`{locale, breakdown, fmt(factor)}`，breakdown 是各瓶经验用 `+` 拼接的字符串。
- 未实装：`wn.ability-todo` 模板，仅显示瓶名 + 单瓶经验。

格式化函数：
- `pct(f)` → `"+25%"` 等，用于乘法系。
- `flat(f, base)` → `"+125"` 等绝对值，用于加法系 HP。

### 扩展新 ability

往 `M.abilities` 追加一项：

```lua
{
    locale = 'wn.ability-xxx',     -- locale 字符串，接收 (breakdown, fmt(f))
    packs  = {'space-science-pack'},
    curve  = M.combined_factor_multiplier,  -- 或 additive
    apply  = function(p, f) p.character_xxx_modifier = f end,
    fmt    = function(f) return pct(f) end,
},
```

注意 packs 可填多个，会按 log-sum 组合。多瓶组合的能力会让低经验玩家更难触发
（任何一瓶 <1 就不贡献）。
