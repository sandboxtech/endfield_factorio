# 异星工厂·无尽跃迁 (Endless Warptorio)

Factorio 2.0 + Space Age 自定义多人场景：建好工厂，跃迁奔向下一个星系，一局接一局，永远有新地图。

Endless Warptorio: a custom multiplayer scenario for Factorio 2.0 + Space Age. Build up, warp to a fresh star system, repeat. Available in 11 languages.

## 核心玩法

- **跃迁倒计时**：顶部倒计时归零就跃迁去新世界（起步约 30 分钟）。研究瓶子科技延长倒计时，发射火箭、投票则缩短它。
- **一切归零**：每次跃迁，整个旧星系被抛弃，工厂、科技、矿物全部留下。所有星球清空重建，玩家死亡复活。
- **两条永久进度**：
  1. **科技瓶经验**：跃迁瞬间，背包里的科技瓶变成经验（每瓶 1 点、品质越高越多，12 种瓶各自独立）。经验越多等级越高，开局拿到的职业物资越多。
  2. **角色技能**：手搓、移动、挖矿做得越多，对应速度越快，跨世界保留。
- **职业系统**：几十种专精职业（采矿/冶炼/物流/战斗/星球开拓……），决定开局白送什么、练哪种瓶发哪种货。HUD 按钮随时切换。
- **飞船有限命数**：太空平台跟随你跨越星系，船名前缀显示还能随你跃迁几次，次数用完即报废。
- **世界变体**：每轮每星球随机滚地表换皮、染地、据点遭遇（奖励箱+守卫/传说建筑）、障碍互换、流体喷口突变、昼夜/形状/资源档位等，大概率寻常、小概率新奇，反复跃迁不重样。
- **双货币**：金币（开局按在线时长发，市场买装备）+ 星星（随时间恢复，投票/延长倒计时用）。

## 安装

1. 需要 Factorio 2.0 与 Space Age DLC。
2. 把本仓库放进 Factorio 的 `scenarios/` 目录（Windows：`%APPDATA%\Factorio\scenarios\endfield_factorio`）。
3. 新游戏 → 场景 → 选择本场景。支持单人，但按多人服设计。

也可以用 `python gen_scenario.py` 打出一个只含运行时文件的干净场景包。

## 项目结构

```
control.lua          场景入口，按顺序 require 各模块
info.json            场景元数据
locale/              11 种语言本地化（de/en/es-ES/fr/ja/ko/pl/pt-BR/ru/zh-CN/zh-TW）
scripts/             全部游戏逻辑（事件总线/跃迁重置/职业/经验/世界变体/据点/GUI…）
gen_*.py             开发工具链（非运行时）：职业热更指令、物品价值表、场景打包
```

模块职责、storage 字段、数据流与易错点的完整说明见 [PROJECT.md](PROJECT.md)。

## 开发

- 改完 `.lua` 用 `luac -p` 做语法体检。
- 改完 `classes.lua` 跑 `gen_set_classes.py`（生成热更指令、同步职业名本地化）；平衡参考跑 `gen_item_values.py`。
- **热更范围**：`storage` 数据（职业表、各 `/c storage.x=` 旋钮）可不停服热改；代码改动必须重载存档才生效（多人服无法热重载场景代码）。
- 几乎所有概率/密度/开关都是 `storage` 旋钮，默认值集中在 `constants.ensure_defaults`，游戏内 `/c storage.xxx=N` 即时调。

## 反馈

- BUG 反馈 QQ 群：293280221
- Issues / PR：https://github.com/sandboxtech/endfield_factorio
