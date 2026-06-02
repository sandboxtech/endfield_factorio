#!/usr/bin/env python3
# 一键执行两个生成器（改完 classes.lua 跑这一个即可）：
#   gen_set_classes.py  → set_classes.txt（/sc 热更指令）+ 同步 zh-CN 职业名
#   gen_item_values.py  → scripts/item_values.lua（物品价值）+ class_values.txt（职业分析）
# 用法：python3 gen.py            # 全部生成
#       python3 gen.py --check     # 两个都只校验是否同步
#       python3 gen.py --rebuild   # 价值脚本重扫 Factorio 缓存(慢)；对 set_classes 无影响
# 透传参数给两个子脚本；任一失败则整体非 0 退出。
import subprocess, sys, os

ROOT = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
rc = 0
for script in ('gen_set_classes.py', 'gen_item_values.py'):
    print(f'\n===== {script} =====')
    r = subprocess.run([sys.executable, os.path.join(ROOT, script)] + args)
    rc = rc or r.returncode

sys.exit(rc)
