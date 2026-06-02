#!/usr/bin/env python3
# 打包场景：把 5 个可玩组件复制成一份干净的 endfield_factorio/ 目录。
#   组件：scripts/  locale/  control.lua  description.json  info.json
#   只含这 5 项 → 自动排除根目录的 gen_*.py / set_classes.txt / class_values.txt / .value_cache.json / *.md 等开发文件。
# 用法：
#   python3 gen_scenario.py            # 输出到 <项目>/endfield_factorio/
#   python3 gen_scenario.py --desktop  # 输出到 桌面/endfield_factorio/（带任意参数即放桌面）
import os, sys, re, shutil

ROOT = os.path.dirname(os.path.abspath(__file__))
NAME = 'endfield_factorio'
ITEMS = ['scripts', 'locale', 'control.lua', 'description.json', 'info.json']

# 目标基准：带参数 → 桌面（Windows 桌面，从 /mnt/c/Users/<用户> 推断）；否则项目目录内
if len(sys.argv) > 1:
    m = re.search(r'^(/mnt/[a-z]/Users/[^/]+)', ROOT)
    base = os.path.join(m.group(1), 'Desktop') if m else os.path.expanduser('~/Desktop')
    if not os.path.isdir(base): sys.exit(f'找不到桌面目录：{base}')
else:
    base = ROOT
dest = os.path.join(base, NAME)

# 源文件齐全性校验
missing = [i for i in ITEMS if not os.path.exists(os.path.join(ROOT, i))]
if missing: sys.exit('缺少组件，无法打包：' + ', '.join(missing))

# 安全：拒绝 dest 等于项目自身（避免自我覆盖）
if os.path.abspath(dest) == ROOT: sys.exit('目标与项目目录相同，已中止。')

# 清旧 + 复制
if os.path.exists(dest): shutil.rmtree(dest)
os.makedirs(dest)
for it in ITEMS:
    src = os.path.join(ROOT, it); dst = os.path.join(dest, it)
    if os.path.isdir(src): shutil.copytree(src, dst)
    else: shutil.copy2(src, dst)

n_files = sum(len(fs) for _, _, fs in os.walk(dest))
print(f'已打包 {len(ITEMS)} 个组件、{n_files} 个文件 → {dest}')
