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
| `respawn_gifts.lua` | 每个世界（`storage.run`）首次复活时发放起手装备 + 按科技经验等级发放物品。物品表在文件顶部，可手动编辑。 |
| `passives.lua` | 科技经验 → character 被动加成（手搓/移速/挖矿/HP 等）；曲线为 log 加和。 |
| `science_exp.lua` | 跃迁前扫描玩家背包里的科技瓶，按 `每组 × 品质倍率` 累加进 `storage.science_exp`。 |
| `research.lua` | 研究完含 `-science-pack` 名字的科技时，把本轮跃迁倒计时延长 1 小时。 |
| `surface.lua` | 跃迁后随机生成各星球：地图设定、资源分布、圆形边界。 |
| `reset.lua` | 跃迁主流程：清场 → 收集经验 → 杀玩家 → 清星球 → 重置科技 → 随机参数。 |
| `tick.lua` | 周期性事件：自动跃迁倒计时；点击 HUD 自杀脱困。 |
| `commands.lua` | 管理/调试命令（控制台调用视作管理员）。 |
| `gui.lua` | 左上角 HUD：轮次、星系词条、经验加成、在线名册、管理员按钮。 |

## 关键 storage 字段

- `storage.run`：当前世界序号，从 1 开始。每次 `reset.reset()` +1。
- `storage.run_start_tick`：本轮跃迁开始时的 tick。
- `storage.warp_hours`：本轮剩余跃迁时长，研究科技瓶相关科技可延长。
- `storage.platform_age[idx]`：飞船已经历的跃迁数；超过 `storage.platform_lifetime` 时摧毁。
- `storage.science_exp[player_index][pack_name '/' quality] = exp`：累计科技瓶经验。
- `storage.last_respawn_run[player_index]`：玩家上次复活时的 `storage.run`，用于判定"本世界是否首次复活"。
- `storage.traits`：左上 HUD 列出的本轮星系词条（本地化字符串数组）。
- 地图参数：`storage.richness / frequency / size / radius / difficulty / local_specialty_multiplier`。

## 数据流速览

```
跃迁前:
    各模块 -> storage           (经验累计、飞船年龄等)

reset.reset():
    science_exp.collect(每玩家)  -> storage.science_exp
    kill / clear 玩家
    surface.clear -> surface.lua 重新生成
    force.reset(科技清零)
    随机污染/小行星/腐烂参数
    passives.apply(在线玩家)

on_player_respawned:
    passives.apply(player)
    若 storage.run != last_respawn_run[idx]:
        respawn_gifts.on_first_respawn(player)
```

## 经验 → 等级

`level = 1 + floor(log10(exp))`，`exp < 1` 时记为 0 级。`respawn_gifts.lua` 中的物品表
`gifts_per_level[pack][level]` 列出每级新增的物品；玩家达到 N 级时累计发放 1..N 级所有物品。
