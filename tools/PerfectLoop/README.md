# 🎞️ PerfectLoop

Create perfectly seamless video loops with advanced frame blending, morphing, and similarity analysis — powered by OpenCV and SSIM. Ideal for game captures, ambient loops, animations, or looping media content.

## 🧠 Key Features

- 🔁 **Loop Completion** — Morphs last frame to first for seamless playback
- 🧬 **Region-Aware Morphing** — Focuses only on changing regions using SSIM
- ⚡ **Speed Control** — Slow down or speed up loop playback
- 🧠 **Best Frame Detection** — Find optimal loop points with `findbestframe.py`
- ✂️ **Manual + Auto Trimming** — Use `analyze_manual.py` or `trim_logic.py`
- 📊 **Visualization Tools** — Compare similarity maps and generate diagnostics

## 📂 Folder Structure

```
PerfectLoop/
├── analyze_manual.py         # Manual start-end frame selection & trim
├── analyze.py                # SSIM-based frame similarity analysis
├── generate_loop.py          # CLI wrapper to create trimmed loop
├── README.md
├── requirements.txt
├── simpleloop.py             # Basic end-to-start morphing loop generator
├── simpleloop_adv.py         # Optical flow & bidirectional morphing
├── src/
│   ├── findbestframe.py      # SSIM loop frame ranking
│   └── trim_logic.py         # Core trimming logic
└── test/
    ├── *.mkv / *.png         # Sample test videos and visual outputs
```

## 🚀 Quick Start

### 🔧 Install Requirements

```bash
pip install -r requirements.txt
```

### 📹 Create a Basic Loop

```bash
python simpleloop.py test/hk_greenpath.mkv test/hk_greenpath_looped.mkv --speed 1.0 --morph_steps 20
```

This creates a loop where the last frame is morphed smoothly into the first using linear blending.

### 🧠 Use Advanced Morphing

```bash
python simpleloop_adv.py test/hk_greenpath.mkv test/hk_greenpath_looped_adv.mkv --speed 1.0 --morph_steps 20
```

This version uses optical flow-based bidirectional warping for more natural transitions.

### 🧠 Region-Aware Smart Looping (Recommended)

```bash
python generate_loop.py --input test/hk_greenpath.mkv --output test/hk_greenpath_looped_adv2.mkv --speed 1.0 --morph_steps 20
```

This uses SSIM to morph only dissimilar regions and fade others into place — resulting in less jittery, more forward-natural loops.

## 🔍 Analyze & Trim Videos

### Analyze Similarity

```bash
python analyze.py test/hk_greenpath.mkv
```

Outputs `ssim_diff_map.png`, `full_similarity.png`, etc. to help you understand best loop points.

### Trim with Manual Frames

```bash
python analyze_manual.py --input test/hk_greenpath.mkv --start 15 --end 292 --output test/hk_greenpath_trimmed.mkv
```

## 📌 Use in Code

You can import the modules and reuse the logic inside:

```python
from src.findbestframe import find_best_loop_frames
from src.trim_logic import trim_video

# Logic to programmatically select, trim, and morph frames into a loop
```

## 📷 Example Output

| SSIM Map | Start vs End Frame |
|----------|-------------------|
| ![SSIM](test/full_similarity.png) | Visual comparison |

## 🧩 Requirements

- Python 3.8+
- OpenCV
- NumPy  
- scikit-image

```bash
pip install opencv-python numpy scikit-image
```

## 🔮 Future Ideas

- [ ] Optical Flow + SSIM hybrid warping
- [ ] Loop-aware video stabilization  
- [ ] Interactive CLI for manual frame selection
- [ ] Batch loop generation for folders


## **🧑‍💻 Author**

Built by an engineer who got tired of manually creating seamless loops for video wallaper. Let algorithms handle the tedious frame-by-frame work.

## 📜 License

MIT License — feel free to use, improve, and share.

---