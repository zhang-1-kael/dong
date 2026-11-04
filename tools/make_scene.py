#!/usr/bin/env python3
"""生成「Win7 碎玻璃 + 猫吃薯片」壁纸的静态层。

输出（2 倍超采样，供动画阶段做位移/缩放）：
  build_scene/bg.png     蓝色渐变 + Win7 四色旗
  build_scene/cat.png    洞里的照片（带 alpha，只保留洞口区域）
  build_scene/glass.png  裂纹层（带 alpha，含洞口边缘的高光）
"""
import math
import random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT = "build_scene"
W, H = 3452, 2160          # 2× of 1726×1080
random.seed(20240520)

# ── 工具 ────────────────────────────────────────────────────────────────

def homography(src, dst):
    """从 src 四点 → dst 四点的单应矩阵（用于把平面图贴到透视四边形里）"""
    A, b = [], []
    for (x, y), (u, v) in zip(src, dst):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    h = np.linalg.solve(np.array(A, float), np.array(b, float))
    return np.append(h, 1.0).reshape(3, 3)


def bilinear(img, xs, ys):
    """img: HxWxC float；xs/ys: 任意形状坐标 → 同形状采样"""
    h, w = img.shape[:2]
    xs = np.clip(xs, 0, w - 1.001)
    ys = np.clip(ys, 0, h - 1.001)
    x0, y0 = np.floor(xs).astype(np.int32), np.floor(ys).astype(np.int32)
    fx, fy = (xs - x0)[..., None], (ys - y0)[..., None]
    a = img[y0, x0]; bb = img[y0, x0 + 1]
    c = img[y0 + 1, x0]; d = img[y0 + 1, x0 + 1]
    return (a * (1 - fx) * (1 - fy) + bb * fx * (1 - fy)
            + c * (1 - fx) * fy + d * fx * fy)


def smoothstep(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def vgrad(size, stops):
    """竖向多段渐变，stops = [(位置0..1, (r,g,b)), ...]"""
    w, h = size
    ys = np.linspace(0, 1, h)
    pos = np.array([s[0] for s in stops])
    cols = np.array([s[1] for s in stops], float)
    out = np.zeros((h, 3))
    for c in range(3):
        out[:, c] = np.interp(ys, pos, cols[:, c])
    return np.repeat(out[:, None, :], w, axis=1)


# ── 1. 背景：Win7 蓝 ────────────────────────────────────────────────────

def make_bg():
    base = vgrad((W, H), [
        (0.00, (10, 96, 158)),
        (0.18, (20, 126, 190)),
        (0.46, (24, 137, 202)),
        (0.74, (14, 104, 172)),
        (1.00, (6, 66, 126)),
    ])

    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    nx, ny = xx / W, yy / H

    # 左上大面积柔光（原图左上偏亮、偏青）
    d = np.sqrt(((nx - 0.16) * 1.0) ** 2 + ((ny - 0.12) * 1.35) ** 2)
    glow = np.clip(1.0 - d / 0.86, 0, 1) ** 1.6
    base += glow[..., None] * np.array([52, 62, 58], float)

    # 斜向光带（Win7 那种从左上打下来的光束）
    for off, wid, amp in [(-0.10, 0.16, 12), (0.16, 0.09, 8), (0.46, 0.06, 5)]:
        t = (nx * 0.62 + ny * 0.55) - off
        band = np.exp(-(t / wid) ** 2)
        base += band[..., None] * amp

    # 右侧轻微压暗，让破洞区更沉
    base -= np.clip((nx - 0.55) / 0.45, 0, 1)[..., None] ** 1.4 * np.array([16, 14, 8], float)
    # 顶部/底部边缘压暗一点
    base -= np.clip((0.18 - ny) / 0.18, 0, 1)[..., None] ** 2 * 10
    base -= np.clip((ny - 0.88) / 0.12, 0, 1)[..., None] ** 2 * 14

    # 极轻的胶片颗粒，避免大面积渐变色带
    noise = np.random.default_rng(7).normal(0, 2.2, (H // 2, W // 2, 1))
    noise = np.repeat(np.repeat(noise, 2, axis=0), 2, axis=1)[:H, :W]
    base += noise

    return np.clip(base, 0, 255)


# ── 2. Win7 四色旗 ──────────────────────────────────────────────────────

def make_flag(canvas):
    S = 1024
    flat = np.zeros((S, S, 4), float)
    fy, fx = np.mgrid[0:S, 0:S].astype(np.float32) / S

    panes = [
        (0.000, 0.000, (242, 80, 34)),    # 左上 红
        (0.509, 0.000, (127, 186, 0)),    # 右上 绿
        (0.000, 0.509, (0, 164, 239)),    # 左下 蓝
        (0.509, 0.509, (255, 185, 0)),    # 右下 黄
    ]
    rad = 0.026
    for ox, oy, col in panes:
        x0, y0 = ox, oy
        x1, y1 = ox + 0.491, oy + 0.491
        # 圆角矩形遮罩
        cx0, cy0, cx1, cy1 = x0 + rad, y0 + rad, x1 - rad, y1 - rad
        m = ((fx >= x0) & (fx <= x1) & (fy >= y0) & (fy <= y1))
        # 圆角
        for cx, cy in [(cx0, cy0), (cx1, cy0), (cx0, cy1), (cx1, cy1)]:
            outside = ((fx - cx) ** 2 + (fy - cy) ** 2) > rad ** 2
            inx = ((cx == cx0) & (fx < cx0)) | ((cx == cx1) & (fx > cx1))
            iny = ((cy == cy0) & (fy < cy0)) | ((cy == cy1) & (fy > cy1))
            m &= ~(outside & inx & iny)
        # 每块内部做上亮下暗，做出玻璃质感
        shade = 1.0 + (0.16 * (1 - (fy - y0) / 0.485) - 0.10 * ((fy - y0) / 0.485))
        flat[m, :3] = np.array(col, float) * shade[m][:, None]
        flat[m, 3] = 255

    # 透视四边形（左大右小，整体略斜）——坐标按 16:10 画面
    dst = [(0.062 * W, 0.286 * H), (0.452 * W, 0.338 * H),
           (0.432 * W, 0.744 * H), (0.044 * W, 0.706 * H)]
    src = [(0, 0), (S, 0), (S, S), (0, S)]
    Hm = homography(src, dst)
    Hi = np.linalg.inv(Hm)

    xs0 = int(min(p[0] for p in dst)) - 8
    xs1 = int(max(p[0] for p in dst)) + 8
    ys0 = int(min(p[1] for p in dst)) - 8
    ys1 = int(max(p[1] for p in dst)) + 8
    yy, xx = np.mgrid[ys0:ys1, xs0:xs1].astype(np.float64)
    den = Hi[2, 0] * xx + Hi[2, 1] * yy + Hi[2, 2]
    sx = (Hi[0, 0] * xx + Hi[0, 1] * yy + Hi[0, 2]) / den
    sy = (Hi[1, 0] * xx + Hi[1, 1] * yy + Hi[1, 2]) / den
    # 让旗面有 Win7 那种起伏：横向波浪位移
    sx = sx + 26 * np.sin(2 * math.pi * (sy / S) * 1.15) * (0.35 + 0.65 * sx / S)
    inside = (sx >= 0) & (sx <= S - 1) & (sy >= 0) & (sy <= S - 1)
    samp = bilinear(flat, np.where(inside, sx, 0), np.where(inside, sy, 0))
    samp[~inside] = 0

    piece = Image.fromarray(np.clip(samp, 0, 255).astype(np.uint8), "RGBA")

    # 外发光（原图旗子周围是冷白偏蓝的柔光，不能糊成一块"底板"）
    alpha = piece.split()[3]
    halo = Image.new("RGBA", piece.size, (150, 214, 255, 0))
    halo.putalpha(alpha.filter(ImageFilter.GaussianBlur(64)).point(lambda v: int(v * 0.62)))

    canvas_rgba = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8)).convert("RGBA")
    layer = Image.new("RGBA", piece.size, (0, 0, 0, 0))
    layer.alpha_composite(halo)
    # 投影
    sh = Image.new("RGBA", piece.size, (0, 0, 0, 0))
    sh.putalpha(alpha.filter(ImageFilter.GaussianBlur(34)).point(lambda v: int(v * 0.5)))
    layer.alpha_composite(sh, (10, 18))
    layer.alpha_composite(piece)
    canvas_rgba.alpha_composite(layer, (xs0, ys0))

    arr = np.array(canvas_rgba.convert("RGB"), float)

    # 玻璃表面的斜向高光条（在画布空间画，方便只落在旗子上）
    mask = np.zeros((H, W), float)
    mask[ys0:ys1, xs0:xs1] = np.array(piece.split()[3], float) / 255.0
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    nx, ny = xx / W, yy / H
    for c, wid, amp in [(-0.02, 0.030, 62), (0.10, 0.017, 40), (0.235, 0.011, 26)]:
        t = nx * 1.05 + ny * 0.55 - c
        streak = np.exp(-(t / wid) ** 2) * amp
        arr += (streak * mask)[..., None]
    # 旗子上缘的一道硬高光
    edge = np.exp(-(((ny - 0.318) * 46) ** 2)) * mask * 26
    arr += edge[..., None]

    return np.clip(arr, 0, 255)


# ── 3. 碎玻璃 ───────────────────────────────────────────────────────────

def hole_polygon(cx, cy, r, spikes=11):
    """撞击洞：不规则多边形，像被撞穿的玻璃缺口（不是规则星形）"""
    pts = []
    n = spikes * 2
    a0 = random.uniform(0, 1)
    for i in range(n):
        a = 2 * math.pi * (i + a0) / n + random.uniform(-0.13, 0.13)
        if i % 2 == 0:
            rr = r * random.uniform(1.00, 1.16)
        else:
            rr = r * random.uniform(0.72, 0.90)
        pts.append((cx + math.cos(a) * rr * 1.25, cy + math.sin(a) * rr * 0.95))
    return pts


def make_glass(canvas, impact, hole_pts):
    cx, cy = impact
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def jag(p0, p1, step, amp, kink=0.0):
        """两点之间画一条裂纹：短线段 + 小抖动 + 偶尔的硬折角"""
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        ln = max(math.hypot(dx, dy), 1e-3)
        nxv, nyv = -dy / ln, dx / ln
        steps = max(2, int(ln / step))
        out = [p0]
        for i in range(1, steps + 1):
            t = i / steps
            x = p0[0] + dx * t
            y = p0[1] + dy * t
            k = random.uniform(-amp, amp) * (1.0 if i < steps else 0.15)
            if random.random() < kink:
                k += random.choice([-1, 1]) * random.uniform(6, 18)
            out.append((x + nxv * k, y + nyv * k))
        return out

    def stroke(pts, w, a):
        d.line(pts, fill=(255, 255, 255, a), width=max(1, int(round(w))), joint="curve")

    R = math.hypot(W, H)

    # ① 主放射裂纹：长短混合，不能像太阳光一样整圈等长
    n_rays = 46
    rays = []
    for i in range(n_rays):
        a = 2 * math.pi * i / n_rays + random.uniform(-0.07, 0.07)
        rays.append(a)
        long_one = random.random() < 0.28
        length = R * (random.uniform(0.50, 1.02) if long_one else random.uniform(0.16, 0.52))
        end = (cx + math.cos(a) * length, cy + math.sin(a) * length)
        seg = jag((cx, cy), end, 88, 4.5, kink=0.12)
        a_main = random.randint(150, 215)
        stroke(seg, 2.0, a_main)
        stroke(seg, 1.0, int(a_main * 0.75))

        # ② 分叉（裂纹分叉角一般 30~55°）
        for _ in range(random.randint(1, 3)):
            k = random.randint(2, max(3, len(seg) - 2))
            bx, by = seg[k]
            ba = a + random.choice([-1, 1]) * random.uniform(0.28, 0.62)
            bl = length * random.uniform(0.08, 0.26)
            bseg = jag((bx, by), (bx + math.cos(ba) * bl, by + math.sin(ba) * bl),
                       70, 3.5, kink=0.10)
            stroke(bseg, 1.0, 120)
            # ③ 极细的末端毛发裂
            if random.random() < 0.55:
                m = random.randint(1, max(1, len(bseg) - 2))
                hx, hy = bseg[m]
                ha = ba + random.choice([-1, 1]) * random.uniform(0.30, 0.75)
                hl = bl * random.uniform(0.25, 0.55)
                stroke(jag((hx, hy), (hx + math.cos(ha) * hl, hy + math.sin(ha) * hl),
                           50, 2.5), 0.8, 85)

    # ④ 环向裂纹：把相邻放射线连起来，形成蛛网
    for i in range(n_rays):
        a0, a1 = rays[i], rays[(i + 1) % n_rays]
        for _ in range(random.randint(2, 5)):
            r0 = R * random.uniform(0.04, 0.62)
            r1 = r0 * random.uniform(0.82, 1.20)
            p0 = (cx + math.cos(a0) * r0 * 1.02, cy + math.sin(a0) * r0 * 0.94)
            p1 = (cx + math.cos(a1) * r1 * 1.02, cy + math.sin(a1) * r1 * 0.94)
            seg = jag(p0, p1, 60, 3.0)
            stroke(seg, 0.9, random.randint(60, 130))

    # ⑤ 洞周围的粉碎带：密集短裂 + 白化
    for _ in range(620):
        a = random.uniform(0, 2 * math.pi)
        r0 = random.uniform(0.10, 0.26) * W
        r1 = r0 * random.uniform(1.04, 1.55)
        p0 = (cx + math.cos(a) * r0 * 1.2, cy + math.sin(a) * r0 * 0.92)
        p1 = (cx + math.cos(a) * r1 * 1.2, cy + math.sin(a) * r1 * 0.92)
        stroke(jag(p0, p1, 26, 3.0), random.uniform(0.7, 1.6), random.randint(40, 120))

    # ⑤ 次级撞击点：附近的局部小裂纹簇，打破"太阳光"式的放射感
    for _ in range(6):
        sx0 = cx + random.gauss(0, 0.20 * W)
        sy0 = cy + random.gauss(0, 0.24 * H)
        if abs(sx0 - cx) < 0.13 * W and abs(sy0 - cy) < 0.14 * H:
            continue
        for _ in range(random.randint(8, 16)):
            aa = random.uniform(0, 2 * math.pi)
            ll = random.uniform(0.012, 0.052) * W
            stroke(jag((sx0, sy0), (sx0 + math.cos(aa) * ll, sy0 + math.sin(aa) * ll), 30, 2.5),
                   0.9, random.randint(45, 105))

    # ⑥ 洞口透出来的光：破口周围一圈柔和白光
    rr = np.hypot(np.mgrid[0:H, 0:W][1] - cx, np.mgrid[0:H, 0:W][0] - cy).astype(np.float32)
    burst = np.clip(1.0 - (rr - 0.115 * W) / (0.16 * W), 0, 1) ** 3.0
    burst_img = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    burst_img.putalpha(Image.fromarray((burst * 58).astype(np.uint8)))
    layer = Image.alpha_composite(layer, burst_img)
    d = ImageDraw.Draw(layer)

    # ⑦ 洞内要清干净：裂纹不能糊在照片上（只保留洞口外的部分）
    keep = Image.new("L", (W, H), 255)
    ImageDraw.Draw(keep).polygon(hole_pts, fill=0)
    keep = keep.filter(ImageFilter.GaussianBlur(2))
    layer.putalpha(ImageChops.multiply(layer.split()[3], keep))

    # ⑦ 洞边缘：亮白边（玻璃断口的厚度感）
    d.polygon(hole_pts, outline=(255, 255, 255, 255), width=7)
    d.polygon(hole_pts, outline=(226, 243, 255, 175), width=2)

    # 光晕（裂纹自带的微弱辉光）
    glow = layer.filter(ImageFilter.GaussianBlur(6))
    glow2 = layer.filter(ImageFilter.GaussianBlur(24))
    glass = ImageChops.add(layer, ImageChops.add(glow, glow2.point(lambda v: int(v * 0.5))))
    # 统一成冷白偏蓝的玻璃色
    arr = np.array(glass, float)
    arr[..., 0] *= 0.93
    arr[..., 1] *= 0.98
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


# ── 4. 洞里的照片 ───────────────────────────────────────────────────────

def make_cat(photo_path, hole_pts, impact):
    im = Image.open(photo_path).convert("RGB")
    w, h = im.size
    # 裁掉右下角 AI 水印
    im = im.crop((0, 0, w, int(h * 0.90)))
    cx, cy = impact
    # 让猫脸落在洞口：照片按洞口宽度的 ~3.2 倍铺开
    tw = int(W * 0.46)
    th = int(tw * im.size[1] / im.size[0])
    im = im.resize((tw, th), Image.LANCZOS)
    # 照片色调整体偏冷一点点，跟玻璃反光统一
    arr = np.array(im, float)
    arr[..., 2] *= 1.06
    arr[..., 1] *= 1.01
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))

    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = int(cx - tw * 0.50)
    py = int(cy - th * 0.44)
    canvas.paste(im, (px, py))

    mask = Image.new("L", (W, H), 0)
    # 照片的遮罩比洞口外扩一点：玻璃层推镜比照片层快，不外扩会露出底板的一条蓝边
    grown = [(cx + (x - cx) * 1.045, cy + (y - cy) * 1.045) for x, y in hole_pts]
    ImageDraw.Draw(mask).polygon(grown, fill=255)
    canvas.putalpha(mask)
    return canvas


# ── main ────────────────────────────────────────────────────────────────

def main(photo):
    import os
    os.makedirs(OUT, exist_ok=True)

    impact = (0.700 * W, 0.215 * H)
    hole = hole_polygon(impact[0], impact[1], 0.108 * W, spikes=18)

    bg = make_bg()
    bg = make_flag(bg)

    cat = make_cat(photo, hole, impact)
    glass = make_glass(bg, impact, hole)

    Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8)).save(f"{OUT}/bg.png")
    cat.save(f"{OUT}/cat.png")
    glass.save(f"{OUT}/glass.png")

    # 预览用合成图
    prev = Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8)).convert("RGBA")
    prev.alpha_composite(cat)
    prev.alpha_composite(glass)
    prev.convert("RGB").resize((1726, 1080), Image.LANCZOS).save(f"{OUT}/preview.jpg", quality=92)
    print("ok", f"{OUT}/preview.jpg")


if __name__ == "__main__":
    import sys
    main(sys.argv[1])
