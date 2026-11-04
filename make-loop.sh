#!/bin/zsh
# 把任意视频做成"无缝循环"壁纸素材：转恒定帧率 + 尾部与头部交叉淡化
# 用法: ./make-loop.sh 输入视频 输出mp4 [淡化秒数=0.4] [目标尺寸=2408x1506]

set -e
FF=~/.local/bin/ffmpeg

IN="$1"
OUT="$2"
FADE="${3:-0.4}"
SIZE="${4:-2408x1506}"
MASK="$5"   # 可选：水印掩膜 PNG（白色=要抹掉的区域，坐标按输入视频原始分辨率）
PRECROP="$6" # 可选：先裁掉一块再缩放的区域，格式 x:y:w:h（比掩膜修补更干净，用于角落水印）
CRF="${7:-18}" # 可选：质量参数，18 为高保真；颗粒/雨雪类素材用 22-24 可省 30% 体积且几乎无差
WIDTH="${SIZE%%x*}"
HEIGHT="${SIZE##*x}"

if [[ -z "$IN" || -z "$OUT" ]]; then
  echo "用法: ./make-loop.sh 输入视频 输出mp4 [淡化秒数] [目标尺寸如 2408x1506] [水印掩膜png] [预裁切 x:y:w:h]" >&2
  exit 1
fi

DELOGO=""
if [[ -n "$MASK" ]]; then
  if [[ ! -f "$MASK" ]]; then echo "掩膜文件不存在: $MASK" >&2; exit 1; fi
  DELOGO="removelogo=filename=${MASK},"
fi

PRECROP_FILTER=""
if [[ -n "$PRECROP" ]]; then
  PCX="${PRECROP%%:*}"; REST="${PRECROP#*:}"
  PCY="${REST%%:*}"; REST="${REST#*:}"
  PCW="${REST%%:*}"; PCH="${REST##*:}"
  PRECROP_FILTER="crop=${PCW}:${PCH}:${PCX}:${PCY},"
fi

# 取时长（无 ffprobe，从 ffmpeg 输出解析）
DUR=$($FF -hide_banner -i "$IN" 2>&1 \
  | sed -n 's/.*Duration: \([0-9][0-9]*\):\([0-9][0-9]*\):\([0-9][0-9.]*\).*/\1 \2 \3/p' \
  | head -1 | awk '{printf "%.3f", $1*3600 + $2*60 + $3}')
if [[ -z "$DUR" ]]; then echo "无法读取时长" >&2; exit 1; fi

# 取帧率，用于定 CFR
FPS=$($FF -hide_banner -i "$IN" 2>&1 | sed -n 's/.*, \([0-9.]*\) fps.*/\1/p' | head -1)
[[ -z "$FPS" ]] && FPS=30
CFR=$(echo "$FPS" | awk '{printf "%d", ($1>30)?30:$1}')
[[ "$CFR" -lt 1 ]] && CFR=30

CUT=$(echo "$DUR - $FADE" | bc)

# 素材本身已经是循环（如 B 站壁纸），淡化传 0 即可只做转码/裁切
# removelogo / 预裁切 必须放在 scale 之前，坐标才对得上原始分辨率
BASE="${DELOGO}${PRECROP_FILTER}fps=${CFR},scale=${WIDTH}:${HEIGHT}:flags=lanczos:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},unsharp=5:5:0.4:5:5:0,format=yuv420p"

if [[ "$(echo "$FADE <= 0" | bc)" == "1" ]]; then
  echo "时长=${DUR}s 原帧率=${FPS} → 统一 ${CFR}fps，不做淡化（原片已是循环）→ ${SIZE}"
  $FF -hide_banner -loglevel error -y -i "$IN" -vf "$BASE" \
    -an -c:v libx264 -profile:v high -pix_fmt yuv420p -crf ${CRF} -preset medium \
    -r ${CFR} -g $((CFR*2)) -movflags +faststart "$OUT"
  echo "完成: $OUT"
  exit 0
fi

echo "时长=${DUR}s 原帧率=${FPS} → 统一 ${CFR}fps，淡化 ${FADE}s → ${SIZE}，成片 ${CUT}s"

$FF -hide_banner -loglevel error -y -i "$IN" -filter_complex "\
[0:v]${BASE},split=3[s0][s1][s2];\
[s0]trim=start=0:end=${FADE},setpts=PTS-STARTPTS,setsar=1[b];\
[s1]trim=start=${CUT}:end=${DUR},setpts=PTS-STARTPTS,setsar=1[a];\
[a][b]blend=all_expr='A*(1-T/${FADE})+B*(T/${FADE})':shortest=1[mix];\
[s2]trim=start=${FADE}:end=${CUT},setpts=PTS-STARTPTS,setsar=1[mid];\
[mix][mid]concat=n=2:v=1:a=0[out]" \
  -map "[out]" -an -c:v libx264 -profile:v high -pix_fmt yuv420p -crf ${CRF} -preset medium -r ${CFR} -g $((CFR*2)) -movflags +faststart "$OUT"

echo "完成: $OUT"
