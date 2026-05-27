# 手动测试流程

针对货币/市场/在线金币/火箭惩罚/跃迁等主要功能的逐步手测清单。
按模块顺序执行即可覆盖核心路径。**单人游戏里玩家 index = 1**，下文命令均按 1 写。

## 0. 前置准备

1. **备份存档**：本流程会用控制台 `/c` 改 storage 数据，且 `/c` / `/cheat` 会**永久关闭本存档成就**。建议先复制一份存档。
2. 用本场景新建/载入一局（地图选 endfield_factorio 场景）。
3. 开作弊：控制台输入
   ```
   /cheat all
   ```
   （给齐全部科技 + 进入作弊模式，方便建造/补给。注意每次跃迁 `force.reset()` 会清空科技，跃迁后如需建造请重跑一次。）
4. 想随时看自己的数据：
   - 鼠标悬停左上角 [img=virtual-signal/signal-science-pack] **🧪 按钮** → 能力面板 tooltip（含每瓶 `Lv. 当前/升级经验` 与在线金币行）。
   - `/inspect` 打印自己的被动加成 + 科技瓶经验。
   - `/exp` 打印自己的科技瓶经验。
   - `/life` 显示距离下次自动跃迁剩余时间。

---

## A. 起手物资与首次复活发放

> 验证：每个世界首次复活只发**护甲 + 5 建设机器人 + 货币**，不再塞建筑。

1. 新局开局（或 `/reset` 后复活）。
2. 打开背包，预期：
   - 护甲槽：modular-armor，内含 1 个人型机器人端口 + 4 太阳能 + 1 电池。
   - 背包：5 个建设机器人。
   - 新号（无经验/无在线统计）**没有**任何科技瓶/金币。
3. ✅ 通过条件：没有出现成品建筑（矿机/组装机等）直接进背包。

---

## B. 货币曲线：品质科技瓶（按经验）

> 验证：经验 → 品质瓶子的 √ 阶梯曲线、UI 等级显示、跃迁后实物发放、防爆背包。

1. 给自己灌入红瓶经验（automation）。先测"刚进绿瓶"边界 20110：
   ```
   /c storage.science_exp = storage.science_exp or {}; storage.science_exp[1] = storage.science_exp[1] or {}; storage.science_exp[1]['automation-science-pack/normal'] = 20110
   ```
2. 悬停 🧪 按钮，找到 automation 那一行，预期：`Lv.201 · …→ [uncommon]`
   （20100 经验填满 200 normal，多出的 10 经验进 uncommon 第 1 个，故 Lv.201）。
3. `/reset` 触发跃迁 → 等待/点击复活。
4. 复活后查背包，预期：**200 个 normal 红瓶 + 1 个 uncommon 红瓶**（各占 1 格）。
5. 边界对照表（设好经验后看 🧪 或跃迁后看背包）：

   | 设定经验 | 预期奖励 |
   | --- | --- |
   | `10` | 4 个 normal |
   | `20100` | 200 normal（1 整组） |
   | `20110` | 200 normal + 1 uncommon |
   | `221100` | 200 normal + 200 uncommon |

6. **防爆背包**：给所有 12 种瓶子灌满（每种都能拿满 5 品质 = 5 组）：
   ```
   /c storage.science_exp = storage.science_exp or {}; storage.science_exp[1] = {}; for _,p in pairs({'automation-science-pack','logistic-science-pack','military-science-pack','chemical-science-pack','production-science-pack','utility-science-pack','space-science-pack','metallurgic-science-pack','electromagnetic-science-pack','agricultural-science-pack','cryogenic-science-pack','promethium-science-pack'}) do storage.science_exp[1][p..'/normal'] = 1e12 end
   ```
   `/reset` 复活后预期：货币占用约 **60 格**（12 瓶 × 5 品质，各 1 组），背包（约 80 格）**不溢出、地上不掉落物品**。
   ✅ 通过条件：没有物品掉到地面。

---

## C. 在线金币（只看在线，不看挂机）

> 验证：在线统计 → 品质金币（normal/uncommon/rare），数量 = floor(√统计)。

1. 灌入在线统计：
   ```
   /c storage.player_stats = storage.player_stats or {}; storage.player_stats[1] = storage.player_stats[1] or {}; storage.player_stats[1].online_minutes = 10000; storage.player_stats[1].online_research = 2500; storage.player_stats[1].online_warps = 100
   ```
2. 悬停 🧪 按钮，末尾三行预期：
   - [item=coin] 在线分钟 · 10000 · **100**（√10000）
   - [item=coin,quality=uncommon] 在线研究科技 · 2500 · **50**
   - [item=coin,quality=rare] 在线跃迁次数 · 100 · **10**
3. `/reset` 复活后查背包，预期：100 normal 金币 + 50 uncommon 金币 + 10 rare 金币。
4. **反挂机验证**：站着别动 ≥1 分钟（保持在线），`/inspect` 看 `online_minutes` 仍在涨（在线即计，不要求挂机）。

---

## D. 市场购买（含品质 / 买不起 / 背包满）

> 验证：Nauvis 出生点市场实体、自定义商店 GUI、付 Q 品质货币得 Q 品质物品。

1. 先备好货币：跑一遍 B、C 的灌数据 + `/reset`，复活后身上有各品质瓶子 + 金币。
2. 复活点附近找到 **市场实体**（出生点，地图已自动 chart）。走过去按 **E**（或点击）打开 → 应弹出自定义商店框（标题"装备 · 建筑市场"），而非原版交易界面。
3. **建筑（用对应品质瓶子买）**：在 automation 区，点 normal 列的电力矿机按钮，预期：扣 5 个 normal 红瓶，背包 +1 normal 矿机；区标题余额实时刷新。
4. **品质匹配**：点 uncommon 列同物品，预期得到 **uncommon** 品质的矿机（付 uncommon 瓶子）。
5. **装备（用金币买）**：装备区点 normal 列外骨骼，扣 10 normal 金币得 normal 外骨骼。
6. **普罗米修斯兑金币**：promethium 区可用普罗米修斯瓶按品质换 coin（epic/legendary 金币唯一来源）。
7. **买不起**：点一个余额不足的品质列，预期：物品上方飘红字"货币不足"，不扣费。
8. **背包满**：把背包塞满（`/cheat all` 给一堆物品或捡垃圾填满），再买，预期：飘字"背包已满"，**货币退回不丢失**。
9. **关闭**：点右上 ✖ 或按 **ESC**，商店框关闭。
10. **不可摧毁**：尝试用武器打市场 / 拆市场，预期：打不掉、挖不动（`destructible=false` + `minable=false`）。

---

## E. 发射火箭惩罚

> 验证：每次发射火箭 → 自动跃迁时间 -1 分钟 + 全员公告 + 打印载荷。

1. 记录当前剩余时间：`/life`。
2. 准备一枚可发射的火箭：
   - 简便法：`/editor` 进编辑器，放 `rocket-silo`，喂满 rocket-part 让火箭造好，往火箭货舱放点货（如卫星/任意物品），退出编辑器。
   - 或对已造好火箭的发射井执行：
     ```
     /c local s = game.player.surface.find_entities_filtered{name='rocket-silo'}[1]; if s then s.launch_rocket() end
     ```
3. 发射后预期，聊天栏出现：
   `🚀 有人发射火箭！自动跃迁时间 -1 分钟（剩余 X 小时）\n载荷：[载荷物品列表]`
4. 再 `/life`，预期剩余时间比步骤 1 **少约 1 分钟**。
5. 连发多枚，预期每枚各 -1 分钟（剩余时间可被压到 0 触发立即跃迁——惩罚生效）。

---

## F. 跃迁与倒计时

1. `/life` 看剩余；研究任一"含 -science-pack"的科技（非红瓶 trigger），预期跃迁时长 +1 小时并公告。
2. 等倒计时到撤离阈值（30/20/10/5/3/1 分钟）会公告提醒。
3. 倒计时归零或 `/reset` → 全星球清空重建、玩家死亡复活、飞船保留一周期、出生点重放市场。
4. 点击左上角 [run] 按钮 = 自杀回母星（卡死脱困用）。

---

## G. 在线采样（on_nth_tick 合并验证）

> 历史 bug：player_stats 与 tick 都注册 on_nth_tick(3600)，后者覆盖前者导致 online_minutes 永不增长。已合并到 tick.lua。

1. 全新存档（或 `/c storage.player_stats[1].online_minutes = 0`）。
2. 保持在线挂着 **2~3 分钟**（真实时间）。
3. `/inspect` 看 `online_minutes`，预期 ≈ 经过的分钟数（说明采样真的在跑）。
   ✅ 通过条件：数值在涨；失败说明 on_nth_tick 又被覆盖。

---

## H. 作弊 / 管理命令清单

游戏内场景命令（控制台调用即视作管理员）：

| 命令 | 权限 | 作用 |
| --- | --- | --- |
| `/reset` | 管理员 | 手动触发跃迁 |
| `/players_gui` | 管理员 | 重绘所有玩家 HUD |
| `/exp_clear` | 管理员 | 清空所有玩家科技瓶经验 |
| `/life` | 所有人 | 距下次自动跃迁剩余时间 |
| `/exp` | 所有人 | 打印自己累计科技瓶经验 |
| `/inspect <名字>` | 所有人 | 查看某玩家被动/经验（省略=自己） |

常用 Factorio 作弊（`/c` 或 `/cheat`，会关成就）：

```
/cheat all                       -- 全科技 + 作弊模式
/editor                          -- 进/出地图编辑器
/c game.player.character.health = 1e9         -- 回血/无敌测试
/c game.speed = 4                -- 加速跑流程（测倒计时/采样别加速）

-- 设科技瓶经验（货币一）：键 = '瓶名/品质'
/c storage.science_exp = storage.science_exp or {}; storage.science_exp[1] = storage.science_exp[1] or {}; storage.science_exp[1]['logistic-science-pack/normal'] = 20110

-- 设在线统计（货币二/被动）：
/c storage.player_stats = storage.player_stats or {}; storage.player_stats[1] = storage.player_stats[1] or {}; storage.player_stats[1].online_minutes = 10000

-- 直接发射现成火箭（测惩罚）：
/c local s = game.player.surface.find_entities_filtered{name='rocket-silo'}[1]; if s then s.launch_rocket() end

-- 给自己金币（跳过赚取，直接测市场）：
/c game.player.insert{name='coin', count=500, quality='rare'}
```

> 设完 storage 数据后，多数发放发生在**跃迁复活时**（`/reset` → 复活）。直接灌背包则用
> `game.player.insert{...}`。

---

## 排错速查

- **商店打开的是原版交易界面而不是自定义框** → `on_gui_opened` 没识别到市场，检查 `storage.market_unit_number` 是否等于该市场 unit_number（市场被重建后会更新）。
- **复活没发货币** → 确认是"本世界首次复活"（`storage.last_respawn_run[1]` 应等于当前 `storage.run`）；同一世界重复复活不重发。
- **online_minutes 不涨** → on_nth_tick 又被某模块重复注册覆盖（应只在 tick.lua 注册）。
- **品质瓶子/金币插不进或品质不对** → 确认该 quality 名拼写（normal/uncommon/rare/epic/legendary）。
- **载荷显示 —** → 火箭货舱为空（发射前没放货）。
