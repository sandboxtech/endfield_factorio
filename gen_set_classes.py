#!/usr/bin/env python3
# 从 scripts/classes.lua 的 DEFAULT_CLASSES 动态生成 set_classes.txt（/sc 热更新指令）。
# classes.lua 是唯一真相源：改完职业表跑一下本脚本即同步，不用手抄。
#   用法：python3 gen_set_classes.py        # 覆盖 set_classes.txt
#         python3 gen_set_classes.py --check # 只校验是否已同步（CI/提交前用），不写文件
import re, sys, os

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(ROOT, 'scripts', 'classes.lua')
OUT  = os.path.join(ROOT, 'set_classes.txt')

src = open(SRC, encoding='utf-8').read()

# 1) 定位 local DEFAULT_CLASSES = { ... }，用花括号配对找到整块。
i = src.index('local DEFAULT_CLASSES =')
i = src.index('{', i)
depth, j = 0, i
while j < len(src):
    c = src[j]
    if c == '{': depth += 1
    elif c == '}':
        depth -= 1
        if depth == 0:
            break
    j += 1
block = src[i + 1:j]   # 不含最外层花括号的内容

# 2) 逐行去掉 lua 行注释（-- 到行尾；数据里没有字符串包含 --，安全），再删全部空白。
no_comment = []
for ln in block.split('\n'):
    p = ln.find('--')
    if p >= 0:
        ln = ln[:p]
    no_comment.append(ln)
flat = re.sub(r'\s+', '', ''.join(no_comment))   # 字符串值(物品名/中文名/pack)内均无空白，可整体删

# 3) 按顶层逗号(depth 0)切成职业条目，空 {} 也保留作分隔符。
elems, depth, start = [], 0, 0
for k, c in enumerate(flat):
    if c == '{':
        depth += 1
    elif c == '}':
        depth -= 1
    elif c == ',' and depth == 0:
        elems.append(flat[start:k]); start = k + 1
elems.append(flat[start:])
elems = [e for e in elems if e != '']   # 去掉尾逗号产生的空串

out = '/sc storage.classes = {\n' + ''.join(e + ',\n' for e in elems) + '}\n'

n_class = sum(1 for e in elems if e.startswith('{key='))
n_sep   = sum(1 for e in elems if e == '{}')

if '--check' in sys.argv:
    cur = open(OUT, encoding='utf-8').read() if os.path.exists(OUT) else ''
    if cur == out:
        print(f'set_classes.txt 已同步（{n_class} 职业 + {n_sep} 分隔）')
        sys.exit(0)
    print('set_classes.txt 与 classes.lua 不同步！请运行 python3 gen_set_classes.py')
    sys.exit(1)

open(OUT, 'w', encoding='utf-8').write(out)
print(f'已生成 set_classes.txt：{n_class} 职业 + {n_sep} 分隔')
