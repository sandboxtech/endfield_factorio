# 手动测试流程

针对货币/市场/在线奖励/火箭惩罚/跃迁等主要功能的逐步手测清单。
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
   - 鼠标悬停左上角 [img=virtual-signal/signal-science-pack] **🧪 按钮** → 能力面板 tooltip（含每瓶 `Lv. 当前/升级经验` 与在线奖励瓶子行）。
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

## B. 货币一曲线：携带经验 → epic/legendary 瓶子（独立 √ 曲线）

> 验证：`epic = floor(√exp)`（最多 4 组/800）、`legendary = floor(√exp/10)`（最多 1 组/200），两档**独立**。
> 普通瓶可量产，故货币一不发 normal/uncommon/rare。经验来源瓶子的品质不影响奖励品质。

1. 给自己灌入红瓶经验（automation）。先测"刚进 legendary"边界 100：
   ```
   /c storage.science_exp = storage.science_exp or {}; storage.science_exp[1] = storage.science_exp[1] or {}; storage.science_exp[1]['automation-science-pack/normal'] = 100
   ```
2. 悬停 🧪 按钮，找到 automation 那一行，预期：`Lv.11 · 100/121 → [epic]`
   （√100=10 epic + √100/10=1 legendary，共 11；下一个 epic 在 exp=11²=121）。
3. `/reset` 触发跃迁 → 等待/点击复活。
4. 复活后查背包，预期：**10 个 epic 红瓶 + 1 个 legendary 红瓶**。
5. 边界对照表（设好经验后看 🧪 或跃迁后看背包）：

   | 设定经验 | epic | legendary |
   | --- | --- | --- |
   | `10` | 3 | 0 |
   | `100` | 10 | 1 |
   | `10000` | 100 | 10 |
   | `640000` | 800（4 组满） | 80 |
   | `4000000`+ | 800（4 组满） | 200（1 组满） |

6. **防爆背包**：给所有 12 种瓶子灌中等经验（每种约 10000 → 各 100 epic + 10 legendary）：
   ```
   /c storage.science_exp = storage.science_exp or {}; storage.science_exp[1] = {}; for _,p in pairs({'automation-science-pack','logistic-science-pack','military-science-pack','chemical-science-pack','production-science-pack','utility-science-pack','space-science-pack','metallurgic-science-pack','electromagnetic-science-pack','agricultural-science-pack','cryogenic-science-pack','promethium-science-pack'}) do storage.science_exp[1][p..'/normal'] = 10000 end
   ```
   `/reset` 复活后预期：每瓶 100 epic + 10 legendary（各 <1 组），12 瓶共约 24 格，不溢出。
   理论极值：每瓶最多 4+1=5 组 → `12 瓶 × 5 = 60 组` ≤ 背包约 80 格，**任何情况都不爆背包**。

---

## C. 在线奖励品质瓶子（只看在线，不看挂机）

> 验证：在线统计 → 品质科技瓶（uncommon/rare/epic，**不发可量产的 normal**），数量 = floor(√统计)。
> 默认映射（`constants.online_rewards` 可改）：分钟→uncommon 红瓶、研究→rare 绿瓶、跃迁→epic 黑瓶。

1. 灌入在线统计：
   ```
   /c storage.player_stats = storage.player_stats or {}; storage.player_stats[1] = storage.player_stats[1] or {}; storage.player_stats[1].online_minutes = 10000; storage.player_stats[1].online_research = 2500; storage.player_stats[1].online_warps = 100
   ```
2. 悬停 🧪 按钮，末尾三行预期（默认配置）：
   - [item=automation-science-pack,quality=uncommon] 在线分钟 · 10000 · **100**（√10000）
   - [item=logistic-science-pack,quality=rare] 在线研究科技 · 2500 · **50**
   - [item=military-science-pack,quality=epic] 在线跃迁次数 · 100 · **10**
3. `/reset` 复活后查背包，预期：100 uncommon 红瓶 + 50 rare 绿瓶 + 10 epic 黑瓶（**没有 normal 瓶**）。
4. **反挂机验证**：站着别动 ≥1 分钟（保持在线），`/inspect` 看 `online_minutes` 仍在涨（在线即计，不要求挂机）。

---

## D. 市场购买（13 个市场 / 品质 / 不可摧毁）

> 验证：出生点 13 个原版 market，每个只卖一种货币，付 Q 品质货币得 Q 品质物品。

> ⚠ `market.lua` 的 `M.sections` 现在是**占位模板**：除普罗米修斯市场（已预填兑金币）外，
> 其余市场默认**空货架**。要测购买，先在 `M.sections` 按"每瓶卖其科技阶段商品"填好货物。

1. 先备好货币：跑一遍 B、C 的灌数据 + `/reset`，复活后身上有 epic/legendary 瓶子（货币一）+ uncommon/rare/epic 瓶子（在线/货币二）。**没有金币**（金币只能在普罗米修斯市场换）。
2. 出生点**北面**（-Y 方向，地图已自动 chart）应看到 **13 个市场**：12 个科技瓶市场排 3 列 × 4 行，金币市场在最上方居中。布局（相对出生点的格偏移，北=负 Y）：

   ```
                       [金币] (0,-18)
        [自动化] [物流] [军事]        y=-15   x = -3, 0, 3
        [化工]   [生产] [通用]        y=-12
        [太空]   [冶金] [电磁]        y=-9
        [农业]   [低温] [普罗米修斯]  y=-6
                  ★出生点(0,0)
   ```
   （顺序 = `constants.science_packs`；每个市场 3×3 格、间距 3 格。）
3. （填好货物后）走到 **自动化市场**，按 **E** 打开 → 原版交易界面，列出你填的物品 × 5 品质条 offer。
4. **付 Q 得 Q**（关键）：用 **epic** 红瓶买 → 得 **epic** 物品；用 legendary 红瓶买 → 得 legendary 物品。确认产出品质 == 付款品质。
5. **普罗米修斯市场**：用普罗米修斯瓶按品质换 coin（**金币唯一来源**；epic 普罗米修斯瓶 → epic 金币）。
6. **金币市场**（最上方）：先在步骤 5 换到金币，再买装备（需你先在 `M.sections` 的 coin 项填装备清单）。
7. **只收一种货币**：确认自动化市场只接受红瓶、不接受其它瓶/金币。
8. **买不起**：货币不足时该 offer 在原版界面无法购买（置灰）。
9. **不可摧毁**：用武器打市场 / 尝试拆，预期打不掉、挖不动（`destructible=false` + `minable=false`）。

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

- **市场没出现 / 数量不足 13 个** → `market.place_on_nauvis` 在出生点放置失败（地形/碰撞）；确认出生点附近是陆地，必要时调大 `request_to_generate_chunks` 半径。
- **买到的物品品质不是所付品质** → `add_market_item` 的 give-item offer 没带上 `quality`；确认你的版本支持（2.0.60+ 支持）。
- **复活没发货币** → 确认是"本世界首次复活"（`storage.last_respawn_run[1]` 应等于当前 `storage.run`）；同一世界重复复活不重发。
- **online_minutes 不涨** → on_nth_tick 又被某模块重复注册覆盖（应只在 tick.lua 注册）。
- **品质瓶子/金币插不进或品质不对** → 确认该 quality 名拼写（normal/uncommon/rare/epic/legendary）。
- **载荷显示 —** → 火箭货舱为空（发射前没放货）。
