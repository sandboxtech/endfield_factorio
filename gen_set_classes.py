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

# 1.5) 把 full 档常量名替换成数字：DEFAULT_CLASSES 里 full 写的是 FULL_LOW/MID/MAX（Lua 局部变量），
#      但 set_classes.txt 要喂给控制台 /sc，那里没有这些变量 → 必须先换成纯数字。
for _name, _val in re.findall(r'local (FULL_\w+)\s*=\s*(\d+)', src):
    block = re.sub(r'\b' + _name + r'\b', _val, block)

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

# 同步职业名到 zh-CN locale（中文为准，从 classes.lua 的 {key=,name=} 提取，写入标记区块）。
# en 的 class-name-* 由人工维护（gen 不碰）；缺失的职业名游戏内回退 def.name。
ZH = os.path.join(ROOT, 'locale', 'zh-CN', 'locale.cfg')
pairs = re.findall(r"\{key = '([a-z_]+)',[\s\S]*?name = '([^']+)'", '\n'.join(no_comment))   # 用去注释版→注释职业不污染；[\s\S]*? 跨行非贪婪：容忍 key 与 name 间夹多行 techs/full 等字段（每个职业都有 name，非贪婪到自身 name 即停，不会窜到下一职业）
body = '\n'.join(f'class-name-{k}={n}' for k, n in pairs)
B = '# >>> 职业名 class-name-<key>（gen_set_classes.py 自动从 classes.lua 同步，勿手改）>>>'
E = '# <<< 职业名 <<<'
cfg = open(ZH, encoding='utf-8').read()
if B in cfg and E in cfg:
    cfg = re.sub(re.escape(B) + r'.*?' + re.escape(E), B + '\n' + body + '\n' + E, cfg, flags=re.S)
    open(ZH, 'w', encoding='utf-8').write(cfg)
    print(f'已同步 zh-CN 职业名：{len(pairs)} 条')
else:
    print('警告：zh-CN locale.cfg 缺少职业名标记区块，跳过同步')
