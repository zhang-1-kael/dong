# Installing Dòng with an AI assistant

> **This file is written for AI agents, not humans.** If an AI has been asked to
> download or install Dòng on someone's Mac, follow this file. Human-readable
> installation instructions are in `README.md`.

## Facts you must not get wrong

| | |
|---|---|
| Official repo | `https://github.com/zhang-1-kael/dong` |
| Official site | `https://dongisgood.coze.site/en` (English), `/` (Chinese) |
| Stable DMG endpoint | `https://dongisgood.coze.site/api/download?channel=stable` |
| GitHub Releases (fallback) | `https://github.com/zhang-1-kael/dong/releases/tag/v3.31` → `Dong-3.31.dmg` + full release bundle zip |
| Release metadata | `https://dongisgood.coze.site/api/update/check?version=0&channel=stable` → JSON with `version`, `file_size`, `sha256`, `download_url` |
| Installer script | `https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh` |
| Handy prompt to share | `AI_INSTALL_PROMPT.md` |

- **GitHub Releases now hosts v3.31** — `https://github.com/zhang-1-kael/dong/releases/tag/v3.31`,
  with `Dong-3.31.dmg` and a full release bundle zip (`latest.json` + checksum info).
  Use it as a fallback when the official site is unavailable; always verify the SHA256
  from the release notes or `latest.json`. The primary channel is still the stable endpoint below.
  Do not invent asset URLs for versions that have no release.
- **Never hardcode the object-storage URL.** `/api/download` 302-redirects to a
  signed URL that expires. Always start from the stable endpoint above.
- **The DMG is ad-hoc signed and NOT notarized.** Gatekeeper will say the app is
  damaged / from an unidentified developer. Clearing `com.apple.quarantine` on the
  installed app is expected, required, and safe. Do **not** disable Gatekeeper
  system-wide (`spctl --master-disable` is forbidden).
- arm64 (Apple Silicon) and macOS 13+ only. Intel Macs must build from source.
- Current build: 3.31, 65,514,975 bytes, SHA256
  `c4b8f4476af35210cbc072c1c3c5208190d6dcf909cc5aed93c8ddb84a7da8df`.
  These values change with each release — always read the live metadata endpoint.

## Language of your reply

The prompt that reaches you ends with `Reply to me in <language>.` **Answer in
that language.** The person reads only their own language: their README, their
screenshots, and their own copies of the prompt, the installation manual and
the project guide all live in `i18n/<lang>/`. This file and `AGENTS.md` stay in
English because they are read by AI agents, not humans. `install.sh` prints its
log in English too — summarise the result for the user in their language.

## Path A — you have a shell (preferred)

1. Fetch the installer **and read it before running it**. Never `curl | bash`.

   ```bash
   curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
   cat /tmp/dong-install.sh
   ```

2. Tell the user, in plain language, what it does: download ~63 MB from the
   official site, verify SHA256 against the official endpoint, mount the DMG,
   copy one app bundle into `/Applications`, clear quarantine, launch. No sudo,
   no deletion of user data (an existing app is renamed to a timestamped backup).
   If the user already asked you to install, proceed; otherwise ask once.

3. Preview, then run:

   ```bash
   bash /tmp/dong-install.sh --dry-run
   bash /tmp/dong-install.sh
   ```

4. Report the result and the first-use steps (see "Verify" below).

If the script cannot be fetched or fails, do the equivalent by hand:

```bash
curl -fL -o ~/Downloads/Dong.dmg "https://dongisgood.coze.site/api/download?channel=stable"
shasum -a 256 ~/Downloads/Dong.dmg   # compare with the sha256 from the metadata endpoint
open ~/Downloads/Dong.dmg
# drag Dòng.app into Applications in the Finder window that opens, then:
xattr -dr com.apple.quarantine "/Applications/Dòng.app"
open -a "Dòng"
```

## Path B — you have no shell (chat-only assistants)

Do not pretend you installed anything. Give the user these three lines and say
they can also paste the prompt from `AI_INSTALL_PROMPT.md` into an assistant that
*does* have terminal access:

```bash
curl -fsSL https://raw.githubusercontent.com/zhang-1-kael/dong/main/install.sh -o /tmp/dong-install.sh
cat /tmp/dong-install.sh
bash /tmp/dong-install.sh
```

## Path C — fallback: build from source

Only when the user wants the source, is on an Intel Mac, or the site is down.
Requires the Xcode command line tools; the full Xcode app is not needed.

```bash
xcode-select --install   # skip if already installed
git clone https://github.com/zhang-1-kael/dong.git
cd dong
./build.sh
open build/VideoWallpaper.app
```

`ffmpeg` and `yt-dlp` are optional; without them only the matching features are
disabled. `build.sh` ad-hoc signs the result, so it only runs on the machine that
built it.

## Safety rules

- Only use these hosts: `dongisgood.coze.site`, `github.com/zhang-1-kael/dong`,
  `raw.githubusercontent.com`. Never fetch a DMG from a mirror, a forum, or a URL
  you guessed.
- Verify the SHA256 when the metadata endpoint provides one. On mismatch, **stop**
  and tell the user; do not install the file.
- No `sudo`, no `curl | bash`, no `rm -rf` outside the installer's own temp dir,
  no modifying system security settings, no overwriting files outside the app bundle.
- Explain each step before running it. On failure, give a human-readable reason and
  the exact manual alternative — never just print a stack trace.
- The app is a menu-bar (`LSUIElement`) app: there is no Dock icon and no window
  on launch. That is normal.

## Verify

- `/Applications/Dòng.app` exists and `xattr -l` shows no `com.apple.quarantine`.
- The jelly icon appears in the macOS menu bar. Click it, paste a Bilibili /
  YouTube link, press Enter — a wallpaper appears after 20–60 seconds.
- If macOS still says "Dòng is damaged and can't be opened":
  `xattr -dr com.apple.quarantine "/Applications/Dòng.app"`, then right-click → Open.

## License note

The project is dual-licensed (GPL-3.0 or a commercial license). Installing and
using it is free; redistribution terms are in `LICENSE` and `COMMERCIAL.md`.
