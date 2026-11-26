#!/bin/zsh
# 编译打包 App（含内置 ffmpeg，可直接拷给别人）
set -e
cd "$(dirname "$0")"

APP="build/VideoWallpaper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"

echo "==> 编译 Swift"
swiftc -O -o "$APP/Contents/MacOS/VideoWallpaper" \
  main.swift Downloader.swift DouyinWebFetcher.swift LockScreen.swift Transcoder.swift LibraryWindow.swift Panel.swift Presets.swift Analytics.swift Updater.swift FrameHealth.swift Tuning.swift PerfectLoopInstaller.swift PlaybackPolicy.swift WebWallpaper.swift Rotation.swift Account.swift SyncEngine.swift SyncCenter.swift AccountUI.swift AccountWindow.swift DynamicLockScreen.swift LibraryOwner.swift \
  -framework Cocoa -framework AVFoundation -framework WebKit -framework Security

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

# PerfectLoop 是【用户自选插件】，App 不再内置。
# 原因：它的 Python 依赖环境约 332 MB（numpy/opencv/scipy/scikit-image），打进 DMG
# 会让所有用户都背上这份体积，而多数人用不到。现改为：用户自行下载安装到
#   ~/.local/share/VideoWallpaper/perfectloop-plugin/
# Transcoder 检测到就启用，没装就自动回退内置 blend / 硬切，功能不受影响。
# 导入入口与画面微调面板会给出推荐，并如实标注实测占用（磁盘 330 MB / 峰值内存 340 MB）。
echo "==> PerfectLoop 为用户自选插件：不打包；UI 会给出推荐与占用说明"

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

# 锁屏动态壁纸扩展（.appex）。
# 它只负责锁屏那一层：PlaybackPolicy 里 alwaysPauseDesktop = true 时桌面暂停、
# 只在 presentionMode == locked 渲染，所以和主程序的桌面自绘窗口可以共存。
# 排查构建问题时用 VW_NO_LOCKSCREEN=1 跳过。
if [ -z "$VW_NO_LOCKSCREEN" ] && [ -f build_ext.sh ]; then
  echo "==> 编译锁屏扩展"
  zsh build_ext.sh --build >/dev/null
  mkdir -p "$APP/Contents/Extensions"
  rm -rf "$APP/Contents/Extensions/DongLockScreen.appex"
  cp -R build/DongLockScreen.appex "$APP/Contents/Extensions/"
  echo "==> 内置锁屏扩展（$(du -sh build/DongLockScreen.appex | cut -f1)）"
elif [ -n "$VW_NO_LOCKSCREEN" ]; then
  echo "==> 跳过锁屏扩展（VW_NO_LOCKSCREEN=1）"
else
  echo "==> 跳过锁屏扩展（未包含 build_ext.sh，常见于 CI）"
fi

# 本地开发用 ad-hoc 签名：只能自己这台机器跑。
# 要分发给别人（过 Gatekeeper）请勿改这里，改用：
#   VW_SIGN_ID="Developer ID Application: 名字 (TEAMID)" ./sign-notarize.sh
echo "==> 本地签名（ad-hoc，仅供本机测试）"
# 先签内层扩展（它需要沙盒 entitlement），再签外层 App，顺序不能反。
if [ -d "$APP/Contents/Extensions/DongLockScreen.appex" ]; then
  codesign --force --sign - --options runtime \
    --entitlements build/DongLockScreen.entitlements \
    "$APP/Contents/Extensions/DongLockScreen.appex"
fi
codesign --force --sign - "$APP"

echo "==> 完成: $APP"
