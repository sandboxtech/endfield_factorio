#!/usr/bin/env python3
# 从 scripts/classes.lua + 正版 Factorio 数据，估算物品/科技/职业价值，生成 scripts/item_values.lua。
# 价值口径见生成文件头部注释。改完 classes.lua 跑一下即可复算。
#   用法：python3 gen_item_values.py            # 覆盖 scripts/item_values.lua
#         python3 gen_item_values.py --check     # 只校验是否已同步(不写文件)，CI/提交前用
#         FACTORIO_DIR=/path/to/Factorio python3 gen_item_values.py   # 指定 Factorio 安装目录
import re, os, sys, glob, json

ROOT = os.path.dirname(os.path.abspath(__file__))
CLASSES = os.path.join(ROOT, 'scripts', 'classes.lua')
OUT = os.path.join(ROOT, 'scripts', 'item_values.lua')
# 正版 Steam 安装路径(校验原型/配方用，别用回收站旧副本)。可用 FACTORIO_DIR 覆盖。
FACTORIO = os.environ.get('FACTORIO_DIR', '/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio')

if not os.path.isdir(os.path.join(FACTORIO, 'data')):
    sys.exit(f'找不到 Factorio 数据：{FACTORIO}\n用 FACTORIO_DIR=... 指定安装目录。')

def matchbrace(s, ob):
    d = 0; k = ob
    while k < len(s):
        if s[k] == '{': d += 1
        elif s[k] == '}':
            d -= 1
            if d == 0: return k
        k += 1
    return len(s) - 1

def dfiles(*pats):
    out = []
    for p in pats:
        out += glob.glob(os.path.join(FACTORIO, p), recursive=True)
    return out

# ---------- 1) 可挖原矿(强制价值=1，忽略煤合成等配方) ----------
RAW = {'coal', 'stone', 'iron-ore', 'copper-ore', 'uranium-ore', 'calcite',
       'tungsten-ore', 'holmium-ore', 'scrap', 'crude-oil', 'lithium', 'fluorine', 'water'}
for f in dfiles('data/**/*.lua'):
    try: s = open(f, encoding='utf-8').read()
    except Exception: continue
    if 'type = "resource"' not in s: continue
    for mt in re.finditer(r'type\s*=\s*"resource"', s):
        seg = s[mt.start():mt.start() + 1500]
        for m in re.finditer(r'result\s*=\s*"([a-z0-9-]+)"', seg):
            RAW.add(m.group(1))

# ---------- 2) stack_size ----------
stack = {}
for f in dfiles('data/base/prototypes/**/*.lua', 'data/space-age/prototypes/**/*.lua',
                'data/quality/prototypes/**/*.lua', 'data/elevated-rails/prototypes/**/*.lua'):
    try: s = open(f, encoding='utf-8').read()
    except Exception: continue
    last = None
    for m in re.finditer(r'name\s*=\s*"([a-z0-9-]+)"|stack_size\s*=\s*(\d+)', s):
        if m.group(1): last = m.group(1)
        elif m.group(2) and last and last not in stack: stack[last] = int(m.group(2))

# ---------- 3) 配方(只认主产物：与配方同名者，否则唯一结果) ----------
def sub(blk, key):
    m = re.search(key + r'\s*=\s*\{', blk)
    if not m: return ''
    o = blk.index('{', m.start()); return blk[o:matchbrace(blk, o) + 1]
def items_of(part):
    d = {}
    for em in re.finditer(r'name\s*=\s*"([a-z0-9-]+)"\s*,\s*amount\s*=\s*([\d.]+)', part):
        d[em.group(1)] = d.get(em.group(1), 0) + float(em.group(2))
    for em in re.finditer(r'\{\s*"([a-z0-9-]+)"\s*,\s*([\d.]+)\s*\}', part):
        d[em.group(1)] = d.get(em.group(1), 0) + float(em.group(2))
    return d
producer = {}
def parse_recipes(s):
    for mt in re.finditer(r'type\s*=\s*"recipe"', s):
        o = s.rfind('{', 0, mt.start()); blk = s[o:matchbrace(s, o) + 1]
        nm = re.search(r'name\s*=\s*"([a-z0-9-]+)"', blk)
        if not nm: continue
        rn = nm.group(1); ing = items_of(sub(blk, 'ingredients')); res = items_of(sub(blk, 'results'))
        if not res: res = {rn: 1.0}
        if not ing: continue
        if rn in res: main, amt = rn, res[rn]
        elif len(res) == 1: main, amt = next(iter(res.items()))
        else: continue
        producer.setdefault(main, []).append((ing, amt))
for f in ('data/base/prototypes/recipe.lua', 'data/space-age/prototypes/recipe.lua',
          'data/quality/prototypes/recipe.lua', 'data/elevated-rails/prototypes/recipe.lua'):
    p = os.path.join(FACTORIO, f)
    if os.path.exists(p): parse_recipes(open(p, encoding='utf-8').read())

memo = {}; inprog = set()
def cost(it):
    if it in RAW: memo[it] = 1.0; return 1.0
    if it in memo: return memo[it]
    if it not in producer: memo[it] = 1.0; return 1.0
    if it in inprog: return float('inf')
    inprog.add(it); best = float('inf')
    for ing, amt in producer[it]:
        c = 0.0; ok = True
        for g, a in ing.items():
            cc = cost(g)
            if cc == float('inf'): ok = False; break
            c += cc * a
        if ok: best = min(best, c / amt)
    inprog.discard(it)
    if best == float('inf'): best = 1.0
    memo[it] = best; return best

# ---------- 4) 科技成本(触发科技=0；无限科技按一批 1000 次估) ----------
COST = {n: round(cost(n), 3) for n in (set(stack) | set(producer) | RAW)}
trigger = set()
for f in dfiles('data/**/technology*.lua'):
    s = open(f, encoding='utf-8').read()
    for mt in re.finditer(r'type\s*=\s*"technology"', s):
        o = s.rfind('{', 0, mt.start()); blk = s[o:matchbrace(s, o) + 1]
        if 'research_trigger' in blk:
            nm = re.search(r'name\s*=\s*"([a-z0-9-]+)"', blk[:200])
            if nm: trigger.add(nm.group(1))
for f in dfiles('data/**/*.lua'):
    try: s = open(f, encoding='utf-8').read()
    except Exception: continue
    for m in re.finditer(r'data\.raw\.technology[.\[]"?([a-z0-9-]+)"?\]?\.research_trigger', s):
        trigger.add(m.group(1))
techcost = {}; infinite = set()
for f in dfiles('data/**/technology*.lua'):
    s = open(f, encoding='utf-8').read()
    for mt in re.finditer(r'type\s*=\s*"technology"', s):
        o = s.rfind('{', 0, mt.start()); blk = s[o:matchbrace(s, o) + 1]
        nm = re.search(r'name\s*=\s*"([a-z0-9-]+)"', blk[:200])
        if not nm: continue
        name = nm.group(1)
        mu = re.search(r'unit\s*=\s*\{', blk)
        if not mu: continue
        ublk = blk[blk.index('{', mu.start()):matchbrace(blk, blk.index('{', mu.start())) + 1]
        mc = re.search(r'count\s*=\s*(\d+)', ublk); cf = 'count_formula' in ublk
        packs = re.findall(r'\{\s*"([a-z0-9-]+-science-pack)"\s*,\s*(\d+)\s*\}', ublk)
        cnt = int(mc.group(1)) if mc else (1000 if cf else 1)
        if cf: infinite.add(name)
        techcost[name] = round(sum(cnt * int(n) * COST.get(p, 1.0) for p, n in packs))
for t in trigger:
    techcost[t] = 0; infinite.discard(t)

# ---------- 5) 解析 classes.lua ----------
src = open(CLASSES, encoding='utf-8').read()
ob = src.index('{', src.index('local DEFAULT_CLASSES'))
block = src[ob:matchbrace(src, ob) + 1]
block = '\n'.join(ln[:ln.find('--')] if '--' in ln else ln for ln in block.split('\n'))
FULL = {'FULL_LOW': 1000, 'FULL_MID': 10000, 'FULL_MAX': 100000}
idxs = [(m.start(), m.group(1)) for m in re.finditer(r"key = '([a-z_]+)'", block)]
used = set(); techused = set(); rows = []
def entries(part):
    out = []
    for em in re.finditer(r"item = '([a-z0-9-]+)'\s*,\s*(count|groups) = (\d+)", part):
        it, kind, num = em.group(1), em.group(2), int(em.group(3)); used.add(it)
        out.append((it, round(COST.get(it, 1.0) * (num if kind == 'count' else stack.get(it, 1) * num))))
    return out
for n, (pos, key) in enumerate(idxs):
    end = idxs[n + 1][0] if n + 1 < len(idxs) else len(block)
    body = block[pos:end]
    mf = re.search(r'full = (FULL_\w+)', body); full = FULL.get(mf.group(1), 100000) if mf else 100000
    def sec(tag):
        m = re.search(tag + r'\s*=\s*\{', body)
        if not m: return ''
        o = body.index('{', m.start()); return body[o:matchbrace(body, o) + 1]
    st = entries(sec('starter')); rw = entries(sec('rewards'))
    mt = re.search(r"techs = \{([^}]*)\}", body)
    tl = re.findall(r"'([a-z0-9-]+)'", mt.group(1)) if mt else []
    techused.update(tl)
    tv = sum(techcost.get(t, 0) for t in tl); inf = any(t in infinite for t in tl)
    si = sum(v for _, v in st); mi = si + sum(v for _, v in rw)
    rows.append((key, full, si, mi, round(tv), inf))

# ---------- 6) 生成 item_values.lua（只含物品价值：unit + stack）----------
L = ['-- 物品价值表（gen_item_values.py 自动生成，勿手改；改 classes.lua 后重跑）。',
     '-- 物品价值=递归原矿成本(沿同名主产物配方到原矿)。【可挖原矿 coal/stone/iron-ore/copper-ore 等强制=1，忽略合成配方】。',
     '--           不反映"高科技但造价低"(如 combat-shotgun)；coin 按 1(低估其市场购买力)。满级"1组"=stack×unit。',
     '-- 数据源：正版 Factorio 2.0.x(base+space-age+quality)，配方变动需重跑。职业/科技价值分析见 class_values.txt。',
     'local M = {}', '', 'M.unit = {']
for it in sorted(used): L.append(f"    ['{it}'] = {COST.get(it, 1.0):g},")
L += ['}', '', 'M.stack = {']
for it in sorted(used): L.append(f"    ['{it}'] = {stack.get(it, 1)},")
L += ['}', '', 'return M']
lua_content = '\n'.join(L) + '\n'

# ---------- 7) 生成 class_values.txt（职业 + 科技价值分析，纯文本）----------
import statistics
tag = lambda f: {1000: 'LOW', 10000: 'MID', 100000: 'MAX'}[f]
TXT = os.path.join(ROOT, 'class_values.txt')
T = ['职业价值分析（gen_item_values.py 自动生成）。重要性权重：初始物品 > 满级物品 >> 科技。',
     '价值=递归原矿成本(可挖原矿=1，忽略合成)。触发科技=0；无限科技按一批1000次估(标 inf)。coin 低估。', '']
w = max(len(r[0]) for r in rows)
T.append(f"{'职业'.ljust(w)}  档   初始物品   满级物品      科技")
T.append('-' * (w + 36))
for r in sorted(rows, key=lambda r: (r[1], r[3])):
    k, f, si, mi, tv, inf = r
    T.append(f"{k.ljust(w)}  {tag(f):<4}{si:>9,}{mi:>11,}{(format(tv, ',') + ('∞' if inf else '')):>11}")
T += ['', '== 复检 ==']
si_all = [r[2] for r in rows]
T.append(f"初始物品 中位={statistics.median(si_all):,.0f}  范围 {min(si_all):,.0f}~{max(si_all):,.0f}")
for t, f in [('LOW', 1000), ('MID', 10000), ('MAX', 100000)]:
    mi = [r[3] for r in rows if r[1] == f]
    if mi: T.append(f"{t} 满级物品 中位={statistics.median(mi):,.0f}  范围 {min(mi):,.0f}~{max(mi):,.0f}")
T += ['', '初始物品最高 8（应大致相当）：']
for r in sorted(rows, key=lambda r: -r[2])[:8]: T.append(f"  {r[0].ljust(w)} {tag(r[1]):<4} {r[2]:>9,}")
T += ['', '满级物品越级 8（MID/LOW 高于 MAX 中位即偏高）：']
for r in sorted([x for x in rows if x[1] < 100000], key=lambda r: -r[3])[:8]:
    T.append(f"  {r[0].ljust(w)} {tag(r[1]):<4} {r[3]:>10,}")
txt_content = '\n'.join(T) + '\n'

if '--check' in sys.argv:
    ok = (open(OUT, encoding='utf-8').read() if os.path.exists(OUT) else '') == lua_content \
        and (open(TXT, encoding='utf-8').read() if os.path.exists(TXT) else '') == txt_content
    if ok:
        print(f'已同步（{len(used)} 物品 / {len(rows)} 职业）')
        sys.exit(0)
    print('item_values.lua / class_values.txt 与 classes.lua 不同步！请运行 python3 gen_item_values.py')
    sys.exit(1)

open(OUT, 'w', encoding='utf-8').write(lua_content)
open(TXT, 'w', encoding='utf-8').write(txt_content)
print(f'已生成 scripts/item_values.lua（{len(used)} 物品）+ class_values.txt（{len(rows)} 职业 / {len(techused)} 科技）')
