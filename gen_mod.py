#!/usr/bin/env python3
# 打包【mod portal 发布用】zip：把场景包成一个含 scenarios/ 目录的模组。
#   结构：<模组名>_<版本>.zip / <模组名>_<版本>/ { info.json(模组版), thumbnail.png(可选), scenarios/endfield_factorio/<场景5组件> }
#   模组名/版本/作者等取自场景 info.json（版本两边共用，发新版只改场景 info.json 一处）。
# 用法：
#   python3 gen_mod.py            # 输出到 <项目>/<模组名>_<版本>.zip
#   python3 gen_mod.py --desktop  # 输出到 桌面（带任意参数即放桌面）
# 发布：mods.factorio.com → 右上角头像 → My Mods → Upload mod → 传 zip。
import os, sys, re, json, shutil, zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
SCENARIO_NAME = 'endfield_factorio'   # 场景文件夹名（游戏内"新游戏→场景"显示的目录）
ITEMS = ['scripts', 'locale', 'control.lua', 'description.json', 'info.json']

# 元数据取自场景 info.json：模组与场景同名同版（版本必须 x.y.z 且每段 ≤ 65535）
with open(os.path.join(ROOT, 'info.json'), encoding='utf-8') as f:
    scen = json.load(f)
MOD_NAME, VERSION = scen['name'], scen['version']
if not re.fullmatch(r'\d+\.\d+\.\d+', VERSION) or any(int(p) > 65535 for p in VERSION.split('.')):
    sys.exit(f'版本号 {VERSION} 不合法：必须 x.y.z 且每段 ≤ 65535')

# 模组 info.json：只放模组字段（场景专属的 quality_required 等不带过去）
mod_info = {
    'name': MOD_NAME,
    'version': VERSION,
    'title': scen.get('title', MOD_NAME),
    'author': scen.get('author', ''),
    'contact': scen.get('contact', ''),
    'homepage': 'https://github.com/sandboxtech/endfield_factorio',
    'description': '建好工厂，跃迁奔向下一个星系，一局接一局。攒瓶子练职业，越玩越强。Endless Warptorio: build, warp to a fresh star system, repeat. 11 languages.',
    'factorio_version': scen.get('factorio_version', '2.0'),
    'dependencies': scen.get('dependencies', ['base >= 2.0.0']),
}

# 目标基准：带参数 → 桌面（Windows 桌面，从 /mnt/c/Users/<用户> 推断）；否则项目目录内
if len(sys.argv) > 1:
    m = re.search(r'^(/mnt/[a-z]/Users/[^/]+)', ROOT)
    base = os.path.join(m.group(1), 'Desktop') if m else os.path.expanduser('~/Desktop')
    if not os.path.isdir(base): sys.exit(f'找不到桌面目录：{base}')
else:
    base = ROOT

# 源文件齐全性校验
missing = [i for i in ITEMS if not os.path.exists(os.path.join(ROOT, i))]
if missing: sys.exit('缺少组件，无法打包：' + ', '.join(missing))

# 组装临时目录 <模组名>_<版本>/ 再整体压 zip
top = f'{MOD_NAME}_{VERSION}'
build = os.path.join(base, top)
if os.path.exists(build): shutil.rmtree(build)
scen_dir = os.path.join(build, 'scenarios', SCENARIO_NAME)
os.makedirs(scen_dir)
with open(os.path.join(build, 'info.json'), 'w', encoding='utf-8') as f:
    json.dump(mod_info, f, ensure_ascii=False, indent=2)
# 缩略图：有 thumbnail.png 用之，否则退回 image.png（mod portal 建议方形 144×144）
for cand in ('thumbnail.png', 'image.png'):
    p = os.path.join(ROOT, cand)
    if os.path.exists(p):
        shutil.copy2(p, os.path.join(build, 'thumbnail.png')); break
for it in ITEMS:
    src = os.path.join(ROOT, it); dst = os.path.join(scen_dir, it)
    if os.path.isdir(src): shutil.copytree(src, dst)
    else: shutil.copy2(src, dst)

zip_path = os.path.join(base, top + '.zip')
if os.path.exists(zip_path): os.remove(zip_path)
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
    for dirpath, _, files in os.walk(build):
        for fn in files:
            full = os.path.join(dirpath, fn)
            z.write(full, os.path.relpath(full, base))   # 归档路径以 <模组名>_<版本>/ 开头
shutil.rmtree(build)   # 临时目录用完即删，只留 zip

n = len(zipfile.ZipFile(zip_path).namelist())
print(f'已打包模组 {MOD_NAME} v{VERSION}（{n} 个文件）→ {zip_path}')
