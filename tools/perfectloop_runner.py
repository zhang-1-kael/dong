#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
perfectloop_runner.py —— 把 PerfectLoop 的「SSIM 区域感知形变」无缝循环接进 Dòng 的生成管线。

为什么不直接用官方 create_loop_video：
    官方会把整段视频所有帧一次性读进内存（read_all_frames）。壁纸动辄几十秒 1080p，
    几千帧 × 全分辨率会轻松吃掉几 GB 甚至被系统 SIGKILL。
本脚本的做法（效果与官方一致）：
    1. 只读取源视频的【首帧】和【尾帧】（各一次 seek），内存占用恒定 ≈ 2 帧；
    2. 调用 PerfectLoop 核心函数 compute_difference_mask + hybrid_morph_frames，
       只在首尾「不一样」的区域做加权形变，相似区域直接淡入首帧；
    3. 用 ffmpeg 把「主体 + 形变段」拼接，并重编码为 h264（与 App 转码参数一致）。

用法：
    perfectloop_runner.py INPUT OUTPUT --width W --height H --fps F --crf C
        [--start S] [--duration D] [--delogo x:y:w:h] [--morph_steps N] [--ffmpeg PATH]
    perfectloop_runner.py --check        # 自检依赖（numpy / opencv / scikit-image / PerfectLoop）

进度：向 stdout 输出 `progress=<0..1>` 行，供调用方（Swift）刷新进度条。
依赖：numpy opencv-python scikit-image  （PerfectLoop 的 LICENSE 见同目录 PerfectLoop/LICENSE，MIT）
"""
import os
import sys

# 本脚本随 App 一起 codesign 签名。Python 若在 App 包内写 __pycache__/*.pyc，
# 会新增未登记资源、破坏签名封印，导致下次启动被判「已损坏」。禁止写字节码。
sys.dont_write_bytecode = True

import json
import threading
import subprocess
import argparse

_HERE = os.path.dirname(os.path.abspath(__file__))
# 让本脚本能 import 到同目录下的 PerfectLoop 核心模块
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.join(_HERE, "PerfectLoop"))


def check_deps():
    """返回 (ok: bool, msg: str)。"""
    try:
        import numpy  # noqa: F401
        import cv2    # noqa: F401
        import skimage  # noqa: F401
        import simpleloop_adv  # noqa: F401
    except Exception as exc:  # pragma: no cover
        return False, "缺少依赖：%s" % exc
    return True, "OK"


def find_ffmpeg(explicit):
    if explicit:
        return explicit
    for p in [os.path.expanduser("~/.local/bin/ffmpeg"),
              "/opt/homebrew/bin/ffmpeg",
              "/usr/local/bin/ffmpeg"]:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return "ffmpeg"


def _progress_reader(proc, total_us, out):
    """后台线程：读 ffmpeg -progress 的 stdout，折算进度并打印 progress= 给上层。"""
    try:
        for raw in proc.stdout:
            if not raw:
                continue
            line = raw.decode("utf-8", "ignore") if isinstance(raw, bytes) else raw
            if line.startswith("out_time_us="):
                try:
                    us = float(line[len("out_time_us="):].strip())
                except ValueError:
                    continue
                pct = min(1.0, max(0.0, us / total_us)) if total_us > 0 else 0.0
                out.write("progress=%.4f\n" % pct)
                out.flush()
    except Exception:
        pass


def _run_impl(input_path, output_path, width, height, fps, crf, start, duration,
              delogo, morph_steps, ffmpeg, precrop=""):
    import cv2
    import numpy as np
    from simpleloop_adv import compute_difference_mask, hybrid_morph_frames

    fps = max(1, int(round(fps)))
    width = int(width)
    height = int(height)
    morph_steps = max(0, int(morph_steps))

    out_dir = os.path.dirname(os.path.abspath(output_path))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    # ── 1) 只读取首帧 / 尾帧（BGR）─────────────────────────────────────
    cap = cv2.VideoCapture(input_path)
    if not cap.isOpened():
        sys.stderr.write("无法打开源视频: %s\n" % input_path)
        return 2
    src_fps = cap.get(cv2.CAP_PROP_FPS) or float(fps)
    n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)

    def read_at(idx):
        if n > 0:
            idx = min(max(0, idx), n - 1)
            cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ret, fr = cap.read()
        return ret, fr

    start_idx = int(round(start * src_fps)) if start > 0 else 0
    ret0, f0 = read_at(start_idx)
    if not ret0 or f0 is None:
        sys.stderr.write("读取首帧失败\n")
        cap.release()
        return 2

    end_idx = int(round((start + duration) * src_fps))
    retN, fN = read_at(end_idx if n <= 0 else max(0, end_idx))
    if not retN or fN is None:
        # 回退：从头顺序读到最后一帧
        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
        fN = f0
        while True:
            r, fr = cap.read()
            if not r:
                break
            fN = fr
    cap.release()

    # 预裁切（坐标按源分辨率）：用于抹掉角落水印等。首尾帧与主体链都裁，保证一致
    if precrop:
        pp = precrop.split(":")
        if len(pp) == 4:
            px, py, pw, ph = (int(float(v)) for v in pp)
            px = max(0, min(px, f0.shape[1] - 1))
            py = max(0, min(py, f0.shape[0] - 1))
            pw = max(1, min(pw, f0.shape[1] - px))
            ph = max(1, min(ph, f0.shape[0] - py))
            f0 = f0[py:py + ph, px:px + pw]
            fN = fN[py:py + ph, px:px + pw]

    sw, sh = f0.shape[1], f0.shape[0]

    # 帧数太少 / 不做形变：直接出主体
    do_morph = morph_steps >= 1 and duration >= 0.5
    if do_morph:
        sys.stderr.write("[PerfectLoop] 计算首尾 SSIM 差异掩膜并生成形变中间帧…\n")
        mask = compute_difference_mask(fN, f0, threshold=0.25, blur_ksize=15)
        morph = hybrid_morph_frames(fN, f0, steps=morph_steps, diff_mask=mask)
        # 强制 BGR uint8、连续内存，方便喂给 ffmpeg rawvideo
        morph = [np.ascontiguousarray(np.clip(m.astype(np.float32), 0, 255).astype(np.uint8))
                 for m in morph if m is not None]
        if len(morph) == 0:
            do_morph = False

    # ── 2) ffmpeg：主体(含裁切/缩放/锐化/去角标) + 形变段 拼接 → h264 ──
    delogo_filter = ""
    if delogo:
        parts = delogo.split(":")
        if len(parts) == 4:
            x, y, w, h = (int(float(p)) for p in parts)
            delogo_filter = "delogo=x=%d:y=%d:w=%d:h=%d," % (x, y, w, h)

    precrop_filter = ""
    if precrop:
        pp = precrop.split(":")
        if len(pp) == 4:
            px, py, pw, ph = (int(float(v)) for v in pp)
            precrop_filter = "crop=%d:%d:%d:%d," % (pw, ph, px, py)

    base_chain = ("fps=%d,%sscale=%d:%d:flags=lanczos,"
                 "unsharp=5:5:0.4:5:5:0,%sformat=yuv420p,setsar=1[body]"
                 % (fps, precrop_filter, width, height, delogo_filter))

    if do_morph:
        morph_chain = ("[1:v]scale=%d:%d:flags=lanczos,format=yuv420p,setsar=1[morph];"
                      "[body][morph]concat=n=2:v=1[v]" % (width, height))
        filter_complex = "[0:v]%s;%s" % (base_chain, morph_chain)
    else:
        filter_complex = "[0:v]%s;%s" % (base_chain, "[body]copy[v]" if False else "[body]null[v]")

    total_us = (duration + (morph_steps / float(fps) if do_morph else 0)) * 1_000_000.0

    cmd = [
        ffmpeg, "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
        "-progress", "pipe:1", "-nostats",
        "-ss", "%.3f" % start, "-t", "%.3f" % duration, "-i", input_path,
    ]
    if do_morph:
        cmd += ["-f", "rawvideo", "-pix_fmt", "bgr24",
                "-s", "%dx%d" % (sw, sh), "-r", str(fps), "-i", "-"]
    cmd += ["-filter_complex", filter_complex, "-map", "[v]",
            "-an", "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p",
            "-crf", str(crf), "-preset", "medium",
            "-maxrate", "80M", "-bufsize", "160M",
            "-r", str(fps), "-g", str(fps * 2),
            "-movflags", "+faststart", output_path]

    sys.stderr.write("[PerfectLoop] ffmpeg: %s\n" % " ".join(cmd[:6]) + " …\n")

    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE if do_morph else subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    reader = threading.Thread(target=_progress_reader, args=(proc, total_us, sys.stdout))
    reader.daemon = True
    reader.start()

    if do_morph:
        try:
            for m in morph:
                proc.stdin.write(m.tobytes())
            proc.stdin.flush()
        except (BrokenPipeError, ValueError):
            pass
        finally:
            try:
                proc.stdin.close()
            except Exception:
                pass

    proc.wait()
    reader.join(timeout=2.0)

    if proc.returncode != 0:
        sys.stderr.write("[PerfectLoop] ffmpeg 退出码 %d\n" % proc.returncode)
        if os.path.exists(output_path):
            try:
                os.remove(output_path)
            except OSError:
                pass
        return proc.returncode or 1

    sys.stdout.write("progress=1.0000\n")
    sys.stdout.flush()
    sys.stderr.write("[PerfectLoop] 无缝循环已生成: %s\n" % output_path)
    return 0


def cli():
    ap = argparse.ArgumentParser(description="PerfectLoop 无缝循环（内存安全版）")
    ap.add_argument("input", nargs="?", help="源视频")
    ap.add_argument("output", nargs="?", help="输出 h264 mp4")
    ap.add_argument("--width", type=int, required=False)
    ap.add_argument("--height", type=int, required=False)
    ap.add_argument("--fps", type=float, default=30)
    ap.add_argument("--crf", type=int, default=18)
    ap.add_argument("--start", type=float, default=0.0)
    ap.add_argument("--duration", type=float, default=0.0)
    ap.add_argument("--delogo", default="", help="x:y:w:h（坐标按目标分辨率）")
    ap.add_argument("--precrop", default="", help="x:y:w:h（坐标按源分辨率，先裁再缩放）")
    ap.add_argument("--morph_steps", type=int, default=14)
    ap.add_argument("--ffmpeg", default="")
    ap.add_argument("--check", action="store_true", help="仅自检依赖")
    args = ap.parse_args()

    if args.check:
        ok, msg = check_deps()
        print(("OK " if ok else "FAIL ") + msg)
        return 0 if ok else 1

    if not args.input or not args.output or not args.width or not args.height:
        ap.error("需要 input / output / --width / --height")

    ok, msg = check_deps()
    if not ok:
        sys.stderr.write("依赖检查失败：%s\n" % msg)
        return 1

    return _run_impl(args.input, args.output, args.width, args.height, args.fps,
                     args.crf, args.start, args.duration, args.delogo,
                     args.morph_steps, find_ffmpeg(args.ffmpeg), args.precrop)


if __name__ == "__main__":
    sys.exit(cli())
