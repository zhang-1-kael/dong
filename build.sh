#!/bin/zsh
# 编译打包 App（含内置 ffmpeg，可直接拷给别人）
set -e
cd "$(dirname "$0")"

APP="build/VideoWallpaper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"

echo "==> 编译 Swift"
swiftc -O -o "$APP/Contents/MacOS/VideoWallpaper" \
  main.swift Downloader.swift LockScreen.swift Transcoder.swift LibraryWindow.swift Panel.swift Presets.swift Analytics.swift Updater.swift FrameHealth.swift \
  -framework Cocoa -framework AVFoundation

echo "==> 组装 App Bundle"
cp Info.plist "$APP/Contents/Info.plist"
if [ -f build/wallpaper.mp4 ]; then
  cp build/wallpaper.mp4 "$APP/Contents/Resources/wallpaper.mp4"
fi

# 默认壁纸：presets/ 里的素材跟着包走，用户首次启动时自动进他的壁纸库
# 注意：Presets.installIfNeeded() 必须在 main.swift 里被调用，否则这些文件只是白占体积。
# 还没接线时用 VW_NO_PRESETS=1 ./build.sh 打包，DMG 会瘦 360MB。
PRESETS="presets"
if [ -n "$VW_NO_PRESETS" ]; then
  echo "==> 跳过内置壁纸（VW_NO_PRESETS=1）"
elif [ -d "$PRESETS" ] && [ -n "$(ls -A "$PRESETS" 2>/dev/null)" ]; then
  mkdir -p "$APP/Contents/Resources/presets"
  # zsh 的 (N) 是 null_glob：某个扩展名一个文件都没有也不会报错
  for f in "$PRESETS"/*.mp4(N) "$PRESETS"/*.mov(N) "$PRESETS"/*.m4v(N); do
    cp "$f" "$APP/Contents/Resources/presets/"
  done
  N=$(ls -1 "$APP/Contents/Resources/presets" | wc -l | tr -d ' ')
  if [ "$N" -gt 0 ]; then
    echo "==> 内置默认壁纸 $N 个（$(du -sh "$APP/Contents/Resources/presets" | cut -f1)）"
    xattr -c "$APP/Contents/Resources/presets"/* 2>/dev/null || true
  else
    rmdir "$APP/Contents/Resources/presets" 2>/dev/null || true
    echo "!! presets/ 里没有可用的视频文件（支持 mp4/mov/m4v）"
  fi
fi

FF="${VW_FFMPEG:-$HOME/.local/bin/ffmpeg}"
if [ -x "$FF" ]; then
  echo "==> 内置 ffmpeg（$(du -h "$FF" | cut -f1)）"
  cp "$FF" "$APP/Contents/Resources/bin/ffmpeg"
  chmod +x "$APP/Contents/Resources/bin/ffmpeg"
else
  echo "!! 没找到 ffmpeg：App 会退而使用系统里的 ffmpeg"
fi

# 链接解析（B 站 / YouTube 等）：PyInstaller 打包的独立二进制，自带运行时
YTDLP="vendor/yt-dlp_macos"
if [ -f "$YTDLP" ]; then
  echo "==> 内置 yt-dlp（$(du -h "$YTDLP" | cut -f1)）"
  cp "$YTDLP" "$APP/Contents/Resources/bin/yt-dlp"
  chmod +x "$APP/Contents/Resources/bin/yt-dlp"
  xattr -c "$APP/Contents/Resources/bin/yt-dlp" 2>/dev/null || true
else
  echo "!! 没有 vendor/yt-dlp_macos：链接下载功能会退回使用系统里的 yt-dlp"
fi

# App 图标：存在就装进 bundle（Info.plist 里 CFBundleIconFile = AppIcon）
if [ -f AppIcon.icns ]; then
  echo "==> 装入图标"
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# 界面里的 logo：面板左上角的徽章 + 菜单栏彩色果冻 + 单色模板（brand/ 生成，勿手改）
for f in BrandMark.png BrandMarkBadge.png BrandMarkMenu.png BrandMarkTemplate.png; do
  if [ -f "$f" ]; then
    cp "$f" "$APP/Contents/Resources/$f"
  fi
done

# 摇摆动画帧：图标不再是「整张图转角度」，而是逐帧重绘的真果冻形变
# 由 ../jelly-anim/export_icons.py 生成，30 帧 = 一个完整来回
if [ -d icons ] && [ -n "$(ls -A icons 2>/dev/null)" ]; then
  N=$(ls -1 icons/*.png(N) | wc -l | tr -d ' ')
  cp icons/*.png(N) "$APP/Contents/Resources/"
  echo "==> 摇摆图标帧 $N 张"
else
  echo "!! icons/ 是空的：菜单栏和徽章会退回静态图标"
fi

# 本地开发用 ad-hoc 签名：只能自己这台机器跑。
# 要分发给别人（过 Gatekeeper）请勿改这里，改用：
#   VW_SIGN_ID="Developer ID Application: 名字 (TEAMID)" ./sign-notarize.sh
echo "==> 本地签名（ad-hoc，仅供本机测试）"
codesign --force --deep --sign - "$APP"

echo "==> 完成: $APP"
