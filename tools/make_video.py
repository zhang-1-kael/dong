#!/usr/bin/env python3
"""把静态三层合成为可循环的动态壁纸。

视差：背景最远、猫在玻璃后面居中、裂纹玻璃最近 → 三者缩放幅度依次变大，
推镜时产生"隔着玻璃往里看"的层次感。12 秒余弦往返，首尾完全对齐，可无缝循环。
"""
import math
import subprocess
import sys
import numpy as np
from PIL import Image, ImageChops, ImageEnhance

SRC = "build_scene"
OUT_MP4 = sys.argv[1] if len(sys.argv) > 1 else "build_scene/out.mp4"
FFMPEG = "/Users/zhanghangshuo/.local/bin/ffmpeg"

OW, OH = 1726, 1080
FPS = 30
SECONDS = 12
FRAMES = FPS * SECONDS

bg = Image.open(f"{SRC}/bg.png").convert("RGB")
cat = Image.open(f"{SRC}/cat.png").convert("RGBA")
glass = Image.open(f"{SRC}/glass.png").convert("RGBA")
SW, SH = bg.size


def crop_zoom(img, z, cx, cy):
    cw, ch = SW / z, SH / z
    x0 = min(max(cx - cw / 2, 0), SW - cw)
    y0 = min(max(cy - ch / 2, 0), SH - ch)
    return img.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).resize(
        (OW, OH), Image.LANCZOS, reducing_gap=2.0)


# 扫过玻璃的高光：一张够宽的斜向柔光带，逐帧横向平移后做 screen 叠加
GW = OW * 2
glare_mask = Image.new("L", (GW, OH), 0)
d = np.zeros((OH, GW), float)
yy, xx = np.mgrid[0:OH, 0:GW].astype(np.float32)
t = (xx / GW) * 1.0 + (yy / OH) * 0.55
band = np.exp(-((t - 0.42) / 0.055) ** 2) * 0.7 + np.exp(-((t - 0.30) / 0.020) ** 2) * 0.5
# 竖向渐隐，别让高光在地平线上是一条硬条
band *= np.clip(1.0 - np.abs(yy / OH - 0.42) / 0.85, 0, 1)
glare_mask = Image.fromarray(np.clip(band * 42, 0, 255).astype(np.uint8))
glare_rgb = Image.new("RGB", (GW, OH), (232, 244, 255))


def frame(i):
    t = i / FRAMES
    e = 0.5 - 0.5 * math.cos(2 * math.pi * t)      # 0→1→0，首尾对齐

    # 镜头中心缓慢移向破洞，再回来
    cx = SW * (0.500 + 0.012 * e)
    cy = SH * (0.480 - 0.008 * e)

    z_bg = 1.000 + 0.020 * e
    z_cat = 1.036 + 0.024 * e
    z_gl = 1.052 + 0.030 * e

    base = crop_zoom(bg, z_bg, cx, cy)
    # 猫轻轻起伏一下（呼吸），幅度控制在 ~3px，不会被洞口边缘发现
    c = crop_zoom(cat, z_cat, cx, cy + 7.0 * math.sin(2 * math.pi * t))
    g = crop_zoom(glass, z_gl, cx, cy)

    out = base.convert("RGBA")
    out.alpha_composite(c)
    out.alpha_composite(g)
    rgb = out.convert("RGB")

    # 高光扫过
    off = int(-OW * 0.55 + (GW - OW * 0.2) * e)
    gm = glare_mask.crop((off, 0, off + OW, OH))
    gr = glare_rgb.crop((off, 0, off + OW, OH))
    gimg = Image.merge("RGB", [ImageChops.multiply(gr.split()[k], gm) for k in range(3)])
    rgb = ImageChops.screen(rgb, gimg)

    # 极轻微的整体呼吸，避免画面"死板"
    k = 1.0 + 0.010 * math.sin(2 * math.pi * t)
    return ImageEnhance.Brightness(rgb).enhance(k)


def main():
    cmd = [FFMPEG, "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{OW}x{OH}",
           "-r", str(FPS), "-i", "-",
           "-an", "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p",
           "-crf", "20", "-preset", "medium", "-maxrate", "14M", "-bufsize", "28M",
           "-r", str(FPS), "-g", str(FPS * 2), "-movflags", "+faststart", OUT_MP4]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    assert p.stdin is not None
    for i in range(FRAMES):
        p.stdin.write(frame(i).tobytes())
        if i % 60 == 0:
            print(f"  {i}/{FRAMES}", flush=True)
    p.stdin.close()
    p.wait()
    print("done", OUT_MP4, "code", p.returncode)


if __name__ == "__main__":
    main()
