<div align="center">
  <img width="225" height="225" src="assets/brandmark-sway.gif" alt="Dòng">
  <h1><b>Dòng</b></h1>
  <p>Turn any video into a living desktop.<br>
  <a href="#features"><strong>Explore Dòng »</strong></a><br><br>
  <a href="#installation">Download for macOS</a> · <a href="https://dongisgood.coze.site/en">Official website ↗</a><br>
  <a href="i18n/en/AI_INSTALL_PROMPT.md"><strong>🤖 Let an AI install it for me (easiest) »</strong></a><br>
  <i>~ Version 3.37 · macOS 13 and later · Apple Silicon ~</i></p>
  <p>
    <b>English</b> · <a href="README.zh.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a><br>
    <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.ru.md">Русский</a>
  </p>
  <p><sub>Everything on this page — screenshots, linked docs and the prompt — is in English.</sub></p>
</div>

> [!NOTE]
>
> Dòng is a macOS live wallpaper tool written entirely in Swift and AppKit — about 8,500 lines of code, zero third-party frameworks.
> No Electron, no SwiftUI, not a single Pod.
> Paste a video link, or drag in a local video: it downloads, trims, and stitches it into a seamless loop, spread across your desktop.

<h6 align="center">
  <a href="i18n/en/AI_INSTALL_PROMPT.md"><img src="https://img.shields.io/badge/AI_Install-One_message-7B61FF?style=for-the-badge&labelColor=23272A" alt="AI one-message install"></a>
  <a href="https://github.com/zhang-1-kael/dong/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-5865F2?style=for-the-badge&labelColor=23272A" alt="GPL-3.0 License"></a>
  <a href="https://github.com/zhang-1-kael/dong/releases"><img src="https://img.shields.io/badge/version-3.37-57F287?style=for-the-badge&labelColor=23272A" alt="Version 3.37"></a>
  <a href="https://github.com/zhang-1-kael/dong"><img src="https://img.shields.io/badge/macOS-13%2B-23272A?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 13+"></a>
  <a href="https://github.com/zhang-1-kael/dong"><img src="https://img.shields.io/badge/Swift-F05138?style=for-the-badge&labelColor=23272A&logo=swift&logoColor=white" alt="Swift"></a>
  <a href="https://github.com/zhang-1-kael/dong/stargazers"><img src="https://img.shields.io/github/stars/zhang-1-kael/dong?style=for-the-badge&label=Stars&color=FEE75C&labelColor=23272A" alt="Stars"></a>
  <a href="https://github.com/zhang-1-kael/dong/issues"><img src="https://img.shields.io/github/issues/zhang-1-kael/dong?style=for-the-badge&label=Issues&color=ED4245&labelColor=23272A" alt="Issues"></a>
</h6>

---

## 🤖 Skip the manual install — send this to an AI

> [!IMPORTANT]
> **The easiest way to install Dòng: one message to an AI assistant.** Copy the block below into any assistant that can run commands on your Mac (WorkBuddy, Claude Code, Cursor, Codex, ...).
>
> It downloads the official DMG, verifies the SHA256, installs the app into Applications, and completes macOS's one-time first-open confirmation — from then on a double-click just works.
>
> No terminal window for you, no hunting through System Settings.
>
> The prompt is written in English on purpose, so every AI tool understands it. Its last line asks the AI to reply in English — so everything you read stays in English.

**① Copy this whole block**

```text
Please install Dòng, a macOS live wallpaper app, on this Mac.

Official repo: https://github.com/zhang-1-kael/dong
Official site: https://dongisgood.coze.site/en
AI installation manual: AI_INSTALL.md in that repo; one-shot installer: install.sh

Please read the manual and the script first, then follow the manual: download from the official stable endpoint, verify the SHA256 from the official release endpoint, install into /Applications, complete macOS's one-time first-open confirmation, launch the app, and report the result plus how to use it.
Use only the official hosts above; no sudo, no deleting or overwriting my files, no changes to system-wide security settings. If you have no terminal access, just give me the shortest copy-pasteable commands — do not claim you installed anything.
Reply to me in English.
```

**② Paste it into the AI and let it finish. Leave the app's own first-run "enable live wallpaper?" choice to me.**

📖 More: [full manual for AI agents](i18n/en/AI_INSTALL.md) · [bilingual prompt](i18n/en/AI_INSTALL_PROMPT.md) · [one-shot installer](install.sh) · [manual download](https://dongisgood.coze.site/en) · [All documents in English](i18n/en/GUIDE.md)

---

## Features

### 🖥 Desktop-grade live wallpaper

Hang a borderless window on WindowServer's desktop layer and loop it with `AVPlayerLayer`.
It doesn't touch the system wallpaper, needs no kernel extension, and requires no admin rights. Every display gets its own window and player; plug in or unplug a monitor and the windows rebuild automatically.

### 🔗 Link → wallpaper

Paste a Bilibili / YouTube link and the whole chain — download, transcode, fine-tune, import — runs automatically.
Douyin links are blocked by the platform's anti-scraping (see [Known Limitations](#known-limitations)); save the video locally first, then drag it in.

### ✂️ Auto-trimmed into a seamless loop

ffmpeg turns on-screen motion into a 1-D signal; jumps in that signal reveal where the real content starts.
Platform watermarks are located by whiteness, aspect ratio, and edge density, then patched with `delogo` interpolation.
A 0.4-second crossfade between ending and opening erases the loop point completely.

### 🎛 Menu bar glass panel

A resident menu bar app: current wallpaper, disk usage, online time, paste a link to import — every control hand-drawn in AppKit.

<p align="center">
  <img src="assets/i18n/en/panel.jpg" width="620" alt="Dòng menu bar panel">
</p>

### 📚 Waterfall wallpaper library

All wallpapers in a cover grid; hover to preview, click to switch. Volume, playback controls, current frame info — all in one screen.

<p align="center">
  <img src="assets/i18n/en/library.jpg" width="720" alt="Dòng wallpaper library">
</p>

### 🔒 Same frame on Lock Screen

Grab a frame and set it as the system wallpaper — moving when unlocked, the same still frame when locked.

---

## Usage

### Installation

#### Download Dòng

Download the latest `.dmg` from the [official site](https://dongisgood.coze.site/en), open it, and drag Dòng into "Applications".

The build is ad-hoc signed and not notarized. If macOS says it is damaged, run `xattr -dr com.apple.quarantine "/Applications/Dòng.app"` once, then open it again.

> [!TIP]
> **Let an AI do it for you.** Copy the prompt in [AI_INSTALL_PROMPT.md](i18n/en/AI_INSTALL_PROMPT.md) into any AI assistant — it downloads, verifies and installs Dòng in one command.
>
> Prefer to build it yourself? The steps below need only the Xcode command line tools.

#### Build from source

**The only dependency is the Xcode command line tools** — the full Xcode app is not required:

```bash
xcode-select --install   # skip if already installed
```

Clone and compile:

```bash
git clone https://github.com/zhang-1-kael/dong.git
cd dong
./build.sh
open build/VideoWallpaper.app
```

`build.sh` compiles the 10 `.swift` files into a single executable with one `swiftc` line, then assembles the `.app`.
The build is **ad-hoc signed** and only runs on your own machine; distributing it to others requires `sign-notarize.sh`.

##### Optional components

Neither of these is required for compiling — missing one only disables the matching feature:

| Component | Purpose | Install |
|---|---|---|
| **ffmpeg** | Transcoding, trimming head/tail, watermark removal, looping | `brew install ffmpeg`, or drop it in `~/.local/bin/ffmpeg` |
| **yt-dlp** | Link downloads | `brew install yt-dlp`, or drop the executable at `vendor/yt-dlp_macos` |

`build.sh` bundles any ffmpeg / yt-dlp it finds into the app package, so the app still works when copied to another machine.

> ⚠️ This repo does **not** include those two binaries, nor the built-in wallpaper assets — see [License & Assets](#license--assets).

##### Package as DMG

```bash
./package.sh                    # → dist/Dòng-<version>.dmg
VW_NO_PRESETS=1 ./package.sh    # without built-in wallpapers, the DMG is 360 MB smaller
```

### Import a wallpaper

1. Click the Dòng icon in the menu bar to open the panel;
2. Paste a Bilibili / YouTube link into the field (a full share text is fine — the app extracts the link itself), press Enter;
3. Or drag a local video file straight into the library window;
4. Wait for the pill at the bottom to finish — usually 20–60 seconds, and the wallpaper switches.

---

## Architecture

Four independent pipelines around a "menu bar app with no window":

```
┌──────────────────────────────────────────────────────────────┐
│                  Menu bar app (LSUIElement)                  │
│                                                              │
│  ① Display    Desktop windows ×N  ──►  AVPlayerLayer  ──►  AVPlayerLooper │
│  ② Pipeline   yt-dlp  ──►  ffmpeg transcode  ──►  Library   │
│  ③ UI         Menu bar panel / library window (all AppKit)  │
│  ④ System     LaunchAgent autostart · folder watch · stats  │
└──────────────────────────────────────────────────────────────┘
```

| File | Lines | Role |
|---|---:|---|
| `main.swift` | 1 833 | Display layer: desktop windows, multi-display, player lifecycle, auto-update wiring |
| `LibraryWindow.swift` | 2 631 | Library window, waterfall layout + hover preview + resident opacity slider |
| `Panel.swift` | 1 654 | Menu bar glass panel, jelly badge animation, all hand-drawn |
| `Transcoder.swift` | 672 | Probing, target size, head/tail detection, watermark removal, encoding |
| `Analytics.swift` | 534 | Anonymous stats + cloud service endpoint (can be disabled) |
| `Updater.swift` | 515 | Auto-update: check, download, SHA256 verify, replace in place |
| `Downloader.swift` | 202 | yt-dlp wrapper and progress parsing |
| `FrameHealth.swift` | 320 | Stall watchdog and playback probes, writes diag.log |
| `LockScreen.swift` | 70 | Grab a frame as the system wallpaper |
| `Presets.swift` | 47 | First-run import of built-in assets |

**The full technical write-up is in [technical guide](i18n/en/GUIDE.md)**: why the window must be 24pt larger than the screen,
why `--deep` signing is harmful, why loop audio mixing must seek in three segments,
why the hand-drawn panel covers the frosted glass — every pitfall documented, including what went wrong when it was hit.

---

## Command-line debugging

Don't want to wait for a full transcode every time you tweak an algorithm? There's a built-in headless entry point:

```bash
VideoWallpaper --detect a.mp4             # detection only: head/tail/watermark verdicts in 0.2 s
VideoWallpaper --try a.mp4 out.mp4        # one full transcode to a given file
VideoWallpaper --import a.mp4 b.mp4       # batch import, prints results
VideoWallpaper --link "https://…"         # link download + import
```

Debugging environment variables are in section 9 of `GUIDE.md` (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, etc.).

---

## Known Limitations

| Limitation | Reason |
|---|---|
| arm64 only | Build target and bundled ffmpeg are both Apple Silicon; a universal binary needs `lipo` |
| Lock screen is static | macOS doesn't open lock-screen video to third parties; a grabbed frame is the only approach that doesn't cross the line |
| Multi-display shares one video | One player per display, but from the same file |
| Updates fully automatic | Check → download → verify SHA256 → replace in place and relaunch on quit; falls back to opening the dmg only if installation fails |
| No Douyin links | Douyin enforces `a_bogus` anti-scraping and requires logged-in cookies; anonymous requests are rejected outright. Save the video in the app first, then drag the file in |
| Link downloads have legal boundaries | When scraping third-party content, only use material you have the rights to |

---

## Privacy

The app includes anonymous usage statistics. **Recorded**: a randomly generated install UUID, version number, OS version,
CPU architecture, language, event name.

**Not recorded**: file names, directory paths, link contents, wallpaper imagery, anything personally identifiable.
One click in Settings turns it off; turning it off immediately clears the local queue and stops all requests.

Stats are sent to the author's own server (the address hardcoded in `Analytics.swift`) and are **on by default**.
**If you fork this and ship your own build, change the default of `isEnabled` on line 50 of `Analytics.swift` to `false`** —
otherwise your users will report to the author's server. That step isn't polite, but it has to be said plainly.

---

## License & Assets

Code and documentation are licensed under **GPL-3.0** — see [LICENSE](LICENSE). If you distribute a modified binary, you must make the complete corresponding source available under the same license.

**Dual licensing:** To use Dòng in a closed-source commercial product, a separate commercial license is available — see [GUIDE.md](i18n/en/GUIDE.md), or open an issue to contact the author.

> **Historical note:** v3.31 and earlier were released under the MIT License. Those grants cannot be revoked; GPL-3.0 applies to later versions only.

**Not covered by the license:**

- The name "Dòng", `AppIcon.icns`, `BrandMark*.png` — brand marks; please don't use them for derivative names or icons.
- **Wallpaper assets**: `presets/` and `bili/` are in `.gitignore`; there are no video files in this repo.
  The copyright of any assets you bundle yourself is your responsibility.
- The `ffmpeg` and `yt-dlp` binaries are not in this repo. Note: official ffmpeg builds with
  `--enable-gpl --enable-nonfree` **cannot be redistributed**; for distribution, switch to an LGPL build
  and change the encoder from `libx264` to `h264_videotoolbox`.

---

## About

I'm a 16-year-old high school sophomore. Dòng started as a whim — I wondered
why a wallpaper couldn't be a moving video, so I wrote one in Swift from
scratch, just for myself.

Then my classmates saw it and wanted it too. So I thought, why not build it
properly and share it. Getting from "it runs on my machine" to "it runs on
yours" meant figuring out downloads, transcoding, code signing, auto-updates —
none of which I had needed to care about before. It was a lot of reading docs
and hitting walls, one small fix at a time.

Now it's open source, and I'm sharing it with everyone. I hope you enjoy using
it — and if you run into any problems or have ideas, please open an issue.
I read every one.

---

<p align="center">
  <sub>Built with swiftc. No frameworks were harmed.</sub>
</p>
