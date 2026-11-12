# Dòng — Technical & project guide

> Everything else about the project, in English.

## Architecture

Four independent pipelines: desktop-layer windows with `AVPlayerLayer`, yt-dlp + ffmpeg transcoding, a hand-drawn AppKit menu bar panel and library, and LaunchAgent autostart / folder watching / anonymous stats.

## Key implementation details

- Each window is 24 pt larger than the screen to hide rounded corners and desktop-switch edges.
- `--deep` code signing breaks nested resource signatures — don't use it.
- Loop audio is mixed with three separate seeks; a single pass leaves a click.
- The menu bar panel is drawn by hand so it covers the system frosted glass.

## Command-line debugging

```bash
VideoWallpaper --detect a.mp4
VideoWallpaper --try a.mp4 out.mp4
VideoWallpaper --import a.mp4 b.mp4
VideoWallpaper --link "https://…" 
```

Environment variables (`VW_PANEL_SHOT`, `VW_GEOM`, `VW_DUMP_MENU`, …) are listed in section 9 of the Chinese original.

## License & commercial use

Code and docs are **GPL-3.0** — the legally binding text is the English [LICENSE](../../LICENSE). A separate commercial licence is available for closed-source products: [COMMERCIAL.md](../../COMMERCIAL.md).

## Brand & assets

The name "Dòng", `AppIcon.icns` and `BrandMark*.png` are brand marks. `presets/` and `bili/` (wallpaper videos) are not in this repo, and neither are the ffmpeg / yt-dlp binaries.

## Contributing & AI policy

Issues and PRs are welcome; templates live in `.github/` and CI builds the app. AI-assisted contributions must be disclosed and reviewed line by line — [AI_POLICY.md](../../AI_POLICY.md).

## Privacy

Anonymous usage stats are on by default and can be switched off in Settings. If you fork the project, change the default of `isEnabled` in `Analytics.swift` to `false`.

Full Chinese technical write-up: [技术原理.md](../../技术原理.md).

---

## All documents in English

- [README.md](../../README.md)
- [AI_INSTALL_PROMPT.md](AI_INSTALL_PROMPT.md)
- [AI_INSTALL.md](AI_INSTALL.md)
- [GUIDE.md](GUIDE.md)
