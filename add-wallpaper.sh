#!/bin/zsh
# 把原始录屏批量转换成"无缝循环壁纸"并放进壁纸库
# 用法: ./add-wallpaper.sh 视频1.mov [视频2.mov ...]

set -e
cd "$(dirname "$0")"

DIR="$HOME/Library/Application Support/VideoWallpaper/wallpapers"
mkdir -p "$DIR"

if [[ $# -eq 0 ]]; then
  echo "用法: ./add-wallpaper.sh 视频1.mov [视频2.mov ...]" >&2
  exit 1
fi

for f in "$@"; do
  if [[ ! -f "$f" ]]; then
    echo "跳过（找不到）: $f" >&2
    continue
  fi
  name="$(basename "${f%.*}")"
  # 去掉文件名里的空格，避免后续命令行麻烦
  name="${name// /-}"
  out="$DIR/${name}.mp4"
  echo "==> 处理 $f"
  ./make-loop.sh "$f" "$out" 0.4 2408x1506
done

echo ""
echo "壁纸库现有："
ls -1 "$DIR" | grep -Ei '\.(mp4|mov|m4v)$' | nl
echo ""
echo "在菜单栏图标里点「重新加载素材」，再用「切换下一个壁纸」轮换。"
