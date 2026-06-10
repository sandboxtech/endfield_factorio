# /diff 全局参数说明

`/diff`（管理员 HUD 红按钮，仅 `storage.gen_diff_whitelist` 白名单内的管理员可见）弹出一个对比窗：
列出所有全局参数的**当前值 vs 默认值**，改过的高亮 + 标注默认。先跑一次 `ensure_all`（补默认/迁移）再展示。

## 怎么改

- 控制台输入：`/c storage.<参数名> = <值>`
  例：`/c storage.loot_density = 2`、`/c storage.encounter_base.material = 0.06`
- 嵌套表参数在 diff 里显示成 `表名.子键`（行文即 `/c` 路径），例 `encounter_base.material`、`loot_planet_mul.gleba`。
- **何时生效**：绝大多数参数在**下次跃迁**或**下次区块生成**时读取生效（世界生成/据点/敌人/计时类都是）。少数即时（如 `chat_bubble_enabled`）。
- **恢复默认**：`/c storage.<参数名> = nil` 后下次 `ensure` 重建；整张表恢复用 `/c storage.encounter_base = nil` 等。
- 改动**持久存档、多人同步**。

---

## 标量参数 `storage.<键>`

### 矿物 / 资源生成
| 参数 | 默认 | 说明 |
|---|---|---|
| `richness_multiplier` | 16 | 矿更富（每格储量倍率） |
| `size_multiplier` | 4 | 矿脉更大（rail world 基准 ×4） |
| `frequency_multiplier` | 2 | 矿脉出现频率 |
| `local_specialty_multiplier` | 0.25 | 本地特产矿权重 |
| `tech_price_multiplier` | 2 | 科技成本倍率（每轮设到 `game.difficulty_settings`） |

### 星球形状 / 半径
| 参数 | 默认 | 说明 |
|---|---|---|
| `radius_standard` | 512 | 标准基准半径。真实半径 = clamp(standard × random_exp(2), min, max) |
| `radius_min` | 256 | 真实半径下限 |
| `radius_max` | 1024 | 真实半径上限 |
| `planet_eccentricity` | 0.25 | 椭圆离心系数：越小越圆，0=全圆。长短轴比最大 (1+e):(1−e) |
| `edge_noise_start` | 0.75 | 边界噪声起作用的归一化半径：小于它必为陆地，向 1 升满。调小=虚空洞更深入，接近 1=近纯椭圆 |

### 出生点
| 参数 | 默认 | 说明 |
|---|---|---|
| `spawn_offset_pow` | 2 | 出生点偏离中心的非线性指数：越大越贴中心；1=线性；<1 偏外缘 |
| `spawn_offset_max` | 0.5 | 出生点偏离中心的最大归一化距离（还会钳进陆地内） |
| `spawn_safe_frac` | 0.25 | 出生安全盘半径 = 半短轴×此值：盘内绝不铺虚空（硬保证） |

### 悬崖（nauvis/vulcanus/fulgora/gleba）
| 参数 | 默认 | 说明 |
|---|---|---|
| `cliff_easy_chance` | 0.35 | 【稀崖世界】概率：行距更大、缺口更多更好走。0=关 |
| `cliff_hard_chance` | 0.1 | 【密崖世界】概率：行距更小、更连续（温和上限）。0=关 |

### Vulcanus 巨虫领地
| 参数 | 默认 | 说明 |
|---|---|---|
| `demolisher_none_chance` | 0.15 | 全图无巨虫概率 |
| `demolisher_small_chance` | 0.2 | 全图只刷小型概率 |
| `demolisher_mid_chance` | 0.15 | 只刷小型+中型概率 |
| `min_territory_size` | 120 | 领地门槛上限：每轮在 [10,此值] 随机；越高巨虫越稀 |
| `territory_cull_max` | 0.5 | 领地删除率上限 A：每轮删除率 p=A×random^B。0=关 |
| `territory_cull_pow` | 2 | 领地删除率指数 B：越大越偏 0（大概率几乎不删） |

### 昼夜
| 参数 | 默认 | 说明 |
|---|---|---|
| `day_len_spread` | 8 | 昼夜长短浮动界 A：每天 tick = 原版 × A^(t³)。1=不浮动 |
| `day_shape_chance` | 0.25 | 昼夜占比重塑概率：命中时白天占比 20%~80% 随机（原版 50%） |
| `platform_lifetime` | 100 | （平台相关计时常量） |
| `difficulty` | 1 | 难度基准常量 |

> 夜晚最低亮度（`min_brightness`，已抬到 0.3~0.45）写在 `surface.lua`，每轮随机、不在 diff 标量里。

### 世界风味概率（每轮是否触发某种特殊世界）
| 参数 | 默认 | 说明 |
|---|---|---|
| `prob_ground_tint` | 2 | 染地世界出现概率乘数（0=关） |
| `prob_tile_remap` | 3 | tile 替换世界概率乘数 |
| `prob_obstacle_remap` | 1 | 障碍换障碍世界（0=关） |
| `prob_fluid_remap` | 1 | 流体资源互换世界（0=关） |
| `tile_remap_rules` | 6 | tile 替换世界最多几条规则 |
| `replicant_mul` | 1 | 复制虫概率乘数：实际冒虫率 = 本轮 danger × 此值（0=关） |
| `debug` | true | 向管理员打印每次世界生成的属性 |

### 敌人（伤害 / 进化 / 巢穴）
| 参数 | 默认 | 说明 |
|---|---|---|
| `enemy_dmg_max` | 12 | 敌人武器伤害上限倍率：每种伤害类型各自随机 [0,此值]，线性递减（12=最高 +1200%） |
| `enemy_evo_max` | 1 | 敌人进化度上限：evo = min(1, 此值×(1−√r))。>1 更多猛虫、<1 压低 |
| `enemy_freq_spread` | 4 | 巢穴 frequency 浮动幅度（对数三角，值域 [1/n,n]）。越大世界间频率差越极端 |
| `enemy_size_spread` | 4 | 巢穴 size 浮动幅度（同上，独立掷） |
| `enemy_freq_mul` | 1 | 巢穴 frequency 全局倍率（在 spread 上再乘）：>1 更密 |
| `enemy_size_mul` | 1 | 巢穴 size 全局倍率：>1 团更大 |
| `enemy_invincible_chance` | 1 | 敌方变电站/避雷针无敌概率（1=全无敌，0=全可摧毁） |

### 杀虫巢掉落
| 参数 | 默认 | 说明 |
|---|---|---|
| `nest_coin` | 6 | 杀死虫巢掉落金币数（0=不掉） |
| `nest_tech_chance_min` | 0.001 | 杀虫巢"获得随机科技"概率下限（每轮在 min~max 随机滚定本世界值） |
| `nest_tech_chance_max` | 0.01 | 同上的上限。两值相等=固定概率；都设 0=关 |

### 据点遭遇 & 奖励箱
| 参数 | 默认 | 说明 |
|---|---|---|
| `loot_density` | 1 | **据点出现率全局乘数**（所有类一起乘）：2 更多、0.5 更少、0 不刷。各类基础频率见下方 `encounter_base` |
| `chest_count_pow` | 2 | 每个据点放几个箱的指数 floor(1+4·random^此值·riches)：越大越偏少箱 |
| `chest_map_tags` | true | 据点生成时在中心打一个箱型图标地图标签（无文本）。false=不打 |
| `outpost_combat` | true | 据点战斗规则：①炮塔杀友军→补弹补电；②守卫全灭→摧毁变电站/EEI。false=关 |
| `outpost_pave_prob` | 0.5 | 据点强制铺地概率（放不下时先铺地砖再硬放）。0=关，1=全强制 |

> 奖励箱**填充量**（物流箱/设备箱填几格、每格数量指数）已整合进命名空间 `storage.fill.*`，见下方「奖励箱填充量」。
> 所有箱型（钢/铁/木/五色物流）统一走 `fill_chest` 填充：钢箱=选 1~3 种 + 近装满 + 整堆；木箱=1~2 件 + exp4 + 宝箱品质。

### 永续（无限）箱属性
| 参数 | 默认 | 说明 |
|---|---|---|
| `perpetual_operable` | false | 可打开 GUI/重配 |
| `perpetual_minable` | false | 可手挖拆走 |
| `perpetual_destructible` | false | 可被摧毁（开了 fulgora 闪电/火炮会劈烂它） |

### 背包
| 参数 | 默认 | 说明 |
|---|---|---|
| `inv_slots_bonus` | 50 | 全员基础背包格加成（每轮设到 force）。`/invbonus <玩家> <数>` 按人**覆盖**以此为基准 |

### 跃迁计时 & 投票
| 参数 | 默认 | 说明 |
|---|---|---|
| `warp_initial_minutes` | 30 | 每轮开局跃迁倒计时（分钟） |
| `warp_extend_default_minutes` | 60 | 完成未列入 `warp_extend_minutes` 的瓶科技 → 延长分钟 |
| `warp_vote_target_minutes` | 5 | `/warp` 投票通过后，倒计时设为剩余的分钟数 |
| `warp_vote_divisor` | 5 | 投票阈值除数：净同意 > ceil(在线人数/此值) 才推进（越大越易过） |
| `action_cd_minutes` | 3 | 投票+传送共享冷却（分钟） |
| `travel_enabled` | true | 前往星球总开关。每外星还要各过 `travel_chance` |

### 复活
| 参数 | 默认 | 说明 |
|---|---|---|
| `respawn_ticks` | 600 | 默认复活等待（脚本死亡/环境死亡）：600 tick=10 秒 |
| `respawn_ticks_by_enemy` | 1800 | 被敌方打死：1800 tick=30 秒 |
| `respawn_step_ticks` | 300 | 跃迁致死：离出生星球每远一个多等的 tick（300=5 秒） |

### 星星系统
| 参数 | 默认 | 说明 |
|---|---|---|
| `charge_max_hours` | 30 | 星星充能上限（游戏内小时，1 星星=1 分钟） |
| `star_extend_cost` | 300 | 花星星给倒计时延长一次的星星数 |
| `star_extend_minutes` | 10 | 每次延长加的分钟 |
| `star_extend_cap` | 60 | 每星系花星星延长的累计上限（分钟） |

> 投票花费的 base/mul/门槛/挂机阈值已整合进命名空间 `storage.star_vote.*`，见下方「投票花费·星星」。

### 职业 / 解锁
| 参数 | 默认 | 说明 |
|---|---|---|
| `class_cd_minutes` | 1 | 切换职业冷却（分钟，纯防刷消息） |
| `class_tech_stack` | true | 多职业指向同一无限科技：true=各 +1 级累加；false=固定第一级 |
| `grant_trigger_techs` | false | 开局是否赠送所有触发科技（捕获虫巢/扔物入太空那类） |
| `unlock_all_planets` | true | 开局自动解锁所有星球传送点（不点亮发现科技） |
| `blueprint_warps` | 1 | 解锁蓝图库/导入/红图所需跃迁次数（0=进服即解锁；会员/管理员恒解锁）。见 `/bpperm` 按人覆盖 |

### 玩家管理
| 参数 | 默认 | 说明 |
|---|---|---|
| `kill_on_leave` | true | 离线杀死角色（尸体/货物留当地，防外星捡货下线带回）。false=保留 |
| `player_cleanup_hours` | 32 | 跃迁时清理多少小时没上线的玩家对象（释放存档膨胀；经验/统计按名字存不丢） |
| `chat_bubble_enabled` | false | 玩家聊天头顶冒气泡 |

### 网络 / 飞船平台
| 参数 | 默认 | 说明 |
|---|---|---|
| `roboport_limit` | 10000 | 单个机器人网络最多 roboport 数，超出则摧毁刚放的并退还 |
| `platform_warp_mode` | 'stay' | 跃迁时飞船去向：`stay` 停原地 / `home` 回母星轨道暂停 / `random` 随机星球轨道暂停 |
| `max_platform_size` | 512 | 飞船最大尺寸（宽/高钳到此值）。0/nil=不限 |
| `max_platform_count` | 30 | 飞船最大数量，超出则销毁新成形平台并广播。0/nil=不限 |

### 世界荣誉榜
| 参数 | 默认 | 说明 |
|---|---|---|
| `hall_of_fame_enabled` | true | 总开关：false=不再记录新世界、隐藏按钮（已有记录保留） |
| `hall_of_fame_max` | 30 | 最大保留条数（按全员带走经验排序，超出裁队尾） |

---

## 命名空间分组的嵌套表（diff 里每子键一行，行文 = `/c` 路径）

### 遭遇频率·每类 `storage.encounter_base.<类>`
**各箱型据点每区块的基础出现率**（实际率 = 世界密度 × 此值 × `loot_density` × `loot_planet_mul[星球]`）。

| 子键 | 默认 | 说明 |
|---|---|---|
| `material` | 0.03 | 钢箱（材料）据点 |
| `equipment` | 0.015 | 铁箱（设备）据点 |
| `treasure` | 0.0075 | 木箱（宝箱）据点 |
| `perpetual` | 0.0075 | 永续无限箱据点 |
| `machine` | 0.0015 | 传说机器据点 |
| `empty` | 0.08 | 空据点（纯敌人，无箱） |
| `logi_active` | 0.004 | 主动供给箱（紫）据点 |
| `logi_passive` | 0.004 | 被动供给箱（红）据点 |
| `logi_storage` | 0.004 | 储物箱（黄）据点 |
| `logi_buffer` | 0.004 | 缓冲箱（绿）据点 |
| `logi_requester` | 0.004 | 请求箱（蓝）据点 |

> 这张表替代了旧的 `loot_density_<类>` 各类乘数（已删）。例：`/c storage.encounter_base.logi_requester = 0.01`。

### 宝箱密度·每星 `storage.loot_planet_mul.<星球>`
每星球据点出现率乘数（不含空据点）。

| 子键 | 默认 |
|---|---|
| `nauvis` | 1 |
| `vulcanus` | 1 |
| `fulgora` | 3 |
| `gleba` | 3 |
| `aquilo` | 3 |

例：`/c storage.loot_planet_mul.gleba = 5`。

### 前往概率·每星 `storage.travel_chance.<星球>`
每次跃迁各外星各自掷一次决定本轮能否前往（默认 1.0=恒开）。仅 4 个外星：`vulcanus / gleba / fulgora / aquilo`。
例：`/c storage.travel_chance.fulgora = 0.6`。

### 延长分钟·每瓶 `storage.warp_extend_minutes.<科技瓶>`
完成对应科技瓶的科技时，延长本世界跃迁倒计时的分钟数。

| 子键（科技瓶） | 默认分钟 |
|---|---|
| `automation-science-pack` | 30 |
| `logistic-science-pack` | 60 |
| `military-science-pack` | 60 |
| `chemical-science-pack` | 60 |
| `production-science-pack` | 60 |
| `utility-science-pack` | 60 |
| `space-science-pack` | 60 |
| `metallurgic-science-pack` | 60 |
| `electromagnetic-science-pack` | 60 |
| `agricultural-science-pack` | 60 |
| `cryogenic-science-pack` | 120 |
| `promethium-science-pack` | 120 |

未列入的瓶用 `warp_extend_default_minutes`（默认 60）。例：`/c storage.warp_extend_minutes['cryogenic-science-pack'] = 90`。

### 投票花费·星星 `storage.star_vote.<子键>`
跃迁/停留投票的星星花费随【本地图已游玩分钟】变化：`cost = base + mul × max(0, 已玩分钟 − thres)`，钳到 ≥0。

| 子键 | 默认 | 说明 |
|---|---|---|
| `base_warp` | 300 | 投跃迁票基础花费（门槛内恒为此值） |
| `base_stay` | 300 | 投停留票基础花费 |
| `mul_warp` | 1 | 跃迁票每分钟乘数（超门槛后越玩越贵） |
| `mul_stay` | -1 | 停留票每分钟乘数（超门槛后越玩越便宜，钳到 0） |
| `thres` | 10 | 花费门槛（分钟）：未超此值花费=base |
| `afk_min` | 30 | 挂机超此分钟的玩家不计入投票总人数 |

例：`/c storage.star_vote.base_warp = 500`。

### 奖励箱填充量 `storage.fill.<子键>`
据点奖励箱填几格、每格几个（数量=堆叠×random^exp；exp 越大每格越少）。五色物流箱共用 `logi_*`、铁(设备)箱 `equip_*`。

| 子键 | 默认 | 说明 |
|---|---|---|
| `logi_lo` / `logi_hi` | 8 / 18 | 五色物流箱填几格 |
| `logi_exp` | 2 | 五色物流箱每格数量指数 |
| `equip_lo` / `equip_hi` | 10 / 24 | 铁(设备)箱填几格 |
| `equip_exp` | 2 | 铁(设备)箱每格数量指数 |

例：`/c storage.fill.logi_hi = 30`。

---

## 不在 diff 标量里、但相关的配置

这些是表/集合型，需直接 `/c` 改（diff 不展开或只部分展开）：

- `storage.gen_diff_whitelist`：能看到 `/gen`、`/diff`（含本窗）的管理员白名单。默认 `{hncsltok=true}`。
  增删：`/c storage.gen_diff_whitelist['玩家名'] = true / nil`。
- `storage.loot_weights[箱型][类]`：箱子里**偏向掉哪类货**（各箱型一张权重表，含五色物流箱 `logi_*`）。
  例：`/c storage.loot_weights.logi_requester.military = 300`。
- `storage.loot[类]`：每类里**有哪些具体物品**名单。
- `storage.bp_override[玩家名]` = true/false：按人覆盖蓝图/受限权限（见 `/bpperm`）。
- `storage.player_inv_bonus[玩家名]` = 数：按人覆盖背包格总数（见 `/invbonus`）。
- `storage.loot_noise[星球]`：据点空间聚簇噪声（amp/seed），让据点成片密/疏。

## 三种"权重/密度"别搞混
| 想配什么 | 改哪 |
|---|---|
| 某箱型据点**多久冒一个**（出现率） | `storage.encounter_base.<类>` + `loot_density` + `loot_planet_mul.<星球>` |
| 箱子里**偏向掉哪类货** | `storage.loot_weights.<箱型>.<类>` |
| 某类里**有哪些具体物品** | `storage.loot.<类>` |
