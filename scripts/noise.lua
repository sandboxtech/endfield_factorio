-- 2D simplex 噪声 + 分形多倍频。control 阶段纯 Lua，可在 on_chunk_generated 里逐格求值，
-- 用来在场景里"手动"造自然地形/矿脉（场景改不了数据阶段的 map gen，只能这样运行时铺）。
-- simplex 算法：Stefan Gustavson 公有领域实现。
-- 分形 fractal/octaves：多层不同频率叠加 → 自然不规则、不重复。

local bit32_band = bit32.band
local math_floor = math.floor
local math_sqrt = math.sqrt

local grad3 = {
    {1, 1, 0}, {-1, 1, 0}, {1, -1, 0}, {-1, -1, 0},
    {1, 0, 1}, {-1, 0, 1}, {1, 0, -1}, {-1, 0, -1},
    {0, 1, 1}, {0, -1, 1}, {0, 1, -1}, {0, -1, -1},
}

local p = {
    151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142,
    8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117,
    35, 11, 32, 57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71,
    134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41,
    55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18,
    169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 52, 217, 226, 250,
    124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227, 47, 16, 58, 17, 182, 189,
    28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9,
    129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251,
    34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192,
    214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205,
    93, 222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180,
}
local perm = {}
for i = 0, 511 do perm[i + 1] = p[bit32_band(i, 255) + 1] end

local F2 = 0.5 * (math_sqrt(3.0) - 1.0)
local G2 = (3.0 - math_sqrt(3.0)) / 6.0

-- 2D simplex，返回 [-1,1]
local function d2(xin, yin, seed)
    xin = xin + seed
    yin = yin + seed
    local n0, n1, n2
    local s = (xin + yin) * F2
    local i = math_floor(xin + s)
    local j = math_floor(yin + s)
    local t = (i + j) * G2
    local X0 = i - t
    local Y0 = j - t
    local x0 = xin - X0
    local y0 = yin - Y0
    local i1, j1
    if x0 > y0 then i1, j1 = 1, 0 else i1, j1 = 0, 1 end
    local x1 = x0 - i1 + G2
    local y1 = y0 - j1 + G2
    local x2 = x0 - 1 + 2 * G2
    local y2 = y0 - 1 + 2 * G2
    local ii = bit32_band(i, 255)
    local jj = bit32_band(j, 255)
    local gi0 = perm[ii + perm[jj + 1] + 1] % 12
    local gi1 = perm[ii + i1 + perm[jj + j1 + 1] + 1] % 12
    local gi2 = perm[ii + 1 + perm[jj + 1 + 1] + 1] % 12
    local t0 = 0.5 - x0 * x0 - y0 * y0
    if t0 < 0 then n0 = 0.0 else t0 = t0 * t0 n0 = t0 * t0 * (x0 * grad3[gi0 + 1][1] + y0 * grad3[gi0 + 1][2]) end
    local t1 = 0.5 - x1 * x1 - y1 * y1
    if t1 < 0 then n1 = 0.0 else t1 = t1 * t1 n1 = t1 * t1 * (x1 * grad3[gi1 + 1][1] + y1 * grad3[gi1 + 1][2]) end
    local t2 = 0.5 - x2 * x2 - y2 * y2
    if t2 < 0 then n2 = 0.0 else t2 = t2 * t2 n2 = t2 * t2 * (x2 * grad3[gi2 + 1][1] + y2 * grad3[gi2 + 1][2]) end
    return 70.0 * (n0 + n1 + n2)
end

local M = {}
M.d2 = d2

-- 倍频模板（modifier=频率，越小团块越大；weight=权重）。
M.octaves = {
    -- 废料：主频偏高(团块中等) + 强细节(打碎巨块、带孔洞)，避免一整片巨型矿
    scrap = {  -- 废料：4→3 倍频（去掉最高频细节层，省采样；巨块影响小）
        {modifier = 0.012, weight = 1}, {modifier = 0.035, weight = 0.5},
        {modifier = 0.09, weight = 0.3},
    },
    blob = {  -- 通用中团块（石阵/树林/虫区）
        {modifier = 0.01, weight = 1}, {modifier = 0.04, weight = 0.4}, {modifier = 0.1, weight = 0.15},
    },
    smooth = {  -- 大而平滑（湖泊）
        {modifier = 0.006, weight = 1}, {modifier = 0.02, weight = 0.2},
    },
    fine = {  -- 细密（装饰物/密度）
        {modifier = 0.05, weight = 1}, {modifier = 0.15, weight = 0.3},
    },
    -- 星球【海岸边缘】专用：低频主导 → 大尺度平滑起伏（海湾/半岛），不要细碎锯齿。
    coast = {  -- 主轮廓：周期 ~250 格大起伏 + 弱次级。低频层权重压倒中频，故边界平滑。
        {modifier = 0.004, weight = 1}, {modifier = 0.012, weight = 0.22},
    },
    coast_detail = {  -- jag 混入的海岸细节：比 fine 低频得多（周期 ~33/14 格 vs fine 的 ~20/7），碎而不锯齿。
        {modifier = 0.03, weight = 1}, {modifier = 0.07, weight = 0.3},
    },
}

-- 分形噪声：多层 simplex 叠加，返回约 [-1,1]。
function M.fractal(octaves, x, y, seed)
    local noise, total = 0, 0
    for i = 1, #octaves do
        noise = noise + d2(x * octaves[i].modifier, y * octaves[i].modifier, seed) * octaves[i].weight
        total = total + octaves[i].weight
        seed = seed + 10000
    end
    return noise / total
end

-- 由种子确定性派生一组"本轮专属"的噪声变换参数（同一 seed 永远得到同一组）：
--   angle   随机旋转方向
--   stretch 各向异性拉伸：1=圆团，越大越拉成长条
--   zoom    整体特征大小：越大矿脉越大
-- → 每轮矿脉的形状/方向/大小都不一样。
local function hash01(n)   -- 经典 sin 哈希，返回 [0,1)
    local x = math.sin(n) * 43758.5453
    return x - math.floor(x)
end
M.hash01 = hash01   -- 暴露出去：可由种子派生"本轮要不要某风味"等开关

function M.seeded_transform(seed)
    local angle = hash01(seed * 1.7) * math.pi * 2
    local stretch = 1                                 -- 默认圆团
    if hash01(seed * 2.9) > 0.85 then                 -- 仅 ~15% 轮次拉成长条（不再每张图都长条）
        stretch = 1.6 + hash01(seed * 5.5) * 2.4      -- 1.6~4
    end
    local zoom = 0.7 + hash01(seed * 4.3) * 0.7       -- 0.7~1.4：整体特征大小
    return angle, stretch, zoom
end

-- 先按变换(旋转+拉伸+缩放)处理坐标，再喂给 fractal → 方向/长宽/大小随机的噪声场。
function M.fractal_warped(octaves, x, y, seed, angle, stretch, zoom)
    local c, s = math.cos(angle), math.sin(angle)
    local rx = (x * c - y * s) / (stretch * zoom)     -- 旋转后沿一轴拉伸 → 长条
    local ry = (x * s + y * c) / zoom
    return M.fractal(octaves, rx, ry, seed)
end


-- 区块降采样器：低频倍频组（波长 >> 步长）按 step(默认4) 网格采样，返回 (px,py)→双线性插值 的取值闭包。
-- 用于"区块内大量逐点取同一张低频噪声"的场合（tile 替换斑块/障碍互换/树调色）：固定 ~100 次 fractal 换无限次取值。
-- 注意：高频细节被插值抹平，只适合波长 ≥ 4×step 的倍频组（smooth/blob 这类）；调用方应在【取样点很多】时才用
-- （阈值 ~120 点，少于它直接逐点 fractal 反而便宜）。
function M.chunk_sampler(octaves, lt, seed, step)
    step = step or 4
    local x0, y0 = lt.x - 1, lt.y - 1
    local ng = math.ceil(34 / step)   -- 网格 0..ng，覆盖区块 ±1 圈
    local grid = {}
    for gy = 0, ng do
        local row = {}
        for gx = 0, ng do
            row[gx] = M.fractal(octaves, x0 + gx * step, y0 + gy * step, seed)
        end
        grid[gy] = row
    end
    local inv = 1 / step
    return function(px, py)
        local fx, fy = (px - x0) * inv, (py - y0) * inv
        local ix, iy = math.floor(fx), math.floor(fy)
        if ix < 0 then ix = 0 elseif ix >= ng then ix = ng - 1 end
        if iy < 0 then iy = 0 elseif iy >= ng then iy = ng - 1 end
        local tx, ty = fx - ix, fy - iy
        local r0, r1 = grid[iy], grid[iy + 1]
        return (r0[ix] * (1 - tx) + r0[ix + 1] * tx) * (1 - ty)
             + (r1[ix] * (1 - tx) + r1[ix + 1] * tx) * ty
    end
end

return M
