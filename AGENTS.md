# AGENTS.md

Dòng — a macOS live wallpaper app written in pure Swift + AppKit. It is a
menu-bar (`LSUIElement`) app: no Dock icon, no window on launch.
Repo: <https://github.com/zhang-1-kael/dong> · Site: <https://dongisgood.coze.site/en>

## If the user asks to install / download / set up Dòng

**Read `AI_INSTALL.md` first and follow it.** Short version:

- Official stable DMG endpoint: `https://dongisgood.coze.site/api/download?channel=stable`
  (release metadata / SHA256: `/api/update/check?version=0&channel=stable`).
- **GitHub Releases hosts v3.31** (`https://github.com/zhang-1-kael/dong/releases/tag/v3.31`):
  `Dong-3.31.dmg` + full bundle zip. Fine as a fallback if the site is down — verify SHA256.
  Never invent asset URLs for versions without a release.
- The DMG is ad-hoc signed and **not notarized**; clear `com.apple.quarantine` on the
  installed app. Never disable Gatekeeper system-wide.
- One-shot installer: `install.sh` — read it before running, never `curl | bash`.
- A prompt the user can paste into any AI assistant: `AI_INSTALL_PROMPT.md`.
- Never use `sudo`, never overwrite/delete user files, stop on checksum mismatch.

## Build & test

- `./build.sh` — compiles the 10 `.swift` files with one `swiftc` call into
  `build/VideoWallpaper.app` (needs the Xcode command line tools).
- `./package.sh` — builds the DMG (refuses to run if `Info.plist` has no `ApiBaseURL`).
- `ffmpeg` and `yt-dlp` are optional; missing ones only disable their features.
- CI: `.github/workflows/build.yml`. There is no separate test framework.

## Conventions

- Code comments and the deep technical write-up (`技术原理.md`) are in Chinese.
- `README.md` is the English default; nine languages link from the header bar.
  Keep them in sync when installation or version info changes.
- **Language switches the whole page, not just the prose.** Every README links
  only into `i18n/<lang>/` (`AI_INSTALL_PROMPT.md`, `AI_INSTALL.md`,
  `GUIDE.md`) and `assets/i18n/<lang>/` (`panel.jpg`, `library.jpg`). Regenerate
  with `tools/gen_i18n_docs.py`, `tools/gen_i18n_readme.py`, and
  `uv run --with pillow python tools/gen_i18n_images.py`.
- The copyable prompt in every README is English **on purpose** — any AI tool
  can read it — and ends with `Reply to me in <language>.` Always answer in that
  language. If no language is named, detect the user's system language
  (`defaults read -g AppleLanguages`) and reply in it; fall back to English for
  unsupported languages. Localized alternative prompts are frozen in
  `tools/i18n_local_prompts.json`; this file and the root `AI_INSTALL.md` stay
  in English because they are machine-facing.
- AI-assisted contributions: disclose and review line by line (`AI_POLICY.md`).
- Dual licensed: GPL-3.0 (`LICENSE`) or commercial (`COMMERCIAL.md`).
