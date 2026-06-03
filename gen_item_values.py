#!/usr/bin/env python3
# 从 scripts/classes.lua + 正版 Factorio 数据，估算物品/科技/职业价值，生成 class_values.txt（职业价值分析）。
# 价值口径见生成文件头部注释。改完 classes.lua 跑一下即可复算。
#   用法：python3 gen_item_values.py            # 生成(用缓存，秒出)
#         python3 gen_item_values.py --check     # 只校验是否已同步(不写文件)
#         python3 gen_item_values.py --rebuild   # 重扫 Factorio 数据刷新缓存(慢，~1分钟；Factorio 更新后才需要)
#         FACTORIO_DIR=/path/to/Factorio python3 gen_item_values.py
#
# 性能：扫 Factorio 数据(几百个原型文件)在 /mnt/c 上很慢，故结果缓存到 .value_cache.json。
#       物品/科技成本只跟 Factorio 数据有关，改 classes.lua 不需要重扫 → 平时秒出。
import re, os, sys, glob, json, statistics

ROOT = os.path.dirname(os.path.abspath(__file__))
CLASSES = os.path.join(ROOT, 'scripts', 'classes.lua')
TXT = os.path.join(ROOT, 'class_values.txt')
CACHE = os.path.join(ROOT, '.value_cache.json')
FACTORIO = os.environ.get('FACTORIO_DIR', '/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio')

def matchbrace(s, ob):
    d = 0; k = ob
    while k < len(s):
        if s[k] == '{': d += 1
        elif s[k] == '}':
            d -= 1
            if d == 0: return k
        k += 1
    return len(s) - 1

# ---------- 扫 Factorio 数据：物品单价 / 堆叠 / 科技成本（结果缓存）----------
def build_factorio_data():
    if not os.path.isdir(os.path.join(FACTORIO, 'data')):
        sys.exit(f'找不到 Factorio 数据：{FACTORIO}\n用 FACTORIO_DIR=... 指定，或确认正版安装路径。')

    def dfiles(*pats):
        out = []
        for p in pats:
            out += glob.glob(os.path.join(FACTORIO, p), recursive=True)
        return out
    PROTO = dfiles('data/base/prototypes/**/*.lua', 'data/space-age/prototypes/**/*.lua',
                   'data/quality/prototypes/**/*.lua', 'data/elevated-rails/prototypes/**/*.lua')

    # 可挖原矿(强制价值=1，忽略煤合成等配方)
    RAW = {'coal', 'stone', 'iron-ore', 'copper-ore', 'uranium-ore', 'calcite',
           'tungsten-ore', 'holmium-ore', 'scrap', 'crude-oil', 'lithium', 'fluorine', 'water'}
    # 物品类 prototype 的 type（带 stack_size 的）。嵌套结构里的 type（direct/instant/create-explosion…）不在此列。
    ITEM_TYPES = {'item', 'ammo', 'gun', 'capsule', 'module', 'armor', 'tool', 'repair-tool',
                  'mining-tool', 'rail-planner', 'item-with-entity-data', 'item-with-inventory',
                  'item-with-tags', 'item-with-label', 'blueprint', 'blueprint-book',
                  'deconstruction-item', 'upgrade-item', 'selection-tool', 'copy-paste-tool',
                  'spidertron-remote', 'space-platform-starter-pack'}
    stack = {}
    for f in PROTO:
        try: s = open(f, encoding='utf-8').read()
        except Exception: continue
        if 'type = "resource"' in s:
            for mt in re.finditer(r'type\s*=\s*"resource"', s):
                seg = s[mt.start():mt.start() + 1500]
                for m in re.finditer(r'result\s*=\s*"([a-z0-9-]+)"', seg):
                    RAW.add(m.group(1))
        # 进入物品类 type 后，取它的【第一个 name】作归属（忽略 ammo_type 等嵌套里的 name/type）；
        # 其后第一个 stack_size 即该物品的。这样嵌套的 name="explosion-..." 不会顶替真正的物品名。
        cur = None; expect = False
        for m in re.finditer(r'type\s*=\s*"([a-z0-9-]+)"|name\s*=\s*"([a-z0-9-]+)"|stack_size\s*=\s*(\d+)', s):
            if m.group(1) is not None:
                if m.group(1) in ITEM_TYPES: expect = True; cur = None
            elif m.group(2) is not None:
                if expect: cur = m.group(2); expect = False
            elif m.group(3) is not None:
                if cur and cur not in stack: stack[cur] = int(m.group(3))

    # 配方(只认主产物：与配方同名者，否则唯一结果)
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
    COST = {n: round(cost(n), 3) for n in sorted(set(stack) | set(producer) | RAW)}

    # 科技成本(触发科技=0；无限科技按一批 1000 次估)
    techfiles = dfiles('data/**/technology*.lua')
    trigger = set()
    for f in techfiles:
        s = open(f, encoding='utf-8').read()
        for mt in re.finditer(r'type\s*=\s*"technology"', s):
            o = s.rfind('{', 0, mt.start()); blk = s[o:matchbrace(s, o) + 1]
            if 'research_trigger' in blk:
                nm = re.search(r'name\s*=\s*"([a-z0-9-]+)"', blk[:200])
                if nm: trigger.add(nm.group(1))
    for f in dfiles('data/*/base-data-updates.lua', 'data/*/data-updates.lua', 'data/*/data-final-fixes.lua'):
        try: s = open(f, encoding='utf-8').read()
        except Exception: continue
        for m in re.finditer(r'data\.raw\.technology[.\[]"?([a-z0-9-]+)"?\]?\.research_trigger', s):
            trigger.add(m.group(1))
    techcost = {}; infinite = set()
    for f in techfiles:
        s = open(f, encoding='utf-8').read()
        for mt in re.finditer(r'type\s*=\s*"technology"', s):
            o = s.rfind('{', 0, mt.start()); blk = s[o:matchbrace(s, o) + 1]
            nm = re.search(r'name\s*=\s*"([a-z0-9-]+)"', blk[:200])
            if not nm: continue
            name = nm.group(1)
            mu = re.search(r'unit\s*=\s*\{', blk)
            if not mu: continue
            uo = blk.index('{', mu.start()); ublk = blk[uo:matchbrace(blk, uo) + 1]
            mc = re.search(r'count\s*=\s*(\d+)', ublk); cf = 'count_formula' in ublk
            packs = re.findall(r'\{\s*"([a-z0-9-]+-science-pack)"\s*,\s*(\d+)\s*\}', ublk)
            cnt = int(mc.group(1)) if mc else (1000 if cf else 1)
            if cf: infinite.add(name)
            techcost[name] = round(sum(cnt * int(n) * COST.get(p, 1.0) for p, n in packs))
    for t in trigger:
        techcost[t] = 0; infinite.discard(t)
    return COST, stack, techcost, infinite

# 缓存：物品/科技成本只随 Factorio 数据变，改 classes.lua 不用重扫。
if os.path.exists(CACHE) and '--rebuild' not in sys.argv:
    _c = json.load(open(CACHE, encoding='utf-8'))
    COST, stack, techcost, infinite = _c['cost'], _c['stack'], _c['techcost'], set(_c['infinite'])
else:
    COST, stack, techcost, infinite = build_factorio_data()
    json.dump({'cost': COST, 'stack': stack, 'techcost': techcost, 'infinite': sorted(infinite)},
              open(CACHE, 'w', encoding='utf-8'))
    print(f'已刷新 Factorio 缓存 .value_cache.json（{len(COST)} 物品 / {len(techcost)} 科技）')

# ---------- 解析 classes.lua ----------
src = open(CLASSES, encoding='utf-8').read()
ob = src.index('{', src.index('local DEFAULT_CLASSES'))
block = src[ob:matchbrace(src, ob) + 1]
block = '\n'.join(ln[:ln.find('--')] if '--' in ln else ln for ln in block.split('\n'))
FULL = {'FULL_LOW': 1000, 'FULL_MID': 10000, 'FULL_MAX': 100000}
idxs = [(m.start(), m.group(1)) for m in re.finditer(r"key\s*=\s*'([a-z_]+)'", block)]
used = set(); techused = set(); rows = []
def entries(part):
    out = []
    # 容忍等号两边有无空格（count=10 与 count = 10 都要匹配）
    for em in re.finditer(r"item\s*=\s*'([a-z0-9-]+)'\s*,\s*(count|groups)\s*=\s*(\d+)", part):
        it, kind, num = em.group(1), em.group(2), int(em.group(3)); used.add(it)
        out.append((it, round(COST.get(it, 1.0) * (num if kind == 'count' else stack.get(it, 1) * num))))
    return out
for n, (pos, key) in enumerate(idxs):
    end = idxs[n + 1][0] if n + 1 < len(idxs) else len(block)
    body = block[pos:end]
    mf = re.search(r'full\s*=\s*(FULL_\w+)', body); full = FULL.get(mf.group(1), 100000) if mf else 100000
    def sec(tag):
        m = re.search(tag + r'\s*=\s*\{', body)
        if not m: return ''
        o = body.index('{', m.start()); return body[o:matchbrace(body, o) + 1]
    mn = re.search(r"name\s*=\s*'([^']*)'", body); cname = mn.group(1) if mn else ''
    st = entries(sec('starter')); rw = entries(sec('rewards'))
    mt = re.search(r"techs = \{([^}]*)\}", body)
    tl = re.findall(r"'([a-z0-9-]+)'", mt.group(1)) if mt else []
    techused.update(tl)
    tv = sum(techcost.get(t, 0) for t in tl); inf = any(t in infinite for t in tl)
    si = sum(v for _, v in st); mi = si + sum(v for _, v in rw)
    rows.append({'key': key, 'name': cname, 'full': full, 'si': si, 'mi': mi,
                 'tv': round(tv), 'inf': inf, 'techs': tl, 'st': st, 'rw': rw})

# ---------- 生成 class_values.txt（职业 + 科技价值分析，详细，按价值分组排列）----------
tag = lambda f: {1000: 'LOW', 10000: 'MID', 100000: 'MAX'}[f]
def fmt_items(lst):
    return '、'.join(f'{it}={v:,}' for it, v in sorted(lst, key=lambda x: -x[1])) or '（无）'
T = ['╔══════════════════════════════════════════════════════════════╗',
     '║  职业价值分析（gen_item_values.py 自动生成，勿手改）           ║',
     '╚══════════════════════════════════════════════════════════════╝',
     '重要性权重：初始物品 > 满级物品 >> 科技。',
     '物品价值=递归原矿成本（沿同名主产物配方展开到原矿；可挖原矿=1，忽略合成；coin 低估）。',
     '满级物品=初始 + 全部 rewards 满配额（stack×groups 或 count）。',
     '科技价值=研究科学瓶投入；触发科技=0；无限科技按一批 1000 次估（标 ∞）。']

# 一、汇总表（按档位 + 满级物品价值降序）
T += ['', '━━━━━━━━━━━━ 一、汇总表 ━━━━━━━━━━━━']
w = max(len(r['key']) for r in rows)
T.append(f"{'职业'.ljust(w)}  档    初始物品    满级物品       科技")
T.append('─' * (w + 40))
for f in (1000, 10000, 100000):
    for r in sorted([x for x in rows if x['full'] == f], key=lambda r: -r['mi']):
        T.append(f"{r['key'].ljust(w)}  {tag(f):<4}{r['si']:>10,}{r['mi']:>12,}"
                 f"{(format(r['tv'], ',') + ('∞' if r['inf'] else '')):>12}")

# 二、分档明细（每档内按满级物品价值降序，逐职业列出物品来源）
for f in (1000, 10000, 100000):
    grp = sorted([x for x in rows if x['full'] == f], key=lambda r: -r['mi'])
    mis = [r['mi'] for r in grp]
    T += ['', f'━━━━━━━━━━━━ 二、{tag(f)} 档明细（{len(grp)}个，满级中位 {statistics.median(mis):,.0f}）━━━━━━━━━━━━']
    for r in grp:
        T.append('')
        T.append(f"【{r['key']} {r['name']}】 初始物品={r['si']:,}  满级物品={r['mi']:,}  "
                 f"科技={r['tv']:,}{'∞' if r['inf'] else ''}  techs={r['techs'] or '无'}")
        T.append(f"    初始: {fmt_items(r['st'])}")
        T.append(f"    奖励: {fmt_items(r['rw'])}")

# 三、复检与离群
T += ['', '━━━━━━━━━━━━ 三、复检 ━━━━━━━━━━━━']
si_all = [r['si'] for r in rows]
T.append(f"初始物品  中位={statistics.median(si_all):,.0f}  范围 {min(si_all):,.0f} ~ {max(si_all):,.0f}（应大致相当）")
for f in (1000, 10000, 100000):
    mi = [r['mi'] for r in rows if r['full'] == f]
    if mi: T.append(f"{tag(f)} 满级物品  中位={statistics.median(mi):,.0f}  范围 {min(mi):,.0f} ~ {max(mi):,.0f}")
N = min(20, len(rows))
def line_si(r):
    return (f"  {r['key'].ljust(w)} {tag(r['full']):<4} 初始={r['si']:>9,}  "
            f"科技={r['tv']:,}{'∞' if r['inf'] else ''}  主因 {fmt_items(r['st']).split('、')[0]}")
def line_mi(r):
    return (f"  {r['key'].ljust(w)} {tag(r['full']):<4} 满级={r['mi']:>10,}  "
            f"科技={r['tv']:,}{'∞' if r['inf'] else ''}  主因 {fmt_items(r['rw']).split('、')[0]}")

T += ['', f'──── 初始物品排名 · 前 {N}（最高，最该削平）────']
for r in sorted(rows, key=lambda r: -r['si'])[:N]: T.append(line_si(r))
T += ['', f'──── 初始物品排名 · 后 {N}（最低，科技列高=靠科技/高科技物品撑，非真弱；coin 低估）────']
for r in sorted(rows, key=lambda r: r['si'])[:N]: T.append(line_si(r))

T += ['', f'──── 满级物品排名 · 前 {N}（最高，含 MID/LOW 越级）────']
for r in sorted(rows, key=lambda r: -r['mi'])[:N]: T.append(line_mi(r))
T += ['', f'──── 满级物品排名 · 后 {N}（最低，最差，最可能需补强）────']
for r in sorted(rows, key=lambda r: r['mi'])[:N]: T.append(line_mi(r))

T += ['', '各档档内最差（满级物品最低 3）：']
for f in (1000, 10000, 100000):
    for r in sorted([x for x in rows if x['full'] == f], key=lambda r: r['mi'])[:3]:
        T.append(f"  {tag(f)}  {r['key'].ljust(w)} 满级={r['mi']:>8,}  科技={r['tv']:,}{'∞' if r['inf'] else ''}  techs={r['techs'] or '无'}")
txt_content = '\n'.join(T) + '\n'

if '--check' in sys.argv:
    ok = (open(TXT, encoding='utf-8').read() if os.path.exists(TXT) else '') == txt_content
    if ok:
        print(f'已同步（{len(used)} 物品 / {len(rows)} 职业）'); sys.exit(0)
    print('class_values.txt 与 classes.lua 不同步！请运行 python3 gen_item_values.py'); sys.exit(1)

open(TXT, 'w', encoding='utf-8').write(txt_content)
print(f'已生成 class_values.txt（{len(rows)} 职业 / {len(techused)} 科技）')
