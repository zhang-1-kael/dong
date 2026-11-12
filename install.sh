#!/bin/bash
# Dòng one-shot installer — https://github.com/zhang-1-kael/dong
#
# This script is meant to be READ before it is RUN. Do not `curl | bash` it.
# It downloads the official DMG, verifies its SHA256 against the official
# update endpoint, mounts it, copies one app bundle into /Applications,
# clears the macOS quarantine attribute and launches the app.
#
# It never uses sudo, never disables Gatekeeper system-wide, and never deletes
# user data (an existing app bundle is renamed to a timestamped backup).
#
# Usage:  bash install.sh [--dry-run] [--no-open]

set -euo pipefail

SITE="https://dongisgood.coze.site"
CHECK_URL="$SITE/api/update/check?version=0&channel=stable"
FALLBACK_DMG_URL="$SITE/api/download?channel=stable"
DEST_APP_NAME="Dòng.app"

die() { echo "!! $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Dòng installer — https://github.com/zhang-1-kael/dong

  bash install.sh              download, verify, install and launch
  bash install.sh --dry-run    print the plan without touching anything
  bash install.sh --no-open    install but do not launch the app
  DONG_INSTALL_DIR=/path       install into a custom directory (for testing)

The DMG is ad-hoc signed and not notarized. The script clears macOS's
com.apple.quarantine attribute on the installed app so it can open normally.
EOF
}

DRY_RUN=0
NO_OPEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-open) NO_OPEN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

[ "$(uname -s)" = "Darwin" ] || die "Dòng only runs on macOS."

ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ]; then
  die "The official DMG is arm64 (Apple Silicon) only; this machine reports '$ARCH'.
   On an Intel Mac, build from source instead:
     xcode-select --install && git clone https://github.com/zhang-1-kael/dong.git && cd dong && ./build.sh"
fi

MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 13 ] || die "Dòng needs macOS 13 or later (this is macOS $MAJOR)."

# Ask the official endpoint for version / size / checksum / current download URL.
# The object-storage URL behind it is signed and expires, so NEVER hardcode it.
echo "==> Checking the official release info"
META="$(curl -fsSL --max-time 25 "$CHECK_URL" 2>/dev/null || true)"
SHA_EXPECTED="$(printf '%s' "$META" | sed -n 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
SIZE_EXPECTED="$(printf '%s' "$META" | sed -n 's/.*"file_size"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -n 1 || true)"
VERSION="$(printf '%s' "$META" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
DMG_URL="$(printf '%s' "$META" | sed -n 's/.*"download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
[ -n "$DMG_URL" ] || DMG_URL="$FALLBACK_DMG_URL"
[ -n "$VERSION" ] || VERSION="latest"

# DONG_INSTALL_DIR is an optional override (useful for CI / smoke tests).
if [ -n "${DONG_INSTALL_DIR:-}" ]; then
  DEST_BASE="$DONG_INSTALL_DIR"
elif [ -w /Applications ]; then
  DEST_BASE="/Applications"
else
  DEST_BASE="$HOME/Applications"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "==> Dry run — nothing was downloaded or changed."
  echo "    Version     $VERSION"
  echo "    From        $DMG_URL"
  echo "    Verify      SHA256 ${SHA_EXPECTED:-unavailable (will warn and continue)}"
  echo "    Expected    ${SIZE_EXPECTED:-unknown} bytes"
  echo "    Install to  $DEST_BASE/$DEST_APP_NAME"
  echo "    Then        clear com.apple.quarantine, launch the app"
  echo "    Never       sudo, curl|bash, deleting or overwriting user files"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dong-install.XXXXXX")"
DMG="$TMP/Dong.dmg"
MNT="$TMP/mnt"

cleanup() {
  if [ -d "$MNT" ]; then
    hdiutil detach "$MNT" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "==> Downloading the official DMG (~63 MB)"
curl -fL --retry 2 --max-time 600 -sS -o "$DMG" "$DMG_URL" \
  || die "Download failed. Check your network, or open $SITE/en and download by hand."

ACTUAL_SIZE="$(stat -f%z "$DMG")"
ACTUAL_SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

if [ -n "$SHA_EXPECTED" ]; then
  [ "$ACTUAL_SHA" = "$SHA_EXPECTED" ] \
    || die "SHA256 mismatch — the file is not the official build, giving up.
   expected $SHA_EXPECTED
   got      $ACTUAL_SHA"
  echo "==> SHA256 verified: $ACTUAL_SHA"
else
  echo "!! The release endpoint did not return a sha256; skipping checksum verification."
  echo "   Downloaded: $ACTUAL_SIZE bytes, SHA256 $ACTUAL_SHA"
fi

if [ -n "$SIZE_EXPECTED" ] && [ "$ACTUAL_SIZE" != "$SIZE_EXPECTED" ]; then
  die "File size mismatch (expected $SIZE_EXPECTED, got $ACTUAL_SIZE). Giving up."
fi

echo "==> Mounting the DMG"
mkdir -p "$MNT"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MNT" >/dev/null \
  || die "Could not mount the DMG — it may be corrupt."

# Never hardcode "Dòng.app": HFS+/APFS may store the accented name decomposed.
APP_SRC=""
for candidate in "$MNT"/*.app; do
  if [ -d "$candidate" ]; then
    APP_SRC="$candidate"
    break
  fi
done
[ -n "$APP_SRC" ] || die "No .app bundle found inside the DMG."

mkdir -p "$DEST_BASE"
DEST="$DEST_BASE/$(basename "$APP_SRC")"

if [ -d "$DEST" ]; then
  BACKUP="$DEST.previous-$(date +%Y%m%d-%H%M%S)"
  mv "$DEST" "$BACKUP"
  echo "==> Existing app kept as a backup: $BACKUP"
fi

echo "==> Installing into $DEST"
ditto "$APP_SRC" "$DEST"

# Ad-hoc signed, not notarized: Gatekeeper would otherwise say "app is damaged".
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
echo "==> Cleared the macOS quarantine attribute"

if [ "$NO_OPEN" -eq 0 ]; then
  open -a "$DEST" || echo "!! Could not launch automatically — double-click $DEST to open it."
fi

echo
echo "==> Done: Dòng $VERSION is installed at $DEST"
echo "    Look for the jelly icon in the menu bar, click it, and paste a"
echo "    Bilibili / YouTube link (or drag a local video in) to make a wallpaper."
echo "    If macOS still says 'Dòng is damaged', run:"
echo "      xattr -dr com.apple.quarantine \"$DEST\""
