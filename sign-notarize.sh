#!/bin/zsh
# 正式签名 + 公证 + 装订（Gatekeeper 放行的完整链路）
#
# 用法：
#   0) 先自检，看还缺什么：
#        ./sign-notarize.sh --check
#   1) 把开发者证书装进钥匙串（developer.apple.com → Certificates → Developer ID Application）
#   2) 存一次公证凭据（只需一次，会进钥匙串）：
#        xcrun notarytool store-credentials dong-notary \
#          --apple-id "你的 Apple ID" \
#          --team-id  "你的 Team ID（10 位，开发者后台右上角）" \
#          --password "App 专用密码（appleid.apple.com 里生成，不是登录密码）"
#   3) 签名 + 公证：
#        VW_SIGN_ID="Developer ID Application: 你的名字 (TEAMID)" ./sign-notarize.sh
#
# 可选环境变量：
#   VW_SIGN_ID          证书名，不填会列出本机可用证书
#   VW_NOTARY_PROFILE   钥匙串里的公证 profile 名，默认 dong-notary
#   VW_APP              要签的 App，默认 build/VideoWallpaper.app
#   VW_SKIP_DMG_NOTARY  设为 1 时跳过第二轮（DMG）公证，只公证并装订 App
set -euo pipefail
cd "$(dirname "$0")"

APP="${VW_APP:-build/VideoWallpaper.app}"
IDENTITY="${VW_SIGN_ID:-}"
PROFILE="${VW_NOTARY_PROFILE:-dong-notary}"
DIST="dist"
VER=$(plutil -extract CFBundleShortVersionString raw Info.plist)
DMG="$DIST/Dòng-$VER.dmg"
BIN="$APP/Contents/Resources/bin"

die() { print -u2 "✗ $1"; exit 1 }

ok()   { print "  ✓ $1" }
bad()  { print "  ✗ $1" }
warn() { print "  ! $1" }

# ================= 自检模式 =================
if [[ "${1:-}" == "--check" ]]; then
  print "签名环境自检"
  print ""

  print "[1] 工具链"
  if command -v xcrun >/dev/null; then ok "xcrun 可用（$(xcode-select -p)）"; else bad "缺 Xcode Command Line Tools"; fi
  if xcrun --find notarytool >/dev/null 2>&1; then ok "notarytool 可用（$(xcrun notarytool --version 2>&1 | head -1)）"; else bad "notarytool 不可用，需要 Xcode 13+ 或对应 CLT"; fi
  command -v codesign >/dev/null && ok "codesign 可用" || bad "codesign 缺失"
  print ""

  print "[2] 签名证书"
  local_id=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 || true)
  if [[ -n "$local_id" ]]; then
    ok "找到 Developer ID Application："
    print "${local_id}"
  else
    bad "钥匙串里没有 Developer ID Application 证书"
    print "     去 developer.apple.com → Certificates → + → Developer ID Application"
    print "     先在本机生成 CSR：钥匙串访问 → 证书助理 → 从证书颁发机构请求证书"
  fi
  print ""

  print "[3] 公证凭据（profile: $PROFILE）"
  if msg=$(xcrun notarytool history --keychain-profile "$PROFILE" 2>&1); then
    ok "凭据有效"
  else
    if print "$msg" | grep -qi "No Keychain password item"; then
      bad "还没存凭据。执行："
      print "     xcrun notarytool store-credentials $PROFILE --apple-id <AppleID> --team-id <TEAMID> --password <App专用密码>"
    else
      bad "凭据校验失败：$(print "$msg" | head -3)"
    fi
  fi
  print ""

  print "[4] 待签产物"
  if [[ -d "$APP" ]]; then
    ok "找到 $APP（$(du -sh "$APP" | cut -f1)）"
    arch=$(lipo -archs "$APP/Contents/MacOS/VideoWallpaper" 2>/dev/null || echo "?")
    if [[ "$arch" == *"x86_64"* && "$arch" == *"arm64"* ]]; then
      ok "主程序架构：$arch（通用二进制）"
    else
      warn "主程序架构：$arch —— Intel Mac 打不开，需要重新编译成 universal"
    fi
    [[ -f "$APP/Contents/Resources/AppIcon.icns" ]] && ok "图标已装" || warn "没有 AppIcon.icns，Finder 里是空白方块"
    for b in "$BIN"/*(N); do
      [[ -f "$b" ]] || continue
      a=$(lipo -archs "$b" 2>/dev/null || echo "?")
      ok "内嵌 $(basename "$b")（$(du -h "$b" | cut -f1)，$a）"
    done
  else
    bad "找不到 $APP，先跑 ./build.sh"
  fi
  print ""

  print "[5] 可分发性（公证不查，但法务会查）"
  if [[ -x "$BIN/ffmpeg" ]] && "$BIN/ffmpeg" -hide_banner -L 2>&1 | grep -q "nonfree"; then
    warn "内嵌 ffmpeg 带 nonfree 组件：官方声明不可再分发（换 LGPL 构建才能合法发）"
  else
    ok "ffmpeg 许可未发现问题"
  fi
  if [[ -d "$APP/Contents/Resources/presets" ]]; then
    n=$(ls -1 "$APP/Contents/Resources/presets" 2>/dev/null | wc -l | tr -d ' ')
    warn "内置 $n 个预设壁纸（$(du -sh "$APP/Contents/Resources/presets" | cut -f1)），确认素材版权"
  fi
  print ""

  print "自检结束。缺项补齐后执行："
  print "  VW_SIGN_ID=\"Developer ID Application: 你的名字 (TEAMID)\" ./sign-notarize.sh"
  exit 0
fi

# ================= 0. 前置检查 =================
[[ -d "$APP" ]] || die "找不到 $APP，先跑 ./build.sh"
command -v xcrun >/dev/null || die "需要 Xcode Command Line Tools"

if [[ -z "$IDENTITY" ]]; then
  print "本机可用的签名证书："
  security find-identity -v -p codesigning
  print ""
  die "请设置 VW_SIGN_ID=\"Developer ID Application: ... (TEAMID)\" 再运行（或先跑 ./sign-notarize.sh --check）"
fi

security find-identity -v -p codesigning | grep -qF "$IDENTITY" \
  || die "钥匙串里找不到这张证书：$IDENTITY"

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || {
  print -u2 "✗ 公证凭据「$PROFILE」不可用。先执行："
  print -u2 "  xcrun notarytool store-credentials $PROFILE --apple-id <AppleID> --team-id <TEAMID> --password <App专用密码>"
  exit 1
}

# 公证 + 装订；$1 提交对象，$2 要装订的对象（默认同 $1）
notarize() {
  local submit="$1" staple_target="${2:-$1}" out rc sid
  print "==> 提交公证：$(basename "$submit")（通常 1–5 分钟，偶尔更久）"
  set +e
  out=$(xcrun notarytool submit "$submit" --keychain-profile "$PROFILE" \
        --wait --timeout "${VW_NOTARY_TIMEOUT:-45m}" 2>&1)
  rc=$?
  set -e
  print "$out" | tail -6

  if [[ $rc -ne 0 ]] || ! print "$out" | grep -q "status: Accepted"; then
    sid=$(print "$out" | awk '/  id:/{print $2; exit}')
    print -u2 "✗ 公证未通过：$(basename "$submit")"
    [[ -n "${sid:-}" ]] && print -u2 "  查日志：xcrun notarytool log $sid --keychain-profile $PROFILE"
    return 1
  fi
  print "==> 装订票据：$(basename "$staple_target")"
  xcrun stapler staple "$staple_target"
}

# ================= 1. 签内置的第三方可执行文件（必须先里后外） =================
print "==> 签名内置二进制"
if [[ -d "$BIN" ]]; then
  # yt-dlp：PyInstaller 单文件，运行时解压 .so，必须开 disable-library-validation
  if [[ -f "$BIN/yt-dlp" ]]; then
    codesign --force --timestamp --options runtime \
      --entitlements entitlements-ytdlp.plist \
      --sign "$IDENTITY" "$BIN/yt-dlp"
    print "    yt-dlp ✓"
  fi
  # ffmpeg：静态二进制，不需要额外 entitlements
  if [[ -f "$BIN/ffmpeg" ]]; then
    codesign --force --timestamp --options runtime \
      --sign "$IDENTITY" "$BIN/ffmpeg"
    print "    ffmpeg ✓"
  fi
fi

# 其他可能存在的 dylib / framework（未来加的库也要按这个顺序签）
if [[ -d "$APP/Contents/Frameworks" ]]; then
  find "$APP/Contents/Frameworks" -type f \( -name "*.dylib" -o -perm +111 \) -print0 \
    | while IFS= read -r -d '' lib; do
        codesign --force --timestamp --options runtime --sign "$IDENTITY" "$lib"
      done
  print "    Frameworks ✓"
fi

# ================= 2. 签 App 本体（不要用 --deep） =================
# --deep 会把 entitlements 灌给嵌套代码，公证常因此失败；这里逐个签才是对的。
print "==> 签名 App 本体"
codesign --force --timestamp --options runtime \
  --entitlements entitlements.plist \
  --sign "$IDENTITY" "$APP"

print "==> 校验签名结构"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier|flags|Authority" || true

# ================= 3. 第一轮公证：App 本体 =================
# 必须先公证并装订 App，再打 DMG。反过来（先打 DMG 再公证）
# 会导致 DMG 里那个 App 没装订票据，用户断网首次打开仍然被拦。
print "==> 打包 App 用于公证"
ZIP="$DIST/Dòng-$VER.zip"
mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

notarize "$ZIP" "$APP"
rm -f "$ZIP"

# ================= 4. 打包 DMG 并签名 =================
print "==> 打包 DMG"
STAGE="$DIST/stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Dòng.app"          # ditto 保留签名与装订票据，cp -R 会破坏签名
[[ -f 安装说明.txt ]] && cp 安装说明.txt "$STAGE/"
ln -s /Applications "$STAGE/应用程序"

hdiutil create -volname "Dòng" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
print "    $(ls -lh "$DMG" | awk '{print $5}') $DMG ✓"

# ================= 5. 第二轮公证：DMG =================
if [[ "${VW_SKIP_DMG_NOTARY:-0}" == "1" ]]; then
  warn "已跳过 DMG 公证（VW_SKIP_DMG_NOTARY=1），离线首次打开依赖 App 内的票据"
else
  notarize "$DMG"
fi

# ================= 6. 终检：模拟用户双击 =================
print "==> Gatekeeper 终检"
spctl -a -t open --context context:primary-signature -vvv "$DMG" || die "DMG 未被 Gatekeeper 接受"
spctl -a -vvv -t exec "$APP" || die "App 未被 Gatekeeper 接受"
codesign --verify --deep --strict --verbose=2 "$APP" || die "签名结构校验失败"

print ""
print "✓ 完成：$DMG"
print "  现在任何一台 Mac 双击都能直接装，不会再出现「无法验证开发者」。"
