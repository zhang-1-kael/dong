#!/bin/zsh
# 打包成分发用的 DMG：App + 安装说明 + 「应用程序」快捷方式
set -e
cd "$(dirname "$0")"

./build.sh

VER=$(plutil -extract CFBundleShortVersionString raw Info.plist)
DIST="dist"
STAGE="$DIST/stage"

rm -rf "$STAGE" "$DIST/Dòng-$VER.dmg"
mkdir -p "$STAGE"

# App 包名直接用「Dòng.app」：Finder、Dock、关于本机、右键菜单看到的都是这个名字，
# 不依赖系统是否采用 CFBundleDisplayName。可执行文件名仍是 VideoWallpaper（改不了，
# 数据目录和锁屏注册都挂在它上面）。
cp -R "build/VideoWallpaper.app" "$STAGE/Dòng.app"
cp 安装说明.txt "$STAGE/安装说明.txt"
ln -s /Applications "$STAGE/应用程序"

# 挂载后的磁盘图标（品牌图标）：.VolumeIcon.icns + 自定义图标标记
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$STAGE/.VolumeIcon.icns"
  SetFile -a C "$STAGE" 2>/dev/null || true
fi

# 保险起见再签一次（拷动过的 bundle）
codesign --force --deep --sign - "$STAGE/Dòng.app" 2>/dev/null || true

echo "==> 生成 DMG"
# hdiutil 偶尔会莫名报「无此文件或目录」，重试一次基本都能过
if ! hdiutil create -volname "Dòng" -srcfolder "$STAGE" -ov -format UDZO \
      "$DIST/Dòng-$VER.dmg" >/dev/null 2>&1; then
  echo "   第一次失败，重试…"
  sleep 1
  hdiutil create -volname "Dòng" -srcfolder "$STAGE" -ov -format UDZO \
    "$DIST/Dòng-$VER.dmg" >/dev/null
fi

rm -rf "$STAGE"
ls -lh "$DIST/Dòng-$VER.dmg"
echo "==> 完成"
